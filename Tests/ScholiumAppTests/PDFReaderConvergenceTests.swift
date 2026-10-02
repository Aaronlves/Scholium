import AppKit
import Combine
import Foundation
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Shared PDF reader convergence", .serialized)
@MainActor
struct PDFReaderConvergenceTests {
    @Test("A managed save refreshes a clean peer and preserves its page, zoom and point")
    func cleanPeerKeepsReadingPosition() async throws {
        let fixture = try Fixture()
        let position = PDFReaderReadingState(pageIndex: 1, pointX: 47, pointY: 511, scaleFactor: 1.6, autoScales: false)
        await fixture.operations.seedPosition(position, noteID: fixture.second.target.noteID)
        let first = fixture.reader()
        let second = fixture.reader()
        defer { fixture.cleanup([first, second]) }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await loaded(second)
        let original = try #require(second.document)
        try addComment("Shared annotation 注释", to: first)
        try await first.flushAnnotations()
        try await eventually { second.document !== original && second.annotations.count == 1 }
        #expect(second.annotations.first?.text == "Shared annotation 注释")
        #expect(second.annotationDraft == nil)
        #expect(second.canAnnotate)
        #expect(second.currentAttachmentID == fixture.attachmentID)
        try await second.flushAnnotations()
        #expect(await fixture.operations.position(for: fixture.second.target.noteID) == position)
        #expect(second.error == nil)
    }

    @Test("An open read-only annotation detail defers passive refresh until it closes")
    func annotationDetailDefersPassiveRefresh() async throws {
        let fixture = try Fixture(initialComment: "Keep reading this full comment 注释")
        let first = fixture.reader()
        let second = fixture.reader()
        defer { fixture.cleanup([first, second]) }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await loaded(second)
        let original = try #require(second.document)
        let annotation = try #require(original.page(at: 0)?.annotations.first)
        second.showAnnotation(annotation)
        let detail = try #require(second.annotationDetail)
        try addComment("New peer annotation", to: first)
        try await first.flushAnnotations()
        try await eventually { second.annotationDetailStatus != nil }
        #expect(second.document === original)
        #expect(second.annotationDetail?.annotation === detail.annotation)
        #expect(second.annotationDetail?.text == "Keep reading this full comment 注释")
        #expect(second.annotationDraft == nil)
        #expect(!second.hasUnsavedAnnotations)
        #expect(!second.canAnnotate)
        second.editAnnotation(annotation)
        #expect(second.annotationDraft == nil)
        #expect(second.annotationDetail?.annotation === annotation)
        second.closeAnnotationDetail()
        try await eventually { second.document !== original && second.annotations.count == 2 }
        #expect(second.annotationDetail == nil)
        #expect(second.annotationDetailStatus == nil)
        #expect(second.canAnnotate)
        #expect(second.error == nil)
        #expect(await fixture.operations.saveCount == 1)
    }

    @Test("A delayed activation check cannot falsely conflict with a verified local save")
    func oldExternalCheckCannotFlagNewSave() async throws {
        let fixture = try Fixture()
        let reader = fixture.reader()
        defer { fixture.cleanup([reader]) }
        reader.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(reader)
        await fixture.operations.holdNextRead()
        let checking = Task { @MainActor in await reader.checkExternalChanges() }
        defer { checking.cancel() }
        try await eventually { await fixture.operations.hasHeldRead }
        try addComment("A locally proven save", to: reader)
        try await reader.flushAnnotations()
        await fixture.operations.releaseRead()
        await checking.value
        #expect(reader.error == nil)
        #expect(reader.canAnnotate)
        #expect(reader.annotations.first?.text == "A locally proven save")
        #expect(await fixture.operations.readCount == 2)
    }

