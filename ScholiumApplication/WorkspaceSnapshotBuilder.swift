import Foundation
import ScholiumContracts
import ScholiumCore

/// Work carried into the accepted builder inputs. Rejected source cohorts may
/// already have consumed catalog counters; these are not whole-cycle I/O totals.
struct WorkspaceRefreshMeasurement: Sendable {
    let workspaceGeneration: UInt64
    let enumeratedFiles: Int
    let readFiles: Int
    let parsedDocuments: Int
    let projectedDocuments: Int
    let restoredSearchProjections: Int
    let enumerationDuration: Duration
    let readDuration: Duration
    let parseDuration: Duration
    let projectionDuration: Duration
    let cacheReadDuration: Duration
    let cacheWriteDuration: Duration
    let identityProjectionDuration: Duration
    let linkCatalogProjectionDuration: Duration
    let graphDuration: Duration
    let searchDocumentProjectionDuration: Duration
    let searchDuration: Duration
    let snapshotAssemblyDuration: Duration
    let totalDuration: Duration
    let snapshotSourceBytes: Int
}

/// One successful coordinator attempt, including preparation before the builder.
/// Capture duration covers its accepted cohort; rejected capture holds and outer
/// superseded attempts are excluded. Caller wall time includes those retries.
/// Catalog per-file timings are summed work, not elapsed time.
struct WorkspaceRefreshCycleMeasurement: Sendable {
    let workspaceGeneration: UInt64
    let indexGenerationWaitDuration: Duration
    let gateWaitDuration: Duration
    let sourcePreparationDuration: Duration
    let sourceCatalogInstallationLeaseDuration: Duration
    let longestSourceCatalogInstallationLeaseDuration: Duration
    let sourceCaptureLeaseDuration: Duration
    let buildDuration: Duration
    let publicationGateWaitDuration: Duration
    let reviewInitializationDuration: Duration
    let publicationLeaseDuration: Duration
    let publicationDuration: Duration
    let totalDuration: Duration
}

struct WorkspaceSnapshotBuildResult: Sendable {
    let snapshot: WorkspaceSnapshot
    let measurement: WorkspaceRefreshMeasurement
}

struct WorkspaceSnapshotBuilderDependencies: Sendable {
    let repositories: [UUID: VaultRepository]
    let searchIndex: TriptychSearchIndex
    let controlStore: TriptychControlStore
    let transactionRecoveryStore: TriptychMutationRecoveryStore
    let identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator
    var sourceCaptureDidComplete: (@Sendable () async throws -> Void)?
    var beginDerivedPublication: (@Sendable () async throws -> Void)?
    #if DEBUG
        var capturedSearchManifestBarrierForTesting: (@Sendable () async -> Void)?
    #endif
}

extension WorkspaceServices {
    var snapshotBuilderDependencies: WorkspaceSnapshotBuilderDependencies {
        WorkspaceSnapshotBuilderDependencies(
            repositories: repositories,
            searchIndex: searchIndex,
            controlStore: controlStore,
            transactionRecoveryStore: transactionRecoveryStore,
            identityRecoveryCoordinator: identityRecoveryCoordinator
        )
    }
}

enum WorkspaceSnapshotBuilder {
    struct GraphDiagnosticCounts: Equatable, Sendable {
        var broken = 0
        var ambiguous = 0
    }

    /// A complete generation's diagnostics are shared by every Note summary.
    /// Count them once rather than filtering the full array for each Note.
    static func graphDiagnosticCountsBySource(
        in graph: GraphSnapshot?
    ) -> [VaultQualifiedNoteID: GraphDiagnosticCounts] {
        var counts: [VaultQualifiedNoteID: GraphDiagnosticCounts] = [:]
        for diagnostic in graph?.diagnostics ?? [] {
            switch diagnostic.code {
            case .broken:
                counts[diagnostic.source, default: GraphDiagnosticCounts()].broken += 1
            case .ambiguous, .ambiguousHeading, .ambiguousBlock:
                counts[diagnostic.source, default: GraphDiagnosticCounts()].ambiguous += 1
            case .missingHeading, .missingBlock:
                break
            }
        }
        return counts
    }

