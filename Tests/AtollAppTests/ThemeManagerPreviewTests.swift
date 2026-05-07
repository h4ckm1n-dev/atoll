import Foundation
import Testing
@testable import AtollApp
import AtollCore

struct ThemeManagerPreviewTests {
    /// Creates a `ThemeManager` backed by an isolated, in-memory
    /// `UserDefaults` suite so tests don't pick up the developer's
    /// actual saved theme choice (which would otherwise make the
    /// `initial == .mocha` assertion flaky).
    @MainActor
    private func makeIsolatedManager() -> ThemeManager {
        let suite = UserDefaults(suiteName: "atoll-tests-\(UUID().uuidString)")!
        return ThemeManager(defaults: suite)
    }

    @Test
    @MainActor
    func setPreviewPaletteOverridesActiveTheme() async {
        let manager = makeIsolatedManager()
        // First-launch default for ThemeManager is `.mocha`.
        let initial = manager.palette
        #expect(initial == ThemePalette.mocha)
        // Set a preview, palette should now return the preview value.
        manager.setPreviewPalette(.latte)
        let preview = manager.palette
        #expect(preview == ThemePalette.latte)
        // Clear the preview, palette returns to theme-resolved.
        manager.setPreviewPalette(nil)
        let cleared = manager.palette
        #expect(cleared == ThemePalette.mocha)
    }

    @Test
    @MainActor
    func setPreviewPaletteSurvivesThemeSwitch() async {
        let manager = makeIsolatedManager()
        manager.setPreviewPalette(.frappe)
        manager.setTheme(.latte)
        let still = manager.palette
        // Even after theme switch, the preview wins.
        #expect(still == ThemePalette.frappe)
        // Clearing the preview reveals the new theme.
        manager.setPreviewPalette(nil)
        let revealed = manager.palette
        #expect(revealed == ThemePalette.latte)
    }

    @Test
    @MainActor
    func previewPaletteIsNilByDefault() async {
        let manager = makeIsolatedManager()
        let preview = manager.previewPalette
        #expect(preview == nil)
    }
}
