import Foundation
import OSLog
import ScholiumContracts
import ScholiumCore

/// Builds the complete descendant identity plan from the last complete
/// Workspace generation plus durable identities committed ahead of it. Folder
/// paths have no identity of their own, so a second Folder move must follow
/// each Note identity to its current path instead of reusing stale descendants
/// from the earlier generation.
func sourceAuthorizedFolderNoteMoves(
    vaultID: UUID,
    sourceFolder: VaultRelativeFolderPath,
    destinationFolder: VaultRelativeFolderPath,
    snapshotDocuments: [WorkspaceNoteSummary],
    sourceAheadIdentityRecords: [VaultQualifiedNoteID: NoteIdentityRecord]
) throws -> [FolderNoteMovePlan] {
    let sourcePrefix = sourceFolder.rawValue + "/"
    let destinationPrefix = destinationFolder.rawValue + "/"
    let sourceAhead = try sourceAheadIdentityRecords.map { location, record in
        guard location.vaultID == record.vaultID,
            location.relativePath == record.relativePath
        else {
            throw TriptychTransactionError.invalidPlan(
                "A source-ahead identity record does not match its current location."
            )
        }
        return record
    }.filter { $0.vaultID == vaultID }
    let sourceAheadIDs = Set(sourceAhead.map(\.id))
    let sourceAheadPaths = Set(sourceAhead.map(\.relativePath))

    var authorizationByID: [UUID: (path: String, revision: DocumentFingerprint)] = [:]
    for note in snapshotDocuments where note.id.vaultID == vaultID {
        if sourceAheadPaths.contains(note.id.relativePath) { continue }
        guard let stableNoteID = note.stableIdentity.resolvedID else {
            if note.id.relativePath.hasPrefix(sourcePrefix) {
                throw NoteIdentityRecoveryError.identityUnresolved(
                    note.id.relativePath
                )
            }
            continue
        }
        guard !sourceAheadIDs.contains(stableNoteID) else { continue }
        authorizationByID[stableNoteID] = (
            path: note.id.relativePath,
            revision: note.fingerprint
        )
    }
    for record in sourceAhead {
        authorizationByID[record.id] = (
            path: record.relativePath,
            revision: record.fingerprint
        )
    }

    let descendants: [FolderNoteMovePlan] = authorizationByID.compactMap {
        stableNoteID, source -> FolderNoteMovePlan? in
        guard source.path.hasPrefix(sourcePrefix) else { return nil }
        let suffix = source.path.dropFirst(sourcePrefix.count)
        return FolderNoteMovePlan(
            stableNoteID: stableNoteID,
            source: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: source.path
            ),
            destination: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: destinationPrefix + suffix
            ),
            expectedRevision: source.revision
        )
    }.sorted { $0.source < $1.source }
    guard Set(descendants.map(\.source)).count == descendants.count else {
        throw TriptychTransactionError.invalidPlan(
            "Several stable Note identities claim the same Folder descendant."
        )
    }
    return descendants
}

