import ScholiumContracts
import Combine
import SwiftUI

/// A document session follows stable vault and note identities. Paths and
/// titles are mutable projections and therefore must never own editor state.
struct DocumentSessionKey: Hashable, Sendable {
    let vaultID: UUID
    let noteID: UUID
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
    let editorSession = MarkdownEditorSession()

    @Published private(set) var presentation = DocumentPresentationState()
    @Published var editingSource = ""
    @Published var originalEditingSource = ""
    @Published var editingRevision: DocumentFingerprint?
    @Published var editError: String?
    @Published var isSavingEdit = false
    /// Ordinary WebView scroll reports update this non-published observation.
    /// They must not invalidate the document tree or become restoration input.
    private(set) var observedScrollPosition = ObservedScrollPosition()
    /// Only an explicit lifecycle or navigation transition creates a request.
    /// Coordinators consume each monotonically increasing ID at most once.
    @Published private(set) var scrollRestoreRequest: ScrollRestoreRequest?
    @Published var returnToReadAfterSave = false
    @Published var suppressAutosave = false
    @Published var renderedReadHTML = ""
    @Published var renderedReadFingerprint = ""
    @Published var renderedReadReadyFingerprint = ""
    @Published var failedReadFingerprint: String?
    @Published var previewCatalog: DocumentPreviewCatalog?
    var readSelection: MarkdownReviewSelection?
    @Published var conflict: DocumentConflictSnapshot?
    @Published var canRetrySave = false
    @Published var showConflictComparison = false

    var autosaveTask: Task<Void, Never>?
    var autosaveDeadline: ContinuousClock.Instant?
    var activeSaveTask: Task<EditorSaveOutcome, Error>?
    var activeSaveToken: UUID?
    private var editorCancellable: AnyCancellable?
    private var nextScrollRestoreRequestID: UInt64 = 0

    init(key: DocumentSessionKey?) {
        self.key = key
        editorCancellable = editorSession.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }
    }

    var isEditing: Bool { presentation.isEditing }
    var presentationMode: NotePresentationMode { presentation.activeMode }
    var retainedEditorMode: MarkdownEditorMode { presentation.retainedEditorMode }
    var activeEditorMode: MarkdownEditorMode? { presentation.activeEditorMode }
    var pendingEditorMode: MarkdownEditorMode? { presentation.pendingEditorMode }
    var retainsEditorSurface: Bool { presentation.retainsEditorSurface }

    func preparePresentationMode(_ mode: NotePresentationMode) {
        updatePresentation { $0.prepare(mode) }
    }

    func beginEditing(in mode: MarkdownEditorMode) {
        updatePresentation { $0.beginEditing(mode) }
    }

    func switchEditorMode(to mode: MarkdownEditorMode) {
        updatePresentation { $0.switchEditorMode(to: mode) }
    }

    func finishEditing() {
        updatePresentation { $0.finishEditing() }
    }

    func resetPresentation() {
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
        activeSaveTask?.cancel()
        activeSaveTask = nil
        activeSaveToken = nil
    }

    func cancelAutosave() {
        autosaveDeadline = nil
        autosaveTask?.cancel()
        autosaveTask = nil
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
        renderedReadHTML = ""
        renderedReadFingerprint = ""
        renderedReadReadyFingerprint = ""
        failedReadFingerprint = nil
        previewCatalog = nil
        readSelection = nil
        conflict = nil
        editError = nil
        canRetrySave = false
    }

    /// A dirty decision must include both the Swift mirror and CodeMirror's
    /// bridge state. Either side can be newer while an editor message is in
    /// flight, so an external publication may replace the buffer only when
    /// both agree that the session is clean.
    var hasUnsavedChanges: Bool {
        editorSession.isDirty || editingSource != originalEditingSource
    }

    var scrollFraction: Double {
        get { observedScrollPosition.fraction }
        set { observedScrollPosition.updateFraction(newValue) }
    }

    var scrollAnchor: EditorScrollAnchor? {
        get { observedScrollPosition.anchor }
        set { observedScrollPosition.anchor = newValue }
    }

    func observeScrollFraction(_ fraction: Double) {
        observedScrollPosition.updateFraction(fraction)
    }

    func observeScrollAnchor(_ anchor: EditorScrollAnchor?) {
        observedScrollPosition.anchor = anchor
    }

    @discardableResult
    func requestScrollRestore(
        fingerprint: String,
        reason: ScrollRestoreReason,
        position: ObservedScrollPosition? = nil
    ) -> ScrollRestoreRequest {
        nextScrollRestoreRequestID &+= 1
        let observed = position ?? observedScrollPosition
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
        observedScrollPosition = ObservedScrollPosition()
        scrollRestoreRequest = nil
    }

    func acknowledgeScrollRestoreRequest(id: UInt64, fingerprint: String) {
        guard scrollRestoreRequest?.id == id,
              scrollRestoreRequest?.fingerprint == fingerprint else { return }
        scrollRestoreRequest = nil
    }
}

/// Per-window retention for document sessions. `DocumentController` owns one
/// store, so two windows cannot share editor buffers, undo histories, focus,
/// or saves.
@MainActor
final class DocumentSessionStore {
    enum PinReason: Hashable, Sendable {
        case dirty
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

    struct ReapedPresentation: Sendable {
        let target: DocumentEditingTarget
        let scrollPosition: ObservedScrollPosition
    }

    private var entries: [DocumentEditingTarget: Entry] = [:]

    var retainedSessions: [DocumentEditingTarget: DocumentSessionModel] {
        entries.mapValues(\.session)
    }

    func session(for target: DocumentEditingTarget) -> DocumentSessionModel {
        if let existing = entries[target]?.session { return existing }
        let key: DocumentSessionKey? = if case .workspace(let key) = target { key } else { nil }
        let session = DocumentSessionModel(key: key)
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

    func reconcileLeases(
        openTargets: [DocumentEditingTarget],
        foregroundTarget: DocumentEditingTarget?
    ) -> [ReapedPresentation] {
        let counts = Dictionary(grouping: openTargets, by: { $0 }).mapValues(\.count)
        for target in counts.keys where entries[target] == nil {
            _ = session(for: target)
        }
        for target in entries.keys {
            entries[target]?.leaseCount = counts[target, default: 0]
            entries[target]?.isForeground = target == foregroundTarget
        }
        return reapEligibleSessions()
    }

    func pinReasons(for session: DocumentSessionModel) -> Set<PinReason> {
        var reasons: Set<PinReason> = []
        if session.hasUnsavedChanges { reasons.insert(.dirty) }
        if session.conflict != nil { reasons.insert(.conflict) }
        if session.isSavingEdit || session.activeSaveTask != nil { reasons.insert(.saveInFlight) }
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

    @discardableResult
    func reapEligibleSessions() -> [ReapedPresentation] {
        let eligible = entries.compactMap { target, entry -> ReapedPresentation? in
            guard entry.leaseCount == 0,
                  pinReasons(for: entry.session).isEmpty,
                  !entry.session.editorSession.hasAttachedWebView else { return nil }
            return ReapedPresentation(
                target: target,
                scrollPosition: entry.session.observedScrollPosition
            )
        }
        for presentation in eligible {
            entries[presentation.target]?.session.shutdown()
            entries[presentation.target] = nil
        }
        return eligible
    }

    func removeAll() {
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
