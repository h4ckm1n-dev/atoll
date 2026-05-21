import SwiftUI
import AppKit
import AtollCore
@preconcurrency import MarkdownUI

// MARK: - Settings tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case setup
    case display
    case sound
    case appearance
    case watch
    case shortcuts
    case dictation
    case lab
    case about

    var id: String { rawValue }

    func label(_ lang: LanguageManager) -> String {
        switch self {
        case .general:    lang.t("settings.tab.general")
        case .setup:      lang.t("settings.tab.setup")
        case .appearance: lang.t("settings.tab.appearance")
        case .display:    lang.t("settings.tab.display")
        case .sound:      lang.t("settings.tab.sound")
        case .watch:      "Watch"
        case .shortcuts:  lang.t("settings.tab.shortcuts")
        case .dictation:  lang.t("settings.tab.dictation")
        case .lab:        lang.t("settings.tab.lab")
        case .about:      lang.t("settings.tab.about")
        }
    }

    var icon: String {
        switch self {
        case .general:    "gearshape.fill"
        case .setup:      "arrow.down.circle.fill"
        case .appearance: "paintbrush.fill"
        case .display:    "textformat.size"
        case .sound:      "speaker.wave.2.fill"
        case .watch:      "applewatch"
        case .shortcuts:  "keyboard.fill"
        case .dictation:  "waveform.badge.mic"
        case .lab:        "flask.fill"
        case .about:      "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .general:    .gray
        case .setup:      .orange
        case .appearance: .purple
        case .display:    .blue
        case .sound:      .green
        case .watch:      .cyan
        case .shortcuts:  .gray
        case .dictation:  .indigo
        case .lab:        .pink
        case .about:      .blue
        }
    }

    var section: SettingsSection {
        switch self {
        case .general, .setup, .display, .sound, .appearance, .watch: .system
        case .shortcuts, .dictation, .lab:                            .advanced
        case .about:                                                  .app
        }
    }
}

enum SettingsSection: String, CaseIterable {
    case system
    case advanced
    case app

    func header(_ lang: LanguageManager) -> String {
        switch self {
        case .system:   lang.t("settings.section.system")
        case .advanced: lang.t("settings.section.advanced")
        case .app:      "Open Island"
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.section == self }
    }
}

// MARK: - Root settings view

struct SettingsView: View {
    var model: AppModel
    @State private var selectedTab: SettingsTab = .general