extension WorkspaceHandle {
    func coordinatedMoveDocument(
        _ source: VaultQualifiedNoteID,
        to destinationRelativePath: String,
        expectedRevision: DocumentFingerprint,
        expectedStableNoteID: UUID? = nil,
        agentMove: AgentMoveAuthorization? = nil,
        undoAgentMoveID: UUID? = nil,
        admission: AgentMutationAdmission? = nil
    ) async throws -> WorkspaceMutationOutcome<TriptychMoveCommit> {
        try requireActive()
        let mutationLease = try await beginSourceMutation(admission: admission)
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let destination = VaultQualifiedNoteID(
            vaultID: source.vaultID,
            relativePath: destinationRelativePath
        )
        let identity = try await resolvedIdentity(
            for: source,
            expectedRevision: expectedRevision
        )
        try requireExpectedIdentity(
            expectedStableNoteID,
            resolved: identity.id,
            relativePath: source.relativePath
        )

        let repositories = services.repositories
        let plan: IncomingLinkRewritePlan
        if let undoAgentMoveID {
            let evidence = try await services.agentChangeStore.evidence(id: undoAgentMoveID)
            guard evidence.change.noteID == identity.id, evidence.change.state == .confirmed,
                evidence.change.afterFingerprint == expectedRevision
            else { throw AgentChangeError.undoUnavailable(undoAgentMoveID) }
            plan = try await agentMoveInverse(evidence: evidence)
            guard plan.movedNote == source && plan.destination == destination else { throw AgentChangeError.mismatchedBinding(undoAgentMoveID) }
        } else {
            plan = try await workspaceMovePlan(moving: source, to: destination)
        }

        let coordinator = TriptychMoveCoordinator(
            triptychID: services.manifest.id,
            repositories: repositories,
            recoveryStore: services.transactionRecoveryStore
        )
        var incomingIdentities: [VaultQualifiedNoteID: NoteIdentityRecord] = [:]
        for rewrite in plan.rewrites where rewrite.source != source {
            if let record = try await services.controlStore.identityRecord(
                vaultID: rewrite.source.vaultID, relativePath: rewrite.source.relativePath),
                record.fingerprint == rewrite.expectedRevision
            {
                incomingIdentities[rewrite.source] = record
            }
        }
        if let agentMove {
            try await coordinator.validate(plan, expectedRevision: expectedRevision)
            try await prepareAgentMoveEvidence(
                plan: plan, noteID: identity.id,
                expectedFingerprint: expectedRevision, authorization: agentMove)
        }
        let commit: TriptychMoveCommit
        do {
            commit = try await coordinator.move(plan, expectedRevision: expectedRevision)
        } catch {
            if let agentMove { try await finishFailedAgentMutation(changeID: agentMove.changeID, error: error) }
            throw error
        }

        var identityFailure: Error?
        var movedIdentityRecord: NoteIdentityRecord?
        do {
            movedIdentityRecord = try await services.controlStore.moveIdentity(
                id: identity.id,
                vaultID: source.vaultID,
                from: source.relativePath,
                to: destinationRelativePath,
                fingerprint: commit.committedRevision
            )
            let failures = await services.identityRecoveryCoordinator.resumePendingRebindings(
                vaultID: source.vaultID,
                repository: try repository(vaultID: source.vaultID)
            )
            if let failure = failures.first(where: { $0.rebinding.noteID == identity.id }) {
                identityFailure = NoteIdentityMigrationError.incomplete(failure.message)
            }
        } catch {
            identityFailure = error
        }

        sourceAheadIdentityRecords[source] = nil
        if identityFailure == nil, let movedIdentityRecord {
            sourceAheadIdentityRecords[destination] = movedIdentityRecord
        } else {
            sourceAheadIdentityRecords[destination] = nil
        }
        // An incoming-link edit is also an exact source commit. Publish its
        // unchanged identity with that receipt now, so the next operation does
        // not depend on the timing of the disposable background refresh.
        do {
            for rewrite in commit.rewrites where rewrite.note != destination {
                guard let before = incomingIdentities[rewrite.note], before.fingerprint == rewrite.previousRevision else {
                    throw NoteIdentityRecoveryError.identityUnresolved(rewrite.note.relativePath)
                }
                let current = try await repository(vaultID: rewrite.note.vaultID).load(relativePath: rewrite.note.relativePath)
                guard current.fingerprint == rewrite.committedRevision else {
                    throw VaultRepositoryError.conflict(expected: rewrite.committedRevision, current: current.fingerprint)
                }
                guard
                    let record = try await services.controlStore.identity(
                        forVaultID: rewrite.note.vaultID, relativePath: rewrite.note.relativePath,
                        fingerprint: rewrite.committedRevision, createIfMissing: false, preferredID: before.id,
                        expectedFingerprint: rewrite.previousRevision)
                else { throw NoteIdentityRecoveryError.identityUnresolved(rewrite.note.relativePath) }
                sourceAheadIdentityRecords[rewrite.note] = record
            }
        } catch {
            identityFailure = identityFailure ?? error
        }

        let refreshPayload = WorkspaceRefreshPayload(
            publication: .explicit,
            failureDisposition: .staleAfterCommittedMutation(
                affectedVaultIDs: Set(repositories.keys)
            ),
            sourceCatalogPreparation: Self.catalogPreparation(
                upserts: [commit.destination] + commit.rewrites.map(\.note),
                deletions: [commit.movedNote],
                refreshFolderVaultIDs: [source.vaultID]
            )
        )
        // The source rename, incoming-link rewrites, and identity rebind are
        // already durable at this point. Graph, Search, and the complete
        // Workspace snapshot are disposable projections, so every kind of
        // Note move resumes them in the owned background refresh instead of
        // holding the interaction open. The exact window installs the
        // committed source-ahead relocation before this operation returns.
        scheduleCommittedMutationRefresh(refreshPayload)
        if let agentMove {
            guard identityFailure == nil else {
                _ = try? await services.agentChangeStore.markOutcomeUncertain(id: agentMove.changeID)
                throw AgentCollaborationError.changeConfirmationUncertain(agentMove.changeID)
            }
            try await confirmAgentMoveEvidence(id: agentMove.changeID, commit: commit)
        }
        if let undoAgentMoveID {
            guard identityFailure == nil else { throw AgentCollaborationError.changeConfirmationUncertain(undoAgentMoveID) }
            try await confirmAgentMoveUndo(id: undoAgentMoveID, commit: commit)
        }
        endSourceMutation(mutationLease)
        ownsMutation = false
        return WorkspaceMutationOutcome(
            committedValue: commit,
            identityRecoveryWarning: identityFailure?.localizedDescription
        )
    }

