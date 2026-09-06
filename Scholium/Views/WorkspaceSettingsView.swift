import ScholiumContracts
import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ScholiumSettingsDestination: String, CaseIterable, Identifiable {
    case triptychs
    case appearance
    case hotkeys
    case metadata
    case attention
    case agentIntegration
    case externalToolsCitations

    var id: String { rawValue }

    static let application: [Self] = [
        .triptychs,
        .appearance,
        .hotkeys,
    ]

    static let triptych: [Self] = [
        .metadata,
        .attention,
    ]

    static let researchGuidance: [Self] = [
        .agentIntegration,
        .externalToolsCitations,
    ]

    var title: LocalizedStringResource {
        switch self {
        case .triptychs: ScholiumL10n.Settings.triptychs
        case .appearance: ScholiumL10n.Settings.appearance
        case .hotkeys: ScholiumL10n.Settings.hotkeys
        case .metadata: ScholiumL10n.Settings.metadata
        case .attention: ScholiumL10n.Settings.attention
        case .agentIntegration:
            ResearchGuidanceCategory.agentIntegration.localizedTitle
        case .externalToolsCitations:
            ResearchGuidanceCategory.externalToolsCitations.localizedTitle
        }
    }

    var toolbarTitle: String {
        switch self {
        case .agentIntegration: ScholiumL10n.string("Agents")
        case .externalToolsCitations: ScholiumL10n.string("Tools")
        default: String(localized: title)
        }
    }

    var symbol: String {
        switch self {
        case .triptychs: "rectangle.3.group"
        case .appearance: "paintbrush"
        case .hotkeys: "keyboard"
        case .metadata: "list.bullet.rectangle"
        case .attention: "bell"
        case .agentIntegration: ResearchGuidanceCategory.agentIntegration.symbol
        case .externalToolsCitations:
            ResearchGuidanceCategory.externalToolsCitations.symbol
        }
    }

    var pane: WorkspaceSettingsPane {
        switch self {
        case .triptychs: .triptychs
        case .metadata: .metadata
        case .appearance: .appearance
        case .hotkeys: .hotkeys
        case .attention: .attention
        case .agentIntegration,
             .externalToolsCitations:
            .researchGuidance
        }
    }

    var researchGuidanceCategory: ResearchGuidanceCategory? {
        switch self {
        case .agentIntegration: .agentIntegration
        case .externalToolsCitations: .externalToolsCitations
        case .triptychs, .metadata, .appearance, .hotkeys,
             .attention: nil
        }
    }

    var searchTerms: [String] {
        switch self {
        case .triptychs:
            ["Triptychs", "folders", "locations", "registration", "workspace"]
        case .appearance:
            ["Appearance", "document", "typeface", "font", "line width", "headings", "callouts", "CSS"]
        case .hotkeys:
            ["Hotkeys", "keyboard", "shortcuts", "commands", "menu"]
                + ScholiumHotkeyCommand.allCases.flatMap {
                    [String(localized: $0.title), String(localized: $0.menuPath)]
                }
        case .metadata:
            ["Metadata", "fields", "About", "optional fields"]
        case .attention:
            ["Notifications", "activities", "reminders", "dismissed items", "timing", "This Mac"]
        case .agentIntegration:
            ["Agent Integration", "MCP", "Codex", "Claude", "Core Protocol", "CLI", "bridge"]
        case .externalToolsCitations:
            ["External Tools & Citations", "CLI", "Zotero", "citation style", "integrations"]
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return searchTerms.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func restored(
        pane: WorkspaceSettingsPane,
        researchCategory: ResearchGuidanceCategory
    ) -> Self {
        switch pane {
        case .triptychs: .triptychs
        case .metadata: .metadata
        case .appearance: .appearance
        case .hotkeys: .hotkeys
        case .attention: .attention
        case .researchGuidance:
            switch researchCategory {
            case .agentIntegration: .agentIntegration
            case .externalToolsCitations: .externalToolsCitations
            }
        }
    }
}

struct ScholiumSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("scholium.settings.selectedPane") private var persistedPane = "triptychs"
    @AppStorage("scholium.settings.researchGuidanceCategory")
    private var persistedResearchCategory = ResearchGuidanceCategory.agentIntegration.rawValue
    @State private var destination = ScholiumSettingsDestination.triptychs
    @State private var searchQuery = ""

    var body: some View {
        // The scene supplies space; individual panes must not publish new
        // window size constraints while AppKit interpolates the frame.
        GeometryReader { _ in
            settingsContent
        }
        .frame(minWidth: 620, minHeight: 180)
    }

    private var settingsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                ScholiumSettingsSearchField(text: $searchQuery)
                    .frame(width: 180)
                    .accessibilityIdentifier("scholium.settings.search")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            if filteredDestinations.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
            settingsDetail
        }
        }
        .frame(minWidth: 620, maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(SettingsToolbarAttachment(destination: $destination))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.settings.root")
        .onAppear {
            let pane = WorkspaceSettingsPane(rawValue: persistedPane) ?? .triptychs
            let category = ResearchGuidanceCategory(
                rawValue: persistedResearchCategory
            ) ?? .agentIntegration
            destination = ScholiumSettingsDestination.restored(
                pane: pane,
                researchCategory: category
            )
            settingsModel.selectPane(destination.pane)
        }
        .onChange(of: destination) { _, destination in
            if !destination.matches(searchQuery) { searchQuery = "" }
            settingsModel.selectPane(destination.pane)
            persistedPane = destination.pane.rawValue
            if let category = destination.researchGuidanceCategory {
                persistedResearchCategory = category.rawValue
            }
        }
        .onChange(of: searchQuery) { _, query in
            guard !destination.matches(query),
                  let first = filteredDestinations.first else { return }
            destination = first
        }
    }

    private var filteredApplicationDestinations: [ScholiumSettingsDestination] {
        ScholiumSettingsDestination.application.filter { $0.matches(searchQuery) }
    }

    private var filteredTriptychDestinations: [ScholiumSettingsDestination] {
        ScholiumSettingsDestination.triptych.filter { $0.matches(searchQuery) }
    }

    private var filteredResearchGuidanceDestinations: [ScholiumSettingsDestination] {
        ScholiumSettingsDestination.researchGuidance.filter { $0.matches(searchQuery) }
    }

    private var filteredDestinations: [ScholiumSettingsDestination] {
        filteredApplicationDestinations
            + filteredTriptychDestinations
            + filteredResearchGuidanceDestinations
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch destination {
        case .triptychs:
            WorkspaceSettingsView()
        case .metadata:
            MetadataSettingsView()
        case .appearance:
            if let store = settingsModel.cssSnippetStore {
                AppearanceSettingsView(store: store)
            } else {
                ScholiumContentStateView(
                    "Appearance Unavailable",
                    detail: Text(
                        "Appearance profiles are unavailable in this Settings session."
                    ),
                    indicator: .symbol("paintbrush", role: .attention)
                )
                .padding(ScholiumGrid.Spacing.regionContentInset)
            }
        case .hotkeys:
            HotkeySettingsView(searchQuery: searchQuery)
        case .attention:
            AttentionSettingsView()
        case .agentIntegration:
            ResearchGuidanceSettingsView(category: .agentIntegration)
        case .externalToolsCitations:
            ResearchGuidanceSettingsView(category: .externalToolsCitations)
        }
    }
}

