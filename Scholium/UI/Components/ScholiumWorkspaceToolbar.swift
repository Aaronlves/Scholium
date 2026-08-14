import AppKit
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
        static let documentNavigationHistory = NSToolbarItem.Identifier(
            "scholium.toolbar.documentNavigationHistory"
        )
        static let inspector = NSToolbarItem.Identifier("scholium.toolbar.inspector")
        // These identifiers are structural bounds for the Document toolbar.
        static let libraryDivider = NSToolbarItem.Identifier.sidebarTrackingSeparator
        static let documentIdentity = NSToolbarItem.Identifier(
            "scholium.toolbar.documentIdentity"
        )
        static let documentCommands = NSToolbarItem.Identifier(
            "scholium.toolbar.documentCommands"
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
    }

    func install(in window: NSWindow) {
        guard splitViewController.splitView.window === window else { return }
        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unified
        installToolbarItemsIfNeeded()
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
            Item.documentNavigationHistory,
            Item.libraryDivider,
            Item.documentIdentity,
            Item.documentCommands,
            Item.apparatusDivider,
            Item.inspector,
        ]
    }

    static var itemIdentifiers: [NSToolbarItem.Identifier] {
        [
            Item.sidebar,
            Item.documentNavigationHistory,
            Item.libraryDivider,
            Item.documentIdentity,
            .flexibleSpace,
            Item.documentCommands,
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
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Sidebar"),
                view: ScholiumWorkspaceSidebarToolbarView(
                    shellState: appState.shellState,
                    windowActions: windowActions
                )
            )
        case Item.documentNavigationHistory:
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document History"),
                view: ScholiumWorkspaceDocumentNavigationToolbarView(
                    appState: appState,
                    historyController: appState.documentNavigationHistoryController
                )
            )
        case Item.libraryDivider:
            let splitView = splitViewController.splitView
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 0
            )
        case Item.documentIdentity:
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document"),
                view: ScholiumWorkspaceDocumentIdentityToolbarView(
                    appState: appState,
                    documentController: appState.documentController,
                    workspaceProjectionController: appState.workspaceProjectionController
                )
            )
        case .flexibleSpace:
            return NSToolbarItem(itemIdentifier: .flexibleSpace)
        case Item.documentCommands:
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document"),
                view: ScholiumWorkspaceDocumentCommandsToolbarView(
                    appState: appState,
                    documentController: appState.documentController,
                    workspaceProjectionController: appState.workspaceProjectionController,
                    researchController: appState.researchController,
                    windowActions: windowActions
                )
            )
        case Item.apparatusDivider:
            let splitView = splitViewController.splitView
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 1
            )
        case Item.inspector:
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Research Inspector"),
                view: ScholiumWorkspaceInspectorToolbarView(
                    shellState: appState.shellState,
                    documentController: appState.documentController,
                    windowActions: windowActions
                )
            )
        default:
            return nil
        }
    }

    private func installToolbarItemsIfNeeded() {
        if toolbar.itemIdentifiers != Self.itemIdentifiers {
            toolbar.itemIdentifiers = Self.itemIdentifiers
        }
    }

    private func hostedItem<Content: View>(
        identifier: NSToolbarItem.Identifier,
        label: String,
        visibilityPriority: NSToolbarItem.VisibilityPriority = .high,
        view: Content
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.visibilityPriority = visibilityPriority
        item.isBordered = false
        item.style = .plain
        let host = NSHostingView(
            rootView: ScholiumWorkspaceToolbarEnvironment(
                shellState: appState.shellState,
                content: view
            )
        )
        host.sizingOptions = [.intrinsicContentSize]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        item.view = host
        return item
    }
}

private struct ScholiumWorkspaceToolbarEnvironment<Content: View>: View {
    @ObservedObject var shellState: WindowShellState
    let content: Content

    var body: some View {
        content
            .preferredColorScheme(shellState.colorScheme.swiftUIColorScheme)
    }
}

/// One semantic presentation recipe for the native controls hosted inside the
/// workspace toolbar. AppKit's control size owns bezel geometry, while the
/// body text style and medium symbol scale preserve the original SwiftUI
/// toolbar content size instead of implicitly shrinking or enlarging it.
@MainActor
enum ScholiumNativeToolbarPresentation {
    static var controlSize: NSControl.ControlSize { .small }

