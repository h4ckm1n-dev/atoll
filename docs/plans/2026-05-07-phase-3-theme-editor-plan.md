# Phase 3 — In-App 26-Picker Theme Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
>
> **Execution mode:** swarm. Spawn `architect → coder → tester → reviewer` in one Agent message, all `run_in_background: true`. See "Swarm dispatch" below.

**Goal:** Let users edit a custom theme inside Atoll: a modal sheet with 26 color pickers (Surfaces 6 / Foregrounds 6 / Accents 14) and an `isLight` toggle, with **live preview** — every drag of a picker retints the actual island/notch in real-time. Save commits the theme to disk via the registry from Phase 2 and switches the picker to it; Cancel reverts cleanly.

**Architecture:** Three pieces. (1) `themeManager.previewPalette: ThemePalette?` already stubbed in Phase 2A — flesh it out so the synchronous `palette` getter returns the preview when set. (2) New `ThemeEditorSheet` owns a draft `ThemePalette` in `@State`, mutates it on every picker drag, pushes it into `themeManager.previewPalette`. Cancel clears preview; Save calls `registry.save(...)` + clears preview + switches picker. (3) New `ColorRoleRow` is the per-color editor row — hex `TextField` + system `ColorPicker` synchronized via a custom `Binding` (typing in hex updates the picker, dragging the picker updates hex).

**Tech Stack:** Swift 6.2, SwiftUI `Sheet` + `ColorPicker` + `DisclosureGroup`, Swift Testing.

**Authoritative reference:** `docs/plans/2026-05-06-theme-personalization-design.md` — section "UI surfaces > Editor sheet" + "Architecture > Live preview during editing".

---

## Preconditions

1. **Phase 2 must be merged to main first.** This plan depends on `CustomThemeRegistry`, `CustomTheme`, the `previewPalette` stub in `ThemeManager`, and the "+ Create from preset…" / per-row Menu in Settings → Appearance. Verify with:
   ```bash
   git log --oneline main | grep -E "Phase 2[ABCD]" | head
   # Expected: 3 commits (A, B, C) plus possibly a merge commit
   test -f Sources/AtollCore/CustomTheme.swift && echo OK
   test -f Sources/AtollCore/CustomThemeRegistry.swift && echo OK
   ```
2. Worktree: `git worktree add ../theme-editor -b feat/theme-editor main`.
3. Dev environment: `swift --version` ≥ 6.2.
4. `swift build && swift test` from `main` passes (373 tests).

---

## Swarm dispatch

```javascript
Agent({
  subagent_type: "apple-dev:apple-ui-designer",
  name: "p3-architect",
  run_in_background: true,
  prompt: "Open the theme-editor worktree. Read docs/plans/2026-05-07-phase-3-theme-editor-plan.md section 'Phase A — architect (HIG)' and design doc section 'UI surfaces > Editor sheet'. Execute Phase A — produce a design specification for the sheet layout, the 3 disclosure groups, the per-row layout, the Reset/Cancel/Save bar, and accessibility (VoiceOver labels, Reduce Motion respect, keyboard nav). SendMessage to 'p3-coder' with the spec attached as plain text in the message body. Then exit. Do NOT write Swift code."
})
Agent({
  subagent_type: "apple-dev:swift-developer",
  name: "p3-coder",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'p3-architect'. Read plan section 'Phase B — coder' + the architect's spec. Execute Phase B end-to-end. SendMessage to 'p3-tester' with: (a) commit SHA, (b) per-file change summary. Then exit."
})
Agent({
  subagent_type: "apple-dev:swift-developer",
  name: "p3-tester",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'p3-coder'. Read plan section 'Phase C — tester'. Execute Phase C. When tests pass (target: 373 + ~6 new = ~379), SendMessage to 'p3-reviewer' with full test output tail. Then exit."
})
Agent({
  subagent_type: "pr-review-toolkit:code-reviewer",
  name: "p3-reviewer",
  run_in_background: true,
  prompt: "Wait for SendMessage from 'p3-tester'. Read plan section 'Phase D — reviewer'. Execute Phase D (CPU smoke + manual editor walkthrough + PR). Report final status with PR URL."
})

SendMessage({ to: "p3-architect", summary: "Start", message: "Phase 3 of theme personalization. Plan at docs/plans/2026-05-07-phase-3-theme-editor-plan.md. Worktree feat/theme-editor off main. Begin Phase A — sheet HIG spec." })
```

