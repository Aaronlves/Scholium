import ScholiumContracts
import Foundation

/// One researcher-owned portable metadata field resolved across Contracts and
/// GUI presentation policy. It never represents a same-named YAML key.
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
    /// The canonical key edited in the portable metadata record.
    let metadataKey: String
    let valueKind: PropertyValueKind
    let isReadOnly: Bool
    let isRecommended: Bool
    let isTypicalForSourceType: Bool
}

/// Pure feature model for the Metadata editor. Authored YAML and Markdown are
/// intentionally outside this model.
struct PropertyEditorModel: Sendable {
    let note: WindowDocumentLocation
    let profile: SchemaProfileID
    let metadataCatalog: NoteMetadataCatalog
    let analysisSourceTypeOverride: AnalysisSourceType?

    init(
        note: WindowDocumentLocation,
        metadataCatalog: NoteMetadataCatalog,
        analysisSourceTypeOverride: AnalysisSourceType? = nil
    ) {
        self.note = note
        self.profile = note.schemaProfile
        self.metadataCatalog = metadataCatalog
        self.analysisSourceTypeOverride = analysisSourceTypeOverride
    }

    var presentFields: [PropertyEditorField] {
        resolvedPresentations.filter {
            note.managedMetadataValue(named: $0.key) != nil
        }
    }

    var availableFields: [PropertyEditorField] {
        resolvedPresentations.filter {
            note.managedMetadataValue(named: $0.key) == nil
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
              case .string(let raw)? = note.managedMetadataValue(named: "type") else { return nil }
        return AnalysisSourceType(rawValue: raw)
    }

    /// Applies one researcher edit to its canonical property key.
    func updating(
        _ fields: [String: YAMLValue],
        field: PropertyEditorField,
        text: String
    ) -> [String: YAMLValue] {
        guard !field.isReadOnly else { return fields }
        var result = fields
        result[field.metadataKey] = value(from: text, kind: field.valueKind)
        return result
    }

    func updating(
        _ fields: [String: YAMLValue],
        field: PropertyEditorField,
        value: YAMLValue
    ) -> [String: YAMLValue] {
        guard !field.isReadOnly else { return fields }
        var result = fields
        result[field.metadataKey] = value
        return result
    }

    /// Returns Core issues relevant to the deliberate edit. Missing fields in
    /// an older note do not block unrelated edits, but clearing a required
    /// field or triggering a conditional/paired rule does.
    func validationIssues(
        proposedFields: [String: YAMLValue],
        changedKeys: Set<String>
    ) -> [PropertyValidationIssue] {
        return metadataCatalog.validate(
            fields: proposedFields,
            profile: profile
        ).filter { issue in
            guard let key = issue.propertyKey else { return true }
            return changedKeys.contains(key)
        }
    }

    private var resolvedPresentations: [PropertyEditorField] {
        let sourceType = analysisSourceType
        let applicable: Set<String>
        let recommended: Set<String>
        if profile == .analysis, let sourceType {
            let sourceProfile = AnalysisSourceTypeProfileCatalog.profile(for: sourceType)
            applicable = Set(
                metadataCatalog.analysisContracts(for: sourceType).map(\.canonicalKey)
            )
            recommended = Set(sourceProfile.recommendedFieldOrder)
        } else if profile == .analysis {
            let perType = AnalysisSourceType.allCases.map {
                Set(AnalysisSourceTypeProfileCatalog.profile(for: $0).applicableFields)
            }
            applicable = perType.dropFirst().reduce(perType.first ?? []) { $0.intersection($1) }
                .union(["type"])
                .union(metadataCatalog.activeCustomFields(for: .analysis).map(\.key))
            recommended = ["type"]
        } else {
            applicable = Set(metadataCatalog.activeContracts(for: profile).map(\.canonicalKey))
            recommended = []
        }
        return PropertyPresentationCatalog.managedPresentations(
            for: profile,
            catalog: metadataCatalog
        ).compactMap { presentation in
            guard let contract = metadataCatalog.contract(
                for: presentation.key,
                profile: profile
            ) else { return nil }
            let presentValue = note.managedMetadataValue(named: presentation.key)
            let hasEditableValueShape = presentValue.map {
                PropertyContractCatalog.supportsTargetedStructuredEditing(
                    $0,
                    as: contract.valueKind
                )
            } ?? true
            return PropertyEditorField(
                presentation: presentation,
                contract: contract,
                metadataKey: contract.canonicalKey,
                valueKind: contract.valueKind,
                isReadOnly: !hasEditableValueShape,
                isRecommended: recommended.contains(presentation.key),
                isTypicalForSourceType: applicable.contains(presentation.key)
            )
        }
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

}
