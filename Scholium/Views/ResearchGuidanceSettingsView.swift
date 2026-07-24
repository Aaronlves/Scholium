import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

enum ResearchGuidanceCategory: String, CaseIterable, Identifiable {
    case methods = "Methods"
    case researcherSkills = "Researcher Skills"
    case permissions = "Permissions"
    case sources = "Sources & Integrations"
    case recovery = "Recovery & Technical"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .methods:
            LocalizedStringResource("Methods", table: "Localizable", bundle: .module)
        case .researcherSkills:
            LocalizedStringResource("Researcher Skills", table: "Localizable", bundle: .module)
        case .permissions:
            LocalizedStringResource("Permissions", table: "Localizable", bundle: .module)
        case .sources:
            LocalizedStringResource("Sources & Integrations", table: "Localizable", bundle: .module)
        case .recovery:
            LocalizedStringResource("Recovery & Technical", table: "Localizable", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .methods: "text.book.closed"
        case .researcherSkills: "wrench.and.screwdriver"
        case .permissions: "lock.shield"
        case .sources: "link"
        case .recovery: "arrow.counterclockwise"
        }
    }
}

struct ResearcherSkillDraftKey: Hashable {
    let triptychID: UUID
    let packageID: String
}

struct ResearchActionProfileDraftKey: Hashable {
    let triptychID: UUID
    let packageID: String
    let actionID: ResearchActionID
}

@MainActor
final class ResearchGuidanceDraftStore: ObservableObject {
    @Published private var skillDraftSources: [ResearcherSkillDraftKey: String] = [:]
    private var savedSkillSources: [ResearcherSkillDraftKey: String] = [:]
    @Published private var profileDrafts: [
        ResearchActionProfileDraftKey: ResearchActionProfileDraft
    ] = [:]
    private var savedProfileDrafts: [
        ResearchActionProfileDraftKey: ResearchActionProfileDraft
    ] = [:]

    func synchronizeSkills(
        triptychID: UUID,
        skills: [ResearchSkillPackage]
    ) {
        for skill in skills {
            let key = ResearcherSkillDraftKey(
                triptychID: triptychID,
                packageID: skill.id
            )
            if let saved = savedSkillSources[key], skillDraftSources[key] != saved {
                // Preserve the researcher's draft while making Discard return
                // to the latest source now visible from the Triptych.
                savedSkillSources[key] = skill.source
            } else {
                savedSkillSources[key] = skill.source
                skillDraftSources[key] = skill.source
            }
        }
    }

    func source(
        for skill: ResearchSkillPackage,
        triptychID: UUID
    ) -> String {
        skillDraftSources[ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: skill.id
        )] ?? skill.source
    }

    func updateSource(
        _ source: String,
        triptychID: UUID,
        packageID: String
    ) {
        skillDraftSources[ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: packageID
        )] = source
    }

    func hasUnsavedChanges(
        for skill: ResearchSkillPackage,
        triptychID: UUID
    ) -> Bool {
        let key = ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: skill.id
        )
        return source(for: skill, triptychID: triptychID)
            != (savedSkillSources[key] ?? skill.source)
    }

    func discardChanges(
        for skill: ResearchSkillPackage,
        triptychID: UUID
    ) {
        let key = ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: skill.id
        )
        skillDraftSources[key] = savedSkillSources[key] ?? skill.source
    }

    func markSkillSaved(
        _ source: String,
        triptychID: UUID,
        packageID: String
    ) {
        let key = ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: packageID
        )
        savedSkillSources[key] = source
        skillDraftSources[key] = source
    }

    func removeSkill(triptychID: UUID, packageID: String) {
        let key = ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: packageID
        )
        savedSkillSources.removeValue(forKey: key)
        skillDraftSources.removeValue(forKey: key)
    }

    func synchronizeProfile(
        key: ResearchActionProfileDraftKey,
        draft: ResearchActionProfileDraft
    ) {
        if let saved = savedProfileDrafts[key], profileDrafts[key] != saved {
            savedProfileDrafts[key] = draft
        } else {
            savedProfileDrafts[key] = draft
            profileDrafts[key] = draft
        }
    }

    func profileDraft(
        for key: ResearchActionProfileDraftKey,
        fallback: ResearchActionProfileDraft
    ) -> ResearchActionProfileDraft {
        profileDrafts[key] ?? fallback
    }

    func updateProfileDraft(
        _ draft: ResearchActionProfileDraft,
        for key: ResearchActionProfileDraftKey
    ) {
        profileDrafts[key] = draft
    }

    func profileHasUnsavedChanges(
        for key: ResearchActionProfileDraftKey,
        fallback: ResearchActionProfileDraft
    ) -> Bool {
        profileDraft(for: key, fallback: fallback)
            != (savedProfileDrafts[key] ?? fallback)
    }

    func discardProfileChanges(
        for key: ResearchActionProfileDraftKey,
        fallback: ResearchActionProfileDraft
    ) {
        profileDrafts[key] = savedProfileDrafts[key] ?? fallback
    }

    func markProfileSaved(
        _ draft: ResearchActionProfileDraft,
        for key: ResearchActionProfileDraftKey
    ) {
        savedProfileDrafts[key] = draft
        profileDrafts[key] = draft
    }

    func removeProfile(for key: ResearchActionProfileDraftKey) {
        savedProfileDrafts.removeValue(forKey: key)
        profileDrafts.removeValue(forKey: key)
    }
}

struct ResearchGuidanceSettingsView: View {
    @AppStorage("scholium.settings.researchGuidanceCategory")
    private var persistedCategory = ResearchGuidanceCategory.methods.rawValue
    @State private var category: ResearchGuidanceCategory = .methods
    @ObservedObject var draftStore: ResearchGuidanceDraftStore

