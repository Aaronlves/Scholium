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
final class WindowAttachedWebView: DocumentNativeWebView, ScholiumDocumentInputStateProviding {
    /// The page owns its reuse age; only its window pool advances this value.
    var editorReuseCount = 0
    var onFirstWindowAttachment: (() -> Void)?
    var onPasteImage: ((EditorPastedImageSource) -> Bool)?
    weak var editorSession: MarkdownEditorSession?
    var onPassageAction: ((DocumentPassageAction) -> Void)?
    var onImagePreview: ((String) -> Void)?
    var scholiumIsComposing: Bool { editorSession?.isComposing == true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil,
            let action = onFirstWindowAttachment
        else { return }
        onFirstWindowAttachment = nil
        action()
    }

    func presentEditorContextMenu(
        clientX: Double,
        clientY: Double,
        context: MarkdownEditorContext,
        mode: MarkdownEditorMode
    ) {
        guard documentSurfaceAllowsInput, clientX.isFinite,
            clientY.isFinite,
            window != nil
        else { return }
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
            guard let self, self.window != nil, self.documentSurfaceAllowsInput else { return }
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
            contentType.conforms(to: .image)
        {
            return .file(url)
        }

        let preferredTypes = [
            NSPasteboard.PasteboardType("public.png"),
            .tiff,
        ]
        let candidates =
            preferredTypes
            + (pasteboard.types ?? []).filter {
                !preferredTypes.contains($0)
            }
        for pasteboardType in candidates {
            guard let type = UTType(pasteboardType.rawValue),
                type.conforms(to: .image),
                let data = pasteboard.data(forType: pasteboardType),
                !data.isEmpty
            else { continue }
            let pathExtension = type.preferredFilenameExtension ?? "png"
            return .data(
                data,
                preferredFilename: "Pasted Image.\(pathExtension)"
            )
        }
        return nil
    }

    func consumePastedImage() -> Bool {
        guard documentSurfaceAllowsInput,
            let source = Self.pastedImageSource(in: .general)
        else { return false }
        return onPasteImage?(source) == true
    }

    @objc private func performPaste(_ sender: Any?) {
        guard documentSurfaceAllowsInput else { return }
        if consumePastedImage() { return }
        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
    }

