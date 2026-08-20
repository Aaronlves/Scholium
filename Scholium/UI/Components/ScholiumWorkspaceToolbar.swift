import AppKit
import Combine
import Foundation
import ScholiumContracts
import SwiftUI

/// The configured window has one native toolbar. Tracking separators establish
/// Library, Document, and Apparatus sections. Sidebar and document-history
/// controls remain leading of the Library boundary, while Inspector remains
/// trailing of the Apparatus boundary; collapsing either pane changes no item
/// topology.
@MainActor
final class ScholiumWorkspaceToolbarController: NSObject, NSToolbarDelegate {
    static let toolbarIdentifier = NSToolbar.Identifier("scholium.workspaceToolbar")

    enum Item {
        static let sidebar = NSToolbarItem.Identifier("scholium.toolbar.sidebar")
        static let back = NSToolbarItem.Identifier("scholium.toolbar.back")
        static let forward = NSToolbarItem.Identifier("scholium.toolbar.forward")
        static let inspector = NSToolbarItem.Identifier("scholium.toolbar.inspector")
        // These identifiers are structural bounds for the Document toolbar.
        static let libraryDivider = NSToolbarItem.Identifier.sidebarTrackingSeparator
        static let headingOutline = NSToolbarItem.Identifier(
            "scholium.toolbar.headingOutline"
        )
        static let search = NSToolbarItem.Identifier("scholium.toolbar.search")
        static let documentMode = NSToolbarItem.Identifier(
            "scholium.toolbar.documentMode"
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
        super.init()
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        observePresentation()
    }

    func install(in window: NSWindow) {
        guard splitViewController.splitView.window === window else { return }
        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
        installToolbarItemsIfNeeded()
        refreshPresentation()
    }

    func controls(_ candidate: NSSplitViewController) -> Bool {
        splitViewController === candidate
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
            Item.headingOutline,
            Item.search,
            Item.documentMode,
            Item.researchRecords,
            Item.apparatusDivider,
            Item.inspector,
        ]
    }

