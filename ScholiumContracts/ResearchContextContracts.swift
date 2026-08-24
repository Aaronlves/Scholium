import Foundation

/// The closed set of authoritative object families that may enter a Research
/// Context response. Adding a future family requires a contract version cut;
/// unknown values never fall through to generic metadata.
public enum ResearchContextSourceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case note
    case record
    case material
    case researcherState = "researcher_state"
}

public enum ResearchContextActorClass: String, Codable, CaseIterable, Hashable, Sendable {
    case researcher
    case agent
    case scholium
    case unknown
}

public enum ResearchContextObjectRole: String, Codable, CaseIterable, Hashable, Sendable {
    case analysis
    case topic
    case work
    case researchRecord = "research_record"
    case sourceMaterial = "source_material"
    case researcherState = "researcher_state"
}

public enum ResearchContextCurrentness: String, Codable, CaseIterable, Hashable, Sendable {
    case current
    case stale
    case unknown
}

public enum ResearchContextAvailability: String, Codable, CaseIterable, Hashable, Sendable {
    case current
    case partial
    case stale
    case unavailable
    case invalidQuery = "invalid_query"
}

/// Discovery reasons remain semantic products of existing owners. They do not
/// expose provider identities, scores, ranking internals, or confidence.
public enum ResearchContextRetrievalReason: String, Codable, CaseIterable, Hashable, Sendable {
    case lexical
    case canonicalSummary = "canonical_summary"
    case propertyPresence = "property_presence"
    case directRelation = "direct_relation"
    case exactRead = "exact_read"
    case recordSearch = "record_search"
    case explicitSelection = "explicit_selection"
    case researcherState = "researcher_state"
}

public enum ResearchContextContractError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidOwner
    case invalidLocator
    case invalidAuthorizedScope
    case invalidSourceReference
    case invalidQuery
    case invalidResponse
    case invalidContextUseReport
    case invalidText(String)
}

public enum ResearchContextOwnerKind: String, Codable, CaseIterable, Hashable, Sendable {
    case note
    case record
    case material
    case researcherState = "researcher_state"
}

/// A route back to exactly one authoritative owner. It contains no absolute
/// path, source bytes, provider key, or mutable projection identity.
public struct ResearchContextOwnerReference: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let kind: ResearchContextOwnerKind
    public let triptychID: UUID
    public let stableObjectIdentity: String
    public let vaultID: UUID?
    public let relativePath: String?
    public let recordID: UUID?
    public let materialID: UUID?

    public static func note(
        triptychID: UUID,
        note: VaultQualifiedNoteID,
        stableObjectIdentity: String
    ) throws -> Self {
        try Self(
            kind: .note,
            triptychID: triptychID,
            stableObjectIdentity: stableObjectIdentity,
            vaultID: note.vaultID,
            relativePath: note.relativePath
        )
    }

    public static func record(
        triptychID: UUID,
        recordID: UUID,
        stableObjectIdentity: String? = nil
    ) throws -> Self {
        try Self(
            kind: .record,
            triptychID: triptychID,
            stableObjectIdentity: stableObjectIdentity ?? recordID.uuidString.lowercased(),
            recordID: recordID
        )
    }

    public static func material(
        triptychID: UUID,
        materialID: UUID,
        stableObjectIdentity: String? = nil
    ) throws -> Self {
        try Self(
            kind: .material,
            triptychID: triptychID,
            stableObjectIdentity: stableObjectIdentity ?? materialID.uuidString.lowercased(),
            materialID: materialID
        )
    }

    public static func researcherState(
        triptychID: UUID,
        stableObjectIdentity: String
    ) throws -> Self {
        try Self(
            kind: .researcherState,
            triptychID: triptychID,
            stableObjectIdentity: stableObjectIdentity
        )
    }

    private init(
        schemaVersion: Int = currentSchemaVersion,
        kind: ResearchContextOwnerKind,
        triptychID: UUID,
        stableObjectIdentity: String,
        vaultID: UUID? = nil,
        relativePath: String? = nil,
        recordID: UUID? = nil,
        materialID: UUID? = nil
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let identity = try ResearchContextValidation.text(
            stableObjectIdentity,
            maximumUTF8Count: 512,
            field: "stableObjectIdentity"
        )
        switch kind {
        case .note:
            guard vaultID != nil,
                  let relativePath,
                  ResearchContextValidation.isSafeRelativePath(relativePath),
                  recordID == nil,
                  materialID == nil else {
                throw ResearchContextContractError.invalidOwner
            }
        case .record:
            guard recordID != nil,
                  vaultID == nil,
                  relativePath == nil,
                  materialID == nil else {
                throw ResearchContextContractError.invalidOwner
            }
        case .material:
            guard materialID != nil,
                  vaultID == nil,
                  relativePath == nil,
                  recordID == nil else {
                throw ResearchContextContractError.invalidOwner
            }
        case .researcherState:
            guard vaultID == nil,
                  relativePath == nil,
                  recordID == nil,
                  materialID == nil else {
                throw ResearchContextContractError.invalidOwner
            }
        }
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.triptychID = triptychID
        self.stableObjectIdentity = identity
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.recordID = recordID
        self.materialID = materialID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case kind
        case triptychID
        case stableObjectIdentity
        case vaultID
        case relativePath
        case recordID
        case materialID
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            kind: try container.decode(ResearchContextOwnerKind.self, forKey: .kind),
            triptychID: try container.decode(UUID.self, forKey: .triptychID),
            stableObjectIdentity: try container.decode(
                String.self,
                forKey: .stableObjectIdentity
            ),
            vaultID: try container.decodeIfPresent(UUID.self, forKey: .vaultID),
            relativePath: try container.decodeIfPresent(String.self, forKey: .relativePath),
            recordID: try container.decodeIfPresent(UUID.self, forKey: .recordID),
            materialID: try container.decodeIfPresent(UUID.self, forKey: .materialID)
        )
    }
}

public enum ResearchContextLocatorKind: String, Codable, CaseIterable, Hashable, Sendable {
    case sourceRange = "source_range"
    case recordStatement = "record_statement"
    case materialLocator = "material_locator"
    case wholeObject = "whole_object"
    case unknown
}

