import AppKit
import SwiftUI

/// One opaque semantic content plane for a native split item. The same
/// background view fills the complete region beneath the transparent titlebar,
/// while foreground content remains a sibling in the live safe area. The
/// native Sidebar deliberately does not use this container: its split-item
/// behavior owns Liquid Glass and samples the adjacent Document underlay.
@MainActor
final class ScholiumSurfaceContainerViewController: NSViewController {
    let contentViewController: NSViewController
    let backgroundView: NSView

    init(
        contentViewController: NSViewController,
        backgroundRole: ScholiumSurfaceRole
    ) {
        self.contentViewController = contentViewController
        let backgroundHost = NSHostingView(
            rootView: backgroundRole.colorRole.color
        )
        // This host is the opaque color plane for the complete split item,
        // including the full-size-content titlebar band. Letting SwiftUI consume
        // AppKit's safe area here would leave that band to system chrome alone,
        // producing a different tone above otherwise continuous pane content.
        backgroundHost.safeAreaRegions = []
        backgroundView = backgroundHost
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ScholiumSurfaceContainerViewController is code-only")
    }

    override func loadView() {
        let containerView = NSView()

        addChild(contentViewController)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = contentViewController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(backgroundView)
        containerView.addSubview(contentView)

        let constraints = [
            backgroundView.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor
            ),
            backgroundView.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor
            ),
            backgroundView.topAnchor.constraint(
                equalTo: containerView.topAnchor
            ),
            backgroundView.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor
            ),
            contentView.leadingAnchor.constraint(
                equalTo: containerView.safeAreaLayoutGuide.leadingAnchor
            ),
            contentView.trailingAnchor.constraint(
                equalTo: containerView.safeAreaLayoutGuide.trailingAnchor
            ),
            contentView.topAnchor.constraint(
                equalTo: containerView.safeAreaLayoutGuide.topAnchor
            ),
            contentView.bottomAnchor.constraint(
                equalTo: containerView.safeAreaLayoutGuide.bottomAnchor
            ),
        ]
        NSLayoutConstraint.activate(constraints)
        view = containerView
    }

}

/// A controller-lifetime adapter for the system Inspector's ideal-width
/// semantics. It owns no persisted value and releases the split geometry after
/// one completed reveal.
@MainActor
private final class ScholiumFirstApparatusWidthOffer {
    private weak var splitView: NSSplitView?
    private weak var apparatusItem: NSSplitViewItem?
    private var didOffer = false

    func connect(splitView: NSSplitView, apparatusItem: NSSplitViewItem) {
        self.splitView = splitView
        self.apparatusItem = apparatusItem
    }

    /// Offer the wider study width exactly once after the first explicit
    /// reveal. If the window cannot preserve a document region at least as
    /// wide as the Inspector, keep AppKit's result and never reassert it.
    func offerAfterReveal() {
        guard !didOffer else { return }
        didOffer = true
        guard let splitView,
            let apparatusItem,
            !apparatusItem.isCollapsed,
            let apparatusView = splitView.arrangedSubviews.last,
            let documentView = splitView.arrangedSubviews.dropLast().last
        else { return }
        splitView.layoutSubtreeIfNeeded()

        let proposedWidth = ScholiumMetrics.Apparatus.firstRevealWidth
        let currentWidth = apparatusView.frame.width
        guard currentWidth < proposedWidth else { return }
        let additionalWidth = proposedWidth - currentWidth
        guard documentView.frame.width - additionalWidth >= proposedWidth else {
            return
        }

        let dividerIndex = splitView.arrangedSubviews.count - 2
        splitView.setPosition(
            splitView.bounds.maxX - proposedWidth,
            ofDividerAt: dividerIndex
        )
        splitView.layoutSubtreeIfNeeded()
    }
}

