import AppKit
import SwiftUI

/// SwiftUI owns the selected category, search and retained page state. AppKit
/// projects that selection into one native preferences toolbar and owns its
/// window boundary; the coordinator only translates selection intents.
struct ScholiumSettingsNavigationHost<Page: View>: NSViewControllerRepresentable {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.agentChatSettingsController) private var chatController
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.controlSize) private var controlSize

    @Binding var selection: ScholiumSettingsDestination
    let page: Page

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSViewController(context: Context) -> SettingsNavigationController {
        SettingsNavigationController(
            selection: selection, locale: locale, page: project(page),
            onSelect: { [weak coordinator = context.coordinator] destination in
                coordinator?.selection.wrappedValue = destination
            })
    }

    func updateNSViewController(_ controller: SettingsNavigationController, context: Context) {
        context.coordinator.selection = $selection
        controller.pageController.rootView = project(page)
        controller.update(selection: selection, locale: locale)
    }

    static func dismantleNSViewController(_ controller: SettingsNavigationController, coordinator: Coordinator) {
        controller.detachToolbar()
        controller.onSelect = { _ in }
        controller.pageController.rootView = AnyView(EmptyView())
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

    @MainActor
    final class Coordinator {
        var selection: Binding<ScholiumSettingsDestination>

        init(selection: Binding<ScholiumSettingsDestination>) {
            self.selection = selection
        }
    }
}

@MainActor
final class SettingsNavigationController: NSViewController, NSToolbarDelegate {
    let pageController: NSHostingController<AnyView>
    var onSelect: (ScholiumSettingsDestination) -> Void

    // This is the last SwiftUI projection, never an independent navigation state.
    private var projectedSelection: ScholiumSettingsDestination
    private var locale: Locale
    private weak var installedWindow: NSWindow?
    private lazy var settingsToolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: "scholium.settings.toolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        return toolbar
    }()

    init(
        selection: ScholiumSettingsDestination, locale: Locale,
        page: AnyView, onSelect: @escaping (ScholiumSettingsDestination) -> Void
    ) {
        projectedSelection = selection
        self.locale = locale
        self.onSelect = onSelect
        pageController = NSHostingController(rootView: page)
        pageController.sizingOptions = []
        pageController.sceneBridgingOptions = []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Settings navigation is code-only") }

    override func loadView() {
        let root = NSView()
        view = root
        addChild(pageController)
        let content = pageController.view
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        let safeArea = root.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            content.topAnchor.constraint(equalTo: safeArea.topAnchor),
            content.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        attachToolbar()
    }

    func update(selection: ScholiumSettingsDestination, locale: Locale) {
        projectedSelection = selection
        self.locale = locale
        for item in settingsToolbar.items {
            guard let destination = destination(for: item.itemIdentifier) else { continue }
            configure(item, for: destination)
        }
        attachToolbar()
    }

    func attachToolbar() {
        guard let window = view.window else { return }
        if installedWindow !== window {
            detachToolbar()
            installedWindow = window
        }
        if !window.styleMask.contains(.resizable) { window.styleMask.insert(.resizable) }
        if window.tabbingMode != .disallowed { window.tabbingMode = .disallowed }
        if window.toolbarStyle != .preference { window.toolbarStyle = .preference }
        if window.titleVisibility != .visible { window.titleVisibility = .visible }
        if window.backgroundColor != .windowBackgroundColor { window.backgroundColor = .windowBackgroundColor }
        let title = localized(projectedSelection.title)
        if window.title != title { window.title = title }
        if window.toolbar !== settingsToolbar { window.toolbar = settingsToolbar }
        if !settingsToolbar.isVisible { settingsToolbar.isVisible = true }
        let selectedIdentifier = itemIdentifier(for: projectedSelection)
        if settingsToolbar.selectedItemIdentifier != selectedIdentifier {
            settingsToolbar.selectedItemIdentifier = selectedIdentifier
        }
    }

    func detachToolbar() {
        if installedWindow?.toolbar === settingsToolbar { installedWindow?.toolbar = nil }
        installedWindow = nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ScholiumSettingsDestination.allCases.map(itemIdentifier(for:))
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar: Bool
    ) -> NSToolbarItem? {
        guard let destination = destination(for: identifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: destination.symbol, accessibilityDescription: nil)
        item.target = self
        item.action = #selector(selectPane(_:))
        item.autovalidates = false
        configure(item, for: destination)
        return item
    }

    private func configure(_ item: NSToolbarItem, for destination: ScholiumSettingsDestination) {
        let label = localized(destination.toolbarTitle)
        let title = localized(destination.title)
        if item.label != label { item.label = label }
        if item.paletteLabel != title { item.paletteLabel = title }
        if item.toolTip != title { item.toolTip = title }
        if item.menuFormRepresentation == nil {
            let menuItem = NSMenuItem(title: label, action: #selector(selectPane(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = destination.rawValue
            item.menuFormRepresentation = menuItem
        }
        let menuItem = item.menuFormRepresentation!
        if menuItem.title != label { menuItem.title = label }
        let state: NSControl.StateValue = destination == projectedSelection ? .on : .off
        if menuItem.state != state { menuItem.state = state }
    }

    @objc private func selectPane(_ sender: Any?) {
        let selectedDestination: ScholiumSettingsDestination?
        switch sender {
        case let item as NSToolbarItem:
            selectedDestination = destination(for: item.itemIdentifier)
        case let item as NSMenuItem:
            selectedDestination = (item.representedObject as? String).flatMap(ScholiumSettingsDestination.init(rawValue:))
        default:
            selectedDestination = nil
        }
        guard let selectedDestination else { return }
        // Clicking the selected pane is still an explicit navigation intent:
        // the SwiftUI owner may need to leave a temporary search route.
        onSelect(selectedDestination)
    }

    private func itemIdentifier(for destination: ScholiumSettingsDestination) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("scholium.settings.category.\(destination.rawValue)")
    }

    private func destination(for identifier: NSToolbarItem.Identifier) -> ScholiumSettingsDestination? {
        ScholiumSettingsDestination.allCases.first { itemIdentifier(for: $0) == identifier }
    }

    private func localized(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}
