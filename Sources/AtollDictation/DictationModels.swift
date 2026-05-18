// DictationModels.swift
// AtollDictation

import Foundation

// MARK: - DictationState

public enum DictationState: Equatable, Sendable {
    case idle
    case preparing
    case recording(startedAt: Date)
    case transcribing
    case completed(Transcription)
    case failed(String)
}

// MARK: - Transcription

public struct Transcription: Equatable, Sendable, Codable {
    public let text: String
    public let durationSeconds: Double
    public let language: String?

    public init(text: String, durationSeconds: Double, language: String?) {
        self.text = text
        self.durationSeconds = durationSeconds
        self.language = language
    }
}

// MARK: - DictationConfig

public struct DictationConfig: Sendable, Codable {
    /// Transcription engine model identifier. Prefix determines the backend:
    /// - `parakeet-*` → ParakeetEngine (FluidAudio / Apple Neural Engine)
    /// - `openai_whisper-*` → WhisperKitEngine
    /// Defaults to Parakeet TDT v3 multilingual (~610 MB, first-launch download).
    public var model: String

    /// Maximum recording duration. Hard cap to prevent runaway captures.
    public var maxRecordingSeconds: TimeInterval

    /// Sample rate for audio capture. Both Whisper and Parakeet expect 16 kHz mono Float32.
    public let sampleRate: Double

    public init(
        model: String = "parakeet-tdt-0.6b-v3",
        maxRecordingSeconds: TimeInterval = 60,
        sampleRate: Double = 16_000
    ) {
        self.model = model
        self.maxRecordingSeconds = maxRecordingSeconds
        self.sampleRate = sampleRate
    }
}
