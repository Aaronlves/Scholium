import Combine
import ScholiumContracts
import SwiftUI

/// A document session follows stable vault and note identities. Paths and
/// titles are mutable projections and therefore must never own editor state.
struct DocumentSessionKey: Hashable, Sendable {
    let vaultID: UUID
    let noteID: UUID
}

/// A single save attempt records durable bytes independently of editor acknowledgement.
@MainActor
final class EditorSaveCommitReceipt {
    var document: NoteDocument?
}

enum EditorSaveOutcome: Equatable {
    case clean
    case changedDuringSave
}

struct ObservedScrollPosition: Equatable, Sendable {
    var fraction: Double
    var anchor: EditorScrollAnchor?

    init(fraction: Double = 0, anchor: EditorScrollAnchor? = nil) {
        self.fraction = Self.normalized(fraction)
        self.anchor = anchor
    }

    mutating func updateFraction(_ value: Double) {
        guard value.isFinite else { return }
        fraction = Self.normalized(value)
    }

    private static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}

enum ScrollRestoreReason: String, Equatable, Sendable {
    case documentLoad
    case modeHandoff
    case webViewRebuild
    case explicitNavigation
}

enum DocumentScrollSurface: Hashable, Sendable {
    case read
    case editor
}

struct ScrollRestoreRequest: Equatable, Sendable {
    let id: UInt64
    let fingerprint: String
    let position: ObservedScrollPosition
    let reason: ScrollRestoreReason
}

/// The single owner for mutable, reconstruction-sensitive document UI state.
/// The WKWebView remains an implementation detail of `MarkdownEditorSession`;
/// CodeMirror remains authoritative while the session is editing.
@MainActor
final class DocumentSessionModel: ObservableObject {
    let key: DocumentSessionKey?
    let editorSession: MarkdownEditorSession

    @Published private(set) var presentation = DocumentPresentationState()
    @Published var editingSource = ""
    @Published var originalEditingSource = ""
    @Published var editingRevision: DocumentFingerprint?
    @Published var editError: String?
    @Published var isSavingEdit = false
    /// Review and the retained editor have independent viewport observations.
    /// A mode handoff copies one position explicitly; an ordinary report from
    /// one surface can never overwrite the other surface's viewport.
    private(set) var readScrollPosition = ObservedScrollPosition()
    private(set) var editorScrollPosition = ObservedScrollPosition()
    /// Only an explicit lifecycle or navigation transition creates a request.
    /// Coordinators consume each monotonically increasing ID at most once.
    @Published private(set) var scrollRestoreRequest: ScrollRestoreRequest?
    @Published var returnToReadAfterSave = false
    var reviewHandoffID: UUID?
    @Published var suppressAutosave = false
    @Published var renderedReadHTML = ""
    @Published var renderedReadFingerprint = ""
    @Published var renderedReadReadyFingerprint = ""
    @Published var failedReadFingerprint: String?
    @Published var previewCatalog: DocumentPreviewCatalog?
    @Published var isAttachingDocument = false
    let findPresentation = DocumentFindPresentationModel()
    var readSelection: MarkdownReviewSelection?
    @Published var conflict: DocumentConflictSnapshot?
    /// The exact conflict revision shown in the open comparison sheet. A
    /// later filesystem observation may update `conflict`, but it must never
    /// change the bytes that the current Reload action is authorized to use.
    @Published private(set) var conflictComparison: DocumentConflictSnapshot?
    @Published var canRetrySave = false
    @Published var showConflictComparison = false
    /// Present only until a managed New Note's acknowledged editor has placed
    /// the insertion point at the exact body boundary. This is session-bound
    /// so another navigation can never consume the creation focus intent.
    @Published private(set) var managedCreationBodyStartUTF16: Int? = nil
    private var hasBeenActivated = false
    private var presentationIsClosed = false

    var autosaveTask: Task<Void, Never>?
    var autosaveToken: UUID?
    var autosaveDeadline: ContinuousClock.Instant?
    var activeSaveTask: Task<EditorSaveOutcome, Error>?
    var activeSaveCommitReceipt: EditorSaveCommitReceipt?
    var activeSaveToken: UUID?
    var pendingEditorCommit: (snapshot: MarkdownEditorPersistenceSnapshot, document: NoteDocument)?
    var detachmentResumeTask: Task<Void, Never>?
    var detachmentResumeToken: UUID?
    var detachmentPreparationTask: Task<Void, Error>?
    var detachmentPreparationToken: UUID?
    private var editorCancellable: AnyCancellable?
    private var nextScrollRestoreRequestID: UInt64 = 0

