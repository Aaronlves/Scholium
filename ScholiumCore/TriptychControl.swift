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
    /// Fields shown by the collapsed Properties projection, in display order.
    public var visibleFields: [String] {
        didSet { visibleFields = Self.unique(visibleFields) }
    }

    /// Top-level YAML fields the researcher may change through structured
    /// controls. Exact Source editing remains a separate, unrestricted mode.
    public var editableFields: [String] {
        didSet { editableFields = Self.unique(editableFields) }
    }

    /// The initial disclosure state for notes in this vault. Opening or
    /// closing one note remains a presentation choice for that note session.
    public var isExpanded: Bool

    public init(
        visibleFields: [String] = [],
        editableFields: [String] = [],
        isExpanded: Bool = false
    ) {
        self.visibleFields = Self.unique(visibleFields)
        self.editableFields = Self.unique(editableFields)
        self.isExpanded = isExpanded
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

    private enum CodingKeys: String, CodingKey {
        case visibleFields
        case editableFields
        case isExpanded
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            visibleFields: try container.decodeIfPresent([String].self, forKey: .visibleFields) ?? [],
            editableFields: try container.decodeIfPresent([String].self, forKey: .editableFields) ?? [],
            isExpanded: try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibleFields, forKey: .visibleFields)
        try container.encode(editableFields, forKey: .editableFields)
        try container.encode(isExpanded, forKey: .isExpanded)
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
}

public struct TriptychSettings: Codable, Hashable, Sendable {
    public var properties: [WorkspaceVaultSlot: VaultPropertiesConfiguration] {
        didSet { properties = Self.completeProperties(properties) }
    }
    public var promptTemplates: [ResearchPromptTemplate]
    public var activePromptTemplateIDs: [ResearchPromptKind: UUID]
    public var attentionDismissalDays: Int

    public var critiquePromptTemplate: String {
        get { activePromptTemplate(for: .critique).source }
        set { setLegacyPrompt(newValue, kind: .critique) }
    }

    public var dialoguePromptTemplate: String {
        get { activePromptTemplate(for: .dialogue).source }
        set { setLegacyPrompt(newValue, kind: .dialogue) }
    }

    public init(
        properties: [WorkspaceVaultSlot: VaultPropertiesConfiguration] = Self.defaultProperties,
        critiquePromptTemplate: String = Self.defaultCritiquePromptTemplate,
        promptTemplates: [ResearchPromptTemplate]? = nil,
        activePromptTemplateIDs: [ResearchPromptKind: UUID]? = nil,
        attentionDismissalDays: Int = 7
    ) {
        self.properties = Self.completeProperties(properties)
        var templates = promptTemplates ?? [.defaultDialogue, .defaultCritique]
        var activeIDs = activePromptTemplateIDs ?? [
            .dialogue: ResearchPromptTemplate.defaultDialogue.id,
            .critique: ResearchPromptTemplate.defaultCritique.id,
        ]
        if promptTemplates == nil, critiquePromptTemplate != Self.defaultCritiquePromptTemplate {
            let migrated = Self.migratedTemplate(for: .critique, source: critiquePromptTemplate)
            templates.append(migrated)
            activeIDs[.critique] = migrated.id
        }
        for kind in ResearchPromptKind.allCases {
            let bundled = kind == .dialogue
                ? ResearchPromptTemplate.defaultDialogue
                : ResearchPromptTemplate.defaultCritique
            guard let index = templates.firstIndex(where: { $0.id == bundled.id }) else { continue }
            let stored = templates[index]
            guard stored != bundled else { continue }
            templates[index] = bundled
            if stored.origin == .researcher, stored.source != bundled.source {
                let migrated = Self.migratedTemplate(for: kind, source: stored.source)
                if let migratedIndex = templates.firstIndex(where: { $0.id == migrated.id }) {
                    templates[migratedIndex] = migrated
                } else {
                    templates.append(migrated)
                }
                if activeIDs[kind] == bundled.id { activeIDs[kind] = migrated.id }
            }
        }
        self.promptTemplates = Self.completeTemplates(templates)
        self.activePromptTemplateIDs = activeIDs
        self.attentionDismissalDays = max(1, attentionDismissalDays)
        repairActiveTemplateIDs()
    }

