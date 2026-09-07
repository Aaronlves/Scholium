import AppKit
import SwiftUI

struct ContextSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let identifier: String
    struct Option {
        let title: String
        let selected: Bool
        let select: () -> Void
    }
    var options: [Option] = []

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = ScholiumL10n.dynamicString(prompt)
        searchField.sendsSearchStringImmediately = true
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchChanged(_:))
        searchField.setAccessibilityLabel(ScholiumL10n.dynamicString(prompt))
        searchField.setAccessibilityIdentifier(identifier)
        searchField.maximumRecents = 0
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if !options.isEmpty { searchField.searchMenuTemplate = context.coordinator.scopeMenu() }
        return searchField
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true, searchField.stringValue != text {
            searchField.stringValue = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSMenuItemValidation {
        var parent: ContextSearchField

        init(parent: ContextSearchField) {
            self.parent = parent
        }

        func scopeMenu() -> NSMenu {
            let menu = NSMenu()
            for (index, option) in parent.options.enumerated() {
                let item = NSMenuItem(title: ScholiumL10n.dynamicString(option.title),
                    action: #selector(selectScope(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            return menu
        }

        @objc func selectScope(_ item: NSMenuItem) {
            guard parent.options.indices.contains(item.tag) else { return }
            parent.options[item.tag].select()
        }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            guard parent.options.indices.contains(menuItem.tag) else { return false }
            menuItem.state = parent.options[menuItem.tag].selected ? .on : .off
            return true
        }

        @objc func searchChanged(_ sender: NSSearchField) {
            guard (sender.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            parent.text = sender.stringValue
        }
    }
}
