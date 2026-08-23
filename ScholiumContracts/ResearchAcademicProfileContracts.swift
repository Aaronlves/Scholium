import Foundation

public struct ResearchAcademicFieldID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard AcademicProfileValidation.isIdentifier(rawValue),
              !Self.machineReservedIDs.contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public static let academicOutcome = Self(rawValue: "academic-outcome")!

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = Self(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid or reserved academic field identifier: \(raw)."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static let machineReservedIDs: Set<String> = [
        "action", "actual-writes", "completed-at", "context-use", "conflict",
        "initial-object", "machine", "method", "recovery", "revision", "run",
        "source-references", "started-at", "status", "triptych",
    ]
}

public enum ResearchAcademicFieldKind: String, Codable, CaseIterable, Hashable, Sendable {
    case freeText = "free_text"
    case singleChoice = "single_choice"
    case multipleChoice = "multiple_choice"
}

public enum ResearchAcademicFieldRequirement: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case excluded
    case optional
    case required
}

public enum ResearchAcademicFieldValue: Codable, Hashable, Sendable {
    case freeText(String)
    case singleChoice(String)
    case multipleChoice([String])

    private enum Kind: String, Codable { case freeText, singleChoice, multipleChoice }
    private enum CodingKeys: String, CodingKey, CaseIterable { case kind, text, choice, choices }