    private enum CodingKeys: String, CodingKey {
        case properties
        case critiquePromptTemplate
        case promptTemplates
        case activePromptTemplateIDs
        case attentionDismissalDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyCritique = try container.decodeIfPresent(String.self, forKey: .critiquePromptTemplate)
            ?? Self.defaultCritiquePromptTemplate
        self.init(
            properties: try container.decodeIfPresent(
                [WorkspaceVaultSlot: VaultPropertiesConfiguration].self,
                forKey: .properties
            ) ?? Self.defaultProperties,
            critiquePromptTemplate: legacyCritique,
            promptTemplates: try container.decodeIfPresent([ResearchPromptTemplate].self, forKey: .promptTemplates),
            activePromptTemplateIDs: try container.decodeIfPresent([ResearchPromptKind: UUID].self, forKey: .activePromptTemplateIDs),
            attentionDismissalDays: try container.decodeIfPresent(
                Int.self,
                forKey: .attentionDismissalDays
            ) ?? 7
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(properties, forKey: .properties)
        try container.encode(critiquePromptTemplate, forKey: .critiquePromptTemplate)
        try container.encode(promptTemplates, forKey: .promptTemplates)
        try container.encode(activePromptTemplateIDs, forKey: .activePromptTemplateIDs)
        try container.encode(attentionDismissalDays, forKey: .attentionDismissalDays)
    }

