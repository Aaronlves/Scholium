import Foundation

/// One concise, frozen scholarly identity for a finished Research Record.
/// It is authored with the result rather than generated later from result prose.
public struct ResearchRecordTitle: Codable, Hashable, Sendable, CustomStringConvertible {
    public static let maximumUTF8Count = 240

    public let value: String

    public var description: String { value }

    public init(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= Self.maximumUTF8Count,
              !PortableResearchRecordValidation.containsAbsolutePath(value),
              !value.unicodeScalars.contains(where: {
                  CharacterSet.newlines.contains($0)
                      || CharacterSet.controlCharacters.contains($0)
              }) else {
            throw PortableResearchRecordError.invalidRecordTitle
        }
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// The durable scholarly shape of one portable Research Record.
///
/// Storage location is intentionally not encoded: active Discussions and
/// finished Records remain filesystem state owned by the portable store.
public enum PortableResearchRecordKind: String, Codable, Hashable, Sendable {
    case action
    case discussion
}

/// Attribution for prose deliberately retained in a Research Record.
public enum PortableResearchStatementAuthor: String, Codable, Hashable, Sendable {
    case researcher
    case agent
}

/// The semantic role of one retained attributed statement. These values do
/// not turn an agent report into an Application-established fact.
public enum PortableResearchStatementKind: String, Codable, Hashable, Sendable {
    case discussionTurn = "discussion_turn"
    case agentFeedback = "agent_feedback"
    case researcherResponse = "researcher_response"
}

/// A lightweight researcher Comment location. It deliberately records no
/// selected prose or exact source offsets; the fingerprint keeps the original
/// one-based inclusive line range truthful after later edits.
public struct ResearchLineReference: Codable, Hashable, Sendable {
    public let fingerprint: DocumentFingerprint
    public let line: Int
    public let endLine: Int

    public init(
        fingerprint: DocumentFingerprint,
        line: Int,
        endLine: Int
    ) throws {
        guard PortableResearchRecordValidation.isValidFingerprint(fingerprint),
              line > 0,
              endLine >= line else {
            throw PortableResearchRecordError.invalidStatement
        }
        self.fingerprint = fingerprint
        self.line = line
        self.endLine = endLine
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fingerprint, line
        case endLine = "end_line"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fingerprint: container.decode(
                PortableResearchStrictFingerprint.self,
                forKey: .fingerprint
            ).value,
            line: container.decode(Int.self, forKey: .line),
            endLine: container.decode(Int.self, forKey: .endLine)
        )
    }
}

public struct PortableResearchStatement: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let author: PortableResearchStatementAuthor
    public let kind: PortableResearchStatementKind
    public let attribution: String
    public let text: String
    public let createdAt: Date
    public let passage: CommentAnchor?
    public let lineReference: ResearchLineReference?

    public init(
        id: UUID = UUID(),
        author: PortableResearchStatementAuthor,
        kind: PortableResearchStatementKind,
        attribution: String,
        text: String,
        createdAt: Date = Date(),
        passage: CommentAnchor? = nil,
        lineReference: ResearchLineReference? = nil
    ) throws {
        let attribution = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attribution.isEmpty,
              attribution.utf8.count <= 256,
              !text.isEmpty,
              text.utf8.count <= 256 * 1024,
              !PortableResearchRecordValidation.containsAbsolutePath(attribution),
              !PortableResearchRecordValidation.containsAbsolutePath(text),
              passage == nil || lineReference == nil,
              passage.map(PortableResearchRecordValidation.isValidPassage) ?? true else {
            throw PortableResearchRecordError.invalidStatement
        }
        switch (author, kind) {
        case (.researcher, .discussionTurn),
             (.researcher, .researcherResponse),
             (.agent, .discussionTurn),
             (.agent, .agentFeedback):
            break
        case (.researcher, .agentFeedback),
             (.agent, .researcherResponse):
            throw PortableResearchRecordError.invalidStatement
        }
        self.id = id
        self.author = author
        self.kind = kind
        self.attribution = attribution
        self.text = text
        self.createdAt = createdAt
        self.passage = passage
        self.lineReference = lineReference
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, author, kind, attribution, text
        case createdAt = "created_at"
        case passage
        case lineReference = "line_reference"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            author: container.decode(PortableResearchStatementAuthor.self, forKey: .author),
            kind: container.decode(PortableResearchStatementKind.self, forKey: .kind),
            attribution: container.decode(String.self, forKey: .attribution),
            text: container.decode(String.self, forKey: .text),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            passage: container.decodeIfPresent(
                PortableResearchStrictPassage.self,
                forKey: .passage
            )?.value,
            lineReference: container.decodeIfPresent(
                ResearchLineReference.self,
                forKey: .lineReference
            )
        )
    }

    public func replacingPassage(_ passage: CommentAnchor?) throws -> Self {
        try Self(
            id: id,
            author: author,
            kind: kind,
            attribution: attribution,
            text: text,
            createdAt: createdAt,
            passage: passage,
            lineReference: lineReference
        )
    }

    public func replacingLineReference(_ lineReference: ResearchLineReference?) throws -> Self {
        try Self(
            id: id,
            author: author,
            kind: kind,
            attribution: attribution,
            text: text,
            createdAt: createdAt,
            passage: passage,
            lineReference: lineReference
        )
    }
}

