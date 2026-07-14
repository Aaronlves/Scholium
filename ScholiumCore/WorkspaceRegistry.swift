import Foundation

public enum VaultRole: String, Codable, CaseIterable, Sendable {
    case sourceCorpus = "source_corpus"
    case topicKnowledge = "topic_knowledge"
    case dissertationControl = "dissertation_control"
    case draftProject = "draft_project"
    case other

    /// Compatibility spellings used by the first CLI release.
    public static let sources = Self.sourceCorpus
    public static let knowledge = Self.topicKnowledge
    public static let project = Self.draftProject

    public var displayName: String {
        switch self {
        case .sourceCorpus: "Analyses"
        case .topicKnowledge: "Topics"
        case .dissertationControl, .draftProject: "Works"
        case .other: "Unclassified"
        }
    }

    public var allowsHumanReview: Bool {
        self == .sourceCorpus || self == .topicKnowledge
    }

    public var allowsCritique: Bool {
        self == .dissertationControl || self == .draftProject
    }

    public init?(commandLineValue: String) {
        switch commandLineValue.lowercased() {
        case "source_corpus", "sources", "analyses": self = .sourceCorpus
        case "topic_knowledge", "knowledge", "topics": self = .topicKnowledge
        case "dissertation_control", "dissertation": self = .dissertationControl
        case "draft_project", "project", "works": self = .draftProject
        case "other", "unclassified": self = .other
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let role = Self(commandLineValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Scholium vault role: \(value)"
            )
        }
        self = role
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RegisteredVault: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var role: VaultRole
    public let canonicalPath: String
    public let registeredAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        role: VaultRole,
        canonicalPath: String,
        registeredAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.canonicalPath = canonicalPath
        self.registeredAt = registeredAt
    }
}

/// One of the three peer roots in every Scholium Triptych.
public enum WorkspaceVaultSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case paperAnalysis = "paper_analysis"
    case topicKnowledge = "topic_knowledge"
    case output

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .paperAnalysis: "Analyses"
        case .topicKnowledge: "Topics"
        case .output: "Works"
        }
    }

    public var vaultRole: VaultRole {
        switch self {
        case .paperAnalysis: .sourceCorpus
        case .topicKnowledge: .topicKnowledge
        case .output: .draftProject
        }
    }
}

/// Stable machine-local registration for one complete Scholium Triptych.
///
/// The three vault UUIDs refer to `VaultIdentityRegistry`; paths and bookmarks
/// are deliberately not duplicated here. Older `ThreeVaultWorkspace` JSON
/// decodes with the Works vault UUID as a deterministic Triptych identity.
public struct ScholiumTriptych: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var paperAnalysisVaultID: UUID
    public var topicKnowledgeVaultID: UUID
    public var outputVaultID: UUID
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Triptych",
        paperAnalysisVaultID: UUID,
        topicKnowledgeVaultID: UUID,
        outputVaultID: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.paperAnalysisVaultID = paperAnalysisVaultID
        self.topicKnowledgeVaultID = topicKnowledgeVaultID
        self.outputVaultID = outputVaultID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func vaultID(for slot: WorkspaceVaultSlot) -> UUID {
        switch slot {
        case .paperAnalysis: paperAnalysisVaultID
        case .topicKnowledge: topicKnowledgeVaultID
        case .output: outputVaultID
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, paperAnalysisVaultID, topicKnowledgeVaultID, outputVaultID
        case createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paperAnalysisVaultID = try container.decode(UUID.self, forKey: .paperAnalysisVaultID)
        topicKnowledgeVaultID = try container.decode(UUID.self, forKey: .topicKnowledgeVaultID)
        outputVaultID = try container.decode(UUID.self, forKey: .outputVaultID)
        // The legacy record had no Triptych identity. The Works vault UUID is
        // stable, already persisted, and deterministic across repeated reads.
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? outputVaultID
        name = Self.normalizedName(
            try container.decodeIfPresent(String.self, forKey: .name) ?? "Triptych"
        )
        let updated = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date.distantPast
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? updated
        updatedAt = updated
    }

    private static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Triptych" : trimmed
    }
}

