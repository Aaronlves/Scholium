import ScholiumContracts

struct AboutProfileGroup: Hashable {
    let group: PropertyPresentationGroup
    let keys: [String]
}

enum WorkspaceAboutConfiguration {
    static func configuration(
        settings: TriptychSettings,
        slot: WorkspaceVaultSlot,
        isAuthoritative: Bool
    ) -> VaultPropertiesConfiguration {
        guard isAuthoritative else {
            return VaultPropertiesConfiguration(visibleFields: [])
        }
        return settings.properties[slot]
            ?? TriptychSettings.defaultProperties[slot]
            ?? VaultPropertiesConfiguration()
    }
}

enum PropertiesSettingsCandidateBuilder {
    static func build(
        from base: TriptychSettings,
        configurations: [WorkspaceVaultSlot: VaultPropertiesConfiguration],
        agentCreation: AnalysisAgentCreationConfiguration
    ) -> TriptychSettings {
        var settings = base
        var candidates = configurations
        for slot in WorkspaceVaultSlot.allCases {
            var configuration = candidates[slot]
                ?? TriptychSettings.defaultProperties[slot]
                ?? VaultPropertiesConfiguration()
            let profile: SchemaProfileID = switch slot {
            case .paperAnalysis: .analysis
            case .topicKnowledge: .topicMarkdown
            case .output: .draftProject
            }
            configuration.visibleFields.removeAll {
                !AboutProfileCatalog.allowsOptionalField($0, profile: profile)
            }
            configuration.visibleFields = AboutProfileCatalog.groupedEntries(
                for: profile,
                visibleFields: configuration.visibleFields
            ).flatMap(\.keys).filter {
                AboutProfileCatalog.allowsOptionalField($0, profile: profile)
            }
            candidates[slot] = configuration
        }
        settings.properties = candidates
        settings.analysisAgentCreation = agentCreation
        return settings
    }
}

/// About selection and group-major reading order. The presentation catalog is
/// the only field-membership owner; this type only applies the saved profile.
enum AboutProfileCatalog {
    static func groupedEntries(
        for profile: SchemaProfileID,
        visibleFields: [String]?
    ) -> [AboutProfileGroup] {
        let managedFields = (visibleFields ?? defaultVisibleFields(for: profile)).filter {
            allowsOptionalField($0, profile: profile)
        }
        let fields = managedFields + fixedAuthoredFields(for: profile)
        let grouped = Dictionary(grouping: fields) { key in
            PropertyPresentationCatalog.presentation(for: key, in: profile)?.group ?? .other
        }
        return PropertyPresentationCatalog.orderedGroups(for: profile).compactMap { group in
            guard let keys = grouped[group], !keys.isEmpty else { return nil }
            return AboutProfileGroup(group: group, keys: keys)
        }.sorted { $0.group.order < $1.group.order }
    }

    static func allowsOptionalField(_ key: String, profile: SchemaProfileID) -> Bool {
        guard key != "title",
              PropertyPresentationCatalog.presentation(for: key, in: profile) != nil else {
            return false
        }
        return NoteMetadataContractCatalog.contract(for: key, profile: profile) != nil
    }

    private static func fixedAuthoredFields(for profile: SchemaProfileID) -> [String] {
        PropertyContractCatalog.contracts(for: profile).map(\.canonicalKey)
    }

    private static func defaultVisibleFields(for profile: SchemaProfileID) -> [String] {
        let slot: WorkspaceVaultSlot? = switch profile {
        case .analysis: .paperAnalysis
        case .topicMarkdown: .topicKnowledge
        case .draftProject: .output
        case .genericMarkdown: nil
        }
        return slot.flatMap { TriptychSettings.defaultProperties[$0]?.visibleFields } ?? []
    }
}
