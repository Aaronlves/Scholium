import Foundation

/// One frozen Profile field paired with the Agent's validated value. Optional
/// fields remain present with a nil value so the durable Record preserves the
/// exact result shape without retaining the whole mutable Profile document.
public struct PortableResearchAcademicFieldResult: Codable, Hashable, Identifiable,
    Sendable
{
    public var id: ResearchAcademicFieldID { definition.fieldID }

    public let definition: ResearchAcademicFieldDefinition
    public let value: ResearchAcademicFieldValue?

    public init(
        definition: ResearchAcademicFieldDefinition,
        value: ResearchAcademicFieldValue?
    ) throws {
        guard definition.requirement != .excluded else {
            throw PortableResearchRecordError.invalidRecord
        }
        _ = try ResearchAcademicFieldValues(
            rawValues: value.map { [definition.fieldID.rawValue: $0] } ?? [:],
            definitions: [definition]
        )
        if let value {
            guard Self.isPortable(value) else {
                throw PortableResearchRecordError.invalidRecord
            }
        }
        self.definition = definition
        self.value = value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case definition, value
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            definition: container.decode(
                ResearchAcademicFieldDefinition.self,
                forKey: .definition
            ),
            value: container.decodeIfPresent(
                ResearchAcademicFieldValue.self,
                forKey: .value
            )
        )
    }

    private static func isPortable(_ value: ResearchAcademicFieldValue) -> Bool {
        let values: [String] = switch value {
        case .freeText(let text): [text]
        case .singleChoice(let choice): [choice]
        case .multipleChoice(let choices): choices
        }
        return values.allSatisfy {
            PortableResearchRecordValidation.hasNoDisallowedControlCharacters($0)
                && !PortableResearchRecordValidation.containsAbsolutePath($0)
        }
    }
}

/// A researcher-authored, still-unhandled comment attached to the method used
/// by this exact Record. Presence is the only durable pending-state signal.
public struct PortableResearchMethodFeedbackComment: Codable, Hashable, Sendable {
    public let revision: UUID
    public let author: PortableResearchStatementAuthor
    public let text: String
    public let updatedAt: Date

    public init(
        revision: UUID = UUID(),
        text: String,
        updatedAt: Date = Date()
    ) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              text.utf8.count <= 16_384,
              PortableResearchRecordValidation.hasNoDisallowedControlCharacters(text),
              !PortableResearchRecordValidation.containsAbsolutePath(text),
              updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PortableResearchRecordError.invalidRecord
        }
        self.revision = revision
        author = .researcher
        self.text = text
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case revision, author, text
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(PortableResearchStatementAuthor.self, forKey: .author)
                == .researcher else {
            throw PortableResearchRecordError.invalidRecord
        }
        try self.init(
            revision: container.decode(UUID.self, forKey: .revision),
            text: container.decode(String.self, forKey: .text),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

/// Researcher-facing input for the one current, still-unhandled Method
/// feedback comment. It is created only by an explicit researcher action.
public struct ResearchMethodFeedbackDraft: Codable, Hashable, Sendable {
    public let text: String

    public init(text: String) throws {
        let validated = try PortableResearchMethodFeedbackComment(
            text: text,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        self.text = validated.text
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(text: container.decode(String.self, forKey: .text))
    }
}

public enum PortableResearchMethodFeedbackMutationError: LocalizedError,
    Hashable, Sendable {
    case staleMethodFeedbackRevision
    case finalizedResultChanged
    case recordUnavailable

    public var errorDescription: String? {
        switch self {
        case .staleMethodFeedbackRevision:
            "The Method Feedback changed elsewhere; reload without discarding the local draft."
        case .finalizedResultChanged:
            "The finalized Research Result no longer matches this Method Feedback."
        case .recordUnavailable:
            "The Research Record is no longer available for Method Feedback."
        }
    }
}

public enum ResearchRecordChangeRecoveryError: LocalizedError,
    Hashable, Sendable {
    case finalizedResultChanged
    case recordUnavailable

    public var errorDescription: String? {
        switch self {
        case .finalizedResultChanged:
            "The finalized Research Result no longer matches this recovery request."
        case .recordUnavailable:
            "The Research Record is no longer available for source recovery."
        }
    }
}

public enum ResearchRecordChangeUndoStatus: Hashable, Sendable {
    case restored
    case alreadyAtStartingRevision
    case conflict
    case unavailable
    case commitUncertain
}

/// Current authoritative source fact for one Agent-confirmed change. This is
/// a disposable Application projection, never a second durable source owner.
public enum ResearchRecordChangeCurrentStatus: Hashable, Sendable {
    case agentEndingRevision
    case startingRevision
    case superseded
    case unavailable
}

public struct ResearchRecordChangeCurrentState: Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let currentRelativePath: String?
    public let status: ResearchRecordChangeCurrentStatus
    public let observedRevision: DocumentFingerprint?

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        currentRelativePath: String?,
        status: ResearchRecordChangeCurrentStatus,
        observedRevision: DocumentFingerprint?
    ) {
        self.noteID = noteID
        self.currentRelativePath = currentRelativePath
        self.status = status
        self.observedRevision = observedRevision
    }
}