/// Compatibility spelling retained while call sites migrate to Triptych terms.
public typealias ThreeVaultWorkspace = ScholiumTriptych

public struct TriptychAssignment: Hashable, Identifiable, Sendable {
    public let triptych: ScholiumTriptych
    public let vaults: [WorkspaceVaultSlot: RegisteredVault]
    public let hasCommonParent: Bool

    public var id: UUID { triptych.id }
    public var workspace: ScholiumTriptych { triptych }

    public func vault(for slot: WorkspaceVaultSlot) -> RegisteredVault? {
        vaults[slot]
    }
}

/// Compatibility spelling retained while the app migrates incrementally.
public typealias ThreeVaultWorkspaceAssignment = TriptychAssignment

public enum WorkspaceRegistryError: LocalizedError, Sendable {
    case notDirectory(String)
    case duplicateName(String)
    case vaultNotFound(String)
    case ambiguousSelector(String)
    case triptychNotFound(UUID)
    case triptychSelectorNotFound(String)
    case ambiguousTriptychSelector(String)
    case triptychIdentityConflict(UUID)
    case corruptRegistry
    case triptychControlDirectoryInUse(String)
    case overlappingVaults(String, String)
    case vaultIdentityMismatch(UUID, String, String)
    case incompleteWorkspace
    case vaultAccessUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .notDirectory(let path): return "Vault path is not a directory: \(path)"
        case .duplicateName(let name): return "A different registered vault already uses the name '\(name)'."
        case .vaultNotFound(let selector): return "No registered vault matches '\(selector)'."
        case .ambiguousSelector(let selector): return "More than one registered vault matches '\(selector)'. Use its UUID."
        case .triptychNotFound(let id): return "No registered Triptych matches '\(id.uuidString)'."
        case .triptychSelectorNotFound(let selector):
            return "No registered Triptych matches '\(selector)'."
        case .ambiguousTriptychSelector(let selector):
            return "More than one registered Triptych is named '\(selector)'. Use its UUID."
        case .triptychIdentityConflict(let id):
            return "Another registered Triptych already uses identity '\(id.uuidString)'."
        case .corruptRegistry:
            return "The Scholium Triptych registry is damaged. Its existing file was preserved for recovery."
        case .triptychControlDirectoryInUse(let path):
            return "Another registered Triptych already uses the portable control folder at '\(path)'. Choose a Works folder under a different parent."
        case .overlappingVaults(let first, let second):
            return "Vault folders in one Triptych must be independent. '\(first)' overlaps '\(second)'."
        case .vaultIdentityMismatch(let id, let existing, let selected):
            return "Vault identity \(id.uuidString) already belongs to '\(existing)', not '\(selected)'."
        case .incompleteWorkspace:
            return "The Triptych is incomplete. Choose Analyses, Topics, and Works again."
        case .vaultAccessUnavailable(let path):
            return "Scholium no longer has access to '\(path)'. Open Manage Triptychs and choose that folder again."
        }
    }
}

