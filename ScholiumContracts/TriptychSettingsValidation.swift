import Foundation

public enum TriptychSettingsValidationError: LocalizedError, Equatable, Sendable {
    case incompleteRoleConfiguration
    case invalidMetadataFieldDefinition(WorkspaceVaultSlot, String)
    case metadataFieldShadowsReservedKey(WorkspaceVaultSlot, String)
    case metadataFieldKindUnsupported(WorkspaceVaultSlot, String, PropertyValueKind)
    case invalidMetadataFieldLabel(WorkspaceVaultSlot, String)
    case invalidMetadataFieldDescription(WorkspaceVaultSlot, String)
    case invalidMetadataFieldChoices(WorkspaceVaultSlot, String)
    case metadataFieldIdentityChanged(WorkspaceVaultSlot, String)
    case metadataFieldChoicesRemoved(WorkspaceVaultSlot, String)
    case noncanonicalConfigurationField(WorkspaceVaultSlot, String)
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
        case .invalidMetadataFieldLabel(let role, let field):
            "The \(role.rawValue) Metadata definition \(field) has an invalid label."
        case .invalidMetadataFieldDescription(let role, let field):
            "The \(role.rawValue) Metadata definition \(field) has an invalid description."
        case .invalidMetadataFieldChoices(let role, let field):
            "The \(role.rawValue) Metadata definition \(field) has invalid controlled choices."
        case .metadataFieldIdentityChanged(let role, let field):
            "The stable key or value kind of \(role.rawValue) Metadata definition \(field) changed or the definition was removed."
        case .metadataFieldChoicesRemoved(let role, let field):
            "Existing controlled choices for \(role.rawValue) Metadata definition \(field) cannot be removed."
        case .noncanonicalConfigurationField(let role, let field):
            "The \(role.rawValue) Metadata Profile contains a blank, duplicate, or unnormalized field: \(field)."
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
                guard isValidLabel(definition.label) else {
                    throw TriptychSettingsValidationError.invalidMetadataFieldLabel(
                        role,
                        definition.key
                    )
                }
                if let description = definition.description,
                   !isValidDescription(description) {
                    throw TriptychSettingsValidationError.invalidMetadataFieldDescription(
                        role,
                        definition.key
                    )
                }
                if definition.valueKind == .choice {
                    guard let choices = definition.allowedValues,
                          isValidChoices(choices) else {
                        throw TriptychSettingsValidationError.invalidMetadataFieldChoices(
                            role,
                            definition.key
                        )
                    }
                } else if definition.allowedValues != nil {
                    throw TriptychSettingsValidationError.invalidMetadataFieldChoices(
                        role,
                        definition.key
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
            for prior in existing {
                guard let next = proposed.first(where: { $0.key == prior.key }),
                      next.valueKind == prior.valueKind else {
                    throw TriptychSettingsValidationError.metadataFieldIdentityChanged(
                        role,
                        prior.key
                    )
                }
                if prior.valueKind == .choice {
                    let oldChoices = prior.allowedValues ?? []
                    let newChoices = Set(next.allowedValues ?? [])
                    guard oldChoices.allSatisfy(newChoices.contains) else {
                        throw TriptychSettingsValidationError.metadataFieldChoicesRemoved(
                            role,
                            prior.key
                        )
                    }
                }
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
        let supported = Set(catalog.activeContracts(for: profile).map(\.canonicalKey))
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

    private static func isValidLabel(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label == trimmed
            && !trimmed.isEmpty
            && trimmed.utf8.count <= 80
            && !trimmed.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }

    private static func isValidDescription(_ description: String) -> Bool {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return description == trimmed
            && !trimmed.isEmpty
            && trimmed.utf8.count <= 240
            && !trimmed.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\r"
            }
    }

    private static func isValidChoices(_ choices: [String]) -> Bool {
        guard !choices.isEmpty, choices.count <= 64 else { return false }
        var seen: Set<String> = []
        return choices.allSatisfy { choice in
            let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
            return choice == trimmed
                && !trimmed.isEmpty
                && trimmed.utf8.count <= 128
                && seen.insert(trimmed).inserted
                && !trimmed.unicodeScalars.contains {
                    CharacterSet.controlCharacters.contains($0)
                }
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
