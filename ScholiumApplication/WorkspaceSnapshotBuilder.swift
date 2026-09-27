import Foundation
import ScholiumContracts
import ScholiumCore

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
    let researchStateDuration: Duration
    let searchDocumentProjectionDuration: Duration
    let searchDuration: Duration
    let snapshotAssemblyDuration: Duration
    let totalDuration: Duration
    let snapshotSourceBytes: Int
}

/// Elapsed time for one coordinator cycle, including preparation performed
/// before the snapshot builder starts. Catalog per-file timings are summed
/// work durations and are not a substitute for this wall-clock measurement.
struct WorkspaceRefreshCycleMeasurement: Sendable {
    let workspaceGeneration: UInt64
    let gateWaitDuration: Duration
    let sourcePreparationDuration: Duration
    let buildDuration: Duration
    let publicationDuration: Duration
    let totalDuration: Duration
}

struct WorkspaceSnapshotBuildResult: Sendable {
    let snapshot: WorkspaceSnapshot
    let measurement: WorkspaceRefreshMeasurement
}

struct WorkspaceSnapshotBuilderDependencies: Sendable {
    let repositories: [UUID: VaultRepository]
    let sourceCatalogs: [UUID: VaultSourceCatalog]
    let searchIndex: TriptychSearchIndex
    let controlStore: TriptychControlStore
    let settlementStore: SettlementStore
    let transactionRecoveryStore: TriptychMutationRecoveryStore
    let identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator
}

extension WorkspaceServices {
    var snapshotBuilderDependencies: WorkspaceSnapshotBuilderDependencies {
        WorkspaceSnapshotBuilderDependencies(
            repositories: repositories,
            sourceCatalogs: sourceCatalogs,
            searchIndex: searchIndex,
            controlStore: controlStore,
            settlementStore: settlementStore,
            transactionRecoveryStore: transactionRecoveryStore,
            identityRecoveryCoordinator: identityRecoveryCoordinator
        )
    }
}

