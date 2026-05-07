import Foundation
import Testing
@testable import AtollCore

struct BoundedFileReaderTests {
    private static func tempFile(name: String = "stream-\(UUID().uuidString).jsonl") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    @Test
    func streamsLinesUnderCap() throws {
        let url = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("a\nb\nc\n".utf8).write(to: url)

        let lines = try streamJSONLines(at: url)
        #expect(lines == ["a", "b", "c"])
    }

    @Test
    func skipsOversizedLines() throws {
        let url = Self.tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let huge = String(repeating: "x", count: 2 * 1024 * 1024) // 2 MiB
        let payload = "ok\n\(huge)\nfine\n"
        try Data(payload.utf8).write(to: url)

        var oversizedCount = 0
        let lines = try streamJSONLines(
            at: url,
            onOversizedLine: { _ in oversizedCount += 1 }
        )
        #expect(oversizedCount >= 1)
        #expect(lines.contains("ok"))
        #expect(lines.contains("fine"))
        #expect(!lines.contains(where: { $0.count > BoundedFileReader.maxLineBytes }))
    }

    @Test
    func registryFileSizeCapRejectsOversizedConfig() throws {
        let url = Self.tempFile(name: "registry-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        // 5 MiB > default 4 MiB cap.
        let blob = Data(repeating: 0x20, count: 5 * 1024 * 1024)
        try blob.write(to: url)

        do {
            _ = try readBoundedConfigFile(at: url)
            Issue.record("expected BoundedFileReaderError.fileTooLarge")
        } catch let error as BoundedFileReaderError {
            guard case .fileTooLarge = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }
    }

    @Test
    func registryFileSizeCapAllowsSmallConfig() throws {
        let url = Self.tempFile(name: "small-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"hello\":\"world\"}".utf8).write(to: url)

        let data = try readBoundedConfigFile(at: url)
        #expect(data != nil)
    }
}
