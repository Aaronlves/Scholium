import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore

struct OwnedRefreshTask: Sendable {
    let token: UUID
    let task: Task<Void, Never>
}

/// One coordinator attempt owns capture and publication authority. Expensive
/// immutable preparation between those stages holds no source lease.
struct WorkspaceRefreshSourceAuthority {
    let id: UUID
    let sourceToken: UUID
    var lease: WorkspaceSourceOperationLease?
    let captureStarted: ContinuousClock.Instant
    var captureDuration = Duration.zero
    var publicationGateWaitDuration = Duration.zero
    var publicationStarted: ContinuousClock.Instant?
}

private enum WorkspaceRefreshPreparationError: Error {
    case superseded
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
    case sourceInventoryRevisionExhausted

    var errorDescription: String? {
        switch self {
        case .graphGenerationExhausted:
            "Workspace graph generation IDs were exhausted."
        case .sourceInventoryRevisionExhausted:
            "Workspace source inventory revision IDs were exhausted."
        }
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
    let fingerprints: [String: DocumentFingerprint]
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
        var payload = try WorkspaceRefreshPayload.merged(payloads)
        while true {
            try Task.checkCancellation()
            try requireActive()
            do {
                return try await performRefreshAttempt(requestID: requestID, payload: payload)
            } catch WorkspaceRefreshPreparationError.superseded {
                // A newer admitted source operation invalidated the captured
                // inputs. Its bytes are already durable; recapture all roles
                // rather than publishing stale success or failing coherent
                // callers that are still waiting for this coordinator cycle.
                payload = WorkspaceRefreshPayload(
                    publication: payload.publication,
                    failureDisposition: payload.failureDisposition,
                    sourceCatalogPreparation: .fullReconcile)
            }
        }
    }

