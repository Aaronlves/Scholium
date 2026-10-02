import AppKit
import Combine
import Foundation
import PDFKit
import ScholiumContracts
import UniformTypeIdentifiers

struct PDFReaderNoteContext: Hashable {
    let triptychID: UUID
    let target: SourceAttachmentTarget
    let authoredPath: String?
}

struct PDFReaderAnnotationDraft: Identifiable {
    let id = UUID()
    let sessionID: UUID
    let annotation: PDFAnnotation?
    let pageIndex: Int
    let point: NSPoint
    let text: String
}

struct PDFReaderAnnotationRow: Identifiable {
    let annotation: PDFAnnotation
    let pageIndex: Int
    let text: String
    var passageText = ""
    var id: ObjectIdentifier { ObjectIdentifier(annotation) }
}

/// An invalidation hint carries identity only; peers must read checked bytes.
struct PDFReaderSharedSaveHint: Sendable {
    let triptychID: UUID
    let storeID: UUID
    let attachmentID: UUID
    let senderID: UUID
}

@MainActor
private final class PDFReadingSession {
    let id = UUID()
    let context: PDFReaderNoteContext
    let operations: any PDFReaderUseCases
    let sharedStoreID: UUID?
    let document: PDFDocument
    let presentationPermissions: PDFReaderPresentationPermissions
    var serializedData: Data? { presentationPermissions.withOriginalPermissions { document.dataRepresentation() } }
    var snapshot: PDFReaderSnapshot
    var position: PDFReaderReadingState
    var unsavedData: Data?
    var hasChanges = false
    var exportedChanges = false
    var saveTask: Task<Void, Error>?
    var isOutdated = false
    var issueIDs: Set<UUID> = []
    var conflictReported = false

    init(
        context: PDFReaderNoteContext, operations: any PDFReaderUseCases, sharedStoreID: UUID?, snapshot: PDFReaderSnapshot, document: PDFDocument,
        position: PDFReaderReadingState
    ) {
        self.context = context
        self.operations = operations
        self.sharedStoreID = sharedStoreID
        self.snapshot = snapshot
        self.document = document
        presentationPermissions = PDFReaderPresentationPermissions(document: document)
        self.position = position
    }
}

/// Owns a window's note-following PDF session. PDFKit objects never cross an
/// actor boundary; Application receives immutable bytes and checked revisions.
@MainActor
final class PDFReaderController: ObservableObject {
    enum Tool: String { case select, highlight, comment }
    static let sharedPDFSavedNotification = Notification.Name("com.scholium.pdf-reader.shared-save")

    @Published private(set) var isVisible = false
    @Published private(set) var paneWidth = 440.0
    @Published private(set) var document: PDFDocument?
    @Published private(set) var filename: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isImporting = false
    @Published private(set) var isDeparting = false
    @Published private(set) var error: String?
    @Published private(set) var pageNumber = 1
    @Published private(set) var pageCount = 0
    @Published private(set) var hasSelection = false
    @Published private(set) var annotations: [PDFReaderAnnotationRow] = []
    @Published var tool: Tool = .select
    @Published var annotationDraft: PDFReaderAnnotationDraft?
    @Published var annotationDetail: PDFReaderAnnotationRow?
    @Published private(set) var annotationDetailStatus: String?
    @Published var attachRequested = false
    @Published var showsAnnotations = false
    @Published var searchQuery = ""
    @Published private(set) var searchStatus: String?
    @Published private(set) var recoveryCandidates: [PDFReaderRecovery] = []
    @Published private(set) var exportedUnsavedAnnotations = false
    @Published var annotationText = ""
    @Published private(set) var annotationDraftError: String?

    let zotero: ZoteroBridge?
    let windowID: UUID
    private(set) var context: PDFReaderNoteContext?
    private(set) var operations: (any PDFReaderUseCases)?
    private var session: PDFReadingSession?
    private weak var presentationWindow: NSWindow?
    private weak var pdfView: PDFReaderNativePDFView?
    private var loadTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var writeAttempt: UInt64 = 0
    private var isClosed = false
    private let instanceID = UUID()
    private let notificationCenter: NotificationCenter
    private var sharedSaveObservation: AnyCancellable?
    private var sharedRefreshTask: Task<Void, Never>?
    private var sharedRefreshAttempt: UInt64 = 0
    private var sharedStoreInvalidation: UInt64 = 0
    private var sharedStoreID: UUID?
    private var pendingSharedHint: PDFReaderSharedSaveHint?
    private var pendingIssueResolution: (generation: UInt64, context: PDFReaderNoteContext, attachmentID: UUID, issueIDs: Set<UUID>)?
    private var pendingReloadPosition: (generation: UInt64, context: PDFReaderNoteContext, attachmentID: UUID, position: PDFReaderReadingState)?
    private var departureTokens: Set<UUID> = []
    private let allowsInteraction: @MainActor () -> Bool
    private var restoredTriptychID: UUID?
    private var visibilityWasChosen = false
    private var widthWasChosen = false
    private let setBinding: @MainActor (String?, SourceAttachmentTarget, String?) async throws -> Void
    private let reportIssue: @MainActor (String) -> UUID?
    private let resolveIssue: @MainActor (UUID) -> Void

