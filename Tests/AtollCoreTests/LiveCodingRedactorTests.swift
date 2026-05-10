import Testing
@testable import AtollCore

struct LiveCodingRedactorTests {
    @Test
    func redactsHomeDirectoryPathsToLastComponent() {
        let input = "Running swift test in /Users/alice/Projects/SecretClient/OpenIsland"

        let output = LiveCodingRedactor.redact(
            input,
            homeDirectory: "/Users/alice"
        )

        #expect(output == "Running swift test in ~/.../OpenIsland")
    }

    @Test
    func redactsOtherUserPathsWithoutLeakingUsername() {
        let input = "Edit /Users/bob/private/repo/Sources/App.swift"

        let output = LiveCodingRedactor.redact(
            input,
            homeDirectory: "/Users/alice"
        )

        #expect(output == "Edit /Users/<user>/.../App.swift")
    }

    @Test
    func redactsCommonSecretShapes() {
        let input = "OPENAI_API_KEY=sk-1234567890abcdefghijklmnop Authorization: Bearer abc.def.ghi ghp_abcdefghijklmnopqrstuvwxyz"

        let output = LiveCodingRedactor.redact(input)

        #expect(output == "OPENAI_API_KEY=<redacted> Authorization: Bearer <redacted> <secret>")
    }

    @Test
    func redactsLongHexTokens() {
        let input = "token 0123456789abcdef0123456789abcdef01234567"

        let output = LiveCodingRedactor.redact(input)

        #expect(output == "token <secret>")
    }

    @Test
    func leavesOrdinaryStatusTextReadable() {
        let input = "Patch applied. Running tests now. See https://example.com/docs/path."

        let output = LiveCodingRedactor.redact(input)

        #expect(output == input)
    }
}
