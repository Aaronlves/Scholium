import ScholiumContracts
import SwiftUI

enum WorkingMethodCatalog {
    static let actions: [ResearchActionID] = [
        .discuss, .analyze, .synthesize, .write, .critique, .checkFidelity,
        .manuscript,
    ]

    static let workingPackageIDs: [ResearchActionID: String] = [
        .discuss: "scholium-working-discuss",
        .analyze: "scholium-working-analyze",
        .synthesize: "scholium-working-synthesize",
        .write: "scholium-working-write",
        .critique: "scholium-working-critique",
        .checkFidelity: "scholium-working-content-fidelity",
        .manuscript: "scholium-working-manuscript",
    ]

    static let bundledPackageIDs: [ResearchActionID: String] = [
        .discuss: "scholium-discuss",
        .analyze: "scholium-analyze",
        .synthesize: "scholium-synthesize",
        .write: "scholium-write",
        .critique: "scholium-critique",
        .checkFidelity: "scholium-content-fidelity",
        .manuscript: "scholium-manuscript",
    ]

    static var workingPackageIDSet: Set<String> {
        Set(workingPackageIDs.values)
    }
}

private struct WorkingMethodEditorContext: Identifiable {
    let actionID: ResearchActionID
    let package: ResearchSkillPackage
    let bindingRevision: DocumentFingerprint

    var id: String { actionID.rawValue }
}

private struct WorkingMethodComparison: Identifiable {
    let actionID: ResearchActionID
    let currentSource: String
    let referenceSource: String

    var id: String { actionID.rawValue }
}

private struct WorkingMethodReplacement: Identifiable {
    let actionID: ResearchActionID
    let candidates: [ResearchSkillPackage]
    let bindingRevision: DocumentFingerprint

    var id: String { actionID.rawValue }
}

