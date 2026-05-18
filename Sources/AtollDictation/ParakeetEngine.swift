// ParakeetEngine.swift
// AtollDictation

// @preconcurrency: FluidAudio's MLModel-backed types (AsrModels, TdtDecoderState)
// hold CoreML MLMultiArray references that are not Sendable in Swift 6 strict mode.
// Isolating everything inside this actor means no value ever crosses an actor
// boundary — the @preconcurrency import suppresses the resulting warnings from
// the pre-Swift-6 CoreML/FluidAudio layer.
@preconcurrency import FluidAudio

// MARK: - ParakeetEngine

/// `TranscriptionEngine` implementation backed by NVIDIA Parakeet TDT via
/// FluidAudio running on Apple Neural Engine.
///
/// The FluidAudio `AsrManager` is an actor itself, but `TdtDecoderState` contains
/// `MLMultiArray` values that are not `Sendable`. We therefore keep both the
/// manager and decoder state private inside this actor so they never cross
/// an isolation boundary.
actor ParakeetEngine: TranscriptionEngine {
    private var manager: AsrManager?
    private var decoderState: TdtDecoderState?
    private var loadedModelID: String?

    func isReady() async -> Bool { manager != nil }

    func prepare(modelID: String) async throws {
        if loadedModelID == modelID, manager != nil { return }
        // Different model → drop previous instance before loading new weights.
        manager = nil
        decoderState = nil
        loadedModelID = nil

        let version = try Self.version(for: modelID)
        let models = try await AsrModels.downloadAndLoad(version: version)
        let newManager = AsrManager(config: .default, models: models)
        manager = newManager
        // TdtDecoderState.init(decoderLayers:) can throw if CoreML array
        // allocation fails — propagate as an engine-init failure.
        decoderState = try TdtDecoderState(decoderLayers: version.decoderLayers)
        loadedModelID = modelID
    }

    func transcribe(audioArray: [Float]) async throws -> (text: String, language: String?) {
        guard let manager, var state = decoderState else {
            throw DictationError.whisperKitInitFailed("Parakeet engine not prepared.")
        }
        // AsrManager.transcribe takes an `inout TdtDecoderState`. Because both
        // the manager and the state live inside this actor we can safely pass
        // the local copy by reference, then store the mutated state back.
        let result = try await manager.transcribe(audioArray, decoderState: &state)
        // Write the updated decoder state back so context carries across calls.
        decoderState = state
        // Parakeet TDT does not expose a per-call detected language; pass nil.
        return (result.text, nil)
    }

    func invalidate() async {
        manager = nil
        decoderState = nil
        loadedModelID = nil
    }

    // MARK: - Private helpers

    /// Maps our stable model-identifier strings to FluidAudio's `AsrModelVersion`.
    private static func version(for modelID: String) throws -> AsrModelVersion {
        switch modelID {
        case "parakeet-tdt-0.6b-v2":
            return .v2
        case "parakeet-tdt-0.6b-v3":
            return .v3
        default:
            throw DictationError.whisperKitInitFailed("Unknown Parakeet model: \(modelID)")
        }
    }
}
