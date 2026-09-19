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
    func takeDocumentForTransfer(tabID: UUID) throws -> DocumentSessionTransfer {
        guard let tab = documentTabController.tabs.first(where: { $0.id == tabID }),
            let plan = documentTabController.closePlan(forTabWithID: tabID)
        else { throw DocumentControllerError.documentUnavailable }
        let previous = documentController.selectedDocument
        if let next = plan.documentToActivate {
            try activateResolvedDocument(next, tabActivation: .preserveTabMembership)
        }
        guard let transfer = documentController.takeSessionForTransfer(tab.document) else {
            if let previous { _ = documentController.selectRetainedDocument(previous) }
            throw DocumentControllerError.documentUnavailable
        }
        documentTabController.apply(plan)
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

    func selectDocumentTab(withID id: UUID) {
        guard documentTabController.selectedTabID != id else { return }
        enqueueDocumentTransition(preparation: .preserveSelectedDocument) { [weak self] in
            guard let self,
                self.documentTabController.selectedTabID != id,
                let tab = self.documentTabController.tabs.first(where: { $0.id == id })
            else { return }
            try await self.activateDocument(
                tab.document, tabActivation: .preserveTabMembership
            )
            self.documentTabController.selectTab(withID: id)
            self.reconcileDocumentSessionLeases()
        }
    }

    func navigateDocumentHistory(_ direction: DocumentNavigationDirection) {
        if let target = documentNavigationHistoryController.target(for: direction),
            workspaceStore.documentLocations.revealExisting(target, excluding: self)
        {
            documentNavigationHistoryController.commit(direction, to: target)
            return
        }
        enqueueDocumentTransition { [weak self] in
            guard let self,
                let target = self.documentNavigationHistoryController.target(
                    for: direction
                )
            else { return }
            try await self.activateDocument(
                target,
                tabActivation: .place(.replaceSelected),
                recordsNavigationHistory: false
            )
            self.documentNavigationHistoryController.commit(direction, to: target)
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
            guard let plan = self.documentTabController.closePlan(forTabWithID: id) else {
                return
            }
            if let documentToActivate = plan.documentToActivate {
                try await self.activateDocument(
                    documentToActivate, tabActivation: .preserveTabMembership
                )
            } else if plan.selectedTabIDAfterClose == nil {
                self.documentController.clearSelectionAfterClosingLastTab()
            }
            self.documentTabController.apply(plan)
            self.reconcileDocumentSessionLeases()
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.documentController.reapDetachedSessions()
            }
        }
    }
}
