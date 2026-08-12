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
    let isRecommended: Bool
    let isTypicalForSourceType: Bool
}

/// Pure feature model for the Properties editor. It composes Core contracts
/// with app presentation descriptors. It probes the targeted patch planner
/// when deciding whether authored source can be edited safely, but never
/// reconstructs writable YAML from projected values.
struct PropertyEditorModel: Sendable {
    let note: WindowDocumentLocation
    let profile: SchemaProfileID
    let analysisSourceTypeOverride: AnalysisSourceType?

    init(
        note: WindowDocumentLocation,
        analysisSourceTypeOverride: AnalysisSourceType? = nil
    ) {
        self.note = note
        self.profile = note.schemaProfile
        self.analysisSourceTypeOverride = analysisSourceTypeOverride
    }

    var presentFields: [PropertyEditorField] {
        let known = resolvedPresentations.filter {
            note.topLevelProperty(named: $0.key) != nil
        }
        let custom = note.frontmatter.keys
            .filter {
                !recognizedKeys.contains($0)
            }
            .sorted()
            .compactMap { key in
                note.frontmatter[key].map { customField(key: key, value: $0) }
            }
        return known + custom
    }

    var availableFields: [PropertyEditorField] {
        resolvedPresentations.filter {
            note.topLevelProperty(named: $0.key) == nil
                && $0.isTypicalForSourceType
        }
    }

    var allFields: [PropertyEditorField] { presentFields + availableFields }

    func canonicalField(for key: String) -> PropertyEditorField? {
        resolvedPresentations.first { $0.key == key }
    }

    var groupedPresentFields: [(group: PropertyPresentationGroup, fields: [PropertyEditorField])] {
        let grouped = Dictionary(grouping: presentFields, by: \.group)
        return PropertyPresentationCatalog.orderedGroups(for: profile).compactMap { group in
            guard let fields = grouped[group], !fields.isEmpty else { return nil }
            return (group, fields)
        }
    }

    var groupedAvailableFields: [(group: PropertyPresentationGroup, fields: [PropertyEditorField])] {
        let grouped = Dictionary(grouping: availableFields, by: \.group)
        return PropertyPresentationCatalog.orderedGroups(for: profile).compactMap { group in
            guard let fields = grouped[group], !fields.isEmpty else { return nil }
            return (
                group,
                fields.sorted {
                    ($0.isRecommended ? 0 : 1, $0.presentation.order)
                        < ($1.isRecommended ? 0 : 1, $1.presentation.order)
                }
            )
        }
    }

