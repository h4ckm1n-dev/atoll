# Phase 4 — Frosted Panel Material Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
>
> **Execution mode:** swarm. Spawn `coder → tester → reviewer` in one Agent message — small enough to skip the architect step. All `run_in_background: true`.

**Goal:** Add a three-way "Panel material" picker (Solid / Frosted thin / Frosted ultra-thin) to Settings → Appearance. Solid keeps the v1.0 ocean-night look (`palette.mantle`); frosted variants swap the opened-panel surface to `.thinMaterial` / `.ultraThinMaterial` with a `palette.crust.opacity(0.55)` overlay so the theme tint still tints the frosted glass.

**Architecture:** New `AppPanelMaterial` enum in `AtollCore`. Persisted via `@AppStorage("appearance.panelMaterial")` as raw String. The render site is a single `@ViewBuilder` in `IslandPanelView` that returns either a solid `Rectangle` or a stacked `Material + tint` pair. Collapsed/idle path stays pure black to preserve the physical-notch blend on notched MacBooks.

**Tech Stack:** Swift 6.2, SwiftUI `Material` + `@AppStorage`, Swift Testing.

**Authoritative reference:** `docs/plans/2026-05-06-theme-personalization-design.md` — section "Phase 4 — Frosted panel option".

---

## Preconditions

1. **Independent of Phases 2/3.** Branch off latest `main` whether Phase 2/3 have shipped or not. Phase 4 only touches the panel surface render and Settings → Appearance.
2. Worktree: `git worktree add ../panel-material -b feat/panel-material main`.
3. Dev environment OK (`swift --version` ≥ 6.2).
4. `swift build && swift test` from `main` passes.

---

## Swarm dispatch

```javascript
Agent({
  subagent_type: "apple-dev:swift-developer",
  name: "p4-coder",
  run_in_background: true,
  prompt: "Open the panel-material worktree. Read docs/plans/2026-05-07-phase-4-frosted-panel-plan.md section 'Phase A — coder' (this plan skips a separate architect agent — it's small enough to spec inline). Execute Phase A end-to-end. SendMessage to 'p4-tester' with commit SHA + per-file change summary. Then exit."
})
Agent({
  subagent_type: "apple-dev:swift-developer",
  name: "p4-tester",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'p4-coder'. Read plan section 'Phase B — tester'. Execute Phase B. SendMessage to 'p4-reviewer' with full test output. Then exit."
})
Agent({
  subagent_type: "pr-review-toolkit:code-reviewer",
  name: "p4-reviewer",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'p4-tester'. Read plan section 'Phase C — reviewer'. Execute Phase C (CPU smoke + manual three-way switch + PR). Report final status with PR URL."
})

SendMessage({ to: "p4-coder", summary: "Start", message: "Phase 4 of theme personalization. Plan at docs/plans/2026-05-07-phase-4-frosted-panel-plan.md. Worktree feat/panel-material off main. Begin Phase A." })
```

---

## Phase A — coder

**Owner:** `p4-coder`.
**Goal:** Land the enum, the render-site change, the picker UI, the localized strings. After Phase A the user can toggle materials live.

### Task A.1: Branch + worktree setup

```bash
git rev-parse --abbrev-ref HEAD
# Expected: feat/panel-material
git status -sb
# Expected: clean
```

### Task A.2: Add `AppPanelMaterial` enum

**Files:** Create `Sources/AtollCore/PanelMaterial.swift`.

```swift
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

    /// Localization key suffix used by the picker labels.
    public var localizationKey: String {
        switch self {
        case .solid:             return "settings.panelMaterial.solid"
        case .frostedThin:       return "settings.panelMaterial.frostedThin"
        case .frostedUltraThin:  return "settings.panelMaterial.frostedUltraThin"
        }
    }
}
```

### Task A.3: Update the render site in `IslandPanelView`

**Files:** Modify `Sources/AtollApp/Views/IslandPanelView.swift`.

**Step A.3.1: Find the existing `openedSurfaceFill`**

```bash
grep -nB2 -A8 "openedSurfaceFill" Sources/AtollApp/Views/IslandPanelView.swift
```

The existing code (around line 315) reads:

