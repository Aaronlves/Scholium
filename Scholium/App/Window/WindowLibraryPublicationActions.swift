import Foundation
import ScholiumContracts

/// Publication of committed library mutations: Application has already
/// accepted the change, so these commands only project it into the window's
/// library, disclosure and selection state.
extension WindowModel {
    func publishCommittedNoteCreation(
        _ outcome: WorkspaceMutationOutcome<WorkspaceManagedNoteCommit>,
        isCurrent: @MainActor () -> Bool
    ) async {
        guard let vault = currentRegisteredVault else { return }
        let commit = outcome.committedValue
        let document = commit.document
        do {
            let sourceAheadSnapshot = commit.sourceAheadSnapshot
            guard
                workspaceProjectionController.recordCommittedNote(
                    sourceAheadSnapshot,
                    visibleVaultID: currentRegisteredVault?.id,
                    visibleSourceScope: noteSourceScope
                ) != nil
            else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            guard isCurrent() else {
                reportCommittedMutationWarnings(outcome)
                return
            }
            if let noteID = sourceAheadSnapshot.stableIdentity.resolvedID {
                try await activateWorkspaceReference(
                    VaultNoteReference(
                        vaultID: vault.id,
                        vaultName: vault.name,
                        vaultRole: vault.role,
                        relativePath: document.relativePath,
                        stableNoteID: noteID.uuidString.lowercased()
                    ),
                    tabActivation: .place(.replaceSelected),
                    managedCreationBodyStartUTF16: document.bodyUTF16Offset
                )
            } else {
                PerformanceProbe.shared.beginReadActivation(
                    documentID: document.relativePath
                )
                documentController.selectUnavailableDocument(
                    vaultID: vault.id,
                    relativePath: document.relativePath
                )
                synchronizeDocumentTabs(after: .place(.replaceSelected))
            }
            revealCreatedNoteInLibrary(document.relativePath, vaultID: vault.id)
            reportCommittedMutationWarnings(outcome)
        } catch {
            reportCommittedMutationWarnings(
                outcome,
                presentationWarning: error.localizedDescription
            )
        }
    }

    func publishCommittedFolderCreation(
        _ outcome: WorkspaceMutationOutcome<VaultRelativeFolderPath>
    ) async {
        guard let vault = currentRegisteredVault else { return }
        let folder = outcome.committedValue
        do {
            guard
                workspaceProjectionController.recordCommittedFolder(
                    folder,
                    vaultID: vault.id
                ) != nil
            else {
                try await refreshCachedWorkspaceVaultSnapshot(vaultID: vault.id)
                try await browseRegisteredVault(vault)
                expandFolderAncestors(folder.rawValue, vaultID: vault.id)
                reportCommittedMutationWarnings(outcome)
                return
            }
            expandFolderAncestors(folder.rawValue, vaultID: vault.id)
            reportCommittedMutationWarnings(outcome)

        } catch {
            reportCommittedMutationWarnings(
                outcome,
                presentationWarning: error.localizedDescription
            )
        }
    }

    func publishCommittedFolderMove(
        _ outcome: WorkspaceMutationOutcome<FolderMoveCommit>
    ) async {
        let commit = outcome.committedValue
        projectFolderMove(
            commit,
            identityResolved: outcome.identityRecoveryWarning == nil
        )
        migrateFolderDisclosure(
            from: commit.sourceFolder.rawValue,
            to: commit.destinationFolder.rawValue,
            vaultID: commit.vaultID
        )
        var presentationWarning: String?
        if outcome.identityRecoveryWarning == nil,
            let projection = workspaceProjectionController.recordCommittedFolderMove(
                commit,
                visibleVaultID: currentRegisteredVault?.id,
                visibleSourceScope: noteSourceScope
            )
        {
            for note in projection.notes {
                documentController.recordCommittedSnapshot(
                    note,
                    vaultName: projection.vault.name,
                    vaultRole: projection.vault.role
                )
            }
        } else {
            presentationWarning = String(
                localized: "The folder moved, but this window is waiting for the committed refresh.",
                table: "Localizable",
                bundle: .module
            )
        }
        scheduleWorkspaceCatalogRefresh()
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
    }

