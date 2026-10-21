import AppKit

enum ExternalMarkdownToolbarCommand: Int {
    case save, find, reveal, close, importToTriptych

    var title: String {
        switch self {
        case .save: ScholiumL10n.string("Save")
        case .find: ScholiumL10n.string("Find")
        case .reveal: ScholiumL10n.string("Reveal Original in Finder")
        case .close: ScholiumL10n.string("Close Window")
        case .importToTriptych: ScholiumL10n.string("Import to Triptych…")
        }
    }
}

/// AppKit owns toolbar geometry, shared control groups and overflow. The
/// external document owns capabilities and execution; attachment updates only
/// project its current state into these retained native controls.
@MainActor
final class ExternalMarkdownWindowToolbar: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation, NSMenuDelegate {
    private enum Item {
        static let mode = NSToolbarItem.Identifier("scholium.externalMarkdown.mode")
        static let find = NSToolbarItem.Identifier("scholium.externalMarkdown.find")
        static let more = NSToolbarItem.Identifier("scholium.externalMarkdown.more")
        static let importDocument = NSToolbarItem.Identifier("scholium.externalMarkdown.import")
    }

    private let toolbar = NSToolbar(identifier: "scholium.externalMarkdown.toolbar")
    private let mode = NSToolbarItem(itemIdentifier: Item.mode)
    private let modeButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let find = NSToolbarItem(itemIdentifier: Item.find)
    private let more = NSMenuToolbarItem(itemIdentifier: Item.more)
    private let importDocument = NSToolbarItem(itemIdentifier: Item.importDocument)
    private weak var model: ExternalMarkdownWindowModel?
    private weak var window: NSWindow?
    private var isInvalidated = false

    init(model: ExternalMarkdownWindowModel) {
        self.model = model
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly

        let modeLabel = ScholiumL10n.string("Document Mode")
        mode.label = modeLabel
        mode.paletteLabel = modeLabel
        mode.toolTip = modeLabel
        mode.visibilityPriority = .high
        mode.autovalidates = false
        modeButton.bezelStyle = .toolbar
        modeButton.setAccessibilityLabel(modeLabel)
        modeButton.setAccessibilityIdentifier(Item.mode.rawValue)
        modeButton.menu = makeModeMenu()
        modeButton.sizeToFit()
        mode.view = modeButton
        let modeOverflow = NSMenuItem(title: modeLabel, action: nil, keyEquivalent: "")
        modeOverflow.submenu = makeModeMenu()
        mode.menuFormRepresentation = modeOverflow

        configure(find, command: .find)
        find.title = ""
        find.image = ScholiumNativeToolbarPresentation.symbol(named: "magnifyingglass")
        find.visibilityPriority = .high

        more.label = ScholiumL10n.string("More")
        more.paletteLabel = more.label
        more.toolTip = more.label
        more.image = ScholiumNativeToolbarPresentation.symbol(named: "ellipsis")
        more.showsIndicator = false
        more.isBordered = true
        more.style = .plain
        more.visibilityPriority = .high
        more.autovalidates = false
        let actions = NSMenu(title: more.label)
        actions.delegate = self
        for command in [ExternalMarkdownToolbarCommand.save, .find, .reveal, .close] {
            if command == .reveal { actions.addItem(.separator()) }
            actions.addItem(menuItem(for: command))
        }
        more.menu = actions

        configure(importDocument, command: .importToTriptych)
        importDocument.style = .prominent
        importDocument.backgroundTintColor = .controlAccentColor
    }

    func install(in window: NSWindow) {
        guard !isInvalidated else { return }
        self.window = window
        window.styleMask.insert(.fullSizeContentView)
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = toolbar
        refreshPresentation()
    }

