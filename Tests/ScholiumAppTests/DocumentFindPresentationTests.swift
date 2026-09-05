import Foundation
import AppKit
import SwiftUI
import Testing
@testable import ScholiumApp

@Suite("Document Find presentation")
@MainActor
struct DocumentFindPresentationTests {
    @Test("Narrow layout retains native query identity and presents a readable failure")
    func nativeFieldSurvivesReflow() async throws {
        _ = NSApplication.shared
        let model = DocumentFindPresentationModel()
        model.presentReplacement()
        model.setQuery("Synthetic 论证")
        model.setReplacement("Revised 理由")
        model.fail(NSError(domain: "QA", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Synthetic find failure. The document remains unchanged."
        ]), for: try #require(model.request?.id))
        let host = NSHostingView(rootView: DocumentFindPanel(model: model, allowsReplacement: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        // Match the real split host: the viewport, not intrinsic SwiftUI size,
        // owns the available width.
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 240),
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
        for (name, appearance) in [("light", NSAppearance.Name.aqua),
                                   ("contrast-dark", NSAppearance.Name.accessibilityHighContrastDarkAqua)] {
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 180),
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
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0),
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
