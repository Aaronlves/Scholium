import Foundation
import ScholiumContracts
import ScholiumCore

/// Application-owned bounded reads and mutation evidence for the fixed MCP collaboration
/// surface and the Agent Changes UI. External hosts never receive a
/// repository, filesystem URL, or durable write authority.
public actor AgentCollaborationOperations: AgentCollaborationUseCases {
    let reference: WorkspaceHandleReference

    init(reference: WorkspaceHandleReference) {
        self.reference = reference
    }

    public func displayTarget(noteID: UUID, expectedFingerprint: DocumentFingerprint,
                              startUTF8: Int?, endUTF8: Int?, expectedText: String?) async throws -> AgentNoteDisplayTarget {
        let handle = try await reference.requireHandle()
        let note = try await handle.currentAgentNote(noteID: noteID)
        let document = try await handle.loadDocument(note.id)
        guard document.fingerprint == expectedFingerprint else { throw AgentCollaborationError.staleRevision(expected: expectedFingerprint, current: document.fingerprint) }
        guard try await handle.resolvedIdentity(for: note.id, expectedRevision: document.fingerprint).id == noteID else {
            throw AgentCollaborationError.noteAmbiguous(noteID)
        }
        return try .init(triptychID: handle.id, noteID: noteID, note: note.id, fingerprint: expectedFingerprint,
            source: document.sourceBytes, startUTF8: startUTF8, endUTF8: endUTF8, expectedText: expectedText)
    }

    public func createNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> AgentNoteCreationResult {
        let handle = try await reference.requireHandle()
        return try await handle.createAgentNote(request)
    }

    public func moveNote(noteID: UUID, expectedFingerprint: DocumentFingerprint, to path: String,
                         expectedPlanFingerprint: DocumentFingerprint) async throws -> AgentNoteMoveResult {
        let handle = try await reference.requireHandle()
        return try await handle.moveAgentNote(noteID: noteID, expectedFingerprint: expectedFingerprint,
            to: path, expectedPlanFingerprint: expectedPlanFingerprint)
    }

    public func previewMoveMutation(noteID: UUID, expectedFingerprint: DocumentFingerprint, to path: String,
                                    expectedPlanFingerprint: DocumentFingerprint) async throws -> AgentNoteUpdatePreview {
        let handle = try await reference.requireHandle()
        return try await handle.previewAgentMoveMutation(noteID: noteID, expectedFingerprint: expectedFingerprint,
            to: path, expectedPlanFingerprint: expectedPlanFingerprint)
    }

    public func previewMoveNote(noteID: UUID, expectedFingerprint: DocumentFingerprint, to relativePath: String) async throws -> AgentNoteMovePreview {
        let handle = try await reference.requireHandle()
        return try await handle.previewAgentNoteMove(noteID: noteID, expectedFingerprint: expectedFingerprint, to: relativePath)
    }

    public func previewUpdateNote(
        noteID: UUID, expectedFingerprint: DocumentFingerprint,
        update: AgentNoteUpdate
    ) async throws -> AgentNoteUpdatePreview {
        let handle = try await reference.requireHandle()
        return try await handle.previewAgentNoteUpdate(
            noteID: noteID, expectedFingerprint: expectedFingerprint, update: update)
    }

    public func updateNote(
        noteID: UUID,
        expectedFingerprint: DocumentFingerprint,
        update: AgentNoteUpdate
    ) async throws -> AgentNoteUpdateResult {
        let handle = try await reference.requireHandle()
        return try await handle.updateAgentNote(
            noteID: noteID,
            expectedFingerprint: expectedFingerprint,
            update: update
        )
    }

    public func trashNote(
        noteID: UUID,
        expectedFingerprint: DocumentFingerprint
    ) async throws -> AgentNoteTrashResult {
        let handle = try await reference.requireHandle()
        return try await handle.trashAgentNote(
            noteID: noteID,
            expectedFingerprint: expectedFingerprint
        )
    }

    public func agentChanges() async throws -> [AgentChange] {
        let handle = try await reference.requireHandle()
        return try await handle.agentChanges()
    }

    public func agentChangeReview(id: UUID) async throws -> AgentChangeReview {
        let handle = try await reference.requireHandle()
        return try await handle.reviewAgentChange(id: id)
    }

    public func previewUndoAgentChange(id: UUID, expectedAfterFingerprint: DocumentFingerprint) async throws -> AgentNoteUpdatePreview {
        let handle = try await reference.requireHandle()
        return try await handle.previewAgentChangeUndo(id: id, expectedAfterFingerprint: expectedAfterFingerprint)
    }

    public func undoAgentChange(
        id: UUID,
        expectedAfterFingerprint: DocumentFingerprint
    ) async throws -> AgentChangeUndoResult {
        let handle = try await reference.requireHandle()
        return try await handle.undoAgentChange(
            id: id,
            expectedAfterFingerprint: expectedAfterFingerprint
        )
    }
}