    public static let defaultProperties: [WorkspaceVaultSlot: VaultPropertiesConfiguration] = [
        .paperAnalysis: VaultPropertiesConfiguration(
            visibleFields: ["title", "authors", "year", "doi", "status", "relevance", "access", "text_reliability", "locators", "last_modified_by", "last_modified_at"],
            editableFields: ["title", "authors", "year", "doi", "status", "relevance", "tags"]
        ),
        .topicKnowledge: VaultPropertiesConfiguration(
            visibleFields: ["title", "aliases", "status", "last_modified_by", "last_modified_at"],
            editableFields: ["title", "aliases", "status", "tags"]
        ),
        .output: VaultPropertiesConfiguration(
            visibleFields: ["title", "kind", "authors", "status", "venue", "deadline", "last_modified_by", "last_modified_at"],
            editableFields: ["title", "kind", "authors", "status", "venue", "deadline", "tags"]
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
    and any limitations. Write the result to the designated Critique document. Do
    not modify the target Work unless the researcher's instruction asks you to do so.
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

    Editing rules:
    {{editing_rules}}
    Inspect the current files before editing. You may inspect and directly modify other relevant Triptych files when the researcher instruction requires it. Treat fingerprints as revision checks, not permission tokens. Neutral links and transitive paths are not evidence.

    Closing response:
    If you changed research notes, conclude with a concise academic change summary. Foreground changes to arguments, interpretations, evidence, or organization. Identify any unresolved question or required researcher review. Keep routine file-operation details secondary.

    A complete Triptych checkpoint named Before Agent Work was created before these instructions were copied.
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

    private mutating func setLegacyPrompt(_ source: String, kind: ResearchPromptKind) {
        var template = activePromptTemplate(for: kind)
        template.source = source
        if template.origin == .scholium && source != (kind == .dialogue ? Self.defaultDialoguePromptTemplate : Self.defaultCritiquePromptTemplate) {
            template = ResearchPromptTemplate(kind: kind, name: "Customized \(kind.displayName)", source: source)
        }
        savePromptTemplate(template)
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

    private static func migratedTemplate(
        for kind: ResearchPromptKind,
        source: String
    ) -> ResearchPromptTemplate {
        let id = kind == .dialogue
            ? UUID(uuidString: "82E8370D-D378-44F9-9E82-E4F70F941003")!
            : UUID(uuidString: "82E8370D-D378-44F9-9E82-E4F70F941004")!
        return ResearchPromptTemplate(
            id: id,
            kind: kind,
            name: "Migrated \(kind.displayName)",
            source: source,
            origin: .researcher
        )
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

struct PermanentDeletionIdentityAmbiguity: Codable, Hashable, Sendable {
    let vaultID: UUID
    let relativePath: String
    let fingerprint: DocumentFingerprint
    let candidateIDs: [UUID]
    let detectedAt: Date
}

struct PermanentDeletionIdentityBackup: Codable, Hashable, Sendable {
    let record: NoteIdentityRecord
    let pendingRebindings: [NoteIdentityPendingRebinding]
    let ambiguities: [PermanentDeletionIdentityAmbiguity]
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
    case unsupportedImport(String)
    case invalidUnclassifiedPath(String)
    case invalidIdentityCandidate(UUID)
    case identityPathAlreadyAssigned(String)
    case identityRebindingNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "The Triptych manifest is missing or does not match the selected vaults."
        case .unsupportedImport(let path):
            return "Only regular Markdown files can be imported: \(path)"
        case .invalidUnclassifiedPath(let path):
            return "Invalid Unclassified Markdown path: \(path)"
        case .invalidIdentityCandidate(let id):
            return "The selected note identity is no longer a valid candidate: \(id.uuidString)"
        case .identityPathAlreadyAssigned(let path):
            return "Another note identity is already assigned to \(path)."
        case .identityRebindingNotFound(let id):
            return "The pending note-identity migration no longer exists: \(id.uuidString)."
        }
    }
}

/// Owns the small, portable `.scholium` directory beside the Works vault.
public actor TriptychControlStore {
    private struct StoredIdentityAmbiguity: Codable {
        let vaultID: UUID
        let relativePath: String
        var fingerprint: DocumentFingerprint
        var candidateIDs: [UUID]
        let detectedAt: Date
    }

    private struct IdentityFile: Codable {
        var records: [NoteIdentityRecord]
        var pendingRebindings: [NoteIdentityPendingRebinding]
        var unresolvedAmbiguities: [StoredIdentityAmbiguity]

        init(
            records: [NoteIdentityRecord],
            pendingRebindings: [NoteIdentityPendingRebinding] = [],
            unresolvedAmbiguities: [StoredIdentityAmbiguity] = []
        ) {
            self.records = records
            self.pendingRebindings = pendingRebindings
            self.unresolvedAmbiguities = unresolvedAmbiguities
        }

        private enum CodingKeys: String, CodingKey {
            case records
            case pendingRebindings
            case unresolvedAmbiguities
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            records = try container.decodeIfPresent([NoteIdentityRecord].self, forKey: .records) ?? []
            pendingRebindings = try container.decodeIfPresent(
                [NoteIdentityPendingRebinding].self,
                forKey: .pendingRebindings
            ) ?? []
            unresolvedAmbiguities = try container.decodeIfPresent(
                [StoredIdentityAmbiguity].self,
                forKey: .unresolvedAmbiguities
            ) ?? []
        }
    }

    public let controlURL: URL
    public let unclassifiedURL: URL

    private let manifestURL: URL
    private let settingsURL: URL
    private let identitiesURL: URL
    private let fileManager: FileManager

    public init(worksVaultURL: URL, fileManager: FileManager = .default) {
        controlURL = worksVaultURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        unclassifiedURL = controlURL.appendingPathComponent("unclassified", isDirectory: true)
        manifestURL = controlURL.appendingPathComponent("manifest.json")
        settingsURL = controlURL.appendingPathComponent("settings.json")
        identitiesURL = controlURL.appendingPathComponent("identities.json")
        self.fileManager = fileManager
    }

    @discardableResult
    public func bootstrap(
        vaultIDs: [WorkspaceVaultSlot: UUID],
        preferredTriptychID: UUID? = nil
    ) throws -> TriptychManifest {
        guard Set(vaultIDs.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw TriptychControlError.invalidManifest
        }
        try fileManager.createDirectory(at: unclassifiedURL, withIntermediateDirectories: true)

        let now = Date()
        let manifest: TriptychManifest
        if var existing: TriptychManifest = try decodeIfPresent(TriptychManifest.self, from: manifestURL) {
            existing.vaultIDs = vaultIDs
            existing.updatedAt = now
            manifest = existing
        } else {
            manifest = TriptychManifest(
                id: preferredTriptychID ?? UUID(),
                vaultIDs: vaultIDs,
                createdAt: now,
                updatedAt: now
            )
        }
        try encode(manifest, to: manifestURL)

        if !fileManager.fileExists(atPath: settingsURL.path) {
            try encode(TriptychSettings(), to: settingsURL)
        }
        if !fileManager.fileExists(atPath: identitiesURL.path) {
            try encode(IdentityFile(records: []), to: identitiesURL)
        }
        return manifest
    }

    public func manifest() throws -> TriptychManifest {
        guard let manifest: TriptychManifest = try decodeIfPresent(TriptychManifest.self, from: manifestURL) else {
            throw TriptychControlError.invalidManifest
        }
        return manifest
    }

    public func settings() throws -> TriptychSettings {
        try decodeIfPresent(TriptychSettings.self, from: settingsURL) ?? TriptychSettings()
    }

    public func saveSettings(_ settings: TriptychSettings) throws {
        try ensureControlDirectory()
        try encode(settings, to: settingsURL)
    }

    /// Copies source Markdown into portable Unclassified staging without
    /// modifying the original file.
    public func importMarkdown(at sourceURL: URL) throws -> URL {
        let resolved = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true,
              resolved.pathExtension.caseInsensitiveCompare("md") == .orderedSame else {
            throw TriptychControlError.unsupportedImport(sourceURL.path)
        }
        try fileManager.createDirectory(at: unclassifiedURL, withIntermediateDirectories: true)
        let destination = availableImportURL(named: resolved.lastPathComponent)
        try fileManager.copyItem(at: resolved, to: destination)
        return destination
    }

    public func unclassifiedDocuments() throws -> [NoteDocument] {
        try ensureControlDirectory()
        guard let enumerator = fileManager.enumerator(
            at: unclassifiedURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var documents: [NoteDocument] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                throw TriptychControlError.invalidUnclassifiedPath(url.path)
            }
            guard values.isRegularFile == true,
                  url.pathExtension.caseInsensitiveCompare("md") == .orderedSame else { continue }
            let relativePath = Self.relativePath(of: url, under: unclassifiedURL)
            documents.append(try loadUnclassified(relativePath: relativePath))
        }
        return documents.sorted { $0.relativePath < $1.relativePath }
    }

    public func loadUnclassified(relativePath: String) throws -> NoteDocument {
        let url = try unclassifiedFileURL(relativePath, mustExist: true)
        let data = try Data(contentsOf: url)
        guard let content = NoteDocument.decodeUTF8PreservingBOM(data) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return NoteDocument(relativePath: relativePath, rawContent: content)
    }

    public func saveUnclassified(
        relativePath: String,
        content: String,
        expectedRevision: DocumentFingerprint
    ) throws -> NoteDocument {
        let url = try unclassifiedFileURL(relativePath, mustExist: true)
        let currentData = try Data(contentsOf: url)
        let current = DocumentFingerprint(data: currentData)
        guard current == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: current)
        }
        let document = NoteDocument(relativePath: relativePath, rawContent: content)
        try Data(content.utf8).write(to: url, options: .atomic)
        let readback = try Data(contentsOf: url)
        let observed = DocumentFingerprint(data: readback)
        guard observed == document.fingerprint else {
            throw VaultRepositoryError.readbackMismatch(expected: document.fingerprint, current: observed)
        }
        return document
    }

