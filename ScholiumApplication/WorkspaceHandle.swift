import ScholiumContracts
import Foundation
import ScholiumCore

enum WorkspaceAccessConfiguration: Sendable {
    case live(
        portableControlAccessRegistry: PortableControlAccessRegistry
    )
    case snapshot
}

struct WorkspaceServices: Sendable {
    let manifest: TriptychManifest
    let repositories: [UUID: VaultRepository]
    let searchIndex: TriptychSearchIndex
    let controlStore: TriptychControlStore
    let researchSkillStore: ResearchSkillStore
    let researchSkillMaintenanceStore: ResearchSkillMaintenanceStore
    let recommendedBibliographyStore: RecommendedBibliographyStore
    let zotero: ZoteroOperations
    let humanReviewStore: HumanReviewStore
    let dialogueStore: DialogueStore
    let critiqueRegistry: CritiqueRegistry
    let checkpointStore: TriptychCheckpointStore
    let transactionRecoveryStore: TriptychMutationRecoveryStore
    let identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator
    let roots: TriptychRoots
}

struct WorkspaceWatcherReadinessEvidence: Equatable, Sendable {
    let watchedVaultIDs: Set<UUID>
    let activationReconciliationCompleted: Bool
}

private struct SecurityScopeLease: Sendable {
    let url: URL
    let started: Bool
}

private struct OwnedRefreshTask: Sendable {
    let token: UUID
    let task: Task<Void, Never>
}

enum RefreshPublication: Sendable {
    case sourceCommitted(VaultQualifiedNoteID, WorkspaceSourceCommitKind)
    case explicit
    case liveInventory
    case researchRecords
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
            return .stale(WorkspaceDerivedRefreshIssue(
                reason: "The authoritative mutation committed, but derived workspace refresh failed: \(error.localizedDescription)",
                affectedVaultIDs: affectedVaultIDs,
                lastKnownGood: evidence
            ))
        case .failed(let affectedVaultIDs):
            return .failed(WorkspaceDerivedRefreshIssue(
                reason: "Derived workspace refresh failed: \(error.localizedDescription)",
                affectedVaultIDs: affectedVaultIDs,
                lastKnownGood: evidence
            ))
        }
    }
}