    init(
        windowID: UUID, zotero: ZoteroBridge? = nil, setBinding: @escaping @MainActor (String?, SourceAttachmentTarget, String?) async throws -> Void,
        reportIssue: @escaping @MainActor (String) -> UUID?,
        allowsInteraction: @escaping @MainActor () -> Bool = { true },
        resolveIssue: @escaping @MainActor (UUID) -> Void = { _ in },
        notificationCenter: NotificationCenter = .default
    ) {
        self.windowID = windowID
        self.zotero = zotero
        self.setBinding = setBinding
        self.reportIssue = reportIssue
        self.allowsInteraction = allowsInteraction
        self.resolveIssue = resolveIssue
        self.notificationCenter = notificationCenter
        sharedSaveObservation = notificationCenter.publisher(for: Self.sharedPDFSavedNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let hint = notification.object as? PDFReaderSharedSaveHint else { return }
                MainActor.assumeIsolated { self?.sharedPDFDidSave(hint) }
            }
    }

    /// Freeze mutation input across every await in a departure transaction.
    /// Nested owners release only their own token, including failed attempts.
    func beginDeparture() -> UUID {
        let token = UUID()
        departureTokens.insert(token)
        isDeparting = true
        return token
    }

    func endDeparture(_ token: UUID) {
        departureTokens.remove(token)
        isDeparting = !departureTokens.isEmpty
        if !isDeparting, let hint = pendingSharedHint, acceptsInteraction { sharedPDFDidSave(hint) }
    }

    private var acceptsInteraction: Bool { !isClosed && !isDeparting && allowsInteraction() }
    var canUseReaderCommands: Bool { acceptsInteraction && !isImporting }

    var canAnnotate: Bool {
        guard acceptsInteraction, let session, document === session.document, context == session.context else { return false }
        return session.document.allowsCommenting && !isSaving && !isImporting && !isLoading && !session.hasChanges && !session.isOutdated
    }
    var canCommitDraft: Bool {
        guard acceptsInteraction, let session, annotationDraft?.sessionID == session.id else { return false }
        return session.document.allowsCommenting && !isSaving && !isImporting && !isLoading && !session.hasChanges
    }
    var canAttach: Bool { acceptsInteraction && context != nil && operations != nil && !isSaving && !isImporting }
    var hasUnsavedAnnotations: Bool { session?.hasChanges == true }
    var pendingSaveFilename: String? { session?.hasChanges == true ? session?.snapshot.record.filename : nil }
    var zoteroSource: ZoteroPDFSource? { session?.snapshot.record.zoteroSource }
    var currentAttachmentID: UUID? {
        guard let session, session.context == context else { return nil }
        return session.snapshot.record.id
    }

    @discardableResult
    func setVisible(_ visible: Bool) -> Bool {
        guard acceptsInteraction else { return false }
        guard isVisible != visible else {
            visibilityWasChosen = true
            return true
        }
        guard annotationDraft == nil else {
            error = ScholiumL10n.string("Save or cancel the PDF comment before hiding the reader.")
            return false
        }
        guard !isImporting else {
            error = ScholiumL10n.string("Finish importing the PDF before hiding the reader.")
            return false
        }
        guard visible || !hasUnsavedAnnotations else {
            if error == nil { error = ScholiumL10n.string("Save or recover the PDF annotations before hiding the reader.") }
            return false
        }
        visibilityWasChosen = true
        capturePosition()
        closeAnnotationDetail()
        isVisible = visible
        if visible { startLoadIfNeeded() }
        persistPositionSoon()
        return true
    }

    func recordPaneWidth(_ width: Double) {
        guard width.isFinite, width >= 200, width <= 10_000, abs(width - paneWidth) > 0.5 else { return }
        widthWasChosen = true
        paneWidth = width
        persistPositionSoon()
    }

    func follow(_ newContext: PDFReaderNoteContext?, operations newOperations: (any PDFReaderUseCases)?, sharedStoreID newStoreID: UUID? = nil) {
        guard !isClosed else { return }
        let sameIdentity =
            context?.triptychID == newContext?.triptychID
            && context?.target.noteID == newContext?.target.noteID
            && context?.target.vaultID == newContext?.target.vaultID
            && context?.target.relativePath == newContext?.target.relativePath
            && context?.authoredPath == newContext?.authoredPath
            && sharedStoreID == newStoreID
        context = newContext
        operations = newOperations
        sharedStoreID = newStoreID
        guard !sameIdentity else { return }
        sharedStoreInvalidation = 0
        capturePosition()
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        invalidateSharedRefresh()
        pendingIssueResolution = nil
        pendingReloadPosition = nil
        document?.cancelFindString()
        document = nil
        pdfView?.document = nil
        attachRequested = false
        filename = nil
        pageCount = 0
        hasSelection = false
        annotations = []
        annotationDetail = nil
        annotationDetailStatus = nil
        recoveryCandidates = []
        searchQuery = ""
        searchStatus = nil
        tool = .select
        error = nil
        annotationDraftError = nil
        isLoading = false
        startLoadIfNeeded()
    }

