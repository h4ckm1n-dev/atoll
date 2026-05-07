import CryptoKit
import Foundation
import Network
import Security
import os

// MARK: - Authenticated request envelope (HMAC) — security model
//
// Every authenticated HTTP request (everything except `POST /pair`) MUST carry:
//   • Authorization: Bearer <token>          — used to look up the WatchToken row
//   • X-Atoll-Timestamp: <unix-epoch-secs>   — rejected if drift > 60 s vs server clock
//   • X-Atoll-Nonce: <random hex string>     — rejected on replay (per-token TTL 90 s)
//   • X-Atoll-HMAC: <hex sha256>             — HMAC-SHA256 over
//                                              "<timestamp>\n<nonce>\n<METHOD>\n<path>\n<body>"
//                                              keyed by the bearer token bytes.
//
// The bearer token alone is never sufficient — without a fresh signed envelope
// the request is rejected with 401. The token is still used for *lookup* of the
// per-device record (see `WatchToken`); the HMAC binds method/path/body to the
// timestamp+nonce pair so a leaked token cannot be replayed.
//
// **Token lifecycle**:
// Tokens are kept in-memory only and forgotten on Atoll restart — every paired
// device must re-pair after a restart of the macOS app. There is no on-disk
// secret store. Tokens also idle-expire 30 days after `lastSeen` updates.
//
// **Migration note**: clients pinned to the previous header-less protocol
// (token only) will be rejected with 401 once this fix lands and must re-pair.
//
// TLS is intentionally NOT yet enabled — H6 is split: HMAC authenticates
// requests in this PR, NWParameters TLS + cert-pinning lives in a follow-up.

// MARK: - SSE Event Types

/// Events pushed to connected iPhone clients via Server-Sent Events.
public enum WatchSSEEvent: Sendable {
    case permissionRequested(WatchPermissionEvent)
    case questionAsked(WatchQuestionEvent)
    case sessionCompleted(WatchCompletionEvent)
    /// Sent when an actionable request (permission/question) has been resolved on the Mac side.
    case actionableStateResolved(WatchResolvedEvent)

    func sseString() -> String {
        switch self {
        case let .permissionRequested(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: permissionRequested\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .questionAsked(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: questionAsked\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .sessionCompleted(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: sessionCompleted\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        case let .actionableStateResolved(event):
            let data = (try? JSONEncoder().encode(event)) ?? Data()
            return "event: actionableStateResolved\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
        }
    }
}

public struct WatchPermissionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var title: String
    public var summary: String
    public var workingDirectory: String?
    public var primaryAction: String
    public var secondaryAction: String
    public var requestID: String
    /// 16-byte hex challenge that the Watch must echo on the matching `POST /resolution`.
    public var challenge: String
}

public struct WatchQuestionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var title: String
    public var options: [String]
    public var requestID: String
    /// 16-byte hex challenge that the Watch must echo on the matching `POST /resolution`.
    public var challenge: String
}

public struct WatchCompletionEvent: Codable, Sendable {
    public var sessionID: String
    public var agentTool: String
    public var summary: String
}

// MARK: - Resolved Event

/// Sent via SSE when an actionable request has been resolved on the Mac side.
public struct WatchResolvedEvent: Codable, Sendable {
    public var requestID: String
    public var sessionID: String

    public init(requestID: String, sessionID: String) {
        self.requestID = requestID
        self.sessionID = sessionID
    }
}

// MARK: - Resolution

public struct WatchResolutionRequest: Codable, Sendable {
    public var requestID: String
    public var action: String
    /// Echo of the challenge issued in the matching SSE event. Required.
    public var challenge: String

    public init(requestID: String, action: String, challenge: String) {
        self.requestID = requestID
        self.action = action
        self.challenge = challenge
    }
}

// MARK: - Pairing

public struct WatchPairRequest: Codable, Sendable {
    public var code: String
    /// Optional human-readable label (e.g. iOS device name). Falls back to "iPhone".
    public var deviceLabel: String?

    public init(code: String, deviceLabel: String? = nil) {
        self.code = code
        self.deviceLabel = deviceLabel
    }
}

public struct WatchPairResponse: Codable, Sendable {
    public var token: String
}

// MARK: - Status

public struct WatchStatusResponse: Codable, Sendable {
    public var connected: Bool
    public var activeSessionCount: Int
}

// MARK: - Token state

/// Per-device token record. Kept in-memory only; lost on app restart.
public struct WatchToken: Sendable, Equatable {
    public var deviceLabel: String
    public var issuedAt: Date
    public var lastSeen: Date

