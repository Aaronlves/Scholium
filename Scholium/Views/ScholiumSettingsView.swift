import AppKit
import ScholiumContracts
import SwiftUI

enum ScholiumSettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case workspace
    case document
    case writing
    case shortcuts
    case agents
    case zotero
    case storage

    var id: String { rawValue }

    /// These pages borrow the selected Triptych's existing Chat owner.
    var needsChatController: Bool {
        switch self {
        case .writing, .agents, .zotero: true
        case .workspace, .document, .shortcuts, .storage: false
        }
    }

    var toolbarTitle: LocalizedStringResource {
        switch self {
        case .workspace: ScholiumL10n.Settings.workspace
        case .document: LocalizedStringResource("settings.toolbar.document", defaultValue: "Document", table: "Interface", bundle: .module)
        case .writing: LocalizedStringResource("Writing", bundle: .module)
        case .agents: LocalizedStringResource("settings.toolbar.agents", defaultValue: "Agents", table: "Interface", bundle: .module)
        case .shortcuts: LocalizedStringResource("Shortcuts", bundle: .module)
        case .zotero: LocalizedStringResource("Zotero", bundle: .module)
        case .storage: LocalizedStringResource("Storage", table: "Interface", bundle: .module)
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .workspace: ScholiumL10n.Settings.workspace
        case .document: ScholiumL10n.Settings.document
        case .writing: ScholiumL10n.WritingAssistance.title
        case .agents: LocalizedStringResource("Agents & Chat", bundle: .module)
        case .shortcuts: LocalizedStringResource("Keyboard Shortcuts", bundle: .module)
        case .zotero: LocalizedStringResource("Zotero", bundle: .module)
        case .storage: LocalizedStringResource("Storage", table: "Interface", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .workspace: "rectangle.3.group"
        case .document: "doc.richtext"
        case .writing: "pencil.line"
        case .agents: "point.3.connected.trianglepath.dotted"
        case .shortcuts: "keyboard"
        case .zotero: "books.vertical"
        case .storage: "internaldrive"
        }
    }
}

struct ScholiumSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    private let preferences: SettingsPreferences
    private let chatControllerProvider: @MainActor (UUID) -> AgentChatController?
    @AppStorage private var persistedPane: String
    @AppStorage private var navigationRevision: String
    @State private var searchRevision = 0
    @State private var destination = ScholiumSettingsDestination.workspace
    @State private var destinationBeforeSearch: ScholiumSettingsDestination?
    @State private var searchQuery = ""
    @State private var searchTarget: SettingsSection?
    init(
        preferences: SettingsPreferences = .standard,
        chatControllerProvider: @escaping @MainActor (UUID) -> AgentChatController?
    ) {
        self.preferences = preferences
        self.chatControllerProvider = chatControllerProvider
        _persistedPane = AppStorage(
            wrappedValue: "workspace", "scholium.settings.selectedPane", store: preferences.defaults)
        _navigationRevision = AppStorage(
            wrappedValue: "", "scholium.settings.navigationRevision", store: preferences.defaults)
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScholiumSettingsNavigationHost(selection: categorySelection, page: settingsContent)
            .environment(\.scholiumSettingsDefaults, preferences.defaults)
            .defaultAppStorage(preferences.defaults)
            .frame(
                minWidth: ScholiumMetrics.Settings.minimumWindowWidth,
                minHeight: ScholiumMetrics.Settings.minimumWindowHeight
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scholium.settings.root")
            .onAppear { restoreRequestedDestination() }
            .onChange(of: navigationRevision) { _, _ in
                destinationBeforeSearch = nil
                searchQuery = ""
                searchTarget = nil
                restoreRequestedDestination()
            }
            .onChange(of: persistedPane) { _, _ in
                if !isSearching || persistedPane != destination.rawValue {
                    searchQuery = ""
                    destinationBeforeSearch = nil
                    restoreRequestedDestination()
                }
            }
            .onChange(of: destination) { _, destination in
                if !isSearching { persistedPane = destination.rawValue }
            }
            .onChange(of: searchQuery) { _, _ in
                if !isSearching {
                    if let destinationBeforeSearch {
                        searchTarget = nil
                        destination = destinationBeforeSearch
                        self.destinationBeforeSearch = nil
                    }
                    return
                }
                if destinationBeforeSearch == nil { destinationBeforeSearch = destination }
                // Typing filters destinations; only choosing a result navigates.
                searchTarget = nil
            }
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                ScholiumSettingsSearchField(text: $searchQuery, reveal: reveal)
                    .frame(width: ScholiumMetrics.Settings.searchFieldWidth)
            }
            .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
            .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            selectedPage
        }
        .scholiumSettingsPaneSurface()
    }

    private var selectedPage: some View {
        ScholiumSettingsPaneHost(
            selection: destination,
            identifier: "scholium.settings.pages"
        ) { item in
            settingsDetail(for: item)
                .environment(
                    \.agentChatSettingsController,
                    item.needsChatController
                        ? settingsModel.selectedTriptychID.flatMap { chatControllerProvider($0) }
                        : nil
                )
        }
        .environment(\.scholiumSettingsSearchTarget, searchTarget)
        .environment(\.scholiumSettingsSearchRevision, searchRevision)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func reveal(_ target: SettingsSearchTarget) {
        searchTarget = target.section
        searchRevision += 1
        destination = target.destination
    }

    private func restoreRequestedDestination() {
        destination = ScholiumSettingsDestination(rawValue: persistedPane) ?? .workspace
        if let target = SettingsNavigationRequest.takeRequestedSection(for: destination, defaults: preferences.defaults) {
            searchTarget = target
            searchRevision += 1
        } else if searchTarget?.destination != destination {
            searchTarget = nil
        }
    }

    private var categorySelection: Binding<ScholiumSettingsDestination> {
        Binding(
            get: { destination },
            set: { value in
                destinationBeforeSearch = nil
                searchQuery = ""
                searchTarget = nil
                destination = value
                persistedPane = value.rawValue
            })
    }

    @ViewBuilder
    private func settingsDetail(for destination: ScholiumSettingsDestination) -> some View {
        switch destination {
        case .workspace:
            WorkspaceSettingsView(
                openTriptych: { id in
                    openWindow(id: "scholium-main", value: TriptychWindowRoute(triptychID: id))
                },
                newTriptych: {
                    openWindow(id: "scholium-bootstrap", value: BootstrapWindowRoute(purpose: .newTriptych))
                }
            )
        case .document:
            if let store = settingsModel.cssSnippetStore {
                AppearanceSettingsView(store: store)
            } else {
                ScholiumContentStateView(
                    "Document Appearance Unavailable",
                    detail: Text("Document appearance profiles are unavailable in this Settings session."),
                    indicator: .symbol("doc.richtext", role: .attention)
                ).padding(ScholiumGrid.Spacing.regionContentInset)
            }
        case .writing:
            WritingSettingsView(
                writingPreferences: preferences.writingAssistance,
                selectionActionPreferences: preferences.selectionActions)
        case .agents:
            AgentIntegrationSettingsView(
                searchQuery: searchQuery,
                chatSidebarPreferences: preferences.chatSidebar,
                contextAccessPreferences: preferences.agentContextAccess)
        case .shortcuts: HotkeySettingsView()
        case .zotero: ZoteroSettingsPageView()
        case .storage: StorageSettingsView(capabilities: settingsModel.storageCapabilities)
        }
    }
}
