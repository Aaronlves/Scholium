import AppKit

/// The same native Review/Edit button in the workspace and document windows.
@MainActor
final class ScholiumDocumentModeToolbarItem: NSToolbarItem {
    private weak var model: WindowModel?

    init(identifier: NSToolbarItem.Identifier, model: WindowModel) {
        self.model = model
        super.init(itemIdentifier: identifier)
        target = self
        action = #selector(toggleMode)
        isBordered = true
        style = .plain
        visibilityPriority = .high
        possibleLabels = Set(NotePresentationMode.allCases.map {
            ScholiumDocumentModeToolbarButtonPresentation(mode: $0).accessibilityLabel
        })
        let overflow = NSMenuItem(title: "", action: #selector(toggleMode), keyEquivalent: "")
        overflow.target = self
        menuFormRepresentation = overflow
        refreshPresentation()
    }

    static func isAvailable(in model: WindowModel) -> Bool {
        guard !model.transferInProgress, let document = model.documentController.selectedDocument else { return false }
        let session = model.documentController.session(for: document.editingTarget)
        let destination = ScholiumDocumentModeToolbarButtonPresentation(mode: model.documentController.chromeProjection.mode).destination
        return !session.editorSession.isComposing && (destination == .read || model.canEditCurrentNote)
    }

    override func validate() { refreshPresentation() }

    func refreshPresentation() {
        guard let model else { isEnabled = false; return }
        let presentation = ScholiumDocumentModeToolbarButtonPresentation(mode: model.documentController.chromeProjection.mode)
        label = presentation.accessibilityLabel
        paletteLabel = label
        title = ""
        toolTip = presentation.toolTip
        image = ScholiumNativeToolbarPresentation.symbol(named: presentation.symbol, accessibilityDescription: presentation.mode.title)
        isEnabled = Self.isAvailable(in: model)
        isHidden = model.currentNote == nil
        menuFormRepresentation?.title = label
        menuFormRepresentation?.image = image
        menuFormRepresentation?.isEnabled = isEnabled
    }

    @objc private func toggleMode() {
        guard let model, Self.isAvailable(in: model) else { return }
        model.requestDocumentMode(ScholiumDocumentModeToolbarButtonPresentation(mode: model.documentController.chromeProjection.mode).destination)
    }
}
