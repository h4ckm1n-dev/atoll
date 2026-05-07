import Foundation
import Observation
import AtollCore
import SwiftUI

/// Holds the active `AppTheme` and exposes the resolved `ThemePalette`
/// to SwiftUI views via `@Observable`. Persisted in UserDefaults so the
/// user's choice survives restarts. Default value is `.mocha`
/// — the rebrand ships on by default with `.system` available as an
/// opt-out.
@Observable
@MainActor
public final class ThemeManager {
    public private(set) var theme: AppTheme

    public private(set) var customRegistry: CustomThemeRegistry

    // previewPalette is added in Phase 3 (editor). Stubbed nil so
    // Phase 2 compiles cleanly without the editor.
    public var previewPalette: ThemePalette? = nil

    // In-memory mirror of the actor's themes so `palette` (a
    // synchronous getter on @Observable @MainActor) doesn't need to
    // `await`. The mirror is refreshed via `loadCustomThemes()` and after
    // every save/delete via `refreshCustomThemes()`.
    private var customThemeCache: [UUID: CustomTheme] = [:]

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "appearance.theme"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        if let raw = defaults.string(forKey: storageKey),
           let stored = AppTheme(stableID: raw) {
            self.theme = stored
        } else {
            self.theme = .mocha
        }
        self.customRegistry = CustomThemeRegistry()
    }

    public var palette: ThemePalette {
        if let preview = previewPalette { return preview }
        if case .custom(let id) = theme {
            // Custom resolution requires the registry's cached themes.
            // The cache is populated by `loadCustomThemes()` on app start;
            // until then `.custom` falls back to mocha.
            if let custom = customThemeCache[id] { return custom.palette }
            return .mocha
        }
        return theme.builtInPalette ?? .mocha
    }

    public func setTheme(_ theme: AppTheme) {
        guard self.theme != theme else { return }
        self.theme = theme
        defaults.set(theme.stableID, forKey: storageKey)
    }

    public func loadCustomThemes() async {
        do {
            try await customRegistry.load()
        } catch {
            // Registry IO errors should not crash the app — log and keep
            // going with an empty library.
            FileHandle.standardError.write(
                Data("Atoll: failed to load custom themes: \(error)\n".utf8)
            )
        }
        await refreshCustomThemes()
    }

    public func refreshCustomThemes() async {
        let themes = await customRegistry.themes
        customThemeCache = Dictionary(uniqueKeysWithValues: themes.map { ($0.id, $0) })
    }

    /// All custom themes, in the order the picker should display them
    /// (oldest first — matches creation order, stable across launches).
    public var customThemes: [CustomTheme] {
        Array(customThemeCache.values).sorted { $0.createdAt < $1.createdAt }
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
