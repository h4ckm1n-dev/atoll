import Testing
@testable import AtollCore
import Foundation

struct StreamOverlaySnapshotTests {
    @Test
    func snapshotOrdersAttentionBeforeRunningAndCompleted() {
        let now = Date(timeIntervalSince1970: 1_000)
        let completed = session(
            id: "completed",
            phase: .completed,
            updatedAt: now.addingTimeInterval(2),
            summary: "Done"
        )
        let running = session(
            id: "running",
            phase: .running,
            updatedAt: now.addingTimeInterval(1),
            summary: "Working"
        )
        let approval = session(
            id: "approval",
            phase: .waitingForApproval,
            updatedAt: now,
            summary: "Needs approval",
            permissionRequest: PermissionRequest(
                title: "Bash",
                summary: "Run tests",
                affectedPath: ""
            )
        )

        let snapshot = StreamOverlaySnapshot.make(
            from: [completed, running, approval],
            generatedAt: now
        )

        #expect(snapshot.liveSessionCount == 3)
        #expect(snapshot.attentionCount == 1)
        #expect(snapshot.runningCount == 1)
        #expect(snapshot.sessions.map(\.id) == ["approval", "running", "completed"])
    }

    @Test
    func snapshotRedactsVisibleTextButKeepsSessionStateRaw() {
        let rawPrompt = "Fix /Users/alice/SecretProject/App.swift with OPENAI_API_KEY=sk-1234567890abcdefghijklmnop"
        let candidate = session(
            id: "sensitive",
            phase: .running,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            summary: "Working",
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: rawPrompt,
                currentTool: "Bash",
                currentCommandPreview: "cat /Users/alice/.ssh/id_rsa"
            )
        )

        let snapshot = StreamOverlaySnapshot.make(
            from: [candidate],
            visibleTextRedactor: { LiveCodingRedactor.redact($0, homeDirectory: "/Users/alice") }
        )

        #expect(candidate.initialUserPromptText == rawPrompt)
        #expect(snapshot.sessions.first?.headline.contains("/Users/alice") == false)
        #expect(snapshot.sessions.first?.headline.contains("sk-") == false)
        #expect(snapshot.sessions.first?.detail == "cat ~/.../id_rsa")
    }

    @Test
    func snapshotSkipsInvisibleSessions() {
        let stale = session(
            id: "stale",
            phase: .completed,
            attachmentState: .detached,
            isProcessAlive: false,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            summary: "Old"
        )

        let snapshot = StreamOverlaySnapshot.make(from: [stale])

        #expect(snapshot.liveSessionCount == 0)
        #expect(snapshot.sessions.isEmpty)
    }

    private func session(
        id: String,
        phase: SessionPhase,
        attachmentState: SessionAttachmentState = .attached,
        isProcessAlive: Bool = true,
        updatedAt: Date,
        summary: String,
        permissionRequest: PermissionRequest? = nil,
        codexMetadata: CodexSessionMetadata? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Codex · OpenIsland",
            tool: .codex,
            origin: .live,
            attachmentState: attachmentState,
            phase: phase,
            summary: summary,
            updatedAt: updatedAt,
            permissionRequest: permissionRequest,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "OpenIsland",
                paneTitle: "codex",
                workingDirectory: "/Users/alice/OpenIsland"
            ),
            codexMetadata: codexMetadata
        )
        session.isProcessAlive = isProcessAlive
        return session
    }
}
