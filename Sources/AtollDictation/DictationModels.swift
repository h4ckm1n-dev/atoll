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
    /// WhisperKit model identifier. Defaults to the tiny English-only model
    /// (~40 MB) for fast first-launch UX.
    public var model: String

    /// Maximum recording duration. Hard cap to prevent runaway captures.
    public var maxRecordingSeconds: TimeInterval

    /// Sample rate for audio capture. Whisper expects 16 kHz mono Float32.
    public let sampleRate: Double

    public init(
        model: String = "openai_whisper-tiny.en",
        maxRecordingSeconds: TimeInterval = 60,
        sampleRate: Double = 16_000
    ) {
        self.model = model
        self.maxRecordingSeconds = maxRecordingSeconds
        self.sampleRate = sampleRate
    }
}
