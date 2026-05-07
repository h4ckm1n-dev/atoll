import Foundation
import os

/// Monitors AppModel state changes and relays relevant events to the WatchHTTPEndpoint as SSE pushes.
/// Also handles resolution callbacks from the Watch/iPhone back to the bridge.
///
/// All routine push-event log lines are emitted at `debug` level (so they're not
/// persisted by the unified logging system) and every interpolated value is
/// marked `privacy: .private` to avoid leaking session/request identifiers.
public final class WatchNotificationRelay: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.atoll", category: "WatchNotificationRelay")

    public let endpoint: WatchHTTPEndpoint

    /// Callback to resolve a permission request (sessionID, approved).
    public var onResolvePermission: (@Sendable (_ sessionID: String, _ approved: Bool) -> Void)?

    /// Callback to answer a question (sessionID, answer).
    public var onAnswerQuestion: (@Sendable (_ sessionID: String, _ answer: String) -> Void)?

    /// Provider for looking up session by ID (needed to map requestID → sessionID).
    public var sessionLookup: (@Sendable (_ requestID: String) -> (sessionID: String, kind: PendingRequestKind)?)?

    public enum PendingRequestKind: Sendable {
        case permission
        case question
    }

    // Maps requestID → (sessionID, kind) for pending requests
    private let queue = DispatchQueue(label: "app.atoll.watch.relay")
    private var pendingRequests: [String: (sessionID: String, kind: PendingRequestKind)] = [:]

    public init(endpoint: WatchHTTPEndpoint = WatchHTTPEndpoint()) {
        self.endpoint = endpoint
        setupResolutionHandler()
    }

    // MARK: - Event Notification

    /// Called by AppModel after applying a tracked event. Filters for events that should
    /// be pushed to the Watch and constructs the appropriate SSE event.
    public func notifyEvent(_ event: AgentEvent, session: AgentSession?) {
        switch event {
        case let .permissionRequested(payload):
            guard let session else { return }
            let requestID = payload.request.id.uuidString
            trackPendingRequest(requestID: requestID, sessionID: payload.sessionID, kind: .permission)

            let sseEvent = WatchSSEEvent.permissionRequested(WatchPermissionEvent(
                sessionID: payload.sessionID,
                agentTool: session.tool.displayName,
                title: payload.request.title,
                summary: payload.request.summary,
                workingDirectory: session.jumpTarget?.workingDirectory,
                primaryAction: payload.request.primaryActionTitle,
                secondaryAction: payload.request.secondaryActionTitle,
                requestID: requestID,
                challenge: WatchHTTPEndpoint.generateChallenge()
            ))
            endpoint.pushEvent(sseEvent)
            Self.logger.debug("Pushed permissionRequested for session \(payload.sessionID, privacy: .private)")

        case let .questionAsked(payload):
            guard let session else { return }
            let requestID = payload.prompt.id.uuidString
            trackPendingRequest(requestID: requestID, sessionID: payload.sessionID, kind: .question)

            let sseEvent = WatchSSEEvent.questionAsked(WatchQuestionEvent(
                sessionID: payload.sessionID,
                agentTool: session.tool.displayName,
                title: payload.prompt.title,
                options: payload.prompt.options,
                requestID: requestID,
                challenge: WatchHTTPEndpoint.generateChallenge()
            ))
            endpoint.pushEvent(sseEvent)
            Self.logger.debug("Pushed questionAsked for session \(payload.sessionID, privacy: .private)")

        case let .sessionCompleted(payload):
            guard let session else { return }
            let sseEvent = WatchSSEEvent.sessionCompleted(WatchCompletionEvent(
                sessionID: payload.sessionID,
                agentTool: session.tool.displayName,
                summary: payload.summary
            ))
            endpoint.pushEvent(sseEvent)
            Self.logger.debug("Pushed sessionCompleted for session \(payload.sessionID, privacy: .private)")

        case let .actionableStateResolved(payload):
            // Find and remove any pending request for this session, then notify iPhone
            let requestID = removePendingRequestBySession(sessionID: payload.sessionID)
            if let requestID {
                let resolvedEvent = WatchSSEEvent.actionableStateResolved(WatchResolvedEvent(
                    requestID: requestID,
                    sessionID: payload.sessionID
                ))
                endpoint.pushEvent(resolvedEvent)
                Self.logger.debug("Pushed actionableStateResolved for request \(requestID, privacy: .private)")
            } else {
                Self.logger.debug("No pending request found for resolved session \(payload.sessionID, privacy: .private)")
            }

        default:
            break
        }
    }

    // MARK: - Lifecycle

    public func start() {
        endpoint.start()
    }

    public func stop() {
        endpoint.stop()
    }

    // MARK: - Private

    private func trackPendingRequest(requestID: String, sessionID: String, kind: PendingRequestKind) {
        queue.sync {
            pendingRequests[requestID] = (sessionID: sessionID, kind: kind)
        }
    }

    private func lookupPendingRequest(requestID: String) -> (sessionID: String, kind: PendingRequestKind)? {
        queue.sync {
            pendingRequests.removeValue(forKey: requestID)
        }
    }

    /// Finds and removes a pending request by sessionID. Returns the requestID if found.
    private func removePendingRequestBySession(sessionID: String) -> String? {
        queue.sync {
            guard let entry = pendingRequests.first(where: { $0.value.sessionID == sessionID }) else {
                return nil
            }
            pendingRequests.removeValue(forKey: entry.key)
            return entry.key
        }
    }

    private func setupResolutionHandler() {
        endpoint.onResolution = { [weak self] resolution in
            guard let self else { return }

            guard let pending = self.lookupPendingRequest(requestID: resolution.requestID)
                    ?? self.sessionLookup?(resolution.requestID) else {
                Self.logger.debug("Resolution for unknown requestID: \(resolution.requestID, privacy: .private)")
                return
            }

            switch pending.kind {
            case .permission:
                let approved = resolution.action.lowercased() == "allow"
                Self.logger.debug("Resolving permission for session \(pending.sessionID, privacy: .private): \(resolution.action, privacy: .private)")
                self.onResolvePermission?(pending.sessionID, approved)

            case .question:
                Self.logger.debug("Answering question for session \(pending.sessionID, privacy: .private): \(resolution.action, privacy: .private)")
                self.onAnswerQuestion?(pending.sessionID, resolution.action)
            }
        }
    }
}
