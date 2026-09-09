import Foundation
import ScholiumContracts
import ScholiumCore

extension WorkspaceHandle {
    func attachmentPlan(noteID: UUID, expectedSource: DocumentFingerprint, update: AgentAttachmentUpdate) async throws -> AgentRecordPlan {
        let target = try await recordTarget(noteID: noteID, expectedSource: expectedSource)
        let listing = try await agentAttachments(noteID: noteID)
        let fingerprint = try listing.fingerprint(triptychID: id, noteID: noteID)
        guard fingerprint == update.listingFingerprint else { throw AgentCollaborationError.staleRevision(expected: update.listingFingerprint, current: fingerprint) }
        let records = try await services.controlStore.documentAttachmentRecords()
        let old = records.first { $0.id == update.attachmentID }
        switch update.action {
        case .add:
            guard try await !services.controlStore.attachmentRecords().contains(where: { $0.id == update.attachmentID }), old == nil, !listing.attachments.contains(where: { $0.id == update.attachmentID }) else { throw DocumentAttachmentError.catalogConflict }
        case .replace, .remove:
            guard let old, old.noteID == noteID, old.vaultID == target.id.vaultID else { throw DocumentAttachmentError.catalogConflict }
        }
        var new: DocumentAttachmentRecord?
        var copy: (bytes: Data, filename: String, id: UUID)?
        var sourceProof: (noteID: UUID, target: WorkspaceNoteSnapshot, fingerprint: DocumentFingerprint, attachmentID: UUID, fileFingerprint: DocumentFingerprint)?
        if update.action != .remove {
            guard let source = update.source else { throw AgentCollaborationError.invalidRequest("Select one existing document attachment as the material source.") }
            let sourceListing = try await agentAttachments(noteID: source.noteID)
            let sourceFingerprint = try sourceListing.fingerprint(triptychID: id, noteID: source.noteID)
            guard sourceFingerprint == source.listingFingerprint else { throw AgentCollaborationError.staleRevision(expected: source.listingFingerprint, current: sourceFingerprint) }
            guard let original = records.first(where: { $0.id == source.attachmentID && $0.noteID == source.noteID }),
                  sourceListing.attachments.contains(where: { $0.id == original.id && $0.available && $0.relationship == .document && $0.location == original.location }) else {
                throw DocumentAttachmentError.unavailable(source.attachmentID.uuidString)
            }
            let sourceNote = try await currentAgentNote(noteID: source.noteID)
            sourceProof = (source.noteID, sourceNote, sourceFingerprint, source.attachmentID, source.fileFingerprint)
            let bytes = try await agentDocumentBytes(noteID: source.noteID, target: sourceNote.id,
                attachmentID: source.attachmentID, expected: source.fileFingerprint)
            let currentListing = try await agentAttachments(noteID: source.noteID)
            guard try currentListing.fingerprint(triptychID: id, noteID: source.noteID) == sourceFingerprint else { throw DocumentAttachmentError.catalogConflict }
            let location: AttachmentLocation
            if original.vaultID == target.id.vaultID, case .vaultRelative = original.location {
                location = original.location
            } else {
                location = .vaultRelative(try .init("Attachments/\(original.id.uuidString.lowercased())/\(original.filename)"))
                copy = (bytes, original.filename, original.id)
            }
            guard !records.contains(where: { $0.id != update.attachmentID && $0.noteID == noteID && $0.location == location }) else {
                throw ScholiumMCPFailure(code: .noChanges, message: "This material is already attached to the Note.", recovery: "Use the existing attachment.")
            }
            new = .init(id: update.attachmentID, noteID: noteID, vaultID: target.id.vaultID, location: location)
        } else if update.source != nil { throw AgentCollaborationError.invalidRequest("Removing a relationship accepts no replacement source.") }
        let plan = try AgentRecordPlan(target: target, noteID: noteID, operation: .attachment,
            before: AgentRecordChange.attachment(old), after: AgentRecordChange.attachment(new), metadataRevision: nil, copy: copy, attachmentListingFingerprint: update.listingFingerprint, sourceListing: sourceProof)
        _ = try plan.preview()
        return plan
    }
    func agentDocumentBytes(noteID: UUID, target: VaultQualifiedNoteID, attachmentID: UUID, expected: DocumentFingerprint) async throws -> Data {
        let lease = try await prepareDocumentAttachmentPreview(attachmentID: attachmentID,
            for: .init(noteID: noteID, vaultID: target.vaultID, relativePath: target.relativePath))
        do {
            let bytes = try await VaultAttachmentStore(vaultURL: URL(fileURLWithPath: "/")).readContent(
                relativePath: AttachmentRelativePath(String(lease.fileURL.path.dropFirst())), maximumByteCount: 20 * 1_024 * 1_024)
            guard DocumentFingerprint(data: bytes) == expected else { throw AgentCollaborationError.staleRevision(expected: expected, current: .init(data: bytes)) }
            await releaseDocumentAttachmentPreview(accessToken: lease.accessToken)
            return bytes
        } catch { await releaseDocumentAttachmentPreview(accessToken: lease.accessToken); throw error }
    }

}
