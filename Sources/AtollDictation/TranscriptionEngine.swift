// TranscriptionEngine.swift
// AtollDictation

/// Pluggable speech-to-text backend. Both Whisper and Parakeet implementations
/// expose the same surface so DictationController can swap between them based
/// on the currently-selected model identifier.
public protocol TranscriptionEngine: Sendable {
    /// Whether the engine has loaded its model and is ready to transcribe.
    func isReady() async -> Bool
    /// Loads / downloads the model identified by `modelID`. Idempotent — calling
    /// twice with the same modelID is a no-op; calling with a different modelID
    /// invalidates the prior model first.
    func prepare(modelID: String) async throws
    /// Transcribes a 16 kHz mono Float32 buffer. Returns the joined transcript
    /// text and the detected language (or nil if the engine doesn't report it).
    func transcribe(audioArray: [Float]) async throws -> (text: String, language: String?)
    /// Drops any cached model so the next prepare() call re-loads.
    func invalidate() async
}

/// Maps a model identifier to the engine that handles it. Identifiers prefixed
/// with `parakeet-` go to ParakeetEngine; everything else falls through to
/// WhisperKitEngine (forward-compatible default).
public enum TranscriptionEngineKind: Sendable {
    case whisper
    case parakeet

    public static func forModel(_ modelID: String) -> TranscriptionEngineKind {
        if modelID.hasPrefix("parakeet-") {
            return .parakeet
        }
        return .whisper
    }
}