    public func removeUnclassified(relativePath: String, expectedRevision: DocumentFingerprint) throws {
        let url = try unclassifiedFileURL(relativePath, mustExist: true)
        let current = DocumentFingerprint(data: try Data(contentsOf: url))
        guard current == expectedRevision else {
            throw VaultRepositoryError.conflict(expected: expectedRevision, current: current)
        }
        try fileManager.removeItem(at: url)
    }

    public func identity(
        forVaultID vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        createIfMissing: Bool = true
    ) throws -> NoteIdentityRecord? {
        var payload = try identityPayload()
        if let index = payload.records.firstIndex(where: {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }) {
            if payload.records[index].fingerprint != fingerprint {
                payload.records[index].fingerprint = fingerprint
                payload.records[index].updatedAt = Date()
                try encode(payload, to: identitiesURL)
            }
            return payload.records[index]
        }
        guard createIfMissing else { return nil }
        let record = NoteIdentityRecord(
            vaultID: vaultID,
            relativePath: relativePath,
            fingerprint: fingerprint
        )
        payload.records.append(record)
        try ensureControlDirectory()
        try encode(payload, to: identitiesURL)
        return record
    }

    func identityRecord(vaultID: UUID, relativePath: String) throws -> NoteIdentityRecord? {
        try identityPayload().records.first {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }
    }

