import Foundation
import Observation

struct GitWorkspaceSnapshot: Equatable, Sendable {
    var branchName: String
    var changedFileCount: Int
    var additions: Int
    var removals: Int
    var untrackedFileCount: Int

    var isDirty: Bool {
        changedFileCount > 0 || untrackedFileCount > 0 || additions > 0 || removals > 0
    }

    var diffSummary: String {
        if additions == 0, removals == 0 {
            return isDirty ? "\(changedFileCount)" : "clean"
        }
        return "+\(additions) -\(removals)"
    }
}

@MainActor
@Observable
final class GitWorkspaceStatusRegistry {
    private(set) var snapshots: [String: GitWorkspaceSnapshot] = [:]

    @ObservationIgnored
    private var lastRefreshByPath: [String: Date] = [:]

    @ObservationIgnored
    private var inFlightPaths: Set<String> = []

    @ObservationIgnored
    private let minimumRefreshInterval: TimeInterval

    init(minimumRefreshInterval: TimeInterval = 8) {
        self.minimumRefreshInterval = minimumRefreshInterval
    }

    func snapshot(for path: String?) -> GitWorkspaceSnapshot? {
        guard let path = Self.normalizedPath(path) else { return nil }
        return snapshots[path]
    }

    func clear() {
        snapshots = [:]
        lastRefreshByPath = [:]
        inFlightPaths = []
    }

    func refresh(paths: [String], now: Date = Date()) {
        let normalizedPaths = Set(paths.compactMap(Self.normalizedPath))
        guard !normalizedPaths.isEmpty else {
            snapshots = [:]
            return
        }

        snapshots = snapshots.filter { normalizedPaths.contains($0.key) }

        let duePaths = normalizedPaths.filter { path in
            guard !inFlightPaths.contains(path) else { return false }
            guard let lastRefresh = lastRefreshByPath[path] else { return true }
            return now.timeIntervalSince(lastRefresh) >= minimumRefreshInterval
        }

        guard !duePaths.isEmpty else { return }
        duePaths.forEach {
            inFlightPaths.insert($0)
            lastRefreshByPath[$0] = now
        }

        Task.detached(priority: .utility) {
            let results = duePaths.map { path in
                (path, GitWorkspaceStatusReader.snapshot(for: path))
            }

            await MainActor.run {
                for (path, snapshot) in results {
                    self.inFlightPaths.remove(path)
                    if let snapshot {
                        self.snapshots[path] = snapshot
                    } else {
                        self.snapshots.removeValue(forKey: path)
                    }
                }
            }
        }
    }

    private static func normalizedPath(_ path: String?) -> String? {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

enum GitWorkspaceStatusReader {
    static func snapshot(for path: String) -> GitWorkspaceSnapshot? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard isInsideWorkTree(path) else { return nil }

        let branchName = currentBranchName(path) ?? "detached"
        let statusLines = git(["-C", path, "status", "--porcelain=v1"]).outputLines
        let changedFileCount = statusLines.count
        let untrackedFileCount = statusLines.filter { $0.hasPrefix("??") }.count

        // Branch-aware diff scope, matching ~/.claude/statusline-command.sh:
        // on main/master we count WIP (working tree vs HEAD); on a feature
        // branch we count the cumulative PR-size diff vs the integration branch.
        let diffArgs = diffArguments(
            forBranch: branchName,
            integrationBranch: integrationBranch(at: path)
        )
        let numstatLines = git(["-C", path, "diff", "--numstat"] + diffArgs + ["--"]).outputLines
        let counts = parseNumstat(lines: numstatLines)

        return GitWorkspaceSnapshot(
            branchName: branchName,
            changedFileCount: changedFileCount,
            additions: counts.additions,
            removals: counts.removals,
            untrackedFileCount: untrackedFileCount
        )
    }

    /// Selects `git diff` arguments based on the current branch.
    ///
    /// Mirrors `~/.claude/statusline-command.sh` so the island badge agrees
    /// with the shell statusline:
    /// - On `main`/`master`: diff working tree against `HEAD` (WIP count).
    /// - On any other branch with an integration branch available: diff against
    ///   the integration branch using three-dot syntax (PR-size count from the
    ///   merge-base — committed changes only, upstream advances ignored).
    /// - Otherwise: fall back to WIP.
    static func diffArguments(forBranch branch: String, integrationBranch: String?) -> [String] {
        if branch == "main" || branch == "master" {
            return ["HEAD"]
        }
        if let integrationBranch {
            return ["\(integrationBranch)...HEAD"]
        }
        return ["HEAD"]
    }

    static func parseNumstat(lines: [String]) -> (additions: Int, removals: Int) {
        lines.reduce(into: (additions: 0, removals: 0)) { result, line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2,
                  let additions = Int(columns[0]),
                  let removals = Int(columns[1]) else {
                return
            }
            result.additions += additions
            result.removals += removals
        }
    }

    private static func isInsideWorkTree(_ path: String) -> Bool {
        git(["-C", path, "rev-parse", "--is-inside-work-tree"]).trimmedOutput == "true"
    }

    private static func integrationBranch(at path: String) -> String? {
        if refExists("main", at: path) { return "main" }
        if refExists("master", at: path) { return "master" }
        return nil
    }

    private static func refExists(_ ref: String, at path: String) -> Bool {
        // Bare ref name lets git resolve through HEAD → refs/heads/ → refs/remotes/,
        // so repos that only have `origin/main` (no local tracking branch) still
        // resolve correctly. Matches the statusline fallback semantics.
        git(["-C", path, "rev-parse", "--verify", "--quiet", ref]).exitCode == 0
    }

    private static func currentBranchName(_ path: String) -> String? {
        let branch = git(["-C", path, "branch", "--show-current"]).trimmedOutput
        if !branch.isEmpty {
            return branch
        }

        let shortSHA = git(["-C", path, "rev-parse", "--short", "HEAD"]).trimmedOutput
        return shortSHA.isEmpty ? nil : shortSHA
    }

    private static func git(_ arguments: [String]) -> GitCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return GitCommandResult(exitCode: -1, output: "")
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return GitCommandResult(exitCode: process.terminationStatus, output: output)
    }
}

struct GitCommandResult {
    var exitCode: Int32
    var output: String

    var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var outputLines: [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
