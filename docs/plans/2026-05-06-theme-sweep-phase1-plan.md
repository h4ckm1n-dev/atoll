# Theme Sweep — Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
>
> **Execution mode (per user directive):** swarm. The plan is structured so the dispatcher spawns four named agents in one message (`architect` → `coder` → `tester` → `reviewer`), each `run_in_background: true`, coordinated via `SendMessage`. See "Swarm dispatch" below.

**Goal:** Replace 39 hardcoded color sites across the app with semantic palette mappings so picking any Catppuccin theme (including Latte) visibly retints the whole panel — completion banners, attention indicators, capsule fills, agent activity dots, plan checklists, recessed panes — not just the buttons we've already wired.

**Architecture:** Three-layer change. (1) `ThemePalette` gains a `role(_:)` API exposing semantic accents (`.warning`, `.danger`, `.success`, `.working`, `.attention`, `.question`, `.completion`) — pure mapping over existing fields, no new colors. (2) `OpenIslandApp` injects the active palette into the SwiftUI Environment so leaf views can read `@Environment(\.themePalette)` instead of threading `palette:` parameters. (3) View files do a mechanical sweep replacing `Color(red:..)` literals and `.white/.black.opacity(...)` chrome overlays with palette references per the table in the design doc.

**Tech Stack:** Swift 6.2, SwiftUI, macOS 14+, Swift Testing (`Testing` framework — already used by `ThemeTests.swift`).

**Authoritative reference:** `docs/plans/2026-05-06-theme-personalization-design.md` — section "Color mapping (Phase 1 sweep)" has the full table; section "Latte (light theme) support" has the chrome-overlay rule. **The plan does not duplicate that table; agents read it directly.**

---

## Preconditions

1. The design doc (`docs/plans/2026-05-06-theme-personalization-design.md`, commit `ef026e9`) must exist on the branch you start from. It currently lives on `feat/inline-diff-and-plan-mode`, **not** yet on `main`. Choose one:
   - **Option A (preferred):** wait for `feat/inline-diff-and-plan-mode` to merge to `main`, then branch `feat/theme-sweep` off the new `main`.
   - **Option B (if blocked):** branch `feat/theme-sweep` off `feat/inline-diff-and-plan-mode` directly. The phase 1 PR will then chain — accept this only if the inline-diff branch is days from merging. CLAUDE.md prohibits chained PRs in steady state, so prefer A.
2. Worktree workflow per `CLAUDE.md`: do all editing inside an isolated worktree, not the main checkout. Use `EnterWorktree` (or `git worktree add ../theme-sweep feat/theme-sweep`).
3. Dev environment can run `swift build`, `swift test`, and the dev app. Verify with `swift --version` (expect ≥ 6.2) and `xcode-select -p`.
4. The dev app launch script `scripts/launch-dev-app.sh` exists and works (it does — used in earlier theme commits).

---

## Swarm dispatch

The dispatcher (the calling session) spawns all four agents in **one** message:

```javascript
Agent({
  subagent_type: "architect",
  name: "architect",
  run_in_background: true,
  prompt: "Open the theme-sweep worktree. Read docs/plans/2026-05-06-theme-sweep-phase1-plan.md sections 'Phase A — architect' and 'Authoritative reference'. Execute Phase A end-to-end. When build + tests are green, SendMessage to 'coder' with: a one-paragraph summary of what landed, the names of the new types/keys you exposed, and any deviations from the plan. Then exit."
})
Agent({
  subagent_type: "coder",
  name: "coder",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'architect'. Read docs/plans/2026-05-06-theme-sweep-phase1-plan.md section 'Phase B — coder' and the design doc's 'Color mapping' table. Execute Phase B end-to-end (sweep 8 files). When build + tests are green, SendMessage to 'tester' with: per-file change count and any sites you preserved as exceptions (1px strokes etc.). Then exit."
})
Agent({
  subagent_type: "tester",
  name: "tester",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'coder'. Read docs/plans/2026-05-06-theme-sweep-phase1-plan.md section 'Phase C — tester'. Execute Phase C end-to-end. When all 357+ tests pass, SendMessage to 'reviewer' with: the full test output tail, and confirmation the new PaletteRoleMappingTests and LatteContrastTests are present. Then exit."
})
Agent({
  subagent_type: "reviewer",
  name: "reviewer",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'tester'. Read docs/plans/2026-05-06-theme-sweep-phase1-plan.md section 'Phase D — reviewer'. Execute Phase D end-to-end (CPU regression + visual smoke + PR creation). Report final status to the user with PR URL or merge instructions."
})

SendMessage({ to: "architect", summary: "Start", message: "Phase 1 of theme sweep. Plan at docs/plans/2026-05-06-theme-sweep-phase1-plan.md. Preconditions are satisfied (worktree exists, branch checked out off main, design doc present). Begin Phase A." })
```