/// One stable Note identity and its exact starting and ending revisions during
/// the recorded scholarly exchange. A Record never substitutes a participant
/// tombstone for a deleted source: the whole associated Record is deleted by
/// the confirmed system-Trash plan.
public struct PortableResearchNoteRevision: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let title: String
    public let startingRevision: DocumentFingerprint
    public let endingRevision: DocumentFingerprint

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        startingRevision: DocumentFingerprint,
        endingRevision: DocumentFingerprint
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.utf8.count <= 1_024,
              !PortableResearchRecordValidation.containsAbsolutePath(title),
              PortableResearchRecordValidation.isValidNote(note),
              PortableResearchRecordValidation.isValidFingerprint(startingRevision),
              PortableResearchRecordValidation.isValidFingerprint(endingRevision) else {
            throw PortableResearchRecordError.invalidNoteRevision
        }
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title
        self.startingRevision = startingRevision
        self.endingRevision = endingRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID = "note_id"
        case note, role, title
        case startingRevision = "starting_revision"
        case endingRevision = "ending_revision"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            noteID: container.decode(UUID.self, forKey: .noteID),
            note: container.decode(
                PortableResearchStrictNoteID.self,
                forKey: .note
            ).value,
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            title: container.decode(String.self, forKey: .title),
            startingRevision: container.decode(
                PortableResearchStrictFingerprint.self,
                forKey: .startingRevision
            ).value,
            endingRevision: container.decode(
                PortableResearchStrictFingerprint.self,
                forKey: .endingRevision
            ).value
        )
    }
}

/// Exact Method and Profile revisions retained without the Method prose,
/// assembled prompt, Action parameters, authority grant, or machine locator.
public struct PortableResearchMethodReference: Codable, Hashable, Sendable {
    public let registrationKey: ResearchSkillRegistrationKey
    public let displayName: String
    public let practiceNames: [String]
    public let profileRevision: DocumentFingerprint

    public init(
        registrationKey: ResearchSkillRegistrationKey,
        displayName: String,
        practiceNames: [String] = [],
        profileRevision: DocumentFingerprint
    ) throws {
        guard !displayName.isEmpty,
              displayName.utf8.count <= 256,
              !PortableResearchRecordValidation.containsAbsolutePath(displayName),
              Set(practiceNames).count == practiceNames.count,
              practiceNames.allSatisfy({
                  !$0.isEmpty
                      && $0.utf8.count <= 256
                      && !PortableResearchRecordValidation.containsAbsolutePath($0)
              }),
              PortableResearchRecordValidation.isValidFingerprint(profileRevision)
        else { throw PortableResearchRecordError.invalidMethodReference }
        self.registrationKey = registrationKey
        self.displayName = displayName
        self.practiceNames = practiceNames
        self.profileRevision = profileRevision
    }

