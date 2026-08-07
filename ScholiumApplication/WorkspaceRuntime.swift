import ScholiumContracts
import Foundation
import ScholiumCore

/// Application-facing bridge for the machine-local registry recovery actions.
/// It does not inspect or mutate any vault source files.
public enum WorkspaceRegistryRecoveryOperations {
    public static func health(storageURL: URL) -> WorkspaceRegistryHealth {
        WorkspaceRegistry.health(storageURL: storageURL)
    }

    @discardableResult
    public static func preserveMalformedRegistryForRelinking(
        storageURL: URL
    ) throws -> URL {
        try WorkspaceRegistry.preserveMalformedRegistryForRelinking(
            storageURL: storageURL
        )
    }
}

/// Process-level composition root for headless Scholium workspaces.
public actor WorkspaceRuntime {
    public struct LiveConfiguration: Sendable {
        public let applicationSupportURL: URL
        public let workspaceRegistryStorageURL: URL

        public init(
            applicationSupportURL: URL,
            workspaceRegistryStorageURL: URL? = nil
        ) {
            self.applicationSupportURL = applicationSupportURL.standardizedFileURL
            self.workspaceRegistryStorageURL = (
                workspaceRegistryStorageURL ?? applicationSupportURL
            ).standardizedFileURL
        }
    }

    public struct SnapshotConfiguration: Sendable {
        public let applicationSupportURL: URL
        public let workspaceRegistryStorageURL: URL
        public let assignments: [TriptychAssignment]
        public let defaultWorkspaceID: UUID?

        public init(
            applicationSupportURL: URL,
            workspaceRegistryStorageURL: URL? = nil,
            assignments: [TriptychAssignment],
            defaultWorkspaceID: UUID? = nil
        ) {
            self.applicationSupportURL = applicationSupportURL.standardizedFileURL
            self.workspaceRegistryStorageURL = (
                workspaceRegistryStorageURL ?? applicationSupportURL
            ).standardizedFileURL
            self.assignments = assignments
            self.defaultWorkspaceID = defaultWorkspaceID
        }
    }

    public enum Configuration: Sendable {
        case live(LiveConfiguration)
        case snapshot(SnapshotConfiguration)
    }

    private enum Membership: Sendable {
        case live(
            registry: WorkspaceRegistry,
            identityRegistry: VaultIdentityRegistry,
            portableControlAccessRegistry: PortableControlAccessRegistry,
            applicationSupportURL: URL
        )
        case snapshot(
            assignments: [UUID: TriptychAssignment],
            defaultWorkspaceID: UUID?,
            applicationSupportURL: URL
        )
    }

    private struct Opening: Sendable {
        let token: UUID
        let task: Task<WorkspaceHandle, Error>
    }

    private struct Replacement: Sendable {
        let previousCacheID: UUID
        let previous: WorkspaceHandle
        let workspaceID: UUID
    }

    private let membership: Membership
    private let vaultPool: WorkspaceVaultPool
    private let savedSearchStore: SavedSearchStore
    private let windowSessionStore: WindowSessionSnapshotStore
    public nonisolated let zotero: ZoteroOperations
    public nonisolated let styles: StyleOperations
    nonisolated let researchAgentSessions: ResearchAgentSessionAuthority?
    private var handles: [UUID: WorkspaceHandle] = [:]
    private var openings: [UUID: Opening] = [:]
    /// A failed replacement must not destroy the activation already borrowed
    /// by a delivery surface. Retained handles stay live until retry or
    /// process shutdown, even though they are no longer returned by new opens.
    private var retainedHandles: [UUID: WorkspaceHandle] = [:]
    private var isShutDown = false

    public init(
        configuration: Configuration,
        zotero injectedZotero: ZoteroOperations? = nil
    ) {
        researchAgentSessions = try? ResearchAgentSessionAuthority()
        switch configuration {
        case .live(let configuration):
            let identityRegistry = VaultIdentityRegistry(
                applicationSupportURL: configuration.applicationSupportURL
            )
            let portableRegistry = PortableControlAccessRegistry(
                applicationSupportURL: configuration.applicationSupportURL
            )
            let registry = WorkspaceRegistry(
                storageURL: configuration.workspaceRegistryStorageURL
            )
            savedSearchStore = SavedSearchStore(
                workspaceStorageURL: configuration.workspaceRegistryStorageURL
            )
            windowSessionStore = WindowSessionSnapshotStore(
                applicationSupportURL: configuration.applicationSupportURL
            )
            vaultPool = WorkspaceVaultPool(
                applicationSupportURL: configuration.applicationSupportURL,
                mode: .live(identityRegistry: identityRegistry)
            )
            zotero = injectedZotero ?? ZoteroOperations()
            styles = StyleOperations(applicationSupportURL: configuration.applicationSupportURL)
            membership = .live(
                registry: registry,
                identityRegistry: identityRegistry,
                portableControlAccessRegistry: portableRegistry,
                applicationSupportURL: configuration.applicationSupportURL
            )
        case .snapshot(let configuration):
            savedSearchStore = SavedSearchStore(
                workspaceStorageURL: configuration.workspaceRegistryStorageURL
            )
            windowSessionStore = WindowSessionSnapshotStore(
                applicationSupportURL: configuration.applicationSupportURL
            )
            vaultPool = WorkspaceVaultPool(
                applicationSupportURL: configuration.applicationSupportURL,
                mode: .snapshot
            )
            zotero = injectedZotero ?? ZoteroOperations()
            styles = StyleOperations(applicationSupportURL: configuration.applicationSupportURL)
            var assignments: [UUID: TriptychAssignment] = [:]
            for assignment in configuration.assignments where assignments[assignment.id] == nil {
                assignments[assignment.id] = assignment
            }
            membership = .snapshot(
                assignments: assignments,
                defaultWorkspaceID: configuration.defaultWorkspaceID,
                applicationSupportURL: configuration.applicationSupportURL
            )
        }
    }

    /// Captures the persisted registry's current assignments into a bounded
    /// snapshot runtime. Later registry changes do not alter its membership.
    public static func snapshot(
        applicationSupportURL: URL,
        workspaceRegistryStorageURL: URL
    ) async throws -> WorkspaceRuntime {
        let registry = WorkspaceRegistry(storageURL: workspaceRegistryStorageURL)
        let assignments = try await registry.allTriptychs()
        let defaultWorkspaceID = try await registry.defaultTriptych()?.id
        return WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: workspaceRegistryStorageURL,
            assignments: assignments,
            defaultWorkspaceID: defaultWorkspaceID
        )))
    }

    public func availableWorkspaces() async throws -> [TriptychAssignment] {
        try requireActive()
        let assignments: [TriptychAssignment]
        switch membership {
        case .live(let registry, _, _, _):
            assignments = try await registry.allTriptychs()
        case .snapshot(let fixed, _, _):
            assignments = Array(fixed.values)
        }
        return assignments.sorted {
            let order = $0.triptych.name.localizedStandardCompare($1.triptych.name)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// Builds a deterministic, source-only workspace bootstrap candidate.
    /// Delivery targets never construct vault or Application Support paths.
    public nonisolated func bootstrapCandidate(
        for request: WorkspaceBootstrapRequest
    ) throws -> WorkspaceBootstrapCandidate {
        try WorkspaceBootstrap.candidate(for: request)
    }

    public func registeredVaults() async throws -> [RegisteredVault] {
        try requireActive()
        switch membership {
        case .live(let registry, _, _, _):
            return try await registry.allVaults()
        case .snapshot(let assignments, _, _):
            return Array(
                Dictionary(
                    assignments.values.flatMap { $0.vaults.values }.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                ).values
            ).sorted {
                if $0.role != $1.role { return $0.role.rawValue < $1.role.rawValue }
                let order = $0.name.localizedStandardCompare($1.name)
                if order != .orderedSame { return order == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    /// Resolves a registered vault without exposing the persistence actor to a
    /// delivery target. Snapshot runtimes resolve only within their immutable
    /// assignment set.
    public func resolveVault(_ selector: String) async throws -> RegisteredVault {
        try requireActive()
        switch membership {
        case .live(let registry, _, _, _):
            return try await registry.resolve(selector)
        case .snapshot:
            let vaults = try await registeredVaults()
            if let id = UUID(uuidString: selector),
               let match = vaults.first(where: { $0.id == id }) {
                return match
            }
            let standardizedPath = URL(
                fileURLWithPath: (selector as NSString).expandingTildeInPath
            ).resolvingSymlinksInPath().standardizedFileURL.path
            let matches = vaults.filter {
                $0.name.caseInsensitiveCompare(selector) == .orderedSame
                    || $0.canonicalPath == standardizedPath
            }
            guard !matches.isEmpty else {
                throw WorkspaceRegistryError.vaultNotFound(selector)
            }
            guard matches.count == 1 else {
                throw WorkspaceRegistryError.ambiguousSelector(selector)
            }
            return matches[0]
        }
    }

    /// Reconciles one persisted assignment with the stable vault identities
    /// at its registered canonical roots. Source files are not modified.
    public func reconcileWorkspaceIdentity(id: UUID) async throws -> TriptychAssignment {
        try requireActive()
        guard case .live(let registry, let identities, _, _) = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        guard let assignment = try await registry.triptych(id: id) else {
            throw ScholiumApplicationError.workspaceNotFound(id)
        }
        var resolved: [WorkspaceVaultSlot: VaultIdentity] = [:]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vault = assignment.vault(for: slot),
                  let identity = await identities.identity(
                    forCanonicalPath: vault.canonicalPath
                  ) else {
                return assignment
            }
            resolved[slot] = identity
        }
        let needsRepair = WorkspaceVaultSlot.allCases.contains { slot in
            assignment.vault(for: slot)?.id != resolved[slot]?.id
        }
        guard needsRepair,
              let analyses = assignment.vault(for: .paperAnalysis),
              let topics = assignment.vault(for: .topicKnowledge),
              let works = assignment.vault(for: .output),
              let analysesIdentity = resolved[.paperAnalysis],
              let topicsIdentity = resolved[.topicKnowledge],
              let worksIdentity = resolved[.output] else {
            return assignment
        }
        let repaired = try await registry.configureTriptych(
            id: assignment.id,
            name: assignment.triptych.name,
            paperAnalysis: (
                URL(fileURLWithPath: analyses.canonicalPath, isDirectory: true),
                analysesIdentity.id
            ),
            topicKnowledge: (
                URL(fileURLWithPath: topics.canonicalPath, isDirectory: true),
                topicsIdentity.id
            ),
            output: (
                URL(fileURLWithPath: works.canonicalPath, isDirectory: true),
                worksIdentity.id
            )
        )
        let prepared = await prepareChangedReplacements(registry: registry)
        let detachedVaults = await detachVaultAuthorities(prepared.invalidatedVaultIDs)
        _ = try await completeReplacements(
            prepared.replacements,
            detachedVaults: detachedVaults
        )
        return repaired
    }

    public func reidentifyWorkspace(
        id currentID: UUID,
        as stableID: UUID
    ) async throws -> TriptychAssignment {
        try requireActive()
        guard case .live(let registry, _, _, _) = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        guard let current = handles[currentID] else {
            throw ScholiumApplicationError.workspaceNotFound(currentID)
        }
        try await current.services.researchConfigurationStore
            .validatePortableIdentityForReidentification(stableID)
        let assignment = try await registry.reidentifyTriptych(id: currentID, as: stableID)
        let prepared = await prepareChangedReplacements(
            registry: registry,
            remappingWorkspaceIDs: [currentID: stableID],
            forcing: [currentID]
        )
        _ = try await completeReplacements(prepared.replacements)
        return assignment
    }

    public func registerVault(
        path: URL,
        name: String?,
        role: VaultRole,
        stableID: UUID? = nil
    ) async throws -> RegisteredVault {
        try requireActive()
        guard case .live(let registry, _, _, _) = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        let updated = try await registry.register(
            path: path,
            name: name,
            role: role,
            stableID: stableID
        )
        let affectedIDs = handles.compactMap { workspaceID, handle in
            handle.assignment.vaults.values.contains(where: { $0.id == updated.id })
                ? workspaceID : nil
        }
        let replacements = await detachReplacements(
            affectedIDs.map { (cacheID: $0, workspaceID: $0) }
        )
        let detachedVaults = replacements.isEmpty
            ? [:]
            : await detachVaultAuthorities([updated.id])
        _ = try await completeReplacements(
            replacements,
            detachedVaults: detachedVaults
        )
        return updated
    }

    public func savedSearches() async throws -> [SavedSearch] {
        try requireActive()
        return try await savedSearchStore.load()
    }

    public func saveSavedSearches(_ searches: [SavedSearch]) async throws {
        try requireActive()
        guard case .live = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        try await savedSearchStore.save(searches)
    }

    public func windowSession(id: UUID) async throws -> WindowSessionSnapshot? {
        try requireActive()
        return try await windowSessionStore.load(id: id)
    }

    public func saveWindowSession(_ snapshot: WindowSessionSnapshot) async throws {
        try requireActive()
        guard case .live = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        try await windowSessionStore.save(snapshot)
    }

    public func saveWindowSession(
        _ snapshot: WindowSessionSnapshot,
        generation: UInt64
    ) async throws {
        try requireActive()
        guard case .live = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        try await windowSessionStore.save(snapshot, generation: generation)
    }

    /// Registers three independently located vaults through the same actors
    /// used for later workspace activation, then returns the one cached handle
    /// for the resulting portable Triptych identity.
    public func configureTriptych(
        paperAnalysisURL: URL,
        topicKnowledgeURL: URL,
        outputURL: URL,
        portableContainerURL: URL,
        triptychID: UUID? = nil,
        triptychName: String? = nil
    ) async throws -> WorkspaceHandle {
        try requireActive()
        guard case .live(
            let registry,
            let identityRegistry,
            let portableRegistry,
            _
        ) = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }

        let portableScopeStarted = portableContainerURL.startAccessingSecurityScopedResource()
        defer {
            if portableScopeStarted {
                portableContainerURL.stopAccessingSecurityScopedResource()
            }
        }
        _ = try await portableRegistry.register(
            containerURL: portableContainerURL,
            forWorksURL: outputURL
        )

        let selections: [(WorkspaceVaultSlot, URL)] = [
            (.paperAnalysis, paperAnalysisURL),
            (.topicKnowledge, topicKnowledgeURL),
            (.output, outputURL),
        ]
        var identities: [WorkspaceVaultSlot: VaultIdentity] = [:]
        for (slot, url) in selections {
            let scopeStarted = url.startAccessingSecurityScopedResource()
            defer { if scopeStarted { url.stopAccessingSecurityScopedResource() } }
            identities[slot] = try await identityRegistry.identity(for: url)
        }
        guard let analysesIdentity = identities[.paperAnalysis],
              let topicsIdentity = identities[.topicKnowledge],
              let worksIdentity = identities[.output] else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }

        let portableID = await portableManifestID(forWorksURL: outputURL)
        var remappedWorkspaceIDs: [UUID: UUID] = [:]
        if let triptychID,
           let portableID,
           triptychID != portableID,
           try await registry.triptych(id: triptychID) != nil {
            _ = try await registry.reidentifyTriptych(id: triptychID, as: portableID)
            remappedWorkspaceIDs[triptychID] = portableID
        }
        let normalizedName = triptychName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignment = try await registry.configureTriptych(
            id: portableID ?? triptychID,
            name: normalizedName?.isEmpty == false ? normalizedName : nil,
            paperAnalysis: (paperAnalysisURL, analysesIdentity.id),
            topicKnowledge: (topicKnowledgeURL, topicsIdentity.id),
            output: (outputURL, worksIdentity.id)
        )
        let prepared = await prepareChangedReplacements(
            registry: registry,
            remappingWorkspaceIDs: remappedWorkspaceIDs
        )
        let detachedVaults = await detachVaultAuthorities(prepared.invalidatedVaultIDs)
        let replacements = try await completeReplacements(
            prepared.replacements,
            detachedVaults: detachedVaults
        )
        if let replacement = replacements[assignment.id] {
            return replacement
        }
        return try await openWorkspace(id: assignment.id)
    }

    public func portableContainerURL(forWorksURL worksURL: URL) async -> URL? {
        guard !isShutDown,
              case .live(_, _, let registry, _) = membership,
              let access = await registry.access(forWorksURL: worksURL) else {
            return nil
        }
        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: access.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), !stale else { return nil }
        let canonical = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == access.canonicalContainerPath,
              resolved.startAccessingSecurityScopedResource() else { return nil }
        resolved.stopAccessingSecurityScopedResource()
        return canonical
    }

    public func portableManifestID(forWorksURL worksURL: URL) async -> UUID? {
        guard !isShutDown else { return nil }
        let store = TriptychControlStore(worksVaultURL: worksURL)
        return try? await store.manifest().id
    }

    /// Returns the persisted default Triptych.
    public func defaultWorkspace() async throws -> TriptychAssignment {
        try requireActive()
        switch membership {
        case .live(let registry, _, _, _):
            guard let assignment = try await registry.defaultTriptych() else {
                throw ScholiumApplicationError.noWorkspaceConfigured
            }
            return assignment
        case .snapshot(let assignments, let defaultWorkspaceID, _):
            if let defaultWorkspaceID, let assignment = assignments[defaultWorkspaceID] {
                return assignment
            }
            guard let first = try await availableWorkspaces().first else {
                throw ScholiumApplicationError.noWorkspaceConfigured
            }
            return first
        }
    }

    /// Repeated opens for one Triptych return the same actor identity until
    /// the runtime is shut down.
    public func openWorkspace(id: UUID) async throws -> WorkspaceHandle {
        try requireActive()
        if let handle = handles[id] { return handle }
        if let opening = openings[id] { return try await opening.task.value }

        let assignment = try await assignment(id: id)
        let token = UUID()
        let task: Task<WorkspaceHandle, Error>
        switch membership {
        case .live(
            _,
            _,
            let portableRegistry,
            let supportURL
        ):
            task = Task {
                try await WorkspaceHandle.open(
                    assignment: assignment,
                    mode: .live,
                    applicationSupportURL: supportURL,
                    windowSessionStore: windowSessionStore,
                    vaultPool: vaultPool,
                    zotero: zotero,
                    researchAgentSessions: researchAgentSessions,
                    access: .live(
                        portableControlAccessRegistry: portableRegistry
                    )
                )
            }
        case .snapshot(_, _, let supportURL):
            task = Task {
                try await WorkspaceHandle.open(
                    assignment: assignment,
                    mode: .snapshot,
                    applicationSupportURL: supportURL,
                    windowSessionStore: windowSessionStore,
                    vaultPool: vaultPool,
                    zotero: zotero,
                    researchAgentSessions: researchAgentSessions,
                    access: .snapshot
                )
            }
        }
        openings[id] = Opening(token: token, task: task)

        do {
            let handle = try await task.value
            if openings[id]?.token == token { openings[id] = nil }
            guard !isShutDown else {
                await handle.shutdown()
                throw ScholiumApplicationError.runtimeShutDown
            }
            if let existing = handles[id] {
                await handle.shutdown()
                return existing
            }
            handles[id] = handle
            return handle
        } catch {
            if openings[id]?.token == token { openings[id] = nil }
            throw error
        }
    }

    public func openWorkspace(selector: String) async throws -> WorkspaceHandle {
        try requireActive()
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: trimmed) {
            return try await openWorkspace(id: id)
        }

        let matches = try await availableWorkspaces().filter {
            $0.triptych.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard let match = matches.first else {
            throw ScholiumApplicationError.workspaceSelectorNotFound(trimmed)
        }
        guard matches.count == 1 else {
            throw ScholiumApplicationError.ambiguousWorkspaceSelector(trimmed)
        }
        return try await openWorkspace(id: match.id)
    }

    /// Cancels in-flight opens, shuts down every cached handle, and prevents
    /// later reuse. Calling shutdown repeatedly is harmless.
    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true

        let pending = openings.values.map(\.task)
        openings.removeAll()
        pending.forEach { $0.cancel() }
        for task in pending {
            if let handle = try? await task.value {
                await handle.shutdown()
            }
        }

        let active = handles.values
        handles.removeAll()
        for handle in active {
            await handle.shutdown()
        }
        let retained = retainedHandles.values
        retainedHandles.removeAll()
        for handle in retained {
            await handle.shutdown()
        }
        await vaultPool.shutdown()
    }

    /// Detaches cached activations without finishing their streams. The old
    /// handles remain usable until `completeReplacements` has opened every
    /// requested successor and published the typed handoff.
    private func detachReplacements(
        _ mappings: [(cacheID: UUID, workspaceID: UUID)]
    ) async -> [Replacement] {
        var replacements: [Replacement] = []
        for mapping in mappings {
            if let opening = openings.removeValue(forKey: mapping.cacheID) {
                opening.task.cancel()
                if let opened = try? await opening.task.value {
                    await opened.shutdown()
                }
            }
            guard let previous = handles.removeValue(forKey: mapping.cacheID) else {
                continue
            }
            replacements.append(Replacement(
                previousCacheID: mapping.cacheID,
                previous: previous,
                workspaceID: mapping.workspaceID
            ))
        }
        return replacements
    }

    /// Opens each successor, publishes `runtimeReloaded` through the old
    /// activation, and only then tears the old activation down. New opens and
    /// every existing subscriber therefore converge on the same cached actor.
    @discardableResult
    private func completeReplacements(
        _ replacements: [Replacement],
        detachedVaults: [UUID: PooledWorkspaceVault] = [:]
    ) async throws -> [UUID: WorkspaceHandle] {
        var successors: [UUID: WorkspaceHandle] = [:]
        var successorSnapshots: [UUID: WorkspaceSnapshot] = [:]
        do {
            for replacement in replacements {
                let successor = try await openWorkspace(id: replacement.workspaceID)
                successors[replacement.workspaceID] = successor
                successorSnapshots[replacement.workspaceID] = try await successor.snapshot()
            }
            // Publication and retirement are nonthrowing after every successor
            // has opened. Peers cannot observe a half-completed handoff.
            for replacement in replacements {
                guard let successor = successors[replacement.workspaceID],
                      let snapshot = successorSnapshots[replacement.workspaceID] else {
                    continue
                }
                await replacement.previous.announceRuntimeReplacement(
                    runtimeIdentity: successor.runtimeIdentity,
                    snapshot: snapshot
                )
                await replacement.previous.shutdown()
                let previousActivationID = replacement.previous.runtimeIdentity.activationID
                retainedHandles[previousActivationID] = nil
            }
            for previousVault in detachedVaults.values {
                await previousVault.shutdown()
            }
            return successors
        } catch {
            for (workspaceID, successor) in successors {
                if handles[workspaceID] === successor {
                    handles[workspaceID] = nil
                }
                await successor.shutdown()
            }
            for (vaultID, previousVault) in detachedVaults {
                await vaultPool.restore(previousVault, vaultID: vaultID)
            }
            for replacement in replacements {
                // Keep a prior activation alive on partial failure. For a
                // same-identity update it remains the safest cached fallback;
                // after reidentification it is retained solely for consumers
                // that already borrowed it and for deterministic shutdown.
                if replacement.previousCacheID == replacement.workspaceID,
                   handles[replacement.previousCacheID] == nil {
                    handles[replacement.previousCacheID] = replacement.previous
                } else {
                    retainedHandles[replacement.previous.runtimeIdentity.activationID] =
                        replacement.previous
                }
            }
            throw error
        }
    }

    private func detachVaultAuthorities(
        _ vaultIDs: Set<UUID>
    ) async -> [UUID: PooledWorkspaceVault] {
        var detached: [UUID: PooledWorkspaceVault] = [:]
        for vaultID in vaultIDs {
            if let previous = await vaultPool.detach(vaultID: vaultID) {
                detached[vaultID] = previous
            }
        }
        return detached
    }

    private func changedVaultIDs(
        from previous: TriptychAssignment,
        to current: TriptychAssignment
    ) -> Set<UUID> {
        var changed: Set<UUID> = []
        for slot in WorkspaceVaultSlot.allCases {
            let old = previous.vault(for: slot)
            let new = current.vault(for: slot)
            guard old != new else { continue }
            if let old { changed.insert(old.id) }
            if let new { changed.insert(new.id) }
        }
        return changed
    }

    private func prepareChangedReplacements(
        registry: WorkspaceRegistry,
        remappingWorkspaceIDs remappedIDs: [UUID: UUID] = [:],
        forcing forcedIDs: Set<UUID> = []
    ) async -> (replacements: [Replacement], invalidatedVaultIDs: Set<UUID>) {
        var mappings: [(cacheID: UUID, workspaceID: UUID)] = []
        var invalidatedVaultIDs: Set<UUID> = []
        for (cacheID, handle) in handles {
            let workspaceID = remappedIDs[cacheID] ?? cacheID
            guard let current = try? await registry.triptych(id: workspaceID) else {
                continue
            }
            guard forcedIDs.contains(cacheID) || handle.assignment != current else {
                continue
            }
            mappings.append((cacheID, workspaceID))
            invalidatedVaultIDs.formUnion(
                changedVaultIDs(from: handle.assignment, to: current)
            )
        }
        let replacements = await detachReplacements(mappings)
        return (replacements, invalidatedVaultIDs)
    }

    private func assignment(id: UUID) async throws -> TriptychAssignment {
        switch membership {
        case .live(let registry, _, _, _):
            guard let assignment = try await registry.triptych(id: id) else {
                throw ScholiumApplicationError.workspaceNotFound(id)
            }
            return assignment
        case .snapshot(let assignments, _, _):
            guard let assignment = assignments[id] else {
                throw ScholiumApplicationError.workspaceNotFound(id)
            }
            return assignment
        }
    }

    private func requireActive() throws {
        if isShutDown { throw ScholiumApplicationError.runtimeShutDown }
    }

    // Internal architecture evidence; delivery capabilities do not expose
    // pool identities or native watcher ownership.
    var pooledVaultRuntimeCount: Int {
        get async { await vaultPool.runtimeCount }
    }

    func pooledVaultSubscriberCount(vaultID: UUID) async -> Int? {
        guard let runtime = await vaultPool.runtime(vaultID: vaultID) else { return nil }
        return await runtime.subscriberCount
    }

    func pooledVaultOwnsNativeWatcher(vaultID: UUID) async -> Bool? {
        guard let runtime = await vaultPool.runtime(vaultID: vaultID) else { return nil }
        return await runtime.ownsNativeWatcher
    }
}