**Coordination rules:**
- Each agent works in the SAME worktree (sequential pipeline, not parallel writes).
- Each agent commits its own atomic commit at end of phase (`feat:`, `test:`, `chore:` per content).
- An agent that hits a blocker `SendMessage`s back to the dispatcher (parent session) with the failure detail and exits — does NOT loop or retry.
- The dispatcher (you, the parent) checks in only when an agent reports back. No polling.

---

## Phase A — architect

**Owner:** `architect` agent.
**Goal:** Land the role API and the Environment key. After this phase the codebase has the new infrastructure in place but no view file has been swept yet — everything still compiles and all 355 existing tests pass.

### Task A.1: Branch + worktree setup

**Step A.1.1: Verify you are in the theme-sweep worktree**

```bash
git rev-parse --abbrev-ref HEAD
# Expected: feat/theme-sweep
git status -sb
# Expected: clean tree
```

If not on `feat/theme-sweep`, abort and `SendMessage` to dispatcher.

**Step A.1.2: Verify the design doc exists**

```bash
test -f docs/plans/2026-05-06-theme-personalization-design.md && echo OK
# Expected: OK
```

If missing, abort and `SendMessage` to dispatcher.

### Task A.2: Add the semantic role API

**Files:**
- Modify: `Sources/OpenIslandCore/Theme.swift`

**Step A.2.1: Read the current Theme.swift to confirm structure**

```bash
wc -l Sources/OpenIslandCore/Theme.swift
# Expected: ~162 lines
```

**Step A.2.2: Append a `PaletteRole` enum + `role(_:)` method**

After the existing `ThemePalette` struct definition (just before the `extension AppTheme` block), add:

```swift
/// Semantic accent roles. Views should prefer `palette.role(.warning)`
/// over `palette.peach` when the call site is naming an *intent*
/// (warning, danger, success) rather than a *color*. The mapping is
/// the same across every flavor — only the underlying hex changes.
public enum PaletteRole: Sendable, Hashable, CaseIterable {
    case warning      // amber / caution — non-destructive nudge
    case danger       // destructive / always-allow
    case success      // task completed, idle-but-ok
    case working      // active / in-progress
    case attention    // demands the user's eyes (permission, mute)
    case question     // structured-question prompt, plan-mode card
    case completion   // celebratory completion banner
}

extension ThemePalette {
    /// Resolves a semantic accent role to the matching palette field.
    /// Used by views that want to express intent rather than color.
    /// See `docs/plans/2026-05-06-theme-personalization-design.md`
    /// section "Color mapping (Phase 1 sweep)" for the rationale.
    public func role(_ role: PaletteRole) -> ProjectColor {
        switch role {
        case .warning, .attention: return peach
        case .danger:              return red
        case .success, .completion: return green
        case .working:             return blue
        case .question:            return yellow
        }
    }
}
```

**Step A.2.3: Verify the file compiles in isolation**

```bash
swift build --target OpenIslandCore 2>&1 | tail -3
# Expected: "Build complete!"
```

### Task A.3: Add the SwiftUI Environment key

**Files:**
- Modify: `Sources/OpenIslandApp/ThemeManager.swift`

**Step A.3.1: Append the Environment key**

After the existing `extension ProjectColor` block, add:

```swift
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
```

### Task A.4: Inject the palette at the App root

**Files:**
- Modify: `Sources/OpenIslandApp/OpenIslandApp.swift`

**Step A.4.1: Find the existing scene definitions**

```bash
grep -n "var body: some Scene\|Window\|MenuBarExtra" Sources/OpenIslandApp/OpenIslandApp.swift
```

**Step A.4.2: Apply `.environment(\.themePalette, ...)` to each top-level scene's content**

For each `Window { ... }` and `MenuBarExtra { ... } label: { ... }` in `OpenIslandApp.body`, wrap the content view with:

```swift
.environment(\.themePalette, appDelegate.model.themeManager.palette)
```

Example transformation — `Window("Open Island Settings", id: "settings")`:

```swift
// Before
Window("Open Island Settings", id: "settings") {
    SettingsWindowContent(model: appDelegate.model)
}

// After
Window("Open Island Settings", id: "settings") {
    SettingsWindowContent(model: appDelegate.model)
        .environment(\.themePalette, appDelegate.model.themeManager.palette)
}
```

