import Foundation

public enum AppTheme: Sendable, Hashable {
    case system
    case latte
    case frappe
    case macchiato
    case mocha
    /// Custom theme stored in `CustomThemeRegistry`. The `id` resolves
    /// to a `CustomTheme` whose palette is rendered. If the id is
    /// missing from the registry (file deleted out-of-band), the
    /// theme manager falls back to `.mocha`.
    case custom(id: UUID)

    /// Built-in flavors that ship with the app. Custom themes are not
    /// listed here — they're enumerated separately via the registry.
    public static let builtIn: [AppTheme] = [.system, .latte, .frappe, .macchiato, .mocha]

    public var displayName: String {
        switch self {
        case .system:    return "System"
        case .latte:     return "Catppuccin Latte"
        case .frappe:    return "Catppuccin Frappé"
        case .macchiato: return "Catppuccin Macchiato"
        case .mocha:     return "Catppuccin Mocha"
        case .custom:    return "Custom"  // overridden at the call site with the CustomTheme.displayName
        }
    }

    /// Stable identifier used for `Picker.tag(_:)` and persistence.
    /// Built-ins use a kind keyword; custom themes use their UUID.
    public var stableID: String {
        switch self {
        case .system:    return "system"
        case .latte:     return "latte"
        case .frappe:    return "frappe"
        case .macchiato: return "macchiato"
        case .mocha:     return "mocha"
        case .custom(let id): return "custom:\(id.uuidString)"
        }
    }

    /// Reverse of `stableID`. Used when reading the persisted theme
    /// choice back from UserDefaults. Returns nil for unrecognized.
    public init?(stableID: String) {
        switch stableID {
        case "system":    self = .system
        case "latte":     self = .latte
        case "frappe":    self = .frappe
        case "macchiato": self = .macchiato
        case "mocha":     self = .mocha
        // Backwards-compat with old persisted strings from before
        // the Atoll rebrand.
        case "catppuccinLatte":     self = .latte
        case "catppuccinFrappe":    self = .frappe
        case "catppuccinMacchiato": self = .macchiato
        case "catppuccinMocha":     self = .mocha
        default:
            guard stableID.hasPrefix("custom:"),
                  let id = UUID(uuidString: String(stableID.dropFirst("custom:".count))) else {
                return nil
            }
            self = .custom(id: id)
        }
    }
}

