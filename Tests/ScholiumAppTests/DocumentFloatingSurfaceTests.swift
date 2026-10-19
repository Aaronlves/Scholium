import AppKit
import Foundation
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Native document floating surfaces", .serialized)
@MainActor
struct DocumentFloatingSurfaceTests {
    private func payload(id: Int = 1, kind: String = "preview") -> [String: Any] {
        let html =
            "<h2 class='scholium-preview-title'>Synthetic preview</h2><div class='scholium-preview-body scholium-document'><p>Source stays unchanged.</p></div>"
        if kind == "hidden" {
            return ["type": "dismissSurface", "kind": "preview", "id": id]
        }
        if kind == "selection" {
            return [
                "type": "selectionSurface",
                "surface": [
                    "id": id, "left": 290, "top": 240, "bottom": 260, "utf16Count": 12,
                ],
            ]
        }
        if kind == "suggestions" {
            return [
                "type": "suggestionSurface",
                "surface": [
                    "id": id, "left": 290, "top": 240, "bottom": 260,
                    "items": [["label": "Date", "detail": "", "disabled": false]], "selected": 0,
                ],
            ]
        }
        return [
            "type": "previewSurface",
            "surface": [
                "id": id, "left": 290, "top": 240, "bottom": 260,
                "html": html, "css": "",
            ],
        ]
    }

    private func setPreviewHTML(_ value: inout [String: Any], _ html: String) {
        var surface = value["surface"] as! [String: Any]
        surface["html"] = html
        value["surface"] = surface
    }

    private func setPreviewCSS(_ value: inout [String: Any], _ css: String) {
        var surface = value["surface"] as! [String: Any]
        surface["css"] = css
        value["surface"] = surface
    }

    private func setID(_ value: inout [String: Any], _ id: Int) {
        var surface = value["surface"] as! [String: Any]
        surface["id"] = id
        value["surface"] = surface
    }