Same pattern for the debug `WindowGroup` and the `MenuBarExtra` content. **Do not** wrap the `MenuBarExtra` *label* — the label is a tiny static glyph that doesn't need the env value, and wrapping it forces extra view-tree traffic in the menu bar render path (the place where we already had a CPU regression — `b80e6e0`).

The overlay panel is created via AppKit (`OverlayPanelController`), not in `body`. Its SwiftUI hosting view will pick up the env value via the existing `.environment` modifier OR an additional explicit injection there. Search for the hosting view:

```bash
grep -rn "NSHostingView\|NSHostingController" Sources/OpenIslandApp/ | head -5
```

If the hosting view doesn't already inject env values, add `.environment(\.themePalette, model.themeManager.palette)` to the hosted SwiftUI view at construction.

**Step A.4.3: Build the whole package**

```bash
swift build 2>&1 | tail -5
# Expected: "Build complete!"
```

If build fails, fix and re-run before proceeding.

### Task A.5: Verify all existing tests still pass

**Step A.5.1: Run the full test suite**

```bash
swift test 2>&1 | tail -3
# Expected: "Test run with 355 tests in 41 suites passed"
```

If any existing test fails, fix before commit. The most likely failure is `mochaPaletteMatchesPublishedHexValues` — but that test was already updated in `b80e6e0`, so it should pass.

### Task A.6: Commit Phase A

**Step A.6.1: Stage and commit**

```bash
git add Sources/OpenIslandCore/Theme.swift \
        Sources/OpenIslandApp/ThemeManager.swift \
        Sources/OpenIslandApp/OpenIslandApp.swift

git commit -m "$(cat <<'EOF'
feat(theme): add PaletteRole semantic accents + ThemePalette Environment key

Phase 1 of the theme-personalization sweep (design doc:
docs/plans/2026-05-06-theme-personalization-design.md). This commit
lays the groundwork — no view file is swept yet.

- PaletteRole enum (.warning / .danger / .success / .working /
  .attention / .question / .completion) with palette.role(_:)
  resolving to the existing accent fields. Views that name intent
  rather than color use this; views naming a literal color
  (palette.peach for an actual peach badge) keep direct field access.
- @Environment(\.themePalette) keyed by ThemePaletteEnvironmentKey
  with .mocha as default. Injected at every top-level Scene's content
  view in OpenIslandApp.body. The MenuBarExtra label is intentionally
  NOT wrapped — earlier theme work showed extra env traffic in the
  menu bar render path triggers SwiftUI invalidation churn.

All 355 existing tests still green.
EOF
)"
```

**Step A.6.2: Sanity check the commit**

```bash
git show --stat HEAD
# Expected: 3 files changed, ~30 insertions
```

### Task A.7: Hand off to coder

**Step A.7.1: SendMessage to 'coder'**

Body of the message must include:
- "Phase A complete at commit `<sha>`"
- "Exposed: `PaletteRole` enum, `palette.role(_:)`, `\.themePalette` environment key"
- "All 355 tests green; build clean"
- "Begin Phase B — sweep the 8 view files per design table"

Then exit. Do not start Phase B yourself.

---

## Phase B — coder

**Owner:** `coder` agent.
**Goal:** Mechanical sweep of 39 hardcoded color sites across 8 files, plus chrome-overlay refactor. After this phase, picking any of the 5 themes in Settings → Appearance visibly retints the whole panel.

### Task B.1: Read the authoritative mapping table

**Step B.1.1: Open the design doc to the mapping table**

The table lives at `docs/plans/2026-05-06-theme-personalization-design.md` section "Color mapping (Phase 1 sweep)". Before editing any view file, **read the table top-to-bottom**. Every transformation in this phase must match a row.

**Step B.1.2: Read the chrome-overlay rule**

Section "Latte (light theme) support" lays out:
- `.white.opacity(x)` → `palette.text.opacity(x)`
- `.black.opacity(x)` → `palette.crust.opacity(x)`
- Ultra-subtle 1px strokes (`.white.opacity(0.04)` and below) — keep as-is with an inline comment.

### Task B.2: Sweep `BadgeColors.swift` (1 site — smallest, do first)

**Files:**
- Modify: `Sources/OpenIslandApp/Views/BadgeColors.swift`

**Step B.2.1: Find the hardcoded color**

