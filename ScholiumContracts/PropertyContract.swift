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
}

/// Requiredness applies only while deliberately creating a new durable note.
/// Existing notes remain readable when a required-for-creation property is
/// absent; Scholium does not migrate or repair them merely by opening them.
public enum PropertyCreationRequirement: String, Codable, Hashable, Sendable {
    case optional
    case required
}

/// Declares who may author a recognized property through structured product
/// surfaces. Protected machine properties remain part of the exact Markdown
/// vocabulary, but are excluded from researcher-facing editors and profiles.
public enum PropertyOwnership: String, Codable, Hashable, Sendable {
    case researcher
    case protectedMachine = "protected_machine"
}

/// A semantic constraint that relates one property to another value or
/// property. Constraints are descriptive Core data as well as validation
/// inputs, so every delivery surface can inspect the same rule catalog.
public enum PropertyConstraint: Codable, Hashable, Sendable {
    /// The property and its peer must either both be present or both be absent.
    case pairedWith(canonicalKey: String)
    /// A present value must be a whole number inside the inclusive bounds.
    case integerRange(minimum: Int, maximum: Int)
    /// During creation, this property is required when another canonical
    /// property contains the specified controlled value.
    case requiredWhen(canonicalKey: String, equals: String)
}

/// One canonical property definition shared by headless Core consumers.
/// Labels, grouping, display order, and control selection remain app concerns.
public struct PropertyContract: Codable, Hashable, Sendable {
    public let canonicalKey: String
    public let valueKind: PropertyValueKind
    public let creationRequirement: PropertyCreationRequirement
    public let ownership: PropertyOwnership
    public let allowedValues: [String]?
    public let constraints: [PropertyConstraint]

    public init(
        canonicalKey: String,
        valueKind: PropertyValueKind,
        creationRequirement: PropertyCreationRequirement = .optional,
        ownership: PropertyOwnership = .researcher,
        allowedValues: [String]? = nil,
        constraints: [PropertyConstraint] = []
    ) {
        self.canonicalKey = canonicalKey
        self.valueKind = valueKind
        self.creationRequirement = creationRequirement
        self.ownership = ownership
        self.allowedValues = allowedValues.map(Self.unique)
        self.constraints = Self.unique(constraints)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func unique(_ values: [PropertyConstraint]) -> [PropertyConstraint] {
        var seen: Set<PropertyConstraint> = []
        return values.filter { seen.insert($0).inserted }
    }
}

public enum PropertyValidationContext: String, Codable, Hashable, Sendable {
    /// Validate only metadata that is actually present. Missing creation
    /// requirements do not make an existing note malformed.
    case existingDocument
    /// Also report properties required by the selected profile at creation.
    case creation
}

public struct PropertyValidationIssue: Codable, Hashable, Sendable {
    public enum Code: String, Codable, Hashable, Sendable {
        case malformedFrontmatter
        case missingRequiredProperty
        case invalidValueKind
        case valueNotAllowed
        case invalidResearchUnit
        case debateImportanceOutOfRange
        case pairedPropertyMissing
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

/// Canonical metadata contracts selected by the already-resolved schema
/// profile. Registered vault role and profile resolution remain owned by
/// `WorkflowProfileResolver`; this catalog never guesses from a path.
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

    /// Protected machine keys remain recognizable source vocabulary but can
    /// never become a researcher-editable Action Profile boundary.
    static func isProtectedMachineKey(_ key: String) -> Bool {
        protectedMachineKeys.contains(key)
    }

    /// Validates a parsed document without changing its exact source or
    /// reconstructing YAML. A malformed mapping produces an envelope issue
    /// and remains readable through the original `NoteDocument`.
    public static func validate(
        _ document: NoteDocument,
        profile: SchemaProfileID,
        context: PropertyValidationContext = .existingDocument
    ) -> [PropertyValidationIssue] {
        guard document.validationWarnings.isEmpty else {
            return [PropertyValidationIssue(
                propertyKey: nil,
                code: .malformedFrontmatter,
                message: document.validationWarnings.joined(separator: "\n")
            )]
        }
        return validate(
            frontmatter: document.parsedFrontmatter,
            profile: profile,
            context: context
        )
    }

