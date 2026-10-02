import AppKit
import PDFKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Exclusive window side panes", .serialized)
@MainActor
struct WindowSidePaneCoordinatorTests {
    @Test("An admitted switch and active-pane close use only the three existing visibility states")
    func threeStatesAndPersistence() async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        try await fixture.load()
        let document = try #require(fixture.reader.document)
        fixture.reader.recordPaneWidth(620)
        fixture.model.sidePaneCoordinator.setInspectorVisible(true)
        try await settled(fixture)
        #expect(!fixture.reader.isVisible && fixture.model.researchInspectorVisible)
        #expect(fixture.reader.document === document && fixture.reader.paneWidth == 620)
        try await fixture.reader.flushPersistence()
        #expect(try await fixture.operations.windowState(windowID: fixture.model.nativeWindowID)?.isVisible == false)
        fixture.model.sidePaneCoordinator.setInspectorVisible(false)
        #expect(!fixture.reader.isVisible && !fixture.model.researchInspectorVisible)
        PDFReaderWindowCommand.toggle(in: fixture.model)
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible)
        #expect(fixture.reader.document === document && fixture.reader.paneWidth == 620)
        PDFReaderWindowCommand.toggle(in: fixture.model)
        try await settled(fixture)
        #expect(!fixture.reader.isVisible && !fixture.model.researchInspectorVisible)
    }

    @Test("Draft and final-import barriers leave the selected PDF and its work intact")
    func draftAndImportBarriers() async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        try await fixture.load()
        let document = try #require(fixture.reader.document)
        fixture.reader.requestComment(on: try #require(document.page(at: 0)), at: NSPoint(x: 40, y: 40))
        let draft = try #require(fixture.reader.annotationDraft)
        fixture.model.sidePaneCoordinator.setInspectorVisible(true)
        try await settled(fixture)
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible)
        #expect(fixture.reader.annotationDraft?.id == draft.id && fixture.reader.document === document)
        fixture.reader.cancelComment()
        await fixture.operations.holdNextImport()
        let importing = Task { @MainActor in
            try await fixture.reader.importPDF(at: URL(fileURLWithPath: "/synthetic/nonprivate.pdf"))
        }
        try await eventually { await fixture.operations.hasHeldImport }
        fixture.model.sidePaneCoordinator.setInspectorVisible(true)
        try await settled(fixture)
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible && fixture.reader.isImporting)
        await fixture.operations.cancelImport()
        await #expect(throws: CancellationError.self) { try await importing.value }
        #expect(fixture.reader.document === document)
    }

    @Test("A held save freezes input and admits only the latest side-pane request")
    func latestIntentAfterSave() async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        try await fixture.load()
        await fixture.operations.holdNextSave()
        try fixture.addComment("Saved before the latest pane choice")
        try await eventually { await fixture.operations.hasHeldSave }
        fixture.model.sidePaneCoordinator.setInspectorVisible(true)
        #expect(fixture.reader.isDeparting && fixture.model.sidePaneCoordinator.isTransitioning)
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible && !fixture.reader.canAnnotate)
        #expect(throws: (any Error).self) { try fixture.model.requestNoteInfoPDFAttachment() }
        #expect(!fixture.reader.attachRequested)
        fixture.model.sidePaneCoordinator.request(.none)
        fixture.model.sidePaneCoordinator.request(.pdf)
        await fixture.operations.releaseSave()
        try await settled(fixture)
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible && !fixture.reader.isDeparting)
        #expect(!fixture.reader.hasUnsavedAnnotations)
        let saved = try #require(await fixture.operations.savedPDF(for: fixture.context.target.noteID))
        #expect(PDFDocument(data: saved.data)?.page(at: 0)?.annotations.first?.contents == "Saved before the latest pane choice")
        try fixture.model.requestNoteInfoPDFAttachment()
        #expect(fixture.reader.attachRequested)
    }

    @Test("A newer native Focus Layout intent survives an older held-save Inspector request", arguments: [false, true])
    func focusLayoutCancelsPendingIntent(fullScreen: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        try await fixture.load()
        let native = WorkspaceWindowCoordinator(
            windowID: fixture.model.nativeWindowID, appState: fixture.model,
            lifecycleRegistry: ScholiumWindowLifecycleRegistry())
        let split = SidePaneTestSplitController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640),
            styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        native.attach(to: window)
        native.attach(splitController: split)
        defer {
            native.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
            window.toolbar = nil
            window.close()
        }
        await fixture.operations.holdNextSave()
        try fixture.addComment("Save continues through the newer Focus Layout choice")
        try await eventually { await fixture.operations.hasHeldSave }
        native.actions.setResearchInspectorVisible(true)
        #expect(fixture.model.sidePaneCoordinator.isTransitioning && fixture.reader.isDeparting)
        if fullScreen {
            native.windowWillEnterFullScreen(Notification(name: NSWindow.willEnterFullScreenNotification, object: window))
        } else {
            #expect(native.actions.canToggleFocusLayout())
            native.actions.toggleFocusLayout()
        }
        #expect(fixture.model.shellState.isFocusLayoutActive)
        #expect(fixture.model.shellState.isFocusLayoutLockedByFullScreen == fullScreen)
        #expect(!fixture.model.sidePaneCoordinator.isTransitioning && !fixture.reader.isDeparting)
        #expect(fixture.reader.isSaving && fixture.reader.hasUnsavedAnnotations)
        #expect(throws: (any Error).self) { try fixture.model.requestNoteInfoPDFAttachment() }
        #expect(!fixture.reader.attachRequested)
        await fixture.operations.releaseSave()
        try await eventually { !fixture.reader.isSaving && !fixture.reader.hasUnsavedAnnotations }
        await Task.yield()
        #expect(fixture.model.shellState.isFocusLayoutActive && window.toolbar?.isVisible == false)
        #expect(fixture.reader.isVisible && !split.researchInspectorIsVisible)
        #expect(!PDFReaderWindowCommand.isVisible(in: fixture.model))
        let saved = try #require(await fixture.operations.savedPDF(for: fixture.context.target.noteID))
        #expect(PDFDocument(data: saved.data)?.page(at: 0)?.annotations.first?.contents == "Save continues through the newer Focus Layout choice")
    }

    @Test("A failed save keeps the prior pane and recoverable annotation candidate")
    func failedSaveDoesNotSwitch() async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        try await fixture.load()
        await fixture.operations.failNextSave(with: .changed)
        try fixture.addComment("Retained local candidate")
        try await eventually { !fixture.reader.isSaving && fixture.reader.hasUnsavedAnnotations }
        fixture.model.sidePaneCoordinator.setInspectorVisible(true)
        try await settled(fixture)
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible && !fixture.reader.isDeparting)
        #expect(fixture.reader.document?.page(at: 0)?.annotations.first?.contents == "Retained local candidate")
        #expect(await fixture.operations.savedPDF(for: fixture.context.target.noteID)?.data == fixture.originalPDF)
    }

    @Test("Context departure cancels a held pane intent without releasing another owner's token")
    func contextCancellationAndNestedDeparture() async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        try await fixture.load()
        await fixture.operations.holdNextSave()
        try fixture.addComment("Preserved across a cancelled pane request")
        try await eventually { await fixture.operations.hasHeldSave }
        fixture.model.sidePaneCoordinator.setInspectorVisible(true)
        let externalDeparture = fixture.reader.beginDeparture()
        fixture.model.sidePaneCoordinator.documentContextWillChange(to: nil)
        #expect(!fixture.model.sidePaneCoordinator.isTransitioning && fixture.reader.isDeparting)
        await fixture.operations.releaseSave()
        await Task.yield()
        await Task.yield()
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible && fixture.reader.isDeparting)
        fixture.reader.endDeparture(externalDeparture)
        #expect(!fixture.reader.isDeparting)
    }

    @Test("Queued cancellation performs no delayed pane change, and raw restoration preserves a draft")
    func queuedCancellationAndRawRestoration() async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        try await fixture.load()
        fixture.model.sidePaneCoordinator.setInspectorVisible(true)
        fixture.model.sidePaneCoordinator.cancelPending()
        await Task.yield()
        await Task.yield()
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible && !fixture.reader.isDeparting)
        fixture.reader.requestComment(on: try #require(fixture.reader.document?.page(at: 0)), at: NSPoint(x: 40, y: 40))
        let draft = try #require(fixture.reader.annotationDraft)
        // Native Focus Layout can restore its captured Inspector visibility.
        fixture.model.recordResearchInspectorVisibility(true)
        fixture.model.sidePaneCoordinator.reconcileVisibility()
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible)
        #expect(fixture.reader.annotationDraft?.id == draft.id)
    }

    @Test("Both-open restoration prefers PDF, and a chosen PDF resists late Inspector visibility restoration")
    func restorationNormalization() async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        await fixture.operations.seedWindow(.init(isVisible: true, paneWidth: 500), windowID: fixture.model.nativeWindowID)
        fixture.model.shellState.restoreInspector(modesByWorkspace: [:], isVisible: true)
        fixture.reader.follow(fixture.context, operations: fixture.operations)
        try await eventually { fixture.reader.isVisible && !fixture.reader.isLoading && !fixture.model.researchInspectorVisible }
        #expect(fixture.model.sidePaneCoordinator.pane == .pdf)
        try await fixture.reader.flushPersistence()
        #expect(try await fixture.operations.windowState(windowID: fixture.model.nativeWindowID)?.isVisible == true)

        let chosen = try Fixture()
        defer { chosen.shutdown() }
        try await chosen.load()
        chosen.model.sidePaneCoordinator.request(.pdf)
        chosen.model.shellState.restoreInspector(modesByWorkspace: [.paperAnalysis: "related"], isVisible: true)
        #expect(chosen.reader.isVisible && !chosen.model.researchInspectorVisible)
        #expect(chosen.model.shellState.inspectorMode(for: .paperAnalysis) == .related)
    }

    @Test("Final teardown rejects queued commands and late restoration notifications")
    func finalTeardown() async throws {
        let fixture = try Fixture()
        defer { fixture.shutdown() }
        try await fixture.load()
        fixture.model.sidePaneCoordinator.setInspectorVisible(true)
        fixture.model.sidePaneCoordinator.shutdown()
        fixture.model.sidePaneCoordinator.request(.none)
        await Task.yield()
        #expect(fixture.reader.isVisible && !fixture.model.researchInspectorVisible && !fixture.reader.isDeparting)
    }

    private func settled(_ fixture: Fixture) async throws {
        try await eventually { !fixture.model.sidePaneCoordinator.isTransitioning }
    }

    private func eventually(_ condition: @escaping @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        try #require(await condition(), "The controlled side-pane transition did not settle.")
    }

    @MainActor
    private final class Fixture {
        let model: WindowModel
        let reader: PDFReaderController
        let context: PDFReaderNoteContext
        let operations: ControlledPDFReaderOperations
        let originalPDF: Data

        init() throws {
            context = PDFReaderNoteContext(
                triptychID: UUID(), target: .init(noteID: UUID(), vaultID: UUID(), relativePath: "Synthetic.md"), authoredPath: "../synthetic.pdf")
            let data = NSMutableData()
            let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            let canvas = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            for _ in 0..<2 {
                canvas.beginPDFPage(nil)
                canvas.endPDFPage()
            }
            canvas.closePDF()
            originalPDF = data as Data
            let record = PortableAttachmentRecord(
                id: UUID(), vaultID: context.target.vaultID, location: .vaultRelative(try AttachmentRelativePath("synthetic.pdf")))
            operations = ControlledPDFReaderOperations(notes: [
                context.target.noteID: .init(
                    record: record, data: originalPDF,
                    revision: .init(fingerprint: DocumentFingerprint(data: originalPDF), device: 1, inode: 1, parentDevice: 1, parentInode: 1))
            ])
            model = WindowModel(workspaceStore: makeTestWorkspaceStore())
            reader = PDFReaderController(windowID: model.nativeWindowID, setBinding: { _, _, _ in }, reportIssue: { _ in nil })
            model.pdfReaderController = reader
            let document = NoteDocument(
                relativePath: context.target.relativePath, rawContent: "---\nid: \(context.target.noteID)\npdf: ../synthetic.pdf\n---\n\nSynthetic Note.\n")
            model.documentController.installOpenedDocument(
                WorkspaceNoteSnapshot(
                    id: .init(vaultID: context.target.vaultID, relativePath: context.target.relativePath), vaultRole: .sourceCorpus,
                    stableIdentity: .resolved(context.target.noteID), document: document,
                    fileMetadata: .init(byteCount: document.sourceBytes.count, creationDate: nil, modificationDate: nil),
                    graphCounts: .init(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0)), vaultName: "Fixture", vaultRole: .sourceCorpus)
            _ = model.sidePaneCoordinator
        }

        func load() async throws {
            reader.setVisible(true)
            reader.follow(context, operations: operations)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while reader.document == nil || reader.isLoading, ContinuousClock.now < deadline { await Task.yield() }
            try #require(reader.document != nil && !reader.isLoading)
        }

        func addComment(_ text: String) throws {
            reader.requestComment(on: try #require(reader.document?.page(at: 0)), at: NSPoint(x: 40, y: 40))
            reader.commitComment(try #require(reader.annotationDraft), text: text)
        }

        func shutdown() {
            model.sidePaneCoordinator.shutdown()
            reader.shutdown()
            model.windowWorkspaceController.cancelAll()
            Task { await operations.cancelPending() }
        }
    }
}

@MainActor
private final class SidePaneTestSplitController: NSSplitViewController, ScholiumWorkspaceSplitControlling {
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        addSplitViewItem(NSSplitViewItem(sidebarWithViewController: NSViewController()))
        addSplitViewItem(NSSplitViewItem(viewController: NSViewController()))
        let inspector = NSSplitViewItem(inspectorWithViewController: NSViewController())
        inspector.isCollapsed = true
        addSplitViewItem(inspector)
    }

    convenience init() { self.init(nibName: nil, bundle: nil) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidePaneTestSplitController is code-only") }

    var nativeSplitViewController: NSSplitViewController { self }
    var libraryIsVisible: Bool { !splitViewItems[0].isCollapsed }
    var researchInspectorIsVisible: Bool { !splitViewItems[2].isCollapsed }
    func setLibraryVisible(_ visible: Bool, animated: Bool) { splitViewItems[0].isCollapsed = !visible }
    func setResearchInspectorVisible(_ visible: Bool, animated: Bool) { splitViewItems[2].isCollapsed = !visible }
}
