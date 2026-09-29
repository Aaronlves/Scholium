import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Window editor command port", .serialized)
struct WindowEditorCommandPortTests {
    @Test("A newer Note view owns the selected command port")
    func staleRegistrationAndRemovalCannotReplaceCurrentPort() throws {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let note = document("A.md")
        window.documentController.selectDocument(note)
        let session = window.documentController.session(for: note.editingTarget)
        let oldPort = ScholiumEditorCommandPort()
        let newPort = ScholiumEditorCommandPort()
        var oldExecutions = 0
        var newExecutions = 0
        window.registerEditorActions(
            port: oldPort, target: note.editingTarget, session: session,
            actions: actions("old") { oldExecutions += 1 }, change: .activation
        )
        let capturedOldAction = try #require(window.currentEditorActions)
        window.registerEditorActions(
            port: newPort, target: note.editingTarget, session: session,
            actions: actions("new") { newExecutions += 1 }, change: .activation
        )
        window.registerEditorActions(
            port: oldPort, target: note.editingTarget, session: session,
            actions: actions("old refresh") { oldExecutions += 1 }, change: .refresh
        )
        window.unregisterEditorActions(token: oldPort.token)
        #expect(window.currentEditorActions?.documentID == "new")
        capturedOldAction.perform(.bold)
        #expect(oldExecutions == 0)
        window.currentEditorActions?.perform(.bold)
        #expect(newExecutions == 1)

        let other = document("B.md")
        window.documentController.selectDocument(other)
        #expect(window.currentEditorActions == nil)
        window.unregisterEditorActions(token: newPort.token)
        #expect(newPort.actions == nil)
    }

    @Test("A transferred session only accepts commands from its new window")
    func commandPortFollowsExactSessionOwner() throws {
        let store = makeTestWorkspaceStore()
        let source = WindowModel(workspaceStore: store)
        let destination = WindowModel(workspaceStore: store)
        let note = document("Transfer.md")
        source.documentController.selectDocument(note)
        let session = source.documentController.session(for: note.editingTarget)
        let sourcePort = ScholiumEditorCommandPort()
        var sourceExecutions = 0
        var destinationExecutions = 0
        source.registerEditorActions(
            port: sourcePort, target: note.editingTarget, session: session,
            actions: actions("source") { sourceExecutions += 1 }, change: .activation
        )
        let capturedSourceAction = try #require(source.currentEditorActions)
        let transfer = try #require(source.documentController.takeSessionForTransfer(note))
        destination.documentController.receiveSessionTransfer(transfer)
        let destinationPort = ScholiumEditorCommandPort()
        destination.registerEditorActions(
            port: destinationPort, target: note.editingTarget, session: session,
            actions: actions("destination") { destinationExecutions += 1 }, change: .activation
        )
        capturedSourceAction.perform(.bold)
        #expect(sourceExecutions == 0)
        #expect(source.currentEditorActions == nil)
        destination.currentEditorActions?.perform(.bold)
        #expect(destinationExecutions == 1)
        source.unregisterEditorActions(token: sourcePort.token)
        #expect(destination.currentEditorActions?.documentID == "destination")
    }

    @Test("A window releases callbacks on close and never retains their view port")
    func closingReleasesWeakCommandPort() {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let note = document("Closing.md")
        window.documentController.selectDocument(note)
        let session = window.documentController.session(for: note.editingTarget)
        weak var weakPort: ScholiumEditorCommandPort?
        do {
            let port = ScholiumEditorCommandPort()
            weakPort = port
            window.registerEditorActions(
                port: port, target: note.editingTarget, session: session,
                actions: actions("closing") {}, change: .activation
            )
            window.clearEditorActions()
            #expect(port.actions == nil)
        }
        #expect(weakPort == nil)
        #expect(window.currentEditorActions == nil)
    }

    private func document(_ path: String) -> WindowSelectedDocument {
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        return .workspace(
            WindowDocumentDescriptor(
                sessionKey: key,
                reference: VaultNoteReference(
                    vaultID: key.vaultID, vaultName: "Fixture", vaultRole: .topicKnowledge,
                    relativePath: path, stableNoteID: key.noteID.uuidString
                )
            )
        )
    }

    private func actions(_ documentID: String, perform: @escaping () -> Void) -> ScholiumFocusedEditorActions {
        ScholiumFocusedEditorActions(
            documentID: documentID,
            isComposing: false,
            isAvailable: { _ in true },
            perform: { _ in perform() },
            performWithArgument: { _, _ in },
            importImage: {},
            indexImage: {},
            canAttachDocument: false,
            attachDocumentCopy: {},
            referenceOriginalDocument: {}
        )
    }
}
