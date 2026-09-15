import AppKit
import ScholiumContracts
import SwiftUI

/// One persistent source-region host. Window state owns the committed role;
/// Core Animation presents its change without retaining a second interactive tree.
struct ScholiumLibraryTransition<Content: View>: NSViewRepresentable {
    let slot: WorkspaceVaultSlot?
    @ViewBuilder var content: Content
    @Environment(\.scholiumReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> LibraryTransitionHost<Content> {
        LibraryTransitionHost(content: content, environment: context.environment, slot: slot)
    }

    func updateNSView(_ host: LibraryTransitionHost<Content>, context: Context) {
        host.update(content: content, environment: context.environment, slot: slot, reduceMotion: reduceMotion)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LibraryTransitionHost<Content>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    static func dismantleNSView(_ host: LibraryTransitionHost<Content>, coordinator: ()) {
        host.stopTransition()
    }
}

struct LibraryTransitionContent<Content: View>: View {
    let content: Content
    let environment: EnvironmentValues

    var body: some View {
        // Forward public presentation values; the nested host owns its
        // accessibility and responder environment.
        content
            .environment(\.locale, environment.locale)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.scholiumVisualEnvironmentOverride, ScholiumVisualEnvironmentOverride(
                increasedContrast: environment.scholiumIncreasedContrast,
                reduceTransparency: environment.scholiumReduceTransparency,
                reduceMotion: environment.scholiumReduceMotion,
                appearsActive: environment.scholiumAppearsActive
            ))
            .disabled(!environment.isEnabled)
    }
}

@MainActor
final class LibraryTransitionHost<Content: View>: NSView {
    // Core Animation stores every CATransition under its reserved key.
    static var animationKey: String { kCATransition }
    let hostingView: NSHostingView<LibraryTransitionContent<Content>>
    private var slot: WorkspaceVaultSlot?

    init(content: Content, environment: EnvironmentValues, slot: WorkspaceVaultSlot?) {
        hostingView = NSHostingView(rootView: LibraryTransitionContent(content: content, environment: environment))
        self.slot = slot
        super.init(frame: .zero)
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
    required init?(coder: NSCoder) { fatalError("Code-only Library transition") }

    func update(content: Content, environment: EnvironmentValues, slot: WorkspaceVaultSlot?, reduceMotion: Bool) {
        let changedWorkspace = self.slot != nil && slot != nil && self.slot != slot
        self.slot = slot
        if reduceMotion || window == nil || isHiddenOrHasHiddenAncestor || slot == nil {
            stopTransition()
        } else if changedWorkspace {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = ScholiumMotion.libraryWorkspaceDuration
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            // Replacing this key interrupts an earlier switch; input and the
            // new source projection never wait for an animation completion.
            layer?.add(transition, forKey: Self.animationKey)
        }
        hostingView.rootView = LibraryTransitionContent(content: content, environment: environment)
        if changedWorkspace { hostingView.layoutSubtreeIfNeeded() }
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