extension WorkspaceHandle {

    func createAgentNote(
        _ request: ManagedNoteCreationRequest
    ) async throws -> AgentNoteCreationResult {
        try requireActive()
        guard case .mcp(let reservedIdentity) = request.authority else {
            throw AgentCollaborationError.invalidRequest(
                "Agent collaboration creation requires one MCP-reserved Note identity."
            )
        }
        guard case .exact(let relativePath) = request.destination else {
            throw AgentCollaborationError.invalidRequest(
                "Agent collaboration creation requires one exact Markdown path."
            )
        }
        let role = try vault(id: request.vaultID).role
        guard Self.isAgentWritableRole(role) else {
            throw AgentCollaborationError.invalidRequest(
                "Agent collaboration can create only in Analyses, Topics, or Works."
            )
        }
        let intendedSource = try ManagedNoteSourceBuilder.source(
            for: request,
            vaultRole: role
        )
        let intendedData = Data(intendedSource.utf8)
        let prepared = try await services.agentChangeStore.prepare(
            operation: .create,
            noteID: reservedIdentity,
            role: role,
            originalRelativePath: nil,
            finalRelativePath: relativePath,
            beforeData: nil,
            afterData: intendedData
        )
        do {
            let outcome = try await createManagedNote(request)
            let commit = outcome.committedValue
            guard commit.id.relativePath == relativePath,
                  commit.id.vaultID == request.vaultID,
                  commit.stableIdentity.resolvedID == reservedIdentity,
                  commit.document.sourceBytes == intendedData,
                  outcome.identityRecoveryWarning == nil else {
                _ = try? await services.agentChangeStore.markOutcomeUncertain(
                    id: prepared.id
                )
                throw AgentCollaborationError.changeConfirmationUncertain(
                    prepared.id
                )
            }
            let change = try await services.agentChangeStore.confirm(
                id: prepared.id,
                observedAfterFingerprint: commit.document.fingerprint
            )
            return AgentNoteCreationResult(
                change: change,
                noteID: reservedIdentity,
                role: role,
                relativePath: relativePath,
                fingerprint: commit.document.fingerprint
            )
        } catch {
            let uncertain = Self.isUncertainAgentMutationError(error)
            try await finishFailedAgentMutation(
                changeID: prepared.id,
                error: error
            )
            if uncertain {
                throw AgentCollaborationError.changeConfirmationUncertain(
                    prepared.id
                )
            }
            if let creationError = error as? DocumentCreationError,
               case .portableIdentityAlreadyExists = creationError {
                throw AgentCollaborationError.pathOccupied(relativePath)
            }
            throw Self.agentCollaborationError(error)
        }
    }

    private func prepareAgentNoteUpdate(
        noteID: UUID,
        expectedFingerprint: DocumentFingerprint,
        update: AgentNoteUpdate
    ) async throws -> (target: WorkspaceNoteSnapshot, current: NoteDocument, changeSet: NoteChangeSet, intended: NoteDocument) {
        try Task.checkCancellation()
        let target = try await currentAgentNote(noteID: noteID)
        let current = try await loadDocument(target.id)
        guard current.fingerprint == expectedFingerprint else {
            throw AgentCollaborationError.staleRevision(
                expected: expectedFingerprint,
                current: current.fingerprint
            )
        }
        let changeSet: NoteChangeSet
        switch update {
        case .body(let content):
            try Self.validateAgentContent(content)
            changeSet = .body(content)
        case .source(let content):
            try Self.validateAgentContent(content)
            changeSet = .source(content)
        case .edits(let edits):
            changeSet = .source(try AgentSourceEdit.applying(edits, to: current.sourceBytes))
        }
        let intendedSource: String
        do {
            intendedSource = try current.applying(changeSet, timestampKey: nil)
        } catch VaultRepositoryError.invalidFrontmatter(let message) {
            throw AgentCollaborationError.invalidRequest(message)
        }
        try Self.validateAgentContent(intendedSource)
        let intended = NoteDocument(
            relativePath: current.relativePath,
            rawContent: intendedSource
        )
        guard intended.frontmatterState != .malformed else {
            throw AgentCollaborationError.invalidRequest(
                intended.validationWarnings.first
                    ?? "The proposed Markdown source has malformed YAML frontmatter."
            )
        }
        guard intended.fingerprint != current.fingerprint else {
            throw AgentCollaborationError.noChanges
        }
        return (target, current, changeSet, intended)
    }

