import Foundation
import ScholiumContracts
import SwiftUI

// MARK: - Tree rows

enum SidebarNoteCommandSurface: Equatable {
    case contextMenu
    case accessibility
}

enum SidebarNoteCommand: String, Hashable, Identifiable {
    case openInNewTab
    case duplicate
    case rename
    case move
    case moveToSystemTrash
    case copyRelativePath
    case revealInFinder

    var id: String { rawValue }

    var requiresMutationTarget: Bool {
        switch self {
        case .openInNewTab, .copyRelativePath, .revealInFinder:
            false
        case .duplicate, .rename, .move, .moveToSystemTrash:
            true
        }
    }

    var contextMenuTitle: LocalizedStringKey {
        switch self {
        case .openInNewTab: "Open in New Tab"
        case .duplicate: "Duplicate…"
        case .rename: "Rename…"
        case .move: "Move Note…"
        case .moveToSystemTrash: "Move to Trash…"
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
        case .moveToSystemTrash: "Move to Trash"
        case .copyRelativePath: "Copy Relative Path"
        case .revealInFinder: "Reveal in Finder"
        }
    }

    var role: ButtonRole? {
        self == .moveToSystemTrash ? .destructive : nil
    }
}

struct SidebarNoteCommandGroup: Hashable, Identifiable {
    enum Kind: String, Hashable {
        case opening
        case editing
        case fileActions
        case location
    }

    let kind: Kind
    let commands: [SidebarNoteCommand]

    var id: Kind { kind }
}

func sidebarNoteCommandGroups(
    isManagedCritique: Bool,
    surface: SidebarNoteCommandSurface
) -> [SidebarNoteCommandGroup] {
    var groups = [SidebarNoteCommandGroup(
        kind: .opening,
        commands: [.openInNewTab]
    )]

    var editing: [SidebarNoteCommand] = []
    if !isManagedCritique { editing.append(.duplicate) }
    editing.append(.rename)
    if surface == .accessibility { editing.append(.move) }
    groups.append(SidebarNoteCommandGroup(
        kind: .editing,
        commands: editing
    ))
    groups.append(SidebarNoteCommandGroup(
        kind: .fileActions,
        commands: [.moveToSystemTrash]
    ))

    groups.append(SidebarNoteCommandGroup(
        kind: .location,
        commands: [.copyRelativePath, .revealInFinder]
    ))
    return groups
}

struct SidebarTreeContext {
    let currentVaultID: UUID?
    let currentVaultRole: VaultRole
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
    let requestFileOperation: (NoteFileRequest) -> Void
    let canMutateLibrary: Bool
    let createUntitledNote: (String?) -> Void
    let createUntitledFolder: (String?) -> Void
    let requestFolderFileOperation: (FolderFileRequest) -> Void
    let requestFolderSystemTrash: (FolderMutationTarget) async throws -> Void
    let copyRelativePath: (String) -> Void
    let revealNote: (String) -> Void
    let requestSystemTrash: (NoteMutationTarget) async throws -> Void
    let showError: (String) -> Void
}

struct SidebarTreeNodeRow: View {
    let node: TreeNode
    @Binding var expandedFolders: Set<String>
    let selectedDocumentPath: String?
    let context: SidebarTreeContext
    let onSelect: (WindowDocumentLocation) -> Void

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
                    Button("Rename Folder…") { context.requestFolderFileOperation(.rename(target)) }
                    Button("Move Folder…") { context.requestFolderFileOperation(.move(target)) }
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
                    if let target = folderTarget(path) { performFolderTrash(target) }
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
                    Button("Rename Folder") { context.requestFolderFileOperation(.rename(target)) }
                    Button("Move Folder") { context.requestFolderFileOperation(.move(target)) }
                    Button("Move Folder and Notes to Trash") {
                        performFolderTrash(target)
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
            command.requiresMutationTarget && NoteMutationTarget(note) == nil
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
            guard let target = NoteMutationTarget(note) else {
                context.showError(
                    "This note cannot be changed until its identity is resolved."
                )
                return
            }
            switch command {
            case .duplicate: context.requestFileOperation(.duplicate(target))
            case .rename: context.requestFileOperation(.rename(target))
            case .move: context.requestFileOperation(.move(target))
            default: break
            }
        case .moveToSystemTrash:
            guard let target = NoteMutationTarget(note) else {
                context.showError(
                    "This note cannot be changed until its identity is resolved."
                )
                return
            }
            Task {
                do { try await context.requestSystemTrash(target) }
                catch {
                    context.showError(
                        "Could not prepare Move to Trash. \(error.localizedDescription)"
                    )
                }
            }
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
        guard context.canMutateLibrary else { return false }
        let candidate = "\(path)/Untitled.md"
        return !context.currentVaultRole.allowsCritique
            || !CritiquePlacement.isManagedCritiquePath(candidate)
    }

    private func folderTarget(_ path: String) -> FolderMutationTarget? {
        guard let vaultID = context.currentVaultID else { return nil }
        return FolderMutationTarget(vaultID: vaultID, relativePath: path)
    }

    private func performFolderTrash(_ target: FolderMutationTarget) {
        Task {
            do { try await context.requestFolderSystemTrash(target) }
            catch { context.showError("Could not prepare this folder for Move to Trash. \(error.localizedDescription)") }
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
