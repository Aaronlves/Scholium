import Foundation

public enum ResearchRecordContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchema(Int)
    case invalidRecord
    case invalidQuestion
    case invalidSubmitter
    case invalidStep
    case invalidCorrection
    case invalidNoteReference

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            "The Research Record schema is unsupported."
        case .invalidRecord:
            "The Research Record is invalid."
        case .invalidQuestion:
            "The Research Record question is invalid."
        case .invalidSubmitter:
            "The Research Record Agent attribution is invalid."
        case .invalidStep:
            "The Research Record step is invalid."
        case .invalidCorrection:
            "The Research Record correction is invalid."
        case .invalidNoteReference:
            "The Research Record Note reference is invalid."
        }
    }
}

public enum ResearchRecordSubmitterKind: String, Codable, Hashable, Sendable {
    case externalAgent = "external_agent"
}

public struct ResearchRecordSubmitter: Codable, Hashable, Sendable {
    public static let maximumDisplayNameUTF8Count = 256

    public let kind: ResearchRecordSubmitterKind
    public let displayName: String

    public init(displayName: String) throws {
        let displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty,
              displayName.utf8.count <= Self.maximumDisplayNameUTF8Count,
              ResearchRecordValidation.isSingleLine(displayName) else {
            throw ResearchRecordContractError.invalidSubmitter
        }
        kind = .externalAgent
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case displayName = "display_name"
    }

    public init(from decoder: Decoder) throws {
        try ResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(ResearchRecordSubmitterKind.self, forKey: .kind)
            == .externalAgent else {
            throw ResearchRecordContractError.invalidSubmitter
        }
        try self.init(displayName: container.decode(String.self, forKey: .displayName))
    }
}

public enum ResearchRecordNoteRelation: String, Codable, Hashable, Sendable {
    case basis
    case modified
}

public struct ResearchRecordNoteReference: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let relation: ResearchRecordNoteRelation
    public let revision: DocumentFingerprint

    public init(
        noteID: UUID,
        relation: ResearchRecordNoteRelation,
        revision: DocumentFingerprint
    ) throws {
        guard ResearchRecordValidation.isValidFingerprint(revision) else {
            throw ResearchRecordContractError.invalidNoteReference
        }
        self.noteID = noteID
        self.relation = relation
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID = "note_id"
        case relation, revision
    }

    public init(from decoder: Decoder) throws {
        try ResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            noteID: ResearchRecordValidation.decodeUUID(container, forKey: .noteID),
            relation: container.decode(ResearchRecordNoteRelation.self, forKey: .relation),
            revision: container.decode(StrictResearchRecordFingerprint.self, forKey: .revision)
                .value
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try ResearchRecordValidation.encodeUUID(noteID, into: &container, forKey: .noteID)
        try container.encode(relation, forKey: .relation)
        try container.encode(StrictResearchRecordFingerprint(revision), forKey: .revision)
    }
}

