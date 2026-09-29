import Foundation
import ScholiumContracts

/// Projection of Document's sessions onto the window's tab strip and
/// selection: what each tab shows, and which tabs survive a library change.
extension WindowModel {
    func synchronizeDocumentTabs(
        after activation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true
    ) {
        guard let document = documentController.selectedDocument else { return }
        let presentation = documentTabPresentation(for: document)
        let previousTabs = documentTabController.tabs
        switch activation {
        case .place(let placement):
            documentTabController.activate(
                document: document,
                title: presentation.title,
                toolTip: presentation.toolTip,
                placement: isDetachedDocumentWindow ? .replaceSelected : placement
            )
            if !libraryMutationController.isCreatingNote {
                scheduleLibraryReveal(for: document)
            }
        case .preserveTabMembership:
            documentTabController.updateDocumentProjection(
                document,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        }
        if recordsNavigationHistory {
            if let departing = documentNavigationHistoryController.currentDocument,
                departing != document
            {
                documentNavigationHistoryController.captureCurrent(
                    document: departing,
                    position: documentController.navigationPosition(for: departing)
                )
            }
            documentNavigationHistoryController.record(document)
        }
        let openTargets = Set(documentTabController.tabs.map { $0.document.editingTarget })
        for tab in previousTabs where !openTargets.contains(tab.document.editingTarget) {
            documentController.endClosedPresentation(of: tab.document)
        }
        reconcileDocumentSessionLeases()
        PerformanceProbe.shared.markFirstReadDocumentSelected(
            documentID: document.relativePath
        )
    }

    /// Every successful in-app document activation converges on this one
    /// presentation path. It changes only Library presentation: the target
    /// vault and Library view, filters that hide the selected Note, folder
    /// disclosure, and the minimum scroll needed to expose its row.
    private func scheduleLibraryReveal(for document: WindowSelectedDocument) {
        libraryRevealTask?.cancel()
        libraryRevealTask = Task { [weak self] in
            guard let self else { return }
            await self.revealDocumentInLibrary(document)
        }
    }

    private func revealDocumentInLibrary(_ document: WindowSelectedDocument) async {
        guard let vaultID = document.vaultID,
            workspaceProjectionController.cachedNote(
                vaultID: vaultID,
                stableNoteID: document.sessionKey?.noteID,
                relativePath: document.relativePath
            ) != nil,
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == vaultID
            }),
            let slot = workspaceSlot(for: vault)
        else { return }

        let scope = LibraryDisclosureScope(
            vaultID: vaultID,
            sourceScope: .library
        )
        let needsProjection =
            currentRegisteredVault?.id != vaultID
            || discoveryController.library.sourceScope != .library
            || discoveryController.libraryRequestIsActive

        if needsProjection {
            let request = discoveryController.beginLibraryRequest(
                workspaceSlot: slot,
                sourceScope: .library,
                presentation: .stagedReplacement
            )
            do {
                try await browseRegisteredVault(
                    vault,
                    slot: slot,
                    libraryRequest: request
                )
            } catch is CancellationError {
                return
            } catch {
                guard discoveryController.isCurrentLibraryRequest(request) else { return }
                discoveryController.failLibraryRequest(
                    error.localizedDescription,
                    for: request
                )
                reportOperationIssue(
                    String(
                        localized: "Could not reveal the current note. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
                    kind: .error
                )
                return
            }
        }

        guard !Task.isCancelled,
            documentController.selectedDocument == document,
            currentRegisteredVault?.id == vaultID,
            discoveryController.library.sourceScope == .library
        else { return }

        let clearsFilters = !filteredNotes.contains {
            $0.relativePath == document.relativePath
        }
        discoveryController.prepareLibraryNoteReveal(
            relativePath: document.relativePath,
            folderAncestors: libraryFolderAncestors(
                forDocumentPath: document.relativePath
            ),
            clearFilters: clearsFilters,
            in: scope
        )
    }

    func reconcileDocumentSessionLeases() {
        documentController.reconcileSessionLeases(
            leasedDocuments: documentTabController.tabs.map(\.document),
            selectedDocument: documentTabController.selectedTab?.document
        )
        releaseEditorActionsIfInvalid()
    }

