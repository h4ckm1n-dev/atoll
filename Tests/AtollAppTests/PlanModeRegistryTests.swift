import Foundation
import Testing
@testable import AtollApp
@testable import AtollCore

@MainActor
struct PlanModeRegistryTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "PlanModeRegistryTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private let stepA = PlanStep(id: "a", title: "Edit AppModel", depth: 0)
    private let stepB = PlanStep(id: "b", title: "Add view", depth: 0)

    @Test
    func recordPlanStoresState() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "s", steps: [stepA, stepB])
        #expect(registry.plan(for: "s")?.steps == [stepA, stepB])
        #expect(registry.plan(for: "s")?.checkedIDs.isEmpty == true)
    }

    @Test
    func recordingIdenticalStepsPreservesChecks() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "s", steps: [stepA, stepB])
        registry.toggleCheck(sessionID: "s", stepID: "a")
        registry.recordPlan(sessionID: "s", steps: [stepA, stepB]) // same plan re-arrives
        #expect(registry.plan(for: "s")?.checkedIDs == ["a"])
    }

    @Test
    func recordingDifferentStepsResetsChecks() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "s", steps: [stepA, stepB])
        registry.toggleCheck(sessionID: "s", stepID: "a")
        registry.recordPlan(sessionID: "s", steps: [stepA]) // plan changed
        #expect(registry.plan(for: "s")?.checkedIDs.isEmpty == true)
    }

    @Test
    func toggleAddsAndRemovesCheck() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "s", steps: [stepA, stepB])

        registry.toggleCheck(sessionID: "s", stepID: "a")
        #expect(registry.plan(for: "s")?.checkedIDs == ["a"])

        registry.toggleCheck(sessionID: "s", stepID: "a")
        #expect(registry.plan(for: "s")?.checkedIDs.isEmpty == true)
    }

    @Test
    func toggleUnknownStepIsNoop() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "s", steps: [stepA])
        registry.toggleCheck(sessionID: "s", stepID: "doesnotexist")
        #expect(registry.plan(for: "s")?.checkedIDs.isEmpty == true)
    }

    @Test
    func toggleUnknownSessionIsNoop() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.toggleCheck(sessionID: "ghost", stepID: "a")
        #expect(registry.plan(for: "ghost") == nil)
    }

    @Test
    func clearPlanRemovesEntry() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "s", steps: [stepA])
        registry.clearPlan(sessionID: "s")
        #expect(registry.plan(for: "s") == nil)
    }

    @Test
    func pruneDropsInactiveSessions() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "active", steps: [stepA])
        registry.recordPlan(sessionID: "stale1", steps: [stepA])
        registry.recordPlan(sessionID: "stale2", steps: [stepA])
        registry.prune(activeSessionIDs: ["active"])
        #expect(registry.plan(for: "active") != nil)
        #expect(registry.plan(for: "stale1") == nil)
        #expect(registry.plan(for: "stale2") == nil)
    }

    @Test
    func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let key = "feature.planMode.state.test"

        let r1 = PlanModeRegistry(defaults: defaults, storageKey: key)
        r1.recordPlan(sessionID: "s", steps: [stepA, stepB])
        r1.toggleCheck(sessionID: "s", stepID: "b")

        let r2 = PlanModeRegistry(defaults: defaults, storageKey: key)
        #expect(r2.plan(for: "s")?.steps == [stepA, stepB])
        #expect(r2.plan(for: "s")?.checkedIDs == ["b"])
    }

    // MARK: - rawMarkdown

    @Test
    func recordPlanStoresRawMarkdown() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        let md = "# Plan\n\nDo a thing.\n- step"
        registry.recordPlan(sessionID: "s", steps: [stepA], rawMarkdown: md)
        #expect(registry.plan(for: "s")?.rawMarkdown == md)
    }

    @Test
    func recordPlanDefaultRawMarkdownIsEmpty() {
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "s", steps: [stepA])
        #expect(registry.plan(for: "s")?.rawMarkdown == "")
    }

    @Test
    func recordingIdenticalStepsRefreshesMarkdownButPreservesChecks() {
        // The step skeleton is unchanged but the prose body got tweaked —
        // checkboxes survive, the rendered markdown updates.
        let registry = PlanModeRegistry(defaults: makeDefaults(), storageKey: "k")
        registry.recordPlan(sessionID: "s", steps: [stepA, stepB], rawMarkdown: "v1")
        registry.toggleCheck(sessionID: "s", stepID: "a")
        registry.recordPlan(sessionID: "s", steps: [stepA, stepB], rawMarkdown: "v2")
        #expect(registry.plan(for: "s")?.rawMarkdown == "v2")
        #expect(registry.plan(for: "s")?.checkedIDs == ["a"])
    }

    @Test
    func planStateCodableRoundTripsRawMarkdown() throws {
        let original = PlanState(
            steps: [stepA, stepB],
            checkedIDs: ["a"],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            rawMarkdown: "# Plan\n- a\n- b"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PlanState.self, from: data)
        #expect(decoded == original)
        #expect(decoded.rawMarkdown == "# Plan\n- a\n- b")
    }

    @Test
    func planStateDecodesLegacyPayloadWithoutRawMarkdown() throws {
        // Simulate a record persisted before rawMarkdown existed: encode
        // only the legacy fields and confirm the new field defaults to "".
        struct LegacyPlanState: Codable {
            let steps: [PlanStep]
            let checkedIDs: Set<String>
            let capturedAt: Date
        }
        let legacy = LegacyPlanState(
            steps: [stepA],
            checkedIDs: ["a"],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(PlanState.self, from: data)
        #expect(decoded.steps == [stepA])
        #expect(decoded.checkedIDs == ["a"])
        #expect(decoded.rawMarkdown == "")
    }

    @Test
    func legacyPersistedRecordsLoadOnRegistryInit() throws {
        // Persist a legacy-shaped JSON payload directly into UserDefaults
        // and confirm the registry surfaces it with rawMarkdown == "".
        let defaults = makeDefaults()
        let key = "feature.planMode.state.legacy"
        struct LegacyPlanState: Codable {
            let steps: [PlanStep]
            let checkedIDs: Set<String>
            let capturedAt: Date
        }
        let legacyMap: [String: LegacyPlanState] = [
            "old": LegacyPlanState(
                steps: [stepA],
                checkedIDs: [],
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
        defaults.set(try JSONEncoder().encode(legacyMap), forKey: key)

        let registry = PlanModeRegistry(defaults: defaults, storageKey: key)
        #expect(registry.plan(for: "old")?.steps == [stepA])
        #expect(registry.plan(for: "old")?.rawMarkdown == "")
    }
}
