import AppKit
import SwiftUI
import WebKit

extension DocumentPreviewFailure {
    var message: String {
        switch self {
        case .size: ScholiumL10n.string("Preview is too large to display.")
        case .loading: ScholiumL10n.string("Preview could not be loaded. Try again.")
        case .measurement: ScholiumL10n.string("Preview could not be displayed. Try again.")
        }
    }
}

/// A bounded read-only preview projection, never an editor/source operation.
struct DocumentPreviewSurface: Codable, Equatable, Sendable {
    let id: Int
    let left: Double
    let top: Double
    let bottom: Double
    let html: String
    let css: String
    var imageResourceKeys: [String] = []
}

/// A bounded read-only completion projection, never an editor/source operation.
struct DocumentSuggestionSurface: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let label: String
        let detail: String
        var disabled = false
    }
    let id: Int
    let left: Double
    let top: Double
    let bottom: Double
    let items: [Item]
    let selected: Int
}

/// A bounded read-only selection-action projection, never an editor/source operation.
struct DocumentSelectionSurface: Codable, Equatable, Sendable {
    let id: Int
    let left: Double
    let top: Double
    let bottom: Double
    let utf16Count: Int
}

enum DocumentFloatingKind: String, Codable, Equatable, Sendable {
    case preview
    case suggestions
    case selection
}

enum DocumentFloatingAction: String, Equatable, Sendable {
    case dismiss
    case enter
    case leave
    case select
    case choose
}

struct DocumentPreviewFailureSurface: Decodable, Equatable, Sendable {
    let id: Int
}

struct DocumentFloatingDismissal: Codable, Equatable, Sendable {
    let kind: DocumentFloatingKind
    let id: Int
}

enum DocumentFloatingEvent: Equatable, Sendable {
    case preview(DocumentPreviewSurface)
    case previewFailure(DocumentPreviewFailureSurface)
    case suggestions(DocumentSuggestionSurface)
    case selection(DocumentSelectionSurface)
    case dismiss(DocumentFloatingDismissal)

    var kind: DocumentFloatingKind? {
        switch self {
        case .preview, .previewFailure: .preview
        case .suggestions: .suggestions
        case .selection: .selection
        case .dismiss(let value): value.kind
        }
    }

    var allowsAgentInquiry: Bool {
        if case .selection = self { return true }
        return false
    }

