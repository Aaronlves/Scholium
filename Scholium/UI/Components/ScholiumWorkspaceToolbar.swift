import AppKit
import Combine
import Foundation
import ScholiumContracts
import SwiftUI

/// The configured window has one native toolbar. Tracking separators establish
/// Library, Document, and Apparatus sections, allowing each peripheral's one
/// control to remain in the native hit-testing layer while it moves between its
/// visible pane section (Hide) and the Document section (Show).
@MainActor
final class ScholiumWorkspaceToolbarController: NSObject, NSToolbarDelegate {
    static let toolbarIdentifier = NSToolbar.Identifier("scholium.workspaceToolbar")

    enum Item {
        static let sidebar = NSToolbarItem.Identifier("scholium.toolbar.sidebar")
        static let inspector = NSToolbarItem.Identifier("scholium.toolbar.inspector")
        // These identifiers are structural bounds for the Document toolbar.
        // They do not make either peripheral pane a semantic toolbar owner.
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
    private var appStateObservation: AnyCancellable?

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
        appStateObservation = Publishers.Merge(
            appState.objectWillChange,
            appState.documentController.objectWillChange
        )
        .sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.reconcileToolbarOwnership()
            }
        }
    }

    func install(in window: NSWindow) {
        guard splitViewController.splitView.window === window else { return }
        if window.toolbar !== toolbar {
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unified
        reconcileToolbarOwnership()
    }

    func controls(_ candidate: NSSplitViewController) -> Bool {
        splitViewController === candidate
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        desiredItemIdentifiers
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

    private var desiredItemIdentifiers: [NSToolbarItem.Identifier] {
        Self.itemIdentifiers(
            sidebarVisible: appState.sidebarVisible,
            researchInspectorVisible: appState.researchInspectorVisible
        )
    }

    static func itemIdentifiers(
        sidebarVisible: Bool,
        researchInspectorVisible: Bool
    ) -> [NSToolbarItem.Identifier] {
        var identifiers: [NSToolbarItem.Identifier] = [.flexibleSpace]
        if sidebarVisible {
            identifiers.append(Item.sidebar)
        }
        identifiers.append(Item.libraryDivider)
        if !sidebarVisible {
            identifiers.append(Item.sidebar)
        }
        identifiers.append(contentsOf: [
            Item.documentIdentity,
            .flexibleSpace,
            Item.documentActions,
            Item.researchRecord,
        ])
        if !researchInspectorVisible {
            identifiers.append(Item.inspector)
        }
        identifiers.append(Item.apparatusDivider)
        if researchInspectorVisible {
            identifiers.append(Item.inspector)
        }
        identifiers.append(.flexibleSpace)
        return identifiers
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
                    appState: appState,
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
                view: ScholiumWorkspaceDocumentIdentityToolbarView(appState: appState)
            )
        case .flexibleSpace:
            return NSToolbarItem(itemIdentifier: .flexibleSpace)
        case Item.documentActions:
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Document Actions"),
                view: ScholiumWorkspaceDocumentActionsToolbarView(appState: appState)
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
                    windowActions: windowActions
                )
            )
        case Item.inspector:
            return hostedItem(
                identifier: itemIdentifier,
                label: ScholiumL10n.string("Research Inspector"),
                view: ScholiumWorkspaceInspectorToolbarView(
                    appState: appState,
                    windowActions: windowActions
                )
            )
        default:
            return nil
        }
    }

    private func reconcileToolbarOwnership() {
        let desired = desiredItemIdentifiers
        if toolbar.itemIdentifiers != desired {
            // `itemIdentifiers` diffs the live toolbar. This preserves retained
            // Document items while the reveal control crosses a split boundary.
            toolbar.itemIdentifiers = desired
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
                appState: appState,
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
    @ObservedObject var appState: WindowModel
    let content: Content

    var body: some View {
        content
            .tint(ScholiumColorRole.accent.color)
            .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch appState.colorScheme {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

private struct ScholiumWorkspaceSidebarToolbarView: View {
    @ObservedObject var appState: WindowModel
    let windowActions: WorkspaceWindowActions

    var body: some View {
        let isVisible = appState.sidebarVisible
        let title = ScholiumL10n.dynamicString(
            isVisible ? "Hide Sidebar" : "Show Sidebar"
        )
        ScholiumInkIconControl(
            title: title,
            systemImage: "sidebar.leading",
            identifier: "scholium.toggleSidebar",
            isActive: isVisible
        ) {
            windowActions.setLibraryVisible(!isVisible)
        }
        .accessibilityValue(
            ScholiumL10n.dynamicString(isVisible ? "Shown" : "Hidden")
        )
    }
}

private struct ScholiumWorkspaceInspectorToolbarView: View {
    @ObservedObject var appState: WindowModel
    let windowActions: WorkspaceWindowActions

    var body: some View {
        let isVisible = appState.researchInspectorVisible
        ScholiumInkIconControl(
            title: ScholiumL10n.dynamicString(
                isVisible ? "Hide Research Inspector" : "Show Research Inspector"
            ),
            systemImage: "sidebar.trailing",
            identifier: "scholium.toggleInspector",
            isActive: isVisible
        ) {
            // The window coordinator converts the explicit intent into the
            // exact split controller's native Inspector transition.
            windowActions.setResearchInspectorVisible(!isVisible)
        }
        .disabled(
            !isVisible && appState.documentController.selectedDocument == nil
        )
        .accessibilityValue(
            ScholiumL10n.dynamicString(isVisible ? "Shown" : "Hidden")
        )
    }
}

private struct ScholiumWorkspaceDocumentIdentityToolbarView: View {
    @ObservedObject var appState: WindowModel

    var body: some View {
        if let note = appState.currentNote {
            HStack(spacing: ScholiumMetrics.Workspace.headerControlSpacing) {
                Menu {
                    let headings = documentHeadings(for: note)
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

    private func documentHeadings(for note: WindowDocumentLocation) -> [HeadingNode] {
        MarkdownSemanticDocument(
            parsing: NoteDocument(
                relativePath: note.relativePath,
                rawContent: note.rawContent
            )
        ).headings
    }
}

private struct ScholiumWorkspaceDocumentActionsToolbarView: View {
    @ObservedObject var appState: WindowModel

    var body: some View {
        if let note = appState.currentNote {
            HStack(spacing: ScholiumMetrics.Workspace.headerControlSpacing) {
                documentModeToolbar(for: note)

                ScholiumInkIconControl(
                    title: ScholiumL10n.dynamicString("Search"),
                    systemImage: "magnifyingglass",
                    identifier: "scholium.documentSearch"
                ) {
                    appState.beginSearch(.general)
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
