import AppKit
import Combine
import Foundation
import ScholiumContracts
import SwiftUI

/// The configured window has one native toolbar. Tracking separators establish
/// Library, Document, and Apparatus sections. Sidebar and document-history
/// controls remain leading of the Library boundary. The Inspector projection
/// control begins the Apparatus section and its visibility control ends it;
/// collapsing either pane changes no item topology.
@MainActor
final class ScholiumWorkspaceToolbarController: NSObject, NSToolbarDelegate, NSPopoverDelegate {
    static let toolbarIdentifier = NSToolbar.Identifier("scholium.workspaceToolbar")

    enum Item {
        static let sidebar = NSToolbarItem.Identifier("scholium.toolbar.sidebar")
        static let back = NSToolbarItem.Identifier("scholium.toolbar.back")
        static let forward = NSToolbarItem.Identifier("scholium.toolbar.forward")
        static let inspector = NSToolbarItem.Identifier("scholium.toolbar.inspector")
        static let inspectorModes = NSToolbarItem.Identifier(
            "scholium.toolbar.inspectorModes"
        )
        // These identifiers are structural bounds for the Document toolbar.
        static let libraryDivider = NSToolbarItem.Identifier.sidebarTrackingSeparator
        static let documentInformation = NSToolbarItem.Identifier(
            "scholium.toolbar.documentInformation"
        )
        static let documentMode = NSToolbarItem.Identifier(
            "scholium.toolbar.documentMode"
        )
        static let settlement = NSToolbarItem.Identifier(
            "scholium.toolbar.settlement"
        )
        static let researchRecords = NSToolbarItem.Identifier(
            "scholium.toolbar.researchRecords"
        )
        // Apparatus is an explicitly managed trailing split item rather than
        // AppKit's Inspector factory item. A private identifier keeps the
        // initializer's explicit dividerIndex authoritative instead of asking
        // AppKit to rediscover and regroup an Inspector section that no longer
        // exists.
        static let apparatusDivider = NSToolbarItem.Identifier(
            "scholium.toolbar.apparatusDivider"
        )
    }

    private let appState: WindowModel
    private let windowActions: WorkspaceWindowActions
    private let splitViewController: NSSplitViewController
    private let toolbar: NSToolbar
    private let documentInformationPopover: NSPopover
    private let settlementPopover: NSPopover
    private weak var window: NSWindow?
    private weak var responderBeforeDocumentInformation: NSResponder?
    private weak var responderBeforeSettlement: NSResponder?
    private var documentInformationHostingController: DocumentInformationHostingController?
    private var settlementPopoverHostingController: DocumentSettlementPopoverHostingController?
    private var presentationCancellables: Set<AnyCancellable> = []

    init(
        appState: WindowModel,
        windowActions: WorkspaceWindowActions,
        splitViewController: NSSplitViewController
    ) {
        self.appState = appState
        self.windowActions = windowActions
        self.splitViewController = splitViewController
        toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        documentInformationPopover = NSPopover()
        settlementPopover = NSPopover()
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        documentInformationPopover.behavior = .transient
        documentInformationPopover.delegate = self
        settlementPopover.behavior = .transient
        settlementPopover.delegate = self
        observePresentation()
    }

    func install(in window: NSWindow) {
        guard splitViewController.splitView.window === window else { return }
        self.window = window
        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
        installToolbarItemsIfNeeded()
        refreshPresentation()
    }

    func controls(_ candidate: NSSplitViewController) -> Bool {
        splitViewController === candidate
    }