---

## Phase A — architect (HIG)

**Owner:** `p3-architect` (`apple-dev:apple-ui-designer`).
**Goal:** Produce a design spec for the editor sheet that the coder can implement without UI/UX guesswork.

### Task A.1: Read the design doc + Phase 2's settings UI

```bash
sed -n '/^### Editor sheet/,/^## /p' docs/plans/2026-05-06-theme-personalization-design.md
grep -nA 5 "settings.theme.customSection" Sources/AtollApp/Views/AppearanceSettingsPane.swift | head -20
```

### Task A.2: Produce the spec

The spec is a plain-text document covering:

1. **Sheet dimensions:** width 480 pt, height adapts to content (target ≤ 720 pt to avoid pushing off small screens).
2. **Header:** theme name as `TextField` (editable inline — saves on Save, reverts on Cancel). isLight toggle on the right, labeled "Light text" with HIG-compliant explanatory `helpText("Use dark text on light surfaces — pick this for light themes.")`.
3. **Body:** scrollable `VStack` of 3 `DisclosureGroup`s:
   - Surfaces (6 colors: base, mantle, crust, surface0, surface1, surface2)
   - Foregrounds (6 colors: text, subtext1, subtext0, overlay2, overlay1, overlay0)
   - Accents (14 colors: rosewater, flamingo, pink, mauve, red, maroon, peach, yellow, green, teal, sky, sapphire, blue, lavender)

   Each group expands by default for the Surfaces tab on first open (most-used) and stays collapsed for the others until clicked.
4. **Per-row layout** (`ColorRoleRow`):
   - 28×28 swatch (RoundedRectangle with 6pt radius, palette color fill, 1px stroke at `.text.opacity(0.15)`)
   - Role name (left-aligned, 13pt regular)
   - Hex `TextField` (monospaced, 8 chars wide, accepts 6-char hex with optional `#` prefix; rejects invalid input on commit by reverting to the last valid value)
   - System `ColorPicker` (the OS color wheel — hidden label, takes ~28×28)
5. **Bottom bar:** sticky `HStack` with three buttons (right-aligned):
   - "Reset to base" (secondary, restores the draft from `originalForkBase`)
   - "Cancel" (default-weight, dismisses sheet without saving)
   - "Save" (primary, blue, accent color from current palette)
   - Cancel and Reset both clear `themeManager.previewPalette`.
6. **Accessibility:**
   - Each `ColorRoleRow` exposes its swatch + hex as one combined accessibility element with label "<RoleName>, <hex>", value of the role description.
   - VoiceOver action: "Open color picker" on each row.
   - Reduce Motion: skip the disclosure-expand animation (`.animation(reduceMotion ? nil : .easeInOut(duration: 0.2))`).
   - Increase Contrast: bump swatch stroke to `.text.opacity(0.4)`.
   - Tab order: theme name → isLight toggle → first row hex → first row picker → ... → Reset → Cancel → Save.
7. **Live preview:** every change to a `ColorRoleRow`'s value (via either hex commit or picker drag) immediately mutates the draft palette in `@State` AND pushes it into `themeManager.previewPalette`. Throttle if needed (60 Hz max — SwiftUI's natural update rate is fine).
8. **Empty / nil draft:** the editor sheet is always presented with a non-nil draft (caller seeds it from a preset or an existing custom theme). Sheet does not gracefully handle nil — it's the caller's responsibility.
9. **Keyboard shortcuts:** `Cmd+S` Save, `Cmd+.` Cancel, `Esc` Cancel.

### Task A.3: Send the spec to coder

`SendMessage` to `'p3-coder'` with the full spec as plain text. Include any layout sketches as ASCII art if helpful.

Then exit.

---

## Phase B — coder

**Owner:** `p3-coder`.
**Goal:** Implement the sheet + the row + wire `previewPalette` so the live preview works.

### Task B.1: Flesh out `themeManager.previewPalette`

**Files:** Modify `Sources/AtollApp/ThemeManager.swift`.

Phase 2A added a stub `public var previewPalette: ThemePalette? = nil`. Verify it's still there:

```bash
grep -n "previewPalette" Sources/AtollApp/ThemeManager.swift
```

