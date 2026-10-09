import Foundation
import ScholiumContracts

/// Accepting Workspace's projection: derived refreshes, committed snapshots,
/// and the window state a new projection replaces.
extension WindowModel {
    var hasDerivedRefreshFailure: Bool {
        switch derivedRefreshStatus {
        case .stale, .failed:
            true
        case .opening, .current, .none:
            false
        }
    }

    func retryDerivedRefresh() async {
        _ = await refreshWorkspaceProjection(
            refreshingStatus: "Retrying Triptych refresh…"
        )
    }

    func refreshAfterResearchHandoff() async -> WorkspaceSnapshot? {
        await refreshWorkspaceProjection(refreshingStatus: nil)
    }

    private func refreshWorkspaceProjection(
        refreshingStatus: String?
    ) async -> WorkspaceSnapshot? {
        guard let vaultID = currentRegisteredVault?.id,
            let runtimeIdentity = windowWorkspaceController.activeCapabilities?.runtimeIdentity
        else { return nil }
        if let refreshingStatus { refreshStatusText = refreshingStatus }
        do {
            let snapshot = try await discoveryController.refreshWorkspace()
            guard currentRegisteredVault?.id == vaultID,
                let capabilities = windowWorkspaceController.activeCapabilities,
                capabilities.runtimeIdentity == runtimeIdentity,
                let commit = workspaceProjectionController.replaceSnapshot(
                    snapshot,
                    runtimeIdentity: capabilities.runtimeIdentity,
                    status: .current(WorkspaceDerivedRefreshEvidence(snapshot: snapshot)),
                    context: workspaceProjectionContext
                )
            else { return nil }
            let reconciliation = reconcilePublishedDocuments(
                workspaceProjectionController.effectiveSnapshot(snapshot))
            applyWorkspaceProjectionCommit(commit, documentReconciliation: reconciliation)
            refreshStatusText = nil
            workspaceProjectionController.reportCatalogError(nil)
            return snapshot
        } catch {
            guard currentRegisteredVault?.id == vaultID,
                windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtimeIdentity
            else { return nil }
            refreshStatusText = "Triptych refresh failed"
            workspaceProjectionController.reportCatalogError(error.localizedDescription)
            return nil
        }
    }

    func resetWindowSession() {
        libraryRevealTask?.cancel()
        libraryRevealTask = nil
        requestedWorkspaceSelection = nil
        presentationRouter.dismissAll()
        documentController.removeAll(retainingSessions: true)
        documentTabController.removeAll()
        documentNavigationHistoryController.removeAll()
        searchController.resetExecution()
        discoveryController.reset()
        researchController.reset()
        workspaceProjectionController.reset()
        shellState.resetWorkspaceSessions()
        documentController.resetPresentationState()
        documentController.requestSourceLocation(line: nil)
        clearMetadataFilters()
        currentRegisteredVault = nil
        currentVaultRole = .other
        noteIdentityByPath = [:]
        identityAmbiguities = []
        pendingIdentityRebindings = []
        identityMigrationFailures = []
        identityResolutionError = nil
    }

