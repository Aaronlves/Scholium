import Foundation
import ScholiumContracts

/// Reuse derived Library work across unrelated window publications. Inputs
/// retain exact current Note values; these projections never authorize writes.
@MainActor
final class LibraryPresentationCache {
    private struct OrderingInput: Equatable {
        let notes: [WindowDocumentLocation]
        let sortOrder: NoteSortOrder
        let localeIdentifier: String

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.sortOrder == rhs.sortOrder && lhs.localeIdentifier == rhs.localeIdentifier
                && libraryNoteCohortsMatch(lhs.notes, rhs.notes)
        }
    }

    private struct DropInput: Equatable {
        let vaultID: UUID?
        let sourceScope: LibrarySourceScope
        let role: VaultRole
        let canMutate: Bool
        let notes: [WindowDocumentLocation]
        let folders: [String]
        let policy: VaultPathComparisonPolicy?
        let pendingNotes: Set<SidebarNoteDragID>
        let pendingFolders: Set<SidebarFolderDragID>

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.vaultID == rhs.vaultID && lhs.sourceScope == rhs.sourceScope && lhs.role == rhs.role
                && lhs.canMutate == rhs.canMutate && lhs.policy == rhs.policy
                && lhs.pendingNotes == rhs.pendingNotes && lhs.pendingFolders == rhs.pendingFolders
                && libraryNoteCohortsMatch(lhs.notes, rhs.notes)
                && libraryFolderInventoriesMatch(lhs.folders, rhs.folders)
        }
    }

    private var orderingInput: OrderingInput?
    private var orderedNotes: [WindowDocumentLocation] = []
    private var dropInput: DropInput?
    private var dropInventory: SidebarTreeDropInventory?

    func ordered(
        _ notes: [WindowDocumentLocation],
        sortOrder: NoteSortOrder,
        localeIdentifier: String = Locale.current.identifier,
        by areOrdered: (WindowDocumentLocation, WindowDocumentLocation) -> Bool
    ) -> [WindowDocumentLocation] {
        let input = OrderingInput(notes: notes, sortOrder: sortOrder, localeIdentifier: localeIdentifier)
        if input != orderingInput {
            orderedNotes = notes.sorted(by: areOrdered)
            orderingInput = input
        }
        return orderedNotes
    }

    func drop(
        vaultID: UUID?,
        sourceScope: LibrarySourceScope,
        role: VaultRole,
        canMutate: Bool,
        notes: [WindowDocumentLocation],
        folders: [String],
        policy: VaultPathComparisonPolicy?,
        pendingNotes: Set<SidebarNoteDragID>,
        pendingFolders: Set<SidebarFolderDragID>
    ) -> SidebarTreeDropInventory {
        let input = DropInput(
            vaultID: vaultID, sourceScope: sourceScope, role: role, canMutate: canMutate,
            notes: notes, folders: folders, policy: policy,
            pendingNotes: pendingNotes, pendingFolders: pendingFolders)
        if input == dropInput, let dropInventory { return dropInventory }
        let inventory = SidebarTreeDropInventory(
            currentVaultID: vaultID, sourceScope: sourceScope, currentVaultRole: role,
            canMutate: canMutate, notes: notes, folderRelativePaths: Set(folders),
            pathComparisonPolicy: policy, pendingNoteMoves: pendingNotes, pendingFolderMoves: pendingFolders)
        dropInput = input
        dropInventory = inventory
        return inventory
    }
}
