import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore

struct OwnedRefreshTask: Sendable {
    let token: UUID
    let task: Task<Void, Never>
}

enum RefreshPublication: Sendable {
    case sourceCommitted(VaultQualifiedNoteID, WorkspaceSourceCommitKind)
    case explicit
    case liveInventory
    case researchState
    case runtimeReloaded
}

enum DerivedRefreshFailureDisposition: Sendable {
    case staleAfterCommittedMutation(affectedVaultIDs: Set<UUID>)
    case failed(affectedVaultIDs: Set<UUID>)

    func status(
        for error: Error,
        lastKnownGood snapshot: WorkspaceSnapshot
    ) -> WorkspaceDerivedRefreshStatus {
        let evidence = WorkspaceDerivedRefreshEvidence(snapshot: snapshot)
        switch self {
        case .staleAfterCommittedMutation(let affectedVaultIDs):
            return .stale(
                WorkspaceDerivedRefreshIssue(
                    reason: "The authoritative mutation committed, but derived workspace refresh failed: \(error.localizedDescription)",
                    affectedVaultIDs: affectedVaultIDs,
                    lastKnownGood: evidence
                ))
        case .failed(let affectedVaultIDs):
            return .failed(
                WorkspaceDerivedRefreshIssue(
                    reason: "Derived workspace refresh failed: \(error.localizedDescription)",
                    affectedVaultIDs: affectedVaultIDs,
                    lastKnownGood: evidence
                ))
        }
    }
}

struct VaultSourceCatalogDelta: Sendable {
    var upserts: Set<String> = []
    var deletions: Set<String> = []
    var refreshFolders = false

    mutating func merge(_ other: Self) {
        for path in other.deletions {
            upserts.remove(path)
            deletions.insert(path)
        }
        for path in other.upserts {
            deletions.remove(path)
            upserts.insert(path)
        }
        refreshFolders = refreshFolders || other.refreshFolders
    }
}

enum SourceCatalogPreparation: Sendable {
    case none
    case delta([UUID: VaultSourceCatalogDelta])
    case fullReconcile

    static func inferred(from publication: RefreshPublication) -> Self {
        switch publication {
        case .sourceCommitted(let id, _):
            .delta([
                id.vaultID: VaultSourceCatalogDelta(
                    upserts: [id.relativePath]
                )
            ])
        case .liveInventory, .researchState:
            .none
        case .explicit, .runtimeReloaded:
            .fullReconcile
        }
    }

    static func merged(_ preparations: [Self]) -> Self {
        guard
            !preparations.contains(where: {
                if case .fullReconcile = $0 { true } else { false }
            })
        else { return .fullReconcile }
        var merged: [UUID: VaultSourceCatalogDelta] = [:]
        for preparation in preparations {
            guard case .delta(let changes) = preparation else { continue }
            for (vaultID, change) in changes {
                merged[vaultID, default: VaultSourceCatalogDelta()].merge(change)
            }
        }
        return merged.isEmpty ? .none : .delta(merged)
    }
}

enum WorkspaceRefreshCycleError: LocalizedError {
    case graphGenerationExhausted

    var errorDescription: String? {
        "Workspace graph generation IDs were exhausted."
    }
}

struct WorkspaceSourceInventoryInput: Sendable {
    let order: Int
    let vaultID: UUID
    let catalog: VaultSourceCatalog
}

struct WorkspaceSourceInventorySnapshot: Sendable {
    let order: Int
    let vaultID: UUID
    let snapshot: VaultSourceCatalogSnapshot
}

struct WorkspaceRefreshPayload: Sendable {
    let publication: RefreshPublication
    let failureDisposition: DerivedRefreshFailureDisposition
    let sourceCatalogPreparation: SourceCatalogPreparation
    /// Non-nil only when every merged request is a Metadata-only mutation.
    /// Values are exact committed record deltas over the last complete map.

    init(
        publication: RefreshPublication,
        failureDisposition: DerivedRefreshFailureDisposition,
        sourceCatalogPreparation: SourceCatalogPreparation
    ) {
        self.publication = publication
        self.failureDisposition = failureDisposition
        self.sourceCatalogPreparation = sourceCatalogPreparation
    }

