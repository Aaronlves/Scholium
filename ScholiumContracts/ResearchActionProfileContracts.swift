import Foundation

/// Stable identity for one researcher-configured field in an Action sheet.
///
/// Application-owned fields such as Target, revision, authority, checkpoint,
/// conflict, and recovery are deliberately reserved. A Profile can request
/// additional focal input, but cannot impersonate or replace those fields.
public struct ResearchActionModuleID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard ResearchActionProfileValidation.isIdentifier(rawValue),
              !Self.applicationOwnedIDs.contains(rawValue) else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let identifier = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid or reserved Action module identifier: \(rawValue)"
            )
        }
        self = identifier
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static let applicationOwnedIDs: Set<String> = [
        "authority",
        "authorization",
        "cancellation",
        "checkpoint",
        "comparison",
        "completion",
        "conflict",
        "consequential-scope",
        "fingerprint",
        "identity",
        "permission",
        "preparation",
        "recovery",
        "revision",
        "source-access",
        "status",
        "target",
        "write-scope",
    ]
}

/// Stable value for one choice supplied by an enumeration module.
public struct ResearchActionModuleChoiceValue: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard ResearchActionProfileValidation.isIdentifier(rawValue) else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Action module choice value: \(rawValue)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One labelled value in an enumeration module. Choice order is interface
/// order and remains researcher-owned.
public struct ResearchActionModuleChoice: Codable, Hashable, Sendable {
    public static let maximumLabelUTF8ByteCount = 120

    public let value: ResearchActionModuleChoiceValue
    public let label: String

    public init(value: ResearchActionModuleChoiceValue, label: String) throws {
        guard ResearchActionProfileValidation.isBoundedSingleLineText(
            label,
            maximumUTF8ByteCount: Self.maximumLabelUTF8ByteCount
        ) else {
            throw ResearchActionProfileContractError.invalidModule(
                "An enumeration choice label must contain 1...\(Self.maximumLabelUTF8ByteCount) UTF-8 bytes and no control characters."
            )
        }
        self.value = value
        self.label = label
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case value
        case label
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionProfileValidation.rejectUnknownFields(
            in: decoder,
            context: "module choice",
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            value: container.decode(ResearchActionModuleChoiceValue.self, forKey: .value),
            label: container.decode(String.self, forKey: .label)
        )
    }
}

/// Closed set of native, declarative modules that Scholium can render.
public enum ResearchActionModuleKind: String, Codable, CaseIterable, Hashable, Sendable {
    case notePicker = "note_picker"
    case passageAnchor = "passage_anchor"
    case materialSelector = "material_selector"
    case sourceReference = "source_reference"
    case boundedText = "bounded_text"
    case boolean
    case enumeration = "enum"
}

/// One validated request for an additional native field in the common Action
/// sheet. Optional configuration is exposed for rendering, but each factory
/// and the decoder accepts only the fields meaningful for its module kind.
public struct ResearchActionModuleDefinition: Codable, Hashable, Sendable {
    public static let maximumLabelUTF8ByteCount = 120
    public static let maximumHelpTextUTF8ByteCount = 512
    public static let maximumPickerSelectionCount = 16
    public static let maximumBoundedTextUTF8ByteCount = 16_384
    public static let maximumEnumerationChoiceCount = 32
    public static let maximumEnumerationSelectionCount = 16

    public let id: ResearchActionModuleID
    public let kind: ResearchActionModuleKind
    public let label: String
    public let helpText: String?
    public let isRequired: Bool
    public let roleScope: [ResearchActionTargetRole]?
    public let maximumSelectionCount: Int?
    public let maximumTextUTF8ByteCount: Int?
    public let allowsMultipleLines: Bool?
    public let choices: [ResearchActionModuleChoice]?
    public let defaultBoolean: Bool?

    public static func notePicker(
        id: ResearchActionModuleID,
        label: String,
        helpText: String? = nil,
        isRequired: Bool,
        roleScope: [ResearchActionTargetRole],
        maximumSelectionCount: Int
    ) throws -> Self {
        try picker(
            id: id,
            kind: .notePicker,
            label: label,
            helpText: helpText,
            isRequired: isRequired,
            roleScope: roleScope,
            maximumSelectionCount: maximumSelectionCount
        )
    }

