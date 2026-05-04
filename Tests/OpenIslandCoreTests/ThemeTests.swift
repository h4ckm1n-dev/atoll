import Foundation
import Testing
@testable import OpenIslandCore

struct ThemeTests {
    @Test
    func everyAppThemeResolvesAPalette() {
        for theme in AppTheme.allCases {
            // Smoke check — all 26 fields populated, light flag matches.
            let palette = theme.palette
            #expect(palette.text.red >= 0 && palette.text.red <= 1)
            #expect(palette.green.red >= 0 && palette.green.red <= 1)
            if theme == .catppuccinLatte {
                #expect(palette.isLight == true)
            } else {
                #expect(palette.isLight == false)
            }
        }
    }

    @Test
    func mochaPaletteMatchesPublishedHexValues() {
        // Spot-check a handful of well-known Catppuccin Mocha values.
        let p = ThemePalette.mocha
        #expect(approximatelyEqual(p.base, hex: "1e1e2e"))
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
        for theme in AppTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(AppTheme.self, from: data)
            #expect(decoded == theme)
        }
    }

    private func approximatelyEqual(_ color: ProjectColor, hex: String) -> Bool {
        let target = ProjectColor.fromHex(hex)
        return abs(color.red - target.red) < 0.01
            && abs(color.green - target.green) < 0.01
            && abs(color.blue - target.blue) < 0.01
    }
}
