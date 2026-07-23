import ScholiumContracts

enum AboutProfileEntry: Hashable {
    case completion
    case scope(label: String)
    case limitations
    case property(String)
    case sourceBasis
}

/// Default About fields are a presentation profile, not the canonical
/// property vocabulary and not a creation checklist.
enum AboutProfileCatalog {
    private static let analysisSourceBasisKeys: Set<String> = [
        "access", "text_reliability", "locators",
    ]

    static func entries(
        for profile: SchemaProfileID,
        visibleFields: [String]?
    ) -> [AboutProfileEntry] {
        var result: [AboutProfileEntry] = switch profile {
        case .analysis: [.completion, .limitations]
        case .topicMarkdown: [.scope(label: "Scope"), .limitations]
        case .draftProject: [.scope(label: "Research Scope"), .limitations]
        case .genericMarkdown: []
        }

        let fields = visibleFields ?? defaultVisibleFields(for: profile)
        var insertedSourceBasis = false
        for key in fields where allowsOptionalField(key, profile: profile) {
            if profile == .analysis, analysisSourceBasisKeys.contains(key) {
                guard !insertedSourceBasis else { continue }
                result.append(.sourceBasis)
                insertedSourceBasis = true
            } else {
                result.append(.property(key))
            }
        }
        return result
    }

    static func allowsOptionalField(_ key: String, profile: SchemaProfileID) -> Bool {
        guard !ResearcherPropertyPolicy.isHidden(key) else { return false }
        if ["research_unit", "tags", "scope", "limitations", "completion"].contains(key) {
            return false
        }
        if profile == .analysis, ["title", "zotero_item_key"].contains(key) {
            return false
        }
        return true
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