    public static func materialSelector(
        id: ResearchActionModuleID,
        label: String,
        helpText: String? = nil,
        isRequired: Bool,
        roleScope: [ResearchActionTargetRole],
        maximumSelectionCount: Int
    ) throws -> Self {
        try picker(
            id: id,
            kind: .materialSelector,
            label: label,
            helpText: helpText,
            isRequired: isRequired,
            roleScope: roleScope,
            maximumSelectionCount: maximumSelectionCount
        )
    }

    public static func passageAnchor(
        id: ResearchActionModuleID,
        label: String,
        helpText: String? = nil,
        isRequired: Bool
    ) throws -> Self {
        try Self(
            id: id,
            kind: .passageAnchor,
            label: label,
            helpText: helpText,
            isRequired: isRequired
        )
    }

    public static func sourceReference(
        id: ResearchActionModuleID,
        label: String,
        helpText: String? = nil,
        isRequired: Bool
    ) throws -> Self {
        try Self(
            id: id,
            kind: .sourceReference,
            label: label,
            helpText: helpText,
            isRequired: isRequired
        )
    }

    public static func boundedText(
        id: ResearchActionModuleID,
        label: String,
        helpText: String? = nil,
        isRequired: Bool,
        maximumTextUTF8ByteCount: Int,
        allowsMultipleLines: Bool
    ) throws -> Self {
        guard (1...Self.maximumBoundedTextUTF8ByteCount).contains(
            maximumTextUTF8ByteCount
        ) else {
            throw ResearchActionProfileContractError.invalidModule(
                "A bounded-text module maximum must be within 1...\(Self.maximumBoundedTextUTF8ByteCount) UTF-8 bytes."
            )
        }
        return try Self(
            id: id,
            kind: .boundedText,
            label: label,
            helpText: helpText,
            isRequired: isRequired,
            maximumTextUTF8ByteCount: maximumTextUTF8ByteCount,
            allowsMultipleLines: allowsMultipleLines
        )
    }

    public static func boolean(
        id: ResearchActionModuleID,
        label: String,
        helpText: String? = nil,
        isRequired: Bool,
        defaultValue: Bool
    ) throws -> Self {
        try Self(
            id: id,
            kind: .boolean,
            label: label,
            helpText: helpText,
            isRequired: isRequired,
            defaultBoolean: defaultValue
        )
    }

    public static func enumeration(
        id: ResearchActionModuleID,
        label: String,
        helpText: String? = nil,
        isRequired: Bool,
        choices: [ResearchActionModuleChoice],
        maximumSelectionCount: Int
    ) throws -> Self {
        guard (2...Self.maximumEnumerationChoiceCount).contains(choices.count) else {
            throw ResearchActionProfileContractError.invalidModule(
                "An enumeration module must contain 2...\(Self.maximumEnumerationChoiceCount) choices."
            )
        }
        guard Set(choices.map(\.value)).count == choices.count else {
            throw ResearchActionProfileContractError.invalidModule(
                "An enumeration module cannot repeat a choice value."
            )
        }
        let maximumAllowed = min(
            choices.count,
            Self.maximumEnumerationSelectionCount
        )
        guard (1...maximumAllowed).contains(maximumSelectionCount) else {
            throw ResearchActionProfileContractError.invalidModule(
                "An enumeration selection maximum must be within 1...\(maximumAllowed)."
            )
        }
        return try Self(
            id: id,
            kind: .enumeration,
            label: label,
            helpText: helpText,
            isRequired: isRequired,
            maximumSelectionCount: maximumSelectionCount,
            choices: choices
        )
    }