/// SwiftUI owns the selected destination; AppKit owns toolbar presentation and
/// window geometry. The coordinator forwards selection events only.
private struct SettingsToolbarAttachment: NSViewRepresentable {
    @Binding var destination: ScholiumSettingsDestination

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(window)
        }
        return view
    }

    func updateNSView(_ view: WindowAttachmentView, context: Context) {
        context.coordinator.parent = self
        if let window = view.window { context.coordinator.attach(window) }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        var parent: SettingsToolbarAttachment
        private weak var window: NSWindow?
        private var presented: ScholiumSettingsDestination?
        private let toolbar = NSToolbar(identifier: "scholium.settings.toolbar")

        init(parent: SettingsToolbarAttachment) {
            self.parent = parent
            super.init()
            toolbar.delegate = self
            toolbar.displayMode = .iconAndLabel
            toolbar.allowsUserCustomization = false
        }

        func attach(_ window: NSWindow) {
            if self.window !== window {
                self.window = window
                window.tabbingMode = .disallowed
                window.toolbar = toolbar
                window.toolbarStyle = .preference
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
                window.titlebarSeparatorStyle = .automatic
                window.backgroundColor = .windowBackgroundColor
                window.contentMinSize = NSSize(width: 620, height: 180)
            }
            let destination = parent.destination
            guard presented != destination else { return }
            let animate = presented != nil && window.isVisible
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            presented = destination
            toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(destination.rawValue)
            window.title = String(localized: destination.title)
            // Finish the SwiftUI layout transaction before starting native
            // geometry changes. Otherwise its hosting-window reconciliation
            // can overwrite an expanding frame animation with the end frame.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.presented == destination else { return }
                self.resize(window, for: destination, animate: animate)
            }
        }

        private func resize(_ window: NSWindow, for destination: ScholiumSettingsDestination, animate: Bool) {
            let size: NSSize
            switch destination {
            case .triptychs: size = NSSize(width: 760, height: 620)
            case .appearance: size = NSSize(width: 720, height: 550)
            case .hotkeys: size = NSSize(width: 760, height: 550)
            case .metadata: size = NSSize(width: 800, height: 560)
            case .attention: size = NSSize(width: 760, height: 330)
            case .agentIntegration: size = NSSize(width: 760, height: 380)
            case .externalToolsCitations: size = NSSize(width: 760, height: 300)
            }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.origin = NSPoint(x: window.frame.minX,
                                   y: window.frame.maxY - frame.height)
            if let screen = window.screen {
                let visible = screen.visibleFrame
                frame.size.width = min(frame.width, visible.width)
                frame.size.height = min(frame.height, visible.height)
                frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
                frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
            }
            // The animator retargets an in-flight resize without blocking the
            // SwiftUI update that installs the selected pane. Both frame edges
            // move together so the current top-left corner stays anchored.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animate ? 0.22 : 0
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.flexibleSpace] + ScholiumSettingsDestination.allCases.map {
                NSToolbarItem.Identifier($0.rawValue)
            } + [.flexibleSpace]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            ScholiumSettingsDestination.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
        }

        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            guard let destination = ScholiumSettingsDestination(rawValue: identifier.rawValue) else { return nil }
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = destination.toolbarTitle
            item.toolTip = String(localized: destination.title)
            item.image = NSImage(systemSymbolName: destination.symbol, accessibilityDescription: item.label)
            item.target = self
            item.action = #selector(selectPane(_:))
            return item
        }

        @objc private func selectPane(_ sender: NSToolbarItem) {
            guard let destination = ScholiumSettingsDestination(rawValue: sender.itemIdentifier.rawValue) else { return }
            parent.destination = destination
        }
    }
}

