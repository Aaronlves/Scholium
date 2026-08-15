import Foundation

/// One exact source target in a monotonic permanent-deletion plan.
public struct PermanentDeletionTarget: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let relativePath: String
    public let expectedRevision: DocumentFingerprint

    public init(
        noteID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint
    ) {
        self.noteID = noteID
        self.relativePath = relativePath
        self.expectedRevision = expectedRevision
    }
}

/// Durable intent for idempotent deletion and privacy cleanup. It contains no
/// Markdown bytes and cannot restore a deleted source.
public struct PermanentDeletionPlan: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let vaultID: UUID
    public let relativePath: String
    public let expectedRevision: DocumentFingerprint
    public let critique: PermanentDeletionTarget?
    public let critiqueAssociations: [CritiqueAssociation]

    public init(
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        critique: PermanentDeletionTarget?,
        critiqueAssociations: [CritiqueAssociation]
    ) {
        self.noteID = noteID
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.expectedRevision = expectedRevision
        self.critique = critique
        self.critiqueAssociations = critiqueAssociations
    }

    public var deletedNoteIDs: Set<UUID> {
        var ids: Set<UUID> = [noteID]
        if let critique { ids.insert(critique.noteID) }
        return ids
    }
}