    public init(snapshot: ResearchActionSnapshot) throws {
        let name = snapshot.method.registration.displayName
        let practices = snapshot.method.practices.map(\.title)
        guard !name.isEmpty,
              name.utf8.count <= 256,
              !PortableResearchRecordValidation.containsAbsolutePath(name),
              Set(practices).count == practices.count,
              practices.allSatisfy({
                  !$0.isEmpty
                      && $0.utf8.count <= 256
                      && !PortableResearchRecordValidation.containsAbsolutePath($0)
              }),
              PortableResearchRecordValidation.isValidFingerprint(
                snapshot.resolvedProfile.profileRevision
              ) else {
            throw PortableResearchRecordError.invalidMethodReference
        }
        try self.init(
            registrationKey: snapshot.method.registration.key,
            displayName: name,
            practiceNames: practices,
            profileRevision: snapshot.resolvedProfile.profileRevision
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case registrationKey = "registration_key"
        case displayName = "display_name"
        case practiceNames = "practice_names"
        case profileRevision = "profile_revision"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let registrationKey = try container.decode(
            ResearchSkillRegistrationKey.self,
            forKey: .registrationKey
        )
        let displayName = try container.decode(String.self, forKey: .displayName)
        let practiceNames = try container.decode([String].self, forKey: .practiceNames)
        guard !displayName.isEmpty,
              displayName.utf8.count <= 256,
              !PortableResearchRecordValidation.containsAbsolutePath(displayName),
              Set(practiceNames).count == practiceNames.count,
              practiceNames.allSatisfy({
                  !$0.isEmpty
                      && $0.utf8.count <= 256
                      && !PortableResearchRecordValidation.containsAbsolutePath($0)
              }) else {
            throw PortableResearchRecordError.invalidMethodReference
        }
        let profileRevision = try container.decode(
            PortableResearchStrictFingerprint.self,
            forKey: .profileRevision
        ).value
        guard PortableResearchRecordValidation.isValidFingerprint(profileRevision) else {
            throw PortableResearchRecordError.invalidMethodReference
        }
        try self.init(
            registrationKey: registrationKey,
            displayName: displayName,
            practiceNames: practiceNames,
            profileRevision: profileRevision
        )
    }
}

/// A Material appears here only when an attributed agent report says it was
/// actually used. Selection alone never creates this value.
public struct PortableResearchMaterialUse: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let title: String
    public let revision: DocumentFingerprint

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        revision: DocumentFingerprint
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.utf8.count <= 1_024,
              !PortableResearchRecordValidation.containsAbsolutePath(title),
              PortableResearchRecordValidation.isValidNote(note),
              PortableResearchRecordValidation.isValidFingerprint(revision) else {
            throw PortableResearchRecordError.invalidMaterialUse
        }
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID = "note_id"
        case note, role, title, revision
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            noteID: container.decode(UUID.self, forKey: .noteID),
            note: container.decode(
                PortableResearchStrictNoteID.self,
                forKey: .note
            ).value,
            role: container.decode(ResearchActionTargetRole.self, forKey: .role),
            title: container.decode(String.self, forKey: .title),
            revision: container.decode(
                PortableResearchStrictFingerprint.self,
                forKey: .revision
            ).value
        )
    }
}

public enum PortableResearchConfirmedChangeKind: String, Codable, Hashable, Sendable {
    case created
    case modified
}

public struct PortableResearchConfirmedChange: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let actor: ResearchContextActorClass
    public let kind: PortableResearchConfirmedChangeKind
    public let startingRevision: DocumentFingerprint?
    public let endingRevision: DocumentFingerprint

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        actor: ResearchContextActorClass,
        startingRevision: DocumentFingerprint?,
        endingRevision: DocumentFingerprint
    ) throws {
        let kind: PortableResearchConfirmedChangeKind = startingRevision == nil
            ? .created
            : .modified
        guard actor == .agent,
              startingRevision.map({ $0 != endingRevision }) ?? true,
              startingRevision.map(
                PortableResearchRecordValidation.isValidFingerprint
              ) ?? true,
              PortableResearchRecordValidation.isValidFingerprint(endingRevision) else {
            throw PortableResearchRecordError.invalidConfirmedChange
        }
        self.noteID = noteID
        self.actor = actor
        self.kind = kind
        self.startingRevision = startingRevision
        self.endingRevision = endingRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID = "note_id"
        case actor, kind
        case startingRevision = "starting_revision"
        case endingRevision = "ending_revision"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            noteID: container.decode(UUID.self, forKey: .noteID),
            actor: container.decode(
                ResearchContextActorClass.self,
                forKey: .actor
            ),
            startingRevision: container.decodeIfPresent(
                PortableResearchStrictFingerprint.self,
                forKey: .startingRevision
            )?.value,
            endingRevision: container.decode(
                PortableResearchStrictFingerprint.self,
                forKey: .endingRevision
            ).value
        )
        guard kind == (try container.decode(
            PortableResearchConfirmedChangeKind.self,
            forKey: .kind
        )) else {
            throw PortableResearchRecordError.invalidConfirmedChange
        }
    }
}

public enum PortableResearchDiscrepancyKind: String, Codable, Hashable, Sendable {
    case changedButNotReported = "changed_but_not_reported"
    case reportedButUnmodified = "reported_but_unmodified"
}

