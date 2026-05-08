import CoreGraphics
import Foundation
import AtollCore

struct IslandDebugSnapshot {
    let title: String
    let summary: String
    let previewHeight: CGFloat
    let notchStatus: NotchStatus
    let notchOpenReason: NotchOpenReason?
    let islandSurface: IslandSurface
    let sessions: [AgentSession]
    let selectedSessionID: String?
}

enum IslandDebugScenario: String, CaseIterable, Identifiable {
    case closed
    case sessionList
    case approvalCard
    case questionCard
    case completionCard
    case longCompletionCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .closed:
            "Closed Notch"
        case .sessionList:
            "Session List"
        case .approvalCard:
            "Approval Card"
        case .questionCard:
            "Question Card"
        case .completionCard:
            "Completion Card"
        case .longCompletionCard:
            "Long Completion Card"
        }
    }

    var summary: String {
        switch self {
        case .closed:
            "Collapsed idle/running notch with live count and attention affordance."
        case .sessionList:
            "Manual expanded list with running, active, and inactive session rows."
        case .approvalCard:
            "Auto-expanded permission surface with approve and deny actions."
        case .questionCard:
            "Auto-expanded question surface with selectable answer buttons."
        case .completionCard:
            "Auto-expanded finished-task reminder surface after a turn completes."
        case .longCompletionCard:
            "Long finished-task reply stays inside the card and scrolls internally."
        }
    }

    func snapshot(at now: Date = .now) -> IslandDebugSnapshot {
        switch self {
        case .closed:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 78,
                notchStatus: .closed,
                notchOpenReason: nil,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .sessionList:
            let sessions = DebugSessionFactory.listSessions(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 430,
                notchStatus: .opened,
                notchOpenReason: .click,
                islandSurface: .sessionList(),
                sessions: sessions,
                selectedSessionID: sessions.first?.id
            )

        case .approvalCard:
            let session = DebugSessionFactory.approvalSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 330,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .questionCard:
            let session = DebugSessionFactory.questionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 270,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .completionCard:
            let session = DebugSessionFactory.completionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 250,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )

        case .longCompletionCard:
            let session = DebugSessionFactory.longCompletionSession(now: now)
            return IslandDebugSnapshot(
                title: title,
                summary: summary,
                previewHeight: 290,
                notchStatus: .opened,
                notchOpenReason: .notification,
                islandSurface: .sessionList(actionableSessionID: session.id),
                sessions: DebugSessionFactory.notificationSessions(lead: session, now: now),
                selectedSessionID: session.id
            )
        }
    }
}

private enum DebugSessionFactory {
    static func listSessions(now: Date) -> [AgentSession] {
        [
            runningSession(now: now),
            recentCompletedSession(now: now),
            inactiveSession(
                id: "session-claude-research",
                workspace: "claude-research",
                initialPrompt: "I'd like to surface my usage in another app — what hooks does Claude Code expose?",
                latestPrompt: "Why would we hit Cursor's API for that? It's a different vendor.",
                assistant: "Don't pick by 'oldest' alone — the oldest model isn't necessarily the lightest fit.",
                age: 27 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-personal",
                workspace: "Personal",
                initialPrompt: "[Image #1] Here are 3 screenshots of models currently available in Cursor.",
                latestPrompt: "[Image #1] Here are 3 screenshots of models currently available in Cursor.",
                assistant: "The models in that screenshot aren't quite the right fit for `voice-input`…",
                age: 32 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-open-agent-sdk",
                workspace: "open-agent-sdk",
                initialPrompt: "OK, do you need to open a PR for this?",
                latestPrompt: "Go ahead and open the PR.",
                assistant: "PR is up:",
                age: 60 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-voice-input",
                workspace: "voice-input",
                initialPrompt: "Take a look at voice-input — I want to nail down model selection.",
                latestPrompt: "Strictly speaking, which model should it pick?",
                assistant: "If the goal is lightweight real-time, mapping Cursor's preset is the wrong starting point.",
                age: 78 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-agents",
                workspace: "agents",
                initialPrompt: "Show me your current branch and worktree.",
                latestPrompt: "So you're going to restart the dev process first?",
                assistant: "Restarted. The new dev process is now running.",
                age: 92 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-claude",
                workspace: "claude-code",
                initialPrompt: "Let's make the entire notch background pure black for now.",
                latestPrompt: "Drop the empty space below the panel.",
                assistant: "Expanded-state height now sizes to fit the content.",
                age: 118 * 60,
                now: now
            ),
            inactiveSession(
                id: "session-hooks",
                workspace: "hooks",
                initialPrompt: "How would I monitor Claude Code usage in real time?",
                latestPrompt: "What about surfacing that in a different app?",
                assistant: "There are a few more direct paths already in the codebase.",
                age: 130 * 60,
                now: now
            ),
        ]
    }