    @Test("Malformed and unbounded projections cannot create a surface")
    func boundedProjection() throws {
        let valid = payload()
        #expect(DocumentFloatingEvent.decode(valid) != nil)
        for (key, value) in [
            ("id", 0 as Any), ("top", Double.infinity as Any),
            ("html", String(repeating: "x", count: 500_001) as Any),
            ("selected", 2 as Any), ("kind", "editor" as Any),
        ] {
            var malformed = valid
            malformed[key] = value
            #expect(DocumentFloatingEvent.decode(malformed) == nil)
        }
        var extra = valid
        extra["source"] = "not an editing operation"
        #expect(DocumentFloatingEvent.decode(extra) == nil)
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

    @Test("Unavailable candidates and overlong writing selections expose disabled native actions")
    func unavailableActions() throws {
        let bar = SelectionActionBar(actions: SelectionActionPreferences.defaultActions, selectionUTF16Count: 12_001)
        let buttons = bar.arrangedSubviews.compactMap { $0 as? NSButton }.filter { !($0 is NSPopUpButton) }
        #expect(buttons.count == 2)
        #expect(buttons.allSatisfy { !$0.isEnabled && $0.accessibilityHelp()?.isEmpty == false })
        let more = try #require(bar.arrangedSubviews.compactMap { $0 as? NSPopUpButton }.first)
        #expect(more.isEnabled)
        let list = NativeFloatingChoiceList(acceptsKeyboard: false)
        list.update(items: [.init(label: "Unavailable Note", detail: "Add a unique alias.", disabled: true)], selected: 0)
        var accepted = false
        list.choose = { _ in accepted = true }
        let row = try #require(list.tableView(list.table, rowViewForRow: 0))
        #expect(row.isAccessibilityEnabled() == false)
        #expect(!row.accessibilityPerformPress())
        #expect(!accepted)
        var candidate = payload(kind: "suggestions")
        var surface = try #require(candidate["surface"] as? [String: Any])
        surface["items"] = [["label": "Unavailable Note", "detail": "Add a unique alias.", "disabled": true]]
        candidate["surface"] = surface
        guard case .suggestions(let decoded) = DocumentFloatingEvent.decode(candidate) else {
            Issue.record("Disabled candidate payload was not admitted")
            return
        }
        #expect(decoded.items.first?.disabled == true)
    }

    @Test("An explicit action admits a viewport-spanning selection before or after its source reply", arguments: [false, true])
    func explicitViewportSelection(delayed: Bool) async throws {
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
        NSApp.activate()
        let controller = DocumentFloatingSurfaceController()
        var captured = false
        defer {
            controller.reset()
            window.close()
        }
        let invoked = try await controller.presentSelectionInquiry(.ask, in: webView) {
            let present = {
                controller.present(
                    .selection(.init(id: 44, left: 300, top: 0, bottom: 600, utf16Count: 500)),
                    in: webView,
                    inquire: { _, validate in
                        captured = await validate()
                        return nil
                    }
                ) { _, _, _ in true }
                #expect(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.allSatisfy { $0.isHidden })
            }
            if delayed {
                Task { @MainActor in
                    await Task.yield()
                    present()
                }
            } else {
                present()
            }
            return 44
        }
        #expect(invoked)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !captured && ContinuousClock.now < deadline { await Task.yield() }
        #expect(captured)
    }

    @Test("An explicit command survives its source owner hiding an existing automatic toolbar")
    func explicitSelectionReplacesAutomaticToolbar() async throws {
        let fixture = SelectionFixture()
        defer { fixture.close() }
        fixture.showSelection(id: 1)
        var captured = false
        let invoked = try await fixture.controller.presentSelectionInquiry(.ask, in: fixture.webView) {
            fixture.controller.present(.dismiss(.init(kind: .selection, id: 1)), in: fixture.webView) { _, _, _ in true }
            #expect(fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
            fixture.showSelection(id: 2) { _, validate in
                captured = await validate()
                return nil
            }
            return 2
        }
        #expect(invoked)
        try await waitForSelectionCondition { captured }
    }

    @Test("Unclaimed automatic selections recover only where the native toolbar fits", arguments: [false, true])
    func automaticSelectionAfterFailedCommand(hasRoom: Bool) async throws {
        let fixture = SelectionFixture()
        defer { fixture.close() }
        let invoked = try await fixture.controller.presentSelectionInquiry(.ask, in: fixture.webView) {
            fixture.controller.present(
                .selection(.init(id: 7, left: 300, top: hasRoom ? 180 : 0, bottom: hasRoom ? 200 : 600, utf16Count: 12)),
                in: fixture.webView, inquire: { _, _ in nil }
            ) { _, _, _ in true }
            let glass = try #require(fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            #expect(glass.isHidden)
            return nil
        }
        #expect(!invoked)
        let glass = fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first
        #expect((glass != nil) == hasRoom)
        #expect(glass?.isHidden != true)
    }

    @Test("A reply arriving after reset cannot dismiss a new toolbar or release its native command")
    func resetDuringSelectionSourceReply() async throws {
        let fixture = SelectionFixture()
        var firstReply: CheckedContinuation<Int?, Never>?
        var secondReply: CheckedContinuation<Int?, Never>?
        let first = Task {
            try await fixture.controller.presentSelectionInquiry(.ask, in: fixture.webView) {
                await withCheckedContinuation { firstReply = $0 }
            }
        }
        var second: Task<Bool, any Error>?
        defer {
            first.cancel()
            second?.cancel()
            firstReply?.resume(returning: nil)
            secondReply?.resume(returning: nil)
            fixture.close()
        }
        try await waitForSelectionCondition { firstReply != nil }
        fixture.controller.reset()
        var captured = false
        second = Task {
            try await fixture.controller.presentSelectionInquiry(.ask, in: fixture.webView) {
                fixture.showSelection(id: 7) { _, validate in
                    captured = await validate()
                    return nil
                }
                return await withCheckedContinuation { secondReply = $0 }
            }
        }
        try await waitForSelectionCondition { secondReply != nil }
        let replacement = try #require(fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        firstReply?.resume(returning: 7)
        firstReply = nil
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(replacement.superview === fixture.viewport)
        #expect(fixture.controller.canInvokeSelectionInquiry(.ask))
        let overlapping = try await fixture.controller.presentSelectionInquiry(.ask, in: fixture.webView) {
            Issue.record("The new command must still own admission after the old defer runs")
            return nil
        }
        #expect(!overlapping)
        secondReply?.resume(returning: 7)
        secondReply = nil
        #expect(try await #require(second).value)
        try await waitForSelectionCondition { captured }
    }

    @Test("A late receipt cancellation cannot cancel a new command reusing the same wire ID")
    func staleSelectionReceiptCancellation() async throws {
        let fixture = SelectionFixture()
        let first = Task {
            try await fixture.controller.presentSelectionInquiry(.ask, in: fixture.webView) { 7 }
        }
        var second: Task<Bool, any Error>?
        defer {
            first.cancel()
            second?.cancel()
            fixture.close()
        }
        try await waitForSelectionCondition { fixture.controller.testingSelectionReceiptCommandID != nil }
        let firstID = try #require(fixture.controller.testingSelectionReceiptCommandID)
        let staleCancellation = try #require(fixture.controller.testingSelectionReceiptCancellationHandler)
        fixture.controller.reset()
        var captured = false
        second = Task {
            try await fixture.controller.presentSelectionInquiry(.ask, in: fixture.webView) { 7 }
        }
        try await waitForSelectionCondition {
            fixture.controller.testingSelectionReceiptCommandID != nil
                && fixture.controller.testingSelectionReceiptCommandID != firstID
        }
        let secondID = try #require(fixture.controller.testingSelectionReceiptCommandID)
        await #expect(throws: CancellationError.self) { try await first.value }
        // Deliver and finish the exact production onCancel task while the new
        // receipt owns the same wire integer. No timing assumption is needed.
        await staleCancellation().value
        #expect(fixture.controller.testingSelectionReceiptCommandID == secondID)
        fixture.showSelection(id: 7) { _, validate in
            captured = await validate()
            return nil
        }
        #expect(try await #require(second).value)
        try await waitForSelectionCondition { captured }
    }

    @Test("Selection Escape does not steal another field's cancellation, and menu tracking keeps its own Escape")
    func selectionEscapeFocusOwnership() throws {
        let fixture = SelectionFixture()
        defer { fixture.close() }
        fixture.showSelection(id: 1)
        try #require(fixture.window.isKeyWindow, "The synthetic key event needs a key native window.")
        let field = NSTextField(string: "Other native input")
        fixture.viewport.addSubview(field)
        try #require(fixture.window.makeFirstResponder(field))
        let fieldResponder = fixture.window.firstResponder
        let escape = try fixture.escape()
        #expect(fixture.controller.handleSelectionKeyDown(escape) === escape)
        #expect(fixture.window.firstResponder === fieldResponder)
        #expect(!fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: fixture.window)
        #expect(fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        #expect(fixture.window.firstResponder === fieldResponder)
        try #require(fixture.window.makeFirstResponder(fixture.webView))
        fixture.showSelection(id: 2)
        fixture.window.simulatesKeyWindow = false
        #expect(fixture.controller.handleSelectionKeyDown(escape) === escape)
        fixture.window.simulatesKeyWindow = true
        let menu = NSMenu()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        #expect(fixture.controller.handleSelectionKeyDown(escape) === escape)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        #expect(fixture.controller.handleSelectionKeyDown(try fixture.escape(modifiers: .shift)) != nil)
        #expect(fixture.controller.handleSelectionKeyDown(escape) == nil)
        #expect(fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        #expect(fixture.window.firstResponder === fixture.webView)
    }

    @Test("A native input client outside NSTextView keeps Escape while marked text is active")
    func selectionEscapeDuringNativeComposition() throws {
        let fixture = SelectionFixture()
        defer { fixture.close() }
        fixture.showSelection(id: 1)
        try #require(fixture.window.isKeyWindow, "The synthetic key event needs a key native window.")
        let input = MarkedInputView()
        fixture.webView.addSubview(input)
        try #require(fixture.window.makeFirstResponder(input))
        let escape = try fixture.escape()
        #expect(fixture.controller.handleSelectionKeyDown(escape) === escape)
        #expect(fixture.window.firstResponder === input)
        #expect(!fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        input.marked = false
        fixture.webView.scholiumIsComposing = true
        #expect(fixture.controller.handleSelectionKeyDown(escape) === escape)
        fixture.webView.scholiumIsComposing = false
        #expect(fixture.controller.handleSelectionKeyDown(escape) == nil)
        #expect(fixture.viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
    }

    private func waitForSelectionCondition(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() && ContinuousClock.now < deadline { await Task.yield() }
        try #require(condition())
    }

    @MainActor
    private final class SelectionFixture {
        let webView: ComposingWebView
        let window: SelectionWindow
        let viewport: DocumentWebViewContainer
        let controller = DocumentFloatingSurfaceController()

        init() {
            _ = NSApplication.shared
            webView = ComposingWebView()
            window = SelectionWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            viewport = DocumentWebViewContainer(webView: webView)
            window.contentView = viewport
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(webView)
        }

        func showSelection(id: Int, inquire: @escaping AgentSelectionInquiryHandler = { _, _ in nil }) {
            controller.present(
                .selection(.init(id: id, left: 300, top: 180, bottom: 200, utf16Count: 12)),
                in: webView, inquire: inquire
            ) { _, _, _ in true }
        }

        func escape(modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: modifiers,
                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                    characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        }

        func close() {
            controller.reset()
            webView.stopLoading()
            window.close()
        }
    }

    private final class SelectionWindow: NSWindow {
        // SwiftPM has no foreground app activation. These tests exercise the
        // native admission state; actual hardware focus belongs to QA journeys.
        var simulatesKeyWindow = true
        override var isKeyWindow: Bool { simulatesKeyWindow }
        override var canBecomeKey: Bool { true }
    }

    private final class ComposingWebView: WKWebView, ScholiumDocumentInputStateProviding {
        var scholiumIsComposing = false
    }

    private final class MarkedInputView: NSView, @MainActor NSTextInputClient {
        var marked = true
        override var acceptsFirstResponder: Bool { true }
        func insertText(_ string: Any, replacementRange: NSRange) {}
        override func doCommand(by selector: Selector) {}
        func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) { marked = true }
        func unmarkText() { marked = false }
        func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
        func markedRange() -> NSRange { NSRange(location: marked ? 0 : NSNotFound, length: marked ? 1 : 0) }
        func hasMarkedText() -> Bool { marked }
        func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
        func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
        func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
        func characterIndex(for point: NSPoint) -> Int { 0 }
    }