    private static func picker(
        id: ResearchActionModuleID,
        kind: ResearchActionModuleKind,
        label: String,
        helpText: String?,
        isRequired: Bool,
        roleScope: [ResearchActionTargetRole],
        maximumSelectionCount: Int
    ) throws -> Self {
        guard let canonicalRoles = ResearchActionProfileValidation.canonicalRoles(
            roleScope
        ) else {
            throw ResearchActionProfileContractError.invalidModule(
                "A \(kind.rawValue) role scope cannot repeat a role."
            )
        }
        guard !canonicalRoles.isEmpty else {
            throw ResearchActionProfileContractError.invalidModule(
                "A picker module must declare at least one readable note role."
            )
        }
        guard (1...Self.maximumPickerSelectionCount).contains(maximumSelectionCount) else {
            throw ResearchActionProfileContractError.invalidModule(
                "A picker selection maximum must be within 1...\(Self.maximumPickerSelectionCount)."
            )
        }
        return try Self(
            id: id,
            kind: kind,
            label: label,
            helpText: helpText,
            isRequired: isRequired,
            roleScope: canonicalRoles,
            maximumSelectionCount: maximumSelectionCount
        )
    }

    private init(
        id: ResearchActionModuleID,
        kind: ResearchActionModuleKind,
        label: String,
        helpText: String?,
        isRequired: Bool,
        roleScope: [ResearchActionTargetRole]? = nil,
        maximumSelectionCount: Int? = nil,
        maximumTextUTF8ByteCount: Int? = nil,
        allowsMultipleLines: Bool? = nil,
        choices: [ResearchActionModuleChoice]? = nil,
        defaultBoolean: Bool? = nil
    ) throws {
        guard ResearchActionProfileValidation.isBoundedSingleLineText(
            label,
            maximumUTF8ByteCount: Self.maximumLabelUTF8ByteCount
        ) else {
            throw ResearchActionProfileContractError.invalidModule(
                "A module label must contain 1...\(Self.maximumLabelUTF8ByteCount) UTF-8 bytes and no control characters."
            )
        }
        guard !ResearchActionProfileValidation.isApplicationOwnedModuleLabel(
            label
        ) else {
            throw ResearchActionProfileContractError.invalidModule(
                "A researcher module cannot use an Application-owned field label."
            )
        }
        if let helpText {
            guard ResearchActionProfileValidation.isBoundedSingleLineText(
                helpText,
                maximumUTF8ByteCount: Self.maximumHelpTextUTF8ByteCount
            ) else {
                throw ResearchActionProfileContractError.invalidModule(
                    "Module help text must contain 1...\(Self.maximumHelpTextUTF8ByteCount) UTF-8 bytes and no control characters."
                )
            }
        }
        self.id = id
        self.kind = kind
        self.label = label
        self.helpText = helpText
        self.isRequired = isRequired
        self.roleScope = roleScope
        self.maximumSelectionCount = maximumSelectionCount
        self.maximumTextUTF8ByteCount = maximumTextUTF8ByteCount
        self.allowsMultipleLines = allowsMultipleLines
        self.choices = choices
        self.defaultBoolean = defaultBoolean
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id = "module_id"
        case kind
        case label
        case helpText = "help_text"
        case isRequired = "required"
        case roleScope = "role_scope"
        case maximumSelectionCount = "maximum_selection_count"
        case maximumTextUTF8ByteCount = "maximum_text_utf8_byte_count"
        case allowsMultipleLines = "allows_multiple_lines"
        case choices
        case defaultBoolean = "default_boolean"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ResearchActionModuleKind.self, forKey: .kind)
        try ResearchActionProfileValidation.rejectUnknownFields(
            in: decoder,
            context: "\(kind.rawValue) module",
            allowed: Self.allowedCodingKeys(for: kind).map(\.stringValue)
        )

        let id = try container.decode(ResearchActionModuleID.self, forKey: .id)
        let label = try container.decode(String.self, forKey: .label)
        let helpText = try container.decodeIfPresent(String.self, forKey: .helpText)
        let isRequired = try container.decode(Bool.self, forKey: .isRequired)