```swift
let openedSurfaceFill: Color = usesOpenedVisualState
    ? model.themeManager.palette.mantle.swiftUIColor
    : .black
```

…then later:

```swift
surfaceShape
    .fill(openedSurfaceFill.opacity(hidesClosedSurfaceChrome ? 0 : 1))
    .frame(width: surfaceWidth, height: surfaceHeight)
```

**Step A.3.2: Add an `@AppStorage` reader**

At the top of `IslandPanelView` next to other `@State` / `@AppStorage` declarations:

```swift
@AppStorage("appearance.panelMaterial")
private var panelMaterialRaw: String = AppPanelMaterial.solid.rawValue

private var panelMaterial: AppPanelMaterial {
    AppPanelMaterial(rawValue: panelMaterialRaw) ?? .solid
}
```

**Step A.3.3: Replace the surface fill with a `@ViewBuilder`**

Replace the `let openedSurfaceFill: Color = ...` line and the corresponding `.fill(openedSurfaceFill...)` line. The new structure:

```swift
// Build the surface fill based on panel material + collapsed-vs-open state.
// Collapsed (notch-blend) is always pure black regardless of material —
// frosting in idle would break the physical-notch illusion.
@ViewBuilder
private func surfaceFill(palette: ThemePalette) -> some View {
    if hidesClosedSurfaceChrome {
        Color.clear
    } else if !usesOpenedVisualState {
        Color.black
    } else {
        switch panelMaterial {
        case .solid:
            Rectangle()
                .fill(palette.mantle.swiftUIColor)
        case .frostedThin:
            ZStack {
                Rectangle().fill(.thinMaterial)
                Rectangle().fill(palette.crust.swiftUIColor.opacity(0.55))
            }
        case .frostedUltraThin:
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(palette.crust.swiftUIColor.opacity(0.55))
            }
        }
    }
}
```

The original `surfaceShape.fill(openedSurfaceFill.opacity(...))` becomes:

```swift
surfaceShape
    .fill(.clear)              // Shape provides the rounded corners …
    .background(                // …then we fill it with the chosen material.
        surfaceFill(palette: model.themeManager.palette)
            .clipShape(surfaceShape)
    )
    .frame(width: surfaceWidth, height: surfaceHeight)
```

The shape's role splits in two: the visible curved silhouette comes from `surfaceShape`, and the fill — which can now be a SwiftUI Material rather than a Color — is layered behind via `.background(...)` clipped to the same shape. This works because `surfaceShape` is a `Shape` that conforms to `View` when filled; the new structure preserves the rounded-corner clipping while letting Material participate.

If the layered structure causes a visual regression (Material bleeding outside the notch silhouette, etc.), fall back to a `Group { … } .clipShape(surfaceShape)` wrapper around the whole pre-existing `surfaceShape.fill(...)` block, swapping the inner fill for the new builder's output.

### Task A.4: Add the Settings picker

**Files:** Modify `Sources/AtollApp/Views/AppearanceSettingsPane.swift`.

Below the existing theme picker row, add:

```swift
@AppStorage("appearance.panelMaterial")
private var panelMaterialRaw: String = AppPanelMaterial.solid.rawValue

// In the body, just below the theme picker:
Picker(lang.t("settings.panelMaterial.title"), selection: $panelMaterialRaw) {
    ForEach(AppPanelMaterial.allCases, id: \.rawValue) { mat in
        Text(lang.t(mat.localizationKey)).tag(mat.rawValue)
    }
}
.pickerStyle(.segmented)
.help(lang.t("settings.panelMaterial.help"))
```

`.segmented` style works because there are exactly 3 options and the labels are short. If localized labels overflow on Chinese, fall back to `.menu` style.

### Task A.5: Localized strings

Add to all three `Localizable.strings`:

**en:**
```
"settings.panelMaterial.title" = "Panel material";
"settings.panelMaterial.help" = "Frosted lets the wallpaper show through the panel. Solid keeps the deep ocean-night look from v1.0.";
"settings.panelMaterial.solid" = "Solid";
"settings.panelMaterial.frostedThin" = "Frosted (thin)";
"settings.panelMaterial.frostedUltraThin" = "Frosted (ultra-thin)";
```

