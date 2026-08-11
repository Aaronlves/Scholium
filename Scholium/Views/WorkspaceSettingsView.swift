import ScholiumContracts
import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScholiumSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("scholium.settings.selectedPane") private var persistedPane = "vaults"

    var body: some View {
        TabView(selection: selectedPane) {
            WorkspaceSettingsView()
                .tabItem { Label(ScholiumL10n.Settings.vaults, systemImage: "externaldrive") }
                .tag(WorkspaceSettingsPane.vaults)

            Group {
                if let store = settingsModel.cssSnippetStore {
                    AppearanceSettingsView(store: store)
                } else {
                    ScholiumContentStateView(
                        "Appearance Unavailable",
                        detail: Text("Open a complete Triptych to manage its appearance."),
                        indicator: .symbol("paintbrush", role: .attention)
                    )
                }
            }
                .tabItem {
                    Label(ScholiumL10n.Settings.appearance, systemImage: "paintbrush")
                }
                .tag(WorkspaceSettingsPane.appearance)

            PropertiesSettingsView()
                .tabItem {
                    Label(ScholiumL10n.Settings.properties, systemImage: "slider.horizontal.3")
                }
                .tag(WorkspaceSettingsPane.properties)

            ResearchGuidanceSettingsView()
                .tabItem {
                    Label(ScholiumL10n.Settings.researchGuidance, systemImage: "text.bubble")
                }
                .tag(WorkspaceSettingsPane.researchGuidance)

            AttentionSettingsView()
                .tabItem {
                    Label(ScholiumL10n.Settings.attention, systemImage: "exclamationmark.triangle")
                }
                .tag(WorkspaceSettingsPane.attention)

            ZoteroSettingsView()
                .tabItem { Label(ScholiumL10n.Settings.zotero, systemImage: "books.vertical") }
                .tag(WorkspaceSettingsPane.zotero)
        }
        .padding(ScholiumGrid.Spacing.inlineControlGap)
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
            let restoredPane = persistedPane == "document-styles"
                ? WorkspaceSettingsPane.appearance
                : WorkspaceSettingsPane(rawValue: persistedPane) ?? .vaults
            settingsModel.selectPane(restoredPane)
        }
        .onChange(of: settingsModel.selectedPane) { _, pane in
            persistedPane = pane.rawValue
        }
    }

    private var selectedPane: Binding<WorkspaceSettingsPane> {
        Binding(
            get: { settingsModel.selectedPane },
            set: { settingsModel.selectPane($0) }
        )
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
        Form {
            Section("Dismissed Attention") {
                Picker("Return dismissed items after", selection: $dismissalDays) {
                    ForEach(durations, id: \.self) { days in
                        Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                .frame(maxWidth: 300)

                Button("Save Attention Settings") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || dismissalDays == settingsModel.triptychSettings.attentionDismissalDays)

                Button("Restore All Dismissed Items") {
                    var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
                    ledger.removeAll()
                    dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
                }
                .disabled(!hasDismissedAttention)

                Text("Timed dismissal hides only the derived reminder for the selected duration. Leave Unchanged hides only the exact Material revision pair until the Material changes again or you restore dismissed items here. Neither action changes a note, its Connections, or Research Record facts.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }

            Section("What Attention Can Report") {
                Text("Possible orphan structure, Changed Since Settled, broken or ambiguous Connections, malformed metadata, and unresolved note identity.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                Text("Attention does not judge truth, evidence, philosophical quality, or how a note may be used.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
        }
        .formStyle(.grouped)
        .padding(ScholiumGrid.Spacing.nestedContentInset)
        .task {
            let stored = settingsModel.triptychSettings.attentionDismissalDays
            dismissalDays = durations.contains(stored)
                ? stored
                : TriptychSettings().attentionDismissalDays
        }
        .alert("Could Not Save Attention Settings", isPresented: Binding(
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
                        ? String(localized: "Attention settings saved", table: "Localizable", bundle: .module)
                        : result.warning ?? String(localized: "Settings saved to the previously active Triptych.", table: "Localizable", bundle: .module)
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private struct PropertiesSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var selectedSlot: WorkspaceVaultSlot = .paperAnalysis
    @State private var configurations = TriptychSettings.defaultProperties
    @State private var savedConfigurations = TriptychSettings.defaultProperties
    @State private var seedDrafts: [WorkspaceVaultSlot: String] = [:]
    @State private var savedSeedDrafts: [WorkspaceVaultSlot: String] = [:]
    @State private var agentCreation = AnalysisAgentCreationConfiguration()
    @State private var savedAgentCreation = AnalysisAgentCreationConfiguration()
    @State private var savedTriptychSettings = TriptychSettings()
    @State private var savedSettingsRevision: SettingsRevision?
    @State private var savedTriptychID: UUID?
    @State private var selectedSourceType: AnalysisSourceType = .journalArticle
    @State private var customField = ""
    @State private var customFieldMessage: String?
    @State private var isSaving = false
    @State private var hasLoaded = false
    @State private var revisionConflict = false
    @State private var errorMessage: String?
    @State private var seedSelection: TextSelection?
    @FocusState private var seedEditorIsFocused: Bool

    private var selectedProfile: SchemaProfileID {
        switch selectedSlot {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
    }

    private var recommendedKeys: [String] {
        PropertyPresentationCatalog.presentations(for: selectedProfile).map(\.key)
    }

    private var availableKeys: [String] {
        let configuration = selectedConfiguration
        let present = settingsModel.propertyKeys(for: selectedSlot)
        return Array(Set(
            configuration.visibleFields
                + configuration.editableFields
                + recommendedKeys
                + present
        ))
            .filter { !ResearcherPropertyPolicy.isHidden($0) }
            .sorted { displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending }
    }

    private var selectedConfiguration: VaultPropertiesConfiguration {
        var configuration = configurations[selectedSlot] ?? TriptychSettings.defaultProperties[selectedSlot]
            ?? VaultPropertiesConfiguration()
        configuration.visibleFields.removeAll {
            !AboutProfileCatalog.allowsOptionalField($0, profile: selectedProfile)
        }
        configuration.editableFields.removeAll { !ResearcherPropertyPolicy.isHumanEditable($0) }
        return configuration
    }

    private var roleName: String {
        switch selectedSlot {
        case .paperAnalysis: "Analysis"
        case .topicKnowledge: "Topic"
        case .output: "Work"
        }
    }

    private var candidateSettings: TriptychSettings {
        PropertiesSettingsCandidateBuilder.build(
            from: savedTriptychSettings,
            configurations: configurations,
            seedDrafts: seedDrafts,
            agentCreation: agentCreation
        )
    }

    private var validationMessage: String? {
        validationDiagnostic?.displayMessage
    }

    private struct SettingsDiagnostic {
        enum Section {
            case newNoteYAML
            case agentRequirements
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
                reason: String(localized: "The complete Properties candidate could not be validated.", table: "Localizable", bundle: .module),
                repair: String(localized: "Review the complete Properties candidate before saving.", table: "Localizable", bundle: .module)
            )
        }
    }

    private var currentSeedDiagnostic: SettingsDiagnostic? {
        guard let diagnostic = validationDiagnostic,
              diagnostic.section == .newNoteYAML,
              diagnostic.role == selectedSlot,
              diagnostic.sourceType == nil else { return nil }
        return diagnostic
    }

    private var currentAgentDiagnostic: SettingsDiagnostic? {
        guard let diagnostic = validationDiagnostic,
              diagnostic.section == .agentRequirements,
              diagnostic.role == .paperAnalysis,
              diagnostic.sourceType == selectedSourceType else { return nil }
        return diagnostic
    }

    private var isDirty: Bool {
        candidateSettings != savedTriptychSettings
    }

    private var selectedSeed: Binding<String> {
        Binding(
            get: { seedDrafts[selectedSlot] ?? "" },
            set: { seedDrafts[selectedSlot] = $0 }
        )
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
        .onChange(of: selectedSlot) { _, _ in
            customField = ""
            customFieldMessage = nil
            seedSelection = nil
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
            Text("Properties")
                .font(ScholiumTypography.interface(.primaryTitle))
            Text("Manage future New Note YAML, Agent creation requirements, About, and structured editing for each Triptych role.")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
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
            Picker("Role", selection: $selectedSlot) {
                Text("Analysis").tag(WorkspaceVaultSlot.paperAnalysis)
                Text("Topic").tag(WorkspaceVaultSlot.topicKnowledge)
                Text("Work").tag(WorkspaceVaultSlot.output)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Properties role")

            ScrollView {
                LazyVStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    newNotesSection
                    if selectedSlot == .paperAnalysis {
                        Divider()
                        agentRequirementsSection
                    }
                    Divider()
                    displayOrderColumn
                    Divider()
                    editableFieldsColumn
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    customFieldInput
                    customFieldButtons
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    customFieldInput
                    customFieldButtons
                }
            }
            if let customFieldMessage {
                Text(customFieldMessage)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }

            if let diagnostic = validationDiagnostic {
                settingsValidationSummary(diagnostic)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    restoreAndClearActions
                    Spacer()
                    revertAndSaveActions
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    restoreAndClearActions
                    revertAndSaveActions
                }
            }
        }
        .padding(ScholiumMetrics.Settings.editorContentInset)
        .disabled(isSaving)
    }

    private var unavailableSettingsContent: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ScholiumContentStateView(
                unavailableSettingsTitle,
                detail: settingsModel.errorMessage.map(Text.init(verbatim:))
                    ?? Text(unavailableSettingsDetail),
                indicator: .symbol("slider.horizontal.3", role: .attention)
            )
            Button("Retry Properties Settings") {
                Task { await settingsModel.refresh() }
            }
            .disabled(settingsModel.isRefreshing)
        }
        .padding(ScholiumMetrics.Settings.editorContentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var unavailableSettingsTitle: LocalizedStringResource {
        switch settingsModel.portableSettingsState {
        case .unavailable: "Properties Require a Complete Triptych"
        case .missing: "Portable Properties Settings Are Missing"
        case .oldSchema: "Properties Settings Use an Older Schema"
        case .futureSchema: "Properties Settings Use a Newer Schema"
        case .corrupted: "Properties Settings Are Damaged"
        case .current, .needsReview: "Properties Settings Need Attention"
        }
    }

    private var unavailableSettingsDetail: LocalizedStringResource {
        switch settingsModel.portableSettingsState {
        case .unavailable:
            "Open or configure a complete Triptych before changing portable Properties settings."
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

    private var newNotesSection: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("YAML Added to New Notes")
                .font(ScholiumTypography.interface(.sectionTitle))
            Text("Every key here is written to every future \(roleName) note. Empty values remain present properties.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)

            VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                Text("---")
                    .font(ScholiumTypography.exact(.body))
                    .scholiumForeground(.mutedText)
                    .accessibilityLabel("Opening YAML boundary added by Scholium")
                TextEditor(text: selectedSeed, selection: $seedSelection)
                    .font(ScholiumTypography.exact(.body))
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(minHeight: 128)
                    .scrollContentBackground(.hidden)
                    .padding(ScholiumGrid.Spacing.labelAccessoryGap)
                    .background(
                        ScholiumColorRole.documentBackground.color,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialTextEditorCornerRadius,
                            style: .continuous
                        )
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialTextEditorCornerRadius,
                            style: .continuous
                        )
                        .stroke(
                            currentSeedDiagnostic == nil
                                ? ScholiumColorRole.separator.color
                                : ScholiumColorRole.destructive.color,
                            lineWidth: 1
                        )
                    )
                    .accessibilityLabel("YAML added to new \(roleName) notes without boundaries")
                    .focused($seedEditorIsFocused)
                Text("---")
                    .font(ScholiumTypography.exact(.body))
                    .scholiumForeground(.mutedText)
                    .accessibilityLabel("Closing YAML boundary added by Scholium")
            }

            Text("This source becomes part of every new note and may sync with the Triptych. Do not store passwords, access tokens, or machine-local paths here.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            if let diagnostic = currentSeedDiagnostic {
                Label(diagnostic.displayMessage, systemImage: "exclamationmark.circle")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.propertiesSettings.validation")
            }
            if revisionConflict {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text("The saved Properties settings changed after this draft was loaded. The saved version and this draft were both preserved.")
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
    }

    private var agentRequirementsSection: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Agent-Created Analyses")
                .font(ScholiumTypography.interface(.sectionTitle))
            Text("Choose fields an authenticated Agent must provide when it creates this source type. Source Type is always required.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            Picker("Source Type", selection: $selectedSourceType) {
                ForEach(AnalysisSourceType.allCases, id: \.self) { sourceType in
                    Text(sourceType.propertyDisplayName).tag(sourceType)
                }
            }
            .frame(maxWidth: 320)

            ForEach(agentRequirementGroups, id: \.group) { group in
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text(group.group.label)
                        .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                        .scholiumForeground(.secondaryText)
                        .accessibilityHeading(.h3)
                    ForEach(group.fields, id: \.key) { field in
                        agentRequirementRow(field)
                    }
                }
            }

            Button("Clear Requirements for This Source Type") {
                agentCreation.requiredFieldsBySourceType.removeValue(forKey: selectedSourceType)
            }
            .disabled(agentCreation.requiredFields(for: selectedSourceType).isEmpty)

            if let diagnostic = currentAgentDiagnostic {
                Label(diagnostic.displayMessage, systemImage: "exclamationmark.circle")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var agentRequirementGroups: [(
        group: PropertyPresentationGroup,
        fields: [PropertyPresentation]
    )] {
        let sourceProfile = AnalysisSourceTypeProfileCatalog.profile(for: selectedSourceType)
        let applicable = Set(sourceProfile.applicableFields).subtracting(["type"])
        let recommended = Set(sourceProfile.recommendedFieldOrder)
        let fields = PropertyPresentationCatalog.presentations(for: .analysis)
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

    private func agentRequirementRow(_ field: PropertyPresentation) -> some View {
        let required = agentCreation.requiredFields(for: selectedSourceType).contains(field.key)
        let seedCollision = analysisSeedKeys.contains(field.key)
        return Toggle(isOn: Binding(
            get: { required },
            set: { enabled in
                var fields = agentCreation.requiredFields(for: selectedSourceType)
                if enabled {
                    if !fields.contains(field.key) { fields.append(field.key) }
                } else {
                    fields.removeAll { $0 == field.key }
                }
                agentCreation.requiredFieldsBySourceType[selectedSourceType] = fields
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
                if seedCollision {
                    Text("Already supplied by the Analysis New Note YAML; remove one requirement before saving.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.destructive)
                } else if let help = field.help {
                    Text(help)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("\(selectedSourceType.propertyDisplayName), \(field.label), \(field.key), required from Agent")
        .accessibilityValue(required ? "Required" : "Not required")
    }

    private var analysisSeedKeys: Set<String> {
        let source = candidateSettings.properties[.paperAnalysis]?.newNoteYAML
        return (try? TriptychSettingsValidator.seedKeys(
            in: source,
            role: .paperAnalysis
        )) ?? []
    }

    private var displayOrderColumn: some View {
        GroupBox("About") {
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

    private var editableFieldsColumn: some View {
        GroupBox("Structured Editing") {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                ForEach(editableConfigurationGroups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.explanationSpacing) {
                        Text(group.group.label)
                            .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                            .scholiumForeground(.secondaryText)
                            .accessibilityHeading(.h3)
                        ForEach(group.keys, id: \.self) { key in
                            HStack {
                                Toggle(isOn: Binding(
                                    get: { selectedConfiguration.editableFields.contains(key) },
                                    set: { enabled in
                                        updateSelectedConfiguration {
                                            $0.setHumanEditable(enabled, field: key)
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                                        Text(displayName(for: key))
                                        Text(key)
                                            .font(ScholiumTypography.exact(.small))
                                            .scholiumForeground(.mutedText)
                                        if PropertyPresentationCatalog.presentation(
                                            for: key,
                                            in: selectedProfile
                                        ) == nil {
                                            Text("Editable When Present")
                                                .font(ScholiumTypography.interface(.small))
                                                .scholiumForeground(.secondaryText)
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .disabled(!ResearcherPropertyPolicy.isHumanEditable(key))
                                .help(key)

                                if !ResearcherPropertyPolicy.isHumanEditable(key) {
                                    Text("Protected")
                                        .font(ScholiumTypography.interface(.small))
                                        .scholiumForeground(.secondaryText)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customFieldInput: some View {
        TextField("Custom top-level YAML field", text: $customField)
            .textFieldStyle(.roundedBorder)
            .onSubmit { addCustomFieldToDisplay() }
    }

    private var customFieldButtons: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Add to Display") { addCustomFieldToDisplay() }
                .disabled(normalizedCustomField == nil)
            Button("Editable When Present") { addCustomFieldToEditableFields() }
                .disabled(!customFieldCanBeEdited)
        }
    }

    private var restoreAndClearActions: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Restore About & Editing Defaults") {
                guard let defaults = TriptychSettings.defaultProperties[selectedSlot] else {
                    return
                }
                var configuration = selectedConfiguration
                configuration.visibleFields = defaults.visibleFields
                configuration.editableFields = defaults.editableFields
                configurations[selectedSlot] = configuration
                customFieldMessage = nil
            }
            Button("Clear New Note YAML") {
                seedDrafts[selectedSlot] = ""
            }
        }
    }

    private var revertAndSaveActions: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button("Revert to Saved") { revertToSaved() }
                .disabled(!isDirty)
            Button("Save Properties") { save() }
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
                .accessibilityIdentifier("scholium.propertiesSettings.validation")
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
            visibleFields: selectedConfiguration.visibleFields
        )
    }

    private var editableConfigurationGroups: [AboutProfileGroup] {
        let grouped = Dictionary(grouping: availableKeys) { key in
            PropertyPresentationCatalog.presentation(
                for: key,
                in: selectedProfile
            )?.group ?? .other
        }
        return PropertyPresentationCatalog.orderedGroups(for: selectedProfile).compactMap { group in
            guard let keys = grouped[group], !keys.isEmpty else { return nil }
            return AboutProfileGroup(group: group, keys: keys)
        }
    }

    private var hiddenAboutConfigurationGroups: [AboutProfileGroup] {
        let hidden = availableKeys.filter {
            AboutProfileCatalog.allowsOptionalField($0, profile: selectedProfile)
                && !selectedConfiguration.visibleFields.contains($0)
        }
        return AboutProfileCatalog.groupedEntries(
            for: selectedProfile,
            visibleFields: hidden
        )
    }

    private var normalizedCustomField: String? {
        let value = customField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !ResearcherPropertyPolicy.isHidden(value) else { return nil }
        return value
    }

    private var customFieldCanBeEdited: Bool {
        guard let field = normalizedCustomField else { return false }
        return ResearcherPropertyPolicy.isHumanEditable(field)
    }

    private func updateSelectedConfiguration(
        _ update: (inout VaultPropertiesConfiguration) -> Void
    ) {
        var configuration = selectedConfiguration
        update(&configuration)
        configurations[selectedSlot] = configuration
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

    private func addCustomFieldToDisplay() {
        guard let field = normalizedCustomField,
              AboutProfileCatalog.allowsOptionalField(field, profile: selectedProfile) else {
            customFieldMessage = "Enter a visible, non-machine YAML field name."
            return
        }
        updateSelectedConfiguration { $0.setVisible(true, field: field) }
        customField = ""
        customFieldMessage = "\(displayName(for: field)) was added at the end of the display order."
    }

    private func addCustomFieldToEditableFields() {
        guard let field = normalizedCustomField, customFieldCanBeEdited else {
            customFieldMessage = "Structured editing supports non-protected top-level YAML keys."
            return
        }
        updateSelectedConfiguration { $0.setHumanEditable(true, field: field) }
        customField = ""
        customFieldMessage = "\(displayName(for: field)) is now available in the structured Properties editor."
    }

    private func displayName(for key: String) -> String {
        if let presentation = PropertyPresentationCatalog.presentation(
            for: key,
            in: selectedProfile
        ) {
            return presentation.label
        }
        return key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
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
                    String(localized: "Properties configuration saved", table: "Localizable", bundle: .module)
                } else {
                    result.warning ?? String(localized: "Properties configuration saved", table: "Localizable", bundle: .module)
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
        let properties = settings.properties.isEmpty
            ? TriptychSettings.defaultProperties
            : settings.properties
        let seeds = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map {
            ($0, properties[$0]?.newNoteYAML ?? "")
        })
        configurations = properties
        savedConfigurations = properties
        seedDrafts = seeds
        savedSeedDrafts = seeds
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
        configurations = savedConfigurations
        seedDrafts = savedSeedDrafts
        agentCreation = savedAgentCreation
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
        var explicitPosition: FrontmatterSourcePosition?
        switch error {
        case .incompleteRoleConfiguration:
            role = nil; sourceType = nil; key = nil
            section = .configuration
            diagnosticReason = String(localized: "The Properties candidate is missing a Triptych role.", table: "Localizable", bundle: .module)
            repair = String(localized: "Restore the missing role configuration.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .noncanonicalConfigurationField(let value, let field):
            role = value; sourceType = nil; key = field
            section = .configuration
            diagnosticReason = String(localized: "This configuration field is blank, duplicated, or unnormalized.", table: "Localizable", bundle: .module)
            repair = String(localized: "Remove the blank or duplicate field entry.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .seedTooLarge(let value, let count):
            role = value; sourceType = nil; key = nil
            section = .newNoteYAML
            diagnosticReason = String(localized: "This New Note YAML is \(count) bytes and exceeds the 64 KiB limit.", table: "Localizable", bundle: .module)
            repair = String(localized: "Shorten this role's New Note YAML to 64 KiB or less.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .invalidSeed(let value, let field, let reason, let position):
            role = value; sourceType = nil; key = field
            section = .newNoteYAML
            diagnosticReason = localizedSeedReason(reason)
            repair = String(localized: "Repair the delimiter-free YAML source in this role.", table: "Localizable", bundle: .module)
            explicitPosition = position
        case .reservedSeedKey(let value, let field):
            role = value; sourceType = nil; key = field
            section = .newNoteYAML
            diagnosticReason = String(localized: "This key is reserved for a portable or machine-owned identity.", table: "Localizable", bundle: .module)
            repair = String(localized: "Remove this reserved key from the New Note YAML.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .canonicalSeedRoleMismatch(let value, let field):
            role = value; sourceType = nil; key = field
            section = .newNoteYAML
            diagnosticReason = String(localized: "This canonical key belongs to another Triptych role.", table: "Localizable", bundle: .module)
            repair = String(localized: "Remove the key or edit the role where it is canonical.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .invalidRequiredField(let type, let field):
            role = .paperAnalysis; sourceType = type; key = field
            section = .agentRequirements
            diagnosticReason = String(localized: "This is not a shape-known field that an Agent may create.", table: "Localizable", bundle: .module)
            repair = String(localized: "Clear this Agent requirement.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .requiredFieldNotApplicable(let type, let field):
            role = .paperAnalysis; sourceType = type; key = field
            section = .agentRequirements
            diagnosticReason = String(localized: "This required field does not apply to the selected Source Type.", table: "Localizable", bundle: .module)
            repair = String(localized: "Clear it or choose a source type where it applies.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .requiredFieldCollidesWithSeed(let type, let field):
            role = .paperAnalysis; sourceType = type; key = field
            section = .agentRequirements
            diagnosticReason = String(localized: "This field is supplied both by New Note YAML and as an Agent requirement.", table: "Localizable", bundle: .module)
            repair = String(localized: "Remove it from the seed or clear the Agent requirement.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .invalidAttentionDismissalDays:
            role = nil; sourceType = nil; key = nil
            section = .other
            diagnosticReason = String(localized: "Attention dismissal days must be positive.", table: "Localizable", bundle: .module)
            repair = String(localized: "Repair Attention settings before saving Properties.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        case .invalidPromptConfiguration:
            role = nil; sourceType = nil; key = nil
            section = .other
            diagnosticReason = String(localized: "The active Research Guidance template selection is incomplete or inconsistent.", table: "Localizable", bundle: .module)
            repair = String(localized: "Repair Research Guidance settings before saving Properties.", table: "Localizable", bundle: .module)
            explicitPosition = nil
        }
        let position = explicitPosition.map { (line: $0.line, column: $0.column) }
            ?? role.flatMap { role in
            key.flatMap { seedPosition(of: $0, role: role) }
        }
        return SettingsDiagnostic(
            section: section,
            role: role,
            sourceType: sourceType,
            key: key,
            line: position?.line,
            column: position?.column,
            reason: diagnosticReason,
            repair: repair
        )
    }

    private func localizedSeedReason(
        _ reason: TriptychSeedValidationReason
    ) -> String {
        switch reason {
        case .sourceNormalization:
            String(localized: "The seed uses unsupported newlines or lacks its terminating newline.", table: "Localizable", bundle: .module)
        case .patchRefusal(let refusal):
            switch refusal {
            case .invalidYAML:
                String(localized: "The YAML syntax is invalid.", table: "Localizable", bundle: .module)
            case .nonBlockMappingRoot:
                String(localized: "The seed must be a top-level YAML block mapping.", table: "Localizable", bundle: .module)
            case .ambiguousStructure:
                String(localized: "The YAML uses a structure that cannot be edited safely as Properties.", table: "Localizable", bundle: .module)
            case .unsupportedExistingValue:
                String(localized: "An existing YAML value cannot be bounded for a safe Properties edit.", table: "Localizable", bundle: .module)
            case .semanticMismatch:
                String(localized: "The encoded YAML did not preserve the requested Property value.", table: "Localizable", bundle: .module)
            }
        case .topLevelMappingRequired:
            String(localized: "The seed must contain at least one top-level mapping entry.", table: "Localizable", bundle: .module)
        case .propertyIssue(let code):
            switch code {
            case .malformedFrontmatter:
                String(localized: "The YAML frontmatter is malformed.", table: "Localizable", bundle: .module)
            case .invalidValueKind:
                String(localized: "A canonical property has the wrong value shape.", table: "Localizable", bundle: .module)
            case .valueNotAllowed:
                String(localized: "A canonical property contains a value that is not allowed.", table: "Localizable", bundle: .module)
            case .invalidCreator:
                String(localized: "A creator entry is incomplete or malformed.", table: "Localizable", bundle: .module)
            }
        }
    }

    private func reveal(_ diagnostic: SettingsDiagnostic) {
        if let role = diagnostic.role { selectedSlot = role }
        if let sourceType = diagnostic.sourceType {
            selectedSlot = .paperAnalysis
            selectedSourceType = sourceType
        }
        guard diagnostic.section == .newNoteYAML,
              let role = diagnostic.role,
              let line = diagnostic.line else { return }
        Task { @MainActor in
            await Task.yield()
            selectSeedLine(line, role: role)
        }
    }

    private func selectSeedLine(_ line: Int, role: WorkspaceVaultSlot) {
        guard role == selectedSlot, line > 0 else { return }
        let source = seedDrafts[role] ?? ""
        var start = source.startIndex
        if line > 1 {
            for _ in 1..<line {
                guard let newline = source[start...].firstIndex(of: "\n") else { return }
                start = source.index(after: newline)
            }
        }
        let end = source[start...].firstIndex(of: "\n") ?? source.endIndex
        seedSelection = TextSelection(range: start..<end)
        seedEditorIsFocused = true
    }

    private func seedPosition(
        of key: String,
        role: WorkspaceVaultSlot
    ) -> (line: Int, column: Int)? {
        let lines = (seedDrafts[role] ?? "").split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        for (index, line) in lines.enumerated() {
            let source = String(line)
            let leading = source.prefix { $0 == " " || $0 == "\t" }
            let remainder = source.dropFirst(leading.count)
            if remainder.hasPrefix("\(key):") {
                return (index + 1, leading.count + 1)
            }
        }
        return nil
    }

    private func profile(for slot: WorkspaceVaultSlot) -> SchemaProfileID {
        switch slot {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
    }
}

struct AgentCLISettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var status: CommandLineToolStatus?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        GroupBox("Scholium CLI") {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if let status {
                    Label(statusLabel(status), systemImage: statusSymbol(status))
                        .accessibilityLabel("Scholium CLI status")
                        .accessibilityValue(statusLabel(status))
                        .accessibilityIdentifier("scholium.agentCLI.status")
                    Text(status.installPath)
                        .font(ScholiumTypography.exact(.small))
                        .scholiumForeground(.secondaryText)
                        .textSelection(.enabled)
                        .accessibilityLabel("CLI installation path")
                        .accessibilityValue(status.installPath)
                    if let repair = status.repairMessage {
                        Text(repair)
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                    HStack {
                        if status.state == .notInstalled || status.state == .updateAvailable {
                            Button(status.state == .updateAvailable ? "Update" : "Install") {
                                Task { await install() }
                            }
                            .disabled(isWorking)
                            .accessibilityHint(
                                "Installs the bundled Scholium command in the displayed user-local path"
                            )
                            .accessibilityIdentifier("scholium.agentCLI.install")
                        }
                        if !status.isOnCurrentPATH
                            && (status.state == .installed || status.state == .updateAvailable) {
                            Button("Copy PATH Setup") {
                                let copied = ScholiumPasteboardWriter.general.writeText(
                                    "export PATH=\"$HOME/.local/bin:$PATH\""
                                )
                                let message = copied
                                    ? String(
                                        localized: "PATH setup copied",
                                        table: "Localizable",
                                        bundle: .module
                                    )
                                    : String(
                                        localized: "PATH setup could not be copied.",
                                        table: "Localizable",
                                        bundle: .module
                                    )
                                settingsModel.showToast(message)
                            }
                            .accessibilityHint(
                                "Copies a shell command; run it in your shell profile and start a new agent task"
                            )
                            .accessibilityIdentifier("scholium.agentCLI.pathSetup")
                        }
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                } else {
                    ProgressView("Checking command-line tool…")
                        .controlSize(.small)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("scholium.agentCLI.section")
        .task { status = await settingsModel.commandLineToolStatus() }
    }

    private func install() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            status = try await settingsModel.installCommandLineTool()
            settingsModel.showToast(String(localized: "Scholium CLI installed", table: "Localizable", bundle: .module))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func statusLabel(_ status: CommandLineToolStatus) -> String {
        switch status.state {
        case .bundledToolUnavailable: "Not included in this build"
        case .notInstalled: "Ready to install"
        case .updateAvailable: "Update available"
        case .installed: status.isOnCurrentPATH ? "Installed and discoverable" : "Installed"
        case .invalidInstallation: "Needs attention"
        }
    }

    private func statusSymbol(_ status: CommandLineToolStatus) -> String {
        switch status.state {
        case .installed: status.isOnCurrentPATH ? "checkmark.circle" : "checkmark"
        case .notInstalled, .updateAvailable: "terminal"
        case .bundledToolUnavailable, .invalidInstallation: "exclamationmark.triangle"
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
        GroupBox {
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
        } label: {
            Label("Citation Style", systemImage: "text.book.closed")
                .font(ScholiumTypography.interface(.sectionTitle))
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
        Form {
            Section("Read-Only Zotero Access") {
                LabeledContent("Local API") {
                    Label(statusTitle, systemImage: statusSymbol)
                        .scholiumForeground(statusColorRole)
                }
                LabeledContent("Last Connected") {
                    Text(info.lastSuccessfulConnection?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                        .scholiumForeground(.secondaryText)
                }
                HStack {
                    Button("Open Zotero") {
                        Task { await settingsModel.openZotero() }
                    }
                    Button("Check Connection") { refresh() }
                        .disabled(isTesting)
                    Button("Clear Connection History", role: .destructive) {
                        Task {
                            try? await settingsModel.clearZoteroConnectionHistory()
                            info = await settingsModel.zoteroConnectionInfo()
                        }
                    }
                }
                Text("Scholium talks only to Zotero Desktop on localhost. No account, password, online API key, or Zotero data-folder permission is required. Scholium never modifies Zotero data.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                if info.status == .apiDisabled {
                    Text("In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’, then test again.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                }
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .scholiumForeground(.destructive)
                }
            }
        }
        .formStyle(.grouped)
        .padding(ScholiumGrid.Spacing.nestedContentInset)
        .task { info = await settingsModel.zoteroConnectionInfo() }
    }

    private var statusTitle: String {
        switch info.status {
        case .available: "Connected"
        case .apiDisabled: "Access Disabled in Zotero"
        case .appUnavailable: "Zotero Not Available"
        case .itemMissing: "Connected"
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
        VStack(spacing: ScholiumMetrics.Settings.rootSpacing) {
            HStack(spacing: ScholiumMetrics.Settings.rootSpacing) {
                Picker("Triptych", selection: selectedTriptychBinding) {
                    ForEach(settingsModel.registeredTriptychs) { assignment in
                        Text(triptychLabel(assignment)).tag(Optional(assignment.id))
                    }
                }
                .frame(maxWidth: 360)
                .disabled(settingsModel.registeredTriptychs.isEmpty)

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
            .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
            .padding(.top, ScholiumGrid.Spacing.nestedContentInset)

            if let selectedTriptychID {
                WorkspacePathEditor(
                    title: "Manage Triptych",
                    explanation: "Change this Triptych’s three independent locations without moving or rewriting research files.",
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
        .padding(ScholiumGrid.Spacing.inlineControlGap)
        .task {
            await settingsModel.refreshRegisteredVaults()
            if selectedTriptychID == nil {
                selectedTriptychID = settingsModel.workspaceAssignment?.id
                    ?? settingsModel.registeredTriptychs.first?.id
            }
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

    private func triptychLabel(_ assignment: TriptychAssignment) -> String {
        let duplicates = settingsModel.registeredTriptychs.filter {
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
}

private struct AppearanceSettingsView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @ObservedObject var store: CSSSnippetStore
    @State private var draft: DocumentAppearanceProfile?
    @State private var importError: String?
    @State private var showRename = false
    @State private var showDeleteConfirmation = false
    @State private var nameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.listRowSpacing) {
                Text("Appearance")
                    .font(ScholiumTypography.interface(.primaryTitle))
                Text("Choose a named document configuration, then adjust line width, typography, and each semantic callout independently. Changes apply after saving; line width is shared by Review, Edit, and Source.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
            .padding(.top, ScholiumGrid.Spacing.sectionSeparation)
            .padding(.bottom, ScholiumGrid.Spacing.nestedContentInset)

            Divider()

            Form {
                Section("Configuration") {
                    HStack {
                        Picker("Configuration", selection: selectedProfileID) {
                            ForEach(store.appearanceProfiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280)

                        Button("New") { store.createAppearance() }
                        Button("Duplicate") {
                            guard let id = store.selectedAppearanceProfileID else { return }
                            store.duplicateAppearance(id)
                        }
                        .disabled(store.selectedAppearanceProfileID == nil)
                        Button("Rename…") { beginRename() }
                            .disabled(store.selectedAppearanceProfileID == nil)
                        Button("Delete…", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(store.appearanceProfiles.count <= 1)
                    }
                    Text("Exactly one configuration is active. Configurations are stored in Scholium’s Application Support folder, not in the research vault.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }

                if let draftBinding {
                    AppearanceProfileEditor(profile: draftBinding)

                    Section {
                        HStack {
                            Button("Save Appearance") {
                                guard let draft else { return }
                                store.updateAppearance(draft)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasUnsavedChanges || !store.canModify)

                            if hasUnsavedChanges {
                                Text("Unsaved changes")
                                    .font(ScholiumTypography.interface(.small))
                                    .scholiumForeground(.secondaryText)
                            }
                        }
                    }
                }

                Section("Advanced CSS") {
                    Text("Optional CSS snippets remain available for advanced compatibility. They are additive and do not replace the selected structured configuration.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)

                    ForEach(store.snippets) { snippet in
                        CSSSnippetRow(
                            snippet: snippet,
                            error: store.validationErrors[snippet.id],
                            store: store
                        )
                    }

                    if store.snippets.isEmpty {
                        Text("No CSS snippets imported.")
                            .font(ScholiumTypography.interface(.body))
                            .scholiumForeground(.secondaryText)
                    }

                    HStack {
                        Button("Import CSS Snippet…") { importSnippet() }
                            .disabled(!store.canModify)
                        Button {
                            store.revealManagedFolder()
                        } label: {
                            Label("Reveal Styles in Finder", systemImage: "folder")
                        }
                        Spacer()
                        Button("Disable All Snippets") { store.disableAll() }
                            .disabled(store.enabledCount == 0 || !store.canModify)
                    }
                }
            }
            .formStyle(.grouped)
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
    }

    private var selectedProfileID: Binding<UUID?> {
        Binding(
            get: { store.selectedAppearanceProfileID },
            set: { id in
                guard let id else { return }
                store.selectAppearance(id)
                if let profile = store.appearanceProfiles.first(where: { $0.id == id }) {
                    draft = profile
                }
            }
        )
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

    var body: some View {
        Section("Layout") {
            AppearanceDoubleControl(
                "Line width",
                value: $profile.settings.lineWidthCharacterUnits,
                range: DocumentAppearanceSettings.lineWidthCharacterUnitsRange,
                step: 1,
                suffix: "ch",
                precision: 0,
                accessibilityUnit: "character-width units"
            )
            Text("Line width is measured in CSS character-width units; the exact number of characters varies by typeface.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
        }

        Section("Body") {
            Picker("Typeface", selection: $profile.settings.body.fontFamily) {
                ForEach(DocumentAppearanceFontFamily.allCases, id: \.self) { family in
                    Text(family.label).tag(family)
                }
            }
            AppearanceDoubleControl("Font size", value: $profile.settings.body.fontSizePoints, range: 9...24, step: 0.5, suffix: "pt")
            AppearanceDoubleControl("Line spacing", value: $profile.settings.body.lineHeight, range: 1.2...2.4, step: 0.05, suffix: "×")
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

        Section("Headings") {
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

        Section("Callouts") {
            Text("Typography is inherited from Body. These controls adjust the role’s spacing and composition without changing its semantic identity.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            ForEach(DocumentCalloutAppearanceRole.allCases, id: \.self) { role in
                if let index = profile.settings.callouts.firstIndex(where: { $0.role == role }) {
                    DisclosureGroup(role.label) {
                        CalloutAppearanceEditor(callout: $profile.settings.callouts[index])
                    }
                }
            }
        }

        Section("Mathematics") {
            LabeledContent("Display equations") {
                Text("Centered, italic, numbered at right")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
            }
            Text("Mathematics, code, and tables use Scholium’s shared restrained styles so their semantics and Read/Live parity remain stable across configurations.")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
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
                    .frame(minWidth: 150, idealWidth: 220)
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
        return slider
    }

    func updateNSView(_ slider: KeyboardAccessibleNSSlider, context: Context) {
        context.coordinator.parent = self
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.keyboardStep = step
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

    let title: String
    let explanation: String
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
            VStack(alignment: .leading, spacing: ScholiumMetrics.Settings.pathHeaderSpacing) {
                Text(ScholiumL10n.dynamicString(title))
                    .font(ScholiumTypography.interface(.primaryTitle))
                Text(ScholiumL10n.dynamicString(explanation))
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, ScholiumMetrics.Settings.pathHorizontalInset)
            .padding(.top, ScholiumMetrics.Settings.pathTopInset)
            .padding(.bottom, ScholiumMetrics.Settings.pathBottomInset)

            Divider()

            Form {
                Section("Triptych") {
                    TextField("Name", text: $triptychName)
                        .accessibilityIdentifier("scholium.triptychName")
                    Text("The name distinguishes complete research domains. Works folders remain ordinary researcher-controlled folders, not app-managed projects.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }

                Section("Research Folders") {
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

                Section("Portable Triptych Data") {
                    PortableControlFolderRow(
                        worksURL: outputURL,
                        containerURL: $portableContainerURL
                    )
                    Text("Scholium stores the small portable .scholium folder beside Works. macOS therefore asks once for access to the folder containing Works; it is not added as a fourth vault.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
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
            .formStyle(.grouped)

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
