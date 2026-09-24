import AppKit
import Combine
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

struct ExternalMarkdownWindowRoute: Codable, Hashable {
    let fileURL: URL
}

private enum ExternalMarkdownWindowIssue: LocalizedError {
    case renameUnavailable
    case unsaved

    var errorDescription: String? {
        switch self {
        case .renameUnavailable: "Rename this external file in Finder, then reopen it."
        case .unsaved: "The external Markdown window could not be saved. Its edits remain open."
        }
    }
}

@MainActor
final class ExternalMarkdownWindowRegistry {
    static let shared = ExternalMarkdownWindowRegistry()
    private var models: [ObjectIdentifier: ExternalMarkdownWindowModel] = [:]

    var hasOpenWindows: Bool { !models.isEmpty }

    func register(_ model: ExternalMarkdownWindowModel) {
        models[ObjectIdentifier(model)] = model
    }

    func unregister(_ model: ExternalMarkdownWindowModel) {
        models.removeValue(forKey: ObjectIdentifier(model))
    }

    func flushAll() async throws {
        for model in Array(models.values) where model.isDirty {
            guard await model.save() else { throw ExternalMarkdownWindowIssue.unsaved }
        }
    }
}

@MainActor
final class ExternalMarkdownWindowModel: NSObject, ObservableObject, NSWindowDelegate {
    let originalURL: URL
    let editorSession = MarkdownEditorSession()
    @Published private(set) var snapshot: ExternalMarkdownFileSnapshot?
    @Published private(set) var readHTML = ""
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published var mode: NotePresentationMode = .read
    @Published var error: String?
    @Published var asksForAccess = false
    private var fileSession: ExternalMarkdownFileSession?
    private var editorObservation: AnyCancellable?
    private var openingID = UUID()
    private var didAllocateEditor = false
    private var pendingAcknowledgement: (MarkdownEditorPersistenceSnapshot, ExternalMarkdownFileSnapshot)?
    private var closeAuthorized = false
    private weak var window: NSWindow?
    private weak var previousDelegate: (any NSWindowDelegate)?

    init(url: URL) {
        originalURL = url.standardizedFileURL
        super.init()
        editorObservation = editorSession.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var title: String { originalURL.lastPathComponent }
    var documentID: String { "external:\(originalURL.path):\(openingID.uuidString)" }
    var isDirty: Bool { editorSession.isDirty || editorSession.hasRecoverableBuffer }
    var canSave: Bool { snapshot != nil && fileSession != nil && isDirty && !isSaving }
    var retainsEditor: Bool { didAllocateEditor }
    var editorReady: Bool {
        editorSession.isLoaded && editorSession.presentedMode == mode.editorMode
    }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        if let current = self.window, current.delegate === self {
            current.delegate = previousDelegate
        }
        self.window = window
        previousDelegate = window.delegate
        window.delegate = self
        window.isDocumentEdited = isDirty
    }

    func open(using selectedURL: URL? = nil) async {
        guard !isSaving else { return }
        isLoading = true
        error = nil
        let accessURL = selectedURL ?? originalURL
        guard accessURL.standardizedFileURL == originalURL else {
            error = "Select the same original Markdown file. Chat's captured copy is unchanged."
            isLoading = false
            return
        }
        do {
            let opened = try await Task.detached(priority: .userInitiated) {
                try ExternalMarkdownFileSession.open(accessURL)
            }.value
            if let old = fileSession { await old.close() }
            fileSession = opened.session
            install(opened.snapshot)
            asksForAccess = false
        } catch {
            self.error = error.localizedDescription
            asksForAccess = error as? ExternalMarkdownFileError == .permissionDenied
        }
        isLoading = false
    }

    private func install(_ loaded: ExternalMarkdownFileSnapshot) {
        snapshot = loaded
        readHTML =
            SafeMarkdownRenderer.render(
                NoteDocument(relativePath: title, rawContent: loaded.source)
            ).htmlBody
        openingID = UUID()
        mode = .read
        didAllocateEditor = false
        window?.isDocumentEdited = false
        error = nil
    }

