import AppKit
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
    @EnvironmentObject var appState: WindowModel
    let windowCoordinator: WorkspaceWindowCoordinator
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var attentionDismissalLedgerData = Data()
    @State private var pendingResearchActionFocusID: ResearchActionID?
    @State private var researchActionFocusRequest: ResearchActionFocusRequest?

    var body: some View {
        ScholiumWorkspaceSplitView(
            initialLibraryVisible: shellLibraryVisible,
            initialApparatusVisible: shellApparatusVisible,
            documentTabs: appState.documentTabController.tabs,
            selectedDocumentTabID: appState.documentTabController.selectedTabID,
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
                if !appState.hasCompletedInitialRestore {
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
            if appState.presentedAgentNoteChangeRequest != nil {
                windowCoordinator.restoreAgentNoteChangeFocus()
                appState.finishAgentNoteChangeRequestDismissal()
            } else if appState.researchController.actions.isPresented {
                let actionID = appState.researchController.actions.activeActionID
                appState.presentationRouter.dismissSheet()
                appState.researchController.actions.dismiss()
                restoreResearchActionFocus(ifOwnedBy: actionID)
            } else if appState.presentationRouter.sheet == nil,
                      appState.researchController.functions.isPresented {
                appState.researchController.functions.dismiss()
            }
            appState.agentNoteChangePresentationCoordinator
                .presentationBecameAvailable(windowID: appState.nativeWindowID)
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
        guard appState.hasCompletedInitialRestore,
              appState.vaultConfig != nil
        else { return true }
        return appState.sidebarVisible
    }

    private var shellApparatusVisible: Bool {
        ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_DISABLE_INSPECTOR"] != "1"
            && appState.hasCompletedInitialRestore
            && appState.vaultConfig != nil
            && appState.researchInspectorVisible
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
            refresh: { await appState.refreshWorkspaceCatalog() },
            inspectMaterial: { item in
                guard let context = item.materialChangedSinceUse else { return }
                appState.discoveryController.showAttentionQueue(false)
                appState.requestOpenNote(context.material)
            },
            resynthesize: { appState.requestResynthesis($0) },
            close: { appState.discoveryController.showAttentionQueue(false) }
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
                propertiesConfiguration: appState.currentDocumentPropertiesConfiguration
            ),
            openProperties: {
                guard let path = appState.currentNote?.relativePath else { return }
                appState.editingNotePath = path
                appState.showFrontmatterEditor = true
            },
            openAttention: {
                appState.discoveryController.showAttentionQueue(true)
            },
            retryRefresh: {
                Task { await appState.retryDerivedRefresh() }
            }
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
            beginSearch: { appState.beginSearch($0) },
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
            clearRequestedDiscussion: {
                appState.clearRequestedDiscussionPresentation()
            },
            handoffDiscussionRequest: { instructions in
                appState.agentApplicationHandoff.copyAndOpen(
                    instructions: instructions,
                    copy: { try appState.copyTextToClipboard($0) }
                )
            },
            copyDiscussionRequest: { instructions in
                appState.agentApplicationHandoff.copyOnly(
                    instructions: instructions,
                    copy: { try appState.copyTextToClipboard($0) }
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
        let selectedLibraryDocumentPath = appState.currentDocumentVaultID
            == appState.currentRegisteredVault?.id
            ? appState.selectedDocumentPath
            : nil
        return SidebarContext(
            triptychName: appState.workspaceAssignment?.triptych.name ?? "Not Selected",
            attentionItems: appState.workspaceCatalog?.attention,
            filteredNotes: appState.filteredNotes,
            allNotes: appState.notes,
            folders: appState.currentLibraryFolders,
            currentVaultID: appState.currentRegisteredVault?.id,
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
            noteLifecycleRequest: appState.noteLifecycleRequest,
            canCreateNote: appState.noteLocationScope == .workspace
                && appState.currentRegisteredVault != nil
                && !appState.isCreatingNote
                && !appState.isMutatingFolder,
            lifecycleMutationGeneration: appState.lifecycleMutationGeneration,
            catalogIsAvailable: appState.workspaceCatalog != nil,
            graphIsAvailable: appState.relationshipGraph != nil,
            tags: appState.allTags,
            authors: appState.availableAuthors,
            years: appState.availableYears,
            propertyKeys: propertyFilterOptions.keys,
            propertyValues: propertyFilterOptions.valuesByKey,
            resolvedIdentityPaths: Set(appState.noteIdentityByPath.keys),
            bibliographyController: appState.researchController.bibliography,
            attentionQueueContext: attentionQueueContext,
            notesAreOrdered: { appState.notesAreOrdered($0, $1) },
            selectLocationScope: { appState.requestNoteLocationScope($0) },
            openNote: { appState.requestOpenNote($0, disposition: $1) },
            openLifecycleNote: { appState.requestLifecycleNote($0, in: $1) },
            selectWorkspaceVault: { appState.requestWorkspaceVault($0) },
            lifecycleItems: { try await appState.lifecycleLocationItems(for: $0) },
            prepareLifecycle: { appState.prepareLifecycleOperation($0) },
            clearPreparedLifecycle: { appState.clearPreparedLifecycleOperation(at: $0) },
            createUntitledNote: { appState.requestUntitledNoteCreation(in: $0) },
            createUntitledFolder: {
                appState.requestUntitledFolderCreation(in: $0)
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
            deletePermanently: { try await appState.deleteNotePermanently($0) },
            classify: { path, slot, destination in
                try await appState.classifyUnclassified(
                    path,
                    into: slot,
                    destination: destination
                )
            },
            openRecommendedAnalysis: { reference in
                guard let note = appState.workspaceCatalog?.notes.first(where: {
                    $0.reference.vaultID == reference.vaultID
                        && $0.reference.relativePath == reference.relativePath
                }) else { return }
                appState.requestOpenNote(note.reference)
            },
            openRecommendedZoteroItem: { itemKey in
                await appState.zoteroBridge.openInZotero(zoteroKey: itemKey)
            },
            copyRecommendedBibliographyText: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                appState.showToast(String(localized: "Research instructions copied.", table: "Localizable", bundle: .module))
            },
            repairRecommendedBibliographyMethod: {
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
            revealCurrentVault: { appState.revealVaultInFinder() },
            setSidebarVisible: { windowCoordinator.actions.setLibraryVisible($0) },
            openSettings: { openSettings() },
            selectSortOrder: { appState.noteSortOrder = $0 },
            showError: { appState.showToast($0, kind: .error) }
        )
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
                    appState.showToast(String(localized: "Frontmatter saved", table: "Localizable", bundle: .module))
                }
                    .frame(minWidth: 520, minHeight: 560)
            }
        case .researchFunction(let route):
            if note(at: route.target.relativePath) != nil {
                ResearchFunctionPanelView(
                    controller: appState.researchController.functions,
                    context: ResearchFunctionPanelContext(
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
                        repairDiscussResponseDefaults: {
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
                        agentApplicationHandoff: appState.agentApplicationHandoff,
                        copyInstructions: { instructions in
                            try appState.copyTextToClipboard(instructions)
                            appState.showToast(String(localized: "Function instructions copied.", table: "Localizable", bundle: .module))
                        },
                        dismiss: {
                            appState.presentationRouter.dismissSheet()
                        }
                    )
                )
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
        case .researchAction(let route):
            if note(at: route.target.relativePath) != nil {
                ResearchActionPanelView(
                    controller: appState.researchController.actions,
                    context: ResearchActionPanelContext(
                        chooseLocalSource: {
                            let panel = NSOpenPanel()
                            panel.title = String(
                                localized: "Choose Source",
                                table: "Localizable",
                                bundle: .module
                            )
                            panel.prompt = String(
                                localized: "Choose",
                                table: "Localizable",
                                bundle: .module
                            )
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            panel.resolvesAliases = false
                            return panel.runModal() == .OK ? panel.url : nil
                        },
                        agentApplicationHandoff: appState.agentApplicationHandoff,
                        copyInstructions: { instructions in
                            try appState.copyTextToClipboard(instructions)
                            appState.showToast(
                                String(
                                    localized: "Action instructions copied.",
                                    table: "Localizable",
                                    bundle: .module
                                )
                            )
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
                        appState.researchController.actions.dismiss(
                            presentationID: route.presentationID
                        )
                    }
                }
            }
        case .agentNoteChange(let requestID):
            if let record = appState.presentedAgentNoteChangeRequest,
               record.id == requestID {
                AgentNoteChangeRequestView(
                    record: record,
                    targets: appState.displayTargets(for: record),
                    identity: appState.presentedAgentNoteChangeIdentity,
                    identityLoadFailed: appState.agentNoteChangeIdentityLoadFailed,
                    hasLocallyExpired: appState.agentNoteChangeHasLocallyExpired,
                    isResolving: appState.isResolvingAgentNoteChangeRequest,
                    resolve: { state, allowedNoteIDs in
                        appState.resolvePresentedAgentNoteChangeRequest(
                            state: state,
                            allowedNoteIDs: allowedNoteIDs
                        )
                    },
                    dismiss: {
                        appState.dismissPresentedAgentNoteChangeRequest(id: requestID)
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
                    _ = try await appState.restoreCheckpoint(
                        checkpointID,
                        selection: selection
                    )
                    appState.showToast(String(localized: "Checkpoint restored. Before Restore checkpoint created.", table: "Localizable", bundle: .module))
                },
                revealCheckpoints: {
                    appState.revealCheckpointsInFinder()
                }
            )
        case .lifecycle(let request):
            NoteLifecycleView(
                request: request,
                actions: NoteLifecycleActions(
                    putBackDestination: {
                        appState.documentController.putBackDestination(for: $0)
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

    private func finishFrontmatter(_ route: FrontmatterPanelRoute) {
        appState.presentationRouter.finishFrontmatter(route)
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
            detailContent
        }
    }

    @ViewBuilder
    private var apparatusRegion: some View {
        if let note = appState.currentNote {
            ResearchInspectorView(
                note: note,
                controller: appState.researchController,
                graph: appState.workspaceCatalog?.graph ?? appState.relationshipGraph,
                catalog: appState.workspaceCatalog,
                currentVaultID: appState.currentDocumentVaultID,
                researchInspectorContentContext: researchInspectorContentContext,
                researchActionsPresentation: appState.researchActionsPresentation(),
                researchActionFocusRequest: researchActionFocusRequest,
                registerResearchActionFocusOwner: {
                    pendingResearchActionFocusID = $0
                },
                openResearchAction: { appState.openResearchAction($0) },
                retryResearchActionCancellation: { runID in
                    appState.researchController.actions.retryCancellationRecovery(runID: runID)
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
        } else if appState.researchController.actions.hasCancellationBarrier {
            ResearchFunctionsInspectorView(
                presentation: appState.researchActionsPresentation(),
                freshness: .current,
                focusRequest: nil,
                registerFocusOwner: { _ in },
                select: { _ in },
                retryRefresh: {},
                retryCancellationRecovery: { runID in
                    appState.researchController.actions.retryCancellationRecovery(runID: runID)
                },
                settle: { _ in }
            )
            .scholiumSurface(.apparatus)
            .accessibilityIdentifier("scholium.researchActions.recoveryOnly")
        } else {
            Color.clear
                .scholiumSurface(.apparatus)
                .accessibilityHidden(true)
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
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.995)))
                .zIndex(0)
        } else {
            ScholiumNoDocumentDetailView()
                .transition(.opacity)
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

/// The configured workspace's intentionally silent no-document state. The
/// Library remains the only actionable interface.
private struct ScholiumNoDocumentDetailView: View {
    var body: some View {
        ScholiumColorRole.documentBackground.color
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .accessibilityIdentifier("scholium.noDocumentSurface")
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
            .padding(28)
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
    let color: Color

    init(toast: WindowModel.Toast) {
        message = toast.message
        symbol = toast.kind.symbol
        color = toast.kind.color
    }

    init(message: String) {
        self.message = message
        symbol = "checkmark.circle"
        color = ScholiumColorRole.confirmed.color
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(color)
            Text(message)
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
    ContentView(windowCoordinator: coordinator)
        .environmentObject(model)
        .frame(width: 1100, height: 700)
}
