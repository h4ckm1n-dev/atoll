import Foundation
import Testing
@testable import AtollCore

struct UserPrivateFileWriteTests {
    private func tempURL(suffix: String = ".dat") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("upfw-\(UUID().uuidString)\(suffix)")
    }

    @Test
    func writeUserPrivateSetsOwnerOnlyMode() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeUserPrivate(Data("payload".utf8), to: url)

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let raw = attrs[.posixPermissions] as? NSNumber else {
            Issue.record("Expected posixPermissions to be readable as NSNumber")
            return
        }
        #expect(raw.intValue == 0o600,
                "writeUserPrivate must clamp the file to 0o600, got 0o\(String(raw.intValue, radix: 8))")
    }

    @Test
    func writeUserPrivateOverwritesPreviousContents() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try writeUserPrivate(Data("v1".utf8), to: url)
        try writeUserPrivate(Data("v2".utf8), to: url)

        let reread = try Data(contentsOf: url)
        #expect(String(data: reread, encoding: .utf8) == "v2")
    }

    @Test
    func ensurePrivateDirectoryCreatesAt0o700() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("upfw-dir-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try UserPrivateFileWrite.ensurePrivateDirectory(at: dir)
        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        guard let raw = attrs[.posixPermissions] as? NSNumber else {
            Issue.record("Expected posixPermissions to be readable as NSNumber")
            return
        }
        #expect(raw.intValue == 0o700,
                "ensurePrivateDirectory must create dirs at 0o700, got 0o\(String(raw.intValue, radix: 8))")
    }

    @Test
    func ensurePrivateDirectoryDowngradesExistingLooseDir() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("upfw-dir-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Pre-create at 0o755 (the legacy default) and then ask the
        // helper to take over — it should opportunistically downgrade.
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Int(0o755)]
        )
        try UserPrivateFileWrite.ensurePrivateDirectory(at: dir)

        let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
        guard let raw = attrs[.posixPermissions] as? NSNumber else {
            Issue.record("Expected posixPermissions to be readable as NSNumber")
            return
        }
        #expect(raw.intValue == 0o700)
    }
}
