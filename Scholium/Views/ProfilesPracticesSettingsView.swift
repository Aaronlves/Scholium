import ScholiumContracts
import SwiftUI

private struct ResearchPracticeEditorContext: Identifiable {
    let practice: ResearchPracticeSnapshot

    var id: String { practice.relativePath }
}

private struct NewResearchPracticeContext: Identifiable {
    let id = UUID()
}

private struct ResearchAcademicProfileEditorContext: Identifiable {
    let profile: ResearchAcademicActionProfile
    let document: ResearchAcademicProfileDocument
    let expectedRevision: DocumentFingerprint

    var id: ResearchActionID { profile.actionID }
}

/// Edits the academic shape of Actions and the exact Markdown Practices linked
/// from primary Methods. Neither surface grants Agent authority or introduces a
/// second Skill/package owner.
struct ProfilesPracticesSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var profiles: ResearchAcademicProfileSnapshot?
    @State private var practices: [ResearchPracticeSnapshot] = []
    @State private var profileEditor: ResearchAcademicProfileEditorContext?
    @State private var practiceEditor: ResearchPracticeEditorContext?
    @State private var newPractice: NewResearchPracticeContext?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Profiles & Practices",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Profiles define each Action's researcher-facing academic fields. Practices are exact Markdown linked from a primary Method; they guide research but never grant authority.",
                        table: "Localizable",
                        bundle: .module
                    )
                )

                researchSettingsSection(LocalizedStringResource(
                    "ACADEMIC PROFILES",
                    table: "Localizable",
                    bundle: .module
                )) {
                    if let profiles {
                        VStack(spacing: 0) {
                            ForEach(profiles.document.profiles) { profile in
                                profileRow(profile, snapshot: profiles)
                                if profile.id != profiles.document.profiles.last?.id {
                                    Divider()
                                }
                            }
                        }
                    } else if isWorking {
                        ScholiumContentStateView(
                            "Loading Profiles…",
                            indicator: .progress,
                            placement: .leading,
                            density: .compact
                        )
                    } else {
                        ScholiumContentStateView(
                            "Profiles Unavailable",
                            detail: Text(errorMessage ?? "Open a complete Triptych."),
                            indicator: .symbol(
                                "rectangle.and.pencil.and.ellipsis",
                                role: .attention
                            ),
                            placement: .leading,
                            density: .compact
                        )
                    }
                }

                researchSettingsSection(LocalizedStringResource(
                    "PHILOSOPHICAL PRACTICES",
                    table: "Localizable",
                    bundle: .module
                )) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Methods opt into Practices only through exact Wikilinks.")
                                .font(ScholiumTypography.interface(.body))
                                .scholiumForeground(.secondaryText)
                            Spacer()
                            Button("New Practice…") {
                                newPractice = NewResearchPracticeContext()
                            }
                        }
                        if practices.isEmpty {
                            ScholiumContentStateView(
                                "No Practices",
                                detail: Text("Create an exact Markdown Practice, then link it from a Method."),
                                indicator: .symbol("doc.text"),
                                placement: .leading,
                                density: .compact
                            )
                            .frame(maxWidth: .infinity, minHeight: 150)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(practices) { practice in
                                    practiceRow(practice)
                                    if practice.id != practices.last?.id { Divider() }
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
                    Text("Profiles and Practices can shape scholarly work and truthful Result fields. They cannot change Platform Actions, Research Context ownership, Session lifetime, collaboration policy, a Bounded Write Set, exact revisions, conflicts, or recovery.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("scholium.researchGuidance.profilesPractices")
        .disabled(
            loadedTriptychID != settingsModel.activeTriptychServicesID
                || isWorking
        )
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .sheet(item: $profileEditor) { context in
            ResearchAcademicProfileEditor(profile: context.profile) { profile in
                let document = try ResearchAcademicProfileDocument(
                    profiles: context.document.profiles.map {
                        $0.actionID == profile.actionID ? profile : $0
                    }
                )
                _ = try await settingsModel.saveAcademicActionProfiles(
                    document,
                    expectedRevision: context.expectedRevision
                )
                await reload()
            }
        }
        .sheet(item: $practiceEditor) { context in
            ResearchPracticeSourceEditor(context: context) { source in
                _ = try await settingsModel.savePhilosophicalPractice(
                    relativePath: context.practice.relativePath,
                    source: source,
                    expectedRevision: context.practice.revision
                )
                await reload()
            } restorePrevious: {
                _ = try await settingsModel.restorePreviousPhilosophicalPractice(
                    relativePath: context.practice.relativePath,
                    expectedRevision: context.practice.revision
                )
                await reload()
            }
        }
        .sheet(item: $newPractice) { _ in
            NewResearchPracticeEditor { title, source in
                _ = try await settingsModel.createPhilosophicalPractice(
                    title: title,
                    source: source
                )
                await reload()
            }
        }
        .alert("Could Not Update Profiles & Practices", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func profileRow(
        _ profile: ResearchAcademicActionProfile,
        snapshot: ResearchAcademicProfileSnapshot
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(profile.displayName)
                    .font(ScholiumTypography.interface(.rowTitle))
                LabeledContent(
                    "Academic Inputs",
                    value: "\(profile.academicInputFields.count)"
                )
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                LabeledContent(
                    "Academic Results",
                    value: "\(profile.academicResultFields.count)"
                )
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                Text("Roles: \(profile.applicableRoles.map(\.rawValue).joined(separator: ", "))")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Toggle("Enabled", isOn: Binding(
                    get: { profile.isEnabled },
                    set: { saveProfileEnabled($0, profile: profile, snapshot: snapshot) }
                ))
                .toggleStyle(.switch)
                .accessibilityIdentifier(
                    "scholium.researchGuidance.profile.\(profile.actionID.rawValue).enabled"
                )
                HStack(spacing: 6) {
                    Button {
                        moveProfile(profile, by: -1, snapshot: snapshot)
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(!canMoveProfile(profile, by: -1, snapshot: snapshot))
                    .help("Move Profile Earlier")
                    Button {
                        moveProfile(profile, by: 1, snapshot: snapshot)
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(!canMoveProfile(profile, by: 1, snapshot: snapshot))
                    .help("Move Profile Later")
                    Button("Edit Profile…") {
                        profileEditor = ResearchAcademicProfileEditorContext(
                            profile: profile,
                            document: snapshot.document,
                            expectedRevision: snapshot.revision
                        )
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func practiceRow(_ practice: ResearchPracticeSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(practice.title)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(practice.relativePath)
                    .font(ScholiumTypography.exact(.small))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Button("Edit…") {
                practiceEditor = ResearchPracticeEditorContext(practice: practice)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchGuidance.practice.\(practice.id)")
    }

    @MainActor
    private func reload() async {
        guard let triptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            profiles = nil
            practices = []
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            async let loadedProfiles = settingsModel.academicActionProfiles()
            async let loadedPractices = settingsModel.philosophicalPractices()
            let result = try await (loadedProfiles, loadedPractices)
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            profiles = result.0
            practices = result.1.sorted {
                $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            loadedTriptychID = triptychID
            errorMessage = nil
        } catch {
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            profiles = nil
            practices = []
            loadedTriptychID = triptychID
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfileEnabled(
        _ enabled: Bool,
        profile: ResearchAcademicActionProfile,
        snapshot: ResearchAcademicProfileSnapshot
    ) {
        performProfileMutation(snapshot: snapshot) {
            try ResearchAcademicActionProfile(
                actionID: profile.actionID,
                displayName: profile.displayName,
                order: profile.order,
                isEnabled: enabled,
                applicableRoles: profile.applicableRoles,
                academicInputFields: profile.academicInputFields,
                academicResultFields: profile.academicResultFields
            )
        }
    }

    private func moveProfile(
        _ profile: ResearchAcademicActionProfile,
        by offset: Int,
        snapshot: ResearchAcademicProfileSnapshot
    ) {
        var ordered = snapshot.document.profiles
        guard let source = ordered.firstIndex(where: {
            $0.actionID == profile.actionID
        }) else { return }
        let destination = source + offset
        guard ordered.indices.contains(destination) else { return }
        ordered.swapAt(source, destination)
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let reindexed = try ordered.enumerated().map { index, profile in
                    try ResearchAcademicActionProfile(
                        actionID: profile.actionID,
                        displayName: profile.displayName,
                        order: index,
                        isEnabled: profile.isEnabled,
                        applicableRoles: profile.applicableRoles,
                        academicInputFields: profile.academicInputFields,
                        academicResultFields: profile.academicResultFields
                    )
                }
                _ = try await settingsModel.saveAcademicActionProfiles(
                    ResearchAcademicProfileDocument(profiles: reindexed),
                    expectedRevision: snapshot.revision
                )
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func canMoveProfile(
        _ profile: ResearchAcademicActionProfile,
        by offset: Int,
        snapshot: ResearchAcademicProfileSnapshot
    ) -> Bool {
        guard !isWorking,
              let index = snapshot.document.profiles.firstIndex(where: {
                  $0.actionID == profile.actionID
              }) else { return false }
        return snapshot.document.profiles.indices.contains(index + offset)
    }

    private func performProfileMutation(
        snapshot: ResearchAcademicProfileSnapshot,
        replacement: @escaping () throws -> ResearchAcademicActionProfile
    ) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let replacement = try replacement()
                let document = try ResearchAcademicProfileDocument(
                    profiles: snapshot.document.profiles.map {
                        $0.actionID == replacement.actionID ? replacement : $0
                    }
                )
                _ = try await settingsModel.saveAcademicActionProfiles(
                    document,
                    expectedRevision: snapshot.revision
                )
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ResearchAcademicProfileEditor: View {
    let profile: ResearchAcademicActionProfile
    let save: (ResearchAcademicActionProfile) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var isEnabled: Bool
    @State private var applicableRoles: Set<ResearchActionTargetRole>
    @State private var academicInputFields: [ResearchAcademicFieldDraft]
    @State private var academicResultFields: [ResearchAcademicFieldDraft]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        profile: ResearchAcademicActionProfile,
        save: @escaping (ResearchAcademicActionProfile) async throws -> Void
    ) {
        self.profile = profile
        self.save = save
        _displayName = State(initialValue: profile.displayName)
        _isEnabled = State(initialValue: profile.isEnabled)
        _applicableRoles = State(initialValue: Set(profile.applicableRoles))
        _academicInputFields = State(initialValue: profile.academicInputFields.map(
            ResearchAcademicFieldDraft.init
        ))
        _academicResultFields = State(initialValue: profile.academicResultFields.map(
            ResearchAcademicFieldDraft.init
        ))
    }

    private var allowedRoles: [ResearchActionTargetRole] {
        PlatformActionCatalog.definition(for: profile.actionID)?.allowedTargetRoles
            ?? profile.applicableRoles
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text("Edit Academic Profile")
                        .font(ScholiumTypography.interface(.primaryTitle))
                    Text(actionTitle(profile.actionID))
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                }
                Spacer()
                Toggle("Enabled", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            Text("Configure only researcher-facing academic fields. Platform selectors, machine facts, permissions, write scope, and recovery are not Profile fields.")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Text("PROFILE")
                            .font(ScholiumTypography.interface(.small, emphasis: .strong))
                            .scholiumForeground(.secondaryText)
                            .accessibilityAddTraits(.isHeader)
                        TextField("Profile Name", text: $displayName)
                        Text("Applicable Roles")
                            .font(ScholiumTypography.interface(.sectionTitle))
                        HStack(spacing: ScholiumGrid.Spacing.sectionSeparation) {
                            ForEach(allowedRoles, id: \.self) { role in
                                Toggle(
                                    role.rawValue.capitalized,
                                    isOn: roleBinding(role)
                                )
                                .toggleStyle(.checkbox)
                            }
                        }
                    }

                    Divider()
                    ResearchAcademicFieldsEditor(
                        title: "Academic Inputs",
                        fields: $academicInputFields
                    )
                    Divider()
                    ResearchAcademicFieldsEditor(
                        title: "Academic Results",
                        fields: $academicResultFields
                    )
                }
                .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.attention)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                if isSaving {
                    ProgressView().controlSize(.small)
                }
                Button("Save Profile") { saveDraft() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
        }
        .padding(18)
        .frame(minWidth: 760, idealWidth: 820, minHeight: 620, idealHeight: 720)
        .disabled(isSaving)
    }

    private func roleBinding(_ role: ResearchActionTargetRole) -> Binding<Bool> {
        Binding(
            get: { applicableRoles.contains(role) },
            set: { selected in
                if selected {
                    applicableRoles.insert(role)
                } else {
                    applicableRoles.remove(role)
                }
            }
        )
    }

    private func saveDraft() {
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let replacement = try ResearchAcademicActionProfile(
                    actionID: profile.actionID,
                    displayName: displayName,
                    order: profile.order,
                    isEnabled: isEnabled,
                    applicableRoles: allowedRoles.filter(applicableRoles.contains),
                    academicInputFields: try academicInputFields.map {
                        try $0.definition
                    },
                    academicResultFields: try academicResultFields.map {
                        try $0.definition
                    }
                )
                try await save(replacement)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct ResearchAcademicFieldsEditor: View {
    let title: LocalizedStringKey
    @Binding var fields: [ResearchAcademicFieldDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(ScholiumTypography.interface(.sectionTitle))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Add Field") {
                    guard fields.count < 24 else { return }
                    fields.append(ResearchAcademicFieldDraft())
                }
                .disabled(fields.count >= 24)
            }
            if fields.isEmpty {
                Text("No academic fields are included in this section.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
            }
            ForEach($fields) { $field in
                ResearchAcademicFieldDraftEditor(
                    field: $field,
                    canMoveEarlier: fields.first?.id != field.id,
                    canMoveLater: fields.last?.id != field.id,
                    moveEarlier: { move(field.id, by: -1) },
                    moveLater: { move(field.id, by: 1) },
                    remove: { fields.removeAll { $0.id == field.id } }
                )
                if fields.last?.id != field.id { Divider() }
            }
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let source = fields.firstIndex(where: { $0.id == id }) else {
            return
        }
        let destination = source + offset
        guard fields.indices.contains(destination) else { return }
        fields.swapAt(source, destination)
    }
}

private struct ResearchAcademicFieldDraftEditor: View {
    @Binding var field: ResearchAcademicFieldDraft
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let moveEarlier: () -> Void
    let moveLater: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack {
                TextField("Field Name", text: $field.label)
                    .font(ScholiumTypography.interface(.rowTitle))
                Spacer(minLength: 12)
                Button(action: moveEarlier) {
                    Image(systemName: "arrow.up")
                }
                .disabled(!canMoveEarlier)
                .help("Move Field Earlier")
                Button(action: moveLater) {
                    Image(systemName: "arrow.down")
                }
                .disabled(!canMoveLater)
                .help("Move Field Later")
                Button(role: .destructive, action: remove) {
                    Image(systemName: "trash")
                }
                .help("Remove Field")
            }
            HStack {
                Picker("Field Type", selection: $field.kind) {
                    Text("Free Text").tag(ResearchAcademicFieldKind.freeText)
                    Text("Single Choice").tag(
                        ResearchAcademicFieldKind.singleChoice
                    )
                    Text("Multiple Choice").tag(
                        ResearchAcademicFieldKind.multipleChoice
                    )
                }
                Picker("Requirement", selection: $field.requirement) {
                    Text("Not Included").tag(
                        ResearchAcademicFieldRequirement.excluded
                    )
                    Text("Optional").tag(
                        ResearchAcademicFieldRequirement.optional
                    )
                    Text("Required").tag(
                        ResearchAcademicFieldRequirement.required
                    )
                }
            }
            TextField("Help Text (Optional)", text: $field.helpText)
            if field.kind != .freeText {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Closed Options")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumForeground(.secondaryText)
                    ForEach($field.choices) { $choice in
                        HStack {
                            TextField("Option Name", text: $choice.label)
                            Button(role: .destructive) {
                                field.choices.removeAll { $0.id == choice.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .disabled(field.choices.count <= 2)
                            .help("Remove Option")
                        }
                    }
                    Button("Add Option") {
                        guard field.choices.count < 32 else { return }
                        field.choices.append(ResearchAcademicChoiceDraft())
                    }
                    .disabled(field.choices.count >= 32)
                }
            }
        }
        .padding(.vertical, 6)
        .onChange(of: field.kind) { _, kind in
            if kind != .freeText {
                while field.choices.count < 2 {
                    field.choices.append(ResearchAcademicChoiceDraft())
                }
            }
        }
    }
}

private struct ResearchAcademicChoiceDraft: Identifiable {
    let id: UUID
    let originalValue: String?
    var label: String

    init(_ choice: ResearchAcademicChoice) {
        id = UUID()
        originalValue = choice.value
        label = choice.label
    }

    init() {
        id = UUID()
        originalValue = nil
        label = "New Option"
    }
}

private struct ResearchAcademicFieldDraft: Identifiable {
    let id: UUID
    let fieldID: ResearchAcademicFieldID
    var kind: ResearchAcademicFieldKind
    var label: String
    var helpText: String
    var requirement: ResearchAcademicFieldRequirement
    var choices: [ResearchAcademicChoiceDraft]
    var maximumTextUTF8Count: Int

    init(_ field: ResearchAcademicFieldDefinition) {
        id = UUID()
        fieldID = field.fieldID
        kind = field.kind
        label = field.label
        helpText = field.helpText ?? ""
        requirement = field.requirement
        choices = field.choices.map(ResearchAcademicChoiceDraft.init)
        maximumTextUTF8Count = field.maximumTextUTF8Count ?? 65_536
    }

    init() {
        let identifier = UUID()
        id = identifier
        fieldID = ResearchAcademicFieldID(
            rawValue: "field-\(identifier.uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))"
        )!
        kind = .freeText
        label = "New Field"
        helpText = ""
        requirement = .optional
        choices = []
        maximumTextUTF8Count = 65_536
    }

    var definition: ResearchAcademicFieldDefinition {
        get throws {
            let help = helpText.trimmingCharacters(in: .whitespacesAndNewlines)
            switch kind {
            case .freeText:
                return try .freeText(
                    id: fieldID,
                    label: label,
                    helpText: help.isEmpty ? nil : help,
                    requirement: requirement,
                    maximumTextUTF8Count: maximumTextUTF8Count
                )
            case .singleChoice:
                return try .singleChoice(
                    id: fieldID,
                    label: label,
                    helpText: help.isEmpty ? nil : help,
                    requirement: requirement,
                    choices: try resolvedChoices()
                )
            case .multipleChoice:
                return try .multipleChoice(
                    id: fieldID,
                    label: label,
                    helpText: help.isEmpty ? nil : help,
                    requirement: requirement,
                    choices: try resolvedChoices()
                )
            }
        }
    }

    private func resolvedChoices() throws -> [ResearchAcademicChoice] {
        var used = Set(choices.compactMap(\.originalValue))
        return try choices.enumerated().map { index, draft in
            let value: String
            if let original = draft.originalValue {
                value = original
            } else {
                let base = Self.identifierBase(draft.label, fallback: index + 1)
                var candidate = base
                var suffix = 2
                while used.contains(candidate) {
                    candidate = "\(base)-\(suffix)"
                    suffix += 1
                }
                value = candidate
                used.insert(candidate)
            }
            return try ResearchAcademicChoice(value: value, label: draft.label)
        }
    }

    private static func identifierBase(_ text: String, fallback: Int) -> String {
        let lowered = text.lowercased()
        var result = ""
        var needsSeparator = false
        for scalar in lowered.unicodeScalars {
            let isLetter = (97...122).contains(Int(scalar.value))
            let isDigit = (48...57).contains(Int(scalar.value))
            if isLetter || isDigit {
                if needsSeparator, !result.isEmpty { result.append("-") }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        if result.first?.isNumber == true { result = "option-\(result)" }
        return result.isEmpty ? "option-\(fallback)" : result
    }
}

private struct ResearchPracticeSourceEditor: View {
    let context: ResearchPracticeEditorContext
    let save: (String) async throws -> Void
    let restorePrevious: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: String
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(
        context: ResearchPracticeEditorContext,
        save: @escaping (String) async throws -> Void,
        restorePrevious: @escaping () async throws -> Void
    ) {
        self.context = context
        self.save = save
        self.restorePrevious = restorePrevious
        _source = State(initialValue: context.practice.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit \(context.practice.title)")
                .font(ScholiumTypography.interface(.primaryTitle))
            Text("This is exact Markdown. Saving replaces only this Practice; one previous edit remains recoverable.")
                .scholiumForeground(.secondaryText)
            TextEditor(text: $source)
                .font(ScholiumTypography.exact(.body))
                .frame(minWidth: 700, minHeight: 460)
                .accessibilityLabel("Philosophical Practice Markdown")
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .scholiumForeground(.attention)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Restore Previous Edit") { perform(restorePrevious) }
                    .disabled(isWorking)
                Spacer()
                Button("Save") { perform { try await save(source) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || source == context.practice.source)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(minWidth: 740, minHeight: 560)
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await operation()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct NewResearchPracticeEditor: View {
    let create: (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var source = "# Practice\n\nState the philosophical practice here.\n"
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Philosophical Practice")
                .font(ScholiumTypography.interface(.primaryTitle))
            Text("Scholium creates one ordinary Markdown document. Link its title exactly from a primary Method to include it in Research Context.")
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Practice title", text: $title)
            TextEditor(text: $source)
                .font(ScholiumTypography.exact(.body))
                .frame(minWidth: 700, minHeight: 410)
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
                            try await create(title, source)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isCreating
                        || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(minWidth: 740, minHeight: 540)
    }
}