    init(key: DocumentSessionKey?, editorSession: MarkdownEditorSession = MarkdownEditorSession()) {
        self.key = key
        self.editorSession = editorSession
        editorCancellable = editorSession.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var isEditing: Bool { presentation.isEditing }
    var presentationMode: NotePresentationMode { presentation.activeMode }
    var retainedEditorMode: MarkdownEditorMode { presentation.retainedEditorMode }
    var activeEditorMode: MarkdownEditorMode? { presentation.activeEditorMode }
    var pendingEditorMode: MarkdownEditorMode? { presentation.pendingEditorMode }
    var pendingPresentationMode: NotePresentationMode? {
        presentation.pendingPresentationMode(
            editorIsLoaded: editorSession.isLoaded,
            acknowledgedEditorMode: editorSession.presentedMode,
            hasEditorError: editorSession.errorMessage != nil
        )
    }
    var retainsEditorSurface: Bool { presentation.retainsEditorSurface }
    var isEnteringManagedCreation: Bool {
        managedCreationBodyStartUTF16 != nil
    }

    var activeScrollSurface: DocumentScrollSurface {
        isEditing ? .editor : .read
    }

    var activeScrollPosition: ObservedScrollPosition {
        switch activeScrollSurface {
        case .read: readScrollPosition
        case .editor: editorScrollPosition
        }
    }

    var readScrollFraction: Double { readScrollPosition.fraction }
    var editorScrollFraction: Double { editorScrollPosition.fraction }
    var editorScrollAnchor: EditorScrollAnchor? { editorScrollPosition.anchor }

    func presentConflictComparison() {
        guard let conflict else { return }
        conflictComparison = conflict
        showConflictComparison = true
    }

    func dismissConflictComparison() {
        showConflictComparison = false
        conflictComparison = nil
    }

    func beginManagedCreationEntry(bodyStartUTF16: Int) {
        managedCreationBodyStartUTF16 = max(0, bodyStartUTF16)
    }

    func completeManagedCreationEntry() {
        managedCreationBodyStartUTF16 = nil
    }

    /// A first activation begins in the body. A retained or restored
    /// session reuses its last title/body focus target and exact valid editor
    /// selection; managed creation keeps its explicit body-start contract.
    func prepareForDocumentActivation() {
        presentationIsClosed = false
        resetScrollPosition()
        editorSession.prepareOpeningPresentation()
        let target: WindowDocumentFocusTarget
        if isEnteringManagedCreation {
            target = .editor
        } else if hasBeenActivated {
            target = editorSession.preferredDocumentFocusTarget ?? .editor
        } else {
            target = .editor
        }
        hasBeenActivated = true
        editorSession.authorizeAutomaticFocus(target: target)
    }

    func restoreWindowPresentation(
        _ presentation: WindowDocumentPresentationSnapshot,
        source: String
    ) {
        readScrollPosition.updateFraction(presentation.scrollFraction)
        editorScrollPosition.updateFraction(presentation.scrollFraction)
        hasBeenActivated = true
        _ = editorSession.restoreWindowPresentation(
            presentation,
            source: source
        )
    }

    var windowPresentationSnapshot: WindowDocumentPresentationSnapshot {
        editorSession.windowPresentationSnapshot(
            scrollFraction: activeScrollPosition.fraction
        )
    }

    /// Prepares the outer Review projection without invalidating a retained
    /// WebView that has already finalized the same authoritative revision.
    /// The WebView load lifecycle owns readiness changes for an actual reload.
    func prepareReadProjection(for fingerprint: String) {
        failedReadFingerprint = nil
        guard renderedReadFingerprint != fingerprint else { return }
        renderedReadReadyFingerprint = ""
    }

    var requiresReadProjection: Bool {
        !isEnteringManagedCreation
            && presentation.requiresReadProjection(
                editorIsLoaded: editorSession.isLoaded,
                hasEditorError: editorSession.errorMessage != nil
            )
    }

    func readProjectionTaskIdentity(relativePath: String, fingerprint: DocumentFingerprint) -> String? {
        requiresReadProjection ? "\(relativePath):\(fingerprint.sha256)" : nil
    }

    /// The task can be queued before a mode change or finish after one. Both
    /// edges require current demand; the caller still checks source revision
    /// before publishing HTML. This never clears a previously viewed Review.
    func loadReadProjectionIfNeeded(using render: () async -> String) async -> String? {
        guard requiresReadProjection, !Task.isCancelled else { return nil }
        let html = await render()
        guard requiresReadProjection, !Task.isCancelled else { return nil }
        return html
    }

    func preparePresentationMode(_ mode: NotePresentationMode) {
        updatePresentation { $0.prepare(mode) }
    }

    func beginEditing(in mode: MarkdownEditorMode) {
        // Entering Edit is an explicit projection handoff from the active
        // Review viewport. The editor keeps its own subsequent position.
        editorScrollPosition = readScrollPosition
        editorSession.setScrollPosition(
            anchor: editorScrollPosition.anchor,
            fallbackFraction: editorScrollPosition.fraction
        )
        updatePresentation { $0.beginEditing(mode) }
    }

    func switchEditorMode(to mode: MarkdownEditorMode) {
        updatePresentation { $0.switchEditorMode(to: mode) }
    }

    func finishEditing() {
        // Returning to Review is the opposite explicit handoff. This is not a
        // shared live state: later hidden-editor reports cannot change Read.
        readScrollPosition = editorScrollPosition
        completeManagedCreationEntry()
        updatePresentation { $0.finishEditing() }
    }

    func resetPresentation() {
        completeManagedCreationEntry()
        updatePresentation { $0.reset() }
    }

    private func updatePresentation(
        _ update: (inout DocumentPresentationState) -> Void
    ) {
        var next = presentation
        update(&next)
        guard next != presentation else { return }
        presentation = next
    }

    func cancelScheduledWork() {
        cancelAutosave()
        detachmentPreparationTask?.cancel()
        detachmentResumeTask?.cancel()
        detachmentResumeTask = nil
        detachmentResumeToken = nil
        activeSaveTask?.cancel()
        activeSaveTask = nil
        activeSaveCommitReceipt = nil
        activeSaveToken = nil
    }

    func cancelAutosave() {
        autosaveDeadline = nil
        autosaveTask?.cancel()
        autosaveTask = nil
        autosaveToken = nil
    }

    func finishAutosave(token: UUID) {
        guard autosaveToken == token else { return }
        autosaveDeadline = nil
        autosaveTask = nil
        autosaveToken = nil
    }

    /// Releases reconstruction-sensitive state after the owning tab lease and
    /// every recovery pin are gone. A still-attached WebView is never torn
    /// out from underneath AppKit; the store retries reaping after detach.
    func shutdown() {
        precondition(!editorSession.hasAttachedWebView)
        cancelScheduledWork()
        editorCancellable?.cancel()
        editorCancellable = nil
        editorSession.shutdownDetachedSession()
        editingSource = ""
        originalEditingSource = ""
        editingRevision = nil
        pendingEditorCommit = nil
        renderedReadHTML = ""
        renderedReadFingerprint = ""
        renderedReadReadyFingerprint = ""
        failedReadFingerprint = nil
        previewCatalog = nil
        readSelection = nil
        conflict = nil
        conflictComparison = nil
        editError = nil
        canRetrySave = false
        managedCreationBodyStartUTF16 = nil
        hasBeenActivated = false
    }

    /// A dirty decision must include both the Swift mirror and CodeMirror's
    /// bridge state. Either side can be newer while an editor message is in
    /// flight, so an external publication may replace the buffer only when
    /// both agree that the session is clean.
    var hasUnsavedChanges: Bool {
        editorSession.isDirty || !editingSource.utf8.elementsEqual(originalEditingSource.utf8)
    }

    /// Presentation readiness does not determine source ownership. A detached
    /// editor retains the checked mirror even though its WebView is unavailable.
    var retainedExactSource: String {
        editorSession.documentID == editorSession.bridgeDocumentID
            ? editorSession.checkedSource
            : editingSource
    }

    var scrollFraction: Double {
        get { activeScrollPosition.fraction }
        set {
            switch activeScrollSurface {
            case .read: readScrollPosition.updateFraction(newValue)
            case .editor: editorScrollPosition.updateFraction(newValue)
            }
        }
    }

    var scrollAnchor: EditorScrollAnchor? {
        get { activeScrollPosition.anchor }
        set {
            switch activeScrollSurface {
            case .read: readScrollPosition.anchor = newValue
            case .editor: editorScrollPosition.anchor = newValue
            }
        }
    }

    /// Observes the active presentation surface. New surface callbacks should
    /// use the overload that names the surface explicitly.
    func observeScrollFraction(_ fraction: Double) {
        observeScrollFraction(fraction, on: activeScrollSurface)
    }

    func observeScrollAnchor(_ anchor: EditorScrollAnchor?) {
        observeScrollAnchor(anchor, on: activeScrollSurface)
    }

    func observeScrollFraction(_ fraction: Double, on surface: DocumentScrollSurface) {
        guard !presentationIsClosed else { return }
        switch surface {
        case .read: readScrollPosition.updateFraction(fraction)
        case .editor: editorScrollPosition.updateFraction(fraction)
        }
    }

    func observeScrollAnchor(_ anchor: EditorScrollAnchor?, on surface: DocumentScrollSurface) {
        guard !presentationIsClosed else { return }
        switch surface {
        case .read: readScrollPosition.anchor = anchor
        case .editor: editorScrollPosition.anchor = anchor
        }
    }

    func adoptEditorScrollPositionForReview(anchor: EditorScrollAnchor?) {
        if let anchor {
            editorScrollPosition.updateFraction(anchor.fallbackFraction)
            editorScrollPosition.anchor = anchor
        }
        readScrollPosition = editorScrollPosition
    }

    @discardableResult
    func requestScrollRestore(
        fingerprint: String,
        reason: ScrollRestoreReason,
        position: ObservedScrollPosition? = nil
    ) -> ScrollRestoreRequest {
        requestReadScrollRestore(
            fingerprint: fingerprint,
            reason: reason,
            position: position ?? activeScrollPosition
        )
    }

    @discardableResult
    func requestReadScrollRestore(
        fingerprint: String,
        reason: ScrollRestoreReason,
        position: ObservedScrollPosition? = nil
    ) -> ScrollRestoreRequest {
        nextScrollRestoreRequestID &+= 1
        let observed = position ?? readScrollPosition
        let matchingAnchor = observed.anchor.flatMap { anchor in
            anchor.sourceFingerprint == fingerprint ? anchor : nil
        }
        let request = ScrollRestoreRequest(
            id: nextScrollRestoreRequestID,
            fingerprint: fingerprint,
            position: ObservedScrollPosition(
                fraction: observed.fraction,
                anchor: matchingAnchor
            ),
            reason: reason
        )
        scrollRestoreRequest = request
        return request
    }

    func resetScrollPosition() {
        readScrollPosition = ObservedScrollPosition()
        editorScrollPosition = ObservedScrollPosition()
        scrollRestoreRequest = nil
    }

    func restoreNavigationPosition(
        _ position: ObservedScrollPosition,
        fingerprint: String
    ) {
        let admitted = ObservedScrollPosition(
            fraction: position.fraction,
            anchor: position.anchor?.sourceFingerprint == fingerprint ? position.anchor : nil
        )
        readScrollPosition = admitted
        editorScrollPosition = admitted
        requestReadScrollRestore(
            fingerprint: fingerprint,
            reason: .explicitNavigation,
            position: admitted
        )
        editorSession.setScrollPosition(
            anchor: admitted.anchor,
            fallbackFraction: admitted.fraction
        )
    }

    /// A successful tab close ends only browsing presentation. Exact source,
    /// save/conflict state and recovery buffers remain owned by this session.
    func endClosedPresentation() {
        presentationIsClosed = true
        resetScrollPosition()
        readSelection = nil
        findPresentation.resetAfterClose()
        let retainsSourceWork =
            hasUnsavedChanges || isSavingEdit
            || activeSaveTask != nil || pendingEditorCommit != nil
            || conflict != nil || canRetrySave || editorSession.isComposing
        editorSession.endClosedPresentation(preservingSourceWork: retainsSourceWork)
        hasBeenActivated = false
    }

    func acknowledgeScrollRestoreRequest(id: UInt64, fingerprint: String) {
        guard scrollRestoreRequest?.id == id,
            scrollRestoreRequest?.fingerprint == fingerprint
        else { return }
        scrollRestoreRequest = nil
    }
}

/// Per-window retention for document sessions. `DocumentController` owns one
/// store, so two windows cannot share editor buffers, undo histories, focus,
/// or saves.
@MainActor
final class DocumentSessionStore {
    #if DEBUG
        struct QADiagnosticCounts: Sendable {
            let retained: Int
            let leased: Int
            let pinned: Int
            let attachedWebView: Int
        }
    #endif

