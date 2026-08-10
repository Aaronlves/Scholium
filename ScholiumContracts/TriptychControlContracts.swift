import Foundation

/// Portable identity and configuration for one Scholium Triptych.
///
/// The manifest deliberately stores no absolute paths or security-scoped
/// bookmarks. Those machine-local values remain in Application Support.
public struct TriptychManifest: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public var vaultIDs: [WorkspaceVaultSlot: UUID]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        vaultIDs: [WorkspaceVaultSlot: UUID],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.vaultIDs = vaultIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VaultPropertiesConfiguration: Codable, Hashable, Sendable {
    /// Exact delimiter-free YAML copied into future managed notes for this
    /// role. `nil` means managed creation remains YAML-free unless typed
    /// creation metadata supplies properties.
    public var newNoteYAML: String? {
        didSet { newNoteYAML = Self.normalizedNewNoteYAML(newNoteYAML) }
    }

    /// Fields shown by the collapsed Properties projection, in display order.
    public var visibleFields: [String] {
        didSet { visibleFields = Self.unique(visibleFields) }
    }

    /// Top-level YAML fields the researcher may change through structured
    /// controls. Exact Source editing remains a separate, unrestricted mode.
    public var editableFields: [String] {
        didSet { editableFields = Self.unique(editableFields) }
    }

    public init(
        newNoteYAML: String? = nil,
        visibleFields: [String] = [],
        editableFields: [String] = []
    ) {
        self.newNoteYAML = Self.normalizedNewNoteYAML(newNoteYAML)
        self.visibleFields = Self.unique(visibleFields)
        self.editableFields = Self.unique(editableFields)
    }

    private enum CodingKeys: String, CodingKey {
        case newNoteYAML
        case visibleFields
        case editableFields
    }

