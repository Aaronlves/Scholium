import ScholiumContracts
import SwiftUI

enum AboutPropertyAuthority: Hashable, Sendable {
    case managedMetadata
    case authoredSource
}

struct AboutPropertyDescriptor: Identifiable, Hashable, Sendable {
    var id: String { presentation.key }
    var key: String { presentation.key }
    var label: String { presentation.label }
    var valueKind: PropertyValueKind { contract.valueKind }
    var controlStyle: PropertyControlStyle { presentation.controlStyle }

    let presentation: PropertyPresentation
    let contract: PropertyContract
    let authority: AboutPropertyAuthority
    let value: YAMLValue?

    var isEditable: Bool {
        if authority == .authoredSource, value == .null { return true }
        return value.map {
            PropertyContractCatalog.supportsTargetedStructuredEditing(
                $0,
                as: contract.valueKind
            )
        } ?? true
    }
}

struct AboutFieldSaveFailure: Hashable {
    let isConflict: Bool
    let message: String

    init(_ error: Error) {
        isConflict = if let metadataError = error as? NoteMetadataError,
                        case .revisionConflict = metadataError {
            true
        } else if let repositoryError = error as? VaultRepositoryError,
                  case .conflict = repositoryError {
            true
        } else {
            false
        }
        message = error.localizedDescription
    }

    var accessibilityIdentifierSuffix: String {
        isConflict ? "conflict" : "error"
    }
}

enum AboutFieldOperationState: Hashable {
    case idle
    case saving
    case failed(AboutFieldSaveFailure)

    var isSaving: Bool { self == .saving }

    var failure: AboutFieldSaveFailure? {
        guard case .failed(let failure) = self else { return nil }
        return failure
    }

    mutating func beginSaving() {
        self = .saving
    }

    mutating func finishSaving() {
        self = .idle
    }

    mutating func finishSaving(with error: Error) {
        self = .failed(AboutFieldSaveFailure(error))
    }

    mutating func reset() {
        self = .idle
    }
}

private struct AboutListItemDraft: Identifiable, Hashable {
    let id: UUID
    var value: String

    init(id: UUID = UUID(), value: String = "") {
        self.id = id
        self.value = value
    }
}

private struct AboutCreatorDraft: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Hashable {
        case person
        case organization

        var title: LocalizedStringResource {
            switch self {
            case .person: "Person"
            case .organization: "Organization"
            }
        }
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
            family = ""
            given = ""
            suffix = ""
            nonDroppingParticle = ""
            droppingParticle = ""
        } else {
            kind = .person
            literal = ""
            family = mapping["family"]?.scalarString ?? ""
            given = mapping["given"]?.scalarString ?? ""
            suffix = mapping["suffix"]?.scalarString ?? ""
            nonDroppingParticle = mapping["non_dropping_particle"]?.scalarString ?? ""
            droppingParticle = mapping["dropping_particle"]?.scalarString ?? ""
        }
    }

    var yamlValue: YAMLValue? {
        switch kind {
        case .organization:
            let name = literal.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : .object(["literal": .string(literal)])
        case .person:
            let family = family.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !family.isEmpty else { return nil }
            var mapping: [String: YAMLValue] = ["family": .string(self.family)]
            for (key, value) in [
                ("given", given),
                ("suffix", suffix),
                ("non_dropping_particle", nonDroppingParticle),
                ("dropping_particle", droppingParticle),
            ] where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mapping[key] = .string(value)
            }
            return .object(mapping)
        }
    }
}

/// One directly editable About row. It owns only a field-local draft and
/// operation presentation; the supplied closure retains the real data owner.
struct AboutEditablePropertyRow: View {
    let descriptor: AboutPropertyDescriptor
    @Binding var activeEditorKey: String?
    let save: @MainActor (YAMLValue?) async throws -> Void

    @State private var scalarText = ""
    @State private var booleanValue = false
    @State private var listItems: [AboutListItemDraft] = []
    @State private var creators: [AboutCreatorDraft] = []
    @State private var operationState: AboutFieldOperationState = .idle
    @FocusState private var scalarIsFocused: Bool

