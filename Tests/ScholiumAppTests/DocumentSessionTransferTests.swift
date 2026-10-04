import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Document session transfer")
struct DocumentSessionTransferTests {
    private func document(_ path: String, role: VaultRole = .topicKnowledge) -> WindowSelectedDocument {
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        return .workspace(
            WindowDocumentDescriptor(
                sessionKey: key,
                reference: VaultNoteReference(
                    vaultID: key.vaultID, vaultName: "Fixture", vaultRole: role,
                    relativePath: path, stableNoteID: key.noteID.uuidString
                )))
    }

    private func snapshot(for selection: WindowSelectedDocument, source: String) -> WorkspaceNoteSnapshot {
        guard case .workspace(let descriptor) = selection else {
            preconditionFailure("The fixture must select a workspace Note")
        }
        let document = NoteDocument(relativePath: descriptor.reference.relativePath, rawContent: source)
        return WorkspaceNoteSnapshot(
            id: VaultQualifiedNoteID(
                vaultID: descriptor.sessionKey.vaultID,
                relativePath: descriptor.reference.relativePath),
            vaultRole: descriptor.reference.vaultRole,
            stableIdentity: .resolved(descriptor.sessionKey.noteID),
            document: document,
            fileMetadata: WorkspaceFileMetadata(
                byteCount: document.sourceBytes.count,
                creationDate: nil,
                modificationDate: nil),
            graphCounts: WorkspaceGraphCounts(incoming: 0, outgoing: 0, broken: 0, ambiguous: 0)
        )
    }

    @Test("Retained tabs across roles apply the window mode and preserve draft context", arguments: [NotePresentationMode.livePreview, .source, .read])
    func retainedTabSelection(mode: NotePresentationMode) throws {
        let controller = DocumentController()
        let first = document("First.md")
        let second = document("Second.md", role: .sourceCorpus)
        let initialMode: MarkdownEditorMode = mode == .source ? .livePreview : .source
        controller.installOpenedDocument(
            snapshot(for: first, source: "Saved"), vaultName: "Fixture", vaultRole: .topicKnowledge)
        let session = controller.session(for: first.editingTarget)
        session.beginEditing(in: initialMode)
        controller.rememberPresentationMode(initialMode.presentationMode)
        session.originalEditingSource = "Saved"
        session.editingSource = "\u{FEFF}Unsaved 中文 😀 e\u{301} draft\r\n"
        session.scrollFraction = 0.62
        session.editError = "Retained save failure"
        session.suppressAutosave = true
        session.editorSession.loadDocument(session.editingSource, documentID: "First.md", mode: initialMode)
        session.editorSession.updateInteraction(
            selections: [.init(anchor: 8, head: 13)], line: 1, column: 9, lineCount: 2,
            documentVersion: 0, focusTarget: .editor, context: nil
        )
        let presentation = session.windowPresentationSnapshot
        controller.installOpenedDocument(
            snapshot(for: second, source: "Other"), vaultName: "Fixture", vaultRole: .sourceCorpus)
        let secondSession = controller.session(for: second.editingTarget)
        secondSession.preparePresentationMode(mode)
        controller.rememberPresentationMode(mode)
        #expect(controller.selectRetainedDocument(first))
        #expect(controller.selectRetainedDocument(first))
        #expect(controller.session(for: first.editingTarget) === session)
        #expect(controller.currentPresentationMode == mode)
        #expect(session.activeEditorMode == (mode.editorMode ?? initialMode))
        #expect(controller.chromeProjection.mode == (mode == .read ? initialMode.presentationMode : mode))
        #expect(session.editingSource == "\u{FEFF}Unsaved 中文 😀 e\u{301} draft\r\n")
        #expect(session.scrollFraction == 0.62)
        #expect(session.windowPresentationSnapshot == presentation)
        #expect(session.editError == "Retained save failure")
        #expect(session.hasUnsavedChanges)
    }

    @Test("A clean retained editor adopts the window Review choice without losing its position")
    func retainedCleanReview() throws {
        let controller = DocumentController()
        let first = document("First.md")
        let second = document("Second.md", role: .draftProject)
        controller.installOpenedDocument(
            snapshot(for: first, source: "Saved"), vaultName: "Fixture", vaultRole: .topicKnowledge)
        let session = controller.session(for: first.editingTarget)
        session.beginEditing(in: .source)
        session.originalEditingSource = "Saved"
        session.editingSource = "Saved"
        session.scrollFraction = 0.62
        controller.installOpenedDocument(
            snapshot(for: second, source: "Other"), vaultName: "Fixture", vaultRole: .draftProject)
        controller.rememberPresentationMode(.read)
        #expect(controller.selectRetainedDocument(first))
        #expect(controller.currentPresentationMode == .read)
        #expect(session.presentationMode == .read)
        #expect(controller.chromeProjection.mode == .read)
        #expect(session.scrollFraction == 0.62)
        #expect(session.editingSource == "Saved")
        #expect(!session.hasUnsavedChanges)
    }

