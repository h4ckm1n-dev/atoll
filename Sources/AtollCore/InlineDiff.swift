import Foundation

/// One line of a unified-style diff. `add` and `remove` carry the full
/// line text without the leading `+`/`-` (the renderer adds those).
public enum DiffLine: Equatable, Sendable {
    case context(String)
    case add(String)
    case remove(String)

    public var text: String {
        switch self {
        case let .context(value),
             let .add(value),
             let .remove(value):
            return value
        }
    }

    public var isAddition: Bool {
        if case .add = self { return true }
        return false
    }

    public var isRemoval: Bool {
        if case .remove = self { return true }
        return false
    }
}

public struct ToolDiff: Equatable, Sendable {
    /// Cap on input size per side. Beyond this, MyersDiff returns nil and
    /// the UI shows a "diff too large to preview" stub instead of locking
    /// up on a huge file.
    public static let maxLinesPerSide = 2000

    public var filePath: String
    public var lines: [DiffLine]
    public var additionCount: Int
    public var removalCount: Int
    public var truncated: Bool

    public init(
        filePath: String,
        lines: [DiffLine],
        additionCount: Int,
        removalCount: Int,
        truncated: Bool = false
    ) {
        self.filePath = filePath
        self.lines = lines
        self.additionCount = additionCount
        self.removalCount = removalCount
        self.truncated = truncated
    }
}

public enum MyersDiff {
    /// Computes line-level diff between two strings. Returns nil when either
    /// side exceeds `ToolDiff.maxLinesPerSide`. Treats trailing newlines
    /// consistently — a string with a trailing newline doesn't get an extra
    /// empty line at the end.
    public static func diff(old: String, new: String) -> [DiffLine]? {
        let oldLines = splitLines(old)
        let newLines = splitLines(new)
        guard oldLines.count <= ToolDiff.maxLinesPerSide,
              newLines.count <= ToolDiff.maxLinesPerSide else {
            return nil
        }
        return compute(oldLines: oldLines, newLines: newLines)
    }

    private static func splitLines(_ s: String) -> [String] {
        if s.isEmpty { return [] }
        var lines = s.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    /// Standard LCS-based diff. O(n*m) time/space which is fine within the
    /// 2000-line cap (worst case ~16MB table — acceptable for the caps we
    /// enforce; pre-approval surface, not a long-running computation).
    private static func compute(oldLines: [String], newLines: [String]) -> [DiffLine] {
        let n = oldLines.count
        let m = newLines.count

        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0..<n {
            for j in 0..<m {
                if oldLines[i] == newLines[j] {
                    lcs[i + 1][j + 1] = lcs[i][j] + 1
                } else {
                    lcs[i + 1][j + 1] = max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var result: [DiffLine] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && oldLines[i - 1] == newLines[j - 1] {
                result.append(.context(oldLines[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j]) {
                result.append(.add(newLines[j - 1]))
                j -= 1
            } else if i > 0 {
                result.append(.remove(oldLines[i - 1]))
                i -= 1
            }
        }
        return result.reversed()
    }
}
