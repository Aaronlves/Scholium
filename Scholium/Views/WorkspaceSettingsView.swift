import ScholiumContracts
import Accessibility
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScholiumSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("scholium.settings.selectedPane") private var persistedPane = "vaults"
    @StateObject private var researchGuidanceDraftStore = ResearchGuidanceDraftStore()

    var body: some View {
        TabView(selection: selectedPane) {
            WorkspaceSettingsView()
                .tabItem { Label(ScholiumL10n.Settings.vaults, systemImage: "externaldrive") }
                .tag(WorkspaceSettingsPane.vaults)

            Group {
                if let store = settingsModel.cssSnippetStore {
                    AppearanceSettingsView(store: store)
                } else {
                    ContentUnavailableView("Appearance Unavailable", systemImage: "paintbrush")
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

            ResearchGuidanceSettingsView(draftStore: researchGuidanceDraftStore)
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
        .padding(8)
        .overlay(alignment: .bottom) {
            if let message = settingsModel.toastMessage {
                ToastView(message: message)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .padding(.bottom, 20)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What Attention Can Report") {
                Text("Possible orphan structure, Changed Since Settled, broken or ambiguous Connections, malformed metadata, and unresolved note identity.")
                    .foregroundStyle(.secondary)
                Text("Attention does not judge truth, evidence, philosophical quality, or how a note may be used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
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
                try await settingsModel.saveTriptychSettings(settings)
                dismissalDays = settings.attentionDismissalDays
                settingsModel.showToast(String(localized: "Attention settings saved", table: "Localizable", bundle: .module))
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
    @State private var customField = ""
    @State private var customFieldMessage: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vault-Wide Properties")
                .font(.title2.weight(.semibold))
            Text("Set the optional About fields, display order, and structured-editing allowlist for each Triptych vault. The role-specific Research Unit remains part of the default About profile; Source mode always exposes the exact YAML.")
                .foregroundStyle(.secondary)
            Picker("Vault", selection: $selectedSlot) {
                ForEach(WorkspaceVaultSlot.allCases) { slot in
                    Text(ScholiumL10n.dynamicString(slot.displayName)).tag(slot)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 24) {
                displayOrderColumn
                editableFieldsColumn
            }
            .frame(maxHeight: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Custom top-level YAML field", text: $customField)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addCustomFieldToDisplay() }
                Button("Add to Display") { addCustomFieldToDisplay() }
                    .disabled(normalizedCustomField == nil)
                Button("Allow Editing") { addCustomFieldToEditableFields() }
                    .disabled(!customFieldCanBeEdited)
            }
            if let customFieldMessage {
                Text(customFieldMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Restore Defaults") {
                    configurations[selectedSlot] = TriptychSettings.defaultProperties[selectedSlot]
                    customFieldMessage = nil
                }
                Spacer()
                Button("Save Properties") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
        }
        .padding(18)
        .task { configurations = settingsModel.triptychSettings.properties.isEmpty
            ? TriptychSettings.defaultProperties
            : settingsModel.triptychSettings.properties }
        .onChange(of: selectedSlot) { _, _ in
            customField = ""
            customFieldMessage = nil
        }
        .alert("Could Not Save Properties", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var displayOrderColumn: some View {
        GroupBox("Shown in This Order") {
            VStack(alignment: .leading, spacing: 8) {
                if selectedConfiguration.visibleFields.isEmpty {
                    Text("No fields are shown when Properties is opened.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(selectedConfiguration.visibleFields.enumerated()), id: \.element) { index, key in
                                HStack(spacing: 6) {
                                    Text(displayName(for: key))
                                        .lineLimit(1)
                                        .help(key)
                                    Spacer(minLength: 6)
                                    Button {
                                        moveVisibleField(key, to: index - 1)
                                    } label: {
                                        Image(systemName: "chevron.up")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(index == 0)
                                    .help("Move \(displayName(for: key)) up")
                                    .accessibilityLabel("Move \(displayName(for: key)) up")

                                    Button {
                                        moveVisibleField(key, to: index + 1)
                                    } label: {
                                        Image(systemName: "chevron.down")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(index == selectedConfiguration.visibleFields.count - 1)
                                    .help("Move \(displayName(for: key)) down")
                                    .accessibilityLabel("Move \(displayName(for: key)) down")

                                    Button {
                                        updateSelectedConfiguration { $0.setVisible(false, field: key) }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Hide \(displayName(for: key))")
                                    .accessibilityLabel("Hide \(displayName(for: key))")
                                }
                            }
                        }
                    }
                }

                Menu("Add Visible Field") {
                    let hidden = availableKeys.filter {
                        AboutProfileCatalog.allowsOptionalField($0, profile: selectedProfile)
                            && !selectedConfiguration.visibleFields.contains($0)
                    }
                    if hidden.isEmpty {
                        Text("All available fields are shown")
                    } else {
                        ForEach(hidden, id: \.self) { key in
                            Button(displayName(for: key)) {
                                updateSelectedConfiguration { $0.setVisible(true, field: key) }
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
        GroupBox("Human-Editable Fields") {
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(availableKeys, id: \.self) { key in
                        HStack {
                            Toggle(isOn: Binding(
                            get: { selectedConfiguration.editableFields.contains(key) },
                            set: { enabled in
                                updateSelectedConfiguration {
                                    $0.setHumanEditable(enabled, field: key)
                                }
                            }
                        )) {
                            Text(displayName(for: key))
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!ResearcherPropertyPolicy.isHumanEditable(key))
                        .help(key)

                            if !ResearcherPropertyPolicy.isHumanEditable(key) {
                                Text("Protected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var normalizedCustomField: String? {
        let value = customField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !ResearcherPropertyPolicy.isHidden(value) else { return nil }
        return value
    }

    private var customFieldCanBeEdited: Bool {
        guard let field = normalizedCustomField else { return false }
        return ResearcherPropertyPolicy.isHumanEditable(field)
            && field.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private func updateSelectedConfiguration(
        _ update: (inout VaultPropertiesConfiguration) -> Void
    ) {
        var configuration = selectedConfiguration
        update(&configuration)
        configurations[selectedSlot] = configuration
    }

    private func moveVisibleField(_ field: String, to index: Int) {
        updateSelectedConfiguration { $0.moveVisibleField(field, to: index) }
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
            customFieldMessage = "Structured editing supports simple, non-protected top-level YAML keys."
            return
        }
        updateSelectedConfiguration { $0.setHumanEditable(true, field: field) }
        customField = ""
        customFieldMessage = "\(displayName(for: field)) is now available in the structured Properties editor."
    }

    private func displayName(for key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func save() {
        isSaving = true
        Task {
            do {
                var settings = settingsModel.triptychSettings
                var sanitized: [WorkspaceVaultSlot: VaultPropertiesConfiguration] = [:]
                for (slot, configuration) in configurations {
                    var result = configuration
                    let profile: SchemaProfileID = switch slot {
                    case .paperAnalysis: .analysis
                    case .topicKnowledge: .topicMarkdown
                    case .output: .draftProject
                    }
                    result.visibleFields.removeAll {
                        !AboutProfileCatalog.allowsOptionalField($0, profile: profile)
                    }
                    result.editableFields.removeAll { !ResearcherPropertyPolicy.isHumanEditable($0) }
                    sanitized[slot] = result
                }
                settings.properties = sanitized
                try await settingsModel.saveTriptychSettings(settings)
                settingsModel.showToast(String(localized: "Properties configuration saved", table: "Localizable", bundle: .module))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
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
            VStack(alignment: .leading, spacing: 8) {
                if let status {
                    Label(statusLabel(status), systemImage: statusSymbol(status))
                        .accessibilityLabel("Scholium CLI status")
                        .accessibilityValue(statusLabel(status))
                        .accessibilityIdentifier("scholium.agentCLI.status")
                    Text(status.installPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel("CLI installation path")
                        .accessibilityValue(status.installPath)
                    if let repair = status.repairMessage {
                        Text(repair)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(
                                    "export PATH=\"$HOME/.local/bin:$PATH\"",
                                    forType: .string
                                )
                                settingsModel.showToast(String(localized: "PATH setup copied", table: "Localizable", bundle: .module))
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
                        .font(.caption)
                        .foregroundStyle(ScholiumColorRole.attention.color)
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

/// Recommended Bibliography uses one complete Source Analyzer independently
/// of Research Action methods.
struct RecommendedBibliographyMethodSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var status: RecommendedBibliographyMethodStatus?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var loadIdentity: String {
        settingsModel.activeTriptychServicesID?.uuidString ?? "none"
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let status {
                    Picker("Bibliography Method", selection: selection) {
                        Text("Built-in Source Analyzer").tag(String?.none)
                        ForEach(status.candidates) { candidate in
                            Text(verbatim: candidate.name).tag(String?.some(candidate.packageID))
                        }
                    }
                    .frame(maxWidth: 420)
                    .disabled(isWorking)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.bibliographyMethod"
                    )

                    Text("Used only to screen reading leads from an Analysis. It does not create a Research Action, edit notes, or write to Zotero.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if status.issue != nil {
                        Label(
                            "The explicit bibliography method requires repair. Scholium will not silently fall back to the built-in method.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } else {
                    ProgressView("Loading bibliography method…")
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Bibliography Method", systemImage: "text.book.closed")
                .font(.headline)
        }
        .task(id: loadIdentity) { await reload() }
        .alert("Could Not Update Bibliography Method", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { status?.activePackageID },
            set: { packageID in
                guard packageID != status?.activePackageID else { return }
                update(packageID)
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
            status = try await settingsModel.bibliographyMethodStatus()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            status = nil
            errorMessage = error.localizedDescription
        }
    }

    private func update(_ packageID: String?) {
        guard let status else { return }
        isWorking = true
        Task {
            do {
                self.status = try await settingsModel.setBibliographyMethod(
                    packageID: packageID,
                    expectedBindingRevision: status.bindingRevision
                )
            } catch {
                errorMessage = error.localizedDescription
                await reload()
            }
            isWorking = false
        }
    }
}

/// Settings is the only presentation surface that activates Triptych-local
/// Researcher Skills. Actions receive semantic availability, never package
/// identifiers or routing metadata.
struct ResearchCitationMethodSettingsView: View {
    private struct CitationMethodChoice: Hashable {
        let packageID: String
        let citationStyle: String
    }

    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    let onStatusChange: (ResearchCitationMethodStatus) -> Void
    @State private var status: ResearchCitationMethodStatus?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let status {
                        if status.candidates.isEmpty {
                            Text("No Triptych citation method is installed.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Method", selection: activeMethodChoice) {
                                Text("None").tag(CitationMethodChoice?.none)
                                ForEach(status.candidates) { candidate in
                                    ForEach(candidate.citationStyles, id: \.self) { style in
                                        Text("\(candidate.name) — \(citationStyleTitle(style))")
                                            .tag(CitationMethodChoice?.some(
                                                CitationMethodChoice(
                                                    packageID: candidate.packageID,
                                                    citationStyle: style
                                                )
                                            ))
                                    }
                                }
                            }
                            .frame(maxWidth: 420)
                            .accessibilityIdentifier(
                                "scholium.researchGuidance.citationMethod"
                            )
                        }

                        if let active = activeCandidate(in: status) {
                            Text(active.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if status.bundledTemplateAvailable {
                            Button("Adopt APA 7 Starter") {
                                adoptStarter()
                            }
                            .disabled(isWorking)
                            .accessibilityIdentifier(
                                "scholium.researchGuidance.adoptAPAStarter"
                            )
                        }

                        if let issue = status.issue {
                            Label(issueDescription(issue.code), systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } else {
                        ProgressView("Loading citation methods…")
                    }
                }
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Citation Method", systemImage: "text.book.closed")
                .font(.headline)
        }
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .alert("Could Not Update Citation Method", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("scholium.researchGuidance.citationMethodSection")
    }

    private var activeMethodChoice: Binding<CitationMethodChoice?> {
        Binding(
            get: {
                guard let packageID = status?.activePackageID,
                      let citationStyle = status?.activeCitationStyle else { return nil }
                return CitationMethodChoice(
                    packageID: packageID,
                    citationStyle: citationStyle
                )
            },
            set: { newValue in
                let current = status.flatMap { current -> CitationMethodChoice? in
                    guard let packageID = current.activePackageID,
                          let citationStyle = current.activeCitationStyle else { return nil }
                    return CitationMethodChoice(
                        packageID: packageID,
                        citationStyle: citationStyle
                    )
                }
                guard newValue != current else { return }
                if let newValue {
                    activate(newValue)
                } else {
                    clear()
                }
            }
        )
    }

    private func activeCandidate(
        in status: ResearchCitationMethodStatus
    ) -> ResearchCitationMethodCandidate? {
        guard let activePackageID = status.activePackageID else { return nil }
        return status.candidates.first { $0.packageID == activePackageID }
    }

    private func citationStyleTitle(_ style: String) -> String {
        switch style.lowercased() {
        case "apa-7": "APA 7"
        case "chicago": "Chicago"
        case "mla": "MLA"
        case "oxford": "Oxford"
        default: style.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    private func issueDescription(_ code: ResearchCitationMethodIssueCode) -> String {
        switch code {
        case .missing:
            "Choose a citation method for Citations in Fidelity."
        case .malformedBinding:
            "The citation method selection needs repair."
        case .invalidPackage:
            "The selected citation method is invalid."
        case .missingCapability:
            "The selected skill does not provide citation verification."
        case .citationStyleMissing:
            "Choose the citation style that this method should apply."
        case .citationStyleMismatch:
            "The selected citation method has incompatible style metadata."
        }
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

    private func activate(_ choice: CitationMethodChoice) {
        perform {
            status = try await settingsModel.activateCitationMethod(
                packageID: choice.packageID,
                citationStyle: choice.citationStyle,
                expectedBindingRevision: status?.bindingRevision
            )
        }
    }

    private func clear() {
        perform {
            status = try await settingsModel.clearCitationMethod(
                expectedBindingRevision: status?.bindingRevision
            )
        }
    }

    private func adoptStarter() {
        perform {
            status = try await settingsModel.adoptBundledCitationStarter(
                expectedBindingRevision: status?.bindingRevision
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
            }
            catch { errorMessage = error.localizedDescription }
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
                        .foregroundStyle(statusColor)
                }
                LabeledContent("Last Connected") {
                    Text(info.lastSuccessfulConnection?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Zotero") {
                        Task { await settingsModel.openZotero() }
                    }
                    Button("Test Connection") { testConnection() }
                        .disabled(isTesting)
                    Button("Refresh Library Information") { refresh() }
                        .disabled(isTesting)
                    Button("Clear Connection History", role: .destructive) {
                        Task {
                            try? await settingsModel.clearZoteroConnectionHistory()
                            info = await settingsModel.zoteroConnectionInfo()
                        }
                    }
                }
                Text("Scholium talks only to Zotero Desktop on localhost. No account, password, online API key, or Zotero data-folder permission is required. Scholium never modifies Zotero data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if info.status == .apiDisabled {
                    Text("In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’, then test again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .padding(12)
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

    private var statusColor: Color {
        info.status == .available ? .green : .orange
    }

    private func testConnection() { refresh() }

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
        VStack(spacing: 10) {
            HStack(spacing: 10) {
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
            .padding(.horizontal, 20)
            .padding(.top, 12)

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
                ContentUnavailableView(
                    "No Triptych Registered",
                    systemImage: "rectangle.3.group",
                    description: Text("Create a Triptych by choosing Analyses, Topics, and Works folders.")
                )
            }
        }
        .padding(8)
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
    @ObservedObject var store: CSSSnippetStore
    @State private var draft: DocumentAppearanceProfile?
    @State private var importError: String?
    @State private var showRename = false
    @State private var showDeleteConfirmation = false
    @State private var nameDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Appearance")
                    .font(.title2.weight(.semibold))
                Text("Choose a named document configuration, then adjust line width, typography, and each semantic callout independently. Changes apply after saving; line width is shared by Review, Edit, and Source.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

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
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Advanced CSS") {
                    Text("Optional CSS snippets remain available for advanced compatibility. They are additive and do not replace the selected structured configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(store.snippets) { snippet in
                        CSSSnippetRow(
                            snippet: snippet,
                            error: store.validationErrors[snippet.id],
                            store: store
                        )
                    }

                    if store.snippets.isEmpty {
                        Text("No CSS snippets imported.")
                            .foregroundStyle(.secondary)
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
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            if let storeError = store.storeError {
                Label(storeError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("settings.css.store-error")
            }
            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
        let panel = NSOpenPanel()
        panel.title = ScholiumL10n.string("Import CSS Snippet")
        panel.prompt = "Import"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let cssType = UTType(filenameExtension: "css") {
            panel.allowedContentTypes = [cssType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            do {
                try await store.importSnippet(from: url)
                importError = nil
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .font(.caption)
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
            Text("Mathematics, code, and tables use Scholium’s shared restrained styles so their semantics and Read/Live parity remain stable across configurations.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            HStack(spacing: 8) {
                AppearanceNativeSlider(
                    value: $value,
                    range: range,
                    step: step
                )
                    .frame(minWidth: 150, idealWidth: 220)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(spokenValue)
                Text(formattedValue)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
                Text(suffix)
                    .foregroundStyle(.secondary)
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
        HStack(spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { snippet.isEnabled },
                    set: { store.setEnabled($0, for: snippet.id) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
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

            Spacer(minLength: 4)

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
        .padding(.vertical, 3)
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
            VStack(alignment: .leading, spacing: 6) {
                Text(ScholiumL10n.dynamicString(title))
                    .font(.title2.weight(.semibold))
                Text(ScholiumL10n.dynamicString(explanation))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider()

            Form {
                Section("Triptych") {
                    TextField("Name", text: $triptychName)
                        .accessibilityIdentifier("scholium.triptychName")
                    Text("The name distinguishes complete research domains. Works folders remain ordinary researcher-controlled folders, not app-managed projects.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if haveCommonParent {
                        Label("These folders share one parent.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if allFoldersSelected {
                        Label("These folders are independent. Keeping them under one parent can make the workspace easier to move and back up.", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .accessibilityLabel("Workspace error: \(errorMessage)")
            } else if let recoveryMessage = settingsModel.workspaceRecoveryMessage {
                Label(recoveryMessage, systemImage: "folder.badge.questionmark")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
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
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
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
    let worksURL: URL?
    @Binding var containerURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.gearshape")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Folder Containing Works")
                    .font(.body.weight(.medium))
                Text("Authorizes portable settings stored beside Works")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(containerURL?.path(percentEncoded: false) ?? "Authorization required")
                    .font(.caption)
                    .foregroundStyle(containerURL == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Button(containerURL == nil ? "Authorize…" : "Authorize Again…") {
                authorizeFolder()
            }
            .disabled(worksURL == nil)
            .accessibilityLabel("Authorize folder containing Works")
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("scholium.portableControlAccess")
    }

    private func authorizeFolder() {
        guard let expected = worksURL?
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL else { return }
        let panel = NSOpenPanel()
        panel.title = ScholiumL10n.string("Authorize the Folder Containing Works")
        panel.message = "Choose '\(expected.lastPathComponent)' so Scholium can use the portable .scholium folder beside Works."
        panel.prompt = "Authorize"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = expected.deletingLastPathComponent()
        if panel.runModal() == .OK {
            containerURL = panel.url
        }
    }
}

struct WorkspaceFolderRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    @Binding var url: URL?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(ScholiumL10n.dynamicString(title))
                    .font(.body.weight(.medium))
                Text(ScholiumL10n.dynamicString(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(url?.path(percentEncoded: false) ?? "No folder selected")
                    .font(.caption)
                    .foregroundStyle(url == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url?.path(percentEncoded: false) ?? "Choose a folder")
            }

            Spacer(minLength: 12)

            Button(url == nil ? "Choose…" : "Change…") {
                chooseFolder()
            }
            .accessibilityLabel("Choose \(title) folder")
        }
        .padding(.vertical, 4)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = String(
            format: ScholiumL10n.string("Choose %@ Folder"),
            locale: Locale.current,
            title
        )
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = url?.deletingLastPathComponent()
#if DEBUG
        if panel.directoryURL == nil,
           let testDirectory = ProcessInfo.processInfo.environment[
               "SCHOLIUM_UI_TEST_OPEN_PANEL_DIRECTORY"
           ],
           !testDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: testDirectory, isDirectory: true)
        }
#endif
        if panel.runModal() == .OK {
            url = panel.url
        }
    }
}
