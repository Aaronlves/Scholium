import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Agent Change notification destinations", .serialized)
@MainActor
struct AgentChangeNotificationRoutingTests {
    @Test("A verified receipt opens current Changes and reviewed evidence remains reachable without changing a dirty Note")
    func currentChangesAndReceiptFallback() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/notification-routing-tests/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let vaults = ["Analyses", "Topics", "Works"].map { root.appendingPathComponent("Triptych/" + $0) }
        for directory in vaults { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let source = "# Researcher Note\n\nSaved source.\n"
        let file = vaults[0].appendingPathComponent("Source.md")
        try Data(source.utf8).write(to: file)
        let store = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("ApplicationSupport"))
        do {
            let configured = try await store.configureTriptychCapabilities(
                paperAnalysisURL: vaults[0], topicKnowledgeURL: vaults[1], outputURL: vaults[2],
                portableContainerURL: root.appendingPathComponent("Triptych"), triptychName: "Notification fixture")
            let window = WindowModel(workspaceStore: store, requestedTriptychID: configured.id)
            await window.refreshWorkspaceAssignment(preferredTriptychID: configured.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            let note = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Source.md" })
            let snapshot = try #require(
                try await window.documentController.noteSnapshot(.init(vaultID: note.reference.vaultID, relativePath: note.reference.relativePath)))
            window.documentController.installOpenedDocument(snapshot, vaultName: note.reference.vaultName, vaultRole: note.reference.vaultRole)
            let document = try #require(window.documentController.selectedDocument)
            let editor = window.documentController.session(for: document.editingTarget)
            editor.suppressAutosave = true
            editor.editingSource = "Unsaved researcher argument"
            let mode = window.presentedDocumentMode
            let targetVault = try #require(configured.assignment.vault(for: .topicKnowledge))
            let created = try await configured.agentCollaboration.createNote(
                ManagedNoteCreationRequest(
                    vaultID: targetVault.id, destination: .exact(relativePath: "Agent Note.md"),
                    source: "# Agent Note\n\nExact saved content.\n", authority: .mcp(reservedIdentity: UUID())), admission: nil)
            let route = AgentChangeNotificationRoute(created.change)
            await window.openNotifiedAgentChange(route)
            guard case .documentChanges(scope: .note(let selectedID)) = window.presentationRouter.sheet else {
                Issue.record("The notification did not open the affected Note's current Changes")
                await store.shutdownApplicationRuntime()
                return
            }
            #expect(selectedID == created.noteID)
            let review = try await configured.changes.changeReview(noteID: created.noteID)
            _ = try await configured.changes.markReviewed(capture: review.capture)
            window.presentationRouter.dismissSheet()
            await window.openNotifiedAgentChange(route)
            guard case .agentChangeReceipt(let receiptID) = window.presentationRouter.sheet else {
                Issue.record("A reviewed Note lost its exact operation evidence destination")
                await store.shutdownApplicationRuntime()
                return
            }
            #expect(receiptID == created.change.id)
            #expect(window.documentController.selectedDocument?.editingTarget == document.editingTarget)
            #expect(window.presentedDocumentMode == mode)
            #expect(editor.editingSource == "Unsaved researcher argument")
            #expect(try Data(contentsOf: file) == Data(source.utf8))
            window.presentationRouter.present(.transactionRecovery)
            await window.openNotifiedAgentChange(route)
            #expect(window.presentationRouter.sheet?.id == "transaction-recovery")
            window.presentationRouter.dismissSheet()
            let cancelled = Task { await window.openNotifiedAgentChange(route) }
            cancelled.cancel()
            await cancelled.value
            #expect(window.presentationRouter.sheet == nil)
            let unrelated = AgentChange(
                id: created.change.id, triptychID: configured.id, operation: created.change.operation,
                noteID: UUID(), role: created.change.role,
                originalRelativePath: created.change.originalRelativePath, finalRelativePath: created.change.finalRelativePath,
                beforeFingerprint: created.change.beforeFingerprint, afterFingerprint: created.change.afterFingerprint,
                state: created.change.state, createdAt: created.change.createdAt, confirmedAt: created.change.confirmedAt, undoneAt: nil)
            await window.openNotifiedAgentChange(AgentChangeNotificationRoute(unrelated))
            #expect(window.presentationRouter.sheet == nil)
            #expect(!window.shellState.operationIssues.isEmpty)
            await store.shutdownApplicationRuntime()
        } catch {
            await store.shutdownApplicationRuntime()
            throw error
        }
    }
}
