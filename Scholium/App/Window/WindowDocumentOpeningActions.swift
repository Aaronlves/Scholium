import Foundation
import ScholiumContracts

/// Opening what a researcher points at: a note, a workspace reference, an
/// internal link, an agent's change, or a path handed to the system.
extension WindowModel {
    func openNote(
        _ path: String,
        tabActivation: DocumentTabActivation = .place(.replaceSelected)
    ) {
        guard !transferInProgress else { return }
        if let descriptor = selectionDescriptor(for: path),
            workspaceStore.documentLocations.revealExisting(descriptor, excluding: self)
        {
            return
        }
        guard let location = notes.first(where: { $0.relativePath == path }) else {
            reportOperationIssue(String(localized: "Note not found: \(path)", table: "Localizable", bundle: .module), kind: .warning)
            return
        }
        PerformanceProbe.shared.beginReadActivation(documentID: path)
        if let snapshot = location.workspaceSnapshot,
            snapshot.stableIdentity.resolvedID != nil,
            let vault = currentRegisteredVault
        {
            if let workspace = workspaceSlot(for: vault) {
                documentController.selectWorkspace(workspace)
                shellState.selectDocumentWorkspace(workspace)
            }
            documentController.installOpenedDocument(
                snapshot,
                vaultName: vault.name,
                vaultRole: vault.role
            )
        } else if let descriptor = selectionDescriptor(for: path) {
            documentController.selectDocument(descriptor)
        } else {
            reportOperationIssue(
                String(localized: "Note not found: \(path)", table: "Localizable", bundle: .module),
                kind: .warning
            )
            return
        }
        synchronizeDocumentTabs(after: tabActivation)
    }

    func openingDocumentPresentationDidComplete() {
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            presentedOpeningRuntimeIdentity != capabilities.runtimeIdentity
        else { return }
        presentedOpeningRuntimeIdentity = capabilities.runtimeIdentity
        ScholiumWebKitProcessPrewarmer.shared.finish()
        Task {
            await capabilities.openingPresentationDidComplete()
        }
    }

    func vaultQualifiedID(
        for document: WindowSelectedDocument
    ) -> VaultQualifiedNoteID? {
        guard let vaultID = document.vaultID else { return nil }
        return VaultQualifiedNoteID(
            vaultID: vaultID,
            relativePath: document.relativePath
        )
    }