The synchronous `palette` getter from Phase 2A already consults it. Verify:

```bash
grep -nA 12 "public var palette: ThemePalette" Sources/AtollApp/ThemeManager.swift
```

If the Phase 2A code reads `if let preview = previewPalette { return preview }` first — done. If not, add it.

Also add explicit setters that the editor uses:

```swift
public func setPreviewPalette(_ palette: ThemePalette?) {
    self.previewPalette = palette
}
```

(Direct assignment works since `previewPalette` is a stored property; the wrapper just gives the editor a clean MainActor-bounded API.)

### Task B.2: Build `ColorRoleRow`

**Files:** Create `Sources/AtollApp/Views/ColorRoleRow.swift`.

Per the architect's spec:

```swift
import SwiftUI
import AtollCore

/// One row in the theme editor sheet. Renders the role name + a swatch
/// + a hex text field + a system color picker, all bound to the same
/// underlying `ProjectColor`. Typing a hex value updates the picker;
/// dragging the picker updates the hex. Invalid hex on commit reverts.
struct ColorRoleRow: View {
    let roleName: LocalizedStringKey
    @Binding var color: ProjectColor

    @State private var hexDraft: String

    init(roleName: LocalizedStringKey, color: Binding<ProjectColor>) {
        self.roleName = roleName
        self._color = color
        self._hexDraft = State(initialValue: color.wrappedValue.toHex())
    }

    var body: some View {
        HStack(spacing: 12) {
            swatch
                .frame(width: 28, height: 28)

            Text(roleName)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("hex", text: $hexDraft)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(width: 88)
                .onSubmit(commitHexDraft)

            ColorPicker("", selection: colorPickerBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(roleName), \(hexDraft)"))
    }

    private var swatch: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color.swiftUIColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
            )
    }

    /// Bridges between the Color picker (which uses SwiftUI's `Color`)
    /// and our underlying `ProjectColor` value type. Picker drags
    /// produce SwiftUI Colors; we decompose into RGB components.
    private var colorPickerBinding: Binding<Color> {
        Binding(
            get: { color.swiftUIColor },
            set: { newColor in
                let resolved = newColor.cgColor ?? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
                let comps = resolved.components ?? [0, 0, 0, 1]
                let r = Double(comps.indices.contains(0) ? comps[0] : 0)
                let g = Double(comps.indices.contains(1) ? comps[1] : 0)
                let b = Double(comps.indices.contains(2) ? comps[2] : 0)
                color = ProjectColor(red: r, green: g, blue: b)
                hexDraft = color.toHex()
            }
        )
    }

    private func commitHexDraft() {
        var s = hexDraft
        if s.hasPrefix("#") { s.removeFirst() }
        if ThemePalette.isValidHex(s) {
            color = ProjectColor.fromHex(s)
            hexDraft = color.toHex()  // normalize to lowercase
        } else {
            // Revert to the last good value.
            hexDraft = color.toHex()
        }
    }
}
```

### Task B.3: Build `ThemeEditorSheet`

**Files:** Create `Sources/AtollApp/Views/ThemeEditorSheet.swift`.

