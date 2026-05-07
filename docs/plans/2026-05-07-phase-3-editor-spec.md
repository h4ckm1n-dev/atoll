# Phase 3 — Theme Editor Sheet — HIG Design Spec

**Audience:** `p3-coder` (`apple-dev:swift-developer`)
**Author:** `p3-architect` (`apple-dev:apple-ui-designer`)
**Date:** 2026-05-07
**Status:** Authoritative for Phase B implementation. Where this spec disagrees with the plan's inline pseudo-code, this spec wins.

This spec is platform-targeted: macOS 14+ (Sonoma) settings sheet over a SwiftUI Settings scene. Target product: Open Island / Atoll. All measurements in points (pt) unless noted.

---

## 0. One-paragraph recommendation

A 480×720 fixed-size sheet, system materials and SF type, three `DisclosureGroup`s housing 26 `ColorRoleRow`s, and a sticky action bar with `.cancelAction` / `.defaultAction` shortcuts wired to Cancel and Save respectively. Live preview is achieved by a single `.onChange(of: draft)` that calls `themeManager.setPreviewPalette(draft)` — SwiftUI's natural coalescing handles the 60 Hz cap. No custom controls beyond the bidirectionally-bound hex `TextField` (the system `ColorPicker` is the source of truth for the picker UI itself). Reference: HIG → "Sheets", "Color Wells", "Disclosure Controls", "Materials".

---

## 1. Sheet container

### 1.1 Dimensions

- **Width:** 480 pt — fixed (`.frame(width: 480, ...)`).
- **Height:** 720 pt — fixed. Justification: 26 rows + headers + bottom bar fit comfortably; sheet is taller than 13" MBA's content area only when Settings window already small. Sheet must NOT exceed 720 pt because macOS sheets never grow beyond their parent window's content rect.
- **Edge insets:** 0 (the sheet itself is edge-to-edge; padding is internal — see §3, §4, §6).
- **Resize:** disabled. Fixed `.frame(width: 480, height: 720)`. Settings sheets are not user-resizable by HIG convention.

### 1.2 Window chrome

- Standard sheet chrome (no titlebar — sheet ribbon sits inside Settings window).
- Background: default system `Form`/sheet background (do **not** apply a custom material; the sheet sits over an opaque Settings pane and a material would create a double-blur).

### 1.3 Vertical structure (top → bottom)

```
┌──────────────────────────────────────────────┐
│  Header                              ~ 64 pt │  (theme name + isLight toggle, padding 16)
├──────────────────────────────────────────────┤
│  Divider (1 pt)                              │
├──────────────────────────────────────────────┤
│                                              │
│  ScrollView                                  │
│   ├─ Surfaces DisclosureGroup (expanded)     │  Body fills remaining height
│   ├─ Foregrounds DisclosureGroup (collapsed) │
│   └─ Accents DisclosureGroup (collapsed)     │
│                                              │
├──────────────────────────────────────────────┤
│  Divider (1 pt)                              │
├──────────────────────────────────────────────┤
│  Bottom action bar                  ~ 56 pt  │  (Reset · Cancel · Save, padding 16)
└──────────────────────────────────────────────┘
```

Header and bottom bar are fixed; only the middle scrolls. This is the standard HIG sheet pattern (Mail rules editor, Calendar event details). HIG: "Layout" → "Use a fixed header and footer to anchor primary controls".

---

## 2. Header (top section, fixed)

### 2.1 Layout

- Outer container: `HStack(spacing: 12)`, padding `.horizontal(16)`, padding `.vertical(12)` → ~64 pt total height.
- Two children, left to right:

| # | Element             | Width             | Behavior                              |
|---|---------------------|-------------------|---------------------------------------|
| 1 | Theme name TextField | flexible (fills)  | `.textFieldStyle(.roundedBorder)`     |
| 2 | "Light text" Toggle | intrinsic         | `.toggleStyle(.switch)` macOS switch  |

### 2.2 Theme name TextField

