import Foundation
import ScholiumContracts
import ScholiumCore

extension AgentCollaborationOperations {
    public func attachments(noteID: UUID) async throws -> AgentAttachmentListing {
        let handle = try await reference.requireHandle()
        return try await handle.agentAttachments(noteID: noteID)
    }
    public func readAttachment(
        noteID: UUID, attachmentID: UUID, expectedNoteFingerprint: DocumentFingerprint,
        request: AgentAttachmentRead
    ) async throws -> AgentAttachmentContent {
        let handle = try await reference.requireHandle()
        do {
            return try await handle.readAgentAttachment(
                noteID: noteID, attachmentID: attachmentID,
                expectedNoteFingerprint: expectedNoteFingerprint, request: request)
        } catch let error as ScholiumMCPFailure { throw error } catch let error as AgentCollaborationError { throw error } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady, message: "The related attachment is missing, changed, unreadable or exceeds the 20 MiB read limit.",
                recovery: "Inspect its availability in the App and list attachments again. No file access prompt or source replacement was performed.")
        }
    }
}

extension WorkspaceHandle {
    func agentAttachments(noteID: UUID, currentNote: WorkspaceNoteSnapshot? = nil) async throws -> AgentAttachmentListing {
        let note: WorkspaceNoteSnapshot
        if let currentNote { note = currentNote } else { note = try await currentAgentNote(noteID: noteID) }
        let source = try await loadDocument(note.id)
        guard source.fingerprint == note.fingerprint else {
            throw AgentCollaborationError.staleRevision(expected: note.fingerprint, current: source.fingerprint)
        }
        let references = SourceResourceReferences.files(in: source.body, noteRelativePath: note.id.relativePath)
        let records = try await services.controlStore.attachmentRecords().filter { $0.vaultID == note.id.vaultID }
        let repository = try repository(vaultID: note.id.vaultID)
        let store = VaultAttachmentStore(vaultURL: await repository.vaultURL)
        var byID: [UUID: AgentAttachment] = [:]
        for reference in references {
            let id: UUID
            let location: AttachmentLocation
            let available: Bool
            if let path = reference.relativePath {
                id =
                    records.first { $0.location == .vaultRelative(path) }?.id
                    ?? SourceResourceReferences.derivedID(vaultID: note.id.vaultID, path: path.rawValue)
                location = .vaultRelative(path)
                available = (try? await store.documentURLIfAvailable(relativePath: path)) != nil
            } else if let path = reference.absolutePath {
                let filename = URL(fileURLWithPath: path).lastPathComponent
                location = .external(try ExternalAttachmentReference(filename: filename))
                let registeredID = try await services.indexedAttachmentAccessStore.attachmentID(forAbsolutePath: path)
                if let registeredID, records.contains(where: { $0.id == registeredID && $0.location == location }) {
                    id = registeredID
                    available = try await services.indexedAttachmentAccessStore.isAvailable(attachmentID: id, expectedFilename: filename)
                } else {
                    id = SourceResourceReferences.derivedID(vaultID: note.id.vaultID, path: path)
                    available = false
                }
            } else {
                continue
            }
            byID[id] = AgentAttachment(id: id, relationship: reference.isImage ? .authoredImage : .document, location: location, available: available)
        }
        let attachments = Array(byID.values)
        guard Set(attachments.map(\.id)).count == attachments.count else {
            throw AgentCollaborationError.invalidRequest("Attachment identities are ambiguous in the current catalog.")
        }
        return .init(noteFingerprint: source.fingerprint, attachments: attachments.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    func readAgentAttachment(
        noteID: UUID, attachmentID: UUID, expectedNoteFingerprint: DocumentFingerprint,
        request: AgentAttachmentRead
    ) async throws -> AgentAttachmentContent {
        let listing = try await agentAttachments(noteID: noteID)
        guard listing.noteFingerprint == expectedNoteFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedNoteFingerprint, current: listing.noteFingerprint)
        }
        guard let attachment = listing.attachments.first(where: { $0.id == attachmentID }), attachment.available else {
            throw ScholiumMCPFailure(
                code: .notFound, message: "The attachment relationship or its read access is unavailable.",
                recovery: "List the current Note attachments and restore access in the App if needed.")
        }
        let note = try await currentAgentNote(noteID: noteID)
        let bytes: Data
        switch attachment.location {
        case .vaultRelative(let path):
            let repository = try repository(vaultID: note.id.vaultID)
            bytes = try await VaultAttachmentStore(vaultURL: await repository.vaultURL).readContent(relativePath: path, maximumByteCount: 20 * 1_024 * 1_024)
        case .external(let reference):
            let access = try await services.indexedAttachmentAccessStore.beginAccess(
                attachmentID: attachmentID,
                expectedFilename: reference.filename
            )
            do {
                // The existing bookmark grants access; descriptor traversal proves the same exact path.
                bytes = try await VaultAttachmentStore(vaultURL: URL(fileURLWithPath: "/")).readContent(
                    relativePath: AttachmentRelativePath(String(access.url.path.dropFirst())), maximumByteCount: 20 * 1_024 * 1_024)
                await services.indexedAttachmentAccessStore.endAccess(access.token)
            } catch {
                await services.indexedAttachmentAccessStore.endAccess(access.token)
                throw error
            }
        }
        try Task.checkCancellation()
        let current = try await agentAttachments(noteID: noteID)
        guard current.noteFingerprint == expectedNoteFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedNoteFingerprint, current: current.noteFingerprint)
        }
        guard current.attachments.contains(attachment) else {
            throw AgentCollaborationError.invalidRequest("The attachment relationship changed during reading.")
        }
        return try AgentAttachmentContentReader.read(bytes, filename: attachment.filename, request: request)
    }
}
