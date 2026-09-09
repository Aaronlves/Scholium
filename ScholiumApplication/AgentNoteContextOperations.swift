import Foundation
import ScholiumContracts

extension AgentCollaborationOperations {
    public func currentNoteContext(noteID: UUID, expectedFingerprint: DocumentFingerprint) async throws -> AgentNoteContext {
        let handle = try await reference.requireHandle()
        let source = try await currentNoteSource(noteID: noteID)
        guard source.fingerprint == expectedFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedFingerprint, current: source.fingerprint)
        }
        let metadata = try await handle.services.controlStore.noteMetadata(noteID: noteID)
        let bindings = source.role == .sourceCorpus ? try await handle.zoteroBindingsSnapshot() : nil
        let attachments = try await handle.agentAttachments(noteID: noteID)
        let currentMetadata = try await handle.services.controlStore.noteMetadata(noteID: noteID)
        let currentBindings = source.role == .sourceCorpus ? try await handle.zoteroBindingsSnapshot() : nil
        let currentAttachments = try await handle.agentAttachments(noteID: noteID)
        let currentSource = try await currentNoteSource(noteID: noteID)
        try Task.checkCancellation()
        guard currentSource.fingerprint == expectedFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedFingerprint, current: currentSource.fingerprint)
        }
        guard currentSource.note == source.note, metadata == currentMetadata,
              bindings == currentBindings,
              attachments.noteFingerprint == expectedFingerprint,
              currentAttachments.noteFingerprint == expectedFingerprint,
              attachments.attachments == currentAttachments.attachments else {
            throw ScholiumMCPFailure(code: .conflict,
                message: "This Note's saved details or material relationships changed while being read.",
                recovery: "Read the Note and its context again before using those relationships.")
        }
        return .init(note: source.note, metadata: metadata, zoteroBinding: bindings?.binding(for: noteID),
                     zoteroBindingsRevision: bindings?.revision, attachments: attachments)
    }
}
