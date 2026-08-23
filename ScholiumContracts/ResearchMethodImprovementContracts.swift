import Foundation

/// The exact Skill entry from the frozen context. The Agent may propose or
/// perform at most one target mutation for an explicitly researcher-started
/// improvement Run.
public struct ResearchMethodImprovementTarget: Codable, Hashable, Identifiable,
    Sendable
{
    public let id: String
    public let title: String
    public let source: String
    public let revision: DocumentFingerprint

    public init(
        id: String,
        title: String,
        source: String,
        revision: DocumentFingerprint
    ) throws {
        guard ResearchMethodImprovementValidation.safeText(id, maximum: 4_096),
              ResearchMethodImprovementValidation.safeText(title, maximum: 256),
              source.utf8.count <= 1_048_576,
              revision == DocumentFingerprint(content: source) else {
            throw ResearchMethodImprovementError.invalidContract
        }
        guard id == "primary-method" else {
            throw ResearchMethodImprovementError.invalidContract
        }
        self.id = id
        self.title = title
        self.source = source
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title
        case source, revision
    }

    public init(from decoder: Decoder) throws {
        try ResearchMethodImprovementValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            title: container.decode(String.self, forKey: .title),
            source: container.decode(String.self, forKey: .source),
            revision: container.decode(DocumentFingerprint.self, forKey: .revision)
        )
    }
}

public enum ResearchMethodImprovementDisposition: String, Codable, Hashable,
    Sendable
{
    case replace
    case diagnosedNoChange = "diagnosed_no_change"
    case unavailable
}

/// Agent-authored input. CLI fills every machine revision from the current
/// authenticated improvement context; the researcher never hand-copies them.
public struct ResearchMethodImprovementDraft: Codable, Hashable, Sendable {
    public let targetID: String
    public let disposition: ResearchMethodImprovementDisposition
    public let replacementSource: String?
    public let diagnosis: String

    public init(
        targetID: String,
        disposition: ResearchMethodImprovementDisposition,
        replacementSource: String? = nil,
        diagnosis: String
    ) throws {
        let diagnosis = diagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ResearchMethodImprovementValidation.safeText(
            targetID,
            maximum: 4_096
        ),
        ResearchMethodImprovementValidation.safeText(
            diagnosis,
            maximum: 16_384
        ) else {
            throw ResearchMethodImprovementError.invalidContract
        }
        switch disposition {
        case .replace:
            guard let replacementSource,
                  replacementSource.utf8.count <= 1_048_576 else {
                throw ResearchMethodImprovementError.invalidContract
            }
        case .diagnosedNoChange, .unavailable:
            guard replacementSource == nil else {
                throw ResearchMethodImprovementError.invalidContract
            }
        }
        self.targetID = targetID
        self.disposition = disposition
        self.replacementSource = replacementSource
        self.diagnosis = diagnosis
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case targetID = "target_id"
        case disposition
        case replacementSource = "replacement_source"
        case diagnosis
    }

    public init(from decoder: Decoder) throws {
        try ResearchMethodImprovementValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            targetID: container.decode(String.self, forKey: .targetID),
            disposition: container.decode(
                ResearchMethodImprovementDisposition.self,
                forKey: .disposition
            ),
            replacementSource: container.decodeIfPresent(
                String.self,
                forKey: .replacementSource
            ),
            diagnosis: container.decode(String.self, forKey: .diagnosis)
        )
    }
}

