import ScholiumContracts
import SwiftUI

private struct ResearchAcademicProfileEditorContext: Identifiable {
    let profile: ResearchAcademicActionProfile
    let document: ResearchAcademicProfileDocument
    let expectedRevision: DocumentFingerprint

    var id: ResearchActionID { profile.actionID }
}

/// Edits only the academic input and result shape of Actions. Permission and
/// Skill entry and ordinary reference sources remain with their existing owners.
struct ActionProfilesSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var profiles: ResearchAcademicProfileSnapshot?
    @State private var profileEditor: ResearchAcademicProfileEditorContext?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Action Profiles",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Configure the academic input and result fields presented by each Action.",
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
                    "BOUNDARY",
                    table: "Localizable",
                    bundle: .module
                )) {
                    Text("Action Profiles shape academic inputs and results; they never grant authority or alter Session, write, revision, conflict, or recovery rules.")
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 760, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.researchGuidance.actionProfiles")
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
        .alert("Could Not Update Action Profiles", isPresented: Binding(
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
        researchSettingsCollectionRow {
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
        } actions: {
            VStack(alignment: .trailing, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Toggle("Enabled", isOn: Binding(
                    get: { profile.isEnabled },
                    set: { saveProfileEnabled($0, profile: profile, snapshot: snapshot) }
                ))
                .toggleStyle(.switch)
                .accessibilityIdentifier(
                    "scholium.researchGuidance.profile.\(profile.actionID.rawValue).enabled"
                )
                HStack(spacing: ScholiumMetrics.ResearchGuidance.controlSpacing) {
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
        .accessibilityElement(children: .contain)
    }

    @MainActor
    private func reload() async {
        guard let triptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            profiles = nil
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await settingsModel.academicActionProfiles()
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            profiles = result
            loadedTriptychID = triptychID
            errorMessage = nil
        } catch {
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            profiles = nil
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
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchGuidance.editorSectionSpacing) {
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
                VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchGuidance.editorMajorSectionSpacing) {
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
        .padding(ScholiumMetrics.ResearchGuidance.editorContentInset)
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
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchGuidance.summarySpacing) {
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
                Spacer(minLength: ScholiumMetrics.ResearchGuidance.trailingControlMinimumSpacing)
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
                VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchGuidance.controlSpacing) {
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
        .padding(.vertical, ScholiumMetrics.ResearchGuidance.controlSpacing)
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