    func previewAgentNoteUpdate(
        noteID: UUID, expectedFingerprint: DocumentFingerprint,
        update: AgentNoteUpdate
    ) async throws -> AgentNoteUpdatePreview {
        let prepared = try await prepareAgentNoteUpdate(
            noteID: noteID, expectedFingerprint: expectedFingerprint, update: update)
        let comparison = try ExactSourceComparisonBuilder.build(
            startingData: prepared.current.sourceBytes, endingData: prepared.intended.sourceBytes,
            startingRevision: prepared.current.fingerprint, endingRevision: prepared.intended.fingerprint)
        return .init(noteID: noteID, relativePath: prepared.current.relativePath, comparison: comparison)
    }

    func updateAgentNote(
        noteID: UUID, expectedFingerprint: DocumentFingerprint,
        update: AgentNoteUpdate
    ) async throws -> AgentNoteUpdateResult {
        let (target, current, changeSet, intended) = try await prepareAgentNoteUpdate(
            noteID: noteID, expectedFingerprint: expectedFingerprint, update: update)
        try Task.checkCancellation()
        let prepared = try await services.agentChangeStore.prepare(
            operation: .update,
            noteID: noteID,
            role: target.vaultRole,
            originalRelativePath: target.id.relativePath,
            finalRelativePath: target.id.relativePath,
            beforeData: current.sourceBytes,
            afterData: intended.sourceBytes
        )
        do {
            try Task.checkCancellation()
            let outcome = try await saveDocument(
                target.id,
                changeSet: changeSet,
                expectedRevision: expectedFingerprint
            )
            let saved = outcome.committedValue.document
            guard saved.sourceBytes == intended.sourceBytes else {
                _ = try? await services.agentChangeStore.markOutcomeUncertain(
                    id: prepared.id
                )
                throw AgentCollaborationError.changeConfirmationUncertain(
                    prepared.id
                )
            }
            let change = try await services.agentChangeStore.confirm(
                id: prepared.id,
                observedAfterFingerprint: saved.fingerprint
            )
            return AgentNoteUpdateResult(
                change: change,
                noteID: noteID,
                relativePath: target.id.relativePath,
                beforeFingerprint: current.fingerprint,
                afterFingerprint: saved.fingerprint,
                readbackVerified: true
            )
        } catch {
            let uncertain = Self.isUncertainAgentMutationError(error)
            try await finishFailedAgentMutation(
                changeID: prepared.id,
                error: error
            )
            if uncertain {
                throw AgentCollaborationError.changeConfirmationUncertain(
                    prepared.id
                )
            }
            throw Self.agentCollaborationError(error)
        }
    }

    func trashAgentNote(
        noteID: UUID,
        expectedFingerprint: DocumentFingerprint
    ) async throws -> AgentNoteTrashResult {
        let target = try await currentAgentNote(noteID: noteID)
        let current = try await loadDocument(target.id)
        guard current.fingerprint == expectedFingerprint else {
            throw AgentCollaborationError.staleRevision(
                expected: expectedFingerprint,
                current: current.fingerprint
            )
        }
        let prepared = try await services.agentChangeStore.prepare(
            operation: .trash,
            noteID: noteID,
            role: target.vaultRole,
            originalRelativePath: target.id.relativePath,
            finalRelativePath: nil,
            beforeData: current.sourceBytes,
            afterData: nil
        )
        do {
            let mutationTarget = NoteMutationTarget(
                documentID: target.id,
                stableNoteID: noteID,
                revision: current.fingerprint
            )
            let preview = try await prepareSystemTrash(mutationTarget)
            let outcome = try await moveToSystemTrash(preview)
            let commit = outcome.committedValue
            guard commit.noteIDs == [noteID],
                  commit.originalRelativePaths == [target.id.relativePath] else {
                _ = try? await services.agentChangeStore.markOutcomeUncertain(
                    id: prepared.id
                )
                throw AgentCollaborationError.changeConfirmationUncertain(
                    prepared.id
                )
            }
            let change = try await services.agentChangeStore.confirm(
                id: prepared.id,
                observedAfterFingerprint: nil
            )
            return AgentNoteTrashResult(
                change: change,
                noteID: noteID,
                originalRelativePath: target.id.relativePath
            )
        } catch {
            let uncertain = Self.isUncertainAgentMutationError(error)
            try await finishFailedAgentMutation(
                changeID: prepared.id,
                error: error
            )
            if uncertain {
                throw AgentCollaborationError.changeConfirmationUncertain(
                    prepared.id
                )
            }
            throw Self.agentCollaborationError(error)
        }
    }

