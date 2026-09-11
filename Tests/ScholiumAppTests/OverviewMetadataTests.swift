import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Overview continuous Metadata") @MainActor
struct OverviewMetadataTests {
    private func session() -> OverviewMetadataSession {
        let session = OverviewMetadataSession()
        session.configure(
            note: .syntheticPreview(relativePath: "Fixture.md", rawContent: "# Fixture\n", vaultRole: .sourceCorpus), catalog: .builtIn,
            visible: ["type", "authors", "publication_date"])
        return session
    }

    @Test("A blur captures its value before later typing and commits with acknowledged revisions")
    func capturedCommit() async throws {
        let session = session()
        var stored: [String: YAMLValue] = [:]
        var revisions: [DocumentFingerprint?] = []
        session.save = { values, revision in
            revisions.append(revision)
            stored = values
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
        session.save = { values, _ in
            stored = values
            return DocumentFingerprint(content: String(describing: values))
        }
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
        session.save = { _, _ in
            attempts += 1
            throw NoteMetadataError.revisionConflict(UUID())
        }
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
        host.session.configure(
            note: .syntheticPreview(relativePath: "Fixture.md", rawContent: "# Fixture\n", vaultRole: .sourceCorpus), catalog: .builtIn,
            visible: ["authors", "publication_date", "type"])
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
    @Test("Narrow Metadata reflows long values without replacing the active native editor")
    func nativeFieldReflow() throws {
        _ = NSApplication.shared
        let host = MetadataFieldsHost()
        let text = String(repeating: "A long source title with mixed 中文 content. ", count: 8)
        host.session.configure(
            note: .syntheticPreview(
                relativePath: "Fixture.md", rawContent: "# Fixture\n",
                vaultRole: .sourceCorpus, managedMetadata: ["title": .string(text)]),
            catalog: .builtIn, visible: ["title", "authors", "publication_date", "type"])
        host.refresh()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let title = try #require(descendants(host, as: MetadataTextField.self).first { $0.key == "title" })
        let wideHeight = title.frame.height
        #expect(window.makeFirstResponder(title))
        let editor = try #require(title.currentEditor())
        window.setContentSize(NSSize(width: 280, height: 800))
        host.layoutSubtreeIfNeeded()
        #expect(title.currentEditor() === editor)
        #expect(title.stringValue == text)
        #expect(title.frame.height > wideHeight)
        for field in descendants(host, as: MetadataTextField.self) {
            // AppKit alignment rects exclude native text-cell optical insets.
            let frame = field.convert(field.alignmentRect(forFrame: field.bounds), to: host)
            #expect(frame.minX >= 0 && frame.maxX <= host.bounds.width + 0.5, Comment(rawValue: "\(field.identity): \(frame), host \(host.bounds)"))
            #expect(field.placeholderString?.isEmpty == false)
        }
    }

    @Test("Adding an empty author focuses its name without writing placeholder Metadata")
    func addAuthorKeepsEmptyInputLocal() async throws {
        _ = NSApplication.shared
        let host = MetadataFieldsHost()
        host.session.configure(
            note: .syntheticPreview(relativePath: "Fixture.md", rawContent: "# Fixture\n", vaultRole: .sourceCorpus),
            catalog: .builtIn, visible: ["authors"])
        var writes = 0
        host.session.save = { _, _ in
            writes += 1
            return DocumentFingerprint(content: "unexpected")
        }
        host.refresh()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        let add = try #require(descendants(host, as: MetadataActionButton.self).first { $0.identifier?.rawValue == "authors.add" })
        add.performClick(nil)
        host.layoutSubtreeIfNeeded()
        let families = descendants(host, as: MetadataTextField.self).filter { $0.identity.hasSuffix(".family") }
        #expect(families.count == 2)
        #expect(families.last?.currentEditor() != nil)
        let newGiven = try #require(descendants(host, as: MetadataTextField.self).last { $0.identity.hasSuffix(".given") })
        #expect(window.makeFirstResponder(newGiven))
        let editor = try #require(newGiven.currentEditor() as? NSTextView)
        editor.insertText("OnlyGiven", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(descendants(host, as: MetadataTextField.self).filter { $0.identity.hasSuffix(".family") }.count == 1)
        #expect(families.first?.currentEditor() != nil)
        try await host.session.flush()
        #expect(writes == 0)
    }

    @Test("Boolean Metadata uses an accessible native checkbox and commits its selected value")
    func nativeBooleanField() async throws {
        let host = MetadataFieldsHost()
        let catalog = NoteMetadataCatalog(customFieldsByRole: [
            .paperAnalysis: [.init(key: "checked", valueKind: .boolean, label: "Checked")]
        ])
        host.session.configure(
            note: .syntheticPreview(
                relativePath: "Fixture.md", rawContent: "# Fixture\n",
                vaultRole: .sourceCorpus, managedMetadata: ["checked": .boolean(true)]), catalog: catalog, visible: ["checked"])
        var stored: [String: YAMLValue] = [:]
        host.session.save = { values, _ in
            stored = values
            return DocumentFingerprint(content: "saved")
        }
        host.refresh()
        let checkbox = try #require(descendants(host, as: MetadataToggleButton.self).first)
        #expect(checkbox.state == .on)
        #expect(checkbox.accessibilityLabel() == "Checked")
        checkbox.performClick(nil)
        try await host.session.flush()
        #expect(stored["checked"] == .boolean(false))
    }

    private func descendants<T: NSView>(_ view: NSView, as type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, as: type) }
    }

}
