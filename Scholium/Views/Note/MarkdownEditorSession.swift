import AppKit
import Foundation
import ScholiumContracts
import SwiftUI
import WebKit

@MainActor
final class MarkdownEditorSession: NSObject, ObservableObject {
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

        var errorDescription: String? {
            switch self {
            case .unavailable: "The Markdown editor is not ready."
            case .invalidResult: "The Markdown editor returned an invalid document."
            case .selectionTooLong: "Select at most 2,000 characters for one source-anchored comment."
            case .staleRequest: "The Markdown editor request belonged to a replaced document or session."
            case .bridgeRejected(let message): message
            }
        }
    }

    @Published private(set) var isReady = false
    @Published private(set) var isLoaded = false
    @Published private(set) var presentedMode: NotePresentationMode?
    @Published private(set) var isDirty = false
    private(set) var line = 1
    private(set) var column = 1
    private(set) var lineCount = 1
    @Published private(set) var errorMessage: String?
    @Published private(set) var interactionAvailability: EditorInteractionAvailability?
    private(set) var context: MarkdownEditorContext?
    private(set) var sessionID = UUID()
    private(set) var documentID = ""

    /// Opaque identity for the CodeMirror document owned by this retained
    /// session. A vault-relative path is a mutable projection and must not
    /// force a new EditorState when the same stable note is renamed.
    var bridgeDocumentID: String { sessionID.uuidString }
    private(set) var startingFingerprint = ""
    private(set) var generation = 0

    var webView: WKWebView?
    private var pendingSource: String?
    private var pendingDocumentID = ""
    private var pendingMode: NotePresentationMode = .livePreview
    private var pendingPresentationCSS = ""
    private var pendingUserCSS = ""
    private var pendingLine: Int?
    private var pendingSourceRange: Range<Int>?
    private var pendingLinkPreviews: [MarkdownEditorLinkPreview] = []
    var pendingScrollFraction: Double?
    var pendingScrollAnchor: EditorScrollAnchor?
    private var reconstructionScrollAnchor: EditorScrollAnchor?
    private var startupTask: Task<Void, Never>?
    private var recoveryCaptureTask: Task<Void, Never>?
    private var scheduledRecoveryCaptureKey: RecoveryCaptureKey?
    private var recoveryCaptureToken: UInt64 = 0
    private var requestBarrier: Task<Void, Never>?
    private var inFlightRequestTasks: [UUID: Task<MarkdownEditorCommandResult, Error>] = [:]
    private var requestEpoch: UInt64 = 0
    private var modeRequestEpoch: UInt64 = 0
    private var modeBeingApplied: NotePresentationMode?
    private let bridgeDispatcher: any MarkdownEditorBridgeDispatching
    private let lifecyclePolicy: ScholiumLifecyclePolicy
    private var committedTextSynchronizer: ((String, String) -> Void)?
    private var sourceChangeHandler: ((String) -> Void)?
    var checkedSource = ""
    private var checkedEditorUTF16Length = 0
    private var sourceOffsetMap = EditorSourceOffsetMap(source: "")
    private var recoverySnapshot: MarkdownEditorRecoverySnapshot?
    private var lastKnownSelectionSnapshot: MarkdownEditorSelectionSnapshot?
    #if DEBUG
    private static let qaTerminationNotification = Notification.Name(
        "com.scholium.qa.simulate-editor-process-termination"
    )
    private var qaTerminationObserverInstalled = false
    #endif
    var hasAttachedWebView: Bool { webView != nil }
    var hasRecoverableBuffer: Bool {
        isDirty || recoverySnapshot?.dirty == true
    }
    var canAttemptPreview: Bool { pendingMode == .livePreview }
    var canShowPreviewAtSelection: Bool {
        guard pendingMode == .livePreview,
              let selectionSnapshot = lastKnownSelectionSnapshot,
              selectionSnapshot.isValid(
                documentID: documentID,
                fingerprint: startingFingerprint,
                generation: generation,
                editorUTF16Length: checkedEditorUTF16Length
              ),
              let head = selectionSnapshot.ranges.first?.head else { return false }
        if pendingLinkPreviews.contains(where: { head >= $0.from && head < $0.to }) {
            return true
        }
        return false
    }

    override convenience init() {
        self.init(
            bridgeDispatcher: WKWebViewMarkdownEditorBridgeDispatcher(),
            lifecyclePolicy: ScholiumLifecyclePolicy()
        )
    }

    init(
        bridgeDispatcher: any MarkdownEditorBridgeDispatching,
        lifecyclePolicy: ScholiumLifecyclePolicy = ScholiumLifecyclePolicy()
    ) {
        self.bridgeDispatcher = bridgeDispatcher
        self.lifecyclePolicy = lifecyclePolicy
        super.init()
    }


    func attach(_ webView: WKWebView) {
        invalidateRequestQueue()
        self.webView = webView
        sessionID = UUID()
        modeRequestEpoch &+= 1
        modeBeingApplied = nil
        updatePublished(\.isReady, to: false)
        updatePublished(\.isLoaded, to: false)
        updatePublished(\.presentedMode, to: nil)
        updatePublished(\.errorMessage, to: nil)
        installQATerminationObserverIfEnabled()
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, !self.isReady else { return }
            self.reportError(String(localized: "Edit mode did not finish starting.", table: "Localizable", bundle: .module))
        }
    }

    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        invalidateRequestQueue()
        startupTask?.cancel()
        cancelScheduledRecoveryCapture()
        self.webView = nil
        modeRequestEpoch &+= 1
        modeBeingApplied = nil
        updatePublished(\.isReady, to: false)
        updatePublished(\.isLoaded, to: false)
        updatePublished(\.presentedMode, to: nil)
        removeQATerminationObserver()
    }

    /// Clears the retained editor mirror and callbacks only after AppKit has
    /// detached the WebView and the session store proved there is no lease or
    /// recovery pin. Closed documents intentionally do not retain undo state.
    func shutdownDetachedSession() {
        precondition(webView == nil)
        invalidateRequestQueue()
        startupTask?.cancel()
        startupTask = nil
        cancelScheduledRecoveryCapture()
        committedTextSynchronizer = nil
        sourceChangeHandler = nil
        pendingSource = nil
        pendingDocumentID = ""
        pendingLinkPreviews = []
        pendingScrollFraction = nil
        pendingScrollAnchor = nil
        reconstructionScrollAnchor = nil
        checkedSource = ""
        checkedEditorUTF16Length = 0
        sourceOffsetMap = EditorSourceOffsetMap(source: "")
        recoverySnapshot = nil
        lastKnownSelectionSnapshot = nil
        modeRequestEpoch &+= 1
        modeBeingApplied = nil
        updatePublished(\.isReady, to: false)
        updatePublished(\.isLoaded, to: false)
        updatePublished(\.presentedMode, to: nil)
        updatePublished(\.isDirty, to: false)
    }

    func editorBecameReady() {
        startupTask?.cancel()
        updatePublished(\.isReady, to: true)
        flushPendingState()
    }

    /// Applies the rAF-coalesced v5 interaction envelope. Exact cursor
    /// coordinates stay readable for commands and recovery, but they are not
    /// Observable state. Only a semantic availability change invalidates UI.
    func updateInteraction(
        selections: [MarkdownEditorSelectionRange],
        line: Int,
        column: Int,
        lineCount: Int,
        documentVersion: Int,
        context semanticContext: MarkdownEditorContext?
    ) {
        let wasComposing = context?.composing == true
        guard documentVersion == generation,
              markdownEditorSelectionRangesAreValid(
                selections,
                forEditorUTF16Length: checkedEditorUTF16Length
              ),
              semanticContext?.selections == nil || semanticContext?.selections == selections else { return }
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: documentVersion,
            ranges: selections
        )
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
            reconvergePendingPresentationState()
        }
        flushPendingSourceRange()
    }

    func reportError(_ message: String) {
        startupTask?.cancel()
        updatePublished(\.errorMessage, to: message)
        updatePublished(\.isLoaded, to: false)
        updatePublished(\.presentedMode, to: nil)
    }

    func loadDocument(
        _ source: String,
        documentID: String,
        mode: NotePresentationMode,
        preservingRecovery: Bool = false
    ) {
        invalidateRequestQueue()
        cancelScheduledRecoveryCapture()
        let retainedStartingFingerprint = preservingRecovery ? startingFingerprint : nil
        if !preservingRecovery {
            recoverySnapshot = nil
            lastKnownSelectionSnapshot = nil
            reconstructionScrollAnchor = nil
            context = nil
            updatePublished(\.interactionAvailability, to: nil)
        }
        pendingSource = source
        pendingDocumentID = documentID
        self.documentID = documentID
        startingFingerprint = retainedStartingFingerprint
            ?? DocumentFingerprint(content: source).sha256
        checkedSource = source
        sourceOffsetMap = EditorSourceOffsetMap(source: source)
        checkedEditorUTF16Length = sourceOffsetMap.editorUTF16Length
        generation = 0
        pendingMode = mode
        modeRequestEpoch &+= 1
        modeBeingApplied = nil
        updatePublished(\.isLoaded, to: false)
        updatePublished(\.presentedMode, to: nil)
        updatePublished(\.isDirty, to: false)
        updatePublished(\.errorMessage, to: nil)
        flushPendingState()
    }

    func setMode(_ mode: NotePresentationMode) {
        guard mode != .read else { return }
        pendingMode = mode
        guard isReady, isLoaded, let webView else { return }
        guard presentedMode != mode,
              modeBeingApplied != mode else { return }
        modeRequestEpoch &+= 1
        let intendedModeRequestEpoch = modeRequestEpoch
        modeBeingApplied = mode
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await send(.setMode(mode), in: webView)
                guard intendedModeRequestEpoch == modeRequestEpoch,
                      pendingMode == mode,
                      self.webView === webView else { return }
                modeBeingApplied = nil
                updatePublished(\.presentedMode, to: mode)
                PerformanceProbe.shared.markEditorModeReady(
                    documentID: documentID,
                    mode: mode
                )
            } catch {
                guard intendedModeRequestEpoch == modeRequestEpoch else { return }
                modeBeingApplied = nil
                let message = "The document mode change was not applied because the editor changed during text composition."
                updatePublished(\.errorMessage, to: message)
                _ = try? await send(.announceStatus(message), in: webView)
            }
        }
    }

    func setUserCSS(_ css: String) {
        pendingUserCSS = css
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setUserCSS(css), in: webView)
        }
    }

    func setPresentationCSS(_ css: String) {
        pendingPresentationCSS = css
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setPresentationCSS(css), in: webView)
        }
    }

    func goToLine(_ line: Int) {
        pendingLine = max(1, line)
        flushPendingLine()
    }

    func revealSourceRange(fromUTF16: Int, toUTF16: Int) {
        let lowerBound = max(0, fromUTF16)
        pendingSourceRange = lowerBound..<max(lowerBound, toUTF16)
        flushPendingSourceRange()
    }

    func setScrollFraction(_ fraction: Double) {
        let normalized = min(1, max(0, fraction))
        pendingScrollFraction = normalized
        pendingScrollAnchor = nil
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setScrollFraction(normalized), in: webView)
        }
    }

    func setScrollPosition(anchor: EditorScrollAnchor?, fallbackFraction: Double) {
        let normalized = min(1, max(0, fallbackFraction))
        pendingScrollFraction = normalized
        pendingScrollAnchor = anchor
        guard isReady, isLoaded, let webView else { return }
        Task {
            if let anchor,
               let wireAnchor = wireAnchor(from: anchor, in: checkedSource) {
                _ = try? await send(.setScrollAnchor(wireAnchor), in: webView)
            } else {
                _ = try? await send(.setScrollFraction(normalized), in: webView)
            }
        }
    }

    func recordScrollFraction(_ fraction: Double) {
        pendingScrollFraction = min(1, max(0, fraction))
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
              ) else {
            pendingScrollAnchor = nil
            return nil
        }
        let anchor = EditorScrollAnchor(
            sourceFingerprint: DocumentFingerprint(content: checkedSource).sha256,
            sourceUTF16Offset: sourceOffset,
            blockUTF16LowerBound: lowerBound,
            blockUTF16UpperBound: upperBound,
            relativeBlockPosition: wireAnchor.relativeBlockPosition,
            fallbackFraction: fraction
        )
        guard anchor.isValid(forUTF16Length: checkedSource.utf16.count) else {
            pendingScrollAnchor = nil
            return nil
        }
        pendingScrollAnchor = anchor
        return anchor
    }

    func retainedScrollFraction(fallback: Double) -> Double {
        pendingScrollFraction ?? min(1, max(0, fallback))
    }

    var retainedScrollAnchor: EditorScrollAnchor? {
        reconstructionScrollAnchor ?? pendingScrollAnchor
    }

    func setLinkPreviews(_ previews: [DocumentLinkPreview], in source: String) {
        let offsetMap = source == checkedSource
            ? sourceOffsetMap
            : EditorSourceOffsetMap(source: source)
        pendingLinkPreviews = previews.prefix(DocumentPreviewCatalogBuilder.maximumLinkCount).compactMap { preview in
            guard let from = offsetMap.editorUTF16Offset(
                forSourceUTF16Offset: preview.sourceSpan.utf16LowerBound
            ), let to = offsetMap.editorUTF16Offset(
                forSourceUTF16Offset: preview.sourceSpan.utf16UpperBound
            ), to > from else { return nil }
            return MarkdownEditorLinkPreview(
                from: from,
                to: to,
                title: String(preview.title.prefix(240)),
                relationship: preview.relationship,
                fragment: preview.fragment.map { String($0.prefix(240)) },
                htmlBody: String(preview.htmlBody.prefix(24_000))
            )
        }
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setLinkPreviews(pendingLinkPreviews), in: webView)
        }
    }

    func showPreview() {
        guard canAttemptPreview, isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.showPreview, in: webView)
        }
    }

    func showPreview(at point: CGPoint) {
        guard canAttemptPreview, isReady, isLoaded, let webView,
              point.x.isFinite, point.y.isFinite else { return }
        Task {
            _ = try? await send(
                .showPreviewAt(x: point.x, y: point.y),
                in: webView
            )
        }
    }

    func currentText(for expectedDocumentID: String? = nil) async throws -> String {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let intendedDocumentID = documentID
        let intendedFingerprint = startingFingerprint
        let result = try await send(.queryText, in: webView)
        guard intendedRequestEpoch == requestEpoch,
              intendedDocumentID == documentID,
              intendedFingerprint == startingFingerprint,
              self.webView === webView,
              let text = result.text else { throw SessionError.invalidResult }
        try reconcileMirror(with: text, publish: true)
        return checkedSource
    }

    /// A retained editor can be briefly unavailable while SwiftUI reattaches
    /// its WebView after a document projection changes. Saves must wait for
    /// that same session to finish loading instead of treating the transient
    /// presentation gap as loss of the authoritative CodeMirror buffer.
    func waitUntilLoadedForSave(
        maximumWait: Duration = .seconds(6)
    ) async throws -> Bool {
        if isReady, isLoaded, webView != nil { return true }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: maximumWait)
        while clock.now < deadline {
            try Task.checkCancellation()
            try await clock.sleep(for: .milliseconds(50))
            if isReady, isLoaded, webView != nil { return true }
        }
        return isReady && isLoaded && webView != nil
    }

    /// Captures CodeMirror's exact source, selection, and bounded history before
    /// SwiftUI removes the WKWebView during a note collapse or replacement.
    /// The retained document session replays this snapshot into the next view.
    func captureStateForViewReconstruction() async throws {
        cancelScheduledRecoveryCapture()
        let expectedKey = RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        )
        try await captureRecoverySnapshot(expectedKey: expectedKey)
        guard expectedKey == RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        ) else { throw SessionError.invalidResult }
        let capturedScrollAnchor = try? await currentScrollAnchor()
        guard expectedKey == RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        ) else { throw SessionError.invalidResult }
        reconstructionScrollAnchor = capturedScrollAnchor ?? pendingScrollAnchor
    }

    private func captureRecoverySnapshot(
        expectedKey: RecoveryCaptureKey
    ) async throws {
        guard expectedKey == RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        ) else { throw SessionError.invalidResult }
        guard isReady, isLoaded, let webView else { return }
        let result = try await send(.captureRecovery, in: webView)
        try Task.checkCancellation()
        guard let snapshot = result.recovery,
              snapshot.documentID == documentID,
              snapshot.fingerprint == startingFingerprint,
              snapshot.generation == generation,
              snapshot.source == checkedSource,
              markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
              ),
              expectedKey == RecoveryCaptureKey(
                requestEpoch: requestEpoch,
                generation: generation
              ) else {
            throw SessionError.invalidResult
        }
        recoverySnapshot = snapshot
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
              self.webView === webView else {
            throw SessionError.bridgeRejected("The editor identity changed while reading its scroll position.")
        }
        return recordScrollPosition(
            result.scrollAnchor,
            fallbackFraction: result.scrollAnchor?.fallbackFraction
                ?? pendingScrollFraction
                ?? 0
        )
    }

    func queryPerformanceSamples() async throws -> [MarkdownEditorPerformanceSample] {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let result = try await send(.queryPerformance, in: webView)
        guard intendedRequestEpoch == requestEpoch,
              self.webView === webView,
              result.accepted,
              let samples = result.performanceSamples else {
            throw SessionError.invalidResult
        }
        return samples
    }

    func hasRecoverySnapshot(documentID: String, source: String) -> Bool {
        guard let snapshot = recoverySnapshot else { return false }
        return snapshot.documentID == documentID
            && snapshot.fingerprint == startingFingerprint
            && snapshot.generation >= 0
            && snapshot.source == source
            && markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: Self.normalizedEditorUTF16Length(of: source)
            )
    }

    func currentSelection(
        for expectedDocumentID: String? = nil,
        in source: String? = nil
    ) async throws -> MarkdownReviewSelection? {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
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
              exactSource == checkedSource,
              source == nil || source == exactSource,
              markdownEditorSelectionRangesAreValid(
                result.selections,
                forEditorUTF16Length: checkedEditorUTF16Length
              ),
              let range = result.selections.first else {
            throw SessionError.invalidResult
        }
        let editorLower = min(range.anchor, range.head)
        let editorUpper = max(range.anchor, range.head)
        guard editorUpper > editorLower else { return nil }
        guard let lower = sourceOffsetMap.sourceUTF16Offset(forEditorUTF16Offset: editorLower),
              let upper = sourceOffsetMap.sourceUTF16Offset(forEditorUTF16Offset: editorUpper),
              upper > lower,
              upper - lower <= 2_000 else { throw SessionError.selectionTooLong }
        let units = exactSource.utf16
        guard let lowerUTF16 = units.index(units.startIndex, offsetBy: lower, limitedBy: units.endIndex),
              let upperUTF16 = units.index(units.startIndex, offsetBy: upper, limitedBy: units.endIndex),
              let lowerIndex = String.Index(lowerUTF16, within: exactSource),
              let upperIndex = String.Index(upperUTF16, within: exactSource) else {
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

    func synchronizeCommittedText(
        expectedText: String,
        committedText: String,
        fingerprint: DocumentFingerprint,
        documentID expectedDocumentID: String
    ) async throws -> Bool {
        guard expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let intendedRequestEpoch = requestEpoch
        let intendedFingerprint = startingFingerprint
        _ = try await send(
            .synchronizeCommittedText(
                expected: expectedText,
                committed: committedText,
                fingerprint: fingerprint.sha256
            ),
            in: webView
        )
        guard intendedRequestEpoch == requestEpoch,
              expectedDocumentID == documentID,
              intendedFingerprint == startingFingerprint,
              self.webView === webView else { return false }
        try reconcileMirror(with: committedText, publish: false)
        let rebasedRanges = currentValidSelectionRanges()
        invalidateRequestQueue()
        cancelScheduledRecoveryCapture()
        startingFingerprint = fingerprint.sha256
        lastKnownSelectionSnapshot = MarkdownEditorSelectionSnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: generation,
            ranges: rebasedRanges
        )
        // A serialized EditorState captured before commit carries the previous
        // bridge identity and may also predate line-separator reconciliation.
        // Keep an immediately recoverable exact-source fallback, then replace
        // it with a fresh bounded capture under the committed fingerprint.
        recoverySnapshot = MarkdownEditorRecoverySnapshot(
            documentID: documentID,
            fingerprint: startingFingerprint,
            generation: generation,
            ranges: rebasedRanges,
            source: checkedSource,
            stateJSON: nil,
            undoHistoryPreserved: false,
            dirty: false
        )
        updatePublished(\.isDirty, to: false)
        committedTextSynchronizer?(committedText, fingerprint.sha256)
        scheduleRecoveryCapture(for: generation)
        return true
    }

    func installCommittedTextSynchronizer(
        _ synchronizer: @escaping (String, String) -> Void
    ) {
        committedTextSynchronizer = synchronizer
    }

    func removeCommittedTextSynchronizer() {
        committedTextSynchronizer = nil
    }

    func installSourceChangeHandler(_ handler: @escaping (String) -> Void) {
        sourceChangeHandler = handler
    }

    func removeSourceChangeHandler() {
        sourceChangeHandler = nil
    }

    func markClean() {
        updatePublished(\.isDirty, to: false)
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.markClean, in: webView)
        }
    }

    func focus() {
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.focus, in: webView)
        }
    }

    /// Removes keyboard focus before the retained editor is hidden by Read.
    /// The WebView remains attached so selection, undo, and CodeMirror state
    /// survive, but it must not continue accepting invisible input.
    func resignFocus() {
        guard isReady, let webView else { return }
        if let window = webView.window,
           let firstResponder = window.firstResponder as? NSView,
           firstResponder === webView || firstResponder.isDescendant(of: webView) {
            window.makeFirstResponder(nil)
        }
        Task {
            _ = try? await send(.blur, in: webView)
        }
    }

    func perform(_ command: MarkdownEditorCommand, argument: String? = nil) async throws {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        _ = try await send(.command(command, argument: argument), in: webView)
    }

    func acceptEditorChanges(
        _ rawChanges: [EditorBridgeChange],
        baseGeneration: Int,
        resultingGeneration: Int
    ) -> String? {
        guard !rawChanges.isEmpty,
              rawChanges.count <= 512,
              baseGeneration == generation,
              resultingGeneration == baseGeneration + 1 else { return nil }
        let sourceBeforeChanges = checkedSource
        let usesCRLF = sourceBeforeChanges.contains("\r\n")
        var changes: [MarkdownEditorDelta] = []
        var insertedUTF16Count = 0
        var resultingEditorUTF16Length = checkedEditorUTF16Length
        for raw in rawChanges {
            guard raw.from >= 0,
                  raw.to >= raw.from,
                  raw.to <= checkedEditorUTF16Length else { return nil }
            insertedUTF16Count += raw.insert.utf16.count
            resultingEditorUTF16Length += Self.normalizedEditorUTF16Length(of: raw.insert)
                - (raw.to - raw.from)
            guard insertedUTF16Count <= 2_000_000,
                  resultingEditorUTF16Length >= 0,
                  let from = sourceOffsetMap.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.from
                  ),
                  let to = sourceOffsetMap.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.to
                  ) else { return nil }
            changes.append(MarkdownEditorDelta(
                fromUTF16: from,
                toUTF16: to,
                insertion: usesCRLF
                    ? raw.insert.replacingOccurrences(of: "\n", with: "\r\n")
                    : raw.insert
            ))
        }
        guard let nextSource = try? MarkdownEditorDeltaApplier.apply(changes, to: checkedSource) else {
            return nil
        }
        sourceOffsetMap.apply(changes, resultingSource: nextSource)
        checkedSource = nextSource
        checkedEditorUTF16Length = resultingEditorUTF16Length
        generation = resultingGeneration
        updatePublished(\.isDirty, to: true)
        sourceChangeHandler?(nextSource)
        scheduleRecoveryCapture(for: resultingGeneration)
        return nextSource
    }

    func webContentProcessTerminated() {
        invalidateRequestQueue()
        cancelScheduledRecoveryCapture()
        let recoveryRanges = currentValidSelectionRanges()
        if let snapshot = recoverySnapshot,
           snapshot.documentID == documentID,
           snapshot.fingerprint == startingFingerprint,
           snapshot.generation == generation,
           snapshot.source == checkedSource,
           markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
           ) {
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
                dirty: isDirty
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
                dirty: isDirty
            )
        }
        pendingSource = checkedSource
        pendingDocumentID = documentID
        updatePublished(\.isReady, to: false)
        updatePublished(\.isLoaded, to: false)
    }

    private func scheduleRecoveryCapture(for generation: Int) {
        let key = RecoveryCaptureKey(
            requestEpoch: requestEpoch,
            generation: generation
        )
        if scheduledRecoveryCaptureKey == key, recoveryCaptureTask != nil {
            return
        }
        recoveryCaptureTask?.cancel()
        recoveryCaptureToken &+= 1
        let token = recoveryCaptureToken
        scheduledRecoveryCaptureKey = key
        recoveryCaptureTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                guard let self else { return }
                try await self.captureRecoverySnapshot(expectedKey: key)
            } catch {
                // A newer generation, identity transition, or explicit
                // reconstruction capture owns recovery now.
            }
            guard let self, self.recoveryCaptureToken == token else { return }
            self.recoveryCaptureTask = nil
            self.scheduledRecoveryCaptureKey = nil
        }
    }

    private func flushPendingState() {
        guard isReady, let source = pendingSource, let webView else { return }
        pendingSource = nil
        let mode = pendingMode
        let documentID = pendingDocumentID
        let intendedRequestEpoch = requestEpoch
        Task {
            do {
                guard intendedRequestEpoch == requestEpoch,
                      self.documentID == documentID,
                      self.webView === webView else { return }
                let matchingRecovery = recoverySnapshot.flatMap { snapshot in
                    snapshot.documentID == documentID
                        && snapshot.fingerprint == startingFingerprint
                        && snapshot.generation >= 0
                        && snapshot.source == source
                        && markdownEditorSelectionRangesAreValid(
                            snapshot.ranges,
                            forEditorUTF16Length: checkedEditorUTF16Length
                        )
                        ? snapshot
                        : nil
                }
                checkedSource = source
                sourceOffsetMap = EditorSourceOffsetMap(source: source)
                checkedEditorUTF16Length = sourceOffsetMap.editorUTF16Length
                generation = 0
                _ = try await send(
                    .initialize(text: source, mode: mode, dialect: .current),
                    in: webView,
                    requiringRequestEpoch: intendedRequestEpoch
                )
                if let snapshot = matchingRecovery,
                   snapshot.fingerprint == startingFingerprint,
                   snapshot.source == checkedSource {
                    let recovered = try await send(
                        .restoreRecovery(snapshot),
                        in: webView,
                        requiringRequestEpoch: intendedRequestEpoch
                    )
                    guard intendedRequestEpoch == requestEpoch,
                          self.documentID == documentID,
                          self.webView === webView else { return }
                    generation = recovered.resultingGeneration
                    updatePublished(\.isDirty, to: snapshot.dirty)
                    if recovered.recovery?.undoHistoryPreserved == false {
                        updatePublished(
                            \.errorMessage,
                            to: String(localized: "The exact editor buffer was recovered, but its pre-crash undo history was unavailable.", table: "Localizable", bundle: .module)
                        )
                        _ = try await send(
                            .announceStatus(
                                "The exact editor buffer was recovered. Pre-crash undo history is unavailable."
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
                      self.webView === webView else { return }
                reconstructionScrollAnchor = nil
                // Appearance and snippet stores can finish loading after the
                // page is ready but while document initialization is still in
                // flight. Keep the editor hidden until a serial convergence
                // pass observes the same latest values before and after all
                // three bridge requests. A SwiftUI update that arrives during
                // an await therefore causes another pass instead of becoming
                // a permanently dropped initial style or preview update.
                try await convergePendingPresentationState(
                    in: webView,
                    requiringRequestEpoch: intendedRequestEpoch,
                    documentID: documentID
                )
                // Recovery and the final converged styles can both change
                // visual block heights. Restore the retained position only
                // after both have settled into the retained EditorState.
                if let anchor = pendingScrollAnchor,
                   let wireAnchor = wireAnchor(from: anchor, in: checkedSource) {
                    _ = try await send(
                        .setScrollAnchor(wireAnchor),
                        in: webView,
                        requiringRequestEpoch: intendedRequestEpoch
                    )
                } else {
                    _ = try await send(
                        .setScrollFraction(pendingScrollFraction ?? 0),
                        in: webView,
                        requiringRequestEpoch: intendedRequestEpoch
                    )
                }
                var appliedMode = mode
                while pendingMode != appliedMode {
                    let requestedMode = pendingMode
                    _ = try await send(
                        .setMode(requestedMode),
                        in: webView,
                        requiringRequestEpoch: intendedRequestEpoch
                    )
                    appliedMode = requestedMode
                }
                modeBeingApplied = nil
                updatePublished(\.presentedMode, to: appliedMode)
                updatePublished(\.isLoaded, to: true)
                PerformanceProbe.shared.markEditorModeReady(
                    documentID: documentID,
                    mode: appliedMode
                )
                flushPendingLine()
                flushPendingSourceRange()
                focus()
            } catch {
                guard intendedRequestEpoch == requestEpoch,
                      self.documentID == documentID,
                      self.webView === webView else { return }
                updatePublished(\.isLoaded, to: false)
                updatePublished(\.presentedMode, to: nil)
                updatePublished(\.errorMessage, to: error.localizedDescription)
            }
        }
    }

    private func reconvergePendingPresentationState() {
        guard isReady, isLoaded, context?.composing != true,
              let webView else { return }
        let intendedRequestEpoch = requestEpoch
        let documentID = documentID
        Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            try? await self.convergePendingPresentationState(
                in: webView,
                requiringRequestEpoch: intendedRequestEpoch,
                documentID: documentID
            )
        }
    }

    private func convergePendingPresentationState(
        in webView: WKWebView,
        requiringRequestEpoch intendedRequestEpoch: UInt64,
        documentID: String
    ) async throws {
        while true {
            let presentationCSS = pendingPresentationCSS
            let userCSS = pendingUserCSS
            let linkPreviews = pendingLinkPreviews
            _ = try await send(
                .setPresentationCSS(presentationCSS),
                in: webView,
                requiringRequestEpoch: intendedRequestEpoch
            )
            _ = try await send(
                .setUserCSS(userCSS),
                in: webView,
                requiringRequestEpoch: intendedRequestEpoch
            )
            _ = try await send(
                .setLinkPreviews(linkPreviews),
                in: webView,
                requiringRequestEpoch: intendedRequestEpoch
            )
            guard intendedRequestEpoch == requestEpoch,
                  self.documentID == documentID,
                  self.webView === webView else {
                throw SessionError.staleRequest
            }
            if presentationCSS == pendingPresentationCSS,
               userCSS == pendingUserCSS,
               linkPreviews == pendingLinkPreviews {
                return
            }
        }
    }

    private func flushPendingLine() {
        guard isReady, isLoaded, let line = pendingLine, let webView else { return }
        pendingLine = nil
        Task {
            _ = try? await send(.goToLine(line), in: webView)
        }
    }

    private func flushPendingSourceRange() {
        guard isReady,
              isLoaded,
              context?.composing != true,
              let range = pendingSourceRange,
              let webView else { return }
        pendingSourceRange = nil
        Task { [weak self] in
            do {
                _ = try await self?.send(
                    .revealSourceRange(
                        fromUTF16: range.lowerBound,
                        toUTF16: range.upperBound
                    ),
                    in: webView
                )
            } catch {
                guard let self else { return }
                if self.context?.composing == true {
                    self.pendingSourceRange = range
                }
            }
        }
    }

    func send(
        _ operation: MarkdownEditorOperation,
        in webView: WKWebView,
        requiringRequestEpoch requiredRequestEpoch: UInt64? = nil
    ) async throws -> MarkdownEditorCommandResult {
        let previous = requestBarrier
        let context = BridgeRequestContext(
            requestEpoch: requiredRequestEpoch ?? requestEpoch,
            sessionID: sessionID,
            documentID: documentID,
            startingFingerprint: startingFingerprint,
            generation: generation,
            webView: webView
        )
        let trackingID = UUID()
        let task = Task { @MainActor in
            await previous?.value
            guard isCurrent(context) else {
                throw SessionError.staleRequest
            }
            let request = MarkdownEditorRequest(
                sessionID: context.sessionID,
                documentID: context.documentID,
                startingFingerprint: context.startingFingerprint,
                expectedGeneration: context.generation,
                operation: operation
            )
            let encoder = JSONEncoder()
            let requestData = try encoder.encode(request)
            guard requestData.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes + 512_000,
                  let requestJSON = String(data: requestData, encoding: .utf8) else {
                throw SessionError.invalidResult
            }
            let rawResult: Any?
            do {
                var dispatchedResult: Any?
                try await withScholiumLifecycleDeadline(
                    phase: .bridgeRequest,
                    timeout: lifecyclePolicy.bridgeRequest
                ) { [bridgeDispatcher] in
                    dispatchedResult = try await bridgeDispatcher.dispatch(
                        requestJSON: requestJSON,
                        in: webView
                    )
                }
                rawResult = dispatchedResult
            } catch {
                guard isCurrent(context) else { throw SessionError.staleRequest }
                throw error
            }
            guard isCurrentIdentity(context) else { throw SessionError.staleRequest }
            guard JSONSerialization.isValidJSONObject(rawResult as Any),
                  let resultData = try? JSONSerialization.data(withJSONObject: rawResult as Any),
                  resultData.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes + 512_000,
                  let result = try? JSONDecoder().decode(MarkdownEditorCommandResult.self, from: resultData),
                  result.requestID == request.requestID else {
                throw SessionError.invalidResult
            }
            guard result.accepted else {
                throw SessionError.bridgeRejected(result.error ?? "The Markdown editor rejected the request.")
            }
            let maximumAcceptedGeneration: Int
            if case let .restoreRecovery(snapshot) = operation {
                maximumAcceptedGeneration = snapshot.generation
            } else {
                maximumAcceptedGeneration = request.expectedGeneration + (result.sourceChanged ? 1 : 0)
            }
            guard result.resultingGeneration >= request.expectedGeneration,
                  result.resultingGeneration <= maximumAcceptedGeneration,
                  result.resultingGeneration >= generation else {
                throw SessionError.invalidResult
            }
            let generationBeforeApplyingResult = generation
            if result.sourceChanged {
                guard let text = result.text else { throw SessionError.invalidResult }
                if result.resultingGeneration > generationBeforeApplyingResult {
                    try reconcileMirror(with: text, publish: true)
                } else if text != checkedSource {
                    throw SessionError.invalidResult
                }
            }
            guard markdownEditorSelectionRangesAreValid(
                result.selections,
                forEditorUTF16Length: checkedEditorUTF16Length
            ), result.context?.selections == nil || result.context?.selections == result.selections else {
                throw SessionError.invalidResult
            }
            generation = result.resultingGeneration
            updateInteraction(
                selections: result.selections,
                line: line,
                column: column,
                lineCount: lineCount,
                documentVersion: result.resultingGeneration,
                context: result.context
            )
            if result.sourceChanged,
               result.resultingGeneration > generationBeforeApplyingResult {
                scheduleRecoveryCapture(for: result.resultingGeneration)
            }
            return result
        }
        inFlightRequestTasks[trackingID] = task
        requestBarrier = Task { @MainActor in _ = try? await task.value }
        defer { inFlightRequestTasks[trackingID] = nil }
        return try await task.value
    }

    private func isCurrent(_ context: BridgeRequestContext) -> Bool {
        isCurrentIdentity(context)
            && context.generation == generation
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
              ProcessInfo.processInfo.arguments.contains("--scholium-editor-qa-faults") else {
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

    private func invalidateRequestQueue() {
        requestEpoch &+= 1
        requestBarrier?.cancel()
        requestBarrier = nil
        for task in inFlightRequestTasks.values {
            task.cancel()
        }
        inFlightRequestTasks.removeAll()
    }

    private func cancelScheduledRecoveryCapture() {
        recoveryCaptureToken &+= 1
        recoveryCaptureTask?.cancel()
        recoveryCaptureTask = nil
        scheduledRecoveryCaptureKey = nil
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
           ) {
            return snapshot.ranges
        }
        if let snapshot = recoverySnapshot,
           snapshot.documentID == documentID,
           snapshot.fingerprint == startingFingerprint,
           snapshot.generation == generation,
           snapshot.source == checkedSource,
           markdownEditorSelectionRangesAreValid(
                snapshot.ranges,
                forEditorUTF16Length: checkedEditorUTF16Length
           ) {
            return snapshot.ranges
        }
        return fallbackSelectionSnapshot().ranges
    }

    private func updatePublished<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<MarkdownEditorSession, Value>,
        to value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    private func reconcileMirror(with text: String, publish: Bool) throws {
        guard text != checkedSource else { return }
        let replacement = MarkdownEditorDelta(
            fromUTF16: 0,
            toUTF16: checkedSource.utf16.count,
            insertion: text
        )
        checkedSource = try MarkdownEditorDeltaApplier.apply([replacement], to: checkedSource)
        sourceOffsetMap = EditorSourceOffsetMap(source: checkedSource)
        checkedEditorUTF16Length = sourceOffsetMap.editorUTF16Length
        if publish { sourceChangeHandler?(checkedSource) }
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
              ) else { return nil }
        return MarkdownEditorWireScrollAnchor(
            sourceUTF16Offset: sourceOffset,
            blockUTF16LowerBound: lowerBound,
            blockUTF16UpperBound: upperBound,
            relativeBlockPosition: anchor.relativeBlockPosition,
            fallbackFraction: anchor.fallbackFraction
        )
    }
}