struct ResearchMethodsSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var bindings: ResearchWorkingMethodBindingSnapshot?
    @State private var profiles: ResearchActionProfileSnapshot?
    @State private var skills: [ResearchSkillPackage] = []
    @State private var editor: WorkingMethodEditorContext?
    @State private var comparison: WorkingMethodComparison?
    @State private var replacement: WorkingMethodReplacement?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Methods",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Each Triptych owns directly editable Working Methods. Bundled references are used only when you explicitly compare or restore.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                researchSettingsSection(LocalizedStringResource(
                    "WORKING METHOD SKILLS",
                    table: "Localizable",
                    bundle: .module
                )) {
                    if bindings == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("This Triptych does not yet have editable Working Methods.")
                                .foregroundStyle(.secondary)
                            Button("Install Working Methods") { installWorkingMethods() }
                                .buttonStyle(.borderedProminent)
                                .disabled(isWorking)
                                .accessibilityIdentifier(
                                    "scholium.researchGuidance.installWorkingMethods"
                                )
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(WorkingMethodCatalog.actions, id: \.rawValue) { actionID in
                                workingMethodRow(actionID)
                                if actionID != WorkingMethodCatalog.actions.last {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                researchSettingsSection(LocalizedStringResource(
                    "BOUNDARY",
                    table: "Localizable",
                    bundle: .module
                )) {
                    Text("Method prose can guide scholarly work, but it cannot change identity, revision, permission, checkpoint, conflict, completion, or recovery rules.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .disabled(loadedTriptychID != settingsModel.activeTriptychServicesID)
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .sheet(item: $editor) { context in
            WorkingMethodSourceEditor(context: context) { source in
                guard let packageRevision = context.package.revision else {
                    throw ResearchSkillError.stalePackage(context.package.id)
                }
                _ = try await settingsModel.saveWorkingMethod(
                    for: context.actionID,
                    source: source,
                    expectedPackageRevision: packageRevision,
                    expectedBindingRevision: context.bindingRevision
                )
                await reload()
            }
        }
        .sheet(item: $comparison) { comparison in
            WorkingMethodComparisonView(comparison: comparison)
        }
        .sheet(item: $replacement) { replacement in
            WorkingMethodReplacementView(replacement: replacement) { packageID in
                _ = try await settingsModel.activateResearcherSkill(
                    packageID: packageID,
                    for: replacement.actionID,
                    expectedBindingRevision: replacement.bindingRevision
                )
                await reload()
            }
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
    private func workingMethodRow(_ actionID: ResearchActionID) -> some View {
        let binding = bindings?.document.binding(for: actionID)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(actionTitle(actionID))
                    .font(.body.weight(.medium))
                Text(methodStatus(binding, actionID: actionID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(methodStatus(binding, actionID: actionID))
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.method.\(actionID.rawValue).status"
                    )
            }
            Spacer(minLength: 12)
            Menu("Manage") {
                if let context = editorContext(actionID, binding: binding) {
                    Button("Edit Method") { editor = context }
                }
                if let comparison = comparisonContext(actionID, binding: binding) {
                    Button("Compare with Bundled Reference") {
                        self.comparison = comparison
                    }
                }
                if let binding, binding.state != .disabled {
                    Button("Disable") { disable(actionID) }
                }
                if let bindingRevision = bindings?.revision {
                    let candidates = replacementCandidates(for: actionID)
                    if !candidates.isEmpty {
                        Button("Replace…") {
                            replacement = WorkingMethodReplacement(
                                actionID: actionID,
                                candidates: candidates,
                                bindingRevision: bindingRevision
                            )
                        }
                    }
                    Divider()
                    if actionID == .manuscript, binding?.state == .disabled {
                        Button("Enable as Work Action") { enableManuscript() }
                    } else if actionID != .manuscript {
                        Button("Restore Bundled Reference") { restore(actionID) }
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .disabled(isWorking || bindings == nil)
            .accessibilityIdentifier(
                "scholium.researchGuidance.method.\(actionID.rawValue).manage"
            )
        }
        .frame(minHeight: ScholiumGrid.Dimension.researchFunctionTargetHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchGuidance.method.\(actionID.rawValue)")
    }

    private func methodStatus(
        _ binding: ResearchWorkingMethodBinding?,
        actionID: ResearchActionID
    ) -> String {
        guard let binding else {
            return ScholiumL10n.localized(LocalizedStringResource(
                "Configuration unavailable",
                table: "Localizable",
                bundle: .module
            ))
        }
        switch binding.state {
        case .installedDefault:
            return ScholiumL10n.localized(LocalizedStringResource(
                "Editable Triptych Working Method",
                table: "Localizable",
                bundle: .module
            ))
        case .researcherSkill:
            let packageID = binding.packageID ?? ScholiumL10n.localized(
                LocalizedStringResource(
                    "Unavailable",
                    table: "Localizable",
                    bundle: .module
                )
            )
            return ScholiumL10n.localized(LocalizedStringResource(
                "Researcher Skill: \(packageID)",
                table: "Localizable",
                bundle: .module
            ))
        case .disabled:
            if actionID == .manuscript {
                return ScholiumL10n.localized(LocalizedStringResource(
                    "Disabled and hidden",
                    table: "Localizable",
                    bundle: .module
                ))
            }
            return ScholiumL10n.localized(LocalizedStringResource(
                "Disabled",
                table: "Localizable",
                bundle: .module
            ))
        }
    }

    private func editorContext(
        _ actionID: ResearchActionID,
        binding: ResearchWorkingMethodBinding?
    ) -> WorkingMethodEditorContext? {
        guard let binding,
              binding.state == .installedDefault
                || (actionID == .manuscript && binding.state == .researcherSkill),
              let packageID = binding.packageID,
              let package = skills.first(where: {
                  $0.origin == .triptych && $0.id == packageID
              }),
              let bindingRevision = bindings?.revision else { return nil }
        return WorkingMethodEditorContext(
            actionID: actionID,
            package: package,
            bindingRevision: bindingRevision
        )
    }

    private func comparisonContext(
        _ actionID: ResearchActionID,
        binding: ResearchWorkingMethodBinding?
    ) -> WorkingMethodComparison? {
        guard let packageID = binding?.packageID,
              let current = skills.first(where: {
                  $0.origin == .triptych && $0.id == packageID
              }),
              let referenceID = WorkingMethodCatalog.bundledPackageIDs[actionID],
              let reference = skills.first(where: {
                  $0.origin == .bundled && $0.id == referenceID
              }) else { return nil }
        return WorkingMethodComparison(
            actionID: actionID,
            currentSource: current.source,
            referenceSource: reference.source
        )
    }

    private func replacementCandidates(
        for actionID: ResearchActionID
    ) -> [ResearchSkillPackage] {
        skills.filter {
            $0.origin == .triptych
                && $0.isValid
                && $0.role == "method"
                && $0.supports(actionID)
                && $0.id != bindings?.document.binding(for: actionID)?.packageID
        }
    }

    private func reload() async {
        guard let requestedTriptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            bindings = nil
            profiles = nil
            skills = []
            return
        }
        loadedTriptychID = nil
        editor = nil
        comparison = nil
        replacement = nil
        do {
            async let loadedBindings = settingsModel.workingMethodBindings()
            async let loadedProfiles = settingsModel.actionProfiles()
            async let loadedSkills = settingsModel.researchSkills()
            let (newBindings, newProfiles, newSkills) = try await (
                loadedBindings,
                loadedProfiles,
                loadedSkills
            )
            try Task.checkCancellation()
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            bindings = newBindings
            profiles = newProfiles
            skills = newSkills
            loadedTriptychID = requestedTriptychID
        } catch is CancellationError {
            return
        } catch {
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func disable(_ actionID: ResearchActionID) {
        guard let revision = bindings?.revision else { return }
        perform {
            if actionID == .manuscript,
               let profileBinding = profiles?.document.binding(for: .manuscript) {
                _ = try await settingsModel.saveActionProfile(
                    try profileBinding.replacingShowInActions(false),
                    expectedDocumentRevision: profiles?.revision
                )
            }
            _ = try await settingsModel.disableWorkingMethod(
                for: actionID,
                expectedBindingRevision: revision
            )
            await reload()
        }
    }

    private func installWorkingMethods() {
        perform {
            _ = try await settingsModel.installDefaultWorkingMethods()
            await reload()
        }
    }

    private func restore(_ actionID: ResearchActionID) {
        guard let bindingRevision = bindings?.revision,
              let packageID = WorkingMethodCatalog.workingPackageIDs[actionID] else { return }
        let current = skills.first {
            $0.origin == .triptych && $0.id == packageID
        }
        let state: ResearchWorkingMethodExpectedPackageState
        if let revision = current?.revision {
            state = .present(revision)
        } else {
            state = .missing
        }
        perform {
            _ = try await settingsModel.restoreBundledWorkingMethod(
                for: actionID,
                expectedPackageState: state,
                expectedBindingRevision: bindingRevision
            )
            await reload()
        }
    }

    private func enableManuscript() {
        guard let bindingRevision = bindings?.revision else { return }
        perform {
            let packageID = try await manuscriptPackageID()
            _ = try await settingsModel.activateResearcherSkill(
                packageID: packageID,
                for: .manuscript,
                expectedBindingRevision: bindingRevision
            )
            let profileBinding: ResearchActionProfileBinding
            if let existing = profiles?.document.binding(for: .manuscript) {
                profileBinding = existing
            } else {
                profileBinding = try Self.defaultManuscriptProfile(packageID: packageID)
            }
            _ = try await settingsModel.saveActionProfile(
                try profileBinding.replacingShowInActions(true),
                expectedDocumentRevision: profiles?.revision
            )
            await reload()
        }
    }

    private func manuscriptPackageID() async throws -> String {
        guard let id = WorkingMethodCatalog.workingPackageIDs[.manuscript] else {
            throw ResearchActionProfileStorageError.invalidPackageID(
                "scholium-working-manuscript"
            )
        }
        if skills.contains(where: { $0.origin == .triptych && $0.id == id }) {
            return id
        }
        return try await settingsModel.duplicateBundledResearchSkill(
            id: "scholium-manuscript",
            as: id
        ).id
    }

    private static func defaultManuscriptProfile(
        packageID: String
    ) throws -> ResearchActionProfileBinding {
        guard let instructionModuleID = ResearchActionModuleID(rawValue: "instruction") else {
            throw ResearchActionProfileContractError.invalidModule(
                "The bundled Manuscript instruction module has an invalid identifier."
            )
        }
        return try ResearchActionProfileBinding(
            packageID: packageID,
            profile: ResearchActionProfile(
                definition: .manuscript,
                buttonName: "Manuscript",
                order: 100,
                applicableRoles: [.work],
                showInActions: false,
                modules: [
                    .boundedText(
                        id: instructionModuleID,
                        label: "Instruction",
                        isRequired: true,
                        maximumTextUTF8ByteCount: 4_000,
                        allowsMultipleLines: true
                    ),
                ],
                sourceRequirement: .none,
                capabilities: ResearchActionCapabilityDeclaration(readableRoles: [.work]),
                feedbackRequirement: .required
            )
        )
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

private struct WorkingMethodSourceEditor: View {
    @Environment(\.dismiss) private var dismiss
    let context: WorkingMethodEditorContext
    let save: (String) async throws -> Void
    @State private var source: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        context: WorkingMethodEditorContext,
        save: @escaping (String) async throws -> Void
    ) {
        self.context = context
        self.save = save
        _source = State(initialValue: context.package.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit \(actionTitle(context.actionID)) Method")
                .font(.title2.weight(.semibold))
            Text("This edits the Triptych Working Method directly. Saving creates a new package revision; the bundled reference remains unchanged.")
                .foregroundStyle(.secondary)
            TextEditor(text: $source)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 620, minHeight: 380)
                .accessibilityLabel("Working Method SKILL.md")
            HStack {
                Button("Revert Unsaved Changes") { source = context.package.source }
                    .disabled(source == context.package.source)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save Method") {
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
                .disabled(isSaving || source == context.package.source)
            }
        }
        .padding(20)
        .alert("Could Not Save Method", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
}

private struct WorkingMethodComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let comparison: WorkingMethodComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare \(actionTitle(comparison.actionID)) Method")
                .font(.title2.weight(.semibold))
            Text("This comparison is disposable. It does not replace or modify either Skill.")
                .foregroundStyle(.secondary)
            HSplitView {
                sourceColumn("Current Working Method", source: comparison.currentSource)
                sourceColumn("Bundled Reference", source: comparison.referenceSource)
            }
            .frame(minWidth: 760, minHeight: 420)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func sourceColumn(_ title: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView {
                Text(verbatim: source)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(8)
    }
}

private struct WorkingMethodReplacementView: View {
    @Environment(\.dismiss) private var dismiss
    let replacement: WorkingMethodReplacement
    let save: (String) async throws -> Void
    @State private var selection: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Replace \(actionTitle(replacement.actionID)) Method")
                .font(.title2.weight(.semibold))
            Text("Choose one complete, compatible Triptych-local Method. This changes only the current Triptych.")
                .foregroundStyle(.secondary)
            List(replacement.candidates, selection: $selection) { package in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: package.name)
                    Text(verbatim: package.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(Optional(package.id))
            }
            .frame(minWidth: 460, minHeight: 240)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Use Selected Method") {
                    guard let selection else { return }
                    isSaving = true
                    Task { @MainActor in
                        defer { isSaving = false }
                        do { try await save(selection); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil || isSaving)
            }
        }
        .padding(20)
        .alert("Could Not Replace Method", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("Dismiss", role: .cancel) {} } message: {
            Text(errorMessage ?? "")
        }
    }
}
