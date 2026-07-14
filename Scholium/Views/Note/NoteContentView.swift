import SwiftUI
import ScholiumCore

// MARK: - Note Content Container

struct NoteTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let activeTab = appState.activeTab,
           let note = appState.notes.first(where: { $0.relativePath == activeTab }) {
            NoteContentView(note: note)
                .id(activeTab)
        }
    }
}

struct ResearchInspectorView: View {
    @EnvironmentObject var appState: AppState

    enum Mode: String, CaseIterable, Identifiable {
        case incoming = "Incoming"
        case outgoing = "Outgoing"
        case relationships = "Research"
        var id: String { rawValue }
    }

    let note: Note

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
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()

            Group {
                switch inspectorMode.wrappedValue {
                case .incoming: BacklinksPanelView()
                case .outgoing: OutgoingLinksPanelView(note: note)
                case .relationships: RelationshipView(note: note)
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
            get: { Mode(rawValue: appState.inspectorModeRaw.capitalized) ?? .incoming },
            set: { appState.inspectorModeRaw = $0.rawValue.lowercased() }
        )
    }
}
// MARK: - Note Content View

struct NoteContentView: View {
    @EnvironmentObject var appState: AppState
    let note: Note

    @State var isEditing = false
    @State var editingSource = ""
    @State private var originalEditingSource = ""
    @State var editingRevision: DocumentFingerprint?
    @State var editError: String?
    @State var isSavingEdit = false
    @State private var presentationMode: NotePresentationMode = .read
    @State private var autosaveTask: Task<Void, Never>?
    @State private var returnToReadAfterSave = false
    @State private var suppressAutosave = false
    @State private var renderedReadHTML = ""
    @State private var renderedReadFingerprint = ""
    @State private var conflict: DocumentConflictSnapshot?
    @State private var canRetrySave = false
    @State private var showConflictComparison = false
    @State private var activeSaveTask: Task<EditorSaveOutcome, Error>?
    @State private var activeSaveToken: UUID?
    @State private var editorFlushToken = UUID()
    @StateObject private var editorSession = MarkdownEditorSession()

