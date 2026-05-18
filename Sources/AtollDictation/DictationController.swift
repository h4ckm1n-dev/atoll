// DictationController.swift
// AtollDictation

import Foundation
import Observation

// MARK: - DictationError

public enum DictationError: Error, LocalizedError, Sendable {
    case alreadyRecording
    case notRecording
    case whisperKitInitFailed(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording session is already in progress."
        case .notRecording:
            return "No recording is in progress."
        case .whisperKitInitFailed(let reason):
            return "Engine failed to initialize: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

// MARK: - DictationController

/// Main entry point for voice dictation. Drives the full lifecycle:
/// microphone capture → transcription engine → `Transcription` value.
///
/// `@Observable` + `@MainActor`: state mutations are always on the main actor
/// and the Observation framework propagates changes to SwiftUI automatically.
/// The `AudioRecorder` actor handles thread-safe audio capture; we cross into
/// it with `await` from the main actor.
///
/// The active transcription engine is selected by `config.model`:
/// - Identifiers prefixed with `parakeet-` route to `ParakeetEngine` (FluidAudio / ANE).
/// - All other identifiers route to `WhisperKitEngine`.
@MainActor
@Observable
public final class DictationController {
    // MARK: - Observable state

    public private(set) var state: DictationState = .idle
    public private(set) var lastTranscription: Transcription?

    // MARK: - Configuration

    public var config: DictationConfig

    // MARK: - Private

    private let recorder = AudioRecorder()

    // One engine instance per backend. Engines hold their model weights lazily
    // so only the selected engine ever downloads anything.
    private let whisperEngine: any TranscriptionEngine = WhisperKitEngine()
    private let parakeetEngine: any TranscriptionEngine = ParakeetEngine()

    // MARK: - Init

    public init(config: DictationConfig = DictationConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// Lazily initializes the selected engine (model download happens here on
    /// first call). Subsequent calls are no-ops once initialization succeeds.
    public func prepare() async throws {
        let activeEngine = engine(for: config.model)
        if await activeEngine.isReady() { return }
        state = .preparing
        do {
            try await activeEngine.prepare(modelID: config.model)
            if case .preparing = state { state = .idle }
        } catch {
            let message = error.localizedDescription
            state = .failed(message)
            throw DictationError.whisperKitInitFailed(message)
        }
    }

    /// Begins microphone capture. Transitions: idle → preparing (if needed) → recording.
    /// Idempotent: calling while already recording is a no-op.
    public func startRecording() async throws {
        guard case .idle = state else {
            if case .recording = state { return }
            return
        }

        let activeEngine = engine(for: config.model)
        if await !activeEngine.isReady() {
            try await prepare()
        }

        do {
            try await recorder.start()
        } catch {
            let message = error.localizedDescription
            state = .failed(message)
            throw error
        }

        state = .recording(startedAt: Date())
    }

    /// Stops recording and transcribes the captured audio.
    /// Transitions: recording → transcribing → completed (or failed).
    @discardableResult
    public func stopAndTranscribe() async throws -> Transcription {
        guard case .recording(let startedAt) = state else {
            throw DictationError.notRecording
        }

        let durationSeconds = Date().timeIntervalSince(startedAt)
        state = .transcribing

        let buffer = await recorder.stop()

        do {
            let activeEngine = engine(for: config.model)
            let (text, language) = try await activeEngine.transcribe(audioArray: buffer)

            let transcription = Transcription(
                text: text,
                durationSeconds: durationSeconds,
                language: language
            )
            lastTranscription = transcription
            state = .completed(transcription)
            return transcription
        } catch {
            let message = error.localizedDescription
            state = .failed(message)
            throw DictationError.transcriptionFailed(message)
        }
    }

    /// Cancels an in-flight recording without transcribing. Returns state to `.idle`.
    public func cancel() async {
        _ = await recorder.stop()
        state = .idle
    }

    /// Resets state to `.idle` without touching the recorder or engines.
    /// Call this to clear a terminal `.failed` or `.completed` state before
    /// starting a fresh recording cycle.
    public func reset() {
        state = .idle
    }

    /// Invalidates the cached model in the currently-selected engine. The next
    /// call to `startRecording()` will re-prepare with the current `config.model`,
    /// downloading the model if it has not been fetched before.
    /// Safe to call from outside an active recording; calling while recording
    /// is in progress leaves the session running — invalidation takes effect
    /// on the next `startRecording()`.
    public func invalidate() async {
        await engine(for: config.model).invalidate()
        if case .completed = state { state = .idle }
        if case .failed = state { state = .idle }
    }

    // MARK: - Private helpers

    private func engine(for modelID: String) -> any TranscriptionEngine {
        switch TranscriptionEngineKind.forModel(modelID) {
        case .parakeet:
            return parakeetEngine
        case .whisper:
            return whisperEngine
        }
    }
}
