import Foundation
import ScholiumContracts
import SwiftUI

// MARK: - Tree rows

func sidebarLifecyclePutBackControlIsVisible(
    isHovered: Bool,
    isNativeFocused: Bool
) -> Bool {
    isHovered || isNativeFocused
}

enum SidebarNoteCommandSurface: Equatable {
    case contextMenu
    case accessibility
}

enum SidebarNoteCommand: String, Hashable, Identifiable {
    case openInNewTab
    case duplicate
    case rename
    case move
    case setAside
    case moveToTrash
    case putBack
    case deletePermanently
    case copyRelativePath
    case revealInFinder

    var id: String { rawValue }

    var requiresLifecycleTarget: Bool {
        switch self {
        case .openInNewTab, .copyRelativePath, .revealInFinder:
            false
        case .duplicate, .rename, .move, .setAside, .moveToTrash,
             .putBack, .deletePermanently:
            true
        }
    }

    var contextMenuTitle: LocalizedStringKey {
        switch self {
        case .openInNewTab: "Open in New Tab"
        case .duplicate: "Duplicate…"
        case .rename: "Rename…"
        case .move: "Move Note…"
        case .setAside: "Set Aside…"
        case .moveToTrash: "Move to Trash…"
        case .putBack: "Put Back"
        case .deletePermanently: "Delete Permanently…"
        case .copyRelativePath: "Copy Relative Path"
        case .revealInFinder: "Reveal in Finder"
        }
    }

    var accessibilityTitle: LocalizedStringKey {
        switch self {
        case .openInNewTab: "Open in New Tab"
        case .duplicate: "Duplicate Note"
        case .rename: "Rename Note"
        case .move: "Move Note"
        case .setAside: "Set Aside"
        case .moveToTrash: "Move to Trash"
        case .putBack: "Put Back"
        case .deletePermanently: "Delete Permanently"
        case .copyRelativePath: "Copy Relative Path"
        case .revealInFinder: "Reveal in Finder"
        }
    }

    var role: ButtonRole? {
        self == .deletePermanently ? .destructive : nil
    }
}

struct SidebarNoteCommandGroup: Hashable, Identifiable {
    enum Kind: String, Hashable {
        case opening
        case editing
        case lifecycle
        case location
    }

    let kind: Kind
    let commands: [SidebarNoteCommand]

    var id: Kind { kind }
}

func sidebarNoteCommandGroups(
    locationScope: NoteLocationScope,
    isManagedCritique: Bool,
    surface: SidebarNoteCommandSurface
) -> [SidebarNoteCommandGroup] {
    var groups = [SidebarNoteCommandGroup(
        kind: .opening,
        commands: [.openInNewTab]
    )]

    switch locationScope {
    case .workspace:
        var editing: [SidebarNoteCommand] = []
        if !isManagedCritique { editing.append(.duplicate) }
        editing.append(.rename)
        if surface == .accessibility { editing.append(.move) }
        groups.append(SidebarNoteCommandGroup(
            kind: .editing,
            commands: editing
        ))
        groups.append(SidebarNoteCommandGroup(
            kind: .lifecycle,
            commands: [.setAside, .moveToTrash]
        ))
    case .setAside:
        groups.append(SidebarNoteCommandGroup(
            kind: .lifecycle,
            commands: [.putBack, .moveToTrash]
        ))
    case .trash:
        groups.append(SidebarNoteCommandGroup(
            kind: .lifecycle,
            commands: [.putBack, .deletePermanently]
        ))
    }

    groups.append(SidebarNoteCommandGroup(
        kind: .location,
        commands: [.copyRelativePath, .revealInFinder]
    ))
    return groups
}

struct SidebarTreeContext {
    let currentVaultID: UUID?
    let currentVaultRole: VaultRole
    let locationScope: NoteLocationScope
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
    let requestLifecycle: (NoteLifecycleRequest) -> Void
    let canMutateLibrary: Bool
    let createUntitledNote: (String?) -> Void
    let createUntitledFolder: (String?) -> Void
    let requestFolderLifecycle: (FolderLifecycleRequest) -> Void
    let moveFolderToTrash: (FolderLifecycleTarget) async throws -> Void
    let copyRelativePath: (String) -> Void
    let revealNote: (String) -> Void
    let setAside: (NoteLifecycleTarget) async throws -> Void
    let moveToTrash: (NoteLifecycleTarget) async throws -> Void
    let deletePermanently: (NoteLifecycleTarget) async throws -> Void
    let showError: (String) -> Void
}

