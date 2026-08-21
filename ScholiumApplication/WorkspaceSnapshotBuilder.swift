import ScholiumContracts
import Foundation
import ScholiumCore

struct WorkspaceRefreshMeasurement: Sendable {
    let workspaceGeneration: UInt64
    let enumeratedFiles: Int
    let readFiles: Int
    let parsedDocuments: Int
    let projectedDocuments: Int
    let enumerationDuration: Duration
    let readDuration: Duration
    let parseDuration: Duration
    let projectionDuration: Duration
    let identityProjectionDuration: Duration
    let graphDuration: Duration
    let researchStateDuration: Duration
    let searchDocumentProjectionDuration: Duration
    let searchDuration: Duration
    let snapshotAssemblyDuration: Duration
    let totalDuration: Duration
    let snapshotSourceBytes: Int
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
    let portableResearchRecordStore: PortableResearchRecordStore
    let localResearchExecutionStore: LocalResearchExecutionStore
    let critiqueRegistry: CritiqueRegistry
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
            portableResearchRecordStore: portableResearchRecordStore,
            localResearchExecutionStore: localResearchExecutionStore,
            critiqueRegistry: critiqueRegistry,
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
        let allDocuments: [NoteDocument]
        let activeDocuments: [NoteDocument]
        let semantics: [String: MarkdownSemanticDocument]
        let searchProjections: [String: SearchDocumentProjection]
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
              let sourceCatalog = dependencies.sourceCatalogs[vault.id] else {
            throw ScholiumApplicationError.incompleteTriptych(assignment.id)
        }