```bash
grep -n "Color(red:\|Color\.\(orange\|red\|yellow\|green\|blue\|mint\|cyan\|purple\|pink\)" Sources/OpenIslandApp/Views/BadgeColors.swift
```

**Step B.2.2: Replace per the table**

The single site is the unknown-agent fallback. Map to `palette.lavender` (neutral accent that reads "tagged but unspecified" in any flavor). Wire palette through if the function doesn't already accept it (it does — `BadgeColors.agent(_:palette:)` is already palette-aware; you're just changing the fallback branch).

**Step B.2.3: Verify build**

```bash
swift build 2>&1 | tail -3
```

### Task B.3: Sweep `AmbientThemeOverlay.swift` (1 site)

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AmbientThemeOverlay.swift`

The single site is per-project tint. **Per design, this stays as-is** (project tint, not theme tint). Add an inline comment at the call site explaining the exception, then move on. Do not change the color.

```swift
// Project-tint, intentionally not theme-driven —
// the spotlight color is per-project (set in AppearanceSettingsPane
// via ProjectColorRegistry), independent of the active ThemePalette.
```

### Task B.4: Sweep `CelebrationParticles.swift` (2 sites)

**Files:**
- Modify: `Sources/OpenIslandApp/Views/CelebrationParticles.swift`

**Step B.4.1: Find the hardcoded RGBs**

```bash
grep -n "Color(red:" Sources/OpenIslandApp/Views/CelebrationParticles.swift
```

**Step B.4.2: Read the surrounding code to find a palette source**

This view is invoked from a parent that already has the model. Either:
(a) read `@Environment(\.themePalette)` (preferred — added in Phase A), or
(b) accept `palette: ThemePalette` as a stored property and pass from the call site.

Use (a) — it's why Phase A added the Env key.

**Step B.4.3: Map the triad**

Per design: festive triad → `palette.green` / `palette.peach` / `palette.lavender`. Replace the three hardcoded RGBs with these.

**Step B.4.4: Verify build**

```bash
swift build 2>&1 | tail -3
```

### Task B.5: Sweep `PlanChecklistView.swift` (2 sites)

**Files:**
- Modify: `Sources/OpenIslandApp/Views/PlanChecklistView.swift`

**Step B.5.1: List the sites**

```bash
grep -nE "Color\(red:|Color\.(orange|red|yellow|green|blue|mint|cyan|purple|pink)\b|\.(white|black)\.opacity" Sources/OpenIslandApp/Views/PlanChecklistView.swift
```

**Step B.5.2: Apply the mapping**

Use `@Environment(\.themePalette) private var palette` at the top of the view. Replace each site per the design table. Chrome `.white.opacity(x)` → `palette.text.opacity(x)`; `.black.opacity(x)` → `palette.crust.opacity(x)`.

### Task B.6: Sweep `AppearanceSettingsPane.swift` (1 site)

**Files:**
- Modify: `Sources/OpenIslandApp/Views/AppearanceSettingsPane.swift`

The single site is in a swatch helper. Apply the design table mapping. If it's a project-color preset list (`projectColorPresets`), **leave it as-is** — those are explicit hex values used as picker presets, not theme-driven.

### Task B.7: Sweep `ControlCenterView.swift` (3 sites)

**Files:**
- Modify: `Sources/OpenIslandApp/Views/ControlCenterView.swift`

**Step B.7.1: List the sites**

```bash
grep -nE "Color\(red:|\.(orange|red|yellow|green|blue|mint|cyan|purple|pink)\b\.opacity|Color\.(orange|red|yellow|green|blue)\b" Sources/OpenIslandApp/Views/ControlCenterView.swift
```

**Step B.7.2: Add `@Environment(\.themePalette)` at the top of the view**

**Step B.7.3: Apply mappings per design table**

### Task B.8: Sweep `SettingsView.swift` (5 sites)

**Files:**
- Modify: `Sources/OpenIslandApp/Views/SettingsView.swift`

Same pattern as B.7 — add Environment, apply mappings.

### Task B.9: Sweep `IslandPanelView.swift` (29 sites — the bulk)

**Files:**
- Modify: `Sources/OpenIslandApp/Views/IslandPanelView.swift`

This is the largest sweep. Be deliberate.

**Step B.9.1: Inventory all sites**

```bash
grep -nE "Color\(red:|Color\.(orange|red|yellow|green|blue|mint|cyan|purple|pink)\b|\.(orange|red|yellow|green|blue|mint|cyan|purple|pink|white|black)\.opacity" Sources/OpenIslandApp/Views/IslandPanelView.swift > /tmp/island-color-sites.txt
wc -l /tmp/island-color-sites.txt
```

**Step B.9.2: Verify the existing palette plumbing**

`IslandSessionRow` already takes `themePalette: ThemePalette = .mocha` (line ~1215) and several call sites pass `model.themeManager.palette`. Keep those parameters. New sites in views that don't already have a palette param read `@Environment(\.themePalette)`.

**Step B.9.3: Apply transformations in order**

Walk `/tmp/island-color-sites.txt` top-to-bottom and transform each line per the design mapping table. After each ~5 sites, run `swift build` to keep the failure surface small. Common patterns:

```swift
// Working agent indicator
Color(red: 0.43, green: 0.62, blue: 1.0)
// → palette.role(.working).swiftUIColor   (or palette.blue.swiftUIColor — equivalent;
//   prefer .role(.working) when the call site reads "this is the working state")

