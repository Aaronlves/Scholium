import ScholiumContracts
import Foundation

public actor WorkspaceRegistry {
    public static let currentSchemaVersion = 2

    private struct RegistryFile: Codable {
        var schemaVersion: Int
        var vaults: [RegisteredVault]
        var triptychs: [ScholiumTriptych]
        var defaultTriptychID: UUID?
    }

    private struct SchemaProbe: Decodable {
        let schemaVersion: Int
    }

    private struct CanonicalSelection {
        let slot: WorkspaceVaultSlot
        let url: URL
        let identityID: UUID
    }

    public let storageURL: URL
    private let registryURL: URL
    private let fileManager: FileManager

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        registryURL = Self.registryURL(storageURL: storageURL)
        self.fileManager = fileManager
    }

    public nonisolated static func registryURL(storageURL: URL) -> URL {
        storageURL.standardizedFileURL.appendingPathComponent("workspace-registry-v2.json")
    }

    public nonisolated static func health(storageURL: URL) -> WorkspaceRegistryHealth {
        let registryURL = registryURL(storageURL: storageURL)
        let data: Data
        do {
            data = try Data(contentsOf: registryURL)
        } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .healthy
        } catch {
            return .ioFailure(error.localizedDescription)
        }
        return health(for: data)
    }

    private nonisolated static func health(for data: Data) -> WorkspaceRegistryHealth {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let version = try decoder.decode(SchemaProbe.self, from: data).schemaVersion
            if version > currentSchemaVersion {
                return .unsupportedNewerSchema(version)
            }
            guard version == currentSchemaVersion else {
                return .malformedCurrentSchema(
                    "Schema \(version) is not supported by this Scholium version."
                )
            }
            let registry = try decoder.decode(RegistryFile.self, from: data)
            if let issue = registryIntegrityIssue(registry) {
                return .malformedCurrentSchema(issue)
            }
            return .healthy
        } catch {
            return .malformedCurrentSchema(error.localizedDescription)
        }
    }

    /// Preserves a malformed current registry before the researcher explicitly
    /// relinks their existing Triptych. Newer and unreadable registries stay
    /// in place because this build cannot safely classify their contents.
    @discardableResult
    public nonisolated static func preserveMalformedRegistryForRelinking(
        storageURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let source = registryURL(storageURL: storageURL)
        let sourceData: Data
        let sourceIdentity: String
        do {
            sourceData = try Data(contentsOf: source)
            let values = try source.resourceValues(forKeys: [.fileResourceIdentifierKey])
            guard let identifier = values.fileResourceIdentifier else {
                throw CocoaError(.fileReadUnknown)
            }
            sourceIdentity = String(describing: identifier)
        } catch {
            throw WorkspaceRegistryError.registryRecoveryRequired(.ioFailure(
                "The damaged registry could not be bound to one readable file before recovery: \(error.localizedDescription)"
            ))
        }
        let health = health(for: sourceData)
        guard health.canRelinkAfterPreserving else {
            throw WorkspaceRegistryError.registryRecoveryRequired(health)
        }
        try fileManager.createDirectory(
            at: storageURL,
            withIntermediateDirectories: true
        )
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let destination = storageURL.standardizedFileURL.appendingPathComponent(
            "workspace-registry-v2.corrupt-\(timestamp)-\(UUID().uuidString.lowercased()).json"
        )
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw WorkspaceRegistryError.registryRecoveryRequired(.ioFailure(
                "The damaged registry could not be preserved: \(error.localizedDescription)"
            ))
        }
        do {
            let movedData = try Data(contentsOf: destination)
            let movedValues = try destination.resourceValues(forKeys: [.fileResourceIdentifierKey])
            let movedIdentity = movedValues.fileResourceIdentifier.map(String.init(describing:))
            guard movedData == sourceData, movedIdentity == sourceIdentity else {
                if !fileManager.fileExists(atPath: source.path) {
                    try? fileManager.moveItem(at: destination, to: source)
                }
                throw WorkspaceRegistryError.registryRecoveryRequired(.ioFailure(
                    "The registry changed while recovery was preparing its preserved copy; no replacement was authorized."
                ))
            }
        } catch let error as WorkspaceRegistryError {
            throw error
        } catch {
            throw WorkspaceRegistryError.registryRecoveryRequired(.ioFailure(
                "The preserved registry could not be verified: \(error.localizedDescription)"
            ))
        }
        return destination
    }

    public func health() -> WorkspaceRegistryHealth {
        Self.health(storageURL: storageURL)
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
        try validateIndependentIdentities(canonical)

        var registry = try writableRegistry()
        let triptychID = requestedID ?? output.identityID
        try validatePortableControlDirectory(
            selections: canonical,
            triptychID: triptychID,
            registry: registry
        )
        try validateRegistrationConflicts(
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
            let samePath = registry.vaults.first(where: { $0.canonicalPath == selection.url.path })
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

    /// Validates one complete selection without changing the machine-local
    /// registry. Application calls this before bookmarks or identities are
    /// recorded so a rejected selection has no partial registration effects.
    public func preflightTriptychConfiguration(
        id requestedID: UUID,
        paperAnalysis: (url: URL, identityID: UUID),
        topicKnowledge: (url: URL, identityID: UUID),
        output: (url: URL, identityID: UUID)
    ) throws {
        let selections = try canonicalSelections(
            paperAnalysis: paperAnalysis,
            topicKnowledge: topicKnowledge,
            output: output
        )
        try validateIndependentRoots(selections)
        try validateIndependentIdentities(selections)
        let registry = try load()
        try validatePortableControlDirectory(
            selections: selections,
            triptychID: requestedID,
            registry: registry
        )
        try validateRegistrationConflicts(
            selections: selections,
            triptychID: requestedID,
            registry: registry
        )
    }

    /// Validates only directory existence and separation. Application calls
    /// this before planning identities so an obvious duplicate or nested
    /// selection receives the directory error without any registry mutation.
    public func preflightIndependentVaultRoots(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL
    ) throws {
        let selections = try canonicalSelections(
            paperAnalysis: (paperAnalysisURL, UUID()),
            topicKnowledge: (topicKnowledgeURL, UUID()),
            output: (outputURL, UUID())
        )
        try validateIndependentRoots(selections)
    }

    public func allTriptychs() throws -> [TriptychAssignment] {
        let registry = try load()
        return try sortedTriptychs(registry.triptychs).map { triptych in
            guard let assignment = assignment(for: triptych, in: registry) else {
                throw WorkspaceRegistryError.registryRecoveryRequired(.malformedCurrentSchema(
                    "Triptych \(triptych.id.uuidString) does not reference three registered vaults."
                ))
            }
            return assignment
        }
    }

    public func triptych(id: UUID) throws -> TriptychAssignment? {
        let registry = try load()
        guard let triptych = registry.triptychs.first(where: { $0.id == id }) else { return nil }
        return assignment(for: triptych, in: registry)
    }

    public func defaultTriptych() throws -> TriptychAssignment? {
        let registry = try load()
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

    /// Removes only one machine-local Triptych registration. Research folders
    /// and portable `.scholium` data remain untouched, and vault registrations
    /// still referenced by another Triptych remain available.
    public func removeTriptychRegistration(id: UUID) throws {
        var registry = try writableRegistry()
        guard let removed = registry.triptychs.first(where: { $0.id == id }) else {
            throw WorkspaceRegistryError.triptychNotFound(id)
        }

        let removedVaultIDs = Set(
            WorkspaceVaultSlot.allCases.map { removed.vaultID(for: $0) }
        )
        registry.triptychs.removeAll { $0.id == id }
        let remainingVaultIDs = Set(registry.triptychs.flatMap { triptych in
            WorkspaceVaultSlot.allCases.map { triptych.vaultID(for: $0) }
        })
        registry.vaults.removeAll {
            removedVaultIDs.contains($0.id) && !remainingVaultIDs.contains($0.id)
        }
        if registry.defaultTriptychID == id {
            registry.defaultTriptychID = sortedTriptychs(registry.triptychs).first?.id
        }
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

    public func allVaults() throws -> [RegisteredVault] {
        try load().vaults.sorted {
            if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            if $0.canonicalPath != $1.canonicalPath { return $0.canonicalPath < $1.canonicalPath }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public func resolve(_ selector: String) throws -> RegisteredVault {
        let vaults = try load().vaults
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

    private func validateIndependentIdentities(
        _ selections: [CanonicalSelection]
    ) throws {
        var seen: Set<UUID> = []
        for selection in selections where !seen.insert(selection.identityID).inserted {
            throw WorkspaceRegistryError.duplicateVaultIdentity(selection.identityID)
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

    private func validateRegistrationConflicts(
        selections: [CanonicalSelection],
        triptychID: UUID,
        registry: RegistryFile
    ) throws {
        let previousVaultIDs = registry.triptychs
            .first(where: { $0.id == triptychID })
            .map { triptych in
                Set(WorkspaceVaultSlot.allCases.map { triptych.vaultID(for: $0) })
            } ?? []

        for selection in selections {
            if let conflicting = registry.vaults.first(where: {
                $0.id == selection.identityID && $0.canonicalPath != selection.url.path
            }), !previousVaultIDs.contains(selection.identityID) {
                throw WorkspaceRegistryError.vaultIdentityMismatch(
                    selection.identityID,
                    conflicting.canonicalPath,
                    selection.url.path
                )
            }
            if let samePath = registry.vaults.first(where: {
                $0.canonicalPath == selection.url.path
            }) {
                guard samePath.id == selection.identityID else {
                    throw WorkspaceRegistryError.vaultIdentityMismatch(
                        selection.identityID,
                        samePath.canonicalPath,
                        selection.url.path
                    )
                }
                guard samePath.role == selection.slot.vaultRole else {
                    throw WorkspaceRegistryError.vaultRoleMismatch(
                        selection.identityID,
                        samePath.role,
                        selection.slot.vaultRole
                    )
                }
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

    private func load() throws -> RegistryFile {
        let health = Self.health(storageURL: storageURL)
        guard health.isHealthy else {
            throw WorkspaceRegistryError.registryRecoveryRequired(health)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: registryURL.path) {
            let data = try Data(contentsOf: registryURL)
            let registry = try decoder.decode(RegistryFile.self, from: data)
            if let issue = registryIntegrityIssue(registry) {
                throw WorkspaceRegistryError.registryRecoveryRequired(
                    .malformedCurrentSchema(issue)
                )
            }
            return registry
        }

        return RegistryFile(
            schemaVersion: Self.currentSchemaVersion,
            vaults: [],
            triptychs: [],
            defaultTriptychID: nil
        )
    }

    private func writableRegistry() throws -> RegistryFile {
        try load()
    }

    private static func registryIntegrityIssue(_ registry: RegistryFile) -> String? {
        let vaultIDs = registry.vaults.map(\.id)
        guard Set(vaultIDs).count == vaultIDs.count else {
            return "The registry contains duplicate vault identities."
        }
        let paths = registry.vaults.map(\.canonicalPath)
        guard paths.allSatisfy({ !$0.isEmpty }), Set(paths).count == paths.count else {
            return "The registry contains empty or duplicate vault paths."
        }
        let triptychIDs = registry.triptychs.map(\.id)
        guard Set(triptychIDs).count == triptychIDs.count else {
            return "The registry contains duplicate Triptych identities."
        }
        let registeredVaults = Dictionary(uniqueKeysWithValues: registry.vaults.map { ($0.id, $0) })
        for triptych in registry.triptychs {
            let references = WorkspaceVaultSlot.allCases.map { triptych.vaultID(for: $0) }
            guard Set(references).count == WorkspaceVaultSlot.allCases.count else {
                return "Triptych \(triptych.id.uuidString) reuses one vault for multiple roles."
            }
            for slot in WorkspaceVaultSlot.allCases {
                guard let vault = registeredVaults[triptych.vaultID(for: slot)] else {
                    return "Triptych \(triptych.id.uuidString) references a missing \(slot.displayName) vault."
                }
                guard vault.role == slot.vaultRole else {
                    return "Triptych \(triptych.id.uuidString) assigns vault \(vault.id.uuidString) to the wrong role."
                }
            }
        }
        if let defaultTriptychID = registry.defaultTriptychID,
           !triptychIDs.contains(defaultTriptychID) {
            return "The registry default Triptych is not registered."
        }
        return nil
    }

    private func registryIntegrityIssue(_ registry: RegistryFile) -> String? {
        Self.registryIntegrityIssue(registry)
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

    private static func pathsOverlap(_ first: URL, _ second: URL) -> Bool {
        let firstComponents = first.standardizedFileURL.pathComponents
        let secondComponents = second.standardizedFileURL.pathComponents
        return firstComponents.starts(with: secondComponents)
            || secondComponents.starts(with: firstComponents)
    }
}
