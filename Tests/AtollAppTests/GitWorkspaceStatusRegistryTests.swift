import Foundation
import Testing
@testable import AtollApp

struct GitWorkspaceStatusRegistryTests {
    @Test
    func numstatParserSumsTextFileChangesAndSkipsBinaryRows() {
        let counts = GitWorkspaceStatusReader.parseNumstat(lines: [
            "12\t3\tSources/File.swift",
            "-\t-\tAssets/Icon.png",
            "4\t0\tREADME.md",
        ])

        #expect(counts.additions == 16)
        #expect(counts.removals == 3)
    }

    @Test
    func diffSummaryUsesCleanDirtyAndLineCounts() {
        #expect(GitWorkspaceSnapshot(
            branchName: "main",
            changedFileCount: 0,
            additions: 0,
            removals: 0,
            untrackedFileCount: 0
        ).diffSummary == "clean")

        #expect(GitWorkspaceSnapshot(
            branchName: "main",
            changedFileCount: 1,
            additions: 0,
            removals: 0,
            untrackedFileCount: 1
        ).diffSummary == "1")

        #expect(GitWorkspaceSnapshot(
            branchName: "main",
            changedFileCount: 2,
            additions: 7,
            removals: 4,
            untrackedFileCount: 0
        ).diffSummary == "+7 -4")
    }
}