    func agentChanges() async throws -> [AgentChange] {
        try requireActive()
        return try await services.agentChangeStore.changes()
    }

    func reviewAgentChange(id: UUID) async throws -> AgentChangeReview {
        try requireActive()
        let evidence = try await services.agentChangeStore.evidence(id: id)
        let change = evidence.change
        if change.operation == .move { return try await reviewAgentMove(evidence) }
        let comparison = change.operation == .update
            ? try evidence.exactUpdateComparison()
            : nil

        guard let endingFingerprint = change.afterFingerprint else {
            return AgentChangeReview(
                change: change,
                comparison: comparison,
                currentCreatedSource: nil,
                endingRevisionState: nil
            )
        }

        let refreshed = try await refresh()
        let matches = refreshed.vaults.flatMap(\.documents).filter {
            $0.stableIdentity.resolvedID == change.noteID
        }
        guard matches.count == 1 else {
            return AgentChangeReview(
                change: change,
                comparison: comparison,
                currentCreatedSource: nil,
                endingRevisionState: .unavailable
            )
        }
        let current = try await loadDocument(matches[0].id)
        let revisionState: AgentChangeEndingRevisionState =
            current.fingerprint == endingFingerprint ? .current : .earlierRevision
        return AgentChangeReview(
            change: change,
            comparison: comparison,
            currentCreatedSource: change.operation == .create && revisionState == .current
                ? current.rawContent
                : nil,
            endingRevisionState: revisionState
        )
    }