**zh-Hans:**
```
"settings.panelMaterial.title" = "面板材质";
"settings.panelMaterial.help" = "毛玻璃模式会让壁纸透过面板显示。「实心」保留 v1.0 的深海夜空配色。";
"settings.panelMaterial.solid" = "实心";
"settings.panelMaterial.frostedThin" = "毛玻璃(薄)";
"settings.panelMaterial.frostedUltraThin" = "毛玻璃(超薄)";
```

**zh-Hant:**
```
"settings.panelMaterial.title" = "面板材質";
"settings.panelMaterial.help" = "毛玻璃模式會讓桌布透過面板顯示。「實心」保留 v1.0 的深海夜空配色。";
"settings.panelMaterial.solid" = "實心";
"settings.panelMaterial.frostedThin" = "毛玻璃(薄)";
"settings.panelMaterial.frostedUltraThin" = "毛玻璃(超薄)";
```

### Task A.6: Build + verify existing tests

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -3
# Expected: build clean, all existing tests still passing (count depends on
# whether Phase 2/3 already merged — if not, 359; if so, 379)
```

### Task A.7: Commit Phase A

```bash
git add Sources/AtollCore/PanelMaterial.swift \
        Sources/AtollApp/Views/IslandPanelView.swift \
        Sources/AtollApp/Views/AppearanceSettingsPane.swift \
        Sources/AtollApp/Resources/en.lproj/Localizable.strings \
        Sources/AtollApp/Resources/zh-Hans.lproj/Localizable.strings \
        Sources/AtollApp/Resources/zh-Hant.lproj/Localizable.strings

git commit -m "$(cat <<'EOF'
feat(theme): Phase 4 — frosted panel material option

Three-way picker in Settings → Appearance. Solid (default) keeps the
v1.0 ocean-night look (palette.mantle solid fill). Frosted (thin) =
.thinMaterial + palette.crust.opacity(0.55) overlay. Frosted (ultra-
thin) = .ultraThinMaterial + same overlay. Persisted via
@AppStorage("appearance.panelMaterial").

Collapsed/idle state stays pure black regardless of material —
frosting there would break the physical-notch blend on notched
MacBooks.

The IslandPanelView render site refactors `openedSurfaceFill` from a
single Color into a @ViewBuilder `surfaceFill(palette:)` that returns
either a Rectangle().fill(Color) or a ZStack of Material + tint
overlay. surfaceShape's role splits: it provides the rounded silhouette
via `.fill(.clear)` for clipping, and the actual fill comes from the
new builder via `.background(...).clipShape(surfaceShape)`.

5 new localized strings × 3 lproj.
EOF
)"
```

### Task A.8: Hand off

`SendMessage` to `'p4-tester'`:

> Phase 4A complete at commit `<sha>`. Files: PanelMaterial.swift (new), IslandPanelView.swift (~30 lines changed), AppearanceSettingsPane.swift (~10 lines added), 3 Localizable.strings (5 keys × 3). Build clean, all tests still green. Begin Phase B.

---

## Phase B — tester

**Owner:** `p4-tester`.
**Goal:** Lock the enum's Codable + raw-string contract.

### Task B.1: One test in `ThemeTests.swift`

```swift
@Test
func appPanelMaterialRoundtripsThroughCodable() throws {
    for mat in AppPanelMaterial.allCases {
        let data = try JSONEncoder().encode(mat)
        let decoded = try JSONDecoder().decode(AppPanelMaterial.self, from: data)
        #expect(decoded == mat)
    }
}

@Test
func appPanelMaterialRawStringIsStable() {
    // The raw strings are persisted in UserDefaults — bumping them
    // is a migration. This test pins the contract.
    #expect(AppPanelMaterial.solid.rawValue == "solid")
    #expect(AppPanelMaterial.frostedThin.rawValue == "frosted-thin")
    #expect(AppPanelMaterial.frostedUltraThin.rawValue == "frosted-ultra-thin")
}
```

### Task B.2: Run + commit

```bash
swift test 2>&1 | tail -3
# Expected: existing count + 2 new tests pass

