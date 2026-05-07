import Foundation

/// Persistence helpers that keep user activity data owner-only on disk.
///
/// macOS is a multi-user OS — by default, files written via
/// `Data.write(to:options:.atomic)` land at mode `0644`, which means
/// every other local account can read them. Atoll's persistence layer
/// stores prompts, transcripts, agent intents, screenshots, and other
/// signals that should never be visible to a different login.
///
/// Use ``writeUserPrivate(_:to:)`` for any payload that may contain
/// user activity data. It writes atomically and tightens the mode to
/// `0o600` (owner read/write, no group, no other) immediately afterward.
public enum UserPrivateFileWrite {
    /// Writes `data` atomically and sets the file permissions to `0o600`
    /// (owner read/write only). Use for any file that may contain user
    /// activity data — registries, caches, screenshots, transcripts.
    public static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: Int(0o600)],
            ofItemAtPath: url.path
        )
    }

    /// Writes `string` (UTF-8) atomically and sets the file permissions
    /// to `0o600`. Convenience wrapper around ``write(_:to:)``.
    public static func writeString(_ string: String, to url: URL) throws {
        try write(Data(string.utf8), to: url)
    }

    /// Creates `directory` (and intermediates) with mode `0o700`
    /// (owner-only) when it does not yet exist, and opportunistically
    /// downgrades a pre-existing directory from `0o755` (or anything
    /// looser) to `0o700` on the next access. Errors during the
    /// opportunistic tightening are swallowed — directory creation is a
    /// best-effort hardening pass and should not block normal IO.
    public static func ensurePrivateDirectory(
        at directory: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: directory.path) {
            // Opportunistic downgrade for installs that predate this
            // helper. We swallow the error: if the user has done
            // something exotic with their permissions we should not
            // refuse to start the app.
            try? fileManager.setAttributes(
                [.posixPermissions: Int(0o700)],
                ofItemAtPath: directory.path
            )
            return
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Int(0o700)]
        )
    }

    /// Marks `url` as excluded from Time Machine / iCloud backups. Use
    /// for regenerable caches and dev-only artifacts that have no
    /// long-term value to the user.
    public static func excludeFromBackup(_ url: URL) {
        var working = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? working.setResourceValues(values)
    }
}

/// Free-function alias matching the audit's recommended API. Equivalent
/// to ``UserPrivateFileWrite/write(_:to:)``.
public func writeUserPrivate(_ data: Data, to url: URL) throws {
    try UserPrivateFileWrite.write(data, to: url)
}
