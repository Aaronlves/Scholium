import AppKit
import Foundation
import ScholiumContracts

// MARK: - Tree rows

enum SidebarNoteCommandSurface: Equatable {
    case contextMenu
    case accessibility
}

enum SidebarNoteCommand: String, Hashable, Identifiable {
    case openInNewTab
    case openInSeparateWindow
    case addToChat
    case duplicate
    case move
    case moveToSystemTrash
    case copyRelativePath
    case revealInFinder

    var id: String { rawValue }

    var requiresMutationTarget: Bool {
        switch self {
        case .openInNewTab, .openInSeparateWindow, .addToChat, .copyRelativePath, .revealInFinder:
            false
        case .duplicate, .move, .moveToSystemTrash:
            true
        }
    }

    var contextMenuTitleKey: String.LocalizationValue {
        switch self {
        case .openInNewTab: "Open in New Tab"
        case .openInSeparateWindow: "Open in Separate Window"
        case .addToChat: "Add to Chat"
        case .duplicate: "Duplicate…"
        case .move: "Move Note…"
        case .moveToSystemTrash: "Move to Trash…"
        case .copyRelativePath: "Copy Relative Path"
        case .revealInFinder: "Reveal in Finder"
        }
    }

    var accessibilityTitleKey: String.LocalizationValue {
        switch self {
        case .openInNewTab: "Open in New Tab"
        case .openInSeparateWindow: "Open in Separate Window"
        case .addToChat: "Add to Chat"
        case .duplicate: "Duplicate Note"
        case .move: "Move Note"
        case .moveToSystemTrash: "Move to Trash"
        case .copyRelativePath: "Copy Relative Path"
        case .revealInFinder: "Reveal in Finder"
        }
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

func sidebarNoteCommandGroups() -> [SidebarNoteCommandGroup] {
    let groups = [
        SidebarNoteCommandGroup(kind: .opening, commands: [.openInNewTab, .openInSeparateWindow, .addToChat]),
        SidebarNoteCommandGroup(kind: .editing, commands: [.duplicate, .move]),
        SidebarNoteCommandGroup(kind: .location, commands: [.revealInFinder, .copyRelativePath]),
        SidebarNoteCommandGroup(kind: .fileActions, commands: [.moveToSystemTrash]),
    ]
    return groups
}

struct SidebarTreeContext {
    let currentVaultID: UUID?
    let currentVaultRole: VaultRole
    var selectedRowIDs: Set<String> = []
    var selectedBatchTargets: [NoteMutationTarget] = []
    var requestNoteBatchMove: ([NoteMutationTarget]) -> Void = { _ in }
    var requestNoteBatchTrash: ([NoteMutationTarget]) -> Void = { _ in }
    let openNote: (WindowDocumentLocation, WindowOpenDisposition) -> Void
    let canAddNoteToChat: (WindowDocumentLocation) -> Bool
    let addNoteToChat: (WindowDocumentLocation) -> Void
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

    @MainActor
    func canPerform(_ command: SidebarNoteCommand, note: WindowDocumentLocation) -> Bool {
        if command == .addToChat { return canAddNoteToChat(note) }
        return !command.requiresMutationTarget || (canMutateLibrary && NoteMutationTarget(note) != nil)
    }

    @MainActor
    func perform(_ command: SidebarNoteCommand, note: WindowDocumentLocation) {
        guard canPerform(command, note: note) else { return }
        switch command {
        case .openInNewTab: openNote(note, .newTab)
        case .openInSeparateWindow: openNote(note, .separateWindow)
        case .addToChat: addNoteToChat(note)
        case .duplicate, .move, .moveToSystemTrash:
            guard let target = NoteMutationTarget(note) else { return }
            switch command {
            case .duplicate: requestFileOperation(.duplicate(target))
            case .move: requestFileOperation(.move(target))
            case .moveToSystemTrash: requestNoteTrash(target)
            default: break
            }
        case .copyRelativePath: copyRelativePath(note.relativePath)
        case .revealInFinder: revealNote(note.relativePath)
        }
    }

    @MainActor
    func requestFolderTrash(_ target: FolderMutationTarget) {
        guard canMutateLibrary else { return }
        Task {
            do { try await requestFolderSystemTrash(target) } catch {
                showError("Could not prepare this folder for Move to Trash. \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    func requestNoteTrash(_ target: NoteMutationTarget) {
        guard canMutateLibrary else { return }
        Task {
            do { try await requestSystemTrash(target) } catch {
                showError("Could not prepare Move to Trash. \(error.localizedDescription)")
            }
        }
    }
}
