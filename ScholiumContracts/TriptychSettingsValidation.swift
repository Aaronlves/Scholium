import Foundation

public enum TriptychSettingsValidationError: LocalizedError, Equatable, Sendable {
    case incompleteRoleConfiguration
    case invalidMetadataFieldDefinition(WorkspaceVaultSlot, String)
    case metadataFieldShadowsReservedKey(WorkspaceVaultSlot, String)
    case metadataFieldKindUnsupported(WorkspaceVaultSlot, String, PropertyValueKind)
    case metadataFieldDefinitionsAreAppendOnly(WorkspaceVaultSlot)
    case noncanonicalConfigurationField(WorkspaceVaultSlot, String)
    case invalidPreferredField(AnalysisSourceType, String)
    case preferredFieldNotApplicable(AnalysisSourceType, String)
    case invalidAttentionDismissalDays

    public var errorDescription: String? {
        switch self {
        case .incompleteRoleConfiguration:
            "Metadata settings must contain exactly the Analysis, Topic, and Work roles."
        case .invalidMetadataFieldDefinition(let role, let field):
            "The \(role.rawValue) Metadata definition has an invalid or duplicate key: \(field)."
        case .metadataFieldShadowsReservedKey(let role, let field):
            "The \(role.rawValue) Metadata definition shadows an existing managed or authored YAML key: \(field)."
        case .metadataFieldKindUnsupported(let role, let field, let kind):
            "The \(role.rawValue) Metadata definition \(field) uses unsupported custom value kind \(kind.rawValue)."
        case .metadataFieldDefinitionsAreAppendOnly(let role):
            "The \(role.rawValue) Metadata definitions can only be appended; existing definitions cannot be renamed, reordered, or removed."
        case .noncanonicalConfigurationField(let role, let field):
            "The \(role.rawValue) Metadata Profile contains a blank, duplicate, or unnormalized field: \(field)."
        case .invalidPreferredField(let type, let key):
            "\(key) is not a shape-known Agent-creatable field for \(type.rawValue)."
        case .preferredFieldNotApplicable(let type, let key):
            "\(key) does not apply to \(type.rawValue)."
        case .invalidAttentionDismissalDays:
            "Attention dismissal days must be positive."
        }
    }
}

/// The sole semantic compiler gate for portable settings. Loading, saving,
/// managed creation, and Settings UI validation must all use this contract.
public enum TriptychSettingsValidator {
    public static func validate(_ settings: TriptychSettings) throws {
        guard Set(settings.metadataFields.keys) == Set(WorkspaceVaultSlot.allCases),
              Set(settings.about.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw TriptychSettingsValidationError.incompleteRoleConfiguration
        }
        guard settings.attentionDismissalDays > 0 else {
            throw TriptychSettingsValidationError.invalidAttentionDismissalDays
        }

        try validateMetadataFieldDefinitions(settings.metadataFields)
        let catalog = NoteMetadataCatalog(settings: settings)
        for role in WorkspaceVaultSlot.allCases {
            let configuration = settings.about[role]!
            try validateConfiguredFields(
                configuration.visibleFields,
                role: role,
                catalog: catalog
            )
        }

        for sourceType in AnalysisSourceType.allCases {
            let preferred = settings.analysisAgentCreation.preferredFields(for: sourceType)
            try validatePreferredFields(
                preferred,
                sourceType: sourceType,
                catalog: catalog
            )
        }
    }

    public static func validateMetadataFieldDefinitions(
        _ definitionsByRole: [WorkspaceVaultSlot: [MetadataFieldDefinition]]
    ) throws {
        guard Set(definitionsByRole.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw TriptychSettingsValidationError.incompleteRoleConfiguration
        }
        let authoredKeys = Set(PropertyContractCatalog.authoredCanonicalKeys)
        for role in WorkspaceVaultSlot.allCases {
            let profile = NoteMetadataCatalog.profile(for: role)
            let builtInKeys = Set(
                BuiltInNoteMetadataCatalog.contracts(for: profile).map(\.canonicalKey)
            )
            var seen: Set<String> = []
            for definition in definitionsByRole[role] ?? [] {
                guard isCanonicalCustomKey(definition.key),
                      seen.insert(definition.key).inserted else {
                    throw TriptychSettingsValidationError.invalidMetadataFieldDefinition(
                        role,
                        definition.key
                    )
                }
                guard !authoredKeys.contains(definition.key),
                      !builtInKeys.contains(definition.key) else {
                    throw TriptychSettingsValidationError.metadataFieldShadowsReservedKey(
                        role,
                        definition.key
                    )
                }
                guard MetadataFieldDefinition.supportedValueKinds.contains(
                    definition.valueKind
                ) else {
                    throw TriptychSettingsValidationError.metadataFieldKindUnsupported(
                        role,
                        definition.key,
                        definition.valueKind
                    )
                }
            }
        }
    }

    public static func validateTransition(
        from current: TriptychSettings,
        to candidate: TriptychSettings
    ) throws {
        for role in WorkspaceVaultSlot.allCases {
            let existing = current.metadataFields[role] ?? []
            let proposed = candidate.metadataFields[role] ?? []
            guard proposed.starts(with: existing) else {
                throw TriptychSettingsValidationError.metadataFieldDefinitionsAreAppendOnly(role)
            }
        }
    }

    private static func validateConfiguredFields(
        _ fields: [String],
        role: WorkspaceVaultSlot,
        catalog: NoteMetadataCatalog
    ) throws {
        var seen: Set<String> = []
        let profile = profile(for: role)
        let supported = Set(catalog.contracts(for: profile).map(\.canonicalKey))
        for field in fields {
            let normalized = field.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty,
                  normalized == field,
                  seen.insert(field).inserted,
                  supported.contains(field) else {
                throw TriptychSettingsValidationError.noncanonicalConfigurationField(
                    role,
                    field
                )
            }
        }
    }

    private static func validatePreferredFields(
        _ fields: [String],
        sourceType: AnalysisSourceType,
        catalog: NoteMetadataCatalog
    ) throws {
        var seen: Set<String> = []
        let applicable = Set(
            catalog.analysisContracts(for: sourceType).map(\.canonicalKey)
        )
        for key in fields {
            let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized == key,
                  !key.isEmpty,
                  key != "type",
                  seen.insert(key).inserted,
                  catalog.contract(for: key, profile: .analysis) != nil else {
                throw TriptychSettingsValidationError.invalidPreferredField(sourceType, key)
            }
            guard applicable.contains(key) else {
                throw TriptychSettingsValidationError.preferredFieldNotApplicable(sourceType, key)
            }
        }
    }

    private static func isCanonicalCustomKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.utf8.count <= 64,
              let first = key.unicodeScalars.first,
              (97...122).contains(first.value) else { return false }
        return key.unicodeScalars.dropFirst().allSatisfy { scalar in
            (97...122).contains(scalar.value)
                || (48...57).contains(scalar.value)
                || scalar.value == 95
        }
    }

    private static func profile(for role: WorkspaceVaultSlot) -> SchemaProfileID {
        switch role {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
    }
}