    static func merged(_ payloads: [Self]) throws -> Self {
        guard let first = payloads.first else { throw CancellationError() }
        guard payloads.count > 1 else { return first }
        var affectedVaultIDs: Set<UUID> = []
        var includesCommittedMutation = false
        for payload in payloads {
            switch payload.failureDisposition {
            case .staleAfterCommittedMutation(let affected):
                includesCommittedMutation = true
                affectedVaultIDs.formUnion(affected)
            case .failed(let affected):
                affectedVaultIDs.formUnion(affected)
            }
        }
        return Self(
            publication: mergedPublication(payloads.map(\.publication)),
            failureDisposition: includesCommittedMutation
                ? .staleAfterCommittedMutation(affectedVaultIDs: affectedVaultIDs)
                : .failed(affectedVaultIDs: affectedVaultIDs),
            sourceCatalogPreparation: .merged(
                payloads.map(\.sourceCatalogPreparation)
            ),
        )
    }

    private static func mergedPublication(
        _ publications: [RefreshPublication]
    ) -> RefreshPublication {
        if publications.allSatisfy({
            if case .researchState = $0 { true } else { false }
        }) {
            return .researchState
        }
        if publications.allSatisfy({
            if case .liveInventory = $0 { true } else { false }
        }) {
            return .liveInventory
        }
        if publications.allSatisfy({
            if case .runtimeReloaded = $0 { true } else { false }
        }) {
            return .runtimeReloaded
        }
        if publications.allSatisfy({
            if case .explicit = $0 { true } else { false }
        }) {
            return .explicit
        }
        if case .sourceCommitted(let firstID, let firstKind) = publications[0],
            publications.dropFirst().allSatisfy({ publication in
                guard case .sourceCommitted(let id, let kind) = publication else {
                    return false
                }
                return id == firstID && kind == firstKind
            })
        {
            return .sourceCommitted(firstID, firstKind)
        }
        // One event generation cannot publish several source identities or
        // heterogeneous semantic causes. A complete inventory event carries
        // every changed note from the merged snapshot instead.
        return .explicit
    }
}
extension WorkspaceHandle {
    func refresh() async throws -> WorkspaceSnapshot {
        let snapshot = try await refresh(publication: .explicit)
        if snapshot.phase.isComplete {
            startLiveIndexRefreshIfNeeded()
        }
        return snapshot
    }

