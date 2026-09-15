import AppKit
import Foundation
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Native document floating surfaces", .serialized)
@MainActor
struct DocumentFloatingSurfaceTests {
    private func payload(id: Int = 1, kind: String = "preview") -> [String: Any] {
        [
            "id": id, "kind": kind, "left": 290, "top": 240, "bottom": 260,
            "html": kind == "preview"
                ? "<h2 class='scholium-preview-title'>Synthetic preview</h2><div class='scholium-preview-body scholium-document'><p>Source stays unchanged.</p></div>"
                : "",
            "css": "", "items": [], "selected": -1,
        ]
    }

    @Test("Malformed and unbounded projections cannot create a surface")
    func boundedProjection() throws {
        let valid = payload()
        #expect(DocumentFloatingSurface.decode(valid) != nil)
        for (key, value) in [
            ("id", 0 as Any), ("top", Double.infinity as Any),
            ("html", String(repeating: "x", count: 500_001) as Any),
            ("selected", 2 as Any), ("kind", "editor" as Any),
        ] {
            var malformed = valid
            malformed[key] = value
            #expect(DocumentFloatingSurface.decode(malformed) == nil)
        }
        var extra = valid
        extra["source"] = "not an editing operation"
        #expect(DocumentFloatingSurface.decode(extra) == nil)
    }

    @Test("Selection actions use native layout and a menu without a duplicate composer")
    func selectionActions() throws {
        let bar = SelectionActionBar(actions: SelectionActionPreferences.defaultActions)
        let menu = try #require(bar.arrangedSubviews.compactMap { $0 as? NSPopUpButton }.first?.menu)
        #expect(!bar.arrangedSubviews.contains { $0 is NSTextField })
        #expect(bar.preferredSize.width <= 340)
        var chosen: AgentChatSelectionInquiry?
        bar.onInquiry = { chosen = $0 }
        let custom = try #require(menu.items.last)
        #expect(NSApp.sendAction(try #require(custom.action), to: custom.target, from: custom))
        #expect(chosen?.question == AgentChatSelectionInquiry.checkEvidence.question)
        let ask = menu.items[1]
        #expect(NSApp.sendAction(try #require(ask.action), to: ask.target, from: ask))
        #expect(chosen == .ask)
    }

