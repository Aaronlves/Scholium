import Foundation

public struct PreparedPermanentDeletion: Codable, Hashable, Sendable {
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    public let recoveryReference: PrewriteRecoveryReference

    public init(
        relativePath: String,
        fingerprint: DocumentFingerprint,
        recoveryReference: PrewriteRecoveryReference
    ) {
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.recoveryReference = recoveryReference
    }

    private enum CodingKeys: String, CodingKey {
        case relativePath
        case fingerprint
        case recoveryReference
        case recoveryVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        fingerprint = try container.decode(DocumentFingerprint.self, forKey: .fingerprint)
        if let reference = try container.decodeIfPresent(
            PrewriteRecoveryReference.self,
            forKey: .recoveryReference
        ) {
            recoveryReference = reference
        } else {
            recoveryReference = try container.decode(
                PrewriteRecoveryReference.self,
                forKey: .recoveryVersion
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(recoveryReference, forKey: .recoveryReference)
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
    public let zoteroBinding: AnalysisZoteroBinding?
    public let pendingRebindings: [NoteIdentityPendingRebinding]
    public let ambiguities: [PermanentDeletionIdentityAmbiguity]

    public init(
        record: NoteIdentityRecord,
        zoteroBinding: AnalysisZoteroBinding? = nil,
        pendingRebindings: [NoteIdentityPendingRebinding],
        ambiguities: [PermanentDeletionIdentityAmbiguity]
    ) {
        self.record = record
        self.zoteroBinding = zoteroBinding
        self.pendingRebindings = pendingRebindings
        self.ambiguities = ambiguities
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
    public let critiqueNoteID: UUID?
    public let critiqueAssociations: [CritiqueAssociation]
    public let identity: PermanentDeletionIdentityBackup?
    public let critiqueIdentity: PermanentDeletionIdentityBackup?
    public let sourceDeletion: PreparedPermanentDeletion?
    public let critiqueDeletion: PreparedPermanentDeletion?
    public let settlements: [SettlementRecord]

    public init(
        phase: PermanentDeletionRecoveryPhase,
        noteID: UUID,
        vaultID: UUID,
        relativePath: String,
        expectedRevision: DocumentFingerprint,
        critiqueNoteID: UUID?,
        critiqueAssociations: [CritiqueAssociation],
        identity: PermanentDeletionIdentityBackup?,
        critiqueIdentity: PermanentDeletionIdentityBackup?,
        sourceDeletion: PreparedPermanentDeletion?,
        critiqueDeletion: PreparedPermanentDeletion?,
        settlements: [SettlementRecord] = []
    ) {
        self.phase = phase
        self.noteID = noteID
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.expectedRevision = expectedRevision
        self.critiqueNoteID = critiqueNoteID
        self.critiqueAssociations = critiqueAssociations
        self.identity = identity
        self.critiqueIdentity = critiqueIdentity
        self.sourceDeletion = sourceDeletion
        self.critiqueDeletion = critiqueDeletion
        self.settlements = Dictionary(
            settlements.map { ($0.noteID, $0) },
            uniquingKeysWith: { _, newest in newest }
        ).values.sorted { $0.noteID.uuidString < $1.noteID.uuidString }
    }

    public func updating(
        phase: PermanentDeletionRecoveryPhase? = nil,
        sourceDeletion: PreparedPermanentDeletion?? = nil,
        critiqueDeletion: PreparedPermanentDeletion?? = nil
    ) -> Self {
        Self(
            phase: phase ?? self.phase,
            noteID: noteID,
            vaultID: vaultID,
            relativePath: relativePath,
            expectedRevision: expectedRevision,
            critiqueNoteID: critiqueNoteID,
            critiqueAssociations: critiqueAssociations,
            identity: identity,
            critiqueIdentity: critiqueIdentity,
            sourceDeletion: sourceDeletion ?? self.sourceDeletion,
            critiqueDeletion: critiqueDeletion ?? self.critiqueDeletion,
            settlements: settlements
        )
    }

    private enum CodingKeys: String, CodingKey {
        case phase, noteID, vaultID, relativePath, expectedRevision
        case critiqueNoteID
        case critiqueAssociations, identity, critiqueIdentity, sourceDeletion
        case critiqueDeletion, settlements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            phase: try container.decode(PermanentDeletionRecoveryPhase.self, forKey: .phase),
            noteID: try container.decode(UUID.self, forKey: .noteID),
            vaultID: try container.decode(UUID.self, forKey: .vaultID),
            relativePath: try container.decode(String.self, forKey: .relativePath),
            expectedRevision: try container.decode(
                DocumentFingerprint.self,
                forKey: .expectedRevision
            ),
            critiqueNoteID: try container.decodeIfPresent(UUID.self, forKey: .critiqueNoteID),
            critiqueAssociations: try container.decode(
                [CritiqueAssociation].self,
                forKey: .critiqueAssociations
            ),
            identity: try container.decodeIfPresent(
                PermanentDeletionIdentityBackup.self,
                forKey: .identity
            ),
            critiqueIdentity: try container.decodeIfPresent(
                PermanentDeletionIdentityBackup.self,
                forKey: .critiqueIdentity
            ),
            sourceDeletion: try container.decodeIfPresent(
                PreparedPermanentDeletion.self,
                forKey: .sourceDeletion
            ),
            critiqueDeletion: try container.decodeIfPresent(
                PreparedPermanentDeletion.self,
                forKey: .critiqueDeletion
            ),
            settlements: try container.decodeIfPresent(
                [SettlementRecord].self,
                forKey: .settlements
            ) ?? []
        )
    }
}
