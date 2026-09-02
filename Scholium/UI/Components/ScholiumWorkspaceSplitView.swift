import AppKit
import SwiftUI

/// Draws a document-owned shadow into the navigation plane without placing a
/// second visible rule beside AppKit's tracking separator. The one-point caster
/// sits just beyond the clipped Library bounds, so only its inward shadow is
/// visible and the native divider remains visually and interactively intact.
private struct ScholiumStructuralDepthView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumAppearsActive) private var appearsActive

    let role: ScholiumStructuralDepthRole

    var body: some View {
        let style = role.style(
            isDark: colorScheme == .dark,
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency,
            appearsActive: appearsActive,
            layoutDirection: layoutDirection
        )
        let casterIsTrailing = role.castsFromTrailingEdge
        let casterAlignment: Alignment = if casterIsTrailing {
            layoutDirection == .leftToRight ? .trailing : .leading
        } else {
            layoutDirection == .leftToRight ? .leading : .trailing
        }
        let casterOffset: CGFloat = if casterIsTrailing {
            layoutDirection == .leftToRight ? 1 : -1
        } else {
            layoutDirection == .leftToRight ? -1 : 1
        }
        ZStack(alignment: casterAlignment) {
            Color.clear
            Rectangle()
                .fill(ScholiumColorRole.documentBackground.color(
                    increasedContrast: increasedContrast
                ))
                .frame(width: 1)
                .shadow(
                    color: ScholiumNativeColorRole.structuralShadow.color.opacity(style.opacity),
                    radius: style.radius,
                    x: style.x,
                    y: style.y
                )
                .offset(x: casterOffset)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private final class ScholiumStructuralDepthHostingView:
    NSHostingView<ScholiumStructuralDepthView>
{
    /// The decorative projection never becomes a second divider hit target.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// `NSHostingView` can restore itself as an accessibility element after
    /// loading even when its SwiftUI content is hidden from accessibility.
    override func isAccessibilityElement() -> Bool { false }
}

/// One opaque semantic plane for a native split item. The same background view
/// fills the complete region beneath the transparent titlebar, while foreground
/// content remains a sibling in the live safe area.
/// A flat color needs no background-extension effect, so AppKit cannot mirror,
/// blur, or retint it at the toolbar edge.
@MainActor
final class ScholiumSurfaceContainerViewController: NSViewController {
    let contentViewController: NSViewController
    let backgroundView: NSView
    let structuralDepthView: NSView?

    init(
        contentViewController: NSViewController,
        backgroundRole: ScholiumSurfaceRole,
        structuralDepthRole: ScholiumStructuralDepthRole? = nil
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
        if let structuralDepthRole {
            let depthHost = ScholiumStructuralDepthHostingView(
                rootView: ScholiumStructuralDepthView(role: structuralDepthRole)
            )
            depthHost.safeAreaRegions = []
            depthHost.setAccessibilityElement(false)
            structuralDepthView = depthHost
        } else {
            structuralDepthView = nil
        }
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
        if let structuralDepthView {
            structuralDepthView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(structuralDepthView)
        }

        var constraints = [
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
        if let structuralDepthView {
            constraints += [
                structuralDepthView.leadingAnchor.constraint(
                    equalTo: containerView.leadingAnchor
                ),
                structuralDepthView.trailingAnchor.constraint(
                    equalTo: containerView.trailingAnchor
                ),
                structuralDepthView.topAnchor.constraint(
                    equalTo: containerView.topAnchor
                ),
                structuralDepthView.bottomAnchor.constraint(
                    equalTo: containerView.bottomAnchor
                ),
            ]
        }
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
        private let firstApparatusWidthOffer = ScholiumFirstApparatusWidthOffer()
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
            // The native split item is the sole width owner. Inspector content
            // fills the container but must not publish intrinsic, minimum, or
            // maximum sizes back into AppKit as modes and content change.
            apparatusHost.sizingOptions = []
            self.libraryHost = libraryHost
            self.documentTabsController = documentTabsController
            self.apparatusHost = apparatusHost
            libraryBackgroundController = ScholiumSurfaceContainerViewController(
                contentViewController: libraryHost,
                backgroundRole: .navigation,
                structuralDepthRole: .documentNavigationBoundary
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

            documentItem = NSSplitViewItem(
                viewController: documentBackgroundController
            )
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
            let retainedApparatusWidth = currentApparatusWidth
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.allowsImplicitAnimation = true
                    libraryItem.isCollapsed = !visible
                } completionHandler: {
                    Task { @MainActor in
                        self.restoreApparatusWidth(retainedApparatusWidth)
                    }
                }
            } else {
                libraryItem.isCollapsed = !visible
                splitView.layoutSubtreeIfNeeded()
                restoreApparatusWidth(retainedApparatusWidth)
            }
            reportVisibility()
        }

        private var currentApparatusWidth: CGFloat? {
            guard apparatusItem != nil,
                  !apparatusItem.isCollapsed,
                  let apparatusView = splitView.arrangedSubviews.last
            else { return nil }
            splitView.layoutSubtreeIfNeeded()
            return apparatusView.frame.width
        }

        private func restoreApparatusWidth(_ width: CGFloat?) {
            guard let width,
                  apparatusItem != nil,
                  !apparatusItem.isCollapsed,
                  splitView.arrangedSubviews.count >= 3
            else { return }
            splitView.layoutSubtreeIfNeeded()
            splitView.setPosition(
                splitView.bounds.maxX - width,
                ofDividerAt: splitView.arrangedSubviews.count - 2
            )
            splitView.layoutSubtreeIfNeeded()
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

    private final class TabSelectorViews {
        let container: NSView
        let title: TabButton
        let close: TabButton
        let selectionRule: NSView

        init(container: NSView, title: TabButton, close: TabButton, selectionRule: NSView) {
            self.container = container
            self.title = title
            self.close = close
            self.selectionRule = selectionRule
        }
    }

    private let tabViewController = NSTabViewController()
    private let tabButtonStack = NSStackView()
    private let tabStrip = NSView()
    private var tabStripHeightConstraint: NSLayoutConstraint!
    private var pageHosts: [UUID: NSHostingController<Document>] = [:]
    private var pageItems: [UUID: NSTabViewItem] = [:]
    private var selectorViews: [UUID: TabSelectorViews] = [:]
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
        tabStrip.setAccessibilityElement(true)
        tabStrip.setAccessibilityRole(.group)
        tabStrip.setAccessibilityLabel("Document Tabs")
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
                      ), currentIndex != index {
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
           let selectedIndex = tabs.firstIndex(where: { $0.id == selectedTabID }) {
            tabViewController.selectedTabViewItemIndex = selectedIndex
        } else if showsPlaceholder,
                  let placeholderIndex = tabViewController.tabViewItems.firstIndex(
                    where: { $0 === placeholderItem }
                  ) {
            tabViewController.selectedTabViewItemIndex = placeholderIndex
        }
        rebuildSelector()
    }

    private func rebuildSelector() {
        let currentIDs = Set(tabs.map(\.id))
        for staleID in Set(selectorViews.keys).subtracting(currentIDs) {
            guard let stale = selectorViews.removeValue(forKey: staleID) else { continue }
            tabButtonStack.removeArrangedSubview(stale.container)
            stale.container.removeFromSuperview()
        }
        for (index, tab) in tabs.enumerated() {
            let selector = selectorViews[tab.id] ?? makeTabItem(for: tab)
            selectorViews[tab.id] = selector
            if !tabButtonStack.arrangedSubviews.contains(where: { $0 === selector.container }) {
                tabButtonStack.insertArrangedSubview(selector.container, at: index)
            } else if let currentIndex = tabButtonStack.arrangedSubviews.firstIndex(
                where: { $0 === selector.container }
            ), currentIndex != index {
                tabButtonStack.removeArrangedSubview(selector.container)
                tabButtonStack.insertArrangedSubview(selector.container, at: index)
            }
            update(selector, for: tab, isSelected: tab.id == selectedTabID)
        }
        let showsTabStrip = tabs.count > 1
        tabStrip.isHidden = !showsTabStrip
        tabStripHeightConstraint.constant = showsTabStrip
            ? ScholiumDocumentTabLayout.stripHeight
            : 0
    }

    private func makeTabItem(for tab: DocumentTabItem) -> TabSelectorViews {
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
            weight: .regular
        )
        titleButton.contentTintColor = ScholiumColorRole.secondaryText.nsColor
        titleButton.toolTip = tab.toolTip
        titleButton.lineBreakMode = .byTruncatingTail
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleButton.setAccessibilityLabel(tab.title)
        titleButton.setAccessibilityValue("")

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
        closeButton.contentTintColor = ScholiumColorRole.secondaryText.nsColor
        closeButton.toolTip = closeLabel
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setAccessibilityLabel(closeLabel)
        closeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let selectionRule = NSView()
        selectionRule.wantsLayer = true
        selectionRule.layer?.backgroundColor = NSColor.clear.cgColor
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
        return TabSelectorViews(
            container: item,
            title: titleButton,
            close: closeButton,
            selectionRule: selectionRule
        )
    }

    private func update(
        _ selector: TabSelectorViews,
        for tab: DocumentTabItem,
        isSelected: Bool
    ) {
        selector.title.title = tab.title
        selector.title.toolTip = tab.toolTip
        selector.title.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: isSelected ? .medium : .regular
        )
        selector.title.contentTintColor = isSelected
            ? ScholiumColorRole.primaryText.nsColor
            : ScholiumColorRole.secondaryText.nsColor
        selector.title.setAccessibilityLabel(tab.title)
        selector.title.setAccessibilityValue(isSelected ? "Selected" : "")
        let closeLabel = "Close \(tab.title)"
        selector.close.toolTip = closeLabel
        selector.close.setAccessibilityLabel(closeLabel)
        selector.selectionRule.layer?.backgroundColor = isSelected
            ? ScholiumColorRole.accent.nsColor.cgColor
            : NSColor.clear.cgColor
    }

    #if DEBUG
    func testingPageHost(for id: UUID) -> AnyObject? { pageHosts[id] }
    func testingPageItem(for id: UUID) -> AnyObject? { pageItems[id] }
    func testingSelectorView(for id: UUID) -> AnyObject? { selectorViews[id]?.container }
    func testingPageLabel(for id: UUID) -> String? { pageItems[id]?.label }
    #endif

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
