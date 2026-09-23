import AppKit
import Combine
import Foundation
import ScholiumContracts
import ScholiumEditor

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
    var documentPhase: DocumentPhase = .unavailable
    var errorMessage: String?
    var isLoaded: Bool { if case .ready = documentPhase { true } else { false } }
    var presentedMode: MarkdownEditorMode? {
        if case .ready(let mode) = documentPhase { mode } else { nil }
    }
}

struct MarkdownEditorTextSnapshot: Equatable, Sendable {
    let text: String
    let generation: Int
}

struct MarkdownEditorPersistenceSnapshot: Sendable {
    let text: String
    let generation: Int
    let documentID: String
    let fingerprint: String
    let suspensionID: String?
}

enum MarkdownEditorCommitAcknowledgement: Equatable, Sendable {
    case clean
    case superseded
}

/// A document retains this native text view, its source provenance and Undo
/// history across SwiftUI hosts. DocumentController remains the disk writer.
@MainActor
final class MarkdownEditorSession: NSObject, ObservableObject {
    enum SessionError: LocalizedError {
        case unavailable
        case invalidResult
        case selectionTooLong
        case staleRequest
        case operationRejected(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "The Markdown editor is not ready."
            case .invalidResult: "The Markdown editor could not validate its source."
            case .selectionTooLong: "Select at most 2,000 characters for one source-anchored comment."
            case .staleRequest: "The editor request belonged to a replaced document or session."
            case .operationRejected(let message): message
            }
        }
    }

    let nativeEditor: EditorTextView
    let scrollView: NSScrollView
    let editorDocumentID = UUID().uuidString
    let writingContextChanges = PassthroughSubject<Void, Never>()
    let selectionChanges = PassthroughSubject<Bool, Never>()
    @Published private(set) var presentation = MarkdownEditorPresentationState()
    @Published private(set) var isDirty = false
    @Published private(set) var interactionAvailability: EditorInteractionAvailability?
    @Published private(set) var openingPresentationID = UUID()
    private(set) var context: MarkdownEditorContext?
    private(set) var sessionID = UUID()
    private(set) var documentID = ""
    private(set) var startingFingerprint = ""
    private(set) var generation = 0
    private(set) var checkedSource = ""
    private(set) var line = 1
    private(set) var column = 1
    private(set) var lineCount = 1
    private(set) var preferredDocumentFocusTarget: WindowDocumentFocusTarget?
    private(set) var detachmentSuspensionID: String?
    var sourceOffsetMap = EditorSourceOffsetMap(source: "")
    var commandSemanticCache: (source: String, document: NoteDocument, semantic: MarkdownSemanticDocument)?
    var pendingScrollFraction: Double?
    var pendingScrollAnchor: EditorScrollAnchor?
    var performanceDocumentID = ""
    var onLinkActivation: ((String) -> Void)?
    var onDocumentActivity: (() -> Void)?
    var onScrollFractionChange: ((Double) -> Void)?
    var onScrollAnchorChange: ((EditorScrollAnchor) -> Void)?
    var onNativeSelectionChange: (([MarkdownEditorSelectionRange], NSRect?) -> Void)?

    private var attachmentID: UUID?
    private var committedSource = ""
    private var lastNativeRevision: UInt64 = 0
    private var isLoading = false
    private var isReconciling = false
    private var sourceError: String?
    private var pendingMode: MarkdownEditorMode = .read
    private var pendingWindowPresentation: WindowDocumentPresentationSnapshot?
    private var automaticFocusIsAuthorized = false
    private var retainedSelections: [MarkdownEditorSelectionRange] = []
    private var committedTextSynchronizer: ((String, String) -> Void)?
    private var sourceChangeHandler: (() -> Void)?
    private var detachedSnapshot: MarkdownEditorPersistenceSnapshot?

    var hasAttachedNativeView: Bool { attachmentID != nil }
    var isReady: Bool { true }
    var isLoaded: Bool { presentation.isLoaded }
    var presentedMode: MarkdownEditorMode? { presentation.presentedMode }
    var errorMessage: String? { presentation.errorMessage }
    var isComposing: Bool { nativeEditor.isComposingSource }
    var hasRecoverableBuffer: Bool { isDirty || isComposing || sourceError != nil }
    var hasNonemptySelection: Bool {
        currentValidSelectionRanges().contains(where: \.isNonempty)
    }
    var hasWritingFocus: Bool {
        guard let window = nativeEditor.window, window.isKeyWindow,
            let responder = window.firstResponder as? NSView
        else { return false }
        return responder === nativeEditor || responder.isDescendant(of: nativeEditor)
    }
    var hasDetachedPersistenceSnapshot: Bool {
        guard !hasAttachedNativeView, !isComposing, let detachedSnapshot else { return false }
        return detachedSnapshot.documentID == documentID
            && detachedSnapshot.generation == generation
            && detachedSnapshot.fingerprint == startingFingerprint
            && detachedSnapshot.suspensionID == detachmentSuspensionID
            && detachedSnapshot.text.utf8.elementsEqual(checkedSource.utf8)
    }

    override init() {
        nativeEditor = EditorTextView.makeTextKit2(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            containerSize: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        scrollView = NSScrollView(frame: nativeEditor.frame)
        super.init()
        nativeEditor.applyTheme(.default)
        nativeEditor.minSize = .zero
        nativeEditor.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        nativeEditor.isVerticallyResizable = true
        nativeEditor.isHorizontallyResizable = false
        nativeEditor.autoresizingMask = [.width]
        nativeEditor.typewriterModeEnabled = false
        nativeEditor.viewMode = .reading
        nativeEditor.isSelectable = true
        nativeEditor.setAccessibilityIdentifier("scholium.document.editor")
        nativeEditor.onSourceStateChange = { [weak self] _ in self?.sourceStateChanged() }
        nativeEditor.onSourceEditRejected = { [weak self] message in self?.reportError(message) }
        nativeEditor.onLinkActivation = { [weak self] target in self?.onLinkActivation?(target) }
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.documentView = nativeEditor
        scrollView.contentView.postsBoundsChangedNotifications = true
        nativeEditor.updateContentInset()
        NotificationCenter.default.addObserver(
            self, selector: #selector(selectionDidChange),
            name: NSTextView.didChangeSelectionNotification, object: nativeEditor)
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollDidChange),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @discardableResult
    func attachNativeView() -> UUID {
        let id = UUID()
        attachmentID = id
        detachedSnapshot = nil
        detachmentSuspensionID = nil
        applyInputAvailability()
        if let anchor = pendingScrollAnchor {
            setScrollPosition(anchor: anchor, fallbackFraction: pendingScrollFraction ?? 0)
        } else if let fraction = pendingScrollFraction {
            setScrollFraction(fraction)
        }
        return id
    }

    func isCurrentAttachment(_ id: UUID) -> Bool { attachmentID == id }

    func detachNativeView(attachmentID: UUID) {
        guard self.attachmentID == attachmentID else { return }
        recordNativeScrollPosition()
        self.attachmentID = nil
        automaticFocusIsAuthorized = false
        // Native storage and Undo remain retained. There is no serialization,
        // history reconstruction or process lifetime tied to this host view.
        if !isComposing, let snapshot = try? reconcileNativeSource() {
            let suspension = detachmentSuspensionID ?? UUID().uuidString
            detachmentSuspensionID = suspension
            detachedSnapshot = MarkdownEditorPersistenceSnapshot(
                text: snapshot.text,
                generation: snapshot.generation, documentID: documentID,
                fingerprint: startingFingerprint, suspensionID: suspension)
        }
        applyInputAvailability()
    }

    func shutdownDetachedSession() {
        guard !hasAttachedNativeView else { return }
        nativeEditor.onSourceStateChange = nil
        nativeEditor.onSourceEditRejected = nil
        nativeEditor.onLinkActivation = nil
        NotificationCenter.default.removeObserver(self)
        committedTextSynchronizer = nil
        sourceChangeHandler = nil
    }

    func prepareOpeningPresentation() { openingPresentationID = UUID() }

    func sourceForViewAttachment(proposedSource: String, documentID proposedDocumentID: String) -> String {
        documentID == proposedDocumentID && isLoaded ? checkedSource : proposedSource
    }

    func loadDocument(
        _ source: String, documentID: String, mode: MarkdownEditorMode,
        initialSourceRange: Range<Int>? = nil
    ) {
        guard !isComposing else {
            reportError("Finish the current input before replacing this document.")
            return
        }
        isLoading = true
        defer { isLoading = false }
        presentation = .init(documentPhase: .loading)
        do {
            try nativeEditor.loadExactUTF8(Data(source.utf8))
            self.documentID = documentID
            sessionID = UUID()
            checkedSource = source
            commandSemanticCache = nil
            committedSource = source
            startingFingerprint = DocumentFingerprint(content: source).sha256
            sourceOffsetMap = EditorSourceOffsetMap(source: source)
            generation = 0
            lastNativeRevision = nativeEditor.sourceState.revision
            detachedSnapshot = nil
            detachmentSuspensionID = nil
            sourceError = nil
            isDirty = false
            pendingMode = mode
            nativeEditor.viewMode = mode == .read ? .reading : .edit
            applyInputAvailability()
            presentation = .init(documentPhase: .ready(mode))
            if let initialSourceRange {
                revealSourceRange(fromUTF16: initialSourceRange.lowerBound, toUTF16: initialSourceRange.upperBound)
            } else if let restored = pendingWindowPresentation,
                restored.sourceFingerprint == startingFingerprint
            {
                let ranges = restored.selections.map {
                    NSValue(
                        range: NSRange(
                            location: min($0.anchor, $0.head), length: abs($0.head - $0.anchor)))
                }
                nativeEditor.selectedRanges = ranges
                preferredDocumentFocusTarget = restored.focusTarget
            } else {
                let body = NoteDocument(relativePath: "", rawContent: source).bodyUTF16Offset
                let caret =
                    sourceOffsetMap.editorUTF16Offset(forSourceUTF16Offset: body)
                    ?? sourceOffsetMap.editorUTF16Offset(forSourceUTF16Offset: source.hasPrefix("\u{FEFF}") ? 1 : 0) ?? 0
                nativeEditor.setSelectedRange(NSRange(location: caret, length: 0))
            }
            pendingWindowPresentation = nil
            updateNativeInteraction()
            committedTextSynchronizer?(source, startingFingerprint)
        } catch {
            presentation = .init(documentPhase: .unavailable, errorMessage: error.localizedDescription)
        }
    }

    func setMode(_ mode: MarkdownEditorMode) {
        pendingMode = mode
        guard isLoaded, !isComposing else { return }
        do {
            _ = try reconcileNativeSource()
            PerformanceProbe.shared.markEditorModeLayoutStarted(mode: mode)
            nativeEditor.viewMode = mode == .read ? .reading : .edit
            applyInputAvailability()
            presentation.documentPhase = .ready(mode)
            PerformanceProbe.shared.markEditorModeApplied(documentID: performanceDocumentID, mode: mode)
            scrollView.superview?.needsLayout = true
            nativeEditor.setAccessibilityLabel(ScholiumL10n.string(mode == .read ? "Document, Reading" : "Document, Editing"))
            updateNativeInteraction()
        } catch { reportError(error.localizedDescription) }
    }

    func setDocumentTitle(_ title: String) { scrollView.setAccessibilityLabel(title) }

    private func applyInputAvailability() {
        nativeEditor.isEditable = pendingMode == .edit && detachmentSuspensionID == nil
        nativeEditor.isSelectable = true
    }

    func reportError(_ message: String) { presentation.errorMessage = message }

    func retryUnavailablePresentation() {
        guard !isLoaded, !documentID.isEmpty else { return }
        loadDocument(checkedSource, documentID: documentID, mode: pendingMode)
    }

    /// Synchronous validation binds source and generation to one main-actor turn.
    /// Provisional IME input never replaces the last checked source.
    @discardableResult
    func reconcileNativeSource() throws -> MarkdownEditorTextSnapshot {
        guard isLoaded, !isComposing else { throw SessionError.unavailable }
        guard !isReconciling else { return .init(text: checkedSource, generation: generation) }
        isReconciling = true
        defer { isReconciling = false }
        let bytes = try nativeEditor.exactUTF8ForSaving()
        let text = String(decoding: bytes, as: UTF8.self)
        let changed = !text.utf8.elementsEqual(checkedSource.utf8)
        let revision = nativeEditor.sourceState.revision
        if changed {
            let advance = revision >= lastNativeRevision ? revision - lastNativeRevision : 1
            generation += max(1, Int(clamping: advance))
            checkedSource = text
            sourceOffsetMap = EditorSourceOffsetMap(source: text)
            isDirty = !text.utf8.elementsEqual(committedSource.utf8)
            detachedSnapshot = nil
            writingContextChanges.send()
            sourceChangeHandler?()
            onDocumentActivity?()
        }
        lastNativeRevision = revision
        if let sourceError, presentation.errorMessage == sourceError { presentation.errorMessage = nil }
        sourceError = nil
        updateNativeInteraction()
        return .init(text: text, generation: generation)
    }

    private func sourceStateChanged() {
        guard !isLoading, isLoaded else { return }
        if isComposing {
            updateNativeInteraction()
            writingContextChanges.send()
            return
        }
        do { _ = try reconcileNativeSource() } catch {
            sourceError = error.localizedDescription
            reportError(error.localizedDescription)
        }
        if presentedMode != pendingMode { setMode(pendingMode) }
    }

    @objc private func selectionDidChange(_ notification: Notification) {
        guard !isLoading, isLoaded else { return }
        updateNativeInteraction()
    }

    func currentValidSelectionRanges() -> [MarkdownEditorSelectionRange] {
        let ranges = nativeEditor.selectedRanges.compactMap { value -> MarkdownEditorSelectionRange? in
            let range = value.rangeValue
            guard range.location != NSNotFound, range.location >= 0, range.length >= 0,
                range.location <= (nativeEditor.rawSource as NSString).length,
                range.length <= (nativeEditor.rawSource as NSString).length - range.location
            else { return nil }
            return MarkdownEditorSelectionRange(anchor: range.location, head: range.upperBound)
        }
        guard ranges.count == nativeEditor.selectedRanges.count,
            markdownEditorSelectionRangesAreValid(ranges, forProjectedText: nativeEditor.rawSource)
        else { return [] }
        return ranges
    }

    func updateNativeInteraction() {
        let ranges = currentValidSelectionRanges()
        let previous = retainedSelections
        retainedSelections = ranges
        let nativeContext = nativeContext()
        context = nativeContext
        let availability = EditorInteractionAvailability(context: nativeContext)
        if interactionAvailability != availability { interactionAvailability = availability }
        let position = min(ranges.first?.head ?? 0, (nativeEditor.rawSource as NSString).length)
        let prefix = (nativeEditor.rawSource as NSString).substring(to: position)
        line = prefix.utf16.reduce(into: 1) { if $1 == 10 { $0 += 1 } }
        column =
            (prefix as NSString).length
            - ((prefix as NSString).range(of: "\n", options: .backwards).location == NSNotFound
                ? 0 : (prefix as NSString).range(of: "\n", options: .backwards).upperBound) + 1
        lineCount = nativeEditor.rawSource.utf16.reduce(into: 1) { if $1 == 10 { $0 += 1 } }
        if previous != ranges {
            if hasWritingFocus { preferredDocumentFocusTarget = .editor }
            writingContextChanges.send()
            selectionChanges.send(hasNonemptySelection)
            onNativeSelectionChange?(ranges, nativeSelectionRect())
        }
    }

    func nativeSelectionRect() -> NSRect? {
        guard nativeEditor.window != nil, nativeEditor.selectedRange().length > 0 else { return nil }
        let screen = nativeEditor.firstRect(forCharacterRange: nativeEditor.selectedRange(), actualRange: nil)
        guard let window = nativeEditor.window else { return nil }
        return nativeEditor.convert(window.convertFromScreen(screen), from: nil)
    }

    func currentText(for expectedDocumentID: String? = nil) async throws -> String {
        try await currentTextSnapshot(for: expectedDocumentID).text
    }

    func currentTextSnapshot(for expectedDocumentID: String? = nil) async throws -> MarkdownEditorTextSnapshot {
        try Task.checkCancellation()
        guard expectedDocumentID == nil || expectedDocumentID == documentID else { throw SessionError.staleRequest }
        return try reconcileNativeSource()
    }

    func waitUntilLoadedForSave(maximumWait: Duration = .seconds(6)) async throws -> Bool {
        try Task.checkCancellation()
        return isLoaded && !isComposing
    }

    func captureStateForViewReconstruction(suspendForDetachment: Bool = false) async throws {
        let snapshot = try reconcileNativeSource()
        recordNativeScrollPosition()
        if suspendForDetachment {
            let suspension = detachmentSuspensionID ?? UUID().uuidString
            detachmentSuspensionID = suspension
            detachedSnapshot = .init(
                text: snapshot.text, generation: snapshot.generation,
                documentID: documentID, fingerprint: startingFingerprint, suspensionID: suspension)
            applyInputAvailability()
        }
    }

    func resumeAfterDetachment(suspensionID: String) async throws {
        guard suspensionID == detachmentSuspensionID else { return }
        detachmentSuspensionID = nil
        detachedSnapshot = nil
        applyInputAvailability()
    }

    func persistenceSnapshot(expectedRevision: DocumentFingerprint) async throws -> MarkdownEditorPersistenceSnapshot {
        guard startingFingerprint == expectedRevision.sha256 else { throw SessionError.staleRequest }
        let snapshot = try reconcileNativeSource()
        return .init(
            text: snapshot.text, generation: snapshot.generation, documentID: documentID,
            fingerprint: startingFingerprint, suspensionID: detachmentSuspensionID)
    }

    func acknowledgePersistenceSnapshot(
        _ snapshot: MarkdownEditorPersistenceSnapshot,
        committedText: String, fingerprint: DocumentFingerprint
    ) async throws -> MarkdownEditorCommitAcknowledgement {
        guard snapshot.documentID == documentID, snapshot.fingerprint == startingFingerprint,
            snapshot.generation <= generation
        else { throw SessionError.staleRequest }
        return try await acknowledgeCommittedSnapshot(
            expectedText: snapshot.text, committedText: committedText,
            fingerprint: fingerprint, documentID: snapshot.documentID)
    }

    func acknowledgeCommittedSnapshot(
        expectedText: String, committedText: String,
        fingerprint: DocumentFingerprint, documentID expectedDocumentID: String
    ) async throws -> MarkdownEditorCommitAcknowledgement {
        guard documentID == expectedDocumentID, DocumentFingerprint(content: committedText) == fingerprint,
            expectedText.utf8.elementsEqual(committedText.utf8)
        else { throw SessionError.invalidResult }
        let current = try reconcileNativeSource()
        committedSource = committedText
        startingFingerprint = fingerprint.sha256
        let superseded = !current.text.utf8.elementsEqual(committedText.utf8)
        isDirty = superseded
        if let suspension = detachmentSuspensionID {
            detachedSnapshot = .init(
                text: current.text, generation: current.generation,
                documentID: documentID, fingerprint: fingerprint.sha256, suspensionID: suspension)
        }
        committedTextSynchronizer?(current.text, fingerprint.sha256)
        return superseded ? .superseded : .clean
    }

    func installCommittedTextSynchronizer(_ synchronizer: @escaping (String, String) -> Void) {
        committedTextSynchronizer = synchronizer
    }
    func removeCommittedTextSynchronizer() { committedTextSynchronizer = nil }
    func installSourceChangeHandler(_ handler: @escaping () -> Void) { sourceChangeHandler = handler }
    func removeSourceChangeHandler() { sourceChangeHandler = nil }

    @discardableResult
    func restoreWindowPresentation(_ snapshot: WindowDocumentPresentationSnapshot, source: String) -> Bool {
        guard let projection = try? ExactSourceProjection(utf8: Data(source.utf8)) else { return false }
        let ranges = snapshot.selections.map { MarkdownEditorSelectionRange(anchor: $0.anchor, head: $0.head) }
        guard snapshot.coordinateSpace == WindowDocumentPresentationSnapshot.nativeCoordinateSpace,
            snapshot.sourceFingerprint == DocumentFingerprint(content: source).sha256,
            markdownEditorSelectionRangesAreValid(ranges, forProjectedText: projection.projectedText)
        else { return false }
        pendingWindowPresentation = snapshot
        preferredDocumentFocusTarget = snapshot.focusTarget
        return true
    }

    func windowPresentationSnapshot(scrollFraction: Double) -> WindowDocumentPresentationSnapshot {
        guard isLoaded, !isDirty, !isComposing else { return .init(scrollFraction: scrollFraction) }
        return .init(
            scrollFraction: scrollFraction,
            sourceFingerprint: DocumentFingerprint(content: checkedSource).sha256,
            selections: currentValidSelectionRanges().map { .init(anchor: $0.anchor, head: $0.head) },
            focusTarget: preferredDocumentFocusTarget)
    }

    func goToLine(_ line: Int, focusesEditor: Bool = true) {
        guard isLoaded, !isComposing else { return }
        let text = nativeEditor.rawSource as NSString
        var offset = 0
        for _ in 1..<max(1, line) {
            guard offset < text.length else { break }
            offset = text.lineRange(for: NSRange(location: offset, length: 0)).upperBound
        }
        nativeEditor.setSelectedRange(NSRange(location: min(offset, text.length), length: 0))
        nativeEditor.scrollRangeToVisible(nativeEditor.selectedRange())
        if focusesEditor { focus() }
    }

    func revealSourceRange(fromUTF16: Int, toUTF16: Int) {
        guard isLoaded, !isComposing, fromUTF16 >= 0, fromUTF16 <= toUTF16,
            let projection = try? ExactSourceProjection(utf8: Data(checkedSource.utf8)),
            let range = try? projection.projectedUTF16Range(
                forSourceUTF16Range:
                    NSRange(location: fromUTF16, length: toUTF16 - fromUTF16))
        else { return }
        nativeEditor.setSelectedRange(range)
        nativeEditor.scrollRangeToVisible(nativeEditor.selectedRange())
        preferredDocumentFocusTarget = .editor
    }

    func revealSourceLocation(_ request: DocumentSourceLocationRequest) async throws {
        let snapshot = try reconcileNativeSource()
        if let expected = request.sourceFingerprint, DocumentFingerprint(content: snapshot.text).sha256 != expected {
            throw DocumentSourceLocationFailure.sourceChanged
        }
        if let range = request.range {
            guard range.utf16LowerBound >= 0, range.utf16UpperBound >= range.utf16LowerBound,
                let projection = try? ExactSourceProjection(utf8: Data(snapshot.text.utf8)),
                (try? projection.projectedUTF16Range(
                    forSourceUTF16Range:
                        NSRange(location: range.utf16LowerBound, length: range.utf16UpperBound - range.utf16LowerBound))) != nil
            else { throw SessionError.invalidResult }
            revealSourceRange(fromUTF16: range.utf16LowerBound, toUTF16: range.utf16UpperBound)
        } else if let line = request.line, line > 0 {
            goToLine(line)
        } else {
            throw SessionError.invalidResult
        }
        focus()
    }

    func prepareReadSelection(_ range: Range<Int>) {
        revealSourceRange(fromUTF16: range.lowerBound, toUTF16: range.upperBound)
    }

    func focus() {
        preferredDocumentFocusTarget = .editor
        automaticFocusIsAuthorized = true
        guard hasAttachedNativeView, !nativeEditor.isHiddenOrHasHiddenAncestor else { return }
        nativeEditor.window?.makeFirstResponder(nativeEditor)
    }
    func focusPreferred() { focus() }
    func authorizeAutomaticFocus(target: WindowDocumentFocusTarget? = nil) {
        if let target { preferredDocumentFocusTarget = target }
        automaticFocusIsAuthorized = true
    }
    func focusAndWait() async throws {
        guard isLoaded, hasAttachedNativeView, nativeEditor.window != nil else { throw SessionError.unavailable }
        focus()
    }
    func resignFocusAndWait() async {
        automaticFocusIsAuthorized = false
        if hasWritingFocus { nativeEditor.window?.makeFirstResponder(nil) }
    }
    func activateAttachedView() {
        if automaticFocusIsAuthorized { focusPreferred() }
    }

    @objc private func scrollDidChange(_ notification: Notification) {
        guard !isLoading, hasAttachedNativeView else { return }
        recordNativeScrollPosition()
    }
    private var scrollFraction: Double {
        let extent = max(0, nativeEditor.bounds.height - scrollView.contentView.bounds.height)
        return extent > 0 ? min(1, max(0, scrollView.contentView.bounds.minY / extent)) : 0
    }
    private func recordNativeScrollPosition() {
        pendingScrollFraction = scrollFraction
        onScrollFractionChange?(scrollFraction)
        guard let anchor = makeScrollAnchor() else { return }
        pendingScrollAnchor = anchor
        onScrollAnchorChange?(anchor)
    }
    private func makeScrollAnchor() -> EditorScrollAnchor? {
        guard isLoaded, !isComposing else { return nil }
        let text = nativeEditor.rawSource as NSString
        let point = NSPoint(
            x: nativeEditor.textContainerOrigin.x + 1,
            y: scrollView.contentView.bounds.minY + 1)
        let offset = min(text.length, nativeEditor.characterIndexForInsertion(at: point))
        let fragment = nativeFragment(at: offset, ensureLayout: false)
        let paragraph = fragment?.range ?? text.lineRange(for: NSRange(location: offset, length: 0))
        let relative =
            fragment.map { value in
                min(1, max(0, (scrollView.contentView.bounds.minY - value.frame.minY) / max(1, value.frame.height)))
            } ?? 0
        guard let source = sourceOffsetMap.sourceUTF16Offset(forEditorUTF16Offset: offset),
            let lower = sourceOffsetMap.sourceUTF16Offset(forEditorUTF16Offset: paragraph.location),
            let upper = sourceOffsetMap.sourceUTF16Offset(forEditorUTF16Offset: paragraph.upperBound)
        else { return nil }
        return .init(
            sourceFingerprint: DocumentFingerprint(content: checkedSource).sha256,
            sourceUTF16Offset: source, blockUTF16LowerBound: lower, blockUTF16UpperBound: upper,
            relativeBlockPosition: relative, fallbackFraction: scrollFraction)
    }
    func currentScrollAnchor() async throws -> EditorScrollAnchor? {
        _ = try reconcileNativeSource()
        let anchor = makeScrollAnchor()
        pendingScrollAnchor = anchor
        return anchor
    }
    func setScrollFraction(_ fraction: Double) {
        guard fraction.isFinite else { return }
        let value = min(1, max(0, fraction))
        pendingScrollFraction = value
        let extent = max(0, nativeEditor.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: extent * value))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    func setScrollPosition(anchor: EditorScrollAnchor?, fallbackFraction: Double) {
        guard let anchor, anchor.sourceFingerprint == DocumentFingerprint(content: checkedSource).sha256,
            anchor.isValid(forUTF16Length: checkedSource.utf16.count),
            let projected = sourceOffsetMap.editorUTF16Offset(forSourceUTF16Offset: anchor.sourceUTF16Offset)
        else {
            pendingScrollAnchor = nil
            setScrollFraction(fallbackFraction)
            return
        }
        pendingScrollAnchor = anchor
        pendingScrollFraction = min(1, max(0, fallbackFraction))
        if let fragment = nativeFragment(at: projected, ensureLayout: true) {
            let y = fragment.frame.minY + fragment.frame.height * anchor.relativeBlockPosition
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            setScrollFraction(fallbackFraction)
        }
    }

    private func nativeFragment(at offset: Int, ensureLayout: Bool) -> (range: NSRange, frame: NSRect)? {
        guard let layout = nativeEditor.textLayoutManager,
            let location = layout.location(layout.documentRange.location, offsetBy: offset),
            let range = NSTextRange(location: location, end: location)
        else { return nil }
        if ensureLayout { layout.ensureLayout(for: range) }
        guard let fragment = layout.textLayoutFragment(for: location) else { return nil }
        let lower = layout.offset(from: layout.documentRange.location, to: fragment.rangeInElement.location)
        let upper = layout.offset(from: layout.documentRange.location, to: fragment.rangeInElement.endLocation)
        guard lower >= 0, upper >= lower, upper <= (nativeEditor.rawSource as NSString).length else { return nil }
        let origin = nativeEditor.textContainerOrigin
        return (
            NSRange(location: lower, length: upper - lower),
            fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
        )
    }
    func recordScrollFraction(_ fraction: Double) { pendingScrollFraction = min(1, max(0, fraction)) }
    func retainedScrollFraction(fallback: Double) -> Double { pendingScrollFraction ?? min(1, max(0, fallback)) }
    var retainedScrollAnchor: EditorScrollAnchor? { pendingScrollAnchor }
}
