import Foundation
import Testing
@testable import AtollCore

struct CustomThemeRegistryTests {
    /// Each test gets its own temp directory so they don't share state.
    private func makeRegistry() -> (CustomThemeRegistry, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-tests-\(UUID().uuidString)", isDirectory: true)
        return (CustomThemeRegistry(directory: tmp), tmp)
    }

    private func sampleTheme(name: String = "Test") -> CustomTheme {
        CustomTheme.fork(from: .mocha, displayName: name)
    }

    @Test
    func saveLoadPreservesAllFields() async throws {
        let (registry, _) = makeRegistry()
        let original = sampleTheme()
        try await registry.save(original)

        let (registry2, _) = (registry, ()) // fresh load via existing instance is fine
        try await registry2.load()
        let loaded = await registry2.themes
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == original.id)
        #expect(loaded.first?.displayName == original.displayName)
        #expect(loaded.first?.palette == original.palette)
    }

    @Test
    func deleteRemovesTheme() async throws {
        let (registry, _) = makeRegistry()
        let theme = sampleTheme()
        try await registry.save(theme)
        try await registry.delete(id: theme.id)
        let after = await registry.themes
        #expect(after.isEmpty)
    }

    @Test
    func duplicateProducesNewUUIDAndCopySuffix() async throws {
        let (registry, _) = makeRegistry()
        let original = sampleTheme(name: "My Night")
        try await registry.save(original)

        let copy = try await registry.duplicate(id: original.id)
        #expect(copy.id != original.id)
        #expect(copy.displayName == "My Night copy")
        #expect(copy.palette == original.palette)

        let copy2 = try await registry.duplicate(id: original.id)
        #expect(copy2.displayName == "My Night copy 2")
    }

    @Test
    func importFromValidJSONAssignsFreshID() async throws {
        let (registry, _) = makeRegistry()
        let original = sampleTheme(name: "Shared")
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try await registry.exportTheme(original, to: exportURL)

        let imported = try await registry.importTheme(from: exportURL)
        #expect(imported.id != original.id, "Import must assign a fresh UUID")
        #expect(imported.displayName == "Shared")
        #expect(imported.palette == original.palette)
    }

    @Test
    func importFromMalformedJSONThrowsAndDoesNotPersist() async throws {
        let (registry, dir) = makeRegistry()
        let bad = dir.deletingLastPathComponent()
            .appendingPathComponent("bad-\(UUID().uuidString).json")
        try Data("{ this is not json".utf8).write(to: bad)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: bad)
        }
        let after = await registry.themes
        #expect(after.isEmpty, "Failed import must not leave a partial entry")
    }

    @Test
    func importFromMissingFieldThrowsCleanly() async throws {
        let (registry, dir) = makeRegistry()
        let bad = dir.deletingLastPathComponent()
            .appendingPathComponent("missing-\(UUID().uuidString).json")
        // Valid JSON, but the palette is missing the `green` key.
        try Data("""
        {
          "id": "\(UUID().uuidString)",
          "displayName": "Broken",
          "createdAt": "2026-05-07T00:00:00Z",
          "updatedAt": "2026-05-07T00:00:00Z",
          "basedOn": {"kind":"mocha"},
          "palette": {
            "schemaVersion": 1,
            "isLight": false,
            "base": "162232", "mantle": "10182a", "crust": "0a1220",
            "surface0": "263347", "surface1": "37475e", "surface2": "4a5b75",
            "text": "cdd6f4", "subtext1": "bac2de", "subtext0": "a6adc8",
            "overlay2": "9399b2", "overlay1": "7f849c", "overlay0": "6c7086",
            "rosewater": "f5e0dc", "flamingo": "f2cdcd", "pink": "f5c2e7",
            "mauve": "cba6f7", "red": "f38ba8", "maroon": "eba0ac",
            "peach": "fab387", "yellow": "f9e2af",
            "teal": "94e2d5", "sky": "89dceb", "sapphire": "74c7ec",
            "blue": "89b4fa", "lavender": "b4befe"
          }
        }
        """.utf8).write(to: bad)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: bad)
        }
    }

    @Test
    func importRejectsOversizedFile() async throws {
        let (registry, _) = makeRegistry()
        let bad = FileManager.default.temporaryDirectory
            .appendingPathComponent("oversized-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: bad) }
        // Padded JSON > 256 KB.
        let padding = String(repeating: " ", count: 300 * 1024)
        try Data("{ \"x\": \"\(padding)\" }".utf8).write(to: bad)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: bad)
        }
        let after = await registry.themes
        #expect(after.isEmpty, "Oversized import must not leave a partial entry")
    }

    @Test
    func importRejectsSymlink() async throws {
        let (registry, _) = makeRegistry()
        let original = sampleTheme(name: "Linked")
        let realFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("real-\(UUID().uuidString).json")
        let symlink = FileManager.default.temporaryDirectory
            .appendingPathComponent("link-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: realFile)
            try? FileManager.default.removeItem(at: symlink)
        }
        try await registry.exportTheme(original, to: realFile)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: symlink)
        }
    }

    @Test
    func importRejectsOversizedDisplayName() async throws {
        let (registry, _) = makeRegistry()
        // Build a theme JSON with an absurdly long displayName by hand
        // so we sidestep the in-process model's freedom to truncate.
        let bad = FileManager.default.temporaryDirectory
            .appendingPathComponent("longname-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: bad) }
        let longName = String(repeating: "a", count: 500)
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "displayName": "\(longName)",
          "createdAt": "2026-05-07T00:00:00Z",
          "updatedAt": "2026-05-07T00:00:00Z",
          "basedOn": {"kind":"mocha"},
          "palette": {
            "schemaVersion": 1,
            "isLight": false,
            "base": "162232", "mantle": "10182a", "crust": "0a1220",
            "surface0": "263347", "surface1": "37475e", "surface2": "4a5b75",
            "text": "cdd6f4", "subtext1": "bac2de", "subtext0": "a6adc8",
            "overlay2": "9399b2", "overlay1": "7f849c", "overlay0": "6c7086",
            "rosewater": "f5e0dc", "flamingo": "f2cdcd", "pink": "f5c2e7",
            "mauve": "cba6f7", "red": "f38ba8", "maroon": "eba0ac",
            "peach": "fab387", "yellow": "f9e2af", "green": "a6e3a1",
            "teal": "94e2d5", "sky": "89dceb", "sapphire": "74c7ec",
            "blue": "89b4fa", "lavender": "b4befe"
          }
        }
        """
        try Data(json.utf8).write(to: bad)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: bad)
        }
    }

    @Test
    func importRejectsBloatedPalette() async throws {
        let (registry, _) = makeRegistry()
        let bad = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloated-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: bad) }

        // 80 distinct keys — well over the 64 cap. The required 26
        // canonical keys are present so Codable decodes; the extra
        // keys then trip the entry-count check.
        var extraKeys = ""
        for index in 0..<80 {
            extraKeys += ",\n            \"extra\(index)\": \"010203\""
        }
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "displayName": "Bloated",
          "createdAt": "2026-05-07T00:00:00Z",
          "updatedAt": "2026-05-07T00:00:00Z",
          "basedOn": {"kind":"mocha"},
          "palette": {
            "schemaVersion": 1,
            "isLight": false,
            "base": "162232", "mantle": "10182a", "crust": "0a1220",
            "surface0": "263347", "surface1": "37475e", "surface2": "4a5b75",
            "text": "cdd6f4", "subtext1": "bac2de", "subtext0": "a6adc8",
            "overlay2": "9399b2", "overlay1": "7f849c", "overlay0": "6c7086",
            "rosewater": "f5e0dc", "flamingo": "f2cdcd", "pink": "f5c2e7",
            "mauve": "cba6f7", "red": "f38ba8", "maroon": "eba0ac",
            "peach": "fab387", "yellow": "f9e2af", "green": "a6e3a1",
            "teal": "94e2d5", "sky": "89dceb", "sapphire": "74c7ec",
            "blue": "89b4fa", "lavender": "b4befe"\(extraKeys)
          }
        }
        """
        try Data(json.utf8).write(to: bad)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: bad)
        }
    }

    @Test
    func importRejectsMalformedHex() async throws {
        let (registry, _) = makeRegistry()
        let bad = FileManager.default.temporaryDirectory
            .appendingPathComponent("badhex-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: bad) }

        // The decoder will throw `dataCorrupted` on this string; the
        // top-level importer should surface it as a `ThemeRegistryError`.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "displayName": "Bad Hex",
          "createdAt": "2026-05-07T00:00:00Z",
          "updatedAt": "2026-05-07T00:00:00Z",
          "basedOn": {"kind":"mocha"},
          "palette": {
            "schemaVersion": 1,
            "isLight": false,
            "base": "ZZZZZZ", "mantle": "10182a", "crust": "0a1220",
            "surface0": "263347", "surface1": "37475e", "surface2": "4a5b75",
            "text": "cdd6f4", "subtext1": "bac2de", "subtext0": "a6adc8",
            "overlay2": "9399b2", "overlay1": "7f849c", "overlay0": "6c7086",
            "rosewater": "f5e0dc", "flamingo": "f2cdcd", "pink": "f5c2e7",
            "mauve": "cba6f7", "red": "f38ba8", "maroon": "eba0ac",
            "peach": "fab387", "yellow": "f9e2af", "green": "a6e3a1",
            "teal": "94e2d5", "sky": "89dceb", "sapphire": "74c7ec",
            "blue": "89b4fa", "lavender": "b4befe"
          }
        }
        """
        try Data(json.utf8).write(to: bad)

        await #expect(throws: ThemeRegistryError.self) {
            _ = try await registry.importTheme(from: bad)
        }
    }

    @Test
    func savedThemeFileIsOwnerOnly() async throws {
        let (registry, dir) = makeRegistry()
        let theme = sampleTheme(name: "Locked Down")
        try await registry.save(theme)

        let fileURL = dir.appendingPathComponent("\(theme.id.uuidString).json")
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let raw = attrs[.posixPermissions] as? NSNumber else {
            Issue.record("Expected posixPermissions to be readable as NSNumber")
            return
        }
        #expect(raw.intValue == 0o600)

        // Directory should also be 0o700.
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        if let dirRaw = dirAttrs[.posixPermissions] as? NSNumber {
            #expect(dirRaw.intValue == 0o700)
        }
    }

    @Test
    func corruptFileInDirIsSkippedDuringLoad() async throws {
        let (registry, dir) = makeRegistry()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Drop one valid file…
        let valid = sampleTheme(name: "Valid")
        try await registry.save(valid)
        // …and one corrupt file alongside it.
        let corrupt = dir.appendingPathComponent("corrupt.json")
        try Data("{ not parseable".utf8).write(to: corrupt)

        try await registry.load()
        let themes = await registry.themes
        #expect(themes.count == 1)
        #expect(themes.first?.id == valid.id)
    }
}