        switch kind {
        case .notePicker:
            self = try Self.notePicker(
                id: id,
                label: label,
                helpText: helpText,
                isRequired: isRequired,
                roleScope: container.decode([ResearchActionTargetRole].self, forKey: .roleScope),
                maximumSelectionCount: container.decode(
                    Int.self,
                    forKey: .maximumSelectionCount
                )
            )
        case .passageAnchor:
            self = try Self.passageAnchor(
                id: id,
                label: label,
                helpText: helpText,
                isRequired: isRequired
            )
        case .materialSelector:
            self = try Self.materialSelector(
                id: id,
                label: label,
                helpText: helpText,
                isRequired: isRequired,
                roleScope: container.decode([ResearchActionTargetRole].self, forKey: .roleScope),
                maximumSelectionCount: container.decode(
                    Int.self,
                    forKey: .maximumSelectionCount
                )
            )
        case .sourceReference:
            self = try Self.sourceReference(
                id: id,
                label: label,
                helpText: helpText,
                isRequired: isRequired
            )
        case .boundedText:
            self = try Self.boundedText(
                id: id,
                label: label,
                helpText: helpText,
                isRequired: isRequired,
                maximumTextUTF8ByteCount: container.decode(
                    Int.self,
                    forKey: .maximumTextUTF8ByteCount
                ),
                allowsMultipleLines: container.decode(Bool.self, forKey: .allowsMultipleLines)
            )
        case .boolean:
            self = try Self.boolean(
                id: id,
                label: label,
                helpText: helpText,
                isRequired: isRequired,
                defaultValue: container.decode(Bool.self, forKey: .defaultBoolean)
            )
        case .enumeration:
            self = try Self.enumeration(
                id: id,
                label: label,
                helpText: helpText,
                isRequired: isRequired,
                choices: container.decode([ResearchActionModuleChoice].self, forKey: .choices),
                maximumSelectionCount: container.decode(
                    Int.self,
                    forKey: .maximumSelectionCount
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(helpText, forKey: .helpText)
        try container.encode(isRequired, forKey: .isRequired)

        switch kind {
        case .notePicker, .materialSelector:
            try container.encode(roleScope, forKey: .roleScope)
            try container.encode(maximumSelectionCount, forKey: .maximumSelectionCount)
        case .boundedText:
            try container.encode(
                maximumTextUTF8ByteCount,
                forKey: .maximumTextUTF8ByteCount
            )
            try container.encode(allowsMultipleLines, forKey: .allowsMultipleLines)
        case .boolean:
            try container.encode(defaultBoolean, forKey: .defaultBoolean)
        case .enumeration:
            try container.encode(choices, forKey: .choices)
            try container.encode(maximumSelectionCount, forKey: .maximumSelectionCount)
        case .passageAnchor, .sourceReference:
            break
        }
    }

    private static func allowedCodingKeys(
        for kind: ResearchActionModuleKind
    ) -> Set<CodingKeys> {
        var allowed: Set<CodingKeys> = [.id, .kind, .label, .helpText, .isRequired]
        switch kind {
        case .notePicker, .materialSelector:
            allowed.formUnion([.roleScope, .maximumSelectionCount])
        case .boundedText:
            allowed.formUnion([.maximumTextUTF8ByteCount, .allowsMultipleLines])
        case .boolean:
            allowed.insert(.defaultBoolean)
        case .enumeration:
            allowed.formUnion([.choices, .maximumSelectionCount])
        case .passageAnchor, .sourceReference:
            break
        }
        return allowed
    }
}

/// Existing-note operations that a Profile may request. Lifecycle operations,
/// conflict overwrite, arbitrary execution, and record mutation are absent by
/// construction and remain unavailable to Profiles.
public enum ResearchActionCandidateWriteOperation: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case modifyMarkdown = "modify_markdown"
    case modifyProperties = "modify_properties"
}

/// Declarative maximum scope requested by one Profile. It is input to a later
/// authority intersection, never a grant or reusable permission token.
public struct ResearchActionCapabilityDeclaration: Codable, Hashable, Sendable {
    public static let maximumEditablePropertyKeyCount = 64
    public static let maximumPropertyKeyUTF8ByteCount = 128