```swift
import SwiftUI
import AtollCore

struct ThemeEditorSheet: View {
    /// Existing theme being edited, or nil if creating fresh.
    let original: CustomTheme?
    let basedOn: AppTheme

    var model: AppModel  // for themeManager.previewPalette + registry

    let onSave: (CustomTheme) -> Void
    let onCancel: () -> Void

    @State private var draftName: String
    @State private var draft: ThemePalette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let originalForkBase: ThemePalette

    init(
        original: CustomTheme?,
        basedOn: AppTheme,
        model: AppModel,
        onSave: @escaping (CustomTheme) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.original = original
        self.basedOn = basedOn
        self.model = model
        self.onSave = onSave
        self.onCancel = onCancel
        let baseName = original?.displayName ?? "\(basedOn.displayName) copy"
        let basePalette = original?.palette ?? (basedOn.builtInPalette ?? .mocha)
        self._draftName = State(initialValue: baseName)
        self._draft = State(initialValue: basePalette)
        self.originalForkBase = basedOn.builtInPalette ?? .mocha
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    surfacesGroup
                    foregroundsGroup
                    accentsGroup
                }
                .padding(16)
            }
            Divider()
            bottomBar
        }
        .frame(width: 480, height: 720)
        .onChange(of: draft) { _, new in
            // Push every change into the live preview slot so the
            // panel retints in real-time.
            model.themeManager.setPreviewPalette(new)
        }
        .onAppear {
            model.themeManager.setPreviewPalette(draft)
        }
        .onDisappear {
            // Safety net: if the sheet dismisses without Save/Cancel
            // (e.g. window close), clear the preview.
            model.themeManager.setPreviewPalette(nil)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            TextField("Theme name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, weight: .medium))
            Toggle("Light text", isOn: $draft.isLight)
                .toggleStyle(.switch)
                .help("Use dark text on light surfaces — pick this for light themes.")
        }
        .padding(16)
    }

    private var surfacesGroup: some View {
        DisclosureGroup("Surfaces", isExpanded: .constant(true)) {
            VStack(spacing: 4) {
                ColorRoleRow(roleName: "base",     color: $draft.base)
                ColorRoleRow(roleName: "mantle",   color: $draft.mantle)
                ColorRoleRow(roleName: "crust",    color: $draft.crust)
                ColorRoleRow(roleName: "surface0", color: $draft.surface0)
                ColorRoleRow(roleName: "surface1", color: $draft.surface1)
                ColorRoleRow(roleName: "surface2", color: $draft.surface2)
            }
        }
    }

    private var foregroundsGroup: some View {
        DisclosureGroup("Foregrounds") {
            VStack(spacing: 4) {
                ColorRoleRow(roleName: "text",     color: $draft.text)
                ColorRoleRow(roleName: "subtext1", color: $draft.subtext1)
                ColorRoleRow(roleName: "subtext0", color: $draft.subtext0)
                ColorRoleRow(roleName: "overlay2", color: $draft.overlay2)
                ColorRoleRow(roleName: "overlay1", color: $draft.overlay1)
                ColorRoleRow(roleName: "overlay0", color: $draft.overlay0)
            }
        }
    }

    private var accentsGroup: some View {
        DisclosureGroup("Accents") {
            VStack(spacing: 4) {
                ColorRoleRow(roleName: "rosewater", color: $draft.rosewater)
                ColorRoleRow(roleName: "flamingo",  color: $draft.flamingo)
                ColorRoleRow(roleName: "pink",      color: $draft.pink)
                ColorRoleRow(roleName: "mauve",     color: $draft.mauve)
                ColorRoleRow(roleName: "red",       color: $draft.red)
                ColorRoleRow(roleName: "maroon",    color: $draft.maroon)
                ColorRoleRow(roleName: "peach",     color: $draft.peach)
                ColorRoleRow(roleName: "yellow",    color: $draft.yellow)
                ColorRoleRow(roleName: "green",     color: $draft.green)
                ColorRoleRow(roleName: "teal",      color: $draft.teal)
                ColorRoleRow(roleName: "sky",       color: $draft.sky)
                ColorRoleRow(roleName: "sapphire",  color: $draft.sapphire)
                ColorRoleRow(roleName: "blue",      color: $draft.blue)
                ColorRoleRow(roleName: "lavender",  color: $draft.lavender)
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button("Reset to base") {
                draft = originalForkBase
            }
            Spacer()
            Button("Cancel") {
                model.themeManager.setPreviewPalette(nil)
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            Button("Save") {
                let saved = makeSaved()
                model.themeManager.setPreviewPalette(nil)
                onSave(saved)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
    }

    private func makeSaved() -> CustomTheme {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? "\(basedOn.displayName) copy" : trimmed
        if var existing = original {
            existing.displayName = displayName
            existing.palette = draft
            return existing
        }
        return CustomTheme(
            displayName: displayName,
            palette: draft,
            basedOn: basedOn
        )
    }
}
```

### Task B.4: Wire the sheet into Settings → Appearance

**Files:** Modify `Sources/AtollApp/Views/AppearanceSettingsPane.swift`.

Phase 2B added "+ Create from preset…" → confirmationDialog → `createCustomFromPreset(...)` which currently just duplicates and selects. Replace it so it opens the editor sheet:

