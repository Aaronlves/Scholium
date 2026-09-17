import AppKit
import SwiftUI

extension EnvironmentValues {
    /// A projection of category selection, including any containing Settings pane.
    @Entry var scholiumSettingsPaneIsActive = true
}

extension View {
    /// Register the default action only while its Settings page is active.
    func scholiumSettingsDefaultAction() -> some View {
        modifier(SettingsDefaultAction())
    }
}

private struct SettingsDefaultAction: ViewModifier {
    @Environment(\.scholiumSettingsPaneIsActive) private var isActive

    func body(content: Content) -> some View {
        content.keyboardShortcut(isActive ? .defaultAction : nil)
    }
}

/// SwiftUI owns selection and feature state. The native container retains visited
/// hosts in the window, hides inactive content and sizes only the selected host.
/// The coordinator projects selection into visibility and activation; it owns no
/// independent navigation, draft, geometry or animation policy.
struct ScholiumSettingsPaneHost<Selection: Hashable, Content: View>: NSViewRepresentable {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.agentChatSettingsController) private var chatController
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.openURL) private var openURL
    @Environment(\.scholiumSettingsSearchTarget) private var searchTarget
    @Environment(\.scholiumSettingsSearchRevision) private var searchRevision
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.controlSize) private var controlSize
    @Environment(\.scholiumSettingsPaneIsActive) private var ancestorIsActive

    let selection: Selection
    let identifier: String?
    private let content: (Selection) -> Content

    init(
        selection: Selection, identifier: String? = nil,
        @ViewBuilder content: @escaping (Selection) -> Content
    ) {
        self.selection = selection
        self.identifier = identifier
        self.content = content
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SettingsPaneContainerView {
        let container = SettingsPaneContainerView()
        if let identifier { container.setAccessibilityIdentifier(identifier) }
        return container
    }

    func updateNSView(_ container: SettingsPaneContainerView, context: Context) {
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
                    .environment(\.scholiumSettingsSearchTarget, searchTarget)
                    .environment(\.scholiumSettingsSearchRevision, searchRevision)
                    .environment(\.locale, locale)
                    .environment(\.colorScheme, colorScheme)
                    .environment(\.layoutDirection, layoutDirection)
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
                    .environment(\.controlSize, controlSize)
                    .buttonStyle(.automatic)
                    .tint(nil)
            ),
            isActive: ancestorIsActive,
            in: container
        )
    }

    static func dismantleNSView(_ container: SettingsPaneContainerView, coordinator: Coordinator) {
        coordinator.dismantle(container)
    }

    @MainActor
    final class Coordinator {
        @MainActor
        private final class Entry {
            let host: NSHostingView<AnyView>
            var content: AnyView
            private(set) var isActive = false

            init(content: AnyView) {
                self.content = content
                host = NSHostingView(rootView: content)
                host.sizingOptions = []
                host.sceneBridgingOptions = []
                host.isHidden = true
            }

            func update(isActive: Bool) {
                self.isActive = isActive
                host.rootView = AnyView(
                    content
                        .environment(\.scholiumSettingsPaneIsActive, isActive)
                )
            }
        }

        private var entries: [Selection: Entry] = [:]

        func present(
            _ selection: Selection, root: AnyView, isActive: Bool, in container: SettingsPaneContainerView
        ) {
            let entry: Entry
            if let existing = entries[selection] {
                entry = existing
                entry.content = root
            } else {
                entry = Entry(content: root)
                entries[selection] = entry
            }
            for other in entries.values where other !== entry && other.isActive {
                other.update(isActive: false)
            }
            entry.update(isActive: isActive)
            container.show(entry.host)
        }

        func dismantle(_ container: SettingsPaneContainerView) {
            container.removeContents()
            entries.removeAll()
        }
    }
}

/// Keeping visited hosts attached avoids NSTabView's eager key-view-loop layout
/// on every selection. Native hiding excludes inactive input and drawing; the
/// accessibility projection exposes only the active host. SwiftUI's inherited
/// active flag also unregisters hidden default actions and gates activation tasks.
final class SettingsPaneContainerView: NSView {
    private(set) weak var selectedView: NSView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        autoresizesSubviews = false
    }

    func show(_ view: NSView) {
        guard selectedView !== view else { return }
        releaseFirstResponder()
        selectedView?.isHidden = true
        if view.superview !== self {
            view.isHidden = true
            view.frame = bounds
            addSubview(view)
        }
        selectedView = view
        if view.frame != bounds { view.frame = bounds }
        view.isHidden = false
        needsLayout = true
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    override func layout() {
        super.layout()
        if let selectedView, selectedView.frame != bounds { selectedView.frame = bounds }
    }

    func removeContents() {
        releaseFirstResponder()
        selectedView = nil
        subviews.forEach { $0.removeFromSuperview() }
    }

    private func releaseFirstResponder() {
        guard let selectedView, let window,
            let responder = window.firstResponder as? NSView
        else { return }
        let fieldOwner = (responder as? NSTextView)?.delegate as? NSView
        if responder.isDescendant(of: selectedView)
            || fieldOwner?.isDescendant(of: selectedView) == true
        {
            window.makeFirstResponder(nil)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? {
        guard let selectedView else { return [] }
        return NSAccessibility.unignoredChildren(from: [selectedView])
    }
    override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? {
        accessibilityChildren()?.compactMap { $0 as? any NSAccessibilityElementProtocol }
    }
}
