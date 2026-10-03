import AppKit

/// Named PDF command groups shared by native toolbar and pull-down controls.
enum PDFReaderMenuButton {
    enum Kind: CaseIterable {
        case actions, zoom

        var title: String {
            switch self {
            case .actions: "PDF Actions"
            case .zoom: "PDF Zoom"
            }
        }

        var symbol: String {
            switch self {
            case .actions: "ellipsis"
            case .zoom: "magnifyingglass"
            }
        }

        var identifier: String {
            switch self {
            case .actions: "scholium.pdf.actions"
            case .zoom: "scholium.pdf.zoom"
            }
        }
    }

}

@MainActor
final class PDFReaderCommandMenu: NSObject, NSMenuDelegate {
    private enum Command: String {
        case attach, detach, export, reload, openZotero
        case zoomIn, zoomOut, fit
        case selectTool, highlightTool, commentTool, highlight, comment, showAnnotations

        var title: String {
            switch self {
            case .attach: "Attach or Replace PDF…"
            case .detach: "Detach PDF"
            case .export: "Export PDF…"
            case .reload: "Reload PDF"
            case .openZotero: "Open in Zotero"
            case .zoomIn: "Zoom In"
            case .zoomOut: "Zoom Out"
            case .fit: "Fit PDF"
            case .selectTool: "Select"
            case .highlightTool: "Highlight"
            case .commentTool: "Comment"
            case .highlight: "Highlight Selection"
            case .comment: "Add PDF Comment…"
            case .showAnnotations: "Show Annotations"
            }
        }
    }

    let menu: NSMenu
    private weak var controller: PDFReaderController?
    private let kind: PDFReaderMenuButton.Kind
    private let includesControlTitle: Bool
    private var isInvalidated = false
    private var overflowMenu: NSMenu?
    private let canPresent: @MainActor () -> Bool

