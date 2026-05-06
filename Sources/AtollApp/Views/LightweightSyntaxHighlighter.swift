import AppKit
import Foundation
import AtollCore
import SwiftUI

/// Tiny cross-language regex highlighter for inline diff previews. Not a
/// real parser — just enough visual signal (strings, comments, numbers,
/// common keywords) to make a 30-line diff readable in the notch without
/// pulling in highlight.js or per-language grammars.
///
/// Language is detected from the file path's extension; unknown extensions
/// fall back to the universal rule set (no keywords).
enum LightweightSyntaxHighlighter {
    /// Per-token foreground colors. Drive these from the active
    /// `ThemePalette` at the call site so theme switches recolor the
    /// diff without re-rendering content. Catppuccin convention is
    /// mauve for keywords, green for strings, overlay0 for comments,
    /// peach for numbers, text for plain code.
    struct TokenColors {
        var keyword: Color
        var string: Color
        var comment: Color
        var number: Color
        var plain: Color

        /// Builds a token palette from a `ThemePalette`. Call this once
        /// per render pass (not per token) to keep `Color` allocation
        /// out of the inner loop.
        static func from(palette: ThemePalette) -> TokenColors {
            TokenColors(
                keyword: palette.mauve.swiftUIColor,
                string: palette.green.swiftUIColor,
                comment: palette.overlay0.swiftUIColor,
                number: palette.peach.swiftUIColor,
                plain: palette.text.swiftUIColor
            )
        }
    }

    /// Returns an `AttributedString` with monospaced font and per-token
    /// foreground colors. Whitespace and unrecognized text use the
    /// `plain` color from `colors`.
    static func attribute(
        _ source: String,
        language: Language?,
        colors: TokenColors
    ) -> AttributedString {
        var attributed = AttributedString(source)
        attributed.font = .system(size: 11, design: .monospaced)
        attributed.foregroundColor = colors.plain

        for rule in rules(for: language, colors: colors) {
            apply(rule: rule, to: &attributed, in: source)
        }
        return attributed
    }

    /// Maps a file path to a known language, or nil to use universal-only
    /// rules (strings + numbers + line comments only).
    static func language(forFilePath path: String) -> Language? {
        let lower = path.lowercased()
        if let ext = (lower as NSString).pathExtension.nonEmpty {
            return Language.fromExtension(ext)
        }
        return nil
    }

    // MARK: - Language

    enum Language {
        case swift
        case typescript
        case javascript
        case python
        case rust
        case go
        case ruby
        case shell
        case generic

        static func fromExtension(_ ext: String) -> Language? {
            switch ext {
            case "swift":                       return .swift
            case "ts", "tsx":                   return .typescript
            case "js", "jsx", "mjs", "cjs":     return .javascript
            case "py":                          return .python
            case "rs":                          return .rust
            case "go":                          return .go
            case "rb":                          return .ruby
            case "sh", "bash", "zsh":           return .shell
            case "json", "yaml", "yml", "toml": return .generic
            default:                            return nil
            }
        }
    }

    // MARK: - Rules

    private struct Rule {
        let regex: NSRegularExpression
        let color: Color
        /// Index of the capture group whose range gets the color (0 = whole
        /// match). Lets us skip leading delimiters when they overlap other
        /// rules.
        let captureIndex: Int

