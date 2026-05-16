import KeyboardShortcuts
import SwiftUI
import AtollCore

struct ShortcutsSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    var body: some View {
        Form {
            Section(lang.t("settings.shortcuts.section.actions")) {
                shortcutRow(
                    titleKey: "settings.shortcuts.toggleOverlay",
                    helpKey: "settings.shortcuts.toggleOverlay.help",
                    name: .toggleOverlay
                )
                shortcutRow(
                    titleKey: "settings.shortcuts.jumpToFocusedSession",
                    helpKey: "settings.shortcuts.jumpToFocusedSession.help",
                    name: .jumpToFocusedSession
                )
                shortcutRow(
                    titleKey: "settings.shortcuts.approveFocusedPermission",
                    helpKey: "settings.shortcuts.approveFocusedPermission.help",
                    name: .approveFocusedPermission
                )
                shortcutRow(
                    titleKey: "settings.shortcuts.denyFocusedPermission",
                    helpKey: "settings.shortcuts.denyFocusedPermission.help",
                    name: .denyFocusedPermission
                )
                shortcutRow(
                    titleKey: "settings.shortcuts.cycleToNextAttentionSession",
                    helpKey: "settings.shortcuts.cycleToNextAttentionSession.help",
                    name: .cycleToNextAttentionSession
                )
                shortcutRow(
                    titleKey: "settings.shortcuts.toggleDictation",
                    helpKey: "settings.shortcuts.toggleDictation.help",
                    name: .toggleDictation
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.shortcuts"))
    }

    @ViewBuilder
    private func shortcutRow(
        titleKey: String,
        helpKey: String,
        name: KeyboardShortcuts.Name
    ) -> some View {
        LabeledContent {
            KeyboardShortcuts.Recorder("", name: name)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t(titleKey))
                Text(lang.t(helpKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