// Idle/success indicator
Color(red: 0.26, green: 0.91, blue: 0.42)
// → palette.role(.success).swiftUIColor

// Warning/attention
.orange.opacity(0.18)
// → palette.role(.attention).swiftUIColor.opacity(0.18)

// Question/plan-mode prompt
.yellow.opacity(0.96)
// → palette.role(.question).swiftUIColor.opacity(0.96)

// Chrome overlay (subtle foreground)
.white.opacity(0.06)
// → palette.text.swiftUIColor.opacity(0.06)

// Recessed pane
Color.black.opacity(0.32)
// → palette.crust.swiftUIColor.opacity(0.45)   // bumped per design

// 1px stroke EXCEPTION (keep as-is)
.white.opacity(0.04)
// inline comment: "kept as Color.white — palette.text would vanish at 0.04 against base"

// Capsule chrome bg
Color(red: 0.14, green: 0.14, blue: 0.15)
// → palette.surface0.swiftUIColor

// Warning card warm-dark surface
Color(red: 0.11, green: 0.08, blue: 0.03)
// → palette.surface0.swiftUIColor    (border already .orange.opacity(0.18) → palette.role(.attention)…)
```

**Step B.9.4: Special case — the button-style fallbacks at lines 2319–2325**

`IslandWideButtonStyle` already has the palette-aware path (added in `b80e6e0`). The hardcoded fallback values at the bottom of `backgroundColor(_:)` are reached only when `palette: nil` is passed. **Leave them** — they're a documented fallback. The design's "39 sites" count includes them; we still consider the sweep complete with the fallback intact, because every actual call site now passes a palette.

### Task B.10: Final build + tests

**Step B.10.1: Full build**

```bash
swift build 2>&1 | tail -5
# Expected: "Build complete!"
```

**Step B.10.2: Full test suite**

```bash
swift test 2>&1 | tail -3
# Expected: "Test run with 355 tests in 41 suites passed"
```

If any test fails — likely `mochaPaletteMatchesPublishedHexValues` if you accidentally changed Theme.swift — revert and re-check.

### Task B.11: Commit Phase B

**Step B.11.1: Stage and commit**

```bash
git add Sources/OpenIslandApp/Views/

git commit -m "$(cat <<'EOF'
refactor(theme): sweep hardcoded colors → palette mappings across 8 views

Phase 1 sweep per docs/plans/2026-05-06-theme-personalization-design.md
section "Color mapping (Phase 1 sweep)". 39 hardcoded color sites
across 8 view files now read from the active ThemePalette so picking
any preset (Latte / Frappé / Macchiato / Mocha / System) visibly
retints the whole panel — agent activity dots, attention indicators,
completion banners, capsule fills, plan checklist, prompt cards.

Files touched:
- Views/IslandPanelView.swift           (29 sites — bulk of the change)
- Views/SettingsView.swift              (5)
- Views/ControlCenterView.swift         (3)
- Views/PlanChecklistView.swift         (2)
- Views/CelebrationParticles.swift      (2)
- Views/BadgeColors.swift               (1, fallback)
- Views/AppearanceSettingsPane.swift    (1)
- Views/AmbientThemeOverlay.swift       (preserved — per-project tint)

Chrome overlays:
- .white.opacity(x) → palette.text.swiftUIColor.opacity(x)
- .black.opacity(x) → palette.crust.swiftUIColor.opacity(x)
- 1px-stroke .white.opacity(0.04) preserved with inline rationale —
  palette.text would vanish at that opacity on dark themes.

