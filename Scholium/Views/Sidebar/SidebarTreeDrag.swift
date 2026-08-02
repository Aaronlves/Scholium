import Foundation
import ScholiumContracts

struct SidebarNoteDragID: Codable, Hashable, Sendable {
    let vaultID: UUID
    let relativePath: String
}

struct SidebarFolderDragID: Codable, Hashable, Sendable {
    let vaultID: UUID
    let relativePath: String
}

struct SidebarNoteDragItem: Codable, Identifiable, Sendable {
    static let pasteboardType = "com.scholium.sidebar-note-move"

    let documentID: VaultQualifiedNoteID
    let stableNoteID: UUID
    let revision: DocumentFingerprint

    var id: SidebarNoteDragID {
        SidebarNoteDragID(
            vaultID: documentID.vaultID,
            relativePath: documentID.relativePath
        )
    }

    var lifecycleTarget: NoteLifecycleTarget {
        NoteLifecycleTarget(
            documentID: documentID,
            stableNoteID: stableNoteID,
            revision: revision
        )
    }

    init(_ target: NoteLifecycleTarget) {
        documentID = target.documentID
        stableNoteID = target.stableNoteID
        revision = target.revision
    }

}

struct SidebarFolderDragItem: Codable, Identifiable, Sendable {
    static let pasteboardType = "com.scholium.sidebar-folder-move"

    let vaultID: UUID
    let relativePath: String

    var id: SidebarFolderDragID {
        SidebarFolderDragID(vaultID: vaultID, relativePath: relativePath)
    }

    var lifecycleTarget: FolderLifecycleTarget {
        FolderLifecycleTarget(vaultID: vaultID, relativePath: relativePath)
    }

    init(_ target: FolderLifecycleTarget) {
        vaultID = target.vaultID
        relativePath = target.relativePath
    }

}

/// Current immutable facts needed to decide whether the native outline may
/// advertise a Move. The repository remains the final filesystem authority;
/// this preflight prevents stale, duplicate, occupied, or structurally invalid
/// drops from presenting an accepting target in the first place.
struct SidebarTreeDropInventory {
    let currentVaultID: UUID?
    let locationScope: NoteLocationScope
    let currentVaultRole: VaultRole
    let canMutate: Bool
    let notes: [WindowDocumentLocation]
    let folderRelativePaths: Set<String>
    let pathComparisonPolicy: VaultPathComparisonPolicy?
    let notePathComparisonKeys: Set<VaultPathComparisonKey>
    let folderPathComparisonKeys: Set<VaultPathComparisonKey>
    let pendingNoteMoves: Set<SidebarNoteDragID>
    let pendingFolderMoves: Set<SidebarFolderDragID>

    init(
        currentVaultID: UUID?,
        locationScope: NoteLocationScope,
        currentVaultRole: VaultRole,
        canMutate: Bool,
        notes: [WindowDocumentLocation],
        folderRelativePaths: Set<String>,
        pathComparisonPolicy: VaultPathComparisonPolicy?,
        pendingNoteMoves: Set<SidebarNoteDragID>,
        pendingFolderMoves: Set<SidebarFolderDragID>
    ) {
        self.currentVaultID = currentVaultID
        self.locationScope = locationScope
        self.currentVaultRole = currentVaultRole
        self.canMutate = canMutate
        self.notes = notes
        self.folderRelativePaths = folderRelativePaths
        self.pathComparisonPolicy = pathComparisonPolicy
        self.pendingNoteMoves = pendingNoteMoves
        self.pendingFolderMoves = pendingFolderMoves

        guard let pathComparisonPolicy else {
            notePathComparisonKeys = []
            folderPathComparisonKeys = []
            return
        }
        notePathComparisonKeys = Set(notes.compactMap { note in
            guard let path = try? MarkdownRelativePath(note.relativePath) else {
                return nil
            }
            return pathComparisonPolicy.comparisonKey(for: path)
        })
        folderPathComparisonKeys = Set(folderRelativePaths.compactMap { rawPath in
            guard let path = try? VaultRelativeFolderPath(rawPath) else {
                return nil
            }
            return pathComparisonPolicy.comparisonKey(for: path)
        })
    }
}

