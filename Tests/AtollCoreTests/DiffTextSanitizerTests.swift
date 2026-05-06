import Foundation
import Testing
@testable import AtollCore

struct DiffTextSanitizerTests {
    @Test
    func plainAsciiPassesThrough() {
        let result = DiffTextSanitizer.sanitize("let a = 1")
        #expect(result.text == "let a = 1")
        #expect(result.hadHiddenCharacters == false)
    }

    @Test
    func emptyStringIsClean() {
        let result = DiffTextSanitizer.sanitize("")
        #expect(result.text == "")
        #expect(result.hadHiddenCharacters == false)
    }

    @Test
    func acceptsUnicodeIdentifiersAndAccents() {
        // Non-ASCII text that's NOT in the danger list should be left alone.
        let result = DiffTextSanitizer.sanitize("élève — 中文")
        #expect(result.text == "élève — 中文")
        #expect(result.hadHiddenCharacters == false)
    }

    @Test
    func detectsRTLOverride() {
        // U+202E RIGHT-TO-LEFT OVERRIDE — Trojan Source flagship attack.
        let payload = "if user.isAdmin { \u{202E}/* tnemmoc */ grantAccess() }"
        let result = DiffTextSanitizer.sanitize(payload)
        #expect(result.hadHiddenCharacters == true)
        #expect(result.text.contains("⟨U+202E⟩"))
        #expect(!result.text.contains("\u{202E}"))
    }

    @Test
    func detectsZeroWidthSpace() {
        // U+200B inserted in the middle of an identifier — visually
        // identical to the original but semantically different.
        let payload = "function authentic\u{200B}ate(user) { exfil(user) }"
        let result = DiffTextSanitizer.sanitize(payload)
        #expect(result.hadHiddenCharacters == true)
        #expect(result.text.contains("⟨U+200B⟩"))
    }

    @Test
    func detectsSoftHyphen() {
        let result = DiffTextSanitizer.sanitize("ad\u{00AD}min")
        #expect(result.hadHiddenCharacters == true)
        #expect(result.text.contains("⟨U+AD⟩"))
    }

    @Test
    func detectsLineParagraphSeparators() {
        let withLine = DiffTextSanitizer.sanitize("a\u{2028}b")
        let withPara = DiffTextSanitizer.sanitize("a\u{2029}b")
        #expect(withLine.hadHiddenCharacters == true)
        #expect(withPara.hadHiddenCharacters == true)
    }

    @Test
    func multipleOccurrencesAllReplaced() {
        let payload = "\u{202E}a\u{202E}b\u{202E}"
        let result = DiffTextSanitizer.sanitize(payload)
        #expect(result.hadHiddenCharacters == true)
        // Three replacements expected.
        let occurrences = result.text.components(separatedBy: "⟨U+202E⟩").count - 1
        #expect(occurrences == 3)
    }

    @Test
    func legitimateNewlinesAndTabsArePreserved() {
        // \n, \r, \t are NOT in the danger list — they're legit text.
        let result = DiffTextSanitizer.sanitize("a\tb\nc")
        #expect(result.text == "a\tb\nc")
        #expect(result.hadHiddenCharacters == false)
    }
}
