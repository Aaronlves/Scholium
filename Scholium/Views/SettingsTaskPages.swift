import SwiftUI

/// A query remembers the browsing segment; only an explicit result can reveal
/// another segment. Clearing the query restores the browsing selection.
struct SettingsSearchNavigation<Category: Equatable> {
    var category: Category
    private(set) var categoryBeforeSearch: Category?

    var isSearching: Bool { categoryBeforeSearch != nil }

    mutating func updateQuery(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let categoryBeforeSearch { category = categoryBeforeSearch }
            categoryBeforeSearch = nil
            return
        }
        if categoryBeforeSearch == nil { categoryBeforeSearch = category }
    }

    mutating func reveal(_ resultCategory: Category) {
        guard isSearching else { return }
        category = resultCategory
    }
}

struct WritingSettingsView: View {
    @StateObject private var selectionActions = SelectionActionsSettingsDraft()

    var body: some View {
        Form {
            WritingAssistanceModelSettingsContent()
            WritingContinuationSettingsContent()
            SelectionActionsSettingsContent(state: selectionActions)
        }
        .scholiumSettingsFormStyle()
        .scholiumSettingsSearchDestination()
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.writing")
    }
}

struct ZoteroSettingsPageView: View {
    @Environment(\.agentChatSettingsController) private var controller

    var body: some View {
        Form {
            ZoteroSettingsView().id(SettingsSection.zoteroDesktop)
            if let controller {
                AgentZoteroCapabilitySettingsView(controller: controller, capabilities: controller.capabilities)
                    .id(controller.triptychID)
                    .id(SettingsSection.zoteroChat)
            } else {
                Section("Zotero in Chat") {
                    Text("Open a Triptych to configure Zotero in Chat.")
                        .foregroundStyle(.secondary)
                }.id(SettingsSection.zoteroChat)
            }
        }
        .scholiumSettingsFormStyle()
        .scholiumSettingsSearchDestination()
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.zotero")
    }
}

func localizedInterfaceString(_ keyAndValue: String.LocalizationValue) -> String {
    ScholiumL10n.string(keyAndValue)
}

/// An explicit navigation request is distinct from remembering a browsing pane.
/// The revision makes repeated links work even when the remembered pane is equal.
@MainActor
enum SettingsNavigationRequest {
    static let requestedSectionKey = "scholium.settings.requestedSection"

    static func select(
        _ pane: ScholiumSettingsDestination, defaults: UserDefaults = .standard
    ) {
        request(pane, section: nil, defaults: defaults)
    }

    static func reveal(_ section: SettingsSection, defaults: UserDefaults = .standard) {
        request(section.destination, section: section, defaults: defaults)
    }

    private static func request(
        _ pane: ScholiumSettingsDestination, section: SettingsSection?, defaults: UserDefaults
    ) {
        if let agentCategory = section?.agentCategory {
            defaults.set(agentCategory.rawValue, forKey: "scholium.settings.agentCategory")
        }
        if let section {
            defaults.set(section.id, forKey: requestedSectionKey)
        } else {
            defaults.removeObject(forKey: requestedSectionKey)
        }
        defaults.set(pane.rawValue, forKey: "scholium.settings.selectedPane")
        defaults.set(UUID().uuidString, forKey: "scholium.settings.navigationRevision")
    }

    /// A requested section is a one-shot route, never retained browsing state.
    static func takeRequestedSection(
        for pane: ScholiumSettingsDestination, defaults: UserDefaults = .standard
    ) -> SettingsSection? {
        let sectionID = defaults.string(forKey: requestedSectionKey)
        defaults.removeObject(forKey: requestedSectionKey)
        return SettingsSearchTarget.all.first { $0.section.id == sectionID && $0.destination == pane }?.section
    }
}