    public func moveIdentity(
        id: UUID,
        to relativePath: String,
        fingerprint: DocumentFingerprint
    ) throws -> NoteIdentityRecord {
        var payload = try identityPayload()
        guard let index = payload.records.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !payload.records.contains(where: {
            $0.id != id
                && $0.vaultID == payload.records[index].vaultID
                && $0.relativePath == relativePath
        }) else {
            throw TriptychControlError.identityPathAlreadyAssigned(relativePath)
        }
        let previousPath = payload.records[index].relativePath
        payload.records[index].relativePath = relativePath
        payload.records[index].fingerprint = fingerprint
        payload.records[index].updatedAt = Date()
        if previousPath != relativePath {
            Self.enqueuePendingRebinding(
                NoteIdentityPendingRebinding(
                    noteID: id,
                    vaultID: payload.records[index].vaultID,
                    previousRelativePath: previousPath,
                    relativePath: relativePath,
                    fingerprint: fingerprint
                ),
                in: &payload.pendingRebindings
            )
        }
        try encode(payload, to: identitiesURL)
        return payload.records[index]
    }

    public func duplicateIdentity(
        from sourceID: UUID,
        to relativePath: String,
        fingerprint: DocumentFingerprint
    ) throws -> NoteIdentityRecord {
        let source = try identityPayload().records.first(where: { $0.id == sourceID })
        guard let source else { throw CocoaError(.fileNoSuchFile) }
        var payload = try identityPayload()
        let duplicate = NoteIdentityRecord(
            vaultID: source.vaultID,
            relativePath: relativePath,
            fingerprint: fingerprint,
            duplicatedFrom: sourceID
        )
        payload.records.append(duplicate)
        try encode(payload, to: identitiesURL)
        return duplicate
    }

    /// Removes the portable stable identity and every pending identity record
    /// that could reintroduce it after a researcher confirms permanent
    /// deletion. The exact vault and path are required to prevent a stale UI
    /// command from purging a reused identity or a different vault's note.
    @discardableResult
    public func purgeIdentity(
        id: UUID,
        vaultID: UUID,
        relativePath: String
    ) throws -> NoteIdentityRecord? {
        var payload = try identityPayload()
        guard let record = payload.records.first(where: { $0.id == id }) else { return nil }
        guard record.vaultID == vaultID, record.relativePath == relativePath else {
            throw TriptychControlError.invalidIdentityCandidate(id)
        }
        payload.records.removeAll { $0.id == id }
        payload.pendingRebindings.removeAll { $0.noteID == id }
        payload.unresolvedAmbiguities = payload.unresolvedAmbiguities.compactMap { ambiguity in
            var ambiguity = ambiguity
            ambiguity.candidateIDs.removeAll { $0 == id }
            return ambiguity.candidateIDs.isEmpty ? nil : ambiguity
        }
        try encode(payload, to: identitiesURL)
        return record
    }

    func prepareIdentityPurge(
        id: UUID,
        vaultID: UUID,
        relativePath: String
    ) throws -> PermanentDeletionIdentityBackup? {
        let payload = try identityPayload()
        guard let record = payload.records.first(where: { $0.id == id }) else { return nil }
        guard record.vaultID == vaultID, record.relativePath == relativePath else {
            throw TriptychControlError.invalidIdentityCandidate(id)
        }
        return PermanentDeletionIdentityBackup(
            record: record,
            pendingRebindings: payload.pendingRebindings.filter { $0.noteID == id },
            ambiguities: payload.unresolvedAmbiguities.compactMap { ambiguity in
                guard ambiguity.candidateIDs.contains(id) else { return nil }
                return PermanentDeletionIdentityAmbiguity(
                    vaultID: ambiguity.vaultID,
                    relativePath: ambiguity.relativePath,
                    fingerprint: ambiguity.fingerprint,
                    candidateIDs: ambiguity.candidateIDs,
                    detectedAt: ambiguity.detectedAt
                )
            }
        )
    }