public struct PortableResearchDiscrepancy: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let kind: PortableResearchDiscrepancyKind

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        kind: PortableResearchDiscrepancyKind
    ) {
        self.id = id
        self.noteID = noteID
        self.kind = kind
    }

    /// Stable identity makes creation of a finished record idempotent across
    /// exact completion retries without treating a discrepancy as a separate
    /// mutable object.
    public static func stableID(
        runID: UUID,
        noteID: UUID,
        kind: PortableResearchDiscrepancyKind
    ) -> UUID {
        let digest = DocumentFingerprint(
            content: "\(runID.uuidString.lowercased()):\(noteID.uuidString.lowercased()):\(kind.rawValue)"
        ).sha256
        let value = [
            String(digest.prefix(8)),
            String(digest.dropFirst(8).prefix(4)),
            String(digest.dropFirst(12).prefix(4)),
            String(digest.dropFirst(16).prefix(4)),
            String(digest.dropFirst(20).prefix(12)),
        ].joined(separator: "-")
        return UUID(uuidString: value)!
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case noteID = "note_id"
        case kind
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            noteID: try container.decode(UUID.self, forKey: .noteID),
            kind: try container.decode(PortableResearchDiscrepancyKind.self, forKey: .kind)
        )
    }
}

/// Scholium-established completion state for the Fidelity process attached to
/// one portable record. Completion means that the declared checks ran against
/// the recorded revision; it is not a truth, quality, or acceptance verdict.
public enum PortableResearchFidelityCompletion: String, Codable, Hashable, Sendable {
    case notRequired = "not_required"
    case completed
    case unverified
    case notApplicable = "not_applicable"
}