public struct ResearchRecordChangeState: Sendable {
    public let recordID: UUID
    public let finalizedResultFingerprint: DocumentFingerprint
    public let documents: [ResearchRecordChangeCurrentState]

    public init(
        recordID: UUID,
        finalizedResultFingerprint: DocumentFingerprint,
        documents: [ResearchRecordChangeCurrentState]
    ) {
        self.recordID = recordID
        self.finalizedResultFingerprint = finalizedResultFingerprint
        self.documents = documents
    }
}

public struct ResearchRecordChangeUndoDocumentResult: Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let status: ResearchRecordChangeUndoStatus
    public let observedRevision: DocumentFingerprint?

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        status: ResearchRecordChangeUndoStatus,
        observedRevision: DocumentFingerprint?
    ) {
        self.noteID = noteID
        self.status = status
        self.observedRevision = observedRevision
    }
}

public struct ResearchRecordChangesUndoResult: Sendable {
    public let record: PortableResearchRecord
    public let documents: [ResearchRecordChangeUndoDocumentResult]

    public init(
        record: PortableResearchRecord,
        documents: [ResearchRecordChangeUndoDocumentResult]
    ) {
        self.record = record
        self.documents = documents
    }
}

public enum ResearchRecordChangeRecoveryOperationError: LocalizedError, Hashable, Sendable {
    case confirmedChangeNotFound(UUID)
    case createdNoteHasNoPreimage(UUID)
    case invalidSelection
    case executionUnavailable
    case changeEvidenceMismatch(UUID)

    public var errorDescription: String? {
        switch self {
        case .confirmedChangeNotFound:
            "The selected note is not an Agent-confirmed change in this Research Record."
        case .createdNoteHasNoPreimage:
            "A Note created by the Agent has no Before Agent Work source to compare or restore."
        case .invalidSelection:
            "Select at least one unresolved Agent-confirmed document."
        case .executionUnavailable:
            "The protected execution evidence required for direct undo is unavailable."
        case .changeEvidenceMismatch:
            "The exact Agent change evidence does not match the confirmed change baseline."
        }
    }
}

public extension PortableResearchRecord {
    /// Fingerprint of the finalized Agent/Scholium result partition. Mutable
    /// researcher-owned recommendation disposition and response fields are
    /// excluded by construction. Note Review is a separate portable object.
    func finalizedResultFingerprint() throws -> DocumentFingerprint {
        let partition = PortableResearchFinalizedResultPartition(
            schemaVersion: schemaVersion,
            id: id,
            triptychID: triptychID,
            title: title,
            kind: kind,
            action: action,
            method: method,
            sourceReference: sourceReference,
            continuationLineage: continuationLineage,
            primaryNoteID: primaryNoteID,
            participatingNotes: participatingNotes,
            statements: statements,
            resultDisposition: resultDisposition,
            academicResults: academicResults,
            fidelityCompletion: fidelityCompletion,
            confirmedChanges: confirmedChanges,
            activityOutcomes: activityOutcomes,
            discrepancies: discrepancies,
            literatureRecommendations: literatureRecommendations.map(
                PortableResearchFinalizedRecommendation.init
            ),
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return DocumentFingerprint(data: try encoder.encode(partition))
    }
}

private struct PortableResearchFinalizedResultPartition: Encodable {
    let schemaVersion: Int
    let id: UUID
    let triptychID: UUID
    let title: ResearchRecordTitle
    let kind: PortableResearchRecordKind
    let action: ResearchActionRecordIdentity?
    let method: PortableResearchMethodReference?
    let sourceReference: ResearchSourceReference?
    let continuationLineage: ResearchContinuationLineage?
    let primaryNoteID: UUID?
    let participatingNotes: [PortableResearchNoteRevision]
    let statements: [PortableResearchStatement]
    let resultDisposition: ResearchAgentResultDisposition
    let academicResults: [PortableResearchAcademicFieldResult]
    let fidelityCompletion: PortableResearchFidelityCompletion
    let confirmedChanges: [PortableResearchConfirmedChange]
    let activityOutcomes: [PortableResearchActivityOutcome]
    let discrepancies: [PortableResearchDiscrepancy]
    let literatureRecommendations: [PortableResearchFinalizedRecommendation]
    let startedAt: Date
    let finishedAt: Date
}

private struct PortableResearchFinalizedRecommendation: Encodable {
    let id: UUID
    let rawCitation: String
    let title: String?
    let authors: [String]
    let year: Int?
    let doi: String?
    let zoteroItemKey: String?
    let sourceLocators: [String]
    let reason: String
    let uncertainty: String?

    init(_ value: ResearchLiteratureRecommendation) {
        id = value.id
        rawCitation = value.rawCitation
        title = value.title
        authors = value.authors
        year = value.year
        doi = value.doi
        zoteroItemKey = value.zoteroItemKey
        sourceLocators = value.sourceLocators
        reason = value.reason
        uncertainty = value.uncertainty
    }
}
