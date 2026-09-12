import ScholiumContracts
import SwiftUI

private enum DocumentTitleRenameError: LocalizedError {
    case invalidName
    case noteUnavailable
    case titleChangedElsewhere

    var errorDescription: String? {
        switch self {
        case .invalidName:
            String(localized: "That note name cannot be used.", table: "Localizable", bundle: .module)
        case .noteUnavailable:
            String(
                localized: "This note is no longer available to rename.", table: "Localizable",
                bundle: .module)
        case .titleChangedElsewhere:
            String(
                localized:
                    "The note was renamed elsewhere. Review its current title before renaming again.",
                table: "Localizable", bundle: .module)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var operationIssueHeight: CGFloat = 0
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
        Group {
            if appState.isDetachedDocumentWindow {
                detailRegion
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ScholiumColorRole.documentBackground.color)
            } else {
                workspaceShell
            }
        }
        .environment(
            \.openChatNoteInSeparateWindow,
            { url in
                _ = appState.openChatReference(url, disposition: .separateWindow)
            }
        )
        .sheet(item: presentedSheet) { route in
            sheetContent(for: route)
                .buttonStyle(.automatic)
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

    private var workspaceShell: some View {
        ScholiumWorkspaceSplitView(
            sidebarContent: shellState.sidebarContent,
            initialLibraryVisible: shellLibraryVisible,
            initialApparatusVisible: shellApparatusVisible,
            documentTabs: appState.documentTabController.tabs,
            selectedDocumentTabID: appState.documentTabController.selectedTabID,
            selectDocumentTab: { appState.selectDocumentTab(withID: $0) },
            closeDocumentTab: { appState.closeDocumentTab(withID: $0) },
            detachDocumentTab: { appState.requestMoveDocumentToWindow(tabID: $0, at: $1) },
            reorderDocumentTab: { appState.documentTabController.moveTab(withID: $0, to: $1) },
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
                ResearchSearchSurface(
                    controller: discoveryController, searchController: searchController,
                    shellState: shellState, workspaceProjectionController: workspaceProjectionController,
                    presentation: .sidebar,
                    revealDocument: { windowCoordinator.makeKeyAndOrderFront() }
                ) {
                    SidebarView(controller: appState.discoveryController, context: sidebarContext)
                }
            }
            .buttonStyle(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } chat: {
            LibrarySurface {
                if let chat = appState.chatController {
                    AgentChatView(
                        controller: chat,
                        isVisible: shellState.libraryVisible && shellState.sidebarContent == .chat,
                        addSelection: { Task { await appState.addCurrentSelectionToChat() } },
                        noteChoices: appState.workspaceCatalog?.notes ?? [],
                        addNote: { note, conversationID in
                            try await appState.addNoteToChat(note, conversationID: conversationID)
                        },
                        openReference: { appState.openChatReference($0) },
                        openAttachment: { attachment in Task { await appState.openChatAttachment(attachment) }
                        },
                        showInLibrary: { url in
                            if appState.openChatReference(url) {
                                if !shellState.libraryVisible || shellState.sidebarContent != .triptych {
                                    windowCoordinator.actions.activateSidebar(.triptych)
                                }
                            }
                        },
                        showChanges: { appState.presentationRouter.present(.agentChanges(scope: .exact($0))) },
                        showConversationChanges: {
                            appState.presentationRouter.present(.agentChanges(scope: .conversation($0)))
                        }, changes: researchController.agentChanges,
                        changesError: researchController.agentChangesError
                    )
                    .task { researchController.scheduleAgentChangesRefresh() }
                    .onChange(of: chat.selected?.messages.compactMap(\.changeID)) { _, _ in
                        researchController.scheduleAgentChangesRefresh()
                    }
                }
            }
            .buttonStyle(.automatic)
            .menuStyle(.automatic)
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
            .buttonStyle(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } apparatus: {
            apparatusRegion
                .buttonStyle(.automatic)
                .scholiumSurface(.apparatus)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
        // The native split and each semantic background fill the complete
        // titlebar frame. Native Liquid Glass controls float above those planes;
        // the toolbar contributes no competing full-width material band.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
            }
        }
        .focusedSceneValue(
            \.scholiumSearchActions,
            ScholiumSearchActions(
                begin: { searchController.begin($0) },
                advanced: { searchController.beginAdvanced() }
            )
        )
        .onChange(of: searchController.focusRequestID) { _, _ in
            switch searchController.presentation {
            case .sidebar:
                _ = shellState.activateSidebar(.triptych)
                windowCoordinator.actions.setLibraryVisible(true)
                windowCoordinator.closeAdvancedSearch()
            case .advanced:
                windowCoordinator.presentAdvancedSearch {
                    ResearchSearchSurface(
                        controller: discoveryController, searchController: searchController,
                        shellState: shellState, workspaceProjectionController: workspaceProjectionController,
                        presentation: .advanced,
                        revealDocument: { windowCoordinator.makeKeyAndOrderFront() }
                    ) {
                        EmptyView()
                    }
                }
            case .inactive:
                break
            }
        }
        .onChange(of: searchController.presentation) { _, presentation in
            if presentation == .inactive { windowCoordinator.closeAdvancedSearch() }
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

    private var researchInspectorContentContext: ResearchInspectorContentContext {
        ResearchInspectorContentContext(
            freshness: researchProjectionFreshness,
            retryRefresh: { Task { await appState.retryDerivedRefresh() } }
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

    private var currentNoteDocumentSession: DocumentSessionModel? {
        if let descriptor = appState.currentDocumentDescriptor {
            return appState.documentController.session(for: descriptor.sessionKey)
        }
        guard let vaultID = appState.currentDocumentVaultID,
            let noteID = currentNoteStableID
        else { return nil }
        return appState.documentController.session(
            for: DocumentSessionKey(vaultID: vaultID, noteID: noteID)
        )
    }

    private var currentDocumentNotificationScope: VaultQualifiedNoteID? {
        guard let note = appState.currentNote,
            let vaultID = appState.currentDocumentVaultID
        else { return nil }
        return VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath)
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
            documentTextScale: appState.documentTextScale,
            appearanceCSS: appState.cssSnippetStore.appearanceCSS,
            readCSS: appState.cssSnippetStore.readCSS,
            livePreviewCSS: appState.cssSnippetStore.livePreviewCSS,
            initialScrollFraction: path.map { appState.scrollPosition(for: $0) } ?? 0,
            requestedPresentationMode: appState.requestPresentationMode,
            sourceLocationRequest: appState.documentController.sourceLocationRequest,
            identityAmbiguity: appState.currentDocumentIdentityAmbiguity,
            pendingIdentityRebinding: appState.currentDocumentPendingIdentityRebinding,
            identityMigrationFailureMessage: appState.currentDocumentIdentityMigrationFailure?.message,
            isResolvingIdentity: appState.isResolvingIdentity
        )
    }

    private var documentFeatureActions: DocumentFeatureActions {
        let documentKey = appState.currentDocumentDescriptor?.sessionKey
        let documentPath = appState.currentNote?.relativePath
        return DocumentFeatureActions(
            askAgent: { inquiry, validate in
                guard appState.currentDocumentDescriptor?.sessionKey == documentKey else { return nil }
                return await appState.runSelectionInquiry(inquiry, validate: validate) {
                    windowCoordinator.actions.activateSidebar(.chat)
                }
            },
            requestIdentityResolution: {
                guard let path = documentPath else { return }
                appState.requestIdentityResolution(for: path)
            },
            retryIdentityRecovery: { await appState.retryIdentityRecovery() },
            beginSearch: { appState.searchController.begin($0) },
            clearRequestedPresentationMode: { appState.requestPresentationMode = nil },
            consumeSourceLocation: { appState.documentController.consumeSourceLocation($0) },
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
            setSidebarVisible: { windowCoordinator.actions.setLibraryVisible($0) },
            setResearchInspectorVisible: {
                windowCoordinator.actions.setResearchInspectorVisible($0)
            },
            openingDocumentPresentationDidComplete: {
                appState.openingDocumentPresentationDidComplete()
            },
            renameNote: { requestedNote, expectedTitle, requestedTitle in
                guard
                    let requestedStableID = requestedNote.workspaceSnapshot?
                        .stableIdentity.resolvedID,
                    let currentNote = appState.currentNote,
                    currentNote.vaultID == requestedNote.vaultID,
                    currentNote.workspaceSnapshot?.stableIdentity.resolvedID
                        == requestedStableID
                else {
                    throw DocumentTitleRenameError.noteUnavailable
                }
                guard currentNote.displayName == expectedTitle else {
                    throw DocumentTitleRenameError.titleChangedElsewhere
                }
                guard let target = NoteMutationTarget(currentNote),
                    let destination = noteRenameDestination(
                        sourceRelativePath: currentNote.relativePath,
                        requestedName: requestedTitle
                    )
                else {
                    throw DocumentTitleRenameError.invalidName
                }
                guard destination != currentNote.relativePath else {
                    return currentNote.displayName
                }
                try await appState.libraryMutationController.moveNote(
                    target,
                    to: destination
                )
                return URL(fileURLWithPath: destination)
                    .deletingPathExtension()
                    .lastPathComponent
            },
            notify: { message, kind in
                switch kind {
                case .information:
                    appState.reportOperationIssue(message, kind: .information)
                case .error:
                    appState.reportOperationIssue(message, kind: .error)
                }
            }
        )
    }

    private var sidebarContext: SidebarContext {
        let propertyFilterOptions = appState.availablePropertyFilterOptions
        let preorderedNotes = appState.filteredNotes
        let folders = appState.currentLibraryFolders
        let selectedLibraryDocumentPath =
            appState.currentDocumentVaultID
                == appState.currentRegisteredVault?.id
            ? appState.selectedDocumentPath
            : nil
        return SidebarContext(
            workspaceNoteCounts: sidebarWorkspaceNoteCounts,
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
            requestedWorkspaceSlot: appState.requestedWorkspaceSelection,
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
            openNote: { appState.requestOpenNote($0, disposition: $1) },
            canAddNoteToChat: { appState.canAddLibraryNoteToChat($0) },
            addNoteToChat: { note in
                guard appState.addLibraryNoteToChat(note) else { return }
                if appState.shellState.sidebarContent != .chat || !appState.shellState.libraryVisible {
                    windowCoordinator.actions.activateSidebar(.chat)
                }
            },
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
                    appState.reportOperationIssue(error.localizedDescription, kind: .error)
                }
            },
            copyRelativePath: { path in
                do {
                    try appState.copyTextToClipboard(path)

                } catch {
                    appState.reportOperationIssue(error.localizedDescription, kind: .error)
                }
            },
            revealNote: { appState.showInFinder($0) },
            requestSystemTrash: {
                do {
                    try await appState.libraryMutationController.prepareNoteSystemTrash($0)
                } catch {
                    appState.reportOperationIssue(error.localizedDescription, kind: .error)
                }
            },
            revealCurrentVault: { appState.revealVaultInFinder() },
            openSettings: { openSettings() },
            selectSortOrder: { appState.discoveryController.selectSortOrder($0) },
            showError: { appState.reportOperationIssue($0, kind: .error) }
        )
    }

    private var sidebarWorkspaceNoteCounts: SidebarWorkspaceNoteCounts {
        guard let assignment = appState.workspaceAssignment else {
            return SidebarWorkspaceNoteCounts(values: [:])
        }
        let snapshots = workspaceProjectionController.vaultSnapshotsByID
        var values: [WorkspaceVaultSlot: Int] = [:]
        for slot in WorkspaceVaultSlot.allCases {
            guard let vaultID = assignment.vault(for: slot)?.id,
                let snapshot = snapshots[vaultID]
            else {
                continue
            }
            values[slot] = snapshot.documents.count
        }
        return SidebarWorkspaceNoteCounts(values: values)
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        appState.currentWorkspaceSlot
    }

    @ViewBuilder
    private func sheetContent(for route: WindowSheetRoute) -> some View {
        switch route {
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

        case .agentChanges(let scope):
            AgentChangesView(
                scope: scope,
                load: {
                    try await researchController.agentChangeHistory()
                },
                loadReview: { changeID in
                    guard
                        let operations = appState.windowWorkspaceController
                            .activeCapabilities?.agentCollaboration
                    else {
                        throw ScholiumApplicationError.noWorkspaceConfigured
                    }
                    return try await operations.agentChangeReview(id: changeID)
                },
                undo: { change in
                    guard
                        let operations = appState.windowWorkspaceController
                            .activeCapabilities?.agentCollaboration,
                        let fingerprint = change.afterFingerprint
                    else {
                        throw AgentChangeError.undoUnavailable(change.id)
                    }
                    _ = try await operations.undoAgentChange(
                        id: change.id,
                        expectedAfterFingerprint: fingerprint
                    )
                    await appState.refreshWorkspaceCatalog()
                    _ = try await researchController.loadAgentChanges()
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

    @ViewBuilder
    private var detailRegion: some View {
        VStack(spacing: 0) {
            if !appState.transactionRecoveryRecords.isEmpty
                || !appState.interruptedSaveRecoveries.isEmpty
                || appState.transactionRecoveryError != nil
                || appState.interruptedSaveRecoveryError != nil
            {
                TransactionRecoveryNotice(
                    count: appState.transactionRecoveryRecords.count
                        + appState.interruptedSaveRecoveries.count,
                    error: appState.transactionRecoveryError
                        ?? appState.interruptedSaveRecoveryError
                ) {
                    appState.showTransactionRecovery = true
                }
            }
            if !shellState.operationIssues.isEmpty || appState.refreshStatusText != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(shellState.operationIssues) { issue in
                            ScholiumOperationIssueView(
                                issue: issue,
                                refresh: { Task { await appState.retryDerivedRefresh() } },
                                dismiss: { shellState.dismissOperationIssue(id: issue.id) })
                        }
                        if let status = appState.refreshStatusText {
                            HStack {
                                Text(status).font(ScholiumTypography.interface(.body)).textSelection(.enabled)
                                if appState.hasDerivedRefreshFailure {
                                    Button("Retry Refresh") { Task { await appState.retryDerivedRefresh() } }
                                }
                            }
                            .accessibilityIdentifier("scholium.refreshStatus")
                        }
                    }
                    .padding(12)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        operationIssueHeight = $0
                    }
                }
                .frame(height: min(operationIssueHeight, 180))
            }
            detailContent
        }
        .animation(
            ScholiumMotion.documentReveal(reduceMotion: reduceMotion),
            value: appState.currentNote != nil
        )
    }

    @ViewBuilder
    private var apparatusRegion: some View {
        if let note = appState.currentNote {
            ResearchInspectorView(
                research: researchController,
                editor: appState.presentedDocumentMode == .read ? nil : currentNoteDocumentSession?.editorSession,
                noteURL: appState.workspaceAssignment?.vaults.values.first(where: { $0.id == appState.currentDocumentVaultID }).map {
                    URL(fileURLWithPath: $0.canonicalPath).appendingPathComponent(note.relativePath)
                },
                vaultRoots: appState.workspaceAssignment?.vaults.values.map { URL(fileURLWithPath: $0.canonicalPath) } ?? [],
                openExternalURL: { appState.openExternalURL($0) },
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
                },
                findRelated: { appState.findRelatedMaterials(automatic: true, paragraph: true) },
                retryRelated: { appState.retryRelatedMaterials() },
                openRelated: { card in Task { _ = await appState.useRelatedMaterial(card, inChat: false) }
                },
                insertRelated: { card in Task { await appState.insertRelatedMaterialLink(card) } },
                discussRelated: { card in
                    Task {
                        if await appState.useRelatedMaterial(card, inChat: true),
                            !shellState.libraryVisible || shellState.sidebarContent != .chat
                        {
                            windowCoordinator.actions.activateSidebar(.chat)
                        }
                    }
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
                documentInformation: appState.documentInformation,
                state: documentFeatureState,
                actions: documentFeatureActions
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(
                ScholiumMotion.documentRevealTransition(
                    showingDocument: true,
                    reduceMotion: reduceMotion
                )
            )
            .zIndex(0)
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

}

private struct LibrarySurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
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

// MARK: - Loading Overlay

private struct LoadingOverlay: View {
    var body: some View {
        ProgressView("Opening vault…")
            .controlSize(.large)
            .padding(ScholiumMetrics.Workspace.loadingOverlayInset)
            .scholiumFloatingSurface(
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.loadingSurfaceCornerRadius,
                    style: .continuous
                )
            )
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("scholium.loadingOverlay")
    }
}

// MARK: - Preview

#Preview {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let workspaceStore = try! WorkspaceStore(
        applicationSupportURL:
            repositoryRoot
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
