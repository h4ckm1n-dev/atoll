import AppKit
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

    private(set) var canCheckForUpdates = false
    private(set) var hasUpdate = false
    private(set) var latestVersion: String?
    private(set) var releaseNotesAttributed: AttributedString?
    private(set) var releaseNotesPlainText: String?

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController!

    @ObservationIgnored
    private var cancellable: AnyCancellable?

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
        // Skip the auto-check entirely in debug — release bundles still update.
        print("[UpdateChecker] skipped in DEBUG build")
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
                self?.canCheckForUpdates = value
            }
        #endif
    }

    /// Manually trigger an update check (from Settings UI).
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Set()
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        // Capture release notes from the appcast item. Sparkle 2.9 exposes inline
        // release notes via `itemDescription` (a String containing HTML/Markdown/
        // plain text depending on `itemDescriptionFormat`). External notes URLs
        // are exposed via `releaseNotesURL` and fetched lazily on demand — we
        // don't fetch here to keep the delegate callback fast.
        let descriptionHTML = item.itemDescription
        Task { @MainActor in
            self.hasUpdate = true
            self.latestVersion = version
            self.releaseNotesAttributed = Self.parseReleaseNotes(fallbackHTML: descriptionHTML)
            self.releaseNotesPlainText = descriptionHTML
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Task { @MainActor in
            self.hasUpdate = false
            self.latestVersion = nil
            self.releaseNotesAttributed = nil
            self.releaseNotesPlainText = nil
        }
    }

    // MARK: - Private helpers

    /// Converts HTML release notes to an `AttributedString`.
    ///
    /// Must be called on `@MainActor` because `NSAttributedString(html:options:documentAttributes:)`
    /// requires AppKit to be ready on the main thread.
    @MainActor
    private static func parseReleaseNotes(fallbackHTML: String?) -> AttributedString? {
        guard let fallbackHTML, let data = fallbackHTML.data(using: .utf8) else {
            return nil
        }

        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        guard let nsAttr = NSAttributedString(html: data, options: options, documentAttributes: nil) else {
            // HTML parse failed — fall back to rendering as plain text.
            return AttributedString(fallbackHTML)
        }
        return try? AttributedString(nsAttr, including: \.appKit)
    }
}
