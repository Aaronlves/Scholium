import AppKit
import SwiftUI

/// One temporary reader per originating window. AppKit owns focus, geometry and
/// dismissal; callers own the exact content and any live operation state.
@MainActor
final class ScholiumContentPreview: NSObject, NSWindowDelegate {
    private(set) var panel: Panel?
    private weak var origin: NSWindow?
    private weak var returnResponder: NSResponder?
    private var monitor: Any?
    private var observations: [NSObjectProtocol] = []
    private var host: NSHostingController<AnyView>?
    private weak var sourceView: NSView?
    private var sourceRect: NSRect = .zero
    private var openingFrame: NSRect = .zero
    private var isDismissing = false
    private let animates: Bool

    init(animates: Bool = true) { self.animates = animates }


    final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        var dismissPreview: (() -> Void)?
        override func cancelOperation(_ sender: Any?) { dismissPreview?() }
        override func performClose(_ sender: Any?) { dismissPreview?() }
    }

    func present<Content: View>(title: String, copyText: String, from source: NSView, anchor: NSRect? = nil, @ViewBuilder content: () -> Content) {
        close()
        guard let window = source.window else { return }
        sourceView = source
        sourceRect = anchor ?? source.bounds
        // Opening a different object replaces only this workspace's preview.
        for child in window.childWindows ?? [] where child is Panel { child.close() }
        origin = window
        returnResponder = window.firstResponder
        let panel = Panel(
            contentRect: Self.previewFrame(parent: window.frame, available: window.screen?.visibleFrame ?? window.frame),
            styleMask: [.titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        panel.title = title
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.animationBehavior = .none
        panel.dismissPreview = { [weak self] in self?.dismiss() }
        panel.isFloatingPanel = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        panel.contentMinSize = NSSize(width: 320, height: 240)
        panel.setAccessibilityIdentifier("scholium.contentPreview")
        panel.delegate = self
        self.panel = panel
        update(title: title, copyText: copyText, content: content)
        window.addChildWindow(panel, ordered: .above)
        // Installing a hosting controller can replace the initial content size.
        // Apply native window geometry after attachment, before first display.
        let destination = Self.previewFrame(parent: window.convertToScreen(window.contentLayoutRect), available: window.screen?.visibleFrame ?? window.frame)
        openingFrame = compactFrame(relativeTo: destination)
        let moves = animates && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(moves ? openingFrame : destination, display: false)
        panel.alphaValue = animates ? 0 : 1
        panel.makeKeyAndOrderFront(nil)
        transition(panel, to: destination, opacity: 1, closing: false) {}
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let dismissed = MainActor.assumeIsolated {
                guard let self, let panel = self.panel, let target = event.window,
                      target !== panel, target == self.origin else { return false }
                self.dismiss()
                return true
            }
            // Dismiss without also activating the control underneath.
            return dismissed ? nil : event
        }
        for (name, object) in [(NSApplication.didResignActiveNotification, nil), (NSWindow.willCloseNotification, window as Any?)] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(restoringFocus: false) }
            })
        }
    }

    func update<Content: View>(title: String, copyText: String, @ViewBuilder content: () -> Content) {
        guard let panel else { return }
        panel.title = title
        let root = AnyView(PreviewContents(title: title, copyText: copyText, dismiss: { [weak self] in self?.dismiss() }, content: content())
            .ignoresSafeArea().tint(nil as Color?))
        if let host { host.rootView = root }
        else {
            let host = NSHostingController(rootView: root)
            host.sizingOptions = []
            panel.contentViewController = host
            self.host = host
        }
    }

    func dismiss(restoringFocus: Bool = true) {
        guard let panel, !isDismissing else { return }
        isDismissing = true
        // Keep the child above its parent until the closing transition finishes.
        transition(panel, to: compactFrame(relativeTo: panel.frame), opacity: 0, closing: true) { [weak self, weak panel] in
            guard let self, self.panel === panel else { return }
            self.close(restoringFocus: restoringFocus)
        }
    }

    private func compactFrame(relativeTo frame: NSRect) -> NSRect {
        guard let sourceView, let window = sourceView.window else { return openingFrame == .zero ? frame : openingFrame }
        let visible = sourceRect.intersection(sourceView.visibleRect)
        guard !visible.isEmpty else { return openingFrame == .zero ? frame : openingFrame }
        let anchor = window.convertToScreen(sourceView.convert(visible, to: nil))
        let size = NSSize(width: max(320, frame.width * 0.4), height: max(240, frame.height * 0.4))
        let screen = window.screen?.visibleFrame ?? window.frame
        return NSRect(x: min(max(anchor.midX - size.width / 2, screen.minX), screen.maxX - size.width),
                      y: min(max(anchor.midY - size.height / 2, screen.minY), screen.maxY - size.height),
                      width: size.width, height: size.height)
    }

    private func transition(_ panel: Panel, to frame: NSRect, opacity: CGFloat, closing: Bool, completion: @escaping @MainActor () -> Void) {
        guard animates else { panel.setFrame(frame, display: false); panel.alphaValue = opacity; completion(); return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ScholiumMotion.contentPreviewDuration(closing: closing, reduceMotion: reduceMotion)
            if !reduceMotion { panel.animator().setFrame(frame, display: true) }
            panel.animator().alphaValue = opacity
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }

    func close(restoringFocus: Bool = true) {
        guard let panel else { return }
        let restore = restoringFocus && panel.isKeyWindow && NSApp.isActive
        let parent = origin
        let responder = returnResponder
        tearDown()
        panel.delegate = nil
        parent?.removeChildWindow(panel)
        panel.close()
        if restore, let parent, parent.isVisible {
            parent.makeKeyAndOrderFront(nil)
            if let responder { parent.makeFirstResponder(responder) }
        }
    }

    func windowDidResignKey(_ notification: Notification) { dismiss(restoringFocus: false) }
    func windowWillClose(_ notification: Notification) {
        guard let panel else { return }
        let parent = origin
        let responder = returnResponder
        let restore = panel.isKeyWindow && NSApp.isActive
        tearDown()
        parent?.removeChildWindow(panel)
        if restore, let parent, parent.isVisible {
            parent.makeKeyAndOrderFront(nil)
            if let responder { parent.makeFirstResponder(responder) }
        }
    }

    private func tearDown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        panel?.dismissPreview = nil
        panel = nil
        host = nil
        sourceView = nil
        isDismissing = false
        origin = nil
        returnResponder = nil
    }

    static func previewFrame(parent: NSRect, available: NSRect) -> NSRect {
        let bounds = available.insetBy(dx: ScholiumGrid.Spacing.regionContentInset, dy: ScholiumGrid.Spacing.regionContentInset)
        let width = min(bounds.width, max(640, min(1120, parent.width * 0.88)))
        let height = min(bounds.height, max(420, min(840, parent.height * 0.86)))
        return NSRect(x: min(max(parent.midX - width / 2, bounds.minX), bounds.maxX - width),
                      y: min(max(parent.midY - height / 2, bounds.minY), bounds.maxY - height), width: width, height: height)
    }
}

