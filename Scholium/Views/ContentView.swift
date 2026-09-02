import ScholiumContracts
import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject private var presentationRouter: WindowPresentationRouter
    @ObservedObject private var discoveryController: DiscoveryController
    @ObservedObject private var searchController: WindowSearchController
    @ObservedObject private var researchController: ResearchController
    @ObservedObject private var shellState: WindowShellState
    @ObservedObject private var documentController: DocumentController
    @ObservedObject private var documentTabController: DocumentTabController
    @ObservedObject private var workspaceProjectionController: WindowWorkspaceProjectionController
    @ObservedObject private var cssSnippetStore: CSSSnippetStore
    @ObservedObject private var windowWorkspaceController: WindowWorkspaceController
    @ObservedObject private var libraryMutationController: WindowLibraryMutationController
    let windowCoordinator: WorkspaceWindowCoordinator
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()

    init(
        appState: WindowModel,
        windowCoordinator: WorkspaceWindowCoordinator
    ) {
        self.appState = appState
        self.windowCoordinator = windowCoordinator
        _presentationRouter = ObservedObject(wrappedValue: appState.presentationRouter)
        _discoveryController = ObservedObject(wrappedValue: appState.discoveryController)
        _searchController = ObservedObject(wrappedValue: appState.searchController)
        _researchController = ObservedObject(wrappedValue: appState.researchController)
        _shellState = ObservedObject(wrappedValue: appState.shellState)
        _documentController = ObservedObject(wrappedValue: appState.documentController)
        _documentTabController = ObservedObject(wrappedValue: appState.documentTabController)
        _workspaceProjectionController = ObservedObject(
            wrappedValue: appState.workspaceProjectionController
        )
        _cssSnippetStore = ObservedObject(wrappedValue: appState.cssSnippetStore)
        _windowWorkspaceController = ObservedObject(
            wrappedValue: appState.windowWorkspaceController
        )
        _libraryMutationController = ObservedObject(
            wrappedValue: appState.libraryMutationController
        )
    }

    var body: some View {
        ScholiumWorkspaceSplitView(
            initialLibraryVisible: shellLibraryVisible,
            initialApparatusVisible: shellApparatusVisible,
            documentTabs: appState.documentTabController.tabs(
                in: shellState.selectedWorkspace
            ),
            selectedDocumentTabID: appState.documentTabController.selectedTabID(
                in: shellState.selectedWorkspace
            ),
            selectDocumentTab: { appState.selectDocumentTab(withID: $0) },
            closeDocumentTab: { appState.closeDocumentTab(withID: $0) },
            libraryVisibilityDidChange: {
                appState.recordLibraryVisibility($0)
            },
            researchInspectorVisibilityDidChange: {
                appState.recordResearchInspectorVisibility($0)
            },
            splitControllerDidAttach: {
                windowCoordinator.attach(splitController: $0)
            },
            splitControllerDidDetach: {
                windowCoordinator.detach(splitController: $0)
            }
        ) {
            LibrarySurface {
                SidebarView(
                    controller: appState.discoveryController,
                    context: sidebarContext
                )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        } document: {
            Group {
                if !shellState.hasCompletedInitialRestore {
                    ScholiumLaunchPlaceholderView()
                } else {
                    detailRegion
                }
            }
            .scholiumSurface(.document)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } apparatus: {
            apparatusRegion
            .scholiumSurface(.apparatus)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        // The native split and each opaque semantic background fill the complete
        // titlebar frame. Each container keeps its actual content inside the
        // live toolbar safe area.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ScholiumWindowTopOverlayHost(
                topInset: ScholiumGrid.Spacing.sectionSeparation
            ) {
                windowTopNotificationOverlay
                    .ignoresSafeArea(.container, edges: .top)
                    .animation(
                        ScholiumMotion.transientStatus(reduceMotion: reduceMotion),
                        value: shellState.feedbackItems
                    )
            }
        }
        .overlay(alignment: .bottom) {
            if let feedback = shellState.transientFeedbackItems.first {
                WindowFeedbackItem(
                    feedback: feedback,
                    dismiss: { shellState.dismissFeedback(id: feedback.id) }
                )
                .padding(.bottom, ScholiumGrid.Spacing.sectionSeparation)
                .transition(
                    ScholiumMotion.transientStatusTransition(
                        reduceMotion: reduceMotion
                    )
                )
                .zIndex(10)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .animation(
            ScholiumMotion.documentReveal(reduceMotion: reduceMotion),
            value: appState.currentNote != nil
        )
        .animation(
            ScholiumMotion.transientStatus(reduceMotion: reduceMotion),
            value: shellState.feedbackItems
        )
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
            }
        }
        .overlay {
            if appState.showSearchSurface {
                SpotlightSearchOverlay(
                    controller: appState.discoveryController,
                    context: spotlightSearchContext
                )
                    .transition(
                        ScholiumMotion.searchPresentationTransition(
                            reduceMotion: reduceMotion
                        )
                    )
                    .zIndex(20)
            }
        }
        .animation(
            ScholiumMotion.searchPresentation(reduceMotion: reduceMotion),
            value: appState.showSearchSurface
        )
        .sheet(item: presentedSheet) { route in
            sheetContent(for: route)
        }
        .alert(item: presentedAlert) { alert in
            switch alert {
            case .actionFailure(let message):
                Alert(
                    title: Text("Could Not Complete Action"),
                    message: Text(message),
                    dismissButton: .default(Text("Dismiss")) {
                        appState.presentationRouter.alert = nil
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var refreshStatusNotice: some View {
        if let status = appState.refreshStatusText {
            HStack(spacing: ScholiumMetrics.Workspace.refreshStatusSpacing) {
                Label(
                    status,
                    systemImage: appState.hasDerivedRefreshFailure
                        ? "exclamationmark.triangle"
                        : "arrow.triangle.2.circlepath"
                )
                if appState.hasDerivedRefreshFailure {
                    Button("Retry Refresh") {
                        Task { await appState.retryDerivedRefresh() }
                    }
                    .buttonStyle(.borderless)
                    .font(
                        ScholiumTypography.interface(
                            .small,
                            emphasis: .strong
                        )
                    )
                }
            }
            .font(ScholiumTypography.interface(.small))
            .padding(
                .horizontal,
                ScholiumMetrics.Workspace.refreshStatusHorizontalInset
            )
            .padding(
                .vertical,
                ScholiumMetrics.Workspace.refreshStatusVerticalInset
            )
            .scholiumEditorialSurface(
                .floatingControl,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                    style: .continuous
                )
            )
            .padding(ScholiumMetrics.Workspace.refreshStatusOuterInset)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scholium.refreshStatus")
        }
    }

    private var shellLibraryVisible: Bool {
        guard shellState.hasCompletedInitialRestore,
              appState.vaultConfig != nil
        else { return true }
        return shellState.libraryVisible
    }

    private var shellApparatusVisible: Bool {
        ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_DISABLE_INSPECTOR"] != "1"
            && shellState.hasCompletedInitialRestore
            && appState.vaultConfig != nil
            && shellState.inspector.isVisible
    }

    private var presentedSheet: Binding<WindowSheetRoute?> {
        Binding(
            get: { appState.presentationRouter.sheet },
            set: { appState.presentationRouter.sheet = $0 }
        )
    }

    private var presentedAlert: Binding<WindowAlertRoute?> {
        Binding(
            get: { appState.presentationRouter.alert },
            set: { appState.presentationRouter.alert = $0 }
        )
    }

    private var spotlightSearchContext: SpotlightSearchContext {
        SpotlightSearchContext(
            completionContext: searchCompletionContext,
            savedSearches: appState.searchController.savedSearches,
            savedSearchLoadFailure: appState.searchController.savedSearchLoadFailure,
            recoverSavedSearches: {
                await appState.searchController.recoverSavedSearches()
            },
            refresh: { await appState.searchController.refresh() },
            dismiss: { appState.searchController.dismiss() },
            save: { appState.searchController.saveCurrent(named: $0) },
            run: { appState.searchController.run($0) },
            rename: { appState.searchController.rename($0, to: $1) },
            move: { appState.searchController.move($0, by: $1) },
            delete: { appState.searchController.delete($0) },
            openRecord: { recordID, stepID in
                guard let triptychID = windowWorkspaceController.activeCapabilities?.id else {
                    return
                }
                ResearchRecordsWindowCoordinator.shared.submit(.init(
                    triptychID: triptychID,
                    recordID: recordID,
                    stepID: stepID
                ))
                openWindow(
                    id: "scholium-records",
                    value: ResearchRecordsWindowRoute(triptychID: triptychID)
                )
            }
        )
    }

    private var searchCompletionContext: SearchCompletionContext {
        let profiles: [SchemaProfileID]
        switch appState.discoveryController.search.criteria.scope {
        case .currentVault:
            profiles = [NoteMetadataCatalog.profile(for: shellState.selectedWorkspace)]
        case .thisNote:
            profiles = []
        case .triptych:
            profiles = [.analysis, .topicMarkdown, .draftProject]
        }
        let managedContracts = profiles.flatMap {
            workspaceProjectionController.metadataCatalog.contracts(for: $0)
        }
        let authoredContracts = profiles.flatMap {
            PropertyContractCatalog.contracts(for: $0)
        }
        let contracts = managedContracts + authoredContracts
        let keys = Array(Set(contracts.map(\.canonicalKey))).sorted()
        let values = Dictionary(
            contracts.compactMap { contract in
                contract.allowedValues.map { (contract.canonicalKey, $0) }
            },
            uniquingKeysWith: { lhs, rhs in Array(Set(lhs + rhs)).sorted() }
        )
        return SearchCompletionContext(
            propertyKeys: keys,
            propertyValues: values
        )
    }

    private var researchInspectorContentContext: ResearchInspectorContentContext {
        ResearchInspectorContentContext(
            presentation: ResearchOverviewPresentation(
                visibleAttentionItems: visibleCurrentDocumentAttentionItems,
                activityNotificationCount: 0,
                freshness: researchProjectionFreshness,
                aboutConfiguration: appState.currentDocumentAboutConfiguration,
                metadataCatalog: workspaceProjectionController.metadataCatalog,
                settlement: currentAboutSettlementPresentation,
                zoteroBinding: currentAnalysisZoteroBinding,
                stableNoteID: currentAnalysisStableNoteID
            ),
            attentionPopoverSession: appState.attentionPopoverSession,
            openProperties: {
                guard let path = appState.currentNote?.relativePath else { return }
                appState.editingNotePath = path
                appState.showMetadataEditor = true
            },
            openAttention: {
                guard let note = appState.currentNote,
                      let vaultID = appState.currentDocumentVaultID else { return }
                windowCoordinator.actions.showAttention(
                    .queue(
                        anchor: .inspector,
                        workspaceSlot: nil,
                        noteScope: VaultQualifiedNoteID(
                            vaultID: vaultID,
                            relativePath: note.relativePath
                        )
                    )
                )
            },
            retryRefresh: {
                Task { await appState.retryDerivedRefresh() }
            },
            saveManagedAboutField: { note, key, value in
                try await appState.saveManagedAboutField(
                    for: note,
                    key: key,
                    value: value
                )
            },
            saveAuthoredAboutField: { note, key, value in
                try await appState.saveAuthoredAboutField(
                    for: note,
                    key: key,
                    value: value
                )
            },
            openZoteroItem: { binding in
                await appState.zoteroCoordinator.bridge.openInZotero(binding: binding)
            },
            refreshZoteroMetadata: { noteID, binding in
                appState.presentationRouter.present(.zoteroBinding(
                    ZoteroBindingPanelRoute(
                        noteID: noteID,
                        currentBinding: binding,
                        mode: .refresh
                    )
                ))
            },
            manageZoteroBinding: { noteID, binding in
                appState.presentationRouter.present(.zoteroBinding(
                    ZoteroBindingPanelRoute(
                        noteID: noteID,
                        currentBinding: binding
                    )
                ))
            }
        )
    }

    private var currentNoteStableID: UUID? {
        appState.currentNote?.workspaceSnapshot?.stableIdentity.resolvedID
    }

    private var currentSettlementRequirement: WorkspaceSettlementRequirement? {
        guard let noteID = currentNoteStableID else { return nil }
        return researchController.researchSnapshot?.settlementRequirements.first {
            $0.noteID == noteID
        }
    }

    private var currentAboutSettlementPresentation: AboutSettlementPresentation {
        AboutSettlementPresentation.resolve(
            noteID: currentNoteStableID,
            currentRevision: appState.currentNote?.document.fingerprint,
            requirement: currentSettlementRequirement,
            settlements: researchController.researchSnapshot?.settlements ?? []
        )
    }

    private var currentNoteDocumentSession: DocumentSessionModel? {
        if let descriptor = appState.currentDocumentDescriptor {
            return appState.documentController.session(for: descriptor.sessionKey)
        }
        guard let vaultID = appState.currentDocumentVaultID,
              let noteID = currentNoteStableID else { return nil }
        return appState.documentController.session(
            for: DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        )
    }

    private var currentAnalysisZoteroBinding: AnalysisZoteroBinding? {
        guard appState.currentDocumentVaultRole == .sourceCorpus else { return nil }
        guard let note = appState.currentNote,
              let vaultID = appState.currentDocumentVaultID else { return nil }
        return appState.workspaceCatalog?.notes.first {
            $0.reference.vaultID == vaultID
                && $0.reference.relativePath == note.relativePath
        }?.zoteroBinding
    }

    private var currentAnalysisStableNoteID: UUID? {
        guard appState.currentDocumentVaultRole == .sourceCorpus else { return nil }
        return currentNoteStableID
    }

    private var visibleCurrentDocumentAttentionItems: [AttentionQueueItem] {
        guard let note = appState.currentNote,
              let vaultID = appState.currentDocumentVaultID else { return [] }
        let matching = (appState.workspaceCatalog?.attention ?? []).filter {
            $0.note.vaultID == vaultID && $0.note.relativePath == note.relativePath
        }
        return AttentionPreferences.decodeLedger(attentionDismissalLedgerData).visible(matching)
    }

    private var researchProjectionFreshness: ResearchProjectionFreshness {
        if appState.isRefreshingWorkspaceCatalog { return .refreshing }
        switch appState.derivedRefreshStatus {
        case .opening:
            return .refreshing
        case .current:
            return .current
        case .stale(let issue):
            return .stale(issue.reason)
        case .failed(let issue):
            return .failed(issue.reason)
        case nil:
            if appState.workspaceCatalog != nil { return .current }
            return .unavailable(
                appState.workspaceCatalogError ?? "No complete derived workspace snapshot is available."
            )
        }
    }

    private var critiqueProvenanceContext: CritiqueProvenanceContext {
        CritiqueProvenanceContext(
            availableNotes: appState.currentDocumentNotes,
            documentRevisions: appState.currentDocumentRevisions,
            loadAssociation: { path in
                try await appState.researchController.critique(
                    critiqueRelativePath: path
                )
            },
            openTarget: { appState.requestOpenNote($0) },
            openFinding: { finding, fallbackTargetPath in
                appState.openCritiqueFinding(
                    finding,
                    fallbackTargetPath: fallbackTargetPath
                )
            }
        )
    }

    private var documentFeatureState: DocumentFeatureState {
        let note = appState.currentNote
        let path = note?.relativePath
        return DocumentFeatureState(
            notes: appState.currentDocumentNotes,
            selectedDocumentPath: appState.selectedDocumentPath,
            ordinarySearchScope: appState.searchController.ordinaryScope,
            currentVaultID: appState.currentDocumentVaultID,
            vaultRole: appState.currentDocumentVaultRole,
            noteIdentityByPath: appState.currentDocumentIdentityByPath,
            documentRevisions: appState.currentDocumentRevisions,
            workspaceCatalog: appState.workspaceCatalog,
            canEdit: appState.canEditCurrentNote,
            isManagedCritique: appState.currentDocumentCapabilities.isManagedCritique,
            documentTextScale: appState.documentTextScale,
            appearanceCSS: appState.cssSnippetStore.appearanceCSS,
            readCSS: appState.cssSnippetStore.readCSS,
            livePreviewCSS: appState.cssSnippetStore.livePreviewCSS,
            initialScrollFraction: path.map { appState.scrollPosition(for: $0) } ?? 0,
            requestedPresentationMode: appState.requestPresentationMode,
            pendingSourceLine: appState.pendingSourceLine,
            pendingSourceRange: appState.pendingSourceRange,
            identityAmbiguity: appState.currentDocumentIdentityAmbiguity,
            pendingIdentityRebinding: appState.currentDocumentPendingIdentityRebinding,
            identityMigrationFailureMessage: appState.currentDocumentIdentityMigrationFailure?.message,
            isResolvingIdentity: appState.isResolvingIdentity
        )
    }

    private var documentFeatureActions: DocumentFeatureActions {
        let documentPath = appState.currentNote?.relativePath
        return DocumentFeatureActions(
            requestIdentityResolution: {
                guard let path = documentPath else { return }
                appState.requestIdentityResolution(for: path)
            },
            retryIdentityRecovery: { await appState.retryIdentityRecovery() },
            beginSearch: { appState.searchController.begin($0) },
            clearRequestedPresentationMode: { appState.requestPresentationMode = nil },
            clearPendingSourceLine: { appState.pendingSourceLine = nil },
            clearPendingSourceRange: { appState.pendingSourceRange = nil },
            rememberScrollPosition: {
                guard let path = documentPath else { return }
                appState.rememberScrollPosition($0, for: path)
            },
            openInternalLink: {
                guard let path = documentPath else { return }
                appState.openInternalLink($0, from: path)
            },
            openExternalURL: { appState.openExternalURL($0) },
            enterCSSSafeMode: { appState.cssSnippetStore.enterSafeMode(after: $0) },
            rememberPresentationMode: {
                appState.rememberPresentationMode($0)
            },
            setPendingSourceLine: { appState.pendingSourceLine = $0 },
            setSidebarVisible: { windowCoordinator.actions.setLibraryVisible($0) },
            editProperties: {
                guard let path = documentPath else { return }
                appState.editingNotePath = path
                appState.showMetadataEditor = true
            },
            setResearchInspectorVisible: {
                windowCoordinator.actions.setResearchInspectorVisible($0)
            },
            openingDocumentPresentationDidComplete: {
                appState.openingDocumentPresentationDidComplete()
            },
            notify: { message, kind in
                switch kind {
                case .confirmation:
                    appState.presentFeedback(message)
                case .information:
                    appState.presentFeedback(message, kind: .information)
                case .error:
                    appState.presentFeedback(message, kind: .error)
                }
            }
        )
    }

    private var sidebarContext: SidebarContext {
        let propertyFilterOptions = appState.availablePropertyFilterOptions
        let preorderedNotes = appState.filteredNotes
        let folders = appState.currentLibraryFolders
        let selectedLibraryDocumentPath = appState.currentDocumentVaultID
            == appState.currentRegisteredVault?.id
            ? appState.selectedDocumentPath
            : nil
        return SidebarContext(
            triptychName: appState.workspaceAssignment?.triptych.name ?? "Not Selected",
            attentionTotal: sidebarAttentionTotal,
            workspaceNoteCounts: sidebarWorkspaceNoteCounts,
            attentionError: appState.workspaceCatalog == nil
                ? appState.workspaceCatalogError
                : nil,
            treeProjection: appState.libraryTreeProjection(
                preorderedNotes: preorderedNotes,
                folderRelativePaths: folders
            ),
            allNotes: appState.notes,
            folders: folders,
            pathComparisonPolicy: appState.currentLibraryPathComparisonPolicy,
            disclosureScope: appState.currentRegisteredVault.map {
                LibraryDisclosureScope(
                    vaultID: $0.id,
                    sourceScope: appState.noteSourceScope
                )
            },
            selectedDocumentPath: selectedLibraryDocumentPath,
            libraryFocusRequestGeneration: appState.libraryFocusRequestGeneration,
            currentVaultRole: appState.currentVaultRole,
            currentWorkspaceSlot: currentWorkspaceSlot,
            canMutateLibrary: appState.currentRegisteredVault != nil
                && !appState.libraryMutationController.isCreatingNote
                && !appState.libraryMutationController.isMutatingFolder,
            sourceMutationGeneration: appState.sourceMutationGeneration,
            filterOptions: SidebarLibraryFilterOptions(
                catalogIsAvailable: appState.workspaceCatalog != nil,
                graphIsAvailable: appState.linkGraph != nil,
                tags: appState.allTags,
                authors: appState.availableAuthors,
                propertyKeys: propertyFilterOptions.keys,
                propertyValues: propertyFilterOptions.valuesByKey
            ),
            attentionPopoverSession: appState.attentionPopoverSession,
            openAttention: {
                windowCoordinator.actions.showAttention(
                    .queue(
                        anchor: .sidebar,
                        workspaceSlot: nil,
                        noteScope: nil
                    )
                )
            },
            retryAttention: {
                Task { await appState.refreshWorkspaceCatalog() }
            },
            openNote: { appState.requestOpenNote($0, disposition: $1) },
            selectTriptychWorkspace: { appState.requestTriptychWorkspace($0) },
            createUntitledNote: {
                appState.libraryMutationController.requestUntitledNoteCreation(in: $0)
            },
            createUntitledFolder: {
                appState.libraryMutationController.requestUntitledFolderCreation(in: $0)
            },
            moveNote: { target, destination in
                try await appState.libraryMutationController.moveNote(target, to: destination)
            },
            moveFolder: { target, destination in
                try await appState.libraryMutationController.moveFolder(target, to: destination)
            },
            requestFolderFileOperation: {
                appState.folderFileRequest = $0
            },
            requestFolderSystemTrash: {
                do {
                    try await appState.libraryMutationController.prepareFolderSystemTrash($0)
                } catch {
                    appState.presentFeedback(error.localizedDescription, kind: .error)
                }
            },
            copyRelativePath: { path in
                do {
                    try appState.copyTextToClipboard(path)
                    appState.presentFeedback(
                        String(
                            localized: "Relative path copied.",
                            table: "Localizable",
                            bundle: .module
                        )
                    )
                } catch {
                    appState.presentFeedback(error.localizedDescription, kind: .error)
                }
            },
            revealNote: { appState.showInFinder($0) },
            requestSystemTrash: {
                do {
                    try await appState.libraryMutationController.prepareNoteSystemTrash($0)
                } catch {
                    appState.presentFeedback(error.localizedDescription, kind: .error)
                }
            },
            revealCurrentVault: { appState.revealVaultInFinder() },
            openSettings: { openSettings() },
            selectSortOrder: { appState.discoveryController.selectSortOrder($0) },
            showError: { appState.presentFeedback($0, kind: .error) }
        )
    }

    private var sidebarAttentionTotal: Int? {
        let settlementCount = researchController.researchSnapshot?
            .settlementRequirements.count ?? 0
        let issueCount = AttentionPreferences.visibleTotalCount(
            catalog: appState.workspaceCatalog,
            assignment: appState.workspaceAssignment,
            dismissalLedgerData: attentionDismissalLedgerData
        )
        if let issueCount { return issueCount + settlementCount }
        let persistentCount = settlementCount
        return persistentCount > 0 ? persistentCount : nil
    }

    private var sidebarWorkspaceNoteCounts: SidebarWorkspaceNoteCounts {
        guard let assignment = appState.workspaceAssignment else {
            return SidebarWorkspaceNoteCounts(values: [:])
        }
        let snapshots = workspaceProjectionController.vaultSnapshotsByID
        var values: [WorkspaceVaultSlot: Int] = [:]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vaultID = assignment.vault(for: slot)?.id,
                  let snapshot = snapshots[vaultID] else {
                continue
            }
            values[slot] = snapshot.documents.count {
                !$0.capabilities.isManagedCritique
            }
        }
        return SidebarWorkspaceNoteCounts(values: values)
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        appState.currentWorkspaceSlot
    }

    @ViewBuilder
    private func sheetContent(for route: WindowSheetRoute) -> some View {
        switch route {
        case .metadata(let route):
            if let note = note(at: route.path) {
                MetadataEditorView(
                    note: note,
                    metadataCatalog: workspaceProjectionController.metadataCatalog,
                    expectedRevision: note.workspaceSnapshot?.metadata?.revision,
                    onClose: {
                        finishMetadata(route)
                    },
                    reload: {
                        try await appState.reloadMetadata(for: note.relativePath)
                    }
                ) { fields, revision in
                    _ = try await appState.saveMetadata(
                        for: note,
                        proposedFields: fields,
                        expectedRevision: revision
                    )
                }
                    .frame(minWidth: 520, minHeight: 560)
            }
        case .noteFileOperation(let request):
            NoteFileOperationView(
                request: request,
                actions: NoteFileActions(
                    duplicate: { source, destination in
                        _ = try await appState.libraryMutationController.duplicateNote(
                            source,
                            to: destination
                        )
                    },
                    move: { source, destination in
                        try await appState.libraryMutationController.moveNote(
                            source,
                            to: destination
                        )
                    }
                )
            )
        case .folderFileOperation(let request):
            FolderFileOperationView(
                request: request,
                folderRelativePaths: appState.currentLibraryFolders,
                actions: FolderFileActions(
                    move: { target, destination in
                        try await appState.libraryMutationController.moveFolder(
                            target,
                            to: destination
                        )
                    }
                )
            )
        case .systemTrash(let preview):
            SystemTrashConfirmationView(
                preview: preview,
                confirm: { preview in
                    try await appState.libraryMutationController.executeSystemTrash(preview)
                    appState.presentationRouter.dismissSheet()
                },
                cancel: { appState.presentationRouter.dismissSheet() }
            )
        case .transactionRecovery:
            TransactionRecoveryView(
                records: appState.transactionRecoveryRecords,
                error: appState.transactionRecoveryError,
                interruptedSaves: appState.interruptedSaveRecoveries,
                interruptedSaveError: appState.interruptedSaveRecoveryError,
                vaultNames: Dictionary(
                    uniqueKeysWithValues: appState.registeredVaults.map { ($0.id, $0.name) }
                ),
                refresh: { await appState.refreshTransactionRecoveryRecords() },
                markResolved: { try await appState.markTransactionRecoveryResolved($0) },
                revealRecords: { appState.revealTransactionRecoveryRecordsInFinder() },
                loadInterruptedSave: {
                    try await appState.interruptedSaveRecoveryContent($0)
                },
                revealInterruptedSave: {
                    try await appState.revealInterruptedSaveRecoveryInFinder($0)
                },
                restoreInterruptedSave: {
                    try await appState.restoreInterruptedSaveRecovery($0)
                }
            )
        case .identityResolution(let ambiguity):
            IdentityResolutionView(
                ambiguity: ambiguity,
                vaultName: appState.currentDocumentVault?.name
                    ?? appState.currentRegisteredVault?.name
                    ?? "Current Vault",
                isResolving: appState.isResolvingIdentity,
                errorMessage: appState.identityResolutionError,
                onConfirm: { candidateID in
                    await appState.resolveSelectedIdentity(candidateID: candidateID)
                },
                onCancel: {
                    appState.presentationRouter.dismissSheet(if: route.id)
                    appState.identityResolutionError = nil
                }
            )
            .onDisappear {
                appState.identityResolutionError = nil
            }
        case .zoteroBinding(let route):
            ZoteroBindingPanelView(
                route: route,
                search: { query in
                    try await appState.zoteroCoordinator.searchLibrary(query: query)
                },
                prepareFill: { hit in
                    try await appState.zoteroCoordinator.prepareLinkAndFill(
                        noteID: route.noteID,
                        library: hit.library,
                        itemKey: hit.item.key
                    )
                },
                prepareRefresh: {
                    try await appState.zoteroCoordinator.prepareMetadataRefresh(
                        noteID: route.noteID
                    )
                },
                commitPlan: { plan in
                    try await appState.zoteroCoordinator.commitMetadataPlan(plan)
                    appState.presentationRouter.dismissSheet()
                },
                clearBinding: {
                    try await appState.zoteroCoordinator.clearBinding(noteID: route.noteID)
                    appState.presentationRouter.dismissSheet()
                },
                dismiss: { appState.presentationRouter.dismissSheet() }
            )
        case .agentChanges:
            AgentChangesView(
                load: {
                    guard let operations = appState.windowWorkspaceController
                        .activeCapabilities?.agentCollaboration else {
                        throw ScholiumApplicationError.critiqueStoreUnavailable(
                            "No workspace is active."
                        )
                    }
                    return try await operations.agentChanges()
                },
                loadReview: { changeID in
                    guard let operations = appState.windowWorkspaceController
                        .activeCapabilities?.agentCollaboration else {
                        throw ScholiumApplicationError.critiqueStoreUnavailable(
                            "No workspace is active."
                        )
                    }
                    return try await operations.agentChangeReview(id: changeID)
                },
                undo: { change in
                    guard let operations = appState.windowWorkspaceController
                        .activeCapabilities?.agentCollaboration,
                          let fingerprint = change.afterFingerprint else {
                        throw AgentChangeError.undoUnavailable(change.id)
                    }
                    _ = try await operations.undoAgentChange(
                        id: change.id,
                        expectedAfterFingerprint: fingerprint
                    )
                    await appState.refreshWorkspaceCatalog()
                }
            )
        }
    }

    private func note(at path: String) -> WindowDocumentLocation? {
        if appState.currentNote?.relativePath == path {
            return appState.currentNote
        }
        return appState.notes.first(where: { $0.relativePath == path })
    }

    private func finishMetadata(_ route: MetadataPanelRoute) {
        appState.presentationRouter.finishMetadata(route)
    }

    @ViewBuilder
    private var detailRegion: some View {
        VStack(spacing: 0) {
            refreshStatusNotice
            if !appState.transactionRecoveryRecords.isEmpty
                || !appState.interruptedSaveRecoveries.isEmpty
                || appState.transactionRecoveryError != nil
                || appState.interruptedSaveRecoveryError != nil {
                TransactionRecoveryNotice(
                    count: appState.transactionRecoveryRecords.count
                        + appState.interruptedSaveRecoveries.count,
                    error: appState.transactionRecoveryError
                        ?? appState.interruptedSaveRecoveryError
                ) {
                    appState.showTransactionRecovery = true
                }
            }
            detailContent
        }
    }

    @ViewBuilder
    private var windowTopNotificationOverlay: some View {
        if shellState.hasCompletedInitialRestore {
            windowTopNotificationSurface
            .zIndex(10)
        }
    }

    @ViewBuilder
    private var windowTopNotificationSurface: some View {
        if let feedback = shellState.persistentFeedbackItems.first {
            WindowFeedbackItem(
                feedback: feedback,
                dismiss: { shellState.dismissFeedback(id: feedback.id) }
            )
            .transition(
                ScholiumMotion.transientStatusTransition(
                    reduceMotion: reduceMotion,
                    edge: .top
                )
            )
        }
    }

    @ViewBuilder
    private var apparatusRegion: some View {
        if let note = appState.currentNote {
            ResearchInspectorView(
                note: note,
                shellState: appState.shellState,
                graph: appState.linkGraph,
                catalog: appState.workspaceCatalog,
                currentVaultID: appState.currentDocumentVaultID,
                researchInspectorContentContext: researchInspectorContentContext,
                openReference: { reference, sourceLine in
                    appState.researchController.requestOpen(
                        reference,
                        sourceLine: sourceLine
                    )
                }
            )
        } else {
            ScholiumContentStateView(
                "No Document Selected",
                indicator: .symbol("doc.text")
            )
            .accessibilityIdentifier("scholium.noDocumentInspectorState")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scholiumSurface(.apparatus)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.currentNote != nil {
            DocumentFeatureView(
                controller: appState.documentController,
                state: documentFeatureState,
                actions: documentFeatureActions,
                critiqueProvenanceContext: critiqueProvenanceContext
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(
                    ScholiumMotion.documentRevealTransition(
                        showingDocument: true,
                        reduceMotion: reduceMotion
                    )
                )
                .zIndex(0)
                .overlay(alignment: .bottomTrailing) {
                    if let settlementTarget {
                        DocumentSettlementControl(
                            presentation: currentAboutSettlementPresentation,
                            settle: { rationale in
                                _ = try await researchController.settle(
                                    settlementTarget.note,
                                    expectedRevision: settlementTarget.fingerprint,
                                    rationale: rationale
                                )
                                try await researchController.refreshResearchProjection()
                            }
                        )
                        .padding(ScholiumGrid.Spacing.sectionSeparation)
                    }
                }
        } else {
            ScholiumNoDocumentDetailView()
                .transition(
                    ScholiumMotion.documentRevealTransition(
                        showingDocument: false,
                        reduceMotion: reduceMotion
                    )
                )
        }
    }

    private var settlementTarget: (note: VaultQualifiedNoteID, fingerprint: DocumentFingerprint)? {
        guard let note = appState.currentNote,
              let vaultID = appState.currentDocumentVaultID,
              currentNoteStableID != nil else { return nil }
        return (
            VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: note.relativePath
            ),
            note.document.fingerprint
        )
    }
}

private struct LibrarySurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .scholiumSurface(.navigation)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Library")
            .accessibilityIdentifier("scholium.librarySurface")
    }
}

struct ScholiumLaunchPlaceholderView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Opening Scholium")
    }
}