    /// A journaled duplicate owns its reserved UUID before source creation.
    /// Inventory must never mint another identity during that interruption gap.
    private static func citationCreationReservations(
        vaultID: UUID, dependencies: WorkspaceSnapshotBuilderDependencies
    ) async throws -> Set<String> {
        var paths: Set<String> = []
        for recovery in try await dependencies.transactionRecoveryStore.pendingCitationSaves()
        where recovery.vaultID == vaultID && recovery.sourceBefore == nil {
            if try await dependencies.controlStore.identityRecord(
                vaultID: vaultID, relativePath: recovery.relativePath)?.id != recovery.noteID
            {
                paths.insert(recovery.relativePath)
            }
        }
        return paths
    }

    private struct LoadedVault: Sendable {
        let slot: WorkspaceVaultSlot
        let vault: RegisteredVault
        let pathComparisonPolicy: VaultPathComparisonPolicy
        let folders: [VaultRelativeFolderPath]
        let fileMetadata: [String: WorkspaceFileMetadata]
        let projections: [WorkspaceSourceProjection]
        let sourceVersions: [String: SourceVersion]
        let searchProjectionCache: SourceSearchProjectionCache?
        let identityStates: [String: WorkspaceNoteIdentityState]
        let identityRecovery: NoteIdentityRecoveryState
        let identityHealthIssues: [String]
    }

    private struct SourceInput: Sendable {
        let order: Int
        let slot: WorkspaceVaultSlot
        let vault: RegisteredVault
        let pathComparisonPolicy: VaultPathComparisonPolicy
        let repository: VaultRepository
        let sourceSnapshot: VaultSourceCatalogSnapshot
    }

    private struct LoadedSource: Sendable {
        let input: SourceInput
        let snapshot: VaultSourceCatalogSnapshot
    }

