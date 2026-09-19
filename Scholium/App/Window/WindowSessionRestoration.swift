import Combine
import Foundation
import ScholiumContracts

/// The window's own session: restoring a saved reading state, persisting the
/// current one, and the per-document presentation the researcher left behind.
extension WindowModel {
    var currentPresentationMode: NotePresentationMode {
        documentController.currentPresentationMode
    }

    /// The workspace retains its desired mode across Notes, while chrome must
    /// report the mode the selected session is actually presenting. This keeps
    /// unavailable documents truthfully in Review
    /// without changing the workspace's retained Edit selection.
    var presentedDocumentMode: NotePresentationMode {
        guard currentNote != nil else { return currentPresentationMode }
        return documentController.chromeProjection.mode
    }

    func rememberPresentationMode(_ mode: NotePresentationMode) {
        documentController.rememberPresentationMode(mode)
    }

    func scrollPosition(for path: String) -> Double {
        documentController.scrollPosition(for: path, vaultID: currentDocumentVaultID)
    }

    func rememberScrollPosition(_ fraction: Double, for path: String) {
        documentController.rememberScrollPosition(
            fraction,
            for: path,
            vaultID: currentDocumentVaultID
        )
        documentPresentationDidChange.send()
    }

    /// Restores only committed presentation state. Editor buffers are absent
    /// from `WindowSessionSnapshot` and therefore cannot override disk bytes.
    func restoreWindowSession(id: UUID) async {
        guard !didRestoreWindowSession || windowSessionID != id else { return }
        windowSessionID = id
        editorFlushCoordinator.updateWindowID(id)
        isRestoringWindowSession = true
        defer {
            isRestoringWindowSession = false
            didRestoreWindowSession = true
            shellState.completeInitialRestore()
            persistWindowSessionNow()
        }

        let stored: WindowSessionSnapshot?
        do {
            stored = try await windowSessionPersistenceCoordinator.load(id: id)
        } catch {
            reportOperationIssue(
                String(
                    localized: "The saved window layout could not be restored. Scholium opened a clean window instead.", table: "Localizable", bundle: .module),
                kind: .warning)
            stored = nil
        }
        guard let stored else {
            // New configured windows keep the stable three-region shell.
            // Visibility changes only after a direct researcher action.
            shellState.restoreLibraryVisibility(true)
            researchController.restoreInspector(
                modesByWorkspace: [:],
                isVisible: nil
            )
            await restoreWorkspaceIfNeeded()
            return
        }

        if ScholiumRuntimeIsolation.fixtureRootURL() != nil {
            // A disposable QA fixture is reconstructed from its explicit root
            // on every process launch. Its saved window presentation is still
            // real, but it cannot authorize restoration before that isolated
            // workspace has installed its current capabilities and document
            // projection in this process.
            await restoreWorkspaceIfNeeded()
        } else {
            await windowWorkspaceController.refreshRegistrations()
            await refreshWorkspaceAssignment(
                preferredTriptychID: requestedTriptychID ?? stored.triptychID
            )
        }
        guard let restoredAssignment = workspaceAssignment else {
            windowWorkspaceController.markInitialRestoreAttempted()
            return
        }
        let requestedWorkspace = requestedInitialDocument.flatMap { requested in
            WorkspaceVaultSlot.allCases.first { workspace in
                restoredAssignment.vault(for: workspace)?.id == requested.vaultID
            }
        }
        let selectedWorkspace = requestedWorkspace ?? stored.selectedWorkspace
        do {
            guard let vault = restoredAssignment.vault(for: selectedWorkspace) else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            windowWorkspaceController.markInitialRestoreAttempted()
            try await openRegisteredVault(vault)
        } catch {
            vaultError = error.localizedDescription
            return
        }

        let availablePathsByVault = Dictionary(
            uniqueKeysWithValues:
                restoredAssignment.vaults.values.map { vault in
                    (
                        vault.id,
                        Set(
                            workspaceProjectionController.vaultSnapshot(id: vault.id)?
                                .documents.map(\.id.relativePath) ?? []
                        )
                    )
                }
        )
        let restoredPresentation = stored.normalized(
            availablePathsByVault: availablePathsByVault
        )

        for workspace in WorkspaceVaultSlot.allCases {
            guard let session = restoredPresentation.workspaceSession(for: workspace) else {
                continue
            }
            discoveryController.synchronizeLibrarySelection(
                workspaceSlot: workspace,
                sourceScope: .library
            )
            if let vaultID = session.vaultID {
                documentController.restorePresentationState(
                    documentPresentations: session.documentPresentations,
                    vaultID: vaultID
                )
            }
        }
        let inspectorModes = Dictionary(
            uniqueKeysWithValues:
                WorkspaceVaultSlot.allCases.map { workspace in
                    (
                        workspace,
                        restoredPresentation.workspaceSession(for: workspace)?
                            .inspectorMode ?? "links"
                    )
                }
        )
        let documentModes = Dictionary(
            uniqueKeysWithValues:
                WorkspaceVaultSlot.allCases.map { workspace in
                    (
                        workspace,
                        restoredPresentation.workspaceSession(for: workspace)
                            .flatMap { NotePresentationMode(rawValue: $0.documentMode) }
                            ?? .read
                    )
                }
        )
        shellState.selectWorkspace(selectedWorkspace)
        documentController.selectWorkspace(selectedWorkspace)
        documentController.restorePresentationModes(documentModes)
        researchController.restoreInspector(
            modesByWorkspace: inspectorModes,
            isVisible: restoredPresentation.inspectorVisible
        )

        reconcileDocumentSessionLeases()

        shellState.restoreLibraryVisibility(
            restoredPresentation.libraryVisible ?? true
        )
        discoveryController.replaceSearchCriteria(
            SearchWorkspaceState(
                scope: restoredPresentation.searchState.scope
            ))
        shellState.setDocumentTextScale(
            restoredPresentation.documentTextScale
                ?? ScholiumMetrics.Document.defaultTextScale
        )
        if ScholiumRuntimeIsolation.fixtureRootURL() != nil {
            // The stored presentation contains no editor bytes, but it does
            // retain the selected committed document for each window. Restore
            // that identity before falling back to the launch-only QA note so
            // multiple fixture windows do not all converge on the same note.
            if let selected =
                restoredPresentation.selectedDocument,
                selected.vaultID == restoredAssignment.vault(for: selectedWorkspace)?.id
            {
                openNote(selected.relativePath)
            } else {
                openRequestedTestNoteIfNeeded()
            }
        }
    }

