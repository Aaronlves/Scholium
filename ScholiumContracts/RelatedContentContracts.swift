import Foundation

/// A separately versioned, non-query operation over the current Note Search
/// generation. It does not change visible Search grammar, scopes, or Saved
/// Search semantics.
public enum RelatedContentContract {
    public static let currentVersion = 1
    public static let rankingPolicyVersion = 1
    public static let maximumCandidates = 8
    public static let maximumSeedUTF16Count = 1_048_576
    public static let maximumSeedTerms = 64
}

/// Exact, ephemeral text authority for one related-content request. The source
/// is used only during the request and is never a writable projection.
public struct RelatedContentSeedSnapshot: Codable, Hashable, Sendable {
    public let noteID: VaultQualifiedNoteID
    public let source: String
    public let metadata: NoteMetadataSnapshot?
    public let metadataCatalog: NoteMetadataCatalog

    public init(
        noteID: VaultQualifiedNoteID,
        source: String,
        metadata: NoteMetadataSnapshot? = nil,
        metadataCatalog: NoteMetadataCatalog = .builtIn
    ) {
        self.noteID = noteID
        self.source = source
        self.metadata = metadata
        self.metadataCatalog = metadataCatalog
    }

    public var fingerprint: DocumentFingerprint {
        DocumentFingerprint(content: source)
    }
}

public struct RelatedContentRequest: Codable, Hashable, Sendable {
    public let id: UUID
    public let seed: RelatedContentSeedSnapshot
    public let limit: Int

    public init(
        id: UUID = UUID(),
        seed: RelatedContentSeedSnapshot,
        limit: Int = RelatedContentContract.maximumCandidates
    ) {
        self.id = id
        self.seed = seed
        self.limit = min(max(0, limit), RelatedContentContract.maximumCandidates)
    }
}

/// Search-owned lexical explanation. Terms are normalized retrieval terms,
/// not quotations, philosophical relations, evidence judgments, or scores.
public struct RelatedContentLexicalReason: Codable, Hashable, Sendable {
    public let matchedFields: [SearchMatchedField]
    public let matchedSeedTerms: [String]

    public init(
        matchedFields: [SearchMatchedField],
        matchedSeedTerms: [String]
    ) {
        self.matchedFields = matchedFields
        self.matchedSeedTerms = matchedSeedTerms
    }
}

public struct RelatedContentCandidate: Codable, Hashable, Sendable {
    public let note: VaultQualifiedNoteID
    public let vaultRole: VaultRole
    public let title: String
    public let fingerprint: DocumentFingerprint
    public let lexicalReason: RelatedContentLexicalReason

    public init(
        note: VaultQualifiedNoteID,
        vaultRole: VaultRole,
        title: String,
        fingerprint: DocumentFingerprint,
        lexicalReason: RelatedContentLexicalReason
    ) {
        self.note = note
        self.vaultRole = vaultRole
        self.title = title
        self.fingerprint = fingerprint
        self.lexicalReason = lexicalReason
    }
}

public enum RelatedContentResultState: String, Codable, Hashable, Sendable {
    case current
    case empty
    case stale
    case unavailable
    case invalidSeed = "invalid_seed"
}

public struct RelatedContentResponse: Codable, Hashable, Sendable {
    public let contractVersion: Int
    public let rankingPolicyVersion: Int
    public let requestID: UUID
    public let seedFingerprint: DocumentFingerprint
    public let freshnessToken: SearchFreshnessToken
    public let availability: SearchAvailability
    public let state: RelatedContentResultState
    public let candidates: [RelatedContentCandidate]
    public let hasMore: Bool

    public init(
        contractVersion: Int = RelatedContentContract.currentVersion,
        rankingPolicyVersion: Int = RelatedContentContract.rankingPolicyVersion,
        requestID: UUID,
        seedFingerprint: DocumentFingerprint,
        freshnessToken: SearchFreshnessToken,
        availability: SearchAvailability,
        state: RelatedContentResultState,
        candidates: [RelatedContentCandidate],
        hasMore: Bool
    ) {
        self.contractVersion = contractVersion
        self.rankingPolicyVersion = rankingPolicyVersion
        self.requestID = requestID
        self.seedFingerprint = seedFingerprint
        self.freshnessToken = freshnessToken
        self.availability = availability
        self.state = state
        self.candidates = candidates
        self.hasMore = hasMore
    }
}
