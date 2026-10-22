import AppKit
import SwiftUI

/// Chat owns the committed page and retained reading state. This native host
/// presents the complete prior page without retaining another input surface.
struct AgentChatNavigationTransition<Content: View>: NSViewRepresentable {
    let showsList: Bool
    let animates: Bool
    var duration: TimeInterval = 0.24
    @ViewBuilder var content: Content
    @Environment(\.scholiumReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> AgentChatNavigationTransitionHost<Content> {
        AgentChatNavigationTransitionHost(content: content, environment: context.environment, showsList: showsList)
    }

    func updateNSView(_ host: AgentChatNavigationTransitionHost<Content>, context: Context) {
        host.update(
            content: content, environment: context.environment, showsList: showsList,
            animates: animates, reduceMotion: reduceMotion, duration: duration)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: AgentChatNavigationTransitionHost<Content>, context: Context
    ) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    static func dismantleNSView(_ host: AgentChatNavigationTransitionHost<Content>, coordinator: ()) {
        host.stopTransition()
    }
}

@MainActor
struct AgentChatNavigationEnvironmentSnapshot {
    let locale: Locale
    let layoutDirection: LayoutDirection
    let dynamicTypeSize: DynamicTypeSize
    let colorScheme: ColorScheme
    let openURL: OpenURLAction
    let visualOverride: ScholiumVisualEnvironmentOverride
    let visibility: DocumentSurfaceVisibility
    let fileSelectionPresenter: ScholiumFileSelectionPresenter?
    let openNewTab: (@MainActor @Sendable (URL) -> Void)?
    let openSeparateWindow: (@MainActor @Sendable (URL) -> Void)?
    let openExternalMarkdown: (@MainActor @Sendable (URL) -> Void)?
    let isEnabled: Bool

    init(_ environment: EnvironmentValues) {
        // This root owns only the values it forwards. Retaining the complete
        // parent environment also extends unrelated values and their owners.
        locale = environment.locale
        layoutDirection = environment.layoutDirection
        dynamicTypeSize = environment.dynamicTypeSize
        colorScheme = environment.colorScheme
        openURL = environment.openURL
        visualOverride = ScholiumVisualEnvironmentOverride(
            increasedContrast: environment.scholiumIncreasedContrast,
            reduceTransparency: environment.scholiumReduceTransparency,
            reduceMotion: environment.scholiumReduceMotion,
            appearsActive: environment.scholiumAppearsActive)
        visibility = environment.scholiumDocumentSurfaceVisibility
        fileSelectionPresenter = environment.scholiumFileSelectionPresenter
        openNewTab = environment.openChatNoteInNewTab
        openSeparateWindow = environment.openChatNoteInSeparateWindow
        openExternalMarkdown = environment.openChatExternalMarkdown
        isEnabled = environment.isEnabled
    }
}

struct AgentChatNavigationTransitionContent<Content: View>: View {
    let content: Content
    let environment: AgentChatNavigationEnvironmentSnapshot

    var body: some View {
        // Forward the Chat's presentation and scene actions explicitly. The
        // nested native host retains its own accessibility and responder owner.
        content
            .environment(\.locale, environment.locale)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.openURL, environment.openURL)
            .environment(\.scholiumVisualEnvironmentOverride, environment.visualOverride)
            .environment(\.scholiumDocumentSurfaceVisibility, environment.visibility)
            .environment(\.scholiumFileSelectionPresenter, environment.fileSelectionPresenter)
            .environment(\.openChatNoteInNewTab, environment.openNewTab)
            .environment(\.openChatNoteInSeparateWindow, environment.openSeparateWindow)
            .environment(\.openChatExternalMarkdown, environment.openExternalMarkdown)
            .disabled(!environment.isEnabled)
    }
}

@MainActor
final class AgentChatNavigationTransitionHost<Content: View>: ScholiumSurfaceContainerView {
    static var animationKey: String { kCATransition }
    let hostingView: NSHostingView<AgentChatNavigationTransitionContent<Content>>
    private var showsList: Bool

    init(content: Content, environment: EnvironmentValues, showsList: Bool) {
        hostingView = NSHostingView(
            rootView: AgentChatNavigationTransitionContent(
                content: content, environment: AgentChatNavigationEnvironmentSnapshot(environment)))
        self.showsList = showsList
        super.init(relinquishesToolbarInput: true)
        wantsLayer = true
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only Chat navigation transition") }

    func update(
        content: Content, environment: EnvironmentValues, showsList: Bool,
        animates: Bool, reduceMotion: Bool, duration: TimeInterval = 0.24
    ) {
        let changedPage = self.showsList != showsList
        self.showsList = showsList
        if !animates || reduceMotion || window == nil || isHiddenOrHasHiddenAncestor {
            stopTransition()
        } else if changedPage {
            // Resolve the old page before committing its new projection. The
            // reserved transition key makes a reversal replace the prior move.
            layoutSubtreeIfNeeded()
            layer?.displayIfNeeded()
            let transition = CATransition()
            transition.type = .push
            transition.subtype = showsList ? .fromLeft : .fromRight
            transition.duration = duration
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(transition, forKey: Self.animationKey)
        }
        hostingView.rootView = AgentChatNavigationTransitionContent(
            content: content, environment: AgentChatNavigationEnvironmentSnapshot(environment))
        if changedPage { hostingView.layoutSubtreeIfNeeded() }
    }

    func stopTransition() { layer?.removeAnimation(forKey: Self.animationKey) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopTransition() }
    }

    override func viewDidHide() {
        super.viewDidHide()
        stopTransition()
    }
}
