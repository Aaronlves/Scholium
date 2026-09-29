import Foundation
import ScholiumContracts

/// Document tabs as the researcher moves through them: transfer between
/// windows, selection, navigation history and closing.
extension WindowModel {
    func openInNewTab(_ reference: VaultNoteReference) {
        enqueueDocumentTransition { [weak self] in
            guard let self else { return }
            try await self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.newTab)
            )
        }
    }

    func waitForDocumentTransitions() async {
        await documentTransitionCoordinator.waitForIdle()
    }

    /// A failed async close must leave the displayed document aligned with
    /// the authoritative tab selection, including a tab replaced while waiting.
    @discardableResult
    func restoreAuthoritativeTabSelection(
        unavailableSnapshotAtStart: WorkspaceNoteSnapshot? = nil
    ) -> Bool {
        guard let selected = documentTabController.selectedTab?.document else {
            documentController.clearSelectionAfterClosingLastTab()
            reconcileDocumentSessionLeases()
            return true
        }
        if documentController.selectedDocument != selected {
            let restored =
                documentController.selectRetainedDocument(selected)
                || unavailableSnapshotAtStart.map {
                    workspaceProjectionController.cachedNote(
                        vaultID: $0.id.vaultID,
                        stableNoteID: nil,
                        relativePath: $0.id.relativePath
                    )?.fingerprint == $0.fingerprint
                        && documentController.restoreRetainedUnavailableDocument(selected, snapshot: $0)
                } == true
            guard restored else {
                documentController.clearSelectionAfterClosingLastTab()
                reconcileDocumentSessionLeases()
                return false
            }
        }
        if let vaultID = selected.vaultID,
            let vault = workspaceAssignment?.vaults.values.first(where: { $0.id == vaultID }),
            let workspace = workspaceSlot(for: vault)
        {
            documentController.selectWorkspace(workspace)
            shellState.selectDocumentWorkspace(workspace)
        }
        reconcileDocumentSessionLeases()
        return true
    }

    func requestMoveDocumentToWindow(tabID: UUID? = nil, at point: NSPoint? = nil) {
        guard let id = tabID ?? documentTabController.selectedTabID else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await workspaceStore.documentLocations.moveTab(id, from: self, at: point) } catch {
                reportOperationIssue(error.localizedDescription, kind: .error)
            }
        }
    }

    func requestMoveDocumentBack() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await workspaceStore.documentLocations.moveBack(from: self) } catch { reportOperationIssue(error.localizedDescription, kind: .error) }
        }
    }

    /// Select the retained neighbor before releasing the outgoing session.
    /// Native toolbar observers must never see an artificial empty document
    /// between two real selections during a move.
    func takeDocumentForTransfer(tabID: UUID) async throws -> DocumentSessionTransfer {
        guard let tab = documentTabController.tabs.first(where: { $0.id == tabID }),
            let plan = documentTabController.closePlan(forTabWithID: tabID)
        else { throw DocumentControllerError.documentUnavailable }
        let previous = documentController.selectedDocument
        let unavailableSnapshotAtStart = documentController.unavailableSnapshot
        if previous == tab.document {
            documentNavigationHistoryController.captureCurrent(
                document: tab.document,
                position: documentController.navigationPosition(for: tab.document)
            )
        }
        do {
            if let next = plan.documentToActivate {
                try await activateResolvedDocument(next, tabActivation: .preserveTabMembership)
            }
        } catch {
            restoreAuthoritativeTabSelection(unavailableSnapshotAtStart: unavailableSnapshotAtStart)
            throw error
        }
        guard documentTabController.closePlan(forTabWithID: tabID) == plan else {
            restoreAuthoritativeTabSelection(unavailableSnapshotAtStart: unavailableSnapshotAtStart)
            throw DocumentControllerError.documentUnavailable
        }
        guard let transfer = documentController.takeSessionForTransfer(tab.document) else {
            restoreAuthoritativeTabSelection(unavailableSnapshotAtStart: unavailableSnapshotAtStart)
            throw DocumentControllerError.documentUnavailable
        }
        guard documentTabController.apply(plan) else {
            documentController.receiveSessionTransfer(transfer, selecting: false)
            restoreAuthoritativeTabSelection(unavailableSnapshotAtStart: unavailableSnapshotAtStart)
            throw DocumentControllerError.documentUnavailable
        }
        reconcileDocumentSessionLeases()
        return transfer
    }

    func finishIncomingTransfer(_ transfer: DocumentSessionTransfer, tab: DocumentTabItem) {
        if let descriptor = transfer.document.workspaceDescriptor,
            let vault = workspaceAssignment?.vaults.values.first(where: { $0.id == descriptor.reference.vaultID }),
            let workspace = workspaceSlot(for: vault)
        {
            documentController.selectWorkspace(workspace)
            shellState.selectDocumentWorkspace(workspace)
        }
        documentController.receiveSessionTransfer(transfer)
        documentTabController.insertTransferredTab(tab)
        documentNavigationHistoryController.record(transfer.document)
        reconcileDocumentSessionLeases()
    }

    func selectAdjacentDocumentTab(offset: Int) {
        let tabs = documentTabController.tabs
        guard let index = tabs.firstIndex(where: { $0.id == documentTabController.selectedTabID }),
            tabs.count > 1
        else { return }
        selectDocumentTab(withID: tabs[(index + offset + tabs.count) % tabs.count].id)
    }

    func selectDocumentTab(
        withID id: UUID,
        historyPosition: DocumentNavigationVisitPosition? = nil,
        onSelection: (@MainActor (Bool) -> Void)? = nil
    ) {
        if documentTabController.selectedTabID == id,
            documentController.selectedDocument == documentTabController.selectedTab?.document
        {
            if let historyPosition,
                let document = documentTabController.selectedTab?.document
            {
                documentController.restoreNavigationPosition(historyPosition, for: document)
            }
            onSelection?(true)
            return
        }
        var activated = false
        enqueueDocumentTransition(preparation: .preserveSelectedDocument) { [weak self] in
            guard let self,
                self.documentTabController.selectedTabID != id
                    || self.documentController.selectedDocument != self.documentTabController.selectedTab?.document,
                let tab = self.documentTabController.tabs.first(where: { $0.id == id })
            else { return }
            try await self.activateDocument(
                tab.document, tabActivation: .preserveTabMembership
            )
            self.documentTabController.selectTab(withID: id)
            if let historyPosition {
                self.documentController.restoreNavigationPosition(historyPosition, for: tab.document)
            }
            self.reconcileDocumentSessionLeases()
            activated = true
        } didFinish: {
            onSelection?(activated)
        }
    }

    func navigateDocumentHistory(_ direction: DocumentNavigationDirection) {
        if let displayed = documentController.selectedDocument {
            documentNavigationHistoryController.captureCurrent(
                document: displayed,
                position: documentController.navigationPosition(for: displayed)
            )
        }
        let historyRevision = documentNavigationHistoryController.revision
        if let target = documentNavigationHistoryController.target(for: direction),
            workspaceStore.documentLocations.revealExisting(
                target,
                excluding: self,
                onSelection: { [weak self] owner, selected in
                    guard let self, selected,
                        self.documentNavigationHistoryController.revision == historyRevision,
                        self.documentNavigationHistoryController.target(for: direction) == target
                    else { return }
                    let position = self.documentNavigationHistoryController.position(for: direction)
                    if self.documentNavigationHistoryController.commit(direction, to: target) {
                        owner.documentController.restoreNavigationPosition(position, for: target)
                    }
                }
            )
        {
            return
        }
        enqueueDocumentTransition { [weak self] in
            guard let self,
                let target = self.documentNavigationHistoryController.target(
                    for: direction
                )
            else { return }
            let position = self.documentNavigationHistoryController.position(for: direction)
            try await self.activateDocument(
                target,
                tabActivation: .place(.replaceSelected),
                recordsNavigationHistory: false
            )
            if self.documentNavigationHistoryController.commit(direction, to: target) {
                self.documentController.restoreNavigationPosition(position, for: target)
            }
        }
    }

    func closeDocumentTab(withID id: UUID) {
        enqueueDocumentTransition(preparation: .operationOnly) { [weak self] in
            guard let self,
                let closingDocument = self.documentTabController.tabs.first(where: {
                    $0.id == id
                })?.document
            else { return }
            try await self.documentController.flushBeforeClosing(closingDocument)
            self.documentNavigationHistoryController.captureCurrent(
                document: closingDocument,
                position: self.documentController.navigationPosition(for: closingDocument)
            )
            guard let plan = self.documentTabController.closePlan(forTabWithID: id),
                plan.closingDocument == closingDocument
            else { throw DocumentControllerError.documentUnavailable }
            let unavailableSnapshotAtStart = self.documentController.unavailableSnapshot
            if let documentToActivate = plan.documentToActivate {
                do {
                    try await self.activateDocument(
                        documentToActivate, tabActivation: .preserveTabMembership
                    )
                } catch {
                    self.restoreAuthoritativeTabSelection(unavailableSnapshotAtStart: unavailableSnapshotAtStart)
                    throw error
                }
            }
            guard self.documentTabController.apply(plan) else {
                self.restoreAuthoritativeTabSelection(unavailableSnapshotAtStart: unavailableSnapshotAtStart)
                throw DocumentControllerError.documentUnavailable
            }
            if plan.selectedTabIDAfterClose == nil {
                self.documentController.clearSelectionAfterClosingLastTab()
            }
            self.documentController.endClosedPresentation(of: closingDocument)
            self.reconcileDocumentSessionLeases()
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.documentController.reapDetachedSessions()
            }
        }
    }
}
