import ScholiumContracts
import SwiftUI

// MARK: - Managed Metadata Editor

private struct CreatorDraft: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Hashable {
        case person
        case organization
    }

    let id: UUID
    var kind: Kind
    var family: String
    var given: String
    var suffix: String
    var nonDroppingParticle: String
    var droppingParticle: String
    var literal: String

    init(
        id: UUID = UUID(),
        kind: Kind = .person,
        family: String = "",
        given: String = "",
        suffix: String = "",
        nonDroppingParticle: String = "",
        droppingParticle: String = "",
        literal: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.family = family
        self.given = given
        self.suffix = suffix
        self.nonDroppingParticle = nonDroppingParticle
        self.droppingParticle = droppingParticle
        self.literal = literal
    }

    init?(value: YAMLValue) {
        guard case .object(let mapping) = value else { return nil }
        id = UUID()
        if case .string(let literal)? = mapping["literal"] {
            kind = .organization
            self.literal = literal
            family = ""; given = ""; suffix = ""
            nonDroppingParticle = ""; droppingParticle = ""
        } else {
            kind = .person
            literal = ""
            family = mapping["family"]?.displayScalar ?? ""
            given = mapping["given"]?.displayScalar ?? ""
            suffix = mapping["suffix"]?.displayScalar ?? ""
            nonDroppingParticle = mapping["non_dropping_particle"]?.displayScalar ?? ""
            droppingParticle = mapping["dropping_particle"]?.displayScalar ?? ""
        }
    }

    var yamlValue: YAMLValue {
        switch kind {
        case .organization:
            return .object(["literal": .string(literal)])
        case .person:
            var value: [String: YAMLValue] = [
                "family": .string(family)
            ]
            for (key, text) in [
                ("given", given),
                ("suffix", suffix),
                ("non_dropping_particle", nonDroppingParticle),
                ("dropping_particle", droppingParticle),
            ] {
                if !text.isEmpty { value[key] = .string(text) }
            }
            return .object(value)
        }
    }
}

