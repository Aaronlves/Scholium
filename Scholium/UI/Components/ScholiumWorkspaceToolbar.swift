import AppKit
import Foundation
import ScholiumContracts
import SwiftUI

/// The configured window has one native toolbar. Tracking separators establish
/// Library, Document, and Apparatus sections. Sidebar and Inspector visibility
/// controls remain stable native-toolbar items; their labels and actions follow
/// the exact window's native-mirrored visibility without moving into pane content.
@MainActor
final class ScholiumWorkspaceToolbarController: NSObject, NSToolbarDelegate {
    static let toolbarIdentifier = NSToolbar.Identifier("scholium.workspaceToolbar")

    enum Item {
        static let sidebar = NSToolbarItem.Identifier("scholium.toolbar.sidebar")
        static let inspector = NSToolbarItem.Identifier("scholium.toolbar.inspector")
        // These identifiers are structural bounds for the Document toolbar.
        static let libraryDivider = NSToolbarItem.Identifier.sidebarTrackingSeparator
        static let documentIdentity = NSToolbarItem.Identifier(
            "scholium.toolbar.documentIdentity"
        )
        static let documentActions = NSToolbarItem.Identifier(
            "scholium.toolbar.documentActions"
        )
        static let apparatusDivider = NSToolbarItem.Identifier.inspectorTrackingSeparator
        static let researchRecord = NSToolbarItem.Identifier("scholium.toolbar.researchRecord")
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
            Item.libraryDivider,
            Item.documentIdentity,
            Item.documentActions,
            Item.researchRecord,
            Item.inspector,
            Item.apparatusDivider,
        ]
    }

    static var itemIdentifiers: [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            Item.libraryDivider,
            Item.sidebar,
            Item.documentIdentity,
            .flexibleSpace,
            Item.documentActions,
            Item.researchRecord,
            Item.inspector,
            Item.apparatusDivider,
            .flexibleSpace,
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
        case Item.documentActions:
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document Actions"),
                view: ScholiumWorkspaceDocumentActionsToolbarView(
                    appState: appState,
                    documentController: appState.documentController,
                    workspaceProjectionController: appState.workspaceProjectionController
                )
            )
        case Item.apparatusDivider:
            let splitView = splitViewController.splitView
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: 1
            )
        case Item.researchRecord:
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Research Record"),
                visibilityPriority: .user,
                view: ScholiumWorkspaceResearchRecordToolbarView(
                    appState: appState,
                    documentController: appState.documentController,
                    workspaceProjectionController: appState.workspaceProjectionController,
                    windowActions: windowActions
                )
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
            .tint(ScholiumColorRole.accent.color)
            .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch shellState.colorScheme {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

private struct ScholiumWorkspaceSidebarToolbarView: View {
    @ObservedObject var shellState: WindowShellState
    let windowActions: WorkspaceWindowActions

    var body: some View {
        ScholiumInkIconControl(
            title: ScholiumL10n.dynamicString(
                shellState.libraryVisible ? "Hide Sidebar" : "Show Sidebar"
            ),
            systemImage: "sidebar.leading",
            identifier: "scholium.toggleSidebar",
            isActive: shellState.libraryVisible
        ) {
            windowActions.setLibraryVisible(!shellState.libraryVisible)
        }
        .accessibilityValue(ScholiumL10n.dynamicString(
            shellState.libraryVisible ? "Shown" : "Hidden"
        ))
    }
}

private struct ScholiumWorkspaceInspectorToolbarView: View {
    @ObservedObject var shellState: WindowShellState
    @ObservedObject var documentController: DocumentController
    let windowActions: WorkspaceWindowActions

    var body: some View {
        ScholiumInkIconControl(
            title: ScholiumL10n.dynamicString(
                shellState.inspector.isVisible
                    ? "Hide Research Inspector"
                    : "Show Research Inspector"
            ),
            systemImage: "sidebar.trailing",
            identifier: "scholium.toggleInspector",
            isActive: shellState.inspector.isVisible
        ) {
            // The window coordinator converts the explicit intent into the
            // exact split controller's native Inspector transition.
            windowActions.setResearchInspectorVisible(!shellState.inspector.isVisible)
        }
        .disabled(
            !shellState.inspector.isVisible
                && documentController.selectedDocument == nil
        )
        .accessibilityValue(ScholiumL10n.dynamicString(
            shellState.inspector.isVisible ? "Shown" : "Hidden"
        ))
    }
}

private struct ScholiumWorkspaceDocumentIdentityToolbarView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject var documentController: DocumentController
    @ObservedObject var workspaceProjectionController: WindowWorkspaceProjectionController

    var body: some View {
        if let note = appState.currentNote {
            HStack(spacing: ScholiumMetrics.Workspace.headerControlSpacing) {
                Menu {
                    let headings = note.workspaceSnapshot?.headings ?? []
                    if headings.isEmpty {
                        Text("No Headings")
                    } else {
                        ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                            Button {
                                appState.pendingSourceLine = heading.span.start.line
                            } label: {
                                Text(
                                    String(
                                        repeating: "  ",
                                        count: max(0, heading.level - 1)
                                    ) + heading.text
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .frame(
                            width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                            height: ScholiumMetrics.Accessibility.preferredCustomTarget
                        )
                        .contentShape(Rectangle())
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Heading Outline")
                .accessibilityLabel("Heading Outline")
                .accessibilityIdentifier("scholium.headingOutline")

                Text(note.title ?? note.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(ScholiumInterfaceTypography.workspaceToolbarIdentity)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
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

}

private struct ScholiumWorkspaceDocumentActionsToolbarView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject var documentController: DocumentController
    @ObservedObject var workspaceProjectionController: WindowWorkspaceProjectionController

    var body: some View {
        if let note = appState.currentNote {
            HStack(spacing: ScholiumMetrics.Workspace.headerControlSpacing) {
                documentModeToolbar(for: note)

                ScholiumInkIconControl(
                    title: ScholiumL10n.dynamicString("Search"),
                    systemImage: "magnifyingglass",
                    identifier: "scholium.documentSearch"
                ) {
                    appState.searchController.begin(.general)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scholium.documentToolbarActions")
        } else {
            ScholiumWorkspaceToolbarPlaceholder()
        }
    }

    private func documentModeToolbar(for note: WindowDocumentLocation) -> some View {
        let mode = appState.presentationMode(for: note.relativePath)
        return Menu {
            ForEach(NotePresentationMode.allCases) { candidate in
                Button {
                    appState.requestPresentationMode = candidate
                } label: {
                    if candidate == mode {
                        Label(candidate.title, systemImage: "checkmark")
                    } else {
                        Label(candidate.title, systemImage: candidate.symbol)
                    }
                }
            }
        } label: {
            Text(mode.title)
                .font(.body)
                .foregroundStyle(ScholiumColorRole.primaryText.color)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!appState.canEditCurrentNote || currentEditorIsComposing)
        .help("Document mode: \(mode.title)")
        .accessibilityLabel("Document mode")
        .accessibilityValue(mode.title)
        .accessibilityIdentifier("scholium.documentModeMenu")
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
            for: .unavailable(relativePath: note.relativePath)
        )
    }
}

private struct ScholiumWorkspaceResearchRecordToolbarView: View {
    @ObservedObject var appState: WindowModel
    @ObservedObject var documentController: DocumentController
    @ObservedObject var workspaceProjectionController: WindowWorkspaceProjectionController
    let windowActions: WorkspaceWindowActions

    var body: some View {
        ScholiumInkIconControl(
            title: ScholiumL10n.dynamicString("Show Research Record"),
            systemImage: "clock.arrow.circlepath",
            identifier: "scholium.showResearchRecord"
        ) {
            windowActions.showResearchRecord()
        }
        .disabled(!isAvailable)
    }

    private var isAvailable: Bool {
        guard let note = appState.currentNote else { return false }
        return appState.documentController.editingDocumentPath == nil
            && appState.currentDocumentIdentityByPath[note.relativePath] != nil
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