    /// Validates only recognized semantic properties. Unknown YAML remains
    /// outside this projection and is neither diagnosed nor changed.
    public static func validate(
        frontmatter: [String: YAMLValue],
        profile: SchemaProfileID,
        context: PropertyValidationContext = .existingDocument
    ) -> [PropertyValidationIssue] {
        let contracts = contracts(for: profile)
        var issues: [PropertyValidationIssue] = []

        for contract in contracts {
            let value = resolvedValue(for: contract, in: frontmatter)
            if context == .creation,
               contract.creationRequirement == .required,
               value.map(isEmpty) != false {
                issues.append(PropertyValidationIssue(
                    propertyKey: contract.canonicalKey,
                    code: .missingRequiredProperty,
                    message: "\(contract.canonicalKey) is required when creating this note."
                ))
                continue
            }
            guard let value else { continue }

            if contract.canonicalKey == "research_unit" {
                let declaration = ResearchUnitDeclaration(
                    frontmatter: ["research_unit": value],
                    profile: profile
                )
                if let message = declaration.validationMessage {
                    issues.append(PropertyValidationIssue(
                        propertyKey: contract.canonicalKey,
                        code: .invalidResearchUnit,
                        message: message
                    ))
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

        issues.append(contentsOf: validateConstraints(
            frontmatter: frontmatter,
            contracts: contracts,
            context: context
        ))
        return issues
    }

    private struct CachedProfile: Sendable {
        let contracts: [PropertyContract]
        let canonicalByKey: [String: PropertyContract]

        init(contracts: [PropertyContract]) {
            self.contracts = contracts
            var canonical: [String: PropertyContract] = [:]
            for contract in contracts {
                if canonical[contract.canonicalKey] == nil {
                    canonical[contract.canonicalKey] = contract
                }
            }
            canonicalByKey = canonical
        }
    }

    private static let analysisProfile = CachedProfile(contracts: analysisContracts)
    private static let topicProfile = CachedProfile(contracts: topicContracts)
    private static let workProfile = CachedProfile(contracts: workContracts)
    private static let genericProfile = CachedProfile(contracts: [])
    private static let protectedMachineKeys = Set(
        (analysisContracts + topicContracts + workContracts)
            .filter { $0.ownership == .protectedMachine }
            .map(\.canonicalKey)
    )

    private static func cachedProfile(for profile: SchemaProfileID) -> CachedProfile {
        switch profile {
        case .analysis: analysisProfile
        case .topicMarkdown: topicProfile
        case .draftProject: workProfile
        case .genericMarkdown: genericProfile
        }
    }

    private static let analysisContracts: [PropertyContract] = {
        [
            property("title", .text),
            property("authors", .textList),
            property("year", .number),
            property("type", .choice, allowed: [
                "journal_article", "book", "book_chapter", "handbook_chapter",
                "encyclopedia_entry", "thesis", "manuscript", "other",
            ]),
            property("tags", .tags),
            property("research_unit", .mapping),
            property("zotero_item_key", .text, ownership: .protectedMachine),
            property("access", .choice, allowed: [
                "full_text", "partial_text", "metadata_only", "unavailable",
            ]),
            property("text_reliability", .choice, allowed: [
                "verified", "usable_with_caution", "unreliable",
            ]),
            property("locators", .choice, allowed: [
                "reliable", "partial", "unverified", "unavailable",
            ]),
            property(
                "debate_importance",
                .number,
                constraints: [
                    .integerRange(minimum: 0, maximum: 10),
                    .pairedWith(canonicalKey: "debate_importance_scope"),
                ]
            ),
            property(
                "debate_importance_scope",
                .text,
                constraints: [.pairedWith(canonicalKey: "debate_importance")]
            ),
        ]
    }()

    private static let topicContracts: [PropertyContract] = [
        property("aliases", .textList),
        property("tags", .tags),
        property("research_unit", .mapping),
    ]

    private static let workContracts: [PropertyContract] = [
        property("authors", .textList),
        property("kind", .choice, allowed: [
            "paper", "chapter", "book", "talk", "review", "teaching", "other",
        ]),
        property("tags", .tags),
        property("research_unit", .mapping),
        property("venue", .text),
    ]

    private static func property(
        _ key: String,
        _ kind: PropertyValueKind,
        requirement: PropertyCreationRequirement = .optional,
        ownership: PropertyOwnership = .researcher,
        allowed: [String]? = nil,
        constraints: [PropertyConstraint] = []
    ) -> PropertyContract {
        PropertyContract(
            canonicalKey: key,
            valueKind: kind,
            creationRequirement: requirement,
            ownership: ownership,
            allowedValues: allowed,
            constraints: constraints
        )
    }

    private static func resolvedValue(
        for contract: PropertyContract,
        in frontmatter: [String: YAMLValue]
    ) -> YAMLValue? {
        frontmatter[contract.canonicalKey]
    }

    private static func isCompatible(
        _ value: YAMLValue,
        with kind: PropertyValueKind
    ) -> Bool {
        switch kind {
        case .text, .multilineText, .date, .choice:
            if case .string = value { return true }
        case .number:
            if case .integer = value { return true }
            if case .double = value { return true }
        case .boolean:
            if case .boolean = value { return true }
        case .tags, .textList:
            if case .array(let values) = value {
                return values.allSatisfy { $0.scalarString != nil }
            }
        case .mapping:
            if case .object = value { return true }
        }
        return false
    }

    private static func isEmpty(_ value: YAMLValue) -> Bool {
        switch value {
        case .string(let value):
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let values):
            values.isEmpty
        case .object(let values):
            values.isEmpty
        case .null:
            true
        case .integer, .double, .boolean:
            false
        }
    }

    private static func description(of kind: PropertyValueKind) -> String {
        switch kind {
        case .text: "text"
        case .multilineText: "multiline text"
        case .number: "a number"
        case .date: "a date"
        case .boolean: "true or false"
        case .tags: "a list of tags"
        case .textList: "a list of text values"
        case .choice: "one controlled text value"
        case .mapping: "a mapping"
        }
    }

    private static func validateConstraints(
        frontmatter: [String: YAMLValue],
        contracts: [PropertyContract],
        context: PropertyValidationContext
    ) -> [PropertyValidationIssue] {
        var issues: [PropertyValidationIssue] = []
        var seenIssueKeys: Set<String> = []
        for contract in contracts {
            let value = resolvedValue(for: contract, in: frontmatter)
            let isPresent = value.map { !isEmpty($0) } == true
            for constraint in contract.constraints {
                let issue: PropertyValidationIssue?
                switch constraint {
                case .pairedWith(let peerKey):
                    guard let peer = contracts.first(where: { $0.canonicalKey == peerKey }) else {
                        continue
                    }
                    let peerIsPresent = resolvedValue(for: peer, in: frontmatter)
                        .map { !isEmpty($0) } == true
                    guard isPresent != peerIsPresent else { continue }
                    let missingKey = isPresent ? peer.canonicalKey : contract.canonicalKey
                    issue = PropertyValidationIssue(
                        propertyKey: missingKey,
                        code: .pairedPropertyMissing,
                        message: "\(contract.canonicalKey) and \(peer.canonicalKey) must be provided together."
                    )
                case .integerRange(let minimum, let maximum):
                    guard let value, isPresent else { continue }
                    guard case .integer(let integer) = value,
                          (minimum...maximum).contains(integer) else {
                        issue = PropertyValidationIssue(
                            propertyKey: contract.canonicalKey,
                            code: .debateImportanceOutOfRange,
                            message: "\(contract.canonicalKey) must be a whole number from \(minimum) to \(maximum)."
                        )
                        break
                    }
                    issue = nil
                case .requiredWhen(let controllingKey, let expectedValue):
                    guard context == .creation,
                          case .string(let actualValue) = frontmatter[controllingKey],
                          actualValue == expectedValue,
                          !isPresent else {
                        continue
                    }
                    issue = PropertyValidationIssue(
                        propertyKey: contract.canonicalKey,
                        code: .missingRequiredProperty,
                        message: "\(contract.canonicalKey) is required when creating a \(expectedValue) record."
                    )
                }
                let issueKey = issue.map {
                    "\($0.propertyKey ?? ""):\($0.code.rawValue)"
                }
                if let issue, let issueKey, seenIssueKeys.insert(issueKey).inserted {
                    issues.append(issue)
                }
            }
        }
        return issues
    }
}