/// One native three-region workspace. Library, Document, and Apparatus are
/// siblings in a single NSSplitViewController; AppKit owns resizing, divider
/// geometry, compression, collapse transitions, and live collapsed state.
struct ScholiumWorkspaceSplitView<Library: View, Chat: View, Document: View, Apparatus: View>:
    NSViewControllerRepresentable
{
    let initialLibraryVisible: Bool
    let initialApparatusVisible: Bool
    let documentTabs: [DocumentTabItem]
    let selectedDocumentTabID: UUID?
    let selectDocumentTab: (UUID) -> Void
    let closeDocumentTab: (UUID) -> Void
    let detachDocumentTab: (UUID, NSPoint?) -> Void
    let reorderDocumentTab: (UUID, Int) -> Void
    let libraryVisibilityDidChange: (Bool) -> Void
    let researchInspectorVisibilityDidChange: (Bool) -> Void
    let splitControllerDidAttach:
        @MainActor (
            any ScholiumWorkspaceSplitControlling
        ) -> Void
    let splitControllerDidDetach:
        @MainActor (
            any ScholiumWorkspaceSplitControlling
        ) -> Void
    let library: Library
    let chat: Chat
    let sidebarContent: SidebarContent
    let document: Document
    let apparatus: Apparatus

    init(
        sidebarContent: SidebarContent,
        initialLibraryVisible: Bool,
        initialApparatusVisible: Bool,
        documentTabs: [DocumentTabItem],
        selectedDocumentTabID: UUID?,
        selectDocumentTab: @escaping (UUID) -> Void,
        closeDocumentTab: @escaping (UUID) -> Void,
        detachDocumentTab: @escaping (UUID, NSPoint?) -> Void = { _, _ in },
        reorderDocumentTab: @escaping (UUID, Int) -> Void = { _, _ in },
        libraryVisibilityDidChange: @escaping (Bool) -> Void,
        researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
        splitControllerDidAttach:
            @escaping @MainActor (
                any ScholiumWorkspaceSplitControlling
            ) -> Void,
        splitControllerDidDetach:
            @escaping @MainActor (
                any ScholiumWorkspaceSplitControlling
            ) -> Void,
        @ViewBuilder library: () -> Library,
        @ViewBuilder chat: () -> Chat,
        @ViewBuilder document: () -> Document,
        @ViewBuilder apparatus: () -> Apparatus
    ) {
        self.initialLibraryVisible = initialLibraryVisible
        self.initialApparatusVisible = initialApparatusVisible
        self.documentTabs = documentTabs
        self.selectedDocumentTabID = selectedDocumentTabID
        self.selectDocumentTab = selectDocumentTab
        self.closeDocumentTab = closeDocumentTab
        self.detachDocumentTab = detachDocumentTab
        self.reorderDocumentTab = reorderDocumentTab
        self.libraryVisibilityDidChange = libraryVisibilityDidChange
        self.researchInspectorVisibilityDidChange = researchInspectorVisibilityDidChange
        self.splitControllerDidAttach = splitControllerDidAttach
        self.splitControllerDidDetach = splitControllerDidDetach
        self.library = library()
        self.chat = chat()
        self.sidebarContent = sidebarContent
        self.document = document()
        self.apparatus = apparatus()
    }

    func makeNSViewController(context: Context) -> Controller {
        let controller = Controller(
            initialLibraryVisible: initialLibraryVisible,
            initialApparatusVisible: initialApparatusVisible,
            documentTabs: documentTabs,
            selectedDocumentTabID: selectedDocumentTabID,
            selectDocumentTab: selectDocumentTab,
            closeDocumentTab: closeDocumentTab,
            detachDocumentTab: detachDocumentTab,
            reorderDocumentTab: reorderDocumentTab,
            libraryVisibilityDidChange: libraryVisibilityDidChange,
            researchInspectorVisibilityDidChange: researchInspectorVisibilityDidChange,
            splitControllerDidAttach: splitControllerDidAttach,
            splitControllerDidDetach: splitControllerDidDetach,
            library: library,
            chat: chat,
            sidebarContent: sidebarContent,
            document: document,
            apparatus: apparatus
        )
        _ = controller.view
        return controller
    }

    func updateNSViewController(_ controller: Controller, context: Context) {
        controller.update(
            library: library,
            chat: chat,
            sidebarContent: sidebarContent,
            document: document,
            apparatus: apparatus,
            documentTabs: documentTabs,
            selectedDocumentTabID: selectedDocumentTabID,
            selectDocumentTab: selectDocumentTab,
            closeDocumentTab: closeDocumentTab,
            detachDocumentTab: detachDocumentTab,
            reorderDocumentTab: reorderDocumentTab,
            libraryVisibilityDidChange: libraryVisibilityDidChange,
            researchInspectorVisibilityDidChange: researchInspectorVisibilityDidChange,
            splitControllerDidAttach: splitControllerDidAttach,
            splitControllerDidDetach: splitControllerDidDetach
        )
    }

    @MainActor
    final class Controller: NSSplitViewController, ScholiumWorkspaceSplitControlling {
        private let sidebarController: ScholiumSidebarViewController<Library, Chat>
        private let documentTabsController: ScholiumDocumentTabsViewController<Document>
        private let apparatusHost: NSHostingController<Apparatus>
        private let documentBackgroundController: ScholiumSurfaceContainerViewController
        private let apparatusBackgroundController: ScholiumSurfaceContainerViewController
        private var libraryItem: NSSplitViewItem!
        private var documentItem: NSSplitViewItem!
        private var apparatusItem: NSSplitViewItem!
        private let initialLibraryVisible: Bool
        private let initialApparatusVisible: Bool
        private var didApplyInitialVisibility = false
        private let firstApparatusWidthOffer = ScholiumFirstApparatusWidthOffer()
        private var observesVisibility = false
        private var libraryVisibilityDidChange: (Bool) -> Void
        private var researchInspectorVisibilityDidChange: (Bool) -> Void
        private var splitControllerDidAttach:
            @MainActor (
                any ScholiumWorkspaceSplitControlling
            ) -> Void
        private var splitControllerDidDetach:
            @MainActor (
                any ScholiumWorkspaceSplitControlling
            ) -> Void

        init(
            initialLibraryVisible: Bool,
            initialApparatusVisible: Bool,
            documentTabs: [DocumentTabItem],
            selectedDocumentTabID: UUID?,
            selectDocumentTab: @escaping (UUID) -> Void,
            closeDocumentTab: @escaping (UUID) -> Void,
            detachDocumentTab: @escaping (UUID, NSPoint?) -> Void = { _, _ in },
            reorderDocumentTab: @escaping (UUID, Int) -> Void = { _, _ in },
            libraryVisibilityDidChange: @escaping (Bool) -> Void,
            researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
            splitControllerDidAttach:
                @escaping @MainActor (
                    any ScholiumWorkspaceSplitControlling
                ) -> Void,
            splitControllerDidDetach:
                @escaping @MainActor (
                    any ScholiumWorkspaceSplitControlling
                ) -> Void,
            library: Library,
            chat: Chat,
            sidebarContent: SidebarContent,
            document: Document,
            apparatus: Apparatus
        ) {
            self.initialLibraryVisible = initialLibraryVisible
            self.initialApparatusVisible = initialApparatusVisible
            self.libraryVisibilityDidChange = libraryVisibilityDidChange
            self.researchInspectorVisibilityDidChange = researchInspectorVisibilityDidChange
            self.splitControllerDidAttach = splitControllerDidAttach
            self.splitControllerDidDetach = splitControllerDidDetach
            let sidebarController = ScholiumSidebarViewController(
                library: library, chat: chat, selection: sidebarContent
            )
            let documentTabsController = ScholiumDocumentTabsViewController(
                document: document,
                tabs: documentTabs,
                selectedTabID: selectedDocumentTabID,
                selectTab: selectDocumentTab,
                closeTab: closeDocumentTab,
                detachTab: detachDocumentTab,
                reorderTab: reorderDocumentTab
            )
            let apparatusHost = NSHostingController(rootView: apparatus)
            // The native split item is the sole width owner. Inspector content
            // fills the container but must not publish intrinsic, minimum, or
            // maximum sizes back into AppKit as modes and content change.
            apparatusHost.sizingOptions = []
            self.sidebarController = sidebarController
            self.documentTabsController = documentTabsController
            self.apparatusHost = apparatusHost
            documentBackgroundController = ScholiumSurfaceContainerViewController(
                contentViewController: documentTabsController,
                backgroundRole: .document
            )
            apparatusBackgroundController = ScholiumSurfaceContainerViewController(
                contentViewController: apparatusHost,
                backgroundRole: .apparatus
            )
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("ScholiumWorkspaceSplitView is code-only")
        }

        var nativeSplitViewController: NSSplitViewController { self }

        var libraryIsVisible: Bool {
            isViewLoaded && libraryItem != nil && !libraryItem.isCollapsed
        }

        var researchInspectorIsVisible: Bool {
            isViewLoaded && apparatusItem != nil && !apparatusItem.isCollapsed
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            splitView.identifier = ScholiumWorkspaceSplitViewIdentifier.value
            splitView.isVertical = true
            splitView.dividerStyle = .thin

            libraryItem = NSSplitViewItem(
                sidebarWithViewController: sidebarController
            )
            libraryItem.minimumThickness = ScholiumMetrics.Library.minimumReadableWidth
            libraryItem.canCollapse = true
            libraryItem.allowsFullHeightLayout = true
            libraryItem.titlebarSeparatorStyle = .line

            documentItem = NSSplitViewItem(
                viewController: documentBackgroundController
            )
            // Let the warm Paper plane continue beneath AppKit's floating
            // Sidebar while its safe area keeps Document content unobscured.
            documentItem.automaticallyAdjustsSafeAreaInsets = true
            documentItem.canCollapse = false
            documentItem.canCollapseFromWindowResize = false
            documentItem.allowsFullHeightLayout = true
            documentItem.titlebarSeparatorStyle = .line

            // AppKit's Inspector factory is a fixed-width presentation on
            // macOS 14 and later. The Workspace needs a resizable semantic
            // Inspector, so use the standard native split item and configure
            // its range and visibility contract explicitly.
            apparatusItem = NSSplitViewItem(
                viewController: apparatusBackgroundController
            )
            // Seed restoration before AppKit installs the item. NSSplitViewItem
            // otherwise begins expanded and can briefly draw before
            // viewWillAppear applies the window-scoped visibility state.
            apparatusItem.isCollapsed = !initialApparatusVisible
            apparatusItem.minimumThickness =
                ScholiumMetrics.Apparatus.minimumReadableWidth
            apparatusItem.maximumThickness = NSSplitViewItem.unspecifiedDimension
            // The Inspector preserves the width chosen by the researcher while
            // Library visibility or window size changes. AppKit therefore
            // assigns changing space to Document first, without a delayed
            // divider correction or a second geometry owner.
            apparatusItem.holdingPriority = NSLayoutConstraint.Priority(
                rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1
            )
            // Keep divider tracking exclusively about width: the native toolbar
            // and View command are the explicit, accessible visibility routes.
            apparatusItem.canCollapse = false
            apparatusItem.canCollapseFromWindowResize = false
            // Keep the workspace frame and the trailing edge fixed when the
            // native Inspector is hidden or shown through those explicit routes.
            // AppKit documents that the behavior-specific default may change
            // across macOS releases; Document absorbs this transition.
            apparatusItem.collapseBehavior =
                .preferResizingSiblingsWithFixedSplitView

            addSplitViewItem(libraryItem)
            addSplitViewItem(documentItem)
            addSplitViewItem(apparatusItem)
            firstApparatusWidthOffer.connect(
                splitView: splitView,
                apparatusItem: apparatusItem
            )
        }

        override func viewWillAppear() {
            super.viewWillAppear()
            guard !didApplyInitialVisibility else { return }
            didApplyInitialVisibility = true
            setLibraryVisible(initialLibraryVisible, animated: false)
            setResearchInspectorVisible(initialApparatusVisible, animated: false)
            observesVisibility = true
            reportVisibility()
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            splitControllerDidAttach(self)
            reportVisibility()
        }

        override func viewDidDisappear() {
            splitControllerDidDetach(self)
            super.viewDidDisappear()
        }

        func update(
            library: Library,
            chat: Chat,
            sidebarContent: SidebarContent,
            document: Document,
            apparatus: Apparatus,
            documentTabs: [DocumentTabItem],
            selectedDocumentTabID: UUID?,
            selectDocumentTab: @escaping (UUID) -> Void,
            closeDocumentTab: @escaping (UUID) -> Void,
            detachDocumentTab: @escaping (UUID, NSPoint?) -> Void = { _, _ in },
            reorderDocumentTab: @escaping (UUID, Int) -> Void = { _, _ in },
            libraryVisibilityDidChange: @escaping (Bool) -> Void,
            researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
            splitControllerDidAttach:
                @escaping @MainActor (
                    any ScholiumWorkspaceSplitControlling
                ) -> Void,
            splitControllerDidDetach:
                @escaping @MainActor (
                    any ScholiumWorkspaceSplitControlling
                ) -> Void
        ) {
            sidebarController.update(library: library, chat: chat, selection: sidebarContent)
            documentTabsController.update(
                document: document,
                tabs: documentTabs,
                selectedTabID: selectedDocumentTabID,
                selectTab: selectDocumentTab,
                closeTab: closeDocumentTab,
                detachTab: detachDocumentTab,
                reorderTab: reorderDocumentTab
            )
            apparatusHost.rootView = apparatus
            self.libraryVisibilityDidChange = libraryVisibilityDidChange
            self.researchInspectorVisibilityDidChange =
                researchInspectorVisibilityDidChange
            self.splitControllerDidAttach = splitControllerDidAttach
            self.splitControllerDidDetach = splitControllerDidDetach
        }

        func setLibraryVisible(_ visible: Bool, animated: Bool) {
            guard isViewLoaded,
                libraryItem != nil,
                libraryIsVisible != visible
            else { return }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.allowsImplicitAnimation = true
                    libraryItem.isCollapsed = !visible
                }
            } else {
                libraryItem.isCollapsed = !visible
                splitView.layoutSubtreeIfNeeded()
            }
            reportVisibility()
        }

        func setResearchInspectorVisible(_ visible: Bool, animated: Bool) {
            guard isViewLoaded,
                apparatusItem != nil,
                researchInspectorIsVisible != visible
            else { return }
            if animated {
                let firstApparatusWidthOffer = self.firstApparatusWidthOffer
                NSAnimationContext.runAnimationGroup { context in
                    context.allowsImplicitAnimation = true
                    apparatusItem.isCollapsed = !visible
                } completionHandler: {
                    Task { @MainActor in
                        if visible {
                            firstApparatusWidthOffer.offerAfterReveal()
                        }
                    }
                }
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    apparatusItem.isCollapsed = !visible
                }
                splitView.layoutSubtreeIfNeeded()
                if visible {
                    firstApparatusWidthOffer.offerAfterReveal()
                }
            }
            reportVisibility()
        }

        override func splitViewDidResizeSubviews(_ notification: Notification) {
            super.splitViewDidResizeSubviews(notification)
            reportVisibility()
        }

        private func reportVisibility() {
            guard observesVisibility,
                libraryItem != nil,
                apparatusItem != nil
            else { return }
            libraryVisibilityDidChange(!libraryItem.isCollapsed)
            researchInspectorVisibilityDidChange(!apparatusItem.isCollapsed)
        }

    }
}