    func restorePurgedIdentity(_ backup: PermanentDeletionIdentityBackup?) throws {
        guard let backup else { return }
        var payload = try identityPayload()
        if let existing = payload.records.first(where: { $0.id == backup.record.id }) {
            guard try persistentlyEquivalent(existing, backup.record) else {
                throw TriptychControlError.invalidIdentityCandidate(backup.record.id)
            }
        } else {
            guard !payload.records.contains(where: {
                $0.vaultID == backup.record.vaultID
                    && $0.relativePath == backup.record.relativePath
            }) else {
                throw TriptychControlError.identityPathAlreadyAssigned(backup.record.relativePath)
            }
            payload.records.append(backup.record)
        }
        for pending in backup.pendingRebindings where !payload.pendingRebindings.contains(pending) {
            payload.pendingRebindings.append(pending)
        }
        for ambiguity in backup.ambiguities {
            let restored = StoredIdentityAmbiguity(
                vaultID: ambiguity.vaultID,
                relativePath: ambiguity.relativePath,
                fingerprint: ambiguity.fingerprint,
                candidateIDs: ambiguity.candidateIDs,
                detectedAt: ambiguity.detectedAt
            )
            if let index = payload.unresolvedAmbiguities.firstIndex(where: {
                $0.vaultID == restored.vaultID && $0.relativePath == restored.relativePath
            }) {
                let existing = payload.unresolvedAmbiguities[index]
                guard existing.fingerprint == restored.fingerprint,
                      existing.candidateIDs == restored.candidateIDs else {
                    throw TriptychControlError.invalidIdentityCandidate(backup.record.id)
                }
            } else {
                payload.unresolvedAmbiguities.append(restored)
            }
        }
        try encode(payload, to: identitiesURL)
    }

    /// Returns a unique fingerprint match for confirming an external rename.
    public func externalRenameCandidate(
        vaultID: UUID,
        fingerprint: DocumentFingerprint
    ) throws -> NoteIdentityRecord? {
        let matches = try identityPayload().records.filter {
            $0.vaultID == vaultID && $0.fingerprint == fingerprint
        }
        return matches.count == 1 ? matches[0] : nil
    }