    func selectMode(_ requested: NotePresentationMode) {
        guard requested != mode else { return }
        if requested == .read && isDirty {
            Task { @MainActor in
                if await save() { mode = .read }
            }
            return
        }
        if requested != .read { didAllocateEditor = true }
        mode = requested
    }

    @discardableResult
    func save() async -> Bool {
        guard !isSaving, let snapshot, let fileSession else { return false }
        if !isDirty { return true }
        isSaving = true
        defer { isSaving = false }
        do {
            var baseSnapshot = snapshot
            if let pendingAcknowledgement {
                let acknowledgement = try await editorSession.acknowledgePersistenceSnapshot(
                    pendingAcknowledgement.0,
                    committedText: pendingAcknowledgement.0.text,
                    fingerprint: pendingAcknowledgement.1.fingerprint
                )
                self.pendingAcknowledgement = nil
                window?.isDocumentEdited = acknowledgement == .superseded
                if acknowledgement == .clean {
                    error = nil
                    return true
                }
                baseSnapshot = pendingAcknowledgement.1
            }
            let candidate = try await editorSession.persistenceSnapshot(expectedRevision: baseSnapshot.fingerprint)
            let committed = try await fileSession.save(candidate: candidate.text, expected: baseSnapshot)
            pendingAcknowledgement = (candidate, committed)
            self.snapshot = committed
            readHTML =
                SafeMarkdownRenderer.render(
                    NoteDocument(relativePath: title, rawContent: committed.source)
                ).htmlBody
            let acknowledgement = try await editorSession.acknowledgePersistenceSnapshot(
                candidate, committedText: candidate.text, fingerprint: committed.fingerprint)
            pendingAcknowledgement = nil
            window?.isDocumentEdited = acknowledgement == .superseded
            error = nil
            return acknowledgement == .clean
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func sourceChanged() {
        window?.isDocumentEdited = isDirty
        objectWillChange.send()
    }

    func refreshIfClean() async {
        guard !isLoading, !isSaving, !isDirty, let fileSession, let snapshot else { return }
        do {
            let current = try await fileSession.load()
            if current.fingerprint != snapshot.fingerprint { install(current) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func close() {
        if let window, window.delegate === self { window.delegate = previousDelegate }
        window = nil
        previousDelegate = nil
        if let fileSession { Task { await fileSession.close() } }
        fileSession = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeAuthorized {
            closeAuthorized = false
            return true
        }
        guard !isSaving else { return false }
        guard isDirty else { return previousDelegate?.windowShouldClose?(sender) ?? true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(title)?"
        alert.informativeText = "This is the original file outside your Triptych. Chat's supplied snapshot will not change."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            guard let self, let sender else { return }
            if response == .alertFirstButtonReturn {
                Task { @MainActor in
                    if await self.save() { self.finishClose(sender) }
                }
            } else if response == .alertThirdButtonReturn {
                self.finishClose(sender)
            }
        }
        return false
    }

    private func finishClose(_ sender: NSWindow) {
        guard window === sender else { return }
        closeAuthorized = true
        sender.performClose(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Task { await refreshIfClean() }
    }

    override func responds(to selector: Selector!) -> Bool {
        MainActor.assumeIsolated {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        MainActor.assumeIsolated {
            if previousDelegate?.responds(to: selector) == true {
                return UncheckedForwardingTarget(value: previousDelegate)
            }
            return UncheckedForwardingTarget(value: super.forwardingTarget(for: selector))
        }.value
    }
}

private struct UncheckedForwardingTarget: @unchecked Sendable {
    let value: Any?
}

struct ExternalMarkdownWindowView: View {
    @StateObject private var model: ExternalMarkdownWindowModel
    @StateObject private var documentFind = DocumentFindPresentationModel()

    init(url: URL) {
        _model = StateObject(wrappedValue: ExternalMarkdownWindowModel(url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(model.title, systemImage: "doc.text")
                    .font(.headline)
                    .lineLimit(1)
                    .help(model.originalURL.path)
                Text("Outside Triptych").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { model.mode }, set: { model.selectMode($0) }
                    )
                ) {
                    ForEach(NotePresentationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Button("Find") { documentFind.present() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Save") { Task { await model.save() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.canSave)
            }
            .padding()
            Divider()
            if model.isLoading {
                ProgressView("Opening Original Markdown…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let snapshot = model.snapshot {
                DocumentEditorHost(
                    documentID: model.documentID,
                    presentsEditor: model.mode != .read,
                    retainsEditor: model.retainsEditor,
                    editorIsReady: model.editorReady
                ) {
                    SafeMarkdownReadWebView(
                        documentID: model.documentID,
                        documentTitle: model.title,
                        fingerprint: snapshot.fingerprint.sha256,
                        source: snapshot.source,
                        htmlBody: model.readHTML,
                        presentationCSS: ScholiumDocumentPresentationConfiguration(textScale: 1).css,
                        userCSS: "",
                        onLinkClick: { _ in }, onOpenExternalURL: { NSWorkspace.shared.open($0) },
                        onRenderingFailure: { model.error = $0 },
                        findRequest: model.mode == .read ? documentFind.request : nil,
                        onFindResult: { requestID, result in
                            switch result {
                            case .success(let value): documentFind.accept(value, for: requestID)
                            case .failure(let error): documentFind.fail(error, for: requestID)
                            }
                        }
                    )
                } editor: {
                    MarkdownEditorWebView(
                        session: model.editorSession,
                        documentID: model.documentID,
                        documentTitle: model.title,
                        performanceDocumentID: model.documentID,
                        source: snapshot.source,
                        mode: model.mode.editorMode ?? .livePreview,
                        presentationCSS: ScholiumDocumentPresentationConfiguration(textScale: 1).css,
                        userCSS: "",
                        requiresMathRuntime: MarkdownEditorWebView.requiresMathRuntime(source: snapshot.source, linkPreviews: []),
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
                }
                .scholiumSurface(.document)
                .overlay {
                    GeometryReader { geometry in
                        DocumentFindOverlay(
                            model: documentFind,
                            allowsReplacement: model.mode != .read,
                            availableWidth: geometry.size.width
                        )
                    }
                }
            } else {
                ScholiumContentStateView(
                    "Original Markdown Unavailable",
                    detail: Text(model.error ?? "The original file could not be opened."),
                    indicator: .symbol("exclamationmark.triangle", role: .attention)
                ) {
                    Button("Retry") { Task { await model.open() } }
                    Button("Choose Original…") { model.asksForAccess = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = model.error, model.snapshot != nil {
                Text(error).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
        }
        .navigationTitle(model.title)
        .background(ExternalMarkdownWindowAttachment(model: model))
        .fileImporter(
            isPresented: $model.asksForAccess,
            allowedContentTypes: [UTType(filenameExtension: "md") ?? .plainText]
        ) { result in
            if case .success(let url) = result { Task { await model.open(using: url) } }
        }
        .onAppear { ExternalMarkdownWindowRegistry.shared.register(model) }
        .task { if model.snapshot == nil { await model.open() } }
        .task(id: documentFind.request) {
            guard let request = documentFind.request, model.mode != .read else { return }
            if case .clear = request.operation {
                await model.editorSession.clearDocumentFind()
                return
            }
            guard let query = request.editorQuery else { return }
            do {
                let result = try await model.editorSession.performDocumentFind(query)
                documentFind.accept(result, for: request.id)
            } catch {
                documentFind.fail(error, for: request.id)
            }
        }
        .onDisappear {
            ExternalMarkdownWindowRegistry.shared.unregister(model)
            model.close()
        }
    }

    private func handleFindShortcut(_ shortcut: DocumentFindShortcut) {
        switch shortcut {
        case .present: documentFind.present()
        case .next: documentFind.next()
        case .previous: documentFind.previous()
        case .useSelection:
            Task { @MainActor in
                let selection = try? await model.editorSession.currentSelection()
                documentFind.useSelection(selection?.excerpt)
            }
        }
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
