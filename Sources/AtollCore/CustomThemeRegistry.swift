import Foundation

/// Errors thrown by `CustomThemeRegistry` for IO and import failures.
/// Localized messages are intentionally English-only at the model
/// layer — the UI catches these and maps to localized strings via
/// `LanguageManager`.
public enum ThemeRegistryError: Error, LocalizedError, Equatable {
    case directoryUnavailable(URL)
    case malformedJSON(url: URL, underlying: String)
    case missingField(url: URL, field: String)
    case ioFailure(url: URL, underlying: String)
    /// Import file rejected because it exceeds the configured size cap
    /// (256 KB) or could not be stat-ed. Theme files are tiny (<10 KB
    /// in practice) — anything larger is either bloat or an attempt to
    /// stress the parser.
    case themeFileTooLarge(url: URL, sizeBytes: Int, limitBytes: Int)
    /// Import file rejected because the URL is a symlink or not a
    /// regular file. We never follow symlinks during import to avoid
    /// being tricked into reading something outside the user's
    /// intended target (e.g. `/etc/shadow`-style attacks against an
    /// app that has access to a sensitive volume).
    case themeFileNotRegular(url: URL)
    /// Import rejected because the decoded theme failed structural
    /// validation (display name too long, palette too large, malformed
    /// hex). Distinct from `malformedJSON` — those are JSON syntax
    /// errors, this is post-decode semantic validation.
    case themeContentInvalid(url: URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .directoryUnavailable(let url):
            return "Themes directory is unavailable: \(url.path)"
        case .malformedJSON(let url, let underlying):
            return "Theme file is malformed: \(url.lastPathComponent) — \(underlying)"
        case .missingField(let url, let field):
            return "Theme file is missing the `\(field)` color: \(url.lastPathComponent)"
        case .ioFailure(let url, let underlying):
            return "Theme file IO failed: \(url.lastPathComponent) — \(underlying)"
        case .themeFileTooLarge(let url, let sizeBytes, let limitBytes):
            return "Theme file is too large to import: \(url.lastPathComponent) — \(sizeBytes) bytes exceeds the \(limitBytes)-byte limit."
        case .themeFileNotRegular(let url):
            return "Theme file must be a regular file (not a symlink): \(url.lastPathComponent)"
        case .themeContentInvalid(let url, let reason):
            return "Theme file failed validation: \(url.lastPathComponent) — \(reason)"
        }
    }
}

