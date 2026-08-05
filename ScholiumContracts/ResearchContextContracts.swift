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

public enum ResearchContextQueryPurpose: String, Codable, CaseIterable, Hashable, Sendable {
    case discover
    case read
    case inspectRelations = "inspect_relations"
    case inspectProperties = "inspect_properties"
    case inspectRecords = "inspect_records"
    case inspectResearcherState = "inspect_researcher_state"
}

/// Agent-facing request. Run and Triptych authority are deliberately absent:
/// the authenticated Application boundary supplies them before any provider
/// work begins, so callers never copy internal IDs or fingerprints.
public struct ResearchContextRequest: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let query: String
    public let sourceKinds: [ResearchContextSourceKind]
    public let purposes: [ResearchContextQueryPurpose]
    public let limit: Int
    public let sectionHeading: String?

    public init(
        id: UUID = UUID(),
        query: String,
        sourceKinds: [ResearchContextSourceKind],
        purposes: [ResearchContextQueryPurpose],
        limit: Int = 20,
        sectionHeading: String? = nil
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            id: id,
            query: query,
            sourceKinds: sourceKinds,
            purposes: purposes,
            limit: limit,
            sectionHeading: sectionHeading
        )
    }

    private init(
        schemaVersion: Int,
        id: UUID,
        query: String,
        sourceKinds: [ResearchContextSourceKind],
        purposes: [ResearchContextQueryPurpose],
        limit: Int,
        sectionHeading: String?
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              !sourceKinds.isEmpty,
              Set(sourceKinds).count == sourceKinds.count,
              !purposes.isEmpty,
              Set(purposes).count == purposes.count,
              (1...ResearchContextQuery.maximumLimit).contains(limit),
              sectionHeading == nil || purposes == [.read] else {
            if schemaVersion != Self.currentSchemaVersion {
                throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
            }
            throw ResearchContextContractError.invalidQuery
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.query = try ResearchContextValidation.text(
            query,
            maximumUTF8Count: 4_096,
            field: "query"
        )
        self.sourceKinds = sourceKinds
        self.purposes = purposes
        self.limit = limit
        self.sectionHeading = try sectionHeading.map {
            try ResearchContextValidation.text(
                $0,
                maximumUTF8Count: 1_024,
                field: "sectionHeading"
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case id
        case query
        case sourceKinds
        case purposes
        case limit
        case sectionHeading
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            id: try container.decode(UUID.self, forKey: .id),
            query: try container.decode(String.self, forKey: .query),
            sourceKinds: try container.decode(
                [ResearchContextSourceKind].self,
                forKey: .sourceKinds
            ),
            purposes: try container.decode(
                [ResearchContextQueryPurpose].self,
                forKey: .purposes
            ),
            limit: try container.decode(Int.self, forKey: .limit),
            sectionHeading: try container.decodeIfPresent(
                String.self,
                forKey: .sectionHeading
            )
        )
    }
}

public struct ResearchContextQuery: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumLimit = 100

    public let schemaVersion: Int
    public let id: UUID
    public let runID: UUID
    public let triptychID: UUID
    public let query: String
    public let sourceKinds: [ResearchContextSourceKind]
    public let purposes: [ResearchContextQueryPurpose]
    public let limit: Int
    public let sectionHeading: String?

    public init(
        id: UUID = UUID(),
        runID: UUID,
        triptychID: UUID,
        query: String,
        sourceKinds: [ResearchContextSourceKind],
        purposes: [ResearchContextQueryPurpose],
        limit: Int = 20,
        sectionHeading: String? = nil
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            id: id,
            runID: runID,
            triptychID: triptychID,
            query: query,
            sourceKinds: sourceKinds,
            purposes: purposes,
            limit: limit,
            sectionHeading: sectionHeading
        )
    }

    public init(
        request: ResearchContextRequest,
        runID: UUID,
        triptychID: UUID
    ) throws {
        try self.init(
            id: request.id,
            runID: runID,
            triptychID: triptychID,
            query: request.query,
            sourceKinds: request.sourceKinds,
            purposes: request.purposes,
            limit: request.limit,
            sectionHeading: request.sectionHeading
        )
    }

    private init(
        schemaVersion: Int,
        id: UUID,
        runID: UUID,
        triptychID: UUID,
        query: String,
        sourceKinds: [ResearchContextSourceKind],
        purposes: [ResearchContextQueryPurpose],
        limit: Int,
        sectionHeading: String?
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              !sourceKinds.isEmpty,
              Set(sourceKinds).count == sourceKinds.count,
              !purposes.isEmpty,
              Set(purposes).count == purposes.count,
              (1...Self.maximumLimit).contains(limit),
              sectionHeading == nil || purposes == [.read] else {
            if schemaVersion != Self.currentSchemaVersion {
                throw ResearchContextContractError.unsupportedSchemaVersion(schemaVersion)
            }
            throw ResearchContextContractError.invalidQuery
        }
        self.schemaVersion = schemaVersion
        self.id = id
        self.runID = runID
        self.triptychID = triptychID
        self.query = try ResearchContextValidation.text(
            query,
            maximumUTF8Count: 4_096,
            field: "query"
        )
        self.sourceKinds = sourceKinds
        self.purposes = purposes
        self.limit = limit
        self.sectionHeading = try sectionHeading.map {
            try ResearchContextValidation.text(
                $0,
                maximumUTF8Count: 1_024,
                field: "sectionHeading"
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case id
        case runID
        case triptychID
        case query
        case sourceKinds
        case purposes
        case limit
        case sectionHeading
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            id: try container.decode(UUID.self, forKey: .id),
            runID: try container.decode(UUID.self, forKey: .runID),
            triptychID: try container.decode(UUID.self, forKey: .triptychID),
            query: try container.decode(String.self, forKey: .query),
            sourceKinds: try container.decode(
                [ResearchContextSourceKind].self,
                forKey: .sourceKinds
            ),
            purposes: try container.decode(
                [ResearchContextQueryPurpose].self,
                forKey: .purposes
            ),
            limit: try container.decode(Int.self, forKey: .limit),
            sectionHeading: try container.decodeIfPresent(
                String.self,
                forKey: .sectionHeading
            )
        )
    }
}

