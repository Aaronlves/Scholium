import SwiftUI

/// The two related, machine-local interaction settings share one top-level
/// preference page. Their underlying owners remain separate.
enum SettingsInteractionCategory: String, CaseIterable, Identifiable {
    case keyboardShortcuts = "keyboard-shortcuts"
    case selectionActions = "selection-actions"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .keyboardShortcuts:
            LocalizedStringResource("Keyboard Shortcuts", table: "Localizable", bundle: .module)
        case .selectionActions:
            LocalizedStringResource("Selection Actions", table: "Localizable", bundle: .module)
        }
    }
}

/// Integrations are related at the Settings level, but each child keeps its
/// own connection and persistence boundary. The category picker is navigation,
/// not a second copy of either integration's state.
enum SettingsIntegrationCategory: String, CaseIterable, Identifiable {
    case agents = "agents"
    case zotero = "zotero"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .agents:
            LocalizedStringResource("Agents & Chat", table: "Localizable", bundle: .module)
        case .zotero:
            LocalizedStringResource("Zotero", table: "Localizable", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .agents: "point.3.connected.trianglepath.dotted"
        case .zotero: "books.vertical"
        }
    }
}

struct SettingsInteractionView: View {
    let searchQuery: String

    @AppStorage("scholium.settings.interactionCategory")
    private var persistedCategory = SettingsInteractionCategory.keyboardShortcuts.rawValue
    @State private var category = SettingsInteractionCategory.keyboardShortcuts

    var body: some View {
        VStack(spacing: 0) {
            Picker("Interaction settings", selection: $category) {
                ForEach(SettingsInteractionCategory.allCases) { category in
                    Text(category.localizedTitle).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16)

            Group {
                switch category {
                case .keyboardShortcuts:
                    HotkeySettingsView(searchQuery: searchQuery)
                case .selectionActions:
                    SelectionActionsSettingsView()
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.interaction")
        .onAppear { restoreCategory() }
        .onChange(of: category) { _, value in
            persistedCategory = value.rawValue
        }
        .onChange(of: searchQuery) { _, _ in
            selectCategoryForSearch()
        }
    }

    private func restoreCategory() {
        category = SettingsInteractionCategory(rawValue: persistedCategory)
            ?? .keyboardShortcuts
        selectCategoryForSearch()
    }

    private func selectCategoryForSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        guard !query.isEmpty else { return }

        if ["selection", "action", "prompt", "instruction", "选段", "操作"]
            .contains(where: query.contains) {
            category = .selectionActions
        } else if ["keyboard", "hotkey", "shortcut", "command", "menu", "快捷键"]
            .contains(where: query.contains) {
            category = .keyboardShortcuts
        }
    }
}

struct SettingsIntegrationsView: View {
    let searchQuery: String

    @AppStorage("scholium.settings.integrationCategory")
    private var persistedCategory = SettingsIntegrationCategory.agents.rawValue
    @State private var category = SettingsIntegrationCategory.agents

    var body: some View {
        VStack(spacing: 0) {
            Picker("Integration settings", selection: $category) {
                ForEach(SettingsIntegrationCategory.allCases) { category in
                    Text(category.localizedTitle).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16)

            Group {
                switch category {
                case .agents:
                    AgentIntegrationSettingsView()
                case .zotero:
                    ZoteroSettingsPageView()
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.integrations")
        .onAppear { restoreCategory() }
        .onChange(of: category) { _, value in
            persistedCategory = value.rawValue
        }
        .onChange(of: searchQuery) { _, _ in
            selectCategoryForSearch()
        }
    }

    private func restoreCategory() {
        category = SettingsIntegrationCategory(rawValue: persistedCategory) ?? .agents
        selectCategoryForSearch()
    }

    private func selectCategoryForSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
        guard !query.isEmpty else { return }

        if ["zotero", "citation", "library", "local api", "引用"]
            .contains(where: query.contains) {
            category = .zotero
        } else if ["agent", "chat", "codex", "claude", "mcp", "method", "tool", "bridge", "智能体"]
            .contains(where: query.contains) {
            category = .agents
        }
    }
}

struct ZoteroSettingsPageView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            ZoteroSettingsView()
        }
        .padding(24)
        .frame(maxWidth: 760, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.zotero")
    }
}

func localizedInterfaceString(
    _ keyAndValue: String.LocalizationValue
) -> String {
    ScholiumL10n.string(keyAndValue)
}
