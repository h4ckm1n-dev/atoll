import Dispatch
import Darwin
import Foundation

public final class BridgeServer: @unchecked Sendable {
    private struct ClientConnection {
        let id: UUID
        let fileDescriptor: Int32
        let readSource: DispatchSourceRead
        var role: BridgeClientRole?
        var buffer = Data()
        /// Per-client token bucket used to drop hostile/runaway frames
        /// without tearing the connection down (see M1 audit finding).
        var rateBucket = TokenBucket()
        /// True once the client has sent a valid `BridgeHello` frame
        /// (optional — see protocol-version handshake bonus). Used to
        /// detect protocol-version mismatches without breaking older
        /// hooks that never send a hello.
        var didReceiveHello = false
    }

    private struct PendingApproval {
        let clientID: UUID
    }

    private struct PendingClaudeToolContext {
        let toolUseID: String?
        let toolName: String?
        let toolInput: ClaudeHookJSONValue?
    }

    private struct PendingClaudeInteraction {
        enum Kind {
            case permission(ClaudeHookPayload)
            case question(ClaudeHookPayload, QuestionPrompt)
        }

        let clientID: UUID
        let kind: Kind
    }

    private struct PendingOpenCodeInteraction {
        enum Kind {
            case permission(OpenCodeHookPayload)
            case question(OpenCodeHookPayload)
        }

        let clientID: UUID
        let kind: Kind
    }

    private struct Listener {
        let fileDescriptor: Int32
        let acceptSource: DispatchSourceRead
        let socketURL: URL
    }

    private struct PendingCursorInteraction {
        let clientID: UUID
        let payload: CursorHookPayload
    }

    private let socketURL: URL
    private let queue = DispatchQueue(label: "app.atoll.bridge.server")
    private let queueKey = DispatchSpecificKey<Void>()

    /// Pluggable peer-credential check. Defaults to same-EUID enforcement.
    /// Tests inject an alternative to verify rejection paths without needing
    /// a real cross-UID socket peer.
    private let peerTrustCheck: @Sendable (Int32) -> Bool

    private var listeners: [Listener] = []
    private var clients: [UUID: ClientConnection] = [:]
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var pendingApprovalOrder: [String] = []
    private var pendingClaudeToolContexts: [String: PendingClaudeToolContext] = [:]
    private var pendingClaudeInteractions: [String: PendingClaudeInteraction] = [:]
    private var pendingClaudeInteractionOrder: [String] = []
    private var pendingOpenCodeInteractions: [String: PendingOpenCodeInteraction] = [:]
    private var pendingOpenCodeInteractionOrder: [String] = []
    private var pendingCursorInteractions: [String: PendingCursorInteraction] = [:]
    private var pendingCursorInteractionOrder: [String] = []
    /// Caches Agent tool description from preToolUse for use by the next subagentStart.
    private var pendingAgentDescriptions: [String: String] = [:]
    /// Maps toolUseID → temporary task ID for TaskCreate, so postToolUse can update with real ID.
    private var pendingTaskCreations: [String: String] = [:]
    private var stateSnapshot = SessionState()
    /// Local working state: tracks sessions emitted by this server between
    /// snapshot pushes from AppModel. This is NOT a duplicate of AppModel's
    /// state — it only contains sessions created via bridge hooks and is
    /// overwritten whenever AppModel pushes a fresh snapshot.
    private var localState = SessionState()

    public init(
        socketURL: URL = BridgeSocketLocation.defaultURL,
        peerTrustCheck: @Sendable @escaping (Int32) -> Bool = BridgeSecurity.defaultPeerTrustCheck
    ) {
        self.socketURL = socketURL
        self.peerTrustCheck = peerTrustCheck
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard listeners.isEmpty else {
            return
        }

        // Primary (and only) socket in a stable, user-owned directory.
        // The legacy /tmp listener was removed in the 2026-05-07 hardening
        // because /tmp is world-readable: any local user could enumerate
        // and connect to it. Hooks built before the rename will reconnect
        // to the new path on next invocation; reverse-compat is intentionally
        // dropped in favor of confidentiality.
        let primaryListener = try bindListener(at: socketURL)
        listeners.append(primaryListener)
    }

    private func bindListener(at url: URL) throws -> Listener {
        let parentURL = url.deletingLastPathComponent()
        // Owner-only parent directory so other local users cannot stat or
        // enumerate the socket path. createDirectory with explicit
        // posixPermissions does NOT chmod existing dirs, so we also chmod
        // the leaf afterwards.
        try FileManager.default.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = chmod(parentURL.path, 0o700)
        try? FileManager.default.removeItem(at: url)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd != -1 else {
            throw BridgeTransportError.systemCallFailed("socket", errno)
        }

        do {
            var reuseAddress: Int32 = 1
            guard setsockopt(
                fd, SOL_SOCKET, SO_REUSEADDR,
                &reuseAddress, socklen_t(MemoryLayout<Int32>.size)
            ) != -1 else {
                throw BridgeTransportError.systemCallFailed("setsockopt", errno)
            }

            // Tighten umask around bind() so the socket inode is created
            // with mode 0600 from birth, closing the brief window where
            // it would otherwise be world-readable. We then chmod
            // unconditionally — belt-and-suspenders if umask was honored
            // at all, and a no-op if so.
            let previousUmask = umask(0o077)
            defer { _ = umask(previousUmask) }

            try withUnixSocketAddress(path: url.path) { address, length in
                guard bind(fd, address, length) != -1 else {
                    throw BridgeTransportError.systemCallFailed("bind", errno)
                }
            }
            _ = chmod(url.path, 0o600)

            guard listen(fd, 16) != -1 else {
                throw BridgeTransportError.systemCallFailed("listen", errno)
            }

            try makeSocketNonBlocking(fd)
        } catch {
            close(fd)
            try? FileManager.default.removeItem(at: url)
            throw error
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingClients(on: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()

        return Listener(fileDescriptor: fd, acceptSource: source, socketURL: url)
    }

    public func stop() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopLocked()
        } else {
            queue.sync {
                stopLocked()
            }
        }
    }

    /// Pushes the authoritative session state from AppModel so BridgeServer
    /// can read session data without maintaining its own copy.
    public func updateStateSnapshot(_ snapshot: SessionState) {
        queue.async { [self] in
            stateSnapshot = snapshot
            localState = snapshot
        }
    }

    private func stopLocked() {
        pendingApprovals.removeAll()
        pendingApprovalOrder.removeAll()
        pendingClaudeInteractions.removeAll()
        pendingClaudeInteractionOrder.removeAll()
        pendingClaudeToolContexts.removeAll()
        pendingOpenCodeInteractions.removeAll()
        pendingOpenCodeInteractionOrder.removeAll()
        pendingCursorInteractions.removeAll()
        pendingCursorInteractionOrder.removeAll()

        let activeConnections = Array(clients.values)
        activeConnections.forEach { $0.readSource.cancel() }
        clients.removeAll()

        for listener in listeners {
            listener.acceptSource.cancel()
        }
        listeners.removeAll()

        // Do NOT delete socket files here.  start() / bindListener() already
        // clean up stale sockets before binding.  Deleting in stop() causes
        // a race when the old process is being terminated while a new process
        // has already created its socket at the same path.
    }

    private func acceptPendingClients(on listeningFileDescriptor: Int32) {
        while true {
            let clientFileDescriptor = accept(listeningFileDescriptor, nil, nil)

            if clientFileDescriptor == -1 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                }

                return
            }

            // H1: reject any peer whose effective UID does not match this
            // process. getpeereid is the kernel-authoritative source — it
            // cannot be spoofed by a malicious client.
            guard peerTrustCheck(clientFileDescriptor) else {
                BridgeServer.logSecurityEvent("bridge: rejected peer (uid mismatch)")
                close(clientFileDescriptor)
                continue
            }

            // H2: hard cap on concurrent client connections to prevent
            // fd exhaustion / memory growth from a flooding peer.
            guard clients.count < BridgeSecurity.maxConcurrentClients else {
                BridgeServer.logSecurityEvent(
                    "bridge: refusing client (max \(BridgeSecurity.maxConcurrentClients) concurrent)"
                )
                close(clientFileDescriptor)
                continue
            }

