import Foundation
import ScholiumContracts

/// Serialised document transitions: every change of the presented document
/// flushes the editor that is losing it before the next one appears.
extension WindowModel {
    /// Resolves document-scoped commands through the selected document's
    /// vault-qualified identity. Library browsing deliberately owns a
    /// different vault projection, so path-only lookup is unsafe when two
    /// Triptych roots contain the same relative path.
    func activeDocumentContext(
        for path: String
    ) -> (
        noteID: UUID,
        vaultID: UUID,
        vaultRole: VaultRole,
        fingerprint: DocumentFingerprint,
        note: WindowDocumentLocation
    )? {
        guard let descriptor = currentDocumentDescriptor,
            descriptor.reference.relativePath == path,
            let note = currentNote,
            note.relativePath == path
        else { return nil }
        return (
            descriptor.sessionKey.noteID,
            descriptor.reference.vaultID,
            descriptor.reference.vaultRole,
            note.document.fingerprint,
            note
        )
    }

    /// Uses the route's exact revision unless it addresses the active editor
    /// session, whose explicit flush may have just committed a newer revision.
    /// In either case the vault and stable note identity remain those captured
    /// by the mutation route, never those of the Library's browsed hierarchy.
    func mutationExpectedRevision(
        for target: NoteMutationTarget
    ) throws -> DocumentFingerprint {
        guard let descriptor = currentDocumentDescriptor,
            descriptor.reference.vaultID == target.documentID.vaultID,
            descriptor.reference.relativePath == target.relativePath,
            descriptor.sessionKey.noteID == target.stableNoteID
        else {
            return target.revision
        }
        guard let currentNote,
            currentNote.workspaceSnapshot?.stableIdentity.resolvedID == target.stableNoteID
        else {
            throw NoteIdentityRecoveryError.identityUnresolved(target.relativePath)
        }
        return currentNote.document.fingerprint
    }

    func registerEditorFlush(
        for relativePath: String,
        token: UUID,
        flush: @escaping @MainActor () async throws -> Void,
        captureForReconstruction: @escaping @MainActor () async throws -> Void
    ) {
        editorFlushCoordinator.registerCurrentEditor(
            relativePath: relativePath,
            token: token,
            triptychID: workspaceAssignment?.id,
            flush: flush,
            captureForReconstruction: captureForReconstruction
        )
    }

    func unregisterEditorFlush(token: UUID) {
        editorFlushCoordinator.unregisterCurrentEditor(
            token: token,
            selectedDocumentPath: selectedDocumentPath
        )
    }

    func flushRegisteredEditorIfNeeded(
        capturingEditorState: Bool = false
    ) async throws {
        try await editorFlushCoordinator.flushCurrentEditor(
            selectedDocumentPath: selectedDocumentPath,
            capturingEditorState: capturingEditorState,
            fallback: { [weak self] capturingEditorState in
                guard let self else { return }
                try await self.documentController.flushLeasedOrPinnedSessions(
                    capturingEditorState: capturingEditorState
                )
            }
        )
    }

    func flushRegisteredEditorIfMutatingActiveDocument(
        _ target: NoteMutationTarget
    ) async throws {
        guard let descriptor = currentDocumentDescriptor,
            descriptor.reference.vaultID == target.documentID.vaultID,
            descriptor.reference.relativePath == target.relativePath,
            descriptor.sessionKey.noteID == target.stableNoteID
        else { return }
        try await flushRegisteredEditorIfNeeded()
    }

