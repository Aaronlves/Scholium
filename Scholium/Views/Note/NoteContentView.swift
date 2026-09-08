import AppKit
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

enum DocumentNotificationKind {
    case information
    case error
}

private enum ImageAttachmentSelectionMode: Equatable {
    case importFile
    case index
}

enum DocumentIntegrityPresentation: Hashable {
    case autosaveFailed(message: String, canRetry: Bool)
    case conflict

    static func resolve(
        editError: String?,
        conflict: DocumentConflictSnapshot?,
        canRetrySave: Bool
    ) -> Self? {
        if conflict != nil { return .conflict }
        guard let editError, !editError.isEmpty else { return nil }
        return .autosaveFailed(message: editError, canRetry: canRetrySave)
    }

    var title: String {
        switch self {
        case .autosaveFailed:
            String(localized: "Autosave Failed", table: "Localizable", bundle: .module)
        case .conflict:
            String(localized: "Autosave Paused", table: "Localizable", bundle: .module)
        }
    }

    var detail: String {
        switch self {
        case .autosaveFailed(let message, _):
            String(
                localized: "Your edits are still available. \(message)",
                table: "Localizable",
                bundle: .module
            )
        case .conflict:
            String(
                localized: "This file changed outside Scholium. Your edits are still available.",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    var kind: ScholiumDocumentStatusKind {
        switch self {
        case .autosaveFailed: .destructive
        case .conflict: .attention
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .autosaveFailed: "scholium.documentStatus.autosaveFailed"
        case .conflict: "scholium.documentStatus.conflict"
        }
    }

    var announcement: String {
        switch self {
        case .autosaveFailed(_, let canRetry):
            if canRetry {
                return String(
                    localized: "\(title). \(detail) Retry Save is available.",
                    table: "Localizable",
                    bundle: .module
                )
            }
            return "\(title). \(detail)"
        case .conflict:
            return String(
                localized: "\(title). \(detail) Compare Changes is available.",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}

struct DocumentFeatureState {
    let notes: [WindowDocumentLocation]
    let selectedDocumentPath: String?
    let ordinarySearchScope: SearchPresentationScope
    let currentVaultID: UUID?
    let vaultRole: VaultRole
    let noteIdentityByPath: [String: UUID]
    let documentRevisions: [String: DocumentFingerprint]
    let workspaceCatalog: WorkspaceCatalogSnapshot?
    let canEdit: Bool
    let documentTextScale: Double
    let appearanceCSS: String
    let readCSS: String
    let livePreviewCSS: String
    let initialScrollFraction: Double
    let requestedPresentationMode: NotePresentationMode?
    let sourceLocationRequest: DocumentSourceLocationRequest?
    let identityAmbiguity: NoteIdentityAmbiguity?
    let pendingIdentityRebinding: NoteIdentityPendingRebinding?
    let identityMigrationFailureMessage: String?
    let isResolvingIdentity: Bool
}

struct DocumentFeatureActions {
    var askAgent: @MainActor (AgentChatSelectionInquiry) -> Void = { _ in }
    let requestIdentityResolution: @MainActor () -> Void
    let retryIdentityRecovery: @MainActor () async -> Void
    let beginSearch: @MainActor (SearchInvocation) -> Void
    let clearRequestedPresentationMode: @MainActor () -> Void
    let consumeSourceLocation: @MainActor (UUID) -> Void
    let rememberScrollPosition: @MainActor (Double) -> Void
    let openInternalLink: @MainActor (String) -> Void
    let openExternalURL: @MainActor (URL) -> Void
    let enterCSSSafeMode: @MainActor (String) -> Void
    let rememberPresentationMode: @MainActor (NotePresentationMode) -> Void
    let setSidebarVisible: @MainActor (Bool) -> Void
    let setResearchInspectorVisible: @MainActor (Bool) -> Void
    let openingDocumentPresentationDidComplete: @MainActor () -> Void
    let renameNote: @MainActor (
        WindowDocumentLocation,
        String,
        String
    ) async throws -> String
    let notify: @MainActor (String, DocumentNotificationKind) -> Void
}

// MARK: - Note Content Container

struct DocumentFeatureView: View {
    @ObservedObject private var controller: DocumentController
    let documentInformation: DocumentInformationProjection
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions

    init(
        controller: DocumentController,
        documentInformation: DocumentInformationProjection,
        state: DocumentFeatureState,
        actions: DocumentFeatureActions
    ) {
        self.controller = controller
        self.documentInformation = documentInformation
        self.state = state
        self.actions = actions
    }

    var body: some View {
        if let selectedDocumentPath = state.selectedDocumentPath,
           let note = state.notes.first(where: { $0.relativePath == selectedDocumentPath }) {
            let selectedWorkspaceKey = controller.activeDocument.flatMap { descriptor in
                descriptor.reference.relativePath == selectedDocumentPath
                    ? descriptor.sessionKey
                    : nil
            }
            let projectedWorkspaceKey = state.currentVaultID.flatMap { vaultID in
                state.noteIdentityByPath[note.relativePath].map { noteID in
                    DocumentSessionKey(vaultID: vaultID, noteID: noteID)
                }
            }
            if let key = selectedWorkspaceKey ?? projectedWorkspaceKey {
                NoteContentView(
                    controller: controller,
                    documentInformation: documentInformation,
                    target: .workspace(key),
                    note: note,
                    documentSession: controller.session(for: key),
                    state: state,
                    actions: actions
                )
                .id(key)
            } else {
                DocumentSessionFallback(
                    note: note,
                    controller: controller,
                    documentInformation: documentInformation,
                    target: .unavailable(
                        vaultID: note.vaultID,
                        relativePath: note.relativePath
                    ),
                    state: state,
                    actions: actions
                )
                    .id(selectedDocumentPath)
            }
        }
    }
}

private struct DocumentSessionFallback: View {
    let note: WindowDocumentLocation
    let controller: DocumentController
    let documentInformation: DocumentInformationProjection
    let target: DocumentEditingTarget
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions

    var body: some View {
        NoteContentView(
            controller: controller,
            documentInformation: documentInformation,
            target: target,
            note: note,
            documentSession: controller.session(for: target),
            state: state,
            actions: actions
        )
    }
}

struct NoteContentView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @ObservedObject private var controller: DocumentController
    @ObservedObject private var documentSession: DocumentSessionModel
    let documentInformation: DocumentInformationProjection
    let target: DocumentEditingTarget
    let note: WindowDocumentLocation
    let state: DocumentFeatureState
    let actions: DocumentFeatureActions
    @StateObject private var documentFind = DocumentFindPresentationModel()
    @StateObject private var reviewDocumentStatistics = ReviewDocumentStatisticsModel()
    @State private var isInsertingImage = false
    @State private var announcedUnavailableIndexedImages: Set<String> = []
    @State private var indexedImageAvailabilityGeneration = 0

    init(
        controller: DocumentController,
        documentInformation: DocumentInformationProjection,
        target: DocumentEditingTarget,
        note: WindowDocumentLocation,
        documentSession: DocumentSessionModel,
        state: DocumentFeatureState,
        actions: DocumentFeatureActions
    ) {
        self.controller = controller
        self.documentInformation = documentInformation
        _documentSession = ObservedObject(wrappedValue: documentSession)
        self.target = target
        self.note = note
        self.state = state
        self.actions = actions
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
        documentSession.presentationMode
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
    private var documentIntegrityPresentation: DocumentIntegrityPresentation? {
        DocumentIntegrityPresentation.resolve(
            editError: editError,
            conflict: conflict,
            canRetrySave: canRetrySave
        )
    }
    private var showConflictComparison: Bool {
        get { documentSession.showConflictComparison }
        nonmutating set { documentSession.showConflictComparison = newValue }
    }
    private var editorSession: MarkdownEditorSession { documentSession.editorSession }

    private var documentAttachmentTarget: NoteDocumentAttachmentTarget? {
        guard case .workspace(let key) = target,
              key.vaultID == note.vaultID else { return nil }
        return NoteDocumentAttachmentTarget(
            noteID: key.noteID,
            vaultID: key.vaultID,
            relativePath: note.relativePath
        )
    }

    var body: some View {
        AnyView(VStack(spacing: 0) {
            if let ambiguity = state.identityAmbiguity {
                IdentityAmbiguityNotice(ambiguity: ambiguity) {
                    actions.requestIdentityResolution()
                }
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            } else if let pending = state.pendingIdentityRebinding {
                IdentityMigrationNotice(
                    rebinding: pending,
                    message: state.identityMigrationFailureMessage,
                    isRetrying: state.isResolvingIdentity
                ) {
                    await actions.retryIdentityRecovery()
                }
                .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }


            if let presentation = documentIntegrityPresentation {
                ScholiumDocumentStatusNotice(
                    presentation.title,
                    detail: presentation.detail,
                    kind: presentation.kind
                ) {
                    documentIntegrityActions(presentation)
                }
                .accessibilityIdentifier(presentation.accessibilityIdentifier)
                .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
            }

            documentBodySurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay {
                DocumentFindOverlay(model: documentFind, allowsReplacement: isEditing)
            }
        }
        .scholiumSurface(.document)
        .focusedSceneValue(
            \.scholiumEditorActions,
            ScholiumFocusedEditorActions(
                documentID: isEditing ? editorSession.documentID : note.relativePath,
                isComposing: isEditing && editorSession.context?.composing == true,
                allowsReplace: isEditing,
                isAvailable: { command in
                    isEditing && editorSession.context?.availableCommands.contains(command) == true
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
                presentFind: documentFind.present,
                presentReplace: documentFind.presentReplacement,
                findNext: documentFind.next,
                findPrevious: documentFind.previous,
                useSelectionForFind: useSelectionForDocumentFind,
                importImage: requestImageImport,
                indexImage: requestImageIndex,
                canAttachDocument: documentAttachmentTarget != nil
                    && !documentSession.isAttachingDocument,
                attachDocumentCopy: {
                    requestDocumentAttachment(.copyIntoTriptych)
                },
                referenceOriginalDocument: {
                    requestDocumentAttachment(.referenceOriginal)
                },
                canEditFrontmatter: editingIsAvailable,
                goToFrontmatter: goToFrontmatter
            )
        ))
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
                .scholiumButtonStyle(.automatic)
            }
        }
        .task(id: documentIntegrityPresentation) {
            guard let presentation = documentIntegrityPresentation else { return }
            AccessibilityNotification.Announcement(presentation.announcement).post()
        }
        .onChange(of: state.requestedPresentationMode) { _, requested in
            guard let requested else { return }
            selectPresentationMode(requested)
            actions.clearRequestedPresentationMode()
        }
        .task(id: sourceLocationExecutionID) { await consumePendingSourceLocation() }
        .onAppear {
            controller.observe(documentSession)
            applyPreparedPresentationModeIfAvailable()
            consumePendingPresentationRequest()
            updateReviewDocumentStatistics(selection: nil)
            documentInformation.activate(documentInformationDocumentID)
            publishDocumentInformation()
        }
        .onChange(of: currentDocumentStatistics) { _, _ in publishDocumentInformation() }
        .onChange(of: isEditing) { _, _ in publishDocumentInformation() }
        .onChange(of: note.rawContent) { _, _ in publishDocumentInformation() }
        .onChange(of: editorSession.outlineHeadings) { _, _ in publishDocumentInformation() }
        .onChange(of: editorSession.currentHeadingLine) { _, _ in publishDocumentInformation() }
        .onChange(of: documentInformationDocumentID) { previous, _ in
            documentInformation.clear(ifCurrent: previous)
            documentInformation.activate(documentInformationDocumentID)
            publishDocumentInformation()
        }
        .onDisappear {
            documentInformation.clear(ifCurrent: documentInformationDocumentID)
        }
        .onChange(of: editingIsAvailable) { _, available in
            // Window restoration publishes the selected note before stable
            // identity recovery necessarily finishes. Keep the edit gate
            // intact, then apply the committed mode as soon as editing becomes
            // available instead of leaving the document in the default Read
            // mode for the rest of the session.
            if available { applyPreparedPresentationModeIfAvailable() }
        }
        .onChange(of: isEditing) { _, _ in
            documentSession.readSelection = nil
            updateReviewDocumentStatistics(selection: nil)
            documentFind.refresh()
            focusEditorIfPresented()
            if !isEditing,
               documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256 {
                markReadPresentationReady(documentID: note.relativePath)
            }
        }
        .onChange(of: editorSession.presentedMode) { _, presentedMode in
            focusEditorIfPresented()
            if let presentedMode {
                PerformanceProbe.shared.markEditorModeAcknowledged(
                    documentID: note.relativePath,
                    mode: presentedMode
                )
                PerformanceProbe.shared.markEditorModeReady(
                    documentID: note.relativePath,
                    mode: presentedMode
                )
            }
        }
        .onChange(of: editorSession.isLoaded) { _, loaded in
            guard loaded else { return }
            focusEditorIfPresented()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            indexedImageAvailabilityGeneration &+= 1
        }
        .task(id: readProjectionTaskIdentity) {
            PerformanceProbe.shared.markReadTaskStarted(
                documentID: note.relativePath
            )
            documentSession.prepareReadProjection(
                for: noteFingerprint.sha256
            )
            updateReviewDocumentStatistics(selection: nil)
            let source = note.rawContent
            let relativePath = note.relativePath
            let fingerprint = noteFingerprint
            if !isEditing {
                documentSession.readSelection = nil
                documentSession.requestScrollRestore(
                    fingerprint: fingerprint.sha256,
                    reason: .documentLoad
                )
            }
            if note.document.hasExactEmptyBody {
                // A header-only Note is already a complete Review state. Do
                // not start WebKit merely to render an exact empty body or
                // imply that source loading is still in progress.
                renderedReadHTML = ""
                renderedReadFingerprint = fingerprint.sha256
                documentSession.renderedReadReadyFingerprint = fingerprint.sha256
                if !isEditing {
                    markReadPresentationReady(documentID: relativePath)
                }
                return
            }
            let html = await controller.readProjectionHTML(
                target: target,
                relativePath: relativePath,
                source: source,
                fingerprint: fingerprint,
                workspaceID: state.currentVaultID,
                semantic: note.workspaceSnapshot?.cachedSemanticDocument
            )
            guard !Task.isCancelled, fingerprint == noteFingerprint else { return }
            PerformanceProbe.shared.markReadHTMLReady(documentID: relativePath)
            renderedReadHTML = html
            renderedReadFingerprint = fingerprint.sha256
        }
        .task(id: indexedImageAvailabilityTaskIdentity) {
            await checkIndexedImageAvailability()
        }
        .task(id: documentAttachmentTaskIdentity) {
            await loadDocumentAttachments()
        }
        .task(id: previewTaskIdentity) {
            await rebuildPreviewCatalog()
        }
        .task(id: documentFind.request) {
            guard let request = documentFind.request else { return }
            if case .clear = request.operation {
                if isEditing {
                    await editorSession.clearDocumentFind()
                }
                return
            }
            guard isEditing, let query = request.editorQuery else { return }
            do {
                let result = try await editorSession.performDocumentFind(query)
                documentFind.accept(result, for: request.id)
            } catch {
                documentFind.fail(error, for: request.id)
            }
        }
        .onDisappear {
        }
    }

    @ViewBuilder
    private func documentIntegrityActions(
        _ presentation: DocumentIntegrityPresentation
    ) -> some View {
        switch presentation {
        case .autosaveFailed(_, let canRetry):
            if canRetry {
                Button("Retry Save") {
                    controller.retrySave(session: documentSession, target: target)
                }
                .scholiumActivationPointer()
                .controlSize(.small)
            }
        case .conflict:
            Button("Compare Changes") {
                showConflictComparison = true
            }
            .scholiumActivationPointer()
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var readProjectionTaskIdentity: String {
        "\(note.relativePath):\(noteFingerprint.sha256)"
    }

    private var previewTaskIdentity: String {
        let generation = state.workspaceCatalog?.graph?.generation ?? -1
        return "\(state.currentVaultID?.uuidString ?? "unavailable"):\(noteFingerprint.sha256):\(generation):\(presentationMode.rawValue):\(hasUnsavedChanges)"
    }

    @MainActor
    private func rebuildPreviewCatalog() async {
        guard let vaultID = state.currentVaultID,
              let graph = state.workspaceCatalog?.graph,
              state.selectedDocumentPath == note.relativePath,
              presentationMode != .source,
              !hasUnsavedChanges else {
            documentSession.previewCatalog = nil
            return
        }
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: note.relativePath)
        let expectedFingerprint = noteFingerprint
        let expectedGeneration = graph.generation
        do {
            let catalog = try await controller.documentPreviewCatalog(
                source: sourceID,
                sourceFingerprint: expectedFingerprint,
                graphGeneration: expectedGeneration
            )
            guard !Task.isCancelled,
                  noteFingerprint == expectedFingerprint,
                  state.workspaceCatalog?.graph?.generation == expectedGeneration,
                  !hasUnsavedChanges else { return }
            documentSession.previewCatalog = catalog
        } catch {
            guard !Task.isCancelled else { return }
            documentSession.previewCatalog = nil
        }
    }

    private var editingIsAvailable: Bool {
        state.canEdit
    }

    private var noteFingerprint: DocumentFingerprint {
        state.documentRevisions[note.relativePath] ?? DocumentFingerprint(content: note.rawContent)
    }

    private var bodyEditor: AnyView {
        AnyView(MarkdownEditorWebView(
            session: editorSession,
            documentID: editorSession.bridgeDocumentID,
            documentTitle: note.displayName,
            performanceDocumentID: note.relativePath,
            source: editingSource,
            mode: documentSession.retainedEditorMode,
            presentationCSS: documentPresentationCSS,
            userCSS: state.livePreviewCSS,
            requiresMathRuntime: MarkdownEditorWebView.requiresMathRuntime(
                source: editingSource,
                linkPreviews: documentSession.previewCatalog?.links ?? []
            ),
            linkCompletionQuery: queryEditorLinkCompletions,
            linkPreviews: documentSession.previewCatalog?.links ?? [],
            initialScrollFraction: state.initialScrollFraction,
            initialScrollAnchor: editorScrollAnchor,
            onDocumentActivity: {
                controller.editorSourceDidChange(
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
            onRequestFind: handleDocumentFindShortcut,
            onRequestDocumentTitleRename: { expectedTitle, requestedTitle in
                try await actions.renameNote(note, expectedTitle, requestedTitle)
            },
            onPasteImage: handlePastedImage,
            onLinkActivation: { target in
                if let url = URL(string: target),
                   let scheme = url.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    actions.openExternalURL(url)
                } else {
                    actions.openInternalLink(target)
                }
            },
            onScrollFractionChange: {
                documentSession.observeScrollFraction($0)
                actions.rememberScrollPosition($0)
            },
            onScrollAnchorChange: { documentSession.observeScrollAnchor($0) },
            onAskAgent: actions.askAgent
        )
        .id(editorSession.viewReconstructionID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1))
    }

    @ViewBuilder
    private var documentBodySurface: some View {
        DocumentEditorHost(
            documentID: editorSession.openingPresentationID.uuidString,
            presentsEditor: isEditing,
            retainsEditor: documentSession.retainsEditorSurface,
            editorIsReady: editorSession.isLoaded
                && !editorSession.opensAtDocumentTitle
                && editorSession.presentedMode == documentSession.activeEditorMode,
            allowsPendingReadRecovery: editorSession.errorMessage != nil
        ) {
            readSurface
        } editor: {
            bodyEditor
        }
        .scholiumSurface(.document)
        .overlay(alignment: .topLeading) {
            if isEditing,
               editorSession.isLoaded,
               let presentedMode = editorSession.presentedMode,
               presentedMode == documentSession.activeEditorMode {
                PerformanceReadyBoundary(
                    generation: "\(noteFingerprint.sha256):\(presentedMode.rawValue)"
                ) {
                    PerformanceProbe.shared.markEditorModeVisible(
                        documentID: note.relativePath,
                        mode: presentedMode
                    )
                    PerformanceProbe.shared.markEditorVisible(
                        documentID: note.relativePath
                    )
                    actions.openingDocumentPresentationDidComplete()
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            if !isEditing,
               (note.document.hasExactEmptyBody
                || documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256) {
                PerformanceReadyBoundary(
                    generation: "read:\(noteFingerprint.sha256)"
                ) {
                    actions.openingDocumentPresentationDidComplete()
                }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var readSurface: some View {
        if documentSession.isEnteringManagedCreation {
            if let error = editorSession.errorMessage {
                managedCreationEditorFailure(error)
            } else {
                // Managed creation never flashes Review or Empty Note while
                // the exact editor waits for its typed mode acknowledgement.
                Color.clear
                    .accessibilityHidden(true)
            }
        } else if note.document.hasExactEmptyBody {
            emptyReviewState
        } else {
            let hasWebProjection = renderedReadFingerprint == noteFingerprint.sha256
                && failedReadFingerprint != noteFingerprint.sha256
            let webProjectionIsReady = hasWebProjection
                && documentSession.renderedReadReadyFingerprint == noteFingerprint.sha256

            ZStack {
                if !webProjectionIsReady {
                    readProjectionPlaceholder
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .layoutPriority(1)
                        .allowsHitTesting(false)
                }

                if hasWebProjection {
                    readDocumentSurface
                        .opacity(webProjectionIsReady ? 1 : 0)
                        .allowsHitTesting(webProjectionIsReady && !isEditing)
                        .accessibilityHidden(!webProjectionIsReady)
                }
            }
        }
    }

    private var emptyReviewState: some View {
        ScholiumContentStateView(
            "Empty Note",
            detail: Text("This note has no body content."),
            indicator: .symbol("doc")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scholium.emptyRenderedReview")
    }

    private func managedCreationEditorFailure(_ error: String) -> some View {
        ScholiumContentStateView(
            "Edit Unavailable",
            detail: Text("The note was created and its exact source is saved. \(error)"),
            indicator: .symbol("exclamationmark.triangle", role: .attention)
        ) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button("Retry Edit") {
                    retryManagedCreationEditor(in: .livePreview)
                }
                .scholiumActivationPointer()
                .keyboardShortcut(.defaultAction)
                Button("Source") {
                    retryManagedCreationEditor(in: .source)
                }
                .scholiumActivationPointer()
            }
        }
        .accessibilityIdentifier("scholium.managedNewNote.editorFailure")
    }

    @ViewBuilder
    private var readProjectionPlaceholder: some View {
        if failedReadFingerprint == noteFingerprint.sha256 {
            ScholiumContentStateView(
                "Review Mode Unavailable",
                detail: Text("Use Source mode while the rendered document is unavailable."),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            )
        } else {
            ScholiumContentStateView(
                "Loading Document…",
                indicator: .progress
            )
        }
    }

    private var readDocumentSurface: some View {
        SafeMarkdownReadWebView(
            documentID: note.relativePath,
            documentTitle: note.displayName,
            fingerprint: noteFingerprint.sha256,
            source: note.rawContent,
            htmlBody: renderedReadHTML,
            presentationCSS: documentPresentationCSS,
            userCSS: state.readCSS,
            configurationRevision: readConfigurationRevision,
            linkPreviews: documentSession.previewCatalog?.links ?? [],
            linkPreviewRevision: readLinkPreviewRevision,
            onLinkClick: {
                actions.openInternalLink($0)
            },
            onOpenExternalURL: actions.openExternalURL,
            onAskAgent: actions.askAgent,
            onSelectionChange: { selection in
                guard !isEditing else { return }
                documentSession.readSelection = selection
                updateReviewDocumentStatistics(selection: selection)
            },
            selectionSurfaceIsActive: !isEditing,
            renderingReadinessIsAcknowledged:
                documentSession.renderedReadReadyFingerprint
                    == noteFingerprint.sha256,
            onRenderingFailure: { reason in
                actions.enterCSSSafeMode(reason)
                failedReadFingerprint = noteFingerprint.sha256
                documentSession.renderedReadReadyFingerprint = ""
            },
            onRenderingLoading: {
                documentSession.renderedReadReadyFingerprint = ""
            },
            onRenderingReady: {
                documentSession.renderedReadReadyFingerprint = noteFingerprint.sha256
                if !isEditing {
                    markReadPresentationReady(documentID: note.relativePath)
                }
            },
            findRequest: isEditing ? nil : documentFind.request,
            onFindResult: { requestID, result in
                switch result {
                case .success(let value):
                    documentFind.accept(value, for: requestID)
                case .failure(let error):
                    documentFind.fail(error, for: requestID)
                }
            },
            observedScrollPosition: documentSession.observedScrollPosition,
            scrollRestoreRequest: documentSession.scrollRestoreRequest,
            onScrollRestoreConsumed: { id, fingerprint in
                documentSession.acknowledgeScrollRestoreRequest(
                    id: id,
                    fingerprint: fingerprint
                )
            },
            onScrollFractionChange: {
                guard !isEditing else { return }
                documentSession.observeScrollFraction($0)
                actions.rememberScrollPosition($0)
            },
            onScrollAnchorChange: {
                guard !isEditing else { return }
                documentSession.observeScrollAnchor($0)
                publishDocumentInformation()
            },
            sourceLocationRequest: isEditing ? nil : currentSourceLocationRequest,
            onSourceRangeUnavailable: { id in
                guard !isEditing, currentSourceLocationRequest?.id == id else { return }
                if editingIsAvailable { selectPresentationMode(.source) }
                else {
                    actions.consumeSourceLocation(id)
                    actions.notify(String(localized: "This passage cannot be selected in Review. Its supplied text remains available in Chat.", bundle: .module), .information)
                }
            },
            onSourceRevisionChanged: { id in
                guard currentSourceLocationRequest?.id == id else { return }
                actions.consumeSourceLocation(id)
                reportChangedSourceLocation()
            },
            onSourceLocationReached: { id in
                guard !isEditing else { return }
                actions.consumeSourceLocation(id)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private func markReadPresentationReady(documentID: String) {
        PerformanceProbe.shared.markReadReady(documentID: documentID)
    }

    private var editorScrollAnchor: EditorScrollAnchor? {
        if let retained = editorSession.retainedScrollAnchor {
            return retained
        }
        let fingerprint = DocumentFingerprint(content: editorSession.checkedSource).sha256
        guard documentSession.scrollAnchor?.sourceFingerprint == fingerprint else { return nil }
        return documentSession.scrollAnchor
    }

    private var documentPresentation: ScholiumDocumentPresentationConfiguration {
        ScholiumDocumentPresentationConfiguration(textScale: state.documentTextScale)
    }

    private var documentPresentationCSS: String {
        documentPresentation.css + "\n" + state.appearanceCSS
    }

    private var readConfigurationRevision: String {
        [
            noteFingerprint.sha256,
            String(note.displayName.hashValue),
            String(state.documentTextScale.bitPattern),
            String(state.appearanceCSS.hashValue),
            String(state.readCSS.hashValue),
        ].joined(separator: ":")
    }

    private var readLinkPreviewRevision: String {
        let previewRevision = documentSession.previewCatalog.map { catalog in
            let targets = catalog.links.map { link in
                "\(link.sourceSpan.utf16LowerBound)-\(link.sourceSpan.utf16UpperBound):"
                    + link.targetFingerprint.sha256
            }.joined(separator: ",")
            return "\(catalog.graphGeneration):\(catalog.sourceFingerprint.sha256):\(targets)"
        } ?? "no-previews"
        return previewRevision
    }

    private var hasUnsavedChanges: Bool {
        documentSession.hasUnsavedChanges
    }

    @MainActor
    private func queryEditorLinkCompletions(
        _ kind: EditorLinkCompletionKind,
        _ query: String
    ) async -> [EditorLinkCompletion] {
        guard let currentVaultID = state.currentVaultID,
              let catalogNotes = state.workspaceCatalog?.notes,
              let generation = state.workspaceCatalog?.graph?.generation else {
            return []
        }
        return await controller.editorLinkCompletions(
            kind: kind,
            matching: query,
            sourcePath: note.relativePath,
            currentVaultID: currentVaultID,
            catalogNotes: catalogNotes,
            graphGeneration: generation
        )
    }

    private var editorIsComposing: Bool {
        isEditing && editorSession.context?.composing == true
    }

    private var currentDocumentStatistics: DocumentStatistics {
        isEditing
            ? editorSession.documentStatistics
            : reviewDocumentStatistics.value
    }

    private var documentInformationDocumentID: DocumentInformationDocumentID {
        DocumentInformationDocumentID(
            vaultID: note.vaultID,
            relativePath: note.relativePath
        )
    }

    private var indexedImageAvailabilityTaskIdentity: String {
        "\(note.relativePath):\(noteFingerprint.sha256):\(indexedImageAvailabilityGeneration)"
    }

    private var documentAttachmentTaskIdentity: String {
        let stableID = documentAttachmentTarget?.noteID.uuidString ?? "unavailable"
        return "\(stableID):\(note.relativePath):\(indexedImageAvailabilityGeneration)"
    }

    @MainActor
    private func loadDocumentAttachments() async {
        guard let expectedTarget = documentAttachmentTarget else {
            documentSession.documentAttachments = []
            return
        }
        try? await controller.refreshDocumentAttachments(for: expectedTarget, session: documentSession)
    }

    private func requestDocumentAttachment(_ mode: DocumentAttachmentSelectionMode) {
        guard let target = documentAttachmentTarget else { return }
        Task { @MainActor in
            defer { if isEditing { editorSession.focusPreferred() } }
            do {
                try await controller.selectDocumentAttachment(mode, for: target,
                    session: documentSession, presenter: fileSelectionPresenter)
            } catch is CancellationError { return }
            catch { actions.notify(error.localizedDescription, .error) }
        }
    }

    @MainActor
    private func checkIndexedImageAvailability() async {
        let source = isEditing ? editingSource : note.rawContent
        guard source.contains("](/") else {
            announcedUnavailableIndexedImages = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(250))
            let unavailable = Set(
                try await controller.unavailableIndexedImagePaths(in: source)
            )
            guard !Task.isCancelled else { return }
            let newlyUnavailable = unavailable.subtracting(
                announcedUnavailableIndexedImages
            )
            announcedUnavailableIndexedImages = unavailable
            guard !newlyUnavailable.isEmpty else { return }
            if newlyUnavailable.count == 1, let path = newlyUnavailable.first {
                actions.notify(
                    String(localized: "Indexed attachment unavailable: \(path)"),
                    .information
                )
            } else {
                actions.notify(
                    String(localized: "\(newlyUnavailable.count) indexed attachments are unavailable."),
                    .information
                )
            }
        } catch is CancellationError {
            return
        } catch {
            // Catalog and local-access health are reported by their owning
            // workflows. A reminder check never blocks or mutates the Note.
        }
    }

    private func updateReviewDocumentStatistics(
        selection: MarkdownReviewSelection?
    ) {
        reviewDocumentStatistics.update(
            markdownSource: note.rawContent,
            revision: noteFingerprint.sha256,
            selection: selection
        )
    }

    private func publishDocumentInformation() {
        documentInformation.publish(currentDocumentStatistics, for: documentInformationDocumentID)
        if isEditing {
            documentInformation.publishOutline(editorSession.outlineHeadings,
                currentLine: editorSession.currentHeadingLine, for: documentInformationDocumentID)
        } else {
            let headings = note.workspaceSnapshot?.headings ?? []
            let offset = documentSession.observedScrollPosition.anchor?.sourceUTF16Offset ?? 0
            documentInformation.publishOutline(headings,
                currentLine: headings.last { $0.span.utf16LowerBound <= offset }?.span.start.line,
                for: documentInformationDocumentID)
        }
    }

    private func handleDocumentFindShortcut(_ shortcut: DocumentFindShortcut) {
        switch shortcut {
        case .present:
            documentFind.present()
        case .next:
            documentFind.next()
        case .previous:
            documentFind.previous()
        case .useSelection:
            useSelectionForDocumentFind()
        }
    }

    private func useSelectionForDocumentFind() {
        if isEditing {
            Task { @MainActor in
                let selection = try? await editorSession.currentSelection(
                    for: editorSession.documentID,
                    in: editingSource
                )
                documentFind.useSelection(selection?.excerpt)
            }
        } else {
            documentFind.useSelection(documentSession.readSelection?.excerpt)
        }
    }

    private func requestImageImport() {
        requestImageSelection(.importFile)
    }

    private func requestImageIndex() {
        requestImageSelection(.index)
    }

    private func requestImageSelection(_ mode: ImageAttachmentSelectionMode) {
        guard isEditing,
              editorSession.isLoaded,
              editorSession.context?.composing != true,
              !isInsertingImage else { return }
        isInsertingImage = true
        let expectedDocumentID = editorSession.documentID
        let expectedPath = note.relativePath
        let noteID = VaultQualifiedNoteID(
            vaultID: note.vaultID,
            relativePath: expectedPath
        )

        Task { @MainActor in
            defer {
                isInsertingImage = false
                focusEditorIfPresented()
            }
            var prepared: PreparedImageAttachment?
            do {
                guard let fileSelectionPresenter else {
                    throw ScholiumFileSelectionError.presenterUnavailable
                }
                let request = ScholiumFileSelectionRequest(
                    title: mode == .importFile
                        ? String(localized: "Import Image")
                        : String(localized: "Index Image"),
                    message: mode == .importFile
                        ? String(localized: "Choose an image to copy into this Vault's Attachments folder.")
                        : String(localized: "Choose an image to reference at its absolute path without copying it."),
                    prompt: mode == .importFile
                        ? String(localized: "Import")
                        : String(localized: "Index"),
                    kind: .files(allowedContentTypes: [.image])
                )
                guard let sourceURL = try await fileSelectionPresenter.selectURL(request) else {
                    return
                }
                guard isEditing,
                      note.relativePath == expectedPath,
                      editorSession.documentID == expectedDocumentID else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                let preparation = switch mode {
                case .importFile:
                    try await controller.importImageAttachment(
                        at: sourceURL,
                        for: noteID
                    )
                case .index:
                    try await controller.indexImageAttachment(
                        at: sourceURL,
                        for: noteID
                    )
                }
                prepared = preparation
                guard isEditing,
                      note.relativePath == expectedPath,
                      editorSession.documentID == expectedDocumentID else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                try await editorSession.perform(
                    .insertImage,
                    argument: preparation.editorArgument
                )
                prepared = nil
                AccessibilityNotification.Announcement(
                    String(localized: "Image inserted.")
                ).post()
            } catch {
                var message = error.localizedDescription
                if let prepared {
                    do {
                        try await controller.rollbackImageAttachment(prepared)
                    } catch {
                        message += " " + String(
                            localized: "Attachment cleanup needs attention: \(error.localizedDescription)"
                        )
                    }
                }
                actions.notify(message, .error)
            }
        }
    }

    private func handlePastedImage(_ source: EditorPastedImageSource) -> Bool {
        guard isEditing,
              editorSession.isLoaded,
              editorSession.context?.composing != true,
              !isInsertingImage else { return false }
        isInsertingImage = true
        let expectedDocumentID = editorSession.documentID
        let expectedPath = note.relativePath
        let noteID = VaultQualifiedNoteID(
            vaultID: note.vaultID,
            relativePath: expectedPath
        )

        Task { @MainActor in
            defer {
                isInsertingImage = false
                focusEditorIfPresented()
            }
            var prepared: PreparedImageAttachment?
            do {
                guard isEditing,
                      note.relativePath == expectedPath,
                      editorSession.documentID == expectedDocumentID else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                let preparation: PreparedImageAttachment
                switch source {
                case .file(let url):
                    preparation = try await controller.importPastedImageAttachment(
                        at: url,
                        for: noteID
                    )
                case .data(let data, let preferredFilename):
                    preparation = try await controller.importPastedImageAttachment(
                        data: data,
                        preferredFilename: preferredFilename,
                        for: noteID
                    )
                }
                prepared = preparation
                guard isEditing,
                      note.relativePath == expectedPath,
                      editorSession.documentID == expectedDocumentID else {
                    throw MarkdownEditorSession.SessionError.staleRequest
                }
                try await editorSession.perform(
                    .insertImage,
                    argument: preparation.editorArgument
                )
                prepared = nil
                AccessibilityNotification.Announcement(
                    String(localized: "Image inserted.")
                ).post()
            } catch {
                var message = error.localizedDescription
                if let prepared {
                    do {
                        try await controller.rollbackImageAttachment(prepared)
                    } catch {
                        message += " " + String(
                            localized: "Attachment cleanup needs attention: \(error.localizedDescription)"
                        )
                    }
                }
                actions.notify(message, .error)
            }
        }
        return true
    }

    private func selectPresentationMode(_ mode: NotePresentationMode) {
        guard !editorIsComposing else {
            actions.notify(
                String(
                    localized: "Finish text composition to change document mode.",
                    table: "Localizable",
                    bundle: .module
                ),
                .information
            )
            return
        }
        if mode == .read {
            guard isEditing else {
                documentSession.resetPresentation()
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
                    let handoffAnchor = try? await editorSession.currentScrollAnchor()
                    documentSession.observeScrollAnchor(handoffAnchor)
                    documentSession.requestScrollRestore(
                        fingerprint: handoffAnchor?.sourceFingerprint
                            ?? DocumentFingerprint(content: editingSource).sha256,
                        reason: .modeHandoff
                    )
                    let committedFingerprint = DocumentFingerprint(
                        content: documentSession.originalEditingSource
                    ).sha256
                    if documentSession.renderedReadReadyFingerprint
                        != committedFingerprint {
                        // Never reveal a retained Review projection for the
                        // pre-save revision while SwiftUI publishes the newly
                        // committed Note and its hidden projection catches up.
                        documentSession.renderedReadReadyFingerprint = ""
                    }
                    guard returnToReadAfterSave else { return }
                    await editorSession.resignFocusAndWait()
                    guard returnToReadAfterSave else { return }
                    finishEditing()
                } catch { /* Controller published the recoverable error state. */ }
            }
            return
        }

        guard editingIsAvailable else {
            actions.notify(
                String(
                    localized: "This note is read-only in Scholium.",
                    table: "Localizable",
                    bundle: .module
                ),
                .information
            )
            return
        }
        guard let editorMode = mode.editorMode else { return }
        returnToReadAfterSave = false
        editorSession.authorizeAutomaticFocus()
        if isEditing {
            documentSession.switchEditorMode(to: editorMode)
        } else {
            beginEditing(mode: editorMode)
        }
        actions.rememberPresentationMode(mode)
    }

    private func applyPreparedPresentationModeIfAvailable() {
        guard !isEditing,
              let preparedMode = documentSession.pendingEditorMode,
              editingIsAvailable else { return }
        beginEditing(mode: preparedMode)
    }

    private func consumePendingPresentationRequest() {
        guard let requested = state.requestedPresentationMode else { return }
        selectPresentationMode(requested)
        actions.clearRequestedPresentationMode()
    }

    private var currentSourceLocationRequest: DocumentSourceLocationRequest? {
        guard state.sourceLocationRequest?.target == target else { return nil }
        return state.sourceLocationRequest
    }

    private var sourceLocationExecutionID: UUID? {
        guard isEditing, editorSession.isLoaded, !editorSession.isComposing,
              let intendedMode = state.requestedPresentationMode?.editorMode
                ?? documentSession.activeEditorMode,
              editorSession.presentedMode == intendedMode else { return nil }
        return currentSourceLocationRequest?.id
    }

    private func reportChangedSourceLocation() {
        actions.notify(String(localized: "This reference is from a different version. The Note was opened without selecting a passage.", bundle: .module), .information)
    }

    private func consumePendingSourceLocation() async {
        guard let id = sourceLocationExecutionID, let request = currentSourceLocationRequest,
              request.id == id else { return }
        do {
            try await editorSession.revealSourceLocation(request)
            guard !Task.isCancelled else { return }
            actions.consumeSourceLocation(id)
        } catch {
            guard !Task.isCancelled, currentSourceLocationRequest?.id == id else { return }
            actions.consumeSourceLocation(id)
            if error is DocumentSourceLocationFailure { reportChangedSourceLocation() }
            else {
                actions.notify(String(localized: "This reference location could not be verified. The Note was opened without selecting a passage.", bundle: .module), .information)
            }
        }
    }

    private func goToFrontmatter() {
        guard editingIsAvailable, editorSession.context?.composing != true else { return }
        selectPresentationMode(.livePreview)
        editorSession.goToLine(1)
    }

    private func beginEditing(mode: MarkdownEditorMode = .livePreview) {
        controller.beginEditing(
            session: documentSession,
            target: target,
            source: note.rawContent,
            revision: state.documentRevisions[note.relativePath],
            mode: mode
        )
    }

    /// Focus belongs to the mode that the Web editor has acknowledged, not
    /// merely to the mode most recently requested by native UI. This keeps a
    /// retained Source surface from receiving focus during Review -> Edit and
    /// prevents rapid Edit/Source requests from racing the bridge handshake.
    private func focusEditorIfPresented() {
        guard DocumentEditorPresentationGate().allowsEditorFocus(
            isEditing: isEditing,
            isReturningToReview: returnToReadAfterSave,
            editorIsReady: editorSession.isLoaded,
            presentedModeMatchesIntent:
                editorSession.presentedMode == documentSession.activeEditorMode
        ) else { return }
        if documentSession.managedCreationBodyStartUTF16 != nil {
            documentSession.completeManagedCreationEntry()
            AccessibilityNotification.Announcement(
                documentSession.activeEditorMode == .source
                    ? String(localized: "New note created. Source is ready.")
                    : String(localized: "New note created. Edit is ready.")
            ).post()
            return
        }
        editorSession.focusPreferred()
    }

    private func retryManagedCreationEditor(in mode: MarkdownEditorMode) {
        guard editingIsAvailable else {
            actions.notify(
                String(
                    localized: "This note is read-only in Scholium.",
                    table: "Localizable",
                    bundle: .module
                ),
                .information
            )
            return
        }
        if let bodyStart = documentSession.managedCreationBodyStartUTF16 {
            editorSession.revealSourceRange(
                fromUTF16: bodyStart,
                toUTF16: bodyStart
            )
        }
        documentSession.switchEditorMode(to: mode)
        actions.rememberPresentationMode(mode.presentationMode)
        editorSession.retryUnavailablePresentation()
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

}
// MARK: - Source comparison

private struct ConflictComparisonSheet: View {
    let conflict: DocumentConflictSnapshot
    let onReturnToEditing: () -> Void
    let onReloadFromDisk: () -> Void
    @State private var isDocumentExpanded = true

    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: "Compare Changes",
            detail: "Compare the current editor with the exact version now on disk.",
            identifier: "scholium.conflictComparison"
        ) {
            Button("Expand All") { isDocumentExpanded = true }
            .scholiumActivationPointer()
            Button("Collapse All") { isDocumentExpanded = false }
            .scholiumActivationPointer()
        } content: {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        isDocumentExpanded.toggle()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: isDocumentExpanded
                                ? "chevron.down" : "chevron.right")
                                .accessibilityHidden(true)
                            VStack(
                                alignment: .leading,
                                spacing: ScholiumGrid.Spacing.labelAccessoryGap
                            ) {
                                Text(conflict.relativePath)
                                    .font(ScholiumTypography.interface(.rowTitle))
                                Text("Editor and disk revisions differ")
                                    .font(ScholiumTypography.interface(.small))
                                    .scholiumForeground(.attention)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ScholiumGrid.Spacing.nestedContentInset)
                        .contentShape(Rectangle())
                    }
                    .scholiumActivationPointer()
                    .scholiumButtonStyle(.plain)
                    .accessibilityLabel(conflict.relativePath)
                    .accessibilityValue(
                        isDocumentExpanded ? "Expanded" : "Collapsed"
                    )
                    .accessibilityHint(
                        isDocumentExpanded
                            ? "Collapses this document" : "Expands this document"
                    )

                    if isDocumentExpanded {
                        ScholiumStructuralRule()
                        if let comparison = try? conflict.exactComparison() {
                            ExactSourceComparisonView(
                                comparison: comparison,
                                startingLabel: "Current Editor",
                                endingLabel: "Disk Version",
                                startingOnlyLabel: "Current editor only",
                                endingOnlyLabel: "Disk version only",
                                identifierPrefix: "scholium.conflict"
                            )
                            .padding(ScholiumGrid.Spacing.nestedContentInset)
                        } else {
                            ScholiumContentStateView(
                                "Comparison Unavailable",
                                detail: Text("The exact source revisions could not be compared."),
                                indicator: .symbol("exclamationmark.triangle", role: .attention)
                            )
                            .frame(
                                minHeight: ScholiumMetrics.ResearchSheet.Comparison.documentStateMinimumHeight
                            )
                        }
                    }
                }
                .background(ScholiumColorRole.documentBackground.color)
                .clipShape(RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                    .stroke(ScholiumColorRole.separator.color, lineWidth: 0.5)
                }
                .padding(ScholiumGrid.Spacing.sectionSeparation)
            }
        } footer: {
            HStack {
                Button("Return to Editing", action: onReturnToEditing)
                    .scholiumActivationPointer()
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reload from Disk", role: .destructive, action: onReloadFromDisk)
                .scholiumActivationPointer()
            }
            .padding(ScholiumGrid.Spacing.sectionSeparation)
        }
    }

}

#Preview {
    let controller = DocumentController()
    let note = WindowDocumentLocation.syntheticPreview(
        relativePath: "topics/consciousness.md",
        rawContent: "---\ntitle: Consciousness\n---\n\n# Consciousness\n\nThis is a test note.",
        vaultRole: .topicKnowledge
    )
    let state = DocumentFeatureState(
        notes: [note],
        selectedDocumentPath: note.relativePath,
        ordinarySearchScope: .triptych,
        currentVaultID: note.workspaceSnapshot?.id.vaultID,
        vaultRole: .topicKnowledge,
        noteIdentityByPath: [
            note.relativePath: note.workspaceSnapshot?.stableIdentity.resolvedID,
        ].compactMapValues { $0 },
        documentRevisions: [note.relativePath: note.document.fingerprint],
        workspaceCatalog: nil,
        canEdit: false,
        documentTextScale: 1,
        appearanceCSS: "",
        readCSS: "",
        livePreviewCSS: "",
        initialScrollFraction: 0,
        requestedPresentationMode: nil,
        sourceLocationRequest: nil,
        identityAmbiguity: nil,
        pendingIdentityRebinding: nil,
        identityMigrationFailureMessage: nil,
        isResolvingIdentity: false
    )
    let actions = DocumentFeatureActions(
        requestIdentityResolution: {},
        retryIdentityRecovery: {},
        beginSearch: { _ in },
        clearRequestedPresentationMode: {},
        consumeSourceLocation: { _ in },
        rememberScrollPosition: { _ in },
        openInternalLink: { _ in },
        openExternalURL: { _ in },
        enterCSSSafeMode: { _ in },
        rememberPresentationMode: { _ in },
        setSidebarVisible: { _ in },
        setResearchInspectorVisible: { _ in },
        openingDocumentPresentationDidComplete: {},
        renameNote: { _, _, requestedTitle in requestedTitle },
        notify: { _, _ in }
    )
    NoteContentView(
        controller: controller,
        documentInformation: DocumentInformationProjection(),
        target: .unavailable(
            vaultID: note.vaultID,
            relativePath: note.relativePath
        ),
        note: note,
        documentSession: DocumentSessionModel(key: nil),
        state: state,
        actions: actions
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
