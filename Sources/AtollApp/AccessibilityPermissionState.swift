import ApplicationServices
import Foundation

/// Helper for inspecting and prompting the macOS Accessibility (AX) and
/// Apple-Events Automation TCC grants that Atoll needs for precision
/// jump, keystroke injection, and AppleScript-driven session probing.
///
/// macOS exposes AX trust through two flavors of the same C API:
///
/// 1. ``AXIsProcessTrusted()`` — pure status check, never prompts.
/// 2. ``AXIsProcessTrustedWithOptions(_:)`` with
///    `kAXTrustedCheckOptionPrompt = true` — same status check, but the
///    first time it returns `false` macOS shows the standard "<App> would
///    like to control this computer using accessibility features" prompt
///    and silently records the request so Atoll appears in
///    `System Settings → Privacy & Security → Accessibility`.
///
/// We separate these so callers that just want a UI hint (banner, "you
/// need to grant permission" affordance) can ask `isGranted` cheaply,
/// while callers that are about to invoke a privileged operation use
/// `ensureOrPrompt()` to make sure the user has at least seen the
/// prompt once before the operation silently no-ops.
@MainActor
enum AccessibilityPermissionState {

    /// Pure status check — never prompts. Use for banner/affordance display.
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Returns `true` if AX is granted, otherwise shows the macOS AX prompt
    /// (once per app launch — macOS deduplicates internally). Call once
    /// on the first jump / keystroke attempt so the user sees the prompt
    /// before the operation silently fails.
    @discardableResult
    static func ensureOrPrompt() -> Bool {
        // `kAXTrustedCheckOptionPrompt` is declared as a `var` in the
        // ApplicationServices module, which Swift 6 strict concurrency
        // flags as non-sendable shared mutable state. In practice the
        // value is constant after dynamic-load, and the AX C API is
        // thread-safe. Use a literal `CFString` of the known key
        // ("AXTrustedCheckOptionPrompt") to side-step the var reference.
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: CFDictionary = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}

/// AppleScript / Apple Events error codes we surface specially.
enum AppleEventErrorCode {
    /// `errAEEventNotPermitted` — the system blocked an Apple Event because
    /// the target app's Automation entry in TCC is missing or denied.
    /// Matches `error -1743` returned by NSAppleScript and osascript.
    static let notPermitted: Int = -1743
}