/// The configured workspace's restrained, read-only no-document state. The
/// Library remains the only actionable interface and this view owns no focus
/// or document state.
private struct ScholiumNoDocumentDetailView: View {
    var body: some View {
        ZStack {
            ScholiumColorRole.documentBackground.color
                .accessibilityHidden(true)

            ScholiumContentStateView(
                "No Document Selected",
                detail: Text("Select a note in the Library to read or edit."),
                indicator: .symbol("doc.text")
            )
            .accessibilityIdentifier("scholium.noDocumentState")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SpotlightSearchOverlay: View {
    @ObservedObject private var controller: DiscoveryController
    let context: SpotlightSearchContext

    init(controller: DiscoveryController, context: SpotlightSearchContext) {
        self.controller = controller
        self.context = context
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: context.dismiss)
                    .accessibilityHidden(true)

                SpotlightSearchPanelView(
                    controller: controller,
                    context: context,
                    maxPanelHeight: max(
                        ScholiumMetrics.Search.collapsedHeight,
                        geometry.size.height
                            - (ScholiumMetrics.Search.responsiveMargin * 2)
                    )
                )
                    .frame(width: panelWidth(for: geometry.size.width))
                    .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
                    .padding(.top, ScholiumMetrics.Search.responsiveMargin)
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityValue(searchPresentationValue)
        .accessibilityIdentifier("scholium.searchWorkspace")
    }

    private func panelWidth(for availableWidth: CGFloat) -> CGFloat {
        min(
            ScholiumMetrics.Search.preferredWidth,
            max(
                320,
                availableWidth - (ScholiumMetrics.Search.responsiveMargin * 2)
            )
        )
    }

    private var searchPresentationValue: String {
        controller.search.criteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? "Collapsed" : "Expanded"
    }
}

// MARK: - Loading Overlay

private struct LoadingOverlay: View {
    var body: some View {
        ProgressView("Opening vault…")
            .controlSize(.large)
            .padding(ScholiumMetrics.Workspace.loadingOverlayInset)
            .scholiumEditorialSurface(
                .floatingControl,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.loadingSurfaceCornerRadius,
                    style: .continuous
                )
            )
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("scholium.loadingOverlay")
    }
}

// MARK: - Window Feedback

private struct WindowFeedbackItem: View {
    let feedback: WindowFeedback
    let dismiss: () -> Void