    func removeDocumentTabs(
        vaultID: UUID,
        removedPaths: Set<String>
    ) async throws {
        let matchingTabs = Dictionary(
            uniqueKeysWithValues: documentTabController.tabs.compactMap { tab -> (UUID, DocumentEditingTarget)? in
                guard let descriptor = tab.document.workspaceDescriptor,
                    descriptor.reference.vaultID == vaultID,
                    removedPaths.contains(descriptor.reference.relativePath)
                else {
                    return nil
                }
                return (tab.id, tab.document.editingTarget)
            })
        guard !matchingTabs.isEmpty else {
            if currentDocumentVaultID == vaultID {
                documentController.clearSelection(forRemovedPaths: removedPaths)
            }
            reconcileDocumentSessionLeases()
            return
        }
        try await removeDocumentTabs(matching: matchingTabs)
    }

    func removeDocumentTabs(matching expectedTabs: [UUID: DocumentEditingTarget]) async throws {
        let matchingIDs = Set(
            documentTabController.tabs.compactMap { tab in
                expectedTabs[tab.id] == tab.document.editingTarget ? tab.id : nil
            })
        guard !matchingIDs.isEmpty else {
            reconcileDocumentSessionLeases()
            return
        }

        // Remove inactive pages first so the selected page's close plan can
        // never choose another document that was deleted in the same commit.
        let selectedID = documentTabController.selectedTabID
        let inactiveIDs = matchingIDs.subtracting(Set([selectedID].compactMap { $0 }))
        let removedInactive = documentTabController.tabs.filter { inactiveIDs.contains($0.id) }
        documentTabController.removeTabs(withIDs: inactiveIDs)
        for tab in removedInactive {
            documentController.endClosedPresentation(of: tab.document)
        }
        if let selectedID, matchingIDs.contains(selectedID),
            let plan = documentTabController.closePlan(forTabWithID: selectedID)
        {
            let closingDocument = plan.closingDocument
            let unavailableSnapshotAtStart = documentController.unavailableSnapshot
            if let documentToActivate = plan.documentToActivate {
                do {
                    try await activateResolvedDocument(
                        documentToActivate, tabActivation: .preserveTabMembership
                    )
                } catch {
                    restoreAuthoritativeTabSelection(unavailableSnapshotAtStart: unavailableSnapshotAtStart)
                    throw error
                }
            }
            guard documentTabController.apply(plan) else {
                restoreAuthoritativeTabSelection(unavailableSnapshotAtStart: unavailableSnapshotAtStart)
                throw DocumentControllerError.documentUnavailable
            }
            if plan.selectedTabIDAfterClose == nil {
                documentController.clearSelectionAfterClosingLastTab()
            }
            documentController.endClosedPresentation(of: closingDocument)
        }
        reconcileDocumentSessionLeases()
    }

    func removeExternallyDeletedDocumentTabs(
        _ documents: Set<WindowSelectedDocument>
    ) {
        guard !documents.isEmpty else { return }
        let targets = Set(documents.map(\.editingTarget))
        let matchingTabs = Dictionary(
            uniqueKeysWithValues: documentTabController.tabs.compactMap { tab -> (UUID, DocumentEditingTarget)? in
                targets.contains(tab.document.editingTarget) ? (tab.id, tab.document.editingTarget) : nil
            })
        guard !matchingTabs.isEmpty else { return }
        documentTransitionCoordinator.enqueueCleanup { [weak self] mayActivateNeighbor in
            guard let self else { return }
            guard mayActivateNeighbor() else {
                discardExternallyDeletedTabs(matching: matchingTabs)
                return
            }
            activeDocumentTransitionCurrency = mayActivateNeighbor
            defer { activeDocumentTransitionCurrency = nil }
            do {
                try await removeDocumentTabs(matching: matchingTabs)
            } catch is CancellationError {
                discardExternallyDeletedTabs(matching: matchingTabs)
            } catch {
                discardExternallyDeletedTabs(matching: matchingTabs)
                reportOperationIssue(
                    String(
                        localized:
                            "The deleted note was removed, but Scholium could not activate the adjacent tab. Choose a document to continue. \(error.localizedDescription)",
                        table: "Localizable",
                        bundle: .module
                    ),
                    kind: .warning
                )
            }
        }
    }

    private func discardExternallyDeletedTabs(matching expectedTabs: [UUID: DocumentEditingTarget]) {
        let closingTabs = documentTabController.tabs.filter {
            expectedTabs[$0.id] == $0.document.editingTarget
        }
        let ids = Set(closingTabs.map(\.id))
        documentTabController.removeTabs(withIDs: ids)
        for tab in closingTabs {
            documentController.endClosedPresentation(of: tab.document)
        }
        restoreAuthoritativeTabSelection()
    }