    /// Builds one complete source catalog without claiming derived readiness.
    /// Opening first exposes the selected vault; the same path prepares each
    /// remaining Library before Graph and Search publish a complete generation.
    static func buildOpening(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        dependencies: WorkspaceSnapshotBuilderDependencies,
        availableVault slot: WorkspaceVaultSlot,
        sourceSnapshot: VaultSourceCatalogSnapshot,
        workspaceGeneration: UInt64
    ) async throws -> WorkspaceSnapshotBuildResult {
        let clock = ContinuousClock()
        let totalStart = clock.now
        try Task.checkCancellation()
        guard mode == .live,
            let vault = assignment.vault(for: slot),
            let repository = dependencies.repositories[vault.id]
        else {
            throw ScholiumApplicationError.incompleteTriptych(assignment.id)
        }

        let rootURL = await repository.vaultURL
        let pathComparisonPolicy = await repository.pathComparisonPolicy()
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(
                atPath: rootURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue
        else {
            throw WorkspaceFileEventWatcherError.rootUnavailable(rootURL.path)
        }

        let projections = sourceSnapshot.projections

        let identityProjectionStart = clock.now
        var identityStates = Dictionary(
            uniqueKeysWithValues: projections.map {
                ($0.relativePath, WorkspaceNoteIdentityState.unresolved)
            }
        )
        var identityHealthIssues: [String] = []
        var identityRecovery = NoteIdentityRecoveryState(
            identities: [:],
            ambiguities: [],
            pendingRebindings: [],
            failures: []
        )
        do {
            let reservedCitationPaths = try await citationCreationReservations(
                vaultID: vault.id, dependencies: dependencies)
            let recovery = try await dependencies.identityRecoveryCoordinator.reconcile(
                vaultID: vault.id,
                documents: projections.filter { !reservedCitationPaths.contains($0.relativePath) }
                    .map { ($0.relativePath, $0.fingerprint) },
                repository: repository
            )
            identityRecovery = recovery
            for (path, record) in recovery.identities {
                identityStates[path] = .resolved(record.id)
            }
            for ambiguity in recovery.ambiguities {
                identityStates[ambiguity.relativePath] = .ambiguous(
                    candidateIDs: ambiguity.candidates.map(\.id).sorted {
                        $0.uuidString < $1.uuidString
                    }
                )
            }
            for pending in recovery.pendingRebindings {
                identityStates[pending.relativePath] = .pending(pending.noteID)
            }
            identityHealthIssues.append(contentsOf: recovery.failures.map(\.message))
            if !reservedCitationPaths.isEmpty {
                identityHealthIssues.append("Citation creation recovery must establish its reserved Note identities before inventory can assign them.")
            }
        } catch {
            identityHealthIssues.append(
                "Portable note identity for \(vault.name): \(error.localizedDescription)"
            )
        }
        let identityProjectionDuration = identityProjectionStart.duration(to: clock.now)
        try Task.checkCancellation()

        let assemblyStart = clock.now
        let loaded = LoadedVault(
            slot: slot,
            vault: vault,
            pathComparisonPolicy: pathComparisonPolicy,
            folders: sourceSnapshot.folders,
            fileMetadata: sourceSnapshot.fileMetadata,
            projections: projections,
            sourceVersions: sourceSnapshot.sourceVersions,
            searchProjectionCache: sourceSnapshot.searchProjectionCache,
            identityStates: identityStates,
            identityRecovery: identityRecovery,
            identityHealthIssues: identityHealthIssues
        )
        let snapshot = try makeSnapshot(
            assignment: assignment,
            mode: mode,
            phase: .opening,
            loadedVaults: [loaded],
            graph: nil,
            searchGeneration: nil,
            research: WorkspaceResearchSnapshot(healthIssues: identityHealthIssues)
        )
        let assemblyDuration = assemblyStart.duration(to: clock.now)
        let measurement = sourceSnapshot.measurement
        return WorkspaceSnapshotBuildResult(
            snapshot: snapshot,
            measurement: WorkspaceRefreshMeasurement(
                workspaceGeneration: workspaceGeneration,
                enumeratedFiles: measurement.enumeratedFiles,
                readFiles: measurement.readFiles,
                parsedDocuments: measurement.parsedDocuments,
                projectedDocuments: 0,
                restoredSearchProjections: 0,
                enumerationDuration: measurement.enumerationDuration,
                readDuration: measurement.readDuration,
                parseDuration: measurement.parseDuration,
                projectionDuration: .zero,
                cacheReadDuration: .zero,
                cacheWriteDuration: .zero,
                identityProjectionDuration: identityProjectionDuration,
                linkCatalogProjectionDuration: .zero,
                graphDuration: .zero,
                searchDocumentProjectionDuration: .zero,
                searchDuration: .zero,
                snapshotAssemblyDuration: assemblyDuration,
                totalDuration: totalStart.duration(to: clock.now),
                snapshotSourceBytes: snapshot.vaults
                    .flatMap { $0.documents }
                    .reduce(0) { $0 + $1.fingerprint.byteCount }
            )
        )
    }

    static func build(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        dependencies: WorkspaceSnapshotBuilderDependencies,
        sourceSnapshots: [UUID: VaultSourceCatalogSnapshot],
        graphGeneration: Int,
        workspaceGeneration: UInt64
    ) async throws -> WorkspaceSnapshotBuildResult {
        let clock = ContinuousClock()
        let totalStart = clock.now
        try Task.checkCancellation()
        var loadedVaults: [LoadedVault] = []
        var authoredLinks: [VaultQualifiedNoteID: [LinkOccurrence]] = [:]
        var linkCatalog: [LinkCatalogNote] = []
        var sourceMeasurements: [VaultSourceCatalogMeasurement] = []
        var identityProjectionDuration = Duration.zero
        var linkCatalogProjectionDuration = Duration.zero

        var sourceInputs: [SourceInput] = []
        for (order, slot) in WorkspaceVaultSlot.allCases.enumerated() {
            try Task.checkCancellation()
            guard let vault = assignment.vault(for: slot),
                let repository = dependencies.repositories[vault.id],
                let sourceSnapshot = sourceSnapshots[vault.id]
            else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }
            let rootURL = await repository.vaultURL
            let pathComparisonPolicy = await repository.pathComparisonPolicy()
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(
                    atPath: rootURL.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue
            else {
                throw WorkspaceFileEventWatcherError.rootUnavailable(rootURL.path)
            }
            sourceInputs.append(
                SourceInput(
                    order: order,
                    slot: slot,
                    vault: vault,
                    pathComparisonPolicy: pathComparisonPolicy,
                    repository: repository,
                    sourceSnapshot: sourceSnapshot
                ))
        }

        let loadedSources = sourceInputs.map {
            LoadedSource(input: $0, snapshot: $0.sourceSnapshot)
        }

        for loadedSource in loadedSources {
            try Task.checkCancellation()
            let slot = loadedSource.input.slot
            let vault = loadedSource.input.vault
            let repository = loadedSource.input.repository
            // The refresh coordinator has already reconciled or applied the
            // exact event delta. Do not repeat directory enumeration while
            // assembling this immutable generation.
            let sourceSnapshot = loadedSource.snapshot
            sourceMeasurements.append(sourceSnapshot.measurement)
            let projections = sourceSnapshot.projections
            for projection in projections {
                try Task.checkCancellation()
                let id = VaultQualifiedNoteID(
                    vaultID: vault.id,
                    relativePath: projection.relativePath
                )
                authoredLinks[id] = projection.authoredLinks
            }
            let identityProjectionStart = clock.now
            var identityStates = Dictionary(
                uniqueKeysWithValues: projections.map {
                    ($0.relativePath, WorkspaceNoteIdentityState.unresolved)
                }
            )
            var identityHealthIssues: [String] = []
            var identityRecovery = NoteIdentityRecoveryState(
                identities: [:],
                ambiguities: [],
                pendingRebindings: [],
                failures: []
            )
            do {
                let reservedCitationPaths = try await citationCreationReservations(
                    vaultID: vault.id, dependencies: dependencies)
                let recovery = try await dependencies.identityRecoveryCoordinator.reconcile(
                    vaultID: vault.id,
                    documents: projections.filter { !reservedCitationPaths.contains($0.relativePath) }
                        .map { ($0.relativePath, $0.fingerprint) },
                    repository: repository
                )
                identityRecovery = recovery
                for (path, record) in recovery.identities {
                    identityStates[path] = .resolved(record.id)
                }
                for ambiguity in recovery.ambiguities {
                    identityStates[ambiguity.relativePath] = .ambiguous(
                        candidateIDs: ambiguity.candidates.map(\.id).sorted {
                            $0.uuidString < $1.uuidString
                        }
                    )
                }
                for pending in recovery.pendingRebindings {
                    identityStates[pending.relativePath] = .pending(pending.noteID)
                }
                identityHealthIssues.append(contentsOf: recovery.failures.map(\.message))
                if !reservedCitationPaths.isEmpty {
                    identityHealthIssues.append("Citation creation recovery must establish its reserved Note identities before inventory can assign them.")
                }
            } catch {
                identityHealthIssues.append(
                    "Portable note identity for \(vault.name): \(error.localizedDescription)"
                )
            }
            identityProjectionDuration += identityProjectionStart.duration(to: clock.now)
            let linkCatalogStart = clock.now
            for projection in projections {
                linkCatalog.append(projection.linkCatalog)
            }
            loadedVaults.append(
                LoadedVault(
                    slot: slot,
                    vault: vault,
                    pathComparisonPolicy: loadedSource.input.pathComparisonPolicy,
                    folders: sourceSnapshot.folders,
                    fileMetadata: sourceSnapshot.fileMetadata,
                    projections: projections,
                    sourceVersions: sourceSnapshot.sourceVersions,
                    searchProjectionCache: sourceSnapshot.searchProjectionCache,
                    identityStates: identityStates,
                    identityRecovery: identityRecovery,
                    identityHealthIssues: identityHealthIssues
                )
            )
            linkCatalogProjectionDuration += linkCatalogStart.duration(to: clock.now)
        }

        // Portable identity reconciliation above changes authoritative state.
        // The remaining Graph and Search preparation consumes these immutable
        // inputs, so it must not retain the source transaction's lease.
        try await dependencies.sourceCaptureDidComplete?()

        let sourceManifestHash = SearchSourceManifest.hash(
            loadedVaults.flatMap { loaded in
                loaded.projections.map {
                    SearchSourceManifestEntry(
                        vaultID: loaded.vault.id,
                        relativePath: $0.relativePath,
                        fingerprint: $0.fingerprint
                    )
                }
            }
        )
        let graph: GraphSnapshot?
        let graphBuildIssue: String?
        let graphStart = clock.now
        do {
            graph = try LinkGraphBuilder.buildCancellable(
                generation: graphGeneration,
                catalog: linkCatalog,
                authoredLinks: authoredLinks,
                resolutionScope: .workspace,
                sourceManifestHash: sourceManifestHash
            )
            graphBuildIssue = nil
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Search is an independent projection of the same source
            // snapshot. A graph failure must not prevent a complete lexical
            // generation from replacing its predecessor.
            graph = nil
            graphBuildIssue = "Link graph: \(error.localizedDescription)"
        }
        let graphDuration = graphStart.duration(to: clock.now)
        let brokenNoteIDs = Set(
            (graph?.diagnostics ?? []).compactMap { diagnostic in
                diagnostic.code == .broken ? diagnostic.source : nil
            })

        let searchDocumentProjectionStart = clock.now
        var searchManifest: [SearchIndexManifestEntry] = []

        for loaded in loadedVaults {
            try Task.checkCancellation()
            searchManifest.append(
                contentsOf: loaded.projections.map { projection in
                    let id = VaultQualifiedNoteID(
                        vaultID: loaded.vault.id,
                        relativePath: projection.relativePath
                    )
                    let stableNoteID: String?
                    if case .resolved(let noteID) = loaded.identityStates[projection.relativePath] {
                        stableNoteID = noteID.uuidString.lowercased()
                    } else {
                        stableNoteID = nil
                    }
                    return SearchIndexManifestEntry(
                        vaultID: loaded.vault.id,
                        vaultName: loaded.vault.name,
                        vaultRole: loaded.vault.role,
                        relativePath: projection.relativePath,
                        stableNoteID: stableNoteID,
                        fingerprint: projection.fingerprint,
                        hasBrokenLink: brokenNoteIDs.contains(id)
                    )
                })
        }
        let searchDocumentProjectionDuration = searchDocumentProjectionStart.duration(
            to: clock.now
        )
        let searchStart = clock.now
        let capturedRepositories = dependencies.repositories
        let capturedVersions = Dictionary(
            uniqueKeysWithValues: loadedVaults.map {
                ($0.vault.id, $0.sourceVersions)
            })
        let capturedManifest = searchManifest
        #if DEBUG
            await dependencies.capturedSearchManifestBarrierForTesting?()
        #endif
        let searchPublication = try await dependencies.searchIndex.synchronizeManifest(
            searchManifest,
            sourceProjectionCaches: Dictionary(
                uniqueKeysWithValues: loadedVaults.compactMap { loaded in
                    loaded.searchProjectionCache.map { (loaded.vault.id, $0) }
                }),
            workspaceGeneration: workspaceGeneration,
            loadChanged: { entry in
                try Task.checkCancellation()
                guard let repository = capturedRepositories[entry.vaultID],
                    let version = capturedVersions[entry.vaultID]?[entry.relativePath]
                else {
                    throw SearchIndexError.invalidDocuments("Search source authority is unavailable")
                }
                let loaded = try await repository.loadCatalogSource(relativePath: entry.relativePath)
                guard loaded.version == version,
                    loaded.document.fingerprint == entry.fingerprint
                else {
                    throw SearchIndexError.invalidDocuments("Search source changed before row preparation")
                }
                return SearchIndexDocument(
                    vaultID: entry.vaultID, vaultName: entry.vaultName,
                    vaultRole: entry.vaultRole, document: loaded.document,
                    stableNoteID: entry.stableNoteID,
                    hasBrokenLink: entry.hasBrokenLink
                )
            },
            validateManifest: {
                // The handle retains this authority through SQLite COMMIT and
                // its matching complete snapshot publication. Checking only
                // source versions would leave a same-App write in that gap.
                try await dependencies.beginDerivedPublication?()
                for entry in capturedManifest {
                    try Task.checkCancellation()
                    guard let repository = capturedRepositories[entry.vaultID],
                        let version = capturedVersions[entry.vaultID]?[entry.relativePath],
                        try await repository.sourceVersionIsCurrent(
                            relativePath: entry.relativePath, version: version)
                    else {
                        throw SearchIndexError.invalidDocuments("Search source changed before complete publication")
                    }
                }
            }
        )
        let searchPreparation = await dependencies.searchIndex.lastSynchronizationTimings
        let searchDuration = searchStart.duration(to: clock.now)
        guard searchPublication.generation.sourceManifestHash == sourceManifestHash else {
            throw SearchIndexError.invalidDocuments(
                "Search and Graph were derived from different source manifests"
            )
        }

        let assemblyStart = clock.now
        var healthIssues: [String] = []
        healthIssues.append(contentsOf: loadedVaults.flatMap(\.identityHealthIssues))
        if let graphBuildIssue { healthIssues.append(graphBuildIssue) }
        let recoveryRecords: [TriptychMutationRecoveryRecord]
        do {
            recoveryRecords = try await dependencies.transactionRecoveryStore.pending()
        } catch {
            recoveryRecords = []
            healthIssues.append(
                "Durable transaction recovery: \(error.localizedDescription)"
            )
        }
        for loaded in loadedVaults {
            if let repository = dependencies.repositories[loaded.vault.id],
                let issue = await repository.recoveryLedgerHealthDiagnostic()
            {
                healthIssues.append("\(loaded.vault.name): \(issue)")
            }
        }

        let research = WorkspaceResearchSnapshot(
            recoveryRecords: recoveryRecords,
            healthIssues: Array(Set(healthIssues)).sorted()
        )
        let snapshot = try makeSnapshot(
            assignment: assignment,
            mode: mode,
            phase: .complete,
            loadedVaults: loadedVaults,
            graph: graph,
            searchGeneration: searchPublication.generation,
            research: research
        )
        let assemblyDuration = assemblyStart.duration(to: clock.now)
        return WorkspaceSnapshotBuildResult(
            snapshot: snapshot,
            measurement: WorkspaceRefreshMeasurement(
                workspaceGeneration: workspaceGeneration,
                enumeratedFiles: sourceMeasurements.reduce(0) {
                    $0 + $1.enumeratedFiles
                },
                readFiles: sourceMeasurements.reduce(0) { $0 + $1.readFiles },
                parsedDocuments: sourceMeasurements.reduce(0) {
                    $0 + $1.parsedDocuments
                },
                projectedDocuments: searchPreparation?.projectedDocuments ?? 0,
                restoredSearchProjections: searchPreparation?.restoredSearchProjections ?? 0,
                enumerationDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.enumerationDuration
                },
                readDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.readDuration
                },
                parseDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.parseDuration
                },
                projectionDuration: searchPreparation?.projectionDuration ?? .zero,
                cacheReadDuration: searchPreparation?.cacheReadDuration ?? .zero,
                cacheWriteDuration: searchPreparation?.cacheWriteDuration ?? .zero,
                identityProjectionDuration: identityProjectionDuration,
                linkCatalogProjectionDuration: linkCatalogProjectionDuration,
                graphDuration: graphDuration,
                searchDocumentProjectionDuration:
                    searchDocumentProjectionDuration,
                searchDuration: searchDuration,
                snapshotAssemblyDuration: assemblyDuration,
                totalDuration: totalStart.duration(to: clock.now),
                snapshotSourceBytes: snapshot.vaults
                    .flatMap(\.documents)
                    .reduce(0) { $0 + $1.fingerprint.byteCount }
            )
        )
    }

    /// Each prepared vault replaces only its own source catalog. No index,
    /// Graph, or completeness claim is synthesized from these opening stages.
    static func mergingOpeningSource(
        _ source: WorkspaceSnapshot,
        into previous: WorkspaceSnapshot
    ) -> WorkspaceSnapshot {
        precondition(!source.phase.isComplete && !previous.phase.isComplete)
        let replacedVaultIDs = Set(source.vaults.map { $0.vault.id })
        let vaultsBySlot = Dictionary(
            uniqueKeysWithValues:
                previous.vaults.filter { !replacedVaultIDs.contains($0.vault.id) }
                .map { ($0.slot, $0) } + source.vaults.map { ($0.slot, $0) }
        )
        let priorCatalog = previous.discovery.catalog
        let sourceCatalog = source.discovery.catalog
        let catalog = WorkspaceCatalogSnapshot(
            generatedAt: source.generatedAt,
            notes: (priorCatalog.notes.filter { !replacedVaultIDs.contains($0.reference.vaultID) }
                + sourceCatalog.notes).sorted { $0.reference.id < $1.reference.id },
            attention: priorCatalog.attention.filter { !replacedVaultIDs.contains($0.note.vaultID) }
                + sourceCatalog.attention,
            graph: nil
        )
        return WorkspaceSnapshot(
            triptych: source.triptych,
            mode: source.mode,
            phase: .opening,
            generatedAt: source.generatedAt,
            vaults: WorkspaceVaultSlot.allCases.compactMap { vaultsBySlot[$0] },
            discovery: WorkspaceDiscoverySnapshot(catalog: catalog, searchGeneration: nil),
            research: WorkspaceResearchSnapshot(
                healthIssues: Array(Set(previous.research.healthIssues + source.research.healthIssues)).sorted()
            ),
            sourceInventoryRevision: previous.sourceInventoryRevision,
            documentChangesGeneration: previous.documentChangesGeneration
        )
    }

    /// One source projection path feeds every opening stage and the final
    /// derived generation. Readiness changes no Note identity or source bytes.
    private static func makeSnapshot(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        phase: WorkspaceSnapshotPhase,
        loadedVaults: [LoadedVault],
        graph: GraphSnapshot?,
        searchGeneration: SearchGenerationID?,
        research: WorkspaceResearchSnapshot
    ) throws -> WorkspaceSnapshot {
        let stableNoteIDs = Dictionary(
            uniqueKeysWithValues: loadedVaults.flatMap { loaded in
                loaded.identityStates.compactMap { path, state -> (VaultQualifiedNoteID, UUID)? in
                    guard case .resolved(let noteID) = state else { return nil }
                    return (
                        VaultQualifiedNoteID(vaultID: loaded.vault.id, relativePath: path),
                        noteID
                    )
                }
            }
        )
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: loadedVaults.map(\.vault),
            projections: Dictionary(uniqueKeysWithValues: loadedVaults.map { ($0.vault.id, $0.projections) }),
            graph: graph,
            identityAmbiguitiesByVault: Dictionary(
                uniqueKeysWithValues: loadedVaults.map { ($0.vault.id, $0.identityRecovery.ambiguities) }
            ),
            stableNoteIDs: stableNoteIDs
        )
        let diagnosticCounts = graphDiagnosticCountsBySource(in: graph)
        let vaultSnapshots = try loadedVaults.map { loaded in
            WorkspaceVaultSnapshot(
                slot: loaded.slot,
                vault: loaded.vault,
                pathComparisonPolicy: loaded.pathComparisonPolicy,
                documents: try loaded.projections.map { projection in
                    let id = VaultQualifiedNoteID(vaultID: loaded.vault.id, relativePath: projection.relativePath)
                    guard let metadata = loaded.fileMetadata[projection.relativePath] else {
                        throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                    }
                    return WorkspaceNoteSummary(
                        id: id,
                        vaultRole: loaded.vault.role,
                        stableIdentity: loaded.identityStates[projection.relativePath] ?? .unresolved,
                        fingerprint: projection.fingerprint,
                        fileMetadata: metadata,
                        graphCounts: WorkspaceGraphCounts(
                            incoming: graph?.incoming[id]?.count ?? 0,
                            outgoing: graph?.outgoing[id]?.count ?? 0,
                            broken: diagnosticCounts[id]?.broken ?? 0,
                            ambiguous: diagnosticCounts[id]?.ambiguous ?? 0
                        ),
                        linkCatalog: projection.linkCatalog,
                        title: projection.title,
                        validationWarnings: projection.validationWarnings,
                        propertyTextValues: projection.propertyTextValues,
                        canonicalAliases: projection.canonicalAliases,
                        canonicalKeywords: projection.canonicalKeywords
                    )
                },
                folders: loaded.folders,
                identityRecovery: loaded.identityRecovery
            )
        }
        return WorkspaceSnapshot(
            triptych: assignment.triptych,
            mode: mode,
            phase: phase,
            generatedAt: Date(),
            vaults: vaultSnapshots,
            discovery: WorkspaceDiscoverySnapshot(catalog: catalog, searchGeneration: searchGeneration),
            research: research
        )
    }

}
