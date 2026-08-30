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
    let showsTitle: Bool

    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @State private var loadedTriptychID: UUID?
    @State private var registrations: ResearchSkillRegistrationSnapshot?
    @State private var methods: [ResearchActionID: ResearchMethodSnapshot] = [:]
    @State private var editor: ResearchMethodEditorContext?
    @State private var newMethod: NewResearchMethodContext?
    @State private var pendingDefaultRestore: ResearchMethodSnapshot?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var canRecoverMethodLocators = false
    @State private var confirmsMethodLocatorRecovery = false

    init(showsTitle: Bool = true) {
        self.showsTitle = showsTitle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                if showsTitle {
                    settingsTitle(
                        LocalizedStringResource("Skills", table: "Localizable", bundle: .module),
                        detail: LocalizedStringResource(
                            "Assign one Skill to each Action. Its SKILL.md routes ordinary references, including philosophical lenses.",
                            table: "Localizable",
                            bundle: .module
                        )
                    )
                }

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
                        if canRecoverMethodLocators {
                            Divider()
                            ScholiumContentStateView(
                                "Skill Access Needs Repair",
                                detail: Text("The machine-local Skill access registry is unreadable. Its original bytes can be archived before resetting local Skill access; portable registrations and research vault files remain unchanged."),
                                indicator: .symbol("externaldrive.badge.exclamationmark", role: .attention),
                                placement: .leading,
                                density: .compact
                            ) {
                                Button("Archive and Reset Skill Access…") {
                                    confirmsMethodLocatorRecovery = true
                                }
                            }
                        }
                    } else if isWorking {
                        ScholiumContentStateView(
                            "Loading Skills…",
                            indicator: .progress,
                            placement: .leading,
                            density: .compact
                        )
                    } else {
                        ScholiumContentStateView(
                            "Skills Unavailable",
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
                    Text("Skills and their ordinary references guide scholarly work; they never grant permissions or alter Session, revision, conflict, or recovery rules.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSettingsPaneSurface()
        .disabled(
            loadedTriptychID != settingsModel.activeTriptychServicesID
                || isWorking
        )
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .sheet(item: $editor) { context in
            ResearchGuidanceMarkdownEditSheet(
                title: Text("Edit \(context.method.registration.displayName)"),
                detail: Text("This edits SKILL.md only. Reference files, including philosophical lenses, keep their own exact bytes."),
                sourceAccessibilityLabel: Text("Primary Research Skill Markdown"),
                initialSource: context.method.primaryMarkdownSource
            ) { source in
                _ = try await settingsModel.saveResearchMethod(
                    registrationKey: context.method.registration.key,
                    source: source,
                    expectedRevision: context.method.primaryMarkdownRevision
                )
                await reload()
            }
        }
        .sheet(item: $newMethod) { context in
            ResearchGuidanceMarkdownCreationSheet(
                title: Text("Create Research Skill"),
                detail: Text("Scholium creates one ordinary local Skill folder with SKILL.md. Add references to that folder and route them explicitly from the Skill."),
                nameLabel: "Display name",
                sourceAccessibilityLabel: Text("Primary Research Skill Markdown"),
                initialName: context.suggestedName,
                initialSource: "# \(context.suggestedName)\n\nState the complete research Skill and route any task-relevant references here.\n"
            ) { name, source in
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
            Text("This replaces the current primary Markdown with the default shipped by this Scholium build.")
        }
        .confirmationDialog(
            "Archive and Reset Skill Access?",
            isPresented: $confirmsMethodLocatorRecovery,
            titleVisibility: .visible
        ) {
            Button("Archive and Reset", role: .destructive) {
                recoverMethodLocators()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scholium will preserve the invalid machine-local Skill access file under a unique recovery name and reset only local paths and bookmarks. Portable Skill registrations, Skill files, and vault files will not be changed; external Skills must be registered again on this Mac.")
        }
        .alert("Could Not Update Skills", isPresented: Binding(
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
        researchSettingsCollectionRow {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(registration.displayName)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(registration.isEnabled ? "Enabled" : "Disabled")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                if let method {
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
                        Text("References and philosophical lenses are ordinary files routed by SKILL.md.")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                } else {
                    Label("Primary Markdown unavailable", systemImage: "exclamationmark.triangle")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                }
            }
        } actions: {
            Menu("Manage") {
                if let method {
                    Button("Edit Primary Markdown") {
                        editor = ResearchMethodEditorContext(method: method)
                    }
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "scholium.researchGuidance.skill.\(registration.actionID.rawValue)"
        )
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
            var locatorFailure: String?
            for registration in snapshot.document.registrations where registration.isEnabled {
                do {
                    let method = try await settingsModel.researchMethod(
                        for: registration.actionID
                    )
                    loaded[registration.actionID] = method
                } catch let error as ResearchMethodLocatorError {
                    locatorFailure = error.localizedDescription
                }
            }
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            registrations = snapshot
            methods = loaded
            loadedTriptychID = triptychID
            canRecoverMethodLocators = locatorFailure != nil
            errorMessage = locatorFailure
        } catch {
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            registrations = nil
            methods = [:]
            loadedTriptychID = triptychID
            if error is ResearchMethodLocatorError {
                canRecoverMethodLocators = true
            }
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
                if error is ResearchMethodLocatorError {
                    canRecoverMethodLocators = true
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func recoverMethodLocators() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let preserved = try await settingsModel
                    .recoverMachineLocalMethodLocators()
                canRecoverMethodLocators = false
                errorMessage = nil
                if let preserved {
                    settingsModel.presentFeedback(
                        String(
                            localized: "Previous Method access was preserved at \(preserved.path).",
                            table: "Localizable",
                            bundle: .module
                        ),
                        kind: .warning
                    )
                }
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
        guard let registrations else { return }
        Task { @MainActor in
            do {
                guard let fileURL = try await chooseMarkdown(
                    message: "Choose the primary Markdown for this Research Skill."
                ) else { return }
                registerExternal(
                    registration: registration,
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    primaryURL: fileURL,
                    folderURL: nil,
                    expectedRevision: registrations.revision
                )
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func registerExternalFolder(
        for registration: ResearchSkillRegistration
    ) {
        guard let registrations else { return }
        Task { @MainActor in
            do {
                guard let folderURL = try await chooseFolder(),
                      let primaryURL = try await chooseMarkdown(
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
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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

    private func chooseMarkdown(
        message: LocalizedStringResource,
        directoryURL: URL? = nil
    ) async throws -> URL? {
        try await fileSelectionPresenter
            .requiredForFileSelection()
            .selectURL(ScholiumFileSelectionRequest(
                message: String(localized: message),
                initialDirectoryURL: directoryURL,
                kind: .files(
                    allowedContentTypes: [
                        UTType(filenameExtension: "md") ?? .plainText
                    ]
                )
            ))
    }

    private func chooseFolder() async throws -> URL? {
        try await fileSelectionPresenter
            .requiredForFileSelection()
            .selectURL(ScholiumFileSelectionRequest(
                message: String(
                    localized: "Choose an ordinary local Skill folder. Scholium records its path but does not inspect its other contents.",
                    table: "Localizable",
                    bundle: .module
                ),
                kind: .directory(canCreateDirectories: false)
            ))
    }
}
