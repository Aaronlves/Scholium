import Foundation

public enum TriptychSeedValidationReason: Equatable, Sendable {
    case sourceNormalization
    case patchRefusal(FrontmatterPatchRefusal)
    case topLevelMappingRequired
    case propertyIssue(PropertyValidationIssue.Code)

    var description: String {
        switch self {
        case .sourceNormalization:
            "configuration newlines or the final newline are not normalized"
        case .patchRefusal(let refusal):
            refusal.localizedDescription
        case .topLevelMappingRequired:
            "the seed must contain at least one top-level mapping entry"
        case .propertyIssue(let code):
            "a canonical field has an invalid \(code.rawValue) value"
        }
    }
}

public enum TriptychSettingsValidationError: LocalizedError, Equatable, Sendable {
    case incompleteRoleConfiguration
    case noncanonicalConfigurationField(WorkspaceVaultSlot, String)
    case seedTooLarge(WorkspaceVaultSlot, Int)
    case invalidSeed(
        WorkspaceVaultSlot,
        key: String?,
        reason: TriptychSeedValidationReason,
        position: FrontmatterSourcePosition?
    )
    case reservedSeedKey(WorkspaceVaultSlot, String)
    case unsupportedSeedKey(WorkspaceVaultSlot, String)
    case invalidRequiredField(AnalysisSourceType, String)
    case requiredFieldNotApplicable(AnalysisSourceType, String)
    case invalidAttentionDismissalDays

    public var errorDescription: String? {
        switch self {
        case .incompleteRoleConfiguration:
            "Metadata Profile settings must contain exactly the Analysis, Topic, and Work roles."
        case .noncanonicalConfigurationField(let role, let field):
            "The \(role.rawValue) Metadata Profile contains a blank, duplicate, or unnormalized field: \(field)."
        case .seedTooLarge(let role, let count):
            "The \(role.rawValue) New Note YAML is \(count) bytes; the maximum is \(TriptychSettingsValidator.maximumSeedUTF8Bytes)."
        case .invalidSeed(let role, _, let reason, _):
            "The \(role.rawValue) New Note YAML is invalid: \(reason.description)"
        case .reservedSeedKey(let role, let key):
            "The \(role.rawValue) New Note YAML cannot contain the reserved key \(key)."
        case .unsupportedSeedKey(let role, let key):
            "The \(role.rawValue) New Note YAML may contain only summary and keywords; \(key) is not allowed."
        case .invalidRequiredField(let type, let key):
            "\(key) is not a shape-known Agent-creatable field for \(type.rawValue)."
        case .requiredFieldNotApplicable(let type, let key):
            "\(key) does not apply to \(type.rawValue)."
        case .invalidAttentionDismissalDays:
            "Attention dismissal days must be positive."
        }
    }
}

/// The sole semantic compiler gate for portable settings. Loading, saving,
/// managed creation, and Settings UI validation must all use this contract.
public enum TriptychSettingsValidator {
    public static let maximumSeedUTF8Bytes = 64 * 1024

    private static let reservedMachineKeys: Set<String> = [
        "note_id", "paper_id", "topic_id", "output_id", "zotero_item_key",
        "created_at", "updated_at", "fingerprint", "provenance",
    ]

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
            _ = try validateSeed(configuration.newNoteYAML, role: role)
        }

        for sourceType in AnalysisSourceType.allCases {
            let required = settings.analysisAgentCreation.requiredFields(for: sourceType)
            try validateRequiredFields(
                required,
                sourceType: sourceType
            )
        }
    }

    public static func seedKeys(
        in source: String?,
        role: WorkspaceVaultSlot
    ) throws -> Set<String> {
        try validateSeed(source, role: role)
    }

    private static func validateConfiguredFields(
        _ fields: [String],
        role: WorkspaceVaultSlot
    ) throws {
        var seen: Set<String> = []
        let profile = profile(for: role)
        let supported = Set(
            PropertyContractCatalog.contracts(for: profile).map(\.canonicalKey)
                + NoteMetadataContractCatalog.contracts(for: profile).map(\.canonicalKey)
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

    private static func validateSeed(
        _ source: String?,
        role: WorkspaceVaultSlot
    ) throws -> Set<String> {
        guard let source else { return [] }
        let byteCount = source.utf8.count
        guard byteCount <= maximumSeedUTF8Bytes else {
            throw TriptychSettingsValidationError.seedTooLarge(role, byteCount)
        }
        guard source == normalizedSeed(source) else {
            throw TriptychSettingsValidationError.invalidSeed(
                role,
                key: nil,
                reason: .sourceNormalization,
                position: nil
            )
        }
        do {
            _ = try FrontmatterPatchPlanner.plan(
                frontmatter: source,
                edits: [:],
                newline: "\n"
            )
        } catch let refusal as FrontmatterPatchRefusal {
            throw TriptychSettingsValidationError.invalidSeed(
                role,
                key: nil,
                reason: .patchRefusal(refusal),
                position: refusal.sourcePosition
            )
        } catch {
            throw TriptychSettingsValidationError.invalidSeed(
                role,
                key: nil,
                reason: .patchRefusal(.invalidYAML(error.localizedDescription)),
                position: nil
            )
        }

        let document = NoteDocument(
            relativePath: "Settings Seed.md",
            rawContent: "---\n\(source)---\n"
        )
        guard document.validationWarnings.isEmpty,
              document.rawFrontmatter != nil,
              !document.parsedFrontmatter.isEmpty else {
            throw TriptychSettingsValidationError.invalidSeed(
                role,
                key: nil,
                reason: .topLevelMappingRequired,
                position: FrontmatterSourcePosition(line: 1, column: 1)
            )
        }
        let keys = Set(document.parsedFrontmatter.keys)
        let roleReserved: Set<String> = role == .paperAnalysis
            ? reservedMachineKeys.union(["title", "type"])
            : reservedMachineKeys.union(["title"])
        if let reserved = keys.intersection(roleReserved).sorted().first {
            throw TriptychSettingsValidationError.reservedSeedKey(role, reserved)
        }

        let profile = profile(for: role)
        for (key, value) in document.parsedFrontmatter {
            guard PropertyContractCatalog.contract(for: key, profile: profile) != nil else {
                throw TriptychSettingsValidationError.unsupportedSeedKey(role, key)
            }
            guard !isExplicitEmpty(value) else { continue }
            if let issue = PropertyContractCatalog.validate(
                frontmatter: [key: value],
                profile: profile
            ).first {
                throw TriptychSettingsValidationError.invalidSeed(
                    role,
                    key: issue.propertyKey,
                    reason: .propertyIssue(issue.code),
                    position: nil
                )
            }
        }
        return keys
    }

    private static func validateRequiredFields(
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
                throw TriptychSettingsValidationError.invalidRequiredField(sourceType, key)
            }
            guard applicable.contains(key) else {
                throw TriptychSettingsValidationError.requiredFieldNotApplicable(sourceType, key)
            }
        }
    }

    private static func normalizedSeed(_ source: String) -> String {
        var source = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if !source.isEmpty, !source.hasSuffix("\n") { source += "\n" }
        return source
    }

    private static func profile(for role: WorkspaceVaultSlot) -> SchemaProfileID {
        switch role {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
    }

    private static func isExplicitEmpty(_ value: YAMLValue) -> Bool {
        switch value {
        case .string(let value): value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let values): values.isEmpty
        case .object(let values): values.isEmpty
        case .null: true
        case .integer, .double, .boolean: false
        }
    }
}