private struct AttentionSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var dismissalDays = TriptychSettings().attentionDismissalDays
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var dismissalLedgerData = Data()

    private let durations = [1, 3, 7, 14, 30]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsEditorSection("Reminder Timing for This Triptych") {
                    reminderTimingPicker
                    saveAttentionButton
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                Divider()
                settingsEditorSection("Dismissed Items on This Mac") {
                    Button("Restore All Dismissed Items on This Mac") {
                        var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
                        ledger.removeAll()
                        dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
                    }
                    .disabled(!hasDismissedAttention)
                    Text("Restores dismissed reminders on this Mac without changing Triptych data.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scholiumSettingsPaneSurface()
        .task {
            await settingsModel.refresh()
            let stored = settingsModel.triptychSettings.attentionDismissalDays
            dismissalDays = durations.contains(stored)
                ? stored
                : TriptychSettings().attentionDismissalDays
        }

    }

    private var hasDismissedAttention: Bool {
        let ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        return !ledger.dismissedUntilByItemID.isEmpty
    }

    private var reminderTimingPicker: some View {
        Picker("Return dismissed items after", selection: $dismissalDays) {
            ForEach(durations, id: \.self) { days in
                Text(days == 1 ? "1 day" : "\(days) days").tag(days)
            }
        }
        .scholiumActivationPointer()
        .frame(maxWidth: 300)
    }

    private var saveAttentionButton: some View {
        Button("Save Notification Settings") { save() }
            .buttonStyle(.bordered)
            .disabled(
                isSaving
                    || dismissalDays
                        == settingsModel.triptychSettings.attentionDismissalDays
            )
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        Task {
            do {
                var settings = settingsModel.triptychSettings
                settings.attentionDismissalDays = AttentionPreferences.normalizedDays(dismissalDays)
                let result = try await settingsModel.saveTriptychSettings(settings)
                dismissalDays = settings.attentionDismissalDays
                errorMessage = result.warning

            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct MetadataSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var selectedSlot: WorkspaceVaultSlot = .paperAnalysis
    @State private var metadataFields = TriptychSettings.defaultMetadataFields
    @State private var savedMetadataFields = TriptychSettings.defaultMetadataFields
    @State private var aboutConfigurations = TriptychSettings.defaultAbout
    @State private var savedAboutConfigurations = TriptychSettings.defaultAbout
    @State private var savedTriptychSettings = TriptychSettings()
    @State private var savedSettingsRevision: SettingsRevision?
    @State private var savedTriptychID: UUID?
    @State private var isSaving = false
    @State private var hasLoaded = false
    @State private var revisionConflict = false
    @State private var errorMessage: String?
    @State private var isAddingField = false
    @State private var newFieldKey = ""
    @State private var newFieldLabel = ""
    @State private var newFieldDescription = ""
    @State private var newFieldChoices = ""
    @State private var newFieldKind: PropertyValueKind = .text
    @State private var choiceDrafts: [String: String] = [:]
    @State private var selectedVisibleField: String?

    private var selectedProfile: SchemaProfileID {
        switch selectedSlot {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
    }

    private var recommendedKeys: [String] {
        PropertyPresentationCatalog.presentations(
            for: selectedProfile,
            catalog: candidateCatalog
        )
            .map(\.key)
            .filter {
                AboutProfileCatalog.allowsOptionalField(
                    $0,
                    profile: selectedProfile,
                    catalog: candidateCatalog
                )
            }
    }

    private var availableKeys: [String] {
        let configuration = selectedConfiguration
        return Array(Set(
            configuration.visibleFields
                + recommendedKeys
        ))
            .sorted { displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending }
    }

    private var selectedConfiguration: VaultAboutConfiguration {
        var configuration = aboutConfigurations[selectedSlot]
            ?? TriptychSettings.defaultAbout[selectedSlot]
            ?? VaultAboutConfiguration()
        configuration.visibleFields.removeAll {
            !AboutProfileCatalog.allowsOptionalField(
                $0,
                profile: selectedProfile,
                catalog: candidateCatalog
            )
        }
        return configuration
    }

    private var candidateCatalog: NoteMetadataCatalog {
        NoteMetadataCatalog(customFieldsByRole: metadataFields)
    }

    private var candidateSettings: TriptychSettings {
        MetadataSettingsCandidateBuilder.build(
            from: savedTriptychSettings,
            metadataFields: metadataFields,
            aboutConfigurations: aboutConfigurations
        )
    }

    private var validationMessage: String? {
        validationDiagnostic?.displayMessage
    }

    private struct SettingsDiagnostic {
        enum Section {
            case fieldDefinitions
            case configuration
            case other
        }

        let section: Section
        let role: WorkspaceVaultSlot?
        let sourceType: AnalysisSourceType?
        let key: String?
        let line: Int?
        let column: Int?
        let reason: String
        let repair: String

        var displayMessage: String {
            var context: [String] = []
            if let role {
                switch role {
                case .paperAnalysis: context.append(String(localized: "Analysis", table: "Localizable", bundle: .module))
                case .topicKnowledge: context.append(String(localized: "Topic", table: "Localizable", bundle: .module))
                case .output: context.append(String(localized: "Work", table: "Localizable", bundle: .module))
                }
            }
            if let sourceType { context.append(sourceType.propertyDisplayName) }
            if let key { context.append(key) }
            if let line, let column {
                context.append(String(localized: "Line \(line), column \(column)", table: "Localizable", bundle: .module))
            }
            return (context.isEmpty ? "" : context.joined(separator: " · ") + ": ")
                + reason + " " + repair
        }
    }

    private var validationDiagnostic: SettingsDiagnostic? {
        do {
            try TriptychSettingsValidator.validate(candidateSettings)
            return nil
        } catch let error as TriptychSettingsValidationError {
            return diagnostic(for: error)
        } catch {
            return SettingsDiagnostic(
                section: .other,
                role: nil,
                sourceType: nil,
                key: nil,
                line: nil,
                column: nil,
                reason: String(localized: "The complete Metadata settings candidate could not be validated.", table: "Localizable", bundle: .module),
                repair: String(localized: "Review the complete Metadata settings candidate before saving.", table: "Localizable", bundle: .module)
            )
        }
    }

    private var isDirty: Bool {
        candidateSettings != savedTriptychSettings
    }

    var body: some View {
        Group {
            if settingsModel.hasWritableTriptychSettings {
                writableSettingsContent
            } else {
                unavailableSettingsContent
            }
        }
        .task {
            await settingsModel.refresh()
            loadSavedSettingsIfNeeded()
        }
        .onChange(of: settingsModel.snapshot) { _, snapshot in
            if isDirty {
                if snapshot.activeTriptychID != savedTriptychID
                    || snapshot.portableSettingsState.editableRevision
                        != savedSettingsRevision {
                    revisionConflict = true
                }
                return
            }
            installSavedDraft(snapshot)
        }
    }

    private var writableSettingsContent: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.sectionSpacing) {
            if case .needsReview = settingsModel.portableSettingsState {
                Label(
                    "These current-schema settings need review before managed creation can resume.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let refreshError = settingsModel.errorMessage {
                Label(
                    "Settings refresh failed. The last confirmed settings remain visible. \(refreshError)",
                    systemImage: "arrow.clockwise.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            settingsEditorSection("Metadata role") {
            Picker("Metadata role", selection: $selectedSlot) {
                Text("Analysis").tag(WorkspaceVaultSlot.paperAnalysis)
                Text("Topic").tag(WorkspaceVaultSlot.topicKnowledge)
                Text("Work").tag(WorkspaceVaultSlot.output)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("scholium.metadataSettings.role")
            .disabled(isAddingField)

                Text("This Triptych").font(.callout).foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    fieldDefinitionsSection
                    Divider()
                    displayOrderColumn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let diagnostic = validationDiagnostic {
                settingsValidationSummary(diagnostic)
            }

            persistenceStateNotice

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    restoreActions
                    Spacer()
                    revertAndSaveActions
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    restoreActions
                    revertAndSaveActions
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .disabled(isSaving)
    }

    private var unavailableSettingsContent: some View {
        ScholiumContentStateView(
            unavailableSettingsTitle,
            detail: settingsModel.errorMessage.map(Text.init(verbatim:))
                ?? Text(unavailableSettingsDetail),
            indicator: .symbol("slider.horizontal.3", role: .attention)
        ) {
            Button("Retry Metadata Settings") {
                Task { await settingsModel.refresh() }
            }
            .disabled(settingsModel.isRefreshing)
        }
        .padding(ScholiumMetrics.Settings.editorContentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var unavailableSettingsTitle: LocalizedStringResource {
        switch settingsModel.portableSettingsState {
        case .unavailable: "Metadata Settings Require a Complete Triptych"
        case .missing: "Portable Metadata Settings Are Missing"
        case .oldSchema: "Metadata Settings Use an Older Schema"
        case .futureSchema: "Metadata Settings Use a Newer Schema"
        case .corrupted: "Metadata Settings Are Damaged"
        case .current, .needsReview: "Metadata Settings Need Attention"
        }
    }

    private var unavailableSettingsDetail: LocalizedStringResource {
        switch settingsModel.portableSettingsState {
        case .unavailable:
            "Open or configure a complete Triptych before changing portable metadata settings."
        case .missing:
            "The settings file is missing. Existing research notes remain unchanged, and managed creation stays unavailable until the file is restored."
        case .oldSchema(let version):
            "The exact settings bytes were preserved, but schema \(version.map(String.init) ?? "without a version") is not supported."
        case .futureSchema(let version):
            "The exact settings bytes were preserved. This Scholium build cannot edit future schema \(version)."
        case .corrupted:
            "The exact settings bytes were preserved for recovery. Scholium will not replace them with defaults."
        case .current, .needsReview:
            "Reload the portable settings before editing."
        }
    }

    @ViewBuilder
    private var persistenceStateNotice: some View {
        if revisionConflict {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("The saved metadata settings changed after this draft was loaded. The saved version and this draft were both preserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Reload Saved Settings") {
                    Task { await reloadSavedSettings() }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fieldDefinitionsSection: some View {
        settingsEditorSection("Managed Fields") {
            Text("Field keys and types are permanent. Archiving preserves stored values.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let definitions = metadataFields[selectedSlot] ?? []
            if definitions.isEmpty {
                Text("No custom fields. Built-in fields remain available.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Settings.listRowSpacing
                ) {
                    ForEach(definitions, id: \.key) { definition in
                        managedFieldRow(definition)
                    }
                }
            }

            if isAddingField {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    TextField("Field Key", text: $newFieldKey, prompt: Text("research_stage"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Managed field key")
                        .accessibilityIdentifier("scholium.metadataSettings.fieldKey")
                    TextField("Display Name", text: $newFieldLabel, prompt: Text("Research Stage"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Managed field display name")
                    TextField("Description (Optional)", text: $newFieldDescription)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Managed field description")
                    Picker("Value Type", selection: $newFieldKind) {
                        ForEach(customFieldKinds, id: \.self) { kind in
                            Text(displayName(for: kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("scholium.metadataSettings.valueType")
                    if newFieldKind == .choice {
                        TextField(
                            "Choices (One Per Line)",
                            text: $newFieldChoices,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Controlled choices, one per line")
                    }
                    if let message = newFieldValidationMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Button("Cancel") { cancelAddingField() }
                            .keyboardShortcut(.escape)
                        Button("Add Field") { addFieldDefinition() }
                            .buttonStyle(.bordered)
                            .disabled(newFieldValidationMessage != nil)
                            .accessibilityIdentifier("scholium.metadataSettings.commitField")
                    }
                }
                .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
            } else {
                Button("Add Field…") {
                    isAddingField = true
                }
                .accessibilityIdentifier("scholium.metadataSettings.addField")
            }
        }
    }

    private var customFieldKinds: [PropertyValueKind] {
        [.text, .multilineText, .textList, .number, .boolean, .date, .choice]
    }

    @ViewBuilder
    private func managedFieldRow(_ definition: MetadataFieldDefinition) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.Settings.rowControlSpacing) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                    TextField("Display Name", text: definitionLabelBinding(definition.key))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Display name for \(definition.key)")
                    Text(definition.key)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: ScholiumMetrics.Settings.labelActionMinimumSpacing)
                VStack(alignment: .trailing, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                    Text(displayName(for: definition.valueKind))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(definition.lifecycle == .active ? "Active" : "Archived")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            TextField(
                "Description (Optional)",
                text: definitionDescriptionBinding(definition.key)
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Description for \(definition.key)")

            if definition.valueKind == .choice {
                ForEach(definition.allowedValues ?? [], id: \.self) { choice in
                    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Text(choice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Move Up") {
                            moveChoice(choice, in: definition.key, by: -1)
                        }
                        .disabled(!canMoveChoice(choice, in: definition.key, by: -1))
                        .accessibilityLabel("Move \(choice) up")
                        Button("Move Down") {
                            moveChoice(choice, in: definition.key, by: 1)
                        }
                        .disabled(!canMoveChoice(choice, in: definition.key, by: 1))
                        .accessibilityLabel("Move \(choice) down")
                    }
                }
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    TextField(
                        "Add Choice",
                        text: choiceDraftBinding(definition.key)
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("New controlled choice for \(definition.key)")
                    Button("Add Choice") { appendChoice(to: definition.key) }
                        .disabled(!canAppendChoice(to: definition.key))
                }
            }

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Used in \(metadataUsageCount(for: definition.key)) Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Move Up") {
                    moveField(definition.key, by: -1)
                }
                .disabled(!canMoveField(definition.key, by: -1))
                .accessibilityLabel("Move \(definition.label) up")
                Button("Move Down") {
                    moveField(definition.key, by: 1)
                }
                .disabled(!canMoveField(definition.key, by: 1))
                .accessibilityLabel("Move \(definition.label) down")
                Button(definition.lifecycle == .active ? "Archive Field" : "Restore Field") {
                    setLifecycle(
                        definition.lifecycle == .active ? .archived : .active,
                        for: definition.key
                    )
                }
                .accessibilityHint(
                    definition.lifecycle == .active
                        ? "Stops offering this field for new values without deleting stored values."
                        : "Offers this field for new values again."
                )
            }
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
    }

    private var newFieldValidationMessage: String? {
        guard isAddingField else { return nil }
        guard !newFieldKey.isEmpty else {
            return String(
                localized: "Use a unique lowercase snake_case key.",
                table: "Localizable",
                bundle: .module
            )
        }
        var candidate = metadataFields
        candidate[selectedSlot, default: []].append(MetadataFieldDefinition(
            key: newFieldKey,
            valueKind: newFieldKind,
            label: newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : newFieldLabel,
            description: normalizedOptionalText(newFieldDescription),
            allowedValues: newFieldKind == .choice ? parsedNewFieldChoices : nil
        ))
        do {
            try TriptychSettingsValidator.validateMetadataFieldDefinitions(candidate)
            return nil
        } catch let error as TriptychSettingsValidationError {
            return diagnostic(for: error).displayMessage
        } catch {
            return String(
                localized: "The complete Metadata settings candidate could not be validated.",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    private func addFieldDefinition() {
        guard newFieldValidationMessage == nil else { return }
        metadataFields[selectedSlot, default: []].append(MetadataFieldDefinition(
            key: newFieldKey,
            valueKind: newFieldKind,
            label: newFieldLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : newFieldLabel,
            description: normalizedOptionalText(newFieldDescription),
            allowedValues: newFieldKind == .choice ? parsedNewFieldChoices : nil
        ))
        cancelAddingField()
    }

    private func cancelAddingField() {
        isAddingField = false
        newFieldKey = ""
        newFieldLabel = ""
        newFieldDescription = ""
        newFieldChoices = ""
        newFieldKind = .text
    }

    private var parsedNewFieldChoices: [String] {
        newFieldChoices.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedOptionalText(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func definitionLabelBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { definition(for: key)?.label ?? MetadataFieldDefinition.defaultLabel(for: key) },
            set: { value in updateDefinition(key) { $0.label = value } }
        )
    }

    private func definitionDescriptionBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { definition(for: key)?.description ?? "" },
            set: { value in updateDefinition(key) { $0.description = normalizedOptionalText(value) } }
        )
    }

    private func choiceDraftBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { choiceDrafts[key] ?? "" },
            set: { choiceDrafts[key] = $0 }
        )
    }

    private func definition(for key: String) -> MetadataFieldDefinition? {
        metadataFields[selectedSlot]?.first { $0.key == key }
    }

    private func updateDefinition(
        _ key: String,
        _ update: (inout MetadataFieldDefinition) -> Void
    ) {
        guard var definitions = metadataFields[selectedSlot],
              let index = definitions.firstIndex(where: { $0.key == key }) else { return }
        update(&definitions[index])
        metadataFields[selectedSlot] = definitions
    }

    private func canMoveField(_ key: String, by offset: Int) -> Bool {
        guard let definitions = metadataFields[selectedSlot],
              let index = definitions.firstIndex(where: { $0.key == key }) else { return false }
        return definitions.indices.contains(index + offset)
    }

    private func moveField(_ key: String, by offset: Int) {
        guard var definitions = metadataFields[selectedSlot],
              let source = definitions.firstIndex(where: { $0.key == key }),
              definitions.indices.contains(source + offset) else { return }
        let definition = definitions.remove(at: source)
        definitions.insert(definition, at: source + offset)
        metadataFields[selectedSlot] = definitions
    }

    private func canMoveChoice(_ choice: String, in key: String, by offset: Int) -> Bool {
        guard let choices = definition(for: key)?.allowedValues,
              let index = choices.firstIndex(of: choice) else { return false }
        return choices.indices.contains(index + offset)
    }

    private func moveChoice(_ choice: String, in key: String, by offset: Int) {
        updateDefinition(key) { definition in
            guard var choices = definition.allowedValues,
                  let source = choices.firstIndex(of: choice),
                  choices.indices.contains(source + offset) else { return }
            let moved = choices.remove(at: source)
            choices.insert(moved, at: source + offset)
            definition.allowedValues = choices
        }
    }

    private func setLifecycle(_ lifecycle: MetadataFieldLifecycle, for key: String) {
        updateDefinition(key) { $0.lifecycle = lifecycle }
    }

    private func metadataUsageCount(for key: String) -> Int {
        settingsModel.snapshot.metadataUsageCounts[selectedSlot]?[key] ?? 0
    }

    private func canAppendChoice(to key: String) -> Bool {
        guard let definition = definition(for: key) else { return false }
        let value = choiceDrafts[key, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty
            && value.utf8.count <= 128
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && !(definition.allowedValues ?? []).contains(value)
    }

    private func appendChoice(to key: String) {
        guard canAppendChoice(to: key) else { return }
        let value = choiceDrafts[key, default: ""]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        updateDefinition(key) { definition in
            definition.allowedValues = (definition.allowedValues ?? []) + [value]
        }
        choiceDrafts[key] = ""
    }

    private struct VisibleFieldRow: Identifiable {
        let key: String
        let group: PropertyPresentationGroup
        let peers: [String]
        let position: Int
        var id: String { key }
    }

    private var visibleFieldRows: [VisibleFieldRow] {
        aboutConfigurationGroups.flatMap { group in
            group.keys.enumerated().map { index, key in
                VisibleFieldRow(key: key, group: group.group, peers: group.keys, position: index)
            }
        }
    }

    private var displayOrderColumn: some View {
        settingsEditorSection("Always Shown in About") {
            Table(visibleFieldRows, selection: $selectedVisibleField) {
                TableColumn("Field") { row in
                    Text(displayName(for: row.key)).help(row.key)
                }
                TableColumn("Group") { row in
                    Text(row.group.label).foregroundStyle(.secondary)
                }
                .width(110)

            }
            .tableStyle(.inset)
            .frame(height: min(280, max(100, CGFloat(visibleFieldRows.count) * 28 + 30)))
            visibleFieldActions
                Menu("Always Show Field") {
                    if hiddenAboutConfigurationGroups.isEmpty {
                        Text("All available fields are always shown")
                    } else {
                        ForEach(hiddenAboutConfigurationGroups, id: \.group) { group in
                            Section(group.group.label) {
                                ForEach(group.keys, id: \.self) { key in
                                    Button(displayName(for: key)) {
                                        updateSelectedConfiguration {
                                            $0.setVisible(true, field: key)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
        }
    }

    private var visibleFieldActions: some View {
        let row = visibleFieldRows.first { $0.key == selectedVisibleField }
        return ControlGroup {
            Button {
                guard let row else { return }
                moveVisibleField(row.key, within: row.peers, to: row.position - 1)
            } label: { Label("Move Up", systemImage: "chevron.up") }
            .disabled(row == nil || row?.position == 0)
            Button {
                guard let row else { return }
                moveVisibleField(row.key, within: row.peers, to: row.position + 1)
            } label: { Label("Move Down", systemImage: "chevron.down") }
            .disabled(row == nil || row?.position == (row?.peers.count ?? 0) - 1)
            Button {
                guard let row else { return }
                updateSelectedConfiguration { $0.setVisible(false, field: row.key) }
            } label: { Label("Show Only When Populated", systemImage: "minus") }
            .disabled(row == nil)
        }
        .labelStyle(.iconOnly)
        .fixedSize()
    }

    private var restoreActions: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Restore Always-Shown Defaults") {
                guard let defaults = TriptychSettings.defaultAbout[selectedSlot] else {
                    return
                }
                var configuration = selectedConfiguration
                configuration.visibleFields = defaults.visibleFields
                aboutConfigurations[selectedSlot] = configuration
            }
        }
    }

    private var revertAndSaveActions: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Revert to Saved") { revertToSaved() }
                .disabled(!isDirty)
            Button("Save Metadata Settings") { save() }
                .buttonStyle(.bordered)
                    .disabled(
                        isSaving || !isDirty || validationMessage != nil
                            || revisionConflict
                            || settingsModel.requiresSettingsReconciliation(
                                for: savedTriptychID
                            )
                    )
        }
    }

    private func settingsValidationSummary(
        _ diagnostic: SettingsDiagnostic
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Label(diagnostic.displayMessage, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scholium.metadataSettings.validation")
            if diagnostic.role != nil || diagnostic.sourceType != nil {
                Button("Review Invalid Setting") {
                    reveal(diagnostic)
                }
            }
        }
    }

    private var aboutConfigurationGroups: [AboutProfileGroup] {
        AboutProfileCatalog.groupedEntries(
            for: selectedProfile,
            visibleFields: selectedConfiguration.visibleFields,
            catalog: candidateCatalog
        )
    }

    private var hiddenAboutConfigurationGroups: [AboutProfileGroup] {
        let hidden = availableKeys.filter {
            AboutProfileCatalog.allowsOptionalField(
                $0,
                profile: selectedProfile,
                catalog: candidateCatalog
            )
                && !selectedConfiguration.visibleFields.contains($0)
        }
        return AboutProfileCatalog.groupedEntries(
            for: selectedProfile,
            visibleFields: hidden,
            catalog: candidateCatalog
        )
    }

    private func updateSelectedConfiguration(
        _ update: (inout VaultAboutConfiguration) -> Void
    ) {
        var configuration = selectedConfiguration
        update(&configuration)
        aboutConfigurations[selectedSlot] = configuration
    }

    private func moveVisibleField(_ field: String, within group: [String], to index: Int) {
        guard group.contains(field), group.indices.contains(index) else {
            return
        }
        let destinationKey = group[index]
        updateSelectedConfiguration { configuration in
            guard let sourceIndex = configuration.visibleFields.firstIndex(of: field),
                  let destinationIndex = configuration.visibleFields.firstIndex(of: destinationKey)
            else { return }
            configuration.visibleFields.swapAt(sourceIndex, destinationIndex)
        }
    }

    private func displayName(for key: String) -> String {
        if let presentation = PropertyPresentationCatalog.presentation(
            for: key,
            in: selectedProfile,
            catalog: candidateCatalog
        ) {
            return presentation.label
        }
        return key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func displayName(for kind: PropertyValueKind) -> String {
        switch kind {
        case .text: "Text"
        case .multilineText: "Multiline Text"
        case .textList: "Text List"
        case .number: "Number"
        case .boolean: "Checkbox"
        case .date: "Date Text"
        case .tags: "Tags"
        case .choice: "Choice"
        case .mapping: "Mapping"
        case .creatorList: "Creators"
        }
    }

    private func save() {
        guard validationMessage == nil,
              let triptychID = savedTriptychID,
              let revision = savedSettingsRevision,
              settingsModel.snapshot.activeTriptychID == triptychID,
              settingsModel.settingsRevision == revision else {
            revisionConflict = true
            return
        }
        isSaving = true
        revisionConflict = settingsModel.settingsRevision != savedSettingsRevision
        errorMessage = nil
        Task {
            do {
                let result = try await settingsModel.saveTriptychSettings(
                    candidateSettings,
                    targetTriptychID: triptychID,
                    expectedRevision: revision
                )
                if result.targetIsCurrent {
                    installSavedDraft(settingsModel.snapshot)
                } else {
                    revisionConflict = true
                    errorMessage = result.warning
                }
                errorMessage = result.warning

            } catch TriptychControlError.settingsRevisionConflict {
                revisionConflict = true
            } catch WorkspaceSettingsMutationError.triptychChanged {
                revisionConflict = true
            } catch WorkspaceSettingsMutationError.commitRequiresReview {
                revisionConflict = true
                errorMessage = String(localized: "Scholium reread the portable settings after an uncertain save. Review the current saved version before trying again.", table: "Localizable", bundle: .module)
            } catch WorkspaceSettingsMutationError.reconciliationRequired {
                revisionConflict = true
                errorMessage = String(localized: "Portable settings must be reread successfully before another save can be attempted.", table: "Localizable", bundle: .module)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func loadSavedSettingsIfNeeded() {
        guard !hasLoaded else { return }
        installSavedDraft(settingsModel.snapshot)
        hasLoaded = true
    }

    private func installSavedDraft(_ snapshot: WorkspaceSettingsSnapshot) {
        let settings = snapshot.triptychSettings
        metadataFields = settings.metadataFields
        savedMetadataFields = settings.metadataFields
        aboutConfigurations = settings.about
        savedAboutConfigurations = settings.about
        savedTriptychSettings = settings
        savedTriptychID = snapshot.activeTriptychID
        savedSettingsRevision = snapshot.portableSettingsState.editableRevision
        revisionConflict = settingsModel.snapshot.activeTriptychID != savedTriptychID
            || settingsModel.settingsRevision != savedSettingsRevision
        errorMessage = nil
    }

    private func revertToSaved() {
        metadataFields = savedMetadataFields
        aboutConfigurations = savedAboutConfigurations
        cancelAddingField()
        revisionConflict = settingsModel.snapshot.activeTriptychID != savedTriptychID
            || settingsModel.settingsRevision != savedSettingsRevision
        errorMessage = nil
    }

    private func reloadSavedSettings() async {
        guard await settingsModel.refresh() else {
            errorMessage = settingsModel.errorMessage
            return
        }
        installSavedDraft(settingsModel.snapshot)
    }

    private func diagnostic(
        for error: TriptychSettingsValidationError
    ) -> SettingsDiagnostic {
        let role: WorkspaceVaultSlot?
        let sourceType: AnalysisSourceType?
        let key: String?
        let section: SettingsDiagnostic.Section
        let diagnosticReason: String
        let repair: String
        switch error {
        case .incompleteRoleConfiguration:
            role = nil; sourceType = nil; key = nil
            section = .configuration
            diagnosticReason = String(localized: "The Metadata settings candidate is missing a Triptych role.", table: "Localizable", bundle: .module)
            repair = String(localized: "Restore the missing role configuration.", table: "Localizable", bundle: .module)
        case .invalidMetadataFieldDefinition(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "This custom Metadata key is invalid or duplicated.", table: "Localizable", bundle: .module)
            repair = String(localized: "Use a unique lowercase snake_case key.", table: "Localizable", bundle: .module)
        case .metadataFieldShadowsReservedKey(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "This custom Metadata key is already owned by Scholium or authored YAML.", table: "Localizable", bundle: .module)
            repair = String(localized: "Choose a different key.", table: "Localizable", bundle: .module)
        case .metadataFieldKindUnsupported(let value, let field, _):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "This custom Metadata value type is unsupported.", table: "Localizable", bundle: .module)
            repair = String(localized: "Choose one of the available simple value types.", table: "Localizable", bundle: .module)
        case .invalidMetadataFieldLabel(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "This custom Metadata display name is invalid.", table: "Localizable", bundle: .module)
            repair = String(localized: "Use a nonempty display name of at most 80 UTF-8 bytes.", table: "Localizable", bundle: .module)
        case .invalidMetadataFieldDescription(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "This custom Metadata description is invalid.", table: "Localizable", bundle: .module)
            repair = String(localized: "Use one line of at most 240 UTF-8 bytes, or leave it blank.", table: "Localizable", bundle: .module)
        case .invalidMetadataFieldChoices(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "This custom Metadata field has invalid controlled choices.", table: "Localizable", bundle: .module)
            repair = String(localized: "Provide unique nonempty choices. Existing choices must remain available.", table: "Localizable", bundle: .module)
        case .metadataFieldIdentityChanged(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "This custom Metadata field's stable key or value type changed, or the field was removed.", table: "Localizable", bundle: .module)
            repair = String(localized: "Restore its identity and use Archive Field to stop offering it.", table: "Localizable", bundle: .module)
        case .metadataFieldChoicesRemoved(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "An existing controlled choice was removed.", table: "Localizable", bundle: .module)
            repair = String(localized: "Restore every existing controlled choice. Their order may change.", table: "Localizable", bundle: .module)
        case .noncanonicalConfigurationField(let value, let field):
            role = value; sourceType = nil; key = field
            section = .configuration
            diagnosticReason = String(localized: "This configuration field is blank, duplicated, or unnormalized.", table: "Localizable", bundle: .module)
            repair = String(localized: "Remove the blank or duplicate field entry.", table: "Localizable", bundle: .module)
        case .invalidAttentionDismissalDays:
            role = nil; sourceType = nil; key = nil
            section = .other
            diagnosticReason = String(localized: "Attention dismissal days must be positive.", table: "Localizable", bundle: .module)
            repair = String(localized: "Repair Attention settings before saving Metadata settings.", table: "Localizable", bundle: .module)
        }
        return SettingsDiagnostic(
            section: section,
            role: role,
            sourceType: sourceType,
            key: key,
            line: nil,
            column: nil,
            reason: diagnosticReason,
            repair: repair
        )
    }

    private func reveal(_ diagnostic: SettingsDiagnostic) {
        if let role = diagnostic.role { selectedSlot = role }
    }

}

struct ZoteroSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var info = ZoteroLibraryInfo(status: .appUnavailable, lastSuccessfulConnection: nil)
    @State private var isTesting = false
    @State private var errorMessage: String?

    var body: some View {
        researchSettingsSection("Zotero") {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                LabeledContent("Local API") {
                    Label(statusTitle, systemImage: statusSymbol)
                        .foregroundStyle(.primary)
                }
                LabeledContent("Last Connected") {
                    Text(info.lastSuccessfulConnection?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
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
                Text("Scholium connects only to Zotero Desktop on localhost and never modifies its data. No account or API key is required.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                if info.status == .apiDisabled {
                    Text("In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’, then test again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .task { info = await settingsModel.zoteroConnectionInfo() }
    }

    @ViewBuilder
    private var zoteroActions: some View {
        Button("Open Zotero") {
            Task { await settingsModel.openZotero() }
        }
        .scholiumActivationPointer()
        Button("Check Connection") { refresh() }
            .disabled(isTesting)
        Button("Clear History", role: .destructive) {
            Task {
                try? await settingsModel.clearZoteroConnectionHistory()
                info = await settingsModel.zoteroConnectionInfo()
            }
        }
        .scholiumActivationPointer()
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
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTriptychID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            settingsEditorSection("Triptych") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ScholiumMetrics.Settings.rootSpacing) {
                        triptychPicker.labelsHidden().fixedSize().frame(width: 180, alignment: .leading)
                        Spacer(minLength: 8)
                        triptychActions
                    }
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumGrid.Spacing.labelAccessoryGap
                    ) {
                        triptychPicker.labelsHidden()
                        triptychActions
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)

            Divider()

            if let selectedTriptychID {
                WorkspacePathEditor(
                    completionTitle: "Save Triptych",
                    targetTriptychID: selectedTriptychID,
                    showsCancel: false,
                    onCompletion: nil
                )
                .id(selectedTriptychID)
            } else {
                ScholiumContentStateView(
                    "No Triptych Registered",
                    detail: Text("Create a Triptych by choosing Analyses, Topics, and Works folders."),
                    indicator: .symbol("rectangle.3.group")
                )
            }
        }
        .scholiumSettingsPaneSurface()
        .task {
            await settingsModel.refreshRegisteredVaults()
            if selectedTriptychID == nil {
                selectedTriptychID = settingsModel.workspaceAssignment?.id
                    ?? settingsModel.registeredTriptychs.first?.id
            }
        }
        .onChange(of: settingsModel.snapshot.activeTriptychID) { _, activeID in
            selectedTriptychID = activeID
        }
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
                Text(settingsTriptychLabel(
                    assignment,
                    among: settingsModel.registeredTriptychs
                ))
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
            openWindow(
                id: "scholium-main",
                value: TriptychWindowRoute(triptychID: selectedTriptychID)
            )
        }
        .scholiumActivationPointer()
        .disabled(selectedTriptychID == nil)

        Button("New Triptych…") {
            openWindow(
                id: "scholium-bootstrap",
                value: BootstrapWindowRoute(purpose: .newTriptych)
            )
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
          let works = assignment.vault(for: .output) else {
        return assignment.triptych.name
    }
    let parent = URL(fileURLWithPath: works.canonicalPath, isDirectory: true)
        .deletingLastPathComponent().lastPathComponent
    return "\(assignment.triptych.name) — \(parent)"
}

private struct AppearanceSettingsView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @ObservedObject var store: CSSSnippetStore
    @State private var draft: DocumentAppearanceProfile?
    @State private var importError: String?
    @State private var showRename = false
    @State private var showDeleteConfirmation = false
    @State private var showRestoreDefaultConfirmation = false
    @State private var showDiscardChangesConfirmation = false
    @State private var pendingProfileSelection: UUID?
    @State private var nameDraft = ""

    @State private var showsCSSSnippets = false
    @State private var confirmsConfigurationReload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    configurationSection

                    Divider()

                    if let draftBinding {
                        AppearanceProfileEditor(profile: draftBinding)
                    }

                    Divider()

                    settingsEditorSection("Configuration File") {
                        HStack {
                            Button("Show in Finder…") { store.revealAppearanceConfiguration() }
                            Button("Reload") {
                                if hasUnsavedChanges { confirmsConfigurationReload = true }
                                else { store.reloadAppearanceConfiguration() }
                            }
                        }
                        HStack {
                            Button("Configuration Guide…") {
                                if let url = Bundle.module.url(forResource: "AppearanceConfiguration", withExtension: "md") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            Button("CSS Snippets…") { showsCSSSnippets = true }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 760, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("scholium.appearance.form")

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
            Divider()
            appearanceSaveActions
        }
        .scholiumSettingsPaneSurface()
        .onAppear { loadSelectedDraft() }
        .onChange(of: store.selectedAppearanceProfileID) { _, _ in loadSelectedDraft() }
        .onChange(of: store.appearanceProfiles) { _, _ in loadSelectedDraft() }
        .onChange(of: store.appearanceReloadRevision) { _, _ in loadSelectedDraft() }
        .sheet(isPresented: $showsCSSSnippets) {
            VStack(alignment: .leading, spacing: 16) {
                Text("CSS Snippets").font(.headline)
                ScrollView { cssSnippetsContent }
                if let error = importError ?? store.storeError {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.red)
                }
                HStack { Spacer(); Button("Done") { showsCSSSnippets = false }.keyboardShortcut(.cancelAction) }
            }
            .padding(.horizontal, 24)
                .padding(.vertical, 16)
            .frame(width: 600, height: 360)
        }
        .confirmationDialog("Reload Appearance Configuration?", isPresented: $confirmsConfigurationReload, titleVisibility: .visible) {
            Button("Reload", role: .destructive) { store.reloadAppearanceConfiguration() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reloading replaces your unsaved appearance draft with the configuration file. An invalid file leaves the draft unchanged.")
        }
        .alert("Rename Appearance", isPresented: $showRename) {
            TextField("Configuration name", text: $nameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let id = store.selectedAppearanceProfileID else { return }
                store.renameAppearance(id, to: nameDraft)
                draft?.name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
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
            Text("This removes the selected configuration from this Mac. Research documents are not changed.")
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
            Text("This replaces the current draft with Scholium’s built-in document appearance. Choose Save to keep it.")
        }
        .confirmationDialog(
            "Discard Unsaved Appearance Changes?",
            isPresented: $showDiscardChangesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard and Switch", role: .destructive) {
                guard let id = pendingProfileSelection else { return }
                pendingProfileSelection = nil
                selectProfile(id)
            }
            Button("Cancel", role: .cancel) {
                pendingProfileSelection = nil
            }
        } message: {
            Text("The selected appearance has unsaved changes. Switching configurations will discard them.")
        }
    }

    private var selectedProfileID: Binding<UUID?> {
        Binding(
            get: { store.selectedAppearanceProfileID },
            set: { id in
                guard let id else { return }
                if hasUnsavedChanges {
                    pendingProfileSelection = id
                    showDiscardChangesConfirmation = true
                } else {
                    selectProfile(id)
                }
            }
        )
    }

    private var configurationSection: some View {
        settingsEditorSection("Configuration") {
            HStack(spacing: 12) {
                appearancePicker
                appearanceManagementMenu
            }
            Text("Stored on this Mac")
                .font(.callout)
                .foregroundStyle(.secondary)
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
            Button("Save") {
                guard let draft else { return }
                store.updateAppearance(draft)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!hasUnsavedChanges || !store.canModify)
            .accessibilityLabel("Save Appearance")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var cssSnippetsContent: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ForEach(store.snippets) { snippet in
                CSSSnippetRow(
                    snippet: snippet,
                    error: store.validationErrors[snippet.id],
                    store: store
                )
            }

            if store.snippets.isEmpty {
                Text("No snippets imported.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button("Import CSS Snippet…") { importSnippet() }
                    .disabled(!store.canModify)

                Menu {
                    Button {
                        store.revealManagedFolder()
                    } label: {
                        Label("Reveal Styles in Finder", systemImage: "folder")
                    }
                    Button("Disable All Snippets") { store.disableAll() }
                        .disabled(store.enabledCount == 0 || !store.canModify)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
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
            Button("New Appearance") { store.createAppearance() }
            Button("Duplicate Appearance") {
                guard let id = store.selectedAppearanceProfileID else { return }
                store.duplicateAppearance(id)
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
                guard let url = try await fileSelectionPresenter
                    .requiredForFileSelection()
                    .selectURL(request) else { return }
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

private struct AppearanceProfileEditor: View {
    @Binding var profile: DocumentAppearanceProfile
    private let sourceFontFamilies = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsEditorSection("Body Font") {
                HStack(spacing: 8) {
                    Picker("Body Font", selection: $profile.settings.body.fontFamily) {
                        ForEach(DocumentAppearanceFontFamily.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.labelsHidden().frame(width: 210, alignment: .leading)
                    AppearanceNumberControl(value: $profile.settings.body.fontSizePoints, range: 9...24, step: 0.5, title: "Body font size")
                    Text("pt")
                }
            }
            AppearanceDoubleControl("Line width", value: $profile.settings.lineWidthCharacterUnits, range: DocumentAppearanceSettings.lineWidthCharacterUnitsRange, step: 1, suffix: "ch", precision: 0, accessibilityUnit: "character-width units")
            AppearanceDoubleControl("Line spacing", value: $profile.settings.body.lineHeight, range: 1.2...2.4, step: 0.05, suffix: "×")
            Divider()
            settingsEditorSection("Source Font") {
                HStack(spacing: 8) {
                    Picker("Source Font", selection: $profile.settings.source.fontFamily) {
                        ForEach(Array(Set(sourceFontFamilies + [profile.settings.source.fontFamily])).sorted(), id: \.self) {
                            Text(verbatim: $0).tag($0)
                        }
                    }.labelsHidden().frame(width: 210, alignment: .leading)
                    .accessibilityIdentifier("scholium.appearance.sourceFont")
                    AppearanceNumberControl(value: $profile.settings.source.fontSizePoints, range: 6...72, step: 0.25, title: "Source font size")
                    Text("pt")
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
        Binding(get: { value }, set: { candidate in
            guard candidate.isFinite else { return }
            value = min(max(candidate, range.lowerBound), range.upperBound)
        })
    }

    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: boundedValue, format: .number.precision(.fractionLength(0...2)))
                .frame(width: 58)
                .accessibilityLabel(Text(title))
            Stepper("", value: boundedValue, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel(Text(title))
        }
        .fixedSize()
    }
}

private struct AppearanceDoubleControl: View {
    let title: LocalizedStringResource
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    let precision: Int
    let accessibilityUnit: LocalizedStringResource?

    init(_ title: LocalizedStringResource, value: Binding<Double>, range: ClosedRange<Double>,
         step: Double, suffix: String, precision: Int = 2,
         accessibilityUnit: LocalizedStringResource? = nil) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.suffix = suffix
        self.precision = precision
        self.accessibilityUnit = accessibilityUnit
    }

    private var boundedValue: Binding<Double> {
        Binding(get: { value }, set: { candidate in
            guard candidate.isFinite else { return }
            value = min(max(candidate, range.lowerBound), range.upperBound)
        })
    }

    var body: some View {
        settingsEditorSection(title) {
            HStack(spacing: 6) {
                TextField("", value: boundedValue,
                          format: .number.precision(.fractionLength(0...precision)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .accessibilityLabel(Text(title))
                Stepper("", value: boundedValue, in: range, step: step)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel(Text(title))
                Text(suffix).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .help(Text(accessibilityUnit ?? title))
        }
    }
}

private extension DocumentAppearanceFontFamily {
    var label: String {
        switch self {
        case .alegreya: "Alegreya"
        case .iowan: "Iowan Old Style"
        case .palatino: "Palatino"
        case .georgia: "Georgia"
        case .times: "Times New Roman"
        case .systemSerif: "System Serif"
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

            Button { store.move(snippet.id, by: -1) } label: {
                Label("Move Earlier", systemImage: "chevron.up")
            }
            .labelStyle(.iconOnly)
            .help("Move Earlier")

            Button { store.move(snippet.id, by: 1) } label: {
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

private struct WorkspacePathEditor: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel

    let completionTitle: String
    var targetTriptychID: UUID? = nil
    var showsCancel = true
    let onCompletion: (() -> Void)?
    var onCancel: (() -> Void)? = nil

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
            VStack(alignment: .leading, spacing: 20) {
                settingsEditorSection("Name") {
                    TextField("Name", text: $triptychName)
                        .labelsHidden()
                        .accessibilityIdentifier("scholium.triptychName")

                }

                Divider()
                settingsEditorSection("Research Folders") {
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
                }

                Divider()
                settingsEditorSection("Portable Triptych Data") {
                    PortableControlFolderRow(
                        worksURL: outputURL,
                        containerURL: $portableContainerURL
                    )
                    Text("Scholium stores the small portable .scholium folder beside Works. macOS therefore asks once for access to the folder containing Works; it is not added as a fourth vault.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(
                            maxWidth: ScholiumMetrics.Settings.formExplanationMaximumWidth,
                            alignment: .leading
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }



            }
            .scholiumSettingsForm()

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

            Divider()

            HStack {
                if showsCancel {
                    Button("Cancel") { onCancel?() }
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(completionTitle) { save() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isSaving)
            }
            .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
            .padding(.vertical, ScholiumGrid.Spacing.sectionSeparation)
        }
        .accessibilityIdentifier("scholium.triptychSetup")
        .task {
            await settingsModel.refreshWorkspaceAssignment()
            loadCurrentValuesIfNeeded()
            await loadPortableContainerIfAvailable()
        }
        .onChange(of: settingsModel.workspaceAssignment) { _, _ in
            loadCurrentValuesIfNeeded(force: true)
            Task { await loadPortableContainerIfAvailable() }
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
              let portableContainerURL else { return false }
        return outputURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            == portableContainerURL.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func loadCurrentValuesIfNeeded(force: Bool = false) {
        guard force || !loadedCurrentValues else { return }
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
        if let registered = await settingsModel.portableContainerURL(for: outputURL) {
            portableContainerURL = registered
        }
    }

    private var targetAssignment: TriptychAssignment? {
        if let targetTriptychID {
            return settingsModel.registeredTriptychs.first(where: { $0.id == targetTriptychID })
        }
        return settingsModel.workspaceAssignment
    }

    private func assignedURL(for slot: WorkspaceVaultSlot) -> URL? {
        targetAssignment?.vault(for: slot).map {
            URL(fileURLWithPath: $0.canonicalPath, isDirectory: true)
        }
    }

    private func save() {
        guard let paperAnalysisURL, let topicKnowledgeURL, let outputURL else { return }
        guard let portableContainerURL else {
            errorMessage = String(localized: "Authorize the folder containing Works before saving this Triptych.", table: "Localizable", bundle: .module)
            return
        }
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
                    triptychName: triptychName
                )
                settingsModel.workspaceRecoveryMessage = nil
                isSaving = false
                onCompletion?()
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
        guard let expected = worksURL?
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL else { return }
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
                guard let selected = try await fileSelectionPresenter
                    .requiredForFileSelection()
                    .selectURL(request) else { return }
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
                    Text(ScholiumL10n.dynamicString(title))
                        .font(.body)
                    Text(url?.path(percentEncoded: false) ?? "No folder selected")
                        .font(.caption)
                        .foregroundStyle(url == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(url?.path(percentEncoded: false) ?? "Choose a folder")
                }

                Spacer(minLength: ScholiumMetrics.Settings.trailingControlMinimumSpacing)

                Button(url == nil ? "Choose…" : "Change…") {
                    chooseFolder()
                }
                .accessibilityLabel("Choose \(title) folder")
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

    private func chooseFolder() {
        var initialDirectoryURL = url?.deletingLastPathComponent()
#if DEBUG
        if initialDirectoryURL == nil,
           let testDirectory = ProcessInfo.processInfo.environment[
               "SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"
           ],
           !testDirectory.isEmpty {
            initialDirectoryURL = URL(fileURLWithPath: testDirectory, isDirectory: true)
        }
#endif
        let request = ScholiumFileSelectionRequest(
            title: String(
                format: ScholiumL10n.string("Choose %@ Folder"),
                locale: Locale.current,
                title
            ),
            prompt: ScholiumL10n.string("Choose"),
            initialDirectoryURL: initialDirectoryURL,
            kind: .directory(canCreateDirectories: true)
        )
        Task { @MainActor in
            do {
                guard let selected = try await fileSelectionPresenter
                    .requiredForFileSelection()
                    .selectURL(request) else { return }
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