    func refreshPresentation() {
        guard isAttached, let model else { return }
        if modeButton.title != model.mode.title { modeButton.selectItem(withTitle: model.mode.title) }
        modeButton.setAccessibilityValue(model.mode.title)
        let canSelectMode = NotePresentationMode.allCases.contains { model.canSelectMode($0) }
        mode.isEnabled = canSelectMode
        modeButton.isEnabled = canSelectMode
        mode.menuFormRepresentation?.isEnabled = canSelectMode
        more.isEnabled = true
        for item in [find, importDocument] {
            item.isEnabled = validateToolbarItem(item)
            item.menuFormRepresentation?.isEnabled = item.isEnabled
        }
        updateModeMenu(modeButton.menu)
        updateModeMenu(mode.menuFormRepresentation?.submenu)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        let menus: [NSMenu?] = [modeButton.menu, mode.menuFormRepresentation?.submenu, more.menu]
        for menu in menus {
            menu?.cancelTracking()
            menu?.delegate = nil
            menu?.removeAllItems()
        }
        for item in [mode, find, more, importDocument] {
            item.target = nil
            item.action = nil
            item.menuFormRepresentation = nil
            item.isEnabled = false
        }
        modeButton.target = nil
        modeButton.action = nil
        modeButton.isEnabled = false
        toolbar.delegate = nil
        if window?.toolbar === toolbar { window?.toolbar = nil }
        window = nil
        model = nil
    }

    private var isAttached: Bool { !isInvalidated && window?.toolbar === toolbar && model != nil }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Item.mode, .space, Item.find, Item.more, .space, Item.importDocument]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard !isInvalidated else { return nil }
        switch identifier {
        case Item.mode: return mode
        case Item.find: return find
        case Item.more: return more
        case Item.importDocument: return importDocument
        default: return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard isAttached, let command = ExternalMarkdownToolbarCommand(rawValue: item.tag) else { return false }
        return model?.canPerformToolbarCommand(command) == true
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard isAttached, let model else { return false }
        if item.action == #selector(selectMode(_:)),
            let raw = item.representedObject as? String, let requested = NotePresentationMode(rawValue: raw)
        {
            return model.canSelectMode(requested)
        }
        guard let command = ExternalMarkdownToolbarCommand(rawValue: item.tag) else { return false }
        return model.canPerformToolbarCommand(command)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateModeMenu(menu)
    }

    private func configure(_ item: NSToolbarItem, command: ExternalMarkdownToolbarCommand) {
        item.label = command.title
        item.paletteLabel = command.title
        item.title = command.title
        item.toolTip = command.title
        item.isBordered = true
        item.style = .plain
        item.tag = command.rawValue
        item.target = self
        item.action = #selector(performCommand(_:))
        item.menuFormRepresentation = menuItem(for: command)
    }

    private func menuItem(for command: ExternalMarkdownToolbarCommand) -> NSMenuItem {
        let item = NSMenuItem(title: command.title, action: #selector(performCommand(_:)), keyEquivalent: "")
        item.tag = command.rawValue
        item.target = self
        return item
    }

    private func makeModeMenu() -> NSMenu {
        let menu = NSMenu(title: ScholiumL10n.string("Document Mode"))
        menu.delegate = self
        for requested in NotePresentationMode.allCases {
            let item = NSMenuItem(title: requested.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.representedObject = requested.rawValue
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    private func updateModeMenu(_ menu: NSMenu?) {
        guard let model else { return }
        for item in menu?.items ?? [] {
            guard let raw = item.representedObject as? String, let requested = NotePresentationMode(rawValue: raw) else { continue }
            item.state = requested == model.mode ? .on : .off
        }
    }

    @objc private func selectMode(_ item: NSMenuItem) {
        defer { refreshPresentation() }
        guard validateMenuItem(item), let raw = item.representedObject as? String,
            let requested = NotePresentationMode(rawValue: raw)
        else { return }
        model?.selectMode(requested)
    }

    @objc private func performCommand(_ sender: Any) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSToolbarItem)?.tag ?? (sender as? NSControl)?.tag
        guard isAttached, let tag, let command = ExternalMarkdownToolbarCommand(rawValue: tag),
            let model, model.canPerformToolbarCommand(command)
        else { return }
        model.performToolbarCommand(command)
    }
}
