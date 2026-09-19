import Foundation
import ScholiumContracts

/// Opening a Triptych: selecting a workspace slot, staging and committing a
/// registered vault, and loading the library that selection makes visible.
extension WindowModel {
    func openWorkspaceVault(_ slot: WorkspaceVaultSlot) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        try await openRegisteredVault(vault)
    }

    func prepareWorkspaceSelection(
        _ slot: WorkspaceVaultSlot,
        sourceScope: LibrarySourceScope,
        validateDestination: () throws -> Void = {}
    ) async throws {
        guard let vault = workspaceAssignment?.vault(for: slot) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let request = discoveryController.beginLibraryRequest(
            workspaceSlot: slot,
            sourceScope: sourceScope,
            presentation: .stagedReplacement
        )
        do {
            let staged = try await stageRegisteredVault(
                vault,
                slot: slot,
                libraryRequest: request
            )
            try validateDestination()
            try commitStagedWorkspaceLibrarySelection(staged)
        } catch {
            if discoveryController.isCurrentLibraryRequest(request) {
                discoveryController.failLibraryRequest(
                    error.localizedDescription,
                    for: request
                )
            }
            throw error
        }
        shellState.selectLibraryWorkspace(slot)
        attentionPresentationState.selectWorkspaceSlot(slot)
        await refreshIdentityState()
        scheduleWorkspaceCatalogRefresh()
    }

    func validateDocumentIsAvailable(
        _ document: WindowSelectedDocument
    ) throws {
        guard let vaultID = document.vaultID,
            workspaceProjectionController.cachedNote(
                vaultID: vaultID,
                stableNoteID: document.sessionKey?.noteID,
                relativePath: document.relativePath
            ) != nil
        else {
            throw WindowNavigationError.noteUnavailable(document.relativePath)
        }
    }

    /// Reprojects Library onto another Triptych vault without touching the
    /// selected document. The target snapshot is staged completely before the
    /// browsed-vault identity changes, so a failed browse leaves both Library
    /// and the open editor intact.
    func browseRegisteredVault(
        _ registered: RegisteredVault,
        slot: WorkspaceVaultSlot? = nil,
        libraryRequest: DiscoveryLibraryRequest? = nil
    ) async throws {
        let staged = try await stageRegisteredVault(
            registered,
            slot: slot,
            libraryRequest: libraryRequest
        )
        try commitStagedWorkspaceLibrarySelection(staged)
        await refreshIdentityState()
        scheduleWorkspaceCatalogRefresh()
    }

    private func stageRegisteredVault(
        _ registered: RegisteredVault,
        slot: WorkspaceVaultSlot? = nil,
        libraryRequest: DiscoveryLibraryRequest? = nil
    ) async throws -> StagedWorkspaceLibrarySelection {
        let vaultSnapshot = try await currentWorkspaceVaultSnapshot(
            vaultID: registered.id
        )
        let targetConfig = await windowWorkspaceController.vaultConfig(
            rootURL: URL(
                fileURLWithPath: registered.canonicalPath,
                isDirectory: true
            )
        )
        if let libraryRequest,
            !discoveryController.isCurrentLibraryRequest(libraryRequest)
        {
            throw CancellationError()
        }

        guard let resolvedSlot = slot ?? workspaceSlot(for: registered) else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let targetSourceScope =
            libraryRequest?.sourceScope
            ?? discoveryController.libraryState(for: resolvedSlot).sourceScope
        let targetNotes = vaultSnapshot.documents
            .map(WindowDocumentLocation.workspace)
            .sorted(by: notesAreOrdered)

        if let libraryRequest,
            !discoveryController.isCurrentLibraryRequest(libraryRequest)
        {
            throw CancellationError()
        }
        return StagedWorkspaceLibrarySelection(
            registeredVault: registered,
            workspace: resolvedSlot,
            sourceScope: targetSourceScope,
            vaultSnapshot: vaultSnapshot,
            vaultConfig: targetConfig,
            notes: targetNotes,
            request: libraryRequest
        )
    }

    private func commitStagedWorkspaceLibrarySelection(
        _ staged: StagedWorkspaceLibrarySelection
    ) throws {
        if let request = staged.request,
            !discoveryController.isCurrentLibraryRequest(request)
        {
            throw CancellationError()
        }
        currentRegisteredVault = staged.registeredVault
        currentVaultRole = staged.registeredVault.role
        vaultConfig = staged.vaultConfig
        if let request = staged.request {
            guard discoveryController.receiveLibraryResult(for: request) else {
                throw CancellationError()
            }
        } else {
            discoveryController.synchronizeLibrarySelection(
                workspaceSlot: staged.workspace,
                sourceScope: staged.sourceScope
            )
        }
        attentionPresentationState.selectWorkspaceSlot(staged.workspace)
        workspaceProjectionController.commitVaultSelection(
            snapshot: staged.vaultSnapshot,
            notes: staged.notes
        )
    }

    func workspaceSlot(for vault: RegisteredVault) -> WorkspaceVaultSlot? {
        WorkspaceVaultSlot.allCases.first { slot in
            guard let assigned = workspaceAssignment?.vault(for: slot) else { return false }
            return assigned.id == vault.id || assigned.canonicalPath == vault.canonicalPath
        }
    }

    func openRegisteredVault(_ vault: RegisteredVault) async throws {
        // The Workspace controller resolves and retains the one capability
        // session. This root applies only the selected Library projection.
        try await loadVault(vault)
    }

    func refreshWorkspaceCatalog() async {
        await workspaceProjectionController.refreshCatalog()
    }

    private func loadVault(_ registered: RegisteredVault) async throws {
        isLoading = true
        vaultError = nil
        do {
            guard let assignment = workspaceAssignment else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            let session = try await windowWorkspaceController.activeSession(
                for: assignment,
                openingVault: workspaceSlot(for: registered) ?? shellState.selectedWorkspace
            )
            let capabilities = session.capabilities
            let workspaceSnapshot = session.snapshot
            let workspaceVaultSnapshots = workspaceSnapshot.vaults
            guard
                let vaultSnapshot = workspaceVaultSnapshots.first(where: {
                    $0.vault.id == registered.id
                })
            else {
                throw WorkspaceRegistryError.incompleteWorkspace
            }
            // Stage the complete target runtime and inventory before replacing
            // any visible window state. A failed vault open must leave the
            // current Triptych document and editor intact.
            let targetNotes = vaultSnapshot.documents
                .map(WindowDocumentLocation.workspace)
                .sorted {
                    $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
                }
            let targetConfig = await windowWorkspaceController.vaultConfig(
                rootURL: URL(
                    fileURLWithPath: registered.canonicalPath,
                    isDirectory: true
                )
            )
            PerformanceProbe.shared.markVaultConfigurationReady()

            resetWindowSession()

            workspaceProjectionController.replaceVaultSnapshots(workspaceVaultSnapshots)
            if let slot = workspaceSlot(for: registered) {
                discoveryController.synchronizeLibrarySelection(
                    workspaceSlot: slot,
                    sourceScope: .library
                )
                shellState.selectWorkspace(slot)
                documentController.selectWorkspace(slot)
                attentionPresentationState.selectWorkspaceSlot(slot)
            }
            currentRegisteredVault = registered
            currentVaultRole = registered.role
            vaultConfig = targetConfig
            workspaceProjectionController.replaceVisibleNotes(targetNotes)
            let commit = workspaceProjectionController.activate(
                snapshot: workspaceSnapshot,
                runtimeIdentity: capabilities.runtimeIdentity,
                context: workspaceProjectionContext
            )
            applyWorkspaceProjectionCommit(commit)
            PerformanceProbe.shared.markWarmLibraryProjectionReady()
            isLoading = false
            // `activate` has already published the authoritative catalog and
            // all Vault snapshots, and identity state was refreshed above.
            // Do not hold initial document restoration behind a duplicate
            // window refresh; later Workspace generations own reconciliation.
            if !workspaceSnapshot.research.healthIssues.isEmpty {
                vaultError = workspaceSnapshot.research.healthIssues.joined(separator: "\n\n")
            }
        } catch {
            isLoading = false
            refreshStatusText = nil
            vaultError = error.localizedDescription
            throw error
        }
    }

    func restoreWorkspaceIfNeeded() async {
        guard
            windowWorkspaceController.beginInitialRestoreIfNeeded(
                isConfigured: vaultConfig != nil
            )
        else { return }
        if let root = ScholiumRuntimeIsolation.fixtureRootURL() {
            do {
                let analysesURL = root.appendingPathComponent(
                    "01-analyses",
                    isDirectory: true
                )
                let topicsURL = root.appendingPathComponent(
                    "02-topics",
                    isDirectory: true
                )
                let worksURL = root.appendingPathComponent(
                    "03-works",
                    isDirectory: true
                )
                let fixtureURLs: [WorkspaceVaultSlot: URL] = [
                    .paperAnalysis: analysesURL,
                    .topicKnowledge: topicsURL,
                    .output: worksURL,
                ]
                await windowWorkspaceController.refreshRegistrations()
                let registered = registeredTriptychs.first { assignment in
                    WorkspaceVaultSlot.allCases.allSatisfy { slot in
                        guard let expected = fixtureURLs[slot],
                            let actual = assignment.vault(for: slot)
                        else { return false }
                        return actual.canonicalPath
                            == expected.resolvingSymlinksInPath()
                            .standardizedFileURL.path
                    }
                }
                if let registered,
                    let openingVault = registered.vault(for: requestedInitialWorkspaceSlot)
                {
                    shellState.selectWorkspace(requestedInitialWorkspaceSlot)
                    await refreshWorkspaceAssignment(preferredTriptychID: registered.id)
                    guard workspaceAssignment?.id == registered.id else {
                        throw WorkspaceRegistryError.incompleteWorkspace
                    }
                    try await openRegisteredVault(openingVault)
                } else {
                    try await configureTriptych(
                        paperAnalysisURL: analysesURL,
                        topicKnowledgeURL: topicsURL,
                        outputURL: worksURL,
                        portableContainerURL: root
                    )
                }
                // Either the already-registered reopen or `configureTriptych`
                // opens the requested Vault exactly once before this route.
                preparePerformancePresentationModeIfNeeded()
                openRequestedTestNoteIfNeeded()
            } catch {
                vaultError = error.localizedDescription
            }
            return
        }
        await windowWorkspaceController.refreshRegistrations()
        await refreshWorkspaceAssignment()
        guard workspaceAssignment != nil else {
            return
        }

        do {
            try await openWorkspaceVault(.paperAnalysis)
            openRequestedTestNoteIfNeeded()
        } catch {
            if windowWorkspaceController.recordRecovery(for: error) {
                vaultError = nil
            } else {
                vaultError = error.localizedDescription
            }
        }
    }

    var requestedInitialWorkspaceSlot: WorkspaceVaultSlot {
        let allowsRequestedSlot: Bool = {
            #if DEBUG
                true
            #else
                PerformanceProbe.shared.isEnabled
            #endif
        }()
        guard allowsRequestedSlot,
            let rawValue = ProcessInfo.processInfo.environment[
                "SCHOLIUM_UI_TEST_OPEN_SLOT"
            ],
            let requested = WorkspaceVaultSlot(rawValue: rawValue)
        else {
            return shellState.selectedWorkspace
        }
        return requested
    }

    func openRequestedTestNoteIfNeeded() {
        // A native-tab route owns its explicit initial document. The general
        // QA launch note applies only to un-routed windows; opening it first
        // would create a transient, incorrect tab identity before the routed
        // document replaces it.
        guard !isDetachedDocumentWindow, requestedInitialDocument == nil,
            let requested = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_OPEN_NOTE"]
        else { return }
        let path =
            requested == "first"
            ? notes.sorted(by: notesAreOrdered).first?.relativePath
            : requested
        if let path { openNote(path) }
    }

    private func preparePerformancePresentationModeIfNeeded() {
        guard PerformanceProbe.shared.requiresInitialReviewPresentation else {
            return
        }
        documentController.rememberPresentationMode(.read)
    }

    func refreshWindowProjection() async {
        // `WorkspaceStore` publishes the authoritative Triptych index and
        // Triptych graph. Keep this method as a window projection refresh for
        // existing callers; it must not create a second graph or index.
        projectionRefreshToken &+= 1
        let refreshToken = projectionRefreshToken
        let startingVaultID = currentRegisteredVault?.id
        await refreshIdentityState()
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }

        if let catalog = try? await discoveryController.discoverySnapshot().catalog {
            workspaceProjectionController.replaceCatalog(catalog)
        }
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }
        if let vaultID = startingVaultID,
            let vault = try? await documentController.workspaceSnapshot(vaultID: vaultID)
        {
            let snapshots = Dictionary(uniqueKeysWithValues: vault.documents.map { ($0.id.relativePath, $0) })
            workspaceProjectionController.refreshVisibleNoteSnapshots(snapshots)
        }
        guard refreshToken == projectionRefreshToken, currentRegisteredVault?.id == startingVaultID else { return }

        if noteSourceScope == .library, workspaceAssignment != nil {
            scheduleWorkspaceCatalogRefresh()
        }

        // Render on demand. Prewarming every note here runs on the main actor
        // and makes a successful save appear stuck while unrelated documents
        // are rendered.
    }

    func scheduleWorkspaceCatalogRefresh() {
        workspaceProjectionController.scheduleCatalogRefresh()
    }

    func selectLibrarySourceScope(_ scope: LibrarySourceScope) async {
        guard let workspaceSlot = currentWorkspaceSlot else { return }
        guard
            scope != noteSourceScope
                || discoveryController.library.sourceError != nil
        else { return }
        let request = discoveryController.beginLibraryRequest(
            workspaceSlot: workspaceSlot,
            sourceScope: scope,
            presentation: .stagedReplacement
        )
        do {
            let loaded = try await loadNotes(
                for: scope,
                vaultID: currentRegisteredVault?.id
            )
            guard discoveryController.receiveLibraryResult(for: request) else { return }
            workspaceProjectionController.replaceVisibleNotes(
                loaded.sorted(by: notesAreOrdered)
            )
            await refreshIdentityState()
            await refreshWindowProjection()
        } catch {
            discoveryController.failLibraryRequest(
                error.localizedDescription,
                for: request
            )
            reportOperationIssue(
                String(localized: "Could not open \(scope.rawValue): \(error.localizedDescription)", table: "Localizable", bundle: .module), kind: .error)
        }
    }

    func refreshLibrarySourceScope() async throws {
        guard let workspaceSlot = currentWorkspaceSlot else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let request = discoveryController.beginLibraryRequest(
            workspaceSlot: workspaceSlot,
            sourceScope: noteSourceScope
        )
        let loaded: [WindowDocumentLocation]
        do {
            loaded = try await loadNotes(
                for: request.sourceScope,
                vaultID: currentRegisteredVault?.id
            )
        } catch {
            discoveryController.failLibraryRequest(error.localizedDescription, for: request)
            throw error
        }
        guard discoveryController.receiveLibraryResult(for: request) else { return }
        workspaceProjectionController.replaceVisibleNotes(
            loaded.sorted(by: notesAreOrdered)
        )
        await refreshIdentityState()
        await refreshWindowProjection()
    }

    private func loadNotes(
        for scope: LibrarySourceScope,
        vaultID: UUID?
    ) async throws -> [WindowDocumentLocation] {
        guard let vaultID else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        let vault = try await currentWorkspaceVaultSnapshot(vaultID: vaultID)
        return vault.documents
            .map(WindowDocumentLocation.workspace)
    }

    /// Window publication is the first source for ordinary navigation. The
    /// Application operation remains the fallback when initial construction
    /// has not yet installed that immutable snapshot.
    private func currentWorkspaceVaultSnapshot(
        vaultID: UUID
    ) async throws -> WorkspaceVaultSnapshot {
        if let snapshot = workspaceProjectionController.vaultSnapshot(id: vaultID) {
            return snapshot
        }
        guard
            let snapshot = try await documentController.workspaceSnapshot(
                vaultID: vaultID
            )
        else {
            throw WorkspaceRegistryError.incompleteWorkspace
        }
        return snapshot
    }
}
