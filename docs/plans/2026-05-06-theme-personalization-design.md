# Theme Personalization — Design

**Date:** 2026-05-06
**Status:** Approved (brainstorming complete; awaiting implementation plan via `writing-plans`)
**Owner:** h4ckm1n

## Goal

Make the active theme visibly impact the **whole** app (not just buttons + a few badges), and let users author their own themes — fork from a Catppuccin preset, tweak 26 colors with live preview, save, share via JSON export/import.

## Non-goals

- Per-app or per-project themes (Open Island theme is global).
- Snapshot / image-diff testing infrastructure.
- A community theme marketplace inside the app.
- Animated theme transitions (instant retint is fine).

## Architecture

### Palette propagation

Three coexisting paths:

1. **Existing explicit-parameter** (e.g. `IslandWideButtonStyle(palette:)`, `InlineDiffView(palette:)`) — kept unchanged to avoid churn at call sites already wired.
2. **Existing direct AppModel access** (`model.themeManager.palette`) — kept where the view already has the model.
3. **New SwiftUI `EnvironmentKey<ThemePalette>`** — injected at root by `OpenIslandApp.body`, mirrors `themeManager.palette`. Read via `@Environment(\.themePalette)`. Used by leaf views that don't otherwise need the model.

`ThemeManager` remains the single source of truth.

### `AppTheme` enum reshape

```swift
public enum AppTheme: Sendable, Hashable {
    case system, latte, frappe, macchiato, mocha
    case custom(id: UUID)
}
```

Codable shape: `{"kind":"mocha"}` for built-ins, `{"kind":"custom","id":"<uuid>"}` for custom. Backwards-compat: old `String` values like `"catppuccinMocha"` decode to `.mocha`.

`ThemeManager.palette` resolves `.custom(id:)` via `CustomThemeRegistry`; falls back to `.mocha` if the id is missing (file deleted out-of-band).

### Live preview during editing

```swift
@Observable @MainActor
public final class ThemeManager {
    public var theme: AppTheme
    public var previewPalette: ThemePalette?  // ← new

    public var palette: ThemePalette {
        previewPalette ?? resolved(theme)
    }
}
```

Editor sheet sets `previewPalette` on every picker drag tick → island retints in real-time. Cancel → clears. Save → writes file + flips `theme` to `.custom(id:)` + clears preview.

### Latte (light theme) support

No `if isLight` branching scattered through views. Instead:

| Pattern (old)            | Pattern (new)                    | Why it works                                           |
| ------------------------ | -------------------------------- | ------------------------------------------------------ |
| `.white.opacity(x)`      | `palette.text.opacity(x)`        | Latte text is dark, Mocha text is light → "subtle foreground tint" intent survives both. |
| `.black.opacity(x)`      | `palette.crust.opacity(x)`       | Stays "deep recessed" on dark, becomes "soft shadow" on Latte. |
| `Color.black` (surfaces) | `palette.crust`                  | Already done in `b80e6e0` for the opened panel.        |

Ultra-subtle 1px stroke overlays (`.white.opacity(0.04)`) that would vanish after the swap stay as `.white.opacity(...)` with an inline comment explaining the exception.

## Data model

### `CustomTheme` (in `OpenIslandCore`)

```swift
public struct CustomTheme: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var palette: ThemePalette
    public var basedOn: AppTheme   // tracks fork-from-preset
    public let createdAt: Date
    public var updatedAt: Date
}
```

### `ThemePalette` JSON schema

`ThemePalette` becomes `Codable`. Encoded as a flat dict of 26 hex strings keyed by role:

```json
{
  "schemaVersion": 1,
  "isLight": false,
  "base": "162232", "mantle": "10182a", "crust": "0a1220",
  "surface0": "263347", "surface1": "37475e", "surface2": "4a5b75",
  "text": "cdd6f4", "subtext1": "bac2de", "subtext0": "a6adc8",
  "overlay2": "9399b2", "overlay1": "7f849c", "overlay0": "6c7086",
  "rosewater": "f5e0dc", "flamingo": "f2cdcd", "pink": "f5c2e7",
  "mauve": "cba6f7", "red": "f38ba8", "maroon": "eba0ac",
  "peach": "fab387", "yellow": "f9e2af", "green": "a6e3a1",
  "teal": "94e2d5", "sky": "89dceb", "sapphire": "74c7ec",
  "blue": "89b4fa", "lavender": "b4befe"
}
```

`schemaVersion` lets future migrations detect old files. Decoder ignores unknown keys (forward-compat). Missing keys throw with localized error naming the missing role.

### On-disk layout

```
~/Library/Application Support/Open Island/
├── themes/
│   ├── <uuid-1>.json
│   ├── <uuid-2>.json
│   └── ...
└── project-colors.json   (already exists)
```

One file per theme — atomic write, drag-from-Finder shareability. UUID filenames so renames don't move files and special characters can't break paths.

