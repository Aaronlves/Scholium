import AppKit
import Combine
import Foundation
import ScholiumContracts
import SwiftUI

/// The configured window has one native toolbar. Tracking separators establish
/// Library, Document, and Apparatus sections. Sidebar and document-history
/// controls belong to their Sidebar and Document sections respectively. The Inspector projection
/// control begins the Apparatus section and its visibility control ends it;
/// collapsing either pane changes no item topology.
@MainActor
final class ScholiumWorkspaceToolbarController: NSObject, NSToolbarDelegate, NSPopoverDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    static let toolbarIdentifier = NSToolbar.Identifier("scholium.workspaceToolbar")

    enum Item {
        static let notifications = NSToolbarItem.Identifier("scholium.toolbar.notifications")
        static let sidebar = NSToolbarItem.Identifier("scholium.toolbar.sidebar")
        static let back = NSToolbarItem.Identifier("scholium.toolbar.back")
        static let forward = NSToolbarItem.Identifier("scholium.toolbar.forward")
        static let inspector = NSToolbarItem.Identifier("scholium.toolbar.inspector")
        static let inspectorModes = NSToolbarItem.Identifier(
            "scholium.toolbar.inspectorModes"
        )
        // These identifiers are structural bounds for the Document toolbar.
        static let libraryDivider = NSToolbarItem.Identifier.sidebarTrackingSeparator
        static let documentTitle = NSToolbarItem.Identifier(
            "scholium.toolbar.documentTitle"
        )
        static let documentMode = NSToolbarItem.Identifier(
            "scholium.toolbar.documentMode"
        )
        static let settlement = NSToolbarItem.Identifier(
            "scholium.toolbar.settlement"
        )
        // Apparatus is an explicitly managed trailing split item rather than
        // AppKit's Inspector factory item. A private identifier keeps the
        // initializer's explicit dividerIndex authoritative instead of asking
        // AppKit to rediscover and regroup an Inspector section that no longer
        // exists.
        static let apparatusDivider = NSToolbarItem.Identifier(
            "scholium.toolbar.apparatusDivider"
        )
    }

    private var isInvalidated = false
    private var presentedSettlementTarget: DocumentSettlementTarget?
    private let appState: WindowModel
    private let windowActions: WorkspaceWindowActions
    private let splitViewController: NSSplitViewController
    private let toolbar: NSToolbar
    private let notificationsPopover = NSPopover()
    private weak var responderBeforeNotifications: NSResponder?
    private let settlementPopover: NSPopover
    private weak var window: NSWindow?
    private weak var responderBeforeSettlement: NSResponder?
    private var settlementPopoverHostingController: DocumentSettlementPopoverHostingController?
    private var presentationCancellables: Set<AnyCancellable> = []

    init(
        appState: WindowModel,
        windowActions: WorkspaceWindowActions,
        splitViewController: NSSplitViewController
    ) {
        self.appState = appState
        self.windowActions = windowActions
        self.splitViewController = splitViewController
        toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        settlementPopover = NSPopover()
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        settlementPopover.behavior = .transient
        settlementPopover.delegate = self
        notificationsPopover.behavior = .transient
        notificationsPopover.delegate = self
        observePresentation()
    }

    func install(in window: NSWindow) {
        guard !isInvalidated, splitViewController.splitView.window === window else { return }
        self.window = window
        window.titleVisibility = .hidden
        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
        installToolbarItemsIfNeeded()
        refreshPresentation()
    }

    func controls(_ candidate: NSSplitViewController) -> Bool {
        splitViewController === candidate
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        presentationCancellables.removeAll()
        responderBeforeSettlement = nil
        responderBeforeNotifications = nil
        settlementPopover.close()
        notificationsPopover.close()
        settlementPopover.contentViewController = nil
        notificationsPopover.contentViewController = nil
        settlementPopoverHostingController = nil
        presentedSettlementTarget = nil
        for item in toolbar.items {
            item.target = nil
            item.action = nil
            item.isEnabled = false
            item.menuFormRepresentation = nil
            if let control = item.view as? NSControl {
                control.target = nil
                control.action = nil
                control.isEnabled = false
            }
        }
        toolbar.delegate = nil
        window = nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            Item.sidebar,
            .flexibleSpace,
            .space,
            Item.notifications,
            Item.libraryDivider,
            Item.back,
            Item.forward,
            Item.documentTitle,
            .space,
            Item.documentMode,
            Item.settlement,
            Item.apparatusDivider,
            Item.inspectorModes,
            Item.inspector,
        ]
    }

    static var itemIdentifiers: [NSToolbarItem.Identifier] {
        [
            Item.sidebar,
            .flexibleSpace,
            .space,
            Item.notifications,
            Item.libraryDivider,
            Item.back,
            Item.forward,
            Item.documentTitle,
            .flexibleSpace,
            Item.settlement,
            .space,
            Item.documentMode,
            Item.apparatusDivider,
            Item.inspectorModes,
            .flexibleSpace,
            .space,
            Item.inspector,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Item.sidebar:
            return sidebarModeItem(identifier: itemIdentifier)
        case Item.notifications:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Open Triptych Notifications"),
                systemImage: "bell",
                action: #selector(showNotifications(_:)),
                visibilityPriority: .user
            )
            return item
        case Item.back:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Back"),
                systemImage: "arrow.left",
                action: #selector(goBack(_:))
            )
            item.isNavigational = true
            return item
        case Item.forward:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Forward"),
                systemImage: "arrow.right",
                action: #selector(goForward(_:))
            )
            item.isNavigational = true
            return item
        case Item.libraryDivider:
            let splitView = splitViewController.splitView
            let item = NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 0
            )
            item.visibilityPriority = .user
            return item
        case Item.documentTitle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let title = NSTextField(labelWithString: "")
            title.font = .systemFont(ofSize: NSFont.systemFontSize)
            title.textColor = .secondaryLabelColor
            title.lineBreakMode = .byTruncatingTail
            title.setAccessibilityIdentifier("scholium.toolbar.documentTitle")
            title.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
            item.view = title
            item.isNavigational = true
            item.visibilityPriority = .high
            return item
        case Item.documentMode:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document Mode"),
                systemImage: NotePresentationMode.livePreview.symbol,
                action: #selector(toggleDocumentMode(_:))
            )
            item.possibleLabels = Set(NotePresentationMode.allCases.map {
                ScholiumDocumentModeToolbarButtonPresentation(mode: $0)
                    .accessibilityLabel
            })
            return item
        case Item.settlement:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Settle"),
                systemImage: "bookmark",
                action: #selector(toggleSettlement(_:))
            )
            item.possibleLabels = [
                ScholiumL10n.string("Settle"),
                ScholiumL10n.string("Settled — Settle Again"),
                ScholiumL10n.string("Changed since settlement — Settle Again"),
                ScholiumL10n.string("Settlement Unavailable"),
            ]
            return item
        case Item.apparatusDivider:
            let splitView = splitViewController.splitView
            let item = NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 1
            )
            item.visibilityPriority = .user
            return item
        case Item.inspectorModes:
            return inspectorModeItem(identifier: itemIdentifier)
        case Item.inspector:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Research Inspector"),
                systemImage: "sidebar.trailing",
                action: #selector(toggleInspector(_:)),
                visibilityPriority: .user
            )
            item.possibleLabels = [
                ScholiumL10n.string("Hide Research Inspector"),
                ScholiumL10n.string("Show Research Inspector"),
            ]
            return item
        case .flexibleSpace, .space:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        default:
            return nil
        }
    }

    @objc private func showNotifications(_ sender: Any?) {
        guard isCommandEnabled(Item.notifications) else { return }
        let session = appState.attentionPopoverSession
        if session.isPresented(from: .toolbar) { session.dismiss() }
        else { windowActions.showAttention(.queue(anchor: .toolbar, workspaceSlot: nil, noteScope: nil)) }
    }

    private func refreshNotifications() {
        guard let item = toolbarItem(Item.notifications) else { return }
        let total = notificationTotal
        let value: String
        if let total {
            value = total == 0 ? ScholiumL10n.string("No notifications")
                : String.localizedStringWithFormat(ScholiumL10n.string("%lld notifications"), Int64(total))
        } else {
            value = notificationError == nil ? ScholiumL10n.string("Checking Notifications")
                : ScholiumL10n.string("Notifications Unavailable")
        }
        let label = ScholiumL10n.string("Open Triptych Notifications")
        update(item, label: label, systemImage: (total ?? 0) > 0 ? "bell.badge" : "bell",
               isEnabled: true, toolTip: "\(label) · \(value)", accessibilityValue: "\(label), \(value)")
        let session = appState.attentionPopoverSession
        if session.isPresented(from: .toolbar) {
            if !notificationsPopover.isShown {
                notificationsPopover.contentViewController = NSHostingController(rootView:
                    AttentionQueueView(presentation: session.presentation, session: session)
                        .scholiumButtonStyle(.automatic)
                        .frame(width: ScholiumMetrics.Attention.popoverWidth,
                               height: ScholiumMetrics.Attention.popoverHeight))
                responderBeforeNotifications = window?.firstResponder
                notificationsPopover.show(relativeTo: item)
            }
        } else if notificationsPopover.isShown { notificationsPopover.close() }
    }

    private var notificationTotal: Int? {
        let settlementCount = appState.researchController.researchSnapshot?
            .settlementRequirements.count
        let issueCount = AttentionPreferences.visibleTotalCount(
            catalog: appState.workspaceCatalog,
            assignment: appState.workspaceAssignment,
            dismissalLedgerData: UserDefaults.standard.data(forKey: AttentionPreferences.dismissalLedgerKey) ?? Data()
        )
        let agentChangeCount = appState.researchController.agentChanges?.count
        let knownTotal = (settlementCount ?? 0)
            + (issueCount ?? 0)
            + (agentChangeCount ?? 0)
        if knownTotal > 0 { return knownTotal }
        guard settlementCount != nil, issueCount != nil, agentChangeCount != nil else {
            return nil
        }
        return 0
    }

    private var notificationError: String? {
        if appState.workspaceCatalog == nil, let error = appState.workspaceCatalogError {
            return error
        }
        if appState.researchController.agentChanges == nil,
           let error = appState.researchController.agentChangesError {
            return error
        }
        if appState.researchController.researchSnapshot == nil,
           let error = appState.researchController.errorMessage {
            return error
        }
        return nil
    }

    private func installToolbarItemsIfNeeded() {
        if toolbar.itemIdentifiers != Self.itemIdentifiers {
            toolbar.itemIdentifiers = Self.itemIdentifiers
        }
    }

    private func actionItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        systemImage: String,
        action: Selector,
        visibilityPriority: NSToolbarItem.VisibilityPriority = .high
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        configure(
            item,
            label: label,
            systemImage: systemImage,
            visibilityPriority: visibilityPriority
        )
        item.target = self
        item.action = action
        let overflowItem = NSMenuItem(
            title: label,
            action: action,
            keyEquivalent: ""
        )
        overflowItem.target = self
        overflowItem.image = item.image
        item.menuFormRepresentation = overflowItem
        return item
    }

    private func inspectorModeItem(
        identifier: NSToolbarItem.Identifier
    ) -> NSToolbarItem {
        let label = ScholiumL10n.dynamicString("Research Inspector")
        let modes = ResearchInspectorMode.allCases
        let control = NSSegmentedControl(
            images: modes.compactMap {
                ScholiumNativeToolbarPresentation.symbol(named: $0.systemImage,
                    accessibilityDescription: ScholiumL10n.localized($0.interfaceTitleResource))
            },
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectInspectorMode(_:))
        )
        control.controlSize = ScholiumNativeToolbarPresentation.controlSize
        control.segmentStyle = .rounded
        control.setAccessibilityLabel(label)
        control.setAccessibilityIdentifier("scholium.inspectorMode")
        for (index, mode) in modes.enumerated() {
            control.setToolTip(
                ScholiumL10n.localized(mode.interfaceTitleResource),
                forSegment: index
            )
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.title = ""
        item.toolTip = label
        item.visibilityPriority = .user
        item.isBordered = false
        item.style = .plain
        item.view = control
        item.menuFormRepresentation = inspectorModeMenu()
        return item
    }

    private func configure(
        _ item: NSToolbarItem,
        label: String,
        systemImage: String,
        visibilityPriority: NSToolbarItem.VisibilityPriority
    ) {
        item.label = label
        item.paletteLabel = label
        item.title = ""
        item.toolTip = label
        item.image = ScholiumNativeToolbarPresentation.symbol(
            named: systemImage,
            accessibilityDescription: label
        )
        item.visibilityPriority = visibilityPriority
        // With no custom view, AppKit creates the toolbar control and owns its
        // geometry, Glass, hover, press, focus, contrast, and transparency.
        item.isBordered = true
        item.style = .plain
    }

    private func observePresentation() {
        let changes: [AnyPublisher<Void, Never>] = [
            appState.windowWorkspaceController.$state
                .dropFirst().receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.attentionPopoverSession.objectWillChange
                .receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.shellState.$sidebarContent.dropFirst().receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.shellState.$libraryVisible.dropFirst().receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.shellState.$colorScheme.dropFirst().receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.commandObservation.$revision
                .receive(on: DispatchQueue.main)
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.researchController.$researchSnapshot
                .receive(on: DispatchQueue.main)
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.shellState.$inspector
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .map { _ in () }
                .eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .sink { [weak self] in self?.refreshPresentation() }
            .store(in: &presentationCancellables)
    }

    private func refreshPresentation() {
        guard !isInvalidated else { return }
        let shellState = appState.shellState
        refreshNotifications()

        if let control = toolbarItem(Item.sidebar)?.view as? NSSegmentedControl {
            control.selectedSegment = shellState.libraryVisible ? shellState.sidebarContent.rawValue : -1
            let unavailable = !appState.canActivateOutline
            control.setEnabled(!unavailable, forSegment: SidebarContent.outline.rawValue)
            control.setToolTip(unavailable
                ? ScholiumL10n.string("No note open yet") : ScholiumL10n.string("Outline"),
                forSegment: SidebarContent.outline.rawValue)
        }

        if let item = toolbarItem(Item.back) {
            update(
                item,
                label: ScholiumL10n.dynamicString("Back"),
                systemImage: "arrow.left",
                isEnabled: isCommandEnabled(Item.back)
            )
        }
        if let item = toolbarItem(Item.forward) {
            update(
                item,
                label: ScholiumL10n.dynamicString("Forward"),
                systemImage: "arrow.right",
                isEnabled: isCommandEnabled(Item.forward)
            )
        }

        if let item = toolbarItem(Item.documentTitle), let title = item.view as? NSTextField {
            let name = appState.currentNote.map { $0.title ?? $0.displayName } ?? "Scholium"
            title.stringValue = name
            title.setAccessibilityLabel(name)
            title.toolTip = name
            title.textColor = .secondaryLabelColor
            item.label = name
            item.paletteLabel = name
        }

        if let item = toolbarItem(Item.documentMode) {
            let presentation = ScholiumDocumentModeToolbarButtonPresentation(
                mode: appState.documentController.chromeProjection.mode
            )
            item.isHidden = appState.currentNote == nil
            update(
                item,
                label: presentation.accessibilityLabel,
                systemImage: presentation.symbol,
                isEnabled: isCommandEnabled(Item.documentMode),
                toolTip: presentation.toolTip,
                accessibilityValue: presentation.mode.title
            )
        }

        if let item = toolbarItem(Item.settlement) {
            let hasDocument = appState.currentNote != nil
            let target = currentSettlementTarget
            let presentation =
                target == nil
                ? AboutSettlementPresentation.unavailable
                : currentSettlementPresentation
            let action = DocumentSettlementAction.resolve(presentation.state)
            let label = ScholiumL10n.localized(
                DocumentSettlementToolbarPresentation.accessibilityLabel(for: presentation.state)
            )
            let help = ScholiumL10n.localized(action.help)
            item.isHidden = !hasDocument
            item.label = label
            item.paletteLabel = label
            item.toolTip = help
            item.image = ScholiumNativeToolbarPresentation.symbol(
                named: DocumentSettlementToolbarPresentation.symbol(for: presentation.state),
                accessibilityDescription: label
            )
            item.isEnabled = isCommandEnabled(Item.settlement)
            item.menuFormRepresentation?.title = ScholiumL10n.localized(action.title)
            item.menuFormRepresentation?.image = item.image
            item.menuFormRepresentation?.isEnabled = item.isEnabled
            if settlementPopover.isShown && target != presentedSettlementTarget {
                settlementPopover.close()
            }
        }

        if let item = toolbarItem(Item.inspectorModes),
            let control = item.view as? NSSegmentedControl
        {
            let isAvailable = isCommandEnabled(Item.inspectorModes)
            item.isHidden = !isAvailable
            control.isEnabled = isAvailable
            control.selectedSegment =
                ResearchInspectorMode.allCases.firstIndex(
                    of: shellState.inspector.mode
                ) ?? 0
            control.setAccessibilityValue(
                ScholiumL10n.localized(
                    shellState.inspector.mode.interfaceTitleResource
                )
            )
        }

        if let item = toolbarItem(Item.inspector) {
            let visible = shellState.inspector.isVisible
            let unavailable = !appState.canToggleResearchInspector
            update(
                item,
                label: ScholiumL10n.dynamicString(
                    visible ? "Hide Research Inspector" : "Show Research Inspector"
                ),
                systemImage: "sidebar.trailing",
                isEnabled: isCommandEnabled(Item.inspector),
                toolTip: unavailable ? ScholiumL10n.string("No note open yet") : nil,
                accessibilityValue: ScholiumL10n.dynamicString(
                    visible ? "Shown" : "Hidden"
                )
            )

        }
    }

    // AppKit periodically validates native items. Use the same current owner
    // as presentation, rather than allowing target/action presence to re-enable
    // commands which refreshPresentation just made unavailable.
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        isCommandEnabled(item.itemIdentifier)
    }

    private func isCommandEnabled(_ identifier: NSToolbarItem.Identifier) -> Bool {
        guard !isInvalidated else { return false }
        return switch identifier {
        case Item.back: appState.documentNavigationHistoryController.canGoBack
        case Item.forward: appState.documentNavigationHistoryController.canGoForward
        case Item.settlement: currentSettlementTarget != nil
        case Item.inspector: appState.canToggleResearchInspector
        case Item.inspectorModes: appState.currentNote != nil && appState.shellState.inspector.isVisible
        case Item.documentMode:
            appState.currentNote != nil && !currentEditorIsComposing && (ScholiumDocumentModeToolbarButtonPresentation(
                mode: appState.documentController.chromeProjection.mode).destination == .read || appState.canEditCurrentNote)
        default: true
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard !isInvalidated else { return false }
        if item.action == #selector(selectSidebarMenu(_:)) {
            return item.tag != SidebarContent.outline.rawValue || appState.canActivateOutline
        }
        if item.action == #selector(selectInspectorModeFromMenu(_:)) {
            item.state = (item.representedObject as? String) == appState.shellState.inspector.mode.rawValue ? .on : .off
            return isCommandEnabled(Item.inspectorModes)
        }
        guard let command = toolbar.items.first(where: { $0.action == item.action && item.action != nil }) else { return true }
        return isCommandEnabled(command.itemIdentifier)
    }

    private func update(
        _ item: NSToolbarItem,
        label: String,
        systemImage: String,
        isEnabled: Bool,
        toolTip: String? = nil,
        accessibilityValue: String? = nil
    ) {
        item.label = label
        item.paletteLabel = label
        item.title = ""
        item.toolTip = toolTip ?? label
        item.image = ScholiumNativeToolbarPresentation.symbol(
            named: systemImage,
            accessibilityDescription: accessibilityValue ?? label
        )
        item.isEnabled = isEnabled
        item.menuFormRepresentation?.title = label
        item.menuFormRepresentation?.image = item.image
        item.menuFormRepresentation?.isEnabled = isEnabled
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier == identifier }
    }

    func activateSidebar(_ content: SidebarContent) {
        guard !isInvalidated, content != .outline || appState.canActivateOutline else { return }
        windowActions.setLibraryVisible(appState.shellState.activateSidebar(content))
        refreshPresentation()
    }

    private func sidebarModeItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let labels = [ScholiumL10n.string("Triptych"), ScholiumL10n.string("Outline")]
        let symbols = ["books.vertical", "list.bullet"]
        let images = zip(symbols, labels).compactMap {
            ScholiumNativeToolbarPresentation.symbol(named: $0, accessibilityDescription: $1)
        }
        let control = NSSegmentedControl(images: images, trackingMode: .selectOne,
                                         target: self, action: #selector(selectSidebarMode(_:)))
        for index in labels.indices {
            control.setToolTip(labels[index], forSegment: index)
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        control.segmentStyle = .rounded
        control.setAccessibilityLabel(ScholiumL10n.string("Sidebar"))
        control.setAccessibilityIdentifier("scholium.sidebarMode")
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = ScholiumL10n.string("Sidebar")
        item.view = control
        item.visibilityPriority = .user
        let menu = NSMenu()
        for mode in SidebarContent.allCases {
            let entry = NSMenuItem(title: labels[mode.rawValue], action: #selector(selectSidebarMenu(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = mode.rawValue
            entry.image = control.image(forSegment: mode.rawValue)
            menu.addItem(entry)
        }
        let overflow = NSMenuItem(title: item.label, action: nil, keyEquivalent: "")
        overflow.submenu = menu
        item.menuFormRepresentation = overflow
        return item
    }

    @objc private func selectSidebarMode(_ sender: NSSegmentedControl) {
        guard let content = SidebarContent(rawValue: sender.selectedSegment) else { return }
        activateSidebar(content)
    }

    @objc private func selectSidebarMenu(_ sender: NSMenuItem) {
        if let content = SidebarContent(rawValue: sender.tag) { activateSidebar(content) }
    }

    private func inspectorModeMenu() -> NSMenuItem {
        let label = ScholiumL10n.dynamicString("Research Inspector")
        let root = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: label)
        for mode in ResearchInspectorMode.allCases {
            let item = NSMenuItem(
                title: ScholiumL10n.localized(mode.interfaceTitleResource),
                action: #selector(selectInspectorModeFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.image = ScholiumNativeToolbarPresentation.symbol(
                named: mode.systemImage
            )
            item.state = appState.shellState.inspector.mode == mode ? .on : .off
            menu.addItem(item)
        }
        root.submenu = menu
        return root
    }

    private var currentEditorIsComposing: Bool {
        guard let session = currentDocumentSession else { return false }
        return session.isEditing && session.editorSession.context?.composing == true
    }

    private var currentDocumentSession: DocumentSessionModel? {
        if let descriptor = appState.currentDocumentDescriptor {
            return appState.documentController.session(for: descriptor)
        }
        guard let note = appState.currentNote else { return nil }
        return appState.documentController.session(
            for: .unavailable(
                vaultID: note.vaultID,
                relativePath: note.relativePath
            )
        )
    }

    @objc private func goBack(_ sender: Any?) {
        guard isCommandEnabled(Item.back) else { return }
        appState.navigateDocumentHistory(.back)
    }

    @objc private func goForward(_ sender: Any?) {
        guard isCommandEnabled(Item.forward) else { return }
        appState.navigateDocumentHistory(.forward)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closedPopover = notification.object as? NSPopover else { return }
        let responder: NSResponder?
        if closedPopover === settlementPopover {
            presentedSettlementTarget = nil
            settlementPopoverHostingController = nil
            settlementPopover.contentViewController = nil
            responder = responderBeforeSettlement
            responderBeforeSettlement = nil
        } else if closedPopover === notificationsPopover {
            notificationsPopover.contentViewController = nil
            responder = responderBeforeNotifications
            responderBeforeNotifications = nil
            if appState.attentionPopoverSession.isPresented(from: .toolbar) {
                appState.attentionPopoverSession.dismiss()
            }
        } else {
            return
        }
        guard !isInvalidated, let window, window.isKeyWindow, let responder else { return }
        if let view = responder as? NSView, view.window !== window { return }
        window.makeFirstResponder(responder)
    }

    @objc private func toggleDocumentMode(_ sender: Any?) {
        guard isCommandEnabled(Item.documentMode) else { return }
        let presentation = ScholiumDocumentModeToolbarButtonPresentation(
            mode: appState.documentController.chromeProjection.mode
        )
        appState.requestDocumentMode(presentation.destination)
    }

    @objc private func toggleSettlement(_ sender: Any?) {
        guard isCommandEnabled(Item.settlement) else { return }
        if settlementPopover.isShown {
            settlementPopover.performClose(sender)
        } else {
            presentSettlement()
        }
    }

    private func presentSettlement() {
        guard let target = currentSettlementTarget,
            let item = toolbarItem(Item.settlement)
        else { return }
        let presentation = currentSettlementPresentation
        presentedSettlementTarget = target
        let rootView = DocumentSettlementPopoverView(
            presentation: presentation,
            settle: { [weak self] rationale in
                guard let self else { return }
                _ = try await self.appState.researchController.settle(
                    target.note,
                    expectedRevision: target.fingerprint,
                    rationale: rationale
                )
                self.refreshPresentation()
                try await self.appState.researchController.refreshResearchProjection()
                self.refreshPresentation()
            },
            dismiss: { [weak self] in
                self?.settlementPopover.performClose(nil)
            }
        )
        let hostingController = DocumentSettlementPopoverHostingController(
            rootView: rootView
        )
        hostingController.sizingOptions = [
            .preferredContentSize,
            .intrinsicContentSize,
        ]
        hostingController.dismiss = { [weak self] in
            self?.settlementPopover.performClose(nil)
        }
        settlementPopoverHostingController = hostingController
        settlementPopover.contentViewController = hostingController
        responderBeforeSettlement = window?.firstResponder
        settlementPopover.show(relativeTo: item)
        hostingController.focusForKeyboardDismissal()
    }

    private var currentSettlementPresentation: AboutSettlementPresentation {
        let noteID = appState.currentNote?.workspaceSnapshot?.stableIdentity.resolvedID
        let requirement = appState.researchController.researchSnapshot?
            .settlementRequirements.first { $0.noteID == noteID }
        return AboutSettlementPresentation.resolve(
            noteID: noteID,
            currentRevision: appState.currentNote?.document.fingerprint,
            requirement: requirement,
            settlements: appState.researchController.researchSnapshot?.settlements ?? []
        )
    }

    private var currentSettlementTarget: DocumentSettlementTarget? {
        guard let note = appState.currentNote,
            let vaultID = appState.currentDocumentVaultID,
            note.workspaceSnapshot?.stableIdentity.resolvedID != nil,
            appState.currentDocumentVaultRole != .other
        else { return nil }
        return DocumentSettlementTarget(
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: note.relativePath
            ),
            fingerprint: note.document.fingerprint
        )
    }

    @objc private func toggleInspector(_ sender: Any?) {
        guard isCommandEnabled(Item.inspector) else { return }
        windowActions.setResearchInspectorVisible(!appState.shellState.inspector.isVisible)
    }

    @objc private func selectInspectorMode(_ sender: NSSegmentedControl) {
        guard isCommandEnabled(Item.inspectorModes) else { return }
        guard
            ResearchInspectorMode.allCases.indices.contains(
                sender.selectedSegment
            )
        else {
            return
        }
        appState.researchController.selectInspectorMode(
            ResearchInspectorMode.allCases[sender.selectedSegment]
        )
        refreshPresentation()
    }

    @objc private func selectInspectorModeFromMenu(_ sender: NSMenuItem) {
        guard isCommandEnabled(Item.inspectorModes) else { return }
        guard let rawValue = sender.representedObject as? String,
            let mode = ResearchInspectorMode(rawValue: rawValue)
        else { return }
        appState.researchController.selectInspectorMode(mode)
        refreshPresentation()
    }
}

