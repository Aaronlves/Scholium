import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Passage action source boundaries")
struct DocumentPassageActionsTests {
    @Test("A complete visible selection keeps its anchor for the next reorganization")
    func visibleParagraphIdentity() throws {
        let source = "Paragraph 😀. ^kept\n\nFollowing."
        let document = NoteDocument(relativePath: "A.md", rawContent: source)
        let paragraph = try ParagraphAnchorPlanner.paragraph(in: document, atUTF16: 0)
        let complete = try #require(DocumentPassageSnapshot.capture(source: source, range: (source as NSString).range(of: "Paragraph 😀.")))
        let expanded = DocumentPassageSnapshot.includingParagraphIdentity(complete, paragraphSpan: paragraph)
        #expect(expanded.excerpt == "Paragraph 😀. ^kept")
        let partial = try #require(DocumentPassageSnapshot.capture(source: source, range: (source as NSString).range(of: "Paragraph")))
        let unchanged = DocumentPassageSnapshot.includingParagraphIdentity(partial, paragraphSpan: paragraph)
        #expect(unchanged.excerpt == partial.excerpt && unchanged.sourceRange == partial.sourceRange)
    }

    @Test("A captured passage retains exact BOM, CRLF and non-BMP coordinates")
    func exactSourceCapture() throws {
        let source = "\u{FEFF}---\r\ncustom: yes\r\n---\r\n\r\n甲 😀 e\u{301} text.\r\n\r\nUntouched."
        let selected = (source as NSString).range(of: "甲 😀 e\u{301} text.")
        let snapshot = try #require(DocumentPassageSnapshot.capture(source: source, range: selected))
        #expect(snapshot.source.utf8.elementsEqual(source.utf8))
        #expect(snapshot.sourceRange.line == 5)
        #expect(snapshot.sourceRange.utf16LowerBound == selected.location)
        #expect(snapshot.excerpt == "甲 😀 e\u{301} text.")
        #expect(DocumentPassageSnapshot.capture(source: source, range: .init(location: source.utf16.count, length: 1)) == nil)
        #expect(DocumentPassageSnapshot.capture(source: source, range: .init(location: 0, length: 0)) == nil)
    }

    @Test("Creating a link inserts only its marker without changing adjacent source")
    func anchorReplacementScope() throws {
        let source = "---\r\ncustom: 'kept'\r\n---\r\n\r\nA 😀 paragraph.\r\n\r\nFollowing.\r\n"
        let document = NoteDocument(relativePath: "Topic.md", rawContent: source)
        let location = (source as NSString).range(of: "A 😀 paragraph.").location
        let original = try ParagraphAnchorPlanner.paragraph(in: document, atUTF16: location)
        let plan = try ParagraphAnchorPlanner.ensureAnchor(in: document, atUTF16: location, id: "paragraph-one")
        let edit = try #require(plan.edits.first)
        let offset = String(decoding: Array(source.utf8)[..<edit.startUTF8], as: UTF8.self).utf16.count
        #expect(edit.startUTF8 == edit.endUTF8)
        #expect(offset == original.utf16UpperBound)
        let candidate = (source as NSString).replacingCharacters(in: .init(location: offset, length: 0), with: edit.replacement)
        #expect(candidate.utf8.elementsEqual(plan.candidateSource.utf8))
        #expect(candidate.hasPrefix("---\r\ncustom: 'kept'\r\n---\r\n\r\n"))
        #expect(candidate.hasSuffix("\r\n\r\nFollowing.\r\n"))
    }

    @Test("Composition prevents passage capture and formatting")
    @MainActor func composition() async throws {
        let session = MarkdownEditorSession()
        session.loadDocument("Paragraph", documentID: "fixture.md", mode: .edit)
        session.nativeEditor.setMarkedText(
            "pin", selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: 0, length: 0))
        #expect(session.isComposing)
        #expect(session.nativeContext().availableCommands.isEmpty)
        await #expect(throws: MarkdownEditorSession.SessionError.self) {
            try await session.passageSourceSnapshot(expectedSelections: session.currentValidSelectionRanges(), expectedGeneration: session.generation)
        }
    }
}
