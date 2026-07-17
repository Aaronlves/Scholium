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
    public let allowedValues: [String]?
    public let legacyAliases: [String]
    public let constraints: [PropertyConstraint]

    public init(
        canonicalKey: String,
        valueKind: PropertyValueKind,
        creationRequirement: PropertyCreationRequirement = .optional,
        allowedValues: [String]? = nil,
        legacyAliases: [String] = [],
        constraints: [PropertyConstraint] = []
    ) {
        self.canonicalKey = canonicalKey
        self.valueKind = valueKind
        self.creationRequirement = creationRequirement
        self.allowedValues = allowedValues.map(Self.unique)
        self.legacyAliases = Self.unique(legacyAliases)
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
        let profile = cachedProfile(for: profile)
        return profile.canonicalByKey[key] ?? profile.aliasByKey[key]
    }

    public static func canonicalKey(
        for key: String,
        profile: SchemaProfileID
    ) -> String? {
        contract(for: key, profile: profile)?.canonicalKey
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
                let declaration = ResearchUnitDeclaration(frontmatter: [
                    "research_unit": value
                ])
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
        let aliasByKey: [String: PropertyContract]

        init(contracts: [PropertyContract]) {
            self.contracts = contracts
            var canonical: [String: PropertyContract] = [:]
            var aliases: [String: PropertyContract] = [:]
            for contract in contracts {
                // Preserve the former first-match behavior for both canonical
                // keys and aliases while still making lookup constant-time.
                if canonical[contract.canonicalKey] == nil {
                    canonical[contract.canonicalKey] = contract
                }
                for alias in contract.legacyAliases where aliases[alias] == nil {
                    aliases[alias] = contract
                }
            }
            canonicalByKey = canonical
            aliasByKey = aliases
        }
    }

    private static let analysisProfile = CachedProfile(contracts:
        analysisContracts(researchUnitRequirement: .optional)
    )
    // Historical analyses remain readable without a Research Unit.
    private static let paperAnalysisProfile = CachedProfile(contracts:
        analysisContracts(researchUnitRequirement: .optional)
    )
    private static let topicProfile = CachedProfile(contracts: topicContracts)
    private static let workProfile = CachedProfile(contracts: workContracts)
    private static let dissertationV3Profile = CachedProfile(contracts: dissertationV3Contracts)
    private static let dissertationV4Profile = CachedProfile(contracts: dissertationV4Contracts)
    private static let genericProfile = CachedProfile(contracts: [])

    private static func cachedProfile(for profile: SchemaProfileID) -> CachedProfile {
        switch profile {
        case .analysis: analysisProfile
        case .paperAnalysisV1: paperAnalysisProfile
        case .topicMarkdown: topicProfile
        case .draftProject: workProfile
        case .dissertationControlV3: dissertationV3Profile
        case .dissertationControlV4: dissertationV4Profile
        case .genericMarkdown: genericProfile
        }
    }

    private static func analysisContracts(
        researchUnitRequirement: PropertyCreationRequirement
    ) -> [PropertyContract] {
        [
            property("title", .text),
            property("authors", .textList),
            property("year", .number),
            property("type", .choice, allowed: [
                "journal_article", "book", "book_chapter", "handbook_chapter",
                "encyclopedia_entry", "thesis", "manuscript", "other",
            ]),
            property("tags", .tags),
            property("research_unit", .mapping, requirement: researchUnitRequirement),
            property("access", .choice, allowed: [
                "full_text", "partial_text", "metadata_only", "unavailable",
            ]),
            property("text_reliability", .choice, allowed: [
                "verified", "usable_with_caution", "unreliable",
            ]),
            property("locators", .choice, allowed: [
                "reliable", "partial", "unverified", "unavailable",
            ]),
            property("status", .choice, allowed: ["draft", "complete", "reviewed"]),
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
    }

    private static let topicContracts: [PropertyContract] = [
        property("title", .text),
        property("aliases", .textList),
        property("tags", .tags),
        property("research_unit", .mapping),
        property("status", .choice, allowed: ["seed", "developing", "maintained"]),
    ]

    private static let workContracts: [PropertyContract] = [
        property("title", .text),
        property("authors", .textList),
        property("kind", .choice, allowed: [
            "paper", "chapter", "book", "talk", "review", "teaching", "other",
        ]),
        property("tags", .tags),
        property("research_unit", .mapping),
        property("status", .choice, allowed: [
            "planning", "drafting", "revising", "review", "ready",
            "submitted", "published", "archived",
        ]),
        property("venue", .text),
        property("deadline", .date),
    ]

    private static let dissertationV3Contracts: [PropertyContract] = [
        customProperty("note_type", .text, requirement: .required),
        customProperty("project_role", .text, requirement: .required),
        customProperty("claim_type", .text, requirement: .required),
        customProperty("status", .text, requirement: .required),
        customProperty("settlement_dimensions", .textList, requirement: .required),
        customProperty("settlement_degree", .text, requirement: .required),
        customProperty("review_status", .text, requirement: .required),
        customProperty("confidence", .choice, requirement: .required, allowed: [
            "low", "medium", "high",
        ]),
        customProperty("prose_permission", .text, requirement: .required),
        customProperty("last_reviewed", .date, requirement: .required),
        customProperty("reopen_condition", .multilineText, requirement: .required),
        customProperty("privacy", .text, requirement: .required),
        customProperty("version", .text),
        customProperty("design_decisions", .textList),
    ]

    private static let dissertationV4Contracts: [PropertyContract] = {
        let base: [PropertyContract] = [
            customProperty(
                "schema_version", .choice, requirement: .required,
                allowed: [DissertationControlV4.schemaVersion]
            ),
            customProperty("note_id", .text, requirement: .required),
            customProperty("title", .text, requirement: .required),
            customProperty(
                "note_type", .choice, requirement: .required,
                allowed: DissertationControlV4.noteTypes.sorted()
            ),
            customProperty(
                "project_role", .choice, requirement: .required,
                allowed: DissertationControlV4.projectRoles.sorted()
            ),
            customProperty(
                "origin", .choice, requirement: .required,
                allowed: DissertationControlV4.origins.sorted()
            ),
            customProperty(
                "evidential_layer", .choice, requirement: .required,
                allowed: DissertationControlV4.evidentialLayers.sorted()
            ),
            customProperty(
                "status", .choice, requirement: .required,
                allowed: DissertationControlV4.statuses.sorted()
            ),
            customProperty(
                "settlement_dimensions", .textList, requirement: .required,
                allowed: DissertationControlV4.settlementDimensions.sorted()
            ),
            customProperty(
                "settlement_degree", .choice, requirement: .required,
                allowed: DissertationControlV4.settlementDegrees.sorted()
            ),
            customProperty(
                "review_status", .choice, requirement: .required,
                allowed: DissertationControlV4.reviewStatuses.sorted()
            ),
            customProperty(
                "confidence", .choice, requirement: .required,
                allowed: DissertationControlV4.confidences.sorted()
            ),
            customProperty(
                "evidence_state", .choice, requirement: .required,
                allowed: DissertationControlV4.evidenceStates.sorted()
            ),
            customProperty(
                "prose_permission", .choice, requirement: .required,
                allowed: DissertationControlV4.prosePermissions.sorted()
            ),
            customProperty("privacy", .text, requirement: .required),
            customProperty("reopen_condition", .multilineText, requirement: .required),
            customProperty("provenance", .textList, requirement: .required),
            customProperty("created_at", .date, requirement: .required),
            customProperty("updated_at", .date, requirement: .required),
            customProperty("last_reviewed", .date, requirement: .required),
            customProperty(
                "migration_state", .choice,
                allowed: DissertationControlV4.migrationStates.sorted()
            ),
            controlledV4Property("question_kind"),
            controlledV4Property("claim_kind"),
            controlledV4Property("inference_type"),
            controlledV4Property("inference_force"),
            controlledV4Property("position_kind"),
            controlledV4Property("concept_kind"),
            controlledV4Property("case_kind"),
            controlledV4Property("evidence_kind"),
            controlledV4Property("verification_state"),
            customProperty("source_locator", .text),
            customProperty(
                "predicate", .choice,
                allowed: DissertationControlV4.predicates.map(\.rawValue).sorted()
            ),
            controlledV4Property("semantic_direction"),
            controlledV4Property("assembly_kind"),
            customProperty("chapter_id", .text),
            controlledV4Property("workflow_stage"),
            customProperty("draft_target", .text),
            controlledV4Property("registry_kind"),
            customProperty(
                "indexed_note_types", .textList,
                allowed: DissertationControlV4.noteTypes.sorted()
            ),
            controlledV4Property("control_kind"),
        ]
        return base.map { contract in
            let conditional = DissertationControlV4.additionalRequiredFields
                .compactMap { noteType, keys -> PropertyConstraint? in
                    guard keys.contains(contract.canonicalKey) else { return nil }
                    return .requiredWhen(canonicalKey: "note_type", equals: noteType)
                }
                .sorted { String(describing: $0) < String(describing: $1) }
            return PropertyContract(
                canonicalKey: contract.canonicalKey,
                valueKind: contract.valueKind,
                creationRequirement: contract.creationRequirement,
                allowedValues: contract.allowedValues,
                legacyAliases: contract.legacyAliases,
                constraints: contract.constraints + conditional
            )
        }
    }()

    private static func property(
        _ key: String,
        _ kind: PropertyValueKind,
        requirement: PropertyCreationRequirement = .optional,
        allowed: [String]? = nil,
        constraints: [PropertyConstraint] = []
    ) -> PropertyContract {
        PropertyContract(
            canonicalKey: key,
            valueKind: kind,
            creationRequirement: requirement,
            allowedValues: allowed,
            legacyAliases: TriptychProperty.legacyAliases[key] ?? [],
            constraints: constraints
        )
    }

    private static func customProperty(
        _ key: String,
        _ kind: PropertyValueKind,
        requirement: PropertyCreationRequirement = .optional,
        allowed: [String]? = nil
    ) -> PropertyContract {
        PropertyContract(
            canonicalKey: key,
            valueKind: kind,
            creationRequirement: requirement,
            allowedValues: allowed
        )
    }

    private static func controlledV4Property(_ key: String) -> PropertyContract {
        customProperty(
            key,
            .choice,
            allowed: DissertationControlV4.controlledFieldValues[key]?.sorted()
        )
    }

    private static func resolvedValue(
        for contract: PropertyContract,
        in frontmatter: [String: YAMLValue]
    ) -> YAMLValue? {
        if let value = frontmatter[contract.canonicalKey] { return value }
        for alias in contract.legacyAliases {
            if let value = frontmatter[alias] { return value }
        }
        return nil
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
