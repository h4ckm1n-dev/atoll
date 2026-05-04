import Foundation

/// Selectable palette family. The cases are ordered Latte → Frappé →
/// Macchiato → Mocha (Catppuccin's light → dark progression) plus a
/// `system` option that preserves Open Island's pre-theme look so users
/// who don't want the rebrand can opt out via Settings → Appearance.
public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system
    case catppuccinLatte
    case catppuccinFrappe
    case catppuccinMacchiato
    case catppuccinMocha

    public var displayName: String {
        switch self {
        case .system:              return "System"
        case .catppuccinLatte:     return "Catppuccin Latte"
        case .catppuccinFrappe:    return "Catppuccin Frappé"
        case .catppuccinMacchiato: return "Catppuccin Macchiato"
        case .catppuccinMocha:     return "Catppuccin Mocha"
        }
    }
}

/// Semantic palette resolved from an `AppTheme`. Names follow the
/// Catppuccin convention so views read naturally (e.g. `palette.green`,
/// `palette.peach`) regardless of which flavor is active. Layered
/// surfaces use Catppuccin's base/mantle/crust/surface progression so
/// chrome elements with subtle depth pick the right tone automatically.
public struct ThemePalette: Equatable, Sendable {
    // Backgrounds, layered light → dark (or dark → darker on dark themes).
    public var base: ProjectColor
    public var mantle: ProjectColor
    public var crust: ProjectColor
    public var surface0: ProjectColor
    public var surface1: ProjectColor
    public var surface2: ProjectColor

    // Foregrounds, primary → tertiary.
    public var text: ProjectColor
    public var subtext1: ProjectColor
    public var subtext0: ProjectColor
    public var overlay2: ProjectColor
    public var overlay1: ProjectColor
    public var overlay0: ProjectColor

    // Accents.
    public var rosewater: ProjectColor
    public var flamingo: ProjectColor
    public var pink: ProjectColor
    public var mauve: ProjectColor
    public var red: ProjectColor
    public var maroon: ProjectColor
    public var peach: ProjectColor
    public var yellow: ProjectColor
    public var green: ProjectColor
    public var teal: ProjectColor
    public var sky: ProjectColor
    public var sapphire: ProjectColor
    public var blue: ProjectColor
    public var lavender: ProjectColor

    /// `true` when the theme is dark-on-light (Latte). Views can use this
    /// to flip subtle decisions like white-translucent overlays vs
    /// black-translucent ones without hardcoding the test against a
    /// specific theme name.
    public var isLight: Bool

    public static let mocha = ThemePalette.from(hex: [
        "1e1e2e", "181825", "11111b", "313244", "45475a", "585b70",
        "cdd6f4", "bac2de", "a6adc8", "9399b2", "7f849c", "6c7086",
        "f5e0dc", "f2cdcd", "f5c2e7", "cba6f7", "f38ba8", "eba0ac",
        "fab387", "f9e2af", "a6e3a1", "94e2d5", "89dceb", "74c7ec",
        "89b4fa", "b4befe",
    ], isLight: false)

    public static let macchiato = ThemePalette.from(hex: [
        "24273a", "1e2030", "181926", "363a4f", "494d64", "5b6078",
        "cad3f5", "b8c0e0", "a5adcb", "939ab7", "8087a2", "6e738d",
        "f4dbd6", "f0c6c6", "f5bde6", "c6a0f6", "ed8796", "ee99a0",
        "f5a97f", "eed49f", "a6da95", "8bd5ca", "91d7e3", "7dc4e4",
        "8aadf4", "b7bdf8",
    ], isLight: false)

    public static let frappe = ThemePalette.from(hex: [
        "303446", "292c3c", "232634", "414559", "51576d", "626880",
        "c6d0f5", "b5bfe2", "a5adce", "949cbb", "838ba7", "737994",
        "f2d5cf", "eebebe", "f4b8e4", "ca9ee6", "e78284", "ea999c",
        "ef9f76", "e5c890", "a6d189", "81c8be", "99d1db", "85c1dc",
        "8caaee", "babbf1",
    ], isLight: false)

    public static let latte = ThemePalette.from(hex: [
        "eff1f5", "e6e9ef", "dce0e8", "ccd0da", "bcc0cc", "acb0be",
        "4c4f69", "5c5f77", "6c6f85", "7c7f93", "8c8fa1", "9ca0b0",
        "dc8a78", "dd7878", "ea76cb", "8839ef", "d20f39", "e64553",
        "fe640b", "df8e1d", "40a02b", "179299", "04a5e5", "209fb5",
        "1e66f5", "7287fd",
    ], isLight: true)

    /// Pre-theme look: rough approximation of the existing palette so
    /// users picking `.system` keep what they had before this rebrand.
    /// Built from the hex values that previously appeared in the views.
    public static let system = ThemePalette.from(hex: [
        "0a0a0a", "060606", "000000", "1a1a1a", "262626", "333333",
        "f0f0f0", "cccccc", "a0a0a0", "888888", "707070", "555555",
        "f5e0dc", "ffafaf", "ff7eb6", "cba6f7", "f38ba8", "ff9999",
        "ff9933", "ffd700", "42e86b", "94e2d5", "5fb3ff", "5fa0ff",
        "6e9fff", "9999ff",
    ], isLight: false)

    /// 26-element flat hex array → typed palette. Order matches the
    /// stored-property declaration order above so a single static array
    /// per theme stays compact and searchable.
    static func from(hex: [String], isLight: Bool) -> ThemePalette {
        precondition(hex.count == 26, "Theme palette requires exactly 26 hex values, got \(hex.count)")
        let c = hex.map { ProjectColor.fromHex($0) }
        return ThemePalette(
            base: c[0], mantle: c[1], crust: c[2],
            surface0: c[3], surface1: c[4], surface2: c[5],
            text: c[6], subtext1: c[7], subtext0: c[8],
            overlay2: c[9], overlay1: c[10], overlay0: c[11],
            rosewater: c[12], flamingo: c[13], pink: c[14], mauve: c[15],
            red: c[16], maroon: c[17], peach: c[18], yellow: c[19],
            green: c[20], teal: c[21], sky: c[22], sapphire: c[23],
            blue: c[24], lavender: c[25],
            isLight: isLight
        )
    }
}

extension AppTheme {
    /// Resolves the palette for the active theme. Pure function — no
    /// IO; safe to call from any actor.
    public var palette: ThemePalette {
        switch self {
        case .system:              return .system
        case .catppuccinLatte:     return .latte
        case .catppuccinFrappe:    return .frappe
        case .catppuccinMacchiato: return .macchiato
        case .catppuccinMocha:     return .mocha
        }
    }
}

extension ProjectColor {
    /// Parse a `#RRGGBB` or `RRGGBB` hex string. Falls back to (0,0,0) on
    /// malformed input so a typo doesn't crash the renderer mid-frame.
    static func fromHex(_ raw: String) -> ProjectColor {
        var s = raw
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else {
            return ProjectColor(red: 0, green: 0, blue: 0)
        }
        return ProjectColor(
            red: Double((value >> 16) & 0xff) / 255.0,
            green: Double((value >> 8) & 0xff) / 255.0,
            blue: Double(value & 0xff) / 255.0
        )
    }
}
