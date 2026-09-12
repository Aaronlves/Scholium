import Foundation
import ScholiumContracts

extension AgentCollaborationOperations {
    public func currentNoteContext(noteID: UUID, expectedFingerprint: DocumentFingerprint) async throws -> AgentNoteContext {
        let handle = try await reference.requireHandle()
        let source = try await currentNoteSource(noteID: noteID)
        guard source.fingerprint == expectedFingerprint else {
            throw AgentCollaborationError.staleRevision(expected: expectedFingerprint, current: source.fingerprint)
        }
        let attachments = try await handle.agentAttachments(noteID: noteID)
        let current = try await currentNoteSource(noteID: noteID)
        guard current.note == source.note, current.fingerprint == expectedFingerprint,
            attachments.noteFingerprint == expectedFingerprint
        else {
            throw AgentCollaborationError.staleRevision(expected: expectedFingerprint, current: current.fingerprint)
        }
        return AgentNoteContext(note: source.note, attachments: attachments)
    }
}