    public init(deviceLabel: String, issuedAt: Date, lastSeen: Date) {
        self.deviceLabel = deviceLabel
        self.issuedAt = issuedAt
        self.lastSeen = lastSeen
    }
}

/// Public read-only descriptor of a paired device, surfaced to the Settings UI.
public struct WatchDeviceInfo: Sendable, Equatable {
    public let token: String
    public let label: String
    public let issuedAt: Date
    public let lastSeen: Date
}

// MARK: - Pairing burn-state

/// Surfaced to the UI when too many wrong pairing attempts have happened
/// in the sliding window — the user must regenerate from Settings.
public enum WatchPairingCodeStatus: Sendable, Equatable {
    case active
    case burned // user must regenerate via Settings UI button
}

// MARK: - Resolution Handler

/// Callback invoked when the Watch/iPhone submits a resolution via `/resolution`.
public typealias WatchResolutionHandler = @Sendable (WatchResolutionRequest) -> Void

/// Callback to query current active session count for `/status`.
public typealias WatchActiveSessionCountProvider = @Sendable () -> Int

// MARK: - WatchHTTPEndpoint

/// A lightweight HTTP server embedded in the macOS app that enables iPhone/Watch communication.
///
/// **Binding**: defaults to loopback (`127.0.0.1`). LAN exposure (binding any
/// interface + Bonjour ad) is opt-in via `lanAdvertise` in UserDefaults.
///
/// **Auth**: `POST /pair` validates an 8-digit pairing code generated with
/// `SecRandomCopyBytes`. Every other endpoint requires HMAC-signed envelopes
/// (see file header). Bodies are capped at 4096 bytes; non-SSE requests have a
/// 10 s deadline; SSE clients are capped at 4 concurrent.
///
/// **Token lifecycle**: in-memory only, lost on app restart, idle-expire 30 days.
/// Surfaces `currentDevices()` for UI; `revoke(token:)` per-device; `revokeAllTokens()`
/// for the master kill switch.
public final class WatchHTTPEndpoint: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.atoll", category: "WatchHTTPEndpoint")
    private static let serviceType = "_openisland._tcp"
    private static let pairingCodeLength = 8
    private static let pairingCodeExpiry: TimeInterval = 120 // 2 minutes
    private static let maxBodyBytes = 4096
    private static let nonSSEDeadlineSeconds: Double = 10
    private static let maxSSEConnections = 4
    private static let hmacWindow: TimeInterval = 60
    private static let nonceTTL: TimeInterval = 90
    private static let tokenIdleExpiry: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private static let pairAttemptThreshold = 5
    private static let pairAttemptWindow: TimeInterval = 60
    private static let pairMinIntervalPerIP: TimeInterval = 1.0

    // UserDefaults keys
    public static let lanAdvertiseDefaultsKey = "atoll.watch.lanAdvertise"
    public static let bonjourShowMachineNameDefaultsKey = "atoll.watch.bonjourShowMachineName"

    private let queue = DispatchQueue(label: "app.atoll.watch.http", qos: .userInitiated)

    // Pairing state
    private var currentPairingCode: String = ""
    private var pairingCodeGeneratedAt: Date = .distantPast
    private var pairingStatus: WatchPairingCodeStatus = .active

    // Per-device tokens
    private var tokens: [String: WatchToken] = [:]

    // Per-token nonce-set for replay protection (timestamped for TTL eviction)
    private var nonceCache: [String: [String: Date]] = [:]

    // Per-resolution challenge: requestID -> challenge hex
    private var pendingChallenges: [String: String] = [:]

    // Per-IP rate limit + sliding 60 s wrong-attempt window for pairing
    private var lastPairAttempt: [String: Date] = [:]
    private var pairAttempts: [Date] = []

    // SSE connections
    private var sseConnections: [UUID: NWConnection] = [:]

    // Listener
    private var listener: NWListener?

    // Configuration knobs (read at start time)
    private var lanAdvertise: Bool = false
    private var bonjourShowMachineName: Bool = false

    /// Optional injection point — overrides the UserDefaults reads so tests don't
    /// need to mutate global state.
    public var lanAdvertiseOverride: Bool?
    public var bonjourShowMachineNameOverride: Bool?

    // Callbacks
    public var onResolution: WatchResolutionHandler?
    public var activeSessionCountProvider: WatchActiveSessionCountProvider?

    public init() {
        regeneratePairingCode()
    }

    // MARK: - Lifecycle

    public func start() {
        queue.async { [weak self] in
            self?.startListener()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            for (id, connection) in self.sseConnections {
                connection.cancel()
                self.sseConnections.removeValue(forKey: id)
            }
        }
    }

    // MARK: - Pairing Code

