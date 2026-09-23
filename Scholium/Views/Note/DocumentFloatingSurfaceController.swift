import AppKit
import SwiftUI
import WebKit

/// A bounded read-only preview projection, never an editor/source operation.
struct DocumentPreviewSurface: Codable, Equatable, Sendable {
    let id: Int
    let left: Double
    let top: Double
    let bottom: Double
    let html: String
    let css: String
}

/// A bounded read-only completion projection, never an editor/source operation.
struct DocumentSuggestionSurface: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        let label: String
        let detail: String
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

struct DocumentFloatingDismissal: Codable, Equatable, Sendable {
    let kind: DocumentFloatingKind
    let id: Int
}

enum DocumentFloatingEvent: Equatable, Sendable {
    case preview(DocumentPreviewSurface)
    case suggestions(DocumentSuggestionSurface)
    case selection(DocumentSelectionSurface)
    case dismiss(DocumentFloatingDismissal)

    var kind: DocumentFloatingKind? {
        switch self {
        case .preview: .preview
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
            Set(value.keys) == ["type", "surface"] || Set(value.keys) == ["type", "kind", "id"],
            JSONSerialization.isValidJSONObject(value),
            let type = value["type"] as? String
        else { return nil }

        switch type {
        case "previewSurface":
            guard Set(value.keys) == ["type", "surface"],
                let object = value["surface"] as? [String: Any],
                Set(object.keys) == ["id", "left", "top", "bottom", "html", "css"],
                let data = try? JSONSerialization.data(withJSONObject: object),
                data.count <= 1_500_000,
                let result = try? JSONDecoder().decode(DocumentPreviewSurface.self, from: data),
                result.id > 0,
                [result.left, result.top, result.bottom].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
                result.bottom >= result.top,
                !result.html.isEmpty,
                result.html.utf8.count <= 500_000,
                result.css.utf8.count <= 900_000
            else { return nil }
            return .preview(result)
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
                Set(object.keys) == ["id", "left", "top", "bottom"],
                let data = try? JSONSerialization.data(withJSONObject: object),
                data.count <= 100_000,
                let result = try? JSONDecoder().decode(DocumentSelectionSurface.self, from: data),
                result.id > 0,
                [result.left, result.top, result.bottom].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
                result.bottom >= result.top
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
}

/// Owns only native floating presentation in the originating document viewport.
/// No source mirror, editing history, or independent completion state.
@MainActor
final class DocumentFloatingSurfaceController: NSObject {
    private weak var owner: NSView?
    private var surface: ActiveDocumentFloatingSurface?
    private var glass: TrackingGlassView?
    private var preview: DocumentPreviewPopover?
    private var suggestions: NativeFloatingChoiceList?
    private var preferredWidth: CGFloat = 368
    private var suggestionsBelow: Bool?
    var previewWebView: WKWebView? { preview?.webView }
    var isPreviewShown: Bool { preview?.isShown == true }
    private var event: ((Int, DocumentFloatingAction, Int) async -> Bool)?
    private var selectionBar: SelectionActionBar?
    var selectionResultPopover: NSPopover? { resultPopover }
    private var resultPopover: NSPopover?
    private var inquiryTask: Task<Void, Never>?
    private var inquiryID: UUID?
    private var observers: [NSObjectProtocol] = []

    func present(
        _ value: DocumentFloatingEvent,
        in webView: NSView,
        inquire: AgentSelectionInquiryHandler? = nil,
        event: @escaping (Int, DocumentFloatingAction, Int) async -> Bool
    ) {
        if case .dismiss(let value) = value {
            if surface?.id == value.id, surface?.kind == value.kind { dismiss() }
            return
        }
        guard webView.window != nil, webView.bounds.width > 24, webView.bounds.height > 24,
            let viewport = webView.superview
        else { return }
        let next: ActiveDocumentFloatingSurface
        switch value {
        case .preview(let preview):
            next = ActiveDocumentFloatingSurface(
                id: preview.id, kind: .preview, left: preview.left, top: preview.top, bottom: preview.bottom)
        case .suggestions(let suggestions):
            next = ActiveDocumentFloatingSurface(
                id: suggestions.id, kind: .suggestions, left: suggestions.left, top: suggestions.top, bottom: suggestions.bottom)
        case .selection(let selection):
            guard selection.bottom + 52 <= webView.bounds.height - 12 || selection.top >= 64 else {
                dismiss()
                return
            }
            next = ActiveDocumentFloatingSurface(
                id: selection.id, kind: .selection, left: selection.left, top: selection.top, bottom: selection.bottom)
        case .dismiss:
            return
        }
        if owner === webView, let surface, next.id <= surface.id { return }
        if owner !== webView {
            reset()
        } else if surface?.kind != next.kind || (surface?.kind == .selection && surface?.id != next.id) {
            dismiss()
        }
        self.event = event
        self.owner = webView
        self.surface = next
        if case .preview(let value) = value {
            let content = preview ?? DocumentPreviewPopover()
            preview = content
            content.onEvent = { [weak self] action in
                self?.send(action)
                if action == .dismiss { self?.dismiss() }
            }
            content.present(value, in: webView)
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
                        guard let self, self.resultPopover == nil, let owner = self.owner,
                            let firstResponder = owner.window?.firstResponder as? NSView
                        else { return }
                        let responder = (firstResponder as? NSTextView)?.delegate as? NSView ?? firstResponder
                        guard responder !== owner, !responder.isDescendant(of: owner),
                            self.glass.map({ !responder.isDescendant(of: $0) }) == true
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
        }
        guard let glass else { return }
        switch value {
        case .suggestions(let value):
            let exposesNativeChoices = !(webView is WKWebView)
            let content =
                suggestions
                ?? NativeFloatingChoiceList(
                    acceptsKeyboard: false, exposesAccessibility: exposesNativeChoices)
            let isNewList = suggestions == nil
            if isNewList {
                suggestions = content
                glass.contentView = content
            }
            content.choose = { [weak self] index in self?.send(.choose, index: index) }
            content.select = { [weak self] index in self?.send(.select, index: index) }
            content.update(items: value.items.map { .init(label: $0.label, detail: $0.detail) }, selected: value.selected)
            preferredWidth = isNewList ? content.preferredSize.width : max(preferredWidth, content.preferredSize.width)
            // Native editors keep typing focus while AppKit exposes the choices.
            // A web host keeps its own AX suggestion tree.
            glass.setAccessibilityElement(true)
            glass.setAccessibilityRole(.group)
            glass.setAccessibilityLabel(ScholiumL10n.string("Suggestions"))
            glass.setAccessibilityIdentifier("scholium.documentSuggestions")
            glass.setAccessibilityChildren(exposesNativeChoices ? [content] : [])
            layout(height: content.preferredSize.height)
        case .preview: break  // Owned by DocumentPreviewPopover above.
        case .selection:
            suggestions = nil
            let bar = SelectionActionBar(actions: SelectionActionPreferences.shared.actions)
            selectionBar = bar
            bar.onDismiss = { [weak self] in
                self?.send(.dismiss)
                self?.dismiss()
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
            glass.contentView = bar
            glass.cornerRadius = 20
            if #available(macOS 27.0, *) { glass.effectIsInteractive = true }
            glass.setAccessibilityElement(false)
            glass.setAccessibilityChildren([bar])
            preferredWidth = bar.preferredSize.width
            layout(height: bar.preferredSize.height)
        case .dismiss: break
        }
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
        selectionBar = nil
        glass?.onPointerPresence = nil
        glass?.removeFromSuperview()
        glass = nil
        let bounds = owner.bounds
        let top = min(max(0, surface.top), bounds.height)
        let bottom = min(max(top, surface.bottom), bounds.height)
        let anchor = NSRect(
            x: min(max(0, surface.left), bounds.width - 1),
            y: owner.isFlipped ? top : bounds.height - bottom,
            width: 1, height: max(1, bottom - top))
        popover.show(relativeTo: anchor, of: owner, preferredEdge: owner.isFlipped ? .maxY : .minY)
    }

    func dismiss() {
        suggestionsBelow = nil
        inquiryTask?.cancel()
        inquiryTask = nil
        inquiryID = nil
        resultPopover?.close()
        resultPopover = nil
        selectionBar = nil
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
        guard let owner, let surface, let glass else { return }
        let bounds = owner.bounds
        let width = min(preferredWidth, surface.kind == .selection ? bounds.width - 24 : 368, bounds.width - 24)
        var height = min(height, 352, bounds.height - 24)
        let anchorX = surface.kind == .selection ? surface.left - width / 2 : surface.left
        let x = min(max(12, anchorX), bounds.width - width - 12)
        let below = surface.bottom + 8
        let top: CGFloat
        if surface.kind == .suggestions {
            let belowSpace = max(0, bounds.height - 12 - below)
            let aboveSpace = max(0, surface.top - 20)
            if suggestionsBelow == nil {
                let fullListHeight =
                    CGFloat(ScholiumMetrics.Completion.maximumVisibleRows)
                    * ScholiumMetrics.Completion.detailedRowHeight + 12
                suggestionsBelow = belowSpace >= min(fullListHeight, bounds.height - 24) || belowSpace >= aboveSpace
            }
            let opensBelow = suggestionsBelow == true
            height = min(height, opensBelow ? belowSpace : aboveSpace)
            top = opensBelow ? below : surface.top - height - 8
        } else {
            top = below + height <= bounds.height - 12 ? below : max(12, surface.top - height - 8)
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
