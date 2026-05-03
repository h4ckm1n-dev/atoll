import Foundation

/// Inspects a tool name + its JSON input and returns a ready-to-render
/// `ToolDiff` for the file-mutating tools we know about. Returns nil for
/// tool names we don't recognize, malformed inputs, or diffs too large to
/// preview cheaply.
///
/// Recognized:
/// - **Edit** (Claude Code): `{file_path, old_string, new_string}`
/// - **Write** (Claude Code): `{file_path, content}` — treated as all-additions
/// - **MultiEdit** (Claude Code): `{file_path, edits: [{old_string, new_string}]}`
/// - **apply_patch** (Codex): `{patch}` — already a unified diff, parsed directly
public enum ToolDiffExtractor {
    public static func diff(
        toolName: String?,
        toolInput: CodexHookJSONValue?
    ) -> ToolDiff? {
        guard let toolName, let toolInput else { return nil }
        guard case let .object(fields) = toolInput else { return nil }

        switch toolName {
        case "Edit":
            return extractEdit(fields: fields)
        case "Write":
            return extractWrite(fields: fields)
        case "MultiEdit":
            return extractMultiEdit(fields: fields)
        case "apply_patch":
            return extractApplyPatch(fields: fields)
        default:
            return nil
        }
    }

    private static func string(_ value: CodexHookJSONValue?) -> String? {
        guard case let .string(s) = value else { return nil }
        return s
    }

    // MARK: - Edit

    private static func extractEdit(fields: [String: CodexHookJSONValue]) -> ToolDiff? {
        guard let filePath = string(fields["file_path"]),
              let oldString = string(fields["old_string"]),
              let newString = string(fields["new_string"]) else {
            return nil
        }
        guard let lines = MyersDiff.diff(old: oldString, new: newString) else {
            return ToolDiff(filePath: filePath, lines: [], additionCount: 0, removalCount: 0, truncated: true)
        }
        return assemble(filePath: filePath, lines: lines)
    }

    // MARK: - Write

    private static func extractWrite(fields: [String: CodexHookJSONValue]) -> ToolDiff? {
        guard let filePath = string(fields["file_path"]),
              let content = string(fields["content"]) else {
            return nil
        }
        // New file — every line is an addition. Apply the same per-side cap.
        let lines = splitForWrite(content)
        if lines.count > ToolDiff.maxLinesPerSide {
            return ToolDiff(filePath: filePath, lines: [], additionCount: lines.count, removalCount: 0, truncated: true)
        }
        let diffLines = lines.map { DiffLine.add($0) }
        return ToolDiff(filePath: filePath, lines: diffLines, additionCount: diffLines.count, removalCount: 0)
    }

    // MARK: - MultiEdit

    private static func extractMultiEdit(fields: [String: CodexHookJSONValue]) -> ToolDiff? {
        guard let filePath = string(fields["file_path"]),
              case let .array(rawEdits) = fields["edits"] ?? .null else {
            return nil
        }

        var combined: [DiffLine] = []
        for edit in rawEdits {
            guard case let .object(editFields) = edit,
                  let oldString = string(editFields["old_string"]),
                  let newString = string(editFields["new_string"]),
                  let hunkLines = MyersDiff.diff(old: oldString, new: newString) else {
                return ToolDiff(filePath: filePath, lines: [], additionCount: 0, removalCount: 0, truncated: true)
            }
            if !combined.isEmpty {
                combined.append(.context("…"))
            }
            combined.append(contentsOf: hunkLines)
        }

        return assemble(filePath: filePath, lines: combined)
    }

    // MARK: - apply_patch

    private static func extractApplyPatch(fields: [String: CodexHookJSONValue]) -> ToolDiff? {
        guard let raw = string(fields["patch"]) ?? string(fields["diff"]) else {
            return nil
        }

        // Multi-file patches let an attacker spoof the displayed filename:
        // put a benign +++ header last (it wins under last-write-wins) while
        // earlier hunks modify a sensitive file. Refuse to preview these and
        // tell the user to review the patch in the terminal instead.
        let plusHeaderCount = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("+++ ") }
            .count
        if plusHeaderCount > 1 {
            return ToolDiff(
                filePath: "(multi-file patch)",
                lines: [],
                additionCount: 0,
                removalCount: 0,
                truncated: true
            )
        }

        var lines: [DiffLine] = []
        var filePath: String? = nil
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("+++ ") {
                let trimmed = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                filePath = trimmed.hasPrefix("b/") ? String(trimmed.dropFirst(2)) : trimmed
                continue
            }
            if line.hasPrefix("--- ") || line.hasPrefix("@@") || line.hasPrefix("diff ")
                || line.hasPrefix("index ") || line.hasPrefix("***") {
                continue
            }
            if line.hasPrefix("+") {
                lines.append(.add(String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                lines.append(.remove(String(line.dropFirst())))
            } else {
                lines.append(.context(line.hasPrefix(" ") ? String(line.dropFirst()) : line))
            }
        }

        return assemble(filePath: filePath ?? "(patch)", lines: lines)
    }

    // MARK: - Helpers

    private static func splitForWrite(_ s: String) -> [String] {
        if s.isEmpty { return [] }
        var lines = s.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func assemble(filePath: String, lines: [DiffLine]) -> ToolDiff {
        var additions = 0
        var removals = 0
        for line in lines {
            if line.isAddition { additions += 1 }
            else if line.isRemoval { removals += 1 }
        }
        return ToolDiff(filePath: filePath, lines: lines, additionCount: additions, removalCount: removals)
    }
}
