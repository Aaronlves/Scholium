import Foundation

public struct ZoteroMetadataFillField: Codable, Hashable, Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let value: YAMLValue

    public init(key: String, value: YAMLValue) {
        self.key = key
        self.value = value
    }
}

/// One researcher-reviewed proposal. It binds the exact Zotero item and local
/// server to the current portable binding and Metadata revisions. Markdown and
/// authored YAML never participate in this value or its commit.
public struct ZoteroMetadataFillPlan: Codable, Hashable, Sendable {
    public let noteID: UUID
    public let sourceRevision: DocumentFingerprint
    public let source: ZoteroExactItemRead
    public let intendedBinding: AnalysisZoteroBinding
    public let currentBinding: AnalysisZoteroBinding?
    public let expectedBindingsRevision: DocumentFingerprint
    public let expectedMetadataRevision: DocumentFingerprint?
    public let resultFields: [String: YAMLValue]
    public let fieldsToFill: [ZoteroMetadataFillField]
    public let retainedConflicts: [ZoteroMetadataFillField]
    public let matchingFields: [ZoteroMetadataFillField]

    public init(
        noteID: UUID,
        sourceRevision: DocumentFingerprint,
        source: ZoteroExactItemRead,
        intendedBinding: AnalysisZoteroBinding,
        currentBinding: AnalysisZoteroBinding?,
        expectedBindingsRevision: DocumentFingerprint,
        expectedMetadataRevision: DocumentFingerprint?,
        resultFields: [String: YAMLValue],
        fieldsToFill: [ZoteroMetadataFillField],
        retainedConflicts: [ZoteroMetadataFillField],
        matchingFields: [ZoteroMetadataFillField]
    ) {
        self.noteID = noteID
        self.sourceRevision = sourceRevision
        self.source = source
        self.intendedBinding = intendedBinding
        self.currentBinding = currentBinding
        self.expectedBindingsRevision = expectedBindingsRevision
        self.expectedMetadataRevision = expectedMetadataRevision
        self.resultFields = resultFields
        self.fieldsToFill = fieldsToFill
        self.retainedConflicts = retainedConflicts
        self.matchingFields = matchingFields
    }
}

public struct ZoteroLinkAndFillResult: Codable, Hashable, Sendable {
    public let binding: AnalysisZoteroBinding
    public let metadata: NoteMetadataSnapshot?
    public let filledKeys: [String]
    public let retainedConflictKeys: [String]
    public let derivedRefreshWarning: String?

    public init(
        binding: AnalysisZoteroBinding,
        metadata: NoteMetadataSnapshot?,
        filledKeys: [String],
        retainedConflictKeys: [String],
        derivedRefreshWarning: String? = nil
    ) {
        self.binding = binding
        self.metadata = metadata
        self.filledKeys = filledKeys
        self.retainedConflictKeys = retainedConflictKeys
        self.derivedRefreshWarning = derivedRefreshWarning
    }
}

public enum ZoteroLinkAndFillError: LocalizedError, Equatable, Sendable {
    case invalidMetadataProposal
    case zoteroItemChanged
    case analysisSourceChanged
    case metadataNotFilledAfterBinding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMetadataProposal:
            "Zotero metadata could not be represented safely in this Analysis profile. No link or Metadata was changed."
        case .zoteroItemChanged:
            "The Zotero item changed after it was reviewed. Search again before linking and filling Metadata."
        case .analysisSourceChanged:
            "The Analysis source changed after Zotero Metadata was reviewed. Reopen Link and Fill from the current Analysis before retrying."
        case .metadataNotFilledAfterBinding(let reason):
            "The Zotero link was saved, but Metadata was not filled because its current revision could not be replaced safely. Reload and try again. \(reason)"
        }
    }
}

