import Foundation
import Testing
@testable import AtollApp

struct HarnessLaunchConfigurationTests {
    @Test
    func defaultsMatchNormalAppLaunch() {
        let configuration = HarnessLaunchConfiguration(environment: [:], arguments: [])

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.shouldShowControlCenter)
        #expect(configuration.shouldStartBridge)
        #expect(configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }

    @Test
    func parsesScenarioFlagsAndAutoExit() {
        // Use a path under NSTemporaryDirectory() so the safety
        // validator accepts it. `/tmp/...` is not under that root on
        // macOS test runners, so artifact-dir validation now requires
        // an explicit /var/folders/... path or the --harness flag.
        let safeDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("open-island-artifacts")

        let configuration = HarnessLaunchConfiguration(
            environment: [
                "OPEN_ISLAND_HARNESS_SCENARIO": "approvalcard",
                "OPEN_ISLAND_HARNESS_PRESENT_OVERLAY": "true",
                "OPEN_ISLAND_HARNESS_SHOW_CONTROL_CENTER": "0",
                "OPEN_ISLAND_HARNESS_START_BRIDGE": "no",
                "OPEN_ISLAND_HARNESS_BOOT_ANIMATION": "off",
                "OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS": "1.5",
                "OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS": "2.5",
                "OPEN_ISLAND_HARNESS_ARTIFACT_DIR": safeDir,
            ],
            arguments: []
        )

        #expect(configuration.scenario == .approvalCard)
        #expect(configuration.presentOverlay)
        #expect(!configuration.shouldShowControlCenter)
        #expect(!configuration.shouldStartBridge)
        #expect(!configuration.shouldPerformBootAnimation)
        #expect(configuration.captureDelay == 1.5)
        #expect(configuration.autoExitAfter == 2.5)
        #expect(configuration.artifactDirectoryURL?.path == safeDir)
    }

    @Test
    func ignoresInvalidInputs() {
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "OPEN_ISLAND_HARNESS_SCENARIO": "missing",
                "OPEN_ISLAND_HARNESS_PRESENT_OVERLAY": "unexpected",
                "OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS": "0",
                "OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS": "-1",
                "OPEN_ISLAND_HARNESS_ARTIFACT_DIR": "   ",
            ],
            arguments: []
        )

        #expect(configuration.scenario == nil)
        #expect(!configuration.presentOverlay)
        #expect(configuration.captureDelay == nil)
        #expect(configuration.autoExitAfter == nil)
        #expect(configuration.artifactDirectoryURL == nil)
    }

    // MARK: - Artifact directory safety

    @Test
    func artifactDirRejectsUnsafePathAndFallsBackToDefault() {
        // `/tmp/...` resolves to `/private/tmp/...`, which is NOT
        // under `NSTemporaryDirectory()` on macOS — the validator
        // must reject it, log to stderr, and hand back the
        // app-owned default path.
        let configuration = HarnessLaunchConfiguration(
            environment: [
                "OPEN_ISLAND_HARNESS_ARTIFACT_DIR": "/tmp/atoll-test-attack",
            ],
            arguments: []
        )

        #expect(configuration.artifactDirectoryURL != nil,
                "Unsafe path must fall back, not become nil")
        #expect(
            configuration.artifactDirectoryURL?.path
                == HarnessLaunchConfiguration.defaultArtifactDirectoryURL.path,
            "Unsafe path must fall back to the app-owned default"
        )
    }

    @Test
    func artifactDirRejectsSiblingPathAttack() {
        // A path that *starts* with the app's harness directory but
        // is actually a sibling (e.g. `…/Atoll/harness2`) must NOT
        // pass the prefix check.
        let attack = HarnessLaunchConfiguration.defaultArtifactDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("harness2-attack", isDirectory: true)
        let configuration = HarnessLaunchConfiguration(
            environment: ["OPEN_ISLAND_HARNESS_ARTIFACT_DIR": attack.path],
            arguments: []
        )

        // Either the sibling lies under one of the legitimate roots
        // (it should not, on any sane test machine), or the validator
        // must fall back to the canonical default — never accept a
        // sibling path.
        #expect(
            configuration.artifactDirectoryURL?.path
                == HarnessLaunchConfiguration.defaultArtifactDirectoryURL.path
        )
    }

    @Test
    func artifactDirAcceptsPathUnderNSTemporaryDirectory() {
        let safe = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("atoll-harness-\(UUID().uuidString)")
        let configuration = HarnessLaunchConfiguration(
            environment: ["OPEN_ISLAND_HARNESS_ARTIFACT_DIR": safe],
            arguments: []
        )
        #expect(configuration.artifactDirectoryURL?.path == safe)
    }

    @Test
    func artifactDirAcceptsAnyPathWithHarnessFlag() {
        let configuration = HarnessLaunchConfiguration(
            environment: ["OPEN_ISLAND_HARNESS_ARTIFACT_DIR": "/Users/Shared/atoll-loose"],
            arguments: ["AtollApp", "--harness"]
        )
        #expect(configuration.artifactDirectoryURL?.path == "/Users/Shared/atoll-loose",
                "When --harness is set, any path is accepted (trusted runner).")
    }
}
