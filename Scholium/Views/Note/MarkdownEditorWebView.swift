import ScholiumContracts
import SwiftUI
import WebKit

private final class WindowAttachedWebView: WKWebView {
    var onFirstWindowAttachment: (() -> Void)?
    weak var editorSession: MarkdownEditorSession?
    var onRequestComment: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let action = onFirstWindowAttachment else { return }
        onFirstWindowAttachment = nil
        action()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        for item in menu.items where item.identifier?.rawValue.hasPrefix("scholium.editor.") == true {
            menu.removeItem(item)
        }
        guard let editorSession else { return menu }
        let available = Set(editorSession.context?.availableCommands ?? [])
        var addedAction = false
        for (title, command) in [
            ("Bold", MarkdownEditorCommand.bold),
            ("Emphasis", .emphasis),
            ("Link", .standardLink),
            ("Toggle Task", .toggleTask),
        ] where available.contains(command) {
            if !addedAction { menu.addItem(.separator()) }
            menu.addItem(editorMenuItem(title, command: command))
            addedAction = true
        }

        let tableCommands: [(String, MarkdownEditorCommand)] = [
            ("Insert Row Before", .tableInsertRowBefore),
            ("Insert Row After", .tableInsertRowAfter),
            ("Delete Row", .tableDeleteRow),
            ("Insert Column Before", .tableInsertColumnBefore),
            ("Insert Column After", .tableInsertColumnAfter),
            ("Delete Column", .tableDeleteColumn),
            ("Align Left", .tableAlignLeft),
            ("Align Center", .tableAlignCenter),
            ("Align Right", .tableAlignRight),
        ].filter { available.contains($0.1) }
        if !tableCommands.isEmpty {
            if !addedAction { menu.addItem(.separator()) }
            let submenu = NSMenu(title: "Table")
            tableCommands.forEach { submenu.addItem(editorMenuItem($0.0, command: $0.1)) }
            let item = NSMenuItem(title: "Table", action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.table")
            item.submenu = submenu
            menu.addItem(item)
            addedAction = true
        }
        if onRequestComment != nil, editorSession.context?.composing != true {
            if !addedAction { menu.addItem(.separator()) }
            let item = NSMenuItem(title: "Add Comment…", action: #selector(requestComment(_:)), keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.comment")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    private func editorMenuItem(_ title: String, command: MarkdownEditorCommand) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performEditorCommand(_:)), keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.\(command.rawValue)")
        item.representedObject = command.rawValue
        item.target = self
        return item
    }

    @objc private func performEditorCommand(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let command = MarkdownEditorCommand(rawValue: rawValue),
              let editorSession else { return }
        Task { @MainActor in
            do {
                try await editorSession.perform(command)
            } catch {
                editorSession.reportError(error.localizedDescription)
            }
        }
    }

    @objc private func requestComment(_ sender: NSMenuItem) {
        onRequestComment?()
    }
}

enum NotePresentationMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case read
    case livePreview
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .read: "Read"
        case .livePreview: "Live Preview"
        case .source: "Source"
        }
    }

    var symbol: String {
        switch self {
        case .read: "book"
        case .livePreview: "text.page.badge.magnifyingglass"
        case .source: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct EditorLinkCompletion: Codable, Hashable, Sendable {
    let label: String
    let insertion: String
    let detail: String
    let path: String
    let isAmbiguous: Bool
}

struct MarkdownEditorCommentAnnotation: Codable, Hashable, Sendable {
    let id: UUID
    let from: Int
    let to: Int
    let comment: String
    let resolved: Bool
}

private struct EditorBridgeChange: Codable {
    let from: Int
    let to: Int
    let insert: String
}

private struct EditorBridgeMessage: Codable {
    let type: String
    let protocolVersion: Int?
    let sessionID: String?
    let documentID: String?
    let startingFingerprint: String?
    let documentVersion: Int?
    let baseGeneration: Int?
    let resultingGeneration: Int?
    let changes: [EditorBridgeChange]?
    let dirty: Bool?
    let line: Int?
    let column: Int?
    let lineCount: Int?
    let message: String?
    let editorReady: Bool?
    let scrollFraction: Double?
    let commentID: String?
    let target: String?
    let context: MarkdownEditorContext?
}

@MainActor
final class MarkdownEditorSession: NSObject, ObservableObject {
    enum SessionError: LocalizedError {
        case unavailable
        case invalidResult
        case selectionTooLong
        case bridgeRejected(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: "The Markdown editor is not ready."
            case .invalidResult: "The Markdown editor returned an invalid document."
            case .selectionTooLong: "Select at most 2,000 characters for one source-anchored comment."
            case .bridgeRejected(let message): message
            }
        }
    }

    @Published private(set) var isReady = false
    @Published private(set) var isLoaded = false
    @Published private(set) var isDirty = false
    @Published private(set) var line = 1
    @Published private(set) var column = 1
    @Published private(set) var lineCount = 1
    @Published private(set) var errorMessage: String?
    @Published private(set) var context: MarkdownEditorContext?
    private(set) var sessionID = UUID()
    private(set) var documentID = ""
    private(set) var startingFingerprint = ""
    private(set) var generation = 0

    private var webView: WKWebView?
    private var pendingSource: String?
    private var pendingDocumentID = ""
    private var pendingMode: NotePresentationMode = .livePreview
    private var pendingUserCSS = ""
    private var pendingLine: Int?
    private var pendingLinkCompletions: [EditorLinkCompletion] = []
    private var pendingResearcherComments: [MarkdownEditorCommentAnnotation] = []
    private var pendingScrollFraction: Double = 0
    private var startupTask: Task<Void, Never>?
    private var recoveryCaptureTask: Task<Void, Never>?
    private var requestBarrier: Task<Void, Never>?
    private var committedTextSynchronizer: ((String, String) -> Void)?
    private var sourceChangeHandler: ((String) -> Void)?
    private var checkedSource = ""
    private var recoverySnapshot: MarkdownEditorRecoverySnapshot?
    private var lastKnownSelections: [MarkdownEditorSelectionRange] = []
    #if DEBUG
    private static let qaTerminationNotification = Notification.Name(
        "com.kbmanager.qa.simulate-editor-process-termination"
    )
    private var qaTerminationObserverInstalled = false
    #endif
    var hasAttachedWebView: Bool { webView != nil }

    override init() {
        super.init()
    }

    #if DEBUG
    struct TestingAccessibilitySnapshot: Decodable, Sendable {
        let contentEditableCount: Int
        let textboxCount: Int
        let label: String
        let multiline: String
        let hasValueText: Bool
        let spellcheck: String
    }

    @discardableResult
    func testingSimulateWebContentProcessTermination() -> Bool {
        guard let webView,
              let coordinator = webView.navigationDelegate as? MarkdownEditorWebView.Coordinator else {
            return false
        }
        coordinator.webViewWebContentProcessDidTerminate(webView)
        return true
    }

    func testingAccessibilitySnapshot() async throws -> TestingAccessibilitySnapshot {
        guard let webView else { throw SessionError.unavailable }
        let rawResult = try await webView.callAsyncJavaScript(
            """
            const editable = document.querySelectorAll('[contenteditable="true"]');
            const textboxes = document.querySelectorAll('[role="textbox"]');
            const content = editable[0];
            return {
                contentEditableCount: editable.length,
                textboxCount: textboxes.length,
                label: content?.getAttribute('aria-label') || '',
                multiline: content?.getAttribute('aria-multiline') || '',
                hasValueText: content?.hasAttribute('aria-valuetext') || false,
                spellcheck: content?.getAttribute('spellcheck') || ''
            };
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        guard JSONSerialization.isValidJSONObject(rawResult as Any),
              let data = try? JSONSerialization.data(withJSONObject: rawResult as Any),
              let snapshot = try? JSONDecoder().decode(TestingAccessibilitySnapshot.self, from: data) else {
            throw SessionError.invalidResult
        }
        return snapshot
    }

    #endif

    fileprivate func attach(_ webView: WKWebView) {
        self.webView = webView
        sessionID = UUID()
        isReady = false
        isLoaded = false
        errorMessage = nil
        recoverySnapshot = nil
        requestBarrier = nil
        installQATerminationObserverIfEnabled()
        startupTask?.cancel()
        startupTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, !self.isReady else { return }
            self.reportError("Live Preview did not finish starting.")
        }
    }

    fileprivate func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        startupTask?.cancel()
        recoveryCaptureTask?.cancel()
        self.webView = nil
        isReady = false
        isLoaded = false
        removeQATerminationObserver()
    }

    fileprivate func editorBecameReady() {
        startupTask?.cancel()
        isReady = true
        flushPendingState()
    }

    fileprivate func updateState(dirty: Bool?, line: Int?, column: Int?, lineCount: Int?) {
        if let dirty { isDirty = dirty }
        if let line { self.line = line }
        if let column { self.column = column }
        if let lineCount { self.lineCount = lineCount }
    }

    fileprivate func updateContext(_ context: MarkdownEditorContext) {
        self.context = context
        lastKnownSelections = context.selections
    }

    fileprivate func reportError(_ message: String) {
        startupTask?.cancel()
        errorMessage = message
        isLoaded = false
    }

    func loadDocument(
        _ source: String,
        documentID: String,
        mode: NotePresentationMode,
        preservingRecovery: Bool = false
    ) {
        if !preservingRecovery {
            recoverySnapshot = nil
            lastKnownSelections = []
        }
        pendingSource = source
        pendingDocumentID = documentID
        self.documentID = documentID
        startingFingerprint = DocumentFingerprint(content: source).sha256
        checkedSource = source
        generation = 0
        pendingMode = mode
        isLoaded = false
        isDirty = false
        errorMessage = nil
        flushPendingState()
    }

    func setMode(_ mode: NotePresentationMode) {
        guard mode != .read else { return }
        pendingMode = mode
        guard isReady, isLoaded, let webView else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await send(.setMode(mode), in: webView)
            } catch {
                let message = "The document mode change was not applied because the editor changed during text composition."
                errorMessage = message
                _ = try? await send(.announceStatus(message), in: webView)
            }
        }
    }

    func setUserCSS(_ css: String) {
        pendingUserCSS = css
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.setUserCSS(css), in: webView)
        }
    }

    func goToLine(_ line: Int) {
        pendingLine = max(1, line)
        flushPendingLine()
    }

    func setScrollFraction(_ fraction: Double) {
        pendingScrollFraction = min(1, max(0, fraction))
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setScrollFraction(pendingScrollFraction), in: webView)
        }
    }

    func setLinkCompletions(_ candidates: [EditorLinkCompletion]) {
        pendingLinkCompletions = candidates
        guard isReady, let webView else { return }
        Task {
            _ = try? await send(.setLinkCompletions(candidates), in: webView)
        }
    }

    func setResearcherComments(_ comments: [ResearcherComment], in source: String) {
        let fingerprint = DocumentFingerprint(content: source)
        pendingResearcherComments = comments.compactMap { comment in
            guard let anchor = comment.anchor,
                  anchor.state == .attached,
                  anchor.fingerprint == fingerprint,
                  let from = Self.editorUTF16Offset(
                    forSourceUTF16Offset: anchor.utf16Range.lowerBound,
                    in: source
                  ),
                  let to = Self.editorUTF16Offset(
                    forSourceUTF16Offset: anchor.utf16Range.upperBound,
                    in: source
                  ),
                  to > from else { return nil }
            return MarkdownEditorCommentAnnotation(
                id: comment.id,
                from: from,
                to: to,
                comment: String(comment.text.prefix(500)),
                resolved: comment.resolvedAt != nil
            )
        }
        guard isReady, isLoaded, let webView else { return }
        Task {
            _ = try? await send(.setResearcherComments(pendingResearcherComments), in: webView)
        }
    }

    func currentText(for expectedDocumentID: String? = nil) async throws -> String {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let result = try await send(.queryText, in: webView)
        guard let text = result.text else { throw SessionError.invalidResult }
        try reconcileMirror(with: text, publish: true)
        return checkedSource
    }

    func currentSelection(
        for expectedDocumentID: String? = nil,
        in source: String? = nil
    ) async throws -> MarkdownReviewSelection? {
        guard expectedDocumentID == nil || expectedDocumentID == documentID,
              isReady, isLoaded, let webView else { throw SessionError.unavailable }
        let result = try await send(.querySelection, in: webView)
        guard let range = result.selection?.ranges.first else { return nil }
        let editorLower = min(range.anchor, range.head)
        let editorUpper = max(range.anchor, range.head)
        guard editorUpper > editorLower else { return nil }
        let exactSource = source ?? checkedSource
        guard let lower = Self.sourceUTF16Offset(forEditorUTF16Offset: editorLower, in: exactSource),
              let upper = Self.sourceUTF16Offset(forEditorUTF16Offset: editorUpper, in: exactSource),
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
        _ = try await send(
            .synchronizeCommittedText(
                expected: expectedText,
                committed: committedText,
                fingerprint: fingerprint.sha256
            ),
            in: webView
        )
        guard expectedDocumentID == documentID else { return false }
        try reconcileMirror(with: committedText, publish: false)
        startingFingerprint = fingerprint.sha256
        isDirty = false
        committedTextSynchronizer?(committedText, fingerprint.sha256)
        return true
    }

    fileprivate func installCommittedTextSynchronizer(
        _ synchronizer: @escaping (String, String) -> Void
    ) {
        committedTextSynchronizer = synchronizer
    }

    fileprivate func removeCommittedTextSynchronizer() {
        committedTextSynchronizer = nil
    }

    fileprivate func installSourceChangeHandler(_ handler: @escaping (String) -> Void) {
        sourceChangeHandler = handler
    }

    fileprivate func removeSourceChangeHandler() {
        sourceChangeHandler = nil
    }

    func markClean() {
        isDirty = false
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

    func perform(_ command: MarkdownEditorCommand, argument: String? = nil) async throws {
        guard isReady, isLoaded, let webView else { throw SessionError.unavailable }
        _ = try await send(.command(command, argument: argument), in: webView)
    }

    fileprivate func acceptEditorChanges(
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
        for raw in rawChanges {
            guard raw.from >= 0, raw.to >= raw.from else { return nil }
            insertedUTF16Count += raw.insert.utf16.count
            guard insertedUTF16Count <= 2_000_000,
                  let from = Self.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.from,
                    in: sourceBeforeChanges
                  ),
                  let to = Self.sourceUTF16Offset(
                    forEditorUTF16Offset: raw.to,
                    in: sourceBeforeChanges
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
        checkedSource = nextSource
        generation = resultingGeneration
        isDirty = true
        sourceChangeHandler?(nextSource)
        scheduleRecoveryCapture()
        return nextSource
    }

    fileprivate func webContentProcessTerminated() {
        recoveryCaptureTask?.cancel()
        if recoverySnapshot?.generation != generation || recoverySnapshot?.source != checkedSource {
            recoverySnapshot = MarkdownEditorRecoverySnapshot(
                documentID: documentID,
                fingerprint: startingFingerprint,
                generation: generation,
                ranges: lastKnownSelections,
                source: checkedSource,
                stateJSON: nil,
                undoHistoryPreserved: false,
                dirty: isDirty
            )
        }
        pendingSource = checkedSource
        pendingDocumentID = documentID
        isReady = false
        isLoaded = false
    }

    private func scheduleRecoveryCapture() {
        recoveryCaptureTask?.cancel()
        recoveryCaptureTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, self.isReady, self.isLoaded,
                  let webView = self.webView else { return }
            guard let result = try? await self.send(.captureRecovery, in: webView),
                  let snapshot = result.recovery,
                  snapshot.documentID == self.documentID,
                  snapshot.fingerprint == self.startingFingerprint,
                  snapshot.generation == self.generation,
                  snapshot.source == self.checkedSource else { return }
            self.recoverySnapshot = snapshot
            self.lastKnownSelections = snapshot.ranges
        }
    }

    private func flushPendingState() {
        guard isReady, let source = pendingSource, let webView else { return }
        pendingSource = nil
        let mode = pendingMode
        let documentID = pendingDocumentID
        Task {
            do {
                let matchingRecovery = recoverySnapshot.flatMap { snapshot in
                    snapshot.documentID == documentID && snapshot.source == source ? snapshot : nil
                }
                startingFingerprint = matchingRecovery?.fingerprint
                    ?? DocumentFingerprint(content: source).sha256
                checkedSource = source
                generation = 0
                _ = try await send(
                    .initialize(text: source, mode: mode, dialect: .current),
                    in: webView
                )
                _ = try await send(.setUserCSS(pendingUserCSS), in: webView)
                _ = try await send(.setLinkCompletions(pendingLinkCompletions), in: webView)
                _ = try await send(.setResearcherComments(pendingResearcherComments), in: webView)
                _ = try await send(.setScrollFraction(pendingScrollFraction), in: webView)
                if let snapshot = matchingRecovery,
                   snapshot.fingerprint == startingFingerprint,
                   snapshot.source == checkedSource {
                    let recovered = try await send(.restoreRecovery(snapshot), in: webView)
                    generation = recovered.resultingGeneration
                    isDirty = snapshot.dirty
                    if recovered.recovery?.undoHistoryPreserved == false {
                        errorMessage = "The exact editor buffer was recovered, but its pre-crash undo history was unavailable."
                        _ = try await send(
                            .announceStatus(
                                "The exact editor buffer was recovered. Pre-crash undo history is unavailable."
                            ),
                            in: webView
                        )
                    } else {
                        _ = try await send(
                            .announceStatus("The exact editor buffer was recovered."),
                            in: webView
                        )
                    }
                } else {
                    isDirty = false
                }
                isLoaded = true
                flushPendingLine()
                focus()
            } catch {
                isLoaded = false
                errorMessage = error.localizedDescription
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

    private func send(
        _ operation: MarkdownEditorOperation,
        in webView: WKWebView
    ) async throws -> MarkdownEditorCommandResult {
        let previous = requestBarrier
        let intendedSessionID = sessionID
        let intendedDocumentID = documentID
        let intendedFingerprint = startingFingerprint
        let task = Task { @MainActor in
            await previous?.value
            guard intendedSessionID == sessionID,
                  intendedDocumentID == documentID,
                  intendedFingerprint == startingFingerprint else {
                throw SessionError.bridgeRejected("The editor identity changed while a request was queued.")
            }
            let request = MarkdownEditorRequest(
                sessionID: intendedSessionID,
                documentID: intendedDocumentID,
                startingFingerprint: intendedFingerprint,
                expectedGeneration: generation,
                operation: operation
            )
            let encoder = JSONEncoder()
            let requestData = try encoder.encode(request)
            guard requestData.count <= MarkdownEditorDeltaApplier.maximumResultUTF8Bytes + 512_000,
                  let requestObject = try JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
                throw SessionError.invalidResult
            }
            let rawResult = try await webView.callAsyncJavaScript(
                "return await window.scholiumEditor.dispatch(request)",
                arguments: ["request": requestObject],
                in: nil,
                contentWorld: .page
            )
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
                  result.resultingGeneration <= maximumAcceptedGeneration else {
                throw SessionError.invalidResult
            }
            if result.sourceChanged, let text = result.text {
                try reconcileMirror(with: text, publish: true)
            }
            if let context = result.context {
                self.context = context
                lastKnownSelections = context.selections
            }
            generation = result.resultingGeneration
            return result
        }
        requestBarrier = Task { @MainActor in _ = try? await task.value }
        return try await task.value
    }

    #if DEBUG
    private func installQATerminationObserverIfEnabled() {
        guard !qaTerminationObserverInstalled,
              Bundle.main.bundleIdentifier == "com.kbmanager.qa",
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

    private func reconcileMirror(with text: String, publish: Bool) throws {
        let exactText = checkedSource.contains("\r\n") && !text.contains("\r\n")
            ? text.replacingOccurrences(of: "\n", with: "\r\n")
            : text
        let replacement = MarkdownEditorDelta(
            fromUTF16: 0,
            toUTF16: checkedSource.utf16.count,
            insertion: exactText
        )
        checkedSource = try MarkdownEditorDeltaApplier.apply([replacement], to: checkedSource)
        if publish { sourceChangeHandler?(checkedSource) }
    }

    private static func sourceUTF16Offset(
        forEditorUTF16Offset requestedOffset: Int,
        in source: String
    ) -> Int? {
        guard requestedOffset >= 0 else { return nil }
        let units = Array(source.utf16)
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < units.count, editorOffset < requestedOffset {
            if units[sourceOffset] == 13,
               sourceOffset + 1 < units.count,
               units[sourceOffset + 1] == 10 {
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        guard editorOffset == requestedOffset else { return nil }
        return sourceOffset
    }

    private static func editorUTF16Offset(
        forSourceUTF16Offset requestedOffset: Int,
        in source: String
    ) -> Int? {
        let units = Array(source.utf16)
        guard requestedOffset >= 0, requestedOffset <= units.count else { return nil }
        var sourceOffset = 0
        var editorOffset = 0
        while sourceOffset < requestedOffset {
            if units[sourceOffset] == 13,
               sourceOffset + 1 < units.count,
               units[sourceOffset + 1] == 10 {
                guard sourceOffset + 2 <= requestedOffset else { return nil }
                sourceOffset += 2
            } else {
                sourceOffset += 1
            }
            editorOffset += 1
        }
        return editorOffset
    }
}

struct MarkdownEditorWebView: NSViewRepresentable {
    @ObservedObject var session: MarkdownEditorSession
    let documentID: String
    let source: String
    let mode: NotePresentationMode
    let userCSS: String
    let linkCompletions: [EditorLinkCompletion]
    let researcherComments: [ResearcherComment]
    let initialScrollFraction: Double
    let onDocumentChange: (String) -> Void
    let onRequestSave: () -> Void
    let onRequestSearch: () -> Void
    let onRequestComment: () -> Void
    let onLinkActivation: (String) -> Void
    let onCommentActivation: ((UUID) -> Void)?
    let onScrollFractionChange: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            session: session,
            onDocumentChange: onDocumentChange,
            onRequestSave: onRequestSave,
            onRequestSearch: onRequestSearch,
            onLinkActivation: onLinkActivation,
            onCommentActivation: onCommentActivation,
            onScrollFractionChange: onScrollFractionChange
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "scholium")
        contentController.addUserScript(WKUserScript(
            source: """
            window.addEventListener('error', function(event) {
                window.webkit.messageHandlers.scholium.postMessage({
                    type: 'editorError',
                    message: event.message || 'The Markdown editor could not start.'
                });
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        if let editorScript = Self.editorScript {
            contentController.addUserScript(WKUserScript(
                source: editorScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
        contentController.addUserScript(WKUserScript(
            source: """
            window.webkit.messageHandlers.scholium.postMessage({
                type: 'documentEnded',
                editorReady: typeof window.scholiumEditor === 'object'
            });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WindowAttachedWebView(frame: .zero, configuration: configuration)
        webView.editorSession = session
        webView.onRequestComment = onRequestComment
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.documentID = documentID
        context.coordinator.source = source
        context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
        context.coordinator.mode = mode
        context.coordinator.userCSS = userCSS
        context.coordinator.linkCompletions = linkCompletions
        context.coordinator.researcherComments = researcherComments
        context.coordinator.initialScrollFraction = initialScrollFraction
        session.attach(webView)

        guard let editorHTML = Self.editorHTML,
              Self.editorScript != nil else {
            session.reportError("The bundled Markdown editor resources could not be found.")
            return webView
        }
        context.coordinator.awaitingEditorLoad = true
        webView.onFirstWindowAttachment = { [weak webView] in
            webView?.loadHTMLString(editorHTML, baseURL: nil)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = session
            webView.onRequestComment = onRequestComment
        }
        context.coordinator.onDocumentChange = onDocumentChange
        context.coordinator.onRequestSave = onRequestSave
        context.coordinator.onRequestSearch = onRequestSearch
        context.coordinator.onLinkActivation = onLinkActivation
        context.coordinator.onCommentActivation = onCommentActivation
        context.coordinator.onScrollFractionChange = onScrollFractionChange
        context.coordinator.initialScrollFraction = initialScrollFraction
        if context.coordinator.userCSS != userCSS {
            context.coordinator.userCSS = userCSS
            session.setUserCSS(userCSS)
        }
        if context.coordinator.linkCompletions != linkCompletions {
            context.coordinator.linkCompletions = linkCompletions
            session.setLinkCompletions(linkCompletions)
        }
        if context.coordinator.researcherComments != researcherComments {
            context.coordinator.researcherComments = researcherComments
            session.setResearcherComments(researcherComments, in: source)
        }
        if context.coordinator.documentID != documentID {
            context.coordinator.documentID = documentID
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollFraction(initialScrollFraction)
        } else if context.coordinator.source != source {
            context.coordinator.source = source
            context.coordinator.startingFingerprint = DocumentFingerprint(content: source).sha256
            context.coordinator.lastDocumentVersion = 0
            session.loadDocument(source, documentID: documentID, mode: mode)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollFraction(initialScrollFraction)
        } else if context.coordinator.mode != mode {
            context.coordinator.mode = mode
            session.setMode(mode)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        if let webView = webView as? WindowAttachedWebView {
            webView.editorSession = nil
            webView.onRequestComment = nil
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scholium")
        webView.navigationDelegate = nil
        coordinator.session.removeCommittedTextSynchronizer()
        coordinator.session.removeSourceChangeHandler()
        coordinator.session.detach(webView)
    }

    private static var editorResourceDirectory: URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let packagedBundleURL = resourceURL
                .appendingPathComponent("Scholium_ScholiumApp.bundle", isDirectory: true)
            if let packagedResources = Bundle(url: packagedBundleURL)?.resourceURL,
               FileManager.default.fileExists(
                   atPath: packagedResources.appendingPathComponent("editor.bundle.js").path
               ) {
                return packagedResources
            }
        }
        return Bundle.module.url(forResource: "index", withExtension: "html")?
            .deletingLastPathComponent()
    }

    private static var editorScript: String? {
        guard let directory = editorResourceDirectory else { return nil }
        return try? String(
            contentsOf: directory.appendingPathComponent("editor.bundle.js"),
            encoding: .utf8
        )
    }

    private static var editorHTML: String? {
        guard let directory = editorResourceDirectory,
              let css = try? String(
                contentsOf: directory.appendingPathComponent("editor.css"),
                encoding: .utf8
              ),
              !ScholiumCalloutStyles.css.isEmpty else { return nil }
        return """
        <!doctype html>
        <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; img-src data:; font-src data:">
            <style>\(ScholiumWebFonts.css)\n\(css)\n\(ScholiumCalloutStyles.css)</style>
            <style id="scholium-user-css"></style>
          </head>
          <body><main id="editor"></main></body>
        </html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let session: MarkdownEditorSession
        var onDocumentChange: (String) -> Void
        var onRequestSave: () -> Void
        var onRequestSearch: () -> Void
        var onLinkActivation: (String) -> Void
        var onCommentActivation: ((UUID) -> Void)?
        var onScrollFractionChange: (Double) -> Void
        var documentID = ""
        var source = ""
        var mode: NotePresentationMode = .livePreview
        var userCSS = ""
        var linkCompletions: [EditorLinkCompletion] = []
        var researcherComments: [ResearcherComment] = []
        var awaitingEditorLoad = false
        var recoveringAfterTermination = false
        var startingFingerprint = ""
        var lastDocumentVersion = 0
        var initialScrollFraction: Double = 0
        private var hasSignaledReady = false

        init(
            session: MarkdownEditorSession,
            onDocumentChange: @escaping (String) -> Void,
            onRequestSave: @escaping () -> Void,
            onRequestSearch: @escaping () -> Void,
            onLinkActivation: @escaping (String) -> Void,
            onCommentActivation: ((UUID) -> Void)?,
            onScrollFractionChange: @escaping (Double) -> Void
        ) {
            self.session = session
            self.onDocumentChange = onDocumentChange
            self.onRequestSave = onRequestSave
            self.onRequestSearch = onRequestSearch
            self.onLinkActivation = onLinkActivation
            self.onCommentActivation = onCommentActivation
            self.onScrollFractionChange = onScrollFractionChange
            super.init()
            session.installCommittedTextSynchronizer { [weak self] source, fingerprint in
                guard let self else { return }
                self.source = source
                self.startingFingerprint = fingerprint
            }
            session.installSourceChangeHandler { [weak self] source in
                guard let self else { return }
                self.source = source
                self.onDocumentChange(source)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "scholium",
                  JSONSerialization.isValidJSONObject(message.body),
                  let data = try? JSONSerialization.data(withJSONObject: message.body),
                  data.count <= markdownEditorMaximumInboundBytes,
                  let payload = try? JSONDecoder().decode(EditorBridgeMessage.self, from: data) else { return }

            switch payload.type {
            case "ready":
                signalReady()
            case "documentEnded":
                if payload.editorReady == true {
                    signalReady()
                } else {
                    session.reportError("The Markdown editor script did not initialize.")
                }
            case "editorError":
                session.reportError(payload.message ?? "The Markdown editor could not start.")
            case "stateChanged":
                guard validEnvelope(payload) else { return }
                session.updateState(
                    dirty: payload.dirty,
                    line: payload.line,
                    column: payload.column,
                    lineCount: payload.lineCount
                )
            case "contextChanged":
                guard validEnvelope(payload), let context = payload.context else { return }
                session.updateContext(context)
            case "documentChanged":
                guard validEnvelope(payload) else { return }
                applyEditorChanges(from: payload)
            case "requestSave":
                guard validEnvelope(payload) else { return }
                onRequestSave()
            case "requestSearch":
                guard validEnvelope(payload) else { return }
                onRequestSearch()
            case "linkActivated":
                guard validEnvelope(payload), let target = payload.target, !target.isEmpty else { return }
                onLinkActivation(target)
            case "commentActivated":
                guard validEnvelope(payload),
                      let rawID = payload.commentID,
                      let id = UUID(uuidString: rawID) else { return }
                onCommentActivation?(id)
            case "scrollChanged":
                guard validEnvelope(payload),
                      let fraction = payload.scrollFraction,
                      fraction.isFinite,
                      (0...1).contains(fraction) else { return }
                onScrollFractionChange(fraction)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The page and an injected end-of-document script both report
            // readiness. Keep this delegate as a last-resort signal on beta
            // WebKit builds that occasionally drop the first script message.
            guard awaitingEditorLoad else { return }
            awaitingEditorLoad = false
            signalReady()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            session.reportError(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            session.webContentProcessTerminated()
            recoveringAfterTermination = true
            hasSignaledReady = false
            awaitingEditorLoad = true
            guard let editorHTML = MarkdownEditorWebView.editorHTML else {
                session.reportError("The Markdown editor resources could not be reloaded.")
                return
            }
            webView.loadHTMLString(editorHTML, baseURL: nil)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // Only Scholium can initiate this in-memory first navigation; the
            // view has not exposed any interactive document yet.
            if awaitingEditorLoad {
                decisionHandler(.allow)
                return
            }
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private func signalReady() {
            guard !hasSignaledReady else { return }
            hasSignaledReady = true
            session.loadDocument(
                source,
                documentID: documentID,
                mode: mode,
                preservingRecovery: recoveringAfterTermination
            )
            recoveringAfterTermination = false
            session.editorBecameReady()
            session.setUserCSS(userCSS)
            session.setLinkCompletions(linkCompletions)
            session.setResearcherComments(researcherComments, in: source)
            session.setScrollFraction(initialScrollFraction)
        }

        private func validEnvelope(_ payload: EditorBridgeMessage) -> Bool {
            guard payload.protocolVersion == markdownEditorProtocolVersion,
                  payload.sessionID == session.sessionID.uuidString,
                  payload.documentID == documentID,
                  payload.startingFingerprint == startingFingerprint,
                  let version = payload.documentVersion,
                  version >= session.generation else { return false }
            return true
        }

        private func applyEditorChanges(from payload: EditorBridgeMessage) {
            guard let rawChanges = payload.changes,
                  let baseGeneration = payload.baseGeneration,
                  let resultingGeneration = payload.resultingGeneration,
                  let nextSource = session.acceptEditorChanges(
                    rawChanges,
                    baseGeneration: baseGeneration,
                    resultingGeneration: resultingGeneration
                  ) else { return }
            source = nextSource
            lastDocumentVersion = resultingGeneration
        }
    }
}
