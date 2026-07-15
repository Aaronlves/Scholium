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

private struct ResearchGuidanceSettingsView: View {
    @AppStorage("scholium.settings.researchGuidanceCollection") private var collection = "prompt-templates"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Research Guidance Collection", selection: $collection) {
                Text("Prompt Templates").tag("prompt-templates")
                Text("Skills").tag("skills")
                Text("Dialogue Response").tag("dialogue-response")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)
            .padding(.vertical, 10)
            .accessibilityIdentifier("scholium.researchGuidance.collection")
            Divider()
            if collection == "skills" {
                // A SKILL.md can be thousands of lines long. Keep its editor
                // inside the finite Settings viewport instead of allowing the
                // text view's intrinsic document height to expand and clip the
                // collection picker and package list.
                GeometryReader { proxy in
                    ResearchSkillsSettingsView()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            } else if collection == "dialogue-response" {
                DialogueResponseSettingsView()
            } else {
                PromptTemplateSettingsView()
            }
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
                Button("Save Dialogue Response Defaults") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || !unknownModuleIDs.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .task { await load() }
        .alert("Could Not Save Dialogue Response Defaults", isPresented: Binding(
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
                settingsModel.showToast("Dialogue response defaults saved")
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
    @State private var skills: [ResearchSkillPackage] = []
    @State private var selectedSkillID: String?
    @State private var identifier = ""
    @State private var source = ""
    @State private var showsRoutingMetadata = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var pendingDeletion: ResearchSkillPackage?

    private var selectedSkill: ResearchSkillPackage? {
        skills.first { $0.selectionID == selectedSkillID }
    }

    private var inspectedDraft: ResearchSkillPackage? {
        guard let selectedSkill else { return nil }
        return ResearchSkillInspector.inspect(
            id: identifier,
            source: source,
            origin: selectedSkill.origin
        )
    }

    private var displayedRoutingPackage: ResearchSkillPackage? {
        guard let selectedSkill else { return nil }
        return selectedSkill.origin == .bundled ? selectedSkill : inspectedDraft
    }

    private var targetConflictsWithBundledPackage: Bool {
        guard selectedSkill?.isTriptychLocal == true else { return false }
        return skills.contains { $0.origin == .bundled && $0.id == identifier }
    }

    private var displayedValidationIssues: [String] {
        var issues = inspectedDraft?.validationIssues ?? []
        if targetConflictsWithBundledPackage {
            issues.append(
                "This identifier belongs to a protected Scholium package. Rename this Triptych-local package or delete it."
            )
        }
        return Array(Set(issues)).sorted()
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSkillID) {
                skillSection("Bundled", skills: skills.filter { $0.origin == .bundled })
                skillSection("Triptych", skills: skills.filter { $0.origin != .bundled })
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
                    Button("Reveal Skills Folder", action: revealSkillsFolder)
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(.bar)
            }
        } detail: {
            if let skill = selectedSkill {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(skill.name)
                                .font(.title2.weight(.semibold))
                            Text(ownershipLabel(for: skill))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(skill.description.isEmpty ? "No valid description is available." : skill.description)
                            .foregroundStyle(.secondary)
                        TextField("Skill Identifier", text: $identifier)
                            .disabled(skill.origin == .bundled)
                            .accessibilityHint("Use lowercase letters, numbers, and hyphens.")
                        if let routing = displayedRoutingPackage {
                            DisclosureGroup(
                                "Routing Metadata",
                                isExpanded: $showsRoutingMetadata
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    routingRow("Role", routing.role)
                                    routingRow(
                                        "Supported modes",
                                        routing.supportedModes.map(\.displayName).joined(separator: ", ")
                                    )
                                    routingRow(
                                        "Automatic modes",
                                        routing.automaticModes.isEmpty
                                            ? "None"
                                            : routing.automaticModes.map(\.displayName).joined(separator: ", ")
                                    )
                                    routingRow(
                                        "Required packages",
                                        routing.requiredSkillIDs.isEmpty
                                            ? "None"
                                            : routing.requiredSkillIDs.joined(separator: ", ")
                                    )
                                    routingRow(
                                        "Compatible Practices",
                                        routing.compatiblePracticeIDs.isEmpty
                                            ? "None"
                                            : routing.compatiblePracticeIDs.joined(separator: ", ")
                                    )
                                    routingRow(
                                        "Practice resources",
                                        routing.practiceResources.isEmpty
                                            ? "None"
                                            : routing.practiceResources.sorted(by: { $0.key < $1.key })
                                                .map { "\($0.key): \($0.value)" }
                                                .joined(separator: ", ")
                                    )
                                    routingRow("Version", routing.version)
                                    routingRow("Update policy", routing.updatePolicy)
                                    Text("Package class and update policy come from origin. Triptych-local frontmatter cannot override them, and compatibility never activates a Practice automatically.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 6)
                            }
                            .accessibilityIdentifier("scholium.researchGuidance.skillRouting")
                        }
                        TextEditor(text: $source)
                            .font(ScholiumTypography.swiftUIMonospaceFont(size: 13, relativeTo: .body))
                            .frame(maxWidth: .infinity, minHeight: 220, idealHeight: 300, maxHeight: 360)
                            .scrollContentBackground(.visible)
                            .disabled(skill.origin == .bundled || skill.revision == nil)
                            .accessibilityLabel("SKILL.md source")
                        if !displayedValidationIssues.isEmpty {
                            Label(displayedValidationIssues.joined(separator: " "), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("scholium.researchGuidance.skillValidation")
                        } else {
                            Text("Valid packages supply name and description frontmatter plus nonempty instruction content. Scholium validates structure, not philosophical quality.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            if skill.canDuplicate {
                                Button("Duplicate into Triptych", action: duplicateBundled)
                            }
                            Spacer()
                            if skill.isTriptychLocal {
                                Button("Save Skill", action: saveSkill)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(
                                        inspectedDraft?.validationIssues.isEmpty != true
                                            || targetConflictsWithBundledPackage
                                            || isWorking
                                            || skill.revision == nil
                                    )
                            }
                        }
                    }
                    .padding(18)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("scholium.researchGuidance.skillEditor")
            } else {
                ContentUnavailableView("Select a Skill", systemImage: "text.book.closed")
            }
        }
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .onChange(of: selectedSkillID) { _, _ in loadDraft() }
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

    private func loadDraft() {
        guard let selectedSkill else { return }
        identifier = selectedSkill.id
        source = selectedSkill.source
    }

    private func ownershipLabel(for skill: ResearchSkillPackage) -> String {
        if skill.origin == .bundled, skill.skillClass == .researcher {
            return "Researcher Template · Bundled"
        }
        let classLabel = switch skill.skillClass {
        case .system: "System"
        case .workflow: "Workflow"
        case .researcher: "Researcher"
        }
        return "\(classLabel) · \(skill.origin.displayName)"
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

    private func reload(selecting id: String? = nil) async {
        do {
            skills = try await settingsModel.researchSkills()
            if let id {
                selectedSkillID = skills.first {
                    $0.id == id && $0.origin == .triptych
                }?.selectionID ?? skills.first { $0.id == id }?.selectionID
            } else if selectedSkillID == nil {
                selectedSkillID = skills.first?.selectionID
            }
            if !skills.contains(where: { $0.selectionID == selectedSkillID }) {
                selectedSkillID = skills.first?.selectionID
            }
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
        }
    }

    private func duplicateBundled() {
        guard let skill = selectedSkill, skill.canDuplicate else { return }
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
            _ = try await settingsModel.duplicateBundledResearchSkill(
                id: skill.id,
                as: duplicateID
            )
            await reload(selecting: duplicateID)
        }
    }

    private func saveSkill() {
        guard var skill = selectedSkill,
              let revision = skill.revision else { return }
        let targetID = identifier
        let editedSource = source
        perform {
            if targetID != skill.id {
                skill = try await settingsModel.renameResearchSkill(
                    id: skill.id,
                    to: targetID,
                    expectedRevision: revision
                )
            }
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
            settingsModel.showToast("Skill saved")
        }
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
            await reload()
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
