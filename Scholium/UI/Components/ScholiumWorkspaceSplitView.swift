import AppKit
import SwiftUI

/// One opaque semantic plane for a native split item. The same background view
/// fills the complete region beneath the transparent titlebar and any pane-local
/// control, while foreground content remains a sibling in the live safe area.
/// A flat color needs no background-extension effect, so AppKit cannot mirror,
/// blur, or retint it at the toolbar edge.
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

        NSLayoutConstraint.activate([
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
        ])
        view = containerView
    }

    /// Installs one control inside the live titlebar safe-area band without
    /// adding a row or defining a toolbar height. The control remains owned by
    /// this split item and tracks its divider through ordinary Auto Layout.
    func installTitlebarControl<Control: View>(
        at edge: ScholiumPeripheralTitlebarEdge,
        @ViewBuilder control: () -> Control
    ) {
        let containerView = view
        let titlebarGuide = NSLayoutGuide()
        let host = NSHostingView(rootView: control())
        // The AppKit guide already places this host inside the titlebar band.
        // Prevent SwiftUI from consuming the same window safe area a second
        // time and inflating a 28pt control host by the toolbar height.
        host.safeAreaRegions = []
        host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor

        containerView.addLayoutGuide(titlebarGuide)
        containerView.addSubview(host)

        let edgeConstraint: NSLayoutConstraint = switch edge {
        case .leading:
            host.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor,
                constant: ScholiumGrid.Spacing.inlineControlGap
            )
        case .trailing:
            host.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor,
                constant: -ScholiumGrid.Spacing.inlineControlGap
            )
        }

        NSLayoutConstraint.activate([
            titlebarGuide.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            titlebarGuide.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            titlebarGuide.topAnchor.constraint(equalTo: containerView.topAnchor),
            titlebarGuide.bottomAnchor.constraint(
                equalTo: containerView.safeAreaLayoutGuide.topAnchor
            ),
            host.centerYAnchor.constraint(equalTo: titlebarGuide.centerYAnchor),
            edgeConstraint,
        ])
    }
}

enum ScholiumPeripheralTitlebarEdge {
    case leading
    case trailing
}

/// The permanent peripheral controls belong to their split items, not to the
/// Document toolbar. Their clear hosts use the live AppKit titlebar safe area;
/// the split item's existing semantic background remains the only color plane.
private struct ScholiumPeripheralTitlebarControlView: View {
    let title: String
    let systemImage: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        ScholiumInkIconControl(
            title: title,
            systemImage: systemImage,
            identifier: identifier,
            isActive: true,
            action: action
        )
        .tint(ScholiumColorRole.accent.color)
    }
}

