import AppKit
import Combine
import ScholiumContracts
import ScholiumEditor
import SwiftUI
import UniformTypeIdentifiers

/// Native transient controls are bound to the retained session's revision and
/// selection. They never own a second source buffer or write a file themselves.
@MainActor
final class NativeEditorInteractions {
    var onRequestSave: () -> Void = {}
    var onRequestFind: (DocumentFindShortcut) -> Void = { _ in }
    var linkCompletionQuery: @MainActor (EditorLinkCompletionKind, String) async -> [EditorLinkCompletion]
    var previewCatalog: DocumentPreviewCatalog?
    var previewRelativePath: String
    var previewAppearance: DocumentAppearanceSettings
    var onPasteImage: (EditorPastedImageSource) -> Bool
    var onAskAgent: AgentSelectionInquiryHandler?
    var onPassageAction: ((DocumentPassageAction, MarkdownSourceSelectionSnapshot?) -> Void)?
    var writingContinuationEnabled: Bool
    var writingContinuationContextKey: String
    var writingContinuationQuery: EditorWritingContinuationQuery
    private weak var session: MarkdownEditorSession?
    private var attachmentID: UUID?
    private var isCurrentHost: Bool {
        guard let session, let attachmentID else { return false }
        return session.isCurrentAttachment(attachmentID)
    }
    private let floating = DocumentFloatingSurfaceController()
    private let continuation = EditorWritingContinuationController()
    private var subscriptions = Set<AnyCancellable>()
    private var queryTask: Task<Void, Never>?
    private var queryOperationID: UUID?
    private var previewTask: Task<Void, Never>?
    private var previewHideTask: Task<Void, Never>?
    private var cachedPreviews: (source: String, catalog: DocumentPreviewCatalog?, values: [NativeDocumentPreview])?
    private var pointerMonitor: Any?
    private var focusObservers: [NSObjectProtocol] = []
    private var surfaceID = 0
    private var suggestions: [EditorLinkCompletion] = []
    private var suggestionRange: NSRange?
    private var suggestionKind = EditorLinkCompletionKind.term
    private var suggestionSessionID: UUID?
    private var suggestionGeneration = -1
    private var suggestionSelection: [MarkdownEditorSelectionRange] = []
    private var selectedSuggestion = 0
    private var ghostCandidate: EditorLinkCompletion?
    private var ghostRange: NSRange?
    private var ghostSessionID: UUID?
    private var ghostGeneration = -1
    private var ghostSelection: [MarkdownEditorSelectionRange] = []
    private var ghostStatusVisible = false
    private var hoverOffset: Int?
    private var hoverPreviewVisible = false
    private var previewPointerInside = false

    init(
        linkCompletionQuery: @escaping @MainActor (EditorLinkCompletionKind, String) async -> [EditorLinkCompletion] = { _, _ in [] },
        previewCatalog: DocumentPreviewCatalog? = nil,
        previewRelativePath: String = "document.md",
        previewAppearance: DocumentAppearanceSettings = .defaultSettings,
        onPasteImage: @escaping (EditorPastedImageSource) -> Bool = { _ in false },
        onAskAgent: AgentSelectionInquiryHandler? = nil,
        onPassageAction: ((DocumentPassageAction, MarkdownSourceSelectionSnapshot?) -> Void)? = nil,
        writingContinuationEnabled: Bool = false,
        writingContinuationContextKey: String = "",
        writingContinuationQuery: @escaping EditorWritingContinuationQuery = { _, _ in .unavailable(nil) }
    ) {
        self.linkCompletionQuery = linkCompletionQuery
        self.previewCatalog = previewCatalog
        self.previewRelativePath = previewRelativePath
        self.previewAppearance = previewAppearance
        self.onPasteImage = onPasteImage
        self.onAskAgent = onAskAgent
        self.onPassageAction = onPassageAction
        self.writingContinuationEnabled = writingContinuationEnabled
        self.writingContinuationContextKey = writingContinuationContextKey
        self.writingContinuationQuery = writingContinuationQuery
    }

    isolated deinit {
        queryTask?.cancel()
        continuation.cancel()
        previewTask?.cancel()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
        session?.nativeEditor.clearInlineGhost()
        floating.reset()
    }

