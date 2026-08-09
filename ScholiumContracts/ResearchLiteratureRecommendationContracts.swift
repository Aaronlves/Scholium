import Foundation

/// The complete agent-authored literature lead accepted by an Analyze
/// completion. The agent supplies only source-grounded scholarly content;
/// identity, grouping, and researcher disposition remain Application-owned.
public struct ResearchLiteratureRecommendationSubmission: Codable, Hashable, Sendable {
    public let rawCitation: String
    public let title: String?
    public let authors: [String]
    public let year: Int?
    public let publication: String?
    public let doi: String?
    public let zoteroItemKey: String?
    public let sourceLocators: [String]
    public let reason: String
    public let uncertainty: String?

    public init(
        rawCitation: String,
        title: String? = nil,
        authors: [String] = [],
        year: Int? = nil,
        publication: String? = nil,
        doi: String? = nil,
        zoteroItemKey: String? = nil,
        sourceLocators: [String] = [],
        reason: String,
        uncertainty: String? = nil
    ) throws {
        let rawCitation = Self.required(rawCitation)
        let title = Self.optional(title)
        let authors = authors.map(Self.required)
        let publication = Self.optional(publication)
        let doi = Self.optional(doi)
        let zoteroItemKey = try ResearchSourceIdentity.normalizedZoteroKey(zoteroItemKey)
        let sourceLocators = sourceLocators.map(Self.required)
        let reason = Self.required(reason)
        let uncertainty = Self.optional(uncertainty)

        guard !rawCitation.isEmpty,
              rawCitation.utf8.count <= 64 * 1024,
              title.map({ $0.utf8.count <= 16 * 1024 }) ?? true,
              authors.count <= 64,
              authors.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 2 * 1024 }),
              year.map({ (-9_999...9_999).contains($0) }) ?? true,
              publication.map({ $0.utf8.count <= 16 * 1024 }) ?? true,
              doi.map({ $0.utf8.count <= 2 * 1024 }) ?? true,
              sourceLocators.count <= 64,
              sourceLocators.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4 * 1024 }),
              !reason.isEmpty,
              reason.utf8.count <= 64 * 1024,
              uncertainty.map({ $0.utf8.count <= 64 * 1024 }) ?? true,
              [rawCitation, title, publication, doi, reason, uncertainty]
                .compactMap({ $0 })
                .allSatisfy(Self.hasNoControlCharacters),
              authors.allSatisfy(Self.hasNoControlCharacters),
              sourceLocators.allSatisfy(Self.hasNoControlCharacters),
              [rawCitation, title, publication, doi, zoteroItemKey, reason, uncertainty]
                .compactMap({ $0 })
                .allSatisfy({
                    !PortableResearchRecordValidation.containsAbsolutePath($0)
                }),
              authors.allSatisfy({
                  !PortableResearchRecordValidation.containsAbsolutePath($0)
              }),
              sourceLocators.allSatisfy({
                  !PortableResearchRecordValidation.containsAbsolutePath($0)
              }) else {
            throw ResearchLiteratureRecommendationError.invalidSubmission
        }

        self.rawCitation = rawCitation
        self.title = title
        self.authors = authors
        self.year = year
        self.publication = publication
        self.doi = doi
        self.zoteroItemKey = zoteroItemKey
        self.sourceLocators = sourceLocators
        self.reason = reason
        self.uncertainty = uncertainty
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case rawCitation
        case title
        case authors
        case year
        case publication
        case doi
        case zoteroItemKey
        case sourceLocators
        case reason
        case uncertainty
    }

    public init(from decoder: Decoder) throws {
        try ResearchLiteratureRecommendationValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            rawCitation: container.decode(String.self, forKey: .rawCitation),
            title: container.decodeIfPresent(String.self, forKey: .title),
            authors: container.decodeIfPresent([String].self, forKey: .authors) ?? [],
            year: container.decodeIfPresent(Int.self, forKey: .year),
            publication: container.decodeIfPresent(String.self, forKey: .publication),
            doi: container.decodeIfPresent(String.self, forKey: .doi),
            zoteroItemKey: container.decodeIfPresent(String.self, forKey: .zoteroItemKey),
            sourceLocators: container.decodeIfPresent(
                [String].self,
                forKey: .sourceLocators
            ) ?? [],
            reason: container.decode(String.self, forKey: .reason),
            uncertainty: container.decodeIfPresent(String.self, forKey: .uncertainty)
        )
    }

    private static func required(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optional(_ value: String?) -> String? {
        guard let normalized = value.map(required), !normalized.isEmpty else { return nil }
        return normalized
    }

    private static func hasNoControlCharacters(_ value: String) -> Bool {
        !value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && scalar.value != 10
                && scalar.value != 9
        }
    }
}

public enum ResearchLiteratureRecommendationDispositionStatus: String, Codable, Hashable, Sendable {
    case unprocessed
    case handled
}

/// Researcher-owned state for one occurrence in one parent Research Record.
/// It does not assert reading, acceptance, citation, verification, or agreement.
public struct PortableResearchRecommendationDisposition: Codable, Hashable, Sendable {
    public let status: ResearchLiteratureRecommendationDispositionStatus
    public let updatedAt: Date
    public let researcherNote: String?

