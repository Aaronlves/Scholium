import AppKit
import CoreText
import PDFKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("PDF toolbar underlap", .serialized)
@MainActor
struct PDFReaderToolbarUnderlapTests {
    @Test("The loaded pane scrolls beneath native chrome while initial text, selection and teardown retain their owners")
    func loadedPaneOwnsContinuousClipPlane() async throws {
        let data = try fixtureData()
        let id = UUID()
        let context = PDFReaderNoteContext(
            triptychID: UUID(), target: SourceAttachmentTarget(noteID: UUID(), vaultID: UUID(), relativePath: "underlap.md"),
            authoredPath: "../.scholium/attachments/files/underlap.pdf")
        let record = PortableAttachmentRecord(
            id: id, vaultID: nil, location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(id.uuidString)/underlap.pdf")))
        let snapshot = PDFReaderSnapshot(
            record: record, data: data,
            revision: PDFReaderRevision(fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
        let operations = ControlledPDFReaderOperations(notes: [context.target.noteID: snapshot])
        let reader = PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
        defer { reader.shutdown() }
        reader.follow(context, operations: operations)
        #expect(reader.setVisible(true))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while reader.document == nil || reader.isLoading, reader.error == nil, ContinuousClock.now < deadline { await Task.yield() }
        let document = try #require(reader.document)
        let surface = ScholiumSurfaceContainerViewController(
            contentViewController: NSHostingController(rootView: PDFReaderPane(controller: reader)),
            backgroundRole: .document, contentExtendsUnderToolbar: true)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.toolbar = NSToolbar(identifier: "SyntheticPDFToolbar")
        window.contentViewController = surface
        window.setContentSize(NSSize(width: 500, height: 650))
        defer {
            window.contentViewController = nil
            window.close()
        }
        var native: PDFReaderNativePDFView?
        while native == nil || (native?.bounds.height ?? 0) < 100, ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            surface.view.layoutSubtreeIfNeeded()
            native = findPDF(in: surface.view)
            try await Task.sleep(for: .milliseconds(10))
        }
        let view = try #require(native)
        defer { view.invalidate() }
        try #require(view.bounds.height > 100 && window.contentLayoutRect.height > 100)
        let scroll = try #require(view.documentView?.enclosingScrollView)
        let clip = scroll.contentView
        let initialInsets = scroll.contentInsets
        try assertUnderlap(view, scroll: scroll, window: window)
        #expect(!scroll.automaticallyAdjustsContentInsets)
        let page = try #require(document.page(at: 0))
        let selection = try #require(page.selection(for: NSRect(x: 20, y: 720, width: 500, height: 45)))
        #expect(selection.string?.contains("Synthetic top title") == true)
        view.setCurrentSelection(selection, animate: false)
        let initialText = view.convert(view.convert(selection.bounds(for: page), from: page), to: nil)
        #expect(initialText.maxY <= window.contentLayoutRect.maxY + 1)
        let initialBounds = clip.bounds
        var beneathToolbar = initialBounds.origin
        beneathToolbar.y += clip.isFlipped ? initialInsets.top + 30 : -initialInsets.top - 30
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: beneathToolbar, size: initialBounds.size)).origin)
        scroll.reflectScrolledClipView(clip)
        let scrolledText = view.convert(view.convert(selection.bounds(for: page), from: page), to: nil)
        #expect(scrolledText.maxY > window.contentLayoutRect.maxY)
        #expect(scroll.convert(clip.frame, to: nil).maxY > window.contentLayoutRect.maxY)
        let retainedOrigin = clip.bounds.origin
        for _ in 0..<3 {
            view.isHidden = true
            view.isHidden = false
            view.layout()
            #expect(clip.bounds.origin == retainedOrigin)
            #expect(view.currentSelection?.string == selection.string)
        }
        for width in [340.0, 580.0] {
            window.setContentSize(NSSize(width: width, height: 650))
            window.layoutIfNeeded()
            surface.view.layoutSubtreeIfNeeded()
            view.layout()
            try assertUnderlap(view, scroll: scroll, window: window)
            #expect(view.document === document && view.currentSelection?.string == selection.string)
        }
        // A covering native control receives its own event; the reader may
        // annotate only the exact paper target after that control departs.
        reader.selectTool(.comment)
        view.apply(reader)
        let paperPoint = view.convert(NSPoint(x: 300, y: 400), from: page)
        let windowPoint = view.convert(paperPoint, to: nil)
        try #require(window.contentLayoutRect.contains(windowPoint))
        let content = try #require(window.contentView)
        let coveredPoint = view.convert(paperPoint, to: content)
        let cover = NSView(frame: NSRect(x: coveredPoint.x - 20, y: coveredPoint.y - 20, width: 40, height: 40))
        content.addSubview(cover)
        let click = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        #expect(view.route(click) === click && reader.annotationDraft == nil)
        cover.removeFromSuperview()
        #expect(view.route(click) == nil && reader.annotationDraft != nil)
        reader.cancelComment()
        view.invalidate()
        #expect(scroll.automaticallyAdjustsContentInsets)
        #expect(scroll.contentInsets.bottom < initialInsets.bottom)
        #expect(await operations.saveCount == 0)
    }

    private func assertUnderlap(_ view: PDFReaderNativePDFView, scroll: NSScrollView, window: NSWindow) throws {
        let frame = scroll.convert(scroll.bounds, to: nil)
        let overlap = frame.maxY - window.contentLayoutRect.maxY
        #expect(overlap > 10)
        #expect(abs(scroll.contentInsets.top - overlap) <= 1)
        #expect(view.convert(view.bounds, to: nil).maxY > window.contentLayoutRect.maxY)
    }

    private func findPDF(in view: NSView) -> PDFReaderNativePDFView? {
        if let pdf = view as? PDFReaderNativePDFView { return pdf }
        return view.subviews.lazy.compactMap { findPDF(in: $0) }.first
    }

    private func fixtureData() throws -> Data {
        let bytes = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: bytes as CFMutableData))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let graphics = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        graphics.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 18, nil)
        let title = NSAttributedString(string: "Synthetic top title", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        graphics.textPosition = CGPoint(x: 30, y: 740)
        CTLineDraw(CTLineCreateWithAttributedString(title as CFAttributedString), graphics)
        graphics.endPDFPage()
        graphics.closePDF()
        return bytes as Data
    }
}