    func invalidate() {
        documentInformationPopover.close()
        settlementPopover.close()
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            Item.sidebar,
            Item.back,
            Item.forward,
            Item.libraryDivider,
            Item.documentInformation,
            .space,
            Item.documentMode,
            Item.researchRecords,
            Item.settlement,
            Item.apparatusDivider,
            Item.inspectorModes,
            Item.inspector,
        ]
    }

    static var itemIdentifiers: [NSToolbarItem.Identifier] {
        [
            Item.sidebar,
            Item.back,
            Item.forward,
            Item.libraryDivider,
            Item.documentInformation,
            .flexibleSpace,
            Item.settlement,
            .space,
            Item.documentMode,
            Item.researchRecords,
            Item.apparatusDivider,
            Item.inspectorModes,
            .flexibleSpace,
            Item.inspector,
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Item.sidebar:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Sidebar"),
                systemImage: "sidebar.leading",
                action: #selector(toggleSidebar(_:)),
                visibilityPriority: .user
            )
            item.possibleLabels = [
                ScholiumL10n.string("Hide Sidebar"),
                ScholiumL10n.string("Show Sidebar"),
            ]
            return item
        case Item.back:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Back"),
                systemImage: "arrow.left",
                action: #selector(goBack(_:))
            )
        case Item.forward:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Forward"),
                systemImage: "arrow.right",
                action: #selector(goForward(_:))
            )
        case Item.libraryDivider:
            let splitView = splitViewController.splitView
            let item = NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 0
            )
            item.visibilityPriority = .user
            return item
        case Item.documentInformation:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document Information"),
                systemImage: "info.circle",
                action: #selector(toggleDocumentInformation(_:))
            )
            // This is the one Document-leading item AppKit may position next
            // to the system-owned title. Sidebar and history controls must
            // remain in their declared section before the tracking separator.
            item.isNavigational = true
            return item
        case Item.documentMode:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document Mode"),
                systemImage: NotePresentationMode.livePreview.symbol,
                action: #selector(toggleDocumentMode(_:))
            )
            item.possibleLabels = Set(NotePresentationMode.allCases.map {
                ScholiumDocumentModeToolbarButtonPresentation(mode: $0)
                    .accessibilityLabel
            })
            return item
        case Item.settlement:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Settle"),
                systemImage: "bookmark",
                action: #selector(toggleSettlement(_:))
            )
            item.possibleLabels = [
                ScholiumL10n.string("Settle"),
                ScholiumL10n.string("Settled — Settle Again"),
                ScholiumL10n.string("Changed since settlement — Settle Again"),
                ScholiumL10n.string("Settlement Unavailable"),
            ]
            return item
        case Item.researchRecords:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Research Records"),
                systemImage: "text.book.closed",
                action: #selector(showResearchRecords(_:))
            )
        case Item.apparatusDivider:
            let splitView = splitViewController.splitView
            let item = NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 1
            )
            item.visibilityPriority = .user
            return item
        case Item.inspectorModes:
            return inspectorModeItem(identifier: itemIdentifier)
        case Item.inspector:
            let item = actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Research Inspector"),
                systemImage: "sidebar.trailing",
                action: #selector(toggleInspector(_:)),
                visibilityPriority: .user
            )
            item.possibleLabels = [
                ScholiumL10n.string("Hide Research Inspector"),
                ScholiumL10n.string("Show Research Inspector"),
            ]
            return item
        case .flexibleSpace, .space:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        default:
            return nil
        }
    }

    private func installToolbarItemsIfNeeded() {
        if toolbar.itemIdentifiers != Self.itemIdentifiers {
            toolbar.itemIdentifiers = Self.itemIdentifiers
        }
    }

    private func actionItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        systemImage: String,
        action: Selector,
        visibilityPriority: NSToolbarItem.VisibilityPriority = .high
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        configure(
            item,
            label: label,
            systemImage: systemImage,
            visibilityPriority: visibilityPriority
        )
        item.target = self
        item.action = action
        let overflowItem = NSMenuItem(
            title: label,
            action: action,
            keyEquivalent: ""
        )
        overflowItem.target = self
        overflowItem.image = item.image
        item.menuFormRepresentation = overflowItem
        return item
    }

    private func inspectorModeItem(
        identifier: NSToolbarItem.Identifier
    ) -> NSToolbarItem {
        let label = ScholiumL10n.dynamicString("Research Inspector")
        let modes = ResearchInspectorMode.allCases
        let control = NSSegmentedControl(
            images: modes.compactMap {
                ScholiumNativeToolbarPresentation.symbol(
                    named: $0.systemImage,
                    accessibilityDescription: ScholiumL10n.localized(
                        $0.interfaceTitleResource
                    )
                )
            },
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectInspectorMode(_:))
        )
        control.controlSize = ScholiumNativeToolbarPresentation.controlSize
        // Automatic lets AppKit select the current toolbar treatment, including
        // Liquid Glass, without changing the control's 70 x 20 fitting size.
        control.segmentStyle = .automatic
        control.setAccessibilityLabel(label)
        control.setAccessibilityIdentifier("scholium.inspectorMode")
        for (index, mode) in modes.enumerated() {
            control.setToolTip(
                ScholiumL10n.localized(mode.interfaceTitleResource),
                forSegment: index
            )
            control.setImageScaling(.scaleProportionallyDown, forSegment: index)
        }

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.title = ""
        item.toolTip = label
        item.visibilityPriority = .user
        item.isBordered = false
        item.style = .plain
        item.view = control
        item.menuFormRepresentation = inspectorModeMenu()
        return item
    }

    private func configure(
        _ item: NSToolbarItem,
        label: String,
        systemImage: String,
        visibilityPriority: NSToolbarItem.VisibilityPriority
    ) {
        item.label = label
        item.paletteLabel = label
        item.title = ""
        item.toolTip = label
        item.image = ScholiumNativeToolbarPresentation.symbol(
            named: systemImage,
            accessibilityDescription: label
        )
        item.visibilityPriority = visibilityPriority
        // With no custom view, AppKit creates the toolbar control and owns its
        // geometry, Glass, hover, press, focus, contrast, and transparency.
        item.isBordered = true
        item.style = .plain
    }

    private func observePresentation() {
        let changes: [AnyPublisher<Void, Never>] = [
            appState.commandObservation.$revision
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.researchController.$researchSnapshot
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.shellState.$inspector
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .map { _ in () }
                .eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes)
            .sink { [weak self] in self?.refreshPresentation() }
            .store(in: &presentationCancellables)
    }

    private func refreshPresentation() {
        let shellState = appState.shellState

        if let item = toolbarItem(Item.sidebar) {
            let visible = shellState.libraryVisible
            update(
                item,
                label: ScholiumL10n.dynamicString(
                    visible ? "Hide Sidebar" : "Show Sidebar"
                ),
                systemImage: "sidebar.leading",
                isEnabled: true,
                accessibilityValue: ScholiumL10n.dynamicString(
                    visible ? "Shown" : "Hidden"
                )
            )
        }

        if let item = toolbarItem(Item.back) {
            update(
                item,
                label: ScholiumL10n.dynamicString("Back"),
                systemImage: "arrow.left",
                isEnabled: appState.documentNavigationHistoryController.canGoBack
            )
        }
        if let item = toolbarItem(Item.forward) {
            update(
                item,
                label: ScholiumL10n.dynamicString("Forward"),
                systemImage: "arrow.right",
                isEnabled: appState.documentNavigationHistoryController.canGoForward
            )
        }

        if let item = toolbarItem(Item.documentInformation) {
            let hasDocument = appState.currentNote != nil
            item.isHidden = !hasDocument
            update(
                item,
                label: ScholiumL10n.dynamicString("Document Information"),
                systemImage: "info.circle",
                isEnabled: hasDocument
            )
            if hasDocument, documentInformationPopover.isShown {
                updateDocumentInformationPopoverContent()
            } else if !hasDocument {
                documentInformationPopover.close()
            }
        }

        if let item = toolbarItem(Item.documentMode) {
            let presentation = ScholiumDocumentModeToolbarButtonPresentation(
                mode: appState.documentController.chromeProjection.mode
            )
            item.isHidden = appState.currentNote == nil
            update(
                item,
                label: presentation.accessibilityLabel,
                systemImage: presentation.symbol,
                isEnabled: !currentEditorIsComposing
                    && (presentation.destination == .read || appState.canEditCurrentNote),
                toolTip: presentation.toolTip,
                accessibilityValue: presentation.mode.title
            )
        }

        if let item = toolbarItem(Item.settlement) {
            let hasDocument = appState.currentNote != nil
            let target = currentSettlementTarget
            let presentation =
                target == nil
                ? AboutSettlementPresentation.unavailable
                : currentSettlementPresentation
            let action = DocumentSettlementAction.resolve(presentation.state)
            let label = ScholiumL10n.localized(
                DocumentSettlementToolbarPresentation.accessibilityLabel(for: presentation.state)
            )
            let help = ScholiumL10n.localized(action.help)
            item.isHidden = !hasDocument
            item.label = label
            item.paletteLabel = label
            item.toolTip = help
            applySettlementSurface(
                for: presentation.state,
                to: item
            )
            item.image = settlementImage(
                for: presentation.state,
                accessibilityDescription: label
            )
            item.isEnabled = target != nil
            item.menuFormRepresentation?.title = ScholiumL10n.localized(action.title)
            item.menuFormRepresentation?.image = item.image
            item.menuFormRepresentation?.isEnabled = target != nil
            if !hasDocument || target == nil {
                settlementPopover.close()
            }
        }

        if let item = toolbarItem(Item.inspectorModes),
            let control = item.view as? NSSegmentedControl
        {
            let hasDocument = appState.documentController.selectedDocument != nil
            let isAvailable = shellState.inspector.isVisible && hasDocument
            item.isHidden = !isAvailable
            control.isEnabled = isAvailable
            control.selectedSegment =
                ResearchInspectorMode.allCases.firstIndex(
                    of: shellState.inspector.mode
                ) ?? 0
            control.setAccessibilityValue(
                ScholiumL10n.localized(
                    shellState.inspector.mode.interfaceTitleResource
                )
            )
            item.menuFormRepresentation = inspectorModeMenu()
        }

        if let item = toolbarItem(Item.inspector) {
            let visible = shellState.inspector.isVisible
            update(
                item,
                label: ScholiumL10n.dynamicString(
                    visible ? "Hide Research Inspector" : "Show Research Inspector"
                ),
                systemImage: "sidebar.trailing",
                isEnabled: visible || appState.documentController.selectedDocument != nil,
                accessibilityValue: ScholiumL10n.dynamicString(
                    visible ? "Shown" : "Hidden"
                )
            )
        }
    }

    private func update(
        _ item: NSToolbarItem,
        label: String,
        systemImage: String,
        isEnabled: Bool,
        toolTip: String? = nil,
        accessibilityValue: String? = nil
    ) {
        item.label = label
        item.paletteLabel = label
        item.title = ""
        item.toolTip = toolTip ?? label
        item.image = ScholiumNativeToolbarPresentation.symbol(
            named: systemImage,
            accessibilityDescription: accessibilityValue ?? label
        )
        item.isEnabled = isEnabled
        item.menuFormRepresentation?.title = label
        item.menuFormRepresentation?.image = item.image
        item.menuFormRepresentation?.isEnabled = isEnabled
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier == identifier }
    }

    func showDocumentInformation() {
        guard !documentInformationPopover.isShown else { return }
        presentDocumentInformation()
    }

    private func presentDocumentInformation() {
        guard appState.currentNote != nil,
            let item = toolbarItem(Item.documentInformation)
        else { return }
        settlementPopover.performClose(nil)
        updateDocumentInformationPopoverContent()
        responderBeforeDocumentInformation = window?.firstResponder
        documentInformationPopover.show(relativeTo: item)
        documentInformationHostingController?.focusForKeyboardDismissal()
    }

    private func updateDocumentInformationPopoverContent() {
        guard let note = appState.currentNote else { return }
        let documentID = DocumentInformationDocumentID(
            vaultID: note.vaultID,
            relativePath: note.relativePath
        )
        let headings = (note.workspaceSnapshot?.headings ?? []).map {
            DocumentOutlineEntry(
                level: $0.level,
                text: $0.text,
                sourceLine: $0.span.start.line
            )
        }
        let rootView = DocumentInformationPopoverView(
            projection: appState.documentInformation,
            documentID: documentID,
            headings: headings,
            openHeading: { [weak self] line in
                self?.openHeading(at: line)
            }
        )
        if let documentInformationHostingController {
            documentInformationHostingController.rootView = rootView
        } else {
            let hostingController = DocumentInformationHostingController(
                rootView: rootView
            )
            hostingController.sizingOptions = [
                .preferredContentSize,
                .intrinsicContentSize,
            ]
            hostingController.dismiss = { [weak self] in
                self?.documentInformationPopover.performClose(nil)
            }
            documentInformationHostingController = hostingController
            documentInformationPopover.contentViewController = hostingController
        }
    }

    private func inspectorModeMenu() -> NSMenuItem {
        let label = ScholiumL10n.dynamicString("Research Inspector")
        let root = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: label)
        for mode in ResearchInspectorMode.allCases {
            let item = NSMenuItem(
                title: ScholiumL10n.localized(mode.interfaceTitleResource),
                action: #selector(selectInspectorModeFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.image = ScholiumNativeToolbarPresentation.symbol(
                named: mode.systemImage
            )
            item.state = appState.shellState.inspector.mode == mode ? .on : .off
            menu.addItem(item)
        }
        root.submenu = menu
        return root
    }

    private var currentEditorIsComposing: Bool {
        guard let session = currentDocumentSession else { return false }
        return session.isEditing && session.editorSession.context?.composing == true
    }

    private var currentDocumentSession: DocumentSessionModel? {
        if let descriptor = appState.currentDocumentDescriptor {
            return appState.documentController.session(for: descriptor)
        }
        guard let note = appState.currentNote else { return nil }
        return appState.documentController.session(
            for: .unavailable(
                vaultID: note.vaultID,
                relativePath: note.relativePath
            )
        )
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        windowActions.setLibraryVisible(!appState.shellState.libraryVisible)
    }

    @objc private func goBack(_ sender: Any?) {
        appState.navigateDocumentHistory(.back)
    }

    @objc private func goForward(_ sender: Any?) {
        appState.navigateDocumentHistory(.forward)
    }

    @objc private func toggleDocumentInformation(_ sender: Any?) {
        if documentInformationPopover.isShown {
            documentInformationPopover.performClose(sender)
        } else {
            presentDocumentInformation()
        }
    }

    private func openHeading(at line: Int) {
        documentInformationPopover.performClose(nil)
        appState.pendingSourceLine = line
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closedPopover = notification.object as? NSPopover else { return }
        let responder: NSResponder?
        if closedPopover === documentInformationPopover {
            responder = responderBeforeDocumentInformation
            responderBeforeDocumentInformation = nil
        } else if closedPopover === settlementPopover {
            responder = responderBeforeSettlement
            responderBeforeSettlement = nil
        } else {
            return
        }
        guard let window, let responder else { return }
        if let view = responder as? NSView, view.window !== window { return }
        window.makeFirstResponder(responder)
    }

    @objc private func toggleDocumentMode(_ sender: Any?) {
        let presentation = ScholiumDocumentModeToolbarButtonPresentation(
            mode: appState.documentController.chromeProjection.mode
        )
        appState.requestDocumentMode(presentation.destination)
    }

    @objc private func showResearchRecords(_ sender: Any?) {
        windowActions.showResearchRecords()
    }

    @objc private func toggleSettlement(_ sender: Any?) {
        if settlementPopover.isShown {
            settlementPopover.performClose(sender)
        } else {
            presentSettlement()
        }
    }

    private func presentSettlement() {
        guard let target = currentSettlementTarget,
            let item = toolbarItem(Item.settlement)
        else { return }
        documentInformationPopover.performClose(nil)
        let presentation = currentSettlementPresentation
        let rootView = DocumentSettlementPopoverView(
            presentation: presentation,
            settle: { [weak self] rationale in
                guard let self else { return }
                _ = try await self.appState.researchController.settle(
                    target.note,
                    expectedRevision: target.fingerprint,
                    rationale: rationale
                )
                self.refreshPresentation()
                try await self.appState.researchController.refreshResearchProjection()
                self.refreshPresentation()
            },
            dismiss: { [weak self] in
                self?.settlementPopover.performClose(nil)
            }
        )
        let hostingController = DocumentSettlementPopoverHostingController(
            rootView: rootView
        )
        hostingController.sizingOptions = [
            .preferredContentSize,
            .intrinsicContentSize,
        ]
        hostingController.dismiss = { [weak self] in
            self?.settlementPopover.performClose(nil)
        }
        settlementPopoverHostingController = hostingController
        settlementPopover.contentViewController = hostingController
        responderBeforeSettlement = window?.firstResponder
        settlementPopover.show(relativeTo: item)
        hostingController.focusForKeyboardDismissal()
    }

    private var currentSettlementPresentation: AboutSettlementPresentation {
        let noteID = appState.currentNote?.workspaceSnapshot?.stableIdentity.resolvedID
        let requirement = appState.researchController.researchSnapshot?
            .settlementRequirements.first { $0.noteID == noteID }
        return AboutSettlementPresentation.resolve(
            noteID: noteID,
            currentRevision: appState.currentNote?.document.fingerprint,
            requirement: requirement,
            settlements: appState.researchController.researchSnapshot?.settlements ?? []
        )
    }

    private var currentSettlementTarget: DocumentSettlementTarget? {
        guard let note = appState.currentNote,
            let vaultID = appState.currentDocumentVaultID,
            note.workspaceSnapshot?.stableIdentity.resolvedID != nil,
            appState.currentDocumentVaultRole != .other
        else { return nil }
        return DocumentSettlementTarget(
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: note.relativePath
            ),
            fingerprint: note.document.fingerprint
        )
    }

    private func settlementImage(
        for state: AboutSettlementState,
        accessibilityDescription: String
    ) -> NSImage? {
        let symbol = DocumentSettlementToolbarPresentation.symbol(for: state)
        if let role = DocumentSettlementToolbarPresentation.symbolColorRole(
            for: state
        ) {
            return semanticSettlementSymbol(
                named: symbol,
                role: role,
                accessibilityDescription: accessibilityDescription
            )
        }
        return ScholiumNativeToolbarPresentation.symbol(
            named: symbol,
            accessibilityDescription: accessibilityDescription
        )
    }

    private func applySettlementSurface(
        for state: AboutSettlementState,
        to item: NSToolbarItem
    ) {
        item.style = DocumentSettlementToolbarPresentation.style(for: state)
        item.backgroundTintColor = nil
    }

    private func semanticSettlementSymbol(
        named name: String,
        role: ScholiumColorRole,
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        let base = NSImage.SymbolConfiguration(textStyle: .body, scale: .medium)
        // A one-color palette collapses the distinct layers of filled symbols
        // into a solid dot. Hierarchical rendering preserves the symbol's
        // internal figure while still resolving the state through one dynamic
        // semantic color.
        let semanticColor = NSImage.SymbolConfiguration(
            hierarchicalColor: role.nsColor
        )
        guard let configured = NSImage(
            systemSymbolName: name,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(base.applying(semanticColor)),
            let image = configured.copy() as? NSImage
        else { return nil }
        image.isTemplate = false
        return image
    }


    @objc private func toggleInspector(_ sender: Any?) {
        windowActions.setResearchInspectorVisible(!appState.shellState.inspector.isVisible)
    }

    @objc private func selectInspectorMode(_ sender: NSSegmentedControl) {
        guard
            ResearchInspectorMode.allCases.indices.contains(
                sender.selectedSegment
            )
        else {
            return
        }
        appState.researchController.selectInspectorMode(
            ResearchInspectorMode.allCases[sender.selectedSegment]
        )
        refreshPresentation()
    }

    @objc private func selectInspectorModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
            let mode = ResearchInspectorMode(rawValue: rawValue)
        else { return }
        appState.researchController.selectInspectorMode(mode)
        refreshPresentation()
    }
}