    static func decode(_ value: Any?) -> Self? {
        guard let value = value as? [String: Any],
            Set(value.keys) == ["type", "surface"] || Set(value.keys) == ["type", "kind", "id"] || Set(value.keys) == ["type", "id", "reason"],
            JSONSerialization.isValidJSONObject(value),
            let type = value["type"] as? String
        else { return nil }

        switch type {
        case "previewSurface":
            guard Set(value.keys) == ["type", "surface"],
                let object = value["surface"] as? [String: Any],
                Set(object.keys) == ["id", "left", "top", "bottom", "html", "css", "imageResourceKeys"],
                let data = try? JSONSerialization.data(withJSONObject: object),
                data.count <= 1_500_000,
                let result = try? JSONDecoder().decode(DocumentPreviewSurface.self, from: data),
                result.id > 0,
                [result.left, result.top, result.bottom].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
                result.bottom >= result.top,
                !result.html.isEmpty,
                result.html.utf8.count <= 500_000,
                result.css.utf8.count <= 900_000,
                result.imageResourceKeys.count <= 8_192,
                Set(result.imageResourceKeys).count == result.imageResourceKeys.count,
                result.imageResourceKeys.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 16_384 })
            else { return nil }
            return .preview(result)
        case "previewFailure":
            guard Set(value.keys) == ["type", "id", "reason"],
                let data = try? JSONSerialization.data(withJSONObject: value),
                let failure = try? JSONDecoder().decode(DocumentPreviewFailureSurface.self, from: data),
                failure.id > 0,
                value["reason"] as? String == "size"
            else { return nil }
            return .previewFailure(failure)
        case "suggestionSurface":
            guard Set(value.keys) == ["type", "surface"],
                let object = value["surface"] as? [String: Any],
                Set(object.keys) == ["id", "left", "top", "bottom", "items", "selected"],
                let data = try? JSONSerialization.data(withJSONObject: object),
                data.count <= 1_500_000,
                let result = try? JSONDecoder().decode(DocumentSuggestionSurface.self, from: data),
                result.id > 0,
                [result.left, result.top, result.bottom].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
                result.bottom >= result.top,
                !result.items.isEmpty,
                result.items.count <= 100,
                result.items.allSatisfy({ $0.label.utf16.count <= 512 && $0.detail.utf16.count <= 1_024 }),
                result.selected >= -1,
                result.selected < result.items.count
            else { return nil }
            return .suggestions(result)
        case "selectionSurface":
            guard Set(value.keys) == ["type", "surface"],
                let object = value["surface"] as? [String: Any],
                Set(object.keys) == ["id", "left", "top", "bottom", "utf16Count"],
                let data = try? JSONSerialization.data(withJSONObject: object),
                data.count <= 100_000,
                let result = try? JSONDecoder().decode(DocumentSelectionSurface.self, from: data),
                result.id > 0,
                [result.left, result.top, result.bottom].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
                result.bottom >= result.top,
                (1...32_000).contains(result.utf16Count)
            else { return nil }
            return .selection(result)
        case "dismissSurface":
            guard Set(value.keys) == ["type", "kind", "id"],
                let kind = value["kind"] as? String,
                let kind = DocumentFloatingKind(rawValue: kind),
                let id = value["id"] as? Int,
                id > 0
            else { return nil }
            return .dismiss(DocumentFloatingDismissal(kind: kind, id: id))
        default:
            return nil
        }
    }
}

private struct ActiveDocumentFloatingSurface: Equatable {
    let id: Int
    let kind: DocumentFloatingKind
    let left: Double
    let top: Double
    let bottom: Double
    var selectionUTF16Count: Int? = nil
    var selectionCommandID: UUID? = nil
}

private struct ActiveSelectionCommand {
    let id: UUID
    var surfaceID: Int?
    var task: Task<Bool, any Error>?
}

/// Owns only native floating presentation in the originating WebKit viewport.
/// No source mirror, editing history, or independent completion state.
@MainActor
final class DocumentFloatingSurfaceController: NSObject {
    private weak var owner: WKWebView?
    private var surface: ActiveDocumentFloatingSurface?
    private var glass: TrackingGlassView?
    private var preview: DocumentPreviewPopover?
    private var suggestions: NativeFloatingChoiceList?
    private var preferredWidth: CGFloat = 368
    private var suggestionsBelow: Bool?
    var previewWebView: WKWebView? { preview?.webView }
    var isPreviewShown: Bool { preview?.isShown == true }
    var onPreviewShown: (() -> Void)?
    var onPreviewFailure: ((DocumentPreviewFailure) -> Void)?
    private var event: ((Int, DocumentFloatingAction, Int) async -> Bool)?
    var selectionResultPopover: NSPopover? { resultPopover }
    private var resultPopover: NSPopover?
    private var inquiryTask: Task<Void, Never>?
    private var inquiryID: UUID?
    private var selectionInquiry: ((AgentChatSelectionInquiry) -> Void)?
    private var selectionCommand: ActiveSelectionCommand?
    private var isPresentingSelectionCommand: Bool { selectionCommand != nil }
    private var selectionReceipt: (commandID: UUID, id: Int, continuation: CheckedContinuation<Void, any Error>)?
    private var observers: [NSObjectProtocol] = []
    private var selectionKeyMonitor: Any?
    private var menuTrackingDepth = 0

    #if DEBUG
        var testingSelectionReceiptCommandID: UUID? { selectionReceipt?.commandID }
        var testingSelectionReceiptCancellationHandler: (@Sendable () -> Task<Void, Never>)? {
            selectionReceipt.map { selectionReceiptCancellationHandler(commandID: $0.commandID) }
        }
    #endif