    public init(from decoder: Decoder) throws {
        try AcademicProfileValidation.rejectUnknownFields(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let populated = CodingKeys.allCases.filter { $0 != .kind && container.contains($0) }
        switch kind {
        case .freeText:
            guard populated == [.text] else { throw ResearchAcademicProfileError.invalidField }
            self = .freeText(try container.decode(String.self, forKey: .text))
        case .singleChoice:
            guard populated == [.choice] else { throw ResearchAcademicProfileError.invalidField }
            self = .singleChoice(try container.decode(String.self, forKey: .choice))
        case .multipleChoice:
            guard populated == [.choices] else { throw ResearchAcademicProfileError.invalidField }
            self = .multipleChoice(try container.decode([String].self, forKey: .choices))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .freeText(let text):
            try container.encode(Kind.freeText, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .singleChoice(let choice):
            try container.encode(Kind.singleChoice, forKey: .kind)
            try container.encode(choice, forKey: .choice)
        case .multipleChoice(let choices):
            try container.encode(Kind.multipleChoice, forKey: .kind)
            try container.encode(choices, forKey: .choices)
        }
    }
}

public struct ResearchAcademicFieldValues: Codable, Hashable, Sendable {
    public let values: [String: ResearchAcademicFieldValue]

    public init(
        values: [ResearchAcademicFieldID: ResearchAcademicFieldValue] = [:],
        definitions: [ResearchAcademicFieldDefinition]
    ) throws {
        try self.init(
            rawValues: Dictionary(uniqueKeysWithValues: values.map {
                ($0.key.rawValue, $0.value)
            }),
            definitions: definitions
        )
    }

    public init(
        rawValues: [String: ResearchAcademicFieldValue] = [:],
        definitions: [ResearchAcademicFieldDefinition]
    ) throws {
        let active = definitions.filter { $0.requirement != .excluded }
        let byID = Dictionary(uniqueKeysWithValues: active.map { ($0.fieldID.rawValue, $0) })
        guard rawValues.keys.allSatisfy({ byID[$0] != nil }) else {
            throw ResearchAcademicProfileError.invalidFieldValues
        }
        for definition in active {
            guard let value = rawValues[definition.fieldID.rawValue] else {
                if definition.requirement == .required {
                    throw ResearchAcademicProfileError.invalidFieldValues
                }
                continue
            }
            try Self.validate(value, definition: definition)
        }
        values = rawValues
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case values
    }

    public init(from decoder: Decoder) throws {
        try AcademicProfileValidation.rejectUnknownFields(
            decoder,
            allowed: CodingKeys.self
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        values = try container.decode(
            [String: ResearchAcademicFieldValue].self,
            forKey: .values
        )
        guard values.keys.allSatisfy({
            ResearchAcademicFieldID(rawValue: $0) != nil
        }) else {
            throw ResearchAcademicProfileError.invalidFieldValues
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(values, forKey: .values)
    }

    private static func validate(
        _ value: ResearchAcademicFieldValue,
        definition: ResearchAcademicFieldDefinition
    ) throws {
        switch (definition.kind, value) {
        case (.freeText, .freeText(let text)):
            guard text.utf8.count <= (definition.maximumTextUTF8Count ?? 0),
                  definition.requirement != .required
                    || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ResearchAcademicProfileError.invalidFieldValues
            }
        case (.singleChoice, .singleChoice(let choice)):
            guard definition.choices.contains(where: { $0.value == choice }) else {
                throw ResearchAcademicProfileError.invalidFieldValues
            }
        case (.multipleChoice, .multipleChoice(let choices)):
            let allowed = Set(definition.choices.map(\.value))
            guard Set(choices).count == choices.count,
                  choices.allSatisfy(allowed.contains),
                  definition.requirement != .required || !choices.isEmpty else {
                throw ResearchAcademicProfileError.invalidFieldValues
            }
        default:
            throw ResearchAcademicProfileError.invalidFieldValues
        }
    }
}

public struct ResearchAcademicChoice: Codable, Hashable, Sendable {
    public let value: String
    public let label: String

    public init(value: String, label: String) throws {
        guard AcademicProfileValidation.isIdentifier(value) else {
            throw ResearchAcademicProfileError.invalidField
        }
        self.value = value
        self.label = try AcademicProfileValidation.text(label, maximumUTF8Count: 120)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case value
        case label
    }

    public init(from decoder: Decoder) throws {
        try AcademicProfileValidation.rejectUnknownFields(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: container.decode(String.self, forKey: .value),
            label: container.decode(String.self, forKey: .label)
        )
    }
}

/// A researcher-owned academic input or result field. Platform selectors,
/// capabilities, write boundaries, permissions, and machine facts cannot be
/// represented by this type.
public struct ResearchAcademicFieldDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchAcademicFieldID { fieldID }

    public let fieldID: ResearchAcademicFieldID
    public let kind: ResearchAcademicFieldKind
    public let label: String
    public let helpText: String?
    public let requirement: ResearchAcademicFieldRequirement
    public let choices: [ResearchAcademicChoice]
    public let maximumTextUTF8Count: Int?

    public static func freeText(
        id: ResearchAcademicFieldID,
        label: String,
        helpText: String? = nil,
        requirement: ResearchAcademicFieldRequirement,
        maximumTextUTF8Count: Int = 65_536
    ) throws -> Self {
        try Self(
            fieldID: id,
            kind: .freeText,
            label: label,
            helpText: helpText,
            requirement: requirement,
            choices: [],
            maximumTextUTF8Count: maximumTextUTF8Count
        )
    }

    public static func singleChoice(
        id: ResearchAcademicFieldID,
        label: String,
        helpText: String? = nil,
        requirement: ResearchAcademicFieldRequirement,
        choices: [ResearchAcademicChoice]
    ) throws -> Self {
        try Self(
            fieldID: id,
            kind: .singleChoice,
            label: label,
            helpText: helpText,
            requirement: requirement,
            choices: choices,
            maximumTextUTF8Count: nil
        )
    }

    public static func multipleChoice(
        id: ResearchAcademicFieldID,
        label: String,
        helpText: String? = nil,
        requirement: ResearchAcademicFieldRequirement,
        choices: [ResearchAcademicChoice]
    ) throws -> Self {
        try Self(
            fieldID: id,
            kind: .multipleChoice,
            label: label,
            helpText: helpText,
            requirement: requirement,
            choices: choices,
            maximumTextUTF8Count: nil
        )
    }

    private init(
        fieldID: ResearchAcademicFieldID,
        kind: ResearchAcademicFieldKind,
        label: String,
        helpText: String?,
        requirement: ResearchAcademicFieldRequirement,
        choices: [ResearchAcademicChoice],
        maximumTextUTF8Count: Int?
    ) throws {
        guard choices.count <= 32,
              Set(choices.map(\.value)).count == choices.count else {
            throw ResearchAcademicProfileError.invalidField
        }
        switch kind {
        case .freeText:
            guard choices.isEmpty,
                  let maximumTextUTF8Count,
                  (1...262_144).contains(maximumTextUTF8Count) else {
                throw ResearchAcademicProfileError.invalidField
            }
        case .singleChoice, .multipleChoice:
            guard (2...32).contains(choices.count), maximumTextUTF8Count == nil else {
                throw ResearchAcademicProfileError.invalidField
            }
        }
        self.fieldID = fieldID
        self.kind = kind
        self.label = try AcademicProfileValidation.text(label, maximumUTF8Count: 120)
        self.helpText = try helpText.map {
            try AcademicProfileValidation.text($0, maximumUTF8Count: 512)
        }
        self.requirement = requirement
        self.choices = choices
        self.maximumTextUTF8Count = maximumTextUTF8Count
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case fieldID
        case kind
        case label
        case helpText
        case requirement
        case choices
        case maximumTextUTF8Count
    }

    public init(from decoder: Decoder) throws {
        try AcademicProfileValidation.rejectUnknownFields(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fieldID: container.decode(ResearchAcademicFieldID.self, forKey: .fieldID),
            kind: container.decode(ResearchAcademicFieldKind.self, forKey: .kind),
            label: container.decode(String.self, forKey: .label),
            helpText: container.decodeIfPresent(String.self, forKey: .helpText),
            requirement: container.decode(
                ResearchAcademicFieldRequirement.self,
                forKey: .requirement
            ),
            choices: container.decode([ResearchAcademicChoice].self, forKey: .choices),
            maximumTextUTF8Count: container.decodeIfPresent(
                Int.self,
                forKey: .maximumTextUTF8Count
            )
        )
    }
}

public struct ResearchAcademicActionProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: ResearchActionID { actionID }

    public let actionID: ResearchActionID
    public let displayName: String
    public let order: Int
    public let isEnabled: Bool
    public let applicableRoles: [ResearchActionTargetRole]
    public let academicInputFields: [ResearchAcademicFieldDefinition]
    public let academicResultFields: [ResearchAcademicFieldDefinition]

    public init(
        actionID: ResearchActionID,
        displayName: String,
        order: Int,
        isEnabled: Bool,
        applicableRoles: [ResearchActionTargetRole],
        academicInputFields: [ResearchAcademicFieldDefinition],
        academicResultFields: [ResearchAcademicFieldDefinition]
    ) throws {
        guard (0...10_000).contains(order),
              !applicableRoles.isEmpty,
              Set(applicableRoles).count == applicableRoles.count,
              academicInputFields.count <= 24,
              academicResultFields.count <= 24,
              Set(academicInputFields.map(\.fieldID)).count == academicInputFields.count,
              Set(academicResultFields.map(\.fieldID)).count == academicResultFields.count else {
            throw ResearchAcademicProfileError.invalidProfile
        }
        self.actionID = actionID
        self.displayName = try AcademicProfileValidation.text(
            displayName,
            maximumUTF8Count: 80
        )
        self.order = order
        self.isEnabled = isEnabled
        self.applicableRoles = ResearchActionTargetRole.allCases.filter(
            Set(applicableRoles).contains
        )
        self.academicInputFields = academicInputFields
        self.academicResultFields = academicResultFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case actionID
        case displayName
        case order
        case isEnabled
        case applicableRoles
        case academicInputFields
        case academicResultFields
    }

    public init(from decoder: Decoder) throws {
        try AcademicProfileValidation.rejectUnknownFields(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            actionID: container.decode(ResearchActionID.self, forKey: .actionID),
            displayName: container.decode(String.self, forKey: .displayName),
            order: container.decode(Int.self, forKey: .order),
            isEnabled: container.decode(Bool.self, forKey: .isEnabled),
            applicableRoles: container.decode(
                [ResearchActionTargetRole].self,
                forKey: .applicableRoles
            ),
            academicInputFields: container.decode(
                [ResearchAcademicFieldDefinition].self,
                forKey: .academicInputFields
            ),
            academicResultFields: container.decode(
                [ResearchAcademicFieldDefinition].self,
                forKey: .academicResultFields
            )
        )
    }
}

public extension ResearchAcademicActionProfile {
    func contentRevision() throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return DocumentFingerprint(data: try encoder.encode(self))
    }
}

