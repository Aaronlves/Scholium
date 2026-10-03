import AppKit
import Combine
import QuartzCore

/// Native presentation only. The reader admits commands and owns the selected
/// tool; the native host owns placement and PDFView owns scrolling clearance.
@MainActor
final class PDFReaderFloatingToolsView: NSGlassEffectView {
    static let visibilityAnimationKey = "scholium.pdf.toolsVisibility"
    private weak var controller: PDFReaderController?
    private let canPresent: @MainActor () -> Bool
    private let stack = NSStackView()
    private let choices: [(tool: PDFReaderController.Tool, button: NSButton)]
    private let zoom: PDFReaderNativeMenuButton
    private let symbols = NSImage.SymbolConfiguration(textStyle: .title3, scale: .medium)
    private var isInvalidated = false
    private let idleDelay: Duration
    private var idleTask: Task<Void, Never>?
    private var idleGeneration: UInt64 = 0
    private var projectedDocument: ObjectIdentifier?
    private var presentationActivity: PDFReaderPresentationActivity
    private var activityObservation: AnyCancellable?
    private var trackingArea: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []
    private var voiceOverObservation: NSKeyValueObservation?
    private var switchControlObservation: NSKeyValueObservation?
    private var reduceMotion = false
    private(set) var isIdleHidden = false

