import AppKit
import SwiftUI

/// One native three-region workspace. Library, Document, and Apparatus are
/// siblings in a single NSSplitViewController; AppKit owns their divider and
/// Inspector behavior.
struct ScholiumWorkspaceSplitView<Library: View, Document: View, Apparatus: View>:
    NSViewControllerRepresentable
{
    let libraryVisible: Bool
    let apparatusVisible: Bool
    let reduceMotion: Bool
    let documentTabs: [DocumentTabItem]
    let selectedDocumentTabID: UUID?
    let selectDocumentTab: (UUID) -> Void
    let closeDocumentTab: (UUID) -> Void
    let researchInspectorVisibilityDidChange: (Bool) -> Void
    let library: Library
    let document: Document
    let apparatus: Apparatus

    init(
        libraryVisible: Bool,
        apparatusVisible: Bool,
        reduceMotion: Bool,
        documentTabs: [DocumentTabItem],
        selectedDocumentTabID: UUID?,
        selectDocumentTab: @escaping (UUID) -> Void,
        closeDocumentTab: @escaping (UUID) -> Void,
        researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
        @ViewBuilder library: () -> Library,
        @ViewBuilder document: () -> Document,
        @ViewBuilder apparatus: () -> Apparatus
    ) {
        self.libraryVisible = libraryVisible
        self.apparatusVisible = apparatusVisible
        self.reduceMotion = reduceMotion
        self.documentTabs = documentTabs
        self.selectedDocumentTabID = selectedDocumentTabID
        self.selectDocumentTab = selectDocumentTab
        self.closeDocumentTab = closeDocumentTab
        self.researchInspectorVisibilityDidChange = researchInspectorVisibilityDidChange
        self.library = library()
        self.document = document()
        self.apparatus = apparatus()
    }

    func makeNSViewController(context: Context) -> Controller {
        let controller = Controller(
            libraryVisible: libraryVisible,
            apparatusVisible: apparatusVisible,
            documentTabs: documentTabs,
            selectedDocumentTabID: selectedDocumentTabID,
            selectDocumentTab: selectDocumentTab,
            closeDocumentTab: closeDocumentTab,
            researchInspectorVisibilityDidChange: researchInspectorVisibilityDidChange,
            library: library,
            document: document,
            apparatus: apparatus
        )
        _ = controller.view
        return controller
    }

    func updateNSViewController(_ controller: Controller, context: Context) {
        controller.scheduleUpdate(
            library: library,
            document: document,
            apparatus: apparatus,
            documentTabs: documentTabs,
            selectedDocumentTabID: selectedDocumentTabID,
            selectDocumentTab: selectDocumentTab,
            closeDocumentTab: closeDocumentTab,
            researchInspectorVisibilityDidChange: researchInspectorVisibilityDidChange,
            libraryVisible: libraryVisible,
            apparatusVisible: apparatusVisible,
            animated: !reduceMotion
        )
    }

    @MainActor
    final class Controller: NSSplitViewController {
        private let libraryHost: NSHostingController<Library>
        private let documentTabsController: ScholiumDocumentTabsViewController<Document>
        private let apparatusHost: NSHostingController<Apparatus>
        private var libraryItem: NSSplitViewItem!
        private var documentItem: NSSplitViewItem!
        private var apparatusItem: NSSplitViewItem!
        private var lastLibraryVisible: Bool
        private var lastApparatusVisible: Bool
        private var researchInspectorVisibilityDidChange: (Bool) -> Void
        private var observesResearchInspectorVisibility = false
        private var pendingUpdate: (
            library: Library,
            document: Document,
            apparatus: Apparatus,
            documentTabs: [DocumentTabItem],
            selectedDocumentTabID: UUID?,
            selectDocumentTab: (UUID) -> Void,
            closeDocumentTab: (UUID) -> Void,
            researchInspectorVisibilityDidChange: (Bool) -> Void,
            libraryVisible: Bool,
            apparatusVisible: Bool,
            animated: Bool
        )?
        private var isUpdateScheduled = false
        private weak var registeredWindow: NSWindow?

        init(
            libraryVisible: Bool,
            apparatusVisible: Bool,
            documentTabs: [DocumentTabItem],
            selectedDocumentTabID: UUID?,
            selectDocumentTab: @escaping (UUID) -> Void,
            closeDocumentTab: @escaping (UUID) -> Void,
            researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
            library: Library,
            document: Document,
            apparatus: Apparatus
        ) {
            lastLibraryVisible = libraryVisible
            lastApparatusVisible = apparatusVisible
            self.researchInspectorVisibilityDidChange = researchInspectorVisibilityDidChange
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
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("ScholiumWorkspaceSplitView is code-only")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            splitView.identifier = ScholiumWorkspaceSplitViewIdentifier.value
            splitView.isVertical = true
            splitView.dividerStyle = .thin
            // The peripheral columns are genuine AppKit roles. Besides their
            // collapse semantics, these roles let AppKit coordinate the native
            // tab bar and toolbar tracking separators with the same split view.
            libraryItem = NSSplitViewItem(sidebarWithViewController: libraryHost)
            libraryItem.canCollapse = true
            libraryItem.canCollapseFromWindowResize = false
            libraryItem.allowsFullHeightLayout = true
            libraryItem.automaticallyAdjustsSafeAreaInsets = false
            libraryItem.titlebarSeparatorStyle = .line

            documentItem = NSSplitViewItem(viewController: documentTabsController)
            documentItem.canCollapse = false
            documentItem.canCollapseFromWindowResize = false
            documentItem.allowsFullHeightLayout = true
            documentItem.automaticallyAdjustsSafeAreaInsets = false
            documentItem.titlebarSeparatorStyle = .line

            apparatusItem = NSSplitViewItem(
                inspectorWithViewController: apparatusHost
            )

            addSplitViewItem(libraryItem)
            addSplitViewItem(documentItem)
            addSplitViewItem(apparatusItem)
            libraryItem.isCollapsed = !lastLibraryVisible
            observesResearchInspectorVisibility = true
        }

        override func viewWillAppear() {
            super.viewWillAppear()
            // Let the semantic Inspector enter an attached split hierarchy in
            // its native default state before applying the window's saved
            // visibility. Collapsing it while the controller is detached
            // prevents AppKit from establishing the default Inspector width,
            // leaving no native geometry for a later toggle to restore.
            reconcileVisibility(animated: false)
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            guard let window = view.window else { return }
            registeredWindow = window
            ScholiumWorkspaceSplitRegistry.shared.register(self, in: window)
        }

        override func viewDidDisappear() {
            ScholiumWorkspaceSplitRegistry.shared.unregister(
                self,
                from: registeredWindow
            )
            registeredWindow = nil
            super.viewDidDisappear()
        }

        func scheduleUpdate(
            library: Library,
            document: Document,
            apparatus: Apparatus,
            documentTabs: [DocumentTabItem],
            selectedDocumentTabID: UUID?,
            selectDocumentTab: @escaping (UUID) -> Void,
            closeDocumentTab: @escaping (UUID) -> Void,
            researchInspectorVisibilityDidChange: @escaping (Bool) -> Void,
            libraryVisible: Bool,
            apparatusVisible: Bool,
            animated: Bool
        ) {
            pendingUpdate = (
                library,
                document,
                apparatus,
                documentTabs,
                selectedDocumentTabID,
                selectDocumentTab,
                closeDocumentTab,
                researchInspectorVisibilityDidChange,
                libraryVisible,
                apparatusVisible,
                animated
            )
            guard !isUpdateScheduled else { return }
            isUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isUpdateScheduled = false
                guard let update = self.pendingUpdate else { return }
                self.pendingUpdate = nil
                self.libraryHost.rootView = update.library
                self.documentTabsController.update(
                    document: update.document,
                    tabs: update.documentTabs,
                    selectedTabID: update.selectedDocumentTabID,
                    selectTab: update.selectDocumentTab,
                    closeTab: update.closeDocumentTab
                )
                self.apparatusHost.rootView = update.apparatus
                self.researchInspectorVisibilityDidChange =
                    update.researchInspectorVisibilityDidChange
                self.updateVisibility(
                    libraryVisible: update.libraryVisible,
                    apparatusVisible: update.apparatusVisible,
                    animated: update.animated
                )
            }
        }

        func updateVisibility(
            libraryVisible: Bool,
            apparatusVisible: Bool,
            animated: Bool
        ) {
            guard isViewLoaded else { return }
            let visibilityChanged = libraryVisible != lastLibraryVisible
                || apparatusVisible != lastApparatusVisible
            lastLibraryVisible = libraryVisible
            lastApparatusVisible = apparatusVisible
            guard visibilityChanged else { return }
            reconcileVisibility(animated: animated)
        }

        private func reconcileVisibility(animated: Bool) {
            guard isViewLoaded,
                  libraryItem != nil,
                  apparatusItem != nil
            else { return }
            let libraryShouldCollapse = !lastLibraryVisible
            let apparatusShouldCollapse = !lastApparatusVisible
            guard libraryItem.isCollapsed != libraryShouldCollapse
                    || apparatusItem.isCollapsed != apparatusShouldCollapse
            else { return }
            if libraryItem.isCollapsed != libraryShouldCollapse {
                guard animated else {
                    libraryItem.isCollapsed = libraryShouldCollapse
                    splitView.layoutSubtreeIfNeeded()
                    applyInspectorVisibility(
                        shouldCollapse: apparatusShouldCollapse
                    )
                    return
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.allowsImplicitAnimation = true
                    libraryItem.isCollapsed = libraryShouldCollapse
                }
            }
            applyInspectorVisibility(
                shouldCollapse: apparatusShouldCollapse
            )
        }

        private func applyInspectorVisibility(
            shouldCollapse: Bool
        ) {
            guard apparatusItem.isCollapsed != shouldCollapse else { return }
            // AppKit owns the Inspector's standard collapse animation and
            // divider/toolbar tracking behavior.
            toggleInspector(nil)
        }

        override func splitViewDidResizeSubviews(_ notification: Notification) {
            super.splitViewDidResizeSubviews(notification)
            guard observesResearchInspectorVisibility,
                  apparatusItem != nil
            else { return }
            let isVisible = !apparatusItem.isCollapsed
            guard isVisible != lastApparatusVisible else { return }
            lastApparatusVisible = isVisible
            researchInspectorVisibilityDidChange(isVisible)
        }

    }
}

enum ScholiumWorkspaceSplitViewIdentifier {
    static let value = NSUserInterfaceItemIdentifier("scholium.workspaceSplitView")
}

private enum ScholiumDocumentTabLayout {
    static let stripHeight: CGFloat = 38
    static let stripTopInset: CGFloat = 6
    static let stripHorizontalInset: CGFloat = 18
    static let tabHorizontalInset: CGFloat = 6
    static let titleSpacing: CGFloat = 4
    static let balancedControlWidth: CGFloat = 20
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