public struct ResearchAcademicProfileDocument: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let profiles: [ResearchAcademicActionProfile]

    public init(profiles: [ResearchAcademicActionProfile]) throws {
        guard profiles.count <= 64,
              Set(profiles.map(\.actionID)).count == profiles.count else {
            throw ResearchAcademicProfileError.invalidDocument
        }
        schemaVersion = Self.currentSchemaVersion
        self.profiles = profiles.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.actionID.rawValue < $1.actionID.rawValue
        }
    }

    public func profile(for actionID: ResearchActionID) -> ResearchAcademicActionProfile? {
        profiles.first { $0.actionID == actionID }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case profiles
    }

    public init(from decoder: Decoder) throws {
        try AcademicProfileValidation.rejectUnknownFields(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else {
            throw ResearchAcademicProfileError.unsupportedSchemaVersion(version)
        }
        try self.init(profiles: container.decode(
            [ResearchAcademicActionProfile].self,
            forKey: .profiles
        ))
    }
}

public enum ResearchAcademicProfileCatalog {
    public static let defaultProfiles: [ResearchAcademicActionProfile] = {
        func id(_ value: String) -> ResearchAcademicFieldID {
            ResearchAcademicFieldID(rawValue: value)!
        }
        func choice(_ value: String, _ label: String) -> ResearchAcademicChoice {
            try! ResearchAcademicChoice(value: value, label: label)
        }
        func text(
            _ fieldID: String,
            _ label: String,
            requirement: ResearchAcademicFieldRequirement,
            help: String? = nil
        ) -> ResearchAcademicFieldDefinition {
            try! .freeText(
                id: id(fieldID),
                label: label,
                helpText: help,
                requirement: requirement
            )
        }
        func single(
            _ fieldID: String,
            _ label: String,
            _ choices: [ResearchAcademicChoice]
        ) -> ResearchAcademicFieldDefinition {
            try! .singleChoice(
                id: id(fieldID),
                label: label,
                requirement: .required,
                choices: choices
            )
        }
        func multiple(
            _ fieldID: String,
            _ label: String,
            _ choices: [ResearchAcademicChoice]
        ) -> ResearchAcademicFieldDefinition {
            try! .multipleChoice(
                id: id(fieldID),
                label: label,
                requirement: .required,
                choices: choices
            )
        }
        let requestID = ResearchAcademicFieldID(rawValue: "research-request")!
        let request = try! ResearchAcademicFieldDefinition.freeText(
            id: requestID,
            label: "Research Request",
            helpText: "State the bounded academic purpose for this Action.",
            requirement: .optional,
            maximumTextUTF8Count: 16_384
        )
        return [
            try! ResearchAcademicActionProfile(
                actionID: .discuss,
                displayName: "Discuss",
                order: 0,
                isEnabled: true,
                applicableRoles: ResearchActionTargetRole.allCases,
                academicInputFields: [request],
                academicResultFields: [
                    text(
                        "overall-conclusion",
                        "Overall Conclusion",
                        requirement: .optional,
                        help: "Optionally state the public conclusion warranted by the full exchange."
                    ),
                    text(
                        "open-question",
                        "Open Question",
                        requirement: .optional,
                        help: "Preserve a question that remains genuinely open after the exchange."
                    ),
                ]
            ),
            try! ResearchAcademicActionProfile(
                actionID: .analyze,
                displayName: "Analyze Note",
                order: 10,
                isEnabled: true,
                applicableRoles: [.analysis],
                academicInputFields: [request],
                academicResultFields: [
                    text(
                        "source-reconstruction",
                        "Source Reconstruction",
                        requirement: .required,
                        help: "Reconstruct the source's relevant concepts, argument, reasons, and limiting uncertainty."
                    ),
                    single("coverage", "Coverage", [
                        choice("all-declared-scope", "All declared scope"),
                        choice("specified-part-only", "Specified part only"),
                        choice("partially-completed", "Partially completed"),
                        choice("unable-to-complete", "Unable to complete"),
                    ]),
                    multiple("reliability", "Reliability", [
                        choice("no-material-limitations", "No material limitations identified"),
                        choice("incomplete-access", "Incomplete access"),
                        choice("ocr-or-extraction", "OCR or extraction problem"),
                        choice("version-or-locator", "Version or locator problem"),
                        choice("unverified", "Unverified"),
                    ]),
                    text("agent-evaluation", "Agent Evaluation", requirement: .optional),
                    text("further-research", "Further Research", requirement: .optional),
                ]
            ),
            try! ResearchAcademicActionProfile(
                actionID: .synthesize,
                displayName: "Synthesize",
                order: 20,
                isEnabled: true,
                applicableRoles: [.topic],
                academicInputFields: [request],
                academicResultFields: [
                    text(
                        "synthesis-outcome",
                        "Synthesis Outcome",
                        requirement: .required,
                        help: "State the integrated result, its public reasons, and any limitation that materially constrains it."
                    ),
                    multiple("contribution", "Contribution", [
                        choice("adds", "Adds"),
                        choice("corrects", "Corrects"),
                        choice("qualifies", "Qualifies"),
                        choice("connects", "Connects"),
                        choice("reopens", "Reopens"),
                        choice("no-warranted-change", "No sufficient reason to change the current synthesis or target text"),
                    ]),
                    text("unresolved-tension", "Unresolved Tension", requirement: .optional),
                    text("next-step", "Next Step", requirement: .optional),
                ]
            ),
            try! ResearchAcademicActionProfile(
                actionID: .write,
                displayName: "Write",
                order: 30,
                isEnabled: true,
                applicableRoles: [.work],
                academicInputFields: [request],
                academicResultFields: [
                    text(
                        "writing-outcome",
                        "Writing Outcome",
                        requirement: .required,
                        help: "Summarize the bounded writing result without duplicating the target document."
                    ),
                    multiple("change-kind", "Change Kind", [
                        choice("drafted", "Drafted"),
                        choice("revised", "Revised"),
                        choice("reorganized", "Reorganized"),
                        choice("clarified", "Clarified"),
                        choice("no-warranted-change", "No sufficient reason to change the target text"),
                    ]),
                    text("remaining-pressure", "Remaining Pressure", requirement: .optional),
                    text("evidence-basis", "Evidence Basis", requirement: .optional),
                ]
            ),
            try! ResearchAcademicActionProfile(
                actionID: .critique,
                displayName: "Critique",
                order: 40,
                isEnabled: true,
                applicableRoles: [.work],
                academicInputFields: [request],
                academicResultFields: [
                    text(
                        "assessment",
                        "Assessment",
                        requirement: .required,
                        help: "Give the source- and argument-sensitive assessment with enough public reason to reopen it."
                    ),
                    multiple("issue-kind", "Issue Kind", [
                        choice("interpretation", "Interpretation"),
                        choice("argument", "Argument"),
                        choice("source-use", "Source use"),
                        choice("objection-and-reply", "Objection and reply"),
                        choice("alternative", "Alternative"),
                        choice("other", "Other"),
                        choice("no-substantive-issue", "No substantive issue found"),
                    ]),
                    text("significance", "Significance", requirement: .optional),
                    text("recommendation", "Recommendation", requirement: .optional),
                ]
            ),
            try! ResearchAcademicActionProfile(
                actionID: .checkFidelity,
                displayName: "Check Fidelity",
                order: 50,
                isEnabled: true,
                applicableRoles: ResearchActionTargetRole.allCases,
                academicInputFields: [request],
                academicResultFields: [
                    text(
                        "finding",
                        "Finding",
                        requirement: .required,
                        help: "State the revision-bound fidelity finding and the exact scope of the check."
                    ),
                    single("finding-status", "Finding Status", [
                        choice("no-inconsistency-in-checked-scope", "No inconsistency found within the checked scope"),
                        choice("inconsistency-found", "Inconsistency found"),
                        choice("unable-to-verify", "Unable to verify"),
                    ]),
                    text("suggested-correction", "Suggested Correction", requirement: .optional),
                ]
            ),
        ]
    }()