    enum PinReason: Hashable, Sendable {
        case dirty
        case composition
        case conflict
        case saveInFlight
        case retryableRecovery
        case recoveryBuffer
    }

    private struct Entry {
        let session: DocumentSessionModel
        var leaseCount = 0
        var isForeground = false
    }

    private var entries: [DocumentEditingTarget: Entry] = [:]
    private(set) var editorWebViewPool = MarkdownEditorWebViewPool()

    var retainedSessions: [DocumentEditingTarget: DocumentSessionModel] {
        entries.mapValues(\.session)
    }

    #if DEBUG
        var qaDiagnosticCounts: QADiagnosticCounts {
            var leased = 0
            var pinned = 0
            var attachedWebView = 0
            for entry in entries.values {
                if entry.leaseCount > 0 { leased += 1 }
                if !pinReasons(for: entry.session).isEmpty { pinned += 1 }
                if entry.session.editorSession.hasAttachedWebView { attachedWebView += 1 }
            }
            return QADiagnosticCounts(
                retained: entries.count,
                leased: leased,
                pinned: pinned,
                attachedWebView: attachedWebView
            )
        }
    #endif

    func session(for target: DocumentEditingTarget) -> DocumentSessionModel {
        if let existing = entries[target]?.session { return existing }
        let key: DocumentSessionKey? = if case .workspace(let key) = target { key } else { nil }
        let session = DocumentSessionModel(key: key)
        session.editorSession.webViewPool = editorWebViewPool
        entries[target] = Entry(session: session)
        return session
    }