enum ScholiumWorkspaceSplitViewIdentifier {
    static let value = NSUserInterfaceItemIdentifier("scholium.workspaceSplitView")
}

/// AppKit owns tab rendering and page containment. Selection requests pass
/// through the window's asynchronous source-safety guard before being applied.
@MainActor
private final class ScholiumNativeDocumentTabController: NSTabViewController {
    var isApplyingSelection = false
    var requestSelection: ((UUID) -> Void)?

    override func tabView(_ tabView: NSTabView, shouldSelect tabViewItem: NSTabViewItem?) -> Bool {
        let allowed = super.tabView(tabView, shouldSelect: tabViewItem)
        guard allowed else { return false }
        guard !isApplyingSelection, let id = tabViewItem?.identifier as? UUID else {
            return true
        }
        requestSelection?(id)
        return false
    }
}

@MainActor
final class ScholiumDocumentTabsViewController<Document: View>: NSViewController {
    private let tabViewController = ScholiumNativeDocumentTabController()
    private let tabStrip = DocumentTabStrip()
    private var pageHosts: [UUID: NSHostingController<Document>] = [:]
    private var pageItems: [UUID: NSTabViewItem] = [:]
    private var placeholderHost: NSHostingController<Document>
    private var placeholderItem: NSTabViewItem
    private var tabs: [DocumentTabItem]
    private var selectedTabID: UUID?
    private var selectTab: (UUID) -> Void
    private var closeTab: (UUID) -> Void
    private var detachTab: (UUID, NSPoint?) -> Void
    private var reorderTab: (UUID, Int) -> Void

