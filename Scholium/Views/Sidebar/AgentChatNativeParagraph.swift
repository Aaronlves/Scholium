import AppKit
import SwiftUI

/// A plain message paragraph. The caller owns source identity and reading state;
/// AppKit owns selection, copying and the live text layout.
struct AgentChatNativeParagraph: NSViewRepresentable {
    @Environment(\.isEnabled) private var environmentIsEnabled
    @Environment(\.scholiumDocumentSurfaceVisibility) private var surfaceVisibility
    let source: String
    let revision: String
    let fitsContent: Bool
    let isInteractive: Bool
    let onInteraction: () -> Void
    let onLayout: (String, CGSize) -> Void

    func makeNSView(context: Context) -> AgentChatNativeParagraphView {
        AgentChatNativeParagraphView()
    }

    func updateNSView(_ view: AgentChatNativeParagraphView, context: Context) {
        view.setSurfaceVisibility(surfaceVisibility)
        view.configure(
            source: source, revision: revision, fitsContent: fitsContent,
            isInteractive: isInteractive && environmentIsEnabled,
            onInteraction: onInteraction, onLayout: onLayout)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatNativeParagraphView, context: Context) -> CGSize? {
        nsView.fittingSize(proposedWidth: proposal.width)
    }

    static func dismantleNSView(_ view: AgentChatNativeParagraphView, coordinator: ()) {
        view.detach()
    }
}

@MainActor final class AgentChatNativeParagraphView: NSTextView, NSTextViewDelegate {
    private let retainedStorage: NSTextStorage
    private let measurementStorage = NSTextStorage()
    private let measurementLayout = NSLayoutManager()
    private let measurementContainer = NSTextContainer(containerSize: .zero)
    private var source: String?
    private var revision = ""
    private var fitsContent = false
    private var surfaceVisibility: DocumentSurfaceVisibility = .active
    private var interactionIsEnabled = false
    private var suppressSelectionNotification = false
    private var onInteraction: (() -> Void)?
    private var onLayout: ((String, CGSize) -> Void)?
    private var layoutGeneration: UInt64 = 0
    private var pendingLayout: LayoutReport?
    private var reportedLayout: LayoutReport?
    private var reportIsScheduled = false

    private struct LayoutReport: Equatable {
        let generation: UInt64
        let revision: String
        let size: CGSize
    }

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        retainedStorage = storage
        super.init(frame: .zero, textContainer: container)

        measurementStorage.addLayoutManager(measurementLayout)
        measurementLayout.addTextContainer(measurementContainer)
        layout.usesFontLeading = false
        measurementLayout.usesFontLeading = false
        container.lineFragmentPadding = 0
        measurementContainer.lineFragmentPadding = 0
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        isEditable = false
        isSelectable = false
        isRichText = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        importsGraphics = false
        allowsUndo = false
        drawsBackground = false
        textContainerInset = .zero
        isHorizontallyResizable = false
        isVerticallyResizable = false
        delegate = self
        // Keep NSTextView's native text role and selection accessibility APIs.
        // The source is its standard value, rather than a duplicate spoken label.
        setAccessibilityIdentifier("scholium.chat.nativeParagraph")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Preparing keeps real layout without input or accessibility. Retained
    /// paragraphs keep their source and selection without compositing.
    func setSurfaceVisibility(_ visibility: DocumentSurfaceVisibility) {
        let changed = surfaceVisibility != visibility
        surfaceVisibility = visibility
        setAccessibilityHidden(!visibility.isActive)
        let isRetained = visibility == .retained
        if isHidden != isRetained { isHidden = isRetained }
        updateInteraction()
        if changed { needsLayout = true }
    }

