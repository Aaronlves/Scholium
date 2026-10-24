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
        requestsPassage: Bool = false,
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
        let forwardToExistingOwner: @MainActor () async -> Bool = { [weak self] in
            guard let self, requestIsCurrent(),
                let owner = self.workspaceStore.documentLocations.existingOwner(of: reference, excluding: self)
            else { return false }
            owner.nativeWindowCoordinator?.makeKeyAndOrderFront()
            await owner.openWorkspaceReference(
                reference, line: line, mode: mode, inspectorMode: inspectorMode, sourceFingerprint: sourceFingerprint,
                requestsPassage: requestsPassage, validateDisplay: validateNavigation, validateSource: validateSource)
            return true
        }
        if await forwardToExistingOwner() { return }
        let validateOpeningSource: @MainActor () async throws -> Void = {
            try validateNavigation()
            // A peer may acquire the target while this request is queued or
            // suspended. Route the complete arrival before preparing the origin.
            if await forwardToExistingOwner() { throw CancellationError() }
            do {
                try await validateSource()
            } catch {
                try validateNavigation()
                throw error
            }
            try validateNavigation()
            if await forwardToExistingOwner() { throw CancellationError() }
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
            validateBeforePreparation: validateNavigation, admitBeforePreparation: validateOpeningSource
        ) { [weak self] in
            guard let self else { return }
            try validateNavigation()
            if await forwardToExistingOwner() { return }
            let alreadyCurrent =
                sourceFingerprint != nil
                && self.currentDocumentDescriptor?.reference.vaultID == reference.vaultID
                && self.currentDocumentDescriptor?.reference.relativePath == reference.relativePath
                && (retainedTarget == nil || self.currentDocumentDescriptor?.sessionKey == retainedTarget)
            if !alreadyCurrent {
                try await self.activateWorkspaceReference(
                    reference,
                    tabActivation: .place(.replaceSelected), validateDisplay: validateNavigation, validateSource: validateOpeningSource
                )
            }
            try validateNavigation()
            if await forwardToExistingOwner() { return }
            if let inspectorMode { self.researchController.selectInspectorMode(inspectorMode) }
            var verifiedLine = line
            var locationNotice: String? =
                requestsPassage && line == nil
                ? String(
                    localized: "This reference location could not be verified. The Note was opened without selecting a passage.", bundle: .module)
                : nil
            if let sourceFingerprint, line != nil {
                guard let capabilities = self.windowWorkspaceController.activeCapabilities,
                    let descriptor = self.currentDocumentDescriptor,
                    descriptor.reference.vaultID == reference.vaultID,
                    descriptor.reference.relativePath == reference.relativePath,
                    retainedTarget == nil || descriptor.sessionKey == retainedTarget
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

    /// The returned task admits the request to its owning transition queue;
    /// presentation and source preparation still finish in that queue.
    @discardableResult
    func openInternalLink(_ targetWithFragment: String, from sourcePath: String) -> Task<Void, Never>? {
        guard
            !ZoteroMarkdownFields.isCitationDestination(
                targetWithFragment.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        guard let sourceContext = activeDocumentContext(for: sourcePath),
            let capabilities = windowWorkspaceController.activeCapabilities
        else {
            reportOperationIssue(
                String(localized: "Connections are still refreshing. Try the link again shortly.", table: "Localizable", bundle: .module),
                kind: .warning)
            return nil
        }
        // A missing or ambiguous newer intent also revokes a queued arrival.
        guard let requestIsCurrent = beginDocumentNavigation() else { return nil }
        guard workspaceProjectionController.snapshotPhase == .complete, workspaceCatalog?.graph != nil else {
            reportOperationIssue(
                String(localized: "Connections are still refreshing. Try the link again shortly.", table: "Localizable", bundle: .module),
                kind: .warning)
            return nil
        }
        let parts = targetWithFragment.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawTarget = String(parts.first ?? "")
        let target = rawTarget.removingPercentEncoding ?? rawTarget
        let rawFragment = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let decodedFragment = rawFragment.flatMap { $0.removingPercentEncoding ?? $0 }
        // Heading normalization already performs percent decoding. Blocks use
        // exact keys, so only that fragment spelling is decoded here.
        let fragment = decodedFragment?.hasPrefix("^") == true ? decodedFragment : rawFragment
        let source = VaultQualifiedNoteID(vaultID: sourceContext.vaultID, relativePath: sourcePath)
        let summaries = workspaceProjectionController.vaultSnapshotsByID.values.flatMap(\.documents)
        let resolver = LinkResolutionCatalog(catalog: summaries.map(\.linkCatalog))
        let destination: LinkDestination
        switch resolver.resolveNavigation(target: target, fragment: fragment, from: source, scope: .workspace) {
        case .resolved(let resolved):
            destination = resolved
        case .missingHeading, .missingBlock, .ambiguousHeading, .ambiguousBlock:
            // The Note may be unambiguous even when its authored passage is
            // unavailable. Keep that useful destination without inventing a line.
            guard
                case .resolved(let note) = resolver.resolveNavigation(
                    target: target, fragment: nil, from: source, scope: .workspace)
            else { return nil }
            destination = note
        case .ambiguous:
            reportOperationIssue(
                String(
                    localized: "This Connection is ambiguous. Open Incoming or Outgoing to choose a source-located candidate.", table: "Localizable",
                    bundle: .module),
                kind: .warning)
            return nil
        case .missingNote:
            let message =
                workspaceProjectionController.snapshotPhase == .complete
                ? String(localized: "This Connection is broken or its destination no longer exists.", table: "Localizable", bundle: .module)
                : String(localized: "Connections are still refreshing. Try the link again shortly.", table: "Localizable", bundle: .module)
            reportOperationIssue(message, kind: .warning)
            return nil
        }
        guard let summary = summaries.first(where: { $0.id == destination.note }),
            let vault = registeredVaults.first(where: { $0.id == destination.note.vaultID })
        else { return nil }
        let reference = VaultNoteReference(
            vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
            relativePath: summary.id.relativePath,
            stableNoteID: summary.stableIdentity.resolvedID?.uuidString.lowercased())
        let runtimeIdentity = capabilities.runtimeIdentity
        let validateSource: @MainActor () async throws -> Void = { [weak self] in
            @MainActor func validate() throws {
                guard let self, requestIsCurrent(),
                    self.windowWorkspaceController.activeCapabilities?.runtimeIdentity == runtimeIdentity,
                    self.workspaceProjectionController.snapshotPhase == .complete, self.workspaceCatalog?.graph != nil
                else { throw CancellationError() }
                guard
                    let current = self.workspaceProjectionController.cachedNote(
                        vaultID: summary.id.vaultID, stableNoteID: summary.stableIdentity.resolvedID,
                        relativePath: summary.id.relativePath),
                    current.hasSameSourceBinding(as: summary)
                else { throw WorkspaceHydrationError.staleSnapshot }
            }
            try validate()
            // A retained tab or an old path does not prove the canonical source
            // still exists or belongs to this Note. Use the checked source owner.
            _ = try await capabilities.documents.hydrate(summary)
            try Task.checkCancellation()
            try validate()
        }
        return Task {
            await openWorkspaceReference(
                reference, line: destination.span?.start.line,
                sourceFingerprint: summary.fingerprint,
                requestsPassage: !(fragment?.isEmpty ?? true), navigationRequest: requestIsCurrent,
                validateSource: validateSource)
        }
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
