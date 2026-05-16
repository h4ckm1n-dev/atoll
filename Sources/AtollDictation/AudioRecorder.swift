// AudioRecorder.swift
// AtollDictation

import AVFoundation
import Foundation

// MARK: - RecordingError

public enum RecordingError: Error, LocalizedError, Sendable {
    case permissionDenied
    case engineFailedToStart(String)
    case converterSetupFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access was denied. Grant permission in System Settings → Privacy & Security → Microphone."
        case .engineFailedToStart(let reason):
            return "Audio engine failed to start: \(reason)"
        case .converterSetupFailed:
            return "Failed to set up audio format converter for 16 kHz mono capture."
        }
    }
}

// MARK: - AudioRecorder

/// Captures microphone audio as 16 kHz mono Float32 samples suitable for
/// WhisperKit's `transcribe(audioArray:)`.
actor AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?

    private(set) var isRecording = false

    // MARK: - Public API

    /// Requests microphone permission if needed, then starts the engine.
    func start() async throws {
        guard !isRecording else { return }

        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw RecordingError.permissionDenied }

        samples.removeAll(keepingCapacity: true)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw RecordingError.converterSetupFailed
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecordingError.converterSetupFailed
        }
        converter = conv

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            // Convert synchronously on the audio thread so only Sendable [Float]
            // crosses the actor boundary. AVAudioPCMBuffer is not Sendable.
            guard let newSamples = Self.convertToTargetSamples(
                buffer: buffer,
                converter: conv,
                targetFormat: targetFormat
            ) else { return }
            Task { await self.appendSamples(newSamples) }
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            converter = nil
            throw RecordingError.engineFailedToStart(error.localizedDescription)
        }

        isRecording = true
    }

    /// Stops the engine and returns the accumulated 16 kHz mono sample buffer.
    func stop() async -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isRecording = false
        let result = samples
        samples.removeAll(keepingCapacity: false)
        return result
    }

    // MARK: - Private

    private func appendSamples(_ newSamples: [Float]) {
        samples.append(contentsOf: newSamples)
    }

    /// Synchronous converter helper invoked from the tap callback. Returns
    /// 16 kHz mono Float samples or nil on failure. Pure function — all state
    /// lives in locals so it's safe to call from any thread.
    nonisolated static func convertToTargetSamples(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> [Float]? {
        let inputFrameCount = AVAudioFrameCount(buffer.frameLength)
        let sampleRateRatio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(inputFrameCount) * sampleRateRatio + 1)

        guard
            outputFrameCapacity > 0,
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCapacity
            )
        else { return nil }

        // Heap-allocated single-shot input holder — lets the @Sendable convert
        // block clear it on first call without mutating a captured stack var.
        let input = ConvertInput(buffer: buffer)
        var error: NSError?

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if let buf = input.take() {
                outStatus.pointee = .haveData
                return buf
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        guard error == nil, outputBuffer.frameLength > 0 else { return nil }
        guard let channelData = outputBuffer.floatChannelData else { return nil }

        let frameCount = Int(outputBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
    }
}

/// Single-shot AVAudioPCMBuffer holder used as the input source for a
/// one-call AVAudioConverter block. Reference type so the converter's
/// `@Sendable` closure can clear it without capturing a mutable stack var.
private final class ConvertInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}
