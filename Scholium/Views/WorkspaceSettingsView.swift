import Accessibility
import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

enum ScholiumSettingsDestination: String, CaseIterable, Identifiable, Hashable {
    case workspace
    case document
    case writing
    case agents
    case shortcuts
    case notifications
    case zotero

    var id: String { rawValue }
    var pane: WorkspaceSettingsPane { WorkspaceSettingsPane(rawValue: rawValue)! }

    var title: LocalizedStringResource {
        switch self {
        case .workspace: ScholiumL10n.Settings.workspace
        case .document: ScholiumL10n.Settings.document
        case .writing: ScholiumL10n.WritingAssistance.title
        case .agents: LocalizedStringResource("Agents & Chat", bundle: .module)
        case .shortcuts: LocalizedStringResource("Keyboard Shortcuts", bundle: .module)
        case .notifications: ScholiumL10n.Settings.notifications
        case .zotero: LocalizedStringResource("Zotero", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .workspace: "rectangle.3.group"
        case .document: "doc.richtext"
        case .writing: "pencil.line"
        case .agents: "point.3.connected.trianglepath.dotted"
        case .shortcuts: "keyboard"
        case .notifications: "bell"
        case .zotero: "books.vertical"
        }
    }
}

struct ScholiumSettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @AppStorage("scholium.settings.selectedPane") private var persistedPane = "workspace"
    @AppStorage("scholium.settings.navigationRevision") private var navigationRevision = ""
    @State private var searchRevision = 0
    @State private var destination = ScholiumSettingsDestination.workspace
    @State private var destinationBeforeSearch: ScholiumSettingsDestination?
    @State private var searchQuery = ""
    @State private var searchTarget: SettingsSearchTarget?
    @FocusState private var sidebarFocused: Bool

