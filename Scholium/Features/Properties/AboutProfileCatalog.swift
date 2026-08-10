import ScholiumContracts

struct AboutProfileGroup: Hashable {
    let group: PropertyPresentationGroup
    let keys: [String]
}

/// About selection and group-major reading order. The presentation catalog is
/// the only field-membership owner; this type only applies the saved profile.
enum AboutProfileCatalog {
    static func groupedEntries(
        for profile: SchemaProfileID,
        visibleFields: [String]?
    ) -> [AboutProfileGroup] {
        let fields = (visibleFields ?? defaultVisibleFields(for: profile)).filter {
            allowsOptionalField($0, profile: profile)
        }
        let grouped = Dictionary(grouping: fields) { key in
            PropertyPresentationCatalog.presentation(for: key, in: profile)?.group ?? .other
        }
        return PropertyPresentationGroup.allCases.compactMap { group in
            guard let keys = grouped[group], !keys.isEmpty else { return nil }
            return AboutProfileGroup(group: group, keys: keys)
        }.sorted { $0.group.order < $1.group.order }
    }

    static func allowsOptionalField(_ key: String, profile: SchemaProfileID) -> Bool {
        guard !ResearcherPropertyPolicy.isHidden(key) else { return false }
        return !(profile == .analysis && key == "title")
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