struct DocumentSettlementTarget: Hashable, Sendable {
    let note: VaultQualifiedNoteID
    let fingerprint: DocumentFingerprint
}

enum DocumentSettlementAction: Hashable {
    case settle
    case settleAgain
    case unavailable

    static func resolve(_ state: AboutSettlementState) -> Self {
        switch state {
        case .notYetSettled:
            .settle
        case .settled, .changedSinceSettlement:
            .settleAgain
        case .unavailable:
            .unavailable
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .settle:
            "Settle"
        case .settleAgain:
            "Settle Again"
        case .unavailable:
            "Settlement Unavailable"
        }
    }

    var help: LocalizedStringResource {
        switch self {
        case .settle:
            "Settle this note"
        case .settleAgain:
            "Settle this note again"
        case .unavailable:
            "Settlement is unavailable"
        }
    }
}

enum DocumentSettlementToolbarPresentation {
    static func symbol(for state: AboutSettlementState) -> String {
        switch state {
        case .settled:
            "bookmark.fill"
        case .notYetSettled, .unavailable:
            "bookmark"
        case .changedSinceSettlement:
            "bookmark.circle"
        }
    }

    static func accessibilityLabel(for state: AboutSettlementState) -> LocalizedStringResource {
        switch state {
        case .settled:
            "Settled — Settle Again"
        case .changedSinceSettlement:
            "Changed since settlement — Settle Again"
        case .notYetSettled:
            "Settle"
        case .unavailable:
            "Settlement Unavailable"
        }
    }
}