public struct ResearchRecordCorrection: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let correctedAt: Date
    public let submittedBy: ResearchRecordSubmitter
    public let bodyMarkdown: String
    public let revisesStepIDs: [UUID]
    public let noteReferences: [ResearchRecordNoteReference]

    public init(
        id: UUID = UUID(),
        correctedAt: Date = Date(),
        submittedBy: ResearchRecordSubmitter,
        bodyMarkdown: String,
        revisesStepIDs: [UUID] = [],
        noteReferences: [ResearchRecordNoteReference] = []
    ) throws {
        let bodyMarkdown = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ResearchRecordValidation.isValidBody(bodyMarkdown),
              Set(revisesStepIDs).count == revisesStepIDs.count,
              ResearchRecordValidation.hasUniqueReferences(noteReferences) else {
            throw ResearchRecordContractError.invalidCorrection
        }
        self.id = id
        self.correctedAt = correctedAt
        self.submittedBy = submittedBy
        self.bodyMarkdown = bodyMarkdown
        self.revisesStepIDs = revisesStepIDs
        self.noteReferences = noteReferences
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "correction_id"
        case correctedAt = "corrected_at"
        case submittedBy = "submitted_by"
        case bodyMarkdown = "body_markdown"
        case revisesStepIDs = "revises_step_ids"
        case noteReferences = "note_references"
    }

    public init(from decoder: Decoder) throws {
        try ResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: ResearchRecordValidation.decodeUUID(container, forKey: .id),
            correctedAt: container.decode(Date.self, forKey: .correctedAt),
            submittedBy: container.decode(ResearchRecordSubmitter.self, forKey: .submittedBy),
            bodyMarkdown: container.decode(String.self, forKey: .bodyMarkdown),
            revisesStepIDs: ResearchRecordValidation.decodeUUIDs(
                container,
                forKey: .revisesStepIDs
            ),
            noteReferences: container.decode(
                [ResearchRecordNoteReference].self,
                forKey: .noteReferences
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try ResearchRecordValidation.encodeUUID(id, into: &container, forKey: .id)
        try container.encode(correctedAt, forKey: .correctedAt)
        try container.encode(submittedBy, forKey: .submittedBy)
        try container.encode(bodyMarkdown, forKey: .bodyMarkdown)
        try ResearchRecordValidation.encodeUUIDs(
            revisesStepIDs,
            into: &container,
            forKey: .revisesStepIDs
        )
        try container.encode(noteReferences, forKey: .noteReferences)
    }
}

public struct ResearchRecordStep: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let recordedAt: Date
    public let submittedBy: ResearchRecordSubmitter
    public let bodyMarkdown: String
    public let revisesStepIDs: [UUID]
    public let noteReferences: [ResearchRecordNoteReference]
    public let corrections: [ResearchRecordCorrection]

    public var currentBodyMarkdown: String {
        corrections.last?.bodyMarkdown ?? bodyMarkdown
    }

    public var currentRevisesStepIDs: [UUID] {
        corrections.last?.revisesStepIDs ?? revisesStepIDs
    }

    public var currentNoteReferences: [ResearchRecordNoteReference] {
        corrections.last?.noteReferences ?? noteReferences
    }

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        submittedBy: ResearchRecordSubmitter,
        bodyMarkdown: String,
        revisesStepIDs: [UUID] = [],
        noteReferences: [ResearchRecordNoteReference] = [],
        corrections: [ResearchRecordCorrection] = []
    ) throws {
        let bodyMarkdown = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ResearchRecordValidation.isValidBody(bodyMarkdown),
              Set(revisesStepIDs).count == revisesStepIDs.count,
              ResearchRecordValidation.hasUniqueReferences(noteReferences) else {
            throw ResearchRecordContractError.invalidStep
        }
        self.id = id
        self.recordedAt = recordedAt
        self.submittedBy = submittedBy
        self.bodyMarkdown = bodyMarkdown
        self.revisesStepIDs = revisesStepIDs
        self.noteReferences = noteReferences
        self.corrections = corrections
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "step_id"
        case recordedAt = "recorded_at"
        case submittedBy = "submitted_by"
        case bodyMarkdown = "body_markdown"
        case revisesStepIDs = "revises_step_ids"
        case noteReferences = "note_references"
        case corrections
    }

    public init(from decoder: Decoder) throws {
        try ResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: ResearchRecordValidation.decodeUUID(container, forKey: .id),
            recordedAt: container.decode(Date.self, forKey: .recordedAt),
            submittedBy: container.decode(ResearchRecordSubmitter.self, forKey: .submittedBy),
            bodyMarkdown: container.decode(String.self, forKey: .bodyMarkdown),
            revisesStepIDs: ResearchRecordValidation.decodeUUIDs(
                container,
                forKey: .revisesStepIDs
            ),
            noteReferences: container.decode(
                [ResearchRecordNoteReference].self,
                forKey: .noteReferences
            ),
            corrections: container.decode(
                [ResearchRecordCorrection].self,
                forKey: .corrections
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try ResearchRecordValidation.encodeUUID(id, into: &container, forKey: .id)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encode(submittedBy, forKey: .submittedBy)
        try container.encode(bodyMarkdown, forKey: .bodyMarkdown)
        try ResearchRecordValidation.encodeUUIDs(
            revisesStepIDs,
            into: &container,
            forKey: .revisesStepIDs
        )
        try container.encode(noteReferences, forKey: .noteReferences)
        try container.encode(corrections, forKey: .corrections)
    }
}

