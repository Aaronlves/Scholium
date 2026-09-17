import SwiftUI

/// Search temporarily reveals a child category without replacing the user's
/// browsing selection. The owning view persists only explicit browsing choices.
struct SettingsSearchNavigation<Category: Equatable> {
    var category: Category
    private(set) var categoryBeforeSearch: Category?

    var isSearching: Bool { categoryBeforeSearch != nil }

    mutating func updateSearch(query: String, matching categoryMatch: Category?) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if let categoryBeforeSearch { category = categoryBeforeSearch }
            categoryBeforeSearch = nil
            return
        }
        if categoryBeforeSearch == nil { categoryBeforeSearch = category }
        if let categoryMatch { category = categoryMatch }
    }
}

struct WritingSettingsView: View {
    @StateObject private var selectionActions = SelectionActionsSettingsDraft()

    var body: some View {
        Form {
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
            ZoteroSettingsView().id("zotero.desktop")
            if let controller {
                AgentZoteroToolSettingsView(controller: controller, capabilities: controller.capabilities)
                    .id(controller.triptychID)
                    .id("zotero.chat")
            } else {
                Section("Zotero in Chat") {
                    Text("Open a Triptych to configure Zotero in Chat.")
                        .foregroundStyle(.secondary)
                }.id("zotero.chat")
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
    static func select(_ pane: WorkspaceSettingsPane, agentCategory: AgentSettingsCategory? = nil) {
        if let agentCategory {
            UserDefaults.standard.set(agentCategory.rawValue, forKey: "scholium.settings.agentCategory")
        }
        UserDefaults.standard.set(pane.rawValue, forKey: "scholium.settings.selectedPane")
        UserDefaults.standard.set(UUID().uuidString, forKey: "scholium.settings.navigationRevision")
    }
}
