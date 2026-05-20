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
    func diffArgumentsCountsWipOnMainAndMaster() {
        #expect(GitWorkspaceStatusReader.diffArguments(
            forBranch: "main",
            integrationBranch: "main"
        ) == ["HEAD"])

        #expect(GitWorkspaceStatusReader.diffArguments(
            forBranch: "master",
            integrationBranch: "master"
        ) == ["HEAD"])
    }

    @Test
    func diffArgumentsCountsAgainstIntegrationBranchOnFeatureBranch() {
        #expect(GitWorkspaceStatusReader.diffArguments(
            forBranch: "feat/badge",
            integrationBranch: "main"
        ) == ["main...HEAD"])

        #expect(GitWorkspaceStatusReader.diffArguments(
            forBranch: "fix/badge",
            integrationBranch: "master"
        ) == ["master...HEAD"])
    }

    @Test
    func diffArgumentsFallsBackToWipWhenNoIntegrationBranchExists() {
        #expect(GitWorkspaceStatusReader.diffArguments(
            forBranch: "feat/badge",
            integrationBranch: nil
        ) == ["HEAD"])
    }

    @Test
    func diffArgumentsHandlesDetachedHeadShaAsFeatureBranch() {
        // currentBranchName falls back to the short SHA when detached;
        // that hash isn't "main"/"master", so it should diff against main.
        #expect(GitWorkspaceStatusReader.diffArguments(
            forBranch: "abc1234",
            integrationBranch: "main"
        ) == ["main...HEAD"])
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
