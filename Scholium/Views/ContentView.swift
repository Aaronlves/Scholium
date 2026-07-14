import ScholiumCore
import SwiftUI

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geometry in
            Group {
                if appState.vaultConfig == nil {
                    WelcomeView()
                } else {
                    NavigationSplitView(columnVisibility: sidebarVisibility) {
                        SidebarView()
                            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 360)
                    } detail: {
                        detailRegion
                    }
                    .navigationSplitViewStyle(.prominentDetail)
                    .navigationTitle(windowTitle)
                }
            }
            .onAppear { updateAdaptiveLayout(for: geometry.size.width, isInitial: true) }
            .onChange(of: geometry.size.width) { _, width in
                updateAdaptiveLayout(for: width)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.toastMessage {
                ToastView(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 20)
            }
        }
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
                .glassEffect(
                    appState.hasDerivedRefreshFailure
                        ? .regular.tint(.orange.opacity(0.18))
                        : .regular,
                    in: Capsule()
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
        .sheet(isPresented: $appState.showQuickOpen) {
            QuickOpenView()
        }
        .sheet(isPresented: adaptiveTrailingContextPresentation) {
            if let note = appState.currentNote {
                if appState.noteHistoryVisible {
                    NoteHistorySheet(note: note, presentation: .sheet)
                        .environmentObject(appState)
                } else {
                    AdaptiveResearchInspectorSheet(note: note) {
                        appState.setResearchInspectorVisible(false, animated: false)
                    }
                    .environmentObject(appState)
                }
            }
        }
        .sheet(isPresented: $appState.showWorkspaceSetup) {
            WorkspaceSetupView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showFrontmatterEditor) {
            if let path = appState.editingNotePath,
               let note = appState.notes.first(where: { $0.relativePath == path }) {
                FrontmatterEditorView(note: note)
                    .frame(minWidth: 520, minHeight: 560)
            }
        }
        .sheet(isPresented: $appState.showScholia) {
            if let note = appState.currentNote {
                ScholiaPanelView(note: note)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $appState.showAttentionQueues) {
            AttentionQueueView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showQualityReview, onDismiss: {
            appState.qualityReviewPath = nil
        }) {
            if let path = appState.qualityReviewPath,
               let note = appState.notes.first(where: { $0.relativePath == path }) {
                QualityReviewView(note: note)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $appState.showResearcherComments, onDismiss: {
            appState.researcherCommentsPath = nil
            appState.pendingCommentSelection = nil
            appState.focusedResearcherCommentID = nil
        }) {
            if let path = appState.researcherCommentsPath,
               let note = appState.notes.first(where: { $0.relativePath == path }) {
                ResearcherCommentsView(note: note)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $appState.showDialogue, onDismiss: {
            appState.dialogueInitialNotes = []
        }) {
            DialogueView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showCreateCheckpoint) {
            CreateCheckpointView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showCheckpointBrowser) {
            RestoreCheckpointView()
                .environmentObject(appState)
        }
        .sheet(item: $appState.noteLifecycleRequest) { request in
            NoteLifecycleView(request: request)
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showTransactionRecovery) {
            TransactionRecoveryView()
                .environmentObject(appState)
        }
        .sheet(isPresented: Binding(
            get: { appState.pendingCritiquePath != nil },
            set: { if !$0 { appState.pendingCritiquePath = nil } }
        )) {
            if let path = appState.pendingCritiquePath,
               let note = appState.notes.first(where: { $0.relativePath == path }) {
                CritiqueRequestView(note: note)
                    .environmentObject(appState)
            }
        }
        .sheet(item: $appState.selectedIdentityAmbiguity, onDismiss: {
            appState.identityResolutionError = nil
        }) { ambiguity in
            IdentityResolutionView(
                ambiguity: ambiguity,
                vaultName: appState.currentRegisteredVault?.name ?? "Current Vault",
                isResolving: appState.isResolvingIdentity,
                errorMessage: appState.identityResolutionError,
                onConfirm: { candidateID in
                    await appState.resolveSelectedIdentity(candidateID: candidateID)
                },
                onCancel: {
                    appState.selectedIdentityAmbiguity = nil
                    appState.identityResolutionError = nil
                }
            )
        }
        .alert("Could Not Complete Action", isPresented: .init(
            get: { appState.vaultError != nil },
            set: { if !$0 { appState.vaultError = nil } }
        )) {
            Button("Dismiss") { appState.vaultError = nil }
        } message: {
            Text(appState.vaultError ?? "")
        }
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.sidebarVisible ? .all : .detailOnly },
            set: { appState.sidebarVisible = $0 != .detailOnly }
        )
    }

    private var showsTrailingContext: Bool {
        ProcessInfo.processInfo.environment["SCHOLIUM_UI_TEST_DISABLE_INSPECTOR"] != "1"
            && (appState.backlinksVisible || appState.noteHistoryVisible)
            && appState.usesWideWindowLayout
            && appState.contentDestination == .document
            && appState.currentNote != nil
    }

    private var adaptiveTrailingContextPresentation: Binding<Bool> {
        Binding(
            get: {
                !appState.usesWideWindowLayout
                    && (appState.backlinksVisible || appState.noteHistoryVisible)
                    && appState.contentDestination == .document
                    && appState.currentNote != nil
            },
            set: { isPresented in
                guard !isPresented else { return }
                if appState.noteHistoryVisible {
                    appState.setNoteHistoryVisible(false, animated: false)
                } else {
                    appState.setResearchInspectorVisible(false, animated: false)
                }
            }
        )
    }

    private func updateAdaptiveLayout(for width: CGFloat, isInitial: Bool = false) {
        guard abs(appState.windowWidth - width) > 0.5 else { return }
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
            if isInitial, width < 980 {
                appState.sidebarVisible = false
            }
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
                        NoteHistorySheet(note: note, presentation: .trailing)
                            .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, maxHeight: .infinity)
                    } else {
                        ResearchInspectorView(note: note)
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
        switch appState.contentDestination {
        case .canvas:
            documentContent
        case .search:
            SearchWorkspaceView()
        case .document:
            documentContent
        }
    }

    @ViewBuilder
    private var documentContent: some View {
        if appState.currentNote != nil {
            NoteTabView()
                .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView()
        }
    }

    private var windowTitle: String {
        switch appState.contentDestination {
        case .canvas: appState.currentNote?.title ?? appState.currentNote?.displayName ?? "Scholium"
        case .search: "Search"
        case .document: appState.currentNote?.title ?? appState.currentNote?.displayName ?? "Scholium"
        }
    }
}