    init(
        document: Document,
        tabs: [DocumentTabItem],
        selectedTabID: UUID?,
        selectTab: @escaping (UUID) -> Void,
        closeTab: @escaping (UUID) -> Void,
        detachTab: @escaping (UUID, NSPoint?) -> Void = { _, _ in },
        reorderTab: @escaping (UUID, Int) -> Void = { _, _ in }
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectTab = selectTab
        self.closeTab = closeTab
        self.detachTab = detachTab
        self.reorderTab = reorderTab
        let placeholderHost = NSHostingController(rootView: document)
        placeholderHost.sizingOptions = []
        self.placeholderHost = placeholderHost
        placeholderItem = NSTabViewItem(viewController: placeholderHost)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ScholiumDocumentTabsViewController is code-only")
    }

    override func loadView() {
        tabViewController.tabStyle = .unspecified
        tabViewController.transitionOptions = []
        tabViewController.canPropagateSelectedChildViewControllerTitle = false
        addChild(tabViewController)
        tabViewController.requestSelection = { [weak self] id in self?.selectTab(id) }
        let tabContent = tabViewController.view
        tabViewController.tabView.tabViewType = .noTabsNoBorder
        tabViewController.tabView.setAccessibilityIdentifier("scholium.documentPage")
        view = DocumentTabContainerView(strip: tabStrip, document: tabContent)
        view.setAccessibilityIdentifier("scholium.documentRegion")
        synchronize(document: placeholderHost.rootView)
    }

