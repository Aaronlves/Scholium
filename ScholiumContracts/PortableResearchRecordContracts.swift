import Foundation

/// The durable scholarly shape of one portable Research Record.
///
/// Storage location is intentionally not encoded: `active/`, `records/`, and
/// `trash/` remain filesystem state owned by the portable store.
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

/// One stable note identity and its revisions during the recorded scholarly
/// exchange. A missing ending revision is reserved for an explicit tombstone;
/// it never reconstructs the deleted Markdown.
public struct PortableResearchNoteRevision: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchActionTargetRole
    public let title: String
    public let startingRevision: DocumentFingerprint
    public let endingRevision: DocumentFingerprint?
    public let isTombstone: Bool

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        title: String,
        startingRevision: DocumentFingerprint,
        endingRevision: DocumentFingerprint?,
        isTombstone: Bool = false
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              title.utf8.count <= 1_024,
              !PortableResearchRecordValidation.containsAbsolutePath(title),
              PortableResearchRecordValidation.isValidNote(note),
              PortableResearchRecordValidation.isValidFingerprint(startingRevision),
              endingRevision.map(PortableResearchRecordValidation.isValidFingerprint) ?? true,
              isTombstone == (endingRevision == nil) else {
            throw PortableResearchRecordError.invalidNoteRevision
        }
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title
        self.startingRevision = startingRevision
        self.endingRevision = endingRevision
        self.isTombstone = isTombstone
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID = "note_id"
        case note, role, title
        case startingRevision = "starting_revision"
        case endingRevision = "ending_revision"
        case isTombstone = "is_tombstone"
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
            endingRevision: container.decodeIfPresent(
                PortableResearchStrictFingerprint.self,
                forKey: .endingRevision
            )?.value,
            isTombstone: container.decode(Bool.self, forKey: .isTombstone)
        )
    }
}

/// Exact Method and Profile revisions retained without the Method prose,
/// assembled prompt, Action parameters, authority grant, or machine locator.
public struct PortableResearchMethodReference: Codable, Hashable, Sendable {
    public let packageID: String
    public let origin: ResearchSkillOrigin
    public let version: String
    public let packageRevision: DocumentFingerprint
    public let loadedResources: [ResearchActionResourceSnapshot]
    public let profileRevision: DocumentFingerprint

