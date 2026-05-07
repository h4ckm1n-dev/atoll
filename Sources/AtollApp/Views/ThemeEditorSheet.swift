import SwiftUI
import AtollCore

/// Modal sheet for editing a custom theme. Presents 26 color pickers
/// (Surfaces 6 / Foregrounds 6 / Accents 14) plus an isLight toggle.
/// Every picker drag pushes the draft palette into
/// `themeManager.previewPalette` so the island/notch retints live.
/// Cancel reverts to the previously-active palette; Save commits via
/// the caller's `onSave` closure.
struct ThemeEditorSheet: View {
    /// Existing custom theme being edited, or nil when creating a new one.
    let original: CustomTheme?
    let basedOn: AppTheme

    var model: AppModel
    let lang: LanguageManager

    let onSave: (CustomTheme) -> Void
    let onCancel: () -> Void

    @State private var draftName: String
    @State private var draft: ThemePalette
    @State private var surfacesExpanded = true
    @State private var foregroundsExpanded = false
    @State private var accentsExpanded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let originalForkBase: ThemePalette

    init(
        original: CustomTheme?,
        basedOn: AppTheme,
        model: AppModel,
        lang: LanguageManager,
        onSave: @escaping (CustomTheme) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.original = original
        self.basedOn = basedOn
        self.model = model
        self.lang = lang
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
            // Push every change into the live preview slot so the panel
            // retints on the same frame.
            model.themeManager.setPreviewPalette(new)
        }
        .onAppear {
            model.themeManager.setPreviewPalette(draft)
        }
        .onDisappear {
            // Safety net: clear preview if the sheet closes without
            // an explicit Save or Cancel (e.g. window close).
            model.themeManager.setPreviewPalette(nil)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            TextField(lang.t("theme.editor.name"), text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14, weight: .medium))
            Toggle(lang.t("theme.editor.lightToggle"), isOn: $draft.isLight)
                .toggleStyle(.switch)
                .help(lang.t("theme.editor.lightToggle.help"))
        }
        .padding(16)
    }

    // MARK: - Disclosure groups

    private var surfacesGroup: some View {
        DisclosureGroup(lang.t("theme.editor.surfaces"), isExpanded: $surfacesExpanded) {
            VStack(spacing: 4) {
                ColorRoleRow(roleName: "base",     color: $draft.base)
                ColorRoleRow(roleName: "mantle",   color: $draft.mantle)
                ColorRoleRow(roleName: "crust",    color: $draft.crust)
                ColorRoleRow(roleName: "surface0", color: $draft.surface0)
                ColorRoleRow(roleName: "surface1", color: $draft.surface1)
                ColorRoleRow(roleName: "surface2", color: $draft.surface2)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: draft)
    }

    private var foregroundsGroup: some View {
        DisclosureGroup(lang.t("theme.editor.foregrounds"), isExpanded: $foregroundsExpanded) {
            VStack(spacing: 4) {
                ColorRoleRow(roleName: "text",     color: $draft.text)
                ColorRoleRow(roleName: "subtext1", color: $draft.subtext1)
                ColorRoleRow(roleName: "subtext0", color: $draft.subtext0)
                ColorRoleRow(roleName: "overlay2", color: $draft.overlay2)
                ColorRoleRow(roleName: "overlay1", color: $draft.overlay1)
                ColorRoleRow(roleName: "overlay0", color: $draft.overlay0)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: draft)
    }

    private var accentsGroup: some View {
        DisclosureGroup(lang.t("theme.editor.accents")) {
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: draft)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(lang.t("theme.editor.resetToBase")) {
                draft = originalForkBase
            }
            Spacer()
            Button(lang.t("settings.cancel")) {
                model.themeManager.setPreviewPalette(nil)
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            Button(lang.t("settings.save")) {
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

    // MARK: - Private helpers

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