    func update(
        document: Document,
        tabs: [DocumentTabItem],
        selectedTabID: UUID?,
        selectTab: @escaping (UUID) -> Void,
        closeTab: @escaping (UUID) -> Void,
        detachTab: @escaping (UUID, NSPoint?) -> Void = { _, _ in },
        reorderTab: @escaping (UUID, Int) -> Void = { _, _ in }
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectTab = selectTab
        self.closeTab = closeTab
        self.detachTab = detachTab
        self.reorderTab = reorderTab
        guard isViewLoaded else {
            placeholderHost.rootView = document
            return
        }
        synchronize(document: document)
    }

    private func synchronize(document: Document) {
        tabViewController.isApplyingSelection = true
        defer { tabViewController.isApplyingSelection = false }
        tabStrip.select = selectTab
        tabStrip.close = closeTab
        tabStrip.detach = detachTab
        tabStrip.reorder = reorderTab
        tabStrip.update(tabs: tabs, selectedID: selectedTabID)
        (view as? DocumentTabContainerView)?.showsTabs = tabs.count > 1
        let showsPlaceholder = tabs.isEmpty || selectedTabID == nil
        if showsPlaceholder {
            placeholderHost.rootView = document
            if !tabViewController.tabViewItems.contains(where: { $0 === placeholderItem }) {
                tabViewController.addTabViewItem(placeholderItem)
            }
        } else {
            if tabViewController.tabViewItems.contains(where: { $0 === placeholderItem }) {
                tabViewController.removeTabViewItem(placeholderItem)
            }
        }

        let currentIDs = Set(tabs.map(\.id))
        for staleID in Set(pageHosts.keys).subtracting(currentIDs) {
            if let staleItem = pageItems[staleID] {
                tabViewController.removeTabViewItem(staleItem)
            }
            pageHosts[staleID] = nil
            pageItems[staleID] = nil
        }
        for (index, tab) in tabs.enumerated() {
            if pageHosts[tab.id] == nil {
                let host = NSHostingController(rootView: document)
                host.sizingOptions = []
                let item = NSTabViewItem(viewController: host)
                item.identifier = tab.id
                pageHosts[tab.id] = host
                pageItems[tab.id] = item
                tabViewController.insertTabViewItem(
                    item,
                    at: min(index, tabViewController.tabViewItems.count)
                )
            } else if let item = pageItems[tab.id],
                let currentIndex = tabViewController.tabViewItems.firstIndex(
                    where: { $0 === item }
                ), currentIndex != index
            {
                tabViewController.removeTabViewItem(item)
                tabViewController.insertTabViewItem(item, at: index)
            }
            pageItems[tab.id]?.label = tab.title
            pageItems[tab.id]?.toolTip = tab.toolTip
        }
        if let selectedTabID, let selectedHost = pageHosts[selectedTabID] {
            selectedHost.rootView = document
        }
        if let selectedTabID,
            let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID })
        {
            tabViewController.selectedTabViewItemIndex = selectedIndex
        } else if showsPlaceholder,
            let placeholderIndex = tabViewController.tabViewItems.firstIndex(
                where: { $0 === placeholderItem }
            )
        {
            tabViewController.selectedTabViewItemIndex = placeholderIndex
        }
    }

    #if DEBUG
        func testingPageHost(for id: UUID) -> AnyObject? { pageHosts[id] }
        func testingPageItem(for id: UUID) -> AnyObject? { pageItems[id] }
        var testingNativeTabView: NSTabView { tabViewController.tabView }
        var testingTabStrip: DocumentTabStrip { tabStrip }
        func testingPageLabel(for id: UUID) -> String? { pageItems[id]?.label }
    #endif

}
