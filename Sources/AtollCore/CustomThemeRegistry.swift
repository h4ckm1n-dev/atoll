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
            let data = try encoder.encode(updated)
            try data.write(to: url, options: .atomic)
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

    /// Imports a theme from an external JSON file. The file's id is
    /// REPLACED with a fresh UUID so two users importing the same
    /// shared theme don't collide if the original is later imported
    /// from a friend. Returns the imported theme so the caller can
    /// flip the picker to it.
    public func importTheme(from url: URL) async throws -> CustomTheme {
        try ensureDirectoryExists()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
        let decoded: CustomTheme
        do {
            decoded = try decoder.decode(CustomTheme.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw ThemeRegistryError.missingField(url: url, field: key.stringValue)
        } catch {
            throw ThemeRegistryError.malformedJSON(url: url, underlying: "\(error)")
        }
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
            try data.write(to: url, options: .atomic)
        } catch {
            throw ThemeRegistryError.ioFailure(url: url, underlying: "\(error)")
        }
    }

    // MARK: - Internal helpers

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
    }

    private func ensureDirectoryExists() throws {
        if fileManager.fileExists(atPath: directory.path) { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
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