    public init(
        status: ResearchLiteratureRecommendationDispositionStatus,
        updatedAt: Date,
        researcherNote: String? = nil
    ) throws {
        let trimmedNote = researcherNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let researcherNote = trimmedNote?.isEmpty == false ? trimmedNote : nil
        guard updatedAt.timeIntervalSinceReferenceDate.isFinite,
              researcherNote.map({
                  !$0.isEmpty
                      && $0.utf8.count <= 64 * 1024
                      && PortableResearchRecordValidation
                          .hasNoDisallowedControlCharacters($0)
                      && !PortableResearchRecordValidation.containsAbsolutePath($0)
              }) ?? true else {
            throw ResearchLiteratureRecommendationError.invalidDisposition
        }
        self.status = status
        self.updatedAt = updatedAt
        self.researcherNote = researcherNote
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case status
        case updatedAt = "updated_at"
        case researcherNote = "researcher_note"
    }

    public init(from decoder: Decoder) throws {
        try ResearchLiteratureRecommendationValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            status: container.decode(
                ResearchLiteratureRecommendationDispositionStatus.self,
                forKey: .status
            ),
            updatedAt: container.decode(Date.self, forKey: .updatedAt),
            researcherNote: container.decodeIfPresent(String.self, forKey: .researcherNote)
        )
    }
}

/// One portable Analyze-record occurrence. Its stable ID is derived from the
/// parent run and ordinal; it has no independent provenance or grouping state.
public struct ResearchLiteratureRecommendation: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let rawCitation: String
    public let title: String?
    public let authors: [String]
    public let year: Int?
    public let publication: String?
    public let doi: String?
    public let zoteroItemKey: String?
    public let sourceLocators: [String]
    public let reason: String
    public let uncertainty: String?
    public let disposition: PortableResearchRecommendationDisposition

    public init(
        id: UUID,
        submission: ResearchLiteratureRecommendationSubmission,
        disposition: PortableResearchRecommendationDisposition
    ) {
        self.id = id
        rawCitation = submission.rawCitation
        title = submission.title
        authors = submission.authors
        year = submission.year
        publication = submission.publication
        doi = submission.doi
        zoteroItemKey = submission.zoteroItemKey
        sourceLocators = submission.sourceLocators
        reason = submission.reason
        uncertainty = submission.uncertainty
        self.disposition = disposition
    }

    public init(
        id: UUID,
        rawCitation: String,
        title: String? = nil,
        authors: [String] = [],
        year: Int? = nil,
        publication: String? = nil,
        doi: String? = nil,
        zoteroItemKey: String? = nil,
        sourceLocators: [String] = [],
        reason: String,
        uncertainty: String? = nil,
        disposition: PortableResearchRecommendationDisposition
    ) throws {
        let submission = try ResearchLiteratureRecommendationSubmission(
            rawCitation: rawCitation,
            title: title,
            authors: authors,
            year: year,
            publication: publication,
            doi: doi,
            zoteroItemKey: zoteroItemKey,
            sourceLocators: sourceLocators,
            reason: reason,
            uncertainty: uncertainty
        )
        self.init(id: id, submission: submission, disposition: disposition)
    }

    public static func stableID(runID: UUID, ordinal: Int) -> UUID {
        let digest = DocumentFingerprint(
            content: "\(runID.uuidString.lowercased()):literature-recommendation:\(ordinal)"
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

    public func replacingDisposition(
        _ disposition: PortableResearchRecommendationDisposition
    ) throws -> Self {
        try Self(
            id: id,
            rawCitation: rawCitation,
            title: title,
            authors: authors,
            year: year,
            publication: publication,
            doi: doi,
            zoteroItemKey: zoteroItemKey,
            sourceLocators: sourceLocators,
            reason: reason,
            uncertainty: uncertainty,
            disposition: disposition
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case rawCitation = "raw_citation"
        case title
        case authors
        case year
        case publication
        case doi
        case zoteroItemKey = "zotero_item_key"
        case sourceLocators = "source_locators"
        case reason
        case uncertainty
        case disposition
    }

    public init(from decoder: Decoder) throws {
        try ResearchLiteratureRecommendationValidation.rejectUnknownFields(
            in: decoder,
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            rawCitation: container.decode(String.self, forKey: .rawCitation),
            title: container.decodeIfPresent(String.self, forKey: .title),
            authors: container.decode([String].self, forKey: .authors),
            year: container.decodeIfPresent(Int.self, forKey: .year),
            publication: container.decodeIfPresent(String.self, forKey: .publication),
            doi: container.decodeIfPresent(String.self, forKey: .doi),
            zoteroItemKey: container.decodeIfPresent(String.self, forKey: .zoteroItemKey),
            sourceLocators: container.decode([String].self, forKey: .sourceLocators),
            reason: container.decode(String.self, forKey: .reason),
            uncertainty: container.decodeIfPresent(String.self, forKey: .uncertainty),
            disposition: container.decode(
                PortableResearchRecommendationDisposition.self,
                forKey: .disposition
            )
        )
    }
}

public enum ResearchLiteratureRecommendationError: LocalizedError, Hashable, Sendable {
    case unsupportedField(String)
    case invalidSubmission
    case invalidDisposition

    public var errorDescription: String? {
        switch self {
        case .unsupportedField(let field):
            "A literature recommendation contains unsupported field \(field)."
        case .invalidSubmission:
            "The literature recommendation violates its bounded submission contract."
        case .invalidDisposition:
            "The literature recommendation has an invalid researcher disposition."
        }
    }
}

private struct ResearchLiteratureRecommendationAnyCodingKey: CodingKey {
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

private enum ResearchLiteratureRecommendationValidation {
    static func rejectUnknownFields(in decoder: Decoder, allowed: [String]) throws {
        let container = try decoder.container(
            keyedBy: ResearchLiteratureRecommendationAnyCodingKey.self
        )
        let allowed = Set(allowed)
        if let unknown = container.allKeys.map(\.stringValue)
            .first(where: { !allowed.contains($0) }) {
            throw ResearchLiteratureRecommendationError.unsupportedField(unknown)
        }
    }
}
