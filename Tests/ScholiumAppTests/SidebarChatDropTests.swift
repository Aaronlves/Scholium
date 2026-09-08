import AppKit
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Toolbar Chat material drop")
@MainActor struct SidebarChatDropTests {
  @Test("Only a current local copy released on Chat accepts; hover and teardown cannot submit")
  func dropBoundary() throws {
    let control = ScholiumSidebarModeControl(frame: NSRect(x: 0, y: 0, width: 100, height: 28))
    control.segmentCount = 2
    control.enableNoteDrops()
    let board = NSPasteboard(name: .init("toolbar-drop-\(UUID())"))
    defer {
      board.releaseGlobally()
      control.invalidateNoteDrops()
    }
    let item = SidebarNoteDragItem(
      .init(
        documentID: .init(vaultID: UUID(), relativePath: "Note.md"),
        stableNoteID: UUID(), revision: .init(content: "source")))
    let payload = NSPasteboardItem()
    payload.setData(
      try JSONEncoder().encode(item), forType: .init(SidebarNoteDragItem.pasteboardType))
    board.writeObjects([payload])
    let drag = SidebarChatDraggingInfo(board)
    var accepted = 0
    var current = true
    control.validateNotes = { $0.count == 1 && current }
    control.acceptNotes = { _ in
      accepted += 1
      return true
    }
    drag.draggingLocation = NSPoint(x: 75, y: 14)
    #expect(control.draggingEntered(drag) == .copy)
    #expect(control.prepareForDragOperation(drag))
    #expect(accepted == 0)
    control.draggingExited(drag)
    #expect(accepted == 0)
    drag.draggingLocation.x = 25
    #expect(control.draggingUpdated(drag).isEmpty)
    #expect(!control.performDragOperation(drag))
    drag.draggingLocation.x = 75
    current = false
    #expect(!control.performDragOperation(drag))
    current = true
    drag.draggingSourceOperationMask = .move
    #expect(control.draggingEntered(drag).isEmpty)
    drag.draggingSourceOperationMask = .copy
    drag.draggingSource = nil
    #expect(!control.performDragOperation(drag))
    drag.draggingSource = control
    #expect(control.performDragOperation(drag))
    #expect(accepted == 1)
    control.setEnabled(false, forSegment: SidebarContent.chat.rawValue)
    #expect(!control.performDragOperation(drag))
    control.setEnabled(true, forSegment: SidebarContent.chat.rawValue)
    control.invalidateNoteDrops()
    #expect(!control.performDragOperation(drag))
    #expect(accepted == 1)
  }
}

@MainActor private final class SidebarChatDraggingInfo: NSObject, NSDraggingInfo {
  let draggingPasteboard: NSPasteboard
  init(_ board: NSPasteboard) { draggingPasteboard = board }
  var draggingSourceOperationMask: NSDragOperation = .copy
  var draggingDestinationWindow: NSWindow? { nil }
  var draggingLocation = NSPoint.zero
  var draggedImageLocation: NSPoint { .zero }
  nonisolated var draggedImage: NSImage? { nil }
  var draggingSource: Any? = NSObject()
  var draggingSequenceNumber: Int { 1 }
  var draggingFormation: NSDraggingFormation = .none
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 1
  var springLoadingHighlight: NSSpringLoadingHighlight { .none }
  func slideDraggedImage(to screenPoint: NSPoint) {}
  nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL)
    -> [String]?
  { nil }
  func resetSpringLoading() {}
  func enumerateDraggingItems(
    options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {}
}
