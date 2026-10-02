import AppKit
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("PDF reader content motion", .serialized)
@MainActor
struct PDFReaderMotionTests {
    @Test("Readiness preserves native reading state and immediately accepts input", arguments: [false, true])
    func readinessPreservesReadingState(reduceMotion: Bool) async throws {
        let fixture = try Fixture()
        let reader = fixture.reader
        defer { reader.shutdown() }
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 500, height: 650))
        let window = makeWindow(view)
        defer {
            view.invalidate()
            window.close()
        }
        try await fixture.load()
        let document = try #require(reader.document)
        view.updatePresentation(reduceMotion: reduceMotion)
        view.apply(reader)
        view.layout()
        #expect(view.document === document)
        #expect(reader.pageNumber == 2)
        #expect(!view.autoScales)
        #expect(abs(view.scaleFactor - 1.4) < 0.001)
        #expect(view.alphaValue == 1)
        #expect(reader.canUseReaderCommands)
        #expect((view.layer?.animation(forKey: PDFReaderNativePDFView.contentRevealAnimationKey) == nil) == reduceMotion)

        // Ordinary SwiftUI updates and native layout must not replay arrival
        // or move a restored reading position.
        view.layer?.removeAllAnimations()
        view.updatePresentation(reduceMotion: reduceMotion)
        view.apply(reader)
        view.layout()
        #expect(view.layer?.animation(forKey: PDFReaderNativePDFView.contentRevealAnimationKey) == nil)
        #expect(view.document === document && reader.pageNumber == 2)
        reader.goToPage(1)
        #expect(reader.pageNumber == 1)
    }

    @Test("Hide, rapid replacement, reduced motion and teardown revoke presentation without stale input")
    func interruptionKeepsCurrentDocument() async throws {
        let first = try Fixture()
        let second = try Fixture()
        defer {
            first.reader.shutdown()
            second.reader.shutdown()
        }
        try await first.load()
        try await second.load()
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 500, height: 650))
        let window = makeWindow(view)
        defer {
            view.invalidate()
            window.close()
        }
        view.updatePresentation(reduceMotion: false)
        view.apply(first.reader)
        view.isHidden = true
        #expect(view.layer?.animation(forKey: PDFReaderNativePDFView.contentRevealAnimationKey) == nil)
        view.updatePresentation(reduceMotion: false)
        view.apply(second.reader)
        #expect(view.document === second.reader.document)
        #expect(view.layer?.animation(forKey: PDFReaderNativePDFView.contentRevealAnimationKey) == nil)
        view.isHidden = false
        view.layout()
        #expect(view.document === second.reader.document)
        #expect(view.layer?.animation(forKey: PDFReaderNativePDFView.contentRevealAnimationKey) != nil)
        view.updatePresentation(reduceMotion: true)
        view.apply(second.reader)
        #expect(view.layer?.animation(forKey: PDFReaderNativePDFView.contentRevealAnimationKey) == nil)
        #expect(second.reader.canUseReaderCommands && view.alphaValue == 1)
        view.invalidate()
        view.updatePresentation(reduceMotion: false)
        view.apply(first.reader)
        #expect(view.document == nil && view.controller == nil)
        #expect(view.layer?.animation(forKey: PDFReaderNativePDFView.contentRevealAnimationKey) == nil)
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
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
        let attachmentID: UUID

        init() throws {
            let document = PDFDocument()
            for _ in 0..<2 { document.insert(PDFPage(), at: document.pageCount) }
            let data = try #require(document.dataRepresentation())
            attachmentID = UUID()
            let record = PortableAttachmentRecord(
                id: attachmentID, vaultID: nil,
                location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(attachmentID.uuidString)/motion.pdf"))
            )
            let snapshot = PDFReaderSnapshot(
                record: record, data: data,
                revision: PDFReaderRevision(
                    fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1
                ))
            context = PDFReaderNoteContext(
                triptychID: UUID(),
                target: SourceAttachmentTarget(
                    noteID: UUID(), vaultID: UUID(), relativePath: "synthetic-motion.md"
                ), authoredPath: "../.scholium/attachments/files/motion.pdf")
            operations = ControlledPDFReaderOperations(notes: [context.target.noteID: snapshot])
            reader = PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil })
        }

        func load() async throws {
            await operations.seedPosition(
                PDFReaderReadingState(pageIndex: 1, scaleFactor: 1.4, autoScales: false),
                noteID: context.target.noteID, attachmentID: attachmentID)
            reader.follow(context, operations: operations)
            #expect(reader.setVisible(true))
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while reader.document == nil || reader.isLoading, reader.error == nil, ContinuousClock.now < deadline {
                await Task.yield()
            }
            try #require(reader.document != nil && !reader.isLoading && reader.error == nil)
        }
    }
}
