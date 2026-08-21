import Foundation

public enum ResearchAgentResultDisposition: String, Codable, Hashable, Sendable {
    case completed
    case blocked
}

/// Agent testimony that one source reference actually affected the academic
/// result. Verification facts are deliberately absent; Scholium establishes
/// them against the current authoritative owner before persistence.
public struct ResearchContextUseClaim: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID { sourceReference.id }

    public let sourceReference: SourceReferenceEnvelope
    public let testimony: String

    public init(
        sourceReference: SourceReferenceEnvelope,
        testimony: String
    ) throws {
        let testimony = testimony.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !testimony.isEmpty,
              testimony.utf8.count <= 2_048,
              !testimony.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
                      && $0 != "\n" && $0 != "\t"
              }) else {
            throw ResearchAgentResultContractError.invalidContextUse
        }
        self.sourceReference = sourceReference
        self.testimony = testimony
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceReference = "source_reference"
        case testimony
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentResultCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sourceReference: container.decode(
                SourceReferenceEnvelope.self,
                forKey: .sourceReference
            ),
            testimony: container.decode(String.self, forKey: .testimony)
        )
    }
}

/// Strict Agent-facing payload. It contains only academic judgments and
/// explicit source-use testimony; Run identity, timestamps, revisions,
/// actual writes, recovery, and completion state are Application-owned.
public struct ResearchAgentResultSubmission: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let recordTitle: ResearchRecordTitle
    public let disposition: ResearchAgentResultDisposition
    public let academicResults: ResearchAcademicFieldValues
    public let contextUseClaims: [ResearchContextUseClaim]
    public let fidelityOutcomes: [FidelityCheckOutcome]
    public let literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?

    public init(
        recordTitle: ResearchRecordTitle,
        disposition: ResearchAgentResultDisposition = .completed,
        academicResults: ResearchAcademicFieldValues,
        contextUseClaims: [ResearchContextUseClaim] = [],
        fidelityOutcomes: [FidelityCheckOutcome] = [],
        literatureRecommendations: [ResearchLiteratureRecommendationSubmission]? = nil
    ) throws {
        guard contextUseClaims.count <= ContextUseReport.maximumEntries,
              Set(contextUseClaims.map(\.id)).count == contextUseClaims.count,
              literatureRecommendations.map({ $0.count <= 256 }) ?? true else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        schemaVersion = Self.currentSchemaVersion
        self.recordTitle = recordTitle
        self.disposition = disposition
        self.academicResults = academicResults
        self.contextUseClaims = contextUseClaims
        self.fidelityOutcomes = fidelityOutcomes
        self.literatureRecommendations = literatureRecommendations
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case recordTitle = "record_title"
        case disposition
        case academicResults = "academic_results"
        case contextUseClaims = "context_use_claims"
        case fidelityOutcomes = "fidelity_outcomes"
        case literatureRecommendations = "literature_recommendations"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentResultCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentResultContractError.unsupportedSchemaVersion
        }
        try self.init(
            recordTitle: container.decode(ResearchRecordTitle.self, forKey: .recordTitle),
            disposition: container.decode(
                ResearchAgentResultDisposition.self,
                forKey: .disposition
            ),
            academicResults: container.decode(
                ResearchAcademicFieldValues.self,
                forKey: .academicResults
            ),
            contextUseClaims: container.decode(
                [ResearchContextUseClaim].self,
                forKey: .contextUseClaims
            ),
            fidelityOutcomes: container.decode(
                [FidelityCheckOutcome].self,
                forKey: .fidelityOutcomes
            ),
            literatureRecommendations: container.decodeIfPresent(
                [ResearchLiteratureRecommendationSubmission].self,
                forKey: .literatureRecommendations
            )
        )
    }

    public func contentFingerprint() throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(self))
    }
}

