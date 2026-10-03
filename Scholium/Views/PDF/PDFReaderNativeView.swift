import AppKit
import PDFKit
import SwiftUI

/// Native sibling composition keeps controls outside PDFKit's paper and AX
/// subtree. The PDF view remains the reading/selection/session adapter.
@MainActor
final class PDFReaderNativeHostView: NSView {
    let pdfView: PDFReaderNativePDFView

    init(pdfView: PDFReaderNativePDFView) {
        self.pdfView = pdfView
        super.init(frame: pdfView.bounds)
        pdfView.frame = bounds
        pdfView.autoresizingMask = [.width, .height]
        addSubview(pdfView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only PDF host") }

    override func accessibilityChildren() -> [Any]? { isHidden ? [] : subviews }
}

/// PDFKit owns reading, selection, links and scrolling. This adapter translates
/// only reader-tool input and reports native state to the current controller.
@MainActor
final class PDFReaderNativePDFView: PDFView {
    static let contentRevealAnimationKey = "scholium.pdf.contentReveal"
    weak var controller: PDFReaderController?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private var activityTrackingArea: NSTrackingArea?
    private var clipObserver: NSObjectProtocol?
    private weak var observedClip: NSClipView?
    private var previousBoundsNotifications = false
    private weak var gestureDocument: PDFDocument?
    private var needsAttachment = false
    private var isRestoring = false
    private var isInvalidated = false
    private var interactionGeneration: UInt64 = 0
    private var needsContentReveal = false
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var displayOptionsObserver: NSObjectProtocol?
    private(set) var floatingTools: PDFReaderFloatingToolsView?
    private weak var insetScrollView: NSScrollView?
    private var originalScrollInsets = NSEdgeInsets()
    private var originalAutomaticInsets = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        displayMode = .singlePageContinuous
        displayDirection = .vertical
        autoScales = true
        backgroundColor = .textBackgroundColor
        setAccessibilityIdentifier("PDFReader.View")
        setAccessibilityLabel(ScholiumL10n.string("PDF Reader"))
        installObservers()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self?.stopContentReveal() }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only PDF reader") }

    func updatePresentation(reduceMotion: Bool) {
        guard !isInvalidated else { return }
        self.reduceMotion = reduceMotion
        floatingTools?.updatePresentation(reduceMotion: reduceMotion)
        if reduceMotion { stopContentReveal() }
    }

    func apply(_ controller: PDFReaderController) {
        guard !isInvalidated else { return }
        let ownerChanged = self.controller !== controller
        if ownerChanged {
            self.controller?.detach(view: self)
            self.controller = controller
        }
        if ownerChanged || document !== controller.document {
            floatingTools?.cancelTracking()
            restoreScrollInsets()
            stopContentReveal()
            interactionGeneration &+= 1
            gestureDocument = nil
            isRestoring = true
            document = controller.document
            needsAttachment = document != nil
            needsContentReveal = document != nil
            isRestoring = false
            synchronizeClipObserver()
        }
        installFloatingToolsIfNeeded(controller)
        floatingTools?.update(controller)
        attachWhenReady()
        revealContentWhenReady()
    }

    override func layout() {
        super.layout()
        synchronizeClipObserver()
        attachWhenReady()
        synchronizeScrollInsets()
        if let controller { floatingTools?.update(controller) }
        revealContentWhenReady()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        attachWhenReady()
        synchronizeScrollInsets()
        if let controller { floatingTools?.update(controller) }
        revealContentWhenReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeEventMonitor()
        removeActivityTrackingArea()
        interactionGeneration &+= 1
        gestureDocument = nil
        floatingTools?.cancelTracking()
        guard !isInvalidated, window != nil else {
            stopContentReveal()
            restoreScrollInsets()
            if let controller { floatingTools?.update(controller) }
            return
        }
        // PDFKit's document subview may handle pointer events before PDFView.
        // Observe only this view's exact window and visible content boundary.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown, .leftMouseDragged, .rightMouseDragged, .scrollWheel]
        ) { [weak self] event in
            let shouldDeliver = MainActor.assumeIsolated {
                guard let self else { return true }
                return self.route(event) != nil
            }
            return shouldDeliver ? event : nil
        }
        updateTrackingAreas()
        attachWhenReady()
        if let controller { floatingTools?.update(controller) }
        synchronizeScrollInsets()
        revealContentWhenReady()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        removeActivityTrackingArea()
        guard !isInvalidated, window != nil else { return }
        // Tracking requests movement for this reader viewport directly, without
        // changing the window's acceptsMouseMovedEvents or PDFKit cursor areas.
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        activityTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        _ = route(event)
        super.mouseMoved(with: event)
    }