        let rootURL = await repository.vaultURL
        let pathComparisonPolicy = await repository.pathComparisonPolicy()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: rootURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw WorkspaceFileEventWatcherError.rootUnavailable(rootURL.path)
        }

        let sourceSnapshot = try await sourceCatalog.snapshot(
            refreshFolders: false,
            consumePendingMeasurement: true,
            projectionRequirement: .library
        )
        let allDocuments = sourceSnapshot.documents
        let activeDocuments = allDocuments
        let semantics = sourceSnapshot.semantics

        let identityProjectionStart = clock.now
        var identityStates = Dictionary(
            uniqueKeysWithValues: allDocuments.map {
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
                documents: allDocuments.map { ($0.relativePath, $0.fingerprint) },
                repository: repository,
                migrateCritiquePaths: slot == .output
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
        let qualifiedSemantics = Dictionary(
            uniqueKeysWithValues: activeDocuments.compactMap { document in
                semantics[document.relativePath].map {
                    (
                        VaultQualifiedNoteID(
                            vaultID: vault.id,
                            relativePath: document.relativePath
                        ),
                        $0
                    )
                }
            }
        )
        let stableNoteIDs: [VaultQualifiedNoteID: UUID] = Dictionary(
            uniqueKeysWithValues: identityStates.compactMap { path, state in
                guard case .resolved(let noteID) = state else { return nil }
                return (
                    VaultQualifiedNoteID(vaultID: vault.id, relativePath: path),
                    noteID
                )
            }
        )
        let zoteroBindingsByNoteID: [UUID: AnalysisZoteroBinding]
        if slot == .paperAnalysis {
            let bindings = try await dependencies.controlStore.zoteroBindings()
            zoteroBindingsByNoteID = Dictionary(
                uniqueKeysWithValues: bindings.bindings.map { ($0.noteID, $0) }
            )
        } else {
            zoteroBindingsByNoteID = [:]
        }
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: [vault],
            documents: [vault.id: activeDocuments],
            semanticDocuments: qualifiedSemantics,
            graph: nil,
            identityAmbiguitiesByVault: [vault.id: identityRecovery.ambiguities],
            stableNoteIDs: stableNoteIDs,
            zoteroBindingsByNoteID: zoteroBindingsByNoteID
        )
        let vaultSnapshot = WorkspaceVaultSnapshot(
            slot: slot,
            vault: vault,
            pathComparisonPolicy: pathComparisonPolicy,
            documents: try allDocuments.map { document in
                guard let fileMetadata = sourceSnapshot.fileMetadata[
                    document.relativePath
                ] else {
                    throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                }
                return WorkspaceNoteSnapshot(
                    id: VaultQualifiedNoteID(
                        vaultID: vault.id,
                        relativePath: document.relativePath
                    ),
                    vaultRole: vault.role,
                    stableIdentity: identityStates[document.relativePath] ?? .unresolved,
                    document: document,
                    fileMetadata: fileMetadata,
                    graphCounts: WorkspaceGraphCounts(
                        incoming: 0,
                        outgoing: 0,
                        broken: 0,
                        ambiguous: 0
                    ),
                    headings: semantics[document.relativePath]?.headings ?? [],
                    cachedSemanticDocument: semantics[document.relativePath],
                    cachedTitleProjection: semantics[document.relativePath].map {
                        WorkspaceNoteTitleProjection(
                            document: document,
                            vaultRole: vault.role,
                            semantic: $0
                        )
                    }
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
                finishedResearchRecordProjectionIsComplete: false,
                critiques: [],
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
                projectedDocuments: measurement.projectedDocuments,
                enumerationDuration: measurement.enumerationDuration,
                readDuration: measurement.readDuration,
                parseDuration: measurement.parseDuration,
                projectionDuration: measurement.projectionDuration,
                identityProjectionDuration: identityProjectionDuration,
                graphDuration: .zero,
                researchStateDuration: .zero,
                searchDocumentProjectionDuration: .zero,
                searchDuration: .zero,
                snapshotAssemblyDuration: assemblyDuration,
                totalDuration: totalStart.duration(to: clock.now),
                snapshotSourceBytes: snapshot.vaults
                    .flatMap { $0.documents }
                    .reduce(0) { $0 + $1.document.sourceBytes.count }
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
        var semanticDocuments: [VaultQualifiedNoteID: MarkdownSemanticDocument] = [:]
        var linkCatalog: [LinkCatalogNote] = []
        var sourceMeasurements: [VaultSourceCatalogMeasurement] = []
        var identityProjectionDuration = Duration.zero

        var sourceInputs: [SourceInput] = []
        for (order, slot) in WorkspaceVaultSlot.allCases.enumerated() {
            try Task.checkCancellation()
            guard let vault = assignment.vault(for: slot),
                  let repository = dependencies.repositories[vault.id],
                  let sourceCatalog = dependencies.sourceCatalogs[vault.id] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }
            let rootURL = await repository.vaultURL
            let pathComparisonPolicy = await repository.pathComparisonPolicy()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: rootURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                throw WorkspaceFileEventWatcherError.rootUnavailable(rootURL.path)
            }
            sourceInputs.append(SourceInput(
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
            let allDocuments = sourceSnapshot.documents
            let activeDocuments = allDocuments
            let semantics = sourceSnapshot.semantics
            for document in activeDocuments {
                try Task.checkCancellation()
                guard let semantic = semantics[document.relativePath] else {
                    throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                }
                let id = VaultQualifiedNoteID(
                    vaultID: vault.id,
                    relativePath: document.relativePath
                )
                semanticDocuments[id] = semantic
                linkCatalog.append(
                    LinkCatalogNote(
                        vaultID: vault.id,
                        document: document,
                        profile: WorkflowProfileResolver.resolve(
                            vaultRole: vault.role,
                            frontmatter: document.parsedFrontmatter,
                            relativePath: document.relativePath
                        ),
                        semantic: semantic
                    )
                )
            }
            let identityProjectionStart = clock.now
            var identityStates = Dictionary(
                uniqueKeysWithValues: allDocuments.map {
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
                    documents: allDocuments.map { ($0.relativePath, $0.fingerprint) },
                    repository: repository,
                    migrateCritiquePaths: slot == .output
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
            loadedVaults.append(
                LoadedVault(
                    slot: slot,
                    vault: vault,
                    pathComparisonPolicy: loadedSource.input.pathComparisonPolicy,
                    folders: sourceSnapshot.folders,
                    fileMetadata: sourceSnapshot.fileMetadata,
                    allDocuments: allDocuments,
                    activeDocuments: activeDocuments,
                    semantics: semantics,
                    searchProjections: sourceSnapshot.searchProjections,
                    identityStates: identityStates,
                    identityRecovery: identityRecovery,
                    identityHealthIssues: identityHealthIssues
                )
            )
            identityProjectionDuration += identityProjectionStart.duration(
                to: clock.now
            )
        }

        let sourceManifestHash = SearchSourceManifest.hash(
            loadedVaults.flatMap { loaded in
                loaded.activeDocuments.map {
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
                documents: semanticDocuments,
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
            graphBuildIssue = "Relationship graph: \(error.localizedDescription)"
        }
        let graphDuration = graphStart.duration(to: clock.now)
        let brokenNoteIDs = Set((graph?.diagnostics ?? []).compactMap { diagnostic in
            diagnostic.code == .broken ? diagnostic.source : nil
        })

        let researchStateStart = clock.now
        let portableSettlementListing = try await dependencies
            .portableResearchRecordStore.settlementListing()
        let settlements = portableSettlementListing.settlements
        let localExecutionListing = try await dependencies.localResearchExecutionStore
            .listing()
        let finishedResearchRecordListing = try await dependencies
            .portableResearchRecordStore.listing()
        let noteReviewListing = try await dependencies.portableResearchRecordStore
            .noteReviewListing()
        let activeDiscussionListing = try await dependencies
            .portableResearchRecordStore.activeDiscussions()
        let latestSettlementByNoteID = Dictionary(
            settlements.map { ($0.noteID, $0) },
            uniquingKeysWith: { lhs, rhs in
                lhs.settledAt >= rhs.settledAt ? lhs : rhs
            }
        )
        let researchStateDuration = researchStateStart.duration(to: clock.now)
        let searchDocumentProjectionStart = clock.now
        var searchDocuments: [SearchIndexDocument] = []

        for loaded in loadedVaults {
            try Task.checkCancellation()
            searchDocuments.append(contentsOf: try loaded.activeDocuments.map { document in
                let id = VaultQualifiedNoteID(
                    vaultID: loaded.vault.id,
                    relativePath: document.relativePath
                )
                guard let semantic = loaded.semantics[document.relativePath],
                      let cachedSourceProjection = loaded.searchProjections[
                          document.relativePath
                      ] else {
                    throw ScholiumApplicationError.incompleteTriptych(
                        assignment.id
                    )
                }
                let stableNoteID: String?
                if case .resolved(let noteID) = loaded.identityStates[document.relativePath] {
                    stableNoteID = noteID.uuidString.lowercased()
                } else {
                    stableNoteID = nil
                }
                return SearchIndexDocument(
                    vaultID: loaded.vault.id,
                    vaultName: loaded.vault.name,
                    vaultRole: loaded.vault.role,
                    document: document,
                    stableNoteID: stableNoteID,
                    semantic: semantic,
                    cachedSourceProjection: cachedSourceProjection,
                    hasBrokenLink: brokenNoteIDs.contains(id)
                )
            })
        }
        let searchDocumentProjectionDuration = searchDocumentProjectionStart.duration(
            to: clock.now
        )
        let searchStart = clock.now
        let searchPublication = try await dependencies.searchIndex.synchronize(
            searchDocuments,
            workspaceGeneration: workspaceGeneration
        )
        let searchDuration = searchStart.duration(to: clock.now)
        guard searchPublication.generation.sourceManifestHash == sourceManifestHash else {
            throw SearchIndexError.invalidDocuments(
                "Search and Graph were derived from different source manifests"
            )
        }

        let assemblyStart = clock.now
        let documentsByVault = Dictionary(
            uniqueKeysWithValues: loadedVaults.map {
                ($0.vault.id, $0.activeDocuments)
            }
        )
        var settlementStates: [String: WorkspaceSettlementState] = [:]
        for loaded in loadedVaults {
            for document in loaded.activeDocuments {
                guard case .resolved(let noteID) = loaded.identityStates[document.relativePath],
                      let settlement = latestSettlementByNoteID[noteID] else { continue }
                let referenceID = "\(loaded.vault.id.uuidString):\(document.relativePath)"
                let changedSinceSettled = settlement.fingerprint != document.fingerprint
                settlementStates[referenceID] = WorkspaceSettlementState(
                    settledFingerprint: settlement.fingerprint,
                    changedSinceSettled: changedSinceSettled
                )
            }
        }
        let materialChangedSinceUseAttention = Self.materialChangedSinceUseAttention(
            records: finishedResearchRecordListing.records,
            loadedVaults: loadedVaults
        )
        let zoteroBindingSnapshot = try await dependencies.controlStore.zoteroBindings()
        let zoteroBindingsByNoteID = Dictionary(
            uniqueKeysWithValues: zoteroBindingSnapshot.bindings.map { ($0.noteID, $0) }
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
            documents: documentsByVault,
            semanticDocuments: semanticDocuments,
            settlementStates: settlementStates,
            additionalAttention: materialChangedSinceUseAttention,
            graph: graph,
            stableNoteIDs: stableNoteIDs,
            zoteroBindingsByNoteID: zoteroBindingsByNoteID
        )

        var healthIssues: [String] = []
        healthIssues.append(contentsOf: loadedVaults.flatMap(\.identityHealthIssues))
        if let graphBuildIssue { healthIssues.append(graphBuildIssue) }
        healthIssues.append(contentsOf: portableSettlementListing.issues.map {
            "Portable Settlement \($0.fileName): \($0.reason)"
        })
        healthIssues.append(contentsOf: activeDiscussionListing.issues.map {
            "Active Discussion \($0.fileName): \($0.reason)"
        })
        healthIssues.append(contentsOf: finishedResearchRecordListing.issues.map {
            "Portable Research Record \($0.fileName): \($0.reason)"
        })
        if let issue = await dependencies.critiqueRegistry.healthError() {
            healthIssues.append(issue)
        }
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
               let issue = await repository.recoveryLedgerHealthDiagnostic() {
                healthIssues.append("\(loaded.vault.name): \(issue)")
            }
        }

        var critiquesByID: [UUID: CritiqueAssociation] = [:]
        if let output = loadedVaults.first(where: { $0.slot == .output }) {
            for document in output.activeDocuments {
                if let association = await dependencies.critiqueRegistry.association(
                    critiqueRelativePath: document.relativePath
                ) {
                    critiquesByID[association.id] = association
                }
                if case .resolved(let noteID) = output.identityStates[
                    document.relativePath
                ], let association = await dependencies.critiqueRegistry.association(
                    workNoteID: noteID
                ) {
                    critiquesByID[association.id] = association
                }
            }
        }

        let vaultSnapshots = try loadedVaults.map { loaded in
            WorkspaceVaultSnapshot(
                slot: loaded.slot,
                vault: loaded.vault,
                pathComparisonPolicy: loaded.pathComparisonPolicy,
                documents: try loaded.allDocuments.map { document in
                    let id = VaultQualifiedNoteID(
                        vaultID: loaded.vault.id,
                        relativePath: document.relativePath
                    )
                    guard let fileMetadata = loaded.fileMetadata[
                        document.relativePath
                    ] else {
                        throw ScholiumApplicationError.incompleteTriptych(
                            assignment.id
                        )
                    }
                    let diagnostics = (graph?.diagnostics ?? []).filter { $0.source == id }
                    return WorkspaceNoteSnapshot(
                        id: id,
                        vaultRole: loaded.vault.role,
                        stableIdentity: loaded.identityStates[document.relativePath] ?? .unresolved,
                        document: document,
                        fileMetadata: fileMetadata,
                        graphCounts: WorkspaceGraphCounts(
                            incoming: graph?.incoming[id]?.count ?? 0,
                            outgoing: graph?.outgoing[id]?.count ?? 0,
                            broken: diagnostics.count { $0.code == .broken },
                            ambiguous: diagnostics.count {
                                $0.code == .ambiguous || $0.code == .ambiguousHeading
                            }
                        ),
                        headings: loaded.semantics[
                            document.relativePath
                        ]?.headings ?? [],
                        cachedSemanticDocument: loaded.semantics[
                            document.relativePath
                        ],
                        cachedTitleProjection: loaded.semantics[
                            document.relativePath
                        ].map {
                            WorkspaceNoteTitleProjection(
                                document: document,
                                vaultRole: loaded.vault.role,
                                semantic: $0
                            )
                        }
                    )
                },
                folders: loaded.folders,
                identityRecovery: loaded.identityRecovery
            )
        }
        healthIssues.append(contentsOf: localExecutionListing.issues.map {
            "Local Research Execution \($0.fileName): \($0.reason)"
        })
        healthIssues.append(contentsOf: noteReviewListing.issues.map {
            "Note Review \($0.fileName): \($0.reason)"
        })
        let critiqueAssociations = critiquesByID.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let activities = researchActivities(
            executions: localExecutionListing.records,
            records: finishedResearchRecordListing.records
        )
        let noteReviewStates = noteReviewStates(
            records: finishedResearchRecordListing.records,
            reviews: noteReviewListing.reviews,
            loadedVaults: loadedVaults
        )
        let resultArrivals = finishedResearchRecordListing.records.compactMap {
            record -> WorkspaceResearchResultArrival? in
            guard record.kind == .action,
                  let action = record.action,
                  let originNoteID = record.primaryNoteID,
                  let fingerprint = try? record.finalizedResultFingerprint() else {
                return nil
            }
            return WorkspaceResearchResultArrival(
                runID: record.id,
                recordID: record.id,
                actionID: action.actionID,
                originNoteID: originNoteID,
                recordFingerprint: fingerprint,
                finishedAt: record.finishedAt
            )
        }.sorted {
            if $0.finishedAt != $1.finishedAt { return $0.finishedAt > $1.finishedAt }
            return $0.recordID.uuidString < $1.recordID.uuidString
        }
        let research = WorkspaceResearchSnapshot(
            settlements: settlements,
            activeDiscussions: activeDiscussionListing.issues.isEmpty
                ? activeDiscussionListing.discussions
                : [],
            finishedResearchRecords: finishedResearchRecordListing.records,
            finishedResearchRecordFingerprints: Dictionary(
                uniqueKeysWithValues: finishedResearchRecordListing.revisions.map {
                    ($0.record.id, $0.fingerprint)
                }
            ),
            finishedResearchRecordSourceManifestHash:
                finishedResearchRecordListing.sourceManifestHash,
            finishedResearchRecordProjectionIsComplete:
                finishedResearchRecordListing.issues.isEmpty,
            critiques: critiqueAssociations,
            recoveryRecords: recoveryRecords,
            activities: activities,
            noteReviews: noteReviewListing.reviews,
            noteReviewStates: noteReviewStates,
            resultArrivals: resultArrivals,
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
                projectedDocuments: sourceMeasurements.reduce(0) {
                    $0 + $1.projectedDocuments
                },
                enumerationDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.enumerationDuration
                },
                readDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.readDuration
                },
                parseDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.parseDuration
                },
                projectionDuration: sourceMeasurements.reduce(.zero) {
                    $0 + $1.projectionDuration
                },
                identityProjectionDuration: identityProjectionDuration,
                graphDuration: graphDuration,
                researchStateDuration: researchStateDuration,
                searchDocumentProjectionDuration:
                    searchDocumentProjectionDuration,
                searchDuration: searchDuration,
                snapshotAssemblyDuration: assemblyDuration,
                totalDuration: totalStart.duration(to: clock.now),
                snapshotSourceBytes: snapshot.vaults
                    .flatMap(\.documents)
                    .reduce(0) { $0 + $1.document.sourceBytes.count }
            )
        )
    }

    private struct CurrentAttentionNote {
        let noteID: UUID
        let reference: VaultNoteReference
        let role: ResearchActionTargetRole
        let fingerprint: DocumentFingerprint
    }

    private struct MaterialUseKey: Hashable {
        let topicNoteID: UUID
        let materialNoteID: UUID
    }

    private struct RecordedMaterialUse {
        let record: PortableResearchRecord
        let material: PortableResearchMaterialUse
    }

    /// Selects the same one current portable-use fact for snapshot derivation
    /// and click-time revalidation. Tombstones and internally inconsistent
    /// participant/material pairs never qualify as validated use evidence.
    private static func latestSynthesisMaterialUses(
        records: [PortableResearchRecord]
    ) -> [MaterialUseKey: RecordedMaterialUse] {
        let recordsByID = Dictionary(
            uniqueKeysWithValues: records.map { ($0.id, $0) }
        )
        func descends(
            _ record: PortableResearchRecord,
            from ancestorID: UUID
        ) -> Bool {
            var current = record
            var visited: Set<UUID> = []
            while let lineage = current.continuationLineage,
                  lineage.kind == .resynthesis,
                  visited.insert(current.id).inserted {
                if lineage.parentRunID == ancestorID { return true }
                guard let parent = recordsByID[lineage.parentRunID] else {
                    return false
                }
                current = parent
            }
            return false
        }
        var latestByUse: [MaterialUseKey: RecordedMaterialUse] = [:]
        for record in records where record.kind == .action
            && record.action?.actionID == .synthesize {
            guard let topicNoteID = record.primaryNoteID,
                  record.participatingNotes.contains(where: {
                      $0.noteID == topicNoteID
                          && $0.role == .topic
                  }) else { continue }
            let participantsByID = Dictionary(
                uniqueKeysWithValues: record.participatingNotes.map {
                    ($0.noteID, $0)
                }
            )
            for material in record.actuallyUsedMaterials where material.role == .analysis {
                guard let participant = participantsByID[material.noteID],
                      participant.role == .analysis,
                      participant.note == material.note,
                      participant.title == material.title,
                      participant.startingRevision == material.revision else {
                    continue
                }
                let key = MaterialUseKey(
                    topicNoteID: topicNoteID,
                    materialNoteID: material.noteID
                )
                if let existing = latestByUse[key] {
                    let candidateSupersedesExisting = descends(
                        record,
                        from: existing.record.id
                    )
                    let existingSupersedesCandidate = descends(
                        existing.record,
                        from: record.id
                    )
                    if existingSupersedesCandidate
                        || (!candidateSupersedesExisting
                            && (existing.record.finishedAt > record.finishedAt
                                || (existing.record.finishedAt == record.finishedAt
                                    && existing.record.id.uuidString
                                        < record.id.uuidString))) {
                        continue
                    }
                }
                latestByUse[key] = RecordedMaterialUse(
                    record: record,
                    material: material
                )
            }
        }
        return latestByUse
    }

    static func isLatestSynthesisMaterialUse(
        recordID: UUID,
        topicNoteID: UUID,
        materialNoteID: UUID,
        records: [PortableResearchRecord]
    ) -> Bool {
        latestSynthesisMaterialUses(records: records)[MaterialUseKey(
            topicNoteID: topicNoteID,
            materialNoteID: materialNoteID
        )]?.record.id == recordID
    }

    private static func researchActivities(
        executions: [LocalResearchExecutionRecord],
        records: [PortableResearchRecord]
    ) -> [WorkspaceResearchActivity] {
        let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        return executions.compactMap { execution in
            guard let action = execution.snapshot.actionSnapshot,
                  action.actionID != .discuss else { return nil }
            let record = recordsByID[execution.id]
            if record != nil { return nil }
            let entryStates = execution.boundedWriteSet.entries.map(\.state)
            let state: WorkspaceResearchActivityState
            let repairReason: WorkspaceResearchActivityRepairReason?

            if entryStates.contains(.recoveryRequired) {
                state = .needsAttention
                repairReason = .recoveryRequired
            } else if entryStates.contains(.conflict) {
                state = .needsAttention
                repairReason = .sourceConflict
            } else if entryStates.contains(.stale)
                || execution.completion?.state == .stale {
                state = .needsAttention
                repairReason = .sourceChanged
            } else if execution.completion.map({
                [.complete, .unverified].contains($0.state)
            }) == true {
                state = .needsAttention
                repairReason = .recordUnavailable
            } else if execution.completion?.state == .cancelled {
                return nil
            } else if !execution.documentWriteRecords.isEmpty
                || execution.resultPayload != nil {
                state = .running
                repairReason = nil
            } else {
                state = .waitingForAgent
                repairReason = nil
            }

            let updatedAt = execution.documentWriteRecords.reduce(
                execution.snapshot.preparedAt
            ) { latest, write in
                max(latest, write.finishedAt ?? write.startedAt)
            }
            return WorkspaceResearchActivity(
                runID: execution.id,
                actionID: action.actionID,
                targetNoteID: action.target.noteID,
                state: state,
                repairReason: repairReason,
                updatedAt: max(updatedAt, execution.completion?.completedAt ?? updatedAt)
            )
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.runID.uuidString < $1.runID.uuidString
        }
    }

    private static func noteReviewStates(
        records: [PortableResearchRecord],
        reviews: [PortableResearchNoteReview],
        loadedVaults: [LoadedVault]
    ) -> [WorkspaceNoteReviewState] {
        var currentRevisions: [UUID: DocumentFingerprint] = [:]
        for loaded in loadedVaults {
            for document in loaded.activeDocuments {
                guard case .resolved(let noteID) = loaded.identityStates[
                    document.relativePath
                ] else { continue }
                currentRevisions[noteID] = document.fingerprint
            }
        }
        let reviewByNoteID = Dictionary(
            uniqueKeysWithValues: reviews.map { ($0.noteID, $0) }
        )
        var activitiesByNoteID: [UUID: [PortableResearchNoteActivityReference]] = [:]
        for record in records {
            for change in record.confirmedChanges {
                activitiesByNoteID[change.noteID, default: []].append(
                    PortableResearchNoteActivityReference(
                        recordID: record.id,
                        noteID: change.noteID
                    )
                )
            }
        }
        let noteIDs = Set(currentRevisions.keys)
            .union(activitiesByNoteID.keys)
            .union(reviewByNoteID.keys)
        return noteIDs.map { noteID in
            let review = reviewByNoteID[noteID]
            let covered = Set(review?.coveredActivities ?? [])
            let pending = (activitiesByNoteID[noteID] ?? [])
                .filter { !covered.contains($0) }
                .sorted { $0.recordID.uuidString < $1.recordID.uuidString }
            let status: WorkspaceNoteReviewStatus
            if !pending.isEmpty {
                status = .needsReview
            } else if review != nil {
                status = .noAgentChangesAwaitingReview
            } else {
                status = .noAgentChangesToReview
            }
            return WorkspaceNoteReviewState(
                noteID: noteID,
                currentRevision: currentRevisions[noteID],
                status: status,
                pendingActivities: pending,
                lastReviewedAt: review?.reviewedAt,
                lastReviewedRevision: review?.observedRevision
            )
        }.sorted { $0.noteID.uuidString < $1.noteID.uuidString }
    }

    /// Rebuilds the latest completed Synthesize use relationship for each
    /// Topic/Analysis pair. Selected-but-unused, deleted, tombstoned, or
    /// identity-unresolved Materials cannot create a condition.
    private static func materialChangedSinceUseAttention(
        records: [PortableResearchRecord],
        loadedVaults: [LoadedVault]
    ) -> [AttentionQueueItem] {
        var currentByNoteID: [UUID: CurrentAttentionNote] = [:]
        for loaded in loadedVaults {
            guard let functionRole = ResearchFunctionTargetRole(
                vaultRole: loaded.vault.role
            ) else {
                continue
            }
            let role: ResearchActionTargetRole = switch functionRole {
            case .analysis: .analysis
            case .topic: .topic
            case .work: .work
            }
            for document in loaded.activeDocuments {
                guard case .resolved(let noteID) = loaded.identityStates[
                    document.relativePath
                ] else { continue }
                currentByNoteID[noteID] = CurrentAttentionNote(
                    noteID: noteID,
                    reference: VaultNoteReference(
                        vaultID: loaded.vault.id,
                        vaultName: loaded.vault.name,
                        vaultRole: loaded.vault.role,
                        relativePath: document.relativePath,
                        stableNoteID: noteID.uuidString.lowercased()
                    ),
                    role: role,
                    fingerprint: document.fingerprint
                )
            }
        }

        let latestByUse = latestSynthesisMaterialUses(records: records)

        return latestByUse.compactMap { key, use in
            guard let topic = currentByNoteID[key.topicNoteID],
                  topic.role == .topic,
                  let material = currentByNoteID[key.materialNoteID],
                  material.role == .analysis,
                  material.fingerprint != use.material.revision else {
                return nil
            }
            let context = MaterialChangedSinceUseAttentionContext(
                triptychID: use.record.triptychID,
                recordID: use.record.id,
                topicNoteID: topic.noteID,
                materialNoteID: material.noteID,
                material: material.reference,
                recordedRevision: use.material.revision,
                currentRevision: material.fingerprint
            )
            return AttentionQueueItem(
                kind: .materialChangedSinceUse,
                severity: .warning,
                note: topic.reference,
                message: "Used Analysis changed after Synthesize",
                materialChangedSinceUse: context
            )
        }.sorted { $0.id < $1.id }
    }

}