    func receiveWorkspaceEvents(_ events: [UUID: WorkspaceEvent]) {
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            let event = events[capabilities.id]
        else { return }
        guard
            workspaceProjectionController.canReceive(
                event,
                runtimeIdentity: capabilities.runtimeIdentity
            )
        else { return }

        if case .vaultAccessInvalidated(let invalidation) = event,
            let path = WorkspaceVaultSlot.allCases.compactMap({ slot -> String? in
                guard let vaultID = workspaceAssignment?.vault(for: slot)?.id else {
                    return nil
                }
                return invalidation.unavailableVaultPaths[vaultID]
            }).first
        {
            _ = windowWorkspaceController.recordRecovery(
                for: WorkspaceRegistryError.vaultAccessUnavailable(path)
            )
        }

        if case .inventoryChanged(let change) = event,
            workspaceProjectionController.advancesSourceInventory(event.snapshot)
        {
            for move in change.moved
            where move.previousLocation.vaultID == move.location.vaultID {
                migrateInMemoryPath(
                    from: move.previousLocation.relativePath,
                    to: move.location.relativePath,
                    noteID: move.stableNoteID,
                    identityResolved: true,
                    vaultID: move.location.vaultID
                )
            }
        }

        if case .researchConfigurationInvalidated = event,
            !workspaceProjectionController.advancesSourceInventory(event.snapshot)
        {
            documentController.refreshCitationSnapshots(affectedNoteIDs: nil)
            _ = workspaceProjectionController.receive(
                event,
                runtimeIdentity: capabilities.runtimeIdentity,
                context: workspaceProjectionContext
            )
            return
        }

        let documentReconciliation = reconcilePublishedDocuments(
            workspaceProjectionController.effectiveSnapshot(event.snapshot))
        // Events are coalesced; any delivered generation can follow a citation
        // invalidation. Recheck only retained Notes, keeping source summaries light.
        documentController.refreshCitationSnapshots(affectedNoteIDs: nil)
        researchController.receive(event.snapshot)
        researchController.observeDocumentChangesGeneration(
            event.snapshot.documentChangesGeneration
        )
        switch event {
        case .sourceCommitted, .inventoryChanged:
            researchController.scheduleAgentChangesRefresh()
            researchController.noteDocumentChangesInvalidated()
        case .documentChangesChanged, .citationAuthorityInvalidated:
            break
        case .snapshot, .derivedStateChanged, .researchStateChanged,
            .researchConfigurationInvalidated, .vaultAccessInvalidated,
            .runtimeReloaded:
            break
        }
        if let commit = workspaceProjectionController.receive(
            event,
            runtimeIdentity: capabilities.runtimeIdentity,
            context: workspaceProjectionContext
        ) {
            applyWorkspaceProjectionCommit(
                commit,
                documentReconciliation: documentReconciliation
            )
        }
    }

    var workspaceProjectionContext: WindowWorkspaceProjectionContext {
        WindowWorkspaceProjectionContext(
            selectedVaultID: currentRegisteredVault?.id,
            sourceScope: noteSourceScope,
            currentDocumentVaultID: currentDocumentVaultID,
            selectedDocumentPath: selectedDocumentPath,
            retainedDeletedDocumentPath: documentController.retainedDeletedDocumentPath
        )
    }

    private func reconcilePublishedDocuments(_ snapshot: WorkspaceSnapshot) -> DocumentWorkspaceReconciliation {
        for vault in snapshot.vaults {
            for rebinding in vault.identityRecovery.pendingRebindings {
                migrateInMemoryPath(
                    from: rebinding.previousRelativePath, to: rebinding.relativePath,
                    noteID: rebinding.noteID, identityResolved: false, vaultID: vault.vault.id
                )
            }
            for rebinding in vault.identityRecovery.completedRebindings {
                migrateInMemoryPath(
                    from: rebinding.previousRelativePath, to: rebinding.relativePath,
                    noteID: rebinding.id, identityResolved: true, vaultID: vault.vault.id
                )
            }
        }
        documentNavigationHistoryController.receive(snapshot)
        return documentController.receive(snapshot, openDocuments: documentTabController.tabs.map(\.document))
    }

    func applyWorkspaceProjectionCommit(
        _ commit: WindowWorkspaceProjectionCommit,
        documentReconciliation: DocumentWorkspaceReconciliation = .unchanged
    ) {
        refreshDocumentTabProjections()
        removeExternallyDeletedDocumentTabs(
            documentReconciliation.removedDocuments
        )
        if commit.searchGenerationChanged {
            searchController.searchGenerationDidChange()
        }
        switch commit.derivedRefreshStatus {
        case .opening:
            if refreshStatusText?.hasPrefix("Conflict:") != true {
                refreshStatusText = String(localized: "Refreshing derived state…")
            }
        case .current:
            if refreshStatusText == String(localized: "Refreshing derived state…")
                || refreshStatusText == "Derived state is stale"
                || refreshStatusText == "Derived refresh failed"
            {
                refreshStatusText = nil
            }
        case .stale:
            if refreshStatusText?.hasPrefix("Conflict:") != true {
                refreshStatusText = "Derived state is stale"
            }
        case .failed:
            if refreshStatusText?.hasPrefix("Conflict:") != true {
                refreshStatusText = "Derived refresh failed"
            }
        }
        if commit.retainedDeletedDocumentPath != nil {
            refreshStatusText = "Conflict: note deleted outside Scholium"
        }
        if let vaultID = currentRegisteredVault?.id,
            let vaultSnapshot = workspaceProjectionController.vaultSnapshot(id: vaultID)
        {
            refreshIdentityState(from: vaultSnapshot)
        }
    }

