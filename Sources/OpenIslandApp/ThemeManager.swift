import Foundation
import Observation
import OpenIslandCore
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