### `CustomThemeRegistry`

```swift
public actor CustomThemeRegistry {
    public var themes: [CustomTheme] { get }
    public func load() async throws
    public func save(_ theme: CustomTheme) async throws
    public func delete(id: UUID) async throws
    public func duplicate(id: UUID) async throws -> CustomTheme
    public func importTheme(from url: URL) async throws -> CustomTheme
    public func exportTheme(_ theme: CustomTheme, to url: URL) async throws
}
```

Actor isolation (not `@unchecked Sendable` like `ProjectColorRegistry`) since file IO benefits from explicit isolation and we already require macOS 14+.

### Validation on import

- Hex regex `^[0-9a-fA-F]{6}$`
- Exactly 26 color keys present
- `schemaVersion ≤ current`

Malformed → throws `ThemeImportError` with localized message ("Theme file is missing the `green` color"). Settings UI shows the message in a banner. No partial state.

## UI surfaces

### Settings → Appearance (existing pane, extended)

```
┌─ Appearance ──────────────────────────────────────┐
│ Theme:  [Mocha ▾]                                 │
│                                                   │
│ ─── Custom themes ─────────────────────────       │
│ ┌──────────────────────────────────────────┐     │
│ │ ● my-night       [Edit] [Duplicate]   ⋯ │     │
│ │   forked from Mocha · today              │     │
│ ├──────────────────────────────────────────┤     │
│ │ ○ daylight       [Edit] [Duplicate]   ⋯ │     │
│ │   forked from Latte · 2d ago             │     │
│ └──────────────────────────────────────────┘     │
│ [+ Create from preset…]   [Import from file…]    │
└───────────────────────────────────────────────────┘
```

`⋯` reveals: Rename, Export…, Delete (with confirm).

### Theme picker (popup at top)

Grouped:

```
─ Built-in ─
  System, Latte, Frappé, Macchiato, Mocha
─ My themes ─
  my-night, daylight, …
```

### Editor sheet (Phase 3)

Modal sheet over Settings. Three disclosure groups:

- **Surfaces** (6): base, mantle, crust, surface0, surface1, surface2
- **Foregrounds** (6): text, subtext1, subtext0, overlay2, overlay1, overlay0
- **Accents** (14): rosewater, flamingo, pink, mauve, red, maroon, peach, yellow, green, teal, sky, sapphire, blue, lavender

Per row: swatch + hex field + system `ColorPicker`. Hex field is source of truth; both inputs sync. One toggle: "Light theme (use dark text)" → flips `isLight`.

Bottom bar: `[Reset to base]` `[Cancel]` `[Save]`.

### Bootstrap flow

"+ Create from preset…" → small dialog asks "Start from?" with the 5 built-ins → that palette copied into a draft → editor sheet opens → default name `<preset>-copy` (auto-incremented on collision).

## Color mapping (Phase 1 sweep)