    private func removeActivityTrackingArea() {
        if let activityTrackingArea { removeTrackingArea(activityTrackingArea) }
        activityTrackingArea = nil
    }

    override func viewDidHide() {
        super.viewDidHide()
        interactionGeneration &+= 1
        gestureDocument = nil
        stopContentReveal()
        floatingTools?.cancelTracking()
        if let controller { floatingTools?.update(controller) }
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        needsContentReveal = document != nil
        attachWhenReady()
        if let controller { floatingTools?.update(controller) }
        revealContentWhenReady()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        controller?.detach(view: self)
        isInvalidated = true
        interactionGeneration &+= 1
        gestureDocument = nil
        controller = nil
        floatingTools?.invalidate()
        restoreScrollInsets()
        stopContentReveal()
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
        displayOptionsObserver = nil
        removeEventMonitor()
        removeActivityTrackingArea()
        removeClipObserver()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        document = nil
    }

    private func attachWhenReady() {
        guard !isInvalidated, needsAttachment, !isRestoring,
            window != nil, !isHiddenOrHasHiddenAncestor,
            bounds.width > 0, bounds.height > 0,
            let controller, document != nil, document === controller.document
        else { return }
        needsAttachment = false
        isRestoring = true
        // Restoration occurs once after native geometry exists. Published
        // page, selection and save changes never reapply a reading destination.
        layoutDocumentView()
        synchronizeScrollInsets()
        controller.attach(view: self)
        isRestoring = false
        synchronizeClipObserver()
        controller.selectionDidChange()
        floatingTools?.update(controller)
    }

