import Foundation

public enum TriptychSettingsValidationError: LocalizedError, Equatable, Sendable {
    case incompleteRoleConfiguration
    case noncanonicalConfigurationField(WorkspaceVaultSlot, String)
    case invalidPreferredField(AnalysisSourceType, String)
    case preferredFieldNotApplicable(AnalysisSourceType, String)
    case invalidAttentionDismissalDays

    public var errorDescription: String? {
        switch self {
        case .incompleteRoleConfiguration:
            "Metadata Profile settings must contain exactly the Analysis, Topic, and Work roles."
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
        guard Set(settings.properties.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw TriptychSettingsValidationError.incompleteRoleConfiguration
        }
        guard settings.attentionDismissalDays > 0 else {
            throw TriptychSettingsValidationError.invalidAttentionDismissalDays
        }

        for role in WorkspaceVaultSlot.allCases {
            let configuration = settings.properties[role]!
            try validateConfiguredFields(configuration.visibleFields, role: role)
        }

        for sourceType in AnalysisSourceType.allCases {
            let preferred = settings.analysisAgentCreation.preferredFields(for: sourceType)
            try validatePreferredFields(
                preferred,
                sourceType: sourceType
            )
        }
    }

    private static func validateConfiguredFields(
        _ fields: [String],
        role: WorkspaceVaultSlot
    ) throws {
        var seen: Set<String> = []
        let profile = profile(for: role)
        let supported = Set(
            NoteMetadataContractCatalog.contracts(for: profile).map(\.canonicalKey)
        )
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
        sourceType: AnalysisSourceType
    ) throws {
        var seen: Set<String> = []
        let applicable = Set(
            AnalysisSourceTypeProfileCatalog.profile(for: sourceType).applicableFields
        )
        for key in fields {
            let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized == key,
                  !key.isEmpty,
                  key != "type",
                  seen.insert(key).inserted,
                  NoteMetadataContractCatalog.contract(for: key, profile: .analysis) != nil else {
                throw TriptychSettingsValidationError.invalidPreferredField(sourceType, key)
            }
            guard applicable.contains(key) else {
                throw TriptychSettingsValidationError.preferredFieldNotApplicable(sourceType, key)
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
