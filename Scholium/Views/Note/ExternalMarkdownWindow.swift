import AppKit
import Combine
import Darwin
import ScholiumApplication
import ScholiumContracts
import SwiftUI
import UniformTypeIdentifiers

struct ExternalMarkdownWindowRoute: Codable, Hashable {
    let fileURL: URL
    let needsOwnershipResolution: Bool

    init(fileURL: URL, needsOwnershipResolution: Bool = false) {
        self.fileURL = fileURL
        self.needsOwnershipResolution = needsOwnershipResolution
    }
}

enum ExternalMarkdownOwnershipState {
    case external
    case unresolved
    case managed(VaultNoteReference, triptychID: UUID)
}

struct ExternalMarkdownImportResult {
    let reference: VaultNoteReference
    let triptychID: UUID
    var message: String?
    let requiresRecovery: Bool
    var recoveryRecord: TriptychMutationRecoveryRecord?
    var persistenceFailure: String?
}

enum ExternalMarkdownWindowIssue: LocalizedError {
    case renameUnavailable
    case unsaved

    var errorDescription: String? {
        switch self {
        case .renameUnavailable: ScholiumL10n.string("Rename this external file in Finder, then reopen it.")
        case .unsaved: ScholiumL10n.string("The external Markdown window could not be saved. Its edits remain open.")
        }
    }
}

@MainActor
final class ExternalMarkdownWindowRegistry {
    static let shared = ExternalMarkdownWindowRegistry()
    private var models: [ObjectIdentifier: ExternalMarkdownWindowModel] = [:]
    private let policy: ScholiumLifecyclePolicy

    init(policy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy()) {
        self.policy = policy
    }

    var hasOpenWindows: Bool { !models.isEmpty }

    func register(_ model: ExternalMarkdownWindowModel) {
        if model.snapshot == nil, !model.isDirty,
            let existing = models.values.first(where: {
                $0 !== model && Self.referToSameFile($0.originalURL, model.originalURL)
            })
        {
            existing.reveal(displaying: model.originalURL)
            model.closeUnopenedDuplicate()
            return
        }
        models[ObjectIdentifier(model)] = model
    }

    func unregister(_ model: ExternalMarkdownWindowModel) {
        models.removeValue(forKey: ObjectIdentifier(model))
    }

    func reveal(_ url: URL) -> Bool {
        guard let model = models.values.first(where: { Self.referToSameFile($0.originalURL, url) })
        else { return false }
        model.reveal(displaying: url)
        return true
    }

    func closeForManagedOpen(_ url: URL) throws {
        guard let model = models.values.first(where: { Self.referToSameFile($0.originalURL, url) })
        else { return }
        guard !model.retainsEditor, !model.isDirty, !model.isBusy else {
            model.reveal()
            throw ScholiumFileSelectionError.rejectedSelection(
                message: ScholiumL10n.string(
                    "Close the external Markdown window before opening this file as a Triptych Note."))
        }
        model.closeWindow()
    }

    /// Routing evidence only: equivalent paths may reveal a retained session,
    /// but never change its original path, revision, or write authorization.
    static func referToSameFile(_ first: URL, _ second: URL) -> Bool {
        guard first.isFileURL, second.isFileURL else { return false }
        if first.standardizedFileURL == second.standardizedFileURL { return true }
        guard let firstIdentity = routingIdentity(at: first),
            let secondIdentity = routingIdentity(at: second)
        else { return false }
        return firstIdentity == secondIdentity
    }