    func coordinatedMoveFolder(
        inVault vaultID: UUID,
        from sourceRelativePath: String,
        to destinationRelativePath: String
    ) async throws -> WorkspaceMutationOutcome<FolderMoveCommit> {
        try requireActive()
        let mutationLease = try await beginSourceMutation()
        var ownsMutation = true
        defer {
            if ownsMutation { endSourceMutation(mutationLease) }
        }
        let sourceFolder: VaultRelativeFolderPath
        let destinationFolder: VaultRelativeFolderPath
        do {
            sourceFolder = try VaultRelativeFolderPath(sourceRelativePath)
            destinationFolder = try VaultRelativeFolderPath(destinationRelativePath)
        } catch {
            throw VaultRepositoryError.invalidRelativePath(
                sourceRelativePath + " → " + destinationRelativePath
            )
        }
        guard let vaultSnapshot = currentSnapshot.vault(id: vaultID) else {
            throw ScholiumApplicationError.vaultNotInWorkspace(vaultID)
        }
        let noteMoves = try sourceAuthorizedFolderNoteMoves(
            vaultID: vaultID,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            snapshotDocuments: vaultSnapshot.documents,
            sourceAheadIdentityRecords: sourceAheadIdentityRecords
        )

        let repositories = services.repositories
        let plan = try await workspaceFolderMovePlan(
            vaultID: vaultID,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            noteMoves: noteMoves
        )

        let coordinator = TriptychFolderMoveCoordinator(
            triptychID: services.manifest.id,
            repositories: repositories,
            recoveryStore: services.transactionRecoveryStore
        )
        let commit = try await coordinator.move(plan)

        var identityFailure: Error?
        var movedIdentityRecords: [NoteIdentityRecord] = []
        do {
            movedIdentityRecords = try await services.controlStore.moveIdentities(
                commit.noteMoves
            )
            let failures = await services.identityRecoveryCoordinator.resumePendingRebindings(
                vaultID: vaultID,
                repository: try repository(vaultID: vaultID)
            )
            let movedIDs = Set(commit.noteMoves.map(\.stableNoteID))
            if let failure = failures.first(where: {
                movedIDs.contains($0.rebinding.noteID)
            }) {
                identityFailure = NoteIdentityMigrationError.incomplete(failure.message)
            }
        } catch {
            identityFailure = error
        }

        for move in commit.noteMoves {
            sourceAheadIdentityRecords[move.source] = nil
            sourceAheadIdentityRecords[move.destination] = nil
        }
        if identityFailure == nil {
            for record in movedIdentityRecords {
                sourceAheadIdentityRecords[
                    VaultQualifiedNoteID(
                        vaultID: record.vaultID,
                        relativePath: record.relativePath
                    )] = record
            }
        }

        let affectedVaultIDs = Set(plan.rewrites.map { $0.source.vaultID })
            .union([vaultID])
        let refreshPayload = WorkspaceRefreshPayload(
            publication: .explicit,
            failureDisposition: .staleAfterCommittedMutation(
                affectedVaultIDs: affectedVaultIDs
            ),
            sourceCatalogPreparation: Self.catalogPreparation(
                upserts: commit.noteMoves.map(\.destination)
                    + commit.rewrites.map(\.note),
                deletions: commit.noteMoves.map(\.source),
                refreshFolderVaultIDs: [vaultID]
            )
        )
        // The directory rename, exact link rewrites, and portable identity
        // rebind are durable. Queue the one complete derived generation while
        // the source lease is still held so matching watcher events cannot
        // start a competing rebuild; the exact window installs the returned
        // committed sources immediately.
        scheduleCommittedMutationRefresh(refreshPayload)
        endSourceMutation(mutationLease)
        ownsMutation = false
        return WorkspaceMutationOutcome(
            committedValue: commit,
            identityRecoveryWarning: identityFailure?.localizedDescription
        )
    }

