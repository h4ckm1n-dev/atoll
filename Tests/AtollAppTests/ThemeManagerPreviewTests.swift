import Foundation
import Testing
@testable import AtollApp
import AtollCore

struct ThemeManagerPreviewTests {
    @Test
    func setPreviewPaletteOverridesActiveTheme() async {
        let manager = await ThemeManager()
        // Initial state: palette resolves from theme.
        let initial = await manager.palette
        #expect(initial == ThemePalette.mocha)
        // Set a preview, palette should now return the preview value.
        await manager.setPreviewPalette(.latte)
        let preview = await manager.palette
        #expect(preview == ThemePalette.latte)
        // Clear the preview, palette returns to theme-resolved.
        await manager.setPreviewPalette(nil)
        let cleared = await manager.palette
        #expect(cleared == ThemePalette.mocha)
    }

    @Test
    func setPreviewPaletteSurvivesThemeSwitch() async {
        let manager = await ThemeManager()
        await manager.setPreviewPalette(.frappe)
        await manager.setTheme(.latte)
        let still = await manager.palette
        // Even after theme switch, the preview wins.
        #expect(still == ThemePalette.frappe)
        // Clearing the preview reveals the new theme.
        await manager.setPreviewPalette(nil)
        let revealed = await manager.palette
        #expect(revealed == ThemePalette.latte)
    }

    @Test
    func previewPaletteIsNilByDefault() async {
        let manager = await ThemeManager()
        let preview = await manager.previewPalette
        #expect(preview == nil)
    }
}