    public let readableRoles: [ResearchActionTargetRole]
    public let candidateWritableRoles: [ResearchActionTargetRole]
    public let candidateWriteOperations: [ResearchActionCandidateWriteOperation]
    public let editablePropertyKeys: [String]

    public init(
        readableRoles: [ResearchActionTargetRole],
        candidateWritableRoles: [ResearchActionTargetRole] = [],
        candidateWriteOperations: [ResearchActionCandidateWriteOperation] = [],
        editablePropertyKeys: [String] = []
    ) throws {
        guard let readableRoles = ResearchActionProfileValidation.canonicalRoles(
            readableRoles
        ) else {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "Readable roles must be unique."
            )
        }
        guard !readableRoles.isEmpty else {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "At least one readable role is required."
            )
        }
        guard let writableRoles = ResearchActionProfileValidation.canonicalRoles(
            candidateWritableRoles
        ) else {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "Candidate writable roles must be unique."
            )
        }
        guard Set(writableRoles).isSubset(of: Set(readableRoles)) else {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "Candidate writable roles must also be readable."
            )
        }
        let operations = try ResearchActionProfileValidation.canonicalWriteOperations(
            candidateWriteOperations
        )

        if writableRoles.isEmpty {
            guard operations.isEmpty, editablePropertyKeys.isEmpty else {
                throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                    "A declaration without candidate writable roles cannot request write operations or property keys."
                )
            }
        } else if operations.isEmpty {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "Candidate writable roles require at least one bounded write operation."
            )
        }

        guard editablePropertyKeys.count <= Self.maximumEditablePropertyKeyCount else {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "A declaration may contain at most \(Self.maximumEditablePropertyKeyCount) property keys."
            )
        }
        guard Set(editablePropertyKeys).count == editablePropertyKeys.count else {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "Editable property keys must be unique."
            )
        }
        for key in editablePropertyKeys {
            guard ResearchActionProfileValidation.isBoundedSingleLineText(
                key,
                maximumUTF8ByteCount: Self.maximumPropertyKeyUTF8ByteCount
            ) else {
                throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                    "An editable property key must contain 1...\(Self.maximumPropertyKeyUTF8ByteCount) UTF-8 bytes and no control characters."
                )
            }
            guard !PropertyContractCatalog.isProtectedMachineKey(key) else {
                throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                    "A protected machine property cannot become a Profile write boundary."
                )
            }
        }
        let modifiesProperties = operations.contains(.modifyProperties)
        guard modifiesProperties == !editablePropertyKeys.isEmpty else {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "The modify-properties operation and its nonempty property boundary must be declared together."
            )
        }

        self.readableRoles = readableRoles
        self.candidateWritableRoles = writableRoles
        self.candidateWriteOperations = operations
        self.editablePropertyKeys = editablePropertyKeys.sorted()
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case readableRoles = "readable_roles"
        case candidateWritableRoles = "candidate_writable_roles"
        case candidateWriteOperations = "candidate_write_operations"
        case editablePropertyKeys = "editable_property_keys"
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionProfileValidation.rejectUnknownFields(
            in: decoder,
            context: "capability declaration",
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            readableRoles: container.decode(
                [ResearchActionTargetRole].self,
                forKey: .readableRoles
            ),
            candidateWritableRoles: container.decode(
                [ResearchActionTargetRole].self,
                forKey: .candidateWritableRoles
            ),
            candidateWriteOperations: container.decode(
                [ResearchActionCandidateWriteOperation].self,
                forKey: .candidateWriteOperations
            ),
            editablePropertyKeys: container.decode([String].self, forKey: .editablePropertyKeys)
        )
    }
}

/// Whether an Action sheet exposes source selection and whether one verified
/// source is structurally required before preparation.
public enum ResearchActionSourceRequirement: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case optional
    case required
}

/// Structured post-run feedback requested by a Profile. This describes an
/// expected output and does not certify that an agent followed its method.
public enum ResearchActionFeedbackRequirement: String, Codable, CaseIterable,
    Hashable, Sendable
{
    case none
    case requested
    case required
}

