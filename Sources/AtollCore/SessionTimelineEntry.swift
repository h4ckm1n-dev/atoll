import Foundation

public enum SessionTimelineKind: String, Codable, Sendable {
    case sessionStarted
    case activity
    case permission
    case question
    case completion
    case jumpTarget
    case metadata
    case resolved
}

public struct SessionTimelineEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sessionID: String
    public var title: String
    public var tool: AgentTool?
    public var kind: SessionTimelineKind
    public var summary: String
    public var detail: String?
    public var timestamp: Date
    public var requiresAttention: Bool

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        title: String,
        tool: AgentTool? = nil,
        kind: SessionTimelineKind,
        summary: String,
        detail: String? = nil,
        timestamp: Date,
        requiresAttention: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.tool = tool
        self.kind = kind
        self.summary = summary
        self.detail = detail
        self.timestamp = timestamp
        self.requiresAttention = requiresAttention
    }

    public static func make(from event: AgentEvent, session: AgentSession? = nil) -> SessionTimelineEntry {
        switch event {
        case let .sessionStarted(payload):
            return SessionTimelineEntry(
                sessionID: payload.sessionID,
                title: session?.title ?? payload.title,
                tool: session?.tool ?? payload.tool,
                kind: .sessionStarted,
                summary: fallback(payload.summary, defaultValue: "Session started."),
                detail: session?.jumpTarget?.workspaceName,
                timestamp: payload.timestamp
            )

        case let .activityUpdated(payload):
            return SessionTimelineEntry(
                sessionID: payload.sessionID,
                title: session?.title ?? payload.sessionID,
                tool: session?.tool,
                kind: .activity,
                summary: fallback(payload.summary, defaultValue: payload.phase.displayName),
                timestamp: payload.timestamp,
                requiresAttention: payload.phase.requiresAttention
            )

        case let .permissionRequested(payload):
            return SessionTimelineEntry(
                sessionID: payload.sessionID,
                title: session?.title ?? payload.sessionID,
                tool: session?.tool,
                kind: .permission,
                summary: fallback(payload.request.summary, defaultValue: payload.request.title),
                detail: optional(payload.request.affectedPath),
                timestamp: payload.timestamp,
                requiresAttention: true
            )

        case let .questionAsked(payload):
            return SessionTimelineEntry(
                sessionID: payload.sessionID,
                title: session?.title ?? payload.sessionID,
                tool: session?.tool,
                kind: .question,
                summary: fallback(payload.prompt.title, defaultValue: "Agent question."),
                detail: questionDetail(for: payload.prompt),
                timestamp: payload.timestamp,
                requiresAttention: true
            )

        case let .sessionCompleted(payload):
            return SessionTimelineEntry(
                sessionID: payload.sessionID,
                title: session?.title ?? payload.sessionID,
                tool: session?.tool,
                kind: .completion,
                summary: fallback(payload.summary, defaultValue: "Session completed."),
                detail: payload.isInterrupt == true ? "Interrupted" : nil,
                timestamp: payload.timestamp
            )

        case let .jumpTargetUpdated(payload):
            return SessionTimelineEntry(
                sessionID: payload.sessionID,
                title: session?.title ?? payload.sessionID,
                tool: session?.tool,
                kind: .jumpTarget,
                summary: "Jump target updated to \(payload.jumpTarget.terminalApp).",
                detail: optional(payload.jumpTarget.workspaceName),
                timestamp: payload.timestamp
            )

        case let .sessionMetadataUpdated(payload):
            return metadataEntry(
                sessionID: payload.sessionID,
                title: session?.title,
                tool: session?.tool ?? .codex,
                currentTool: payload.codexMetadata.currentTool,
                lastMessage: payload.codexMetadata.lastAssistantMessage,
                fallback: "Codex session metadata updated.",
                timestamp: payload.timestamp
            )

        case let .claudeSessionMetadataUpdated(payload):
            return metadataEntry(
                sessionID: payload.sessionID,
                title: session?.title,
                tool: session?.tool ?? .claudeCode,
                currentTool: payload.claudeMetadata.currentTool,
                lastMessage: payload.claudeMetadata.lastAssistantMessage,
                fallback: "Claude session metadata updated.",
                timestamp: payload.timestamp
            )

        case let .geminiSessionMetadataUpdated(payload):
            return metadataEntry(
                sessionID: payload.sessionID,
                title: session?.title,
                tool: session?.tool ?? .geminiCLI,
                currentTool: nil,
                lastMessage: payload.geminiMetadata.lastAssistantMessage,
                fallback: "Gemini session metadata updated.",
                timestamp: payload.timestamp
            )

        case let .openCodeSessionMetadataUpdated(payload):
            return metadataEntry(
                sessionID: payload.sessionID,
                title: session?.title,
                tool: session?.tool ?? .openCode,
                currentTool: payload.openCodeMetadata.currentTool,
                lastMessage: payload.openCodeMetadata.lastAssistantMessage,
                fallback: "OpenCode session metadata updated.",
                timestamp: payload.timestamp
            )

        case let .cursorSessionMetadataUpdated(payload):
            return metadataEntry(
                sessionID: payload.sessionID,
                title: session?.title,
                tool: session?.tool ?? .cursor,
                currentTool: payload.cursorMetadata.currentTool,
                lastMessage: payload.cursorMetadata.lastAssistantMessage,
                fallback: "Cursor session metadata updated.",
                timestamp: payload.timestamp
            )

        case let .actionableStateResolved(payload):
            return SessionTimelineEntry(
                sessionID: payload.sessionID,
                title: session?.title ?? payload.sessionID,
                tool: session?.tool,
                kind: .resolved,
                summary: fallback(payload.summary, defaultValue: "Action resolved."),
                timestamp: payload.timestamp
            )
        }
    }

    private static func metadataEntry(
        sessionID: String,
        title: String?,
        tool: AgentTool,
        currentTool: String?,
        lastMessage: String?,
        fallback: String,
        timestamp: Date
    ) -> SessionTimelineEntry {
        let summary: String
        if let currentTool = optional(currentTool) {
            summary = "\(tool.displayName) is running \(currentTool)."
        } else {
            summary = Self.fallback(lastMessage, defaultValue: fallback)
        }

        return SessionTimelineEntry(
            sessionID: sessionID,
            title: title ?? sessionID,
            tool: tool,
            kind: .metadata,
            summary: summary,
            timestamp: timestamp
        )
    }

    private static func questionDetail(for prompt: QuestionPrompt) -> String? {
        if !prompt.questions.isEmpty {
            return "\(prompt.questions.count) question\(prompt.questions.count == 1 ? "" : "s")"
        }

        let options = prompt.options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !options.isEmpty else { return nil }
        return options.joined(separator: " / ")
    }

    private static func fallback(_ value: String?, defaultValue: String) -> String {
        optional(value) ?? defaultValue
    }

    private static func optional(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

public extension AgentEvent {
    var sessionID: String {
        switch self {
        case let .sessionStarted(payload):
            return payload.sessionID
        case let .activityUpdated(payload):
            return payload.sessionID
        case let .permissionRequested(payload):
            return payload.sessionID
        case let .questionAsked(payload):
            return payload.sessionID
        case let .sessionCompleted(payload):
            return payload.sessionID
        case let .jumpTargetUpdated(payload):
            return payload.sessionID
        case let .sessionMetadataUpdated(payload):
            return payload.sessionID
        case let .claudeSessionMetadataUpdated(payload):
            return payload.sessionID
        case let .geminiSessionMetadataUpdated(payload):
            return payload.sessionID
        case let .openCodeSessionMetadataUpdated(payload):
            return payload.sessionID
        case let .cursorSessionMetadataUpdated(payload):
            return payload.sessionID
        case let .actionableStateResolved(payload):
            return payload.sessionID
        }
    }
}
