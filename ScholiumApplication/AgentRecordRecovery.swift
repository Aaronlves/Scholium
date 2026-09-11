import Foundation
import ScholiumContracts

extension WorkspaceHandle {
    func reviewAgentRecord(_ evidence: AgentChangeEvidence) async throws -> AgentChangeReview {
        let change = evidence.change
        let comparison = try evidence.exactUpdateComparison()
        let state: AgentChangeEndingRevisionState
        do {
            let target = try await currentAgentNote(noteID: change.noteID)
            guard target.vaultRole == change.role else { throw AgentChangeError.invalid(change.id) }
            let current = try await recordBytes(
                operation: change.operation, noteID: change.noteID,
                before: evidence.beforeData!, after: evidence.afterData!)
            state = DocumentFingerprint(data: current) == change.afterFingerprint ? .current : .earlierRevision
        } catch { state = .unavailable }
        return .init(change: change, comparison: comparison, currentCreatedSource: nil, endingRevisionState: state)
    }

    func prepareAgentRecordUndo(id: UUID, expected: DocumentFingerprint) async throws -> (AgentChangeEvidence, WorkspaceNoteSnapshot) {
        let evidence = try await services.agentChangeStore.evidence(id: id)
        let change = evidence.change
        guard change.operation.isRecordMutation, change.state == .confirmed, change.afterFingerprint == expected,
            let before = evidence.beforeData, let after = evidence.afterData
        else { throw AgentChangeError.undoUnavailable(id) }
        let target = try await currentAgentNote(noteID: change.noteID)
        guard target.vaultRole == change.role else { throw AgentChangeError.invalid(id) }
        let current = try await recordBytes(operation: change.operation, noteID: change.noteID, before: before, after: after)
        guard current == after else { throw AgentCollaborationError.staleRevision(expected: expected, current: .init(data: current)) }
        return (evidence, target)
    }

    func previewAgentRecordUndo(id: UUID, expected: DocumentFingerprint) async throws -> AgentNoteUpdatePreview {
        let (evidence, target) = try await prepareAgentRecordUndo(id: id, expected: expected)
        return try .init(
            noteID: evidence.change.noteID, relativePath: target.id.relativePath,
            comparison: ExactSourceComparisonBuilder.build(
                startingData: evidence.afterData!, endingData: evidence.beforeData!,
                startingRevision: evidence.change.afterFingerprint!, endingRevision: evidence.change.beforeFingerprint!), operation: evidence.change.operation)
    }

    func undoAgentRecord(id: UUID, expected: DocumentFingerprint) async throws -> AgentChangeUndoResult {
        let (evidence, target) = try await prepareAgentRecordUndo(id: id, expected: expected)
        let lease = try await beginSourceMutation()
        defer { endSourceMutation(lease) }
        let document = try await loadDocument(target.id)
        guard try await resolvedIdentity(for: target.id, expectedRevision: document.fingerprint).id == evidence.change.noteID else {
            throw AgentChangeError.undoUnavailable(id)
        }
        guard
            try await recordBytes(
                operation: evidence.change.operation, noteID: evidence.change.noteID,
                before: evidence.beforeData!, after: evidence.afterData!) == evidence.afterData
        else { throw AgentChangeError.undoUnavailable(id) }
        let change = evidence.change
        try Task.checkCancellation()
        do {
            if change.operation == .metadata {
                let before = try JSONDecoder().decode(NoteMetadataRecord?.self, from: evidence.beforeData!)
                let current = try await services.controlStore.noteMetadata(noteID: change.noteID)
                guard try AgentRecordChange.metadata(current?.record) == evidence.afterData else { throw NoteMetadataError.revisionConflict(change.noteID) }
                if let before {
                    _ = try await services.controlStore.saveNoteMetadata(noteID: change.noteID, fields: before.fields, expectedRevision: current?.revision)
                } else if let current {
                    try await services.controlStore.removeNoteMetadata(current)
                }
                noteRecordDidChange(vaultID: target.id.vaultID)
            } else {
                try await applyAttachmentRecord(before: evidence.afterData!, after: evidence.beforeData!)
                noteRecordDidChange(vaultID: target.id.vaultID)
            }
            let restored = try await recordBytes(operation: change.operation, noteID: change.noteID, before: evidence.beforeData!, after: evidence.afterData!)
            guard restored == evidence.beforeData else { throw AgentCollaborationError.changeConfirmationUncertain(id) }
            _ = try await services.agentChangeStore.markUndone(id: id, restoredFingerprint: .init(data: restored))
            return .init(changeID: id, noteID: change.noteID, restoredFingerprint: .init(data: restored))
        } catch {
            // Keep the confirmed receipt and exact preimages; the current read
            // decides eligibility on retry rather than assuming rollback.
            let current = try? await recordBytes(operation: change.operation, noteID: change.noteID, before: evidence.beforeData!, after: evidence.afterData!)
            if current == evidence.afterData { throw error }
            throw AgentCollaborationError.changeConfirmationUncertain(id)
        }
    }
}
