import AppKit
import SwiftUI

/// AppKit owns the field editor, search-menu tracking, and input services;
/// the presentation model owns the query and explicit focus requests.
struct DocumentFindSearchField: NSViewRepresentable {
    @ObservedObject var model: DocumentFindPresentationModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> FindSearchField {
        let field = FindSearchField()
        field.placeholderString = ScholiumL10n.string("Find in Document")
        field.sendsSearchStringImmediately = true
        field.maximumRecents = 0
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.setAccessibilityLabel(ScholiumL10n.string("Find in Document"))
        field.setAccessibilityIdentifier("scholium.documentFind.query")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let menu = NSMenu(title: ScholiumL10n.string("Find Options"))
        for (title, action) in [
            (ScholiumL10n.string("Case Sensitive"), #selector(Coordinator.toggleCaseSensitive(_:))),
            (ScholiumL10n.string("Whole Word"), #selector(Coordinator.toggleWholeWord(_:))),
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = context.coordinator
            menu.addItem(item)
        }
        field.searchMenuTemplate = menu
        return field
    }

    func updateNSView(_ field: FindSearchField, context: Context) {
        context.coordinator.model = model
        if field.stringValue != model.query { field.stringValue = model.query }
        field.focusRequestID = model.focusRequestID
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FindSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }

    final class FindSearchField: NSSearchField {
        var focusRequestID: UInt64? { didSet { applyFocusRequest() } }
        private var appliedFocusRequestID: UInt64?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyFocusRequest()
        }

        private func applyFocusRequest() {
            guard let focusRequestID, focusRequestID != appliedFocusRequestID,
                  let window, window.makeFirstResponder(self) else { return }
            appliedFocusRequestID = focusRequestID
            currentEditor()?.selectAll(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate, NSMenuItemValidation {
        var model: DocumentFindPresentationModel

        init(model: DocumentFindPresentationModel) { self.model = model }

        @objc func searchChanged(_ sender: NSSearchField) { model.setQuery(sender.stringValue) }
        @objc func toggleCaseSensitive(_ sender: NSMenuItem) { model.setCaseSensitive(!model.caseSensitive) }
        @objc func toggleWholeWord(_ sender: NSMenuItem) { model.setWholeWord(!model.wholeWord) }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            if menuItem.action == #selector(toggleCaseSensitive(_:)) {
                menuItem.state = model.caseSensitive ? .on : .off
            } else if menuItem.action == #selector(toggleWholeWord(_:)) {
                menuItem.state = model.wholeWord ? .on : .off
            }
            return true
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { model.previous() }
                else { model.next() }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                model.dismiss()
                return true
            default:
                return false
            }
        }
    }
}