    @Test("Draft and failed-write peers retain their document and exportable local candidate", arguments: [false, true])
    func localWorkIsNeverReplaced(alreadyDirty: Bool) async throws {
        let fixture = try Fixture()
        let first = fixture.reader()
        var reports: [String] = []
        let second = fixture.reader(report: {
            reports.append($0)
            return UUID()
        })
        defer { fixture.cleanup([first, second]) }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await loaded(second)
        let original = try #require(second.document)
        let draft: PDFReaderAnnotationDraft?
        if alreadyDirty {
            await fixture.operations.failNextSave(.io("Controlled write failure"))
            try addComment("Local candidate must survive", to: second)
            try await eventually { !second.isSaving && second.hasUnsavedAnnotations }
            draft = nil
        } else {
            second.requestComment(on: try #require(original.page(at: 0)), at: NSPoint(x: 40, y: 40))
            draft = try #require(second.annotationDraft)
            second.annotationText = "Local candidate must survive"
        }
        try addComment("Peer's committed annotation", to: first)
        try await first.flushAnnotations()
        try await eventually { second.error == PDFReaderPresentationError.message(PDFReaderError.changed) }
        #expect(second.document === original)
        #expect(!second.canAnnotate)
        #expect(!reports.isEmpty)
        if let draft {
            #expect(second.annotationDraft?.id == draft.id)
            #expect(second.annotationText == "Local candidate must survive")
            #expect(second.canCommitDraft)
            second.commitComment(draft, text: second.annotationText)
            try await eventually { !second.isSaving && second.hasUnsavedAnnotations }
        }
        let export = fixture.exportURL
        try await second.exportAnnotations(to: export)
        let data = try #require(await fixture.operations.exported(at: export))
        let candidate = try #require(PDFDocument(data: data))
        #expect(candidate.page(at: 0)?.annotations.map(\.contents) == ["Local candidate must survive"])
        #expect(first.annotations.map(\.text) == ["Peer's committed annotation"])
        #expect(second.hasUnsavedAnnotations)
    }

    @Test("An active save is retained when a peer wins the checked file revision")
    func activeSaveCannotBeReplaced() async throws {
        let fixture = try Fixture()
        let first = fixture.reader()
        let second = fixture.reader()
        defer { fixture.cleanup([first, second]) }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await loaded(second)
        await fixture.operations.holdNextSave()
        try addComment("Held local annotation", to: second)
        try await eventually { await fixture.operations.hasHeldSave }
        let original = try #require(second.document)
        try addComment("Winning peer annotation", to: first)
        try await first.flushAnnotations()
        try await eventually { second.error == PDFReaderPresentationError.message(PDFReaderError.changed) }
        #expect(second.document === original)
        #expect(second.isSaving)
        #expect(second.hasUnsavedAnnotations)
        await fixture.operations.releaseSave()
        try await eventually { !second.isSaving }
        await #expect(throws: PDFReaderError.changed) { try await second.flushAnnotations() }
        try await second.exportAnnotations(to: fixture.exportURL)
        let data = try #require(await fixture.operations.exported(at: fixture.exportURL))
        #expect(PDFDocument(data: data)?.page(at: 0)?.annotations.first?.contents == "Held local annotation")
        #expect(second.document === original)
    }

    @Test("Invalidation hints are partitioned by Triptych, active store and attachment")
    func unrelatedScopesDoNotRefresh() async throws {
        let fixture = try Fixture()
        let first = fixture.reader()
        let peer = fixture.reader()
        let anotherStore = fixture.reader()
        let anotherTriptych = fixture.reader()
        let anotherAttachment = fixture.reader()
        defer { fixture.cleanup([first, peer, anotherStore, anotherTriptych, anotherAttachment]) }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        peer.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        anotherStore.follow(fixture.second, operations: fixture.operations, sharedStoreID: UUID())
        anotherTriptych.follow(
            PDFReaderNoteContext(triptychID: UUID(), target: fixture.second.target, authoredPath: fixture.second.authoredPath),
            operations: fixture.operations, sharedStoreID: fixture.storeID)
        anotherAttachment.follow(fixture.other, operations: fixture.operations, sharedStoreID: fixture.storeID)
        for reader in [first, peer, anotherStore, anotherTriptych, anotherAttachment] { try await loaded(reader) }
        let unaffected = [anotherStore, anotherTriptych, anotherAttachment].map { $0.document }
        try addComment("Scoped save", to: first)
        try await first.flushAnnotations()
        try await eventually { peer.annotations.count == 1 }
        await drainNotifications()
        for (reader, original) in zip([anotherStore, anotherTriptych, anotherAttachment], unaffected) {
            #expect(reader.document === original)
            #expect(reader.annotations.isEmpty)
            #expect(reader.error == nil)
        }
        #expect(await fixture.operations.readCount == 1)
    }

    @Test("A confirmed save during delayed initial admission cannot install a stale PDF")
    func initialLoadRechecksMissedHint() async throws {
        let fixture = try Fixture()
        await fixture.operations.holdPosition(for: fixture.second.target.noteID)
        let first = fixture.reader()
        let second = fixture.reader()
        var publishedAnnotations: [Int] = []
        let observation = second.$document.sink { document in
            if let document { publishedAnnotations.append(document.page(at: 0)?.annotations.count ?? 0) }
        }
        defer {
            observation.cancel()
            fixture.cleanup([first, second])
        }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await eventually { await fixture.operations.hasHeldPosition }
        #expect(second.document == nil)
        try addComment("Committed before initial publication", to: first)
        try await first.flushAnnotations()
        await drainNotifications()
        await fixture.operations.releasePosition()
        try await loaded(second)
        #expect(publishedAnnotations == [1])
        #expect(second.annotations.first?.text == "Committed before initial publication")
        #expect(await fixture.operations.readCount == 1)
    }

    @Test("Repeated saves supersede an older delayed peer read")
    func delayedReadCannotUndoNewerRefresh() async throws {
        let fixture = try Fixture()
        let first = fixture.reader()
        let second = fixture.reader()
        defer { fixture.cleanup([first, second]) }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await loaded(second)
        await fixture.operations.holdNextRead()
        try addComment("First save", to: first)
        try await first.flushAnnotations()
        try await eventually { await fixture.operations.hasHeldRead }
        try addComment("Second save", to: first)
        try await first.flushAnnotations()
        try await eventually { second.annotations.count == 2 }
        let current = try #require(second.document)
        await fixture.operations.releaseRead()
        await drainNotifications()
        #expect(second.document === current)
        #expect(second.annotations.map(\.text) == ["First save", "Second save"])
        #expect(second.error == nil)
    }

    @Test("A repeated invalidation hint cannot replace a newer verified local commit")
    func delayedPeerReadRechecksLocalCommit() async throws {
        let fixture = try Fixture()
        let first = fixture.reader()
        let second = fixture.reader()
        var savedHint: PDFReaderSharedSaveHint?
        let observation = fixture.center.publisher(for: PDFReaderController.sharedPDFSavedNotification).sink { notification in
            savedHint = notification.object as? PDFReaderSharedSaveHint
        }
        defer {
            observation.cancel()
            fixture.cleanup([first, second])
        }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await loaded(second)
        try addComment("First reader's save", to: first)
        try await first.flushAnnotations()
        try await eventually { second.annotations.count == 1 }
        let hint = try #require(savedHint)
        await fixture.operations.holdNextRead()
        fixture.center.post(name: PDFReaderController.sharedPDFSavedNotification, object: hint)
        try await eventually { await fixture.operations.hasHeldRead }
        let current = try #require(second.document)
        try addComment("Second reader's newer save", to: second)
        try await second.flushAnnotations()
        await fixture.operations.releaseRead()
        await drainNotifications()
        try await eventually { first.annotations.count == 2 }
        #expect(second.document === current)
        #expect(second.annotations.map(\.text) == ["First reader's save", "Second reader's newer save"])
        #expect(second.canAnnotate)
        #expect(second.error == nil)
    }

    @Test("Navigation and shutdown revoke a delayed peer completion", arguments: [false, true])
    func delayedReadCannotPublishAfterDeparture(shutdown: Bool) async throws {
        let fixture = try Fixture()
        let first = fixture.reader()
        let second = fixture.reader()
        defer { fixture.cleanup([first, second]) }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await loaded(second)
        await fixture.operations.holdNextRead()
        try addComment("Old attachment update", to: first)
        try await first.flushAnnotations()
        try await eventually { await fixture.operations.hasHeldRead }
        if shutdown {
            second.shutdown()
        } else {
            second.follow(fixture.other, operations: fixture.operations, sharedStoreID: fixture.storeID)
            #expect(second.currentAttachmentID == nil)
            try await loaded(second)
            #expect(second.currentAttachmentID == fixture.otherAttachmentID)
        }
        let current = second.document
        await fixture.operations.releaseRead()
        await drainNotifications()
        #expect(second.document === current)
        #expect(second.annotations.isEmpty)
        #expect(second.error == nil)
        let reads = await fixture.operations.readCount
        try addComment("Another old attachment update", to: first)
        try await first.flushAnnotations()
        await drainNotifications()
        #expect(await fixture.operations.readCount == reads)
        #expect(second.document === current)
    }

    @Test("Only a successful same-attachment explicit reload resolves owned issue IDs")
    func reloadResolvesOnlyOwnedIssues() async throws {
        let fixture = try Fixture()
        let unrelated = UUID()
        var visibleIssues: Set<UUID> = [unrelated]
        var reported: Set<UUID> = []
        var resolved: Set<UUID> = []
        let first = fixture.reader()
        let second = fixture.reader(
            report: { _ in
                let id = UUID()
                visibleIssues.insert(id)
                reported.insert(id)
                return id
            },
            resolve: { id in
                resolved.insert(id)
                visibleIssues.remove(id)
            })
        defer { fixture.cleanup([first, second]) }
        first.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        second.follow(fixture.second, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(first)
        try await loaded(second)
        await fixture.operations.failNextSave(.io("Controlled failure"))
        try addComment("Export before reload", to: second)
        try await eventually { !second.isSaving && second.hasUnsavedAnnotations }
        try addComment("Fresh peer content", to: first)
        try await first.flushAnnotations()
        try await eventually { second.error == PDFReaderPresentationError.message(PDFReaderError.changed) }
        await second.reload()
        #expect(resolved.isEmpty)
        try await second.exportAnnotations(to: fixture.exportURL)
        await fixture.operations.failNextBoundLoad()
        await second.reload(discardExportedChanges: true)
        try await eventually { !second.isLoading && second.error != nil && second.document == nil }
        #expect(resolved.isEmpty)
        await second.reload()
        try await loaded(second)
        #expect(resolved == reported)
        #expect(visibleIssues == [unrelated])
        #expect(second.annotations.first?.text == "Fresh peer content")
    }

    @Test("A verified retry resolves its issues only while its originating context remains selected", arguments: [false, true])
    func retryResolutionIsContextScoped(departed: Bool) async throws {
        let fixture = try Fixture()
        let issue = UUID()
        var resolved: [UUID] = []
        let reader = fixture.reader(report: { _ in issue }, resolve: { resolved.append($0) })
        defer { fixture.cleanup([reader]) }
        reader.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(reader)
        await fixture.operations.failNextSave(.io("Transient fixture failure"))
        try addComment("Retried candidate", to: reader)
        try await eventually { !reader.isSaving && reader.hasUnsavedAnnotations }
        await fixture.operations.holdNextSave()
        reader.retrySave()
        try await eventually { await fixture.operations.hasHeldSave }
        if departed { reader.follow(fixture.other, operations: fixture.operations, sharedStoreID: fixture.storeID) }
        await fixture.operations.releaseSave()
        try await eventually { !reader.isSaving }
        if departed {
            try await loaded(reader)
            #expect(reader.currentAttachmentID == fixture.otherAttachmentID)
            #expect(resolved.isEmpty)
        } else {
            #expect(resolved == [issue])
            #expect(reader.canAnnotate)
        }
    }

    @Test("Annotation detail is readable without mutation permission and has bounded lifetime", arguments: [false, true])
    func annotationDetailIsReadOnly(restricted: Bool) async throws {
        let text = "完整注释 😀\n" + String(repeating: "Complete comment. ", count: 30)
        let fixture = try Fixture(initialComment: text, restricted: restricted)
        let reader = fixture.reader()
        defer { fixture.cleanup([reader]) }
        reader.follow(fixture.first, operations: fixture.operations, sharedStoreID: fixture.storeID)
        try await loaded(reader)
        let annotation = try #require(reader.document?.page(at: 0)?.annotations.first)
        reader.showAnnotation(annotation)
        #expect(reader.annotationDetail?.text == text)
        #expect(reader.annotationDraft == nil)
        #expect(await fixture.operations.saveCount == 0)
        if restricted {
            #expect(reader.document?.allowsCommenting == false)
            #expect(!reader.canAnnotate)
            reader.editAnnotation(annotation)
            #expect(reader.annotationDraft == nil)
            #expect(reader.annotationDetail?.text == text)
        } else {
            reader.editAnnotation(annotation)
            #expect(reader.annotationDetail == nil)
            #expect(reader.annotationDraft?.text == text)
            reader.cancelComment()
            reader.showAnnotation(annotation)
        }
        reader.setVisible(false)
        #expect(reader.annotationDetail == nil)
        reader.setVisible(true)
        reader.showAnnotation(annotation)
        reader.follow(fixture.other, operations: fixture.operations, sharedStoreID: fixture.storeID)
        #expect(reader.annotationDetail == nil)
        #expect(reader.currentAttachmentID == nil)
        try await loaded(reader)
        #expect(reader.currentAttachmentID == fixture.otherAttachmentID)
    }

    private func loaded(_ reader: PDFReaderController) async throws {
        try await eventually { reader.document != nil && !reader.isLoading }
    }

    private func eventually(_ condition: @escaping @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        try #require(await condition(), "The controlled PDF convergence boundary was not reached.")
    }

    private func addComment(_ text: String, to reader: PDFReaderController) throws {
        reader.requestComment(on: try #require(reader.document?.page(at: 0)), at: NSPoint(x: 40, y: 40))
        reader.commitComment(try #require(reader.annotationDraft), text: text)
    }

    private func drainNotifications() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    @MainActor
    private struct Fixture {
        let storeID = UUID()
        let center = NotificationCenter()
        let first: PDFReaderNoteContext
        let second: PDFReaderNoteContext
        let other: PDFReaderNoteContext
        let attachmentID: UUID
        let otherAttachmentID: UUID
        let operations: ConvergencePDFOperations
        let exportURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/pdf-reader-convergence/\(UUID())/export.pdf")

        init(initialComment: String? = nil, restricted: Bool = false) throws {
            let triptychID = UUID()
            let vaultID = UUID()
            first = .init(triptychID: triptychID, target: .init(noteID: UUID(), vaultID: vaultID, relativePath: "First.md"), authoredPath: "../shared.pdf")
            second = .init(triptychID: triptychID, target: .init(noteID: UUID(), vaultID: vaultID, relativePath: "Second.md"), authoredPath: "../shared.pdf")
            other = .init(triptychID: triptychID, target: .init(noteID: UUID(), vaultID: vaultID, relativePath: "Other.md"), authoredPath: "../other.pdf")
            let data = try Self.pdfData(initialComment: initialComment, restricted: restricted)
            let shared = try Self.snapshot("shared.pdf", data: data)
            let separate = try Self.snapshot("other.pdf", data: data)
            attachmentID = shared.record.id
            otherAttachmentID = separate.record.id
            operations = ConvergencePDFOperations(
                snapshots: [attachmentID: shared, otherAttachmentID: separate],
                notes: [first.target.noteID: attachmentID, second.target.noteID: attachmentID, other.target.noteID: otherAttachmentID])
        }

        func reader(report: @escaping @MainActor (String) -> UUID? = { _ in nil }, resolve: @escaping @MainActor (UUID) -> Void = { _ in })
            -> PDFReaderController
        {
            let reader = PDFReaderController(
                windowID: UUID(), setBinding: { _, _, _ in }, reportIssue: report, resolveIssue: resolve, notificationCenter: center)
            reader.setVisible(true)
            return reader
        }

        func cleanup(_ readers: [PDFReaderController]) {
            for reader in readers { reader.shutdown() }
            Task { await operations.cancelPending() }
        }

        private static func snapshot(_ filename: String, data: Data) throws -> PDFReaderSnapshot {
            let id = UUID()
            return PDFReaderSnapshot(
                record: PortableAttachmentRecord(
                    id: id, vaultID: nil, location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(id.uuidString.lowercased())/\(filename)"))
                ),
                data: data, revision: .init(fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
        }

        private static func pdfData(initialComment: String?, restricted: Bool) throws -> Data {
            let data = NSMutableData()
            let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            for _ in 0..<2 {
                context.beginPDFPage(nil)
                context.endPDFPage()
            }
            context.closePDF()
            let document = try #require(PDFDocument(data: data as Data))
            if let initialComment {
                let annotation = PDFAnnotation(bounds: CGRect(x: 40, y: 40, width: 24, height: 24), forType: .text, withProperties: nil)
                annotation.contents = initialComment
                document.page(at: 0)?.addAnnotation(annotation)
            }
            if restricted {
                return try #require(
                    document.dataRepresentation(options: [
                        PDFDocumentWriteOption.ownerPasswordOption: "fixture-owner", PDFDocumentWriteOption.userPasswordOption: "",
                        PDFDocumentWriteOption.accessPermissionsOption: NSNumber(value: 0),
                    ]))
            }
            return try #require(document.dataRepresentation())
        }
    }
}

private actor ConvergencePDFOperations: PDFReaderUseCases {
    private struct HeldRead {
        let snapshot: PDFReaderSnapshot
        let continuation: CheckedContinuation<PDFReaderSnapshot, any Error>
    }
    private struct HeldSave {
        let candidate: Data
        let expected: PDFReaderSnapshot
        let continuation: CheckedContinuation<PDFReaderSnapshot, any Error>
    }
    private var snapshots: [UUID: PDFReaderSnapshot]
    private let notes: [UUID: UUID]
    private var positions: [UUID: PDFReaderReadingState] = [:]
    private var holdRead = false
    private var heldRead: HeldRead?
    private var holdSave = false
    private var heldSave: HeldSave?
    private var heldPositionNote: UUID?
    private var heldPosition: (UUID, CheckedContinuation<PDFReaderReadingState?, any Error>)?
    private var nextSaveError: PDFReaderError?
    private var failBound = false
    private var exports: [URL: Data] = [:]
    private(set) var readCount = 0
    private(set) var saveCount = 0

    init(snapshots: [UUID: PDFReaderSnapshot], notes: [UUID: UUID]) {
        self.snapshots = snapshots
        self.notes = notes
    }
    var hasHeldRead: Bool { heldRead != nil }
    var hasHeldSave: Bool { heldSave != nil }
    var hasHeldPosition: Bool { heldPosition != nil }
    func holdNextRead() { holdRead = true }
    func holdNextSave() { holdSave = true }
    func holdPosition(for noteID: UUID) { heldPositionNote = noteID }
    func failNextSave(_ error: PDFReaderError) { nextSaveError = error }
    func failNextBoundLoad() { failBound = true }
    func seedPosition(_ position: PDFReaderReadingState, noteID: UUID) { positions[noteID] = position }
    func position(for noteID: UUID) -> PDFReaderReadingState? { positions[noteID] }
    func exported(at url: URL) -> Data? { exports[url] }
    func releaseRead() {
        guard let heldRead else { return }
        self.heldRead = nil
        heldRead.continuation.resume(returning: heldRead.snapshot)
    }
    func releaseSave() {
        guard let heldSave else { return }
        self.heldSave = nil
        do { heldSave.continuation.resume(returning: try commit(heldSave.candidate, expected: heldSave.expected)) } catch {
            heldSave.continuation.resume(throwing: error)
        }
    }
    func releasePosition() {
        guard let (noteID, continuation) = heldPosition else { return }
        heldPosition = nil
        continuation.resume(returning: positions[noteID])
    }
    func cancelPending() {
        heldRead?.continuation.resume(throwing: CancellationError())
        heldRead = nil
        heldSave?.continuation.resume(throwing: CancellationError())
        heldSave = nil
        heldPosition?.1.resume(throwing: CancellationError())
        heldPosition = nil
    }
    func boundPDF(for target: SourceAttachmentTarget, authoredPath: String?) async throws -> PDFReaderSnapshot? {
        if failBound {
            failBound = false
            throw PDFReaderError.missing
        }
        guard let id = notes[target.noteID] else { throw PDFReaderError.missing }
        return snapshots[id]
    }
    func loadPDF(attachmentID: UUID) async throws -> PDFReaderSnapshot {
        readCount += 1
        guard let snapshot = snapshots[attachmentID] else { throw PDFReaderError.missing }
        if holdRead {
            holdRead = false
            return try await withCheckedThrowingContinuation { heldRead = HeldRead(snapshot: snapshot, continuation: $0) }
        }
        return snapshot
    }
    func savePDF(candidate: Data, expected: PDFReaderSnapshot) async throws -> PDFReaderSnapshot {
        saveCount += 1
        if let error = nextSaveError {
            nextSaveError = nil
            throw error
        }
        if holdSave {
            holdSave = false
            return try await withCheckedThrowingContinuation { heldSave = HeldSave(candidate: candidate, expected: expected, continuation: $0) }
        }
        return try commit(candidate, expected: expected)
    }
    private func commit(_ candidate: Data, expected: PDFReaderSnapshot) throws -> PDFReaderSnapshot {
        guard let current = snapshots[expected.record.id], current.revision == expected.revision else { throw PDFReaderError.changed }
        let saved = PDFReaderSnapshot(
            record: expected.record, data: candidate,
            revision: .init(fingerprint: DocumentFingerprint(data: candidate), device: 1, inode: expected.revision.inode + 1, parentDevice: 1, parentInode: 1))
        snapshots[expected.record.id] = saved
        return saved
    }
    func readingState(noteID: UUID, attachmentID: UUID) async throws -> PDFReaderReadingState? {
        if heldPositionNote == noteID {
            heldPositionNote = nil
            return try await withCheckedThrowingContinuation { heldPosition = (noteID, $0) }
        }
        return positions[noteID]
    }
    func saveReadingState(_ state: PDFReaderReadingState, noteID: UUID, attachmentID: UUID, windowID: UUID, attempt: UInt64) async throws {
        positions[noteID] = state
    }
    func availablePDFs() async throws -> [PortableAttachmentRecord] { snapshots.values.map(\.record) }
    func boundPDFRecoveries(for target: SourceAttachmentTarget, authoredPath: String?) async throws -> [PDFReaderRecovery] { [] }
    func importPDF(at sourceURL: URL, for target: SourceAttachmentTarget, zoteroSource: ZoteroPDFSource?, allowNewVersion: Bool) async throws -> PDFReaderImport
    {
        throw PDFReaderError.missing
    }
    func importLocalCopy(_ candidate: ZoteroPDFLocalCopyCandidate, for target: SourceAttachmentTarget, allowNewVersion: Bool) async throws -> PDFReaderImport {
        throw PDFReaderError.missing
    }
    func attachPDF(attachmentID: UUID, for target: SourceAttachmentTarget) async throws -> PDFReaderImport { throw PDFReaderError.missing }
    func exportPDF(candidate: Data, to destination: URL) async throws { exports[destination] = candidate }
    func recoveryData(_ recovery: PDFReaderRecovery) async throws -> Data { throw PDFReaderError.missing }
    func recoveries(attachmentID: UUID) async throws -> [PDFReaderRecovery] { [] }
    func windowState(windowID: UUID) async throws -> PDFReaderWindowState? { nil }
    func saveWindowState(_ state: PDFReaderWindowState, windowID: UUID, attempt: UInt64) async throws {}
}