public struct ResearchContextSourceLocator: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let kind: ResearchContextLocatorKind
    public let sourceRange: SearchSourceRange?
    public let statementID: UUID?
    public let materialLocator: String?

    public static func sourceRange(_ range: SearchSourceRange) throws -> Self {
        try Self(kind: .sourceRange, sourceRange: range)
    }

    public static func recordStatement(_ id: UUID) throws -> Self {
        try Self(kind: .recordStatement, statementID: id)
    }

    public static func material(_ locator: String) throws -> Self {
        try Self(kind: .materialLocator, materialLocator: locator)
    }

    /// A path-free locator derived only from the authoritative source identity.
    /// Local filenames, bookmarks, and absolute paths never enter the envelope.
    public static func materialSource(_ source: ResearchSourceReference) throws -> Self {
        let identity = source.identity
        let locator: String = switch identity.route {
        case .localFile:
            "local-file:\(identity.id.uuidString.lowercased())"
        case .zoteroAttachment:
            "zotero-item:\(identity.zoteroItemKey!);attachment:\(identity.zoteroAttachmentKey!)"
        }
        return try material(locator)
    }

    public static let wholeObject = try! Self(kind: .wholeObject)
    public static let unknown = try! Self(kind: .unknown)

    private init(
        schemaVersion: Int = currentSchemaVersion,
        kind: ResearchContextLocatorKind,
        sourceRange: SearchSourceRange? = nil,
        statementID: UUID? = nil,
        materialLocator: String? = nil
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
        }
        switch kind {
        case .sourceRange:
            guard let sourceRange,
                  sourceRange.utf16LowerBound >= 0,
                  sourceRange.utf16UpperBound >= sourceRange.utf16LowerBound,
                  sourceRange.line > 0,
                  sourceRange.column > 0,
                  sourceRange.endLine >= sourceRange.line,
                  sourceRange.endColumn > 0,
                  statementID == nil,
                  materialLocator == nil else {
                throw ResearchContextContractError.invalidLocator
            }
        case .recordStatement:
            guard statementID != nil,
                  sourceRange == nil,
                  materialLocator == nil else {
                throw ResearchContextContractError.invalidLocator
            }
        case .materialLocator:
            guard sourceRange == nil,
                  statementID == nil,
                  materialLocator != nil else {
                throw ResearchContextContractError.invalidLocator
            }
        case .wholeObject, .unknown:
            guard sourceRange == nil,
                  statementID == nil,
                  materialLocator == nil else {
                throw ResearchContextContractError.invalidLocator
            }
        }
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.sourceRange = sourceRange
        self.statementID = statementID
        self.materialLocator = try materialLocator.map {
            try ResearchContextValidation.text(
                $0,
                maximumUTF8Count: 512,
                field: "materialLocator"
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case kind
        case sourceRange
        case statementID
        case materialLocator
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            kind: try container.decode(ResearchContextLocatorKind.self, forKey: .kind),
            sourceRange: try container.decodeIfPresent(
                SearchSourceRange.self,
                forKey: .sourceRange
            ),
            statementID: try container.decodeIfPresent(UUID.self, forKey: .statementID),
            materialLocator: try container.decodeIfPresent(
                String.self,
                forKey: .materialLocator
            )
        )
    }

    /// Confirms that a source-range locator is an exact, reversible position in
    /// the current UTF-8 source, including EOF after a final newline.
    public func isValid(in source: String) -> Bool {
        switch kind {
        case .wholeObject:
            return true
        case .sourceRange:
            guard let range = sourceRange,
                  range.utf16LowerBound >= 0,
                  range.utf16UpperBound >= range.utf16LowerBound,
                  range.utf16UpperBound <= source.utf16.count else { return false }
            let lowerUTF16 = source.utf16.index(
                source.utf16.startIndex,
                offsetBy: range.utf16LowerBound
            )
            let upperUTF16 = source.utf16.index(
                source.utf16.startIndex,
                offsetBy: range.utf16UpperBound
            )
            guard String.Index(lowerUTF16, within: source) != nil,
                  String.Index(upperUTF16, within: source) != nil else {
                return false
            }
            let start = Self.position(in: source, atUTF16Offset: range.utf16LowerBound)
            let end = Self.position(in: source, atUTF16Offset: range.utf16UpperBound)
            return range.line == start.line
                && range.column == start.column
                && range.endLine == end.line
                && range.endColumn == end.column
        case .recordStatement, .materialLocator, .unknown:
            return false
        }
    }

    private static func position(in source: String, atUTF16Offset offset: Int) -> (line: Int, column: Int) {
        var line = 1
        var column = 1
        for unit in source.utf16.prefix(offset) {
            if unit == 10 {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return (line, column)
    }
}

public enum ResearchAuthorizedScopeKind: String, Codable, CaseIterable, Hashable, Sendable {
    case triptych
    case vault
    case object
}

/// Authorization is established before provider work and is then copied into
/// each reference. This value contains no bearer credential.
public struct ResearchAuthorizedScope: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: UUID
    public let triptychID: UUID
    public let kind: ResearchAuthorizedScopeKind
    public let vaultID: UUID?
    public let stableObjectIdentity: String?

    public static func triptych(runID: UUID, triptychID: UUID) throws -> Self {
        try Self(runID: runID, triptychID: triptychID, kind: .triptych)
    }

    public static func vault(runID: UUID, triptychID: UUID, vaultID: UUID) throws -> Self {
        try Self(
            runID: runID,
            triptychID: triptychID,
            kind: .vault,
            vaultID: vaultID
        )
    }

    public static func object(
        runID: UUID,
        triptychID: UUID,
        stableObjectIdentity: String
    ) throws -> Self {
        try Self(
            runID: runID,
            triptychID: triptychID,
            kind: .object,
            stableObjectIdentity: stableObjectIdentity
        )
    }

    private init(
        schemaVersion: Int = currentSchemaVersion,
        runID: UUID,
        triptychID: UUID,
        kind: ResearchAuthorizedScopeKind,
        vaultID: UUID? = nil,
        stableObjectIdentity: String? = nil
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let identity = try stableObjectIdentity.map {
            try ResearchContextValidation.text(
                $0,
                maximumUTF8Count: 512,
                field: "stableObjectIdentity"
            )
        }
        switch kind {
        case .triptych:
            guard vaultID == nil, identity == nil else {
                throw ResearchContextContractError.invalidAuthorizedScope
            }
        case .vault:
            guard vaultID != nil, identity == nil else {
                throw ResearchContextContractError.invalidAuthorizedScope
            }
        case .object:
            guard vaultID == nil, identity != nil else {
                throw ResearchContextContractError.invalidAuthorizedScope
            }
        }
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.triptychID = triptychID
        self.kind = kind
        self.vaultID = vaultID
        self.stableObjectIdentity = identity
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case runID
        case triptychID
        case kind
        case vaultID
        case stableObjectIdentity
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            runID: try container.decode(UUID.self, forKey: .runID),
            triptychID: try container.decode(UUID.self, forKey: .triptychID),
            kind: try container.decode(ResearchAuthorizedScopeKind.self, forKey: .kind),
            vaultID: try container.decodeIfPresent(UUID.self, forKey: .vaultID),
            stableObjectIdentity: try container.decodeIfPresent(
                String.self,
                forKey: .stableObjectIdentity
            )
        )
    }
}