    func configure(
        source: String, revision: String, fitsContent: Bool, isInteractive: Bool,
        onInteraction: @escaping () -> Void, onLayout: @escaping (String, CGSize) -> Void
    ) {
        self.onInteraction = onInteraction
        self.onLayout = onLayout
        interactionIsEnabled = isInteractive
        updateInteraction()

        let font = ScholiumChatAppearance.messageNSFont
        let foreground = ScholiumChatAppearance.messageNSForeground
        let sourceChanged = self.source.map { !$0.utf8.elementsEqual(source.utf8) } ?? true
        let revisionChanged = !self.revision.utf8.elementsEqual(revision.utf8)
        let styleChanged = self.font != font || textColor != foreground
        let fitChanged = self.fitsContent != fitsContent
        self.revision = revision
        self.fitsContent = fitsContent
        guard sourceChanged || revisionChanged || styleChanged || fitChanged else { return }

        layoutGeneration &+= 1
        pendingLayout = nil
        if sourceChanged || styleChanged {
            let paragraph = NSMutableParagraphStyle()
            let lineHeight = font.pointSize * ScholiumChatAppearance.messageLineHeight
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
            paragraph.lineBreakMode = .byWordWrapping
            let content = NSAttributedString(
                string: source,
                attributes: [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph])
            suppressSelectionNotification = true
            let selection = selectedRanges
            retainedStorage.setAttributedString(content)
            measurementStorage.setAttributedString(content)
            if !sourceChanged { selectedRanges = selection }
            suppressSelectionNotification = false
            self.source = source
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func fittingSize(proposedWidth: CGFloat?) -> CGSize {
        // SwiftUI's probes must never resize the live text container, move its
        // selection or change its accessibility frame.
        let availableWidth = positiveFinite(proposedWidth) ?? positiveFinite(bounds.width)
        let width: CGFloat
        if fitsContent || availableWidth == nil {
            let naturalWidth = measuredSize(width: CGFloat.greatestFiniteMagnitude).width
            width = min(availableWidth ?? naturalWidth, naturalWidth)
        } else {
            width = availableWidth ?? 1
        }
        let fittedWidth = max(1, width)
        return CGSize(width: fittedWidth, height: measuredSize(width: fittedWidth).height)
    }

    private func measuredSize(width: CGFloat) -> CGSize {
        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if measurementContainer.containerSize != size { measurementContainer.containerSize = size }
        measurementLayout.ensureLayout(for: measurementContainer)
        let used = measurementLayout.usedRect(for: measurementContainer)
        return CGSize(
            width: min(width, max(1, ceil(used.width))),
            height: max(ScholiumChatAppearance.messageLoadingHeight, ceil(used.height)))
    }

    override func layout() {
        super.layout()
        guard let width = positiveFinite(bounds.width), positiveFinite(bounds.height) != nil,
            let textContainer, let layoutManager
        else { return }
        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if textContainer.containerSize != size { textContainer.containerSize = size }
        layoutManager.ensureLayout(for: textContainer)
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return }
        enqueueLayout(LayoutReport(generation: layoutGeneration, revision: revision, size: bounds.size))
    }

    private func enqueueLayout(_ report: LayoutReport) {
        guard report != reportedLayout, report != pendingLayout else { return }
        pendingLayout = report
        guard !reportIsScheduled else { return }
        reportIsScheduled = true
        // Publish outside AppKit/SwiftUI layout, coalescing probes and rejecting
        // an obsolete source, detached view or a width awaiting its next layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reportIsScheduled = false
            guard let report = self.pendingLayout else { return }
            self.pendingLayout = nil
            guard report.generation == self.layoutGeneration,
                report.size == self.bounds.size,
                self.window != nil, !self.isHiddenOrHasHiddenAncestor,
                let onLayout = self.onLayout
            else { return }
            self.reportedLayout = report
            onLayout(report.revision, report.size)
        }
    }

    private func positiveFinite(_ value: CGFloat?) -> CGFloat? {
        guard let value, value.isFinite, value > 0, value < CGFloat.greatestFiniteMagnitude else { return nil }
        return value
    }

    private var canInteract: Bool {
        interactionIsEnabled && surfaceVisibility.isActive && window != nil && !isHiddenOrHasHiddenAncestor
    }

    private func updateInteraction() {
        suppressSelectionNotification = true
        isSelectable = canInteract
        if !canInteract, let window, window.firstResponder === self { window.makeFirstResponder(nil) }
        suppressSelectionNotification = false
    }

    override var acceptsFirstResponder: Bool { canInteract && super.acceptsFirstResponder }

    override func hitTest(_ point: NSPoint) -> NSView? {
        canInteract ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard canInteract else { return }
        onInteraction?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard canInteract else { return }
        onInteraction?()
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard canInteract else { return }
        onInteraction?()
        super.keyDown(with: event)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard canInteract, !suppressSelectionNotification else { return }
        onInteraction?()
    }

    override func setAccessibilitySelectedTextRange(_ range: NSRange) {
        guard canInteract else { return }
        onInteraction?()
        super.setAccessibilitySelectedTextRange(range)
    }

    override func setAccessibilitySelectedTextRanges(_ ranges: [NSValue]?) {
        guard canInteract else { return }
        onInteraction?()
        super.setAccessibilitySelectedTextRanges(ranges)
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateInteraction()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateInteraction()
        needsLayout = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window, let window, window.firstResponder === self { window.makeFirstResponder(nil) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateInteraction()
        needsLayout = true
    }

    func detach() {
        interactionIsEnabled = false
        updateInteraction()
        onInteraction = nil
        onLayout = nil
        layoutGeneration &+= 1
        pendingLayout = nil
    }
}