    public static let defaultDocument = try! ResearchAcademicProfileDocument(
        profiles: defaultProfiles
    )

    /// Fixed Platform semantics for the few baseline choices whose explicit
    /// no-change/no-issue value is mutually exclusive with positive values.
    /// This is not a user-defined validator or a generic conditional-form
    /// framework; unknown or researcher-replaced fields receive no hidden rule.
    public static func validatePlatformResultRules(
        _ values: ResearchAcademicFieldValues,
        actionID: ResearchActionID
    ) throws {
        let rule: (fieldID: String, exclusiveValue: String)? = switch actionID {
        case .analyze: ("reliability", "no-material-limitations")
        case .synthesize: ("contribution", "no-warranted-change")
        case .write: ("change-kind", "no-warranted-change")
        case .critique: ("issue-kind", "no-substantive-issue")
        case .discuss, .checkFidelity: nil
        default: nil
        }
        guard let rule,
              case .multipleChoice(let choices)? = values.values[rule.fieldID]
        else { return }
        guard !choices.contains(rule.exclusiveValue) || choices.count == 1 else {
            throw ResearchAcademicProfileError.invalidFieldValues
        }
    }
}

public struct ResearchAcademicProfileSnapshot: Hashable, Sendable {
    public let document: ResearchAcademicProfileDocument
    public let revision: DocumentFingerprint

