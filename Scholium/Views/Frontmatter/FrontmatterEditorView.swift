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
        ResearchUnitEdit?,
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
    @State private var researchUnitCompletion = ""
    @State private var originalResearchUnitCompletion = ""
    @State private var researchUnitScope = ""
    @State private var originalResearchUnitScope = ""
    @State private var researchUnitLimitationsText = ""
    @State private var originalResearchUnitLimitationsText = ""
    @State private var researchUnitWasInvalid = false

    init(
        note: WindowDocumentLocation,
        configuredEditableFields: Set<String>? = nil,
        expectedRevision: DocumentFingerprint? = nil,
        onClose: (@MainActor () -> Void)? = nil,
        save: @escaping @MainActor (
            [String: YAMLValue],
            ResearchUnitEdit?,
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
                VStack(alignment: .leading, spacing: 3) {
                    Text("Properties")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(note.title ?? note.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
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
                    .tint(.accentColor)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(isSaving)
                }
            }
            .padding(20)

            Divider()

            // Form fields
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Researcher Properties")
                        .font(.headline)

                    if supportsResearchUnit {
                        researchUnitEditor
                    }

                    if allFields.isEmpty {
                        Label(
                            "No other fields are enabled for structured editing in this vault. Change the vault-wide allowlist in Settings, or use Source mode to edit exact YAML.",
                            systemImage: "lock"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }

                    if hiddenPropertyCount > 0 {
                        Group {
                            if hiddenPropertyCount == 1 {
                                Label(
                                    "One machine or custom property is preserved in Source mode.",
                                    systemImage: "gearshape.2"
                                )
                            } else {
                                Label(
                                    "\(hiddenPropertyCount) machine or custom properties are preserved in Source mode.",
                                    systemImage: "gearshape.2"
                                )
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    ForEach(groupedPresentFields, id: \.group) { group in
                        GroupBox(group.group.label) {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(group.fields) { field in
                                    fieldEditor(for: field)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                    }

                    if !availableFields.isEmpty {
                        Divider()
                            .padding(.vertical, 4)

                        DisclosureGroup("Add a Property", isExpanded: $showAvailableProperties) {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(availableFields) { field in
                                    fieldEditor(for: field)
                                }
                            }
                            .padding(.top, 12)
                        }
                        .font(.headline)
                    }
                }
                .padding(20)
            }

            // Footer with validation summary
            if !fieldErrors.isEmpty {
                Divider()
                    .opacity(0.5)

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .scholiumForeground(.destructive)
                        .font(.caption)
                    Text("\(fieldErrors.count) validation error\(fieldErrors.count == 1 ? "" : "s")")
                        .font(.caption)
                        .scholiumForeground(.destructive)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
            let declaration = note.researchUnit
            switch declaration.state {
            case .absent:
                break
            case .declared:
                researchUnitCompletion = declaration.completion?.yamlScalar ?? ""
                originalResearchUnitCompletion = researchUnitCompletion
                researchUnitScope = declaration.scope ?? ""
                originalResearchUnitScope = researchUnitScope
                researchUnitLimitationsText = declaration.limitations.joined(separator: "\n")
                originalResearchUnitLimitationsText = researchUnitLimitationsText
            case .invalid:
                researchUnitWasInvalid = true
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

    private var hiddenPropertyCount: Int {
        editorModel.hiddenPropertyCount
    }

    private var supportsResearchUnit: Bool {
        guard PropertyContractCatalog.contract(
            for: "research_unit",
            profile: note.schemaProfile
        ) != nil else { return false }
        return configuredEditableFields?.contains("research_unit") ?? true
    }

    private var researchUnitLimitations: [String] {
        researchUnitLimitationsText
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var researchUnitHasChanges: Bool {
        researchUnitCompletion != originalResearchUnitCompletion
            || researchUnitScope != originalResearchUnitScope
            || researchUnitLimitationsText != originalResearchUnitLimitationsText
    }

    @ViewBuilder
    private var researchUnitEditor: some View {
        GroupBox("Research Unit") {
            VStack(alignment: .leading, spacing: 10) {
                Text(researchUnitHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if researchUnitWasInvalid {
                    Label(
                        "The existing Research Unit is not valid for this note role. Source mode preserves its exact YAML; changing these fields will replace it with a valid declaration.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .scholiumForeground(.attention)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if note.schemaProfile == .analysis {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Completion")
                            .font(.callout.weight(.medium))
                        TextField("complete, incomplete, or 6/11", text: $researchUnitCompletion)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Analysis completion")
                            .accessibilityIdentifier("scholium.properties.researchUnitCompletion")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(note.schemaProfile == .draftProject ? "Research Scope" : "Scope")
                            .font(.callout.weight(.medium))
                        TextField("Describe the boundary of this note's research", text: $researchUnitScope)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel(note.schemaProfile == .draftProject ? "Research Scope" : "Scope")
                            .accessibilityIdentifier("scholium.properties.researchUnitScope")
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Limitations")
                        .font(.callout.weight(.medium))
                    Text("One material boundary per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $researchUnitLimitationsText)
                        .font(.body)
                        .frame(minHeight: 70)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                        .accessibilityLabel("Research Unit Limitations")
                }

                if let error = fieldErrors["research_unit"] {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .scholiumForeground(.destructive)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    // MARK: - Field Editors

    @ViewBuilder
    private func fieldEditor(for field: PropertyEditorField) -> some View {
        let hasError = fieldErrors[field.key] != nil

        VStack(alignment: .leading, spacing: 6) {
            // Label
            HStack(spacing: 5) {
                Text(field.label)
                    .font(.callout)
                    .fontWeight(.medium)
                if field.isReadOnly {
                    Text("Read only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }

            // Description
            if let desc = field.help {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)
                    Text(error)
                        .font(.caption2)
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
                .font(ScholiumTypography.swiftUIMonospaceFont(
                    size: ScholiumTypography.exactSourcePointSize,
                    relativeTo: .body
                ))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            hasError
                                ? ScholiumColorRole.destructive.color
                                : Color.secondary.opacity(0.2),
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
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
                    .font(.callout)
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

        case .researchUnit:
            EmptyView()
        }
    }

    // MARK: - Tag Editor

    @ViewBuilder
    private func tagEditor(for field: PropertyEditorField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current tags
            let tags = parseArray(fieldValues[field.key])
            if !tags.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text(tag)
                                .font(.caption)
                            Button {
                                let updated = tags.filter { $0 != tag }
                                fieldValues[field.key] = updated.joined(separator: "; ")
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .frame(
                                minWidth: ScholiumMetrics.Accessibility.preferredCustomTarget,
                                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
                            )
                            .contentShape(Rectangle())
                            .help("Remove tag \(tag)")
                            .accessibilityLabel("Remove tag \(tag)")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Color.accentColor.opacity(0.12),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
            }

            // Add tag input
            HStack(spacing: 6) {
                TextField("Add tag...", text: $tagInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addTag(field: field)
                    }
                Button {
                    addTag(field: field)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
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
        VStack(alignment: .leading, spacing: 6) {
            let items = parseArray(fieldValues[field.key])

            ForEach(items.indices, id: \.self) { idx in
                HStack(spacing: 6) {
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
                            .foregroundStyle(.secondary)
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
                    .font(.caption)
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
        let hasResearchUnitChanges = researchUnitHasChanges

        guard !changedFields.isEmpty || hasResearchUnitChanges else {
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

        let researchUnitEdit: ResearchUnitEdit?
        if hasResearchUnitChanges {
            let completionText = researchUnitCompletion.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let completion: AnalysisCompletion?
            if completionText.isEmpty {
                completion = nil
            } else if let parsed = AnalysisCompletion(yamlScalar: completionText) {
                completion = parsed
            } else {
                fieldErrors = [
                    "research_unit": "Completion must be complete, incomplete, or a valid completed/total ratio."
                ]
                return
            }

            let trimmedScope = researchUnitScope.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let scope = trimmedScope.isEmpty ? nil : trimmedScope
            researchUnitEdit = completion == nil
                && scope == nil
                && researchUnitLimitations.isEmpty
                ? .remove
                : .set(
                    completion: completion,
                    scope: scope,
                    limitations: researchUnitLimitations
                )
        } else {
            researchUnitEdit = nil
        }

        fieldErrors = [:]
        saveError = nil
        let issues = editorModel.validationIssues(
            proposedFrontmatter: proposedFrontmatter,
            researchUnitEdit: researchUnitEdit,
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
                try await save(proposedFrontmatter, researchUnitEdit, revision)
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

    private var researchUnitHelp: String {
        switch note.schemaProfile {
        case .analysis:
            "Record how much source material this Analysis represents and any material limitations. Completion does not judge analytical adequacy."
        case .topicMarkdown:
            "Describe the Topic's conceptual or debate scope and any material limitations."
        case .draftProject:
            "Describe this Work's Research Scope and any material limitations."
        case .genericMarkdown:
            "This note role does not define a Research Unit."
        }
    }

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
        authors: [Smith, Jones]
        year: 2023
        tags: [attention, nlp]
        research_unit:
          completion: 6/11
        ---
        """,
        vaultRole: .sourceCorpus
    )) { _, _, _ in }
}