    static var font: NSFont {
        .systemFont(ofSize: NSFont.systemFontSize)
    }

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

private struct ScholiumNativeToolbarMenuEntry {
    let title: String
    var systemImage: String? = nil
    var isSelected = false
    var isEnabled = true
    let action: () -> Void
}

/// A native toolbar pull-down. Its first menu item supplies the visible label;
/// AppKit owns the indicator, hover bezel, press feedback, focus ring, and menu
/// tracking instead of a SwiftUI label reconstructing those states.
private struct ScholiumNativeToolbarMenu: NSViewRepresentable {
    let title: String
    var systemImage: String? = nil
    let identifier: String
    var accessibilityValue: String? = nil
    var isEnabled = true
    let entries: [ScholiumNativeToolbarMenuEntry]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = ScholiumNativeToolbarPresentation.controlSize
        button.font = ScholiumNativeToolbarPresentation.font
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.imagePosition = systemImage == nil ? .noImage : .imageOnly
        update(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        update(button, coordinator: context.coordinator)
    }

    private func update(_ button: NSPopUpButton, coordinator: Coordinator) {
        coordinator.actions = entries.map(\.action)

        let menu = NSMenu()
        let labelItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        labelItem.image = systemImage.flatMap(
            ScholiumNativeToolbarPresentation.symbol(named:)
        )
        menu.addItem(labelItem)

        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(Coordinator.choose(_:)),
                keyEquivalent: ""
            )
            item.target = coordinator
            item.tag = index
            item.isEnabled = entry.isEnabled
            item.state = entry.isSelected ? .on : .off
            item.image = entry.systemImage.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }
            menu.addItem(item)
        }

        button.menu = menu
        button.selectItem(at: 0)
        button.imagePosition = systemImage == nil ? .noImage : .imageOnly
        button.toolTip = title
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(title)
        button.setAccessibilityValue(accessibilityValue)
        button.setAccessibilityIdentifier(identifier)
    }

    final class Coordinator: NSObject {
        var actions: [() -> Void] = []

        @objc func choose(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            actions[sender.tag]()
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

private struct ScholiumWorkspaceSidebarToolbarView: View {
    @ObservedObject var shellState: WindowShellState
    let windowActions: WorkspaceWindowActions

    var body: some View {
        ScholiumNativeToolbarButton(
            title: ScholiumL10n.dynamicString(
                shellState.libraryVisible ? "Hide Sidebar" : "Show Sidebar"
            ),
            systemImage: "sidebar.leading",
            identifier: "scholium.toggleSidebar",
            accessibilityValue: ScholiumL10n.dynamicString(
                shellState.libraryVisible ? "Shown" : "Hidden"
            )
        ) {
            windowActions.setLibraryVisible(!shellState.libraryVisible)
        }
    }
}

private struct ScholiumWorkspaceDocumentNavigationToolbarView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject var historyController: DocumentNavigationHistoryController

    var body: some View {
        HStack(spacing: 0) {
            ScholiumNativeToolbarButton(
                title: ScholiumL10n.dynamicString("Back"),
                systemImage: "arrow.left",
                identifier: "scholium.documentHistoryBack",
                isEnabled: historyController.canGoBack
            ) {
                appState.navigateDocumentHistory(.back)
            }

            ScholiumNativeToolbarButton(
                title: ScholiumL10n.dynamicString("Forward"),
                systemImage: "arrow.right",
                identifier: "scholium.documentHistoryForward",
                isEnabled: historyController.canGoForward
            ) {
                appState.navigateDocumentHistory(.forward)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.documentNavigationHistory")
    }
}

private struct ScholiumWorkspaceInspectorToolbarView: View {
    @ObservedObject var shellState: WindowShellState
    @ObservedObject var documentController: DocumentController
    let windowActions: WorkspaceWindowActions

    var body: some View {
        ScholiumNativeToolbarButton(
            title: ScholiumL10n.dynamicString(
                shellState.inspector.isVisible
                    ? "Hide Research Inspector"
                    : "Show Research Inspector"
            ),
            systemImage: "sidebar.trailing",
            identifier: "scholium.toggleInspector",
            accessibilityValue: ScholiumL10n.dynamicString(
                shellState.inspector.isVisible ? "Shown" : "Hidden"
            ),
            isEnabled: shellState.inspector.isVisible
                || documentController.selectedDocument != nil
        ) {
            // The window coordinator converts the explicit intent into the
            // exact split controller's native Inspector transition.
            windowActions.setResearchInspectorVisible(!shellState.inspector.isVisible)
        }
    }
}

private struct ScholiumWorkspaceDocumentIdentityToolbarView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject var documentController: DocumentController
    @ObservedObject var workspaceProjectionController: WindowWorkspaceProjectionController

    var body: some View {
        if let note = appState.currentNote {
            HStack(spacing: ScholiumMetrics.Workspace.headerControlSpacing) {
                headingOutline(for: note)

                Text(note.title ?? note.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .scholiumForeground(.secondaryText)
                    .help(note.title ?? note.displayName)
                    .accessibilityIdentifier("scholium.documentNoteName")
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scholium.documentToolbarIdentity")
        } else {
            ScholiumWorkspaceToolbarPlaceholder()
        }
    }

    private func headingOutline(for note: WindowDocumentLocation) -> some View {
        let headings = note.workspaceSnapshot?.headings ?? []
        let entries = headings.isEmpty
            ? [ScholiumNativeToolbarMenuEntry(
                title: ScholiumL10n.dynamicString("No Headings"),
                isEnabled: false,
                action: {}
            )]
            : headings.map { heading in
                ScholiumNativeToolbarMenuEntry(
                    title: String(
                        repeating: "  ",
                        count: max(0, heading.level - 1)
                    ) + heading.text,
                    action: {
                        appState.pendingSourceLine = heading.span.start.line
                    }
                )
            }
        return ScholiumNativeToolbarMenu(
            title: ScholiumL10n.dynamicString("Heading Outline"),
            systemImage: "list.bullet.indent",
            identifier: "scholium.headingOutline",
            entries: entries
        )
    }

}

private struct ScholiumWorkspaceDocumentCommandsToolbarView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject var documentController: DocumentController
    @ObservedObject var workspaceProjectionController: WindowWorkspaceProjectionController
    @ObservedObject var researchController: ResearchController
    let windowActions: WorkspaceWindowActions

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ScholiumWorkspaceSearchToolbarView(appState: appState)

            if appState.currentNote != nil {
                ScholiumWorkspaceDocumentModeToolbarView(
                    appState: appState,
                    documentController: documentController,
                    workspaceProjectionController: workspaceProjectionController
                )
            }

            ScholiumWorkspaceResearchRecordsToolbarView(
                appState: appState,
                researchController: researchController,
                windowActions: windowActions
            )
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.documentToolbarCommands")
    }
}

private struct ScholiumWorkspaceDocumentModeToolbarView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject var documentController: DocumentController
    @ObservedObject var workspaceProjectionController: WindowWorkspaceProjectionController

    var body: some View {
        let presentation = ScholiumDocumentModeToolbarButtonPresentation(
            mode: documentController.chromeProjection.mode
        )
        return ScholiumNativeToolbarButton(
            title: ScholiumL10n.dynamicString("Document Mode"),
            systemImage: presentation.symbol,
            identifier: "scholium.documentModeButton",
            toolTip: presentation.toolTip,
            accessibilityValue: presentation.mode.title,
            isEnabled: !currentEditorIsComposing
                && (presentation.destination == .read || appState.canEditCurrentNote)
        ) {
            appState.requestDocumentMode(presentation.destination)
        }
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
}

private struct ScholiumWorkspaceSearchToolbarView: View {
    @ObservedObject var appState: WindowModel

    var body: some View {
        ScholiumNativeToolbarButton(
            title: ScholiumL10n.dynamicString("Search"),
            systemImage: "magnifyingglass",
            identifier: "scholium.documentSearch"
        ) {
            appState.searchController.begin(.general)
        }
    }
}

private struct ScholiumWorkspaceResearchRecordsToolbarView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject var researchController: ResearchController
    let windowActions: WorkspaceWindowActions

    var body: some View {
        let presentation = ScholiumWorkspaceResearchRecordsToolbarState.resolve(
            hasTriptych: appState.workspaceAssignment != nil,
            hasCurrentNote: appState.currentNote != nil,
            currentNoteIsAvailable: currentNoteIsAvailable
        )
        ScholiumNativeToolbarButton(
            title: ScholiumL10n.dynamicString(presentation.title),
            systemImage: hasRecords(in: presentation.scope) ? "tray.full" : "tray",
            identifier: "scholium.showResearchRecords",
            isEnabled: presentation.isEnabled
        ) {
            switch presentation.scope {
            case .note:
                windowActions.showNoteResearchRecords()
            case .triptych:
                windowActions.showTriptychResearchRecords()
            }
        }
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
            return researchController.records?.finishedResearchRecords.contains { record in
                record.participatingNotes.contains { $0.noteID == noteID }
            } == true
        case .triptych:
            return researchController.records?.finishedResearchRecords.isEmpty == false
        }
    }
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

/// AppKit measures every custom toolbar item before a document is available.
/// Empty SwiftUI content has a zero intrinsic size, which makes NSToolbar emit
/// ambiguous-measurement warnings. This invisible point keeps measurement
/// well-defined without reserving a visible control or accessibility element.
private struct ScholiumWorkspaceToolbarPlaceholder: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: ScholiumMetrics.Accessibility.preferredCustomTarget)
            .accessibilityHidden(true)
    }
}
