import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Retained native Markdown session", .serialized)
struct NativeMarkdownEditorSessionTests {
    init() { _ = NSApplication.shared }

    @Test("Save acknowledgement preserves newer typing and advances only its disk base")
    func typingDuringSave() async throws {
        let session = MarkdownEditorSession()
        let original = "\u{FEFF}one\r\ntwo"
        session.loadDocument(original, documentID: "note", mode: .edit)
        let attachment = session.attachNativeView()
        defer { session.detachNativeView(attachmentID: attachment) }
        session.nativeEditor.insertText("!", replacementRange: NSRange(location: 7, length: 0))
        let snapshot = try await session.persistenceSnapshot(expectedRevision: DocumentFingerprint(content: original))
        session.nativeEditor.insertText("?", replacementRange: NSRange(location: 8, length: 0))
        let acknowledged = try await session.acknowledgePersistenceSnapshot(
            snapshot,
            committedText: snapshot.text, fingerprint: DocumentFingerprint(content: snapshot.text))
        #expect(acknowledged == .superseded)
        #expect(session.checkedSource.utf8.elementsEqual((original + "!?").utf8))
        #expect(session.startingFingerprint == DocumentFingerprint(content: original + "!").sha256)
        #expect(session.isDirty)
    }

    @Test("Detachment retains the exact source and the same Undo stack")
    func retainedNativeUndo() async throws {
        let session = MarkdownEditorSession()
        let original = "\u{FEFF}正文\r\n末尾"
        session.loadDocument(original, documentID: "note", mode: .edit)
        let first = session.attachNativeView()
        let editor = session.nativeEditor
        editor.insertText("!", replacementRange: NSRange(location: 5, length: 0))
        try await session.captureStateForViewReconstruction(suspendForDetachment: true)
        #expect(!editor.isEditable)
        session.detachNativeView(attachmentID: first)
        #expect(session.hasDetachedPersistenceSnapshot)
        let captured = try await session.persistenceSnapshot(expectedRevision: DocumentFingerprint(content: original))
        #expect(captured.text.utf8.elementsEqual((original + "!").utf8))
        _ = session.attachNativeView()
        #expect(session.nativeEditor === editor)
        editor.undo(nil)
        #expect(try await session.currentText().utf8.elementsEqual(original.utf8))
    }

    @Test("Reading preserves history and Chinese composition blocks saving")
    func readAndComposition() async throws {
        let session = MarkdownEditorSession()
        session.loadDocument("Hello ", documentID: "note", mode: .edit)
        _ = session.attachNativeView()
        session.nativeEditor.insertText("!", replacementRange: NSRange(location: 6, length: 0))
        session.setMode(.read)
        session.nativeEditor.undo(nil)
        #expect(try await session.currentText() == "Hello !")
        session.setMode(.edit)
        session.nativeEditor.undo(nil)
        #expect(try await session.currentText() == "Hello ")
        session.nativeEditor.setMarkedText(
            "zhong", selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: 6, length: 0))
        #expect(session.isComposing)
        await #expect(throws: MarkdownEditorSession.SessionError.self) { try await session.currentText() }
        session.nativeEditor.insertText("中文", replacementRange: session.nativeEditor.markedRange())
        #expect(try await session.currentText() == "Hello 中文")
    }

    @Test("A to B to A retains separate exact buffers and native histories")
    func independentDocuments() async throws {
        let a = MarkdownEditorSession()
        let b = MarkdownEditorSession()
        a.loadDocument("A\r\nfirst", documentID: "a", mode: .edit)
        b.loadDocument("B\nsecond", documentID: "b", mode: .edit)
        let attachedA = a.attachNativeView()
        a.nativeEditor.insertText("!", replacementRange: NSRange(location: 7, length: 0))
        try await a.captureStateForViewReconstruction(suspendForDetachment: true)
        a.detachNativeView(attachmentID: attachedA)
        let attachedB = b.attachNativeView()
        b.nativeEditor.insertText("?", replacementRange: NSRange(location: 8, length: 0))
        try await b.captureStateForViewReconstruction(suspendForDetachment: true)
        b.detachNativeView(attachmentID: attachedB)
        let reattachedA = a.attachNativeView()
        defer { a.detachNativeView(attachmentID: reattachedA) }
        a.nativeEditor.undo(nil)
        #expect(try await a.currentText() == "A\r\nfirst")
        #expect(try await b.currentText() == "B\nsecond?")
    }

    @Test("A stale host cannot detach the newly attached native editor")
    func staleHostDetachment() throws {
        let session = MarkdownEditorSession()
        session.loadDocument("retained", documentID: "note", mode: .edit)
        let old = session.attachNativeView()
        let current = session.attachNativeView()
        session.detachNativeView(attachmentID: old)
        #expect(session.hasAttachedNativeView)
        #expect(session.isCurrentAttachment(current))
        #expect(session.nativeEditor.isEditable)
        session.detachNativeView(attachmentID: current)
        #expect(!session.hasAttachedNativeView)
        #expect(!session.nativeEditor.isEditable)
    }

}