    func session(for key: DocumentSessionKey) -> DocumentSessionModel {
        session(for: .workspace(key))
    }

    func retainedSession(for target: DocumentEditingTarget) -> DocumentSessionModel? {
        entries[target]?.session
    }

    func retainedSession(for key: DocumentSessionKey) -> DocumentSessionModel? {
        retainedSession(for: .workspace(key))
    }

    func takeSession(for target: DocumentEditingTarget) -> DocumentSessionModel? {
        entries.removeValue(forKey: target)?.session
    }

    func receiveSession(_ session: DocumentSessionModel, for target: DocumentEditingTarget) {
        precondition(entries[target] == nil)
        session.editorSession.webViewPool = editorWebViewPool
        entries[target] = Entry(session: session, leaseCount: 1, isForeground: true)
    }

    func reconcileLeases(
        openTargets: [DocumentEditingTarget],
        foregroundTarget: DocumentEditingTarget?
    ) {
        let counts = Dictionary(grouping: openTargets, by: { $0 }).mapValues(\.count)
        for target in counts.keys where entries[target] == nil {
            _ = session(for: target)
        }
        for target in entries.keys {
            entries[target]?.leaseCount = counts[target, default: 0]
            entries[target]?.isForeground = target == foregroundTarget
        }
        reapEligibleSessions()
    }