/// Source-preserving attribution and authorization metadata for one item.
/// This envelope is not philosophical evidence and never carries confidence.
public struct SourceReferenceEnvelope: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumLimitations = 16

    public let schemaVersion: Int
    public let id: UUID
    public let sourceKind: ResearchContextSourceKind
    public let owner: ResearchContextOwnerReference
    public let actorClass: ResearchContextActorClass
    public let objectRole: ResearchContextObjectRole
    public let vaultRole: VaultRole?
    public let fingerprint: DocumentFingerprint?
    public let locator: ResearchContextSourceLocator
    public let authorizedScope: ResearchAuthorizedScope
    public let currentness: ResearchContextCurrentness
    public let evidentialLayer: EvidentialLayer
    public let retrievalReason: ResearchContextRetrievalReason
    public let materialLimitations: [String]

    public init(
        id: UUID = UUID(),
        sourceKind: ResearchContextSourceKind,
        owner: ResearchContextOwnerReference,
        actorClass: ResearchContextActorClass,
        objectRole: ResearchContextObjectRole,
        vaultRole: VaultRole? = nil,
        fingerprint: DocumentFingerprint? = nil,
        locator: ResearchContextSourceLocator,
        authorizedScope: ResearchAuthorizedScope,
        currentness: ResearchContextCurrentness,
        evidentialLayer: EvidentialLayer,
        retrievalReason: ResearchContextRetrievalReason,
        materialLimitations: [String] = []
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            id: id,
            sourceKind: sourceKind,
            owner: owner,
            actorClass: actorClass,
            objectRole: objectRole,
            vaultRole: vaultRole,
            fingerprint: fingerprint,
            locator: locator,
            authorizedScope: authorizedScope,
            currentness: currentness,
            evidentialLayer: evidentialLayer,
            retrievalReason: retrievalReason,
            materialLimitations: materialLimitations
        )
    }

    private init(
        schemaVersion: Int,
        id: UUID,
        sourceKind: ResearchContextSourceKind,
        owner: ResearchContextOwnerReference,
        actorClass: ResearchContextActorClass,
        objectRole: ResearchContextObjectRole,
        vaultRole: VaultRole?,
        fingerprint: DocumentFingerprint?,
        locator: ResearchContextSourceLocator,
        authorizedScope: ResearchAuthorizedScope,
        currentness: ResearchContextCurrentness,
        evidentialLayer: EvidentialLayer,
        retrievalReason: ResearchContextRetrievalReason,
        materialLimitations: [String]
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
        }
        guard sourceKind.rawValue == owner.kind.rawValue,
              owner.triptychID == authorizedScope.triptychID,
              materialLimitations.count <= Self.maximumLimitations else {
            throw ResearchContextContractError.invalidSourceReference
        }
        switch authorizedScope.kind {
        case .triptych:
            break
        case .vault:
            guard owner.vaultID == authorizedScope.vaultID else {
                throw ResearchContextContractError.invalidSourceReference
            }
        case .object:
            guard owner.stableObjectIdentity == authorizedScope.stableObjectIdentity else {
                throw ResearchContextContractError.invalidSourceReference
            }
        }
        switch sourceKind {
        case .note:
            let roleMatchesVault = switch (objectRole, vaultRole) {
            case (.analysis, .sourceCorpus), (.topic, .topicKnowledge),
                 (.work, .draftProject): true
            default: false
            }
            guard roleMatchesVault,
                  locator.kind == .sourceRange
                    || locator.kind == .wholeObject
                    || locator.kind == .unknown else {
                throw ResearchContextContractError.invalidSourceReference
            }
        case .record:
            guard objectRole == .researchRecord,
                  vaultRole == nil,
                  locator.kind == .recordStatement
                    || locator.kind == .wholeObject
                    || locator.kind == .unknown else {
                throw ResearchContextContractError.invalidSourceReference
            }
        case .material:
            guard objectRole == .sourceMaterial,
                  vaultRole == nil,
                  locator.kind == .materialLocator
                    || locator.kind == .wholeObject
                    || locator.kind == .unknown else {
                throw ResearchContextContractError.invalidSourceReference
            }
        case .researcherState:
            guard objectRole == .researcherState,
                  vaultRole == nil,
                  locator.kind == .wholeObject
                    || locator.kind == .unknown else {
                throw ResearchContextContractError.invalidSourceReference
            }
        }
        if let fingerprint {
            guard fingerprint.byteCount >= 0,
                  fingerprint.sha256.count == 64,
                  fingerprint.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                throw ResearchContextContractError.invalidSourceReference
            }
        }
        if currentness == .current, fingerprint == nil {
            throw ResearchContextContractError.invalidSourceReference
        }
        if actorClass == .unknown || locator.kind == .unknown || currentness == .unknown {
            guard !materialLimitations.isEmpty else {
                throw ResearchContextContractError.invalidSourceReference
            }
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.sourceKind = sourceKind
        self.owner = owner
        self.actorClass = actorClass
        self.objectRole = objectRole
        self.vaultRole = vaultRole
        self.fingerprint = fingerprint
        self.locator = locator
        self.authorizedScope = authorizedScope
        self.currentness = currentness
        self.evidentialLayer = evidentialLayer
        self.retrievalReason = retrievalReason
        self.materialLimitations = try ResearchContextValidation.texts(
            materialLimitations,
            maximumCount: Self.maximumLimitations,
            maximumUTF8Count: 1_024,
            field: "materialLimitations"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case id
        case sourceKind
        case owner
        case actorClass
        case objectRole
        case vaultRole
        case fingerprint
        case locator
        case authorizedScope
        case currentness
        case evidentialLayer
        case retrievalReason
        case materialLimitations
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            id: try container.decode(UUID.self, forKey: .id),
            sourceKind: try container.decode(
                ResearchContextSourceKind.self,
                forKey: .sourceKind
            ),
            owner: try container.decode(
                ResearchContextOwnerReference.self,
                forKey: .owner
            ),
            actorClass: try container.decode(
                ResearchContextActorClass.self,
                forKey: .actorClass
            ),
            objectRole: try container.decode(
                ResearchContextObjectRole.self,
                forKey: .objectRole
            ),
            vaultRole: try container.decodeIfPresent(VaultRole.self, forKey: .vaultRole),
            fingerprint: try container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .fingerprint
            ),
            locator: try container.decode(
                ResearchContextSourceLocator.self,
                forKey: .locator
            ),
            authorizedScope: try container.decode(
                ResearchAuthorizedScope.self,
                forKey: .authorizedScope
            ),
            currentness: try container.decode(
                ResearchContextCurrentness.self,
                forKey: .currentness
            ),
            evidentialLayer: try container.decode(
                EvidentialLayer.self,
                forKey: .evidentialLayer
            ),
            retrievalReason: try container.decode(
                ResearchContextRetrievalReason.self,
                forKey: .retrievalReason
            ),
            materialLimitations: try container.decode(
                [String].self,
                forKey: .materialLimitations
            )
        )
    }
}