    /// Folder mutations publish a new authoritative snapshot before returning,
    /// but the per-window Combine projection may still be queued on the main
    /// actor. Refresh the exact vault cache before rebuilding the visible tree
    /// so newly created empty folders and folder moves cannot be hidden by the
    /// preceding window generation.
    func refreshCachedWorkspaceVaultSnapshot(vaultID: UUID) async throws {
        guard
            let snapshot = try await documentController.workspaceSnapshot(
                vaultID: vaultID
            )
        else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        workspaceProjectionController.replaceVaultSnapshot(snapshot)
    }

    private func projectFolderMove(
        _ commit: FolderMoveCommit,
        identityResolved: Bool
    ) {
        for move in commit.noteMoves {
            let sessionKey = DocumentSessionKey(
                vaultID: commit.vaultID,
                noteID: move.stableNoteID
            )
            let wasSelected = currentDocumentDescriptor?.sessionKey == sessionKey
            migrateAppOwnedState(
                sourcePath: move.source.relativePath,
                destinationPath: move.destination.relativePath,
                noteID: move.stableNoteID,
                identityResolved: identityResolved,
                vaultID: commit.vaultID
            )
            _ = wasSelected
        }
    }

    private func expandFolderAncestors(_ relativePath: String, vaultID: UUID) {
        let visiblePath = libraryCategoryRelativeFolderPath(relativePath)
        guard !visiblePath.isEmpty else { return }
        let scope = LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        var expanded = discoveryController.expandedFolders(in: scope)
        let parts = visiblePath.split(separator: "/").map(String.init)
        for count in 1...parts.count {
            expanded.insert(parts.prefix(count).joined(separator: "/"))
        }
        discoveryController.setExpandedFolders(expanded, in: scope)
    }

    private func revealCreatedNoteInLibrary(_ relativePath: String, vaultID: UUID) {
        let scope = LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        discoveryController.prepareCreatedNoteReveal(
            relativePath: relativePath,
            folderAncestors: libraryFolderAncestors(forDocumentPath: relativePath),
            in: scope
        )
    }

    private func migrateFolderDisclosure(
        from sourceRelativePath: String,
        to destinationRelativePath: String?,
        vaultID: UUID
    ) {
        let scope = LibraryDisclosureScope(vaultID: vaultID, sourceScope: .library)
        let source = libraryCategoryRelativeFolderPath(sourceRelativePath)
        let destination = destinationRelativePath.map(libraryCategoryRelativeFolderPath)
        guard !source.isEmpty else { return }
        let sourcePrefix = source + "/"
        var migrated: Set<String> = []
        for folder in discoveryController.expandedFolders(in: scope) {
            if folder == source || folder.hasPrefix(sourcePrefix) {
                guard let destination, !destination.isEmpty else { continue }
                migrated.insert(destination + folder.dropFirst(source.count))
            } else {
                migrated.insert(folder)
            }
        }
        if let destination, !destination.isEmpty {
            let parts = destination.split(separator: "/").map(String.init)
            if parts.count > 1 {
                for count in 1..<parts.count {
                    migrated.insert(parts.prefix(count).joined(separator: "/"))
                }
            }
        }
        discoveryController.setExpandedFolders(migrated, in: scope)
    }