- Placeholder: `lang.t("theme.editor.name")` → "Theme name".
- Bound to `$draftName: String`.
- Font: `.system(size: 14, weight: .medium)` (slightly heavier than body to read as the document title).
- `.textFieldStyle(.roundedBorder)` — default macOS TextField chrome.
- Auto-focus on appear: yes — `.focused($nameFieldFocused)` with `.task { nameFieldFocused = true }` so a fresh sheet lets the user type immediately. (HIG: "Make the most likely first action effortless.")
- Empty handling: displayed as is (empty string). Save button is disabled when trimmed empty (see §5.4).

### 2.3 isLight Toggle

- Label: `Text(lang.t("theme.editor.lightToggle"))` → "Light text".
- Bound to `$draft.isLight`.
- `.toggleStyle(.switch)` (macOS Sonoma standard switch — NOT `.checkbox`).
- `.help(lang.t("theme.editor.lightToggle.help"))` → tooltip on hover with explanatory text "Use dark text on light surfaces — pick this for light themes."
- Toggle must NOT be vertically centered to the TextField's baseline — let HStack center alignment (the switch's intrinsic center) handle it; `Toggle` already aligns correctly inside an HStack.

### 2.4 Localization

All strings via `lang.t(...)`. Pass `lang` into `ThemeEditorSheet` as a parameter (mirroring `AppearanceSettingsPane`). Keys:
- `theme.editor.name`
- `theme.editor.lightToggle`
- `theme.editor.lightToggle.help`

---

## 3. Body — ScrollView with three DisclosureGroups

### 3.1 ScrollView

- Single `ScrollView(.vertical, showsIndicators: true)`.
- Inner content padding: `.padding(16)` so DisclosureGroups don't kiss the divider lines or the side walls.
- DisclosureGroups in a `VStack(alignment: .leading, spacing: 8)`.

### 3.2 The three DisclosureGroups (in order)

| Group        | Default state | Rows | Localization key                |
|--------------|---------------|------|---------------------------------|
| Surfaces     | **expanded**  | 6    | `theme.editor.surfaces`         |
| Foregrounds  | collapsed     | 6    | `theme.editor.foregrounds`      |
| Accents      | collapsed     | 14   | `theme.editor.accents`          |

**Why Surfaces is the only one expanded by default:** it's the most-touched group (base/mantle/crust drive the entire sheet's perceived theme). Foregrounds and Accents are tweaked less often and their combined 20 rows would push the bottom bar off-screen on first view if all three were open.

### 3.3 DisclosureGroup state binding

The plan's pseudo-code uses `isExpanded: .constant(true)` on Surfaces. **Use `@State private var surfacesExpanded = true` etc. instead** — `.constant(true)` would prevent the user from collapsing Surfaces, which is wrong. Spec:

```
@State private var surfacesExpanded: Bool = true
@State private var foregroundsExpanded: Bool = false
@State private var accentsExpanded: Bool = false
```

Bind each `DisclosureGroup`'s `isExpanded:` to the matching `@State`.

### 3.4 Group title styling

Default `DisclosureGroup` title — system font, secondary color label is fine. Do NOT customize the chevron or the disclosure animation; rely on system defaults so the sheet looks consistent with `Form`-style settings panes elsewhere.

### 3.5 Row container inside each group

`VStack(spacing: 4)` — tight rows, since each row is already 36 pt tall (28 pt swatch + 4 pt vertical padding × 2). Total group heights:

- Surfaces: 6 × 36 = 216 pt + group header (~28) + spacing → ~245 pt.
- Foregrounds: same as Surfaces → ~245 pt.
- Accents: 14 × 36 = 504 pt + header → ~535 pt.

When all three are expanded the inner content is ~1050 pt — the ScrollView handles the overflow.

---

## 4. Per-row layout (`ColorRoleRow`)

### 4.1 Geometry

```
┌───────────────────────────────────────────────────────────────┐
│ [swatch] [role name───────────] [hex field]    [color picker] │
│  28×28    flex, leading 13pt    88pt mono       28×28         │
└───────────────────────────────────────────────────────────────┘
```