/// Whitelisted, portable scholarly evidence for one finished Discussion or
/// validated nonconversational Action. It deliberately has no generic metadata
/// dictionary, so machine-local execution fields cannot leak through encoding.
public struct PortableResearchRecord: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 12

    public let schemaVersion: Int
    public let id: UUID
    public let triptychID: UUID
    public let title: ResearchRecordTitle
    public let kind: PortableResearchRecordKind
    public let action: ResearchActionRecordIdentity?
    public let method: PortableResearchMethodReference?
    public let sourceReference: ResearchSourceReference?
    /// Frozen Zotero metadata is portable task provenance for an Analyze run;
    /// it is not paper content, source evidence, or a Scholium source locator.
    public let zoteroBibliographicContext: ZoteroBibliographicContext?
    /// Explicit Analyze source routing. `researcher_provided` records only the
    /// declared route; it does not invent a locator, source bytes, or evidence.
    public let analysisSourceRoute: ResearchAnalysisSourceRoute?
    public let continuationLineage: ResearchContinuationLineage?
    public let primaryNoteID: UUID?
    public let participatingNotes: [PortableResearchNoteRevision]
    public let statements: [PortableResearchStatement]
    public let resultDisposition: ResearchAgentResultDisposition
    public let academicResults: [PortableResearchAcademicFieldResult]
    public let contextUseReport: ContextUseReport?
    public let actuallyUsedMaterials: [PortableResearchMaterialUse]
    public let fidelityCompletion: PortableResearchFidelityCompletion
    public let confirmedChanges: [PortableResearchConfirmedChange]
    public let discrepancies: [PortableResearchDiscrepancy]
    public let literatureRecommendations: [ResearchLiteratureRecommendation]
    public let startedAt: Date
    public let finishedAt: Date
    public let researcherEvaluation: PortableResearcherEvaluation?
    public let methodFeedbackComment: PortableResearchMethodFeedbackComment?

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        title: ResearchRecordTitle,
        kind: PortableResearchRecordKind,
        action: ResearchActionRecordIdentity?,
        method: PortableResearchMethodReference?,
        sourceReference: ResearchSourceReference? = nil,
        zoteroBibliographicContext: ZoteroBibliographicContext? = nil,
        analysisSourceRoute: ResearchAnalysisSourceRoute? = nil,
        continuationLineage: ResearchContinuationLineage? = nil,
        primaryNoteID: UUID? = nil,
        participatingNotes: [PortableResearchNoteRevision],
        statements: [PortableResearchStatement],
        resultDisposition: ResearchAgentResultDisposition = .completed,
        academicResults: [PortableResearchAcademicFieldResult] = [],
        contextUseReport: ContextUseReport? = nil,
        actuallyUsedMaterials: [PortableResearchMaterialUse] = [],
        fidelityCompletion: PortableResearchFidelityCompletion,
        confirmedChanges: [PortableResearchConfirmedChange] = [],
        discrepancies: [PortableResearchDiscrepancy] = [],
        literatureRecommendations: [ResearchLiteratureRecommendation] = [],
        startedAt: Date,
        finishedAt: Date,
        researcherEvaluation: PortableResearcherEvaluation? = nil,
        methodFeedbackComment: PortableResearchMethodFeedbackComment? = nil
    ) throws {
        let participatingByID = Dictionary(
            participatingNotes.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let statementIDs = statements.map(\.id)
        let discrepancyIDs = discrepancies.map(\.id)
        let recommendationIDs = literatureRecommendations.map(\.id)
        let academicFieldIDs = academicResults.map(\.id)
        guard startedAt.timeIntervalSinceReferenceDate.isFinite,
              finishedAt.timeIntervalSinceReferenceDate.isFinite,
              finishedAt >= startedAt,
              !participatingNotes.isEmpty,
              participatingNotes.count <= 256,
              statements.count <= 4_096,
              academicResults.count <= 24,
              actuallyUsedMaterials.count <= 256,
              confirmedChanges.count <= 256,
              discrepancies.count <= 256,
              literatureRecommendations.count <= 256,
              participatingByID.count == participatingNotes.count,
              Set(statementIDs).count == statementIDs.count,
              Set(academicFieldIDs).count == academicFieldIDs.count,
              zip(statements, statements.dropFirst()).allSatisfy({ pair in
                  pair.0.createdAt <= pair.1.createdAt
              }),
              Set(discrepancyIDs).count == discrepancyIDs.count,
              Set(recommendationIDs).count == recommendationIDs.count,
              literatureRecommendations.enumerated().allSatisfy({ ordinal, item in
                  item.id == ResearchLiteratureRecommendation.stableID(
                      runID: id,
                      ordinal: ordinal
                  )
              }),
              Set(actuallyUsedMaterials.map(\.noteID)).count == actuallyUsedMaterials.count,
              Set(confirmedChanges.map(\.noteID)).count == confirmedChanges.count,
              actuallyUsedMaterials.allSatisfy({ material in
                  guard let participant = participatingByID[material.noteID] else {
                      return false
                  }
                  return participant.note == material.note
                      && participant.role == material.role
                      && participant.title == material.title
                      && participant.startingRevision == material.revision
              }),
              confirmedChanges.allSatisfy({ change in
                  guard let participant = participatingByID[change.noteID] else {
                      return false
                  }
                  guard participant.endingRevision == change.endingRevision else {
                      return false
                  }
                  return true
              }),
              discrepancies.allSatisfy({ discrepancy in
                  participatingByID[discrepancy.noteID] != nil
              }),
              contextUseReport.map({ report in
                  report.runID == id && report.triptychID == triptychID
                      && report.entries.allSatisfy({ entry in
                          !PortableResearchRecordValidation.containsAbsolutePath(
                              entry.testimony
                          )
                      })
              }) ?? true,
              (action == nil) == (method == nil) else {
            throw PortableResearchRecordError.invalidRecord
        }
        switch kind {
        case .action:
            guard action != nil,
                  method != nil,
                  fidelityCompletion != .notApplicable,
                  primaryNoteID.map({ participatingByID[$0] != nil }) ?? true,
                  Self.validAnalysisSourceRoute(
                      actionID: action?.actionID,
                      route: analysisSourceRoute,
                      sourceReference: sourceReference,
                      zoteroContext: zoteroBibliographicContext
                  ),
                  zoteroBibliographicContext == nil || action?.actionID == .analyze,
                  action?.actionID == .analyze || literatureRecommendations.isEmpty else {
                throw PortableResearchRecordError.invalidRecord
            }
        case .discussion:
            guard let primaryNoteID,
                  participatingByID[primaryNoteID] != nil,
                  !statements.isEmpty,
                  continuationLineage == nil,
                  actuallyUsedMaterials.isEmpty,
                  fidelityCompletion == .notApplicable,
                  confirmedChanges.isEmpty,
                  researcherEvaluation == nil,
                  methodFeedbackComment == nil,
                  discrepancies.isEmpty,
                  literatureRecommendations.isEmpty else {
                throw PortableResearchRecordError.invalidRecord
            }
        }
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.triptychID = triptychID
        self.title = title
        self.kind = kind
        self.action = action
        self.method = method
        self.sourceReference = sourceReference
        self.zoteroBibliographicContext = zoteroBibliographicContext
        self.analysisSourceRoute = analysisSourceRoute
        self.continuationLineage = continuationLineage
        self.primaryNoteID = primaryNoteID
        self.participatingNotes = participatingNotes.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        self.statements = statements
        self.resultDisposition = resultDisposition
        self.academicResults = academicResults
        self.contextUseReport = contextUseReport
        self.actuallyUsedMaterials = actuallyUsedMaterials.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        self.fidelityCompletion = fidelityCompletion
        self.confirmedChanges = confirmedChanges.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        self.discrepancies = discrepancies.sorted {
            if $0.noteID != $1.noteID { return $0.noteID.uuidString < $1.noteID.uuidString }
            return $0.id.uuidString < $1.id.uuidString
        }
        self.literatureRecommendations = literatureRecommendations
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.researcherEvaluation = researcherEvaluation
        self.methodFeedbackComment = methodFeedbackComment
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id
        case triptychID = "triptych_id"
        case title = "record_title"
        case kind, action, method
        case sourceReference = "source_reference"
        case zoteroBibliographicContext = "zotero_bibliographic_context"
        case analysisSourceRoute = "analysis_source_route"
        case continuationLineage = "continuation_lineage"
        case primaryNoteID = "primary_note_id"
        case participatingNotes = "participating_notes"
        case statements
        case resultDisposition = "result_disposition"
        case academicResults = "academic_results"
        case contextUseReport = "context_use_report"
        case actuallyUsedMaterials = "actually_used_materials"
        case fidelityCompletion = "fidelity_completion"
        case confirmedChanges = "confirmed_changes"
        case discrepancies
        case literatureRecommendations = "literature_recommendations"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case researcherEvaluation = "researcher_evaluation"
        case methodFeedbackComment = "method_feedback_comment"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchRecordError.unsupportedSchemaVersion(schemaVersion)
        }
        let continuationLineage = try container.decodeIfPresent(
            ResearchContinuationLineage.self,
            forKey: .continuationLineage
        )
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            triptychID: container.decode(UUID.self, forKey: .triptychID),
            title: container.decode(ResearchRecordTitle.self, forKey: .title),
            kind: container.decode(PortableResearchRecordKind.self, forKey: .kind),
            action: container.decodeIfPresent(
                ResearchActionRecordIdentity.self,
                forKey: .action
            ),
            method: container.decodeIfPresent(
                PortableResearchMethodReference.self,
                forKey: .method
            ),
            sourceReference: container.decodeIfPresent(
                PortableResearchStrictSourceReference.self,
                forKey: .sourceReference
            )?.value,
            zoteroBibliographicContext: container.decodeIfPresent(
                ZoteroBibliographicContext.self,
                forKey: .zoteroBibliographicContext
            ),
            analysisSourceRoute: container.decodeIfPresent(
                ResearchAnalysisSourceRoute.self,
                forKey: .analysisSourceRoute
            ),
            continuationLineage: continuationLineage,
            primaryNoteID: container.decodeIfPresent(UUID.self, forKey: .primaryNoteID),
            participatingNotes: container.decode(
                [PortableResearchNoteRevision].self,
                forKey: .participatingNotes
            ),
            statements: container.decode(
                [PortableResearchStatement].self,
                forKey: .statements
            ),
            resultDisposition: container.decode(
                ResearchAgentResultDisposition.self,
                forKey: .resultDisposition
            ),
            academicResults: container.decode(
                [PortableResearchAcademicFieldResult].self,
                forKey: .academicResults
            ),
            contextUseReport: container.decodeIfPresent(
                ContextUseReport.self,
                forKey: .contextUseReport
            ),
            actuallyUsedMaterials: container.decode(
                [PortableResearchMaterialUse].self,
                forKey: .actuallyUsedMaterials
            ),
            fidelityCompletion: container.decode(
                PortableResearchFidelityCompletion.self,
                forKey: .fidelityCompletion
            ),
            confirmedChanges: container.decode(
                [PortableResearchConfirmedChange].self,
                forKey: .confirmedChanges
            ),
            discrepancies: container.decode(
                [PortableResearchDiscrepancy].self,
                forKey: .discrepancies
            ),
            literatureRecommendations: container.decode(
                [ResearchLiteratureRecommendation].self,
                forKey: .literatureRecommendations
            ),
            startedAt: container.decode(Date.self, forKey: .startedAt),
            finishedAt: container.decode(Date.self, forKey: .finishedAt),
            researcherEvaluation: container.decodeIfPresent(
                PortableResearcherEvaluation.self,
                forKey: .researcherEvaluation
            ),
            methodFeedbackComment: container.decodeIfPresent(
                PortableResearchMethodFeedbackComment.self,
                forKey: .methodFeedbackComment
            )
        )
    }

    private static func validAnalysisSourceRoute(
        actionID: ResearchActionID?,
        route: ResearchAnalysisSourceRoute?,
        sourceReference: ResearchSourceReference?,
        zoteroContext: ZoteroBibliographicContext?
    ) -> Bool {
        guard actionID == .analyze else {
            return route == nil
        }
        switch route {
        case .scholiumSource:
            return sourceReference != nil
        case .externalZotero:
            return sourceReference == nil && zoteroContext != nil
        case .researcherProvided:
            return sourceReference == nil && zoteroContext == nil
        case nil:
            return false
        }
    }
}