public actor WorkspaceRegistry {
    private static let currentSchemaVersion = 2

    private struct LegacyRegistryFile: Codable {
        var vaults: [RegisteredVault]
    }

    private struct RegistryFile: Codable {
        var schemaVersion: Int
        var vaults: [RegisteredVault]
        var triptychs: [ScholiumTriptych]
        var defaultTriptychID: UUID?
    }

    private struct CanonicalSelection {
        let slot: WorkspaceVaultSlot
        let url: URL
        let identityID: UUID
    }

    public let storageURL: URL
    private let registryURL: URL
    private let legacyVaultRegistryURL: URL
    private let legacyThreeVaultWorkspaceURL: URL
    private let fileManager: FileManager

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        registryURL = storageURL.appendingPathComponent("workspace-registry-v2.json")
        legacyVaultRegistryURL = storageURL.appendingPathComponent("vaults.json")
        legacyThreeVaultWorkspaceURL = storageURL.appendingPathComponent("three-vault-workspace.json")
        self.fileManager = fileManager
    }

    @discardableResult
    public func register(
        path: URL,
        name: String?,
        role: VaultRole,
        stableID: UUID? = nil
    ) throws -> RegisteredVault {
        let canonical = try canonicalDirectory(path)
        var registry = try writableRegistry()
        let chosenName = normalizedName(name ?? canonical.lastPathComponent)
        if let existing = registry.vaults.first(where: { $0.canonicalPath == canonical.path }) {
            var updated = existing
            updated.name = chosenName
            updated.role = role
            guard !registry.vaults.contains(where: {
                $0.id != existing.id && $0.name.caseInsensitiveCompare(chosenName) == .orderedSame
            }) else {
                throw WorkspaceRegistryError.duplicateName(chosenName)
            }
            registry.vaults.removeAll { $0.id == existing.id }
            registry.vaults.append(updated)
            try persist(registry)
            return updated
        }

        guard !registry.vaults.contains(where: {
            $0.name.caseInsensitiveCompare(chosenName) == .orderedSame
        }) else {
            throw WorkspaceRegistryError.duplicateName(chosenName)
        }
        let vault = RegisteredVault(
            id: stableID ?? UUID(),
            name: chosenName,
            role: role,
            canonicalPath: canonical.path
        )
        registry.vaults.append(vault)
        try persist(registry)
        return vault
    }

    /// Registers or updates one complete Triptych without replacing any other
    /// Triptych. Equal or nested roots are rejected within this assignment.
    public func configureTriptych(
        id requestedID: UUID? = nil,
        name requestedName: String? = nil,
        paperAnalysis: (url: URL, identityID: UUID),
        topicKnowledge: (url: URL, identityID: UUID),
        output: (url: URL, identityID: UUID)
    ) throws -> TriptychAssignment {
        let canonical = try canonicalSelections(
            paperAnalysis: paperAnalysis,
            topicKnowledge: topicKnowledge,
            output: output
        )
        try validateIndependentRoots(canonical)

        var registry = try writableRegistry()
        let triptychID = requestedID ?? output.identityID
        try validatePortableControlDirectory(
            selections: canonical,
            triptychID: triptychID,
            registry: registry
        )
        let previous = registry.triptychs.first(where: { $0.id == triptychID })
        let previousVaultIDs = previous.map { triptych in
            Set(WorkspaceVaultSlot.allCases.map { triptych.vaultID(for: $0) })
        } ?? []

        var registered: [WorkspaceVaultSlot: RegisteredVault] = [:]
        for selection in canonical {
            if let conflicting = registry.vaults.first(where: {
                $0.id == selection.identityID && $0.canonicalPath != selection.url.path
            }) {
                throw WorkspaceRegistryError.vaultIdentityMismatch(
                    selection.identityID,
                    conflicting.canonicalPath,
                    selection.url.path
                )
            }

            let samePath = registry.vaults.first(where: { $0.canonicalPath == selection.url.path })
            if let samePath, samePath.id != selection.identityID {
                replaceVaultID(samePath.id, with: selection.identityID, in: &registry.triptychs)
            }
            let registeredAt = samePath?.registeredAt
                ?? registry.vaults.first(where: { $0.id == selection.identityID })?.registeredAt
                ?? Date()
            registry.vaults.removeAll {
                $0.id == selection.identityID || $0.canonicalPath == selection.url.path
            }
            let vault = RegisteredVault(
                id: selection.identityID,
                name: selection.slot.displayName,
                role: selection.slot.vaultRole,
                canonicalPath: selection.url.path,
                registeredAt: registeredAt
            )
            registry.vaults.append(vault)
            registered[selection.slot] = vault
        }

        guard let analyses = registered[.paperAnalysis],
              let topics = registered[.topicKnowledge],
              let works = registered[.output] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }

        let name = normalizedName(requestedName ?? previous?.name ?? inferredTriptychName(from: canonical))
        let now = Date()
        let triptych = ScholiumTriptych(
            id: triptychID,
            name: name,
            paperAnalysisVaultID: analyses.id,
            topicKnowledgeVaultID: topics.id,
            outputVaultID: works.id,
            createdAt: previous?.createdAt ?? now,
            updatedAt: now
        )
        registry.triptychs.removeAll { $0.id == triptychID }
        registry.triptychs.append(triptych)
        if registry.defaultTriptychID == nil { registry.defaultTriptychID = triptychID }

        let referencedIDs = Set(registry.triptychs.flatMap { triptych in
            WorkspaceVaultSlot.allCases.map { triptych.vaultID(for: $0) }
        })
        registry.vaults.removeAll {
            previousVaultIDs.contains($0.id) && !referencedIDs.contains($0.id)
        }
        try persist(registry)
        guard let result = assignment(for: triptych, in: registry) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return result
    }

    /// Compatibility API for callers that still manage one Triptych. It
    /// updates the default Triptych instead of creating a second assignment.
    public func configureThreeVaultWorkspace(
        paperAnalysis: (url: URL, identityID: UUID),
        topicKnowledge: (url: URL, identityID: UUID),
        output: (url: URL, identityID: UUID)
    ) throws -> ThreeVaultWorkspaceAssignment {
        let registry = load()
        let defaultID = registry.defaultTriptychID
            ?? sortedTriptychs(registry.triptychs).first?.id
        return try configureTriptych(
            id: defaultID,
            paperAnalysis: paperAnalysis,
            topicKnowledge: topicKnowledge,
            output: output
        )
    }

    public func allTriptychs() -> [TriptychAssignment] {
        let registry = load()
        return sortedTriptychs(registry.triptychs).compactMap { assignment(for: $0, in: registry) }
    }

    public func triptych(id: UUID) -> TriptychAssignment? {
        let registry = load()
        guard let triptych = registry.triptychs.first(where: { $0.id == id }) else { return nil }
        return assignment(for: triptych, in: registry)
    }

    public func resolveTriptych(_ selector: String) throws -> TriptychAssignment {
        let registry = load()
        if let id = UUID(uuidString: selector),
           let triptych = registry.triptychs.first(where: { $0.id == id }),
           let result = assignment(for: triptych, in: registry) {
            return result
        }
        let matches = registry.triptychs.filter {
            $0.name.caseInsensitiveCompare(selector) == .orderedSame
        }.compactMap { assignment(for: $0, in: registry) }
        guard !matches.isEmpty else {
            throw WorkspaceRegistryError.triptychSelectorNotFound(selector)
        }
        guard matches.count == 1 else {
            throw WorkspaceRegistryError.ambiguousTriptychSelector(selector)
        }
        return matches[0]
    }

    /// Compatibility default for one-Triptych callers and the first CLI.
    public func threeVaultWorkspace() -> ThreeVaultWorkspaceAssignment? {
        let registry = load()
        let selected = registry.defaultTriptychID.flatMap { id in
            registry.triptychs.first(where: { $0.id == id })
        } ?? sortedTriptychs(registry.triptychs).first
        guard let selected else { return nil }
        return assignment(for: selected, in: registry)
    }

    public func setDefaultTriptych(id: UUID) throws {
        var registry = try writableRegistry()
        guard registry.triptychs.contains(where: { $0.id == id }) else {
            throw WorkspaceRegistryError.triptychNotFound(id)
        }
        registry.defaultTriptychID = id
        try persist(registry)
    }

    /// Reconciles a machine-local registration with the stable portable
    /// `.scholium/manifest.json` identity without changing any vault UUID.
    public func reidentifyTriptych(id currentID: UUID, as stableID: UUID) throws -> TriptychAssignment {
        var registry = try writableRegistry()
        guard let current = registry.triptychs.first(where: { $0.id == currentID }) else {
            throw WorkspaceRegistryError.triptychNotFound(currentID)
        }
        if currentID == stableID {
            guard let result = assignment(for: current, in: registry) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            return result
        }
        guard !registry.triptychs.contains(where: { $0.id == stableID }) else {
            throw WorkspaceRegistryError.triptychIdentityConflict(stableID)
        }
        let repaired = ScholiumTriptych(
            id: stableID,
            name: current.name,
            paperAnalysisVaultID: current.paperAnalysisVaultID,
            topicKnowledgeVaultID: current.topicKnowledgeVaultID,
            outputVaultID: current.outputVaultID,
            createdAt: current.createdAt,
            updatedAt: Date()
        )
        registry.triptychs.removeAll { $0.id == currentID }
        registry.triptychs.append(repaired)
        if registry.defaultTriptychID == currentID { registry.defaultTriptychID = stableID }
        try persist(registry)
        guard let result = assignment(for: repaired, in: registry) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return result
    }

    public func allVaults() -> [RegisteredVault] {
        load().vaults.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            if $0.canonicalPath != $1.canonicalPath { return $0.canonicalPath < $1.canonicalPath }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func resolve(_ selector: String) throws -> RegisteredVault {
        let vaults = load().vaults
        if let id = UUID(uuidString: selector), let match = vaults.first(where: { $0.id == id }) {
            return match
        }
        let standardizedPath = URL(fileURLWithPath: (selector as NSString).expandingTildeInPath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let matches = vaults.filter {
            $0.name.caseInsensitiveCompare(selector) == .orderedSame || $0.canonicalPath == standardizedPath
        }
        guard !matches.isEmpty else { throw WorkspaceRegistryError.vaultNotFound(selector) }
        guard matches.count == 1 else { throw WorkspaceRegistryError.ambiguousSelector(selector) }
        return matches[0]
    }

    private func canonicalSelections(
        paperAnalysis: (url: URL, identityID: UUID),
        topicKnowledge: (url: URL, identityID: UUID),
        output: (url: URL, identityID: UUID)
    ) throws -> [CanonicalSelection] {
        try [
            (WorkspaceVaultSlot.paperAnalysis, paperAnalysis),
            (WorkspaceVaultSlot.topicKnowledge, topicKnowledge),
            (WorkspaceVaultSlot.output, output),
        ].map { slot, selection in
            CanonicalSelection(
                slot: slot,
                url: try canonicalDirectory(selection.url),
                identityID: selection.identityID
            )
        }
    }

    private func canonicalDirectory(_ url: URL) throws -> URL {
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: canonical.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceRegistryError.notDirectory(url.path)
        }
        return canonical
    }

    private func validateIndependentRoots(_ selections: [CanonicalSelection]) throws {
        for firstIndex in selections.indices {
            for secondIndex in selections.indices where secondIndex > firstIndex {
                let first = selections[firstIndex].url
                let second = selections[secondIndex].url
                if Self.pathsOverlap(first, second) {
                    throw WorkspaceRegistryError.overlappingVaults(first.path, second.path)
                }
            }
        }
    }

    private func validatePortableControlDirectory(
        selections: [CanonicalSelection],
        triptychID: UUID,
        registry: RegistryFile
    ) throws {
        guard let selectedWorks = selections.first(where: { $0.slot == .output })?.url else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let selectedControlPath = selectedWorks.deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
            .standardizedFileURL.path
        for triptych in registry.triptychs where triptych.id != triptychID {
            guard let works = registry.vaults.first(where: {
                $0.id == triptych.outputVaultID
            }) else { continue }
            let existingControlPath = URL(
                fileURLWithPath: works.canonicalPath,
                isDirectory: true
            ).deletingLastPathComponent()
                .appendingPathComponent(".scholium", isDirectory: true)
                .standardizedFileURL.path
            if existingControlPath == selectedControlPath {
                throw WorkspaceRegistryError.triptychControlDirectoryInUse(selectedControlPath)
            }
        }
    }

    private func assignment(
        for triptych: ScholiumTriptych,
        in registry: RegistryFile
    ) -> TriptychAssignment? {
        var vaults: [WorkspaceVaultSlot: RegisteredVault] = [:]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = registry.vaults.first(where: { $0.id == triptych.vaultID(for: slot) }) else {
                return nil
            }
            vaults[slot] = vault
        }
        let parents = Set(vaults.values.map {
            URL(fileURLWithPath: $0.canonicalPath, isDirectory: true)
                .deletingLastPathComponent().path
        })
        return TriptychAssignment(
            triptych: triptych,
            vaults: vaults,
            hasCommonParent: parents.count == 1
        )
    }

    private func inferredTriptychName(from selections: [CanonicalSelection]) -> String {
        let parents = Set(selections.map { $0.url.deletingLastPathComponent().path })
        if parents.count == 1, let parent = parents.first {
            return URL(fileURLWithPath: parent, isDirectory: true).lastPathComponent
        }
        return selections.first(where: { $0.slot == .output })?.url
            .deletingLastPathComponent().lastPathComponent ?? "Triptych"
    }

    private func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Triptych" : trimmed
    }

    private func load() -> RegistryFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: registryURL.path) {
            guard let data = try? Data(contentsOf: registryURL),
                  let decoded = try? decoder.decode(RegistryFile.self, from: data),
                  decoded.schemaVersion == Self.currentSchemaVersion else {
                // Never overwrite a damaged or newer registry with legacy or
                // empty state. Mutating callers fail closed through
                // `writableRegistry()`; read-only callers see no assignments.
                return RegistryFile(
                    schemaVersion: -1,
                    vaults: [],
                    triptychs: [],
                    defaultTriptychID: nil
                )
            }
            return decoded
        }

        let legacyVaults: [RegisteredVault]
        if let data = try? Data(contentsOf: legacyVaultRegistryURL),
           let decoded = try? decoder.decode(LegacyRegistryFile.self, from: data) {
            legacyVaults = decoded.vaults
        } else {
            legacyVaults = []
        }

        var triptychs: [ScholiumTriptych] = []
        if let data = try? Data(contentsOf: legacyThreeVaultWorkspaceURL),
           var legacy = try? decoder.decode(ScholiumTriptych.self, from: data) {
            legacy.name = inferredTriptychName(legacy, vaults: legacyVaults)
            triptychs = [legacy]
        }
        let migrated = RegistryFile(
            schemaVersion: Self.currentSchemaVersion,
            vaults: legacyVaults,
            triptychs: triptychs,
            defaultTriptychID: triptychs.first?.id
        )
        // Migration is additive. The legacy files remain byte-for-byte intact.
        try? persist(migrated)
        return migrated
    }

    private func writableRegistry() throws -> RegistryFile {
        let registry = load()
        guard registry.schemaVersion == Self.currentSchemaVersion else {
            throw WorkspaceRegistryError.corruptRegistry
        }
        return registry
    }

    private func inferredTriptychName(
        _ triptych: ScholiumTriptych,
        vaults: [RegisteredVault]
    ) -> String {
        let assigned = WorkspaceVaultSlot.allCases.compactMap { slot in
            vaults.first(where: { $0.id == triptych.vaultID(for: slot) })
        }
        guard assigned.count == WorkspaceVaultSlot.allCases.count else { return triptych.name }
        let parents = Set(assigned.map {
            URL(fileURLWithPath: $0.canonicalPath, isDirectory: true)
                .deletingLastPathComponent().path
        })
        if parents.count == 1, let parent = parents.first {
            return normalizedName(URL(fileURLWithPath: parent, isDirectory: true).lastPathComponent)
        }
        let works = assigned.first(where: { $0.role == .draftProject })
        return normalizedName(
            works.map {
                URL(fileURLWithPath: $0.canonicalPath, isDirectory: true)
                    .deletingLastPathComponent().lastPathComponent
            } ?? triptych.name
        )
    }

    private func persist(_ registry: RegistryFile) throws {
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(registry).write(to: registryURL, options: .atomic)
    }

    private func sortedTriptychs(_ triptychs: [ScholiumTriptych]) -> [ScholiumTriptych] {
        triptychs.sorted {
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private func replaceVaultID(
        _ oldID: UUID,
        with newID: UUID,
        in triptychs: inout [ScholiumTriptych]
    ) {
        for index in triptychs.indices {
            if triptychs[index].paperAnalysisVaultID == oldID {
                triptychs[index].paperAnalysisVaultID = newID
            }
            if triptychs[index].topicKnowledgeVaultID == oldID {
                triptychs[index].topicKnowledgeVaultID = newID
            }
            if triptychs[index].outputVaultID == oldID {
                triptychs[index].outputVaultID = newID
            }
        }
    }

    private static func pathsOverlap(_ first: URL, _ second: URL) -> Bool {
        let firstComponents = first.standardizedFileURL.pathComponents
        let secondComponents = second.standardizedFileURL.pathComponents
        return firstComponents.starts(with: secondComponents)
            || secondComponents.starts(with: firstComponents)
    }
}
