import AppKit
import Combine
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("PDF native presentation activity", .serialized)
@MainActor
struct PDFReaderPresentationActivityTests {
    @Test("Nested native presentations publish synchronously and release independently")
    func nestedPresentationTokens() throws {
        let activity = PDFReaderPresentationActivity()
        let other = PDFReaderPresentationActivity()
        var values: [Bool] = []
        let observation = activity.$isActive.sink { values.append($0) }
        defer { observation.cancel() }
        let first = try #require(activity.begin())
        #expect(values == [false, true])
        let second = try #require(activity.begin())
        let foreign = try #require(other.begin())
        activity.end(foreign)
        activity.end(first)
        activity.end(first)
        #expect(activity.isActive && values == [false, true])
        activity.end(second)
        #expect(!activity.isActive && values == [false, true, false])
        other.end(foreign)
    }

    @Test("Menu and nested overflow own separate pins and cancellation cannot leak them")
    func menuTrackingOwnership() throws {
        let reader = makeReader()
        defer { reader.shutdown() }
        let owner = PDFReaderCommandMenu(controller: reader, kind: .actions)
        defer { owner.invalidate() }
        let overflow = owner.makeOverflowMenu()
        owner.menuWillOpen(owner.menu)
        owner.menuWillOpen(owner.menu)
        owner.menuWillOpen(overflow)
        owner.menuDidClose(owner.menu)
        #expect(reader.presentationActivity.isActive)
        owner.menuDidClose(overflow)
        #expect(!reader.presentationActivity.isActive)
        owner.menuWillOpen(owner.menu)
        owner.menuWillOpen(overflow)
        owner.cancelTracking()
        #expect(!reader.presentationActivity.isActive)
        owner.menuDidClose(overflow)
        owner.menuWillOpen(owner.menu)
        owner.invalidate()
        owner.menuWillOpen(owner.menu)
        #expect(!reader.presentationActivity.isActive)
    }

    @Test("Menu retargeting releases only its old window's pins")
    func retargetingKeepsWindowIsolation() throws {
        let first = makeReader()
        let second = makeReader()
        defer {
            first.shutdown()
            second.shutdown()
        }
        let owner = PDFReaderCommandMenu(controller: first, kind: .zoom)
        defer { owner.invalidate() }
        owner.menuWillOpen(owner.menu)
        let unrelated = try #require(first.presentationActivity.begin())
        owner.update(controller: second)
        #expect(first.presentationActivity.isActive && !second.presentationActivity.isActive)
        first.presentationActivity.end(unrelated)
        #expect(!first.presentationActivity.isActive)
        owner.menuWillOpen(owner.menu)
        #expect(second.presentationActivity.isActive && !first.presentationActivity.isActive)
        owner.menuDidClose(owner.menu)
        #expect(!second.presentationActivity.isActive)
    }

