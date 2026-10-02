import AppKit
import CoreText
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("PDF floating tools", .serialized)
@MainActor
struct PDFReaderFloatingToolsTests {
    @Test("The native capsule fits the pane and final-page text clears it without changing page spacing", arguments: [280.0, 500.0])
    func pageEndClearance(width: Double) async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let document = try #require(fixture.reader.document)
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        let window = makeWindow(view)
        defer {
            view.invalidate()
            window.close()
        }
        view.document = document
        view.layoutDocumentView()
        let scroll = try #require(view.documentView?.enclosingScrollView)
        let clip = scroll.contentView
        let originalInsets = scroll.contentInsets
        let originalAutomatic = scroll.automaticallyAdjustsContentInsets
        let margins = view.pageBreakMargins
        view.apply(fixture.reader)
        window.contentView?.layoutSubtreeIfNeeded()
        let tools = try #require(view.floatingTools)
        #expect(!tools.isAccessibilityElement())
        #expect(tools.style == .regular)
        #expect(tools.frame.width > 100 && tools.frame.width < width)
        #expect(abs(tools.frame.midX - view.bounds.midX) < 1)
        #expect(tools.frame.minY >= ScholiumMetrics.PDFReader.toolsBottomInset - 1)
        #expect(scroll === view.documentView?.enclosingScrollView && scroll.contentView === clip)
        #expect(!scroll.automaticallyAdjustsContentInsets)
        #expect(scroll.contentInsets.top == originalInsets.top)
        #expect(scroll.contentInsets.bottom >= tools.frame.height + ScholiumMetrics.PDFReader.toolsBottomInset)
        #expect(view.pageBreakMargins.top == margins.top && view.pageBreakMargins.bottom == margins.bottom)
        let lastPage = try #require(document.page(at: document.pageCount - 1))
        let lastLine = try #require(lastPage.selection(for: NSRect(x: 0, y: 0, width: 600, height: 35)))
        #expect(lastLine.string?.contains("final line") == true)
        view.setCurrentSelection(lastLine, animate: false)
        for factor in [view.scaleFactor, 1.1] {
            view.scaleFactor = factor
            view.layoutDocumentView()
            window.contentView?.layoutSubtreeIfNeeded()
            var end = clip.bounds
            end.origin.y = clip.isFlipped ? 100_000 : -100_000
            clip.scroll(to: clip.constrainBoundsRect(end).origin)
            scroll.reflectScrolledClipView(clip)
            let textFrame = view.convert(lastLine.bounds(for: lastPage), from: lastPage)
            #expect(textFrame.minY >= tools.frame.maxY - 1)
            try assertSelection(view.currentSelection, matches: lastLine)
        }
        view.invalidate()
        #expect(scroll.automaticallyAdjustsContentInsets == originalAutomatic)
        #expect(scroll.contentInsets.bottom == originalInsets.bottom)
        #expect(tools.isHidden && tools.isAccessibilityHidden())
    }

    @Test("Tool actions preserve the PDF selection, follow capability changes and revoke hidden or dismantled input")
    func toolAdmissionAndSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let window = makeWindow(view)
        defer {
            view.invalidate()
            window.close()
        }
        view.apply(fixture.reader)
        window.contentView?.layoutSubtreeIfNeeded()
        let tools = try #require(view.floatingTools)
        let select = try button("select", in: tools)
        let highlight = try button("highlight", in: tools)
        let comment = try button("comment", in: tools)
        for button in [select, highlight, comment] {
            #expect(button.image != nil && button.symbolConfiguration != nil)
            #expect(!button.isBordered)
        }
        let zoom = try #require(findButton("scholium.pdf.zoom", in: tools))
        for button in [select, highlight, comment, zoom] {
            let host = try #require(window.contentView)
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: host.superview)
            #expect(host.hitTest(point) === button)
        }
        let document = try #require(view.document)
        let selection = try #require(document.page(at: 0)?.selection(for: NSRect(x: 0, y: 0, width: 600, height: 35)))
        view.setCurrentSelection(selection, animate: false)
        let position = view.currentDestination
        highlight.performClick(nil)
        #expect(fixture.reader.tool == .highlight && highlight.state == .on && select.state == .off)
        #expect(view.document === document)
        try assertSelection(view.currentSelection, matches: selection)
        #expect(view.currentDestination?.page === position?.page)
        #expect(await fixture.operations.saveCount == 0)
        let departure = fixture.reader.beginDeparture()
        view.apply(fixture.reader)
        #expect(!highlight.isEnabled && !comment.isEnabled && !select.isEnabled)
        let staleAction = try #require(comment.action)
        #expect(NSApplication.shared.sendAction(staleAction, to: comment.target, from: comment))
        #expect(fixture.reader.tool == .highlight)
        fixture.reader.endDeparture(departure)
        view.isHidden = true
        #expect(NSApplication.shared.sendAction(staleAction, to: comment.target, from: comment))
        #expect(fixture.reader.tool == .highlight)
        view.isHidden = false
        view.apply(fixture.reader)
        comment.performClick(nil)
        #expect(fixture.reader.tool == .comment && fixture.reader.annotationDraft == nil)
        view.invalidate()
        #expect(comment.target == nil && comment.action == nil)
        #expect(NSApplication.shared.sendAction(staleAction, to: tools, from: comment))
        #expect(fixture.reader.tool == .comment)
    }

    private func button(_ tool: String, in view: NSView) throws -> NSButton {
        try #require(findButton("scholium.pdf.tool.\(tool)", in: view), "Missing native tool \(tool)")
    }

    @Test("Zero-sized insertion, native resizing, hiding and window removal refresh tool admission")
    func presentationLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let view = PDFReaderNativePDFView(frame: .zero)
        let host = PDFReaderNativeHostView(pdfView: view)
        view.apply(fixture.reader)
        let tools = try #require(view.floatingTools)
        let highlight = try button("highlight", in: tools)
        let action = try #require(highlight.action)
        #expect(!highlight.isEnabled)
        host.setFrameSize(NSSize(width: 400, height: 600))
        let window = makeWindow(host)
        defer {
            view.invalidate()
            window.close()
        }
        view.setFrameSize(host.bounds.size)
        #expect(highlight.isEnabled)
        view.isHidden = true
        #expect(!highlight.isEnabled)
        #expect(NSApplication.shared.sendAction(action, to: tools, from: highlight))
        #expect(fixture.reader.tool == .select)
        view.isHidden = false
        #expect(highlight.isEnabled)
        view.removeFromSuperview()
        #expect(!highlight.isEnabled)
        #expect(tools.isHidden)
        #expect(NSApplication.shared.sendAction(action, to: tools, from: highlight))
        #expect(fixture.reader.tool == .select)
        host.addSubview(view)
        #expect(highlight.isEnabled)
        highlight.performClick(nil)
        #expect(fixture.reader.tool == .highlight && highlight.state == .on)
    }

    @Test("The native key-view loop traverses floating tools in both directions")
    func nativeKeyTraversal() async throws {
        let fixture = try Fixture()
        defer { fixture.reader.shutdown() }
        try await fixture.load()
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let window = makeWindow(view)
        defer {
            view.invalidate()
            window.close()
        }
        view.apply(fixture.reader)
        window.contentView?.layoutSubtreeIfNeeded()
        let tools = try #require(view.floatingTools)
        let select = try button("select", in: tools)
        let highlight = try button("highlight", in: tools)
        let comment = try button("comment", in: tools)
        window.recalculateKeyViewLoop()
        #expect(window.makeFirstResponder(select))
        window.selectNextKeyView(select)
        #expect(window.firstResponder === highlight)
        window.selectNextKeyView(highlight)
        #expect(window.firstResponder === comment)
        window.selectPreviousKeyView(comment)
        #expect(window.firstResponder === highlight)
        #expect(fixture.reader.annotationDraft == nil && fixture.reader.tool == .select)
    }

    private func assertSelection(_ actual: PDFSelection?, matches expected: PDFSelection) throws {
        let actual = try #require(actual)
        #expect(actual.string == expected.string)
        #expect(actual.pages.elementsEqual(expected.pages, by: { $0 === $1 }))
        for page in expected.pages { #expect(actual.bounds(for: page) == expected.bounds(for: page)) }
    }

    private func findButton(_ identifier: String, in view: NSView) -> NSButton? {
        for child in view.subviews {
            if let button = child as? NSButton, button.accessibilityIdentifier() == identifier { return button }
            if let button = findButton(identifier, in: child) { return button }
        }
        return nil
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = (view as? PDFReaderNativePDFView).map(PDFReaderNativeHostView.init(pdfView:)) ?? view
        window.layoutIfNeeded()
        return window
    }

    @MainActor
    private struct Fixture {
        let reader: PDFReaderController
        let operations: ControlledPDFReaderOperations
        let context: PDFReaderNoteContext

        init() throws {
            let bytes = NSMutableData()
            let consumer = try #require(CGDataConsumer(data: bytes as CFMutableData))
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            let graphics = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            for index in 1...2 {
                graphics.beginPDFPage(nil)
                let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
                let text = NSAttributedString(
                    string: "Synthetic final line \(index)", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                graphics.textPosition = CGPoint(x: 30, y: 5)
                CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), graphics)
                graphics.endPDFPage()
            }
            graphics.closePDF()
            let data = bytes as Data
            let id = UUID()
            let record = PortableAttachmentRecord(
                id: id, vaultID: nil, location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(id.uuidString)/floating.pdf")))
            let snapshot = PDFReaderSnapshot(
                record: record, data: data,
                revision: PDFReaderRevision(fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
            context = PDFReaderNoteContext(
                triptychID: UUID(), target: SourceAttachmentTarget(noteID: UUID(), vaultID: UUID(), relativePath: "synthetic-floating.md"),
                authoredPath: "../.scholium/attachments/files/floating.pdf")
            operations = ControlledPDFReaderOperations(notes: [context.target.noteID: snapshot])
            reader = PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
        }

        func load() async throws {
            reader.follow(context, operations: operations)
            #expect(reader.setVisible(true))
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while reader.document == nil || reader.isLoading, reader.error == nil, ContinuousClock.now < deadline { await Task.yield() }
            try #require(reader.document != nil && !reader.isLoading && reader.error == nil)
        }
    }
}
