import AppKit
import ScholiumContracts
import SwiftUI

private struct ExternalMarkdownComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let value: ExternalMarkdownComparison
    var body: some View {
        ExactSourceComparisonSheetLayout(
            title: "Compare Changes", detail: "Compare the current editor with the exact version now on disk.",
            identifier: "scholium.externalMarkdown.comparison"
        ) {
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        } content: {
            ScrollView {
                if let comparison = try? ExactSourceComparisonBuilder.build(
                    startingData: Data(value.buffer.utf8), endingData: Data(value.disk.utf8),
                    startingRevision: DocumentFingerprint(content: value.buffer), endingRevision: DocumentFingerprint(content: value.disk)
                ) {
                    ExactSourceComparisonView(
                        comparison: comparison, startingLabel: "Current Editor", endingLabel: "Disk Version", startingOnlyLabel: "Current editor only",
                        endingOnlyLabel: "Disk version only", identifierPrefix: "scholium.externalMarkdown.diff")
                } else {
                    Text("Comparison Unavailable")
                }
            }
        } footer: {
            EmptyView()
        }
    }
}

struct ExternalMarkdownWindowView: View {
    @EnvironmentObject private var bootstrap: ApplicationBootstrapController
    @EnvironmentObject private var applicationDelegate: ScholiumApplicationDelegate
    @StateObject private var model: ExternalMarkdownWindowModel
    @State private var confirmsReload = false
    @State private var readReadyDocumentID: String?
    private var documentFind: DocumentFindPresentationModel { model.documentFind }