    var body: some View {
        HSplitView {
            List(ResearchGuidanceCategory.allCases, selection: $category) { item in
                Label {
                    Text(item.localizedTitle)
                } icon: {
                    Image(systemName: item.symbol)
                }
                    .tag(item)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.category.\(item.id)"
                    )
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 240)
            .accessibilityIdentifier("scholium.researchGuidance.categoryList")

            Group {
                switch category {
                case .methods:
                    ResearchMethodsSettingsView()
                case .researcherSkills:
                    ResearcherSkillsSettingsView(draftStore: draftStore)
                case .permissions:
                    ResearchPermissionSettingsPlaceholder()
                case .sources:
                    ResearchSourcesSettingsView()
                case .recovery:
                    ResearchRecoverySettingsView()
                }
            }
            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            category = ResearchGuidanceCategory(rawValue: persistedCategory) ?? .methods
        }
        .onChange(of: category) { _, value in
            persistedCategory = value.rawValue
        }
    }
}

private enum WorkingMethodCatalog {
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

private struct ResearchMethodsSettingsView: View {
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

private func settingsTitle(
    _ title: LocalizedStringResource,
    detail: LocalizedStringResource
) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
        Text(detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func researchSettingsSection<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

func actionTitle(_ actionID: ResearchActionID) -> String {
    switch actionID {
    case .discuss:
        ScholiumL10n.localized(LocalizedStringResource(
            "Discuss", table: "Localizable", bundle: .module
        ))
    case .analyze:
        ScholiumL10n.localized(LocalizedStringResource(
            "Analyze", table: "Localizable", bundle: .module
        ))
    case .synthesize:
        ScholiumL10n.localized(LocalizedStringResource(
            "Synthesize", table: "Localizable", bundle: .module
        ))
    case .write:
        ScholiumL10n.localized(LocalizedStringResource(
            "Write", table: "Localizable", bundle: .module
        ))
    case .critique:
        ScholiumL10n.localized(LocalizedStringResource(
            "Critique", table: "Localizable", bundle: .module
        ))
    case .checkFidelity:
        ScholiumL10n.localized(LocalizedStringResource(
            "Check Fidelity", table: "Localizable", bundle: .module
        ))
    case .manuscript:
        ScholiumL10n.localized(LocalizedStringResource(
            "Manuscript", table: "Localizable", bundle: .module
        ))
    default: actionID.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

private extension ResearchActionProfileBinding {
    func replacingShowInActions(_ showInActions: Bool) throws -> Self {
        try ResearchActionProfileBinding(
            packageID: packageID,
            profile: ResearchActionProfile(
                definition: profile.definition,
                buttonName: profile.buttonName,
                order: profile.order,
                applicableRoles: profile.applicableRoles,
                showInActions: showInActions,
                modules: profile.modules,
                sourceRequirement: profile.sourceRequirement,
                capabilities: profile.capabilities,
                feedbackRequirement: profile.feedbackRequirement
            )
        )
    }

    func replacingOrder(_ order: Int) throws -> Self {
        try ResearchActionProfileBinding(
            packageID: packageID,
            profile: ResearchActionProfile(
                definition: profile.definition,
                buttonName: profile.buttonName,
                order: order,
                applicableRoles: profile.applicableRoles,
                showInActions: profile.showInActions,
                modules: profile.modules,
                sourceRequirement: profile.sourceRequirement,
                capabilities: profile.capabilities,
                feedbackRequirement: profile.feedbackRequirement
            )
        )
    }
}

private struct NewResearcherSkillDraft: Identifiable {
    let id = UUID()
    var packageID = "new-research-skill"
    var name = "New Research Skill"
    var actionID = "new-research-action"
    var executionKind: ResearchActionExecutionKind = .discussion

    var source: String {
        let mode: String = switch executionKind {
        case .discussion: "discuss"
        case .analysis: "analyze"
        case .synthesis: "synthesize"
        case .writing: "write"
        case .critique: "review"
        case .checkFidelity: "audit"
        case .manuscript: "manuscript"
        }
        return """
        ---
        name: \(name.trimmingCharacters(in: .whitespacesAndNewlines))
        description: Describe the bounded scholarly method this Skill provides.
        scholium:
          role: specialist
          supported_actions: [\(actionID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())]
          capabilities: []
          supported_modes: [\(mode)]
          required_skills: []
        ---
        State the method, evidential boundaries, and truthful feedback requirements here.
        """ + "\n"
    }
}

private struct ResearcherSkillsSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @ObservedObject var draftStore: ResearchGuidanceDraftStore
    @State private var loadedTriptychID: UUID?
    @State private var skills: [ResearchSkillPackage] = []
    @State private var profiles: ResearchActionProfileSnapshot?
    @State private var selectedPackageID: String?
    @State private var selectedActionID: ResearchActionID?
    @State private var installation: ResearchSkillInstallationPreparation?
    @State private var newSkillDraft: NewResearcherSkillDraft?
    @State private var pendingDeletion: ResearchSkillPackage?
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var localSkills: [ResearchSkillPackage] {
        skills.filter {
            $0.origin == .triptych
                && !WorkingMethodCatalog.workingPackageIDSet.contains($0.id)
        }
    }

    private var selectedSkill: ResearchSkillPackage? {
        localSkills.first { $0.id == selectedPackageID }
    }

    private var selectedProfileBinding: ResearchActionProfileBinding? {
        guard let selectedActionID else { return nil }
        return profiles?.document.binding(for: selectedActionID)
    }

    private var packageProfiles: [ResearchActionProfileBinding] {
        guard let selectedPackageID else { return [] }
        return profiles?.document.orderedBindings.filter {
            $0.packageID == selectedPackageID
        } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Researcher Skills",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Install or create bounded local Skills, edit their Triptych copy, and configure declarative Actions. Nothing runs or receives authority from this page.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                HStack {
                    Picker("Installed Skill", selection: $selectedPackageID) {
                        if localSkills.isEmpty {
                            Text("No Researcher Skills").tag(Optional<String>.none)
                        }
                        ForEach(localSkills) { skill in
                            Text(verbatim: skill.name).tag(Optional(skill.id))
                        }
                    }
                    .frame(maxWidth: 360)
                    Spacer()
                    Menu("Add Skill") {
                        Button("Install from Local Directory…") { chooseInstallationDirectory() }
                        Button("New Local Skill…") {
                            newSkillDraft = NewResearcherSkillDraft()
                        }
                    }
                }

                if let skill = selectedSkill {
                    skillEditor(skill)
                } else {
                    ContentUnavailableView(
                        "No Researcher Skills",
                        systemImage: "text.book.closed",
                        description: Text("Install a local directory or create a bounded Triptych-local Skill.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("scholium.researchGuidance.researcherSkills")
        .disabled(loadedTriptychID != settingsModel.activeTriptychServicesID)
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .onChange(of: selectedPackageID) { _, _ in loadSelectedSkill() }
        .sheet(item: $installation) { preparation in
            ResearchSkillInstallationSheet(
                preparation: preparation,
                triptychs: settingsModel.registeredTriptychs,
                activeTriptychID: settingsModel.activeTriptychServicesID,
                install: { triptychIDs in
                    _ = try await settingsModel.installResearcherSkill(
                        preparation,
                        to: triptychIDs
                    )
                    await reload(selecting: preparation.packageID)
                },
                discard: {
                    await settingsModel.discardResearcherSkillInstallation(
                        preparationID: preparation.id
                    )
                }
            )
        }
        .sheet(item: $newSkillDraft) { draft in
            NewResearcherSkillSheet(initialDraft: draft) { completed in
                _ = try await settingsModel.createResearchSkill(
                    id: completed.packageID,
                    source: completed.source
                )
                await reload(selecting: completed.packageID)
            }
        }
        .confirmationDialog(
            "Delete Researcher Skill?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Skill", role: .destructive) { deleteSelectedSkill() }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("A Skill still used by a Working Method or Action Profile cannot be deleted. Remove its binding first.")
        }
        .alert("Could Not Manage Researcher Skills", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func skillEditor(_ skill: ResearchSkillPackage) -> some View {
        researchSettingsSection(LocalizedStringResource(
            "SKILL PACKAGE",
            table: "Localizable",
            bundle: .module
        )) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    LabeledContent("State", value: skillStateTitle(skill))
                    Spacer()
                    Button("Delete…", role: .destructive) { pendingDeletion = skill }
                        .disabled(isWorking)
                }
                if !skill.validationIssues.isEmpty {
                    Label(
                        skill.validationIssues.joined(separator: " "),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(ScholiumColorRole.attention.color)
                    .font(.caption)
                }
                TextEditor(text: Binding(
                    get: { draftSource(for: skill) },
                    set: { updateDraftSource($0, for: skill) }
                ))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220, idealHeight: 280, maxHeight: 360)
                    .accessibilityLabel("Researcher Skill SKILL.md")
                HStack {
                    Text("Scholium validates structure and bounded routing, not philosophical quality.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Discard Unsaved Changes") {
                        discardDraftChanges(for: skill)
                    }
                    .disabled(!hasUnsavedDraftChanges(for: skill) || isWorking)
                    Button("Save Skill") { saveSkill(skill) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasUnsavedDraftChanges(for: skill) || isWorking)
                }
            }
        }

        researchSettingsSection(LocalizedStringResource(
            "ACTION PROFILES",
            table: "Localizable",
            bundle: .module
        )) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Action", selection: $selectedActionID) {
                        if packageProfiles.isEmpty {
                            Text("No configured Actions").tag(Optional<ResearchActionID>.none)
                        }
                        ForEach(packageProfiles, id: \.profile.actionID) { binding in
                            Text(verbatim: binding.profile.buttonName)
                                .tag(Optional(binding.profile.actionID))
                        }
                    }
                    .frame(maxWidth: 360)
                    Spacer()
                    Menu("New Action") {
                        let candidates = profileCandidates(for: skill)
                        if candidates.isEmpty {
                            Text("No unconfigured Action IDs in SKILL.md")
                        } else {
                            ForEach(candidates, id: \.rawValue) { actionID in
                                Button(actionTitle(actionID)) {
                                    selectedActionID = actionID
                                }
                            }
                        }
                    }
                    .disabled(!skill.isValid)
                }

                if let actionID = selectedActionID {
                    actionProfileEditor(skill: skill, actionID: actionID)
                } else {
                    Text("Create an Action from an identifier explicitly declared by this Skill. The Action starts hidden until its Profile is valid and deliberately shown.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func actionProfileEditor(
        skill: ResearchSkillPackage,
        actionID: ResearchActionID
    ) -> some View {
        if let triptychID = settingsModel.activeTriptychServicesID {
            let existing = profiles?.document.binding(for: actionID)
            let initial = existing.map(ResearchActionProfileDraft.init(binding:))
                ?? newProfileDraft(actionID: actionID, skill: skill)
            let draftKey = ResearchActionProfileDraftKey(
                triptychID: triptychID,
                packageID: skill.id,
                actionID: actionID
            )
            let deleteAction: (() async throws -> Void)? = existing == nil ? nil : {
                guard let revision = profiles?.revision else {
                    throw ResearchActionProfileStorageError.staleDocument
                }
                profiles = try await settingsModel.removeActionProfile(
                    actionID: actionID,
                    expectedDocumentRevision: revision
                )
                selectedActionID = packageProfiles.first?.profile.actionID
            }
            VStack(alignment: .leading, spacing: 8) {
                ResearchActionProfileEditorView(
                    package: skill,
                    initialDraft: initial,
                    draftKey: draftKey,
                    draftStore: draftStore,
                    isNew: existing == nil,
                    triptychs: settingsModel.registeredTriptychs,
                    activeTriptychID: triptychID,
                    save: { binding in
                        profiles = try await settingsModel.saveActionProfile(
                            binding,
                            expectedDocumentRevision: profiles?.revision
                        )
                        selectedActionID = binding.profile.actionID
                    },
                    copy: { binding, triptychIDs in
                        await settingsModel.copyActionProfile(binding, to: triptychIDs)
                    },
                    delete: deleteAction
                )
                .id("\(triptychID):\(skill.id):\(actionID.rawValue):\(profiles?.revision.sha256 ?? "new")")

                if existing != nil {
                    HStack {
                        Button("Move Earlier") { moveProfile(actionID, by: -1) }
                            .disabled(isWorking || !canMoveProfile(actionID, by: -1))
                        Button("Move Later") { moveProfile(actionID, by: 1) }
                            .disabled(isWorking || !canMoveProfile(actionID, by: 1))
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Active Triptych",
                systemImage: "rectangle.stack",
                description: Text("Choose a Triptych before editing an Action Profile.")
            )
        }
    }

    private func profileCandidates(for skill: ResearchSkillPackage) -> [ResearchActionID] {
        let globallyConfigured = Set(
            profiles?.document.actionBindings.keys.compactMap {
                ResearchActionID(rawValue: $0)
            } ?? []
        )
        return skill.supportedActions.filter {
            ($0 == .manuscript || !$0.isReservedForBundledAction)
                && !globallyConfigured.contains($0)
        }
    }

    private func newProfileDraft(
        actionID: ResearchActionID,
        skill: ResearchSkillPackage
    ) -> ResearchActionProfileDraft {
        let kind: ResearchActionExecutionKind = actionID == .manuscript
            ? .manuscript
            : .discussion
        return ResearchActionProfileDraft(
            actionID: actionID.rawValue,
            executionKind: kind,
            buttonName: actionTitle(actionID),
            order: (profiles?.document.orderedBindings.map(\.profile.order).max() ?? 0) + 1,
            applicableRoles: kind.allowedTargetRoles,
            showInActions: false
        )
    }

    private func chooseInstallationDirectory() {
        let panel = NSOpenPanel()
        panel.title = ScholiumL10n.localized(LocalizedStringResource(
            "Install Researcher Skill",
            table: "Localizable",
            bundle: .module
        ))
        panel.prompt = ScholiumL10n.localized(LocalizedStringResource(
            "Review Directory",
            table: "Localizable",
            bundle: .module
        ))
        panel.message = ScholiumL10n.localized(LocalizedStringResource(
            "Choose one local Skill directory. Scholium stages only bounded UTF-8 Skill resources and installs disabled copies.",
            table: "Localizable",
            bundle: .module
        ))
        panel.allowedContentTypes = [.folder]
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        perform {
            installation = try await settingsModel.stageResearcherSkillInstallation(
                from: directory
            )
        }
    }

    private func saveSkill(_ skill: ResearchSkillPackage) {
        guard let revision = skill.revision,
              let triptychID = settingsModel.activeTriptychServicesID else { return }
        let candidate = draftStore.source(for: skill, triptychID: triptychID)
        perform {
            let inspection = await settingsModel.inspectResearchSkillDraft(
                id: skill.id,
                source: candidate,
                origin: .triptych
            )
            guard let inspection, inspection.isValid else {
                throw ResearchSkillError.invalidPackage(
                    skill.id,
                    inspection?.validationIssues ?? ["The draft could not be validated."]
                )
            }
            let saved = try await settingsModel.saveResearchSkill(
                id: skill.id,
                source: candidate,
                expectedRevision: revision
            )
            draftStore.markSkillSaved(
                saved.source,
                triptychID: triptychID,
                packageID: saved.id
            )
            await reload(selecting: skill.id)
        }
    }

    private func deleteSelectedSkill() {
        guard let skill = pendingDeletion,
              let revision = skill.revision,
              let triptychID = settingsModel.activeTriptychServicesID else {
            pendingDeletion = nil
            return
        }
        pendingDeletion = nil
        perform {
            try await settingsModel.deleteResearchSkill(
                id: skill.id,
                expectedRevision: revision
            )
            draftStore.removeSkill(triptychID: triptychID, packageID: skill.id)
            await reload()
        }
    }

    private func moveProfile(_ actionID: ResearchActionID, by offset: Int) {
        guard let snapshot = profiles else { return }
        var ordered = snapshot.document.orderedBindings
        guard let sourceIndex = ordered.firstIndex(where: {
            $0.profile.actionID == actionID
        }) else { return }
        let destinationIndex = min(max(sourceIndex + offset, 0), ordered.count - 1)
        guard sourceIndex != destinationIndex else { return }
        ordered.swapAt(sourceIndex, destinationIndex)
        perform {
            var replacement: [ResearchActionID: ResearchActionProfileBinding] = [:]
            for (index, binding) in ordered.enumerated() {
                replacement[binding.profile.actionID] = try binding.replacingOrder(index)
            }
            profiles = try await settingsModel.saveActionProfileDocument(
                ResearchActionProfileDocument(actionBindings: replacement),
                expectedDocumentRevision: snapshot.revision
            )
        }
    }

    private func canMoveProfile(_ actionID: ResearchActionID, by offset: Int) -> Bool {
        guard let ordered = profiles?.document.orderedBindings,
              let sourceIndex = ordered.firstIndex(where: {
                  $0.profile.actionID == actionID
              }) else { return false }
        let destinationIndex = sourceIndex + offset
        return ordered.indices.contains(destinationIndex)
    }

    private func reload(selecting packageID: String? = nil) async {
        guard let requestedTriptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            skills = []
            profiles = nil
            newSkillDraft = nil
            return
        }
        loadedTriptychID = nil
        pendingDeletion = nil
        newSkillDraft = nil
        do {
            async let loadedSkills = settingsModel.researchSkills()
            async let loadedProfiles = settingsModel.actionProfiles()
            let (newSkills, newProfiles) = try await (
                loadedSkills,
                loadedProfiles
            )
            try Task.checkCancellation()
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            let newLocalSkills = newSkills.filter {
                $0.origin == .triptych
                    && !WorkingMethodCatalog.workingPackageIDSet.contains($0.id)
            }
            draftStore.synchronizeSkills(
                triptychID: requestedTriptychID,
                skills: newLocalSkills
            )
            skills = newSkills
            profiles = newProfiles
            let selection = packageID ?? selectedPackageID
            selectedPackageID = newLocalSkills.contains(where: { $0.id == selection })
                ? selection
                : newLocalSkills.first?.id
            loadSelectedSkill()
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

    private func loadSelectedSkill() {
        let available = packageProfiles.map(\.profile.actionID)
        if selectedActionID.map(available.contains) != true {
            selectedActionID = available.first
        }
    }

    private func draftSource(for skill: ResearchSkillPackage) -> String {
        guard let triptychID = settingsModel.activeTriptychServicesID else {
            return skill.source
        }
        return draftStore.source(for: skill, triptychID: triptychID)
    }

    private func updateDraftSource(
        _ source: String,
        for skill: ResearchSkillPackage
    ) {
        guard let triptychID = settingsModel.activeTriptychServicesID else { return }
        draftStore.updateSource(
            source,
            triptychID: triptychID,
            packageID: skill.id
        )
    }

    private func hasUnsavedDraftChanges(
        for skill: ResearchSkillPackage
    ) -> Bool {
        guard let triptychID = settingsModel.activeTriptychServicesID else {
            return false
        }
        return draftStore.hasUnsavedChanges(
            for: skill,
            triptychID: triptychID
        )
    }

    private func discardDraftChanges(for skill: ResearchSkillPackage) {
        guard let triptychID = settingsModel.activeTriptychServicesID else { return }
        draftStore.discardChanges(for: skill, triptychID: triptychID)
    }

    private func skillStateTitle(_ skill: ResearchSkillPackage) -> String {
        if skill.isValid {
            return ScholiumL10n.localized(LocalizedStringResource(
                "Structurally valid",
                table: "Localizable",
                bundle: .module
            ))
        }
        return ScholiumL10n.localized(LocalizedStringResource(
            "Needs repair",
            table: "Localizable",
            bundle: .module
        ))
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

private struct ResearchActionProfileEditorView: View {
    let package: ResearchSkillPackage
    let initialDraft: ResearchActionProfileDraft
    let draftKey: ResearchActionProfileDraftKey
    @ObservedObject var draftStore: ResearchGuidanceDraftStore
    let isNew: Bool
    let triptychs: [TriptychAssignment]
    let activeTriptychID: UUID
    let save: (ResearchActionProfileBinding) async throws -> Void
    let copy: (
        ResearchActionProfileBinding, [UUID]
    ) async -> ResearchActionProfileCopyOutcome
    let delete: (() async throws -> Void)?

    @State private var copyTargets: Set<UUID> = []
    @State private var previewIsNarrow = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var copyMessage: String?
    @State private var isConfirmingDeletion = false

    private var draft: ResearchActionProfileDraft {
        draftStore.profileDraft(for: draftKey, fallback: initialDraft)
    }

    private var draftBinding: Binding<ResearchActionProfileDraft> {
        Binding(
            get: { draftStore.profileDraft(for: draftKey, fallback: initialDraft) },
            set: { draftStore.updateProfileDraft($0, for: draftKey) }
        )
    }

    private var validationMessage: String? {
        draft.validationMessage(packageID: package.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            researchSettingsSection(LocalizedStringResource(
                "PLACEMENT",
                table: "Localizable",
                bundle: .module
            )) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Button name", text: draftBinding.buttonName)
                    Picker("Execution", selection: Binding(
                        get: { draft.executionKind },
                        set: { executionKind in
                            updateDraft { $0.selectExecutionKind(executionKind) }
                        }
                    )) {
                        ForEach(ResearchActionExecutionKind.allCases, id: \.rawValue) {
                            Text(executionTitle($0)).tag($0)
                        }
                    }
                    Stepper(
                        "Order: \(draft.order)",
                        value: draftBinding.order,
                        in: 0 ... 10_000
                    )
                    Toggle("Show in Actions", isOn: draftBinding.showInActions)
                        .accessibilityIdentifier(
                            "scholium.researchGuidance.profile.showInActions"
                        )
                    roleToggles(LocalizedStringResource(
                        "Applicable Note roles",
                        table: "Localizable",
                        bundle: .module
                    ), selection: draftBinding.applicableRoles)
                }
            }

            researchSettingsSection(LocalizedStringResource(
                "PROFILE MODULES",
                table: "Localizable",
                bundle: .module
            )) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(draftBinding.modules) { $module in
                        ResearchActionModuleDraftEditor(
                            module: $module,
                            remove: {
                                updateDraft { $0.removeModule(id: module.id) }
                            }
                        )
                    }
                    Menu("Add Declarative Module") {
                        ForEach(ResearchActionModuleKind.allCases, id: \.rawValue) { kind in
                            Button(moduleTitle(kind)) {
                                updateDraft { $0.addModule(kind: kind) }
                            }
                        }
                    }
                }
            }

            researchSettingsSection(LocalizedStringResource(
                "DECLARED CAPABILITIES",
                table: "Localizable",
                bundle: .module
            )) {
                VStack(alignment: .leading, spacing: 10) {
                    roleToggles(LocalizedStringResource(
                        "Readable roles",
                        table: "Localizable",
                        bundle: .module
                    ), selection: draftBinding.readableRoles)
                    roleToggles(LocalizedStringResource(
                        "Candidate writable roles",
                        table: "Localizable",
                        bundle: .module
                    ), selection: draftBinding.writableRoles)
                    Toggle("Modify Markdown", isOn: setBinding(
                        .modifyMarkdown,
                        in: draftBinding.writeOperations
                    ))
                    Toggle("Modify bounded Properties", isOn: setBinding(
                        .modifyProperties,
                        in: draftBinding.writeOperations
                    ))
                    if draft.writeOperations.contains(.modifyProperties) {
                        TextField(
                            "Editable property keys, one per line",
                            text: draftBinding.editablePropertyKeys,
                            axis: .vertical
                        )
                        .lineLimit(2 ... 6)
                    }
                    Picker("Source", selection: draftBinding.sourceRequirement) {
                        ForEach(ResearchActionSourceRequirement.allCases, id: \.rawValue) {
                            Text(sourceRequirementTitle($0)).tag($0)
                        }
                    }
                    Picker("Feedback", selection: draftBinding.feedbackRequirement) {
                        ForEach(ResearchActionFeedbackRequirement.allCases, id: \.rawValue) {
                            Text(feedbackRequirementTitle($0)).tag($0)
                        }
                    }
                    Text("Declarations can narrow a later grant; they cannot grant authority by themselves.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            researchSettingsSection(LocalizedStringResource(
                "NONEXECUTING ACTION SHEET PREVIEW",
                table: "Localizable",
                bundle: .module
            )) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Preview width", selection: $previewIsNarrow) {
                        Text("Regular").tag(false)
                        Text("Narrow").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    ResearchActionProfilePreview(draft: draft, narrow: previewIsNarrow)
                }
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(ScholiumColorRole.attention.color)
            }
            if let copyMessage {
                Text(copyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if delete != nil {
                    Button("Delete Action", role: .destructive) {
                        isConfirmingDeletion = true
                    }
                }
                Spacer()
                Button("Discard Unsaved Changes") {
                    draftStore.discardProfileChanges(
                        for: draftKey,
                        fallback: initialDraft
                    )
                }
                .disabled(
                    !draftStore.profileHasUnsavedChanges(
                        for: draftKey,
                        fallback: initialDraft
                    ) || isWorking
                )
                Menu("Save Copy to Triptychs") {
                    ForEach(triptychs.filter { $0.id != activeTriptychID }) { triptych in
                        Toggle(
                            triptych.triptych.name,
                            isOn: Binding(
                                get: { copyTargets.contains(triptych.id) },
                                set: { selected in
                                    if selected { copyTargets.insert(triptych.id) }
                                    else { copyTargets.remove(triptych.id) }
                                }
                            )
                        )
                    }
                    Divider()
                    Button("Save Selected Copies") { saveCopies() }
                        .disabled(copyTargets.isEmpty || validationMessage != nil)
                }
                Button(isNew ? "Create Action" : "Save Profile") { saveCurrent() }
                    .buttonStyle(.borderedProminent)
                    .disabled(validationMessage != nil || isWorking)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.profile.save"
                    )
            }
        }
        .onAppear {
            draftStore.synchronizeProfile(key: draftKey, draft: initialDraft)
        }
        .alert("Could Not Save Action Profile", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("Dismiss", role: .cancel) {} } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete Action Profile?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete Action", role: .destructive) {
                guard let delete else { return }
                isWorking = true
                Task { @MainActor in
                    defer { isWorking = false }
                    do {
                        try await delete()
                        draftStore.removeProfile(for: draftKey)
                    }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the Action Profile from the current Triptych. The Skill package remains, but the Profile has no undo and must be recreated to restore the Action.")
        }
    }

    private func saveCurrent() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let candidate = draft
                try await save(candidate.binding(packageID: package.id))
                draftStore.markProfileSaved(candidate, for: draftKey)
            }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func saveCopies() {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let outcome = await copy(
                    try draft.binding(packageID: package.id),
                    Array(copyTargets)
                )
                copyMessage = ScholiumL10n.localized(LocalizedStringResource(
                    "Created \(outcome.copiedTriptychIDs.count) independent Profile copies.",
                    table: "Localizable",
                    bundle: .module
                ))
                if !outcome.failures.isEmpty {
                    errorMessage = outcome.failures.values.sorted().joined(separator: " ")
                } else {
                    copyTargets.removeAll()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateDraft(
        _ update: (inout ResearchActionProfileDraft) -> Void
    ) {
        var updated = draft
        update(&updated)
        draftStore.updateProfileDraft(updated, for: draftKey)
    }

    @ViewBuilder
    private func roleToggles(
        _ title: LocalizedStringResource,
        selection: Binding<Set<ResearchActionTargetRole>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.medium))
            HStack {
                ForEach(ResearchActionTargetRole.allCases, id: \.rawValue) { role in
                    Toggle(roleTitle(role), isOn: setBinding(role, in: selection))
                        .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func setBinding<Value: Hashable>(
        _ value: Value,
        in selection: Binding<Set<Value>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { enabled in
                if enabled { selection.wrappedValue.insert(value) }
                else { selection.wrappedValue.remove(value) }
            }
        )
    }
}

private struct ResearchActionModuleDraftEditor: View {
    @Binding var module: ResearchActionModuleDraft
    let remove: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Module identifier", text: $module.moduleID)
                TextField("Label", text: $module.label)
                TextField("Help text", text: $module.helpText)
                Toggle("Required", isOn: $module.isRequired)
                switch module.kind {
                case .notePicker, .materialSelector:
                    Stepper(
                        "Maximum selections: \(module.maximumSelectionCount)",
                        value: $module.maximumSelectionCount,
                        in: 1 ... ResearchActionModuleDefinition.maximumPickerSelectionCount
                    )
                case .boundedText:
                    Stepper(
                        "Maximum UTF-8 bytes: \(module.maximumTextUTF8ByteCount)",
                        value: $module.maximumTextUTF8ByteCount,
                        in: 1 ... ResearchActionModuleDefinition.maximumBoundedTextUTF8ByteCount,
                        step: 100
                    )
                    Toggle("Allow multiple lines", isOn: $module.allowsMultipleLines)
                case .boolean:
                    Toggle("Default on", isOn: $module.defaultBoolean)
                case .enumeration:
                    TextField(
                        "Choices as value: Label",
                        text: $module.enumerationChoices,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 8)
                    Stepper(
                        "Maximum selections: \(module.maximumSelectionCount)",
                        value: $module.maximumSelectionCount,
                        in: 1 ... ResearchActionModuleDefinition.maximumEnumerationSelectionCount
                    )
                case .passageAnchor, .sourceReference:
                    EmptyView()
                }
                Button("Remove Module", role: .destructive, action: remove)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(module.label.isEmpty ? moduleTitle(module.kind) : module.label)
                Spacer()
                Text(moduleTitle(module.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ResearchActionProfilePreview: View {
    let draft: ResearchActionProfileDraft
    let narrow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draft.buttonName.isEmpty ? "Untitled Action" : draft.buttonName)
                .font(.headline)
            previewRow("Target", "Current Note")
            previewRow("Starting revision", "Verified at preparation")
            ForEach(draft.modules) { module in
                previewRow(module.label, moduleTitle(module.kind))
            }
            Divider()
            previewRow("Permission", "Validated when the Action is prepared")
            previewRow("Checkpoint", "Owned by Scholium when writing is possible")
            previewRow("Conflicts", "Block preparation until resolved")
            previewRow("Recovery", "Retained independently of the Skill")
        }
        .padding(12)
        .frame(maxWidth: narrow ? 340 : 620, alignment: .leading)
        .overlay {
            Rectangle()
                .stroke(ScholiumColorRole.separator.color, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func previewRow(_ label: String, _ value: String) -> some View {
        Group {
            if narrow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption.weight(.medium))
                    Text(value).foregroundStyle(.secondary)
                }
            } else {
                LabeledContent(label, value: value)
            }
        }
        .font(.caption)
    }
}

private struct ResearchSkillInstallationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preparation: ResearchSkillInstallationPreparation
    let triptychs: [TriptychAssignment]
    let activeTriptychID: UUID?
    let install: ([UUID]) async throws -> Void
    let discard: () async -> Void
    @State private var selectedTriptychs: Set<UUID>
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(
        preparation: ResearchSkillInstallationPreparation,
        triptychs: [TriptychAssignment],
        activeTriptychID: UUID?,
        install: @escaping ([UUID]) async throws -> Void,
        discard: @escaping () async -> Void
    ) {
        self.preparation = preparation
        self.triptychs = triptychs
        self.activeTriptychID = activeTriptychID
        self.install = install
        self.discard = discard
        _selectedTriptychs = State(initialValue: Set([activeTriptychID].compactMap { $0 }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            installationHeader
            installationForm
            Label(
                "Installed Skills start disabled. A valid Action Profile and deliberate Show in Actions choice are still required.",
                systemImage: "lock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            installationButtons
        }
        .padding(20)
        .interactiveDismissDisabled()
        .alert("Could Not Install Skill", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("Dismiss", role: .cancel) {} } message: {
            Text(errorMessage ?? "")
        }
    }

    private var installationHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Install Researcher Skill")
                .font(.title2.weight(.semibold))
            Text("Review the exact staged inventory before Scholium creates disabled, independent Triptych copies.")
                .foregroundStyle(.secondary)
        }
    }

    private var installationForm: some View {
        Form {
            Section("Package") {
                LabeledContent("Identifier", value: preparation.packageID)
                LabeledContent("Origin", value: preparation.originDisplayName)
                LabeledContent("Purpose", value: preparation.purpose)
                LabeledContent("Note roles", value: roleDescription)
                LabeledContent("Proposed Actions", value: actionDescription)
            }
            Section("Accepted Files") {
                ForEach(preparation.files) { file in
                    LabeledContent(file.relativePath, value: fileSize(file))
                }
            }
            Section("Install To") {
                ForEach(triptychs) { triptych in
                    Toggle(
                        triptych.triptych.name,
                        isOn: triptychSelection(triptych.id)
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 360)
    }

    private var installationButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) {
                Task { await discard(); dismiss() }
            }
            Button("Install Disabled") {
                isWorking = true
                Task { @MainActor in
                    defer { isWorking = false }
                    do { try await install(Array(selectedTriptychs)); dismiss() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTriptychs.isEmpty || isWorking)
        }
    }

    private var roleDescription: String {
        preparation.applicableRoles.map(roleTitle).joined(separator: ", ")
    }

    private var actionDescription: String {
        preparation.proposedActionIDs.map(actionTitle).joined(separator: ", ")
    }

    private func fileSize(_ file: ResearchSkillInstallationFile) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(file.utf8ByteCount),
            countStyle: .file
        )
    }

    private func triptychSelection(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedTriptychs.contains(id) },
            set: { enabled in
                if enabled { selectedTriptychs.insert(id) }
                else { selectedTriptychs.remove(id) }
            }
        )
    }
}

private struct NewResearcherSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    let save: (NewResearcherSkillDraft) async throws -> Void
    @State private var draft: NewResearcherSkillDraft
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(
        initialDraft: NewResearcherSkillDraft,
        save: @escaping (NewResearcherSkillDraft) async throws -> Void
    ) {
        self.save = save
        _draft = State(initialValue: initialDraft)
    }