struct SidebarTreeNodeRow: View {
    let node: TreeNode
    @Binding var expandedFolders: Set<String>
    let selectedDocumentPath: String?
    let context: SidebarTreeContext
    let onSelect: (WindowDocumentLocation) -> Void
    let onPutBack: (WindowDocumentLocation) -> Void
    let onWillRemove: (WindowDocumentLocation) -> Void
    let onMutationFailed: (WindowDocumentLocation) -> Void

    @State private var pendingDestructiveAction: DestructiveAction?
    @State private var pendingFolderTrashTarget: FolderLifecycleTarget?

    private enum DestructiveAction: String, Identifiable {
        case setAside = "Set Aside"
        case trash = "Move to Trash"
        case delete = "Delete Permanently"
        var id: String { rawValue }
    }

    private var isExpanded: Bool { expandedFolders.contains(node.id) }

    var body: some View {
        Group {
            if node.isFolder { folderRow }
            else if let note = node.note { noteRow(note) }
        }
        .id(node.id)
    }

    private var folderRow: some View {
        Button(action: toggleFolder) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if node.children.isEmpty {
                    Image(systemName: "folder")
                        .font(ScholiumTypography.interface(.small, emphasis: .medium))
                        .scholiumForeground(.secondaryText)
                        .frame(width: ScholiumMetrics.Library.leadingSlotWidth)
                        .accessibilityHidden(true)
                } else {
                    Color.clear
                        .frame(width: ScholiumMetrics.Library.leadingSlotWidth)
                        .accessibilityHidden(true)
                }

                Text(node.name)
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, rowLeadingInset)
            .padding(.trailing, ScholiumMetrics.Library.rowHorizontalInset)
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.Library.hierarchyRowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                tracksHover: false,
                in: Rectangle()
            )
        )
        .help(node.name)
        .accessibilityLabel(node.name)
        .accessibilityValue(node.children.isEmpty ? "Empty folder" : isExpanded ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("scholium.folderRow.\(node.id)")
        .contextMenu { folderContextMenu }
        .accessibilityActions { folderAccessibilityActions }
        .confirmationDialog(
            "Move Folder to Trash?",
            isPresented: Binding(
                get: { pendingFolderTrashTarget != nil },
                set: { if !$0 { pendingFolderTrashTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move Folder and Notes to Trash", role: .destructive) {
                guard let target = pendingFolderTrashTarget else { return }
                pendingFolderTrashTarget = nil
                performFolderTrash(target)
            }
            Button("Cancel", role: .cancel) { pendingFolderTrashTarget = nil }
        }
    }

    private func noteRow(_ note: WindowDocumentLocation) -> some View {
        Button { onSelect(note) } label: {
            SidebarNoteRow(
                note: note,
                isActive: selectedDocumentPath == note.relativePath,
                depth: node.depth
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                tracksHover: false,
                in: Rectangle()
            )
        )
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibilityLabel(note.title ?? note.displayName)
        .accessibilityAddTraits(
            selectedDocumentPath == note.relativePath ? .isSelected : []
        )
        .accessibilityIdentifier("scholium.noteRow.\(note.relativePath)")
        .frame(minHeight: ScholiumMetrics.Library.hierarchyRowHeight)
        .contextMenu { noteContextMenu(note) }
        .accessibilityActions { noteAccessibilityActions(note) }
        .confirmationDialog(
            pendingDestructiveAction?.rawValue ?? "Confirm",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { if !$0 { pendingDestructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingDestructiveAction {
                Button(action.rawValue, role: action == .setAside ? nil : .destructive) {
                    perform(action, note: note)
                }
            }
            Button("Cancel", role: .cancel) { pendingDestructiveAction = nil }
        } message: {
            Text(destructiveMessage(for: pendingDestructiveAction, note: note))
        }
    }

    private var rowLeadingInset: CGFloat {
        sidebarLibraryRowLeadingInset(depth: node.depth)
    }

    private func toggleFolder() {
        if isExpanded { expandedFolders.remove(node.id) }
        else { expandedFolders.insert(node.id) }
    }

    @ViewBuilder
    private var folderContextMenu: some View {
        if let path = node.folderRelativePath {
            if canMutateFolder(path) {
                Button("New Note") { context.createUntitledNote(path) }
                Button("New Folder") { context.createUntitledFolder(path) }
                if let target = folderTarget(path) {
                    Button("Rename Folder…") { context.requestFolderLifecycle(.rename(target)) }
                    Button("Move Folder…") { context.requestFolderLifecycle(.move(target)) }
                }
            }
            if !node.children.isEmpty {
                Button(subtreeIsExpanded ? "Collapse All" : "Expand All", action: toggleEntireSubtree)
            }
            Divider()
            Button("Copy Relative Path") { context.copyRelativePath(path) }
            Button("Reveal in Finder") { context.revealNote(path) }
            if canMutateFolder(path) {
                Divider()
                Button("Move Folder and Notes to Trash…", role: .destructive) {
                    pendingFolderTrashTarget = folderTarget(path)
                }
            }
        } else if !node.children.isEmpty {
            Button(subtreeIsExpanded ? "Collapse All" : "Expand All", action: toggleEntireSubtree)
        }
    }

    @ViewBuilder
    private var folderAccessibilityActions: some View {
        if let path = node.folderRelativePath {
            if canMutateFolder(path) {
                Button("New Note") { context.createUntitledNote(path) }
                Button("New Folder") { context.createUntitledFolder(path) }
                if let target = folderTarget(path) {
                    Button("Rename Folder") { context.requestFolderLifecycle(.rename(target)) }
                    Button("Move Folder") { context.requestFolderLifecycle(.move(target)) }
                    Button("Move Folder and Notes to Trash") {
                        pendingFolderTrashTarget = target
                    }
                }
            }
            Button("Copy Relative Path") { context.copyRelativePath(path) }
            Button("Reveal in Finder") { context.revealNote(path) }
        }
        if !node.children.isEmpty {
            Button(subtreeIsExpanded ? "Collapse All" : "Expand All", action: toggleEntireSubtree)
        }
    }

    @ViewBuilder
    private func noteContextMenu(_ note: WindowDocumentLocation) -> some View {
        let groups = sidebarNoteCommandGroups(
            locationScope: context.locationScope,
            isManagedCritique: CritiquePlacement.isManagedCritiquePath(
                note.relativePath
            ),
            surface: .contextMenu
        )
        ForEach(groups.indices, id: \.self) { index in
            if index > groups.startIndex { Divider() }
            ForEach(groups[index].commands) { command in
                noteCommandButton(command, note: note, surface: .contextMenu)
            }
        }
    }

    @ViewBuilder
    private func noteAccessibilityActions(_ note: WindowDocumentLocation) -> some View {
        let groups = sidebarNoteCommandGroups(
            locationScope: context.locationScope,
            isManagedCritique: CritiquePlacement.isManagedCritiquePath(
                note.relativePath
            ),
            surface: .accessibility
        )
        ForEach(groups) { group in
            ForEach(group.commands) { command in
                noteCommandButton(command, note: note, surface: .accessibility)
            }
        }
    }

    @ViewBuilder
    private func noteCommandButton(
        _ command: SidebarNoteCommand,
        note: WindowDocumentLocation,
        surface: SidebarNoteCommandSurface
    ) -> some View {
        let title = surface == .contextMenu
            ? command.contextMenuTitle
            : command.accessibilityTitle
        Button(role: command.role) {
            perform(command, note: note)
        } label: {
            Text(title)
        }
        .disabled(
            command.requiresLifecycleTarget && NoteLifecycleTarget(note) == nil
        )
    }

    private func perform(
        _ command: SidebarNoteCommand,
        note: WindowDocumentLocation
    ) {
        switch command {
        case .openInNewTab:
            context.openNote(note, .newTab)
        case .duplicate, .rename, .move:
            guard let target = NoteLifecycleTarget(note) else {
                context.showError(
                    "This note cannot be changed until its identity is resolved."
                )
                return
            }
            switch command {
            case .duplicate: context.requestLifecycle(.duplicate(target))
            case .rename: context.requestLifecycle(.rename(target))
            case .move: context.requestLifecycle(.move(target))
            default: break
            }
        case .setAside:
            pendingDestructiveAction = .setAside
        case .moveToTrash:
            pendingDestructiveAction = .trash
        case .putBack:
            onPutBack(note)
        case .deletePermanently:
            pendingDestructiveAction = .delete
        case .copyRelativePath:
            context.copyRelativePath(note.relativePath)
        case .revealInFinder:
            context.revealNote(note.relativePath)
        }
    }

    private var subtreeFolderIDs: Set<String> { node.folderIDs }
    private var subtreeIsExpanded: Bool { subtreeFolderIDs.isSubset(of: expandedFolders) }

    private func toggleEntireSubtree() {
        if subtreeIsExpanded { expandedFolders.subtract(subtreeFolderIDs) }
        else { expandedFolders.formUnion(subtreeFolderIDs) }
    }

    private func canMutateFolder(_ path: String) -> Bool {
        guard context.locationScope == .workspace,
              context.canMutateLibrary else { return false }
        let candidate = "\(path)/Untitled.md"
        return !context.currentVaultRole.allowsCritique
            || !CritiquePlacement.isManagedCritiquePath(candidate)
    }

    private func folderTarget(_ path: String) -> FolderLifecycleTarget? {
        guard let vaultID = context.currentVaultID else { return nil }
        return FolderLifecycleTarget(vaultID: vaultID, relativePath: path)
    }

    private func performFolderTrash(_ target: FolderLifecycleTarget) {
        Task {
            do { try await context.moveFolderToTrash(target) }
            catch { context.showError("Could not move this folder to Trash. \(error.localizedDescription)") }
        }
    }

    private func destructiveMessage(
        for action: DestructiveAction?,
        note: WindowDocumentLocation
    ) -> String {
        let title = note.title ?? note.displayName
        return switch action {
        case .setAside: "Move ‘\(title)’ out of the active Workspace?"
        case .trash: "Move ‘\(title)’ to Trash?"
        case .delete: "Permanently delete ‘\(title)’? This cannot be undone."
        case nil: ""
        }
    }

    private func perform(_ action: DestructiveAction, note: WindowDocumentLocation) {
        pendingDestructiveAction = nil
        guard let target = NoteLifecycleTarget(note) else {
            onMutationFailed(note)
            context.showError(
                "This note cannot be changed until its identity is resolved."
            )
            return
        }
        onWillRemove(note)
        Task {
            do {
                switch action {
                case .setAside: try await context.setAside(target)
                case .trash: try await context.moveToTrash(target)
                case .delete: try await context.deletePermanently(target)
                }
            } catch {
                onMutationFailed(note)
                context.showError("Could not \(action.rawValue.lowercased()): \(error.localizedDescription)")
            }
        }
    }

}

struct SidebarNoteRow: View {
    let note: WindowDocumentLocation
    let isActive: Bool
    var depth: Int = 0

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: "doc.text")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
                .frame(width: ScholiumMetrics.Library.leadingSlotWidth)
                .accessibilityHidden(true)
            Text(note.title ?? note.displayName)
                .font(
                    isActive
                        ? ScholiumTypography.interface(.body, emphasis: .strong)
                        : ScholiumTypography.interface(.body)
                )
                .lineLimit(1)
                .truncationMode(.middle)
                .scholiumForeground(.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.leading, sidebarLibraryRowLeadingInset(depth: depth))
        .padding(.trailing, ScholiumMetrics.Library.rowHorizontalInset)
        .frame(
            maxWidth: .infinity,
            minHeight: ScholiumMetrics.Library.hierarchyRowHeight,
            alignment: .leading
        )
        .help(note.title ?? note.displayName)
    }
}

func sidebarLibraryRowLeadingInset(depth: Int) -> CGFloat {
    ScholiumMetrics.Library.rowHorizontalInset
        + CGFloat(max(0, depth)) * ScholiumMetrics.Library.hierarchyIndent
}