    @Test("Unavailable selection actions replace the toolbar beside the captured passage")
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
        defer {
            controller.dismiss()
            webView.stopLoading()
            window.close()
        }
        controller.present(
            .selection(.init(id: 1, left: 300, top: 180, bottom: 200, utf16Count: 12)),
            in: webView,
            inquire: { _, _ in throw AgentChatNoteMaterialError.selectionUnavailable }
        ) { _, action, _ in
            #expect(action == .choose || action == .dismiss)
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
        #expect(
            popover.positioningRect
                == NSRect(
                    x: 300, y: webView.isFlipped ? 180 : webView.bounds.height - 200,
                    width: 1, height: 20))
        #expect(glass.superview == nil)
        #expect(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        popover.close()
        let closeDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while controller.selectionResultPopover != nil && ContinuousClock.now < closeDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.selectionResultPopover == nil)
    }

    @Test("Closing a result removes presentation while captured generation finishes without reopening")
    func selectionResultDismissal() async throws {
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
        var finish: CheckedContinuation<String, Never>?
        let result = AgentSelectionResult(
            title: "Polish", original: "Synthetic source", adopt: { _ in },
            openReference: { _ in false },
            generate: { await withCheckedContinuation { finish = $0 } },
            continueInChat: { _ in })
        defer {
            controller.dismiss()
            finish?.resume(returning: "Synthetic proposal")
            webView.stopLoading()
            window.close()
        }
        controller.present(
            .selection(.init(id: 1, left: 300, top: 180, bottom: 200, utf16Count: 12)),
            in: webView,
            inquire: { _, validate in
                guard await validate() else { return nil }
                result.regenerate()
                return result
            }
        ) { _, _, _ in true }
        let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        let bar = try #require(glass.contentView as? SelectionActionBar)
        bar.onInquiry?(.polish)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (controller.selectionResultPopover?.isShown != true || finish == nil) && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let popover = try #require(controller.selectionResultPopover)
        #expect(popover.isShown)
        #expect(result.isGenerating)
        #expect(glass.superview == nil)
        popover.close()
        #expect(result.isGenerating)
        let continuation = try #require(finish)
        finish = nil
        continuation.resume(returning: "Synthetic proposal")
        let completionDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while (result.isGenerating || controller.selectionResultPopover != nil) && ContinuousClock.now < completionDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(result.finalReply == "Synthetic proposal")
        #expect(controller.selectionResultPopover == nil)
        #expect(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
    }

    @Test("A completed draft handoff removes the toolbar without a result popover")
    func selectionDraftHandoff() async throws {
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
        var captured = false
        var dismissed = false
        defer {
            controller.dismiss()
            webView.stopLoading()
            window.close()
        }
        controller.present(
            .selection(.init(id: 1, left: 300, top: 180, bottom: 200, utf16Count: 12)),
            in: webView,
            inquire: { _, validate in
                captured = await validate()
                return nil
            }
        ) { _, action, _ in
            if action == .dismiss { dismissed = true }
            return true
        }
        let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        let bar = try #require(glass.contentView as? SelectionActionBar)
        bar.onInquiry?(.checkEvidence)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !dismissed && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(captured && dismissed)
        #expect(controller.selectionResultPopover == nil)
        #expect(glass.superview == nil)
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
                .selection(.init(id: id, left: 300, top: 180, bottom: 200, utf16Count: 12)),
                in: webView,
                inquire: { _, _ in
                    Issue.record("Cancelled validation must not admit the inquiry")
                    return nil
                }
            ) { id, action, _ in
                guard action == .choose else { return true }
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
        func show(_ items: [DocumentSuggestionSurface.Item], selected: Int = 0, top: Double = 40) throws -> CGFloat {
            id += 1
            controller.present(
                .suggestions(
                    .init(
                        id: id, left: 20, top: top, bottom: top + 20, items: items, selected: selected)),
                in: webView
            ) { _, _, _ in true }
            let glass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            #expect(glass.frame.minX >= 12 && glass.frame.maxX <= webView.bounds.width - 12)
            return glass.frame.width
        }
        let short = try show([.init(label: "Date", detail: "")])
        #expect(short > 44 && short < 100)
        let shortGlass = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        let shortList = try #require(shortGlass.contentView as? NativeFloatingChoiceList)
        let shortRow = shortList.table.rect(ofRow: 0)
        #expect(abs(shortRow.minY - (shortList.contentView.bounds.height - shortRow.maxY)) < 0.5)
        let items: [DocumentSuggestionSurface.Item] = [
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
        let lastVisibleRow = content.table.rect(ofRow: 1)
        #expect(abs(content.table.rect(ofRow: 0).minY - (content.contentView.bounds.height - lastVisibleRow.maxY)) < 0.5)
        for index in 0..<12 {
            _ = try show(items, selected: index % 2)
            #expect(glass.contentView === content && glass.frame == frame)
        }
        // Filtering never shrinks the retained native list's horizontal footprint.
        #expect(try show([items[0]]) == detailed)
        let filteredRow = content.table.rect(ofRow: 0)
        #expect(abs(filteredRow.minY - (content.contentView.bounds.height - filteredRow.maxY)) < 0.5)
        #expect(glass.frame.height < frame.height)
        controller.dismiss()
        _ = try show([items[0]], top: 240)
        let above = try #require(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        let anchoredBottom = above.frame.maxY
        let overflowing = Array(repeating: items[1], count: 12)
        _ = try show(overflowing, selected: 11, top: 240)
        let overflowList = try #require(above.contentView as? NativeFloatingChoiceList)
        #expect(overflowList.table.visibleRect.intersects(overflowList.table.rect(ofRow: 11)))
        let overflowHeight = above.frame.height
        #expect(above.frame.maxY == anchoredBottom)
        #expect(above.frame.minY >= 12)
        #expect(above.frame.maxY < 240)
        _ = try show([items[0]], top: 240)
        let filteredOverflowRow = overflowList.table.rect(ofRow: 0)
        #expect(above.frame.height < overflowHeight)
        #expect(above.frame.maxY == anchoredBottom)
        #expect(abs(filteredOverflowRow.minY - (overflowList.contentView.bounds.height - filteredOverflowRow.maxY)) < 0.5)
        let long = [DocumentSuggestionSurface.Item(label: String(repeating: "研究笔记", count: 40), detail: "")]
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
        let surface = try #require(DocumentFloatingEvent.decode(payload(id: 2)))
        controller.present(surface, in: webView) { _, _, _ in true }
        #expect(!controller.isPreviewShown)
        let preview = try #require(controller.previewWebView)
        // A second report for the same pending target must not strand its measurement.
        controller.present(try #require(DocumentFloatingEvent.decode(payload(id: 3))), in: webView) { _, _, _ in true }
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
        controller.present(try #require(DocumentFloatingEvent.decode(payload(id: 4))), in: webView) { _, _, _ in true }
        #expect(controller.previewWebView === preview)
        #expect(preview.window?.frame == initialFrame)
        #expect(preview.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(try await preview.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String == "rgba(0, 0, 0, 0)")
        controller.present(
            try #require(DocumentFloatingEvent.decode(payload(id: 1, kind: "hidden"))),
            in: webView
        ) { _, _, _ in true }
        #expect(controller.previewWebView === preview)
        controller.present(
            try #require(DocumentFloatingEvent.decode(payload(id: 4, kind: "hidden"))),
            in: webView
        ) { _, _, _ in true }
        #expect(controller.previewWebView == nil)
        #expect(viewport.subviews.compactMap { $0 as? NSGlassEffectView }.isEmpty)
        #expect(webView.frame == originalFrame && webView.bounds == originalBounds)
        // Replacing and cancelling hidden preparation cannot show an obsolete target.
        controller.present(surface, in: webView) { _, _, _ in true }
        let obsolete = controller.previewWebView
        var latest = payload(id: 10)
        setPreviewHTML(
            &latest,
            "<h2 class='scholium-preview-title'>Latest target</h2><div class='scholium-preview-body scholium-document'>"
                + "<h2>Authored heading</h2><p><code>sample</code> <strong><span lang='zh-Hans'>中文</span></strong></p>"
                + String(repeating: "<p>Long synthetic paragraph 中文。</p>", count: 60) + "</div>")
        setPreviewCSS(
            &latest,
            try #require(ScholiumDocumentWebResources.text(named: "editor", extension: "css"))
                + ":root { --scholium-color-accent: #ff0000 !important; --scholium-color-separator: #00ff00 !important; "
                + "--scholium-document-accent: #ff0000 !important; --scholium-document-source-font-size: 80px !important; } "
                + ".scholium-document h2 { font-size: 300%; text-align: right; padding-block: 80px; } "
                + ".scholium-document strong :lang(zh-Hans) { font-family: Georgia; }")
        controller.present(try #require(DocumentFloatingEvent.decode(latest)), in: webView) { _, _, _ in true }
        let current = try #require(controller.previewWebView)
        #expect(current === obsolete)
        #expect(current === preview)
        let replacementDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !controller.isPreviewShown && ContinuousClock.now < replacementDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.isPreviewShown)
        #expect(try await current.evaluateJavaScript("document.querySelector('h2').textContent") as? String == "Latest target")
        let previewStyle = try #require(
            try await current.evaluateJavaScript(
                """
                (() => {
                  const root = getComputedStyle(document.documentElement);
                  const heading = getComputedStyle(document.querySelector('.scholium-preview-body h2'));
                  const code = getComputedStyle(document.querySelector('.scholium-preview-body code'));
                  const cjk = getComputedStyle(document.querySelector('.scholium-preview-body :lang(zh-Hans)'));
                  return [root.getPropertyValue('--scholium-color-accent').trim(),
                    root.getPropertyValue('--scholium-color-separator').trim(),
                    root.getPropertyValue('--scholium-document-accent').trim(),
                    heading.textAlign, heading.fontSize, heading.paddingTop,
                    code.fontSize, cjk.fontFamily];
                })()
                """) as? [String])
        try #require(previewStyle.count == 8)
        #expect(!previewStyle[0].contains("#ff0000"))
        #expect(!previewStyle[1].contains("#00ff00"))
        #expect(!previewStyle[2].contains("#ff0000"))
        var nativeAccent: NSColor?
        current.effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeAccent = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        }
        let accent = try #require(nativeAccent)
        let rgb = previewStyle[0]
            .replacingOccurrences(of: "rgba(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        #expect(rgb.count == 4)
        if rgb.count == 4 {
            #expect(abs(rgb[0] - accent.redComponent * 255) < 1)
            #expect(abs(rgb[1] - accent.greenComponent * 255) < 1)
            #expect(abs(rgb[2] - accent.blueComponent * 255) < 1)
        }
        #expect(previewStyle[3] == "start")
        #expect((Double(previewStyle[4].replacingOccurrences(of: "px", with: "")) ?? 100) < 30)
        #expect((Double(previewStyle[5].replacingOccurrences(of: "px", with: "")) ?? 100) < 20)
        #expect((Double(previewStyle[6].replacingOccurrences(of: "px", with: "")) ?? 100) < 30)
        #expect(previewStyle[7].contains("system-ui"))
        #expect(try await current.evaluateJavaScript("document.body.scrollHeight > window.innerHeight") as? Bool == true)
        // Editor CSS disables viewport scrolling. The native preview must own
        // its scroll policy: scrollTo alone also succeeds with overflow:hidden.
        #expect(try await current.evaluateJavaScript("getComputedStyle(document.documentElement).overflowY") as? String == "auto")
        #expect(try await current.evaluateJavaScript("getComputedStyle(document.body).overflowY") as? String == "visible")
        #expect(try await current.evaluateJavaScript("getComputedStyle(document.body).fontFamily.includes('system-ui')") as? Bool == true)
        #expect(try await current.evaluateJavaScript("window.scrollY") as? Double == 0)
        _ = try await current.evaluateJavaScript("window.scrollTo(0, 160)")
        let readingOffset = try await current.evaluateJavaScript("window.scrollY") as? Double
        #expect((readingOffset ?? 0) > 0)
        setID(&latest, 11)
        controller.present(try #require(DocumentFloatingEvent.decode(latest)), in: webView) { _, _, _ in true }
        #expect(try await current.evaluateJavaScript("window.scrollY") as? Double == readingOffset)
        // Closing deactivates the surface; reopening another target reuses only
        // the renderer, never the previous content, focus eligibility, or scroll.
        controller.dismiss()
        #expect(controller.previewWebView == nil)
        #expect(current.superview == nil)
        #expect(!current.acceptsFirstResponder)
        controller.present(try #require(DocumentFloatingEvent.decode(payload(id: 12))), in: webView) { _, _, _ in true }
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
        setID(&latest, 13)
        controller.present(try #require(DocumentFloatingEvent.decode(latest)), in: webView) { _, _, _ in true }
        controller.dismiss()
        try await Task.sleep(for: .milliseconds(150))
        #expect(!controller.isPreviewShown && controller.previewWebView == nil)
        controller.reset()
        controller.present(try #require(DocumentFloatingEvent.decode(payload(id: 14))), in: webView) { _, _, _ in true }
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
        controller.present(try #require(DocumentFloatingEvent.decode(payload(id: 1))), in: otherOwner) { _, _, _ in true }
        #expect(controller.previewWebView != nil)
        #expect(controller.previewWebView !== previousOwnerRenderer)
    }
}
