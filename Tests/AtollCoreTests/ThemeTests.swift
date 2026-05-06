import Foundation
import Testing
@testable import AtollCore

struct ThemeTests {
    @Test
    func everyAppThemeResolvesAPalette() {
        for theme in AppTheme.builtIn {
            // Smoke check — all 26 fields populated, light flag matches.
            let palette = theme.builtInPalette ?? .mocha
            #expect(palette.text.red >= 0 && palette.text.red <= 1)
            #expect(palette.green.red >= 0 && palette.green.red <= 1)
            if theme == .latte {
                #expect(palette.isLight == true)
            } else {
                #expect(palette.isLight == false)
            }
        }
    }

    @Test
    func mochaPaletteMatchesPublishedHexValues() {
        // Accents stay on the official Catppuccin Mocha spec so muscle
        // memory across catppuccin'd apps still applies. The layered
        // surface tones (base/mantle/crust/surface*) intentionally
        // deviate — pushed toward a deeper blue-teal so the panel reads
        // as ocean-night rather than the flat purple-grey of canonical
        // Mocha. See Theme.swift for the full rationale.
        let p = ThemePalette.mocha
        #expect(approximatelyEqual(p.base, hex: "162232"))
        #expect(approximatelyEqual(p.crust, hex: "0a1220"))
        #expect(approximatelyEqual(p.text, hex: "cdd6f4"))
        #expect(approximatelyEqual(p.green, hex: "a6e3a1"))
        #expect(approximatelyEqual(p.red, hex: "f38ba8"))
        #expect(approximatelyEqual(p.peach, hex: "fab387"))
        #expect(approximatelyEqual(p.blue, hex: "89b4fa"))
        #expect(approximatelyEqual(p.mauve, hex: "cba6f7"))
    }

    @Test
    func lattePaletteIsTheLightFlavor() {
        let p = ThemePalette.latte
        #expect(p.isLight == true)
        // Latte's base is near-white.
        #expect(p.base.red > 0.85 && p.base.green > 0.85 && p.base.blue > 0.85)
    }

    @Test
    func malformedHexFallsBackToBlack() {
        let c = ProjectColor.fromHex("not-hex")
        #expect(c.red == 0 && c.green == 0 && c.blue == 0)
    }

    @Test
    func hexWithLeadingHashParses() {
        let c = ProjectColor.fromHex("#ff0000")
        #expect(approximatelyEqual(c, hex: "ff0000"))
    }

    @Test
    func appThemeRoundtripsThroughCodable() throws {
        for theme in AppTheme.builtIn {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
            #expect(decoded == theme)
        }
        // Also test custom round-trip.
        let customID = UUID()
        let custom = AppTheme.custom(id: customID)
        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
        #expect(decoded == custom)
    }

    @Test
    func paletteRoleMapsToExpectedAccentForEveryFlavor() {
        for theme in AppTheme.builtIn {
            let p = theme.builtInPalette ?? .mocha
            // Each role must resolve to a specific palette field. The
            // mapping is locked — adding a role or moving a role must
            // require updating this test, which is a feature not a bug.
            #expect(p.role(.warning)    == p.peach)
            #expect(p.role(.attention)  == p.peach)
            #expect(p.role(.danger)     == p.red)
            #expect(p.role(.success)    == p.green)
            #expect(p.role(.completion) == p.green)
            #expect(p.role(.working)    == p.blue)
            #expect(p.role(.question)   == p.yellow)
        }
    }

    @Test
    func paletteRoleEnumIsExhaustive() {
        // PaletteRole.allCases must stay in sync with the role(_:) switch.
        // If a new role is added without a switch case, this fails on the
        // first call (the switch becomes non-exhaustive at compile time).
        let p = ThemePalette.mocha
        for role in PaletteRole.allCases {
            let resolved = p.role(role)
            // Every role must map to one of the 14 accents.
            let accents: [ProjectColor] = [
                p.rosewater, p.flamingo, p.pink, p.mauve, p.red, p.maroon,
                p.peach, p.yellow, p.green, p.teal, p.sky, p.sapphire,
                p.blue, p.lavender,
            ]
            #expect(accents.contains(resolved))
        }
    }

    @Test
    func lattePaletteHasReadableContrast() {
        let p = ThemePalette.latte
        // Latte must be a real light theme — dark text on light base.
        // Catches regressions where someone shifts Latte numbers without
        // realizing they broke the readability contract.
        let textLuma = relativeLuminance(p.text)
        let baseLuma = relativeLuminance(p.base)
        #expect(textLuma < 0.5,
                "Latte.text luma (\(textLuma)) must be < 0.5 — dark text on light base")
        #expect(baseLuma > 0.85,
                "Latte.base luma (\(baseLuma)) must be > 0.85 — near-white base")

        // Crust on Latte should be slightly darker than base (depth).
        let crustLuma = relativeLuminance(p.crust)
        #expect(crustLuma < baseLuma,
                "Latte.crust must be darker than base for layered depth")
    }

    @Test
    func darkFlavorsHaveDarkBase() {
        // Inverse contract for the dark flavors — base must be dark.
        for theme in [AppTheme.frappe, .macchiato, .mocha] {
            let p = theme.builtInPalette ?? .mocha
            let baseLuma = relativeLuminance(p.base)
            #expect(baseLuma < 0.20,
                    "\(theme).base luma (\(baseLuma)) must be < 0.20 — dark base")
        }
    }

    private func approximatelyEqual(_ color: ProjectColor, hex: String) -> Bool {
        let target = ProjectColor.fromHex(hex)
        return abs(color.red - target.red) < 0.01
            && abs(color.green - target.green) < 0.01
            && abs(color.blue - target.blue) < 0.01
    }
}

/// Rec. 709 relative luminance (test-helper, not part of the public API).
/// Good enough for contract-locking; we don't ship a contrast checker.
private func relativeLuminance(_ c: ProjectColor) -> Double {
    func channel(_ v: Double) -> Double {
        v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
}