public struct ResearchMethodImprovementSubmission: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let requestID: UUID
    public let feedbackRevision: UUID
    public let expectedResultFingerprint: DocumentFingerprint
    public let targetID: String
    public let expectedTargetRevision: DocumentFingerprint
    public let disposition: ResearchMethodImprovementDisposition
    public let replacementSource: String?
    public let diagnosis: String

    public init(
        requestID: UUID,
        feedbackRevision: UUID,
        expectedResultFingerprint: DocumentFingerprint,
        targetID: String,
        expectedTargetRevision: DocumentFingerprint,
        disposition: ResearchMethodImprovementDisposition,
        replacementSource: String? = nil,
        diagnosis: String
    ) throws {
        _ = try ResearchMethodImprovementDraft(
            targetID: targetID,
            disposition: disposition,
            replacementSource: replacementSource,
            diagnosis: diagnosis
        )
        schemaVersion = Self.currentSchemaVersion
        self.requestID = requestID
        self.feedbackRevision = feedbackRevision
        self.expectedResultFingerprint = expectedResultFingerprint
        self.targetID = targetID
        self.expectedTargetRevision = expectedTargetRevision
        self.disposition = disposition
        self.replacementSource = replacementSource
        self.diagnosis = diagnosis.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    public func contentFingerprint() throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return DocumentFingerprint(data: try encoder.encode(self))
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case requestID = "request_id"
        case feedbackRevision = "feedback_revision"
        case expectedResultFingerprint = "expected_result_fingerprint"
        case targetID = "target_id"
        case expectedTargetRevision = "expected_target_revision"
        case disposition
        case replacementSource = "replacement_source"
        case diagnosis
    }

    public init(from decoder: Decoder) throws {
        try ResearchMethodImprovementValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchMethodImprovementError.unsupportedSchema(version)
        }
        try self.init(
            requestID: container.decode(UUID.self, forKey: .requestID),
            feedbackRevision: container.decode(UUID.self, forKey: .feedbackRevision),
            expectedResultFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .expectedResultFingerprint
            ),
            targetID: container.decode(String.self, forKey: .targetID),
            expectedTargetRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .expectedTargetRevision
            ),
            disposition: container.decode(
                ResearchMethodImprovementDisposition.self,
                forKey: .disposition
            ),
            replacementSource: container.decodeIfPresent(
                String.self,
                forKey: .replacementSource
            ),
            diagnosis: container.decode(String.self, forKey: .diagnosis)
        )
    }
}

public enum ResearchMethodImprovementRunState: String, Codable, Hashable,
    Sendable
{
    case prepared
    case writing
    case completed
    case cancelled
}