    @Test("Unavailable selection actions stay anchored to their native bar")
    func selectionFailureAnchor() async throws {
        _ = NSApplication.shared
        let webView = WKWebView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = DocumentWebViewContainer(webView: webView)
        window.contentView = viewport
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        let controller = DocumentFloatingSurfaceController()
        defer { controller.dismiss(); webView.stopLoading(); window.close() }
        controller.present(
            DocumentFloatingSurface(id: 1, kind: .selection, left: 300, top: 180, bottom: 200,
                html: "", css: "", items: [], selected: -1),
            in: webView,
            inquire: { _, _ in throw AgentChatNoteMaterialError.selectionUnavailable }
        ) { _, action, _ in
            #expect(action == "choose")
            return true
        }
        let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        let bar = try #require(glass.contentView as? SelectionActionBar)
        bar.onInquiry?(.polish)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.selectionResultPopover?.isShown != true && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let popover = try #require(controller.selectionResultPopover)
        #expect(popover.isShown)
        #expect(popover.positioningRect == glass.bounds)
        #expect(glass.superview === viewport)
        #expect(glass.contentView === bar)
        popover.close()
        let closeDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while controller.selectionResultPopover != nil && ContinuousClock.now < closeDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.selectionResultPopover == nil)
    }

    @Test("Late cancelled inquiry cleanup preserves the replacement inquiry's cancellation")
    func replacementInquiryCancellation() async throws {
        _ = NSApplication.shared
        let webView = WKWebView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = DocumentWebViewContainer(webView: webView)
        window.contentView = viewport
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        let controller = DocumentFloatingSurfaceController()
        var first: CheckedContinuation<Void, Never>?
        var second: CheckedContinuation<Void, Never>?
        var firstReturned = false
        var secondReturned = false
        var replacementWasCancelled = false
        defer {
            controller.dismiss()
            first?.resume()
            second?.resume()
            webView.stopLoading()
            window.close()
        }
        func waitFor(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while !condition() && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(condition())
        }
        func start(_ id: Int) throws {
            controller.present(
                DocumentFloatingSurface(id: id, kind: .selection, left: 300, top: 180, bottom: 200,
                    html: "", css: "", items: [], selected: -1),
                in: webView,
                inquire: { _, _ in
                    Issue.record("Cancelled validation must not admit the inquiry")
                    return nil
                }
            ) { id, action, _ in
                guard action == "choose" else { return true }
                await withCheckedContinuation { continuation in
                    if id == 1 { first = continuation } else { second = continuation }
                }
                if id == 1 {
                    firstReturned = true
                } else {
                    replacementWasCancelled = Task.isCancelled
                    secondReturned = true
                }
                return true
            }
            let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            let bar = try #require(glass.contentView as? SelectionActionBar)
            bar.onInquiry?(.polish)
        }
        try start(1)
        try await waitFor { first != nil }
        controller.dismiss()
        try start(2)
        try await waitFor { second != nil }
        // A finishes after B owns the controller's pending inquiry slot.
        first?.resume()
        first = nil
        try await waitFor { firstReturned }
        controller.dismiss()
        second?.resume()
        second = nil
        try await waitFor { secondReturned }
        #expect(replacementWasCancelled)
        #expect(controller.selectionResultPopover == nil)
    }

    @Test("Completion fits candidate content, remains stable on selection, and respects the viewport")
    func completionWidth() throws {
        _ = NSApplication.shared
        let webView = WKWebView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = DocumentWebViewContainer(webView: webView)
        window.contentView = viewport
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        let controller = DocumentFloatingSurfaceController()
        defer {
            controller.dismiss()
            webView.stopLoading()
            window.close()
        }
        var id = 0
        func show(_ items: [DocumentFloatingSurface.Item], selected: Int = 0, top: Double = 40) throws -> CGFloat {
            id += 1
            controller.present(
                DocumentFloatingSurface(
                    id: id, kind: .suggestions,
                    left: 20, top: top, bottom: top + 20, html: "", css: "", items: items, selected: selected),
                in: webView
            ) { _, _, _ in true }
            let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            #expect(glass.frame.minX >= 12 && glass.frame.maxX <= webView.bounds.width - 12)
            return glass.frame.width
        }
        let short = try show([.init(label: "Date", detail: "")])
        #expect(short > 44 && short < 100)
        let items: [DocumentFloatingSurface.Item] = [
            .init(label: "Date", detail: ""), .init(label: "研究笔记", detail: "Insert a linked research note"),
        ]
        let detailed = try show(items)
        let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        let content = try #require(glass.contentView as? NativeFloatingChoiceList)
        let frame = glass.frame
        #expect(detailed > short)
        #expect(try show(items, selected: 1) == detailed)
        #expect(glass.contentView === content)
        #expect(glass.frame == frame)
        #expect(abs(frame.height - 80) < 0.5)
        for index in 0..<12 {
            _ = try show(items, selected: index % 2)
            #expect(glass.contentView === content && glass.frame == frame)
        }
        // Filtering never shrinks the retained native list's horizontal footprint.
        #expect(try show([items[0]]) == detailed)
        controller.dismiss()
        _ = try show([items[0]], top: 240)
        let above = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        let anchoredBottom = above.frame.maxY
        _ = try show(Array(repeating: items[1], count: 12), top: 240)
        #expect(above.frame.maxY == anchoredBottom)
        #expect(above.frame.minY >= 12)
        #expect(above.frame.maxY < 240)
        let long = [DocumentFloatingSurface.Item(label: String(repeating: "研究笔记", count: 40), detail: "")]
        let capped = try show(long)
        #expect(capped > detailed && capped < webView.bounds.width)
        window.setContentSize(NSSize(width: 180, height: 400))
        viewport.layoutSubtreeIfNeeded()
        #expect(try show(long) <= 156)
    }

    @Test("Pointer and keyboard share one native choice while acceptance remains explicit")
    func unifiedChoice() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let list = NativeFloatingChoiceList(acceptsKeyboard: true)
        window.contentView = list
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        list.update(items: [.init(label: "First"), .init(label: "第二节"), .init(label: "Third")], selected: 0)
        list.layoutSubtreeIfNeeded()
        window.makeFirstResponder(list.table)
        var accepted: [Int] = []
        list.choose = { accepted.append($0) }
        func pointer(_ type: NSEvent.EventType, row: Int) throws -> NSEvent {
            let rect = list.table.rect(ofRow: row)
            return try #require(
                NSEvent.mouseEvent(
                    with: type,
                    location: list.table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil),
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        }
        list.table.mouseMoved(with: try pointer(.mouseMoved, row: 1))
        #expect(list.table.selectedRow == 1)
        #expect(accepted.isEmpty)
        let down = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
                characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125))
        list.table.keyDown(with: down)
        #expect(list.table.selectedRow == 2)
        #expect(accepted.isEmpty)
        list.table.mouseMoved(with: try pointer(.mouseMoved, row: 0))
        #expect(list.table.selectedRow == 0)
        list.table.mouseDown(with: try pointer(.leftMouseDown, row: 0))
        #expect(accepted == [0])
        #expect(list.table.selectedRowIndexes == IndexSet(integer: 0))
    }

    @Test("Native preview preserves viewport and focus, clamps to narrow bounds, and rejects stale dismissal")
    func previewOwnership() async throws {
        _ = NSApplication.shared
        let webView = WKWebView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = DocumentWebViewContainer(webView: webView)
        window.contentView = viewport
        window.makeKeyAndOrderFront(nil)
        let controller = DocumentFloatingSurfaceController()
        defer {
            controller.dismiss()
            webView.stopLoading()
            window.close()
        }
        window.makeFirstResponder(webView)
        let firstResponder = window.firstResponder
        let wasKey = window.isKeyWindow
        let originalBounds = webView.bounds
        let originalFrame = webView.frame
        let surface = try #require(DocumentFloatingSurface.decode(payload(id: 2)))
        controller.present(surface, in: webView) { _, _, _ in true }
        #expect(!controller.isPreviewShown)
        let preview = try #require(controller.previewWebView)
        // A second report for the same pending target must not strand its measurement.
        controller.present(try #require(DocumentFloatingSurface.decode(payload(id: 3))), in: webView) { _, _, _ in true }
        #expect(controller.previewWebView === preview)
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !controller.isPreviewShown && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.isPreviewShown)
        #expect(preview.window !== window)
        #expect(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        #expect(preview.bounds.width <= originalBounds.width - 24)
        #expect(preview.bounds.height <= originalBounds.height - 24)
        #expect(webView.frame == originalFrame && webView.bounds == originalBounds)
        #expect(window.firstResponder === firstResponder)
        #expect(window.isKeyWindow == wasKey)
        let initialFrame = preview.window?.frame
        let text = try await preview.evaluateJavaScript("document.body.textContent") as? String ?? ""
        #expect(text.contains("Source stays unchanged"))
        controller.present(try #require(DocumentFloatingSurface.decode(payload(id: 4))), in: webView) { _, _, _ in true }
        #expect(controller.previewWebView === preview)
        #expect(preview.window?.frame == initialFrame)
        #expect(preview.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(try await preview.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String == "rgba(0, 0, 0, 0)")
        controller.present(
            try #require(DocumentFloatingSurface.decode(payload(id: 1, kind: "hidden"))),
            in: webView
        ) { _, _, _ in true }
        #expect(controller.previewWebView === preview)
        controller.present(
            try #require(DocumentFloatingSurface.decode(payload(id: 4, kind: "hidden"))),
            in: webView
        ) { _, _, _ in true }
        #expect(controller.previewWebView == nil)
        #expect(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        #expect(webView.frame == originalFrame && webView.bounds == originalBounds)
        // Replacing and cancelling hidden preparation cannot show an obsolete target.
        controller.present(surface, in: webView) { _, _, _ in true }
        let obsolete = controller.previewWebView
        var latest = payload(id: 10)
        latest["html"] =
            "<h2 class='scholium-preview-title'>Latest target</h2><div class='scholium-preview-body scholium-document'>"
            + String(repeating: "<p>Long synthetic paragraph 中文。</p>", count: 60) + "</div>"
        controller.present(try #require(DocumentFloatingSurface.decode(latest)), in: webView) { _, _, _ in true }
        let current = try #require(controller.previewWebView)
        #expect(current === obsolete)
        #expect(current === preview)
        let replacementDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !controller.isPreviewShown && ContinuousClock.now < replacementDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.isPreviewShown)
        #expect(try await current.evaluateJavaScript("document.querySelector('h2').textContent") as? String == "Latest target")
        #expect(try await current.evaluateJavaScript("document.body.scrollHeight > window.innerHeight") as? Bool == true)
        #expect(try await current.evaluateJavaScript("getComputedStyle(document.body).fontFamily.includes('system-ui')") as? Bool == true)
        _ = try await current.evaluateJavaScript("window.scrollTo(0, 160)")
        let readingOffset = try await current.evaluateJavaScript("window.scrollY") as? Double
        #expect((readingOffset ?? 0) > 0)
        latest["id"] = 11
        controller.present(try #require(DocumentFloatingSurface.decode(latest)), in: webView) { _, _, _ in true }
        #expect(try await current.evaluateJavaScript("window.scrollY") as? Double == readingOffset)
        // Closing deactivates the surface; reopening another target reuses only
        // the renderer, never the previous content, focus eligibility, or scroll.
        controller.dismiss()
        #expect(controller.previewWebView == nil)
        #expect(current.superview == nil)
        #expect(!current.acceptsFirstResponder)
        controller.present(try #require(DocumentFloatingSurface.decode(payload(id: 12))), in: webView) { _, _, _ in true }
        #expect(controller.previewWebView === current)
        let reopenDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !controller.isPreviewShown && ContinuousClock.now < reopenDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.isPreviewShown)
        #expect(try await current.evaluateJavaScript("document.querySelector('h2').textContent") as? String == "Synthetic preview")
        #expect(try await current.evaluateJavaScript("window.scrollY") as? Double == 0)
        #expect(window.firstResponder === firstResponder)
        #expect(webView.frame == originalFrame && webView.bounds == originalBounds)
        // Cancel pending replacement, then end the host lifetime. Late callbacks
        // must neither expose the cancelled target nor affect the fresh renderer.
        latest["id"] = 13
        controller.present(try #require(DocumentFloatingSurface.decode(latest)), in: webView) { _, _, _ in true }
        controller.dismiss()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!controller.isPreviewShown && controller.previewWebView == nil)
        controller.reset()
        controller.present(try #require(DocumentFloatingSurface.decode(payload(id: 14))), in: webView) { _, _, _ in true }
        #expect(controller.previewWebView !== current)
        let previousOwnerRenderer = controller.previewWebView
        let otherOwner = WKWebView()
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        otherWindow.contentView = DocumentWebViewContainer(webView: otherOwner)
        otherWindow.orderFront(nil)
        defer { otherWindow.close() }
        // Surface IDs belong to their originating WebView, not a global sequence.
        controller.present(try #require(DocumentFloatingSurface.decode(payload(id: 1))), in: otherOwner) { _, _, _ in true }
        #expect(controller.previewWebView != nil)
        #expect(controller.previewWebView !== previousOwnerRenderer)
    }
}
