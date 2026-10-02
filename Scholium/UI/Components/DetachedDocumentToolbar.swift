import AppKit
import Combine

@MainActor
final class DetachedDocumentToolbar: NSObject, NSToolbarDelegate, NSToolbarItemValidation, NSMenuItemValidation {
    let toolbar = NSToolbar(identifier: "scholium.detachedDocumentToolbar")
    private weak var model: WindowModel?
    private var observation: AnyCancellable?
    private var readingObservation: AnyCancellable?
    private var geometryObservation: AnyCancellable?
    private weak var window: NSWindow?
    private var readingDivider: NSTrackingSeparatorToolbarItem?
    private var readerControls: PDFReaderToolbarController?
    private let mode: ScholiumDocumentModeToolbarItem
    private let more: DocumentNoteActionsToolbarItem
    private let pdfReader: NSToolbarItemGroup
    private let pdfReaderCommand: NSToolbarItem
    private var isInvalidated = false

    init(model: WindowModel) {
        self.model = model
        mode = ScholiumDocumentModeToolbarItem(identifier: .init("mode"), model: model)
        more = DocumentNoteActionsToolbarItem(identifier: .init("more"), model: model)
        pdfReaderCommand = NSToolbarItem(itemIdentifier: .init("scholium.toolbar.pdfReader.toggle"))
        pdfReaderCommand.label = ScholiumL10n.string("PDF Reader")
        pdfReaderCommand.image = ScholiumNativeToolbarPresentation.symbol(named: "doc.richtext")
        pdfReader = ScholiumPaneVisibilityToolbarPresentation.group(
            identifier: .init("scholium.toolbar.pdfReader"), label: pdfReaderCommand.label,
            items: [pdfReaderCommand], target: nil, action: nil)
        super.init()
        readerControls = PDFReaderToolbarController(controller: model.pdfReaderController) { [weak self] in self?.refreshReaderPresentation() }
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        pdfReader.label = ScholiumL10n.string("PDF Reader")
        pdfReader.image = ScholiumNativeToolbarPresentation.symbol(named: "doc.richtext")
        pdfReader.isBordered = true
        pdfReader.style = .plain
        pdfReader.visibilityPriority = .user
        pdfReader.target = self
        pdfReader.action = #selector(togglePDFReader(_:))
        pdfReaderCommand.target = self
        pdfReaderCommand.action = #selector(togglePDFReader(_:))
        pdfReader.possibleLabels = [ScholiumL10n.string("Hide PDF Reader"), ScholiumL10n.string("Show PDF Reader")]
        let overflow = NSMenuItem(title: pdfReader.label, action: #selector(togglePDFReader(_:)), keyEquivalent: "")
        overflow.target = self
        pdfReader.menuFormRepresentation = overflow
        observation = model.commandObservation.$revision.sink { [weak self] _ in
            self?.mode.refreshPresentation()
            self?.more.refreshPresentation()
            self?.refreshReaderPresentation()
        }
        readingObservation = NotificationCenter.default.publisher(for: ScholiumDocumentReadingSplitController.participationDidChange)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshReaderPresentation() }
        geometryObservation = NotificationCenter.default.publisher(for: NSSplitView.didResizeSubviewsNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification))
            .receive(on: DispatchQueue.main).sink { [weak self] notification in
                guard let self, !self.isInvalidated, let window = self.window else { return }
                guard
                    notification.object as? NSWindow === window
                        || notification.object as? NSSplitView === self.readingController?.splitView
                else { return }
                self.updateReaderRegionWidth()
            }
    }

    func install(in window: NSWindow) {
        guard !isInvalidated else { return }
        self.window = window
        if window.toolbar !== toolbar { window.toolbar = toolbar }
        refreshReaderPresentation()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        observation?.cancel()
        observation = nil
        readingObservation?.cancel()
        readingObservation = nil
        geometryObservation?.cancel()
        geometryObservation = nil
        readerControls?.invalidate()
        readerControls = nil
        readingDivider = nil
        window = nil
        model = nil
        mode.invalidate()
        more.invalidate()
        ScholiumPaneVisibilityToolbarPresentation.invalidate(pdfReader)
        pdfReader.target = nil
        pdfReader.action = nil
        pdfReader.isEnabled = false
        for item in toolbar.items {
            item.target = nil
            item.action = nil
            item.isEnabled = false
        }
        toolbar.delegate = nil
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers(
            readerVisible: readingController?.readerIsVisible == true,
            readerPresentation: readerControls?.presentation ?? .actions)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    static func itemIdentifiers(readerVisible: Bool, readerPresentation: PDFReaderToolbarController.Presentation = .expanded) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .init("mode"), .init("more")]
            + (readerVisible
                ? [ScholiumWorkspaceToolbarController.Item.readingDivider]
                    + PDFReaderToolbarController.itemIdentifiers(for: readerPresentation) + [.flexibleSpace] : [.space]) + [
                ScholiumWorkspaceToolbarController.Item.pdfReader
            ]
    }

    private var readingController: ScholiumDocumentReadingSplitController? {
        guard let view = window?.contentView else { return nil }
        return ScholiumDocumentReadingSplitController.find(in: view)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        guard !isInvalidated else { return nil }
        if id.rawValue == "mode" { return mode }
        if id == ScholiumWorkspaceToolbarController.Item.readingDivider {
            guard let readingController, readingController.splitView.window === window else { return nil }
            if readingDivider?.splitView !== readingController.splitView {
                readingDivider = NSTrackingSeparatorToolbarItem(
                    identifier: id, splitView: readingController.splitView, dividerIndex: 0)
                readingDivider?.visibilityPriority = .user
            }
            return readingDivider
        }
        if PDFReaderToolbarController.allIdentifiers.contains(id) {
            if let window {
                readerControls?.install(in: window, toolbar: toolbar, readerView: readingController?.readerController.view)
            }
            updateReaderRegionWidth()
            return readerControls?.item(for: id)
        }
        if id == pdfReader.itemIdentifier {
            refreshReaderPresentation(updateTopology: false)
            return pdfReader
        }
        guard id.rawValue == "more" else { return nil }
        return more
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard !isInvalidated else { return false }
        guard item === pdfReader else { return item.isEnabled }
        return model.map { PDFReaderWindowCommand.isAvailable(in: $0) } == true
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard !isInvalidated else { return false }
        item.state = model.map { PDFReaderWindowCommand.isVisible(in: $0) } == true ? .on : .off
        return model.map { PDFReaderWindowCommand.isAvailable(in: $0) } == true
    }

    @objc private func togglePDFReader(_ sender: Any?) {
        guard !isInvalidated, let model else { return }
        defer { refreshReaderPresentation() }
        PDFReaderWindowCommand.toggle(in: model)
    }

    private func updateReaderRegionWidth() {
        guard !isInvalidated, let readingController, readingController.readerIsVisible,
            let window, readingController.splitView.window === window
        else { return }
        readerControls?.setRegionWidth(width: readingController.readerController.view.bounds.width, trailingPaneSwitchCount: 1)
    }

    private func refreshReaderPresentation(updateTopology: Bool = true) {
        guard !isInvalidated, let model else { return }
        if let window {
            readerControls?.install(in: window, toolbar: toolbar, readerView: readingController?.readerController.view)
        }
        updateReaderRegionWidth()
        if updateTopology, window != nil {
            let identifiers = Self.itemIdentifiers(
                readerVisible: readingController?.readerIsVisible == true,
                readerPresentation: readerControls?.presentation ?? .actions)
            if toolbar.itemIdentifiers != identifiers { toolbar.itemIdentifiers = identifiers }
            if let readingController, let readingDivider { readingDivider.splitView = readingController.splitView }
        }
        updateReaderRegionWidth()
        readerControls?.refresh()
        let label = ScholiumL10n.dynamicString(PDFReaderWindowCommand.isVisible(in: model) ? "Hide PDF Reader" : "Show PDF Reader")
        pdfReader.label = label
        pdfReader.paletteLabel = label
        pdfReader.title = ""
        pdfReader.toolTip = label
        pdfReader.isEnabled = PDFReaderWindowCommand.isAvailable(in: model)
        pdfReaderCommand.label = label
        pdfReaderCommand.toolTip = label
        pdfReaderCommand.isEnabled = pdfReader.isEnabled
        ScholiumPaneVisibilityToolbarPresentation.refresh(
            pdfReader, selected: [PDFReaderWindowCommand.isVisible(in: model)])
        pdfReader.menuFormRepresentation?.title = label
        pdfReader.menuFormRepresentation?.image = pdfReader.image
        pdfReader.menuFormRepresentation?.isEnabled = pdfReader.isEnabled
        pdfReader.menuFormRepresentation?.state = PDFReaderWindowCommand.isVisible(in: model) ? .on : .off
    }
}
