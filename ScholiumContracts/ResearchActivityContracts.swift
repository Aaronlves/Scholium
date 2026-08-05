import Foundation

/// A researcher-owned judgment that one exact saved revision is sufficiently
/// stable for current work. It is neither a truth claim nor qualification.
public struct SettlementRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let noteID: UUID
    public let fingerprint: DocumentFingerprint
    public let settledAt: Date
    public let researcher: String
    public let rationale: String?

    public init(
        id: UUID = UUID(),
        noteID: UUID,
        fingerprint: DocumentFingerprint,
        settledAt: Date = Date(),
        researcher: String = "Researcher",
        rationale: String? = nil
    ) {
        self.id = id
        self.noteID = noteID
        self.fingerprint = fingerprint
        self.settledAt = settledAt
        self.researcher = researcher.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rationale = normalized?.isEmpty == false ? normalized : nil
    }
}

/// One document identity in the Application-confirmed write report for a Run.
/// It is a snapshot for attribution, not a new document or relation owner.
public struct ResearchRunWriteNoteReference: Codable, Hashable, Identifiable,
    Sendable
{
    public let noteID: UUID
    public let note: VaultQualifiedNoteID
    public let role: ResearchFunctionTargetRole
    public let title: String

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        note: VaultQualifiedNoteID,
        role: ResearchFunctionTargetRole,
        title: String
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 1_024 else {
            throw ResearchRunWriteReportError.invalidReference
        }
        self.noteID = noteID
        self.note = note
        self.role = role
        self.title = title
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noteID = "note_id"
        case note, role, title
    }

    public init(from decoder: Decoder) throws {
        try ResearchRunWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            noteID: container.decode(UUID.self, forKey: .noteID),
            note: container.decode(VaultQualifiedNoteID.self, forKey: .note),
            role: container.decode(ResearchFunctionTargetRole.self, forKey: .role),
            title: container.decode(String.self, forKey: .title)
        )
    }
}

/// Application-confirmed per-Run write facts derived from bounded transaction
/// records. Agent prose, candidate paths, keys, and permission claims are not
/// accepted here.
public struct ResearchRunWriteReport: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let runID: UUID
    public let confirmedModifiedNotes: [ResearchRunWriteNoteReference]
    public let unmodifiedNotes: [ResearchRunWriteNoteReference]
    public let observedFingerprints: [UUID: DocumentFingerprint]
    public let completedAt: Date

    public init(
        runID: UUID,
        confirmedModifiedNotes: [ResearchRunWriteNoteReference],
        unmodifiedNotes: [ResearchRunWriteNoteReference],
        observedFingerprints: [UUID: DocumentFingerprint],
        completedAt: Date = Date()
    ) throws {
        let modified = try Self.orderedUnique(confirmedModifiedNotes)
        let unmodified = try Self.orderedUnique(unmodifiedNotes)
        let modifiedIDs = Set(modified.map(\.noteID))
        let unmodifiedIDs = Set(unmodified.map(\.noteID))
        guard modifiedIDs.isDisjoint(with: unmodifiedIDs),
              modifiedIDs.union(unmodifiedIDs) == Set(observedFingerprints.keys),
              observedFingerprints.values.allSatisfy({
                  $0.byteCount >= 0
                      && $0.sha256.range(
                          of: #"^[0-9a-f]{64}$"#,
                          options: .regularExpression
                      ) != nil
              }),
              completedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ResearchRunWriteReportError.invalidReport
        }
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.confirmedModifiedNotes = modified
        self.unmodifiedNotes = unmodified
        self.observedFingerprints = observedFingerprints
        self.completedAt = completedAt
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case confirmedModifiedNotes = "confirmed_modified_notes"
        case unmodifiedNotes = "unmodified_notes"
        case observedFingerprints = "observed_fingerprints"
        case completedAt = "completed_at"
    }

    public init(from decoder: Decoder) throws {
        try ResearchRunWriteCoding.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .schemaVersion)
                == Self.currentSchemaVersion else {
            throw ResearchRunWriteReportError.invalidReport
        }
        try self.init(
            runID: container.decode(UUID.self, forKey: .runID),
            confirmedModifiedNotes: container.decode(
                [ResearchRunWriteNoteReference].self,
                forKey: .confirmedModifiedNotes
            ),
            unmodifiedNotes: container.decode(
                [ResearchRunWriteNoteReference].self,
                forKey: .unmodifiedNotes
            ),
            observedFingerprints: container.decode(
                [UUID: DocumentFingerprint].self,
                forKey: .observedFingerprints
            ),
            completedAt: container.decode(Date.self, forKey: .completedAt)
        )
    }

    private static func orderedUnique(
        _ notes: [ResearchRunWriteNoteReference]
    ) throws -> [ResearchRunWriteNoteReference] {
        guard Set(notes.map(\.noteID)).count == notes.count,
              Set(notes.map(\.note)).count == notes.count else {
            throw ResearchRunWriteReportError.invalidReport
        }
        return notes.sorted {
            if $0.note.vaultID != $1.note.vaultID {
                return $0.note.vaultID.uuidString < $1.note.vaultID.uuidString
            }
            return $0.note.relativePath < $1.note.relativePath
        }
    }
}

public enum ResearchRunWriteReportError: Error, Hashable, Sendable {
    case invalidReference
    case invalidReport
}

private enum ResearchRunWriteCoding {
    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: some Sequence<String>
    ) throws {
        let container = try decoder.container(
            keyedBy: ResearchRunWriteCodingKey.self
        )
        let allowed = Set(allowed)
        guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) })
        else {
            throw ResearchRunWriteReportError.invalidReport
        }
    }
}

private struct ResearchRunWriteCodingKey: CodingKey {
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
