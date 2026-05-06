import Foundation
import Observation
import AtollCore
import SwiftUI

/// Holds the active `AppTheme` and exposes the resolved `ThemePalette`
/// to SwiftUI views via `@Observable`. Persisted in UserDefaults so the
/// user's choice survives restarts. Default value is `.catppuccinMocha`
/// — the rebrand ships on by default with `.system` available as an
/// opt-out.
@Observable
@MainActor
public final class ThemeManager {
    public private(set) var theme: AppTheme

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "appearance.theme"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let raw = defaults.string(forKey: storageKey),
           let stored = AppTheme(rawValue: raw) {
            self.theme = stored
        } else {
            self.theme = .catppuccinMocha
        }
    }

    public var palette: ThemePalette { theme.palette }

    public func setTheme(_ theme: AppTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        defaults.set(theme.rawValue, forKey: storageKey)
    }
}

extension ProjectColor {
    /// SwiftUI bridge. The Core type stays SwiftUI-free so it can be
    /// shared with the bridge / hooks targets; views convert at the
    /// boundary.
    public var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}

private struct ThemePaletteEnvironmentKey: EnvironmentKey {
    /// Default falls back to Mocha (the same default ThemeManager
    /// uses on first launch). Views that read this without an
    /// injecting ancestor still render — useful in previews.
    static let defaultValue: ThemePalette = .mocha
}

extension EnvironmentValues {
    /// Active palette, mirroring `themeManager.palette`. Views read
    /// this via `@Environment(\.themePalette)`. Injection happens at
    /// the App root in `OpenIslandApp.body` so the value tracks the
    /// `ThemeManager.theme` and `previewPalette` automatically.
    public var themePalette: ThemePalette {
        get { self[ThemePaletteEnvironmentKey.self] }
        set { self[ThemePaletteEnvironmentKey.self] = newValue }
    }
}

/// Wraps a SwiftUI subtree and re-injects `\.themePalette` from the
/// supplied `ThemeManager` on every body invalidation. Used by AppKit
/// hosting roots (`NSHostingView` / `NSHostingController`) — passing
/// `themeManager.palette` directly into `.environment` at host-init
/// time captures a stale value that doesn't update when the user
/// switches theme. Wrapping in this view forces SwiftUI's Observation
/// machinery to re-read `themeManager.palette` whenever the theme
/// changes, so the env value tracks the live palette.
public struct ThemedHostingRoot<Content: View>: View {
    let themeManager: ThemeManager
    let content: Content

    public init(themeManager: ThemeManager, @ViewBuilder content: () -> Content) {
        self.themeManager = themeManager
        self.content = content()
    }

    public var body: some View {
        content
            .environment(\.themePalette, themeManager.palette)
    }
}
