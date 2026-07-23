import ScholiumContracts
import Foundation

/// One field resolved across Core semantics and GUI presentation policy.
/// Unknown vault properties have no Core contract and are edited only through
/// their observed scalar/list shape. Nested mappings remain read-only.
struct PropertyEditorField: Identifiable, Hashable, Sendable {
    var id: String { presentation.key }
    var key: String { presentation.key }
    var label: String { presentation.label }
    var help: String? { presentation.help }
    var group: PropertyPresentationGroup { presentation.group }
    var controlStyle: PropertyControlStyle { presentation.controlStyle }
    var allowedValues: [String]? { contract?.allowedValues }
    let presentation: PropertyPresentation
    let contract: PropertyContract?
    /// The canonical key edited in exact source.
    let sourceKey: String
    let valueKind: PropertyValueKind
    let isReadOnly: Bool
}

/// Pure feature model for the Properties editor. It composes Core contracts
/// with app presentation descriptors and never parses or serializes YAML.
struct PropertyEditorModel: Sendable {
    let note: WindowDocumentLocation
    let profile: SchemaProfileID
    let configuredEditableFields: Set<String>?

    init(note: WindowDocumentLocation, configuredEditableFields: Set<String>? = nil) {
        self.note = note
        self.profile = note.schemaProfile
        self.configuredEditableFields = configuredEditableFields
    }

    var presentFields: [PropertyEditorField] {
        let known = resolvedPresentations.filter {
            $0.key != "research_unit"
                && note.property(at: $0.key) != nil
                && isEditableByConfiguration($0.key)
        }
        let custom = note.frontmatter.keys
            .filter {
                !recognizedKeys.contains($0)
                    && $0 != "research_unit"
                    && isEditableByConfiguration($0)
            }
            .sorted()
            .compactMap { key in
                note.frontmatter[key].map { customField(key: key, value: $0) }
            }
        return known + custom
    }

    var availableFields: [PropertyEditorField] {
        resolvedPresentations.filter {
            $0.key != "research_unit"
                && note.property(at: $0.key) == nil
                && isEditableByConfiguration($0.key)
        }
    }

    var allFields: [PropertyEditorField] { presentFields + availableFields }

    var groupedPresentFields: [(group: PropertyPresentationGroup, fields: [PropertyEditorField])] {
        let grouped = Dictionary(grouping: presentFields, by: \.group)
        return PropertyPresentationGroup.allCases.compactMap { group in
            guard let fields = grouped[group], !fields.isEmpty else { return nil }
            return (group, fields)
        }
    }

    var hiddenPropertyCount: Int {
        return note.frontmatter.keys.count {
            $0 != "research_unit"
                && ResearcherPropertyPolicy.isHidden($0)
        }
    }

    /// Applies one researcher edit to its canonical property key.
    func updating(
        _ frontmatter: [String: YAMLValue],
        field: PropertyEditorField,
        text: String
    ) -> [String: YAMLValue] {
        guard !field.isReadOnly else { return frontmatter }
        var result = frontmatter
        result[field.sourceKey] = value(from: text, kind: field.valueKind)
        return result
    }

    /// Returns Core issues relevant to the deliberate edit. Missing fields in
    /// an older note do not block unrelated edits, but clearing a required
    /// field or triggering a conditional/paired rule does.
    func validationIssues(
        proposedFrontmatter: [String: YAMLValue],
        researchUnitEdit: ResearchUnitEdit?,
        changedKeys: Set<String>
    ) -> [PropertyValidationIssue] {
        let sourceDocument = NoteDocument(
            relativePath: note.relativePath,
            rawContent: note.rawContent
        )
        if !sourceDocument.validationWarnings.isEmpty {
            return PropertyContractCatalog.validate(
                sourceDocument,
                profile: profile,
                context: .creation
            )
        }

        var proposed = proposedFrontmatter
        if let researchUnitEdit {
            switch researchUnitEdit {
            case .set(let completion, let scope, let limitations):
                var mapping: [String: YAMLValue] = [:]
                if let completion {
                    mapping["completion"] = .string(completion.yamlScalar)
                }
                if let scope {
                    mapping["scope"] = .string(scope)
                }
                if !limitations.isEmpty {
                    mapping["limitations"] = .array(limitations.map(YAMLValue.string))
                }
                proposed["research_unit"] = .object(mapping)
            case .remove:
                proposed.removeValue(forKey: "research_unit")
            }
        }

        var relevantKeys = changedKeys
        if researchUnitEdit != nil { relevantKeys.insert("research_unit") }
        for contract in PropertyContractCatalog.contracts(for: profile) {
            for constraint in contract.constraints {
                switch constraint {
                case .pairedWith(let peer):
                    if changedKeys.contains(contract.canonicalKey) { relevantKeys.insert(peer) }
                    if changedKeys.contains(peer) { relevantKeys.insert(contract.canonicalKey) }
                case .requiredWhen(let controllingKey, _):
                    if changedKeys.contains(controllingKey) {
                        relevantKeys.insert(contract.canonicalKey)
                    }
                case .integerRange:
                    break
                }
            }
        }

        return PropertyContractCatalog.validate(
            frontmatter: proposed,
            profile: profile,
            context: .existingDocument
        ).filter { issue in
            guard let key = issue.propertyKey else { return true }
            return relevantKeys.contains(key)
        }
    }