    func refreshDocumentTabProjections() {
        for tab in documentTabController.tabs {
            guard case .workspace(let descriptor) = tab.document,
                let snapshot = workspaceProjectionController.cachedNote(
                    vaultID: descriptor.reference.vaultID,
                    stableNoteID: descriptor.sessionKey.noteID,
                    relativePath: descriptor.reference.relativePath
                ),
                let vault = workspaceAssignment?.vaults.values.first(where: {
                    $0.id == descriptor.reference.vaultID
                })
            else { continue }
            let updated = WindowSelectedDocument.workspace(
                WindowDocumentDescriptor(
                    sessionKey: descriptor.sessionKey,
                    reference: VaultNoteReference(
                        vaultID: vault.id,
                        vaultName: vault.name,
                        vaultRole: vault.role,
                        relativePath: snapshot.id.relativePath,
                        stableNoteID: descriptor.reference.stableNoteID
                    )
                ))
            let presentation = documentTabPresentation(for: updated)
            documentTabController.updateDocumentProjection(
                updated,
                title: presentation.title,
                toolTip: presentation.toolTip
            )
        }
    }

    private func documentTabPresentation(
        for document: WindowSelectedDocument
    ) -> (title: String, toolTip: String) {
        let location: WindowDocumentLocation? =
            if let sessionKey = document.sessionKey {
                workspaceProjectionController.cachedNote(
                    vaultID: sessionKey.vaultID,
                    stableNoteID: sessionKey.noteID,
                    relativePath: document.relativePath
                )
                .map(WindowDocumentLocation.workspace)
            } else {
                document.vaultID.flatMap { vaultID in
                    workspaceProjectionController.cachedNote(
                        vaultID: vaultID, stableNoteID: nil, relativePath: document.relativePath
                    ).map(WindowDocumentLocation.workspace)
                }
            }
        let fallbackTitle = URL(fileURLWithPath: document.relativePath)
            .deletingPathExtension()
            .lastPathComponent
        let title = location?.title ?? location?.displayName ?? fallbackTitle
        let vaultName = document.workspaceDescriptor?.reference.vaultName
        let toolTip = [title, vaultName, document.relativePath]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " — ")
        return (title, toolTip)
    }

    private func documentSessionKey(for path: String) -> DocumentSessionKey? {
        guard let vaultID = currentRegisteredVault?.id,
            let noteID = noteIdentityByPath[path]
        else { return nil }
        return DocumentSessionKey(vaultID: vaultID, noteID: noteID)
    }

    private func documentDescriptor(for path: String) -> WindowDocumentDescriptor? {
        guard let key = documentSessionKey(for: path),
            let vault = currentRegisteredVault
        else { return nil }
        return WindowDocumentDescriptor(
            sessionKey: key,
            reference: VaultNoteReference(
                vaultID: vault.id,
                vaultName: vault.name,
                vaultRole: vault.role,
                relativePath: path,
                stableNoteID: key.noteID.uuidString
            )
        )
    }

    func documentReference(for path: String) -> VaultNoteReference? {
        documentDescriptor(for: path)?.reference
    }

    func selectionDescriptor(for path: String) -> WindowSelectedDocument? {
        if let descriptor = documentDescriptor(for: path) {
            return .workspace(descriptor)
        }
        guard
            let vaultID = notes.first(where: { $0.relativePath == path })?
                .workspaceSnapshot?.id.vaultID ?? currentRegisteredVault?.id
        else {
            return nil
        }
        return .unavailable(vaultID: vaultID, relativePath: path)
    }

    func refreshSelectedDocumentProjection() {
        guard let selectedDocumentPath else { return }
        // Library refreshes must never reinterpret an existing vault-qualified
        // document through the newly browsed vault, especially when two vaults
        // contain the same relative path.
        guard documentController.activeDocument == nil,
            documentController.selectedDocument?.vaultID == currentRegisteredVault?.id
        else { return }
        if let descriptor = documentDescriptor(for: selectedDocumentPath) {
            documentController.selectDocument(.workspace(descriptor))
        } else if documentController.activeDocument == nil,
            let descriptor = selectionDescriptor(for: selectedDocumentPath)
        {
            documentController.selectDocument(descriptor)
        }
        synchronizeDocumentTabs(after: .preserveTabMembership)
    }
}