    /// Refreshes disposable projections after a durable non-document
    /// operation. Failure is reported as an explicit committed outcome so a
    /// delivery surface can refresh later without repeating the mutation.
    func refreshAfterCommittedOperation(
        _ operation: String,
        publication: RefreshPublication,
        affectedVaultIDs: Set<UUID> = []
    ) async throws {
        do {
            _ = try await refresh(
                publication: publication,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: affectedVaultIDs
                )
            )
        } catch {
            throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: operation,
                reason: error.localizedDescription
            )
        }
    }

    func refresh(
        publication: RefreshPublication,
        failureDisposition: DerivedRefreshFailureDisposition = .failed(
            affectedVaultIDs: []
        ),
        sourceCatalogPreparation: SourceCatalogPreparation? = nil
    ) async throws -> WorkspaceSnapshot {
        try requireActive()
        return try await refreshCoordinator.request(
            WorkspaceRefreshPayload(
                publication: publication,
                failureDisposition: failureDisposition,
                sourceCatalogPreparation: sourceCatalogPreparation
                    ?? .inferred(from: publication)
            ))
    }

    func performRefreshCycle(
        requestID: RefreshRequestID,
        payloads: [WorkspaceRefreshPayload]
    ) async throws -> WorkspaceSnapshot {
        let clock = ContinuousClock()
        let cycleStart = clock.now
        let refreshLease = try await beginRefreshCycle()
        let gateWaitDuration = cycleStart.duration(to: clock.now)
        defer { endRefreshCycle(refreshLease) }
        let payload = try WorkspaceRefreshPayload.merged(payloads)
        let snapshot: WorkspaceSnapshot
        let measurement: WorkspaceRefreshMeasurement
        let sourcePreparationDuration: Duration
        let buildDuration: Duration
        do {
            let preparationStart = clock.now
            if mode == .live,
                !currentSnapshot.phase.isComplete,
                !didCompleteActivationReconciliation
            {
                await progressiveActivationReconciliationBarrierForTesting?()
                try Task.checkCancellation()
                try requireActive()
                // Observation already owns all three Vault streams. Complete
                // one full post-observation reconciliation before the first
                // complete snapshot can be built or published, closing the
                // initial-open blind interval as one completion boundary.
                try await prepareSourceCatalogs(.fullReconcile)
                didCompleteActivationReconciliation = true
            } else {
                try await prepareSourceCatalogs(payload.sourceCatalogPreparation)
            }
            sourcePreparationDuration = preparationStart.duration(to: clock.now)
            guard nextGraphGeneration < Int.max else {
                throw WorkspaceRefreshCycleError.graphGenerationExhausted
            }
            let indexedWorkspaceGeneration = try await services.searchIndex
                .workspaceGeneration()
            guard indexedWorkspaceGeneration < UInt64(Int.max) else {
                throw SearchIndexError.invalidDocuments(
                    "Search workspace generation IDs were exhausted."
                )
            }
            let workspaceGeneration = max(
                requestID.rawValue,
                indexedWorkspaceGeneration + 1
            )
            let graphGeneration = nextGraphGeneration
            nextGraphGeneration += 1
            let buildStart = clock.now
            let build = try await WorkspaceSnapshotBuilder.build(
                assignment: assignment,
                mode: mode,
                dependencies: services.snapshotBuilderDependencies,
                graphGeneration: graphGeneration,
                workspaceGeneration: workspaceGeneration,
            )
            buildDuration = buildStart.duration(to: clock.now)
            snapshot = build.snapshot
            measurement = build.measurement
            latestRefreshMeasurement = measurement
        } catch {
            for catalog in services.sourceCatalogs.values {
                await catalog.discardPendingMeasurement()
            }
            if !Task.isCancelled, !isShutDown {
                derivedStateRequiresRefresh = true
                await events.publishDerivedStateChanged(
                    snapshot: currentSnapshot,
                    status: payload.failureDisposition.status(
                        for: error,
                        lastKnownGood: currentSnapshot
                    )
                )
            }
            throw error
        }
        try requireActive()
        let previous = currentSnapshot
        currentSnapshot = snapshot
        sourceAheadIdentityRecords.removeAll(keepingCapacity: true)
        let confirmsEarlierFailure = derivedStateRequiresRefresh
        derivedStateRequiresRefresh = false
        let publicationStart = clock.now
        await publish(
            payload.publication,
            previous: previous,
            snapshot: snapshot,
            confirmsEarlierFailure: confirmsEarlierFailure
        )
        let publicationDuration = publicationStart.duration(to: clock.now)
        let cycleMeasurement = WorkspaceRefreshCycleMeasurement(
            workspaceGeneration: measurement.workspaceGeneration,
            gateWaitDuration: gateWaitDuration,
            sourcePreparationDuration: sourcePreparationDuration,
            buildDuration: buildDuration,
            publicationDuration: publicationDuration,
            totalDuration: cycleStart.duration(to: clock.now)
        )
        latestRefreshCycleMeasurement = cycleMeasurement
        Self.logRefresh(measurement, publicationDuration: publicationDuration)
        Self.refreshLogger.info(
            "cycle generation=\(cycleMeasurement.workspaceGeneration, privacy: .public) gateWait=\(String(describing: cycleMeasurement.gateWaitDuration), privacy: .public) sourcePreparation=\(String(describing: cycleMeasurement.sourcePreparationDuration), privacy: .public) build=\(String(describing: cycleMeasurement.buildDuration), privacy: .public) publish=\(String(describing: cycleMeasurement.publicationDuration), privacy: .public) total=\(String(describing: cycleMeasurement.totalDuration), privacy: .public)"
        )
        return snapshot
    }

    nonisolated static func logRefresh(
        _ measurement: WorkspaceRefreshMeasurement,
        publicationDuration: Duration?
    ) {
        refreshLogger.info(
            "generation=\(measurement.workspaceGeneration, privacy: .public) files=\(measurement.enumeratedFiles, privacy: .public) reads=\(measurement.readFiles, privacy: .public) parses=\(measurement.parsedDocuments, privacy: .public) projections=\(measurement.projectedDocuments, privacy: .public) restored=\(measurement.restoredSearchProjections, privacy: .public) sourceBytes=\(measurement.snapshotSourceBytes, privacy: .public) enumerate=\(String(describing: measurement.enumerationDuration), privacy: .public) read=\(String(describing: measurement.readDuration), privacy: .public) parse=\(String(describing: measurement.parseDuration), privacy: .public) project=\(String(describing: measurement.projectionDuration), privacy: .public) cacheRead=\(String(describing: measurement.cacheReadDuration), privacy: .public) cacheWrite=\(String(describing: measurement.cacheWriteDuration), privacy: .public) identity=\(String(describing: measurement.identityProjectionDuration), privacy: .public) links=\(String(describing: measurement.linkCatalogProjectionDuration), privacy: .public) graph=\(String(describing: measurement.graphDuration), privacy: .public) research=\(String(describing: measurement.researchStateDuration), privacy: .public) searchProjection=\(String(describing: measurement.searchDocumentProjectionDuration), privacy: .public) search=\(String(describing: measurement.searchDuration), privacy: .public) assemble=\(String(describing: measurement.snapshotAssemblyDuration), privacy: .public) publish=\(String(describing: publicationDuration), privacy: .public) total=\(String(describing: measurement.totalDuration), privacy: .public)"
        )
    }

    private func prepareSourceCatalogs(
        _ preparation: SourceCatalogPreparation
    ) async throws {
        // Snapshot runtimes have no native watcher. Every publication must
        // therefore stat-reconcile all three catalogs so an external addition,
        // deletion, or unreadable source in another vault cannot be hidden by
        // an otherwise precise local mutation. Unchanged notes are not read or
        // reparsed because SourceVersion remains the cache gate.
        if mode == .snapshot {
            for catalog in services.sourceCatalogs.values {
                try await catalog.reconcile()
            }
            return
        }
        switch preparation {
        case .fullReconcile:
            for catalog in services.sourceCatalogs.values {
                try await catalog.reconcile()
            }
        case .none:
            break
        case .delta(let changes):
            for (vaultID, change) in changes {
                guard let catalog = services.sourceCatalogs[vaultID] else {
                    throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
                }
                try await catalog.apply(
                    upserts: change.upserts,
                    deletions: change.deletions,
                    refreshFolders: change.refreshFolders
                )
            }
        }
    }

    static func catalogPreparation(
        upserts: [VaultQualifiedNoteID] = [],
        deletions: [VaultQualifiedNoteID] = [],
        refreshFolderVaultIDs: Set<UUID> = []
    ) -> SourceCatalogPreparation {
        var changes: [UUID: VaultSourceCatalogDelta] = [:]
        for id in deletions {
            changes[id.vaultID, default: VaultSourceCatalogDelta()]
                .deletions.insert(id.relativePath)
        }
        for id in upserts {
            var change = changes[id.vaultID, default: VaultSourceCatalogDelta()]
            change.deletions.remove(id.relativePath)
            change.upserts.insert(id.relativePath)
            changes[id.vaultID] = change
        }
        for vaultID in refreshFolderVaultIDs {
            changes[vaultID, default: VaultSourceCatalogDelta()]
                .refreshFolders = true
        }
        return changes.isEmpty ? .none : .delta(changes)
    }

    private func publish(
        _ publication: RefreshPublication,
        previous: WorkspaceSnapshot,
        snapshot: WorkspaceSnapshot,
        confirmsEarlierFailure: Bool
    ) async {
        let changes = inventoryChanges(from: previous, to: snapshot)
        switch publication {
        case .sourceCommitted(let id, let kind):
            guard let note = snapshot.document(id: id) else {
                await events.publishDerivedStateChanged(snapshot: snapshot)
                return
            }
            await events.publishSourceCommitted(
                snapshot: snapshot,
                note: note,
                kind: kind
            )
        case .explicit:
            if changes.hasChanges {
                await events.publishInventoryChanged(
                    snapshot: snapshot,
                    added: changes.added,
                    removed: changes.removed,
                    changed: changes.changed,
                    moved: changes.moved
                )
            } else {
                await events.publishDerivedStateChanged(snapshot: snapshot)
            }
        case .liveInventory:
            if previous.phase != snapshot.phase {
                await events.publishDerivedStateChanged(snapshot: snapshot)
                return
            }
            guard changes.hasChanges else {
                if confirmsEarlierFailure {
                    await events.publishDerivedStateChanged(snapshot: snapshot)
                }
                return
            }
            await events.publishInventoryChanged(
                snapshot: snapshot,
                added: changes.added,
                removed: changes.removed,
                changed: changes.changed,
                moved: changes.moved
            )
        case .researchState:
            await events.publishResearchStateChanged(snapshot: snapshot)
        case .runtimeReloaded:
            await events.publishRuntimeReloaded(
                runtimeIdentity: runtimeIdentity,
                snapshot: snapshot
            )
        }
    }

    /// Publishes the one typed handoff from this activation to a fully opened
    /// replacement. Subscribers can adopt the replacement identity and its
    /// complete snapshot before this handle finishes its stream.
    func announceRuntimeReplacement(
        runtimeIdentity: TriptychRuntimeIdentity,
        snapshot: WorkspaceSnapshot
    ) async {
        await events.publishRuntimeReloaded(
            runtimeIdentity: runtimeIdentity,
            snapshot: snapshot
        )
    }

    private func inventoryChanges(
        from previous: WorkspaceSnapshot,
        to current: WorkspaceSnapshot
    ) -> (
        added: Set<VaultQualifiedNoteID>,
        removed: Set<VaultQualifiedNoteID>,
        changed: Set<VaultQualifiedNoteID>,
        moved: [WorkspaceNoteMove],
        hasChanges: Bool
    ) {
        let old = sourceRevisions(in: previous)
        let new = sourceRevisions(in: current)
        let oldIDs = Set(old.keys)
        let newIDs = Set(new.keys)
        let previousLocations = resolvedIdentityLocations(in: previous)
        let currentLocations = resolvedIdentityLocations(in: current)
        let moved = Set(previousLocations.keys).intersection(currentLocations.keys)
            .compactMap { stableID -> WorkspaceNoteMove? in
                guard let oldLocation = previousLocations[stableID],
                    let newLocation = currentLocations[stableID],
                    oldLocation != newLocation
                else { return nil }
                return WorkspaceNoteMove(
                    stableNoteID: stableID,
                    previousLocation: oldLocation,
                    location: newLocation
                )
            }
            .sorted { left, right in
                if left.previousLocation.vaultID != right.previousLocation.vaultID {
                    return left.previousLocation.vaultID.uuidString
                        < right.previousLocation.vaultID.uuidString
                }
                return left.previousLocation.relativePath < right.previousLocation.relativePath
            }
        let movedFrom = Set(moved.map(\.previousLocation))
        let movedTo = Set(moved.map(\.location))
        let added = newIDs.subtracting(oldIDs).subtracting(movedTo)
        let removed = oldIDs.subtracting(newIDs).subtracting(movedFrom)
        let changed = oldIDs.intersection(newIDs).filter { old[$0] != new[$0] }
        return (
            added,
            removed,
            Set(changed),
            moved,
            !added.isEmpty || !removed.isEmpty || !changed.isEmpty || !moved.isEmpty
        )
    }

    private func resolvedIdentityLocations(
        in snapshot: WorkspaceSnapshot
    ) -> [UUID: VaultQualifiedNoteID] {
        Dictionary(
            snapshot.vaults.flatMap(\.documents).compactMap { note in
                note.stableIdentity.resolvedID.map { ($0, note.id) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func sourceRevisions(
        in snapshot: WorkspaceSnapshot
    ) -> [VaultQualifiedNoteID: DocumentFingerprint] {
        Dictionary(
            uniqueKeysWithValues: snapshot.vaults.flatMap { vault in
                vault.documents.map { ($0.id, $0.fingerprint) }
            }
        )
    }

    func startLiveTasks(
        streams: [UUID: AsyncStream<VaultWatchEvent>],
        preOpenInventory: [VaultQualifiedNoteID: DocumentFingerprint],
        completesOpeningInBackground: Bool
    ) async {
        guard mode == .live, !isShutDown, liveWatcherTask == nil else { return }
        liveWatcherTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for (vaultID, stream) in streams {
                    group.addTask { [weak self] in
                        for await event in stream {
                            guard !Task.isCancelled, let self else { return }
                            await self.receiveLiveEvent(event, vaultID: vaultID)
                        }
                    }
                }
                await group.waitForAll()
            }
        }
        if completesOpeningInBackground {
            let presentationEvents = openingPresentationSignal.stream
            openingCompletionTask = Task(priority: .utility) { [weak self] in
                let clock = ContinuousClock()
                let openingStart = clock.now
                await Self.waitForOpeningPresentationOrFallback(presentationEvents)
                guard !Task.isCancelled, let self else { return }
                let presentationWait = openingStart.duration(to: clock.now)
                let completionStart = clock.now
                await self.completeLiveOpening()
                Self.refreshLogger.info(
                    "openingBackground presentationWait=\(String(describing: presentationWait), privacy: .public) completionWork=\(String(describing: completionStart.duration(to: clock.now)), privacy: .public) total=\(String(describing: openingStart.duration(to: clock.now)), privacy: .public)"
                )
            }
            return
        }
        await reconcileLiveActivation(preOpenInventory: preOpenInventory)
    }

    private nonisolated static func waitForOpeningPresentationOrFallback(
        _ events: AsyncStream<Void>
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in events { return }
            }
            group.addTask {
                // A Library-only window must still converge when no Document
                // is selected or its renderer fails before becoming visible.
                try? await Task.sleep(for: .seconds(2))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    private func completeLiveOpening() async {
        defer { openingCompletionTask = nil }
        guard !isShutDown, !Task.isCancelled else { return }
        do {
            if !currentSnapshot.phase.isComplete {
                _ = try await refresh(
                    publication: .liveInventory,
                    failureDisposition: .failed(
                        affectedVaultIDs: Set(assignment.vaults.values.map(\.id))
                    ),
                    sourceCatalogPreparation: .fullReconcile
                )
            }
            startLiveIndexRefreshIfNeeded()
        } catch {
            // `refresh` already published a typed failure while retaining the
            // usable opening vault. Explicit Retry performs a full reconcile.
        }
    }

    /// Closes the interval between the pre-open inventory and watcher
    /// ownership. The comparison against both the pre-open signature and the
    /// published initial snapshot catches a source that changed during scan,
    /// including an intermediate revision that was captured by that scan.
    private func reconcileLiveActivation(
        preOpenInventory: [VaultQualifiedNoteID: DocumentFingerprint]
    ) async {
        defer { didCompleteActivationReconciliation = true }
        guard !isShutDown else { return }
        var attemptedRefresh = false
        do {
            let observed = try await Self.sourceInventory(
                assignment: assignment,
                sourceCatalogs: services.sourceCatalogs
            )
            let published = sourceRevisions(in: currentSnapshot)
            let changedDuringActivation = observed != preOpenInventory
            let publishedRevisionIsStale = observed != published
            guard changedDuringActivation || publishedRevisionIsStale else { return }
            if publishedRevisionIsStale {
                attemptedRefresh = true
                _ = try await refresh(
                    publication: .liveInventory,
                    failureDisposition: .failed(
                        affectedVaultIDs: Set(assignment.vaults.values.map(\.id))
                    )
                )
            }
        } catch {
            guard !attemptedRefresh, !Task.isCancelled, !isShutDown else { return }
            // Native observation is already owned. A concurrent filesystem
            // event remains buffered and triggers a complete retry, while the
            // delivery surfaces retain the initial last-known-good snapshot.
            derivedStateRequiresRefresh = true
            await events.publishDerivedStateChanged(
                snapshot: currentSnapshot,
                status: DerivedRefreshFailureDisposition.failed(
                    affectedVaultIDs: Set(assignment.vaults.values.map(\.id))
                ).status(for: error, lastKnownGood: currentSnapshot)
            )
        }
    }

    private func receiveLiveEvent(_ event: VaultWatchEvent, vaultID: UUID) {
        guard !isShutDown else { return }
        if event.rootChanged {
            unavailableRootVaultIDs.insert(vaultID)
        } else if !unavailableRootVaultIDs.isEmpty {
            // The replacement runtime performs a complete initial reconcile.
            // No delta from this invalid activation may refresh its snapshot.
            return
        }
        var journal = pendingLiveEvents[vaultID] ?? VaultWatchEventJournal(capacity: 256)
        journal.append(event)
        pendingLiveEvents[vaultID] = journal
        startLiveIndexRefreshIfNeeded()
    }

    func beginSourceMutation() async throws -> WorkspaceSourceOperationLease {
        try requireActive()
        try requireRootAuthoritiesAvailable()
        do {
            let lease = try await acquireWorkspaceSourceOperation(.sourceMutation)
            do {
                try Task.checkCancellation()
                try requireActive()
                try requireRootAuthoritiesAvailable()
                return lease
            } catch {
                releaseWorkspaceSourceOperation(lease)
                throw error
            }
        } catch WorkspaceSourceOperationGateError.shutDown {
            throw ScholiumApplicationError.workspaceShutDown(id)
        }
    }

    func beginResearchControlledSourceObservation() async throws
        -> WorkspaceSourceOperationLease
    {
        try await beginSourceMutation()
    }

    func endSourceMutation(_ lease: WorkspaceSourceOperationLease) {
        releaseWorkspaceSourceOperation(lease)
        startLiveIndexRefreshIfNeeded()
    }

    func endResearchControlledSourceObservation(
        _ lease: WorkspaceSourceOperationLease
    ) {
        endSourceMutation(lease)
    }

    private func beginRefreshCycle() async throws -> WorkspaceSourceOperationLease {
        try requireActive()
        try requireRootAuthoritiesAvailable()
        do {
            let lease = try await acquireWorkspaceSourceOperation(.refreshCycle)
            do {
                try Task.checkCancellation()
                try requireActive()
                try requireRootAuthoritiesAvailable()
                return lease
            } catch {
                releaseWorkspaceSourceOperation(lease)
                throw error
            }
        } catch WorkspaceSourceOperationGateError.shutDown {
            throw ScholiumApplicationError.workspaceShutDown(id)
        }
    }

    private func endRefreshCycle(_ lease: WorkspaceSourceOperationLease) {
        releaseWorkspaceSourceOperation(lease)
    }

    private func startLiveIndexRefreshIfNeeded() {
        guard !isShutDown,
            currentSnapshot.phase.isComplete,
            !sourceOperationGate.sourceMutationIsActive,
            !pendingLiveEvents.isEmpty,
            sourceCommitRefreshTask == nil,
            liveIndexRefreshTask == nil
        else { return }

        let token = UUID()
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runLiveIndexRefresh(token: token)
        }
        liveIndexRefreshTask = OwnedRefreshTask(token: token, task: task)
    }

    /// Commits and derived state intentionally have different completion
    /// semantics. The source caller receives the revision-checked repository
    /// result immediately; this actor retains and coalesces the disposable
    /// refresh work until publication or a typed stale-state event.
    func scheduleSourceCommitRefresh(
        id: VaultQualifiedNoteID,
        kind: WorkspaceSourceCommitKind
    ) {
        scheduleCommittedMutationRefresh(
            WorkspaceRefreshPayload(
                publication: .sourceCommitted(id, kind),
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                ),
                sourceCatalogPreparation: .inferred(
                    from: .sourceCommitted(id, kind)
                )
            ))
    }

    /// Retains disposable projection work after a proven source mutation so
    /// filesystem completion never waits for graph, Search, or research-state
    /// assembly. Callers enqueue while holding the source lease; the owned
    /// refresh task can therefore begin only after that lease is released.
    func scheduleCommittedMutationRefresh(
        _ payload: WorkspaceRefreshPayload
    ) {
        pendingSourceCommitRefreshes.append(payload)
        guard !isShutDown, sourceCommitRefreshTask == nil else { return }
        sourceCommitRefreshTask = Task(priority: .utility) { [weak self] in
            await self?.runSourceCommitRefreshes()
        }
    }

    private func runSourceCommitRefreshes() async {
        defer {
            sourceCommitRefreshTask = nil
            startLiveIndexRefreshIfNeeded()
        }
        while !isShutDown, !Task.isCancelled,
            !pendingSourceCommitRefreshes.isEmpty
        {
            let queued = pendingSourceCommitRefreshes
            pendingSourceCommitRefreshes.removeAll(keepingCapacity: true)
            do {
                let payload = try WorkspaceRefreshPayload.merged(queued)
                _ = try await refreshCoordinator.request(payload)
            } catch is CancellationError {
                return
            } catch {
                // `performRefreshCycle` already published the typed stale
                // state while retaining its last known-good snapshot. A
                // derived failure never turns the committed save into a
                // retryable source mutation.
            }
        }
    }

    private func runLiveIndexRefresh(token: UUID) async {
        while !isShutDown, !pendingLiveEvents.isEmpty {
            guard !sourceOperationGate.sourceMutationIsActive else { break }
            let pending = pendingLiveEvents
            pendingLiveEvents.removeAll()
            var changedVaultIDs: Set<UUID> = []
            var rootChangedVaultIDs: Set<UUID> = []
            for (vaultID, var journal) in pending {
                guard let event = journal.drain() else { continue }
                if event.rootChanged {
                    rootChangedVaultIDs.insert(vaultID)
                } else {
                    changedVaultIDs.insert(vaultID)
                }
            }
            // A root discontinuity invalidates the authority path itself. Do
            // not let an unrelated vault event clear that stale status by
            // rebuilding against a missing or relocated root.
            if !rootChangedVaultIDs.isEmpty || !unavailableRootVaultIDs.isEmpty {
                unavailableRootVaultIDs.formUnion(rootChangedVaultIDs)
                derivedStateRequiresRefresh = true
                await events.publishVaultAccessInvalidated(
                    snapshot: currentSnapshot,
                    unavailableVaultPaths: unavailableRootPaths()
                )
                continue
            }
            guard !changedVaultIDs.isEmpty else { continue }
            do {
                if !derivedStateRequiresRefresh {
                    // FSEvents may coalesce harmless startup activity from
                    // several roots with one real source change. Scope the
                    // refresh outcome to vaults whose authoritative Markdown
                    // inventory actually differs from the published snapshot.
                    // An unreadable source still counts as changed so the
                    // subsequent full rebuild publishes a typed, vault-local
                    // failure instead of silently discarding the event.
                    changedVaultIDs = await sourceInventoryChanges(
                        vaultIDs: changedVaultIDs
                    )
                    guard !changedVaultIDs.isEmpty else { continue }
                }
                guard !sourceOperationGate.sourceMutationIsActive else {
                    for vaultID in changedVaultIDs {
                        var journal =
                            pendingLiveEvents[vaultID]
                            ?? VaultWatchEventJournal(capacity: 256)
                        journal.append(.reconciliationRequired(sequence: 0))
                        pendingLiveEvents[vaultID] = journal
                    }
                    break
                }
                _ = try await refresh(
                    publication: .liveInventory,
                    failureDisposition: .failed(
                        affectedVaultIDs: changedVaultIDs
                    )
                )
            } catch {
                // `refresh` already published one failed generation using the
                // complete last known good snapshot. Retain it for the next
                // native event or explicit refresh; never masquerade an
                // unchanged index as a successful rebuild.
            }
        }
        if liveIndexRefreshTask?.token == token {
            liveIndexRefreshTask = nil
            startLiveIndexRefreshIfNeeded()
        }
    }

    private func sourceInventoryChanges(vaultIDs: Set<UUID>) async -> Set<UUID> {
        let published = sourceRevisions(in: currentSnapshot)
        var changed: Set<UUID> = []
        for vaultID in vaultIDs {
            do {
                guard let catalog = services.sourceCatalogs[vaultID] else {
                    throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
                }
                let source = try await catalog.snapshot(refreshFolders: false)
                let publishedForVault = published.filter {
                    $0.key.vaultID == vaultID
                }
                guard source.documents.count == publishedForVault.count else {
                    changed.insert(vaultID)
                    continue
                }
                for document in source.documents {
                    let id = VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: document.relativePath
                    )
                    if publishedForVault[id] != document.fingerprint {
                        changed.insert(vaultID)
                        break
                    }
                }
            } catch {
                guard !Task.isCancelled else { return [] }
                changed.insert(vaultID)
            }
        }
        return changed
    }

    static func sourceInventory(
        assignment: TriptychAssignment,
        sourceCatalogs: [UUID: VaultSourceCatalog]
    ) async throws -> [VaultQualifiedNoteID: DocumentFingerprint] {
        var inputs: [WorkspaceSourceInventoryInput] = []
        for (order, slot) in WorkspaceVaultSlot.allCases.enumerated() {
            try Task.checkCancellation()
            guard let vault = assignment.vault(for: slot),
                let catalog = sourceCatalogs[vault.id]
            else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }
            inputs.append(
                WorkspaceSourceInventoryInput(
                    order: order,
                    vaultID: vault.id,
                    catalog: catalog
                ))
        }
        let sources = try await withThrowingTaskGroup(
            of: WorkspaceSourceInventorySnapshot.self
        ) { group in
            for input in inputs {
                group.addTask {
                    try Task.checkCancellation()
                    return WorkspaceSourceInventorySnapshot(
                        order: input.order,
                        vaultID: input.vaultID,
                        snapshot: try await input.catalog.snapshot()
                    )
                }
            }
            var loaded: [WorkspaceSourceInventorySnapshot] = []
            for try await source in group {
                loaded.append(source)
            }
            return loaded.sorted { $0.order < $1.order }
        }
        var observed: [VaultQualifiedNoteID: DocumentFingerprint] = [:]
        for source in sources {
            for document in source.snapshot.documents {
                try Task.checkCancellation()
                observed[
                    VaultQualifiedNoteID(
                        vaultID: source.vaultID,
                        relativePath: document.relativePath
                    )] =
                    document.fingerprint
            }
        }
        return observed
    }

    // Internal evidence for lifecycle tests; capabilities do not expose tasks.
    var ownedBackgroundTaskCount: Int {
        (liveWatcherTask == nil ? 0 : 1)
            + (openingCompletionTask == nil ? 0 : 1)
            + (liveIndexRefreshTask == nil ? 0 : 1)
    }

    var activationReconciliationCompleted: Bool {
        didCompleteActivationReconciliation
    }

    var watcherReadinessEvidence: WorkspaceWatcherReadinessEvidence? {
        guard liveWatcherTask != nil,
            currentSnapshot.phase.isComplete,
            didCompleteActivationReconciliation
        else { return nil }
        return WorkspaceWatcherReadinessEvidence(
            watchedVaultIDs: Set(assignment.vaults.values.map(\.id)),
            activationReconciliationCompleted: true
        )
    }

}
