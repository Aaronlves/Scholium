import ScholiumContracts
import SwiftUI

enum DiscussionPresentationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Discussion is unavailable until Scholium can identify the selected Analysis, Topic, or Work reliably."
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @ObservedObject var appState: WindowModel
    @ObservedObject private var presentationRouter: WindowPresentationRouter
    @ObservedObject private var discoveryController: DiscoveryController
    @ObservedObject private var searchController: WindowSearchController
    @ObservedObject private var researchController: ResearchController
    @ObservedObject private var researchActionController: ResearchActionController
    @ObservedObject private var shellState: WindowShellState
    @ObservedObject private var documentController: DocumentController
    @ObservedObject private var documentTabController: DocumentTabController
    @ObservedObject private var workspaceProjectionController: WindowWorkspaceProjectionController
    @ObservedObject private var researchAgentPermissionWindowController:
        ResearchAgentPermissionWindowController
    @ObservedObject private var cssSnippetStore: CSSSnippetStore
    @ObservedObject private var windowWorkspaceController: WindowWorkspaceController
    let windowCoordinator: WorkspaceWindowCoordinator
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()
    @State private var pendingResearchActionFocusID: ResearchActionID?
    @State private var researchActionFocusRequest: ResearchActionFocusRequest?

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
        _researchActionController = ObservedObject(
            wrappedValue: appState.researchController.actions
        )
        _shellState = ObservedObject(wrappedValue: appState.shellState)
        _documentController = ObservedObject(wrappedValue: appState.documentController)
        _documentTabController = ObservedObject(wrappedValue: appState.documentTabController)
        _workspaceProjectionController = ObservedObject(
            wrappedValue: appState.workspaceProjectionController
        )
        _researchAgentPermissionWindowController = ObservedObject(
            wrappedValue: appState.researchAgentPermissionWindowController
        )
        _cssSnippetStore = ObservedObject(wrappedValue: appState.cssSnippetStore)
        _windowWorkspaceController = ObservedObject(
            wrappedValue: appState.windowWorkspaceController
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
        .ignoresSafeArea(.container, edges: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(
            ScholiumMotion.documentReveal(reduceMotion: reduceMotion),
            value: appState.currentNote != nil
        )
        .overlay(alignment: .bottom) {
            if let toast = appState.toastMessage {
                ToastView(toast: toast)
                    .transition(
                        ScholiumMotion.transientStatusTransition(
                            reduceMotion: reduceMotion
                        )
                    )
                    .padding(.bottom, ScholiumGrid.Spacing.regionContentInset)
            }
        }
        .animation(
            ScholiumMotion.transientStatus(reduceMotion: reduceMotion),
            value: appState.toastMessage
        )
        .overlay(alignment: .topTrailing) {
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
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    }
                }
                .font(ScholiumTypography.interface(.small))
                .padding(.horizontal, ScholiumMetrics.Workspace.refreshStatusHorizontalInset)
                .padding(.vertical, ScholiumMetrics.Workspace.refreshStatusVerticalInset)
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
        .onChange(of: shellState.researchResultNotice) { previous, current in
            guard current != nil, current != previous else { return }
            AccessibilityNotification.Announcement(
                String(
                    localized: "An Agent result is ready to review.",
                    table: "Localizable",
                    bundle: .module
                )
            ).post()
        }
        .onChange(
            of: shellState.researchNotificationPermissionNotice
        ) { previous, current in
            guard let current, current != previous else { return }
            let message = switch current {
            case .enable:
                String(
                    localized: "Get Notified When Results Are Ready",
                    table: "Localizable",
                    bundle: .module
                )
            case .openSettings:
                String(
                    localized: "Notifications Are Off",
                    table: "Localizable",
                    bundle: .module
                )
            }
            AccessibilityNotification.Announcement(message).post()
        }
        .sheet(item: presentedSheet, onDismiss: {
            let permissionController = appState
                .researchAgentPermissionWindowController
            if permissionController.claim != nil {
                windowCoordinator.restoreResearchAgentPermissionFocus()
                permissionController.finishDismissal()
            } else if researchActionController.isPresented {
                let actionID = researchActionController.activeActionID
                appState.presentationRouter.dismissSheet()
                researchActionController.dismiss()
                restoreResearchActionFocus(ifOwnedBy: actionID)
                permissionController.presentationBecameAvailable()
            } else {
                permissionController.presentationBecameAvailable()
            }
        }) { route in
            sheetContent(for: route)
        }
        .alert(item: presentedAlert) { alert in
            Alert(
                title: Text("Could Not Complete Action"),
                message: Text(alert.message),
                dismissButton: .default(Text("Dismiss")) {
                    appState.presentationRouter.alert = nil
                }
            )
        }
        .task(id: appState.currentResearchFunctionTarget) {
            await appState.refreshResearchActionAvailability()
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

    private func restoreResearchActionFocus(
        ifOwnedBy actionID: ResearchActionID?
    ) {
        let pendingActionID = pendingResearchActionFocusID
        pendingResearchActionFocusID = nil
        guard let actionID, pendingActionID == actionID else {
            return
        }
        researchActionFocusRequest = ResearchActionFocusRequest(actionID: actionID)
    }

    private var spotlightSearchContext: SpotlightSearchContext {
        SpotlightSearchContext(
            savedSearches: appState.searchController.savedSearches,
            refresh: { await appState.searchController.refresh() },
            dismiss: { appState.searchController.dismiss() },
            save: { appState.searchController.saveCurrent(named: $0) },
            run: { appState.searchController.run($0) },
            rename: { appState.searchController.rename($0, to: $1) },
            move: { appState.searchController.move($0, by: $1) },
            delete: { appState.searchController.delete($0) }
        )
    }

    private var researchInspectorContentContext: ResearchInspectorContentContext {
        ResearchInspectorContentContext(
            presentation: ResearchOverviewPresentation(
                researchUnit: appState.currentNote?.researchUnit
                    ?? ResearchUnitDeclaration(
                        frontmatter: [:],
                        profile: .genericMarkdown
                    ),
                visibleAttentionItems: visibleCurrentDocumentAttentionItems,
                freshness: researchProjectionFreshness,
                propertiesConfiguration: appState.currentDocumentPropertiesConfiguration,
                zoteroItemKey: currentAnalysisZoteroItemKey,
                noteReviewState: currentNoteReviewState
            ),
            attentionPopoverSession: appState.attentionPopoverSession,
            openProperties: {
                guard let path = appState.currentNote?.relativePath else { return }
                appState.editingNotePath = path
                appState.showFrontmatterEditor = true
            },
            openAttention: {
                guard let note = appState.currentNote,
                      let vaultID = appState.currentDocumentVaultID else { return }
                windowCoordinator.actions.showAttention(
                    .inspector,
                    VaultQualifiedNoteID(
                        vaultID: vaultID,
                        relativePath: note.relativePath
                    )
                )
            },
            openNoteReview: {
                guard let reviewState = currentNoteReviewState,
                      reviewState.status == .needsReview else { return }
                currentNoteDocumentSession?.presentNoteReviewTask(
                    for: reviewState
                )
            },
            retryRefresh: {
                Task { await appState.retryDerivedRefresh() }
            },
            openZoteroItem: { itemKey in
                await appState.zoteroBridge.openInZotero(zoteroKey: itemKey)
            }
        )
    }

    private var currentNoteStableID: UUID? {
        appState.currentNote?.workspaceSnapshot?.stableIdentity.resolvedID
    }

    private var currentNoteReviewState: WorkspaceNoteReviewState? {
        guard let noteID = currentNoteStableID else { return nil }
        return researchController.records?.noteReviewStates.first {
            $0.noteID == noteID
        }
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

    private var currentAnalysisZoteroItemKey: String? {
        guard appState.currentDocumentVaultRole == .sourceCorpus else { return nil }
        return ZoteroBridge.normalizedItemKey(
            appState.currentNote?.frontmatter["zotero_item_key"]?.scalarString
        )
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
            locationScope: appState.currentDocumentDescriptor == nil
                ? appState.noteLocationScope
                : .workspace,
            noteIdentityByPath: appState.currentDocumentIdentityByPath,
            documentRevisions: appState.currentDocumentRevisions,
            workspaceCatalog: appState.workspaceCatalog,
            propertiesConfiguration: appState.currentDocumentPropertiesConfiguration,
            activeDiscussions: appState.researchController.records?.activeDiscussions ?? [],
            requestedDiscussionID: appState.requestedDiscussionID,
            canComment: appState.canCommentCurrentNote,
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
            isResolvingIdentity: appState.isResolvingIdentity,
            noteReviewState: currentNoteReviewState,
            researchRecordSourceManifestHash: researchController.records?
                .finishedResearchRecordSourceManifestHash ?? "",
            researchRecordProjectionIsComplete: researchController.records?
                .finishedResearchRecordProjectionIsComplete ?? false
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
            createDiscussion: { anchor, message in
                guard let target = appState.currentResearchFunctionTarget else {
                    throw DiscussionPresentationError.unavailable
                }
                let discussion = try await appState.researchController.createDiscussion(
                    target: target,
                    passage: anchor,
                    researcherMessage: message
                )
                try await appState.researchController.refreshResearchProjection()
                appState.requestDiscussionPresentation(discussion.id)
                return discussion
            },
            createComment: { expectedNoteID, expectedPath, lineReference, message in
                guard let target = appState.currentResearchFunctionTarget,
                      target.noteID == expectedNoteID,
                      target.note.relativePath == expectedPath,
                      target.fingerprint == lineReference.fingerprint else {
                    throw DiscussionPresentationError.unavailable
                }
                let discussion = try await appState.researchController.createComment(
                    target: target,
                    lineReference: lineReference,
                    researcherMessage: message
                )
                do {
                    try await appState.researchController.refreshResearchProjection()
                } catch {
                    throw ScholiumApplicationError.operationCommittedButRefreshFailed(
                        operation: "The Comment",
                        reason: error.localizedDescription
                    )
                }
                return discussion
            },
            reloadDiscussion: { discussionID in
                try await appState.researchController.activeDiscussionIfPresent(
                    id: discussionID
                )
            },
            loadDiscussionAgentInstructions: { discussionID in
                try await appState.researchController.discussionAgentInstructions(
                    id: discussionID
                )
            },
            refreshDiscussionProjection: {
                try await appState.researchController.refreshResearchProjection()
            },
            appendDiscussionStatement: { discussionID, author, attribution, text in
                try await appState.researchController.appendDiscussionStatement(
                    discussionID: discussionID,
                    author: author,
                    attribution: attribution,
                    text: text
                )
            },
            finishDiscussion: { discussionID in
                try await appState.researchController.finishDiscussion(
                    discussionID: discussionID
                )
            },
            endDiscussion: { discussionID in
                try await appState.researchController.endDiscussion(id: discussionID)
            },
            clearRequestedDiscussion: {
                appState.clearRequestedDiscussionPresentation()
            },
            copyDiscussionRequest: { instructions in
                try appState.copyTextToClipboard(instructions)
            },
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
                appState.showFrontmatterEditor = true
            },
            openResearchAction: { actionID, selection in
                appState.openResearchAction(actionID, selection: selection)
            },
            setResearchInspectorVisible: {
                windowCoordinator.actions.setResearchInspectorVisible($0)
            },
            viewAgentChanges: {
                windowCoordinator.actions.showNoteResearchRecords()
            },
            reloadNoteReviewState: {
                try await appState.researchController.refreshResearchProjection()
            },
            markCurrentNoteReviewed: { noteID, revision, manifest in
                _ = try await appState.researchController.markCurrentNoteReviewed(
                    noteID: noteID,
                    expectedRevision: revision,
                    expectedRecordSourceManifestHash: manifest
                )
            },
            notify: { message, kind in
                switch kind {
                case .success: appState.showToast(message)
                case .information: appState.showToast(message, kind: .information)
                case .error: appState.showToast(message, kind: .error)
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
                    locationScope: appState.noteLocationScope
                )
            },
            selectedDocumentPath: selectedLibraryDocumentPath,
            libraryFocusRequestGeneration: appState.libraryFocusRequestGeneration,
            currentVaultRole: appState.currentVaultRole,
            currentWorkspaceSlot: currentWorkspaceSlot,
            canMutateLibrary: appState.noteLocationScope == .workspace
                && appState.currentRegisteredVault != nil
                && !appState.isCreatingNote
                && !appState.isMutatingFolder,
            lifecycleMutationGeneration: appState.lifecycleMutationGeneration,
            filterOptions: SidebarLibraryFilterOptions(
                catalogIsAvailable: appState.workspaceCatalog != nil,
                graphIsAvailable: appState.relationshipGraph != nil,
                tags: appState.allTags,
                authors: appState.availableAuthors,
                years: appState.availableYears,
                propertyKeys: propertyFilterOptions.keys,
                propertyValues: propertyFilterOptions.valuesByKey
            ),
            attentionPopoverSession: appState.attentionPopoverSession,
            openAttention: {
                windowCoordinator.actions.showAttention(.sidebar, nil)
            },
            retryAttention: {
                Task { await appState.refreshWorkspaceCatalog() }
            },
            selectLocationScope: { appState.requestNoteLocationScope($0) },
            openNote: { appState.requestOpenNote($0, disposition: $1) },
            selectTriptychWorkspace: { appState.requestTriptychWorkspace($0) },
            createUntitledNote: { appState.requestUntitledNoteCreation(in: $0) },
            createUntitledFolder: {
                appState.requestUntitledFolderCreation(in: $0)
            },
            moveNote: { target, destination in
                try await appState.moveNote(target, to: destination)
            },
            moveFolder: { target, destination in
                try await appState.moveFolder(target, to: destination)
            },
            requestFolderLifecycle: {
                appState.folderLifecycleRequest = $0
            },
            moveFolderToTrash: {
                try await appState.moveFolderToTrash($0)
            },
            copyRelativePath: { path in
                do {
                    try appState.copyTextToClipboard(path)
                    appState.showToast(
                        String(
                            localized: "Relative path copied.",
                            table: "Localizable",
                            bundle: .module
                        )
                    )
                } catch {
                    appState.showToast(error.localizedDescription, kind: .error)
                }
            },
            revealNote: { appState.showInFinder($0) },
            setAside: { try await appState.setAsideNote($0) },
            moveToTrash: { try await appState.moveNoteToTrash($0) },
            putBack: { try await appState.putBackNote($0) },
            deletePermanently: { try await appState.deleteNotePermanently($0) },
            revealCurrentVault: { appState.revealVaultInFinder() },
            openSettings: { openSettings() },
            selectSortOrder: { appState.noteSortOrder = $0 },
            showError: { appState.showToast($0, kind: .error) }
        )
    }

    private var sidebarAttentionTotal: Int? {
        AttentionPreferences.visibleTotalCount(
            catalog: appState.workspaceCatalog,
            assignment: appState.workspaceAssignment,
            dismissalLedgerData: attentionDismissalLedgerData
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
                  let snapshot = snapshots[vaultID] else {
                continue
            }
            values[slot] = snapshot.documents.count {
                $0.lifecycle == .active && !$0.capabilities.isManagedCritique
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
        case .frontmatter(let route):
            if let note = note(at: route.path) {
                FrontmatterEditorView(
                    note: note,
                    configuredEditableFields: appState.currentDocumentPropertiesConfiguration.map {
                        Set($0.editableFields)
                    },
                    expectedRevision: appState.currentDocumentRevisions[note.relativePath],
                    onClose: {
                        finishFrontmatter(route)
                    }
                ) { proposedFrontmatter, researchUnitEdit, revision in
                    _ = try await appState.saveProperties(
                        for: note,
                        proposedFrontmatter: proposedFrontmatter,
                        expectedRevision: revision,
                        researchUnitEdit: researchUnitEdit
                    )
                }
                    .frame(minWidth: 520, minHeight: 560)
            }
        case .researchAction(let route):
            if note(at: route.target.relativePath) != nil {
                ResearchActionPanelView(
                    controller: researchActionController,
                    context: ResearchActionPanelContext(
                        chooseLocalSource: {
                            try await fileSelectionPresenter
                                .requiredForFileSelection()
                                .selectURL(ScholiumFileSelectionRequest(
                                    title: String(
                                        localized: "Choose Source",
                                        table: "Localizable",
                                        bundle: .module
                                    ),
                                    prompt: String(
                                        localized: "Choose",
                                        table: "Localizable",
                                        bundle: .module
                                    ),
                                    kind: .files(
                                        allowedContentTypes: [.item],
                                        resolvesAliases: false
                                    )
                                ))
                        },
                        copyInstructions: { instructions in
                            try appState.copyTextToClipboard(instructions)
                        },
                        didCopyHandoff: { runID in
                            windowCoordinator.recordSuccessfulResearchHandoff(
                                runID: runID
                            )
                        },
                        retryRefresh: {
                            Task { await appState.retryDerivedRefresh() }
                        },
                        openRecovery: {
                            appState.presentationRouter.dismissSheet()
                            Task { @MainActor in
                                await Task.yield()
                                appState.showTransactionRecovery = true
                            }
                        },
                        dismiss: { appState.presentationRouter.dismissSheet() }
                    )
                )
                .onDisappear {
                    if let currentSheet = appState.presentationRouter.sheet {
                        if case .researchAction(let currentRoute) = currentSheet,
                           currentRoute.presentationID == route.presentationID {
                            // Native dismissal is still in flight. The root
                            // `onDismiss` finalizes the draft and restores
                            // focus only after AppKit has closed the sheet.
                            return
                        }
                        researchActionController.dismiss(
                            presentationID: route.presentationID
                        )
                    }
                }
            }
        case .researchAgentPermission(let requestID):
            let controller = appState.researchAgentPermissionWindowController
            if let claim = controller.claim,
               claim.id == requestID {
                ResearchAgentPermissionView(
                    claim: claim,
                    hasLocallyExpired: controller.hasLocallyExpired,
                    isResolving: controller.isResolving,
                    resolveWriteSet: { state, allowedHandles in
                        controller.resolveWriteSet(
                            state: state,
                            allowedHandles: allowedHandles
                        )
                    },
                    resolveContinuation: { allow in
                        controller.resolveContinuation(allow: allow)
                    },
                    dismiss: {
                        controller.requestDismissal(id: requestID)
                    }
                )
            }
        case .createCheckpoint:
            CreateCheckpointView { name in
                _ = try await appState.createCheckpoint(name: name, kind: .manual)
                appState.showToast(String(localized: "Checkpoint created.", table: "Localizable", bundle: .module))
            }
        case .restoreCheckpoint:
            RestoreCheckpointView(
                controller: appState.researchController,
                restoreCheckpoint: { checkpointID, selection in
                    let result = try await appState.restoreCheckpoint(
                        checkpointID,
                        selection: selection
                    )
                    if result.cleanupWarnings.isEmpty {
                        appState.showToast(String(localized: "Checkpoint restored. Before Restore checkpoint created.", table: "Localizable", bundle: .module))
                    }
                },
                revealCheckpoints: {
                    appState.revealCheckpointsInFinder()
                }
            )
        case .lifecycle(let request):
            NoteLifecycleView(
                request: request,
                actions: NoteLifecycleActions(
                    duplicate: { source, destination in
                        _ = try await appState.duplicateNote(source, to: destination)
                    },
                    move: { source, destination in
                        try await appState.moveNote(source, to: destination)
                    }
                )
            )
        case .folderLifecycle(let request):
            FolderLifecycleView(
                request: request,
                folderRelativePaths: appState.currentLibraryFolders,
                actions: FolderLifecycleActions(
                    move: { target, destination in
                        try await appState.moveFolder(target, to: destination)
                    }
                )
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
        }
    }

    private func note(at path: String) -> WindowDocumentLocation? {
        if appState.currentNote?.relativePath == path {
            return appState.currentNote
        }
        return appState.notes.first(where: { $0.relativePath == path })
    }

    private func finishFrontmatter(_ route: FrontmatterPanelRoute) {
        appState.presentationRouter.finishFrontmatter(route)
    }

    @ViewBuilder
    private var detailRegion: some View {
        VStack(spacing: 0) {
            researchNotificationBanner
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
    private var researchNotificationBanner: some View {
        if let destination = shellState.researchResultNotice {
            ResearchResultNotificationView(
                kind: .result,
                review: {
                    windowCoordinator.reviewResearchResult(destination)
                },
                dismiss: {
                    shellState.dismissResearchResultNotice(matching: destination)
                }
            )
            .padding(ScholiumMetrics.Workspace.refreshStatusOuterInset)
        } else if let permission = shellState.researchNotificationPermissionNotice {
            ResearchResultNotificationView(
                kind: permission == .enable
                    ? .enableNotifications
                    : .openNotificationSettings,
                review: {
                    switch permission {
                    case .enable:
                        windowCoordinator.requestResearchNotificationAuthorization()
                    case .openSettings:
                        windowCoordinator.openResearchNotificationSettings()
                    }
                },
                dismiss: {
                    shellState.dismissResearchNotificationPermissionNotice()
                }
            )
            .padding(ScholiumMetrics.Workspace.refreshStatusOuterInset)
        }
    }

    @ViewBuilder
    private var apparatusRegion: some View {
        if let note = appState.currentNote {
            ResearchInspectorView(
                note: note,
                shellState: appState.shellState,
                graph: appState.relationshipGraph,
                catalog: appState.workspaceCatalog,
                currentVaultID: appState.currentDocumentVaultID,
                researchInspectorContentContext: researchInspectorContentContext,
                researchActionsPresentation: appState.researchActionsPresentation(),
                researchActionFocusRequest: researchActionFocusRequest,
                registerResearchActionFocusOwner: {
                    pendingResearchActionFocusID = $0
                },
                openResearchAction: { item in
                    if let activity = item.activity {
                        appState.openResearchActionStatus(
                            activity.primary
                        )
                    } else {
                        appState.openResearchAction(item.id)
                    }
                },
                endResearchActivity: { runID in
                    researchActionController.endActivity(runID: runID)
                },
                retryResearchActionCancellation: { runID in
                    researchActionController.retryCancellationRecovery(runID: runID)
                },
                openReference: { reference, sourceLine in
                    appState.researchController.requestOpen(
                        reference,
                        sourceLine: sourceLine
                    )
                },
                settle: { rationale in
                    guard let target = appState.currentResearchFunctionTarget else { return }
                    _ = try await appState.researchController.settle(
                        target.note,
                        expectedRevision: target.fingerprint,
                        rationale: rationale
                    )
                }
            )
        } else {
            VStack(spacing: 0) {
                if researchActionController.hasCancellationBarrier {
                    ResearchActionsInspectorView(
                        presentation: appState.researchActionsPresentation(),
                        freshness: .current,
                        focusRequest: nil,
                        registerFocusOwner: { _ in },
                        select: { _ in },
                        endActivity: { _ in },
                        retryRefresh: {},
                        retryCancellationRecovery: { runID in
                            researchActionController
                                .retryCancellationRecovery(runID: runID)
                        },
                        settle: { _ in }
                    )
                    .accessibilityIdentifier("scholium.researchActions.recoveryOnly")
                } else {
                    Color.clear
                        .accessibilityHidden(true)
                }
            }
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

// MARK: - Toast View

struct ToastView: View {
    let message: String
    let symbol: String
    let colorRole: ScholiumColorRole

    init(toast: WindowToast) {
        message = toast.message
        symbol = toast.kind.symbol
        colorRole = toast.kind.colorRole
    }

    init(message: String) {
        self.message = message
        symbol = "checkmark.circle"
        colorRole = .confirmed
    }

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: symbol)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(colorRole)
            Text(message)
                .font(ScholiumTypography.interface(.rowTitle))
        }
        .padding(.horizontal, ScholiumMetrics.Workspace.toastHorizontalInset)
        .padding(.vertical, ScholiumMetrics.Workspace.toastVerticalInset)
        .scholiumEditorialSurface(
            .floatingControl,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ResearchResultNotificationView: View {
    enum Kind {
        case result
        case enableNotifications
        case openNotificationSettings
    }

    let kind: Kind
    let review: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(
            alignment: .center,
            spacing: ScholiumGrid.Spacing.inlineControlGap
        ) {
            Image(systemName: symbol)
                .font(ScholiumTypography.interface(.body, emphasis: .strong))
                .scholiumForeground(.secondaryText)
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.labelAccessoryGap
            ) {
                Text(title)
                    .font(ScholiumTypography.interface(.rowTitle))
                Text(detail)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actionButton
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .accessibilityLabel("Dismiss")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(.horizontal, ScholiumMetrics.Workspace.toastHorizontalInset)
        .padding(.vertical, ScholiumMetrics.Workspace.toastVerticalInset)
        .frame(maxWidth: 520, alignment: .leading)
        .scholiumEditorialSurface(
            .floatingControl,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var symbol: String {
        switch kind {
        case .result: "doc.text.magnifyingglass"
        case .enableNotifications, .openNotificationSettings: "bell"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if kind == .result {
            Button(actionTitle, action: review)
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        } else {
            Button(actionTitle, action: review)
                .controlSize(.small)
                .buttonStyle(.bordered)
        }
    }

    private var title: LocalizedStringResource {
        switch kind {
        case .result: "Agent Result Arrived"
        case .enableNotifications: "Get Notified When Results Are Ready"
        case .openNotificationSettings: "Notifications Are Off"
        }
    }

    private var detail: LocalizedStringResource {
        switch kind {
        case .result:
            "Review the completed Research Record when you are ready."
        case .enableNotifications:
            "Scholium can notify you when the app is in the background."
        case .openNotificationSettings:
            "Turn on Scholium notifications in System Settings if you want background alerts."
        }
    }

    private var actionTitle: LocalizedStringResource {
        switch kind {
        case .result: "Review Result"
        case .enableNotifications: "Enable Notifications"
        case .openNotificationSettings: "Open Settings"
        }
    }

    private var identifier: String {
        switch kind {
        case .result: "scholium.researchResultNotification"
        case .enableNotifications, .openNotificationSettings:
            "scholium.researchNotificationPermission"
        }
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