    /// Returns the current pairing code. Regenerates if expired.
    public func currentCode() -> String {
        queue.sync {
            if pairingStatus == .burned {
                return currentPairingCode
            }
            if Date().timeIntervalSince(pairingCodeGeneratedAt) > Self.pairingCodeExpiry {
                regeneratePairingCodeUnsafe()
            }
            return currentPairingCode
        }
    }

    /// Force-regenerate pairing code (thread-safe). Clears the burned state.
    public func regeneratePairingCode() {
        queue.sync {
            regeneratePairingCodeUnsafe()
        }
    }

    /// Current pairing code status, surfaced to the UI.
    public func pairingCodeStatus() -> WatchPairingCodeStatus {
        queue.sync { pairingStatus }
    }

    // MARK: - Tokens

    /// Snapshot of currently paired devices.
    public func currentDevices() -> [WatchDeviceInfo] {
        queue.sync {
            evictExpiredTokensUnsafe()
            return tokens.map { token, record in
                WatchDeviceInfo(
                    token: token,
                    label: record.deviceLabel,
                    issuedAt: record.issuedAt,
                    lastSeen: record.lastSeen
                )
            }
        }
    }

    /// Revoke a specific token (per-device unpair).
    public func revoke(token: String) {
        queue.sync {
            tokens.removeValue(forKey: token)
            nonceCache.removeValue(forKey: token)
        }
    }

    /// Revoke all paired tokens, forcing re-pairing.
    public func revokeAllTokens() {
        queue.sync {
            tokens.removeAll()
            nonceCache.removeAll()
        }
    }

    // MARK: - SSE Push