    static var itemIdentifiers: [NSToolbarItem.Identifier] {
        [
            Item.sidebar,
            Item.back,
            Item.forward,
            Item.libraryDivider,
            Item.headingOutline,
            .flexibleSpace,
            Item.search,
            Item.documentMode,
            Item.researchRecords,
            Item.apparatusDivider,
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
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Sidebar"),
                systemImage: "sidebar.leading",
                action: #selector(toggleSidebar(_:)),
                visibilityPriority: .user,
                isNavigational: true
            )
        case Item.back:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Back"),
                systemImage: "arrow.left",
                action: #selector(goBack(_:)),
                isNavigational: true
            )
        case Item.forward:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Forward"),
                systemImage: "arrow.right",
                action: #selector(goForward(_:)),
                isNavigational: true
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
        case Item.headingOutline:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            configure(
                item,
                label: ScholiumL10n.string("Heading Outline"),
                systemImage: "list.bullet.indent",
                visibilityPriority: .high
            )
            // The outline is an icon command in the window toolbar. Its
            // semantic label remains available to accessibility, help, and
            // the native overflow menu without reserving title width beside
            // the document's system-owned window title.
            item.title = ""
            item.showsIndicator = true
            return item
        case Item.search:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Search"),
                systemImage: "magnifyingglass",
                action: #selector(showSearch(_:))
            )
        case Item.documentMode:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document Mode"),
                systemImage: NotePresentationMode.livePreview.symbol,
                action: #selector(toggleDocumentMode(_:))
            )
        case Item.researchRecords:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Triptych Records"),
                systemImage: "tray",
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
        case Item.inspector:
            return actionItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Research Inspector"),
                systemImage: "sidebar.trailing",
                action: #selector(toggleInspector(_:)),
                visibilityPriority: .user
            )
        case .flexibleSpace:
            return NSToolbarItem(itemIdentifier: .flexibleSpace)
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
        visibilityPriority: NSToolbarItem.VisibilityPriority = .high,
        isNavigational: Bool = false
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
        item.autovalidates = false
        item.isNavigational = isNavigational
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

    private func configure(
        _ item: NSToolbarItem,
        label: String,
        systemImage: String,
        visibilityPriority: NSToolbarItem.VisibilityPriority
    ) {
        item.label = label
        item.paletteLabel = label
        item.title = label
        item.toolTip = label
        item.image = ScholiumNativeToolbarPresentation.symbol(named: systemImage)
        item.visibilityPriority = visibilityPriority
        item.isBordered = false
        item.style = .plain
    }

    private func observePresentation() {
        let changes: [AnyPublisher<Void, Never>] = [
            appState.commandObservation.$revision
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.researchController.$records
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

        if let item = toolbarItem(Item.headingOutline) as? NSMenuToolbarItem {
            item.isHidden = appState.currentNote == nil
            item.menu = headingMenu()
        }

        if let item = toolbarItem(Item.search) {
            update(
                item,
                label: ScholiumL10n.dynamicString("Search"),
                systemImage: "magnifyingglass",
                isEnabled: true
            )
        }

        if let item = toolbarItem(Item.documentMode) {
            let presentation = ScholiumDocumentModeToolbarButtonPresentation(
                mode: appState.documentController.chromeProjection.mode
            )
            item.isHidden = appState.currentNote == nil
            update(
                item,
                label: ScholiumL10n.dynamicString("Document Mode"),
                systemImage: presentation.symbol,
                isEnabled: !currentEditorIsComposing
                    && (presentation.destination == .read || appState.canEditCurrentNote),
                toolTip: presentation.toolTip,
                accessibilityValue: presentation.mode.title
            )
        }

        if let item = toolbarItem(Item.researchRecords) {
            let presentation = ScholiumWorkspaceResearchRecordsToolbarState.resolve(
                hasTriptych: appState.workspaceAssignment != nil,
                hasCurrentNote: appState.currentNote != nil,
                currentNoteIsAvailable: currentNoteIsAvailable
            )
            update(
                item,
                label: ScholiumL10n.dynamicString(presentation.title),
                systemImage: hasRecords(in: presentation.scope) ? "tray.full" : "tray",
                isEnabled: presentation.isEnabled
            )
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
        item.title = accessibilityValue.map { "\(label): \($0)" } ?? label
        item.toolTip = toolTip ?? label
        item.image = ScholiumNativeToolbarPresentation.symbol(named: systemImage)
        item.isEnabled = isEnabled
        item.menuFormRepresentation?.title = label
        item.menuFormRepresentation?.image = item.image
        item.menuFormRepresentation?.isEnabled = isEnabled
    }

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier == identifier }
    }

    private func headingMenu() -> NSMenu {
        let menu = NSMenu(title: ScholiumL10n.dynamicString("Heading Outline"))
        menu.autoenablesItems = false
        let headings = appState.currentNote?.workspaceSnapshot?.headings ?? []
        if headings.isEmpty {
            let item = NSMenuItem(
                title: ScholiumL10n.dynamicString("No Headings"),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
            return menu
        }
        for heading in headings {
            let item = NSMenuItem(
                title: String(repeating: "  ", count: max(0, heading.level - 1))
                    + heading.text,
                action: #selector(openHeading(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = heading.span.start.line
            menu.addItem(item)
        }
        return menu
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

    private var currentNoteIsAvailable: Bool {
        guard let note = appState.currentNote else { return false }
        return appState.currentDocumentIdentityByPath[note.relativePath] != nil
    }

    private func hasRecords(
        in scope: ScholiumWorkspaceResearchRecordsToolbarState.Scope
    ) -> Bool {
        switch scope {
        case .note:
            guard let noteID = appState.currentNote?.workspaceSnapshot?
                .stableIdentity.resolvedID else { return false }
            return appState.researchController.records?.finishedResearchRecords.contains {
                record in
                record.participatingNotes.contains { $0.noteID == noteID }
            } == true
        case .triptych:
            return appState.researchController.records?
                .finishedResearchRecords.isEmpty == false
        }
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

    @objc private func openHeading(_ sender: NSMenuItem) {
        guard let line = sender.representedObject as? Int else { return }
        appState.pendingSourceLine = line
    }

    @objc private func showSearch(_ sender: Any?) {
        appState.searchController.begin(.general)
    }

    @objc private func toggleDocumentMode(_ sender: Any?) {
        let presentation = ScholiumDocumentModeToolbarButtonPresentation(
            mode: appState.documentController.chromeProjection.mode
        )
        appState.requestDocumentMode(presentation.destination)
    }

    @objc private func showResearchRecords(_ sender: Any?) {
        let presentation = ScholiumWorkspaceResearchRecordsToolbarState.resolve(
            hasTriptych: appState.workspaceAssignment != nil,
            hasCurrentNote: appState.currentNote != nil,
            currentNoteIsAvailable: currentNoteIsAvailable
        )
        switch presentation.scope {
        case .note:
            windowActions.showNoteResearchRecords()
        case .triptych:
            windowActions.showTriptychResearchRecords()
        }
    }

    @objc private func toggleInspector(_ sender: Any?) {
        windowActions.setResearchInspectorVisible(!appState.shellState.inspector.isVisible)
    }
}

/// One semantic presentation recipe for native toolbar symbols and the
/// remaining AppKit controls embedded in secondary surfaces.
@MainActor
enum ScholiumNativeToolbarPresentation {
    static var controlSize: NSControl.ControlSize { .small }

    static func symbol(named name: String) -> NSImage? {
        NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            textStyle: .body,
            scale: .medium
        ))
    }
}

/// Native toolbar buttons retain AppKit's pointer, press, keyboard-focus, and
/// disabled rendering. SwiftUI remains only the observation bridge that keeps
/// the exact window's command state current inside the hosted toolbar item.
struct ScholiumNativeToolbarButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    let identifier: String
    var toolTip: String? = nil
    var accessibilityValue: String? = nil
    var isEnabled = true
    var keyEquivalent: String? = nil
    var keyEquivalentModifierMask: NSEvent.ModifierFlags = []
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: .zero)
        button.target = context.coordinator
        button.action = #selector(Coordinator.activate(_:))
        button.setButtonType(.momentaryPushIn)
        button.controlSize = ScholiumNativeToolbarPresentation.controlSize
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        update(button)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        update(button)
    }

    private func update(_ button: NSButton) {
        button.image = ScholiumNativeToolbarPresentation.symbol(named: systemImage)
        button.title = ""
        button.toolTip = toolTip ?? title
        button.isEnabled = isEnabled
        button.keyEquivalent = keyEquivalent ?? ""
        button.keyEquivalentModifierMask = keyEquivalentModifierMask
        button.setAccessibilityLabel(title)
        button.setAccessibilityValue(accessibilityValue)
        button.setAccessibilityIdentifier(identifier)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func activate(_ sender: NSButton) {
            action()
        }
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
        destination = switch mode {
        case .read: .livePreview
        case .livePreview, .source: .read
        }
    }

    var symbol: String { mode.symbol }
    var toolTip: String { mode.title }
}

struct ScholiumWorkspaceResearchRecordsToolbarState: Equatable {
    enum Scope: Equatable {
        case note
        case triptych
    }

    let scope: Scope
    let title: String
    let isEnabled: Bool

    static func resolve(
        hasTriptych: Bool,
        hasCurrentNote: Bool,
        currentNoteIsAvailable: Bool
    ) -> Self {
        if !hasCurrentNote {
            return Self(
                scope: .triptych,
                title: "Triptych Records",
                isEnabled: hasTriptych
            )
        }
        return Self(
            scope: .note,
            title: "This Note Records",
            isEnabled: hasTriptych && currentNoteIsAvailable
        )
    }
}
