import AppKit
import WebKit

/// The AppKit half of the retained editor surface.
///
/// CodeMirror owns selection and pointer interpretation. A finalized DOM
/// `contextmenu` event asks this view to present exactly one native menu. This
/// class therefore never monitors or consumes `rightMouseDown`, asks WebKit's
/// private descendant views for a premature menu, or opens a second nested
/// menu loop.
final class WindowAttachedWebView: WKWebView {
    var onFirstWindowAttachment: (() -> Void)?
    weak var editorSession: MarkdownEditorSession?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil,
              let action = onFirstWindowAttachment else { return }
        onFirstWindowAttachment = nil
        action()
    }

    func presentEditorContextMenu(
        clientX: Double,
        clientY: Double,
        context: MarkdownEditorContext,
        mode: MarkdownEditorMode
    ) {
        guard clientX.isFinite,
              clientY.isFinite,
              window != nil else { return }
        let menu = makeEditorContextMenu(
            context: context,
            mode: mode,
            canPaste: NSPasteboard.general.string(forType: .string) != nil
        )
        let x = min(max(0, clientX), bounds.width)
        let webY = min(max(0, clientY), bounds.height)
        let point = NSPoint(
            x: x,
            y: isFlipped ? webY : bounds.height - webY
        )

        // The script message is delivered while WebKit is unwinding the DOM
        // context-menu event. Present on the next AppKit turn after that event
        // has been prevented and CodeMirror has synchronized its selection.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            menu.popUp(positioning: nil, at: point, in: self)
        }
    }

    func makeEditorContextMenu(
        context: MarkdownEditorContext,
        mode: MarkdownEditorMode,
        canPaste: Bool
    ) -> NSMenu {
        let menu = NSMenu()
        menu.identifier = NSUserInterfaceItemIdentifier("scholium.editor.contextMenu")
        menu.autoenablesItems = false
        let hasSelection = context.selections.contains(where: \.isNonempty)

        menu.addItem(standardEditItem(
            ScholiumL10n.string("Cut"),
            action: #selector(NSText.cut(_:)),
            identifier: "cut",
            isEnabled: hasSelection && !context.composing
        ))
        menu.addItem(standardEditItem(
            ScholiumL10n.string("Copy"),
            action: #selector(NSText.copy(_:)),
            identifier: "copy",
            isEnabled: hasSelection
        ))
        menu.addItem(standardEditItem(
            ScholiumL10n.string("Paste"),
            action: #selector(NSText.paste(_:)),
            identifier: "paste",
            isEnabled: canPaste && !context.composing
        ))
        menu.addItem(.separator())
        menu.addItem(standardEditItem(
            ScholiumL10n.string("Select All"),
            action: #selector(NSResponder.selectAll(_:)),
            identifier: "selectAll",
            isEnabled: !context.composing
        ))

        // System edit actions are always first. Scholium adds only commands
        // whose meaning depends on one collapsed, clicked Edit construct.
        guard mode == .livePreview,
              !hasSelection,
              !context.composing else { return menu }
        let available = Set(context.availableCommands)
        var contextualItems: [NSMenuItem] = []
        if available.contains(.toggleTask) {
            contextualItems.append(editorMenuItem(
                ScholiumL10n.string("Toggle Task"),
                command: .toggleTask
            ))
        }

        let tableCommands: [(String, MarkdownEditorCommand)] = [
            (ScholiumL10n.string("Insert Row Before"), .tableInsertRowBefore),
            (ScholiumL10n.string("Insert Row After"), .tableInsertRowAfter),
            (ScholiumL10n.string("Delete Row"), .tableDeleteRow),
            (ScholiumL10n.string("Insert Column Before"), .tableInsertColumnBefore),
            (ScholiumL10n.string("Insert Column After"), .tableInsertColumnAfter),
            (ScholiumL10n.string("Delete Column"), .tableDeleteColumn),
            (ScholiumL10n.string("Align Left"), .tableAlignLeft),
            (ScholiumL10n.string("Align Center"), .tableAlignCenter),
            (ScholiumL10n.string("Align Right"), .tableAlignRight),
        ].filter { available.contains($0.1) }
        if !tableCommands.isEmpty {
            let submenu = NSMenu(title: ScholiumL10n.string("Table"))
            submenu.autoenablesItems = false
            tableCommands.forEach { submenu.addItem(editorMenuItem($0.0, command: $0.1)) }
            let item = NSMenuItem(
                title: ScholiumL10n.string("Table"),
                action: nil,
                keyEquivalent: ""
            )
            item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.table")
            item.submenu = submenu
            contextualItems.append(item)
        }

        if !contextualItems.isEmpty {
            menu.addItem(.separator())
            contextualItems.forEach { menu.addItem($0) }
        }
        return menu
    }

    private func standardEditItem(
        _ title: String,
        action: Selector,
        identifier: String,
        isEnabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.\(identifier)")
        item.target = nil
        item.isEnabled = isEnabled
        return item
    }

    private func editorMenuItem(
        _ title: String,
        command: MarkdownEditorCommand
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(performEditorCommand(_:)),
            keyEquivalent: ""
        )
        item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.\(command.rawValue)")
        item.representedObject = command.rawValue
        item.target = self
        item.isEnabled = true
        return item
    }

    @objc private func performEditorCommand(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let command = MarkdownEditorCommand(rawValue: rawValue),
              let editorSession else { return }
        Task { @MainActor in
            do {
                try await editorSession.perform(command)
            } catch {
                editorSession.reportError(error.localizedDescription)
            }
        }
    }
}