| Old hardcoded color                                               | Semantic role         | New value                         |
| ----------------------------------------------------------------- | --------------------- | --------------------------------- |
| `Color(red: 0.43, 0.62, 1.0)` (#6E9FFF working blue)              | agent-working         | `palette.blue`                    |
| `Color(red: 0.26, 0.91, 0.42)` (#42E86B idle green)               | agent-idle            | `palette.green`                   |
| `Color(red: 0.34, 0.61, 0.99)` (working blue alt)                 | agent-working         | `palette.blue`                    |
| `Color(red: 0.29, 0.86, 0.46)` (success green alt)                | success               | `palette.green`                   |
| `Color(red: 0.45, 0.85, 0.55)` (completion green)                 | completion            | `palette.green`                   |
| `Color(red: 0.26, 0.45, 0.86)` (button primary)                   | primary CTA           | `palette.blue`                    |
| `Color(red: 0.85, 0.55, 0.15)` (button warning)                   | warning / caution     | `palette.peach`                   |
| `Color(red: 0.82, 0.22, 0.22)` (button danger)                    | danger / destructive  | `palette.red`                     |
| `.orange` / `.orange.opacity(...)` (attention, mute icon)         | attention             | `palette.peach`                   |
| `.yellow` / `.yellow.opacity(...)` (question prompts, plan mode)  | question / inquiry    | `palette.yellow`                  |
| `.cyan.opacity(...)`                                              | accent / cool         | `palette.sky`                     |
| `.red.opacity(...)`                                               | error                 | `palette.red`                     |
| `.green.opacity(...)`                                             | success               | `palette.green`                   |
| `Color(red: 0.11, 0.08, 0.03)` (warm dark card)                   | warning card surface  | `palette.surface0` + peach border |
| `Color(red: 0.14, 0.14, 0.15)` (count badge bg)                   | chrome capsule        | `palette.surface0`                |
| `Color.black.opacity(0.32)` (recessed panes)                      | recessed pane         | `palette.crust.opacity(0.45)`     |

`AmbientThemeOverlay` keeps its per-project tint (not theme-driven). `BadgeColors.swift` already palette-aware; only the unknown-agent fallback shifts to `palette.lavender`. `CelebrationParticles` triad → `palette.green` / `peach` / `lavender`.

## Testing

### Unit tests (extend existing `ThemeTests` suite)

- `PaletteRoleMappingTests` — for each built-in palette, semantic role → palette field is non-default.
- `LatteContrastTests` — Latte `text` luminance < 0.5; `base` luminance > 0.85.
- `CustomThemeCodableRoundtripTests` — encode → decode preserves all fields.
- `CustomThemeRegistryTests` (with temp dir):
  - save/load preserves fields
  - delete removes file
  - duplicate produces new UUID + `" copy"` suffix
  - import valid JSON → registered
  - import malformed JSON → throws `ThemeImportError`, no partial state
  - corrupt file in dir → skipped, others load
- `AppThemeMigrationTests` — old `"catppuccinMocha"` string decodes to `.mocha`; new `.custom(id:)` round-trips.
- `ThemePalettePreviewModeTests` — preview set/clear, save while preview active.
- `HexValidationTests` — accept `abcdef` / `ABCDEF` / `#abcdef`; reject `abc` / `xyz123` / empty.

### Manual verification (per phase)

1. Switch through System / Latte / Frappé / Macchiato / Mocha — each visibly different.
2. Open a permission request — Yes/No/Always Allow buttons retint per theme.
3. Open the plan checklist — recessed panels read on Latte.
4. Phase 2: import a hand-edited JSON → in list, picker switches.
5. Phase 3: drag a picker → island retints live. Cancel reverts. Save persists.

### CPU regression guard

Each phase: re-launch dev app, wait for session-discovery settle (~2 min), confirm idle ≤ 1% CPU. Phase 1 in particular touches the panel render path — easy to introduce a SwiftUI invalidation loop.

## Phase boundaries (swarm composition)

Each phase = own feature branch off latest `main` → PR → merge. No chained PRs.

### Phase 1 — Tinting sweep (`feat/theme-sweep`)

Replace 39 color sites. Refactor `.white.opacity` / `.black.opacity` chrome overlays. Add `EnvironmentKey<ThemePalette>` injected at root.

**Files:** `IslandPanelView.swift`, `SettingsView.swift`, `ControlCenterView.swift`, `PlanChecklistView.swift`, `CelebrationParticles.swift`, `BadgeColors.swift`, `AmbientThemeOverlay.swift`, `OpenIslandApp.swift`, `Theme.swift`.

**Swarm:** `architect` → `coder` → `tester` → `reviewer` (hierarchical, 4 agents, SendMessage chain, all `run_in_background: true`).

**Gate:** `swift build && swift test` green; manual switch through 5 themes; CPU settle ≤ 1%.

### Phase 2 — Custom theme model + library (`feat/theme-custom-registry`)

`CustomTheme`, `CustomThemeRegistry` actor, `AppTheme` enum-with-associated-value migration, `ThemePalette: Codable` with schemaVersion. Settings → Appearance "Themes" section: list with rename / duplicate / delete / **import** / **export** (no in-app editor yet).

**Files (new):** `Sources/OpenIslandCore/CustomTheme.swift`, `Sources/OpenIslandCore/CustomThemeRegistry.swift`. **(modified):** `Theme.swift`, `ThemeManager.swift`, `AppearanceSettingsPane.swift`, localized strings.

**Swarm:** `architect` (enum migration safety) → `coder` → `tester` (codable + registry + migration) → `reviewer` (security: malformed JSON, file IO error paths). Hierarchical, 4 agents.

**Gate:** migration test green; round-trip green; manually import a hand-written JSON; export, edit on disk, re-import.

### Phase 3 — In-app 26-picker editor (`feat/theme-editor`)

Editor sheet (3 disclosure groups), live preview via `themeManager.previewPalette`, hex + ColorPicker per row, isLight toggle, fork-from-preset bootstrap.

**Files (new):** `Sources/OpenIslandApp/Views/ThemeEditorSheet.swift`, `Sources/OpenIslandApp/Views/ColorRoleRow.swift`. **(modified):** `ThemeManager.swift` (preview), `AppearanceSettingsPane.swift`, localized strings.

**Swarm:** `apple-dev:apple-ui-designer` (HIG sheet layout) ↔ `apple-dev:swift-developer` (impl + preview wiring) → `tester` (preview + hex validation) → `reviewer` (Settings UX). Mesh, 4 agents — designer + developer iterate together.

**Gate:** preview tests green; manual: drag picker → island retints live; Cancel reverts; Save persists.

## Stop conditions

We can ship after any phase. If after Phase 1 the visual impact already feels right and Phase 2 isn't priority, this design stands and 2/3 become future work.

## Open questions

None at design-approval time. Implementation plan (next, via `writing-plans`) will resolve any further detail before the swarm starts on Phase 1.