struct DocumentSettlementTarget: Hashable, Sendable {
    let note: VaultQualifiedNoteID
    let fingerprint: DocumentFingerprint
}

enum DocumentSettlementAction: Hashable {
    case settle
    case settleAgain
    case unavailable

    static func resolve(_ state: AboutSettlementState) -> Self {
        switch state {
        case .notYetSettled:
            .settle
        case .settled, .changedSinceSettlement:
            .settleAgain
        case .unavailable:
            .unavailable
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .settle:
            "Settle"
        case .settleAgain:
            "Settle Again"
        case .unavailable:
            "Settlement Unavailable"
        }
    }

    var help: LocalizedStringResource {
        switch self {
        case .settle:
            "Settle this note"
        case .settleAgain:
            "Settle this note again"
        case .unavailable:
            "Settlement is unavailable"
        }
    }
}

enum DocumentSettlementToolbarPresentation {
    static func symbol(for state: AboutSettlementState) -> String {
        switch state {
        case .settled:
            "bookmark.fill"
        case .notYetSettled, .unavailable:
            "bookmark"
        case .changedSinceSettlement:
            "bookmark.circle"
        }
    }

    static func style(for state: AboutSettlementState) -> NSToolbarItem.Style {
        .plain
    }

    static func symbolColorRole(
        for state: AboutSettlementState
    ) -> ScholiumColorRole? {
        switch state {
        case .changedSinceSettlement:
            .attention
        case .settled:
            .confirmed
        case .notYetSettled, .unavailable:
            nil
        }
    }

