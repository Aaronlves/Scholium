import AppKit
import ScholiumContracts
import SwiftUI

enum ScholiumLibraryVisibilityPolicy {
    static func automaticVisibility(
        windowWidth: CGFloat,
        hasOpenDocument: Bool,
        isInitial: Bool,
        previousLayoutMode: LayoutMode
    ) -> Bool? {
        if LayoutMode(windowWidth: windowWidth) == .compact {
            if !hasOpenDocument { return true }
            if isInitial || previousLayoutMode != .compact { return false }
        } else if previousLayoutMode == .compact {
            return true
        }
        return nil
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: WindowModel
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        GeometryReader { geometry in
            Group {
                if !appState.hasCompletedInitialRestore {
                    ScholiumLaunchPlaceholderView()
                } else if appState.vaultConfig == nil {
                    WorkspaceSetupView(context: workspaceSetupContext)
                } else {
                    NavigationSplitView(columnVisibility: sidebarVisibility) {
                        LibrarySurface(isElevatedOverDocument: appState.currentNote != nil) {
                            SidebarView(
                                controller: appState.discoveryController,
                                context: sidebarContext
                            )
                        }
                            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .navigationSplitViewColumnWidth(
                                min: 300,
                                ideal: ScholiumMetrics.Triptych.preferredWidth,
                                max: ScholiumMetrics.Triptych.preferredWidth
                            )
                    } detail: {
                        detailRegion
                    }
                    .navigationSplitViewStyle(.prominentDetail)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            TriptychActionsMenu(
                                revealCurrentVault: { appState.revealVaultInFinder() },
                                manageTriptychs: { openSettings() }
                            )
                        }
                    }
                    .navigationTitle(windowTitle)
                }
            }
            .onAppear { updateAdaptiveLayout(for: geometry.size.width, isInitial: true) }
            .onChange(of: geometry.size.width) { _, width in
                updateAdaptiveLayout(for: width)
            }
            .onChange(of: appState.selectedDocumentPath) { _, _ in
                updateLibraryVisibilityForDocumentChange(at: geometry.size.width)
            }
        }
        .animation(
            ScholiumMotion.documentReveal(reduceMotion: reduceMotion),
            value: appState.currentNote != nil
        )
        .overlay(alignment: .bottom) {
            if let toast = appState.toastMessage {
                ToastView(toast: toast)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .padding(.bottom, 20)
            }
        }
        .animation(
            ScholiumMotion.transientStatus(reduceMotion: reduceMotion),
            value: appState.toastMessage
        )
        .overlay(alignment: .topTrailing) {
            if let status = appState.refreshStatusText {
                HStack(spacing: 7) {
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
                        .font(.caption.weight(.semibold))
                    }
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .scholiumEditorialSurface(
                    .floatingControl,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                        style: .continuous
                    )
                )
                .padding(10)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("scholium.refreshStatus")
            }
        }
        .overlay {
            if appState.isLoading {
                LoadingOverlay()
                    .transition(.opacity.combined(with: .scale(0.98)))
            }
        }
        .overlay {
            if appState.showSearchSurface {
                SpotlightSearchOverlay(
                    controller: appState.discoveryController,
                    context: spotlightSearchContext
                )
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .zIndex(20)
            }
        }
        .animation(
            ScholiumMotion.searchPresentation(reduceMotion: reduceMotion),
            value: appState.showSearchSurface
        )
        .sheet(item: presentedSheet, onDismiss: {
            if appState.presentationRouter.sheet == nil,
               appState.researchController.functions.isPresented {
                appState.researchController.functions.dismiss()
            }
            appState.finishJudgmentPanelDismissal()
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
            await appState.refreshResearchFunctionAvailability()
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.sidebarVisible ? .all : .detailOnly },
            set: { visibility in
                appState.sidebarVisible = visibility != .detailOnly
            }
        )
    }

    private var showsTrailingContext: Bool {
        ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_DISABLE_INSPECTOR"] != "1"
            && (appState.backlinksVisible || appState.noteHistoryVisible)
            && appState.usesWideWindowLayout
            && appState.currentNote != nil
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
            savedSearches: appState.savedSearches,
            refresh: { await appState.refreshAdvancedSearch() },
            dismiss: { appState.dismissSearch() },
            save: { appState.saveCurrentSearch(named: $0) },
            run: { appState.runSavedSearch($0) },
            rename: { appState.renameSavedSearch($0, to: $1) },
            move: { appState.moveSavedSearch($0, by: $1) },
            delete: { appState.deleteSavedSearch($0) }
        )
    }

    private var attentionQueueContext: AttentionQueueContext {
        AttentionQueueContext(
            items: appState.workspaceCatalog?.attention ?? [],
            errorMessage: appState.workspaceCatalogError,
            isRefreshing: appState.isRefreshingWorkspaceCatalog,
            dismissalDays: appState.triptychSettings.attentionDismissalDays,
            refresh: { await appState.refreshWorkspaceCatalog() }
        )
    }

    private var relationshipViewContext: RelationshipViewContext {
        RelationshipViewContext(
            currentVault: appState.currentDocumentVault,
            analysesVaultID: appState.workspaceAssignment?.workspace.paperAnalysisVaultID,
            catalog: appState.workspaceCatalog,
            attentionDismissalDays: appState.triptychSettings.attentionDismissalDays,
            resolveZoteroSource: { source in
                try await appState.zoteroBridge.resolve(source: source)
            },
            openZoteroItem: { itemKey in
                await appState.zoteroBridge.openInZotero(zoteroKey: itemKey)
            },
            confirmZoteroItem: { itemKey, reference in
                try await appState.confirmZoteroItemKey(itemKey, for: reference)
            },
            didConfirmZoteroSource: { title in
                appState.showToast("Zotero source confirmed for \(title).")
            },
            copyResearchText: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                appState.showToast("Research instructions copied.")
            },
            repairBibliographyMethod: {
                UserDefaults.standard.set(
                    WorkspaceSettingsPane.researchGuidance.rawValue,
                    forKey: "scholium.settings.selectedPane"
                )
                UserDefaults.standard.set(
                    "skills",
                    forKey: "scholium.settings.researchGuidanceCollection"
                )
                openSettings()
            }
        )
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
            ordinarySearchScope: appState.ordinarySearchScope,
            currentVaultID: appState.currentDocumentVaultID,
            vaultRole: appState.currentDocumentVaultRole,
            locationScope: appState.currentDocumentDescriptor == nil
                ? appState.noteLocationScope
                : .workspace,
            noteIdentityByPath: appState.currentDocumentIdentityByPath,
            documentRevisions: appState.currentDocumentRevisions,
            workspaceCatalog: appState.workspaceCatalog,
            propertiesConfiguration: appState.currentDocumentPropertiesConfiguration,
            reviewRecord: appState.currentDocumentReviewRecord,
            reviewDisplayState: appState.currentDocumentReviewDisplayState,
            changedSinceReview: appState.currentDocumentChangedSinceReview,
            canComment: appState.canCommentCurrentNote,
            canEdit: appState.canEditCurrentNote,
            documentTextScale: appState.documentTextScale,
            readCSS: appState.cssSnippetStore.readCSS,
            livePreviewCSS: appState.cssSnippetStore.livePreviewCSS,
            initialScrollFraction: path.map { appState.scrollPosition(for: $0) } ?? 0,
            requestedPresentationMode: appState.requestPresentationMode,
            pendingSourceLine: appState.pendingSourceLine,
            isCompactLayout: appState.layoutMode == .compact,
            noteHistoryVisible: appState.noteHistoryVisible,
            researchInspectorVisible: appState.backlinksVisible,
            identityAmbiguity: appState.currentDocumentIdentityAmbiguity,
            pendingIdentityRebinding: appState.currentDocumentPendingIdentityRebinding,
            identityMigrationFailureMessage: appState.currentDocumentIdentityMigrationFailure?.message,
            isResolvingIdentity: appState.isResolvingIdentity,
            researchStrip: appState.researchStripPresentation
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
            beginSearch: { appState.beginSearch($0) },
            clearRequestedPresentationMode: { appState.requestPresentationMode = nil },
            registerEditorFlush: { path, token, flush, captureForReconstruction in
                appState.registerEditorFlush(
                    for: path,
                    token: token,
                    flush: flush,
                    captureForReconstruction: captureForReconstruction
                )
            },
            unregisterEditorFlush: { appState.unregisterEditorFlush(token: $0) },
            clearPendingSourceLine: { appState.pendingSourceLine = nil },
            requestComments: { selection, commentID in
                guard let path = documentPath else { return }
                appState.requestResearcherComments(
                    at: path,
                    selection: selection,
                    focusedCommentID: commentID
                )
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
                guard let path = documentPath else { return }
                appState.rememberPresentationMode($0, for: path)
            },
            setPendingSourceLine: { appState.pendingSourceLine = $0 },
            editProperties: {
                guard let path = documentPath else { return }
                appState.editingNotePath = path
                appState.showFrontmatterEditor = true
            },
            openResearchFunction: { function, selection in
                appState.openResearchFunction(function, selection: selection)
            },
            setNoteHistoryVisible: {
                appState.setNoteHistoryVisible($0, animated: false)
            },
            setResearchInspectorVisible: {
                appState.setResearchInspectorVisible($0, animated: false)
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

    private var noteHistoryContext: NoteHistoryContext {
        NoteHistoryContext(
            controller: appState.researchController,
            vaultRole: appState.currentDocumentVaultRole,
            documentRevisions: appState.currentDocumentRevisions,
            currentReview: { _ in appState.currentDocumentReviewRecord },
            loadDialogue: { await appState.dialogueHistory(for: $0) },
            loadCritique: { await appState.critiqueAssociationRelated(to: $0) },
            loadCheckpoints: { try await appState.noteCheckpoints(for: $0) },
            checkpointContent: { try await appState.noteCheckpointContent($0, path: $1) },
            createCheckpoint: {
                _ = try await appState.createCheckpoint(name: $0, kind: .manual)
            },
            restoreNote: { try await appState.restoreNote($0, from: $1) },
            revealCheckpoints: { appState.revealCheckpointsInFinder() },
            copyText: { try appState.copyTextToClipboard($0) },
            openNote: { appState.requestOpenNote($0) },
            closeTrailing: {
                appState.setNoteHistoryVisible(false, animated: false)
            },
            notify: { appState.showToast($0) }
        )
    }

    private var sidebarContext: SidebarContext {
        let propertyFilterOptions = appState.availablePropertyFilterOptions
        let selectedLibraryDocumentPath = appState.currentDocumentVaultID
            == appState.currentRegisteredVault?.id
            ? appState.selectedDocumentPath
            : nil
        return SidebarContext(
            triptychName: appState.workspaceAssignment?.triptych.name ?? "Not Selected",
            attentionItems: appState.workspaceCatalog?.attention,
            filteredNotes: appState.filteredNotes,
            allNotes: appState.notes,
            currentVaultID: appState.currentRegisteredVault?.id,
            selectedDocumentPath: selectedLibraryDocumentPath,
            libraryFocusRequestGeneration: appState.libraryFocusRequestGeneration,
            currentVaultRole: appState.currentVaultRole,
            currentWorkspaceSlot: currentWorkspaceSlot,
            noteLifecycleRequest: appState.noteLifecycleRequest,
            lifecycleMutationGeneration: appState.lifecycleMutationGeneration,
            catalogIsAvailable: appState.workspaceCatalog != nil,
            graphIsAvailable: appState.relationshipGraph != nil,
            hasUnqualifiedReview: appState.humanReviewRecords.values.contains {
                $0.latestReview?.qualification == .unqualified
            },
            changedSinceReviewCount: appState.changedSinceReviewPaths.count,
            tags: appState.allTags,
            statuses: appState.availableStatuses,
            authors: appState.availableAuthors,
            years: appState.availableYears,
            propertyKeys: propertyFilterOptions.keys,
            propertyValues: propertyFilterOptions.valuesByKey,
            resolvedIdentityPaths: Set(appState.noteIdentityByPath.keys),
            reviewDisplayState: { appState.reviewDisplayState(for: $0) },
            notesAreOrdered: { appState.notesAreOrdered($0, $1) },
            presentAttention: { appState.showAttentionQueues = true },
            selectLocationScope: { appState.requestNoteLocationScope($0) },
            openNote: { appState.requestOpenNote($0, disposition: $1) },
            openLifecycleNote: { appState.requestLifecycleNote($0, in: $1) },
            selectWorkspaceVault: { appState.requestWorkspaceVault($0) },
            lifecycleItems: { try await appState.lifecycleLocationItems(for: $0) },
            prepareLifecycle: { appState.prepareLifecycleOperation($0) },
            clearPreparedLifecycle: { appState.clearPreparedLifecycleOperation(at: $0) },
            revealNote: { appState.showInFinder($0) },
            setAside: { try await appState.setAsideNote($0) },
            moveToTrash: { try await appState.moveNoteToTrash($0) },
            deletePermanently: { try await appState.deleteNotePermanently($0) },
            classify: { path, slot, destination in
                try await appState.classifyUnclassified(
                    path,
                    into: slot,
                    destination: destination
                )
            },
            selectSortOrder: { appState.noteSortOrder = $0 },
            showError: { appState.showToast($0, kind: .error) }
        )
    }

    private var currentWorkspaceSlot: WorkspaceVaultSlot? {
        appState.currentWorkspaceSlot
    }

    private var workspaceSetupContext: WorkspaceSetupContext {
        WorkspaceSetupContext(
            isCreatingNewTriptych: appState.isCreatingNewTriptych,
            targetTriptychID: appState.workspaceAssignment?.id,
            workspaceAssignment: appState.workspaceAssignment,
            registeredTriptychs: appState.registeredTriptychs,
            recoveryMessage: appState.workspaceRecoveryMessage,
            isInitialConfiguration: appState.vaultConfig == nil,
            refreshAssignment: { await appState.refreshWorkspaceAssignment() },
            portableContainerURL: { await appState.portableContainerURL(for: $0) },
            configure: { selection in
                try await appState.configureThreeVaultWorkspace(
                    paperAnalysisURL: selection.paperAnalysisURL,
                    topicKnowledgeURL: selection.topicKnowledgeURL,
                    outputURL: selection.outputURL,
                    portableContainerURL: selection.portableContainerURL,
                    triptychID: selection.triptychID,
                    triptychName: selection.triptychName
                )
                appState.workspaceRecoveryMessage = nil
            },
            dismiss: { appState.showWorkspaceSetup = false }
        )
    }

    @ViewBuilder
    private func sheetContent(for route: WindowSheetRoute) -> some View {
        switch route {
        case .adaptiveContext:
            if let note = appState.currentNote {
                if appState.noteHistoryVisible {
                    NoteHistorySheet(
                        note: note,
                        presentation: .sheet,
                        context: noteHistoryContext
                    )
                        .onDisappear {
                            appState.setNoteHistoryVisible(false, animated: false)
                        }
                } else {
                    AdaptiveResearchInspectorSheet(
                        note: note,
                        controller: appState.researchController,
                        graph: appState.workspaceCatalog?.graph ?? appState.relationshipGraph,
                        catalog: appState.workspaceCatalog,
                        currentVaultID: appState.currentDocumentVaultID,
                        relationshipViewContext: relationshipViewContext
                    ) {
                        appState.setResearchInspectorVisible(false, animated: false)
                    }
                    .environmentObject(appState)
                    .onDisappear {
                        appState.setResearchInspectorVisible(false, animated: false)
                    }
                }
            }
        case .workspaceSetup:
            WorkspaceSetupView(context: workspaceSetupContext)
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
                    appState.showToast("Frontmatter saved")
                }
                    .frame(minWidth: 520, minHeight: 560)
            }
        case .researchFunction(let route):
            if let note = note(at: route.target.relativePath) {
                ResearchFunctionPanelView(
                    controller: appState.researchController.functions,
                    context: ResearchFunctionPanelContext(
                        comments: appState.currentDocumentReviewRecord?.comments ?? [],
                        repairCitationMethod: {
                            UserDefaults.standard.set(
                                WorkspaceSettingsPane.researchGuidance.rawValue,
                                forKey: "scholium.settings.selectedPane"
                            )
                            UserDefaults.standard.set(
                                "skills",
                                forKey: "scholium.settings.researchGuidanceCollection"
                            )
                            openSettings()
                        },
                        repairDialogueResponseDefaults: {
                            UserDefaults.standard.set(
                                WorkspaceSettingsPane.researchGuidance.rawValue,
                                forKey: "scholium.settings.selectedPane"
                            )
                            UserDefaults.standard.set(
                                "prompt-templates",
                                forKey: "scholium.settings.researchGuidanceCollection"
                            )
                            UserDefaults.standard.set(
                                "dialogue-response",
                                forKey: "scholium.settings.researchGuidancePromptSection"
                            )
                            openSettings()
                        },
                        copyInstructions: { instructions in
                            do {
                                try appState.copyTextToClipboard(instructions)
                                appState.showToast("Function instructions copied.")
                            } catch {
                                appState.showToast(
                                    error.localizedDescription,
                                    kind: .error
                                )
                            }
                        },
                        dismiss: {
                            appState.presentationRouter.dismissSheet()
                        },
                        note: note,
                        commentsContext: researcherCommentsContext(for: note),
                        focusCommentComposer: route.focusCommentComposer
                    )
                ) {
                    QualityReviewView(
                        note: note,
                        context: qualityReviewContext(for: note, route: route),
                        showsHeader: false
                    )
                }
                .onDisappear {
                    // Normal sheet dismissal is finalized by the root
                    // `onDismiss`, after AppKit has yielded keyboard focus.
                    // A direct route replacement still invalidates this draft
                    // immediately so it cannot leak into the next sheet.
                    if appState.presentationRouter.sheet != nil,
                       !appState.presentationRouter.suspendsResearchFunction(
                           presentationID: route.presentationID
                       ) {
                        appState.researchController.functions.dismiss(
                            presentationID: route.presentationID
                        )
                    }
                }
            }
        case .attention:
            AttentionQueueView(
                controller: appState.discoveryController,
                context: attentionQueueContext
            )
        case .createCheckpoint:
            CreateCheckpointView { name in
                _ = try await appState.createCheckpoint(name: name, kind: .manual)
                appState.showToast("Checkpoint created.")
            }
        case .restoreCheckpoint:
            RestoreCheckpointView(
                controller: appState.researchController,
                restoreCheckpoint: { checkpointID, selection in
                    _ = try await appState.restoreCheckpoint(
                        checkpointID,
                        selection: selection
                    )
                    appState.showToast("Checkpoint restored. Before Restore checkpoint created.")
                },
                revealCheckpoints: {
                    appState.revealCheckpointsInFinder()
                }
            )
        case .lifecycle(let request):
            NoteLifecycleView(
                request: request,
                vaultRole: appState.currentVaultRole,
                actions: NoteLifecycleActions(
                    putBackDestination: {
                        appState.documentController.putBackDestination(for: $0)
                    },
                    create: { path, title, researchStatus in
                        _ = try await appState.createNote(
                            relativePath: path,
                            title: title,
                            analysisResearchStatus: researchStatus
                        )
                    },
                    duplicate: { source, destination in
                        _ = try await appState.duplicateNote(source, to: destination)
                    },
                    move: { source, destination in
                        try await appState.moveNote(source, to: destination)
                    },
                    putBack: { try await appState.putBackNote($0) },
                    classify: { source, slot, destination in
                        try await appState.classifyUnclassified(
                            source,
                            into: slot,
                            destination: destination
                        )
                    }
                )
            )
        case .transactionRecovery:
            TransactionRecoveryView(
                records: appState.transactionRecoveryRecords,
                error: appState.transactionRecoveryError,
                vaultNames: Dictionary(
                    uniqueKeysWithValues: appState.registeredVaults.map { ($0.id, $0.name) }
                ),
                refresh: { await appState.refreshTransactionRecoveryRecords() },
                markResolved: { try await appState.markTransactionRecoveryResolved($0) },
                revealRecords: { appState.revealTransactionRecoveryRecordsInFinder() }
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

    private func qualityReviewContext(
        for note: WindowDocumentLocation,
        route: ResearchFunctionPanelRoute
    ) -> QualityReviewContext {
        let functions = appState.researchController.functions
        return QualityReviewContext(
            revision: functions.humanReviewRevision,
            record: appState.currentDocumentReviewRecord,
            qualification: Binding(
                get: { functions.humanReviewQualification },
                set: { functions.humanReviewQualification = $0 }
            ),
            reviewNote: Binding(
                get: { functions.humanReviewNote },
                set: { functions.humanReviewNote = $0 }
            ),
            researchStatusDeclared: appState.currentDocumentVaultRole != .sourceCorpus
                || note.researchUnit.isDeclared,
            declareResearchStatus: {
                appState.presentationRouter.presentFrontmatter(
                    path: note.relativePath,
                    returningTo: route
                )
            },
            saveDraft: { revision, qualification, reviewNote in
                try await appState.saveHumanReviewDraft(
                    for: note.relativePath,
                    fingerprint: revision,
                    qualification: qualification,
                    reviewNote: reviewNote
                )
            },
            completeReview: { revision, qualification, reviewNote in
                try await appState.completeHumanReview(
                    for: note.relativePath,
                    fingerprint: revision,
                    qualification: qualification,
                    reviewNote: reviewNote
                )
            }
        )
    }

    private func finishFrontmatter(_ route: FrontmatterPanelRoute) {
        if let continuation = route.returnToResearchFunction {
            guard let target = appState.currentResearchFunctionTarget else {
                appState.researchController.functions.dismiss(
                    presentationID: continuation.presentationID
                )
                appState.presentationRouter.dismissSheet()
                return
            }
            appState.researchController.functions.resumeHumanReviewDraft(
                presentationID: continuation.presentationID,
                target: target
            )
        }
        appState.presentationRouter.finishFrontmatter(route)
    }

    private func researcherCommentsContext(for note: WindowDocumentLocation) -> ResearcherCommentsContext {
        ResearcherCommentsContext(
            initialComments: appState.currentDocumentReviewRecord?.comments ?? [],
            pendingSelection: appState.pendingCommentSelection,
            focusedCommentID: appState.focusedResearcherCommentID,
            clearPendingSelection: {
                appState.pendingCommentSelection = nil
            },
            add: { text, anchor in
                let record = try await appState.addResearcherComment(
                    to: note.relativePath,
                    text: text,
                    anchor: anchor
                )
                return record.comments
            },
            update: { commentID, text in
                try await appState.updateResearcherComment(
                    at: note.relativePath,
                    commentID: commentID,
                    text: text
                )
                return appState.currentDocumentReviewRecord?.comments ?? []
            },
            setResolved: { commentID, resolved in
                try await appState.setResearcherCommentResolved(
                    at: note.relativePath,
                    commentID: commentID,
                    resolved: resolved
                )
                return appState.currentDocumentReviewRecord?.comments ?? []
            },
            delete: { commentID in
                try await appState.deleteResearcherComment(
                    at: note.relativePath,
                    commentID: commentID
                )
                return appState.currentDocumentReviewRecord?.comments ?? []
            },
            reattach: { commentID, anchor in
                try await appState.reattachResearcherComment(
                    at: note.relativePath,
                    commentID: commentID,
                    anchor: anchor
                )
                return appState.currentDocumentReviewRecord?.comments ?? []
            },
            tryAutomaticReattachment: {
                let record = try await appState.tryReattachingResearcherComments(
                    at: note.relativePath
                )
                return record.comments
            }
        )
    }

    private func updateAdaptiveLayout(for width: CGFloat, isInitial: Bool = false) {
        guard abs(appState.windowWidth - width) > 0.5 else { return }
        let previousLayoutMode = appState.layoutMode
        // GeometryReader is evaluated during layout. Defer observable state
        // changes until that pass completes to avoid recursive AppKit
        // constraint invalidation on beta macOS.
        DispatchQueue.main.async {
            guard abs(appState.windowWidth - width) > 0.5 else { return }
            appState.windowWidth = width
            if width < 1200, appState.backlinksVisible {
                appState.setResearchInspectorVisible(false, animated: false)
            }
            if width < 1200, appState.noteHistoryVisible {
                appState.setNoteHistoryVisible(false, animated: false)
            }
            if let visibility = ScholiumLibraryVisibilityPolicy.automaticVisibility(
                windowWidth: width,
                hasOpenDocument: appState.currentNote != nil,
                isInitial: isInitial,
                previousLayoutMode: previousLayoutMode
            ) {
                appState.sidebarVisible = visibility
            }
        }
    }

    private func updateLibraryVisibilityForDocumentChange(at width: CGFloat) {
        let hasOpenDocument = appState.currentNote != nil
        DispatchQueue.main.async {
            guard let visibility = ScholiumLibraryVisibilityPolicy.automaticVisibility(
                windowWidth: width,
                hasOpenDocument: hasOpenDocument,
                isInitial: true,
                previousLayoutMode: appState.layoutMode
            ) else { return }
            appState.sidebarVisible = visibility
        }
    }

    @ViewBuilder
    private var detailRegion: some View {
        VStack(spacing: 0) {
            if !appState.transactionRecoveryRecords.isEmpty || appState.transactionRecoveryError != nil {
                TransactionRecoveryNotice(
                    count: appState.transactionRecoveryRecords.count,
                    error: appState.transactionRecoveryError
                ) {
                    appState.showTransactionRecovery = true
                }
            }
            if showsTrailingContext, let note = appState.currentNote {
                // SwiftUI's `.inspector` host can recursively invalidate
                // NSWindow constraints on beta macOS when the selected note adds a
                // WebKit-backed document. HSplitView preserves the native trailing,
                // resizable inspector model without that unstable window host.
                HSplitView {
                    detailContent
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                    if appState.noteHistoryVisible {
                        NoteHistorySheet(
                            note: note,
                            presentation: .trailing,
                            context: noteHistoryContext
                        )
                            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
                    } else {
                        ResearchInspectorView(
                            note: note,
                            controller: appState.researchController,
                            graph: appState.workspaceCatalog?.graph ?? appState.relationshipGraph,
                            catalog: appState.workspaceCatalog,
                            currentVaultID: appState.currentDocumentVaultID,
                            relationshipViewContext: relationshipViewContext
                        )
                            .frame(minWidth: 280, idealWidth: 322, maxWidth: 380, maxHeight: .infinity)
                    }
                }
            } else {
                detailContent
            }
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
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.995)))
                .zIndex(0)
        } else {
            FeaturedArtworkDetailView()
                .transition(.opacity)
        }
    }

    private var windowTitle: String {
        appState.currentNote?.title ?? appState.currentNote?.displayName ?? "Scholium"
    }
}

