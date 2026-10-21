import AppKit
import Combine
import Foundation
import ScholiumContracts
import SwiftUI
import WebKit

struct MarkdownSourceSelectionSnapshot: Sendable {
    let source: String
    let excerpt: String
    let sourceRange: SearchSourceRange
    var line: Int { sourceRange.line }
}

struct MarkdownEditorPresentationState: Equatable, Sendable {
    enum DocumentPhase: Equatable, Sendable {
        case unavailable
        case loading
        case ready(MarkdownEditorMode)
    }

    private(set) var webContentReady = false
    private(set) var documentPhase: DocumentPhase = .unavailable
    private(set) var errorMessage: String?

    var isLoaded: Bool {
        guard case .ready = documentPhase else { return false }
        return true
    }

    var presentedMode: MarkdownEditorMode? {
        guard case .ready(let mode) = documentPhase else { return nil }
        return mode
    }

    mutating func reset() {
        self = MarkdownEditorPresentationState()
    }

    mutating func webContentBecameReady(hasPendingDocument: Bool) {
        webContentReady = true
        if hasPendingDocument {
            documentPhase = .loading
            errorMessage = nil
        }
    }

    mutating func beginLoading() {
        documentPhase = .loading
        errorMessage = nil
    }

    mutating func complete(_ mode: MarkdownEditorMode) {
        documentPhase = .ready(mode)
    }

    mutating func fail(_ message: String) {
        documentPhase = .unavailable
        errorMessage = message
    }

    mutating func report(_ message: String) {
        errorMessage = message
    }

    mutating func clearReport(matching message: String) {
        guard errorMessage == message else { return }
        errorMessage = nil
    }

    mutating func webContentTerminated() {
        webContentReady = false
        documentPhase = .loading
    }
}

struct MarkdownEditorTextSnapshot: Equatable, Sendable {
    let text: String
    let generation: Int
    var citationData: ZoteroCitationData? = nil
}

typealias EditorImageResourceQuery = @MainActor (String) async -> [String: RenderedMarkdownImage]

/// A persistence input is bound to the editing base as well as exact source.
/// A suspension ID proves a detached snapshot came from an input-frozen page.
struct MarkdownEditorPersistenceSnapshot: Sendable {
    let text: String
    let generation: Int
    let documentID: String
    let fingerprint: String
    let suspensionID: String?
    var citationData: ZoteroCitationData? = nil
    var companionRevision: DocumentFingerprint? = nil
}

enum MarkdownEditorCommitAcknowledgement: Equatable, Sendable {
    case clean
    case superseded
}

@MainActor
final class MarkdownEditorSession: NSObject, ObservableObject {
    private static let modeChangeRecoveryMessage = ScholiumL10n.string(
        "The document mode change was not applied because the editor changed during text composition.")

    private static let rejectedChangeRecoveryMessage = String(
        localized: "The editor buffer could not be synchronized. Autosave will retry without discarding your text.",
        table: "Localizable",
        bundle: .module
    )

    private struct BridgeRequestContext {
        let requestEpoch: UInt64
        let sessionID: UUID
        let documentID: String
        let startingFingerprint: String
        let generation: Int
        let webView: WKWebView
    }

    private struct RecoveryCaptureKey: Equatable {
        let requestEpoch: UInt64
        let generation: Int
    }

