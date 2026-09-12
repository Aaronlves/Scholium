import AppKit
import Combine

@MainActor
final class DetachedDocumentToolbar: NSObject, NSToolbarDelegate, NSMenuItemValidation {
    let toolbar = NSToolbar(identifier: "scholium.detachedDocumentToolbar")
    private weak var model: WindowModel?
    private var observation: AnyCancellable?
    private let mode: ScholiumDocumentModeToolbarItem

    init(model: WindowModel) {
        self.model = model
        mode = ScholiumDocumentModeToolbarItem(identifier: .init("mode"), model: model)
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        observation = model.commandObservation.$revision.sink { [weak self] _ in self?.mode.refreshPresentation() }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("mode"), .init("more")] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        if id.rawValue == "mode" { return mode }
        guard id.rawValue == "more" else { return nil }
        let item = NSMenuToolbarItem(itemIdentifier: id)
        item.label = ScholiumL10n.string("More")
        item.toolTip = item.label
        item.image = ScholiumNativeToolbarPresentation.symbol(named: "ellipsis", accessibilityDescription: item.label)
        item.showsIndicator = false
        let menu = NSMenu()
        populate(menu)
        item.menu = menu
        return item
    }

    private func populate(_ menu: NSMenu) {
        add("Move to Main Window", action: #selector(moveBack), to: menu)
        menu.addItem(.separator())
        add("Close Window", action: #selector(closeDocument), to: menu)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let model, !model.transferInProgress else { return false }
        return model.documentTabController.selectedTabID != nil
    }

    @discardableResult private func add(_ label: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: ScholiumL10n.dynamicString(label), action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }
    @objc private func moveBack() { model?.requestMoveDocumentBack() }
    @objc private func closeDocument() { model?.nativeWindowCoordinator?.requestNativeClose() }
}
