import ScholiumContracts
import SwiftUI

enum DocumentNotificationKind {
    case success
    case information
    case error
}

struct DocumentFeatureState {
    let notes: [WindowDocumentLocation]
    let selectedDocumentPath: String?
    let ordinarySearchScope: SearchPresentationScope
    let currentVaultID: UUID?
    let vaultRole: VaultRole
    let locationScope: NoteLocationScope
    let noteIdentityByPath: [String: UUID]
    let documentRevisions: [String: DocumentFingerprint]
    let workspaceCatalog: WorkspaceCatalogSnapshot?
    let propertiesConfiguration: VaultPropertiesConfiguration?
    let reviewRecord: HumanReviewRecord?
    let reviewDisplayState: HumanReviewDisplayState
    let changedSinceReview: Bool
    let canComment: Bool
    let canEdit: Bool
    let documentTextScale: Double
    let readCSS: String
    let livePreviewCSS: String
    let initialScrollFraction: Double
    let requestedPresentationMode: NotePresentationMode?
    let pendingSourceLine: Int?
    let isCompactLayout: Bool
    let noteHistoryVisible: Bool
    let researchInspectorVisible: Bool
    let identityAmbiguity: NoteIdentityAmbiguity?
    let pendingIdentityRebinding: NoteIdentityPendingRebinding?
    let identityMigrationFailureMessage: String?
    let isResolvingIdentity: Bool
    let researchStrip: ResearchStripPresentation
}

struct DocumentFeatureActions {
    let requestIdentityResolution: @MainActor () -> Void
    let retryIdentityRecovery: @MainActor () async -> Void
    let beginSearch: @MainActor (SearchInvocation) -> Void
    let clearRequestedPresentationMode: @MainActor () -> Void
    let registerEditorFlush: @MainActor (
        String,
        UUID,
        @escaping @MainActor () async throws -> Void,
        @escaping @MainActor () async throws -> Void
    ) -> Void
    let unregisterEditorFlush: @MainActor (UUID) -> Void
    let clearPendingSourceLine: @MainActor () -> Void
    let requestComments: @MainActor (MarkdownReviewSelection?, UUID?) -> Void
    let rememberScrollPosition: @MainActor (Double) -> Void
    let openInternalLink: @MainActor (String) -> Void
    let openExternalURL: @MainActor (URL) -> Void
    let enterCSSSafeMode: @MainActor (String) -> Void
    let rememberPresentationMode: @MainActor (NotePresentationMode) -> Void
    let setPendingSourceLine: @MainActor (Int?) -> Void
    let editProperties: @MainActor () -> Void
    let openResearchFunction: @MainActor (
        ResearchFunctionID,
        ResearcherCommentAnchor?
    ) -> Void
    let setNoteHistoryVisible: @MainActor (Bool) -> Void
    let setResearchInspectorVisible: @MainActor (Bool) -> Void
    let notify: @MainActor (String, DocumentNotificationKind) -> Void
}

enum ResearchFunctionSelectionCapture {
    static func anchor(
        for selection: MarkdownReviewSelection?,
        in source: String,
        relativePath: String
    ) -> ResearcherCommentAnchor? {
        guard let selection else { return nil }
        let document = NoteDocument(relativePath: relativePath, rawContent: source)
        if let exactRange = selection.exactUTF16Range {
            return ResearcherCommentAnchorBuilder.anchor(
                in: source,
                fingerprint: document.fingerprint,
                utf16Range: exactRange,
                selectedText: selection.excerpt
            )
        }
        return ResearcherCommentAnchorBuilder.anchor(
            forRenderedQuotation: selection.excerpt,
            contextBefore: selection.contextBefore,
            contextAfter: selection.contextAfter,
            in: document
        )
    }
}

// MARK: - Note Content Container

struct DocumentFeatureView: View {
    @ObservedObject private var controller: DocumentController
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let critiqueProvenanceContext: CritiqueProvenanceContext

    init(
        controller: DocumentController,
        state: DocumentFeatureState,
        actions: DocumentFeatureActions,
        critiqueProvenanceContext: CritiqueProvenanceContext
    ) {
        self.controller = controller
        self.state = state
        self.actions = actions
        self.critiqueProvenanceContext = critiqueProvenanceContext
    }

    var body: some View {
        if let selectedDocumentPath = state.selectedDocumentPath,
           let note = state.notes.first(where: { $0.relativePath == selectedDocumentPath }) {
            if let vaultID = state.currentVaultID,
               let noteID = state.noteIdentityByPath[note.relativePath] {
                let key = DocumentSessionKey(vaultID: vaultID, noteID: noteID)
                NoteContentView(
                    controller: controller,
                    target: .workspace(key),
                    note: note,
                    documentSession: controller.session(for: key),
                    state: state,
                    actions: actions,
                    critiqueProvenanceContext: critiqueProvenanceContext
                )
                .id(key)
            } else {
                DocumentSessionFallback(
                    note: note,
                    controller: controller,
                    target: state.locationScope == .unclassified
                        ? .unclassified(relativePath: note.relativePath)
                        : .unavailable(relativePath: note.relativePath),
                    state: state,
                    actions: actions,
                    critiqueProvenanceContext: critiqueProvenanceContext
                )
                    .id(selectedDocumentPath)
            }
        }
    }
}

private struct DocumentSessionFallback: View {
    let note: WindowDocumentLocation
    let controller: DocumentController
    let target: DocumentEditingTarget
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let critiqueProvenanceContext: CritiqueProvenanceContext

    var body: some View {
        NoteContentView(
            controller: controller,
            target: target,
            note: note,
            documentSession: controller.session(for: target),
            state: state,
            actions: actions,
            critiqueProvenanceContext: critiqueProvenanceContext
        )
    }
}

struct ResearchInspectorView: View {
    @ObservedObject private var controller: ResearchController

    enum Mode: String, CaseIterable, Identifiable {
        case incoming = "Incoming"
        case outgoing = "Outgoing"
        case relationships = "Research"
        var id: String { rawValue }
    }

    let note: WindowDocumentLocation
    let graph: GraphSnapshot?
    let catalog: WorkspaceCatalogSnapshot?
    let currentVaultID: UUID?
    let relationshipViewContext: RelationshipViewContext

