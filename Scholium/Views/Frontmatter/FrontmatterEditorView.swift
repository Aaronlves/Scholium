import SwiftUI
import ScholiumCore

// MARK: - Properties Editor

/// Schema-aware sheet for editing a note's frontmatter.
struct FrontmatterEditorView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let note: Note

    @State private var fieldValues: [String: String] = [:]
    @State private var originalFieldValues: [String: String] = [:]
    @State private var fieldErrors: [String: String] = [:]
    @State private var tagInput: String = ""
    @State private var isSaving = false
    @State private var resolvedCitation: String?
    @State private var expectedRevision: DocumentFingerprint?
    @State private var saveError: String?
    @State private var showAvailableProperties = false

    private var schema: FrontmatterSchema {
        FrontmatterSchema.schema(for: note)
    }

    /// `nil` is the compatibility policy for notes outside a classified
    /// Triptych vault. An empty set is a deliberate vault-wide choice to make
    /// no fields editable through structured controls.
    private var configuredEditableFields: Set<String>? {
        appState.currentPropertiesConfiguration.map { Set($0.editableFields) }
    }

    private var presentFields: [FrontmatterSchema.FieldDefinition] {
        let known = schema.fields.filter {
            note.property(at: $0.key) != nil
                && ResearcherPropertyPolicy.isHumanEditable($0.key)
                && (configuredEditableFields?.contains($0.key) ?? true)
        }
        let knownKeys = Set(schema.fields.map(\.key))
        let legacyKeys = Set(schema.fields.flatMap { TriptychProperty.legacyAliases[$0.key] ?? [] })
        let custom = note.frontmatter.keys
            .filter {
                !knownKeys.contains($0)
                    && !legacyKeys.contains($0)
                    && ResearcherPropertyPolicy.isHumanEditable($0)
                    && (configuredEditableFields?.contains($0) ?? true)
            }
            .sorted()
            .compactMap { key in
                note.frontmatter[key].map { inferredField(key: key, value: $0) }
            }
        return known + custom
    }

    private var availableFields: [FrontmatterSchema.FieldDefinition] {
        return schema.fields.filter {
            note.property(at: $0.key) == nil
                && ResearcherPropertyPolicy.isHumanEditable($0.key)
                && (configuredEditableFields?.contains($0.key) ?? true)
        }
    }

    private var allFields: [FrontmatterSchema.FieldDefinition] {
        presentFields + availableFields
    }

    private var missingRequiredFields: [FrontmatterSchema.FieldDefinition] {
        availableFields.filter(\.required)
    }

    private var groupedPresentFields: [(name: String, fields: [FrontmatterSchema.FieldDefinition])] {
        let order = ["About", "Source", "Progress", "Use", "History", "Other"]
        let grouped = Dictionary(grouping: presentFields, by: { category(for: $0.key) })
        return order.compactMap { name in
            guard let fields = grouped[name], !fields.isEmpty else { return nil }
            return (name, fields)
        }
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
                    Button("Cancel") { dismiss() }
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
                    if !missingRequiredFields.isEmpty {
                        Label(
                            "This note uses an older property set. You can edit its existing properties now and add newer schema properties when useful.",
                            systemImage: "info.circle"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Text("Researcher Properties")
                        .font(.headline)

                    if allFields.isEmpty {
                        Label(
                            "No fields are enabled for structured editing in this vault. Change the vault-wide allowlist in Settings, or use Source mode to edit exact YAML.",
                            systemImage: "lock"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }

                    if hiddenPropertyCount > 0 {
                        Label(
                            "\(hiddenPropertyCount) machine or legacy propert\(hiddenPropertyCount == 1 ? "y is" : "ies are") preserved in Source mode.",
                            systemImage: "gearshape.2"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    ForEach(groupedPresentFields, id: \.name) { group in
                        GroupBox(group.name) {
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
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("\(fieldErrors.count) validation error\(fieldErrors.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // Initialize field values from existing frontmatter
            for (key, value) in note.frontmatter {
                let stringValue = frontmatterToString(value)
                fieldValues[key] = stringValue
                originalFieldValues[key] = stringValue
            }
            for field in schema.fields where fieldValues[field.key] == nil {
                guard let value = note.property(at: field.key) else { continue }
                let stringValue = frontmatterToString(value)
                fieldValues[field.key] = stringValue
                originalFieldValues[field.key] = stringValue
            }
            expectedRevision = appState.documentRevisions[note.relativePath]
            // Resolve Zotero citation
            if let zoteroKey = note.zoteroKey {
                do {
                    if let citation = try await appState.zoteroBridge.resolveCitation(zoteroKey: zoteroKey) {
                        resolvedCitation = citation.inlineCitation
                    }
                } catch {
                    // Citation not resolved
                }
            }
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
        let legacyKeys = Set(schema.fields.flatMap { TriptychProperty.legacyAliases[$0.key] ?? [] })
        return note.frontmatter.keys.count {
            ResearcherPropertyPolicy.isHidden($0) || legacyKeys.contains($0)
        }
    }

    private func category(for key: String) -> String {
        switch key {
        case "title", "authors", "year", "type", "aliases", "note_type", "project_role", "claim_type", "project", "target", "primary_level", "main_topic", "related_topics", "tags":
            "About"
        case "access", "text_reliability", "locators", "doi", "audit":
            "Source"
        case "analysis_mode", "status", "reviewed", "settlement_dimensions", "settlement_degree", "review_status", "confidence":
            "Progress"
        case "relevance", "dissertation_role", "dissertation_claim_links", "revision_relation", "cui_kb_integration", "follow_up", "venue", "deadline", "prose_permission", "reopen_condition", "privacy":
            "Use"
        case "created", "updated", "dissertation_updated_at", "last_reviewed":
            "History"
        default:
            "Other"
        }
    }

    // MARK: - Field Editors

    @ViewBuilder
    private func fieldEditor(for field: FrontmatterSchema.FieldDefinition) -> some View {
        let hasError = fieldErrors[field.key] != nil

        VStack(alignment: .leading, spacing: 6) {
            // Label
            HStack(spacing: 5) {
                Text(field.label)
                    .font(.callout)
                    .fontWeight(.medium)
                if field.required {
                    Text("*")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .fontWeight(.bold)
                }
                if field.autoFilled {
                    Text(isPreservedReadOnly(field) ? "Read only" : "Managed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }

            // Description
            if let desc = field.description {
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
                .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func editorContent(
        for field: FrontmatterSchema.FieldDefinition,
        binding: Binding<String>,
        hasError: Bool
    ) -> some View {
        switch field.type {
        case .string, .doi:
            TextField(field.label, text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(field.autoFilled)

        case .text:
            TextEditor(text: binding)
                .font(ScholiumTypography.swiftUIMonospaceFont(
                    size: ScholiumTypography.sourceBodySize,
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
                        .stroke(hasError ? Color.red : Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .disabled(field.autoFilled)

        case .number:
            TextField(field.label, text: binding)
                .textFieldStyle(.roundedBorder)
                .disabled(field.autoFilled)

        case .date:
            if field.autoFilled {
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

        case .boolean:
            Toggle(isOn: Binding(
                get: { fieldValues[field.key]?.lowercased() == "true" },
                set: { fieldValues[field.key] = $0 ? "true" : "false" }
            )) {
                Text(field.label)
                    .font(.callout)
            }
            .disabled(field.autoFilled)

        case .tags:
            tagEditor(for: field)

        case .array:
            arrayEditor(for: field)

        case .enum:
            if let allowed = field.allowedValues {
                Picker(field.label, selection: binding) {
                    Text("—").tag("")
                    ForEach(allowed, id: \.self) { value in
                        Text(value.capitalized).tag(value)
                    }
                }
                .pickerStyle(.menu)
                .disabled(field.autoFilled)
                .frame(maxWidth: 240)
            }

        case .zoteroKey:
            VStack(alignment: .leading, spacing: 6) {
                TextField("Zotero item key", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(field.autoFilled)

                if let citation = resolvedCitation {
                    HStack(spacing: 5) {
                        Image(systemName: "books.vertical")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(citation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if !binding.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        Task { await appState.zoteroBridge.openInZotero(zoteroKey: binding.wrappedValue) }
                    } label: {
                        Label("Open in Zotero", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    // MARK: - Tag Editor

    @ViewBuilder
    private func tagEditor(for field: FrontmatterSchema.FieldDefinition) -> some View {
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
                .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .disabled(field.autoFilled)
    }

    // MARK: - Array Editor

    @ViewBuilder
    private func arrayEditor(for field: FrontmatterSchema.FieldDefinition) -> some View {
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
        .disabled(field.autoFilled)
    }

    // MARK: - Tag Add Helper

    private func addTag(field: FrontmatterSchema.FieldDefinition) {
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
            !field.autoFilled && fieldValues[field.key] != originalFieldValues[field.key]
        }

        guard !changedFields.isEmpty else {
            dismiss()
            return
        }

        // Validate
        fieldErrors = [:]
        for field in changedFields {
            let value = fieldValues[field.key]?.trimmingCharacters(in: .whitespaces) ?? ""
            if field.required && value.isEmpty {
                fieldErrors[field.key] = "\(field.label) is required"
            }
            if field.type == .enum, let allowed = field.allowedValues, !value.isEmpty {
                if !allowed.contains(value) {
                    fieldErrors[field.key] = "Must be one of: \(allowed.joined(separator: ", "))"
                }
            }
            if field.key == "relevance", !value.isEmpty {
                guard let rating = Int(value), (1...10).contains(rating) else {
                    fieldErrors[field.key] = "Must be a whole number from 1 to 10"
                    continue
                }
            }
        }

        guard fieldErrors.isEmpty else { return }

        // Build updated frontmatter
        isSaving = true
        var updatedNote = note
        let noteSchema = FrontmatterSchema.schema(for: note)

        Task {
            for field in changedFields {
                guard let stringValue = fieldValues[field.key] else { continue }
                let frontmatterValue = stringToFrontmatter(stringValue, type: field.type)
                if let value = frontmatterValue {
                    do {
                        updatedNote.frontmatter = try await appState.frontmatterService.updateField(
                            field.key, value: value, in: updatedNote.frontmatter, schema: noteSchema
                        )
                        for legacyKey in TriptychProperty.legacyAliases[field.key] ?? [] {
                            updatedNote.frontmatter.removeValue(forKey: legacyKey)
                        }
                    } catch {
                        fieldErrors[field.key] = error.localizedDescription
                        isSaving = false
                        return
                    }
                }
            }

            guard let revision = expectedRevision else {
                saveError = "The editing revision is unavailable. Close and reopen the editor."
                isSaving = false
                return
            }
            do {
                _ = try await appState.saveNote(updatedNote, expectedRevision: revision)
                appState.showToast("Frontmatter saved")
                isSaving = false
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    // MARK: - Helpers

    private func frontmatterToString(_ value: FrontmatterValue) -> String {
        switch value {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .date(let d): return formatDate(d)
        case .array(let arr): return arr.joined(separator: "; ")
        case .dictionary(let dict): return dict.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        }
    }

    private func inferredField(
        key: String,
        value: FrontmatterValue
    ) -> FrontmatterSchema.FieldDefinition {
        let type: FrontmatterSchema.FieldDefinition.FieldType
        let readOnly: Bool
        switch value {
        case .string: type = .string; readOnly = false
        case .int, .double: type = .number; readOnly = false
        case .bool: type = .boolean; readOnly = false
        case .date: type = .date; readOnly = false
        case .array: type = key == "tags" ? .tags : .array; readOnly = false
        case .dictionary: type = .text; readOnly = true
        }
        return FrontmatterSchema.FieldDefinition(
            key: key,
            label: key.replacingOccurrences(of: "_", with: " ").capitalized,
            type: type,
            required: false,
            autoFilled: readOnly,
            description: readOnly ? "Nested YAML is displayed read-only so its exact structure is preserved." : "Custom vault property.",
            allowedValues: nil
        )
    }

    private func isPreservedReadOnly(_ field: FrontmatterSchema.FieldDefinition) -> Bool {
        guard let value = note.frontmatter[field.key] else { return false }
        if case .dictionary = value { return true }
        return false
    }

    private func stringToFrontmatter(_ string: String, type: FrontmatterSchema.FieldDefinition.FieldType) -> FrontmatterValue? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        switch type {
        case .string, .text, .doi, .zoteroKey:
            return .string(trimmed)
        case .number:
            if let intVal = Int(trimmed) { return .int(intVal) }
            if let doubleVal = Double(trimmed) { return .double(doubleVal) }
            return .string(trimmed)
        case .boolean:
            return .bool(trimmed.lowercased() == "true")
        case .date:
            if let date = parseDate(trimmed) { return .date(date) }
            return .string(trimmed)
        case .tags, .array:
            let items = trimmed.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return .array(items)
        case .enum:
            return .string(trimmed)
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
    FrontmatterEditorView(note: Note(
        relativePath: "papers/smith2023.md",
        frontmatter: [
            "title": .string("Attention Is All You Need"),
            "authors": .array(["Smith", "Jones"]),
            "year": .int(2023),
            "tags": .array(["attention", "nlp"]),
            "status": .string("analyzed"),
        ],
        body: "",
        rawContent: ""
    ))
    .environmentObject(AppState())
}
