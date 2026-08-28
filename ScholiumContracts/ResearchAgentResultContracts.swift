import Foundation

public enum ResearchAgentResultDisposition: String, Codable, Hashable, Sendable {
    case completed
    case blocked
}

/// Strict Agent-facing payload. It contains only academic judgments and
/// optional Action-specific evidence. Run identity, timestamps, revisions,
/// reading history, actual writes, recovery, and completion state are
/// Application-owned.
public struct ResearchAgentResultSubmission: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let recordTitle: ResearchRecordTitle
    public let disposition: ResearchAgentResultDisposition
    public let academicResults: ResearchAcademicFieldValues
    public let fidelityOutcomes: [FidelityCheckOutcome]
    public let literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?

    public init(
        recordTitle: ResearchRecordTitle,
        disposition: ResearchAgentResultDisposition = .completed,
        academicResults: ResearchAcademicFieldValues,
        fidelityOutcomes: [FidelityCheckOutcome] = [],
        literatureRecommendations: [ResearchLiteratureRecommendationSubmission]? = nil
    ) throws {
        guard literatureRecommendations.map({ $0.count <= 256 }) ?? true else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        schemaVersion = Self.currentSchemaVersion
        self.recordTitle = recordTitle
        self.disposition = disposition
        self.academicResults = academicResults
        self.fidelityOutcomes = fidelityOutcomes
        self.literatureRecommendations = literatureRecommendations
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case recordTitle = "record_title"
        case disposition
        case academicResults = "academic_results"
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
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let runID: UUID
    public let submissionFingerprint: DocumentFingerprint
    public let recordTitle: ResearchRecordTitle
    public let disposition: ResearchAgentResultDisposition
    public let academicResults: ResearchAcademicFieldValues
    public let fidelityOutcomes: [FidelityCheckOutcome]
    public let literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?
    public let submittedAt: Date

    public init(
        runID: UUID,
        submissionFingerprint: DocumentFingerprint,
        recordTitle: ResearchRecordTitle,
        disposition: ResearchAgentResultDisposition,
        academicResults: ResearchAcademicFieldValues,
        fidelityOutcomes: [FidelityCheckOutcome],
        literatureRecommendations: [ResearchLiteratureRecommendationSubmission]?,
        submittedAt: Date
    ) throws {
        let fingerprintScalars = submissionFingerprint.sha256.unicodeScalars
        guard fingerprintScalars.count == 64,
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
    case unverified
}

/// Minimal acknowledgement returned to an authenticated Agent. Machine IDs,
/// fingerprints, paths, capabilities, and recovery internals remain owned by
/// Scholium and are deliberately absent from this receipt.
public struct ResearchAgentResultReceipt: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public let disposition: ResearchAgentResultDisposition
    public let state: ResearchAgentResultFinalizationState
    public let recordFormed: Bool
    public let message: String

    public init(
        disposition: ResearchAgentResultDisposition,
        state: ResearchAgentResultFinalizationState,
        recordFormed: Bool,
        message: String
    ) throws {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty,
              message.utf8.count <= 1_024,
              !message.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw ResearchAgentResultContractError.invalidSubmission
        }
        schemaVersion = Self.currentSchemaVersion
        self.disposition = disposition
        self.state = state
        self.recordFormed = recordFormed
        self.message = message
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case disposition, state
        case recordFormed = "record_formed"
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
            message: container.decode(String.self, forKey: .message)
        )
    }
}

public enum ResearchAgentResultContractError: LocalizedError, Hashable, Sendable,
    AgentCommandErrorCodeProviding
{
    case unsupportedSchemaVersion
    case invalidSubmission
    case fidelityOutcomesNotPermitted(ResearchActionID)
    case resultAlreadySubmitted

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            "The Agent Result schema version is unsupported."
        case .invalidSubmission:
            "The Agent Result does not match its bounded contract."
        case .fidelityOutcomesNotPermitted(let actionID):
            "The Agent Result field fidelity_outcomes is reserved for Check Fidelity and must be empty for the \(actionID.rawValue) Action. If its Method performed a bounded self-check, record the relevant limits in the academic Result fields or limitations, then resubmit the same Run."
        case .resultAlreadySubmitted:
            "A different Agent Result is already attached to this Run."
        }
    }

    public var agentCommandErrorCode: String { "invalid_request" }

    public var agentCommandRecovery: AgentOperationRecovery? {
        switch self {
        case .resultAlreadySubmitted:
            AgentOperationRecovery(
                safeToRetry: false,
                mustReuseRequestIdentity: true,
                nextStep: .inspectOriginalRequestState
            )
        case .unsupportedSchemaVersion, .invalidSubmission,
             .fidelityOutcomesNotPermitted:
            AgentOperationRecovery(
                safeToRetry: true,
                mustReuseRequestIdentity: true,
                nextStep: .correctRequest
            )
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
