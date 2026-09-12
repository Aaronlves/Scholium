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
            selections: [.init(anchor: caret, head: caret)], paragraph: true)
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
            selections: [.init(anchor: 6, head: 2)], paragraph: true)
        #expect(value.excerpt == "test")
        #expect(throws: (any Error).self) {
            try MarkdownWritingContextProjection.capture(source: "test", selections: [.init(anchor: 0, head: 0), .init(anchor: 2, head: 2)], paragraph: true)
        }
    }

    @Test("Insertion transport retains both generation and exact caret")
    func insertionTransport() throws {
        let operation = MarkdownEditorOperation.insertReference(selection: .init(anchor: 9, head: 9), generation: 7, target: "自由")
        let data = try JSONEncoder().encode(operation)
        #expect(try JSONDecoder().decode(MarkdownEditorOperation.self, from: data) == operation)
        #expect(operation.serializesSourceMutation)
    }
}
