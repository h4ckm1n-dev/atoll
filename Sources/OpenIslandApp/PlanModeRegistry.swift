import Foundation
import Observation
import OpenIslandCore

/// Per-session plan state with manually-toggled checkboxes. Stable across
/// app launches via UserDefaults — when a session has a long-running
/// workflow you can quit, relaunch, and pick up where you left off.
public struct PlanState: Equatable, Codable, Sendable {
    public var steps: [PlanStep]
    public var checkedIDs: Set<String>
    public var capturedAt: Date

    public init(steps: [PlanStep], checkedIDs: Set<String> = [], capturedAt: Date = Date()) {
        self.steps = steps
        self.checkedIDs = checkedIDs
        self.capturedAt = capturedAt
    }
}

/// `@Observable` registry mapping session ID to `PlanState`. Mutations
/// trigger SwiftUI re-renders for views observing `plans`. Persistence is
/// best-effort — encoding errors are silently dropped to avoid blocking
/// the UI thread on a bad payload.
@Observable
@MainActor
public final class PlanModeRegistry {
    public private(set) var plans: [String: PlanState]

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "feature.planMode.state"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.plans = Self.load(from: defaults, key: storageKey)
    }

    /// Replace or initialize the plan for a session. If the new step list
    /// is identical to the existing one, the call is a no-op (preserves
    /// any existing checkbox state). Otherwise the prior plan is replaced
    /// and checkboxes reset.
    public func recordPlan(sessionID: String, steps: [PlanStep], capturedAt: Date = Date()) {
        if let existing = plans[sessionID], existing.steps == steps {
            return
        }
        plans[sessionID] = PlanState(steps: steps, checkedIDs: [], capturedAt: capturedAt)
        persist()
    }

    /// Toggle the checkbox for a given step. No-op when the session or
    /// step isn't tracked.
    public func toggleCheck(sessionID: String, stepID: String) {
        guard var state = plans[sessionID] else { return }
        guard state.steps.contains(where: { $0.id == stepID }) else { return }
        if state.checkedIDs.contains(stepID) {
            state.checkedIDs.remove(stepID)
        } else {
            state.checkedIDs.insert(stepID)
        }
        plans[sessionID] = state
        persist()
    }

    public func plan(for sessionID: String) -> PlanState? {
        plans[sessionID]
    }

    public func clearPlan(sessionID: String) {
        guard plans[sessionID] != nil else { return }
        plans.removeValue(forKey: sessionID)
        persist()
    }

    /// Drop plans for sessions that no longer exist. Keeps the persisted
    /// store from gradually accumulating thousands of stale entries over
    /// months of use.
    public func prune(activeSessionIDs: Set<String>) {
        let staleKeys = plans.keys.filter { !activeSessionIDs.contains($0) }
        guard !staleKeys.isEmpty else { return }
        for key in staleKeys {
            plans.removeValue(forKey: key)
        }
        persist()
    }

    // MARK: - Persistence

    private static func load(from defaults: UserDefaults, key: String) -> [String: PlanState] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: PlanState].self, from: data)) ?? [:]
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(plans) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
