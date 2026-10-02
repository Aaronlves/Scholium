import AppKit
import Combine
import Foundation
import ScholiumContracts

/// The configured window has one native toolbar. Tracking separators establish
/// Library, Markdown, PDF, and Apparatus sections. Sidebar and document-history
/// controls belong to their Sidebar and Document sections respectively. The Inspector projection
/// control begins the Apparatus section; independent PDF/Inspector toggles end it;
/// the reading region participates only while its native split item is visible.
@MainActor
final class ScholiumWorkspaceToolbarController: NSObject, NSToolbarDelegate, NSPopoverDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    static func toolbarIdentifier(for windowID: UUID) -> NSToolbar.Identifier {
        .init("scholium.workspaceToolbar.\(windowID.uuidString)")
    }

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
        static let documentMode = NSToolbarItem.Identifier(
            "scholium.toolbar.documentMode"
        )
        static let noteActions = NSToolbarItem.Identifier("scholium.toolbar.noteActions")
        static let pdfReader = NSToolbarItem.Identifier("scholium.toolbar.pdfReader")
        static let paneVisibility = NSToolbarItem.Identifier("scholium.toolbar.paneVisibility")
        static let viewChanges = NSToolbarItem.Identifier("scholium.toolbar.viewChanges")
        static let readingDivider = NSToolbarItem.Identifier("scholium.toolbar.readingDivider")
        static let readerControls = NSToolbarItem.Identifier("scholium.toolbar.pdfControls")
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
    private let appState: WindowModel
    private let windowActions: WorkspaceWindowActions
    private let splitViewController: NSSplitViewController
    private let toolbar: NSToolbar
    private let documentTabs = DocumentToolbarTabs()
    private let notificationsPopover = NSPopover()
    private weak var responderBeforeNotifications: NSResponder?
    private weak var window: NSWindow?
    private weak var observedChat: AgentChatController?
    private var chatObservation: AnyCancellable?
    private var presentationCancellables: Set<AnyCancellable> = []
    private var readingDivider: NSTrackingSeparatorToolbarItem?
    private var readerControls: PDFReaderToolbarItem?

    init(
        appState: WindowModel,
        windowActions: WorkspaceWindowActions,
        splitViewController: NSSplitViewController
    ) {
        self.appState = appState
        self.windowActions = windowActions
        self.splitViewController = splitViewController
        toolbar = NSToolbar(identifier: Self.toolbarIdentifier(for: appState.nativeWindowID))
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        documentTabs.select = { [weak appState] id in appState?.selectDocumentTab(withID: id) }
        documentTabs.close = { [weak appState] id in appState?.closeDocumentTab(withID: id) }
        documentTabs.detach = { [weak appState] id, point in
            appState?.requestMoveDocumentToWindow(tabID: id, at: point)
        }
        documentTabs.reorder = { [weak appState] id, index in
            appState?.documentTabController.moveTab(withID: id, to: index)
        }
        notificationsPopover.behavior = .transient
        notificationsPopover.delegate = self
        observePresentation()
        observeReadingGeometry()
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
        chatObservation?.cancel()
        chatObservation = nil
        observedChat = nil
        presentationCancellables.removeAll()
        documentTabs.invalidate()
        responderBeforeNotifications = nil
        notificationsPopover.close()
        notificationsPopover.contentViewController = nil
        readerControls?.invalidate()
        readerControls = nil
        readingDivider = nil
        for item in toolbar.items {
            if let panes = item as? NSToolbarItemGroup, item.itemIdentifier == Item.paneVisibility {
                ScholiumPaneVisibilityToolbarPresentation.invalidate(panes)
            } else if let noteActions = item as? DocumentNoteActionsToolbarItem {
                noteActions.invalidate()
            } else if let mode = item as? ScholiumDocumentModeToolbarItem {
                mode.invalidate()
            } else if let reader = item as? PDFReaderToolbarItem {
                reader.invalidate()
            } else {
                item.menuFormRepresentation = nil
            }
            item.target = nil
            item.action = nil
            item.isEnabled = false
            (item.view as? ScholiumSidebarModeControl)?.invalidateNoteDrops()
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
        itemIdentifiers
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
            .space,
            Item.viewChanges,
            Item.documentMode,
            Item.noteActions,
            Item.readingDivider,
            Item.readerControls,
            Item.apparatusDivider,
            Item.inspectorModes,
            Item.paneVisibility,
        ] + documentTabs.visibleIdentifiers
    }

    var itemIdentifiers: [NSToolbarItem.Identifier] {
        Self.itemIdentifiers(tabIdentifiers: documentTabs.visibleIdentifiers, readerVisible: readingController?.readerIsVisible == true)
    }

    private var readingController: ScholiumDocumentReadingSplitController? {
        ScholiumDocumentReadingSplitController.find(in: splitViewController.view)
    }

    static func itemIdentifiers(
        tabIdentifiers: [NSToolbarItem.Identifier], readerVisible: Bool = false
    ) -> [NSToolbarItem.Identifier] {
        [
            Item.sidebar,
            .flexibleSpace,
            .space,
            Item.notifications,
            Item.libraryDivider,
            Item.back,
            Item.forward,
        ] + tabIdentifiers + [
            .flexibleSpace,
            Item.viewChanges,
            .space,
            Item.documentMode,
            Item.noteActions,
        ]
            + (readerVisible
                ? [
                    Item.readingDivider,
                    Item.readerControls,
                    .flexibleSpace,
                ] : []) + [
                Item.apparatusDivider,
                Item.inspectorModes,
                .flexibleSpace,
                .space,
                Item.paneVisibility,
            ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard !isInvalidated else { return nil }
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
                action: #selector(goBack(_:)),
                visibilityPriority: .user
            )
            item.isNavigational = true
            return item
        case Item.forward:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Forward"),
                systemImage: "arrow.right",
                action: #selector(goForward(_:)),
                visibilityPriority: .user
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
        case Item.documentMode:
            let item = ScholiumDocumentModeToolbarItem(identifier: itemIdentifier, model: appState)
            item.visibilityPriority = .user
            return item
        case Item.noteActions:
            let item = DocumentNoteActionsToolbarItem(identifier: itemIdentifier, model: appState)
            item.visibilityPriority = .standard
            return item
        case Item.readingDivider:
            guard let readingController, readingController.splitView.window === window else { return nil }
            if readingDivider?.splitView !== readingController.splitView {
                readingDivider = NSTrackingSeparatorToolbarItem(
                    identifier: itemIdentifier, splitView: readingController.splitView, dividerIndex: 0)
                readingDivider?.visibilityPriority = .user
            }
            return readingDivider
        case Item.readerControls:
            if readerControls == nil {
                readerControls = PDFReaderToolbarItem(identifier: itemIdentifier, controller: appState.pdfReaderController)
            }
            if let window { readerControls?.install(in: window) }
            updateReaderRegionWidth()
            readerControls?.refresh()
            return readerControls
        case Item.paneVisibility:
            return paneVisibilityItem(identifier: itemIdentifier)
        case Item.pdfReader:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("PDF Reader"),
                systemImage: "doc.richtext",
                action: #selector(togglePDFReader(_:)),
                visibilityPriority: .user
            )
            item.possibleLabels = [
                ScholiumL10n.string("Hide PDF Reader"),
                ScholiumL10n.string("Show PDF Reader"),
            ]
            return item
        case Item.viewChanges:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("View Changes"),
                systemImage: "doc.text.magnifyingglass",
                action: #selector(viewCurrentChanges(_:)),
                visibilityPriority: .standard
            )
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
            return documentTabs.item(for: itemIdentifier)
        }
    }

    @objc private func showNotifications(_ sender: Any?) {
        guard isCommandEnabled(Item.notifications) else { return }
        let session = appState.attentionPopoverSession
        if session.isPresented(from: .toolbar) {
            session.dismiss()
        } else {
            windowActions.showAttention(.queue(anchor: .toolbar, workspaceSlot: nil, noteScope: nil))
        }
    }

    private func refreshNotifications() {
        guard let item = toolbarItem(Item.notifications) else { return }
        let total = appState.researchController.pendingChanges?.count
        let value: String
        if let total {
            value =
                switch total {
                case 0: ScholiumL10n.string("No notifications")
                case 1: ScholiumL10n.string("1 notification")
                default: String.localizedStringWithFormat(ScholiumL10n.string("%lld notifications"), Int64(total))
                }
        } else {
            value =
                notificationError == nil
                ? ScholiumL10n.string("Checking Notifications")
                : ScholiumL10n.string("Notifications Unavailable")
        }
        let label = ScholiumL10n.string("Open Triptych Notifications")
        update(
            item,
            label: label,
            systemImage: (total ?? 0) > 0 ? "bell.badge" : "bell",
            isEnabled: true,
            toolTip: "\(label) · \(value)",
            accessibilityValue: value
        )
        let session = appState.attentionPopoverSession
        if session.isPresented(from: .toolbar) {
            if !notificationsPopover.isShown {
                let content = AttentionQueueViewController(
                    presentation: session.presentation,
                    session: session
                )
                content.preferredContentSize = NSSize(
                    width: ScholiumMetrics.Attention.popoverWidth,
                    height: ScholiumMetrics.Attention.popoverHeight
                )
                notificationsPopover.contentViewController = content
                responderBeforeNotifications = window?.firstResponder
                showNotificationsPopover(relativeTo: item)
                content.focusInitialContentIfNeeded()
            }
        } else if notificationsPopover.isShown {
            notificationsPopover.close()
        }
    }

    private func showNotificationsPopover(relativeTo item: NSToolbarItem) {
        guard let window, let contentView = window.contentView else { return }
        if toolbar.isVisible {
            // AppKit supplies its native alternate anchor when the item is in overflow.
            notificationsPopover.show(relativeTo: item)
        } else {
            // Focus Layout retains the command while removing toolbar chrome.
            // Anchor in this window's visible content without revealing a pane or toolbar.
            let safeArea = contentView.safeAreaRect
            let trailingX =
                contentView.userInterfaceLayoutDirection == .rightToLeft
                ? safeArea.minX : max(safeArea.minX, safeArea.maxX - 1)
            let topY = contentView.isFlipped ? safeArea.minY : max(safeArea.minY, safeArea.maxY - 1)
            notificationsPopover.show(
                relativeTo: NSRect(x: trailingX, y: topY, width: 1, height: 1),
                of: contentView,
                preferredEdge: contentView.isFlipped ? .maxY : .minY
            )
        }
    }

    private var notificationError: String? {
        if appState.workspaceCatalog == nil, let error = appState.workspaceCatalogError {
            return error
        }
        if appState.researchController.pendingChanges == nil,
            let error = appState.researchController.pendingChangesError
        {
            return error
        }
        return nil
    }

    private func installToolbarItemsIfNeeded() {
        documentTabs.update(
            tabs: appState.documentTabController.tabs,
            selectedID: appState.documentTabController.selectedTabID
        )
        if toolbar.itemIdentifiers != itemIdentifiers {
            toolbar.itemIdentifiers = itemIdentifiers
        }
        if let readingController, let readingDivider {
            readingDivider.splitView = readingController.splitView
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
        let control = ScholiumTooltippedSegmentedControl(frame: .zero)
        control.segmentCount = modes.count
        control.trackingMode = .selectOne
        control.target = self
        control.action = #selector(selectInspectorMode(_:))
        control.controlSize = ScholiumNativeToolbarPresentation.controlSize
        control.segmentStyle = .rounded
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel(label)
        control.setAccessibilityIdentifier("scholium.inspectorMode")
        for (index, mode) in modes.enumerated() {
            let title = ScholiumL10n.localized(mode.interfaceTitleResource)
            control.setImage(
                ScholiumNativeToolbarPresentation.symbol(
                    named: mode.systemImage,
                    accessibilityDescription: title
                ),
                forSegment: index
            )
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }
        control.setSegmentToolTips(
            modes.map { ScholiumL10n.localized($0.interfaceTitleResource) }
        )

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
            named: systemImage
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
            NotificationCenter.default.publisher(for: ScholiumDocumentReadingSplitController.participationDidChange)
                .receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.shellState.$sidebarContent.dropFirst().receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.shellState.$libraryVisible.dropFirst().receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.shellState.$colorScheme.dropFirst().receive(on: DispatchQueue.main).map { _ in () }.eraseToAnyPublisher(),
            appState.commandObservation.$revision
                .receive(on: DispatchQueue.main)
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.documentTabController.$tabs
                .receive(on: DispatchQueue.main)
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.documentTabController.$selectedTabID
                .receive(on: DispatchQueue.main)
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.researchController.$pendingChanges
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

    private func observeReadingGeometry() {
        NotificationCenter.default.publisher(for: NSSplitView.didResizeSubviewsNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, !self.isInvalidated, let window = self.window else { return }
                guard
                    notification.object as? NSWindow === window
                        || notification.object as? NSSplitView === self.readingController?.splitView
                        || notification.object as? NSSplitView === self.splitViewController.splitView
                else { return }
                self.updateReaderRegionWidth()
            }
            .store(in: &presentationCancellables)
    }

    private func updateReaderRegionWidth() {
        guard !isInvalidated, let readingController, readingController.readerIsVisible,
            let window, readingController.splitView.window === window
        else { return }
        readerControls?.setRegionWidth(width: readingController.readerController.view.bounds.width, trailingPaneSwitchCount: 2)
    }

    private func refreshPresentation() {
        guard !isInvalidated else { return }
        installToolbarItemsIfNeeded()
        updateReaderRegionWidth()
        readerControls?.refresh()
        let shellState = appState.shellState
        let chat = appState.chatController
        if observedChat !== chat {
            chatObservation?.cancel()
            observedChat = chat
            chatObservation = chat?.needsInputPublisher
                .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshPresentation() }
        }
        refreshNotifications()

        if let control = toolbarItem(Item.sidebar)?.view as? ScholiumSidebarModeControl {
            control.selectedSegment = shellState.libraryVisible ? shellState.sidebarContent.rawValue : -1
            let unavailable = appState.workspaceAssignment == nil
            control.setEnabled(!unavailable, forSegment: SidebarContent.chat.rawValue)
            let awaitingInput = chat?.needsInput == true
            let title =
                unavailable
                ? ScholiumL10n.string("No Triptych Open")
                : awaitingInput ? String(localized: "Chat Needs Your Input") : String(localized: "Chat")
            control.setSegmentToolTips([sidebarModeLabels[0], title])
            control.setImage(
                ScholiumNativeToolbarPresentation.symbol(
                    named: awaitingInput ? "exclamationmark.bubble" : "bubble.left.and.bubble.right",
                    accessibilityDescription: title), forSegment: SidebarContent.chat.rawValue)
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

        (toolbarItem(Item.documentMode) as? ScholiumDocumentModeToolbarItem)?.refreshPresentation()
        (toolbarItem(Item.noteActions) as? DocumentNoteActionsToolbarItem)?.refreshPresentation()
        if let item = toolbarItem(Item.pdfReader) {
            let visible = PDFReaderWindowCommand.isVisible(in: appState)
            update(
                item,
                label: ScholiumL10n.dynamicString(visible ? "Hide PDF Reader" : "Show PDF Reader"),
                systemImage: "doc.richtext",
                isEnabled: isCommandEnabled(Item.pdfReader),
                accessibilityValue: ScholiumL10n.dynamicString(visible ? "Shown" : "Hidden")
            )
        }

        if let item = toolbarItem(Item.viewChanges) {
            item.isHidden = !hasCurrentPendingChanges
            update(
                item,
                label: ScholiumL10n.dynamicString("View Changes"),
                systemImage: "doc.text.magnifyingglass",
                isEnabled: isCommandEnabled(Item.viewChanges)
            )
        }

        toolbarItem(Item.apparatusDivider)?.isHidden = !shellState.inspector.isVisible
        if let item = toolbarItem(Item.inspectorModes),
            let control = item.view as? ScholiumTooltippedSegmentedControl
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
        if let panes = toolbarItem(Item.paneVisibility) as? NSToolbarItemGroup {
            ScholiumPaneVisibilityToolbarPresentation.refresh(
                panes,
                selected: [PDFReaderWindowCommand.isVisible(in: appState), shellState.inspector.isVisible])
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
        case Item.viewChanges: hasCurrentPendingChanges
        case Item.inspector: appState.canToggleResearchInspector
        case Item.inspectorModes: appState.currentNote != nil && appState.shellState.inspector.isVisible
        case Item.documentMode: ScholiumDocumentModeToolbarItem.isAvailable(in: appState)
        case Item.noteActions: appState.currentNote != nil && !appState.transferInProgress
        case Item.pdfReader: PDFReaderWindowCommand.isAvailable(in: appState)
        case Item.paneVisibility: PDFReaderWindowCommand.isAvailable(in: appState) || appState.canToggleResearchInspector
        default: true
        }
    }

    private var hasCurrentPendingChanges: Bool {
        guard let noteID = appState.currentDocumentDescriptor?.sessionKey.noteID else {
            return false
        }
        return appState.researchController.pendingChanges?.contains {
            $0.noteID == noteID
        } == true
    }

    @objc private func viewCurrentChanges(_ sender: Any?) {
        guard hasCurrentPendingChanges,
            let noteID = appState.currentDocumentDescriptor?.sessionKey.noteID
        else { return }
        appState.presentationRouter.present(.documentChanges(scope: .note(noteID)))
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard !isInvalidated else { return false }
        if item.action == #selector(selectSidebarMenu(_:)) {
            item.state =
                appState.shellState.libraryVisible
                    && item.tag == appState.shellState.sidebarContent.rawValue ? .on : .off
            return item.tag != SidebarContent.chat.rawValue || appState.workspaceAssignment != nil
        }
        if item.action == #selector(selectInspectorModeFromMenu(_:)) {
            item.state = (item.representedObject as? String) == appState.shellState.inspector.mode.rawValue ? .on : .off
            return isCommandEnabled(Item.inspectorModes)
        }
        guard let command = commandItems.first(where: { $0.action == item.action && item.action != nil }) else { return true }
        if command.itemIdentifier == Item.pdfReader {
            item.state = PDFReaderWindowCommand.isVisible(in: appState) ? .on : .off
        } else if command.itemIdentifier == Item.inspector {
            item.state = appState.shellState.inspector.isVisible ? .on : .off
        }
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
            accessibilityDescription: accessibilityValue
        )
        item.isEnabled = isEnabled
        item.menuFormRepresentation?.title = label
        item.menuFormRepresentation?.image = item.image
        item.menuFormRepresentation?.isEnabled = isEnabled
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        commandItems.first { $0.itemIdentifier == identifier }
    }

    private var commandItems: [NSToolbarItem] {
        toolbar.items.flatMap { item in [item] + ((item as? NSToolbarItemGroup)?.subitems ?? []) }
    }

    private func paneVisibilityItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let reader = self.toolbar(toolbar, itemForItemIdentifier: Item.pdfReader, willBeInsertedIntoToolbar: false)
        let inspector = self.toolbar(toolbar, itemForItemIdentifier: Item.inspector, willBeInsertedIntoToolbar: false)
        return ScholiumPaneVisibilityToolbarPresentation.group(
            identifier: identifier, label: ScholiumL10n.string("Reading Panes"),
            items: [reader, inspector].compactMap { $0 },
            target: self, action: #selector(togglePaneVisibility(_:)))
    }

    @objc private func togglePaneVisibility(_ sender: Any?) {
        guard !isInvalidated,
            let group = toolbarItem(Item.paneVisibility) as? NSToolbarItemGroup, group.subitems.count == 2,
            (sender as? NSToolbarItemGroup) === group
        else { return }
        // A select-any group has no selectedIndex when its last pane is
        // deselected. The one changed native bit identifies that intent.
        let actual = [PDFReaderWindowCommand.isVisible(in: appState), appState.shellState.inspector.isVisible]
        let changed = actual.indices.filter { group.isSelected(at: $0) != actual[$0] }
        guard changed.count == 1 else {
            refreshPresentation()
            return
        }
        switch changed[0] {
        case 0: togglePDFReader(sender)
        case 1: toggleInspector(sender)
        default: refreshPresentation()
        }
    }

    func activateSidebar(_ content: SidebarContent) {
        guard !isInvalidated, content != .chat || appState.workspaceAssignment != nil else { return }
        windowActions.setLibraryVisible(appState.shellState.activateSidebar(content))
        refreshPresentation()
    }

    private var sidebarModeLabels: [String] {
        [ScholiumL10n.string("Library"), ScholiumL10n.string("Chat")]
    }

    private func sidebarModeItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let labels = sidebarModeLabels
        let symbols = ["books.vertical", "bubble.left.and.bubble.right"]
        let images = zip(symbols, labels).compactMap {
            ScholiumNativeToolbarPresentation.symbol(named: $0, accessibilityDescription: $1)
        }
        let control = ScholiumSidebarModeControl(
            images: images, trackingMode: .selectOne,
            target: self, action: #selector(selectSidebarMode(_:)))
        control.enableNoteDrops()
        control.validateNotes = { [weak self] notes in
            guard let self, !self.isInvalidated else { return false }
            return self.appState.canAddNotesToChat(notes)
        }
        control.acceptNotes = { [weak self] notes in
            guard let self, !self.isInvalidated, self.appState.addNotesToChat(notes) else { return false }
            if self.appState.shellState.sidebarContent != .chat || !self.appState.shellState.libraryVisible {
                self.activateSidebar(.chat)
            }
            return true
        }
        control.setSegmentToolTips(labels)
        for index in labels.indices {
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
            entry.image = ScholiumNativeToolbarPresentation.symbol(
                named: symbols[mode.rawValue]
            )
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

    @objc private func goBack(_ sender: Any?) {
        guard isCommandEnabled(Item.back) else { return }
        appState.navigateDocumentHistory(.back)
    }

    @objc private func goForward(_ sender: Any?) {
        guard isCommandEnabled(Item.forward) else { return }
        appState.navigateDocumentHistory(.forward)
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === notificationsPopover else { return }
        notificationsPopover.contentViewController = nil
        let responder = responderBeforeNotifications
        responderBeforeNotifications = nil
        if appState.attentionPopoverSession.isPresented(from: .toolbar) {
            appState.attentionPopoverSession.dismiss()
        }
        guard !isInvalidated, let window, window.isKeyWindow, let responder else { return }
        if let view = responder as? NSView, view.window !== window { return }
        window.makeFirstResponder(responder)
    }

    @objc private func toggleInspector(_ sender: Any?) {
        defer { refreshPresentation() }
        guard isCommandEnabled(Item.inspector) else { return }
        windowActions.setResearchInspectorVisible(!appState.shellState.inspector.isVisible)
    }

    @objc private func togglePDFReader(_ sender: Any?) {
        defer { refreshPresentation() }
        guard isCommandEnabled(Item.pdfReader) else { return }
        PDFReaderWindowCommand.toggle(in: appState)
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