    private var isEditing: Bool { activeEditorKey == descriptor.key }
    private var anotherFieldIsEditing: Bool {
        activeEditorKey != nil && !isEditing
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Properties.fieldSpacing
        ) {
            if isEditing {
                editor
            } else {
                displayButton
            }

            if let failure = operationState.failure {
                Label(failure.message, systemImage: "exclamationmark.circle.fill")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        "scholium.about.field.\(descriptor.key)."
                            + failure.accessibilityIdentifierSuffix
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: descriptor.value) { _, _ in
            guard !isEditing else { return }
            installDraft()
            operationState.reset()
        }
        .onChange(of: isEditing) { _, editing in
            guard editing else { return }
            installDraft()
            operationState.reset()
            if usesScalarControl {
                Task { @MainActor in
                    await Task.yield()
                    scalarIsFocused = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.about.field.\(descriptor.key)")
    }

    private var displayButton: some View {
        Button {
            guard descriptor.isEditable, !anotherFieldIsEditing else { return }
            activeEditorKey = descriptor.key
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.Apparatus.factColumnSpacing) {
                    fieldLabel
                        .multilineTextAlignment(.trailing)
                        .frame(
                            width: ScholiumMetrics.Apparatus.factLabelMinimumWidth,
                            alignment: .trailing
                        )
                    displayValue
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.longTextLabelSpacing
                ) {
                    fieldLabel
                    displayValue
                        .padding(.leading, ScholiumMetrics.Apparatus.longTextIndent)
                }
            }
            .contentShape(Rectangle())
        }
        .scholiumActivationPointer()
        .buttonStyle(.plain)
        .disabled(!descriptor.isEditable || anotherFieldIsEditing)
        .help(descriptor.isEditable ? "Edit \(descriptor.label)" : "Open Metadata to review this unsupported value")
        .accessibilityLabel(Text(verbatim: descriptor.label))
        .accessibilityValue(Text(verbatim: displayText))
        .accessibilityHint(descriptor.isEditable ? "Edits this field in About" : "This value has an unsupported editable shape")
    }

    private var fieldLabel: some View {
        Text(verbatim: descriptor.label)
            .font(ScholiumTypography.interface(.compact, emphasis: .strong))
            .scholiumForeground(.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var displayValue: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(verbatim: displayText)
                .font(displayFont)
                .scholiumForeground(descriptor.value == nil ? .mutedText : .primaryText)
                .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
            if descriptor.isEditable {
                Image(systemName: "pencil")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
                    .accessibilityHidden(true)
            }
        }
    }

    private var displayFont: Font {
        switch descriptor.controlStyle {
        case .multilineText:
            ScholiumTypography.scholarly(.body)
        case .creatorListEditor, .textListEditor, .tagEditor:
            ScholiumTypography.scholarly(.body)
        default:
            ScholiumTypography.scholarly(.body)
        }
    }

    private var displayText: String {
        guard let value = descriptor.value else {
            return String(localized: "Add \(descriptor.label)")
        }
        switch value {
        case .string(let value):
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return String(localized: "Add \(descriptor.label)")
            }
            return descriptor.valueKind == .choice
                ? PropertyPresentationCatalog.choiceDisplayName(
                    for: value,
                    fieldKey: descriptor.key
                )
                : value
        case .integer(let value): return String(value)
        case .double(let value): return String(value)
        case .boolean(let value): return value ? String(localized: "Yes") : String(localized: "No")
        case .array(let values):
            if descriptor.valueKind == .creatorList {
                let names = values.compactMap(AboutCreatorDraft.init(value:)).compactMap { creator in
                    switch creator.kind {
                    case .organization: creator.literal
                    case .person:
                        [creator.given, creator.family]
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                    }
                }
                return names.isEmpty ? String(localized: "Add \(descriptor.label)") : names.joined(separator: "; ")
            }
            let items = values.compactMap(\.scalarString)
            return items.isEmpty ? String(localized: "Add \(descriptor.label)") : items.joined(separator: ", ")
        case .null:
            return String(localized: "Add \(descriptor.label)")
        case .object:
            return String(localized: "Review in Metadata")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
            HStack(alignment: .firstTextBaseline) {
                fieldLabel
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Text(authorityLabel)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
            }

            editorControl

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if descriptor.value != nil {
                    Button("Remove", role: .destructive) {
                        commit(nil)
                    }
                    .scholiumActivationPointer()
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Button("Cancel") { cancel() }
                    .scholiumActivationPointer()
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.escape)
                Button("Save") { commit(candidateValue) }
                    .scholiumActivationPointer()
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(operationState.isSaving || candidateValue == descriptor.value)
            }
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .disabled(operationState.isSaving)
    }

    private var authorityLabel: String {
        switch descriptor.authority {
        case .managedMetadata: String(localized: "Scholium Metadata")
        case .authoredSource: String(localized: "Authored Source")
        }
    }

