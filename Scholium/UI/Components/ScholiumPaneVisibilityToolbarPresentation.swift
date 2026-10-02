import AppKit

/// Native multi-selection projects each pane's independent visibility. The
/// owning window continues to admit commands and own the actual pane state.
@MainActor
enum ScholiumPaneVisibilityToolbarPresentation {
    static func group(
        identifier: NSToolbarItem.Identifier,
        label: String,
        items: [NSToolbarItem],
        target: AnyObject?,
        action: Selector?
    ) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(
            itemIdentifier: identifier,
            images: items.map { $0.image ?? NSImage(size: .zero) },
            selectionMode: .selectAny,
            labels: items.map(\.label),
            target: target,
            action: action)
        group.subitems = items
        group.label = label
        group.paletteLabel = label
        group.controlRepresentation = .expanded
        group.visibilityPriority = .user
        if #available(macOS 27, *) { group.role = .valueSelection }
        // The macOS 27 factory owns a private native view; `view` may be nil.
        // Public group/subitem properties own selection, labels and validation.
        let overflow = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: label)
        for item in items {
            if let command = item.menuFormRepresentation { menu.addItem(command) }
        }
        overflow.submenu = menu
        group.menuFormRepresentation = overflow
        return group
    }

    static func refresh(_ group: NSToolbarItemGroup, selected: [Bool]) {
        guard selected.count == group.subitems.count else { return }
        group.isEnabled = group.subitems.contains { $0.isEnabled }
        for index in selected.indices {
            let item = group.subitems[index]
            item.image?.accessibilityDescription = item.label
            group.setSelected(selected[index], at: index)
            item.menuFormRepresentation?.state = selected[index] ? .on : .off
        }
    }

    static func invalidate(_ group: NSToolbarItemGroup) {
        let overflow = group.menuFormRepresentation
        overflow?.target = nil
        overflow?.action = nil
        overflow?.isEnabled = false
        for item in group.subitems {
            item.target = nil
            item.action = nil
            item.isEnabled = false
            item.menuFormRepresentation?.target = nil
            item.menuFormRepresentation?.action = nil
            item.menuFormRepresentation?.isEnabled = false
            item.menuFormRepresentation = nil
        }
        group.subitems = []
        group.menuFormRepresentation?.submenu?.removeAllItems()
        // Setting nil asks the factory group to synthesize a fresh command on
        // every access. Retain one inert representation instead.
        let disabledOverflow = NSMenuItem(title: group.label, action: nil, keyEquivalent: "")
        disabledOverflow.isEnabled = false
        group.menuFormRepresentation = disabledOverflow
        group.target = nil
        group.action = nil
        group.isEnabled = false
        group.isHidden = true
    }
}