`HStack(spacing: 12)`, `.padding(.vertical, 2)`. Total row height ~36 pt.

### 4.2 Swatch (leading)

- `RoundedRectangle(cornerRadius: 6, style: .continuous)`.
- `.fill(color.swiftUIColor)`.
- 1pt overlay stroke — `RoundedRectangle(...).strokeBorder(.primary.opacity(0.15), lineWidth: 1)`.
- `.frame(width: 28, height: 28)`.
- **Increase Contrast variant:** when `@Environment(\.accessibilityDifferentiateWithoutColor)` OR `@Environment(\.colorSchemeContrast) == .increased`, bump stroke to `.primary.opacity(0.4)`. Use `.colorSchemeContrast` for macOS Increase Contrast detection.

### 4.3 Role name

- `Text(roleName)`.
- `.font(.system(size: 13))` (regular weight, matches macOS Form row label sizing).
- `.foregroundStyle(.primary)`.
- `.frame(maxWidth: .infinity, alignment: .leading)` so it expands and pushes the hex+picker to the trailing edge.
- Role name strings are NOT localized — they're palette role identifiers (base, mantle, crust, surface0, surface1, surface2, text, subtext1, subtext0, overlay2, overlay1, overlay0, rosewater, flamingo, pink, mauve, red, maroon, peach, yellow, green, teal, sky, sapphire, blue, lavender). Treat them as code identifiers and pass as plain `String`. Justification: these are Catppuccin-defined role names, not English nouns; localizing "rosewater" as "agua de rosas" would confuse anyone cross-referencing the upstream palette.

### 4.4 Hex TextField

