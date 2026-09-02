import CryptoKit
import Foundation

/// Stable versions that make a Search generation reproducible and prevent a
/// saved query or derived database from silently acquiring new semantics.
public enum SearchContract {
    public static let currentVersion = 11
    public static let schemaVersion = 11
    public static let tokenizerPolicyVersion = 2
    public static let rankingPolicyVersion = 2
    public static let maximumInterfaceResults = 100
    public static let defaultCLIResults = 20
    public static let maximumCLIResults = 500
    public static let maximumQueryUTF16Count = 16_384
    public static let maximumQueryTokenCount = 64

    /// A prior version may be listed only after the current contract declares
    /// grammar, interpretation, explanation, ordering, response compatibility,
    /// and security boundaries unchanged for existing Saved Search definitions.
    public static let savedSearchCompatibleVersions: Set<Int> = [currentVersion]

    public static func isSavedSearchContractCompatible(_ version: Int) -> Bool {
        savedSearchCompatibleVersions.contains(version)
    }
}

public struct SearchSourceManifestEntry: Codable, Hashable, Sendable {
    public let vaultID: UUID
    public let relativePath: String
    public let fingerprint: DocumentFingerprint

    public init(
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint
    ) {
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.fingerprint = fingerprint
    }
}

public enum SearchSourceManifest {
    public static func hash(_ entries: [SearchSourceManifestEntry]) -> String {
        let material = entries.sorted {
            if $0.vaultID != $1.vaultID { return $0.vaultID.uuidString < $1.vaultID.uuidString }
            return $0.relativePath < $1.relativePath
        }.map {
            "\($0.vaultID.uuidString.lowercased())\u{1F}\($0.relativePath)\u{1F}\($0.fingerprint.sha256)\u{1F}\($0.fingerprint.byteCount)"
        }.joined(separator: "\u{1E}")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// The sole durable declaration stored by a Saved Search.
public struct SearchDefinition: Codable, Hashable, Sendable {
    public let contractVersion: Int
    public var query: String
    public var presentationScope: SearchPresentationScope

    public init(
        contractVersion: Int = SearchContract.currentVersion,
        query: String,
        presentationScope: SearchPresentationScope
    ) {
        self.contractVersion = contractVersion
        self.query = query
        self.presentationScope = presentationScope
    }
}

/// Exact, nonpersisted editor authority used only by This Note Search.
public struct SearchSourceSnapshot: Codable, Hashable, Sendable {
    public let noteID: VaultQualifiedNoteID
    public let stableNoteID: UUID?
    public let editorSessionID: UUID
    public let source: String
    public let editorRevision: UInt64
    public let metadata: NoteMetadataSnapshot?
    public let metadataCatalog: NoteMetadataCatalog

    public init(
        noteID: VaultQualifiedNoteID,
        stableNoteID: UUID? = nil,
        editorSessionID: UUID,
        source: String,
        editorRevision: UInt64,
        metadata: NoteMetadataSnapshot? = nil,
        metadataCatalog: NoteMetadataCatalog = .builtIn
    ) {
        self.noteID = noteID
        self.stableNoteID = stableNoteID
        self.editorSessionID = editorSessionID
        self.source = source
        self.editorRevision = editorRevision
        self.metadata = metadata
        self.metadataCatalog = metadataCatalog
    }

    public var fingerprint: DocumentFingerprint {
        DocumentFingerprint(content: source)
    }
}

/// Resolved execution authority. Scope is never inferred from query text.
public enum SearchExecutionScope: Codable, Hashable, Sendable {
    case currentNote(SearchSourceSnapshot)
    case currentVault(UUID)
    case triptych
}

public struct SearchRequest: Codable, Hashable, Sendable {
    public let id: UUID
    public let query: String
    public let presentationScope: SearchPresentationScope
    public let executionScope: SearchExecutionScope
    public let limit: Int
    public let offset: Int?
    /// Optional App-authorized subset of the selected Triptych. This is used
    /// by Scholium MCP's explicit three-role scope; query text never changes
    /// it and the Search owner retains the one canonical ordering.
    public let includedVaultIDs: [UUID]?

    public init(
        id: UUID = UUID(),
        query: String,
        presentationScope: SearchPresentationScope,
        executionScope: SearchExecutionScope,
        limit: Int,
        offset: Int = 0,
        includedVaultIDs: Set<UUID>? = nil
    ) {
        self.id = id
        self.query = query
        self.presentationScope = presentationScope
        self.executionScope = executionScope
        self.limit = limit
        self.offset = offset > 0 ? offset : nil
        self.includedVaultIDs = includedVaultIDs.map {
            $0.sorted { $0.uuidString < $1.uuidString }
        }
    }

    public var resultOffset: Int { max(0, offset ?? 0) }

    public var hasConsistentScopes: Bool {
        switch (presentationScope, executionScope) {
        case (.thisNote, .currentNote),
             (.currentVault, .currentVault),
             (.triptych, .triptych):
            includedVaultIDs == nil || {
                if case .triptych = executionScope { return true }
                return false
            }()
        default:
            false
        }
    }
}

public struct SearchGenerationID: Codable, Hashable, Sendable {
    public let triptychID: UUID
    public let sequence: Int
    public let schemaVersion: Int
    public let queryContractVersion: Int
    public let tokenizerPolicyVersion: Int
    public let rankingPolicyVersion: Int
    public let sourceManifestHash: String

    public init(
        triptychID: UUID,
        sequence: Int,
        schemaVersion: Int = SearchContract.schemaVersion,
        queryContractVersion: Int = SearchContract.currentVersion,
        tokenizerPolicyVersion: Int = SearchContract.tokenizerPolicyVersion,
        rankingPolicyVersion: Int = SearchContract.rankingPolicyVersion,
        sourceManifestHash: String
    ) {
        self.triptychID = triptychID
        self.sequence = sequence
        self.schemaVersion = schemaVersion
        self.queryContractVersion = queryContractVersion
        self.tokenizerPolicyVersion = tokenizerPolicyVersion
        self.rankingPolicyVersion = rankingPolicyVersion
        self.sourceManifestHash = sourceManifestHash
    }
}

public struct TriptychSearchIndexSyncResult: Codable, Hashable, Sendable {
    public let generation: SearchGenerationID
    public let disposition: SearchIndexSyncDisposition

    public init(
        generation: SearchGenerationID,
        disposition: SearchIndexSyncDisposition
    ) {
        self.generation = generation
        self.disposition = disposition
    }
}

public struct SearchFreshnessToken: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func currentNote(_ snapshot: SearchSourceSnapshot) -> Self {
        Self(
            "note:\(snapshot.editorSessionID.uuidString.lowercased()):\(snapshot.editorRevision):\(snapshot.fingerprint.sha256)"
        )
    }

    public static func triptych(_ generation: SearchGenerationID) -> Self {
        Self(
            "triptych:\(generation.triptychID.uuidString.lowercased()):\(generation.sequence):\(generation.sourceManifestHash)"
        )
    }

}

public struct SearchBuildProgress: Codable, Hashable, Sendable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.completed = max(0, completed)
        self.total = max(0, total)
    }

    public var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }
}

