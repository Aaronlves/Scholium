import AppKit
import Foundation
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("PDF reader lifecycle", .serialized)
@MainActor
struct PDFReaderLifecycleTests {
    @Test("A delayed departed PDF cannot replace the current Note's PDF")
    func departedLoadCannotPublish() async throws {
        let fixture = try Fixture()
        await fixture.operations.holdLoad(for: fixture.first.target.noteID)
        await fixture.operations.holdLoad(for: fixture.second.target.noteID)
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await eventually { await fixture.operations.hasHeldLoad(for: fixture.first.target.noteID) }

        reader.follow(fixture.second, operations: fixture.operations)
        #expect(reader.document == nil)
        #expect(reader.annotationDraft == nil)
        try await eventually { await fixture.operations.hasHeldLoad(for: fixture.second.target.noteID) }
        await fixture.operations.releaseLoad(for: fixture.second.target.noteID)
        try await loaded(reader)
        let current = try #require(reader.document)
        #expect(reader.filename == "second.pdf")

        await fixture.operations.releaseLoad(for: fixture.first.target.noteID)
        try await eventually { await fixture.operations.returnedLoadCount == 2 }
        await Task.yield()
        #expect(reader.document === current)
        #expect(reader.filename == "second.pdf")
        #expect(reader.context == fixture.second)
        #expect(reader.error == nil)
    }

    @Test("Repeated reveal and hide retain one load and one current document")
    func repeatedVisibilityDoesNotReload() async throws {
        let fixture = try Fixture()
        await fixture.operations.holdLoad(for: fixture.first.target.noteID)
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.follow(fixture.first, operations: fixture.operations)
        reader.setVisible(true)
        try await eventually { await fixture.operations.hasHeldLoad(for: fixture.first.target.noteID) }
        for _ in 0..<20 {
            reader.setVisible(false)
            reader.setVisible(true)
        }
        #expect(await fixture.operations.loadCount == 1)
        await fixture.operations.releaseLoad(for: fixture.first.target.noteID)
        try await loaded(reader)
        let current = try #require(reader.document)
        for _ in 0..<20 {
            reader.setVisible(false)
            reader.setVisible(true)
            #expect(reader.document === current)
        }
        try await reader.flushPersistence()
        #expect(await fixture.operations.loadCount == 1)
        #expect(reader.isVisible)
    }