/// Per-Triptych application boundary shared by every consumer of a runtime.
/// The actor borrows the runtime's identity-pooled vault authorities and owns
/// only the Triptych-level composition, snapshots, and publication lifetime.
public actor WorkspaceHandle {
    public nonisolated let id: UUID
    public nonisolated let runtimeIdentity: TriptychRuntimeIdentity
    public nonisolated let assignment: TriptychAssignment
    public nonisolated let mode: WorkspaceConfigurationMode
    public nonisolated let events: WorkspaceEventSource
    public nonisolated let documents: DocumentOperations
    public nonisolated let discovery: DiscoveryOperations
    public nonisolated let research: ResearchOperations

    let services: WorkspaceServices
    private let leases: [SecurityScopeLease]
    var currentSnapshot: WorkspaceSnapshot
    private var nextGraphGeneration = 2
    private var refreshRequest: UInt64 = 0
    private var appliedRefreshRequest: UInt64 = 0
    private var derivedStateRequiresRefresh = false
    private var isShutDown = false
    private var liveWatcherTask: Task<Void, Never>?
    private var liveIndexRefreshTask: OwnedRefreshTask?
    private var pendingLiveEvents: [UUID: VaultWatchEventJournal] = [:]
    private var didCompleteActivationReconciliation = false

    private init(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        services: WorkspaceServices,
        leases: [SecurityScopeLease],
        initialSnapshot: WorkspaceSnapshot,
        documents: DocumentOperations,
        discovery: DiscoveryOperations,
        research: ResearchOperations
    ) {
        id = assignment.id
        runtimeIdentity = TriptychRuntimeIdentity(
            triptychID: assignment.id,
            activationID: UUID()
        )
        self.assignment = assignment
        self.mode = mode
        self.services = services
        self.leases = leases
        currentSnapshot = initialSnapshot
        self.documents = documents
        self.discovery = discovery
        self.research = research
        events = WorkspaceEventSource(initialSnapshot: initialSnapshot)
    }

    static func open(
        assignment: TriptychAssignment,
        mode: WorkspaceConfigurationMode,
        applicationSupportURL: URL,
        windowSessionStore: WindowSessionSnapshotStore,
        vaultPool: WorkspaceVaultPool,
        zotero: ZoteroOperations,
        access: WorkspaceAccessConfiguration
    ) async throws -> WorkspaceHandle {
        try Task.checkCancellation()
        guard Set(assignment.vaults.keys) == Set(WorkspaceVaultSlot.allCases) else {
            throw ScholiumApplicationError.incompleteTriptych(assignment.id)
        }

        var leases: [SecurityScopeLease] = []
        do {
            var repositories: [UUID: VaultRepository] = [:]
            var resolvedURLs: [WorkspaceVaultSlot: URL] = [:]
            var pooledVaults: [UUID: PooledWorkspaceVault] = [:]

            for slot in WorkspaceVaultSlot.allCases {
                try Task.checkCancellation()
                guard let vault = assignment.vault(for: slot) else {
                    throw ScholiumApplicationError.incompleteTriptych(assignment.id)
                }
                let pooled = try await vaultPool.vault(for: vault)
                repositories[vault.id] = pooled.repository
                pooledVaults[vault.id] = pooled
                resolvedURLs[slot] = pooled.rootURL
            }

            guard let worksVault = assignment.vault(for: .output),
                  let worksURL = resolvedURLs[.output],
                  let analysesURL = resolvedURLs[.paperAnalysis],
                  let topicsURL = resolvedURLs[.topicKnowledge] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }

            if case .live(let portableRegistry) = access {
                let portable = try await resolvePortableControlAccess(
                    worksVault: worksVault,
                    registry: portableRegistry
                )
                leases.append(portable)
            }

            let controlStore = TriptychControlStore(worksVaultURL: worksURL)
            let controlURL = await controlStore.controlURL
            let manifestURL = controlURL.appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                let existing = try await controlStore.manifest()
                guard existing.id == assignment.id else {
                    throw ScholiumApplicationError.manifestIdentityMismatch(
                        expected: assignment.id,
                        actual: existing.id
                    )
                }
            }

            let vaultIDs = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map {
                ($0, assignment.triptych.vaultID(for: $0))
            })
            let manifest = try await controlStore.bootstrap(
                vaultIDs: vaultIDs,
                preferredTriptychID: assignment.id
            )
            guard manifest.id == assignment.id else {
                throw ScholiumApplicationError.manifestIdentityMismatch(
                    expected: assignment.id,
                    actual: manifest.id
                )
            }

            let openedSearchIndex = try TriptychSearchIndex.openRecovering(
                databaseURL: TriptychSearchIndex.databaseURL(
                    applicationSupportURL: applicationSupportURL,
                    triptychID: manifest.id
                ),
                triptychID: manifest.id,
                vaults: Array(assignment.vaults.values)
            )

            let triptychStorage = applicationSupportURL
                .appendingPathComponent("Triptychs", isDirectory: true)
                .appendingPathComponent(manifest.id.uuidString, isDirectory: true)
            let humanReviewStore = HumanReviewStore(
                storageURL: triptychStorage.appendingPathComponent(
                    "human-review",
                    isDirectory: true
                )
            )
            let dialogueStore = DialogueStore(
                storageURL: triptychStorage.appendingPathComponent(
                    "dialogue",
                    isDirectory: true
                )
            )
            let critiqueRegistry = CritiqueRegistry(controlURL: controlURL)
            let transactionRecoveryStore = try TriptychMutationRecoveryStore(
                storageURL: triptychStorage.appendingPathComponent(
                    "transactions",
                    isDirectory: true
                )
            )
            let researchSkillStore = ResearchSkillStore(controlURL: controlURL)
            let researchSkillMaintenanceStore = ResearchSkillMaintenanceStore(
                skillStore: researchSkillStore,
                snapshotRootURL: triptychStorage
                    .appendingPathComponent("research-guidance", isDirectory: true)
                    .appendingPathComponent("skill-snapshots", isDirectory: true)
            )
            let services = WorkspaceServices(
                manifest: manifest,
                repositories: repositories,
                searchIndex: openedSearchIndex.index,
                controlStore: controlStore,
                researchSkillStore: researchSkillStore,
                researchSkillMaintenanceStore: researchSkillMaintenanceStore,
                recommendedBibliographyStore: RecommendedBibliographyStore(
                    controlURL: controlURL
                ),
                zotero: zotero,
                humanReviewStore: humanReviewStore,
                dialogueStore: dialogueStore,
                critiqueRegistry: critiqueRegistry,
                checkpointStore: TriptychCheckpointStore(
                    triptychID: manifest.id,
                    applicationSupportURL: applicationSupportURL
                ),
                transactionRecoveryStore: transactionRecoveryStore,
                identityRecoveryCoordinator: NoteIdentityRecoveryCoordinator(
                    control: controlStore,
                    humanReviews: humanReviewStore,
                    dialogue: dialogueStore,
                    critiques: critiqueRegistry,
                    windowSessions: windowSessionStore
                ),
                roots: TriptychRoots(
                    analyses: analysesURL,
                    topics: topicsURL,
                    works: worksURL,
                    control: controlURL
                )
            )
            var watcherStreams: [UUID: AsyncStream<VaultWatchEvent>] = [:]
            if mode == .live {
                for (vaultID, pooled) in pooledVaults {
                    watcherStreams[vaultID] = await pooled.events()
                }
            }
            // Native observation is live before either inventory pass. The
            // buffered stream plus the post-publication reconciliation closes
            // edits that race either scan.
            let preOpenInventory = mode == .live
                ? try await sourceInventory(
                    assignment: assignment,
                    repositories: services.repositories
                )
                : nil
            let initialSnapshot = try await WorkspaceSnapshotBuilder.build(
                assignment: assignment,
                mode: mode,
                services: services,
                graphGeneration: 1
            )
            try Task.checkCancellation()
            let reference = WorkspaceHandleReference(workspaceID: assignment.id)
            let documentOperations = DocumentOperations(reference: reference)
            let discoveryOperations = DiscoveryOperations(reference: reference)
            let researchOperations = ResearchOperations(
                reference: reference,
                skillsURL: services.researchSkillStore.skillsURL,
                recoveryRecordsURL: services.transactionRecoveryStore.storageURL
            )
            let handle = WorkspaceHandle(
                assignment: assignment,
                mode: mode,
                services: services,
                leases: leases,
                initialSnapshot: initialSnapshot,
                documents: documentOperations,
                discovery: discoveryOperations,
                research: researchOperations
            )
            await reference.bind(handle)
            if case .live = access {
                await handle.startLiveTasks(
                    streams: watcherStreams,
                    preOpenInventory: preOpenInventory ?? [:]
                )
            }
            return handle
        } catch {
            for lease in leases.reversed() where lease.started {
                lease.url.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    public func snapshot() throws -> WorkspaceSnapshot {
        try requireActive()
        return currentSnapshot
    }

    func documentPreviewCatalog(
        source: VaultQualifiedNoteID,
        sourceFingerprint: DocumentFingerprint,
        graphGeneration: Int
    ) throws -> DocumentPreviewCatalog {
        try requireActive()
        guard let graph = currentSnapshot.discovery.catalog.graph,
              graph.generation == graphGeneration,
              let sourceDocument = currentSnapshot.document(id: source)?.document,
              sourceDocument.fingerprint == sourceFingerprint else {
            return DocumentPreviewCatalog(
                graphGeneration: graphGeneration,
                source: source,
                sourceFingerprint: sourceFingerprint,
                links: []
            )
        }
        let targetIDs = Set((graph.outgoing[source] ?? []).compactMap {
            $0.destination?.note
        })
        let targetDocuments = Dictionary(uniqueKeysWithValues: targetIDs.compactMap { id in
            currentSnapshot.document(id: id).map { (id, $0.document) }
        })
        return DocumentPreviewCatalogBuilder.build(
            source: source,
            sourceFingerprint: sourceFingerprint,
            graph: graph,
            documents: targetDocuments
        )
    }

    public func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        let watcher = liveWatcherTask
        let refresh = liveIndexRefreshTask?.task
        liveWatcherTask = nil
        liveIndexRefreshTask = nil
        pendingLiveEvents.removeAll()
        watcher?.cancel()
        refresh?.cancel()
        await watcher?.value
        await refresh?.value
        await events.finish(finalSnapshot: currentSnapshot)
        for lease in leases.reversed() where lease.started {
            lease.url.stopAccessingSecurityScopedResource()
        }
    }

    func loadDocument(_ id: VaultQualifiedNoteID) async throws -> NoteDocument {
        try requireActive()
        let repository = try repository(vaultID: id.vaultID)
        return try await repository.load(relativePath: id.relativePath)
    }

    func loadUnclassifiedDocument(relativePath: String) async throws -> NoteDocument {
        try requireActive()
        return try await services.controlStore.loadUnclassified(relativePath: relativePath)
    }

    func unclassifiedDocuments() async throws -> [NoteDocument] {
        try requireActive()
        return try await services.controlStore.unclassifiedDocuments()
    }

    func importUnclassifiedMarkdown(at sourceURL: URL) async throws -> URL {
        try requireActive()
        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if secured { sourceURL.stopAccessingSecurityScopedResource() }
        }
        return try await services.controlStore.importMarkdown(at: sourceURL)
    }

    func saveUnclassifiedDocument(
        relativePath: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteDocument {
        try requireActive()
        return try await services.controlStore.saveUnclassified(
            relativePath: relativePath,
            content: source,
            expectedRevision: expectedRevision
        )
    }

    func createDocument(
        _ id: VaultQualifiedNoteID,
        content: String
    ) async throws -> NoteDocument {
        try requireActive()
        let repository = try repository(vaultID: id.vaultID)
        let registeredVault = try vault(id: id.vaultID)
        if registeredVault.role.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(id.relativePath) {
            throw CritiquePlacementError.directCreationRequiresRequestCritique
        }

        let document = try await repository.create(
            relativePath: id.relativePath,
            content: content
        )
        do {
            _ = try await services.controlStore.identity(
                forVaultID: id.vaultID,
                relativePath: id.relativePath,
                fingerprint: document.fingerprint
            )
        } catch {
            try? await repository.removeCreatedFileForRollback(
                relativePath: id.relativePath,
                createdRevision: document.fingerprint
            )
            throw error
        }
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                document.fingerprint,
                error.localizedDescription
            )
        }
        return document
    }

    func createDocument(_ request: DocumentCreationRequest) async throws -> NoteDocument {
        try requireActive()
        let registeredVault = try vault(id: request.id.vaultID)
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let researchStatus: AnalysisResearchStatusChoice = request.analysisResearchStatus

        let scope: String?
        let limitations: [String]
        switch researchStatus {
        case .declareNow(let proposedScope, let proposedLimitations):
            scope = proposedScope.trimmingCharacters(in: .whitespacesAndNewlines)
            limitations = proposedLimitations
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        case .notYet:
            scope = nil
            limitations = []
        }

        var frontmatter: [String: YAMLValue] = [:]
        if registeredVault.role == .sourceCorpus,
           case .declareNow = researchStatus {
            var researchUnit: [String: YAMLValue] = ["scope": .string(scope ?? "")]
            if !limitations.isEmpty {
                researchUnit["limitations"] = .array(limitations.map(YAMLValue.string))
            }
            frontmatter["research_unit"] = .object(researchUnit)
        }
        let profile: SchemaProfileID = switch registeredVault.role {
        case .sourceCorpus: .analysis
        case .topicKnowledge: .topicMarkdown
        case .draftProject: .draftProject
        case .other: .genericMarkdown
        }
        let issues = PropertyContractCatalog.validate(
            frontmatter: frontmatter,
            profile: profile,
            context: .creation
        )
        guard issues.isEmpty else { throw DocumentCreationError.invalidMetadata(issues) }

        let content: String
        if registeredVault.role == .sourceCorpus, let scope, !scope.isEmpty {
            var lines = [
                "---",
                "research_unit:",
                "  scope: \(Self.yamlQuotedScalar(scope))",
            ]
            if !limitations.isEmpty {
                lines.append("  limitations:")
                lines.append(contentsOf: limitations.map {
                    "    - \(Self.yamlQuotedScalar($0))"
                })
            }
            lines.append("---")
            if !title.isEmpty { lines.append("# \(title)") }
            content = lines.joined(separator: "\n") + "\n"
        } else {
            content = title.isEmpty ? "" : "# \(title)\n"
        }
        return try await createDocument(request.id, content: content)
    }

    private static func yamlQuotedScalar(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }

    func duplicateDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteDocument {
        try requireActive()
        let repository = try repository(vaultID: id.vaultID)
        let registeredVault = try vault(id: id.vaultID)
        if registeredVault.role.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(id.relativePath) {
            throw CritiquePlacementError.duplicateNotSupported
        }
        if registeredVault.role.allowsCritique,
           CritiquePlacement.isManagedCritiquePath(destinationRelativePath) {
            throw CritiquePlacementError.directCreationRequiresRequestCritique
        }
        let identity = try await resolvedIdentity(
            for: id,
            expectedRevision: expectedRevision
        )
        let document = try await repository.duplicate(
            relativePath: id.relativePath,
            to: destinationRelativePath,
            expectedRevision: expectedRevision
        )
        do {
            _ = try await services.controlStore.duplicateIdentity(
                from: identity.id,
                to: destinationRelativePath,
                fingerprint: document.fingerprint
            )
        } catch {
            try? await repository.removeCreatedFileForRollback(
                relativePath: destinationRelativePath,
                createdRevision: document.fingerprint
            )
            throw error
        }
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                document.fingerprint,
                error.localizedDescription
            )
        }
        return document
    }

    func saveDocument(
        _ id: VaultQualifiedNoteID,
        changeSet: NoteChangeSet,
        expectedRevision: DocumentFingerprint
    ) async throws -> SaveResult {
        try requireActive()
        let repository = try repository(vaultID: id.vaultID)
        let result: SaveResult
        do {
            result = try await repository.save(
                relativePath: id.relativePath,
                changeSet: changeSet,
                expectedRevision: expectedRevision
            )
        } catch let error as VaultRepositoryError {
            guard case .commitUncertain = error else { throw error }
            let observed = try? await repository.load(relativePath: id.relativePath).fingerprint
            let state: TriptychMutationRecoveryState
            if let observed {
                state = observed == expectedRevision ? .restored : .externallyChanged
            } else {
                state = .unreadable
            }
            let record = TriptychMutationRecoveryRecord(
                triptychID: self.id,
                operation: .noteSave,
                failure: error.localizedDescription,
                files: [TriptychMutationRecoveryFile(
                    vaultID: id.vaultID,
                    path: id.relativePath,
                    role: .savedNote,
                    beforeRevision: expectedRevision,
                    intendedRevision: nil,
                    observedRevision: observed,
                    state: state,
                    detail: "The coordinated save could not prove both canonical and displaced bytes. Recovery evidence remains machine-local."
                )]
            )
            do {
                try await services.transactionRecoveryStore.record(record)
            } catch {
                throw TriptychTransactionError.recoveryPersistenceFailed(
                    record,
                    error.localizedDescription
                )
            }
            throw TriptychTransactionError.recoveryRequired(record)
        }
        do {
            _ = try await refresh(
                publication: .sourceCommitted(id, .save),
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                result.document.fingerprint,
                error.localizedDescription
            )
        }
        return result
    }

    func moveDocument(
        _ id: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        try await coordinatedMoveDocument(
            id,
            to: destinationRelativePath,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: true
        )
    }

    func setAsideDocument(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let destination = id.relativePath.hasPrefix("Set Aside/")
            ? id.relativePath
            : "Set Aside/" + id.relativePath
        return try await coordinatedMoveDocument(
            id,
            to: destination,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: false
        )
    }

    func moveDocumentToTrash(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let destination: String
        if id.relativePath.hasPrefix("Set Aside/") {
            destination = "Trash/" + id.relativePath.dropFirst("Set Aside/".count)
        } else if id.relativePath.hasPrefix("Trash/") {
            destination = id.relativePath
        } else {
            destination = "Trash/" + id.relativePath
        }
        return try await coordinatedMoveDocument(
            id,
            to: destination,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: false
        )
    }

    func putBackDocument(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> TriptychMoveCommit {
        let destination: String?
        if id.relativePath.hasPrefix("Set Aside/") {
            destination = String(id.relativePath.dropFirst("Set Aside/".count))
        } else if id.relativePath.hasPrefix("Trash/") {
            destination = String(id.relativePath.dropFirst("Trash/".count))
        } else {
            destination = nil
        }
        guard let destination, !destination.isEmpty else {
            throw VaultRepositoryError.invalidRelativePath(id.relativePath)
        }
        return try await coordinatedMoveDocument(
            id,
            to: destination,
            expectedRevision: expectedRevision,
            validatesCritiquePlacement: true
        )
    }

    func deleteDocumentPermanently(
        _ id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> PermanentDeletionCommit {
        try requireActive()
        guard id.relativePath.hasPrefix("Trash/") else {
            throw VaultRepositoryError.invalidRelativePath(id.relativePath)
        }
        let identity = try await resolvedIdentity(
            for: id,
            expectedRevision: expectedRevision
        )
        let repository = try repository(vaultID: id.vaultID)
        let coordinator = NotePermanentDeletionCoordinator(
            triptychID: services.manifest.id,
            repository: repository,
            humanReviewStore: services.humanReviewStore,
            dialogueStore: services.dialogueStore,
            critiqueRegistry: services.critiqueRegistry,
            checkpointStore: services.checkpointStore,
            controlStore: services.controlStore,
            recoveryStore: services.transactionRecoveryStore
        )
        let commit = try await coordinator.delete(
            noteID: identity.id,
            vaultID: id.vaultID,
            relativePath: id.relativePath,
            expectedRevision: expectedRevision,
            checkpointArea: try checkpointArea(vaultID: id.vaultID)
        )
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [id.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                commit.fingerprint,
                error.localizedDescription
            )
        }
        return commit
    }

    func recoverInterruptedDocumentTransactions() async -> [String] {
        guard !isShutDown else {
            return [ScholiumApplicationError.workspaceShutDown(id).localizedDescription]
        }
        var issues: [String] = []
        for (vaultID, repository) in services.repositories.sorted(by: {
            $0.key.uuidString < $1.key.uuidString
        }) {
            let coordinator = NotePermanentDeletionCoordinator(
                triptychID: services.manifest.id,
                repository: repository,
                humanReviewStore: services.humanReviewStore,
                dialogueStore: services.dialogueStore,
                critiqueRegistry: services.critiqueRegistry,
                checkpointStore: services.checkpointStore,
                controlStore: services.controlStore,
                recoveryStore: services.transactionRecoveryStore
            )
            do {
                try await coordinator.recoverInterruptedTransactions()
            } catch {
                issues.append("Vault \(vaultID.uuidString): \(error.localizedDescription)")
            }
        }
        return issues
    }

    func classifyUnclassifiedDocument(
        _ relativePath: String,
        into slot: WorkspaceVaultSlot,
        destinationRelativePath: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> UnclassifiedClassificationCommit {
        try requireActive()
        guard let destinationVault = assignment.vault(for: slot),
              let destinationRepository = services.repositories[destinationVault.id] else {
            throw ScholiumApplicationError.incompleteTriptych(assignment.id)
        }
        let source = try await services.controlStore.loadUnclassified(
            relativePath: relativePath
        )
        guard source.fingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedRevision,
                current: source.fingerprint
            )
        }
        let coordinator = UnclassifiedClassificationCoordinator(
            triptychID: services.manifest.id,
            control: services.controlStore,
            destinationVaultID: destinationVault.id,
            destinationRepository: destinationRepository,
            recoveryStore: services.transactionRecoveryStore
        )
        let commit = try await coordinator.classify(
            sourceRelativePath: relativePath,
            expectedRevision: expectedRevision,
            destinationRelativePath: destinationRelativePath
        )
        _ = try await services.controlStore.identity(
            forVaultID: destinationVault.id,
            relativePath: commit.destination.relativePath,
            fingerprint: commit.committedRevision
        )
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [destinationVault.id]
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                commit.committedRevision,
                error.localizedDescription
            )
        }
        return commit
    }

    func refresh() async throws -> WorkspaceSnapshot {
        try await refresh(publication: .explicit)
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
        )
    ) async throws -> WorkspaceSnapshot {
        try requireActive()
        refreshRequest &+= 1
        let request = refreshRequest
        let graphGeneration = nextGraphGeneration
        nextGraphGeneration &+= 1
        let snapshot: WorkspaceSnapshot
        do {
            snapshot = try await WorkspaceSnapshotBuilder.build(
                assignment: assignment,
                mode: mode,
                services: services,
                graphGeneration: graphGeneration
            )
        } catch {
            if !Task.isCancelled, !isShutDown, request > appliedRefreshRequest {
                // A newer failed attempt supersedes older in-flight results in
                // exactly the same way as a newer successful refresh.
                appliedRefreshRequest = request
                derivedStateRequiresRefresh = true
                await events.publishDerivedStateChanged(
                    snapshot: currentSnapshot,
                    status: failureDisposition.status(
                        for: error,
                        lastKnownGood: currentSnapshot
                    )
                )
            }
            throw error
        }
        try requireActive()
        guard request > appliedRefreshRequest else { return currentSnapshot }
        appliedRefreshRequest = request
        let previous = currentSnapshot
        currentSnapshot = snapshot
        let confirmsEarlierFailure = derivedStateRequiresRefresh
        derivedStateRequiresRefresh = false
        await publish(
            publication,
            previous: previous,
            snapshot: snapshot,
            confirmsEarlierFailure: confirmsEarlierFailure
        )
        return snapshot
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
        case .researchRecords:
            await events.publishResearchRecordsChanged(snapshot: snapshot)
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
                      oldLocation != newLocation else { return nil }
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

    private func sourceRevisions(
        in snapshot: WorkspaceSnapshot
    ) -> [VaultQualifiedNoteID: DocumentFingerprint] {
        Dictionary(
            uniqueKeysWithValues: snapshot.vaults.flatMap { vault in
                vault.documents.map { ($0.id, $0.fingerprint) }
            }
        )
    }

    private func startLiveTasks(
        streams: [UUID: AsyncStream<VaultWatchEvent>],
        preOpenInventory: [VaultQualifiedNoteID: DocumentFingerprint]
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
        await reconcileLiveActivation(preOpenInventory: preOpenInventory)
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
                repositories: services.repositories
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
        var journal = pendingLiveEvents[vaultID] ?? VaultWatchEventJournal(capacity: 256)
        journal.append(event)
        pendingLiveEvents[vaultID] = journal
        guard liveIndexRefreshTask == nil else { return }

        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runLiveIndexRefresh(token: token)
        }
        liveIndexRefreshTask = OwnedRefreshTask(token: token, task: task)
    }

    private func runLiveIndexRefresh(token: UUID) async {
        while !isShutDown, !pendingLiveEvents.isEmpty {
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
            if !rootChangedVaultIDs.isEmpty {
                let evidence = WorkspaceDerivedRefreshEvidence(snapshot: currentSnapshot)
                derivedStateRequiresRefresh = true
                await events.publishDerivedStateChanged(
                    snapshot: currentSnapshot,
                    status: .stale(WorkspaceDerivedRefreshIssue(
                        reason: "Native observation reported that a vault root changed. The last complete derived snapshot remains available until access is restored and a refresh succeeds.",
                        affectedVaultIDs: rootChangedVaultIDs,
                        lastKnownGood: evidence
                    ))
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
        }
    }

    private func sourceInventoryChanges(vaultIDs: Set<UUID>) async -> Set<UUID> {
        let published = sourceRevisions(in: currentSnapshot)
        var changed: Set<UUID> = []
        for vaultID in vaultIDs {
            do {
                let repository = try repository(vaultID: vaultID)
                let paths = try await repository.markdownRelativePaths(
                    includeLifecycle: true
                )
                let publishedForVault = published.filter {
                    $0.key.vaultID == vaultID
                }
                guard paths.count == publishedForVault.count else {
                    changed.insert(vaultID)
                    continue
                }
                for path in paths {
                    let id = VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: path
                    )
                    let document = try await repository.load(relativePath: path)
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

    private static func sourceInventory(
        assignment: TriptychAssignment,
        repositories: [UUID: VaultRepository]
    ) async throws -> [VaultQualifiedNoteID: DocumentFingerprint] {
        var observed: [VaultQualifiedNoteID: DocumentFingerprint] = [:]
        for slot in WorkspaceVaultSlot.allCases {
            try Task.checkCancellation()
            guard let vault = assignment.vault(for: slot),
                  let repository = repositories[vault.id] else {
                throw ScholiumApplicationError.incompleteTriptych(assignment.id)
            }
            let paths = try await repository.markdownRelativePaths(includeLifecycle: true)
            for path in paths {
                try Task.checkCancellation()
                let document = try await repository.load(relativePath: path)
                observed[VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)] =
                    document.fingerprint
            }
        }
        return observed
    }

    // Internal evidence for lifecycle tests; capabilities do not expose tasks.
    var ownedBackgroundTaskCount: Int {
        (liveWatcherTask == nil ? 0 : 1) + (liveIndexRefreshTask == nil ? 0 : 1)
    }

    var activationReconciliationCompleted: Bool {
        didCompleteActivationReconciliation
    }

    var watcherReadinessEvidence: WorkspaceWatcherReadinessEvidence? {
        guard liveWatcherTask != nil, didCompleteActivationReconciliation else { return nil }
        return WorkspaceWatcherReadinessEvidence(
            watchedVaultIDs: Set(assignment.vaults.values.map(\.id)),
            activationReconciliationCompleted: true
        )
    }

    func search(_ request: SearchRequest) async throws -> SearchResponse {
        try requireActive()
        return try await services.searchIndex.search(request)
    }

    func related(
        query: String,
        scope: SearchExecutionScope,
        searchGeneration: SearchGenerationID?,
        excluding: Set<VaultQualifiedNoteID>,
        limit: Int
    ) throws -> RelatedSearchResponse {
        try requireActive()
        let parsed = SearchQueryParser.parse(query)
        guard parsed.diagnostics.isEmpty,
              parsed.ast?.relatedIdentityNeedle != nil else {
            return RelatedSearchResponse(availability: .notApplicable)
        }
        guard let searchGeneration else {
            return RelatedSearchResponse(availability: .notApplicable)
        }
        guard currentSnapshot.discovery.searchGeneration == searchGeneration else {
            return RelatedSearchResponse(availability: .refreshing)
        }
        guard let graph = currentSnapshot.discovery.catalog.graph else {
            return RelatedSearchResponse(availability: .refreshing)
        }
        guard graph.sourceManifestHash == searchGeneration.sourceManifestHash else {
            return RelatedSearchResponse(
                availability: .stale(
                    reason: "Related connections were derived from an older source manifest."
                )
            )
        }
        return RelatedSearchResponse(
            availability: .current,
            items: currentSnapshot.discovery.catalog.relatedSearchResults(
            for: query,
            scope: scope,
            searchGeneration: currentSnapshot.discovery.searchGeneration,
            excluding: excluding,
            limit: limit
            )
        )
    }

    func researchSnapshot() throws -> WorkspaceResearchSnapshot {
        try requireActive()
        return currentSnapshot.research
    }

    func humanReview(noteID: UUID) async throws -> HumanReviewRecord? {
        try requireActive()
        return await services.humanReviewStore.record(noteID: noteID)
    }

    func dialogues(noteID: UUID) async throws -> [DialogueEntry] {
        try requireActive()
        return await services.dialogueStore.entries(noteID: noteID).filter {
            $0.functionSnapshot == nil
                || $0.functionSnapshot?.request.function == .dialogue
        }
    }

    func critique(workNoteID: UUID) async throws -> CritiqueAssociation? {
        try requireActive()
        return await services.critiqueRegistry.association(workNoteID: workNoteID)
    }

    func dialogueResponseProfile() async throws -> DialogueResponseProfile {
        try requireActive()
        return try await services.controlStore.dialogueResponseProfile()
    }

    func triptychSettings() async throws -> TriptychSettings {
        try requireActive()
        return try await services.controlStore.settings()
    }

    func saveTriptychSettings(_ settings: TriptychSettings) async throws {
        try requireActive()
        try await services.controlStore.saveSettings(settings)
        try await refreshAfterCommittedOperation(
            "The Triptych settings",
            publication: .researchRecords
        )
    }

    func saveDialogueResponseProfile(_ profile: DialogueResponseProfile) async throws {
        try requireActive()
        try await services.controlStore.saveDialogueResponseProfile(profile)
        try await refreshAfterCommittedOperation(
            "The Dialogue response profile",
            publication: .researchRecords
        )
    }

    func dialogueEntries() async throws -> [DialogueEntry] {
        try requireActive()
        if let error = await services.dialogueStore.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(error)
        }
        return await services.dialogueStore.allEntries().filter {
            $0.functionSnapshot == nil
                || $0.functionSnapshot?.request.function == .dialogue
        }
    }

    func dialogue(id: UUID) async throws -> DialogueEntry {
        try requireActive()
        if let error = await services.dialogueStore.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(error)
        }
        let entry = try await services.dialogueStore.entry(id: id)
        guard entry.functionSnapshot == nil
                || entry.functionSnapshot?.request.function == .dialogue else {
            throw DialogueError.entryNotFound(id)
        }
        return entry
    }

    func appendDialogueReply(
        _ reply: DialogueReply,
        to entryID: UUID
    ) async throws -> DialogueEntry {
        try requireActive()
        if let error = await services.dialogueStore.healthError() {
            throw ScholiumApplicationError.researchStoreUnavailable(error)
        }
        let entry = try await services.dialogueStore.appendReply(reply, to: entryID)
        try await refreshAfterCommittedOperation(
            "The Dialogue reply",
            publication: .researchRecords
        )
        return entry
    }

    func skills() async throws -> [ResearchSkillPackage] {
        try requireActive()
        return try await services.researchSkillStore.skills()
    }

    func skillCatalog() async throws -> ResearchSkillCatalog {
        try requireActive()
        return try await services.researchSkillStore.catalog()
    }

    func skillPackage(id: String) async throws -> ResearchSkillPackage {
        try requireActive()
        return try await services.researchSkillStore.package(id: id)
    }

    func createSkill(id: String, source: String) async throws -> ResearchSkillPackage {
        try requireActive()
        return try await services.researchSkillStore.create(id: id, source: source)
    }

    func duplicateBundledSkill(
        id: String,
        as newID: String
    ) async throws -> ResearchSkillPackage {
        try requireActive()
        return try await services.researchSkillStore.duplicateBundled(id: id, as: newID)
    }

    func saveSkill(
        id: String,
        source: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        try requireActive()
        return try await services.researchSkillStore.save(
            id: id,
            source: source,
            expectedRevision: expectedRevision
        )
    }

    func renameSkill(
        id: String,
        to newID: String,
        expectedRevision: DocumentFingerprint
    ) async throws -> ResearchSkillPackage {
        try requireActive()
        return try await services.researchSkillStore.rename(
            id: id,
            to: newID,
            expectedRevision: expectedRevision
        )
    }

    func deleteSkill(id: String, expectedRevision: DocumentFingerprint) async throws {
        try requireActive()
        try await services.researchSkillStore.delete(
            id: id,
            expectedRevision: expectedRevision
        )
    }

    func skillResourcePaths(id: String) async throws -> [String] {
        try requireActive()
        return try await services.researchSkillStore.resourcePaths(id: id)
    }

    func skillResource(id: String, relativePath: String) async throws -> String {
        try requireActive()
        return try await services.researchSkillStore.resource(
            id: id,
            relativePath: relativePath
        )
    }

    func skillInstructionAssembly(
        mode: ResearchSkillMode,
        requestedSkillIDs: [String],
        mixedPhases: [ResearchSkillAssemblyPhase]
    ) async throws -> String {
        try requireActive()
        return try await services.researchSkillStore.instructionAssembly(
            mode: mode,
            requestedSkillIDs: requestedSkillIDs,
            mixedPhases: mixedPhases
        )
    }

    func resolveWorkflow(
        _ contract: ResearchWorkflowContract
    ) async throws -> ResolvedResearchWorkflowEnvelope {
        try requireActive()
        return try await ResearchWorkflowAssembler.resolve(
            contract,
            store: services.researchSkillStore
        )
    }

    private func coordinatedMoveDocument(
        _ source: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint,
        validatesCritiquePlacement: Bool
    ) async throws -> TriptychMoveCommit {
        try requireActive()
        let destination = VaultQualifiedNoteID(
            vaultID: source.vaultID,
            relativePath: destinationRelativePath
        )
        let identity = try await resolvedIdentity(
            for: source,
            expectedRevision: expectedRevision
        )
        let registeredVault = try vault(id: source.vaultID)
        if validatesCritiquePlacement, registeredVault.role.allowsCritique {
            try CritiquePlacement.validateOrdinaryMove(
                from: source.relativePath,
                to: destinationRelativePath
            )
        }

        let sourceIsActive = !Self.isLifecyclePath(source.relativePath)
        let destinationIsActive = !Self.isLifecyclePath(destinationRelativePath)
        let plan: IncomingLinkRewritePlan
        let repositories: [UUID: VaultRepository]
        if sourceIsActive, destinationIsActive {
            repositories = services.repositories
            plan = try await workspaceMovePlan(moving: source, to: destination)
        } else {
            repositories = [source.vaultID: try repository(vaultID: source.vaultID)]
            plan = IncomingLinkRewritePlan(
                movedNote: source,
                destination: destination,
                graphGeneration: currentSnapshot.discovery.catalog.graph?.generation ?? 0,
                rewrites: []
            )
        }

        let coordinator = TriptychMoveCoordinator(
            triptychID: services.manifest.id,
            repositories: repositories,
            recoveryStore: services.transactionRecoveryStore
        )
        let commit = try await coordinator.move(
            plan,
            expectedRevision: expectedRevision
        )

        var identityFailure: Error?
        do {
            _ = try await services.controlStore.moveIdentity(
                id: identity.id,
                vaultID: source.vaultID,
                from: source.relativePath,
                to: destinationRelativePath,
                fingerprint: commit.committedRevision
            )
            let failures = await services.identityRecoveryCoordinator.resumePendingRebindings(
                vaultID: source.vaultID,
                repository: try repository(vaultID: source.vaultID),
                migrateCritiquePaths: assignment.vault(for: .output)?.id == source.vaultID
            )
            if let failure = failures.first(where: { $0.rebinding.noteID == identity.id }) {
                identityFailure = NoteIdentityMigrationError.incomplete(failure.message)
            }
        } catch {
            identityFailure = error
        }

        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: Set(repositories.keys)
                )
            )
        } catch {
            throw ScholiumApplicationError.committedButRefreshFailed(
                commit.committedRevision,
                error.localizedDescription
            )
        }
        if let identityFailure { throw identityFailure }
        return commit
    }

    private func workspaceMovePlan(
        moving source: VaultQualifiedNoteID,
        to destination: VaultQualifiedNoteID
    ) async throws -> IncomingLinkRewritePlan {
        var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
        for registeredVault in orderedVaults() {
            let repository = try repository(vaultID: registeredVault.id)
            for path in try await repository.markdownRelativePaths() {
                let document = try await repository.load(relativePath: path)
                documents[VaultQualifiedNoteID(
                    vaultID: registeredVault.id,
                    relativePath: path
                )] = document
            }
        }
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let catalog = documents.map { id, document in
            LinkCatalogNote(
                vaultID: id.vaultID,
                document: document,
                semantic: semantics[id]
            )
        }
        let graph = LinkGraphBuilder.build(
            generation: (currentSnapshot.discovery.catalog.graph?.generation ?? 0) + 1,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace
        )
        return IncomingLinkRewriter.plan(
            documents: documents,
            graph: graph,
            moving: source,
            to: destination
        )
    }

    func resolvedIdentity(
        for id: VaultQualifiedNoteID,
        expectedRevision: DocumentFingerprint
    ) async throws -> NoteIdentityRecord {
        let repository = try repository(vaultID: id.vaultID)
        let current = try await repository.load(relativePath: id.relativePath)
        guard current.fingerprint == expectedRevision else {
            throw VaultRepositoryError.conflict(
                expected: expectedRevision,
                current: current.fingerprint
            )
        }
        guard let note = currentSnapshot.document(id: id),
              note.fingerprint == expectedRevision,
              case .resolved(let stableID) = note.stableIdentity,
              let record = try await services.controlStore.identityRecord(
                vaultID: id.vaultID,
                relativePath: id.relativePath
              ),
              record.id == stableID else {
            throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
        }
        return record
    }

    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> NoteIdentityRecord {
        try requireActive()
        let repository = try repository(vaultID: ambiguity.vaultID)
        guard let slot = WorkspaceVaultSlot.allCases.first(where: {
            assignment.vault(for: $0)?.id == ambiguity.vaultID
        }) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(ambiguity.vaultID)
        }
        let record = try await services.identityRecoveryCoordinator.resolve(
            ambiguity,
            candidateID: candidateID,
            repository: repository,
            migrateCritiquePaths: slot == .output
        )
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [ambiguity.vaultID]
                )
            )
        } catch {
            throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                operation: "The note-identity resolution",
                reason: error.localizedDescription
            )
        }
        return record
    }

    func checkpointArea(vaultID: UUID) throws -> TriptychCheckpointArea {
        guard let slot = WorkspaceVaultSlot.allCases.first(where: {
            assignment.vault(for: $0)?.id == vaultID
        }) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        switch slot {
        case .paperAnalysis: return .analyses
        case .topicKnowledge: return .topics
        case .output: return .works
        }
    }

    private static func isLifecyclePath(_ path: String) -> Bool {
        path.hasPrefix("Set Aside/") || path.hasPrefix("Trash/")
    }

    private func orderedVaults() -> [RegisteredVault] {
        WorkspaceVaultSlot.allCases.compactMap { assignment.vault(for: $0) }
    }

    func vault(id: UUID) throws -> RegisteredVault {
        guard let vault = assignment.vaults.values.first(where: { $0.id == id }) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(id)
        }
        return vault
    }

    func repository(vaultID: UUID) throws -> VaultRepository {
        guard let repository = services.repositories[vaultID] else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        return repository
    }

    func requireActive() throws {
        if isShutDown { throw ScholiumApplicationError.workspaceShutDown(id) }
    }

    private static func resolvePortableControlAccess(
        worksVault: RegisteredVault,
        registry: PortableControlAccessRegistry
    ) async throws -> SecurityScopeLease {
        let worksURL = URL(
            fileURLWithPath: worksVault.canonicalPath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let expectedContainer = worksURL.deletingLastPathComponent()
        guard let access = await registry.access(forWorksURL: worksURL),
              access.canonicalContainerPath == expectedContainer.path else {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(
                expectedContainer.path
            )
        }

        var stale = false
        let resolved: URL
        do {
            resolved = try URL(
                resolvingBookmarkData: access.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(
                expectedContainer.path
            )
        }
        let canonical = resolved.resolvingSymlinksInPath().standardizedFileURL
        guard !stale,
              canonical.path == expectedContainer.path,
              resolved.startAccessingSecurityScopedResource() else {
            throw WorkspaceRegistryError.portableControlAccessUnavailable(
                expectedContainer.path
            )
        }
        return SecurityScopeLease(url: resolved, started: true)
    }
}