    private func performRefreshAttempt(
        requestID: RefreshRequestID,
        payload: WorkspaceRefreshPayload
    ) async throws -> WorkspaceSnapshot {
        let clock = ContinuousClock()
        let cycleStart = clock.now
        // Reading the derived writer's watermark can wait behind a large
        // index operation. It owns no source state and must not stop saves.
        let indexedWorkspaceGeneration: UInt64
        do {
            indexedWorkspaceGeneration = try await services.searchIndex.workspaceGeneration()
        } catch {
            await publishRefreshFailure(error, payload: payload)
            throw error
        }
        let indexGenerationWaitDuration = cycleStart.duration(to: clock.now)
        let gateWaitStart = clock.now
        let refreshLease = try await beginRefreshCycle()
        let gateWaitDuration = gateWaitStart.duration(to: clock.now)
        precondition(refreshSourceAuthority == nil)
        let authorityID = UUID()
        refreshSourceAuthority = WorkspaceRefreshSourceAuthority(
            id: authorityID, sourceToken: sourceAuthorityToken, lease: refreshLease,
            captureStarted: clock.now)
        defer { endRefreshSourceAuthority(id: authorityID) }
        if mode == .live,
            case .liveInventory = payload.publication,
            case .none = payload.sourceCatalogPreparation,
            currentSnapshot.phase.isComplete,
            !derivedStateRequiresRefresh,
            currentSnapshot.research.healthIssues.isEmpty
        {
            // A live request can wait behind a source commit that already
            // publishes its complete inputs. Revalidate while holding the
            // existing source lease before allocating another graph generation.
            let changed = await sourceInventoryChanges(
                vaultIDs: Set(assignment.vaults.values.map(\.id))
            )
            try Task.checkCancellation()
            try requireActive()
            try requireRootAuthoritiesAvailable()
            if changed.isEmpty {
                return currentSnapshot
            }
        }
        var snapshot: WorkspaceSnapshot
        let measurement: WorkspaceRefreshMeasurement
        let sourcePreparationDuration: Duration
        let buildDuration: Duration
        do {
            guard currentSnapshot.sourceInventoryRevision < UInt64.max else {
                throw WorkspaceRefreshCycleError.sourceInventoryRevisionExhausted
            }
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
            var dependencies = services.snapshotBuilderDependencies
            dependencies.sourceCaptureDidComplete = { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.completeRefreshSourceCapture(id: authorityID)
            }
            dependencies.beginDerivedPublication = { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.beginRefreshDerivedPublication(id: authorityID)
            }
            #if DEBUG
                dependencies.capturedSearchManifestBarrierForTesting = capturedSearchManifestBarrierForTesting
            #endif
            let build = try await WorkspaceSnapshotBuilder.build(
                assignment: assignment,
                mode: mode,
                dependencies: dependencies,
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
            // Fresh row hydration can detect the newer bytes before Core
            // reaches final publication admission. It is still a superseded
            // capture, not a derived failure for coherent callers. Departure,
            // cancellation and unavailable root authority keep their meaning.
            if !Task.isCancelled, !isShutDown, unavailableRootVaultIDs.isEmpty,
                let authority = refreshSourceAuthority, authority.id == authorityID,
                authority.sourceToken != sourceAuthorityToken
            {
                throw WorkspaceRefreshPreparationError.superseded
            }
            await publishRefreshFailure(error, payload: payload)
            throw error
        }
        try requireActive()
        guard currentSnapshot.sourceInventoryRevision < UInt64.max else {
            throw WorkspaceRefreshCycleError.sourceInventoryRevisionExhausted
        }
        let previous = currentSnapshot
        let reviewInitializationStart = clock.now
        if !previous.phase.isComplete && snapshot.phase.isComplete {
            // Prepared libraries already established their source baselines.
            // Changes since those stages remain new observations; a complete
            // projection never turns them into an acknowledged source baseline.
            await initializeNewDocumentReviews(from: previous, to: snapshot)
            await initializeDocumentReviewsFromOpeningSnapshot(snapshot)
        } else if previous.phase.isComplete {
            await initializeNewDocumentReviews(from: previous, to: snapshot)
        }
        let reviewInitializationDuration = reviewInitializationStart.duration(to: clock.now)
        #if DEBUG
            await reviewedSnapshotPublicationBarrierForTesting?()
        #endif
        try Task.checkCancellation()
        try requireActive()
        try requireRootAuthoritiesAvailable()
        snapshot = snapshot.withDocumentChangesGeneration(
            currentSnapshot.documentChangesGeneration
        ).withSourceInventoryRevision(
            currentSnapshot.sourceInventoryRevision + 1
        )
        currentSnapshot = snapshot
        sourceAheadIdentityRecords.removeAll(keepingCapacity: true)
        sourceAheadSourceVersions.removeAll(keepingCapacity: true)
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
        let authority = refreshSourceAuthority
        let cycleMeasurement = WorkspaceRefreshCycleMeasurement(
            workspaceGeneration: measurement.workspaceGeneration,
            indexGenerationWaitDuration: indexGenerationWaitDuration,
            gateWaitDuration: gateWaitDuration,
            sourcePreparationDuration: sourcePreparationDuration,
            sourceCaptureLeaseDuration: authority?.captureDuration ?? .zero,
            buildDuration: buildDuration,
            publicationGateWaitDuration: authority?.publicationGateWaitDuration ?? .zero,
            reviewInitializationDuration: reviewInitializationDuration,
            publicationLeaseDuration: authority?.publicationStarted.map { $0.duration(to: clock.now) } ?? .zero,
            publicationDuration: publicationDuration,
            totalDuration: cycleStart.duration(to: clock.now)
        )
        latestRefreshCycleMeasurement = cycleMeasurement
        Self.logRefresh(measurement, publicationDuration: publicationDuration)
        Self.refreshLogger.info(
            "cycle generation=\(cycleMeasurement.workspaceGeneration, privacy: .public) indexGenerationWait=\(String(describing: cycleMeasurement.indexGenerationWaitDuration), privacy: .public) gateWait=\(String(describing: cycleMeasurement.gateWaitDuration), privacy: .public) sourcePreparation=\(String(describing: cycleMeasurement.sourcePreparationDuration), privacy: .public) captureLease=\(String(describing: cycleMeasurement.sourceCaptureLeaseDuration), privacy: .public) build=\(String(describing: cycleMeasurement.buildDuration), privacy: .public) publicationGateWait=\(String(describing: cycleMeasurement.publicationGateWaitDuration), privacy: .public) reviewInitialization=\(String(describing: cycleMeasurement.reviewInitializationDuration), privacy: .public) publicationLease=\(String(describing: cycleMeasurement.publicationLeaseDuration), privacy: .public) publish=\(String(describing: cycleMeasurement.publicationDuration), privacy: .public) total=\(String(describing: cycleMeasurement.totalDuration), privacy: .public)"
        )
        return snapshot
    }

    private func publishRefreshFailure(_ error: Error, payload: WorkspaceRefreshPayload) async {
        guard !(error is WorkspaceRefreshPreparationError), !Task.isCancelled, !isShutDown else { return }
        derivedStateRequiresRefresh = true
        await events.publishDerivedStateChanged(
            snapshot: currentSnapshot,
            status: payload.failureDisposition.status(for: error, lastKnownGood: currentSnapshot))
    }

    /// Library readiness belongs to source observation. The capture lease
    /// owns these source and identity stages before immutable derived work.
    private func publishOpeningSourceReadiness(_ source: WorkspaceSnapshot) async throws {
        try Task.checkCancellation()
        try requireActive()
        try requireRootAuthoritiesAvailable()
        guard !currentSnapshot.phase.isComplete else { return }
        guard
            source.vaults.contains(where: { prepared in
                guard let prior = currentSnapshot.vault(id: prepared.vault.id) else { return true }
                return prior.documents != prepared.documents || prior.folders != prepared.folders
            })
        else { return }
        guard currentSnapshot.sourceInventoryRevision < UInt64.max else {
            throw WorkspaceRefreshCycleError.sourceInventoryRevisionExhausted
        }
        let previous = currentSnapshot
        let prepared = WorkspaceSnapshotBuilder.mergingOpeningSource(source, into: previous)
        await initializeNewDocumentReviews(from: previous, to: prepared)
        await initializeDocumentReviewsFromOpeningSnapshot(source)
        // Review initialization performs authorized I/O. Root replacement or
        // departure while suspended must never expose the captured libraries.
        try Task.checkCancellation()
        try requireActive()
        try requireRootAuthoritiesAvailable()
        let snapshot = prepared.withDocumentChangesGeneration(
            currentSnapshot.documentChangesGeneration
        ).withSourceInventoryRevision(currentSnapshot.sourceInventoryRevision + 1)
        currentSnapshot = snapshot
        await publish(
            .liveInventory,
            previous: previous,
            snapshot: snapshot,
            confirmsEarlierFailure: true
        )
    }

    nonisolated static func logRefresh(
        _ measurement: WorkspaceRefreshMeasurement,
        publicationDuration: Duration?
    ) {
        refreshLogger.info(
            "generation=\(measurement.workspaceGeneration, privacy: .public) files=\(measurement.enumeratedFiles, privacy: .public) reads=\(measurement.readFiles, privacy: .public) parses=\(measurement.parsedDocuments, privacy: .public) projections=\(measurement.projectedDocuments, privacy: .public) restored=\(measurement.restoredSearchProjections, privacy: .public) sourceBytes=\(measurement.snapshotSourceBytes, privacy: .public) enumerate=\(String(describing: measurement.enumerationDuration), privacy: .public) read=\(String(describing: measurement.readDuration), privacy: .public) parse=\(String(describing: measurement.parseDuration), privacy: .public) project=\(String(describing: measurement.projectionDuration), privacy: .public) cacheRead=\(String(describing: measurement.cacheReadDuration), privacy: .public) cacheWrite=\(String(describing: measurement.cacheWriteDuration), privacy: .public) identity=\(String(describing: measurement.identityProjectionDuration), privacy: .public) links=\(String(describing: measurement.linkCatalogProjectionDuration), privacy: .public) graph=\(String(describing: measurement.graphDuration), privacy: .public) searchProjection=\(String(describing: measurement.searchDocumentProjectionDuration), privacy: .public) search=\(String(describing: measurement.searchDuration), privacy: .public) assemble=\(String(describing: measurement.snapshotAssemblyDuration), privacy: .public) publish=\(String(describing: publicationDuration), privacy: .public) total=\(String(describing: measurement.totalDuration), privacy: .public)"
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
            for slot in WorkspaceVaultSlot.allCases {
                guard let vault = assignment.vault(for: slot),
                    let catalog = services.sourceCatalogs[vault.id]
                else {
                    throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                }
                try await catalog.reconcile()
                if !currentSnapshot.phase.isComplete {
                    let source = try await WorkspaceSnapshotBuilder.buildOpening(
                        assignment: assignment,
                        mode: mode,
                        dependencies: services.snapshotBuilderDependencies,
                        availableVault: slot,
                        workspaceGeneration: latestRefreshMeasurement.workspaceGeneration,
                        consumePendingMeasurement: false
                    )
                    try await publishOpeningSourceReadiness(source.snapshot)
                }
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
        let oldFolders = Dictionary(uniqueKeysWithValues: previous.vaults.map { ($0.vault.id, $0.folders) })
        let newFolders = Dictionary(uniqueKeysWithValues: current.vaults.map { ($0.vault.id, $0.folders) })
        return (
            added,
            removed,
            Set(changed),
            moved,
            !added.isEmpty || !removed.isEmpty || !changed.isEmpty || !moved.isEmpty
                || oldFolders != newFolders
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
        defer {
            openingCompletionTask = nil
            if !Task.isCancelled { startLiveIndexRefreshIfNeeded() }
        }
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
        } catch {
            // Retain the usable opening vault and its typed failure. Buffered
            // or later native invalidations can reconcile current source once
            // this worker releases ownership; without one, Retry remains explicit.
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

    func beginSourceMutation(admission: AgentMutationAdmission? = nil) async throws -> WorkspaceSourceOperationLease {
        try requireActive()
        try requireRootAuthoritiesAvailable()
        do {
            let lease = try await acquireWorkspaceSourceOperation(.sourceMutation)
            do {
                try Task.checkCancellation()
                try requireActive()
                try requireRootAuthoritiesAvailable()
                // The live check runs only for the addressed Agent write while
                // its consequential lease is held. Success admits this source
                // transaction; Stop does not cancel its commit or recovery.
                if let admission { try await admission() }
                try requireActive()
                try requireRootAuthoritiesAvailable()
                sourceAuthorityToken = UUID()
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

    private func completeRefreshSourceCapture(id: UUID) throws {
        try Task.checkCancellation()
        try requireActive()
        try requireRootAuthoritiesAvailable()
        guard var authority = refreshSourceAuthority, authority.id == id,
            let lease = authority.lease
        else { throw CancellationError() }
        authority.captureDuration = authority.captureStarted.duration(to: .now)
        authority.lease = nil
        refreshSourceAuthority = authority
        releaseWorkspaceSourceOperation(lease)
    }

    private func beginRefreshDerivedPublication(id: UUID) async throws {
        guard let captured = refreshSourceAuthority, captured.id == id,
            captured.lease == nil
        else { throw CancellationError() }
        let waitStart = ContinuousClock.now
        let lease = try await beginRefreshCycle()
        guard var authority = refreshSourceAuthority, authority.id == id else {
            releaseWorkspaceSourceOperation(lease)
            throw CancellationError()
        }
        authority.lease = lease
        authority.publicationGateWaitDuration = waitStart.duration(to: .now)
        authority.publicationStarted = .now
        refreshSourceAuthority = authority
        guard authority.sourceToken == sourceAuthorityToken else {
            throw WorkspaceRefreshPreparationError.superseded
        }
    }

    private func endRefreshSourceAuthority(id: UUID) {
        guard let authority = refreshSourceAuthority, authority.id == id else {
            preconditionFailure("Refresh source authority must end with its owning attempt.")
        }
        refreshSourceAuthority = nil
        if let lease = authority.lease { releaseWorkspaceSourceOperation(lease) }
    }

    private func startLiveIndexRefreshIfNeeded() {
        guard !isShutDown,
            currentSnapshot.phase.isComplete
                || (didCompleteActivationReconciliation && openingCompletionTask == nil),
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
                if let barrier = committedMutationRefreshBarrierForTesting { await barrier() }
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
                    #if DEBUG
                        await liveInventoryPreflightBarrierForTesting?()
                    #endif
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
                let completesOpening = !currentSnapshot.phase.isComplete
                _ = try await refresh(
                    publication: .liveInventory,
                    failureDisposition: .failed(
                        affectedVaultIDs: completesOpening
                            ? Set(assignment.vaults.values.map(\.id)) : changedVaultIDs
                    ),
                    // A rejected opening may have captured catalog versions
                    // before this invalidation. Reconcile all roles before
                    // attempting the first complete publication again.
                    sourceCatalogPreparation: completesOpening ? .fullReconcile : SourceCatalogPreparation.none
                )
            } catch {
                // `refresh` already published one failed generation using the
                // last known good snapshot. Retain it for the next
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
        var changed: Set<UUID> = []
        var observed: [UUID: VaultSourceCatalogPublicationInventory] = [:]
        for vaultID in vaultIDs {
            do {
                guard let catalog = services.sourceCatalogs[vaultID] else {
                    throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
                }
                observed[vaultID] = try await catalog.publicationInventory()
            } catch {
                guard !Task.isCancelled else { return [] }
                changed.insert(vaultID)
            }
        }
        // Capture publication after the asynchronous catalog reads. A save may
        // have published while those reads were suspended; comparing with the
        // old snapshot would queue a duplicate complete rebuild.
        let published = currentSnapshot
        var expectedIdentities: [UUID: [String: NoteIdentityRecord]] = [:]
        for (vaultID, inventory) in observed {
            guard let vault = published.vault(id: vaultID),
                inventory.fingerprints.count == vault.documents.count,
                inventory.folders == vault.folders,
                vault.identityRecovery.ambiguities.isEmpty,
                vault.identityRecovery.pendingRebindings.isEmpty,
                vault.identityRecovery.failures.isEmpty
            else {
                changed.insert(vaultID)
                continue
            }
            if vault.documents.contains(where: {
                inventory.fingerprints[$0.id.relativePath] != $0.fingerprint
                    || inventory.fileMetadata[$0.id.relativePath] != $0.fileMetadata
                    || $0.stableIdentity.resolvedID == nil
                    || vault.identityRecovery.identities[$0.id.relativePath]?.id != $0.stableIdentity.resolvedID
            }) {
                changed.insert(vaultID)
                continue
            }
            expectedIdentities[vaultID] = vault.identityRecovery.identities
        }
        if !expectedIdentities.isEmpty {
            do {
                changed.formUnion(try await services.controlStore.identityInventoryChanges(comparedWith: expectedIdentities))
            } catch {
                guard !Task.isCancelled else { return [] }
                changed.formUnion(expectedIdentities.keys)
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
                        fingerprints: try await input.catalog.sourceInventory()
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
            for (path, fingerprint) in source.fingerprints {
                try Task.checkCancellation()
                observed[
                    VaultQualifiedNoteID(
                        vaultID: source.vaultID,
                        relativePath: path
                    )] =
                    fingerprint
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