/// Versioned, researcher-owned declarative configuration for one Action.
///
/// A Profile controls presentation and requests a bounded capability ceiling.
/// The Application still owns Target, revisions, authorization, checkpoints,
/// conflicts, completion, and recovery, and later intersects this declaration
/// with every other authority boundary.
public struct ResearchActionProfile: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    public static let maximumButtonNameUTF8ByteCount = 80
    public static let maximumOrder = 10_000
    public static let maximumModuleCount = 24
    public static let maximumTotalEnumerationChoiceCount = 128

    public let schemaVersion: Int
    public let definition: ResearchActionDefinition
    public let buttonName: String
    public let order: Int
    public let applicableRoles: [ResearchActionTargetRole]
    public let showInActions: Bool
    public let modules: [ResearchActionModuleDefinition]
    public let sourceRequirement: ResearchActionSourceRequirement
    public let capabilities: ResearchActionCapabilityDeclaration
    public let feedbackRequirement: ResearchActionFeedbackRequirement

    public var actionID: ResearchActionID { definition.id }
    public var executionKind: ResearchActionExecutionKind { definition.executionKind }

    public init(
        definition: ResearchActionDefinition,
        buttonName: String,
        order: Int,
        applicableRoles: [ResearchActionTargetRole],
        showInActions: Bool,
        modules: [ResearchActionModuleDefinition],
        sourceRequirement: ResearchActionSourceRequirement,
        capabilities: ResearchActionCapabilityDeclaration,
        feedbackRequirement: ResearchActionFeedbackRequirement
    ) throws {
        guard ResearchActionProfileValidation.isBoundedSingleLineText(
            buttonName,
            maximumUTF8ByteCount: Self.maximumButtonNameUTF8ByteCount
        ) else {
            throw ResearchActionProfileContractError.invalidProfile(
                "A button name must contain 1...\(Self.maximumButtonNameUTF8ByteCount) UTF-8 bytes and no control characters."
            )
        }
        guard (0...Self.maximumOrder).contains(order) else {
            throw ResearchActionProfileContractError.invalidProfile(
                "Action order must be within 0...\(Self.maximumOrder)."
            )
        }
        guard let applicableRoles = ResearchActionProfileValidation.canonicalRoles(
            applicableRoles
        ) else {
            throw ResearchActionProfileContractError.invalidProfile(
                "The applicable roles declaration cannot repeat a role."
            )
        }
        guard !applicableRoles.isEmpty,
              Set(applicableRoles).isSubset(of: definition.allowedTargetRoles) else {
            throw ResearchActionProfileContractError.invalidProfile(
                "Applicable roles must be a nonempty narrowing of the Action execution kind."
            )
        }
        guard Set(applicableRoles).isSubset(of: Set(capabilities.readableRoles)) else {
            throw ResearchActionProfileContractError.invalidProfile(
                "Every applicable Target role must remain readable and visible to the Application."
            )
        }
        guard modules.count <= Self.maximumModuleCount else {
            throw ResearchActionProfileContractError.invalidProfile(
                "An Action Profile may contain at most \(Self.maximumModuleCount) modules."
            )
        }
        guard Set(modules.map(\.id)).count == modules.count else {
            throw ResearchActionProfileContractError.invalidProfile(
                "Action module identifiers must be unique within a Profile."
            )
        }
        let totalChoiceCount = modules.reduce(into: 0) { count, module in
            count += module.choices?.count ?? 0
        }
        guard totalChoiceCount <= Self.maximumTotalEnumerationChoiceCount else {
            throw ResearchActionProfileContractError.invalidProfile(
                "An Action Profile may contain at most \(Self.maximumTotalEnumerationChoiceCount) enumeration choices."
            )
        }

        let readableRoles = Set(capabilities.readableRoles)
        for module in modules {
            if let roleScope = module.roleScope,
               !Set(roleScope).isSubset(of: readableRoles) {
                throw ResearchActionProfileContractError.invalidProfile(
                    "Module \(module.id.rawValue) requests note roles outside the declared readable scope."
                )
            }
        }

        let writableLimit = definition.executionKind.maximumCandidateWritableRoles
        guard Set(capabilities.candidateWritableRoles).isSubset(of: writableLimit) else {
            throw ResearchActionProfileContractError.invalidProfile(
                "Candidate writable roles exceed the hard limit for \(definition.executionKind.rawValue)."
            )
        }
        try Self.validateSourceRequirement(
            sourceRequirement,
            modules: modules,
            executionKind: definition.executionKind
        )

        schemaVersion = Self.currentSchemaVersion
        self.definition = definition
        self.buttonName = buttonName
        self.order = order
        self.applicableRoles = applicableRoles
        self.showInActions = showInActions
        self.modules = modules
        self.sourceRequirement = sourceRequirement
        self.capabilities = capabilities
        self.feedbackRequirement = feedbackRequirement
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case actionID = "action_id"
        case executionKind = "execution_kind"
        case buttonName = "button_name"
        case order
        case applicableRoles = "applicable_roles"
        case showInActions = "show_in_actions"
        case modules
        case sourceRequirement = "source_requirement"
        case capabilities
        case feedbackRequirement = "feedback_requirement"
    }

    public init(from decoder: Decoder) throws {
        try ResearchActionProfileValidation.rejectUnknownFields(
            in: decoder,
            context: "Action Profile",
            allowed: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ResearchActionProfileContractError.unsupportedSchemaVersion(schemaVersion)
        }
        let definition = try ResearchActionDefinition(
            validatingID: container.decode(ResearchActionID.self, forKey: .actionID),
            executionKind: container.decode(
                ResearchActionExecutionKind.self,
                forKey: .executionKind
            )
        )
        try self.init(
            definition: definition,
            buttonName: container.decode(String.self, forKey: .buttonName),
            order: container.decode(Int.self, forKey: .order),
            applicableRoles: container.decode(
                [ResearchActionTargetRole].self,
                forKey: .applicableRoles
            ),
            showInActions: container.decode(Bool.self, forKey: .showInActions),
            modules: container.decode([ResearchActionModuleDefinition].self, forKey: .modules),
            sourceRequirement: container.decode(
                ResearchActionSourceRequirement.self,
                forKey: .sourceRequirement
            ),
            capabilities: container.decode(
                ResearchActionCapabilityDeclaration.self,
                forKey: .capabilities
            ),
            feedbackRequirement: container.decode(
                ResearchActionFeedbackRequirement.self,
                forKey: .feedbackRequirement
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(actionID, forKey: .actionID)
        try container.encode(executionKind, forKey: .executionKind)
        try container.encode(buttonName, forKey: .buttonName)
        try container.encode(order, forKey: .order)
        try container.encode(applicableRoles, forKey: .applicableRoles)
        try container.encode(showInActions, forKey: .showInActions)
        try container.encode(modules, forKey: .modules)
        try container.encode(sourceRequirement, forKey: .sourceRequirement)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(feedbackRequirement, forKey: .feedbackRequirement)
    }

    private static func validateSourceRequirement(
        _ requirement: ResearchActionSourceRequirement,
        modules: [ResearchActionModuleDefinition],
        executionKind: ResearchActionExecutionKind
    ) throws {
        let sourceModules = modules.filter { $0.kind == .sourceReference }
        guard sourceModules.count <= 1 else {
            throw ResearchActionProfileContractError.invalidProfile(
                "An Action Profile may contain at most one source-reference module."
            )
        }
        switch requirement {
        case .none:
            guard sourceModules.isEmpty else {
                throw ResearchActionProfileContractError.invalidProfile(
                    "A source-reference module requires an optional or required source declaration."
                )
            }
        case .optional:
            guard sourceModules.count == 1, sourceModules[0].isRequired == false else {
                throw ResearchActionProfileContractError.invalidProfile(
                    "An optional source declaration requires one optional source-reference module."
                )
            }
        case .required:
            guard sourceModules.count == 1, sourceModules[0].isRequired else {
                throw ResearchActionProfileContractError.invalidProfile(
                    "A required source declaration requires one required source-reference module."
                )
            }
        }
        if executionKind == .analysis, requirement != .required {
            throw ResearchActionProfileContractError.invalidProfile(
                "Analysis requires one explicit source reference."
            )
        }
    }
}

extension ResearchActionExecutionKind {
    /// Hard public ceiling for direct writes by this Action. Critique and
    /// Discussion may recommend a separately authorized child Action, but
    /// their own Profiles cannot acquire write authority.
    public var maximumCandidateWritableRoles: Set<ResearchActionTargetRole> {
        switch self {
        case .analysis:
            [.analysis]
        case .synthesis:
            [.topic]
        case .writing, .manuscript:
            [.work]
        case .discussion, .critique, .checkFidelity:
            []
        }
    }
}

public enum ResearchActionProfileContractError: LocalizedError, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedField(context: String, field: String)
    case invalidProfile(String)
    case invalidModule(String)
    case invalidCapabilityDeclaration(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "Unsupported Research Action Profile schema version \(version)."
        case .unsupportedField(let context, let field):
            "Unsupported \(context) field: \(field)."
        case .invalidProfile(let reason):
            "Invalid Research Action Profile: \(reason)"
        case .invalidModule(let reason):
            "Invalid Research Action module: \(reason)"
        case .invalidCapabilityDeclaration(let reason):
            "Invalid Research Action capability declaration: \(reason)"
        }
    }
}