    var body: some View {
        ScholiumOperationFeedback(
            id: feedback.id,
            message: feedback.message,
            kind: feedback.kind,
            maximumWidth: feedback.kind.dismissesAutomatically
                ? ScholiumMetrics.Notice.transientToastMaximumWidth
                : ScholiumMetrics.Notice.windowFeedbackMaximumWidth,
            accessibilityIdentifierPrefix: "scholium.windowFeedback",
            dismiss: dismiss
        )
    }
}

enum DocumentSettlementRailAction: Hashable {
    case settle
    case settleAgain
    case unavailable

    static func resolve(
        _ state: AboutSettlementState
    ) -> DocumentSettlementRailAction {
        switch state {
        case .notYetSettled:
            .settle
        case .settled, .changedSinceSettlement:
            .settleAgain
        case .unavailable:
            .unavailable
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .settle:
            "Settle"
        case .settleAgain:
            "Settle Again"
        case .unavailable:
            "Settlement Unavailable"
        }
    }

    var help: LocalizedStringResource {
        switch self {
        case .settle:
            "Settle this note"
        case .settleAgain:
            "Settle this note again"
        case .unavailable:
            "Settlement is unavailable"
        }
    }
}

private struct DocumentSettlementControl: View {
    let presentation: AboutSettlementPresentation
    let settle: (String?) async throws -> Void

