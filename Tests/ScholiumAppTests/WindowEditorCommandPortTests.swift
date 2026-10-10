import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Window editor command port", .serialized)
struct WindowEditorCommandPortTests {
    @Test("Mounted mode requests run synchronously; an unmounted destination keeps its intent")
    func modeRequestUsesCurrentMountedPort() throws {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let note = document("Active.md")
        window.documentController.selectDocument(note)
        let session = window.documentController.session(for: note.editingTarget)
        let port = ScholiumEditorCommandPort()
        var requestedModes: [NotePresentationMode] = []
        window.registerEditorActions(
            port: port, target: note.editingTarget, session: session,
            actions: actions("active", selectMode: { requestedModes.append($0) }) {}, change: .activation
        )
        #expect(!session.isEditing)
        window.requestPresentationMode = .source

        window.requestDocumentMode(.read)

        #expect(requestedModes == [.read])
        #expect(window.requestPresentationMode == nil)

        window.documentController.selectDocument(document("Next.md"))
        window.requestDocumentMode(.read)
        #expect(requestedModes == [.read])
        #expect(window.requestPresentationMode == .read)
    }

    @Test("Selection inquiry commands use the current window token and revoke stale callbacks")
    func selectionInquiryPort() throws {
        let window = WindowModel(workspaceStore: makeTestWorkspaceStore())
        let note = document("A.md")
        window.documentController.selectDocument(note)
        let session = window.documentController.session(for: note.editingTarget)
        let port = ScholiumEditorCommandPort()
        var invoked: [AgentChatSelectionInquiry] = []
        var availability = false
        var registered = actions("selection", selectMode: { _ in }) {}
        registered.canInvokeSelectionInquiry = { _ in availability }
        registered.invokeSelectionInquiry = { invoked.append($0) }
        window.registerEditorActions(
            port: port, target: note.editingTarget, session: session,
            actions: registered, change: .activation)
        let captured = try #require(window.currentEditorActions)
        #expect(!captured.canInvokeSelectionInquiry(.explain))
        availability = true
        #expect(captured.canInvokeSelectionInquiry(.explain))
        captured.invokeSelectionInquiry(.explain)
        #expect(invoked == [.explain])
        window.documentController.selectDocument(document("B.md"))
        #expect(!captured.canInvokeSelectionInquiry(.polish))
        captured.invokeSelectionInquiry(.polish)
        #expect(invoked == [.explain])
    }

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
            actions: actions("old", selectMode: { _ in oldExecutions += 1 }) { oldExecutions += 1 }, change: .activation
        )
        let capturedOldAction = try #require(window.currentEditorActions)
        window.registerEditorActions(
            port: newPort, target: note.editingTarget, session: session,
            actions: actions("new", selectMode: { _ in newExecutions += 1 }) { newExecutions += 1 }, change: .activation
        )
        window.registerEditorActions(
            port: oldPort, target: note.editingTarget, session: session,
            actions: actions("old refresh", selectMode: { _ in oldExecutions += 1 }) { oldExecutions += 1 }, change: .refresh
        )
        window.unregisterEditorActions(token: oldPort.token)
        #expect(window.currentEditorActions?.documentID == "new")
        capturedOldAction.perform(.bold)
        capturedOldAction.selectPresentationMode(.source)
        #expect(oldExecutions == 0)
        window.currentEditorActions?.perform(.bold)
        #expect(newExecutions == 1)
        let capturedNewAction = try #require(window.currentEditorActions)
        capturedNewAction.selectPresentationMode(.read)
        #expect(newExecutions == 2)

        let other = document("B.md")
        window.documentController.selectDocument(other)
        capturedNewAction.selectPresentationMode(.source)
        #expect(newExecutions == 2)
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
            actions: actions("source", selectMode: { _ in sourceExecutions += 1 }) { sourceExecutions += 1 }, change: .activation
        )
        let capturedSourceAction = try #require(source.currentEditorActions)
        let transfer = try #require(source.documentController.takeSessionForTransfer(note))
        destination.documentController.receiveSessionTransfer(transfer)
        let destinationPort = ScholiumEditorCommandPort()
        destination.registerEditorActions(
            port: destinationPort, target: note.editingTarget, session: session,
            actions: actions("destination", selectMode: { _ in destinationExecutions += 1 }) { destinationExecutions += 1 }, change: .activation
        )
        capturedSourceAction.perform(.bold)
        capturedSourceAction.selectPresentationMode(.source)
        #expect(sourceExecutions == 0)
        #expect(source.currentEditorActions == nil)
        destination.currentEditorActions?.perform(.bold)
        #expect(destinationExecutions == 1)
        destination.currentEditorActions?.selectPresentationMode(.read)
        #expect(destinationExecutions == 2)
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
                actions: actions("closing", selectMode: { _ in }) {}, change: .activation
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

    private func actions(
        _ documentID: String, selectMode: @escaping (NotePresentationMode) -> Void, perform: @escaping () -> Void
    ) -> ScholiumFocusedEditorActions {
        ScholiumFocusedEditorActions(
            documentID: documentID,
            isComposing: false,
            selectPresentationMode: selectMode,
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