public enum ResearchContextContentKind: String, Codable, CaseIterable, Hashable, Sendable {
    case searchSnippet = "search_snippet"
    case noteSection = "note_section"
    case noteDocument = "note_document"
    case recordStatement = "record_statement"
    case materialExcerpt = "material_excerpt"
    case researcherState = "researcher_state"
}

public struct ResearchContextResponseItem: Codable, Hashable, Identifiable, Sendable {
    public static let maximumNoteMatchReasons = 32

    public var id: UUID { sourceReference.id }

    public let sourceReference: SourceReferenceEnvelope
    public let title: String
    public let contentKind: ResearchContextContentKind
    public let content: String
    /// Exact structured provenance returned by the one Foundation Search
    /// owner. This remains typed data beside source content so a direct
    /// relation or Property match is not flattened into an explanation string.
    public let noteMatchReasons: [NoteSearchMatchReason]

    public init(
        sourceReference: SourceReferenceEnvelope,
        title: String,
        contentKind: ResearchContextContentKind,
        content: String,
        noteMatchReasons: [NoteSearchMatchReason] = []
    ) throws {
        guard noteMatchReasons.count <= Self.maximumNoteMatchReasons,
              sourceReference.sourceKind == .note || noteMatchReasons.isEmpty,
              Self.primaryReasonMatchesEnvelope(
                  noteMatchReasons.first,
                  retrievalReason: sourceReference.retrievalReason
              ),
              Self.relationshipTargetsMatchOwner(
                  noteMatchReasons,
                  owner: sourceReference.owner
              ) else {
            throw ResearchContextContractError.invalidResponse
        }
        self.sourceReference = sourceReference
        self.title = try ResearchContextValidation.text(
            title,
            maximumUTF8Count: 1_024,
            field: "title"
        )
        self.contentKind = contentKind
        self.content = try ResearchContextValidation.text(
            content,
            maximumUTF8Count: 262_144,
            field: "content"
        )
        self.noteMatchReasons = noteMatchReasons
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceReference
        case title
        case contentKind
        case content
        case noteMatchReasons
    }

    public init(from decoder: Decoder) throws {
        try ResearchContextValidation.rejectUnknownKeys(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceReference: try container.decode(
                SourceReferenceEnvelope.self,
                forKey: .sourceReference
            ),
            title: try container.decode(String.self, forKey: .title),
            contentKind: try container.decode(
                ResearchContextContentKind.self,
                forKey: .contentKind
            ),
            content: try container.decode(String.self, forKey: .content),
            noteMatchReasons: try container.decode(
                [NoteSearchMatchReason].self,
                forKey: .noteMatchReasons
            )
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

public struct ResearchContextResponse: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let queryID: UUID
    public let runID: UUID
    public let triptychID: UUID
    public let availability: ResearchContextAvailability
    public let items: [ResearchContextResponseItem]
    public let limitations: [String]

    public init(
        query: ResearchContextQuery,
        availability: ResearchContextAvailability,
        items: [ResearchContextResponseItem],
        limitations: [String] = []
    ) throws {
        guard items.count <= query.limit,
              items.allSatisfy({ item in
                  item.sourceReference.authorizedScope.runID == query.runID
                      && item.sourceReference.owner.triptychID == query.triptychID
                      && query.sourceKinds.contains(item.sourceReference.sourceKind)
              }),
              Set(items.map(\.id)).count == items.count,
              !([.unavailable, .invalidQuery].contains(availability) && !items.isEmpty) else {
            throw ResearchContextContractError.invalidResponse
        }
        self.schemaVersion = Self.currentSchemaVersion
        queryID = query.id
        runID = query.runID
        triptychID = query.triptychID
        self.availability = availability
        self.items = items
        self.limitations = try ResearchContextValidation.texts(
            limitations,
            maximumCount: 32,
            maximumUTF8Count: 1_024,
            field: "limitations"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case queryID
        case runID
        case triptychID
        case availability
        case items
        case limitations
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
        let availability = try container.decode(
            ResearchContextAvailability.self,
            forKey: .availability
        )
        let items = try container.decode(
            [ResearchContextResponseItem].self,
            forKey: .items
        )
        let limitations = try ResearchContextValidation.texts(
            try container.decode([String].self, forKey: .limitations),
            maximumCount: 32,
            maximumUTF8Count: 1_024,
            field: "limitations"
        )
        guard items.count <= ResearchContextQuery.maximumLimit,
              Set(items.map(\.id)).count == items.count,
              items.allSatisfy({
                  $0.sourceReference.authorizedScope.runID == runID
                      && $0.sourceReference.owner.triptychID == triptychID
              }),
              !([.unavailable, .invalidQuery].contains(availability) && !items.isEmpty) else {
            throw ResearchContextContractError.invalidResponse
        }
        self.schemaVersion = schemaVersion
        self.queryID = queryID
        self.runID = runID
        self.triptychID = triptychID
        self.availability = availability
        self.items = items
        self.limitations = limitations
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