private struct DocumentSettlementPopoverView: View {
    let presentation: AboutSettlementPresentation
    let settle: (String?) async throws -> Void
    let dismiss: () -> Void

    @State private var rationale = ""
    @State private var errorMessage: String?
    @State private var isSettling = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Apparatus.sectionContentSpacing
        ) {
            Text(actionTitle)
                .font(ScholiumTypography.interface(.sectionTitle))
            Text("Record this saved revision as sufficiently stable for current research.")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Optional rationale", text: $rationale, axis: .vertical)
                .lineLimit(2...4)
            if let errorMessage {
                Text(errorMessage)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.attention)
            }
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button(actionTitle) {
                    isSettling = true
                    errorMessage = nil
                    Task {
                        do {
                            try await settle(rationale.nilIfBlank)
                            isSettling = false
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isSettling = false
                        }
                    }
                }
                .scholiumButtonStyle(.bordered)
                .disabled(isSettling)
            }
        }
        .padding(ScholiumGrid.Spacing.sectionSeparation)
        .frame(width: 300)
        .scholiumButtonStyle(.automatic)
    }

    private var actionTitle: LocalizedStringResource {
        DocumentSettlementAction.resolve(presentation.state).title
    }
}

@MainActor
private final class DocumentSettlementPopoverHostingController:
    NSHostingController<DocumentSettlementPopoverView>
{
    var dismiss: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func focusForKeyboardDismissal() {
        guard let window = view.window else { return }
        window.makeKey()
        window.makeFirstResponder(self)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss?()
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One semantic presentation recipe for native Liquid Glass toolbar symbols
/// and the remaining AppKit controls embedded in the window toolbar.
@MainActor
enum ScholiumNativeToolbarPresentation {
    static var controlSize: NSControl.ControlSize { .small }

    static func symbol(
        named name: String,
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        NSImage(
            systemSymbolName: name,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                textStyle: .body,
                scale: .medium
            ))

    }
}

/// The toolbar reports the current Document mode with one stable icon button.
/// Activating it toggles Review/Edit; Source is only entered from the menu and
/// returns to Review on activation, matching Command-R.
struct ScholiumDocumentModeToolbarButtonPresentation: Equatable {
    let mode: NotePresentationMode
    let destination: NotePresentationMode

    init(mode: NotePresentationMode) {
        self.mode = mode
        destination =
            switch mode {
            case .read: .livePreview
            case .livePreview, .source: .read
            }
    }

    var symbol: String { mode.symbol }
    var toolTip: String { mode.title }
    var accessibilityLabel: String {
        String.localizedStringWithFormat(
            ScholiumL10n.string("Document Mode, %@"),
            mode.title
        )
    }
}