    var body: some View {
        VStack(spacing: 0) {
            documentContextRow

            if let ambiguity = appState.identityAmbiguity(for: note.relativePath) {
                IdentityAmbiguityNotice(ambiguity: ambiguity) {
                    appState.requestIdentityResolution(for: note.relativePath)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else if let pending = appState.pendingIdentityRebinding(for: note.relativePath) {
                IdentityMigrationNotice(
                    rebinding: pending,
                    message: appState.identityMigrationFailure(for: note.relativePath)?.message,
                    isRetrying: appState.isResolvingIdentity
                ) {
                    await appState.retryIdentityRecovery()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if isCritiqueDocument {
                CritiqueProvenanceView(note: note)
            }

            if isEditing {
                bodyEditor
            } else {
                if ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_NATIVE_READ"] != "1",
                   renderedReadFingerprint == noteFingerprint.sha256,
                   !renderedReadHTML.isEmpty {
                    readDocumentSurface
                } else {
                    NativeMarkdownReadView(
                        source: note.rawContent,
                        textScale: appState.documentTextScale,
                        onLinkClick: {
                            appState.openInternalLink($0, from: note.relativePath)
                        },
                        onRequestComment: commentingIsAvailable ? { selection in
                            appState.requestResearcherComments(
                                at: note.relativePath,
                                selection: selection
                            )
                        } : nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                }
            }
        }
        .toolbar { noteToolbar }
        .focusedSceneValue(\.scholiumSearchActions, ScholiumSearchActions { mode in
            appState.beginSearch(mode: mode)
        })
        .sheet(isPresented: $showConflictComparison) {
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
            get: { editError != nil },
            set: { if !$0 { editError = nil } }
        )) {
            if conflict != nil {
                Button("Compare Changes") {
                    editError = nil
                    showConflictComparison = true
                }
                .keyboardShortcut(.defaultAction)
                Button("Reload from Disk", role: .destructive) { reloadFromDisk() }
            } else if canRetrySave {
                Button("Retry Save") { retrySave() }
            }
            Button("Keep Editing", role: .cancel) { editError = nil }
        } message: {
            Text(editError ?? "")
        }
        .onChange(of: editingSource) { _, _ in
            scheduleAutosave()
        }
        .onChange(of: appState.requestPresentationMode) { _, requested in
            guard let requested else { return }
            selectPresentationMode(requested)
            appState.requestPresentationMode = nil
        }
        .onAppear {
            let restoredMode = appState.presentationMode(for: note.relativePath)
            if restoredMode != .read { selectPresentationMode(restoredMode) }
            consumePendingPresentationRequest()
            appState.registerEditorFlush(
                for: note.relativePath,
                token: editorFlushToken
            ) {
                try await flushForAgentWork()
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            appState.unregisterEditorFlush(token: editorFlushToken)
        }
        .onChange(of: editorSession.isLoaded) { _, loaded in
            guard loaded, let line = appState.pendingSourceLine else { return }
            editorSession.goToLine(line)
            appState.pendingSourceLine = nil
        }
        .task(id: noteFingerprint.sha256) {
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

    private var reviewButtonTitle: String {
        if appState.humanReviewRecord(for: note.relativePath)?.draft != nil { return "Continue Review" }
        switch appState.reviewDisplayState(for: note.relativePath) {
        case .qualified: return "Qualified"
        case .unqualified: return "Unqualified"
        case .notReviewed, .reviewed: return "Review"
        }
    }

    private var reviewButtonSymbol: String {
        if appState.changedSinceReviewPaths.contains(note.relativePath) { return "arrow.triangle.2.circlepath" }
        switch appState.reviewDisplayState(for: note.relativePath) {
        case .qualified: return "checkmark.seal.fill"
        case .unqualified: return "xmark.seal.fill"
        case .notReviewed, .reviewed: return "checkmark.circle"
        }
    }

    private var reviewButtonTint: Color {
        if appState.changedSinceReviewPaths.contains(note.relativePath) { return .orange }
        switch appState.reviewDisplayState(for: note.relativePath) {
        case .qualified: return .green
        case .unqualified: return .red
        case .notReviewed, .reviewed: return .accentColor
        }
    }

    private var reviewButtonHelp: String {
        if appState.changedSinceReviewPaths.contains(note.relativePath) {
            return "Review the changed file bytes"
        }
        return appState.humanReviewRecord(for: note.relativePath)?.draft != nil
            ? "Continue the saved Human Review draft"
            : "Review and qualify this note"
    }

    private var humanReviewIsAvailable: Bool {
        appState.noteLocationScope == .workspace && appState.currentVaultRole.allowsHumanReview
    }

    private var commentingIsAvailable: Bool {
        appState.currentNote?.relativePath == note.relativePath && appState.canCommentCurrentNote
    }

    private var editingIsAvailable: Bool {
        appState.canEditCurrentNote && !isCritiqueDocument
    }

    private var isCritiqueDocument: Bool {
        appState.currentVaultRole.allowsCritique
            && (note.relativePath == "Critiques" || note.relativePath.hasPrefix("Critiques/"))
    }

    private var noteFingerprint: DocumentFingerprint {
        appState.documentRevisions[note.relativePath] ?? DocumentFingerprint(content: note.rawContent)
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
            initialScrollFraction: appState.scrollPosition(for: note.relativePath),
            onDocumentChange: { updatedSource in
                guard isEditing, editingSource != updatedSource else { return }
                editingSource = updatedSource
            },
            onRequestSave: {
                Task { await persistEditingSource() }
            },
            onCommentActivation: commentingIsAvailable ? { commentID in
                appState.requestResearcherComments(
                    at: note.relativePath,
                    focusedCommentID: commentID
                )
            } : nil,
            onScrollFractionChange: { appState.rememberScrollPosition($0, for: note.relativePath) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
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
                appState.openInternalLink($0, from: note.relativePath)
            },
            onCommentSelection: commentingIsAvailable ? { selection in
                appState.requestResearcherComments(
                    at: note.relativePath,
                    selection: selection
                )
            } : nil,
            onCommentActivation: commentingIsAvailable ? { commentID in
                appState.requestResearcherComments(
                    at: note.relativePath,
                    focusedCommentID: commentID
                )
            } : nil,
            onRenderingFailure: { reason in
                appState.cssSnippetStore.enterSafeMode(after: reason)
            },
            initialScrollFraction: appState.scrollPosition(for: note.relativePath),
            onScrollFractionChange: {
                appState.rememberScrollPosition($0, for: note.relativePath)
            },
            targetSourceLine: appState.pendingSourceLine,
            onSourceLineReached: { appState.pendingSourceLine = nil }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    private var currentResearcherComments: [ResearcherComment] {
        appState.humanReviewRecord(for: note.relativePath)?.comments ?? []
    }

    private var scaledReadCSS: String {
        appState.cssSnippetStore.readCSS
            + "\n.scholium-document { font-size: \(appState.documentTextScale)em; }"
    }

    private var scaledEditorCSS: String {
        appState.cssSnippetStore.livePreviewCSS
            + "\n.cm-content { font-size: \(appState.documentTextScale)em; }"
    }

    private var editorLinkCompletions: [EditorLinkCompletion] {
        guard let currentVaultID = appState.currentRegisteredVault?.id,
              let catalogNotes = appState.workspaceCatalog?.notes,
              !catalogNotes.isEmpty else {
            let stemCounts = Dictionary(grouping: appState.notes, by: \.displayName).mapValues(\.count)
            return appState.notes.map { candidate in
                let needsPath = (stemCounts[candidate.displayName] ?? 0) > 1
                return EditorLinkCompletion(
                    label: candidate.title ?? candidate.displayName,
                    insertion: needsPath
                        ? (candidate.relativePath as NSString).deletingPathExtension
                        : candidate.displayName,
                    detail: "Current Vault · \(candidate.relativePath)",
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
                ? " · Ambiguous: no unique Obsidian-compatible target"
                : ""
            return EditorLinkCompletion(
                label: candidate.title,
                insertion: insertion,
                detail: "\(candidate.reference.vaultName) · \(candidate.reference.vaultRole.displayName) · \(candidate.reference.relativePath)\(ambiguity)",
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
        editingSource != originalEditingSource || (isEditing && editorSession.isDirty)
    }

    private func selectPresentationMode(_ mode: NotePresentationMode) {
        if mode == .read {
            guard isEditing else {
                presentationMode = .read
                appState.rememberPresentationMode(.read, for: note.relativePath)
                return
            }
            returnToReadAfterSave = true
            autosaveTask?.cancel()
            Task {
                do {
                    try await flushCurrentEditor()
                    guard returnToReadAfterSave else { return }
                    finishEditing()
                } catch {
                    await presentSaveFailure(error)
                }
            }
            return
        }

        guard editingIsAvailable else {
            appState.showToast("This note is read-only in Scholium.", kind: .information)
            return
        }
        appState.rememberPresentationMode(mode, for: note.relativePath)

        if isEditing {
            presentationMode = mode
        } else {
            beginEditing(mode: mode)
        }
    }

    private func consumePendingPresentationRequest() {
        guard let requested = appState.requestPresentationMode else { return }
        selectPresentationMode(requested)
        appState.requestPresentationMode = nil
        if let line = appState.pendingSourceLine {
            editorSession.goToLine(line)
        }
    }

    private func beginEditing(mode: NotePresentationMode = .livePreview) {
        guard isEditing == false, mode != .read else { return }
        suppressAutosave = true
        originalEditingSource = note.rawContent
        editingSource = note.rawContent
        editingRevision = appState.documentRevisions[note.relativePath]
        appState.editingBodyPath = nil
        presentationMode = mode
        isEditing = true
        Task { @MainActor in
            await Task.yield()
            suppressAutosave = false
        }
    }

    private func finishEditing() {
        autosaveTask?.cancel()
        autosaveTask = nil
        isEditing = false
        editingSource = ""
        originalEditingSource = ""
        editingRevision = nil
        appState.editingBodyPath = nil
        presentationMode = .read
        appState.rememberPresentationMode(.read, for: note.relativePath)
        returnToReadAfterSave = false
        suppressAutosave = false
    }

    private func scheduleAutosave() {
        guard isEditing, !suppressAutosave, hasUnsavedChanges else { return }
        appState.editingBodyPath = note.relativePath
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(autosaveDelayMilliseconds))
            guard !Task.isCancelled else { return }
            await persistEditingSource()
        }
    }

    private var autosaveDelayMilliseconds: Int {
#if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_AUTOSAVE_DELAY_MS"],
           let value = Int(raw), value >= 0 {
            return value
        }
#endif
        return 850
    }

    @MainActor
    private func persistEditingSource() async {
        do {
            let outcome = try await saveEditingSource()
            editError = nil
            conflict = nil
            if outcome == .changedDuringSave {
                scheduleAutosave()
            }
        } catch {
            await presentSaveFailure(error)
        }
    }

    @MainActor
    private func saveEditingSource() async throws -> EditorSaveOutcome {
        if let activeSaveTask {
            return try await activeSaveTask.value
        }

        let token = UUID()
        let task = Task { @MainActor in
            try await performEditingSave()
        }
        activeSaveToken = token
        activeSaveTask = task
        isSavingEdit = true

        do {
            let outcome = try await task.value
            if activeSaveToken == token {
                activeSaveTask = nil
                activeSaveToken = nil
                isSavingEdit = false
            }
            return outcome
        } catch {
            if activeSaveToken == token {
                activeSaveTask = nil
                activeSaveToken = nil
                isSavingEdit = false
            }
            throw error
        }
    }

    @MainActor
    private func performEditingSave() async throws -> EditorSaveOutcome {
        guard isEditing else { return .clean }
        if !editorSession.isReady || !editorSession.isLoaded {
            guard editingSource == originalEditingSource, !editorSession.isDirty else {
                throw EditorFlushError.editorUnavailable
            }
            return .clean
        }
        guard let revision = editingRevision else {
            throw EditorFlushError.saveFailed(
                "The editing revision is unavailable. Return to Read mode and reopen the editor."
            )
        }

        let sourceBeingSaved = try await editorSession.currentText(for: note.relativePath)
        let mirroredSource = editingSource
        guard DocumentFingerprint(content: sourceBeingSaved) == DocumentFingerprint(content: mirroredSource) else {
            // Do not write a buffer after a bridge delta was lost or rejected.
            // Preserve the complete CodeMirror text, reconcile the local mirror,
            // and require a fresh save attempt through the same revision gate.
            suppressAutosave = true
            editingSource = sourceBeingSaved
            suppressAutosave = false
            appState.editingBodyPath = note.relativePath
            throw EditorFlushError.deltaMirrorMismatch
        }
        suppressAutosave = true
        editingSource = sourceBeingSaved
        defer { suppressAutosave = false }

        guard sourceBeingSaved != originalEditingSource || editorSession.isDirty else {
            appState.editingBodyPath = nil
            return .clean
        }

        let saved = try await appState.saveSource(
            sourceBeingSaved,
            for: note.relativePath,
            expectedRevision: revision
        )
        let savedSource = saved.rawContent
        let savedRevision = DocumentFingerprint(content: savedSource)
        editingRevision = savedRevision
        originalEditingSource = savedSource

        let synchronized = try await editorSession.synchronizeCommittedText(
            expectedText: sourceBeingSaved,
            committedText: savedSource,
            fingerprint: savedRevision,
            documentID: note.relativePath
        )
        if synchronized {
            editingSource = savedSource
            appState.editingBodyPath = nil
            return .clean
        }

        let latestSource = try await editorSession.currentText(for: note.relativePath)
        editingSource = latestSource
        appState.editingBodyPath = note.relativePath
        return .changedDuringSave
    }

    @MainActor
    private func flushCurrentEditor() async throws {
        autosaveTask?.cancel()
        for _ in 0..<4 {
            let outcome = try await saveEditingSource()
            if outcome == .clean { return }
        }
        throw EditorFlushError.changedDuringSave
    }

    @MainActor
    private func flushForAgentWork() async throws {
        do {
            try await flushCurrentEditor()
        } catch {
            await presentSaveFailure(error)
            throw error
        }
    }

    @MainActor
    private func presentSaveFailure(_ error: Error) async {
        editError = error.localizedDescription
        appState.lastSaveError = error.localizedDescription
        if case VaultRepositoryError.conflict = error,
           let diskDocument = try? await appState.diskDocument(for: note.relativePath),
           let baseRevision = editingRevision {
            conflict = DocumentConflictSnapshot(
                relativePath: note.relativePath,
                editorSource: editingSource,
                diskSource: diskDocument.rawContent,
                baseRevision: baseRevision
            )
            canRetrySave = false
        } else {
            conflict = nil
            // Repository validation, identity, and containment failures require
            // a source or setup correction. I/O and editor-bridge failures can
            // plausibly succeed when retried without discarding the buffer.
            canRetrySave = !(error is VaultRepositoryError)
        }
    }

    private func retrySave() {
        editError = nil
        canRetrySave = false
        Task {
            do {
                try await flushCurrentEditor()
            } catch {
                await presentSaveFailure(error)
            }
        }
    }

    private func reloadFromDisk() {
        guard let conflict else { return }
        Task {
            do {
                _ = try await appState.reloadDocumentFromDisk(
                    for: note.relativePath,
                    expectedDiskRevision: conflict.diskRevision
                )
                showConflictComparison = false
                self.conflict = nil
                canRetrySave = false
                editError = nil
                finishEditing()
            } catch {
                showConflictComparison = false
                await presentSaveFailure(error)
            }
        }
    }

    // MARK: - Toolbar

    private var documentContextRow: some View {
        HStack(alignment: .top, spacing: 4) {
            Menu {
                ForEach(NotePresentationMode.allCases) { mode in
                    Button {
                        appState.requestDocumentMode(mode)
                    } label: {
                        if mode == presentationMode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Label(mode.title, systemImage: mode.symbol)
                        }
                    }
                }
            } label: {
                Label(presentationMode.title, systemImage: presentationMode.symbol)
            }
            .fixedSize()
            .disabled(!editingIsAvailable)
            .buttonStyle(.glass)
            .help("Document mode: \(presentationMode.title)")
            .accessibilityLabel("Document mode")
            .accessibilityValue(presentationMode.title)
            .accessibilityIdentifier("scholium.documentModeMenu")

            Menu {
                if documentHeadings.isEmpty {
                    Text("No Headings")
                } else {
                    ForEach(Array(documentHeadings.enumerated()), id: \.offset) { _, heading in
                        Button {
                            appState.pendingSourceLine = heading.span.start.line
                            if isEditing { editorSession.goToLine(heading.span.start.line) }
                        } label: {
                            Text(String(repeating: "  ", count: max(0, heading.level - 1)) + heading.text)
                        }
                    }
                }
            } label: {
                Label("Outline", systemImage: "list.bullet.indent")
            }
            .buttonStyle(.glass)
            .help("Heading Outline")
            .accessibilityIdentifier("scholium.headingOutline")

            MetadataCardView(note: note)
                .frame(maxWidth: .infinity)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.vertical, 4)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ToolbarContentBuilder
    var noteToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if appState.openTabs.count > 1 {
                DocumentTabBar()
                    .frame(minWidth: 180, idealWidth: 420, maxWidth: 600)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                appState.beginSearch(mode: .triptych)
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search the Triptych")
            .accessibilityIdentifier("scholium.searchToolbarButton")
            .popover(isPresented: $appState.showSearchSurface, arrowEdge: .top) {
                SearchWorkspaceView()
                    .environmentObject(appState)
                    .frame(width: 680, height: 520)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            if commentingIsAvailable || humanReviewIsAvailable || appState.currentVaultRole.allowsCritique {
                Button {
                    appState.openScholia()
                } label: {
                    Label("Open Scholia…", systemImage: "text.bubble")
                }
                .help("Open comments, review, critique, and Dialogue for this note")
                .accessibilityIdentifier("scholium.openScholiaButton")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            ControlGroup {
                Button {
                    appState.setNoteHistoryVisible(!appState.noteHistoryVisible, animated: false)
                } label: {
                    Label(
                        appState.noteHistoryVisible ? "Hide Note History" : "Show Note History",
                        systemImage: "clock.arrow.circlepath"
                    )
                }
                .disabled(isEditing || appState.noteIdentityByPath[note.relativePath] == nil)
                .help(appState.noteHistoryVisible ? "Hide Note History" : "Show Note History")
                .accessibilityIdentifier("scholium.noteHistoryButton")

                Button {
                    appState.setResearchInspectorVisible(!appState.backlinksVisible, animated: false)
                } label: {
                    Label(
                        appState.backlinksVisible ? "Hide Research Inspector" : "Show Research Inspector",
                        systemImage: "sidebar.trailing"
                    )
                }
                .help(appState.backlinksVisible ? "Hide Research Inspector" : "Show Research Inspector")
                .accessibilityIdentifier("scholium.researchInspectorButton")
            }
        }
    }

    private func requestResearcherCommentsFromDocument() {
        guard commentingIsAvailable else { return }
        guard isEditing else {
            appState.requestResearcherComments(at: note.relativePath)
            return
        }
        Task { @MainActor in
            do {
                let currentSource = try await editorSession.currentText(for: note.relativePath)
                let selection = try await editorSession.currentSelection(
                    for: note.relativePath,
                    in: currentSource
                )
                try await flushCurrentEditor()
                appState.requestResearcherComments(
                    at: note.relativePath,
                    selection: selection
                )
            } catch {
                appState.showToast(
                    "Scholium could not capture the current editor selection. Keep editing and try again. \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    private var documentHeadings: [HeadingNode] {
        MarkdownSemanticDocument(
            parsing: NoteDocument(relativePath: note.relativePath, rawContent: note.rawContent)
        ).headings
    }

    func noteDisplayName(_ path: String) -> String {
        guard let note = appState.notes.first(where: { $0.relativePath == path }) else {
            return (path as NSString).lastPathComponent
        }
        return note.title ?? note.displayName
    }
}

private enum EditorSaveOutcome: Equatable {
    case clean
    case changedDuringSave
}

private enum EditorFlushError: LocalizedError {
    case saveFailed(String)
    case editorUnavailable
    case changedDuringSave
    case deltaMirrorMismatch

    var errorDescription: String? {
        switch self {
        case .saveFailed(let message):
            "Scholium kept the current editor open because it could not safely save this note. \(message)"
        case .editorUnavailable:
            "Scholium kept the current editor open because it could not retrieve the complete Markdown buffer."
        case .changedDuringSave:
            "Scholium kept the current editor open because the note continued changing while it was being saved."
        case .deltaMirrorMismatch:
            "Scholium kept the current editor open because an editor update did not reach the autosave mirror. The complete editor buffer was recovered; retry the save."
        }
    }
}

// MARK: - Document Tabs

private struct DocumentTabBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(appState.openTabs, id: \.self) { path in
                            DocumentTab(path: path)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.hidden)

            Menu {
                ForEach(appState.openTabs, id: \.self) { path in
                    Button {
                        appState.requestSelectTab(path)
                    } label: {
                        if appState.activeTab == path {
                            Label(noteDisplayName(path), systemImage: "checkmark")
                        } else {
                            Text(noteDisplayName(path))
                        }
                    }
                }
            } label: {
                Label("Open Tabs", systemImage: "chevron.down")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .help("Open document tabs")
            .accessibilityLabel("Open document tabs")
        }
        .frame(height: 32)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Open document tabs")
        .accessibilityIdentifier("scholium.documentTabs")
    }

    private func noteDisplayName(_ path: String) -> String {
        guard let note = appState.notes.first(where: { $0.relativePath == path }) else {
            return (path as NSString).lastPathComponent
        }
        return note.title ?? note.displayName
    }
}

private struct DocumentTab: View {
    @EnvironmentObject var appState: AppState
    let path: String

    @State private var isHovering = false

    private var isSelected: Bool { appState.activeTab == path }

    private var title: String {
        guard let note = appState.notes.first(where: { $0.relativePath == path }) else {
            return (path as NSString).lastPathComponent
        }
        return note.title ?? note.displayName
    }

    private var tabLabel: String {
        title
    }

    private var supplementaryLabel: String? {
        guard let note = appState.notes.first(where: { $0.relativePath == path }) else { return nil }
        let author = note.authors.first?.split(separator: " ").last.map(String.init)
        let year = note.year.map { $0.formatted(.number.grouping(.never)) }
        let label = [author, year].compactMap { $0 }.joined(separator: " ")
        return label.isEmpty ? nil : label
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                appState.requestSelectTab(path)
            } label: {
                Text(tabLabel)
                    .font(.callout.weight(isSelected ? .medium : .regular))
                    .lineLimit(1)
                    .frame(minWidth: 72, maxWidth: 150, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(supplementaryLabel.map { "\(title) — \($0)" } ?? title)
            .accessibilityLabel(supplementaryLabel.map { "\(title), \($0)" } ?? title)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button {
                appState.requestCloseTab(path)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isSelected || isHovering ? 1 : 0)
            .accessibilityLabel("Close \(title)")
            .help("Close \(title)")
        }
        .padding(.horizontal, 9)
        .frame(height: 31)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .glassEffect(
            isSelected ? .regular.interactive() : .identity,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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
                        .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
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
                                .font(ScholiumTypography.swiftUIMonospaceFont(
                                    size: 13,
                                    relativeTo: .body,
                                    bold: true
                                ))
                                .foregroundStyle(color(for: line.kind))
                                .frame(width: 16)
                                .accessibilityLabel(label(for: line.kind))
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(ScholiumTypography.swiftUIMonospaceFont(size: 13, relativeTo: .body))
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
        .frame(minWidth: 760, idealWidth: 900, minHeight: 520, idealHeight: 680)
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
                .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
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
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    let note: Note
    let presentation: NoteHistoryPresentation

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
    @State private var errorMessage: String?

    init(note: Note, presentation: NoteHistoryPresentation = .sheet) {
        self.note = note
        self.presentation = presentation
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
                if presentation == .sheet {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button {
                        appState.setNoteHistoryVisible(false, animated: false)
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
                        if appState.currentVaultRole.allowsHumanReview { reviewSection }
                        commentSection
                        dialogueSection
                        if appState.currentVaultRole.allowsCritique { critiqueSection }
                        checkpointSection
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            HStack {
                Button("Reveal Checkpoints in Finder") {
                    appState.revealCheckpointsInFinder()
                }
                Spacer()
                if let selectedCheckpoint {
                    Button("Restore This Version", role: .destructive) {
                        restore(selectedCheckpoint)
                    }
                    .disabled(isRestoring)
                }
            }
            .padding(16)
        }
        .frame(
            minWidth: presentation == .sheet ? 760 : 280,
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
                    checkpointSource = try await appState.noteCheckpointContent(
                        checkpoint.id,
                        path: note.relativePath
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
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
                ManualDialogueFollowUpView(entry: entry) { updated in
                    if let index = dialogue.firstIndex(where: { $0.id == updated.id }) {
                        dialogue[index] = updated
                    }
                    pendingDialogueSheet = nil
                }
                .environmentObject(appState)
            case .response(let entry):
                ManualDialogueReplyView(entry: entry) { updated in
                    if let index = dialogue.firstIndex(where: { $0.id == updated.id }) {
                        dialogue[index] = updated
                    }
                    pendingDialogueSheet = nil
                }
                .environmentObject(appState)
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
                            Text(comment.anchor.map {
                                $0.state == .needsReattachment
                                    ? "Needs Reattachment · originally line \($0.line)"
                                    : ($0.line == $0.endLine ? "Line \($0.line)" : "Lines \($0.line)–\($0.endLine)")
                            } ?? "Whole note")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(comment.anchor?.state == .needsReattachment ? Color.orange : Color.secondary)
                            if comment.resolvedAt != nil {
                                Text("Resolved")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Text(comment.text).textSelection(.enabled)
                        if let anchor = comment.anchor {
                            Text(anchor.selectedText ?? anchor.quotation)
                                .font(ScholiumTypography.swiftUIMonospaceFont(size: 11, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .lineLimit(3)
                        }
                    }
                    .padding(.vertical, 3)
                    if comment.id != comments.last?.id { Divider() }
                }
            } else {
                emptyText("This note has no researcher comments.")
            }
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
                        Text("Checkpoint: Before Agent Work · \(entry.checkpointID.uuidString.prefix(8))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
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
                                        Text("\(selectedNote.vaultName) · \(selectedNote.relativePath)")
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
                                    if let sourceNote = includedComment.note {
                                        Text(sourceNote.title)
                                            .font(.subheadline.weight(.medium))
                                        Text("\(sourceNote.vaultName) · \(sourceNote.relativePath)")
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
                                    } else {
                                        Text("Source note unavailable")
                                            .font(.subheadline.weight(.medium))
                                        Text("Legacy Dialogue entry")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                    Text(includedComment.comment.text)
                                        .textSelection(.enabled)
                                    Text(includedComment.comment.anchor.map {
                                        "Lines \($0.line)–\($0.endLine)"
                                    } ?? "Whole note")
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
                                        try appState.copyTextToClipboard(entry.generatedPrompt)
                                        appState.showToast("Instructions copied")
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
            let owner = included.note?.title ?? "comment"
            return "Comment in \(owner)"
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
                        appState.requestOpenNote(critique.critiqueRelativePath)
                    } label: {
                        Label("Open Critique", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.link)
                }

                Button {
                    appState.requestOpenNote(critique.workRelativePath)
                } label: {
                    Label("Open Target Work", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.link)

                let currentTargetSHA = appState.documentRevisions[critique.workRelativePath]?.sha256
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
                                    Text("\(round.scope.rawValue) · \(round.requestedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.subheadline)
                                    HStack(spacing: 5) {
                                        Text("SHA-256 \(round.targetFingerprint.sha256.prefix(12))…")
                                        if let checkpointID = round.checkpointID {
                                            Text("· Before Agent Work \(checkpointID.uuidString.prefix(8))")
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
                                        size: ScholiumTypography.sourceBodySize,
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
        review = appState.humanReviewRecord(for: note.relativePath)
        do {
            async let loadedDialogue = appState.dialogueHistory(for: note.relativePath)
            async let loadedCritique = appState.critiqueAssociationRelated(to: note.relativePath)
            async let loadedCheckpoints = appState.noteCheckpoints(for: note.relativePath)
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
                try await appState.restoreNote(note.relativePath, from: checkpoint.id)
                appState.showToast("Restored \(note.displayName) from \(checkpoint.name)")
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

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
        .frame(minWidth: 560, idealWidth: 640, minHeight: 430, idealHeight: 500)
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
                let updated = try await appState.recordDialogueFollowUpComment(
                    entryID: entry.id,
                    text: text,
                    noteID: targetIDs.noteID,
                    commentID: targetIDs.commentID
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

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
        .frame(minWidth: 560, idealWidth: 640, minHeight: 430, idealHeight: 500)
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
                let updated = try await appState.recordDialogueReply(
                    entryID: entry.id,
                    agentName: agentName,
                    text: text,
                    noteID: targetIDs.noteID,
                    commentID: targetIDs.commentID
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
        let owner = included.note?.title ?? "selected note"
        return "Comment in \(owner): \(included.comment.text)"
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
        })?.note?.noteID
        return (noteID, id)
    }
}

// MARK: - Preview

#Preview {
    let note = Note(
        relativePath: "topics/consciousness.md",
        frontmatter: ["title": .string("Consciousness")],
        body: "# Consciousness\n\nThis is a test note.",
        rawContent: "---\ntitle: Consciousness\n---\n\n# Consciousness\n\nThis is a test note.",
        isReviewed: true,
        reviewedAt: Date()
    )
    NoteContentView(note: note)
        .environmentObject(AppState())
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