- Bound to `$hexDraft: String` (local `@State`).
- Initial value: `color.toHex()` (lowercase, 6 chars, no `#` prefix — match the on-disk JSON shape from Phase 2).
- `.font(.system(size: 12, design: .monospaced))` — monospaced is non-negotiable; users compare hex strings.
- `.textFieldStyle(.roundedBorder)`.
- `.frame(width: 88)` — fits 8 monospaced characters (`#abcdef` = 7 chars + caret room) without truncation. The plan says "8-char wide" — 88 pt at 12 pt monospaced is the right physical size.
- Placeholder: `Text("hex")` (untranslated — universal).
- `.onSubmit { commitHexDraft() }` — commit on Return only. Do NOT commit on every keystroke (would fight user typing).
- `.disableAutocorrection(true)`, `.textInputAutocapitalization(.never)` (no-op on macOS but harmless and future-proof for iPad Catalyst).
- Validation flow:
  1. On Submit, read `hexDraft`.
  2. Strip leading `#` if present.
  3. If `ThemePalette.isValidHex(stripped)` → set `color = ProjectColor.fromHex(stripped)` then resync `hexDraft = color.toHex()` (normalizes case).
  4. Else → silently revert: `hexDraft = color.toHex()`. **No error UI.** (HIG: when input is reversible and the invalid case is obvious, prefer silent revert over alert. This matches Xcode's hex color editor behavior.)

### 4.5 ColorPicker (trailing)

- `ColorPicker("", selection: colorPickerBinding, supportsOpacity: false)`.
- `.labelsHidden()`.
- `.frame(width: 28, height: 28)`.
- The default macOS ColorPicker renders as a square color well; sized at 28×28 it matches the swatch visually.
- `supportsOpacity: false` — the ThemePalette schema is RGB-only, no alpha channel.
- The custom `Binding<Color>` (in plan section B.2) decomposes the dragged color via `cgColor.components` and updates BOTH the underlying `ProjectColor` AND the local `hexDraft` — keeps the hex field live during a drag.

### 4.6 Row interaction model

| Source       | Update path                                                           |
|--------------|-----------------------------------------------------------------------|
| Hex commit   | `hexDraft` → validate → `color` (parent draft) → resync `hexDraft`    |
| Picker drag  | `Color` → `ProjectColor` decomposition → `color` + `hexDraft` both updated |
| Parent reset | `color` (binding) changes → `.onChange(of: color)` resyncs `hexDraft` |

Add `.onChange(of: color) { _, newColor in hexDraft = newColor.toHex() }` so external draft mutations (e.g. "Reset to base") propagate into the local hex draft state. This is missing from the plan's pseudo-code but is required for Reset to actually update the visible hex strings.

### 4.7 Tap target sizing

- macOS pointer targets: 28×28 minimum is acceptable for the ColorPicker. The plan's 28×28 sizing meets that floor.
- The TextField at 88×~22 is well above any minimum.

---

## 5. Bottom action bar (fixed footer)

### 5.1 Layout

- `HStack(spacing: 12)`, `.padding(16)` → ~56 pt total height.
- Three buttons, left-anchored Reset / spacer / right-anchored Cancel + Save.

```
[ Reset to base ]                              [ Cancel ]  [ Save ]
   secondary                                    default    primary
```

### 5.2 Reset to base button

- Title: `lang.t("theme.editor.resetToBase")` → "Reset to base".
- Style: default `Button` (no `.borderedProminent`). On macOS this renders as a standard bordered button.
- Action:
  1. `draft = originalForkBase` — restores the 26 colors to the source preset's palette.
  2. `themeManager.setPreviewPalette(originalForkBase)` is implicit because of the `.onChange(of: draft)` already wired in §7.
- **Does NOT clear preview** — it sets it to the base palette so the live UI shows the reset effect.
- **Does NOT close the sheet** — Reset is a draft-only action.
- **Optional confirmation:** spec **omits** a confirmation dialog. Reset is undoable by clicking Cancel (no save); a confirmation would be over-paternalistic for a non-destructive draft state.

### 5.3 Cancel button

- Title: `lang.t("theme.editor.cancel")` (add this key) — "Cancel".
- Style: default `Button` (NOT prominent). Default-weight, standard bordered.
- `.keyboardShortcut(.cancelAction)` — wires both `Esc` AND `Cmd+.` automatically. (HIG: "Use `.cancelAction` so the system handles both shortcuts uniformly.")
- Action sequence (order matters):
  1. `themeManager.setPreviewPalette(nil)` — clear preview FIRST so the panel snaps back before the sheet animates closed.
  2. `onCancel()` — caller dismisses.

### 5.4 Save button

- Title: `lang.t("theme.editor.save")` (add this key) — "Save".
- Style: `.borderedProminent` (the macOS prominent blue button — accent color from current palette).
- `.keyboardShortcut("s", modifiers: .command)` — `Cmd+S`.
- `.keyboardShortcut(.defaultAction)` is **also** valid and would bind Return; the plan uses `Cmd+S`. **Use `Cmd+S`** because Return inside the editor is consumed by the hex TextField's `onSubmit`. Binding Return to Save would steal it from row commit.
- `.disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)` — empty name disables Save. (HIG: "Disable controls whose action would fail or produce no result.")
- Action:
  1. Build `CustomTheme` via `makeSaved()`.
  2. `themeManager.setPreviewPalette(nil)` — clear preview so the actual save-and-switch flow's repaint isn't doubled.
  3. `onSave(saved)` — caller persists + switches the picker.

### 5.5 Localization keys to add

In addition to plan's 9, also add:
- `theme.editor.cancel` = "Cancel"
- `theme.editor.save` = "Save"

(macOS hosts will fall back to system localizations of "Cancel"/"Save" via `Button(role:)` patterns elsewhere, but explicit keys keep this sheet consistent with the rest of `AppearanceSettingsPane`.)

---

## 6. Accessibility

### 6.1 Per-row VoiceOver

```
.accessibilityElement(children: .combine)
.accessibilityLabel(Text("\(roleName), \(hexDraft)"))
.accessibilityValue(Text(roleName))   // role description for context
.accessibilityHint(Text(lang.t("theme.editor.row.hint")))
   // "Double-tap to open the color picker; or edit the hex value."
```

The row IS one composite accessibility element. The hex `TextField` and `ColorPicker` remain individually focusable for keyboard navigation, but VoiceOver reads the group as a single labeled item.

Add localization key:
- `theme.editor.row.hint` = "Double-tap to open the color picker, or edit the hex value."

### 6.2 Header VoiceOver

- Theme name TextField: native `TextField` accessibility (placeholder is read as label).
- Toggle: native `Toggle` accessibility (label "Light text", value on/off).

### 6.3 Bottom bar VoiceOver

- Buttons read their titles natively. No customization needed.
- Save button announces "dimmed" automatically via `.disabled(...)`.

### 6.4 Reduce Motion

```
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- DisclosureGroup expand/collapse: SwiftUI's default animation is short and respects Reduce Motion automatically. Do NOT add a custom `.animation(...)` modifier — that would override the system's reduce-motion handling.
- The plan's suggested `.animation(reduceMotion ? nil : .easeInOut(duration: 0.2))` is **only needed if you replace the default animation**. Since we keep defaults, omit this line.
- If a custom transition is later needed: gate every `.animation(...)` with `reduceMotion ? nil : <curve>`.

### 6.5 Increase Contrast

```
@Environment(\.colorSchemeContrast) private var colorSchemeContrast
```

- Swatch border: `.primary.opacity(colorSchemeContrast == .increased ? 0.4 : 0.15)`.
- DisclosureGroup chevrons and TextField borders: system handles these automatically via `.colorSchemeContrast`.

### 6.6 Reduce Transparency

Not applicable — this sheet uses no materials. If you later add a frosted background, gate it with `@Environment(\.accessibilityReduceTransparency)`.

### 6.7 Tab order (keyboard navigation)

Standard macOS tab key flow, top-to-bottom, left-to-right within rows:

1. Theme name TextField
2. Light text Toggle
3. Surfaces group: row 0 hex → row 0 ColorPicker → row 1 hex → row 1 ColorPicker → … → row 5 ColorPicker
4. Foregrounds group rows (each hex → picker)
5. Accents group rows (each hex → picker)
6. Reset to base Button
7. Cancel Button
8. Save Button

Notes:
- DisclosureGroup's chevron is keyboard-focusable by default; the user can collapse/expand groups with Space. **This is desired** — don't suppress it.
- A collapsed DisclosureGroup hides its contents from the tab loop automatically (SwiftUI default).
- Do NOT use `.focusable(false)` anywhere — the system focus order is what we want.

### 6.8 Dynamic Type

- macOS doesn't expose Dynamic Type the same way iOS does; `.font(.system(size: 13))` body text is fixed-pixel by HIG convention for settings UIs.
- For the role name, this is acceptable — it's a code identifier display, not body content.
- For the hex TextField, monospaced 12pt is fixed by intent (alignment matters more than scaling).
- The TextField in the header (theme name) at 14pt could use `.font(.body)` for consistency with rest of Settings, but 14pt fixed is also acceptable since `Form`-driven settings panes already use fixed sizing throughout this codebase.

### 6.9 Color contrast

- All text is `.primary` / system colors → adapts to light/dark and Increase Contrast automatically. PASSES WCAG AA in both modes.
- Save button uses `.borderedProminent` → system accent color → PASSES.
- Swatch text/labels are NEVER drawn over the swatch — the swatch is purely visual, with hex string in a separate adjacent TextField. No legibility risk.

---

## 7. Live preview pattern

### 7.1 The contract

Every change to the draft palette — from any source (hex commit, ColorPicker drag, Reset to base) — must immediately be reflected in `themeManager.previewPalette`. The synchronous `palette` getter (`ThemeManager.swift:46-50`) already prefers `previewPalette` when non-nil, so the existing island/notch UI retints automatically.

### 7.2 Implementation pattern

Inside `ThemeEditorSheet.body`:

```swift
.onAppear {
    model.themeManager.setPreviewPalette(draft)
}
.onChange(of: draft) { _, new in
    model.themeManager.setPreviewPalette(new)
}
.onDisappear {
    model.themeManager.setPreviewPalette(nil)  // safety net
}
```

### 7.3 Throttling

**Do NOT throttle.** SwiftUI coalesces `@State` mutations to display refresh rate (60 Hz on most displays, 120 Hz on ProMotion). A manual throttle would *worsen* perceived responsiveness during a ColorPicker drag.

If profiling later shows the live retint exceeds 1% CPU at idle (Phase D's CPU gate), revisit by debouncing only the hex `TextField`'s typing path — but the picker drag path must stay unthrottled.

### 7.4 Cleanup invariants

| Exit path                        | preview cleared? |
|----------------------------------|------------------|
| Cancel button                    | yes (action body)|
| Save button                      | yes (action body)|
| Reset to base button             | NO (re-set to fork base, not nil) |
| Esc / Cmd+. (via `.cancelAction`)| yes (Cancel action runs) |
| Window close / sheet dismiss without action | yes (`.onDisappear`) |
| Crash / force-quit               | not our problem (preview is in-memory only) |

The `.onDisappear` belt-and-braces clearing handles the rare "user closes Settings while sheet is open" edge case.

---

## 8. Empty / nil draft handling

The sheet is **never** presented with a nil draft. The caller (`AppearanceSettingsPane`) is responsible for providing either:

- An existing `CustomTheme` (for Edit) → `original = theme`, `basedOn = theme.basedOn`, draft seeded from `theme.palette`.
- A fresh fork from a preset → `original = nil`, `basedOn = preset`, draft seeded from `preset.builtInPalette`.

The init signature enforces this:

```swift
init(
    original: CustomTheme?,         // nil for fresh fork; non-nil for Edit
    basedOn: AppTheme,              // never nil
    model: AppModel,
    onSave: @escaping (CustomTheme) -> Void,
    onCancel: @escaping () -> Void
)
```

Internal seeding rule: `basePalette = original?.palette ?? (basedOn.builtInPalette ?? .mocha)`. If `basedOn` is `.system` or `.custom(id:)` (which `builtInPalette` returns nil for), fall back to `.mocha` rather than crash. This is a defense-in-depth fallback; the caller should already have prevented this case by passing a built-in preset.

`originalForkBase` (used by Reset to base) follows the same rule: `basedOn.builtInPalette ?? .mocha`.

**Empty `draftName`:**
- Allowed in the field (user can clear and retype).
- Save button disabled while trimmed-empty.
- On Save with whitespace-only name → `makeSaved()` synthesizes `"\(basedOn.displayName) copy"` as a defensive fallback (the disabled state should prevent this from ever firing, but `makeSaved` codifies the contract).

---

## 9. Keyboard shortcuts (final table)

| Shortcut            | Action      | Mechanism                                  |
|---------------------|-------------|--------------------------------------------|
| `Cmd+S`             | Save        | `.keyboardShortcut("s", modifiers: .command)` |
| `Esc`               | Cancel      | `.keyboardShortcut(.cancelAction)`         |
| `Cmd+.`             | Cancel      | `.keyboardShortcut(.cancelAction)` (system maps both) |
| `Return`            | Commit hex (when focused on hex field) | `TextField.onSubmit` |
| `Tab` / `Shift+Tab` | Move focus  | system default                             |
| `Space`             | Toggle DisclosureGroup expand (when chevron focused) | system default |

**Do NOT** bind `Return` to Save — it would conflict with `TextField.onSubmit` for the hex commit. The plan's pseudo-code did not bind Return; this spec confirms that decision.

---

## 10. ASCII layout sketch (full sheet, all groups expanded)

```
╔═════════════════════════════════════════════════════════╗
║  ┌─────────────────────────────────────┐  ┌─────────┐   ║  ← header (64 pt)
║  │ My Mocha Fork                       │  │ ⬤ Light │   ║
║  └─────────────────────────────────────┘  └─────────┘   ║
╠═════════════════════════════════════════════════════════╣
║                                                         ║
║  ▼ Surfaces                                             ║  ← DisclosureGroup
║  ┌─┐                                                    ║
║  │█│ base       ┌───────────┐  ┌─┐                     ║  ← row (36 pt)
║  └─┘            │ 1e1e2e    │  │█│                     ║
║  ┌─┐                                                    ║
║  │█│ mantle     ┌───────────┐  ┌─┐                     ║
║  └─┘            │ 181825    │  │█│                     ║
║   ... (4 more rows: crust, surface0, surface1, surface2)║
║                                                         ║
║  ▶ Foregrounds  (collapsed by default)                  ║
║                                                         ║
║  ▶ Accents      (collapsed by default)                  ║
║                                                         ║
╠═════════════════════════════════════════════════════════╣
║  [ Reset to base ]                  [ Cancel ] [ Save ] ║  ← bottom bar (56 pt)
╚═════════════════════════════════════════════════════════╝
                          480 pt
```

Total: 64 + 1 + ~599 (scrollable body) + 1 + 56 = 720 pt.

---

## 11. HIG references (decision audit trail)

| Decision                                  | HIG section                              |
|-------------------------------------------|------------------------------------------|
| Sheet at fixed 480×720 over Settings      | Sheets → "Modal sheets fit their content"|
| `DisclosureGroup` for grouped editing     | Disclosure Controls → "Progressive reveal of related fields" |
| `ColorPicker` system control              | Color Wells → "Use the system color well rather than a custom picker" |
| `.borderedProminent` for primary action   | Buttons → "One prominent action per dialog" |
| `.cancelAction` keyboard shortcut         | Keyboard → "Cancel: Esc and Cmd+ ."      |
| Silent revert on invalid hex              | Feedback → "Prefer reversible silent correction over interrupting alerts" |
| Reduce Motion handling via system default | Accessibility → "Use system animations so Reduce Motion is automatic" |
| Increase Contrast via `.colorSchemeContrast` | Accessibility → "Adapt strokes and dividers to Increase Contrast" |
| Combined accessibility element per row    | Accessibility → "Group related controls so VoiceOver speaks one item" |
| Monospaced font for hex                   | Typography → "Use SF Mono for tabular or hex numeric data" |
| Disable Save when name empty              | Buttons → "Disable buttons whose action cannot succeed" |

---

## 12. Trade-offs and explicit non-decisions

### Decisions made

- **Surfaces expanded by default** vs all-expanded: chose expanded-Surfaces because all-expanded pushes the bottom bar off-screen at 720pt window height.
- **Silent hex revert** vs error popover: chose silent revert (matches Xcode, Sketch, Figma — all silent on invalid hex).
- **Cmd+S only for Save** vs adding `.defaultAction` Return: chose Cmd+S only because Return is consumed by the hex TextField.
- **Role names un-localized**: they are Catppuccin palette identifiers, not English words.
- **No custom DisclosureGroup animation**: rely on system default so Reduce Motion is automatic.
- **No throttle on `.onChange(of: draft)`**: SwiftUI's natural coalescing is sufficient.

### Deferred (out of scope for Phase 3)

- Snapshot tests of the sheet layout (the codebase has none; Phase D handles visual smoke manually).
- iOS/iPadOS layout — Atoll is macOS-only.
- A "favorites" subgroup inside Accents — premature.
- Drag-to-reorder roles — the 26 Catppuccin roles have fixed identity.
- Per-role descriptions / help popovers — could be added later as `.help(...)` on each row's role name.

### Caveat to coder

The plan's pseudo-code at `Phase B` is a starting point; this spec corrects two items:

1. `isExpanded: .constant(true)` on Surfaces → use `@State surfacesExpanded` (3 separate states) so groups remain collapsible.
2. Add `.onChange(of: color) { _, newColor in hexDraft = newColor.toHex() }` inside `ColorRoleRow` so external draft changes (Reset) update the hex string visibly.

Everything else in the plan's pseudo-code matches this spec.

---

## End of spec.

Coder: when in doubt, default to system behavior. Anything not explicitly specified here, do not invent — let the SwiftUI defaults speak.