public enum ResearchContextClauseKind: String, Codable, CaseIterable, Hashable, Sendable {
    case discoverNote = "discover_note"
    case readNote = "read_note"
    case inspectRelations = "inspect_relations"
    case inspectMetadata = "inspect_metadata"
    case inspectRecords = "inspect_records"
    case inspectMaterials = "inspect_materials"
    case inspectResearcherState = "inspect_researcher_state"

    public var sourceKind: ResearchContextSourceKind {
        switch self {
        case .discoverNote, .readNote, .inspectRelations, .inspectMetadata: .note
        case .inspectRecords: .record
        case .inspectMaterials: .material
        case .inspectResearcherState: .researcherState
        }
    }
}

public enum ResearchContextClauseScope: String, Codable, CaseIterable, Hashable, Sendable {
    case triptych
}

public enum ResearchContextUseEligibility: String, Codable, CaseIterable, Hashable, Sendable {
    case contextUse = "context_use"
    case referenceOnly = "reference_only"
}

/// Stateless continuation data. Its binding is recomputed by Application from
/// the authenticated Run, Triptych, query, clause, owner revision, and range;
/// it is neither a capability nor a delivery registry entry.
public struct ResearchContextPageCursor: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let clauseID: UUID
    public let note: VaultQualifiedNoteID
    public let fingerprint: DocumentFingerprint
    public let sourceRange: SearchSourceRange
    public let pageStartUTF8Offset: Int
    public let nextUTF8Offset: Int
    public let binding: DocumentFingerprint
    public let pageDigest: DocumentFingerprint

    public init(
        clauseID: UUID,
        note: VaultQualifiedNoteID,
        fingerprint: DocumentFingerprint,
        sourceRange: SearchSourceRange,
        pageStartUTF8Offset: Int,
        nextUTF8Offset: Int,
        binding: DocumentFingerprint,
        pageDigest: DocumentFingerprint
    ) throws {
        guard pageStartUTF8Offset >= 0,
              nextUTF8Offset > pageStartUTF8Offset,
              sourceRange.utf16LowerBound >= 0,
              sourceRange.utf16UpperBound >= sourceRange.utf16LowerBound,
              ResearchContextValidation.validFingerprint(fingerprint),
              ResearchContextValidation.validFingerprint(binding),
              ResearchContextValidation.validFingerprint(pageDigest) else {
            throw ResearchContextContractError.invalidQuery
        }
        schemaVersion = Self.currentSchemaVersion
        self.clauseID = clauseID
        self.note = note
        self.fingerprint = fingerprint
        self.sourceRange = sourceRange
        self.pageStartUTF8Offset = pageStartUTF8Offset
        self.nextUTF8Offset = nextUTF8Offset
        self.binding = binding
        self.pageDigest = pageDigest
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, clauseID, note, fingerprint, sourceRange,
             pageStartUTF8Offset, nextUTF8Offset, binding, pageDigest
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            clauseID: try container.decode(UUID.self, forKey: .clauseID),
            note: try container.decode(VaultQualifiedNoteID.self, forKey: .note),
            fingerprint: try container.decode(DocumentFingerprint.self, forKey: .fingerprint),
            sourceRange: try container.decode(SearchSourceRange.self, forKey: .sourceRange),
            pageStartUTF8Offset: try container.decode(Int.self, forKey: .pageStartUTF8Offset),
            nextUTF8Offset: try container.decode(Int.self, forKey: .nextUTF8Offset),
            binding: try container.decode(DocumentFingerprint.self, forKey: .binding),
            pageDigest: try container.decode(DocumentFingerprint.self, forKey: .pageDigest)
        )
    }
}

