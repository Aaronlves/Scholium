import Foundation

/// A separately versioned, non-query operation over the current Note Search
/// generation. It does not change visible Search grammar, scopes, or Saved
/// Search semantics.
public enum RelatedContentContract {
    public static let currentVersion = 5
    public static let rankingPolicyVersion = 4
    public static let maximumCandidates = 27
    public static let maximumDirectConnectionCandidates = 4
    public static let maximumIdentityCandidates = 3
    public static let maximumLexicalCandidates = 24
    public static let maximumPassages = 6
    public static let maximumPassagesPerNote = 2
    public static let maximumPassageUTF16Count = 32_000
    public static let maximumSeedUTF16Count = 1_048_576
    public static let maximumFocusUTF16Count = 65_536
    public static let maximumSourceSeedTerms = 64
    public static let maximumFocusSeedTerms = 32
    public static let maximumCombinedSeedTerms = 96
    public static let maximumLexicalCandidatePool = 256
}

/// Names the exact part of the frozen task that supplied a retrieval term or
/// identity mention. Values order focused text before the source Note only for
/// internal deterministic ranking; they do not express evidential strength.
public enum RelatedContentSeedKind: String, Codable, CaseIterable, Hashable, Sendable {
    case selectedPassage = "selected_passage"
    case researchRequest = "research_request"
    case sourceNote = "source_note"

    public static let rankingOrder: [Self] = [
        .selectedPassage, .researchRequest, .sourceNote,
    ]
}

public enum RelatedContentCandidateRole: String, Codable, CaseIterable, Hashable,
    Sendable
{
    case analysis
    case topic

    public var vaultRole: VaultRole {
        switch self {
        case .analysis: .sourceCorpus
        case .topic: .topicKnowledge
        }
    }
}

public struct RelatedContentSeedFocus: Codable, Hashable, Sendable {
    public let kind: RelatedContentSeedKind
    public let text: String

