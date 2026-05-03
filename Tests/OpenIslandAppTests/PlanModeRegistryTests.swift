import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

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
}
