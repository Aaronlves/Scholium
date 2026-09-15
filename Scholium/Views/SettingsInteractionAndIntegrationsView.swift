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

/// Related machine-local interaction settings share one top-level
/// preference page. Their underlying owners remain separate.
enum SettingsInteractionCategory: String, CaseIterable, Identifiable {
    case keyboardShortcuts = "keyboard-shortcuts"
    case selectionActions = "selection-actions"
    case chat = "chat"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .keyboardShortcuts:
            LocalizedStringResource("Keyboard Shortcuts", table: "Localizable", bundle: .module)
        case .chat:
            LocalizedStringResource("Chat", table: "Localizable", bundle: .module)
        case .selectionActions:
            LocalizedStringResource("Selection Actions", table: "Localizable", bundle: .module)
        }
    }

    static func matchingSearch(_ searchQuery: String) -> Self? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        if ScholiumHotkeyCommand.customizableCommands.contains(where: { command in
            [String(localized: command.title), String(localized: command.menuPath)]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }) {
            return .keyboardShortcuts
        }
        let normalized = query.localizedLowercase
        if ["chat", "queue", "steer", "return", "聊天", "回车", "排队"].contains(where: normalized.contains) {
            return .chat
        }
        if ["selection", "action", "prompt", "instruction", "选段", "操作"].contains(where: normalized.contains) {
            return .selectionActions
        }
        if ["keyboard", "hotkey", "shortcut", "command", "menu", "快捷键"].contains(where: normalized.contains) {
            return .keyboardShortcuts
        }
        return nil
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

    static func matchingSearch(_ searchQuery: String) -> Self? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !query.isEmpty else { return nil }
        if ["zotero", "citation", "library", "local api", "引用"].contains(where: query.contains) {
            return .zotero
        }
        if ["agent", "chat", "codex", "claude", "mcp", "skill", "tool", "bridge", "智能体"].contains(where: query.contains) {
            return .agents
        }
        return nil
    }
}

struct SettingsInteractionView: View {
    let searchQuery: String

    @AppStorage("scholium.settings.interactionCategory")
    private var persistedCategory = SettingsInteractionCategory.keyboardShortcuts.rawValue
    @State private var navigation = SettingsSearchNavigation<SettingsInteractionCategory>(category: .keyboardShortcuts)
    @State private var hasRestoredCategory = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Interaction settings", selection: categoryBinding) {
                ForEach(SettingsInteractionCategory.allCases) { category in
                    Text(category.localizedTitle).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16)

            ScholiumSettingsPaneHost(selection: navigation.category) { item in
                switch item {
                case .keyboardShortcuts: HotkeySettingsView(searchQuery: searchQuery)
                case .selectionActions: SelectionActionsSettingsView()
                case .chat: AgentChatInputSettingsView()
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
        .onAppear { updateSearchNavigation() }
        .onChange(of: searchQuery) { _, _ in updateSearchNavigation() }
    }

    private var categoryBinding: Binding<SettingsInteractionCategory> {
        Binding(
            get: { navigation.category },
            set: { value in
                navigation.category = value
                if !navigation.isSearching { persistedCategory = value.rawValue }
            }
        )
    }

    private func updateSearchNavigation() {
        if !hasRestoredCategory {
            navigation.category = SettingsInteractionCategory(rawValue: persistedCategory) ?? .keyboardShortcuts
            hasRestoredCategory = true
        }
        navigation.updateSearch(query: searchQuery, matching: SettingsInteractionCategory.matchingSearch(searchQuery))
    }
}

struct SettingsIntegrationsView: View {
    let searchQuery: String

    @AppStorage("scholium.settings.integrationCategory")
    private var persistedCategory = SettingsIntegrationCategory.agents.rawValue
    @State private var navigation = SettingsSearchNavigation<SettingsIntegrationCategory>(category: .agents)
    @State private var hasRestoredCategory = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Integration settings", selection: categoryBinding) {
                ForEach(SettingsIntegrationCategory.allCases) { category in
                    Text(category.localizedTitle).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16)

            ScholiumSettingsPaneHost(selection: navigation.category) { item in
                switch item {
                case .agents: AgentIntegrationSettingsView()
                case .zotero: ZoteroSettingsPageView()
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
        .onAppear { updateSearchNavigation() }
        .onChange(of: searchQuery) { _, _ in updateSearchNavigation() }
    }

    private var categoryBinding: Binding<SettingsIntegrationCategory> {
        Binding(
            get: { navigation.category },
            set: { value in
                navigation.category = value
                if !navigation.isSearching { persistedCategory = value.rawValue }
            }
        )
    }

    private func updateSearchNavigation() {
        if !hasRestoredCategory {
            navigation.category = SettingsIntegrationCategory(rawValue: persistedCategory) ?? .agents
            hasRestoredCategory = true
        }
        navigation.updateSearch(query: searchQuery, matching: SettingsIntegrationCategory.matchingSearch(searchQuery))
    }
}

struct ZoteroSettingsPageView: View {
    var body: some View {
        Form {
            ZoteroSettingsView()
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("scholium.settings.zotero")
    }
}

func localizedInterfaceString(
    _ keyAndValue: String.LocalizationValue
) -> String {
    ScholiumL10n.string(keyAndValue)
}