/// Owns the on-disk directory of user-authored themes. One file per
/// theme keyed by UUID — atomic writes, drag-from-Finder shareability,
/// no special characters in filenames.
///
/// Actor isolation: serializes all file IO. Public methods are async;
/// the SwiftUI layer awaits them from MainActor without contention.
public actor CustomThemeRegistry {
    /// In-memory cache of loaded themes, sorted by `createdAt` ascending
    /// (oldest first) so the UI list order is stable across launches.
    public private(set) var themes: [CustomTheme] = []

    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Default location: `~/Library/Application Support/Atoll/themes/`.
    /// Tests inject a temp directory for isolation.
    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("Atoll", isDirectory: true)
            .appendingPathComponent("themes", isDirectory: true)
    }

    /// Scans the directory and populates `themes`. Safe to call on
    /// startup. Per-file decode errors are *swallowed* (logged via
    /// stderr) rather than propagated — one corrupt file should not
    /// hide the rest of the user's library.
    public func load() async throws {
        try ensureDirectoryExists()
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]
        )) ?? []
        var loaded: [CustomTheme] = []
        for url in urls where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                let theme = try decoder.decode(CustomTheme.self, from: data)
                loaded.append(theme)
            } catch {
                FileHandle.standardError.write(
                    Data("Atoll: skipping corrupt theme \(url.lastPathComponent): \(error)\n".utf8)
                )
            }
        }
        themes = loaded.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ theme: CustomTheme) async throws {
        try ensureDirectoryExists()
        var updated = theme
        updated.updatedAt = Date()
        let url = fileURL(for: updated.id)
        do {
            // TODO(security): consider redacting any PII/tokens that
            // may end up in displayName or palette metadata before
            // persisting. Current model has no free-form user text
            // beyond `displayName`, but track for future audits.
            let data = try encoder.encode(updated)
            try writeUserPrivate(data, to: url)
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
        if let index = themes.firstIndex(where: { $0.id == updated.id }) {
            themes[index] = updated
        } else {
            themes.append(updated)
            themes.sort { $0.createdAt < $1.createdAt }
        }
    }

    public func delete(id: UUID) async throws {
        let url = fileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
            }
        }
        themes.removeAll { $0.id == id }
    }

    public func duplicate(id: UUID) async throws -> CustomTheme {
        guard let source = themes.first(where: { $0.id == id }) else {
            throw ThemeRegistryError.ioFailure(
                url: fileURL(for: id),
                underlying: "Theme \(id) not found in registry"
            )
        }
        let copy = CustomTheme(
            displayName: nextAvailableDuplicateName(for: source.displayName),
            palette: source.palette,
            basedOn: source.basedOn
        )
        try await save(copy)
        return copy
    }

    /// Hard cap on the size of a theme JSON file we'll import. Real
    /// themes are <10 KB; 256 KB is generous headroom for future
    /// schema growth while still rejecting payloads that look like
    /// parser-stress probes.
    public static let maxImportFileSizeBytes: Int = 256 * 1024

    /// Maximum allowed length of `CustomTheme.displayName`. Keeps the
    /// settings list readable and prevents pathological strings from
    /// reaching the UI / pasteboard.
    public static let maxDisplayNameLength: Int = 256

    /// Hard cap on the number of decoded color entries we accept in a
    /// palette. The current schema has 26 named fields — anything
    /// claiming more than 64 is malformed.
    public static let maxPaletteEntries: Int = 64

    /// Imports a theme from an external JSON file. The file's id is
    /// REPLACED with a fresh UUID so two users importing the same
    /// shared theme don't collide if the original is later imported
    /// from a friend. Returns the imported theme so the caller can
    /// flip the picker to it.
    ///
    /// Defensive checks before reading:
    /// - The URL must point to a regular file (no symlinks).
    /// - File size must be <= ``maxImportFileSizeBytes``.
    /// After decoding:
    /// - `displayName` length is bounded.
    /// - Every color hex string is validated.
    /// - Palettes with absurd entry counts are rejected.
    public func importTheme(from url: URL) async throws -> CustomTheme {
        try ensureDirectoryExists()
        try Self.assertImportableFile(url: url)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
        guard data.count <= Self.maxImportFileSizeBytes else {
            throw ThemeRegistryError.themeFileTooLarge(
                url: url,
                sizeBytes: data.count,
                limitBytes: Self.maxImportFileSizeBytes
            )
        }
        let decoded: CustomTheme
        do {
            decoded = try decoder.decode(CustomTheme.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw ThemeRegistryError.missingField(url: url, field: key.stringValue)
        } catch {
            throw ThemeRegistryError.malformedJSON(url: url, underlying: "\(error)")
        }
        try Self.assertImportContentValid(decoded, url: url, rawData: data)
        let renamed = CustomTheme(
            id: UUID(),
            displayName: decoded.displayName,
            palette: decoded.palette,
            basedOn: decoded.basedOn,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await save(renamed)
        return renamed
    }

    public func exportTheme(_ theme: CustomTheme, to url: URL) async throws {
        do {
            let data = try encoder.encode(theme)
            // Exports often land in user-chosen destinations (Downloads,
            // shared volumes). Still default to owner-only — the user
            // can chmod afterward if they truly intend to share.
            try writeUserPrivate(data, to: url)
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
    }

    // MARK: - Import validation

    /// Refuses non-regular files (symlinks, devices, directories) and
    /// caps the file size before we even allocate the read buffer.
    private static func assertImportableFile(url: URL) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
        if values.isSymbolicLink == true {
            throw ThemeRegistryError.themeFileNotRegular(url: url)
        }
        if values.isRegularFile != true {
            throw ThemeRegistryError.themeFileNotRegular(url: url)
        }
        if let size = values.fileSize, size > maxImportFileSizeBytes {
            throw ThemeRegistryError.themeFileTooLarge(
                url: url,
                sizeBytes: size,
                limitBytes: maxImportFileSizeBytes
            )
        }
    }

    /// Validates the decoded theme structure and the on-disk JSON's
    /// shape. The palette field count is checked against the raw JSON
    /// — Swift's `Codable` would happily silently drop excess keys,
    /// but a payload claiming to be a 5,000-entry palette has no
    /// legitimate origin.
    private static func assertImportContentValid(
        _ theme: CustomTheme,
        url: URL,
        rawData: Data
    ) throws {
        if theme.displayName.count > maxDisplayNameLength {
            throw ThemeRegistryError.themeContentInvalid(
                url: url,
                reason: "displayName must be \(maxDisplayNameLength) characters or fewer"
            )
        }
        // Validate every hex string in the palette. The decoder
        // already enforces 6-char hex, but we re-check here so we
        // produce the consistent `themeContentInvalid` error rather
        // than the decoder's `dataCorrupted` path. `^#?[0-9A-Fa-f]{6,8}$`
        // is the required regex; we accept the optional alpha bytes
        // even though `ProjectColor` ignores them today.
        for (name, hex) in theme.palette.allHexValues() {
            guard isAcceptableHexString(hex) else {
                throw ThemeRegistryError.themeContentInvalid(
                    url: url,
                    reason: "color '\(name)' is not a valid hex string"
                )
            }
        }
        // Cap the on-disk palette size: if the JSON object claims more
        // than `maxPaletteEntries` color keys, reject it. This guards
        // against pathological imports that would still pass the
        // typed Codable check (because Swift drops unknown keys).
        if let palette = paletteJSONKeys(in: rawData), palette.count > maxPaletteEntries {
            throw ThemeRegistryError.themeContentInvalid(
                url: url,
                reason: "palette declares \(palette.count) entries; max is \(maxPaletteEntries)"
            )
        }
    }

    private static func isAcceptableHexString(_ raw: String) -> Bool {
        var s = raw
        if s.hasPrefix("#") { s.removeFirst() }
        guard (6...8).contains(s.count) else { return false }
        return s.allSatisfy { $0.isHexDigit }
    }

    /// Returns the `palette` object's keys as parsed from the raw JSON,
    /// or nil if the structure is unexpected. We use this only to
    /// count entries — the decoded `ThemePalette` already enforces the
    /// canonical 26-field shape.
    private static func paletteJSONKeys(in data: Data) -> [String]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let palette = root["palette"] as? [String: Any]
        else { return nil }
        return Array(palette.keys)
    }

    // MARK: - Internal helpers

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func ensureDirectoryExists() throws {
        do {
            // Both creates the directory at 0o700 on first run and
            // opportunistically downgrades pre-existing 0o755 dirs
            // from older builds.
            try UserPrivateFileWrite.ensurePrivateDirectory(
                at: directory,
                fileManager: fileManager
            )
        } catch {
            throw ThemeRegistryError.directoryUnavailable(directory)
        }
    }

    /// Picks "<base> copy", "<base> copy 2", "<base> copy 3" … Used by
    /// `duplicate(id:)` so the user sees a unique name in the list
    /// without manual renaming.
    private func nextAvailableDuplicateName(for base: String) -> String {
        let stem = "\(base) copy"
        if !themes.contains(where: { $0.displayName == stem }) { return stem }
        var index = 2
        while themes.contains(where: { $0.displayName == "\(stem) \(index)" }) {
            index += 1
        }
        return "\(stem) \(index)"
    }
}