    public init(snapshot: ResearchActionSnapshot) throws {
        guard snapshot.method.packageID.utf8.count <= 256,
              snapshot.method.version.utf8.count <= 128,
              !PortableResearchRecordValidation.containsAbsolutePath(
                snapshot.method.packageID
              ),
              !PortableResearchRecordValidation.containsAbsolutePath(
                snapshot.method.version
              ),
              PortableResearchRecordValidation.isValidFingerprint(
                snapshot.method.packageRevision
              ),
              PortableResearchRecordValidation.isValidFingerprint(
                snapshot.resolvedProfile.profileRevision
              ),
              snapshot.method.loadedResources.allSatisfy({
                PortableResearchRecordValidation.isValidFingerprint($0.revision)
                    && PortableResearchRecordValidation.isValidResourcePath(
                        $0.relativePath
                    )
              }) else {
            throw PortableResearchRecordError.invalidMethodReference
        }
        packageID = snapshot.method.packageID
        origin = snapshot.method.origin
        version = snapshot.method.version
        packageRevision = snapshot.method.packageRevision
        loadedResources = snapshot.method.loadedResources
        profileRevision = snapshot.resolvedProfile.profileRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case packageID = "package_id"
        case origin, version
        case packageRevision = "package_revision"
        case loadedResources = "loaded_resources"
        case profileRevision = "profile_revision"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let packageID = try container.decode(String.self, forKey: .packageID)
        let version = try container.decode(String.self, forKey: .version)
        let loadedResources = try container.decode(
            [PortableResearchStrictResourceSnapshot].self,
            forKey: .loadedResources
        ).map(\.value)
        guard !packageID.isEmpty,
              packageID.utf8.count <= 256,
              !PortableResearchRecordValidation.containsAbsolutePath(packageID),
              version.utf8.count <= 128,
              !PortableResearchRecordValidation.containsAbsolutePath(version),
              loadedResources.allSatisfy({ resource in
                  PortableResearchRecordValidation.isValidResourcePath(
                      resource.relativePath
                  )
              }) else {
            throw PortableResearchRecordError.invalidMethodReference
        }
        let origin = try container.decode(ResearchSkillOrigin.self, forKey: .origin)
        let packageRevision = try container.decode(
            PortableResearchStrictFingerprint.self,
            forKey: .packageRevision
        ).value
        let profileRevision = try container.decode(
            PortableResearchStrictFingerprint.self,
            forKey: .profileRevision
        ).value
        let validated: ResearchActionMethodSnapshot
        do {
            validated = try ResearchActionMethodSnapshot(
                packageID: packageID,
                origin: origin,
                version: version,
                packageRevision: packageRevision,
                loadedResources: loadedResources
            )
        } catch {
            throw PortableResearchRecordError.invalidMethodReference
        }
        guard PortableResearchRecordValidation.isValidFingerprint(packageRevision),
              PortableResearchRecordValidation.isValidFingerprint(profileRevision),
              loadedResources.allSatisfy({
                PortableResearchRecordValidation.isValidFingerprint($0.revision)
              }) else {
            throw PortableResearchRecordError.invalidMethodReference
        }
        self.packageID = validated.packageID
        self.origin = validated.origin
        self.version = validated.version
        self.packageRevision = validated.packageRevision
        self.loadedResources = validated.loadedResources
        self.profileRevision = profileRevision
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

public struct PortableResearchConfirmedChange: Codable, Hashable, Identifiable, Sendable {
    public let noteID: UUID
    public let startingRevision: DocumentFingerprint
    public let endingRevision: DocumentFingerprint

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        startingRevision: DocumentFingerprint,
        endingRevision: DocumentFingerprint
    ) throws {
        guard startingRevision != endingRevision,
              PortableResearchRecordValidation.isValidFingerprint(startingRevision),
              PortableResearchRecordValidation.isValidFingerprint(endingRevision) else {
            throw PortableResearchRecordError.invalidConfirmedChange
        }
        self.noteID = noteID
        self.startingRevision = startingRevision
        self.endingRevision = endingRevision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID = "note_id"
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

/// Whitelisted, portable scholarly evidence for one finished Discussion or
/// validated nonconversational Action. It deliberately has no generic metadata
/// dictionary, so machine-local execution fields cannot leak through encoding.
public struct PortableResearchRecord: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let id: UUID
    public let triptychID: UUID
    public let kind: PortableResearchRecordKind
    public let action: ResearchActionRecordIdentity?
    public let method: PortableResearchMethodReference?
    public let sourceReference: ResearchSourceReference?
    public let continuationLineage: ResearchContinuationLineage?
    public let primaryNoteID: UUID?
    public let participatingNotes: [PortableResearchNoteRevision]
    public let statements: [PortableResearchStatement]
    public let actuallyUsedMaterials: [PortableResearchMaterialUse]
    public let confirmedChanges: [PortableResearchConfirmedChange]
    public let discrepancies: [PortableResearchDiscrepancy]
    public let startedAt: Date
    public let finishedAt: Date
    public let isPinned: Bool

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        kind: PortableResearchRecordKind,
        action: ResearchActionRecordIdentity?,
        method: PortableResearchMethodReference?,
        sourceReference: ResearchSourceReference? = nil,
        continuationLineage: ResearchContinuationLineage? = nil,
        primaryNoteID: UUID? = nil,
        participatingNotes: [PortableResearchNoteRevision],
        statements: [PortableResearchStatement],
        actuallyUsedMaterials: [PortableResearchMaterialUse] = [],
        confirmedChanges: [PortableResearchConfirmedChange] = [],
        discrepancies: [PortableResearchDiscrepancy] = [],
        startedAt: Date,
        finishedAt: Date,
        isPinned: Bool = false
    ) throws {
        let participatingByID = Dictionary(
            participatingNotes.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let statementIDs = statements.map(\.id)
        let discrepancyIDs = discrepancies.map(\.id)
        guard startedAt.timeIntervalSinceReferenceDate.isFinite,
              finishedAt.timeIntervalSinceReferenceDate.isFinite,
              finishedAt >= startedAt,
              !participatingNotes.isEmpty,
              participatingNotes.count <= 256,
              statements.count <= 4_096,
              actuallyUsedMaterials.count <= 256,
              confirmedChanges.count <= 256,
              discrepancies.count <= 256,
              participatingByID.count == participatingNotes.count,
              Set(statementIDs).count == statementIDs.count,
              zip(statements, statements.dropFirst()).allSatisfy({ pair in
                  pair.0.createdAt <= pair.1.createdAt
              }),
              Set(discrepancyIDs).count == discrepancyIDs.count,
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
                  return participant.startingRevision == change.startingRevision
                      && (participant.isTombstone
                          || participant.endingRevision == change.endingRevision)
              }),
              discrepancies.allSatisfy({ discrepancy in
                  participatingByID[discrepancy.noteID] != nil
              }),
              (action == nil) == (method == nil) else {
            throw PortableResearchRecordError.invalidRecord
        }
        switch kind {
        case .action:
            guard action != nil,
                  method != nil,
                  primaryNoteID.map({ participatingByID[$0] != nil }) ?? true else {
                throw PortableResearchRecordError.invalidRecord
            }
        case .discussion:
            guard let primaryNoteID,
                  participatingByID[primaryNoteID] != nil,
                  !statements.isEmpty,
                  continuationLineage == nil else {
                throw PortableResearchRecordError.invalidRecord
            }
        }
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.triptychID = triptychID
        self.kind = kind
        self.action = action
        self.method = method
        self.sourceReference = sourceReference
        self.continuationLineage = continuationLineage
        self.primaryNoteID = primaryNoteID
        self.participatingNotes = participatingNotes.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        self.statements = statements
        self.actuallyUsedMaterials = actuallyUsedMaterials.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        self.confirmedChanges = confirmedChanges.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        self.discrepancies = discrepancies.sorted {
            if $0.noteID != $1.noteID { return $0.noteID.uuidString < $1.noteID.uuidString }
            return $0.id.uuidString < $1.id.uuidString
        }
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id
        case triptychID = "triptych_id"
        case kind, action, method
        case sourceReference = "source_reference"
        case continuationLineage = "continuation_lineage"
        case primaryNoteID = "primary_note_id"
        case participatingNotes = "participating_notes"
        case statements
        case actuallyUsedMaterials = "actually_used_materials"
        case confirmedChanges = "confirmed_changes"
        case discrepancies
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case isPinned = "is_pinned"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 || schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchRecordError.unsupportedSchemaVersion(schemaVersion)
        }
        let continuationLineage = try container.decodeIfPresent(
            ResearchContinuationLineage.self,
            forKey: .continuationLineage
        )
        guard schemaVersion == Self.currentSchemaVersion
                || continuationLineage == nil else {
            throw PortableResearchRecordError.invalidRecord
        }
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            triptychID: container.decode(UUID.self, forKey: .triptychID),
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
            actuallyUsedMaterials: container.decode(
                [PortableResearchMaterialUse].self,
                forKey: .actuallyUsedMaterials
            ),
            confirmedChanges: container.decode(
                [PortableResearchConfirmedChange].self,
                forKey: .confirmedChanges
            ),
            discrepancies: container.decode(
                [PortableResearchDiscrepancy].self,
                forKey: .discrepancies
            ),
            startedAt: container.decode(Date.self, forKey: .startedAt),
            finishedAt: container.decode(Date.self, forKey: .finishedAt),
            isPinned: container.decode(Bool.self, forKey: .isPinned)
        )
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

