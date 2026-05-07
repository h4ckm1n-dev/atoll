import Foundation

/// Errors thrown when a string cannot be safely embedded inside an
/// AppleScript double-quoted literal.
///
/// - `invalidControlChar`: the input contained CR, LF, U+2028, U+2029, or
///   NUL — characters that change AppleScript parsing semantics or that
///   downstream tools (osascript, Apple Events) treat as line terminators.
///   We reject rather than escape because there is no portable inline
///   representation across every site that interpolates these strings.
/// - `tooLong`: the input exceeds the configured byte budget. Bounding
///   length keeps the constructed AppleScript well under osascript's
///   command-line limit and protects against pathological pane titles
///   or working directories used as DoS vectors.
enum AppleScriptStringError: Error {
    case invalidControlChar
    case tooLong
}

/// Escapes a string for safe interpolation into an AppleScript
/// double-quoted literal.
///
/// Rejects control characters that could change parsing semantics
/// (carriage return, line feed, U+2028 line separator, U+2029 paragraph
/// separator, NUL). Caps length at `maxBytes` UTF-8 bytes (default 1024)
/// to bound script size.
///
/// - Parameter s: the raw string to escape.
/// - Parameter maxBytes: the maximum allowed UTF-8 byte length (default 1024).
/// - Returns: the escaped string with `\` and `"` doubled into AppleScript-safe form.
/// - Throws: `AppleScriptStringError.invalidControlChar` or `AppleScriptStringError.tooLong`.
func escapeAppleScriptStrict(_ s: String, maxBytes: Int = 1024) throws -> String {
    if s.utf8.count > maxBytes { throw AppleScriptStringError.tooLong }
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\u{00}", "\r", "\n", "\u{2028}", "\u{2029}":
            throw AppleScriptStringError.invalidControlChar
        default:
            break
        }
    }
    var out = ""
    out.reserveCapacity(s.count + 8)
    for ch in s {
        if ch == "\\" {
            out.append("\\\\")
        } else if ch == "\"" {
            out.append("\\\"")
        } else {
            out.append(ch)
        }
    }
    return out
}