    private func installFloatingToolsIfNeeded(_ controller: PDFReaderController) {
        guard floatingTools == nil, let host = superview as? PDFReaderNativeHostView else { return }
        let tools = PDFReaderFloatingToolsView(controller: controller) { [weak self] in
            self?.canReport == true && self?.isHiddenOrHasHiddenAncestor == false && self?.controller?.isVisible == true
        }
        floatingTools = tools
        tools.updatePresentation(reduceMotion: reduceMotion)
        tools.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(tools)
        NSLayoutConstraint.activate([
            tools.centerXAnchor.constraint(equalTo: host.safeAreaLayoutGuide.centerXAnchor),
            tools.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -ScholiumMetrics.PDFReader.toolsBottomInset),
        ])
    }

    private func synchronizeScrollInsets() {
        guard !isInvalidated, let tools = floatingTools, controller?.isVisible == true,
            window != nil, !isHiddenOrHasHiddenAncestor, document != nil,
            let scroll = documentView?.enclosingScrollView
        else {
            restoreScrollInsets()
            return
        }
        if insetScrollView !== scroll {
            restoreScrollInsets()
            insetScrollView = scroll
            originalScrollInsets = scroll.contentInsets
            originalAutomaticInsets = scroll.automaticallyAdjustsContentInsets
            // Automatic tiling otherwise replaces the explicit overlay inset.
            scroll.automaticallyAdjustsContentInsets = false
        }
        let bottom =
            originalScrollInsets.bottom + tools.intrinsicContentSize.height
            + ScholiumMetrics.PDFReader.toolsBottomInset + (tools.superview?.safeAreaInsets.bottom ?? 0)
        guard abs(scroll.contentInsets.bottom - bottom) > 0.5 else { return }
        var insets = scroll.contentInsets
        insets.bottom = bottom
        scroll.contentInsets = insets
    }

    private func restoreScrollInsets() {
        guard let scroll = insetScrollView else { return }
        insetScrollView = nil
        scroll.contentInsets = originalScrollInsets
        scroll.automaticallyAdjustsContentInsets = originalAutomaticInsets
    }

    private func revealContentWhenReady() {
        guard needsContentReveal, !isInvalidated, !needsAttachment, !isRestoring,
            window != nil, !isHiddenOrHasHiddenAncestor,
            bounds.width > 0, bounds.height > 0,
            document != nil, document === controller?.document
        else { return }
        needsContentReveal = false
        stopContentReveal()
        guard !reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // Animate viewer opacity after position restoration. The model
        // stays fully visible and interactive; split geometry and PDFKit's
        // document, selection and scrolling never wait for this presentation.
        wantsLayer = true
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = ScholiumMotion.pdfContentRevealDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(animation, forKey: Self.contentRevealAnimationKey)
    }

    private func stopContentReveal() {
        layer?.removeAnimation(forKey: Self.contentRevealAnimationKey)
    }

    private func installObservers() {
        for name: Notification.Name in [.PDFViewPageChanged, .PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.reportPosition() }
                })
        }
        observers.append(
            NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: self, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.canReport else { return }
                    self.controller?.selectionDidChange()
                }
            })
    }

    private var canReport: Bool {
        !isInvalidated && !isRestoring && !needsAttachment && window != nil
            && document != nil && document === controller?.document
    }

    private func reportPosition() {
        guard canReport else { return }
        controller?.viewPositionDidChange()
    }

    private func synchronizeClipObserver() {
        guard !isInvalidated else { return }
        let clip = documentView?.enclosingScrollView?.contentView
        guard clip !== observedClip else { return }
        removeClipObserver()
        guard let clip else { return }
        observedClip = clip
        previousBoundsNotifications = clip.postsBoundsChangedNotifications
        clip.postsBoundsChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportPosition() }
        }
    }

    private func removeClipObserver() {
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        clipObserver = nil
        observedClip?.postsBoundsChangedNotifications = previousBoundsNotifications
        observedClip = nil
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    func route(_ event: NSEvent) -> NSEvent? {
        guard !isInvalidated, !isHiddenOrHasHiddenAncestor,
            let window, event.window === window,
            let controller, let document, document === controller.document
        else { return event }
        if event.type == .keyDown {
            // Form filling is outside this reader's mutation contract. Avoid
            // PDFKit's Tab-to-widget entry without altering PDF annotation flags.
            let responder =
                (window.firstResponder as? NSTextView)?.delegate as? NSView
                ?? window.firstResponder as? NSView
            if let responder,
                responder === self || responder.isDescendant(of: self)
                    || floatingTools.map({ responder === $0 || responder.isDescendant(of: $0) }) == true
            {
                floatingTools?.noteActivity()
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control])
            if event.keyCode == 48, modifiers.isEmpty,
                let responder, responder === self || responder.isDescendant(of: self)
            {
                if event.modifierFlags.contains(.shift) { window.selectPreviousKeyView(self) } else { window.selectNextKeyView(self) }
                return nil
            }
            return event
        }
        let point = convert(event.locationInWindow, from: nil)
        // Activity is a presentation hint only. Preserve PDFKit's native
        // scrolling, dragging and cursor routing without entering tool dispatch.
        // A stationary click must not reveal the sibling before AppKit chooses
        // its target: quiet controls leave that click addressed to paper.
        if [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel].contains(event.type) {
            if window.contentLayoutRect.contains(event.locationInWindow), bounds.contains(point) {
                floatingTools?.noteActivity()
            }
            return event
        }
        // The native sibling capsule owns its input even while a PDF tool is
        // armed; surrounding paper retains highlighting and commenting.
        if let floatingTools, let host = floatingTools.superview,
            floatingTools.hitTest(host.convert(point, from: self)) != nil
        {
            gestureDocument = nil
            return event
        }
        guard window.contentLayoutRect.contains(event.locationInWindow), bounds.contains(point) else {
            if event.type == .leftMouseUp { gestureDocument = nil }
            return event
        }
        if event.type == .leftMouseUp {
            let expectedGeneration = interactionGeneration
            let completedDocument = gestureDocument
            gestureDocument = nil
            guard completedDocument === document, controller.tool == .highlight else { return event }
            // Let PDFKit finish its native selection before accepting the tool
            // action; a switch, hide or teardown revokes this completion.
            Task { @MainActor [weak self, weak document] in
                guard let self, let document,
                    !self.isInvalidated, !self.isHiddenOrHasHiddenAncestor,
                    self.interactionGeneration == expectedGeneration,
                    self.document === document, self.controller?.document === document,
                    self.controller?.tool == .highlight
                else { return }
                self.controller?.highlightSelection()
            }
            return event
        }
        guard let page = page(for: point, nearest: false), page.document === document else { return event }
        let pagePoint = convert(point, to: page)
        if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            showReaderMenu(event, page: page, point: pagePoint)
            return nil
        }
        gestureDocument = document
        if page.annotations.contains(where: {
            PDFReaderAnnotations.hasType($0, .widget) && $0.bounds.contains(pagePoint)
        }) {
            gestureDocument = nil
            window.makeFirstResponder(self)
            return nil
        }
        if let annotation = page.annotation(at: pagePoint), PDFReaderAnnotations.isEditable(annotation),
            PDFReaderAnnotations.hasType(annotation, .text) || event.clickCount >= 2
        {
            gestureDocument = nil
            controller.showAnnotation(annotation)
            return nil
        }
        if controller.tool == .comment {
            gestureDocument = nil
            controller.requestComment(on: page, at: pagePoint)
            return nil
        }
        return event
    }

    private func showReaderMenu(_ event: NSEvent, page: PDFPage, point: NSPoint) {
        guard let activity = controller?.presentationActivity else { return }
        let presentation = activity.begin()
        defer { if let presentation { activity.end(presentation) } }
        let menu = NSMenu()
        let copy = NSMenuItem(title: ScholiumL10n.string("Copy"), action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = document?.allowsCopying == true && currentSelection?.string?.isEmpty == false
        menu.addItem(copy)
        menu.addItem(.separator())
        let highlight = NSMenuItem(title: ScholiumL10n.string("Highlight Selection"), action: #selector(highlightFromMenu(_:)), keyEquivalent: "")
        highlight.target = self
        highlight.isEnabled = controller?.canAnnotate == true && currentSelection?.string?.isEmpty == false
        menu.addItem(highlight)
        let comment = NSMenuItem(title: ScholiumL10n.string("Add Comment…"), action: #selector(commentFromMenu(_:)), keyEquivalent: "")
        comment.target = self
        comment.representedObject = PDFDestination(page: page, at: point)
        comment.isEnabled = controller?.canAnnotate == true
        menu.addItem(comment)
        if let annotation = page.annotation(at: point), PDFReaderAnnotations.isEditable(annotation) {
            let read = NSMenuItem(title: ScholiumL10n.string("Read Annotation"), action: #selector(readFromMenu(_:)), keyEquivalent: "")
            read.target = self
            read.representedObject = annotation
            read.isEnabled = controller?.canUseReaderCommands == true
            menu.addItem(read)
            let edit = NSMenuItem(title: ScholiumL10n.string("Edit Annotation…"), action: #selector(editFromMenu(_:)), keyEquivalent: "")
            edit.target = self
            edit.representedObject = annotation
            edit.isEnabled = controller?.canAnnotate == true
            menu.addItem(edit)
        }
        menu.autoenablesItems = false
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func highlightFromMenu(_ sender: NSMenuItem) {
        guard canReport else { return }
        controller?.highlightSelection()
    }

    @objc private func commentFromMenu(_ sender: NSMenuItem) {
        guard canReport, let destination = sender.representedObject as? PDFDestination,
            destination.page?.document === document
        else { return }
        controller?.requestComment(on: destination.page, at: destination.point)
    }

    @objc private func readFromMenu(_ sender: NSMenuItem) {
        guard canReport, let annotation = sender.representedObject as? PDFAnnotation,
            annotation.page?.document === document
        else { return }
        controller?.showAnnotation(annotation)
    }

    @objc private func editFromMenu(_ sender: NSMenuItem) {
        guard canReport, let annotation = sender.representedObject as? PDFAnnotation,
            annotation.page?.document === document
        else { return }
        controller?.editAnnotation(annotation)
    }
}

struct PDFReaderNativeView: NSViewRepresentable {
    @ObservedObject var controller: PDFReaderController
    @Environment(\.scholiumReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> PDFReaderNativeHostView {
        let view = PDFReaderNativePDFView(frame: .zero)
        let host = PDFReaderNativeHostView(pdfView: view)
        view.updatePresentation(reduceMotion: reduceMotion)
        view.apply(controller)
        return host
    }

    func updateNSView(_ host: PDFReaderNativeHostView, context: Context) {
        host.pdfView.updatePresentation(reduceMotion: reduceMotion)
        host.pdfView.apply(controller)
    }

    static func dismantleNSView(_ host: PDFReaderNativeHostView, coordinator: ()) {
        host.pdfView.invalidate()
    }
}