    public init(document: ResearchAcademicProfileDocument, revision: DocumentFingerprint) {
        self.document = document
        self.revision = revision
    }
}

public enum ResearchMachineResultPurpose: String, Codable, Hashable, Sendable {
    case researcherJudgment = "researcher_judgment"
    case safetyAndRecovery = "safety_and_recovery"
    case researchContinuity = "research_continuity"
}

public enum ResearchMachineResultFieldID: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case run
    case action
    case initialObject = "initial_object"
    case method
    case startedAt = "started_at"
    case completedAt = "completed_at"
    case sourceReferences = "source_references"
    case actualWrites = "actual_writes"
    case recovery
    case contextUse = "context_use"

    public var purpose: ResearchMachineResultPurpose {
        switch self {
        case .actualWrites, .recovery:
            .safetyAndRecovery
        case .sourceReferences, .contextUse, .method:
            .researchContinuity
        case .run, .action, .initialObject, .startedAt, .completedAt:
            .researcherJudgment
        }
    }
}

/// Frozen once per Run. Agent fields remain separate from fields Scholium can
/// derive and prefill from its actual machine state.
public struct ResearchResultContract: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let actionID: ResearchActionID
    public let registrationKey: ResearchSkillRegistrationKey
    public let profileRevision: DocumentFingerprint
    public let academicFields: [ResearchAcademicFieldDefinition]
    public let machineFields: [ResearchMachineResultFieldID]

    public init(
        profile: ResearchAcademicActionProfile,
        registrationKey: ResearchSkillRegistrationKey,
        profileRevision: DocumentFingerprint,
        machineFields: [ResearchMachineResultFieldID] = ResearchMachineResultFieldID.allCases
    ) throws {
        let included = profile.academicResultFields.filter {
            $0.requirement != .excluded
        }
        try self.init(
            schemaVersion: Self.currentSchemaVersion,
            actionID: profile.actionID,
            registrationKey: registrationKey,
            profileRevision: profileRevision,
            academicFields: included,
            machineFields: machineFields
        )
    }

    private init(
        schemaVersion: Int,
        actionID: ResearchActionID,
        registrationKey: ResearchSkillRegistrationKey,
        profileRevision: DocumentFingerprint,
        academicFields: [ResearchAcademicFieldDefinition],
        machineFields: [ResearchMachineResultFieldID]
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              academicFields.allSatisfy({ $0.requirement != .excluded }),
              Set(academicFields.map(\.fieldID)).count == academicFields.count,
              profileRevision.byteCount >= 0,
              profileRevision.sha256.range(
                of: #"^[0-9a-f]{64}$"#,
                options: .regularExpression
              ) != nil,
              Set(machineFields).count == machineFields.count else {
            if schemaVersion != Self.currentSchemaVersion {
                throw ResearchAcademicProfileError.unsupportedSchemaVersion(schemaVersion)
            }
            throw ResearchAcademicProfileError.invalidResultContract
        }
        self.schemaVersion = schemaVersion
        self.actionID = actionID
        self.registrationKey = registrationKey
        self.profileRevision = profileRevision
        self.academicFields = academicFields
        self.machineFields = ResearchMachineResultFieldID.allCases.filter(
            Set(machineFields).contains
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case actionID
        case registrationKey
        case profileRevision
        case academicFields
        case machineFields
    }

    public init(from decoder: Decoder) throws {
        try AcademicProfileValidation.rejectUnknownFields(decoder, allowed: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            actionID: container.decode(ResearchActionID.self, forKey: .actionID),
            registrationKey: container.decode(
                ResearchSkillRegistrationKey.self,
                forKey: .registrationKey
            ),
            profileRevision: container.decode(
                DocumentFingerprint.self,
                forKey: .profileRevision
            ),
            academicFields: container.decode(
                [ResearchAcademicFieldDefinition].self,
                forKey: .academicFields
            ),
            machineFields: container.decode(
                [ResearchMachineResultFieldID].self,
                forKey: .machineFields
            )
        )
    }
}