    /// Decoding deliberately retains current-schema bytes semantically as
    /// authored. The shared settings validator, rather than synthesized
    /// Codable or property observers, decides whether they need review.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        newNoteYAML = try container.decodeIfPresent(String.self, forKey: .newNoteYAML)
        visibleFields = try container.decode([String].self, forKey: .visibleFields)
        editableFields = try container.decode([String].self, forKey: .editableFields)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(newNoteYAML, forKey: .newNoteYAML)
        try container.encode(visibleFields, forKey: .visibleFields)
        try container.encode(editableFields, forKey: .editableFields)
    }

    /// Adds or removes a field without losing the explicit order of the
    /// remaining visible fields.
    public mutating func setVisible(_ isVisible: Bool, field: String) {
        guard let field = Self.normalized(field) else { return }
        if isVisible {
            if !visibleFields.contains(field) { visibleFields.append(field) }
        } else {
            visibleFields.removeAll { $0 == field }
        }
    }

    /// Moves one visible field to a bounded destination while preserving all
    /// other relative ordering.
    public mutating func moveVisibleField(_ field: String, to destinationIndex: Int) {
        guard let sourceIndex = visibleFields.firstIndex(of: field) else { return }
        let value = visibleFields.remove(at: sourceIndex)
        let boundedIndex = min(max(0, destinationIndex), visibleFields.count)
        visibleFields.insert(value, at: boundedIndex)
    }

    public mutating func setHumanEditable(_ isEditable: Bool, field: String) {
        guard let field = Self.normalized(field) else { return }
        if isEditable {
            if !editableFields.contains(field) { editableFields.append(field) }
        } else {
            editableFields.removeAll { $0 == field }
        }
    }

    private static func unique(_ fields: [String]) -> [String] {
        var seen: Set<String> = []
        return fields.compactMap { field in
            guard let normalized = normalized(field),
                  seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private static func normalized(_ field: String) -> String? {
        let normalized = field.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func normalizedNewNoteYAML(_ source: String?) -> String? {
        guard var source else { return nil }
        source = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if !source.hasSuffix("\n") { source += "\n" }
        return source
    }
}

public struct AnalysisAgentCreationConfiguration: Codable, Hashable, Sendable {
    public var requiredFieldsBySourceType: [AnalysisSourceType: [String]] {
        didSet { requiredFieldsBySourceType = Self.normalized(requiredFieldsBySourceType) }
    }

    public init(requiredFieldsBySourceType: [AnalysisSourceType: [String]] = [:]) {
        self.requiredFieldsBySourceType = Self.normalized(requiredFieldsBySourceType)
    }

    private enum CodingKeys: String, CodingKey {
        case requiredFieldsBySourceType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requiredFieldsBySourceType = try container.decode(
            [AnalysisSourceType: [String]].self,
            forKey: .requiredFieldsBySourceType
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requiredFieldsBySourceType, forKey: .requiredFieldsBySourceType)
    }

    public func requiredFields(for sourceType: AnalysisSourceType) -> [String] {
        requiredFieldsBySourceType[sourceType] ?? []
    }

    private static func normalized(
        _ fields: [AnalysisSourceType: [String]]
    ) -> [AnalysisSourceType: [String]] {
        fields.reduce(into: [:]) { result, entry in
            var seen: Set<String> = []
            let values = entry.value.compactMap { raw -> String? in
                let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, seen.insert(key).inserted else { return nil }
                return key
            }
            if !values.isEmpty { result[entry.key] = values }
        }
    }
}

public struct TriptychSettings: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public var properties: [WorkspaceVaultSlot: VaultPropertiesConfiguration] {
        didSet { properties = Self.completeProperties(properties) }
    }
    public var analysisAgentCreation: AnalysisAgentCreationConfiguration
    public var promptTemplates: [ResearchPromptTemplate]
    public var activePromptTemplateIDs: [ResearchPromptKind: UUID]
    public var attentionDismissalDays: Int

    public init(
        properties: [WorkspaceVaultSlot: VaultPropertiesConfiguration] = Self.defaultProperties,
        analysisAgentCreation: AnalysisAgentCreationConfiguration = .init(),
        promptTemplates: [ResearchPromptTemplate]? = nil,
        activePromptTemplateIDs: [ResearchPromptKind: UUID]? = nil,
        attentionDismissalDays: Int = 7
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.properties = Self.completeProperties(properties)
        self.analysisAgentCreation = analysisAgentCreation
        var templates = promptTemplates ?? [.defaultDialogue, .defaultCritique]
        let activeIDs = activePromptTemplateIDs ?? [
            .dialogue: ResearchPromptTemplate.defaultDialogue.id,
            .critique: ResearchPromptTemplate.defaultCritique.id,
        ]
        for kind in ResearchPromptKind.allCases {
            let bundled = kind == .dialogue
                ? ResearchPromptTemplate.defaultDialogue
                : ResearchPromptTemplate.defaultCritique
            guard let index = templates.firstIndex(where: { $0.id == bundled.id }) else { continue }
            templates[index] = bundled
        }
        self.promptTemplates = Self.completeTemplates(templates)
        self.activePromptTemplateIDs = activeIDs
        self.attentionDismissalDays = max(1, attentionDismissalDays)
        repairActiveTemplateIDs()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case properties
        case analysisAgentCreation
        case promptTemplates
        case activePromptTemplateIDs
        case attentionDismissalDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported Triptych settings schema \(schemaVersion)."
            )
        }
        let properties = try container.decode(
            [WorkspaceVaultSlot: VaultPropertiesConfiguration].self,
            forKey: .properties
        )
        guard Set(properties.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw DecodingError.dataCorruptedError(
                forKey: .properties,
                in: container,
                debugDescription: "Properties settings must contain exactly all Triptych roles."
            )
        }
        self.schemaVersion = schemaVersion
        self.properties = properties
        analysisAgentCreation = try container.decode(
            AnalysisAgentCreationConfiguration.self,
            forKey: .analysisAgentCreation
        )
        promptTemplates = try container.decode(
            [ResearchPromptTemplate].self,
            forKey: .promptTemplates
        )
        activePromptTemplateIDs = try container.decode(
            [ResearchPromptKind: UUID].self,
            forKey: .activePromptTemplateIDs
        )
        attentionDismissalDays = try container.decode(
            Int.self,
            forKey: .attentionDismissalDays
        )
        for bundled in [ResearchPromptTemplate.defaultDialogue, .defaultCritique] {
            if let index = promptTemplates.firstIndex(where: { $0.id == bundled.id }) {
                promptTemplates[index] = bundled
            }
        }
        promptTemplates = Self.completeTemplates(promptTemplates)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(properties, forKey: .properties)
        try container.encode(analysisAgentCreation, forKey: .analysisAgentCreation)
        try container.encode(promptTemplates, forKey: .promptTemplates)
        try container.encode(activePromptTemplateIDs, forKey: .activePromptTemplateIDs)
        try container.encode(attentionDismissalDays, forKey: .attentionDismissalDays)
    }

    public static let defaultProperties: [WorkspaceVaultSlot: VaultPropertiesConfiguration] = [
        .paperAnalysis: VaultPropertiesConfiguration(
            visibleFields: [
                "type", "publication_date", "limitations", "summary", "source_basis", "tags",
            ],
            editableFields: PropertyContractCatalog.analysisCanonicalKeys
        ),
        .topicKnowledge: VaultPropertiesConfiguration(
            visibleFields: ["summary", "aliases", "limitations", "tags"],
            editableFields: ["aliases", "summary", "limitations", "tags"]
        ),
        .output: VaultPropertiesConfiguration(
            visibleFields: ["work_type", "coauthors", "summary", "limitations", "tags"],
            editableFields: ["work_type", "coauthors", "summary", "limitations", "tags"]
        ),
    ]

    private static func completeProperties(
        _ properties: [WorkspaceVaultSlot: VaultPropertiesConfiguration]
    ) -> [WorkspaceVaultSlot: VaultPropertiesConfiguration] {
        var result = defaultProperties
        for (slot, configuration) in properties {
            result[slot] = configuration
        }
        return result
    }

    public static let defaultCritiquePromptTemplate = """
    Critique the Work identified in the Scholium request using the standards and
    questions of a careful specialist in the relevant field. Apply those standards
    without presenting yourself as a human specialist.

    Critique scope: {{critique_scope}}
    Critique lens: {{critique_lens}}
    Selected passages or requested focus: {{selected_ranges}}
    Additional instructions: {{additional_instructions}}

    Inspect the relevant Analyses and Topics in the Triptych. Distinguish what those
    notes report, support, dispute, or leave uncertain from your own reconstruction
    or evaluation. Do not treat neutral links or transitive paths as evidence.

    Use the sections Overall Assessment, Strengths, Major Concerns, Source Support,
    Objections and Alternatives, Revision Priorities, Specific Findings, and
    Materials Consulted and Limitations. Identify the materials actually consulted
    and any limitations. Write the result only to the designated Critique document.
    The target Work and all contextual Materials remain read-only. If a later change
    is warranted, prepare an independent Revise function through Scholium.
    """

    public static let defaultDialoguePromptTemplate = """
    Scholium researcher instructions

    Researcher instruction:
    {{researcher_instruction}}

    Selected notes (focal context, not an authorization boundary):
    {{selected_notes}}

    Triptych context:
    {{triptych_context}}

    Researcher comments:
    {{researcher_comments}}

    Relevant linked-note context:
    {{linked_note_context}}

    Requested destination:
    {{requested_destination}}

    Discuss boundary:
    {{editing_rules}}
    The selected Target and contextual Materials are read-only. Inspect their current
    revisions before relying on them. If the request requires changing the Target,
    stop the Discuss exchange and prepare Develop for an Analysis or Topic, or Revise
    for a Work, through Scholium's Research Function API. Treat fingerprints as
    revision checks, not permission tokens. Neutral links and transitive paths are
    not evidence.

    Closing response:
    Conclude with a concise attributed academic result. Identify any unresolved
    question, warranted promotion, or required researcher review. Discuss itself
    creates no checkpoint and authorizes no research-note mutation.
    """

    public func activePromptTemplate(for kind: ResearchPromptKind) -> ResearchPromptTemplate {
        if let id = activePromptTemplateIDs[kind],
           let template = promptTemplates.first(where: { $0.id == id && $0.kind == kind }) {
            return template
        }
        return kind == .dialogue ? .defaultDialogue : .defaultCritique
    }

    public mutating func savePromptTemplate(_ template: ResearchPromptTemplate) {
        if let index = promptTemplates.firstIndex(where: { $0.id == template.id }) {
            promptTemplates[index] = template
        } else {
            promptTemplates.append(template)
        }
        activePromptTemplateIDs[template.kind] = template.id
    }

    public mutating func deletePromptTemplate(id: UUID) {
        guard let template = promptTemplates.first(where: { $0.id == id }),
              template.origin == .researcher else { return }
        promptTemplates.removeAll { $0.id == id }
        if activePromptTemplateIDs[template.kind] == id {
            activePromptTemplateIDs[template.kind] = template.kind == .dialogue
                ? ResearchPromptTemplate.defaultDialogue.id
                : ResearchPromptTemplate.defaultCritique.id
        }
    }

    public mutating func resetPromptTemplate(for kind: ResearchPromptKind) {
        activePromptTemplateIDs[kind] = kind == .dialogue
            ? ResearchPromptTemplate.defaultDialogue.id
            : ResearchPromptTemplate.defaultCritique.id
    }

    private mutating func repairActiveTemplateIDs() {
        for kind in ResearchPromptKind.allCases {
            let id = activePromptTemplateIDs[kind]
            if !promptTemplates.contains(where: { $0.id == id && $0.kind == kind }) {
                activePromptTemplateIDs[kind] = kind == .dialogue
                    ? ResearchPromptTemplate.defaultDialogue.id
                    : ResearchPromptTemplate.defaultCritique.id
            }
        }
    }

    private static func completeTemplates(_ templates: [ResearchPromptTemplate]) -> [ResearchPromptTemplate] {
        var result = templates
        if !result.contains(where: { $0.id == ResearchPromptTemplate.defaultDialogue.id }) { result.append(.defaultDialogue) }
        if !result.contains(where: { $0.id == ResearchPromptTemplate.defaultCritique.id }) { result.append(.defaultCritique) }
        return result
    }

}

