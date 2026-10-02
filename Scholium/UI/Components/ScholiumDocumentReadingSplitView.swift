import AppKit
import SwiftUI

/// AppKit retains the two content hosts and owns their divider and collapse.
/// The feature controller projects visibility and receives completed widths;
/// neither SwiftUI updates nor note changes reconstruct the Markdown host.
@MainActor
final class ScholiumDocumentReadingSplitController: NSSplitViewController {
    static let participationDidChange = Notification.Name("scholium.documentReadingSplit.participationDidChange")
    let documentController: NSViewController
    let readerController: NSViewController
    private(set) var documentItem: NSSplitViewItem!
    private(set) var readerItem: NSSplitViewItem!
    private var requestedVisible: Bool
    private var requestedWidth: Double
    private var widthDidChange: (Double) -> Void
    private var focusDocument: () -> Void
    private var needsWidthOffer: Bool
    private var isApplyingLayout = false
    private var isInvalidated = false

    var readerIsVisible: Bool {
        guard !isInvalidated, isViewLoaded, let readerItem else { return false }
        return !readerItem.isCollapsed
    }

    /// Locate only this application's native owner through public view containment.
    /// SwiftUI can attach a representable after the window's toolbar is installed.
    static func find(in view: NSView) -> ScholiumDocumentReadingSplitController? {
        if let split = view as? NSSplitView,
            let controller = split.delegate as? ScholiumDocumentReadingSplitController,
            !controller.isInvalidated, controller.splitView === split
        {
            return controller
        }
        for child in view.subviews {
            if let controller = find(in: child) { return controller }
        }
        return nil
    }

    init(
        documentController: NSViewController,
        readerController: NSViewController,
        readerVisible: Bool,
        readerWidth: Double,
        widthDidChange: @escaping (Double) -> Void,
        focusDocument: @escaping () -> Void
    ) {
        self.documentController = documentController
        self.readerController = readerController
        requestedVisible = readerVisible
        requestedWidth = readerWidth
        self.widthDidChange = widthDidChange
        self.focusDocument = focusDocument
        needsWidthOffer = readerVisible
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only Document reading split") }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.identifier = .init("scholium.documentReadingSplit")
        splitView.setAccessibilityIdentifier("scholium.documentReadingSplit")
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        documentItem = NSSplitViewItem(viewController: documentController)
        documentItem.canCollapse = false
        documentItem.canCollapseFromWindowResize = false
        documentItem.minimumThickness = 240
        documentItem.automaticallyAdjustsSafeAreaInsets = true
        readerItem = NSSplitViewItem(viewController: readerController)
        readerItem.automaticallyAdjustsSafeAreaInsets = true
        readerItem.isCollapsed = !requestedVisible
        readerItem.minimumThickness = 280
        readerItem.maximumThickness = NSSplitViewItem.unspecifiedDimension
        readerItem.holdingPriority = .init(rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1)
        readerItem.canCollapse = false
        readerItem.canCollapseFromWindowResize = false
        readerItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        addSplitViewItem(documentItem)
        addSplitViewItem(readerItem)
        synchronizeReaderParticipation()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        offerWidthIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        publishParticipation()
    }

    func update(
        readerVisible: Bool,
        readerWidth: Double,
        widthDidChange: @escaping (Double) -> Void,
        focusDocument: @escaping () -> Void
    ) {
        guard !isInvalidated else { return }
        self.widthDidChange = widthDidChange
        self.focusDocument = focusDocument
        requestedWidth = readerWidth
        guard requestedVisible != readerVisible else { return }
        requestedVisible = readerVisible
        needsWidthOffer = readerVisible
        guard isViewLoaded else { return }
        if !readerVisible { relinquishReaderFocus() }
        isApplyingLayout = true
        readerItem.isCollapsed = !readerVisible
        synchronizeReaderParticipation()
        splitView.layoutSubtreeIfNeeded()
        isApplyingLayout = false
        offerWidthIfNeeded()
        publishParticipation()
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        recordVisibleWidth()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        if isViewLoaded {
            relinquishReaderFocus()
            if readerController.isViewLoaded {
                readerController.view.isHidden = true
                readerController.view.setAccessibilityHidden(true)
            }
        }
        widthDidChange = { _ in }
        focusDocument = {}
        publishParticipation()
    }

