import Foundation

/// Caps used by the streaming JSONL reader and registry-file loaders.
public enum BoundedFileReader {
    /// Skip lines longer than this when streaming a JSONL transcript.
    public static let maxLineBytes = 1 * 1024 * 1024 // 1 MiB

    /// Stop reading further once a single transcript file has yielded this many bytes.
    public static let maxFileBytes = 64 * 1024 * 1024 // 64 MiB

    /// Cap any settings/registry/config JSON file at this size.
    /// Files above this are refused (throw) rather than silently truncated.
    public static let maxConfigFileBytes = 4 * 1024 * 1024 // 4 MiB

    /// Internal chunk size for incremental reads.
    public static let chunkSize = 64 * 1024
}

/// Error thrown by `readBoundedConfigFile` when the file exceeds the size cap.
public enum BoundedFileReaderError: Error, LocalizedError, Equatable {
    case fileTooLarge(path: String, sizeBytes: Int, limitBytes: Int)

    public var errorDescription: String? {
        switch self {
        case let .fileTooLarge(path, size, limit):
            return "File \(path) is \(size) bytes; refusing to load past \(limit)-byte cap."
        }
    }
}

/// Reads the entire file at `url`, capped at `BoundedFileReader.maxConfigFileBytes`
/// (default 4 MiB). Throws `BoundedFileReaderError.fileTooLarge` if the file
/// exceeds the cap. Returns `nil` if the file does not exist.
public func readBoundedConfigFile(
    at url: URL,
    limit: Int = BoundedFileReader.maxConfigFileBytes,
    fileManager: FileManager = .default
) throws -> Data? {
    guard fileManager.fileExists(atPath: url.path) else {
        return nil
    }

    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    if let size = attributes[.size] as? NSNumber, size.intValue > limit {
        throw BoundedFileReaderError.fileTooLarge(
            path: url.path,
            sizeBytes: size.intValue,
            limitBytes: limit
        )
    }

    let data = try Data(contentsOf: url)
    if data.count > limit {
        throw BoundedFileReaderError.fileTooLarge(
            path: url.path,
            sizeBytes: data.count,
            limitBytes: limit
        )
    }
    return data
}

/// Streams `url` line by line. Lines longer than `maxLineBytes` are dropped
/// (with `onOversizedLine` invoked). Reading stops after `maxFileBytes` total
/// bytes have been consumed (`onTruncated` is invoked once if hit).
///
/// Returns the lines that were yielded successfully, in order.
public func streamJSONLines(
    at url: URL,
    maxLineBytes: Int = BoundedFileReader.maxLineBytes,
    maxFileBytes: Int = BoundedFileReader.maxFileBytes,
    chunkSize: Int = BoundedFileReader.chunkSize,
    onOversizedLine: ((Int) -> Void)? = nil,
    onTruncated: (() -> Void)? = nil
) throws -> [String] {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var lines: [String] = []
    var buffer = Data()
    var totalConsumed = 0
    var truncatedFired = false
    let newlineByte: UInt8 = 0x0A

    while totalConsumed < maxFileBytes {
        let remainingBudget = maxFileBytes - totalConsumed
        let toRead = min(chunkSize, remainingBudget)
        guard let chunk = try handle.read(upToCount: toRead), !chunk.isEmpty else {
            break
        }
        totalConsumed += chunk.count
        buffer.append(chunk)

        while let nlIndex = buffer.firstIndex(of: newlineByte) {
            let lineRange = buffer.startIndex..<nlIndex
            let lineSize = nlIndex - buffer.startIndex
            if lineSize > maxLineBytes {
                onOversizedLine?(lineSize)
            } else if let line = String(data: buffer.subdata(in: lineRange), encoding: .utf8) {
                lines.append(line)
            }
            buffer.removeSubrange(buffer.startIndex...nlIndex)
        }

        // If the buffer has grown beyond a line cap without a newline,
        // there's a runaway line — drop it eagerly so we don't OOM.
        if buffer.count > maxLineBytes {
            onOversizedLine?(buffer.count)
            buffer.removeAll(keepingCapacity: false)
        }
    }

    // Trailing line without a newline.
    if !buffer.isEmpty, buffer.count <= maxLineBytes {
        if let line = String(data: buffer, encoding: .utf8) {
            lines.append(line)
        }
    }

    if totalConsumed >= maxFileBytes {
        // Check if there was actually more.
        if let extra = try handle.read(upToCount: 1), !extra.isEmpty {
            if !truncatedFired {
                onTruncated?()
                truncatedFired = true
            }
        }
    }

    return lines
}
