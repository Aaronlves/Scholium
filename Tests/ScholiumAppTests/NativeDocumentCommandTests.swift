import AppKit
import Foundation
import ScholiumEditor
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Native document command transactions", .serialized)
struct NativeDocumentCommandTests {
    init() {
        _ = NSApplication.shared
    }

    private func editor(_ source: String) throws -> ScholiumEditor.EditorTextView {
        let editor = ScholiumEditor.EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        editor.applyTheme(.default)
        editor.typewriterModeEnabled = false
        editor.viewMode = .edit
        editor.isEditable = true
        try editor.loadExactUTF8(Data(source.utf8))
        return editor
    }

    @Test(
        "Native inline commands preserve neighboring original bytes and undo",
        arguments: [
            ("bold", "**target**"), ("markdownComment", "%% target %%"),
            ("annotatedWikilink", "[[target]]{{Annotation}}"), ("insertInlineFootnote", "^[target]"),
            ("standardLink", "[target](https://example.com)"),
        ])
    func inlineCommands(value: (String, String)) throws {
        let source = "\u{FEFF}before\r\ntarget\nafter\r"
        let view = try editor(source)
        view.setSelectedRange((view.rawSource as NSString).range(of: "target"))
        try view.performDocumentCommand(named: value.0, argument: value.0 == "standardLink" ? "https://example.com" : nil)
        #expect(try view.exactUTF8ForSaving() == Data("\u{FEFF}before\r\n\(value.1)\nafter\r".utf8))
        view.undo(nil)
        #expect(try view.exactUTF8ForSaving() == Data(source.utf8))
    }

    @Test("Footnote moves the selected text to its definition in one exact transaction")
    func footnote() throws {
        let source = "\u{FEFF}before\r\ntarget\nafter"
        let view = try editor(source)
        view.setSelectedRange((view.rawSource as NSString).range(of: "target"))
        try view.performDocumentCommand(named: "insertFootnote")
        #expect(try view.exactUTF8ForSaving() == Data("\u{FEFF}before\r\n[^1]\nafter\r\n\r\n[^1]: target\r\n".utf8))
        view.undo(nil)
        #expect(try view.exactUTF8ForSaving() == Data(source.utf8))
    }

    @Test("Table alignment changes only the selected separator cell")
    func tableAlignment() throws {
        let source = "| A | B |\r\n|---|---|\n| one | two |\r"
        let view = try editor(source)
        view.setSelectedRange((view.rawSource as NSString).range(of: "one"))
        #expect(view.documentTablePosition?.column == 0)
        try view.performDocumentCommand(named: "tableAlignCenter")
        #expect(try view.exactUTF8ForSaving() == Data("| A | B |\r\n|:---:|---|\n| one | two |\r".utf8))
        view.undo(nil)
        #expect(try view.exactUTF8ForSaving() == Data(source.utf8))
    }

