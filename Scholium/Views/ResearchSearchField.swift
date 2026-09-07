import AppKit
import SwiftUI
import ScholiumContracts

/// The native field editor owns composition and focus. Only committed text is
/// sent to Search; updates never overwrite marked text or reselect typed input.
struct ResearchSearchField: NSViewRepresentable {
    enum Command { case up, down, complete, submit, cancel }
    @Binding var text: String
    let placeholder: String
    @Binding var scope: SearchPresentationScope
    let openAdvanced: (() -> Void)?
    let isActive: Bool
    let focusRequestID: UInt64?
    let replacementID: UInt64
    let beganEditing: () -> Void
    let endedEditing: () -> Void
    let command: (Command) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.sendsSearchStringImmediately = true
        field.maximumRecents = 0
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.searchMenuTemplate = context.coordinator.makeSearchMenu()
        field.setAccessibilityIdentifier("scholium.searchField")
        field.setAccessibilityLabel(ScholiumL10n.string("Search"))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        // The field editor is authoritative during typing. A render can arrive
        // between AppKit edits; assigning stringValue then can discard keystrokes.
        // Only explicit model replacements may change an active field editor.
        if !field.isComposing {
            if field.currentEditor() == nil || field.appliedReplacementID != replacementID {
                if field.stringValue != text { field.stringValue = text }
            }
            field.appliedReplacementID = replacementID
        }
        field.focusRequestID = focusRequestID
        field.isSearchActive = isActive
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Field, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 220, height: nsView.intrinsicContentSize.height)
    }

    final class Field: NSSearchField {
        var appliedReplacementID: UInt64?
        var focusRequestID: UInt64? { didSet { applyFocusRequest() } }
        var isSearchActive = false {
            didSet {
                if oldValue && !isSearchActive { restoreFocusIfOwned() }
            }
        }
        private var appliedFocusRequestID: UInt64?
        private weak var previousResponder: NSResponder?
        var isComposing: Bool { (currentEditor() as? NSTextView)?.hasMarkedText() ?? false }
        override func becomeFirstResponder() -> Bool {
            if currentEditor() == nil, window?.firstResponder !== self {
                previousResponder = window?.firstResponder
            }
            return super.becomeFirstResponder()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyFocusRequest()
        }
        private func applyFocusRequest() {
            guard let focusRequestID, focusRequestID != appliedFocusRequestID,
                  !isComposing, let window, !isHiddenOrHasHiddenAncestor else { return }
            if currentEditor() != nil || window.makeFirstResponder(self) {
                appliedFocusRequestID = focusRequestID
            }
        }
        private func restoreFocusIfOwned() {
            guard let window, let editor = currentEditor(), window.firstResponder === editor else { return }
            if let view = previousResponder as? NSView, view.window === window {
                window.makeFirstResponder(view)
            } else {
                window.makeFirstResponder(nil)
            }
            previousResponder = nil
        }
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate, NSMenuItemValidation {
        var parent: ResearchSearchField
        init(_ parent: ResearchSearchField) { self.parent = parent }
        func makeSearchMenu() -> NSMenu {
            let menu = NSMenu(title: ScholiumL10n.string("Search"))
            let scopeMenu = NSMenu(title: ScholiumL10n.string("Search scope"))
            for (index, title) in ["This Note", "This Vault", "Triptych"].enumerated() {
                let item = NSMenuItem(title: ScholiumL10n.dynamicString(title), action: #selector(selectScope(_:)), keyEquivalent: "")
                item.tag = index
                item.target = self
                scopeMenu.addItem(item)
            }
            let scope = NSMenuItem(title: scopeMenu.title, action: nil, keyEquivalent: "")
            scope.submenu = scopeMenu
            menu.addItem(scope)
            menu.addItem(.separator())
            let clear = NSMenuItem(title: ScholiumL10n.string("Clear Filters"), action: #selector(clearFilters(_:)), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
            if parent.openAdvanced != nil {
                menu.addItem(.separator())
                let advanced = NSMenuItem(title: ScholiumL10n.string("Advanced Search…"), action: #selector(advancedSearch(_:)), keyEquivalent: "")
                advanced.target = self
                menu.addItem(advanced)
            }
            return menu
        }
        @objc func selectScope(_ sender: NSMenuItem) {
            let modes: [SearchPresentationScope] = [.thisNote, .currentVault, .triptych]
            guard modes.indices.contains(sender.tag) else { return }
            parent.scope = modes[sender.tag]
        }
        @objc func clearFilters(_ sender: NSMenuItem) {
            parent.scope = .triptych
        }
        @objc func advancedSearch(_ sender: NSMenuItem) { parent.openAdvanced?() }
        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            if item.action == #selector(selectScope(_:)) {
                item.state = [.thisNote, .currentVault, .triptych][item.tag] == parent.scope ? .on : .off
            } else if item.action == #selector(clearFilters(_:)) {
                return parent.scope != .triptych
            }
            return true
        }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.beganEditing() }
        func controlTextDidEndEditing(_ notification: Notification) { parent.endedEditing() }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? Field else { return }
            changed(field)
        }
        @objc func changed(_ field: Field) {
            guard !field.isComposing else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): return parent.command(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.command(.down)
            case #selector(NSResponder.insertTab(_:)): return parent.command(.complete)
            case #selector(NSResponder.insertNewline(_:)): return parent.command(.submit)
            case #selector(NSResponder.cancelOperation(_:)): return parent.command(.cancel)
            default: return false
            }
        }
    }
}
