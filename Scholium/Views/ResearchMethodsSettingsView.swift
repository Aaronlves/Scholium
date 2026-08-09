import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

private struct ResearchMethodEditorContext: Identifiable {
    let method: ResearchMethodSnapshot

    var id: ResearchSkillRegistrationKey { method.registration.key }
}

private struct NewResearchMethodContext: Identifiable {
    let actionID: ResearchActionID
    let expectedRegistrationRevision: DocumentFingerprint
    let suggestedName: String

    var id: ResearchActionID { actionID }
}

struct ResearchMethodsSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var registrations: ResearchSkillRegistrationSnapshot?
    @State private var methods: [ResearchActionID: ResearchMethodSnapshot] = [:]
    @State private var editor: ResearchMethodEditorContext?
    @State private var newMethod: NewResearchMethodContext?
    @State private var pendingDefaultRestore: ResearchMethodSnapshot?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource("Methods", table: "Localizable", bundle: .module),
                    detail: LocalizedStringResource(
                        "Each Action routes to one current primary Markdown method. Practices are derived only from exact Wikilinks in that method; an optional local folder remains ordinary Agent-readable storage, not a package.",
                        table: "Localizable",
                        bundle: .module
                    )
                )

                researchSettingsSection(LocalizedStringResource(
                    "RESEARCH SKILLS",
                    table: "Localizable",
                    bundle: .module
                )) {
                    if let registrations {
                        VStack(spacing: 0) {
                            ForEach(registrations.document.registrations) { registration in
                                methodRow(registration)
                                if registration.id != registrations.document.registrations.last?.id {
                                    Divider()
                                }
                            }
                        }
                    } else if isWorking {
                        ScholiumContentStateView(
                            "Loading Methods…",
                            indicator: .progress,
                            placement: .leading,
                            density: .compact
                        )
                    } else {
                        ScholiumContentStateView(
                            "Methods Unavailable",
                            detail: Text(errorMessage ?? "Open a complete Triptych."),
                            indicator: .symbol("text.book.closed", role: .attention),
                            placement: .leading,
                            density: .compact
                        )
                    }
                }

                researchSettingsSection(LocalizedStringResource(
                    "BOUNDARY",
                    table: "Localizable",
                    bundle: .module
                )) {
                    Text("Method and Practice prose guides scholarly work. It cannot change Platform Action support, Session scope, collaboration policy, write authorization, exact revisions, conflicts, or recovery.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .disabled(
            loadedTriptychID != settingsModel.activeTriptychServicesID
                || isWorking
        )
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .sheet(item: $editor) { context in
            ResearchMethodSourceEditor(context: context) { source in
                _ = try await settingsModel.saveResearchMethod(
                    registrationKey: context.method.registration.key,
                    source: source,
                    expectedRevision: context.method.primaryMarkdownRevision
                )
                await reload()
            }
        }
        .sheet(item: $newMethod) { context in
            NewResearchMethodEditor(context: context) { name, source in
                _ = try await settingsModel.createResearchMethod(
                    actionID: context.actionID,
                    displayName: name,
                    source: source,
                    expectedRegistrationRevision:
                        context.expectedRegistrationRevision
                )
                await reload()
            }
        }
        .confirmationDialog(
            "Restore the Current Scholium Default?",
            isPresented: Binding(
                get: { pendingDefaultRestore != nil },
                set: { if !$0 { pendingDefaultRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Default", role: .destructive) { restoreDefault() }
            Button("Cancel", role: .cancel) { pendingDefaultRestore = nil }
        } message: {
            Text("This replaces the current primary Markdown with the default shipped by this Scholium build. The current bytes remain available as the one previous-edit recovery point; no version history is created.")
        }
        .alert("Could Not Update Methods", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func methodRow(_ registration: ResearchSkillRegistration) -> some View {
        let method = methods[registration.actionID]
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(registration.displayName)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(registration.isEnabled ? "Enabled" : "Disabled")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                if let method {
                    if method.practices.isEmpty {
                        Text("No linked Practices")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    } else {
                        Text("Practices: \(method.practices.map(\.title).joined(separator: ", "))")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(method.practiceIssues.enumerated()), id: \.offset) { _, issue in
                        Label(
                            practiceIssueText(issue),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                    }
                    if let folder = method.skillFolderPath {
                        LabeledContent(
                            method.skillFolderIsAvailable == true
                                ? "Local folder"
                                : "Local folder unavailable",
                            value: folder
                        )
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .textSelection(.enabled)
                    }
                } else {
                    Label("Primary Markdown unavailable", systemImage: "exclamationmark.triangle")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                }
            }
            Spacer(minLength: 12)
            Menu("Manage") {
                if let method {
                    Button("Edit Primary Markdown") {
                        editor = ResearchMethodEditorContext(method: method)
                    }
                    Button("Restore Previous Edit") {
                        restorePrevious(method)
                    }
                    Divider()
                    Button("Restore Scholium Default…") {
                        pendingDefaultRestore = method
                    }
                }
                if let registrations {
                    Divider()
                    Button("Create New Skill…") {
                        newMethod = NewResearchMethodContext(
                            actionID: registration.actionID,
                            expectedRegistrationRevision: registrations.revision,
                            suggestedName: registration.displayName
                        )
                    }
                    Button("Register Markdown…") {
                        registerExternalMarkdown(for: registration)
                    }
                    Button("Register Skill Folder…") {
                        registerExternalFolder(for: registration)
                    }
                }
                Button(registration.isEnabled ? "Disable" : "Enable") {
                    setEnabled(!registration.isEnabled, registration: registration)
                }
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "scholium.researchGuidance.method.\(registration.actionID.rawValue)"
        )
    }

    private func practiceIssueText(_ issue: ResearchPracticeResolutionIssue) -> String {
        switch issue.kind {
        case .missing:
            "Missing Practice: \(issue.target)"
        case .ambiguous:
            "Ambiguous Practice: \(issue.target)"
        case .unsupportedReference:
            "Unsupported Practice reference: \(issue.target)"
        }
    }

    @MainActor
    private func reload() async {
        guard let triptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            registrations = nil
            methods = [:]
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let snapshot = try await settingsModel.researchSkillRegistrations()
            var loaded: [ResearchActionID: ResearchMethodSnapshot] = [:]
            for registration in snapshot.document.registrations where registration.isEnabled {
                if let method = try? await settingsModel.researchMethod(
                    for: registration.actionID
                ) {
                    loaded[registration.actionID] = method
                }
            }
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            registrations = snapshot
            methods = loaded
            loadedTriptychID = triptychID
            errorMessage = nil
        } catch {
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            registrations = nil
            methods = [:]
            loadedTriptychID = triptychID
            errorMessage = error.localizedDescription
        }
    }

    private func setEnabled(
        _ enabled: Bool,
        registration: ResearchSkillRegistration
    ) {
        guard let snapshot = registrations else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let replacement = try ResearchSkillRegistration(
                    key: registration.key,
                    actionID: registration.actionID,
                    displayName: registration.displayName,
                    primaryMarkdown: registration.primaryMarkdown,
                    skillFolder: registration.skillFolder,
                    isEnabled: enabled
                )
                _ = try await settingsModel.saveResearchSkillRegistrations(
                    snapshot.document.replacing(replacement),
                    expectedRevision: snapshot.revision
                )
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restorePrevious(_ method: ResearchMethodSnapshot) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await settingsModel.restorePreviousResearchMethod(
                    registrationKey: method.registration.key,
                    expectedRevision: method.primaryMarkdownRevision
                )
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restoreDefault() {
        guard let method = pendingDefaultRestore else { return }
        pendingDefaultRestore = nil
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await settingsModel.restoreDefaultResearchMethod(
                    actionID: method.registration.actionID,
                    expectedRevision: method.primaryMarkdownRevision
                )
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func registerExternalMarkdown(
        for registration: ResearchSkillRegistration
    ) {
        guard let registrations,
              let fileURL = Self.chooseMarkdown(
                message: "Choose the primary Markdown for this Research Skill."
              ) else { return }
        registerExternal(
            registration: registration,
            name: fileURL.deletingPathExtension().lastPathComponent,
            primaryURL: fileURL,
            folderURL: nil,
            expectedRevision: registrations.revision
        )
    }

    private func registerExternalFolder(
        for registration: ResearchSkillRegistration
    ) {
        guard let registrations,
              let folderURL = Self.chooseFolder(),
              let primaryURL = Self.chooseMarkdown(
                message: "Choose the primary Markdown inside the selected Skill folder.",
                directoryURL: folderURL
              ) else { return }
        registerExternal(
            registration: registration,
            name: folderURL.lastPathComponent,
            primaryURL: primaryURL,
            folderURL: folderURL,
            expectedRevision: registrations.revision
        )
    }

    private func registerExternal(
        registration: ResearchSkillRegistration,
        name: String,
        primaryURL: URL,
        folderURL: URL?,
        expectedRevision: DocumentFingerprint
    ) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await settingsModel.registerExternalResearchMethod(
                    actionID: registration.actionID,
                    displayName: name,
                    primaryMarkdownPath: primaryURL.standardizedFileURL.path,
                    skillFolderPath: folderURL?.standardizedFileURL.path,
                    expectedRegistrationRevision: expectedRevision
                )
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func chooseMarkdown(
        message: String,
        directoryURL: URL? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.directoryURL = directoryURL
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose an ordinary local Skill folder. Scholium records its path but does not inspect its other contents."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct ResearchMethodSourceEditor: View {
    let context: ResearchMethodEditorContext
    let save: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        context: ResearchMethodEditorContext,
        save: @escaping (String) async throws -> Void
    ) {
        self.context = context
        self.save = save
        _source = State(initialValue: context.method.primaryMarkdownSource)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(context.method.registration.displayName)")
                .font(ScholiumTypography.interface(.primaryTitle))
            Text("This edits the current primary Markdown only. Linked Practices and optional folder files keep their own exact bytes.")
                .scholiumForeground(.secondaryText)
            TextEditor(text: $source)
                .font(ScholiumTypography.exact(.body))
                .frame(minWidth: 700, minHeight: 480)
                .accessibilityLabel("Primary Research Skill Markdown")
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .scholiumForeground(.attention)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    isSaving = true
                    Task { @MainActor in
                        defer { isSaving = false }
                        do {
                            try await save(source)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || source == context.method.primaryMarkdownSource)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(minWidth: 740, minHeight: 580)
    }
}

private struct NewResearchMethodEditor: View {
    let context: NewResearchMethodContext
    let create: (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var source: String
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(
        context: NewResearchMethodContext,
        create: @escaping (String, String) async throws -> Void
    ) {
        self.context = context
        self.create = create
        _name = State(initialValue: context.suggestedName)
        _source = State(initialValue:
            "# \(context.suggestedName)\n\nState the complete primary research method here.\n"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Research Skill")
                .font(ScholiumTypography.interface(.primaryTitle))
            Text("Scholium creates one ordinary local folder and registers only this primary Markdown. It does not create a package, version, dependency graph, or resource manifest.")
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Display name", text: $name)
            TextEditor(text: $source)
                .font(ScholiumTypography.exact(.body))
                .frame(minWidth: 700, minHeight: 430)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .scholiumForeground(.attention)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Create") {
                    isCreating = true
                    Task { @MainActor in
                        defer { isCreating = false }
                        do {
                            try await create(name, source)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isCreating
                        || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(minWidth: 740, minHeight: 560)
    }
}
