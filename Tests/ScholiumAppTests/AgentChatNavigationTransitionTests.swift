import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Chat native page transition", .serialized)
@MainActor
struct AgentChatNavigationTransitionTests {
    private final class ProbeView: NSView {
        var lifetimeID: UUID?
        var title = ""
        var locale = ""
        var direction = LayoutDirection.leftToRight
        var typeSize = DynamicTypeSize.large
        var colorScheme = ColorScheme.light
        var enabled = true
        var visual = ScholiumVisualEnvironmentOverride()
        var visibility = DocumentSurfaceVisibility.active
        var presenter: ScholiumFileSelectionPresenter?
        var openURL: OpenURLAction?
        var newTab: (@MainActor @Sendable (URL) -> Void)?
        var separateWindow: (@MainActor @Sendable (URL) -> Void)?
        var externalMarkdown: (@MainActor @Sendable (URL) -> Void)?
    }

    private struct Source: NSViewRepresentable {
        let title: String
        @State private var lifetimeID = UUID()
        @Environment(\.locale) private var locale
        @Environment(\.layoutDirection) private var direction
        @Environment(\.dynamicTypeSize) private var typeSize
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var enabled
        @Environment(\.scholiumVisualEnvironmentOverride) private var visual
        @Environment(\.scholiumDocumentSurfaceVisibility) private var visibility
        @Environment(\.scholiumFileSelectionPresenter) private var presenter
        @Environment(\.openURL) private var openURL
        @Environment(\.openChatNoteInNewTab) private var newTab
        @Environment(\.openChatNoteInSeparateWindow) private var separateWindow
        @Environment(\.openChatExternalMarkdown) private var externalMarkdown

        func makeNSView(context: Context) -> ProbeView { ProbeView() }
        func updateNSView(_ view: ProbeView, context: Context) {
            view.lifetimeID = lifetimeID
            view.title = title
            view.locale = locale.identifier
            view.direction = direction
            view.typeSize = typeSize
            view.colorScheme = colorScheme
            view.enabled = enabled
            view.visual = visual
            view.visibility = visibility
            view.presenter = presenter
            view.openURL = openURL
            view.newTab = newTab
            view.separateWindow = separateWindow
            view.externalMarkdown = externalMarkdown
        }
    }

    private final class ActionSpy {
        var calls: [String] = []
    }

    private func descendants<T: NSView>(_ root: NSView, of type: T.Type) -> [T] {
        (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants($0, of: type) }
    }

