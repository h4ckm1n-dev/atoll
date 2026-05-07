import XCTest
@testable import AtollApp

final class AppleScriptStringTests: XCTestCase {

    // MARK: - Acceptance

    func testAcceptsSimpleAscii() throws {
        XCTAssertEqual(try escapeAppleScriptStrict("hello world"), "hello world")
    }

    func testEscapesBackslash() throws {
        XCTAssertEqual(try escapeAppleScriptStrict("a\\b"), "a\\\\b")
    }

    func testEscapesDoubleQuote() throws {
        XCTAssertEqual(try escapeAppleScriptStrict("she said \"hi\""),
                       "she said \\\"hi\\\"")
    }

    func testEscapesBackslashAndQuoteCombined() throws {
        XCTAssertEqual(try escapeAppleScriptStrict("\\\""),
                       "\\\\\\\"")
    }

    func testAcceptsEmoji() throws {
        let result = try escapeAppleScriptStrict("hello 🍣 ☕️")
        XCTAssertEqual(result, "hello 🍣 ☕️")
    }

    func testAcceptsExactly1024Bytes() throws {
        let s = String(repeating: "a", count: 1024)
        XCTAssertEqual(try escapeAppleScriptStrict(s).count, 1024)
    }

    func testAcceptsTabCharacter() throws {
        // Tab is not in the rejected set — AppleScript handles it fine.
        XCTAssertEqual(try escapeAppleScriptStrict("a\tb"), "a\tb")
    }

    // MARK: - Rejection: control characters

    func testRejectsLineFeed() {
        XCTAssertThrowsError(try escapeAppleScriptStrict("a\nb")) { error in
            XCTAssertEqual(error as? AppleScriptStringError, .invalidControlChar)
        }
    }

    func testRejectsCarriageReturn() {
        XCTAssertThrowsError(try escapeAppleScriptStrict("a\rb")) { error in
            XCTAssertEqual(error as? AppleScriptStringError, .invalidControlChar)
        }
    }

    func testRejectsLineSeparatorU2028() {
        XCTAssertThrowsError(try escapeAppleScriptStrict("a\u{2028}b")) { error in
            XCTAssertEqual(error as? AppleScriptStringError, .invalidControlChar)
        }
    }

    func testRejectsParagraphSeparatorU2029() {
        XCTAssertThrowsError(try escapeAppleScriptStrict("a\u{2029}b")) { error in
            XCTAssertEqual(error as? AppleScriptStringError, .invalidControlChar)
        }
    }

    func testRejectsNul() {
        XCTAssertThrowsError(try escapeAppleScriptStrict("a\u{00}b")) { error in
            XCTAssertEqual(error as? AppleScriptStringError, .invalidControlChar)
        }
    }

    // MARK: - Rejection: length

    func testRejects2048ByteString() {
        let big = String(repeating: "a", count: 2048)
        XCTAssertThrowsError(try escapeAppleScriptStrict(big)) { error in
            XCTAssertEqual(error as? AppleScriptStringError, .tooLong)
        }
    }

    func testRejects1025ByteString() {
        let big = String(repeating: "a", count: 1025)
        XCTAssertThrowsError(try escapeAppleScriptStrict(big)) { error in
            XCTAssertEqual(error as? AppleScriptStringError, .tooLong)
        }
    }

    func testCustomMaxBytesEnforced() {
        XCTAssertThrowsError(try escapeAppleScriptStrict("hello", maxBytes: 3)) { error in
            XCTAssertEqual(error as? AppleScriptStringError, .tooLong)
        }
    }
}