    func activateDocument(
        _ document: WindowSelectedDocument,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true
    ) async throws {
        if workspaceStore.documentLocations.revealExisting(document, excluding: self) { return }
        guard let vaultID = document.vaultID,
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == vaultID
            }),
            let workspace = workspaceSlot(for: vault)
        else {
            throw WindowNavigationError.noteUnavailable(document.relativePath)
        }
        if shellState.selectedWorkspace != workspace {
            try await prepareWorkspaceSelection(
                workspace,
                sourceScope: .library,
                validateDestination: {
                    try self.validateDocumentIsAvailable(document)
                }
            )
        }
        try activateResolvedDocument(
            document,
            tabActivation: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory
        )
    }

    func activateResolvedDocument(
        _ document: WindowSelectedDocument,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true
    ) throws {
        if case .preserveTabMembership = tabActivation {
            try validateDocumentIsAvailable(document)
            if let vaultID = document.vaultID,
                let vault = workspaceAssignment?.vaults.values.first(where: { $0.id == vaultID }),
                let workspace = workspaceSlot(for: vault)
            {
                documentController.selectWorkspace(workspace)
                shellState.selectDocumentWorkspace(workspace)
            }
            if documentController.selectRetainedDocument(document) {
                synchronizeDocumentTabs(after: tabActivation, recordsNavigationHistory: recordsNavigationHistory)
                return
            }
        }
        switch document {
        case .workspace(let descriptor):
            try activateResolvedWorkspaceReference(
                descriptor.reference,
                tabActivation: tabActivation,
                recordsNavigationHistory: recordsNavigationHistory
            )
        case .unavailable(let vaultID, let relativePath):
            try validateDocumentIsAvailable(document)
            PerformanceProbe.shared.beginReadActivation(documentID: relativePath)
            documentController.selectUnavailableDocument(
                vaultID: vaultID,
                relativePath: relativePath
            )
            synchronizeDocumentTabs(
                after: tabActivation,
                recordsNavigationHistory: recordsNavigationHistory
            )
        }
    }

    func activateWorkspaceReference(
        _ reference: VaultNoteReference,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true,
        managedCreationBodyStartUTF16: Int? = nil,
        validateDisplay: @MainActor () throws -> Void = {}
    ) async throws {
        guard !transferInProgress else { throw CancellationError() }
        try validateDisplay()
        if workspaceStore.documentLocations.revealExisting(reference, excluding: self) { return }
        guard
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == reference.vaultID
            }), let workspace = workspaceSlot(for: vault)
        else {
            throw WindowNavigationError.vaultUnavailable(reference.vaultName)
        }
        let requestedStableID = reference.stableNoteID.flatMap(UUID.init(uuidString:))
        guard
            workspaceProjectionController.cachedNote(
                vaultID: reference.vaultID,
                stableNoteID: requestedStableID,
                relativePath: reference.relativePath
            ) != nil
        else {
            throw WindowNavigationError.noteUnavailable(reference.relativePath)
        }
        if shellState.selectedWorkspace != workspace {
            try await prepareWorkspaceSelection(
                workspace,
                sourceScope: .library,
                validateDestination: {
                    try validateDisplay()
                    guard
                        self.workspaceProjectionController.cachedNote(
                            vaultID: reference.vaultID,
                            stableNoteID: requestedStableID,
                            relativePath: reference.relativePath
                        ) != nil
                    else {
                        throw WindowNavigationError.noteUnavailable(
                            reference.relativePath
                        )
                    }
                }
            )
        }
        try activateResolvedWorkspaceReference(
            reference,
            tabActivation: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory,
            managedCreationBodyStartUTF16: managedCreationBodyStartUTF16
        )
    }

    private func activateResolvedWorkspaceReference(
        _ reference: VaultNoteReference,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true,
        managedCreationBodyStartUTF16: Int? = nil
    ) throws {
        if workspaceStore.documentLocations.revealExisting(reference, excluding: self) { return }
        guard
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == reference.vaultID
            })
        else {
            throw WindowNavigationError.vaultUnavailable(reference.vaultName)
        }
        let requestedStableID = reference.stableNoteID.flatMap(UUID.init(uuidString:))
        guard
            let snapshot = workspaceProjectionController.cachedNote(
                vaultID: reference.vaultID,
                stableNoteID: requestedStableID,
                relativePath: reference.relativePath
            )
        else {
            throw WindowNavigationError.noteUnavailable(reference.relativePath)
        }
        if let workspace = workspaceSlot(for: vault) {
            documentController.selectWorkspace(workspace)
            shellState.selectDocumentWorkspace(workspace)
        }
        if managedCreationBodyStartUTF16 == nil {
            PerformanceProbe.shared.beginReadActivation(
                documentID: snapshot.id.relativePath
            )
        }
        if snapshot.stableIdentity.resolvedID != nil {
            documentController.installOpenedDocument(
                snapshot,
                vaultName: vault.name,
                vaultRole: vault.role,
                managedCreationBodyStartUTF16: managedCreationBodyStartUTF16
            )
        } else {
            documentController.selectUnavailableDocument(
                vaultID: vault.id,
                relativePath: snapshot.id.relativePath
            )
        }
        synchronizeDocumentTabs(
            after: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory
        )
    }

    func showInFinder(_ path: String) {
        guard let vaultURL = vaultConfig?.path else { return }
        let fileURL = vaultURL.appendingPathComponent(path)
        workspaceStore.revealInFinder(fileURL)
    }

    func revealVaultInFinder() {
        guard let vaultURL = vaultConfig?.path else { return }
        workspaceStore.revealInFinder(vaultURL)
    }

    func openExternalURL(_ url: URL) {
        _ = workspaceStore.openExternal(url)
    }

    func openWorkspaceReference(
        _ reference: VaultNoteReference,
        line: Int? = nil,
        mode: NotePresentationMode? = nil,
        inspectorMode: ResearchInspectorMode? = nil,
        sourceFingerprint: DocumentFingerprint? = nil
    ) async {
        if let owner = workspaceStore.documentLocations.existingOwner(of: reference, excluding: self) {
            owner.nativeWindowCoordinator?.makeKeyAndOrderFront()
            await owner.openWorkspaceReference(
                reference, line: line, mode: mode, inspectorMode: inspectorMode, sourceFingerprint: sourceFingerprint)
            return
        }
        let navigationMode = mode ?? presentedDocumentMode
        let retainedTarget = sourceFingerprint.flatMap { _ in
            reference.stableNoteID.flatMap(UUID.init(uuidString:)).map {
                DocumentSessionKey(vaultID: reference.vaultID, noteID: $0)
            }
        }
        enqueueDocumentTransition(preservingCurrentEditorState: false, retainingCurrentDocument: retainedTarget) { [weak self] in
            guard let self else { return }
            let alreadyCurrent =
                sourceFingerprint != nil
                && self.currentDocumentDescriptor?.reference.vaultID == reference.vaultID
                && self.currentDocumentDescriptor?.reference.relativePath == reference.relativePath
            if !alreadyCurrent {
                try await self.activateWorkspaceReference(
                    reference,
                    tabActivation: .place(.replaceSelected)
                )
            }
            if let inspectorMode { self.researchController.selectInspectorMode(inspectorMode) }
            var verifiedLine = line
            var locationNotice: String?
            if let sourceFingerprint, line != nil {
                guard let capabilities = self.windowWorkspaceController.activeCapabilities,
                    let descriptor = self.currentDocumentDescriptor,
                    descriptor.reference.vaultID == reference.vaultID,
                    descriptor.reference.relativePath == reference.relativePath
                else { throw CancellationError() }
                let session = self.documentController.session(for: descriptor)
                let document: NoteDocument?
                do {
                    document = try await capabilities.documents.load(
                        .init(vaultID: reference.vaultID, relativePath: reference.relativePath))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    document = nil
                }
                try Task.checkCancellation()
                guard self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                    self.currentDocumentDescriptor?.sessionKey == descriptor.sessionKey
                else { throw CancellationError() }
                if session.hasUnsavedChanges || session.editorSession.isComposing || document == nil {
                    verifiedLine = nil
                    locationNotice = String(
                        localized: "This reference location could not be verified. The Note was opened without selecting a passage.", bundle: .module)
                } else if document?.fingerprint != sourceFingerprint {
                    verifiedLine = nil
                    locationNotice = String(
                        localized: "This reference is from a different version. The Note was opened without selecting a passage.", bundle: .module)
                } else if self.currentNote?.workspaceSnapshot?.fingerprint != document?.fingerprint {
                    verifiedLine = nil
                    locationNotice = String(
                        localized: "This reference location could not be verified. The Note was opened without selecting a passage.", bundle: .module)
                }
            }
            self.documentController.requestSourceLocation(
                line: verifiedLine.map { max(1, $0) },
                sourceFingerprint: verifiedLine == nil ? nil : sourceFingerprint?.sha256)
            if let locationNotice { self.reportOperationIssue(locationNotice, kind: .information) }
            // Read-only destinations already enter Review through DocumentController.
            // Ordinary navigation must not turn that exception into an edit warning.
            self.requestPresentationMode =
                mode == nil
                    && self.currentNote?.workspaceSnapshot?.capabilities.canEditSource == false
                ? nil : navigationMode
        }
    }

    func openWorkspaceReference(
        _ reference: VaultNoteReference,
        sourceRange: SearchSourceRange?,
        fallbackLine: Int
    ) {
        if let owner = workspaceStore.documentLocations.existingOwner(of: reference, excluding: self) {
            owner.nativeWindowCoordinator?.makeKeyAndOrderFront()
            owner.openWorkspaceReference(reference, sourceRange: sourceRange, fallbackLine: fallbackLine)
            return
        }
        enqueueDocumentTransition(preservingCurrentEditorState: false) { [weak self] in
            guard let self else { return }
            try await self.activateWorkspaceReference(
                reference,
                tabActivation: .place(.replaceSelected)
            )
            self.documentController.requestSourceLocation(line: sourceRange?.line ?? max(1, fallbackLine), range: sourceRange)
            self.requestPresentationMode = .source
        }
    }

    func openInternalLink(_ targetWithFragment: String, from sourcePath: String) {
        guard let sourceContext = activeDocumentContext(for: sourcePath),
            let graph = workspaceCatalog?.graph
        else {
            reportOperationIssue(
                String(localized: "Connections are still refreshing. Try the link again shortly.", table: "Localizable", bundle: .module), kind: .information)
            return
        }
        let parts = targetWithFragment.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(parts.first ?? "").removingPercentEncoding ?? String(parts.first ?? "")
        let rawFragment = parts.count == 2 ? String(parts[1]) : nil
        let fragment = rawFragment.flatMap { $0.removingPercentEncoding ?? $0 }
        let source = VaultQualifiedNoteID(vaultID: sourceContext.vaultID, relativePath: sourcePath)
        let matching = graph.outgoing[source, default: []].filter { edge in
            let occurrenceTarget =
                edge.occurrence.target.removingPercentEncoding
                ?? edge.occurrence.target
            let occurrenceFragment = edge.occurrence.fragment.flatMap {
                $0.removingPercentEncoding ?? $0
            }
            return occurrenceTarget == target && occurrenceFragment == fragment
        }
        let resolved = matching.compactMap { edge -> (VaultQualifiedNoteID, Int?)? in
            guard let destination = edge.destination else { return nil }
            return (destination.note, destination.span?.start.line)
        }
        var destinations: [(note: VaultQualifiedNoteID, line: Int?)] = []
        for (destination, line) in resolved
        where !destinations.contains(where: { $0.note == destination }) {
            destinations.append((destination, line))
        }

        guard destinations.count == 1, let destination = destinations.first else {
            let hasAmbiguity = matching.contains {
                if case .ambiguous = $0.occurrence.resolution { return true }
                let edge = $0
                return graph.diagnostics.contains {
                    $0.source == edge.source && $0.span == edge.occurrence.span
                        && ($0.code == .ambiguousBlock || $0.code == .ambiguousHeading)
                }
            }
            let message =
                hasAmbiguity
                ? String(
                    localized: "This Connection is ambiguous. Open Incoming or Outgoing to choose a source-located candidate.",
                    table: "Localizable",
                    bundle: .module
                )
                : String(
                    localized: "This Connection is broken or its destination no longer exists.",
                    table: "Localizable",
                    bundle: .module
                )
            reportOperationIssue(
                message,
                kind: .warning
            )
            return
        }
        guard
            let reference = workspaceCatalog?.notes.first(where: {
                $0.reference.vaultID == destination.note.vaultID
                    && $0.reference.relativePath == destination.note.relativePath
            })?.reference
        else {
            reportOperationIssue(
                String(localized: "The resolved note is not available in the current Triptych catalog.", table: "Localizable", bundle: .module), kind: .warning)
            return
        }
        Task { await openWorkspaceReference(reference, line: destination.line) }
    }

    func diskDocument(for path: String) async throws -> NoteDocument {
        guard let context = activeDocumentContext(for: path) else {
            throw VaultRepositoryError.fileDoesNotExist(path)
        }
        return try await documentController.load(
            VaultQualifiedNoteID(vaultID: context.vaultID, relativePath: path)
        )
    }

    func openNotifiedAgentChange(_ route: AgentChangeNotificationRoute) async {
        guard workspaceAssignment?.id == route.triptychID,
            let capabilities = windowWorkspaceController.activeCapabilities
        else { return }
        do {
            let review = try await capabilities.agentCollaboration.agentChangeReview(id: route.changeID)
            guard windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity,
                route.matches(review.change)
            else {
                reportOperationIssue(String(localized: "This Agent Change is no longer available."), kind: .warning)
                return
            }
            presentationRouter.present(.agentChanges(scope: .exact(route.changeID)))
        } catch {
            reportOperationIssue(error.localizedDescription, kind: .error)
        }
    }
}