    struct ScopedMoveProjectionContext {
        let projections: [VaultQualifiedNoteID: WorkspaceSourceProjection]
        let versions: [VaultQualifiedNoteID: SourceVersion]
        let catalog: [LinkCatalogNote]
        let authoredLinks: [VaultQualifiedNoteID: [LinkOccurrence]]
        let graph: GraphSnapshot
        let manifest: [SearchSourceManifestEntry]
    }

    /// A fresh compact cohort proves resolution without retaining every Note
    /// source. Only moved Notes and graph-identified link owners are loaded.
    func freshScopedMoveProjectionContext() async throws -> ScopedMoveProjectionContext {
        var projections: [VaultQualifiedNoteID: WorkspaceSourceProjection] = [:]
        var versions: [VaultQualifiedNoteID: SourceVersion] = [:]
        for vault in orderedVaults() {
            guard let sourceCatalog = services.sourceCatalogs[vault.id] else {
                throw ScholiumApplicationError.vaultNotInWorkspace(vault.id)
            }
            try await sourceCatalog.reconcile()
            let source = try await sourceCatalog.snapshot(refreshFolders: false)
            for projection in source.projections {
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: projection.relativePath)
                guard let version = source.sourceVersions[projection.relativePath] else {
                    throw WorkspaceHydrationError.staleSnapshot
                }
                projections[id] = projection
                versions[id] = version
            }
        }
        let all = projections.values.sorted { $0.linkCatalog.id < $1.linkCatalog.id }
        let manifest = all.map {
            SearchSourceManifestEntry(
                vaultID: $0.linkCatalog.id.vaultID,
                relativePath: $0.relativePath, fingerprint: $0.fingerprint)
        }
        let authoredLinks = Dictionary(
            uniqueKeysWithValues: all.map {
                ($0.linkCatalog.id, $0.authoredLinks)
            })
        let graph = LinkGraphBuilder.build(
            generation: (currentSnapshot.discovery.catalog.graph?.generation ?? 0) + 1,
            catalog: all.map(\.linkCatalog),
            authoredLinks: authoredLinks,
            resolutionScope: .workspace,
            sourceManifestHash: SearchSourceManifest.hash(manifest)
        )
        return ScopedMoveProjectionContext(
            projections: projections, versions: versions,
            catalog: all.map(\.linkCatalog), authoredLinks: authoredLinks,
            graph: graph, manifest: manifest
        )
    }

    func loadScopedMoveDocuments(
        _ ids: Set<VaultQualifiedNoteID>, context: ScopedMoveProjectionContext
    ) async throws -> [VaultQualifiedNoteID: NoteDocument] {
        var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
        for id in ids.sorted() {
            try Task.checkCancellation()
            guard let projection = context.projections[id],
                let version = context.versions[id]
            else { throw WorkspaceHydrationError.staleSnapshot }
            let repository = try repository(vaultID: id.vaultID)
            let loaded = try await repository.loadCatalogSource(relativePath: id.relativePath)
            guard loaded.version == version,
                loaded.document.fingerprint == projection.fingerprint
            else { throw WorkspaceHydrationError.staleSnapshot }
            documents[id] = loaded.document
        }
        return documents
    }

    func validateScopedMoveCohort(_ context: ScopedMoveProjectionContext) async throws {
        for vault in orderedVaults() {
            let repository = try repository(vaultID: vault.id)
            let observed = try await repository.markdownRelativePaths()
            let expected = context.projections.keys.filter { $0.vaultID == vault.id }
                .map(\.relativePath)
            guard Set(observed.map { Data($0.utf8) }) == Set(expected.map { Data($0.utf8) })
            else { throw WorkspaceHydrationError.staleSnapshot }
        }
        for id in context.versions.keys.sorted() {
            try Task.checkCancellation()
            let repository = try repository(vaultID: id.vaultID)
            guard let version = context.versions[id],
                try await repository.sourceVersionIsCurrent(
                    relativePath: id.relativePath, version: version)
            else { throw WorkspaceHydrationError.staleSnapshot }
        }
    }

    private func workspaceFolderMovePlan(
        vaultID: UUID,
        sourceFolder: VaultRelativeFolderPath,
        destinationFolder: VaultRelativeFolderPath,
        noteMoves: [FolderNoteMovePlan]
    ) async throws -> FolderIncomingLinkRewritePlan {
        let context = try await freshScopedMoveProjectionContext()
        let movingIDs = Set(noteMoves.map(\.source))
        let candidateIDs = Set(
            context.graph.outgoing.values.flatMap { $0 }.compactMap {
                edge -> VaultQualifiedNoteID? in
                guard case .resolved(let target) = edge.occurrence.resolution,
                    movingIDs.contains(target)
                else { return nil }
                return edge.source
            }
        ).union(movingIDs)
        let documents = try await loadScopedMoveDocuments(candidateIDs, context: context)
        guard
            let plan = IncomingLinkRewriter.folderPlanUsingValidatedSnapshot(
                documents: documents, catalog: context.catalog, graph: context.graph,
                sourceManifest: context.manifest, vaultID: vaultID,
                sourceFolder: sourceFolder, destinationFolder: destinationFolder,
                noteMoves: noteMoves)
        else {
            throw VaultRepositoryError.writeFailed(
                "The exact Metadata-aware Link catalog could not be proven for this folder move.")
        }
        try await validateScopedMoveCohort(context)
        let rewrites = try await preservingPDFBindings(
            documents: documents, destinations: Dictionary(uniqueKeysWithValues: noteMoves.map { ($0.source, $0.destination) }),
            rewrites: plan.rewrites)
        return FolderIncomingLinkRewritePlan(
            vaultID: plan.vaultID, sourceFolder: plan.sourceFolder, destinationFolder: plan.destinationFolder,
            graphGeneration: plan.graphGeneration, noteMoves: plan.noteMoves, rewrites: rewrites,
            blockedIncomingLinks: plan.blockedIncomingLinks)
    }

    func workspaceMovePlan(
        moving source: VaultQualifiedNoteID,
        to destination: VaultQualifiedNoteID
    ) async throws -> IncomingLinkRewritePlan {
        let context = try await freshScopedMoveProjectionContext()
        let candidateIDs = Set(
            context.graph.outgoing.values.flatMap { $0 }.compactMap {
                edge -> VaultQualifiedNoteID? in
                guard case .resolved(let target) = edge.occurrence.resolution,
                    target == source
                else { return nil }
                return edge.source
            }
        ).union([source])
        let documents = try await loadScopedMoveDocuments(candidateIDs, context: context)
        guard
            let plan = IncomingLinkRewriter.planUsingValidatedSnapshot(
                documents: documents, catalog: context.catalog, graph: context.graph,
                sourceManifest: context.manifest, moving: source, to: destination)
        else {
            throw VaultRepositoryError.writeFailed(
                "The exact Metadata-aware Link catalog could not be proven for this Note move.")
        }
        try await validateScopedMoveCohort(context)
        let rewrites = try await preservingPDFBindings(documents: documents, destinations: [source: destination], rewrites: plan.rewrites)
        return IncomingLinkRewritePlan(
            movedNote: plan.movedNote, destination: plan.destination, graphGeneration: plan.graphGeneration,
            rewrites: rewrites, blockedIncomingLinks: plan.blockedIncomingLinks)
    }

    private func preservingPDFBindings(
        documents: [VaultQualifiedNoteID: NoteDocument], destinations: [VaultQualifiedNoteID: VaultQualifiedNoteID],
        rewrites: [IncomingLinkRewrite]
    ) async throws -> [IncomingLinkRewrite] {
        var bySource = Dictionary(uniqueKeysWithValues: rewrites.map { ($0.source, $0) })
        for source in destinations.keys.sorted() {
            guard let original = documents[source], let destination = destinations[source],
                let binding = try PDFNoteBinding.path(in: original)
            else { continue }
            let rebased = try await services.pdfReader.rebaseBinding(binding, from: source, to: destination)
            guard rebased != binding else { continue }
            let previous = bySource[source]
            let current = NoteDocument(relativePath: source.relativePath, rawContent: previous?.updatedSource ?? original.rawContent)
            guard let patch = try NoteInfoMetadataPlanner.plan(document: current, edits: ["pdf": .string(rebased)]) else { continue }
            bySource[source] = IncomingLinkRewrite(
                source: source, expectedRevision: original.fingerprint, updatedSource: patch.resultingSource,
                rewrittenOccurrences: (previous?.rewrittenOccurrences ?? 0) + 1)
        }
        return bySource.values.sorted { $0.source < $1.source }
    }

    func freshMovePlanningContext() async throws -> (documents: [VaultQualifiedNoteID: NoteDocument], catalog: [LinkCatalogNote], graph: GraphSnapshot) {
        var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
        for registeredVault in orderedVaults() {
            let repository = try repository(vaultID: registeredVault.id)
            for path in try await repository.markdownRelativePaths() {
                let document = try await repository.load(relativePath: path)
                documents[
                    VaultQualifiedNoteID(
                        vaultID: registeredVault.id,
                        relativePath: path
                    )] = document
            }
        }
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let vaultRoles = Dictionary(
            uniqueKeysWithValues: orderedVaults().map {
                ($0.id, $0.role)
            })
        let catalog = try await exactLinkCatalog(
            documents: documents,
            semantics: semantics,
            vaultRoles: vaultRoles
        )
        let sourceManifestHash = SearchSourceManifest.hash(
            documents.map {
                id, document in
                SearchSourceManifestEntry(
                    vaultID: id.vaultID,
                    relativePath: id.relativePath,
                    fingerprint: document.fingerprint
                )
            })
        let graph = LinkGraphBuilder.build(
            generation: (currentSnapshot.discovery.catalog.graph?.generation ?? 0) + 1,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace,
            sourceManifestHash: sourceManifestHash
        )
        return (documents, catalog, graph)
    }

    private func exactLinkCatalog(
        documents: [VaultQualifiedNoteID: NoteDocument],
        semantics: [VaultQualifiedNoteID: MarkdownSemanticDocument],
        vaultRoles: [UUID: VaultRole]
    ) async throws -> [LinkCatalogNote] {
        var catalog: [LinkCatalogNote] = []
        catalog.reserveCapacity(documents.count)
        for id in documents.keys.sorted() {
            guard let document = documents[id] else { continue }
            let role = vaultRoles[id.vaultID] ?? .other
            catalog.append(
                LinkCatalogNote(
                    vaultID: id.vaultID,
                    document: document,
                    profile: WorkflowProfileResolver.resolve(vaultRole: role),
                    semantic: semantics[id]
                ))
        }
        return catalog
    }

    func requireExpectedIdentity(
        _ expected: UUID?,
        resolved current: UUID,
        relativePath: String
    ) throws {
        guard let expected else { return }
        guard expected == current else {
            throw NoteIdentityRecoveryError.targetIdentityChanged(relativePath)
        }
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
        guard
            let record = try await services.controlStore.identityRecord(
                vaultID: id.vaultID,
                relativePath: id.relativePath
            ), record.fingerprint == expectedRevision
        else {
            throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
        }
        if let note = currentSnapshot.document(id: id),
            note.fingerprint == expectedRevision,
            note.stableIdentity.resolvedID == record.id
        {
            return record
        }
        guard let sourceAhead = sourceAheadIdentityRecords[id],
            sourceAhead.id == record.id,
            sourceAhead.fingerprint == record.fingerprint
        else {
            throw NoteIdentityRecoveryError.identityUnresolved(id.relativePath)
        }
        return record
    }

    func resolveIdentity(
        _ ambiguity: NoteIdentityAmbiguity,
        candidateID: UUID?
    ) async throws -> WorkspaceMutationOutcome<NoteIdentityRecord> {
        try requireActive()
        let repository = try repository(vaultID: ambiguity.vaultID)
        guard
            WorkspaceVaultSlot.allCases.contains(where: {
                assignment.vault(for: $0)?.id == ambiguity.vaultID
            })
        else {
            throw ScholiumApplicationError.vaultNotInWorkspace(ambiguity.vaultID)
        }
        let record = try await services.identityRecoveryCoordinator.resolve(
            ambiguity,
            candidateID: candidateID,
            repository: repository
        )
        let derivedRefreshWarning: String?
        do {
            _ = try await refresh(
                publication: .explicit,
                failureDisposition: .staleAfterCommittedMutation(
                    affectedVaultIDs: [ambiguity.vaultID]
                )
            )
            derivedRefreshWarning = nil
        } catch {
            derivedRefreshWarning = error.localizedDescription
        }
        return WorkspaceMutationOutcome(
            committedValue: record,
            derivedRefreshWarning: derivedRefreshWarning
        )
    }

}
