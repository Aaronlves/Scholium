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

    private enum CodingKeys: String, CodingKey {
        case id, noteID, fingerprint, settledAt, researcher, rationale
        // Retained only for exact compatibility with the portable v2 format.
        case legacyCoveredActivities = "coveredActivities"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        noteID = try container.decode(UUID.self, forKey: .noteID)
        fingerprint = try container.decode(DocumentFingerprint.self, forKey: .fingerprint)
        settledAt = try container.decode(Date.self, forKey: .settledAt)
        researcher = try container.decode(String.self, forKey: .researcher)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        _ = try container.decodeIfPresent(
            [LegacySettlementActivityReference].self,
            forKey: .legacyCoveredActivities
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(noteID, forKey: .noteID)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(settledAt, forKey: .settledAt)
        try container.encode(researcher, forKey: .researcher)
        try container.encodeIfPresent(rationale, forKey: .rationale)
        try container.encode(
            [LegacySettlementActivityReference](),
            forKey: .legacyCoveredActivities
        )
    }
}

private struct LegacySettlementActivityReference: Codable, Hashable {
    let recordID: UUID
    let noteID: UUID
}