    /// Reconciles one vault inventory in one atomic portable-state write.
    ///
    /// Exact paths are claimed before fingerprint matching so an external copy
    /// whose path sorts earlier cannot steal the original note's identity. A
    /// unique unused fingerprint match preserves identity across an external
    /// rename. Ambiguous matches remain unresolved until the researcher chooses
    /// an existing identity or confirms that the file is a new note.
    public func reconcileIdentityInventory(
        vaultID: UUID,
        documents: [(relativePath: String, fingerprint: DocumentFingerprint)]
    ) throws -> NoteIdentityReconciliation {
        var payload = try identityPayload()
        var result: [String: NoteIdentityRecord] = [:]
        var rebound: [NoteIdentityRebinding] = []
        var ambiguities: [NoteIdentityAmbiguity] = []
        var claimedIDs: Set<UUID> = []
        var unmatched: [(relativePath: String, fingerprint: DocumentFingerprint)] = []
        var changed = false

        // First reserve every identity whose path still exists. This is the
        // authoritative signal that a same-fingerprint file is a copy rather
        // than a rename of that still-present note.
        for document in documents.sorted(by: { $0.relativePath < $1.relativePath }) {
            if let index = payload.records.firstIndex(where: {
                $0.vaultID == vaultID && $0.relativePath == document.relativePath
            }) {
                if payload.records[index].fingerprint != document.fingerprint {
                    payload.records[index].fingerprint = document.fingerprint
                    payload.records[index].updatedAt = Date()
                    changed = true
                }
                claimedIDs.insert(payload.records[index].id)
                result[document.relativePath] = payload.records[index]
                let unresolvedCount = payload.unresolvedAmbiguities.count
                payload.unresolvedAmbiguities.removeAll {
                    $0.vaultID == vaultID && $0.relativePath == document.relativePath
                }
                if payload.unresolvedAmbiguities.count != unresolvedCount { changed = true }
            } else {
                unmatched.append(document)
            }
        }

        for document in unmatched {
            if let unresolvedIndex = payload.unresolvedAmbiguities.firstIndex(where: {
                $0.vaultID == vaultID && $0.relativePath == document.relativePath
            }) {
                let stored = payload.unresolvedAmbiguities[unresolvedIndex]
                let candidates = stored.candidateIDs.compactMap { candidateID in
                    payload.records.first { record in
                        record.id == candidateID
                            && record.vaultID == vaultID
                            && !claimedIDs.contains(record.id)
                    }
                }
                if payload.unresolvedAmbiguities[unresolvedIndex].fingerprint != document.fingerprint {
                    payload.unresolvedAmbiguities[unresolvedIndex].fingerprint = document.fingerprint
                    changed = true
                }
                ambiguities.append(NoteIdentityAmbiguity(
                    vaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint,
                    candidates: candidates
                ))
                continue
            }
            let candidateIndices = payload.records.indices.filter { index in
                payload.records[index].vaultID == vaultID
                    && payload.records[index].fingerprint == document.fingerprint
                    && !claimedIDs.contains(payload.records[index].id)
            }
            if candidateIndices.count == 1, let index = candidateIndices.first {
                let previousPath = payload.records[index].relativePath
                payload.records[index].relativePath = document.relativePath
                payload.records[index].updatedAt = Date()
                claimedIDs.insert(payload.records[index].id)
                result[document.relativePath] = payload.records[index]
                rebound.append(NoteIdentityRebinding(
                    id: payload.records[index].id,
                    previousRelativePath: previousPath,
                    relativePath: document.relativePath
                ))
                Self.enqueuePendingRebinding(
                    NoteIdentityPendingRebinding(
                        noteID: payload.records[index].id,
                        vaultID: vaultID,
                        previousRelativePath: previousPath,
                        relativePath: document.relativePath,
                        fingerprint: document.fingerprint
                    ),
                    in: &payload.pendingRebindings
                )
                changed = true
            } else if candidateIndices.isEmpty {
                let record = NoteIdentityRecord(
                    vaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint
                )
                payload.records.append(record)
                claimedIDs.insert(record.id)
                result[document.relativePath] = record
                changed = true
            } else {
                payload.unresolvedAmbiguities.removeAll {
                    $0.vaultID == vaultID && $0.relativePath == document.relativePath
                }
                payload.unresolvedAmbiguities.append(StoredIdentityAmbiguity(
                    vaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint,
                    candidateIDs: candidateIndices.map { payload.records[$0].id },
                    detectedAt: Date()
                ))
                changed = true
                ambiguities.append(NoteIdentityAmbiguity(
                    vaultID: vaultID,
                    relativePath: document.relativePath,
                    fingerprint: document.fingerprint,
                    candidates: candidateIndices.map { payload.records[$0] }
                ))
            }
        }
        if changed {
            try ensureControlDirectory()
            try encode(payload, to: identitiesURL)
        }
        return NoteIdentityReconciliation(
            identities: result,
            rebound: rebound.sorted { $0.relativePath < $1.relativePath },
            ambiguities: ambiguities.sorted { $0.relativePath < $1.relativePath },
            pendingRebindings: payload.pendingRebindings
                .filter { $0.vaultID == vaultID }
                .sorted { $0.relativePath < $1.relativePath }
        )
    }

    public func reconcileIdentities(
        vaultID: UUID,
        documents: [(relativePath: String, fingerprint: DocumentFingerprint)]
    ) throws -> [String: NoteIdentityRecord] {
        try reconcileIdentityInventory(vaultID: vaultID, documents: documents).identities
    }