/// One normalized Run-owned result payload. This is temporary machine state
/// until all started writes are known and one portable Record is finalized.
public struct ResearchRunResultPayload: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let runID: UUID
    public let submissionFingerprint: DocumentFingerprint
    public let recordTitle: ResearchRecordTitle
    public let disposition: ResearchAgentResultDisposition
    public let academicResults: ResearchAcademicFieldValues
    public let contextUseReport: ContextUseReport?
    public let fidelityOutcomes: [FidelityCheckOutcome]
    public let literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?
    public let submittedAt: Date

    public init(
        runID: UUID,
        submissionFingerprint: DocumentFingerprint,
        recordTitle: ResearchRecordTitle,
        disposition: ResearchAgentResultDisposition,
        academicResults: ResearchAcademicFieldValues,
        contextUseReport: ContextUseReport?,
        fidelityOutcomes: [FidelityCheckOutcome],
        literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?,
        submittedAt: Date
    ) throws {
        let fingerprintScalars = submissionFingerprint.sha256.unicodeScalars
        guard contextUseReport.map({ $0.runID == runID }) ?? true,
              fingerprintScalars.count == 64,
              fingerprintScalars.allSatisfy({
                  (48...57).contains(Int($0.value))
                      || (97...102).contains(Int($0.value))
              }),
              submissionFingerprint.byteCount >= 0,
              literatureRecommendations.map({ $0.count <= 256 }) ?? true,
              submittedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.submissionFingerprint = submissionFingerprint
        self.recordTitle = recordTitle
        self.disposition = disposition
        self.academicResults = academicResults
        self.contextUseReport = contextUseReport
        self.fidelityOutcomes = fidelityOutcomes
        self.literatureRecommendations = literatureRecommendations
        self.submittedAt = submittedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case submissionFingerprint = "submission_fingerprint"
        case recordTitle = "record_title"
        case disposition
        case academicResults = "academic_results"
        case contextUseReport = "context_use_report"
        case fidelityOutcomes = "fidelity_outcomes"
        case literatureRecommendations = "literature_recommendations"
        case submittedAt = "submitted_at"
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentResultCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentResultContractError.unsupportedSchemaVersion
        }
        try self.init(
            runID: container.decode(UUID.self, forKey: .runID),
            submissionFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .submissionFingerprint
            ),
            recordTitle: container.decode(ResearchRecordTitle.self, forKey: .recordTitle),
            disposition: container.decode(
                ResearchAgentResultDisposition.self,
                forKey: .disposition
            ),
            academicResults: container.decode(
                ResearchAcademicFieldValues.self,
                forKey: .academicResults
            ),
            contextUseReport: container.decodeIfPresent(
                ContextUseReport.self,
                forKey: .contextUseReport
            ),
            fidelityOutcomes: container.decode(
                [FidelityCheckOutcome].self,
                forKey: .fidelityOutcomes
            ),
            literatureRecommendations: container.decodeIfPresent(
                [ResearchLiteratureRecommendationSubmission].self,
                forKey: .literatureRecommendations
            ),
            submittedAt: container.decode(Date.self, forKey: .submittedAt)
        )
    }
}

public enum ResearchAgentResultFinalizationState: String, Codable, Hashable, Sendable {
    case finalized
    case awaitingFidelity = "awaiting_fidelity"
    case unverified
}

