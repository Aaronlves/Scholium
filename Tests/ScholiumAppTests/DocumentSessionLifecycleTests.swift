import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@MainActor
@Suite("Document session lifecycle")
struct DocumentSessionLifecycleTests {
    @Test("Read and Edit retain one native viewport position")
    func readAndEditorShareScrollPosition() {
        let session = DocumentSessionModel(key: nil)
        session.observeScrollFraction(0.2)
        #expect(session.scrollFraction == 0.2)
        session.preparePresentationMode(.edit)
        session.beginEditing(in: .edit)
        #expect(session.scrollFraction == 0.2)
        session.observeScrollFraction(0.9)
        session.finishEditing()
        #expect(session.scrollFraction == 0.9)
    }

    @Test("Document top presents persistent feedback, Actions, then permission education")
    func documentTopSurfacePriority() {
        #expect(
            DocumentTopSurfacePresentation.resolve(
                hasPersistentFeedback: true,
                hasActionNotifications: true,
                hasSettlementReminder: true,
                hasNotificationPermissionNotice: true
            ) == .persistentFeedback)
        #expect(
            DocumentTopSurfacePresentation.resolve(
                hasPersistentFeedback: false,
                hasActionNotifications: true,
                hasSettlementReminder: false,
                hasNotificationPermissionNotice: true
            ) == .researchNotifications)
        #expect(
            DocumentTopSurfacePresentation.resolve(
                hasPersistentFeedback: false,
                hasActionNotifications: false,
                hasSettlementReminder: true,
                hasNotificationPermissionNotice: true
            ) == .researchNotifications)
        #expect(
            DocumentTopSurfacePresentation.resolve(
                hasPersistentFeedback: false,
                hasActionNotifications: false,
                hasSettlementReminder: false,
                hasNotificationPermissionNotice: true
            ) == .notificationPermissionNotice)
        #expect(
            DocumentTopSurfacePresentation.resolve(
                hasPersistentFeedback: false,
                hasActionNotifications: false,
                hasSettlementReminder: false,
                hasNotificationPermissionNotice: false
            ) == .none)
    }

    @Test("Document presentation commits only valid lifecycle states")
    func documentPresentationStateMachine() {
        let session = DocumentSessionModel(key: nil)
        var publications: [DocumentPresentationState] = []
        let observation = session.$presentation.dropFirst().sink {
            publications.append($0)
        }

        session.preparePresentationMode(.edit)
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == .edit)
        #expect(!session.isEditing)
        #expect(session.retainsEditorSurface)

        session.beginEditing(in: .edit)
        #expect(session.presentationMode == .edit)
        #expect(session.activeEditorMode == .edit)
        #expect(session.pendingEditorMode == nil)
        #expect(session.isEditing)
        #expect(session.retainsEditorSurface)

        session.switchEditorMode(to: .edit)
        #expect(session.presentationMode == .edit)
        #expect(session.activeEditorMode == .edit)
        #expect(session.retainedEditorMode == .edit)

        session.finishEditing()
        #expect(session.presentationMode == .read)
        #expect(session.pendingEditorMode == nil)
        #expect(!session.isEditing)
        #expect(session.retainsEditorSurface)
        #expect(session.retainedEditorMode == .edit)

        #expect(publications.count == 4)
        _ = observation
    }

    @Test("A native editor retry retains its view and checked source")
    func managedCreationEditorRetry() {
        let session = DocumentSessionModel(key: nil)
        session.beginManagedCreationEntry(bodyStartUTF16: 24)
        session.beginEditing(in: .edit)
        session.editorSession.loadDocument("Draft", documentID: "retry.md", mode: .edit)
        session.editorSession.reportError("Editor failed")
        let retainedView = session.editorSession.nativeEditor

        #expect(session.isEnteringManagedCreation)
        #expect(session.editorSession.errorMessage == "Editor failed")
        session.editorSession.retryUnavailablePresentation()
        #expect(session.editorSession.nativeEditor === retainedView)
        #expect(session.editorSession.checkedSource == "Draft")
        #expect(session.editorSession.errorMessage == nil)

        session.completeManagedCreationEntry()
        #expect(!session.isEnteringManagedCreation)
    }

    @Test("Managed creation intent is discarded only by explicit presentation teardown")
    func managedCreationIntentTeardown() {
        let session = DocumentSessionModel(key: nil)

        session.beginManagedCreationEntry(bodyStartUTF16: 24)
        session.beginEditing(in: .edit)
        session.finishEditing()
        #expect(!session.isEnteringManagedCreation)

        session.beginManagedCreationEntry(bodyStartUTF16: 24)
        session.resetPresentation()
        #expect(!session.isEnteringManagedCreation)

        session.beginManagedCreationEntry(bodyStartUTF16: 24)
        session.shutdown()
        #expect(!session.isEnteringManagedCreation)
    }

    @Test("Activation preserves selection but starts a new opening presentation")
    func activationFocusPolicy() {
        let session = DocumentSessionModel(key: nil)
        let source = "# Section\n\nArgument."

        session.prepareForDocumentActivation()
        #expect(session.editorSession.preferredDocumentFocusTarget == .editor)

        session.editorSession.loadDocument(
            source,
            documentID: "focus-policy",
            mode: .edit
        )
        #expect(session.editorSession.preferredDocumentFocusTarget == .editor)
        session.editorSession.nativeEditor.setSelectedRange(NSRange(location: 12, length: 0))
        session.editorSession.updateNativeInteraction()
        let previousOpening = session.editorSession.openingPresentationID
        session.prepareForDocumentActivation()
        #expect(session.editorSession.openingPresentationID != previousOpening)

        #expect(session.editorSession.preferredDocumentFocusTarget == .editor)
        #expect(session.windowPresentationSnapshot.focusTarget == .editor)
        #expect(
            session.windowPresentationSnapshot.selections == [
                WindowDocumentSelectionRange(anchor: 12, head: 12)
            ])
    }

    @Test("Managed creation keeps explicit body focus")
    func managedCreationFocusPolicy() {
        let session = DocumentSessionModel(key: nil)
        session.beginManagedCreationEntry(bodyStartUTF16: 24)

        session.prepareForDocumentActivation()

        #expect(session.editorSession.preferredDocumentFocusTarget == .editor)
    }

    @Test("Persisted editor position restores only for the same exact source")
    func persistedPresentationRequiresExactSource() {
        let source = "Argument."
        let presentation = WindowDocumentPresentationSnapshot(
            scrollFraction: 0.4,
            sourceFingerprint: DocumentFingerprint(content: source).sha256,
            selections: [WindowDocumentSelectionRange(anchor: 5, head: 5)],
            focusTarget: .editor
        )
        let matching = DocumentSessionModel(key: nil)
        matching.restoreWindowPresentation(presentation, source: source)
        matching.editorSession.loadDocument(
            source,
            documentID: "matching",
            mode: .edit
        )
        #expect(matching.editorSession.preferredDocumentFocusTarget == .editor)
        #expect(matching.windowPresentationSnapshot.selections == presentation.selections)

        let stale = DocumentSessionModel(key: nil)
        stale.restoreWindowPresentation(presentation, source: "Changed argument.")
        stale.prepareForDocumentActivation()
        #expect(stale.editorSession.preferredDocumentFocusTarget == .editor)
        #expect(stale.windowPresentationSnapshot.selections.isEmpty)
    }

    @Test("Lease reconciliation acquires the destination before reaping the source")
    func acquireBeforeRelease() {
        let store = DocumentSessionStore()
        let first = DocumentEditingTarget.workspace(.init(vaultID: UUID(), noteID: UUID()))
        let second = DocumentEditingTarget.workspace(.init(vaultID: UUID(), noteID: UUID()))
        let firstSession = store.session(for: first)
        firstSession.preparePresentationMode(.edit)

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
                documentID: session.editorSession.editorDocumentID,
                mode: .edit
            )
            let selection = MarkdownEditorSelectionRange(anchor: 0, head: 0)
            session.editorSession.nativeEditor.setMarkedText(
                "pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: 0, length: 0))
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
        #expect(
            DocumentIntegrityPresentation.resolve(
                editError: nil,
                conflict: nil,
                canRetrySave: false
            ) == nil)
        #expect(
            DocumentIntegrityPresentation.resolve(
                editError: "The save service is unavailable.",
                conflict: nil,
                canRetrySave: true
            )
                == .autosaveFailed(
                    message: "The save service is unavailable.",
                    canRetry: true
                ))

        let conflict = DocumentConflictSnapshot(
            relativePath: "Conflict.md",
            editorSource: "editor",
            diskSource: "disk",
            baseRevision: DocumentFingerprint(content: "base")
        )
        #expect(
            DocumentIntegrityPresentation.resolve(
                editError: "A lower-level conflict description.",
                conflict: conflict,
                canRetrySave: true
            ) == .conflict)

        #expect(
            DocumentController.saveFailureAllowsRetry(
                VaultRepositoryError.writeFailed("Temporary provider failure")
            ))
        #expect(
            !DocumentController.saveFailureAllowsRetry(
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
            session.preparePresentationMode(.edit)
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
        first.preparePresentationMode(.edit)
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
        #expect(reopened.pendingEditorMode == .edit)
        #expect(reopened.scrollFraction == 0.6)
        #expect(reopened.editingSource.isEmpty)
    }
}