    @Test("Multi-range replacement is atomic and a single Undo preserves mixed endings")
    func replacementBatch() throws {
        let source = "\u{FEFF}one\r\ntwo\none"
        let view = try editor(source)
        try view.replaceProjectedRanges([(NSRange(location: 0, length: 3), "一"), (NSRange(location: 8, length: 3), "一")])
        #expect(try view.exactUTF8ForSaving() == Data("\u{FEFF}一\r\ntwo\n一".utf8))
        view.undo(nil)
        #expect(try view.exactUTF8ForSaving() == Data(source.utf8))
        #expect(throws: (any Error).self) {
            try view.replaceProjectedRanges([(NSRange(location: 0, length: 3), "changed"), (NSRange(location: 100, length: 1), "bad")])
        }
        #expect(try view.exactUTF8ForSaving() == Data(source.utf8))
        view.viewMode = .reading
        #expect(throws: ScholiumEditor.EditorTextView.DocumentCommandError.self) {
            try view.performDocumentCommand(named: "bold")
        }
        #expect(try view.exactUTF8ForSaving() == Data(source.utf8))
    }

    @Test("Find uses literal Unicode word boundaries and Replace All retains exact newline bytes")
    func findReplacement() async throws {
        let session = MarkdownEditorSession()
        let source = "\u{FEFF}cat\r\nCAT\nscatter\rcat"
        session.loadDocument(source, documentID: "test.md", mode: .edit)
        let query = DocumentFindQuery(query: "cat", replacement: "猫", caseSensitive: false, wholeWord: true, action: .replaceAll)
        let result = try await session.performDocumentFind(query)
        #expect(result.total == 0)
        #expect(try await session.currentText() == "\u{FEFF}猫\r\n猫\nscatter\r猫")
        session.nativeEditor.undo(nil)
        #expect(try await session.currentText() == source)
        let literal = DocumentFindQuery(query: "a.b", replacement: "", caseSensitive: true, wholeWord: false, action: .update)
        #expect(try NativeDocumentFind.matches(in: "a.b axb", query: literal) == [NSRange(location: 0, length: 3)])
    }

    @Test("Command availability rejects literal and frontmatter formatting and all read-mode edits")
    func commandProtection() throws {
        let session = MarkdownEditorSession()
        session.loadDocument("\u{FEFF}---\r\ntitle: test\r\n---\r\n\r\nbody\r\n\r\n```swift\r\nlet x = 1\r\n```", documentID: "test.md", mode: .edit)
        session.nativeEditor.setSelectedRange((session.nativeEditor.rawSource as NSString).range(of: "title"))
        #expect(!session.nativeCommandIsPermitted(.bold))
        #expect(session.nativeCommandIsPermitted(.pastePlain))
        session.nativeEditor.setSelectedRange((session.nativeEditor.rawSource as NSString).range(of: "let x"))
        #expect(!session.nativeCommandIsPermitted(.bold))
        session.nativeEditor.setSelectedRange((session.nativeEditor.rawSource as NSString).range(of: "body"))
        #expect(session.nativeCommandIsPermitted(.bold))
        session.setMode(.read)
        #expect(!session.nativeCommandIsPermitted(.bold))
    }

    @Test("Passage edits preserve the selected text when an earlier anchor changes source length")
    func passageSelectionMapping() async throws {
        let session = MarkdownEditorSession()
        let source = "\u{FEFF}first\r\n\r\nselected😀\nlast\r"
        session.loadDocument(source, documentID: "test.md", mode: .edit)
        let selected = (session.nativeEditor.rawSource as NSString).range(of: "selected😀")
        session.nativeEditor.setSelectedRange(selected)
        let insertion = (source as NSString).range(of: "first").upperBound
        try session.replacePassage(
            expectedText: source, fromUTF16: insertion, toUTF16: insertion,
            replacement: " ^anchor", preserveSelection: true)
        #expect((session.nativeEditor.rawSource as NSString).substring(with: session.nativeEditor.selectedRange()) == "selected😀")
        #expect(session.nativeEditor.selectedRange().location == selected.location + 8)
        #expect(try await session.currentText() == "\u{FEFF}first ^anchor\r\n\r\nselected😀\nlast\r")
        session.nativeEditor.undo(nil)
        #expect(try await session.currentText() == source)
        #expect(session.nativeEditor.selectedRange() == selected)
        session.nativeEditor.redo(nil)
        #expect(try await session.currentText() == "\u{FEFF}first ^anchor\r\n\r\nselected😀\nlast\r")
        #expect(session.nativeEditor.selectedRange() == NSRange(location: selected.location + 8, length: selected.length))
    }

    @Test("Writing context counts bare CR and mixed endings without interpreting Unicode separators")
    func writingContext() throws {
        let source = "\u{FEFF}first\rsecond\r\nthird\nfourth\u{2028}same line"
        let map = EditorSourceOffsetMap(source: source)
        for (line, word) in [(2, "second"), (3, "third"), (4, "fourth\u{2028}same line")] {
            let exact = (source as NSString).range(of: word)
            let caret = try #require(map.editorUTF16Offset(forSourceUTF16Offset: exact.location))
            let result = try MarkdownWritingContextProjection.capture(
                source: source, selections: [.init(anchor: caret, head: caret)], mode: .selectionOrCurrentLine)
            #expect(result.excerpt == word)
            #expect(result.sourceRange.line == line)
            #expect(result.sourceRange.utf16LowerBound == exact.location)
        }
    }
}
