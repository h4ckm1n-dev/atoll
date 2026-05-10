import Foundation
import Testing
@testable import AtollCore

struct SessionTimelineEntryTests {
    @Test
    func permissionEntryCarriesAttentionAndAffectedPath() {
        let timestamp = Date(timeIntervalSince1970: 5_000)
        let event = AgentEvent.permissionRequested(
            PermissionRequested(
                sessionID: "s1",
                request: PermissionRequest(
                    title: "Edit file",
                    summary: "Needs to edit README",
                    affectedPath: "README.md"
                ),
                timestamp: timestamp
            )
        )

        let entry = SessionTimelineEntry.make(from: event)

        #expect(entry.sessionID == "s1")
        #expect(entry.kind == .permission)
        #expect(entry.summary == "Needs to edit README")
        #expect(entry.detail == "README.md")
        #expect(entry.timestamp == timestamp)
        #expect(entry.requiresAttention)
    }

    @Test
    func questionEntrySummarizesStructuredQuestionCount() {
        let event = AgentEvent.questionAsked(
            QuestionAsked(
                sessionID: "s2",
                prompt: QuestionPrompt(
                    title: "Choose rollout",
                    questions: [
                        QuestionPromptItem(
                            question: "Which channel?",
                            header: "Channel",
                            options: [QuestionOption(label: "Stable")]
                        ),
                        QuestionPromptItem(
                            question: "Run migrations?",
                            header: "Migrations",
                            options: [QuestionOption(label: "Yes")]
                        ),
                    ]
                ),
                timestamp: Date(timeIntervalSince1970: 5_001)
            )
        )

        let entry = SessionTimelineEntry.make(from: event)

        #expect(entry.kind == .question)
        #expect(entry.summary == "Choose rollout")
        #expect(entry.detail == "2 questions")
        #expect(entry.requiresAttention)
    }

    @Test
    func metadataEntryPrefersCurrentToolAndSessionTitle() {
        let session = AgentSession(
            id: "s3",
            title: "Codex · Atoll",
            tool: .codex,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 5_002)
        )
        let event = AgentEvent.sessionMetadataUpdated(
            SessionMetadataUpdated(
                sessionID: "s3",
                codexMetadata: CodexSessionMetadata(currentTool: "Bash"),
                timestamp: Date(timeIntervalSince1970: 5_003)
            )
        )

        let entry = SessionTimelineEntry.make(from: event, session: session)

        #expect(entry.title == "Codex · Atoll")
        #expect(entry.tool == .codex)
        #expect(entry.kind == .metadata)
        #expect(entry.summary == "Codex is running Bash.")
    }

    @Test
    func agentEventExposesSessionID() {
        let event = AgentEvent.actionableStateResolved(
            ActionableStateResolved(
                sessionID: "resolved-session",
                summary: "Done",
                timestamp: Date(timeIntervalSince1970: 5_004)
            )
        )

        #expect(event.sessionID == "resolved-session")
    }
}
