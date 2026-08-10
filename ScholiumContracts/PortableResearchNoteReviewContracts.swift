import Foundation

/// One Agent-confirmed source-change activity covered by an explicit review
/// of its Note. The pair remains stable even when a Record participates in
/// several Notes.
public struct PortableResearchNoteActivityReference: Codable, Hashable,
    Identifiable, Sendable
{
    public let recordID: UUID
    public let noteID: UUID

    public var id: String {
        "\(recordID.uuidString.lowercased()):\(noteID.uuidString.lowercased())"
    }

    public init(recordID: UUID, noteID: UUID) {
        self.recordID = recordID
        self.noteID = noteID
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case recordID = "record_id"
        case noteID = "note_id"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchNoteReviewValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            recordID: try container.decode(UUID.self, forKey: .recordID),
            noteID: try container.decode(UUID.self, forKey: .noteID)
        )
    }
}

/// The single portable review fact for one Note. Covered activities are
/// cumulative; `observedRevision` and `reviewedAt` describe the most recent
/// explicit review of the Note's saved source.
public struct PortableResearchNoteReview: Codable, Hashable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumCoveredActivities = 65_536

    public let schemaVersion: Int
    public let noteID: UUID
    public let observedRevision: DocumentFingerprint
    public let reviewedAt: Date
    public let coveredActivities: [PortableResearchNoteActivityReference]

    public var id: UUID { noteID }

    public init(
        noteID: UUID,
        observedRevision: DocumentFingerprint,
        reviewedAt: Date = Date(),
        coveredActivities: [PortableResearchNoteActivityReference]
    ) throws {
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            noteID: noteID,
            observedRevision: observedRevision,
            reviewedAt: reviewedAt,
            coveredActivities: coveredActivities
        )
    }

    private init(
        schemaVersion: Int,
        noteID: UUID,
        observedRevision: DocumentFingerprint,
        reviewedAt: Date,
        coveredActivities: [PortableResearchNoteActivityReference]
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw PortableResearchNoteReviewError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        guard PortableResearchNoteReviewValidation.isValidFingerprint(
                observedRevision
              ),
              reviewedAt.timeIntervalSinceReferenceDate.isFinite,
              !coveredActivities.isEmpty,
              coveredActivities.count <= Self.maximumCoveredActivities,
              coveredActivities.allSatisfy({ $0.noteID == noteID }),
              Set(coveredActivities).count == coveredActivities.count else {
            throw PortableResearchNoteReviewError.invalidReview
        }
        self.schemaVersion = schemaVersion
        self.noteID = noteID
        self.observedRevision = observedRevision
        self.reviewedAt = reviewedAt
        self.coveredActivities = coveredActivities.sorted {
            if $0.recordID != $1.recordID {
                return $0.recordID.uuidString < $1.recordID.uuidString
            }
            return $0.noteID.uuidString < $1.noteID.uuidString
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case noteID = "note_id"
        case observedRevision = "observed_revision"
        case reviewedAt = "reviewed_at"
        case coveredActivities = "covered_activities"
    }

    public init(from decoder: Decoder) throws {
        try PortableResearchNoteReviewValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            noteID: container.decode(UUID.self, forKey: .noteID),
            observedRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .observedRevision
            ),
            reviewedAt: container.decode(Date.self, forKey: .reviewedAt),
            coveredActivities: container.decode(
                [PortableResearchNoteActivityReference].self,
                forKey: .coveredActivities
            )
        )
    }
}

public enum PortableResearchNoteReviewError: LocalizedError, Hashable, Sendable {
    case unsupportedField(String)
    case unsupportedSchemaVersion(Int)
    case invalidReview

    public var errorDescription: String? {
        switch self {
        case .unsupportedField(let field):
            "The portable Note Review contains unsupported field \(field)."
        case .unsupportedSchemaVersion(let version):
            "Unsupported portable Note Review schema version \(version)."
        case .invalidReview:
            "The portable Note Review violates its bounded schema."
        }
    }
}

public enum PortableResearchNoteReviewMutationError: LocalizedError,
    Hashable, Sendable {
    case sourceChanged
    case sourceUnavailable
    case recordProjectionChanged
    case noPendingAgentChanges

    public var errorDescription: String? {
        switch self {
        case .sourceChanged:
            "The Note changed before it could be marked reviewed. Save and review the current source again."
        case .sourceUnavailable:
            "The Note is not currently available for review."
        case .recordProjectionChanged:
            "The set of Research Records changed before the Note Review was saved. Reload and review the current activities."
        case .noPendingAgentChanges:
            "There are no pending Agent changes for this Note."
        }
    }
}

private enum PortableResearchNoteReviewValidation {
    static func isValidFingerprint(_ fingerprint: DocumentFingerprint) -> Bool {
        fingerprint.byteCount >= 0
            && fingerprint.sha256.count == 64
            && fingerprint.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        allowed: [String]
    ) throws {
        let container = try decoder.container(
            keyedBy: PortableResearchNoteReviewAnyCodingKey.self
        )
        let allowed = Set(allowed)
        if let unknown = container.allKeys.first(where: {
            !allowed.contains($0.stringValue)
        }) {
            throw PortableResearchNoteReviewError.unsupportedField(
                unknown.stringValue
            )
        }
    }
}

private struct PortableResearchNoteReviewAnyCodingKey: CodingKey {
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
