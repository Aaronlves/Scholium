import Foundation

public struct PreparedPermanentDeletion: Codable, Hashable, Sendable {
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    public let recoveryVersion: VaultVersion

    public init(
        relativePath: String,
        fingerprint: DocumentFingerprint,
        recoveryVersion: VaultVersion
    ) {
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.recoveryVersion = recoveryVersion
    }
}

public struct PermanentDeletionIdentityAmbiguity: Codable, Hashable, Sendable {
    public let vaultID: UUID
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    public let candidateIDs: [UUID]
    public let detectedAt: Date

    public init(
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        candidateIDs: [UUID],
        detectedAt: Date
    ) {
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.candidateIDs = candidateIDs
        self.detectedAt = detectedAt
    }
}

public struct PermanentDeletionIdentityBackup: Codable, Hashable, Sendable {
    public let record: NoteIdentityRecord
    public let pendingRebindings: [NoteIdentityPendingRebinding]
    public let ambiguities: [PermanentDeletionIdentityAmbiguity]

    public init(
        record: NoteIdentityRecord,
        pendingRebindings: [NoteIdentityPendingRebinding],
        ambiguities: [PermanentDeletionIdentityAmbiguity]
    ) {
        self.record = record
        self.pendingRebindings = pendingRebindings
        self.ambiguities = ambiguities
    }
}

public struct PreparedCheckpointPurge: Codable, Hashable, Sendable {
    public let stagingID: UUID
    public let checkpointIDs: [UUID]

    public init(stagingID: UUID, checkpointIDs: [UUID]) {
        self.stagingID = stagingID
        self.checkpointIDs = checkpointIDs
    }
}

public enum PermanentDeletionRecoveryPhase: String, Codable, Hashable, Sendable {
    case rollbackRequired
    case committing
}

public struct PermanentDeletionRecoveryBackup: Codable, Hashable, Sendable {
    public let phase: PermanentDeletionRecoveryPhase
    public let noteID: UUID
    public let vaultID: UUID
    public let relativePath: String
    public let expectedRevision: DocumentFingerprint
    public let checkpointArea: TriptychCheckpointArea
    public let humanReview: HumanReviewRecord?
    public let dialogues: [DialogueEntry]
    public let critiqueNoteID: UUID?
    public let critiqueHumanReview: HumanReviewRecord?
    public let critiqueDialogues: [DialogueEntry]
    public let critiqueAssociations: [CritiqueAssociation]
    public let identity: PermanentDeletionIdentityBackup?
    public let critiqueIdentity: PermanentDeletionIdentityBackup?
    public let sourceDeletion: PreparedPermanentDeletion?
    public let critiqueDeletion: PreparedPermanentDeletion?
    public let checkpointPurge: PreparedCheckpointPurge?

    public init(
        phase: PermanentDeletionRecoveryPhase,
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        checkpointArea: TriptychCheckpointArea,
        humanReview: HumanReviewRecord?,
        dialogues: [DialogueEntry],
        critiqueNoteID: UUID?,
        critiqueHumanReview: HumanReviewRecord?,
        critiqueDialogues: [DialogueEntry],
        critiqueAssociations: [CritiqueAssociation],
        identity: PermanentDeletionIdentityBackup?,
        critiqueIdentity: PermanentDeletionIdentityBackup?,
        sourceDeletion: PreparedPermanentDeletion?,
        critiqueDeletion: PreparedPermanentDeletion?,
        checkpointPurge: PreparedCheckpointPurge?
    ) {
        self.phase = phase
        self.noteID = noteID
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.expectedRevision = expectedRevision
        self.checkpointArea = checkpointArea
        self.humanReview = humanReview
        self.dialogues = dialogues
        self.critiqueNoteID = critiqueNoteID
        self.critiqueHumanReview = critiqueHumanReview
        self.critiqueDialogues = critiqueDialogues
        self.critiqueAssociations = critiqueAssociations
        self.identity = identity
        self.critiqueIdentity = critiqueIdentity
        self.sourceDeletion = sourceDeletion
        self.critiqueDeletion = critiqueDeletion
        self.checkpointPurge = checkpointPurge
    }

    public func updating(
        phase: PermanentDeletionRecoveryPhase? = nil,
        sourceDeletion: PreparedPermanentDeletion?? = nil,
        critiqueDeletion: PreparedPermanentDeletion?? = nil,
        checkpointPurge: PreparedCheckpointPurge?? = nil
    ) -> Self {
        Self(
            phase: phase ?? self.phase,
            noteID: noteID,
            vaultID: vaultID,
            relativePath: relativePath,
            expectedRevision: expectedRevision,
            checkpointArea: checkpointArea,
            humanReview: humanReview,
            dialogues: dialogues,
            critiqueNoteID: critiqueNoteID,
            critiqueHumanReview: critiqueHumanReview,
            critiqueDialogues: critiqueDialogues,
            critiqueAssociations: critiqueAssociations,
            identity: identity,
            critiqueIdentity: critiqueIdentity,
            sourceDeletion: sourceDeletion ?? self.sourceDeletion,
            critiqueDeletion: critiqueDeletion ?? self.critiqueDeletion,
            checkpointPurge: checkpointPurge ?? self.checkpointPurge
        )
    }
}
