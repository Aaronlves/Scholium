import Foundation
import ScholiumContracts
import ScholiumCore

extension AgentCollaborationOperations {
    public func previewMetadata(noteID: UUID, expectedSource: DocumentFingerprint, update: AgentMetadataUpdate) async throws -> AgentNoteUpdatePreview {
        let handle = try await reference.requireHandle()
        return try await handle.metadataPlan(noteID: noteID, expectedSource: expectedSource, update: update).preview()
    }

    public func updateMetadata(noteID: UUID, expectedSource: DocumentFingerprint, update: AgentMetadataUpdate) async throws -> AgentNoteUpdateResult {
        let handle = try await reference.requireHandle()
        let plan = try await handle.metadataPlan(noteID: noteID, expectedSource: expectedSource, update: update)
        let lease = try await handle.beginSourceMutation()
        do {
            let result = try await handle.commitAgentRecord(plan)
            await handle.endSourceMutation(lease)
            return result
        } catch { await handle.endSourceMutation(lease); throw error }
    }

    public func previewAttachment(noteID: UUID, expectedSource: DocumentFingerprint, update: AgentAttachmentUpdate) async throws -> AgentNoteUpdatePreview {
        let handle = try await reference.requireHandle()
        return try await handle.attachmentPlan(noteID: noteID, expectedSource: expectedSource, update: update).preview()
    }

    public func updateAttachment(noteID: UUID, expectedSource: DocumentFingerprint, update: AgentAttachmentUpdate) async throws -> AgentNoteUpdateResult {
        let handle = try await reference.requireHandle()
        let plan = try await handle.attachmentPlan(noteID: noteID, expectedSource: expectedSource, update: update)
        let lease = try await handle.beginSourceMutation()
        do {
            let result = try await handle.commitAgentRecord(plan)
            await handle.endSourceMutation(lease)
            return result
        } catch { await handle.endSourceMutation(lease); throw error }
    }
}

struct AgentRecordPlan {
    let target: WorkspaceNoteSnapshot
    let noteID: UUID
    let operation: AgentChangeOperation
    let before: Data
    let after: Data
    let metadataRevision: DocumentFingerprint?
    var copy: (bytes: Data, filename: String, id: UUID)?
    var attachmentListingFingerprint: DocumentFingerprint?
    var sourceListing: (noteID: UUID, target: WorkspaceNoteSnapshot, fingerprint: DocumentFingerprint, attachmentID: UUID, fileFingerprint: DocumentFingerprint)?

    func preview() throws -> AgentNoteUpdatePreview {
        guard before.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount,
              after.count <= ScholiumMCPContract.maximumDocumentUTF8ByteCount else { throw AgentChangeError.sourceTooLarge }
        guard before != after else {
            throw ScholiumMCPFailure(code: .noChanges, message: "These saved details are unchanged.", recovery: "No write is needed.")
        }
        return try .init(noteID: noteID, relativePath: target.id.relativePath,
            comparison: ExactSourceComparisonBuilder.build(startingData: before, endingData: after,
                startingRevision: .init(data: before), endingRevision: .init(data: after)), operation: operation)
    }
}

extension WorkspaceHandle {
    func recordTarget(noteID: UUID, expectedSource: DocumentFingerprint) async throws -> WorkspaceNoteSnapshot {
        let target = try await currentAgentNote(noteID: noteID)
        let source = try await loadDocument(target.id)
        guard source.fingerprint == expectedSource else { throw AgentCollaborationError.staleRevision(expected: expectedSource, current: source.fingerprint) }
        guard try await resolvedIdentity(for: target.id, expectedRevision: expectedSource).id == noteID else { throw AgentCollaborationError.noteAmbiguous(noteID) }
        return target
    }