    private func attach(_ host: NSView) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return window
    }

    @Test("Back and entry replace one native push while same-page updates retain its animation and SwiftUI state")
    func directionsAndRetainedIdentity() throws {
        let environment = EnvironmentValues()
        let host = AgentChatNavigationTransitionHost(content: Source(title: "Detail"), environment: environment, showsList: false)
        let window = attach(host)
        defer {
            window.contentView = nil
            window.close()
        }
        let native = try #require(descendants(host, of: ProbeView.self).first)
        let lifetimeID = try #require(native.lifetimeID)
        let hostingView = host.hostingView
        let key = AgentChatNavigationTransitionHost<Source>.animationKey
        #expect(host.layer?.animation(forKey: key) == nil)

        host.update(content: Source(title: "List"), environment: environment, showsList: true, animates: true, reduceMotion: false, duration: 2.4)
        host.layoutSubtreeIfNeeded()
        let back = try #require(host.layer?.animation(forKey: key) as? CATransition)
        #expect(back.type == .push)
        #expect(back.subtype == .fromLeft)
        #expect(back.duration == 2.4)
        // Installed animations are immutable. The refresh offers the default
        // 0.24 duration, so retaining this 2.4 duration detects an illicit restart.
        let backBeginTime = back.beginTime
        host.update(content: Source(title: "List refreshed"), environment: environment, showsList: true, animates: true, reduceMotion: false)
        host.layoutSubtreeIfNeeded()
        let continuing = try #require(host.layer?.animation(forKey: key) as? CATransition)
        #expect(continuing.beginTime == backBeginTime)
        #expect(continuing.duration == 2.4)
        #expect(native.title == "List refreshed")

        host.update(content: Source(title: "Detail returned"), environment: environment, showsList: false, animates: true, reduceMotion: false)
        host.layoutSubtreeIfNeeded()
        let entry = try #require(host.layer?.animation(forKey: key) as? CATransition)
        #expect(entry.type == .push)
        #expect(entry.subtype == .fromRight)
        #expect(entry.duration == 0.24)
        #expect(entry.timeOffset == 0)
        #expect(host.layer?.animationKeys() == [key])
        #expect(host.hostingView === hostingView)
        #expect(descendants(host, of: ProbeView.self).first === native)
        #expect(native.lifetimeID == lifetimeID)
        #expect(native.title == "Detail returned")
    }

    @Test("Motion suppression, hidden pages and detach remove a transition without delaying the committed page")
    func suppressionAndTeardown() throws {
        let environment = EnvironmentValues()
        let host = AgentChatNavigationTransitionHost(content: Text("List"), environment: environment, showsList: true)
        let key = AgentChatNavigationTransitionHost<Text>.animationKey
        host.update(content: Text("Detail"), environment: environment, showsList: false, animates: true, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) == nil)
        let window = attach(host)
        defer {
            window.contentView = nil
            window.close()
        }
        host.update(content: Text("List"), environment: environment, showsList: true, animates: true, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) != nil)
        host.update(content: Text("List"), environment: environment, showsList: true, animates: true, reduceMotion: true)
        #expect(host.layer?.animation(forKey: key) == nil)
        host.update(content: Text("Detail"), environment: environment, showsList: false, animates: true, reduceMotion: true)
        #expect(host.layer?.animation(forKey: key) == nil)
        host.update(content: Text("List"), environment: environment, showsList: true, animates: false, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) == nil)
        host.update(content: Text("Detail"), environment: environment, showsList: false, animates: true, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) != nil)
        host.isHidden = true
        #expect(host.layer?.animation(forKey: key) == nil)
        host.update(content: Text("List"), environment: environment, showsList: true, animates: true, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) == nil)
        host.isHidden = false
        host.update(content: Text("Detail"), environment: environment, showsList: false, animates: true, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) != nil)
        AgentChatNavigationTransition<Text>.dismantleNSView(host, coordinator: ())
        AgentChatNavigationTransition<Text>.dismantleNSView(host, coordinator: ())
        #expect(host.layer?.animation(forKey: key) == nil)
        host.update(content: Text("List"), environment: environment, showsList: true, animates: true, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) != nil)
        host.removeFromSuperview()
        #expect(host.window == nil)
        #expect(host.layer?.animation(forKey: key) == nil)
        host.stopTransition()
        host.stopTransition()
        host.update(content: Text("Detached list"), environment: environment, showsList: true, animates: true, reduceMotion: false)
        #expect(host.layer?.animation(forKey: key) == nil)
    }

    @Test("The nested host forwards presentation, exact scene presenter and Chat navigation actions")
    func forwardedEnvironmentAndActions() throws {
        let presenter = ScholiumFileSelectionPresenter()
        let spy = ActionSpy()
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: "zh-Hans")
        environment.layoutDirection = .rightToLeft
        environment.dynamicTypeSize = .accessibility3
        environment.colorScheme = .dark
        environment.isEnabled = false
        environment.scholiumVisualEnvironmentOverride = .init(
            increasedContrast: true, reduceTransparency: true, reduceMotion: true, appearsActive: false)
        environment.scholiumDocumentSurfaceVisibility = .retained
        environment.scholiumFileSelectionPresenter = presenter
        environment.openChatNoteInNewTab = { _ in spy.calls.append("tab") }
        environment.openChatNoteInSeparateWindow = { _ in spy.calls.append("window") }
        environment.openChatExternalMarkdown = { _ in spy.calls.append("markdown") }
        environment.openURL = OpenURLAction { _ in
            spy.calls.append("url")
            return .handled
        }
        let host = AgentChatNavigationTransitionHost(content: Source(title: "Synthetic"), environment: environment, showsList: true)
        let window = attach(host)
        defer {
            window.contentView = nil
            window.close()
        }
        let native = try #require(descendants(host, of: ProbeView.self).first)
        #expect(native.locale == "zh-Hans")
        #expect(native.direction == .rightToLeft)
        #expect(native.typeSize == .accessibility3)
        #expect(native.colorScheme == .dark)
        #expect(!native.enabled)
        #expect(native.visual == environment.scholiumVisualEnvironmentOverride)
        #expect(native.visibility == .retained)
        #expect(native.presenter === presenter)
        let reference = URL(string: "scholium-note://synthetic")!
        native.newTab?(reference)
        native.separateWindow?(reference)
        native.externalMarkdown?(reference)
        native.openURL?.callAsFunction(reference)
        #expect(spy.calls == ["tab", "window", "markdown", "url"])
    }
}