extension AppTheme: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, id
    }

    public init(from decoder: Decoder) throws {
        // Permit both the new keyed shape ({"kind":"mocha"} or
        // {"kind":"custom","id":"..."}) and the legacy unkeyed
        // single-string shape ("catppuccinMocha", etc.).
        if let single = try? decoder.singleValueContainer().decode(String.self),
           let theme = AppTheme(stableID: single) {
            self = theme
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "system":    self = .system
        case "latte":     self = .latte
        case "frappe":    self = .frappe
        case "macchiato": self = .macchiato
        case "mocha":     self = .mocha
        case "custom":
            self = .custom(id: try c.decode(UUID.self, forKey: .id))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "Unknown AppTheme kind '\(kind)'"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .system:    try c.encode("system",    forKey: .kind)
        case .latte:     try c.encode("latte",     forKey: .kind)
        case .frappe:    try c.encode("frappe",    forKey: .kind)
        case .macchiato: try c.encode("macchiato", forKey: .kind)
        case .mocha:     try c.encode("mocha",     forKey: .kind)
        case .custom(let id):
            try c.encode("custom", forKey: .kind)
            try c.encode(id, forKey: .id)
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

    /// Mocha base/mantle/crust/surface tones are pushed toward a deeper
    /// blue-teal than the canonical Catppuccin Mocha (which leans purple).
    /// This matches Open Island's "tropical island" identity — the panel
    /// reads as a calm ocean-night rather than a flat dark grey. Accent
    /// values (rosewater → lavender) stay on-spec so any cross-app
    /// muscle memory for Catppuccin colors still applies.
    public static let mocha = ThemePalette.from(hex: [
        "162232", "10182a", "0a1220", "263347", "37475e", "4a5b75",
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
    /// Resolves the palette for a *built-in* theme. Returns nil for
    /// `.custom` — the caller (typically `ThemeManager`) is responsible
    /// for looking that up in `CustomThemeRegistry`.
    public var builtInPalette: ThemePalette? {
        switch self {
        case .system:    return .system
        case .latte:     return .latte
        case .frappe:    return .frappe
        case .macchiato: return .macchiato
        case .mocha:     return .mocha
        case .custom:    return nil
        }
    }
}

/// Semantic accent roles. Views should prefer `palette.role(.warning)`
/// over `palette.peach` when the call site is naming an *intent*
/// (warning, danger, success) rather than a *color*. The mapping is
/// the same across every flavor — only the underlying hex changes.
public enum PaletteRole: Sendable, Hashable, CaseIterable {
    case warning      // amber / caution — non-destructive nudge
    case danger       // destructive / always-allow
    case success      // task completed, idle-but-ok
    case working      // active / in-progress
    case attention    // demands the user's eyes (permission, mute)
    case question     // structured-question prompt, plan-mode card
    case completion   // celebratory completion banner
}

extension ThemePalette {
    /// Resolves a semantic accent role to the matching palette field.
    /// Used by views that want to express intent rather than color.
    /// See `docs/plans/2026-05-06-theme-personalization-design.md`
    /// section "Color mapping (Phase 1 sweep)" for the rationale.
    public func role(_ role: PaletteRole) -> ProjectColor {
        switch role {
        case .warning, .attention: return peach
        case .danger:              return red
        case .success, .completion: return green
        case .working:             return blue
        case .question:            return yellow
        }
    }
}

extension ProjectColor {
    /// Parse a `#RRGGBB` or `RRGGBB` hex string. Falls back to (0,0,0) on
    /// malformed input so a typo doesn't crash the renderer mid-frame.
    public static func fromHex(_ raw: String) -> ProjectColor {
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

    /// Encodes this color as a 6-char lowercase hex string (no '#').
    public func toHex() -> String {
        let r = Int((red * 255).rounded()) & 0xff
        let g = Int((green * 255).rounded()) & 0xff
        let b = Int((blue * 255).rounded()) & 0xff
        return String(format: "%02x%02x%02x", r, g, b)
    }
}

extension ThemePalette: Codable {
    /// Schema version of the on-disk JSON. Bump when the field set
    /// changes incompatibly. Decoder rejects files with a version
    /// higher than `currentSchemaVersion` (forward-incompatible).
    public static let currentSchemaVersion: Int = 1

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case isLight
        case base, mantle, crust
        case surface0, surface1, surface2
        case text, subtext1, subtext0
        case overlay2, overlay1, overlay0
        case rosewater, flamingo, pink, mauve
        case red, maroon, peach, yellow
        case green, teal, sky, sapphire
        case blue, lavender
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Theme schemaVersion \(version) is newer than supported (\(Self.currentSchemaVersion)). Update Atoll."
            ))
        }
        func hex(_ key: CodingKeys) throws -> ProjectColor {
            let raw = try c.decode(String.self, forKey: key)
            guard ThemePalette.isValidHex(raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Invalid hex value '\(raw)' for color '\(key.stringValue)'. Expected 6 hex chars."
                ))
            }
            return ProjectColor.fromHex(raw)
        }
        self.init(
            base: try hex(.base), mantle: try hex(.mantle), crust: try hex(.crust),
            surface0: try hex(.surface0), surface1: try hex(.surface1), surface2: try hex(.surface2),
            text: try hex(.text), subtext1: try hex(.subtext1), subtext0: try hex(.subtext0),
            overlay2: try hex(.overlay2), overlay1: try hex(.overlay1), overlay0: try hex(.overlay0),
            rosewater: try hex(.rosewater), flamingo: try hex(.flamingo), pink: try hex(.pink), mauve: try hex(.mauve),
            red: try hex(.red), maroon: try hex(.maroon), peach: try hex(.peach), yellow: try hex(.yellow),
            green: try hex(.green), teal: try hex(.teal), sky: try hex(.sky), sapphire: try hex(.sapphire),
            blue: try hex(.blue), lavender: try hex(.lavender),
            isLight: try c.decode(Bool.self, forKey: .isLight)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(isLight, forKey: .isLight)
        try c.encode(base.toHex(), forKey: .base)
        try c.encode(mantle.toHex(), forKey: .mantle)
        try c.encode(crust.toHex(), forKey: .crust)
        try c.encode(surface0.toHex(), forKey: .surface0)
        try c.encode(surface1.toHex(), forKey: .surface1)
        try c.encode(surface2.toHex(), forKey: .surface2)
        try c.encode(text.toHex(), forKey: .text)
        try c.encode(subtext1.toHex(), forKey: .subtext1)
        try c.encode(subtext0.toHex(), forKey: .subtext0)
        try c.encode(overlay2.toHex(), forKey: .overlay2)
        try c.encode(overlay1.toHex(), forKey: .overlay1)
        try c.encode(overlay0.toHex(), forKey: .overlay0)
        try c.encode(rosewater.toHex(), forKey: .rosewater)
        try c.encode(flamingo.toHex(), forKey: .flamingo)
        try c.encode(pink.toHex(), forKey: .pink)
        try c.encode(mauve.toHex(), forKey: .mauve)
        try c.encode(red.toHex(), forKey: .red)
        try c.encode(maroon.toHex(), forKey: .maroon)
        try c.encode(peach.toHex(), forKey: .peach)
        try c.encode(yellow.toHex(), forKey: .yellow)
        try c.encode(green.toHex(), forKey: .green)
        try c.encode(teal.toHex(), forKey: .teal)
        try c.encode(sky.toHex(), forKey: .sky)
        try c.encode(sapphire.toHex(), forKey: .sapphire)
        try c.encode(blue.toHex(), forKey: .blue)
        try c.encode(lavender.toHex(), forKey: .lavender)
    }

    /// Validates a 6-char hex string (no `#` prefix). Used by the
    /// decoder to reject malformed import files cleanly.
    public static func isValidHex(_ raw: String) -> Bool {
        var s = raw
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 else { return false }
        return s.allSatisfy { $0.isHexDigit }
    }

    /// Every named color in the palette, paired with its hex string.
    /// Used by import validators that need to walk the full palette
    /// without depending on `Codable`. Order is the canonical
    /// declaration order so audits and diff tooling stay stable.
    public func allHexValues() -> [(name: String, hex: String)] {
        [
            ("base", base.toHex()),
            ("mantle", mantle.toHex()),
            ("crust", crust.toHex()),
            ("surface0", surface0.toHex()),
            ("surface1", surface1.toHex()),
            ("surface2", surface2.toHex()),
            ("text", text.toHex()),
            ("subtext1", subtext1.toHex()),
            ("subtext0", subtext0.toHex()),
            ("overlay2", overlay2.toHex()),
            ("overlay1", overlay1.toHex()),
            ("overlay0", overlay0.toHex()),
            ("rosewater", rosewater.toHex()),
            ("flamingo", flamingo.toHex()),
            ("pink", pink.toHex()),
            ("mauve", mauve.toHex()),
            ("red", red.toHex()),
            ("maroon", maroon.toHex()),
            ("peach", peach.toHex()),
            ("yellow", yellow.toHex()),
            ("green", green.toHex()),
            ("teal", teal.toHex()),
            ("sky", sky.toHex()),
            ("sapphire", sapphire.toHex()),
            ("blue", blue.toHex()),
            ("lavender", lavender.toHex()),
        ]
    }
}