/// The sole deterministic Zotero-to-Scholium Metadata mapping. It proposes
/// only catalog fields applicable to the effective Analysis source type,
/// fills absent keys, and retains every existing researcher value.
public enum ZoteroMetadataFillPlanner {
    public static func plan(
        noteID: UUID,
        sourceRevision: DocumentFingerprint,
        bindingSnapshot: AnalysisZoteroBindingsSnapshot,
        metadataSnapshot: NoteMetadataSnapshot?,
        source: ZoteroExactItemRead
    ) throws -> ZoteroMetadataFillPlan {
        if let metadataSnapshot,
           metadataSnapshot.record.noteID != noteID {
            throw ZoteroLinkAndFillError.invalidMetadataProposal
        }
        let intendedBinding = try AnalysisZoteroBinding(
            noteID: noteID,
            library: source.library.identity,
            itemKey: source.item.key
        )
        let existing = metadataSnapshot?.record.fields ?? [:]
        let importedType = sourceType(for: source.item.itemType)
        let effectiveType: AnalysisSourceType
        if case .string(let rawType)? = existing["type"],
           let retainedType = AnalysisSourceType(rawValue: rawType) {
            effectiveType = retainedType
        } else {
            effectiveType = importedType
        }
        let applicable = Set(
            AnalysisSourceTypeProfileCatalog.profile(for: effectiveType).applicableFields
        )
        let proposed = mappedFields(item: source.item, sourceType: importedType)
            .filter { applicable.contains($0.key) }
        let proposedByKey = Dictionary(
            proposed.map { ($0.key, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        var resultFields = existing
        var toFill: [ZoteroMetadataFillField] = []
        var conflicts: [ZoteroMetadataFillField] = []
        var matching: [ZoteroMetadataFillField] = []
        for field in ordered(proposedByKey, sourceType: effectiveType) {
            if let retained = existing[field.key] {
                if retained == field.value {
                    matching.append(field)
                } else {
                    conflicts.append(field)
                }
            } else {
                resultFields[field.key] = field.value
                toFill.append(field)
            }
        }
        guard NoteMetadataContractCatalog.validate(
            fields: resultFields,
            profile: .analysis
        ).isEmpty else {
            throw ZoteroLinkAndFillError.invalidMetadataProposal
        }
        return ZoteroMetadataFillPlan(
            noteID: noteID,
            sourceRevision: sourceRevision,
            source: source,
            intendedBinding: intendedBinding,
            currentBinding: bindingSnapshot.binding(for: noteID),
            expectedBindingsRevision: bindingSnapshot.revision,
            expectedMetadataRevision: metadataSnapshot?.revision,
            resultFields: resultFields,
            fieldsToFill: toFill,
            retainedConflicts: conflicts,
            matchingFields: matching
        )
    }

    public static func sourceType(for zoteroItemType: String?) -> AnalysisSourceType {
        switch zoteroItemType?.lowercased() {
        case "journalarticle": .journalArticle
        case "book": .book
        case "booksection": .chapter
        case "encyclopediaarticle", "dictionaryentry": .encyclopediaEntry
        case "thesis": .thesis
        case "manuscript": .manuscript
        case "report": .report
        case "preprint": .preprint
        case "conferencepaper": .conferencePaper
        case "presentation": .presentation
        case "webpage", "blogpost", "forumpost": .webpage
        case "review", "reviewbook": .review
        case "dataset": .dataset
        case "computerprogram": .software
        case "letter", "email", "instantmessage": .correspondence
        case "audiorecording", "film", "interview", "podcast",
             "radiobroadcast", "tvbroadcast", "videorecording": .audiovisual
        default: .other
        }
    }

    private static func mappedFields(
        item: ZoteroItemMetadata,
        sourceType: AnalysisSourceType
    ) -> [ZoteroMetadataFillField] {
        var values: [String: YAMLValue] = [
            "type": .string(sourceType.rawValue),
        ]
        insert(item.title, as: "title", into: &values)
        insert(item.date, as: "publication_date", into: &values)
        insert(item.language, as: "language", into: &values)
        insert(item.containerTitle, as: "container_title", into: &values)
        insert(item.series, as: "series_title", into: &values)
        insert(item.volume, as: "volume", into: &values)
        insert(item.issue, as: "issue", into: &values)
        insert(item.pages, as: "pages", into: &values)
        insert(item.edition, as: "edition", into: &values)
        insert(item.publisher, as: "publisher", into: &values)
        insert(item.place, as: "publisher_place", into: &values)
        insert(item.doi, as: "doi", into: &values)
        insert(item.isbn, as: "isbn", into: &values)
        insert(item.issn, as: "issn", into: &values)
        insert(item.url, as: "url", into: &values)

        let creators = Dictionary(grouping: item.creators) { creatorKey(for: $0.role) }
        for (key, entries) in creators where key != nil {
            let mapped = entries.compactMap(creatorValue)
            if !mapped.isEmpty, let key {
                values[key] = .array(mapped)
            }
        }
        return values.map { ZoteroMetadataFillField(key: $0.key, value: $0.value) }
    }

    private static func insert(
        _ rawValue: String?,
        as key: String,
        into values: inout [String: YAMLValue]
    ) {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }
        values[key] = .string(value)
    }

    private static func creatorKey(for role: String) -> String? {
        switch role.lowercased() {
        case "author": "authors"
        case "bookauthor": "container_authors"
        case "editor": "editors"
        case "translator": "translators"
        case "serieseditor": "collection_editors"
        case "reviewedauthor": "reviewed_authors"
        default: nil
        }
    }

    private static func creatorValue(_ creator: ZoteroCreatorMetadata) -> YAMLValue? {
        if let literal = nonempty(creator.literalName) {
            return .object(["literal": .string(literal)])
        }
        if let family = nonempty(creator.familyName) {
            var members: [String: YAMLValue] = ["family": .string(family)]
            if let given = nonempty(creator.givenName) {
                members["given"] = .string(given)
            }
            return .object(members)
        }
        guard let literal = nonempty(creator.name) else { return nil }
        return .object(["literal": .string(literal)])
    }

    private static func nonempty(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private static func ordered(
        _ fields: [String: YAMLValue],
        sourceType: AnalysisSourceType
    ) -> [ZoteroMetadataFillField] {
        let profile = AnalysisSourceTypeProfileCatalog.profile(for: sourceType)
        let order = Dictionary(
            uniqueKeysWithValues: profile.serializationFieldOrder.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        return fields.map { ZoteroMetadataFillField(key: $0.key, value: $0.value) }
            .sorted {
                let left = order[$0.key] ?? Int.max
                let right = order[$1.key] ?? Int.max
                return left == right ? $0.key < $1.key : left < right
            }
    }
}