/// Machine-local Run evidence. The portable Record continues to own the one
/// researcher comment; this value owns only retry/recovery identity and a
/// single terminal outcome, not a feedback queue or method history.
public struct ResearchMethodImprovementRun: Codable, Hashable, Identifiable,
    Sendable
{
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let parentRecordID: UUID
    public let triptychID: UUID
    public let registrationKey: ResearchSkillRegistrationKey
    public let actionID: ResearchActionID
    public let method: ResearchMethodSnapshot
    public let feedbackRevision: UUID
    public let feedbackText: String
    public let expectedResultFingerprint: DocumentFingerprint
    public let preparedAt: Date
    public let state: ResearchMethodImprovementRunState
    public let submissionFingerprint: DocumentFingerprint?
    public let pendingSubmission: ResearchMethodImprovementSubmission?
    public let receipt: ResearchMethodImprovementReceipt?

    public init(
        id: UUID,
        parentRecordID: UUID,
        triptychID: UUID,
        registrationKey: ResearchSkillRegistrationKey,
        actionID: ResearchActionID,
        method: ResearchMethodSnapshot,
        feedbackRevision: UUID,
        feedbackText: String,
        expectedResultFingerprint: DocumentFingerprint,
        preparedAt: Date = Date(),
        state: ResearchMethodImprovementRunState = .prepared,
        submissionFingerprint: DocumentFingerprint? = nil,
        pendingSubmission: ResearchMethodImprovementSubmission? = nil,
        receipt: ResearchMethodImprovementReceipt? = nil
    ) throws {
        guard method.registration.key == registrationKey,
              method.registration.actionID == actionID,
              method.registration.isEnabled,
              method.primaryMarkdownRevision
                == DocumentFingerprint(content: method.primaryMarkdownSource),
              ResearchMethodImprovementValidation.safeText(
                feedbackText,
                maximum: 16_384
              ),
              preparedAt.timeIntervalSinceReferenceDate.isFinite,
              (state == .writing || state == .completed)
                == (submissionFingerprint != nil),
              (state == .writing) == (pendingSubmission != nil),
              (state == .completed) == (receipt != nil),
              pendingSubmission.map({ submission in
                  submission.feedbackRevision == feedbackRevision
                      && submission.expectedResultFingerprint
                        == expectedResultFingerprint
                      && (try? submission.contentFingerprint())
                        == submissionFingerprint
              }) ?? true,
              receipt?.runID == id || receipt == nil else {
            throw ResearchMethodImprovementError.invalidContract
        }
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.parentRecordID = parentRecordID
        self.triptychID = triptychID
        self.registrationKey = registrationKey
        self.actionID = actionID
        self.method = method
        self.feedbackRevision = feedbackRevision
        self.feedbackText = feedbackText
        self.expectedResultFingerprint = expectedResultFingerprint
        self.preparedAt = preparedAt
        self.state = state
        self.submissionFingerprint = submissionFingerprint
        self.pendingSubmission = pendingSubmission
        self.receipt = receipt
    }

    public func beginning(
        submission: ResearchMethodImprovementSubmission,
        submissionFingerprint: DocumentFingerprint
    ) throws -> Self {
        guard state == .prepared else {
            throw ResearchMethodImprovementError.resultAlreadySubmitted
        }
        return try Self(
            id: id,
            parentRecordID: parentRecordID,
            triptychID: triptychID,
            registrationKey: registrationKey,
            actionID: actionID,
            method: method,
            feedbackRevision: feedbackRevision,
            feedbackText: feedbackText,
            expectedResultFingerprint: expectedResultFingerprint,
            preparedAt: preparedAt,
            state: .writing,
            submissionFingerprint: submissionFingerprint,
            pendingSubmission: submission
        )
    }

    public func completing(
        submissionFingerprint: DocumentFingerprint,
        receipt: ResearchMethodImprovementReceipt
    ) throws -> Self {
        try Self(
            id: id,
            parentRecordID: parentRecordID,
            triptychID: triptychID,
            registrationKey: registrationKey,
            actionID: actionID,
            method: method,
            feedbackRevision: feedbackRevision,
            feedbackText: feedbackText,
            expectedResultFingerprint: expectedResultFingerprint,
            preparedAt: preparedAt,
            state: .completed,
            submissionFingerprint: submissionFingerprint,
            pendingSubmission: nil,
            receipt: receipt
        )
    }

    public func cancelling() throws -> Self {
        guard state == .prepared || state == .writing else {
            throw ResearchMethodImprovementError.runUnavailable
        }
        return try Self(
            id: id,
            parentRecordID: parentRecordID,
            triptychID: triptychID,
            registrationKey: registrationKey,
            actionID: actionID,
            method: method,
            feedbackRevision: feedbackRevision,
            feedbackText: feedbackText,
            expectedResultFingerprint: expectedResultFingerprint,
            preparedAt: preparedAt,
            state: .cancelled
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id
        case parentRecordID = "parent_record_id"
        case triptychID = "triptych_id"
        case registrationKey = "registration_key"
        case actionID = "action_id"
        case method
        case feedbackRevision = "feedback_revision"
        case feedbackText = "feedback_text"
        case expectedResultFingerprint = "expected_result_fingerprint"
        case preparedAt = "prepared_at"
        case state
        case submissionFingerprint = "submission_fingerprint"
        case pendingSubmission = "pending_submission"
        case receipt
    }

    public init(from decoder: Decoder) throws {
        try ResearchMethodImprovementValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchMethodImprovementError.unsupportedSchema(version)
        }
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            parentRecordID: container.decode(UUID.self, forKey: .parentRecordID),
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            registrationKey: container.decode(
                ResearchSkillRegistrationKey.self,
                forKey: .registrationKey
            ),
            actionID: container.decode(ResearchActionID.self, forKey: .actionID),
            method: container.decode(ResearchMethodSnapshot.self, forKey: .method),
            feedbackRevision: container.decode(UUID.self, forKey: .feedbackRevision),
            feedbackText: container.decode(String.self, forKey: .feedbackText),
            expectedResultFingerprint: container.decode(
                DocumentFingerprint.self,
                forKey: .expectedResultFingerprint
            ),
            preparedAt: container.decode(Date.self, forKey: .preparedAt),
            state: container.decode(
                ResearchMethodImprovementRunState.self,
                forKey: .state
            ),
            submissionFingerprint: container.decodeIfPresent(
                DocumentFingerprint.self,
                forKey: .submissionFingerprint
            ),
            pendingSubmission: container.decodeIfPresent(
                ResearchMethodImprovementSubmission.self,
                forKey: .pendingSubmission
            ),
            receipt: container.decodeIfPresent(
                ResearchMethodImprovementReceipt.self,
                forKey: .receipt
            )
        )
    }
}