/// A closed query clause. An Agent chooses no provider, source-kind cross
/// product, Run, Triptych, or authorization scope; Application binds those
/// facts after authenticating the request.
public struct ResearchContextClause: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 4
    public static let maximumLimit = 20

    public let schemaVersion: Int
    public let id: UUID
    public let kind: ResearchContextClauseKind
    public let scope: ResearchContextClauseScope
    public let query: String?
    /// Application-derived exact selector for a Run-frozen Note. Agent-authored
    /// discovery continues to use query; a Fidelity inspection packet uses
    /// this vault-qualified identity plus expectedFingerprint so same-path
    /// Notes in different vaults cannot be confused.
    public let note: VaultQualifiedNoteID?
    public let expectedFingerprint: DocumentFingerprint?
    public let sectionHeading: String?
    public let limit: Int
    public let useEligibility: ResearchContextUseEligibility
    public let cursor: ResearchContextPageCursor?

    public init(
        id: UUID = UUID(),
        kind: ResearchContextClauseKind,
        query: String? = nil,
        note: VaultQualifiedNoteID? = nil,
        expectedFingerprint: DocumentFingerprint? = nil,
        sectionHeading: String? = nil,
        limit: Int = 8,
        useEligibility: ResearchContextUseEligibility,
        cursor: ResearchContextPageCursor? = nil
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            id: id,
            kind: kind,
            scope: .triptych,
            query: query,
            note: note,
            expectedFingerprint: expectedFingerprint,
            sectionHeading: sectionHeading,
            limit: limit,
            useEligibility: useEligibility,
            cursor: cursor
        )
    }

    private init(
        schemaVersion: Int,
        id: UUID,
        kind: ResearchContextClauseKind,
        scope: ResearchContextClauseScope,
        query: String?,
        note: VaultQualifiedNoteID?,
        expectedFingerprint: DocumentFingerprint?,
        sectionHeading: String?,
        limit: Int,
        useEligibility: ResearchContextUseEligibility,
        cursor: ResearchContextPageCursor?
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              scope == .triptych,
              (1...Self.maximumLimit).contains(limit) else {
            if schemaVersion != Self.currentSchemaVersion {
                throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
            }
            throw ResearchContextContractError.invalidQuery
        }
        let normalizedQuery = try query.map {
            try ResearchContextValidation.text($0, maximumUTF8Count: 4_096, field: "query")
        }
        let normalizedHeading = try sectionHeading.map {
            try ResearchContextValidation.text($0, maximumUTF8Count: 1_024, field: "sectionHeading")
        }
        let hasQuery = normalizedQuery != nil
        let clauseIsValid: Bool = switch kind {
        case .discoverNote, .inspectRelations, .inspectMetadata, .inspectRecords:
            hasQuery && note == nil && expectedFingerprint == nil
                && normalizedHeading == nil && cursor == nil
        case .readNote:
            ((hasQuery && note == nil && expectedFingerprint == nil)
                || (!hasQuery && note != nil && expectedFingerprint != nil))
                && cursor.map { $0.clauseID == id } != false
        case .inspectMaterials, .inspectResearcherState:
            !hasQuery && note == nil && expectedFingerprint == nil
                && normalizedHeading == nil && cursor == nil
        }
        guard clauseIsValid else { throw ResearchContextContractError.invalidQuery }
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.scope = scope
        self.query = normalizedQuery
        self.note = note
        self.expectedFingerprint = expectedFingerprint
        self.sectionHeading = normalizedHeading
        self.limit = limit
        self.useEligibility = useEligibility
        self.cursor = cursor
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id, kind, scope, query, note
        case expectedFingerprint = "expected_fingerprint"
        case sectionHeading = "section_heading"
        case limit
        case useEligibility = "use_eligibility"
        case cursor
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            id: try container.decode(UUID.self, forKey: .id),
            kind: try container.decode(ResearchContextClauseKind.self, forKey: .kind),
            scope: try container.decode(ResearchContextClauseScope.self, forKey: .scope),
            query: try container.decodeIfPresent(String.self, forKey: .query),
            note: try container.decodeIfPresent(
                VaultQualifiedNoteID.self,
                forKey: .note
            ),
            expectedFingerprint: try container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .expectedFingerprint
            ),
            sectionHeading: try container.decodeIfPresent(String.self, forKey: .sectionHeading),
            limit: try container.decode(Int.self, forKey: .limit),
            useEligibility: try container.decode(ResearchContextUseEligibility.self, forKey: .useEligibility),
            cursor: try container.decodeIfPresent(ResearchContextPageCursor.self, forKey: .cursor)
        )
    }
}

/// Agent-facing request. Run and Triptych authority are deliberately absent:
/// the authenticated Application boundary supplies them before provider work.
public struct ResearchContextRequest: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 4
    public static let maximumClauses = 4

    public let schemaVersion: Int
    public let id: UUID
    public let clauses: [ResearchContextClause]

    public init(id: UUID = UUID(), clauses: [ResearchContextClause]) throws {
        try self.init(schemaVersion: Self.currentSchemaVersion, id: id, clauses: clauses)
    }

    private init(schemaVersion: Int, id: UUID, clauses: [ResearchContextClause]) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              !clauses.isEmpty,
              clauses.count <= Self.maximumClauses,
              Set(clauses.map(\.id)).count == clauses.count else {
            if schemaVersion != Self.currentSchemaVersion {
                throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
            }
            throw ResearchContextContractError.invalidQuery
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.clauses = clauses
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id, clauses
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            id: try container.decode(UUID.self, forKey: .id),
            clauses: try container.decode([ResearchContextClause].self, forKey: .clauses)
        )
    }
}

public struct ResearchContextQuery: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let id: UUID
    public let runID: UUID
    public let triptychID: UUID
    public let clauses: [ResearchContextClause]

    public init(request: ResearchContextRequest, runID: UUID, triptychID: UUID) throws {
        schemaVersion = Self.currentSchemaVersion
        id = request.id
        self.runID = runID
        self.triptychID = triptychID
        clauses = request.clauses
    }

    public func clause(id: UUID) -> ResearchContextClause? {
        clauses.first { $0.id == id }
    }

    /// The digest binds a received cursor to this authenticated query without
    /// copying Run or Triptych identifiers back into the public request.
    public func paginationBinding(for clause: ResearchContextClause) -> DocumentFingerprint {
        let material = [
            id.uuidString.lowercased(),
            runID.uuidString.lowercased(),
            triptychID.uuidString.lowercased(),
            clause.id.uuidString.lowercased(),
            clause.kind.rawValue,
            clause.scope.rawValue,
            clause.query ?? "",
            clause.sectionHeading ?? "",
            String(clause.limit),
            clause.useEligibility.rawValue,
        ].joined(separator: "\u{1F}")
        return DocumentFingerprint(content: material)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, id, runID, triptychID, clauses
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let request = try ResearchContextRequest(
            id: try container.decode(UUID.self, forKey: .id),
            clauses: try container.decode([ResearchContextClause].self, forKey: .clauses)
        )
        try self.init(
            request: request,
            runID: try container.decode(UUID.self, forKey: .runID),
            triptychID: try container.decode(UUID.self, forKey: .triptychID)
        )
    }
}

public enum ResearchContextContentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case searchSnippet = "search_snippet"
    case noteSection = "note_section"
    case noteDocument = "note_document"
    case recordStatement = "record_statement"
    case sourceMaterial = "source_material"
    case researcherState = "researcher_state"
}

/// Ephemeral, typed material data supplied by the existing source and Zotero
/// owners. It is response data only: it creates no source cache or durable
/// Material owner, and it never carries a bookmark, path, or source bytes.
public struct ResearchContextMaterialContent: Codable, Hashable, Sendable {
    public let source: ResearchSourceReference
    public let zoteroBibliographicContext: ZoteroBibliographicContext?