            do {
                try disableSocketSigPipe(clientFileDescriptor)
                try makeSocketNonBlocking(clientFileDescriptor)
                configureClient(fileDescriptor: clientFileDescriptor)
            } catch {
                close(clientFileDescriptor)
            }
        }
    }

    /// Single chokepoint for security log lines so tests / future audits
    /// can grep one prefix.
    static func logSecurityEvent(_ message: @autoclosure () -> String) {
        // FileHandle.standardError is async-safe; print() routes through
        // stdout which the app also wires elsewhere. Keep this dependency
        // light — no os.Logger import.
        let line = "[atoll.security] " + message() + "\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private func configureClient(fileDescriptor: Int32) {
        let clientID = UUID()
        let readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)

        readSource.setEventHandler { [weak self] in
            self?.readAvailableData(from: clientID)
        }
        readSource.setCancelHandler { [weak self] in
            guard let self else {
                return
            }

            if let client = self.clients[clientID] {
                close(client.fileDescriptor)
            } else {
                close(fileDescriptor)
            }
        }

        clients[clientID] = ClientConnection(
            id: clientID,
            fileDescriptor: fileDescriptor,
            readSource: readSource,
            role: nil
        )
        readSource.resume()

        send(.hello(BridgeHello()), to: clientID)
    }

    private func readAvailableData(from clientID: UUID) {
        guard var client = clients[clientID] else {
            return
        }

        var localBuffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let bytesRead = read(client.fileDescriptor, &localBuffer, localBuffer.count)

            if bytesRead > 0 {
                client.buffer.append(localBuffer, count: bytesRead)

                // H2: cap per-client buffer to prevent OOM from a peer
                // that streams bytes without ever writing a newline.
                if client.buffer.count > BridgeSecurity.maxClientBufferBytes {
                    BridgeServer.logSecurityEvent(
                        "bridge: client buffer overflow (\(client.buffer.count) > \(BridgeSecurity.maxClientBufferBytes))"
                    )
                    clients[clientID] = client
                    removeClient(clientID)
                    return
                }

                // H2: cap individual frame size. We scan the *unconsumed*
                // prefix for a frame longer than the limit; if found, we
                // drop the whole connection rather than sift partial junk.
                if let firstNewline = client.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let frameLength = client.buffer.distance(from: client.buffer.startIndex, to: firstNewline)
                    if frameLength > BridgeSecurity.maxFrameBytes {
                        BridgeServer.logSecurityEvent(
                            "bridge: frame too large (\(frameLength) > \(BridgeSecurity.maxFrameBytes))"
                        )
                        clients[clientID] = client
                        removeClient(clientID)
                        return
                    }
                } else if client.buffer.count > BridgeSecurity.maxFrameBytes {
                    // No newline yet but already over frame limit — abort.
                    BridgeServer.logSecurityEvent(
                        "bridge: frame without newline exceeds \(BridgeSecurity.maxFrameBytes) bytes"
                    )
                    clients[clientID] = client
                    removeClient(clientID)
                    return
                }

                do {
                    let envelopes = try BridgeCodec.decodeLines(from: &client.buffer)
                    clients[clientID] = client

                    for envelope in envelopes {
                        // Optional defensive handshake: if the peer chooses
                        // to send a `BridgeHello` first, validate its
                        // protocol version. Existing client implementations
                        // (LocalBridgeClient, BridgeCommandClient,
                        // AtollHooks) do not send one, so absence is not an
                        // error — we simply skip this check until proven
                        // otherwise. A mismatched-version hello, however,
                        // is fatal.
                        if !client.didReceiveHello, case let .hello(hello) = envelope {
                            if hello.protocolVersion != BridgeHello().protocolVersion {
                                BridgeServer.logSecurityEvent(
                                    "bridge: protocol version mismatch (\(hello.protocolVersion))"
                                )
                                removeClient(clientID)
                                return
                            }
                            if var c = clients[clientID] {
                                c.didReceiveHello = true
                                clients[clientID] = c
                            }
                            continue
                        }

                        if case let .command(command) = envelope {
                            // M1: token-bucket rate limit. Drop the frame
                            // when over budget but keep the connection up;
                            // a legitimate burst should not kill the helper.
                            guard var c = clients[clientID] else { return }
                            if !c.rateBucket.tryConsume() {
                                clients[clientID] = c
                                BridgeServer.logSecurityEvent(
                                    "bridge: rate-limit drop for client \(clientID)"
                                )
                                continue
                            }
                            clients[clientID] = c
                            handle(command, from: clientID)
                        }
                    }
                } catch {
                    removeClient(clientID)
                    return
                }

                continue
            }

            if bytesRead == 0 {
                removeClient(clientID)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                clients[clientID] = client
                return
            }

            removeClient(clientID)
            return
        }
    }

    private func handle(_ command: BridgeCommand, from clientID: UUID) {
        switch command {
        case let .registerClient(role):
            guard var client = clients[clientID] else {
                return
            }

            client.role = role
            clients[clientID] = client
            send(.response(.acknowledged), to: clientID)

        case let .requestQuestion(sessionID, prompt):
            guard hasSession(id: sessionID) else {
                send(.response(.acknowledged), to: clientID)
                return
            }

            emit(
                .questionAsked(
                    QuestionAsked(
                        sessionID: sessionID,
                        prompt: prompt,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case let .resolvePermission(sessionID, resolution):
            if pendingClaudeInteractions[sessionID] != nil {
                resolvePendingClaudeInteraction(sessionID: sessionID, resolution: resolution)
                send(.response(.acknowledged), to: clientID)
                return
            }

            if pendingOpenCodeInteractions[sessionID] != nil {
                resolvePendingOpenCodeInteraction(sessionID: sessionID, resolution: resolution)
                send(.response(.acknowledged), to: clientID)
                return
            }

            if let interaction = pendingCursorInteractions.removeValue(forKey: sessionID) {
                let directive: CursorHookDirective
                let summary: String
                let phase: SessionPhase
                switch resolution {
                case .allowOnce:
                    directive = CursorHookDirective(continue: true, permission: .allow)
                    summary = "Permission approved."
                    phase = .running
                case let .deny(message, _):
                    directive = CursorHookDirective(continue: true, permission: .deny, agentMessage: message)
                    summary = message ?? "Permission denied in Open Island."
                    phase = .completed
                }

                emit(
                    phase == .completed
                        ? .sessionCompleted(
                            SessionCompleted(
                                sessionID: sessionID,
                                summary: summary,
                                timestamp: .now
                            )
                        )
                        : .activityUpdated(
                            SessionActivityUpdated(
                                sessionID: sessionID,
                                summary: summary,
                                phase: phase,
                                timestamp: .now
                            )
                        )
                )

                send(.response(.cursorHookDirective(directive)), to: interaction.clientID)
                send(.response(.acknowledged), to: clientID)
                return
            }

            localState.resolvePermission(sessionID: sessionID, resolution: resolution)
            broadcast([.event(
                resolution.isApproved
                    ? .activityUpdated(
                        SessionActivityUpdated(
                            sessionID: sessionID,
                            summary: "Permission approved. Codex continued the command.",
                            phase: .running,
                            timestamp: .now
                        )
                    )
                    : .sessionCompleted(
                        SessionCompleted(
                            sessionID: sessionID,
                            summary: "Permission denied in Open Island.",
                            timestamp: .now
                        )
                    )
            )])
            resolvePendingApproval(sessionID: sessionID, approved: resolution.isApproved)
            send(.response(.acknowledged), to: clientID)

        case let .answerQuestion(sessionID, response):
            if pendingClaudeInteractions[sessionID] != nil {
                resolvePendingClaudeQuestion(sessionID: sessionID, response: response)
                send(.response(.acknowledged), to: clientID)
                return
            }

            if pendingOpenCodeInteractions[sessionID] != nil {
                resolvePendingOpenCodeQuestion(sessionID: sessionID, response: response)
                send(.response(.acknowledged), to: clientID)
                return
            }

            let summary = response.displaySummary.isEmpty
                ? "Answered the question."
                : "Answered: \(response.displaySummary)"
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case let .processCodexHook(payload):
            handleCodexHook(payload, from: clientID)

        case let .processClaudeHook(payload):
            handleClaudeHook(payload, from: clientID)

        case let .processOpenCodeHook(payload):
            handleOpenCodeHook(payload, from: clientID)

        case let .processCursorHook(payload):
            handleCursorHook(payload, from: clientID)

        case let .processGeminiHook(payload):
            handleGeminiHook(payload, from: clientID)
        }
    }

    private func handleCodexHook(_ payload: CodexHookPayload, from clientID: UUID) {
        // Filter out Codex.app internal invocations (e.g. conversation title
        // generation).  These fire hooks but have no transcript file — they're
        // ephemeral API calls, not user-facing sessions.
        if payload.terminalApp == "Codex.app",
           (payload.transcriptPath ?? "").isEmpty {
            send(.response(.acknowledged), to: clientID)
            return
        }

        switch payload.hookEventName {
        case .sessionStart:
            let event = AgentEvent.sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .codex,
                    origin: .live,
                    summary: payload.implicitStartSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    codexMetadata: payload.defaultCodexMetadata.isEmpty ? nil : payload.defaultCodexMetadata
                )
            )

            emit(event)
            send(.response(.acknowledged), to: clientID)

        case .userPromptSubmit:
            ensureSessionExists(for: payload)
            synchronizeJumpTarget(for: payload)
            synchronizeCodexMetadata(for: payload)
            // L3: truncate helper-supplied strings before they reach SessionState/UI.
            let prompt = (payload.prompt ?? payload.promptPreview ?? "User submitted a prompt to Codex.")
                .truncatedForUI()
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: "Prompt: \(prompt)".truncatedForUI(),
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .preToolUse:
            ensureSessionExists(for: payload)
            synchronizeJumpTarget(for: payload)
            synchronizeCodexMetadata(for: payload)

            let command = (payload.commandPreview ?? "Bash command").truncatedForUI()

            let approvalEvent = AgentEvent.permissionRequested(
                PermissionRequested(
                    sessionID: payload.sessionID,
                    request: PermissionRequest(
                        title: "Run Bash command",
                        summary: "Codex wants to run a shell command.",
                        affectedPath: (payload.commandText ?? command).truncatedForUI(),
                        primaryActionTitle: "Allow",
                        secondaryActionTitle: "Deny"
                    ),
                    timestamp: .now
                )
            )

            emit(approvalEvent)

            putPendingApproval(
                sessionID: payload.sessionID,
                approval: PendingApproval(clientID: clientID)
            )

        case .postToolUse:
            ensureSessionExists(for: payload)
            synchronizeJumpTarget(for: payload)
            synchronizeCodexMetadata(for: payload)
            let command = (payload.commandPreview ?? "Bash command").truncatedForUI()
            let responsePreview = payload.toolResponsePreview?.truncatedForUI()
            let summary = (responsePreview.map { "Bash finished: \(command) · \($0)" } ?? "Bash finished: \(command)").truncatedForUI()

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .stop:
            ensureSessionExists(for: payload)
            synchronizeJumpTarget(for: payload)
            synchronizeCodexMetadata(for: payload)
            let summary = (payload.lastAssistantMessage ?? payload.assistantMessagePreview ?? "Codex completed the turn.").truncatedForUI()

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: summary,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)
        }
    }

    private func handleClaudeHook(_ payload: ClaudeHookPayload, from clientID: UUID) {
        // Subagent processes fire their own hooks with agentID set.
        // The parent session already receives SubagentStart/SubagentStop events,
        // so we suppress subagent hooks to avoid creating duplicate sessions.
        if payload.agentID != nil,
           payload.hookEventName != .subagentStart,
           payload.hookEventName != .subagentStop {
            send(.response(.acknowledged), to: clientID)
            return
        }

        // On every event from the parent session, opportunistically clean up
        // subagents whose SubagentStop was never received.
        cleanUpStaleSubagents(forSession: payload.sessionID)

        switch payload.hookEventName {
        case .sessionStart:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            emit(
                .sessionStarted(
                    SessionStarted(
                        sessionID: payload.sessionID,
                        title: payload.sessionTitle,
                        tool: payload.resolvedAgentTool,
                        origin: .live,
                        initialPhase: .completed,
                        summary: payload.implicitStartSummary,
                        timestamp: .now,
                        jumpTarget: payload.defaultJumpTarget,
                        claudeMetadata: payload.defaultClaudeMetadata.isEmpty ? nil : payload.defaultClaudeMetadata,
                        isRemote: payload.remote == true
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .userPromptSubmit:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: (payload.promptPreview.map { "Prompt: \($0)" } ?? payload.implicitStartSummary).truncatedForUI(),
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .preToolUse:
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)
            pendingClaudeToolContexts[payload.permissionCorrelationKey] = PendingClaudeToolContext(
                toolUseID: payload.toolUseID,
                toolName: payload.toolName,
                toolInput: payload.toolInput
            )

            // Cache Agent tool description for upcoming subagentStart
            if payload.toolName == "Agent",
               case let .object(obj) = payload.toolInput,
               case let .string(desc) = obj["description"],
               !desc.isEmpty {
                pendingAgentDescriptions[payload.sessionID] = desc
            }

            // Capture task creation/updates from TaskCreate, TaskUpdate tools
            if let toolName = payload.toolName,
               case let .object(obj) = payload.toolInput {
                if toolName == "TaskCreate" {
                    let tempID = updateTask(from: obj, toolName: toolName, sessionID: payload.sessionID)
                    if let tempID, let toolUseID = payload.toolUseID {
                        pendingTaskCreations[toolUseID] = tempID
                    }
                } else if toolName == "TaskUpdate" {
                    _ = updateTask(from: obj, toolName: toolName, sessionID: payload.sessionID)
                }
            }

            // L3: helper-supplied tool name + input preview are unbounded.
            let claudePreToolName = payload.toolName?.truncatedForUI()
            let claudePreToolPreview = payload.toolInputPreview?.truncatedForUI()
            let summary = claudePreToolName.map { "Running \($0)" } ?? "Running \(payload.resolvedAgentTool.displayName) tool"
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: (claudePreToolPreview.map { "\(summary): \($0)" } ?? summary).truncatedForUI(),
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .permissionRequest:
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            if let prompt = payload.questionPrompt {
                emit(
                    .questionAsked(
                        QuestionAsked(
                            sessionID: payload.sessionID,
                            prompt: prompt,
                            timestamp: .now
                        )
                    )
                )

                putPendingClaudeInteraction(
                    sessionID: payload.sessionID,
                    interaction: PendingClaudeInteraction(
                        clientID: clientID,
                        kind: .question(payload, prompt)
                    )
                )
            } else {
                let suggestions = payload.permissionSuggestions ?? []

                emit(
                    .permissionRequested(
                        PermissionRequested(
                            sessionID: payload.sessionID,
                            request: PermissionRequest(
                                // L3: bound title/summary/path before they reach UI labels.
                                title: payload.permissionRequestTitle.truncatedForUI(),
                                summary: payload.permissionRequestSummary.truncatedForUI(),
                                affectedPath: payload.permissionAffectedPath.truncatedForUI(),
                                primaryActionTitle: "Allow Once",
                                secondaryActionTitle: "Deny",
                                toolName: payload.toolName?.truncatedForUI(),
                                toolUseID: claudeToolUseID(for: payload),
                                toolInput: payload.toolInput,
                                suggestedUpdates: suggestions
                            ),
                            timestamp: .now
                        )
                    )
                )

                putPendingClaudeInteraction(
                    sessionID: payload.sessionID,
                    interaction: PendingClaudeInteraction(
                        clientID: clientID,
                        kind: .permission(payload)
                    )
                )
            }

        case .postToolUse:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)
            pendingClaudeToolContexts.removeValue(forKey: payload.permissionCorrelationKey)

            // After TaskCreate completes, update the temporary ID with the real task_id from the response
            if payload.toolName == "TaskCreate",
               let toolUseID = payload.toolUseID,
               let tempID = pendingTaskCreations.removeValue(forKey: toolUseID) {
                replaceTaskID(
                    sessionID: payload.sessionID,
                    tempID: tempID,
                    response: payload.toolResponse
                )
            }

            let summary = {
                if payload.toolName == "AskUserQuestion" {
                    return "\(payload.resolvedAgentTool.displayName) captured your answers."
                }

                if let preview = payload.toolResponsePreview?.truncatedForUI(),
                   let toolName = payload.toolName?.truncatedForUI() {
                    return "\(toolName) finished: \(preview)"
                }

                if let toolName = payload.toolName?.truncatedForUI() {
                    return "\(toolName) finished."
                }

                return payload.implicitStartSummary
            }()

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary.truncatedForUI(),
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .postToolUseFailure:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)
            pendingClaudeToolContexts.removeValue(forKey: payload.permissionCorrelationKey)

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: (payload.error?.truncatedForUI() ?? "\(payload.resolvedAgentTool.displayName) tool failed."),
                        phase: payload.isInterrupt == true ? .completed : .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .permissionDenied:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: (payload.error?.truncatedForUI() ?? "\(payload.resolvedAgentTool.displayName) permission was denied."),
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .notification:
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            let currentPhase = localState.session(id: payload.sessionID)?.phase ?? .completed
            let notificationPhase: SessionPhase
            if payload.notificationType == "idle_prompt" {
                notificationPhase = .completed
            } else {
                // Notifications are informational — never escalate phase to running.
                notificationPhase = currentPhase
            }

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: (payload.notificationPreview ?? payload.implicitStartSummary).truncatedForUI(),
                        phase: notificationPhase,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .stop:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            // Turn is complete — all subagents from this turn must be finished.
            clearAllActiveSubagents(fromSession: payload.sessionID)

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: (payload.lastAssistantMessage ?? payload.assistantMessagePreview ?? "\(payload.resolvedAgentTool.displayName) completed the turn.").truncatedForUI(),
                        timestamp: .now,
                        isInterrupt: payload.isInterrupt
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .stopFailure:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            // Turn failed — all subagents from this turn must be finished.
            clearAllActiveSubagents(fromSession: payload.sessionID)

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: (payload.error ?? payload.lastAssistantMessage ?? payload.assistantMessagePreview ?? "\(payload.resolvedAgentTool.displayName) failed to finish the turn.").truncatedForUI(),
                        timestamp: .now,
                        isInterrupt: payload.isInterrupt
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .subagentStart:
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            if let agentID = payload.agentID {
                let desc = pendingAgentDescriptions.removeValue(forKey: payload.sessionID)
                addSubagent(
                    ClaudeSubagentInfo(
                        agentID: agentID,
                        agentType: payload.agentType,
                        taskDescription: desc?.truncatedForUI(),
                        startedAt: .now
                    ),
                    toSession: payload.sessionID
                )
            }

            let summary = (payload.agentType.map { "Started \($0) subagent." } ?? "Started \(payload.resolvedAgentTool.displayName) subagent.").truncatedForUI()
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .subagentStop:
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            if let agentID = payload.agentID {
                removeSubagent(agentID: agentID, fromSession: payload.sessionID)
            }

            let summary = (payload.lastAssistantMessage ?? payload.assistantMessagePreview
                ?? payload.agentType.map { "Finished \($0) subagent." }
                ?? "Finished \(payload.resolvedAgentTool.displayName) subagent.").truncatedForUI()
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .preCompact:
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: "\(payload.resolvedAgentTool.displayName) is compacting the conversation.",
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .sessionEnd:
            clearStaleClaudeInteractionIfNeeded(for: payload.sessionID)
            ensureClaudeSessionExists(for: payload)
            synchronizeClaudeJumpTarget(for: payload)
            synchronizeClaudeMetadata(for: payload)

            // Session is ending — clean up any lingering subagents.
            clearAllActiveSubagents(fromSession: payload.sessionID)

            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: "\(payload.resolvedAgentTool.displayName) session ended.",
                        timestamp: .now,
                        isInterrupt: true,
                        isSessionEnd: true
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)
        }
    }

    private func handleOpenCodeHook(_ payload: OpenCodeHookPayload, from clientID: UUID) {
        switch payload.hookEventName {
        case .sessionStart:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            emit(
                .sessionStarted(
                    SessionStarted(
                        sessionID: payload.sessionID,
                        title: payload.sessionTitle,
                        tool: .openCode,
                        origin: .live,
                        initialPhase: .running,
                        summary: payload.implicitStartSummary,
                        timestamp: .now,
                        jumpTarget: payload.defaultJumpTarget,
                        openCodeMetadata: payload.defaultOpenCodeMetadata.isEmpty ? nil : payload.defaultOpenCodeMetadata
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .userPromptSubmit:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: (payload.promptPreview.map { "Prompt: \($0)" } ?? payload.implicitStartSummary).truncatedForUI(),
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .preToolUse:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            let ocToolName = payload.toolName?.truncatedForUI()
            let ocToolPreview = payload.toolInputPreview?.truncatedForUI()
            let summary = ocToolName.map { "Running \($0)" } ?? "Running OpenCode tool"
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: (ocToolPreview.map { "\(summary): \($0)" } ?? summary).truncatedForUI(),
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .postToolUse:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            let summary = (payload.toolName.map { "\($0.truncatedForUI()) finished." } ?? "OpenCode tool finished.")
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .permissionRequest:
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)

            emit(
                .permissionRequested(
                    PermissionRequested(
                        sessionID: payload.sessionID,
                        request: PermissionRequest(
                            title: (payload.permissionTitle ?? payload.toolName.map { "Allow \($0)" } ?? "Allow OpenCode tool").truncatedForUI(),
                            summary: (payload.permissionDescription ?? "OpenCode needs permission to continue.").truncatedForUI(),
                            affectedPath: (payload.toolInputPreview ?? payload.cwd).truncatedForUI(),
                            primaryActionTitle: "Allow",
                            secondaryActionTitle: "Deny",
                            toolName: payload.toolName?.truncatedForUI()
                        ),
                        timestamp: .now
                    )
                )
            )

            putPendingOpenCodeInteraction(
                sessionID: payload.sessionID,
                interaction: PendingOpenCodeInteraction(
                    clientID: clientID,
                    kind: .permission(payload)
                )
            )

        case .questionAsked:
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)

            let questionTitle = (payload.questionText ?? "OpenCode has a question for you.").truncatedForUI()
            emit(
                .questionAsked(
                    QuestionAsked(
                        sessionID: payload.sessionID,
                        prompt: QuestionPrompt(
                            title: questionTitle,
                            options: []
                        ),
                        timestamp: .now
                    )
                )
            )

            putPendingOpenCodeInteraction(
                sessionID: payload.sessionID,
                interaction: PendingOpenCodeInteraction(
                    clientID: clientID,
                    kind: .question(payload)
                )
            )

        case .stop:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: (payload.lastAssistantMessage ?? payload.assistantMessagePreview ?? "OpenCode completed the turn.").truncatedForUI(),
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .sessionEnd:
            clearStaleOpenCodeInteractionIfNeeded(for: payload.sessionID)
            ensureOpenCodeSessionExists(for: payload)
            synchronizeOpenCodeJumpTarget(for: payload)
            synchronizeOpenCodeMetadata(for: payload)
            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: "OpenCode session ended.",
                        timestamp: .now,
                        isInterrupt: true,
                        isSessionEnd: true
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)
        }
    }

    /// Dispatches a Cursor hook payload to the appropriate handler based on
    /// the hook event name, managing session lifecycle, metadata, and
    /// permission directives.
    private func handleCursorHook(_ payload: CursorHookPayload, from clientID: UUID) {
        switch payload.hookEventName {
        case .beforeSubmitPrompt:
            clearStaleCursorInteractionIfNeeded(for: payload.sessionID)
            ensureCursorSessionExists(for: payload)
            synchronizeCursorJumpTarget(for: payload)
            synchronizeCursorMetadata(for: payload)
            let promptSummary = payload.promptPreview
                ?? localState.session(id: payload.sessionID)?.cursorMetadata?.initialUserPrompt
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: (promptSummary.map { "Prompt: \($0)" } ?? payload.implicitStartSummary).truncatedForUI(),
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .beforeShellExecution:
            clearStaleCursorInteractionIfNeeded(for: payload.sessionID)
            ensureCursorSessionExists(for: payload)
            synchronizeCursorJumpTarget(for: payload)
            synchronizeCursorMetadata(for: payload)
            let shellSummary = (payload.commandPreview.map { "Running: \($0)" } ?? "Running shell command").truncatedForUI()
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: shellSummary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.cursorHookDirective(CursorHookDirective(permission: .allow))), to: clientID)

        case .beforeMCPExecution:
            clearStaleCursorInteractionIfNeeded(for: payload.sessionID)
            ensureCursorSessionExists(for: payload)
            synchronizeCursorJumpTarget(for: payload)
            synchronizeCursorMetadata(for: payload)
            let mcpSummary = (payload.toolName.map { "Calling \($0)" } ?? "Calling MCP tool").truncatedForUI()
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: mcpSummary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.cursorHookDirective(CursorHookDirective(permission: .allow))), to: clientID)

        case .beforeReadFile:
            clearStaleCursorInteractionIfNeeded(for: payload.sessionID)
            ensureCursorSessionExists(for: payload)
            synchronizeCursorJumpTarget(for: payload)
            synchronizeCursorMetadata(for: payload)
            let summary = (payload.filePath.map { "Reading \($0)" } ?? "Reading a file").truncatedForUI()
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .afterFileEdit:
            clearStaleCursorInteractionIfNeeded(for: payload.sessionID)
            ensureCursorSessionExists(for: payload)
            synchronizeCursorJumpTarget(for: payload)
            synchronizeCursorMetadata(for: payload)
            let summary = (payload.filePath.map { "Edited \($0)" } ?? "Cursor edited a file").truncatedForUI()
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: summary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .stop:
            clearStaleCursorInteractionIfNeeded(for: payload.sessionID)
            ensureCursorSessionExists(for: payload)
            synchronizeCursorJumpTarget(for: payload)
            synchronizeCursorMetadata(for: payload)
            let stopSummary: String
            switch payload.status {
            case "error":
                stopSummary = "Cursor encountered an error."
            case "aborted":
                stopSummary = "Cursor task was aborted."
            default:
                stopSummary = "Cursor completed the turn."
            }
            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: stopSummary,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)
        }
    }

    private func handleGeminiHook(_ payload: GeminiHookPayload, from clientID: UUID) {
        switch payload.hookEventName {
        case .sessionStart:
            emit(
                .sessionStarted(
                    SessionStarted(
                        sessionID: payload.sessionID,
                        title: payload.sessionTitle,
                        tool: .geminiCLI,
                        origin: .live,
                        initialPhase: .completed,
                        summary: payload.implicitSummary,
                        timestamp: .now,
                        jumpTarget: payload.defaultJumpTarget,
                        geminiMetadata: payload.defaultGeminiMetadata.isEmpty ? nil : payload.defaultGeminiMetadata
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .beforeAgent:
            ensureGeminiSessionExists(for: payload)
            synchronizeGeminiJumpTarget(for: payload)
            synchronizeGeminiMetadata(for: payload)
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.implicitSummary,
                        phase: .running,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .afterAgent:
            ensureGeminiSessionExists(for: payload)
            synchronizeGeminiJumpTarget(for: payload)
            synchronizeGeminiMetadata(for: payload)
            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: payload.implicitSummary,
                        timestamp: .now
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .sessionEnd:
            ensureGeminiSessionExists(for: payload)
            synchronizeGeminiJumpTarget(for: payload)
            synchronizeGeminiMetadata(for: payload)
            emit(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: payload.sessionID,
                        summary: (payload.reason.map { "Gemini CLI session ended: \($0)." } ?? payload.implicitSummary).truncatedForUI(),
                        timestamp: .now,
                        isInterrupt: true,
                        isSessionEnd: true
                    )
                )
            )
            send(.response(.acknowledged), to: clientID)

        case .notification:
            ensureGeminiSessionExists(for: payload)
            synchronizeGeminiJumpTarget(for: payload)
            synchronizeGeminiMetadata(for: payload)

            let currentPhase = localState.session(id: payload.sessionID)?.phase ?? .completed
            emit(
                .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: payload.sessionID,
                        summary: payload.notificationSummary.truncatedForUI(),
                        phase: currentPhase,
                        timestamp: .now
                    )
                )
            )

            send(.response(.acknowledged), to: clientID)
        }
    }

    private func ensureGeminiSessionExists(for payload: GeminiHookPayload) {
        guard !hasSession(id: payload.sessionID) else {
            return
        }

        emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .geminiCLI,
                    origin: .live,
                    initialPhase: .completed,
                    summary: payload.hookEventName == .notification ? payload.notificationSummary : payload.implicitSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    geminiMetadata: payload.defaultGeminiMetadata.isEmpty ? nil : payload.defaultGeminiMetadata
                )
            )
        )
    }

    private func synchronizeGeminiJumpTarget(for payload: GeminiHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let jumpTarget = Self.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: payload.defaultJumpTarget,
            existing: existingSession.jumpTarget
        )

        guard existingSession.jumpTarget != jumpTarget else {
            return
        }

        emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: jumpTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeGeminiMetadata(for payload: GeminiHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let update = payload.defaultGeminiMetadata
        let merged = GeminiSessionMetadata(
            transcriptPath: update.transcriptPath ?? existingSession.geminiMetadata?.transcriptPath,
            initialUserPrompt: existingSession.geminiMetadata?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existingSession.geminiMetadata?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existingSession.geminiMetadata?.lastAssistantMessage,
            lastAssistantMessageBody: update.lastAssistantMessageBody ?? existingSession.geminiMetadata?.lastAssistantMessageBody
        )
        guard !merged.isEmpty else {
            return
        }

        guard existingSession.geminiMetadata != merged else {
            return
        }

        emit(
            .geminiSessionMetadataUpdated(
                GeminiSessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    geminiMetadata: merged,
                    timestamp: .now
                )
            )
        )
    }

    private func clearStaleCursorInteractionIfNeeded(for sessionID: String) {
        guard pendingCursorInteractions.removeValue(forKey: sessionID) != nil else {
            return
        }

        emit(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: sessionID,
                    summary: "Approval was handled outside Open Island.",
                    timestamp: .now
                )
            )
        )
    }

    /// Creates a Cursor session if one does not already exist for the given
    /// conversation, or re-creates it if the previous session was marked as
    /// ended (e.g. after a staleness timeout).
    private func ensureCursorSessionExists(for payload: CursorHookPayload) {
        if let existing = localState.session(id: payload.sessionID), !existing.isSessionEnded {
            return
        }

        emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .cursor,
                    origin: .live,
                    initialPhase: .running,
                    summary: payload.implicitStartSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    cursorMetadata: payload.defaultCursorMetadata.isEmpty ? nil : payload.defaultCursorMetadata
                )
            )
        )
    }

    private func synchronizeCursorJumpTarget(for payload: CursorHookPayload) {
        let newTarget = payload.defaultJumpTarget
        guard let existing = localState.session(id: payload.sessionID)?.jumpTarget,
              existing != newTarget else {
            return
        }

        emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: newTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeCursorMetadata(for payload: CursorHookPayload) {
        let existing = localState.session(id: payload.sessionID)?.cursorMetadata
        let update = payload.defaultCursorMetadata
        let clearToolState = payload.hookEventName == .stop

        let resolvedTranscriptPath = update.transcriptPath ?? existing?.transcriptPath

        var initialPrompt = existing?.initialUserPrompt ?? update.initialUserPrompt
        if initialPrompt == nil, let transcriptPath = resolvedTranscriptPath {
            initialPrompt = CursorTranscriptReader.initialUserPrompt(at: transcriptPath)
        }

        let merged = CursorSessionMetadata(
            conversationId: update.conversationId ?? existing?.conversationId,
            generationId: update.generationId ?? existing?.generationId,
            workspaceRoots: update.workspaceRoots ?? existing?.workspaceRoots,
            initialUserPrompt: initialPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt ?? initialPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: clearToolState ? nil : (update.currentTool ?? existing?.currentTool),
            currentToolInputPreview: clearToolState ? nil : (update.currentToolInputPreview ?? existing?.currentToolInputPreview),
            currentCommandPreview: clearToolState ? nil : (update.currentCommandPreview ?? existing?.currentCommandPreview),
            model: update.model ?? existing?.model,
            transcriptPath: resolvedTranscriptPath
        )

        guard existing != merged else { return }

        emit(
            .cursorSessionMetadataUpdated(
                CursorSessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    cursorMetadata: merged,
                    timestamp: .now
                )
            )
        )
    }

    private func clearStaleOpenCodeInteractionIfNeeded(for sessionID: String) {
        guard pendingOpenCodeInteractions.removeValue(forKey: sessionID) != nil else {
            return
        }

        emit(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: sessionID,
                    summary: "Approval was handled outside Open Island.",
                    timestamp: .now
                )
            )
        )
    }

    private func ensureOpenCodeSessionExists(for payload: OpenCodeHookPayload) {
        guard !hasSession(id: payload.sessionID) else {
            return
        }

        emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .openCode,
                    origin: .live,
                    initialPhase: .running,
                    summary: payload.implicitStartSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    openCodeMetadata: payload.defaultOpenCodeMetadata.isEmpty ? nil : payload.defaultOpenCodeMetadata
                )
            )
        )
    }

    private func synchronizeOpenCodeJumpTarget(for payload: OpenCodeHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        var jumpTarget = payload.defaultJumpTarget

        if jumpTarget.terminalSessionID == nil,
           let existingID = existingSession.jumpTarget?.terminalSessionID,
           !existingID.isEmpty {
            jumpTarget.terminalSessionID = existingID
        }

        guard existingSession.jumpTarget != jumpTarget else {
            return
        }

        emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: jumpTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeOpenCodeMetadata(for payload: OpenCodeHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let mergedMetadata = mergedOpenCodeMetadata(
            existing: existingSession.openCodeMetadata,
            update: payload.defaultOpenCodeMetadata,
            hookEventName: payload.hookEventName
        )
        guard !mergedMetadata.isEmpty else {
            return
        }

        guard existingSession.openCodeMetadata != mergedMetadata else {
            return
        }

        emit(
            .openCodeSessionMetadataUpdated(
                OpenCodeSessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    openCodeMetadata: mergedMetadata,
                    timestamp: .now
                )
            )
        )
    }

    private func mergedOpenCodeMetadata(
        existing: OpenCodeSessionMetadata?,
        update: OpenCodeSessionMetadata,
        hookEventName: OpenCodeHookEventName
    ) -> OpenCodeSessionMetadata {
        OpenCodeSessionMetadata(
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedOpenCodeCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentToolInputPreview: mergedOpenCodeCurrentToolInputPreview(
                existing: existing?.currentToolInputPreview,
                update: update.currentToolInputPreview,
                hookEventName: hookEventName
            ),
            model: update.model ?? existing?.model
        )
    }

    private func mergedOpenCodeCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: OpenCodeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .stop, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .questionAsked:
            return existing
        }
    }

    private func mergedOpenCodeCurrentToolInputPreview(
        existing: String?,
        update: String?,
        hookEventName: OpenCodeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .stop, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .questionAsked:
            return existing
        }
    }

    private func resolvePendingOpenCodeInteraction(
        sessionID: String,
        resolution: PermissionResolution
    ) {
        guard let pendingInteraction = pendingOpenCodeInteractions.removeValue(forKey: sessionID) else {
            return
        }

        let directive: OpenCodeHookDirective
        let summary: String
        let phase: SessionPhase

        switch (pendingInteraction.kind, resolution) {
        case let (.permission(payload), .allowOnce):
            directive = .allow
            summary = payload.toolName.map { "Permission approved for \($0)." } ?? "Permission approved."
            phase = .running

        case let (.permission(_), .deny(message, _)):
            directive = .deny(reason: message ?? "Permission denied in Open Island.")
            summary = message ?? "Permission denied in Open Island."
            phase = .completed

        case (.question, .allowOnce):
            directive = .allow
            summary = "OpenCode's question was answered."
            phase = .running

        case let (.question(_), .deny(message, _)):
            directive = .deny(reason: message ?? "Declined to answer.")
            summary = message ?? "Declined to answer."
            phase = .completed
        }

        emit(
            phase == .completed
                ? .sessionCompleted(
                    SessionCompleted(
                        sessionID: sessionID,
                        summary: summary,
                        timestamp: .now
                    )
                )
                : .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: sessionID,
                        summary: summary,
                        phase: phase,
                        timestamp: .now
                    )
                )
        )

        send(.response(.openCodeHookDirective(directive)), to: pendingInteraction.clientID)
    }

    private func resolvePendingOpenCodeQuestion(
        sessionID: String,
        response: QuestionPromptResponse
    ) {
        guard let pendingInteraction = pendingOpenCodeInteractions.removeValue(forKey: sessionID) else {
            return
        }

        let answerText = response.rawAnswer ?? response.displaySummary
        let summary = answerText.isEmpty
            ? "Answered OpenCode's question."
            : "Answered: \(answerText)"

        emit(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: sessionID,
                    summary: summary,
                    phase: .running,
                    timestamp: .now
                )
            )
        )

        send(
            .response(.openCodeHookDirective(.answer(text: answerText))),
            to: pendingInteraction.clientID
        )
    }

    private func clearStaleClaudeInteractionIfNeeded(for sessionID: String) {
        guard pendingClaudeInteractions.removeValue(forKey: sessionID) != nil else {
            return
        }

        emit(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: sessionID,
                    summary: "Approval was handled outside Open Island.",
                    timestamp: .now
                )
            )
        )
    }

    private func ensureSessionExists(for payload: CodexHookPayload) {
        guard !hasSession(id: payload.sessionID) else {
            return
        }

        emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: .codex,
                    origin: .live,
                    summary: payload.implicitStartSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    codexMetadata: payload.defaultCodexMetadata.isEmpty ? nil : payload.defaultCodexMetadata
                )
            )
        )
    }

    private func synchronizeJumpTarget(for payload: CodexHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let jumpTarget = Self.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: payload.defaultJumpTarget,
            existing: existingSession.jumpTarget
        )

        guard existingSession.jumpTarget != jumpTarget else {
            return
        }

        emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: jumpTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeCodexMetadata(for payload: CodexHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let mergedMetadata = mergedCodexMetadata(
            existing: existingSession.codexMetadata,
            update: payload.defaultCodexMetadata,
            hookEventName: payload.hookEventName
        )
        guard !mergedMetadata.isEmpty else {
            return
        }

        guard existingSession.codexMetadata != mergedMetadata else {
            return
        }

        emit(
            .sessionMetadataUpdated(
                SessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    codexMetadata: mergedMetadata,
                    timestamp: .now
                )
            )
        )
    }

    private func ensureClaudeSessionExists(for payload: ClaudeHookPayload) {
        guard !hasSession(id: payload.sessionID) else {
            return
        }

        emit(
            .sessionStarted(
                SessionStarted(
                    sessionID: payload.sessionID,
                    title: payload.sessionTitle,
                    tool: payload.resolvedAgentTool,
                    origin: .live,
                    initialPhase: .completed,
                    summary: payload.implicitStartSummary,
                    timestamp: .now,
                    jumpTarget: payload.defaultJumpTarget,
                    claudeMetadata: payload.defaultClaudeMetadata.isEmpty ? nil : payload.defaultClaudeMetadata,
                    isRemote: payload.remote == true
                )
            )
        )
    }

    /// Merges an incoming jumpTarget with the session's existing one so
    /// that expensive-to-resolve fields are not silently cleared by a
    /// later hook that failed to re-resolve them.
    ///
    /// Two fields fall into this category:
    ///
    /// 1. `terminalSessionID` — only SessionStart hooks actually query
    ///    Ghostty's focused-terminal locator (subsequent hooks leave it
    ///    nil to avoid stamping the wrong terminal if the user has
    ///    since switched tabs). Without preservation, every non-start
    ///    hook would overwrite a correctly-resolved session id with
    ///    nil. Preservation has been in place since the Ghostty jump
    ///    feature landed.
    ///
    /// 2. `warpPaneUUID` — resolved via a SQLite + process-tree walk
    ///    at hook time. Legitimate transient failures (pgrep race,
    ///    SQLite lock contention, Warp mid-startup) make the resolver
    ///    return nil. Without preservation, the first such transient
    ///    failure after a successful resolve would permanently drop
    ///    the mapping for the rest of the session, demoting precision
    ///    jump to bare activation until the NEXT lucky hook.
    ///
    /// Both are "resolved fields": the hook either succeeds at
    /// finding them or reports nil. nil does NOT mean "absence is the
    /// ground truth" — it means "this invocation could not determine
    /// the value, prefer the last known good one".
    static func mergeJumpTargetPreservingExistingResolvedFields(
        incoming: JumpTarget,
        existing: JumpTarget?
    ) -> JumpTarget {
        var merged = incoming
        if merged.terminalSessionID == nil,
           let existingID = existing?.terminalSessionID,
           !existingID.isEmpty {
            merged.terminalSessionID = existingID
        }
        if merged.warpPaneUUID == nil,
           let existingUUID = existing?.warpPaneUUID,
           !existingUUID.isEmpty {
            merged.warpPaneUUID = existingUUID
        }
        return merged
    }

    private func synchronizeClaudeJumpTarget(for payload: ClaudeHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let jumpTarget = Self.mergeJumpTargetPreservingExistingResolvedFields(
            incoming: payload.defaultJumpTarget,
            existing: existingSession.jumpTarget
        )

        guard existingSession.jumpTarget != jumpTarget else {
            return
        }

        emit(
            .jumpTargetUpdated(
                JumpTargetUpdated(
                    sessionID: payload.sessionID,
                    jumpTarget: jumpTarget,
                    timestamp: .now
                )
            )
        )
    }

    private func synchronizeClaudeMetadata(for payload: ClaudeHookPayload) {
        guard let existingSession = localState.session(id: payload.sessionID) else {
            return
        }

        let mergedMetadata = mergedClaudeMetadata(
            existing: existingSession.claudeMetadata,
            update: payload.defaultClaudeMetadata,
            hookEventName: payload.hookEventName
        )
        guard !mergedMetadata.isEmpty else {
            return
        }

        guard existingSession.claudeMetadata != mergedMetadata else {
            return
        }

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: payload.sessionID,
                    claudeMetadata: mergedMetadata,
                    timestamp: .now
                )
            )
        )
    }

    private func mergedCodexMetadata(
        existing: CodexSessionMetadata?,
        update: CodexSessionMetadata,
        hookEventName: CodexHookEventName
    ) -> CodexSessionMetadata {
        CodexSessionMetadata(
            transcriptPath: update.transcriptPath ?? existing?.transcriptPath,
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentCommandPreview: mergedCurrentCommandPreview(
                existing: existing?.currentCommandPreview,
                update: update.currentCommandPreview,
                hookEventName: hookEventName
            )
        )
    }

    private func mergedCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: CodexHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .userPromptSubmit, .postToolUse, .stop:
            return nil
        case .sessionStart, .preToolUse:
            return existing
        }
    }

    private func mergedClaudeMetadata(
        existing: ClaudeSessionMetadata?,
        update: ClaudeSessionMetadata,
        hookEventName: ClaudeHookEventName
    ) -> ClaudeSessionMetadata {
        ClaudeSessionMetadata(
            transcriptPath: update.transcriptPath ?? existing?.transcriptPath,
            initialUserPrompt: existing?.initialUserPrompt ?? update.initialUserPrompt ?? update.lastUserPrompt,
            lastUserPrompt: update.lastUserPrompt ?? existing?.lastUserPrompt,
            lastAssistantMessage: update.lastAssistantMessage ?? existing?.lastAssistantMessage,
            currentTool: mergedClaudeCurrentTool(
                existing: existing?.currentTool,
                update: update.currentTool,
                hookEventName: hookEventName
            ),
            currentToolInputPreview: mergedClaudeCurrentToolInputPreview(
                existing: existing?.currentToolInputPreview,
                update: update.currentToolInputPreview,
                hookEventName: hookEventName
            ),
            model: update.model ?? existing?.model,
            startupSource: update.startupSource ?? existing?.startupSource,
            permissionMode: update.permissionMode ?? existing?.permissionMode,
            agentID: update.agentID ?? existing?.agentID,
            agentType: update.agentType ?? existing?.agentType,
            worktreeBranch: update.worktreeBranch ?? existing?.worktreeBranch,
            activeSubagents: existing?.activeSubagents ?? [],
            activeTasks: existing?.activeTasks ?? []
        )
    }

    private func addSubagent(_ subagent: ClaudeSubagentInfo, toSession sessionID: String) {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata else {
            return
        }

        metadata.activeSubagents.removeAll { $0.agentID == subagent.agentID }
        metadata.activeSubagents.append(subagent)

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )
    }

    private func removeSubagent(agentID: String, fromSession sessionID: String) {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata else {
            return
        }

        metadata.activeSubagents.removeAll { $0.agentID == agentID }

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )
    }

    /// Removes subagents that have been inactive for too long.
    /// Called on each hook event from the parent session as a fallback
    /// in case `SubagentStop` was never received (e.g. hook connection dropped).
    private static let subagentStaleTimeout: TimeInterval = 3 * 60  // 3 minutes

    private func cleanUpStaleSubagents(forSession sessionID: String) {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata,
              !metadata.activeSubagents.isEmpty else {
            return
        }

        let now = Date.now
        let before = metadata.activeSubagents.count
        metadata.activeSubagents.removeAll { sub in
            guard let started = sub.startedAt else { return false }
            return now.timeIntervalSince(started) > Self.subagentStaleTimeout
        }

        guard metadata.activeSubagents.count != before else { return }

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )
    }

    /// Clears all active subagents from the session.
    /// Called when the session's turn ends (`stop`, `stopFailure`, `sessionEnd`)
    /// to ensure no stale subagent indicators linger.
    private func clearAllActiveSubagents(fromSession sessionID: String) {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata,
              !metadata.activeSubagents.isEmpty else {
            return
        }

        metadata.activeSubagents.removeAll()

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )
    }

    /// Returns the temporary task ID if a task was created, nil otherwise.
    @discardableResult
    private func updateTask(
        from input: [String: ClaudeHookJSONValue],
        toolName: String,
        sessionID: String
    ) -> String? {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata else {
            return nil
        }

        var createdID: String?

        if toolName == "TaskCreate" {
            guard case let .string(title) = input["subject"] ?? input["description"] else { return nil }
            let id = (input["id"]).flatMap { if case let .string(s) = $0 { s } else { nil } }
                ?? UUID().uuidString
            let statusStr = (input["status"]).flatMap { if case let .string(s) = $0 { s } else { nil } }
            let status = statusStr.flatMap { ClaudeTaskInfo.Status(rawValue: $0) } ?? .pending
            metadata.activeTasks.append(ClaudeTaskInfo(id: id, title: title, status: status))
            createdID = id
        } else if toolName == "TaskUpdate" {
            // Claude Code sends "taskId" (camelCase) in TaskUpdate tool_input
            let taskId: String? = (input["taskId"] ?? input["task_id"] ?? input["id"]).flatMap {
                if case let .string(s) = $0 { s } else { nil }
            }
            guard let taskId else { return nil }
            if let idx = metadata.activeTasks.firstIndex(where: { $0.id == taskId }) {
                if let statusStr = (input["status"]).flatMap({ if case let .string(s) = $0 { s } else { nil } }),
                   let status = ClaudeTaskInfo.Status(rawValue: statusStr) {
                    metadata.activeTasks[idx].status = status
                }
            }
        }

        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )

        return createdID
    }

    /// Replace a temporary task ID with the real ID from the TaskCreate tool response.
    private func replaceTaskID(
        sessionID: String,
        tempID: String,
        response: ClaudeHookJSONValue?
    ) {
        guard var metadata = localState.session(id: sessionID)?.claudeMetadata,
              let idx = metadata.activeTasks.firstIndex(where: { $0.id == tempID }) else {
            return
        }

        // Try to extract the real task ID from the tool response.
        // Actual response format: {"task": {"id": "7", "subject": "..."}}
        let realID: String? = {
            switch response {
            case let .object(obj):
                // Primary: nested under "task" object — {"task": {"id": "7"}}
                if case let .object(taskObj) = obj["task"],
                   let idVal = taskObj["id"] ?? taskObj["taskId"] {
                    if case let .string(s) = idVal { return s }
                    if case let .number(n) = idVal { return String(Int(n)) }
                }
                // Fallback: top-level "taskId", "task_id", "id"
                return (obj["taskId"] ?? obj["task_id"] ?? obj["id"]).flatMap {
                    if case let .string(s) = $0 { s } else { nil }
                }
            case let .string(s):
                // Fallback for string responses like "Task #7 created successfully"
                if let idRange = s.range(of: #"(?<=Task #)\S+"#, options: .regularExpression) {
                    return String(s[idRange])
                }
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            default:
                return nil
            }
        }()

        guard let realID, !realID.isEmpty else { return }

        metadata.activeTasks[idx].id = realID
        emit(
            .claudeSessionMetadataUpdated(
                ClaudeSessionMetadataUpdated(
                    sessionID: sessionID,
                    claudeMetadata: metadata,
                    timestamp: .now
                )
            )
        )
    }

    private func mergedClaudeCurrentTool(
        existing: String?,
        update: String?,
        hookEventName: ClaudeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .postToolUseFailure, .permissionDenied, .stop, .stopFailure, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .notification, .subagentStart, .subagentStop, .preCompact:
            return existing
        }
    }

    private func mergedClaudeCurrentToolInputPreview(
        existing: String?,
        update: String?,
        hookEventName: ClaudeHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .postToolUse, .postToolUseFailure, .permissionDenied, .stop, .stopFailure, .sessionEnd:
            return nil
        case .sessionStart, .userPromptSubmit, .preToolUse, .permissionRequest, .notification, .subagentStart, .subagentStop, .preCompact:
            return existing
        }
    }

    private func mergedCurrentCommandPreview(
        existing: String?,
        update: String?,
        hookEventName: CodexHookEventName
    ) -> String? {
        if let update {
            return update
        }

        switch hookEventName {
        case .userPromptSubmit, .postToolUse, .stop:
            return nil
        case .sessionStart, .preToolUse:
            return existing
        }
    }

    private func resolvePendingApproval(sessionID: String, approved: Bool) {
        guard let pendingApproval = pendingApprovals.removeValue(forKey: sessionID) else {
            return
        }

        let response: BridgeResponse
        if approved {
            response = .acknowledged
        } else {
            response = .codexHookDirective(.deny(reason: "Permission denied in Open Island."))
        }

        send(.response(response), to: pendingApproval.clientID)
    }

    private func resolvePendingClaudeInteraction(
        sessionID: String,
        resolution: PermissionResolution
    ) {
        guard let pendingInteraction = pendingClaudeInteractions.removeValue(forKey: sessionID) else {
            return
        }

        let directive: ClaudeHookDirective
        let summary: String
        let phase: SessionPhase

        switch (pendingInteraction.kind, resolution) {
        case let (.permission(payload), .allowOnce(updatedInput, updatedPermissions)):
            let finalInput = updatedInput ?? payload.toolInput
            directive = .permissionRequest(
                .allow(updatedInput: finalInput, updatedPermissions: updatedPermissions)
            )
            summary = payload.toolName.map { "Permission approved for \($0)." } ?? "Permission approved."
            phase = .running

        case let (.permission(_), .deny(message, interrupt)):
            directive = .permissionRequest(
                .deny(message: message ?? "Permission denied in Open Island.", interrupt: interrupt)
            )
            summary = message ?? "Permission denied in Open Island."
            phase = .completed

        case let (.question(payload, _), .allowOnce(updatedInput, updatedPermissions)):
            let finalInput = updatedInput ?? payload.toolInput
            directive = .permissionRequest(
                .allow(updatedInput: finalInput, updatedPermissions: updatedPermissions)
            )
            summary = "\(payload.resolvedAgentTool.displayName)'s questions were answered."
            phase = .running

        case let (.question(payload, _), .deny(message, interrupt)):
            let fallback = "Declined to answer \(payload.resolvedAgentTool.displayName)'s questions."
            directive = .permissionRequest(
                .deny(message: message ?? fallback, interrupt: interrupt)
            )
            summary = message ?? fallback
            phase = .completed
        }

        emit(
            phase == .completed
                ? .sessionCompleted(
                    SessionCompleted(
                        sessionID: sessionID,
                        summary: summary,
                        timestamp: .now
                    )
                )
                : .activityUpdated(
                    SessionActivityUpdated(
                        sessionID: sessionID,
                        summary: summary,
                        phase: phase,
                        timestamp: .now
                    )
                )
        )

        send(.response(.claudeHookDirective(directive)), to: pendingInteraction.clientID)
    }

    private func resolvePendingClaudeQuestion(
        sessionID: String,
        response: QuestionPromptResponse
    ) {
        guard let pendingInteraction = pendingClaudeInteractions.removeValue(forKey: sessionID) else {
            return
        }

        guard case let .question(payload, prompt) = pendingInteraction.kind else {
            return
        }

        let updatedInput = mergedClaudeQuestionInput(
            payload: payload,
            prompt: prompt,
            response: response
        )
        let summary = response.displaySummary.isEmpty
            ? "Answered \(payload.resolvedAgentTool.displayName)'s questions."
            : "Answered: \(response.displaySummary)"

        emit(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: sessionID,
                    summary: summary,
                    phase: .running,
                    timestamp: .now
                )
            )
        )

        send(
            .response(
                .claudeHookDirective(
                    .permissionRequest(.allow(updatedInput: updatedInput))
                )
            ),
            to: pendingInteraction.clientID
        )
    }

    private func claudeToolUseID(for payload: ClaudeHookPayload) -> String? {
        payload.toolUseID ?? pendingClaudeToolContexts[payload.permissionCorrelationKey]?.toolUseID
    }

    private func mergedClaudeQuestionInput(
        payload: ClaudeHookPayload,
        prompt: QuestionPrompt,
        response: QuestionPromptResponse
    ) -> ClaudeHookJSONValue {
        let fallbackQuestion = prompt.questions.first?.question

        var answers = response.answers
        if answers.isEmpty,
           let rawAnswer = response.rawAnswer,
           !rawAnswer.isEmpty,
           let fallbackQuestion {
            answers[fallbackQuestion] = rawAnswer
        }

        var annotationsObject: [String: ClaudeHookJSONValue] = [:]
        for key in response.annotations.keys.sorted() {
            guard let annotation = response.annotations[key] else {
                continue
            }

            var object: [String: ClaudeHookJSONValue] = [:]
            if let preview = annotation.preview, !preview.isEmpty {
                object["preview"] = .string(preview)
            }
            if let notes = annotation.notes, !notes.isEmpty {
                object["notes"] = .string(notes)
            }
            if !object.isEmpty {
                annotationsObject[key] = .object(object)
            }
        }

        guard case let .object(existingObject) = payload.toolInput else {
            return .object([
                "answers": .object(answers.mapValues { .string($0) }),
                "annotations": .object(annotationsObject),
            ])
        }

        var updatedObject = existingObject
        updatedObject["answers"] = .object(answers.mapValues { .string($0) })
        if !annotationsObject.isEmpty {
            updatedObject["annotations"] = .object(annotationsObject)
        }

        return .object(updatedObject)
    }

    private func emit(_ event: AgentEvent) {
        localState.apply(event)
        broadcast([.event(event)])
    }

    // MARK: - Bounded pending-interaction insertion (M1)

    /// FIFO-bounded insert into `pendingApprovals`. Evicts the oldest
    /// entry once `BridgeSecurity.maxPendingInteractions` is exceeded.
    private func putPendingApproval(sessionID: String, approval: PendingApproval) {
        if pendingApprovals[sessionID] == nil {
            pendingApprovalOrder.append(sessionID)
        }
        pendingApprovals[sessionID] = approval
        evictOldestPending(
            map: &pendingApprovals,
            order: &pendingApprovalOrder,
            label: "approvals"
        )
    }

    private func putPendingClaudeInteraction(sessionID: String, interaction: PendingClaudeInteraction) {
        if pendingClaudeInteractions[sessionID] == nil {
            pendingClaudeInteractionOrder.append(sessionID)
        }
        pendingClaudeInteractions[sessionID] = interaction
        evictOldestPending(
            map: &pendingClaudeInteractions,
            order: &pendingClaudeInteractionOrder,
            label: "claude"
        )
    }

    private func putPendingOpenCodeInteraction(sessionID: String, interaction: PendingOpenCodeInteraction) {
        if pendingOpenCodeInteractions[sessionID] == nil {
            pendingOpenCodeInteractionOrder.append(sessionID)
        }
        pendingOpenCodeInteractions[sessionID] = interaction
        evictOldestPending(
            map: &pendingOpenCodeInteractions,
            order: &pendingOpenCodeInteractionOrder,
            label: "opencode"
        )
    }

    private func putPendingCursorInteraction(sessionID: String, interaction: PendingCursorInteraction) {
        if pendingCursorInteractions[sessionID] == nil {
            pendingCursorInteractionOrder.append(sessionID)
        }
        pendingCursorInteractions[sessionID] = interaction
        evictOldestPending(
            map: &pendingCursorInteractions,
            order: &pendingCursorInteractionOrder,
            label: "cursor"
        )
    }

    private func evictOldestPending<Value>(
        map: inout [String: Value],
        order: inout [String],
        label: String
    ) {
        while map.count > BridgeSecurity.maxPendingInteractions, let oldest = order.first {
            order.removeFirst()
            if map.removeValue(forKey: oldest) != nil {
                BridgeServer.logSecurityEvent(
                    "bridge: evicted oldest pending \(label) interaction (sessionID=\(oldest))"
                )
            }
        }
    }

    private func hasSession(id: String) -> Bool {
        localState.session(id: id) != nil || localState.session(id: id) != nil
    }

    private func send(_ envelope: BridgeEnvelope, to clientID: UUID) {
        guard let client = clients[clientID] else {
            return
        }

        do {
            let data = try BridgeCodec.encodeLine(envelope)
            try writeAll(data, to: client.fileDescriptor)
        } catch {
            removeClient(clientID)
        }
    }

    private func broadcast(_ envelopes: [BridgeEnvelope]) {
        let clientIDs = Array(clients.keys)

        for clientID in clientIDs {
            for envelope in envelopes {
                send(envelope, to: clientID)
            }
        }
    }

    private func removeClient(_ clientID: UUID) {
        guard let client = clients.removeValue(forKey: clientID) else {
            return
        }

        let pendingSessionIDs = pendingApprovals.compactMap { entry -> String? in
            let (sessionID, pendingApproval) = entry
            return pendingApproval.clientID == clientID ? sessionID : nil
        }

        for sessionID in pendingSessionIDs {
            pendingApprovals.removeValue(forKey: sessionID)
            pendingApprovalOrder.removeAll(where: { $0 == sessionID })
        }

        let pendingClaudeSessionIDs = pendingClaudeInteractions.compactMap { entry -> String? in
            let (sessionID, pendingInteraction) = entry
            return pendingInteraction.clientID == clientID ? sessionID : nil
        }

        for sessionID in pendingClaudeSessionIDs {
            pendingClaudeInteractions.removeValue(forKey: sessionID)
            pendingClaudeInteractionOrder.removeAll(where: { $0 == sessionID })
            emit(
                .actionableStateResolved(
                    ActionableStateResolved(
                        sessionID: sessionID,
                        summary: "Hook process disconnected.",
                        timestamp: .now
                    )
                )
            )
        }

        let pendingOpenCodeSessionIDs = pendingOpenCodeInteractions.compactMap { entry -> String? in
            let (sessionID, pendingInteraction) = entry
            return pendingInteraction.clientID == clientID ? sessionID : nil
        }

        for sessionID in pendingOpenCodeSessionIDs {
            pendingOpenCodeInteractions.removeValue(forKey: sessionID)
            pendingOpenCodeInteractionOrder.removeAll(where: { $0 == sessionID })
            emit(
                .actionableStateResolved(
                    ActionableStateResolved(
                        sessionID: sessionID,
                        summary: "Plugin process disconnected.",
                        timestamp: .now
                    )
                )
            )
        }

        let pendingCursorSessionIDs = pendingCursorInteractions.compactMap { entry -> String? in
            let (sessionID, pendingInteraction) = entry
            return pendingInteraction.clientID == clientID ? sessionID : nil
        }

        for sessionID in pendingCursorSessionIDs {
            pendingCursorInteractions.removeValue(forKey: sessionID)
            pendingCursorInteractionOrder.removeAll(where: { $0 == sessionID })
            emit(
                .actionableStateResolved(
                    ActionableStateResolved(
                        sessionID: sessionID,
                        summary: "Hook process disconnected.",
                        timestamp: .now
                    )
                )
            )
        }

        client.readSource.cancel()
    }
}
