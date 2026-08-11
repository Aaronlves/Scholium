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

public enum PortableResearchObservedIssue: String, Codable, CaseIterable, Hashable,
    Sendable
{
    case sourceOrAttribution = "source_or_attribution"
    case conceptOrInterpretation = "concept_or_interpretation"
    case argumentOrObjectionReply = "argument_or_objection_reply"
    case epistemicIdentityOrResearcherState = "epistemic_identity_or_researcher_state"
    case evidentialScopeOrRestraint = "evidential_scope_or_restraint"
    case researchHelpOrNextStep = "research_help_or_next_step"
    case other
}

/// The single current researcher-authored evaluation partition of one Record.
/// Its revision is an optimistic-concurrency token, not an evaluation history.
public struct PortableResearcherEvaluation: Codable, Hashable, Sendable {
    public let revision: UUID
    public let author: PortableResearchStatementAuthor
    public let observedIssues: [PortableResearchObservedIssue]
    public let noIssuesObserved: Bool
    public let valuableDiscovery: Bool
    public let note: String?
    public let updatedAt: Date

    public init(
        revision: UUID = UUID(),
        observedIssues: [PortableResearchObservedIssue] = [],
        noIssuesObserved: Bool = false,
        valuableDiscovery: Bool = false,
        note: String? = nil,
        updatedAt: Date = Date()
    ) throws {
        let issues = PortableResearchObservedIssue.allCases.filter(
            Set(observedIssues).contains
        )
        let normalizedNote = note?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let retainedNote = normalizedNote?.isEmpty == false ? normalizedNote : nil
        guard Set(observedIssues).count == observedIssues.count,
              !(noIssuesObserved && !issues.isEmpty),
              !issues.isEmpty || noIssuesObserved || valuableDiscovery
                || retainedNote != nil,
              retainedNote.map({
                  $0.utf8.count <= 16_384
                      && PortableResearchRecordValidation
                        .hasNoDisallowedControlCharacters($0)
                      && !PortableResearchRecordValidation.containsAbsolutePath($0)
              }) ?? true,
              updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PortableResearchRecordError.invalidRecord
        }
        self.revision = revision
        author = .researcher
        self.observedIssues = issues
        self.noIssuesObserved = noIssuesObserved
        self.valuableDiscovery = valuableDiscovery
        self.note = retainedNote
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case revision, author
        case observedIssues = "observed_issues"
        case noIssuesObserved = "no_issues_observed"
        case valuableDiscovery = "valuable_discovery"
        case note
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
            observedIssues: container.decode(
                [PortableResearchObservedIssue].self,
                forKey: .observedIssues
            ),
            noIssuesObserved: container.decode(Bool.self, forKey: .noIssuesObserved),
            valuableDiscovery: container.decode(Bool.self, forKey: .valuableDiscovery),
            note: container.decodeIfPresent(String.self, forKey: .note),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

/// Researcher-facing evaluation input. Record identity, actor, revision, and
/// time are supplied by the Record owner at the atomic save boundary.
public struct ResearcherEvaluationDraft: Codable, Hashable, Sendable {
    public let observedIssues: [PortableResearchObservedIssue]
    public let noIssuesObserved: Bool
    public let valuableDiscovery: Bool
    public let note: String?

    public init(
        observedIssues: [PortableResearchObservedIssue] = [],
        noIssuesObserved: Bool = false,
        valuableDiscovery: Bool = false,
        note: String? = nil
    ) throws {
        let validated = try PortableResearcherEvaluation(
            observedIssues: observedIssues,
            noIssuesObserved: noIssuesObserved,
            valuableDiscovery: valuableDiscovery,
            note: note,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        self.observedIssues = validated.observedIssues
        self.noIssuesObserved = validated.noIssuesObserved
        self.valuableDiscovery = validated.valuableDiscovery
        self.note = validated.note
    }

    public init(_ evaluation: PortableResearcherEvaluation) throws {
        try self.init(
            observedIssues: evaluation.observedIssues,
            noIssuesObserved: evaluation.noIssuesObserved,
            valuableDiscovery: evaluation.valuableDiscovery,
            note: evaluation.note
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case observedIssues = "observed_issues"
        case noIssuesObserved = "no_issues_observed"
        case valuableDiscovery = "valuable_discovery"
        case note
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            observedIssues: container.decode(
                [PortableResearchObservedIssue].self,
                forKey: .observedIssues
            ),
            noIssuesObserved: container.decode(Bool.self, forKey: .noIssuesObserved),
            valuableDiscovery: container.decode(Bool.self, forKey: .valuableDiscovery),
            note: container.decodeIfPresent(String.self, forKey: .note)
        )
    }
}

/// A researcher-authored, still-unhandled comment attached to the method used
/// by this exact Record. Presence is the only durable pending-state signal.
public struct PortableResearchMethodFeedbackComment: Codable, Hashable, Sendable {
    public let revision: UUID
    public let author: PortableResearchStatementAuthor
    public let text: String
    public let sourceEvaluationRevision: UUID?
    public let updatedAt: Date

