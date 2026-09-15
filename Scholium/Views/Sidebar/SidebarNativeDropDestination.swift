import AppKit
import ScholiumContracts
import SwiftUI

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

/// The stable LibraryHeader is the sole native pointer target for moving an
/// ordinary Note or Folder back to the current vault root. The populated
/// outline remains responsible only for Folder-row destinations.
struct SidebarLibraryHeaderDropDestination: NSViewRepresentable {
    let dropInventory: SidebarTreeDropInventory
    let onMoveNoteDrop: (SidebarNoteDragItem, String?) -> Void
    let onMoveFolderDrop: (SidebarFolderDragItem, String?) -> Void
    let onMoveNotesDrop: ([SidebarNoteDragItem], String?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = SidebarLibraryHeaderDropView()
        view.registerForDraggedTypes(sidebarNativeDraggingTypes)
        view.update(
            dropInventory: dropInventory,
            onMoveNoteDrop: onMoveNoteDrop,
            onMoveFolderDrop: onMoveFolderDrop,
            onMoveNotesDrop: onMoveNotesDrop
        )
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? SidebarLibraryHeaderDropView else { return }
        view.update(
            dropInventory: dropInventory,
            onMoveNoteDrop: onMoveNoteDrop,
            onMoveFolderDrop: onMoveFolderDrop,
            onMoveNotesDrop: onMoveNotesDrop
        )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Void) {
        view.unregisterDraggedTypes()
    }
}

@MainActor
private final class SidebarLibraryHeaderDropView: NSView {
    private var dropInventory: SidebarTreeDropInventory?
    private var onMoveNoteDrop: ((SidebarNoteDragItem, String?) -> Void)?
    private var onMoveFolderDrop: ((SidebarFolderDragItem, String?) -> Void)?
    private var onMoveNotesDrop: (([SidebarNoteDragItem], String?) -> Void)?
    private var isDropTargeted = false

    override var isOpaque: Bool { false }

    func update(
        dropInventory: SidebarTreeDropInventory,
        onMoveNoteDrop: @escaping (SidebarNoteDragItem, String?) -> Void,
        onMoveFolderDrop: @escaping (SidebarFolderDragItem, String?) -> Void,
        onMoveNotesDrop: @escaping ([SidebarNoteDragItem], String?) -> Void
    ) {
        self.dropInventory = dropInventory
        self.onMoveNoteDrop = onMoveNoteDrop
        self.onMoveFolderDrop = onMoveFolderDrop
        self.onMoveNotesDrop = onMoveNotesDrop
        if dropInventory.sourceScope != .library || !dropInventory.canMutate {
            setDropTargeted(false)
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        validatedOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        validatedOperation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        validatedPayload(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let payload = validatedPayload(from: sender),
            let onMoveNoteDrop,
            let onMoveFolderDrop,
            let onMoveNotesDrop
        else {
            setDropTargeted(false)
            return false
        }
        setDropTargeted(false)
        commitSidebarNativeDrop(
            payload,
            folderRelativePath: nil,
            onMoveNote: onMoveNoteDrop,
            onMoveFolder: onMoveFolderDrop,
            onMoveNotes: onMoveNotesDrop
        )
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        setDropTargeted(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isDropTargeted else { return }
        NSColor(ScholiumColorRole.raisedSurfaceBackground.color)
            .withAlphaComponent(0.48)
            .setFill()
        bounds.fill()
    }

    private func validatedOperation(
        for sender: NSDraggingInfo
    ) -> NSDragOperation {
        let operation: NSDragOperation =
            validatedPayload(from: sender) == nil
            ? []
            : .move
        setDropTargeted(operation == .move)
        return operation
    }

    private func validatedPayload(
        from sender: NSDraggingInfo
    ) -> SidebarNativeDragPayload? {
        guard let dropInventory,
            let payload = sidebarNativeDragPayload(from: sender),
            sidebarNativeDropIsValid(
                payload,
                folderRelativePath: nil,
                inventory: dropInventory
            )
        else { return nil }
        return payload
    }

    private func setDropTargeted(_ targeted: Bool) {
        guard isDropTargeted != targeted else { return }
        isDropTargeted = targeted
        needsDisplay = true
    }
}