    private func publishParticipation() {
        NotificationCenter.default.post(name: Self.participationDidChange, object: self)
    }

    private func offerWidthIfNeeded() {
        guard !isInvalidated, needsWidthOffer, requestedVisible,
            !isApplyingLayout, isViewLoaded, !readerItem.isCollapsed,
            splitViewItems.count == 2, splitView.bounds.width > 0
        else { return }
        needsWidthOffer = false
        guard requestedWidth.isFinite, requestedWidth > 0 else {
            recordVisibleWidth()
            return
        }
        isApplyingLayout = true
        splitView.setPosition(
            splitView.bounds.maxX - CGFloat(requestedWidth) - splitView.dividerThickness,
            ofDividerAt: 0
        )
        splitView.layoutSubtreeIfNeeded()
        isApplyingLayout = false
        recordVisibleWidth()
    }

    private func recordVisibleWidth() {
        guard !isInvalidated, !isApplyingLayout, !needsWidthOffer,
            requestedVisible, readerItem != nil, !readerItem.isCollapsed
        else { return }
        let width = readerController.view.frame.width
        guard width.isFinite, width > 0 else { return }
        widthDidChange(Double(width))
    }

    private func synchronizeReaderParticipation() {
        guard requestedVisible || readerController.isViewLoaded else { return }
        readerController.view.isHidden = !requestedVisible
        readerController.view.setAccessibilityHidden(!requestedVisible)
    }

    private func relinquishReaderFocus() {
        guard readerController.isViewLoaded, let window = view.window else { return }
        let responder =
            (window.firstResponder as? NSTextView)?.delegate as? NSView
            ?? window.firstResponder as? NSView
        guard let responder,
            responder === readerController.view || responder.isDescendant(of: readerController.view)
        else { return }
        window.makeFirstResponder(nil)
        focusDocument()
    }
}

/// Detached Notes use the same native reading container without a tab owner.
struct ScholiumDocumentReadingSplitView<Document: View, Reader: View>: NSViewControllerRepresentable {
    let readerVisible: Bool
    let readerWidth: Double
    let widthDidChange: (Double) -> Void
    let focusDocument: () -> Void
    let document: Document
    let reader: Reader

    func makeNSViewController(context: Context) -> ScholiumDocumentReadingSplitController {
        let documentHost = NSHostingController(rootView: document)
        let readerHost = NSHostingController(rootView: reader)
        documentHost.sizingOptions = []
        readerHost.sizingOptions = []
        let controller = ScholiumDocumentReadingSplitController(
            documentController: documentHost,
            readerController: ScholiumSurfaceContainerViewController(
                contentViewController: readerHost, backgroundRole: .document,
                contentExtendsUnderToolbar: true
            ),
            readerVisible: readerVisible, readerWidth: readerWidth,
            widthDidChange: widthDidChange, focusDocument: focusDocument
        )
        _ = controller.view
        return controller
    }

    func updateNSViewController(_ controller: ScholiumDocumentReadingSplitController, context: Context) {
        (controller.documentController as? NSHostingController<Document>)?.rootView = document
        let readerSurface = controller.readerController as? ScholiumSurfaceContainerViewController
        (readerSurface?.contentViewController as? NSHostingController<Reader>)?.rootView = reader
        controller.update(
            readerVisible: readerVisible, readerWidth: readerWidth,
            widthDidChange: widthDidChange, focusDocument: focusDocument
        )
    }

    static func dismantleNSViewController(_ controller: ScholiumDocumentReadingSplitController, coordinator: ()) {
        controller.invalidate()
    }
}