/// One native three-region workspace. Library, Document, and Apparatus are
/// siblings in a single NSSplitViewController; AppKit owns resizing, divider
/// geometry, compression, collapse transitions, and live collapsed state.
struct ScholiumWorkspaceSplitView<Library: View, Document: View, Apparatus: View>:
    NSViewControllerRepresentable
{
    let initialLibraryVisible: Bool
    let initialApparatusVisible: Bool
    let documentTabs: [DocumentTabItem]
    let selectedDocumentTabID: UUID?
    let selectDocumentTab: (UUID) -> Void
    let closeDocumentTab: (UUID) -> Void
    let libraryVisibilityDidChange: (Bool) -> Void
    let researchInspectorVisibilityDidChange: (Bool) -> Void
    let splitControllerDidAttach: @MainActor (
        any ScholiumWorkspaceSplitControlling
    ) -> Void
    let splitControllerDidDetach: @MainActor (
        any ScholiumWorkspaceSplitControlling
    ) -> Void
    let library: Library
    let document: Document
    let apparatus: Apparatus

    init(
        initialLibraryVisible: Bool,
        initialApparatusVisible: Bool,
        documentTabs: [DocumentTabItem],
        selectedDocumentTabID: UUID?,
        selectDocumentTab: @escaping (UUID) -> Void,
        closeDocumentTab: @escaping (UUID) -> Void,
        libraryVisibilityDidChange: @escaping (Bool) -> Void,
        researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
        splitControllerDidAttach: @escaping @MainActor (
            any ScholiumWorkspaceSplitControlling
        ) -> Void,
        splitControllerDidDetach: @escaping @MainActor (
            any ScholiumWorkspaceSplitControlling
        ) -> Void,
        @ViewBuilder library: () -> Library,
        @ViewBuilder document: () -> Document,
        @ViewBuilder apparatus: () -> Apparatus
    ) {
        self.initialLibraryVisible = initialLibraryVisible
        self.initialApparatusVisible = initialApparatusVisible
        self.documentTabs = documentTabs
        self.selectedDocumentTabID = selectedDocumentTabID
        self.selectDocumentTab = selectDocumentTab
        self.closeDocumentTab = closeDocumentTab
        self.libraryVisibilityDidChange = libraryVisibilityDidChange
        self.researchInspectorVisibilityDidChange = researchInspectorVisibilityDidChange
        self.splitControllerDidAttach = splitControllerDidAttach
        self.splitControllerDidDetach = splitControllerDidDetach
        self.library = library()
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
            libraryVisibilityDidChange: libraryVisibilityDidChange,
            researchInspectorVisibilityDidChange: researchInspectorVisibilityDidChange,
            splitControllerDidAttach: splitControllerDidAttach,
            splitControllerDidDetach: splitControllerDidDetach,
            library: library,
            document: document,
            apparatus: apparatus
        )
        _ = controller.view
        return controller
    }

    func updateNSViewController(_ controller: Controller, context: Context) {
        controller.update(
            library: library,
            document: document,
            apparatus: apparatus,
            documentTabs: documentTabs,
            selectedDocumentTabID: selectedDocumentTabID,
            selectDocumentTab: selectDocumentTab,
            closeDocumentTab: closeDocumentTab,
            libraryVisibilityDidChange: libraryVisibilityDidChange,
            researchInspectorVisibilityDidChange: researchInspectorVisibilityDidChange,
            splitControllerDidAttach: splitControllerDidAttach,
            splitControllerDidDetach: splitControllerDidDetach
        )
    }

    @MainActor
    final class Controller: NSSplitViewController, ScholiumWorkspaceSplitControlling {
        private let libraryHost: NSHostingController<Library>
        private let documentTabsController: ScholiumDocumentTabsViewController<Document>
        private let apparatusHost: NSHostingController<Apparatus>
        private let libraryBackgroundController: ScholiumSurfaceContainerViewController
        private let documentBackgroundController: ScholiumSurfaceContainerViewController
        private let apparatusBackgroundController: ScholiumSurfaceContainerViewController
        private var libraryItem: NSSplitViewItem!
        private var documentItem: NSSplitViewItem!
        private var apparatusItem: NSSplitViewItem!
        private let initialLibraryVisible: Bool
        private let initialApparatusVisible: Bool
        private var didApplyInitialVisibility = false
        private var observesVisibility = false
        private var libraryVisibilityDidChange: (Bool) -> Void
        private var researchInspectorVisibilityDidChange: (Bool) -> Void
        private var splitControllerDidAttach: @MainActor (
            any ScholiumWorkspaceSplitControlling
        ) -> Void
        private var splitControllerDidDetach: @MainActor (
            any ScholiumWorkspaceSplitControlling
        ) -> Void

        init(
            initialLibraryVisible: Bool,
            initialApparatusVisible: Bool,
            documentTabs: [DocumentTabItem],
            selectedDocumentTabID: UUID?,
            selectDocumentTab: @escaping (UUID) -> Void,
            closeDocumentTab: @escaping (UUID) -> Void,
            libraryVisibilityDidChange: @escaping (Bool) -> Void,
            researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
            splitControllerDidAttach: @escaping @MainActor (
                any ScholiumWorkspaceSplitControlling
            ) -> Void,
            splitControllerDidDetach: @escaping @MainActor (
                any ScholiumWorkspaceSplitControlling
            ) -> Void,
            library: Library,
            document: Document,
            apparatus: Apparatus
        ) {
            self.initialLibraryVisible = initialLibraryVisible
            self.initialApparatusVisible = initialApparatusVisible
            self.libraryVisibilityDidChange = libraryVisibilityDidChange
            self.researchInspectorVisibilityDidChange = researchInspectorVisibilityDidChange
            self.splitControllerDidAttach = splitControllerDidAttach
            self.splitControllerDidDetach = splitControllerDidDetach
            let libraryHost = NSHostingController(rootView: library)
            let documentTabsController = ScholiumDocumentTabsViewController(
                document: document,
                tabs: documentTabs,
                selectedTabID: selectedDocumentTabID,
                selectTab: selectDocumentTab,
                closeTab: closeDocumentTab
            )
            let apparatusHost = NSHostingController(rootView: apparatus)
            self.libraryHost = libraryHost
            self.documentTabsController = documentTabsController
            self.apparatusHost = apparatusHost
            libraryBackgroundController = ScholiumSurfaceContainerViewController(
                contentViewController: libraryHost,
                backgroundRole: .navigation
            )
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
                sidebarWithViewController: libraryBackgroundController
            )
            libraryItem.minimumThickness = ScholiumMetrics.Library.minimumReadableWidth
            libraryItem.canCollapse = true
            libraryItem.allowsFullHeightLayout = true
            libraryItem.titlebarSeparatorStyle = .line
            libraryBackgroundController.installTitlebarControl(at: .trailing) {
                ScholiumPeripheralTitlebarControlView(
                    title: ScholiumL10n.dynamicString("Hide Sidebar"),
                    systemImage: "sidebar.leading",
                    identifier: "scholium.toggleSidebar"
                ) { [weak self] in
                    self?.setLibraryVisible(
                        false,
                        animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    )
                }
            }

            documentItem = NSSplitViewItem(
                viewController: documentBackgroundController
            )
            documentItem.canCollapse = false
            documentItem.canCollapseFromWindowResize = false
            documentItem.allowsFullHeightLayout = true
            documentItem.titlebarSeparatorStyle = .line

            apparatusItem = NSSplitViewItem(
                inspectorWithViewController: apparatusBackgroundController
            )
            apparatusBackgroundController.installTitlebarControl(at: .leading) {
                ScholiumPeripheralTitlebarControlView(
                    title: ScholiumL10n.dynamicString("Hide Research Inspector"),
                    systemImage: "sidebar.trailing",
                    identifier: "scholium.toggleInspector"
                ) { [weak self] in
                    self?.setResearchInspectorVisible(
                        false,
                        animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                    )
                }
            }

            addSplitViewItem(libraryItem)
            addSplitViewItem(documentItem)
            addSplitViewItem(apparatusItem)
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
            document: Document,
            apparatus: Apparatus,
            documentTabs: [DocumentTabItem],
            selectedDocumentTabID: UUID?,
            selectDocumentTab: @escaping (UUID) -> Void,
            closeDocumentTab: @escaping (UUID) -> Void,
            libraryVisibilityDidChange: @escaping (Bool) -> Void,
            researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
            splitControllerDidAttach: @escaping @MainActor (
                any ScholiumWorkspaceSplitControlling
            ) -> Void,
            splitControllerDidDetach: @escaping @MainActor (
                any ScholiumWorkspaceSplitControlling
            ) -> Void
        ) {
            libraryHost.rootView = library
            documentTabsController.update(
                document: document,
                tabs: documentTabs,
                selectedTabID: selectedDocumentTabID,
                selectTab: selectDocumentTab,
                closeTab: closeDocumentTab
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
                toggleInspector(nil)
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    context.allowsImplicitAnimation = false
                    toggleInspector(nil)
                }
                splitView.layoutSubtreeIfNeeded()
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

private enum ScholiumDocumentTabLayout {
    static let stripHeight = ScholiumGrid.Dimension.documentTabStripHeight
    static let stripTopInset = ScholiumGrid.Spacing.inlineControlGap
    static let stripHorizontalInset = ScholiumGrid.Spacing.regionContentInset
    static let tabHorizontalInset = ScholiumGrid.Spacing.inlineControlGap
    static let titleSpacing = ScholiumGrid.Spacing.labelAccessoryGap
    static let balancedControlWidth = ScholiumGrid.Dimension.minimumCustomTarget
    static let selectionRuleHeight: CGFloat = 1
}

/// AppKit content-tab container installed only in the middle split item. The
/// `.unspecified` style is the ownership boundary that prevents this controller
/// from replacing Scholium's existing native toolbar.
@MainActor
final class ScholiumDocumentTabsViewController<Document: View>: NSViewController {
    private final class TabButton: NSButton {
        var tabID: UUID?
    }

    private let tabViewController = NSTabViewController()
    private let tabButtonStack = NSStackView()
    private let tabStrip = NSView()
    private var tabStripHeightConstraint: NSLayoutConstraint!
    private var pageHosts: [UUID: NSHostingController<Document>] = [:]
    private var pageItems: [UUID: NSTabViewItem] = [:]
    private var placeholderHost: NSHostingController<Document>
    private var placeholderItem: NSTabViewItem
    private var tabs: [DocumentTabItem]
    private var selectedTabID: UUID?
    private var selectTab: (UUID) -> Void
    private var closeTab: (UUID) -> Void

    init(
        document: Document,
        tabs: [DocumentTabItem],
        selectedTabID: UUID?,
        selectTab: @escaping (UUID) -> Void,
        closeTab: @escaping (UUID) -> Void
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectTab = selectTab
        self.closeTab = closeTab
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
        view = NSView()
        view.setAccessibilityIdentifier("scholium.documentRegion")

        tabViewController.tabStyle = .unspecified
        tabViewController.transitionOptions = []
        tabViewController.canPropagateSelectedChildViewControllerTitle = false
        addChild(tabViewController)

        tabButtonStack.orientation = .horizontal
        tabButtonStack.alignment = .height
        tabButtonStack.distribution = .fillEqually
        tabButtonStack.spacing = 0
        tabButtonStack.translatesAutoresizingMaskIntoConstraints = false
        tabButtonStack.setHuggingPriority(.defaultLow, for: .horizontal)
        tabButtonStack.setAccessibilityIdentifier("scholium.documentTabSelector")

        tabStrip.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.setAccessibilityIdentifier("scholium.documentTabs")
        tabStrip.addSubview(tabButtonStack)

        let tabContent = tabViewController.view
        tabContent.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabStrip)
        view.addSubview(tabContent)

        tabStripHeightConstraint = tabStrip.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: view.topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabStripHeightConstraint,
            tabButtonStack.topAnchor.constraint(
                equalTo: tabStrip.topAnchor,
                constant: ScholiumDocumentTabLayout.stripTopInset
            ),
            tabButtonStack.leadingAnchor.constraint(
                equalTo: tabStrip.leadingAnchor,
                constant: ScholiumDocumentTabLayout.stripHorizontalInset
            ),
            tabButtonStack.trailingAnchor.constraint(
                equalTo: tabStrip.trailingAnchor,
                constant: -ScholiumDocumentTabLayout.stripHorizontalInset
            ),
            tabButtonStack.bottomAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            tabContent.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            tabContent.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabContent.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabContent.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        synchronize(document: placeholderHost.rootView)
    }

    func update(
        document: Document,
        tabs: [DocumentTabItem],
        selectedTabID: UUID?,
        selectTab: @escaping (UUID) -> Void,
        closeTab: @escaping (UUID) -> Void
    ) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.selectTab = selectTab
        self.closeTab = closeTab
        guard isViewLoaded else {
            placeholderHost.rootView = document
            return
        }
        synchronize(document: document)
    }

    private func synchronize(document: Document) {
        if tabs.isEmpty {
            placeholderHost.rootView = document
            tabViewController.tabViewItems = [placeholderItem]
            tabViewController.selectedTabViewItemIndex = 0
        } else {
            let currentIDs = Set(tabs.map(\.id))
            for staleID in Set(pageHosts.keys).subtracting(currentIDs) {
                pageHosts[staleID] = nil
                pageItems[staleID] = nil
            }
            for tab in tabs where pageHosts[tab.id] == nil {
                let host = NSHostingController(rootView: document)
                host.sizingOptions = []
                let item = NSTabViewItem(viewController: host)
                item.identifier = tab.id
                pageHosts[tab.id] = host
                pageItems[tab.id] = item
            }
            if let selectedTabID, let selectedHost = pageHosts[selectedTabID] {
                selectedHost.rootView = document
            }
            let orderedItems = tabs.compactMap { tab -> NSTabViewItem? in
                guard let item = pageItems[tab.id] else { return nil }
                item.label = tab.title
                item.toolTip = tab.toolTip
                return item
            }
            tabViewController.tabViewItems = orderedItems
            if let selectedTabID,
               let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) {
                tabViewController.selectedTabViewItemIndex = selectedIndex
            }
        }
        rebuildSelector()
    }

    private func rebuildSelector() {
        for arrangedView in tabButtonStack.arrangedSubviews {
            tabButtonStack.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }
        for tab in tabs {
            tabButtonStack.addArrangedSubview(makeTabItem(
                for: tab,
                isSelected: tab.id == selectedTabID
            ))
        }
        let showsTabStrip = tabs.count > 1
        tabStrip.isHidden = !showsTabStrip
        tabStripHeightConstraint.constant = showsTabStrip
            ? ScholiumDocumentTabLayout.stripHeight
            : 0
    }

    private func makeTabItem(for tab: DocumentTabItem, isSelected: Bool) -> NSView {
        let item = NSView()

        let leadingBalance = NSView()
        leadingBalance.translatesAutoresizingMaskIntoConstraints = false
        leadingBalance.setAccessibilityElement(false)

        let titleButton = TabButton(
            title: tab.title,
            target: self,
            action: #selector(selectDocumentTab(_:))
        )
        titleButton.tabID = tab.id
        titleButton.isBordered = false
        titleButton.alignment = .center
        titleButton.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: isSelected ? .medium : .regular
        )
        titleButton.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
        titleButton.toolTip = tab.toolTip
        titleButton.lineBreakMode = .byTruncatingTail
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleButton.setAccessibilityLabel(tab.title)
        titleButton.setAccessibilityValue(isSelected ? "Selected" : "")

        let closeLabel = "Close \(tab.title)"
        let closeButton = TabButton(
            image: NSImage(
                systemSymbolName: "xmark",
                accessibilityDescription: closeLabel
            ) ?? NSImage(),
            target: self,
            action: #selector(closeDocumentTab(_:))
        )
        closeButton.tabID = tab.id
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = closeLabel
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setAccessibilityLabel(closeLabel)
        closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let selectionRule = NSView()
        selectionRule.wantsLayer = true
        selectionRule.layer?.backgroundColor = isSelected
            ? NSColor.labelColor.withAlphaComponent(0.72).cgColor
            : NSColor.clear.cgColor
        selectionRule.translatesAutoresizingMaskIntoConstraints = false

        item.addSubview(leadingBalance)
        item.addSubview(titleButton)
        item.addSubview(closeButton)
        item.addSubview(selectionRule)

        NSLayoutConstraint.activate([
            leadingBalance.leadingAnchor.constraint(
                equalTo: item.leadingAnchor,
                constant: ScholiumDocumentTabLayout.tabHorizontalInset
            ),
            leadingBalance.widthAnchor.constraint(
                equalToConstant: ScholiumDocumentTabLayout.balancedControlWidth
            ),
            titleButton.leadingAnchor.constraint(
                equalTo: leadingBalance.trailingAnchor,
                constant: ScholiumDocumentTabLayout.titleSpacing
            ),
            titleButton.trailingAnchor.constraint(
                equalTo: closeButton.leadingAnchor,
                constant: -ScholiumDocumentTabLayout.titleSpacing
            ),
            titleButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            closeButton.trailingAnchor.constraint(
                equalTo: item.trailingAnchor,
                constant: -ScholiumDocumentTabLayout.tabHorizontalInset
            ),
            closeButton.centerYAnchor.constraint(equalTo: item.centerYAnchor, constant: -1),
            closeButton.widthAnchor.constraint(
                equalToConstant: ScholiumDocumentTabLayout.balancedControlWidth
            ),
            closeButton.heightAnchor.constraint(
                equalToConstant: ScholiumDocumentTabLayout.balancedControlWidth
            ),
            selectionRule.leadingAnchor.constraint(equalTo: item.leadingAnchor),
            selectionRule.trailingAnchor.constraint(equalTo: item.trailingAnchor),
            selectionRule.bottomAnchor.constraint(equalTo: item.bottomAnchor),
            selectionRule.heightAnchor.constraint(
                equalToConstant: ScholiumDocumentTabLayout.selectionRuleHeight
            ),
        ])
        return item
    }

    @objc
    private func selectDocumentTab(_ sender: NSButton) {
        guard let tabID = (sender as? TabButton)?.tabID else { return }
        selectTab(tabID)
    }

    @objc
    private func closeDocumentTab(_ sender: NSButton) {
        guard let tabID = (sender as? TabButton)?.tabID else { return }
        closeTab(tabID)
    }
}
