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
    case skills
    case actionProfiles
    case agentAccess
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
        .skills,
        .actionProfiles,
        .agentAccess,
        .externalToolsCitations,
    ]

    var title: LocalizedStringResource {
        switch self {
        case .triptychs: ScholiumL10n.Settings.triptychs
        case .appearance: ScholiumL10n.Settings.appearance
        case .hotkeys: ScholiumL10n.Settings.hotkeys
        case .metadata: ScholiumL10n.Settings.metadata
        case .attention: ScholiumL10n.Settings.attention
        case .skills:
            ResearchGuidanceCategory.skills.localizedTitle
        case .actionProfiles:
            ResearchGuidanceCategory.actionProfiles.localizedTitle
        case .agentAccess: ResearchGuidanceCategory.agentAccess.localizedTitle
        case .externalToolsCitations:
            ResearchGuidanceCategory.externalToolsCitations.localizedTitle
        }
    }

    var symbol: String {
        switch self {
        case .triptychs: "rectangle.3.group"
        case .appearance: "paintbrush"
        case .hotkeys: "keyboard"
        case .metadata: "list.bullet.rectangle"
        case .attention: "bell"
        case .skills: ResearchGuidanceCategory.skills.symbol
        case .actionProfiles: ResearchGuidanceCategory.actionProfiles.symbol
        case .agentAccess: ResearchGuidanceCategory.agentAccess.symbol
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
        case .skills, .actionProfiles, .agentAccess,
             .externalToolsCitations:
            .researchGuidance
        }
    }

    var researchGuidanceCategory: ResearchGuidanceCategory? {
        switch self {
        case .skills: .skills
        case .actionProfiles: .actionProfiles
        case .agentAccess: .agentAccess
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
            ["Metadata", "fields", "About", "Agent preferences", "optional fields"]
        case .attention:
            ["Notifications", "activities", "reminders", "dismissed items", "timing", "This Mac"]
        case .skills:
            ["Skills", "Research Skills", "SKILL.md", "references", "philosophical lenses", "recovery"]
        case .actionProfiles:
            ["Action Profiles", "academic inputs", "academic results", "roles", "fields"]
        case .agentAccess:
            ["Agent Access", "write set", "permission", "Run", "Full Triptych Access"]
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
            case .skills: .skills
            case .actionProfiles: .actionProfiles
            case .agentAccess: .agentAccess
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
    private var persistedResearchCategory = ResearchGuidanceCategory.skills.rawValue
    @State private var destination = ScholiumSettingsDestination.triptychs
    @State private var searchQuery = ""

    var body: some View {
        GeometryReader { geometry in
            let topInset = max(
                geometry.safeAreaInsets.top
                    - ScholiumMetrics.Settings.editorContentInset,
                0
            )
            HStack(spacing: 0) {
                settingsSidebar
                    .padding(.top, topInset)

                settingsDetail
                    .padding(.top, topInset)
                    .frame(
                        width: max(
                            geometry.size.width
                                - ScholiumMetrics.Settings.sidebarWidth,
                            0
                        ),
                        alignment: .topLeading
                    )
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .scholiumSettingsPaneSurface()
                    .clipped()
            }
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: ScholiumMetrics.Settings.sidebarWidth)
                    Divider()
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.settings.root")
        .overlay(alignment: .bottom) {
            if let message = settingsModel.toastMessage {
                ToastView(message: message)
                    .transition(
                        ScholiumMotion.transientStatusTransition(
                            reduceMotion: reduceMotion
                        )
                    )
                    .padding(.bottom, ScholiumGrid.Spacing.regionContentInset)
            }
        }
        .animation(
            ScholiumMotion.transientStatus(reduceMotion: reduceMotion),
            value: settingsModel.toastMessage
        )
        .task(id: settingsModel.toastMessage) {
            guard let message = settingsModel.toastMessage else { return }
            AccessibilityNotification.Announcement(message).post()
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            settingsModel.dismissToast(message)
        }
        .onAppear {
            let pane = WorkspaceSettingsPane(rawValue: persistedPane) ?? .triptychs
            let category = ResearchGuidanceCategory(
                rawValue: persistedResearchCategory
            ) ?? .skills
            destination = ScholiumSettingsDestination.restored(
                pane: pane,
                researchCategory: category
            )
            settingsModel.selectPane(destination.pane)
        }
        .onChange(of: destination) { _, destination in
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

    private var sidebarSelection: Binding<ScholiumSettingsDestination?> {
        Binding(
            get: { destination },
            set: { if let value = $0 { destination = value } }
        )
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScholiumSettingsSearchField(text: $searchQuery)
                .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
                .padding(.top, ScholiumMetrics.Settings.editorContentInset)
                .padding(.bottom, ScholiumGrid.Spacing.inlineControlGap)
                .accessibilityIdentifier("scholium.settings.search")

            List(selection: sidebarSelection) {
                if !filteredApplicationDestinations.isEmpty {
                    Section("Application") {
                        ForEach(filteredApplicationDestinations) { item in
                            settingsSidebarRow(item)
                        }
                    }
                }

                if !filteredTriptychDestinations.isEmpty {
                    Section("This Triptych") {
                        ForEach(filteredTriptychDestinations) { item in
                            settingsSidebarRow(item)
                        }
                    }
                }

                if !filteredResearchGuidanceDestinations.isEmpty {
                    Section {
                        ForEach(filteredResearchGuidanceDestinations) { item in
                            settingsSidebarRow(item)
                        }
                    } header: {
                        Text(ScholiumL10n.Settings.researchGuidance)
                            .font(ScholiumTypography.interface(.small, emphasis: .strong))
                            .scholiumForeground(.secondaryText)
                            .textCase(nil)
                    }
                }

                if filteredDestinations.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("scholium.settings.search.empty")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("scholium.settings.sidebarList")
        }
        .frame(
            minWidth: ScholiumMetrics.Settings.sidebarWidth,
            idealWidth: ScholiumMetrics.Settings.sidebarWidth,
            maxWidth: ScholiumMetrics.Settings.sidebarWidth,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .scholiumSettingsPaneSurface(.navigationSurfaceBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.settings.sidebar")
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

    private func settingsSidebarRow(
        _ item: ScholiumSettingsDestination
    ) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.symbol)
        }
        .tag(item)
        .accessibilityIdentifier("scholium.settings.destination.\(item.rawValue)")
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
        case .skills:
            ResearchGuidanceSettingsView(category: .skills)
        case .actionProfiles:
            ResearchGuidanceSettingsView(category: .actionProfiles)
        case .agentAccess:
            ResearchGuidanceSettingsView(category: .agentAccess)
        case .externalToolsCitations:
            ResearchGuidanceSettingsView(category: .externalToolsCitations)
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
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle(
                ScholiumL10n.Settings.attention,
                detail: LocalizedStringResource(
                    "Set when dismissed reminders return and restore local dismissals.",
                    table: "Localizable",
                    bundle: .module
                )
            )
            .padding(ScholiumMetrics.Settings.editorContentInset)

            Divider()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    settingsEditorSection("Reminder Timing for This Triptych") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                            reminderTimingPicker
                            Spacer()
                            saveAttentionButton
                        }
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumGrid.Spacing.labelAccessoryGap
                        ) {
                            reminderTimingPicker
                            saveAttentionButton
                        }
                    }

                    Text("These durations apply only to derived issue reminders. Dismiss on a completed Action removes that activity immediately; neither operation reviews, accepts, adopts, undoes, or changes Notes or Records.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    settingsEditorSection("Dismissed Items on This Mac") {
                        Button("Restore All Dismissed Items on This Mac") {
                            var ledger = AttentionPreferences.decodeLedger(
                                dismissalLedgerData
                            )
                            ledger.removeAll()
                            dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
                        }
                        .disabled(!hasDismissedAttention)

                        Text("Restores dismissed reminders on this Mac without changing Triptych data.")
                            .font(ScholiumTypography.interface(.body))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    settingsEditorSection("What Notifications Can Report") {
                        Text("Reports structural, metadata, identity, Connection, and settled-revision issues.")
                            .font(ScholiumTypography.interface(.body))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Never judges truth, evidence, philosophical quality, or appropriate use.")
                            .font(ScholiumTypography.interface(.body))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(ScholiumGrid.Spacing.regionContentInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
        .scholiumSettingsPaneSurface()
        .task {
            let stored = settingsModel.triptychSettings.attentionDismissalDays
            dismissalDays = durations.contains(stored)
                ? stored
                : TriptychSettings().attentionDismissalDays
        }
        .alert("Could Not Save Notification Settings", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var hasDismissedAttention: Bool {
        let ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        return !ledger.dismissedUntilByItemID.isEmpty
            || !ledger.revisionBoundItemIDs.isEmpty
    }

    private var reminderTimingPicker: some View {
        Picker("Return dismissed items after", selection: $dismissalDays) {
            ForEach(durations, id: \.self) { days in
                Text(days == 1 ? "1 day" : "\(days) days").tag(days)
            }
        }
        .frame(maxWidth: 300)
    }

    private var saveAttentionButton: some View {
        Button("Save Notification Settings") { save() }
            .buttonStyle(.borderedProminent)
            .disabled(
                isSaving
                    || dismissalDays
                        == settingsModel.triptychSettings.attentionDismissalDays
            )
    }

    private func save() {
        isSaving = true
        Task {
            do {
                var settings = settingsModel.triptychSettings
                settings.attentionDismissalDays = AttentionPreferences.normalizedDays(dismissalDays)
                let result = try await settingsModel.saveTriptychSettings(settings)
                dismissalDays = settings.attentionDismissalDays
                settingsModel.showToast(
                    result.targetIsCurrent
                        ? String(localized: "Notification settings saved", table: "Localizable", bundle: .module)
                        : result.warning ?? String(localized: "Settings saved to the previously active Triptych.", table: "Localizable", bundle: .module)
                )
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
    @State private var agentCreation = AnalysisAgentCreationConfiguration()
    @State private var savedAgentCreation = AnalysisAgentCreationConfiguration()
    @State private var savedTriptychSettings = TriptychSettings()
    @State private var savedSettingsRevision: SettingsRevision?
    @State private var savedTriptychID: UUID?
    @State private var selectedSourceType: AnalysisSourceType = .journalArticle
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
            aboutConfigurations: aboutConfigurations,
            agentCreation: agentCreation
        )
    }

    private var validationMessage: String? {
        validationDiagnostic?.displayMessage
    }

    private struct SettingsDiagnostic {
        enum Section {
            case fieldDefinitions
            case agentPreferences
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

    private var currentAgentDiagnostic: SettingsDiagnostic? {
        guard let diagnostic = validationDiagnostic,
              diagnostic.section == .agentPreferences,
              diagnostic.role == .paperAnalysis,
              diagnostic.sourceType == selectedSourceType else { return nil }
        return diagnostic
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
        .task { loadSavedSettingsIfNeeded() }
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
            settingsTitle(
                ScholiumL10n.Settings.metadata,
                detail: LocalizedStringResource(
                    "Define optional managed fields for each role, then choose Agent guidance and About presentation independently. New Note YAML remains fixed.",
                    table: "Localizable",
                    bundle: .module
                )
            )
            if case .needsReview = settingsModel.portableSettingsState {
                Label(
                    "These current-schema settings need review before managed creation can resume.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.attention)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let refreshError = settingsModel.errorMessage {
                Label(
                    "Settings refresh failed. The last confirmed settings remain visible. \(refreshError)",
                    systemImage: "arrow.clockwise.circle"
                )
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.attention)
                .fixedSize(horizontal: false, vertical: true)
            }
            ScholiumSegmentedControl(
                selection: $selectedSlot,
                options: [
                    ScholiumSegmentedControlOption(
                        .paperAnalysis,
                        title: String(localized: "Analysis")
                    ),
                    ScholiumSegmentedControlOption(
                        .topicKnowledge,
                        title: String(localized: "Topic")
                    ),
                    ScholiumSegmentedControlOption(
                        .output,
                        title: String(localized: "Work")
                    ),
                ],
                label: String(localized: "Metadata role"),
                accessibilityIdentifier: "scholium.metadataSettings.role"
            )
            .disabled(isAddingField)

            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    fieldDefinitionsSection
                    Divider()
                    if selectedSlot == .paperAnalysis {
                        agentPreferencesSection
                        Divider()
                    }
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
        .padding(ScholiumMetrics.Settings.editorContentInset)
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
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                Button("Reload Saved Settings") {
                    Task { await reloadSavedSettings() }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.destructive)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fieldDefinitionsSection: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            settingsSectionTitle("Managed Fields")
            Text("Fields added here become optional Metadata fields for every Note in this role. A field key and value type are permanent. Labels and descriptions can change; archiving is reversible and preserves every stored value.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            let definitions = metadataFields[selectedSlot] ?? []
            if definitions.isEmpty {
                Text("No custom fields. Built-in fields remain available.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
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
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Button("Cancel") { cancelAddingField() }
                            .keyboardShortcut(.escape)
                        Button("Add Field") { addFieldDefinition() }
                            .buttonStyle(.borderedProminent)
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
                        .font(ScholiumTypography.exact(.small))
                        .scholiumForeground(.mutedText)
                }
                Spacer(minLength: ScholiumMetrics.Settings.labelActionMinimumSpacing)
                VStack(alignment: .trailing, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                    Text(displayName(for: definition.valueKind))
                        .font(ScholiumTypography.interface(.compact))
                        .scholiumForeground(.secondaryText)
                    Text(definition.lifecycle == .active ? "Active" : "Archived")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }
            }
            TextField(
                "Description (Optional)",
                text: definitionDescriptionBinding(definition.key)
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Description for \(definition.key)")

            if definition.valueKind == .choice {
                Text((definition.allowedValues ?? []).joined(separator: " · "))
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
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
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                Spacer()
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

    private var agentPreferencesSection: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Agent-Created Analyses")
                .font(ScholiumTypography.interface(.sectionTitle))
            Text("Choose Scholium-managed fields to highlight for this source type. Every field is optional; an Agent may create the Analysis without supplying any of them.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            Picker("Source Type", selection: $selectedSourceType) {
                ForEach(AnalysisSourceType.allCases, id: \.self) { sourceType in
                    Text(sourceType.propertyDisplayName).tag(sourceType)
                }
            }
            .frame(maxWidth: 320)

            ForEach(agentPreferenceGroups, id: \.group) { group in
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text(group.group.label)
                        .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                        .scholiumForeground(.secondaryText)
                        .accessibilityHeading(.h3)
                    ForEach(group.fields, id: \.key) { field in
                        agentPreferenceRow(field)
                    }
                }
            }

            Button("Clear Preferred Fields for This Source Type") {
                agentCreation.preferredFieldsBySourceType.removeValue(forKey: selectedSourceType)
            }
            .disabled(agentCreation.preferredFields(for: selectedSourceType).isEmpty)

            if let diagnostic = currentAgentDiagnostic {
                Label(diagnostic.displayMessage, systemImage: "exclamationmark.circle")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var agentPreferenceGroups: [(
        group: PropertyPresentationGroup,
        fields: [PropertyPresentation]
    )] {
        let sourceProfile = AnalysisSourceTypeProfileCatalog.profile(for: selectedSourceType)
        let applicable = Set(
            candidateCatalog.analysisContracts(for: selectedSourceType)
                .map(\.canonicalKey)
        ).subtracting(["type"])
        let recommended = Set(sourceProfile.recommendedFieldOrder)
        let fields = PropertyPresentationCatalog.presentations(
            for: .analysis,
            catalog: candidateCatalog
        )
            .filter { applicable.contains($0.key) }
        let grouped = Dictionary(grouping: fields, by: \.group)
        return PropertyPresentationCatalog.orderedGroups(for: .analysis).compactMap { group in
            guard let values = grouped[group], !values.isEmpty else { return nil }
            return (
                group,
                values.sorted {
                    (recommended.contains($0.key) ? 0 : 1, $0.order)
                        < (recommended.contains($1.key) ? 0 : 1, $1.order)
                }
            )
        }
    }

    private func agentPreferenceRow(_ field: PropertyPresentation) -> some View {
        let preferred = agentCreation.preferredFields(for: selectedSourceType).contains(field.key)
        return Toggle(isOn: Binding(
            get: { preferred },
            set: { enabled in
                var fields = agentCreation.preferredFields(for: selectedSourceType)
                if enabled {
                    if !fields.contains(field.key) { fields.append(field.key) }
                } else {
                    fields.removeAll { $0 == field.key }
                }
                agentCreation.preferredFieldsBySourceType[selectedSourceType] = fields
            }
        )) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text(field.label)
                    if AnalysisSourceTypeProfileCatalog.profile(
                        for: selectedSourceType
                    ).recommendedFieldOrder.contains(field.key) {
                        Text("Recommended")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                }
                Text(field.key)
                    .font(ScholiumTypography.exact(.small))
                    .scholiumForeground(.mutedText)
                if let help = field.help {
                    Text(help)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("\(selectedSourceType.propertyDisplayName), \(field.label), \(field.key), preferred for Agent")
        .accessibilityValue(preferred ? "Preferred" : "Optional")
    }

    private var displayOrderColumn: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            settingsSectionTitle("About")
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if selectedConfiguration.visibleFields.isEmpty {
                    Text("No fields are shown in About.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                        ForEach(aboutConfigurationGroups, id: \.group) { group in
                            VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.listRowSpacing) {
                                Text(group.group.label)
                                    .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                                    .scholiumForeground(.secondaryText)
                                    .accessibilityHeading(.h3)
                                ForEach(Array(group.keys.enumerated()), id: \.element) { index, key in
                                HStack(spacing: ScholiumMetrics.Settings.rowControlSpacing) {
                                    VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                                        Text(displayName(for: key))
                                            .font(ScholiumTypography.interface(.body))
                                        Text(key)
                                            .font(ScholiumTypography.exact(.small))
                                            .scholiumForeground(.mutedText)
                                    }
                                    Spacer(minLength: ScholiumMetrics.Settings.labelActionMinimumSpacing)
                                    Button {
                                        moveVisibleField(key, within: group.keys, to: index - 1)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                            .scholiumForeground(.secondaryText)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(index == 0)
                                    .help("Move \(displayName(for: key)) up")
                                    .accessibilityLabel("Move \(displayName(for: key)) up")

                                    Button {
                                        moveVisibleField(key, within: group.keys, to: index + 1)
                                    } label: {
                                        Image(systemName: "chevron.down")
                                            .scholiumForeground(.secondaryText)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(index == group.keys.count - 1)
                                    .help("Move \(displayName(for: key)) down")
                                    .accessibilityLabel("Move \(displayName(for: key)) down")

                                    Button {
                                        updateSelectedConfiguration { $0.setVisible(false, field: key) }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .scholiumForeground(.secondaryText)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Hide \(displayName(for: key))")
                                    .accessibilityLabel("Hide \(displayName(for: key))")
                                }
                            }
                        }
                    }
                }
                }

                Menu("Add Visible Field") {
                    if hiddenAboutConfigurationGroups.isEmpty {
                        Text("All available fields are shown")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var restoreActions: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Restore About Defaults") {
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
                .buttonStyle(.borderedProminent)
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
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.destructive)
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
                let message = if result.warning == nil {
                    String(localized: "Metadata configuration saved", table: "Localizable", bundle: .module)
                } else {
                    result.warning ?? String(localized: "Metadata configuration saved", table: "Localizable", bundle: .module)
                }
                settingsModel.showToast(message)
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
        agentCreation = settings.analysisAgentCreation
        savedAgentCreation = settings.analysisAgentCreation
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
        agentCreation = savedAgentCreation
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
            repair = String(localized: "Provide unique nonempty choices. Existing choices can only be extended.", table: "Localizable", bundle: .module)
        case .metadataFieldIdentityChanged(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "This custom Metadata field's stable key, value type, or position changed.", table: "Localizable", bundle: .module)
            repair = String(localized: "Restore its identity and use Archive Field to stop offering it.", table: "Localizable", bundle: .module)
        case .metadataFieldChoicesRemoved(let value, let field):
            role = value; sourceType = nil; key = field
            section = .fieldDefinitions
            diagnosticReason = String(localized: "An existing controlled choice was removed or reordered.", table: "Localizable", bundle: .module)
            repair = String(localized: "Restore the existing order; controlled choices may only be appended.", table: "Localizable", bundle: .module)
        case .noncanonicalConfigurationField(let value, let field):
            role = value; sourceType = nil; key = field
            section = .configuration
            diagnosticReason = String(localized: "This configuration field is blank, duplicated, or unnormalized.", table: "Localizable", bundle: .module)
            repair = String(localized: "Remove the blank or duplicate field entry.", table: "Localizable", bundle: .module)
        case .invalidPreferredField(let type, let field):
            role = .paperAnalysis; sourceType = type; key = field
            section = .agentPreferences
            diagnosticReason = String(localized: "This is not a shape-known field that an Agent may create.", table: "Localizable", bundle: .module)
            repair = String(localized: "Clear this preferred Agent field.", table: "Localizable", bundle: .module)
        case .preferredFieldNotApplicable(let type, let field):
            role = .paperAnalysis; sourceType = type; key = field
            section = .agentPreferences
            diagnosticReason = String(localized: "This preferred field does not apply to the selected Source Type.", table: "Localizable", bundle: .module)
            repair = String(localized: "Clear it or choose a source type where it applies.", table: "Localizable", bundle: .module)
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
        if let sourceType = diagnostic.sourceType {
            selectedSlot = .paperAnalysis
            selectedSourceType = sourceType
        }
    }

}

struct AgentCLISettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel

    var body: some View {
        researchSettingsSection(LocalizedStringResource(
            "SCHOLIUM CLI ON THIS MAC",
            table: "Localizable",
            bundle: .module
        )) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text("Scholium does not manage this Mac’s CLI. Copy the official instructions for your Agent.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Copy CLI Installation Instructions") {
                    let copied = ScholiumPasteboardWriter.general.writeText(
                        ScholiumCLIInstallationInstructions.text
                    )
                    let message = copied
                        ? String(
                            localized: "CLI installation instructions copied",
                            table: "Localizable",
                            bundle: .module
                        )
                        : String(
                            localized: "CLI installation instructions could not be copied.",
                            table: "Localizable",
                            bundle: .module
                        )
                    settingsModel.showToast(message)
                }
                .accessibilityIdentifier("scholium.agentCLI.copyInstructions")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Citation style is a protected Platform integration setting. It does not
/// select, install, or grant authority to a Skill package.
struct ResearchCitationMethodSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    let onStatusChange: (ResearchCitationMethodStatus) -> Void
    @State private var status: ResearchCitationMethodStatus?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        researchSettingsSection(LocalizedStringResource(
            "TRIPTYCH CITATION STYLE",
            table: "Localizable",
            bundle: .module
        )) {
            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.fieldSpacing) {
                    if let status {
                        if status.availableStyles.isEmpty {
                            Text("No citation styles are available in this build.")
                                .font(ScholiumTypography.interface(.body))
                                .scholiumForeground(.secondaryText)
                        } else {
                            Picker("Citation style", selection: activeStyleSelection) {
                                Text("None").tag(String?.none)
                                ForEach(status.availableStyles) { option in
                                    Text(option.displayName)
                                        .tag(Optional(option.citationStyle))
                                }
                            }
                            .frame(maxWidth: 420)
                            .accessibilityIdentifier(
                                "scholium.researchGuidance.citationMethod"
                            )
                        }
                        if let active = status.availableStyles.first(where: {
                            $0.citationStyle == status.activeCitationStyle
                        }) {
                            Text(active.description)
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Citation checking remains unavailable until a style is selected.")
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(.secondaryText)
                        }
                    } else {
                        ProgressView("Loading citation styles…")
                    }
                }
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .alert("Could Not Update Citation Style", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("scholium.researchGuidance.citationMethodSection")
    }

    private var activeStyleSelection: Binding<String?> {
        Binding(
            get: { status?.activeCitationStyle },
            set: { newValue in
                guard newValue != status?.activeCitationStyle else { return }
                if let newValue {
                    activate(newValue)
                } else {
                    clear()
                }
            }
        )
    }

    private func reload() async {
        guard settingsModel.activeTriptychServicesID != nil else {
            status = nil
            errorMessage = nil
            return
        }
        do {
            status = try await settingsModel.citationMethodStatus()
            if let status { onStatusChange(status) }
            errorMessage = nil
        } catch {
            status = nil
            errorMessage = error.localizedDescription
        }
    }

    private func activate(_ citationStyle: String) {
        perform {
            status = try await settingsModel.activateCitationMethod(
                citationStyle: citationStyle,
                expectedConfigurationRevision: status?.configurationRevision
            )
        }
    }

    private func clear() {
        perform {
            status = try await settingsModel.clearCitationMethod(
                expectedConfigurationRevision: status?.configurationRevision
            )
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await operation()
                if let status { onStatusChange(status) }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ZoteroSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var info = ZoteroLibraryInfo(status: .appUnavailable, lastSuccessfulConnection: nil)
    @State private var isTesting = false
    @State private var errorMessage: String?

    var body: some View {
        researchSettingsSection(LocalizedStringResource(
            "READ-ONLY ZOTERO ON THIS MAC",
            table: "Localizable",
            bundle: .module
        )) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                LabeledContent("Local API") {
                    Label(statusTitle, systemImage: statusSymbol)
                        .scholiumForeground(statusColorRole)
                }
                LabeledContent("Last Connected") {
                    Text(info.lastSuccessfulConnection?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                        .scholiumForeground(.secondaryText)
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
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                if info.status == .apiDisabled {
                    Text("In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’, then test again.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .scholiumForeground(.destructive)
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

    private var statusColorRole: ScholiumColorRole {
        info.status == .available ? .confirmed : .attention
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
            VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.sectionSpacing) {
                settingsTitle(
                    ScholiumL10n.Settings.triptychs,
                    detail: LocalizedStringResource(
                        "Manage registered Triptychs and their three researcher-controlled folders.",
                        table: "Localizable",
                        bundle: .module
                    )
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: ScholiumMetrics.Settings.rootSpacing) {
                        triptychPicker
                        triptychActions
                        Spacer(minLength: ScholiumMetrics.Settings.editorContentInset)
                    }
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumGrid.Spacing.labelAccessoryGap
                    ) {
                        triptychPicker
                        triptychActions
                    }
                }
            }
            .padding(ScholiumMetrics.Settings.editorContentInset)

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
        .disabled(selectedTriptychID == nil)

        Button("New Triptych…") {
            openWindow(
                id: "scholium-bootstrap",
                value: BootstrapWindowRoute(purpose: .newTriptych)
            )
        }
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
    @State private var showsAdvancedCSS = false
    @State private var nameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsTitle(
                ScholiumL10n.Settings.appearance,
                detail: LocalizedStringResource(
                    "Choose the document appearance shared by Review, Edit, and Source.",
                    table: "Localizable",
                    bundle: .module
                )
            )
            .padding(ScholiumMetrics.Settings.editorContentInset)

            Divider()

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

                    DisclosureGroup("Advanced CSS", isExpanded: $showsAdvancedCSS) {
                        advancedCSSContent
                            .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                    }
                }
                .padding(ScholiumGrid.Spacing.regionContentInset)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("scholium.appearance.form")

            if let reason = store.safeModeReason {
                Label("CSS Safe Mode: \(reason)", systemImage: "exclamationmark.shield.fill")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.attention)
                    .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                    .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }
            if let storeError = store.storeError {
                Label(storeError, systemImage: "exclamationmark.triangle.fill")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.destructive)
                    .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                    .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                    .accessibilityIdentifier("settings.css.store-error")
            }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.destructive)
                    .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                    .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }
        }
        .scholiumSettingsPaneSurface()
        .onAppear { loadSelectedDraft() }
        .onChange(of: store.selectedAppearanceProfileID) { _, _ in loadSelectedDraft() }
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
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                appearancePicker

                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)

                Button("Save") {
                    guard let draft else { return }
                    store.updateAppearance(draft)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasUnsavedChanges || !store.canModify)
                .accessibilityLabel("Save Appearance")

                Button("Revert to Saved") {
                    loadSelectedDraft()
                }
                .disabled(!hasUnsavedChanges)

                appearanceManagementMenu
            }

            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("Stored on this Mac")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                if hasUnsavedChanges {
                    Text("Unsaved changes")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumForeground(.attention)
                }
            }
        }
    }

    private var advancedCSSContent: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Optional CSS snippets are additive compatibility overrides; the selected appearance remains primary.")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(store.snippets) { snippet in
                CSSSnippetRow(
                    snippet: snippet,
                    error: store.validationErrors[snippet.id],
                    store: store
                )
            }

            if store.snippets.isEmpty {
                Text("No snippets imported.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
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
        .labelsHidden()
        .frame(width: ScholiumMetrics.Settings.appearancePickerWidth)
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
    @State private var showsAdvancedAppearance = false

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            settingsEditorSection("Layout") {
                AppearanceDoubleControl(
                    "Line width",
                    value: $profile.settings.lineWidthCharacterUnits,
                    range: DocumentAppearanceSettings.lineWidthCharacterUnitsRange,
                    step: 1,
                    suffix: "ch",
                    precision: 0,
                    accessibilityUnit: "character-width units"
                )
                Text("Measured in CSS character-width units; the exact measure varies by typeface.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            settingsEditorSection("Body") {
                Picker("Typeface", selection: $profile.settings.body.fontFamily) {
                    ForEach(DocumentAppearanceFontFamily.allCases, id: \.self) { family in
                        Text(family.label).tag(family)
                    }
                }
                AppearanceDoubleControl("Font size", value: $profile.settings.body.fontSizePoints, range: 9...24, step: 0.5, suffix: "pt")
                AppearanceDoubleControl("Line spacing", value: $profile.settings.body.lineHeight, range: 1.2...2.4, step: 0.05, suffix: "×")
            }

            Divider()

            ScholiumDisclosureHeaderButton(
                isExpanded: showsAdvancedAppearance,
                accessibilityLabel: Text("Advanced Appearance"),
                accessibilityIdentifier: "scholium.appearance.advanced",
                action: { showsAdvancedAppearance.toggle() }
            ) {
                Text("Advanced Appearance")
                    .font(ScholiumTypography.interface(.body))
            }
            if showsAdvancedAppearance {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    settingsEditorSection("Body Details") {
                        AppearanceDoubleControl("Paragraph spacing", value: $profile.settings.body.paragraphSpacingEm, range: 0...2, step: 0.05, suffix: "em")
                        AppearanceDoubleControl("First-line indent", value: $profile.settings.body.firstLineIndentEm, range: 0...4, step: 0.1, suffix: "em")
                        AppearanceDoubleControl("Letter spacing", value: $profile.settings.body.letterSpacingEm, range: -0.05...0.1, step: 0.005, suffix: "em", precision: 3)
                        AppearanceDoubleControl("Word spacing", value: $profile.settings.body.wordSpacingEm, range: -0.1...0.5, step: 0.01, suffix: "em")
                        Picker("Alignment", selection: $profile.settings.body.alignment) {
                            ForEach(DocumentTextAlignment.allCases, id: \.self) { alignment in
                                Text(alignment.label).tag(alignment)
                            }
                        }
                        Picker("Hyphenation", selection: $profile.settings.body.hyphenation) {
                            ForEach(DocumentHyphenation.allCases, id: \.self) { hyphenation in
                                Text(hyphenation.label).tag(hyphenation)
                            }
                        }
                        Toggle("Kerning", isOn: $profile.settings.body.kerning)
                        Toggle("Common ligatures", isOn: $profile.settings.body.ligatures)
                    }

                    Divider()

                    settingsEditorSection("Headings") {
                        Picker("Typeface", selection: $profile.settings.headings.fontFamily) {
                            ForEach(DocumentHeadingFontFamily.allCases, id: \.self) { family in
                                Text(family.label).tag(family)
                            }
                        }
                        Picker("Style", selection: $profile.settings.headings.style) {
                            ForEach(DocumentHeadingStyle.allCases, id: \.self) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        AppearanceWeightPicker("Weight", weight: $profile.settings.headings.weight)
                        AppearanceDoubleControl("Line spacing", value: $profile.settings.headings.lineHeight, range: 1...2.4, step: 0.05, suffix: "×")
                        AppearanceDoubleControl("Letter spacing", value: $profile.settings.headings.letterSpacingEm, range: -0.05...0.1, step: 0.005, suffix: "em", precision: 3)

                        DisclosureGroup("Document title (H1)") {
                            HeadingLevelAppearanceEditor(level: $profile.settings.headings.title)
                        }
                        DisclosureGroup("Section heading (H2)") {
                            HeadingLevelAppearanceEditor(level: $profile.settings.headings.level1)
                        }
                        DisclosureGroup("Lower headings (H3–H6)") {
                            HeadingLevelAppearanceEditor(level: $profile.settings.headings.level2)
                        }
                    }

                    Divider()

                    settingsEditorSection("Callouts") {
                        Text("Callouts inherit Body typography; each role controls only spacing and composition.")
                            .font(ScholiumTypography.interface(.body))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(DocumentCalloutAppearanceRole.allCases, id: \.self) { role in
                            if let index = profile.settings.callouts.firstIndex(where: { $0.role == role }) {
                                DisclosureGroup(role.label) {
                                    CalloutAppearanceEditor(callout: $profile.settings.callouts[index])
                                }
                            }
                        }
                    }
                }
                .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                .padding(.leading, ScholiumGrid.Spacing.nestedContentInset)
            }
        }
    }
}

private struct HeadingLevelAppearanceEditor: View {
    @Binding var level: DocumentHeadingLevelAppearance

    var body: some View {
        AppearanceDoubleControl("Scale", value: $level.scale, range: 0.8...3, step: 0.05, suffix: "×")
        Picker("Alignment", selection: $level.alignment) {
            ForEach(DocumentTextAlignment.allCases, id: \.self) { alignment in
                Text(alignment.label).tag(alignment)
            }
        }
        AppearanceDoubleControl("Space before", value: $level.spaceBeforeEm, range: 0...4, step: 0.1, suffix: "em")
        AppearanceDoubleControl("Space after", value: $level.spaceAfterEm, range: 0...4, step: 0.1, suffix: "em")
    }
}

private struct CalloutAppearanceEditor: View {
    @Binding var callout: DocumentCalloutAppearance

    var body: some View {
        AppearanceDoubleControl("Horizontal inset", value: $callout.inlineInsetEm, range: 0...4, step: 0.1, suffix: "em")
        AppearanceDoubleControl("Block spacing", value: $callout.blockGapEm, range: 0...4, step: 0.1, suffix: "em")
        AppearanceDoubleControl("Text scale", value: $callout.fontScale, range: 0.8...1.4, step: 0.05, suffix: "×")
        AppearanceDoubleControl("Paragraph spacing", value: $callout.paragraphSpacingEm, range: 0...2, step: 0.05, suffix: "em")
        AppearanceWeightPicker("Title weight", weight: $callout.titleWeight)

        switch callout.role {
        case .orientation:
            AppearanceDoubleControl("Start inset", value: optional($callout.startInsetEm, fallback: 3), range: 0...6, step: 0.1, suffix: "em")
            AppearanceDoubleControl("End inset", value: optional($callout.endInsetEm, fallback: 3), range: 0...6, step: 0.1, suffix: "em")
            AppearanceDoubleControl("Line spacing", value: optional($callout.lineHeight, fallback: 1.3), range: 1.1...2.4, step: 0.05, suffix: "×")
        case .connections:
            AppearanceDoubleControl("Content indent", value: optional($callout.contentIndentEm, fallback: 1.1), range: 0...4, step: 0.1, suffix: "em")
        case .statement:
            AppearanceDoubleControl("Title gap", value: optional($callout.titleGapEm, fallback: 0.32), range: 0...2, step: 0.05, suffix: "em")
        case .illustration:
            AppearanceDoubleControl("Title column", value: optional($callout.titleColumnEm, fallback: 6.5), range: 3...16, step: 0.5, suffix: "em")
            AppearanceDoubleControl("Column gap", value: optional($callout.columnGapEm, fallback: 1), range: 0...4, step: 0.1, suffix: "em")
        case .caution, .source:
            AppearanceDoubleControl("Vertical padding", value: optional($callout.paddingBlockEm, fallback: 0.9), range: 0...3, step: 0.1, suffix: "em")
            AppearanceDoubleControl("Horizontal padding", value: optional($callout.paddingInlineEm, fallback: 1), range: 0...4, step: 0.1, suffix: "em")
        case .folded:
            AppearanceDoubleControl("Content indent", value: optional($callout.contentIndentEm, fallback: 1.05), range: 0...4, step: 0.1, suffix: "em")
        case .quotation:
            AppearanceDoubleControl("Quotation scale", value: optional($callout.quotationScale, fallback: 1.06), range: 0.8...1.5, step: 0.05, suffix: "×")
            AppearanceDoubleControl("Attribution scale", value: optional($callout.attributionScale, fallback: 0.85), range: 0.6...1.2, step: 0.05, suffix: "×")
        }
    }

    private func optional(_ value: Binding<Double?>, fallback: Double) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue ?? fallback },
            set: { value.wrappedValue = $0 }
        )
    }
}

private struct AppearanceDoubleControl: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    let precision: Int
    let accessibilityUnit: LocalizedStringResource?

    init(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String,
        precision: Int = 2,
        accessibilityUnit: LocalizedStringResource? = nil
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.suffix = suffix
        self.precision = precision
        self.accessibilityUnit = accessibilityUnit
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                AppearanceNativeSlider(
                    value: $value,
                    range: range,
                    step: step
                )
                    .frame(minWidth: 150, idealWidth: 220, maxWidth: 260)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(spokenValue)
                Text(formattedValue)
                    .font(ScholiumTypography.interface(.body, tabularDigits: true))
                    .frame(width: 52, alignment: .trailing)
                Text(suffix)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .frame(width: 24, alignment: .leading)
            }
        }
    }

    private var formattedValue: String {
        value.formatted(.number.precision(.fractionLength(0...precision)))
    }

    private var spokenValue: Text {
        let unit = accessibilityUnit.map { String(localized: $0) } ?? suffix
        return Text(verbatim: "\(formattedValue) \(unit)")
    }
}

private struct AppearanceNativeSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> KeyboardAccessibleNSSlider {
        let slider = KeyboardAccessibleNSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.keyboardStep = step
        slider.trackFillColor = ScholiumColorRole.accent.nsColor
        return slider
    }

    func updateNSView(_ slider: KeyboardAccessibleNSSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.keyboardStep = step
        slider.trackFillColor = ScholiumColorRole.accent.nsColor
        if slider.doubleValue != value {
            slider.doubleValue = value
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: AppearanceNativeSlider

        init(parent: AppearanceNativeSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSSlider) {
            let lowerBound = parent.range.lowerBound
            let snapped = lowerBound
                + ((sender.doubleValue - lowerBound) / parent.step).rounded() * parent.step
            let normalized = min(max(snapped, lowerBound), parent.range.upperBound)
            sender.doubleValue = normalized
            parent.value = normalized
        }
    }
}

private final class KeyboardAccessibleNSSlider: NSSlider {
    var keyboardStep: Double = 1

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .leftArrow:
            adjustValue(by: -keyboardStep)
        case .rightArrow:
            adjustValue(by: keyboardStep)
        default:
            super.keyDown(with: event)
        }
    }

    private func adjustValue(by delta: Double) {
        doubleValue = min(max(doubleValue + delta, minValue), maxValue)
        sendAction(action, to: target)
    }
}