    init(
        note: WindowDocumentLocation,
        controller: ResearchController,
        graph: GraphSnapshot?,
        catalog: WorkspaceCatalogSnapshot?,
        currentVaultID: UUID?,
        relationshipViewContext: RelationshipViewContext
    ) {
        self.note = note
        self.controller = controller
        self.graph = graph
        self.catalog = catalog
        self.currentVaultID = currentVaultID
        self.relationshipViewContext = relationshipViewContext
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Research Inspector", selection: inspectorMode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .scholiumGlassSurface(
                .floatingControl,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()

            Group {
                switch inspectorMode.wrappedValue {
                case .incoming: BacklinksPanelView(context: relationshipContext)
                case .outgoing: OutgoingLinksPanelView(context: relationshipContext)
                case .relationships:
                    RelationshipView(
                        note: note,
                        controller: controller,
                        context: relationshipViewContext
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.researchInspector")
    }

    private var inspectorMode: Binding<Mode> {
        Binding(
            get: { Mode(rawValue: controller.inspector.modeRawValue.capitalized) ?? .incoming },
            set: { controller.selectInspectorMode($0.rawValue.lowercased()) }
        )
    }

    private var relationshipContext: RelationshipInspectorContext {
        RelationshipInspectorContext(
            graph: graph,
            catalog: catalog,
            current: currentVaultID.map {
                VaultQualifiedNoteID(vaultID: $0, relativePath: note.relativePath)
            },
            openReference: { reference, line in
                controller.requestOpen(reference, sourceLine: line)
            }
        )
    }
}
// MARK: - Note Content View

struct NoteContentView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var controller: DocumentController
    let target: DocumentEditingTarget
    let note: WindowDocumentLocation
    let documentSession: DocumentSessionModel
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    let critiqueProvenanceContext: CritiqueProvenanceContext

    init(
        controller: DocumentController,
        target: DocumentEditingTarget,
        note: WindowDocumentLocation,
        documentSession: DocumentSessionModel,
        state: DocumentFeatureState,
        actions: DocumentFeatureActions,
        critiqueProvenanceContext: CritiqueProvenanceContext
    ) {
        self.controller = controller
        self.target = target
        self.note = note
        self.documentSession = documentSession
        self.state = state
        self.actions = actions
        self.critiqueProvenanceContext = critiqueProvenanceContext
    }

    private var isEditing: Bool {
        documentSession.isEditing
    }
    private var editingSource: String {
        documentSession.editingSource
    }
    private var editError: String? {
        get { documentSession.editError }
        nonmutating set { documentSession.editError = newValue }
    }
    private var isSavingEdit: Bool {
        documentSession.isSavingEdit
    }
    private var presentationMode: NotePresentationMode {
        get { documentSession.presentationMode }
        nonmutating set { documentSession.presentationMode = newValue }
    }
    private var returnToReadAfterSave: Bool {
        get { documentSession.returnToReadAfterSave }
        nonmutating set { documentSession.returnToReadAfterSave = newValue }
    }
    private var renderedReadHTML: String {
        get { documentSession.renderedReadHTML }
        nonmutating set { documentSession.renderedReadHTML = newValue }
    }
    private var renderedReadFingerprint: String {
        get { documentSession.renderedReadFingerprint }
        nonmutating set { documentSession.renderedReadFingerprint = newValue }
    }
    private var failedReadFingerprint: String? {
        get { documentSession.failedReadFingerprint }
        nonmutating set { documentSession.failedReadFingerprint = newValue }
    }
    private var conflict: DocumentConflictSnapshot? {
        documentSession.conflict
    }
    private var canRetrySave: Bool {
        documentSession.canRetrySave
    }
    private var showConflictComparison: Bool {
        get { documentSession.showConflictComparison }
        nonmutating set { documentSession.showConflictComparison = newValue }
    }
    private var editorFlushToken: UUID { documentSession.editorFlushToken }
    private var editorSession: MarkdownEditorSession { documentSession.editorSession }

    var body: some View {
        VStack(spacing: 0) {
            if let ambiguity = state.identityAmbiguity {
                IdentityAmbiguityNotice(ambiguity: ambiguity) {
                    actions.requestIdentityResolution()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else if let pending = state.pendingIdentityRebinding {
                IdentityMigrationNotice(
                    rebinding: pending,
                    message: state.identityMigrationFailureMessage,
                    isRetrying: state.isResolvingIdentity
                ) {
                    await actions.retryIdentityRecovery()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if isCritiqueDocument {
                CritiqueProvenanceView(
                    note: note,
                    context: critiqueProvenanceContext
                )
            }

            ZStack(alignment: .top) {
                documentBodySurface

                documentContextRow
                    .zIndex(2)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !state.researchStrip.items.isEmpty {
                    ResearchStripView(
                        presentation: state.researchStrip,
                        select: openResearchFunction
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .toolbar { noteToolbar }
        .focusedSceneValue(\.scholiumSearchActions, ScholiumSearchActions { invocation in
            actions.beginSearch(invocation)
        })
        .focusedSceneValue(
            \.scholiumResearchFunctionActions,
            ScholiumFocusedResearchFunctionActions(open: openResearchFunction)
        )
        .focusedSceneValue(
            \.scholiumEditorActions,
            isEditing ? ScholiumFocusedEditorActions(
                isComposing: editorSession.context?.composing == true,
                isAvailable: { command in
                    editorSession.context?.availableCommands.contains(command) == true
                },
                canAddComment: {
                    editorSession.context?.selections.contains(where: \.isNonempty) == true
                },
                perform: { command in
                    Task { @MainActor in
                        do {
                            try await editorSession.perform(command)
                        } catch {
                            actions.notify(error.localizedDescription, .error)
                        }
                    }
                },
                performWithArgument: { command, argument in
                    Task { @MainActor in
                        do {
                            try await editorSession.perform(command, argument: argument)
                        } catch {
                            actions.notify(error.localizedDescription, .error)
                        }
                    }
                },
                addComment: requestResearcherCommentsFromDocument
            ) : nil
        )
        .sheet(isPresented: Binding(
            get: { showConflictComparison },
            set: { showConflictComparison = $0 }
        )) {
            if let conflict {
                ConflictComparisonSheet(
                    conflict: conflict,
                    onReturnToEditing: {
                        showConflictComparison = false
                        Task { @MainActor in
                            await Task.yield()
                            editorSession.focus()
                        }
                    },
                    onReloadFromDisk: { reloadFromDisk() }
                )
            }
        }
        .alert(conflict == nil ? "Save Failed" : "This Note Changed on Disk", isPresented: Binding(
            get: { editError != nil && (conflict == nil || !editorIsComposing) },
            set: { if !$0, !editorIsComposing { editError = nil } }
        )) {
            if conflict != nil {
                Button("Compare Changes") {
                    editError = nil
                    showConflictComparison = true
                }
                .keyboardShortcut(.defaultAction)
                Button("Reload from Disk", role: .destructive) { reloadFromDisk() }
            } else if canRetrySave {
                Button("Retry Save") {
                    controller.retrySave(session: documentSession, target: target)
                }
            }
            Button("Keep Editing", role: .cancel) { editError = nil }
        } message: {
            Text(editError ?? "")
        }
        .onChange(of: state.requestedPresentationMode) { _, requested in
            guard let requested else { return }
            selectPresentationMode(requested)
            actions.clearRequestedPresentationMode()
        }
        .onAppear {
            controller.observe(documentSession)
            restorePresentationModeIfAvailable()
            consumePendingPresentationRequest()
            actions.registerEditorFlush(
                note.relativePath,
                editorFlushToken,
                {
                    try await controller.flushForExternalOperation(
                        session: documentSession,
                        target: target
                    )
                },
                {
                    try await editorSession.captureStateForViewReconstruction()
                }
            )
        }
        .onChange(of: editingIsAvailable) { _, available in
            // Window restoration publishes the selected note before stable
            // identity recovery necessarily finishes. Keep the edit gate
            // intact, then apply the committed mode as soon as editing becomes
            // available instead of leaving the document in the default Read
            // mode for the rest of the session.
            if available { restorePresentationModeIfAvailable() }
        }
        .onChange(of: isEditing) { _, _ in
            documentSession.readSelection = nil
        }
        .onDisappear {
            // The document session, not this reconstructed view, owns the
            // pending autosave. Inspector and window-layout changes can
            // temporarily detach this view while the session remains active.
            actions.unregisterEditorFlush(editorFlushToken)
        }
        .onChange(of: editorSession.isLoaded) { _, loaded in
            guard loaded, let line = state.pendingSourceLine else { return }
            editorSession.goToLine(line)
            actions.clearPendingSourceLine()
        }
        .task(id: noteFingerprint.sha256) {
            failedReadFingerprint = nil
            documentSession.readSelection = nil
            let source = note.rawContent
            let relativePath = note.relativePath
            let fingerprint = noteFingerprint.sha256
            let html = await Task.detached(priority: .userInitiated) {
                SafeMarkdownRenderer.render(
                    NoteDocument(relativePath: relativePath, rawContent: source)
                ).htmlBody
            }.value
            guard !Task.isCancelled, fingerprint == noteFingerprint.sha256 else { return }
            renderedReadHTML = html
            renderedReadFingerprint = fingerprint
        }
    }

    private var commentingIsAvailable: Bool {
        state.selectedDocumentPath == note.relativePath && state.canComment
    }

    private var editingIsAvailable: Bool {
        state.canEdit && !isCritiqueDocument
    }

    private var isCritiqueDocument: Bool {
        state.vaultRole.allowsCritique
            && (note.relativePath == "Critiques" || note.relativePath.hasPrefix("Critiques/"))
    }

    private var noteFingerprint: DocumentFingerprint {
        state.documentRevisions[note.relativePath] ?? DocumentFingerprint(content: note.rawContent)
    }

    private var bodyEditor: some View {
        MarkdownEditorWebView(
            session: editorSession,
            documentID: note.relativePath,
            source: editingSource,
            mode: presentationMode,
            userCSS: scaledEditorCSS,
            linkCompletions: editorLinkCompletions,
            researcherComments: currentResearcherComments,
            initialScrollFraction: state.initialScrollFraction,
            onDocumentChange: { updatedSource in
                controller.updateEditingSource(
                    updatedSource,
                    session: documentSession,
                    target: target
                )
            },
            onRequestSave: {
                Task {
                    await controller.persistEditingSource(
                        session: documentSession,
                        target: target
                    )
                }
            },
            onRequestSearch: {
                actions.beginSearch(.findInNote(previousScope: state.ordinarySearchScope))
            },
            onRequestComment: requestResearcherCommentsFromDocument,
            onLinkActivation: { target in
                if let url = URL(string: target),
                   let scheme = url.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    actions.openExternalURL(url)
                } else {
                    actions.openInternalLink(target)
                }
            },
            onCommentActivation: commentingIsAvailable ? { commentID in
                actions.requestComments(nil, commentID)
            } : nil,
            onScrollFractionChange: { actions.rememberScrollPosition($0) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var documentBodySurface: some View {
        if isEditing {
            bodyEditor
        } else if ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_NATIVE_READ"] != "1",
                  renderedReadFingerprint == noteFingerprint.sha256,
                  !renderedReadHTML.isEmpty,
                  failedReadFingerprint != noteFingerprint.sha256 {
            readDocumentSurface
        } else {
            NativeMarkdownReadView(
                source: note.rawContent,
                textScale: state.documentTextScale,
                topContentInset: ScholiumMetrics.ContextSurface.initialOverlayClearance,
                onLinkClick: {
                    actions.openInternalLink($0)
                },
                onRequestComment: commentingIsAvailable ? { selection in
                    actions.requestComments(selection, nil)
                } : nil,
                onSelectionChange: { selection in
                    documentSession.readSelection = selection
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
    }

    private var readDocumentSurface: some View {
        SafeMarkdownReadWebView(
            documentID: note.relativePath,
            fingerprint: noteFingerprint.sha256,
            source: note.rawContent,
            htmlBody: renderedReadHTML,
            userCSS: scaledReadCSS,
            researcherComments: currentResearcherComments,
            onLinkClick: {
                actions.openInternalLink($0)
            },
            onOpenExternalURL: actions.openExternalURL,
            onCommentSelection: commentingIsAvailable ? { selection in
                actions.requestComments(selection, nil)
            } : nil,
            onSelectionChange: { selection in
                documentSession.readSelection = selection
            },
            onCommentActivation: commentingIsAvailable ? { commentID in
                actions.requestComments(nil, commentID)
            } : nil,
            onRenderingFailure: { reason in
                actions.enterCSSSafeMode(reason)
                failedReadFingerprint = noteFingerprint.sha256
            },
            onRenderingReady: {
                PerformanceProbe.shared.markReadReady(documentID: note.relativePath)
            },
            initialScrollFraction: state.initialScrollFraction,
            onScrollFractionChange: {
                actions.rememberScrollPosition($0)
            },
            targetSourceLine: state.pendingSourceLine,
            onSourceLineReached: { actions.clearPendingSourceLine() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var currentResearcherComments: [ResearcherComment] {
        state.reviewRecord?.comments ?? []
    }

    private var scaledReadCSS: String {
        state.readCSS
            + "\n.scholium-document { font-size: \(state.documentTextScale)em; padding-top: \(ScholiumMetrics.ContextSurface.initialOverlayClearance)px; }"
    }

    private var scaledEditorCSS: String {
        state.livePreviewCSS
            + """

            .cm-content { font-size: \(state.documentTextScale)em; }
            .scholium-live-mode .cm-content,
            .scholium-source-mode .cm-content {
              padding-top: \(ScholiumMetrics.ContextSurface.initialOverlayClearance)px;
            }
            """
    }

    private var editorLinkCompletions: [EditorLinkCompletion] {
        guard let currentVaultID = state.currentVaultID,
              let catalogNotes = state.workspaceCatalog?.notes,
              !catalogNotes.isEmpty else {
            let stemCounts = Dictionary(grouping: state.notes, by: \.displayName).mapValues(\.count)
            return state.notes.map { candidate in
                let needsPath = (stemCounts[candidate.displayName] ?? 0) > 1
                return EditorLinkCompletion(
                    label: candidate.title ?? candidate.displayName,
                    insertion: needsPath
                        ? (candidate.relativePath as NSString).deletingPathExtension
                        : candidate.displayName,
                        detail: "Current Vault — \(candidate.relativePath)",
                    path: candidate.relativePath,
                    isAmbiguous: false
                )
            }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        }

        func stem(_ path: String) -> String {
            ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        func folder(_ path: String) -> String {
            (path as NSString).deletingLastPathComponent
        }
        let stemGroups = Dictionary(grouping: catalogNotes) {
            stem($0.reference.relativePath).folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
        }
        let pathGroups = Dictionary(grouping: catalogNotes) {
            (($0.reference.relativePath as NSString).deletingPathExtension).folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
        }
        let currentFolder = folder(note.relativePath)

        return catalogNotes.map { candidate in
            let candidateStem = stem(candidate.reference.relativePath)
            let stemKey = candidateStem.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            let relativeWithoutExtension = (candidate.reference.relativePath as NSString)
                .deletingPathExtension
            let pathKey = relativeWithoutExtension.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            let sameFolderMatches = stemGroups[stemKey, default: []].filter {
                $0.reference.vaultID == currentVaultID
                    && folder($0.reference.relativePath) == currentFolder
            }
            let currentVaultMatches = stemGroups[stemKey, default: []].filter {
                $0.reference.vaultID == currentVaultID
            }
            let allStemMatches = stemGroups[stemKey, default: []]
            let allPathMatches = pathGroups[pathKey, default: []]

            let insertion: String
            let isAmbiguous: Bool
            if candidate.reference.vaultID == currentVaultID,
               folder(candidate.reference.relativePath) == currentFolder,
               sameFolderMatches.count == 1 {
                insertion = candidateStem
                isAmbiguous = false
            } else if candidate.reference.vaultID == currentVaultID,
                      currentVaultMatches.count == 1 {
                insertion = candidateStem
                isAmbiguous = false
            } else if allStemMatches.count == 1 {
                insertion = candidateStem
                isAmbiguous = false
            } else if candidate.reference.vaultID == currentVaultID || allPathMatches.count == 1 {
                insertion = relativeWithoutExtension
                isAmbiguous = false
            } else {
                insertion = ""
                isAmbiguous = true
            }

            let ambiguity = isAmbiguous
                ? " — Ambiguous: no unique Obsidian-compatible target"
                : ""
            return EditorLinkCompletion(
                label: candidate.title,
                insertion: insertion,
                detail: "\(candidate.reference.vaultName) — \(candidate.reference.vaultRole.displayName) — \(candidate.reference.relativePath)\(ambiguity)",
                path: "\(candidate.reference.vaultName)/\(candidate.reference.relativePath)",
                isAmbiguous: isAmbiguous
            )
        }.sorted {
            if $0.label != $1.label { return $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            return $0.path < $1.path
        }
    }

    private var editorStatusText: String {
        if editError != nil { return "Not saved" }
        if isSavingEdit { return "Saving…" }
        if hasUnsavedChanges { return "Waiting to save…" }
        return "Saved automatically"
    }

    private var hasUnsavedChanges: Bool {
        documentSession.hasUnsavedChanges
    }

    private var editorIsComposing: Bool {
        isEditing && editorSession.context?.composing == true
    }

    private func selectPresentationMode(_ mode: NotePresentationMode) {
        guard !editorIsComposing else {
            actions.notify("Finish text composition to change document mode.", .information)
            return
        }
        if mode == .read {
            guard isEditing else {
                presentationMode = .read
                actions.rememberPresentationMode(.read)
                return
            }
            returnToReadAfterSave = true
            Task {
                do {
                    try await controller.flushForExternalOperation(
                        session: documentSession,
                        target: target
                    )
                    guard returnToReadAfterSave else { return }
                    finishEditing()
                } catch { /* Controller published the recoverable error state. */ }
            }
            return
        }

        guard editingIsAvailable else {
            actions.notify("This note is read-only in Scholium.", .information)
            return
        }
        actions.rememberPresentationMode(mode)

        if isEditing {
            presentationMode = mode
        } else {
            beginEditing(mode: mode)
        }
    }

    private func restorePresentationModeIfAvailable() {
        guard !isEditing,
              presentationMode != .read,
              editingIsAvailable else { return }
        beginEditing(mode: presentationMode)
    }

    private func consumePendingPresentationRequest() {
        guard let requested = state.requestedPresentationMode else { return }
        selectPresentationMode(requested)
        actions.clearRequestedPresentationMode()
        if let line = state.pendingSourceLine {
            editorSession.goToLine(line)
        }
    }

    private func beginEditing(mode: NotePresentationMode = .livePreview) {
        controller.beginEditing(
            session: documentSession,
            target: target,
            source: note.rawContent,
            revision: state.documentRevisions[note.relativePath],
            mode: mode
        )
    }

    private func finishEditing() {
        controller.finishEditing(session: documentSession, target: target)
        actions.rememberPresentationMode(.read)
    }

    private func reloadFromDisk() {
        Task {
            do {
                try await controller.reloadFromDisk(
                    session: documentSession,
                    target: target
                )
                actions.rememberPresentationMode(.read)
            } catch { /* Controller published the recoverable error state. */ }
        }
    }

    // MARK: - Toolbar

    private var documentContextRow: some View {
        DocumentMeasureAlignedLayout {
            MetadataCardView(
                note: note,
                propertiesConfiguration: state.propertiesConfiguration,
                canEdit: state.canEdit,
                changedSinceReview: state.changedSinceReview,
                editProperties: actions.editProperties
            ) {
                documentContextControls
            }
        }
        // The controls, Properties strip, expanded panel, and document all
        // share one centered 920-point measure. This view floats above the
        // scrolling document rather than reserving an opaque toolbar band.
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var documentContextControls: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(NotePresentationMode.allCases) { mode in
                    Button {
                        selectPresentationMode(mode)
                    } label: {
                        if mode == presentationMode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                }
            } label: {
                Image(systemName: presentationMode.symbol)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!editingIsAvailable || editorIsComposing)
            .help(editorIsComposing
                ? "Finish text composition to change document mode."
                : "Document mode: \(presentationMode.title)")
            .accessibilityLabel("Document mode")
            .accessibilityValue(presentationMode.title)
            .accessibilityIdentifier("scholium.documentModeMenu")

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 2)

            Menu {
                if documentHeadings.isEmpty {
                    Text("No Headings")
                } else {
                    ForEach(Array(documentHeadings.enumerated()), id: \.offset) { _, heading in
                        Button {
                            actions.setPendingSourceLine(heading.span.start.line)
                            if isEditing { editorSession.goToLine(heading.span.start.line) }
                        } label: {
                            Text(String(repeating: "  ", count: max(0, heading.level - 1)) + heading.text)
                        }
                    }
                }
            } label: {
                Image(systemName: "list.bullet.indent")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Heading Outline")
            .accessibilityLabel("Heading Outline")
            .accessibilityIdentifier("scholium.headingOutline")
        }
        .frame(
            width: ScholiumMetrics.ContextSurface.leadingControlsWidth,
            height: ScholiumMetrics.ContextSurface.controlHeight
        )
        .scholiumGlassSurface(
            .floatingControl,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.documentContextControls")
    }

    @ToolbarContentBuilder
    var noteToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                actions.beginSearch(.general)
            } label: {
                if state.isCompactLayout {
                    Image(systemName: "magnifyingglass")
                } else {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            .help("Search the Triptych")
            .accessibilityLabel("Search")
            .accessibilityIdentifier("scholium.searchToolbarButton")
        }

        ToolbarItem(placement: .primaryAction) {
            ControlGroup {
                Button {
                    actions.setNoteHistoryVisible(!state.noteHistoryVisible)
                } label: {
                    Label(
                        state.noteHistoryVisible ? "Hide Note History" : "Show Note History",
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .disabled(isEditing || state.noteIdentityByPath[note.relativePath] == nil)
                .help(state.noteHistoryVisible ? "Hide Note History" : "Show Note History")
                .accessibilityIdentifier("scholium.noteHistoryButton")

                Button {
                    actions.setResearchInspectorVisible(!state.researchInspectorVisible)
                } label: {
                    Label(
                        state.researchInspectorVisible ? "Hide Research Inspector" : "Show Research Inspector",
                        systemImage: "sidebar.trailing"
                    )
                }
                .help(state.researchInspectorVisible ? "Hide Research Inspector" : "Show Research Inspector")
                .accessibilityIdentifier("scholium.researchInspectorButton")
            }
        }
    }

    private func requestResearcherCommentsFromDocument() {
        guard commentingIsAvailable else { return }
        guard isEditing else {
            actions.notify(
                "Select a passage in Read, Live Preview, or Source before adding a Comment.",
                .information
            )
            return
        }
        Task { @MainActor in
            do {
                let currentSource = try await editorSession.currentText(for: note.relativePath)
                let selection = try await editorSession.currentSelection(
                    for: note.relativePath,
                    in: currentSource
                )
                guard let selection,
                      ResearchFunctionSelectionCapture.anchor(
                          for: selection,
                          in: currentSource,
                          relativePath: note.relativePath
                      ) != nil else {
                    actions.notify(
                        "Select a passage before adding a Comment. Review or Critique provides the whole-note judgment.",
                        .information
                    )
                    editorSession.focus()
                    return
                }
                try await controller.flushForExternalOperation(
                    session: documentSession,
                    target: target
                )
                actions.requestComments(selection, nil)
            } catch {
                actions.notify(
                    "Scholium could not capture the current editor selection. Keep editing and try again. \(error.localizedDescription)",
                    .error
                )
            }
        }
    }

    private func openResearchFunction(_ function: ResearchFunctionID) {
        guard !editorIsComposing else {
            actions.notify(
                "Finish text composition to open a research function.",
                .information
            )
            return
        }
        guard isEditing else {
            let selection = documentSession.readSelection
            let anchor = ResearchFunctionSelectionCapture.anchor(
                for: selection,
                in: note.rawContent,
                relativePath: note.relativePath
            )
            if selection != nil, anchor == nil {
                actions.notify(
                    "Scholium could not match the selected passage reliably. The function will open for the whole note.",
                    .information
                )
            }
            actions.openResearchFunction(function, anchor)
            return
        }

        Task { @MainActor in
            do {
                let currentSource = try await editorSession.currentText(for: note.relativePath)
                let selection = try await editorSession.currentSelection(
                    for: note.relativePath,
                    in: currentSource
                )
                let anchor = ResearchFunctionSelectionCapture.anchor(
                    for: selection,
                    in: currentSource,
                    relativePath: note.relativePath
                )
                actions.openResearchFunction(function, anchor)
            } catch {
                actions.notify(
                    "Scholium could not capture the current selection. The function will open for the whole note. \(error.localizedDescription)",
                    .information
                )
                actions.openResearchFunction(function, nil)
            }
        }
    }

    private var documentHeadings: [HeadingNode] {
        MarkdownSemanticDocument(
            parsing: NoteDocument(relativePath: note.relativePath, rawContent: note.rawContent)
        ).headings
    }

}

// MARK: - Note History

private struct ConflictComparisonSheet: View {
    let conflict: DocumentConflictSnapshot
    let onReturnToEditing: () -> Void
    let onReloadFromDisk: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare Changes")
                        .font(.title2.weight(.semibold))
                    Text(conflict.relativePath)
                        .font(ScholiumTypography.swiftUIRevisionIdentity())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            HStack(alignment: .top, spacing: 24) {
                revisionLabel(
                    title: "Current Editor",
                    fingerprint: conflict.editorRevision,
                    detail: "Based on \(short(conflict.baseRevision))"
                )
                revisionLabel(
                    title: "Disk Version",
                    fingerprint: conflict.diskRevision,
                    detail: "The version shown below"
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(marker(for: line.kind))
                                .font(ScholiumTypography.swiftUIDiff(bold: true))
                                .foregroundStyle(color(for: line.kind))
                                .frame(width: 16)
                                .accessibilityLabel(label(for: line.kind))
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(ScholiumTypography.swiftUIDiff())
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(color(for: line.kind).opacity(line.kind == .unchanged ? 0 : 0.08))
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Button("Return to Editing", action: onReturnToEditing)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reload from Disk", role: .destructive, action: onReloadFromDisk)
            }
            .padding(16)
        }
        .frame(minWidth: 0, idealWidth: 900, minHeight: 520, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.conflictComparison")
    }

    @ViewBuilder
    private func revisionLabel(
        title: String,
        fingerprint: DocumentFingerprint,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            Text(short(fingerprint))
                .font(ScholiumTypography.swiftUIRevisionIdentity())
                .textSelection(.enabled)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            title == "Current Editor"
                ? "scholium.conflict.currentRevision"
                : "scholium.conflict.diskRevision"
        )
    }

    private func marker(for kind: DocumentConflictLineKind) -> String {
        switch kind {
        case .unchanged: " "
        case .editorOnly: "−"
        case .diskOnly: "+"
        }
    }

    private func label(for kind: DocumentConflictLineKind) -> String {
        switch kind {
        case .unchanged: "Unchanged"
        case .editorOnly: "Current editor only"
        case .diskOnly: "Disk version only"
        }
    }

    private func color(for kind: DocumentConflictLineKind) -> Color {
        switch kind {
        case .unchanged: .secondary
        case .editorOnly: .red
        case .diskOnly: .green
        }
    }

    private func short(_ fingerprint: DocumentFingerprint) -> String {
        "SHA-256 \(fingerprint.sha256.prefix(12))… (\(fingerprint.byteCount) bytes)"
    }

    private var diffLines: [DocumentConflictLine] { conflict.comparisonLines }
}

enum NoteHistoryPresentation {
    case sheet
    case trailing
}

struct NoteHistoryContext {
    let controller: ResearchController
    let vaultRole: VaultRole
    let documentRevisions: [String: DocumentFingerprint]
    let currentReview: @MainActor (String) -> HumanReviewRecord?
    let loadDialogue: @MainActor (String) async -> [DialogueEntry]
    let loadCritique: @MainActor (String) async -> CritiqueAssociation?
    let loadCheckpoints: @MainActor (String) async throws -> [TriptychCheckpoint]
    let checkpointContent: @MainActor (UUID, String) async throws -> String
    let createCheckpoint: @MainActor (String) async throws -> Void
    let restoreNote: @MainActor (String, UUID) async throws -> Void
    let revealCheckpoints: @MainActor () -> Void
    let copyText: @MainActor (String) throws -> Void
    let openNote: @MainActor (String) -> Void
    let closeTrailing: @MainActor () -> Void
    let notify: @MainActor (String) -> Void
}

private enum DialogueHistorySheetRoute: Identifiable {
    case followUp(DialogueEntry)
    case response(DialogueEntry)

    var id: String {
        switch self {
        case .followUp(let entry): "follow-up-\(entry.id.uuidString)"
        case .response(let entry): "response-\(entry.id.uuidString)"
        }
    }
}

struct NoteHistorySheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var researchController: ResearchController
    let note: WindowDocumentLocation
    let presentation: NoteHistoryPresentation
    let context: NoteHistoryContext

    @State private var review: HumanReviewRecord?
    @State private var dialogue: [DialogueEntry] = []
    @State private var critique: CritiqueAssociation?
    @State private var checkpoints: [TriptychCheckpoint] = []
    @State private var selectedCheckpoint: TriptychCheckpoint?
    @State private var checkpointSource: String?
    @State private var checkpointPresentation: CheckpointPresentation = .compare
    @State private var pendingDialogueSheet: DialogueHistorySheetRoute?
    @State private var expandedDialogueEntryIDs: Set<UUID> = []
    @State private var isLoading = true
    @State private var isRestoring = false
    @State private var showCreateCheckpoint = false
    @State private var errorMessage: String?

    init(
        note: WindowDocumentLocation,
        presentation: NoteHistoryPresentation = .sheet,
        context: NoteHistoryContext
    ) {
        self.note = note
        self.presentation = presentation
        self.context = context
        _researchController = ObservedObject(wrappedValue: context.controller)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Note History")
                        .font(.title2.weight(.semibold))
                    Text(note.title ?? note.displayName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Create Checkpoint…") {
                        showCreateCheckpoint = true
                    }
                    Divider()
                    Button("Reveal Checkpoints in Finder") {
                        context.revealCheckpoints()
                    }
                } label: {
                    Label("Checkpoint Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .help("Checkpoint Actions")
                .accessibilityLabel("Checkpoint Actions")
                .accessibilityIdentifier("scholium.noteHistory.checkpointActions")
                if presentation == .sheet {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        context.closeTrailing()
                    } label: {
                        Label("Hide Note History", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)
                    .help("Hide Note History")
                }
            }
            .padding(18)

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading Note History…")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if context.vaultRole.allowsHumanReview { reviewSection }
                        commentSection
                        functionRunSection
                        dialogueSection
                        if context.vaultRole.allowsCritique { critiqueSection }
                        checkpointSection
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let selectedCheckpoint {
                Divider()

                HStack {
                    Spacer()
                    Button("Restore This Version", role: .destructive) {
                        restore(selectedCheckpoint)
                    }
                    .disabled(isRestoring)
                }
                .padding(16)
            }
        }
        .frame(
            minWidth: presentation == .sheet ? 0 : 280,
            idealWidth: presentation == .sheet ? 880 : 340,
            maxWidth: presentation == .trailing ? .infinity : nil,
            minHeight: presentation == .sheet ? 560 : 0,
            idealHeight: presentation == .sheet ? 700 : nil,
            maxHeight: presentation == .trailing ? .infinity : nil
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.noteHistoryPanel")
        .task { await reload() }
        .onChange(of: selectedCheckpoint) { _, checkpoint in
            guard let checkpoint else {
                checkpointSource = nil
                return
            }
            Task {
                do {
                    checkpointSource = try await context.checkpointContent(
                        checkpoint.id,
                        note.relativePath
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showCreateCheckpoint) {
            CreateCheckpointView { name in
                try await context.createCheckpoint(name)
                context.notify("Checkpoint created.")
            }
        }
        .alert("Note History Unavailable", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $pendingDialogueSheet) { route in
            switch route {
            case .followUp(let entry):
                ManualDialogueFollowUpView(
                    controller: context.controller,
                    entry: entry
                ) { updated in
                    if let index = dialogue.firstIndex(where: { $0.id == updated.id }) {
                        dialogue[index] = updated
                    }
                    pendingDialogueSheet = nil
                }
            case .response(let entry):
                ManualDialogueReplyView(
                    controller: context.controller,
                    entry: entry
                ) { updated in
                    if let index = dialogue.firstIndex(where: { $0.id == updated.id }) {
                        dialogue[index] = updated
                    }
                    pendingDialogueSheet = nil
                }
            }
        }
    }

    private var reviewSection: some View {
        historySection("Human Review", systemImage: "checkmark.seal") {
            if let review {
                if let latest = review.latestReview {
                    HStack {
                        Label(
                            latest.qualification == .qualified ? "Qualified" : "Unqualified",
                            systemImage: latest.qualification == .qualified
                                ? "checkmark.seal.fill"
                                : "xmark.seal.fill"
                        )
                        .foregroundStyle(latest.qualification == .qualified ? .green : .red)
                        Spacer()
                        Text(latest.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                    Text(latest.reviewNote)
                        .textSelection(.enabled)
                    Text("Bound to SHA-256 \(latest.fingerprint.sha256.prefix(12))…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else if let draft = review.draft {
                    Label("Review draft saved", systemImage: "square.and.pencil")
                    if !draft.reviewNote.isEmpty { Text(draft.reviewNote).textSelection(.enabled) }
                } else {
                    emptyText("No completed Human Review for this note.")
                }
            } else {
                emptyText("This note has no Human Review.")
            }
        }
    }

    private var commentSection: some View {
        historySection("Researcher Comments", systemImage: "text.bubble") {
            if let comments = review?.comments, !comments.isEmpty {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            let anchor = comment.anchor
                            Text(anchor.state == .needsReattachment
                                ? "Needs Reattachment — originally line \(anchor.line)"
                                : (anchor.line == anchor.endLine
                                    ? "Line \(anchor.line)"
                                    : "Lines \(anchor.line)–\(anchor.endLine)"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(anchor.state == .needsReattachment ? Color.orange : Color.secondary)
                            if comment.resolvedAt != nil {
                                Text("Resolved")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Text(comment.text).textSelection(.enabled)
                        Text(comment.anchor.selectedText ?? comment.anchor.quotation)
                            .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 3)
                    if comment.id != comments.last?.id { Divider() }
                }
            } else {
                emptyText("This note has no researcher comments.")
            }
        }
    }

    private var functionRunSection: some View {
        historySection("Function Runs", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            if currentFunctionRuns.isEmpty {
                emptyText("No Research Function runs are recorded for this note.")
            } else {
                Text("Run state is shown here without merging Dialogue, Critique, Human Review, Comments, or Fidelity findings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(currentFunctionRuns) { run in
                    VStack(alignment: .leading, spacing: 8) {
                        ResearchFunctionRunStatusView(record: run, showsFunction: true)
                        if let instructions = run.preparedInstructions,
                           run.runState != .complete,
                           run.runState != .cancelled {
                            Button("Copy Instructions for Agent") {
                                do {
                                    try context.copyText(instructions)
                                    context.notify("Research Function instructions copied")
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                            .accessibilityIdentifier(
                                "scholium.noteHistory.copyResearchFunctionInstructions"
                            )
                        }
                    }
                    if run.id != currentFunctionRuns.last?.id { Divider() }
                }
            }
        }
        .accessibilityIdentifier("scholium.noteHistory.functionRuns")
    }

    private var currentFunctionRuns: [ResearchFunctionRecordProjection] {
        guard let noteID = note.workspaceSnapshot?.stableIdentity.resolvedID else {
            return []
        }
        return (researchController.records?.functionRuns ?? [])
            .filter { $0.snapshot.request.target.noteID == noteID }
            .sorted {
                if $0.snapshot.preparedAt != $1.snapshot.preparedAt {
                    return $0.snapshot.preparedAt > $1.snapshot.preparedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private var dialogueSection: some View {
        historySection("Dialogue", systemImage: "bubble.left.and.bubble.right") {
            if dialogue.isEmpty {
                emptyText("No researcher instructions have included this note.")
            } else {
                ForEach(dialogue) { entry in
                    let isExpanded = expandedDialogueEntryIDs.contains(entry.id)
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            if isExpanded {
                                expandedDialogueEntryIDs.remove(entry.id)
                            } else {
                                expandedDialogueEntryIDs.insert(entry.id)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 12)
                                    .accessibilityHidden(true)
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Dialogue from \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                        .accessibilityHint(isExpanded ? "Collapses this Dialogue entry" : "Expands this Dialogue entry")
                        .accessibilityIdentifier("scholium.dialogue.entryDisclosure")

                        if isExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                        DialogueTurnRow(
                            id: entry.id,
                            participant: "Researcher",
                            role: "Initial Comment",
                            scope: "Overall",
                            text: entry.instruction,
                            createdAt: entry.createdAt,
                            systemImage: "person"
                        )
                        if let checkpointID = entry.checkpointID {
                            Text("Checkpoint: Before Agent Work — \(checkpointID.uuidString.prefix(8))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if let destination = entry.requestedDestination {
                            LabeledContent("Requested Destination") {
                                Text(destination)
                                    .multilineTextAlignment(.trailing)
                                    .textSelection(.enabled)
                            }
                        }
                        DisclosureGroup("Selected Notes (\(entry.selectedNotes.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(entry.selectedNotes) { selectedNote in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(selectedNote.title)
                                            .font(.subheadline.weight(.medium))
                                        Text("\(selectedNote.vaultName) — \(selectedNote.relativePath)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                        if let kind = selectedNote.kind {
                                            Text("Kind: \(kind)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                        if let linkedNoteSummary = entry.linkedNoteSummary {
                            DisclosureGroup("Linked-Note Context") {
                                Text(linkedNoteSummary)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .padding(.top, 3)
                            }
                        }
                        if !entry.includedComments.isEmpty {
                            Divider()
                            Text("Included Comments")
                                .font(.subheadline.weight(.semibold))
                            ForEach(entry.includedComments) { includedComment in
                                VStack(alignment: .leading, spacing: 3) {
                                    let sourceNote = includedComment.note
                                    Text(sourceNote.title)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(sourceNote.vaultName) — \(sourceNote.relativePath)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    Text("Note ID: \(sourceNote.noteID.uuidString)")
                                        .font(ScholiumTypography.swiftUIMonospaceFont(
                                            size: 10,
                                            relativeTo: .caption
                                        ))
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                    Text(includedComment.comment.text)
                                        .textSelection(.enabled)
                                    Text(
                                        "Lines \(includedComment.comment.anchor.line)–\(includedComment.comment.anchor.endLine)"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                        let chronologicalTurns = entry.chronologicalTurns
                        if !chronologicalTurns.isEmpty {
                            Divider()
                            Text("Follow-up Exchange")
                                .font(.subheadline.weight(.semibold))
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(chronologicalTurns) { turn in
                            switch turn {
                            case .researcher(let comment):
                                DialogueTurnRow(
                                    id: comment.id,
                                    participant: "Researcher",
                                    role: "Follow-up Comment",
                                    scope: dialogueScope(
                                        noteID: comment.noteID,
                                        commentID: comment.commentID,
                                        in: entry
                                    ),
                                    text: comment.text,
                                    createdAt: comment.createdAt,
                                    systemImage: "person"
                                )
                            case .agent(let reply):
                                DialogueTurnRow(
                                    id: reply.id,
                                    participant: reply.agentName.isEmpty ? "Agent" : reply.agentName,
                                    role: "Agent Response",
                                    scope: dialogueScope(
                                        noteID: reply.noteID,
                                        commentID: reply.commentID,
                                        in: entry
                                    ),
                                    text: reply.text,
                                    createdAt: reply.createdAt,
                                    systemImage: "sparkles"
                                )
                            }
                        }
                        if !entry.generatedPrompt.isEmpty {
                            DisclosureGroup("Legacy Copied Prompt") {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(entry.generatedPrompt)
                                    .font(ScholiumTypography.swiftUIMonospaceFont(
                                        size: 11,
                                        relativeTo: .caption
                                    ))
                                    .textSelection(.enabled)
                                Button {
                                    do {
                                        try context.copyText(entry.generatedPrompt)
                                        context.notify("Instructions copied")
                                    } catch {
                                        errorMessage = error.localizedDescription
                                    }
                                } label: {
                                    Label("Copy Legacy Instructions", systemImage: "doc.on.doc")
                                }
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                            }
                        }
                        HStack {
                            Button {
                                pendingDialogueSheet = .followUp(entry)
                            } label: {
                                Label("Add Follow-up Comment…", systemImage: "plus.bubble")
                            }
                            .accessibilityIdentifier("scholium.dialogue.addFollowUp")

                            Button {
                                pendingDialogueSheet = .response(entry)
                            } label: {
                                Label("Record Agent Response…", systemImage: "bubble.left.and.bubble.right")
                            }
                            .accessibilityIdentifier("scholium.dialogue.recordResponse")
                        }
                        .controlSize(.small)
                            }
                            .padding(.leading, 19)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("scholium.noteHistory.dialogueSection")
    }

    private func dialogueScope(
        noteID: UUID?,
        commentID: UUID?,
        in entry: DialogueEntry
    ) -> String {
        if let commentID,
           let included = entry.includedComments.first(where: { $0.comment.id == commentID }) {
            return "Comment in \(included.note.title)"
        }
        if let noteID,
           let selected = entry.selectedNotes.first(where: { $0.noteID == noteID }) {
            return selected.title
        }
        return "Overall"
    }

    private var critiqueSection: some View {
        historySection("Critique", systemImage: "sparkles") {
            if let critique {
                if note.relativePath != critique.critiqueRelativePath {
                    Button {
                        context.openNote(critique.critiqueRelativePath)
                    } label: {
                        Label("Open Critique", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.link)
                }

                Button {
                    context.openNote(critique.workRelativePath)
                } label: {
                    Label("Open Target Work", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.link)

                let currentTargetSHA = context.documentRevisions[critique.workRelativePath]?.sha256
                let isStale = currentTargetSHA.map { $0 != critique.targetFingerprint.sha256 } ?? true
                Label(
                    isStale ? "Targets an earlier Work version" : "Targets the current Work version",
                    systemImage: isStale ? "clock.badge.exclamationmark" : "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(isStale ? .orange : .secondary)

                Text("Target SHA-256 \(critique.targetFingerprint.sha256.prefix(12))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !critique.rounds.isEmpty {
                    DisclosureGroup("Request Rounds (\(critique.rounds.count))") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(critique.rounds.reversed()) { round in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(round.scope.rawValue) — \(round.requestedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.subheadline)
                                    HStack(spacing: 5) {
                                        Text("SHA-256 \(round.targetFingerprint.sha256.prefix(12))…")
                                        if let checkpointID = round.checkpointID {
                                            Text("— Before Agent Work \(checkpointID.uuidString.prefix(8))")
                                        }
                                    }
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.top, 5)
                    }
                }
            } else {
                emptyText("No Critique is associated with this Work.")
            }
        }
    }

    private var checkpointSection: some View {
        historySection("Checkpoint Versions", systemImage: "externaldrive.badge.timemachine") {
            if checkpoints.isEmpty {
                emptyText("No retained Triptych checkpoint contains this note.")
            } else {
                Picker("Checkpoint", selection: $selectedCheckpoint) {
                    Text("Select a checkpoint").tag(Optional<TriptychCheckpoint>.none)
                    ForEach(checkpoints) { checkpoint in
                        Text("\(checkpoint.name) — \(checkpoint.createdAt.formatted(date: .abbreviated, time: .shortened))")
                            .tag(Optional(checkpoint))
                    }
                }
                if let checkpointSource {
                    Picker("Checkpoint View", selection: $checkpointPresentation) {
                        Text("Compare").tag(CheckpointPresentation.compare)
                        Text("Captured Source").tag(CheckpointPresentation.capturedSource)
                    }
                    .pickerStyle(.segmented)

                    switch checkpointPresentation {
                    case .compare:
                        CheckpointSourceComparison(
                            currentSource: note.rawContent,
                            checkpointSource: checkpointSource,
                            isCompact: presentation == .trailing
                        )
                    case .capturedSource:
                        GroupBox("Captured Source") {
                            ScrollView([.vertical, .horizontal]) {
                                Text(checkpointSource)
                                    .font(ScholiumTypography.swiftUIMonospaceFont(
                                        size: ScholiumTypography.exactSourcePointSize,
                                        relativeTo: .body
                                    ))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(minHeight: 160, maxHeight: 260)
                        }
                    }
                }
            }
        }
    }

    private func historySection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
        }
    }

    private func emptyText(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func reload() async {
        isLoading = true
        review = context.currentReview(note.relativePath)
        do {
            async let loadedDialogue = context.loadDialogue(note.relativePath)
            async let loadedCritique = context.loadCritique(note.relativePath)
            async let loadedCheckpoints = context.loadCheckpoints(note.relativePath)
            dialogue = await loadedDialogue
            critique = await loadedCritique
            checkpoints = try await loadedCheckpoints
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func restore(_ checkpoint: TriptychCheckpoint) {
        isRestoring = true
        Task {
            do {
                try await context.restoreNote(note.relativePath, checkpoint.id)
                context.notify("Restored \(note.displayName) from \(checkpoint.name)")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRestoring = false
            }
        }
    }
}

private enum CheckpointPresentation: Hashable {
    case compare
    case capturedSource
}

private struct CheckpointSourceComparison: View {
    let currentSource: String
    let checkpointSource: String
    let isCompact: Bool

    var body: some View {
        if currentSource == checkpointSource {
            ContentUnavailableView(
                "No Changes",
                systemImage: "equal.circle",
                description: Text("The current note matches the selected checkpoint.")
            )
            .frame(minHeight: 150)
        } else {
            Group {
                if isCompact {
                    VStack(spacing: 10) {
                        sourceColumn("Checkpoint", source: checkpointSource)
                        sourceColumn("Current", source: currentSource)
                    }
                } else {
                    HSplitView {
                        sourceColumn("Checkpoint", source: checkpointSource)
                        sourceColumn("Current", source: currentSource)
                    }
                }
            }
            .frame(minHeight: 220, maxHeight: 320)
            .accessibilityLabel("Checkpoint and current source comparison")
        }
    }

    private func sourceColumn(_ title: String, source: String) -> some View {
        GroupBox(title) {
            ScrollView([.vertical, .horizontal]) {
                Text(source)
                    .font(ScholiumTypography.swiftUIMonospaceFont(
                        size: 11,
                        relativeTo: .caption
                    ))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
        }
        .frame(minWidth: isCompact ? 0 : 300, maxWidth: .infinity)
    }
}

private struct DialogueTurnRow: View {
    let id: UUID
    let participant: String
    let role: String
    let scope: String
    let text: String
    let createdAt: Date
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label(participant, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(scope)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .textSelection(.enabled)
            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scholium.dialogue.turn.\(id.uuidString)")
    }
}

private enum ManualDialogueTarget: Hashable, Identifiable {
    case overall
    case note(UUID)
    case comment(UUID)

    var id: String {
        switch self {
        case .overall: "overall"
        case .note(let id): "note:\(id.uuidString)"
        case .comment(let id): "comment:\(id.uuidString)"
        }
    }
}

private struct ManualDialogueFollowUpView: View {
    @Environment(\.dismiss) private var dismiss

    let controller: ResearchController
    let entry: DialogueEntry
    let onSaved: (DialogueEntry) -> Void

    @State private var text = ""
    @State private var target: ManualDialogueTarget = .overall
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var targetOptions: [ManualDialogueTarget] {
        [.overall]
            + entry.selectedNotes.map { .note($0.noteID) }
            + entry.includedComments.map { .comment($0.comment.id) }
    }

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "plus.bubble")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Follow-up Comment")
                        .font(.title2.weight(.semibold))
                    Text("Continue the scholarly exchange without changing the selected notes or creating agent instructions.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            Form {
                Picker("Comment Applies To", selection: $target) {
                    ForEach(targetOptions) { option in
                        Text(dialogueTargetLabel(option, in: entry)).tag(option)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Comment") {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .padding(5)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .accessibilityLabel("Follow-up Comment")
                        .accessibilityIdentifier("scholium.dialogue.followUpText")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Comment") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("scholium.dialogue.saveFollowUp")
            }
            .padding(16)
        }
        .frame(minWidth: 0, idealWidth: 640, minHeight: 430, idealHeight: 500)
        .alert("Could Not Add Follow-up Comment", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        guard canSave else { return }
        let targetIDs = dialogueTargetIDs(target, in: entry)
        isSaving = true
        Task {
            do {
                let updated = try await controller.appendDialogueFollowUpComment(
                    DialogueFollowUpComment(
                        text: text,
                        noteID: targetIDs.noteID,
                        commentID: targetIDs.commentID
                    ),
                    to: entry.id
                )
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct ManualDialogueReplyView: View {
    @Environment(\.dismiss) private var dismiss

    let controller: ResearchController
    let entry: DialogueEntry
    let onSaved: (DialogueEntry) -> Void

    @State private var agentName = "Agent"
    @State private var text = ""
    @State private var target: ManualDialogueTarget = .overall
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var targetOptions: [ManualDialogueTarget] {
        [.overall]
            + entry.selectedNotes.map { .note($0.noteID) }
            + entry.includedComments.map { .comment($0.comment.id) }
    }

    private var canSave: Bool {
        !agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record Agent Response")
                        .font(.title2.weight(.semibold))
                    Text("Store a response returned outside the local Scholium CLI in this Dialogue entry.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            Form {
                TextField("Agent Name", text: $agentName)
                    .accessibilityIdentifier("scholium.dialogue.agentName")
                Picker("Reply Addresses", selection: $target) {
                    ForEach(targetOptions) { option in
                        Text(dialogueTargetLabel(option, in: entry)).tag(option)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Response") {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .padding(5)
                        .background(
                            Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .accessibilityLabel("Agent response")
                        .accessibilityIdentifier("scholium.dialogue.responseText")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Record Response") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("scholium.dialogue.saveResponse")
            }
            .padding(16)
        }
        .frame(minWidth: 0, idealWidth: 640, minHeight: 430, idealHeight: 500)
        .alert("Could Not Record Agent Response", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Keep Editing", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        guard canSave else { return }
        let targetIDs = dialogueTargetIDs(target, in: entry)

        isSaving = true
        Task {
            do {
                let updated = try await controller.appendDialogueReply(
                    DialogueReply(
                        agentName: agentName,
                        text: text,
                        noteID: targetIDs.noteID,
                        commentID: targetIDs.commentID
                    ),
                    to: entry.id
                )
                onSaved(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private func dialogueTargetLabel(
    _ target: ManualDialogueTarget,
    in entry: DialogueEntry
) -> String {
    switch target {
    case .overall:
        return "Overall instruction"
    case .note(let noteID):
        return entry.selectedNotes.first(where: { $0.noteID == noteID })
            .map { "Note: \($0.title)" }
            ?? "Selected note"
    case .comment(let commentID):
        guard let included = entry.includedComments.first(where: {
            $0.comment.id == commentID
        }) else { return "Researcher Comment" }
        return "Comment in \(included.note.title): \(included.comment.text)"
    }
}

private func dialogueTargetIDs(
    _ target: ManualDialogueTarget,
    in entry: DialogueEntry
) -> (noteID: UUID?, commentID: UUID?) {
    switch target {
    case .overall:
        return (nil, nil)
    case .note(let id):
        return (id, nil)
    case .comment(let id):
        let noteID = entry.includedComments.first(where: {
            $0.comment.id == id
        })?.note.noteID
        return (noteID, id)
    }
}

// MARK: - Preview

#Preview {
    let controller = DocumentController()
    let note = WindowDocumentLocation.unclassified(NoteDocument(
        relativePath: "topics/consciousness.md",
        rawContent: "---\ntitle: Consciousness\n---\n\n# Consciousness\n\nThis is a test note."
    ))
    let state = DocumentFeatureState(
        notes: [note],
        selectedDocumentPath: note.relativePath,
        ordinarySearchScope: .triptych,
        currentVaultID: nil,
        vaultRole: .other,
        locationScope: .unclassified,
        noteIdentityByPath: [:],
        documentRevisions: [note.relativePath: note.document.fingerprint],
        workspaceCatalog: nil,
        propertiesConfiguration: nil,
        reviewRecord: nil,
        reviewDisplayState: .notReviewed,
        changedSinceReview: false,
        canComment: false,
        canEdit: false,
        documentTextScale: 1,
        readCSS: "",
        livePreviewCSS: "",
        initialScrollFraction: 0,
        requestedPresentationMode: nil,
        pendingSourceLine: nil,
        isCompactLayout: false,
        noteHistoryVisible: false,
        researchInspectorVisible: false,
        identityAmbiguity: nil,
        pendingIdentityRebinding: nil,
        identityMigrationFailureMessage: nil,
        isResolvingIdentity: false,
        researchStrip: ResearchStripPresentation(items: [], activeFunction: nil)
    )
    let actions = DocumentFeatureActions(
        requestIdentityResolution: {},
        retryIdentityRecovery: {},
        beginSearch: { _ in },
        clearRequestedPresentationMode: {},
        registerEditorFlush: { _, _, _, _ in },
        unregisterEditorFlush: { _ in },
        clearPendingSourceLine: {},
        requestComments: { _, _ in },
        rememberScrollPosition: { _ in },
        openInternalLink: { _ in },
        openExternalURL: { _ in },
        enterCSSSafeMode: { _ in },
        rememberPresentationMode: { _ in },
        setPendingSourceLine: { _ in },
        editProperties: {},
        openResearchFunction: { _, _ in },
        setNoteHistoryVisible: { _ in },
        setResearchInspectorVisible: { _ in },
        notify: { _, _ in }
    )
    let critiqueProvenanceContext = CritiqueProvenanceContext(
        availableNotes: [note],
        documentRevisions: [note.relativePath: note.document.fingerprint],
        loadAssociation: { _ in nil },
        openTarget: { _ in },
        openFinding: { _, _ in }
    )
    NoteContentView(
        controller: controller,
        target: .unavailable(relativePath: note.relativePath),
        note: note,
        documentSession: DocumentSessionModel(key: nil),
        state: state,
        actions: actions,
        critiqueProvenanceContext: critiqueProvenanceContext
    )
}

// MARK: - RoundedCorner Shape (for NSTabView-style folder tabs)

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: RectCorner

    struct RectCorner: OptionSet {
        let rawValue: Int
        static let topLeft = RectCorner(rawValue: 1 << 0)
        static let topRight = RectCorner(rawValue: 1 << 1)
        static let bottomLeft = RectCorner(rawValue: 1 << 2)
        static let bottomRight = RectCorner(rawValue: 1 << 3)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)

        // Top-left corner
        if corners.contains(.topLeft) {
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                       radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX - (corners.contains(.topRight) ? r : 0), y: rect.minY))

        // Top-right corner
        if corners.contains(.topRight) {
            path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                       radius: r, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
