import Foundation

/// Redacts local-machine details and obvious secrets from text that may be
/// visible on a livestream or screen share. The redactor is intentionally
/// conservative: it keeps enough shape for the user to understand the event
/// while removing values that commonly identify a machine, account, repo path,
/// or credential.
public enum LiveCodingRedactor {
    public static func redact(
        _ text: String,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        guard !text.isEmpty else { return text }

        var redacted = text
        redacted = redactKeyValueSecrets(in: redacted)
        redacted = replace(
            in: redacted,
            pattern: #"(?i)(Authorization:\s*Bearer\s+)[A-Za-z0-9._~+/\-]+=*"#,
            transform: { match in
                guard let prefix = capture(1, in: match) else { return "<redacted>" }
                return "\(prefix)<redacted>"
            }
        )
        redacted = replace(
            in: redacted,
            pattern: #"\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\b"#,
            transform: { _ in "<secret>" }
        )
        redacted = replace(
            in: redacted,
            pattern: #"\bsk-[A-Za-z0-9_\-]{20,}\b"#,
            transform: { _ in "<secret>" }
        )
        redacted = replace(
            in: redacted,
            pattern: #"\b(?:ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}\b"#,
            transform: { _ in "<secret>" }
        )
        redacted = replace(
            in: redacted,
            pattern: #"\b[A-Fa-f0-9]{40,}\b"#,
            transform: { _ in "<secret>" }
        )
        redacted = redactPaths(in: redacted, homeDirectory: homeDirectory)
        return redacted
    }

    private static func redactKeyValueSecrets(in text: String) -> String {
        replace(
            in: text,
            pattern: #"(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASS|API[_-]?KEY|AUTH)[A-Z0-9_]*)\s*=\s*("[^"]*"|'[^']*'|[^\s]+)"#,
            transform: { match in
                guard let key = capture(1, in: match) else { return "<redacted>" }
                return "\(key)=<redacted>"
            }
        )
    }

    private static func redactPaths(in text: String, homeDirectory: String) -> String {
        var redacted = text
        let normalizedHome = trimTrailingSlashes(homeDirectory)
        if !normalizedHome.isEmpty {
            redacted = replace(
                in: redacted,
                pattern: #"(?<![A-Za-z0-9_])\#(NSRegularExpression.escapedPattern(for: normalizedHome))(?:/[^\s"'`]+)*"#,
                transform: { match in summarizedPath(match.fullMatch, homeDirectory: normalizedHome) }
            )
        }

        redacted = replace(
            in: redacted,
            pattern: #"(?<![A-Za-z0-9_])/(?:Users|Volumes)/[^\s"'`]+(?:/[^\s"'`]+)*"#,
            transform: { match in summarizedPath(match.fullMatch, homeDirectory: normalizedHome) }
        )
        redacted = replace(
            in: redacted,
            pattern: #"(?<![:/A-Za-z0-9_])/(?:[A-Za-z0-9._-]+/){1,}[A-Za-z0-9._-]+"#,
            transform: { match in summarizedPath(match.fullMatch, homeDirectory: normalizedHome) }
        )
        return redacted
    }

    private static func summarizedPath(_ rawPath: String, homeDirectory: String) -> String {
        let path = trimTrailingSlashes(rawPath)
        guard !path.isEmpty else { return rawPath }

        let lastComponent = URL(fileURLWithPath: path).lastPathComponent
        if !homeDirectory.isEmpty, path == homeDirectory {
            return "~"
        }
        if !homeDirectory.isEmpty, path.hasPrefix(homeDirectory + "/") {
            return lastComponent.isEmpty ? "~" : "~/.../\(lastComponent)"
        }
        if path.hasPrefix("/Users/") {
            return lastComponent.isEmpty ? "/Users/<user>" : "/Users/<user>/.../\(lastComponent)"
        }
        if path.hasPrefix("/Volumes/") {
            return lastComponent.isEmpty ? "/Volumes/<volume>" : "/Volumes/<volume>/.../\(lastComponent)"
        }
        if path.hasPrefix("/") {
            return lastComponent.isEmpty ? "/..." : "/.../\(lastComponent)"
        }
        return rawPath
    }

    private static func trimTrailingSlashes(_ value: String) -> String {
        var trimmed = value
        while trimmed.count > 1, trimmed.last == "/" {
            trimmed.removeLast()
        }
        return trimmed
    }

    private struct RegexMatch {
        var fullMatch: String
        var captures: [String?]
    }

    private static func capture(_ index: Int, in match: RegexMatch) -> String? {
        guard index > 0, index <= match.captures.count else { return nil }
        return match.captures[index - 1]
    }

    private static func replace(
        in text: String,
        pattern: String,
        transform: (RegexMatch) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else {
                continue
            }
            let originalFullRange = match.range
            let fullMatch = nsText.substring(with: originalFullRange)
            let captures = (1..<match.numberOfRanges).map { index -> String? in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }

            result.replaceSubrange(
                fullRange,
                with: transform(RegexMatch(fullMatch: fullMatch, captures: captures))
            )
        }
        return result
    }
}
