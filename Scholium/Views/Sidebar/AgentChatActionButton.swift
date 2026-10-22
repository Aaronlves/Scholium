import AppKit
import SwiftUI

private struct AgentChatActionFocusKey: EnvironmentKey {
    static var defaultValue: Binding<UUID?>? { nil }
}

extension EnvironmentValues {
    var agentChatActionFocus: Binding<UUID?>? {
        get { self[AgentChatActionFocusKey.self] }
        set { self[AgentChatActionFocusKey.self] = newValue }
    }
}

struct AgentChatCopyButton: View {
    var label = "Copy"
    var contentIdentity = ""
    var accessibilityID: String? = nil
    let copy: () -> Bool

    var body: some View {
        ScholiumCopyFeedback(contentIdentity: .init(contentIdentity), copy: copy) { copied, performCopy in
            AgentChatActionButton(label: copied ? "Copied" : label,
                systemImage: copied ? "checkmark" : ScholiumSidebarAction.copy.symbol,
                accessibilityID: accessibilityID, action: performCopy)
        }
    }
}

/// Message actions use native controls so the persistent SwiftUI page graph
/// does not cache an input/responder subtree for every footer button.
struct AgentChatActionButton: NSViewRepresentable {
    let label: String
    let systemImage: String
    var accessibilityID: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.locale) private var locale
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    @Environment(\.agentChatActionFocus) private var focus
    @Environment(\.agentChatActionsDrawContent) private var drawsContent

    func makeNSView(context: Context) -> AgentChatActionButtonView {
        AgentChatActionButtonView()
    }

    func updateNSView(_ button: AgentChatActionButtonView, context: Context) {
        button.handler = action
        button.focusChanged = { [focus] id, focused in
            if focused { focus?.wrappedValue = id }
            else if focus?.wrappedValue == id { focus?.wrappedValue = nil }
        }
        button.isEnabled = isEnabled
        button.isTransparent = !drawsContent
        button.contentTintColor = ScholiumColorRole.secondaryText.nsColor(increasedContrast: increasedContrast)
        let title = ScholiumL10n.string(String.LocalizationValue(stringLiteral: label), locale: locale)
        button.title = title
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        // AppKit changes imagePosition when assigning a nonempty title.
        // Keep the semantic title without drawing it into the icon target.
        button.imagePosition = .imageOnly
        button.symbolConfiguration = .init(
            pointSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular, scale: .small)
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(accessibilityID)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AgentChatActionButtonView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    static func dismantleNSView(_ button: AgentChatActionButtonView, coordinator: ()) {
        button.handler = nil
        button.focusChanged = nil
    }
}

@MainActor
final class AgentChatActionButtonView: ScholiumPointingHandButton {
    private let focusID = UUID()
    var handler: (() -> Void)?
    var focusChanged: ((UUID, Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(invoke)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Code-only Chat action") }

    override var intrinsicContentSize: NSSize {
        let target = ScholiumGrid.Dimension.preferredCustomTarget
        return NSSize(width: target, height: target)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusChanged?(focusID, true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusChanged?(focusID, false) }
        return accepted
    }

    @objc private func invoke() { handler?() }
}