    /// Builds targeted Core edits. `NoteDocument` remains responsible for
    /// applying them to exact source bytes.
    static func frontmatterEdits(
        from original: [String: YAMLValue],
        to proposed: [String: YAMLValue]
    ) -> [String: FrontmatterEditValue] {
        var edits: [String: FrontmatterEditValue] = [:]
        let keys = Set(original.keys).union(proposed.keys)
        for key in keys where key != "research_unit" && original[key] != proposed[key] {
            if let value = proposed[key] {
                edits[key] = editValue(value)
            } else {
                edits[key] = .remove
            }
        }
        return edits
    }

    private var resolvedPresentations: [PropertyEditorField] {
        PropertyPresentationCatalog.presentations(for: profile).compactMap { presentation in
            guard let contract = PropertyPresentationCatalog.contract(
                for: presentation,
                in: profile
            ) else { return nil }
            return PropertyEditorField(
                presentation: presentation,
                contract: contract,
                sourceKey: contract.canonicalKey,
                valueKind: contract.valueKind,
                isReadOnly: contract.ownership != .researcher
                    || !ResearcherPropertyPolicy.isHumanEditable(presentation.key)
            )
        }
    }

    private var recognizedKeys: Set<String> {
        let contracts = PropertyContractCatalog.contracts(for: profile)
        return Set(contracts.map(\.canonicalKey))
    }

    private func isEditableByConfiguration(_ key: String) -> Bool {
        PropertyContractCatalog.contract(for: key, profile: profile)?.ownership != .protectedMachine
            && ResearcherPropertyPolicy.isHumanEditable(key)
            && (configuredEditableFields?.contains(key) ?? true)
    }

    private func customField(key: String, value: YAMLValue) -> PropertyEditorField {
        let kind: PropertyValueKind
        let control: PropertyControlStyle
        let readOnly: Bool
        switch value {
        case .string:
            kind = .text; control = .textField; readOnly = false
        case .integer, .double:
            kind = .number; control = .numberField; readOnly = false
        case .boolean:
            kind = .boolean; control = .toggle; readOnly = false
        case .array:
            kind = key == "tags" ? .tags : .textList
            control = key == "tags" ? .tagEditor : .textListEditor
            readOnly = false
        case .object, .null:
            kind = .mapping; control = .multilineText; readOnly = true
        }
        return PropertyEditorField(
            presentation: PropertyPresentation(
                key: key,
                label: Self.humanized(key),
                help: readOnly
                    ? "Nested YAML is displayed read-only so its exact structure is preserved."
                    : "Custom vault property.",
                group: .other,
                order: 0,
                controlStyle: control
            ),
            contract: nil,
            sourceKey: key,
            valueKind: kind,
            isReadOnly: readOnly
        )
    }

    private func value(from text: String, kind: PropertyValueKind) -> YAMLValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .text, .multilineText, .choice:
            return .string(trimmed)
        case .number:
            if let integer = Int(trimmed) { return .integer(integer) }
            if let double = Double(trimmed) { return .double(double) }
            return .string(trimmed)
        case .date:
            return .string(trimmed)
        case .boolean:
            if trimmed.lowercased() == "true" { return .boolean(true) }
            if trimmed.lowercased() == "false" { return .boolean(false) }
            return .string(trimmed)
        case .tags, .textList:
            return .array(
                trimmed.split(separator: ";")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .map(YAMLValue.string)
            )
        case .mapping:
            // Mappings are read-only except for the dedicated Research Unit
            // editor, which supplies a `ResearchUnitEdit` instead.
            return .string(trimmed)
        }
    }

    private static func editValue(_ value: YAMLValue) -> FrontmatterEditValue {
        switch value {
        case .string(let value): .string(value)
        case .integer(let value): .integer(value)
        case .double(let value): .double(value)
        case .boolean(let value): .boolean(value)
        case .array(let values):
            .array(values.map(\.displayScalar))
        case .object(let values):
            .mapping(values.mapValues(editValue))
        case .null:
            .string("")
        }
    }

    private static func humanized(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