IslandWideButtonStyle hardcoded fallbacks kept as-is — only reached
when palette: nil is passed, every actual call site now passes a
palette.

All 355 existing tests green. Visual smoke deferred to Phase D.
EOF
)"
```

**Step B.11.2: Sanity check**

```bash
git show --stat HEAD
# Expected: 7-8 files, ~80–120 insertions, ~80–120 deletions
```

### Task B.12: Hand off to tester

**Step B.12.1: SendMessage to 'tester'**

Body must include:
- "Phase B complete at commit `<sha>`"
- "Files swept: 8. Sites changed: <count>. Sites preserved as exceptions: <count> (list them)"
- "Build clean, all 355 tests still green"
- "Begin Phase C — add PaletteRoleMappingTests + LatteContrastTests"

Then exit.

---

## Phase C — tester

**Owner:** `tester` agent.
**Goal:** Add the two new test suites the design specifies for Phase 1, lock the role mapping, lock the Latte contrast contract.

### Task C.1: Add `PaletteRoleMappingTests`

**Files:**
- Modify: `Tests/OpenIslandCoreTests/ThemeTests.swift`

**Step C.1.1: Read the current test file structure**

```bash
grep -n "@Test\|struct " Tests/OpenIslandCoreTests/ThemeTests.swift
```

Locate where to append the new test methods (inside the existing `struct ThemeTests`, after the `appThemeRoundtripsThroughCodable` test).

**Step C.1.2: Append the role mapping suite**

```swift
@Test
func paletteRoleMapsToExpectedAccentForEveryFlavor() {
    for theme in AppTheme.allCases {
        let p = theme.palette
        // Each role must resolve to a specific palette field. The
        // mapping is locked — adding a role or moving a role must
        // require updating this test, which is a feature not a bug.
        #expect(p.role(.warning)    == p.peach)
        #expect(p.role(.attention)  == p.peach)
        #expect(p.role(.danger)     == p.red)
        #expect(p.role(.success)    == p.green)
        #expect(p.role(.completion) == p.green)
        #expect(p.role(.working)    == p.blue)
        #expect(p.role(.question)   == p.yellow)
    }
}

@Test
func paletteRoleEnumIsExhaustive() {
    // PaletteRole.allCases must stay in sync with the role(_:) switch.
    // If a new role is added without a switch case, this fails on the
    // first call (the switch becomes non-exhaustive at compile time).
    let p = ThemePalette.mocha
    for role in PaletteRole.allCases {
        let resolved = p.role(role)
        // Every role must map to one of the 14 accents.
        let accents: [ProjectColor] = [
            p.rosewater, p.flamingo, p.pink, p.mauve, p.red, p.maroon,
            p.peach, p.yellow, p.green, p.teal, p.sky, p.sapphire,
            p.blue, p.lavender,
        ]
        #expect(accents.contains(resolved))
    }
}
```

**Step C.1.3: Run just this test method**

```bash
swift test --filter "ThemeTests/paletteRoleMapsToExpectedAccentForEveryFlavor" 2>&1 | tail -3
# Expected: PASSED
```

```bash
swift test --filter "ThemeTests/paletteRoleEnumIsExhaustive" 2>&1 | tail -3
# Expected: PASSED
```

### Task C.2: Add `LatteContrastTests`

**Files:**
- Modify: `Tests/OpenIslandCoreTests/ThemeTests.swift`

**Step C.2.1: Append the Latte contrast suite**

After the role tests, add:

```swift
@Test
func lattePaletteHasReadableContrast() {
    let p = ThemePalette.latte
    // Latte must be a real light theme — dark text on light base.
    // Catches regressions where someone shifts Latte numbers without
    // realizing they broke the readability contract.
    let textLuma = relativeLuminance(p.text)
    let baseLuma = relativeLuminance(p.base)
    #expect(textLuma < 0.5,
            "Latte.text luma (\(textLuma)) must be < 0.5 — dark text on light base")
    #expect(baseLuma > 0.85,
            "Latte.base luma (\(baseLuma)) must be > 0.85 — near-white base")

    // Crust on Latte should be slightly darker than base (depth).
    let crustLuma = relativeLuminance(p.crust)
    #expect(crustLuma < baseLuma,
            "Latte.crust must be darker than base for layered depth")
}

@Test
func darkFlavorsHaveDarkBase() {
    // Inverse contract for the dark flavors — base must be dark.
    for theme in [AppTheme.catppuccinFrappe,
                  .catppuccinMacchiato,
                  .catppuccinMocha] {
        let p = theme.palette
        let baseLuma = relativeLuminance(p.base)
        #expect(baseLuma < 0.20,
                "\(theme).base luma (\(baseLuma)) must be < 0.20 — dark base")
    }
}