    func metadataPlan(noteID: UUID, expectedSource: DocumentFingerprint, update: AgentMetadataUpdate) async throws -> AgentRecordPlan {
        let target = try await recordTarget(noteID: noteID, expectedSource: expectedSource)
        let current = try await services.controlStore.noteMetadata(noteID: noteID)
        guard current?.revision == update.expectedRevision else { throw NoteMetadataError.revisionConflict(noteID) }
        guard update.set.count + update.remove.count <= 128,
              Set(update.remove).count == update.remove.count,
              Set(update.set.keys).isDisjoint(with: update.remove) else {
            throw AgentCollaborationError.invalidRequest("Use at most 128 distinct field edits; a field cannot be set and removed together.")
        }
        var fields = current?.record.fields ?? [:]
        for key in update.remove { fields[key] = nil }
        for (key, value) in update.set { fields[key] = value }
        guard fields != (current?.record.fields ?? [:]) else { throw ScholiumMCPFailure(code: .noChanges, message: "These Metadata values are unchanged.", recovery: "No write is needed.") }
        try await validateMetadataFields(fields, role: target.vaultRole, current: current)
        let plan = try AgentRecordPlan(target: target, noteID: noteID, operation: .metadata,
            before: AgentRecordChange.metadata(current?.record), after: AgentRecordChange.metadata(.init(noteID: noteID, fields: fields)),
            metadataRevision: current?.revision)
        _ = try plan.preview()
        return plan
    }

    func commitAgentRecord(_ plan: AgentRecordPlan) async throws -> AgentNoteUpdateResult {
        _ = try plan.preview()
        let document = try await loadDocument(plan.target.id)
        guard document.fingerprint == plan.target.fingerprint,
              try await resolvedIdentity(for: plan.target.id, expectedRevision: document.fingerprint).id == plan.noteID else { throw AgentCollaborationError.staleRevision(expected: plan.target.fingerprint, current: document.fingerprint) }
        if let expected = plan.attachmentListingFingerprint {
            let listing = try await agentAttachments(noteID: plan.noteID, currentNote: plan.target)
            guard try listing.fingerprint(triptychID: id, noteID: plan.noteID) == expected else { throw DocumentAttachmentError.catalogConflict }
        }
        if let source = plan.sourceListing {
            let listing = try await agentAttachments(noteID: source.noteID, currentNote: source.target)
            guard try listing.fingerprint(triptychID: id, noteID: source.noteID) == source.fingerprint else { throw DocumentAttachmentError.catalogConflict }
            _ = try await agentDocumentBytes(noteID: source.noteID, target: source.target.id,
                attachmentID: source.attachmentID, expected: source.fileFingerprint)
        }
        guard try await recordBytes(operation: plan.operation, noteID: plan.noteID, before: plan.before, after: plan.after) == plan.before else { throw DocumentAttachmentError.catalogConflict }
        let receipt = try await services.agentChangeStore.prepare(operation: plan.operation, noteID: plan.noteID,
            role: plan.target.vaultRole, originalRelativePath: plan.target.id.relativePath, finalRelativePath: plan.target.id.relativePath,
            beforeData: plan.before, afterData: plan.after)
        var copied: PreparedVaultDocumentFile?
        var didWrite = false
        var copyAttempted = false
        do {
            try Task.checkCancellation()
            // Copy only the previously verified immutable bytes; no caller path is accepted.
            if let copy = plan.copy {
                let store = VaultAttachmentStore(vaultURL: try await repository(vaultID: plan.target.id.vaultID).vaultURL)
                let path = try AttachmentRelativePath("Attachments/\(copy.id.uuidString.lowercased())/\(copy.filename)")
                if let _ = try await store.documentURLIfAvailable(relativePath: path) {
                    guard try await store.readContent(relativePath: path, maximumByteCount: 20 * 1_024 * 1_024) == copy.bytes else { throw DocumentAttachmentError.catalogConflict }
                } else {
                    copyAttempted = true
                    copied = try await store.copyDocumentSnapshot(copy.bytes, filename: copy.filename, attachmentID: copy.id)
                }
            }
            try Task.checkCancellation()
            let currentSource = try await loadDocument(plan.target.id)
            guard currentSource.fingerprint == plan.target.fingerprint,
                  try await resolvedIdentity(for: plan.target.id, expectedRevision: currentSource.fingerprint).id == plan.noteID else {
                throw AgentCollaborationError.staleRevision(expected: plan.target.fingerprint, current: currentSource.fingerprint)
            }
            if plan.operation == .metadata {
                let after = try JSONDecoder().decode(NoteMetadataRecord.self, from: plan.after)
                _ = try await commitNoteMetadata(plan.target.id, fields: after.fields, expectedRevision: plan.metadataRevision, agentTarget: (plan.noteID, plan.target.fingerprint))
            } else {
                try await applyAttachmentRecord(before: plan.before, after: plan.after)
            }
            didWrite = true
            if plan.operation == .attachment { noteRecordDidChange(vaultID: plan.target.id.vaultID) }
            let current = try await recordBytes(operation: plan.operation, noteID: plan.noteID, before: plan.before, after: plan.after)
            guard current == plan.after else { throw AgentCollaborationError.changeConfirmationUncertain(receipt.id) }
            let confirmed = try await services.agentChangeStore.confirm(id: receipt.id, observedAfterFingerprint: .init(data: current))
            return .init(change: confirmed, noteID: plan.noteID, relativePath: plan.target.id.relativePath,
                beforeFingerprint: .init(data: plan.before), afterFingerprint: .init(data: current), readbackVerified: true)
        } catch {
            let current = try? await recordBytes(operation: plan.operation, noteID: plan.noteID, before: plan.before, after: plan.after)
            var unconfirmedCopyRemains = false
            if copyAttempted, copied == nil, let copy = plan.copy {
                // A failed file preparation may have crossed its own commit.
                // Do not discard evidence merely because the relationship stayed unchanged.
                do {
                    let store = VaultAttachmentStore(vaultURL: try await repository(vaultID: plan.target.id.vaultID).vaultURL)
                    let path = try AttachmentRelativePath("Attachments/\(copy.id.uuidString.lowercased())/\(copy.filename)")
                    unconfirmedCopyRemains = try await store.documentURLIfAvailable(relativePath: path) != nil
                } catch { unconfirmedCopyRemains = true }
            }
            if !didWrite, !unconfirmedCopyRemains, current == plan.before {
                if let path = copied?.copiedRelativePath, let fingerprint = copied?.copiedFileFingerprint {
                    let store = VaultAttachmentStore(vaultURL: try await repository(vaultID: plan.target.id.vaultID).vaultURL)
                    do { try await store.removeCopiedDocumentIfExact(relativePath: path, expectedFingerprint: fingerprint) }
                    catch {
                        _ = try? await services.agentChangeStore.markOutcomeUncertain(id: receipt.id)
                        throw AgentCollaborationError.changeConfirmationUncertain(receipt.id)
                    }
                }
                try await services.agentChangeStore.discardPrepared(id: receipt.id)
                throw error
            }
            _ = try? await services.agentChangeStore.markOutcomeUncertain(id: receipt.id)
            throw AgentCollaborationError.changeConfirmationUncertain(receipt.id)
        }
    }