    public init(
        revision: UUID = UUID(),
        text: String,
        sourceEvaluationRevision: UUID? = nil,
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
        self.sourceEvaluationRevision = sourceEvaluationRevision
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case revision, author, text
        case sourceEvaluationRevision = "source_evaluation_revision"
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
            sourceEvaluationRevision: container.decodeIfPresent(
                UUID.self,
                forKey: .sourceEvaluationRevision
            ),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

/// Researcher-facing input for the one current, still-unhandled Method
/// feedback comment. It is created only by an explicit researcher action.
public struct ResearchMethodFeedbackDraft: Codable, Hashable, Sendable {
    public let text: String
    public let sourceEvaluationRevision: UUID?

    public init(
        text: String,
        sourceEvaluationRevision: UUID? = nil
    ) throws {
        let validated = try PortableResearchMethodFeedbackComment(
            text: text,
            sourceEvaluationRevision: sourceEvaluationRevision,
            updatedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        self.text = validated.text
        self.sourceEvaluationRevision = validated.sourceEvaluationRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case sourceEvaluationRevision = "source_evaluation_revision"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            text: container.decode(String.self, forKey: .text),
            sourceEvaluationRevision: container.decodeIfPresent(
                UUID.self,
                forKey: .sourceEvaluationRevision
            )
        )
    }
}

/// One editor payload for the researcher-owned Evaluation and Method Feedback
/// partitions. The portable store validates and replaces both in one CAS.
public struct ResearcherResponseDraft: Hashable, Sendable {
    public let evaluation: ResearcherEvaluationDraft?
    public let methodFeedbackText: String?

    public init(
        evaluation: ResearcherEvaluationDraft?,
        methodFeedbackText: String?
    ) throws {
        let normalizedFeedback = methodFeedbackText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedFeedback, !normalizedFeedback.isEmpty {
            _ = try ResearchMethodFeedbackDraft(text: normalizedFeedback)
            self.methodFeedbackText = normalizedFeedback
        } else {
            self.methodFeedbackText = nil
        }
        self.evaluation = evaluation
    }
}

public enum PortableResearcherResponseMutationError: LocalizedError,
    Hashable, Sendable {
    case staleEvaluationRevision
    case staleMethodFeedbackRevision
    case finalizedResultChanged
    case recordUnavailable

    public var errorDescription: String? {
        switch self {
        case .staleEvaluationRevision:
            "The Researcher Evaluation changed elsewhere; reload without discarding the local response."
        case .staleMethodFeedbackRevision:
            "The Method Feedback changed elsewhere; reload without discarding the local response."
        case .finalizedResultChanged:
            "The finalized Research Result no longer matches this researcher response."
        case .recordUnavailable:
            "The Research Record is no longer available for a researcher response."
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
    case checkpointMismatch(UUID)

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
        case .checkpointMismatch:
            "The Before Agent Work checkpoint does not match the confirmed change baseline."
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
            contextUseReport: contextUseReport,
            actuallyUsedMaterials: actuallyUsedMaterials,
            fidelityCompletion: fidelityCompletion,
            confirmedChanges: confirmedChanges,
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
    let contextUseReport: ContextUseReport?
    let actuallyUsedMaterials: [PortableResearchMaterialUse]
    let fidelityCompletion: PortableResearchFidelityCompletion
    let confirmedChanges: [PortableResearchConfirmedChange]
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