```swift
@State private var editorContext: EditorContext? = nil

private struct EditorContext: Identifiable {
    let id = UUID()
    let original: CustomTheme?
    let basedOn: AppTheme
}

// Replace createCustomFromPreset with:
private func createCustomFromPreset(_ preset: AppTheme) {
    editorContext = EditorContext(original: nil, basedOn: preset)
}

// Add an "Edit" button to customThemeRow's Menu:
Button(lang.t("settings.theme.row.edit")) {
    editorContext = EditorContext(original: theme, basedOn: theme.basedOn)
}

// Present the sheet:
.sheet(item: $editorContext) { ctx in
    ThemeEditorSheet(
        original: ctx.original,
        basedOn: ctx.basedOn,
        model: model,
        onSave: { saved in
            Task { @MainActor in
                do {
                    try await model.themeManager.customRegistry.save(saved)
                    await model.themeManager.refreshCustomThemes()
                    model.themeManager.setTheme(.custom(id: saved.id))
                } catch {
                    importErrorMessage = error.localizedDescription
                    isPresentingImportError = true
                }
                editorContext = nil
            }
        },
        onCancel: {
            editorContext = nil
        }
    )
}
```

### Task B.5: Add localized strings for the editor

**Files:** Modify the 3 `Localizable.strings` files.

Add to `en.lproj`:

```
"settings.theme.row.edit" = "Edit…";
"theme.editor.title" = "Edit theme";
"theme.editor.name" = "Theme name";
"theme.editor.lightToggle" = "Light text";
"theme.editor.lightToggle.help" = "Use dark text on light surfaces — pick this for light themes.";
"theme.editor.surfaces" = "Surfaces";
"theme.editor.foregrounds" = "Foregrounds";
"theme.editor.accents" = "Accents";
"theme.editor.resetToBase" = "Reset to base";
```

Same shape for `zh-Hans.lproj` (translate to Simplified Chinese) and `zh-Hant.lproj` (Traditional Chinese).

Replace the hardcoded `LocalizedStringKey` literals in `ThemeEditorSheet` (`"Theme name"`, `"Light text"`, `"Surfaces"`, etc.) with calls to `lang.t("theme.editor.<key>")` — pass `lang` through as a parameter just like `AppearanceSettingsPane` does.

### Task B.6: Build + verify

```bash
swift build 2>&1 | tail -3
swift test 2>&1 | tail -3
# Expected: build clean, 373/373 tests still passing (Phase B adds no new tests yet)
```

### Task B.7: Commit Phase B

```bash
git add Sources/AtollApp/ThemeManager.swift \
        Sources/AtollApp/Views/ColorRoleRow.swift \
        Sources/AtollApp/Views/ThemeEditorSheet.swift \
        Sources/AtollApp/Views/AppearanceSettingsPane.swift \
        Sources/AtollApp/Resources/en.lproj/Localizable.strings \
        Sources/AtollApp/Resources/zh-Hans.lproj/Localizable.strings \
        Sources/AtollApp/Resources/zh-Hant.lproj/Localizable.strings

git commit -m "$(cat <<'EOF'
feat(theme): Phase 3B — in-app 26-picker editor sheet with live preview

A modal sheet with three disclosure groups (Surfaces 6 / Foregrounds
6 / Accents 14), each row pairing a hex TextField with a system
ColorPicker. Editing any color pushes into themeManager.previewPalette
on the same frame; the actual island/notch retints live as you drag.
Cancel clears the preview; Save commits via the registry from Phase 2.

- ColorRoleRow: 28×28 swatch + role name + 8-char monospaced hex
  TextField + system ColorPicker. Hex TextField commits on Submit;
  invalid hex reverts to the last good value (no error UI — defensive
  silent revert matches HIG hex pickers elsewhere on macOS). Picker
  drags decompose CGColor into RGB and update both swatch + hex
  together. Combined accessibility element with VoiceOver label
  "<role>, <hex>".
- ThemeEditorSheet: 480×720 sheet, header (theme name + isLight
  toggle), scrollable body with 3 DisclosureGroups (Surfaces expanded
  by default, others collapsed), bottom bar (Reset to base / Cancel /
  Save with Cmd+S keyboard shortcut). Reset restores from
  basedOn.builtInPalette. Save creates or updates a CustomTheme via
  the caller's onSave closure.
- ThemeManager.setPreviewPalette(_:) — explicit MainActor setter.
  The synchronous palette getter from Phase 2A already consulted
  previewPalette first; this just gives the editor a clean API.
- AppearanceSettingsPane: "+ Create from preset…" no longer duplicates
  immediately — it opens the editor sheet pre-populated. Per-row
  Menu gains "Edit…" which reopens the sheet on an existing theme.
- 9 new localized strings × 3 lproj.

373/373 existing tests still green.
EOF
)"
```

