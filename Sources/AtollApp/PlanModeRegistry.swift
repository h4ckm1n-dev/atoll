import Foundation
import Observation
import AtollCore

/// Per-session plan state with manually-toggled checkboxes. Stable across
/// app launches via UserDefaults — when a session has a long-running
/// workflow you can quit, relaunch, and pick up where you left off.
///
/// `rawMarkdown` carries the original plan markdown body alongside the
/// parsed steps so views can render the full document (e.g. headings,
/// paragraphs, code blocks) instead of only the bullet/heading skeleton
/// `PlanModeParser.parse` extracts. Persisted records written before
/// `rawMarkdown` existed decode with an empty string fallback.
public struct PlanState: Equatable, Codable, Sendable {
    public var steps: [PlanStep]
    public var checkedIDs: Set<String>
    public var capturedAt: Date
    public var rawMarkdown: String

    public init(
        steps: [PlanStep],
        checkedIDs: Set<String> = [],
        capturedAt: Date = Date(),
        rawMarkdown: String = ""
    ) {
        self.steps = steps
        self.checkedIDs = checkedIDs
        self.capturedAt = capturedAt
        self.rawMarkdown = rawMarkdown
    }

    private enum CodingKeys: String, CodingKey {
        case steps, checkedIDs, capturedAt, rawMarkdown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.steps = try container.decode([PlanStep].self, forKey: .steps)
        self.checkedIDs = try container.decode(Set<String>.self, forKey: .checkedIDs)
        self.capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        // Older persisted records (pre-rawMarkdown) decode with empty
        // markdown; the disclosure view renders an empty-state in that case.
        self.rawMarkdown = try container.decodeIfPresent(String.self, forKey: .rawMarkdown) ?? ""
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
    /// is identical to the existing one, the call preserves checkbox state
    /// but still refreshes `rawMarkdown` (the markdown body may have been
    /// captured for the first time, or the new payload may have non-step
    /// edits like prose tweaks that should still update the rendered view).
    /// Otherwise the prior plan is replaced and checkboxes reset.
    public func recordPlan(
        sessionID: String,
        steps: [PlanStep],
        rawMarkdown: String = "",
        capturedAt: Date = Date()
    ) {
        if let existing = plans[sessionID], existing.steps == steps {
            // Same step structure — preserve checked state, refresh markdown.
            if existing.rawMarkdown == rawMarkdown { return }
            var updated = existing
            updated.rawMarkdown = rawMarkdown
            plans[sessionID] = updated
            persist()
            return
        }
        plans[sessionID] = PlanState(
            steps: steps,
            checkedIDs: [],
            capturedAt: capturedAt,
            rawMarkdown: rawMarkdown
        )
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
