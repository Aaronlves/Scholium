import AppKit
import Foundation
import SwiftUI
import Testing
import WebKit

@testable import ScholiumApp

@Suite("Document Find presentation")
@MainActor
struct DocumentFindPresentationTests {
    enum SupersededFocusReturn: CaseIterable {
        case responder, reusedFieldEditor, composition, inactiveWindow, reactivation, hiddenDocument
    }

    @Test("Find return authority rejects newer native interactions including a reused field editor", arguments: SupersededFocusReturn.allCases)
    func findReturnAuthorityRejectsNewerNativeFocus(_ cause: SupersededFocusReturn) throws {
        _ = NSApplication.shared
        let window = FindFocusWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let webView = WKWebView(frame: window.contentView?.bounds ?? .zero)
        let findField = FindFocusField(frame: .zero)
        findField.setAccessibilityIdentifier("scholium.documentFind.query")
        let fieldEditor = NSTextView(frame: .zero)
        fieldEditor.isFieldEditor = true
        fieldEditor.delegate = findField
        window.contentView?.addSubview(webView)
        window.contentView?.addSubview(findField)
        window.contentView?.addSubview(fieldEditor)
        #expect(window.makeFirstResponder(fieldEditor))
        let authority = try #require(DocumentFindFocusReturnAuthority(webView: webView))
        #expect(authority.canRestore(to: webView))
        switch cause {
        case .responder:
            let other = NSTextView(frame: .zero)
            window.contentView?.addSubview(other)
            #expect(window.makeFirstResponder(other))
        case .reusedFieldEditor:
            let other = FindFocusField(frame: .zero)
            window.contentView?.addSubview(other)
            fieldEditor.delegate = other
            #expect(window.firstResponder === fieldEditor)
        case .composition:
            fieldEditor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: 0, length: 0))
            #expect(fieldEditor.hasMarkedText())
        case .inactiveWindow:
            window.reportsKeyWindow = false
        case .reactivation:
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            #expect(window.isKeyWindow)
        case .hiddenDocument:
            webView.isHidden = true
        }
        #expect(!authority.canRestore(to: webView))
        #expect(!window.isVisible)
    }

    @Test("A Find-clear task that begins after a newer control takes focus has no return authority")
    func lateFindClearCannotCaptureUnrelatedInitiator() throws {
        _ = NSApplication.shared
        let window = FindFocusWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let webView = WKWebView(frame: window.contentView?.bounds ?? .zero)
        let other = NSTextView(frame: .zero)
        window.contentView?.addSubview(webView)
        window.contentView?.addSubview(other)
        #expect(window.makeFirstResponder(other))
        #expect(DocumentFindFocusReturnAuthority(webView: webView) == nil)
        #expect(window.firstResponder === other)
        #expect(!window.isVisible)
    }

    @MainActor
    private final class FindFocusField: NSTextField, NSTextViewDelegate {}

    @MainActor
    private final class FindFocusWindow: NSWindow {
        var reportsKeyWindow = true
        override var isKeyWindow: Bool { reportsKeyWindow }
    }

    @Test("Summary refresh retains replacement feedback and never requests selection navigation")
    func refreshRetainsReceipt() throws {
        let model = DocumentFindPresentationModel()
        model.presentReplacement()
        model.setQuery("f")
        model.accept(
            .init(
                current: 0, total: 1, replaceable: 0, canReplaceCurrent: false,
                replacement: .init(replaced: 1, skipped: 1)), for: try #require(model.request?.id))
        model.refresh()
        #expect(model.request?.operation == .execute(.present))
        model.accept(
            .init(current: 0, total: 1, replaceable: 1, canReplaceCurrent: true),
            for: try #require(model.request?.id))
        #expect(model.result.canReplaceCurrent)
        #expect(model.result.replacement == .init(replaced: 1, skipped: 1))
        model.setQuery("new")
        model.accept(.init(current: 0, total: 0), for: try #require(model.request?.id))
        #expect(model.result.replacement == nil)
    }

    @Test("An observation refresh cannot cancel or discard a pending replacement")
    func refreshWaitsForReplacement() throws {
        let model = DocumentFindPresentationModel()
        model.presentReplacement()
        model.setQuery("f")
        model.accept(
            .init(current: 1, total: 2, replaceable: 1, canReplaceCurrent: true),
            for: try #require(model.request?.id))
        model.replaceAll()
        let replacementRequest = try #require(model.request)
        model.refresh()
        model.refresh()
        #expect(model.request == replacementRequest)
        model.accept(.init(current: 0, total: 1, replacement: .init(replaced: 1, skipped: 1)), for: replacementRequest.id)
        #expect(model.request?.operation == .execute(.present))
        #expect(model.request?.id != replacementRequest.id)
        model.accept(.init(current: 0, total: 1), for: try #require(model.request?.id))
        #expect(model.result.replacement == .init(replaced: 1, skipped: 1))
    }

    @Test(
        "An invalidated Find consumes only a queued summary refresh; real failures and obsolete workers stay distinct",
        arguments: ["stale", "cancel", "real", "noRefresh", "obsolete"])
    func invalidatedFindRefresh(boundary: String) throws {
        let model = DocumentFindPresentationModel()
        model.presentReplacement()
        model.setQuery("f")
        model.accept(.init(current: 1, total: 2, replaceable: 2, canReplaceCurrent: true), for: try #require(model.request?.id))
        model.replaceAll()
        let old = try #require(model.request)
        if boundary != "noRefresh" { model.refresh() }
        if boundary == "obsolete" { model.setQuery("new") }
        let current = try #require(model.request)
        let failure: any Error
        if boundary == "cancel" {
            failure = CancellationError()
        } else if boundary == "real" {
            failure = NSError(domain: "SyntheticFind", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic bridge failure"])
        } else {
            failure = MarkdownEditorSession.SessionError.staleRequest
        }
        model.fail(failure, for: old.id)
        if boundary == "stale" || boundary == "cancel" {
            #expect(model.errorMessage == nil)
            let refreshed = try #require(model.request)
            #expect(refreshed.id != old.id)
            #expect(refreshed.operation == .execute(.present))
            #expect(model.hasPendingRequest)
        } else if boundary == "obsolete" {
            #expect(model.request == current)
            #expect(model.hasPendingRequest)
            #expect(model.errorMessage == nil)
        } else {
            #expect(model.request == old)
            #expect(!model.hasPendingRequest)
            #expect(model.errorMessage == failure.localizedDescription)
        }
        #expect(model.query == (boundary == "obsolete" ? "new" : "f"))
        #expect(model.replacement.isEmpty)
    }

    @Test("Narrow layout retains native query identity and presents a readable failure")
    func nativeFieldSurvivesReflow() async throws {
        _ = NSApplication.shared
        let model = DocumentFindPresentationModel()
        model.presentReplacement()
        model.setQuery("Synthetic 论证")
        model.setReplacement("Revised 理由")
        model.fail(
            NSError(
                domain: "QA", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Synthetic find failure. The document remains unchanged."
                ]), for: try #require(model.request?.id))
        let host = NSHostingView(
            rootView: DocumentFindPanel(model: model, allowsReplacement: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        // Match the real split host: the viewport, not intrinsic SwiftUI size,
        // owns the available width.
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 240),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        func searchField(in view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            return view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while searchField(in: host) == nil && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let field = try #require(searchField(in: host))
        #expect(field.stringValue == "Synthetic 论证")
        window.setContentSize(NSSize(width: 320, height: 240))
        let narrowDeadline = clock.now.advanced(by: .seconds(3))
        while field.frame.width > 280 && clock.now < narrowDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(searchField(in: host) === field)
        #expect(field.frame.width >= 120 && field.frame.width <= 280)
        #expect(field.stringValue == "Synthetic 论证")
        #expect(model.replacement == "Revised 理由")

        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/document-find-redesign")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [
            ("light", NSAppearance.Name.aqua),
            ("contrast-dark", NSAppearance.Name.accessibilityHighContrastDarkAqua),
        ] {
            window.appearance = NSAppearance(named: appearance)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent("find-narrow-\(name).png"))
        }
    }

    @Test("Native find fields retain marked text across result updates and yield IME commands", arguments: [false, true])
    func markedTextSurvivesUpdates(replacement: Bool) async throws {
        _ = NSApplication.shared
        let model = DocumentFindPresentationModel()
        model.presentReplacement()
        model.setQuery("original")
        model.setReplacement("original")
        let host = NSHostingView(rootView: DocumentFindPanel(model: model, allowsReplacement: true))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let identifier = replacement ? "scholium.documentFind.replacement" : "scholium.documentFind.query"
        func findField(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.accessibilityIdentifier() == identifier { return field }
            return view.subviews.lazy.compactMap { findField($0) }.first
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while findField(host) == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let field = try #require(findField(host))
        window.makeFirstResponder(field)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.setMarkedText(
            "zhong", selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        let coordinator = try #require(field.delegate as? DocumentFindSearchField.Coordinator)
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(model.query == "original" && model.replacement == "original")
        for command in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:))] {
            #expect(!coordinator.control(field, textView: editor, doCommandBy: command))
        }
        model.accept(.init(current: 1, total: 2), for: try #require(model.request?.id))
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        #expect(editor.hasMarkedText())
        #expect(editor.string == "zhong")
        #expect(model.isPresented)
        editor.insertText("中", replacementRange: editor.markedRange())
        coordinator.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(!editor.hasMarkedText())
        #expect(replacement ? model.replacement == "中" : model.query == "中")
    }

    @Test("Find and replacement entry retain drafts but choose distinct presentations")
    func entryAndDisclosure() throws {
        let model = DocumentFindPresentationModel()
        model.setQuery("论证")
        model.setReplacement("理由")
        model.setWholeWord(true)
        model.presentReplacement()
        #expect(model.replacementIsPresented)
        let request = try #require(model.request)
        model.setReplacementPresented(false)
        #expect(model.request == request)
        #expect(model.replacement == "理由")
        model.presentReplacement()
        let focus = model.focusRequestID
        model.present()
        #expect(!model.replacementIsPresented)
        #expect(model.focusRequestID > focus)
        #expect(model.query == "论证")
        #expect(model.wholeWord)
        model.dismiss()
        #expect(model.request?.operation == .clear)
        #expect(!model.isPresented)
        #expect(!model.isSearching)
        #expect(model.replacement == "理由")
    }

    @Test("Only the current query may publish a count or failure")
    func staleResultsDoNotReplaceCurrentQuery() throws {
        let model = DocumentFindPresentationModel()
        model.present()
        #expect(!model.isSearching)
        model.setQuery("first")
        let first = try #require(model.request?.id)
        model.setQuery("second")
        let second = try #require(model.request?.id)
        model.accept(.init(current: 1, total: 9), for: first)
        #expect(model.isSearching)
        #expect(model.result.total == 0)
        model.accept(.init(current: 1, total: 2), for: second)
        #expect(!model.isSearching)
        #expect(model.result.total == 2)
        model.fail(NSError(domain: "QA", code: 1), for: first)
        #expect(model.errorMessage == nil)
        model.setQuery("")
        #expect(!model.isSearching)
    }

    @Test("Navigation keeps field focus while explicit Find requests refocus it")
    func navigationDoesNotRefocus() throws {
        let model = DocumentFindPresentationModel()
        model.present()
        model.setQuery("term")
        let focus = model.focusRequestID
        model.next()
        #expect(model.request?.operation == .execute(.next))
        model.previous()
        #expect(model.request?.operation == .execute(.previous))
        #expect(model.focusRequestID == focus)
        model.present()
        #expect(model.focusRequestID > focus)
        #expect(model.request?.operation == .execute(.present))
    }
}
