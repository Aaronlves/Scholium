import ScholiumContracts
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScholiumSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @AppStorage("scholium.settings.selectedPane") private var persistedPane = "vaults"

    var body: some View {
        TabView(selection: selectedPane) {
            WorkspaceSettingsView()
                .tabItem { Label("Vaults", systemImage: "externaldrive") }
                .tag(WorkspaceSettingsPane.vaults)

            Group {
                if let store = settingsModel.cssSnippetStore {
                    CSSSnippetSettingsView(
                        store: store,
                        onOpenExternalURL: settingsModel.openExternal
                    )
                } else {
                    ContentUnavailableView("Document Styles Unavailable", systemImage: "paintbrush")
                }
            }
                .tabItem { Label("Document Styles", systemImage: "paintbrush") }
                .tag(WorkspaceSettingsPane.documentStyles)

            PropertiesSettingsView()
                .tabItem { Label("Properties", systemImage: "slider.horizontal.3") }
                .tag(WorkspaceSettingsPane.properties)

            ResearchGuidanceSettingsView()
                .tabItem { Label("Research Guidance", systemImage: "text.bubble") }
                .tag(WorkspaceSettingsPane.researchGuidance)

            AttentionSettingsView()
                .tabItem { Label("Attention", systemImage: "exclamationmark.triangle") }
                .tag(WorkspaceSettingsPane.attention)

            ZoteroSettingsView()
                .tabItem { Label("Zotero", systemImage: "books.vertical") }
                .tag(WorkspaceSettingsPane.zotero)
        }
        .padding(8)
        .onAppear {
            settingsModel.selectPane(WorkspaceSettingsPane(rawValue: persistedPane) ?? .vaults)
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
                .disabled(AttentionPreferences.decodeLedger(dismissalLedgerData).dismissedUntilByItemID.isEmpty)

                Text("Every Attention item is dismissible. Dismissal hides only the derived reminder for the selected duration; it never changes the note, its Connections, Human Review, or qualification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What Attention Can Report") {
                Text("Possible orphan structure, Changed Since Review, broken or ambiguous Connections, explicit reliance on an Unqualified Analysis, malformed metadata, and unresolved note identity.")
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

    private func save() {
        isSaving = true
        Task {
            do {
                var settings = settingsModel.triptychSettings
                settings.attentionDismissalDays = AttentionPreferences.normalizedDays(dismissalDays)
                try await settingsModel.saveTriptychSettings(settings)
                dismissalDays = settings.attentionDismissalDays
                settingsModel.showToast("Attention settings saved")
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

    private var recommendedKeys: [String] {
        let profile: SchemaProfileID = switch selectedSlot {
        case .paperAnalysis: .analysis
        case .topicKnowledge: .topicMarkdown
        case .output: .draftProject
        }
        return PropertyPresentationCatalog.presentations(for: profile).map(\.key)
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
        configuration.visibleFields.removeAll { ResearcherPropertyPolicy.isHidden($0) }
        configuration.editableFields.removeAll { !ResearcherPropertyPolicy.isHumanEditable($0) }
        return configuration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vault-Wide Properties")
                .font(.title2.weight(.semibold))
            Text("Set the fields, display order, structured-editing allowlist, and starting disclosure for each Triptych vault. The setting applies to the complete vault; Source mode always exposes the exact YAML.")
                .foregroundStyle(.secondary)
            Picker("Vault", selection: $selectedSlot) {
                ForEach(WorkspaceVaultSlot.allCases) { slot in
                    Text(slot.displayName).tag(slot)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 24) {
                displayOrderColumn
                editableFieldsColumn
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Open Properties by Default", isOn: defaultDisclosureBinding)
                    .toggleStyle(.checkbox)
                Text("This is the starting state for notes in \(selectedSlot.displayName); the researcher can still open or close an individual note.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

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

    private var defaultDisclosureBinding: Binding<Bool> {
        Binding(
            get: { selectedConfiguration.isExpanded },
            set: { value in
                updateSelectedConfiguration { $0.isExpanded = value }
            }
        )
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
                    let hidden = availableKeys.filter { !selectedConfiguration.visibleFields.contains($0) }
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
        guard let field = normalizedCustomField else {
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
                settings.properties = configurations.mapValues { configuration in
                    var result = configuration
                    result.visibleFields.removeAll { ResearcherPropertyPolicy.isHidden($0) }
                    result.editableFields.removeAll { !ResearcherPropertyPolicy.isHumanEditable($0) }
                    return result
                }
                try await settingsModel.saveTriptychSettings(settings)
                settingsModel.showToast("Properties configuration saved")
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

enum ResearchGuidanceStatusLoadState: Hashable {
    case loading
    case loaded
    case unavailable
}

enum ResearchGuidanceAdvancedDestination: Hashable {
    case citationMethod
    case researchMethod(ResearchFunctionID)

    var anchorID: String {
        switch self {
        case .citationMethod:
            "scholium.researchGuidance.advanced.citationMethod"
        case .researchMethod:
            "scholium.researchGuidance.advanced.researchMethods"
        }
    }

    var selectionID: String {
        switch self {
        case .citationMethod:
            "citation-method"
        case .researchMethod(let function):
            "research-method:\(function.rawValue)"
        }
    }
}

struct ResearchGuidanceRepairPrompt: Identifiable, Hashable {
    let message: String
    let destination: ResearchGuidanceAdvancedDestination

    var id: String { destination.selectionID }
}

enum ResearchGuidancePresentation {
    static let configurableFunctions: [ResearchFunctionID] = [
        .develop,
        .critique,
        .revise,
        .fidelity,
        .manuscript,
    ]

    static func repairPrompts(
        methodStatuses: [ResearchFunctionID: ResearchFunctionSkillBindingStatus],
        citationStatus: ResearchCitationMethodStatus?
    ) -> [ResearchGuidanceRepairPrompt] {
        var prompts: [ResearchGuidanceRepairPrompt] = []
        if citationStatus?.issue != nil {
            prompts.append(ResearchGuidanceRepairPrompt(
                message: "Citation method configuration needs repair.",
                destination: .citationMethod
            ))
        }
        for function in configurableFunctions
        where methodStatuses[function]?.issue != nil {
            prompts.append(ResearchGuidanceRepairPrompt(
                message: "\(function.interfaceTitle) method configuration needs repair.",
                destination: .researchMethod(function)
            ))
        }
        return prompts
    }

    static func ownershipLabel(for skill: ResearchSkillPackage) -> String {
        skill.origin == .bundled ? "Built-in" : "Triptych"
    }

    static func statusLabel(
        for skill: ResearchSkillPackage,
        allSkills: [ResearchSkillPackage],
        methodStatuses: [ResearchFunctionID: ResearchFunctionSkillBindingStatus],
        citationStatus: ResearchCitationMethodStatus?,
        loadState: ResearchGuidanceStatusLoadState
    ) -> String {
        guard skill.isValid else { return "Inactive until repaired" }
        switch loadState {
        case .loading:
            return "Loading active status…"
        case .unavailable:
            return "Active status unavailable"
        case .loaded:
            break
        }

        let validMethodStatuses = configurableFunctions.compactMap {
            methodStatuses[$0]
        }.filter { $0.issue == nil }

        if skill.isTriptychLocal {
            let primaryFunctions = validMethodStatuses.compactMap { status in
                status.selection.primaryPackageID == skill.id ? status.function : nil
            }
            let supplementalFunctions = validMethodStatuses.compactMap { status in
                status.selection.supplementalPackageIDs.contains(skill.id)
                    ? status.function
                    : nil
            }
            let practiceFunctions = validMethodStatuses.compactMap { status in
                status.selection.selectedPractices.contains { $0.packageID == skill.id }
                    ? status.function
                    : nil
            }
            let isCitationMethod = citationStatus?.issue == nil
                && citationStatus?.activePackageID == skill.id
                && citationStatus?.activeCitationStyle != nil
            var bindings: [String] = []
            if !primaryFunctions.isEmpty {
                bindings.append("Primary for \(functionList(primaryFunctions))")
            }
            if !supplementalFunctions.isEmpty {
                bindings.append("Supplement for \(functionList(supplementalFunctions))")
            }
            if !practiceFunctions.isEmpty {
                bindings.append("Practice for \(functionList(practiceFunctions))")
            }
            if isCitationMethod {
                bindings.append("Citation method for Fidelity")
            }
            if !bindings.isEmpty {
                return "Bound — \(bindings.joined(separator: "; "))"
            }
        }

        if skill.origin == .bundled,
           skill.skillClass == .system,
           !skill.automaticModes.isEmpty {
            if skill.automaticModes.contains(.all) {
                return "Active automatically"
            }
            return "Active automatically — \(skill.automaticModes.map(\.displayName).joined(separator: ", "))"
        }

        if skill.origin == .bundled, skill.skillClass == .workflow {
            let defaultFunctions = validMethodStatuses.compactMap { status in
                status.selection.primaryPackageID == nil && skill.supports(status.function)
                    ? status.function
                    : nil
            }
            if !defaultFunctions.isEmpty {
                return "Active — \(functionList(defaultFunctions))"
            }
        }

        if activePackageIDs(
            in: allSkills,
            methodStatuses: methodStatuses,
            citationStatus: citationStatus
        ).contains(skill.id) {
            return "Active dependency"
        }
        return "Not active"
    }

    private static func functionList(_ functions: [ResearchFunctionID]) -> String {
        let selected = Set(functions)
        return configurableFunctions
            .filter { selected.contains($0) }
            .map(\.interfaceTitle)
            .joined(separator: ", ")
    }

    private static func activePackageIDs(
        in skills: [ResearchSkillPackage],
        methodStatuses: [ResearchFunctionID: ResearchFunctionSkillBindingStatus],
        citationStatus: ResearchCitationMethodStatus?
    ) -> Set<String> {
        var packagesByID: [String: ResearchSkillPackage] = [:]
        for skill in skills where packagesByID[skill.id] == nil {
            packagesByID[skill.id] = skill
        }
        var seeds = Set(skills.filter {
            $0.origin == .bundled
                && $0.skillClass == .system
                && $0.isValid
                && !$0.automaticModes.isEmpty
        }.map(\.id))

        for status in methodStatuses.values where status.issue == nil {
            if let primaryPackageID = status.selection.primaryPackageID {
                seeds.insert(primaryPackageID)
            } else {
                for skill in skills where skill.origin == .bundled
                    && skill.skillClass == .workflow
                    && skill.isValid
                    && skill.supports(status.function) {
                    seeds.insert(skill.id)
                }
            }
            seeds.formUnion(status.selection.supplementalPackageIDs)
            seeds.formUnion(status.selection.selectedPractices.map(\.packageID))
        }
        if citationStatus?.issue == nil,
           citationStatus?.activeCitationStyle != nil,
           let activePackageID = citationStatus?.activePackageID {
            seeds.insert(activePackageID)
        }

        var active: Set<String> = []
        func include(_ packageID: String) {
            guard active.insert(packageID).inserted,
                  let package = packagesByID[packageID] else { return }
            for dependencyID in package.requiredSkillIDs {
                include(dependencyID)
            }
        }
        for packageID in seeds {
            include(packageID)
        }
        return active
    }
}

private struct ResearchGuidanceSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @AppStorage("scholium.settings.researchGuidanceCollection") private var collection = "prompt-templates"
    @AppStorage("scholium.settings.researchGuidancePromptSection") private var promptSection = "templates"
    @State private var showsAdvanced = false
    @State private var selectedMethodFunction: ResearchFunctionID = .develop
    @State private var methodStatuses: [ResearchFunctionID: ResearchFunctionSkillBindingStatus] = [:]
    @State private var citationStatus: ResearchCitationMethodStatus?
    @State private var statusLoadState: ResearchGuidanceStatusLoadState = .loading
    @State private var statusRefreshGeneration = 0

    private var repairPrompts: [ResearchGuidanceRepairPrompt] {
        ResearchGuidancePresentation.repairPrompts(
            methodStatuses: methodStatuses,
            citationStatus: citationStatus
        )
    }

    private var statusLoadIdentity: String {
        let workspace = settingsModel.activeTriptychServicesID?.uuidString ?? "none"
        return "\(workspace):\(collection):\(statusRefreshGeneration)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Research Guidance Collection", selection: $collection) {
                Text("Prompt Templates").tag("prompt-templates")
                Text("Skills").tag("skills")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            .padding(.vertical, 10)
            .accessibilityIdentifier("scholium.researchGuidance.collection")
            Divider()
            if collection == "skills" {
                ScrollViewReader { advancedProxy in
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Button {
                                showsAdvanced.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showsAdvanced ? "chevron.down" : "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .accessibilityHidden(true)
                                    Text("Advanced")
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .accessibilityValue(showsAdvanced ? "Expanded" : "Collapsed")
                            .accessibilityHint("Shows research methods, bindings, routing, evolution, and recovery")
                            .accessibilityIdentifier("scholium.researchGuidance.advanced")

                            if !repairPrompts.isEmpty {
                                VStack(spacing: 6) {
                                    ForEach(repairPrompts) { prompt in
                                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                                            Label(
                                                prompt.message,
                                                systemImage: "exclamationmark.triangle"
                                            )
                                            .font(.caption)
                                            .foregroundStyle(ScholiumColorRole.attention.color)
                                            Spacer(minLength: 8)
                                            Button("Repair…") {
                                                openAdvanced(prompt.destination, with: advancedProxy)
                                            }
                                            .accessibilityHint(
                                                "Opens the issue-specific Advanced recovery destination"
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                                .accessibilityIdentifier(
                                    "scholium.researchGuidance.repairSummary"
                                )
                            }

                            if showsAdvanced {
                                ScrollView {
                                    VStack(spacing: 0) {
                                        AgentCLISettingsView()
                                            .padding(.vertical, 8)
                                        Divider()
                                        ResearchCitationMethodSettingsView { updated in
                                            citationStatus = updated
                                        }
                                        .padding(.vertical, 8)
                                        .id(ResearchGuidanceAdvancedDestination.citationMethod.anchorID)
                                        Divider()
                                        RecommendedBibliographyMethodSettingsView()
                                            .padding(.vertical, 8)
                                        Divider()
                                        ResearchFunctionMethodSettingsView(
                                            selectedFunction: $selectedMethodFunction
                                        ) { updated in
                                            methodStatuses[updated.function] = updated
                                        }
                                        .padding(.vertical, 8)
                                        .id(
                                            ResearchGuidanceAdvancedDestination
                                                .researchMethod(selectedMethodFunction)
                                                .anchorID
                                        )
                                    }
                                    .padding(.leading, 18)
                                }
                                .frame(maxHeight: 260)
                            }
                        }
                        Divider()
                        // A SKILL.md can be thousands of lines long. Keep its editor
                        // inside the finite Settings viewport instead of allowing the
                        // text view's intrinsic document height to expand and clip the
                        // collection picker and package list.
                        GeometryReader { proxy in
                            ResearchSkillsSettingsView(
                                showsAdvanced: $showsAdvanced,
                                methodStatuses: methodStatuses,
                                citationStatus: citationStatus,
                                statusLoadState: statusLoadState,
                                refreshGuidanceStatus: {
                                    statusRefreshGeneration &+= 1
                                }
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    Picker("Prompt Guidance Section", selection: $promptSection) {
                        Text("Templates").tag("templates")
                        Text("Dialogue Defaults").tag("dialogue-response")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 300)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("scholium.researchGuidance.promptSection")
                    Divider()
                    if promptSection == "dialogue-response" {
                        DialogueResponseSettingsView()
                    } else {
                        PromptTemplateSettingsView()
                    }
                }
            }
        }
        .onAppear {
            // Migrate the former third peer collection into the subordinate
            // Prompt Templates section without discarding the researcher's
            // last visible destination.
            if collection == "dialogue-response" {
                collection = "prompt-templates"
                promptSection = "dialogue-response"
            }
        }
        .task(id: statusLoadIdentity) {
            guard collection == "skills" else { return }
            await reloadGuidanceStatus()
        }
    }

    private func openAdvanced(
        _ destination: ResearchGuidanceAdvancedDestination,
        with proxy: ScrollViewProxy
    ) {
        if case .researchMethod(let function) = destination {
            selectedMethodFunction = function
        }
        showsAdvanced = true
        DispatchQueue.main.async {
            proxy.scrollTo(destination.anchorID, anchor: .top)
        }
    }

    private func reloadGuidanceStatus() async {
        guard let workspaceID = settingsModel.activeTriptychServicesID else {
            methodStatuses = [:]
            citationStatus = nil
            statusLoadState = .unavailable
            return
        }
        statusLoadState = .loading
        do {
            var loadedMethods: [ResearchFunctionID: ResearchFunctionSkillBindingStatus] = [:]
            for function in ResearchGuidancePresentation.configurableFunctions {
                loadedMethods[function] = try await settingsModel
                    .researchFunctionSkillBindingStatus(for: function)
            }
            let loadedCitation = try await settingsModel.citationMethodStatus()
            try Task.checkCancellation()
            guard settingsModel.activeTriptychServicesID == workspaceID else { return }
            methodStatuses = loadedMethods
            citationStatus = loadedCitation
            statusLoadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard settingsModel.activeTriptychServicesID == workspaceID else { return }
            methodStatuses = [:]
            citationStatus = nil
            statusLoadState = .unavailable
        }
    }
}

private struct AgentCLISettingsView: View {
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
                                settingsModel.showToast("PATH setup copied")
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
            settingsModel.showToast("Scholium CLI installed")
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
/// of the Strip's Research Function bindings.
private struct RecommendedBibliographyMethodSettingsView: View {
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
                            Text(candidate.name).tag(String?.some(candidate.packageID))
                        }
                    }
                    .frame(maxWidth: 420)
                    .disabled(isWorking)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.bibliographyMethod"
                    )

                    Text("Used only to screen reading leads from an Analysis. It does not create a Strip function, edit notes, or write to Zotero.")
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
/// Researcher Skills. The editor Strip receives semantic function
/// availability, never package identifiers or routing metadata.
private struct ResearchFunctionMethodSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Binding var selectedFunction: ResearchFunctionID
    let onStatusChange: (ResearchFunctionSkillBindingStatus) -> Void
    @State private var status: ResearchFunctionSkillBindingStatus?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var primaryCandidates: [ResearchFunctionSkillCandidate] {
        candidates(for: .primary)
    }

    private var supplementalCandidates: [ResearchFunctionSkillCandidate] {
        candidates(for: .supplemental)
    }

    private var practiceCandidates: [ResearchFunctionSkillCandidate] {
        candidates(for: .practice)
    }

    private var loadIdentity: String {
        let workspace = settingsModel.activeTriptychServicesID?.uuidString ?? "none"
        return "\(workspace):\(selectedFunction.rawValue)"
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Picker("Function", selection: $selectedFunction) {
                        ForEach(ResearchGuidancePresentation.configurableFunctions, id: \.self) { function in
                            Text(function.interfaceTitle).tag(function)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 180)
                    .disabled(isWorking)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.researchMethod.function"
                    )
                    Spacer()
                    if isWorking { ProgressView().controlSize(.small) }
                }

                if let status {
                    if status.candidates.isEmpty {
                        Text("No compatible Triptych method is installed for \(selectedFunction.interfaceTitle). The built-in workflow remains active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        if !primaryCandidates.isEmpty {
                            Picker("Method", selection: primarySelection) {
                                Text("Built-in").tag(String?.none)
                                ForEach(primaryCandidates) { candidate in
                                    Text(candidate.name).tag(String?.some(candidate.packageID))
                                }
                            }
                            .frame(maxWidth: 420)
                            .disabled(isWorking)
                            .accessibilityIdentifier(
                                "scholium.researchGuidance.researchMethod.primary"
                            )
                        }

                        if !supplementalCandidates.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Supplements")
                                    .font(.caption.weight(.semibold))
                                ForEach(supplementalCandidates) { candidate in
                                    Toggle(
                                        candidate.name,
                                        isOn: supplementalSelection(candidate.packageID)
                                    )
                                    .disabled(isWorking)
                                    .accessibilityHint(
                                        "Use this supplement with \(selectedFunction.interfaceTitle)."
                                    )
                                }
                            }
                        }

                        if !practiceCandidates.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Practices")
                                    .font(.caption.weight(.semibold))
                                ForEach(practiceCandidates) { candidate in
                                    ForEach(candidate.practiceIDs, id: \.self) { practiceID in
                                        Toggle(
                                            "\(candidate.name) — \(friendlyTitle(practiceID))",
                                            isOn: practiceSelection(
                                                packageID: candidate.packageID,
                                                practiceID: practiceID
                                            )
                                        )
                                        .disabled(isWorking)
                                        .accessibilityHint(
                                            "Use this practice with \(selectedFunction.interfaceTitle)."
                                        )
                                    }
                                }
                            }
                        }

                        if let active = activePrimaryCandidate(in: status),
                           !active.description.isEmpty {
                            Text(active.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let issue = status.issue {
                        Label(
                            issueDescription(issue.code),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } else {
                    ProgressView("Loading research methods…")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Research Methods", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
        .task(id: loadIdentity) { await reload() }
        .alert("Could Not Update Research Method", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .accessibilityIdentifier("scholium.researchGuidance.researchMethods")
    }

    private var primarySelection: Binding<String?> {
        Binding(
            get: { status?.selection.primaryPackageID },
            set: { packageID in
                guard packageID != status?.selection.primaryPackageID else { return }
                updatePrimaryPackage(packageID)
            }
        )
    }

    private func supplementalSelection(_ packageID: String) -> Binding<Bool> {
        Binding(
            get: { status?.selection.supplementalPackageIDs.contains(packageID) == true },
            set: { isSelected in
                guard let status else { return }
                var selected = status.selection.supplementalPackageIDs
                selected.removeAll { $0 == packageID }
                if isSelected { selected.append(packageID) }
                saveSelection(ResearchFunctionSkillSelection(
                    function: selectedFunction,
                    primaryPackageID: status.selection.primaryPackageID,
                    supplementalPackageIDs: selected,
                    selectedPractices: status.selection.selectedPractices
                ))
            }
        )
    }

    private func practiceSelection(
        packageID: String,
        practiceID: String
    ) -> Binding<Bool> {
        let selectionID = "\(packageID):\(practiceID)"
        return Binding(
            get: {
                status?.selection.selectedPractices.contains {
                    $0.selectionID == selectionID
                } == true
            },
            set: { isSelected in
                guard let status else { return }
                var selected = status.selection.selectedPractices
                selected.removeAll { $0.selectionID == selectionID }
                if isSelected {
                    selected.append(ResearchPracticeSelection(
                        packageID: packageID,
                        practiceID: practiceID
                    ))
                }
                saveSelection(ResearchFunctionSkillSelection(
                    function: selectedFunction,
                    primaryPackageID: status.selection.primaryPackageID,
                    supplementalPackageIDs: status.selection.supplementalPackageIDs,
                    selectedPractices: selected
                ))
            }
        )
    }

    private func updatePrimaryPackage(_ packageID: String?) {
        guard let status else { return }
        saveSelection(ResearchFunctionSkillSelection(
            function: selectedFunction,
            primaryPackageID: packageID,
            supplementalPackageIDs: status.selection.supplementalPackageIDs,
            selectedPractices: status.selection.selectedPractices
        ))
    }

    private func saveSelection(_ selection: ResearchFunctionSkillSelection) {
        guard let status else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let updated = try await settingsModel.saveResearchFunctionSkillSelection(
                    selection,
                    expectedBindingRevision: status.bindingRevision
                )
                guard selectedFunction == selection.function else { return }
                self.status = updated
                onStatusChange(updated)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func candidates(
        for role: ResearchFunctionSkillBindingRole
    ) -> [ResearchFunctionSkillCandidate] {
        status?.candidates.filter { $0.availableRoles.contains(role) } ?? []
    }

    private func activePrimaryCandidate(
        in status: ResearchFunctionSkillBindingStatus
    ) -> ResearchFunctionSkillCandidate? {
        guard let packageID = status.selection.primaryPackageID else { return nil }
        return status.candidates.first { $0.packageID == packageID }
    }

    private func friendlyTitle(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func issueDescription(_ code: ResearchFunctionSkillBindingIssueCode) -> String {
        switch code {
        case .functionHasNoSkill:
            "This function does not use an executable skill."
        case .malformedBinding:
            "The saved method selection needs repair. Choose a valid method to replace it."
        case .invalidPackage:
            "The selected method is no longer available."
        case .unsupportedFunction:
            "The selected method does not support this function."
        case .invalidRole:
            "The selected guidance cannot play this role."
        case .invalidPractice:
            "The selected practice is no longer available."
        case .legacyReplacementPractice:
            "A legacy replacement Practice must become a supplement or a complete Researcher Skill."
        }
    }

    private func reload() async {
        guard settingsModel.activeTriptychServicesID != nil else {
            status = nil
            errorMessage = nil
            return
        }
        let function = selectedFunction
        status = nil
        do {
            let loaded = try await settingsModel.researchFunctionSkillBindingStatus(
                for: function
            )
            try Task.checkCancellation()
            guard selectedFunction == function else { return }
            status = loaded
            onStatusChange(loaded)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

private struct ResearchCitationMethodSettingsView: View {
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

private struct DialogueResponseSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var selectedModules: Set<DialogueResponseModule> = []
    @State private var commentPreservation = DialogueCommentPreservation.keepAcademicIntentions
    @State private var unknownModuleIDs: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("New Dialogue Requests") {
                LabeledContent("Required base") {
                    Text("Academic Outcome")
                        .foregroundStyle(.secondary)
                }
                Text("Choose the optional scholarly modules included in newly prepared Dialogue requests. This setting does not change existing Dialogue records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Optional Response Modules") {
                ForEach(DialogueResponseModule.allCases, id: \.self) { module in
                    Toggle(isOn: moduleBinding(module)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(module.displayName)
                            Text(module.promptQuestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("scholium.settings.responseModule.\(module.rawValue)")
                }
            }

            Section("Comment Preservation") {
                Picker("Preserve", selection: $commentPreservation) {
                    ForEach(DialogueCommentPreservation.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityIdentifier("scholium.settings.commentPreservation")
                Text("Preservation changes how the external agent presents the selected Comment. It never grants note-edit permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !unknownModuleIDs.isEmpty {
                Section {
                    Label(
                        "This profile contains unsupported response modules: \(unknownModuleIDs.joined(separator: ", ")). Update Scholium before saving it.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Button("Save Dialogue Defaults") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !unknownModuleIDs.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .task(id: settingsModel.activeTriptychServicesID) { await load() }
        .alert("Could Not Save Dialogue Defaults", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func moduleBinding(_ module: DialogueResponseModule) -> Binding<Bool> {
        Binding(
            get: { selectedModules.contains(module) },
            set: { isSelected in
                if isSelected {
                    selectedModules.insert(module)
                } else {
                    selectedModules.remove(module)
                }
            }
        )
    }

    private func load() async {
        guard settingsModel.activeTriptychServicesID != nil else {
            errorMessage = nil
            return
        }
        do {
            let profile = try await settingsModel.dialogueResponseProfile()
            selectedModules = Set(profile.knownModules)
            unknownModuleIDs = profile.unknownModuleIDs
            if let mode = DialogueCommentPreservation(rawValue: profile.commentPreservation) {
                commentPreservation = mode
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let modules = DialogueResponseModule.allCases.filter { selectedModules.contains($0) }
                let profile = DialogueResponseProfile(
                    modules: modules,
                    commentPreservation: commentPreservation
                )
                try await settingsModel.saveDialogueResponseProfile(profile)
                settingsModel.showToast("Dialogue Defaults saved")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PromptTemplateSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @AppStorage("scholium.settings.researchGuidanceKind") private var preferredKind = ResearchPromptKind.dialogue.rawValue
    @State private var selectedTemplateID: UUID?
    @State private var name = ""
    @State private var source = ""
    @State private var showsPreview = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var templates: [ResearchPromptTemplate] {
        settingsModel.triptychSettings.promptTemplates.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private var selectedTemplate: ResearchPromptTemplate? {
        templates.first { $0.id == selectedTemplateID }
    }

    private var draft: ResearchPromptTemplate? {
        guard var template = selectedTemplate else { return nil }
        template.name = name
        template.source = source
        return template
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTemplateID) {
                ForEach(ResearchPromptKind.allCases) { kind in
                    Section(kind.displayName) {
                        ForEach(templates.filter { $0.kind == kind }) { template in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                    if settingsModel.triptychSettings.activePromptTemplateIDs[kind] == template.id {
                                        Text("Active")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: kind == .dialogue ? "bubble.left.and.text.bubble.right" : "doc.text.magnifyingglass")
                            }
                            .tag(template.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 0) {
                    Menu {
                        ForEach(ResearchPromptKind.allCases) { kind in
                            Button("New \(kind.displayName) Template") { create(kind) }
                        }
                        Button("Duplicate", action: duplicate)
                            .disabled(selectedTemplate == nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                    .accessibilityLabel("Add Prompt Template")
                    Button(action: delete) { Image(systemName: "minus") }
                        .buttonStyle(.borderless)
                        .frame(width: 28)
                        .disabled(selectedTemplate?.origin != .researcher)
                        .accessibilityLabel("Delete Prompt Template")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(.bar)
            }
        } detail: {
            if let template = selectedTemplate {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(template.kind.displayName)
                            .font(.title2.weight(.semibold))
                        if settingsModel.triptychSettings.activePromptTemplateIDs[template.kind] == template.id {
                            Text("Active")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Use for \(template.kind.displayName)") { assign() }
                            .disabled(settingsModel.triptychSettings.activePromptTemplateIDs[template.kind] == template.id)
                    }
                    TextField("Template Name", text: $name)
                        .disabled(template.origin == .scholium)
                    TextEditor(text: $source)
                        .font(ScholiumTypography.swiftUIMonospaceFont(size: 13, relativeTo: .body))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scrollContentBackground(.visible)
                        .accessibilityLabel("\(template.kind.displayName) template instructions")
                    Text("Required: \(template.kind.requiredPlaceholders.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let draft, !draft.validationIssues.isEmpty {
                        Label(draft.validationIssues.joined(separator: " "), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    DisclosureGroup("Preview with Sample Context", isExpanded: $showsPreview) {
                        ScrollView {
                            Text(preview(for: template.kind))
                                .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 100, maxHeight: 160)
                    }
                    HStack {
                        Button("Reset to Scholium Default") { reset(template.kind) }
                        Spacer()
                        Button("Save Template", action: save)
                            .buttonStyle(.borderedProminent)
                            .disabled(draft?.validationIssues.isEmpty != true || isSaving)
                    }
                }
                .padding(18)
                .accessibilityIdentifier("scholium.researchGuidance.templateEditor")
            } else {
                ContentUnavailableView("Select a Prompt Template", systemImage: "text.bubble")
            }
        }
        .task(id: settingsModel.workspaceAssignment?.id) { selectPreferredTemplate() }
        .onChange(of: selectedTemplateID) { _, _ in loadDraft() }
        .alert("Could Not Save Research Guidance", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        guard var template = draft else { return }
        isSaving = true
        Task {
            do {
                var settings = settingsModel.triptychSettings
                if template.origin == .scholium {
                    template = ResearchPromptTemplate(
                        kind: template.kind,
                        name: "Customized \(template.kind.displayName)",
                        source: template.source
                    )
                }
                settings.savePromptTemplate(template)
                try await settingsModel.saveTriptychSettings(settings)
                selectedTemplateID = template.id
                settingsModel.showToast("Research Guidance saved")
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func selectPreferredTemplate() {
        let kind = ResearchPromptKind(rawValue: preferredKind) ?? .dialogue
        selectedTemplateID = settingsModel.triptychSettings.activePromptTemplateIDs[kind]
        loadDraft()
    }

    private func loadDraft() {
        guard let selectedTemplate else { return }
        name = selectedTemplate.name
        source = selectedTemplate.source
    }

    private func create(_ kind: ResearchPromptKind) {
        let template = ResearchPromptTemplate(kind: kind, name: "New \(kind.displayName) Template", source: kind == .dialogue ? TriptychSettings.defaultDialoguePromptTemplate : TriptychSettings.defaultCritiquePromptTemplate)
        var settings = settingsModel.triptychSettings
        settings.savePromptTemplate(template)
        persist(settings, selecting: template.id)
    }

    private func duplicate() {
        guard let selectedTemplate else { return }
        let copy = ResearchPromptTemplate(kind: selectedTemplate.kind, name: "\(selectedTemplate.name) Copy", source: selectedTemplate.source)
        var settings = settingsModel.triptychSettings
        settings.savePromptTemplate(copy)
        persist(settings, selecting: copy.id)
    }

    private func delete() {
        guard let id = selectedTemplateID else { return }
        var settings = settingsModel.triptychSettings
        let kind = selectedTemplate?.kind ?? .dialogue
        settings.deletePromptTemplate(id: id)
        persist(settings, selecting: settings.activePromptTemplateIDs[kind])
    }

    private func assign() {
        guard let selectedTemplate else { return }
        var settings = settingsModel.triptychSettings
        settings.activePromptTemplateIDs[selectedTemplate.kind] = selectedTemplate.id
        persist(settings, selecting: selectedTemplate.id)
    }

    private func reset(_ kind: ResearchPromptKind) {
        var settings = settingsModel.triptychSettings
        settings.resetPromptTemplate(for: kind)
        persist(settings, selecting: settings.activePromptTemplateIDs[kind])
    }

    private func persist(_ settings: TriptychSettings, selecting id: UUID?) {
        Task {
            do {
                try await settingsModel.saveTriptychSettings(settings)
                selectedTemplateID = id
                loadDraft()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func preview(for kind: ResearchPromptKind) -> String {
        if kind == .critique {
            return CritiquePromptBuilder.build(CritiquePromptContext(
                template: source, scope: .both, lens: "Argument structure and source support",
                selectedRanges: "Section 2", additionalInstructions: "Identify revision priorities.",
                workTitle: "Sample Work", workRelativePath: "Sample Work.md",
                workFingerprint: DocumentFingerprint(content: "preview"),
                critiqueRelativePath: "Critiques/Sample Work Critique.md"
            ))
        }
        return DialoguePromptBuilder.build(DialoguePromptContext(
            instruction: "Compare the selected arguments.", selectedNotes: []
        ), template: source)
    }
}

private struct ResearchSkillsSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Binding var showsAdvanced: Bool
    let methodStatuses: [ResearchFunctionID: ResearchFunctionSkillBindingStatus]
    let citationStatus: ResearchCitationMethodStatus?
    let statusLoadState: ResearchGuidanceStatusLoadState
    let refreshGuidanceStatus: () -> Void
    @State private var skills: [ResearchSkillPackage] = []
    @State private var selectedSkillID: String?
    @State private var source = ""
    @State private var inspectedDraft: ResearchSkillPackage?
    @State private var draftInspectionTask: Task<Void, Never>?
    @State private var isInspectingDraft = false
    @State private var showsRoutingMetadata = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var pendingDeletion: ResearchSkillPackage?
    @State private var maintenanceInstruction = ""
    @State private var maintenanceCurrentPackage: ResearchSkillProposedPackage?
    @State private var maintenanceProposedPackage: ResearchSkillProposedPackage?
    @State private var maintenanceProposalSource = ""
    @State private var maintenanceProposalError: String?
    @State private var maintenancePackageLoadTask: Task<Void, Never>?
    @State private var maintenancePackageLoadID: UUID?
    @State private var isLoadingMaintenancePackage = false
    @State private var maintenanceEvaluationEvidenceSource = ""
    @State private var maintenancePreparation: ResearchSkillMaintenancePreparation?
    @State private var maintenanceOutcome: ResearchSkillMaintenanceApplyOutcome?
    @State private var maintenanceSnapshots: [ResearchSkillMaintenanceSnapshot] = []
    @State private var maintenanceSnapshotIssues: [ResearchSkillMaintenanceSnapshotIssue] = []
    @State private var pendingMaintenanceRestore: ResearchSkillMaintenanceSnapshot?
    @State private var draftSkillSelectionID: String?

    private static let recoverySelectionPrefix = "recovery:"
    private static let recoveryIssuesSelection = "recovery:issues"

    private var selectedSkill: ResearchSkillPackage? {
        skills.first { $0.selectionID == selectedSkillID }
    }

    private var selectedRecoverySnapshot: ResearchSkillMaintenanceSnapshot? {
        guard let selectedSkillID,
              selectedSkillID.hasPrefix(Self.recoverySelectionPrefix),
              selectedSkillID != Self.recoveryIssuesSelection,
              let id = UUID(uuidString: String(
                selectedSkillID.dropFirst(Self.recoverySelectionPrefix.count)
              )) else { return nil }
        return maintenanceSnapshots.first { $0.id == id }
    }

    private var displayedRoutingPackage: ResearchSkillPackage? {
        guard let selectedSkill else { return nil }
        return selectedSkill.origin == .bundled ? selectedSkill : inspectedDraft
    }

    private var displayedValidationIssues: [String] {
        Array(Set(inspectedDraft?.validationIssues ?? selectedSkill?.validationIssues ?? [])).sorted()
    }

    private var maintenanceProposalSourceMatchesImport: Bool {
        guard let proposedPackage = maintenanceProposedPackage,
              let canonicalSource = try? ResearchSkillMaintenanceProposalDraft.encode(
                proposedPackage
              ) else {
            return false
        }
        return maintenanceProposalSource == canonicalSource
    }

    private var maintenancePreparationMatchesProposalDraft: Bool {
        guard let skill = selectedSkill,
              source == skill.source,
              maintenanceProposalSourceMatchesImport,
              let proposedPackage = maintenanceProposedPackage,
              let preparation = maintenancePreparation,
              preparation.request.expectedPackageRevision == skill.revision,
              preparation.request.instruction == maintenanceInstruction
                .trimmingCharacters(in: .whitespacesAndNewlines),
              preparation.request.proposedPackage == proposedPackage else {
            return false
        }
        return true
    }

    private var maintenancePreparationMatchesDraft: Bool {
        guard maintenancePreparationMatchesProposalDraft,
              let preparation = maintenancePreparation,
              preparation.isReadyForSettingsApply else {
            return false
        }
        do {
            return try decodeMaintenanceEvaluationEvidence()
                == preparation.request.evaluationEvidence
        } catch {
            return false
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSkillID) {
                skillSection("Built-in", skills: skills.filter { $0.origin == .bundled })
                skillSection("Triptych", skills: skills.filter { $0.origin != .bundled })
                if showsAdvanced {
                    recoverySection
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 0) {
                    Button(action: createSkill) { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .frame(width: 28)
                        .accessibilityLabel("New Triptych Skill")
                    Button {
                        pendingDeletion = selectedSkill
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 28)
                    .disabled(selectedSkill?.isTriptychLocal != true)
                    .accessibilityLabel("Delete Triptych Skill")
                    Spacer()
                    if showsAdvanced {
                        Button("Reveal Skills Folder", action: revealSkillsFolder)
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(.bar)
            }
        } detail: {
            if let skill = selectedSkill {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(skill.name)
                                .font(.title2.weight(.semibold))
                                .accessibilityIdentifier("scholium.researchGuidance.skillTitle")
                            Spacer()
                        }
                        Text(skill.description.isEmpty ? "No valid purpose is available." : skill.description)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        GroupBox("Skill") {
                            VStack(alignment: .leading, spacing: 7) {
                                routingRow("Ownership", ownershipLabel(for: skill))
                                routingRow(
                                    "Relevant function",
                                    skill.supportedFunctions.isEmpty
                                        ? "General guidance"
                                        : skill.supportedFunctions
                                            .map(\.interfaceTitle)
                                            .joined(separator: ", ")
                                )
                                routingRow("Validity", skill.isValid ? "Valid" : "Needs Repair")
                                routingRow(
                                    "Status",
                                    ResearchGuidancePresentation.statusLabel(
                                        for: skill,
                                        allSkills: skills,
                                        methodStatuses: methodStatuses,
                                        citationStatus: citationStatus,
                                        loadState: statusLoadState
                                    )
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if !skill.isValid || !displayedValidationIssues.isEmpty {
                            Label(
                                displayedValidationIssues.isEmpty
                                    ? "This Skill is inactive until its package is repaired."
                                    : displayedValidationIssues.joined(separator: " "),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("scholium.researchGuidance.skillValidation")
                            Button("Repair…") {
                                showsAdvanced = true
                                DispatchQueue.main.async {
                                    scrollProxy.scrollTo(
                                        "scholium.researchGuidance.repairDestination",
                                        anchor: .top
                                    )
                                }
                            }
                            .accessibilityHint("Opens the Advanced repair surface for this Skill")
                            .accessibilityIdentifier("scholium.researchGuidance.repairSkill")
                        }

                        HStack {
                            if skill.canDuplicate || skill.isTriptychLocal {
                                Button("Duplicate", action: duplicateSelectedSkill)
                            }
                            if skill.isTriptychLocal {
                                Button("Edit") { showsAdvanced = true }
                                    .disabled(showsAdvanced)
                            }
                            Spacer()
                        }

                        if showsAdvanced {
                            Divider()
                                .id("scholium.researchGuidance.repairDestination")
                            if let routing = displayedRoutingPackage {
                                DisclosureGroup(
                                    "Routing Metadata",
                                    isExpanded: $showsRoutingMetadata
                                ) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        routingRow(
                                            "Capabilities",
                                            routing.capabilities.isEmpty
                                                ? "None"
                                                : routing.capabilities
                                                    .map(capabilityTitle)
                                                    .joined(separator: ", ")
                                        )
                                        routingRow(
                                            "Citation Styles",
                                            routing.citationStyles.isEmpty
                                                ? "None"
                                                : routing.citationStyles
                                                    .map(citationStyleTitle)
                                                    .joined(separator: ", ")
                                        )
                                        routingRow(
                                            "Guided Evolution",
                                            routing.allowsEvolution ? "Eligible" : "Not enabled"
                                        )
                                        routingRow("Version", routing.version)
                                    }
                                    .padding(.top, 6)
                                }
                                .accessibilityIdentifier("scholium.researchGuidance.skillRouting")
                            }

                            if skill.isTriptychLocal {
                                TextEditor(text: $source)
                                    .font(ScholiumTypography.swiftUIMonospaceFont(size: 13, relativeTo: .body))
                                    .frame(maxWidth: .infinity, minHeight: 220, idealHeight: 300, maxHeight: 360)
                                    .scrollContentBackground(.visible)
                                    .disabled(skill.revision == nil)
                                    .accessibilityLabel("SKILL.md source")

                                Text("Scholium validates package structure and routing, not philosophical quality.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if skill.skillClass == .researcher,
                                   skill.allowsEvolution {
                                    Button("Evolve…") {
                                        scrollProxy.scrollTo(
                                            "scholium.researchGuidance.maintenanceAnchor",
                                            anchor: .top
                                        )
                                    }
                                    .accessibilityHint(
                                        "Moves to explicit whole-package maintenance for this Triptych Skill"
                                    )
                                    .accessibilityIdentifier(
                                        "scholium.researchGuidance.openMaintenance"
                                    )

                                    ResearchSkillMaintenanceView(
                                        instruction: $maintenanceInstruction,
                                        proposalSource: $maintenanceProposalSource,
                                        evaluationEvidenceSource: $maintenanceEvaluationEvidenceSource,
                                        currentPackage: maintenanceCurrentPackage,
                                        proposedPackage: maintenanceProposedPackage,
                                        proposalError: maintenanceProposalError,
                                        preparation: maintenancePreparation,
                                        appliedOutcome: maintenanceOutcome,
                                        recoverySnapshots: maintenanceSnapshots.filter {
                                            $0.packageID == skill.id
                                        },
                                        currentPackageRevision: skill.revision,
                                        isWorking: isWorking,
                                        isLoadingCurrentPackage: isLoadingMaintenancePackage,
                                        hasUnsavedSkillDraft: source != skill.source,
                                        proposalSourceMatchesImport: maintenanceProposalSourceMatchesImport,
                                        canRequestEvaluation: maintenancePreparationMatchesProposalDraft,
                                        canApply: maintenancePreparationMatchesDraft,
                                        copyProposalRequest: copyMaintenanceProposalRequest,
                                        importProposal: importMaintenanceProposal,
                                        copyEvaluationRequest: copyMaintenanceEvaluationRequest,
                                        prepare: prepareMaintenance,
                                        apply: applyMaintenance,
                                        restore: requestMaintenanceRestore
                                    )
                                    .id("scholium.researchGuidance.maintenanceAnchor")
                                }

                                HStack {
                                    Spacer()
                                    Button("Save Skill", action: saveSkill)
                                        .buttonStyle(.borderedProminent)
                                        .disabled(
                                            inspectedDraft?.validationIssues.isEmpty != true
                                                || isInspectingDraft
                                                || isWorking
                                                || skill.revision == nil
                                        )
                                }
                            } else {
                                Text("Built-in Skill source is release-managed. Duplicate it to make a Triptych-owned revision.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        }
                        .padding(18)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("scholium.researchGuidance.skillEditor")
            } else if let snapshot = selectedRecoverySnapshot {
                maintenanceRecoveryDetail(snapshot)
            } else if selectedSkillID == Self.recoveryIssuesSelection {
                maintenanceRecoveryIssuesDetail
            } else {
                ContentUnavailableView("Select a Skill", systemImage: "text.book.closed")
            }
        }
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .onChange(of: selectedSkillID) { _, _ in loadDraft() }
        .onChange(of: source) { _, newSource in
            scheduleDraftInspection()
            if newSource != selectedSkill?.source {
                maintenancePreparation = nil
            }
        }
        .onDisappear {
            draftInspectionTask?.cancel()
            maintenancePackageLoadTask?.cancel()
        }
        .confirmationDialog(
            "Delete Triptych Skill?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Skill", role: .destructive, action: deleteSkill)
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This permanently removes the selected Triptych-local skill package. Bundled guidance is not changed.")
        }
        .confirmationDialog(
            "Restore Complete Researcher Skill?",
            isPresented: Binding(
                get: { pendingMaintenanceRestore != nil },
                set: { if !$0 && !isWorking { pendingMaintenanceRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Complete Package", role: .destructive) {
                confirmMaintenanceRestore()
            }
            Button("Cancel", role: .cancel) { pendingMaintenanceRestore = nil }
        } message: {
            if let snapshot = pendingMaintenanceRestore {
                Text(maintenanceRestoreConfirmationMessage(snapshot))
            }
        }
        .alert("Could Not Manage Skills", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func skillSection(_ title: String, skills: [ResearchSkillPackage]) -> some View {
        Section(title) {
            if skills.isEmpty {
                Text("No \(title.lowercased()) skills")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(skills, id: \.selectionID) { skill in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name)
                            Text(ownershipLabel(for: skill))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !skill.isValid {
                                Text("Needs Attention")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    } icon: {
                        Image(systemName: skill.isValid ? "text.book.closed" : "exclamationmark.triangle")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.skill.\(skill.origin.rawValue).\(skill.id)"
                    )
                    .tag(skill.selectionID)
                }
            }
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        if !maintenanceSnapshots.isEmpty || !maintenanceSnapshotIssues.isEmpty {
            Section("Recovery") {
                ForEach(maintenanceSnapshots) { snapshot in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recoveryPackageName(snapshot.packageID))
                            Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.recovery.\(snapshot.id.uuidString)"
                    )
                    .tag(Self.recoverySelectionPrefix + snapshot.id.uuidString)
                }
                if !maintenanceSnapshotIssues.isEmpty {
                    Label(
                        "Recovery Issues (\(maintenanceSnapshotIssues.count))",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .tag(Self.recoveryIssuesSelection)
                }
            }
        }
    }

    private func maintenanceRecoveryDetail(
        _ snapshot: ResearchSkillMaintenanceSnapshot
    ) -> some View {
        let current = skills.first {
            $0.isTriptychLocal && $0.id == snapshot.packageID
        }
        let hasUnsavedDraft = hasUnsavedDraft(forPackageID: snapshot.packageID)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Recovery", systemImage: "clock.arrow.circlepath")
                    .font(.title2.weight(.semibold))
                Text(recoveryPackageName(snapshot.packageID))
                    .font(.headline)
                Text("This is a complete, backend-validated Researcher Skill snapshot. Restore rechecks the current package and creates a new undo snapshot before replacement.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GroupBox("Snapshot") {
                    VStack(alignment: .leading, spacing: 7) {
                        LabeledContent("Created") {
                            Text(snapshot.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        }
                        LabeledContent("Revision") {
                            Text(snapshot.packageRevision.sha256)
                                .font(ScholiumTypography.swiftUIMonospaceFont(
                                    size: 10,
                                    relativeTo: .caption
                                ))
                                .textSelection(.enabled)
                        }
                        LabeledContent("Current state") {
                            if let currentRevision = current?.revision {
                                Text(currentRevision == snapshot.packageRevision ? "This snapshot" : "Different revision")
                            } else if current == nil {
                                Text("Package missing")
                            } else {
                                Text("No safe revision")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if hasUnsavedDraft {
                    Label(
                        "Save or discard the unsaved SKILL.md draft before restoring this package.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
                if current?.revision == snapshot.packageRevision {
                    Label("This snapshot is the current package.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else if current != nil, current?.revision == nil {
                    Label(
                        "Scholium cannot prove the current package revision, so Restore is unavailable.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                } else {
                    Button("Restore…") { requestMaintenanceRestore(snapshot) }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking || hasUnsavedDraft)
                        .accessibilityIdentifier(
                            "scholium.researchGuidance.recoveryRestore.\(snapshot.id.uuidString)"
                        )
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("scholium.researchGuidance.recoveryDetail")
    }

    private var maintenanceRecoveryIssuesDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Recovery Issues", systemImage: "exclamationmark.triangle")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Valid snapshots remain available. Scholium will not restore the unsafe or corrupt entries listed below.")
                    .foregroundStyle(.secondary)
                ForEach(maintenanceSnapshotIssues) { issue in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.summary)
                            Text(issue.entryName)
                                .font(ScholiumTypography.swiftUIMonospaceFont(
                                    size: 10,
                                    relativeTo: .caption
                                ))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text(issue.code.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("scholium.researchGuidance.recoveryIssues")
    }

    private func loadDraft() {
        maintenancePackageLoadTask?.cancel()
        maintenancePackageLoadID = nil
        isLoadingMaintenancePackage = false
        draftInspectionTask?.cancel()
        isInspectingDraft = false
        guard let selectedSkill else { return }
        draftSkillSelectionID = selectedSkill.selectionID
        maintenanceCurrentPackage = nil
        maintenanceProposalError = nil
        let preservesAppliedMaintenance = maintenanceOutcome?.packageID == selectedSkill.id
            && maintenanceOutcome?.packageRevision == selectedSkill.revision
        source = selectedSkill.source
        inspectedDraft = selectedSkill.origin == .bundled ? selectedSkill : nil
        if !preservesAppliedMaintenance {
            maintenanceInstruction = ""
            maintenanceProposedPackage = nil
            maintenanceProposalSource = ""
            maintenanceEvaluationEvidenceSource = ""
            maintenancePreparation = nil
            maintenanceOutcome = nil
        }
        scheduleDraftInspection()
        scheduleMaintenancePackageLoad(for: selectedSkill)
    }

    private func scheduleDraftInspection() {
        draftInspectionTask?.cancel()
        guard let skill = selectedSkill else {
            inspectedDraft = nil
            isInspectingDraft = false
            return
        }
        guard skill.origin != .bundled else {
            inspectedDraft = skill
            isInspectingDraft = false
            return
        }
        let skillSelectionID = skill.selectionID
        let id = skill.id
        let draftSource = source
        let origin = skill.origin
        isInspectingDraft = true
        draftInspectionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(140))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let inspection = await settingsModel.inspectResearchSkillDraft(
                id: id,
                source: draftSource,
                origin: origin
            )
            guard !Task.isCancelled,
                  selectedSkillID == skillSelectionID,
                  source == draftSource else { return }
            inspectedDraft = inspection
            isInspectingDraft = false
        }
    }

    private func scheduleMaintenancePackageLoad(for skill: ResearchSkillPackage) {
        guard skill.isTriptychLocal,
              skill.skillClass == .researcher,
              skill.allowsEvolution,
              let expectedRevision = skill.revision else {
            return
        }
        let selectionID = skill.selectionID
        let loadID = UUID()
        maintenancePackageLoadID = loadID
        isLoadingMaintenancePackage = true
        maintenancePackageLoadTask = Task { @MainActor in
            defer {
                if selectedSkillID == selectionID,
                   maintenancePackageLoadID == loadID {
                    isLoadingMaintenancePackage = false
                    maintenancePackageLoadID = nil
                }
            }
            do {
                let package = try await completeMaintenancePackage(id: skill.id)
                try Task.checkCancellation()
                guard selectedSkillID == selectionID,
                      maintenancePackageLoadID == loadID else { return }
                guard package.packageRevision == expectedRevision else {
                    throw ResearchSkillMaintenanceError.stalePackage(skill.id)
                }
                maintenanceCurrentPackage = package
            } catch is CancellationError {
                return
            } catch {
                guard selectedSkillID == selectionID,
                      maintenancePackageLoadID == loadID else { return }
                maintenanceProposalError = error.localizedDescription
            }
        }
    }

    private func completeMaintenancePackage(
        id: String
    ) async throws -> ResearchSkillProposedPackage {
        let resourcePaths = try await settingsModel.researchSkillResourcePaths(id: id)
        for path in resourcePaths where !ResearchSkillMaintenancePath.isAllowed(path) {
            throw ResearchSkillMaintenanceError.invalidResourcePath(path)
        }
        var files: [ResearchSkillMaintenanceFile] = []
        files.reserveCapacity(resourcePaths.count)
        for path in resourcePaths {
            files.append(ResearchSkillMaintenanceFile(
                relativePath: path,
                source: try await settingsModel.researchSkillResource(
                    id: id,
                    relativePath: path
                )
            ))
        }
        let package = ResearchSkillProposedPackage(files: files)
        try package.validate()
        return package
    }

    private func ownershipLabel(for skill: ResearchSkillPackage) -> String {
        ResearchGuidancePresentation.ownershipLabel(for: skill)
    }

    @ViewBuilder
    private func routingRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private func capabilityTitle(_ capability: ResearchSkillCapability) -> String {
        switch capability {
        case .citationVerification: "Citation Verification"
        case .citationFormatting: "Citation Formatting"
        case .bibliographyRecommendation: "Bibliography Recommendation"
        }
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

    private func reload(selecting id: String? = nil) async {
        guard settingsModel.activeTriptychServicesID != nil else {
            skills = []
            maintenanceSnapshots = []
            maintenanceSnapshotIssues = []
            errorMessage = nil
            return
        }
        do {
            skills = try await settingsModel.researchSkills()
            do {
                let recovery = try await settingsModel.researchSkillMaintenanceSnapshots()
                maintenanceSnapshots = recovery.snapshots
                maintenanceSnapshotIssues = recovery.issues
            } catch {
                maintenanceSnapshots = []
                maintenanceSnapshotIssues = []
                errorMessage = "Research Skills loaded, but recovery inventory is unavailable. \(error.localizedDescription)"
            }
            if let id {
                selectedSkillID = skills.first {
                    $0.id == id && $0.origin == .triptych
                }?.selectionID ?? skills.first { $0.id == id }?.selectionID
            } else if selectedSkillID == nil {
                selectedSkillID = skills.first?.selectionID
            }
            let recoverySelectionExists = selectedRecoverySnapshot != nil
                || (selectedSkillID == Self.recoveryIssuesSelection
                    && !maintenanceSnapshotIssues.isEmpty)
            if !skills.contains(where: { $0.selectionID == selectedSkillID }),
               !recoverySelectionExists {
                selectedSkillID = skills.first?.selectionID
            }
            errorMessage = nil
            loadDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createSkill() {
        let existing = Set(skills.map(\.id))
        var id = "new-skill"
        var suffix = 2
        while existing.contains(id) {
            id = "new-skill-\(suffix)"
            suffix += 1
        }
        let source = """
        ---
        name: New Research Skill
        description: Describe when this Triptych-local guidance should be used.
        scholium:
          role: specialist
          supported_modes: [all]
        ---
        Add precise, reusable research instructions here.
        """
        perform {
            _ = try await settingsModel.createResearchSkill(id: id, source: source)
            await reload(selecting: id)
            refreshGuidanceStatus()
        }
    }

    private func duplicateSelectedSkill() {
        guard let skill = selectedSkill,
              skill.canDuplicate || skill.isTriptychLocal else { return }
        let existing = Set(skills.map(\.id))
        let officialStem = skill.id.hasPrefix("scholium-")
            ? String(skill.id.dropFirst("scholium-".count))
            : skill.id
        var newID = "\(officialStem)-copy"
        var suffix = 2
        while existing.contains(newID) {
            newID = "\(officialStem)-copy-\(suffix)"
            suffix += 1
        }
        let duplicateID = newID
        perform {
            if skill.origin == .bundled {
                _ = try await settingsModel.duplicateBundledResearchSkill(
                    id: skill.id,
                    as: duplicateID
                )
            } else {
                _ = try await settingsModel.createResearchSkill(
                    id: duplicateID,
                    source: skill.source
                )
            }
            await reload(selecting: duplicateID)
            refreshGuidanceStatus()
        }
    }

    private func saveSkill() {
        guard var skill = selectedSkill,
              skill.revision != nil else { return }
        let editedSource = source
        perform {
            if editedSource != skill.source {
                guard let currentRevision = skill.revision else {
                    throw ResearchSkillError.stalePackage(skill.id)
                }
                skill = try await settingsModel.saveResearchSkill(
                    id: skill.id,
                    source: editedSource,
                    expectedRevision: currentRevision
                )
            }
            await reload(selecting: skill.id)
            refreshGuidanceStatus()
            settingsModel.showToast("Skill saved")
        }
    }

    private func prepareMaintenance() {
        guard let skill = selectedSkill,
              skill.isTriptychLocal,
              skill.skillClass == .researcher,
              skill.allowsEvolution,
              source == skill.source,
              maintenanceProposalSourceMatchesImport,
              let revision = skill.revision,
              let proposedPackage = maintenanceProposedPackage else { return }
        let instruction = maintenanceInstruction
        perform {
            let request = ResearchSkillMaintenanceRequest(
                packageID: skill.id,
                expectedPackageRevision: revision,
                proposedPackage: proposedPackage,
                instruction: instruction,
                evaluationEvidence: try decodeMaintenanceEvaluationEvidence()
            )
            maintenancePreparation = try await settingsModel
                .prepareResearchSkillMaintenance(request)
            maintenanceOutcome = nil
        }
    }

    private func copyMaintenanceProposalRequest() {
        guard let skill = selectedSkill,
              maintenanceOutcome == nil,
              source == skill.source,
              let currentPackage = maintenanceCurrentPackage,
              let revision = skill.revision else { return }
        do {
            let handoff = try ResearchSkillMaintenanceProposalDraft.proposalRequest(
                packageID: skill.id,
                currentPackage: currentPackage,
                expectedPackageRevision: revision,
                purpose: maintenanceInstruction
            )
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(handoff, forType: .string)
            settingsModel.showToast("Agent proposal request copied")
        } catch {
            maintenanceProposalError = error.localizedDescription
        }
    }

    private func importMaintenanceProposal() {
        guard let skill = selectedSkill,
              maintenanceOutcome == nil,
              source == skill.source,
              let currentPackage = maintenanceCurrentPackage,
              currentPackage.packageRevision == skill.revision else { return }
        do {
            let proposal = try ResearchSkillMaintenanceProposalDraft.decode(
                maintenanceProposalSource
            )
            maintenanceProposalSource = try ResearchSkillMaintenanceProposalDraft.encode(
                proposal
            )
            maintenanceProposedPackage = proposal
            maintenanceProposalError = nil
            maintenanceEvaluationEvidenceSource = ""
            maintenancePreparation = nil
            maintenanceOutcome = nil
        } catch {
            maintenanceProposalError = error.localizedDescription
        }
    }

    private func decodeMaintenanceEvaluationEvidence(
    ) throws -> ResearchSkillMaintenanceExternalEvaluation? {
        let source = maintenanceEvaluationEvidenceSource.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !source.isEmpty else { return nil }
        guard let data = source.data(using: .utf8) else {
            throw ResearchSkillMaintenanceError.evaluationFailed
        }
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        do {
            return try isoDecoder.decode(
                ResearchSkillMaintenanceExternalEvaluation.self,
                from: data
            )
        } catch {
            return try JSONDecoder().decode(
                ResearchSkillMaintenanceExternalEvaluation.self,
                from: data
            )
        }
    }

    private func copyMaintenanceEvaluationRequest() {
        guard maintenancePreparationMatchesProposalDraft,
              let preparation = maintenancePreparation else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let packageJSON = String(
                decoding: try encoder.encode(preparation.request.proposedPackage),
                as: UTF8.self
            )
            let revision = preparation.proposedPackageRevision
            let resultTemplate: [String: Any] = [
                "proposedPackageRevision": [
                    "sha256": revision.sha256,
                    "byteCount": revision.byteCount,
                ],
                "evaluator": "<agent name, model, and version>",
                "method": "<semantic, source-fidelity, and adversarial evaluation method>",
                "status": "incomplete",
                "cases": [[
                    "id": "<case-id>",
                    "status": "incomplete",
                    "summary": "<finding and evidence>",
                ]],
                "evaluatedAt": ISO8601DateFormatter().string(from: Date()),
            ]
            let templateData = try JSONSerialization.data(
                withJSONObject: resultTemplate,
                options: [.prettyPrinted, .sortedKeys]
            )
            let templateJSON = String(decoding: templateData, as: UTF8.self)
            let handoff = """
            Evaluate this complete proposed Researcher Skill package for its stated philosophical workflow. Test source fidelity, conceptual and argumentative discipline, boundary behavior, and adversarial cases. Do not report passed unless every reported case passed. Bind the result to the exact proposal revision below.

            Maintenance purpose:
            \(preparation.request.instruction)

            Proposed package revision:
            \(revision.sha256) (\(revision.byteCount) bytes)

            Complete proposed package (JSON):
            \(packageJSON)

            Return only JSON matching this template. Replace every placeholder and report status truthfully:
            \(templateJSON)
            """
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(handoff, forType: .string)
            settingsModel.showToast("Agent evaluation handoff copied")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyMaintenance() {
        guard let preparation = maintenancePreparation,
              maintenancePreparationMatchesDraft else { return }
        let selectedID = preparation.request.packageID
        perform {
            maintenanceOutcome = try await settingsModel
                .applyResearchSkillMaintenance(preparation)
            await reload(selecting: selectedID)
            refreshGuidanceStatus()
        }
    }

    private func requestMaintenanceRestore(
        _ snapshot: ResearchSkillMaintenanceSnapshot
    ) {
        guard !isWorking,
              !hasUnsavedDraft(forPackageID: snapshot.packageID),
              skills.first(where: {
                  $0.isTriptychLocal && $0.id == snapshot.packageID
              })?.revision != snapshot.packageRevision else { return }
        pendingMaintenanceRestore = snapshot
    }

    private func confirmMaintenanceRestore() {
        guard let snapshot = pendingMaintenanceRestore else { return }
        pendingMaintenanceRestore = nil
        let expectedState: ResearchSkillMaintenanceExpectedCurrentState
        if let current = skills.first(where: {
            $0.isTriptychLocal && $0.id == snapshot.packageID
        }) {
            guard let revision = current.revision else {
                errorMessage = "Scholium cannot prove the current package revision."
                return
            }
            expectedState = .present(revision)
        } else {
            expectedState = .missing
        }
        let selectedID = snapshot.packageID
        perform {
            _ = try await settingsModel.restoreResearchSkillMaintenance(
                snapshotID: snapshot.id,
                expectedCurrentState: expectedState
            )
            maintenanceOutcome = nil
            await reload(selecting: selectedID)
            refreshGuidanceStatus()
        }
    }

    private func maintenanceRestoreConfirmationMessage(
        _ snapshot: ResearchSkillMaintenanceSnapshot
    ) -> String {
        let package = recoveryPackageName(snapshot.packageID)
        if let current = skills.first(where: {
            $0.isTriptychLocal && $0.id == snapshot.packageID
        }), let revision = current.revision {
            return "Replace the complete current \(package) package (\(revision.sha256.prefix(12))…) with snapshot \(snapshot.packageRevision.sha256.prefix(12))…? Scholium first creates a new undo snapshot. Files absent from the selected snapshot are removed."
        }
        return "Reinstall the complete missing \(package) package from snapshot \(snapshot.packageRevision.sha256.prefix(12))…? Scholium will recheck that the package is still absent before writing."
    }

    private func recoveryPackageName(_ packageID: String) -> String {
        skills.first(where: { $0.id == packageID && $0.isTriptychLocal })?.name
            ?? packageID
    }

    private func hasUnsavedDraft(forPackageID packageID: String) -> Bool {
        guard let skill = skills.first(where: {
            $0.isTriptychLocal && $0.id == packageID
        }), draftSkillSelectionID == skill.selectionID else { return false }
        return source != skill.source
    }

    private func deleteSkill() {
        guard let skill = pendingDeletion,
              let revision = skill.revision else {
            pendingDeletion = nil
            return
        }
        pendingDeletion = nil
        perform {
            try await settingsModel.deleteResearchSkill(
                id: skill.id,
                expectedRevision: revision
            )
            // When a Triptych package shadowed a bundled package with the
            // same ID, keep the researcher's conceptual selection on that
            // package after deletion instead of jumping to an unrelated row.
            await reload(selecting: skill.id)
            refreshGuidanceStatus()
        }
    }

    private func revealSkillsFolder() {
        perform {
            let url = try await settingsModel.researchSkillsURL()
            settingsModel.openExternal(url)
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct ZoteroSettingsView: View {
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
                    Button("Forget Cached Zotero Data", role: .destructive) {
                        Task {
                            try? await settingsModel.forgetZoteroCache()
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
    @State private var newTriptychID = UUID()
    @State private var showsNewTriptych = false

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
                    newTriptychID = UUID()
                    showsNewTriptych = true
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
        .sheet(isPresented: $showsNewTriptych) {
            WorkspacePathEditor(
                title: "Create a Triptych",
                explanation: "Choose one Analyses vault, one Topics vault, and one Works vault. Scholium does not create or manage projects inside Works.",
                completionTitle: "Create Triptych",
                targetTriptychID: newTriptychID,
                showsCancel: true,
                onCompletion: {
                    let createdID = settingsModel.workspaceAssignment?.id ?? newTriptychID
                    selectedTriptychID = createdID
                    showsNewTriptych = false
                    openWindow(
                        id: "scholium-main",
                        value: TriptychWindowRoute(triptychID: createdID)
                    )
                },
                onCancel: { showsNewTriptych = false }
            )
            .environmentObject(settingsModel)
            .frame(minWidth: 640, idealWidth: 700, minHeight: 500)
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

private struct CSSSnippetSettingsView: View {
    @ObservedObject var store: CSSSnippetStore
    let onOpenExternalURL: (URL) -> Void
    @State private var selectedSnippetID: UUID?
    @State private var importError: String?

    private static let previewSource = """
        # A Philosophical Question

        Clear prose should remain the center of the reading experience, with **emphasis**, *distinctions*, and [[Internal Links]].

        > A restrained quotation can carry an objection or a source passage.

        `Conceptual notation` uses the configured monospace treatment.

        > [!state] Semantic distinction
        > Callouts remain protected research signals while ordinary document styles can change.

        > [!flag] Source-status limit
        > A warning stays explicit in text and never depends on color alone.
        """
    private static let previewHTML = SafeMarkdownRenderer.render(
        NoteDocument(relativePath: "Style Preview.md", rawContent: previewSource)
    ).htmlBody

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Document Styles")
                    .font(.title2.weight(.semibold))
                Text("Import a limited CSS snippet for Read and Live Preview. Scholium protects callouts, footnotes, review annotations, diagnostics, and provenance warnings.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    List(selection: $selectedSnippetID) {
                        ForEach(store.snippets) { snippet in
                            CSSSnippetRow(
                                snippet: snippet,
                                error: store.validationErrors[snippet.id],
                                store: store
                            )
                            .tag(snippet.id)
                        }
                    }
                    .disabled(!store.canModify)
                    .overlay {
                        if store.snippets.isEmpty {
                            ContentUnavailableView(
                                "No CSS Snippets",
                                systemImage: "paintbrush",
                                description: Text("Import a CSS file to style document typography and ordinary Markdown content.")
                            )
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Button("Import CSS Snippet…") { importSnippet() }
                            .disabled(!store.canModify)
                        Button {
                            store.revealManagedFolder()
                        } label: {
                            Label("Reveal Snippets in Finder", systemImage: "folder")
                        }
                        .help("Reveal Scholium’s managed snippet copies in Finder")

                        Spacer()

                        Button("Disable All Snippets") { store.disableAll() }
                            .disabled(store.enabledCount == 0 || !store.canModify)
                    }
                    .padding(12)
                }
                .frame(minWidth: 330, idealWidth: 390)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)
                    Text("Enabled snippets update this sample and the open document immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SafeMarkdownReadWebView(
                        documentID: "style-preview",
                        fingerprint: String(store.readCSS.hashValue),
                        source: Self.previewSource,
                        htmlBody: Self.previewHTML,
                        userCSS: store.readCSS,
                        researcherComments: [],
                        onLinkClick: { _ in },
                        onOpenExternalURL: onOpenExternalURL,
                        onCommentSelection: nil,
                        onCommentActivation: nil,
                        onRenderingFailure: { reason in store.enterSafeMode(after: reason) }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    }
                }
                .padding(16)
                .frame(minWidth: 270, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

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
    }

    private func importSnippet() {
        let panel = NSOpenPanel()
        panel.title = "Import CSS Snippet"
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
                selectedSnippetID = store.snippets.last?.id
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
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
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(explanation)
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
            errorMessage = "Authorize the folder containing Works before saving this Triptych."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await settingsModel.configureThreeVaultWorkspace(
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
        panel.title = "Authorize the Folder Containing Works"
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
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
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
        panel.title = "Choose \(title) Folder"
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