/// Rec. 709 relative luminance (test-helper, not part of the public API).
/// Good enough for contract-locking; we don't ship a contrast checker.
private func relativeLuminance(_ c: ProjectColor) -> Double {
    func channel(_ v: Double) -> Double {
        v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
}
```

**Step C.2.2: Run just these tests**

```bash
swift test --filter "ThemeTests/lattePaletteHasReadableContrast" 2>&1 | tail -3
swift test --filter "ThemeTests/darkFlavorsHaveDarkBase" 2>&1 | tail -3
# Expected: both PASSED
```

If either fails, the palette numbers in `Theme.swift` were edited beyond what we expected. Surface the failure to the dispatcher — do NOT mutate Theme.swift to make tests pass.

### Task C.3: Run the full test suite

**Step C.3.1: Full run**

```bash
swift test 2>&1 | tail -5
# Expected: "Test run with 359 tests in 41 suites passed" (4 new tests)
```

If existing tests broke, surface them — fixing them is out of scope for the tester role.

### Task C.4: Commit Phase C

**Step C.4.1: Stage and commit**

```bash
git add Tests/OpenIslandCoreTests/ThemeTests.swift

git commit -m "$(cat <<'EOF'
test(theme): lock role mapping + Latte contrast contract

Adds 4 tests to the ThemeTests suite per the Phase 1 plan:

- paletteRoleMapsToExpectedAccentForEveryFlavor — locks the
  PaletteRole → palette field mapping across all 5 flavors. Future
  role additions or remappings must update this test deliberately.
- paletteRoleEnumIsExhaustive — guards against drift between
  PaletteRole.allCases and the role(_:) switch.
- lattePaletteHasReadableContrast — Latte.text luma < 0.5 and
  Latte.base luma > 0.85, plus crust darker than base. Catches
  regressions where Latte numbers shift past the readability cliff.
- darkFlavorsHaveDarkBase — Frappé/Macchiato/Mocha base luma < 0.20.

Test helper: Rec. 709 relativeLuminance() — file-private, not part
of public API. Good enough to lock the contract; not a contrast
checker.

359 tests in 41 suites green.
EOF
)"
```

**Step C.4.2: Sanity check**

```bash
git show --stat HEAD
# Expected: 1 file, ~70 insertions
```

### Task C.5: Hand off to reviewer

**Step C.5.1: SendMessage to 'reviewer'**

Body must include:
- "Phase C complete at commit `<sha>`"
- "Test count: 359 (4 new — list them)"
- "Full test output tail attached"
- "Begin Phase D — CPU smoke + visual verification + PR"

Then exit.

---

## Phase D — reviewer

**Owner:** `reviewer` agent.
**Goal:** Confirm the sweep didn't introduce a CPU regression, visually verify the 5 themes look right in the running app, and open the PR.

### Task D.1: Build dev app

**Step D.1.1: Build**

```bash
swift build 2>&1 | tail -3
# Expected: "Build complete!"
```

**Step D.1.2: Refresh + launch the dev bundle**

```bash
zsh scripts/launch-dev-app.sh --skip-setup 2>&1 | tail -3
# Expected: "Build of product 'OpenIslandSetup' complete!"
```

```bash
sleep 4 && pgrep -fl "Open Island Dev/Contents/MacOS"
# Expected: a single PID line
```

Capture the PID for the next steps.

### Task D.2: CPU regression gate

**Step D.2.1: Wait for session-discovery settle**

The app does heavy work for ~90–120s on launch (transcript scan, terminal reconciliation). Use `Monitor`-style polling — DO NOT `sleep 120` in one shot.

```bash
PID=<captured PID>
until [ "$(ps -p $PID -o %cpu= 2>/dev/null | tr -d ' ' | cut -d, -f1)" -lt 5 ] 2>/dev/null; do
  sleep 5
  ps -p $PID -o %cpu,etime 2>/dev/null | tail -1