    public init(kind: RelatedContentSeedKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Exact, ephemeral text authority for one related-content request. The source
/// and focused task text are used only during the request and are never a
/// writable projection.
public struct RelatedContentSeedSnapshot: Codable, Hashable, Sendable {
    public let noteID: VaultQualifiedNoteID
    public let source: String
    public let focuses: [RelatedContentSeedFocus]
    public let metadata: NoteMetadataSnapshot?
    public let metadataCatalog: NoteMetadataCatalog

    public init(
        noteID: VaultQualifiedNoteID,
        source: String,
        focuses: [RelatedContentSeedFocus] = [],
        metadata: NoteMetadataSnapshot? = nil,
        metadataCatalog: NoteMetadataCatalog = .builtIn
    ) {
        self.noteID = noteID
        self.source = source
        self.focuses = RelatedContentSeedKind.rankingOrder.compactMap { kind in
            focuses.first { $0.kind == kind }
        }
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
    public let candidateRoles: [RelatedContentCandidateRole]
    public let identityLimit: Int
    public let lexicalLimit: Int

    public init(
        id: UUID = UUID(),
        seed: RelatedContentSeedSnapshot,
        candidateRoles: [RelatedContentCandidateRole] = RelatedContentCandidateRole.allCases,
        identityLimit: Int = RelatedContentContract.maximumIdentityCandidates,
        lexicalLimit: Int = RelatedContentContract.maximumLexicalCandidates
    ) {
        self.id = id
        self.seed = seed
        self.candidateRoles = RelatedContentCandidateRole.allCases.filter {
            candidateRoles.contains($0)
        }
        self.identityLimit = min(
            max(0, identityLimit),
            RelatedContentContract.maximumIdentityCandidates
        )
        self.lexicalLimit = min(
            max(0, lexicalLimit),
            RelatedContentContract.maximumLexicalCandidates
        )
    }
}

public enum RelatedContentIdentityKind: String, Codable, Hashable, Sendable {
    case title
    case alias
}

/// One exact candidate title or alias found in one explicit seed component.
/// The value is an identity explanation, not a relation or evidence claim.
public struct RelatedContentIdentityMention: Codable, Hashable, Sendable {
    public let seedKind: RelatedContentSeedKind
    public let identityKind: RelatedContentIdentityKind
    public let matchedIdentity: String
    public let seedField: SearchMatchedField?

    public init(
        seedKind: RelatedContentSeedKind,
        identityKind: RelatedContentIdentityKind,
        matchedIdentity: String,
        seedField: SearchMatchedField? = nil
    ) {
        self.seedKind = seedKind
        self.identityKind = identityKind
        self.matchedIdentity = matchedIdentity
        self.seedField = seedField
    }
}

public struct RelatedContentIdentityMentionReason: Codable, Hashable, Sendable {
    public let mentions: [RelatedContentIdentityMention]

    public init(mentions: [RelatedContentIdentityMention]) {
        self.mentions = mentions
    }
}

public struct RelatedContentSeedTermMatch: Codable, Hashable, Sendable {
    public let seedKind: RelatedContentSeedKind
    public let terms: [String]

    public init(seedKind: RelatedContentSeedKind, terms: [String]) {
        self.seedKind = seedKind
        self.terms = terms
    }
}

/// Search-owned lexical explanation. Terms are normalized retrieval terms,
/// not quotations, philosophical relations, evidence judgments, or scores.
public struct RelatedContentLexicalReason: Codable, Hashable, Sendable {
    public let matchedFields: [SearchMatchedField]
    public let seedMatches: [RelatedContentSeedTermMatch]

    public init(
        matchedFields: [SearchMatchedField],
        seedMatches: [RelatedContentSeedTermMatch]
    ) {
        self.matchedFields = matchedFields
        self.seedMatches = seedMatches
    }
}

public enum RelatedContentSearchReason: Codable, Hashable, Sendable {
    case identityMention(RelatedContentIdentityMentionReason)
    case lexicalOverlap(RelatedContentLexicalReason)
}

public struct RelatedContentCandidate: Codable, Hashable, Sendable {
    public let note: VaultQualifiedNoteID
    public let vaultRole: VaultRole
    public let title: String
    public let fingerprint: DocumentFingerprint
    public let reason: RelatedContentSearchReason

    public init(
        note: VaultQualifiedNoteID,
        vaultRole: VaultRole,
        title: String,
        fingerprint: DocumentFingerprint,
        reason: RelatedContentSearchReason
    ) {
        self.note = note
        self.vaultRole = vaultRole
        self.title = title
        self.fingerprint = fingerprint
        self.reason = reason
    }
}

/// One exact, revision-bound research paragraph. Visible text is a read-only
/// projection; quotation and handoff always use `source` and its original range.
public struct RelatedContentPassage: Codable, Hashable, Sendable, Identifiable {
    public let candidate: RelatedContentCandidate
    public let range: SearchSourceRange
    public let source: String
    public let displayText: String
    public let matches: [RelatedContentSeedTermMatch]
    public var id: String {
        "\(candidate.note.vaultID):\(candidate.note.relativePath):\(candidate.fingerprint.sha256):\(range.utf16LowerBound)"
    }
    public init(
        candidate: RelatedContentCandidate, range: SearchSourceRange, source: String,
        displayText: String, matches: [RelatedContentSeedTermMatch]
    ) {
        self.candidate = candidate
        self.range = range
        self.source = source
        self.displayText = displayText
        self.matches = matches
    }
}

public struct RelatedContentSource: Sendable {
    public let candidate: RelatedContentCandidate
    public let document: NoteDocument
    public init(candidate: RelatedContentCandidate, document: NoteDocument) {
        self.candidate = candidate
        self.document = document
    }
}

public enum RelatedContentResultState: String, Codable, Hashable, Sendable {
    case current
    case empty
    case partial
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
    public let identityCandidates: [RelatedContentCandidate]
    public let lexicalCandidates: [RelatedContentCandidate]
    public let identityHasMore: Bool
    public let lexicalHasMore: Bool
    public let passages: [RelatedContentPassage]
    public let omittedSourceCount: Int

    public init(
        contractVersion: Int = RelatedContentContract.currentVersion,
        rankingPolicyVersion: Int = RelatedContentContract.rankingPolicyVersion,
        requestID: UUID,
        seedFingerprint: DocumentFingerprint,
        freshnessToken: SearchFreshnessToken,
        availability: SearchAvailability,
        state: RelatedContentResultState,
        identityCandidates: [RelatedContentCandidate],
        lexicalCandidates: [RelatedContentCandidate],
        identityHasMore: Bool,
        lexicalHasMore: Bool,
        passages: [RelatedContentPassage] = [],
        omittedSourceCount: Int = 0
    ) {
        self.contractVersion = contractVersion
        self.rankingPolicyVersion = rankingPolicyVersion
        self.requestID = requestID
        self.seedFingerprint = seedFingerprint
        self.freshnessToken = freshnessToken
        self.availability = availability
        self.state = state
        self.identityCandidates = identityCandidates
        self.lexicalCandidates = lexicalCandidates
        self.identityHasMore = identityHasMore
        self.lexicalHasMore = lexicalHasMore
        self.passages = passages
        self.omittedSourceCount = omittedSourceCount
    }
}