    func persistWindowSessionNow() {
        guard didRestoreWindowSession,
            !isRestoringWindowSession,
            !windowSessionPersistenceCoordinator.isFinalizing,
            !windowSessionPersistenceCoordinator.isClosed
        else { return }
        let snapshot = currentWindowSessionSnapshot()
        windowSessionPersistenceCoordinator.schedule(
            snapshot: snapshot,
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.shellState.clearWindowSessionPersistenceFailure()
                case .failure(let error):
                    self.shellState.recordWindowSessionPersistenceFailure(
                        error.localizedDescription
                    )
                }
            }
        )
    }

    func currentWindowSessionSnapshot() -> WindowSessionSnapshot {
        let workspaceSessions = WorkspaceVaultSlot.allCases.map { workspace in
            let vaultID = workspaceAssignment?.vault(for: workspace)?.id
            let tabs = documentTabController.tabs.filter { $0.document.vaultID == vaultID }
            let openDocuments = tabs.compactMap {
                vaultQualifiedID(for: $0.document)
            }
            let openPaths = Set(openDocuments.map(\.relativePath))
            let documentPresentations = documentController.presentationSnapshot(
                vaultID: vaultID
            ).documents.filter { openPaths.contains($0.key) }
            return WindowWorkspaceSessionSnapshot(
                workspace: workspace,
                vaultID: vaultID,
                documentPresentations: documentPresentations,
                inspectorMode: shellState.inspectorMode(for: workspace).rawValue,
                documentMode: documentController.presentationMode(for: workspace).rawValue
            )
        }
        return WindowSessionSnapshot(
            id: windowSessionID,
            triptychID: workspaceAssignment?.id,
            selectedWorkspace: shellState.selectedWorkspace,
            openDocuments: documentTabController.tabs.compactMap { vaultQualifiedID(for: $0.document) },
            selectedDocument: documentTabController.selectedTab.flatMap { vaultQualifiedID(for: $0.document) },
            workspaceSessions: workspaceSessions,
            libraryVisible: nativeWindowCoordinator?.restoredLibraryVisibility ?? sidebarVisible,
            inspectorVisible: nativeWindowCoordinator?.restoredInspectorVisibility ?? researchInspectorVisible,
            searchState: SearchWorkspaceState(scope: searchController.ordinaryScope),
            documentTextScale: documentTextScale
        )
    }

    func observeWindowSessionChanges() {
        let stateChanges: [AnyPublisher<Void, Never>] = [
            windowWorkspaceController.$state
                .map(nonisolatedWorkspaceAssignmentID)
                .removeDuplicates()
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            $currentRegisteredVault.map(nonisolatedDiscardPublisherValue).eraseToAnyPublisher(),
            documentController.$selectedDocument
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            documentController.$currentPresentationMode
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            shellState.$libraryVisible
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            shellState.$documentTextScale
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            shellState.$selectedWorkspace
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            shellState.$inspector
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
            discoveryController.$search
                .map(nonisolatedDiscardPublisherValue)
                .eraseToAnyPublisher(),
        ]
        var changes: [AnyPublisher<Void, Never>] = []
        changes.reserveCapacity(stateChanges.count + 3)
        for stateChange in stateChanges {
            changes.append(stateChange.dropFirst().eraseToAnyPublisher())
        }
        changes.append(contentsOf: [
            documentTabController.objectWillChange.eraseToAnyPublisher(),
            discoveryController.objectWillChange.eraseToAnyPublisher(),
            documentPresentationDidChange.eraseToAnyPublisher(),
        ])
        let relay = WindowModelObserverRelay(model: self)
        let persistenceHandler: @Sendable () -> Void = {
            deliverWindowSessionPersistence(to: relay.model)
        }
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink(receiveValue: persistenceHandler)
            .store(in: &workspaceCancellables)
    }

    func adjustDocumentTextScale(by delta: Double) {
        shellState.setDocumentTextScale(documentTextScale + delta)
    }

    func setDocumentTextScale(_ requestedScale: Double) {
        shellState.setDocumentTextScale(requestedScale)
    }

    func resetDocumentTextScale() {
        shellState.resetDocumentTextScale()
    }
}
