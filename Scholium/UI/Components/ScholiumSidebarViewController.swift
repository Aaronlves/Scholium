import AppKit
import SwiftUI

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only sidebar") }

    override func loadView() {
        view = NSView()
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

    func update(library: Library, chat: Chat, selection: SidebarContent) {
        libraryHost.rootView = library
        chatHost.rootView = chat
        self.selection = selection
        if isViewLoaded { synchronizeVisibility() }
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