    init(url: URL, needsOwnershipResolution: Bool = false) {
        _model = StateObject(
            wrappedValue: ExternalMarkdownWindowModel(
                url: url, needsOwnershipResolution: needsOwnershipResolution
            ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading {
                ProgressView("Opening Original Markdown…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = model.snapshot {
                let documentID = model.documentID
                DocumentEditorHost(
                    documentID: documentID,
                    presentsEditor: model.mode != .read,
                    retainsEditor: model.retainsEditor,
                    editorIsReady: model.editorReady
                ) {
                    SafeMarkdownReadWebView(
                        documentID: documentID,
                        documentTitle: model.title,
                        fingerprint: snapshot.fingerprint.sha256,
                        source: snapshot.source,
                        htmlBody: model.readHTML,
                        presentationCSS: ScholiumDocumentPresentationConfiguration(textScale: model.documentTextScale).css,
                        userCSS: "",
                        onLinkClick: { _ in },
                        onOpenExternalURL: { url in
                            WorkspaceStore.openExternal(url) { NSWorkspace.shared.open($0) }
                        },
                        onSelectionChange: { model.acceptReadSelection($0, documentID: documentID, fingerprint: snapshot.fingerprint) },
                        onRenderingFailure: { error in
                            guard model.documentID == documentID, model.snapshot?.fingerprint == snapshot.fingerprint else { return }
                            model.error = error
                        },
                        onRenderingReady: {
                            guard model.documentID == documentID, model.mode == .read, readReadyDocumentID != documentID else { return }
                            readReadyDocumentID = documentID
                            documentFind.refresh()
                        },
                        findRequest: model.mode == .read ? documentFind.request : nil,
                        onFindResult: { requestID, result in
                            guard model.documentID == documentID, model.mode == .read else { return }
                            switch result {
                            case .success(let value): documentFind.accept(value, for: requestID)
                            case .failure(let error): documentFind.fail(error, for: requestID)
                            }
                        }
                    )
                } editor: {
                    MarkdownEditorWebView(
                        session: model.editorSession,
                        documentID: documentID,
                        documentTitle: model.title,
                        performanceDocumentID: documentID,
                        source: snapshot.source,
                        mode: model.mode.editorMode ?? .livePreview,
                        presentationCSS: ScholiumDocumentPresentationConfiguration(textScale: model.documentTextScale).css,
                        userCSS: "",
                        requiresMathRuntime: MarkdownEditorWebView.requiresMathRuntime(linkPreviews: []),
                        linkCompletionQuery: { _, _ in [] }, linkPreviews: [],
                        initialScrollFraction: 0, initialScrollAnchor: nil,
                        onDocumentActivity: { model.sourceChanged() },
                        onRequestSave: { Task { await model.save() } },
                        onRequestFind: handleFindShortcut,
                        onRequestDocumentTitleRename: { _, _ in throw ExternalMarkdownWindowIssue.renameUnavailable },
                        onPasteImage: { _ in false },
                        onLinkActivation: { _ in },
                        onScrollFractionChange: { _ in }, onScrollAnchorChange: { _ in }
                    )
                    .id(model.editorSession.viewReconstructionID)
                }
                .id(documentID)
                .scholiumSurface(.document)
                .overlay {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            DocumentFindOverlay(
                                model: documentFind,
                                allowsReplacement: model.mode != .read,
                                availableWidth: geometry.size.width
                            )
                            GeometryReader { remaining in
                                if hasDocumentNotices {
                                    ScholiumDocumentNoticeStack(availableSize: remaining.size) {
                                        documentNotices
                                    }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                }
                            }
                        }
                    }
                }
            } else {
                ScholiumContentStateView(
                    "Original Markdown Unavailable",
                    detail: Text(verbatim: model.error ?? ScholiumL10n.string("The original file could not be opened.")),
                    indicator: .symbol("exclamationmark.triangle", role: .attention)
                ) {
                    Button("Retry") { Task { await model.open() } }
                    Button("Choose Original…") { model.asksForAccess = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .navigationTitle(model.title)
        .navigationSubtitle(ScholiumL10n.string("Outside Triptych"))
        .preferredColorScheme(model.colorScheme.swiftUIColorScheme)
        .toolbar {
            ToolbarItem(id: "external-mode", placement: .primaryAction) {
                Menu {
                    ForEach(NotePresentationMode.allCases) { mode in
                        Toggle(
                            ScholiumL10n.dynamicString(mode.title),
                            isOn: Binding(
                                get: { model.mode == mode },
                                set: { if $0 { model.selectMode(mode) } }
                            )
                        )
                        .disabled(!model.canSelectMode(mode))
                    }
                } label: {
                    Label(ScholiumL10n.dynamicString(model.mode.title), systemImage: "doc.text")
                }
                .labelStyle(.titleOnly)
                .disabled(model.isBusy || model.snapshot == nil || model.editorSession.isComposing)
                .help("Document Mode")
                .accessibilityLabel("Document Mode")
                .accessibilityValue(Text(ScholiumL10n.dynamicString(model.mode.title)))
                .accessibilityIdentifier("scholium.externalMarkdown.mode")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Find", systemImage: "magnifyingglass") { documentFind.present() }
                    .disabled(model.snapshot == nil)
                    .accessibilityIdentifier("scholium.externalMarkdown.find")
                Menu {
                    Button("Save") { Task { await model.save() } }
                        .disabled(!model.canSave)
                    Button("Find") { documentFind.present() }
                        .disabled(model.snapshot == nil)
                    Divider()
                    Button("Reveal Original in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.originalURL])
                    }
                    Button("Close Window") { model.closeWindow() }
                        .disabled(!model.canRequestClose)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .help("More")
                .accessibilityIdentifier("scholium.externalMarkdown.more")
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(id: "external-import", placement: .primaryAction) {
                Button("Import to Triptych…") { model.showsImport = true }
                    .buttonStyle(.borderedProminent)
                    .tint(ScholiumNativeColorRole.controlAccent.color)
                    .disabled(!model.canPresentImport)
                    .accessibilityIdentifier("scholium.externalMarkdown.import")
            }
        }
        .focusedSceneObject(model)
        .focusedSceneValue(\.scholiumApplicationBootstrapStatus, ScholiumApplicationBootstrapStatus(isReady: bootstrap.isReady))
        .confirmationDialog("Discard changes and reload the original file?", isPresented: $confirmsReload) {
            Button("Reload from Disk", role: .destructive) { Task { await model.reloadFromDisk() } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $model.showsImport) { ExternalMarkdownImportView(original: model) }
        .sheet(item: $model.comparison) { ExternalMarkdownComparisonView(value: $0) }
        .background(ExternalMarkdownWindowAttachment(model: model))
        .fileImporter(
            isPresented: $model.asksForAccess,
            allowedContentTypes: [MarkdownFileOpeningController.contentType]
        ) { result in
            if case .success(let url) = result { Task { await model.open(using: url) } }
        }
        .onAppear { ExternalMarkdownWindowRegistry.shared.register(model) }
        .task { if model.snapshot == nil { await model.open() } }
        .task(id: model.editorFocusExecutionID) { await model.focusEditorIfPresented() }
        .onChange(of: model.mode) { _, _ in documentFind.refresh() }
        .onChange(of: model.editorSession.isLoaded) { _, loaded in
            if loaded { documentFind.refresh() }
        }
        .onChange(of: model.snapshot?.fingerprint) { _, _ in documentFind.refresh() }
        .task(id: documentFind.request) {
            guard let request = documentFind.request, model.mode != .read else { return }
            let documentID = model.documentID
            let editor = model.editorSession
            let mode = model.mode
            if case .clear = request.operation {
                await editor.clearDocumentFind()
                return
            }
            guard editor.isLoaded, let query = request.editorQuery else { return }
            do {
                let result = try await editor.performDocumentFind(query)
                guard !Task.isCancelled, model.documentID == documentID, model.editorSession === editor, model.mode == mode else { return }
                documentFind.accept(result, for: request.id)
            } catch {
                guard !Task.isCancelled, model.documentID == documentID, model.editorSession === editor, model.mode == mode else { return }
                documentFind.fail(error, for: request.id)
            }
        }
        .onDisappear {
            ExternalMarkdownWindowRegistry.shared.unregister(model)
            model.close()
        }
    }

    private var hasDocumentNotices: Bool {
        !model.permitsSourceActions || model.error != nil || model.inputResumeError != nil || model.mode != .read && model.editorSession.errorMessage != nil
            || model.citationPresentation?.isVisible == true
    }

    @ViewBuilder
    private var documentNotices: some View {
        if let presentation = model.citationPresentation {
            DocumentCitationNotice(
                presentation: presentation,
                dismiss: model.editorSession.dismissCitationStatus,
                refresh: {
                    Task { @MainActor in
                        guard model.citationPresentation?.canRefresh == true else { return }
                        do { try await model.editorSession.perform(.refreshCitations) } catch {
                            await model.editorSession.announceCitationStatus(ScholiumErrorLocalization.message(error))
                        }
                    }
                },
                openSource: { model.selectMode(.source) }
            )
        }
        if !model.permitsSourceActions {
            ScholiumDocumentStatusNotice(
                ScholiumL10n.string("Reading Only"),
                detail: ScholiumL10n.string(
                    model.managedNote == nil
                        ? "This file is open for reading. Retry to enable editing and Import."
                        : "This file is a Triptych Note. Open Note to use its Triptych."
                ), kind: .attention
            ) {
                if model.managedNote != nil {
                    Button("Open Note") {
                        Task {
                            do { try await applicationDelegate.markdownFiles.openManagedPreview(model) } catch {
                                model.error = ScholiumErrorLocalization.message(error)
                            }
                        }
                    }.disabled(!model.canOpenManagedNote)
                } else {
                    Button("Retry") {
                        Task { await applicationDelegate.markdownFiles.retryExternalOwnership(model) }
                    }.disabled(!model.canRetryOwnership)
                }
            }
            .accessibilityIdentifier("scholium.externalMarkdown.readingOnly")
        }
        if let error = model.error {
            ScholiumDocumentStatusNotice(
                ScholiumL10n.string(model.hasConflict ? "Conflict" : "Error"), detail: error,
                kind: .attention
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack { fileRepairActions }
                    VStack(alignment: .leading) { fileRepairActions }
                }
                .disabled(model.isBusy)
            }
            .accessibilityIdentifier("scholium.externalMarkdown.issue")
        }
        if let error = model.inputResumeError {
            ScholiumDocumentStatusNotice(ScholiumL10n.string("Editor Unavailable"), detail: error, kind: .attention) {
                Button("Resume Editing") { Task { await model.resumeInput() } }
                    .disabled(!model.canResumeInput)
                if !model.editorSession.isLoaded {
                    Button("Retry Editor") { model.editorSession.retryUnavailablePresentation() }
                        .disabled(model.isBusy)
                }
            }
            .accessibilityIdentifier("scholium.externalMarkdown.inputRecovery")
        }
        if model.inputResumeError == nil, model.mode != .read, let error = model.editorSession.errorMessage {
            ScholiumDocumentStatusNotice(ScholiumL10n.string("Editor Unavailable"), detail: error, kind: .attention) {
                if !model.editorSession.isLoaded {
                    Button("Retry Editor") { model.editorSession.retryUnavailablePresentation() }
                        .disabled(model.isBusy)
                }
            }
        }
    }

    @ViewBuilder
    private var fileRepairActions: some View {
        if model.hasConflict {
            Button("Compare Changes") { Task { await model.compareChanges() } }
        }
        Button("Reload from Disk") {
            if model.isDirty || model.retainsEditor { confirmsReload = true } else { Task { await model.reloadFromDisk() } }
        }
        if model.needsFileAccess { Button("Choose Original…") { model.asksForAccess = true } }
    }

    private func handleFindShortcut(_ shortcut: DocumentFindShortcut) {
        model.performFind(shortcut)
    }
}

private struct ExternalMarkdownWindowAttachment: NSViewRepresentable {
    let model: ExternalMarkdownWindowModel

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = model.attach(to:)
        return view
    }

    func updateNSView(_ view: WindowAttachmentView, context: Context) {
        view.onWindowAttachment = model.attach(to:)
        if let window = view.window { model.attach(to: window) }
    }
}
