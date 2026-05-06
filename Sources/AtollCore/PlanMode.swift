import Foundation

/// One step extracted from a Claude Code plan markdown. `id` is a stable
/// hash of the title used as the key for checkbox state across app
/// launches — same title → same id, regardless of order or surrounding
/// formatting changes.
public struct PlanStep: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var depth: Int

    public init(id: String, title: String, depth: Int) {
        self.id = id
        self.title = title
        self.depth = depth
    }
}

/// Classifies whether a `file_path` looks like a plan markdown that we
/// should capture into the plan registry alongside the native ExitPlanMode
/// flow. Covers the two skill-driven flows that produce plan files:
///   - `superpowers:brainstorming` writes `docs/plans/YYYY-MM-DD-<topic>-design.md`
///   - `superpowers:writing-plans` writes `docs/plans/YYYY-MM-DD-<topic>.md`
/// Plus GSD-style `.planning/` paths and any markdown filename containing
/// `plan`/`PLAN`. Conservative on purpose — false positives would feed
/// unrelated markdown into the plan registry.
public enum PlanFilePathClassifier {
    public static func looksLikePlan(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard lower.hasSuffix(".md") else { return false }

        let components = lower.split(separator: "/").map(String.init)

        // `docs/plans/...` or any directory named `plans`/`plan`/`.planning`.
        if components.contains(where: { $0 == "plans" || $0 == "plan" || $0 == ".planning" }) {
            return true
        }

        // Filename ending in `-plan.md`, `_plan.md`, or simply called `plan.md`/`PLAN.md`.
        guard let filename = components.last else { return false }
        if filename == "plan.md" {
            return true
        }
        if filename.hasSuffix("-plan.md") || filename.hasSuffix("_plan.md") {
            return true
        }
        return false
    }
}

/// Parses the markdown body Claude Code submits via the ExitPlanMode tool
/// into a flat ordered list of `PlanStep`. Recognized line shapes:
/// - `## Heading` / `### Heading` → step at depth 0/1
/// - `- bullet` / `* bullet` / `+ bullet` → step at depth derived from
///   leading whitespace (every 2 spaces of indent = +1 depth)
/// - `1. numbered` / `1) numbered` → numbered bullet, same depth rule
/// Headings always reset depth to their hash count - 2 (so `##` = 0,
/// `###` = 1, etc.). Empty lines and lines that don't match any shape
/// are skipped.
public enum PlanModeParser {
    public static func parse(_ markdown: String) -> [PlanStep] {
        var steps: [PlanStep] = []
        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let (title, depth) = matchHeading(line) {
                steps.append(makeStep(title: title, depth: depth))
                continue
            }
            if let (title, depth) = matchBullet(line) {
                steps.append(makeStep(title: title, depth: depth))
                continue
            }
        }
        return steps
    }

    private static func makeStep(title: String, depth: Int) -> PlanStep {
        PlanStep(id: stableID(for: title, depth: depth), title: title, depth: max(0, depth))
    }

    /// Stable hash so the same step survives Codable round-trips and
    /// re-parses. Includes the depth so a bullet promoted to a heading
    /// (or vice versa) gets a fresh checkbox state — depth changes
    /// usually mean the plan was substantially rewritten.
    private static func stableID(for title: String, depth: Int) -> String {
        let normalized = title.trimmingCharacters(in: .whitespaces).lowercased()
        var hash: UInt64 = 0xcbf29ce484222325 // FNV-1a 64-bit offset basis
        let prime: UInt64 = 0x100000001b3
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        hash ^= UInt64(bitPattern: Int64(depth))
        hash = hash &* prime
        return String(hash, radix: 16)
    }

    // MARK: - Line matchers

    private static func matchHeading(_ line: String) -> (title: String, depth: Int)? {
        var hashCount = 0
        for char in line {
            if char == "#" { hashCount += 1 }
            else { break }
        }
        guard hashCount >= 2 else { return nil }
        let body = line.dropFirst(hashCount)
        guard body.first == " " else { return nil }
        let title = body.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (title, hashCount - 2)
    }

    private static func matchBullet(_ line: String) -> (title: String, depth: Int)? {
        var leadingSpaces = 0
        for char in line {
            if char == " " { leadingSpaces += 1 }
            else if char == "\t" { leadingSpaces += 4 }
            else { break }
        }
        let body = String(line.dropFirst(leadingSpaces))
        let depth = leadingSpaces / 2

        // - bullet / * bullet / + bullet
        if let first = body.first, "-*+".contains(first) {
            let rest = body.dropFirst()
            guard rest.first == " " else { return nil }
            let title = rest.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return (title, depth)
        }

        // 1. numbered / 1) numbered
        var numberLength = 0
        for char in body {
            if char.isNumber { numberLength += 1 } else { break }
        }
        guard numberLength > 0 else { return nil }
        let after = body.dropFirst(numberLength)
        guard let separator = after.first, separator == "." || separator == ")" else { return nil }
        let rest = after.dropFirst()
        guard rest.first == " " else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return (title, depth)
    }
}