private struct PreviewContents<Content: View>: View {
    let title: String
    let copyText: String
    let dismiss: () -> Void
    let content: Content
    @State private var copied = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Button(action: dismiss) {
                    ScholiumSidebarIcon(systemImage: ScholiumSidebarAction.close.symbol, placement: .action)
                }
                .help("Close").accessibilityLabel("Close")
                .accessibilityIdentifier("scholium.contentPreview.close")
                Text(verbatim: title).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(copyText, forType: .string)
                } label: { ScholiumSidebarCopyIcon(copied: copied) }
                .help(copied ? "Copied" : "Copy").accessibilityLabel(copied ? "Copied" : "Copy")
                .accessibilityIdentifier("scholium.contentPreview.copy")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
            .frame(height: ScholiumGrid.Dimension.regionHeaderHeight)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding([.horizontal, .bottom], ScholiumGrid.Spacing.regionContentInset)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }
}

/// Captures the initiating view's window, never the application's current key window.
struct ScholiumPreviewAttachment: NSViewRepresentable {
    let attach: (NSView) -> Void
    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowAttachment = { [weak view] _ in if let view { attach(view) } }
        return view
    }
    func updateNSView(_ view: WindowAttachmentView, context: Context) {
        view.onWindowAttachment = { [weak view] _ in if let view { attach(view) } }
        if view.window != nil { attach(view) }
    }
    static func dismantleNSView(_ view: WindowAttachmentView, coordinator: ()) { view.onWindowAttachment = nil }
}