public struct ResearchMethodImprovementContext: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let run: ResearchRunLocator
    public let parentRecordID: UUID
    public let actionID: ResearchActionID
    public let methodDisplayName: String
    public let feedbackRevision: UUID
    public let feedbackText: String
    public let expectedResultFingerprint: DocumentFingerprint
    public let targets: [ResearchMethodImprovementTarget]

    public init(run: ResearchRunLocator, improvement: ResearchMethodImprovementRun)
        throws
    {
        let primary = try ResearchMethodImprovementTarget(
            id: "primary-method",
            title: improvement.method.registration.displayName,
            source: improvement.method.primaryMarkdownSource,
            revision: improvement.method.primaryMarkdownRevision
        )
        schemaVersion = Self.currentSchemaVersion
        self.run = run
        parentRecordID = improvement.parentRecordID
        actionID = improvement.actionID
        methodDisplayName = improvement.method.registration.displayName
        feedbackRevision = improvement.feedbackRevision
        feedbackText = improvement.feedbackText
        expectedResultFingerprint = improvement.expectedResultFingerprint
        targets = [primary]
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case run
        case parentRecordID = "parent_record_id"
        case actionID = "action_id"
        case methodDisplayName = "method_display_name"
        case feedbackRevision = "feedback_revision"
        case feedbackText = "feedback_text"
        case expectedResultFingerprint = "expected_result_fingerprint"
        case targets
    }

    public init(from decoder: Decoder) throws {
        try ResearchMethodImprovementValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        let methodDisplayName = try container.decode(
            String.self,
            forKey: .methodDisplayName
        )
        let feedbackText = try container.decode(
            String.self,
            forKey: .feedbackText
        )
        let targets = try container.decode(
            [ResearchMethodImprovementTarget].self,
            forKey: .targets
        )
        guard version == Self.currentSchemaVersion,
              ResearchMethodImprovementValidation.safeText(
                methodDisplayName,
                maximum: 256
              ),
              ResearchMethodImprovementValidation.safeText(
                feedbackText,
                maximum: 16_384
              ),
              !targets.isEmpty,
              Set(targets.map(\.id)).count == targets.count else {
            throw ResearchMethodImprovementError.invalidContract
        }
        schemaVersion = version
        run = try container.decode(ResearchRunLocator.self, forKey: .run)
        parentRecordID = try container.decode(UUID.self, forKey: .parentRecordID)
        actionID = try container.decode(ResearchActionID.self, forKey: .actionID)
        self.methodDisplayName = methodDisplayName
        feedbackRevision = try container.decode(UUID.self, forKey: .feedbackRevision)
        self.feedbackText = feedbackText
        expectedResultFingerprint = try container.decode(
            DocumentFingerprint.self,
            forKey: .expectedResultFingerprint
        )
        self.targets = targets
    }
}