    public init(
        source: ResearchSourceReference,
        zoteroBibliographicContext: ZoteroBibliographicContext? = nil
    ) throws {
        if source.identity.route == .zoteroAttachment,
           let zoteroBibliographicContext {
            guard zoteroBibliographicContext.itemKey
                    == source.identity.zoteroItemKey else {
                throw ResearchContextContractError.invalidResponse
            }
        }
        self.source = source
        self.zoteroBibliographicContext = zoteroBibliographicContext
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case source
        case zoteroBibliographicContext
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            source: try container.decode(
                ResearchSourceReference.self,
                forKey: .source
            ),
            zoteroBibliographicContext: try container.decodeIfPresent(
                ZoteroBibliographicContext.self,
                forKey: .zoteroBibliographicContext
            )
        )
    }
}

/// Exact source bytes represented as their lossless UTF-8 String form. The
/// separate type deliberately avoids the semantic-text trim/control policy.
public struct ResearchContextExactSource: Codable, Hashable, Sendable {
    public static let maximumUTF8Count = 96 * 1_024

    public let content: String
    public let pageDigest: DocumentFingerprint

    public init(content: String) throws {
        guard content.utf8.count <= Self.maximumUTF8Count,
              !content.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw ResearchContextContractError.invalidText("exactSource")
        }
        self.content = content
        pageDigest = DocumentFingerprint(content: content)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case content, pageDigest }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let content = try container.decode(String.self, forKey: .content)
        let pageDigest = try container.decode(DocumentFingerprint.self, forKey: .pageDigest)
        try self.init(content: content)
        guard self.pageDigest == pageDigest else {
            throw ResearchContextContractError.invalidResponse
        }
    }
}

public struct ResearchContextResponseItem: Codable, Hashable, Identifiable, Sendable {
    public static let maximumNoteMatchReasons = 16
    public static let maximumSemanticContentUTF8Count = 2_048

    public var id: UUID { sourceReference.id }

    public let clauseID: UUID
    public let sourceReference: SourceReferenceEnvelope
    public let title: String
    public let contentKind: ResearchContextContentKind
    public let semanticContent: String?
    public let exactSource: ResearchContextExactSource?
    public let materialContent: ResearchContextMaterialContent?
    public let contextUseEligibility: ResearchContextUseEligibility
    /// Exact structured provenance returned by the one Foundation Search
    /// owner. This remains typed data beside source content so a direct
    /// relation or Property match is not flattened into an explanation string.
    public let noteMatchReasons: [NoteSearchMatchReason]

    public init(
        clauseID: UUID,
        sourceReference: SourceReferenceEnvelope,
        title: String,
        contentKind: ResearchContextContentKind,
        semanticContent: String? = nil,
        exactSource: ResearchContextExactSource? = nil,
        materialContent: ResearchContextMaterialContent? = nil,
        contextUseEligibility: ResearchContextUseEligibility,
        noteMatchReasons: [NoteSearchMatchReason] = []
    ) throws {
        let expectsExact = contentKind == .noteSection || contentKind == .noteDocument
        let expectsMaterial = contentKind == .sourceMaterial
        let materialMatchesEnvelope = materialContent.map { material in
            sourceReference.sourceKind == .material
                && sourceReference.owner.materialID == material.source.identity.id
                && sourceReference.owner.stableObjectIdentity
                    == material.source.identity.id.uuidString.lowercased()
                && sourceReference.fingerprint == material.source.fingerprint
                && sourceReference.locator
                    == (try? ResearchContextSourceLocator.materialSource(material.source))
        } ?? false
        guard noteMatchReasons.count <= Self.maximumNoteMatchReasons,
              sourceReference.sourceKind == .note || noteMatchReasons.isEmpty,
              !noteMatchReasons.contains(where: { reason in
                  if case .structured = reason { return true }
                  return false
              }),
              (expectsExact && semanticContent == nil && exactSource != nil
                  && materialContent == nil
                  && sourceReference.locator.kind == .sourceRange)
                  || (expectsMaterial && semanticContent == nil && exactSource == nil
                      && materialMatchesEnvelope)
                  || (!expectsExact && !expectsMaterial && semanticContent != nil
                      && exactSource == nil && materialContent == nil),
              Self.primaryReasonMatchesEnvelope(
                  noteMatchReasons.first,
                  retrievalReason: sourceReference.retrievalReason
              ),
              Self.relationshipTargetsMatchOwner(noteMatchReasons, owner: sourceReference.owner),
              contextUseEligibility == .referenceOnly || sourceReference.currentness == .current else {
            throw ResearchContextContractError.invalidResponse
        }
        self.clauseID = clauseID
        self.sourceReference = sourceReference
        self.title = try ResearchContextValidation.text(title, maximumUTF8Count: 512, field: "title")
        self.contentKind = contentKind
        self.semanticContent = try semanticContent.map {
            try ResearchContextValidation.text(
                $0,
                maximumUTF8Count: Self.maximumSemanticContentUTF8Count,
                field: "semanticContent"
            )
        }
        self.exactSource = exactSource
        self.materialContent = materialContent
        self.contextUseEligibility = contextUseEligibility
        self.noteMatchReasons = noteMatchReasons
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case clauseID, sourceReference, title, contentKind, semanticContent,
             exactSource, materialContent, contextUseEligibility, noteMatchReasons
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            clauseID: try container.decode(UUID.self, forKey: .clauseID),
            sourceReference: try container.decode(SourceReferenceEnvelope.self, forKey: .sourceReference),
            title: try container.decode(String.self, forKey: .title),
            contentKind: try container.decode(ResearchContextContentKind.self, forKey: .contentKind),
            semanticContent: try container.decodeIfPresent(String.self, forKey: .semanticContent),
            exactSource: try container.decodeIfPresent(ResearchContextExactSource.self, forKey: .exactSource),
            materialContent: try container.decodeIfPresent(
                ResearchContextMaterialContent.self,
                forKey: .materialContent
            ),
            contextUseEligibility: try container.decode(ResearchContextUseEligibility.self, forKey: .contextUseEligibility),
            noteMatchReasons: try container.decode([NoteSearchMatchReason].self, forKey: .noteMatchReasons)
        )
    }

    private static func primaryReasonMatchesEnvelope(
        _ reason: NoteSearchMatchReason?,
        retrievalReason: ResearchContextRetrievalReason
    ) -> Bool {
        switch retrievalReason {
        case .directRelation:
            guard let reason else { return false }
            if case .relationship = reason { return true }
            return false
        case .propertyPresence:
            guard let reason else { return false }
            if case .property = reason { return true }
            return false
        case .lexical, .canonicalSummary, .exactRead, .recordSearch,
                .explicitSelection, .researcherState:
            return true
        }
    }

    private static func relationshipTargetsMatchOwner(
        _ reasons: [NoteSearchMatchReason],
        owner: ResearchContextOwnerReference
    ) -> Bool {
        guard reasons.contains(where: { reason in
            if case .relationship = reason { return true }
            return false
        }) else { return true }
        guard owner.kind == .note,
              let vaultID = owner.vaultID,
              let relativePath = owner.relativePath else {
            return false
        }
        let ownerNote = VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: relativePath
        )
        return reasons.allSatisfy { reason in
            guard case .relationship(let relationship) = reason else {
                return true
            }
            return relationship.targetNote == ownerNote
        }
    }
}