func sidebarValidatedNoteDropDestination(
    item: SidebarNoteDragItem,
    folderRelativePath: String?,
    inventory: SidebarTreeDropInventory
) -> String? {
    guard inventory.locationScope == .workspace,
          inventory.canMutate,
          item.documentID.vaultID == inventory.currentVaultID,
          !inventory.pendingNoteMoves.contains(item.id),
          let source = inventory.notes.first(where: {
              $0.relativePath == item.documentID.relativePath
          }),
          NoteLifecycleTarget(source) == item.lifecycleTarget,
          !CritiquePlacement.isManagedCritiquePath(source.relativePath),
          sidebarDropFolderIsMutable(folderRelativePath, inventory: inventory),
          let pathComparisonPolicy = inventory.pathComparisonPolicy,
          let sourcePath = try? MarkdownRelativePath(item.documentID.relativePath)
    else { return nil }

    let destination = sidebarNoteDropDestination(
        sourceRelativePath: item.documentID.relativePath,
        folderRelativePath: folderRelativePath
    )
    guard let destinationPath = try? MarkdownRelativePath(destination) else {
        return nil
    }
    let sourceKey = pathComparisonPolicy.comparisonKey(for: sourcePath)
    let destinationKey = pathComparisonPolicy.comparisonKey(for: destinationPath)
    guard destinationKey != sourceKey,
          !inventory.notePathComparisonKeys.contains(destinationKey),
          !inventory.folderPathComparisonKeys.contains(destinationKey)
    else { return nil }

    if inventory.currentVaultRole.allowsCritique {
        guard (try? CritiquePlacement.validateOrdinaryMove(
            from: item.documentID.relativePath,
            to: destination
        )) != nil else { return nil }
    }
    return destination
}

func sidebarValidatedFolderDropDestination(
    item: SidebarFolderDragItem,
    folderRelativePath: String?,
    inventory: SidebarTreeDropInventory
) -> String? {
    guard inventory.locationScope == .workspace,
          inventory.canMutate,
          item.vaultID == inventory.currentVaultID,
          !inventory.pendingFolderMoves.contains(item.id),
          inventory.folderRelativePaths.contains(item.relativePath),
          sidebarDropFolderIsMutable(item.relativePath, inventory: inventory),
          sidebarDropFolderIsMutable(folderRelativePath, inventory: inventory),
          let pathComparisonPolicy = inventory.pathComparisonPolicy,
          let sourcePath = try? VaultRelativeFolderPath(item.relativePath),
          let destination = sidebarFolderDropDestination(
              sourceRelativePath: item.relativePath,
              folderRelativePath: folderRelativePath
          ),
          let destinationPath = try? VaultRelativeFolderPath(destination)
    else { return nil }

    let sourceKey = pathComparisonPolicy.comparisonKey(for: sourcePath)
    if let folderRelativePath {
        guard let targetPath = try? VaultRelativeFolderPath(folderRelativePath) else {
            return nil
        }
        let targetKey = pathComparisonPolicy.comparisonKey(for: targetPath)
        guard targetKey != sourceKey,
              !targetKey.value.hasPrefix(sourceKey.value + "/") else {
            return nil
        }
    }
    let destinationKey = pathComparisonPolicy.comparisonKey(for: destinationPath)
    guard destinationKey != sourceKey,
          !inventory.folderPathComparisonKeys.contains(destinationKey),
          !inventory.notePathComparisonKeys.contains(destinationKey) else {
        return nil
    }
    return destination
}

func sidebarDropFolderIsMutable(
    _ folderRelativePath: String?,
    inventory: SidebarTreeDropInventory
) -> Bool {
    guard let folderRelativePath else { return true }
    guard inventory.folderRelativePaths.contains(folderRelativePath) else {
        return false
    }
    let candidate = "\(folderRelativePath)/Untitled.md"
    return !inventory.currentVaultRole.allowsCritique
        || !CritiquePlacement.isManagedCritiquePath(candidate)
}

func sidebarNoteDropDestination(
    sourceRelativePath: String,
    folderRelativePath: String?
) -> String {
    let fileName = (sourceRelativePath as NSString).lastPathComponent
    guard let folderRelativePath,
          !folderRelativePath.isEmpty else { return fileName }
    return (folderRelativePath as NSString).appendingPathComponent(fileName)
}

/// Returns the exact folder destination for a direct tree move. Moving to the
/// current parent, into the source itself, or into one of its descendants is
/// rejected before the filesystem transaction begins.
func sidebarFolderDropDestination(
    sourceRelativePath: String,
    folderRelativePath: String?
) -> String? {
    let source = sourceRelativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let fileName = (source as NSString).lastPathComponent
    guard !source.isEmpty, !fileName.isEmpty else { return nil }

    if let folderRelativePath, !folderRelativePath.isEmpty {
        let folder = folderRelativePath.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        guard folder != source, !folder.hasPrefix(source + "/") else { return nil }
        let destination = (folder as NSString).appendingPathComponent(fileName)
        return destination == source ? nil : destination
    }

    return fileName == source ? nil : fileName
}