    /// Push an SSE event to all authenticated, connected clients.
    public func pushEvent(_ event: WatchSSEEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            // For permission/question events, register the issued challenge for replay protection.
            switch event {
            case let .permissionRequested(payload):
                self.pendingChallenges[payload.requestID] = payload.challenge
            case let .questionAsked(payload):
                self.pendingChallenges[payload.requestID] = payload.challenge
            default:
                break
            }
            let payload = event.sseString()
            guard let data = payload.data(using: .utf8) else { return }
            for (id, connection) in self.sseConnections {
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        Self.logger.warning("SSE send failed for \(id, privacy: .private): \(error.localizedDescription, privacy: .private)")
                    }
                })
            }
        }
    }

    /// Generate a fresh per-resolution challenge (16 random bytes hex). Public so
    /// the relay can stamp it onto outgoing events.
    public static func generateChallenge() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Private: Listener

    private func startListener() {
        do {
            // Read knobs (overrides win for tests).
            self.lanAdvertise = lanAdvertiseOverride ?? UserDefaults.standard.bool(forKey: Self.lanAdvertiseDefaultsKey)
            self.bonjourShowMachineName = bonjourShowMachineNameOverride ?? UserDefaults.standard.bool(forKey: Self.bonjourShowMachineNameDefaultsKey)

            let params = NWParameters.tcp
            params.requiredLocalEndpoint = lanAdvertise
                ? nil
                : NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

            let listener = try NWListener(using: params)

            // Bonjour advertising — only when LAN-advertise is opted in.
            if lanAdvertise {
                let baseName = "Atoll"
                let serviceName: String
                if bonjourShowMachineName, let host = Host.current().localizedName, !host.isEmpty {
                    serviceName = "\(baseName) — \(host)"
                } else {
                    serviceName = baseName
                }
                listener.service = NWListener.Service(
                    name: serviceName,
                    type: Self.serviceType
                )
            }

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = self?.listener?.port {
                        Self.logger.info("WatchHTTPEndpoint listening on port \(port.rawValue)")
                    }
                case let .failed(error):
                    Self.logger.error("WatchHTTPEndpoint listener failed: \(error.localizedDescription, privacy: .private)")
                    self?.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                        self?.startListener()
                    }
                case .cancelled:
                    Self.logger.info("WatchHTTPEndpoint listener cancelled")
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Self.logger.error("Failed to create NWListener: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Private: Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection, accumulated: Data(), deadline: nil)
    }

    /// Receives bytes until headers are complete, then either dispatches (GET/SSE)
    /// or buffers up to `Content-Length` bytes for POST. A single `DispatchWorkItem`
    /// armed at first byte enforces the 10 s non-SSE deadline; SSE handlers cancel it.
    private func receiveHTTPRequest(
        on connection: NWConnection,
        accumulated: Data,
        deadline: DispatchWorkItem?
    ) {
        let armedDeadline: DispatchWorkItem
        if let deadline {
            armedDeadline = deadline
        } else {
            let item = DispatchWorkItem { [weak connection] in
                Self.logger.debug("Connection deadline exceeded, closing")
                connection?.cancel()
            }
            queue.asyncAfter(deadline: .now() + Self.nonSSEDeadlineSeconds, execute: item)
            armedDeadline = item
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else {
                armedDeadline.cancel()
                return
            }
            if let error {
                Self.logger.debug("Connection receive error: \(error.localizedDescription, privacy: .private)")
                armedDeadline.cancel()
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let chunk = content { buffer.append(chunk) }

            if buffer.isEmpty {
                if isComplete {
                    armedDeadline.cancel()
                    connection.cancel()
                }
                return
            }

            // Parse headers if we have them.
            guard let headerEnd = self.findHeaderEnd(in: buffer) else {
                // Not yet — keep receiving.
                if buffer.count > 32_768 {
                    armedDeadline.cancel()
                    self.sendHTTPResponse(connection: connection, status: "431 Request Header Fields Too Large", body: #"{"error":"headers too large"}"#)
                    return
                }
                self.receiveHTTPRequest(on: connection, accumulated: buffer, deadline: armedDeadline)
                return
            }

            let headerData = buffer.prefix(headerEnd)
            guard let headerString = String(data: headerData, encoding: .utf8) else {
                armedDeadline.cancel()
                self.sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid request"}"#)
                return
            }

            let parsed = self.parseHTTPHeaders(headerString)
            // Reject duplicate headers (parser flags this).
            if parsed.duplicateHeader {
                armedDeadline.cancel()
                self.sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"duplicate header"}"#)
                return
            }
            // Reject paths with .. or non-ASCII control chars.
            if !self.isPathSafe(parsed.path) {
                armedDeadline.cancel()
                self.sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid path"}"#)
                return
            }
            // Reject chunked transfer encoding.
            if let te = parsed.headers["Transfer-Encoding"]?.lowercased() ?? parsed.headers["transfer-encoding"]?.lowercased(),
               te.contains("chunked") {
                armedDeadline.cancel()
                self.sendHTTPResponse(connection: connection, status: "411 Length Required", body: #"{"error":"chunked not supported"}"#)
                return
            }

            let bodySoFar = buffer.suffix(from: headerEnd)
            let contentLengthRaw = parsed.headers["Content-Length"] ?? parsed.headers["content-length"]
            let contentLength = contentLengthRaw.flatMap { Int($0) }

            // Method allowlist gate (M9). Any path/method outside the four allowed
            // routes — including OPTIONS — is rejected with 405 (M8).
            if !self.isAllowed(method: parsed.method, path: parsed.path) {
                armedDeadline.cancel()
                let status = parsed.method == "OPTIONS" ? "405 Method Not Allowed" : "405 Method Not Allowed"
                self.sendHTTPResponse(
                    connection: connection,
                    status: status,
                    body: #"{"error":"method not allowed"}"#,
                    extraHeaders: ["Allow": "POST, GET"]
                )
                return
            }

            if parsed.method == "POST" {
                // POST requires Content-Length.
                guard let cl = contentLength else {
                    armedDeadline.cancel()
                    self.sendHTTPResponse(connection: connection, status: "411 Length Required", body: #"{"error":"length required"}"#)
                    return
                }
                if cl > Self.maxBodyBytes {
                    armedDeadline.cancel()
                    self.sendHTTPResponse(connection: connection, status: "413 Payload Too Large", body: #"{"error":"body too large"}"#)
                    return
                }
                if bodySoFar.count >= cl {
                    armedDeadline.cancel()
                    let body = String(data: bodySoFar.prefix(cl), encoding: .utf8)
                    self.dispatch(method: parsed.method, path: parsed.path, headers: parsed.headers, body: body, connection: connection)
                    return
                }
                // Need more bytes for body.
                self.receivePOSTBody(
                    on: connection,
                    expected: cl,
                    accumulated: Data(bodySoFar),
                    headers: parsed.headers,
                    method: parsed.method,
                    path: parsed.path,
                    deadline: armedDeadline
                )
                return
            }

            // GET / SSE — cancel deadline only after dispatch (SSE handler clears it).
            self.dispatch(
                method: parsed.method,
                path: parsed.path,
                headers: parsed.headers,
                body: nil,
                connection: connection,
                deadline: armedDeadline
            )
        }
    }

    private func receivePOSTBody(
        on connection: NWConnection,
        expected: Int,
        accumulated: Data,
        headers: [String: String],
        method: String,
        path: String,
        deadline: DispatchWorkItem
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: max(1, expected - accumulated.count)) { [weak self] content, _, isComplete, error in
            guard let self else {
                deadline.cancel()
                return
            }
            if let error {
                deadline.cancel()
                Self.logger.debug("Body receive error: \(error.localizedDescription, privacy: .private)")
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let chunk = content { buffer.append(chunk) }

            if buffer.count > Self.maxBodyBytes || buffer.count > expected {
                deadline.cancel()
                self.sendHTTPResponse(connection: connection, status: "413 Payload Too Large", body: #"{"error":"body too large"}"#)
                return
            }
            if buffer.count >= expected {
                deadline.cancel()
                let body = String(data: buffer.prefix(expected), encoding: .utf8)
                self.dispatch(method: method, path: path, headers: headers, body: body, connection: connection)
                return
            }
            if isComplete {
                deadline.cancel()
                self.sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"truncated body"}"#)
                return
            }
            self.receivePOSTBody(
                on: connection,
                expected: expected,
                accumulated: buffer,
                headers: headers,
                method: method,
                path: path,
                deadline: deadline
            )
        }
    }

    // MARK: - Private: HTTP Routing

    private func dispatch(
        method: String,
        path: String,
        headers: [String: String],
        body: String?,
        connection: NWConnection,
        deadline: DispatchWorkItem? = nil
    ) {
        switch (method, path) {
        case ("POST", "/pair"):
            deadline?.cancel()
            handlePair(body: body, headers: headers, connection: connection)

        case ("GET", "/events"):
            handleEventsSSE(headers: headers, connection: connection, deadline: deadline)

        case ("POST", "/resolution"):
            deadline?.cancel()
            handleResolution(body: body, headers: headers, connection: connection, method: method, path: path)

        case ("GET", "/status"):
            deadline?.cancel()
            handleStatus(headers: headers, connection: connection, method: method, path: path)

        default:
            deadline?.cancel()
            sendHTTPResponse(
                connection: connection,
                status: "405 Method Not Allowed",
                body: #"{"error":"method not allowed"}"#,
                extraHeaders: ["Allow": "POST, GET"]
            )
        }
    }

    private func isAllowed(method: String, path: String) -> Bool {
        switch (method, path) {
        case ("POST", "/pair"), ("GET", "/events"), ("POST", "/resolution"), ("GET", "/status"):
            return true
        default:
            return false
        }
    }

    private func isPathSafe(_ path: String) -> Bool {
        if path.contains("..") { return false }
        for scalar in path.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F { return false }
            if scalar.value > 0x7F { return false }
        }
        return true
    }

    // MARK: - Private: Endpoint Handlers

    private func handlePair(body: String?, headers: [String: String], connection: NWConnection) {
        let peerIP = peerIP(from: connection)

        // Per-IP rate limit: 1 second between attempts.
        let now = Date()
        if let last = lastPairAttempt[peerIP], now.timeIntervalSince(last) < Self.pairMinIntervalPerIP {
            sendHTTPResponse(connection: connection, status: "429 Too Many Requests", body: #"{"error":"rate limited"}"#)
            return
        }
        lastPairAttempt[peerIP] = now

        // Sliding window for global attempt budget.
        evictPairAttemptsUnsafe(now: now)

        // If burned, refuse all attempts until the user regenerates.
        if pairingStatus == .burned {
            sendHTTPResponse(connection: connection, status: "423 Locked", body: #"{"error":"code burned, regenerate from Settings"}"#)
            return
        }

        guard let body, let bodyData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(WatchPairRequest.self, from: bodyData) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid body"}"#)
            return
        }

        // Check expiry (best-effort regenerate; still 410 for this request).
        if Date().timeIntervalSince(pairingCodeGeneratedAt) > Self.pairingCodeExpiry {
            regeneratePairingCodeUnsafe()
            sendHTTPResponse(connection: connection, status: "410 Gone", body: #"{"error":"pairing code expired"}"#)
            return
        }

        guard request.code == currentPairingCode else {
            pairAttempts.append(now)
            evictPairAttemptsUnsafe(now: now)
            if pairAttempts.count >= Self.pairAttemptThreshold {
                // Burn the code; do NOT auto-regenerate.
                pairingStatus = .burned
                Self.logger.warning("Pairing code burned after too many wrong attempts")
                sendHTTPResponse(connection: connection, status: "423 Locked", body: #"{"error":"code burned, regenerate from Settings"}"#)
                return
            }
            sendHTTPResponse(connection: connection, status: "403 Forbidden", body: #"{"error":"invalid pairing code"}"#)
            return
        }

        // Generate token using SecRandomCopyBytes for a 32-byte secret.
        var tokenBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, tokenBytes.count, &tokenBytes)
        precondition(status == errSecSuccess)
        let token = tokenBytes.map { String(format: "%02x", $0) }.joined()

        let label = (request.deviceLabel?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "iPhone"
        tokens[token] = WatchToken(deviceLabel: label, issuedAt: Date(), lastSeen: Date())

        // Regenerate pairing code after successful pair (also clears burn state).
        regeneratePairingCodeUnsafe()
        // Reset pair attempt counter — clean slate for the next code.
        pairAttempts.removeAll()

        let response = WatchPairResponse(token: token)
        if let responseData = try? JSONEncoder().encode(response),
           let responseString = String(data: responseData, encoding: .utf8) {
            sendHTTPResponse(connection: connection, status: "200 OK", body: responseString)
        }
    }

    private func handleEventsSSE(headers: [String: String], connection: NWConnection, deadline: DispatchWorkItem?) {
        guard let token = authenticatedToken(method: "GET", path: "/events", headers: headers, body: "") else {
            deadline?.cancel()
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }
        // Touch lastSeen.
        if var record = tokens[token] {
            record.lastSeen = Date()
            tokens[token] = record
        }

        // Concurrent SSE connection cap (M9).
        if sseConnections.count >= Self.maxSSEConnections {
            deadline?.cancel()
            sendHTTPResponse(connection: connection, status: "503 Service Unavailable", body: #"{"error":"too many sse clients"}"#)
            return
        }

        // SSE is long-lived — clear the request deadline.
        deadline?.cancel()

        // Send SSE headers and keep connection open. NOTE: no Access-Control-Allow-Origin.
        let sseHeaders = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        \r

        """

        guard let headerData = sseHeaders.data(using: .utf8) else { return }

        let connectionID = UUID()
        sseConnections[connectionID] = connection

        let queue = self.queue
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            if let error {
                Self.logger.warning("Failed to send SSE headers: \(error.localizedDescription, privacy: .private)")
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
                connection.cancel()
                return
            }
            // Send initial keepalive comment.
            guard let keepalive = ": connected\n\n".data(using: .utf8) else { return }
            connection.send(content: keepalive, completion: .contentProcessed { _ in })
        })

        // Monitor for disconnect.
        connection.viabilityUpdateHandler = { [weak self] isViable in
            if !isViable {
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
            }
        }

        // Detect connection close.
        monitorSSEConnection(connectionID: connectionID, connection: connection)
    }

    private func monitorSSEConnection(connectionID: UUID, connection: NWConnection) {
        let queue = self.queue
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                queue.async { [weak self] in
                    self?.sseConnections.removeValue(forKey: connectionID)
                }
                connection.cancel()
            } else {
                self?.monitorSSEConnection(connectionID: connectionID, connection: connection)
            }
        }
    }

    private func handleResolution(body: String?, headers: [String: String], connection: NWConnection, method: String, path: String) {
        guard let token = authenticatedToken(method: method, path: path, headers: headers, body: body ?? "") else {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }
        if var record = tokens[token] {
            record.lastSeen = Date()
            tokens[token] = record
        }

        guard let body, let bodyData = body.data(using: .utf8),
              let request = try? JSONDecoder().decode(WatchResolutionRequest.self, from: bodyData) else {
            sendHTTPResponse(connection: connection, status: "400 Bad Request", body: #"{"error":"invalid body"}"#)
            return
        }

        // Per-resolution challenge check (L11). Once consumed, second use → 410 Gone.
        guard let expected = pendingChallenges[request.requestID] else {
            sendHTTPResponse(connection: connection, status: "410 Gone", body: #"{"error":"unknown or consumed challenge"}"#)
            return
        }
        guard constantTimeEqual(expected, request.challenge) else {
            sendHTTPResponse(connection: connection, status: "403 Forbidden", body: #"{"error":"bad challenge"}"#)
            return
        }
        pendingChallenges.removeValue(forKey: request.requestID)

        onResolution?(request)
        sendHTTPResponse(connection: connection, status: "200 OK", body: #"{"status":"accepted"}"#)
    }

    private func handleStatus(headers: [String: String], connection: NWConnection, method: String, path: String) {
        guard let token = authenticatedToken(method: method, path: path, headers: headers, body: "") else {
            sendHTTPResponse(connection: connection, status: "401 Unauthorized", body: #"{"error":"unauthorized"}"#)
            return
        }
        if var record = tokens[token] {
            record.lastSeen = Date()
            tokens[token] = record
        }

        let response = WatchStatusResponse(
            connected: !sseConnections.isEmpty,
            activeSessionCount: activeSessionCountProvider?() ?? 0
        )

        if let responseData = try? JSONEncoder().encode(response),
           let responseString = String(data: responseData, encoding: .utf8) {
            sendHTTPResponse(connection: connection, status: "200 OK", body: responseString)
        }
    }

    // MARK: - Private: Auth + HMAC

    /// Verifies bearer token + HMAC envelope. Returns the looked-up token string on success.
    /// `body` is the literal request-body string used in the HMAC; pass empty string for GET.
    func authenticatedToken(method: String, path: String, headers: [String: String], body: String) -> String? {
        guard let auth = caseInsensitive(headers, "authorization"),
              auth.hasPrefix("Bearer ") else {
            return nil
        }
        let token = String(auth.dropFirst("Bearer ".count))

        // Token must exist (and not be idle-expired).
        evictExpiredTokensUnsafe()
        guard tokens[token] != nil else { return nil }

        guard let timestampHeader = caseInsensitive(headers, "x-atoll-timestamp"),
              let timestamp = TimeInterval(timestampHeader) else {
            return nil
        }
        if abs(Date().timeIntervalSince1970 - timestamp) > Self.hmacWindow {
            return nil
        }
        guard let nonce = caseInsensitive(headers, "x-atoll-nonce"), !nonce.isEmpty, nonce.count <= 128 else {
            return nil
        }
        guard let mac = caseInsensitive(headers, "x-atoll-hmac"), !mac.isEmpty else {
            return nil
        }

        // Replay protection: per-token nonce-set with TTL.
        var perToken = nonceCache[token] ?? [:]
        let now = Date()
        perToken = perToken.filter { _, seen in now.timeIntervalSince(seen) < Self.nonceTTL }
        if perToken[nonce] != nil { return nil }

        // Verify HMAC.
        let canonical = "\(timestampHeader)\n\(nonce)\n\(method)\n\(path)\n\(body)"
        guard let canonicalData = canonical.data(using: .utf8),
              let tokenKey = token.data(using: .utf8) else {
            return nil
        }
        let key = SymmetricKey(data: tokenKey)
        let computed = HMAC<SHA256>.authenticationCode(for: canonicalData, using: key)
        let computedHex = computed.map { String(format: "%02x", $0) }.joined()
        guard constantTimeEqual(computedHex, mac.lowercased()) else {
            return nil
        }

        // Commit nonce (after successful verify).
        perToken[nonce] = now
        nonceCache[token] = perToken
        return token
    }

    private func caseInsensitive(_ headers: [String: String], _ name: String) -> String? {
        if let v = headers[name] { return v }
        for (k, v) in headers where k.lowercased() == name.lowercased() {
            return v
        }
        return nil
    }

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8)
        let bb = Array(b.utf8)
        if ab.count != bb.count { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }

    private func peerIP(from connection: NWConnection) -> String {
        switch connection.endpoint {
        case let .hostPort(host, _):
            return "\(host)"
        default:
            return "unknown"
        }
    }

    // MARK: - Private: HTTP Helpers

    private func findHeaderEnd(in data: Data) -> Int? {
        // Look for CRLF CRLF; tolerate LF LF as fallback.
        let crlfcrlf: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        if let r = rangeOf(crlfcrlf, in: data) { return r.upperBound }
        let lflf: [UInt8] = [0x0A, 0x0A]
        if let r = rangeOf(lflf, in: data) { return r.upperBound }
        return nil
    }

    private func rangeOf(_ needle: [UInt8], in haystack: Data) -> Range<Int>? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let bytes = [UInt8](haystack)
        for i in 0...(bytes.count - needle.count) {
            var match = true
            for j in 0..<needle.count where bytes[i + j] != needle[j] {
                match = false
                break
            }
            if match { return i..<(i + needle.count) }
        }
        return nil
    }

    private struct ParsedHeaders {
        let method: String
        let path: String
        let headers: [String: String]
        let duplicateHeader: Bool
    }

    private func parseHTTPHeaders(_ raw: String) -> ParsedHeaders {
        let lines = raw.components(separatedBy: "\r\n").flatMap { $0.components(separatedBy: "\n") }
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return ParsedHeaders(method: "", path: "", headers: [:], duplicateHeader: false)
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2)
        let method = requestParts.count > 0 ? String(requestParts[0]) : ""
        let path = requestParts.count > 1 ? String(requestParts[1]) : ""

        var headers: [String: String] = [:]
        var duplicate = false
        for line in lines.dropFirst() {
            if line.isEmpty { continue }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                let lowerKey = key.lowercased()
                // Map under canonical (preserve original) — track duplicates by lower case.
                let alreadyPresent = headers.keys.contains(where: { $0.lowercased() == lowerKey })
                if alreadyPresent {
                    // Allow only if same value (some clients repeat with identical content).
                    if let existing = headers.first(where: { $0.key.lowercased() == lowerKey })?.value, existing != value {
                        duplicate = true
                    }
                } else {
                    headers[key] = value
                }
            }
        }
        return ParsedHeaders(method: method, path: path, headers: headers, duplicateHeader: duplicate)
    }

    private func sendHTTPResponse(
        connection: NWConnection,
        status: String,
        body: String,
        contentType: String = "application/json",
        extraHeaders: [String: String] = [:]
    ) {
        var headerLines = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n"
        for (k, v) in extraHeaders {
            headerLines += "\(k): \(v)\r\n"
        }
        let response = "\(headerLines)\r\n\(body)"

        guard let data = response.data(using: .utf8) else { return }
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Private: Pairing Code Generation

    /// Cryptographically random N-digit string. Uses `SecRandomCopyBytes` per
    /// the C1 fix; rejection sampling avoids the modulo bias for the first 250
    /// values of a `UInt8` (still negligible for digit generation but kept clean).
    private func cryptoRandomDigits(_ count: Int) -> String {
        var output = ""
        output.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: count * 2 + 4)
        var index = 0
        while output.count < count {
            if index >= buffer.count {
                let status = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
                precondition(status == errSecSuccess)
                index = 0
            } else if index == 0 {
                let status = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
                precondition(status == errSecSuccess)
            }
            let byte = buffer[index]
            index += 1
            // Reject sample to avoid modulo bias: 250..<256 are skipped.
            if byte >= 250 { continue }
            output.append(String(byte % 10))
        }
        return output
    }

    /// Must be called on `queue`.
    private func regeneratePairingCodeUnsafe() {
        currentPairingCode = cryptoRandomDigits(Self.pairingCodeLength)
        pairingCodeGeneratedAt = Date()
        pairingStatus = .active
        pairAttempts.removeAll()
        Self.logger.info("New pairing code generated")
    }

    private func evictPairAttemptsUnsafe(now: Date) {
        pairAttempts = pairAttempts.filter { now.timeIntervalSince($0) <= Self.pairAttemptWindow }
    }

    private func evictExpiredTokensUnsafe() {
        let now = Date()
        for (token, record) in tokens where now.timeIntervalSince(record.lastSeen) > Self.tokenIdleExpiry {
            tokens.removeValue(forKey: token)
            nonceCache.removeValue(forKey: token)
        }
    }
}

// MARK: - Test hooks

extension WatchHTTPEndpoint {
    /// Test-only: synchronously install a token for fixture setup. Production
    /// code paths only mutate via `handlePair` under the queue.
    func _installTokenForTesting(_ token: String, deviceLabel: String = "iPhone") {
        queue.sync {
            tokens[token] = WatchToken(deviceLabel: deviceLabel, issuedAt: Date(), lastSeen: Date())
        }
    }

    /// Test-only: register a challenge so a `/resolution` test can satisfy the L11 check.
    func _registerChallengeForTesting(requestID: String, challenge: String) {
        queue.sync {
            pendingChallenges[requestID] = challenge
        }
    }

    /// Test-only: synchronously read the burned status without going through `currentCode()`.
    func _pairingStatusForTesting() -> WatchPairingCodeStatus {
        queue.sync { pairingStatus }
    }

    /// Test-only: forcibly mark the bound token's `lastSeen` to `date` so we can test idle expiry.
    func _setLastSeenForTesting(token: String, lastSeen: Date) {
        queue.sync {
            guard var record = tokens[token] else { return }
            record.lastSeen = lastSeen
            tokens[token] = record
        }
    }

    /// Test-only: invoke `authenticatedToken` synchronously; bypasses the listener.
    func _authenticateForTesting(method: String, path: String, headers: [String: String], body: String) -> String? {
        queue.sync {
            authenticatedToken(method: method, path: path, headers: headers, body: body)
        }
    }

    /// Test-only: simulate a wrong-pair attempt against the in-memory state. No network IO.
    func _recordWrongPairAttemptForTesting() {
        queue.sync {
            let now = Date()
            pairAttempts.append(now)
            evictPairAttemptsUnsafe(now: now)
            if pairAttempts.count >= Self.pairAttemptThreshold {
                pairingStatus = .burned
            }
        }
    }

    /// Test-only: read the listener's current port (nil before `.ready`).
    func _listenerPortForTesting() -> NWEndpoint.Port? {
        queue.sync { listener?.port }
    }

    /// Test-only: expose the method-allowlist gate.
    func _isAllowedForTesting(method: String, path: String) -> Bool {
        isAllowed(method: method, path: path)
    }

    /// Test-only: expose the path-safety check.
    func _isPathSafeForTesting(_ path: String) -> Bool {
        isPathSafe(path)
    }
}