    @Test("Empty comment validation stays with its draft and clears on cancel or successful save")
    func commentValidationLifecycle() async throws {
        let fixture = try Fixture()
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        reader.requestComment(on: try #require(reader.document?.page(at: 0)), at: NSPoint(x: 40, y: 40))
        let draft = try #require(reader.annotationDraft)
        reader.commitComment(draft, text: " \n ")
        #expect(reader.annotationDraft?.id == draft.id && reader.annotationDraftError != nil)
        #expect(reader.error == nil && reader.document?.page(at: 0)?.annotations.isEmpty == true)
        #expect(await fixture.operations.saveCount == 0)
        reader.cancelComment()
        #expect(reader.annotationDraft == nil && reader.annotationDraftError == nil && reader.error == nil)
        reader.requestComment(on: try #require(reader.document?.page(at: 0)), at: NSPoint(x: 40, y: 40))
        let retry = try #require(reader.annotationDraft)
        reader.commitComment(retry, text: "")
        #expect(reader.annotationDraftError != nil)
        reader.commitComment(retry, text: "Valid synthetic comment")
        try await eventually { !reader.isSaving && !reader.hasUnsavedAnnotations }
        #expect(reader.annotationDraft == nil && reader.annotationDraftError == nil)
        #expect(reader.document?.page(at: 0)?.annotations.first?.contents == "Valid synthetic comment")
    }

    @Test("Departure flush waits for an in-flight annotation save")
    func flushWaitsForSaveCompletion() async throws {
        let fixture = try Fixture()
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        await fixture.operations.holdNextSave()
        try addComment("Pending annotation", to: reader)
        try await eventually { await fixture.operations.hasHeldSave }
        #expect(reader.isSaving)
        #expect(!reader.canAnnotate)
        var flushCompleted = false
        let flush = Task { @MainActor in
            try await reader.flushAnnotations()
            flushCompleted = true
        }
        await Task.yield()
        await Task.yield()
        #expect(!flushCompleted)

        await fixture.operations.releaseSave()
        try await flush.value
        #expect(flushCompleted)
        #expect(!reader.isSaving)
        #expect(!reader.hasUnsavedAnnotations)
        #expect(reader.canAnnotate)
        let saved = try #require(await fixture.operations.savedPDF(for: fixture.first.target.noteID))
        let document = try #require(PDFDocument(data: saved.data))
        #expect(document.page(at: 0)?.annotations.first?.contents == "Pending annotation")
    }

    @Test("A save conflict retains an exportable candidate and blocks departure and further annotations")
    func conflictRetainsCandidate() async throws {
        let fixture = try Fixture()
        var reported: [String] = []
        let reader = makeReader(reportIssue: { reported.append($0) })
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        await fixture.operations.failNextSave(with: .changed)
        try addComment("Retained after conflict 注释", to: reader)
        try await eventually { !reader.isSaving && reader.error != nil }
        #expect(reader.hasUnsavedAnnotations)
        #expect(!reader.canAnnotate)
        #expect(reported.count == 1)
        #expect(!reader.setVisible(false))
        #expect(reader.isVisible && reader.hasUnsavedAnnotations)
        await #expect(throws: PDFReaderError.changed) { try await reader.flushAnnotations() }
        await #expect(throws: PDFReaderError.changed) { try await reader.flushPersistence() }
        let page = try #require(reader.document?.page(at: 0))
        reader.requestComment(on: page, at: NSPoint(x: 40, y: 40))
        #expect(reader.annotationDraft == nil)
        #expect(await fixture.operations.saveCount == 1)

        let destination = fixtureExportURL()
        try await reader.exportAnnotations(to: destination)
        let candidate = try #require(await fixture.operations.exportedData(at: destination))
        let exported = try #require(PDFDocument(data: candidate))
        #expect(exported.page(at: 0)?.annotations.first?.contents == "Retained after conflict 注释")
        let unchanged = try #require(await fixture.operations.savedPDF(for: fixture.first.target.noteID))
        #expect(unchanged.data == fixture.firstSnapshot.data)
        await reader.reload()
        #expect(reader.hasUnsavedAnnotations)
        #expect(reader.document === page.document)
    }

    @Test("Comment creation, editing and deletion persist across document reloads")
    func commentRoundTrip() async throws {
        let fixture = try Fixture()
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        try addComment("Original comment 😀", to: reader)
        try await reader.flushAnnotations()
        await reader.reload()
        try await loaded(reader)
        let original = try #require(reader.document?.page(at: 0)?.annotations.first)
        #expect(original.contents == "Original comment 😀")

        reader.editAnnotation(original)
        let edit = try #require(reader.annotationDraft)
        reader.commitComment(edit, text: "Edited comment 注释")
        try await reader.flushAnnotations()
        await reader.reload()
        try await loaded(reader)
        let edited = try #require(reader.document?.page(at: 0)?.annotations.first)
        #expect(edited.contents == "Edited comment 注释")

        reader.editAnnotation(edited)
        reader.deleteAnnotation(try #require(reader.annotationDraft))
        try await reader.flushAnnotations()
        await reader.reload()
        try await loaded(reader)
        #expect(reader.document?.page(at: 0)?.annotations.isEmpty == true)
        #expect(reader.annotations.isEmpty)
        #expect(await fixture.operations.saveCount == 3)
    }

    @Test("Explicit reload retains a draft and its document until the researcher finishes it")
    func draftStopsReload() async throws {
        let fixture = try Fixture()
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        let document = try #require(reader.document)
        let page = try #require(document.page(at: 0))
        reader.requestComment(on: page, at: NSPoint(x: 40, y: 40))
        reader.annotationText = "Retain this unfinished comment"
        let draft = try #require(reader.annotationDraft)
        let loads = await fixture.operations.loadCount
        await reader.reload()
        #expect(reader.document === document && reader.annotationDraft?.id == draft.id)
        #expect(reader.annotationText == "Retain this unfinished comment" && reader.canCommitDraft)
        #expect(await fixture.operations.loadCount == loads)
        reader.commitComment(draft, text: reader.annotationText)
        try await eventually { !reader.isSaving && !reader.hasUnsavedAnnotations }
        await reader.reload()
        try await loaded(reader)
        #expect(reader.document?.page(at: 0)?.annotations.first?.contents == "Retain this unfinished comment")
    }

    @Test("An unfinished comment blocks departure; a cancelled draft cannot mutate the next PDF")
    func departedDraftCannotMutateCurrentPDF() async throws {
        let fixture = try Fixture()
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        reader.requestComment(on: try #require(reader.document?.page(at: 0)), at: NSPoint(x: 40, y: 40))
        let departedDraft = try #require(reader.annotationDraft)
        await fixture.operations.holdNextRecoveryLookup()
        reader.follow(fixture.second, operations: fixture.operations)
        #expect(reader.annotationDraft?.id == departedDraft.id)
        try await eventually { await fixture.operations.hasHeldRecoveryLookup }
        await #expect(throws: (any Error).self) { try await reader.flushAnnotations() }
        reader.cancelComment()
        #expect(reader.annotationDraft == nil)
        try await loaded(reader)
        await fixture.operations.releaseRecoveryLookup()
        try await eventually { await fixture.operations.returnedRecoveryCount == 1 }
        await Task.yield()
        #expect(reader.filename == "second.pdf")
        #expect(reader.error == nil)
        reader.commitComment(departedDraft, text: "Must never appear")
        #expect(reader.document?.page(at: 0)?.annotations.isEmpty == true)
        #expect(await fixture.operations.saveCount == 0)
        reader.follow(nil, operations: nil)
        #expect(reader.document == nil)
        #expect(!reader.canAnnotate)
    }

    @Test("Shutdown invalidates late load completion and future visibility or follow requests")
    func shutdownDropsLateLoad() async throws {
        let fixture = try Fixture()
        await fixture.operations.holdLoad(for: fixture.first.target.noteID)
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await eventually { await fixture.operations.hasHeldLoad(for: fixture.first.target.noteID) }
        reader.shutdown()
        await fixture.operations.releaseLoad(for: fixture.first.target.noteID)
        try await eventually { await fixture.operations.returnedLoadCount == 1 }
        await Task.yield()
        reader.setVisible(false)
        reader.follow(fixture.second, operations: fixture.operations)
        #expect(reader.document == nil)
        #expect(reader.filename == nil)
        #expect(reader.annotationDraft == nil)
        #expect(!reader.canAttach)
        #expect(await fixture.operations.loadCount == 1)
    }

    @Test("Window visibility and width plus Note/PDF reading position restore and persist")
    func readingPositionAndWindowPreferences() async throws {
        let fixture = try Fixture()
        let position = PDFReaderReadingState(pageIndex: 1, pointX: 40, pointY: 500, scaleFactor: 1.5, autoScales: false)
        await fixture.operations.seedPosition(position, noteID: fixture.first.target.noteID, attachmentID: fixture.firstSnapshot.record.id)
        let windowID = UUID()
        await fixture.operations.seedWindow(PDFReaderWindowState(isVisible: true, paneWidth: 512), windowID: windowID)
        let reader = makeReader(windowID: windowID)
        defer { cleanup(reader, operations: fixture.operations) }
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        #expect(reader.isVisible)
        #expect(reader.paneWidth == 512)
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        defer { view.invalidate() }
        view.displayMode = .singlePageContinuous
        reader.attach(view: view)
        view.layoutDocumentView()
        #expect(reader.pageNumber == 2)
        #expect(!view.autoScales)
        #expect(abs(view.scaleFactor - 1.5) < 0.001)
        reader.recordPaneWidth(620)
        reader.setVisible(false)
        try await reader.flushPersistence()
        let savedWindow = try #require(try await fixture.operations.windowState(windowID: windowID))
        #expect(savedWindow == PDFReaderWindowState(isVisible: false, paneWidth: 620))
        let savedPosition = try #require(
            try await fixture.operations.readingState(noteID: fixture.first.target.noteID, attachmentID: fixture.firstSnapshot.record.id))
        #expect(savedPosition.pageIndex == 1)
        #expect(!savedPosition.autoScales)
        #expect(abs(savedPosition.scaleFactor - 1.5) < 0.001)
        reader.detach(view: view)
    }

    @Test("Delayed window restoration cannot override newer explicit visibility and width")
    func explicitPreferencesWinOverDelayedRestore() async throws {
        let fixture = try Fixture()
        let windowID = UUID()
        await fixture.operations.seedWindow(PDFReaderWindowState(isVisible: false, paneWidth: 512), windowID: windowID)
        await fixture.operations.holdNextWindowState()
        let reader = makeReader(windowID: windowID)
        defer { cleanup(reader, operations: fixture.operations) }
        reader.follow(fixture.first, operations: fixture.operations)
        try await eventually { await fixture.operations.hasHeldWindowState }
        reader.setVisible(true)
        reader.recordPaneWidth(620)
        await fixture.operations.releaseWindowState()
        try await loaded(reader)
        #expect(reader.isVisible)
        #expect(reader.paneWidth == 620)
        try await reader.flushPersistence()
        #expect(try await fixture.operations.windowState(windowID: windowID) == PDFReaderWindowState(isVisible: true, paneWidth: 620))
    }

    @Test("An explicit unchanged hidden choice defeats delayed visible restoration")
    func unchangedHiddenChoiceWinsRestore() async throws {
        let fixture = try Fixture()
        let windowID = UUID()
        await fixture.operations.seedWindow(PDFReaderWindowState(isVisible: true, paneWidth: 512), windowID: windowID)
        await fixture.operations.holdNextWindowState()
        let reader = makeReader(windowID: windowID)
        defer { cleanup(reader, operations: fixture.operations) }
        reader.follow(fixture.first, operations: fixture.operations)
        try await eventually { await fixture.operations.hasHeldWindowState }
        #expect(reader.setVisible(false))
        await fixture.operations.releaseWindowState()
        try await eventually { !reader.isLoading }
        #expect(!reader.isVisible && reader.document == nil)
        try await reader.flushPersistence()
        #expect(try await fixture.operations.windowState(windowID: windowID)?.isVisible == false)
    }

    @Test("Continuous final-page navigation persists the visible page when the viewport cannot align its top")
    func finalPagePositionUsesCurrentPage() async throws {
        let fixture = try Fixture()
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        let view = PDFReaderNativePDFView(frame: NSRect(x: 0, y: 0, width: 350, height: 580))
        defer { view.invalidate() }
        reader.attach(view: view)
        view.layoutDocumentView()
        reader.goToPage(2)
        view.layoutDocumentView()
        reader.viewPositionDidChange()
        #expect(view.currentPage === reader.document?.page(at: 1))
        #expect(reader.pageNumber == 2)
        try await reader.flushPersistence()
        let saved = try #require(try await fixture.operations.readingState(noteID: fixture.first.target.noteID, attachmentID: fixture.firstSnapshot.record.id))
        #expect(saved.pageIndex == 1)
        #expect(saved.pointY >= 0 && saved.pointY <= 792)
    }

    @Test("Pending import blocks departure; completion and cancellation retain the captured Note binding")
    func pendingImportCannotBindAnotherNote() async throws {
        let fixture = try Fixture()
        var bindings: [(path: String?, target: SourceAttachmentTarget, expectedPath: String?)] = []
        let reader = PDFReaderController(
            windowID: UUID(),
            setBinding: { bindings.append(($0, $1, $2)) }, reportIssue: { _ in nil })
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        await fixture.operations.holdNextImport()
        let completed = Task { @MainActor in try await reader.importPDF(at: fixtureExportURL()) }
        try await eventually { await fixture.operations.hasHeldImport }
        #expect(reader.isImporting)
        #expect(!reader.canAttach)
        #expect(!reader.canAnnotate)
        #expect(bindings.isEmpty)
        await #expect(throws: (any Error).self) { try await reader.flushAnnotations() }
        await #expect(throws: (any Error).self) { try await reader.flushPersistence() }
        reader.setVisible(false)
        #expect(reader.isVisible)
        await fixture.operations.releaseImport()
        try await completed.value
        #expect(!reader.isImporting)
        try #require(bindings.count == 1)
        #expect(bindings[0].target == fixture.first.target)
        #expect(bindings[0].path == "../.scholium/attachments/files/imported.pdf")
        #expect(bindings[0].expectedPath == fixture.first.authoredPath)

        await fixture.operations.holdNextImport()
        let departed = Task { @MainActor in try await reader.importPDF(at: fixtureExportURL()) }
        try await eventually { await fixture.operations.hasHeldImport }
        reader.follow(fixture.second, operations: fixture.operations)
        await fixture.operations.releaseImport()
        await #expect(throws: CancellationError.self) { try await departed.value }
        try await loaded(reader)
        #expect(bindings.count == 1)
        #expect(reader.context == fixture.second)
        #expect(reader.filename == "second.pdf")
        #expect(!reader.isImporting)

        await fixture.operations.holdNextImport()
        let canceled = Task { @MainActor in try await reader.importPDF(at: fixtureExportURL()) }
        try await eventually { await fixture.operations.hasHeldImport }
        canceled.cancel()
        await fixture.operations.cancelImport()
        await #expect(throws: CancellationError.self) { try await canceled.value }
        #expect(!reader.isImporting)
        #expect(bindings.count == 1)
        try await reader.flushAnnotations()
    }

    @Test("Nested departure tokens refuse new mutations until every owner releases")
    func departureFreezesInput() async throws {
        let fixture = try Fixture()
        let reader = makeReader()
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        let page = try #require(reader.document?.page(at: 0))
        let document = reader.document
        let first = reader.beginDeparture()
        let second = reader.beginDeparture()
        try await reader.flushAnnotations()
        reader.requestComment(on: page, at: NSPoint(x: 40, y: 40))
        reader.requestAttachPDF()
        reader.setVisible(false)
        await reader.reload()
        #expect(reader.annotationDraft == nil)
        #expect(!reader.attachRequested)
        #expect(reader.isVisible)
        #expect(reader.document === document)
        #expect(!reader.canAnnotate && !reader.canAttach)
        reader.endDeparture(first)
        #expect(reader.isDeparting)
        reader.endDeparture(second)
        #expect(!reader.isDeparting && reader.canAnnotate && reader.canAttach)
        reader.requestComment(on: page, at: NSPoint(x: 40, y: 40))
        #expect(reader.annotationDraft != nil)
    }

    @Test("Close and quit currency refuses mutation after content flushing completes")
    func closeCurrencyGuardsInput() async throws {
        let fixture = try Fixture()
        var closing = false
        let reader = PDFReaderController(windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: { _ in nil }, allowsInteraction: { !closing })
        defer { cleanup(reader, operations: fixture.operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: fixture.operations)
        try await loaded(reader)
        let page = try #require(reader.document?.page(at: 0))
        closing = true
        try await reader.flushPersistence()
        reader.requestComment(on: page, at: NSPoint(x: 40, y: 40))
        reader.requestAttachPDF()
        #expect(reader.annotationDraft == nil && !reader.attachRequested)
        #expect(!reader.canAnnotate && !reader.canAttach)
        closing = false
        #expect(reader.canAnnotate && reader.canAttach)
    }

    @Test("An unavailable bound PDF can detach only its captured authored binding")
    func unavailablePDFDetach() async throws {
        let fixture = try Fixture()
        let operations = ControlledPDFReaderOperations(notes: [:])
        await operations.failNextLoad(with: .missing)
        var bindings: [(String?, SourceAttachmentTarget, String?)] = []
        let reader = PDFReaderController(
            windowID: UUID(), setBinding: { bindings.append(($0, $1, $2)) }, reportIssue: { _ in nil })
        defer { cleanup(reader, operations: operations) }
        reader.setVisible(true)
        reader.follow(fixture.first, operations: operations)
        try await eventually { !reader.isLoading && reader.context == fixture.first }
        #expect(reader.document == nil && reader.error != nil && reader.context?.authoredPath == fixture.first.authoredPath)
        try await reader.detachPDF()
        #expect(bindings.count == 1)
        #expect(bindings.first?.0 == nil && bindings.first?.1 == fixture.first.target)
        #expect(bindings.first?.2 == fixture.first.authoredPath)
        #expect(!reader.isImporting && !reader.isDeparting)
    }

    private func makeReader(windowID: UUID = UUID(), reportIssue: @escaping @MainActor (String) -> Void = { _ in }) -> PDFReaderController {
        PDFReaderController(
            windowID: windowID, setBinding: { _, _, _ in },
            reportIssue: {
                reportIssue($0)
                return nil
            })
    }

    private func loaded(_ reader: PDFReaderController) async throws {
        try await eventually { reader.document != nil && !reader.isLoading }
    }

    private func eventually(_ condition: @escaping @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        try #require(await condition(), "The controlled PDF lifecycle did not reach its expected boundary.")
    }

    private func addComment(_ text: String, to reader: PDFReaderController) throws {
        let page = try #require(reader.document?.page(at: 0))
        reader.requestComment(on: page, at: NSPoint(x: 40, y: 40))
        reader.commitComment(try #require(reader.annotationDraft), text: text)
    }

    private func cleanup(_ reader: PDFReaderController, operations: ControlledPDFReaderOperations) {
        reader.shutdown()
        Task { await operations.cancelPending() }
    }

    private func fixtureExportURL() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/pdf-reader-lifecycle-fixtures/\(UUID())/export.pdf")
    }

    private struct Fixture {
        let first: PDFReaderNoteContext
        let second: PDFReaderNoteContext
        let firstSnapshot: PDFReaderSnapshot
        let operations: ControlledPDFReaderOperations

        init() throws {
            let triptychID = UUID()
            let vaultID = UUID()
            first = PDFReaderNoteContext(
                triptychID: triptychID, target: SourceAttachmentTarget(noteID: UUID(), vaultID: vaultID, relativePath: "first.md"),
                authoredPath: "../.scholium/attachments/files/first.pdf")
            second = PDFReaderNoteContext(
                triptychID: triptychID, target: SourceAttachmentTarget(noteID: UUID(), vaultID: vaultID, relativePath: "nested/second.md"),
                authoredPath: "../../.scholium/attachments/files/second.pdf")
            let data = try Self.pdfData()
            firstSnapshot = try Self.snapshot(filename: "first.pdf", vaultID: vaultID, data: data)
            let secondSnapshot = try Self.snapshot(filename: "second.pdf", vaultID: vaultID, data: data)
            operations = ControlledPDFReaderOperations(notes: [first.target.noteID: firstSnapshot, second.target.noteID: secondSnapshot])
        }

        private static func snapshot(filename: String, vaultID: UUID, data: Data) throws -> PDFReaderSnapshot {
            let record = PortableAttachmentRecord(id: UUID(), vaultID: vaultID, location: .vaultRelative(try AttachmentRelativePath("Attachments/\(filename)")))
            return PDFReaderSnapshot(
                record: record, data: data,
                revision: PDFReaderRevision(fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
        }

        private static func pdfData() throws -> Data {
            let data = NSMutableData()
            let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            for page in 0..<2 {
                context.beginPDFPage(nil)
                context.setFillColor(CGColor(gray: page == 0 ? 0.9 : 0.8, alpha: 1))
                context.fill(CGRect(x: 80, y: 80, width: 50, height: 50))
                context.endPDFPage()
            }
            context.closePDF()
            return data as Data
        }
    }
}

actor ControlledPDFReaderOperations: PDFReaderUseCases {
    private struct PositionKey: Hashable {
        let noteID: UUID
        let attachmentID: UUID
    }
    private struct PendingSave {
        let candidate: Data
        let expected: PDFReaderSnapshot
        let continuation: CheckedContinuation<PDFReaderSnapshot, any Error>
    }
    private var notes: [UUID: PDFReaderSnapshot]
    private var heldNoteIDs: Set<UUID> = []
    private var heldLoads: [UUID: CheckedContinuation<PDFReaderSnapshot?, any Error>] = [:]
    private var holdSave = false
    private var pendingSave: PendingSave?
    private var nextSaveError: PDFReaderError?
    private var nextLoadError: PDFReaderError?
    private var positions: [PositionKey: PDFReaderReadingState] = [:]
    private var windows: [UUID: PDFReaderWindowState] = [:]
    private var holdWindowState = false
    private var heldWindowState: (UUID, CheckedContinuation<PDFReaderWindowState?, any Error>)?
    private var holdRecoveryLookup = false
    private var heldRecoveryLookup: CheckedContinuation<[PDFReaderRecovery], any Error>?
    private var holdImport = false
    private var heldImport: (PDFReaderImport, CheckedContinuation<PDFReaderImport, any Error>)?
    private var exports: [URL: Data] = [:]
    private(set) var loadCount = 0
    private(set) var returnedLoadCount = 0
    private(set) var saveCount = 0
    private(set) var returnedRecoveryCount = 0

    init(notes: [UUID: PDFReaderSnapshot]) { self.notes = notes }

    func holdLoad(for noteID: UUID) { heldNoteIDs.insert(noteID) }
    func hasHeldLoad(for noteID: UUID) -> Bool { heldLoads[noteID] != nil }
    func releaseLoad(for noteID: UUID) { heldLoads.removeValue(forKey: noteID)?.resume(returning: notes[noteID]) }
    func holdNextSave() { holdSave = true }
    func failNextSave(with error: PDFReaderError) { nextSaveError = error }
    func failNextLoad(with error: PDFReaderError) { nextLoadError = error }
    var hasHeldSave: Bool { pendingSave != nil }
    func savedPDF(for noteID: UUID) -> PDFReaderSnapshot? { notes[noteID] }
    func exportedData(at url: URL) -> Data? { exports[url] }
    func seedPosition(_ position: PDFReaderReadingState, noteID: UUID, attachmentID: UUID) {
        positions[PositionKey(noteID: noteID, attachmentID: attachmentID)] = position
    }
    func seedWindow(_ state: PDFReaderWindowState, windowID: UUID) { windows[windowID] = state }
    func holdNextWindowState() { holdWindowState = true }
    func holdNextRecoveryLookup() { holdRecoveryLookup = true }
    var hasHeldRecoveryLookup: Bool { heldRecoveryLookup != nil }
    func releaseRecoveryLookup() {
        heldRecoveryLookup?.resume(returning: [])
        heldRecoveryLookup = nil
    }
    func holdNextImport() { holdImport = true }
    var hasHeldImport: Bool { heldImport != nil }
    func releaseImport() {
        guard let (prepared, continuation) = heldImport else { return }
        heldImport = nil
        continuation.resume(returning: prepared)
    }
    func cancelImport() {
        heldImport?.1.resume(throwing: CancellationError())
        heldImport = nil
    }
    var hasHeldWindowState: Bool { heldWindowState != nil }
    func releaseWindowState() {
        guard let (windowID, continuation) = heldWindowState else { return }
        heldWindowState = nil
        continuation.resume(returning: windows[windowID])
    }

    func releaseSave() {
        guard let pending = pendingSave else { return }
        pendingSave = nil
        do { pending.continuation.resume(returning: try commit(pending.candidate, expected: pending.expected)) } catch {
            pending.continuation.resume(throwing: error)
        }
    }

    func cancelPending() {
        let loads = heldLoads.values
        heldLoads = [:]
        for continuation in loads { continuation.resume(throwing: CancellationError()) }
        pendingSave?.continuation.resume(throwing: CancellationError())
        pendingSave = nil
        heldWindowState?.1.resume(throwing: CancellationError())
        heldWindowState = nil
        heldRecoveryLookup?.resume(throwing: CancellationError())
        heldRecoveryLookup = nil
        cancelImport()
    }

    func boundPDF(for target: SourceAttachmentTarget, authoredPath: String?) async throws -> PDFReaderSnapshot? {
        loadCount += 1
        defer { returnedLoadCount += 1 }
        if let error = nextLoadError {
            nextLoadError = nil
            throw error
        }
        if heldNoteIDs.remove(target.noteID) != nil {
            return try await withCheckedThrowingContinuation { heldLoads[target.noteID] = $0 }
        }
        return notes[target.noteID]
    }

    func savePDF(candidate: Data, expected: PDFReaderSnapshot) async throws -> PDFReaderSnapshot {
        saveCount += 1
        if let error = nextSaveError {
            nextSaveError = nil
            throw error
        }
        if holdSave {
            holdSave = false
            return try await withCheckedThrowingContinuation {
                pendingSave = PendingSave(candidate: candidate, expected: expected, continuation: $0)
            }
        }
        return try commit(candidate, expected: expected)
    }

    private func commit(_ candidate: Data, expected: PDFReaderSnapshot) throws -> PDFReaderSnapshot {
        guard let current = notes.values.first(where: { $0.record.id == expected.record.id }), current.revision == expected.revision else {
            throw PDFReaderError.changed
        }
        let saved = PDFReaderSnapshot(
            record: expected.record, data: candidate,
            revision: PDFReaderRevision(
                fingerprint: DocumentFingerprint(data: candidate), device: 1, inode: expected.revision.inode + 1, parentDevice: 1, parentInode: 1))
        for noteID in Array(notes.keys) where notes[noteID]?.record.id == expected.record.id { notes[noteID] = saved }
        return saved
    }

    func availablePDFs() async throws -> [PortableAttachmentRecord] { notes.values.map(\.record) }
    func boundPDFRecoveries(for target: SourceAttachmentTarget, authoredPath: String?) async throws -> [PDFReaderRecovery] {
        defer { returnedRecoveryCount += 1 }
        if holdRecoveryLookup {
            holdRecoveryLookup = false
            return try await withCheckedThrowingContinuation { heldRecoveryLookup = $0 }
        }
        return []
    }
    func importPDF(at sourceURL: URL, for target: SourceAttachmentTarget, zoteroSource: ZoteroPDFSource?, allowNewVersion: Bool) async throws -> PDFReaderImport
    {
        guard let snapshot = notes[target.noteID] else { throw PDFReaderError.missing }
        let prepared = PDFReaderImport(snapshot: snapshot, noteRelativePath: "../.scholium/attachments/files/imported.pdf", wasNew: false)
        if holdImport {
            holdImport = false
            return try await withCheckedThrowingContinuation { heldImport = (prepared, $0) }
        }
        return prepared
    }
    func attachPDF(attachmentID: UUID, for target: SourceAttachmentTarget) async throws -> PDFReaderImport { throw PDFReaderError.missing }
    func importLocalCopy(_ candidate: ZoteroPDFLocalCopyCandidate, for target: SourceAttachmentTarget, allowNewVersion: Bool) async throws -> PDFReaderImport {
        try await importPDF(at: candidate.originalURL, for: target, zoteroSource: nil, allowNewVersion: allowNewVersion)
    }
    func loadPDF(attachmentID: UUID) async throws -> PDFReaderSnapshot {
        guard let snapshot = notes.values.first(where: { $0.record.id == attachmentID }) else { throw PDFReaderError.missing }
        return snapshot
    }
    func exportPDF(candidate: Data, to destination: URL) async throws { exports[destination] = candidate }
    func recoveryData(_ recovery: PDFReaderRecovery) async throws -> Data { throw PDFReaderError.missing }
    func recoveries(attachmentID: UUID) async throws -> [PDFReaderRecovery] { [] }
    func readingState(noteID: UUID, attachmentID: UUID) async throws -> PDFReaderReadingState? {
        positions[PositionKey(noteID: noteID, attachmentID: attachmentID)]
    }
    func saveReadingState(_ state: PDFReaderReadingState, noteID: UUID, attachmentID: UUID, windowID: UUID, attempt: UInt64) async throws {
        positions[PositionKey(noteID: noteID, attachmentID: attachmentID)] = state
    }
    func windowState(windowID: UUID) async throws -> PDFReaderWindowState? {
        if holdWindowState {
            holdWindowState = false
            return try await withCheckedThrowingContinuation { heldWindowState = (windowID, $0) }
        }
        return windows[windowID]
    }
    func saveWindowState(_ state: PDFReaderWindowState, windowID: UUID, attempt: UInt64) async throws { windows[windowID] = state }
}
