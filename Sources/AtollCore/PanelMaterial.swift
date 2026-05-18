import Foundation

/// Controls how the opened-panel surface fills behind the agent rows.
/// Persisted via `@AppStorage("appearance.panelMaterial")` as the
/// raw String. Default `.solid` so existing users see no forced
/// behavior change.
public enum AppPanelMaterial: String, Codable, CaseIterable, Sendable {
    /// `palette.mantle` solid fill — the v1.0 ocean-night look.
    case solid
    /// `.thinMaterial` + `palette.crust.opacity(0.55)` overlay.
    /// Frosted glass with a strong theme tint still bleeding through.
    case frostedThin = "frosted-thin"
    /// `.ultraThinMaterial` + `palette.crust.opacity(0.55)` overlay.
    /// More translucent — wallpaper bleeds through more visibly.
    case frostedUltraThin = "frosted-ultra-thin"
    /// Liquid Glass-inspired material with a brighter refractive edge and
    /// a subtle moving highlight.
    case liquidGlass = "liquid-glass"

    /// Localization key suffix used by the picker labels.
    public var localizationKey: String {
        switch self {
        case .solid:             return "settings.panelMaterial.solid"
        case .frostedThin:       return "settings.panelMaterial.frostedThin"
        case .frostedUltraThin:  return "settings.panelMaterial.frostedUltraThin"
        case .liquidGlass:       return "settings.panelMaterial.liquidGlass"
        }
    }
}
