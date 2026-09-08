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
    var focusRequest: UUID? = nil
    var navigate: ((Bool) -> Void)? = nil
    var dismiss: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> Field {
        let searchField = Field()
        searchField.placeholderString = ScholiumL10n.dynamicString(prompt)
        searchField.sendsSearchStringImmediately = true
        searchField.target = context.coordinator
        searchField.delegate = context.coordinator
        searchField.action = #selector(Coordinator.searchChanged(_:))
        searchField.setAccessibilityLabel(ScholiumL10n.dynamicString(prompt))
        searchField.setAccessibilityIdentifier(identifier)
        searchField.maximumRecents = 0
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if !options.isEmpty { searchField.searchMenuTemplate = context.coordinator.scopeMenu() }
        return searchField
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Field, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }

    func updateNSView(_ searchField: Field, context: Context) {
        context.coordinator.parent = self
        if (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true, searchField.stringValue != text {
            searchField.stringValue = text
        }
        searchField.focusRequest = focusRequest
    }

    final class Field: NSSearchField {
        var focusRequest: UUID? { didSet { applyFocus() } }
        private var appliedFocus: UUID?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyFocus()
        }
        private func applyFocus() {
            guard let focusRequest, focusRequest != appliedFocus,
                  (currentEditor() as? NSTextView)?.hasMarkedText() != true,
                  let window, window.makeFirstResponder(self) else { return }
            appliedFocus = focusRequest
            currentEditor()?.selectAll(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate, NSMenuItemValidation {
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

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if commandSelector == #selector(NSResponder.insertNewline(_:)), let navigate = parent.navigate {
                navigate(NSApp?.currentEvent?.modifierFlags.contains(.shift) == true)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)), let dismiss = parent.dismiss {
                dismiss()
                return true
            }
            return false
        }
    }
}
