import Foundation

/// Strips Unicode formatting characters that an attacker could use to
/// make a diff line look harmless while it executes something else.
/// Returns the sanitized text plus a flag indicating whether any
/// dangerous characters were found, so the renderer can show a warning
/// badge instead of silently neutralizing the manipulation.
///
/// Targets:
/// - **Bidi overrides** (U+202A–U+202E, U+2066–U+2069) — Trojan Source
///   attacks (Boucher & Anderson 2021).
/// - **Zero-width and invisible** (U+200B–U+200F, U+FEFF, U+00AD) —
///   identifier-substitution attacks: `authentic​ate` looks like
///   `authenticate` but is a different symbol.
/// - **Line / paragraph separators** (U+2028, U+2029) — break diff
///   line accounting in subtle ways.
///
/// Each occurrence is replaced with a visible placeholder of the form
/// `⟨XXXX⟩` (the codepoint in hex), so the user sees the attack rather
/// than missing it.
public enum DiffTextSanitizer {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var hadHiddenCharacters: Bool

        public init(text: String, hadHiddenCharacters: Bool) {
            self.text = text
            self.hadHiddenCharacters = hadHiddenCharacters
        }
    }

    public static func sanitize(_ source: String) -> Result {
        var output = ""
        output.reserveCapacity(source.count)
        var flagged = false
        for scalar in source.unicodeScalars {
            if isDangerous(scalar) {
                flagged = true
                let hex = String(scalar.value, radix: 16, uppercase: true)
                output.append("⟨U+\(hex)⟩")
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return Result(text: output, hadHiddenCharacters: flagged)
    }

    private static func isDangerous(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        // Bidi control characters
        case 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
             0x2066, 0x2067, 0x2068, 0x2069:
            return true
        // Zero-width and invisible formatting
        case 0x200B, 0x200C, 0x200D, 0x200E, 0x200F,
             0x00AD,    // SOFT HYPHEN
             0xFEFF:    // ZERO WIDTH NO-BREAK SPACE / BOM
            return true
        // Line / paragraph separators that are not LF/CR
        case 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }
}
