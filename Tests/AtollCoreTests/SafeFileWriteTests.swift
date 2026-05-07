import Foundation
import Testing
@testable import AtollCore

struct SafeFileWriteTests {
    private static func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-safewrite-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func writesNewFileAtomically() throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("settings.json")
        try safeAtomicWrite(Data("{}".utf8), to: target)
        let read = try Data(contentsOf: target)
        #expect(read == Data("{}".utf8))
    }

    @Test
    func overwritesExistingNonSymlinkFile() throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("config.toml")
        try Data("old".utf8).write(to: target)
        try safeAtomicWrite(Data("new".utf8), to: target)
        let read = try Data(contentsOf: target)
        #expect(read == Data("new".utf8))
    }

    @Test
    func refusesWhenDestinationIsSymlink() throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real-target.txt")
        let symlink = dir.appendingPathComponent("link-target.txt")
        try Data("hijacked".utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: real)

        do {
            try safeAtomicWrite(Data("attacker payload".utf8), to: symlink)
            Issue.record("expected SafeFileWriteError.destinationIsSymlink")
        } catch let error as SafeFileWriteError {
            guard case .destinationIsSymlink = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }

        // Real file must still hold its original content.
        #expect(try Data(contentsOf: real) == Data("hijacked".utf8))
    }

    @Test
    func refusesWhenParentIsSymlink() throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let realParent = dir.appendingPathComponent("real-parent", isDirectory: true)
        let linkParent = dir.appendingPathComponent("link-parent", isDirectory: true)
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkParent, withDestinationURL: realParent)
        let target = linkParent.appendingPathComponent("file.txt")

        do {
            try safeAtomicWrite(Data("payload".utf8), to: target)
            Issue.record("expected SafeFileWriteError.parentIsSymlink")
        } catch let error as SafeFileWriteError {
            guard case .parentIsSymlink = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }
    }

    @Test
    func setsPosixPermissionsWhenRequested() throws {
        let dir = Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("script.sh")
        try safeAtomicWrite(Data("#!/bin/sh\n".utf8), to: target, posixPermissions: 0o755)

        let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        #expect(perms & 0o777 == 0o755)
    }
}