    static func accessibilityLabel(for state: AboutSettlementState) -> LocalizedStringResource {
        switch state {
        case .settled:
            "Settled — Settle Again"
        case .changedSinceSettlement:
            "Changed since settlement — Settle Again"
        case .notYetSettled:
            "Settle"
        case .unavailable:
            "Settlement Unavailable"
        }
    }
}

private struct DocumentSettlementPopoverView: View {
    let presentation: AboutSettlementPresentation
    let settle: (String?) async throws -> Void
    let dismiss: () -> Void

    @State private var rationale = ""
    @State private var errorMessage: String?
    @State private var isSettling = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Apparatus.sectionContentSpacing
        ) {
            Text(actionTitle)
                .font(ScholiumTypography.interface(.sectionTitle))
            Text("Record this saved revision as sufficiently stable for current research.")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Optional rationale", text: $rationale, axis: .vertical)
                .lineLimit(2...4)
            if let errorMessage {
                Text(errorMessage)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.attention)
            }
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button(actionTitle) {
                    isSettling = true
                    errorMessage = nil
                    Task {
                        do {
                            try await settle(rationale.nilIfBlank)
                            isSettling = false
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            isSettling = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSettling)
            }
        }
        .padding(ScholiumGrid.Spacing.sectionSeparation)
        .frame(width: 300)
    }

    private var actionTitle: LocalizedStringResource {
        DocumentSettlementAction.resolve(presentation.state).title
    }
}