    @Test("Page field-editor focus pins before typing, preserves drafts and releases independently from overflow")
    func toolbarAndPageDraftOwnership() async throws {
        let fixture = try ReaderFixture()
        let reader = fixture.reader
        defer { reader.shutdown() }
        try await fixture.load(0)
        let (toolbar, window, page, otherField) = try makeToolbarWindow(reader)
        defer {
            toolbar.invalidate()
            window.close()
        }
        let menuItem = try #require(toolbar.item(for: PDFReaderToolbarController.compactID) as? NSMenuToolbarItem)
        var beganEditing = false
        let editing = NotificationCenter.default.publisher(for: NSControl.textDidBeginEditingNotification, object: page)
            .sink { _ in beganEditing = true }
        defer { editing.cancel() }
        toolbar.menuWillOpen(menuItem.menu)
        #expect(window.makeFirstResponder(page))
        let editor = try #require(page.currentEditor() as? NSTextView)
        #expect(window.firstResponder === editor && !beganEditing)
        updateWindow(window)
        toolbar.menuDidClose(menuItem.menu)
        #expect(reader.presentationActivity.isActive)
        editor.string = "123"
        toolbar.refresh()
        updateWindow(window)
        #expect(editor.string == "123" && reader.presentationActivity.isActive)
        editor.setMarkedText("12", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: 0, length: 3))
        let marked = editor.markedRange()
        let text = editor.string
        toolbar.refresh()
        updateWindow(window)
        #expect(editor.hasMarkedText() && editor.markedRange() == marked && editor.string == text)
        editor.unmarkText()
        #expect(window.makeFirstResponder(otherField))
        #expect(page.currentEditor() == nil)
        updateWindow(window)
        #expect(!reader.presentationActivity.isActive)
        toolbar.menuWillOpen(menuItem.menu)
        #expect(window.makeFirstResponder(page))
        updateWindow(window)
        toolbar.invalidate()
        updateWindow(window)
        #expect(!reader.presentationActivity.isActive)
    }

    @Test("Hide and source replacement revoke surviving page focus without stale window updates repinning")
    func pageFocusCannotReviveDepartedReader() async throws {
        let fixture = try ReaderFixture()
        let reader = fixture.reader
        defer { reader.shutdown() }
        try await fixture.load(0)
        let (toolbar, window, page, _) = try makeToolbarWindow(reader)
        defer {
            toolbar.invalidate()
            window.close()
        }
        #expect(window.makeFirstResponder(page))
        updateWindow(window)
        #expect(reader.presentationActivity.isActive)
        #expect(reader.setVisible(false))
        toolbar.refresh()
        updateWindow(window)
        #expect(!reader.presentationActivity.isActive)
        #expect(reader.setVisible(true))
        toolbar.refresh()
        updateWindow(window)
        #expect(!reader.presentationActivity.isActive)
        #expect(window.makeFirstResponder(nil))
        updateWindow(window)
        #expect(window.makeFirstResponder(page))
        updateWindow(window)
        #expect(reader.presentationActivity.isActive)
        try await fixture.load(1)
        toolbar.refresh()
        updateWindow(window)
        toolbar.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: page))
        #expect(!reader.presentationActivity.isActive)
        #expect(window.makeFirstResponder(nil))
        updateWindow(window)
        #expect(window.makeFirstResponder(page))
        updateWindow(window)
        #expect(reader.presentationActivity.isActive)
        window.toolbar = nil
        toolbar.refresh()
        updateWindow(window)
        toolbar.controlTextDidBeginEditing(Notification(name: NSControl.textDidBeginEditingNotification, object: page))
        #expect(!reader.presentationActivity.isActive)
    }

    @Test("Canceled departure restores the same focused page editor's pin and unsubmitted text")
    func pageFocusResumesAfterCanceledDeparture() async throws {
        let fixture = try ReaderFixture()
        let reader = fixture.reader
        defer { reader.shutdown() }
        try await fixture.load(0)
        let (toolbar, window, page, _) = try makeToolbarWindow(reader)
        defer {
            toolbar.invalidate()
            window.close()
        }
        #expect(window.makeFirstResponder(page))
        let editor = try #require(page.currentEditor() as? NSTextView)
        editor.string = "2"
        updateWindow(window)
        #expect(reader.presentationActivity.isActive)
        let context = reader.context
        let document = reader.document
        let departure = reader.beginDeparture()
        toolbar.refresh()
        updateWindow(window)
        #expect(!reader.presentationActivity.isActive)
        #expect(page.currentEditor() === editor && window.firstResponder === editor && editor.string == "2")
        reader.endDeparture(departure)
        toolbar.refresh()
        updateWindow(window)
        #expect(reader.presentationActivity.isActive)
        #expect(page.currentEditor() === editor && window.firstResponder === editor && editor.string == "2")
        #expect(reader.context == context && reader.document === document)
    }

    @Test("Reader shutdown permanently revokes presentation tokens")
    func shutdownRevokesTokens() throws {
        let reader = makeReader()
        let token = try #require(reader.presentationActivity.begin())
        reader.shutdown()
        #expect(!reader.presentationActivity.isActive)
        #expect(reader.presentationActivity.begin() == nil)
        reader.presentationActivity.end(token)
        #expect(!reader.presentationActivity.isActive)
    }

    private func makeReader() -> PDFReaderController {
        .init(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
    }

    private func updateWindow(_ window: NSWindow) {
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
    }

    private func makeToolbarWindow(_ reader: PDFReaderController) throws -> (PDFReaderToolbarController, NSWindow, NSTextField, NSTextField) {
        let toolbar = PDFReaderToolbarController(controller: reader, presentationDidChange: {})
        let group = try #require(toolbar.item(for: PDFReaderToolbarController.navigationID) as? NSToolbarItemGroup)
        let pageContent = try #require(group.subitems.compactMap { $0.view as? NSStackView }.first)
        let page = try #require(pageContent.views.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "scholium.pdf.page" })
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        pageContent.frame = NSRect(origin: NSPoint(x: 20, y: 60), size: pageContent.fittingSize)
        host.addSubview(pageContent)
        let otherField = NSTextField(frame: NSRect(x: 20, y: 10, width: 120, height: 24))
        host.addSubview(otherField)
        let window = NSWindow(contentRect: host.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        let nativeToolbar = NSToolbar(identifier: "synthetic.pdf.focus.\(UUID().uuidString)")
        window.toolbar = nativeToolbar
        toolbar.install(in: window, toolbar: nativeToolbar, readerView: nil)
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        return (toolbar, window, page, otherField)
    }

    @MainActor
    private struct ReaderFixture {
        let reader: PDFReaderController
        let operations: ControlledPDFReaderOperations
        let contexts: [PDFReaderNoteContext]

        init() throws {
            let document = PDFDocument()
            for _ in 0..<2 { document.insert(PDFPage(), at: document.pageCount) }
            let data = try #require(document.dataRepresentation())
            let triptych = UUID()
            contexts = (0..<2).map { index in
                PDFReaderNoteContext(
                    triptychID: triptych,
                    target: SourceAttachmentTarget(noteID: UUID(), vaultID: UUID(), relativePath: "synthetic-page-focus-\(index).md"),
                    authoredPath: "../.scholium/attachments/files/page-focus-\(index).pdf")
            }
            let snapshots = try contexts.map { context in
                let id = UUID()
                let record = PortableAttachmentRecord(
                    id: id, vaultID: nil,
                    location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(id.uuidString)/page-focus.pdf")))
                return (context.target.noteID, PDFReaderSnapshot(
                    record: record, data: data,
                    revision: PDFReaderRevision(fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1)))
            }
            operations = ControlledPDFReaderOperations(notes: Dictionary(uniqueKeysWithValues: snapshots))
            reader = PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
        }

        func load(_ index: Int) async throws {
            reader.follow(contexts[index], operations: operations)
            #expect(reader.setVisible(true))
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while reader.document == nil || reader.isLoading, reader.error == nil, ContinuousClock.now < deadline { await Task.yield() }
            try #require(reader.document != nil && !reader.isLoading && reader.error == nil)
        }
    }
}