enum WorkspaceSnapshotBuilder {
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
        let catalog: VaultSourceCatalog
    }

    private struct LoadedSource: Sendable {
        let input: SourceInput
        let snapshot: VaultSourceCatalogSnapshot
    }

    /// Builds the first researcher-usable live projection without claiming a
    /// complete Triptych generation. The selected vault's source, metadata,
    /// and stable identities are authoritative; Graph, Search, and portable
    /// research projections remain explicitly unavailable until `build`
    /// publishes the complete replacement.
    static func buildOpening(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        dependencies: WorkspaceSnapshotBuilderDependencies,
        availableVault slot: WorkspaceVaultSlot,
        workspaceGeneration: UInt64
    ) async throws -> WorkspaceSnapshotBuildResult {
        let clock = ContinuousClock()
        let totalStart = clock.now
        try Task.checkCancellation()
        guard mode == .live,
            let vault = assignment.vault(for: slot),
            let repository = dependencies.repositories[vault.id],
            let sourceCatalog = dependencies.sourceCatalogs[vault.id]
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

        let sourceSnapshot = try await sourceCatalog.snapshot(
            refreshFolders: false,
            consumePendingMeasurement: true
        )
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
            let recovery = try await dependencies.identityRecoveryCoordinator.reconcile(
                vaultID: vault.id,
                documents: projections.map { ($0.relativePath, $0.fingerprint) },
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
        } catch {
            identityHealthIssues.append(
                "Portable note identity for \(vault.name): \(error.localizedDescription)"
            )
        }
        let identityProjectionDuration = identityProjectionStart.duration(to: clock.now)
        try Task.checkCancellation()

        let assemblyStart = clock.now
        let stableNoteIDs: [VaultQualifiedNoteID: UUID] = Dictionary(
            uniqueKeysWithValues: identityStates.compactMap { path, state in
                guard case .resolved(let noteID) = state else { return nil }
                return (
                    VaultQualifiedNoteID(vaultID: vault.id, relativePath: path),
                    noteID
                )
            }
        )
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: [vault],
            projections: [vault.id: projections],
            graph: nil,
            identityAmbiguitiesByVault: [vault.id: identityRecovery.ambiguities],
            stableNoteIDs: stableNoteIDs,
        )
        let vaultSnapshot = WorkspaceVaultSnapshot(
            slot: slot,
            vault: vault,
            pathComparisonPolicy: pathComparisonPolicy,
            documents: try projections.map { projection in
                guard
                    let fileMetadata = sourceSnapshot.fileMetadata[
                        projection.relativePath
                    ]
                else {
                    throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                }
                return WorkspaceNoteSummary(
                    id: VaultQualifiedNoteID(
                        vaultID: vault.id,
                        relativePath: projection.relativePath
                    ),
                    vaultRole: vault.role,
                    stableIdentity: identityStates[projection.relativePath] ?? .unresolved,
                    fingerprint: projection.fingerprint,
                    fileMetadata: fileMetadata,
                    graphCounts: WorkspaceGraphCounts(
                        incoming: 0,
                        outgoing: 0,
                        broken: 0,
                        ambiguous: 0
                    ),
                    linkCatalog: projection.linkCatalog,
                    title: projection.title,
                    validationWarnings: projection.validationWarnings,
                    propertyTextValues: projection.propertyTextValues,
                    canonicalAliases: projection.canonicalAliases,
                    canonicalKeywords: projection.canonicalKeywords
                )
            },
            folders: sourceSnapshot.folders,
            identityRecovery: identityRecovery
        )
        let snapshot = WorkspaceSnapshot(
            triptych: assignment.triptych,
            mode: mode,
            phase: .opening(availableVault: slot),
            generatedAt: Date(),
            vaults: [vaultSnapshot],
            discovery: WorkspaceDiscoverySnapshot(
                catalog: catalog,
                searchGeneration: nil
            ),
            research: WorkspaceResearchSnapshot(
                healthIssues: identityHealthIssues
            )
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
                researchStateDuration: .zero,
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
                let sourceCatalog = dependencies.sourceCatalogs[vault.id]
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
                    catalog: sourceCatalog
                ))
        }

        let loadedSources = try await withThrowingTaskGroup(
            of: LoadedSource.self
        ) { group in
            for input in sourceInputs {
                group.addTask {
                    try Task.checkCancellation()
                    // Each catalog is an independent rebuildable projection.
                    // The refresh coordinator still owns one atomic cycle;
                    // only preparation of the three immutable generations
                    // overlaps.
                    return LoadedSource(
                        input: input,
                        snapshot: try await input.catalog.snapshot(
                            refreshFolders: false,
                            consumePendingMeasurement: true
                        )
                    )
                }
            }
            var loaded: [LoadedSource] = []
            for try await source in group {
                loaded.append(source)
            }
            return loaded.sorted { $0.input.order < $1.input.order }
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
                let recovery = try await dependencies.identityRecoveryCoordinator.reconcile(
                    vaultID: vault.id,
                    documents: projections.map { ($0.relativePath, $0.fingerprint) },
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

        let researchStateStart = clock.now
        let settlementListing = try await dependencies.settlementStore.listing()
        let settlements = settlementListing.settlements
        let researchStateDuration = researchStateStart.duration(to: clock.now)
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
        let projectionsByVault = Dictionary(
            uniqueKeysWithValues: loadedVaults.map {
                ($0.vault.id, $0.projections)
            }
        )
        let stableNoteIDPairs: [(VaultQualifiedNoteID, UUID)] = loadedVaults.flatMap { loaded in
            loaded.identityStates.compactMap { relativePath, state -> (VaultQualifiedNoteID, UUID)? in
                guard case .resolved(let noteID) = state else { return nil }
                return (
                    VaultQualifiedNoteID(
                        vaultID: loaded.vault.id,
                        relativePath: relativePath
                    ),
                    noteID
                )
            }
        }
        let stableNoteIDs = Dictionary(uniqueKeysWithValues: stableNoteIDPairs)
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: loadedVaults.map(\.vault),
            projections: projectionsByVault,
            graph: graph,
            stableNoteIDs: stableNoteIDs,
        )

        var healthIssues: [String] = []
        healthIssues.append(contentsOf: loadedVaults.flatMap(\.identityHealthIssues))
        if let graphBuildIssue { healthIssues.append(graphBuildIssue) }
        healthIssues.append(
            contentsOf: settlementListing.issues.map {
                "Settlement \($0.fileName): \($0.reason)"
            })
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

        let vaultSnapshots = try loadedVaults.map { loaded in
            WorkspaceVaultSnapshot(
                slot: loaded.slot,
                vault: loaded.vault,
                pathComparisonPolicy: loaded.pathComparisonPolicy,
                documents: try loaded.projections.map { projection in
                    let id = VaultQualifiedNoteID(
                        vaultID: loaded.vault.id,
                        relativePath: projection.relativePath
                    )
                    guard
                        let fileMetadata = loaded.fileMetadata[
                            projection.relativePath
                        ]
                    else {
                        throw ScholiumApplicationError.incompleteTriptych(
                            assignment.id
                        )
                    }
                    let diagnostics = (graph?.diagnostics ?? []).filter { $0.source == id }
                    return WorkspaceNoteSummary(
                        id: id,
                        vaultRole: loaded.vault.role,
                        stableIdentity: loaded.identityStates[projection.relativePath] ?? .unresolved,
                        fingerprint: projection.fingerprint,
                        fileMetadata: fileMetadata,
                        graphCounts: WorkspaceGraphCounts(
                            incoming: graph?.incoming[id]?.count ?? 0,
                            outgoing: graph?.outgoing[id]?.count ?? 0,
                            broken: diagnostics.count { $0.code == .broken },
                            ambiguous: diagnostics.count {
                                $0.code == .ambiguous || $0.code == .ambiguousHeading || $0.code == .ambiguousBlock
                            }
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
        let settlementRequirements = settlementRequirements(
            settlements: settlements,
            catalog: catalog
        )
        let research = WorkspaceResearchSnapshot(
            settlements: settlements,
            recoveryRecords: recoveryRecords,
            settlementRequirements: settlementRequirements,
            healthIssues: Array(Set(healthIssues)).sorted()
        )
        let snapshot = WorkspaceSnapshot(
            triptych: assignment.triptych,
            mode: mode,
            generatedAt: Date(),
            vaults: vaultSnapshots,
            discovery: WorkspaceDiscoverySnapshot(
                catalog: catalog,
                searchGeneration: searchPublication.generation
            ),
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
                researchStateDuration: researchStateDuration,
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

    private static func settlementRequirements(
        settlements: [SettlementRecord],
        catalog: WorkspaceCatalogSnapshot
    ) -> [WorkspaceSettlementRequirement] {
        let settlementByNoteID = Dictionary(
            uniqueKeysWithValues: settlements.map { ($0.noteID, $0) }
        )
        return catalog.notes.compactMap { note -> WorkspaceSettlementRequirement? in
            guard let stableNoteID = note.reference.stableNoteID,
                let noteID = UUID(uuidString: stableNoteID)
            else { return nil }
            let settlement = settlementByNoteID[noteID]
            let reason: WorkspaceSettlementRequirementReason
            if let settlement,
                settlement.fingerprint != note.fingerprint
            {
                reason = .changedSinceSettlement
            } else {
                return nil
            }
            return WorkspaceSettlementRequirement(
                noteID: noteID,
                note: VaultQualifiedNoteID(
                    vaultID: note.reference.vaultID,
                    relativePath: note.reference.relativePath
                ),
                title: note.title,
                currentRevision: note.fingerprint,
                reason: reason,
                previousSettlement: settlement
            )
        }.sorted { $0.noteID.uuidString < $1.noteID.uuidString }
    }

}
