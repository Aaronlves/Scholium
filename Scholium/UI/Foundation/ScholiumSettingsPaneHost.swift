import AppKit
import SwiftUI

/// SwiftUI owns the selected category and each pane's feature state. NSTabView
/// owns attachment, layout and responder membership for the selected pane;
/// the coordinator retains previously visited hosts without another selection
/// model, geometry policy or transition animation.
struct ScholiumSettingsPaneHost<Selection: Hashable, Content: View>: NSViewRepresentable {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.agentChatSettingsController) private var chatController
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.controlSize) private var controlSize

    let selection: Selection
    let identifier: String?
    private let content: (Selection) -> Content

    init(selection: Selection, identifier: String? = nil, @ViewBuilder content: @escaping (Selection) -> Content) {
        self.selection = selection
        self.identifier = identifier
        self.content = content
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SettingsPaneTabView {
        let tabView = SettingsPaneTabView()
        tabView.tabPosition = .none
        tabView.tabViewBorderType = .none
        tabView.drawsBackground = false
        if let identifier { tabView.setAccessibilityIdentifier(identifier) }
        tabView.delegate = context.coordinator
        return tabView
    }

    func updateNSView(_ tabView: SettingsPaneTabView, context: Context) {
        // Forward declared Settings dependencies and public presentation values.
        // Each host owns its accessibility graph and reads system adaptation
        // directly instead of inheriting the outer hosting graph's context.
        context.coordinator.present(
            selection,
            root: AnyView(
                content(selection)
                    .environmentObject(settingsModel)
                    .environment(\.agentChatSettingsController, chatController)
                    .environment(\.scholiumFileSelectionPresenter, fileSelectionPresenter)
                    .environment(\.openURL, openURL)
                    .environment(\.locale, locale)
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.layoutDirection, layoutDirection)
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
                    .environment(\.controlSize, controlSize)
                    .buttonStyle(.automatic)
                    .tint(nil)
            ),
            in: tabView
        )
    }

    static func dismantleNSView(_ tabView: SettingsPaneTabView, coordinator: Coordinator) {
        coordinator.dismantle(tabView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTabViewDelegate {
        private var items: [Selection: NSTabViewItem] = [:]
        private weak var requestedItem: NSTabViewItem?

        func present(_ selection: Selection, root: AnyView, in tabView: NSTabView) {
            let item: NSTabViewItem
            if let existing = items[selection], let host = existing.view as? NSHostingView<AnyView> {
                item = existing
                host.rootView = root
            } else {
                let host = NSHostingView(rootView: root)
                // The containing Settings scene supplies the available size.
                // A pane's intrinsic size must not resize its window.
                host.sizingOptions = []
                host.sceneBridgingOptions = []
                host.autoresizingMask = [.width, .height]
                item = NSTabViewItem(identifier: selection)
                item.view = host
                items[selection] = item
            }

            requestedItem = item
            if item.tabView == nil {
                tabView.addTabViewItem(item)
            }
            guard tabView.selectedTabViewItem !== item else { return }
            releaseFirstResponder(in: tabView.selectedTabViewItem?.view)
            tabView.selectTabViewItem(item)
            NSAccessibility.post(element: tabView, notification: .layoutChanged)
        }

        func tabView(_ tabView: NSTabView, shouldSelect tabViewItem: NSTabViewItem?) -> Bool {
            // Hidden tabs have no navigation controls. Reject native next/previous
            // responder actions that would bypass the SwiftUI selection owner.
            tabViewItem === requestedItem
        }

        func dismantle(_ tabView: NSTabView) {
            releaseFirstResponder(in: tabView.selectedTabViewItem?.view)
            tabView.delegate = nil
            tabView.tabViewItems = []
            requestedItem = nil
            items.removeAll()
        }

        private func releaseFirstResponder(in outgoingView: NSView?) {
            guard let outgoingView, let window = outgoingView.window,
                let responder = window.firstResponder as? NSView
            else { return }

            let fieldOwner = (responder as? NSTextView)?.delegate as? NSView
            if responder.isDescendant(of: outgoingView)
                || fieldOwner?.isDescendant(of: outgoingView) == true
            {
                window.makeFirstResponder(nil)
            }
        }
    }
}

/// Borderless tabs are an attachment mechanism, not a second category picker.
/// Project only the selected host's existing accessibility elements; NSTabView's
/// default tab-strip accessibility does not expose these tabless contents.
final class SettingsPaneTabView: NSTabView {
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityChildren() -> [Any]? {
        guard let selectedView = selectedTabViewItem?.view else { return [] }
        return NSAccessibility.unignoredChildren(from: [selectedView])
    }

    override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? {
        accessibilityChildren()?.compactMap { $0 as? any NSAccessibilityElementProtocol }
    }
}