    init(controller: PDFReaderController, idleDelay: Duration = .seconds(2.5), canPresent: @escaping @MainActor () -> Bool) {
        self.controller = controller
        self.canPresent = canPresent
        self.idleDelay = idleDelay
        presentationActivity = controller.presentationActivity
        choices = [(.select, PDFReaderToolbarButton()), (.highlight, PDFReaderToolbarButton()), (.comment, PDFReaderToolbarButton())]
        zoom = PDFReaderNativeMenuButton(controller: controller, kind: .zoom, canPresent: canPresent)
        super.init(frame: .zero)
        wantsLayer = true
        style = .regular
        if #available(macOS 27.0, *) { effectIsInteractive = true }
        setAccessibilityElement(false)
        stack.setAccessibilityElement(true)
        stack.setAccessibilityIdentifier("scholium.pdf.tools")
        stack.setAccessibilityLabel(ScholiumL10n.string("PDF Reader"))
        stack.setAccessibilityRole(.group)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = ScholiumMetrics.PDFReader.toolsGap
        let inset = ScholiumMetrics.PDFReader.toolsContentInset
        stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        for (index, choice) in choices.enumerated() {
            let title: String
            let symbol: String
            switch choice.tool {
            case .select: (title, symbol) = ("Select", "text.cursor")
            case .highlight: (title, symbol) = ("Highlight", "highlighter")
            case .comment: (title, symbol) = ("Comment", "text.bubble")
            }
            let button = choice.button
            button.tag = index
            button.setButtonType(.pushOnPushOff)
            button.isBordered = false
            // Suppress persistent state drawing while retaining native transient
            // highlights. The toggle's accessibility value is projected below.
            (button.cell as? NSButtonCell)?.showsStateBy = []
            button.setAccessibilityRole(.button)
            button.setAccessibilitySubrole(.toggle)
            button.image = ScholiumNativeToolbarPresentation.symbol(named: symbol)
            button.symbolConfiguration = symbols
            button.imagePosition = .imageOnly
            button.controlSize = .regular
            button.toolTip = ScholiumL10n.dynamicString(title)
            button.setAccessibilityLabel(ScholiumL10n.dynamicString(title))
            button.setAccessibilityIdentifier("scholium.pdf.tool.\(choice.tool.rawValue)")
            button.target = self
            button.action = #selector(chooseTool(_:))
            (button as? PDFReaderToolbarButton)?.focusDidChange = { [weak self] focused in
                self?.controlFocusDidChange(focused)
            }
            button.widthAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize).isActive = true
            stack.addArrangedSubview(button)
        }
        zoom.controlSize = .regular
        zoom.symbolConfiguration = symbols
        zoom.widthAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize).isActive = true
        zoom.heightAnchor.constraint(equalToConstant: ScholiumMetrics.PDFReader.toolsControlSize).isActive = true
        stack.addArrangedSubview(zoom)
        zoom.focusDidChange = { [weak self] focused in self?.controlFocusDidChange(focused) }
        contentView = stack
        synchronizeAccessibilityVisibility()
        observePresentationActivity()
        voiceOverObservation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshVisibility() }
        }
        switchControlObservation = NSWorkspace.shared.observe(\.isSwitchControlEnabled, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refreshVisibility() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        update(controller)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only PDF tools") }

    override var intrinsicContentSize: NSSize { stack.fittingSize }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        if cornerRadius != radius { cornerRadius = radius }
        refreshVisibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeWindowObservers()
        cancelIdle()
        stopVisibilityMotion()
        guard !isInvalidated else { return }
        if let window {
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                windowObservers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.noteActivity(animated: false) }
                    })
            }
            windowObservers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didUpdateNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshVisibility() }
                })
        }
        setControlsVisible(true, animated: false)
        refreshVisibility()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = nil
        guard !isInvalidated else { return }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { noteActivity() }
    override func mouseExited(with event: NSEvent) { refreshVisibility() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The quiet strip leaves paper pointer-addressable, but remains in the
        // native key-view loop. Actual pane departure still hides the view.
        guard !isIdleHidden else { return nil }
        return super.hitTest(point)
    }

    func updatePresentation(reduceMotion: Bool) {
        guard !isInvalidated else { return }
        self.reduceMotion = reduceMotion
        if reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { stopVisibilityMotion() }
    }

    func update(_ controller: PDFReaderController) {
        guard !isInvalidated else { return }
        let documentID = controller.document.map(ObjectIdentifier.init)
        let changedDocument = self.controller !== controller || projectedDocument != documentID
        self.controller = controller
        projectedDocument = documentID
        if presentationActivity !== controller.presentationActivity {
            activityObservation?.cancel()
            presentationActivity = controller.presentationActivity
            observePresentationActivity()
        }
        if changedDocument {
            cancelIdle()
            setControlsVisible(true, animated: false)
        }
        for choice in choices {
            let selected = controller.tool == choice.tool
            choice.button.isEnabled = canPresent() && controller.canSelectTool(choice.tool)
            choice.button.state = selected ? .on : .off
            choice.button.contentTintColor = selected ? .controlAccentColor : .labelColor
            choice.button.setAccessibilityValue(NSNumber(value: selected))
        }
        zoom.update(controller: controller)
        refreshVisibility()
    }

    func cancelTracking() { zoom.cancelTracking() }

    /// Pointer and keyboard activity only presents controls. It never consumes
    /// the event, changes tool choice, or moves PDFKit's focus/selection.
    func noteActivity(animated: Bool = true) {
        guard !isInvalidated else { return }
        cancelIdle()
        setControlsVisible(true, animated: animated)
        refreshVisibility()
    }

    private func observePresentationActivity() {
        // NSMenu uses its own event-tracking run loop. A default-run-loop hop
        // would leave the bar hidden until tracking ended. Use the published
        // value directly because @Published sends before storing its new value.
        activityObservation = presentationActivity.$isActive.sink { [weak self] active in
            self?.refreshVisibility(presentationActive: active)
        }
    }

    private var hasControlFocus: Bool {
        let responder =
            (window?.firstResponder as? NSTextView)?.delegate as? NSView
            ?? window?.firstResponder as? NSView
        return responder.map { $0 === self || $0.isDescendant(of: self) } ?? false
    }

    private var hasControlHover: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func isPinned(_ controller: PDFReaderController, presentationActive: Bool?) -> Bool {
        (presentationActive ?? presentationActivity.isActive) || hasControlFocus || hasControlHover
            || NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
            || controller.annotationDraft != nil || controller.annotationDetail != nil
            || controller.attachRequested || controller.showsAnnotations
            || controller.hasUnsavedAnnotations || controller.isSaving || controller.isImporting || controller.isLoading
            || controller.error != nil || controller.annotationDraftError != nil || !controller.recoveryCandidates.isEmpty
    }

    private func refreshVisibility(presentationActive: Bool? = nil, hideWhenUnpinned: Bool = false) {
        guard !isInvalidated, let controller else { return }
        let available = controller.document != nil && controller.isVisible && canPresent() && window != nil && superview != nil
        let wasHidden = isHidden
        if isHidden != !available { isHidden = !available }
        synchronizeAccessibilityVisibility()
        guard available else {
            cancelIdle()
            setControlsVisible(true, animated: false)
            return
        }
        if wasHidden { setControlsVisible(true, animated: false) }
        if isPinned(controller, presentationActive: presentationActive) {
            cancelIdle()
            setControlsVisible(true)
        } else if hideWhenUnpinned, bounds.width > 0, bounds.height > 0 {
            setControlsVisible(false)
        } else if !isIdleHidden {
            scheduleIdle()
        }
    }

    private func scheduleIdle() {
        guard idleTask == nil, bounds.width > 0, bounds.height > 0,
            let controller, let window, let documentID = controller.document.map(ObjectIdentifier.init)
        else { return }
        let generation = idleGeneration
        let delay = idleDelay
        idleTask = Task { @MainActor [weak self, weak controller, weak window] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self, let controller, let window,
                !self.isInvalidated, self.idleGeneration == generation,
                self.controller === controller, self.window === window,
                controller.document.map(ObjectIdentifier.init) == documentID
            else { return }
            self.idleTask = nil
            self.refreshVisibility(hideWhenUnpinned: true)
        }
    }

    private func cancelIdle() {
        idleGeneration &+= 1
        idleTask?.cancel()
        idleTask = nil
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool = true) {
        let hidden = !visible
        guard isIdleHidden != hidden else { return }
        isIdleHidden = hidden
        let current = layer?.presentation()?.opacity ?? Float(alphaValue)
        stopVisibilityMotion()
        alphaValue = visible ? 1 : 0
        synchronizeAccessibilityVisibility()
        let duration = ScholiumMotion.floatingControlsDuration(
            reduceMotion: reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        guard animated, duration > 0, window != nil, !isHiddenOrHasHiddenAncestor, abs(current - Float(alphaValue)) > 0.001 else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = current
        animation.toValue = alphaValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(animation, forKey: Self.visibilityAnimationKey)
    }

    private func stopVisibilityMotion() { layer?.removeAnimation(forKey: Self.visibilityAnimationKey) }

    private func synchronizeAccessibilityVisibility() {
        let hidden = isInvalidated || isIdleHidden || isHiddenOrHasHiddenAncestor || window == nil || superview == nil
        setAccessibilityHidden(hidden)
        stack.setAccessibilityHidden(hidden)
        for choice in choices { choice.button.setAccessibilityHidden(hidden) }
        zoom.setAccessibilityHidden(hidden)
        // The glass is an ignored AX container with explicitly supplied
        // children. Suppress that projection too, so a transparent strip cannot
        // promote its group or controls into the reading tree. Native subviews
        // stay intact for the key-view loop and focus-triggered disclosure.
        setAccessibilityChildren(hidden ? [] : [stack])
    }

    private func controlFocusDidChange(_ focused: Bool) {
        if focused {
            noteActivity()
        } else {
            // AppKit calls resign before installing the next first responder.
            Task { @MainActor [weak self] in self?.refreshVisibility() }
        }
    }

    @objc private func displayOptionsDidChange() {
        guard !isInvalidated else { return }
        if reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { stopVisibilityMotion() }
    }

    private func removeWindowObservers() {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        cancelIdle()
        stopVisibilityMotion()
        activityObservation?.cancel()
        activityObservation = nil
        removeWindowObservers()
        voiceOverObservation?.invalidate()
        voiceOverObservation = nil
        switchControlObservation?.invalidate()
        switchControlObservation = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = nil
        cancelTracking()
        zoom.invalidate()
        controller = nil
        isHidden = true
        synchronizeAccessibilityVisibility()
        for choice in choices {
            (choice.button as? PDFReaderToolbarButton)?.focusDidChange = nil
            choice.button.target = nil
            choice.button.action = nil
            choice.button.isEnabled = false
        }
    }

    @objc private func chooseTool(_ sender: NSButton) {
        guard !isInvalidated, canPresent(), choices.indices.contains(sender.tag),
            choices[sender.tag].button === sender, let controller
        else { return }
        noteActivity()
        controller.selectTool(choices[sender.tag].tool)
        update(controller)
    }
}
