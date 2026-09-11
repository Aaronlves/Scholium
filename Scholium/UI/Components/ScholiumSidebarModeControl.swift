import AppKit

/// A native segment remains a navigation control and accepts explicit Note copies on Chat.
final class ScholiumSidebarModeControl: NSSegmentedControl {
    var validateNotes: (([SidebarNoteDragItem]) -> Bool)?
    var acceptNotes: (([SidebarNoteDragItem]) -> Bool)?

    func enableNoteDrops() {
        segmentDistribution = .fillEqually
        registerForDraggedTypes([.init(SidebarNoteDragItem.pasteboardType)])
    }

    func invalidateNoteDrops() {
        unregisterDraggedTypes()
        validateNotes = nil
        acceptNotes = nil
    }

    func isChatDropPoint(_ point: NSPoint) -> Bool {
        guard isEnabled, segmentCount == 2, isEnabled(forSegment: SidebarContent.chat.rawValue),
            bounds.contains(point), bounds.width > 0
        else { return false }
        let physicalSegment = point.x < bounds.midX ? 0 : 1
        let segment =
            userInterfaceLayoutDirection == .rightToLeft ? 1 - physicalSegment : physicalSegment
        return segment == SidebarContent.chat.rawValue
    }

    private func notes(from sender: any NSDraggingInfo) -> [SidebarNoteDragItem]? {
        guard sender.draggingSource != nil, sender.draggingSourceOperationMask.contains(.copy),
            isChatDropPoint(convert(sender.draggingLocation, from: nil)),
            let items = sender.draggingPasteboard.pasteboardItems, !items.isEmpty
        else { return nil }
        var notes: [SidebarNoteDragItem] = []
        for item in items {
            guard let data = item.data(forType: .init(SidebarNoteDragItem.pasteboardType)),
                let note = try? JSONDecoder().decode(SidebarNoteDragItem.self, from: data)
            else { return nil }
            notes.append(note)
        }
        return validateNotes?(notes) == true ? notes : nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        notes(from: sender) == nil ? [] : .copy
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        notes(from: sender) != nil
    }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let notes = notes(from: sender) else { return false }
        return acceptNotes?(notes) == true
    }
}