done
echo "settled"
```

Acceptable: CPU drops below 5% within ~150 seconds. **Hard gate: < 1% sustained.** If CPU stays above 5% for more than 180s the sweep introduced a SwiftUI invalidation loop (we hit this in `b80e6e0`'s first attempt). Surface to dispatcher with the stuck CPU number.

**Step D.2.2: Confirm idle baseline**

```bash
ps -p $PID -o %cpu,rss,etime,command 2>/dev/null | head -2
# Expected: %CPU ≤ 1, RSS reasonable (< 300MB)
```

### Task D.3: Visual smoke check (manual — reviewer prompts the user)

The reviewer can't drive Settings → Appearance from the shell. Instead, prepare a checklist and ask the user to walk through it:

**Step D.3.1: Tell the user what to do**

`SendMessage` to dispatcher:

> Visual smoke check needed. Please:
> 1. Click the menu bar coconut → "Settings…" (Cmd+,).
> 2. Open Settings → Appearance.
> 3. Switch through Latte / Frappé / Macchiato / Mocha — each should visibly recolor the panel chrome, agent dots, attention badges, prompt cards.
> 4. Trigger an attention state if available (any waiting permission session) — confirm the Yes/No/Always Allow row retints.
> 5. Confirm Latte is readable (dark text on light base) — not white-text-on-white.
> 6. Reply "ok" if all five themes look right, or paste a screenshot/description of what's wrong.

Then wait for the user's reply before proceeding.

### Task D.4: Open the PR

**Step D.4.1: Push branch**

```bash
git push -u origin feat/theme-sweep
```

**Step D.4.2: Create PR**

```bash
gh pr create --base main --title "feat(theme): Phase 1 — palette sweep across 8 views" --body "$(cat <<'EOF'
## Summary

Phase 1 of the 3-phase theme-personalization rollout (design:
`docs/plans/2026-05-06-theme-personalization-design.md`).

- 39 hardcoded colors across 8 view files now read the active
  `ThemePalette` — picking Latte / Frappé / Macchiato / Mocha visibly
  retints the whole panel.
- New `PaletteRole` semantic API (`palette.role(.warning)` etc.) for
  views naming intent rather than color.
- New `\.themePalette` SwiftUI Environment key injected at the App
  root — leaf views read via `@Environment(\.themePalette)`.
- 4 new tests lock the role mapping and Latte contrast contract.

This phase ships **no new UI**. Custom theme creation lands in Phase
2 (`feat/theme-custom-registry`) and Phase 3 (`feat/theme-editor`).

## Test plan

- [x] `swift build` clean
- [x] `swift test` — 359/359 green
- [x] CPU settles ≤ 1% post launch (no SwiftUI invalidation loop)
- [x] Manual: switched through all 5 themes — visible retint each step
- [x] Manual: Latte readable (dark text on light base)
- [ ] Reviewer visual sign-off

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step D.4.3: Capture PR URL**

```bash
gh pr view --json url -q .url
```

### Task D.5: Final report to user

`SendMessage` to dispatcher (parent session):

> Phase 1 complete. PR: <url>
>
> Commits on `feat/theme-sweep`:
> - `<sha>` feat(theme): add PaletteRole + Environment key
> - `<sha>` refactor(theme): sweep hardcoded colors across 8 views
> - `<sha>` test(theme): lock role mapping + Latte contrast
>
> Tests: 359/359 green. CPU idle: <%>. Visual smoke: passed (per user).
>
> Ready for merge to main. Phase 2 starts on `feat/theme-custom-registry` after merge.

Then exit.

---

## Verification gates summary

| Gate    | Owner       | Pass condition                                                          |
| ------- | ----------- | ----------------------------------------------------------------------- |
| **A→B** | architect   | Build clean. 355 tests green. Phase A commit on branch.                 |
| **B→C** | coder       | Build clean. 355 tests green. ≥ 35 sites swept (allow 1–2 preserves).   |
| **C→D** | tester      | Build clean. 359 tests green (4 new). Phase C commit on branch.         |
| **D→**  | reviewer    | CPU ≤ 1% post-settle. User visual sign-off. PR open.                    |

If any gate fails, the owning agent `SendMessage`s the dispatcher (parent session) with the specific failure, then exits. The dispatcher decides: re-prompt the same agent, change scope, or escalate to user.

---

## Out of scope (Phase 2/3 territory — do NOT do here)

- `CustomTheme`, `CustomThemeRegistry`, JSON import/export.
- `AppTheme` enum-with-associated-value migration.
- 26-picker editor sheet.
- `themeManager.previewPalette` live-preview machinery.
- New "Themes" section in Settings → Appearance.
- Removing the `IslandWideButtonStyle` hardcoded fallbacks (kept by design).
- Any change to `AmbientThemeOverlay` per-project tint (intentionally not theme-driven).
- Tweaking palette hex values (the design docked Mocha base/crust/surface; further tweaks are a separate decision).