/// Schema-aware sheet for editing one portable Scholium metadata record.
struct MetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let initialExpectedRevision: DocumentFingerprint?
    let metadataCatalog: NoteMetadataCatalog
    let onClose: (@MainActor () -> Void)?
    let reload: (@MainActor () async throws -> (
        note: WindowDocumentLocation,
        revision: DocumentFingerprint?
    ))?
    let save: @MainActor (
        [String: YAMLValue],
        DocumentFingerprint?
    ) async throws -> Void

    @State private var note: WindowDocumentLocation
    @State private var fieldValues: [String: String] = [:]
    @State private var originalFieldValues: [String: String] = [:]
    @State private var fieldErrors: [String: String] = [:]
    @State private var tagInput: String = ""
    @State private var isSaving = false
    @State private var expectedRevision: DocumentFingerprint?
    @State private var saveError: String?
    @State private var showAvailableProperties = false
    @State private var selectedNewFieldKeys: Set<String> = []
    @State private var removedFieldKeys: Set<String> = []
    @State private var creatorValues: [String: [CreatorDraft]] = [:]
    @State private var originalCreatorValues: [String: [CreatorDraft]] = [:]
    @State private var listValues: [String: [String]] = [:]
    @State private var originalListValues: [String: [String]] = [:]
    @State private var pendingChooserFieldFocus: String?
    @State private var hoveredFieldKey: String?
    @State private var revisionConflict = false
    @State private var isReloading = false
    @FocusState private var focusedFieldKey: String?
    @FocusState private var addPropertyButtonIsFocused: Bool

    init(
        note: WindowDocumentLocation,
        metadataCatalog: NoteMetadataCatalog,
        expectedRevision: DocumentFingerprint? = nil,
        onClose: (@MainActor () -> Void)? = nil,
        reload: (@MainActor () async throws -> (
            note: WindowDocumentLocation,
            revision: DocumentFingerprint?
        ))? = nil,
        save: @escaping @MainActor (
            [String: YAMLValue],
            DocumentFingerprint?
        ) async throws -> Void
    ) {
        self.note = note
        _note = State(initialValue: note)
        self.metadataCatalog = metadataCatalog
        self.initialExpectedRevision = expectedRevision
        self.onClose = onClose
        self.reload = reload
        self.save = save
    }

    private var editorModel: PropertyEditorModel {
        PropertyEditorModel(
            note: note,
            metadataCatalog: metadataCatalog,
            analysisSourceTypeOverride: fieldValues["type"].flatMap(AnalysisSourceType.init)
        )
    }

    private var presentFields: [PropertyEditorField] { editorModel.presentFields }

    private var availableFields: [PropertyEditorField] { editorModel.availableFields }

    private var allFields: [PropertyEditorField] {
        let selected = selectedNewFieldKeys.compactMap {
            editorModel.canonicalField(for: $0)
        }
            .sorted {
                ($0.group.order, $0.presentation.order)
                    < ($1.group.order, $1.presentation.order)
            }
        return presentFields + selected
    }

    private var groupedPresentFields: [(group: PropertyPresentationGroup, fields: [PropertyEditorField])] {
        let grouped = Dictionary(grouping: allFields, by: \.group)
        return PropertyPresentationCatalog.orderedGroups(for: note.schemaProfile).compactMap {
            group in
            guard let fields = grouped[group], !fields.isEmpty else { return nil }
            return (group, fields)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                    Text("Metadata")
                        .font(ScholiumTypography.interface(.primaryTitle))
                    Text(note.title ?? note.displayName)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }
                Spacer()
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Button("Cancel") { closeEditor() }
                        .scholiumActivationPointer()
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut(.escape)
                    Button {
                        saveChanges()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Text("Save")
                        }
                    }
                    .scholiumActivationPointer()
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(ScholiumColorRole.accent.color)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isSaving || !canSaveDraft || revisionConflict)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)

            Divider()

            propertiesContent

            if revisionConflict {
                Divider()
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text("This Note's metadata changed through another participant. Your draft was preserved and cannot replace the newer revision.")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Button("Discard Draft and Reload Current Note") {
                            reloadCurrentNote()
                        }
                        .scholiumActivationPointer()
                        .disabled(isReloading || reload == nil)
                    }
                }
                .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }

            // Footer with validation summary
            if !displayedFieldErrors.isEmpty {
                Divider()

                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scholiumForeground(.destructive)
                        .font(ScholiumTypography.interface(.small))
                    Text("\(displayedFieldErrors.count) validation error\(displayedFieldErrors.count == 1 ? "" : "s")")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.destructive)
                    Spacer()
                }
                .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }
        }
        .scholiumSurface(.boundedPanel)
        .disabled(isSaving)
        .accessibilityIdentifier("scholium.metadataEditor")
        .task {
            installDraft(note: note, revision: initialExpectedRevision)
        }
        .sheet(isPresented: $showAvailableProperties, onDismiss: restoreChooserFocus) {
            PropertyChooserView(
                model: editorModel,
                excludedKeys: selectedNewFieldKeys,
                select: selectNewField
            )
        }
        .alert("Could Not Save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { saveError = nil }
            .scholiumActivationPointer()
        } message: {
            Text(saveError ?? "")
        }
        .interactiveDismissDisabled(hasDraftChanges || isSaving)
    }

    @ViewBuilder
    private var propertiesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if allFields.isEmpty {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        Text("No managed metadata yet.")
                            .font(ScholiumTypography.interface(.body))
                        Text("Add only the fields useful for this Note. Markdown and YAML remain unchanged.")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                }

                ForEach(Array(groupedPresentFields.enumerated()), id: \.element.group) { index, group in
                    ScholiumPropertyGroup(
                        label: group.group.label,
                        separatesFromPrevious: index > 0
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumMetrics.Properties.fieldBlockSeparation
                        ) {
                            ForEach(group.fields) { field in
                                fieldEditor(for: field)
                            }
                        }
                    }
                }

                if !availableFields.isEmpty {
                    Button("Add a Field…") {
                        showAvailableProperties = true
                    }
                    .scholiumActivationPointer()
                    .focused($addPropertyButtonIsFocused)
                    .accessibilityIdentifier("scholium.metadataEditor.addField")
                    .accessibilityHint("Chooses a managed field without changing Markdown or YAML")
                    .padding(
                        .top,
                        allFields.isEmpty
                            ? ScholiumGrid.Spacing.inlineControlGap
                            : ScholiumMetrics.Properties.semanticGroupSeparation
                    )
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
        }
    }

    private struct DraftCandidate {
        let fields: [String: YAMLValue]
        let changedKeys: Set<String>
    }

    private var hasDraftChanges: Bool {
        !removedFieldKeys.isEmpty || !selectedNewFieldKeys.isEmpty
            || allFields.contains(where: fieldHasDraftChange)
    }

    private var draftCandidate: DraftCandidate {
        var proposed = note.managedMetadataFields
        var changedKeys = removedFieldKeys
        for key in removedFieldKeys { proposed.removeValue(forKey: key) }

        for field in allFields where fieldHasDraftChange(field) {
            changedKeys.insert(field.key)
            if field.valueKind == .creatorList {
                proposed = editorModel.updating(
                    proposed,
                    field: field,
                    value: .array((creatorValues[field.key] ?? []).map(\.yamlValue))
                )
            } else if field.valueKind == .textList || field.valueKind == .tags {
                proposed = editorModel.updating(
                    proposed,
                    field: field,
                    value: .array((listValues[field.key] ?? []).map(YAMLValue.string))
                )
            } else if let text = fieldValues[field.key] {
                proposed = editorModel.updating(proposed, field: field, text: text)
            }
        }
        return DraftCandidate(fields: proposed, changedKeys: changedKeys)
    }

    private var liveFieldErrors: [String: String] {
        var errors: [String: String] = [:]
        for field in allFields where selectedNewFieldKeys.contains(field.key)
            && !field.isTypicalForSourceType {
            errors[field.key] = String(
                localized: "This field is not applicable to the selected Source Type.",
                table: "Localizable",
                bundle: .module
            )
        }
        let candidate = draftCandidate
        for issue in editorModel.validationIssues(
            proposedFields: candidate.fields,
            changedKeys: candidate.changedKeys
        ) {
            if let key = issue.propertyKey {
                errors[key] = localizedValidationMessage(for: issue)
            }
        }
        return errors
    }

    private func localizedValidationMessage(
        for issue: PropertyValidationIssue
    ) -> String {
        switch issue.code {
        case .malformedFrontmatter:
            String(localized: "The stored metadata record is unavailable.", table: "Localizable", bundle: .module)
        case .invalidValueKind:
            String(localized: "This value does not match the field's required shape.", table: "Localizable", bundle: .module)
        case .valueNotAllowed:
            String(localized: "Choose an allowed value for this field.", table: "Localizable", bundle: .module)
        case .invalidCreator:
            String(localized: "Each creator needs a family name or an organization name.", table: "Localizable", bundle: .module)
        }
    }

    private var displayedFieldErrors: [String: String] {
        liveFieldErrors.merging(fieldErrors) { _, savedError in savedError }
    }

    private var canSaveDraft: Bool {
        hasDraftChanges
            && !revisionConflict
            && displayedFieldErrors.isEmpty
    }

    private func fieldHasDraftChange(_ field: PropertyEditorField) -> Bool {
        guard !removedFieldKeys.contains(field.key), !field.isReadOnly else { return false }
        if selectedNewFieldKeys.contains(field.key) { return true }
        if field.valueKind == .creatorList {
            return creatorValues[field.key] != originalCreatorValues[field.key]
        }
        if field.valueKind == .textList || field.valueKind == .tags {
            return (listValues[field.key] ?? []) != (originalListValues[field.key] ?? [])
        }
        return fieldValues[field.key] != originalFieldValues[field.key]
    }

    private func selectNewField(_ field: PropertyEditorField) {
        selectedNewFieldKeys.insert(field.key)
        if field.valueKind == .creatorList {
            creatorValues[field.key] = [CreatorDraft()]
        } else if field.valueKind == .textList {
            listValues[field.key] = [""]
        } else if field.valueKind == .tags {
            listValues[field.key] = []
        } else {
            fieldValues[field.key] = ""
        }
        showAvailableProperties = false
        pendingChooserFieldFocus = field.key
    }

    private func restoreChooserFocus() {
        if let key = pendingChooserFieldFocus {
            pendingChooserFieldFocus = nil
            focusedFieldKey = key
        } else {
            addPropertyButtonIsFocused = true
        }
    }

    private func removeField(_ field: PropertyEditorField) {
        if hoveredFieldKey == field.key {
            hoveredFieldKey = nil
        }
        fieldErrors.removeValue(forKey: field.key)
        if selectedNewFieldKeys.remove(field.key) != nil {
            fieldValues.removeValue(forKey: field.key)
            creatorValues.removeValue(forKey: field.key)
            listValues.removeValue(forKey: field.key)
            addPropertyButtonIsFocused = true
        } else {
            removedFieldKeys.insert(field.key)
        }
        focusedFieldKey = nil
    }

    // MARK: - Field Editors

    @ViewBuilder
    private func fieldEditor(for field: PropertyEditorField) -> some View {
        let displayedError = displayedFieldErrors[field.key]
        let hasError = displayedError != nil
        let isRemoved = removedFieldKeys.contains(field.key)

        VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
            fieldHeader(for: field, isRemoved: isRemoved)

            if isRemoved {
                EmptyView()
            } else {
                if field.isReadOnly {
                    readOnlyFieldValue(for: field)
                } else {
                    let binding = Binding(
                        get: { fieldValues[field.key] ?? "" },
                        set: { newValue in
                            fieldValues[field.key] = newValue
                            fieldErrors.removeValue(forKey: field.key)
                        }
                    )

                    editorContent(for: field, binding: binding, hasError: hasError)
                }

                if let error = displayedError {
                    HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(ScholiumTypography.interface(.small))
                        Text(error)
                            .font(ScholiumTypography.interface(.small))
                    }
                    .scholiumForeground(.destructive)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .scholiumHoverState { isHovering in
            if isHovering {
                hoveredFieldKey = field.key
            } else if hoveredFieldKey == field.key {
                hoveredFieldKey = nil
            }
        }
    }

    private func fieldHeader(
        for field: PropertyEditorField,
        isRemoved: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.Properties.labelSpacing) {
            Text(field.label)
                .font(ScholiumTypography.interface(.rowTitle))
                .layoutPriority(1)
                .help(propertyHelpText(for: field))
                .accessibilityValue(Text(verbatim: field.key))
            if isRemoved {
                Text("Pending Removal")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .help("This metadata field will be removed when Save succeeds.")
            } else if !field.isTypicalForSourceType,
                      let sourceType = editorModel.analysisSourceType {
                Text("Not typical")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .help(notTypicalHelp(for: field, sourceType: sourceType))
            }
            if field.isReadOnly, !isRemoved {
                Text("Unsupported shape")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
            if isRemoved {
                Button("Undo Removal") {
                    removedFieldKeys.remove(field.key)
                }
                .scholiumActivationPointer()
                .buttonStyle(.borderless)
            } else if field.isReadOnly {
                Button("Remove Field", role: .destructive) {
                    removeField(field)
                }
                .scholiumActivationPointer()
                .buttonStyle(.borderless)
            } else {
                ScholiumEditorialIconControl(
                    systemImage: "ellipsis",
                    isVisuallyRevealed: hoveredFieldKey == field.key
                        || focusedFieldKey == field.key
                ) { label in
                    Menu {
                        Button(
                            selectedNewFieldKeys.contains(field.key)
                                ? "Discard Added Field"
                                : "Remove Field",
                            role: .destructive
                        ) {
                            removeField(field)
                        }
                        .scholiumActivationPointer()
                    } label: {
                        label
                    }
                    .scholiumActivationPointer()
                }
                .help("Field Actions")
                .accessibilityLabel("Field Actions")
                .accessibilityValue(Text(verbatim: field.label))
            }
        }
    }

    private func notTypicalHelp(
        for field: PropertyEditorField,
        sourceType: AnalysisSourceType
    ) -> Text {
        if selectedNewFieldKeys.contains(field.key) {
            return Text("This draft field does not apply to \(sourceType.propertyDisplayName). Discard it or choose its source type before saving.")
        }
        return Text("Not typical for \(sourceType.propertyDisplayName). The existing value remains authoritative and can be kept or removed.")
    }

    @ViewBuilder
    private func readOnlyFieldValue(for field: PropertyEditorField) -> some View {
        let value = fieldValues[field.key].flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        Text(value)
            .font(readOnlyValueFont(for: field))
            .scholiumForeground(.secondaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readOnlyValueFont(
        for field: PropertyEditorField
    ) -> Font {
        switch field.controlStyle {
        case .multilineText:
            ScholiumTypography.scholarly(.body)
        case .creatorListEditor, .textListEditor, .tagEditor:
            ScholiumTypography.exact(.body)
        default:
            ScholiumTypography.interface(.body)
        }
    }

    @ViewBuilder
    private func editorContent(
        for field: PropertyEditorField,
        binding: Binding<String>,
        hasError: Bool
    ) -> some View {
        switch field.controlStyle {
        case .textField:
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(field.isReadOnly)
                .focused($focusedFieldKey, equals: field.key)
                .accessibilityLabel(Text(verbatim: field.label))

        case .multilineText:
            TextEditor(text: binding)
                .font(ScholiumTypography.scholarly(.body))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(ScholiumGrid.Spacing.labelAccessoryGap)
                .background(
                    ScholiumColorRole.documentBackground.color,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialTextEditorCornerRadius,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialTextEditorCornerRadius,
                        style: .continuous
                    )
                        .stroke(
                            hasError
                                ? ScholiumColorRole.destructive.color
                                : ScholiumColorRole.separator.color,
                            lineWidth: 1
                        )
                )
                .disabled(field.isReadOnly)
                .focused($focusedFieldKey, equals: field.key)

        case .numberField:
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(field.isReadOnly)
                .focused($focusedFieldKey, equals: field.key)
                .accessibilityLabel(Text(verbatim: field.label))
                .frame(
                    maxWidth: ScholiumMetrics.Properties.numberControlMaximumWidth,
                    alignment: .leading
                )

        case .dateField:
            TextField("", text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(field.isReadOnly)
                .focused($focusedFieldKey, equals: field.key)
                .accessibilityLabel(Text(verbatim: field.label))
                .frame(
                    maxWidth: ScholiumMetrics.Properties.compactControlMaximumWidth,
                    alignment: .leading
                )

        case .toggle:
            Toggle(isOn: Binding(
                get: { fieldValues[field.key]?.lowercased() == "true" },
                set: { fieldValues[field.key] = $0 ? "true" : "false" }
            )) {}
            .scholiumActivationPointer()
            .labelsHidden()
            .accessibilityLabel(Text(verbatim: field.label))
            .disabled(field.isReadOnly)
            .focused($focusedFieldKey, equals: field.key)

        case .tagEditor:
            tagEditor(for: field)

        case .textListEditor:
            arrayEditor(for: field)

        case .choicePicker:
            if let allowed = field.contract?.allowedValues {
                Picker("", selection: binding) {
                    Text("—").tag("")
                    ForEach(allowed, id: \.self) { value in
                        Text(PropertyPresentationCatalog.choiceDisplayName(
                            for: value,
                            fieldKey: field.key
                        )).tag(value)
                    }
                }
                .scholiumActivationPointer()
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: field.label))
                .pickerStyle(.menu)
                .disabled(field.isReadOnly)
                .frame(
                    maxWidth: ScholiumMetrics.Properties.compactControlMaximumWidth,
                    alignment: .leading
                )
                .focused($focusedFieldKey, equals: field.key)
            }

        case .creatorListEditor:
            creatorListEditor(for: field)
        }
    }

    // MARK: - Creator List Editor

    @ViewBuilder
    private func creatorListEditor(for field: PropertyEditorField) -> some View {
        if field.isReadOnly {
            Text(fieldValues[field.key] ?? "—")
                .font(ScholiumTypography.exact(.body))
                .scholiumForeground(.secondaryText)
                .textSelection(.enabled)
        } else {
            let creators = creatorValues[field.key] ?? []
            let presentation = creatorRolePresentation(for: field.key)
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Properties.creatorItemSeparation
            ) {
                ForEach(Array(creators.enumerated()), id: \.element.id) { index, creator in
                    let binding = creatorBinding(
                        field: field.key,
                        index: index,
                        fallback: creator
                    )
                    VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                                Text(verbatim: "\(presentation.itemLabel) \(index + 1)")
                                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                                    .scholiumForeground(.secondaryText)
                                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                                creatorKindPicker(selection: binding.kind)
                                removeCreatorButton(field: field, index: index)
                            }
                            VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
                                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                                    Text(verbatim: "\(presentation.itemLabel) \(index + 1)")
                                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                                        .scholiumForeground(.secondaryText)
                                    Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                                    removeCreatorButton(field: field, index: index)
                                }
                                creatorKindPicker(selection: binding.kind)
                            }
                        }

                        if creator.kind == .organization {
                            creatorTextField(
                                "Organization Name",
                                text: binding.literal
                            )
                            .focused($focusedFieldKey, equals: field.key)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                                    creatorTextField("Family name", text: binding.family)
                                        .focused($focusedFieldKey, equals: field.key)
                                    creatorTextField("Given name", text: binding.given)
                                }
                                VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
                                    creatorTextField("Family name", text: binding.family)
                                        .focused($focusedFieldKey, equals: field.key)
                                    creatorTextField("Given name", text: binding.given)
                                }
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                                    creatorTextField(
                                        "Non-dropping particle",
                                        text: binding.nonDroppingParticle
                                    )
                                    creatorTextField(
                                        "Dropping particle",
                                        text: binding.droppingParticle
                                    )
                                    creatorTextField("Suffix", text: binding.suffix)
                                }
                                VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
                                    creatorTextField(
                                        "Non-dropping particle",
                                        text: binding.nonDroppingParticle
                                    )
                                    creatorTextField(
                                        "Dropping particle",
                                        text: binding.droppingParticle
                                    )
                                    creatorTextField("Suffix", text: binding.suffix)
                                }
                            }
                        }
                    }
                }

                Button {
                    creatorValues[field.key, default: []].append(CreatorDraft())
                } label: {
                    Label {
                        Text(verbatim: presentation.addActionLabel)
                    } icon: {
                        Image(systemName: "plus.circle")
                    }
                }
                .scholiumActivationPointer()
                .buttonStyle(.borderless)
            }
        }
    }

    private struct CreatorRolePresentation {
        let itemLabel: String
        let addActionLabel: String
    }

    private func creatorRolePresentation(for key: String) -> CreatorRolePresentation {
        let labels: (String, String) = switch key {
        case "authors": ("Author", "Add Author")
        case "editors": ("Editor", "Add Editor")
        case "translators": ("Translator", "Add Translator")
        case "collection_editors": ("Collection Editor", "Add Collection Editor")
        case "container_authors": ("Container Author", "Add Container Author")
        case "original_authors": ("Original Author", "Add Original Author")
        case "reviewed_authors": ("Reviewed Author", "Add Reviewed Author")
        default: ("Creator", "Add Creator")
        }
        return CreatorRolePresentation(
            itemLabel: ScholiumL10n.dynamicString(labels.0),
            addActionLabel: ScholiumL10n.dynamicString(labels.1)
        )
    }

    private func creatorKindPicker(
        selection: Binding<CreatorDraft.Kind>
    ) -> some View {
        ScholiumSegmentedControl(
            selection: selection,
            options: [
                ScholiumSegmentedControlOption(
                    .person,
                    title: String(localized: "Person")
                ),
                ScholiumSegmentedControlOption(
                    .organization,
                    title: String(localized: "Organization")
                ),
            ],
            label: String(localized: "Creator Kind")
        )
        .frame(
            maxWidth: ScholiumMetrics.Properties.compactControlMaximumWidth,
            alignment: .leading
        )
    }

    private func creatorTextField(
        _ label: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
            Text(label)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func removeCreatorButton(
        field: PropertyEditorField,
        index: Int
    ) -> some View {
        Button {
            var updated = creatorValues[field.key] ?? []
            if updated.count == 1 {
                removeField(field)
            } else {
                updated.remove(at: index)
                creatorValues[field.key] = updated
            }
        } label: {
            Image(systemName: "minus.circle")
                .frame(
                    width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    height: ScholiumMetrics.Accessibility.preferredCustomTarget
                )
                .contentShape(Rectangle())
        }
        .scholiumActivationPointer()
        .buttonStyle(.borderless)
        .accessibilityLabel("Remove creator \(index + 1)")
    }

    private func creatorBinding(
        field: String,
        index: Int,
        fallback: CreatorDraft
    ) -> Binding<CreatorDraft> {
        Binding(
            get: {
                guard let creators = creatorValues[field], creators.indices.contains(index) else {
                    return fallback
                }
                return creators[index]
            },
            set: { value in
                guard var creators = creatorValues[field], creators.indices.contains(index) else {
                    return
                }
                creators[index] = value
                creatorValues[field] = creators
                fieldErrors.removeValue(forKey: field)
            }
        )
    }

    // MARK: - Tag Editor

    @ViewBuilder
    private func tagEditor(for field: PropertyEditorField) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            // Current tags
            let tags = listValues[field.key] ?? []
            if !tags.isEmpty {
                FlowLayout(spacing: ScholiumMetrics.Properties.optionSpacing) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                        Button {
                            var updated = listValues[field.key] ?? []
                            guard updated.indices.contains(index) else { return }
                            updated.remove(at: index)
                            if updated.isEmpty {
                                removeField(field)
                            } else {
                                listValues[field.key] = updated
                            }
                        } label: {
                            ScholiumTagCapsuleLabel(
                                tag,
                                trailingSystemImage: "xmark"
                            )
                        }
                        .scholiumActivationPointer()
                        .buttonStyle(.plain)
                        .help("Remove tag \(tag)")
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                }
            }

            // Add tag input
            HStack(spacing: ScholiumMetrics.Properties.fieldSpacing) {
                TextField("Add tag...", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedFieldKey, equals: field.key)
                    .onSubmit {
                        addTag(field: field)
                    }
                Button {
                    addTag(field: field)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .scholiumSymbolStyle(.prominent)
                        .scholiumForeground(.accent)
                }
                .scholiumActivationPointer()
                .buttonStyle(.plain)
                .frame(
                    minWidth: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
                )
                .contentShape(Rectangle())
                .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Add tag")
                .accessibilityLabel("Add tag")
            }
        }
        .disabled(field.isReadOnly)
    }

    // MARK: - Array Editor

    @ViewBuilder
    private func arrayEditor(for field: PropertyEditorField) -> some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
            let items = listValues[field.key] ?? []

            ForEach(items.indices, id: \.self) { idx in
                HStack(spacing: ScholiumMetrics.Properties.fieldSpacing) {
                    TextField("Item \(idx + 1)", text: Binding(
                        get: {
                            guard let current = listValues[field.key],
                                  current.indices.contains(idx) else { return "" }
                            return current[idx]
                        },
                        set: { newVal in
                            guard var updated = listValues[field.key],
                                  updated.indices.contains(idx) else { return }
                            updated[idx] = newVal
                            listValues[field.key] = updated
                            fieldErrors.removeValue(forKey: field.key)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedFieldKey, equals: field.key)

                    Button {
                        guard var updated = listValues[field.key],
                              updated.indices.contains(idx) else { return }
                        if updated.count == 1 {
                            removeField(field)
                        } else {
                            updated.remove(at: idx)
                            listValues[field.key] = updated
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .scholiumForeground(.secondaryText)
                    }
                    .scholiumActivationPointer()
                    .buttonStyle(.plain)
                    .frame(
                        minWidth: ScholiumMetrics.Accessibility.preferredCustomTarget,
                        minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
                    )
                    .contentShape(Rectangle())
                    .help("Remove item \(idx + 1)")
                    .accessibilityLabel("Remove item \(idx + 1)")
                }
            }

            Button {
                listValues[field.key, default: []].append("")
            } label: {
                Label("Add item", systemImage: "plus.circle")
                    .font(ScholiumTypography.interface(.small))
            }
            .scholiumActivationPointer()
            .buttonStyle(.borderless)
        }
        .disabled(field.isReadOnly)
    }

    // MARK: - Tag Add Helper

    private func addTag(field: PropertyEditorField) {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var tags = listValues[field.key] ?? []
        tags.append(trimmed)
        listValues[field.key] = tags
        tagInput = ""
    }

    // MARK: - Save

    private func saveChanges() {
        saveError = nil
        fieldErrors = liveFieldErrors
        guard canSaveDraft else { return }
        let candidate = draftCandidate

        isSaving = true
        Task {
            do {
                try await save(candidate.fields, expectedRevision)
                isSaving = false
                closeEditor()
            } catch let error as NoteMetadataError {
                if case .revisionConflict = error {
                    revisionConflict = true
                    saveError = nil
                } else {
                    saveError = error.localizedDescription
                }
                isSaving = false
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func reloadCurrentNote() {
        guard let reload else { return }
        isReloading = true
        saveError = nil
        Task {
            do {
                let refreshed = try await reload()
                installDraft(note: refreshed.note, revision: refreshed.revision)
            } catch {
                saveError = error.localizedDescription
            }
            isReloading = false
        }
    }

    private func installDraft(
        note refreshedNote: WindowDocumentLocation,
        revision: DocumentFingerprint?
    ) {
        note = refreshedNote
        fieldValues = [:]
        originalFieldValues = [:]
        fieldErrors = [:]
        creatorValues = [:]
        originalCreatorValues = [:]
        listValues = [:]
        originalListValues = [:]
        selectedNewFieldKeys = []
        removedFieldKeys = []
        revisionConflict = false
        saveError = nil

        for (key, value) in refreshedNote.managedMetadataFields {
            let stringValue = metadataValueToString(value)
            fieldValues[key] = stringValue
            originalFieldValues[key] = stringValue
        }
        let model = PropertyEditorModel(
            note: refreshedNote,
            metadataCatalog: metadataCatalog
        )
        for field in model.presentFields where field.valueKind == .creatorList {
            guard case .array(let values)? = refreshedNote.managedMetadataValue(named: field.key) else {
                continue
            }
            let drafts = values.compactMap(CreatorDraft.init(value:))
            creatorValues[field.key] = drafts
            originalCreatorValues[field.key] = drafts
        }
        for field in model.presentFields where field.valueKind == .textList
            || field.valueKind == .tags {
            guard case .array(let values)? = refreshedNote.managedMetadataValue(named: field.key) else {
                continue
            }
            let items = values.compactMap { value -> String? in
                guard case .string(let item) = value else { return nil }
                return item
            }
            listValues[field.key] = items
            originalListValues[field.key] = items
        }
        expectedRevision = revision
    }

    private func closeEditor() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    // MARK: - Helpers

    private func metadataValueToString(_ value: YAMLValue) -> String {
        switch value {
        case .string(let s): return s
        case .integer(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .boolean(let b): return b ? "true" : "false"
        case .null: return ""
        case .array(let values): return values.map(\.displayScalar).joined(separator: "; ")
        case .object(let values):
            return values.map { "\($0.key): \($0.value.displayScalar)" }.joined(separator: "; ")
        }
    }

}

private struct PropertyChooserView: View {
    @Environment(\.dismiss) private var dismiss
    let model: PropertyEditorModel
    let excludedKeys: Set<String>
    let select: (PropertyEditorField) -> Void
    @State private var query = ""
    @State private var selectionKey: String?
    @FocusState private var searchIsFocused: Bool
    @FocusState private var listIsFocused: Bool

    private var groups: [(group: PropertyPresentationGroup, fields: [PropertyEditorField])] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.groupedAvailableFields.compactMap { group in
            let fields = group.fields.filter { field in
                guard !excludedKeys.contains(field.key) else { return false }
                guard !normalized.isEmpty else { return true }
                return field.label.localizedStandardContains(normalized)
                    || field.key.localizedStandardContains(normalized)
                    || (field.help?.localizedStandardContains(normalized) ?? false)
            }
            return fields.isEmpty ? nil : (group.group, fields)
        }
    }

    private var fields: [PropertyEditorField] { groups.flatMap(\.fields) }

    private var selectedField: PropertyEditorField? {
        guard let selectionKey else { return nil }
        return fields.first { $0.key == selectionKey }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                    Text("Add a Field")
                        .font(ScholiumTypography.interface(.primaryTitle))
                    if model.profile == .analysis {
                        Text(model.analysisSourceType.map {
                            "Recommended fields for \($0.propertyDisplayName)"
                        } ?? "Choose Source Type first, or add a field shared by all source types")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .scholiumActivationPointer()
                    .keyboardShortcut(.escape)
            }

            TextField("Search fields", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)
                .accessibilityIdentifier("scholium.metadataChooser.search")
                .onKeyPress(.downArrow) {
                    guard let first = fields.first else { return .ignored }
                    selectionKey = first.key
                    listIsFocused = true
                    return .handled
                }
                .onSubmit { addSelectedField(preferFirst: true) }

            if groups.isEmpty {
                ScholiumContentStateView(
                    "No Matching Fields",
                            detail: Text("Try a field label or exact Metadata key."),
                    indicator: .symbol("magnifyingglass", role: .secondaryText)
                )
            } else {
                List(selection: $selectionKey) {
                    ForEach(groups, id: \.group) { group in
                        Section(group.group.label) {
                            ForEach(group.fields) { field in
                                VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                                    HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                                        Text(field.label)
                                            .font(ScholiumTypography.interface(.body))
                                        if field.isRecommended {
                                            Text("Recommended")
                                                .font(ScholiumTypography.interface(.small))
                                                .scholiumForeground(.secondaryText)
                                        }
                                    }
                                    Text(field.key)
                                        .font(ScholiumTypography.exact(.small))
                                        .scholiumForeground(.mutedText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(propertyHelpText(for: field))
                                .tag(field.key)
                                .contentShape(Rectangle())
                                .scholiumActivationPointer()
                                .onTapGesture(count: 2) {
                                    selectionKey = field.key
                                    addSelectedField()
                                }
                                .accessibilityHint("Adds an empty draft editor; the note changes only after a valid Save")
                            }
                        }
                    }
                }
                .focused($listIsFocused)
                .accessibilityIdentifier("scholium.metadataChooser.list")
            }

            HStack {
                Spacer()
                Button("Add Selected Field") { addSelectedField() }
                    .scholiumActivationPointer()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedField == nil)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(minWidth: 440, minHeight: 480)
        .task { searchIsFocused = true }
        .onChange(of: query) { _, _ in
            if selectedField == nil { selectionKey = nil }
        }
    }

    private func addSelectedField(preferFirst: Bool = false) {
        if preferFirst, selectionKey == nil { selectionKey = fields.first?.key }
        guard let field = selectedField else { return }
        select(field)
    }
}

private func propertyHelpText(for field: PropertyEditorField) -> Text {
        let metadataKey = "Metadata: \(field.key)"
        guard let help = field.help, !help.isEmpty else {
            return Text(verbatim: metadataKey)
        }
        return Text(verbatim: "\(help)\n\(metadataKey)")
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sized = measuredSizes(subviews, maximumWidth: proposal.width)
        let rows = computeRows(proposal: proposal, sizes: sized)
        let height = rows.reduce(0) { $0 + ($1.map { $0.height }.max() ?? 0) } + CGFloat(max(0, rows.count - 1)) * spacing
        let contentWidth = rows.map { row in
            row.reduce(0) { $0 + $1.width }
                + CGFloat(max(0, row.count - 1)) * spacing
        }.max() ?? 0
        return CGSize(width: proposal.width ?? contentWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measuredSizes(subviews, maximumWidth: bounds.width)
        let rows = computeRows(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            sizes: sizes
        )
        var y = bounds.minY
        var idx = 0
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.height }.max() ?? 0
            for size in row {
                if idx < subviews.count {
                    subviews[idx].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                    x += size.width + spacing
                    idx += 1
                }
            }
            y += rowHeight + spacing
        }
    }

    private func measuredSizes(
        _ subviews: Subviews,
        maximumWidth: CGFloat?
    ) -> [CGSize] {
        subviews.map { subview in
            let intrinsic = subview.sizeThatFits(.unspecified)
            guard let maximumWidth, maximumWidth.isFinite,
                  maximumWidth > 0, intrinsic.width > maximumWidth else {
                return intrinsic
            }
            let bounded = subview.sizeThatFits(ProposedViewSize(
                width: maximumWidth,
                height: nil
            ))
            return CGSize(
                width: min(maximumWidth, bounded.width),
                height: bounded.height
            )
        }
    }

    private func computeRows(proposal: ProposedViewSize, sizes: [CGSize]) -> [[CGSize]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var currentWidth: CGFloat = 0
        for size in sizes {
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(size)
            currentWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Preview

#Preview {
    MetadataEditorView(note: .syntheticPreview(
        relativePath: "papers/smith2023.md",
            rawContent: "# Attention Is All You Need\n",
            vaultRole: .sourceCorpus,
            managedMetadata: [
                "type": .string("journal_article"),
                "title": .string("Attention Is All You Need"),
                "authors": .array([
                    .object(["family": .string("Smith")]),
                    .object(["family": .string("Jones")]),
                ]),
                "publication_date": .string("2023"),
            ]
    ), metadataCatalog: .builtIn) { _, _ in }
}
