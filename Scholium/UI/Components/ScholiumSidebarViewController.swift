import AppKit
import SwiftUI

/// The selected page changes immediately; Core Animation presents its old and
/// new contents without giving the hidden page another interaction route.
@MainActor
private final class SidebarPageTransitionView: NSView {
    static let animationKey = kCATransition

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopTransition() }
    }

    override func viewDidHide() {
        super.viewDidHide()
        stopTransition()
    }

    func stopTransition() { layer?.removeAnimation(forKey: Self.animationKey) }
}

/// The split item owns size; these persistent hosts own their SwiftUI state.
/// Only the selected page participates in native event and tooltip tracking.
@MainActor
final class ScholiumSidebarViewController<Library: View, Chat: View>: NSViewController {
    let libraryHost: NSHostingController<Library>
    let chatHost: NSHostingController<Chat>
    private var selection: SidebarContent

    init(library: Library, chat: Chat, selection: SidebarContent) {
        libraryHost = NSHostingController(rootView: library)
        chatHost = NSHostingController(rootView: chat)
        self.selection = selection
        super.init(nibName: nil, bundle: nil)
        // Disclosure content may grow inside the page, never the window.
        libraryHost.sizingOptions = []
        chatHost.sizingOptions = []
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only sidebar") }

    override func loadView() {
        let container = SidebarPageTransitionView()
        container.wantsLayer = true
        view = container
        for controller in [libraryHost as NSViewController, chatHost] {
            addChild(controller)
            let content = controller.view
            content.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
        }
        synchronizeVisibility()
    }

    override func viewDidDisappear() {
        (view as? SidebarPageTransitionView)?.stopTransition()
        super.viewDidDisappear()
    }

    func update(library: Library, chat: Chat, selection: SidebarContent) {
        let switched = self.selection != selection
        if isViewLoaded {
            if switched {
                beginPageTransition()
            } else if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                (view as? SidebarPageTransitionView)?.stopTransition()
            }
        }
        libraryHost.rootView = library
        chatHost.rootView = chat
        self.selection = selection
        if isViewLoaded { synchronizeVisibility() }
    }

    private func beginPageTransition() {
        guard let container = view as? SidebarPageTransitionView else { return }
        container.stopTransition()
        guard let window = container.window, window.isVisible,
            !container.isHiddenOrHasHiddenAncestor,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }

        container.layoutSubtreeIfNeeded()
        let transition = CATransition()
        transition.type = .fade
        transition.duration = ScholiumMotion.sidebarPageDuration
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        container.layer?.add(transition, forKey: SidebarPageTransitionView.animationKey)
    }

    @objc private func displayOptionsDidChange(_ notification: Notification) {
        if isViewLoaded && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            (view as? SidebarPageTransitionView)?.stopTransition()
        }
    }

    private func synchronizeVisibility() {
        let hidden = selection == .chat ? libraryHost.view : chatHost.view
        if let responder = view.window?.firstResponder as? NSView,
            responder === hidden || responder.isDescendant(of: hidden)
        {
            view.window?.makeFirstResponder(nil)
        }
        libraryHost.view.isHidden = selection != .triptych
        chatHost.view.isHidden = selection != .chat
    }
}
