import AppKit
import Combine
import CryptoKit
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Deterministic app callbacks and unshown-window layout are responsiveness
/// proxies. They do not measure onscreen first display or perceptual scrolling.
/// Keep this harness on APIs also present in the HEAD43 comparison source.
@Suite("PDF reader performance proxies", .serialized)
@MainActor
struct PDFReaderPerformanceTests {
    @Test("Native teardown releases a synchronously owned PDF view and document")
    func nativeResourceRelease() async throws {
        let fixture = try Fixture(data: fixtureData(pageCount: 12))
        let reader = fixture.reader
        defer { reader.shutdown() }
        reader.follow(fixture.context, operations: fixture.operations)
        #expect(reader.setVisible(true))
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while reader.document == nil || reader.isLoading, reader.error == nil, ContinuousClock.now < deadline { await Task.yield() }
        guard reader.document != nil, reader.error == nil else { throw CocoaError(.fileReadCorruptFile) }
        let references = ReleasedReferences()
        autoreleasepool {
            let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 500, height: 650))
            let host = PDFReaderNativeHostView(pdfView: view)
            let window = NSWindow(contentRect: view.bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            view.updatePresentation(reduceMotion: true)
            view.apply(reader)
            view.layout()
            if let selection = reader.document?.findString("scholium-early-needle", fromSelection: nil, withOptions: []) {
                view.setCurrentSelection(selection, animate: false)
                view.go(to: selection)
            }
            references.view = view
            references.tools = view.floatingTools
            references.document = reader.document
            references.window = window
            view.invalidate()
            reader.shutdown()
            window.contentView = nil
            window.close()
        }
        try await Task.sleep(for: .milliseconds(50))
        let released = references.view == nil && references.tools == nil && references.document == nil && references.window == nil
        #expect(released)
    }

    @Test("Synthetic reader readiness, callback cost, pane retention and release", arguments: [12, 800])
    func readerProxies(pageCount: Int) async throws {
        let data = try fixtureData(pageCount: pageCount)
        let (metrics, references) = try await measureReader(data: data, pageCount: pageCount)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !references.appOwnersAreReleased, ContinuousClock.now < deadline {
            drainNativeCallbacks()
            await Task.yield()
        }
        var result = metrics
        result["releasedReader"] = references.reader == nil
        result["releasedDocument"] = references.document == nil
        result["releasedNativeView"] = references.view == nil
        result["releasedHost"] = references.host == nil
        result["releasedTools"] = references.tools == nil
        result["releasedToolbar"] = references.toolbar == nil
        result["releasedWindow"] = references.window == nil
        result["sourceLabel"] = ProcessInfo.processInfo.environment["SCHOLIUM_PDF_PERFORMANCE_LABEL"] ?? "current"
        let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("PDF_READER_PERFORMANCE " + String(decoding: json, as: UTF8.self))
        // Async PDFKit proxy/evaluation lifetimes are diagnostic only. The
        // synchronous test above owns the complete native deallocation claim.
        #expect(references.appOwnersAreReleased, "Reader teardown must release its app and window owners.")
    }

    private func measureReader(data: Data, pageCount: Int) async throws -> ([String: Any], ReleasedReferences) {
        let fixture = try Fixture(data: data)
        let reader = fixture.reader
        defer { reader.shutdown() }
        let references = ReleasedReferences()
        references.reader = reader
        let modelStart = ContinuousClock.now
        reader.follow(fixture.context, operations: fixture.operations)
        #expect(reader.setVisible(true))
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while reader.document == nil || reader.isLoading, reader.error == nil, ContinuousClock.now < deadline {
            await Task.yield()
        }
        guard reader.document != nil, !reader.isLoading, reader.error == nil else { throw CocoaError(.fileReadCorruptFile) }
        let modelReadyMS = milliseconds(since: modelStart)
        references.document = reader.document

        // There is no running NSApplication event loop in this harness. Drain
        // Cocoa's temporary notifications and objects at each native boundary.
        let (view, host, window, toolbar) = autoreleasepool {
            let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 500, height: 650))
            let host = PDFReaderNativeHostView(pdfView: view)
            let window = NSWindow(contentRect: view.bounds, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            let nativeToolbar = NSToolbar(identifier: "scholium.pdf.performance.proxy")
            window.toolbar = nativeToolbar
            let toolbar = PDFReaderToolbarController(controller: reader, presentationDidChange: {})
            toolbar.install(in: window, toolbar: nativeToolbar, readerView: host)
            return (view, host, window, toolbar)
        }
        references.view = view
        references.host = host
        references.window = window
        references.toolbar = toolbar
        defer {
            autoreleasepool {
                toolbar.invalidate()
                view.invalidate()
                reader.shutdown()
                window.contentView = nil
                window.toolbar = nil
                window.close()
            }
        }

        let applyStart = ContinuousClock.now
        autoreleasepool {
            view.updatePresentation(reduceMotion: true)
            view.apply(reader)
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            view.layout()
        }
        let applyLayoutMS = milliseconds(since: applyStart)
        references.tools = view.floatingTools
        guard view.document === reader.document, reader.pageCount == pageCount else { throw CocoaError(.fileReadCorruptFile) }
        // Freeze PDFKit's auto-fit after the initial layout proxy. Repeated
        // callbacks compare a stable viewport rather than deferred auto-fit.
        autoreleasepool {
            view.layoutDocumentView()
            reader.zoom(1)
        }
        try await reader.flushPersistence()
        guard let clip = view.documentView?.enclosingScrollView?.contentView else { throw CocoaError(.fileReadCorruptFile) }
        let initialPage = reader.pageNumber
        let initialOrigin = clip.bounds.origin
        let initialScale = view.scaleFactor
        guard
            let selection = autoreleasepool(invoking: {
                reader.document?.findString("scholium-early-needle", fromSelection: nil, withOptions: [.caseInsensitive])
            })
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        autoreleasepool {
            view.setCurrentSelection(selection, animate: false)
            reader.selectionDidChange()
        }
        var publications = 0
        let observation = reader.objectWillChange.sink { publications += 1 }
        let callbacks = 1_000
        let callbackStart = ContinuousClock.now
        autoreleasepool {
            for _ in 0..<callbacks {
                NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
            }
        }
        let callbackMS = milliseconds(since: callbackStart)
        observation.cancel()
        #expect(reader.pageNumber == initialPage)
        #expect(clip.bounds.origin == initialOrigin)
        #expect(view.scaleFactor == initialScale)
        #expect(view.currentSelection?.string == selection.string)
        var selectionPublications = 0
        let selectionObservation = reader.objectWillChange.sink { selectionPublications += 1 }
        let selectionStart = ContinuousClock.now
        autoreleasepool {
            for _ in 0..<callbacks {
                NotificationCenter.default.post(name: .PDFViewSelectionChanged, object: view)
            }
        }
        let selectionMS = milliseconds(since: selectionStart)
        selectionObservation.cancel()
        #expect(reader.hasSelection && view.currentSelection?.string == selection.string)
        try await reader.flushPersistence()
        let saved = try #require(await fixture.operations.readingState(noteID: fixture.context.target.noteID, attachmentID: fixture.attachmentID))
        #expect(saved.pageIndex == initialPage - 1)
        #expect(abs(saved.scaleFactor - initialScale) < 1e-9)

        // This separately times explicit native projection. The callback loop
        // above includes synchronous notification work, not queued SwiftUI work.
        let projectionStart = ContinuousClock.now
        autoreleasepool {
            for _ in 0..<callbacks {
                view.apply(reader)
                toolbar.refresh()
            }
        }
        let projectionMS = milliseconds(since: projectionStart)
        #expect(abs(clip.bounds.origin.x - initialOrigin.x) < 0.001)
        #expect(abs(clip.bounds.origin.y - initialOrigin.y) < 0.001)
        #expect(view.currentSelection?.string == selection.string)

        let pageChangeStart = ContinuousClock.now
        autoreleasepool { reader.goToPage(3) }
        let pageChangeMS = milliseconds(since: pageChangeStart)
        #expect(reader.pageNumber == 3)
        try await reader.flushPersistence()
        let changed = try #require(await fixture.operations.readingState(noteID: fixture.context.target.noteID, attachmentID: fixture.attachmentID))
        #expect(changed.pageIndex == 2)
        let retainedOrigin = clip.bounds.origin
        let paneCycles = 20
        let paneStart = ContinuousClock.now
        autoreleasepool {
            for _ in 0..<paneCycles {
                #expect(reader.setVisible(false))
                view.isHidden = true
                #expect(reader.setVisible(true))
                view.isHidden = false
                view.apply(reader)
                view.layout()
            }
        }
        let paneMS = milliseconds(since: paneStart)
        let paneOriginDeltaX = clip.bounds.origin.x - retainedOrigin.x
        let paneOriginDeltaY = clip.bounds.origin.y - retainedOrigin.y
        #expect(await fixture.operations.loadCount == 1)
        #expect(reader.pageNumber == 3)
        let retainsDocument = view.document === reader.document
        #expect(retainsDocument)
        #expect(abs(clip.bounds.origin.x - retainedOrigin.x) < 0.5)
        #expect(abs(clip.bounds.origin.y - retainedOrigin.y) < 0.5)
        #expect(view.currentSelection?.string == selection.string)
        try await reader.flushPersistence()

        // Same-page reading points and zoom remain private session authority,
        // even when the public page number does not change.
        let beforeScroll = try #require(await fixture.operations.readingState(noteID: fixture.context.target.noteID, attachmentID: fixture.attachmentID))
        autoreleasepool {
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: clip.bounds.origin.y + 24))
            reader.viewPositionDidChange()
        }
        try await reader.flushPersistence()
        let afterScroll = try #require(await fixture.operations.readingState(noteID: fixture.context.target.noteID, attachmentID: fixture.attachmentID))
        #expect(afterScroll.pageIndex == beforeScroll.pageIndex)
        #expect(afterScroll.pointX != beforeScroll.pointX || afterScroll.pointY != beforeScroll.pointY)
        autoreleasepool { reader.zoom(1.1) }
        try await reader.flushPersistence()
        let afterZoom = try #require(await fixture.operations.readingState(noteID: fixture.context.target.noteID, attachmentID: fixture.attachmentID))
        #expect(afterZoom.pageIndex == afterScroll.pageIndex && !afterZoom.autoScales)
        #expect(afterZoom.scaleFactor != afterScroll.scaleFactor)
        autoreleasepool { reader.fitPage() }
        try await reader.flushPersistence()
        let afterFit = try #require(await fixture.operations.readingState(noteID: fixture.context.target.noteID, attachmentID: fixture.attachmentID))
        #expect(afterFit.autoScales)

        var searches: [[String: Any]] = []
        try autoreleasepool {
            for backwards in [false, true] {
                view.clearSelection()
                reader.searchQuery = "scholium-missing-needle"
                let searchStart = ContinuousClock.now
                reader.find(backwards: backwards)
                searches.append([
                    "case": backwards ? "missing-backward-nil-selection" : "missing-forward-nil-selection", "ms": milliseconds(since: searchStart),
                ])
                let hasNoSelection = view.currentSelection == nil
                #expect(reader.searchStatus != nil && hasNoSelection)
            }
            for backwards in [false, true] {
                let startQuery = backwards ? "scholium-early-needle" : "scholium-late-needle"
                let query = backwards ? "scholium-late-needle" : "scholium-early-needle"
                guard let startingSelection = reader.document?.findString(startQuery, fromSelection: nil, withOptions: [.caseInsensitive]) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                view.setCurrentSelection(startingSelection, animate: false)
                reader.searchQuery = query
                let searchStart = ContinuousClock.now
                reader.find(backwards: backwards)
                searches.append(["case": backwards ? "backward-wrap" : "forward-wrap", "ms": milliseconds(since: searchStart)])
                #expect(view.currentSelection?.string == query && reader.searchStatus == nil)
                guard let resultPage = view.currentSelection?.pages.first else { throw CocoaError(.fileReadCorruptFile) }
                #expect(reader.document?.index(for: resultPage) == (backwards ? pageCount - 1 : 0))
            }
        }

        return (
            [
                "measurement": "unshown-window-native-proxy",
                "pages": pageCount,
                "fixtureBytes": data.count,
                "fixtureSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                "modelReadyMS": modelReadyMS,
                "applyLayoutProxyMS": applyLayoutMS,
                "sameViewportCallbacks": callbacks,
                "sameViewportPublications": publications,
                "sameViewportCallbacksMS": callbackMS,
                "sameSelectionCallbacks": callbacks,
                "sameSelectionPublications": selectionPublications,
                "sameSelectionCallbacksMS": selectionMS,
                "nativeProjections": callbacks,
                "nativeProjectionsMS": projectionMS,
                "pageChangeMS": pageChangeMS,
                "paneCycles": paneCycles,
                "paneCyclesMS": paneMS,
                "paneRetainedPage": beforeScroll.pageIndex + 1,
                "paneOriginDeltaX": paneOriginDeltaX,
                "paneOriginDeltaY": paneOriginDeltaY,
                "loadCount": await fixture.operations.loadCount,
                "searches": searches,
            ], references
        )
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: ContinuousClock.now).components
        return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
    }

    private func drainNativeCallbacks() {
        autoreleasepool { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
    }

    private func fixtureData(pageCount: Int) throws -> Data {
        if let root = ProcessInfo.processInfo.environment["SCHOLIUM_PDF_PERFORMANCE_FIXTURES"] {
            return try Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("synthetic-\(pageCount).pdf"))
        }
        // ASCII PDF generation has no timestamps, platform font substitution,
        // or file-system participants; baseline/current receive identical bytes.
        let fontID = 3 + pageCount * 2
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Count \(pageCount) /Kids [" + (0..<pageCount).map { "\(3 + $0 * 2) 0 R" }.joined(separator: " ") + "] >>",
        ]
        for page in 0..<pageCount {
            var stream = "BT\n/F1 10 Tf\n12 TL\n36 750 Td\n"
            for row in 0..<45 {
                var text = String(format: "Synthetic scholarly passage page %04d line %02d: links and context remain readable.", page + 1, row + 1)
                if page == 0 && row == 0 { text += " scholium-early-needle" }
                if page == pageCount - 1 && row == 44 { text += " scholium-late-needle" }
                stream += "(\(text)) Tj\nT*\n"
            }
            stream += "ET\n"
            objects.append(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 \(fontID) 0 R >> >> /Contents \(4 + page * 2) 0 R >>")
            objects.append("<< /Length \(stream.utf8.count) >>\nstream\n\(stream)endstream")
        }
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        var pdf = "%PDF-1.4\n% Scholium synthetic fixture\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(offsets.count)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }

    private final class ReleasedReferences {
        weak var reader: PDFReaderController?
        weak var document: PDFDocument?
        weak var view: PDFReaderNativePDFView?
        weak var host: PDFReaderNativeHostView?
        weak var tools: PDFReaderFloatingToolsView?
        weak var toolbar: PDFReaderToolbarController?
        weak var window: NSWindow?
        var appOwnersAreReleased: Bool {
            reader == nil && host == nil && toolbar == nil && window == nil
        }
    }

    @MainActor private struct Fixture {
        let reader: PDFReaderController
        let operations: ControlledPDFReaderOperations
        let context: PDFReaderNoteContext
        let attachmentID: UUID

        init(data: Data) throws {
            attachmentID = UUID()
            let record = PortableAttachmentRecord(
                id: attachmentID, vaultID: nil,
                location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(attachmentID.uuidString)/performance.pdf")))
            let snapshot = PDFReaderSnapshot(
                record: record, data: data,
                revision: PDFReaderRevision(fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
            context = PDFReaderNoteContext(
                triptychID: UUID(), target: SourceAttachmentTarget(noteID: UUID(), vaultID: UUID(), relativePath: "synthetic-performance.md"),
                authoredPath: "../.scholium/attachments/files/performance.pdf")
            operations = ControlledPDFReaderOperations(notes: [context.target.noteID: snapshot])
            reader = PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
        }
    }
}