    @State private var isPresented = false
    @State private var rationale = ""
    @State private var errorMessage: String?
    @State private var isSettling = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: presentation.state == .settled
                ? "checkmark.circle.fill"
                : "checkmark.circle")
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.bordered)
        .disabled(presentation.state == .unavailable)
        .help(actionHelp)
        .accessibilityLabel(actionTitle)
        .accessibilityIdentifier("scholium.document.settle")
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.sectionContentSpacing) {
                Text(actionTitle)
                    .font(ScholiumTypography.interface(.sectionTitle))
                Text("Record this saved revision as sufficiently stable for current research.")
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Optional rationale", text: $rationale, axis: .vertical)
                    .lineLimit(2...4)
                if let errorMessage {
                    Text(errorMessage)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.attention)
                }
                HStack {
                    Button("Cancel") {
                        rationale = ""
                        errorMessage = nil
                        isPresented = false
                    }
                    Spacer()
                    Button(actionTitle) {
                        isSettling = true
                        errorMessage = nil
                        Task {
                            do {
                                try await settle(rationale)
                                rationale = ""
                                isSettling = false
                                isPresented = false
                            } catch {
                                errorMessage = error.localizedDescription
                                isSettling = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSettling)
                }
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)
            .frame(width: 300)
        }
    }

    private var actionTitle: LocalizedStringResource {
        DocumentSettlementRailAction.resolve(presentation.state).title
    }

    private var actionHelp: LocalizedStringResource {
        DocumentSettlementRailAction.resolve(presentation.state).help
    }
}

// MARK: - Preview

#Preview {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let workspaceStore = try! WorkspaceStore(
        applicationSupportURL: repositoryRoot
            .appendingPathComponent(".build/previews", isDirectory: true)
            .appendingPathComponent("ContentView", isDirectory: true)
    )
    let model = WindowModel(workspaceStore: workspaceStore)
    let coordinator = WorkspaceWindowCoordinator(
        windowID: model.nativeWindowID,
        appState: model,
        lifecycleRegistry: ScholiumWindowLifecycleRegistry()
    )
    ContentView(appState: model, windowCoordinator: coordinator)
        .frame(width: 1100, height: 700)
}
