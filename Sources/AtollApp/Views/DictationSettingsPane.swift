// DictationSettingsPane.swift
// AtollApp

import SwiftUI
import AtollCore

// MARK: - DictationModelOption

private struct DictationModelOption: Identifiable {
    let id: String          // Engine model identifier
    let display: String     // Short display name shown in the picker
    let size: String        // Approximate download size
    let detail: String      // One-line description
}

/// Parakeet TDT models (FluidAudio / Apple Neural Engine).
private let parakeetModelOptions: [DictationModelOption] = [
    DictationModelOption(
        id: "parakeet-tdt-0.6b-v3",
        display: "Parakeet TDT v3 (Multilingual)",
        size: "~610 MB",
        detail: "25 European languages, NVIDIA Parakeet on Apple Neural Engine. Default, recommended."
    ),
    DictationModelOption(
        id: "parakeet-tdt-0.6b-v2",
        display: "Parakeet TDT v2 (English)",
        size: "~480 MB",
        detail: "English-only, slightly smaller and faster."
    ),
]

/// OpenAI Whisper models (WhisperKit).
private let whisperModelOptions: [DictationModelOption] = [
    DictationModelOption(
        id: "openai_whisper-tiny.en",
        display: "Whisper Tiny (English)",
        size: "~40 MB",
        detail: "Smallest download, lowest accuracy."
    ),
    DictationModelOption(
        id: "openai_whisper-base.en",
        display: "Whisper Base (English)",
        size: "~150 MB",
        detail: "Balanced speed and accuracy."
    ),
    DictationModelOption(
        id: "openai_whisper-small.en",
        display: "Whisper Small (English)",
        size: "~500 MB",
        detail: "Good accuracy for technical terms."
    ),
    DictationModelOption(
        id: "openai_whisper-large-v3-v20240930_626MB",
        display: "Whisper Large v3 (Distilled)",
        size: "~626 MB",
        detail: "Argmax compression of large-v3. Recommended."
    ),
    DictationModelOption(
        id: "openai_whisper-large-v3-turbo",
        display: "Whisper Large v3 Turbo",
        size: "~800 MB",
        detail: "Fast multilingual, near Superwhisper quality."
    ),
    DictationModelOption(
        id: "openai_whisper-large-v3",
        display: "Whisper Large v3 (Full)",
        size: "~3 GB",
        detail: "Highest Whisper accuracy, slowest. Multilingual."
    ),
]

/// All options in display order: Parakeet first, Whisper second.
private let allDictationModelOptions: [DictationModelOption] =
    parakeetModelOptions + whisperModelOptions

// MARK: - DictationSettingsPane

struct DictationSettingsPane: View {
    var model: AppModel

    private var lang: LanguageManager { model.lang }

    /// The model identifier the user has chosen. Bound directly through AppModel so
    /// the didSet handler in AppModel keeps `dictationController.config.model`
    /// in sync whenever this changes.
    @State private var selectedModelID: String = "parakeet-tdt-0.6b-v3"

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
                // Parakeet group
                Text("Parakeet — Apple Neural Engine")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tag("__section_parakeet__")
                    .disabled(true)

                ForEach(parakeetModelOptions) { option in
                    modelPickerRow(option).tag(option.id)
                }

                Divider()

                // Whisper group
                Text("Whisper — WhisperKit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .tag("__section_whisper__")
                    .disabled(true)

                ForEach(whisperModelOptions) { option in
                    modelPickerRow(option).tag(option.id)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .onChange(of: selectedModelID) { _, newValue in
                // Section header tags are not valid model IDs — ignore them.
                guard !newValue.hasPrefix("__section_") else { return }
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
        allDictationModelOptions.first { $0.id == modelID }?.display ?? modelID
    }
}
