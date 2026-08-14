import AppKit
import UniformTypeIdentifiers
import WebKit

enum EditorPastedImageSource: Sendable {
    case file(URL)
    case data(Data, preferredFilename: String)
}

/// The AppKit half of the retained editor surface.
///
/// CodeMirror owns selection and pointer interpretation. A finalized DOM
/// `contextmenu` event asks this view to present exactly one native menu. This
/// class therefore never monitors or consumes `rightMouseDown`, asks WebKit's
/// private descendant views for a premature menu, or opens a second nested
/// menu loop.
final class WindowAttachedWebView: WKWebView {
    var onFirstWindowAttachment: (() -> Void)?
    var onPasteImage: ((EditorPastedImageSource) -> Bool)?
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
                || Self.pastedImageSource(in: .general) != nil
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

    static func pastedImageSource(
        in pasteboard: NSPasteboard
    ) -> EditorPastedImageSource? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           let url = urls.first,
           let contentType = try? url.resourceValues(
            forKeys: [.contentTypeKey]
           ).contentType,
           contentType.conforms(to: .image) {
            return .file(url)
        }

        let preferredTypes = [
            NSPasteboard.PasteboardType("public.png"),
            .tiff,
        ]
        let candidates = preferredTypes + (pasteboard.types ?? []).filter {
            !preferredTypes.contains($0)
        }
        for pasteboardType in candidates {
            guard let type = UTType(pasteboardType.rawValue),
                  type.conforms(to: .image),
                  let data = pasteboard.data(forType: pasteboardType),
                  !data.isEmpty else { continue }
            let pathExtension = type.preferredFilenameExtension ?? "png"
            return .data(
                data,
                preferredFilename: "Pasted Image.\(pathExtension)"
            )
        }
        return nil
    }

    func consumePastedImage() -> Bool {
        guard let source = Self.pastedImageSource(in: .general) else { return false }
        return onPasteImage?(source) == true
    }

    @objc private func performPaste(_ sender: Any?) {
        if consumePastedImage() { return }
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
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
        let pasteItem = standardEditItem(
            ScholiumL10n.string("Paste"),
            action: #selector(performPaste(_:)),
            identifier: "paste",
            isEnabled: canPaste && !context.composing
        )
        pasteItem.target = self
        menu.addItem(pasteItem)
        menu.addItem(.separator())
        menu.addItem(standardEditItem(
            ScholiumL10n.string("Select All"),
            action: #selector(NSResponder.selectAll(_:)),
            identifier: "selectAll",
            isEnabled: !context.composing
        ))
        menu.addItem(.separator())
        menu.addItem(spellingAndGrammarItem())

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

    private func spellingAndGrammarItem() -> NSMenuItem {
        let submenu = NSMenu(title: ScholiumL10n.string("Spelling and Grammar"))
        submenu.autoenablesItems = true
        let commands: [(String, String)] = [
            (ScholiumL10n.string("Show Spelling and Grammar"), "showGuessPanel:"),
            (ScholiumL10n.string("Check Document Now"), "checkSpelling:"),
            (ScholiumL10n.string("Check Spelling While Typing"), "toggleContinuousSpellChecking:"),
            (ScholiumL10n.string("Check Grammar With Spelling"), "toggleGrammarChecking:"),
            (ScholiumL10n.string("Correct Spelling Automatically"), "toggleAutomaticSpellingCorrection:"),
        ]
        for (title, selector) in commands {
            let item = NSMenuItem(
                title: title,
                action: NSSelectorFromString(selector),
                keyEquivalent: ""
            )
            item.target = nil
            submenu.addItem(item)
        }
        let item = NSMenuItem(
            title: ScholiumL10n.string("Spelling and Grammar"),
            action: nil,
            keyEquivalent: ""
        )
        item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.spellingAndGrammar")
        item.submenu = submenu
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
