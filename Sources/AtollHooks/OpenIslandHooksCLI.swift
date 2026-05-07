import Foundation
import AtollCore

@main
struct OpenIslandHooksCLI {
    private static let interactiveClaudeHookTimeout: TimeInterval = 24 * 60 * 60

    private enum HookSource: String {
        case codex
        case claude
        case qoder
        case qwen
        case factory
        case droid
        case codebuddy
        case cursor
        case gemini
        case kimi

        var isClaudeFormat: Bool {
            switch self {
            case .claude, .qoder, .qwen, .factory, .droid, .codebuddy, .kimi:
                return true
            case .codex, .cursor, .gemini:
                return false
            }
        }
    }

    static func main() {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard !input.isEmpty else {
                return
            }

            let arguments = Array(CommandLine.arguments.dropFirst())
            let source: HookSource
            do {
                source = try hookSource(arguments: arguments)
            } catch let error as InvalidHookSourceError {
                logStderr("invalid --source value: \(error.value); refusing to coerce")
                // Hooks must fail open — exit cleanly without writing a directive.
                return
            }
            let sourceString = rawSourceString(arguments: arguments)
            let decoder = JSONDecoder()
            let client = BridgeCommandClient(socketURL: BridgeSocketLocation.currentURL())

            switch source {
            case .codex:
                let payload = try decoder
                    .decode(CodexHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                guard let response = try? client.send(.processCodexHook(payload)) else {
                    logStderr("bridge unavailable for codex hook")
                    return
                }

                if let output = try CodexHookOutputEncoder.standardOutput(for: response) {
                    FileHandle.standardOutput.write(output)
                }
            case .claude, .qoder, .qwen, .factory, .droid, .codebuddy, .kimi:
                var payload = try decoder
                    .decode(ClaudeHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)
                payload.hookSource = sourceString

                let timeout = payload.hookEventName == .permissionRequest
                    ? interactiveClaudeHookTimeout
                    : 45

                guard let response = try? client.send(.processClaudeHook(payload), timeout: timeout) else {
                    logStderr("bridge unavailable for claude hook (\(payload.hookEventName.rawValue))")
                    return
                }

                if let output = try ClaudeHookOutputEncoder.standardOutput(for: response) {
                    FileHandle.standardOutput.write(output)
                }
            case .cursor:
                let payload = try decoder.decode(CursorHookPayload.self, from: input)

                let timeout: TimeInterval = payload.isBlockingHook
                    ? Self.interactiveClaudeHookTimeout
                    : 45

                guard let response = try? client.send(.processCursorHook(payload), timeout: timeout) else {
                    return
                }

                if case let .cursorHookDirective(directive) = response {
                    let encoder = JSONEncoder()
                    let output = try encoder.encode(directive)
                    FileHandle.standardOutput.write(output)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
            case .gemini:
                let payload = try decoder
                    .decode(GeminiHookPayload.self, from: input)
                    .withRuntimeContext(environment: ProcessInfo.processInfo.environment)

                _ = try? client.send(.processGeminiHook(payload), timeout: 45)
            }
        } catch {
            // Hooks should fail open so the CLI continues working even if the bridge is unavailable.
            logStderr("hook failed: \(error)")
        }
    }

    private static func logStderr(_ message: String) {
        guard let data = "[OpenIslandHooks] \(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    /// Thrown when the user passes `--source <unknown>` — we refuse to coerce
    /// silently to `.codex` because the choice changes the wire decoder and a
    /// malformed value would mis-route a hostile payload.
    struct InvalidHookSourceError: Error {
        let value: String
    }

    private static func hookSource(arguments: [String]) throws -> HookSource {
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--source", index + 1 < arguments.count {
                let raw = arguments[index + 1]
                guard let source = HookSource(rawValue: raw) else {
                    throw InvalidHookSourceError(value: raw)
                }
                return source
            }

            index += 1
        }

        return .codex
    }

    private static func rawSourceString(arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--source", index + 1 < arguments.count {
                return arguments[index + 1]
            }

            index += 1
        }

        return nil
    }
}