public enum PortableResearchRecordError: LocalizedError, Hashable, Sendable {
    case unsupportedField(String)
    case unsupportedSchemaVersion(Int)
    case invalidStatement
    case invalidNoteRevision
    case invalidMethodReference
    case invalidMaterialUse
    case invalidConfirmedChange
    case invalidRecordTitle
    case invalidRecord

    public var errorDescription: String? {
        switch self {
        case .unsupportedField(let field):
            "The portable Research Record contains unsupported field \(field)."
        case .unsupportedSchemaVersion(let version):
            "Unsupported portable Research Record schema version \(version)."
        case .invalidStatement:
            "The portable Research Record contains an invalid attributed statement."
        case .invalidNoteRevision:
            "The portable Research Record contains an invalid note revision."
        case .invalidMethodReference:
            "The portable Research Record contains an invalid Method reference."
        case .invalidMaterialUse:
            "The portable Research Record contains an invalid actually-used Material."
        case .invalidConfirmedChange:
            "The portable Research Record contains an invalid confirmed change."
        case .invalidRecordTitle:
            "The portable Research Record title must be one concise line."
        case .invalidRecord:
            "The portable Research Record violates its bounded schema."
        }
    }
}

private struct PortableResearchRecordAnyCodingKey: CodingKey {
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

private struct PortableResearchStrictFingerprint: Decodable {
    let value: DocumentFingerprint

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sha256, byteCount
    }