public struct ResearchRecord: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumQuestionUTF8Count = 1_024
    public static let maximumStepBodyUTF8Count = 64 * 1_024

    public let schemaVersion: Int
    public let id: UUID
    public let triptychID: UUID
    public let question: String
    public let steps: [ResearchRecordStep]

    public var createdAt: Date { steps[0].recordedAt }
    public var lastSubstantiveAt: Date { steps[steps.count - 1].recordedAt }

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        question: String,
        steps: [ResearchRecordStep]
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.triptychID = triptychID
        self.question = try Self.normalizedQuestion(question)
        self.steps = steps
        try validateHistory()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id = "record_id"
        case triptychID = "triptych_id"
        case question, steps
    }

    public init(from decoder: Decoder) throws {
        try ResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchRecordContractError.unsupportedSchema(version)
        }
        try self.init(
            id: ResearchRecordValidation.decodeUUID(container, forKey: .id),
            triptychID: ResearchRecordValidation.decodeUUID(container, forKey: .triptychID),
            question: container.decode(String.self, forKey: .question),
            steps: container.decode([ResearchRecordStep].self, forKey: .steps)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try ResearchRecordValidation.encodeUUID(id, into: &container, forKey: .id)
        try ResearchRecordValidation.encodeUUID(
            triptychID,
            into: &container,
            forKey: .triptychID
        )
        try container.encode(question, forKey: .question)
        try container.encode(steps, forKey: .steps)
    }

    public func appending(
        _ step: ResearchRecordStep,
        question replacementQuestion: String? = nil
    ) throws -> Self {
        try Self(
            id: id,
            triptychID: triptychID,
            question: replacementQuestion ?? question,
            steps: steps + [step]
        )
    }

    public func correcting(
        stepID: UUID,
        with correction: ResearchRecordCorrection
    ) throws -> Self {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else {
            throw ResearchRecordContractError.invalidCorrection
        }
        var correctedSteps = steps
        let step = correctedSteps[index]
        correctedSteps[index] = try ResearchRecordStep(
            id: step.id,
            recordedAt: step.recordedAt,
            submittedBy: step.submittedBy,
            bodyMarkdown: step.bodyMarkdown,
            revisesStepIDs: step.revisesStepIDs,
            noteReferences: step.noteReferences,
            corrections: step.corrections + [correction]
        )
        return try Self(
            id: id,
            triptychID: triptychID,
            question: question,
            steps: correctedSteps
        )
    }

    private static func normalizedQuestion(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumQuestionUTF8Count,
              ResearchRecordValidation.isSingleLine(value) else {
            throw ResearchRecordContractError.invalidQuestion
        }
        return value
    }

    private func validateHistory() throws {
        guard !steps.isEmpty, Set(steps.map(\.id)).count == steps.count else {
            throw ResearchRecordContractError.invalidRecord
        }
        var earlierStepIDs = Set<UUID>()
        var correctionIDs = Set<UUID>()
        var priorStepTime: Date?
        for step in steps {
            if let priorStepTime, step.recordedAt < priorStepTime {
                throw ResearchRecordContractError.invalidRecord
            }
            guard step.revisesStepIDs.allSatisfy(earlierStepIDs.contains) else {
                throw ResearchRecordContractError.invalidStep
            }
            var priorCorrectionTime = step.recordedAt
            for correction in step.corrections {
                guard correction.correctedAt >= priorCorrectionTime,
                      correctionIDs.insert(correction.id).inserted,
                      correction.revisesStepIDs.allSatisfy(earlierStepIDs.contains) else {
                    throw ResearchRecordContractError.invalidCorrection
                }
                priorCorrectionTime = correction.correctedAt
            }
            earlierStepIDs.insert(step.id)
            priorStepTime = step.recordedAt
        }
    }
}

public struct ResearchRecordRevision: Hashable, Identifiable, Sendable {
    public let record: ResearchRecord
    public let fingerprint: DocumentFingerprint

    public var id: UUID { record.id }

