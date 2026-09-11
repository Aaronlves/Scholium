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
        if !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false),
            field.stringValue != model.query
        {
            field.stringValue = model.query
        }
        field.focusRequestID = model.focusRequestID
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FindSearchField, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.intrinsicContentSize.width,
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
                !((currentEditor() as? NSTextView)?.hasMarkedText() ?? false),
                let window, window.makeFirstResponder(self)
            else { return }
            appliedFocusRequestID = focusRequestID
            currentEditor()?.selectAll(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate, NSMenuItemValidation {
        var model: DocumentFindPresentationModel

        init(model: DocumentFindPresentationModel) { self.model = model }

        @objc func searchChanged(_ sender: NSTextField) {
            guard !((sender.currentEditor() as? NSTextView)?.hasMarkedText() ?? false) else { return }
            if sender is NSSearchField { model.setQuery(sender.stringValue) } else { model.setReplacement(sender.stringValue) }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            searchChanged(field)
        }
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
                guard control is NSSearchField else { return false }
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true { model.previous() } else { model.next() }
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

/// Replacement shares the query field's input-service boundary. Partial IME
/// text stays exclusively in the field editor until it is committed.
struct DocumentFindReplacementField: NSViewRepresentable {
    @ObservedObject var model: DocumentFindPresentationModel
    func makeCoordinator() -> DocumentFindSearchField.Coordinator { .init(model: model) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.placeholderString = ScholiumL10n.string("Replace with")
        field.delegate = context.coordinator
        field.setAccessibilityLabel(ScholiumL10n.string("Replace with"))
        field.setAccessibilityIdentifier("scholium.documentFind.replacement")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.model = model
        guard !((field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false) else { return }
        if field.stringValue != model.replacement { field.stringValue = model.replacement }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }
}
