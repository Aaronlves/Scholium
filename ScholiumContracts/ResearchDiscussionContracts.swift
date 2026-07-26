import Foundation

/// One unfinished, portable scholarly exchange.
///
/// The containing `active/` directory establishes that this value is an
/// unfinished Discussion. Closing its presentation does not mutate it. Only
/// an explicit Finish operation converts it into a `PortableResearchRecord`.
public struct PortableResearchDiscussion: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let triptychID: UUID
    public let primaryNoteID: UUID
    public let action: ResearchActionRecordIdentity?
    public let method: PortableResearchMethodReference?
    public let participatingNotes: [PortableResearchNoteRevision]
    public let statements: [PortableResearchStatement]
    public let createdAt: Date
    public let updatedAt: Date

    public var primaryNote: PortableResearchNoteRevision {
        participatingNotes.first { $0.noteID == primaryNoteID }!
    }

    public var passage: CommentAnchor? {
        statements.lazy.compactMap(\.passage).first
    }

    public var lineReference: ResearchLineReference? {
        statements.lazy.compactMap(\.lineReference).first
    }

    public var awaitsAgentReply: Bool {
        statements.last?.author == .researcher
    }

    public init(
        id: UUID = UUID(),
        triptychID: UUID,
        primaryNoteID: UUID,
        action: ResearchActionRecordIdentity? = nil,
        method: PortableResearchMethodReference? = nil,
        participatingNotes: [PortableResearchNoteRevision],
        statements: [PortableResearchStatement],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let notesByID = Dictionary(
            participatingNotes.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let statementIDs = statements.map(\.id)
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= createdAt,
              notesByID[primaryNoteID] != nil,
              !participatingNotes.isEmpty,
              participatingNotes.count <= 256,
              notesByID.count == participatingNotes.count,
              participatingNotes.allSatisfy({ note in
                  !note.isTombstone && note.endingRevision == note.startingRevision
              }),
              !statements.isEmpty,
              statements.count <= 4_096,
              Set(statementIDs).count == statementIDs.count,
              zip(statements, statements.dropFirst()).allSatisfy({ pair in
                  pair.0.createdAt <= pair.1.createdAt
              }),
              statements.allSatisfy({ $0.createdAt >= createdAt && $0.createdAt <= updatedAt }),
              (action == nil) == (method == nil) else {
            throw PortableResearchDiscussionError.invalidDiscussion
        }
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.triptychID = triptychID
        self.primaryNoteID = primaryNoteID
        self.action = action
        self.method = method
        self.participatingNotes = participatingNotes.sorted {
            $0.noteID.uuidString < $1.noteID.uuidString
        }
        self.statements = statements
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func appending(
        _ statement: PortableResearchStatement,
        at updatedAt: Date
    ) throws -> Self {
        if let existing = statements.first(where: { $0.id == statement.id }) {
            guard existing == statement else {
                throw PortableResearchDiscussionError.duplicateStatement(statement.id)
            }
            return self
        }
        return try Self(
            id: id,
            triptychID: triptychID,
            primaryNoteID: primaryNoteID,
            action: action,
            method: method,
            participatingNotes: participatingNotes,
            statements: statements + [statement],
            createdAt: createdAt,
            updatedAt: max(self.updatedAt, max(updatedAt, statement.createdAt))
        )
    }

    public func replacingStatements(_ statements: [PortableResearchStatement]) throws -> Self {
        guard Set(statements.map(\.id)) == Set(self.statements.map(\.id)) else {
            throw PortableResearchDiscussionError.invalidDiscussion
        }
        return try Self(
            id: id,
            triptychID: triptychID,
            primaryNoteID: primaryNoteID,
            action: action,
            method: method,
            participatingNotes: participatingNotes,
            statements: statements,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Binds a Comment-only draft to the exact resolved Discuss Action while
    /// preserving its earlier researcher-authored line Comments.
    public func activating(
        action: ResearchActionRecordIdentity,
        method: PortableResearchMethodReference,
        participatingNotes: [PortableResearchNoteRevision],
        statement: PortableResearchStatement,
        at updatedAt: Date
    ) throws -> Self {
        let currentNotes = Dictionary(
            uniqueKeysWithValues: self.participatingNotes.map { ($0.noteID, $0) }
        )
        let activatedNotes = Dictionary(
            uniqueKeysWithValues: participatingNotes.map { ($0.noteID, $0) }
        )
        guard self.action == nil,
              self.method == nil,
              currentNotes.allSatisfy({ activatedNotes[$0.key] == $0.value }),
              statement.author == .researcher,
              statement.createdAt >= createdAt else {
            throw PortableResearchDiscussionError.invalidDiscussion
        }
        return try Self(
            id: id,
            triptychID: triptychID,
            primaryNoteID: primaryNoteID,
            action: action,
            method: method,
            participatingNotes: participatingNotes,
            statements: statements + [statement],
            createdAt: createdAt,
            updatedAt: max(self.updatedAt, max(updatedAt, statement.createdAt))
        )
    }

    public func finishedRecord(
        participatingNotes: [PortableResearchNoteRevision],
        finishedAt: Date
    ) throws -> PortableResearchRecord {
        let originalByID = Dictionary(
            uniqueKeysWithValues: self.participatingNotes.map { ($0.noteID, $0) }
        )
        let finishedByID = Dictionary(
            participatingNotes.map { ($0.noteID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard Set(originalByID.keys) == Set(finishedByID.keys),
              participatingNotes.count == finishedByID.count,
              participatingNotes.allSatisfy({ note in
                  guard let original = originalByID[note.noteID] else { return false }
                  return note.noteID == original.noteID
                      && note.note == original.note
                      && note.role == original.role
                      && note.title == original.title
                      && note.startingRevision == original.startingRevision
                      && !note.isTombstone
                      && note.endingRevision != nil
              }),
              finishedAt >= updatedAt else {
            throw PortableResearchDiscussionError.invalidFinish
        }
        return try PortableResearchRecord(
            id: id,
            triptychID: triptychID,
            kind: .discussion,
            action: action,
            method: method,
            primaryNoteID: primaryNoteID,
            participatingNotes: participatingNotes,
            statements: statements,
            startedAt: createdAt,
            finishedAt: finishedAt
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case id
        case triptychID = "triptych_id"
        case primaryNoteID = "primary_note_id"
        case action, method
        case participatingNotes = "participating_notes"
        case statements
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscussionCodingKey.self)
        let unknown = Set(container.allKeys.map(\.stringValue))
            .subtracting(CodingKeys.allCases.map(\.stringValue))
        if let field = unknown.sorted().first {
            throw PortableResearchRecordError.unsupportedField(field)
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchDiscussionError.unsupportedSchemaVersion(schemaVersion)
        }
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            triptychID: values.decode(UUID.self, forKey: .triptychID),
            primaryNoteID: values.decode(UUID.self, forKey: .primaryNoteID),
            action: values.decodeIfPresent(ResearchActionRecordIdentity.self, forKey: .action),
            method: values.decodeIfPresent(PortableResearchMethodReference.self, forKey: .method),
            participatingNotes: values.decode(
                [PortableResearchNoteRevision].self,
                forKey: .participatingNotes
            ),
            statements: values.decode([PortableResearchStatement].self, forKey: .statements),
            createdAt: values.decode(Date.self, forKey: .createdAt),
            updatedAt: values.decode(Date.self, forKey: .updatedAt)
        )
    }
}

public enum PortableResearchDiscussionError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidDiscussion
    case duplicateStatement(UUID)
    case invalidFinish

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported portable Discussion schema version \(version)."
        case .invalidDiscussion:
            "The portable Discussion violates its bounded schema."
        case .duplicateStatement(let id):
            "Discussion statement \(id.uuidString) already exists with different content."
        case .invalidFinish:
            "The finished Discussion does not match its active participants."
        }
    }
}

private struct DiscussionCodingKey: CodingKey {
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
