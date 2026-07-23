import Foundation

public struct PermanentDeletionCommit: Hashable, Sendable {
    public let noteID: UUID
    public let vaultID: UUID
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    public let removedCritiqueDocumentPath: String?
    public let removedDialogueIDs: [UUID]
    public let removedCritiqueAssociationIDs: [UUID]
    public let invalidatedCheckpointIDs: [UUID]

    public init(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        removedCritiqueDocumentPath: String? = nil,
        removedDialogueIDs: [UUID],
        removedCritiqueAssociationIDs: [UUID],
        invalidatedCheckpointIDs: [UUID]
    ) {
        self.noteID = noteID
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.removedCritiqueDocumentPath = removedCritiqueDocumentPath
        self.removedDialogueIDs = removedDialogueIDs
        self.removedCritiqueAssociationIDs = removedCritiqueAssociationIDs
        self.invalidatedCheckpointIDs = invalidatedCheckpointIDs
    }
}
