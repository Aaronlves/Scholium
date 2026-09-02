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
    ) -> VaultAboutConfiguration {
        guard isAuthoritative else {
            return VaultAboutConfiguration(visibleFields: [])
        }
        return settings.about[slot]
            ?? TriptychSettings.defaultAbout[slot]
            ?? VaultAboutConfiguration()
    }
}

enum MetadataSettingsCandidateBuilder {
    static func build(
        from base: TriptychSettings,
        metadataFields: [WorkspaceVaultSlot: [MetadataFieldDefinition]],
        aboutConfigurations: [WorkspaceVaultSlot: VaultAboutConfiguration]
    ) -> TriptychSettings {
        var settings = base
        settings.metadataFields = metadataFields
        let catalog = NoteMetadataCatalog(settings: settings)
        var candidates = aboutConfigurations
        for slot in WorkspaceVaultSlot.allCases {
            var configuration = candidates[slot]
                ?? TriptychSettings.defaultAbout[slot]
                ?? VaultAboutConfiguration()
            let profile: SchemaProfileID = switch slot {
            case .paperAnalysis: .analysis
            case .topicKnowledge: .topicMarkdown
            case .output: .draftProject
            }
            configuration.visibleFields.removeAll {
                !AboutProfileCatalog.allowsOptionalField(
                    $0,
                    profile: profile,
                    catalog: catalog
                )
            }
            configuration.visibleFields = AboutProfileCatalog.groupedEntries(
                for: profile,
                visibleFields: configuration.visibleFields,
                catalog: catalog
            ).flatMap(\.keys).filter {
                AboutProfileCatalog.allowsOptionalField(
                    $0,
                    profile: profile,
                    catalog: catalog
                )
            }
            candidates[slot] = configuration
        }
        settings.about = candidates
        return settings
    }
}

/// About selection and group-major reading order. The presentation catalog is
/// the only field-membership owner; this type only applies the saved profile.
enum AboutProfileCatalog {
    static func groupedEntries(
        for profile: SchemaProfileID,
        visibleFields: [String]?,
        presentManagedFields: Set<String> = [],
        catalog: NoteMetadataCatalog
    ) -> [AboutProfileGroup] {
        let alwaysShownFields = (visibleFields ?? defaultVisibleFields(for: profile)).filter {
            allowsOptionalField($0, profile: profile, catalog: catalog)
        }
        let configured = Set(alwaysShownFields)
        let additionalPresentFields = PropertyPresentationCatalog.managedPresentations(
            for: profile,
            catalog: catalog
        ).map(\.key).filter {
            presentManagedFields.contains($0)
                && !configured.contains($0)
                && allowsPresentField($0, profile: profile, catalog: catalog)
        }
        let managedFields = alwaysShownFields + additionalPresentFields
        let fields = managedFields + fixedAuthoredFields(for: profile)
        let grouped = Dictionary(grouping: fields) { key in
            PropertyPresentationCatalog.presentation(
                for: key,
                in: profile,
                catalog: catalog
            )?.group ?? .customMetadata
        }
        return PropertyPresentationCatalog.orderedGroups(for: profile).compactMap { group in
            guard let keys = grouped[group], !keys.isEmpty else { return nil }
            return AboutProfileGroup(group: group, keys: keys)
        }.sorted { $0.group.order < $1.group.order }
    }

    static func allowsOptionalField(
        _ key: String,
        profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> Bool {
        guard key != "title",
              PropertyPresentationCatalog.presentation(
                for: key,
                in: profile,
                catalog: catalog
              ) != nil else {
            return false
        }
        return catalog.activeContracts(for: profile).contains {
            $0.canonicalKey == key
        }
    }

    /// Present archived values remain researcher-visible even though they can
    /// no longer be selected as an empty always-shown field.
    static func allowsPresentField(
        _ key: String,
        profile: SchemaProfileID,
        catalog: NoteMetadataCatalog
    ) -> Bool {
        guard key != "title",
              PropertyPresentationCatalog.presentation(
                for: key,
                in: profile,
                catalog: catalog
              ) != nil else {
            return false
        }
        return catalog.contract(for: key, profile: profile) != nil
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
        return slot.flatMap { TriptychSettings.defaultAbout[$0]?.visibleFields } ?? []
    }
}