    public init(record: ResearchRecord, fingerprint: DocumentFingerprint) {
        self.record = record
        self.fingerprint = fingerprint
    }
}

public struct ResearchRecordStoreIssue: Hashable, Identifiable, Sendable {
    public let fileName: String
    public let reason: String

    public var id: String { fileName }

    public init(fileName: String, reason: String) {
        self.fileName = fileName
        self.reason = reason
    }
}

public struct ResearchRecordListing: Hashable, Sendable {
    public let records: [ResearchRecordRevision]
    public let issues: [ResearchRecordStoreIssue]

    public init(
        records: [ResearchRecordRevision],
        issues: [ResearchRecordStoreIssue]
    ) {
        self.records = records
        self.issues = issues
    }
}

public enum ResearchRecordProgressKind: String, Codable, Hashable, Sendable {
    case created
    case appended
}

public struct ResearchRecordProgressResult: Hashable, Sendable {
    public let kind: ResearchRecordProgressKind
    public let revision: ResearchRecordRevision
    public let stepID: UUID

    public init(
        kind: ResearchRecordProgressKind,
        revision: ResearchRecordRevision,
        stepID: UUID
    ) {
        self.kind = kind
        self.revision = revision
        self.stepID = stepID
    }
}

private struct StrictResearchRecordFingerprint: Codable {
    let value: DocumentFingerprint

    init(_ value: DocumentFingerprint) {
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sha256
        case byteCount = "byte_count"
    }

    init(from decoder: Decoder) throws {
        try ResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = DocumentFingerprint(
            sha256: try container.decode(String.self, forKey: .sha256),
            byteCount: try container.decode(Int.self, forKey: .byteCount)
        )
        guard ResearchRecordValidation.isValidFingerprint(value) else {
            throw ResearchRecordContractError.invalidNoteReference
        }
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.sha256, forKey: .sha256)
        try container.encode(value.byteCount, forKey: .byteCount)
    }
}

private enum ResearchRecordValidation {
    static func isSingleLine(_ value: String) -> Bool {
        !value.unicodeScalars.contains { scalar in
            CharacterSet.newlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
        }
    }

    static func isValidBody(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= ResearchRecord.maximumStepBodyUTF8Count
            && !value.unicodeScalars.contains { scalar in
                CharacterSet.controlCharacters.contains(scalar)
                    && scalar != "\n"
                    && scalar != "\t"
            }
    }

    static func isValidFingerprint(_ value: DocumentFingerprint) -> Bool {
        value.byteCount >= 0
            && value.sha256.count == 64
            && value.sha256.allSatisfy { $0.isNumber || ("a"..."f").contains($0) }
    }

    static func hasUniqueReferences(_ references: [ResearchRecordNoteReference]) -> Bool {
        struct Key: Hashable {
            let noteID: UUID
            let relation: ResearchRecordNoteRelation
        }
        return Set(references.map { Key(noteID: $0.noteID, relation: $0.relation) }).count
            == references.count
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: [String]
    ) throws {
        let container = try decoder.container(keyedBy: AnyResearchRecordCodingKey.self)
        let allowed = Set(allowed)
        guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw ResearchRecordContractError.invalidRecord
        }
    }

    static func decodeUUID<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> UUID {
        let raw = try container.decode(String.self, forKey: key)
        guard let value = UUID(uuidString: raw), raw == value.uuidString.lowercased() else {
            throw ResearchRecordContractError.invalidRecord
        }
        return value
    }

    static func decodeUUIDs<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> [UUID] {
        try container.decode([String].self, forKey: key).map { raw in
            guard let value = UUID(uuidString: raw), raw == value.uuidString.lowercased() else {
                throw ResearchRecordContractError.invalidRecord
            }
            return value
        }
    }

    static func encodeUUID<Key: CodingKey>(
        _ value: UUID,
        into container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        try container.encode(value.uuidString.lowercased(), forKey: key)
    }

    static func encodeUUIDs<Key: CodingKey>(
        _ values: [UUID],
        into container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        try container.encode(values.map { $0.uuidString.lowercased() }, forKey: key)
    }
}

private struct AnyResearchRecordCodingKey: CodingKey {
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
