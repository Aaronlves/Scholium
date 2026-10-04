import AppKit
import Combine

@MainActor
final class DetachedDocumentToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "scholium.detachedDocumentToolbar")
    private weak var model: WindowModel?
    private var observation: AnyCancellable?
    private let mode: ScholiumDocumentModeToolbarItem
    private let more: DocumentNoteActionsToolbarItem
    private var isInvalidated = false

    init(model: WindowModel) {
        self.model = model
        mode = ScholiumDocumentModeToolbarItem(identifier: .init("mode"), model: model)
        more = DocumentNoteActionsToolbarItem(identifier: .init("more"), model: model)
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        observation = model.commandObservation.$revision.sink { [weak self] _ in
            self?.mode.refreshPresentation()
            self?.more.refreshPresentation()
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        observation?.cancel()
        observation = nil
        model = nil
        mode.invalidate()
        more.invalidate()
        for item in toolbar.items {
            item.target = nil
            item.action = nil
            item.isEnabled = false
        }
        toolbar.delegate = nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, .init("mode"), .init("more")] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        guard !isInvalidated else { return nil }
        if id.rawValue == "mode" { return mode }
        guard id.rawValue == "more" else { return nil }
        return more
    }
}
