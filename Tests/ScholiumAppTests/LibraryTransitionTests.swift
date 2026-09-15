import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Library workspace transition", .serialized)
@MainActor
struct LibraryTransitionTests {
    private struct Source: NSViewRepresentable {
        let title: String
        @Environment(\.locale) private var locale

        func makeNSView(context: Context) -> NSScrollView {
            let scroll = NSScrollView()
            let text = NSTextView(frame: .init(x: 0, y: 0, width: 280, height: 2000))
            text.isVerticallyResizable = false
            scroll.documentView = text
            return scroll
        }

        func updateNSView(_ scroll: NSScrollView, context: Context) {
            scroll.documentView?.setAccessibilityLabel("\(title):\(locale.identifier)")
        }
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }

    @Test("Committed switches preserve the native source, scroll and keyboard responder")
    func retainedSourceAndInterruptions() throws {
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "zh-Hans")
        let host = LibraryTransitionHost(content: Source(title: "Analyses"), environment: environment, slot: .paperAnalysis)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        let scroll = try #require(descendants(host, of: NSScrollView.self).first)
        let text = try #require(scroll.documentView as? NSTextView)
        scroll.contentView.scroll(to: .init(x: 0, y: 200))
        let scrollOrigin = scroll.contentView.bounds.origin
        #expect(window.makeFirstResponder(text))
        let key = LibraryTransitionHost<Source>.animationKey
        #expect(host.layer?.animation(forKey: key) == nil)

        for slot in [WorkspaceVaultSlot.topicKnowledge, .output, .paperAnalysis, .topicKnowledge] {
            host.update(content: Source(title: slot.displayName), environment: environment, slot: slot, reduceMotion: false)
            host.layoutSubtreeIfNeeded()
            #expect(descendants(host, of: NSScrollView.self).count == 1)
            #expect(descendants(host, of: NSScrollView.self).first === scroll)
            #expect(window.firstResponder === text)
            #expect(scroll.contentView.bounds.origin == scrollOrigin)
            #expect(text.accessibilityLabel() == "\(slot.displayName):zh-Hans")
            #expect(host.layer?.animationKeys() == [key])
        }

        host.stopTransition()
        // A same-workspace refresh must not restart the transition.
        host.update(content: Source(title: "Filtered"), environment: environment, slot: .topicKnowledge, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) == nil)
        host.update(content: Source(title: "Works"), environment: environment, slot: .output, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) != nil)
        host.update(content: Source(title: "Works"), environment: environment, slot: .output, reduceMotion: true)
        #expect(host.layer?.animation(forKey: key) == nil)
        host.update(content: Source(title: "Topics"), environment: environment, slot: .topicKnowledge, reduceMotion: true)
        #expect(host.layer?.animation(forKey: key) == nil)
        #expect(window.firstResponder === text)
    }

    @Test("Unconfigured and detached sources never animate; teardown clears an active switch")
    func lifecycle() throws {
        let environment = EnvironmentValues()
        let host = LibraryTransitionHost(content: Text("Loading Library…"), environment: environment, slot: nil)
        let key = LibraryTransitionHost<Text>.animationKey
        host.update(content: Text("No Notes"), environment: environment, slot: .paperAnalysis, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) == nil)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.update(content: Text("Could Not Open Library"), environment: environment, slot: .topicKnowledge, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) != nil)
        host.removeFromSuperview()
        #expect(host.layer?.animation(forKey: key) == nil)
    }
}