    @Test("Reordering tabs preserves the selected identity and closing-neighbor policy")
    func reorderTabIdentity() throws {
        let controller = DocumentTabController()
        for path in ["A.md", "B.md", "C.md"] {
            controller.activate(document: document(path), title: path, toolTip: path, placement: .newTab)
        }
        let original = controller.tabs
        controller.moveTab(withID: original[2].id, to: 0)
        #expect(controller.tabs.map(\.id) == [original[2].id, original[0].id, original[1].id])
        #expect(controller.selectedTabID == original[2].id)
        #expect(controller.closePlan(forTabWithID: original[2].id)?.selectedTabIDAfterClose == original[0].id)
    }

    @Test("Moving a dirty session retains identity, exact bytes, selection, scroll, and save failure")
    func preservesSession() async throws {
        let source = DocumentController()
        let destination = DocumentController()
        let note = document("A.md")
        source.selectDocument(note)
        let original = source.session(for: note.editingTarget)
        original.beginEditing(in: .source)
        source.rememberPresentationMode(.source)
        original.originalEditingSource = "\u{FEFF}# A\r\n"
        original.editingSource = "\u{FEFF}# A\r\n\r\n论点 🦉 e\u{301}"
        original.editError = "Fixture save failure"
        original.canRetrySave = true
        original.scrollFraction = 0.61
        original.editorSession.loadDocument(original.editingSource, documentID: "A.md", mode: .source)
        original.editorSession.updateInteraction(
            selections: [.init(anchor: 9, head: 12)], line: 3, column: 2, lineCount: 3,
            documentVersion: 0, focusTarget: .editor, context: nil
        )
        let presentation = original.windowPresentationSnapshot
        try await source.prepareSessionTransfer(note)
        let transfer = try #require(source.takeSessionForTransfer(note))
        #expect(transfer.mode == .source)
        #expect(source.selectedDocument == nil)
        #expect(source.retainedSessionCount == 0)
        destination.receiveSessionTransfer(transfer)
        destination.reconcileSessionLeases(leasedDocuments: [note], selectedDocument: note)
        let received = destination.session(for: note.editingTarget)
        #expect(received === original)
        #expect(received.editingSource == "\u{FEFF}# A\r\n\r\n论点 🦉 e\u{301}")
        #expect(received.originalEditingSource == "\u{FEFF}# A\r\n")
        #expect(received.editError == "Fixture save failure")
        #expect(received.canRetrySave)
        #expect(received.presentationMode == .livePreview)
        #expect(destination.currentPresentationMode == .livePreview)
        #expect(received.windowPresentationSnapshot == presentation)
        #expect(destination.selectedDocument == note)
        #expect(source.retainedSessionCount == 0)
    }

    @Test("A new detached window inherits the originating window mode while main return keeps its own choice")
    func transferModeIsWindowOwned() throws {
        let store = makeTestWorkspaceStore()
        let main = WindowModel(workspaceStore: store)
        let detached = WindowModel(workspaceStore: store)
        detached.isDetachedDocumentWindow = true
        let note = document("Transferred.md")
        main.documentController.installOpenedDocument(
            snapshot(for: note, source: "Saved"), vaultName: "Fixture", vaultRole: .topicKnowledge)
        let session = main.documentController.session(for: note.editingTarget)
        session.beginEditing(in: .source)
        main.documentController.rememberPresentationMode(.source)
        main.documentTabController.activate(document: note, title: "Transferred", toolTip: "Transferred", placement: .newTab)
        let tab = try #require(main.documentTabController.selectedTab)
        let outgoing = try #require(main.documentController.takeSessionForTransfer(note))
        main.documentTabController.removeAll()
        detached.finishIncomingTransfer(outgoing, tab: tab)
        #expect(detached.currentPresentationMode == .source)
        #expect(detached.documentController.session(for: note.editingTarget) === session)
        main.documentController.rememberPresentationMode(.livePreview)
        #expect(detached.currentPresentationMode == .source)
        let returning = try #require(detached.documentController.takeSessionForTransfer(note))
        main.finishIncomingTransfer(returning, tab: tab)
        #expect(main.currentPresentationMode == .livePreview)
        #expect(session.activeEditorMode == .livePreview)
        #expect(main.documentController.session(for: note.editingTarget) === session)
        #expect(detached.currentPresentationMode == .source)
    }

