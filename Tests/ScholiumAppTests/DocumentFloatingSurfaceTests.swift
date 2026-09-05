import AppKit
import Foundation
import Testing
import WebKit
@testable import ScholiumApp

@Suite("Native document floating surfaces", .serialized)
@MainActor
struct DocumentFloatingSurfaceTests {
    private func payload(id: Int = 1, kind: String = "preview") -> [String: Any] {
        ["id": id, "kind": kind, "left": 290, "top": 240, "bottom": 260,
         "html": kind == "preview" ? "<h2 class='scholium-preview-title'>Synthetic preview</h2><div class='scholium-preview-body scholium-document'><p>Source stays unchanged.</p></div>" : "",
         "css": "", "items": [], "selected": -1]
    }

    @Test("Malformed and unbounded projections cannot create a surface")
    func boundedProjection() throws {
        let valid = payload()
        #expect(DocumentFloatingSurface.decode(valid) != nil)
        for (key, value) in [("id", 0 as Any), ("top", Double.infinity as Any),
                             ("html", String(repeating: "x", count: 500_001) as Any),
                             ("selected", 2 as Any), ("kind", "editor" as Any)] {
            var malformed = valid
            malformed[key] = value
            #expect(DocumentFloatingSurface.decode(malformed) == nil)
        }
        var extra = valid
        extra["source"] = "not an editing operation"
        #expect(DocumentFloatingSurface.decode(extra) == nil)
    }

    @Test("Completion fits candidate content, remains stable on selection, and respects the viewport")
    func completionWidth() throws {
        _ = NSApplication.shared
        let webView = WKWebView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = DocumentWebViewContainer(webView: webView)
        window.contentView = viewport
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        let controller = DocumentFloatingSurfaceController()
        defer { controller.dismiss(); webView.stopLoading(); window.close() }
        var id = 0
        func show(_ items: [DocumentFloatingSurface.Item], selected: Int = 0) throws -> CGFloat {
            id += 1
            controller.present(DocumentFloatingSurface(id: id, kind: .suggestions,
                left: 20, top: 40, bottom: 60, html: "", css: "", items: items, selected: selected),
                in: webView) { _, _, _ in }
            let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            #expect(glass.frame.minX >= 12 && glass.frame.maxX <= webView.bounds.width - 12)
            return glass.frame.width
        }
        let short = try show([.init(label: "Date", detail: "")])
        #expect(short > 44 && short < 100)
        let items: [DocumentFloatingSurface.Item] = [
            .init(label: "Date", detail: ""), .init(label: "研究笔记", detail: "Insert a linked research note")]
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 180),
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
            return try #require(NSEvent.mouseEvent(with: type,
                location: list.table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
        }
        list.table.mouseMoved(with: try pointer(.mouseMoved, row: 1))
        #expect(list.table.selectedRow == 1)
        #expect(accepted.isEmpty)
        let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = DocumentWebViewContainer(webView: webView)
        window.contentView = viewport
        window.makeKeyAndOrderFront(nil)
        let controller = DocumentFloatingSurfaceController()
        defer { controller.dismiss(); webView.stopLoading(); window.close() }
        window.makeFirstResponder(webView)
        let firstResponder = window.firstResponder
        let originalBounds = webView.bounds
        let originalFrame = webView.frame
        let surface = try #require(DocumentFloatingSurface.decode(payload(id: 2)))
        controller.present(surface, in: webView) { _, _, _ in }
        let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        #expect(glass.style == .regular)
        #expect(glass.frame.minX >= 12 && glass.frame.maxX <= webView.bounds.width - 12)
        #expect(glass.frame.minY >= 12 && glass.frame.maxY <= webView.bounds.height - 12)
        #expect(webView.frame == originalFrame && webView.bounds == originalBounds)
        #expect(window.firstResponder === firstResponder)
        let preview = try #require(controller.previewWebView)
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        var text = ""
        while !text.contains("Source stays unchanged") && ContinuousClock.now < deadline {
            text = (try? await preview.evaluateJavaScript("document.body?.textContent || ''")) as? String ?? ""
            if !text.contains("Source stays unchanged") { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(text.contains("Source stays unchanged"))
        #expect(preview.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(try await preview.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String == "rgba(0, 0, 0, 0)")
        controller.present(try #require(DocumentFloatingSurface.decode(payload(id: 1, kind: "hidden"))),
                           in: webView) { _, _, _ in }
        #expect(controller.previewWebView === preview)
        controller.present(try #require(DocumentFloatingSurface.decode(payload(id: 2, kind: "hidden"))),
                           in: webView) { _, _, _ in }
        #expect(controller.previewWebView == nil)
        #expect(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        #expect(webView.frame == originalFrame && webView.bounds == originalBounds)
    }
}