public enum SearchAvailability: Codable, Hashable, Sendable {
    case unavailable
    case building(SearchBuildProgress)
    case current(SearchGenerationID)
    /// A source-validated subset from the last complete compatible index is
    /// usable while the wider authoritative workspace is still opening.
    case limited(lastGood: SearchGenerationID)
    case refreshing(lastGood: SearchGenerationID)
    case stale(lastGood: SearchGenerationID, reason: String)
    case failed(lastGood: SearchGenerationID?, reason: String)

    public var lastGoodGeneration: SearchGenerationID? {
        switch self {
        case .current(let generation): generation
        case .limited(let generation): generation
        case .refreshing(let generation): generation
        case .stale(let generation, _): generation
        case .failed(let generation, _): generation
        case .unavailable, .building: nil
        }
    }
}

public struct SearchProviderAvailability: Codable, Hashable, Sendable {
    public let noteAvailability: SearchAvailability

    public init(_ noteAvailability: SearchAvailability) {
        self.noteAvailability = noteAvailability
    }

    public static func note(_ availability: SearchAvailability) -> Self {
        Self(availability)
    }

    public var provider: SearchProvider { .note }

}

public enum SearchQueryDiagnosticCode: String, Codable, Hashable, Sendable {
    case emptyClause
    case unclosedPhrase
    case invalidEscape
    case invalidPrefix
    case cjkPrefixUnsupported
    case unknownField
    case unsupportedField
    case providerMismatch
    case unsupportedScopeSelector
    case duplicateClause
    case missingCompanion
    case ambiguousIdentity
    case notApplicable
    case missingFieldValue
    case unknownStructuredValue
    case unsupportedSyntax
    case onlyExcludedFreeText
    case needsEditing
}