    func pinReasons(for session: DocumentSessionModel) -> Set<PinReason> {
        var reasons: Set<PinReason> = []
        if session.hasUnsavedChanges { reasons.insert(.dirty) }
        if session.editorSession.isComposing { reasons.insert(.composition) }
        if session.conflict != nil { reasons.insert(.conflict) }
        if session.isSavingEdit || session.activeSaveTask != nil || session.pendingEditorCommit != nil {
            reasons.insert(.saveInFlight)
        }
        if session.detachmentPreparationTask != nil { reasons.insert(.saveInFlight) }
        if session.canRetrySave { reasons.insert(.retryableRecovery) }
        if session.editorSession.hasRecoverableBuffer { reasons.insert(.recoveryBuffer) }
        return reasons
    }

    var leasedOrPinnedSessions: [(DocumentEditingTarget, DocumentSessionModel)] {
        entries.compactMap { target, entry in
            guard entry.leaseCount > 0 || !pinReasons(for: entry.session).isEmpty else {
                return nil
            }
            return (target, entry.session)
        }
    }

    func reapEligibleSessions() {
        let eligible = entries.compactMap { target, entry -> DocumentEditingTarget? in
            guard entry.leaseCount == 0,
                pinReasons(for: entry.session).isEmpty,
                !entry.session.editorSession.hasAttachedWebView
            else { return nil }
            return target
        }
        for target in eligible {
            entries[target]?.session.shutdown()
            entries[target] = nil
        }
    }

    func removeAll() {
        editorWebViewPool.invalidate()
        editorWebViewPool = MarkdownEditorWebViewPool()
        for entry in entries.values {
            if entry.session.editorSession.hasAttachedWebView {
                entry.session.cancelScheduledWork()
            } else {
                entry.session.shutdown()
            }
        }
        entries.removeAll()
    }
}
