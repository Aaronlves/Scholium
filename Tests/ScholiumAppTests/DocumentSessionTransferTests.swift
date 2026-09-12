import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Document session transfer")
struct DocumentSessionTransferTests {
    private func document(_ path: String) -> WindowSelectedDocument {
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        return .workspace(WindowDocumentDescriptor(sessionKey: key, reference: VaultNoteReference(
            vaultID: key.vaultID, vaultName: "Fixture", vaultRole: .topicKnowledge,
            relativePath: path, stableNoteID: key.noteID.uuidString
        )))
    }

    @Test("Switching retained tabs preserves dirty source, mode, and scroll without saving")
    func retainedTabSelection() throws {
        let controller = DocumentController()
        let first = document("First.md")
        let second = document("Second.md")
        controller.selectDocument(first)
        let session = controller.session(for: first.editingTarget)
        session.beginEditing(in: .source)
        session.originalEditingSource = "Saved"
        session.editingSource = "Unsaved draft"
        session.scrollFraction = 0.62
        session.editError = "Retained save failure"
        session.suppressAutosave = true
        controller.selectDocument(second)
        #expect(controller.selectRetainedDocument(first))
        #expect(controller.session(for: first.editingTarget) === session)
        #expect(controller.currentPresentationMode == .source)
        #expect(session.editingSource == "Unsaved draft")
        #expect(session.scrollFraction == 0.62)
        #expect(session.editError == "Retained save failure")
        #expect(session.hasUnsavedChanges)
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
        #expect(received.presentationMode == .source)
        #expect(received.windowPresentationSnapshot == presentation)
        #expect(destination.selectedDocument == note)
        #expect(source.retainedSessionCount == 0)
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
