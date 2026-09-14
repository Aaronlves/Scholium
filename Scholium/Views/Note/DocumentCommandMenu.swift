import AppKit
import WebKit

/// AppKit owns tracking and selection; the document revalidates and applies commands.
@MainActor
final class DocumentCommandMenu: NSObject {
    let menu: NSMenu
    private let surface: DocumentFloatingSurface
    private var cancelled = false
    private var chosenIndex: Int?
    var onEvent: ((String, Int) -> Void)?
    private var observations: [NSObjectProtocol] = []

    init(surface: DocumentFloatingSurface) {
        self.surface = surface
        menu = NSMenu()
        super.init()
        menu.identifier = .init("scholium.documentCommands")
        menu.autoenablesItems = false
        menu.allowsContextMenuPlugIns = false
        for (index, candidate) in surface.items.enumerated() {
            let item = NSMenuItem(title: candidate.label, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
    }

    func present(in owner: WKWebView) {
        guard let window = owner.window else { return }
        for name in [NSWindow.willCloseNotification, NSWindow.didResizeNotification, NSWindow.didResignKeyNotification] {
            observations.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.dismiss() }
                })
        }
        // Unwind the WebKit input event before starting AppKit's menu tracking loop.
        DispatchQueue.main.async { [weak self, weak owner] in
            guard let self, let owner, owner.window === window, !self.cancelled else { return }
            let point = NSPoint(
                x: min(max(0, self.surface.left), owner.bounds.width),
                y: owner.isFlipped ? self.surface.bottom : owner.bounds.height - self.surface.bottom)
            self.menu.popUp(positioning: nil, at: point, in: owner)
            self.removeObservations()
            guard !self.cancelled else { return }
            if let chosenIndex = self.chosenIndex { self.onEvent?("choose", chosenIndex) } else { self.onEvent?("dismiss", -1) }
        }
    }

    func dismiss() {
        cancelled = true
        menu.cancelTrackingWithoutAnimation()
        removeObservations()
    }

    private func removeObservations() {
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
        observations.removeAll()
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard !cancelled, menu.items.contains(item), surface.items.indices.contains(item.tag) else { return }
        chosenIndex = item.tag
    }
}
