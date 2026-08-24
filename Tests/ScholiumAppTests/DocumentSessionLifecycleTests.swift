import Foundation
import ScholiumContracts
import Testing
import Combine
@testable import ScholiumApp

@MainActor
@Suite("Document session lifecycle")
struct DocumentSessionLifecycleTests {
    @Test("Repeated Review preparation preserves a finalized retained revision")
    func repeatedReadProjectionPreparationPreservesReadiness() {
        let session = DocumentSessionModel(key: nil)
        let currentFingerprint = "current-revision"

        session.renderedReadFingerprint = currentFingerprint
        session.renderedReadReadyFingerprint = currentFingerprint
        session.failedReadFingerprint = currentFingerprint

        session.prepareReadProjection(for: currentFingerprint)

        #expect(session.failedReadFingerprint == nil)
        #expect(
            session.renderedReadReadyFingerprint == currentFingerprint
        )

        session.prepareReadProjection(for: "new-revision")

        #expect(session.renderedReadReadyFingerprint.isEmpty)
    }

    @Test("Note Review task auto-presents once per retained pending set")
    func noteReviewTaskPresentationLifecycle() {
        let session = DocumentSessionModel(key: nil)
        let noteID = UUID()
        let firstRecordID = UUID()
        let secondRecordID = UUID()
        let firstPending = reviewState(
            noteID: noteID,
            recordIDs: [firstRecordID],
            source: "saved source"
        )

        session.reconcileNoteReviewTask(with: firstPending)
        #expect(session.noteReviewTaskPresentation.isPresented(for: noteID))

        session.dismissNoteReviewTask(for: firstPending)
        #expect(!session.noteReviewTaskPresentation.isPresented)

        let researcherEdited = reviewState(
            noteID: noteID,
            recordIDs: [firstRecordID],
            source: "later researcher edit"
        )
        session.reconcileNoteReviewTask(with: researcherEdited)
        #expect(!session.noteReviewTaskPresentation.isPresented)

        session.presentNoteReviewTask(for: researcherEdited)
        #expect(session.noteReviewTaskPresentation.isPresented(for: noteID))
        session.dismissNoteReviewTask(for: researcherEdited)

        let newAgentActivity = reviewState(
            noteID: noteID,
            recordIDs: [firstRecordID, secondRecordID],
            source: "later researcher edit"
        )
        session.reconcileNoteReviewTask(with: newAgentActivity)
        #expect(session.noteReviewTaskPresentation.isPresented(for: noteID))

        session.reconcileNoteReviewTask(
            with: WorkspaceNoteReviewState(
                noteID: noteID,
                currentRevision: newAgentActivity.currentRevision,
                status: .noAgentChangesAwaitingReview
            )
        )
        #expect(!session.noteReviewTaskPresentation.isPresented)
    }

    @Test("Document presentation commits only valid lifecycle states")
    func documentPresentationStateMachine() {
        let session = DocumentSessionModel(key: nil)
        var publications: [DocumentPresentationState] = []
        let observation = session.$presentation.dropFirst().sink {
            publications.append($0)
        }

        session.preparePresentationMode(.source)
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == .source)
        #expect(!session.isEditing)
        #expect(!session.retainsEditorSurface)

        session.beginEditing(in: .source)
        #expect(session.presentationMode == .source)
        #expect(session.activeEditorMode == .source)
        #expect(session.pendingEditorMode == nil)
        #expect(session.isEditing)
        #expect(session.retainsEditorSurface)

        session.switchEditorMode(to: .livePreview)
        #expect(session.presentationMode == .livePreview)
        #expect(session.activeEditorMode == .livePreview)
        #expect(session.retainedEditorMode == .livePreview)

        session.finishEditing()
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == nil)
        #expect(!session.isEditing)
        #expect(session.retainsEditorSurface)
        #expect(session.retainedEditorMode == .livePreview)

        #expect(publications.count == 4)
        _ = observation
    }

    @Test("A failed managed editor retry replaces only its retained WebView request")
    func managedCreationEditorRetry() {
        let session = DocumentSessionModel(key: nil)
        session.beginManagedCreationEntry(bodyStartUTF16: 24)
        session.beginEditing(in: .livePreview)
        session.editorSession.reportError("Editor failed")
        let priorReconstruction = session.editorSession.viewReconstructionID

        #expect(session.isEnteringManagedCreation)
        #expect(session.editorSession.errorMessage == "Editor failed")
        session.editorSession.retryUnavailablePresentation()
        #expect(
            session.editorSession.viewReconstructionID
                != priorReconstruction
        )
        #expect(session.editorSession.errorMessage == nil)

        session.completeManagedCreationEntry()
        #expect(!session.isEnteringManagedCreation)
    }

    @Test("Managed creation intent is discarded only by explicit presentation teardown")
    func managedCreationIntentTeardown() {
        let session = DocumentSessionModel(key: nil)

        session.beginManagedCreationEntry(bodyStartUTF16: 24)
        session.beginEditing(in: .livePreview)
        session.finishEditing()
        #expect(!session.isEnteringManagedCreation)

        session.beginManagedCreationEntry(bodyStartUTF16: 24)
        session.resetPresentation()
        #expect(!session.isEnteringManagedCreation)

        session.beginManagedCreationEntry(bodyStartUTF16: 24)
        session.shutdown()
        #expect(!session.isEnteringManagedCreation)
    }

    private func reviewState(
        noteID: UUID,
        recordIDs: [UUID],
        source: String
    ) -> WorkspaceNoteReviewState {
        WorkspaceNoteReviewState(
            noteID: noteID,
            currentRevision: DocumentFingerprint(content: source),
            status: .needsReview,
            pendingActivities: recordIDs.map {
                PortableResearchNoteActivityReference(
                    recordID: $0,
                    noteID: noteID
                )
            }
        )
    }

    @Test("Lease reconciliation acquires the destination before reaping the source")
    func acquireBeforeRelease() {
        let store = DocumentSessionStore()
        let first = DocumentEditingTarget.workspace(.init(vaultID: UUID(), noteID: UUID()))
        let second = DocumentEditingTarget.workspace(.init(vaultID: UUID(), noteID: UUID()))
        let firstSession = store.session(for: first)
        firstSession.preparePresentationMode(.source)

        _ = store.reconcileLeases(openTargets: [first], foregroundTarget: first)
        _ = store.reconcileLeases(openTargets: [second], foregroundTarget: second)

        #expect(store.retainedSession(for: first) == nil)
        #expect(store.retainedSession(for: second) != nil)
        #expect(firstSession.editingSource.isEmpty)
    }

    @Test("Fallback targets retain vault-qualified session identity")
    func unifiedTargets() {
        let store = DocumentSessionStore()
        let workspace = DocumentEditingTarget.workspace(.init(vaultID: UUID(), noteID: UUID()))
        let fallbackVaultID = UUID()
        let fallback = DocumentEditingTarget.unavailable(
            vaultID: fallbackVaultID,
            relativePath: "Inbox\\literal.md"
        )
        let samePathInAnotherVault = DocumentEditingTarget.unavailable(
            vaultID: UUID(),
            relativePath: "Inbox\\literal.md"
        )

        #expect(store.session(for: workspace) === store.session(for: workspace))
        #expect(store.session(for: fallback) === store.session(for: fallback))
        #expect(store.session(for: fallback) !== store.session(for: samePathInAnotherVault))
        #expect(fallback.vaultID == fallbackVaultID)
        #expect(store.retainedSessions.count == 3)
    }

    @Test(
        "Every safety state pins a zero-lease session",
        arguments: [
            DocumentSessionStore.PinReason.dirty,
            .composition,
            .conflict,
            .saveInFlight,
            .retryableRecovery,
        ]
    )
    func pinReasons(reason: DocumentSessionStore.PinReason) {
        let store = DocumentSessionStore()
        let target = DocumentEditingTarget.workspace(.init(vaultID: UUID(), noteID: UUID()))
        let session = store.session(for: target)
        session.originalEditingSource = "clean"
        session.editingSource = "clean"
        switch reason {
        case .dirty:
            session.editingSource = "dirty"
        case .composition:
            session.editorSession.loadDocument(
                "clean",
                documentID: session.editorSession.bridgeDocumentID,
                mode: .livePreview
            )
            let selection = MarkdownEditorSelectionRange(anchor: 0, head: 0)
            session.editorSession.updateInteraction(
                selections: [selection],
                line: 1,
                column: 1,
                lineCount: 1,
                documentVersion: session.editorSession.generation,
                context: MarkdownEditorContext(
                    selections: [selection],
                    activeInlineConstructs: [],
                    activeBlockConstructs: [],
                    tablePosition: nil,
                    composing: true,
                    availableCommands: [],
                    undoLabel: nil,
                    redoLabel: nil
                )
            )
        case .conflict:
            session.conflict = DocumentConflictSnapshot(
                relativePath: "Pinned.md",
                editorSource: "editor",
                diskSource: "disk",
                baseRevision: DocumentFingerprint(content: "base")
            )
        case .saveInFlight:
            session.isSavingEdit = true
        case .retryableRecovery:
            session.canRetrySave = true
        case .recoveryBuffer:
            Issue.record("Recovery-buffer pin is exercised by WebKit recovery integration tests")
        }

        _ = store.reconcileLeases(openTargets: [], foregroundTarget: nil)
        #expect(store.retainedSession(for: target) === session)
        #expect(store.pinReasons(for: session).contains(reason))
    }

    @Test("Document integrity presentation excludes invalid state combinations")
    func documentIntegrityPresentation() {
        #expect(DocumentIntegrityPresentation.resolve(
            editError: nil,
            conflict: nil,
            canRetrySave: false
        ) == nil)
        #expect(DocumentIntegrityPresentation.resolve(
            editError: "The save service is unavailable.",
            conflict: nil,
            canRetrySave: true
        ) == .autosaveFailed(
            message: "The save service is unavailable.",
            canRetry: true
        ))

        let conflict = DocumentConflictSnapshot(
            relativePath: "Conflict.md",
            editorSource: "editor",
            diskSource: "disk",
            baseRevision: DocumentFingerprint(content: "base")
        )
        #expect(DocumentIntegrityPresentation.resolve(
            editError: "A lower-level conflict description.",
            conflict: conflict,
            canRetrySave: true
        ) == .conflict)

        #expect(DocumentController.saveFailureAllowsRetry(
            VaultRepositoryError.writeFailed("Temporary provider failure")
        ))
        #expect(!DocumentController.saveFailureAllowsRetry(
            VaultRepositoryError.conflict(
                expected: DocumentFingerprint(content: "before"),
                current: DocumentFingerprint(content: "external")
            )
        ))
    }

    @Test("A clean detached zero-lease session is fully reaped")
    func detachedEviction() {
        let store = DocumentSessionStore()
        let target = DocumentEditingTarget.unavailable(
            vaultID: UUID(),
            relativePath: "Closed.md"
        )
        let session = store.session(for: target)
        session.editingSource = "large exact source"
        session.originalEditingSource = "large exact source"
        session.renderedReadHTML = String(repeating: "x", count: 4_096)
        session.previewCatalog = DocumentPreviewCatalog(
            graphGeneration: 1,
            source: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Closed.md"),
            sourceFingerprint: DocumentFingerprint(content: "large exact source"),
            links: []
        )

        let reaped = store.reconcileLeases(openTargets: [], foregroundTarget: nil)

        #expect(reaped.map(\.target) == [target])
        #expect(store.retainedSession(for: target) == nil)
        #expect(session.editingSource.isEmpty)
        #expect(session.renderedReadHTML.isEmpty)
        #expect(session.previewCatalog == nil)
    }

    @Test("Closed-document presentation is bounded and responds to memory pressure")
    func boundedPresentationCache() {
        let controller = DocumentController()
        let vaultID = UUID()
        for index in 0..<80 {
            let key = DocumentSessionKey(vaultID: vaultID, noteID: UUID())
            let descriptor = WindowDocumentDescriptor(
                sessionKey: key,
                reference: VaultNoteReference(
                    vaultID: vaultID,
                    vaultName: "Fixture",
                    vaultRole: .topicKnowledge,
                    relativePath: "Topic-\(index).md",
                    stableNoteID: key.noteID.uuidString
                )
            )
            controller.selectDocument(.workspace(descriptor))
            let session = controller.session(for: key)
            session.preparePresentationMode(.source)
            session.scrollFraction = Double(index) / 100
            controller.reconcileSessionLeases(
                leasedDocuments: [.workspace(descriptor)],
                selectedDocument: .workspace(descriptor)
            )
            controller.reconcileSessionLeases(leasedDocuments: [], selectedDocument: nil)
        }

        #expect(controller.retainedSessionCount == 0)
        #expect(controller.closedPresentationCount == 64)
        controller.handleMemoryPressure(.warning)
        #expect(controller.closedPresentationCount == 16)
        controller.handleMemoryPressure(.critical)
        #expect(controller.closedPresentationCount == 0)
    }

    @Test("A renamed stable document restores scroll and reapplies the Workspace mode")
    func renamePresentationRestore() {
        let controller = DocumentController()
        let key = DocumentSessionKey(vaultID: UUID(), noteID: UUID())
        func descriptor(path: String) -> WindowDocumentDescriptor {
            WindowDocumentDescriptor(
                sessionKey: key,
                reference: VaultNoteReference(
                    vaultID: key.vaultID,
                    vaultName: "Fixture",
                    vaultRole: .topicKnowledge,
                    relativePath: path,
                    stableNoteID: key.noteID.uuidString
                )
            )
        }
        let original = descriptor(path: "Before.md")
        controller.selectDocument(.workspace(original))
        let first = controller.session(for: key)
        first.preparePresentationMode(.source)
        first.scrollFraction = 0.6
        controller.reconcileSessionLeases(
            leasedDocuments: [.workspace(original)],
            selectedDocument: .workspace(original)
        )
        controller.reconcileSessionLeases(leasedDocuments: [], selectedDocument: nil)
        controller.migratePresentationPath(
            from: "Before.md",
            to: "After.md",
            vaultID: key.vaultID
        )

        let renamed = descriptor(path: "After.md")
        controller.selectDocument(.workspace(renamed))
        let reopened = controller.session(for: key)

        #expect(reopened !== first)
        #expect(reopened.presentationMode == .read)
        #expect(reopened.pendingEditorMode == .livePreview)
        #expect(reopened.scrollFraction == 0.6)
        #expect(reopened.editingSource.isEmpty)
    }
}