        init?(_ pattern: String, color: Color, options: NSRegularExpression.Options = [], captureIndex: Int = 0) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            self.regex = regex
            self.color = color
            self.captureIndex = captureIndex
        }
    }

    /// Rules are applied in order; later rules override earlier ones for
    /// overlapping ranges, so put strings/comments last so they don't get
    /// recolored by keyword matching that happened first.
    private static func rules(for language: Language?, colors: TokenColors) -> [Rule] {
        var rules: [Rule] = []

        if let language {
            rules.append(contentsOf: keywordRules(for: language, color: colors.keyword))
        }
        if let numberRule = Rule(#"\b\d+(\.\d+)?\b"#, color: colors.number) {
            rules.append(numberRule)
        }
        if let r1 = Rule(#""([^"\\\n]|\\.)*""#, color: colors.string) { rules.append(r1) }
        if let r2 = Rule(#"'([^'\\\n]|\\.)*'"#, color: colors.string) { rules.append(r2) }

        switch language {
        case .swift, .typescript, .javascript, .rust, .go:
            if let r = Rule(#"//[^\n]*"#, color: colors.comment) { rules.append(r) }
            if let r = Rule(#"/\*[\s\S]*?\*/"#, color: colors.comment, options: [.dotMatchesLineSeparators]) {
                rules.append(r)
            }
        case .python, .ruby, .shell:
            if let r = Rule(#"#[^\n]*"#, color: colors.comment) { rules.append(r) }
        case .generic, .none:
            // Be conservative: only treat // as comments when we know the
            // host language uses them (avoids breaking JSON values like
            // "https://example.com").
            break
        }
        return rules
    }

    private static func keywordRules(for language: Language, color: Color) -> [Rule] {
        let keywords: [String]
        switch language {
        case .swift:
            keywords = ["let", "var", "func", "class", "struct", "enum", "protocol", "extension",
                        "if", "else", "guard", "switch", "case", "default", "for", "while", "do",
                        "return", "throw", "throws", "try", "catch", "import", "public", "private",
                        "internal", "fileprivate", "static", "self", "init", "deinit", "true", "false", "nil"]
        case .typescript, .javascript:
            keywords = ["const", "let", "var", "function", "class", "interface", "type", "enum",
                        "if", "else", "switch", "case", "default", "for", "while", "do", "return",
                        "throw", "try", "catch", "import", "export", "from", "as", "async", "await",
                        "public", "private", "protected", "static", "this", "new", "null", "undefined",
                        "true", "false"]
        case .python:
            keywords = ["def", "class", "import", "from", "as", "if", "elif", "else", "for", "while",
                        "return", "yield", "try", "except", "finally", "raise", "with", "lambda",
                        "pass", "break", "continue", "True", "False", "None", "and", "or", "not", "is", "in"]
        case .rust:
            keywords = ["let", "mut", "fn", "struct", "enum", "trait", "impl", "pub", "use", "mod",
                        "if", "else", "match", "for", "while", "loop", "return", "break", "continue",
                        "true", "false", "self", "Self", "ref", "as", "where"]
        case .go:
            keywords = ["func", "type", "struct", "interface", "package", "import", "var", "const",
                        "if", "else", "switch", "case", "default", "for", "range", "return",
                        "go", "defer", "chan", "true", "false", "nil"]
        case .ruby:
            keywords = ["def", "class", "module", "if", "elsif", "else", "unless", "case", "when",
                        "do", "end", "return", "yield", "begin", "rescue", "ensure", "raise",
                        "true", "false", "nil", "self", "require", "include"]
        case .shell:
            keywords = ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                        "case", "esac", "function", "return", "in"]
        case .generic:
            return []
        }

        let pattern = "\\b(?:" + keywords.joined(separator: "|") + ")\\b"
        guard let rule = Rule(pattern, color: color) else { return [] }
        return [rule]
    }

    // MARK: - Apply

    private static func apply(rule: Rule, to attributed: inout AttributedString, in source: String) {
        let fullNSRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = rule.regex.matches(in: source, options: [], range: fullNSRange)
        for match in matches {
            guard rule.captureIndex < match.numberOfRanges else { continue }
            let nsRange = match.range(at: rule.captureIndex)
            guard nsRange.location != NSNotFound,
                  let stringRange = Range(nsRange, in: source),
                  let attrRange = attributedRange(in: attributed, source: source, stringRange: stringRange) else {
                continue
            }
            attributed[attrRange].foregroundColor = rule.color
        }
    }

    /// Convert a `Range<String.Index>` on `source` into an `AttributedString`
    /// index range. Necessary because matching by substring (`range(of:)`)
    /// would hit the first occurrence rather than the matched position.
    private static func attributedRange(
        in attributed: AttributedString,
        source: String,
        stringRange: Range<String.Index>
    ) -> Range<AttributedString.Index>? {
        let lowerOffset = source.utf16.distance(from: source.startIndex, to: stringRange.lowerBound)
        let upperOffset = source.utf16.distance(from: source.startIndex, to: stringRange.upperBound)
        let unicodeScalars = attributed.unicodeScalars
        let start = unicodeScalars.index(unicodeScalars.startIndex, offsetBy: lowerOffset, limitedBy: unicodeScalars.endIndex)
        let end = unicodeScalars.index(unicodeScalars.startIndex, offsetBy: upperOffset, limitedBy: unicodeScalars.endIndex)
        guard let start, let end else { return nil }
        return start..<end
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