    /// Resolves an ambiguous external rename after the researcher has seen the
    /// candidate paths. Passing `nil` creates a new identity for the file.
    public func resolveIdentityAmbiguity(
        vaultID: UUID,
        relativePath: String,
        fingerprint: DocumentFingerprint,
        candidateID: UUID?
    ) throws -> NoteIdentityRecord {
        var payload = try identityPayload()
        guard !payload.records.contains(where: {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }) else {
            throw TriptychControlError.identityPathAlreadyAssigned(relativePath)
        }

        let record: NoteIdentityRecord
        if let candidateID {
            let storedCandidates = payload.unresolvedAmbiguities.first(where: {
                $0.vaultID == vaultID && $0.relativePath == relativePath
            })?.candidateIDs
            guard let index = payload.records.firstIndex(where: {
                $0.id == candidateID && $0.vaultID == vaultID
            }), storedCandidates?.contains(candidateID) ?? (payload.records[index].fingerprint == fingerprint) else {
                throw TriptychControlError.invalidIdentityCandidate(candidateID)
            }
            let previousPath = payload.records[index].relativePath
            payload.records[index].relativePath = relativePath
            payload.records[index].updatedAt = Date()
            record = payload.records[index]
            Self.enqueuePendingRebinding(
                NoteIdentityPendingRebinding(
                    noteID: record.id,
                    vaultID: vaultID,
                    previousRelativePath: previousPath,
                    relativePath: relativePath,
                    fingerprint: fingerprint
                ),
                in: &payload.pendingRebindings
            )
        } else {
            record = NoteIdentityRecord(
                vaultID: vaultID,
                relativePath: relativePath,
                fingerprint: fingerprint
            )
            payload.records.append(record)
        }
        payload.unresolvedAmbiguities.removeAll {
            $0.vaultID == vaultID && $0.relativePath == relativePath
        }
        try ensureControlDirectory()
        try encode(payload, to: identitiesURL)
        return record
    }

    public func pendingIdentityRebindings(
        vaultID: UUID? = nil
    ) throws -> [NoteIdentityPendingRebinding] {
        let pending = try identityPayload().pendingRebindings
        return pending
            .filter { vaultID == nil || $0.vaultID == vaultID }
            .sorted {
                if $0.vaultID != $1.vaultID {
                    return $0.vaultID.uuidString < $1.vaultID.uuidString
                }
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
    }

    /// Marks a path migration complete only after every app-owned reference
    /// has been migrated. Calling this method again is harmless, which makes a
    /// recovery retry safe after an interruption.
    public func completeIdentityRebinding(_ rebinding: NoteIdentityPendingRebinding) throws {
        var payload = try identityPayload()
        guard let record = payload.records.first(where: {
            $0.id == rebinding.noteID
                && $0.vaultID == rebinding.vaultID
                && $0.relativePath == rebinding.relativePath
        }) else {
            throw TriptychControlError.identityRebindingNotFound(rebinding.noteID)
        }
        _ = record
        payload.pendingRebindings.removeAll { pending in
            pending.noteID == rebinding.noteID
                && pending.vaultID == rebinding.vaultID
                && pending.previousRelativePath == rebinding.previousRelativePath
                && pending.relativePath == rebinding.relativePath
        }
        try encode(payload, to: identitiesURL)
    }

    private static func enqueuePendingRebinding(
        _ rebinding: NoteIdentityPendingRebinding,
        in pending: inout [NoteIdentityPendingRebinding]
    ) {
        pending.removeAll { existing in
            existing.noteID == rebinding.noteID && existing.vaultID == rebinding.vaultID
        }
        pending.append(rebinding)
    }

    private func identityPayload() throws -> IdentityFile {
        try decodeIfPresent(IdentityFile.self, from: identitiesURL) ?? IdentityFile(records: [])
    }

    private func unclassifiedFileURL(_ relativePath: String, mustExist: Bool) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !components.contains(".."),
              !components.contains("."),
              !components.contains(""),
              URL(fileURLWithPath: relativePath).pathExtension.caseInsensitiveCompare("md") == .orderedSame else {
            throw TriptychControlError.invalidUnclassifiedPath(relativePath)
        }
        let root = unclassifiedURL.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw TriptychControlError.invalidUnclassifiedPath(relativePath)
        }
        if mustExist {
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw TriptychControlError.invalidUnclassifiedPath(relativePath)
            }
        }
        return candidate
    }

    private static func relativePath(of file: URL, under root: URL) -> String {
        String(file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    private func availableImportURL(named name: String) -> URL {
        let requested = unclassifiedURL.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: requested.path) else { return requested }
        let base = requested.deletingPathExtension().lastPathComponent
        let ext = requested.pathExtension
        var index = 2
        while true {
            let candidate = unclassifiedURL.appendingPathComponent("\(base) \(index).\(ext)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func ensureControlDirectory() throws {
        try fileManager.createDirectory(at: controlURL, withIntermediateDirectories: true)
    }

    private func decodeIfPresent<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureControlDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func persistentlyEquivalent<T: Encodable>(_ lhs: T, _ rhs: T) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lhs) == encoder.encode(rhs)
    }
}
