import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's `SPUUpdater` to provide observable update state for SwiftUI.
///
/// Sparkle handles the full lifecycle: checking for updates, downloading,
/// extracting, replacing the app bundle, and relaunching.
/// This wrapper simply exposes the current state so the UI can react.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let releasesURL = URL(string: "https://github.com/h4ckm1n-dev/atoll/releases")!

    private(set) var canCheckForUpdates = true
    private(set) var sparkleCanCheckForUpdates = false
    private(set) var sparkleUpdateAvailable = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?
    private(set) var latestReleaseName: String?
    private(set) var latestReleaseNotes: String?
    private(set) var latestReleaseURL: URL?

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    @ObservationIgnored
    private var cancellable: AnyCancellable?

    @ObservationIgnored
    private let releaseFetcher = GitHubReleaseFetcher()

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    /// Start Sparkle's automatic update checking schedule.
    /// Call once after app launch.
    func startIfNeeded() {
        #if DEBUG
        // Dev builds run from a local branch that often carries fixes not yet in
        // the upstream appcast. Letting Sparkle prompt the user to "update" to
        // 1.0.21 would overwrite the bundle and silently discard those fixes.
        // Skip Sparkle entirely in debug, but still fetch the latest GitHub
        // release so the Settings pane can expose stale release/appcast issues.
        print("[UpdateChecker] skipped in DEBUG build")
        Task { await refreshLatestReleaseFromGitHub() }
        return
        #else
        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = true
        updater.updateCheckInterval = 60 * 60 // 1 hour
        updater.automaticallyDownloadsUpdates = false

        do {
            try updater.start()
        } catch {
            print("[UpdateChecker] Failed to start Sparkle updater: \(error)")
        }

        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.sparkleCanCheckForUpdates = value
            }

        Task { await refreshLatestReleaseFromGitHub() }
        #endif
    }

    /// Manually trigger an update check (from Settings UI).
    func checkForUpdates() {
        Task { await refreshLatestReleaseFromGitHub() }
        #if !DEBUG
        if sparkleCanCheckForUpdates {
            updaterController.checkForUpdates(nil)
        }
        #endif
    }

    // MARK: - Private

    private func refreshLatestReleaseFromGitHub() async {
        guard let release = await releaseFetcher.fetchLatest() else { return }
        latestReleaseName = release.displayName
        latestReleaseNotes = release.body
        latestReleaseURL = release.htmlURL
        let releaseVersion = Self.normalizedVersionString(release.tagName)
        guard Self.isVersion(releaseVersion, newerThan: Self.currentVersionString) else { return }
        hasUpdate = true
        if latestVersion == nil {
            latestVersion = releaseVersion
        }
    }

    private static var currentVersionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    private static func normalizedVersionString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        return withoutPrefix
            .split(separator: "-", maxSplits: 1)
            .first
            .map(String.init) ?? withoutPrefix
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = numericComponents(candidate)
        let rhs = numericComponents(current)
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }

    private static func numericComponents(_ version: String) -> [Int] {
        normalizedVersionString(version)
            .split(separator: ".")
            .map { component in
                let digits = component.prefix { $0.isNumber }
                return Int(String(digits)) ?? 0
            }
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Set()
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in
            self.hasUpdate = true
            self.sparkleUpdateAvailable = true
            self.latestVersion = version
            await self.refreshLatestReleaseFromGitHub()
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.hasUpdate = false
            self.sparkleUpdateAvailable = false
            self.latestVersion = nil
            await self.refreshLatestReleaseFromGitHub()
        }
    }
}
