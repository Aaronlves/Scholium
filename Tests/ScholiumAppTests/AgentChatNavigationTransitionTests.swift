import AppKit
import Observation
import SwiftUI
import Testing

@testable import ScholiumApp

@MainActor
private final class ChatNavigationEnvironmentSentinel {}

private struct ChatNavigationUnforwardedSentinelKey: EnvironmentKey {
    static let defaultValue: ChatNavigationEnvironmentSentinel? = nil
}

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

    fileprivate final class ActionSpy {
        var calls: [String] = []
    }

    @MainActor
    @Observable
    fileprivate final class ParentEnvironmentState {
        var isUpdated = false
        let presenter = ScholiumFileSelectionPresenter()
        let updatedPresenter = ScholiumFileSelectionPresenter()
        let spy = ActionSpy()
    }

    private struct ParentEnvironmentSource: View {
        @State var state: ParentEnvironmentState
        private let source = Source(title: "Environment-only fixture")

        var body: some View {
            let updated = state.isUpdated
            let spy = state.spy
            AgentChatNavigationTransition(showsList: true, animates: false) {
                source
            }
            .environment(\.locale, Locale(identifier: updated ? "en-GB" : "zh-Hans"))
            .environment(\.layoutDirection, updated ? .leftToRight : .rightToLeft)
            .environment(\.dynamicTypeSize, updated ? .small : .accessibility3)
            .environment(\.colorScheme, updated ? .light : .dark)
            .environment(\.isEnabled, updated)
            .environment(
                \.scholiumVisualEnvironmentOverride,
                ScholiumVisualEnvironmentOverride(
                    increasedContrast: !updated, reduceTransparency: !updated,
                    reduceMotion: !updated, appearsActive: updated)
            )
            .environment(\.scholiumDocumentSurfaceVisibility, updated ? .active : .retained)
            .environment(\.scholiumFileSelectionPresenter, updated ? state.updatedPresenter : state.presenter)
            .environment(\.openChatNoteInNewTab, { _ in spy.calls.append(updated ? "updated-tab" : "tab") })
            .environment(\.openChatNoteInSeparateWindow, { _ in spy.calls.append(updated ? "updated-window" : "window") })
            .environment(\.openChatExternalMarkdown, { _ in spy.calls.append(updated ? "updated-markdown" : "markdown") })
            .environment(
                \.openURL,
                OpenURLAction { _ in
                    spy.calls.append(updated ? "updated-url" : "url")
                    return .handled
                })
        }
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

    @Test("Init and same-page updates release unforwarded parent environment values while the host remains alive", arguments: [false, true])
    func unforwardedParentEnvironmentValueReleases(viaUpdate: Bool) {
        weak var sentinel: ChatNavigationEnvironmentSentinel?
        let host = autoreleasepool {
            let value = ChatNavigationEnvironmentSentinel()
            sentinel = value
            var environment = EnvironmentValues()
            // The key owns the value strongly; only the external witness is weak.
            // Neither the content nor any forwarded operation captures it.
            environment[ChatNavigationUnforwardedSentinelKey.self] = value
            environment.openURL = OpenURLAction { _ in .handled }
            if viaUpdate {
                let host = AgentChatNavigationTransitionHost(content: Text("Initial"), environment: EnvironmentValues(), showsList: true)
                host.update(
                    content: Text("Updated"), environment: environment, showsList: true,
                    animates: false, reduceMotion: true)
                return host
            }
            return AgentChatNavigationTransitionHost(content: Text("Initial"), environment: environment, showsList: true)
        }
        withExtendedLifetime(host) {
            #expect(host.hostingView.superview === host)
            #expect(sentinel == nil)
        }
    }

    @Test("Parent environment-only changes update the real representable without replacing its host or Source state")
    func parentEnvironmentChangesReachRepresentable() async throws {
        let state = ParentEnvironmentState()
        let root = NSHostingView(rootView: ParentEnvironmentSource(state: state))
        let window = attach(root)
        defer {
            window.contentView = nil
            window.close()
        }
        for _ in 0..<100 {
            root.layoutSubtreeIfNeeded()
            if let probe = descendants(root, of: ProbeView.self).first,
                probe.locale == "zh-Hans", probe.lifetimeID != nil
            {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let host = try #require(descendants(root, of: AgentChatNavigationTransitionHost<Source>.self).first)
        let native = try #require(descendants(host, of: ProbeView.self).first)
        let lifetimeID = try #require(native.lifetimeID)
        let hostingView = host.hostingView
        #expect(native.title == "Environment-only fixture")
        #expect(native.locale == "zh-Hans")
        #expect(native.direction == .rightToLeft)
        #expect(native.typeSize == .accessibility3)
        #expect(native.colorScheme == .dark)
        #expect(!native.enabled)
        #expect(native.visual == .init(increasedContrast: true, reduceTransparency: true, reduceMotion: true, appearsActive: false))
        #expect(native.visibility == .retained)
        #expect(native.presenter === state.presenter)
        let reference = URL(string: "scholium-note://parent-environment")!
        native.newTab?(reference)
        native.separateWindow?(reference)
        native.externalMarkdown?(reference)
        native.openURL?.callAsFunction(reference)
        #expect(state.spy.calls == ["tab", "window", "markdown", "url"])

        // Keep child content and showsList fixed. Only the parent @State-owned
        // model changes; SwiftUI must deliver its new environment to updateNSView.
        state.isUpdated = true
        let expectedVisual = ScholiumVisualEnvironmentOverride(
            increasedContrast: false, reduceTransparency: false, reduceMotion: false, appearsActive: true)
        for _ in 0..<100 {
            root.layoutSubtreeIfNeeded()
            if native.locale == "en-GB", native.enabled, native.visual == expectedVisual { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let updatedHost = try #require(descendants(root, of: AgentChatNavigationTransitionHost<Source>.self).first)
        let updatedNative = try #require(descendants(updatedHost, of: ProbeView.self).first)
        #expect(updatedHost === host)
        #expect(updatedHost.hostingView === hostingView)
        #expect(updatedNative === native)
        #expect(updatedNative.lifetimeID == lifetimeID)
        #expect(updatedNative.title == "Environment-only fixture")
        #expect(updatedNative.locale == "en-GB")
        #expect(updatedNative.direction == .leftToRight)
        #expect(updatedNative.typeSize == .small)
        #expect(updatedNative.colorScheme == .light)
        #expect(updatedNative.enabled)
        #expect(updatedNative.visual == expectedVisual)
        #expect(updatedNative.visibility == .active)
        #expect(updatedNative.presenter === state.updatedPresenter)
        updatedNative.newTab?(reference)
        updatedNative.separateWindow?(reference)
        updatedNative.externalMarkdown?(reference)
        updatedNative.openURL?.callAsFunction(reference)
        #expect(state.spy.calls == ["tab", "window", "markdown", "url", "updated-tab", "updated-window", "updated-markdown", "updated-url"])
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
        let lifetimeID = try #require(native.lifetimeID)
        let hostingView = host.hostingView
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

        let updatedPresenter = ScholiumFileSelectionPresenter()
        let updatedSpy = ActionSpy()
        var updatedEnvironment = EnvironmentValues()
        updatedEnvironment.locale = Locale(identifier: "en-GB")
        updatedEnvironment.layoutDirection = .leftToRight
        updatedEnvironment.dynamicTypeSize = .small
        updatedEnvironment.colorScheme = .light
        updatedEnvironment.isEnabled = true
        updatedEnvironment.scholiumVisualEnvironmentOverride = .init()
        let effectiveVisual = ScholiumVisualEnvironmentOverride(
            increasedContrast: updatedEnvironment.scholiumIncreasedContrast,
            reduceTransparency: updatedEnvironment.scholiumReduceTransparency,
            reduceMotion: updatedEnvironment.scholiumReduceMotion,
            appearsActive: updatedEnvironment.scholiumAppearsActive)
        updatedEnvironment.scholiumDocumentSurfaceVisibility = .active
        updatedEnvironment.scholiumFileSelectionPresenter = updatedPresenter
        updatedEnvironment.openChatNoteInNewTab = { _ in updatedSpy.calls.append("updated-tab") }
        updatedEnvironment.openChatNoteInSeparateWindow = { _ in updatedSpy.calls.append("updated-window") }
        updatedEnvironment.openChatExternalMarkdown = { _ in updatedSpy.calls.append("updated-markdown") }
        updatedEnvironment.openURL = OpenURLAction { _ in
            updatedSpy.calls.append("updated-url")
            return .handled
        }
        host.update(
            content: Source(title: "Updated"), environment: updatedEnvironment, showsList: true,
            animates: false, reduceMotion: true)
        host.layoutSubtreeIfNeeded()
        let updatedNative = try #require(descendants(host, of: ProbeView.self).first)
        #expect(host.hostingView === hostingView)
        #expect(updatedNative === native)
        #expect(updatedNative.lifetimeID == lifetimeID)
        #expect(updatedNative.title == "Updated")
        #expect(updatedNative.locale == "en-GB")
        #expect(updatedNative.direction == .leftToRight)
        #expect(updatedNative.typeSize == .small)
        #expect(updatedNative.colorScheme == .light)
        #expect(updatedNative.enabled)
        #expect(updatedNative.visual == effectiveVisual)
        #expect(updatedNative.visibility == .active)
        #expect(updatedNative.presenter === updatedPresenter)
        updatedNative.newTab?(reference)
        updatedNative.separateWindow?(reference)
        updatedNative.externalMarkdown?(reference)
        updatedNative.openURL?.callAsFunction(reference)
        #expect(updatedSpy.calls == ["updated-tab", "updated-window", "updated-markdown", "updated-url"])
        #expect(spy.calls == ["tab", "window", "markdown", "url"])
    }
}