    init(
        controller: PDFReaderController,
        kind: PDFReaderMenuButton.Kind,
        includesControlTitle: Bool = false,
        canPresent: @escaping @MainActor () -> Bool = { true }
    ) {
        self.canPresent = canPresent
        self.controller = controller
        self.kind = kind
        self.includesControlTitle = includesControlTitle
        let label = ScholiumL10n.dynamicString(kind.title)
        menu = NSMenu(title: label)
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        // Only pull-down NSControls consume a first item as their title.
        if includesControlTitle {
            let titleItem = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            titleItem.image = ScholiumNativeToolbarPresentation.symbol(named: kind.symbol)
            menu.addItem(titleItem)
        }
        for command in commandList {
            if kind == .actions, command == .selectTool || command == .highlight {
                menu.addItem(.separator())
            }
            let item = NSMenuItem(title: ScholiumL10n.dynamicString(command.title), action: #selector(performCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command.rawValue
            item.identifier = NSUserInterfaceItemIdentifier("\(kind.identifier).\(command.rawValue)")
            menu.addItem(item)
        }
        refresh()
    }

    var isEnabled: Bool {
        !isInvalidated && canPresent() && controller?.canUseReaderCommands == true
    }

    func update(controller: PDFReaderController) {
        guard !isInvalidated else { return }
        self.controller = controller
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    func makeOverflowMenu() -> NSMenu {
        if let overflowMenu { return overflowMenu }
        let overflow = NSMenu(title: ScholiumL10n.dynamicString(kind.title))
        overflow.autoenablesItems = false
        overflowMenu = overflow
        guard !isInvalidated else { return overflow }
        overflow.delegate = self
        for item in menu.items.dropFirst(includesControlTitle ? 1 : 0) {
            if let copy = item.copy() as? NSMenuItem { overflow.addItem(copy) }
        }
        refresh()
        return overflow
    }

    func cancelTracking() {
        menu.cancelTracking()
        overflowMenu?.cancelTracking()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        controller = nil
        for commands in [menu, overflowMenu].compactMap({ $0 }) {
            commands.cancelTracking()
            commands.delegate = nil
            for item in commands.items {
                item.target = nil
                item.action = nil
            }
            commands.removeAllItems()
        }
        overflowMenu = nil
    }

    private var commandList: [Command] {
        switch kind {
        case .actions:
            [
                .attach, .detach, .export, .reload, .openZotero,
                .selectTool, .highlightTool, .commentTool, .highlight, .comment, .showAnnotations,
            ]
        case .zoom: [.zoomIn, .zoomOut, .fit]
        }
    }

    private func isEnabled(_ command: Command, controller: PDFReaderController) -> Bool {
        guard !isInvalidated, canPresent(), controller.canUseReaderCommands else { return false }
        return switch command {
        case .attach: controller.canAttach
        case .detach: controller.canAttach && controller.context?.authoredPath != nil
        case .export, .zoomIn, .zoomOut, .fit: controller.canUseReaderCommands && controller.document != nil
        case .reload:
            !controller.isSaving && !controller.isLoading && !controller.hasUnsavedAnnotations
                && (controller.document != nil || (controller.operations != nil && controller.context?.authoredPath != nil))
        case .openZotero: controller.canUseReaderCommands && controller.zoteroSource != nil
        case .highlight: controller.canAnnotate && controller.hasSelection
        case .comment: controller.canAnnotate
        case .selectTool: controller.canSelectTool(.select)
        case .highlightTool: controller.canSelectTool(.highlight)
        case .commentTool: controller.canSelectTool(.comment)
        case .showAnnotations: controller.document != nil
        }
    }

    private func refresh() {
        for item in [menu, overflowMenu].compactMap({ $0 }).flatMap(\.items) {
            guard let raw = item.representedObject as? String, let command = Command(rawValue: raw) else { continue }
            item.isEnabled = controller.map { isEnabled(command, controller: $0) } ?? false
            item.isHidden = command == .openZotero && controller?.zoteroSource == nil
            let selected =
                switch command {
                case .showAnnotations: controller?.showsAnnotations == true
                case .selectTool: controller?.tool == .select
                case .highlightTool: controller?.tool == .highlight
                case .commentTool: controller?.tool == .comment
                default: false
                }
            item.state = selected ? .on : .off
        }
    }

    @objc private func performCommand(_ item: NSMenuItem) {
        guard !isInvalidated, let controller, let ownerMenu = item.menu, ownerMenu === menu || ownerMenu === overflowMenu,
            let raw = item.representedObject as? String, let command = Command(rawValue: raw),
            isEnabled(command, controller: controller)
        else { return }
        switch command {
        case .attach: controller.requestAttachPDF()
        case .detach:
            Task { do { try await controller.detachPDF() } catch { controller.presentFailure(error) } }
        case .export: controller.requestExport()
        case .reload: Task { await controller.reload() }
        case .openZotero:
            if let source = controller.zoteroSource { NSWorkspace.shared.open(source.pdfReference.url) }
        case .zoomIn: controller.zoom(1.25)
        case .zoomOut: controller.zoom(0.8)
        case .fit: controller.fitPage()
        case .selectTool: controller.selectTool(.select)
        case .highlightTool: controller.selectTool(.highlight)
        case .commentTool: controller.selectTool(.comment)
        case .highlight: controller.highlightSelection()
        case .comment: controller.requestComment()
        case .showAnnotations: controller.showsAnnotations.toggle()
        }
        refresh()
    }
}

/// Pull-down presentation only; its menu owns capability and command dispatch.
@MainActor
final class PDFReaderNativeMenuButton: NSPopUpButton {
    private let commands: PDFReaderCommandMenu

    override var acceptsFirstResponder: Bool { isEnabled && !isHiddenOrHasHiddenAncestor }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }

    init(controller: PDFReaderController, kind: PDFReaderMenuButton.Kind, canPresent: @escaping @MainActor () -> Bool = { true }) {
        commands = PDFReaderCommandMenu(controller: controller, kind: kind, includesControlTitle: true, canPresent: canPresent)
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28), pullsDown: true)
        isBordered = false
        controlSize = ScholiumNativeToolbarPresentation.controlSize
        contentTintColor = .labelColor
        imagePosition = .imageOnly
        (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        let label = ScholiumL10n.dynamicString(kind.title)
        setAccessibilityLabel(label)
        setAccessibilityIdentifier(kind.identifier)
        toolTip = label
        widthAnchor.constraint(greaterThanOrEqualToConstant: ScholiumGrid.Dimension.preferredCustomTarget).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: ScholiumGrid.Dimension.preferredCustomTarget).isActive = true
        menu = commands.menu
        autoenablesItems = false
        isEnabled = commands.isEnabled
    }

    required init?(coder: NSCoder) { nil }

    func update(controller: PDFReaderController) {
        commands.update(controller: controller)
        isEnabled = commands.isEnabled
    }

    func invalidate() {
        commands.invalidate()
        isEnabled = false
        setAccessibilityHidden(true)
    }
}