private struct AdaptiveResearchInspectorSheet: View {
    let note: Note
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

            ResearchInspectorView(note: note)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 560, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("scholium.adaptiveContextPanel")
    }
}

// MARK: - Loading Overlay

private struct LoadingOverlay: View {
    var body: some View {
        ProgressView("Opening vault…")
            .controlSize(.large)
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityAddTraits(.isModal)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "text.book.closed")
                .font(.system(size: 52, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Scholium")
                    .font(.largeTitle.weight(.semibold))

                Text("A local-first workbench for source-grounded research.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button {
                appState.showWorkspaceSetup = true
            } label: {
                Label("Choose Your Triptych…", systemImage: "folder.badge.gearshape")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Label("Vault files stay local. You control when agents may edit them.", systemImage: "checkmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Choose a Note")
                .font(.title2.weight(.semibold))

            Text("Select a note in the sidebar, or use Quick Open to find one.")
                .foregroundStyle(.secondary)

            Button {
                appState.showQuickOpen = true
            } label: {
                Label("Quick Open…", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("p", modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Quick Open View

struct QuickOpenView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WorkspaceCatalogNote] = []
    @State private var selectedResultID: WorkspaceCatalogNote.ID?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                List(results, selection: $selectedResultID) { note in
                    Button {
                        open(note)
                    } label: {
                        QuickOpenRow(
                            title: note.title,
                            vaultRole: note.reference.vaultRole,
                            relativePath: note.reference.relativePath
                        )
                    }
                    .buttonStyle(.plain)
                    .tag(note.id)
                    .accessibilityLabel(
                        "\(note.title), \(note.reference.vaultRole.displayName), \(note.reference.relativePath)"
                    )
                    .accessibilityHint("Open note")
                    .accessibilityIdentifier(
                        "scholium.quickOpenResult.\(note.reference.vaultRole.rawValue).\(note.reference.relativePath)"
                    )
                }
                .listStyle(.inset)

                if results.isEmpty {
                    ContentUnavailableView {
                        Label(
                            query.isEmpty ? "No Notes Available" : "No Matching Notes",
                            systemImage: "doc.text.magnifyingglass"
                        )
                    } description: {
                        if appState.isRefreshingWorkspaceCatalog {
                            Text("Scholium is preparing the Triptych catalog.")
                        } else if let error = appState.workspaceCatalogError,
                                  appState.workspaceCatalog == nil {
                            Text("The Triptych catalog is unavailable. \(error)")
                        } else if appState.workspaceCatalog == nil {
                            Text("The Triptych catalog is unavailable.")
                        } else if query.isEmpty {
                            Text("Add a note to Analyses, Topics, or Works.")
                        } else {
                            Text("No title, path, or alias matches \"\(query)\".")
                        }
                    } actions: {
                        if appState.workspaceCatalog == nil,
                           !appState.isRefreshingWorkspaceCatalog {
                            Button("Retry") {
                                Task { await appState.refreshWorkspaceCatalog() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Go to Note")
            .searchable(
                text: $query,
                placement: .toolbar,
                prompt: "Title, path, or alias"
            )
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { openSelectedResult() }
            .onExitCommand { dismiss() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(width: 520, height: 420)
        .accessibilityIdentifier("scholium.quickOpen")
        .onAppear { searchFocused = true }
        .task(id: QuickOpenRequest(query: query, generatedAt: appState.workspaceCatalog?.generatedAt)) {
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            results = appState.quickOpenResults(for: query)
            selectedResultID = results.first?.id
        }
        .onMoveCommand { direction in
            guard !results.isEmpty else { return }
            let currentIndex = selectedResultID.flatMap { selectedID in
                results.firstIndex(where: { $0.id == selectedID })
            } ?? 0
            switch direction {
            case .down:
                selectedResultID = results[min(results.count - 1, currentIndex + 1)].id
            case .up:
                selectedResultID = results[max(0, currentIndex - 1)].id
            default:
                break
            }
        }
    }

    private func openSelectedResult() {
        guard let selectedResultID,
              let note = results.first(where: { $0.id == selectedResultID }) else { return }
        open(note)
    }

    private func open(_ note: WorkspaceCatalogNote) {
        appState.requestOpenNote(note.reference)
        dismiss()
    }
}

// MARK: - Quick Open Row

private struct QuickOpenRow: View {
    let title: String
    let vaultRole: VaultRole
    let relativePath: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: vaultRole.quickOpenSymbolName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(vaultRole.displayName) · \(relativePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct QuickOpenRequest: Hashable {
    let query: String
    let generatedAt: Date?
}

private extension VaultRole {
    var quickOpenSymbolName: String {
        switch self {
        case .sourceCorpus: "doc.text"
        case .topicKnowledge: "lightbulb"
        case .dissertationControl, .draftProject: "pencil.and.outline"
        case .other: "doc"
        }
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: AppState.Toast

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
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 1100, height: 700)
}
