import AppKit
import SwiftUI
import AtollCore

struct AppearanceSettingsPane: View {
    var model: AppModel
    @State private var previewPhase: SessionPhase = .running

    // MARK: Custom theme state
    @State private var isPresentingPresetChooser = false
    @State private var isPresentingImportError = false
    @State private var importErrorMessage: String? = nil
    @State private var renameTarget: CustomTheme? = nil
    @State private var deleteTarget: CustomTheme? = nil
    @State private var editorContext: EditorContext? = nil

    private struct EditorContext: Identifiable {
        let id = UUID()
        let original: CustomTheme?
        let basedOn: AppTheme
    }

    @Environment(\.themePalette) private var palette

    @AppStorage("appearance.panelMaterial")
    private var panelMaterialRaw: String = AppPanelMaterial.solid.rawValue

    private var lang: LanguageManager { model.lang }
    private var isCustom: Bool { model.islandAppearanceMode == .custom }

    // MARK: - Theme picker binding

    private var themeBinding: Binding<String> {
        Binding(
            get: { model.themeManager.theme.stableID },
            set: { newID in
                guard let newTheme = AppTheme(stableID: newID) else { return }
                Task { @MainActor in
                    model.themeManager.setTheme(newTheme)
                }
            }
        )
    }

    var body: some View {
        Form {
            Section(lang.t("settings.theme.title")) {
                Picker(lang.t("settings.theme.picker"), selection: themeBinding) {
                    Section(lang.t("settings.theme.builtin")) {
                        ForEach(AppTheme.builtIn, id: \.stableID) { theme in
                            Text(theme.displayName).tag(theme.stableID)
                        }
                    }
                    if !model.themeManager.customThemes.isEmpty {
                        Section(lang.t("settings.theme.custom")) {
                            ForEach(model.themeManager.customThemes) { custom in
                                Text(custom.displayName).tag(AppTheme.custom(id: custom.id).stableID)
                            }
                        }
                    }
                }
                themePreviewRow(palette: model.themeManager.palette)
                Text(lang.t("settings.theme.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(lang.t("settings.panelMaterial.title"), selection: $panelMaterialRaw) {
                    ForEach(AppPanelMaterial.allCases, id: \.rawValue) { mat in
                        Text(lang.t(mat.localizationKey)).tag(mat.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .help(lang.t("settings.panelMaterial.help"))
            }

            // MARK: Custom themes section
            Section(lang.t("settings.theme.customSection")) {
                if model.themeManager.customThemes.isEmpty {
                    Text(lang.t("settings.theme.customEmpty"))
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                } else {
                    ForEach(model.themeManager.customThemes) { custom in
                        customThemeRow(custom)
                    }
                }
                HStack(spacing: 12) {
                    Button(lang.t("settings.theme.createFromPreset")) {
                        isPresentingPresetChooser = true
                    }
                    Button(lang.t("settings.theme.importFromFile")) {
                        presentImportPanel()
                    }
                }
            }
            .confirmationDialog(
                lang.t("settings.theme.preset.choose"),
                isPresented: $isPresentingPresetChooser,
                titleVisibility: .visible
            ) {
                ForEach(AppTheme.builtIn, id: \.stableID) { preset in
                    Button(preset.displayName) {
                        createCustomFromPreset(preset)
                    }
                }
                Button(lang.t("settings.cancel"), role: .cancel) { }
            }
            .alert(
                lang.t("settings.theme.import.failed"),
                isPresented: $isPresentingImportError,
                presenting: importErrorMessage
            ) { _ in
                Button(lang.t("settings.ok"), role: .cancel) { }
            } message: { msg in
                Text(msg)
            }
            .alert(
                lang.t("settings.theme.delete.confirm"),
                isPresented: deleteAlertBinding,
                presenting: deleteTarget
            ) { theme in
                Button(lang.t("settings.theme.row.delete"), role: .destructive) {
                    performDelete(theme)
                }
                Button(lang.t("settings.cancel"), role: .cancel) { }
            } message: { theme in
                Text(lang.t("settings.theme.delete.message", theme.displayName))
            }
            .sheet(item: $renameTarget) { theme in
                RenameThemeSheet(
                    original: theme,
                    onSave: { newName in
                        renameTheme(theme, to: newName)
                        renameTarget = nil
                    },
                    onCancel: { renameTarget = nil }
                )
            }
            .sheet(item: $editorContext) { ctx in
                ThemeEditorSheet(
                    original: ctx.original,
                    basedOn: ctx.basedOn,
                    model: model,
                    lang: lang,
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

            Section(lang.t("settings.appearance.mode")) {
                Picker(lang.t("settings.appearance.mode"), selection: Binding(
                    get: { model.islandAppearanceMode },
                    set: { model.islandAppearanceMode = $0 }
                )) {
                    Text(lang.t("settings.appearance.mode.default")).tag(IslandAppearanceMode.default)
                    Text(lang.t("settings.appearance.mode.custom")).tag(IslandAppearanceMode.custom)
                }
                .pickerStyle(.segmented)

                if !isCustom {
                    Text(lang.t("settings.appearance.mode.defaultDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(lang.t("settings.appearance.style")) {
                if isCustom {
                    Picker(lang.t("settings.appearance.closedStyle"), selection: Binding(
                        get: { model.islandClosedDisplayStyle },
                        set: { model.islandClosedDisplayStyle = $0 }
                    )) {
                        Text(lang.t("settings.appearance.style.minimal")).tag(IslandClosedDisplayStyle.minimal)
                        Text(lang.t("settings.appearance.style.detailed")).tag(IslandClosedDisplayStyle.detailed)
                    }
                    .pickerStyle(.segmented)
                }

                Toggle(lang.t("settings.appearance.hideIdleToEdge"), isOn: Binding(
                    get: { model.hideIdleIslandToEdge },
                    set: { model.hideIdleIslandToEdge = $0 }
                ))

                Text(lang.t("settings.appearance.hideIdleToEdge.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isCustom {
                Section(lang.t("settings.appearance.preview")) {
                    notchPreviewCard
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section(lang.t("settings.appearance.pixelShape")) {
                    HStack(spacing: 12) {
                        ForEach(IslandPixelShapeStyle.allCases) { style in
                            pixelShapeCard(style)
                        }
                    }

                    if model.islandPixelShapeStyle == .custom {
                        HStack(spacing: 12) {
                            Button(lang.t("settings.appearance.avatar.upload")) {
                                model.importCustomAvatar()
                            }
                            if model.customAvatarImage != nil {
                                Button(lang.t("settings.appearance.avatar.remove")) {
                                    model.removeCustomAvatar()
                                }
                                .foregroundStyle(.red)
                            }
                        }

                        Text(lang.t("settings.appearance.avatar.help"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(lang.t("settings.appearance.statusColors")) {
                    ForEach(SessionPhase.allCases, id: \.self) { phase in
                        statusColorRow(phase)
                    }
                }
            }

            Section {
                DisclosureGroup(lang.t("settings.projectColors.title")) {
                    let keys = model.projectColorRegistry.knownKeys().sorted()
                    if keys.isEmpty {
                        Text(lang.t("settings.projectColors.empty"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(keys, id: \.self) { key in
                            projectColorRow(key)
                        }
                    }
                    HStack {
                        Button(lang.t("settings.projectColors.resetAll")) {
                            model.projectColorRegistry.resetAll()
                        }
                        Button(lang.t("settings.projectColors.removeUnused")) {
                            model.projectColorRegistry.pruneUnusedKeys(activePaths: model.activeWorkspaceKeys)
                        }
                    }
                    Text(lang.t("settings.projectColors.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(lang.t("settings.ambient.title")) {
                Toggle(lang.t("settings.ambient.toggle"), isOn: Binding(
                    get: { model.ambientThemeEnabled },
                    set: { model.ambientThemeEnabled = $0 }
                ))

                HStack {
                    Text(lang.t("settings.ambient.subtle")).font(.caption).foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { model.ambientThemeOpacity },
                        set: { model.ambientThemeOpacity = AmbientTheme.clampOpacity($0) }
                    ), in: AmbientTheme.minOpacity...AmbientTheme.maxOpacity)
                    Text(lang.t("settings.ambient.bold")).font(.caption).foregroundStyle(.secondary)
                }

                Text(lang.t("settings.ambient.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(lang.t("settings.celebrations.title")) {
                Toggle(lang.t("settings.celebrations.toggle"), isOn: Binding(
                    get: { model.celebrationsEnabled },
                    set: { model.celebrationsEnabled = $0 }
                ))
                Text(lang.t("settings.celebrations.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(lang.t("settings.appearance.communityNote"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.appearance"))
    }


    // MARK: - Custom theme helpers

    @ViewBuilder
    private func customThemeRow(_ theme: CustomTheme) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.displayName)
                    .font(.system(size: 13))
                Text(lang.t("settings.theme.customRow.subtitle", theme.basedOn.displayName))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button(lang.t("settings.theme.row.edit")) {
                    editorContext = EditorContext(original: theme, basedOn: theme.basedOn)
                }
                Button(lang.t("settings.theme.row.rename")) { renameTarget = theme }
                Button(lang.t("settings.theme.row.duplicate")) { duplicateTheme(theme) }
                Button(lang.t("settings.theme.row.export")) { exportTheme(theme) }
                Divider()
                Button(lang.t("settings.theme.row.delete"), role: .destructive) {
                    deleteTarget = theme
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func createCustomFromPreset(_ preset: AppTheme) {
        editorContext = EditorContext(original: nil, basedOn: preset)
    }

    private func duplicateTheme(_ theme: CustomTheme) {
        Task { @MainActor in
            do {
                _ = try await model.themeManager.customRegistry.duplicate(id: theme.id)
                await model.themeManager.refreshCustomThemes()
            } catch {
                importErrorMessage = error.localizedDescription
                isPresentingImportError = true
            }
        }
    }

    private func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("settings.theme.import.button", comment: "")
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                do {
                    let theme = try await model.themeManager.customRegistry.importTheme(from: url)
                    await model.themeManager.refreshCustomThemes()
                    model.themeManager.setTheme(.custom(id: theme.id))
                } catch {
                    importErrorMessage = error.localizedDescription
                    isPresentingImportError = true
                }
            }
        }
    }

    private func exportTheme(_ theme: CustomTheme) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(theme.displayName).json"
        if panel.runModal() == .OK, let url = panel.url {
            Task { @MainActor in
                do {
                    try await model.themeManager.customRegistry.exportTheme(theme, to: url)
                } catch {
                    importErrorMessage = error.localizedDescription
                    isPresentingImportError = true
                }
            }
        }
    }

    private func performDelete(_ theme: CustomTheme) {
        Task { @MainActor in
            do {
                try await model.themeManager.customRegistry.delete(id: theme.id)
                await model.themeManager.refreshCustomThemes()
                // If the deleted theme was active, fall back to mocha.
                if case .custom(let id) = model.themeManager.theme, id == theme.id {
                    model.themeManager.setTheme(.mocha)
                }
            } catch {
                importErrorMessage = error.localizedDescription
                isPresentingImportError = true
            }
        }
    }

    private func renameTheme(_ theme: CustomTheme, to newName: String) {
        var updated = theme
        updated.displayName = newName
        Task { @MainActor in
            do {
                try await model.themeManager.customRegistry.save(updated)
                await model.themeManager.refreshCustomThemes()
            } catch {
                importErrorMessage = error.localizedDescription
                isPresentingImportError = true
            }
        }
    }

    // MARK: - Preview card

    // Preview is a fixed visual mock of the physical notch on a dark
    // wallpaper. Chrome here is intentionally NOT palette-driven —
    // changing it would make the preview lie about the actual notch
    // appearance.
    private var notchPreviewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.surface0.swiftUIColor)

            VStack(spacing: 14) {
                previewIslandBar
                previewPhaseSelector
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    private var previewIslandBar: some View {
        if shouldPreviewIdleEdgeOnly {
            return AnyView(previewIdleEdge)
        }

        let tint = model.statusColor(for: previewPhase)
        let isDetailed = model.islandClosedDisplayStyle == .detailed

        return AnyView(HStack(spacing: 8) {
            IslandPixelGlyph(
                tint: tint,
                style: model.islandPixelShapeStyle,
                isAnimating: previewPhase != .completed,
                customAvatarImage: model.customAvatarImage
            )

            if previewPhase.requiresAttention {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(tint)
            }

            if isDetailed {
                Text(phaseTitle(previewPhase))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            }

            Spacer()

            Text("2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            if isDetailed {
                Text(lang.t("settings.appearance.preview.sessions"))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous)))
    }

    private var shouldPreviewIdleEdgeOnly: Bool {
        model.hideIdleIslandToEdge && previewPhase == .running
    }

    private var previewIdleEdge: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.black)
                .frame(height: 4)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity)
    }

    private var previewPhaseSelector: some View {
        HStack(spacing: 8) {
            ForEach(SessionPhase.allCases, id: \.self) { phase in
                Button {
                    previewPhase = phase
                } label: {
                    Text(phaseTitle(phase))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(previewPhase == phase ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                previewPhase == phase
                                    ? model.statusColor(for: phase).opacity(0.35)
                                    : Color.white.opacity(0.06)
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Status color row

    private func statusColorRow(_ phase: SessionPhase) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(model.statusColor(for: phase))
                .frame(width: 10, height: 10)

            Text(phaseTitle(phase))

            Spacer()

            Text(model.statusColorHexes[phase] ?? "#6E9FFF")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            ColorPicker(
                "",
                selection: Binding(
                    get: { model.statusColor(for: phase) },
                    set: { model.setStatusColor($0, for: phase) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }

    // MARK: - Pixel shape card

    private func pixelShapeCard(_ style: IslandPixelShapeStyle) -> some View {
        let selected = model.islandPixelShapeStyle == style
        return Button {
            if style == .custom && model.customAvatarImage == nil {
                model.importCustomAvatar()
            } else {
                model.islandPixelShapeStyle = style
            }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.surface0.swiftUIColor)
                    .frame(height: 48)
                    .overlay {
                        if style == .custom {
                            if let avatar = model.customAvatarImage {
                                Image(nsImage: avatar)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            IslandPixelGlyph(
                                tint: model.statusColor(for: previewPhase),
                                style: style,
                                isAnimating: previewPhase != .completed,
                                width: 30,
                                height: 18
                            )
                        }
                    }

                Text(pixelShapeTitle(style))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? palette.surface0.swiftUIColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        selected ? Color.accentColor : palette.text.swiftUIColor.opacity(0.08),
                        lineWidth: selected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func phaseTitle(_ phase: SessionPhase) -> String {
        switch phase {
        case .running:            lang.t("settings.appearance.status.running")
        case .waitingForApproval: lang.t("settings.appearance.status.approval")
        case .waitingForAnswer:   lang.t("settings.appearance.status.answer")
        case .completed:          lang.t("settings.appearance.status.completed")
        }
    }

    private func pixelShapeTitle(_ style: IslandPixelShapeStyle) -> String {
        switch style {
        case .bars:   lang.t("settings.appearance.pixelShape.bars")
        case .steps:  lang.t("settings.appearance.pixelShape.steps")
        case .blocks: lang.t("settings.appearance.pixelShape.blocks")
        case .custom: lang.t("settings.appearance.pixelShape.custom")
        }
    }

    /// 8-swatch row showing the active palette's notable accents so the
    /// user can preview the flavor before committing. The swatches don't
    /// react to taps — Picker above is the source of truth.
    @ViewBuilder
    private func themePreviewRow(palette: ThemePalette) -> some View {
        HStack(spacing: 6) {
            swatch(palette.base)
            swatch(palette.surface0)
            swatch(palette.text)
            swatch(palette.green)
            swatch(palette.yellow)
            swatch(palette.peach)
            swatch(palette.red)
            swatch(palette.mauve)
        }
    }

    private func swatch(_ color: ProjectColor) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color.swiftUIColor)
            .frame(width: 18, height: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(palette.text.swiftUIColor.opacity(0.06))
            )
    }

    // MARK: - Project colors

    /// Catppuccin Mocha accents across the color wheel + three muted
    /// overlays. Coupled to Mocha (not the active theme) so a workspace's
    /// chosen color stays stable when the user switches themes — only
    /// rendering through palette-aware helpers shifts.
    private static let projectColorPresets: [ProjectColor] = [
        ProjectColor.fromHex("f38ba8"),  // red
        ProjectColor.fromHex("fab387"),  // peach
        ProjectColor.fromHex("f9e2af"),  // yellow
        ProjectColor.fromHex("a6e3a1"),  // green
        ProjectColor.fromHex("94e2d5"),  // teal
        ProjectColor.fromHex("89dceb"),  // sky
        ProjectColor.fromHex("89b4fa"),  // blue
        ProjectColor.fromHex("cba6f7"),  // mauve
        ProjectColor.fromHex("f5c2e7"),  // pink
        ProjectColor.fromHex("9399b2"),  // overlay2
        ProjectColor.fromHex("7f849c"),  // overlay1
        ProjectColor.fromHex("6c7086"),  // overlay0
    ]

    @ViewBuilder
    private func projectColorRow(_ key: String) -> some View {
        let current = model.projectColorRegistry.color(for: key)
        HStack(spacing: 10) {
            Circle()
                .fill(swiftUIColor(current))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text((key as NSString).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                Text(key)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Menu {
                ForEach(Array(Self.projectColorPresets.enumerated()), id: \.offset) { _, preset in
                    Button {
                        model.projectColorRegistry.setColor(preset, for: key)
                    } label: {
                        HStack {
                            Circle().fill(swiftUIColor(preset)).frame(width: 12, height: 12)
                            Text(hexLabel(preset))
                        }
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func swiftUIColor(_ c: ProjectColor) -> Color {
        Color(red: c.red, green: c.green, blue: c.blue)
    }

    private func hexLabel(_ c: ProjectColor) -> String {
        let r = Int((c.red * 255).rounded())
        let g = Int((c.green * 255).rounded())
        let b = Int((c.blue * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - RenameThemeSheet

private struct RenameThemeSheet: View {
    let original: CustomTheme
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var draftName: String

    init(original: CustomTheme, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.original = original
        self.onSave = onSave
        self.onCancel = onCancel
        self._draftName = State(initialValue: original.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("settings.theme.rename.title", comment: ""))
                .font(.headline)
            TextField(NSLocalizedString("settings.theme.rename.placeholder", comment: ""), text: $draftName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(NSLocalizedString("settings.cancel", comment: ""), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("settings.save", comment: "")) {
                    let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(trimmed.isEmpty ? original.displayName : trimmed)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