private struct PortableResearchStrictResourceSnapshot: Decodable {
    let value: ResearchActionResourceSnapshot

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case relativePath = "relative_path"
        case revision
    }

    init(from decoder: Decoder) throws {
        try PortableResearchRecordValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let relativePath = try container.decode(String.self, forKey: .relativePath)
        let revision = try container.decode(
            PortableResearchStrictFingerprint.self,
            forKey: .revision
        ).value
        guard PortableResearchRecordValidation.isValidResourcePath(relativePath) else {
            throw PortableResearchRecordError.invalidMethodReference
        }
        value = ResearchActionResourceSnapshot(
            relativePath: relativePath,
            revision: revision
        )
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

private enum PortableResearchRecordValidation {
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
        value.split(whereSeparator: { character in
            character.isWhitespace
                || "\"'`()[]{}<>,;".contains(character)
        }).contains { rawToken in
            let token = String(rawToken)
            if token.lowercased().hasPrefix("file://") { return true }
            if token.hasPrefix("/") && token.split(separator: "/").count > 1 {
                return true
            }
            let scalars = Array(token.unicodeScalars)
            return scalars.count >= 3
                && CharacterSet.letters.contains(scalars[0])
                && scalars[1] == ":"
                && (scalars[2] == "\\" || scalars[2] == "/")
        }
    }
}