    static func notificationSessions(lead: AgentSession, now: Date) -> [AgentSession] {
        var sessions = listSessions(now: now)
        if sessions.isEmpty {
            return [lead]
        }
        sessions[0] = lead
        return sessions
    }

    static func runningSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-running",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .running,
            summary: "Reading IslandPanelView.swift and AppModel.swift",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-running"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Refactor DEV into a debug page so I can iterate on the card UI.",
                lastUserPrompt: "There were some incorrect changes earlier — please redo them.",
                lastAssistantMessage: "Reading the current notch state and event routing — splitting the notification state out of the session list.",
                currentTool: "exec_command",
                currentCommandPreview: "sed -n '1,260p' Sources/OpenIslandApp/Views/ControlCenterView.swift"
            )
        )
    }

    static func recentCompletedSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-recent",
            title: "Codex · open-agent-sdk",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "The session list now matches the original island more closely.",
            updatedAt: now.addingTimeInterval(-3 * 60),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-agent-sdk",
                paneTitle: "codex ~/Personal/open-agent-sdk",
                workingDirectory: "/Users/wangruobing/Personal/open-agent-sdk",
                terminalSessionID: "ghostty-recent"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Read this paper: https://arxiv.org/html/2603.28052",
                lastUserPrompt: "Read this paper: https://arxiv.org/html/2603.28052v1 — feels related to the agent we're building.",
                lastAssistantMessage: "Done — extracted the key differences from the auto-research sections."
            )
        )
    }

    static func inactiveSession(
        id: String,
        workspace: String,
        initialPrompt: String,
        latestPrompt: String,
        assistant: String,
        age: TimeInterval,
        now: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspace)",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: assistant,
            updatedAt: now.addingTimeInterval(-age),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "codex ~/Personal/\(workspace)",
                workingDirectory: "/Users/wangruobing/Personal/\(workspace)",
                terminalSessionID: "ghostty-\(id)"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: initialPrompt,
                lastUserPrompt: latestPrompt,
                lastAssistantMessage: assistant
            )
        )
    }

    static func approvalSession(now: Date) -> AgentSession {
        let oldString = """
@MainActor
final class ShortcutsManager {
    private let model: AppModel
    init(model: AppModel) { self.model = model }
    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleOverlay) { [model] in
            model.toggleOverlay()
        }
    }
}
"""
        let newString = """
@MainActor
final class ShortcutsManager {
    private let model: AppModel
    init(model: AppModel) { self.model = model }
    func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleOverlay) { [model] in
            model.toggleOverlay()
        }
        KeyboardShortcuts.onKeyDown(for: .jumpToFocusedSession) { [model] in
            model.jumpToFocusedSession()
        }
        KeyboardShortcuts.onKeyDown(for: .approveFocusedPermission) { [model] in
            model.approveFocusedPermission(true)
        }
    }
}
"""
        return AgentSession(
            id: "session-approval",
            title: "Claude Code · atoll",
            tool: .claudeCode,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Allow Edit to extend ShortcutsManager.start()?",
            updatedAt: now.addingTimeInterval(-20),
            permissionRequest: PermissionRequest(
                title: "Edit Sources/AtollApp/ShortcutsManager.swift",
                summary: "Add jumpToFocusedSession + approveFocusedPermission handlers",
                affectedPath: "Sources/AtollApp/ShortcutsManager.swift",
                primaryActionTitle: "Allow",
                secondaryActionTitle: "Deny",
                toolName: "Edit",
                toolInput: .object([
                    "file_path": .string("Sources/AtollApp/ShortcutsManager.swift"),
                    "old_string": .string(oldString),
                    "new_string": .string(newString),
                ])
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "atoll",
                paneTitle: "claude ~/Personal/atoll",
                workingDirectory: "/Users/jules/Personal/atoll",
                terminalSessionID: "ghostty-approval"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Wire up the productive global shortcuts in the settings page.",
                lastUserPrompt: "Add the jump + approve handlers next to the toggle one.",
                lastAssistantMessage: "Ready to extend ShortcutsManager — needs approval to edit the file.",
                currentTool: "Edit",
                currentCommandPreview: "Edit Sources/AtollApp/ShortcutsManager.swift"
            )
        )
    }

    static func questionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-question",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Should the notification state auto-dismiss?",
            updatedAt: now.addingTimeInterval(-18),
            questionPrompt: QuestionPrompt(
                title: "Which authentication method should we use?",
                questions: [
                    QuestionPromptItem(
                        question: "Which authentication method should we use?",
                        header: "Auth",
                        options: [
                            QuestionOption(label: "JWT tokens", description: "Stateless, scalable"),
                            QuestionOption(label: "Session cookies", description: "Traditional approach"),
                            QuestionOption(label: "OAuth 2.0", description: "Third-party auth"),
                            QuestionOption(label: "Other", description: "", allowsFreeform: true),
                        ]
                    )
                ]
            ),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-question"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "The original product looks like a single notch surface + multiple content surfaces.",
                lastUserPrompt: "What approach should we take?",
                lastAssistantMessage: "Suggest splitting approvalCard, questionCard, and completionCard into separate surfaces first."
            )
        )
    }

    static func completionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "DEV page now runs in mock-driven card debug mode.",
            updatedAt: now.addingTimeInterval(-15),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-completion"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "I genuinely need mock data this time to validate these card UIs.",
                lastUserPrompt: "Refactor DEV into a debug page entirely.",
                lastAssistantMessage: "Plan file is written. How are the hooks firing on your end?"
            )
        )
    }

    static func longCompletionSession(now: Date) -> AgentSession {
        AgentSession(
            id: "session-completion-long",
            title: "Codex · open-island",
            tool: .codex,
            origin: .demo,
            attachmentState: .attached,
            phase: .completed,
            summary: "README is committed; long replies now scroll inside the card.",
            updatedAt: now.addingTimeInterval(-45),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/Personal/open-island",
                workingDirectory: "/Users/wangruobing/Personal/open-island",
                terminalSessionID: "ghostty-completion-long"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Commit the README too and paste the result back to me.",
                lastUserPrompt: "Also, confirm the current worktree state and verification status.",
                lastAssistantMessage: """
The existing [README.md](/Users/jules/Personal/atoll/README.md) tweaks have been committed separately — commit `f196316`, message `docs: update readme tagline`.

I didn't run the tests this round because the change is doc-only. The working tree is clean; `main` is now `ahead 6` of `origin/main`.

If you want me to keep going, I'd recommend splitting the next round into its own worktree so it can't collide with parallel changes on shared `main`.

Next: check the current repo state, then create a fresh worktree and branch off `origin/main`. I'll handle the styling fix in that isolated workspace and run the full verification before reporting back.
"""
            )
        )
    }
}