public struct ResearchContextClauseOutcome: Codable, Hashable, Sendable {
    public let clauseID: UUID
    public let kind: ResearchContextClauseKind
    public let availability: ResearchContextAvailability
    public let items: [ResearchContextResponseItem]
    public let limitations: [String]
    public let hasMore: Bool
    public let nextCursor: ResearchContextPageCursor?

    public init(
        clause: ResearchContextClause,
        availability: ResearchContextAvailability,
        items: [ResearchContextResponseItem],
        limitations: [String] = [],
        hasMore: Bool = false,
        nextCursor: ResearchContextPageCursor? = nil
    ) throws {
        guard items.count <= clause.limit,
              items.allSatisfy({ $0.clauseID == clause.id && $0.sourceReference.sourceKind == clause.kind.sourceKind }),
              Set(items.map(\.id)).count == items.count,
              !([.unavailable, .invalidQuery].contains(availability) && !items.isEmpty),
              hasMore == (nextCursor != nil),
              (nextCursor.map { $0.clauseID == clause.id && clause.kind == .readNote } != false) else {
            throw ResearchContextContractError.invalidResponse
        }
        clauseID = clause.id
        kind = clause.kind
        self.availability = availability
        self.items = items
        self.limitations = try ResearchContextValidation.texts(
            limitations,
            maximumCount: 16,
            maximumUTF8Count: 512,
            field: "clauseLimitations"
        )
        self.hasMore = hasMore
        self.nextCursor = nextCursor
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case clauseID, kind, availability, items, limitations, hasMore, nextCursor
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let clauseID = try container.decode(UUID.self, forKey: .clauseID)
        let kind = try container.decode(ResearchContextClauseKind.self, forKey: .kind)
        let items = try container.decode([ResearchContextResponseItem].self, forKey: .items)
        let hasMore = try container.decode(Bool.self, forKey: .hasMore)
        let nextCursor = try container.decodeIfPresent(ResearchContextPageCursor.self, forKey: .nextCursor)
        guard items.allSatisfy({ $0.clauseID == clauseID && $0.sourceReference.sourceKind == kind.sourceKind }),
              items.count <= ResearchContextClause.maximumLimit,
              Set(items.map(\.id)).count == items.count,
              hasMore == (nextCursor != nil),
              (nextCursor.map { $0.clauseID == clauseID && kind == .readNote } != false),
              !([.unavailable, .invalidQuery].contains(try container.decode(ResearchContextAvailability.self, forKey: .availability)) && !items.isEmpty) else {
            throw ResearchContextContractError.invalidResponse
        }
        self.clauseID = clauseID
        self.kind = kind
        availability = try container.decode(ResearchContextAvailability.self, forKey: .availability)
        self.items = items
        limitations = try ResearchContextValidation.texts(
            try container.decode([String].self, forKey: .limitations),
            maximumCount: 16,
            maximumUTF8Count: 512,
            field: "clauseLimitations"
        )
        self.hasMore = hasMore
        self.nextCursor = nextCursor
    }
}

public struct ResearchContextResponse: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 4
    /// Leaves a material margin below the 1 MiB local-bridge frame for its
    /// envelope, error fields, and future transport metadata.
    public static let maximumEncodedByteCount = 768 * 1_024

    public let schemaVersion: Int
    public let queryID: UUID
    public let runID: UUID
    public let triptychID: UUID
    public let availability: ResearchContextAvailability
    public let outcomes: [ResearchContextClauseOutcome]
    public let limitations: [String]

    /// Convenience projection only. It is not duplicated in the wire schema.
    public var items: [ResearchContextResponseItem] { outcomes.flatMap(\.items) }

    public init(
        query: ResearchContextQuery,
        outcomes: [ResearchContextClauseOutcome],
        limitations: [String] = []
    ) throws {
        let normalizedLimitations = try ResearchContextValidation.texts(
            limitations,
            maximumCount: 16,
            maximumUTF8Count: 512,
            field: "limitations"
        )
        let availability = Self.combinedAvailability(outcomes.map(\.availability))
        guard outcomes.count == query.clauses.count,
              zip(outcomes, query.clauses).allSatisfy({ outcome, clause in
                  outcome.clauseID == clause.id && outcome.kind == clause.kind
              }),
              Set(Self.items(for: outcomes).map(\.id)).count == Self.items(for: outcomes).count,
              Self.items(for: outcomes).allSatisfy({ item in
                  item.sourceReference.authorizedScope.runID == query.runID
                      && item.sourceReference.owner.triptychID == query.triptychID
              }) else {
            throw ResearchContextContractError.invalidResponse
        }
        schemaVersion = Self.currentSchemaVersion
        queryID = query.id
        runID = query.runID
        triptychID = query.triptychID
        self.availability = availability
        self.outcomes = outcomes
        self.limitations = normalizedLimitations
        try Self.validateEncodedByteCount(
            queryID: query.id,
            runID: query.runID,
            triptychID: query.triptychID,
            availability: availability,
            outcomes: outcomes,
            limitations: normalizedLimitations
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, queryID, runID, triptychID, availability, outcomes, limitations
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let queryID = try container.decode(UUID.self, forKey: .queryID)
        let runID = try container.decode(UUID.self, forKey: .runID)
        let triptychID = try container.decode(UUID.self, forKey: .triptychID)
        let availability = try container.decode(ResearchContextAvailability.self, forKey: .availability)
        let outcomes = try container.decode([ResearchContextClauseOutcome].self, forKey: .outcomes)
        let limitations = try ResearchContextValidation.texts(
            try container.decode([String].self, forKey: .limitations),
            maximumCount: 16,
            maximumUTF8Count: 512,
            field: "limitations"
        )
        guard !outcomes.isEmpty,
              outcomes.count <= ResearchContextRequest.maximumClauses,
              Set(outcomes.map(\.clauseID)).count == outcomes.count,
              Self.combinedAvailability(outcomes.map(\.availability)) == availability,
              Set(Self.items(for: outcomes).map(\.id)).count == Self.items(for: outcomes).count,
              Self.items(for: outcomes).allSatisfy({
                  $0.sourceReference.authorizedScope.runID == runID
                      && $0.sourceReference.owner.triptychID == triptychID
              }) else {
            throw ResearchContextContractError.invalidResponse
        }
        self.schemaVersion = schemaVersion
        self.queryID = queryID
        self.runID = runID
        self.triptychID = triptychID
        self.availability = availability
        self.outcomes = outcomes
        self.limitations = limitations
        try Self.validateEncodedByteCount(
            queryID: queryID,
            runID: runID,
            triptychID: triptychID,
            availability: availability,
            outcomes: outcomes,
            limitations: limitations
        )
    }

    private static func items(for outcomes: [ResearchContextClauseOutcome]) -> [ResearchContextResponseItem] {
        outcomes.flatMap(\.items)
    }

    private static func combinedAvailability(_ values: [ResearchContextAvailability]) -> ResearchContextAvailability {
        guard !values.isEmpty else { return .unavailable }
        if values.contains(.invalidQuery) { return .invalidQuery }
        if values.allSatisfy({ $0 == .current }) { return .current }
        if values.allSatisfy({ $0 == .unavailable }) { return .unavailable }
        if values.contains(.stale) { return .stale }
        return .partial
    }

    private static func validateEncodedByteCount(
        queryID: UUID,
        runID: UUID,
        triptychID: UUID,
        availability: ResearchContextAvailability,
        outcomes: [ResearchContextClauseOutcome],
        limitations: [String]
    ) throws {
        let encoded = try JSONEncoder().encode(ResponseBudgetProjection(
            schemaVersion: Self.currentSchemaVersion,
            queryID: queryID,
            runID: runID,
            triptychID: triptychID,
            availability: availability,
            outcomes: outcomes,
            limitations: limitations
        ))
        guard encoded.count <= Self.maximumEncodedByteCount else {
            throw ResearchContextContractError.invalidResponse
        }
    }

    private struct ResponseBudgetProjection: Encodable {
        let schemaVersion: Int
        let queryID: UUID
        let runID: UUID
        let triptychID: UUID
        let availability: ResearchContextAvailability
        let outcomes: [ResearchContextClauseOutcome]
        let limitations: [String]
    }
}