    /// Serializes every transition that can replace the active document view.
    /// The newest requested destination wins, but an already-running operation
    /// is allowed to finish before the next begins so vault state is never
    /// mutated concurrently by two window transitions. Replacement navigation
    /// still flushes CodeMirror's exact text, but skips serializing selection,
    /// scroll, and undo state that will be discarded with the replaced tab.
    func enqueueDocumentTransition(
        preparation: DocumentTransitionPreparation = .saveOpenDocuments,
        preservingCurrentEditorState: Bool = true,
        retainingCurrentDocument target: DocumentSessionKey? = nil,
        _ operation: @escaping @MainActor () async throws -> Void,
        didFail customFailure: (@MainActor (Error) -> Void)? = nil,
        didSucceed: (@MainActor () -> Void)? = nil,
        didFinish: (@MainActor () -> Void)? = nil
    ) {
        guard !transferInProgress else { return }
        var preservedEditor: (document: WindowSelectedDocument, suspensionID: String?)?
        documentTransitionCoordinator.enqueue(
            prepare: { [weak self] in
                guard let self else { throw CancellationError() }
                if let target, self.currentDocumentDescriptor?.sessionKey == target { return }
                switch preparation {
                case .saveOpenDocuments:
                    if let document = self.documentController.selectedDocument {
                        let session = self.documentController.session(for: document.editingTarget)
                        defer {
                            preservedEditor = (document, session.editorSession.detachmentSuspensionID)
                        }
                        // Freeze before the final save: input accepted while
                        // opening a destination must not escape the saved base.
                        try await self.documentController.prepareSessionTransfer(document)
                        try await self.flushRegisteredEditorIfNeeded(capturingEditorState: false)
                        if session.editorSession.hasAttachedWebView {
                            // A commit rebases the editor identity. Capture its
                            // final source/history while input remains frozen.
                            try await session.editorSession.captureStateForViewReconstruction(suspendForDetachment: true)
                        }
                    } else {
                        try await self.flushRegisteredEditorIfNeeded(capturingEditorState: preservingCurrentEditorState)
                    }
                case .preserveSelectedDocument:
                    if let document = self.documentController.selectedDocument {
                        let session = self.documentController.session(for: document.editingTarget)
                        defer {
                            preservedEditor = (document, session.editorSession.detachmentSuspensionID)
                        }
                        try await self.documentController.prepareSessionTransfer(document)
                    }
                case .operationOnly:
                    break
                }
            },
            operation: operation,
            didFail: { [weak self] error in
                guard let self else { return }
                self.revealRetainedDocumentAfterTransitionFailure()
                if let customFailure {
                    customFailure(error)
                    return
                }
                if let issueID = self.documentTransitionIssueID {
                    self.shellState.dismissOperationIssue(id: issueID)
                }
                if let navigationError = error as? WindowNavigationError {
                    self.documentTransitionIssueID = self.reportOperationIssue(navigationError.localizedDescription, kind: .warning)
                } else if case .saveOpenDocuments = preparation {
                    self.lastSaveError = error.localizedDescription
                    self.documentTransitionIssueID = self.reportOperationIssue(
                        String(
                            localized: "The current note could not be saved, so Scholium kept it open. \(error.localizedDescription)",
                            table: "Localizable",
                            bundle: .module
                        ),
                        kind: .error
                    )
                } else {
                    self.documentTransitionIssueID = self.reportOperationIssue(error.localizedDescription, kind: .error)
                }
            },
            didSucceed: { [weak self] in
                if let self, let issueID = self.documentTransitionIssueID {
                    self.shellState.dismissOperationIssue(id: issueID)
                    self.documentTransitionIssueID = nil
                }
                didSucceed?()
            },
            didFinish: { [weak self] in
                if let preservedEditor {
                    self?.documentController.resumeAutosave(
                        afterTransferOf: preservedEditor.document,
                        suspensionID: preservedEditor.suspensionID
                    )
                }
                didFinish?()
            }
        )
    }

    private func revealRetainedDocumentAfterTransitionFailure() {
        guard let document = documentController.selectedDocument,
            let vaultID = currentRegisteredVault?.id,
            discoveryController.library.sourceScope == .library
        else { return }
        discoveryController.prepareLibraryNoteReveal(
            relativePath: document.relativePath,
            folderAncestors: libraryFolderAncestors(forDocumentPath: document.relativePath),
            clearFilters: false,
            in: LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        )
    }

    func enqueueCurrencyAwareDocumentTransition(
        preservingCurrentEditorState: Bool = true,
        retainingCurrentDocument target: DocumentSessionKey? = nil,
        validateBeforePreparation: @escaping @MainActor () throws -> Void = {},
        _ operation:
            @escaping @MainActor (
                DocumentTransitionCoordinator.Currency
            ) async throws -> Void,
        didFail customFailure: (@MainActor (Error) -> Void)? = nil,
        didSucceed: (@MainActor () -> Void)? = nil,
        didFinish: (@MainActor () -> Void)? = nil
    ) {
        documentTransitionCoordinator.enqueueCurrencyAware(
            prepare: { [weak self] in
                guard let self else { throw CancellationError() }
                try validateBeforePreparation()
                if let target, self.currentDocumentDescriptor?.sessionKey == target { return }
                try await self.flushRegisteredEditorIfNeeded(
                    capturingEditorState: preservingCurrentEditorState
                )
            },
            operation: operation,
            didFail: { [weak self] error in
                guard let self else { return }
                self.revealRetainedDocumentAfterTransitionFailure()
                if let customFailure {
                    customFailure(error)
                    return
                }
                if let issueID = self.documentTransitionIssueID {
                    self.shellState.dismissOperationIssue(id: issueID)
                }
                if let navigationError = error as? WindowNavigationError {
                    self.documentTransitionIssueID = self.reportOperationIssue(
                        navigationError.localizedDescription,
                        kind: .warning
                    )
                } else {
                    self.lastSaveError = error.localizedDescription
                    self.documentTransitionIssueID = self.reportOperationIssue(
                        String(
                            localized: "The current note could not be saved, so Scholium kept it open. \(error.localizedDescription)",
                            table: "Localizable",
                            bundle: .module
                        ),
                        kind: .error
                    )
                }
            },
            didSucceed: { [weak self] in
                if let self, let issueID = self.documentTransitionIssueID {
                    self.shellState.dismissOperationIssue(id: issueID)
                    self.documentTransitionIssueID = nil
                }
                didSucceed?()
            },
            didFinish: { didFinish?() }
        )
    }
}