    private func replaceCachedWorkspaceNote(_ note: WorkspaceNoteSnapshot) {
        guard
            let vault = workspaceProjectionController.recordCommittedNote(
                note.summary,
                visibleVaultID: currentRegisteredVault?.id,
                visibleSourceScope: noteSourceScope
            )
        else { return }
        refreshDocumentTabProjections()
        documentController.recordCommittedSnapshot(
            note,
            vaultName: vault.name,
            vaultRole: vault.role
        )
    }

    /// Publishes authoritative document bytes before refreshing disposable
    /// projections. A parse or index failure can make derived state stale, but
    /// must never make the editor retry an already committed repository write
    /// or reject a disk revision the researcher explicitly accepted.
    func replaceSavedDocument(_ document: NoteDocument) async -> WindowDocumentLocation? {
        guard let context = activeDocumentContext(for: document.relativePath) else {
            return nil
        }
        let previous = workspaceProjectionController.cachedNote(
            vaultID: context.vaultID,
            stableNoteID: context.noteID,
            relativePath: document.relativePath
        )
        let loaded = try? await documentController.noteSnapshot(
            VaultQualifiedNoteID(
                vaultID: context.vaultID,
                relativePath: document.relativePath
            ))
        let savedSnapshot: WorkspaceNoteSnapshot
        if let loaded, loaded.fingerprint == document.fingerprint {
            savedSnapshot = loaded
        } else {
            // Only the active Note needs an immediate source-bound title and
            // outline before the Triptych-wide derived refresh catches up.
            // Parse it off the main actor once, then publish the immutable
            // projection; SwiftUI views never parse Markdown in `body`.
            let semantic = await Task.detached(priority: .utility) {
                MarkdownSemanticDocument(parsing: document)
            }.value
            let metadata: WorkspaceFileMetadata
            let identity: WorkspaceNoteIdentityState
            let graphCounts: WorkspaceGraphCounts
            if let previous {
                metadata = WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: previous.fileMetadata.creationDate,
                    modificationDate: previous.fileMetadata.modificationDate
                )
                identity = previous.stableIdentity
                graphCounts = previous.graphCounts
            } else {
                metadata = WorkspaceFileMetadata(
                    byteCount: document.sourceBytes.count,
                    creationDate: nil,
                    modificationDate: nil
                )
                identity = .resolved(context.noteID)
                graphCounts = WorkspaceGraphCounts(
                    incoming: 0,
                    outgoing: 0,
                    broken: 0,
                    ambiguous: 0
                )
            }
            let id = VaultQualifiedNoteID(
                vaultID: context.vaultID,
                relativePath: document.relativePath
            )
            let summary = WorkspaceNoteSummary(
                id: id,
                vaultRole: context.vaultRole,
                stableIdentity: identity,
                document: document,
                semantic: semantic,
                fileMetadata: metadata,
                graphCounts: graphCounts,
                derivedProjectionState: .sourceAhead
            )
            savedSnapshot = WorkspaceNoteSnapshot(
                summary: summary, document: document,
                cachedSemanticDocument: semantic
            )
        }

        replaceCachedWorkspaceNote(savedSnapshot)
        let saved = WindowDocumentLocation.hydrated(savedSnapshot)
        if currentRegisteredVault?.id == context.vaultID {
            return notes.first(where: { $0.relativePath == document.relativePath }) ?? saved
        }
        return saved
    }
}
