import AppKit
import Combine
import Foundation
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("PDF reader window transfer", .serialized)
@MainActor
struct PDFReaderWindowTransferTests {
    @Test("Move Back retains Note Info drafts unless their discard is explicit", arguments: [false, true])
    func moveBackSettlesNoteInfo(discard: Bool) async throws {
        try await withFixture { fixture in
            let coordinator = fixture.attachDetachedContainer()
            defer { coordinator.closeTransferredContainer() }
            let info = fixture.noteInfo()
            fixture.source.noteInfoWindowController = info
            info.model.summary = "Unapplied transfer draft"
            info.discardConfirmation = { discard }
            defer { info.close() }
            if discard {
                try await fixture.store.documentLocations.moveBack(from: fixture.source)
                #expect(!info.model.hasChanges)
                #expect(fixture.source.documentTabController.tabs.isEmpty)
                #expect(fixture.destination.documentController.selectedDocument == fixture.sourceDocument)
            } else {
                await #expect(throws: CancellationError.self) {
                    try await fixture.store.documentLocations.moveBack(from: fixture.source)
                }
                fixture.expectOriginalSelections()
                #expect(info.model.summary == "Unapplied transfer draft")
                #expect(info.model.hasChanges)
                #expect(!fixture.source.transferInProgress)
            }
        }
    }

    @Test("Move Back cannot close Note Info while Apply is in progress")
    func moveBackDuringNoteInfoApply() async throws {
        try await withFixture { fixture in
            let coordinator = fixture.attachDetachedContainer()
            defer { coordinator.closeTransferredContainer() }
            var release: CheckedContinuation<Void, Never>?
            let info = fixture.noteInfo { context, _ in
                await withCheckedContinuation { release = $0 }
                return context
            }
            defer {
                release?.resume()
                info.close()
            }
            fixture.source.noteInfoWindowController = info
            info.model.summary = "Applying transfer draft"
            info.model.apply()
            try await eventually { release != nil }
            await #expect(throws: CancellationError.self) {
                try await fixture.store.documentLocations.moveBack(from: fixture.source)
            }
            fixture.expectOriginalSelections()
            #expect(info.model.isWorking)
            #expect(info.model.summary == "Applying transfer draft")
            release?.resume()
            release = nil
            try await eventually { !info.model.isWorking }
        }
    }

    @Test("Accepted Note Info closes before an origin close waits for PDF persistence")
    func originCloseCannotAcceptAnotherInfoDraft() async throws {
        try await withFixture { fixture in
            let info = fixture.noteInfo()
            fixture.source.noteInfoWindowController = info
            info.onClose = { fixture.source.noteInfoWindowController = nil }
            info.model.summary = "Explicitly discarded before close"
            info.discardConfirmation = { true }
            await fixture.operations.holdNextSave()
            try addComment("Held origin-close save", to: fixture.source.pdfReaderController)
            try await eventually { await fixture.operations.hasHeldSave }
            var completed = false
            let closing = Task { @MainActor in
                _ = try await fixture.source.windowCloseCoordinator.prepare()
                completed = true
            }
            defer { closing.cancel() }
            try await eventually { fixture.source.noteInfoWindowController == nil }
            #expect(!completed)
            #expect(!info.model.hasChanges)
            fixture.source.showNoteInfo()
            await Task.yield()
            #expect(fixture.source.noteInfoWindowController == nil)
            await fixture.operations.releaseSave()
            try await closing.value
            #expect(completed)
        }
    }

    @Test("Moving a Note waits for either window's annotation save", arguments: [false, true])
    func transferWaitsForPDFSave(inDestination: Bool) async throws {
        try await withFixture { fixture in
            let reader = inDestination ? fixture.destination.pdfReaderController : fixture.source.pdfReaderController
            await fixture.operations.holdNextSave()
            try addComment("Save before moving 注释", to: reader)
            try await eventually { await fixture.operations.hasHeldSave }
            var completed = false
            let movement = Task { @MainActor in
                try await fixture.move()
                completed = true
            }
            defer { movement.cancel() }
            try await eventually { fixture.destination.transferInProgress }
            await Task.yield()
            #expect(!completed)
            fixture.expectOriginalSelections()
            #expect(!fixture.source.pdfReaderController.canAnnotate)
            #expect(!fixture.destination.pdfReaderController.canAnnotate)

            await fixture.operations.releaseSave()
            try await movement.value
            #expect(completed)
            #expect(fixture.source.documentTabController.tabs.isEmpty)
            #expect(fixture.destination.documentController.selectedDocument == fixture.sourceDocument)
            let noteID = inDestination ? fixture.second.target.noteID : fixture.first.target.noteID
            let saved = try #require(await fixture.operations.savedPDF(for: noteID))
            let document = try #require(PDFDocument(data: saved.data))
            #expect(document.page(at: 0)?.annotations.first?.contents == "Save before moving 注释")
        }
    }

    @Test("An unfinished comment keeps both windows' Notes and draft ownership intact", arguments: [false, true])
    func draftStopsTransfer(inDestination: Bool) async throws {
        try await withFixture { fixture in
            let reader = inDestination ? fixture.destination.pdfReaderController : fixture.source.pdfReaderController
            let page = try #require(reader.document?.page(at: 0))
            reader.requestComment(on: page, at: NSPoint(x: 40, y: 40))
            let draft = try #require(reader.annotationDraft)
            await #expect(throws: (any Error).self) { try await fixture.move() }
            fixture.expectOriginalSelections()
            #expect(reader.annotationDraft?.id == draft.id)
            #expect(reader.document === page.document)
            #expect(reader.canCommitDraft)
            #expect(!fixture.source.transferInProgress)
            #expect(!fixture.destination.transferInProgress)
            #expect(await fixture.operations.saveCount == 0)
            reader.cancelComment()
            #expect(reader.canAnnotate)
        }
    }

    @Test("An annotation save failure stops transfer without losing its exportable candidate", arguments: [false, true])
    func failedPDFSaveStopsTransfer(inDestination: Bool) async throws {
        try await withFixture { fixture in
            let reader = inDestination ? fixture.destination.pdfReaderController : fixture.source.pdfReaderController
            await fixture.operations.failNextSave(with: .changed)
            try addComment("Keep this failed candidate", to: reader)
            try await eventually { !reader.isSaving && reader.hasUnsavedAnnotations }
            await #expect(throws: PDFReaderError.changed) { try await fixture.move() }
            fixture.expectOriginalSelections()
            #expect(reader.hasUnsavedAnnotations)
            let export = fixture.root.appendingPathComponent("export.pdf")
            try await reader.exportAnnotations(to: export)
            let candidate = try #require(await fixture.operations.exportedData(at: export))
            let document = try #require(PDFDocument(data: candidate))
            #expect(document.page(at: 0)?.annotations.first?.contents == "Keep this failed candidate")
            let noteID = inDestination ? fixture.second.target.noteID : fixture.first.target.noteID
            let unchanged = try #require(await fixture.operations.savedPDF(for: noteID))
            #expect(unchanged.data == fixture.originalPDF)
            #expect(!fixture.destination.transferInProgress)
        }
    }

    @Test("Reader mutations stay frozen while Markdown transfer preparation suspends")
    func markdownPreparationCannotAcceptNewPDFDraft() async throws {
        try await withFixture { fixture in
            var release: CheckedContinuation<Void, Never>?
            let markdownSave = Task<EditorSaveOutcome, any Error> { @MainActor in
                await withCheckedContinuation { release = $0 }
                fixture.sourceSession.activeSaveTask = nil
                return .clean
            }
            fixture.sourceSession.activeSaveTask = markdownSave
            // Preparation clears this existing autosave slot immediately
            // before joining the held Markdown save, proving the wait owner.
            fixture.sourceSession.autosaveTask = Task {}
            defer {
                release?.resume()
                markdownSave.cancel()
                fixture.sourceSession.activeSaveTask = nil
            }
            try await eventually { release != nil }
            var completed = false
            let movement = Task { @MainActor in
                try await fixture.move()
                completed = true
            }
            defer { movement.cancel() }
            try await eventually { fixture.sourceSession.autosaveTask == nil && fixture.destination.transferInProgress }
            fixture.expectOriginalSelections()
            #expect(!completed)
            for model in [fixture.source, fixture.destination] {
                let reader = model.pdfReaderController
                reader.requestComment(on: try #require(reader.document?.page(at: 0)), at: NSPoint(x: 40, y: 40))
                reader.requestAttachPDF()
                reader.setVisible(false)
                #expect(reader.annotationDraft == nil)
                #expect(!reader.attachRequested)
                #expect(reader.isVisible)
                #expect(!reader.canAnnotate)
                #expect(!reader.canAttach)
            }
            release?.resume()
            release = nil
            try await movement.value
            #expect(completed)
            #expect(await fixture.operations.saveCount == 0)
            #expect(fixture.destination.documentController.selectedDocument == fixture.sourceDocument)
        }
    }

    @Test("Rollback restores the authoritative PDF context before departure protection ends")
    func rollbackRestoresPDFContext() async throws {
        try await withFixture { fixture in
            var detached = false
            let observation = fixture.source.documentController.$selectedDocument.dropFirst().sink { selected in
                guard selected == nil else { return }
                detached = true
                // Represent a destination disappearing after the source session
                // has detached, plus the native view following that empty source.
                fixture.destination.isRestoringWindowSession = true
                fixture.source.pdfReaderController.follow(nil, operations: nil)
            }
            defer {
                observation.cancel()
                fixture.destination.isRestoringWindowSession = false
            }
            await #expect(throws: (any Error).self) { try await fixture.move() }
            #expect(detached)
            fixture.expectOriginalSelections()
            #expect(fixture.source.pdfReaderController.context == fixture.first)
            #expect(fixture.destination.pdfReaderController.context == fixture.second)
            #expect(!fixture.source.pdfReaderController.isDeparting)
            #expect(!fixture.destination.pdfReaderController.isDeparting)
            #expect(await fixture.operations.saveCount == 0)
        }
    }

    @Test("Note Info cannot detach a PDF with an unfinished comment or retained failed save", arguments: [false, true])
    func noteInfoDetachRetainsUnfinishedPDF(failedSave: Bool) async throws {
        try await withFixture { fixture in
            let reader = fixture.source.pdfReaderController
            let context = try fixture.boundNoteInfoContext()
            let originalSource = try Data(contentsOf: context.fileURL)
            let originalDocument = try #require(reader.document)
            if failedSave {
                await fixture.operations.failNextSave(with: .changed)
                try addComment("Retained Note Info detach candidate", to: reader)
                try await eventually { !reader.isSaving && reader.hasUnsavedAnnotations }
            } else {
                reader.requestComment(on: try #require(originalDocument.page(at: 0)), at: NSPoint(x: 40, y: 40))
                reader.annotationText = "Unfinished Note Info detach draft"
            }
            await #expect(throws: (any Error).self) {
                try await fixture.source.applyNoteInfoPanelChanges(context, edits: ["pdf": .remove])
            }
            fixture.expectOriginalSelections()
            #expect(try Data(contentsOf: context.fileURL) == originalSource)
            #expect(reader.document === originalDocument && reader.context == fixture.first)
            #expect(!reader.isDeparting)
            if failedSave {
                #expect(reader.hasUnsavedAnnotations)
                let export = fixture.root.appendingPathComponent("note-info-candidate.pdf")
                try await reader.exportAnnotations(to: export)
                let data = try #require(await fixture.operations.exportedData(at: export))
                #expect(PDFDocument(data: data)?.page(at: 0)?.annotations.first?.contents == "Retained Note Info detach candidate")
            } else {
                #expect(reader.canCommitDraft && reader.annotationText == "Unfinished Note Info detach draft")
                reader.cancelComment()
            }
        }
    }

    @Test("Note Info PDF detach waits for save and revalidates its source before changing Markdown")
    func noteInfoDetachWaitsForSave() async throws {
        try await withFixture { fixture in
            let context = try fixture.boundNoteInfoContext()
            let originalSource = try Data(contentsOf: context.fileURL)
            let reader = fixture.source.pdfReaderController
            await fixture.operations.holdNextSave()
            try addComment("Saved before Note Info detach", to: reader)
            try await eventually { await fixture.operations.hasHeldSave }
            var completed = false
            let detach = Task { @MainActor in
                defer { completed = true }
                return try await fixture.source.applyNoteInfoPanelChanges(context, edits: ["pdf": .remove])
            }
            defer {
                detach.cancel()
                fixture.source.transferInProgress = false
            }
            try await eventually { reader.isDeparting }
            #expect(!completed && !reader.canAnnotate && !reader.canAttach)
            #expect(try Data(contentsOf: context.fileURL) == originalSource)
            // An independently begun transition invalidates the panel's authority
            // while save is held. Completion must check that authority again.
            fixture.source.transferInProgress = true
            await fixture.operations.releaseSave()
            await #expect(throws: (any Error).self) { try await detach.value }
            #expect(completed && !reader.isDeparting && !reader.hasUnsavedAnnotations)
            #expect(try Data(contentsOf: context.fileURL) == originalSource)
            let saved = try #require(await fixture.operations.savedPDF(for: fixture.first.target.noteID))
            #expect(PDFDocument(data: saved.data)?.page(at: 0)?.annotations.first?.contents == "Saved before Note Info detach")
        }
    }

    private func addComment(_ text: String, to reader: PDFReaderController) throws {
        reader.requestComment(on: try #require(reader.document?.page(at: 0)), at: NSPoint(x: 40, y: 40))
        reader.commitComment(try #require(reader.annotationDraft), text: text)
    }

    private func eventually(_ condition: @escaping @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        try #require(await condition(), "The controlled transfer did not reach its expected boundary.")
    }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let fixture = try await Fixture()
        do {
            try await eventually {
                fixture.source.pdfReaderController.document != nil && !fixture.source.pdfReaderController.isLoading
                    && fixture.destination.pdfReaderController.document != nil && !fixture.destination.pdfReaderController.isLoading
            }
            try await body(fixture)
        } catch {
            await fixture.close()
            throw error
        }
        await fixture.close()
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let store: WorkspaceStore
        let source: WindowModel
        let destination: WindowModel
        let first: PDFReaderNoteContext
        let second: PDFReaderNoteContext
        let originalPDF: Data
        let operations: ControlledPDFReaderOperations
        let sourceDocument: WindowSelectedDocument
        let destinationDocument: WindowSelectedDocument
        let sourceSession: DocumentSessionModel
        let destinationSession: DocumentSessionModel
        let tab: DocumentTabItem

        init() async throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/pdf-reader-transfer-fixtures/\(UUID())", isDirectory: true)
            let container = root.appendingPathComponent("triptych", isDirectory: true)
            let vaults = ["analyses", "topics", "works"].map { container.appendingPathComponent($0, isDirectory: true) }
            for vault in vaults { try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true) }
            let firstID = UUID()
            let secondID = UUID()
            // Index the durable Notes at configuration, before any live window
            // projection can reconcile a controlled transfer against the disk.
            for (id, filename, pdf) in [(firstID, "First.md", "first.pdf"), (secondID, "Second.md", "second.pdf")] {
                let source = "---\nid: \(id.uuidString)\npdf: ../\(pdf)\n---\n\nSynthetic Note.\n"
                try Data(source.utf8).write(to: vaults[0].appendingPathComponent(filename))
            }
            store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("state", isDirectory: true))
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: container, triptychName: "PDF transfer fixture")
            let vaultID = try #require(configured.assignment.vault(for: .paperAnalysis)?.id)
            first = PDFReaderNoteContext(
                triptychID: configured.id, target: .init(noteID: firstID, vaultID: vaultID, relativePath: "First.md"), authoredPath: "../first.pdf")
            second = PDFReaderNoteContext(
                triptychID: configured.id, target: .init(noteID: secondID, vaultID: vaultID, relativePath: "Second.md"), authoredPath: "../second.pdf")
            originalPDF = try Self.pdfData()
            operations = ControlledPDFReaderOperations(notes: [
                first.target.noteID: try Self.pdfSnapshot("first.pdf", data: originalPDF),
                second.target.noteID: try Self.pdfSnapshot("second.pdf", data: originalPDF),
            ])
            source = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            destination = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            // This fixture controls transition and save scheduling explicitly;
            // workspace-event convergence has its own integration suites.
            source.workspaceCancellables.removeAll()
            destination.workspaceCancellables.removeAll()
            await source.restoreWindowSession(id: source.nativeWindowID)
            await destination.restoreWindowSession(id: destination.nativeWindowID)
            await source.waitForDocumentTransitions()
            await destination.waitForDocumentTransitions()
            sourceDocument = try Self.install(first, in: source)
            destinationDocument = try Self.install(second, in: destination)
            sourceSession = source.documentController.session(for: sourceDocument.editingTarget)
            destinationSession = destination.documentController.session(for: destinationDocument.editingTarget)
            tab = try #require(source.documentTabController.selectedTab)
            for (model, context) in [(source, first), (destination, second)] {
                model.pdfReaderController = PDFReaderController(windowID: model.nativeWindowID, setBinding: { _, _, _ in }, reportIssue: { _ in nil })
                model.pdfReaderController.setVisible(true)
                model.pdfReaderController.follow(context, operations: operations, sharedStoreID: configured.runtimeIdentity.activationID)
            }
        }

        func move() async throws {
            source.transferInProgress = true
            defer { source.transferInProgress = false }
            try await store.documentLocations.transfer(tab, from: source, to: destination)
        }

        func attachDetachedContainer() -> WorkspaceWindowCoordinator {
            source.isDetachedDocumentWindow = true
            let coordinator = WorkspaceWindowCoordinator(
                windowID: source.nativeWindowID, appState: source,
                lifecycleRegistry: ScholiumWindowLifecycleRegistry())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            coordinator.attach(to: window)
            store.documentLocations.register(destination)
            return coordinator
        }

        func noteInfo(
            apply: @escaping @MainActor (NoteInfoContext, [String: FrontmatterEditValue]) async throws -> NoteInfoContext = { context, _ in context }
        ) -> NoteInfoWindowController {
            let document = NoteDocument(relativePath: first.target.relativePath, rawContent: "---\nsummary: Original\n---\nBody")
            let context = NoteInfoContext(
                target: first.target, title: "Synthetic transfer Note", document: document,
                fileURL: root.appendingPathComponent(first.target.relativePath), canEdit: true,
                fileMetadata: .init(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil))
            return NoteInfoWindowController(
                context: context, reload: { _ in context }, apply: apply, attachPDF: { _ in }, openSource: { _ in })
        }

        func boundNoteInfoContext() throws -> NoteInfoContext {
            let file = root.appendingPathComponent("triptych/analyses/First.md")
            let source = try String(contentsOf: file, encoding: .utf8)
            return NoteInfoContext(
                target: first.target, title: "Synthetic Note", document: .init(relativePath: first.target.relativePath, rawContent: source),
                fileURL: file, canEdit: true, fileMetadata: .init(byteCount: source.utf8.count, creationDate: nil, modificationDate: nil))
        }

        func expectOriginalSelections() {
            #expect(source.documentController.selectedDocument == sourceDocument)
            #expect(destination.documentController.selectedDocument == destinationDocument)
            #expect(source.documentTabController.tabs.map(\.document) == [sourceDocument])
            #expect(destination.documentTabController.tabs.map(\.document) == [destinationDocument])
            #expect(source.documentController.session(for: sourceDocument.editingTarget) === sourceSession)
            #expect(destination.documentController.session(for: destinationDocument.editingTarget) === destinationSession)
        }

        func close() async {
            source.pdfReaderController.shutdown()
            destination.pdfReaderController.shutdown()
            sourceSession.cancelScheduledWork()
            destinationSession.cancelScheduledWork()
            source.windowWorkspaceController.cancelAll()
            destination.windowWorkspaceController.cancelAll()
            await operations.cancelPending()
            await store.shutdownApplicationRuntime()
            try? FileManager.default.removeItem(at: root)
        }

        private static func install(_ context: PDFReaderNoteContext, in model: WindowModel) throws -> WindowSelectedDocument {
            let target = context.target
            let path = try #require(context.authoredPath)
            let document = NoteDocument(
                relativePath: target.relativePath, rawContent: "---\nid: \(target.noteID.uuidString)\npdf: \(path)\n---\n\nSynthetic Note.\n")
            model.documentController.installOpenedDocument(
                WorkspaceNoteSnapshot(
                    id: .init(vaultID: target.vaultID, relativePath: target.relativePath), vaultRole: .sourceCorpus,
                    stableIdentity: .resolved(target.noteID), document: document,
                    fileMetadata: .init(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
                    graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0)), vaultName: "Fixture", vaultRole: .sourceCorpus)
            let selected = try #require(model.documentController.selectedDocument)
            model.documentTabController.activate(document: selected, title: target.relativePath, toolTip: target.relativePath, placement: .newTab)
            model.reconcileDocumentSessionLeases()
            return selected
        }

        private static func pdfSnapshot(_ filename: String, data: Data) throws -> PDFReaderSnapshot {
            let id = UUID()
            return PDFReaderSnapshot(
                record: PortableAttachmentRecord(
                    id: id, vaultID: nil, location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(id.uuidString.lowercased())/\(filename)"))
                ),
                data: data, revision: .init(fingerprint: DocumentFingerprint(data: data), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
        }

        private static func pdfData() throws -> Data {
            let data = NSMutableData()
            let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            context.beginPDFPage(nil)
            context.endPDFPage()
            context.closePDF()
            return data as Data
        }
    }
}