    private var isValid: Bool {
        ResearchActionID(researcherOwnedRawValue: draft.actionID) != nil
            && !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.packageID.range(
                of: #"^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$"#,
                options: .regularExpression
            ) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Local Skill").font(.title2.weight(.semibold))
            Text("Create one disabled Triptych-local package and declare its first custom Action identifier. Edit the full method before showing it in Actions.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Package identifier", text: $draft.packageID)
                TextField("Skill name", text: $draft.name)
                TextField("Custom Action identifier", text: $draft.actionID)
                Picker("Execution", selection: $draft.executionKind) {
                    ForEach(ResearchActionExecutionKind.allCases.filter {
                        $0 != .manuscript
                    }, id: \.rawValue) { kind in
                        Text(executionTitle(kind)).tag(kind)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 460)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create Skill") {
                    isWorking = true
                    Task { @MainActor in
                        defer { isWorking = false }
                        do { try await save(draft); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isWorking)
            }
        }
        .padding(20)
        .alert("Could Not Create Skill", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("Dismiss", role: .cancel) {} } message: {
            Text(errorMessage ?? "")
        }
    }
}

private func executionTitle(_ kind: ResearchActionExecutionKind) -> String {
    switch kind {
    case .discussion:
        localizedInterfaceString("Discuss")
    case .analysis:
        localizedInterfaceString("Analyze")
    case .synthesis:
        localizedInterfaceString("Synthesize")
    case .writing:
        localizedInterfaceString("Write")
    case .critique:
        localizedInterfaceString("Critique")
    case .checkFidelity:
        localizedInterfaceString("Check Fidelity")
    case .manuscript:
        localizedInterfaceString("Manuscript")
    }
}

private func moduleTitle(_ kind: ResearchActionModuleKind) -> String {
    switch kind {
    case .notePicker:
        localizedInterfaceString("Note Picker")
    case .passageAnchor:
        localizedInterfaceString("Passage Anchor")
    case .materialSelector:
        localizedInterfaceString("Material Selector")
    case .sourceReference:
        localizedInterfaceString("Source Reference")
    case .boundedText:
        localizedInterfaceString("Bounded Text")
    case .boolean:
        localizedInterfaceString("Toggle")
    case .enumeration:
        localizedInterfaceString("Choices")
    }
}

private func roleTitle(_ role: ResearchActionTargetRole) -> String {
    switch role {
    case .analysis:
        localizedInterfaceString("Analysis")
    case .topic:
        localizedInterfaceString("Topic")
    case .work:
        localizedInterfaceString("Work")
    }
}

private func sourceRequirementTitle(
    _ requirement: ResearchActionSourceRequirement
) -> String {
    switch requirement {
    case .none:
        localizedInterfaceString("None")
    case .optional:
        ScholiumL10n.localized(LocalizedStringResource(
            "Optional", table: "Localizable", bundle: .module
        ))
    case .required:
        localizedInterfaceString("Required")
    }
}

private func feedbackRequirementTitle(
    _ requirement: ResearchActionFeedbackRequirement
) -> String {
    switch requirement {
    case .none:
        localizedInterfaceString("None")
    case .requested:
        ScholiumL10n.localized(LocalizedStringResource(
            "Requested", table: "Localizable", bundle: .module
        ))
    case .required:
        localizedInterfaceString("Required")
    }
}

private func localizedInterfaceString(
    _ keyAndValue: String.LocalizationValue
) -> String {
    ScholiumL10n.string(keyAndValue)
}

private struct ResearchPermissionSettingsPlaceholder: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Permissions",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Action Profiles declare requested capabilities here only as inspectable limits. Standing Triptych and per-Skill policies are not yet stored by this build.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                researchSettingsSection(LocalizedStringResource(
                    "CURRENT BOUNDARY",
                    table: "Localizable",
                    bundle: .module
                )) {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(
                            "Default behavior",
                            value: ScholiumL10n.localized(LocalizedStringResource(
                                "Ask for every additional change",
                                table: "Localizable",
                                bundle: .module
                            ))
                        )
                        Text("This page does not grant reusable authority. Until the standing-permission implementation is complete, every new write scope continues through the existing short-lived authorization boundary.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                researchSettingsSection(LocalizedStringResource(
                    "PLANNED POLICIES",
                    table: "Localizable",
                    bundle: .module
                )) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ask Me Every Time")
                        Text("Ask Me Only for Works")
                        Text("Triptych-wide")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("scholium.researchGuidance.permissions")
    }
}

