import ScholiumContracts
import SwiftUI

struct ResearchMethodsSettingsView: View {
    let showsTitle: Bool

    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @State private var loadedTriptychID: UUID?
    @State private var registrations: ResearchSkillRegistrationSnapshot?
    @State private var bindings: [ResearchActionID: ResearchSkillBindingSnapshot] = [:]
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var canRecoverSkillFolderLocators = false
    @State private var confirmsSkillFolderLocatorRecovery = false

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
                            "Assign one researcher-owned Skill folder to each Action. Manage every file in Finder or your preferred editor; Scholium does not inspect or edit Skill contents.",
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
                                skillRow(registration)
                                if registration.id != registrations.document.registrations.last?.id {
                                    Divider()
                                }
                            }
                        }
                        if canRecoverSkillFolderLocators {
                            Divider()
                            ScholiumContentStateView(
                                "Skill Access Needs Repair",
                                detail: Text("The machine-local Skill-folder access registry is unreadable. Its original bytes can be archived before resetting local folder access; portable Action bindings and research vault files remain unchanged."),
                                indicator: .symbol("externaldrive.badge.exclamationmark", role: .attention),
                                placement: .leading,
                                density: .compact
                            ) {
                                Button("Archive and Reset Skill Access…") {
                                    confirmsSkillFolderLocatorRecovery = true
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
                    Text("Action Skills are researcher-owned folders. Scholium records their assignment and availability only; it never reads, validates, creates, replaces, or edits their files. Protected Protocols remain separate system sources. Neither kind grants permissions or alters Session, revision, conflict, or recovery rules.")
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
        .confirmationDialog(
            "Archive and Reset Skill Access?",
            isPresented: $confirmsSkillFolderLocatorRecovery,
            titleVisibility: .visible
        ) {
            Button("Archive and Reset", role: .destructive) {
                recoverSkillFolderLocators()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scholium will preserve the invalid machine-local Skill access file under a unique recovery name and reset only local folder paths and read-only bookmarks. Portable Action bindings, Skill files, and vault files will not be changed; external Skill folders must be assigned again on this Mac.")
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
    private func skillRow(_ registration: ResearchSkillRegistration) -> some View {
        let binding = bindings[registration.actionID]
        researchSettingsCollectionRow {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(registration.displayName)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(registration.isEnabled ? "Enabled" : "Disabled")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                if let binding {
                    LabeledContent(
                        binding.skillFolderIsAvailable
                            ? "Skill folder"
                            : "Skill folder unavailable",
                        value: binding.skillFolderPath
                    )
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
                    Text("The user and external Agents may read or edit this folder independently of Scholium.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                } else {
                    Label("Skill folder unavailable", systemImage: "exclamationmark.triangle")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                }
            }
        } actions: {
            Menu("Manage") {
                if let binding, binding.skillFolderIsAvailable {
                    Button("Show Skill Folder in Finder…") {
                        showFolder(for: registration.actionID)
                    }
                }
                if let registrations {
                    Button("Assign Skill Folder…") {
                        assignExternalFolder(
                            for: registration,
                            expectedRevision: registrations.revision
                        )
                    }
                }
                Divider()
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
            bindings = [:]
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let snapshot = try await settingsModel.researchSkillRegistrations()
            var loaded: [ResearchActionID: ResearchSkillBindingSnapshot] = [:]
            var locatorFailure: String?
            for registration in snapshot.document.registrations {
                do {
                    loaded[registration.actionID] = try await settingsModel
                        .researchSkillBinding(for: registration.actionID)
                } catch let error as ResearchSkillFolderLocatorError {
                    locatorFailure = error.localizedDescription
                }
            }
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            registrations = snapshot
            bindings = loaded
            loadedTriptychID = triptychID
            canRecoverSkillFolderLocators = locatorFailure != nil
            errorMessage = locatorFailure
        } catch {
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            registrations = nil
            bindings = [:]
            loadedTriptychID = triptychID
            if error is ResearchSkillFolderLocatorError {
                canRecoverSkillFolderLocators = true
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
                    skillFolder: registration.skillFolder,
                    isEnabled: enabled
                )
                _ = try await settingsModel.saveResearchSkillRegistrations(
                    snapshot.document.replacing(replacement),
                    expectedRevision: snapshot.revision
                )
                await reload()
            } catch {
                if error is ResearchSkillFolderLocatorError {
                    canRecoverSkillFolderLocators = true
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func recoverSkillFolderLocators() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let preserved = try await settingsModel
                    .recoverMachineLocalSkillFolderLocators()
                canRecoverSkillFolderLocators = false
                errorMessage = nil
                if let preserved {
                    settingsModel.presentFeedback(
                        String(
                            localized: "Previous Skill-folder access was preserved at \(preserved.path).",
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

    private func assignExternalFolder(
        for registration: ResearchSkillRegistration,
        expectedRevision: DocumentFingerprint
    ) {
        Task { @MainActor in
            do {
                guard let folderURL = try await chooseFolder() else { return }
                isWorking = true
                defer { isWorking = false }
                _ = try await settingsModel.registerExternalResearchSkillFolder(
                    actionID: registration.actionID,
                    displayName: folderURL.lastPathComponent,
                    skillFolderPath: folderURL.standardizedFileURL.path,
                    expectedRegistrationRevision: expectedRevision
                )
                await reload()
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func showFolder(for actionID: ResearchActionID) {
        Task { @MainActor in
            do {
                try await settingsModel.showResearchSkillFolder(for: actionID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseFolder() async throws -> URL? {
        try await fileSelectionPresenter
            .requiredForFileSelection()
            .selectURL(ScholiumFileSelectionRequest(
                message: String(
                    localized: "Choose the researcher-owned folder that an external Agent should load for this Action. Scholium records only the folder relation and does not inspect its contents.",
                    table: "Localizable",
                    bundle: .module
                ),
                kind: .directory(canCreateDirectories: false)
            ))
    }
}