/// Minimal acknowledgement returned to an authenticated Agent. Machine IDs,
/// fingerprints, paths, capabilities, and recovery internals remain owned by
/// Scholium and are deliberately absent from this receipt.
public struct ResearchAgentResultReceipt: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let disposition: ResearchAgentResultDisposition
    public let state: ResearchAgentResultFinalizationState
    public let recordFormed: Bool
    /// Present only when completing an automatic Fidelity child also advanced
    /// its lineage-bound parent Result.
    public let parentState: ResearchAgentResultFinalizationState?
    public let parentRecordFormed: Bool?
    public let message: String

    public init(
        disposition: ResearchAgentResultDisposition,
        state: ResearchAgentResultFinalizationState,
        recordFormed: Bool,
        parentState: ResearchAgentResultFinalizationState? = nil,
        parentRecordFormed: Bool? = nil,
        message: String
    ) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              message.utf8.count <= 1_024,
              !message.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }),
              (state == .awaitingFidelity) == !recordFormed,
              (parentState == nil) == (parentRecordFormed == nil),
              parentState.map({
                  ($0 == .awaitingFidelity) == (parentRecordFormed == false)
              }) ?? true else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        schemaVersion = Self.currentSchemaVersion
        self.disposition = disposition
        self.state = state
        self.recordFormed = recordFormed
        self.parentState = parentState
        self.parentRecordFormed = parentRecordFormed
        self.message = message
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case disposition, state
        case recordFormed = "record_formed"
        case parentState = "parent_state"
        case parentRecordFormed = "parent_record_formed"
        case message
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentResultCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentResultContractError.unsupportedSchemaVersion
        }
        try self.init(
            disposition: container.decode(
                ResearchAgentResultDisposition.self,
                forKey: .disposition
            ),
            state: container.decode(
                ResearchAgentResultFinalizationState.self,
                forKey: .state
            ),
            recordFormed: container.decode(Bool.self, forKey: .recordFormed),
            parentState: container.decodeIfPresent(
                ResearchAgentResultFinalizationState.self,
                forKey: .parentState
            ),
            parentRecordFormed: container.decodeIfPresent(
                Bool.self,
                forKey: .parentRecordFormed
            ),
            message: container.decode(String.self, forKey: .message)
        )
    }
}

/// Receipt for attaching an exact final-revision Fidelity child to the
/// authenticated parent Session. The Session secret remains in the CLI's
/// protected store; only the new opaque child locator crosses ordinary output.
public struct ResearchAgentFidelityPreparationReceipt: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let childRun: ResearchRunLocator?
    public let childState: ResearchActionRunState
    public let parentState: ResearchAgentResultFinalizationState
    public let parentRecordFormed: Bool
    public let message: String

    public init(
        childRun: ResearchRunLocator?,
        childState: ResearchActionRunState,
        parentState: ResearchAgentResultFinalizationState,
        parentRecordFormed: Bool,
        message: String
    ) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let childIsActive = childState == .prepared
        guard childIsActive == (childRun != nil),
              childIsActive || [.complete, .unverified].contains(childState),
              (parentState == .awaitingFidelity) == !parentRecordFormed,
              !message.isEmpty,
              message.utf8.count <= 1_024,
              !message.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        schemaVersion = Self.currentSchemaVersion
        self.childRun = childRun
        self.childState = childState
        self.parentState = parentState
        self.parentRecordFormed = parentRecordFormed
        self.message = message
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case childRun = "child_run"
        case childState = "child_state"
        case parentState = "parent_state"
        case parentRecordFormed = "parent_record_formed"
        case message
    }

    public init(from decoder: Decoder) throws {
        try ResearchAgentResultCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchAgentResultContractError.unsupportedSchemaVersion
        }
        try self.init(
            childRun: container.decodeIfPresent(
                ResearchRunLocator.self,
                forKey: .childRun
            ),
            childState: container.decode(
                ResearchActionRunState.self,
                forKey: .childState
            ),
            parentState: container.decode(
                ResearchAgentResultFinalizationState.self,
                forKey: .parentState
            ),
            parentRecordFormed: container.decode(
                Bool.self,
                forKey: .parentRecordFormed
            ),
            message: container.decode(String.self, forKey: .message)
        )
    }
}

public enum ResearchAgentResultContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion
    case invalidSubmission
    case invalidContextUse
    case resultAlreadySubmitted

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            "The Agent Result schema version is unsupported."
        case .invalidSubmission:
            "The Agent Result does not match its bounded contract."
        case .invalidContextUse:
            "The Context Use claim is invalid or outside this Run."
        case .resultAlreadySubmitted:
            "A different Agent Result is already attached to this Run."
        }
    }
}

private enum ResearchAgentResultCoding {
    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: [String]
    ) throws {
        let container = try decoder.container(
            keyedBy: ResearchAgentResultAnyCodingKey.self
        )
        let allowed = Set(allowed)
        guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
    }
}

private struct ResearchAgentResultAnyCodingKey: CodingKey {
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