    enum SessionError: LocalizedError {
        case unavailable
        case invalidResult
        case selectionTooLong
        case staleRequest
        case bridgeRejected(String)
        case citationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "The Markdown editor is not ready."
            case .invalidResult: "The Markdown editor returned an invalid document."
            case .selectionTooLong: "Select at most 2,000 characters for one source-anchored comment."
            case .staleRequest: "The Markdown editor request belonged to a replaced document or session."
            case .bridgeRejected(let message), .citationFailed(let message): message
            }
        }
    }

    let writingContextChanges = PassthroughSubject<Void, Never>()
    let selectionChanges = PassthroughSubject<Bool, Never>()
    var hasNonemptySelection: Bool {
        lastKnownSelectionSnapshot?.ranges.contains { $0.anchor != $0.head } == true
            && preferredDocumentFocusTarget != .title
    }

    @Published private(set) var presentation = MarkdownEditorPresentationState()
    @Published private(set) var isDirty = false
    /// A bounded retry replaces only this retained session's failed WebView.
    /// `sourceForViewAttachment` restores the checked exact-source mirror.
    @Published private(set) var viewReconstructionID = UUID()
    private(set) var line = 1
    private(set) var column = 1
    private(set) var lineCount = 1
    @Published private(set) var interactionAvailability: EditorInteractionAvailability?
    private(set) var context: MarkdownEditorContext?
    private(set) var sessionID = UUID()
    private(set) var documentID = ""

    /// Opaque identity for the CodeMirror document owned by this retained
    /// session. A vault-relative path is a mutable projection and must not
    /// force a new EditorState when the same stable note is renamed.
    // The transport session rotates on attachment; the document identity must
    // survive that rotation for reconstruction to admit its selection/history.
    let bridgeDocumentID = UUID().uuidString
    private(set) var startingFingerprint = ""
    private(set) var committedCitationSnapshot: ZoteroCitationSnapshot? {
        didSet { cachedCitationFields = nil }
    }
    private(set) var checkedCitationData: ZoteroCitationData? {
        didSet {
            // A checked snapshot with the same absent payload does not change
            // citation authority. Source changes already have an exact-byte
            // fingerprint in the catalog key. Nonempty assignments still
            // invalidate opaque bytes even under canonical Unicode equality.
            if oldValue != nil || checkedCitationData != nil { cachedCitationFields = nil }
        }
    }

    /// Checked in-memory state uses current source coordinates; the committed
    /// snapshot remains the independent portable-file CAS preimage.
    var currentCitationSnapshot: ZoteroCitationSnapshot? {
        guard let base = committedCitationSnapshot else { return nil }
        if base.status == .unresolved || base.status == .unsupported { return base }
        guard let data = checkedCitationData else {
            return ZoteroCitationSnapshot(noteID: base.noteID, vaultID: base.vaultID, status: .absent)
        }
        return ZoteroCitationSnapshot(
            noteID: base.noteID, vaultID: base.vaultID,
            revision: base.revision, sourceFingerprint: checkedSourceBuffer.fingerprint,
            data: data, status: .available)
    }

    /// A disposable catalog of the checked source pair. Read and an editor
    /// whose document has not loaded keep their independent source owners.
    func citationFields(forDocumentID expectedDocumentID: String) -> ZoteroMarkdownFields? {
        guard !documentID.isEmpty, documentID == expectedDocumentID else { return nil }
        let key = CitationFieldsKey(
            documentID: documentID, sourceFingerprint: checkedSourceBuffer.fingerprint,
            citationSnapshot: currentCitationSnapshot)
        if let cachedCitationFields, cachedCitationFields.key == key { return cachedCitationFields.fields }
        let fields = ZoteroMarkdownFields(
            parsing: NoteDocument(relativePath: documentID, rawContent: checkedSource, citationSnapshot: key.citationSnapshot))
        cachedCitationFields = (key, fields)
        return fields
    }

    private(set) var generation = 0 {
        didSet {
            guard generation != oldValue else { return }
            citationInteractionRevision &+= 1
            writingContextChanges.send()
            refreshImageResources()
        }
    }

    let floatingSurfaces = DocumentFloatingSurfaceController()
    var webView: WKWebView?
    var webViewPool: MarkdownEditorWebViewPool?

    /// A bridge request already executing in WebKit cannot be cancelled by
    /// cancelling its Swift task. Only hand an idle, acknowledged page to a
    /// different document; other detach paths keep their recovery behavior.
    var canRecycleWebView: Bool {
        isReady && isLoaded && errorMessage == nil && !isComposing
            && inFlightRequestTasks.isEmpty && unfinishedBridgeDispatches.isEmpty
            && webView?.isLoading == false
            && (webView as? DocumentNativeWebView)?.editorHandoffLease == nil
    }
    private var citationTransactionID: String?
    @Published private(set) var citationStatus: String?
    private var citationCancellationRequested = false
    private var citationInteractionRevision: UInt64 = 0
    private(set) var rendererInteractionRevision: Int?
    private let citationIntegration: any ZoteroDocumentIntegrating
    private var pendingSource: String?
    private var pendingDocumentID = ""
    private var pendingDocumentTitle = ""
    private var deliveredPresentationConfiguration: MarkdownEditorPresentationConfiguration?
    private var presentationConvergenceTask: Task<Void, Error>?
    private var presentationConvergenceID: UUID?
    private var pendingLinkPreviewGeneration = 0
    private var pendingMode: MarkdownEditorMode = .livePreview
    private var pendingPresentationCSS = ""
    private var pendingUserCSS = ""
    private var pendingReviewProjection: MarkdownEditorReviewProjection?
    /// A newer committed HTML projection may arrive before reconciliation has
    /// frozen and replaced the current CM source. Finish the current load with
    /// its own projection; only a source rebase can admit the newer one.
    private var currentReviewProjection: MarkdownEditorReviewProjection?
    private var pendingLine: (line: Int, focusesEditor: Bool)?
    private var pendingSourceRange: Range<Int>?
    private var pendingSourceRangeIsDefault = false
    private var pendingSourceRangeRequiresEditing = false
    private var hasPresentedWritableMode = false
    private var navigationRequestRevision: UInt64 = 0
    private var pendingSourceRangeRevision: UInt64 = 0
    private struct ScrollIntent {
        let revision: UInt64
        let anchor: EditorScrollAnchor?
        let fraction: Double
    }
    private var pendingScrollIntent: ScrollIntent?
    private var navigationIntentTask: Task<Void, Never>?
    private var navigationIntentTaskID: UUID?
    private var pendingLinkPreviews: [MarkdownEditorLinkPreview] = []
    private var pendingImageResources: [String: String] = [:]
    private var pendingImageResourceGeneration = 0
    // Pending admission is not proof of delivery: typing may supersede its
    // generation while earlier presentation operations are still awaiting.
    private var deliveredImageResources: [String: String]?
    private var imageResourceQuery: EditorImageResourceQuery?
    private var imageResourceContextKey = ""
    private var imageResourceQueryTask: Task<Void, Never>?
    private var imageResourceQueryID: UUID?
    private var openingImageWaitTask: Task<Void, any Error>?
    private var openingImageWaitID: UUID?
    private var pendingWritingContinuationEnabled = false
    private var pendingWritingContinuationContextKey = ""
    private var pendingWritingIndexContextKey = ""
    var pendingScrollFraction: Double?
    var pendingScrollAnchor: EditorScrollAnchor?
    @Published private(set) var openingPresentationID = UUID()
    private var reconstructionScrollAnchor: EditorScrollAnchor?
    private var startupTask: Task<Void, Never>?
    private var documentLoadTask: Task<Void, Never>?
    private var focusHandoffTask: Task<Void, Never>?
    private var automaticFocusIsAuthorized = false
    private var presentationIsClosed = false
    private(set) var focusRequestRevision: UInt64 = 0
    private var pendingFocusIntentRevision: UInt64?
    private var automaticFocusTarget: WindowDocumentFocusTarget = .editor
    private var sourceMutationBarrier: Task<Void, Never>?
    private var inFlightRequestTasks: [UUID: Task<MarkdownEditorCommandResult, Error>] = [:]
    // Unlike the caller's request queue, this survives cancellation and
    // deadline expiry until the actual WebKit dispatch has returned.
    private var unfinishedBridgeDispatches: Set<UUID> = []
    private var requestEpoch: UInt64 = 0
    private var lastQueueInvalidationPreservedRenderer = false
    private var modeTransitionEpoch: UInt64 = 0
    private var modeTransitionTask: Task<Void, Never>?
    private var modeTransitionID: UUID?
    private var modeNeedsReassertion = false
    private var rejectedChangeRecoveryTask: Task<Void, Never>?
    private var rejectedChangeRecoveryID: UUID?
    private var pendingRejectedChangeGeneration: Int?
    private let bridgeDispatcher: any MarkdownEditorBridgeDispatching
    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private var sourceChangeHandler: (() -> Void)?
    private var sourceChangeHandlerOwner: ObjectIdentifier?
    private let checkedSourceBuffer = EditorExactSourceBuffer()
    private struct CitationFieldsKey: Equatable {
        let documentID: String
        let sourceFingerprint: DocumentFingerprint
        let citationSnapshot: ZoteroCitationSnapshot?
    }
    // Companion assignments clear this even when Swift's canonical Unicode
    // equality considers two opaque vendor strings equal.
    private var cachedCitationFields: (key: CitationFieldsKey, fields: ZoteroMarkdownFields)?
    var checkedSource: String { checkedSourceBuffer.snapshot() }
    var isComposing: Bool { context?.composing == true }
    private var checkedEditorUTF16Length = 0
    private var sourceOffsetMap = EditorSourceOffsetMap(source: "")
    private var recoverySnapshot: MarkdownEditorRecoverySnapshot?
    private struct DetachmentCapture {
        let suspensionID: String
        let transportSessionID: UUID
        let snapshot: MarkdownEditorRecoverySnapshot
    }
    private var detachmentCapture: DetachmentCapture?
    private var pendingDetachmentSuspensionID: String?
    var detachmentSuspensionID: String? {
        pendingDetachmentSuspensionID ?? detachmentCapture?.suspensionID
    }

    /// A fresh, hidden Review has never admitted writable source or history.
    /// An external revision may replace its pending initialization directly;
    /// waiting for the superseded HTML would prevent it from ever loading.
    var canReplaceUninitializedReview: Bool {
        pendingMode == .review && pendingSource != nil && !isLoaded && !isDirty && !isComposing
            && generation == 0 && context == nil && recoverySnapshot == nil
            && detachmentSuspensionID == nil
            && (webView as? DocumentNativeWebView)?.documentSurfaceAllowsInput == false
    }
    private var lastKnownSelectionSnapshot: MarkdownEditorSelectionSnapshot?
    private var pendingWindowPresentation: WindowDocumentPresentationSnapshot?
    private(set) var preferredDocumentFocusTarget: WindowDocumentFocusTarget? {
        didSet {
            if preferredDocumentFocusTarget != oldValue { citationInteractionRevision &+= 1 }
        }
    }
    #if DEBUG
        private static let qaTerminationNotification = Notification.Name(
            "com.scholium.qa.simulate-editor-process-termination"
        )
        private var qaTerminationObserverInstalled = false
        var testingOpeningImageWaitID: UUID? { openingImageWaitID }

        var testingReviewPreparationDiagnostics: [String: String] {
            [
                "source": startingFingerprint,
                "pendingSource": pendingSource.map { DocumentFingerprint(content: $0).sha256 } ?? "none",
                "pendingProjection": pendingReviewProjection?.sourceFingerprint ?? "none",
                "currentProjection": currentReviewProjection?.sourceFingerprint ?? "none",
                "deliveredProjection": deliveredPresentationConfiguration?.reviewProjection?.sourceFingerprint ?? "none",
                "pendingMode": pendingMode.rawValue,
                "loaded": String(isLoaded), "ready": String(isReady),
                "suspension": detachmentSuspensionID ?? "none",
                "error": errorMessage ?? "none",
            ]
        }

        struct TestingEditorChangeTiming: Sendable {
            let baseGeneration: Int
            let resultingGeneration: Int
            let accepted: Bool
            let startedAt: ContinuousClock.Instant
            let completedAt: ContinuousClock.Instant
            let validationAndMapping: Duration
            let bufferApply: Duration?
            let offsetMap: Duration?
            let publishingAndCallbacks: Duration?
        }

        /// Opt-in, content-free observation of the existing synchronous path.
        var testingEditorChangeObserver: ((TestingEditorChangeTiming) -> Void)?

        struct TestingImageRefreshTiming: Sendable {
            let generation: Int
            let accepted: Bool
            let startedAt: ContinuousClock.Instant
            let completedAt: ContinuousClock.Instant
            let sourceCapture: Duration
            let containsAndQuery: Duration?
            let admissionGuard: Duration?
            let publication: Duration?
        }

        /// Starts after debounce and initial identity admission; query time can
        /// include suspension and is elapsed time rather than main-actor CPU.
        var testingImageRefreshObserver: ((TestingImageRefreshTiming) -> Void)?

        struct TestingRecoveryRetentionStats: Sendable {
            let currentGeneration: Int
            let recoveryGeneration: Int?
            let recoverySourceUTF8Bytes: Int
            let recoveryHistoryUTF8Bytes: Int
            let detachmentSourceUTF8Bytes: Int
            let detachmentHistoryUTF8Bytes: Int
        }

        /// Logical retained payload sizes, not process RSS or distinct allocations.
        var testingRecoveryRetentionStats: TestingRecoveryRetentionStats {
            TestingRecoveryRetentionStats(
                currentGeneration: generation,
                recoveryGeneration: recoverySnapshot?.generation,
                recoverySourceUTF8Bytes: recoverySnapshot?.source.utf8.count ?? 0,
                recoveryHistoryUTF8Bytes: recoverySnapshot?.stateJSON?.utf8.count ?? 0,
                detachmentSourceUTF8Bytes: detachmentCapture?.snapshot.source.utf8.count ?? 0,
                detachmentHistoryUTF8Bytes: detachmentCapture?.snapshot.stateJSON?.utf8.count ?? 0)
        }
    #endif
    var hasAttachedWebView: Bool { webView != nil }
    var isReady: Bool { presentation.webContentReady }
    var isLoaded: Bool { presentation.isLoaded }
    var presentedMode: MarkdownEditorMode? { presentation.presentedMode }
    var errorMessage: String? { presentation.errorMessage }
    var hasRecoverableBuffer: Bool {
        isDirty || recoverySnapshot?.dirty == true
    }
    var hasRetainedHistory: Bool {
        recoverySnapshot.map {
            $0.undoHistoryPreserved && $0.stateJSON?.isEmpty == false && $0.hasHistory
        } ?? false
    }
    var canAttemptPreview: Bool { pendingMode == .livePreview }

    @discardableResult
    func restoreWindowPresentation(
        _ presentation: WindowDocumentPresentationSnapshot,
        source: String
    ) -> Bool {
        let fingerprint = DocumentFingerprint(content: source).sha256
        let offsetMap = EditorSourceOffsetMap(source: source)
        let ranges = presentation.selections.map {
            MarkdownEditorSelectionRange(anchor: $0.anchor, head: $0.head)
        }
        guard presentation.sourceFingerprint == fingerprint,
            markdownEditorSelectionRangesAreValid(
                ranges,
                forEditorUTF16Length: offsetMap.editorUTF16Length
            )
        else {
            pendingWindowPresentation = nil
            preferredDocumentFocusTarget = nil
            return false
        }
        pendingWindowPresentation = presentation
        preferredDocumentFocusTarget = presentation.focusTarget
        return true
    }

    func windowPresentationSnapshot(
        scrollFraction: Double
    ) -> WindowDocumentPresentationSnapshot {
        if let pendingWindowPresentation {
            return WindowDocumentPresentationSnapshot(
                scrollFraction: scrollFraction,
                sourceFingerprint: pendingWindowPresentation.sourceFingerprint,
                selections: pendingWindowPresentation.selections,
                focusTarget: pendingWindowPresentation.focusTarget
            )
        }
        guard !isDirty,
            let selection = lastKnownSelectionSnapshot,
            selection.isValid(
                documentID: documentID,
                fingerprint: startingFingerprint,
                generation: generation,
                editorUTF16Length: checkedEditorUTF16Length
            )
        else {
            return WindowDocumentPresentationSnapshot(
                scrollFraction: scrollFraction
            )
        }
        return WindowDocumentPresentationSnapshot(
            scrollFraction: scrollFraction,
            sourceFingerprint: selection.fingerprint,
            selections: selection.ranges.map {
                WindowDocumentSelectionRange(anchor: $0.anchor, head: $0.head)
            },
            focusTarget: preferredDocumentFocusTarget
        )
    }

    /// An external clean revision may keep only source coordinates proven to
    /// lie in exact unchanged text. A new EditorState still starts fresh Undo.
    func prepareSelectionForCleanExternalRevision(
        from oldSource: String,
        to newSource: String,
        scrollFraction: Double
    ) {
        let old = windowPresentationSnapshot(scrollFraction: scrollFraction)
        let oldFingerprint = DocumentFingerprint(content: oldSource).sha256
        guard old.sourceFingerprint == oldFingerprint,
            !old.selections.isEmpty,
            let mapped = EditorExternalSelectionMapper.map(
                old.selections.map { .init(anchor: $0.anchor, head: $0.head) },
                from: oldSource,
                to: newSource
            )
        else {
            pendingWindowPresentation = nil
            preferredDocumentFocusTarget = nil
            lastKnownSelectionSnapshot = nil
            return
        }
        let retained = WindowDocumentPresentationSnapshot(
            scrollFraction: scrollFraction,
            sourceFingerprint: DocumentFingerprint(content: newSource).sha256,
            selections: mapped.map { .init(anchor: $0.anchor, head: $0.head) },
            focusTarget: old.focusTarget
        )
        _ = restoreWindowPresentation(retained, source: newSource)
    }

    /// A SwiftUI/AppKit reconstruction of the same retained document must use
    /// the session's exact mirror, not the parent view's lifecycle snapshot.
    /// A different document still initializes from its proposed source.
    func sourceForViewAttachment(
        proposedSource: String,
        documentID proposedDocumentID: String
    ) -> String {
        guard !documentID.isEmpty, documentID == proposedDocumentID else {
            return proposedSource
        }
        return checkedSource
    }
    override convenience init() {
        self.init(
            bridgeDispatcher: WKWebViewMarkdownEditorBridgeDispatcher(),
            lifecyclePolicy: ScholiumLifecyclePolicy()
        )
    }

    init(
        bridgeDispatcher: any MarkdownEditorBridgeDispatching,
        lifecyclePolicy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy(),
        citationIntegration: any ZoteroDocumentIntegrating = WorkspaceStore.citationIntegration
    ) {
        self.bridgeDispatcher = bridgeDispatcher
        self.lifecyclePolicy = lifecyclePolicy
        self.citationIntegration = citationIntegration
        super.init()
    }

    func attach(_ webView: WKWebView) {
        updatePublished(\.citationStatus, to: nil)
        presentationIsClosed = false
        floatingSurfaces.reset()
        invalidateRequestQueue(clearingRecoveryReport: false)
        cancelModeTransition()
        self.webView = webView
        if let handoff = (webView as? DocumentNativeWebView)?.editorHandoffLease,
            !handoff.claim()
        {
            handoff.retire()
        }
        deliveredImageResources = nil
        sessionID = UUID()
        updatePresentation { $0.reset() }
        installQATerminationObserverIfEnabled()
        startupTask?.cancel()
        documentLoadTask?.cancel()
        documentLoadTask = nil
        focusHandoffTask?.cancel()
        startupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, !self.isReady else { return }
            self.reportError(String(localized: "Edit mode did not finish starting.", table: "Localizable", bundle: .module))
        }
    }

    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        (webView as? DocumentNativeWebView)?.editorHandoffLease?.retire()
        floatingSurfaces.reset()
        invalidateRequestQueue(clearingRecoveryReport: false)
        cancelModeTransition()
        startupTask?.cancel()
        documentLoadTask?.cancel()
        documentLoadTask = nil
        focusHandoffTask?.cancel()
        self.webView = nil
        removeQATerminationObserver()

        // SwiftUI calls dismantleNSView while its AttributeGraph is destroying
        // the representable. Publishing from that callback re-enters the same
        // graph transaction and can trip Swift's dynamic exclusivity check.
        // Keep the non-publishing detach synchronous, then reset presentation
        // after teardown has returned. A fast reattach owns the session again
        // and already resets presentation in attach(_:), so it must win.
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.webView == nil else { return }
            // Even a never-ready page completes a lifecycle transition here.
            // Publish its detachment so the document owner can release a
            // closed session after SwiftUI's teardown has returned.
            self.presentation = MarkdownEditorPresentationState()
        }
    }

    /// Clears the retained editor mirror and callbacks only after AppKit has
    /// detached the WebView and the session store proved there is no lease or
    /// recovery pin. Closed documents intentionally do not retain undo state.
    func shutdownDetachedSession() {
        precondition(webView == nil)
        detachmentCapture = nil
        pendingDetachmentSuspensionID = nil
        floatingSurfaces.reset()
        invalidateRequestQueue(clearingRecoveryReport: false)
        startupTask?.cancel()
        startupTask = nil
        documentLoadTask?.cancel()
        documentLoadTask = nil
        focusHandoffTask?.cancel()
        focusHandoffTask = nil
        automaticFocusIsAuthorized = false
        pendingFocusIntentRevision = nil
        automaticFocusTarget = .editor
        sourceChangeHandler = nil
        sourceChangeHandlerOwner = nil
        pendingSource = nil
        pendingSourceRange = nil
        pendingSourceRangeIsDefault = false
        pendingSourceRangeRequiresEditing = false
        hasPresentedWritableMode = false
        pendingDocumentID = ""
        pendingDocumentTitle = ""
        pendingReviewProjection = nil
        currentReviewProjection = nil
        pendingLinkPreviews = []
        pendingLinkPreviewGeneration = 0
        pendingImageResources = [:]
        deliveredImageResources = nil
        removeImageResourceQuery()
        pendingScrollFraction = nil
        pendingScrollAnchor = nil
        pendingScrollIntent = nil
        reconstructionScrollAnchor = nil
        checkedSourceBuffer.replace(with: "")
        committedCitationSnapshot = nil
        checkedCitationData = nil
        checkedEditorUTF16Length = 0
        sourceOffsetMap = EditorSourceOffsetMap(source: "")
        recoverySnapshot = nil
        lastKnownSelectionSnapshot = nil
        pendingWindowPresentation = nil
        preferredDocumentFocusTarget = nil
        cancelModeTransition()
        updatePresentation { $0.reset() }
        updatePublished(\.isDirty, to: false)
    }

    func editorBecameReady() {
        startupTask?.cancel()
        updatePresentation {
            $0.webContentBecameReady(hasPendingDocument: pendingSource != nil)
        }
        flushPendingState()
    }

    /// Applies the rAF-coalesced interaction envelope. Exact cursor
    /// coordinates stay readable for commands and recovery, but they are not
    /// Observable state. Only a semantic availability change invalidates UI.
    @discardableResult
    func updateInteraction(
        selections: [MarkdownEditorSelectionRange],
        line: Int,
        column: Int,
        lineCount: Int,
        documentVersion: Int,
        interactionRevision: Int,
        focusTarget: WindowDocumentFocusTarget? = nil,
        context semanticContext: MarkdownEditorContext?
    ) -> Bool {
        guard !presentationIsClosed else { return false }
        let previousSelection = lastKnownSelectionSnapshot?.ranges
        let previousRendererRevision = rendererInteractionRevision
        let wasComposing = context?.composing == true
        guard documentVersion == generation,
            markdownEditorInteractionRevisionIsValid(interactionRevision),
            previousRendererRevision.map({ interactionRevision >= $0 }) ?? true,
            markdownEditorSelectionRangesAreValid(
                selections,
                forEditorUTF16Length: checkedEditorUTF16Length
            ),
            semanticContext?.selections == nil || semanticContext?.selections == selections
        else { return false }
        rendererInteractionRevision = interactionRevision
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: documentVersion,
            ranges: selections
        )
        if let focusTarget {
            observeFocusTarget(focusTarget)
        }
        self.line = max(1, line)
        self.column = max(1, column)
        self.lineCount = max(1, lineCount)
        if let semanticContext {
            let availability = EditorInteractionAvailability(context: semanticContext)
            context = availability.context(selections: selections)
            updatePublished(\.interactionAvailability, to: availability)
        } else if let interactionAvailability {
            context = interactionAvailability.context(selections: selections)
        }
        if wasComposing, context?.composing == false {
            flushPendingScrollPosition()
            reconvergePendingPresentationState()
        }
        if previousSelection != selections || wasComposing != isComposing || previousRendererRevision != interactionRevision {
            citationInteractionRevision &+= 1
            writingContextChanges.send()
            selectionChanges.send(hasNonemptySelection)
        }
        flushPendingSourceRange()
        return true
    }

    func reportError(_ message: String) {
        (webView as? DocumentNativeWebView)?.editorHandoffLease?.retire()
        startupTask?.cancel()
        cancelModeTransition()
        updatePresentation { $0.fail(message) }
    }

    /// An initialization whose result is unknown cannot be parked or reused.
    /// Defer publication because detachment can run inside SwiftUI teardown.
    func retireQuarantinedHandoff(in webView: WKWebView) {
        guard self.webView === webView else { return }
        invalidateRequestQueue(clearingRecoveryReport: false)
        documentLoadTask?.cancel()
        startupTask?.cancel()
        Task { @MainActor [weak self, weak webView] in
            await Task.yield()
            guard let self, let webView, self.webView === webView,
                (webView as? DocumentNativeWebView)?.editorHandoffLease?.isRetired == true,
                self.errorMessage == nil
            else { return }
            self.updatePresentation {
                $0.fail(String(localized: "Edit mode did not finish starting.", table: "Localizable", bundle: .module))
            }
        }
    }

    func retryUnavailablePresentation() {
        guard !isLoaded else { return }
        updatePresentation { $0.beginLoading() }
        viewReconstructionID = UUID()
    }

    /// Advances the native host identity for a new presentation without
    /// imposing a title- or frontmatter-specific viewport.
    func prepareOpeningPresentation() {
        presentationIsClosed = false
        openingPresentationID = UUID()
    }

    /// Drops clean editor presentation after its tab closes. A recovery buffer
    /// remains available until its separate safety owner releases it.
    func endClosedPresentation(preservingSourceWork: Bool = false) {
        citationInteractionRevision &+= 1
        let retainsComposition = isComposing
        presentationIsClosed = true
        openingPresentationID = UUID()
        pendingWindowPresentation = nil
        preferredDocumentFocusTarget = nil
        if !retainsComposition {
            lastKnownSelectionSnapshot = nil
            pendingSourceRange = nil
            pendingSourceRangeIsDefault = false
            pendingSourceRangeRequiresEditing = false
            pendingLine = nil
        }
        pendingScrollFraction = nil
        pendingScrollAnchor = nil
        pendingScrollIntent = nil
        reconstructionScrollAnchor = nil
        automaticFocusIsAuthorized = false
        pendingFocusIntentRevision = nil
        focusRequestRevision &+= 1
        focusHandoffTask?.cancel()
        focusHandoffTask = nil
        floatingSurfaces.reset()
        if !retainsComposition {
            context = nil
            updatePublished(\.interactionAvailability, to: nil)
        }
        if !preservingSourceWork && !hasRecoverableBuffer {
            sessionID = UUID()
            invalidateRequestQueue(clearingRecoveryReport: false)
            startupTask?.cancel()
            startupTask = nil
            documentLoadTask?.cancel()
            documentLoadTask = nil
            cancelModeTransition()
            recoverySnapshot = nil
            viewReconstructionID = UUID()
        }
    }

    /// First attachment consumes the source already admitted by the document
    /// owner. Reconstruction and recovery still require their complete load.
    func prepareForViewAttachment(
        _ source: String, documentID: String, mode: MarkdownEditorMode,
        citationSnapshot: ZoteroCitationSnapshot?
    ) {
        guard !isReady, generation == 0, !isDirty,
            self.documentID == documentID, pendingDocumentID == documentID,
            let pendingSource, pendingSource.utf8.elementsEqual(source.utf8),
            recoverySnapshot == nil, pendingWindowPresentation == nil
        else {
            loadDocument(source, documentID: documentID, mode: mode, citationSnapshot: citationSnapshot)
            return
        }
        committedCitationSnapshot = citationSnapshot
        checkedCitationData = citationSnapshot?.data
        setMode(mode)
    }

    func loadDocument(
        _ source: String,
        documentID: String,
        mode: MarkdownEditorMode,
        initialSourceRange: Range<Int>? = nil,
        citationSnapshot: ZoteroCitationSnapshot? = nil
    ) {
        if !self.documentID.isEmpty,
            self.documentID != documentID || !checkedSource.utf8.elementsEqual(source.utf8),
            pendingSourceRangeRequiresEditing
        {
            // A first-edit selection belongs to the Review source that
            // supplied it; a later revision cannot inherit that locator.
            pendingSourceRange = nil
            pendingSourceRangeRequiresEditing = false
        }
        if self.documentID != documentID { hasPresentedWritableMode = false }
        let preservesLinkPreviews =
            self.documentID == documentID
            && checkedSource.utf8.elementsEqual(source.utf8) && pendingLinkPreviewGeneration == generation
        // An opening default belongs only to the source that created it. A
        // replacement or failed initialization recomputes its own boundary;
        // explicit navigation retains its independently authorized intent.
        if pendingSourceRangeIsDefault {
            pendingSourceRange = nil
            pendingSourceRangeIsDefault = false
        }
        detachmentCapture = nil
        updatePublished(\.citationStatus, to: nil)
        pendingDetachmentSuspensionID = nil
        floatingSurfaces.reset()
        let publishesLoadingState = isReady
        invalidateRequestQueue()
        let nextFingerprint = DocumentFingerprint(content: source).sha256
        let restoredPresentation = pendingWindowPresentation
        pendingWindowPresentation = nil
        let restoredRanges =
            restoredPresentation?.selections.map {
                MarkdownEditorSelectionRange(anchor: $0.anchor, head: $0.head)
            } ?? []
        let canRestoreWindowPresentation =
            initialSourceRange == nil
            && restoredPresentation?.sourceFingerprint == nextFingerprint
            && markdownEditorSelectionRangesAreValid(
                restoredRanges,
                forEditorUTF16Length: EditorSourceOffsetMap(source: source).editorUTF16Length
            )
        let preservesRecovery =
            recoverySnapshot.map {
                $0.documentID == documentID
                    && $0.fingerprint == startingFingerprint
                    && $0.source.utf8.elementsEqual(source.utf8)
                    && committedCitationSnapshot == citationSnapshot
                    && $0.generation >= 0
                    && markdownEditorSelectionRangesAreValid(
                        $0.ranges,
                        forEditorUTF16Length: EditorSourceOffsetMap(source: source).editorUTF16Length)
            } ?? false
        let retainedStartingFingerprint = preservesRecovery ? startingFingerprint : nil
        if !preservesRecovery {
            committedCitationSnapshot = citationSnapshot
            checkedCitationData = citationSnapshot?.data
        }
        if !preservesRecovery {
            if canRestoreWindowPresentation, let restoredPresentation {
                recoverySnapshot = MarkdownEditorRecoverySnapshot(
                    documentID: documentID,
                    fingerprint: nextFingerprint,
                    generation: 0,
                    ranges: restoredRanges,
                    source: source,
                    stateJSON: nil,
                    undoHistoryPreserved: false,
                    dirty: false,
                    focusTarget: restoredPresentation.focusTarget,
                    citationSnapshot: citationSnapshot,
                    citationData: citationSnapshot?.data
                )
                lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
                    documentID: documentID,
                    fingerprint: nextFingerprint,
                    generation: 0,
                    ranges: restoredRanges
                )
                preferredDocumentFocusTarget = restoredPresentation.focusTarget
            } else {
                recoverySnapshot = nil
                lastKnownSelectionSnapshot = nil
            }
            reconstructionScrollAnchor = nil
            context = nil
            updatePublished(\.interactionAvailability, to: nil)
        }
        pendingSource = source
        pendingDocumentID = documentID
        self.documentID = documentID
        startingFingerprint =
            retainedStartingFingerprint
            ?? nextFingerprint
        currentReviewProjection = reviewProjectionForCurrentSource
        checkedSourceBuffer.replace(with: source)
        sourceOffsetMap = EditorSourceOffsetMap(source: source)
        checkedEditorUTF16Length = sourceOffsetMap.editorUTF16Length
        generation = 0
        if !preservesLinkPreviews { pendingLinkPreviews = [] }
        pendingLinkPreviewGeneration = 0
        pendingImageResources = [:]
        pendingImageResourceGeneration = generation
        deliveredImageResources = nil
        refreshImageResources()
        pendingMode = mode
        if let initialSourceRange {
            pendingSourceRangeIsDefault = false
            pendingSourceRangeRequiresEditing = false
            navigationRequestRevision &+= 1
            pendingSourceRangeRevision = navigationRequestRevision
            let lowerBound = max(0, initialSourceRange.lowerBound)
            pendingSourceRange =
                lowerBound..<max(
                    lowerBound,
                    initialSourceRange.upperBound
                )
        } else if !canRestoreWindowPresentation,
            !preservesRecovery, pendingSourceRange == nil
        {
            pendingSourceRange = 0..<0
            pendingSourceRangeIsDefault = true
            pendingSourceRangeRequiresEditing = false
            pendingSourceRangeRevision = 0
        }
        cancelModeTransition()
        if publishesLoadingState {
            updatePresentation {
                $0.beginLoading()
            }
        }
        if !preservesRecovery { updatePublished(\.isDirty, to: false) }
        flushPendingState()
    }

    func setReviewProjection(_ projection: MarkdownEditorReviewProjection?) {
        guard pendingReviewProjection != projection else { return }
        pendingReviewProjection = projection
        if projection == nil { currentReviewProjection = nil } else { currentReviewProjection = reviewProjectionForCurrentSource }
        flushPendingState()
        reconvergePendingPresentationState()
        if pendingMode == .review, isReady, isLoaded, let webView {
            startModeConvergence(in: webView)
        }
    }

    func setMode(_ mode: MarkdownEditorMode) {
        if pendingMode != mode { citationInteractionRevision &+= 1 }
        let requiresConvergence = pendingMode != mode || presentedMode != mode || modeNeedsReassertion
        pendingMode = mode
        if mode == .source { openingImageWaitTask?.cancel() }
        guard requiresConvergence else { return }
        guard isReady, isLoaded, let webView else { return }
        startModeConvergence(in: webView)
    }

    func setDocumentTitle(_ title: String) {
        pendingDocumentTitle = String(title.prefix(1_024))
        reconvergePendingPresentationState()
    }

    /// Serially converges the retained CodeMirror configuration on the latest
    /// requested editor mode. A newer request never starts a competing bridge
    /// task and never gets discarded merely because the previously published
    /// mode still matches it while another mode is in flight.
    private func startModeConvergence(in webView: WKWebView) {
        guard modeTransitionTask == nil else { return }
        let transitionID = UUID()
        let intendedModeTransitionEpoch = modeTransitionEpoch
        modeTransitionID = transitionID
        let transitionTask = Task.immediate { [weak self, weak webView] in
            guard let self, let webView else { return }
            var failedMode: MarkdownEditorMode?
            var attemptedMode = self.pendingMode
            defer {
                if self.modeTransitionID == transitionID {
                    self.modeTransitionTask = nil
                    self.modeTransitionID = nil
                    // Recovery can arrive while the failure announcement is
                    // awaiting its bridge reply. Converge that newer request,
                    // without automatically retrying the failed mode forever.
                    if let failedMode, self.pendingMode != failedMode {
                        self.startModeConvergence(in: webView)
                    }
                }
            }
            do {
                while true {
                    try Task.checkCancellation()
                    guard intendedModeTransitionEpoch == self.modeTransitionEpoch,
                        self.isReady,
                        self.isLoaded,
                        self.webView === webView
                    else { return }
                    let targetMode = self.pendingMode
                    attemptedMode = targetMode
                    if targetMode == .review {
                        guard !self.isDirty,
                            self.reviewProjectionForCurrentSource != nil
                        else { return }
                        try await self.convergePendingPresentationState(
                            in: webView, requiringRequestEpoch: self.requestEpoch, documentID: self.documentID)
                    }
                    guard self.presentedMode != targetMode || self.modeNeedsReassertion else { return }
                    PerformanceProbe.shared.markEditorModeBridgeStarted(
                        mode: targetMode
                    )
                    // A mode request is idempotent and source-preserving. One
                    // bounded retry safely resolves a transient transport
                    // failure or an acknowledgement lost after the Web side
                    // already applied the compartment, without creating a
                    // second mode owner or an unbounded retry loop.
                    do {
                        _ = try await self.send(.setMode(targetMode), in: webView)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch SessionError.staleRequest {
                        throw SessionError.staleRequest
                    } catch {
                        _ = try await self.send(.setMode(targetMode), in: webView)
                    }
                    guard intendedModeTransitionEpoch == self.modeTransitionEpoch,
                        self.webView === webView
                    else { return }
                    self.modeNeedsReassertion = false
                    self.updatePresentation {
                        $0.complete(targetMode)
                        $0.clearReport(matching: Self.modeChangeRecoveryMessage)
                    }
                    if self.pendingMode == targetMode { return }
                }
            } catch is CancellationError {
                return
            } catch SessionError.staleRequest {
                return
            } catch {
                guard intendedModeTransitionEpoch == self.modeTransitionEpoch,
                    self.webView === webView
                else { return }
                // A rejected acknowledgement may follow an applied Web mode.
                // Reassert the next requested mode even if the last native
                // acknowledgement already names it.
                self.modeNeedsReassertion = true
                failedMode = attemptedMode
                let message = Self.modeChangeRecoveryMessage
                self.updatePresentation { $0.report(message) }
                _ = try? await self.send(.announceStatus(message), in: webView)
            }
        }
        if modeTransitionID == transitionID { modeTransitionTask = transitionTask }
    }

    private func cancelModeTransition() {
        modeTransitionEpoch &+= 1
        modeTransitionTask?.cancel()
        modeTransitionTask = nil
        modeTransitionID = nil
        modeNeedsReassertion = false
    }

    func setUserCSS(_ css: String) {
        pendingUserCSS = css
        reconvergePendingPresentationState()
    }

    func setWritingContinuation(enabled: Bool, contextKey: String) {
        pendingWritingContinuationEnabled = enabled
        pendingWritingContinuationContextKey = String(contextKey.prefix(256))
        reconvergePendingPresentationState()
    }

    func setWritingIndexContext(_ contextKey: String) {
        pendingWritingIndexContextKey = String(contextKey.prefix(256))
        reconvergePendingPresentationState()
    }

    func setPresentationCSS(_ css: String) {
        pendingPresentationCSS = css
        reconvergePendingPresentationState()
    }

    func goToLine(_ line: Int, focusesEditor: Bool = true) {
        if focusesEditor {
            _ = beginFocusIntent(.editor)
        }
        pendingLine = (max(1, line), focusesEditor)
        flushPendingLine()
    }

    func revealSourceRange(fromUTF16: Int, toUTF16: Int) {
        queueSourceRange(fromUTF16: fromUTF16, toUTF16: toUTF16, requiresEditing: false)
    }

    private func queueSourceRange(fromUTF16: Int, toUTF16: Int, requiresEditing: Bool) {
        focusRequestRevision &+= 1
        pendingFocusIntentRevision = nil
        preferredDocumentFocusTarget = .editor
        automaticFocusTarget = .editor
        let lowerBound = max(0, fromUTF16)
        pendingSourceRange = lowerBound..<max(lowerBound, toUTF16)
        pendingSourceRangeIsDefault = false
        pendingSourceRangeRequiresEditing = requiresEditing
        navigationRequestRevision &+= 1
        pendingSourceRangeRevision = navigationRequestRevision
        flushPendingSourceRange()
    }

    func selectAll() async throws {
        guard isReady, isLoaded, !isComposing, let webView else { return }
        try await sendCapturedEditorInput(.selectAll, in: webView)
    }

    func pasteClipboard(plainText: String, selections: [MarkdownEditorSelectionRange]) async throws {
        guard pendingMode != .review, presentedMode != .review, isReady, isLoaded, !isComposing, let webView else { return }
        guard plainText.utf8.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes else {
            let message = WebKitInterfaceLocalization.current().string("The edited Markdown document exceeds the supported editor size.")
            _ = try? await send(.announceStatus(message), in: webView)
            return
        }
        try await sendCapturedEditorInput(.pasteClipboard(plainText: plainText, selections: selections), in: webView)
    }

    private func sendCapturedEditorInput(_ operation: MarkdownEditorOperation, in webView: WKWebView) async throws {
        do {
            _ = try await send(operation, in: webView)
        } catch SessionError.bridgeRejected(let message)
            where message == "clipboard selection changed"
            || message == "stale editor generation"
            || message == "editor identity cannot change during composition"
        {
            // A newer input or composition cancels this captured intent without
            // making the editor unavailable for the next input.
            return
        } catch SessionError.staleRequest {
            return
        }
    }

    /// Applies an original-source locator through the existing generation-checked bridge.
    func revealSourceLocation(_ request: DocumentSourceLocationRequest) async throws {
        guard isReady, isLoaded, !isComposing, let webView else { throw SessionError.unavailable }
        if let expected = request.sourceFingerprint,
            DocumentFingerprint(content: checkedSource).sha256 != expected
        {
            throw DocumentSourceLocationFailure.sourceChanged
        }
        let operation: MarkdownEditorOperation
        if let range = request.range {
            guard range.utf16UpperBound >= range.utf16LowerBound,
                let from = sourceOffsetMap.editorUTF16Offset(forSourceUTF16Offset: range.utf16LowerBound),
                let to = sourceOffsetMap.editorUTF16Offset(forSourceUTF16Offset: range.utf16UpperBound)
            else { throw SessionError.invalidResult }
            operation = .revealSourceRange(fromUTF16: from, toUTF16: to)
        } else if let line = request.line, line > 0 {
            operation = .goToLine(line, focusesEditor: true)
        } else {
            throw SessionError.invalidResult
        }
        let documentID = self.documentID
        let focusRevision = focusRequestRevision
        // No suspension separates revision/offset validation from capturing the
        // bridge generation. A later editor change rejects this operation.
        _ = try await send(operation, in: webView)
        guard !Task.isCancelled, self.webView === webView, self.documentID == documentID,
            focusRequestRevision == focusRevision,
            webView.window?.makeFirstResponder(webView) == true
        else { return }
        try await focusAndWait(.editor)
    }

    func setScrollFraction(_ fraction: Double) {
        setScrollPosition(anchor: nil, fallbackFraction: fraction)
    }

    func setScrollPosition(anchor: EditorScrollAnchor?, fallbackFraction: Double) {
        let normalized = min(1, max(0, fallbackFraction))
        // A new explicit handoff supersedes the outgoing view's captured
        // restoration fallback, including on the next renderer allocation.
        reconstructionScrollAnchor = nil
        pendingScrollFraction = normalized
        pendingScrollAnchor = anchor
        navigationRequestRevision &+= 1
        pendingScrollIntent = ScrollIntent(revision: navigationRequestRevision, anchor: anchor, fraction: normalized)
        flushPendingScrollPosition()
    }

    /// Explicit navigation is independent of the retained scroll observations
    /// reported by CodeMirror. Only the latest unconsumed intent is replayed.
    private func flushPendingScrollPosition() {
        _ = flushPendingNavigationIntents()
    }

    private var canApplyPendingSourceRange: Bool {
        pendingSourceRange != nil
            && (!pendingSourceRangeRequiresEditing || (pendingMode != .review && presentedMode != .review))
    }

    @discardableResult
    private func flushPendingNavigationIntents() -> Task<Void, Never>? {
        if let navigationIntentTask { return navigationIntentTask }
        guard isReady, isLoaded, !isComposing, let webView,
            canApplyPendingSourceRange || pendingScrollIntent != nil
        else { return nil }
        let epoch = requestEpoch
        let intendedDocumentID = documentID
        let taskID = UUID()
        navigationIntentTaskID = taskID
        let task = Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            defer {
                if self.requestEpoch == epoch, self.navigationIntentTaskID == taskID {
                    self.navigationIntentTask = nil
                    self.navigationIntentTaskID = nil
                }
            }
            while self.requestEpoch == epoch, self.documentID == intendedDocumentID,
                self.webView === webView, self.isLoaded, !self.isComposing,
                self.canApplyPendingSourceRange || self.pendingScrollIntent != nil
            {
                do {
                    try await self.applyPendingSourceRange(in: webView, requiringRequestEpoch: epoch)
                    try await self.applyPendingScrollPosition(in: webView, requiringRequestEpoch: epoch)
                } catch { return }
            }
        }
        navigationIntentTask = task
        return task
    }

    private func applyPendingScrollPosition(in webView: WKWebView, requiringRequestEpoch epoch: UInt64) async throws {
        guard epoch == requestEpoch, self.webView === webView, isLoaded, !isComposing,
            let intent = pendingScrollIntent
        else { return }
        if intent.revision < pendingSourceRangeRevision {
            pendingScrollIntent = nil
            return
        }
        defer {
            if requestEpoch == epoch, pendingScrollIntent?.revision == intent.revision { pendingScrollIntent = nil }
        }
        let operation: MarkdownEditorOperation =
            intent.anchor.flatMap { wireAnchor(from: $0, in: checkedSource) }
            .map(MarkdownEditorOperation.setScrollAnchor) ?? .setScrollFraction(intent.fraction)
        _ = try await send(operation, in: webView, requiringRequestEpoch: epoch)
    }

    func recordScrollFraction(_ fraction: Double) {
        pendingScrollFraction = min(1, max(0, fraction))
    }

    /// An acknowledged Review reports exact-source coordinates. Remember its
    /// current viewport without creating a navigation or restoration intent.
    func recordReviewScrollPosition(_ position: ObservedScrollPosition) {
        guard isReady, isLoaded, pendingMode == .review, presentedMode == .review,
            position.fraction.isFinite, (0...1).contains(position.fraction)
        else { return }
        pendingScrollFraction = position.fraction
        reconstructionScrollAnchor = nil
        pendingScrollAnchor = position.anchor.flatMap { anchor in
            anchor.sourceFingerprint == startingFingerprint
                && anchor.isValid(forUTF16Length: checkedSourceBuffer.utf16Length) ? anchor : nil
        }
    }

    func recordScrollPosition(
        _ wireAnchor: MarkdownEditorWireScrollAnchor?,
        fallbackFraction: Double
    ) -> EditorScrollAnchor? {
        let fraction = min(1, max(0, fallbackFraction))
        pendingScrollFraction = fraction
        guard let wireAnchor,
            let sourceOffset = sourceOffsetMap.sourceUTF16Offset(
                forEditorUTF16Offset: wireAnchor.sourceUTF16Offset
            ),
            let lowerBound = sourceOffsetMap.sourceUTF16Offset(
                forEditorUTF16Offset: wireAnchor.blockUTF16LowerBound
            ),
            let upperBound = sourceOffsetMap.sourceUTF16Offset(
                forEditorUTF16Offset: wireAnchor.blockUTF16UpperBound
            )
        else {
            pendingScrollAnchor = nil
            return nil
        }
        let anchor = EditorScrollAnchor(
            sourceFingerprint: checkedSourceBuffer.fingerprint.sha256,
            sourceUTF16Offset: sourceOffset,
            blockUTF16LowerBound: lowerBound,
            blockUTF16UpperBound: upperBound,
            relativeBlockPosition: wireAnchor.relativeBlockPosition,
            fallbackFraction: fraction
        )
        guard anchor.isValid(forUTF16Length: checkedSourceBuffer.utf16Length) else {
            pendingScrollAnchor = nil
            return nil
        }
        pendingScrollAnchor = reconstructionScrollAnchor ?? anchor
        return anchor
    }

    func retainedScrollFraction(fallback: Double) -> Double {
        pendingScrollFraction ?? min(1, max(0, fallback))
    }

    var retainedScrollAnchor: EditorScrollAnchor? {
        reconstructionScrollAnchor ?? pendingScrollAnchor
    }

    /// The active page may refer only to raster resources Native already delivered.
    /// Never interpret a peer Note's raw image filename in the current catalog.
    func deliveredPreviewImageResources(for keys: [String]) -> [String: String] {
        guard let deliveredImageResources else { return [:] }
        return keys.reduce(into: [:]) { resources, key in
            if let value = deliveredImageResources[key] { resources[key] = value }
        }
    }

    func setLinkPreviews(_ previews: [DocumentLinkPreview], in source: String) {
        pendingLinkPreviewGeneration = generation
        let offsetMap =
            source.utf8.elementsEqual(checkedSource.utf8)
            ? sourceOffsetMap
            : EditorSourceOffsetMap(source: source)
        pendingLinkPreviews = previews.prefix(DocumentPreviewCatalogBuilder.maximumLinkCount).compactMap { preview in
            guard
                let from = offsetMap.editorUTF16Offset(
                    forSourceUTF16Offset: preview.sourceSpan.utf16LowerBound
                ),
                let to = offsetMap.editorUTF16Offset(
                    forSourceUTF16Offset: preview.sourceSpan.utf16UpperBound
                ), to > from
            else { return nil }
            return MarkdownEditorLinkPreview(
                from: from,
                to: to,
                title: String(preview.title.prefix(240)),
                isEmbedded: preview.syntax == .embed,
                fragment: preview.fragment.map { String($0.prefix(240)) },
                htmlBody: preview.syntax == .embed
                    ? preview.htmlBody
                    : String(preview.htmlBody.prefix(24_000))
            )
        }
        reconvergePendingPresentationState()
    }

    func installImageResourceQuery(
        _ query: @escaping EditorImageResourceQuery,
        contextKey: String
    ) {
        let requiresRefresh = imageResourceQuery == nil || imageResourceContextKey != contextKey
        imageResourceQuery = query
        imageResourceContextKey = contextKey
        if requiresRefresh { refreshImageResources() }
    }

    func removeImageResourceQuery() {
        imageResourceQueryTask?.cancel()
        imageResourceQueryTask = nil
        imageResourceQueryID = nil
        imageResourceQuery = nil
    }

    /// Resolve the checked live buffer, which may be newer than SwiftUI's
    /// commit-paced source. A later edit or attachment context cancels and
    /// supersedes this read without changing any editor transaction.
    private func refreshImageResources() {
        imageResourceQueryTask?.cancel()
        imageResourceQueryTask = nil
        imageResourceQueryID = nil
        guard imageResourceQuery != nil, !documentID.isEmpty, !presentationIsClosed else { return }
        let queryID = UUID()
        let intendedRequestEpoch = requestEpoch
        let intendedDocumentID = documentID
        let intendedContextKey = imageResourceContextKey
        let debouncesChanges = isLoaded
        imageResourceQueryID = queryID
        imageResourceQueryTask = Task { @MainActor [weak self] in
            if debouncesChanges {
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            }
            guard let self, !Task.isCancelled, !self.presentationIsClosed,
                intendedRequestEpoch == self.requestEpoch,
                intendedDocumentID == self.documentID,
                intendedContextKey == self.imageResourceContextKey,
                let query = self.imageResourceQuery
            else { return }
            defer {
                if self.imageResourceQueryID == queryID {
                    self.imageResourceQueryTask = nil
                    self.imageResourceQueryID = nil
                }
            }
            #if DEBUG
                let timingObserver = self.testingImageRefreshObserver
                let timingStartedAt: ContinuousClock.Instant? = timingObserver == nil ? nil : .now
                var timingGeneration: Int?
                var timingSourceCapturedAt: ContinuousClock.Instant?
                var timingQueryCompletedAt: ContinuousClock.Instant?
                var timingAdmittedAt: ContinuousClock.Instant?
                var timingAccepted = false
                defer {
                    if let timingObserver, let timingStartedAt, let timingGeneration {
                        let completedAt = ContinuousClock.now
                        timingObserver(
                            TestingImageRefreshTiming(
                                generation: timingGeneration, accepted: timingAccepted,
                                startedAt: timingStartedAt, completedAt: completedAt,
                                sourceCapture: timingStartedAt.duration(to: timingSourceCapturedAt ?? completedAt),
                                containsAndQuery: timingSourceCapturedAt.map { $0.duration(to: timingQueryCompletedAt ?? completedAt) },
                                admissionGuard: timingQueryCompletedAt.map { $0.duration(to: timingAdmittedAt ?? completedAt) },
                                publication: timingAdmittedAt.map { $0.duration(to: completedAt) }))
                    }
                }
            #endif
            let source = self.checkedSource
            let expectedGeneration = self.generation
            #if DEBUG
                if timingObserver != nil {
                    timingGeneration = expectedGeneration
                    timingSourceCapturedAt = .now
                }
            #endif
            let images = source.contains("![") ? await query(source) : [:]
            #if DEBUG
                if timingObserver != nil { timingQueryCompletedAt = .now }
            #endif
            guard !Task.isCancelled, !self.presentationIsClosed,
                intendedRequestEpoch == self.requestEpoch,
                intendedDocumentID == self.documentID,
                intendedContextKey == self.imageResourceContextKey,
                self.imageResourceQueryID == queryID,
                expectedGeneration == self.generation,
                self.checkedSourceBuffer.isEqual(to: source)
            else { return }
            #if DEBUG
                if timingObserver != nil { timingAdmittedAt = .now }
            #endif
            self.setImageResources(images, documentID: intendedDocumentID, generation: expectedGeneration)
            #if DEBUG
                timingAccepted = true
            #endif
        }
    }

    /// Only image bytes admitted by Documents.exportImages become data URLs.
    /// Replace the catalog as one presentation change, outside Undo/history.
    func setImageResources(
        _ images: [String: RenderedMarkdownImage],
        documentID expectedDocumentID: String,
        generation expectedGeneration: Int
    ) {
        guard !presentationIsClosed,
            expectedDocumentID == documentID, expectedGeneration == generation
        else { return }
        var resources: [String: String] = [:]
        var decodedBytes = 0
        var metadataBytes = 1_024
        for destination in images.keys.sorted() {
            guard let image = images[destination] else { continue }
            let keyBytes = destination.utf8.count * 6 + 64
            guard image.data.count <= markdownEditorMaximumImageResourceBytes - decodedBytes,
                keyBytes <= markdownEditorMaximumImageResourceMetadataBytes - metadataBytes
            else { continue }
            resources[destination] = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
            decodedBytes += image.data.count
            metadataBytes += keyBytes
        }
        let requiresConvergence =
            pendingImageResources != resources
            || pendingImageResourceGeneration != expectedGeneration
            || deliveredImageResources != resources
        pendingImageResources = resources
        pendingImageResourceGeneration = expectedGeneration
        guard requiresConvergence else { return }
        reconvergePendingPresentationState()
    }

    func showPreview(
        for preview: DocumentLinkPreview,
        previews: [DocumentLinkPreview],
        performanceDocumentID: String,
        in source: String
    ) async {
        guard canAttemptPreview, isReady, isLoaded, let webView else { return }
        let offsetMap =
            source.utf8.elementsEqual(checkedSource.utf8)
            ? sourceOffsetMap
            : EditorSourceOffsetMap(source: source)
        guard
            let from = offsetMap.editorUTF16Offset(
                forSourceUTF16Offset: preview.sourceSpan.utf16LowerBound
            ),
            let to = offsetMap.editorUTF16Offset(
                forSourceUTF16Offset: preview.sourceSpan.utf16UpperBound
            ), to > from
        else { return }
        let insertion = from + (to - from) / 2
        do {
            // The regular preview update is asynchronous. Acknowledge its
            // delivery before the measured action uses it.
            setLinkPreviews(previews, in: source)
            try await convergePendingPresentationState(
                in: webView, requiringRequestEpoch: requestEpoch, documentID: documentID)
            _ = try await send(
                .revealSourceRange(fromUTF16: insertion, toUTF16: insertion),
                in: webView
            )
            // Wait for the selection and its native anchor to be laid out.
            _ = try await webView.callAsyncJavaScript(
                "await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))); return true;",
                arguments: [:], in: nil, contentWorld: .page
            )
            PerformanceProbe.shared.beginEditorCachedPreview(documentID: performanceDocumentID)
            _ = try await send(.showPreview, in: webView)
        } catch {
            return
        }
    }

    func measureVisibleProjection() {
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.measureVisibleProjection, in: webView)
        }
    }

    func currentText(for expectedDocumentID: String? = nil) async throws -> String {
        try await currentTextSnapshot(for: expectedDocumentID).text
    }

    func passageSourceSnapshot(expectedSelections: [MarkdownEditorSelectionRange]?, expectedGeneration: Int) async throws -> MarkdownSourceSelectionSnapshot {
        guard !isComposing, isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let epoch = requestEpoch
        let identity = documentID
        let result = try await send(.queryText, in: webView)
        guard epoch == requestEpoch, identity == documentID, self.webView === webView,
            result.resultingGeneration == generation, generation == expectedGeneration,
            result.selections == expectedSelections, !isComposing, let source = result.text,
            result.selections.count == 1, let selection = result.selections.first
        else { throw SessionError.invalidResult }
        if selection.isNonempty {
            let captured = try MarkdownWritingContextProjection.capture(source: source, selections: result.selections, mode: .selectionOnly)
            guard
                let span = try? ParagraphAnchorPlanner.paragraph(
                    in: NoteDocument(relativePath: identity, rawContent: source), atUTF16: captured.sourceRange.utf16LowerBound)
            else { return captured }
            return DocumentPassageSnapshot.includingParagraphIdentity(captured, paragraphSpan: span)
        }
        guard let offset = EditorSourceOffsetMap(source: source).sourceUTF16Offset(forEditorUTF16Offset: selection.head) else {
            throw SessionError.invalidResult
        }
        let span = try ParagraphAnchorPlanner.paragraph(in: NoteDocument(relativePath: identity, rawContent: source), atUTF16: offset)
        guard let snapshot = DocumentPassageSnapshot.capture(source: source, range: span.nsRange) else { throw SessionError.invalidResult }
        return snapshot
    }

    func selectedSourceSnapshot() async throws -> MarkdownSourceSelectionSnapshot {
        try await writingContextSnapshot(mode: .selectionOnly).snapshot
    }

    /// A read request may not reconcile the mirror, dispatch queued selection
    /// intents, or provoke an autosave. The ordinary editor stream remains its owner.
    func currentChatMetadata() async throws -> (AgentChatDocumentObservation.Revision, AgentChatDocumentObservation.Selection) {
        if isComposing { return (.unavailable(.composing), .unavailable(.composing)) }
        guard isReady, isLoaded, webView != nil else { return (.unavailable(.loading), .unavailable(.loading)) }
        do {
            let snapshot = try await currentAgentSourceSnapshot()
            return (.editorSnapshot(snapshot.fingerprint), snapshot.selection)
        } catch let failure as ScholiumMCPFailure where failure.code == .workspaceNotReady {
            return (.unavailable(.sourceSnapshotUnavailable), .unavailable(.sourceMappingUnavailable))
        }
    }

    /// Exact demand-driven source capture. The caller separately controls
    /// whether source text may leave the App; metadata-only callers discard it.
    /// This query never reconciles a mirror, saves or consumes navigation intents.
    func currentAgentSourceSnapshot() async throws -> (
        source: String, fingerprint: DocumentFingerprint, selection: AgentChatDocumentObservation.Selection
    ) {
        guard !isComposing, isReady, isLoaded, let webView else {
            throw ScholiumMCPFailure.chatObservation(.workspaceNotReady)
        }
        let epoch = requestEpoch
        let interaction = citationInteractionRevision
        guard let rendererInteraction = rendererInteractionRevision else {
            throw ScholiumMCPFailure.chatObservation(.staleRevision)
        }
        let modeEpoch = modeTransitionEpoch
        let result: MarkdownEditorCommandResult
        do {
            result = try await send(.queryText, in: webView, observingOnly: true)
        } catch {
            guard epoch == requestEpoch, interaction == citationInteractionRevision,
                rendererInteraction == rendererInteractionRevision, modeEpoch == modeTransitionEpoch,
                self.webView === webView, !Task.isCancelled
            else { throw ScholiumMCPFailure.chatObservation(.staleRevision) }
            if case SessionError.staleRequest = error { throw ScholiumMCPFailure.chatObservation(.staleRevision) }
            if case SessionError.invalidResult = error { throw ScholiumMCPFailure.chatObservation(.staleRevision) }
            throw ScholiumMCPFailure.chatObservation(.workspaceNotReady)
        }
        guard epoch == requestEpoch, interaction == citationInteractionRevision,
            rendererInteraction == rendererInteractionRevision, result.interactionRevision == rendererInteraction,
            modeEpoch == modeTransitionEpoch,
            self.webView === webView, !Task.isCancelled, !isComposing,
            result.resultingGeneration == generation, let source = result.text,
            result.context?.composing != true,
            result.selections == lastKnownSelectionSnapshot?.ranges
        else { throw ScholiumMCPFailure.chatObservation(.staleRevision) }
        let selection: AgentChatDocumentObservation.Selection =
            preferredDocumentFocusTarget == .title
            ? .unavailable(.sourceMappingUnavailable) : .editor(source: source, selections: result.selections)
        return (source, DocumentFingerprint(content: source), selection)
    }

    func writingContextSnapshot(mode: MarkdownWritingContextCaptureMode) async throws -> (
        snapshot: MarkdownSourceSelectionSnapshot, point: MarkdownEditorInsertionPoint?
    ) {
        guard !isComposing, isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let identity = documentID
        let sourceAtStart = checkedSource
        let generationAtStart = generation
        let interactionAtStart = rendererInteractionRevision
        let selectionsAtStart = lastKnownSelectionSnapshot?.ranges
        let modeAtStart = modeTransitionEpoch
        let interactionAuthorityAtStart = citationInteractionRevision
        func unchangedWritingPoint() -> Bool {
            isReady && isLoaded && !isComposing && self.webView === webView && documentID == identity
                && generation == generationAtStart && modeTransitionEpoch == modeAtStart
                && citationInteractionRevision == interactionAuthorityAtStart
                && checkedSource.utf8.elementsEqual(sourceAtStart.utf8)
                && lastKnownSelectionSnapshot?.ranges == selectionsAtStart
                && rendererInteractionRevision == interactionAtStart
        }
        // A save may rebase only the committed fingerprint while this read is
        // suspended. Recapture once, under the new bridge identity, only when
        // its source, interaction and renderer lifetime are still proved equal.
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let epoch = requestEpoch
            do {
                let result = try await send(.queryText, in: webView)
                try Task.checkCancellation()
                guard epoch == requestEpoch, unchangedWritingPoint(),
                    result.resultingGeneration == generation, result.selections == selectionsAtStart,
                    result.interactionRevision == interactionAtStart, let source = result.text
                else { throw SessionError.staleRequest }
                let snapshot = try MarkdownWritingContextProjection.capture(source: source, selections: result.selections, mode: mode)
                let point = result.selections.first.flatMap { selection -> MarkdownEditorInsertionPoint? in
                    guard !selection.isNonempty else { return nil }
                    return .init(sessionID: sessionID, documentID: identity, generation: generation, selection: selection)
                }
                return (snapshot, point)
            } catch {
                let invalidatedRead =
                    error is CancellationError
                    || (error as? SessionError).map {
                        if case .staleRequest = $0 { true } else { false }
                    } == true
                guard attempt == 0, invalidatedRead, !Task.isCancelled,
                    epoch &+ 1 == requestEpoch, lastQueueInvalidationPreservedRenderer,
                    interactionAtStart != nil, unchangedWritingPoint()
                else { throw error }
            }
        }
        throw SessionError.staleRequest
    }

    var hasWritingFocus: Bool {
        guard let webView, webView.window?.isKeyWindow == true,
            let responder = webView.window?.firstResponder as? NSView
        else { return false }
        return responder === webView || responder.isDescendant(of: webView)
    }

    func acceptsInsertionPoint(_ point: MarkdownEditorInsertionPoint) -> Bool {
        !isComposing && isReady && isLoaded && point.sessionID == sessionID && point.documentID == documentID
            && point.generation == generation && lastKnownSelectionSnapshot?.ranges == [point.selection]
    }

    func insertReference(_ target: String, at point: MarkdownEditorInsertionPoint) async throws {
        guard acceptsInsertionPoint(point), let webView else { throw SessionError.invalidResult }
        _ = try await send(.insertReference(selection: point.selection, generation: point.generation, target: target), in: webView)
    }

    func currentTextSnapshot(
        for expectedDocumentID: String? = nil
    ) async throws -> MarkdownEditorTextSnapshot {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
            isReady, isLoaded, let webView
        else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let intendedDocumentID = documentID
        let intendedFingerprint = startingFingerprint
        let result = try await send(.queryText, in: webView)
        guard intendedRequestEpoch == requestEpoch,
            intendedDocumentID == documentID,
            intendedFingerprint == startingFingerprint,
            self.webView === webView,
            let text = result.text
        else { throw SessionError.invalidResult }
        return MarkdownEditorTextSnapshot(
            text: text,
            generation: result.resultingGeneration,
            citationData: result.citationData
        )
    }

    /// A retained editor can be briefly unavailable while SwiftUI reattaches
    /// its WebView after a document projection changes. Saves must wait for
    /// that same session to finish loading instead of treating the transient
    /// presentation gap as loss of the authoritative CodeMirror buffer.
    func waitUntilLoadedForSave(
        maximumWait: Duration = .seconds(6)
    ) async throws -> Bool {
        if isReady, isLoaded, webView != nil { return true }
        // Document loading already has one authoritative lifecycle task. Join
        // that task instead of polling the published projection and racing the
        // WebKit bridge under main-actor contention. The bounded fallback is
        // only for a reattachment gap before `editorBecameReady()` has had a
        // chance to install the task.
        let expectedDocumentID = documentID
        let expectedWebView = webView
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: maximumWait)
        while true {
            try Task.checkCancellation()
            guard documentID == expectedDocumentID,
                expectedWebView == nil || webView === expectedWebView
            else { return false }
            if isReady, isLoaded, webView != nil { return true }
            if case .unavailable = presentation.documentPhase, errorMessage != nil { return false }
            // The handshake may install the current load after this waiter
            // starts. Join that task as soon as it exists, rather than a load
            // cancelled by an earlier WebView attachment.
            if let documentLoadTask {
                let loadEpoch = requestEpoch
                await documentLoadTask.value
                try Task.checkCancellation()
                guard documentID == expectedDocumentID,
                    expectedWebView == nil || webView === expectedWebView
                else { return false }
                // A clean external publication can replace the pending load
                // without changing the Note or its native attachment.
                if loadEpoch != requestEpoch { continue }
                return isReady && isLoaded && webView != nil
            }
            guard clock.now < deadline else { return false }
            try await clock.sleep(for: .milliseconds(50))
        }
    }

    /// Captures CodeMirror's exact source, selection, and bounded history before
    /// SwiftUI removes the WKWebView during a note collapse or replacement.
    /// The retained document session replays this snapshot into the next view.
    func captureStateForViewReconstruction(suspendForDetachment: Bool = false) async throws {
        if suspendForDetachment, hasAttachedWebView, !isReady || !isLoaded {
            // Departure can arrive before the current document's bootstrap
            // acknowledges readiness. Join that lifecycle before freezing its
            // authoritative buffer; loading is not a failed save, and a clean
            // native mirror cannot prove that WebKit has no pending input.
            guard try await waitUntilLoadedForSave() else { throw SessionError.unavailable }
        }
        if suspendForDetachment { citationInteractionRevision &+= 1 }
        var expectedKey = RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        )
        var capturedNewFrozenState = false
        var frozenScrollAnchor: MarkdownEditorWireScrollAnchor?
        if suspendForDetachment {
            guard !isComposing, isReady, isLoaded, let webView else {
                throw SessionError.unavailable
            }
            let existingCapture = validFrozenPersistenceCapture
            // The acknowledged suspension freezes CodeMirror input. Repeated
            // departure preparation can retain that exact recovery/history
            // proof; commit rebase, resume, or reattachment invalidates it.
            if existingCapture == nil {
                let suspensionID = pendingDetachmentSuspensionID ?? UUID().uuidString
                pendingDetachmentSuspensionID = suspensionID
                do {
                    let result = try await send(.suspendForDetachment(suspensionID: suspensionID), in: webView)
                    guard self.webView === webView,
                        pendingDetachmentSuspensionID == suspensionID,
                        let snapshot = result.recovery,
                        snapshot.undoHistoryPreserved,
                        snapshot.stateJSON?.isEmpty == false,
                        snapshot.documentID == documentID,
                        snapshot.fingerprint == startingFingerprint,
                        snapshot.generation == generation,
                        snapshot.source.utf8.elementsEqual(checkedSource.utf8),
                        snapshot.citationSnapshot == committedCitationSnapshot,
                        snapshot.citationData == checkedCitationData,
                        markdownEditorSelectionRangesAreValid(snapshot.ranges, forEditorUTF16Length: checkedEditorUTF16Length)
                    else { throw SessionError.invalidResult }
                    recoverySnapshot = snapshot
                    // The atomic freeze can include input accepted after the
                    // request's generation was captured. `send` has validated
                    // and reconciled that full source before this snapshot.
                    expectedKey = RecoveryCaptureKey(requestEpoch: requestEpoch, generation: generation)
                    detachmentCapture = DetachmentCapture(
                        suspensionID: suspensionID, transportSessionID: sessionID, snapshot: snapshot
                    )
                    pendingDetachmentSuspensionID = nil
                    lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
                        documentID: snapshot.documentID, fingerprint: snapshot.fingerprint,
                        generation: snapshot.generation, ranges: snapshot.ranges
                    )
                    if let focusTarget = snapshot.focusTarget {
                        observeFocusTarget(focusTarget)
                    }
                    frozenScrollAnchor = result.scrollAnchor
                    capturedNewFrozenState = true
                } catch {
                    try? await resumeAfterDetachment(suspensionID: suspensionID)
                    throw error
                }
            }
        } else {
            try await captureRecoverySnapshot(expectedKey: expectedKey)
        }
        guard
            expectedKey
                == RecoveryCaptureKey(
                    requestEpoch: requestEpoch,
                    generation: generation
                )
        else { throw SessionError.invalidResult }
        let capturedScrollAnchor: EditorScrollAnchor?
        if capturedNewFrozenState {
            if let frozenScrollAnchor {
                reconstructionScrollAnchor = nil
                capturedScrollAnchor = recordScrollPosition(
                    frozenScrollAnchor, fallbackFraction: frozenScrollAnchor.fallbackFraction)
                pendingScrollAnchor = capturedScrollAnchor
            } else {
                capturedScrollAnchor = nil
            }
        } else {
            // A frozen source can still scroll while persistence is pending.
            capturedScrollAnchor = try? await currentScrollAnchor()
        }
        guard
            expectedKey
                == RecoveryCaptureKey(
                    requestEpoch: requestEpoch,
                    generation: generation
                )
        else { throw SessionError.invalidResult }
        reconstructionScrollAnchor = capturedScrollAnchor ?? pendingScrollAnchor
    }

    /// Failed/cancelled navigation may keep the original page visible. An old
    /// completion cannot unfreeze a newer suspension of that same document.
    func resumeAfterDetachment(suspensionID: String) async throws {
        guard detachmentSuspensionID == suspensionID,
            let webView, isReady, isLoaded
        else { return }
        // Dispatch can unfreeze WebKit before its reply returns. From this
        // point an independent detach cannot retain the old no-input proof.
        detachmentCapture = nil
        pendingDetachmentSuspensionID = suspensionID
        _ = try await send(.resumeAfterDetachment(suspensionID: suspensionID), in: webView)
        guard self.webView === webView, detachmentSuspensionID == suspensionID else { return }
        detachmentCapture = nil
        pendingDetachmentSuspensionID = nil
        recordNoteOpeningActualFocus(
            attemptID: PerformanceProbe.shared.currentNoteOpeningAttempt(editorSessionID: sessionID))
    }

    /// An acknowledged freeze is an exact source proof even before the view
    /// detaches. Input resume, commit rebase and transport replacement revoke it.
    private var validFrozenPersistenceCapture: DetachmentCapture? {
        guard !isComposing,
            let capture = detachmentCapture,
            capture.snapshot.documentID == documentID,
            capture.snapshot.fingerprint == startingFingerprint,
            capture.snapshot.generation == generation,
            capture.snapshot.source.utf8.elementsEqual(checkedSource.utf8),
            capture.snapshot.citationSnapshot == committedCitationSnapshot,
            capture.snapshot.citationData == checkedCitationData
        else { return nil }
        if hasAttachedWebView {
            guard isReady, isLoaded, capture.transportSessionID == sessionID else { return nil }
        }
        return capture
    }

    var hasDetachedPersistenceSnapshot: Bool { !hasAttachedWebView && validFrozenPersistenceCapture != nil }

    func persistenceSnapshot(expectedRevision: DocumentFingerprint) async throws -> MarkdownEditorPersistenceSnapshot {
        if let capture = validFrozenPersistenceCapture,
            !hasAttachedWebView || startingFingerprint == expectedRevision.sha256
        {
            guard startingFingerprint == expectedRevision.sha256 else { throw SessionError.staleRequest }
            return MarkdownEditorPersistenceSnapshot(
                text: capture.snapshot.source, generation: generation,
                documentID: documentID, fingerprint: startingFingerprint,
                suspensionID: capture.suspensionID,
                citationData: capture.snapshot.citationData,
                companionRevision: committedCitationSnapshot?.revision
            )
        }
        guard hasAttachedWebView else { throw SessionError.unavailable }
        let snapshot = try await currentTextSnapshot(for: documentID)
        // A durable write may already have advanced Document's repository base
        // while its live acknowledgement failed. A fresh full WebKit read is
        // still authoritative; the repository separately checks that base.
        return MarkdownEditorPersistenceSnapshot(
            text: snapshot.text, generation: snapshot.generation,
            documentID: documentID, fingerprint: startingFingerprint,
            suspensionID: nil,
            citationData: snapshot.citationData, companionRevision: committedCitationSnapshot?.revision
        )
    }

    func acknowledgePersistenceSnapshot(
        _ snapshot: MarkdownEditorPersistenceSnapshot,
        committedText: String,
        fingerprint: DocumentFingerprint,
        citationSnapshot: ZoteroCitationSnapshot? = nil
    ) async throws -> MarkdownEditorCommitAcknowledgement {
        guard snapshot.documentID == documentID, snapshot.fingerprint == startingFingerprint else {
            throw SessionError.staleRequest
        }
        // Reattachment may have resumed editing while the repository saved.
        // Its live acknowledgement then decides whether newer input wins.
        if hasAttachedWebView {
            guard try await waitUntilLoadedForSave() else { throw SessionError.unavailable }
            return try await acknowledgeCommittedSnapshot(
                expectedText: snapshot.text, committedText: committedText,
                fingerprint: fingerprint, documentID: snapshot.documentID,
                expectedCitationData: snapshot.citationData, citationSnapshot: citationSnapshot
            )
        }
        guard !hasAttachedWebView, let capture = validFrozenPersistenceCapture,
            capture.snapshot.generation >= snapshot.generation,
            capture.snapshot.generation != snapshot.generation
                || capture.snapshot.source.utf8.elementsEqual(snapshot.text.utf8),
            DocumentFingerprint(content: committedText) == fingerprint
        else { throw SessionError.invalidResult }
        let recovered = capture.snapshot
        let superseded =
            !recovered.source.utf8.elementsEqual(committedText.utf8)
            || recovered.citationData != citationSnapshot?.data
        committedCitationSnapshot = citationSnapshot
        let committed = MarkdownEditorRecoverySnapshot(
            documentID: documentID, fingerprint: fingerprint.sha256,
            generation: generation, ranges: recovered.ranges,
            source: recovered.source, stateJSON: recovered.stateJSON,
            undoHistoryPreserved: recovered.undoHistoryPreserved, hasHistory: recovered.hasHistory, dirty: superseded,
            focusTarget: recovered.focusTarget,
            undoLabel: recovered.undoLabel,
            redoLabel: recovered.redoLabel,
            citationSnapshot: committedCitationSnapshot,
            citationData: checkedCitationData
        )
        startingFingerprint = fingerprint.sha256
        committedCitationSnapshot = citationSnapshot
        recoverySnapshot = committed
        detachmentCapture = DetachmentCapture(
            suspensionID: capture.suspensionID, transportSessionID: capture.transportSessionID, snapshot: committed
        )
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: documentID, fingerprint: fingerprint.sha256,
            generation: generation, ranges: recovered.ranges
        )
        updatePublished(\.isDirty, to: superseded)
        return superseded ? .superseded : .clean
    }

    private func captureRecoverySnapshot(
        expectedKey: RecoveryCaptureKey
    ) async throws {
        guard
            expectedKey
                == RecoveryCaptureKey(
                    requestEpoch: requestEpoch,
                    generation: generation
                )
        else { throw SessionError.invalidResult }
        guard isReady, isLoaded, let webView else { return }
        let result = try await send(.captureRecovery, in: webView)
        try Task.checkCancellation()
        guard let snapshot = result.recovery,
            snapshot.documentID == documentID,
            snapshot.fingerprint == startingFingerprint,
            snapshot.generation == generation,
            snapshot.source.utf8.elementsEqual(checkedSource.utf8),
            snapshot.citationSnapshot == committedCitationSnapshot,
            snapshot.citationData == checkedCitationData,
            markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
            ),
            expectedKey
                == RecoveryCaptureKey(
                    requestEpoch: requestEpoch,
                    generation: generation
                )
        else {
            throw SessionError.invalidResult
        }
        recoverySnapshot = snapshot
        if let focusTarget = snapshot.focusTarget {
            observeFocusTarget(focusTarget)
        }
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: snapshot.documentID,
            fingerprint: snapshot.fingerprint,
            generation: snapshot.generation,
            ranges: snapshot.ranges
        )
    }

    func currentScrollAnchor() async throws -> EditorScrollAnchor? {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let result = try await send(.queryScrollAnchor, in: webView)
        guard intendedRequestEpoch == requestEpoch,
            self.webView === webView
        else {
            throw SessionError.staleRequest
        }
        let anchor = recordScrollPosition(
            result.scrollAnchor,
            fallbackFraction: result.scrollAnchor?.fallbackFraction
                ?? pendingScrollFraction
                ?? 0
        )
        reconstructionScrollAnchor = nil
        pendingScrollAnchor = anchor
        return anchor
    }

    func queryPerformanceSamples() async throws -> [MarkdownEditorPerformanceSample] {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let result = try await send(.queryPerformance, in: webView)
        guard intendedRequestEpoch == requestEpoch,
            self.webView === webView,
            result.accepted,
            let samples = result.performanceSamples
        else {
            throw SessionError.invalidResult
        }
        return samples
    }

    func currentSelection(
        for expectedDocumentID: String? = nil,
        in source: String? = nil
    ) async throws -> MarkdownReviewSelection? {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
            isReady, isLoaded, let webView
        else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let intendedDocumentID = documentID
        let intendedFingerprint = startingFingerprint
        // Source and selections must come from one JS turn and one resulting
        // generation. Two separate queries can otherwise anchor a newer
        // selection into an older source after intervening input.
        let result = try await send(.queryText, in: webView)
        guard intendedRequestEpoch == requestEpoch,
            intendedDocumentID == documentID,
            intendedFingerprint == startingFingerprint,
            self.webView === webView,
            let exactSource = result.text,
            exactSource.utf8.elementsEqual(checkedSource.utf8),
            source.map({ $0.utf8.elementsEqual(exactSource.utf8) }) ?? true,
            markdownEditorSelectionRangesAreValid(
                result.selections,
                forEditorUTF16Length: checkedEditorUTF16Length
            ),
            let range = result.selections.first
        else {
            throw SessionError.invalidResult
        }
        let editorLower = min(range.anchor, range.head)
        let editorUpper = max(range.anchor, range.head)
        guard editorUpper > editorLower else { return nil }
        guard let lower = sourceOffsetMap.sourceUTF16Offset(forEditorUTF16Offset: editorLower),
            let upper = sourceOffsetMap.sourceUTF16Offset(forEditorUTF16Offset: editorUpper),
            upper > lower,
            upper - lower <= 2_000
        else { throw SessionError.selectionTooLong }
        let units = exactSource.utf16
        guard let lowerUTF16 = units.index(units.startIndex, offsetBy: lower, limitedBy: units.endIndex),
            let upperUTF16 = units.index(units.startIndex, offsetBy: upper, limitedBy: units.endIndex),
            let lowerIndex = String.Index(lowerUTF16, within: exactSource),
            let upperIndex = String.Index(upperUTF16, within: exactSource)
        else {
            throw SessionError.invalidResult
        }
        let prefix = exactSource[..<lowerIndex]
        let excerpt = String(exactSource[lowerIndex..<upperIndex])
        let startLine = prefix.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
        let endLine = startLine + excerpt.reduce(into: 0) { if $1 == "\n" { $0 += 1 } }
        return MarkdownReviewSelection(
            startLine: startLine,
            endLine: endLine,
            excerpt: excerpt,
            utf16LowerBound: lower,
            utf16UpperBound: upper,
            contextBefore: String(prefix.suffix(48)),
            contextAfter: String(exactSource[upperIndex...].prefix(48))
        )
    }

    func acknowledgeCommittedSnapshot(
        expectedText: String,
        committedText: String,
        fingerprint: DocumentFingerprint,
        documentID expectedDocumentID: String,
        expectedCitationData: ZoteroCitationData? = nil,
        citationSnapshot: ZoteroCitationSnapshot? = nil
    ) async throws -> MarkdownEditorCommitAcknowledgement {
        guard expectedDocumentID == documentID,
            isReady, isLoaded, let webView
        else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let intendedFingerprint = startingFingerprint
        let result = try await send(
            .acknowledgeCommittedSnapshot(
                expected: expectedText,
                committed: committedText,
                fingerprint: fingerprint.sha256,
                expectedCitationData: expectedCitationData,
                committedCitationSnapshot: citationSnapshot
            ),
            in: webView
        )
        guard intendedRequestEpoch == requestEpoch,
            expectedDocumentID == documentID,
            intendedFingerprint == startingFingerprint,
            self.webView === webView,
            let currentText = result.text,
            let commitSuperseded = result.commitSuperseded,
            result.resultingGeneration == generation,
            currentText.utf8.elementsEqual(checkedSource.utf8)
        else { throw SessionError.invalidResult }
        let rebasedRanges = currentValidSelectionRanges()
        // Rebasing a committed fingerprint does not replace the live renderer.
        // Its validated response already admitted the current interaction revision.
        invalidateRequestQueue(preservingRendererInteraction: true)
        startingFingerprint = fingerprint.sha256
        committedCitationSnapshot = citationSnapshot
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: generation,
            ranges: rebasedRanges
        )
        // A commit advances the repository base identity. If typing continued
        // after the saved snapshot, the newer CodeMirror source remains dirty
        // and is scheduled for the next save rather than being replaced.
        recoverySnapshot = MarkdownEditorRecoverySnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: generation,
            ranges: rebasedRanges,
            source: checkedSource,
            stateJSON: nil,
            undoHistoryPreserved: false,
            dirty: commitSuperseded,
            focusTarget: preferredDocumentFocusTarget,
            citationSnapshot: committedCitationSnapshot,
            citationData: checkedCitationData
        )
        updatePublished(\.isDirty, to: commitSuperseded)
        return commitSuperseded ? .superseded : .clean
    }

    func installSourceChangeHandler(owner: AnyObject, _ handler: @escaping () -> Void) {
        sourceChangeHandlerOwner = ObjectIdentifier(owner)
        sourceChangeHandler = handler
    }

    func removeSourceChangeHandler(owner: AnyObject) {
        guard sourceChangeHandlerOwner == ObjectIdentifier(owner) else { return }
        sourceChangeHandlerOwner = nil
        sourceChangeHandler = nil
    }

    func focus() {
        requestFocus(.editor)
    }

    /// Completes an admitted external text drop's native focus handoff. The
    /// page already owns the inserted text and caret; do not send a selection
    /// operation or revive the focus lease of a hidden Review document.
    @discardableResult
    func acceptNativeFocusAfterDrop(from requestingWebView: WKWebView) -> Bool {
        guard webView === requestingWebView, isReady, isLoaded, errorMessage == nil,
            automaticFocusIsAuthorized, !isComposing, presentedMode == pendingMode,
            !requestingWebView.isHiddenOrHasHiddenAncestor,
            let window = requestingWebView.window, window.isKeyWindow,
            window.makeFirstResponder(requestingWebView)
        else { return false }
        focusRequestRevision &+= 1
        pendingFocusIntentRevision = nil
        automaticFocusTarget = .editor
        preferredDocumentFocusTarget = .editor
        return true
    }

    func focusTitle() {
        requestFocus(.title)
    }

    func prepareReadSelection(_ range: Range<Int>) {
        // Cold Review has a CodeMirror selection snapshot too. Only an actual
        // writable presentation, rather than that default snapshot, means an
        // editing selection must be retained on later Review handoffs.
        guard !hasPresentedWritableMode,
            pendingSourceRange == nil || pendingSourceRangeIsDefault || pendingSourceRangeRequiresEditing
        else { return }
        queueSourceRange(fromUTF16: range.lowerBound, toUTF16: range.upperBound, requiresEditing: true)
    }

    func focusPreferred() {
        requestFocus(preferredDocumentFocusTarget ?? .editor)
    }

    /// Completes a window-owned mode-entry intent only at the bridge dispatch
    /// boundary. Loading must not revive an intent superseded by navigation,
    /// blur, composition, or another native responder.
    func focusIfPresented(
        in mode: MarkdownEditorMode,
        requiringFocusRevision revision: UInt64,
        target requestedTarget: WindowDocumentFocusTarget? = nil,
        isStillRequested: @escaping @MainActor () -> Bool
    ) async throws {
        try Task.checkCancellation()
        guard let webView else { throw SessionError.unavailable }
        let target = requestedTarget ?? preferredDocumentFocusTarget ?? .editor
        var admittedFocusRevision: UInt64?
        let intendedRequestEpoch = requestEpoch
        defer {
            if requestEpoch == intendedRequestEpoch, let admittedFocusRevision {
                acknowledgeFocusIntent(admittedFocusRevision, target: target)
            }
        }
        _ = try await send(
            focusOperation(for: target, mode: mode), in: webView,
            admittingFocus: { [self] in
                guard !Task.isCancelled, requestEpoch == intendedRequestEpoch, focusRequestRevision == revision,
                    isReady, isLoaded, errorMessage == nil, !isComposing,
                    presentedMode == mode, pendingMode == mode,
                    !webView.isHiddenOrHasHiddenAncestor,
                    let window = webView.window, window.isKeyWindow,
                    window.attachedSheet == nil,
                    (window.firstResponder as? any NSTextInputClient)?.hasMarkedText() != true,
                    isStillRequested(), window.makeFirstResponder(webView)
                else { return false }
                // Responder callbacks may synchronously supersede the intent.
                guard requestEpoch == intendedRequestEpoch, focusRequestRevision == revision, !isComposing,
                    window.isKeyWindow, isStillRequested()
                else { return false }
                admittedFocusRevision = beginFocusIntent(target)
                return true
            }
        )
    }

    private func requestFocus(_ target: WindowDocumentFocusTarget) {
        let revision = beginFocusIntent(target)
        // Opening owns the pending intent. Do not let a task created before
        // readiness wake afterward and race its serial navigation handoff.
        guard isReady, isLoaded else { return }
        let intendedRequestEpoch = requestEpoch
        let precedingHandoff = focusHandoffTask
        let precedingNavigation = navigationIntentTask
        Task {
            await precedingHandoff?.value
            await precedingNavigation?.value
            guard intendedRequestEpoch == requestEpoch, revision == focusRequestRevision, automaticFocusIsAuthorized else { return }
            try? await applyFocusIntent(target, revision: revision)
        }
    }

    private func beginFocusIntent(_ target: WindowDocumentFocusTarget) -> UInt64 {
        focusRequestRevision &+= 1
        pendingFocusIntentRevision = focusRequestRevision
        automaticFocusTarget = target
        preferredDocumentFocusTarget = target
        automaticFocusIsAuthorized = true
        return focusRequestRevision
    }

    private func acknowledgeFocusIntent(_ revision: UInt64, target: WindowDocumentFocusTarget) {
        guard revision == focusRequestRevision, target == automaticFocusTarget,
            pendingFocusIntentRevision == revision
        else { return }
        pendingFocusIntentRevision = nil
    }

    private func observeFocusTarget(_ target: WindowDocumentFocusTarget) {
        // Renderer focus is an observation. It cannot replace a newer native
        // intent before that intent's own focus acknowledgment has returned.
        guard pendingFocusIntentRevision == nil else { return }
        preferredDocumentFocusTarget = target
        automaticFocusTarget = target
    }

    func authorizeAutomaticFocus(
        target: WindowDocumentFocusTarget? = nil
    ) {
        _ = beginFocusIntent(target ?? preferredDocumentFocusTarget ?? automaticFocusTarget)
    }

    func focusAndWait() async throws {
        try await focusAndWait(.editor)
    }

    func focusTitleAndWait() async throws {
        try await focusAndWait(.title)
    }

    private func focusAndWait(
        _ target: WindowDocumentFocusTarget
    ) async throws {
        let revision = beginFocusIntent(target)
        try await applyFocusIntent(target, revision: revision)
    }

    private func applyFocusIntent(_ target: WindowDocumentFocusTarget, revision: UInt64) async throws {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let epoch = requestEpoch
        let intendedSessionID = sessionID
        let mode = presentedMode ?? pendingMode
        let openingAttemptID = PerformanceProbe.shared.currentNoteOpeningAttempt(editorSessionID: intendedSessionID)
        do {
            _ = try await send(
                focusOperation(for: target, mode: mode),
                in: webView,
                admittingFocus: { [self] in
                    revision == focusRequestRevision && target == automaticFocusTarget && automaticFocusIsAuthorized
                }
            )
        } catch {
            if epoch == requestEpoch { acknowledgeFocusIntent(revision, target: target) }
            throw error
        }
        acknowledgeFocusIntent(revision, target: target)
        if let openingAttemptID,
            !Task.isCancelled,
            epoch == requestEpoch, sessionID == intendedSessionID, self.webView === webView,
            revision == focusRequestRevision, target == automaticFocusTarget,
            presentedMode == mode, pendingMode == mode
        {
            recordNoteOpeningActualFocus(attemptID: openingAttemptID)
        }
    }

    /// Observes an acknowledged native focus without requesting or changing it.
    /// A retained surface may become visible without another bridge focus command.
    func recordNoteOpeningActualFocus(attemptID: UUID?) {
        guard let attemptID,
            automaticFocusIsAuthorized, pendingFocusIntentRevision == nil,
            !presentationIsClosed, isReady, isLoaded, errorMessage == nil, !isComposing,
            detachmentSuspensionID == nil,
            let presentedMode, pendingMode == presentedMode,
            let nativeWebView = webView as? DocumentNativeWebView,
            nativeWebView.documentSurfaceAllowsInput, !nativeWebView.isHiddenOrHasHiddenAncestor,
            let window = nativeWebView.window, window.isKeyWindow, window.attachedSheet == nil,
            let responder = window.firstResponder as? NSView,
            responder === nativeWebView || responder.isDescendant(of: nativeWebView)
        else { return }
        PerformanceProbe.shared.markNoteOpeningEditorPhase(.focused, editorSessionID: sessionID, attemptID: attemptID)
    }

    var noteOpeningFocusDiagnostics: [String: Bool] {
        let native = webView as? DocumentNativeWebView
        let window = native?.window
        let responder = window?.firstResponder as? NSView
        return [
            "authorized": automaticFocusIsAuthorized, "pending": pendingFocusIntentRevision != nil,
            "closed": presentationIsClosed, "composing": isComposing,
            "suspended": detachmentSuspensionID != nil, "mode_matches": presentedMode == pendingMode,
            "native": native != nil, "allows_input": native?.documentSurfaceAllowsInput == true,
            "hidden": native?.isHiddenOrHasHiddenAncestor != false, "key_window": window?.isKeyWindow == true,
            "sheet": window?.attachedSheet != nil,
            "responder": native.map { responder === $0 || responder?.isDescendant(of: $0) == true } ?? false,
        ]
    }

    private func focusOperation(
        for target: WindowDocumentFocusTarget,
        mode: MarkdownEditorMode
    ) -> MarkdownEditorOperation {
        switch target {
        case .title where mode == .livePreview: .focusTitle
        case .title: .focus
        case .editor: .focus
        }
    }

    func resignFocusAndWait() async {
        focusRequestRevision &+= 1
        citationInteractionRevision &+= 1
        automaticFocusIsAuthorized = false
        pendingFocusIntentRevision = nil
        await resignFocusAndWait(revision: focusRequestRevision)
    }

    private func resignFocusAndWait(revision: UInt64) async {
        await documentLoadTask?.value
        // A newer Edit/Source request supersedes this pending Review handoff.
        // Its renewed focus lease must not be revoked by the older task.
        guard revision == focusRequestRevision, !automaticFocusIsAuthorized else { return }
        guard isReady, let webView else { return }
        if let window = webView.window,
            let firstResponder = window.firstResponder as? NSView,
            firstResponder === webView || firstResponder.isDescendant(of: webView)
        {
            window.makeFirstResponder(nil)
        }
        // Native focus ownership is authoritative for the retained, hidden
        // WebView. A failed best-effort bridge blur must never trap the
        // researcher in Edit after the source save has already succeeded.
        _ = try? await send(.blur, in: webView)
    }

    /// Zotero owns the picker and formatter. The editor stages every callback
    /// against one exact snapshot and publishes only one accepted transaction.
    func performCitation(
        _ command: ZoteroDocumentCommand,
        reference: MarkdownEditorCitationReference? = nil
    ) async throws {
        updatePublished(\.citationStatus, to: nil)
        do {
            try await performCitationTransaction(command, reference: reference)
        } catch {
            await announceCitationStatus(ScholiumErrorLocalization.message(error))
            throw error
        }
    }

    private func performCitationTransaction(
        _ command: ZoteroDocumentCommand,
        reference: MarkdownEditorCitationReference?
    ) async throws {
        guard isReady, isLoaded, !isComposing, preferredDocumentFocusTarget != .title,
            citationTransactionID == nil, let webView
        else { throw SessionError.unavailable }
        let transactionID = "citation_" + UUID().uuidString
        let capturedSessionID = sessionID
        let capturedDocumentID = documentID
        let capturedRevision = citationInteractionRevision
        _ = try await send(.beginCitation(transactionID: transactionID, command: command.rawValue, reference: reference), in: webView)
        citationTransactionID = transactionID
        citationCancellationRequested = false
        defer {
            if citationTransactionID == transactionID { citationTransactionID = nil }
        }
        let authority: @Sendable () async -> ZoteroDocumentAuthority = { [weak self] in
            await self?.citationAuthority(
                transactionID: transactionID, sessionID: capturedSessionID,
                documentID: capturedDocumentID, revision: capturedRevision) ?? .unavailable
        }
        let result = await citationIntegration.run(
            transactionID: transactionID, command: command, documentID: bridgeDocumentID,
            authority: authority,
            handler: { [weak self] callback in
                guard let self else { throw SessionError.unavailable }
                return try await self.handleCitationCallback(
                    callback, transactionID: transactionID,
                    sessionID: capturedSessionID, documentID: capturedDocumentID, revision: capturedRevision)
            })
        do {
            if result.status == .cleanedUp, result.remoteCleanupConfirmed,
                await authority() == .current
            {
                _ = try await send(.finishCitation(transactionID: transactionID), in: webView)
                _ = try? await send(.focus, in: webView)
            } else {
                if self.webView === webView, sessionID == capturedSessionID {
                    _ = try? await send(.cancelCitation(transactionID: transactionID), in: webView)
                }
                switch result.status {
                case .cancelled: return
                case .busy:
                    throw SessionError.citationFailed("Zotero is handling another citation operation. Finish or cancel its open dialog, then try again.")
                case .unavailable, .cleanedUp:
                    if citationCancellationRequested, result.remoteCleanupConfirmed { return }
                    throw SessionError.citationFailed(
                        "The document changed during the citation operation. Your text was preserved; try again at the current position.")
                case .failed:
                    throw SessionError.citationFailed(citationStatus ?? result.message ?? "The citation operation could not finish. Your text was preserved.")
                case .unknown:
                    throw SessionError.citationFailed(result.message ?? "The citation operation could not finish. Your text was preserved.")
                }
            }
        } catch {
            if self.webView === webView, sessionID == capturedSessionID {
                _ = try? await send(.cancelCitation(transactionID: transactionID), in: webView)
            }
            if citationCancellationRequested, citationTransactionID == transactionID,
                case SessionError.staleRequest = error
            {
                return
            }
            throw error
        }
    }

    private func citationAuthority(
        transactionID: String, sessionID capturedSessionID: UUID,
        documentID capturedDocumentID: String, revision: UInt64
    ) -> ZoteroDocumentAuthority {
        guard citationTransactionID == transactionID else { return .unavailable }
        if citationCancellationRequested { return .cancelled }
        return sessionID == capturedSessionID && documentID == capturedDocumentID
            && citationInteractionRevision == revision
            && isReady && isLoaded && !isComposing && !presentationIsClosed
            && detachmentSuspensionID == nil && webView != nil
            ? .current : .unavailable
    }

    private func handleCitationCallback(
        _ callback: ZoteroDocumentCallback, transactionID: String,
        sessionID capturedSessionID: UUID, documentID capturedDocumentID: String, revision: UInt64
    ) async throws -> ZoteroDocumentReply {
        guard
            citationAuthority(
                transactionID: transactionID, sessionID: capturedSessionID,
                documentID: capturedDocumentID, revision: revision) == .current, let webView
        else { throw SessionError.staleRequest }
        switch callback {
        case .activate:
            NSApp.activate()
            webView.window?.makeKeyAndOrderFront(nil)
            return .none
        case .displayAlert(let text, let icon, let buttons):
            guard let window = webView.window else { throw SessionError.unavailable }
            guard let presentation = MarkdownEditorCitationAlert(rawValue: buttons) else { throw SessionError.invalidResult }
            let alert = NSAlert()
            alert.messageText = "Zotero"
            alert.informativeText = text
            alert.alertStyle = icon == 0 ? .critical : .warning
            for title in presentation.buttonTitles { alert.addButton(withTitle: ScholiumL10n.dynamicString(title)) }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            let response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
            guard let reply = presentation.reply(for: response) else { throw SessionError.staleRequest }
            return reply
        default:
            let value = try MarkdownEditorCitationCallback(callback)
            do {
                let result = try await send(.citationCallback(transactionID: transactionID, value: value), in: webView)
                guard let reply = result.citationReply else { throw SessionError.invalidResult }
                return reply.protocolReply
            } catch {
                await announceCitationStatus(ScholiumErrorLocalization.message(error))
                throw error
            }
        }
    }

    func announceCitationStatus(_ message: String) async {
        guard citationStatus != message else { return }
        citationStatus = message
        if let webView { _ = try? await send(.announceStatus(message), in: webView) }
    }

    func dismissCitationStatus() { updatePublished(\.citationStatus, to: nil) }

    func presentSelectionInquiry(_ inquiry: AgentChatSelectionInquiry) async throws -> Bool {
        guard isReady, isLoaded, !isComposing, hasNonemptySelection,
            let count = context?.selectionActionUTF16Count, (1...32_000).contains(count), let webView,
            inquiry.operation == nil || count <= MarkdownSelectionActionAdmission.maximumWritingAssistanceUTF16Length
        else { throw SessionError.unavailable }
        return try await floatingSurfaces.presentSelectionInquiry(inquiry, in: webView) {
            let result = try await send(.showSelectionActions, in: webView)
            return result.selectionSurfaceID
        }
    }

    func perform(_ command: MarkdownEditorCommand, argument: String? = nil) async throws {
        switch command {
        case .previewAtSelection:
            guard isReady, isLoaded, !isComposing, let webView,
                context?.availableCommands.contains(command) == true
            else { throw SessionError.unavailable }
            _ = try await send(.showPreview, in: webView)
            return
        case .insertCitation:
            try await performCitation(.addEditCitation)
            return
        case .insertBibliography:
            try await performCitation(.addEditBibliography)
            return
        case .refreshCitations:
            try await performCitation(.refresh)
            return
        case .citationStyle:
            try await performCitation(.setDocPrefs)
            return
        case .cancelCitation:
            guard let transactionID = citationTransactionID else { return }
            citationCancellationRequested = true
            if let webView { _ = try? await send(.cancelCitation(transactionID: transactionID), in: webView) }
            await citationIntegration.cancelCurrentTransaction(transactionID: transactionID)
            await announceCitationStatus(ScholiumL10n.dynamicString("Citation cancelled. Finish or cancel any open Zotero dialog."))
            return
        default: break
        }
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        _ = try await send(.command(command, argument: argument), in: webView)
    }

    func performDocumentFind(_ query: DocumentFindQuery) async throws -> DocumentFindResult {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let result = try await send(.documentFind(query), in: webView)
        guard let find = result.find, find.isValid
        else {
            throw SessionError.invalidResult
        }
        return find
    }

    func clearDocumentFind() async {
        guard isReady, isLoaded, let webView else { return }
        let currentDocumentID = documentID
        let focusRevision = focusRequestRevision
        let focusTarget = preferredDocumentFocusTarget ?? .editor
        let mode = presentedMode ?? pendingMode
        let focusReturn = DocumentFindFocusReturnAuthority(webView: webView)
        do {
            _ = try await send(.clearDocumentFind, in: webView)
            guard !Task.isCancelled, let focusReturn else { return }
            try await focusIfPresented(
                in: mode, requiringFocusRevision: focusRevision, target: .editor
            ) { [weak self] in
                guard let self else { return false }
                return self.webView === webView && self.documentID == currentDocumentID
                    && (self.preferredDocumentFocusTarget ?? .editor) == focusTarget
                    && focusReturn.canRestore(to: webView)
            }
        } catch {
            // Find is already dismissed; the retained document owns any editor
            // failure. A failed clear must not transfer focus to another page.
        }
    }

    func acceptEditorChanges(
        _ rawChanges: [EditorBridgeChange],
        baseGeneration: Int,
        resultingGeneration: Int,
        citationManaged: Bool? = nil,
        citationData: ZoteroCitationData? = nil
    ) -> Bool {
        #if DEBUG
            let timingObserver = testingEditorChangeObserver
            let timingStartedAt: ContinuousClock.Instant? = timingObserver == nil ? nil : .now
            var timingMappedAt: ContinuousClock.Instant?
            var timingBufferAppliedAt: ContinuousClock.Instant?
            var timingOffsetMappedAt: ContinuousClock.Instant?
            var timingAccepted = false
            defer {
                if let timingObserver, let timingStartedAt {
                    let completedAt = ContinuousClock.now
                    timingObserver(
                        TestingEditorChangeTiming(
                            baseGeneration: baseGeneration, resultingGeneration: resultingGeneration,
                            accepted: timingAccepted, startedAt: timingStartedAt, completedAt: completedAt,
                            validationAndMapping: timingStartedAt.duration(to: timingMappedAt ?? completedAt),
                            bufferApply: timingMappedAt.map { $0.duration(to: timingBufferAppliedAt ?? completedAt) },
                            offsetMap: timingBufferAppliedAt.map { $0.duration(to: timingOffsetMappedAt ?? completedAt) },
                            publishingAndCallbacks: timingOffsetMappedAt.map { $0.duration(to: completedAt) }))
                }
            }
        #endif
        guard pendingMode != .review, presentedMode != .review,
            !rawChanges.isEmpty || citationManaged == true,
            rawChanges.count <= 512,
            baseGeneration == generation,
            resultingGeneration == baseGeneration + 1,
            (citationManaged ?? false) == (committedCitationSnapshot != nil),
            citationData == nil || citationManaged == true,
            citationData.map({ (try? $0.validate()) != nil }) ?? true
        else { return false }
        var changes: [MarkdownEditorDelta] = []
        var resultingEditorUTF16Length = checkedEditorUTF16Length
        for raw in rawChanges {
            guard raw.hasMatchingExactInsertion,
                raw.from >= 0,
                raw.to >= raw.from,
                raw.to <= checkedEditorUTF16Length
            else { return false }
            resultingEditorUTF16Length +=
                Self.normalizedEditorUTF16Length(of: raw.insert)
                - (raw.to - raw.from)
            guard resultingEditorUTF16Length >= 0,
                let from = sourceOffsetMap.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.from
                ),
                let to = sourceOffsetMap.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.to
                )
            else { return false }
            changes.append(
                MarkdownEditorDelta(
                    fromUTF16: from,
                    toUTF16: to,
                    insertion: raw.exactInsert
                ))
        }
        #if DEBUG
            if timingObserver != nil { timingMappedAt = .now }
        #endif
        do {
            try checkedSourceBuffer.apply(changes)
        } catch {
            return false
        }
        #if DEBUG
            if timingObserver != nil { timingBufferAppliedAt = .now }
        #endif
        sourceOffsetMap.apply(
            changes,
            resultingSourceUTF16Length: checkedSourceBuffer.utf16Length,
            resultingCharacterAt: checkedSourceBuffer.character(atUTF16:)
        )
        #if DEBUG
            if timingObserver != nil { timingOffsetMappedAt = .now }
        #endif
        checkedEditorUTF16Length = resultingEditorUTF16Length
        checkedCitationData = citationData
        generation = resultingGeneration
        discardSupersededAttachedRecovery()
        updatePublished(\.isDirty, to: true)
        sourceChangeHandler?()
        #if DEBUG
            timingAccepted = true
        #endif
        return true
    }

    /// Validates an interaction payload against the same checked CodeMirror
    /// generation and UTF-16 length that accepted editor deltas update. The
    /// parent SwiftUI source is intentionally commit-paced and must never be
    /// used to authorize a live selection.
    func acceptsInteractionRanges(
        _ ranges: [MarkdownEditorSelectionRange],
        documentVersion: Int
    ) -> Bool {
        documentVersion == generation
            && markdownEditorSelectionRangesAreValid(
                ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
            )
    }

    /// A current-identity Web editor has already committed this generation, so
    /// rejecting its delta cannot leave the native mirror looking clean. Pin the
    /// exact buffer immediately and coalesce a full-buffer read through the same
    /// typed bridge. The ordinary autosave path then performs revision-checked
    /// persistence; a failed reconciliation remains dirty and reaches its
    /// existing visible save-recovery state instead of losing Web-only source.
    func reconcileAfterRejectedEditorChanges(
        resultingGeneration: Int,
        in webView: WKWebView
    ) {
        guard resultingGeneration > generation,
            self.webView === webView,
            isReady,
            isLoaded
        else { return }
        pendingRejectedChangeGeneration = max(
            pendingRejectedChangeGeneration ?? resultingGeneration,
            resultingGeneration
        )
        updatePublished(\.isDirty, to: true)
        sourceChangeHandler?()
        guard rejectedChangeRecoveryTask == nil else { return }

        let recoveryID = UUID()
        rejectedChangeRecoveryID = recoveryID
        rejectedChangeRecoveryTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            defer {
                if self.rejectedChangeRecoveryID == recoveryID {
                    self.rejectedChangeRecoveryTask = nil
                    self.rejectedChangeRecoveryID = nil
                }
            }
            while let expectedGeneration = self.pendingRejectedChangeGeneration,
                expectedGeneration > self.generation
            {
                self.pendingRejectedChangeGeneration = nil
                do {
                    let snapshot = try await self.currentTextSnapshot(
                        for: self.documentID
                    )
                    guard snapshot.generation >= expectedGeneration else {
                        throw SessionError.invalidResult
                    }
                    self.updatePresentation {
                        $0.clearReport(matching: Self.rejectedChangeRecoveryMessage)
                    }
                    self.updatePublished(\.isDirty, to: true)
                    self.sourceChangeHandler?()
                } catch is CancellationError {
                    return
                } catch SessionError.staleRequest {
                    return
                } catch {
                    let message = Self.rejectedChangeRecoveryMessage
                    self.updatePresentation { $0.report(message) }
                    _ = try? await self.send(
                        .announceStatus(message),
                        in: webView
                    )
                    return
                }
            }
            self.pendingRejectedChangeGeneration = nil
        }
    }

    func webContentProcessTerminated() {
        floatingSurfaces.reset()
        invalidateRequestQueue()
        cancelModeTransition()
        let recoveryRanges = currentValidSelectionRanges()
        if let snapshot = recoverySnapshot,
            snapshot.documentID == documentID,
            snapshot.fingerprint == startingFingerprint,
            snapshot.generation == generation,
            snapshot.source.utf8.elementsEqual(checkedSource.utf8),
            snapshot.citationSnapshot == committedCitationSnapshot,
            snapshot.citationData == checkedCitationData,
            markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
            )
        {
            // The bounded serialized history may predate recent cursor moves.
            // Preserve that history while making the exact lightweight
            // selection and current dirty state authoritative for recovery.
            recoverySnapshot = MarkdownEditorRecoverySnapshot(
                documentID: snapshot.documentID,
                fingerprint: snapshot.fingerprint,
                generation: snapshot.generation,
                ranges: recoveryRanges,
                source: snapshot.source,
                stateJSON: snapshot.stateJSON,
                undoHistoryPreserved: snapshot.undoHistoryPreserved,
                hasHistory: snapshot.hasHistory,
                dirty: isDirty,
                focusTarget: preferredDocumentFocusTarget,
                undoLabel: snapshot.undoLabel,
                redoLabel: snapshot.redoLabel,
                citationSnapshot: committedCitationSnapshot,
                citationData: checkedCitationData
            )
        } else {
            recoverySnapshot = MarkdownEditorRecoverySnapshot(
                documentID: documentID,
                fingerprint: startingFingerprint,
                generation: generation,
                ranges: recoveryRanges,
                source: checkedSource,
                stateJSON: nil,
                undoHistoryPreserved: false,
                dirty: isDirty,
                focusTarget: preferredDocumentFocusTarget,
                citationSnapshot: committedCitationSnapshot,
                citationData: checkedCitationData
            )
        }
        let recoverySource = checkedSource
        let recoveryDocumentID = documentID
        let recoveryMode = pendingMode
        updatePresentation { $0.webContentTerminated() }
        loadDocument(
            recoverySource,
            documentID: recoveryDocumentID,
            mode: recoveryMode,
            citationSnapshot: committedCitationSnapshot
        )
    }

    private func flushPendingState() {
        guard isReady, let source = pendingSource, let webView else { return }
        if pendingMode == .review {
            guard reviewProjectionForCurrentSource != nil else { return }
        }
        pendingSource = nil
        let mode = pendingMode
        let documentID = pendingDocumentID
        let intendedRequestEpoch = requestEpoch
        let openingAttempt = PerformanceProbe.shared.currentNoteOpeningAttempt(editorSessionID: sessionID)
        let openingSession = sessionID
        PerformanceProbe.shared.markNoteOpeningMilestone(.loadScheduled, attemptID: openingAttempt, editorSessionID: openingSession)
        let handoff = (webView as? DocumentNativeWebView)?.editorHandoffLease
        documentLoadTask = Task {
            defer { handoff?.retire() }
            do {
                if let handoff {
                    try Task.checkCancellation()
                    guard !handoff.isRetired else { throw SessionError.unavailable }
                }
                guard intendedRequestEpoch == requestEpoch,
                    self.documentID == documentID,
                    self.webView === webView
                else { return }
                PerformanceProbe.shared.markNoteOpeningMilestone(.loadStarted, attemptID: openingAttempt, editorSessionID: openingSession)
                let matchingRecovery = recoverySnapshot.flatMap { snapshot in
                    snapshot.documentID == documentID
                        && snapshot.fingerprint == startingFingerprint
                        && snapshot.generation >= 0
                        && snapshot.source.utf8.elementsEqual(source.utf8)
                        && markdownEditorSelectionRangesAreValid(
                            snapshot.ranges,
                            forEditorUTF16Length: checkedEditorUTF16Length
                        )
                        ? snapshot
                        : nil
                }
                let requestedInitialRange = pendingSourceRangeRequiresEditing && mode == .review ? nil : pendingSourceRange
                let initialRangeIsDefault = pendingSourceRangeIsDefault
                let initialRangeRevision = pendingSourceRangeRevision
                let initialSelection =
                    try requestedInitialRange.map { try editorSelection(for: $0) }
                    ?? matchingRecovery?.ranges.first
                deliveredImageResources = nil
                let initialPresentation = pendingPresentationConfiguration
                PerformanceProbe.shared.markNoteOpeningMilestone(.initializationRequested, attemptID: openingAttempt, editorSessionID: openingSession)
                let initialized = try await send(
                    .initialize(
                        text: source,
                        mode: mode,
                        dialect: .current,
                        initialSelection: initialSelection,
                        citationSnapshot: committedCitationSnapshot,
                        recovery: matchingRecovery,
                        presentation: initialPresentation
                    ),
                    in: webView,
                    requiringRequestEpoch: intendedRequestEpoch
                )
                try Task.checkCancellation()
                guard intendedRequestEpoch == requestEpoch,
                    self.documentID == documentID, self.webView === webView
                else { return }
                PerformanceProbe.shared.markNoteOpeningMilestone(.initialized, attemptID: openingAttempt, editorSessionID: openingSession)
                deliveredPresentationConfiguration = initialPresentation
                if initialized.resultingGeneration == initialPresentation.imageResourceGeneration {
                    deliveredImageResources = initialPresentation.imageResources
                }
                if let initialSelection, matchingRecovery == nil {
                    guard initialized.selections == [initialSelection] else {
                        throw SessionError.invalidResult
                    }
                }
                // Recovery installs all captured ranges. A default caret may
                // yield to them, while an explicit navigation request must be
                // applied by the convergence loop after that atomic install.
                if matchingRecovery == nil || initialRangeIsDefault,
                    pendingSourceRange == requestedInitialRange, pendingSourceRangeRevision == initialRangeRevision,
                    pendingSourceRangeIsDefault == initialRangeIsDefault
                {
                    pendingSourceRange = nil
                    pendingSourceRangeIsDefault = false
                    pendingSourceRangeRequiresEditing = false
                }
                if let handoff {
                    try Task.checkCancellation()
                    guard intendedRequestEpoch == requestEpoch, self.documentID == documentID,
                        self.webView === webView, handoff.commit()
                    else { throw SessionError.staleRequest }
                }
                if let snapshot = matchingRecovery {
                    updatePublished(\.isDirty, to: snapshot.dirty)
                    if initialized.recoveryHistoryPreserved == false {
                        updatePresentation {
                            $0.report(
                                String(
                                    localized: "The exact editor buffer was recovered, but its previous undo history was unavailable.", table: "Localizable",
                                    bundle: .module))
                        }
                        _ = try await send(
                            .announceStatus(
                                "The exact editor buffer was recovered. Previous undo history is unavailable."
                            ),
                            in: webView,
                            requiringRequestEpoch: intendedRequestEpoch
                        )
                    } else {
                        _ = try await send(
                            .announceStatus("The exact editor buffer was recovered."),
                            in: webView,
                            requiringRequestEpoch: intendedRequestEpoch
                        )
                    }
                } else {
                    updatePublished(\.isDirty, to: false)
                }
                guard intendedRequestEpoch == requestEpoch,
                    self.documentID == documentID,
                    self.webView === webView
                else { return }
                let restorationScrollAnchor =
                    reconstructionScrollAnchor
                    ?? pendingScrollAnchor
                pendingScrollAnchor = restorationScrollAnchor
                let restorationScrollFraction = pendingScrollFraction ?? 0
                // Appearance and snippet stores can finish loading after the
                // page is ready but while document initialization is still in
                // flight. Keep the opening masked until a serial convergence
                // pass observes the same latest values before and after all
                // the preparation awaits. A SwiftUI update that arrives during
                // an await therefore causes another pass instead of becoming
                // a permanently dropped initial style or preview update.
                try await convergePendingPresentationState(
                    in: webView,
                    requiringRequestEpoch: intendedRequestEpoch,
                    documentID: documentID
                )
                var appliedMode = mode
                PerformanceProbe.shared.markNoteOpeningMilestone(.presentationConverged, attemptID: openingAttempt, editorSessionID: openingSession)
                var sourceLocatorRevision = requestedInitialRange != nil && !initialRangeIsDefault ? initialRangeRevision : 0
                var appliedScrollIntent: ScrollIntent?
                while true {
                    try await awaitOpeningImageResources(in: webView, requiringRequestEpoch: intendedRequestEpoch, documentID: documentID)
                    try await convergePendingPresentationState(
                        in: webView, requiringRequestEpoch: intendedRequestEpoch, documentID: documentID)
                    while pendingMode != appliedMode {
                        let requestedMode = pendingMode
                        _ = try await send(
                            .setMode(requestedMode), in: webView,
                            requiringRequestEpoch: intendedRequestEpoch)
                        appliedMode = requestedMode
                    }
                    if let range = pendingSourceRange, !pendingSourceRangeRequiresEditing || appliedMode != .review {
                        let selection = try editorSelection(for: range)
                        let rangeRevision = pendingSourceRangeRevision
                        let rangeIsDefault = pendingSourceRangeIsDefault
                        if !rangeIsDefault { sourceLocatorRevision = rangeRevision }
                        _ = try await send(
                            .revealSourceRange(fromUTF16: selection.anchor, toUTF16: selection.head),
                            in: webView, requiringRequestEpoch: intendedRequestEpoch)
                        if pendingSourceRange == range, pendingSourceRangeRevision == rangeRevision,
                            pendingSourceRangeIsDefault == rangeIsDefault
                        {
                            pendingSourceRange = nil
                            pendingSourceRangeIsDefault = false
                            pendingSourceRangeRequiresEditing = false
                        }
                    }
                    let navigationRevision = navigationRequestRevision
                    let scrollIntent = pendingScrollIntent ?? appliedScrollIntent
                    let restoresScroll = sourceLocatorRevision == 0 || (scrollIntent?.revision ?? 0) > sourceLocatorRevision
                    let scrollAnchor = scrollIntent?.anchor ?? restorationScrollAnchor
                    let scrollFraction = scrollIntent?.fraction ?? restorationScrollFraction
                    let configuration = pendingPresentationConfiguration
                    let focused = automaticFocusIsAuthorized
                    let focusRevision = focusRequestRevision
                    let focusTarget = automaticFocusTarget
                    _ = try await send(
                        .completePreparation(
                            anchor: restoresScroll ? scrollAnchor.flatMap { wireAnchor(from: $0, in: checkedSource) } : nil,
                            fraction: restoresScroll ? scrollFraction : nil),
                        in: webView, requiringRequestEpoch: intendedRequestEpoch)
                    guard intendedRequestEpoch == requestEpoch,
                        self.documentID == documentID, self.webView === webView
                    else { return }
                    PerformanceProbe.shared.markNoteOpeningMilestone(.preparationCompleted, attemptID: openingAttempt, editorSessionID: openingSession)
                    if let scrollIntent, pendingScrollIntent?.revision == scrollIntent.revision {
                        pendingScrollIntent = nil
                        if restoresScroll { appliedScrollIntent = scrollIntent }
                    }
                    if !(pendingMode == .livePreview && checkedSource.contains("![") && imageResourceQueryTask != nil),
                        navigationRevision == navigationRequestRevision,
                        pendingMode == appliedMode,
                        configuration == pendingPresentationConfiguration,
                        configuration == deliveredPresentationConfiguration,
                        pendingSourceRange == nil || (pendingSourceRangeRequiresEditing && appliedMode == .review),
                        !automaticFocusIsAuthorized || (focused && focusRevision == focusRequestRevision && focusTarget == automaticFocusTarget)
                    {
                        break
                    }
                }
                let focused = automaticFocusIsAuthorized
                let releaseFocusRevision = focusRequestRevision
                let releaseFocusTarget = automaticFocusTarget
                _ = try await send(
                    .releasePreparation(focusTarget: focused ? releaseFocusTarget : nil),
                    in: webView, requiringRequestEpoch: intendedRequestEpoch)
                guard intendedRequestEpoch == requestEpoch,
                    self.documentID == documentID, self.webView === webView
                else { return }
                if focused, !automaticFocusIsAuthorized {
                    _ = try await send(.blur, in: webView, requiringRequestEpoch: intendedRequestEpoch)
                }
                if focused { acknowledgeFocusIntent(releaseFocusRevision, target: releaseFocusTarget) }
                updatePresentation { $0.complete(appliedMode) }
                PerformanceProbe.shared.markNoteOpeningMilestone(.sessionLoaded, attemptID: openingAttempt, editorSessionID: openingSession)
                // Updates arriving after the stable handoff use the loaded
                // configuration and mode owners, including the release await.
                if pendingMode != appliedMode { startModeConvergence(in: webView) }
                reconvergePendingPresentationState()
                flushPendingOpeningIntents(
                    in: webView, requiringRequestEpoch: intendedRequestEpoch,
                    focusWasAuthorized: focused, focusRevision: releaseFocusRevision, focusTarget: releaseFocusTarget)
                // CodeMirror has replaced its exact source, but WebKit can
                // retain the previous accessibility value until a separate
                // DOM interaction occurs. Invalidate that value projection
                // without moving focus or adding an audible announcement.
                NSAccessibility.post(element: webView, notification: .valueChanged)
                flushPendingLine()
            } catch {
                guard intendedRequestEpoch == requestEpoch,
                    self.documentID == documentID,
                    self.webView === webView
                else { return }
                _ = try? await send(
                    .blur,
                    in: webView,
                    requiringRequestEpoch: intendedRequestEpoch
                )
                guard intendedRequestEpoch == requestEpoch,
                    self.documentID == documentID,
                    self.webView === webView
                else { return }
                updatePresentation { $0.fail(ScholiumErrorLocalization.message(error)) }
            }
        }
    }

    private func awaitOpeningImageResources(
        in webView: WKWebView,
        requiringRequestEpoch epoch: UInt64, documentID: String
    ) async throws {
        // Source displays the authored image syntax. Ordinary text does not
        // acquire an image-read barrier; potential Markdown images use the
        // existing admitted catalog query, in parallel with initialization.
        guard pendingMode == .livePreview, checkedSource.contains("![") else { return }
        while let query = imageResourceQueryTask {
            let waitID = UUID()
            let wait = Task { [lifecyclePolicy] in
                try await withScholiumLifecycleDeadline(phase: .bridgeRequest, timeout: lifecyclePolicy.bridgeRequest) {
                    await query.value
                }
            }
            openingImageWaitID = waitID
            openingImageWaitTask = wait
            defer {
                if openingImageWaitID == waitID {
                    openingImageWaitTask = nil
                    openingImageWaitID = nil
                }
            }
            do { try await wait.value } catch is CancellationError {
                guard epoch == requestEpoch, self.documentID == documentID, self.webView === webView
                else { throw SessionError.staleRequest }
                if pendingMode == .source { return }
                // The same opening may return to Edit before the cancelled
                // Source wait unwinds. Its still-current query remains owned
                // by this attachment, so join it with the latest mode.
                continue
            }
            guard epoch == requestEpoch, self.documentID == documentID, self.webView === webView
            else { throw SessionError.staleRequest }
        }
    }

    private var reviewProjectionForCurrentSource: MarkdownEditorReviewProjection? {
        for projection in [pendingReviewProjection, currentReviewProjection] {
            if let projection, projection.documentID == documentID,
                projection.sourceFingerprint == startingFingerprint
            {
                return projection
            }
        }
        return nil
    }

    private var pendingPresentationConfiguration: MarkdownEditorPresentationConfiguration {
        .init(
            reviewProjection: reviewProjectionForCurrentSource,
            documentTitle: pendingDocumentTitle,
            presentationCSS: pendingPresentationCSS,
            userCSS: pendingUserCSS,
            linkPreviews: pendingLinkPreviews,
            linkPreviewGeneration: pendingLinkPreviewGeneration,
            imageResources: pendingImageResources,
            imageResourceGeneration: pendingImageResourceGeneration,
            writingContinuationEnabled: pendingWritingContinuationEnabled,
            writingContinuationContextKey: pendingWritingContinuationContextKey,
            writingIndexContextKey: pendingWritingIndexContextKey)
    }

    private func reconvergePendingPresentationState() {
        guard isReady, isLoaded, context?.composing != true,
            presentationConvergenceTask == nil, let webView
        else { return }
        _ = startPresentationConvergence(
            in: webView, requiringRequestEpoch: requestEpoch, documentID: documentID)
    }

    private func convergePendingPresentationState(
        in webView: WKWebView,
        requiringRequestEpoch intendedRequestEpoch: UInt64,
        documentID: String
    ) async throws {
        while true {
            try Task.checkCancellation()
            guard intendedRequestEpoch == requestEpoch,
                self.documentID == documentID, self.webView === webView
            else { throw SessionError.staleRequest }
            if presentationConvergenceTask == nil,
                pendingPresentationConfiguration == deliveredPresentationConfiguration
            {
                return
            }
            // Review mode admission and ordinary appearance updates can both
            // arrive before one bridge response. Join its owner rather than
            // queueing the same source-sized configuration a second time.
            let convergence = startPresentationConvergence(
                in: webView, requiringRequestEpoch: intendedRequestEpoch, documentID: documentID)
            try await convergence.value
        }
    }

    private func startPresentationConvergence(
        in webView: WKWebView,
        requiringRequestEpoch intendedRequestEpoch: UInt64,
        documentID: String
    ) -> Task<Void, Error> {
        if let presentationConvergenceTask { return presentationConvergenceTask }
        let convergenceID = UUID()
        presentationConvergenceID = convergenceID
        let convergence = Task { [weak self, weak webView] in
            defer {
                if let self, intendedRequestEpoch == self.requestEpoch, self.presentationConvergenceID == convergenceID {
                    self.presentationConvergenceTask = nil
                    self.presentationConvergenceID = nil
                }
            }
            guard let self, let webView else { throw SessionError.unavailable }
            while true {
                try Task.checkCancellation()
                guard intendedRequestEpoch == self.requestEpoch,
                    self.documentID == documentID, self.webView === webView
                else { throw SessionError.staleRequest }
                let configuration = self.pendingPresentationConfiguration
                if configuration == self.deliveredPresentationConfiguration { return }
                let delivered = try await self.send(
                    .setPresentation(configuration), in: webView,
                    requiringRequestEpoch: intendedRequestEpoch)
                try Task.checkCancellation()
                guard intendedRequestEpoch == self.requestEpoch,
                    self.documentID == documentID, self.webView === webView
                else { throw SessionError.staleRequest }
                self.deliveredPresentationConfiguration = configuration
                if delivered.resultingGeneration == configuration.imageResourceGeneration {
                    self.deliveredImageResources = configuration.imageResources
                }
                if self.pendingPresentationConfiguration == configuration { return }
            }
        }
        presentationConvergenceTask = convergence
        return convergence
    }

    private func flushPendingLine() {
        guard isReady, isLoaded, let line = pendingLine, let webView else { return }
        pendingLine = nil
        let documentID = self.documentID
        let focusRevision = focusRequestRevision
        Task {
            do {
                let focusesEditor =
                    line.focusesEditor && focusRevision == focusRequestRevision
                    && automaticFocusIsAuthorized
                _ = try await send(.goToLine(line.line, focusesEditor: focusesEditor), in: webView)
                guard line.focusesEditor, self.webView === webView,
                    focusRevision == self.focusRequestRevision, self.automaticFocusIsAuthorized,
                    self.documentID == documentID, !Task.isCancelled,
                    webView.window?.makeFirstResponder(webView) == true
                else { return }
                try await focusAndWait(.editor)
            } catch {
                // Failed or replaced navigation cannot transfer focus elsewhere.
            }
        }
    }

    private func editorSelection(for sourceRange: Range<Int>) throws -> MarkdownEditorSelectionRange {
        guard let anchor = sourceOffsetMap.editorUTF16Offset(forSourceUTF16Offset: sourceRange.lowerBound),
            let head = sourceOffsetMap.editorUTF16Offset(forSourceUTF16Offset: sourceRange.upperBound)
        else { throw SessionError.invalidResult }
        return .init(anchor: anchor, head: head)
    }

    private func flushPendingOpeningIntents(
        in webView: WKWebView, requiringRequestEpoch epoch: UInt64,
        focusWasAuthorized: Bool, focusRevision: UInt64, focusTarget: WindowDocumentFocusTarget
    ) {
        let intendedDocumentID = documentID
        let navigationWork = flushPendingNavigationIntents()
        Task { [weak self, weak webView] in
            await navigationWork?.value
            guard let self, let webView, self.requestEpoch == epoch,
                self.documentID == intendedDocumentID, self.webView === webView
            else { return }
            guard self.requestEpoch == epoch, self.documentID == intendedDocumentID,
                self.webView === webView, self.automaticFocusIsAuthorized,
                !focusWasAuthorized || focusRevision != self.focusRequestRevision || focusTarget != self.automaticFocusTarget
            else { return }
            try? await self.applyFocusIntent(self.automaticFocusTarget, revision: self.focusRequestRevision)
        }
    }

    private func flushPendingSourceRange() {
        _ = flushPendingNavigationIntents()
    }

    private func applyPendingSourceRange(in webView: WKWebView, requiringRequestEpoch epoch: UInt64) async throws {
        guard canApplyPendingSourceRange, isReady, isLoaded, !isComposing, epoch == requestEpoch, self.webView === webView,
            let range = pendingSourceRange
        else { return }
        let selection = try editorSelection(for: range)
        let isDefault = pendingSourceRangeIsDefault
        let requiresEditing = pendingSourceRangeRequiresEditing
        let revision = pendingSourceRangeRevision
        pendingSourceRange = nil
        pendingSourceRangeIsDefault = false
        pendingSourceRangeRequiresEditing = false
        do {
            _ = try await send(
                .revealSourceRange(fromUTF16: selection.anchor, toUTF16: selection.head),
                in: webView, requiringRequestEpoch: epoch)
        } catch {
            if requestEpoch == epoch, context?.composing == true, pendingSourceRange == nil,
                pendingSourceRangeRevision == revision
            {
                pendingSourceRange = range
                pendingSourceRangeIsDefault = isDefault
                pendingSourceRangeRequiresEditing = requiresEditing
            }
            throw error
        }
    }

    func send(
        _ operation: MarkdownEditorOperation,
        in webView: WKWebView,
        requiringRequestEpoch requiredRequestEpoch: UInt64? = nil,
        observingOnly: Bool = false,
        admittingFocus: (@MainActor () -> Bool)? = nil
    ) async throws -> MarkdownEditorCommandResult {
        guard !operation.requiresWritableSource || (pendingMode != .review && presentedMode != .review)
        else { throw SessionError.unavailable }
        if observingOnly {
            guard case .queryText = operation else { throw SessionError.invalidResult }
        }
        let requestDeadline = ContinuousClock.now.advanced(by: lifecyclePolicy.bridgeRequest)
        let duration = lifecyclePolicy.bridgeRequest.components
        let durationMilliseconds =
            Double(duration.seconds) * 1_000
            + Double(duration.attoseconds) / 1_000_000_000_000_000
        let expiresAt = Int64((Date().timeIntervalSince1970 * 1_000 + durationMilliseconds).rounded(.down))
        let previous = operation.serializesSourceMutation ? sourceMutationBarrier : nil
        let capturedCitationRevision = citationInteractionRevision
        let context = BridgeRequestContext(
            requestEpoch: requiredRequestEpoch ?? requestEpoch,
            sessionID: sessionID,
            documentID: documentID,
            startingFingerprint: startingFingerprint,
            generation: generation,
            webView: webView
        )
        let trackingID = UUID()
        let task = Task.immediate { @MainActor in
            let openingBridgeOperation: PerformanceProbe.NoteOpeningBridgeOperation? =
                switch operation {
                case .initialize: .initialize
                case .completePreparation: .completePreparation
                case .releasePreparation: .releasePreparation
                default: nil
                }
            var openingBridgeSample: (attemptID: UUID, dispatchNanoseconds: UInt64, returnedNanoseconds: UInt64?)?
            await previous?.value
            try Task.checkCancellation()
            guard isCurrentIdentity(context) else {
                throw SessionError.staleRequest
            }
            let remaining = ContinuousClock.now.duration(to: requestDeadline)
            guard remaining > .zero else {
                throw ScholiumWindowLifecycleError.timedOut(.bridgeRequest)
            }
            let request = MarkdownEditorRequest(
                sessionID: context.sessionID,
                documentID: context.documentID,
                startingFingerprint: context.startingFingerprint,
                knownGeneration: context.generation,
                expiresAt: expiresAt,
                operation: operation
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let requestData = try encoder.encode(request)
            guard requestData.count <= operation.maximumRequestEnvelopeBytes,
                let requestJSON = String(data: requestData, encoding: .utf8)
            else {
                throw SessionError.invalidResult
            }
            let rawResult: Any?
            do {
                var dispatchedResult: Any?
                try await withScholiumLifecycleDeadline(
                    phase: .bridgeRequest,
                    timeout: remaining
                ) { [self, bridgeDispatcher] in
                    guard isCurrentIdentity(context) else { throw SessionError.staleRequest }
                    if let admittingFocus {
                        switch operation {
                        case .focus, .focusTitle:
                            guard admittingFocus() else { throw SessionError.staleRequest }
                        default:
                            throw SessionError.invalidResult
                        }
                    }
                    if case .finishCitation(let transactionID) = operation {
                        guard
                            citationAuthority(
                                transactionID: transactionID, sessionID: context.sessionID,
                                documentID: context.documentID, revision: capturedCitationRevision) == .current
                        else { throw SessionError.staleRequest }
                    }
                    let dispatchID = UUID()
                    unfinishedBridgeDispatches.insert(dispatchID)
                    defer { unfinishedBridgeDispatches.remove(dispatchID) }
                    if openingBridgeOperation != nil,
                        let attemptID = PerformanceProbe.shared.currentNoteOpeningAttempt(editorSessionID: context.sessionID)
                    {
                        openingBridgeSample = (attemptID, DispatchTime.now().uptimeNanoseconds, nil)
                    }
                    dispatchedResult = try await bridgeDispatcher.dispatch(
                        requestJSON: requestJSON,
                        in: webView
                    )
                    if let sample = openingBridgeSample {
                        openingBridgeSample = (sample.attemptID, sample.dispatchNanoseconds, DispatchTime.now().uptimeNanoseconds)
                    }
                }
                rawResult = dispatchedResult
            } catch {
                guard isCurrentIdentity(context) else { throw SessionError.staleRequest }
                throw error
            }
            guard isCurrentIdentity(context) else { throw SessionError.staleRequest }
            guard JSONSerialization.isValidJSONObject(rawResult as Any),
                let resultData = try? JSONSerialization.data(withJSONObject: rawResult as Any),
                resultData.count <= operation.maximumResultEnvelopeBytes,
                let result = try? JSONDecoder().decode(MarkdownEditorCommandResult.self, from: resultData),
                result.requestID == request.requestID
            else {
                throw SessionError.invalidResult
            }
            guard result.accepted else {
                throw SessionError.bridgeRejected(result.error ?? ScholiumL10n.string("The Markdown editor rejected the request."))
            }
            guard result.resultingGeneration >= 0,
                markdownEditorInteractionRevisionIsValid(result.interactionRevision)
            else {
                throw SessionError.invalidResult
            }

            if case .initialize(let source, _, _, _, _, let recovery, _) = operation {
                // Initialization is a checked source install, including an
                // optional retained generation. Admit its receipt before any
                // mirror, selection or semantic availability can advance.
                guard !result.sourceChanged, result.recovery == nil,
                    result.resultingGeneration == (recovery?.generation ?? 0),
                    (result.recoveryHistoryPreserved != nil) == (recovery != nil)
                else { throw SessionError.invalidResult }
                if let recovery {
                    guard let text = result.text,
                        ScholiumExactUTF8.equal(text, source),
                        result.selections == recovery.ranges,
                        result.citationData == recovery.citationData
                    else { throw SessionError.invalidResult }
                }
            }

            // Validate the complete response before changing the checked mirror.
            // A bounded JSON envelope does not establish a bounded exact source.
            guard result.text.map({ $0.utf8.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes }) ?? true,
                result.recovery.map({
                    $0.source.utf8.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes
                        && ($0.stateJSON?.utf8.count ?? 0) <= markdownEditorMaximumRecoveryHistoryBytes
                        && ($0.undoLabel?.utf8.count ?? 0) <= 1_024
                        && ($0.redoLabel?.utf8.count ?? 0) <= 1_024
                }) ?? true,
                !result.sourceChanged || result.text != nil
            else { throw SessionError.invalidResult }
            if result.text != nil {
                guard (result.citationManaged ?? false) == (committedCitationSnapshot != nil),
                    result.citationData == nil || result.citationManaged == true,
                    result.citationData.map({ (try? $0.validate()) != nil }) ?? true
                else { throw SessionError.invalidResult }
            }

            let responseEditorLength =
                result.text.map {
                    Self.normalizedEditorUTF16Length(of: $0)
                } ?? (result.resultingGeneration == generation ? checkedEditorUTF16Length : nil)
            guard result.context?.selections == nil || result.context?.selections == result.selections else {
                throw SessionError.invalidResult
            }
            if let responseEditorLength,
                !markdownEditorSelectionRangesAreValid(
                    result.selections,
                    forEditorUTF16Length: responseEditorLength
                )
            {
                throw SessionError.invalidResult
            }
            if observingOnly {
                guard case .queryText = operation,
                    result.resultingGeneration == context.generation, generation == context.generation,
                    let text = result.text, checkedSourceBuffer.isEqual(to: text), !result.sourceChanged,
                    result.citationData == checkedCitationData
                else { throw SessionError.staleRequest }
                return result
            }
            // A later full snapshot can overtake queued deltas. An unexplained
            // same-generation mismatch cannot silently replace the checked source.
            if let text = result.text, result.resultingGeneration >= generation {
                if result.resultingGeneration == generation,
                    !checkedSourceBuffer.isEqual(to: text) || result.citationData != checkedCitationData
                {
                    updatePublished(\.isDirty, to: true)
                    sourceChangeHandler?()
                    throw SessionError.invalidResult
                }
                let citationChanged = result.citationData != checkedCitationData
                let advanced = result.resultingGeneration > generation
                try reconcileMirror(with: text, publish: advanced)
                checkedCitationData = result.citationData
                if advanced && citationChanged {
                    updatePublished(\.isDirty, to: true)
                    sourceChangeHandler?()
                }
                generation = result.resultingGeneration
                if advanced { discardSupersededAttachedRecovery() }
            }
            if result.resultingGeneration == generation,
                responseEditorLength != nil
            {
                updateInteraction(
                    selections: result.selections,
                    line: line,
                    column: column,
                    lineCount: lineCount,
                    documentVersion: result.resultingGeneration,
                    interactionRevision: result.interactionRevision,
                    context: result.context
                )
            }
            if let openingBridgeOperation, let sample = openingBridgeSample, let returnedNanoseconds = sample.returnedNanoseconds {
                PerformanceProbe.shared.recordNoteOpeningBridge(
                    operation: openingBridgeOperation, attemptID: sample.attemptID, editorSessionID: context.sessionID,
                    dispatchNanoseconds: sample.dispatchNanoseconds, returnedNanoseconds: returnedNanoseconds,
                    validatedNanoseconds: DispatchTime.now().uptimeNanoseconds)
            }
            return result
        }
        inFlightRequestTasks[trackingID] = task
        if operation.serializesSourceMutation {
            sourceMutationBarrier = Task { @MainActor in _ = try? await task.value }
        }
        defer { inFlightRequestTasks[trackingID] = nil }
        return try await task.value
    }

    private func isCurrentIdentity(_ context: BridgeRequestContext) -> Bool {
        context.requestEpoch == requestEpoch
            && context.sessionID == sessionID
            && context.documentID == documentID
            && context.startingFingerprint == startingFingerprint
            && self.webView === context.webView
    }

    #if DEBUG
        private func installQATerminationObserverIfEnabled() {
            guard !qaTerminationObserverInstalled,
                Bundle.main.bundleIdentifier == "com.scholium.qa",
                ProcessInfo.processInfo.arguments.contains("--scholium-editor-qa-faults")
            else {
                return
            }
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(receiveQATerminationNotification(_:)),
                name: Self.qaTerminationNotification,
                object: nil
            )
            qaTerminationObserverInstalled = true
        }

        private func removeQATerminationObserver() {
            guard qaTerminationObserverInstalled else { return }
            DistributedNotificationCenter.default().removeObserver(
                self,
                name: Self.qaTerminationNotification,
                object: nil
            )
            qaTerminationObserverInstalled = false
        }

        @objc private func receiveQATerminationNotification(_ notification: Notification) {
            guard notification.userInfo?["documentID"] as? String == documentID else { return }
            guard testingSimulateWebContentProcessTermination() else { return }
            if let markerPath = ProcessInfo.processInfo.environment[
                "SCHOLIUM_UI_TEST_EDITOR_FAULT_MARKER"
            ] {
                try? Data(documentID.utf8).write(
                    to: URL(fileURLWithPath: markerPath),
                    options: .atomic
                )
            }
        }
    #else
        private func installQATerminationObserverIfEnabled() {}
        private func removeQATerminationObserver() {}
    #endif

    private func invalidateRequestQueue(
        clearingRecoveryReport: Bool = true,
        preservingRendererInteraction: Bool = false
    ) {
        requestEpoch &+= 1
        lastQueueInvalidationPreservedRenderer = preservingRendererInteraction
        openingImageWaitTask?.cancel()
        openingImageWaitTask = nil
        openingImageWaitID = nil
        navigationIntentTask?.cancel()
        navigationIntentTask = nil
        navigationIntentTaskID = nil
        presentationConvergenceTask?.cancel()
        presentationConvergenceTask = nil
        presentationConvergenceID = nil
        deliveredPresentationConfiguration = nil
        if !preservingRendererInteraction { rendererInteractionRevision = nil }
        imageResourceQueryTask?.cancel()
        imageResourceQueryTask = nil
        imageResourceQueryID = nil
        rejectedChangeRecoveryTask?.cancel()
        rejectedChangeRecoveryTask = nil
        rejectedChangeRecoveryID = nil
        pendingRejectedChangeGeneration = nil
        if clearingRecoveryReport {
            updatePresentation {
                $0.clearReport(matching: Self.rejectedChangeRecoveryMessage)
            }
        }
        sourceMutationBarrier?.cancel()
        sourceMutationBarrier = nil
        for task in inFlightRequestTasks.values {
            task.cancel()
        }
        inFlightRequestTasks.removeAll()
    }

    private func fallbackSelectionSnapshot() -> MarkdownEditorSelectionSnapshot {
        MarkdownEditorSelectionSnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: generation,
            ranges: [MarkdownEditorSelectionRange(anchor: 0, head: 0)]
        )
    }

    private func currentValidSelectionRanges() -> [MarkdownEditorSelectionRange] {
        if let snapshot = lastKnownSelectionSnapshot,
            snapshot.isValid(
                documentID: documentID,
                fingerprint: startingFingerprint,
                generation: generation,
                editorUTF16Length: checkedEditorUTF16Length
            )
        {
            return snapshot.ranges
        }
        if let snapshot = recoverySnapshot,
            snapshot.documentID == documentID,
            snapshot.fingerprint == startingFingerprint,
            snapshot.generation == generation,
            snapshot.source.utf8.elementsEqual(checkedSource.utf8),
            snapshot.citationSnapshot == committedCitationSnapshot,
            snapshot.citationData == checkedCitationData,
            markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
            )
        {
            return snapshot.ranges
        }
        return fallbackSelectionSnapshot().ranges
    }

    private func updatePresentation(
        _ update: (inout MarkdownEditorPresentationState) -> Void
    ) {
        var next = presentation
        update(&next)
        guard next != presentation else { return }
        presentation = next
        if let mode = next.presentedMode, mode != .review {
            hasPresentedWritableMode = true
            if canApplyPendingSourceRange { flushPendingSourceRange() }
        }
    }

    private func updatePublished<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<MarkdownEditorSession, Value>,
        to value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    private func reconcileMirror(with text: String, publish: Bool) throws {
        guard !checkedSourceBuffer.isEqual(to: text) else { return }
        checkedSourceBuffer.replace(with: text)
        sourceOffsetMap = EditorSourceOffsetMap(source: text)
        checkedEditorUTF16Length = sourceOffsetMap.editorUTF16Length
        if publish {
            updatePublished(\.isDirty, to: true)
            sourceChangeHandler?()
        }
    }

    /// The live page owns newer source and Undo. An older capture can no longer
    /// recover that generation; keep only captures that still prove its state.
    /// Loading/restoration retains the capture until its history is installed.
    private func discardSupersededAttachedRecovery() {
        guard isReady, isLoaded, webView != nil else { return }
        if let snapshot = recoverySnapshot, snapshot.generation < generation {
            recoverySnapshot = nil
        }
        if let capture = detachmentCapture, capture.snapshot.generation < generation {
            detachmentCapture = nil
        }
    }

    private static func normalizedEditorUTF16Length(of source: String) -> Int {
        let units = source.utf16
        var index = units.startIndex
        var length = 0
        while index < units.endIndex {
            if units[index] == 13 {
                let next = units.index(after: index)
                if next < units.endIndex, units[next] == 10 {
                    index = units.index(after: next)
                    length += 1
                    continue
                }
            }
            index = units.index(after: index)
            length += 1
        }
        return length
    }

    func wireAnchor(
        from anchor: EditorScrollAnchor,
        in source: String
    ) -> MarkdownEditorWireScrollAnchor? {
        guard anchor.sourceFingerprint == DocumentFingerprint(content: source).sha256,
            anchor.isValid(forUTF16Length: source.utf16.count),
            let sourceOffset = sourceOffsetMap.editorUTF16Offset(
                forSourceUTF16Offset: anchor.sourceUTF16Offset
            ),
            let lowerBound = sourceOffsetMap.editorUTF16Offset(
                forSourceUTF16Offset: anchor.blockUTF16LowerBound
            ),
            let upperBound = sourceOffsetMap.editorUTF16Offset(
                forSourceUTF16Offset: anchor.blockUTF16UpperBound
            )
        else { return nil }
        return MarkdownEditorWireScrollAnchor(
            sourceUTF16Offset: sourceOffset,
            blockUTF16LowerBound: lowerBound,
            blockUTF16UpperBound: upperBound,
            relativeBlockPosition: anchor.relativeBlockPosition,
            fallbackFraction: anchor.fallbackFraction
        )
    }
}
