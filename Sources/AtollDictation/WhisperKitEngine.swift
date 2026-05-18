// WhisperKitEngine.swift
// AtollDictation

// @preconcurrency: WhisperKit's types are not Sendable. Isolating the instance
// inside an actor means cross-context calls happen via `await`, not by sending
// the reference. The @preconcurrency import downgrades the resulting concurrency
// warnings to errors-as-warnings for pre-Swift-6 library code.
@preconcurrency import WhisperKit

// MARK: - WhisperKitEngine

/// `TranscriptionEngine` implementation backed by WhisperKit (OpenAI Whisper).
///
/// Owns the non-Sendable `WhisperKit` instance inside an actor so every
/// cross-context call goes through an actor hop. The `WhisperKit` reference
/// is never sent across actor boundaries.
actor WhisperKitEngine: TranscriptionEngine {
    private var kit: WhisperKit?
    private var loadedModelID: String?

    func isReady() async -> Bool { kit != nil }

    func prepare(modelID: String) async throws {
        if loadedModelID == modelID, kit != nil { return }
        // Different model → drop previous instance before loading new weights.
        kit = nil
        loadedModelID = nil

        kit = try await WhisperKit(WhisperKitConfig(model: modelID))
        loadedModelID = modelID
    }

    func transcribe(audioArray: [Float]) async throws -> (text: String, language: String?) {
        guard let kit else {
            throw DictationError.whisperKitInitFailed("WhisperKit was deallocated unexpectedly.")
        }
        let results = try await kit.transcribe(audioArray: audioArray)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let language = results.first?.language
        return (text, language)
    }

    func invalidate() async {
        kit = nil
        loadedModelID = nil
    }
}