    private var searchResults: [SettingsSearchTarget] { SettingsSearchTarget.matches(searchQuery) }
    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScholiumSettingsNavigationHost(title: destination.title, sidebar: sidebar, page: selectedPage)
            .ignoresSafeArea(.container, edges: .top)
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
                settingsModel.selectPane(destination.pane)
                if !isSearching { persistedPane = destination.rawValue }
            }
            .onChange(of: searchQuery) { _, _ in
                if !isSearching {
                    searchTarget = nil
                    if let destinationBeforeSearch {
                        destination = destinationBeforeSearch
                        self.destinationBeforeSearch = nil
                    }
                    return
                }
                if destinationBeforeSearch == nil { destinationBeforeSearch = destination }
                if let first = searchResults.first { reveal(first) }
            }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScholiumSettingsSearchField(text: $searchQuery)
                .accessibilityIdentifier("scholium.settings.search")
                .padding(ScholiumGrid.Spacing.inlineControlGap)
            List(selection: sidebarSelection) {
                if isSearching {
                    Section("Search Results") {
                        ForEach(searchResults) { result in
                            Button {
                                reveal(result)
                            } label: {
                                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                                    Text(result.title)
                                    Text(result.destination.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("scholium.settings.result.\(result.id)")
                        }
                    }
                }
                Section {
                    ForEach(ScholiumSettingsDestination.allCases) { item in
                        Label(item.title, systemImage: item.symbol)
                            .tag(item)
                            .accessibilityIdentifier("scholium.settings.category.\(item.rawValue)")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .focused($sidebarFocused)
            .simultaneousGesture(TapGesture().onEnded { sidebarFocused = true })
            .accessibilityLabel("Settings categories")
        }
    }

    private var selectedPage: some View {
        ScholiumSettingsPaneHost(
            selection: isSearching && searchResults.isEmpty ? nil : destination,
            identifier: "scholium.settings.pages"
        ) { item in
            if let item {
                settingsDetail(for: item)
            } else {
                ContentUnavailableView.search(text: searchQuery)
            }
        }
        .environment(\.scholiumSettingsSearchTarget, searchTarget?.sectionID)
        .environment(\.scholiumSettingsSearchRevision, searchRevision)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func reveal(_ target: SettingsSearchTarget) {
        searchTarget = target
        searchRevision += 1
        destination = target.destination
    }

    private func restoreRequestedDestination() {
        destination = ScholiumSettingsDestination(rawValue: persistedPane) ?? .workspace
        settingsModel.selectPane(destination.pane)
    }

    private var sidebarSelection: Binding<ScholiumSettingsDestination?> {
        Binding(
            get: { destination },
            set: { value in
                guard let value else { return }
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
        case .writing: WritingSettingsView()
        case .agents: AgentIntegrationSettingsView(searchQuery: searchQuery)
        case .shortcuts: HotkeySettingsView(searchQuery: "")
        case .notifications: AttentionSettingsView()
        case .zotero: ZoteroSettingsPageView()
        }
    }
}

struct ZoteroSettingsView: View {
    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var info = ZoteroLibraryInfo(
        status: .appUnavailable, lastSuccessfulConnection: nil)
    @State private var isTesting = false
    @State private var errorMessage: String?

    var body: some View {
        Section("Zotero") {
            LabeledContent("Local API") {
                Label(statusTitle, systemImage: statusSymbol)
                    .foregroundStyle(.primary)
            }
            LabeledContent("Last Connected") {
                Text(
                    info.lastSuccessfulConnection?.formatted(date: .abbreviated, time: .shortened)
                        ?? localizedInterfaceString("Never")
                )
                .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    zoteroActions
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    zoteroActions
                }
            }
            Text(
                "Scholium connects only to Zotero Desktop on localhost and never accesses its private database. Chat imports and item changes require explicit confirmation. No account or API key is required."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            if info.status == .apiDisabled {
                Text(
                    "In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’, then test again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .task(id: isPaneActive) {
            guard isPaneActive else { return }
            let current = await settingsModel.zoteroConnectionInfo()
            guard !Task.isCancelled else { return }
            info = current
        }
        .accessibilityIdentifier("scholium.settings.zotero.connection")
    }

    @ViewBuilder
    private var zoteroActions: some View {
        Button("Open Zotero") {
            Task { await settingsModel.openZotero() }
        }
        Button("Check Connection") { refresh() }
            .disabled(isTesting)
        Button("Clear History", role: .destructive) {
            Task {
                try? await settingsModel.clearZoteroConnectionHistory()
                info = await settingsModel.zoteroConnectionInfo()
            }
        }
        .accessibilityLabel("Clear Connection History")
    }

    private var statusTitle: String {
        switch info.status {
        case .available, .itemMissing:
            localizedInterfaceString("Connected")
        case .apiDisabled:
            localizedInterfaceString("Access Disabled in Zotero")
        case .appUnavailable:
            localizedInterfaceString("Zotero Not Available")
        }
    }

    private var statusSymbol: String {
        info.status == .available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func refresh() {
        isTesting = true
        Task {
            do {
                info = try await settingsModel.refreshZoteroLibraryInfo()
                errorMessage = nil
            } catch {
                info = await settingsModel.zoteroConnectionInfo()
                errorMessage = error.localizedDescription
            }
            isTesting = false
        }
    }
}

struct WorkspaceSettingsView: View {
    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var selectedTriptychID: UUID?
    let openTriptych: (UUID) -> Void
    let newTriptych: () -> Void

    var body: some View {
        ScholiumSettingsPaneHost(selection: selectedTriptychID) { id in
            if let id {
                WorkspacePathEditor(targetTriptychID: id) { registrationSection }
            } else {
                Form {
                    registrationSection
                    if settingsModel.isRefreshing {
                        ProgressView("Loading Registered Triptychs")
                    } else if let error = settingsModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                        Button("Reload Triptych Registration") {
                            Task { await settingsModel.refreshRegisteredVaults() }
                        }
                    } else {
                        ScholiumContentStateView(
                            "No Triptych Registered",
                            detail: Text("Create a Triptych by choosing Analyses, Topics, and Works folders."),
                            indicator: .symbol("rectangle.3.group")
                        )
                    }
                }.scholiumSettingsFormStyle()
            }
        }
        .scholiumSettingsPaneSurface()
        .task(id: isPaneActive) {
            guard isPaneActive else { return }
            await settingsModel.refreshRegisteredVaults()
            guard !Task.isCancelled else { return }
            if selectedTriptychID == nil {
                selectedTriptychID =
                    settingsModel.workspaceAssignment?.id
                    ?? settingsModel.registeredTriptychs.first?.id
            }
        }
        .onChange(of: settingsModel.snapshot.activeTriptychID) { _, activeID in
            selectedTriptychID = activeID
        }
    }

    private var registrationSection: some View {
        Section("Registered Triptychs") {
            triptychPicker
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumMetrics.Settings.rootSpacing) { triptychActions }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    triptychActions
                }
            }
        }.id("workspace.registration")
    }

    private var selectedTriptychBinding: Binding<UUID?> {
        Binding(
            get: { selectedTriptychID },
            set: { value in
                selectedTriptychID = value
                guard let value else { return }
                Task { await settingsModel.activateRegisteredTriptych(id: value) }
            }
        )
    }

    private var triptychPicker: some View {
        Picker("Triptych", selection: selectedTriptychBinding) {
            ForEach(settingsModel.registeredTriptychs) { assignment in
                Text(
                    settingsTriptychLabel(
                        assignment,
                        among: settingsModel.registeredTriptychs
                    )
                )
                .tag(Optional(assignment.id))
            }
        }
        .scholiumActivationPointer()
        .frame(maxWidth: 360)
        .disabled(settingsModel.registeredTriptychs.isEmpty)
        .accessibilityIdentifier("scholium.settings.triptychScope")
    }

    @ViewBuilder
    private var triptychActions: some View {
        Button("Open in New Window") {
            guard let selectedTriptychID else { return }
            openTriptych(selectedTriptychID)
        }
        .scholiumActivationPointer()
        .disabled(selectedTriptychID == nil)

        Button("New Triptych…") {
            newTriptych()
        }
        .scholiumActivationPointer()
    }

}

private func settingsTriptychLabel(
    _ assignment: TriptychAssignment,
    among assignments: [TriptychAssignment]
) -> String {
    let duplicates = assignments.filter {
        $0.triptych.name.caseInsensitiveCompare(assignment.triptych.name) == .orderedSame
    }
    guard duplicates.count > 1,
        let works = assignment.vault(for: .output)
    else {
        return assignment.triptych.name
    }
    let parent = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
        .deletingLastPathComponent().lastPathComponent
    return "\(assignment.triptych.name) — \(parent)"
}

private struct AppearanceSettingsView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @ObservedObject var store: CSSSnippetStore
    @StateObject private var fontCatalog = ScholiumSettingsFontCatalog()
    @State private var draft: DocumentAppearanceProfile?
    @State private var importError: String?
    @State private var showRename = false
    @State private var showDeleteConfirmation = false
    @State private var showRestoreDefaultConfirmation = false
    @State private var confirmsAppearanceRecovery = false
    @State private var confirmsSnippetRecovery = false
    @State private var showDiscardChangesConfirmation = false
    private enum ProfileSelection {
        case existing(UUID)
        case create
        case duplicate(UUID)
    }
    @State private var pendingProfileSelection: ProfileSelection?
    @State private var nameDraft = ""

    @State private var confirmsConfigurationReload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let draftBinding {
                appearanceSectionContent(profile: draftBinding)
            } else {
                Form {
                    appearanceRecoverySection
                    Section("CSS Snippets") { cssSnippetsContent }.id("appearance.css")
                    configurationFileSection.id("appearance.file")
                }
                .scholiumSettingsFormStyle()
                .scholiumSettingsSearchDestination()
            }

            appearanceStatus
            appearanceSaveActions
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.appearance.form")
        .task { await fontCatalog.loadIfNeeded() }
        .onAppear { if draft == nil { loadSelectedDraft() } }
        .onChange(of: store.selectedAppearanceProfileID) { _, _ in loadSelectedDraft() }
        .onChange(of: store.appearanceProfiles) { previous, _ in
            if let draft, let saved = store.selectedAppearanceProfile,
                draft.id == saved.id,
                let baseline = previous.first(where: { $0.id == draft.id }),
                draft.settings != baseline.settings
            {
                // A successful rename or background refresh cannot erase an
                // unsaved typography draft. Save still belongs to the store.
                self.draft?.name = saved.name
            } else {
                loadSelectedDraft()
            }
        }
        .onChange(of: store.appearanceReloadRevision) { _, _ in loadSelectedDraft() }
        .confirmationDialog(
            "Reload Appearance Configuration?", isPresented: $confirmsConfigurationReload,
            titleVisibility: .visible
        ) {
            Button("Reload", role: .destructive) { store.reloadAppearanceConfiguration() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Reloading replaces your unsaved appearance draft with the configuration file. An invalid file leaves the draft unchanged."
            )
        }
        .alert("Rename Appearance", isPresented: $showRename) {
            TextField("Configuration name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let id = store.selectedAppearanceProfileID else { return }
                store.renameAppearance(id, to: nameDraft)
            }
            .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Appearance?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let id = store.selectedAppearanceProfileID else { return }
                store.removeAppearance(id)
            }
        } message: {
            Text(
                "This removes the selected configuration from this Mac. Research documents are not changed."
            )
        }
        .confirmationDialog("Recover Default Appearance?", isPresented: $confirmsAppearanceRecovery, titleVisibility: .visible) {
            Button("Recover Default Appearance", role: .destructive) { store.restoreAppearanceDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Replace saved appearance profiles with a default profile and discard the current appearance draft. The previous configuration file is preserved separately. CSS snippets and research files are unchanged."
            )
        }
        .confirmationDialog("Recover CSS Snippet Settings?", isPresented: $confirmsSnippetRecovery, titleVisibility: .visible) {
            Button("Recover CSS Snippet Settings", role: .destructive) { store.restoreStyleSnippetDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Restore snippet settings with all snippets disabled. The previous settings file is preserved separately. CSS files, appearance profiles and research files are unchanged."
            )
        }
        .confirmationDialog(
            "Restore Default Appearance?",
            isPresented: $showRestoreDefaultConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                draft?.settings = DocumentAppearanceSettings.defaultSettings
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This replaces the current draft with Scholium’s built-in document appearance. Choose Save to keep it."
            )
        }
        .confirmationDialog(
            "Discard Unsaved Appearance Changes?",
            isPresented: $showDiscardChangesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard and Switch", role: .destructive) {
                guard let id = pendingProfileSelection else { return }
                pendingProfileSelection = nil
                performProfileSelection(id)
            }
            Button("Cancel", role: .cancel) {
                pendingProfileSelection = nil
            }
        } message: {
            Text(
                "The selected appearance has unsaved changes. Switching configurations will discard them.")
        }
    }

    @ViewBuilder
    private func appearanceSectionContent(
        profile: Binding<DocumentAppearanceProfile>
    ) -> some View {
        Form {
            configurationSection.id("appearance.profile").disabled(!store.canModifyAppearance)
            appearanceRecoverySection
            AppearanceReadingEditor(profile: profile, fontCatalog: fontCatalog).disabled(!store.canModifyAppearance && !store.canRepairAppearance)
            TypographySettingsView(profile: profile, fontCatalog: fontCatalog).disabled(!store.canModifyAppearance && !store.canRepairAppearance)
            Section("CSS Snippets") { cssSnippetsContent }.id("appearance.css")
            configurationFileSection.id("appearance.file")
        }
        .scholiumSettingsFormStyle()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scholiumSettingsSearchDestination()
        .accessibilityIdentifier("scholium.settings.appearance")
    }

    @ViewBuilder
    private var appearanceRecoverySection: some View {
        if let error = store.appearanceError {
            Section("Appearance Recovery") {
                Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                Button("Recover Default Appearance…") { confirmsAppearanceRecovery = true }
                    .disabled(store.isRestoringAppearance)
                    .accessibilityIdentifier("scholium.settings.appearance.recover")
            }
        }
    }

    private var configurationFileSection: some View {
        Section("Configuration File") {
            HStack {
                Button("Show in Finder…") { store.revealAppearanceConfiguration() }
                Spacer()
                Button("Reload") {
                    if hasUnsavedChanges {
                        confirmsConfigurationReload = true
                    } else {
                        store.reloadAppearanceConfiguration()
                    }
                }
                .accessibilityIdentifier("scholium.settings.appearance.reload")
                Button("Configuration Guide…") {
                    if let url = Bundle.module.url(
                        forResource: "AppearanceConfiguration", withExtension: "md")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var appearanceStatus: some View {
        if let reason = store.safeModeReason {
            Label("CSS Safe Mode: \(reason)", systemImage: "exclamationmark.shield.fill")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        }
        if let storeError = store.storeError {
            Label(storeError, systemImage: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(.red)
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                .accessibilityIdentifier("settings.css.store-error")
        }
        if let importError {
            Label(importError, systemImage: "exclamationmark.triangle.fill")
                .font(.body)
                .foregroundStyle(.red)
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        }
    }

    private var selectedProfileID: Binding<UUID?> {
        Binding(
            get: { store.selectedAppearanceProfileID },
            set: { id in
                guard let id else { return }
                requestProfileSelection(.existing(id))
            }
        )
    }

    private var configurationSection: some View {
        Section {
            LabeledContent("Profile") {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    appearancePicker
                    appearanceManagementMenu
                }
            }
        } footer: {
            Text("Saved on this Mac")
        }
    }

    private var appearanceSaveActions: some View {
        HStack(spacing: 8) {
            if hasUnsavedChanges {
                Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revert to Saved") { loadSelectedDraft() }
                .disabled(!hasUnsavedChanges)
            if store.canRepairAppearance {
                Button("Repair Saved Profile") {
                    guard let draft else { return }
                    store.repairAppearanceProfile(draft)
                }
                .disabled(store.isRestoringAppearance)
                .accessibilityIdentifier("scholium.settings.appearance.repair")
            }
            Button("Save Appearance") {
                guard let draft else { return }
                store.updateAppearance(draft)
            }
            .scholiumSettingsDefaultAction()
            .disabled(!hasUnsavedChanges || !store.canModifyAppearance)
            .accessibilityLabel("Save Appearance")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var cssSnippetsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                "Add .css files to the managed folder, or import one. Changes are detected automatically and apply to Review and Edit after validation; Source remains exact."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Callouts: .callout, .callout-title, .callout-body, and .callout-<role>.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button {
                    store.revealManagedFolder()
                } label: {
                    Label("Open CSS Folder", systemImage: "folder")
                }

                Button {
                    store.reloadSnippets()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }

                Spacer(minLength: 0)

                Button("Import CSS Snippet…") { importSnippet() }
                    .disabled(!store.canModify)
            }

            Divider()

            if let error = store.snippetError {
                Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                Button("Recover CSS Snippet Settings…") { confirmsSnippetRecovery = true }
                    .disabled(store.isRestoringSnippets)
                    .accessibilityIdentifier("scholium.settings.css.recover")
            }

            ForEach(store.snippets) { snippet in
                CSSSnippetRow(
                    snippet: snippet,
                    error: store.validationErrors[snippet.id],
                    store: store
                ).disabled(!store.canModify)
            }

            if store.snippets.isEmpty {
                Text("No CSS snippets yet. Open the folder or import a file to add one.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button("Disable All Snippets") { store.disableAll() }
                .disabled(store.enabledCount == 0 || !store.canModify)
        }
    }

    private var appearancePicker: some View {
        Picker("Configuration", selection: selectedProfileID) {
            ForEach(store.appearanceProfiles) { profile in
                Text(profile.name).tag(Optional(profile.id))
            }
        }
        .scholiumActivationPointer()
        .labelsHidden()
        .frame(width: ScholiumMetrics.Settings.appearancePickerWidth, alignment: .leading)
    }

    private var appearanceManagementMenu: some View {
        Menu {
            Button("New Appearance") { requestProfileSelection(.create) }
            Button("Duplicate Appearance") {
                guard let id = store.selectedAppearanceProfileID else { return }
                requestProfileSelection(.duplicate(id))
            }
            .disabled(store.selectedAppearanceProfileID == nil)
            Button("Rename Appearance…") { beginRename() }
                .disabled(store.selectedAppearanceProfileID == nil)
            Button("Restore Default Appearance…") {
                showRestoreDefaultConfirmation = true
            }
            .disabled(store.selectedAppearanceProfileID == nil)
            Divider()
            Button("Delete Appearance…", role: .destructive) {
                showDeleteConfirmation = true
            }
            .disabled(store.appearanceProfiles.count <= 1)
        } label: {
            Label("Manage", systemImage: "ellipsis.circle")
        }
        .scholiumActivationPointer()
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityIdentifier("scholium.appearance.manage")
    }

    private var draftBinding: Binding<DocumentAppearanceProfile>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft! },
            set: { draft = $0 }
        )
    }

    private var hasUnsavedChanges: Bool {
        guard let draft, let selected = store.selectedAppearanceProfile else { return false }
        return draft != selected
    }

    private func loadSelectedDraft() {
        draft = store.selectedAppearanceProfile
    }

    private func requestProfileSelection(_ selection: ProfileSelection) {
        if hasUnsavedChanges {
            pendingProfileSelection = selection
            showDiscardChangesConfirmation = true
        } else {
            performProfileSelection(selection)
        }
    }

    private func performProfileSelection(_ selection: ProfileSelection) {
        switch selection {
        case .existing(let id): selectProfile(id)
        case .create: store.createAppearance()
        case .duplicate(let id): store.duplicateAppearance(id)
        }
    }

    private func selectProfile(_ id: UUID) {
        store.selectAppearance(id)
        if let profile = store.appearanceProfiles.first(where: { $0.id == id }) {
            draft = profile
        }
    }

    private func beginRename() {
        guard let selected = store.selectedAppearanceProfile else { return }
        nameDraft = selected.name
        showRename = true
    }

    private func importSnippet() {
        let request = ScholiumFileSelectionRequest(
            title: ScholiumL10n.string("Import CSS Snippet"),
            prompt: ScholiumL10n.string("Import"),
            kind: .files(
                allowedContentTypes: [
                    UTType(filenameExtension: "css") ?? .plainText
                ]
            )
        )
        Task { @MainActor in
            do {
                guard
                    let url =
                        try await fileSelectionPresenter
                        .requiredForFileSelection()
                        .selectURL(request)
                else { return }
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                try await store.importSnippet(from: url)
                importError = nil
            } catch is CancellationError {
                return
            } catch {
                importError = error.localizedDescription
            }
        }
    }
}

private struct AppearanceReadingEditor: View {
    @Binding var profile: DocumentAppearanceProfile
    @ObservedObject var fontCatalog: ScholiumSettingsFontCatalog

    var body: some View {
        Section("Reading") {
            Picker("Body Font", selection: $profile.settings.body.fontFamily) {
                ForEach(DocumentAppearanceFontFamily.presets, id: \.self) { Text($0.label).tag($0) }
                Divider()
                ForEach(
                    fontCatalog.families(
                        retaining: profile.settings.body.fontFamily.rawValue,
                        excluding: DocumentAppearanceFontFamily.presets.map(\.rawValue)),
                    id: \.self
                ) { family in
                    Text(verbatim: family).tag(DocumentAppearanceFontFamily(rawValue: family))
                }
            }
            .accessibilityIdentifier("scholium.appearance.bodyFont")
            LabeledContent("Body font size") {
                HStack {
                    AppearanceNumberControl(
                        value: $profile.settings.body.fontSizePoints, range: 9...24, step: 0.5,
                        title: "Body font size")
                    Text("pt").foregroundStyle(.secondary)
                        .frame(width: ScholiumMetrics.Settings.unitLabelWidth, alignment: .leading)
                }
            }
            LabeledContent("Line width") {
                AppearanceDoubleValueControl(
                    value: $profile.settings.lineWidthCharacterUnits,
                    range: DocumentAppearanceSettings.lineWidthCharacterUnitsRange,
                    step: 1, suffix: "ch", precision: 0, title: "Line width",
                    accessibilityUnit: "character-width units")
            }
            LabeledContent("Line spacing") {
                AppearanceDoubleValueControl(
                    value: $profile.settings.body.lineHeight, range: 1.2...2.4,
                    step: 0.05, suffix: "×", precision: 2, title: "Line spacing", accessibilityUnit: nil)
            }
            Picker("Alignment", selection: $profile.settings.body.alignment) {
                ForEach(DocumentTextAlignment.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Hyphenation", selection: $profile.settings.hyphenation) {
                ForEach(DocumentHyphenation.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .accessibilityIdentifier("scholium.appearance.hyphenation")
            .id("appearance.hyphenation")
            Text(
                "Automatic hyphenation uses language-aware dictionaries for supported prose. Chinese text is not syllabified; Source and technical regions remain unchanged."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }.id("appearance.reading")
        Section("Source Font") {
            Picker("Source Font", selection: $profile.settings.source.fontFamily) {
                ForEach(fontCatalog.families(retaining: profile.settings.source.fontFamily), id: \.self) {
                    Text(verbatim: $0).tag($0)
                }
            }
            .accessibilityIdentifier("scholium.appearance.sourceFont")
            LabeledContent("Source font size") {
                HStack {
                    AppearanceNumberControl(
                        value: $profile.settings.source.fontSizePoints, range: 6...72, step: 0.25,
                        title: "Source font size")
                    Text("pt").foregroundStyle(.secondary)
                        .frame(width: ScholiumMetrics.Settings.unitLabelWidth, alignment: .leading)
                }
            }
        }.id("appearance.source")
    }

}

private struct TypographySettingsView: View {
    @Binding var profile: DocumentAppearanceProfile
    @ObservedObject var fontCatalog: ScholiumSettingsFontCatalog

    var body: some View {
        Group {
            Section("Body Typography") {
                LabeledContent("Paragraph spacing") {
                    AppearanceDoubleValueControl(
                        value: $profile.settings.body.paragraphSpacingEm, range: 0...2,
                        step: 0.05, suffix: "em", precision: 2, title: "Paragraph spacing",
                        accessibilityUnit: nil)
                }
                LabeledContent("First-line indent") {
                    AppearanceDoubleValueControl(
                        value: $profile.settings.body.firstLineIndentEm, range: 0...4,
                        step: 0.1, suffix: "em", precision: 2, title: "First-line indent",
                        accessibilityUnit: nil)
                }
            }.id("appearance.body")
            Section("Heading Typography") {
                Picker("Heading Font", selection: $profile.settings.headings.fontFamily) {
                    ForEach(DocumentHeadingFontFamily.presets, id: \.self) { Text($0.label).tag($0) }
                    Divider()
                    ForEach(headingFamilies, id: \.self) { family in
                        Text(verbatim: family).tag(DocumentHeadingFontFamily(rawValue: family))
                    }
                }
                .accessibilityIdentifier("scholium.appearance.headingFont")
                Picker("Heading Style", selection: $profile.settings.headings.style) {
                    ForEach(DocumentHeadingStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                LabeledContent("Heading Weight") {
                    AppearanceIntegerControl(
                        title: "Heading Weight", value: $profile.settings.headings.weight, range: 400...700,
                        step: 50)
                }
                LabeledContent("Heading Line Spacing") {
                    AppearanceDoubleValueControl(
                        value: $profile.settings.headings.lineHeight, range: 1...2.4,
                        step: 0.05, suffix: "×", precision: 2, title: "Heading Line Spacing",
                        accessibilityUnit: nil)
                }
            }.id("appearance.headingFont")
            Section("Text Styles") {
                roleFont("Body Bold Font", selection: $profile.settings.body.cjkStrongFontFamily)
                roleFont("Body Italic Font", selection: $profile.settings.body.cjkEmphasisFontFamily)
                roleFont("Heading Bold Font", selection: $profile.settings.headings.cjkStrongFontFamily)
                roleFont("Heading Italic Font", selection: $profile.settings.headings.cjkEmphasisFontFamily)
            }.id("appearance.styles")
            Section("Heading Hierarchy") {
                AppearanceHeadingLevelMatrix(headings: $profile.settings.headings)
            }.id("appearance.headings")
        }
        .accessibilityIdentifier("scholium.settings.appearance.typography")
    }

    private var headingFamilies: [String] {
        fontCatalog.families(
            retaining: profile.settings.headings.fontFamily.rawValue,
            excluding: DocumentHeadingFontFamily.presets.map(\.rawValue))
    }

    private func roleFont(_ title: LocalizedStringResource, selection: Binding<String?>) -> some View {
        AppearanceRoleFontPicker(
            title: title, selection: selection,
            availableFamilies: fontCatalog.families(retaining: selection.wrappedValue))
    }

}

private enum AppearanceHeadingLevel: String, CaseIterable, Identifiable {
    case h1
    case h2
    case h3
    case h4
    case h5
    case h6

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .h1: "H1"
        case .h2: "H2"
        case .h3: "H3"
        case .h4: "H4"
        case .h5: "H5"
        case .h6: "H6"
        }
    }
}

private struct AppearanceHeadingLevelMatrix: View {
    @Binding var headings: DocumentHeadingAppearance

    var body: some View {
        // Keep each level a direct native Form row so search can reveal it
        // before the lower part of this scrolling group is realized.
        ForEach(AppearanceHeadingLevel.allCases) { level in
            ViewThatFits(in: .horizontal) {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: ScholiumMetrics.Settings.matrixColumnSpacing,
                    verticalSpacing: ScholiumMetrics.Settings.matrixRowSpacing
                ) {
                    GridRow {
                        settingsMatrixHeader("Heading Level")
                        settingsMatrixHeader("Scale")
                        settingsMatrixHeader("Alignment")
                        settingsMatrixHeader("Space Before")
                        settingsMatrixHeader("Space After")
                    }
                    AppearanceHeadingLevelMatrixRow(
                        level: level,
                        appearance: binding(for: level))
                }
                .frame(minWidth: ScholiumMetrics.Settings.headingMatrixMinimumWidth, maxWidth: .infinity, alignment: .leading)
                AppearanceHeadingLevelDetailRow(
                    level: level,
                    appearance: binding(for: level))
            }
            .id("appearance.\(level.rawValue)")
        }
    }

    private func binding(
        for level: AppearanceHeadingLevel
    ) -> Binding<DocumentHeadingLevelAppearance> {
        switch level {
        case .h1: $headings.level1
        case .h2: $headings.level2
        case .h3: $headings.level3
        case .h4: $headings.level4
        case .h5: $headings.level5
        case .h6: $headings.level6
        }
    }

}

private struct AppearanceHeadingLevelMatrixRow: View {
    let level: AppearanceHeadingLevel
    @Binding var appearance: DocumentHeadingLevelAppearance

    var body: some View {
        GridRow {
            settingsMatrixRowLabel(level.title)
            HStack(spacing: 6) {
                AppearanceNumberControl(
                    value: $appearance.scale,
                    range: 0.8...3,
                    step: 0.05,
                    title: "\(level.title) scale"
                )
                Text("×")
                    .foregroundStyle(.secondary)
            }
            Picker("\(level.title) alignment", selection: $appearance.alignment) {
                ForEach(DocumentTextAlignment.allCases, id: \.self) {
                    Text($0.label).tag($0)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 124, alignment: .leading)
            Group {
                HStack(spacing: 6) {
                    AppearanceNumberControl(
                        value: $appearance.spaceBeforeEm,
                        range: 0...4,
                        step: 0.05,
                        title: "\(level.title) space before"
                    )
                    Text("em")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    AppearanceNumberControl(
                        value: $appearance.spaceAfterEm,
                        range: 0...4,
                        step: 0.05,
                        title: "\(level.title) space after"
                    )
                    Text("em")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AppearanceHeadingLevelDetailRow: View {
    let level: AppearanceHeadingLevel
    @Binding var appearance: DocumentHeadingLevelAppearance

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(level.title)
                .font(.subheadline.weight(.semibold))
            settingsEditorSection("Scale") {
                HStack(spacing: 6) {
                    AppearanceNumberControl(
                        value: $appearance.scale,
                        range: 0.8...3,
                        step: 0.05,
                        title: "\(level.title) scale"
                    )
                    Text("×")
                        .foregroundStyle(.secondary)
                }
            }
            settingsEditorSection("Alignment") {
                Picker("\(level.title) alignment", selection: $appearance.alignment) {
                    ForEach(DocumentTextAlignment.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            settingsEditorSection("Space Before") {
                HStack(spacing: 6) {
                    AppearanceNumberControl(
                        value: $appearance.spaceBeforeEm,
                        range: 0...4,
                        step: 0.05,
                        title: "\(level.title) space before"
                    )
                    Text("em")
                        .foregroundStyle(.secondary)
                }
            }
            settingsEditorSection("Space After") {
                HStack(spacing: 6) {
                    AppearanceNumberControl(
                        value: $appearance.spaceAfterEm,
                        range: 0...4,
                        step: 0.05,
                        title: "\(level.title) space after"
                    )
                    Text("em")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AppearanceNumberControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let title: LocalizedStringResource

    private var boundedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { candidate in
                guard candidate.isFinite else { return }
                value = min(max(candidate, range.lowerBound), range.upperBound)
            })
    }

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            TextField("", value: boundedValue, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: ScholiumMetrics.Settings.numberFieldWidth)
                .accessibilityLabel(Text(title))
            Stepper("", value: boundedValue, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(Text(title))
        }
        .fixedSize()
    }
}

private struct AppearanceIntegerControl: View {
    let title: LocalizedStringResource
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    private var boundedValue: Binding<Int> {
        Binding(
            get: { value },
            set: { candidate in
                value = min(max(candidate, range.lowerBound), range.upperBound)
            })
    }

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            TextField("", value: boundedValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: ScholiumMetrics.Settings.numberFieldWidth)
                .accessibilityLabel(Text(title))
            Stepper("", value: boundedValue, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(Text(title))
        }
        .fixedSize()
    }
}

private struct AppearanceDoubleValueControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    let precision: Int
    let title: LocalizedStringResource
    let accessibilityUnit: LocalizedStringResource?

    private var boundedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { candidate in
                guard candidate.isFinite else { return }
                value = min(max(candidate, range.lowerBound), range.upperBound)
            })
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(
                "",
                value: boundedValue,
                format: .number.precision(.fractionLength(0...precision))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: ScholiumMetrics.Settings.numberFieldWidth)
            .accessibilityLabel(Text(title))
            Stepper("", value: boundedValue, in: range, step: step)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel(Text(title))
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: ScholiumMetrics.Settings.unitLabelWidth, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .help(Text(accessibilityUnit ?? title))
    }
}

private struct AppearanceRoleFontPicker: View {
    private static let defaultChoice = "__scholium_role_default__"
    private static let automaticChoice = "__scholium_role_font__"

    let title: LocalizedStringResource
    @Binding var selection: String?
    let availableFamilies: [String]

    private var choiceBinding: Binding<String> {
        Binding(
            get: {
                if let selection, !selection.isEmpty { return selection }
                if selection == nil { return Self.defaultChoice }
                return Self.automaticChoice
            },
            set: { value in
                if value == Self.defaultChoice {
                    selection = nil
                } else if value == Self.automaticChoice {
                    selection = ""
                } else {
                    selection = value
                }
            }
        )
    }

    var body: some View {
        Picker(title, selection: choiceBinding) {
            Text("Default")
                .tag(Self.defaultChoice)
            Text("Use role font")
                .tag(Self.automaticChoice)
            ForEach(availableFamilies, id: \.self) { family in
                Text(verbatim: family).tag(family)
            }
        }
        .pickerStyle(.menu)
    }
}

extension DocumentAppearanceFontFamily {
    fileprivate var label: String {
        switch self {
        case .alegreya: "Alegreya"
        case .iowan: "Iowan Old Style"
        case .palatino: "Palatino"
        case .georgia: "Georgia"
        case .times: "Times New Roman"
        case .systemSerif: "System Serif"
        default: rawValue
        }
    }
}

extension DocumentHeadingFontFamily {
    fileprivate var label: LocalizedStringResource {
        switch self {
        case .body: "Body Font"
        case .alegreya: "Alegreya"
        case .systemSerif: "System Serif"
        case .systemSans: "System Sans"
        default: LocalizedStringResource(stringLiteral: rawValue)
        }
    }
}

extension DocumentHeadingStyle {
    fileprivate var label: LocalizedStringResource {
        switch self {
        case .upright: "Upright"
        case .italic: "Italic"
        case .smallCaps: "Small Caps"
        }
    }
}

extension DocumentTextAlignment {
    fileprivate var label: LocalizedStringResource {
        switch self {
        case .start: "Start"
        case .center: "Center"
        case .justify: "Justify"
        }
    }
}

extension DocumentHyphenation {
    fileprivate var label: LocalizedStringResource {
        switch self {
        case .none: "Never"
        case .automatic: "Automatic"
        }
    }
}

private struct CSSSnippetRow: View {
    let snippet: CSSSnippetRecord
    let error: String?
    @ObservedObject var store: CSSSnippetStore
    @State private var showRename = false
    @State private var nameDraft = ""

    var body: some View {
        HStack(spacing: ScholiumMetrics.Settings.rootSpacing) {
            Toggle(
                isOn: Binding(
                    get: { snippet.isEnabled },
                    set: { store.setEnabled($0, for: snippet.id) }
                )
            ) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                    Text(snippet.name)
                        .lineLimit(1)
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    } else {
                        Text(snippet.isEnabled ? "Enabled" : "Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Spacer(minLength: ScholiumMetrics.Settings.rowActionMinimumSpacing)

            Button {
                store.move(snippet.id, by: -1)
            } label: {
                Label("Move Earlier", systemImage: "chevron.up")
            }
            .labelStyle(.iconOnly)
            .help("Move Earlier")

            Button {
                store.move(snippet.id, by: 1)
            } label: {
                Label("Move Later", systemImage: "chevron.down")
            }
            .labelStyle(.iconOnly)
            .help("Move Later")

            Menu {
                Button("Rename…") {
                    nameDraft = snippet.name
                    showRename = true
                }
                Button("Duplicate") { store.duplicate(snippet.id) }
                Button("Edit Managed Copy") { store.editManagedCopy(snippet.id) }
                Button("Reload from Disk") { store.reload(snippet.id) }
                Divider()
                Button("Remove Snippet", role: .destructive) { store.remove(snippet.id) }
            } label: {
                Label("Snippet Actions", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, ScholiumMetrics.Settings.rowVerticalInset)
        .alert("Rename CSS Snippet", isPresented: $showRename) {
            TextField("Snippet name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { store.rename(snippet.id, to: nameDraft) }
        }
    }
}

private struct WorkspacePathEditor<Registration: View>: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel

    let targetTriptychID: UUID
    @ViewBuilder var registration: () -> Registration

    @State private var paperAnalysisURL: URL?
    @State private var topicKnowledgeURL: URL?
    @State private var outputURL: URL?
    @State private var portableContainerURL: URL?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var loadedCurrentValues = false
    @State private var triptychName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                registration()
                Section("Name") {
                    TextField("Name", text: $triptychName)
                        .labelsHidden()
                        .accessibilityIdentifier("scholium.triptychName")

                }.id("workspace.name")

                Section("Research Folders") {
                    WorkspaceFolderRow(
                        title: "Analyses",
                        url: $paperAnalysisURL
                    )
                    WorkspaceFolderRow(
                        title: "Topics",
                        url: $topicKnowledgeURL
                    )
                    WorkspaceFolderRow(
                        title: "Works",
                        url: $outputURL
                    )
                }.id("workspace.folders")

                Section("Portable Triptych Data") {
                    PortableControlFolderRow(
                        worksURL: outputURL,
                        containerURL: $portableContainerURL
                    )
                    Text(
                        "Scholium stores the small portable .scholium folder beside Works. macOS therefore asks once for access to the folder containing Works; it is not added as a fourth vault."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: ScholiumMetrics.Settings.formExplanationMaximumWidth,
                        alignment: .leading
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }.id("workspace.portable")

                if loadedCurrentValues { PortableSettingsRecoverySection(triptychID: targetTriptychID) }

            }
            .disabled(!loadedCurrentValues)
            .scholiumSettingsFormStyle()
            .scholiumSettingsSearchDestination()

            if !loadedCurrentValues {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    if settingsModel.isRefreshing {
                        ProgressView("Loading Registered Triptychs")
                    } else {
                        if let error = settingsModel.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                        }
                        Button("Reload Triptych Registration") {
                            Task { await settingsModel.refreshRegisteredVaults() }
                        }
                    }
                }
                .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(.red)
                    .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
                    .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                    .accessibilityLabel("Workspace error: \(errorMessage)")
            } else if let recoveryMessage = settingsModel.workspaceRecoveryMessage {
                Label(recoveryMessage, systemImage: "folder.badge.questionmark")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
                    .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                    .accessibilityLabel("Workspace access: \(recoveryMessage)")
            }

            HStack {
                Spacer()
                Button("Save Triptych") { save() }
                    .buttonStyle(.bordered)
                    .scholiumSettingsDefaultAction()
                    .disabled(!canSave || isSaving)
            }
            .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
            .padding(.vertical, ScholiumGrid.Spacing.sectionSeparation)
        }
        .accessibilityIdentifier("scholium.triptychSetup")
        .onChange(of: targetAssignment) { _, _ in loadCurrentValuesIfNeeded() }
        .task {
            loadCurrentValuesIfNeeded()
            await settingsModel.refreshWorkspaceAssignment()
            loadCurrentValuesIfNeeded()
            await loadPortableContainerIfAvailable()
        }
        .onChange(of: outputURL) { oldValue, newValue in
            let oldParent = oldValue?.deletingLastPathComponent().standardizedFileURL.path
            let newParent = newValue?.deletingLastPathComponent().standardizedFileURL.path
            if oldParent != newParent {
                portableContainerURL = nil
            }
            Task { await loadPortableContainerIfAvailable() }
        }
    }

    private var allFoldersSelected: Bool {
        paperAnalysisURL != nil && topicKnowledgeURL != nil && outputURL != nil
    }

    private var canSave: Bool {
        guard allFoldersSelected,
            let outputURL,
            let portableContainerURL
        else { return false }
        return outputURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            == portableContainerURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func loadCurrentValuesIfNeeded() {
        guard !loadedCurrentValues, targetAssignment != nil else { return }
        loadedCurrentValues = true
        paperAnalysisURL = assignedURL(for: .paperAnalysis)
        topicKnowledgeURL = assignedURL(for: .topicKnowledge)
        outputURL = assignedURL(for: .output)
        triptychName = targetAssignment?.triptych.name ?? ""
    }

    private func loadPortableContainerIfAvailable() async {
        guard let outputURL else {
            portableContainerURL = nil
            return
        }
        let registered = await settingsModel.portableContainerURL(for: outputURL)
        guard self.outputURL?.standardizedFileURL == outputURL.standardizedFileURL else { return }
        if let registered { portableContainerURL = registered }
    }

    private var targetAssignment: TriptychAssignment? {
        settingsModel.registeredTriptychs.first(where: { $0.id == targetTriptychID })
    }

    private func assignedURL(for slot: WorkspaceVaultSlot) -> URL? {
        targetAssignment?.vault(for: slot).map {
            URL(fileURLWithPath: $0.canonicalPath, isDirectory: true)
        }
    }

    private func save() {
        guard let paperAnalysisURL, let topicKnowledgeURL, let outputURL else { return }
        guard let portableContainerURL else {
            errorMessage = String(
                localized: "Authorize the folder containing Works before saving this Triptych.",
                table: "Localizable", bundle: .module)
            return
        }
        let submittedName = triptychName
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await settingsModel.configureTriptych(
                    paperAnalysisURL: paperAnalysisURL,
                    topicKnowledgeURL: topicKnowledgeURL,
                    outputURL: outputURL,
                    portableContainerURL: portableContainerURL,
                    triptychID: targetTriptychID,
                    triptychName: submittedName
                )
                settingsModel.workspaceRecoveryMessage = nil
                isSaving = false
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PortableControlFolderRow: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    let worksURL: URL?
    @Binding var containerURL: URL?
    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
            HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
                Image(systemName: "folder.badge.gearshape")
                    .scholiumSymbolStyle(.prominent)
                    .foregroundStyle(.primary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                    Text("Folder Containing Works")
                        .font(.body)
                    Text("Authorizes portable settings stored beside Works")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(containerURL?.path(percentEncoded: false) ?? "Authorization required")
                        .font(.caption)
                        .foregroundStyle(containerURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: ScholiumMetrics.Settings.trailingControlMinimumSpacing)

                Button(containerURL == nil ? "Authorize…" : "Authorize Again…") {
                    authorizeFolder()
                }
                .disabled(worksURL == nil)
                .accessibilityLabel("Authorize folder containing Works")
            }
            if let selectionError {
                Text(selectionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .accessibilityIdentifier("scholium.portableControlAccess")
    }

    private func authorizeFolder() {
        guard
            let expected = worksURL?
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .standardizedFileURL
        else { return }
        let request = ScholiumFileSelectionRequest(
            title: ScholiumL10n.string("Authorize the Folder Containing Works"),
            message: String(
                format: ScholiumL10n.string(
                    "Choose '%@' so Scholium can use the portable .scholium folder beside Works."
                ),
                locale: Locale.current,
                expected.lastPathComponent
            ),
            prompt: ScholiumL10n.string("Authorize"),
            initialDirectoryURL: expected.deletingLastPathComponent(),
            kind: .directory(canCreateDirectories: false),
            constraint: .exactCanonicalDirectory(
                expected,
                rejectionMessage: ScholiumL10n.string(
                    "Choose the folder containing Works shown above."
                )
            )
        )
        Task { @MainActor in
            do {
                guard
                    let selected =
                        try await fileSelectionPresenter
                        .requiredForFileSelection()
                        .selectURL(request)
                else { return }
                selectionError = nil
                containerURL = selected
            } catch is CancellationError {
                return
            } catch {
                selectionError = error.localizedDescription
            }
        }
    }
}

struct WorkspaceFolderRow: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    let title: String
    @Binding var url: URL?
    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
            HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                    Text(localizedTitle)
                        .font(.body)
                    Text(url?.path(percentEncoded: false) ?? ScholiumL10n.string("No folder selected"))
                        .font(.caption)
                        .foregroundStyle(url == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url?.path(percentEncoded: false) ?? ScholiumL10n.string("Choose a folder"))
                }

                Spacer(minLength: ScholiumMetrics.Settings.trailingControlMinimumSpacing)

                Button(url == nil ? ScholiumL10n.string("Choose…") : ScholiumL10n.string("Change…")) {
                    chooseFolder()
                }
                .accessibilityLabel(Text(verbatim: chooseFolderAccessibilityLabel))
            }
            if let selectionError {
                Text(selectionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
    }

    private var localizedTitle: String {
        ScholiumL10n.dynamicString(title)
    }

    private var chooseFolderAccessibilityLabel: String {
        String(
            format: ScholiumL10n.string("Choose %@ Folder", locale: Locale.current),
            locale: Locale.current,
            localizedTitle
        )
    }

    private func chooseFolder() {
        var initialDirectoryURL = url?.deletingLastPathComponent()
        #if DEBUG
            if initialDirectoryURL == nil,
                let testDirectory = ProcessInfo.processInfo.environment[
                    "SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"
                ],
                !testDirectory.isEmpty
            {
                initialDirectoryURL = URL(fileURLWithPath: testDirectory, isDirectory: true)
            }
        #endif
        let request = ScholiumFileSelectionRequest(
            title: String(
                format: ScholiumL10n.string("Choose %@ Folder"),
                locale: Locale.current,
                localizedTitle
            ),
            prompt: ScholiumL10n.string("Choose"),
            initialDirectoryURL: initialDirectoryURL,
            kind: .directory(canCreateDirectories: true)
        )
        Task { @MainActor in
            do {
                guard
                    let selected =
                        try await fileSelectionPresenter
                        .requiredForFileSelection()
                        .selectURL(request)
                else { return }
                selectionError = nil
                url = selected
            } catch is CancellationError {
                return
            } catch {
                selectionError = error.localizedDescription
            }
        }
    }
}