    func publishCommittedNoteDuplication(
        _ outcome: WorkspaceMutationOutcome<NoteDocument>,
        target: NoteMutationTarget,
        destination: String
    ) async {
        guard
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == target.documentID.vaultID
            })
        else {
            reportCommittedMutationWarnings(
                outcome,
                presentationWarning: WorkspaceRegistryError.incompleteWorkspace.localizedDescription
            )
            return
        }
        var presentationWarning: String?
        do {
            try await refreshCachedWorkspaceVaultSnapshot(vaultID: target.documentID.vaultID)
            try await browseRegisteredVault(vault)
            openNote(destination)
        } catch {
            presentationWarning = error.localizedDescription
        }
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
    }

    func publishCommittedNoteMove(
        _ outcome: WorkspaceMutationOutcome<TriptychMoveCommit>,
        target: NoteMutationTarget
    ) async {
        guard
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == target.documentID.vaultID
            })
        else {
            reportCommittedMutationWarnings(
                outcome,
                presentationWarning: WorkspaceRegistryError.incompleteWorkspace.localizedDescription
            )
            return
        }
        let preservesDocument = libraryMutationController.isBatchWorking
        let commit = outcome.committedValue
        let destination = commit.destination.relativePath
        migrateAppOwnedState(
            sourcePath: target.relativePath,
            destinationPath: destination,
            noteID: target.stableNoteID,
            identityResolved: outcome.identityRecoveryWarning == nil,
            vaultID: target.documentID.vaultID
        )
        var presentationWarning: String?
        if outcome.identityRecoveryWarning == nil,
            let projection = workspaceProjectionController.recordCommittedNoteMove(
                commit,
                stableIdentity: .resolved(target.stableNoteID),
                visibleVaultID: currentRegisteredVault?.id,
                visibleSourceScope: noteSourceScope
            )
        {
            documentController.recordCommittedSnapshot(
                projection.note,
                vaultName: projection.vault.name,
                vaultRole: projection.vault.role
            )
            if !preservesDocument {
                do {
                    try await activateWorkspaceReference(
                        VaultNoteReference(
                            vaultID: projection.note.id.vaultID,
                            vaultName: projection.vault.name,
                            vaultRole: projection.vault.role,
                            relativePath: projection.note.id.relativePath,
                            stableNoteID: target.stableNoteID.uuidString.lowercased()
                        ),
                        tabActivation: .place(.replaceSelected)
                    )
                    revealCreatedNoteInLibrary(
                        projection.note.id.relativePath,
                        vaultID: projection.note.id.vaultID
                    )
                } catch {
                    presentationWarning = error.localizedDescription
                }
            }
        } else {
            do {
                try await refreshCachedWorkspaceVaultSnapshot(
                    vaultID: target.documentID.vaultID
                )
                try await browseRegisteredVault(vault)
                if !preservesDocument { openNote(destination) }
            } catch {
                presentationWarning = error.localizedDescription
            }
        }
        scheduleWorkspaceCatalogRefresh()
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: presentationWarning
        )
    }

    func requestCurrentNoteSystemTrash() {
        guard let currentNote,
            let target = NoteMutationTarget(currentNote),
            currentDocumentCapabilities.allows(.moveToSystemTrash)
        else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await libraryMutationController.prepareNoteSystemTrash(target)
            } catch is CancellationError {
                return
            } catch {
                reportOperationIssue(error.localizedDescription, kind: .error)
            }
        }
    }

    func publishSystemTrashResult(
        _ preview: SystemTrashDeletionPreview,
        outcome: WorkspaceMutationOutcome<SystemTrashDeletionCommit>?
    ) async {
        guard let outcome else {
            _ = try? await discoveryController.refreshWorkspace()
            await synchronizeSystemTrashPresentation(preview)
            return
        }
        await synchronizeSystemTrashPresentation(preview)
        sourceMutationGeneration &+= 1
        reportCommittedMutationWarnings(
            outcome,
            presentationWarning: nil
        )
    }

    private func synchronizeSystemTrashPresentation(
        _ preview: SystemTrashDeletionPreview
    ) async {
        guard let vaultID = preview.sources.first?.vaultID else { return }
        try? await refreshCachedWorkspaceVaultSnapshot(vaultID: vaultID)
        let currentPaths = Set(
            workspaceProjectionController.vaultSnapshot(id: vaultID)?
                .documents.map { $0.id.relativePath } ?? []
        )
        let plannedPaths = Set(preview.sources.flatMap(\.notes).map(\.relativePath))
        let removedPaths = plannedPaths.subtracting(currentPaths)
        guard !removedPaths.isEmpty else { return }
        do {
            try removeDocumentTabs(vaultID: vaultID, removedPaths: removedPaths)
        } catch {
            if currentDocumentVaultID == vaultID {
                documentController.clearSelection(forRemovedPaths: removedPaths)
            }
        }
        if currentRegisteredVault?.id == vaultID {
            try? await refreshLibrarySourceScope()
        }
        scheduleWorkspaceCatalogRefresh()
    }
}