private enum ResearchActionProfileValidation {
    static func isIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard (1...64).contains(bytes.count),
              bytes.first != 45,
              bytes.last != 45,
              !value.contains("--") else {
            return false
        }
        return bytes.allSatisfy { byte in
            switch byte {
            case 45, 48...57, 97...122:
                true
            default:
                false
            }
        }
    }

    static func isBoundedSingleLineText(
        _ value: String,
        maximumUTF8ByteCount: Int
    ) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count <= maximumUTF8ByteCount else {
            return false
        }
        return !value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                || CharacterSet.newlines.contains(scalar)
        }
    }

    static func isApplicationOwnedModuleLabel(_ value: String) -> Bool {
        applicationOwnedModuleLabels.contains(normalizedModuleLabel(value))
    }

    static func canonicalRoles(
        _ roles: [ResearchActionTargetRole]
    ) -> [ResearchActionTargetRole]? {
        guard Set(roles).count == roles.count else { return nil }
        let roleSet = Set(roles)
        return ResearchActionTargetRole.allCases.filter(roleSet.contains)
    }

    static func canonicalWriteOperations(
        _ operations: [ResearchActionCandidateWriteOperation]
    ) throws -> [ResearchActionCandidateWriteOperation] {
        guard Set(operations).count == operations.count else {
            throw ResearchActionProfileContractError.invalidCapabilityDeclaration(
                "Candidate write operations must be unique."
            )
        }
        let operationSet = Set(operations)
        return ResearchActionCandidateWriteOperation.allCases.filter(operationSet.contains)
    }

    static func rejectUnknownFields(
        in decoder: Decoder,
        context: String,
        allowed: some Sequence<String>
    ) throws {
        let rawContainer = try decoder.container(keyedBy: ResearchActionProfileAnyCodingKey.self)
        let allowed = Set(allowed)
        if let unknown = rawContainer.allKeys.map(\.stringValue).sorted()
            .first(where: { !allowed.contains($0) }) {
            throw ResearchActionProfileContractError.unsupportedField(
                context: context,
                field: unknown
            )
        }
    }

    private static let applicationOwnedModuleLabels = Set([
        "authority",
        "authorization",
        "cancellation",
        "checkpoint",
        "comparison",
        "completion",
        "conflict",
        "consequential scope",
        "current revision",
        "current target",
        "identity",
        "permission",
        "permissions",
        "preparation",
        "recovery",
        "revision",
        "source access",
        "stable identity",
        "status",
        "target",
        "target revision",
        "write scope",
    ])

    private static func normalizedModuleLabel(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.split { character in
            character.isWhitespace
                || character == "-"
                || character == "_"
                || character == ":"
        }.joined(separator: " ")
    }
}

private struct ResearchActionProfileAnyCodingKey: CodingKey {
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
