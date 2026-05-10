import Foundation

public enum StreamOverlayStatus: String, Codable, Sendable {
    case running
    case attention
    case completed
    case idle
}

public struct StreamOverlaySession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var tool: String
    public var status: StreamOverlayStatus
    public var statusLabel: String
    public var headline: String
    public var detail: String
    public var workspace: String
    public var terminal: String?
    public var currentTool: String?
    public var updatedAt: Date

    public init(
        id: String,
        tool: String,
        status: StreamOverlayStatus,
        statusLabel: String,
        headline: String,
        detail: String,
        workspace: String,
        terminal: String? = nil,
        currentTool: String? = nil,
        updatedAt: Date
    ) {
        self.id = id
        self.tool = tool
        self.status = status
        self.statusLabel = statusLabel
        self.headline = headline
        self.detail = detail
        self.workspace = workspace
        self.terminal = terminal
        self.currentTool = currentTool
        self.updatedAt = updatedAt
    }
}

public struct StreamOverlaySnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var liveSessionCount: Int
    public var attentionCount: Int
    public var runningCount: Int
    public var sessions: [StreamOverlaySession]

    public init(
        generatedAt: Date,
        liveSessionCount: Int,
        attentionCount: Int,
        runningCount: Int,
        sessions: [StreamOverlaySession]
    ) {
        self.generatedAt = generatedAt
        self.liveSessionCount = liveSessionCount
        self.attentionCount = attentionCount
        self.runningCount = runningCount
        self.sessions = sessions
    }

    public static var empty: StreamOverlaySnapshot {
        StreamOverlaySnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            liveSessionCount: 0,
            attentionCount: 0,
            runningCount: 0,
            sessions: []
        )
    }

    public static func make(
        from sessions: [AgentSession],
        maxSessions: Int = 4,
        generatedAt: Date = Date(),
        visibleTextRedactor: @Sendable (String) -> String = { $0 }
    ) -> StreamOverlaySnapshot {
        let visible = sessions.filter(\.isVisibleInIsland)
        let ordered = visible.sorted { lhs, rhs in
            let leftRank = rank(lhs)
            let rightRank = rank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        return StreamOverlaySnapshot(
            generatedAt: generatedAt,
            liveSessionCount: visible.count,
            attentionCount: visible.filter { $0.phase.requiresAttention }.count,
            runningCount: visible.filter { $0.phase == .running }.count,
            sessions: ordered.prefix(max(0, maxSessions)).map {
                makeSession(from: $0, visibleTextRedactor: visibleTextRedactor)
            }
        )
    }

    private static func rank(_ session: AgentSession) -> Int {
        if session.phase.requiresAttention { return 0 }
        if session.phase == .running { return 1 }
        if session.phase == .completed { return 2 }
        return 3
    }

    private static func makeSession(
        from session: AgentSession,
        visibleTextRedactor: @Sendable (String) -> String
    ) -> StreamOverlaySession {
        let workspace = displayWorkspace(for: session)
        let prompt = session.latestUserPromptText ?? session.initialUserPromptText
        let rawHeadline = [workspace, prompt]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " · ")
        let rawDetail = detailText(for: session)
        let status = overlayStatus(for: session.phase)

        return StreamOverlaySession(
            id: session.id,
            tool: session.tool.displayName,
            status: status,
            statusLabel: statusLabel(for: session.phase),
            headline: visibleTextRedactor(rawHeadline.isEmpty ? session.title : rawHeadline)
                .truncatedForUI(maxBytes: 180),
            detail: visibleTextRedactor(rawDetail).truncatedForUI(maxBytes: 240),
            workspace: visibleTextRedactor(workspace).truncatedForUI(maxBytes: 120),
            terminal: session.jumpTarget?.terminalApp,
            currentTool: session.currentToolName.map { visibleTextRedactor($0).truncatedForUI(maxBytes: 80) },
            updatedAt: session.updatedAt
        )
    }

    private static func detailText(for session: AgentSession) -> String {
        if let request = session.permissionRequest?.summary,
           !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return request
        }
        if let question = session.questionPrompt?.title,
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return question
        }
        if let command = session.currentCommandPreviewText,
           !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return command
        }
        if let assistant = session.completionAssistantMessageText ?? session.lastAssistantMessageText,
           !assistant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return assistant
        }
        return session.summary
    }

    private static func displayWorkspace(for session: AgentSession) -> String {
        if let workspace = session.jumpTarget?.workspaceName,
           !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return workspace
        }

        let pieces = session.title.split(separator: "·", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if pieces.count == 2, !pieces[1].isEmpty {
            return pieces[1]
        }

        return session.title
    }

    private static func overlayStatus(for phase: SessionPhase) -> StreamOverlayStatus {
        switch phase {
        case .running:
            return .running
        case .waitingForApproval, .waitingForAnswer:
            return .attention
        case .completed:
            return .completed
        }
    }

    private static func statusLabel(for phase: SessionPhase) -> String {
        switch phase {
        case .running:
            return "Running"
        case .waitingForApproval:
            return "Needs approval"
        case .waitingForAnswer:
            return "Needs answer"
        case .completed:
            return "Completed"
        }
    }
}

public final class StreamOverlaySnapshotCache: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StreamOverlaySnapshot

    public init(snapshot: StreamOverlaySnapshot = .empty) {
        self.stored = snapshot
    }

    public func set(_ snapshot: StreamOverlaySnapshot) {
        lock.lock()
        stored = snapshot
        lock.unlock()
    }

    public func get() -> StreamOverlaySnapshot {
        lock.lock()
        let value = stored
        lock.unlock()
        return value
    }
}
