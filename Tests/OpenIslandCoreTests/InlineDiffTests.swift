import Foundation
import Testing
@testable import OpenIslandCore

struct MyersDiffTests {
    @Test
    func emptyInputsReturnEmpty() {
        #expect(MyersDiff.diff(old: "", new: "") == [])
    }

    @Test
    func identicalReturnsAllContext() {
        let lines = MyersDiff.diff(old: "a\nb\nc", new: "a\nb\nc")
        #expect(lines == [.context("a"), .context("b"), .context("c")])
    }

    @Test
    func fullReplaceMarksRemoveThenAdd() {
        let lines = MyersDiff.diff(old: "old", new: "new")
        #expect(lines?.contains(.remove("old")) == true)
        #expect(lines?.contains(.add("new")) == true)
    }

    @Test
    func partialChangeKeepsContextAndMarksDelta() {
        let lines = MyersDiff.diff(old: "a\nb\nc", new: "a\nB\nc")
        #expect(lines == [.context("a"), .remove("b"), .add("B"), .context("c")])
    }

    @Test
    func insertionInMiddleProducesAddOnly() {
        let lines = MyersDiff.diff(old: "a\nc", new: "a\nb\nc")
        #expect(lines == [.context("a"), .add("b"), .context("c")])
    }

    @Test
    func deletionProducesRemoveOnly() {
        let lines = MyersDiff.diff(old: "a\nb\nc", new: "a\nc")
        #expect(lines == [.context("a"), .remove("b"), .context("c")])
    }

    @Test
    func trailingNewlineNormalized() {
        let withNewline = MyersDiff.diff(old: "a\n", new: "a\n")
        let without = MyersDiff.diff(old: "a", new: "a")
        #expect(withNewline == without)
    }

    @Test
    func sizeCapReturnsNil() {
        let huge = String(repeating: "x\n", count: ToolDiff.maxLinesPerSide + 1)
        #expect(MyersDiff.diff(old: huge, new: "y") == nil)
    }
}

struct ToolDiffExtractorTests {
    private func obj(_ pairs: [String: CodexHookJSONValue]) -> CodexHookJSONValue {
        .object(pairs)
    }

    @Test
    func unknownToolReturnsNil() {
        #expect(ToolDiffExtractor.diff(toolName: "Bash", toolInput: obj(["command": .string("ls")])) == nil)
    }

    @Test
    func nilInputReturnsNil() {
        #expect(ToolDiffExtractor.diff(toolName: "Edit", toolInput: nil) == nil)
    }

    @Test
    func nonObjectInputReturnsNil() {
        #expect(ToolDiffExtractor.diff(toolName: "Edit", toolInput: .string("garbage")) == nil)
    }

    @Test
    func editProducesUnifiedDiff() throws {
        let input = obj([
            "file_path": .string("/tmp/x.swift"),
            "old_string": .string("let a = 1"),
            "new_string": .string("let a = 2"),
        ])
        let diff = try #require(ToolDiffExtractor.diff(toolName: "Edit", toolInput: input))
        #expect(diff.filePath == "/tmp/x.swift")
        #expect(diff.additionCount == 1)
        #expect(diff.removalCount == 1)
        #expect(diff.lines.contains(.remove("let a = 1")))
        #expect(diff.lines.contains(.add("let a = 2")))
    }

    @Test
    func writeMarksEveryLineAsAddition() throws {
        let input = obj([
            "file_path": .string("/tmp/new.swift"),
            "content": .string("line one\nline two\nline three"),
        ])
        let diff = try #require(ToolDiffExtractor.diff(toolName: "Write", toolInput: input))
        #expect(diff.additionCount == 3)
        #expect(diff.removalCount == 0)
        #expect(diff.lines.allSatisfy { $0.isAddition })
    }

    @Test
    func multiEditCombinesHunksWithEllipsisSeparator() throws {
        let edits: CodexHookJSONValue = .array([
            obj(["old_string": .string("a"), "new_string": .string("A")]),
            obj(["old_string": .string("b"), "new_string": .string("B")]),
        ])
        let input = obj([
            "file_path": .string("/tmp/multi.swift"),
            "edits": edits,
        ])
        let diff = try #require(ToolDiffExtractor.diff(toolName: "MultiEdit", toolInput: input))
        #expect(diff.additionCount == 2)
        #expect(diff.removalCount == 2)
        #expect(diff.lines.contains(.context("…")))
    }

    @Test
    func applyPatchParsesUnifiedDiff() throws {
        let patch = """
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,3 @@
         context
        -old line
        +new line
         tail
        """
        let diff = try #require(ToolDiffExtractor.diff(toolName: "apply_patch", toolInput: obj(["patch": .string(patch)])))
        #expect(diff.filePath == "foo.swift")
        #expect(diff.lines.contains(.context("context")))
        #expect(diff.lines.contains(.remove("old line")))
        #expect(diff.lines.contains(.add("new line")))
        #expect(diff.lines.contains(.context("tail")))
        #expect(diff.additionCount == 1)
        #expect(diff.removalCount == 1)
    }

    @Test
    func editMissingFieldsReturnsNil() {
        let input = obj([
            "file_path": .string("/tmp/x.swift"),
            "old_string": .string("a"),
            // missing new_string
        ])
        #expect(ToolDiffExtractor.diff(toolName: "Edit", toolInput: input) == nil)
    }

    @Test
    func editTooLargeReturnsTruncatedDiff() throws {
        let huge = String(repeating: "x\n", count: ToolDiff.maxLinesPerSide + 100)
        let input = obj([
            "file_path": .string("/tmp/big.txt"),
            "old_string": .string(huge),
            "new_string": .string("y"),
        ])
        let diff = try #require(ToolDiffExtractor.diff(toolName: "Edit", toolInput: input))
        #expect(diff.truncated == true)
        #expect(diff.lines.isEmpty)
    }
}