    func update(from other: NativeEditorInteractions) {
        if writingContinuationContextKey != other.writingContinuationContextKey
            || writingContinuationEnabled != other.writingContinuationEnabled
        {
            dismissSuggestions()
        }
        linkCompletionQuery = other.linkCompletionQuery
        if previewCatalog != other.previewCatalog || previewRelativePath != other.previewRelativePath {
            cachedPreviews = nil
        }
        previewCatalog = other.previewCatalog
        previewRelativePath = other.previewRelativePath
        previewAppearance = other.previewAppearance
        onPasteImage = other.onPasteImage
        onAskAgent = other.onAskAgent
        onPassageAction = other.onPassageAction
        writingContinuationEnabled = other.writingContinuationEnabled
        writingContinuationContextKey = other.writingContinuationContextKey
        writingContinuationQuery = other.writingContinuationQuery
    }

    func attach(to session: MarkdownEditorSession, attachmentID: UUID) {
        detach()
        self.session = session
        self.attachmentID = attachmentID
        session.nativeEditor.onNativeKeyDown = { [weak self] in self?.keyDown($0) ?? false }
        session.nativeEditor.onNativeMenu = { [weak self] in self?.extendMenu($0) }
        session.nativeEditor.onNativePasteboard = { [weak self] in
            guard let self, let source = Self.imageSource(in: $0) else { return false }
            return self.onPasteImage(source)
        }
        session.onNativeSelectionChange = { [weak self] ranges, rect in self?.selectionChanged(ranges, rect: rect) }
        session.$presentation.map(\.presentedMode).removeDuplicates().dropFirst().sink { [weak self] _ in
            self?.dismissSuggestions()
        }.store(in: &subscriptions)
        session.writingContextChanges.sink { [weak self] in
            guard let self else { return }
            self.dismissSuggestions()
            self.scheduleCompletions(explicit: false)
        }.store(in: &subscriptions)
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved(event) }
            return event
        }
        focusObservers = [
            NotificationCenter.default.addObserver(
                forName: NSText.didEndEditingNotification, object: session.nativeEditor, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissSuggestions() }
            },
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
            ) { [weak self, weak session] _ in
                MainActor.assumeIsolated {
                    guard let session, session.nativeEditor.window?.isKeyWindow == false else { return }
                    self?.dismissSuggestions()
                }
            },
        ]
    }

    func detach() {
        dismissSuggestions()
        previewTask?.cancel()
        previewTask = nil
        previewHideTask?.cancel()
        previewHideTask = nil
        cachedPreviews = nil
        subscriptions.removeAll()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        pointerMonitor = nil
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
        focusObservers = []
        session?.nativeEditor.onNativeKeyDown = nil
        session?.nativeEditor.onNativeMenu = nil
        session?.nativeEditor.onNativePasteboard = nil
        session?.onNativeSelectionChange = nil
        floating.reset()
        session = nil
        attachmentID = nil
    }

    private func keyDown(_ event: NSEvent) -> Bool {
        guard isCurrentHost, let session, !session.isComposing else { return false }
        if ghostCandidate != nil && !session.nativeEditor.hasInlineGhost { dismissSuggestions() }
        if event.keyCode == 53, !suggestions.isEmpty || queryTask != nil || ghostCandidate != nil || ghostStatusVisible {
            dismissSuggestions()
            return true
        }
        if event.keyCode == 48, ghostCandidate != nil,
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        {
            acceptGhost()
            return true
        }
        if !suggestions.isEmpty, session.presentedMode == .edit,
            session.sessionID == suggestionSessionID, suggestionGeneration == session.generation
        {
            if event.keyCode == 125 || event.keyCode == 126 {
                selectedSuggestion = (selectedSuggestion + (event.keyCode == 125 ? 1 : suggestions.count - 1)) % suggestions.count
                showSuggestions()
                return true
            }
            if event.keyCode == 48 || event.keyCode == 36 {
                acceptSuggestion(selectedSuggestion)
                return true
            }
        }
        if event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control {
            scheduleCompletions(explicit: true)
            return true
        }
        return false
    }

    private func selectionChanged(_ ranges: [MarkdownEditorSelectionRange], rect: NSRect?) {
        dismissSuggestions()
        cancelHover()
        guard let session, !session.isComposing, ranges.count == 1 else { return }
        if !ranges[0].isNonempty {
            // Navigation keys can land on a source-located disclosure without
            // moving the pointer. Keep that keyboard route on the same native
            // preview as hover. A resolved link takes precedence over link
            // completion suggestions while its caret moves through the source.
            if let event = NSApp.currentEvent, event.type == .keyDown,
                event.window === session.nativeEditor.window,
                [UInt16(48), 123, 124, 125, 126].contains(event.keyCode),
                let snapshot = try? session.reconcileNativeSource(),
                let offset = EditorSourceOffsetMap(source: snapshot.text)
                    .sourceUTF16Offset(forEditorUTF16Offset: ranges[0].head),
                let preview = preview(at: offset, in: snapshot.text)
            {
                showPreview(preview)
                return
            }
            scheduleCompletions(explicit: false)
            return
        }
        let range = NSRange(
            location: min(ranges[0].anchor, ranges[0].head),
            length: abs(ranges[0].head - ranges[0].anchor))
        // Explain/Polish operate on prose, not a selected structural marker.
        // Keeping the bar away also leaves this newly revealed source syntax
        // unobscured while the researcher edits the Callout type.
        if session.nativeEditor.selectionContainsOnlyCalloutMarker(range) { return }
        guard let rect, onAskAgent != nil else { return }
        let generation = session.generation
        let sessionID = session.sessionID
        let geometry = viewportGeometry(rect)
        surfaceID += 1
        let id = surfaceID
        floating.present(
            .selection(.init(id: id, left: geometry.left, top: geometry.top, bottom: geometry.bottom)),
            in: session.scrollView, inquire: onAskAgent
        ) { [weak self, weak session] requested, action, _ in
            guard let self, self.isCurrentHost, let session, requested == self.surfaceID, session.sessionID == sessionID, session.generation == generation,
                session.currentValidSelectionRanges() == ranges, !session.isComposing
            else { return false }
            if action == .dismiss { self.floating.dismiss() }
            return true
        }
    }

    private func scheduleCompletions(explicit: Bool) {
        guard isCurrentHost, let session, (try? session.reconcileNativeSource()) != nil else { return }
        guard explicit || !hoverPreviewVisible else { return }
        guard session.hasWritingFocus, session.presentedMode == .edit,
            !session.isComposing, session.nativeCommandIsPermitted(.wikilink),
            session.currentValidSelectionRanges().count == 1,
            let selection = session.currentValidSelectionRanges().first, !selection.isNonempty
        else { return }
        let text = session.nativeEditor.rawSource as NSString
        let caret = selection.head
        guard caret <= text.length else { return }
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let prefix = text.substring(with: NSRange(location: line.location, length: caret - line.location))
        if let syntax = Self.syntaxSuggestions(prefix: prefix) {
            suggestions = syntax
            suggestionRange = NSRange(location: line.location, length: caret - line.location)
            suggestionSessionID = session.sessionID
            suggestionGeneration = session.generation
            suggestionSelection = session.currentValidSelectionRanges()
            suggestionKind = .term
            selectedSuggestion = 0
            showSuggestions()
            return
        }
        var kind = EditorLinkCompletionKind.term
        var query = ""
        var start = caret
        if let opening = prefix.range(of: "[[", options: .backwards), !prefix[opening.upperBound...].contains("]") {
            kind = .wikilink
            query = String(prefix[opening.upperBound...])
            start = line.location + prefix[..<opening.lowerBound].utf16.count
        } else if let opening = prefix.range(of: "[@", options: .backwards), !prefix[opening.upperBound...].contains("]") {
            kind = .analysisReference
            query = String(prefix[opening.upperBound...])
            start = line.location + prefix[..<opening.lowerBound].utf16.count
        } else {
            query = String(prefix.reversed().prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }).reversed())
            guard explicit || query.count >= 2 || writingContinuationEnabled else { return }
            start = caret - query.utf16.count
        }
        let generation = session.generation
        let sessionID = session.sessionID
        let ranges = session.currentValidSelectionRanges()
        queryTask?.cancel()
        let operationID = UUID()
        queryOperationID = operationID
        queryTask = Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            defer {
                if self.queryOperationID == operationID {
                    self.queryTask = nil
                    self.queryOperationID = nil
                }
            }
            if !explicit { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            let candidates = kind == .term && query.count < 2 ? [] : await self.linkCompletionQuery(kind, query)
            guard !Task.isCancelled, session.sessionID == sessionID, session.generation == generation,
                self.isCurrentHost, self.session === session, session.presentedMode == .edit, session.hasWritingFocus,
                session.currentValidSelectionRanges() == ranges, !session.isComposing
            else { return }
            if kind == .term {
                self.showLocalGhost(
                    candidates, queryRange: NSRange(location: start, length: caret - start),
                    sessionID: sessionID, generation: generation, ranges: ranges)
            } else {
                self.suggestions = Array(candidates.filter { !$0.isAmbiguous && !$0.insertion.isEmpty }.prefix(100))
                self.suggestionKind = kind
                self.suggestionRange = NSRange(location: start, length: caret - start)
                self.suggestionSessionID = sessionID
                self.suggestionGeneration = generation
                self.suggestionSelection = ranges
                self.selectedSuggestion = 0
                self.showSuggestions()
                return
            }
            guard self.writingContinuationEnabled,
                Self.aiEligible(prefix: prefix, next: caret == text.length ? nil : text.character(at: caret))
            else { return }
            // Local words appear promptly. AI is admitted only after a longer
            // pause, and its waiting phase replaces the preview at the caret.
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, session.sessionID == sessionID, session.generation == generation,
                self.isCurrentHost, self.session === session, session.hasWritingFocus,
                session.currentValidSelectionRanges() == ranges, !session.isComposing
            else { return }
            self.clearGhost()
            let sourceOffset = EditorSourceOffsetMap(source: session.checkedSource).sourceUTF16Offset(forEditorUTF16Offset: caret)
            if let sourceOffset {
                var result = EditorWritingContinuationResult.unavailable(nil)
                self.showContinuationStatus(.preparing, at: caret)
                let continuationTask = self.continuation.start(
                    requestID: UUID().uuidString, sourceCaret: sourceOffset, editorCaret: caret,
                    query: self.writingContinuationQuery,
                    isCurrent: { [weak self, weak session] in
                        guard let self, let session else { return false }
                        return self.isCurrentHost && self.session === session && session.sessionID == sessionID
                            && session.generation == generation && session.currentValidSelectionRanges() == ranges
                            && session.hasWritingFocus && !session.isComposing && session.presentedMode == .edit
                    },
                    publish: { [weak self] publication in
                        switch publication {
                        case .status(let status): self?.showContinuationStatus(status, at: caret)
                        case .result(let value): result = value
                        }
                    })
                await continuationTask.value
                guard !Task.isCancelled, session.sessionID == sessionID, session.generation == generation,
                    self.isCurrentHost, self.session === session, session.presentedMode == .edit, session.hasWritingFocus,
                    session.currentValidSelectionRanges() == ranges, !session.isComposing
                else { return }
                self.clearGhost()
                if case .suggestion(let text) = result {
                    self.showAIGhost(text, at: caret, sessionID: sessionID, generation: generation, ranges: ranges)
                } else if case .unavailable(let reason?) = result, reason.showsInEditor {
                    let reasonText = ScholiumL10n.string(String.LocalizationValue(reason.localizationKey))
                    self.showGhostStatus(reasonText, at: caret)
                }
            }
        }
    }

    private func showContinuationStatus(_ status: EditorWritingContinuationStatus, at caret: Int) {
        let label: String.LocalizationValue =
            switch status {
            case .preparing: "Preparing continuation…"
            case .retrieving: "Retrieving context…"
            case .generating: "Generating continuation…"
            }
        showGhostStatus(ScholiumL10n.string(label), at: caret)
    }

    static func aiEligible(prefix: String, next: unichar?) -> Bool {
        guard next == nil || next == 10 else { return false }
        let prose = prefix.replacingOccurrences(
            of: #"^(?:[ \t]*>[ \t]*)+"#, with: "", options: .regularExpression
        )
        .trimmingCharacters(in: .whitespaces)
        guard prose.contains(where: { $0.isLetter || $0.isNumber }),
            prose.range(
                of: #"^(?:#{1,6}[ \t]|[-+*][ \t]|\d{1,9}[.)][ \t]|\[!|\||!\[|\[[^]]+\]:)"#,
                options: .regularExpression) == nil
        else { return false }
        let last = prose.replacingOccurrences(of: #"[\s\"'”’）】\]]+$"#, with: "", options: .regularExpression).last
        return last.map { !".!?。！？…".contains($0) } ?? false
    }

    private func showLocalGhost(
        _ candidates: [EditorLinkCompletion], queryRange: NSRange,
        sessionID: UUID, generation: Int, ranges: [MarkdownEditorSelectionRange]
    ) {
        guard let session, let candidate = candidates.first(where: { !$0.isAmbiguous && $0.writingAction == "term" }),
            let count = candidate.replacementUTF16Count, count > 0, count <= queryRange.length
        else { return }
        let source = session.nativeEditor.rawSource as NSString
        // A paint-only preview cannot reflow authored characters after the
        // caret, so offer it only at a logical line end.
        guard queryRange.upperBound == source.length || source.character(at: queryRange.upperBound) == 10 else { return }
        let prefix = source.substring(with: NSRange(location: queryRange.upperBound - count, length: count))
        guard candidate.insertion.hasPrefix(prefix) else { return }
        let units = Self.visibleSourceUnits(String(candidate.insertion.dropFirst(prefix.count)))
        let suffix = String(units.map(\.visible))
        guard let visible = session.nativeEditor.showInlineGhost(suffix, at: queryRange.upperBound) else { return }
        let acceptedSource = prefix + units.prefix(visible.count).map(\.source).joined()
        ghostCandidate = .init(
            label: candidate.label, insertion: acceptedSource, detail: candidate.detail,
            path: candidate.path, displayText: nil, isAmbiguous: false,
            writingAction: "term", replacementUTF16Count: count)
        ghostRange = queryRange
        ghostSessionID = sessionID
        ghostGeneration = generation
        ghostSelection = ranges
        AccessibilityNotification.Announcement(
            String.localizedStringWithFormat(
                ScholiumL10n.string("Completion: %@. Press Tab to accept."), visible)
        ).post()
    }

    /// Authored library terms are Markdown-escaped in source. Keep the preview
    /// typographic while retaining the exact source fragment for every shown
    /// grapheme, including an escaped punctuation mark at an elision boundary.
    static func visibleSourceUnits(_ source: String) -> [(visible: Character, source: String)] {
        var result: [(visible: Character, source: String)] = []
        var iterator = source.makeIterator()
        while let character = iterator.next() {
            if character == "\\", let escaped = iterator.next() {
                result.append((escaped, "\\" + String(escaped)))
            } else {
                result.append((character, String(character)))
            }
        }
        return result
    }

    private func showAIGhost(
        _ text: String, at caret: Int, sessionID: UUID,
        generation: Int, ranges: [MarkdownEditorSelectionRange]
    ) {
        guard let session, let visible = session.nativeEditor.showInlineGhost(text, at: caret, isAI: true) else { return }
        ghostCandidate = .init(
            label: visible, insertion: visible, detail: "AI continuation", path: "",
            displayText: nil, isAmbiguous: false,
            writingAction: "continuation", replacementUTF16Count: 0)
        ghostRange = NSRange(location: caret, length: 0)
        ghostSessionID = sessionID
        ghostGeneration = generation
        ghostSelection = ranges
        AccessibilityNotification.Announcement(
            String.localizedStringWithFormat(
                ScholiumL10n.string("AI continuation: %@. Press Tab to accept."), visible)
        ).post()
    }

    private func showGhostStatus(_ message: String, at caret: Int) {
        clearGhost()
        guard let session else { return }
        ghostStatusVisible = session.nativeEditor.showInlineGhost(message, at: caret, isAI: true, isStatus: true) != nil
        AccessibilityNotification.Announcement(message).post()
    }

    private func clearGhost() {
        ghostCandidate = nil
        ghostRange = nil
        ghostStatusVisible = false
        session?.nativeEditor.clearInlineGhost()
    }

    private func acceptGhost() {
        guard isCurrentHost, let session else { return }
        do { _ = try session.reconcileNativeSource() } catch {
            session.reportError(error.localizedDescription)
            dismissSuggestions()
            return
        }
        guard let candidate = ghostCandidate, let range = ghostRange,
            session.sessionID == ghostSessionID, session.generation == ghostGeneration,
            session.currentValidSelectionRanges() == ghostSelection,
            !session.isComposing, session.presentedMode == .edit
        else {
            dismissSuggestions()
            return
        }
        do {
            let edit = try NativeEditorCompletion.edit(
                candidate, kind: .term, queryRange: range, source: session.nativeEditor.rawSource)
            dismissSuggestions()
            try session.nativeEditor.replaceProjectedRanges(
                [(edit.range, edit.insertion)],
                selection: NSRange(location: edit.range.location + edit.insertion.utf16.count, length: 0))
            _ = try session.reconcileNativeSource()
            session.updateNativeInteraction()
        } catch {
            session.reportError(error.localizedDescription)
            dismissSuggestions()
        }
    }

    private func showSuggestions() {
        guard isCurrentHost, let session, session.presentedMode == .edit, !session.isComposing,
            session.sessionID == suggestionSessionID, session.generation == suggestionGeneration,
            session.currentValidSelectionRanges() == suggestionSelection, !suggestions.isEmpty
        else {
            dismissSuggestions()
            return
        }
        let rect = session.nativeEditor.firstRect(forCharacterRange: session.nativeEditor.selectedRange(), actualRange: nil)
        guard let window = session.nativeEditor.window else { return }
        let local = session.nativeEditor.convert(window.convertFromScreen(rect), from: nil)
        let geometry = viewportGeometry(local)
        surfaceID += 1
        floating.present(
            .suggestions(
                .init(
                    id: surfaceID, left: geometry.left, top: geometry.top, bottom: geometry.bottom,
                    items: suggestions.map { .init(label: $0.label, detail: $0.detail) }, selected: selectedSuggestion)),
            in: session.scrollView
        ) { [weak self] id, action, index in
            guard let self, id == self.surfaceID else { return false }
            if action == .choose { self.acceptSuggestion(index) }
            if action == .select, self.suggestions.indices.contains(index) {
                self.selectedSuggestion = index
                self.showSuggestions()
            }
            if action == .dismiss { self.dismissSuggestions() }
            return true
        }
    }

    private func acceptSuggestion(_ index: Int) {
        guard isCurrentHost, let session else { return }
        do { _ = try session.reconcileNativeSource() } catch {
            session.reportError(error.localizedDescription)
            dismissSuggestions()
            return
        }
        guard suggestions.indices.contains(index), let range = suggestionRange,
            session.sessionID == suggestionSessionID, session.generation == suggestionGeneration, session.currentValidSelectionRanges() == suggestionSelection,
            !session.isComposing, session.presentedMode == .edit
        else {
            dismissSuggestions()
            return
        }
        let candidate = suggestions[index]
        do {
            let edit = try NativeEditorCompletion.edit(
                candidate, kind: suggestionKind,
                queryRange: range, source: session.nativeEditor.rawSource)
            try session.nativeEditor.replaceProjectedRanges(
                [(edit.range, edit.insertion)],
                selection: NSRange(location: edit.range.location + edit.insertion.utf16.count, length: 0))
            _ = try session.reconcileNativeSource()
            session.updateNativeInteraction()
        } catch { session.reportError(error.localizedDescription) }
        dismissSuggestions()
    }

    private func dismissSuggestions() {
        queryTask?.cancel()
        queryTask = nil
        queryOperationID = nil
        continuation.cancel()
        clearGhost()
        suggestions = []
        suggestionRange = nil
        floating.dismiss()
    }

    private func extendMenu(_ menu: NSMenu) {
        guard isCurrentHost, let session, (try? session.reconcileNativeSource()) != nil else { return }
        let generation = session.generation
        let sessionID = session.sessionID
        let ranges = session.currentValidSelectionRanges()
        if onPassageAction != nil {
            menu.addItem(.separator())
            for action in DocumentPassageAction.allCases {
                menu.addItem(
                    PassageMenuItem(title: action.title, enabled: !session.isComposing) { [weak self, weak session] in
                        Task { @MainActor in
                            guard let self, self.isCurrentHost, let session, session.sessionID == sessionID,
                                let snapshot = try? await session.passageSourceSnapshot(expectedSelections: ranges, expectedGeneration: generation)
                            else { return }
                            self.onPassageAction?(action, snapshot)
                        }
                    })
            }
        }
        if session.presentedMode == .edit {
            menu.addItem(.separator())
            menu.addItem(
                PassageMenuItem(title: ScholiumL10n.string("Suggestions"), enabled: !session.isComposing) { [weak self] in
                    self?.scheduleCompletions(explicit: true)
                })
        }
        if let selection = ranges.first,
            let offset = EditorSourceOffsetMap(source: session.checkedSource).sourceUTF16Offset(forEditorUTF16Offset: selection.head),
            let preview = preview(at: offset, in: session.checkedSource)
        {
            menu.addItem(
                PassageMenuItem(title: preview.title, enabled: true) { [weak self, weak session] in
                    guard let self, self.isCurrentHost, let session, session.sessionID == sessionID,
                        (try? session.reconcileNativeSource()) != nil, session.generation == generation
                    else { return }
                    self.showPreview(preview)
                })
        }
    }

    private func cancelHover() {
        previewTask?.cancel()
        previewTask = nil
        previewHideTask?.cancel()
        previewHideTask = nil
        previewPointerInside = false
        hoverOffset = nil
        if hoverPreviewVisible { floating.dismiss() }
        hoverPreviewVisible = false
    }

    private func schedulePreviewHide() {
        previewTask?.cancel()
        previewTask = nil
        hoverOffset = nil
        guard hoverPreviewVisible, !previewPointerInside else { return }
        previewHideTask?.cancel()
        previewHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, !self.previewPointerInside else { return }
            self.cancelHover()
        }
    }

    private func pointerMoved(_ event: NSEvent) {
        if event.window === floating.previewWebView?.window { return }
        guard isCurrentHost, let session, event.window === session.nativeEditor.window, session.nativeEditor.window?.isKeyWindow == true,
            session.currentValidSelectionRanges().allSatisfy({ !$0.isNonempty }), !session.isComposing,
            (try? session.reconcileNativeSource()) != nil
        else {
            schedulePreviewHide()
            return
        }
        let point = session.nativeEditor.convert(event.locationInWindow, from: nil)
        guard session.nativeEditor.visibleRect.contains(point) else {
            schedulePreviewHide()
            return
        }
        let index = session.nativeEditor.characterIndexForInsertion(at: point)
        guard index != hoverOffset else { return }
        hoverOffset = index
        previewTask?.cancel()
        guard let offset = EditorSourceOffsetMap(source: session.checkedSource).sourceUTF16Offset(forEditorUTF16Offset: index) else {
            schedulePreviewHide()
            return
        }
        let generation = session.generation
        let sessionID = session.sessionID
        previewTask = Task { @MainActor [weak self, weak session] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, self.isCurrentHost, let session, self.session === session,
                self.hoverOffset == index, session.nativeEditor.window?.isKeyWindow == true,
                session.sessionID == sessionID, session.generation == generation
            else { return }
            guard let preview = self.preview(at: offset, in: session.checkedSource) else {
                self.schedulePreviewHide()
                return
            }
            self.previewHideTask?.cancel()
            self.previewHideTask = nil
            self.showPreview(preview)
        }
    }

    private func preview(at offset: Int, in source: String) -> NativeDocumentPreview? {
        if cachedPreviews?.source != source || cachedPreviews?.catalog != previewCatalog {
            cachedPreviews = (
                source, previewCatalog,
                NativeDocumentPreviewBuilder.build(
                    source: source, relativePath: previewRelativePath, catalog: previewCatalog)
            )
        }
        return cachedPreviews?.values.first {
            $0.span.utf16LowerBound <= offset && offset < $0.span.utf16UpperBound
        }
    }

    private func showPreview(_ preview: NativeDocumentPreview) {
        guard let session,
            let map = try? ExactSourceProjection(utf8: Data(session.checkedSource.utf8)),
            let range = try? map.projectedUTF16Range(forSourceUTF16Range: preview.span.nsRange),
            let window = session.nativeEditor.window
        else { return }
        let screen = session.nativeEditor.firstRect(forCharacterRange: range, actualRange: nil)
        let rect = session.nativeEditor.convert(window.convertFromScreen(screen), from: nil)
        let geometry = viewportGeometry(rect)
        surfaceID += 1
        hoverPreviewVisible = true
        let css = [
            SafeMarkdownReadWebView.Coordinator.documentResourceCSS(),
            DocumentAppearanceStyles.css(for: previewAppearance),
            ScholiumDocumentPresentationConfiguration(textScale: 1).css,
        ].joined(separator: "\n")
        floating.present(
            .preview(
                .init(
                    id: surfaceID, left: geometry.left, top: geometry.top, bottom: geometry.bottom,
                    html: preview.html, css: css)),
            in: session.scrollView
        ) { [weak self] _, action, _ in
            guard let self else { return false }
            switch action {
            case .enter:
                self.previewPointerInside = true
                self.previewHideTask?.cancel()
                self.previewHideTask = nil
            case .leave:
                self.previewPointerInside = false
                self.schedulePreviewHide()
            case .dismiss:
                self.hoverPreviewVisible = false
                self.previewPointerInside = false
            case .select, .choose: break
            }
            return true
        }
    }

    private func viewportGeometry(_ rect: NSRect) -> (left: Double, top: Double, bottom: Double) {
        guard let session else { return (0, 0, 0) }
        let rect = session.scrollView.convert(rect, from: session.nativeEditor)
        let top = session.scrollView.isFlipped ? rect.minY : session.scrollView.bounds.height - rect.maxY
        return (Double(rect.minX), Double(top), Double(top + rect.height))
    }

    private static func syntaxSuggestions(prefix: String) -> [EditorLinkCompletion]? {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        let callouts = ["orient", "cite", "connect", "state", "illustrate", "quote", "flag"]
        if trimmed.hasPrefix("> [!") || trimmed.hasPrefix(">[!") {
            guard !trimmed.contains("]"), let marker = trimmed.range(of: "[!") else { return nil }
            let query = trimmed[marker.upperBound...].lowercased()
            return callouts.filter { $0.hasPrefix(query) }.map {
                .init(label: $0.capitalized, insertion: "> [!\($0)]\n> ", detail: "Callout", path: "", displayText: nil, isAmbiguous: false)
            }
        }
        guard trimmed.hasPrefix("/"), !trimmed.dropFirst().contains(where: { $0.isWhitespace || $0 == "/" }) else { return nil }
        let query = trimmed.dropFirst().lowercased()
        let entries: [(String, String)] =
            [
                ("Heading 1", "# "), ("Heading 2", "## "), ("Heading 3", "### "),
                ("Bullet List", "- "), ("Numbered List", "1. "), ("Task List", "- [ ] "),
                ("Quote", "> "), ("Code Block", "```\n\n```"), ("Mermaid", "```mermaid\n\n```"),
                ("Table", "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |"),
                ("Math", "$$\n\n$$"), ("Thematic Break", "---\n"), ("Image", "![]()"),
            ] + callouts.map { ($0.capitalized, "> [!\($0)]\n> ") }
        return entries.filter { query.isEmpty || $0.0.lowercased().contains(query) }.map {
            .init(label: $0.0, insertion: $0.1, detail: "Markdown", path: "", displayText: nil, isAmbiguous: false)
        }
    }

    private static func imageSource(in pasteboard: NSPasteboard) -> EditorPastedImageSource? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard let url = urls.first, let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
                type.conforms(to: .image)
            else { return nil }
            return .file(url)
        }
        for kind in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: kind), !data.isEmpty {
                return .data(data, preferredFilename: kind == .png ? "Pasted Image.png" : "Pasted Image.tiff")
            }
        }
        return nil
    }
}
