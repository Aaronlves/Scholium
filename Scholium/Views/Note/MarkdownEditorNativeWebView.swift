import AppKit
import WebKit

final class WindowAttachedWebView: WKWebView {
    var onFirstWindowAttachment: (() -> Void)?
    weak var editorSession: MarkdownEditorSession?
    private var rightMouseMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            removeRightMouseMonitor()
            return
        }
        installRightMouseMonitorIfNeeded()
        guard let action = onFirstWindowAttachment else { return }
        onFirstWindowAttachment = nil
        action()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        return prepareEditorContextMenu(menu)
    }

    private func installRightMouseMonitorIfNeeded() {
        guard rightMouseMonitor == nil else { return }
        rightMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) {
            [weak self] event in
            self?.handleRightMouseDown(event) ?? event
        }
    }

    private func removeRightMouseMonitor() {
        guard let rightMouseMonitor else { return }
        NSEvent.removeMonitor(rightMouseMonitor)
        self.rightMouseMonitor = nil
    }

    private func handleRightMouseDown(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return event }
        // WKWebView dispatches pointer events to a private descendant view, so
        // overriding the outer view's menu(for:) is not enough. Ask the actual
        // hit view for WebKit's standard menu, append Scholium's domain
        // commands, then consume this one event to avoid a duplicate menu.
        let targetView = hitTest(point) ?? self
        let standardMenu = targetView === self
            ? (super.menu(for: event) ?? NSMenu())
            : (targetView.menu(for: event) ?? NSMenu())
        let menu = prepareEditorContextMenu(standardMenu)
        // Return from the local monitor before opening the replacement menu.
        // A synchronous nested menu loop lets WebKit enqueue its own generic
        // menu before the original event is consumed, producing a second
        // Font/Preview hierarchy after Scholium's menu closes.
        DispatchQueue.main.async {
            NSMenu.popUpContextMenu(menu, with: event, for: targetView)
        }
        return nil
    }

    private func prepareEditorContextMenu(_ menu: NSMenu) -> NSMenu {
        menu.identifier = NSUserInterfaceItemIdentifier("scholium.editor.contextMenu")
        for item in menu.items where item.identifier?.rawValue.hasPrefix("scholium.editor.") == true {
            menu.removeItem(item)
        }
        let commonFormattingTitles = Set([
            "Bold",
            "Italic",
            "Emphasis",
            "Underline",
            "Inline Code",
            "Link",
            ScholiumL10n.string("Bold"),
            ScholiumL10n.string("Emphasis"),
            ScholiumL10n.string("Inline Code"),
            ScholiumL10n.string("Link"),
        ])
        for item in menu.items where commonFormattingTitles.contains(item.title) {
            menu.removeItem(item)
        }
        let formattingSubmenuTitles = Set([
            "Font",
            "Typeface",
            ScholiumL10n.string("Typeface"),
        ])
        for item in menu.items where item.submenu != nil {
            let submenuDescriptors = item.submenu?.items.map { submenuItem in
                "\(submenuItem.title) \(String(describing: submenuItem.action))".lowercased()
            } ?? []
            let containsCommonFormatting = submenuDescriptors.contains { descriptor in
                descriptor.contains("bold")
                    || descriptor.contains("italic")
                    || descriptor.contains("underline")
            }
            if formattingSubmenuTitles.contains(item.title) || containsCommonFormatting {
                menu.removeItem(item)
            }
        }
        // Preview is already available through the clicked construct's
        // ordinary inline interaction. Keep secondary click free of a second
        // preview route and of WebKit's unexplained nested Preview menu.
        let genericPreviewTitles = Set([
            "Preview",
            "Show Preview",
            ScholiumL10n.string("Preview"),
            ScholiumL10n.string("Show Preview"),
        ])
        for item in menu.items where genericPreviewTitles.contains(item.title) {
            menu.removeItem(item)
        }
        guard let editorSession else { return menu }
        let available = Set(editorSession.context?.availableCommands ?? [])
        var addedAction = false
        // Selection formatting belongs to the Edit selection toolbar, the
        // Format menu, and keyboard shortcuts. Keep secondary click for
        // commands whose meaning depends on the clicked construct.
        for (title, command) in [
            (ScholiumL10n.string("Toggle Task"), MarkdownEditorCommand.toggleTask),
        ] where available.contains(command) {
            if !addedAction { menu.addItem(.separator()) }
            menu.addItem(editorMenuItem(title, command: command))
            addedAction = true
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
            if !addedAction { menu.addItem(.separator()) }
            let submenu = NSMenu(title: ScholiumL10n.string("Table"))
            tableCommands.forEach { submenu.addItem(editorMenuItem($0.0, command: $0.1)) }
            let item = NSMenuItem(title: ScholiumL10n.string("Table"), action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.table")
            item.submenu = submenu
            menu.addItem(item)
            addedAction = true
        }
        removeRedundantSeparators(from: menu)
        return menu
    }

    private func removeRedundantSeparators(from menu: NSMenu) {
        while menu.items.first?.isSeparatorItem == true {
            menu.removeItem(at: 0)
        }
        while menu.items.last?.isSeparatorItem == true {
            menu.removeItem(at: menu.items.count - 1)
        }
        var previousWasSeparator = false
        for item in menu.items.reversed() {
            if item.isSeparatorItem && previousWasSeparator {
                menu.removeItem(item)
            }
            previousWasSeparator = item.isSeparatorItem
        }
    }

    private func editorMenuItem(_ title: String, command: MarkdownEditorCommand) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performEditorCommand(_:)), keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.\(command.rawValue)")
        item.representedObject = command.rawValue
        item.target = self
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