public struct NoteIdentityRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let vaultID: UUID
    public var relativePath: String
    public var fingerprint: DocumentFingerprint
    public let createdAt: Date
    public var updatedAt: Date
    public var duplicatedFrom: UUID?

    public init(
        id: UUID = UUID(),
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        duplicatedFrom: UUID? = nil
    ) {
        self.id = id
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duplicatedFrom = duplicatedFrom
    }
}

public struct NoteIdentityRebinding: Codable, Hashable, Sendable {
    public let id: UUID
    public let previousRelativePath: String
    public let relativePath: String

    public init(id: UUID, previousRelativePath: String, relativePath: String) {
        self.id = id
        self.previousRelativePath = previousRelativePath
        self.relativePath = relativePath
    }
}

public struct NoteIdentityAmbiguity: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(vaultID.uuidString):\(relativePath)" }
    public let vaultID: UUID
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    public let candidates: [NoteIdentityRecord]

    public init(
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        candidates: [NoteIdentityRecord]
    ) {
        self.vaultID = vaultID
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.candidates = candidates.sorted { $0.relativePath < $1.relativePath }
    }
}

/// A confirmed or uniquely detected path change whose app-owned references
/// have not all been migrated yet. This record is written atomically with the
/// identity path change, so an interruption cannot make the note appear fully
/// reconciled while History, comments, Dialogue, or other state still points
/// at the previous path.
public struct NoteIdentityPendingRebinding: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(vaultID.uuidString):\(noteID.uuidString):\(relativePath)" }
    public let noteID: UUID
    public let vaultID: UUID
    public let previousRelativePath: String
    public let relativePath: String
    public let fingerprint: DocumentFingerprint
    public let detectedAt: Date

    public init(
        noteID: UUID,
        vaultID: UUID,
        previousRelativePath: String,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        detectedAt: Date = Date()
    ) {
        self.noteID = noteID
        self.vaultID = vaultID
        self.previousRelativePath = previousRelativePath
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.detectedAt = detectedAt
    }
}

