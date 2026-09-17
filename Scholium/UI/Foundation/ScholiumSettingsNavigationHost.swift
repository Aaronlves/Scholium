import AppKit
import SwiftUI

/// AppKit owns sidebar material, window adaptation and the fixed navigation
/// boundary. SwiftUI retains category selection, search and page state.
struct ScholiumSettingsNavigationHost<Sidebar: View, Page: View>: NSViewControllerRepresentable {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.agentChatSettingsController) private var chatController
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.controlSize) private var controlSize

    let title: LocalizedStringResource
    let sidebar: Sidebar
    let page: Page

    func makeNSViewController(context: Context) -> SettingsNavigationSplitController {
        SettingsNavigationSplitController(title: localizedTitle, sidebar: project(sidebar), page: project(page))
    }

    func updateNSViewController(_ controller: SettingsNavigationSplitController, context: Context) {
        controller.sidebarController.rootView = project(sidebar)
        controller.pageController.rootView = project(page)
        controller.updateTitle(localizedTitle)
    }

    static func dismantleNSViewController(_ controller: SettingsNavigationSplitController, coordinator: ()) {
        controller.detachToolbar()
        controller.sidebarController.rootView = AnyView(EmptyView())
        controller.pageController.rootView = AnyView(EmptyView())
    }

    private var localizedTitle: String {
        var resource = title
        resource.locale = locale
        return String(localized: resource)
    }

    private func project<V: View>(_ view: V) -> AnyView {
        AnyView(
            view
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
                .tint(nil))
    }
}

@MainActor
final class SettingsNavigationSplitController: NSSplitViewController, NSToolbarDelegate {
    let sidebarController: NSHostingController<AnyView>
    let pageController: NSHostingController<AnyView>

    private var pageTitle: String
    private weak var installedWindow: NSWindow?
    private lazy var settingsToolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: "scholium.settings.toolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        return toolbar
    }()

    init(title: String = "", sidebar: AnyView, page: AnyView) {
        pageTitle = title
        sidebarController = NSHostingController(rootView: sidebar)
        pageController = NSHostingController(rootView: page)
        sidebarController.sizingOptions = []
        pageController.sizingOptions = []
        sidebarController.sceneBridgingOptions = []
        pageController.sceneBridgingOptions = []
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        let navigation = NSSplitViewItem(sidebarWithViewController: sidebarController)
        navigation.canCollapse = false
        navigation.canCollapseFromWindowResize = false
        navigation.minimumThickness = ScholiumMetrics.Settings.navigationWidth
        navigation.maximumThickness = ScholiumMetrics.Settings.navigationWidth
        navigation.allowsFullHeightLayout = true
        let content = NSSplitViewItem(viewController: pageController)
        content.canCollapse = false
        content.canCollapseFromWindowResize = false
        addSplitViewItem(navigation)
        addSplitViewItem(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Settings navigation is code-only") }

    override func viewDidAppear() {
        super.viewDidAppear()
        attachToolbar()
    }

    func updateTitle(_ title: String) {
        pageTitle = title
        attachToolbar()
    }

    /// The toolbar and split view share one native owner. A tracking separator
    /// associates each titlebar section with its corresponding split item.
    func attachToolbar() {
        guard let window = view.window else { return }
        window.title = pageTitle
        applyWindowMask(to: window)
        guard installedWindow !== window else { return }
        installedWindow = window
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.toolbar = settingsToolbar
        // The Settings scene finishes its initial window-mask transaction after
        // attachment; apply the native full-height/resizing mask afterwards.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.installedWindow === window else { return }
            self.applyWindowMask(to: window)
        }
    }

    private func applyWindowMask(to window: NSWindow) {
        let required: NSWindow.StyleMask = [.resizable, .fullSizeContentView]
        if !window.styleMask.isSuperset(of: required) {
            window.styleMask.formUnion(required)
        }
    }

    func detachToolbar() {
        if installedWindow?.toolbar === settingsToolbar { installedWindow?.toolbar = nil }
        installedWindow = nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar: Bool
    ) -> NSToolbarItem? {
        guard identifier == .sidebarTrackingSeparator else { return nil }
        return NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 0)
    }

    override func splitView(
        _ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int
    ) -> NSRect {
        _ = super.splitView(splitView, effectiveRect: proposedEffectiveRect, forDrawnRect: drawnRect, ofDividerAt: dividerIndex)
        return .zero
    }

    override func splitView(_ splitView: NSSplitView, additionalEffectiveRectOfDividerAt dividerIndex: Int) -> NSRect {
        _ = super.splitView(splitView, additionalEffectiveRectOfDividerAt: dividerIndex)
        return .zero
    }
}