    var analysisSourceType: AnalysisSourceType? {
        if let analysisSourceTypeOverride { return analysisSourceTypeOverride }
        guard profile == .analysis,
              case .string(let raw)? = note.topLevelProperty(named: "type") else { return nil }
        return AnalysisSourceType(rawValue: raw)
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

    func updating(
        _ frontmatter: [String: YAMLValue],
        field: PropertyEditorField,
        value: YAMLValue
    ) -> [String: YAMLValue] {
        guard !field.isReadOnly else { return frontmatter }
        var result = frontmatter
        result[field.sourceKey] = value
        return result
    }

    /// Returns Core issues relevant to the deliberate edit. Missing fields in
    /// an older note do not block unrelated edits, but clearing a required
    /// field or triggering a conditional/paired rule does.
    func validationIssues(
        proposedFrontmatter: [String: YAMLValue],
        changedKeys: Set<String>
    ) -> [PropertyValidationIssue] {
        let sourceDocument = NoteDocument(
            relativePath: note.relativePath,
            rawContent: note.rawContent
        )
        if !sourceDocument.validationWarnings.isEmpty {
            return PropertyContractCatalog.validate(
                sourceDocument,
                profile: profile
            )
        }

        return PropertyContractCatalog.validate(
            frontmatter: proposedFrontmatter,
            profile: profile
        ).filter { issue in
            guard let key = issue.propertyKey else { return true }
            return changedKeys.contains(key)
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
        for key in keys where original[key] != proposed[key] {
            if let value = proposed[key] {
                edits[key] = editValue(value)
            } else {
                edits[key] = .remove
            }
        }
        return edits
    }

    private var resolvedPresentations: [PropertyEditorField] {
        let sourceType = analysisSourceType
        let applicable: Set<String>
        let recommended: Set<String>
        if profile == .analysis, let sourceType {
            let sourceProfile = AnalysisSourceTypeProfileCatalog.profile(for: sourceType)
            applicable = Set(sourceProfile.applicableFields)
            recommended = Set(sourceProfile.recommendedFieldOrder)
        } else if profile == .analysis {
            let perType = AnalysisSourceType.allCases.map {
                Set(AnalysisSourceTypeProfileCatalog.profile(for: $0).applicableFields)
            }
            applicable = perType.dropFirst().reduce(perType.first ?? []) { $0.intersection($1) }
                .union(["type"])
            recommended = ["type"]
        } else {
            applicable = Set(PropertyContractCatalog.contracts(for: profile).map(\.canonicalKey))
            recommended = []
        }
        return PropertyPresentationCatalog.presentations(for: profile).compactMap { presentation in
            guard let contract = PropertyPresentationCatalog.contract(
                for: presentation,
                in: profile
            ) else { return nil }
            let presentValue = note.topLevelProperty(named: presentation.key)
            let hasEditableSourceShape = presentValue.map {
                PropertyContractCatalog.supportsTargetedStructuredEditing(
                    $0,
                    as: contract.valueKind
                ) && sourceCanTarget(
                    key: presentation.key,
                    value: $0,
                    kind: contract.valueKind
                )
            } ?? true
            return PropertyEditorField(
                presentation: presentation,
                contract: contract,
                sourceKey: contract.canonicalKey,
                valueKind: contract.valueKind,
                isReadOnly: !hasEditableSourceShape,
                isRecommended: recommended.contains(presentation.key),
                isTypicalForSourceType: applicable.contains(presentation.key)
            )
        }
    }

    private var recognizedKeys: Set<String> {
        let contracts = PropertyContractCatalog.contracts(for: profile)
        return Set(contracts.map(\.canonicalKey))
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
        case .array(let values):
            let isStringList = values.allSatisfy {
                if case .string = $0 { true } else { false }
            }
            if isStringList {
                kind = key == "tags" ? .tags : .textList
                control = key == "tags" ? .tagEditor : .textListEditor
                readOnly = false
            } else {
                kind = .mapping; control = .multilineText; readOnly = true
            }
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
                || !sourceCanTarget(key: key, value: value, kind: kind),
            isRecommended: false,
            isTypicalForSourceType: true
        )
    }

    private func value(from text: String, kind: PropertyValueKind) -> YAMLValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .text, .multilineText, .choice:
            return .string(text)
        case .number:
            if let integer = Int(trimmed) { return .integer(integer) }
            if let double = Double(trimmed) { return .double(double) }
            return .string(trimmed)
        case .date:
            return .string(text)
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
            return .string(trimmed)
        case .creatorList:
            // CreatorList uses its dedicated structured control. This scalar
            // fallback is never used for a writable creator field.
            return .string(trimmed)
        }
    }

    private func sourceCanTarget(
        key: String,
        value: YAMLValue,
        kind: PropertyValueKind
    ) -> Bool {
        let expectsString = switch kind {
        case .text, .multilineText, .date, .choice: true
        case .number, .boolean, .textList, .tags, .mapping, .creatorList: false
        }
        if expectsString,
           let token = note.authoredTopLevelScalarToken(named: key),
           FrontmatterPatchPlanner.isTimestampScalarToken(token) {
            return false
        }
        let document = NoteDocument(
            relativePath: note.relativePath,
            rawContent: note.rawContent
        )
        guard document.frontmatterState == .valid,
              let probe = Self.probeEdit(for: value, kind: kind) else { return false }
        return (try? document.applying(
            .frontmatter([key: probe]),
            timestampKey: nil
        )) != nil
    }

    private static func probeEdit(
        for value: YAMLValue,
        kind: PropertyValueKind
    ) -> FrontmatterEditValue? {
        switch (kind, value) {
        case (.text, .string(let text)),
             (.multilineText, .string(let text)),
             (.date, .string(let text)),
             (.choice, .string(let text)):
            return .string(text + "__scholium_probe__")
        case (.number, .integer(let number)):
            return .integer(number == 0 ? 1 : 0)
        case (.number, .double(let number)):
            return .double(number == 0 ? 1 : 0)
        case (.boolean, .boolean(let flag)):
            return .boolean(!flag)
        case (.tags, .array(let values)), (.textList, .array(let values)):
            let strings = values.compactMap { value -> String? in
                guard case .string(let text) = value else { return nil }
                return text
            }
            guard strings.count == values.count else { return nil }
            return .array(strings + ["__scholium_probe__"])
        case (.creatorList, .array(let values)):
            return .sequence(
                values.map(editValue)
                    + [.mapping(["family": .string("__scholium_probe__")])]
            )
        case (.mapping, .object(let values)):
            var mapping = values.mapValues(editValue)
            mapping["__scholium_probe__"] = .string("probe")
            return .mapping(mapping)
        default:
            return nil
        }
    }

    private static func editValue(_ value: YAMLValue) -> FrontmatterEditValue {
        switch value {
        case .string(let value): .string(value)
        case .integer(let value): .integer(value)
        case .double(let value): .double(value)
        case .boolean(let value): .boolean(value)
        case .array(let values):
            if values.allSatisfy({ if case .string = $0 { true } else { false } }) {
                .array(values.map(\.displayScalar))
            } else {
                .sequence(values.map(editValue))
            }
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
