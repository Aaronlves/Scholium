import AppKit
import PDFKit
import SwiftUI

/// PDFKit owns reading, selection, links and scrolling. This adapter translates
/// only reader-tool input and reports native state to the current controller.
@MainActor
final class PDFReaderNativePDFView: PDFView {
    weak var controller: PDFReaderController?
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private var clipObserver: NSObjectProtocol?
    private weak var observedClip: NSClipView?
    private var previousBoundsNotifications = false
    private weak var gestureDocument: PDFDocument?
    private var needsAttachment = false
    private var isRestoring = false
    private var isInvalidated = false
    private var interactionGeneration: UInt64 = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        displayMode = .singlePageContinuous
        displayDirection = .vertical
        autoScales = true
        backgroundColor = .textBackgroundColor
        setAccessibilityIdentifier("PDFReader.View")
        setAccessibilityLabel(ScholiumL10n.string("PDF Reader"))
        installObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only PDF reader") }

    func apply(_ controller: PDFReaderController) {
        guard !isInvalidated else { return }
        let ownerChanged = self.controller !== controller
        if ownerChanged {
            self.controller?.detach(view: self)
            self.controller = controller
        }
        if ownerChanged || document !== controller.document {
            interactionGeneration &+= 1
            gestureDocument = nil
            isRestoring = true
            document = controller.document
            needsAttachment = document != nil
            isRestoring = false
            synchronizeClipObserver()
        }
        attachWhenReady()
    }

    override func layout() {
        super.layout()
        synchronizeClipObserver()
        attachWhenReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeEventMonitor()
        guard !isInvalidated, window != nil else { return }
        // PDFKit's document subview may handle pointer events before PDFView.
        // Observe only this view's exact window and visible content boundary.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .keyDown]) { [weak self] event in
            let shouldDeliver = MainActor.assumeIsolated {
                guard let self else { return true }
                return self.route(event) != nil
            }
            return shouldDeliver ? event : nil
        }
        attachWhenReady()
    }

    override func viewDidHide() {
        super.viewDidHide()
        interactionGeneration &+= 1
        gestureDocument = nil
    }

    func invalidate() {
        guard !isInvalidated else { return }
        controller?.detach(view: self)
        isInvalidated = true
        interactionGeneration &+= 1
        gestureDocument = nil
        controller = nil
        removeEventMonitor()
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
        controller.attach(view: self)
        isRestoring = false
        synchronizeClipObserver()
        controller.selectionDidChange()
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

    private func route(_ event: NSEvent) -> NSEvent? {
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
    let controller: PDFReaderController

    func makeNSView(context: Context) -> PDFReaderNativePDFView {
        let view = PDFReaderNativePDFView(frame: .zero)
        view.apply(controller)
        return view
    }

    func updateNSView(_ view: PDFReaderNativePDFView, context: Context) {
        view.apply(controller)
    }

    static func dismantleNSView(_ view: PDFReaderNativePDFView, coordinator: ()) {
        view.invalidate()
    }
}