    @ViewBuilder
    private var editorControl: some View {
        switch descriptor.controlStyle {
        case .textField, .numberField, .dateField:
            TextField(descriptor.label, text: $scalarText)
                .textFieldStyle(.roundedBorder)
                .focused($scalarIsFocused)
                .accessibilityLabel(Text(verbatim: descriptor.label))

        case .multilineText:
            TextEditor(text: $scalarText)
                .font(ScholiumTypography.scholarly(.body))
                .frame(minHeight: 84)
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
                    .stroke(ScholiumColorRole.separator.color, lineWidth: 1)
                )
                .focused($scalarIsFocused)
                .accessibilityLabel(Text(verbatim: descriptor.label))

        case .toggle:
            Toggle(descriptor.label, isOn: $booleanValue)
                .scholiumActivationPointer()
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: descriptor.label))

        case .choicePicker:
            Picker(descriptor.label, selection: $scalarText) {
                Text("Choose…").tag("")
                ForEach(descriptor.contract.allowedValues ?? [], id: \.self) { value in
                    Text(PropertyPresentationCatalog.choiceDisplayName(
                        for: value,
                        fieldKey: descriptor.key
                    )).tag(value)
                }
            }
            .scholiumActivationPointer()
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: ScholiumMetrics.Properties.compactControlMaximumWidth, alignment: .leading)
            .accessibilityLabel(Text(verbatim: descriptor.label))

        case .tagEditor, .textListEditor:
            listEditor

        case .creatorListEditor:
            creatorEditor
        }
    }

    private var listEditor: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
            ForEach($listItems) { $item in
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    TextField(descriptor.label, text: $item.value)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        listItems.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .scholiumActivationPointer()
                    .buttonStyle(.borderless)
                    .help("Remove value")
                    .accessibilityLabel("Remove \(descriptor.label) value")
                }
            }
            Button("Add Value") {
                listItems.append(AboutListItemDraft())
            }
            .scholiumActivationPointer()
            .buttonStyle(.borderless)
        }
    }

    private var creatorEditor: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.creatorItemSeparation) {
            ForEach($creators) { $creator in
                VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
                    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Picker("Creator Type", selection: $creator.kind) {
                            ForEach(AboutCreatorDraft.Kind.allCases, id: \.self) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .scholiumActivationPointer()
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                        Button {
                            creators.removeAll { $0.id == creator.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .scholiumActivationPointer()
                        .buttonStyle(.borderless)
                        .help("Remove creator")
                        .accessibilityLabel("Remove creator")
                    }

                    if creator.kind == .organization {
                        TextField("Organization Name", text: $creator.literal)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField("Family Name", text: $creator.family)
                            .textFieldStyle(.roundedBorder)
                        TextField("Given Name", text: $creator.given)
                            .textFieldStyle(.roundedBorder)
                        DisclosureGroup("Additional Name Fields") {
                            VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
                                TextField("Suffix", text: $creator.suffix)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Non-dropping Particle", text: $creator.nonDroppingParticle)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Dropping Particle", text: $creator.droppingParticle)
                                    .textFieldStyle(.roundedBorder)
                            }
                            .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
                        }
                        .scholiumActivationPointer()
                    }
                }
                .padding(.bottom, ScholiumGrid.Spacing.labelAccessoryGap)
            }
            Button("Add Creator") {
                creators.append(AboutCreatorDraft())
            }
            .scholiumActivationPointer()
            .buttonStyle(.borderless)
        }
    }

    private var usesScalarControl: Bool {
        switch descriptor.controlStyle {
        case .textField, .multilineText, .numberField, .dateField: true
        case .toggle, .tagEditor, .textListEditor, .choicePicker, .creatorListEditor: false
        }
    }

    private var candidateValue: YAMLValue? {
        switch descriptor.valueKind {
        case .text, .multilineText, .date, .choice:
            return scalarText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : .string(scalarText)
        case .number:
            let value = scalarText.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { return nil }
            if let integer = Int(value) { return .integer(integer) }
            if let double = Double(value) { return .double(double) }
            return .string(value)
        case .boolean:
            return .boolean(booleanValue)
        case .tags, .textList:
            let values = listItems.map(\.value).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if values.isEmpty {
                return descriptor.authority == .authoredSource && descriptor.key == "keywords"
                    ? .array([])
                    : nil
            }
            return .array(values.map(YAMLValue.string))
        case .creatorList:
            let values = creators.compactMap(\.yamlValue)
            return values.isEmpty ? nil : .array(values)
        case .mapping:
            return descriptor.value
        }
    }

    private func installDraft() {
        scalarText = ""
        booleanValue = false
        listItems = []
        creators = []
        guard let value = descriptor.value else {
            if descriptor.valueKind == .tags || descriptor.valueKind == .textList {
                listItems = [AboutListItemDraft()]
            }
            return
        }
        switch value {
        case .string(let value): scalarText = value
        case .integer(let value): scalarText = String(value)
        case .double(let value): scalarText = String(value)
        case .boolean(let value): booleanValue = value
        case .array(let values):
            if descriptor.valueKind == .creatorList {
                creators = values.compactMap(AboutCreatorDraft.init(value:))
            } else {
                listItems = values.compactMap(\.scalarString).map {
                    AboutListItemDraft(value: $0)
                }
                if listItems.isEmpty { listItems = [AboutListItemDraft()] }
            }
        case .object, .null:
            break
        }
    }

    private func cancel() {
        guard !operationState.isSaving else { return }
        installDraft()
        operationState.reset()
        activeEditorKey = nil
    }

    private func commit(_ value: YAMLValue?) {
        guard !operationState.isSaving else { return }
        operationState.beginSaving()
        Task { @MainActor in
            do {
                try await save(value)
                operationState.finishSaving()
                activeEditorKey = nil
            } catch is CancellationError {
                // A cancelled field mutation retains the draft without adding
                // a misleading failure state.
                operationState.finishSaving()
            } catch {
                operationState.finishSaving(with: error)
            }
        }
    }
}
