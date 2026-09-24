import Foundation
import ScholiumContracts

/// Intents the window receives from menus, search and other windows, and the
/// requests a researcher can make of the currently presented document.
extension WindowModel {
    /// The only cross-feature routing boundary. Feature controllers emit a
    /// closed intent and never reach into a peer controller's mutable state.
    func handleWindowIntent(_ intent: WindowIntent) {
        switch intent {
        case .openDocument(let route):
            if route.disposition == .newTab {
                requestOpenNote(route.reference, disposition: .newTab)
                return
            }
            Task { [weak self] in
                await self?.openWorkspaceReference(
                    route.reference,
                    line: route.sourceLocator?.line
                )
            }
        case .openSearchResult(let result, let disposition):
            Task { [weak self] in
                await self?.searchController.open(result, disposition: disposition)
            }
        case .revealSourceLocator(let vaultID, let locator):
            Task { [weak self] in
                guard let self else { return }
                do {
                    let vault = try await self.workspaceStore.resolveVault(vaultID.uuidString)
                    let reference = VaultNoteReference(
                        vaultID: vault.id,
                        vaultName: vault.name,
                        vaultRole: vault.role,
                        relativePath: locator.file,
                        stableNoteID: nil
                    )
                    await self.openWorkspaceReference(
                        reference,
                        line: locator.line,
                        mode: .source
                    )
                } catch {
                    self.vaultError = error.localizedDescription
                }
            }
        case .switchVault(let vaultID):
            Task { [weak self] in
                guard let self else { return }
                do {
                    let vault = try await self.workspaceStore.resolveVault(vaultID.uuidString)
                    try await self.browseRegisteredVault(vault)
                } catch {
                    self.vaultError = error.localizedDescription
                }
            }
        case .presentNoteFileOperation(let request):
            noteFileRequest = request
        }
    }

    func openSearchSelection(
        _ result: SearchResultSelection,
        disposition: WindowOpenDisposition
    ) async {
        switch result {
        case .result(.note(let note)):
            let reference = VaultNoteReference(
                vaultID: note.vaultID,
                vaultName: note.vaultName,
                vaultRole: note.vaultRole,
                relativePath: note.relativePath,
                stableNoteID: note.stableNoteID
            )
            if disposition == .newTab {
                requestOpenNote(reference, disposition: .newTab)
            } else {
                openWorkspaceReference(
                    reference,
                    sourceRange: note.sourceRange,
                    fallbackLine: note.sourceLine
                )
            }
        }
    }