private struct ResearchSourcesSettingsView: View {
    @State private var citationStatus: ResearchCitationMethodStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Sources & Integrations",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Long-lived source, citation, bibliography, agent-handoff, and command-line configuration lives here. Action-specific source choice remains in the Action sheet.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                AgentCLISettingsView()
                Divider()
                ZoteroSettingsView()
                Divider()
                ResearchCitationMethodSettingsView { citationStatus = $0 }
                Divider()
                RecommendedBibliographyMethodSettingsView()
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("scholium.researchGuidance.sources")
    }
}

private struct ResearchRecoverySettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var listing = ResearchSkillMaintenanceSnapshotListing(
        snapshots: [],
        issues: []
    )
    @State private var skills: [ResearchSkillPackage] = []
    @State private var pendingRestore: ResearchSkillMaintenanceSnapshot?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Recovery & Technical",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Inspect machine-local Skill recovery snapshots and reveal portable or legacy files without projecting legacy guidance into current Actions.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                researchSettingsSection(LocalizedStringResource(
                    "SKILL RECOVERY",
                    table: "Localizable",
                    bundle: .module
                )) {
                    if listing.snapshots.isEmpty {
                        Text("No Skill recovery snapshots are available.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(listing.snapshots) { snapshot in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: snapshot.packageID)
                                        Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Restore…") { pendingRestore = snapshot }
                                        .disabled(isWorking)
                                }
                                .frame(minHeight: 40)
                                Divider()
                            }
                        }
                    }
                    ForEach(listing.issues, id: \.id) { issue in
                        Label(issue.summary, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(ScholiumColorRole.attention.color)
                    }
                }
                researchSettingsSection(LocalizedStringResource(
                    "FILES",
                    table: "Localizable",
                    bundle: .module
                )) {
                    HStack {
                        Button("Reveal Skills Folder") { revealSkillsFolder() }
                        Button("Reveal Legacy Data") { revealLegacyData() }
                    }
                    Text("Legacy files remain byte-unchanged and cannot authorize a current Action.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .disabled(loadedTriptychID != settingsModel.activeTriptychServicesID)
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .confirmationDialog(
            "Restore Complete Skill Package?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Complete Package") { restoreSnapshot() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Scholium rechecks the current package revision and creates an undo snapshot before replacement when possible.")
        }
        .alert("Recovery Operation Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("Dismiss", role: .cancel) {} } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() async {
        guard let requestedTriptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            listing = ResearchSkillMaintenanceSnapshotListing(snapshots: [], issues: [])
            skills = []
            pendingRestore = nil
            return
        }
        loadedTriptychID = nil
        pendingRestore = nil
        do {
            async let loadedListing = settingsModel.researchSkillMaintenanceSnapshots()
            async let loadedSkills = settingsModel.researchSkills()
            let (newListing, newSkills) = try await (loadedListing, loadedSkills)
            try Task.checkCancellation()
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            listing = newListing
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

    private func restoreSnapshot() {
        guard let snapshot = pendingRestore else { return }
        pendingRestore = nil
        let current = skills.first {
            $0.origin == .triptych && $0.id == snapshot.packageID
        }
        let expectedState: ResearchSkillMaintenanceExpectedCurrentState
        if let revision = current?.revision {
            expectedState = .present(revision)
        } else {
            expectedState = .missing
        }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await settingsModel.restoreResearchSkillMaintenance(
                    snapshotID: snapshot.id,
                    expectedCurrentState: expectedState
                )
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func revealSkillsFolder() {
        Task { @MainActor in
            do { settingsModel.openExternal(try await settingsModel.researchSkillsURL()) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func revealLegacyData() {
        Task { @MainActor in
            do {
                let skillsURL = try await settingsModel.researchSkillsURL()
                settingsModel.openExternal(skillsURL.deletingLastPathComponent())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