private struct LibrarySurface<Content: View>: View {
    let isElevatedOverDocument: Bool
    let content: Content

    init(
        isElevatedOverDocument: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.isElevatedOverDocument = isElevatedOverDocument
        self.content = content()
    }

    var body: some View {
        content
            .scholiumSurface(.navigation)
            .overlay(alignment: .trailing) {
                ScholiumStructuralRule(orientation: .vertical)
            }
            .ignoresSafeArea(.container, edges: .top)
            .zIndex(isElevatedOverDocument ? 2 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Library")
            .accessibilityIdentifier("scholium.librarySurface")
    }
}

private struct TriptychActionsMenu: View {
    let revealCurrentVault: () -> Void
    let manageTriptychs: () -> Void

    var body: some View {
        Menu {
            Button {
                manageTriptychs()
            } label: {
                Label("Manage Triptychs…", systemImage: "folder.badge.gearshape")
            }
            Button {
                revealCurrentVault()
            } label: {
                Label("Reveal Current Vault in Finder", systemImage: "folder")
            }
        } label: {
            Label("Triptych management", systemImage: "ellipsis")
        }
        .labelStyle(.iconOnly)
        .help("Triptych management")
        .accessibilityLabel("Triptych management")
        .accessibilityIdentifier("scholium.triptychManagement")
    }
}

private struct ScholiumLaunchPlaceholderView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Opening Scholium")
    }
}