    private struct RoutingFileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
        let parentDevice: dev_t
        let parentInode: ino_t
    }

    private static func routingIdentity(at selectedURL: URL) -> RoutingFileIdentity? {
        let scoped = selectedURL.startAccessingSecurityScopedResource()
        defer { if scoped { selectedURL.stopAccessingSecurityScopedResource() } }
        let url = selectedURL.standardizedFileURL
        let parentURL = url.deletingLastPathComponent()
        let directory = Darwin.open(parentURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { return nil }
        defer { Darwin.close(directory) }
        var parent = stat()
        var namedParent = stat()
        guard fstat(directory, &parent) == 0,
            lstat(parentURL.path, &namedParent) == 0,
            (parent.st_mode & S_IFMT) == S_IFDIR,
            (namedParent.st_mode & S_IFMT) == S_IFDIR,
            parent.st_dev == namedParent.st_dev, parent.st_ino == namedParent.st_ino
        else { return nil }
        let descriptor = openat(directory, url.lastPathComponent, O_EVTONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var opened = stat()
        var named = stat()
        guard fstat(descriptor, &opened) == 0,
            fstatat(directory, url.lastPathComponent, &named, AT_SYMLINK_NOFOLLOW) == 0,
            (opened.st_mode & S_IFMT) == S_IFREG, opened.st_nlink == 1,
            (named.st_mode & S_IFMT) == S_IFREG, named.st_nlink == 1,
            opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
            lstat(parentURL.path, &namedParent) == 0,
            (namedParent.st_mode & S_IFMT) == S_IFDIR,
            parent.st_dev == namedParent.st_dev, parent.st_ino == namedParent.st_ino
        else { return nil }
        return RoutingFileIdentity(
            device: opened.st_dev, inode: opened.st_ino,
            parentDevice: parent.st_dev, parentInode: parent.st_ino)
    }

    func flushAll() async throws {
        let current = Array(models.values)
        do {
            try await withScholiumLifecycleDeadline(
                phase: .applicationTermination, timeout: policy.applicationTermination
            ) { [policy] in
                var firstError: (any Error)?
                let concurrency = max(1, policy.maximumConcurrentWindowFlushes)
                for start in stride(from: 0, to: current.count, by: concurrency) {
                    try Task.checkCancellation()
                    let end = min(start + concurrency, current.count)
                    let tasks = current[start..<end].map { model in
                        Task { @MainActor in
                            do {
                                try await withScholiumLifecycleDeadline(
                                    phase: .contentFlush, timeout: policy.contentFlush
                                ) {
                                    guard await model.prepareTermination() else {
                                        throw ExternalMarkdownWindowIssue.unsaved
                                    }
                                }
                            } catch {
                                if !Task.isCancelled {
                                    if model.error == nil || error is ScholiumWindowLifecycleError {
                                        model.error = ScholiumErrorLocalization.message(error)
                                    }
                                    model.reveal()
                                }
                                throw error
                            }
                        }
                    }
                    try await withTaskCancellationHandler {
                        for task in tasks {
                            do { try await task.value } catch {
                                if firstError == nil { firstError = error }
                            }
                        }
                        try Task.checkCancellation()
                    } onCancel: {
                        for task in tasks { task.cancel() }
                    }
                }
                if let firstError { throw firstError }
            }
        } catch {
            if error as? ScholiumWindowLifecycleError == .timedOut(.applicationTermination) {
                for model in current where model.isPreparingTermination {
                    model.error = ScholiumErrorLocalization.message(error)
                    model.reveal()
                }
            }
            for model in current { await model.resumeInput() }
            throw error
        }
    }
}

@MainActor
final class ExternalMarkdownWindowModel: NSObject, ObservableObject, NSWindowDelegate {
    typealias OpenFile =
        @Sendable (URL) async throws -> (
            session: ExternalMarkdownFileSession, snapshot: ExternalMarkdownFileSnapshot
        )
    let originalURL: URL
    private let grantedURL: URL
    private(set) var editorSession: MarkdownEditorSession
    private let openFile: OpenFile
    private let isApplicationActive: @MainActor () -> Bool
    @Published private(set) var snapshot: ExternalMarkdownFileSnapshot?
    @Published private(set) var readHTML = ""
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var documentTextScale = ScholiumMetrics.Document.defaultTextScale
    @Published var colorScheme: WindowColorSchemeChoice = .system
    @Published private(set) var inputResumeError: String?
    @Published private(set) var isResumingInput = false
    @Published var mode: NotePresentationMode = .read
    @Published private(set) var ownership: ExternalMarkdownOwnershipState
    @Published private(set) var isResolvingOwnership = false
    @Published var error: String?
    @Published var asksForAccess = false
    @Published private(set) var needsFileAccess = false
    @Published var showsImport = false
    @Published var pendingImport: ExternalMarkdownImportResult?
    @Published private(set) var isImporting = false
    @Published var importCommitInProgress = false {
        didSet { if !importCommitInProgress { refreshAfterOperation() } }
    }
    @Published private(set) var hasConflict = false
    @Published var comparison: ExternalMarkdownComparison?
    let documentFind = DocumentFindPresentationModel()
    private var fileSession: ExternalMarkdownFileSession?
    private var editorObservation: AnyCancellable?
    private var findObservation: AnyCancellable?
    private var findFocusObservation: AnyCancellable?
    private var openingID = UUID()
    private var didAllocateEditor = false
    private var pendingAcknowledgement: (MarkdownEditorPersistenceSnapshot, ExternalMarkdownFileSnapshot)?
    private var closeAuthorized = false
    private var closesOnAttachment = false
    private var isClosed = false
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    @Published private(set) var isRefreshing = false
    private var openingTaskID: UUID?
    @Published private(set) var isPreparingClose = false
    @Published private(set) var isTerminating = false
    @Published private(set) var isPreparingTermination = false
    @Published private(set) var isChangingMode = false
    private var modeTransitionTask: Task<Void, Never>?
    private struct EditorFocusIntent {
        let id = UUID()
        let documentID: String
        let editor: MarkdownEditorSession
        let mode: NotePresentationMode
        let focusRevision: UInt64
        weak var responder: NSResponder?
    }
    private var editorFocusIntent: EditorFocusIntent?
    private var inputSuspensionID: String?
    @Published private var displayFilename: String?
    private struct BoundReadSelection {
        let documentID: String
        let fingerprint: DocumentFingerprint
        let value: MarkdownReviewSelection
    }
    private var readSelection: BoundReadSelection?
    private weak var window: NSWindow?
    private weak var previousDelegate: (any NSWindowDelegate)?

    init(
        url: URL, needsOwnershipResolution: Bool = false,
        editorSession: MarkdownEditorSession = MarkdownEditorSession(),
        isApplicationActive: @escaping @MainActor () -> Bool = { NSApp.isActive },
        openFile: @escaping OpenFile = { url in
            try await Task.detached(priority: .userInitiated) {
                try ExternalMarkdownFileSession.open(url)
            }.value
        }
    ) {
        originalURL = url.standardizedFileURL
        ownership = needsOwnershipResolution ? .unresolved : .external
        grantedURL = url
        self.editorSession = editorSession
        self.isApplicationActive = isApplicationActive
        self.openFile = openFile
        super.init()
        observeEditor()
        findObservation = documentFind.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
        findFocusObservation = documentFind.$focusRequestID.dropFirst().sink { [weak self] _ in
            self?.editorFocusIntent = nil
        }
    }

    private func observeEditor() {
        editorObservation = editorSession.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var title: String { displayFilename ?? originalURL.lastPathComponent }
    var documentID: String { "external:\(originalURL.path):\(openingID.uuidString)" }
    var isDirty: Bool { editorSession.isDirty || editorSession.hasRecoverableBuffer }
    var permitsSourceActions: Bool {
        if case .external = ownership { return true }
        return false
    }
    var canRetryOwnership: Bool {
        guard !isClosed, snapshot != nil, !isBusy, !isResolvingOwnership else { return false }
        if case .unresolved = ownership { return true }
        return false
    }
    var managedNote: (reference: VaultNoteReference, triptychID: UUID)? {
        if case .managed(let reference, let triptychID) = ownership { return (reference, triptychID) }
        return nil
    }
    var canOpenManagedNote: Bool { !isClosed && !isBusy && !isResolvingOwnership && managedNote != nil }

    func retryOwnership(
        using classify: @MainActor () async throws -> ExternalMarkdownOwnershipState
    ) async {
        guard canRetryOwnership, let fileSession, let snapshot else { return }
        isResolvingOwnership = true
        defer { isResolvingOwnership = false }
        do {
            let resolved = try await classify()
            try Task.checkCancellation()
            guard !isClosed else { return }
            let current = try await fileSession.load()
            try Task.checkCancellation()
            guard !isClosed else { return }
            guard current.identity == snapshot.identity, current.fingerprint == snapshot.fingerprint else {
                throw ExternalMarkdownFileError.changed
            }
            ownership = resolved
        } catch {
            guard !isClosed, !Task.isCancelled else { return }
            // Ownership failure leaves the reading-only notice and its Retry.
            // Source failures retain their existing exact-file repair routes.
            if error is ExternalMarkdownFileError {
                self.error = ScholiumErrorLocalization.message(error)
            }
        }
    }
    private var operationInProgress: Bool {
        isLoading || openingTaskID != nil || isSaving || isImporting || isRefreshing
            || importCommitInProgress || isResumingInput
    }
    var isBusy: Bool {
        operationInProgress || isPreparingClose || isTerminating || isPreparingTermination
            || isChangingMode
    }
    var canRequestClose: Bool {
        !isClosed && (!isBusy && !editorSession.isComposing || isLoading && snapshot == nil && !isPreparingClose && !isTerminating)
    }
    var canSave: Bool {
        permitsSourceActions && snapshot != nil && fileSession != nil && (isDirty || retainsEditor && editorReady) && !isBusy
            && !hasConflict && !editorSession.isComposing
            && inputResumeError == nil
    }
    var canImport: Bool {
        permitsSourceActions && snapshot != nil && fileSession != nil && !isBusy && !hasConflict && !editorSession.isComposing
            && pendingImport == nil && inputResumeError == nil
    }
    var canPresentImport: Bool { permitsSourceActions && !isClosed && (canImport || pendingImport != nil && !isBusy) }
    var retainsEditor: Bool { didAllocateEditor }
    var editorReady: Bool {
        editorSession.isLoaded && editorSession.presentedMode == mode.editorMode
    }
    var editorFocusExecutionID: UUID? { editorReady ? editorFocusIntent?.id : nil }

    func focusEditorIfPresented() async {
        guard editorReady, let intent = editorFocusIntent, let editorMode = intent.mode.editorMode else { return }
        var waitsForIdle = false
        defer { if !waitsForIdle, editorFocusIntent?.id == intent.id { editorFocusIntent = nil } }
        // SwiftUI must first reveal the acknowledged native editor surface.
        // Recheck the one-shot intent after that presentation boundary.
        await Task.yield()
        guard !Task.isCancelled else { return }
        guard !isBusy else {
            waitsForIdle = true
            return
        }
        try? await intent.editor.focusIfPresented(
            in: editorMode, requiringFocusRevision: intent.focusRevision
        ) { [weak self] in
            guard let self, !self.isClosed,
                self.editorFocusIntent?.id == intent.id,
                self.documentID == intent.documentID, self.editorSession === intent.editor,
                self.mode == intent.mode, self.isApplicationActive(),
                !self.documentFind.isPresented, !self.showsImport, self.comparison == nil,
                let window = self.window, intent.editor.webView?.window === window,
                window.firstResponder === intent.responder || window.firstResponder == nil || window.firstResponder === window
                    || intent.editor.hasWritingFocus
            else { return false }
            guard !self.isBusy else {
                waitsForIdle = true
                return false
            }
            return self.error == nil && !self.hasConflict && self.inputResumeError == nil
                && intent.editor.detachmentSuspensionID == nil
        }
    }

    var canResumeInput: Bool {
        !isClosed && inputResumeError != nil && !isBusy && editorSession.isReady
            && editorSession.isLoaded
            && (inputSuspensionID ?? editorSession.detachmentSuspensionID) != nil
    }

    func canSelectMode(_ requested: NotePresentationMode) -> Bool {
        guard !isClosed, snapshot != nil, fileSession != nil, !isBusy,
            !editorSession.isComposing, inputResumeError == nil
        else { return false }
        guard permitsSourceActions || requested == .read else { return false }
        if requested == .read {
            return !hasConflict && (mode == .read || !retainsEditor || editorReady)
        }
        return true
    }

    func setDocumentTextScale(_ requestedScale: Double) {
        let adjusted = min(
            ScholiumMetrics.Document.maximumTextScale,
            max(ScholiumMetrics.Document.minimumTextScale, requestedScale))
        documentTextScale = (adjusted * 10).rounded() / 10
    }

    func adjustDocumentTextScale(by amount: Double) {
        setDocumentTextScale(documentTextScale + amount)
    }

    func resetDocumentTextScale() { documentTextScale = ScholiumMetrics.Document.defaultTextScale }

    func attach(to window: NSWindow) {
        if closesOnAttachment {
            window.close()
            return
        }
        guard self.window !== window else { return }
        if let current = self.window, current.delegate === self {
            current.delegate = previousDelegate
        }
        self.window = window
        previousDelegate = window.delegate
        window.delegate = self
        window.representedURL = originalURL
        window.isDocumentEdited = isDirty
    }

    func open(using selectedURL: URL? = nil) async {
        guard !isClosed, openingTaskID == nil, !isSaving, !isImporting, !isRefreshing,
            !importCommitInProgress,
            !isPreparingClose, !isTerminating, !isChangingMode, selectedURL != nil || !isDirty
        else { return }
        let requestID = UUID()
        openingTaskID = requestID
        defer {
            if openingTaskID == requestID {
                openingTaskID = nil
                isLoading = false
                refreshAfterOperation()
            }
        }
        isLoading = snapshot == nil
        error = nil
        let accessURL = selectedURL ?? grantedURL
        guard accessURL.standardizedFileURL == originalURL else {
            error = ScholiumL10n.string("Select the same original Markdown file.")
            isLoading = false
            return
        }
        do {
            let opened = try await openFile(accessURL)
            guard !isClosed, openingTaskID == requestID else {
                await opened.session.close()
                return
            }
            // Fresh user-selected access may repair permissions, but it must
            // not discard a retained editor or silently adopt different bytes.
            if retainsEditor, let snapshot, opened.snapshot.fingerprint != snapshot.fingerprint {
                await opened.session.close()
                hasConflict = true
                error = ScholiumErrorLocalization.message(ExternalMarkdownFileError.changed)
                asksForAccess = false
                return
            }
            if let old = fileSession { await old.close() }
            guard !isClosed, openingTaskID == requestID else {
                await opened.session.close()
                return
            }
            fileSession = opened.session
            if retainsEditor {
                snapshot = opened.snapshot
                if let pendingAcknowledgement {
                    self.pendingAcknowledgement = (pendingAcknowledgement.0, opened.snapshot)
                }
                hasConflict = false
            } else {
                install(opened.snapshot)
            }
            startObservation()
            asksForAccess = false
            needsFileAccess = false
        } catch {
            if Task.isCancelled { return }
            self.error = ScholiumErrorLocalization.message(error)
            asksForAccess = error as? ExternalMarkdownFileError == .permissionDenied
            needsFileAccess = asksForAccess
        }
        isLoading = false
    }

    private func install(_ loaded: ExternalMarkdownFileSnapshot) {
        editorFocusIntent = nil
        let previousMode = mode
        if snapshot != nil {
            editorSession = MarkdownEditorSession()
            observeEditor()
        }
        pendingAcknowledgement = nil
        inputSuspensionID = nil
        inputResumeError = nil
        readSelection = nil
        snapshot = loaded
        readHTML =
            SafeMarkdownRenderer.render(
                NoteDocument(relativePath: title, rawContent: loaded.source)
            ).htmlBody
        openingID = UUID()
        mode = previousMode
        didAllocateEditor = mode != .read
        window?.isDocumentEdited = false
        error = nil
        hasConflict = false
        needsFileAccess = false
    }

    func selectMode(_ requested: NotePresentationMode) {
        guard requested != mode, canSelectMode(requested) else { return }
        editorFocusIntent = nil
        if requested == .read && retainsEditor {
            guard !hasConflict else { return }
            isChangingMode = true
            modeTransitionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await suspendInput()
                    if await save(allowingLifecycle: true), !isClosed {
                        await editorSession.resignFocusAndWait()
                        if !isClosed { mode = .read }
                    }
                } catch { self.error = ScholiumErrorLocalization.message(error) }
                await resumeInput()
                isChangingMode = false
                modeTransitionTask = nil
                refreshAfterOperation()
            }
            return
        }
        guard requested != .read || !hasConflict else { return }
        if requested != .read {
            didAllocateEditor = true
            readSelection = nil
            if let window, window.isKeyWindow, isApplicationActive() {
                editorFocusIntent = EditorFocusIntent(
                    documentID: documentID, editor: editorSession, mode: requested,
                    focusRevision: editorSession.focusRequestRevision, responder: window.firstResponder)
            }
        }
        mode = requested
    }

    func waitForModeTransition() async { await modeTransitionTask?.value }

    @discardableResult
    func save(allowingLifecycle: Bool = false) async -> Bool {
        guard permitsSourceActions, !isClosed, !operationInProgress,
            allowingLifecycle || !isPreparingClose && !isTerminating && !isChangingMode, !hasConflict,
            !editorSession.isComposing, inputResumeError == nil || allowingLifecycle, let snapshot,
            let fileSession
        else { return false }
        if !isDirty && !retainsEditor { return true }
        isSaving = true
        defer {
            isSaving = false
            refreshAfterOperation()
        }
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
            let candidate = try await editorSession.persistenceSnapshot(
                expectedRevision: baseSnapshot.fingerprint)
            try Task.checkCancellation()
            let committed = try await fileSession.save(candidate: candidate.text, expected: baseSnapshot)
            pendingAcknowledgement = (candidate, committed)
            self.snapshot = committed
            readSelection = nil
            startObservation()
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
            if Task.isCancelled { return false }
            self.error = ScholiumErrorLocalization.message(error)
            if error as? ExternalMarkdownFileError == .permissionDenied { needsFileAccess = true }
            if error as? ExternalMarkdownFileError == .changed { hasConflict = true }
            return false
        }
    }

    func sourceChanged() {
        window?.isDocumentEdited = isDirty
        objectWillChange.send()
    }

    func refreshFromDisk() async {
        guard !isClosed, !isBusy, inputResumeError == nil, let fileSession, let snapshot else {
            refreshPending = true
            return
        }
        isRefreshing = true
        let observedEditor = editorSession
        do {
            if retainsEditor && !editorSession.isComposing {
                try await suspendInput()
            }
            if isDirty || editorSession.isComposing {
                let current = try await fileSession.load()
                guard !isClosed else { throw CancellationError() }
                if current.fingerprint != snapshot.fingerprint { throw ExternalMarkdownFileError.changed }
                hasConflict = false
                error = nil
            } else {
                let current = try await fileSession.reload()
                guard !isClosed else { throw CancellationError() }
                // Input can become dirty while the actor performs its read.
                if isDirty || editorSession.isComposing {
                    if current.fingerprint != snapshot.fingerprint || current.identity != snapshot.identity {
                        throw ExternalMarkdownFileError.changed
                    }
                } else if current.fingerprint != snapshot.fingerprint
                    || current.identity != snapshot.identity
                {
                    install(current)
                    startObservation()
                }
                if !hasConflict { error = nil }
            }
        } catch {
            if !isClosed {
                self.error = ScholiumErrorLocalization.message(error)
                if error as? ExternalMarkdownFileError == .permissionDenied { needsFileAccess = true }
                if error as? ExternalMarkdownFileError == .changed { hasConflict = true }
            }
        }
        if editorSession === observedEditor { await resumeInput() }
        isRefreshing = false
        refreshAfterOperation()
    }

    func reloadFromDisk() async {
        guard !isClosed, !isBusy, !editorSession.isComposing, let fileSession else { return }
        isLoading = true
        defer {
            isLoading = false
            refreshAfterOperation()
        }
        do {
            let loaded = try await fileSession.reload()
            guard !isClosed else { return }
            install(loaded)
            startObservation()
        } catch {
            self.error = ScholiumErrorLocalization.message(error)
            if error as? ExternalMarkdownFileError == .permissionDenied { needsFileAccess = true }
        }
    }

    func captureImport() async throws -> Data {
        guard canImport, let snapshot, let fileSession else {
            throw ExternalMarkdownWindowIssue.unsaved
        }
        isImporting = true
        defer {
            isImporting = false
            refreshAfterOperation()
        }
        do {
            let original = try await fileSession.validatedBytes(expected: snapshot)
            let candidate: Data
            if retainsEditor {
                candidate = Data(
                    try await editorSession.persistenceSnapshot(expectedRevision: snapshot.fingerprint).text
                        .utf8)
            } else {
                candidate = original
            }
            _ = try await fileSession.validatedBytes(expected: snapshot)
            guard !isClosed else { throw CancellationError() }
            return candidate
        } catch {
            self.error = ScholiumErrorLocalization.message(error)
            if error as? ExternalMarkdownFileError == .permissionDenied { needsFileAccess = true }
            if error as? ExternalMarkdownFileError == .changed {
                hasConflict = true
            }
            throw error
        }
    }

    func compareChanges() async {
        guard !isBusy, let snapshot else { return }
        do {
            // A separate read never rebases the dirty original session.
            let opened = try await Task.detached { [grantedURL] in
                try ExternalMarkdownFileSession.open(grantedURL)
            }.value
            await opened.session.close()
            guard !isClosed else { return }
            let buffer =
                retainsEditor
                ? try await editorSession.persistenceSnapshot(expectedRevision: snapshot.fingerprint).text
                : snapshot.source
            comparison = ExternalMarkdownComparison(buffer: buffer, disk: opened.snapshot.source)
        } catch { self.error = ScholiumErrorLocalization.message(error) }
    }

    func reveal(displaying url: URL? = nil) {
        if let url, ExternalMarkdownWindowRegistry.referToSameFile(originalURL, url) {
            displayFilename = url.standardizedFileURL.lastPathComponent
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func closeUnopenedDuplicate() {
        guard snapshot == nil, !isDirty else { return }
        let duplicateWindow = window
        closesOnAttachment = duplicateWindow == nil
        close()
        duplicateWindow?.close()
    }
    func closeWindow() { window?.performClose(nil) }

    func acceptReadSelection(
        _ selection: MarkdownReviewSelection?, documentID: String, fingerprint: DocumentFingerprint
    ) {
        guard !isClosed, mode == .read, self.documentID == documentID,
            snapshot?.fingerprint == fingerprint
        else { return }
        readSelection = selection.map {
            BoundReadSelection(documentID: documentID, fingerprint: fingerprint, value: $0)
        }
    }

    func performFind(_ shortcut: DocumentFindShortcut) {
        guard !isClosed, snapshot != nil else { return }
        switch shortcut {
        case .present: documentFind.present()
        case .next: documentFind.next()
        case .previous: documentFind.previous()
        case .useSelection:
            if mode == .read {
                if let readSelection, readSelection.documentID == documentID,
                    readSelection.fingerprint == snapshot?.fingerprint
                {
                    documentFind.useSelection(readSelection.value.excerpt)
                }
                return
            }
            let selectedDocumentID = documentID
            let selectedEditor = editorSession
            Task {
                let selection = try? await selectedEditor.currentSelection()
                guard !isClosed, mode != .read, documentID == selectedDocumentID,
                    editorSession === selectedEditor
                else { return }
                documentFind.useSelection(selection?.excerpt)
            }
        }
    }

    func prepareTermination() async -> Bool {
        if isLoading, snapshot == nil {
            window?.close()
            close()
            return true
        }
        if isBusy {
            reveal()
            return false
        }
        isTerminating = true
        isPreparingTermination = true
        defer { isPreparingTermination = false }
        do {
            try await suspendInput()
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled {
                await resumeInput()
                return false
            }
            isTerminating = false
            self.error = ScholiumErrorLocalization.message(error)
            reveal()
            return false
        }
        if !isDirty { return true }
        let saved = await save(allowingLifecycle: true)
        guard !Task.isCancelled else { return false }
        if saved { return true }
        await resumeInput()
        reveal()
        return false
    }

    private func startObservation() {
        for watcher in watchers { watcher.cancel() }
        watchers = []
        for url in [originalURL, originalURL.deletingLastPathComponent()] {
            let descriptor = Darwin.open(url.path, O_EVTONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { continue }
            let watcher = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: .main)
            watcher.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            }
            watcher.setCancelHandler { Darwin.close(descriptor) }
            watcher.resume()
            watchers.append(watcher)
        }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        guard !isClosed else { return }
        refreshPending = true
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            self.refreshTask = nil
            guard !self.isClosed, !self.isBusy, self.inputResumeError == nil else { return }
            self.refreshPending = false
            await self.refreshFromDisk()
        }
    }

    private func refreshAfterOperation() {
        if refreshPending && inputResumeError == nil { scheduleRefresh() }
        // Readiness can arrive while a checked refresh has suspended input.
        // Its completion, not a coalescible view observation of busy state,
        // resumes only the still-pending explicit mode-entry intent.
        if !isBusy, editorFocusIntent != nil {
            Task { @MainActor [weak self] in await self?.focusEditorIfPresented() }
        }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        editorFocusIntent = nil
        readSelection = nil
        modeTransitionTask?.cancel()
        openingTaskID = nil
        refreshTask?.cancel()
        refreshTask = nil
        for watcher in watchers { watcher.cancel() }
        watchers = []
        ExternalMarkdownWindowRegistry.shared.unregister(self)
        if let window, window.delegate === self { window.delegate = previousDelegate }
        window = nil
        previousDelegate = nil
        if let fileSession { Task { await fileSession.close() } }
        fileSession = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return previousDelegate?.windowShouldClose?(sender) ?? true }
        if isLoading, snapshot == nil { return previousDelegate?.windowShouldClose?(sender) ?? true }
        if closeAuthorized {
            closeAuthorized = false
            return true
        }
        guard !isBusy, !isPreparingClose, !editorSession.isComposing else { return false }
        if !retainsEditor && !isDirty { return previousDelegate?.windowShouldClose?(sender) ?? true }
        isPreparingClose = true
        Task { @MainActor [weak self, weak sender] in
            guard let self, let sender else { return }
            do {
                try await self.suspendInput()
                guard !self.isClosed else { return }
                if self.isDirty { self.confirmClose(sender) } else { self.finishClose(sender) }
            } catch {
                self.isPreparingClose = false
                self.error = ScholiumErrorLocalization.message(error)
                await self.resumeInput()
            }
        }
        return false
    }

    private func confirmClose(_ sender: NSWindow) {
        let alert = NSAlert()
        alert.messageText = ScholiumL10n.string("Save changes to \(title)?")
        alert.informativeText = ScholiumL10n.string(
            "Saving changes the original file outside your Triptych.")
        alert.addButton(withTitle: ScholiumL10n.string("Save"))
        alert.addButton(withTitle: ScholiumL10n.string("Cancel"))
        alert.addButton(withTitle: ScholiumL10n.string("Discard Changes"))
        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            guard let self, let sender else { return }
            if response == .alertFirstButtonReturn {
                Task { @MainActor in
                    if await self.save(allowingLifecycle: true) {
                        self.finishClose(sender)
                    } else {
                        self.isPreparingClose = false
                        await self.resumeInput()
                    }
                }
            } else if response == .alertThirdButtonReturn {
                self.finishClose(sender)
            } else {
                self.isPreparingClose = false
                Task { await self.resumeInput() }
            }
        }
    }

    private func suspendInput() async throws {
        guard retainsEditor else { return }
        defer { inputSuspensionID = editorSession.detachmentSuspensionID }
        if let snapshot {
            _ = try await editorSession.persistenceSnapshot(expectedRevision: snapshot.fingerprint)
        }
        try await editorSession.captureStateForViewReconstruction(suspendForDetachment: true)
    }

    func resumeInput() async {
        guard !isClosed, !isResumingInput else { return }
        isTerminating = false
        let observedEditor = editorSession
        guard let suspensionID = inputSuspensionID ?? observedEditor.detachmentSuspensionID else {
            inputResumeError = nil
            refreshAfterOperation()
            return
        }
        isResumingInput = true
        defer {
            isResumingInput = false
            refreshAfterOperation()
        }
        do {
            try await observedEditor.resumeAfterDetachment(suspensionID: suspensionID)
            guard !isClosed, editorSession === observedEditor else { return }
            guard observedEditor.detachmentSuspensionID == nil else {
                throw MarkdownEditorSession.SessionError.unavailable
            }
            if inputSuspensionID == suspensionID { inputSuspensionID = nil }
            inputResumeError = nil
        } catch {
            guard !isClosed, editorSession === observedEditor else { return }
            inputSuspensionID = suspensionID
            inputResumeError = ScholiumErrorLocalization.message(error)
        }
    }

    var editorActions: ScholiumFocusedEditorActions? {
        guard permitsSourceActions, !isClosed, mode != .read, !isBusy, editorReady, inputResumeError == nil else {
            return nil
        }
        return ScholiumFocusedEditorActions(
            documentID: documentID, isComposing: editorSession.isComposing,
            isAvailable: { [weak self] command in
                guard let self, self.permitsSourceActions, !self.isBusy, self.inputResumeError == nil, !self.editorSession.isComposing,
                    ![MarkdownEditorCommand.insertImage].contains(command)
                else { return false }
                return self.editorSession.context?.availableCommands.contains(command) == true
            },
            perform: { [weak self] command in self?.performEditorCommand(command) },
            performWithArgument: { [weak self] command, argument in
                self?.performEditorCommand(command, argument: argument)
            },
            importImage: {}, indexImage: {}, canAttachDocument: false,
            attachDocumentCopy: {}, referenceOriginalDocument: {}
        )
    }

    private func performEditorCommand(_ command: MarkdownEditorCommand, argument: String? = nil) {
        Task { @MainActor in
            guard permitsSourceActions, !isClosed, mode != .read, !isBusy, inputResumeError == nil, !editorSession.isComposing,
                editorReady
            else { return }
            do { try await editorSession.perform(command, argument: argument) } catch {
                self.error = ScholiumErrorLocalization.message(error)
            }
        }
    }

    private func finishClose(_ sender: NSWindow) {
        guard window === sender else { return }
        closeAuthorized = true
        sender.performClose(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        scheduleRefresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === window { editorFocusIntent = nil }
        previousDelegate?.windowDidResignKey?(notification)
    }

    func windowWillClose(_ notification: Notification) {
        let delegate = previousDelegate
        if notification.object as? NSWindow === window { close() }
        delegate?.windowWillClose?(notification)
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

struct ExternalMarkdownComparison: Identifiable {
    let id = UUID()
    let buffer: String
    let disk: String
}