    init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = DocumentFingerprint(
            sha256: try container.decode(String.self, forKey: .sha256),
            byteCount: try container.decode(Int.self, forKey: .byteCount)
        )
        guard PortableResearchRecordValidation.isValidFingerprint(value) else {
            throw PortableResearchRecordError.invalidRecord
        }
    }
}

private struct PortableResearchStrictNoteID: Decodable {
    let value: VaultQualifiedNoteID

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case vaultID, relativePath
    }

    init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = VaultQualifiedNoteID(
            vaultID: try container.decode(UUID.self, forKey: .vaultID),
            relativePath: try container.decode(String.self, forKey: .relativePath)
        )
        guard PortableResearchRecordValidation.isValidNote(value) else {
            throw PortableResearchRecordError.invalidNoteRevision
        }
    }
}

private struct PortableResearchStrictPassage: Decodable {
    let value: CommentAnchor

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fingerprint, utf8Range, utf16Range, line, endLine, quotation
        case selectedText, contextBefore, contextAfter, state
    }

    init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = CommentAnchor(
            fingerprint: try container.decode(
                PortableResearchStrictFingerprint.self,
                forKey: .fingerprint
            ).value,
            utf8Range: try container.decode(Range<Int>.self, forKey: .utf8Range),
            utf16Range: try container.decode(Range<Int>.self, forKey: .utf16Range),
            line: try container.decode(Int.self, forKey: .line),
            endLine: try container.decode(Int.self, forKey: .endLine),
            quotation: try container.decode(String.self, forKey: .quotation),
            selectedText: try container.decodeIfPresent(String.self, forKey: .selectedText),
            contextBefore: try container.decode(String.self, forKey: .contextBefore),
            contextAfter: try container.decode(String.self, forKey: .contextAfter),
            state: try container.decode(CommentAttachmentState.self, forKey: .state)
        )
        guard PortableResearchRecordValidation.isValidPassage(value) else {
            throw PortableResearchRecordError.invalidStatement
        }
    }
}

private struct PortableResearchStrictSourceReference: Decodable {
    let value: ResearchSourceReference

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, identity, displayName, fingerprint
    }

    init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == ResearchSourceReference.currentSchemaVersion else {
            throw PortableResearchRecordError.invalidRecord
        }
        value = try ResearchSourceReference(
            identity: container.decode(ResearchSourceIdentity.self, forKey: .identity),
            displayName: container.decode(String.self, forKey: .displayName),
            fingerprint: container.decode(
                PortableResearchStrictFingerprint.self,
                forKey: .fingerprint
            ).value
        )
    }
}

enum PortableResearchRecordValidation {
    static func isValidFingerprint(_ fingerprint: DocumentFingerprint) -> Bool {
        fingerprint.byteCount >= 0
            && fingerprint.sha256.count == 64
            && fingerprint.sha256.unicodeScalars.allSatisfy { scalar in
                ("0"..."9").contains(Character(scalar))
                    || ("a"..."f").contains(Character(scalar))
            }
    }

    static func isValidNote(_ note: VaultQualifiedNoteID) -> Bool {
        note.relativePath.utf8.count <= 4_096
            && !containsAbsolutePath(note.relativePath)
            && (try? MarkdownRelativePath(note.relativePath)) != nil
    }

