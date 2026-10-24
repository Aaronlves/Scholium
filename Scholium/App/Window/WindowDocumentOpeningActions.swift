import Foundation
import ScholiumContracts

/// Opening what a researcher points at: a note, a workspace reference, an
/// internal link, an agent's change, or a path handed to the system.
extension WindowModel {
    func openNote(
        _ path: String,
        tabActivation: DocumentTabActivation = .place(.replaceSelected)
    ) async throws {
        guard !transferInProgress else { throw CancellationError() }
        guard let location = notes.first(where: { $0.relativePath == path }),
            let summary = location.workspaceSnapshot,
            let vault = currentRegisteredVault
        else { throw WindowNavigationError.noteUnavailable(path) }
        let reference = VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: summary.id.relativePath,
            stableNoteID: summary.stableIdentity.resolvedID?.uuidString.lowercased()
        )
        try await activateWorkspaceReference(reference, tabActivation: tabActivation)
    }

    func openingDocumentPresentationDidComplete() {
        guard let capabilities = windowWorkspaceController.activeCapabilities,
            presentedOpeningRuntimeIdentity != capabilities.runtimeIdentity
        else { return }
        presentedOpeningRuntimeIdentity = capabilities.runtimeIdentity
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
        recordsNavigationHistory: Bool = true,
        validateDisplay: @MainActor () throws -> Void = {}
    ) async throws {
        try validateDisplay()
        if workspaceStore.documentLocations.revealExisting(
            document, excluding: self, isCurrentRequest: activeDocumentTransitionCurrency ?? { true }
        ) {
            return
        }
        guard let vaultID = document.vaultID,
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == vaultID
            }),
            workspaceSlot(for: vault) != nil
        else {
            throw WindowNavigationError.noteUnavailable(document.relativePath)
        }
        try await activateResolvedDocument(
            document,
            tabActivation: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory,
            validateDisplay: validateDisplay
        )
    }

    func activateResolvedDocument(
        _ document: WindowSelectedDocument,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true,
        validateDisplay: @MainActor () throws -> Void = {}
    ) async throws {
        try validateDisplay()
        if case .preserveTabMembership = tabActivation {
            try validateDocumentIsAvailable(document)
            if documentController.canSelectRetainedDocument(document),
                let vaultID = document.vaultID
            {
                let stagedLibrary = try await stageDocumentLibrarySelection(vaultID: vaultID)
                try validateDisplay()
                try validateDocumentIsAvailable(document)
                guard activeDocumentTransitionCurrency?() ?? true else { throw CancellationError() }
                guard documentController.canSelectRetainedDocument(document),
                    let summary = workspaceProjectionController.cachedNote(
                        vaultID: vaultID,
                        stableNoteID: document.sessionKey?.noteID,
                        relativePath: document.relativePath
                    )
                else { throw WindowNavigationError.noteUnavailable(document.relativePath) }
                try commitDocumentLibrarySelection(stagedLibrary, opening: summary)
                _ = documentController.selectRetainedDocument(document)
                if let vaultID = document.vaultID,
                    let vault = workspaceAssignment?.vaults.values.first(where: { $0.id == vaultID }),
                    let workspace = workspaceSlot(for: vault)
                {
                    shellState.selectDocumentWorkspace(workspace)
                }
                synchronizeDocumentTabs(after: tabActivation, recordsNavigationHistory: recordsNavigationHistory)
                return
            }
        }
        switch document {
        case .workspace(let descriptor):
            try await activateResolvedWorkspaceReference(
                descriptor.reference,
                tabActivation: tabActivation,
                recordsNavigationHistory: recordsNavigationHistory,
                validateDisplay: validateDisplay
            )
        case .unavailable(let vaultID, let relativePath):
            try validateDocumentIsAvailable(document)
            PerformanceProbe.shared.beginReadActivation(documentID: relativePath)
            guard
                let summary = workspaceProjectionController.cachedNote(
                    vaultID: vaultID, relativePath: relativePath
                )
            else { throw WindowNavigationError.noteUnavailable(relativePath) }
            let hydrated = try await hydrateForOpening(summary)
            let stagedLibrary = try await stageDocumentLibrarySelection(vaultID: vaultID)
            try validateDisplay()
            try validateDocumentIsAvailable(document)
            guard activeDocumentTransitionCurrency?() ?? true else { throw CancellationError() }
            try commitDocumentLibrarySelection(stagedLibrary, opening: hydrated.summary)
            if let vault = workspaceAssignment?.vaults.values.first(where: { $0.id == vaultID }),
                let workspace = workspaceSlot(for: vault)
            {
                shellState.selectDocumentWorkspace(workspace)
            }
            documentController.selectUnavailableDocument(hydrated)
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
        committedSnapshot: WorkspaceNoteSnapshot? = nil,
        openingMeasurement: UUID? = nil,
        validateDisplay: @MainActor () throws -> Void = {},
        validateSource: @MainActor () async throws -> Void = {}
    ) async throws {
        guard !transferInProgress else { throw CancellationError() }
        try validateDisplay()
        if workspaceStore.documentLocations.revealExisting(
            reference, excluding: self, isCurrentRequest: activeDocumentTransitionCurrency ?? { true }
        ) {
            PerformanceProbe.shared.cancelNoteOpening(attemptID: openingMeasurement)
            return
        }
        guard
            let vault = workspaceAssignment?.vaults.values.first(where: {
                $0.id == reference.vaultID
            }), workspaceSlot(for: vault) != nil
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
        try await activateResolvedWorkspaceReference(
            reference,
            tabActivation: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory,
            managedCreationBodyStartUTF16: managedCreationBodyStartUTF16,
            committedSnapshot: committedSnapshot,
            openingMeasurement: openingMeasurement,
            validateDisplay: validateDisplay, validateSource: validateSource
        )
    }

    private func activateResolvedWorkspaceReference(
        _ reference: VaultNoteReference,
        tabActivation: DocumentTabActivation,
        recordsNavigationHistory: Bool = true,
        managedCreationBodyStartUTF16: Int? = nil,
        committedSnapshot: WorkspaceNoteSnapshot? = nil,
        openingMeasurement: UUID? = nil,
        validateDisplay: @MainActor () throws -> Void = {},
        validateSource: @MainActor () async throws -> Void = {}
    ) async throws {
        if workspaceStore.documentLocations.revealExisting(
            reference, excluding: self, isCurrentRequest: activeDocumentTransitionCurrency ?? { true }
        ) {
            PerformanceProbe.shared.cancelNoteOpening(attemptID: openingMeasurement)
            return
        }
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
        let stagedLibrary = try await stageDocumentLibrarySelection(vaultID: vault.id)
        if managedCreationBodyStartUTF16 == nil,
            let retainedTab = documentTabController.tab(for: reference)
        {
            try await validateSource()
            try validateDisplay()
            guard activeDocumentTransitionCurrency?() ?? true else { throw CancellationError() }
            try validateDocumentIsAvailable(retainedTab.document)
            if documentController.canSelectRetainedDocument(retainedTab.document) {
                PerformanceProbe.shared.markNoteOpeningSourceReused(
                    attemptID: openingMeasurement, documentID: reference.relativePath)
                try commitDocumentLibrarySelection(stagedLibrary, opening: snapshot)
                _ = documentController.selectRetainedDocument(retainedTab.document)
                PerformanceProbe.shared.markNoteOpeningPhase(.documentInstalled, attemptID: openingMeasurement)
                if let workspace = workspaceSlot(for: vault) {
                    shellState.selectDocumentWorkspace(workspace)
                }
                synchronizeDocumentTabs(after: tabActivation, recordsNavigationHistory: recordsNavigationHistory)
                return
            }
        }
        let hydrated: WorkspaceNoteSnapshot
        let sourceReused: Bool
        if let committedSnapshot {
            guard committedSnapshot.summary.hasSameSourceBinding(as: snapshot) else {
                throw WorkspaceHydrationError.staleSnapshot
            }
            hydrated = WorkspaceNoteSnapshot(
                summary: snapshot, document: committedSnapshot.document,
                cachedSemanticDocument: committedSnapshot.cachedSemanticDocument
            )
            sourceReused = true
        } else if let stableID = snapshot.stableIdentity.resolvedID {
            let key = DocumentSessionKey(vaultID: snapshot.id.vaultID, noteID: stableID)
            if let retained = documentController.snapshots[key],
                retained.fingerprint == snapshot.fingerprint,
                retained.id.relativePath.utf8.elementsEqual(snapshot.id.relativePath.utf8)
            {
                hydrated = WorkspaceNoteSnapshot(
                    summary: snapshot, document: retained.document,
                    cachedSemanticDocument: retained.cachedSemanticDocument
                )
                sourceReused = true
            } else {
                hydrated = try await hydrateForOpening(snapshot, openingMeasurement: openingMeasurement)
                sourceReused = false
            }
        } else {
            hydrated = try await hydrateForOpening(snapshot, openingMeasurement: openingMeasurement)
            sourceReused = false
        }
        try await validateSource()
        try validateDisplay()
        guard activeDocumentTransitionCurrency?() ?? true else { throw CancellationError() }
        guard
            let currentSummary = workspaceProjectionController.cachedNote(
                vaultID: hydrated.id.vaultID,
                stableNoteID: requestedStableID,
                relativePath: hydrated.id.relativePath
            ), currentSummary.hasSameSourceBinding(as: hydrated.summary)
        else { throw WorkspaceHydrationError.staleSnapshot }
        if sourceReused {
            PerformanceProbe.shared.markNoteOpeningSourceReused(
                attemptID: openingMeasurement, documentID: hydrated.id.relativePath)
        }
        let current = WorkspaceNoteSnapshot(
            summary: currentSummary, document: hydrated.document,
            cachedSemanticDocument: hydrated.cachedSemanticDocument
        )
        try commitDocumentLibrarySelection(stagedLibrary, opening: current.summary)
        if let workspace = workspaceSlot(for: vault) {
            shellState.selectDocumentWorkspace(workspace)
        }
        if managedCreationBodyStartUTF16 == nil {
            PerformanceProbe.shared.beginReadActivation(documentID: current.id.relativePath)
        }
        if current.stableIdentity.resolvedID != nil {
            documentController.installOpenedDocument(
                current,
                vaultName: vault.name,
                vaultRole: vault.role,
                managedCreationBodyStartUTF16: managedCreationBodyStartUTF16
            )
        } else {
            documentController.selectUnavailableDocument(current)
        }
        synchronizeDocumentTabs(
            after: tabActivation,
            recordsNavigationHistory: recordsNavigationHistory
        )
        PerformanceProbe.shared.markNoteOpeningPhase(.documentInstalled, attemptID: openingMeasurement)
    }

    /// A document opening may change the browsed Library only after its exact
    /// destination is ready. Staging owns no visible selection, so hydration
    /// failure leaves the origin workspace and editor intact.
    private func stageDocumentLibrarySelection(
        vaultID: UUID
    ) async throws -> StagedWorkspaceLibrarySelection? {
        guard let vault = workspaceAssignment?.vaults.values.first(where: { $0.id == vaultID }),
            let workspace = workspaceSlot(for: vault)
        else { throw WorkspaceRegistryError.incompleteWorkspace }
        guard shellState.selectedWorkspace != workspace else { return nil }
        return try await stageRegisteredVault(vault, slot: workspace, sourceScope: .library)
    }

    private func commitDocumentLibrarySelection(
        _ staged: StagedWorkspaceLibrarySelection?,
        opening summary: WorkspaceNoteSummary
    ) throws {
        guard let staged else { return }
        guard activeDocumentTransitionCurrency?() ?? true else { throw CancellationError() }
        guard
            staged.vaultSnapshot.documents.first(where: { $0.id == summary.id })?
                .hasSameSourceBinding(as: summary) == true,
            workspaceProjectionController.cachedNote(
                vaultID: summary.id.vaultID,
                stableNoteID: summary.stableIdentity.resolvedID,
                relativePath: summary.id.relativePath
            )?.hasSameSourceBinding(as: summary) == true
        else { throw WorkspaceHydrationError.staleSnapshot }
        let accepted = try commitStagedWorkspaceLibrarySelection(staged)
        shellState.selectLibraryWorkspace(staged.workspace)
        refreshIdentityState(from: accepted)
        scheduleWorkspaceCatalogRefresh()
    }

    private func hydrateForOpening(
        _ summary: WorkspaceNoteSummary, openingMeasurement: UUID? = nil
    ) async throws -> WorkspaceNoteSnapshot {
        guard let capabilities = windowWorkspaceController.activeCapabilities else {
            throw WindowNavigationError.noteUnavailable(summary.id.relativePath)
        }
        let runtimeIdentity = capabilities.runtimeIdentity
        PerformanceProbe.shared.markNoteOpeningPhase(.hydrationStarted, attemptID: openingMeasurement)
        let hydrated: WorkspaceNoteSnapshot
        do {
            hydrated = try await capabilities.documents.hydrate(summary)
        } catch WorkspaceHydrationError.staleSnapshot {
            guard activeDocumentTransitionCurrency?() ?? true else { throw CancellationError() }
            guard
                let newer = workspaceProjectionController.cachedNote(
                    vaultID: summary.id.vaultID,
                    stableNoteID: summary.stableIdentity.resolvedID,
                    relativePath: summary.id.relativePath
                ), newer != summary,
                newer.stableIdentity == summary.stableIdentity
            else { throw WorkspaceHydrationError.staleSnapshot }
            hydrated = try await capabilities.documents.hydrate(newer)
        }
        try Task.checkCancellation()
        guard activeDocumentTransitionCurrency?() ?? true else { throw CancellationError() }
        guard windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtimeIdentity,
            let currentSummary = workspaceProjectionController.cachedNote(
                vaultID: hydrated.id.vaultID,
                stableNoteID: hydrated.stableIdentity.resolvedID,
                relativePath: hydrated.id.relativePath
            ), currentSummary.hasSameSourceBinding(as: hydrated.summary)
        else { throw WorkspaceHydrationError.staleSnapshot }
        PerformanceProbe.shared.markNoteOpeningPhase(.hydrated, attemptID: openingMeasurement)
        return WorkspaceNoteSnapshot(
            summary: currentSummary, document: hydrated.document,
            cachedSemanticDocument: hydrated.cachedSemanticDocument
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
        sourceFingerprint: DocumentFingerprint? = nil,
        navigationRequest: DocumentTransitionCoordinator.Currency? = nil,
        validateDisplay: @escaping @MainActor () throws -> Void = {},
        validateSource: @escaping @MainActor () async throws -> Void = {}
    ) async {
        do { try validateDisplay() } catch { return }
        guard let requestIsCurrent = beginDocumentNavigation(continuing: navigationRequest) else { return }
        let validateNavigation: @MainActor () throws -> Void = {
            guard requestIsCurrent() else { throw CancellationError() }
            try validateDisplay()
        }
        if let owner = workspaceStore.documentLocations.existingOwner(of: reference, excluding: self) {
            owner.nativeWindowCoordinator?.makeKeyAndOrderFront()
            await owner.openWorkspaceReference(
                reference, line: line, mode: mode, inspectorMode: inspectorMode, sourceFingerprint: sourceFingerprint,
                validateDisplay: validateNavigation, validateSource: validateSource)
            return
        }
        let navigationMode = mode ?? presentedDocumentMode
        let retainedTarget = sourceFingerprint.flatMap { _ in
            reference.stableNoteID.flatMap(UUID.init(uuidString:)).map {
                DocumentSessionKey(vaultID: reference.vaultID, noteID: $0)
            }
        }
        enqueueDocumentTransition(
            preparation: openingPreparation(for: reference), requestIsCurrent: requestIsCurrent,
            retainingCurrentDocument: retainedTarget,
            validateBeforePreparation: validateNavigation, admitBeforePreparation: validateSource
        ) { [weak self] in
            guard let self else { return }
            try validateNavigation()
            let alreadyCurrent =
                sourceFingerprint != nil
                && self.currentDocumentDescriptor?.reference.vaultID == reference.vaultID
                && self.currentDocumentDescriptor?.reference.relativePath == reference.relativePath
            if !alreadyCurrent {
                try await self.activateWorkspaceReference(
                    reference,
                    tabActivation: .place(.replaceSelected), validateDisplay: validateNavigation, validateSource: validateSource
                )
            }
            try validateNavigation()
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
                try validateNavigation()
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
        fallbackLine: Int,
        sourceFingerprint: DocumentFingerprint,
        scope: SearchPresentationScope,
        freshnessToken: SearchFreshnessToken,
        placement: DocumentTabPlacement = .replaceSelected,
        mode: NotePresentationMode? = nil,
        isCurrentRequest: @escaping @MainActor () -> Bool = { true },
        onCompletion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        guard isCurrentRequest() else {
            onCompletion(false)
            return
        }
        guard let localRequestIsCurrent = beginDocumentNavigation() else {
            onCompletion(false)
            return
        }
        let requestIsCurrent: DocumentTransitionCoordinator.Currency = { localRequestIsCurrent() && isCurrentRequest() }
        var forwarded = false
        let forwardToExistingOwner: @MainActor () -> Bool = { [weak self] in
            guard let self, let owner = self.workspaceStore.documentLocations.existingOwner(of: reference, excluding: self) else { return false }
            guard !forwarded else { return true }
            forwarded = true
            owner.nativeWindowCoordinator?.makeKeyAndOrderFront()
            owner.openWorkspaceReference(
                reference, sourceRange: sourceRange, fallbackLine: fallbackLine,
                sourceFingerprint: sourceFingerprint, scope: scope, freshnessToken: freshnessToken,
                placement: placement, mode: mode,
                isCurrentRequest: requestIsCurrent, onCompletion: onCompletion)
            return true
        }
        if forwardToExistingOwner() { return }
        guard let capabilities = windowWorkspaceController.activeCapabilities else {
            onCompletion(false)
            return
        }
        let navigationMode = mode ?? presentedDocumentMode
        let target = reference.stableNoteID.flatMap(UUID.init(uuidString:)).map {
            DocumentSessionKey(vaultID: reference.vaultID, noteID: $0)
        }
        let currentSummary: @MainActor () throws -> WorkspaceNoteSummary = { [weak self] in
            guard
                let summary = self?.workspaceProjectionController.cachedNote(
                    vaultID: reference.vaultID, stableNoteID: target?.noteID, relativePath: reference.relativePath)
            else { throw SearchResultNavigationError.staleResult }
            return summary
        }
        var admittedSummary: WorkspaceNoteSummary?
        let validateDisplay: @MainActor () throws -> Void = { [weak self] in
            guard requestIsCurrent(),
                self?.windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity
            else { throw CancellationError() }
            // A peer can acquire the target while this request is queued or
            // suspended. Redirect the complete request before preparing the
            // origin; activation's ordinary reveal is not local selection.
            if forwardToExistingOwner() { throw CancellationError() }
            if let admittedSummary, try !currentSummary().hasSameSourceBinding(as: admittedSummary) {
                throw SearchResultNavigationError.staleResult
            }
        }
        let validateSource: @MainActor () async throws -> Void = { [weak self] in
            guard let self else { throw CancellationError() }
            try validateDisplay()
            let summary = try currentSummary()
            if scope == .thisNote {
                guard let snapshot = try await self.currentSearchSourceSnapshot(),
                    snapshot.noteID == summary.id,
                    target == nil || snapshot.stableNoteID == target?.noteID,
                    snapshot.fingerprint == sourceFingerprint,
                    SearchFreshnessToken.currentNote(snapshot) == freshnessToken
                else { throw SearchResultNavigationError.staleResult }
            } else {
                guard summary.fingerprint == sourceFingerprint else { throw SearchResultNavigationError.staleResult }
                // Hydration checks the resolved identity/path and filesystem
                // version. Reading the captured path could validate an unrelated
                // replacement after the stable Note has moved.
                let hydrated = try await capabilities.documents.hydrate(summary)
                guard hydrated.summary.hasSameSourceBinding(as: summary) else { throw SearchResultNavigationError.staleResult }
                if let target, let session = self.documentController.retainedSession(for: target),
                    session.hasUnsavedChanges || session.editorSession.isComposing
                {
                    throw SearchResultNavigationError.staleResult
                }
            }
            try Task.checkCancellation()
            try validateDisplay()
            guard try currentSummary().hasSameSourceBinding(as: summary) else { throw SearchResultNavigationError.staleResult }
            admittedSummary = summary
        }
        // Search evidence is checked again when the queued transition runs and
        // immediately before activation, before saving or replacing the origin.
        enqueueDocumentTransition(
            preparation: openingPreparation(for: reference, placement: placement), requestIsCurrent: requestIsCurrent,
            retainingCurrentDocument: target,
            validateBeforePreparation: validateDisplay, admitBeforePreparation: validateSource
        ) { [weak self] in
            guard let self else { return }
            try await self.activateWorkspaceReference(
                reference,
                tabActivation: .place(placement),
                validateDisplay: validateDisplay, validateSource: validateSource
            )
            try validateDisplay()
            guard let admittedSummary,
                self.currentNote?.workspaceSnapshot?.hasSameSourceBinding(as: admittedSummary) == true,
                self.documentController.selectedDocument?.vaultID == admittedSummary.id.vaultID,
                self.documentController.selectedDocument?.relativePath == admittedSummary.id.relativePath,
                target == nil || self.currentDocumentDescriptor?.sessionKey == target
            else { throw SearchResultNavigationError.staleResult }
            self.documentController.requestSourceLocation(
                line: sourceRange?.line ?? max(1, fallbackLine), range: sourceRange,
                sourceFingerprint: sourceFingerprint.sha256)
            // Search locates a result; it does not choose a new Document mode.
            // Read-only destinations still enter Review through activation.
            self.requestPresentationMode =
                mode == nil
                    && self.currentNote?.workspaceSnapshot?.capabilities.canEditSource == false
                ? nil : navigationMode
        } completion: { result in
            if !forwarded { onCompletion((try? result.get()) != nil) }
        }
    }

    func openInternalLink(_ targetWithFragment: String, from sourcePath: String) {
        guard
            !ZoteroMarkdownFields.isCitationDestination(
                targetWithFragment.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
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
        guard let requestIsCurrent = beginDocumentNavigation() else { return }
        Task { await openWorkspaceReference(reference, line: destination.line, navigationRequest: requestIsCurrent) }
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
        guard !Task.isCancelled, !windowCloseCoordinator.isPreparingOrFinalized,
            workspaceAssignment?.id == route.triptychID,
            let capabilities = windowWorkspaceController.activeCapabilities
        else { return }
        guard presentationRouter.sheet == nil else {
            reportOperationIssue(ScholiumL10n.string("Finish or close the current dialog before opening this notification."), kind: .information)
            return
        }
        let isCurrent = {
            !Task.isCancelled && !self.windowCloseCoordinator.isPreparingOrFinalized
                && self.workspaceAssignment?.id == route.triptychID
                && self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == capabilities.runtimeIdentity
                && self.presentationRouter.sheet == nil
        }
        do {
            let review = try await capabilities.agentCollaboration.agentChangeReview(id: route.changeID)
            guard isCurrent() else { return }
            guard route.matches(review.change) else {
                reportOperationIssue(String(localized: "This Agent Change is no longer available."), kind: .warning)
                return
            }
            let pending: [DocumentChangeSummary]
            do {
                pending = try await capabilities.changes.pendingChanges()
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent() else { return }
                // Receipt access remains useful when the derived current
                // comparison cannot refresh; retain the failure beside it.
                reportOperationIssue(error.localizedDescription, kind: .warning)
                presentationRouter.present(.agentChangeReceipt(route.changeID))
                return
            }
            guard isCurrent() else { return }
            if pending.contains(where: { $0.noteID == route.noteID && $0.role == review.change.role }) {
                presentationRouter.present(.documentChanges(scope: .note(route.noteID)))
                return
            }
            // Reviewed, deleted, or otherwise unavailable Notes retain their
            // exact operation evidence without disturbing a live editor.
            presentationRouter.present(.agentChangeReceipt(route.changeID))
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent() else { return }
            reportOperationIssue(error.localizedDescription, kind: .error)
        }
    }
}