public enum ResearchAcademicProfileError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(String)
    case invalidField
    case invalidProfile
    case invalidDocument
    case invalidResultContract
    case invalidFieldValues
    case invalidText

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported academic Action Profile schema version \(version)."
        case .unsupportedField(let field):
            "Unsupported academic Action Profile field: \(field)."
        case .invalidField:
            "The academic field definition is invalid."
        case .invalidProfile:
            "The academic Action Profile is invalid."
        case .invalidDocument:
            "The academic Action Profile document is invalid."
        case .invalidResultContract:
            "The frozen Result Contract is invalid."
        case .invalidFieldValues:
            "The academic field values do not satisfy the current Profile."
        case .invalidText:
            "Academic Profile text is invalid."
        }
    }
}

private enum AcademicProfileValidation {
    static func isIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...64).contains(bytes.count)
            && bytes.first != 45
            && bytes.last != 45
            && !value.contains("--")
            && bytes.allSatisfy { byte in
                byte == 45 || (48...57).contains(byte) || (97...122).contains(byte)
            }
    }

    static func text(_ value: String, maximumUTF8Count: Int) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= maximumUTF8Count,
              !trimmed.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw ResearchAcademicProfileError.invalidText }
        return trimmed
    }

    static func rejectUnknownFields<Key: CodingKey & CaseIterable>(
        _ decoder: Decoder,
        allowed: Key.Type
    ) throws {
        let raw = try decoder.container(keyedBy: AcademicCodingKey.self)
        let known = Set(Key.allCases.map(\.stringValue))
        if let unknown = raw.allKeys.map(\.stringValue).first(where: {
            !known.contains($0)
        }) {
            throw ResearchAcademicProfileError.unsupportedField(unknown)
        }
    }

    private struct AcademicCodingKey: CodingKey {
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
}