### Task B.8: Hand off

`SendMessage` to `'p3-tester'`:

> Phase 3B complete at commit `<sha>`. Files: ColorRoleRow.swift (new), ThemeEditorSheet.swift (new), ThemeManager.swift (setPreviewPalette), AppearanceSettingsPane.swift (sheet wiring + Edit menu item), 3 Localizable.strings (9 keys × 3). Build clean, 373/373 tests still green. Begin Phase C.

Then exit.

---

## Phase C — tester

**Owner:** `p3-tester`.
**Goal:** Lock the preview-mode contract + hex validation + the editor's draft-to-CustomTheme conversion.

### Task C.1: `ThemePalettePreviewModeTests`

**Files:** Modify `Tests/AtollCoreTests/ThemeTests.swift`.

```swift
@Test
func setPreviewPaletteOverridesActiveTheme() async {
    let manager = await ThemeManager()  // requires @MainActor; await synthesizes
    // Initial state: palette resolves from theme.
    let initial = await manager.palette
    #expect(initial == ThemePalette.mocha)
    // Set a preview, palette should now return the preview value.
    await manager.setPreviewPalette(.latte)
    let preview = await manager.palette
    #expect(preview == ThemePalette.latte)
    // Clear the preview, palette returns to theme-resolved.
    await manager.setPreviewPalette(nil)
    let cleared = await manager.palette
    #expect(cleared == ThemePalette.mocha)
}

@Test
func setPreviewPaletteSurvivesThemeSwitch() async {
    let manager = await ThemeManager()
    await manager.setPreviewPalette(.frappe)
    await manager.setTheme(.latte)
    let still = await manager.palette
    // Even after theme switch, the preview wins.
    #expect(still == ThemePalette.frappe)
    // Clearing the preview reveals the new theme.
    await manager.setPreviewPalette(nil)
    let revealed = await manager.palette
    #expect(revealed == ThemePalette.latte)
}
```

### Task C.2: `HexValidationTests`

```swift
@Test
func isValidHexAcceptsLowercaseUppercaseAndOptionalHash() {
    #expect(ThemePalette.isValidHex("abcdef"))
    #expect(ThemePalette.isValidHex("ABCDEF"))
    #expect(ThemePalette.isValidHex("#abcdef"))
    #expect(ThemePalette.isValidHex("#ABCDEF"))
    #expect(ThemePalette.isValidHex("000000"))
    #expect(ThemePalette.isValidHex("ffffff"))
}

@Test
func isValidHexRejectsBadInput() {
    #expect(!ThemePalette.isValidHex(""))
    #expect(!ThemePalette.isValidHex("abc"))                 // 3 chars
    #expect(!ThemePalette.isValidHex("xyz123"))              // non-hex
    #expect(!ThemePalette.isValidHex("0x123456"))            // unsupported prefix
    #expect(!ThemePalette.isValidHex("abcdefg"))             // 7 chars
    #expect(!ThemePalette.isValidHex(" abcdef"))             // leading whitespace
}

@Test
func projectColorHexRoundtripIsLossless() {
    let samples = ["162232", "ffffff", "000000", "a6e3a1", "1e1e2e"]
    for s in samples {
        let c = ProjectColor.fromHex(s)
        #expect(c.toHex() == s, "\(s) round-trip lost: \(c.toHex())")
    }
}
```

### Task C.3: Run + commit

```bash
swift test 2>&1 | tail -3
# Expected: 373 + 6 = 379 tests pass

git add Tests/AtollCoreTests/ThemeTests.swift

git commit -m "$(cat <<'EOF'
test(theme): Phase 3C — lock previewPalette + hex validation contracts

6 new tests:

- setPreviewPaletteOverridesActiveTheme — preview wins over theme,
  clearing reveals theme.
- setPreviewPaletteSurvivesThemeSwitch — preview survives a setTheme
  call (the editor depends on this so a stray theme change during
  editing doesn't blow away the in-progress draft).
- isValidHexAcceptsLowercaseUppercaseAndOptionalHash — six positive
  cases.
- isValidHexRejectsBadInput — six negative cases.
- projectColorHexRoundtripIsLossless — fromHex → toHex preserves the
  string for known good inputs.

379/379 tests in 41+ suites green.
EOF
)"
```

