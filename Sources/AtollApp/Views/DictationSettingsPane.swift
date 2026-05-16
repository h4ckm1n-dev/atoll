// DictationSettingsPane.swift
// AtollApp

import SwiftUI
import AtollCore

// MARK: - DictationModelOption

private struct DictationModelOption: Identifiable {
    let id: String          // WhisperKit model identifier
    let display: String     // Short display name shown in the picker
    let size: String        // Approximate download size
    let detail: String      // One-line description
}

private let dictationModelOptions: [DictationModelOption] = [
    DictationModelOption(
        id: "openai_whisper-tiny.en",
        display: "Tiny (English)",
        size: "~40 MB",
        detail: "Fastest, lowest accuracy. Default."
    ),
    DictationModelOption(
        id: "openai_whisper-base.en",
        display: "Base (English)",
        size: "~150 MB",
        detail: "Balanced speed and accuracy."
    ),
    DictationModelOption(
        id: "openai_whisper-small.en",
        display: "Small (English)",
        size: "~500 MB",
        detail: "Good accuracy for technical terms."
    ),
    DictationModelOption(
        id: "openai_whisper-large-v3-v20240930_626MB",
        display: "Large v3 (Distilled)",
        size: "~626 MB",
        detail: "Argmax compression of large-v3. Recommended."
    ),
    DictationModelOption(
        id: "openai_whisper-large-v3-turbo",
        display: "Large v3 Turbo",
        size: "~800 MB",
        detail: "Fast multilingual, near Superwhisper quality."
    ),
    DictationModelOption(
        id: "openai_whisper-large-v3",
        display: "Large v3 (Full)",
        size: "~3 GB",
        detail: "Highest accuracy, slowest. Multilingual."
    ),
]

// MARK: - DictationSettingsPane

struct DictationSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    /// The model identifier the user has chosen. This drives both the picker
    /// and the pending-status comparison. Bound directly through AppModel so
    /// the didSet handler in AppModel keeps `dictationController.config.model`
    /// in sync whenever this changes.
    @State private var selectedModelID: String = "openai_whisper-tiny.en"

    var body: some View {
        Form {
            modelPickerSection
            statusSection
            helpSection
        }
        .formStyle(.grouped)
        .navigationTitle(lang.t("settings.tab.dictation"))
        .onAppear {
            selectedModelID = model.dictationModel
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var modelPickerSection: some View {
        Section(lang.t("settings.dictation.section.model")) {
            Picker(lang.t("settings.dictation.section.model"), selection: $selectedModelID) {
                ForEach(dictationModelOptions) { option in
                    modelPickerRow(option).tag(option.id)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .onChange(of: selectedModelID) { _, newValue in
                model.dictationModel = newValue
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        let loadedID = model.dictationController.config.model
        let isPending = loadedID != selectedModelID

        Section {
            LabeledContent(lang.t("settings.dictation.loaded", displayName(for: loadedID))) {
                if isPending {
                    Text(lang.t("settings.dictation.pending"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(lang.t("settings.dictation.reload")) {
                model.reloadDictationModel()
            }
            .disabled(!isPending)
        }
    }

    @ViewBuilder
    private var helpSection: some View {
        Section {
            Text(lang.t("settings.dictation.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func modelPickerRow(_ option: DictationModelOption) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(option.display)
                    .fontWeight(.medium)
                Text(option.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(option.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func displayName(for modelID: String) -> String {
        dictationModelOptions.first { $0.id == modelID }?.display ?? modelID
    }
}