public struct ResearchMethodImprovementReceipt: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: UUID
    public let requestID: UUID
    public let disposition: ResearchMethodImprovementDisposition
    public let targetID: String
    public let startingRevision: DocumentFingerprint
    public let endingRevision: DocumentFingerprint
    public let feedbackCleared: Bool
    public let diagnosis: String
    public let completedAt: Date

    public init(
        runID: UUID,
        requestID: UUID,
        disposition: ResearchMethodImprovementDisposition,
        targetID: String,
        startingRevision: DocumentFingerprint,
        endingRevision: DocumentFingerprint,
        feedbackCleared: Bool,
        diagnosis: String,
        completedAt: Date = Date()
    ) throws {
        guard ResearchMethodImprovementValidation.safeText(targetID, maximum: 4_096),
              ResearchMethodImprovementValidation.safeText(
                diagnosis,
                maximum: 16_384
              ),
              completedAt.timeIntervalSinceReferenceDate.isFinite,
              (disposition == .replace || startingRevision == endingRevision)
        else { throw ResearchMethodImprovementError.invalidContract }
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.requestID = requestID
        self.disposition = disposition
        self.targetID = targetID
        self.startingRevision = startingRevision
        self.endingRevision = endingRevision
        self.feedbackCleared = feedbackCleared
        self.diagnosis = diagnosis.trimmingCharacters(in: .whitespacesAndNewlines)
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case requestID = "request_id"
        case disposition
        case targetID = "target_id"
        case startingRevision = "starting_revision"
        case endingRevision = "ending_revision"
        case feedbackCleared = "feedback_cleared"
        case diagnosis
        case completedAt = "completed_at"
    }

    public init(from decoder: Decoder) throws {
        try ResearchMethodImprovementValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchMethodImprovementError.unsupportedSchema(version)
        }
        try self.init(
            runID: container.decode(UUID.self, forKey: .runID),
            requestID: container.decode(UUID.self, forKey: .requestID),
            disposition: container.decode(
                ResearchMethodImprovementDisposition.self,
                forKey: .disposition
            ),
            targetID: container.decode(String.self, forKey: .targetID),
            startingRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .startingRevision
            ),
            endingRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .endingRevision
            ),
            feedbackCleared: container.decode(Bool.self, forKey: .feedbackCleared),
            diagnosis: container.decode(String.self, forKey: .diagnosis),
            completedAt: container.decode(Date.self, forKey: .completedAt)
        )
    }
}

public enum ResearchMethodImprovementError: LocalizedError, Hashable, Sendable {
    case unsupportedSchema(Int)
    case invalidContract
    case runUnavailable
    case feedbackChanged
    case methodChanged
    case resultChanged
    case resultAlreadySubmitted

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            "Unsupported Method improvement schema version \(version)."
        case .invalidContract:
            "The Method improvement contract is invalid."
        case .runUnavailable:
            "The Method improvement Run is unavailable."
        case .feedbackChanged:
            "The Method feedback changed; start a new improvement Run without discarding the current comment."
        case .methodChanged:
            "The selected Skill changed; start a new improvement Run from its current revision."
        case .resultChanged:
            "The source Research Result changed; the improvement Run cannot clear its comment."
        case .resultAlreadySubmitted:
            "This Method improvement Run already has a different final submission."
        }
    }
}

private enum ResearchMethodImprovementValidation {
    static func safeText(_ value: String, maximum: Int) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf8.count <= maximum
            && !trimmed.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
                    && $0 != "\n" && $0 != "\t" && $0 != "\r"
            })
    }

    static func rejectUnknownFields<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        allowed: Key.Type
    ) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let allowedKeys = Set(Key.allCases.map(\.stringValue))
        guard Set(container.allKeys.map(\.stringValue)).isSubset(of: allowedKeys)
        else { throw ResearchMethodImprovementError.invalidContract }
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