public struct NoteIdentityReconciliation: Codable, Hashable, Sendable {
    public let identities: [String: NoteIdentityRecord]
    public let rebound: [NoteIdentityRebinding]
    public let ambiguities: [NoteIdentityAmbiguity]
    public let pendingRebindings: [NoteIdentityPendingRebinding]

    public init(
        identities: [String: NoteIdentityRecord],
        rebound: [NoteIdentityRebinding] = [],
        ambiguities: [NoteIdentityAmbiguity] = [],
        pendingRebindings: [NoteIdentityPendingRebinding] = []
    ) {
        self.identities = identities
        self.rebound = rebound
        self.ambiguities = ambiguities
        self.pendingRebindings = pendingRebindings
    }
}

public enum TriptychControlError: LocalizedError, Sendable {
    case invalidManifest
    case settingsMissing
    case settingsOldSchema(Int?)
    case settingsFutureSchema(Int)
    case settingsCorrupted
    case settingsNeedsReview(String)
    case settingsRevisionConflict
    case invalidZoteroBindings
    case zoteroBindingsRevisionConflict
    case invalidIdentities
    case identitiesRevisionConflict
    case invalidIdentityCandidate(UUID)
    case identityPathAlreadyAssigned(String)
    case identityRebindingNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "The Triptych manifest is missing or does not match the selected vaults."
        case .settingsMissing:
            return "The portable Triptych settings are missing. Managed creation is unavailable until they are restored."
        case .settingsOldSchema(let version):
            let value = version.map(String.init) ?? "without a version"
            return "The portable Triptych settings use an unsupported old schema (\(value)). Their exact bytes were preserved."
        case .settingsFutureSchema(let version):
            return "The portable Triptych settings use future schema \(version). Their exact bytes were preserved."
        case .settingsCorrupted:
            return "The current-schema portable Triptych settings are damaged. Their exact bytes were preserved for recovery."
        case .settingsNeedsReview(let reason):
            return "The current-schema portable Triptych settings need review before managed creation can continue: \(reason)"
        case .settingsRevisionConflict:
            return "The Triptych settings changed after they were loaded. Reload the saved settings before trying again."
        case .invalidZoteroBindings:
            return "The portable Zotero bindings are missing, damaged, or use an unsupported schema."
        case .zoteroBindingsRevisionConflict:
            return "The Zotero bindings changed after they were loaded. Reload them before trying again."
        case .invalidIdentities:
            return "The portable Note identities are missing or damaged. Their exact bytes were preserved for recovery."
        case .identitiesRevisionConflict:
            return "The portable Note identities changed while Scholium was updating them. Reload the workspace before trying again."
        case .invalidIdentityCandidate(let id):
            return "The selected note identity is no longer a valid candidate: \(id.uuidString)"
        case .identityPathAlreadyAssigned(let path):
            return "Another note identity is already assigned to \(path)."
        case .identityRebindingNotFound(let id):
            return "The pending note-identity migration no longer exists: \(id.uuidString)."
        }
    }
}