private struct AppearanceWeightPicker: View {
    let title: String
    @Binding var weight: Int

    init(_ title: String, weight: Binding<Int>) {
        self.title = title
        _weight = weight
    }

    var body: some View {
        Picker(title, selection: $weight) {
            Text("Regular, 400").tag(400)
            Text("Medium, 500").tag(500)
            Text("Semibold, 600").tag(600)
            Text("Bold, 700").tag(700)
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

private extension DocumentHeadingFontFamily {
    var label: String {
        switch self {
        case .body: "Inherit Body"
        case .alegreya: "Alegreya"
        case .systemSerif: "System Serif"
        case .systemSans: "System Sans"
        }
    }
}

private extension DocumentHeadingStyle {
    var label: String {
        switch self {
        case .upright: "Upright"
        case .italic: "Italic"
        case .smallCaps: "Small Caps"
        }
    }
}

private extension DocumentTextAlignment {
    var label: String {
        switch self {
        case .start: "Leading"
        case .center: "Centered"
        case .justify: "Justified"
        }
    }
}

private extension DocumentHyphenation {
    var label: String {
        switch self {
        case .none: "Off"
        case .automatic: "Automatic"
        }
    }
}

private extension DocumentCalloutAppearanceRole {
    var label: String {
        switch self {
        case .orientation: "Orientation"
        case .connections: "Connections"
        case .statement: "Statement"
        case .illustration: "Illustration"
        case .caution: "Caution"
        case .folded: "Folded"
        case .quotation: "Quotation"
        case .source: "Source"
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
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.destructive)
                            .lineLimit(2)
                    } else {
                        Text(snippet.isEnabled ? "Enabled" : "Disabled")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
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
            Form {
                Section {
                    TextField("Name", text: $triptychName)
                        .accessibilityIdentifier("scholium.triptychName")
                    Text("The name distinguishes complete research domains. Works folders remain ordinary researcher-controlled folders, not app-managed projects.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .frame(
                            maxWidth: ScholiumMetrics.Settings.formExplanationMaximumWidth,
                            alignment: .leading
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                header: {
                    settingsSectionTitle("Triptych")
                }

                Section {
                    WorkspaceFolderRow(
                        title: "Analyses",
                        subtitle: "Source-facing reports and evidence records",
                        symbol: "doc.text.magnifyingglass",
                        url: $paperAnalysisURL
                    )
                    WorkspaceFolderRow(
                        title: "Topics",
                        subtitle: "Topic-centred concepts, debates, and synthesis",
                        symbol: "lightbulb",
                        url: $topicKnowledgeURL
                    )
                    WorkspaceFolderRow(
                        title: "Works",
                        subtitle: "Researcher-authored papers, chapters, and prose",
                        symbol: "square.and.pencil",
                        url: $outputURL
                    )
                }
                header: {
                    settingsSectionTitle("Research Folders")
                }

                Section {
                    PortableControlFolderRow(
                        worksURL: outputURL,
                        containerURL: $portableContainerURL
                    )
                    Text("Scholium stores the small portable .scholium folder beside Works. macOS therefore asks once for access to the folder containing Works; it is not added as a fourth vault.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .frame(
                            maxWidth: ScholiumMetrics.Settings.formExplanationMaximumWidth,
                            alignment: .leading
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                header: {
                    settingsSectionTitle("Portable Triptych Data")
                }

                Section {
                    if haveCommonParent {
                        Label("These folders share one parent.", systemImage: "checkmark.circle.fill")
                            .scholiumForeground(.confirmed)
                    } else if allFoldersSelected {
                        Label("These folders are independent. Keeping them under one parent can make the workspace easier to move and back up.", systemImage: "info.circle")
                            .scholiumForeground(.secondaryText)
                    }
                }
            }
            .scholiumSettingsForm()

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.destructive)
                    .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
                    .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                    .accessibilityLabel("Workspace error: \(errorMessage)")
            } else if let recoveryMessage = settingsModel.workspaceRecoveryMessage {
                Label(recoveryMessage, systemImage: "folder.badge.questionmark")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.attention)
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
                    .buttonStyle(.borderedProminent)
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

    private var haveCommonParent: Bool {
        guard let paperAnalysisURL, let topicKnowledgeURL, let outputURL else { return false }
        return Set([paperAnalysisURL, topicKnowledgeURL, outputURL].map {
            $0.standardizedFileURL.deletingLastPathComponent().path
        }).count == 1
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
                    .scholiumForeground(.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                    Text("Folder Containing Works")
                        .font(ScholiumTypography.interface(.rowTitle))
                    Text("Authorizes portable settings stored beside Works")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                    Text(containerURL?.path(percentEncoded: false) ?? "Authorization required")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(
                            containerURL == nil ? .secondaryText : .primaryText
                        )
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
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
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
    let subtitle: String
    let symbol: String
    @Binding var url: URL?
    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
            HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
                Image(systemName: symbol)
                    .scholiumSymbolStyle(.prominent)
                    .scholiumForeground(.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.rowDetailSpacing) {
                    Text(ScholiumL10n.dynamicString(title))
                        .font(ScholiumTypography.interface(.rowTitle))
                    Text(ScholiumL10n.dynamicString(subtitle))
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                    Text(url?.path(percentEncoded: false) ?? "No folder selected")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(url == nil ? .secondaryText : .primaryText)
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
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
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