    private func startLoadIfNeeded() {
        guard loadTask == nil, document == nil, !isClosed,
            let context, let operations
        else { return }
        let requestedGeneration = generation
        let outgoing = session
        let requestedStoreID = sharedStoreID
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generation == requestedGeneration {
                    self.isLoading = false
                    self.loadTask = nil
                }
            }
            do {
                if let outgoing {
                    try await self.flush(outgoing)
                    try await self.persist(outgoing)
                }
                try self.check(requestedGeneration)
                if self.restoredTriptychID != context.triptychID {
                    let state = try await operations.windowState(windowID: self.windowID)
                    try self.check(requestedGeneration)
                    self.restoredTriptychID = context.triptychID
                    if let state {
                        if !self.visibilityWasChosen { self.isVisible = state.isVisible }
                        if !self.widthWasChosen { self.paneWidth = state.paneWidth }
                    }
                }
                self.session?.presentationPermissions.invalidate()
                self.session = nil
                guard self.isVisible else { return }
                var observedInvalidation = self.sharedStoreInvalidation
                guard var snapshot = try await operations.boundPDF(for: context.target, authoredPath: context.authoredPath) else { return }
                try self.check(requestedGeneration)
                var position = try await operations.readingState(noteID: context.target.noteID, attachmentID: snapshot.record.id) ?? PDFReaderReadingState()
                try self.check(requestedGeneration)
                while self.sharedStoreInvalidation != observedInvalidation {
                    observedInvalidation = self.sharedStoreInvalidation
                    let fresh = try await operations.loadPDF(attachmentID: snapshot.record.id)
                    try self.check(requestedGeneration)
                    guard fresh.record == snapshot.record else { throw PDFReaderError.changed }
                    snapshot = fresh
                }
                guard let document = PDFDocument(data: snapshot.data), !document.isLocked, document.pageCount > 0 else {
                    throw PDFReaderError.malformed
                }
                if let retained = self.pendingReloadPosition,
                    retained.generation == requestedGeneration, retained.context == context, retained.attachmentID == snapshot.record.id
                {
                    position = retained.position
                    self.pendingReloadPosition = nil
                }
                let session = PDFReadingSession(
                    context: context, operations: operations, sharedStoreID: requestedStoreID, snapshot: snapshot, document: document, position: position)
                self.session = session
                self.document = document
                self.filename = snapshot.record.filename
                self.recoveryCandidates = snapshot.recoveryCandidates
                self.exportedUnsavedAnnotations = false
                self.pageCount = document.pageCount
                self.restorePosition()
                self.refreshAnnotations()
                self.error = nil
                if let resolution = self.pendingIssueResolution,
                    resolution.generation == requestedGeneration, resolution.context == context, resolution.attachmentID == snapshot.record.id
                {
                    for id in resolution.issueIDs { self.resolveIssue(id) }
                    self.pendingIssueResolution = nil
                }
            } catch is CancellationError {
                // Superseded work has no presentation authority.
            } catch {
                guard self.generation == requestedGeneration else { return }
                self.error = PDFReaderPresentationError.message(error)
                let recoveries = try? await operations.boundPDFRecoveries(for: context.target, authoredPath: context.authoredPath)
                guard self.generation == requestedGeneration, !self.isClosed else { return }
                self.recoveryCandidates = recoveries ?? []
                self.filename = context.authoredPath.map { URL(fileURLWithPath: $0).lastPathComponent }
            }
        }
    }

    func requestAttachPDF() {
        guard isVisible, canAttach else { return }
        attachRequested = true
    }

    func availablePDFs() async throws -> [PortableAttachmentRecord] {
        guard let operations else { throw PDFReaderError.missing }
        return try await operations.availablePDFs()
    }

    func importPDF(at url: URL, zoteroSource: ZoteroPDFSource? = nil, allowNewVersion: Bool = false) async throws {
        guard let context, let operations, canAttach else { throw PDFReaderError.invalidBinding }
        let capturedGeneration = generation
        try await flushAnnotations()
        try check(capturedGeneration)
        guard canAttach else { throw CancellationError() }
        isImporting = true
        defer { isImporting = false }
        let prepared = try await operations.importPDF(at: url, for: context.target, zoteroSource: zoteroSource, allowNewVersion: allowNewVersion)
        try check(capturedGeneration)
        try await setBinding(prepared.noteRelativePath, context.target, context.authoredPath)
        attachRequested = false
    }

    func importLocalCopy(_ candidate: ZoteroPDFLocalCopyCandidate, allowNewVersion: Bool = false) async throws {
        guard let context, let operations, canAttach else { throw PDFReaderError.invalidBinding }
        let capturedGeneration = generation
        try await flushAnnotations()
        try check(capturedGeneration)
        guard canAttach else { throw CancellationError() }
        isImporting = true
        defer { isImporting = false }
        let prepared = try await operations.importLocalCopy(candidate, for: context.target, allowNewVersion: allowNewVersion)
        try check(capturedGeneration)
        try await setBinding(prepared.noteRelativePath, context.target, context.authoredPath)
        attachRequested = false
    }

    func attachExisting(_ id: UUID) async throws {
        guard let context, let operations, canAttach else { throw PDFReaderError.invalidBinding }
        let capturedGeneration = generation
        try await flushAnnotations()
        try check(capturedGeneration)
        guard canAttach else { throw CancellationError() }
        isImporting = true
        defer { isImporting = false }
        let prepared = try await operations.attachPDF(attachmentID: id, for: context.target)
        try check(capturedGeneration)
        try await setBinding(prepared.noteRelativePath, context.target, context.authoredPath)
        attachRequested = false
    }

    func checkExternalChanges() async {
        if let hint = pendingSharedHint, acceptsInteraction { sharedPDFDidSave(hint) }
        guard let session, !isLoading, !isSaving else { return }
        let requestedGeneration = generation
        do {
            var expectedRevision = session.snapshot.revision
            var current = try await session.operations.loadPDF(attachmentID: session.snapshot.record.id)
            guard self.session === session, generation == requestedGeneration, !isClosed else { return }
            while expectedRevision != session.snapshot.revision {
                expectedRevision = session.snapshot.revision
                current = try await session.operations.loadPDF(attachmentID: session.snapshot.record.id)
                guard self.session === session, generation == requestedGeneration, !isClosed else { return }
            }
            recoveryCandidates = current.recoveryCandidates
            if current.revision != session.snapshot.revision { recordConflict(in: session) }
        } catch {
            guard self.session === session, generation == requestedGeneration, !isClosed else { return }
            self.error = PDFReaderPresentationError.message(error)
        }
    }

    private func sharedPDFDidSave(_ hint: PDFReaderSharedSaveHint) {
        guard !isClosed, hint.senderID != instanceID,
            hint.triptychID == context?.triptychID, hint.storeID == sharedStoreID
        else { return }
        sharedStoreInvalidation &+= 1
        guard let session,
            session.context == context, document === session.document,
            hint.triptychID == session.context.triptychID, hint.storeID == session.sharedStoreID,
            hint.attachmentID == session.snapshot.record.id
        else { return }
        if isDeparting || !allowsInteraction() || isImporting {
            pendingSharedHint = hint
            return
        }
        pendingSharedHint = nil
        sharedRefreshAttempt &+= 1
        let requestedAttempt = sharedRefreshAttempt
        let requestedGeneration = generation
        let expectedRevision = session.snapshot.revision
        sharedRefreshTask?.cancel()
        sharedRefreshTask = Task { [weak self, session] in
            guard let self else { return }
            defer { if self.sharedRefreshAttempt == requestedAttempt { self.sharedRefreshTask = nil } }
            do {
                let fresh = try await session.operations.loadPDF(attachmentID: hint.attachmentID)
                try self.check(requestedGeneration)
                guard self.sharedRefreshAttempt == requestedAttempt, self.session === session,
                    self.context == session.context, self.document === session.document
                else { return }
                // A local save may finish while the read is delayed. Re-read
                // instead of publishing bytes older than that proven commit.
                guard session.snapshot.revision == expectedRevision else {
                    self.sharedPDFDidSave(hint)
                    return
                }
                guard fresh.record == session.snapshot.record else { throw PDFReaderError.changed }
                guard fresh.revision != session.snapshot.revision else {
                    if session.isOutdated, !session.hasChanges, session.saveTask == nil, self.annotationDraft == nil,
                        !self.isSaving, !self.isLoading, !self.isImporting, self.acceptsInteraction
                    {
                        session.isOutdated = false
                        self.annotationDetailStatus = nil
                        self.error = nil
                        self.resolveIssues(in: session)
                    }
                    return
                }
                self.recoveryCandidates = fresh.recoveryCandidates
                guard !session.hasChanges, session.saveTask == nil, self.annotationDraft == nil,
                    !self.isSaving, !self.isLoading, !self.isImporting
                else {
                    self.recordConflict(in: session)
                    return
                }
                guard !self.isDeparting, self.acceptsInteraction else {
                    self.pendingSharedHint = hint
                    return
                }
                if self.annotationDetail != nil {
                    session.isOutdated = true
                    self.pendingSharedHint = hint
                    self.annotationDetailStatus = ScholiumL10n.string("New PDF annotations are available. Close this view to refresh.")
                    return
                }
                guard let document = PDFDocument(data: fresh.data), !document.isLocked, document.pageCount > 0 else {
                    throw PDFReaderError.malformed
                }
                self.capturePosition()
                let replacement = PDFReadingSession(
                    context: session.context, operations: session.operations, sharedStoreID: session.sharedStoreID,
                    snapshot: fresh, document: document, position: session.position)
                replacement.issueIDs = session.issueIDs
                replacement.conflictReported = session.conflictReported
                session.document.cancelFindString()
                session.presentationPermissions.invalidate()
                self.generation &+= 1
                self.session = replacement
                self.document = document
                self.annotationDetail = nil
                self.annotationDetailStatus = nil
                self.filename = fresh.record.filename
                self.pageCount = document.pageCount
                self.hasSelection = false
                self.searchStatus = nil
                self.error = nil
                self.refreshAnnotations()
                self.pdfView?.apply(self)
                self.resolveIssues(in: replacement)
            } catch is CancellationError {
            } catch {
                guard self.generation == requestedGeneration, self.sharedRefreshAttempt == requestedAttempt,
                    self.session === session, self.context == session.context, !self.isClosed
                else { return }
                if (error as? PDFReaderError) == .changed {
                    self.recordConflict(in: session)
                } else {
                    self.error = PDFReaderPresentationError.message(error)
                }
            }
        }
    }

    private func invalidateSharedRefresh() {
        sharedRefreshAttempt &+= 1
        sharedRefreshTask?.cancel()
        sharedRefreshTask = nil
        pendingSharedHint = nil
    }

    private func recordConflict(in session: PDFReadingSession) {
        guard self.session === session, context == session.context else { return }
        session.isOutdated = true
        let message = PDFReaderPresentationError.message(PDFReaderError.changed)
        error = message
        guard !session.conflictReported else { return }
        session.conflictReported = true
        if let id = reportIssue(message) { session.issueIDs.insert(id) }
    }

    private func resolveIssues(in session: PDFReadingSession) {
        guard self.session === session, context == session.context else { return }
        for id in session.issueIDs { resolveIssue(id) }
        session.issueIDs.removeAll()
        session.conflictReported = false
    }

    func presentFailure(_ error: Error) { self.error = PDFReaderPresentationError.message(error) }

    func detachPDF() async throws {
        guard canAttach, let context else { return }
        let capturedGeneration = generation
        try await flushAnnotations()
        try check(capturedGeneration)
        guard canAttach else { throw CancellationError() }
        isImporting = true
        defer { isImporting = false }
        try await setBinding(nil, context.target, context.authoredPath)
    }

    func attach(view: PDFReaderNativePDFView) {
        guard !isClosed else { return }
        pdfView = view
        if view.document !== document { view.document = document }
        restorePosition()
    }

    func detach(view: PDFReaderNativePDFView) {
        guard pdfView === view else { return }
        capturePosition()
        if !isClosed { persistPositionSoon() }
        pdfView = nil
    }

    func restorePosition() {
        guard let session, let view = pdfView, view.document === session.document,
            let page = session.document.page(at: min(session.position.pageIndex, session.document.pageCount - 1))
        else { return }
        view.autoScales = session.position.autoScales
        if !session.position.autoScales { view.scaleFactor = session.position.scaleFactor }
        if session.position.pointX == 0 && session.position.pointY == 0 {
            view.go(to: page)
        } else {
            let box = page.bounds(for: .cropBox)
            let point = NSPoint(x: min(max(session.position.pointX, box.minX), box.maxX), y: min(max(session.position.pointY, box.minY), box.maxY))
            view.go(to: PDFDestination(page: page, at: point))
        }
        pageNumber = session.document.index(for: page) + 1
    }

    func viewPositionDidChange() {
        guard pdfView?.document === document, document != nil else { return }
        capturePosition()
        persistPositionSoon()
    }

    private func capturePosition() {
        guard let session, let view = pdfView, view.document === session.document,
            let destination = view.currentDestination, let page = view.currentPage ?? destination.page
        else { return }
        let pageIndex = session.document.index(for: page)
        guard pageIndex != NSNotFound else { return }
        // Continuous mode's viewport origin can still fall on the preceding
        // page when the requested final page cannot scroll all the way to the
        // top. PDFKit's currentPage tracks the page at the viewport midpoint.
        let point = destination.page === page ? destination.point : view.convert(NSPoint(x: view.bounds.minX, y: view.bounds.maxY), to: page)
        let box = page.bounds(for: .cropBox)
        session.position = PDFReaderReadingState(
            pageIndex: pageIndex, pointX: min(max(point.x, box.minX), box.maxX), pointY: min(max(point.y, box.minY), box.maxY),
            scaleFactor: view.scaleFactor, autoScales: view.autoScales)
        pageNumber = pageIndex + 1
    }

    func selectionDidChange() {
        hasSelection =
            pdfView?.document === document
            && pdfView?.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func goToPage(_ number: Int) {
        guard canUseReaderCommands, let document, let page = document.page(at: number - 1) else { return }
        pdfView?.go(to: page)
        viewPositionDidChange()
    }

    func zoom(_ factor: Double) {
        guard canUseReaderCommands, let view = pdfView, document != nil else { return }
        view.autoScales = false
        view.scaleFactor = min(max(view.scaleFactor * factor, view.minScaleFactor), view.maxScaleFactor)
        viewPositionDidChange()
    }

    func fitPage() {
        guard canUseReaderCommands else { return }
        pdfView?.autoScales = true
        viewPositionDidChange()
    }

    func find(backwards: Bool = false) {
        guard canUseReaderCommands else { return }
        guard let document, let view = pdfView, !searchQuery.isEmpty else {
            searchStatus = nil
            return
        }
        let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .backwards] : [.caseInsensitive]
        let result =
            document.findString(searchQuery, fromSelection: view.currentSelection, withOptions: options)
            ?? document.findString(searchQuery, fromSelection: nil, withOptions: options)
        if let result {
            view.setCurrentSelection(result, animate: false)
            view.go(to: result)
            searchStatus = nil
        } else {
            searchStatus = ScholiumL10n.string("No matches in this PDF.")
        }
    }

    func highlightSelection() {
        guard canAnnotate, let session, let selection = pdfView?.currentSelection else { return }
        do {
            let prepared = try PDFReaderAnnotations.highlights(for: selection, in: session.document)
            for (page, annotation) in prepared { page.addAnnotation(annotation) }
            pdfView?.clearSelection()
            saveMutation(session)
        } catch { self.error = PDFReaderPresentationError.message(error) }
    }

    func requestComment(on page: PDFPage? = nil, at point: NSPoint? = nil) {
        guard canAnnotate, let session else { return }
        let selectedPage = page ?? pdfView?.currentSelection?.pages.first ?? pdfView?.currentPage
        guard let selectedPage, selectedPage.document === session.document else { return }
        let box = selectedPage.bounds(for: .cropBox)
        let selectedPoint =
            point ?? pdfView?.currentSelection.map { NSPoint(x: $0.bounds(for: selectedPage).minX, y: $0.bounds(for: selectedPage).maxY) }
            ?? NSPoint(x: box.minX + 28, y: box.maxY - 28)
        annotationText = ""
        annotationDraftError = nil
        annotationDetail = nil
        annotationDraft = PDFReaderAnnotationDraft(
            sessionID: session.id, annotation: nil, pageIndex: session.document.index(for: selectedPage), point: selectedPoint, text: "")
    }

    func editAnnotation(_ annotation: PDFAnnotation) {
        guard canAnnotate, let session else { return }
        do {
            let page = try PDFReaderAnnotations.requireCurrent(annotation, in: session.document)
            annotationDetail = nil
            annotationText = annotation.contents ?? ""
            annotationDraftError = nil
            annotationDraft = PDFReaderAnnotationDraft(
                sessionID: session.id, annotation: annotation, pageIndex: session.document.index(for: page), point: annotation.bounds.origin,
                text: annotation.contents ?? "")
        } catch { self.error = PDFReaderPresentationError.message(error) }
    }

    func commitComment(_ draft: PDFReaderAnnotationDraft, text: String) {
        guard canCommitDraft, let session, session.id == draft.sessionID else { return }
        do {
            if let annotation = draft.annotation {
                _ = try PDFReaderAnnotations.requireCurrent(annotation, in: session.document)
                if PDFReaderAnnotations.hasType(annotation, .text) && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw PDFReaderAnnotationEditingError.emptyComment
                }
                annotation.contents = text
                annotation.modificationDate = Date()
            } else {
                guard let page = session.document.page(at: draft.pageIndex) else { throw PDFReaderError.changed }
                let annotation = try PDFReaderAnnotations.comment(text: text, at: draft.point, on: page, in: session.document)
                page.addAnnotation(annotation)
            }
            annotationDraft = nil
            annotationDraftError = nil
            saveMutation(session)
        } catch { annotationDraftError = PDFReaderPresentationError.message(error) }
    }

    func showAnnotation(_ annotation: PDFAnnotation) {
        guard canUseReaderCommands, annotationDraft == nil, let session,
            session.context == context, document === session.document
        else { return }
        do {
            let page = try PDFReaderAnnotations.requireReadable(annotation, in: session.document)
            let bounds = PDFReaderAnnotations.navigationBounds(for: annotation, on: page)
            if !bounds.isNull, !bounds.isEmpty { pdfView?.go(to: bounds, on: page) }
            annotationDetail = PDFReaderAnnotationRow(
                annotation: annotation, pageIndex: session.document.index(for: page), text: annotation.contents ?? "",
                passageText: PDFReaderAnnotations.selectedPassage(for: annotation, on: page))
        } catch { self.error = PDFReaderPresentationError.message(error) }
    }

    func closeAnnotationDetail() {
        annotationDetail = nil
        annotationDetailStatus = nil
        if let hint = pendingSharedHint, acceptsInteraction { sharedPDFDidSave(hint) }
    }

    func deleteAnnotation(_ draft: PDFReaderAnnotationDraft) {
        guard canCommitDraft, let session, session.id == draft.sessionID, let annotation = draft.annotation else { return }
        do {
            let page = try PDFReaderAnnotations.requireCurrent(annotation, in: session.document)
            page.removeAnnotation(annotation)
            annotationDraft = nil
            annotationDraftError = nil
            saveMutation(session)
        } catch { annotationDraftError = PDFReaderPresentationError.message(error) }
    }

    private func saveMutation(_ session: PDFReadingSession) {
        session.hasChanges = true
        session.exportedChanges = false
        exportedUnsavedAnnotations = false
        guard let data = session.serializedData else {
            error = ScholiumL10n.string("The PDF annotations could not be prepared for saving. Keep this reader open.")
            return
        }
        session.unsavedData = data
        refreshAnnotations()
        pdfView?.needsDisplay = true
        isSaving = true
        error = nil
        let candidate = data
        let expected = session.snapshot
        let notificationCenter = notificationCenter
        let senderID = instanceID
        session.saveTask = Task { [weak self, session] in
            do {
                let saved = try await session.operations.savePDF(candidate: candidate, expected: expected)
                session.snapshot = saved
                session.unsavedData = nil
                session.hasChanges = false
                session.isOutdated = false
                session.saveTask = nil
                if let self, self.session === session {
                    self.isSaving = false
                    self.error = nil
                    self.resolveIssues(in: session)
                    if self.document == nil { self.restartLoad() }
                }
                if let storeID = session.sharedStoreID {
                    notificationCenter.post(
                        name: PDFReaderController.sharedPDFSavedNotification,
                        object: PDFReaderSharedSaveHint(
                            triptychID: session.context.triptychID, storeID: storeID, attachmentID: saved.record.id, senderID: senderID))
                }
            } catch {
                session.saveTask = nil
                if let self, self.session === session {
                    self.isSaving = false
                    self.error = PDFReaderPresentationError.message(error)
                    if (error as? PDFReaderError) == .changed {
                        self.recordConflict(in: session)
                    } else if let id = self.reportIssue(PDFReaderPresentationError.message(error)) {
                        session.issueIDs.insert(id)
                    }
                }
                throw error
            }
        }
    }

    func retrySave() {
        guard let session, session.hasChanges, session.saveTask == nil else { return }
        saveMutation(session)
    }

    func reload(discardExportedChanges: Bool = false) async {
        guard acceptsInteraction else { return }
        guard annotationDraft == nil else {
            error = ScholiumL10n.string("Save or cancel the PDF comment before reloading the reader.")
            return
        }
        guard let session else {
            startLoadIfNeeded()
            return
        }
        guard session.saveTask == nil, !isImporting else { return }
        guard !session.hasChanges || (discardExportedChanges && session.exportedChanges) else {
            error = ScholiumL10n.string("Export your unsaved annotations before reloading this PDF.")
            return
        }
        generation &+= 1
        invalidateSharedRefresh()
        loadTask?.cancel()
        loadTask = nil
        capturePosition()
        pendingReloadPosition = (generation, session.context, session.snapshot.record.id, session.position)
        pendingIssueResolution = (generation, session.context, session.snapshot.record.id, session.issueIDs)
        document = nil
        pdfView?.document = nil
        session.presentationPermissions.invalidate()
        self.session = nil
        annotationDetail = nil
        annotationDetailStatus = nil
        exportedUnsavedAnnotations = false
        startLoadIfNeeded()
    }

    func exportAnnotations(to destination: URL) async throws {
        guard let session, let data = session.unsavedData ?? session.serializedData else { throw PDFReaderError.missing }
        try await session.operations.exportPDF(candidate: data, to: destination)
        if session.hasChanges {
            session.exportedChanges = true
            if self.session === session { exportedUnsavedAnnotations = true }
        }
    }

    func flushAnnotations() async throws {
        guard !isImporting else { throw PDFReaderDraftError.importing }
        guard let session else { return }
        try await flush(session)
        capturePosition()
        try await persist(session)
    }

    private func flush(_ session: PDFReadingSession) async throws {
        if annotationDraft?.sessionID == session.id {
            throw PDFReaderDraftError.unfinished
        }
        if let saving = session.saveTask { try await saving.value }
        if session.hasChanges { throw PDFReaderError.changed }
    }

    func flushPersistence() async throws {
        try await flushAnnotations()
        positionTask?.cancel()
        positionTask = nil
        guard let operations else { return }
        writeAttempt &+= 1
        try await operations.saveWindowState(PDFReaderWindowState(isVisible: isVisible, paneWidth: paneWidth), windowID: windowID, attempt: writeAttempt)
    }

    private func persist(_ session: PDFReadingSession) async throws {
        writeAttempt &+= 1
        try await session.operations.saveReadingState(
            session.position, noteID: session.context.target.noteID, attachmentID: session.snapshot.record.id, windowID: windowID, attempt: writeAttempt)
    }

    private func persistPositionSoon() {
        guard !isClosed else { return }
        let requestedGeneration = generation
        positionTask?.cancel()
        positionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard let self, !self.isClosed else { return }
                if let session = self.session { try await self.persist(session) }
                if let operations = self.operations {
                    self.writeAttempt &+= 1
                    try await operations.saveWindowState(
                        PDFReaderWindowState(isVisible: self.isVisible, paneWidth: self.paneWidth), windowID: self.windowID, attempt: self.writeAttempt)
                }
            } catch is CancellationError {
            } catch {
                if let self, self.generation == requestedGeneration, !self.isClosed {
                    self.error = PDFReaderPresentationError.message(error)
                }
            }
        }
    }

    private func refreshAnnotations() {
        guard let document else {
            annotations = []
            return
        }
        annotations = (0..<document.pageCount).flatMap { pageIndex in
            guard let page = document.page(at: pageIndex) else { return [PDFReaderAnnotationRow]() }
            return page.annotations.filter(PDFReaderAnnotations.isEditable).map {
                PDFReaderAnnotationRow(
                    annotation: $0, pageIndex: pageIndex, text: $0.contents ?? "",
                    passageText: PDFReaderAnnotations.selectedPassage(for: $0, on: page))
            }
        }
    }

    private func check(_ requestedGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard !isClosed, generation == requestedGeneration else { throw CancellationError() }
    }

    private func restartLoad() {
        guard !isClosed else { return }
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        invalidateSharedRefresh()
        pendingIssueResolution = nil
        pendingReloadPosition = nil
        error = nil
        startLoadIfNeeded()
    }

    func cancelComment() {
        annotationDraft = nil
        annotationDetail = nil
        annotationDetailStatus = nil
        annotationText = ""
        annotationDraftError = nil
        if document == nil { restartLoad() }
    }

    func registerPresentationWindow(_ window: NSWindow) { presentationWindow = window }
    func unregisterPresentationWindow(_ window: NSWindow) {
        if presentationWindow === window { presentationWindow = nil }
    }

    func requestExport(recovery: PDFReaderRecovery? = nil) {
        guard acceptsInteraction else { return }
        guard let window = presentationWindow ?? pdfView?.window,
            let operations = recovery == nil ? session?.operations : self.operations
        else {
            error = ScholiumL10n.string("Open the PDF reader before exporting annotations.")
            return
        }
        let exportingSession = session
        let exportGeneration = generation
        let candidate = recovery == nil ? (session?.unsavedData ?? session?.serializedData) : nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Annotated-" + (exportingSession?.snapshot.record.filename ?? "Recovered.pdf")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in
                do {
                    let data: Data
                    if let recovery {
                        data = try await operations.recoveryData(recovery)
                    } else if let candidate {
                        data = candidate
                    } else {
                        throw PDFReaderError.malformed
                    }
                    try await operations.exportPDF(candidate: data, to: destination)
                    if recovery == nil, let exportingSession, exportingSession.hasChanges {
                        exportingSession.exportedChanges = true
                        if self?.session === exportingSession { self?.exportedUnsavedAnnotations = true }
                    }
                } catch {
                    if let self, self.generation == exportGeneration, !self.isClosed {
                        self.error = PDFReaderPresentationError.message(error)
                    }
                }
            }
        }
    }

    func shutdown() {
        guard !isClosed else { return }
        isClosed = true
        generation &+= 1
        loadTask?.cancel()
        loadTask = nil
        invalidateSharedRefresh()
        sharedSaveObservation?.cancel()
        sharedSaveObservation = nil
        pendingIssueResolution = nil
        pendingReloadPosition = nil
        positionTask?.cancel()
        positionTask = nil
        document?.cancelFindString()
        annotationDraft = nil
        annotationDetail = nil
        annotationDetailStatus = nil
        pdfView?.invalidate()
        pdfView = nil
        document = nil
        session?.presentationPermissions.invalidate()
        session = nil
        presentationWindow = nil
    }
}

private enum PDFReaderDraftError: LocalizedError {
    case unfinished, importing
    var errorDescription: String? {
        switch self {
        case .unfinished: ScholiumL10n.string("Save or cancel the PDF comment before leaving this note.")
        case .importing: ScholiumL10n.string("Finish importing the PDF before leaving this note.")
        }
    }
}
