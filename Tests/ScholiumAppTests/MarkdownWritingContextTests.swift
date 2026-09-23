import Foundation
import Testing

@testable import ScholiumApp

@Suite("Writing context source fidelity")
struct MarkdownWritingContextTests {
    @Test("Paragraph capture preserves BOM-aware offsets, CRLF and non-BMP characters")
    func paragraph() throws {
        let source = "\u{FEFF}# Title\r\n\r\n控制😀 条件\r\n继续说明。\r\n\r\nEnd"
        let caret = "# Title\n\n控制😀".utf16.count
        let value = try MarkdownWritingContextProjection.capture(
            source: source,
            selections: [.init(anchor: caret, head: caret)], mode: .selectionOrParagraph)
        #expect(value.source == source)
        #expect(value.excerpt == "控制😀 条件\r\n继续说明。\r\n")
        #expect(value.sourceRange.line == 3)
        #expect(
            (source as NSString).substring(
                with: NSRange(
                    location: value.sourceRange.utf16LowerBound,
                    length: value.sourceRange.utf16UpperBound - value.sourceRange.utf16LowerBound)) == value.excerpt)
    }

    @Test("Selection is preferred and multiple cursors never imply a writing range")
    func selections() throws {
        let value = try MarkdownWritingContextProjection.capture(
            source: "a test paragraph",
            selections: [.init(anchor: 6, head: 2)], mode: .selectionOrParagraph)
        #expect(value.excerpt == "test")
        #expect(throws: (any Error).self) {
            try MarkdownWritingContextProjection.capture(
                source: "test", selections: [.init(anchor: 0, head: 0), .init(anchor: 2, head: 2)], mode: .selectionOrParagraph)
        }
    }

    @Test("Current line never expands into adjacent prose and preserves exact Unicode offsets", arguments: ["\n", "\r\n"])
    func currentLine(newline: String) throws {
        let lines = ["First e\u{301} line", "  控制😀 e\u{301} 条件  ", "Final line"]
        let source = "\u{FEFF}" + lines.joined(separator: newline)
        let native = source as NSString
        let map = EditorSourceOffsetMap(source: source)
        for (index, line) in lines.enumerated() {
            let expected = native.range(of: line)
            // At either boundary the caret still belongs to this logical line.
            for sourceCaret in [expected.location, NSMaxRange(expected)] {
                let caret = try #require(map.editorUTF16Offset(forSourceUTF16Offset: sourceCaret))
                let snapshot = try MarkdownWritingContextProjection.capture(
                    source: source, selections: [.init(anchor: caret, head: caret)], mode: .selectionOrCurrentLine)
                #expect(snapshot.source.utf8.elementsEqual(source.utf8))
                #expect(snapshot.excerpt.utf8.elementsEqual(line.utf8))
                #expect(snapshot.sourceRange.utf16LowerBound == expected.location)
                #expect(snapshot.sourceRange.utf16UpperBound == NSMaxRange(expected))
                #expect(snapshot.sourceRange.line == index + 1)
                #expect(snapshot.sourceRange.endLine == index + 1)
                #expect(snapshot.sourceRange.column == (index == 0 ? 2 : 1))
                #expect(snapshot.sourceRange.endColumn == line.utf16.count + (index == 0 ? 2 : 1))
            }
        }
    }

    @Test("Blank lines and a trailing empty line never fall back to preceding prose")
    func blankCurrentLine() throws {
        let cases: [(String, Int)] = [
            ("", 0), ("\u{FEFF}", 1), ("\u{FEFF}\r\nLater", 1),
            ("Earlier\n\nLater", 8), ("Earlier\r\n \t\r\nLater", 10),
            ("Earlier\n", 8), ("Earlier\r\n", 9),
        ]
        for (source, sourceCaret) in cases {
            let caret = try #require(EditorSourceOffsetMap(source: source).editorUTF16Offset(forSourceUTF16Offset: sourceCaret))
            #expect(throws: RelatedMaterialsError.invalidSeed) {
                try MarkdownWritingContextProjection.capture(
                    source: source, selections: [.init(anchor: caret, head: caret)], mode: .selectionOrCurrentLine)
            }
        }
    }

    @Test(
        "Every capture mode prefers an exact cross-line selection in either direction",
        arguments: [
            MarkdownWritingContextCaptureMode.selectionOnly, .selectionOrCurrentLine, .selectionOrParagraph,
        ])
    func exactSelection(mode: MarkdownWritingContextCaptureMode) throws {
        let source = "\u{FEFF}Before\r\n控制😀 e\u{301}\r\nnext line\r\nAfter"
        let expectedText = "😀 e\u{301}\r\nnext"
        let expected = (source as NSString).range(of: expectedText)
        let map = EditorSourceOffsetMap(source: source)
        let lower = try #require(map.editorUTF16Offset(forSourceUTF16Offset: expected.location))
        let upper = try #require(map.editorUTF16Offset(forSourceUTF16Offset: NSMaxRange(expected)))
        for selection in [MarkdownEditorSelectionRange(anchor: lower, head: upper), .init(anchor: upper, head: lower)] {
            let snapshot = try MarkdownWritingContextProjection.capture(source: source, selections: [selection], mode: mode)
            #expect(snapshot.source.utf8.elementsEqual(source.utf8))
            #expect(snapshot.excerpt.utf8.elementsEqual(expectedText.utf8))
            #expect(snapshot.sourceRange.utf16LowerBound == expected.location)
            #expect(snapshot.sourceRange.utf16UpperBound == NSMaxRange(expected))
            #expect(snapshot.sourceRange.line == 2 && snapshot.sourceRange.column == 3)
            #expect(snapshot.sourceRange.endLine == 3 && snapshot.sourceRange.endColumn == 5)
        }
        let whitespace = try MarkdownWritingContextProjection.capture(
            source: "before\n \t\nafter", selections: [.init(anchor: 7, head: 9)], mode: mode)
        #expect(whitespace.excerpt == " \t")
    }

    @Test("Paragraph mode retains its multi-line range and trailing-newline fallback")
    func paragraphFallback() throws {
        let source = "Earlier paragraph.\r\n\r\nCurrent line.\r\nContinuation.\r\n"
        let caret = EditorSourceOffsetMap(source: source).editorUTF16Length
        let snapshot = try MarkdownWritingContextProjection.capture(
            source: source, selections: [.init(anchor: caret, head: caret)], mode: .selectionOrParagraph)
        #expect(snapshot.excerpt == "Current line.\r\nContinuation.\r\n")
        #expect(snapshot.sourceRange.line == 3)
        #expect(throws: RelatedMaterialsError.invalidSeed) {
            try MarkdownWritingContextProjection.capture(
                source: source, selections: [.init(anchor: caret, head: caret)], mode: .selectionOrCurrentLine)
        }
        #expect(throws: RelatedMaterialsError.selectionRequired) {
            try MarkdownWritingContextProjection.capture(
                source: source, selections: [.init(anchor: caret, head: caret)], mode: .selectionOnly)
        }
    }

    @Test("Current line follows source LF boundaries, not Unicode separators or visual wrapping")
    func logicalLine() throws {
        let line = "A\u{2028}B\u{2029}C " + String(repeating: "long prose ", count: 100)
        let source = "Before\n" + line + "\nAfter"
        let snapshot = try MarkdownWritingContextProjection.capture(
            source: source, selections: [.init(anchor: 9, head: 9)], mode: .selectionOrCurrentLine)
        #expect(snapshot.excerpt.utf8.elementsEqual(line.utf8))
        #expect(snapshot.sourceRange.line == 2 && snapshot.sourceRange.endLine == 2)
        #expect(snapshot.sourceRange.column == 1 && snapshot.sourceRange.endColumn == line.utf16.count + 1)
    }

    @Test("Capture rejects multiple selections, invalid offsets and unbounded lines")
    func invalidRanges() throws {
        let selectionSets: [[MarkdownEditorSelectionRange]] = [[], [.init(anchor: 0, head: 0), .init(anchor: 2, head: 2)]]
        for mode in [MarkdownWritingContextCaptureMode.selectionOnly, .selectionOrCurrentLine, .selectionOrParagraph] {
            for selections in selectionSets {
                #expect(throws: RelatedMaterialsError.selectionRequired) {
                    try MarkdownWritingContextProjection.capture(source: "text", selections: selections, mode: mode)
                }
            }
            for selection in [MarkdownEditorSelectionRange(anchor: -1, head: 0), .init(anchor: 0, head: 5)] {
                #expect(throws: RelatedMaterialsError.invalidSeed) {
                    try MarkdownWritingContextProjection.capture(source: "text", selections: [selection], mode: mode)
                }
            }
        }
        let source = String(repeating: "x", count: 32_001)
        #expect(throws: RelatedMaterialsError.invalidSeed) {
            try MarkdownWritingContextProjection.capture(
                source: source, selections: [.init(anchor: 1, head: 1)], mode: .selectionOrCurrentLine)
        }
        let selection = try MarkdownWritingContextProjection.capture(
            source: source, selections: [.init(anchor: 1, head: 2)], mode: .selectionOrCurrentLine)
        #expect(selection.excerpt == "x")
    }

}
