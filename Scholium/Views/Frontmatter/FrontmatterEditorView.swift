import ScholiumContracts
import SwiftUI

// MARK: - Properties Editor

/// Schema-aware sheet for editing a note's frontmatter.
struct FrontmatterEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let note: WindowDocumentLocation
    let configuredEditableFields: Set<String>?
    let initialExpectedRevision: DocumentFingerprint?
    let onClose: (@MainActor () -> Void)?
    let save: @MainActor (
        [String: YAMLValue],
        DocumentFingerprint
    ) async throws -> Void

    @State private var fieldValues: [String: String] = [:]
    @State private var originalFieldValues: [String: String] = [:]
    @State private var fieldErrors: [String: String] = [:]
    @State private var tagInput: String = ""
    @State private var isSaving = false
    @State private var expectedRevision: DocumentFingerprint?
    @State private var saveError: String?
    @State private var showAvailableProperties = false

    init(
        note: WindowDocumentLocation,
        configuredEditableFields: Set<String>? = nil,
        expectedRevision: DocumentFingerprint? = nil,
        onClose: (@MainActor () -> Void)? = nil,
        save: @escaping @MainActor (
            [String: YAMLValue],
            DocumentFingerprint
        ) async throws -> Void
    ) {
        self.note = note
        self.configuredEditableFields = configuredEditableFields
        self.initialExpectedRevision = expectedRevision
        self.onClose = onClose
        self.save = save
    }

    private var editorModel: PropertyEditorModel {
        PropertyEditorModel(
            note: note,
            configuredEditableFields: configuredEditableFields
        )
    }

    private var presentFields: [PropertyEditorField] { editorModel.presentFields }

    private var availableFields: [PropertyEditorField] { editorModel.availableFields }

    private var allFields: [PropertyEditorField] { editorModel.allFields }

    private var groupedPresentFields: [(group: PropertyPresentationGroup, fields: [PropertyEditorField])] {
        editorModel.groupedPresentFields
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.headerDetailSpacing) {
                    Text("Properties")
                        .font(ScholiumTypography.interface(.primaryTitle))
                    Text(note.title ?? note.displayName)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                }
                Spacer()
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Button("Cancel") { closeEditor() }
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(ScholiumColorRole.accent.color)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isSaving)
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)

            Divider()

            // Form fields
            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    Text("Researcher Properties")
                        .font(ScholiumTypography.interface(.sectionTitle))

                    if allFields.isEmpty {
                        Label(
                            "No other fields are enabled for structured editing in this vault. Change the vault-wide allowlist in Settings, or use Source mode to edit exact YAML.",
                            systemImage: "lock"
                        )
                        .font(ScholiumTypography.interface(.body))
                        .scholiumForeground(.secondaryText)
                    }

                    ForEach(groupedPresentFields, id: \.group) { group in
                        GroupBox(group.group.label) {
                            VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.sectionSpacing) {
                                ForEach(group.fields) { field in
                                    fieldEditor(for: field)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
                        }
                    }

                    if !availableFields.isEmpty {
                        Divider()
                            .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)

                        DisclosureGroup("Add a Property", isExpanded: $showAvailableProperties) {
                            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                                ForEach(availableFields) { field in
                                    fieldEditor(for: field)
                                }
                            }
                            .padding(.top, ScholiumGrid.Spacing.nestedContentInset)
                        }
                        .font(ScholiumTypography.interface(.sectionTitle))
                    }
                }
                .padding(ScholiumGrid.Spacing.regionContentInset)
            }

            // Footer with validation summary
            if !fieldErrors.isEmpty {
                Divider()

                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scholiumForeground(.destructive)
                        .font(ScholiumTypography.interface(.small))
                    Text("\(fieldErrors.count) validation error\(fieldErrors.count == 1 ? "" : "s")")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.destructive)
                    Spacer()
                }
                .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }
        }
        .scholiumSurface(.boundedPanel)
        .accessibilityIdentifier("scholium.propertiesEditor")
        .task {
            // Initialize field values from existing frontmatter
            for (key, value) in note.frontmatter {
                let stringValue = frontmatterToString(value)
                fieldValues[key] = stringValue
                originalFieldValues[key] = stringValue
            }
            for field in allFields where fieldValues[field.key] == nil {
                guard let value = note.property(at: field.key) else { continue }
                let stringValue = frontmatterToString(value)
                fieldValues[field.key] = stringValue
                originalFieldValues[field.key] = stringValue
            }
            expectedRevision = initialExpectedRevision
        }
        .alert("Could Not Save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Field Editors

    @ViewBuilder
    private func fieldEditor(for field: PropertyEditorField) -> some View {
        let hasError = fieldErrors[field.key] != nil

        VStack(alignment: .leading, spacing: ScholiumMetrics.Properties.fieldSpacing) {
            // Label
            HStack(spacing: ScholiumMetrics.Properties.labelSpacing) {
                Text(field.label)
                    .font(ScholiumTypography.interface(.rowTitle))
                if field.isReadOnly {
                    Text("Read only")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .padding(.horizontal, ScholiumMetrics.Properties.badgeHorizontalInset)
                        .padding(.vertical, ScholiumMetrics.Properties.badgeVerticalInset)
                        .background(
                            ScholiumColorRole.raisedSurfaceBackground.color,
                            in: Capsule()
                        )
                }
            }

            // Description
            if let desc = field.help {
                Text(desc)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
            }

            // Editor
            let binding = Binding(
                get: { fieldValues[field.key] ?? "" },
                set: { newValue in
                    fieldValues[field.key] = newValue
                    fieldErrors.removeValue(forKey: field.key)
                }
            )

            editorContent(for: field, binding: binding, hasError: hasError)

            // Error message
            if let error = fieldErrors[field.key] {
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

    @ViewBuilder
    private func editorContent(
        for field: PropertyEditorField,
        binding: Binding<String>,
        hasError: Bool
    ) -> some View {
        switch field.controlStyle {
        case .textField:
            TextField(field.label, text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(field.isReadOnly)

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

        case .numberField:
            TextField(field.label, text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(field.isReadOnly)

        case .dateField:
            if field.isReadOnly {
                Text(fieldValues[field.key] ?? "—")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
            } else {
                if let value = fieldValues[field.key], let date = parseDate(value) {
                    DatePicker("", selection: Binding(
                        get: { date },
                        set: { fieldValues[field.key] = formatDate($0) }
                    ), displayedComponents: .date)
                    .datePickerStyle(.field)
                } else {
                    DatePicker("", selection: Binding(
                        get: { Date() },
                        set: { fieldValues[field.key] = formatDate($0) }
                    ), displayedComponents: .date)
                    .datePickerStyle(.field)
                }
            }

        case .toggle:
            Toggle(isOn: Binding(
                get: { fieldValues[field.key]?.lowercased() == "true" },
                set: { fieldValues[field.key] = $0 ? "true" : "false" }
            )) {
                Text(field.label)
                    .font(ScholiumTypography.interface(.body))
            }
            .disabled(field.isReadOnly)

        case .tagEditor:
            tagEditor(for: field)

        case .textListEditor:
            arrayEditor(for: field)

        case .choicePicker:
            if let allowed = field.contract?.allowedValues {
                Picker(field.label, selection: binding) {
                    Text("—").tag("")
                    ForEach(allowed, id: \.self) { value in
                        Text(value.capitalized).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .disabled(field.isReadOnly)
                .frame(maxWidth: 240)
            }

        case .creatorListEditor:
            Text(fieldValues[field.key] ?? "—")
                .font(ScholiumTypography.scholarly(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Tag Editor

    @ViewBuilder
    private func tagEditor(for field: PropertyEditorField) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            // Current tags
            let tags = parseArray(fieldValues[field.key])
            if !tags.isEmpty {
                FlowLayout(spacing: ScholiumMetrics.Properties.optionSpacing) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: ScholiumMetrics.Properties.tagContentSpacing) {
                            Text(tag)
                                .font(ScholiumTypography.interface(.small))
                            Button {
                                let updated = tags.filter { $0 != tag }
                                fieldValues[field.key] = updated.joined(separator: "; ")
                            } label: {
                                Image(systemName: "xmark")
                                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                            }
                            .buttonStyle(.plain)
                            .scholiumForeground(.secondaryText)
                            .frame(
                                minWidth: ScholiumMetrics.Accessibility.preferredCustomTarget,
                                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
                            )
                            .contentShape(Rectangle())
                            .help("Remove tag \(tag)")
                            .accessibilityLabel("Remove tag \(tag)")
                        }
                        .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
                        .padding(.vertical, ScholiumMetrics.Properties.tagVerticalInset)
                        .background(
                            ScholiumColorRole.raisedSurfaceBackground.color,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    ScholiumColorRole.separator.color,
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }

            // Add tag input
            HStack(spacing: ScholiumMetrics.Properties.fieldSpacing) {
                TextField("Add tag...", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
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
            let items = parseArray(fieldValues[field.key])

            ForEach(items.indices, id: \.self) { idx in
                HStack(spacing: ScholiumMetrics.Properties.fieldSpacing) {
                    TextField("Item \(idx + 1)", text: Binding(
                        get: { items[idx] },
                        set: { newVal in
                            var updated = items
                            updated[idx] = newVal
                            fieldValues[field.key] = updated.joined(separator: "; ")
                        }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        var updated = items
                        updated.remove(at: idx)
                        fieldValues[field.key] = updated.joined(separator: "; ")
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .scholiumForeground(.secondaryText)
                    }
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
                var updated = items
                updated.append("")
                fieldValues[field.key] = updated.joined(separator: "; ")
            } label: {
                Label("Add item", systemImage: "plus.circle")
                    .font(ScholiumTypography.interface(.small))
            }
            .buttonStyle(.borderless)
        }
        .disabled(field.isReadOnly)
    }

    // MARK: - Tag Add Helper

    private func addTag(field: PropertyEditorField) {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var tags = parseArray(fieldValues[field.key])
        if !tags.contains(trimmed) {
            tags.append(trimmed)
            fieldValues[field.key] = tags.joined(separator: "; ")
        }
        tagInput = ""
    }

    // MARK: - Save

    private func saveChanges() {
        let changedFields = allFields.filter { field in
            !field.isReadOnly && fieldValues[field.key] != originalFieldValues[field.key]
        }

        guard !changedFields.isEmpty else {
            closeEditor()
            return
        }

        var proposedFrontmatter = note.frontmatter
        for field in changedFields {
            guard let text = fieldValues[field.key] else { continue }
            proposedFrontmatter = editorModel.updating(
                proposedFrontmatter,
                field: field,
                text: text
            )
        }

        fieldErrors = [:]
        saveError = nil
        let issues = editorModel.validationIssues(
            proposedFrontmatter: proposedFrontmatter,
            changedKeys: Set(changedFields.map(\.key))
        )
        for issue in issues {
            if let key = issue.propertyKey {
                fieldErrors[key] = issue.message
            } else {
                saveError = issue.message
            }
        }
        guard fieldErrors.isEmpty, saveError == nil else { return }

        guard let revision = expectedRevision else {
            saveError = "The editing revision is unavailable. Close and reopen the editor."
            return
        }

        isSaving = true
        Task {
            do {
                try await save(proposedFrontmatter, revision)
                isSaving = false
                closeEditor()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func closeEditor() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    // MARK: - Helpers

    private func frontmatterToString(_ value: YAMLValue) -> String {
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

    private func parseArray(_ value: String?) -> [String] {
        guard let value = value, !value.isEmpty else { return [] }
        return value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = formatter.date(from: string) { return date }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        return fallback.date(from: string)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter.string(from: date)
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sized = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = computeRows(proposal: proposal, sizes: sized)
        let height = rows.reduce(0) { $0 + ($1.map { $0.height }.max() ?? 0) } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var sized: [(CGSize, Int)] = []
        for (i, sv) in subviews.enumerated() {
            sized.append((sv.sizeThatFits(.unspecified), i))
        }
        let rows = computeRows(proposal: proposal, sizes: sized.map { $0.0 })
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
    FrontmatterEditorView(note: .syntheticPreview(
        relativePath: "papers/smith2023.md",
        rawContent: """
        ---
        title: Attention Is All You Need
        authors:
          - family: Smith
          - family: Jones
        publication_date: "2023"
        tags: [attention, nlp]
        ---
        """,
        vaultRole: .sourceCorpus
    )) { _, _ in }
}
