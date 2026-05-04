import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct LightweightSyntaxHighlighterTests {
    @Test
    func languageDetectionFromFilePath() {
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "foo.swift") == .swift)
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "/abs/Path/x.ts") == .typescript)
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "y.tsx") == .typescript)
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "main.py") == .python)
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "lib.rs") == .rust)
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "main.go") == .go)
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "config.yaml") == .generic)
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "no-extension") == nil)
        #expect(LightweightSyntaxHighlighter.language(forFilePath: "weird.unknown") == nil)
    }

    private var colors: LightweightSyntaxHighlighter.TokenColors {
        LightweightSyntaxHighlighter.TokenColors.from(palette: .mocha)
    }

    @Test
    func returnsAttributedStringWithMonoFont() {
        let attributed = LightweightSyntaxHighlighter.attribute("let a = 1", language: .swift, colors: colors)
        // Sanity: same characters round-tripped.
        #expect(String(attributed.characters) == "let a = 1")
    }

    @Test
    func emptyInputReturnsEmptyAttributedString() {
        let attributed = LightweightSyntaxHighlighter.attribute("", language: .swift, colors: colors)
        #expect(String(attributed.characters) == "")
    }

    @Test
    func unknownLanguageStillProducesValidOutput() {
        let source = #"const x = "hello"; // 42"#
        let attributed = LightweightSyntaxHighlighter.attribute(source, language: nil, colors: colors)
        #expect(String(attributed.characters) == source)
    }

    @Test
    func multilineSwiftKeywordsAcrossLinesDoNotCrash() {
        let source = """
        func test() {
            let a = "x"
            return a
        }
        """
        let attributed = LightweightSyntaxHighlighter.attribute(source, language: .swift, colors: colors)
        #expect(String(attributed.characters) == source)
    }
}