### Task C.4: Hand off

`SendMessage` to `'p3-reviewer'` with: commit SHA, "379 tests green", begin Phase D.

---

## Phase D — reviewer

**Owner:** `p3-reviewer`.
**Goal:** Confirm the editor works live + open the PR.

### Task D.1: Build dev app + CPU regression gate

Same pattern as Phase 1/2 reviewer's. Wait for ≤ 5% sustained, gate at 1%.

### Task D.2: Manual editor walkthrough (asks user)

`SendMessage` to dispatcher:

> Visual smoke check needed:
>
> 1. Settings → Appearance → "+ Create from preset…" → Latte → confirm editor sheet opens with all 26 rows visible.
> 2. Drag the `green` accent picker — confirm the island/notch's success indicators (running agent dots, completion banner) retint LIVE during the drag.
> 3. Type `ff0000` into the `red` row's hex field, press Enter — confirm the picker swatch and the live panel both update.
> 4. Type `xyz` into the `blue` row's hex field, press Enter — confirm the field reverts to the previous value with no error UI.
> 5. Toggle "Light text" — confirm whatever text overlays should flip do flip.
> 6. Click "Reset to base" — confirm all 26 colors revert to Latte's stock values.
> 7. Click Cancel — confirm the panel returns to whatever theme was previously active (no lingering Latte tint).
> 8. Reopen "+ Create from preset…" → Mocha → make some changes → click Save → confirm the new theme appears in the picker, is selected, panel retints to the saved values.
> 9. Click ⋯ on the saved theme → Edit → confirm the sheet reopens with the saved values, NOT a fresh fork.
>
> Reply "ok" or describe failures.

### Task D.3: Push + PR

```bash
git push -u origin feat/theme-editor

gh pr create --base main --title "feat(theme): Phase 3 — in-app 26-picker theme editor with live preview" --body "$(cat <<'EOF'
## Summary

Phase 3 of the theme-personalization rollout. Users can now edit any
custom theme inside Atoll: a modal sheet with 26 color pickers
arranged in three disclosure groups (Surfaces / Foregrounds /
Accents), live preview as you drag, isLight toggle, Reset / Cancel /
Save with Cmd+S keyboard shortcut.

Depends on Phase 2 (custom theme registry).

- New `ColorRoleRow` — swatch + hex TextField + system ColorPicker,
  bidirectionally synced.
- New `ThemeEditorSheet` — 480×720 sheet, three DisclosureGroups,
  pushes draft into `themeManager.previewPalette` on every change.
- `themeManager.setPreviewPalette(_:)` API. The synchronous `palette`
  getter from Phase 2A already consulted the preview slot.
- "+ Create from preset…" + per-row "Edit…" menu item now both open
  the editor.
- 6 new tests (preview mode + hex validation), 379/379 green.
- 9 new localized strings × 3 lproj.

## Test plan

- [x] `swift build` clean
- [x] `swift test` — 379/379 green
- [x] CPU settles ≤ 1%
- [x] Manual: editor opens, drag retints live, hex commits, invalid
  hex reverts, Reset works, Cancel reverts, Save persists.
- [ ] Reviewer visual sign-off

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"

gh pr view --json url -q .url
```

### Task D.4: Final report

Same as Phase 2's D.6. Phase 4 (frosted panel) is independent — can land before, between, or after Phases 2/3 once they merge.

---

## Verification gates

| Gate    | Pass condition                                                       |
| ------- | -------------------------------------------------------------------- |
| **A→B** | architect spec sent to coder; nothing else (no code in Phase A).     |
| **B→C** | Build clean. 373 tests still green. Sheet wired into settings.       |
| **C→D** | Build clean. 379 tests green (6 new).                                |
| **D→**  | CPU ≤ 1%. User 9-step manual sign-off. PR open.                      |

---

## Out of scope

- Phase 4 (frosted panel material).
- Snapshot tests of the sheet layout (none in this codebase; not adding now).
- Per-color swatch customization beyond the 28×28 standard.
- Drag-to-reorder colors (the 26 Catppuccin roles have a fixed identity; reordering would invent a new taxonomy).
