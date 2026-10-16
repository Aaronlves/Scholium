import Foundation
import OSLog
import ScholiumContracts
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
    private nonisolated static let openLogger = Logger(
        subsystem: "com.scholium.app",
        category: "WorkspaceOpen"
    )

    public struct LiveConfiguration: Sendable {
        public let applicationSupportURL: URL
        public let workspaceRegistryStorageURL: URL

        public init(
            applicationSupportURL: URL,
            workspaceRegistryStorageURL: URL? = nil
        ) {
            self.applicationSupportURL = applicationSupportURL.standardizedFileURL
            self.workspaceRegistryStorageURL = (workspaceRegistryStorageURL ?? applicationSupportURL).standardizedFileURL
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
            self.workspaceRegistryStorageURL = (workspaceRegistryStorageURL ?? applicationSupportURL).standardizedFileURL
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

    private struct StorageOperation: Sendable {
        let id: UUID
        let action: ScholiumStorageAction
        let triptychID: UUID?
        let task: Task<ScholiumStorageOperationResult, Error>
    }

    private struct Replacement: Sendable {
        let previousCacheID: UUID
        let previous: WorkspaceHandle
        let workspaceID: UUID
    }

    private let membership: Membership
    private let vaultPool: WorkspaceVaultPool
    private let savedSearchStore: SavedSearchStore
    private let searchTermGroupStore: SearchTermGroupStore
    private let windowSessionStore: WindowSessionSnapshotStore
    public nonisolated let zotero: ZoteroOperations
    public nonisolated let styles: StyleOperations
    private var handles: [UUID: WorkspaceHandle] = [:]
    private var openings: [UUID: Opening] = [:]
    /// A failed replacement must not destroy the activation already borrowed
    /// by a delivery surface. Retained handles stay live until retry or
    /// process shutdown, even though they are no longer returned by new opens.
    private var retainedHandles: [UUID: WorkspaceHandle] = [:]
    private var isShutDown = false
    private var shutdownTask: Task<Void, Never>?
    private var storageOperation: StorageOperation?
    #if DEBUG
        private(set) var shutdownJoinCountForTesting = 0
        private(set) var openingLookupCountForTesting = 0
        private(set) var openingFactoryCountForTesting = 0
        private(set) var openingJoinCountForTesting = 0
        private(set) var storageOpeningJoinCountForTesting = 0
        private var openingLookupBarrierForTesting: (@Sendable (UUID) async -> Void)?

        func setOpeningLookupBarrierForTesting(_ barrier: (@Sendable (UUID) async -> Void)?) {
            openingLookupBarrierForTesting = barrier
        }
    #endif
    private typealias MaintenanceResult = Result<DerivedStateMaintenanceSummary, Error>
    private enum MaintenancePhase: Equatable { case waiting, running }
    private struct MaintenanceWork {
        let id: UUID
        var phase: MaintenancePhase
        let task: Task<MaintenanceResult?, Never>
    }
    private var deferredMaintenanceTask: MaintenanceWork?
    private var didMaintainDerivedState = false
    private(set) var latestDerivedStateMaintenanceSummary: DerivedStateMaintenanceSummary?
    #if DEBUG
        private(set) var derivedMaintenancePassCountForTesting = 0
        private(set) var derivedMaintenanceJoinCountForTesting = 0
        private(set) var derivedMaintenanceWaitingCancellationCountForTesting = 0
        private var derivedMaintenanceBarrierForTesting: (@Sendable (Int) async -> Void)?

        var derivedMaintenancePhaseForTesting: String? {
            switch deferredMaintenanceTask?.phase {
            case .waiting: "waiting"
            case .running: "running"
            case nil: nil
            }
        }

        func setDerivedMaintenanceBarrierForTesting(_ barrier: (@Sendable (Int) async -> Void)?) {
            derivedMaintenanceBarrierForTesting = barrier
        }
    #endif

    /// One automatic pass follows a cached Handle's complete opening. Listing
    /// membership never waits for disposable-state scans or creates a worker.
    private func scheduleDerivedMaintenance(after handle: WorkspaceHandle) {
        guard case .live = membership, !isShutDown, !didMaintainDerivedState,
            deferredMaintenanceTask == nil
        else { return }
        let id = UUID()
        let source = handle.events
        let task = Task<MaintenanceResult?, Never>(priority: .utility) { [weak self] in
            let completed = await Self.waitForCompleteOpening(source)
            guard completed, !Task.isCancelled, let self else {
                await self?.finishDerivedMaintenance(id: id)
                return nil
            }
            return await self.executeDerivedMaintenance(id: id)
        }
        deferredMaintenanceTask = MaintenanceWork(id: id, phase: .waiting, task: task)
    }

    private nonisolated static func waitForCompleteOpening(_ source: WorkspaceEventSource) async -> Bool {
        // Keep the observer awaiting its next event after signaling readiness.
        // Cancellation then retires its EventSource subscription explicitly.
        let readiness = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let observer = Task {
            let stream = await source.events()
            var signaled = false
            for await event in stream {
                guard !Task.isCancelled else { break }
                if !signaled, event.snapshot.phase.isComplete {
                    signaled = true
                    readiness.continuation.yield(true)
                }
            }
            if !signaled { readiness.continuation.yield(false) }
            readiness.continuation.finish()
        }
        let completed = await withTaskCancellationHandler {
            var iterator = readiness.stream.makeAsyncIterator()
            return await iterator.next() ?? false
        } onCancel: {
            observer.cancel()
        }
        observer.cancel()
        await observer.value
        return completed && !Task.isCancelled
    }

    private func finishDerivedMaintenance(id: UUID) {
        if deferredMaintenanceTask?.id == id { deferredMaintenanceTask = nil }
    }

    /// The worker never calls the joining entry point, so it cannot await its
    /// own Task. Tokens prevent a retired waiter from clearing a newer pass.
    private func executeDerivedMaintenance(id: UUID, duringShutdown: Bool = false) async -> MaintenanceResult? {
        guard deferredMaintenanceTask?.id == id, !Task.isCancelled,
            !isShutDown || duringShutdown,
            case .live(let registry, let supportURL) = membership
        else {
            finishDerivedMaintenance(id: id)
            return nil
        }
        deferredMaintenanceTask?.phase = .running
        didMaintainDerivedState = true
        defer { finishDerivedMaintenance(id: id) }
        #if DEBUG
            derivedMaintenancePassCountForTesting += 1
            if let derivedMaintenanceBarrierForTesting {
                await derivedMaintenanceBarrierForTesting(derivedMaintenancePassCountForTesting)
            }
        #endif
        do {
            try Task.checkCancellation()
            let summary = try await registry.maintainDerivedState(applicationSupportURL: supportURL)
            latestDerivedStateMaintenanceSummary = summary
            Self.openLogger.info(
                "derivedMaintenance removedFiles=\(summary.removedFiles) removedBytes=\(summary.removedBytes) busyDirectories=\(summary.busyDirectories) failedDirectories=\(summary.failedDirectories) failedFiles=\(summary.failedFiles) preservedFiles=\(summary.preservedFiles)"
            )
            return .success(summary)
        } catch {
            // A failed registry read is never an empty reference set.
            latestDerivedStateMaintenanceSummary = DerivedStateMaintenanceSummary(failedDirectories: 1)
            Self.openLogger.error("derivedMaintenance unavailable; no membership-based deletion admitted")
            return .failure(error)
        }
    }

    @discardableResult
    private func maintainDerivedStateIfNeeded(force: Bool = false, duringShutdown: Bool = false) async -> MaintenanceResult? {
        guard case .live = membership, !isShutDown || duringShutdown else { return nil }
        while let work = deferredMaintenanceTask {
            #if DEBUG
                derivedMaintenanceJoinCountForTesting += 1
            #endif
            if work.phase == .waiting {
                #if DEBUG
                    derivedMaintenanceWaitingCancellationCountForTesting += 1
                #endif
                work.task.cancel()
            }
            _ = await work.task.value
            finishDerivedMaintenance(id: work.id)
        }
        guard !Task.isCancelled, !isShutDown || duringShutdown,
            force || !didMaintainDerivedState
        else { return nil }
        let id = UUID()
        let task = Task<MaintenanceResult?, Never>(priority: .utility) { [weak self] in
            guard let self else { return nil }
            return await self.executeDerivedMaintenance(id: id, duringShutdown: duringShutdown)
        }
        deferredMaintenanceTask = MaintenanceWork(id: id, phase: .running, task: task)
        return await task.value
    }

    public init(
        configuration: Configuration,
        zotero injectedZotero: ZoteroOperations? = nil
    ) {
        switch configuration {
        case .live(let configuration):
            let registry = WorkspaceRegistry(
                storageURL: configuration.workspaceRegistryStorageURL
            )
            searchTermGroupStore = SearchTermGroupStore(workspaceStorageURL: configuration.workspaceRegistryStorageURL)
            savedSearchStore = SavedSearchStore(
                workspaceStorageURL: configuration.workspaceRegistryStorageURL
            )
            windowSessionStore = WindowSessionSnapshotStore(
                applicationSupportURL: configuration.applicationSupportURL
            )
            vaultPool = WorkspaceVaultPool(
                applicationSupportURL: configuration.applicationSupportURL,
                mode: .live
            )
            zotero = injectedZotero ?? ZoteroOperations(applicationSupportURL: configuration.applicationSupportURL)
            styles = StyleOperations(applicationSupportURL: configuration.applicationSupportURL)
            membership = .live(
                registry: registry,
                applicationSupportURL: configuration.applicationSupportURL
            )
        case .snapshot(let configuration):
            searchTermGroupStore = SearchTermGroupStore(workspaceStorageURL: configuration.workspaceRegistryStorageURL)
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
            zotero = injectedZotero ?? ZoteroOperations(applicationSupportURL: configuration.applicationSupportURL)
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
        return WorkspaceRuntime(
            configuration: .snapshot(
                .init(
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
        case .live(let registry, _):
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

    /// Removes one unavailable machine-local registration without opening or
    /// inspecting its vaults. Active runtimes must be closed first so a
    /// registered source cannot disappear beneath an owned document session.
    public func removeLocalTriptychRegistration(id: UUID) async throws {
        try requireActive()
        guard case .live(let registry, _) = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        guard handles[id] == nil,
            openings[id] == nil,
            !retainedHandles.values.contains(where: { $0.assignment.id == id })
        else {
            throw ScholiumApplicationError.workspaceRegistrationInUse(id)
        }
        try await registry.removeTriptychRegistration(id: id)
        await maintainDerivedStateIfNeeded(force: true)
    }

    /// Explicitly archives one unsupported `.scholium` owner so the selected
    /// folders can be configured against current control state. This requires
    /// a fresh folder authorization and refuses any active/opening Triptych.
    @discardableResult
    public func preserveUnsupportedPortableControl(
        portableContainerURL: URL,
        worksURL: URL,
        triptychID: UUID? = nil
    ) async throws -> URL {
        try requireActive()
        guard case .live = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        if let triptychID,
            handles[triptychID] != nil || openings[triptychID] != nil
                || retainedHandles.values.contains(where: { $0.assignment.id == triptychID })
        {
            throw ScholiumApplicationError.workspaceRegistrationInUse(triptychID)
        }
        let container = portableContainerURL.resolvingSymlinksInPath().standardizedFileURL
        let expected = worksURL.standardizedFileURL.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL
        guard container.path == expected.path else {
            throw PortableControlAccessError.invalidContainer(
                expected: expected.path,
                selected: container.path
            )
        }
        let scopeStarted = portableContainerURL.startAccessingSecurityScopedResource()
        defer { if scopeStarted { portableContainerURL.stopAccessingSecurityScopedResource() } }
        return try await TriptychControlStore.preserveUnsupportedControlBundle(
            worksVaultURL: worksURL
        )
    }

    public func registeredVaults() async throws -> [RegisteredVault] {
        try requireActive()
        switch membership {
        case .live(let registry, _):
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
        case .live(let registry, _):
            return try await registry.resolve(selector)
        case .snapshot:
            let vaults = try await registeredVaults()
            if let id = UUID(uuidString: selector),
                let match = vaults.first(where: { $0.id == id })
            {
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
        guard case .live(let registry, _) = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        guard let assignment = try await registry.triptych(id: id) else {
            throw ScholiumApplicationError.workspaceNotFound(id)
        }
        return assignment
    }

    public func reidentifyWorkspace(
        id currentID: UUID,
        as stableID: UUID
    ) async throws -> TriptychAssignment {
        try requireActive()
        guard case .live(let registry, _) = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        guard handles[currentID] != nil else {
            throw ScholiumApplicationError.workspaceNotFound(currentID)
        }
        let assignment = try await registry.reidentifyTriptych(id: currentID, as: stableID)
        let prepared = await prepareChangedReplacements(
            registry: registry,
            remappingWorkspaceIDs: [currentID: stableID],
            forcing: [currentID]
        )
        _ = try await completeReplacements(prepared.replacements)
        await maintainDerivedStateIfNeeded(force: true)
        return assignment
    }

    public func registerVault(
        path: URL,
        name: String?,
        role: VaultRole,
        stableID: UUID? = nil
    ) async throws -> RegisteredVault {
        try requireActive()
        guard case .live(let registry, _) = membership else {
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
        let detachedVaults =
            replacements.isEmpty
            ? [:]
            : await detachVaultAuthorities([updated.id])
        _ = try await completeReplacements(
            replacements,
            detachedVaults: detachedVaults
        )
        await maintainDerivedStateIfNeeded(force: true)
        return updated
    }

    public func searchTermGroups() async throws -> [SearchTermGroup] {
        try requireActive()
        return try await searchTermGroupStore.load()
    }
    public func saveSearchTermGroup(_ group: SearchTermGroup, replacing expected: SearchTermGroup?) async throws -> [SearchTermGroup] {
        try requireActive()
        guard case .live = membership else { throw ScholiumApplicationError.runtimeConfigurationUnavailable }
        return try await searchTermGroupStore.save(group, replacing: expected)
    }
    public func deleteSearchTermGroup(_ group: SearchTermGroup) async throws -> [SearchTermGroup] {
        try requireActive()
        guard case .live = membership else { throw ScholiumApplicationError.runtimeConfigurationUnavailable }
        return try await searchTermGroupStore.delete(group)
    }

    public func savedSearches() async throws -> [SavedSearch] {
        try requireActive()
        return try await savedSearchStore.load()
    }

    public func saveSavedSearches(_ searches: [SavedSearch], replacing expected: [SavedSearch]) async throws {
        try requireActive()
        guard case .live = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        try await savedSearchStore.save(searches, replacing: expected)
    }

    @discardableResult
    public func preserveUnreadableSavedSearchesAndReset() async throws -> URL? {
        try requireActive()
        guard case .live = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }
        return try await savedSearchStore.preserveUnreadableAndReset()
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
        triptychName: String? = nil,
        openingVault: WorkspaceVaultSlot? = nil
    ) async throws -> WorkspaceHandle {
        let clock = ContinuousClock()
        let totalStart = clock.now
        try requireActive()
        guard case .live(let registry, _) = membership else {
            throw ScholiumApplicationError.runtimeConfigurationUnavailable
        }

        let portableScopeStarted = portableContainerURL.startAccessingSecurityScopedResource()
        defer {
            if portableScopeStarted {
                portableContainerURL.stopAccessingSecurityScopedResource()
            }
        }
        let portableManifest = try await existingPortableManifest(
            forWorksURL: outputURL
        )
        if let portableManifest {
            try await preflightExistingPortableControl(
                worksURL: outputURL,
                manifest: portableManifest
            )
        } else {
            try preflightPortableControlWithoutManifest(worksURL: outputURL)
        }
        let canonicalContainer = portableContainerURL.resolvingSymlinksInPath()
            .standardizedFileURL
        let expectedContainer = outputURL.resolvingSymlinksInPath()
            .standardizedFileURL.deletingLastPathComponent()
        guard canonicalContainer.path == expectedContainer.path else {
            throw PortableControlAccessError.invalidContainer(
                expected: expectedContainer.path,
                selected: canonicalContainer.path
            )
        }
        try await registry.preflightIndependentVaultRoots(
            paperAnalysisURL: paperAnalysisURL,
            topicKnowledgeURL: topicKnowledgeURL,
            outputURL: outputURL
        )
        let selections: [(WorkspaceVaultSlot, URL)] = [
            (.paperAnalysis, paperAnalysisURL),
            (.topicKnowledge, topicKnowledgeURL),
            (.output, outputURL),
        ]
        var plannedIdentityIDs: [WorkspaceVaultSlot: UUID] = [:]
        for (slot, url) in selections {
            plannedIdentityIDs[slot] = try await registry.plannedIdentityID(
                for: url,
                preferredID: portableManifest?.vaultIDs[slot]
            )
        }
        guard let analysesID = plannedIdentityIDs[.paperAnalysis],
            let topicsID = plannedIdentityIDs[.topicKnowledge],
            let worksID = plannedIdentityIDs[.output]
        else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let requestedPortableID = portableManifest?.id ?? triptychID ?? worksID
        try await registry.preflightTriptychConfiguration(
            id: requestedPortableID,
            paperAnalysis: (paperAnalysisURL, analysesID),
            topicKnowledge: (topicKnowledgeURL, topicsID),
            output: (outputURL, worksID)
        )
        let portableAccess = PortableControlAccess(
            canonicalContainerPath: canonicalContainer.path,
            bookmarkData: try canonicalContainer.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        )
        let portableReady = clock.now

        var vaultBookmarks: [WorkspaceVaultSlot: Data] = [:]
        for (slot, url) in selections {
            let scopeStarted = url.startAccessingSecurityScopedResource()
            defer { if scopeStarted { url.stopAccessingSecurityScopedResource() } }
            vaultBookmarks[slot] = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        let identitiesReady = clock.now

        let portableID = portableManifest?.id
        var remappedWorkspaceIDs: [UUID: UUID] = [:]
        if let triptychID,
            let portableID,
            triptychID != portableID,
            try await registry.triptych(id: triptychID) != nil
        {
            _ = try await registry.reidentifyTriptych(id: triptychID, as: portableID)
            remappedWorkspaceIDs[triptychID] = portableID
        }
        let normalizedName = triptychName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignment = try await registry.configureTriptych(
            id: portableID ?? triptychID,
            name: normalizedName?.isEmpty == false ? normalizedName : nil,
            paperAnalysis: (paperAnalysisURL, analysesID),
            topicKnowledge: (topicKnowledgeURL, topicsID),
            output: (outputURL, worksID),
            vaultBookmarks: vaultBookmarks,
            portableControlAccess: portableAccess
        )
        let registryReady = clock.now
        let invalidRootVaultIDs = await vaultPool.invalidRootVaultIDs()
        let prepared = await prepareChangedReplacements(
            registry: registry,
            remappingWorkspaceIDs: remappedWorkspaceIDs,
            forcingVaultIDs: invalidRootVaultIDs
        )
        let detachedVaults = await detachVaultAuthorities(prepared.invalidatedVaultIDs)
        let replacements = try await completeReplacements(
            prepared.replacements,
            detachedVaults: detachedVaults
        )
        let replacementsReady = clock.now
        if let replacement = replacements[assignment.id] {
            await maintainDerivedStateIfNeeded(force: true)
            Self.logOpen(
                portable: totalStart.duration(to: portableReady),
                identities: portableReady.duration(to: identitiesReady),
                registry: identitiesReady.duration(to: registryReady),
                replacements: registryReady.duration(to: replacementsReady),
                workspace: .zero,
                total: totalStart.duration(to: replacementsReady)
            )
            return replacement
        }
        let handle = try await workspace(
            id: assignment.id,
            openingVault: openingVault
        )
        let completed = clock.now
        await maintainDerivedStateIfNeeded(force: true)
        Self.logOpen(
            portable: totalStart.duration(to: portableReady),
            identities: portableReady.duration(to: identitiesReady),
            registry: identitiesReady.duration(to: registryReady),
            replacements: registryReady.duration(to: replacementsReady),
            workspace: replacementsReady.duration(to: completed),
            total: totalStart.duration(to: completed)
        )
        return handle
    }

    private nonisolated static func logOpen(
        portable: Duration,
        identities: Duration,
        registry: Duration,
        replacements: Duration,
        workspace: Duration,
        total: Duration
    ) {
        openLogger.info(
            "configure portable=\(String(describing: portable), privacy: .public) identities=\(String(describing: identities), privacy: .public) registry=\(String(describing: registry), privacy: .public) replacements=\(String(describing: replacements), privacy: .public) workspace=\(String(describing: workspace), privacy: .public) total=\(String(describing: total), privacy: .public)"
        )
    }

    public func portableContainerURL(forWorksURL worksURL: URL) async -> URL? {
        guard !isShutDown,
            case .live(let registry, _) = membership,
            let access = try? await registry.portableAccess(forWorksURL: worksURL)
        else {
            return nil
        }
        var stale = false
        guard
            let resolved = try? URL(
                resolvingBookmarkData: access.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale
        else { return nil }
        let canonical = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path == access.canonicalContainerPath,
            resolved.startAccessingSecurityScopedResource()
        else { return nil }
        resolved.stopAccessingSecurityScopedResource()
        return canonical
    }

    private func existingPortableManifest(
        forWorksURL worksURL: URL
    ) async throws -> TriptychManifest? {
        let manifestURL = worksURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium/manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let manifest: TriptychManifest
        do {
            manifest = try await TriptychControlStore(
                worksVaultURL: worksURL
            ).manifest()
        } catch let error as TriptychControlError {
            throw ScholiumApplicationError.portableControlRecoveryRequired(
                controlPath: manifestURL.deletingLastPathComponent().path,
                reason: error.localizedDescription
            )
        } catch {
            throw error
        }
        guard manifest.schemaVersion == TriptychManifest.currentSchemaVersion,
            Set(manifest.vaultIDs.keys) == Set(WorkspaceVaultSlot.allCases),
            Set(manifest.vaultIDs.values).count == WorkspaceVaultSlot.allCases.count
        else {
            throw ScholiumApplicationError.portableControlRecoveryRequired(
                controlPath: manifestURL.deletingLastPathComponent().path,
                reason: TriptychControlError.invalidManifest.localizedDescription
            )
        }
        return manifest
    }

    private func preflightExistingPortableControl(
        worksURL: URL,
        manifest: TriptychManifest
    ) async throws {
        let controlStore = TriptychControlStore(worksVaultURL: worksURL)
        let controlURL = await controlStore.controlURL
        do {
            try await controlStore.validateExistingSupportedControlState()
        } catch let error as TriptychControlError {
            throw ScholiumApplicationError.portableControlRecoveryRequired(
                controlPath: controlURL.path,
                reason: error.localizedDescription
            )
        }
    }

    private func preflightPortableControlWithoutManifest(
        worksURL: URL
    ) throws {
        let controlURL = worksURL.standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".scholium", isDirectory: true)
        let values: URLResourceValues
        do {
            values = try controlURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
        } catch let error as CocoaError
            where [
                .fileReadNoSuchFile,
                .fileNoSuchFile,
            ].contains(error.code)
        {
            return
        }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ScholiumApplicationError.portableControlRecoveryRequired(
                controlPath: controlURL.path,
                reason: "The portable control owner is linked or is not a directory."
            )
        }
        guard try !FileManager.default.contentsOfDirectory(atPath: controlURL.path).isEmpty
        else { return }
        throw ScholiumApplicationError.portableControlRecoveryRequired(
            controlPath: controlURL.path,
            reason: TriptychControlError.invalidManifest.localizedDescription
        )
    }

    /// Returns the persisted default Triptych.
    public func defaultWorkspace() async throws -> TriptychAssignment {
        try requireActive()
        switch membership {
        case .live(let registry, _):
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
    public func storageInventory() async throws -> ScholiumStorageInventory {
        try requireActive()
        let support = storageRootURL
        let task = Task.detached(priority: .utility) {
            try ScholiumStorageInventoryReader.scan(applicationSupportURL: support)
        }
        return try await withTaskCancellationHandler {
            let inventory = try await task.value
            try Task.checkCancellation()
            try requireActive()
            return inventory
        } onCancel: {
            task.cancel()
        }
    }

    /// One App-level maintenance owner. Destructive operations never race a
    /// second Settings request. Shutdown cancels its admitted owners before
    /// joining this waiter, then drains every owner before releasing storage.
    public func performStorageAction(
        _ action: ScholiumStorageAction, triptychID: UUID? = nil
    ) async throws -> ScholiumStorageOperationResult {
        try requireActive()
        try Task.checkCancellation()
        guard storageOperation == nil else { throw ScholiumStorageManagementError.operationInProgress }
        let token = UUID()
        let task = Task { try await executeStorageAction(action, triptychID: triptychID) }
        storageOperation = StorageOperation(id: token, action: action, triptychID: triptychID, task: task)
        defer { if storageOperation?.id == token { storageOperation = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private var storageRootURL: URL {
        switch membership {
        case .live(_, let support), .snapshot(_, _, let support): support
        }
    }

    private func executeStorageAction(
        _ action: ScholiumStorageAction, triptychID: UUID?
    ) async throws -> ScholiumStorageOperationResult {
        try requireActive()
        try Task.checkCancellation()
        let support = storageRootURL
        switch action {
        case .clearTemporaryFiles:
            let result = try await Task.detached(priority: .utility) {
                try DerivedStateStorage.clearWordTemporaryDirectories(applicationSupportURL: support)
            }.value
            return .init(action: action, cleanup: result)
        case .clearProjectionCache:
            let vaults = try await registeredVaults()
            let result = try await Task.detached(priority: .utility) {
                var removedFiles = 0
                var preservedFiles = 0
                var failedFiles = 0
                var busyDirectories = 0
                var removedBytes: Int64 = 0
                for vault in vaults {
                    try Task.checkCancellation()
                    do {
                        let result = try SourceProjectionCache(
                            applicationSupportURL: support, vaultID: vault.id, role: vault.role
                        ).clearRecognizedRecords()
                        removedFiles += result.removedFiles
                        removedBytes += result.removedBytes
                        preservedFiles += result.preservedFiles
                        failedFiles += result.failedFiles
                        busyDirectories += result.busyDirectories
                    } catch DerivedStateStorageError.inUse {
                        busyDirectories += 1
                    } catch {
                        failedFiles += 1
                    }
                }
                return ScholiumStorageClearResult(
                    removedFiles: removedFiles, removedBytes: removedBytes, preservedFiles: preservedFiles,
                    failedFiles: failedFiles, busyDirectories: busyDirectories)
            }.value
            return .init(action: action, cleanup: result)
        case .cleanRetiredDerivedState:
            guard case .live = membership else {
                throw ScholiumApplicationError.runtimeConfigurationUnavailable
            }
            guard let result = await maintainDerivedStateIfNeeded(force: true) else {
                try Task.checkCancellation()
                try requireActive()
                throw ScholiumApplicationError.runtimeConfigurationUnavailable
            }
            let summary = try result.get()
            try Task.checkCancellation()
            try requireActive()
            return .init(
                action: action,
                cleanup: .init(
                    removedFiles: summary.removedFiles, removedBytes: summary.removedBytes,
                    preservedFiles: summary.preservedFiles, failedFiles: summary.failedFiles + summary.failedDirectories,
                    busyDirectories: summary.busyDirectories))
        case .rebuildIndex:
            guard let triptychID else { throw ScholiumStorageManagementError.triptychRequired }
            _ = try await assignment(id: triptychID)
            let handle: WorkspaceHandle
            if let active = handles[triptychID] {
                handle = active
            } else {
                // Settings needs a source-ready activation, then one explicit
                // complete rebuild; opening all roles first would build twice.
                handle = try await workspace(id: triptychID, openingVault: .paperAnalysis)
            }
            _ = try await handle.rebuildSearchIndex()
            return .init(action: action)
        case .clearIndex:
            guard let triptychID else { throw ScholiumStorageManagementError.triptychRequired }
            let assignment = try await assignment(id: triptychID)
            let outcome: SearchIndexClearResult
            var warnings: [String] = []
            var openingHandle: WorkspaceHandle?
            if let opening = openings[triptychID] {
                #if DEBUG
                    storageOpeningJoinCountForTesting += 1
                #endif
                openingHandle = try await opening.task.value
                try requireActive()
            }
            if let active = handles[triptychID] ?? openingHandle {
                let result = try await active.clearSearchIndex()
                outcome = result.0
                if let warning = result.1 { warnings.append("Index cleared; the subsequent workspace refresh failed: \(warning)") }
            } else {
                // No vault access or source reads are required to clear an
                // inactive index. The factory enforces policy and containment.
                let opened = try await TriptychSearchIndex.openRecovering(
                    applicationSupportURL: support, triptychID: triptychID,
                    vaults: Array(assignment.vaults.values))
                do {
                    outcome = try await opened.index.clear()
                } catch {
                    await opened.index.shutdown()
                    throw error
                }
                await opened.index.shutdown()
            }
            switch outcome.reclamation {
            case .completed: break
            case .deferred: warnings.append("Index cleared; reclaiming its remaining disk space was deferred.")
            case .failed: warnings.append("Index cleared; compacting its remaining storage failed.")
            }
            return .init(action: action, warnings: warnings)
        }
    }

    /// Activates a Library and resumes any explicitly cleared index. Live
    /// activations retain source-ready presentation while the owned rebuild runs.
    public func openWorkspace(
        id: UUID,
        openingVault: WorkspaceVaultSlot? = nil
    ) async throws -> WorkspaceHandle {
        let handle = try await workspace(id: id, openingVault: openingVault)
        try Task.checkCancellation()
        try await handle.resumeSearchIndexForActivation()
        try Task.checkCancellation()
        try requireActive()
        return handle
    }

    /// Borrows the one workspace service owner. Capability and metadata reads
    /// preserve an explicitly cleared Search index, including after restart.
    public func workspace(
        id: UUID,
        openingVault: WorkspaceVaultSlot? = nil
    ) async throws -> WorkspaceHandle {
        try requireActive()
        try Task.checkCancellation()
        if let operation = storageOperation, operation.action == .clearIndex, operation.triptychID == id {
            _ = try await operation.task.value
            try requireActive()
            try Task.checkCancellation()
        }
        if let handle = handles[id] {
            try requireActive()
            return handle
        }
        if let opening = openings[id] {
            #if DEBUG
                openingJoinCountForTesting += 1
            #endif
            let handle = try await opening.task.value
            try requireActive()
            return handle
        }

        let token = UUID()
        // Admission and registration are one actor turn. Membership lookup
        // belongs to the same owned task as source-ready creation, so shutdown
        // cannot miss an opener suspended before the factory.
        let task = Task {
            try Task.checkCancellation()
            try requireActive()
            try Task.checkCancellation()
            try requireActive()
            #if DEBUG
                openingLookupCountForTesting += 1
            #endif
            let assignment = try await assignment(id: id)
            try Task.checkCancellation()
            try requireActive()
            #if DEBUG
                if let openingLookupBarrierForTesting { await openingLookupBarrierForTesting(id) }
            #endif
            try Task.checkCancellation()
            try requireActive()
            #if DEBUG
                openingFactoryCountForTesting += 1
            #endif
            switch membership {
            case .live(_, let supportURL):
                return try await WorkspaceHandle.open(
                    assignment: assignment,
                    mode: .live,
                    applicationSupportURL: supportURL,
                    windowSessionStore: windowSessionStore,
                    vaultPool: vaultPool,
                    zotero: zotero,
                    access: .live,
                    openingVault: openingVault
                )
            case .snapshot(_, _, let supportURL):
                return try await WorkspaceHandle.open(
                    assignment: assignment,
                    mode: .snapshot,
                    applicationSupportURL: supportURL,
                    windowSessionStore: windowSessionStore,
                    vaultPool: vaultPool,
                    zotero: zotero,
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
            scheduleDerivedMaintenance(after: handle)
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

    /// Machine-local Changes settings for a registered Triptych, without
    /// opening its vaults or changing the selected runtime.
    public func documentChangeArchive(triptychID: UUID) async throws -> DocumentChangeArchiveOperations {
        try requireActive()
        _ = try await assignment(id: triptychID)
        let supportURL: URL
        switch membership {
        case .live(_, let url): supportURL = url
        case .snapshot(_, _, let url): supportURL = url
        }
        return DocumentChangeArchiveOperations(
            store: try DocumentReviewStore(
                applicationSupportURL: supportURL, triptychID: triptychID
            ),
            receipts: try AgentChangeStore(
                applicationSupportURL: supportURL, triptychID: triptychID
            ),
            runtime: self, triptychID: triptychID
        )
    }

    func finishDocumentChangesCleanup(triptychID: UUID) async throws {
        if let handle = handles[triptychID] {
            do {
                try await handle.reclaimReviewedOperationReceipts()
            } catch {
                await handle.publishDocumentChangesChanged()
                throw DocumentChangeError.historyChangedCleanupPending(error.localizedDescription)
            }
            await handle.publishDocumentChangesChanged()
        }
    }

    func publishDocumentChangesChanged(triptychID: UUID) async {
        if let handle = handles[triptychID] {
            await handle.publishDocumentChangesChanged()
        }
    }

    /// Cancels in-flight opens, shuts down every cached handle, and prevents
    /// later reuse. Calling shutdown repeatedly is harmless.
    public func shutdown() async {
        if let shutdownTask {
            #if DEBUG
                shutdownJoinCountForTesting += 1
            #endif
            await shutdownTask.value
            return
        }
        isShutDown = true
        let task = Task { await finishShutdown() }
        shutdownTask = task
        await task.value
    }

    private func finishShutdown() async {
        let maintenance = deferredMaintenanceTask
        if maintenance?.phase == .waiting {
            #if DEBUG
                derivedMaintenanceWaitingCancellationCountForTesting += 1
            #endif
        }
        maintenance?.task.cancel()
        let operation = storageOperation?.task
        let pending = openings.values.map(\.task)
        openings.removeAll()
        let active = Array(handles.values) + Array(retainedHandles.values)
        handles.removeAll()
        retainedHandles.removeAll()
        operation?.cancel()
        pending.forEach { $0.cancel() }
        // Storage requests can be waiting on an opening or a Handle-owned
        // rebuild. Start every owner's shutdown before joining those waiters.
        await withTaskGroup(of: Void.self) { drains in
            for handle in active {
                drains.addTask { await handle.shutdown() }
            }
            if let operation { _ = try? await operation.value }
            for task in pending {
                if let handle = try? await task.value {
                    await handle.shutdown()
                }
            }
        }
        _ = await maintenance?.task.value
        if let maintenance { finishDerivedMaintenance(id: maintenance.id) }
        await vaultPool.shutdown()
        await maintainDerivedStateIfNeeded(force: true, duringShutdown: true)
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
            replacements.append(
                Replacement(
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
                let successor = try await workspace(id: replacement.workspaceID)
                successors[replacement.workspaceID] = successor
                successorSnapshots[replacement.workspaceID] = try await successor.snapshot()
            }
            // Publication and retirement are nonthrowing after every successor
            // has opened. Peers cannot observe a half-completed handoff.
            for replacement in replacements {
                guard let successor = successors[replacement.workspaceID],
                    let snapshot = successorSnapshots[replacement.workspaceID]
                else {
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
                    handles[replacement.previousCacheID] == nil
                {
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
        forcing forcedIDs: Set<UUID> = [],
        forcingVaultIDs: Set<UUID> = []
    ) async -> (replacements: [Replacement], invalidatedVaultIDs: Set<UUID>) {
        var mappings: [(cacheID: UUID, workspaceID: UUID)] = []
        var invalidatedVaultIDs: Set<UUID> = []
        for (cacheID, handle) in handles {
            let workspaceID = remappedIDs[cacheID] ?? cacheID
            guard let current = try? await registry.triptych(id: workspaceID) else {
                continue
            }
            let handleVaultIDs = Set(handle.assignment.vaults.values.map(\.id))
            let invalidRootsInHandle = handleVaultIDs.intersection(forcingVaultIDs)
            guard
                forcedIDs.contains(cacheID)
                    || !invalidRootsInHandle.isEmpty
                    || handle.assignment != current
            else {
                continue
            }
            mappings.append((cacheID, workspaceID))
            invalidatedVaultIDs.formUnion(
                changedVaultIDs(from: handle.assignment, to: current)
            )
            invalidatedVaultIDs.formUnion(invalidRootsInHandle)
        }
        let replacements = await detachReplacements(mappings)
        return (replacements, invalidatedVaultIDs)
    }

    private func assignment(id: UUID) async throws -> TriptychAssignment {
        switch membership {
        case .live(let registry, _):
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

    func deliverPooledVaultEventForTesting(
        _ event: VaultWatchEvent,
        vaultID: UUID
    ) async throws {
        guard let runtime = await vaultPool.runtime(vaultID: vaultID) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        await runtime.receiveForTesting(event)
    }
}
