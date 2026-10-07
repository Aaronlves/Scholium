import AppKit
import ScholiumContracts

let sidebarNativeDraggingTypes = [
    NSPasteboard.PasteboardType(SidebarNoteDragItem.pasteboardType),
    NSPasteboard.PasteboardType(SidebarFolderDragItem.pasteboardType),
]

enum SidebarNativeDragPayload {
    case note(SidebarNoteDragItem)
    case notes([SidebarNoteDragItem])
    case folder(SidebarFolderDragItem)
}

@MainActor
func sidebarNativeDragPayload(
    from info: NSDraggingInfo
) -> SidebarNativeDragPayload? {
    // A local AppKit source object is the synchronous process boundary that
    // keeps forged external pasteboard data from advertising a Move. Exact
    // revision and occupancy facts are checked against the current inventory.
    guard info.draggingSource != nil else { return nil }
    return sidebarNativeDragPayload(from: info.draggingPasteboard)
}

func sidebarNativeDragPayload(from pasteboard: NSPasteboard) -> SidebarNativeDragPayload? {
    guard let entries = pasteboard.pasteboardItems, !entries.isEmpty else { return nil }
    var notes: [SidebarNoteDragItem] = []
    for entry in entries {
        let noteData = entry.data(forType: sidebarNativeDraggingTypes[0])
        let folderData = entry.data(forType: sidebarNativeDraggingTypes[1])
        guard (noteData != nil) != (folderData != nil) else { return nil }
        if let noteData {
            guard let item = try? JSONDecoder().decode(SidebarNoteDragItem.self, from: noteData) else { return nil }
            notes.append(item)
        } else if let folderData {
            guard entries.count == 1,
                let item = try? JSONDecoder().decode(SidebarFolderDragItem.self, from: folderData)
            else { return nil }
            return .folder(item)
        }
    }
    guard Set(notes.map(\.id)).count == notes.count else { return nil }
    if notes.count == 1, let item = notes.first { return .note(item) }
    return notes.isEmpty ? nil : .notes(notes)
}

func sidebarNativeDropIsValid(
    _ payload: SidebarNativeDragPayload,
    folderRelativePath: String?,
    inventory: SidebarTreeDropInventory
) -> Bool {
    switch payload {
    case .note(let item):
        sidebarValidatedNoteDropDestination(
            item: item,
            folderRelativePath: folderRelativePath,
            inventory: inventory
        ) != nil
    case .notes(let items):
        sidebarValidatedNotesDropDestinations(items: items, folderRelativePath: folderRelativePath, inventory: inventory) != nil
    case .folder(let item):
        sidebarValidatedFolderDropDestination(
            item: item,
            folderRelativePath: folderRelativePath,
            inventory: inventory
        ) != nil
    }
}

@MainActor
func commitSidebarNativeDrop(
    _ payload: SidebarNativeDragPayload,
    folderRelativePath: String?,
    onMoveNote: (SidebarNoteDragItem, String?) -> Void,
    onMoveFolder: (SidebarFolderDragItem, String?) -> Void,
    onMoveNotes: ([SidebarNoteDragItem], String?) -> Void
) {
    switch payload {
    case .note(let item): onMoveNote(item, folderRelativePath)
    case .notes(let items): onMoveNotes(items, folderRelativePath)
    case .folder(let item): onMoveFolder(item, folderRelativePath)
    }
}