public struct SearchQueryDiagnostic: Error, Codable, Hashable, Sendable {
    public let code: SearchQueryDiagnosticCode
    public let message: String
    public let utf16LowerBound: Int
    public let utf16UpperBound: Int
    public let needsEditing: Bool

    public init(
        code: SearchQueryDiagnosticCode,
        message: String,
        utf16LowerBound: Int,
        utf16UpperBound: Int,
        needsEditing: Bool = false
    ) {
        self.code = code
        self.message = message
        self.utf16LowerBound = utf16LowerBound
        self.utf16UpperBound = utf16UpperBound
        self.needsEditing = needsEditing
    }
}

public enum SearchRankReason: String, Codable, Hashable, Sendable {
    case exactTitle = "exact_title"
    case exactAlias = "exact_alias"
    case exactFilename = "exact_filename"
    case exactPath = "exact_path"
    case lexicalRelevance = "lexical_relevance"
    case structuredFilter = "structured_filter"
}

public struct SearchSourceRange: Codable, Hashable, Sendable {
    public let utf16LowerBound: Int
    public let utf16UpperBound: Int
    public let line: Int
    public let column: Int
    public let endLine: Int
    public let endColumn: Int

    public init(
        utf16LowerBound: Int,
        utf16UpperBound: Int,
        line: Int,
        column: Int,
        endLine: Int,
        endColumn: Int
    ) {
        self.utf16LowerBound = utf16LowerBound
        self.utf16UpperBound = utf16UpperBound
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
    }
}

public struct SearchResponse: Codable, Hashable, Sendable {
    public let contractVersion: Int
    public let requestID: UUID
    public let scope: SearchPresentationScope
    public let explanation: SearchExplanation
    public let freshnessToken: SearchFreshnessToken
    public let availability: SearchProviderAvailability
    public let results: [SearchResult]
    public let hasMore: Bool
    public let totalResultCount: Int?
    public let diagnostics: [SearchQueryDiagnostic]

    public init(
        contractVersion: Int = SearchContract.currentVersion,
        requestID: UUID,
        scope: SearchPresentationScope,
        explanation: SearchExplanation,
        freshnessToken: SearchFreshnessToken,
        availability: SearchProviderAvailability,
        results: [SearchResult],
        hasMore: Bool,
        totalResultCount: Int? = nil,
        diagnostics: [SearchQueryDiagnostic] = []
    ) {
        self.contractVersion = contractVersion
        self.requestID = requestID
        self.scope = scope
        self.explanation = explanation
        self.freshnessToken = freshnessToken
        self.availability = availability
        self.results = results
        self.hasMore = hasMore
        self.totalResultCount = totalResultCount
        self.diagnostics = diagnostics
    }

    public var provider: SearchProvider { availability.provider }

    public var hasConsistentProviderIdentity: Bool {
        results.allSatisfy { $0.provider == provider }
            && explanation.provider == provider
    }
}