    func present(
        _ value: DocumentFloatingEvent,
        in webView: WKWebView,
        inquire: AgentSelectionInquiryHandler? = nil,
        imageResources: [String: String] = [:],
        event: @escaping (Int, DocumentFloatingAction, Int) async -> Bool
    ) {
        if case .dismiss(let value) = value {
            if surface?.id == value.id, surface?.kind == value.kind {
                // presentCurrent first hides the previous automatic toolbar.
                // That old wire ID does not own the new native command.
                if let commandID = surface?.selectionCommandID, commandID == selectionCommand?.id {
                    dismiss()
                } else {
                    dismissPresentation()
                }
            }
            return
        }
        guard webView.window != nil, webView.bounds.width > 24, webView.bounds.height > 24,
            let viewport = webView.superview as? DocumentWebViewContainer
        else { return }
        if case .previewFailure(let failure) = value {
            guard owner !== webView || surface == nil || failure.id > surface!.id else { return }
            dismiss()
            onPreviewFailure?(.size)
            return
        }
        let next: ActiveDocumentFloatingSurface
        switch value {
        case .preview(let preview):
            next = ActiveDocumentFloatingSurface(
                id: preview.id, kind: .preview, left: preview.left, top: preview.top, bottom: preview.bottom)
        case .suggestions(let suggestions):
            next = ActiveDocumentFloatingSurface(
                id: suggestions.id, kind: .suggestions, left: suggestions.left, top: suggestions.top, bottom: suggestions.bottom)
        case .selection(let selection):
            guard isPresentingSelectionCommand || selectionHasToolbarRoom(top: selection.top, bottom: selection.bottom, in: webView) else {
                dismiss()
                return
            }
            next = ActiveDocumentFloatingSurface(
                id: selection.id, kind: .selection, left: selection.left, top: selection.top, bottom: selection.bottom,
                selectionUTF16Count: selection.utf16Count,
                selectionCommandID: owner === webView && selectionCommand?.surfaceID == selection.id ? selectionCommand?.id : nil)
        case .dismiss, .previewFailure:
            return
        }
        if owner === webView, let surface, next.id <= surface.id { return }
        if owner !== webView {
            reset()
        } else if surface?.kind != next.kind || (surface?.kind == .selection && surface?.id != next.id) {
            dismissPresentation()
        }
        self.event = event
        self.owner = webView
        self.surface = next
        if case .preview(let value) = value {
            let content = preview ?? DocumentPreviewPopover()
            preview = content
            content.onShown = { [weak self] in self?.onPreviewShown?() }
            content.onFailure = { [weak self] failure in self?.onPreviewFailure?(failure) }
            content.onEvent = { [weak self] action in
                self?.send(action)
                if action == .dismiss { self?.dismiss() }
            }
            content.present(value, in: webView, imageResources: imageResources)
            return
        }
        if glass == nil {
            let container = TrackingGlassView()
            container.style = .regular
            container.setAccessibilityEnabled(true)
            container.cornerRadius = ScholiumCornerRole.boundedPanel.radius
            container.onPointerPresence = { [weak self] entered in self?.send(entered ? .enter : .leave) }
            glass = container
            viewport.addSubview(container, positioned: .above, relativeTo: webView)
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didUpdateNotification, object: webView.window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.resultPopover == nil,
                            self.focusedPresentationView != nil, !self.presentationOwnsFocus
                        else { return }
                        self.send(.dismiss)
                        self.dismiss()
                    }
                })
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.didResizeNotification] {
                observers.append(
                    NotificationCenter.default.addObserver(
                        forName: name, object: webView.window, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            // The native transient popover owns activation and outside-click
                            // dismissal while its controls take keyboard focus.
                            if name == NSWindow.didResignKeyNotification, self?.resultPopover != nil { return }
                            self?.send(.dismiss)
                            self?.dismiss()
                        }
                    })
            }
            for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.menuTrackingDepth = max(0, self.menuTrackingDepth + (name == NSMenu.didBeginTrackingNotification ? 1 : -1))
                        }
                    })
            }
            selectionKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleSelectionKeyDown(event)
            }
        }
        guard let glass else { return }
        switch value {
        case .suggestions(let value):
            let content = suggestions ?? NativeFloatingChoiceList(acceptsKeyboard: false)
            let isNewList = suggestions == nil
            if isNewList {
                suggestions = content
                glass.contentView = content
            }
            content.choose = { [weak self] index in self?.send(.choose, index: index) }
            content.select = { [weak self] index in self?.send(.select, index: index) }
            content.update(items: value.items.map { .init(label: $0.label, detail: $0.detail, disabled: $0.disabled) }, selected: value.selected)
            preferredWidth = isNewList ? content.preferredSize.width : max(preferredWidth, content.preferredSize.width)
            // CodeMirror retains the single AX listbox, active descendant and keyboard path.
            glass.setAccessibilityElement(true)
            glass.setAccessibilityRole(.group)
            glass.setAccessibilityLabel(ScholiumL10n.string("Suggestions"))
            glass.setAccessibilityIdentifier("scholium.documentSuggestions")
            glass.setAccessibilityChildren([])
            layout(height: content.preferredSize.height)
        case .preview, .previewFailure: break  // Owned by DocumentPreviewPopover above.
        case .selection:
            guard inquire != nil else {
                dismiss()
                return
            }
            suggestions = nil
            let bar = SelectionActionBar(actions: SelectionActionPreferences.shared.actions, selectionUTF16Count: next.selectionUTF16Count ?? 0)
            bar.onDismiss = { [weak self] in
                self?.cancelSelectionPresentation()
            }
            bar.onMenuClosed = { [weak self] in
                // Defer focus restoration while the pop-up button unwinds,
                // then check this exact surface and its current responder.
                Task { @MainActor [weak self] in
                    await Task.yield()
                    guard let self, self.surface?.id == next.id, self.surface?.kind == .selection,
                        let owner = self.owner, let window = owner.window, window.isKeyWindow,
                        let responder = self.focusedPresentationView, let glass = self.glass,
                        responder === glass || responder.isDescendant(of: glass)
                    else { return }
                    window.makeFirstResponder(owner)
                }
            }
            bar.onInquiry = { [weak self] inquiry in
                guard let self, self.inquiryTask == nil, self.resultPopover == nil,
                    let surface = self.surface, let event = self.event
                else { return }
                let inquiryID = UUID()
                self.inquiryID = inquiryID
                self.inquiryTask = Task { @MainActor [weak self] in
                    defer {
                        if self?.inquiryID == inquiryID {
                            self?.inquiryTask = nil
                            self?.inquiryID = nil
                        }
                    }
                    guard await event(surface.id, .choose, 0), !Task.isCancelled,
                        let self, self.surface?.id == surface.id
                    else { return }
                    do {
                        let result = try await inquire?(inquiry, { await event(surface.id, .choose, 0) })
                        guard !Task.isCancelled, self.surface?.id == surface.id,
                            self.inquiryID == inquiryID
                        else { return }
                        guard let result else {
                            self.send(.dismiss)
                            self.dismiss()
                            return
                        }
                        self.showSelectionPopover(
                            AgentSelectionResultView(
                                result: result, close: { [weak self] in self?.resultPopover?.close() },
                                width: min(380, max(1, (self.owner?.bounds.width ?? 404) - 24))))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled, self.surface?.id == surface.id else { return }
                        self.showSelectionPopover(
                            VStack(alignment: .leading, spacing: 12) {
                                Text(inquiry.title).font(.headline)
                                Text(error.localizedDescription).textSelection(.enabled)
                                HStack {
                                    Spacer()
                                    Button("Dismiss") { [weak self] in self?.resultPopover?.close() }
                                        .keyboardShortcut(.cancelAction)
                                }
                            }
                            .padding(16)
                            .frame(width: min(300, max(1, (self.owner?.bounds.width ?? 324) - 24)))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("scholium.selectionResult.error"))
                    }
                }
            }
            selectionInquiry = bar.onInquiry
            // A menu invokes directly, including selections spanning the viewport.
            // Its temporary admission must not paint a toolbar over selected prose.
            glass.isHidden = isPresentingSelectionCommand
            glass.contentView = bar
            glass.cornerRadius = 20
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.setAccessibilityElement(false)
            glass.setAccessibilityChildren([bar])
            preferredWidth = bar.preferredSize.width
            layout(height: bar.preferredSize.height)
            if selectionReceipt?.id == next.id, selectionReceipt?.commandID == next.selectionCommandID {
                selectionReceipt?.continuation.resume()
                selectionReceipt = nil
            }
        case .dismiss: break
        }
    }

    func presentSelectionInquiry(
        _ inquiry: AgentChatSelectionInquiry,
        in webView: WKWebView,
        presenting: @escaping @MainActor () async throws -> Int?
    ) async throws -> Bool {
        try Task.checkCancellation()
        guard !isPresentingSelectionCommand, webView.window != nil else { return false }
        if owner !== webView {
            reset()
            owner = webView
        }
        let commandID = UUID()
        selectionCommand = ActiveSelectionCommand(id: commandID)
        // The host owns the whole command, including the initial JavaScript
        // reply before a floating-surface receipt exists. Reset must end that
        // wait even when the menu's caller remains alive and uncancelled.
        let task = Task { @MainActor in
            try await self.performSelectionInquiry(inquiry, in: webView, commandID: commandID, presenting: presenting)
        }
        selectionCommand?.task = task
        return try await withTaskCancellationHandler {
            let invoked = try await task.value
            try Task.checkCancellation()
            return invoked
        } onCancel: {
            task.cancel()
        }
    }

    private func performSelectionInquiry(
        _ inquiry: AgentChatSelectionInquiry,
        in webView: WKWebView,
        commandID: UUID,
        presenting: @MainActor () async throws -> Int?
    ) async throws -> Bool {
        defer {
            if selectionCommand?.id == commandID {
                selectionCommand = nil
                // An automatic projection received during the reply wait must
                // not remain hidden after an unrelated command failed.
                if let surface, surface.selectionCommandID == nil {
                    if surface.kind == .selection, let owner,
                        !selectionHasToolbarRoom(top: surface.top, bottom: surface.bottom, in: owner)
                    {
                        dismissPresentation()
                    } else {
                        glass?.isHidden = false
                    }
                }
            }
        }
        do {
            try Task.checkCancellation()
            let presentedID = try await presenting()
            try Task.checkCancellation()
            guard let id = presentedID, id > 0 else {
                return false
            }
            guard selectionCommand?.id == commandID, owner === webView else {
                throw CancellationError()
            }
            selectionCommand?.surfaceID = id
            if surface?.kind == .selection, surface?.id == id {
                surface?.selectionCommandID = commandID
            }
            try Task.checkCancellation()
            if surface?.kind != .selection || surface?.id != id {
                try await withScholiumLifecycleDeadline(phase: .bridgeRequest, timeout: .seconds(3)) {
                    let cancelReceipt = self.selectionReceiptCancellationHandler(commandID: commandID)
                    try await withTaskCancellationHandler {
                        try Task.checkCancellation()
                        guard self.selectionCommand?.id == commandID, self.owner === webView else {
                            throw CancellationError()
                        }
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                            if self.surface?.kind == .selection, self.surface?.id == id,
                                self.surface?.selectionCommandID == commandID
                            {
                                continuation.resume()
                            } else {
                                self.selectionReceipt = (commandID, id, continuation)
                            }
                        }
                    } onCancel: {
                        _ = cancelReceipt()
                    }
                }
            }
            guard selectionCommand?.id == commandID, owner === webView else {
                throw CancellationError()
            }
            guard surface?.kind == .selection, surface?.id == id, surface?.selectionCommandID == commandID else {
                return false
            }
            try Task.checkCancellation()
            let invoked = invokeSelectionInquiry(inquiry)
            if !invoked { dismissPresentation() }
            return invoked
        } catch {
            cancelSelectionReceipt(commandID: commandID)
            if owner === webView, surface?.selectionCommandID == commandID { dismissPresentation() }
            throw error
        }
    }

    private func cancelSelectionReceipt(commandID: UUID? = nil) {
        guard let receipt = selectionReceipt, commandID == nil || receipt.commandID == commandID else { return }
        selectionReceipt = nil
        receipt.continuation.resume(throwing: CancellationError())
    }

    private func selectionReceiptCancellationHandler(commandID: UUID) -> @Sendable () -> Task<Void, Never> {
        { [weak self] in
            Task { @MainActor [weak self] in self?.cancelSelectionReceipt(commandID: commandID) }
        }
    }

    private func cancelSelectionPresentation() {
        if let owner, owner.window?.isKeyWindow == true { owner.window?.makeFirstResponder(owner) }
        send(.dismiss)
        dismiss()
    }

    private var focusedPresentationView: NSView? {
        guard let responder = owner?.window?.firstResponder as? NSView else { return nil }
        return (responder as? NSTextView)?.delegate as? NSView ?? responder
    }

    private var presentationOwnsFocus: Bool {
        guard let responder = focusedPresentationView, let owner else { return false }
        return responder === owner || responder.isDescendant(of: owner)
            || glass.map { responder === $0 || responder.isDescendant(of: $0) } == true
    }

    private func selectionHasToolbarRoom(top: Double, bottom: Double, in webView: WKWebView) -> Bool {
        bottom + 52 <= webView.bounds.height - 12 || top >= 64
    }

    /// The local monitor routes only input owned by this document or its bar.
    func handleSelectionKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 53,
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
            surface?.kind == .selection, resultPopover == nil, menuTrackingDepth == 0,
            let owner, event.window === owner.window, owner.window?.isKeyWindow == true,
            presentationOwnsFocus,
            (owner as? any ScholiumDocumentInputStateProviding)?.scholiumIsComposing != true,
            (owner.window?.firstResponder as? any NSTextInputClient)?.hasMarkedText() != true
        else { return event }
        cancelSelectionPresentation()
        return nil
    }

    func canInvokeSelectionInquiry(_ inquiry: AgentChatSelectionInquiry) -> Bool {
        guard surface?.kind == .selection, let count = surface?.selectionUTF16Count,
            selectionInquiry != nil, inquiryTask == nil, resultPopover == nil,
            owner?.window != nil
        else { return false }
        return inquiry.operation == nil || count <= MarkdownSelectionActionAdmission.maximumWritingAssistanceUTF16Length
    }

    @discardableResult
    func invokeSelectionInquiry(_ inquiry: AgentChatSelectionInquiry) -> Bool {
        guard canInvokeSelectionInquiry(inquiry) else { return false }
        selectionInquiry?(inquiry)
        return true
    }

    private func showSelectionPopover<Content: View>(_ content: Content) {
        guard let owner, owner.window != nil, let surface, surface.kind == .selection else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        resultPopover = popover
        popover.delegate = self
        // Source capture has finished. Remove only the toolbar presentation: a
        // full dismissal here would cancel capture and invalidate its selection.
        glass?.onPointerPresence = nil
        glass?.removeFromSuperview()
        glass = nil
        let bounds = owner.bounds
        let visibleTop = (owner.superview as? DocumentWebViewContainer)?.floatingContentTopInset ?? 0
        let top = min(max(visibleTop, surface.top), bounds.height - 1)
        let bottom = min(max(top, surface.bottom), bounds.height - 1)
        let anchor = NSRect(
            x: min(max(0, surface.left), bounds.width - 1),
            y: owner.isFlipped ? top : bounds.height - bottom,
            width: 1, height: max(1, bottom - top))
        popover.show(relativeTo: anchor, of: owner, preferredEdge: owner.isFlipped ? .maxY : .minY)
    }

    /// Native visibility can end before the retained document receives another
    /// DOM event. Revoke its matching Web presentation as well as the window.
    func dismissNotifyingOwner() {
        send(.dismiss)
        dismiss()
    }

    func dismiss() {
        selectionCommand?.task?.cancel()
        selectionCommand = nil
        cancelSelectionReceipt()
        dismissPresentation()
    }

    private func dismissPresentation() {
        if let selectionKeyMonitor { NSEvent.removeMonitor(selectionKeyMonitor) }
        selectionKeyMonitor = nil
        menuTrackingDepth = 0
        suggestionsBelow = nil
        inquiryTask?.cancel()
        inquiryTask = nil
        inquiryID = nil
        selectionInquiry = nil
        resultPopover?.close()
        resultPopover = nil
        preview?.dismiss()
        suggestions = nil
        glass?.removeFromSuperview()
        glass = nil
        surface = nil
        event = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    /// Ends the document host's lifetime, including its reusable preview renderer.
    func reset() {
        dismiss()
        preview?.reset()
        preview = nil
        owner = nil
    }

    private func send(_ action: DocumentFloatingAction, index: Int = -1) {
        guard let surface, let event else { return }
        Task { _ = await event(surface.id, action, index) }
    }

    private func layout(height: CGFloat) {
        guard let owner, let surface, let glass,
            let viewport = owner.superview as? DocumentWebViewContainer
        else { return }
        let bounds = owner.bounds
        let width = min(preferredWidth, surface.kind == .selection ? bounds.width - 24 : 368, bounds.width - 24)
        let minimumTop = max(12, viewport.floatingContentTopInset + 12)
        let maximumBottom = bounds.height - 12
        guard maximumBottom > minimumTop else {
            dismiss()
            return
        }
        var height = min(height, 352, maximumBottom - minimumTop)
        let anchorX = surface.kind == .selection ? surface.left - width / 2 : surface.left
        let x = min(max(12, anchorX), bounds.width - width - 12)
        let below = surface.bottom + 8
        let top: CGFloat
        if surface.kind == .suggestions {
            let belowSpace = max(0, maximumBottom - max(minimumTop, below))
            let aboveSpace = max(0, surface.top - minimumTop - 8)
            if suggestionsBelow == nil {
                let fullListHeight =
                    CGFloat(ScholiumMetrics.Completion.maximumVisibleRows)
                    * ScholiumMetrics.Completion.detailedRowHeight + (suggestions?.nativeVerticalPadding ?? 0)
                suggestionsBelow = belowSpace >= min(fullListHeight, maximumBottom - minimumTop) || belowSpace >= aboveSpace
            }
            let opensBelow = suggestionsBelow == true
            height = min(height, opensBelow ? belowSpace : aboveSpace)
            top = opensBelow ? max(minimumTop, below) : max(minimumTop, surface.top - height - 8)
        } else {
            top =
                max(minimumTop, below) + height <= maximumBottom
                ? max(minimumTop, below)
                : max(minimumTop, surface.top - height - 8)
        }
        let rect = NSRect(
            x: x, y: owner.isFlipped ? top : bounds.height - top - height,
            width: width, height: height)
        glass.frame = owner.convert(rect, to: glass.superview)
        glass.contentView?.frame = glass.bounds
    }

}

private final class TrackingGlassView: NSGlassEffectView {
    var onPointerPresence: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { onPointerPresence?(true) }
    override func mouseExited(with event: NSEvent) { onPointerPresence?(false) }
}

extension DocumentFloatingSurfaceController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === resultPopover else { return }
        resultPopover = nil
        send(.dismiss)
        dismiss()
    }
}
