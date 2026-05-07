import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Errors thrown by `safeAtomicWrite(_:to:posixPermissions:)` when a symlink-based
/// hijack attempt is detected at the destination or in its immediate parent
/// directory.
public enum SafeFileWriteError: Error, LocalizedError, Equatable {
    case parentNotDirectory(path: String)
    case parentIsSymlink(path: String)
    case destinationIsSymlink(path: String)
    case writeFailed(path: String, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case let .parentNotDirectory(path):
            return "Parent of \(path) is not a directory; refusing to write."
        case let .parentIsSymlink(path):
            return "Parent of \(path) is a symlink; refusing to follow."
        case let .destinationIsSymlink(path):
            return "Destination \(path) is a symlink; refusing to follow."
        case let .writeFailed(path, errno):
            return "Failed to write \(path): errno \(errno)."
        }
    }
}

/// Atomically writes `data` to `url`, refusing to follow symlinks at the
/// destination or in the immediate parent directory.
///
/// The implementation:
/// 1. `lstat`s the parent and refuses if it does not exist as a directory or
///    if it is itself a symlink.
/// 2. `lstat`s the destination if it exists; refuses if it is a symlink.
/// 3. Opens a sibling temp file with `O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW`,
///    writes the bytes, fsyncs, and then atomically renames over the
///    destination. If `posixPermissions` is provided, the file mode is set
///    via `fchmod` before rename.
///
/// On any error mid-write the temp file is best-effort unlinked.
public func safeAtomicWrite(
    _ data: Data,
    to url: URL,
    posixPermissions: Int? = nil
) throws {
    let path = url.path
    let parent = url.deletingLastPathComponent().path

    // 1. Parent dir must exist, must be a real directory, must NOT be a symlink.
    var parentStat = stat()
    if lstat(parent, &parentStat) != 0 {
        throw SafeFileWriteError.parentNotDirectory(path: parent)
    }
    if (parentStat.st_mode & S_IFMT) == S_IFLNK {
        throw SafeFileWriteError.parentIsSymlink(path: parent)
    }
    if (parentStat.st_mode & S_IFMT) != S_IFDIR {
        throw SafeFileWriteError.parentNotDirectory(path: parent)
    }

    // 2. Destination, if it exists, must NOT be a symlink.
    var destStat = stat()
    if lstat(path, &destStat) == 0 {
        if (destStat.st_mode & S_IFMT) == S_IFLNK {
            throw SafeFileWriteError.destinationIsSymlink(path: path)
        }
    }

    // 3. Create a sibling temp file with O_NOFOLLOW so we never follow a
    //    symlink that races into existence.
    let tempName = "." + url.lastPathComponent + ".oitmp." + UUID().uuidString
    let tempPath = (parent as NSString).appendingPathComponent(tempName)

    let openFlags: Int32 = O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW
    let mode: mode_t = mode_t(posixPermissions ?? 0o600)
    let fd = tempPath.withCString { open($0, openFlags, mode) }
    guard fd >= 0 else {
        throw SafeFileWriteError.writeFailed(path: tempPath, errno: errno)
    }

    func cleanupTemp() {
        unlink(tempPath)
    }

    // Write data via fd.
    let writeResult = data.withUnsafeBytes { buf -> Int in
        guard let base = buf.baseAddress else { return 0 }
        var remaining = buf.count
        var offset = 0
        while remaining > 0 {
            let written = write(fd, base.advanced(by: offset), remaining)
            if written < 0 {
                if errno == EINTR { continue }
                return -1
            }
            if written == 0 { break }
            offset += written
            remaining -= written
        }
        return offset
    }

    if writeResult < 0 {
        let err = errno
        close(fd)
        cleanupTemp()
        throw SafeFileWriteError.writeFailed(path: tempPath, errno: err)
    }

    if let permissions = posixPermissions {
        if fchmod(fd, mode_t(permissions)) != 0 {
            let err = errno
            close(fd)
            cleanupTemp()
            throw SafeFileWriteError.writeFailed(path: tempPath, errno: err)
        }
    }

    // Best-effort fsync; ignore EINVAL on non-syncable fs.
    _ = fsync(fd)
    if close(fd) != 0 {
        let err = errno
        cleanupTemp()
        throw SafeFileWriteError.writeFailed(path: tempPath, errno: err)
    }

    // 4. Atomic rename over destination. rename(2) is atomic within the same fs.
    if rename(tempPath, path) != 0 {
        let err = errno
        cleanupTemp()
        throw SafeFileWriteError.writeFailed(path: path, errno: err)
    }
}

/// Convenience: write a UTF-8 string via `safeAtomicWrite`.
public func safeAtomicWrite(
    _ string: String,
    to url: URL,
    posixPermissions: Int? = nil
) throws {
    let data = Data(string.utf8)
    try safeAtomicWrite(data, to: url, posixPermissions: posixPermissions)
}

/// Reads `url` once, refusing to follow symlinks at the destination or its
/// immediate parent. Returns `nil` if the file does not exist; throws if a
/// symlink is detected. Used by backup helpers replacing the
/// `fileExists`-then-`copyItem` TOCTOU pattern.
public func safeReadingFileDescriptor(at url: URL) throws -> Int32? {
    let path = url.path
    let parent = url.deletingLastPathComponent().path

    var parentStat = stat()
    if lstat(parent, &parentStat) != 0 {
        return nil
    }
    if (parentStat.st_mode & S_IFMT) == S_IFLNK {
        throw SafeFileWriteError.parentIsSymlink(path: parent)
    }

    var destStat = stat()
    if lstat(path, &destStat) != 0 {
        return nil
    }
    if (destStat.st_mode & S_IFMT) == S_IFLNK {
        throw SafeFileWriteError.destinationIsSymlink(path: path)
    }

    let fd = path.withCString { open($0, O_RDONLY | O_NOFOLLOW) }
    guard fd >= 0 else {
        return nil
    }
    return fd
}

/// Copies the contents of `source` to `destination` atomically and without
/// following symlinks at either side. Used to replace
/// `FileManager.copyItem(at:to:)` in installer backup helpers.
public func safeCopyFile(from source: URL, to destination: URL) throws {
    guard let fd = try safeReadingFileDescriptor(at: source) else {
        return
    }
    defer { close(fd) }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while true {
        let n = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            return read(fd, base, ptr.count)
        }
        if n < 0 {
            if errno == EINTR { continue }
            throw SafeFileWriteError.writeFailed(path: source.path, errno: errno)
        }
        if n == 0 { break }
        data.append(buffer, count: n)
    }

    try safeAtomicWrite(data, to: destination)
}
