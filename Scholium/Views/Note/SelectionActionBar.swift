import AppKit

/// Native layout and menu presentation only. Selection and execution stay with their owners.
@MainActor
final class SelectionActionBar: NSStackView {
    var onInquiry: ((AgentChatSelectionInquiry) -> Void)?
    var onDismiss: (() -> Void)?
    private let actions: [SelectionActionDefinition]
    var preferredSize: NSSize { fittingSize }

    init(actions: [SelectionActionDefinition]) {
        self.actions = actions.filter(\.isEnabled)
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        let explain = button(.explain, symbol: "questionmark.bubble", action: #selector(explainPassage))
        let polish = button(.polish, symbol: "sparkles", action: #selector(polishPassage))
        let more = NSPopUpButton(frame: .zero, pullsDown: true)
        more.bezelStyle = .inline
        more.isBordered = false
        more.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        more.addItem(withTitle: ScholiumL10n.string("More Actions"))
        more.setAccessibilityLabel(ScholiumL10n.string("More Actions"))
        more.setAccessibilityIdentifier("scholium.selectionActions.more")
        let ask = NSMenuItem(title: ScholiumL10n.string("Ask Agent"), action: #selector(askAgent), keyEquivalent: "")
        ask.target = self
        more.menu?.addItem(ask)
        if !self.actions.isEmpty { more.menu?.addItem(.separator()) }
        for (index, action) in self.actions.enumerated() {
            let item = NSMenuItem(title: action.name, action: #selector(runCustom(_:)), keyEquivalent: "")
            item.target = self; item.tag = index
            more.menu?.addItem(item)
        }
        [explain, polish, more].forEach { control in
            control.contentTintColor = .labelColor
            addArrangedSubview(control)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(ScholiumL10n.string("Selection Actions"))
    }
    required init?(coder: NSCoder) { nil }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    private func button(_ inquiry: AgentChatSelectionInquiry, symbol: String, action: Selector) -> NSButton {
        let button = NSButton(title: inquiry.title, target: self, action: action)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.bezelStyle = .inline
        button.isBordered = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        button.setAccessibilityLabel(inquiry.title)
        return button
    }
    @objc private func explainPassage() { onInquiry?(.explain) }
    @objc private func polishPassage() { onInquiry?(.polish) }
    @objc private func askAgent() { onInquiry?(.ask) }
    @objc private func runCustom(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        onInquiry?(actions[sender.tag].inquiry)
    }
}