    func applyAttachmentRecord(before: Data, after: Data) async throws {
        let old = try JSONDecoder().decode(DocumentAttachmentRecord?.self, from: before)
        let new = try JSONDecoder().decode(DocumentAttachmentRecord?.self, from: after)
        if let old, let new {
            try await services.controlStore.replaceDocumentAttachment(old, with: new)
        } else if let new {
            let result = try await services.controlStore.registerDocumentAttachment(noteID: new.noteID, vaultID: new.vaultID,
                location: new.location, preferredID: new.id)
            guard result.record == new else { throw DocumentAttachmentError.catalogConflict }
        } else if let old {
            try await services.controlStore.removeDocumentAttachment(old)
        } else { throw DocumentAttachmentError.catalogConflict }
    }

    func recordBytes(operation: AgentChangeOperation, noteID: UUID, before: Data, after: Data) async throws -> Data {
        if operation == .metadata { return try await AgentRecordChange.metadata(services.controlStore.noteMetadata(noteID: noteID)?.record) }
        let old = try JSONDecoder().decode(DocumentAttachmentRecord?.self, from: before)
        let new = try JSONDecoder().decode(DocumentAttachmentRecord?.self, from: after)
        guard let id = (new ?? old)?.id else { throw AgentChangeError.invalid(noteID) }
        return try await AgentRecordChange.attachment(services.controlStore.documentAttachmentRecords(noteID: noteID).first { $0.id == id })
    }
}