    private var lang: LanguageManager { model.lang }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailView
        }
        .frame(minWidth: 680, idealWidth: 780, minHeight: 480, idealHeight: 560)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: .openIslandSelectSetupTab)) { _ in
            selectedTab = .setup
        }
    }

    // MARK: Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selectedTab) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Section(section.header(lang)) {
                    ForEach(section.tabs) { tab in
                        Label {
                            Text(tab.label(lang))
                        } icon: {
                            Image(systemName: tab.icon)
                                .foregroundStyle(tab.iconColor)
                        }
                        .tag(tab)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailView: some View {
        ZStack(alignment: .topTrailing) {
            switch selectedTab {
            case .general:
                GeneralSettingsPane(model: model)
            case .setup:
                SetupSettingsPane(model: model)
            case .appearance:
                AppearanceSettingsPane(model: model)
            case .display:
                DisplaySettingsPane(model: model)
            case .sound:
                SoundSettingsPane(model: model)
            case .watch:
                WatchSettingsPane(model: model)
            case .shortcuts:
                ShortcutsSettingsPane(model: model)
            case .dictation:
                DictationSettingsPane(model: model)
            case .lab:
                LabSettingsPane(model: model)
            case .about:
                AboutSettingsPane(model: model)
            }

            if model.updateChecker.hasUpdate {
                UpdateCard(updateChecker: model.updateChecker, lang: lang)
                    .padding(.top, 8)
                    .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - Lab

struct LabSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section {
                Toggle(lang.t("settings.lab.mediaControls"), isOn: Binding(
                    get: { model.mediaControlsEnabled },
                    set: { model.mediaControlsEnabled = $0 }
                ))

                Toggle(lang.t("settings.lab.mediaArtwork"), isOn: Binding(
                    get: { model.mediaArtworkEnabled },
                    set: { model.mediaArtworkEnabled = $0 }
                ))
                .disabled(!model.mediaControlsEnabled)

                Text(lang.t("settings.lab.mediaHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(lang.t("settings.lab.section.media"))
            }

            Section {
                Toggle(lang.t("settings.appearance.badges.tool"), isOn: Binding(
                    get: { model.sessionToolBadgeEnabled },
                    set: { model.sessionToolBadgeEnabled = $0 }
                ))
                Toggle(lang.t("settings.appearance.badges.terminal"), isOn: Binding(
                    get: { model.sessionTerminalBadgeEnabled },
                    set: { model.sessionTerminalBadgeEnabled = $0 }
                ))
                Toggle(lang.t("settings.appearance.badges.gitBranch"), isOn: Binding(
                    get: { model.sessionGitBranchBadgeEnabled },
                    set: { model.sessionGitBranchBadgeEnabled = $0 }
                ))
                Toggle(lang.t("settings.appearance.badges.gitDiff"), isOn: Binding(
                    get: { model.sessionGitDiffBadgeEnabled },
                    set: { model.sessionGitDiffBadgeEnabled = $0 }
                ))
                Toggle(lang.t("settings.appearance.badges.context"), isOn: Binding(
                    get: { model.sessionContextBadgeEnabled },
                    set: { model.sessionContextBadgeEnabled = $0 }
                ))
                Toggle(lang.t("settings.appearance.badges.age"), isOn: Binding(
                    get: { model.sessionAgeBadgeEnabled },
                    set: { model.sessionAgeBadgeEnabled = $0 }
                ))
            } header: {
                Text(lang.t("settings.appearance.badges"))
            }

            Section {
                Toggle(lang.t("settings.lab.advancedAvatars"), isOn: Binding(
                    get: { model.advancedAvatarsEnabled },
                    set: { model.advancedAvatarsEnabled = $0 }
                ))

                Text(lang.t("settings.lab.avatarHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(lang.t("settings.lab.section.avatar"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.lab"))
    }
}

// MARK: - General

struct GeneralSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.section.system")) {
                Toggle(lang.t("settings.general.launchAtLogin"), isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.launchAtLoginEnabled = $0 }
                ))

                Picker(lang.t("settings.general.monitor"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            Section(lang.t("settings.general.language")) {
                Picker(lang.t("settings.general.language"), selection: Binding(
                    get: { lang.language },
                    set: { lang.language = $0 }
                )) {
                    Text(lang.t("settings.general.languageSystem")).tag(LanguageManager.AppLanguage.system)
                    Text(lang.t("settings.general.languageEnglish")).tag(LanguageManager.AppLanguage.en)
                    Text(lang.t("settings.general.languageChinese")).tag(LanguageManager.AppLanguage.zhHans)
                    Text(lang.t("settings.general.languageTraditionalChinese")).tag(LanguageManager.AppLanguage.zhHant)
                }
            }

            Section(lang.t("settings.general.behavior")) {
                Toggle(lang.t("settings.general.autoCollapse"), isOn: .constant(true))
                Toggle(lang.t("settings.general.showDockIcon"), isOn: Binding(
                    get: { model.showDockIcon },
                    set: { model.showDockIcon = $0 }
                ))
                Toggle(lang.t("settings.general.hapticFeedback"), isOn: Binding(
                    get: { model.hapticFeedbackEnabled },
                    set: { model.hapticFeedbackEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.completionReply"), isOn: Binding(
                    get: { model.completionReplyEnabled },
                    set: { model.completionReplyEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.liveCodingMode"), isOn: Binding(
                    get: { model.liveCodingModeEnabled },
                    set: { model.liveCodingModeEnabled = $0 }
                ))
                Toggle(lang.t("settings.general.suppressFrontmostNotifications"), isOn: Binding(
                    get: { model.suppressFrontmostNotifications },
                    set: { model.suppressFrontmostNotifications = $0 }
                ))
            }

            Section(lang.t("settings.stream.title")) {
                Toggle(lang.t("settings.stream.overlay"), isOn: Binding(
                    get: { model.streamOverlayEnabled },
                    set: { model.streamOverlayEnabled = $0 }
                ))

                LabeledContent(lang.t("settings.stream.url")) {
                    HStack(spacing: 8) {
                        Text(model.streamOverlayURLText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(lang.t("settings.stream.copyURL")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.streamOverlayURLText, forType: .string)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Text(lang.t("settings.stream.help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.general"))
    }
}

// MARK: - Display

struct DisplaySettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.display.monitor")) {
                Picker(lang.t("settings.display.position"), selection: Binding(
                    get: { model.overlayDisplaySelectionID },
                    set: { model.overlayDisplaySelectionID = $0 }
                )) {
                    Text(lang.t("settings.general.automatic")).tag(OverlayDisplayOption.automaticID)
                    ForEach(model.overlayDisplayOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            if let diag = model.overlayPlacementDiagnostics {
                Section(lang.t("settings.display.diagnostics")) {
                    LabeledContent(lang.t("settings.display.currentScreen"), value: diag.targetScreenName)
                    LabeledContent(lang.t("settings.display.layoutMode"), value: diag.modeDescription)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.display"))
    }
}

// MARK: - Sound

struct SoundSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    private var availableSounds: [String] {
        NotificationSoundService.availableSounds()
    }

    var body: some View {
        Form {
            Section(lang.t("settings.sound.notifications")) {
                Toggle(lang.t("settings.sound.mute"), isOn: Binding(
                    get: { model.isSoundMuted },
                    set: { _ in model.toggleSoundMuted() }
                ))
            }

            Section(lang.t("settings.sound.selectSound")) {
                List(availableSounds, id: \.self) { name in
                    Button {
                        model.selectedSoundName = name
                        NotificationSoundService.play(name)
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if name == model.selectedSoundName {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.sound"))
    }
}

// MARK: - About

struct AboutSettingsPane: View {
    var model: AppModel

    @Environment(\.themePalette) private var palette
    private var lang: LanguageManager { model.lang }
    private var primaryInk: Color { palette.text.swiftUIColor.opacity(0.94) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)

                Text(lang.t("app.name"))
                    .font(.title.bold())

                Text(lang.t("app.description"))
                    .foregroundStyle(.secondary)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text(lang.t("settings.about.version", version))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            Form {
                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.checkForUpdates"),
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: primaryInk,
                        action: {
                            model.updateChecker.checkForUpdates()
                        }
                    )
                    .disabled(!model.updateChecker.canCheckForUpdates)
                    .opacity(model.updateChecker.canCheckForUpdates ? 1 : 0.55)
                    .accessibilityIdentifier("settings.about.checkForUpdates")
                }

                Section {
                    aboutActionRow(
                        title: lang.t("settings.about.quitApp"),
                        systemImage: "rectangle.portrait.and.arrow.right",
                        tint: palette.role(.danger).swiftUIColor,
                        action: {
                            model.quitApplication()
                        }
                    )
                    .accessibilityIdentifier("settings.about.quitApp")
                }
            }
            .formStyle(.grouped)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t("settings.tab.about"))
    }

    private func aboutActionRow(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18, alignment: .leading)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))

                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Setup

struct SetupSettingsPane: View {
    var model: AppModel

    @Environment(\.themePalette) private var palette
    @State private var confirmingUninstallClaude = false
    @State private var confirmingUninstallCodex = false
    @State private var confirmingUninstallOpenCode = false
    @State private var confirmingUninstallQoder = false
    @State private var confirmingUninstallQwenCode = false
    @State private var confirmingUninstallFactory = false
    @State private var confirmingUninstallCodebuddy = false
    @State private var confirmingUninstallCursor = false
    @State private var confirmingUninstallGemini = false
    @State private var confirmingUninstallKimi = false
    @State private var confirmingUninstallClaudeUsage = false

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            creatorQuickStartSection

            if !model.hasAnyInstalledAgent {
                emptyStateBanner
            }

            claudeConfigDirectorySection

            Section(lang.t("setup.section.hooks")) {
                hookRow(
                    name: "Claude Code",
                    installed: model.claudeHooksInstalled,
                    busy: model.isClaudeHookSetupBusy,
                    configLocationURL: model.claudeHookStatus?.settingsURL,
                    installAction: { model.installClaudeHooks() },
                    uninstallAction: { confirmingUninstallClaude = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaude) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claude"))
                }

                hookRow(
                    name: "Codex",
                    installed: model.codexHooksInstalled,
                    busy: model.isCodexSetupBusy,
                    configLocationURL: codexHookConfigURL,
                    installAction: { model.installCodexHooks() },
                    uninstallAction: { confirmingUninstallCodex = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodex) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodexHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.codex"))
                }

                hookRow(
                    name: "OpenCode",
                    installed: model.openCodePluginInstalled,
                    busy: model.isOpenCodeSetupBusy,
                    requiresBinary: false,
                    configLocationURL: model.openCodePluginStatus?.configURL,
                    installAction: { model.installOpenCodePlugin() },
                    uninstallAction: { confirmingUninstallOpenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallOpenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallOpenCodePlugin()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the Open Island plugin from ~/.config/opencode/plugins/.")
                }

                hookRow(
                    name: "Qoder",
                    installed: model.qoderHooksInstalled,
                    busy: model.isQoderHookSetupBusy,
                    configLocationURL: model.qoderHookStatus?.settingsURL,
                    installAction: { model.installQoderHooks() },
                    uninstallAction: { confirmingUninstallQoder = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQoder) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQoderHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.qoder/settings.json.")
                }

                hookRow(
                    name: "Qwen Code",
                    installed: model.qwenCodeHooksInstalled,
                    busy: model.isQwenCodeHookSetupBusy,
                    configLocationURL: model.qwenCodeHookStatus?.settingsURL,
                    installAction: { model.installQwenCodeHooks() },
                    uninstallAction: { confirmingUninstallQwenCode = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallQwenCode) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallQwenCodeHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.qwen/settings.json.")
                }

                hookRow(
                    name: "Factory",
                    installed: model.factoryHooksInstalled,
                    busy: model.isFactoryHookSetupBusy,
                    configLocationURL: model.factoryHookStatus?.settingsURL,
                    installAction: { model.installFactoryHooks() },
                    uninstallAction: { confirmingUninstallFactory = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallFactory) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallFactoryHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.factory/settings.json.")
                }

                hookRow(
                    name: "CodeBuddy",
                    installed: model.codebuddyHooksInstalled,
                    busy: model.isCodebuddyHookSetupBusy,
                    configLocationURL: model.codebuddyHookStatus?.settingsURL,
                    installAction: { model.installCodebuddyHooks() },
                    uninstallAction: { confirmingUninstallCodebuddy = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCodebuddy) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCodebuddyHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.codebuddy/settings.json.")
                }

                hookRow(
                    name: "Cursor",
                    installed: model.cursorHooksInstalled,
                    busy: model.isCursorHookSetupBusy,
                    requiresBinary: true,
                    configLocationURL: model.cursorHookStatus?.hooksURL,
                    installAction: { model.installCursorHooks() },
                    uninstallAction: { confirmingUninstallCursor = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallCursor) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallCursorHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove the Open Island hooks from ~/.cursor/hooks.json.")
                }

                hookRow(
                    name: "Gemini CLI",
                    installed: model.geminiHooksInstalled,
                    busy: model.isGeminiHookSetupBusy,
                    configLocationURL: geminiHookConfigURL,
                    installAction: { model.installGeminiHooks() },
                    uninstallAction: { confirmingUninstallGemini = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallGemini) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallGeminiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.gemini/settings.json.")
                }

                hookRow(
                    name: "Kimi CLI",
                    installed: model.kimiHooksInstalled,
                    busy: model.isKimiHookSetupBusy,
                    configLocationURL: model.kimiHookStatus?.configURL,
                    installAction: { model.installKimiHooks() },
                    uninstallAction: { confirmingUninstallKimi = true }
                )
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallKimi) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallKimiHooks()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text("This will remove Open Island hooks from ~/.kimi/config.toml.")
                }
            }

            Section {
                HStack {
                    Label(lang.t("setup.usageBridge"), systemImage: "chart.bar")
                    Spacer()
                    if model.claudeUsageInstalled {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(lang.t("setup.usageBridgeReady"))
                                .foregroundStyle(.secondary)
                        }
                        Button(lang.t("settings.general.uninstall")) {
                            confirmingUninstallClaudeUsage = true
                        }
                    } else if model.isClaudeUsageSetupBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(lang.t("settings.general.install")) {
                            model.installClaudeUsageBridge()
                        }
                    }
                }
                .alert(lang.t("settings.general.uninstallConfirmTitle"), isPresented: $confirmingUninstallClaudeUsage) {
                    Button(lang.t("settings.general.uninstallConfirmAction"), role: .destructive) {
                        model.uninstallClaudeUsageBridge()
                    }
                    Button(lang.t("settings.general.cancel"), role: .cancel) {}
                } message: {
                    Text(lang.t("settings.general.uninstallConfirmMessage.claudeUsage"))
                }

                Toggle(lang.t("settings.general.showCodexUsage"), isOn: Binding(
                    get: { model.showCodexUsage },
                    set: { model.showCodexUsage = $0 }
                ))
            } header: {
                HStack(spacing: 4) {
                    Text(lang.t("setup.section.usage"))
                    Text(lang.t("setup.optional"))
                        .foregroundStyle(.tertiary)
                }
            }

            Section(lang.t("setup.section.permissions")) {
                HStack(alignment: .top) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lang.t("setup.permissionsTitle"))
                            Text(lang.t("setup.permissionsDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.shield")
                    }
                    Spacer()
                }
            }

            hookDiagnosticsSection

            RemoteConnectionSection(model: model)

            Section {
                Button(lang.t("setup.installAll")) {
                    if !model.claudeHooksInstalled { model.installClaudeHooks() }
                    if !model.codexHooksInstalled { model.installCodexHooks() }
                    if !model.openCodePluginInstalled { model.installOpenCodePlugin() }
                    if !model.qoderHooksInstalled { model.installQoderHooks() }
                    if !model.qwenCodeHooksInstalled { model.installQwenCodeHooks() }
                    if !model.factoryHooksInstalled { model.installFactoryHooks() }
                    if !model.codebuddyHooksInstalled { model.installCodebuddyHooks() }
                    if !model.cursorHooksInstalled { model.installCursorHooks() }
                    if !model.geminiHooksInstalled { model.installGeminiHooks() }
                    if !model.kimiHooksInstalled { model.installKimiHooks() }
                    if !model.claudeUsageInstalled { model.installClaudeUsageBridge() }
                }
                .disabled(model.hooksBinaryURL == nil || allReady)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.setup"))
    }

    @ViewBuilder
    private var claudeConfigDirectorySection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.t("setup.claudeConfigDir.title"))
                        Text(ClaudeConfigDirectory.resolved().path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: "folder")
                }
                Spacer()
                if ClaudeConfigDirectory.customDirectory != nil {
                    Button(lang.t("setup.claudeConfigDir.reset")) {
                        model.updateClaudeConfigDirectory(to: nil)
                    }
                    .font(.caption)
                }
                Button(lang.t("setup.claudeConfigDir.choose")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    panel.showsHiddenFiles = true
                    panel.prompt = lang.t("setup.claudeConfigDir.choose")
                    if panel.runModal() == .OK, let url = panel.url {
                        model.updateClaudeConfigDirectory(to: url)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.claudeConfigDir.section"))
                Text(lang.t("setup.optional"))
                    .foregroundStyle(.tertiary)
            }
        } footer: {
            Text(lang.t("setup.claudeConfigDir.footer"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var allReady: Bool {
        model.claudeHooksInstalled && model.codexHooksInstalled && model.openCodePluginInstalled
            && model.qoderHooksInstalled && model.qwenCodeHooksInstalled && model.factoryHooksInstalled && model.codebuddyHooksInstalled
            && model.cursorHooksInstalled && model.geminiHooksInstalled && model.kimiHooksInstalled && model.claudeUsageInstalled
    }

    @ViewBuilder
    private var creatorQuickStartSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(palette.role(.working).swiftUIColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.t("setup.creator.title"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(lang.t("setup.creator.message"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(lang.t(
                        "setup.creator.progress",
                        model.creatorQuickStartCompletedCount,
                        model.creatorQuickStartTotalCount
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.creatorQuickStartSteps) { step in
                        creatorQuickStartStepRow(step)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        creatorQuickStartActions
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        creatorQuickStartActions
                    }
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        } header: {
            Text(lang.t("setup.section.creator"))
        } footer: {
            Text(lang.t("setup.creator.footer"))
        }
    }

    @ViewBuilder
    private var creatorQuickStartActions: some View {
        Button {
            model.applyCreatorStreamingDefaults()
        } label: {
            Label(lang.t("setup.creator.apply"), systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)

        Button {
            model.copyStreamOverlayURLToPasteboard()
        } label: {
            Label(lang.t("setup.creator.copyOverlayURL"), systemImage: "link")
        }
        .buttonStyle(.bordered)

        Button {
            model.copyCreatorAutomationActionURLs()
        } label: {
            Label(lang.t("setup.creator.copyActions"), systemImage: "keyboard")
        }
        .buttonStyle(.bordered)

        if !model.firstLaunchCompleted {
            Button {
                model.completeCreatorOnboarding()
            } label: {
                Label(lang.t("setup.creator.finish"), systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func creatorQuickStartStepRow(_ step: AppModel.CreatorQuickStartStep) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: step.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(step.isComplete ? .green : .secondary)
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t("setup.creator.step.\(step.id).title"))
                    .font(.system(size: 12, weight: .medium))
                Text(lang.t("setup.creator.step.\(step.id).detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text(step.isComplete ? lang.t("setup.creator.ready") : lang.t("setup.creator.pending"))
                .font(.caption)
                .foregroundStyle(step.isComplete ? .green : .secondary)
        }
    }

    @ViewBuilder
    private var emptyStateBanner: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("setup.banner.noHooks.title"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(lang.t("setup.banner.noHooks.message"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var codexHookConfigURL: URL? {
        if let hooksURL = model.codexHookStatus?.hooksURL, FileManager.default.fileExists(atPath: hooksURL.path) {
            return hooksURL
        }
        return model.codexHookStatus?.configURL ?? model.codexHookStatus?.hooksURL
    }

    private var geminiHookConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/settings.json")
    }

    private var hasErrors: Bool {
        let claudeErrors = model.claudeHealthReport?.errors.count ?? 0
        let codexErrors = model.codexHealthReport?.errors.count ?? 0
        return claudeErrors + codexErrors > 0
    }

    private var hasRepairableIssues: Bool {
        let claude = model.claudeHealthReport?.repairableIssues.isEmpty == false
        let codex = model.codexHealthReport?.repairableIssues.isEmpty == false
        return claude || codex
    }

    private var hasNotices: Bool {
        let claude = model.claudeHealthReport?.notices.isEmpty == false
        let codex = model.codexHealthReport?.notices.isEmpty == false
        return claude || codex
    }

    @ViewBuilder
    private var hookDiagnosticsSection: some View {
        Section {
            if let claudeReport = model.claudeHealthReport, !claudeReport.issues.isEmpty {
                issueList(report: claudeReport)
            }
            if let codexReport = model.codexHealthReport, !codexReport.issues.isEmpty {
                issueList(report: codexReport)
            }

            if model.claudeHealthReport == nil && model.codexHealthReport == nil {
                HStack {
                    Text(lang.t("setup.diagnostics.notRun"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(lang.t("setup.diagnostics.runCheck")) {
                        model.runHealthChecks()
                    }
                }
            } else if !hasErrors {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(lang.t("setup.diagnostics.allHealthy"))
                    Spacer()
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }
                    .font(.caption)
                }
            } else {
                HStack(spacing: 10) {
                    Button(lang.t("setup.diagnostics.recheck")) {
                        model.runHealthChecks()
                    }

                    if hasRepairableIssues {
                        Button(lang.t("setup.diagnostics.repair")) {
                            model.repairHooks()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text(lang.t("setup.section.diagnostics"))
                if hasErrors {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                }
            }
        }
    }

    @ViewBuilder
    private func issueList(report: HookHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(report.agent == "claude" ? "Claude Code" : "Codex")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: issueIcon(for: issue))
                        .font(.caption2)
                        .foregroundStyle(issueColor(for: issue))
                        .frame(width: 14)

                    Text(issue.description)
                        .font(.caption)
                        .foregroundStyle(issue.severity == .info ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let binaryPath = report.binaryPath {
                Text("Binary: \(binaryPath)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func issueIcon(for issue: HookHealthReport.Issue) -> String {
        switch issue.severity {
        case .info: "info.circle.fill"
        case .error: issue.isAutoRepairable ? "wrench.fill" : "exclamationmark.triangle.fill"
        }
    }

    private func issueColor(for issue: HookHealthReport.Issue) -> Color {
        switch issue.severity {
        case .info: palette.role(.working).swiftUIColor
        case .error: issue.isAutoRepairable ? palette.role(.attention).swiftUIColor : palette.role(.danger).swiftUIColor
        }
    }

    @ViewBuilder
    private func hookRow(
        name: String,
        installed: Bool,
        busy: Bool,
        requiresBinary: Bool = true,
        configLocationURL: URL? = nil,
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(name, systemImage: "terminal")
            Spacer()
            if installed {
                HStack(spacing: 8) {
                    if let configLocationURL {
                        Button {
                            revealInFinder(configLocationURL)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(lang.t("setup.revealConfigLocation"))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(lang.t("settings.general.activated"))
                            .foregroundStyle(.secondary)
                    }
                    Button(lang.t("settings.general.uninstall")) {
                        uninstallAction()
                    }
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            } else if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(lang.t("settings.general.install")) {
                    installAction()
                }
                .disabled(requiresBinary && model.hooksBinaryURL == nil)
            }
        }
    }

    private func revealInFinder(_ url: URL) {
        let fileManager = FileManager.default
        let standardizedURL = url.standardizedFileURL

        if fileManager.fileExists(atPath: standardizedURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([standardizedURL])
            return
        }

        let directoryURL = standardizedURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directoryURL.path) {
            NSWorkspace.shared.open(directoryURL)
        }
    }
}

// MARK: - Watch

struct WatchSettingsPane: View {
    var model: AppModel

    @State private var pairingCode: String = "----"
    @State private var burned: Bool = false
    @State private var devices: [WatchDeviceInfo] = []

    private static let lastSeenFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        Form {
            Section {
                Toggle("Watch Notifications", isOn: Binding(
                    get: { model.watchNotificationEnabled },
                    set: { model.watchNotificationEnabled = $0 }
                ))

                if model.watchNotificationEnabled {
                    Text("When enabled, Atoll listens locally so a paired iPhone can deliver permission decisions and answer questions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("General")
            }

            if model.watchNotificationEnabled {
                Section("Network") {
                    Toggle("Advertise on local network", isOn: Binding(
                        get: { model.watchLANAdvertiseEnabled },
                        set: { model.watchLANAdvertiseEnabled = $0 }
                    ))

                    Text("Off (default): Atoll binds only to 127.0.0.1; pairing requires the iPhone to reach this Mac via a port-forward. On: Atoll binds all interfaces and broadcasts on Bonjour to your local network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if model.watchLANAdvertiseEnabled {
                        Toggle("Show machine name in Bonjour ad", isOn: Binding(
                            get: { model.watchBonjourShowMachineName },
                            set: { model.watchBonjourShowMachineName = $0 }
                        ))
                        Text("Off (default): the service is advertised as \"Atoll\" only. On: appends your Mac's name so multiple Atoll machines on the same network can be told apart.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Pairing") {
                    HStack {
                        Text("Pairing Code")
                        Spacer()
                        Text(pairingCode)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(burned ? .red : .blue)
                    }

                    if burned {
                        Label("Code burned — regenerate from Settings", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    } else {
                        Text("Enter this code on your iPhone app to pair. Code expires after 2 minutes; after 5 wrong attempts it is burned and you must regenerate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Refresh Code") {
                        model.watchRelay?.endpoint.regeneratePairingCode()
                        refresh()
                    }
                }

                Section("Paired Devices") {
                    if devices.isEmpty {
                        HStack {
                            Label("No devices paired", systemImage: "iphone.slash")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(devices, id: \.token) { device in
                            HStack {
                                Label(device.label, systemImage: "iphone")
                                Spacer()
                                Text("last seen " + Self.lastSeenFormatter.localizedString(for: device.lastSeen, relativeTo: Date()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(role: .destructive) {
                                    model.watchRelay?.endpoint.revoke(token: device.token)
                                    refresh()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Button("Revoke All Pairings", role: .destructive) {
                        model.watchRelay?.endpoint.revokeAllTokens()
                        refresh()
                    }
                }

                Section("About") {
                    Text("Tokens persist in-memory only — restarting Atoll forgets every paired device, and idle devices are dropped after 30 days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Watch")
        .onAppear { refresh() }
    }

    private func refresh() {
        pairingCode = model.watchPairingCode
        burned = model.watchPairingCodeBurned
        devices = model.watchPairedDevices.sorted { $0.issuedAt > $1.issuedAt }
    }
}

// MARK: - Placeholder

struct PlaceholderSettingsPane: View {
    var model: AppModel
    let titleKey: String
    let subtitleKey: String

    private var lang: LanguageManager { model.lang }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(lang.t(subtitleKey))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(lang.t(titleKey))
    }
}

// MARK: - Remote Connection

struct RemoteConnectionSection: View {
    var model: AppModel

    @Environment(\.themePalette) private var palette
    @State private var copiedCommand: String?

    private var remoteSessionCount: Int {
        model.state.sessions.filter(\.isRemote).count
    }

    private var socketName: String {
        "open-island-\(getuid()).sock"
    }

    private var setupCommand: String {
        "./scripts/remote-setup.sh user@host"
    }

    private var sshCommand: String {
        "ssh -R /tmp/\(socketName):/tmp/\(socketName) user@host"
    }

    private var sshConfigSnippet: String {
        """
        Host myserver
            RemoteForward /tmp/\(socketName) /tmp/\(socketName)
        """
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Status
                HStack {
                    Label("SSH Remote", systemImage: "network")
                    Spacer()
                    if remoteSessionCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 7, height: 7)
                            Text("\(remoteSessionCount) active")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No remote sessions")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text("Monitor Claude Code running on remote servers via SSH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Step 1
                remoteSetupStep(
                    number: "1",
                    title: "Deploy hooks to remote server",
                    description: "Run from the Open Island repo directory:",
                    command: setupCommand
                )

                // Step 2
                remoteSetupStep(
                    number: "2",
                    title: "Connect with socket forwarding",
                    description: "Add to ~/.ssh/config (recommended):",
                    command: sshConfigSnippet,
                    multiline: true
                )

                // Step 2 alternative
                VStack(alignment: .leading, spacing: 4) {
                    Text("Or connect directly:")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    copyableCommand(sshCommand)
                }

                // Tip
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.role(.working).swiftUIColor.opacity(0.8))
                        .padding(.top, 1)
                    Text("The remote sshd needs `StreamLocalBindUnlink yes` in /etc/ssh/sshd_config for reliable reconnects.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("Remote")
                Text("Beta")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func remoteSetupStep(
        number: String,
        title: String,
        description: String,
        command: String,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(number)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(palette.role(.working).swiftUIColor.opacity(0.7)))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            Text(description)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            copyableCommand(command, multiline: multiline)
        }
    }

    @ViewBuilder
    private func copyableCommand(_ command: String, multiline: Bool = false) -> some View {
        let isCopied = copiedCommand == command
        GroupBox {
            HStack(alignment: multiline ? .top : .center) {
                Text(command)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(multiline ? nil : 1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copiedCommand = command
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedCommand == command {
                            copiedCommand = nil
                        }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, multiline ? 2 : 0)
        }
    }
}

// MARK: - Update Card

struct UpdateCard: View {
    var updateChecker: UpdateChecker
    let lang: LanguageManager

    @Environment(\.themePalette) private var palette
    @State private var isExpanded = false

    private var versionLabel: String {
        if let name = updateChecker.latestReleaseName, !name.isEmpty {
            return name
        }
        if let version = updateChecker.latestVersion {
            return lang.t("settings.update.available", version)
        }
        return lang.t("settings.update.available", "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                changelogSection
                actionRow
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(palette.surface0.swiftUIColor)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .frame(maxWidth: 340)
    }

    // MARK: Private

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.role(.working).swiftUIColor)
            Text(versionLabel)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Text(lang.t("settings.update.whatsNew"))
                        .font(.system(size: 11))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var changelogSection: some View {
        ScrollView {
            Group {
                if let notes = updateChecker.latestReleaseNotes, !notes.isEmpty {
                    Markdown(notes)
                        .markdownTextStyle { FontSize(12) }
                } else {
                    let fallbackURL = updateChecker.latestReleaseURL?.absoluteString
                        ?? UpdateChecker.releasesURL.absoluteString
                    Markdown(
                        """
                        \(lang.t("settings.update.notesUnavailable"))

                        [\(lang.t("settings.update.viewOnGitHub"))](\(fallbackURL))
                        """
                    )
                    .markdownTextStyle { FontSize(12) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .frame(maxHeight: 280)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(
                updateChecker.sparkleUpdateAvailable
                    ? lang.t("settings.update.updateNow")
                    : lang.t("settings.update.downloadNow")
            ) {
                if updateChecker.sparkleUpdateAvailable {
                    updateChecker.checkForUpdates()
                } else {
                    NSWorkspace.shared.open(
                        updateChecker.latestReleaseURL ?? UpdateChecker.releasesURL
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(palette.role(.working).swiftUIColor)

            Button(lang.t("settings.update.viewOnGitHub")) {
                NSWorkspace.shared.open(
                    updateChecker.latestReleaseURL ?? UpdateChecker.releasesURL
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button(lang.t("settings.update.later")) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}