    @objc func performSelectAll(_ sender: Any?) {
        guard documentSurfaceAllowsInput, let editorSession else { return }
        let sessionID = editorSession.sessionID
        let documentID = editorSession.documentID
        let responder = window?.firstResponder
        Task { @MainActor [weak self] in
            guard self?.documentSurfaceAllowsInput == true, self?.editorSession === editorSession,
                editorSession.sessionID == sessionID, editorSession.documentID == documentID,
                self?.window?.firstResponder === responder
            else { return }
            do {
                try await editorSession.selectAll()
            } catch {
                guard self?.documentSurfaceAllowsInput == true, self?.editorSession === editorSession,
                    editorSession.sessionID == sessionID, editorSession.documentID == documentID,
                    self?.window?.firstResponder === responder
                else { return }
                editorSession.reportError(ScholiumErrorLocalization.message(error))
            }
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

        if let imageTarget = context.imageTarget, onImagePreview != nil {
            let generation = editorSession?.generation
            let sessionID = editorSession?.sessionID
            let item = PassageMenuItem(title: ScholiumL10n.string("View Original Image"), enabled: !context.composing) { [weak self] in
                guard let self, let session = self.editorSession,
                    session.generation == generation, session.sessionID == sessionID,
                    session.context?.selections == context.selections, !session.isComposing
                else { return }
                self.onImagePreview?(imageTarget)
            }
            item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.viewOriginalImage")
            menu.addItem(item)
            menu.addItem(.separator())
        }

        menu.addItem(
            standardEditItem(
                ScholiumL10n.string("Cut"),
                action: #selector(NSText.cut(_:)),
                identifier: "cut",
                isEnabled: hasSelection && !context.composing
            ))
        menu.addItem(
            standardEditItem(
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
        let selectAllItem = standardEditItem(
            ScholiumL10n.string("Select All"),
            action: #selector(performSelectAll(_:)),
            identifier: "selectAll",
            isEnabled: !context.composing
        )
        selectAllItem.target = self
        menu.addItem(selectAllItem)
        menu.addItem(.separator())
        menu.addItem(spellingAndGrammarItem())

        if onPassageAction != nil {
            menu.addItem(.separator())
            let generation = editorSession?.generation
            let sessionID = editorSession?.sessionID
            for action in DocumentPassageAction.allCases {
                let item = PassageMenuItem(
                    title: action.title,
                    enabled: !context.composing && context.selections.count == 1
                ) { [weak self] in
                    guard let self, let session = self.editorSession,
                        session.generation == generation, session.sessionID == sessionID,
                        session.context?.selections == context.selections, !session.isComposing
                    else { return }
                    self.onPassageAction?(action)
                }
                item.identifier = NSUserInterfaceItemIdentifier("scholium.passage.\(action.rawValue)")
                menu.addItem(item)
            }
        }

        // System edit actions are always first. Scholium adds only commands
        // whose meaning depends on one collapsed, clicked Edit construct.
        guard mode == .livePreview,
            !hasSelection,
            !context.composing
        else { return menu }
        let available = Set(context.availableCommands)
        var contextualItems: [NSMenuItem] = []
        if available.contains(.toggleTask) {
            contextualItems.append(
                editorMenuItem(
                    ScholiumL10n.string("Toggle Task"),
                    command: .toggleTask,
                    context: context,
                    mode: mode
                ))
        }

        let tableCommandGroups: [[(String, MarkdownEditorCommand)]] = [
            [
                (ScholiumL10n.string("Insert Row Before"), .tableInsertRowBefore),
                (ScholiumL10n.string("Insert Row After"), .tableInsertRowAfter),
                (ScholiumL10n.string("Delete Row"), .tableDeleteRow),
            ],
            [
                (ScholiumL10n.string("Insert Column Before"), .tableInsertColumnBefore),
                (ScholiumL10n.string("Insert Column After"), .tableInsertColumnAfter),
                (ScholiumL10n.string("Delete Column"), .tableDeleteColumn),
            ],
            [
                (ScholiumL10n.string("Align Left"), .tableAlignLeft),
                (ScholiumL10n.string("Align Center"), .tableAlignCenter),
                (ScholiumL10n.string("Align Right"), .tableAlignRight),
            ],
        ].map { $0.filter { available.contains($0.1) } }.filter { !$0.isEmpty }
        if !tableCommandGroups.isEmpty {
            let submenu = NSMenu(title: ScholiumL10n.string("Table"))
            submenu.autoenablesItems = false
            for (index, group) in tableCommandGroups.enumerated() {
                if index > 0 { submenu.addItem(.separator()) }
                group.forEach {
                    submenu.addItem(editorMenuItem($0.0, command: $0.1, context: context, mode: mode))
                }
            }
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
        command: MarkdownEditorCommand,
        context: MarkdownEditorContext,
        mode: MarkdownEditorMode
    ) -> NSMenuItem {
        let editorSession = editorSession
        let sessionID = editorSession?.sessionID
        let documentID = editorSession?.documentID
        let generation = editorSession?.generation
        let isCurrent: @MainActor () -> Bool = { [weak self, weak editorSession] in
            guard let self, let editorSession,
                self.editorSession === editorSession, editorSession.webView === self,
                self.window != nil, !self.isHiddenOrHasHiddenAncestor,
                self.documentSurfaceAllowsInput,
                editorSession.isReady, editorSession.isLoaded, !editorSession.isComposing,
                editorSession.sessionID == sessionID, editorSession.documentID == documentID,
                editorSession.generation == generation, editorSession.presentedMode == mode,
                editorSession.canAttemptPreview,
                editorSession.context?.selections == context.selections,
                editorSession.context?.availableCommands.contains(command) == true
            else { return false }
            return true
        }
        let item = PassageMenuItem(title: title, enabled: true) { [weak self, weak editorSession] in
            guard self != nil, editorSession != nil, isCurrent() else { return }
            Task { @MainActor [weak self, weak editorSession] in
                guard let self, let editorSession, isCurrent() else { return }
                do {
                    // Selection-only changes do not advance source generation.
                    // Recheck this menu's context after the mutation lane drains.
                    _ = try await editorSession.send(
                        .command(command, argument: nil), in: self, admittingCommand: isCurrent)
                } catch is CancellationError {
                    return
                } catch MarkdownEditorSession.SessionError.staleRequest {
                    return
                } catch {
                    guard isCurrent() else { return }
                    editorSession.reportError(ScholiumErrorLocalization.message(error))
                }
            }
        }
        item.identifier = NSUserInterfaceItemIdentifier("scholium.editor.\(command.rawValue)")
        return item
    }
}