@MainActor
private final class DocumentInformationHostingController:
    NSHostingController<DocumentInformationPopoverView>
{
    var dismiss: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func focusForKeyboardDismissal() {
        guard let window = view.window else { return }
        window.makeKey()
        window.makeFirstResponder(self)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss?()
    }
}

@MainActor
private final class DocumentSettlementPopoverHostingController:
    NSHostingController<DocumentSettlementPopoverView>
{
    var dismiss: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    func focusForKeyboardDismissal() {
        guard let window = view.window else { return }
        window.makeKey()
        window.makeFirstResponder(self)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss?()
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One semantic presentation recipe for native Liquid Glass toolbar symbols
/// and the remaining AppKit controls embedded in the window toolbar.
@MainActor
enum ScholiumNativeToolbarPresentation {
    static var controlSize: NSControl.ControlSize { .small }

    static func symbol(
        named name: String,
        accessibilityDescription: String? = nil
    ) -> NSImage? {
        NSImage(
            systemSymbolName: name,
            accessibilityDescription: accessibilityDescription
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                textStyle: .body,
                scale: .medium
            ))
    }
}

/// The toolbar reports the current Document mode with one stable icon button.
/// Activating it toggles Review/Edit; Source is only entered from the menu and
/// returns to Review on activation, matching Command-R.
struct ScholiumDocumentModeToolbarButtonPresentation: Equatable {
    let mode: NotePresentationMode
    let destination: NotePresentationMode

    init(mode: NotePresentationMode) {
        self.mode = mode
        destination =
            switch mode {
            case .read: .livePreview
            case .livePreview, .source: .read
            }
    }

    var symbol: String { mode.symbol }
    var toolTip: String { mode.title }
    var accessibilityLabel: String {
        String.localizedStringWithFormat(
            ScholiumL10n.string("Document Mode, %@"),
            mode.title
        )
    }
}