    func requestOpenNote(
        _ path: String,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        if disposition == .separateWindow, let reference = documentReference(for: path) {
            requestOpenNote(reference, disposition: disposition)
            return
        }
        if let reference = documentReference(for: path),
            workspaceStore.documentLocations.revealExisting(reference, excluding: self)
        {
            return
        }
        if disposition == .newTab {
            guard let reference = documentReference(for: path) else { return }
            requestOpenNote(reference, disposition: .newTab)
            return
        }
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            self.openNote(path)
        }
    }

    func requestOpenNote(
        _ location: WindowDocumentLocation,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        guard let snapshot = location.workspaceSnapshot else {
            requestOpenNote(location.relativePath, disposition: disposition)
            return
        }
        guard
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == snapshot.id.vaultID
            })
        else {
            reportOperationIssue(String(localized: "The selected vault is no longer available.", table: "Localizable", bundle: .module), kind: .warning)
            return
        }
        let reference = VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: snapshot.id.relativePath,
            stableNoteID: snapshot.stableIdentity.resolvedID?.uuidString.lowercased()
        )
        requestOpenNote(reference, disposition: disposition)
    }

    func requestOpenNote(
        _ reference: VaultNoteReference,
        disposition: WindowOpenDisposition = .replaceCurrent
    ) {
        if disposition == .separateWindow {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do { _ = try await workspaceStore.documentLocations.openSeparate(reference, from: self) } catch {
                    reportOperationIssue(error.localizedDescription, kind: .error)
                }
            }
            return
        }
        if workspaceStore.documentLocations.revealExisting(reference, excluding: self) { return }
        if disposition == .newTab {
            openInNewTab(reference)
            return
        }
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            try await self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.replaceSelected)
            )
        }
    }

    func requestOpenNote(
        _ path: String,
        sourceLine: Int,
        mode: NotePresentationMode = .source
    ) {
        if let reference = documentReference(for: path),
            let owner = workspaceStore.documentLocations.existingOwner(of: reference, excluding: self)
        {
            owner.nativeWindowCoordinator?.makeKeyAndOrderFront()
            Task { await owner.openWorkspaceReference(reference, line: sourceLine, mode: mode) }
            return
        }
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            self.openNote(path)
            guard self.selectedDocumentPath == path else { return }
            self.documentController.requestSourceLocation(line: max(1, sourceLine))
            self.requestPresentationMode = mode
        }
    }

    func requestTriptychWorkspace(_ slot: WorkspaceVaultSlot) {
        let destination = discoveryController.libraryState(for: slot)
        guard requestedWorkspaceSelection != slot,
            shellState.selectedWorkspace != slot
                || requestedWorkspaceSelection != nil
                || destination.sourceError != nil
        else { return }
        requestedWorkspaceSelection = slot
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try await self.prepareWorkspaceSelection(
                slot,
                sourceScope: destination.sourceScope,
                validateDestination: {
                    guard self.requestedWorkspaceSelection == slot else {
                        throw CancellationError()
                    }
                }
            )
            self.reconcileDocumentSessionLeases()
        } didFinish: { [weak self] in
            guard self?.requestedWorkspaceSelection == slot else { return }
            self?.requestedWorkspaceSelection = nil
        }
    }

    func requestLibrarySourceScope(_ scope: LibrarySourceScope) {
        Task { [weak self] in await self?.selectLibrarySourceScope(scope) }
    }

    func requestDocumentMode(_ mode: NotePresentationMode) {
        guard !transferInProgress else { return }
        guard mode == .read || canEditCurrentNote else {
            reportOperationIssue(String(localized: "This note is read-only in Scholium.", table: "Localizable", bundle: .module), kind: .information)
            return
        }
        requestPresentationMode = mode
    }

    func currentSearchResultEvidence(
        for result: SearchResult,
        scope: SearchPresentationScope
    ) async -> WindowSearchResultEvidence {
        switch result {
        case .note(let note):
            if scope == .thisNote {
                let snapshot = try? await currentSearchSourceSnapshot()
                return WindowSearchResultEvidence(
                    freshness: snapshot.map(SearchFreshnessToken.currentNote),
                    fingerprint: snapshot?.fingerprint
                )
            }
            let discovery = try? await discoveryController.discoverySnapshot()
            let cached = workspaceProjectionController.cachedNote(
                vaultID: note.vaultID,
                stableNoteID: note.stableNoteID.flatMap(UUID.init(uuidString:)),
                relativePath: note.relativePath
            )
            let freshness =
                discovery?.searchGeneration.map(
                    SearchFreshnessToken.triptych
                )
                ?? (workspaceProjectionController.snapshotPhase?.isComplete == false
                    && cached?.fingerprint == note.fingerprint
                    ? note.freshnessToken
                    : nil)
            return WindowSearchResultEvidence(
                freshness: freshness,
                fingerprint: cached?.fingerprint
            )
        }
    }

    /// Captures CodeMirror's checked in-memory source without flushing or
    /// saving it. Identity is rechecked after the asynchronous bridge query so
    /// a superseded tab cannot become This Note Search authority.
    func currentSearchSourceSnapshot() async throws -> SearchSourceSnapshot? {
        guard let descriptor = currentDocumentDescriptor,
            let note = currentNote
        else { return nil }
        let session = documentController.session(for: descriptor)
        let sessionID = session.editorSession.sessionID
        let source: String
        if session.isEditing || session.editorSession.hasRecoverableBuffer {
            source = try await session.editorSession.currentText(
                for: session.editorSession.bridgeDocumentID
            )
        } else {
            source = note.rawContent
        }
        guard currentDocumentDescriptor?.sessionKey == descriptor.sessionKey,
            documentController.session(for: descriptor) === session,
            session.editorSession.sessionID == sessionID
        else {
            throw CancellationError()
        }
        return SearchSourceSnapshot(
            noteID: VaultQualifiedNoteID(
                vaultID: descriptor.reference.vaultID,
                relativePath: note.relativePath
            ),
            stableNoteID: note.workspaceSnapshot?.stableIdentity.resolvedID,
            editorSessionID: sessionID,
            source: source,
            editorRevision: UInt64(max(0, session.editorSession.generation)),
        )
    }
}
