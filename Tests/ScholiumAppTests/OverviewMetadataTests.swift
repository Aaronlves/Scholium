import AppKit
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Overview continuous Metadata") @MainActor
struct OverviewMetadataTests {
    private func session() -> OverviewMetadataSession {
        let session = OverviewMetadataSession()
        session.configure(note: .syntheticPreview(relativePath: "Fixture.md", rawContent: "# Fixture\n", vaultRole: .sourceCorpus), catalog: .builtIn, visible: ["type", "authors", "publication_date"])
        return session
    }

    @Test("A blur captures its value before later typing and commits with acknowledged revisions")
    func capturedCommit() async throws {
        let session = session()
        var stored: [String: YAMLValue] = [:]
        var revisions: [DocumentFingerprint?] = []
        session.save = { values, revision in
            revisions.append(revision); stored = values
            return DocumentFingerprint(content: "revision-\(revisions.count)")
        }
        session.edit("publication_date") { $0.text = "2026" }
        session.requestCommit()
        session.edit("publication_date") { $0.text = "2027" }
        for _ in 0..<5 { await Task.yield() }
        #expect(stored["publication_date"] == .string("2026"))
        #expect(session.drafts["publication_date"]?.text == "2027")
        try await session.flush()
        #expect(stored["publication_date"] == .string("2027"))
        #expect(revisions == [nil, DocumentFingerprint(content: "revision-1")])
    }

    @Test("Committed Metadata supports durable Undo and Redo")
    func committedUndoRedo() async throws {
        let session = session()
        var stored: [String: YAMLValue] = [:]
        session.save = { values, _ in stored = values; return DocumentFingerprint(content: String(describing: values)) }
        session.edit("publication_date") { $0.text = "2030" }
        session.requestCommit()
        try await session.undoCommitted()
        #expect(stored["publication_date"] == nil)
        #expect(session.undoManager.canRedo)
        try await session.redoCommitted()
        #expect(stored["publication_date"] == .string("2030"))
    }

    @Test("A revision failure retains the draft and composition blocks departure")
    func conflictAndComposition() async throws {
        let session = session()
        var attempts = 0
        session.save = { _, _ in attempts += 1; throw NoteMetadataError.revisionConflict(UUID()) }
        session.edit("publication_date") { $0.text = "2031" }
        session.composing.insert("publication_date")
        await #expect(throws: (any Error).self) { try await session.flush() }
        #expect(attempts == 0)
        session.composing.removeAll()
        await #expect(throws: (any Error).self) { try await session.flush() }
        #expect(session.drafts["publication_date"]?.text == "2031")
        #expect(session.baseline["publication_date"] == nil)
    }

    @Test("Native Tab transfers to the next name before the next character")
    func nativeNameTraversal() async throws {
        _ = NSApplication.shared
        let host = MetadataFieldsHost()
        host.session.configure(note: .syntheticPreview(relativePath: "Fixture.md", rawContent: "# Fixture\n", vaultRole: .sourceCorpus), catalog: .builtIn, visible: ["authors", "publication_date", "type"])
        host.session.save = { values, _ in DocumentFingerprint(content: String(describing: values)) }
        host.refresh()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        func inputs(_ view: NSView) -> [MetadataTextField] {
            (view as? MetadataTextField).map { [$0] } ?? view.subviews.flatMap(inputs)
        }
        let names = inputs(host)
        let family = try #require(names.first { $0.identity.hasSuffix(".family") })
        let given = try #require(names.first { $0.identity.hasSuffix(".given") })
        let date = try #require(names.first { $0.identity == "publication_date" })
        let initialFamilyFrame = family.convert(family.bounds, to: host)
        let initialGivenFrame = given.convert(given.bounds, to: host)
        #expect(abs(initialFamilyFrame.minX - date.convert(date.bounds, to: host).minX) < 0.5)
        #expect(window.makeFirstResponder(family))
        let editor = try #require(family.currentEditor() as? NSTextView)
        editor.insertText("Example", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.insertTab(nil)
        let next = try #require(given.currentEditor() as? NSTextView)
        next.insertText("Ada", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(family.stringValue == "Example")
        #expect(given.stringValue == "Ada")
        #expect(window.makeFirstResponder(host))
        host.refresh()
        host.layoutSubtreeIfNeeded()
        let retained = try #require(inputs(host).first { $0.identity.hasSuffix(".family") })
        #expect(retained === family)
        #expect(retained.stringValue == "Example")
        #expect(given.stringValue == "Ada")
        #expect(family.convert(family.bounds, to: host) == initialFamilyFrame)
        #expect(given.convert(given.bounds, to: host) == initialGivenFrame)
        #expect(family.frame.minX < given.frame.minX)
        #expect(abs(family.frame.width - given.frame.width) < 0.5)
        #expect(window.makeFirstResponder(family))
        let reopenedEditor = try #require(family.currentEditor() as? NSTextView)
        try await host.session.flush()
        reopenedEditor.selectAll(nil)
        reopenedEditor.insertText("Changed", replacementRange: NSRange(location: NSNotFound, length: 0))
        reopenedEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(family.currentEditor() === reopenedEditor)
        #expect(family.stringValue == "Example")
        #expect(reopenedEditor.string == "Example")
        #expect(inputs(host).filter { $0.identity.hasSuffix(".family") }.count == 1)
        #expect(given.stringValue == "Ada")
    }
}