public enum ContextUseVerificationFact: String, Codable, CaseIterable, Hashable, Sendable {
    case authoritativeOwnerRead = "authoritative_owner_read"
    case revisionMatched = "revision_matched"
    case locatorResolved = "locator_resolved"
}

public struct ContextUseEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID { sourceReference.id }

    public let sourceReference: SourceReferenceEnvelope
    public let verificationFacts: [ContextUseVerificationFact]
    public let testimony: String

    public init(
        sourceReference: SourceReferenceEnvelope,
        verificationFacts: [ContextUseVerificationFact],
        testimony: String
    ) throws {
        guard !verificationFacts.isEmpty,
              Set(verificationFacts).count == verificationFacts.count else {
            throw ResearchContextContractError.invalidContextUseReport
        }
        self.sourceReference = sourceReference
        self.verificationFacts = verificationFacts
        self.testimony = try ResearchContextValidation.text(
            testimony,
            maximumUTF8Count: 2_048,
            field: "testimony"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceReference
        case verificationFacts
        case testimony
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceReference: try container.decode(
                SourceReferenceEnvelope.self,
                forKey: .sourceReference
            ),
            verificationFacts: try container.decode(
                [ContextUseVerificationFact].self,
                forKey: .verificationFacts
            ),
            testimony: try container.decode(String.self, forKey: .testimony)
        )
    }
}

/// Optional, bounded testimony about references actually relied upon. The
/// shape deliberately cannot retain queries, candidates, ranks, provider IDs,
/// prompts, or complete responses.
public struct ContextUseReport: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumEntries = 64

    public let schemaVersion: Int
    public let runID: UUID
    public let triptychID: UUID
    public let entries: [ContextUseEntry]

    public init(runID: UUID, triptychID: UUID, entries: [ContextUseEntry]) throws {
        guard !entries.isEmpty,
              entries.count <= Self.maximumEntries,
              Set(entries.map(\.id)).count == entries.count,
              entries.allSatisfy({ entry in
                  entry.sourceReference.authorizedScope.runID == runID
                      && entry.sourceReference.owner.triptychID == triptychID
              }) else {
            throw ResearchContextContractError.invalidContextUseReport
        }
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.triptychID = triptychID
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case runID
        case triptychID
        case entries
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let runID = try container.decode(UUID.self, forKey: .runID)
        let triptychID = try container.decode(UUID.self, forKey: .triptychID)
        let entries = try container.decode([ContextUseEntry].self, forKey: .entries)
        try self.init(runID: runID, triptychID: triptychID, entries: entries)
    }
}

private enum ResearchContextValidation {
    static func validFingerprint(_ fingerprint: DocumentFingerprint) -> Bool {
        fingerprint.byteCount >= 0
            && fingerprint.sha256.count == 64
            && fingerprint.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
    }

    static func text(
        _ value: String,
        maximumUTF8Count: Int,
        field: String
    ) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.utf8.count <= maximumUTF8Count,
              !normalized.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
              }) else {
            throw ResearchContextContractError.invalidText(field)
        }
        return normalized
    }

    static func texts(
        _ values: [String],
        maximumCount: Int,
        maximumUTF8Count: Int,
        field: String
    ) throws -> [String] {
        guard values.count <= maximumCount else {
            throw ResearchContextContractError.invalidText(field)
        }
        let normalized = try values.map {
            try text($0, maximumUTF8Count: maximumUTF8Count, field: field)
        }
        guard Set(normalized).count == normalized.count else {
            throw ResearchContextContractError.invalidText(field)
        }
        return normalized
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              path.utf8.count <= 1_024,
              !path.hasPrefix("/"),
              !path.hasPrefix("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    static func rejectUnknownKeys<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        allowed: Key.Type
    ) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedKeys = Set(Key.allCases.map(\.stringValue))
        let unknown = container.allKeys.map(\.stringValue).filter {
            !allowedKeys.contains($0)
        }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown Research Context fields: \(unknown.joined(separator: ", "))."
            ))
        }
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}
