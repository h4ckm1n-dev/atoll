// DictationController.swift
// AtollDictation

import Foundation
import Observation
// @preconcurrency: WhisperKit's transcribe(audioArray:) is `nonisolated` but
// the WhisperKit class itself isn't Sendable. Without this attribute, every
// cross-context call (actor → nonisolated method on owned reference) trips
// Swift 6 strict concurrency. The downgrade-to-warnings is the standard fix
// for pre-Swift-6 libraries.
@preconcurrency import WhisperKit

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
            return "WhisperKit failed to initialize: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

// MARK: - DictationController

/// Main entry point for voice dictation. Drives the full lifecycle:
/// microphone capture → WhisperKit transcription → `Transcription` value.
///
/// `@Observable` + `@MainActor`: state mutations are always on the main actor
/// and the Observation framework propagates changes to SwiftUI automatically.
/// The `AudioRecorder` actor handles thread-safe audio capture; we cross into
/// it with `await` from the main actor.
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
    // WhisperKit is a non-Sendable class. Wrapping it in a dedicated actor
    // keeps the reference fully isolated to that actor, so cross-context
    // method calls happen via `await host.transcribe(_:)` rather than by
    // sending the kit reference itself. This is the architecturally clean
    // Swift 6 pattern for non-Sendable framework types.
    private let host = WhisperKitHost()

    // MARK: - Init

    public init(config: DictationConfig = DictationConfig()) {
        self.config = config
    }

    // MARK: - Public API

    /// Lazily initializes WhisperKit (model download happens here on first call).
    /// Subsequent calls are no-ops once initialization succeeds.
    public func prepare() async throws {
        if await host.isReady { return }
        state = .preparing
        do {
            try await host.prepare(model: config.model)
            // Return to idle so callers know we're ready.
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

        if await !host.isReady {
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
            let (text, language) = try await host.transcribe(audioArray: buffer)

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

    /// Resets state to `.idle` without touching the recorder or WhisperKit host.
    /// Call this to clear a terminal `.failed` or `.completed` state before
    /// starting a fresh recording cycle.
    public func reset() {
        state = .idle
    }

    /// Invalidates the cached WhisperKit instance. The next call to
    /// `startRecording()` will re-prepare with the current `config.model`,
    /// downloading the model if it has not been fetched before.
    /// Safe to call from outside an active recording; calling while recording
    /// is in progress leaves the session running — invalidation takes effect
    /// on the next `startRecording()`.
    public func invalidate() async {
        await host.invalidate()
        if case .completed = state { state = .idle }
        if case .failed = state { state = .idle }
    }
}

// MARK: - WhisperKitHost

/// Actor owning the WhisperKit instance. Isolating the non-Sendable WhisperKit
/// reference inside an actor means all cross-context calls go through actor
/// hops (`await host.transcribe(...)`) rather than by sending the reference.
private actor WhisperKitHost {
    private var kit: WhisperKit?

    var isReady: Bool { kit != nil }

    func prepare(model: String) async throws {
        guard kit == nil else { return }
        kit = try await WhisperKit(WhisperKitConfig(model: model))
    }

    func invalidate() {
        kit = nil
    }

    /// Transcribes the buffer. Returns the joined text and the detected
    /// language. Returns ("", nil) for silence — not an error.
    func transcribe(audioArray buffer: [Float]) async throws -> (text: String, language: String?) {
        guard let kit else {
            throw DictationError.whisperKitInitFailed("WhisperKit was deallocated unexpectedly.")
        }
        let results = try await kit.transcribe(audioArray: buffer)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let language = results.first?.language
        return (text, language)
    }
}