/// The configured workspace's intentionally silent no-document state. The
/// Library remains the only actionable interface; this image is decorative.
private struct FeaturedArtworkDetailView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            } else {
                ScholiumColorRole.documentBackground.color
            }
        }
        .accessibilityHidden(true)
        .accessibilityIdentifier("scholium.featuredArtwork")
    }

    private var artwork: NSImage? {
        let name = colorScheme == .dark
            ? "ScholiumFeaturedFolioDark"
            : "ScholiumFeaturedFolioLight"
        let url = Bundle.module.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Artwork"
        ) ?? Bundle.module.url(forResource: name, withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }
}

private struct SpotlightSearchOverlay: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    let context: SpotlightSearchContext

    init(controller: DiscoveryController, context: SpotlightSearchContext) {
        self.controller = controller
        self.context = context
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(
                        reduceTransparency
                            ? ScholiumColorRole.documentBackground.color
                            : ScholiumColorRole.primaryText.color.opacity(0.12)
                    )
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

private struct AdaptiveResearchInspectorSheet: View {
    let note: WindowDocumentLocation
    let controller: ResearchController
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let currentVaultID: UUID?
    let relationshipViewContext: RelationshipViewContext
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Research Inspector")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            ResearchInspectorView(
                note: note,
                controller: controller,
                graph: graph,
                catalog: catalog,
                currentVaultID: currentVaultID,
                relationshipViewContext: relationshipViewContext
            )
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 560, idealHeight: 680)
        .scholiumSurface(.denseEvidence)
        .accessibilityIdentifier("scholium.adaptiveContextPanel")
    }
}

// MARK: - Loading Overlay

private struct LoadingOverlay: View {
    var body: some View {
        ProgressView("Opening vault…")
            .controlSize(.large)
            .padding(28)
            .scholiumEditorialSurface(
                .floatingControl,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.loadingSurfaceCornerRadius,
                    style: .continuous
                )
            )
            .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: WindowModel.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.kind.symbol)
                .font(.callout)
                .foregroundStyle(toast.kind.color)
            Text(toast.message)
                .font(.callout)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
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

// MARK: - Preview

#Preview {
    let workspaceStore = WorkspaceStore()
    ContentView()
        .environmentObject(WindowModel(workspaceStore: workspaceStore))
        .frame(width: 1100, height: 700)
}