git add Tests/AtollCoreTests/ThemeTests.swift

git commit -m "$(cat <<'EOF'
test(theme): Phase 4B — lock AppPanelMaterial Codable + raw-string contract

Two tests:
- appPanelMaterialRoundtripsThroughCodable — encode/decode preserves
  the case across all 3 variants.
- appPanelMaterialRawStringIsStable — pins the rawValue strings used
  by @AppStorage. Changing them later is a migration; this test
  forces the conversation.
EOF
)"
```

### Task B.3: Hand off

`SendMessage` to `'p4-reviewer'` with commit SHA + test count.

---

## Phase C — reviewer

**Owner:** `p4-reviewer`.
**Goal:** CPU smoke + manual three-way switch + PR.

### Task C.1: Build dev app + CPU regression gate

Same pattern as earlier reviewers.

### Task C.2: Manual smoke (asks user)

`SendMessage` to dispatcher:

> Visual smoke check needed:
>
> 1. Settings → Appearance → confirm a "Panel material" segmented control appears under the Theme picker with three options.
> 2. Switch to **Solid** — confirm the panel surface is a solid blue-teal `palette.mantle` (Mocha) or whatever your active flavor's mantle is. No translucency.
> 3. Switch to **Frosted (thin)** — confirm the panel surface visibly translucent (you can see your wallpaper through it) with a strong theme-color tint still readable on top.
> 4. Switch to **Frosted (ultra-thin)** — confirm even more wallpaper visible through the panel; theme tint still present but more subtle.
> 5. With Frosted (ultra-thin) selected, COLLAPSE the panel (move mouse away) — confirm the closed/idle state is pure black again (notch blend), NOT translucent.
> 6. Quit + relaunch — confirm the picker remembers the choice.
>
> Reply "ok" or describe failures.

### Task C.3: Push + PR

```bash
git push -u origin feat/panel-material

gh pr create --base main --title "feat(theme): Phase 4 — frosted panel material option" --body "$(cat <<'EOF'
## Summary

Three-way "Panel material" picker in Settings → Appearance:
- **Solid** (default) — `palette.mantle` solid fill (v1.0 look)
- **Frosted (thin)** — `.thinMaterial` + `palette.crust.opacity(0.55)`
- **Frosted (ultra-thin)** — `.ultraThinMaterial` + same overlay

Frosting only applies to the OPENED panel; collapsed/idle stays pure
black to preserve the physical-notch blend on notched MacBooks.

Independent of Phases 2/3 (custom theme registry + editor). Can be
shipped before, between, or after them.

- New `AppPanelMaterial` enum in AtollCore.
- `IslandPanelView` render site refactored from a single `Color` to a
  `@ViewBuilder surfaceFill(palette:)`.
- @AppStorage("appearance.panelMaterial") persists the choice.
- 5 new localized strings × 3 lproj.
- 2 new tests, 381/381 green (or 359 + 2 = 361 if Phases 2/3 haven't
  merged yet).

## Test plan

- [x] `swift build` clean
- [x] `swift test` — all green
- [x] CPU settles ≤ 1%
- [x] Manual: 3-way switch retints live, collapsed state stays pure black
- [ ] Reviewer visual sign-off

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

gh pr view --json url -q .url
```

### Task C.4: Final report

`SendMessage` to dispatcher with PR URL + summary. Then exit.

---

## Verification gates

| Gate    | Pass condition                                                       |
| ------- | -------------------------------------------------------------------- |
| **A→B** | Build clean. Existing tests still green. Phase A commit on branch.   |
| **B→C** | Build clean. Existing + 2 new tests green.                           |
| **C→**  | CPU ≤ 1%. User 6-step manual sign-off. PR open.                      |

---

## Out of scope

- Per-theme material override (e.g. "always frosted on Latte"). Today's design is global — one material setting applies regardless of theme.
- Animated transitions between materials. Switching is instant (which matches macOS Settings appearance switches).
- Custom material strengths between thin and ultra-thin. SwiftUI exposes only those two graceful steps.
- Renaming `OpenIslandApp.swift` (still uses the old filename — see v1.0 README's deferred-cosmetics note).