    @Test(
        "An in-flight save failure keeps the source session while a successful save permits transfer",
        arguments: [true, false])
    func inFlightSaveControlsTransfer(fails: Bool) async throws {
        let source = DocumentController()
        let destination = DocumentController()
        let note = document("Saving.md")
        source.selectDocument(note)
        let original = source.session(for: note.editingTarget)
        original.beginEditing(in: .source)
        original.originalEditingSource = "\u{FEFF}# Saving\r\n"
        let exactSource = "\u{FEFF}# Saving\r\n\r\n论点 🦉 e\u{301}"
        original.editingSource = exactSource
        original.editorSession.loadDocument(exactSource, documentID: "Saving.md", mode: .source)
        original.editorSession.updateInteraction(
            selections: [.init(anchor: 9, head: 12)], line: 3, column: 2, lineCount: 3,
            documentVersion: 0, focusTarget: .editor, context: nil
        )
        original.scrollFraction = 0.61
        original.suppressAutosave = true
        let presentation = original.windowPresentationSnapshot
        let failureDetail = "Fixture in-flight write failed"
        original.isSavingEdit = true
        // The existing save-task slot supplies the suspension boundary. Its
        // completion clears saving state as finishSaveAttempt does, so a
        // discarded error cannot be hidden by a later saving-state timeout.
        let save = Task<EditorSaveOutcome, Error> { @MainActor in
            defer {
                original.activeSaveTask = nil
                original.isSavingEdit = false
            }
            if fails {
                original.editError = failureDetail
                original.canRetrySave = true
                throw VaultRepositoryError.writeFailed(failureDetail)
            }
            original.originalEditingSource = exactSource
            return .clean
        }
        original.activeSaveTask = save
        defer {
            save.cancel()
            original.cancelScheduledWork()
        }

        if fails {
            do {
                try await source.prepareSessionTransfer(note)
                Issue.record("A failed in-flight save must stop transfer preparation")
            } catch VaultRepositoryError.writeFailed(let detail) {
                #expect(detail == failureDetail)
            } catch {
                Issue.record("Expected the original write failure, received \(error)")
            }
            #expect(source.selectedDocument == note)
            #expect(source.retainedSessionCount == 1)
            #expect(destination.retainedSessionCount == 0)
            #expect(source.session(for: note.editingTarget) === original)
            #expect(original.editError == failureDetail)
            #expect(original.canRetrySave)
            #expect(original.hasUnsavedChanges)
            #expect(Data(original.originalEditingSource.utf8) == Data("\u{FEFF}# Saving\r\n".utf8))
        } else {
            try await source.prepareSessionTransfer(note)
            let transfer = try #require(source.takeSessionForTransfer(note))
            destination.receiveSessionTransfer(transfer)
            #expect(source.selectedDocument == nil)
            #expect(source.retainedSessionCount == 0)
            #expect(destination.selectedDocument == note)
            #expect(destination.session(for: note.editingTarget) === original)
            #expect(!original.hasUnsavedChanges)
        }
        #expect(original.activeSaveTask == nil)
        #expect(!original.isSavingEdit)
        #expect(Data(original.retainedExactSource.utf8) == Data(exactSource.utf8))
        #expect(original.windowPresentationSnapshot == presentation)
    }

    @Test("Late source-view cleanup cannot dismiss Find in the destination")
    func transferredFindPresentationOwnership() throws {
        let source = DocumentController()
        let destination = DocumentController()
        let note = document("Transferred.md")
        source.selectDocument(note)
        let session = source.session(for: note.editingTarget)
        let openingID = session.editorSession.openingPresentationID
        session.findPresentation.present()
        let transfer = try #require(source.takeSessionForTransfer(note))
        destination.receiveSessionTransfer(transfer)
        #expect(destination.session(for: note.editingTarget) === session)

        // The old host disappears after the same session has moved and Find
        // has been shown in its new window.
        source.dismissFindForDisappearingPresentation(
            target: note.editingTarget, session: session, openingPresentationID: openingID)
        #expect(session.findPresentation.isPresented)

        // An ordinary retained-tab disappearance still closes its own panel.
        destination.dismissFindForDisappearingPresentation(
            target: note.editingTarget, session: session, openingPresentationID: openingID)
        #expect(!session.findPresentation.isPresented)
    }

