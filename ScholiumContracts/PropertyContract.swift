import Foundation

/// The semantic shape Scholium expects when it presents or validates one
/// recognized top-level property. This is a read-only interpretation of
/// `YAMLValue`; it is never a serialization instruction.
public enum PropertyValueKind: String, Codable, Hashable, Sendable {
    case text
    case multilineText
    case number
    case date
    case boolean
    case tags
    case textList
    case choice
    case mapping
    case creatorList
}

/// One canonical property definition shared by headless Core consumers.
/// Requiredness, visibility, structured-edit access, presentation, and exact
/// New Note YAML are deliberately owned by separate contracts.
public struct PropertyContract: Codable, Hashable, Sendable {
    public let canonicalKey: String
    public let valueKind: PropertyValueKind
    public let allowedValues: [String]?

    public init(
        canonicalKey: String,
        valueKind: PropertyValueKind,
        allowedValues: [String]? = nil
    ) {
        self.canonicalKey = canonicalKey
        self.valueKind = valueKind
        self.allowedValues = allowedValues.map(Self.unique)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public struct PropertyValidationIssue: Codable, Hashable, Sendable {
    public enum Code: String, Codable, Hashable, Sendable {
        case malformedFrontmatter
        case invalidValueKind
        case valueNotAllowed
        case invalidCreator
    }

    /// The canonical key, or `nil` when the complete frontmatter envelope is
    /// malformed and no property can be interpreted safely.
    public let propertyKey: String?
    public let code: Code
    public let message: String

    public init(propertyKey: String?, code: Code, message: String) {
        self.propertyKey = propertyKey
        self.code = code
        self.message = message
    }
}

public struct CreatorNameProjection: Codable, Hashable, Sendable {
    public let displayName: String
    public let searchableComponents: [String]

    public init(displayName: String, searchableComponents: [String]) {
        self.displayName = displayName
        self.searchableComponents = searchableComponents
    }
}

/// The deliberately small authored-YAML contract selected by an already
/// resolved schema profile. Only `summary` and `keywords` receive Scholium
/// semantics in research-note frontmatter. Every other YAML key remains exact
/// researcher-authored custom source and is never promoted by this catalog.
public enum PropertyContractCatalog {
    public static func contracts(for profile: SchemaProfileID) -> [PropertyContract] {
        cachedProfile(for: profile).contracts
    }

    public static func contract(
        for key: String,
        profile: SchemaProfileID
    ) -> PropertyContract? {
        cachedProfile(for: profile).canonicalByKey[key]
    }

    public static func canonicalKey(
        for key: String,
        profile: SchemaProfileID
    ) -> String? {
        contract(for: key, profile: profile)?.canonicalKey
    }

    /// Produces deterministic display/search values only for a completely
    /// valid canonical CreatorList. It never accepts legacy string arrays or
    /// coerces YAML scalars into names.
    public static func creatorNames(from value: YAMLValue) -> [CreatorNameProjection]? {
        guard validateCreatorList(value, key: "creators") == nil,
              case .array(let entries) = value else { return nil }
        return entries.compactMap { entry in
            guard case .object(let members) = entry else { return nil }
            if case .string(let literal)? = members["literal"] {
                return CreatorNameProjection(
                    displayName: literal,
                    searchableComponents: [literal]
                )
            }
            let orderedKeys = [
                "given", "dropping_particle", "non_dropping_particle", "family", "suffix",
            ]
            let components = orderedKeys.compactMap { key -> String? in
                guard case .string(let value)? = members[key] else { return nil }
                return value
            }
            return CreatorNameProjection(
                displayName: components.joined(separator: " "),
                searchableComponents: components
            )
        }
    }

    /// Returns whether a present semantic value can be changed by one of the
    /// targeted structured controls without guessing or replacing an
    /// unsupported source shape. Empty values remain editable so the
    /// researcher can repair or remove them; validation still rejects saving
    /// an invalid nonempty-property candidate.
    public static func supportsTargetedStructuredEditing(
        _ value: YAMLValue,
        as kind: PropertyValueKind
    ) -> Bool {
        switch kind {
        case .text, .date, .choice:
            guard case .string(let text) = value else { return false }
            return isStructurallySafeText(text, allowsNewlines: false)
        case .multilineText:
            guard case .string(let text) = value else { return false }
            return isStructurallySafeText(text, allowsNewlines: true)
        case .number:
            if case .integer = value { return true }
            if case .double = value { return true }
            return false
        case .boolean:
            if case .boolean = value { return true }
            return false
        case .tags, .textList:
            guard case .array(let values) = value else { return false }
            return values.allSatisfy {
                guard case .string(let text) = $0 else { return false }
                return isStructurallySafeText(text, allowsNewlines: false)
            }
        case .mapping:
            if case .object = value { return true }
            return false
        case .creatorList:
            guard case .array(let entries) = value else { return false }
            let personKeys: Set<String> = [
                "family", "given", "suffix", "non_dropping_particle", "dropping_particle",
            ]
            return entries.allSatisfy { entry in
                guard case .object(let members) = entry else { return false }
                let keys = Set(members.keys)
                if keys.contains("literal") {
                    guard keys == ["literal"], case .string(let text)? = members["literal"] else {
                        return false
                    }
                    return isStructurallySafeText(text, allowsNewlines: false)
                }
                return keys.isSubset(of: personKeys)
                    && members.values.allSatisfy {
                        guard case .string(let text) = $0 else { return false }
                        return isStructurallySafeText(text, allowsNewlines: false)
                    }
            }
        }
    }

    /// Validates a parsed document without changing its exact source or
    /// reconstructing YAML. Unknown YAML remains authored custom source.
    public static func validate(
        _ document: NoteDocument,
        profile: SchemaProfileID
    ) -> [PropertyValidationIssue] {
        guard document.validationWarnings.isEmpty else {
            return [PropertyValidationIssue(
                propertyKey: nil,
                code: .malformedFrontmatter,
                message: document.validationWarnings.joined(separator: "\n")
            )]
        }
        return validate(frontmatter: document.parsedFrontmatter, profile: profile)
    }

    /// Validates only recognized semantic properties. Bibliographic values are
    /// shape-checked but never normalized or verified against external facts.
    public static func validate(
        frontmatter: [String: YAMLValue],
        profile: SchemaProfileID
    ) -> [PropertyValidationIssue] {
        validate(values: frontmatter, against: contracts(for: profile))
    }

    fileprivate static func validate(
        values: [String: YAMLValue],
        against contracts: [PropertyContract]
    ) -> [PropertyValidationIssue] {
        var issues: [PropertyValidationIssue] = []
        for contract in contracts {
            guard let value = values[contract.canonicalKey] else { continue }
            if contract.valueKind == .creatorList {
                if let creatorIssue = validateCreatorList(value, key: contract.canonicalKey) {
                    issues.append(creatorIssue)
                }
                continue
            }
            guard isCompatible(value, with: contract.valueKind) else {
                issues.append(PropertyValidationIssue(
                    propertyKey: contract.canonicalKey,
                    code: .invalidValueKind,
                    message: "\(contract.canonicalKey) must be \(description(of: contract.valueKind))."
                ))
                continue
            }
            guard let allowedValues = contract.allowedValues, !isEmpty(value) else { continue }
            let allowed = Set(allowedValues)
            let suppliedValues: [String]
            if contract.valueKind == .textList || contract.valueKind == .tags {
                guard case .array(let values) = value else { continue }
                suppliedValues = values.compactMap(\.scalarString)
            } else {
                suppliedValues = value.scalarString.map { [$0] } ?? []
            }
            if let invalid = suppliedValues.first(where: { !allowed.contains($0) }) {
                issues.append(PropertyValidationIssue(
                    propertyKey: contract.canonicalKey,
                    code: .valueNotAllowed,
                    message: "\(invalid) is not an allowed value for \(contract.canonicalKey)."
                ))
            }
        }
        return issues
    }

    private struct CachedProfile: Sendable {
        let contracts: [PropertyContract]
        let canonicalByKey: [String: PropertyContract]

        init(contracts: [PropertyContract]) {
            self.contracts = contracts
            canonicalByKey = Dictionary(
                contracts.map { ($0.canonicalKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    private static let analysisProfile = CachedProfile(contracts: analysisContracts)
    private static let topicProfile = CachedProfile(contracts: topicContracts)
    private static let workProfile = CachedProfile(contracts: workContracts)
    private static let genericProfile = CachedProfile(contracts: [])

    private static func cachedProfile(for profile: SchemaProfileID) -> CachedProfile {
        switch profile {
        case .analysis: analysisProfile
        case .topicMarkdown: topicProfile
        case .draftProject: workProfile
        case .genericMarkdown: genericProfile
        }
    }

    public static let authoredCanonicalKeys: [String] = analysisContracts.map(\.canonicalKey)

    private static let analysisContracts: [PropertyContract] = [
        property("summary", .multilineText),
        property("keywords", .tags),
    ]

    private static let topicContracts: [PropertyContract] = [
        property("summary", .multilineText),
        property("keywords", .tags),
    ]

    private static let workContracts: [PropertyContract] = [
        property("summary", .multilineText),
        property("keywords", .tags),
    ]

    private static func property(
        _ key: String,
        _ kind: PropertyValueKind,
        allowed: [String]? = nil
    ) -> PropertyContract {
        PropertyContract(canonicalKey: key, valueKind: kind, allowedValues: allowed)
    }

    private static func isCompatible(_ value: YAMLValue, with kind: PropertyValueKind) -> Bool {
        switch kind {
        case .text, .multilineText, .date, .choice:
            if case .string(let text) = value {
                return isSourceSafeText(text, allowsNewlines: kind == .multilineText)
            }
        case .boolean:
            if case .boolean = value { return true }
        case .number:
            if case .integer = value { return true }
            if case .double = value { return true }
        case .tags, .textList:
            if case .array(let values) = value {
                return !values.isEmpty && values.allSatisfy {
                    guard case .string(let text) = $0 else { return false }
                    return isSourceSafeText(text, allowsNewlines: false)
                }
            }
        case .mapping:
            if case .object = value { return true }
        case .creatorList:
            return validateCreatorList(value, key: "creator") == nil
        }
        return false
    }

    private static func validateCreatorList(
        _ value: YAMLValue,
        key: String
    ) -> PropertyValidationIssue? {
        guard case .array(let entries) = value, !entries.isEmpty else {
            return creatorIssue(key, "\(key) must be a nonempty list of creator mappings.")
        }
        let personKeys: Set<String> = [
            "family", "given", "suffix", "non_dropping_particle", "dropping_particle",
        ]
        for (index, entry) in entries.enumerated() {
            guard case .object(let members) = entry else {
                return creatorIssue(key, "Creator \(index + 1) in \(key) must be a mapping.")
            }
            let keys = Set(members.keys)
            if let literal = members["literal"] {
                guard keys == ["literal"],
                      case .string(let text) = literal,
                      isSourceSafeText(text, allowsNewlines: false) else {
                    return creatorIssue(
                        key,
                        "Literal creator \(index + 1) in \(key) must contain only nonempty literal text."
                    )
                }
                continue
            }
            guard keys.isSubset(of: personKeys), keys.contains("family"),
                  members.values.allSatisfy({ value in
                      guard case .string(let text) = value else { return false }
                      return isSourceSafeText(text, allowsNewlines: false)
                  }) else {
                return creatorIssue(
                    key,
                    "Person creator \(index + 1) in \(key) requires family and supports only the canonical name members."
                )
            }
        }
        return nil
    }

    private static func creatorIssue(_ key: String, _ message: String) -> PropertyValidationIssue {
        PropertyValidationIssue(propertyKey: key, code: .invalidCreator, message: message)
    }

    private static func isSourceSafeText(_ text: String, allowsNewlines: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return isStructurallySafeText(text, allowsNewlines: allowsNewlines)
    }

    private static func isStructurallySafeText(_ text: String, allowsNewlines: Bool) -> Bool {
        return text.unicodeScalars.allSatisfy { scalar in
            if scalar == "\n" || scalar == "\r" { return allowsNewlines }
            return !CharacterSet.controlCharacters.contains(scalar)
        }
    }

    private static func isEmpty(_ value: YAMLValue) -> Bool {
        switch value {
        case .string(let value): value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let values): values.isEmpty
        case .object(let values): values.isEmpty
        case .null: true
        case .integer, .double, .boolean: false
        }
    }

    private static func description(of kind: PropertyValueKind) -> String {
        switch kind {
        case .text: "nonempty single-line text"
        case .multilineText: "nonempty text"
        case .date: "nonempty source-safe date text"
        case .boolean: "true or false"
        case .number: "a number"
        case .tags: "a nonempty list of tags"
        case .textList: "a nonempty list of text values"
        case .choice: "one controlled text value"
        case .mapping: "a mapping"
        case .creatorList: "a nonempty list of creator mappings"
        }
    }
}

public enum MetadataFieldLifecycle: String, Codable, Hashable, Sendable {
    case active
    case archived
}

/// One researcher-defined managed field applied globally to one Triptych role.
/// The key and value shape are stable storage identity. Label, description,
/// controlled choices, and lifecycle are schema guidance only; requiredness,
/// defaults, About visibility, Agent preference, integrations, and authored
/// source remain deliberately outside this contract.
public struct MetadataFieldDefinition: Codable, Hashable, Sendable {
    public static let supportedValueKinds: Set<PropertyValueKind> = [
        .text, .multilineText, .number, .date, .boolean, .textList, .choice,
    ]

    public let key: String
    public let valueKind: PropertyValueKind
    public var label: String
    public var description: String?
    public var allowedValues: [String]?
    public var lifecycle: MetadataFieldLifecycle

    public init(
        key: String,
        valueKind: PropertyValueKind,
        label: String? = nil,
        description: String? = nil,
        allowedValues: [String]? = nil,
        lifecycle: MetadataFieldLifecycle = .active
    ) {
        self.key = key
        self.valueKind = valueKind
        self.label = label ?? Self.defaultLabel(for: key)
        self.description = description
        self.allowedValues = allowedValues
        self.lifecycle = lifecycle
    }

    public var contract: PropertyContract {
        PropertyContract(
            canonicalKey: key,
            valueKind: valueKind,
            allowedValues: allowedValues
        )
    }

    public var isActive: Bool { lifecycle == .active }

    public static func defaultLabel(for key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

/// Product-owned built-in Scholium Metadata shapes. Workspace consumers use a
/// resolved `NoteMetadataCatalog`, not this seed catalog directly.
public enum BuiltInNoteMetadataCatalog {
    public static func contracts(for profile: SchemaProfileID) -> [PropertyContract] {
        cachedProfile(for: profile).contracts
    }

    public static func contract(
        for key: String,
        profile: SchemaProfileID
    ) -> PropertyContract? {
        cachedProfile(for: profile).canonicalByKey[key]
    }

    public static func validate(
        fields: [String: YAMLValue],
        profile: SchemaProfileID
    ) -> [PropertyValidationIssue] {
        let recognized = Set(contracts(for: profile).map(\.canonicalKey))
        var issues = fields.keys.filter { !recognized.contains($0) }.sorted().map {
            PropertyValidationIssue(
                propertyKey: $0,
                code: .invalidValueKind,
                message: "\($0) is not a managed field for this Note role."
            )
        }
        issues.append(contentsOf: PropertyContractCatalog.validate(
            values: fields,
            against: contracts(for: profile)
        ))
        return issues
    }

    public static let analysisCanonicalKeys: [String] = analysisContracts.map(\.canonicalKey)

    private struct CachedProfile: Sendable {
        let contracts: [PropertyContract]
        let canonicalByKey: [String: PropertyContract]

        init(contracts: [PropertyContract]) {
            self.contracts = contracts
            canonicalByKey = Dictionary(
                contracts.map { ($0.canonicalKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }

    private static let analysisProfile = CachedProfile(contracts: analysisContracts)
    private static let topicProfile = CachedProfile(contracts: topicContracts)
    private static let workProfile = CachedProfile(contracts: workContracts)
    private static let genericProfile = CachedProfile(contracts: [])

    private static func cachedProfile(for profile: SchemaProfileID) -> CachedProfile {
        switch profile {
        case .analysis: analysisProfile
        case .topicMarkdown: topicProfile
        case .draftProject: workProfile
        case .genericMarkdown: genericProfile
        }
    }

    private static let analysisContracts: [PropertyContract] = [
        property("type", .choice, allowed: AnalysisSourceType.allCases.map(\.rawValue)),
        property("title", .text),
        property("short_title", .text),
        property("original_title", .text),
        property("reviewed_title", .text),
        property("genre", .text),
        property("medium", .text),
        property("version", .text),
        property("language", .text),
        property("authors", .creatorList),
        property("editors", .creatorList),
        property("translators", .creatorList),
        property("collection_editors", .creatorList),
        property("container_authors", .creatorList),
        property("original_authors", .creatorList),
        property("reviewed_authors", .creatorList),
        property("publication_date", .date),
        property("publication_status", .text),
        property("original_publication_date", .date),
        property("accessed_date", .date),
        property("event_date", .date),
        property("container_title", .text),
        property("container_title_short", .text),
        property("series_title", .text),
        property("series_number", .text),
        property("volume", .text),
        property("volume_title", .text),
        property("issue", .text),
        property("pages", .text),
        property("chapter_number", .text),
        property("edition", .text),
        property("number_of_volumes", .text),
        property("publisher", .text),
        property("publisher_place", .text),
        property("original_publisher", .text),
        property("original_publisher_place", .text),
        property("institution", .text),
        property("report_number", .text),
        property("event_title", .text),
        property("event_place", .text),
        property("doi", .text),
        property("isbn", .text),
        property("issn", .text),
        property("url", .text),
        property("pmid", .text),
        property("pmcid", .text),
        property("arxiv_id", .text),
        property("archive", .text),
        property("archive_collection", .text),
        property("archive_location", .text),
        property("archive_place", .text),
        property("call_number", .text),
    ]

    private static let topicContracts: [PropertyContract] = [
        property("aliases", .textList),
    ]

    private static let workContracts: [PropertyContract] = [
        property("work_type", .choice, allowed: [
            "paper", "chapter", "book", "talk", "review", "teaching", "other",
        ]),
        property("coauthors", .textList),
    ]

    private static func property(
        _ key: String,
        _ kind: PropertyValueKind,
        allowed: [String]? = nil
    ) -> PropertyContract {
        PropertyContract(canonicalKey: key, valueKind: kind, allowedValues: allowed)
    }
}

/// The one immutable, workspace-scoped Metadata catalog. It resolves the
/// product-owned built-ins with stable researcher definitions from the
/// current Triptych settings and is safe to pass across delivery boundaries.
public struct NoteMetadataCatalog: Codable, Hashable, Sendable {
    public let customFieldsByRole: [WorkspaceVaultSlot: [MetadataFieldDefinition]]

    public init(
        customFieldsByRole: [WorkspaceVaultSlot: [MetadataFieldDefinition]] = [:]
    ) {
        var completed: [WorkspaceVaultSlot: [MetadataFieldDefinition]] = [:]
        for role in WorkspaceVaultSlot.allCases {
            completed[role] = customFieldsByRole[role] ?? []
        }
        self.customFieldsByRole = completed
    }

    public init(settings: TriptychSettings) {
        self.init(customFieldsByRole: settings.metadataFields)
    }

    public static let builtIn = NoteMetadataCatalog()

    public func contracts(for profile: SchemaProfileID) -> [PropertyContract] {
        BuiltInNoteMetadataCatalog.contracts(for: profile)
            + customFields(for: profile).map(\.contract)
    }

    /// Contracts available for adding a new value or configuring About and
    /// Agent guidance. Archived definitions remain in `contracts(for:)` so
    /// existing values validate, render, and remain searchable.
    public func activeContracts(for profile: SchemaProfileID) -> [PropertyContract] {
        BuiltInNoteMetadataCatalog.contracts(for: profile)
            + activeCustomFields(for: profile).map(\.contract)
    }

    public func contract(
        for key: String,
        profile: SchemaProfileID
    ) -> PropertyContract? {
        contracts(for: profile).first { $0.canonicalKey == key }
    }

    public func validate(
        fields: [String: YAMLValue],
        profile: SchemaProfileID
    ) -> [PropertyValidationIssue] {
        let contracts = contracts(for: profile)
        let recognized = Set(contracts.map(\.canonicalKey))
        var issues = fields.keys.filter { !recognized.contains($0) }.sorted().map {
            PropertyValidationIssue(
                propertyKey: $0,
                code: .invalidValueKind,
                message: "\($0) is not a managed field for this Note role."
            )
        }
        issues.append(contentsOf: PropertyContractCatalog.validate(
            values: fields,
            against: contracts
        ))
        return issues
    }

    public var analysisCanonicalKeys: [String] {
        contracts(for: .analysis).map(\.canonicalKey)
    }

    /// Built-in Analysis fields retain source-type profile order. Custom
    /// fields are globally applicable and follow researcher-controlled
    /// definition order.
    public func analysisContracts(
        for sourceType: AnalysisSourceType
    ) -> [PropertyContract] {
        let builtInByKey = Dictionary(
            uniqueKeysWithValues: BuiltInNoteMetadataCatalog
                .contracts(for: .analysis).map { ($0.canonicalKey, $0) }
        )
        let orderedBuiltIns = AnalysisSourceTypeProfileCatalog.profile(for: sourceType)
            .serializationFieldOrder.compactMap { builtInByKey[$0] }
        return orderedBuiltIns + activeCustomFields(for: .analysis).map(\.contract)
    }

    public func isAnalysisFieldApplicable(
        _ key: String,
        sourceType: AnalysisSourceType
    ) -> Bool {
        analysisContracts(for: sourceType).contains { $0.canonicalKey == key }
    }

    public func customFields(for role: WorkspaceVaultSlot) -> [MetadataFieldDefinition] {
        customFieldsByRole[role] ?? []
    }

    public func activeCustomFields(
        for role: WorkspaceVaultSlot
    ) -> [MetadataFieldDefinition] {
        customFields(for: role).filter(\.isActive)
    }

    public func customFields(for profile: SchemaProfileID) -> [MetadataFieldDefinition] {
        guard let role = Self.role(for: profile) else { return [] }
        return customFields(for: role)
    }

    public func activeCustomFields(
        for profile: SchemaProfileID
    ) -> [MetadataFieldDefinition] {
        guard let role = Self.role(for: profile) else { return [] }
        return activeCustomFields(for: role)
    }

    public func customField(
        for key: String,
        profile: SchemaProfileID
    ) -> MetadataFieldDefinition? {
        customFields(for: profile).first { $0.key == key }
    }

    public static func role(for profile: SchemaProfileID) -> WorkspaceVaultSlot? {
        switch profile {
        case .analysis: .paperAnalysis
        case .topicMarkdown: .topicKnowledge
        case .draftProject: .output
        case .genericMarkdown: nil
        }
    }

    public static func profile(for role: WorkspaceVaultSlot) -> SchemaProfileID {
        switch role {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        WorkspaceVaultSlot.allCases.allSatisfy {
            lhs.customFields(for: $0) == rhs.customFields(for: $0)
        }
    }

    public func hash(into hasher: inout Hasher) {
        for role in WorkspaceVaultSlot.allCases {
            hasher.combine(role)
            hasher.combine(customFields(for: role))
        }
    }
}