    static func isValidResourcePath(_ path: String) -> Bool {
        let components = path.components(separatedBy: "/")
        return !path.isEmpty
            && path.utf8.count <= 4_096
            && !containsAbsolutePath(path)
            && !path.hasPrefix("/")
            && !path.contains("\\")
            && !path.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
            && components.allSatisfy { component in
                !component.isEmpty && component != "." && component != ".."
            }
    }

    static func isValidPassage(_ passage: CommentAnchor) -> Bool {
        guard isValidFingerprint(passage.fingerprint),
              passage.utf8Range.lowerBound >= 0,
              passage.utf8Range.upperBound > passage.utf8Range.lowerBound,
              passage.utf8Range.count == passage.quotation.utf8.count,
              passage.utf16Range.lowerBound >= 0,
              passage.utf16Range.upperBound > passage.utf16Range.lowerBound,
              passage.utf16Range.count == passage.quotation.utf16.count,
              passage.line > 0,
              passage.endLine >= passage.line,
              !passage.quotation.isEmpty,
              passage.quotation.utf8.count <= 256 * 1024,
              (passage.selectedText?.utf8.count ?? 0) <= 256 * 1024,
              passage.contextBefore.utf8.count <= 4_096,
              passage.contextAfter.utf8.count <= 4_096 else {
            return false
        }
        return [
            passage.quotation,
            passage.selectedText ?? "",
            passage.contextBefore,
            passage.contextAfter,
        ].allSatisfy { !containsAbsolutePath($0) }
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: [String]
    ) throws {
        let container = try decoder.container(
            keyedBy: PortableResearchRecordAnyCodingKey.self
        )
        let allowed = Set(allowed)
        if let unknown = container.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw PortableResearchRecordError.unsupportedField(unknown)
        }
    }

    static func containsAbsolutePath(_ value: String) -> Bool {
        var candidate = value.precomposedStringWithCompatibilityMapping
        if containsAbsolutePathSyntax(candidate) { return true }
        for _ in 0..<3 {
            guard let decoded = candidate.removingPercentEncoding,
                  decoded != candidate else {
                break
            }
            candidate = decoded.precomposedStringWithCompatibilityMapping
            if containsAbsolutePathSyntax(candidate) { return true }
        }
        return false
    }

    static func hasNoDisallowedControlCharacters(_ value: String) -> Bool {
        !value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && scalar.value != 10
                && scalar.value != 9
        }
    }

    private static func containsAbsolutePathSyntax(_ value: String) -> Bool {
        let characters = Array(value)

        for index in characters.indices {
            let character = characters[index]
            let nextIndex = characters.index(after: index)
            let hasNext = nextIndex < characters.endIndex
            let next = hasNext ? characters[nextIndex] : nil
            let isBoundary = index == characters.startIndex
                || isPathBoundary(characters[characters.index(before: index)])

            if character == "~", isBoundary, next == "/" || next == "\\" {
                return true
            }

            if character == "/" {
                guard isBoundary else { continue }
                if isWebURLSlash(characters, at: index) {
                    continue
                }
                guard let next, !next.isWhitespace else { continue }
                return true
            }

            if character == "\\" {
                guard isBoundary, let next, !next.isWhitespace else { continue }
                return true
            }

            guard isASCIIAlpha(character), hasNext, next == ":" else { continue }
            let pathIndex = characters.index(after: nextIndex)
            guard pathIndex < characters.endIndex,
                  characters[pathIndex] == "/" || characters[pathIndex] == "\\",
                  isBoundary else {
                continue
            }
            return true
        }
        return false
    }

    private static func isPathBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)
        }
    }

    private static func isWebURLSlash(
        _ characters: [Character],
        at index: Int
    ) -> Bool {
        if isFirstWebURLSlash(characters, at: index) { return true }
        guard index > 0, characters[index - 1] == "/" else { return false }
        return isFirstWebURLSlash(characters, at: index - 1)
    }

    private static func isFirstWebURLSlash(
        _ characters: [Character],
        at index: Int
    ) -> Bool {
        guard index + 1 < characters.count,
              characters[index] == "/",
              characters[index + 1] == "/" else {
            return false
        }
        for scheme in ["http", "https"] {
            let schemeCharacters = Array(scheme)
            let schemeStart = index - schemeCharacters.count - 1
            guard schemeStart >= 0,
                  characters[index - 1] == ":",
                  Array(characters[schemeStart..<(index - 1)])
                    .map({ Character(String($0).lowercased()) })
                    == schemeCharacters else {
                continue
            }
            if schemeStart == 0 || isPathBoundary(characters[schemeStart - 1]) {
                return true
            }
        }
        return false
    }

    private static func isASCIIAlpha(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        return (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
}