    @Test("Find commands follow the selected retained session across a window transfer")
    func selectedFindOwnerTransfers() throws {
        let source = DocumentController()
        let destination = DocumentController()
        let note = document("Find.md")
        source.selectDocument(note)
        let session = source.session(for: note.editingTarget)
        #expect(source.canFindSelectedDocument)
        #expect(!source.canReplaceInSelectedDocument)
        source.performSelectedDocumentFind(.present)
        #expect(session.findPresentation.isPresented)
        source.performSelectedDocumentFind(.next)
        #expect(session.findPresentation.request?.operation == .execute(.next))

        let transfer = try #require(source.takeSessionForTransfer(note))
        session.findPresentation.dismiss()
        source.performSelectedDocumentFind(.present)
        #expect(!source.canFindSelectedDocument)
        #expect(!session.findPresentation.isPresented)
        destination.receiveSessionTransfer(transfer)
        #expect(destination.session(for: note.editingTarget) === session)
        destination.performSelectedDocumentFind(.present)
        #expect(session.findPresentation.isPresented)
        session.beginEditing(in: .source)
        #expect(destination.canReplaceInSelectedDocument)
        destination.presentReplacementFindForSelectedDocument()
        #expect(session.findPresentation.replacementIsPresented)
    }

    @Test("A stale selection result cannot change another tab or a newer source")
    func staleFindSelectionIsRejected() {
        let controller = DocumentController()
        let first = document("First Find.md")
        let second = document("Second Find.md")
        controller.selectDocument(first)
        let firstSession = controller.session(for: first.editingTarget)
        let firstOpeningID = firstSession.editorSession.openingPresentationID
        controller.selectDocument(second)
        let secondSession = controller.session(for: second.editingTarget)

        controller.acceptFindSelection(
            "stale", target: first.editingTarget, session: firstSession,
            openingPresentationID: firstOpeningID, expectedSource: nil
        )
        #expect(firstSession.findPresentation.query.isEmpty)
        #expect(secondSession.findPresentation.query.isEmpty)
        controller.performSelectedDocumentFind(
            .present, expectedTarget: first.editingTarget, expectedSession: firstSession
        )
        #expect(!secondSession.findPresentation.isPresented)

        secondSession.beginEditing(in: .source)
        secondSession.editingSource = "Current source"
        controller.acceptFindSelection(
            "stale", target: second.editingTarget, session: secondSession,
            openingPresentationID: secondSession.editorSession.openingPresentationID,
            expectedSource: "Earlier source"
        )
        #expect(secondSession.findPresentation.query.isEmpty)
        controller.acceptFindSelection(
            "stale", target: second.editingTarget, session: secondSession,
            openingPresentationID: UUID(), expectedSource: "Current source"
        )
        #expect(secondSession.findPresentation.query.isEmpty)
        secondSession.finishEditing()
        controller.acceptFindSelection(
            "stale edit", target: second.editingTarget, session: secondSession,
            openingPresentationID: secondSession.editorSession.openingPresentationID,
            expectedSource: "Current source"
        )
        #expect(secondSession.findPresentation.query.isEmpty)
        secondSession.beginEditing(in: .source)
        controller.acceptFindSelection(
            "current", target: second.editingTarget, session: secondSession,
            openingPresentationID: secondSession.editorSession.openingPresentationID,
            expectedSource: "Current source"
        )
        #expect(secondSession.findPresentation.query == "current")
    }

    @Test("Unavailable Review keeps Find in its selected session")
    func unavailableReviewFind() {
        let controller = DocumentController()
        let note = WindowSelectedDocument.unavailable(vaultID: UUID(), relativePath: "Unavailable.md")
        controller.selectDocument(note)
        let session = controller.session(for: note.editingTarget)
        #expect(controller.canFindSelectedDocument)
        controller.performSelectedDocumentFind(.present)
        #expect(session.findPresentation.isPresented)
    }

    @Test("Restoring a background transfer leaves the active document selected")
    func backgroundRollback() throws {
        let controller = DocumentController()
        let background = document("Background.md")
        let active = document("Active.md")
        controller.selectDocument(background)
        let session = controller.session(for: background.editingTarget)
        session.editingSource = "recover me"
        controller.selectDocument(active)
        let transfer = try #require(controller.takeSessionForTransfer(background))
        controller.receiveSessionTransfer(transfer, selecting: false)
        #expect(controller.selectedDocument == active)
        #expect(controller.session(for: background.editingTarget) === session)
        #expect(session.editingSource == "recover me")
    }

    @Test("Transferring a tab retains its identity and closes no destination neighbor")
    func tabMembershipTransfer() throws {
        let source = DocumentTabController()
        let destination = DocumentTabController()
        let note = document("A.md")
        let neighbor = document("B.md")
        source.activate(document: note, title: "A", toolTip: "A", placement: .newTab)
        destination.activate(document: neighbor, title: "B", toolTip: "B", placement: .newTab)
        let tab = try #require(source.selectedTab)
        source.removeTabs(withIDs: [tab.id])
        destination.insertTransferredTab(tab)
        #expect(source.tabs.isEmpty)
        #expect(destination.tabs.map(\.document) == [neighbor, note])
        #expect(destination.selectedTabID == tab.id)
    }
}