    private func prepareAgentChangeUndo(
        id: UUID, expectedAfterFingerprint: DocumentFingerprint
    ) async throws -> (change: AgentChange, target: WorkspaceNoteSnapshot, current: NoteDocument, beforeData: Data) {
        try Task.checkCancellation()
        let change = try await services.agentChangeStore.change(id: id)
        guard change.operation == .update, change.state == .confirmed,
              change.afterFingerprint == expectedAfterFingerprint else {
            throw AgentChangeError.undoUnavailable(id)
        }
        let target = try await currentAgentNote(noteID: change.noteID)
        let current = try await loadDocument(target.id)
        guard current.fingerprint == expectedAfterFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedAfterFingerprint, current: current.fingerprint)
        }
        let beforeData = try await services.agentChangeStore.beforeDataForUndo(id: id, expectedAfterFingerprint: expectedAfterFingerprint)
        return (change, target, current, beforeData)
    }

    func previewAgentChangeUndo(id: UUID, expectedAfterFingerprint: DocumentFingerprint) async throws -> AgentNoteUpdatePreview {
        if try await services.agentChangeStore.change(id: id).operation == .move {
            return try await previewAgentMoveUndo(id: id, expectedAfterFingerprint: expectedAfterFingerprint)
        }
        let prepared = try await prepareAgentChangeUndo(id: id, expectedAfterFingerprint: expectedAfterFingerprint)
        let comparison = try ExactSourceComparisonBuilder.build(
            startingData: prepared.current.sourceBytes, endingData: prepared.beforeData,
            startingRevision: prepared.current.fingerprint, endingRevision: DocumentFingerprint(data: prepared.beforeData))
        return .init(noteID: prepared.change.noteID, relativePath: prepared.target.id.relativePath, comparison: comparison)
    }

    func undoAgentChange(id: UUID, expectedAfterFingerprint: DocumentFingerprint) async throws -> AgentChangeUndoResult {
        if try await services.agentChangeStore.change(id: id).operation == .move {
            return try await undoAgentMove(id: id, expectedAfterFingerprint: expectedAfterFingerprint)
        }
        let (change, target, _, beforeData) = try await prepareAgentChangeUndo(id: id, expectedAfterFingerprint: expectedAfterFingerprint)
        guard let beforeSource = NoteDocument.decodeUTF8PreservingBOM(beforeData) else { throw AgentChangeError.invalid(id) }
        try Task.checkCancellation()
        do {
            let outcome = try await saveDocument(target.id, changeSet: .exactContent(beforeSource), expectedRevision: expectedAfterFingerprint)
            let restored = outcome.committedValue.document.fingerprint
            guard restored == change.beforeFingerprint else { throw AgentCollaborationError.changeConfirmationUncertain(id) }
            _ = try await services.agentChangeStore.markUndone(id: id, restoredFingerprint: restored)
            return AgentChangeUndoResult(changeID: id, noteID: change.noteID, restoredFingerprint: restored)
        } catch {
            if Self.isUncertainAgentMutationError(error) { throw AgentCollaborationError.changeConfirmationUncertain(id) }
            throw Self.agentCollaborationError(error)
        }
    }

    func currentAgentNote(
        noteID: UUID
    ) async throws -> WorkspaceNoteSnapshot {
        let refreshed = try await refresh()
        let matches = refreshed.vaults.flatMap(\.documents).filter {
            $0.stableIdentity.resolvedID == noteID
        }
        guard !matches.isEmpty else {
            throw AgentCollaborationError.noteNotFound(noteID)
        }
        guard matches.count == 1 else {
            throw AgentCollaborationError.noteAmbiguous(noteID)
        }
        guard Self.isAgentWritableRole(matches[0].vaultRole) else {
            throw AgentCollaborationError.invalidRequest(
                "Agent collaboration can mutate only Analyses, Topics, or Works."
            )
        }
        return matches[0]
    }

    func finishFailedAgentMutation(
        changeID: UUID,
        error: Error
    ) async throws {
        if Self.isUncertainAgentMutationError(error) {
            _ = try? await services.agentChangeStore.markOutcomeUncertain(
                id: changeID
            )
        } else {
            try? await services.agentChangeStore.discardPrepared(id: changeID)
        }
    }

    private static func validateAgentContent(_ content: String) throws {
        guard content.utf8.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount,
              !content.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw AgentCollaborationError.invalidRequest(
                "The proposed content is invalid or exceeds the supported UTF-8 size."
            )
        }
    }

    private static func isAgentWritableRole(_ role: VaultRole) -> Bool {
        switch role {
        case .sourceCorpus, .topicKnowledge, .draftProject: true
        case .other: false
        }
    }

    private static func isUncertainAgentMutationError(_ error: Error) -> Bool {
        if error is AgentChangeError {
            // Every store error reaching this helper occurred after the
            // source owner was invoked. Preserve the prepared evidence until
            // exact reconciliation proves whether the source crossed commit.
            return true
        }
        if error is ManagedCreationFinalVerificationError
            || error is CreatedDocumentIdentityRollbackError {
            return true
        }
        if let error = error as? VaultRepositoryError {
            switch error {
            case .commitUncertain, .readbackMismatch, .recoveryRequired:
                return true
            default:
                return false
            }
        }
        if let error = error as? TriptychTransactionError {
            switch error {
            case .recoveryRequired, .recoveryPersistenceFailed:
                return true
            default:
                return false
            }
        }
        if let error = error as? ScholiumApplicationError,
           case .operationCommitUncertain = error {
            return true
        }
        if let error = error as? AgentCollaborationError,
           case .changeConfirmationUncertain = error {
            return true
        }
        return false
    }

    private static func agentCollaborationError(_ error: Error) -> Error {
        if let error = error as? AgentCollaborationError { return error }
        if let error = error as? VaultRepositoryError {
            switch error {
            case .conflict(let expected, let current):
                return AgentCollaborationError.staleRevision(
                    expected: expected,
                    current: current
                )
            case .fileAlreadyExists(let path),
                 .pathCollision(_, let path):
                return AgentCollaborationError.pathOccupied(path)
            default:
                return error
            }
        }
        if isUncertainAgentMutationError(error) {
            return error
        }
        return error
    }
}
