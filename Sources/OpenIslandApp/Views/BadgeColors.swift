import SwiftUI
import OpenIslandCore

enum BadgeColors {
    /// Distinct per-agent tint for the agent badge text. Picked to match
    /// the agent's brand association where one is obvious (Claude=peach,
    /// Codex=green, etc.) and remapped to the active `ThemePalette` so the
    /// reconnaissable hue follows the theme: switching to Latte (light)
    /// turns Claude's orange into Latte's peach, not raw `Color.orange`.
    static func agent(_ tool: AgentTool, palette: ThemePalette = .mocha) -> Color {
        switch tool {
        case .claudeCode: return palette.peach.swiftUIColor
        case .codex:      return palette.green.swiftUIColor
        case .cursor:     return palette.sky.swiftUIColor
        case .geminiCLI:  return palette.mauve.swiftUIColor
        case .openCode:   return palette.teal.swiftUIColor
        case .qoder:      return palette.pink.swiftUIColor
        case .qwenCode:   return palette.red.swiftUIColor
        case .factory:    return palette.yellow.swiftUIColor
        case .codebuddy:  return palette.flamingo.swiftUIColor
        case .kimiCLI:    return palette.lavender.swiftUIColor
        }
    }

    /// Distinct per-terminal tint. Substring match on the terminal
    /// app/badge name — falls back to overlay tone for unknowns.
    static func terminal(_ name: String, palette: ThemePalette = .mocha) -> Color {
        let lower = name.lowercased()
        if lower.contains("cmux") || lower.contains("tmux")     { return palette.green.swiftUIColor }
        if lower.contains("ghostty")                            { return palette.mauve.swiftUIColor }
        if lower.contains("iterm")                              { return palette.sapphire.swiftUIColor }
        if lower.contains("terminal")                           { return palette.subtext1.swiftUIColor }
        if lower.contains("warp")                               { return palette.peach.swiftUIColor }
        if lower.contains("wezterm")                            { return palette.maroon.swiftUIColor }
        if lower.contains("zellij")                             { return palette.yellow.swiftUIColor }
        if lower.contains("kaku")                               { return palette.pink.swiftUIColor }
        if lower.contains("vs code") || lower.contains("vscode") { return palette.blue.swiftUIColor }
        if lower.contains("cursor")                             { return palette.sky.swiftUIColor }
        if lower.contains("windsurf")                           { return palette.teal.swiftUIColor }
        return palette.subtext0.swiftUIColor
    }
}
