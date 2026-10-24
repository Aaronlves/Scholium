import AppKit
import Combine
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Notifications activation", .serialized)
@MainActor
struct AttentionQueueInteractionTests {
    @Test(
        "Notification content hits its native button and row edges retain the native table action",
        arguments: ["title", "detail", "icon", "leading edge", "trailing edge"]
    )
    func nativeHitTargets(region: String) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.controller.view.layoutSubtreeIfNeeded()
        fixture.table.layoutSubtreeIfNeeded()
        let cell = try #require(fixture.table.view(atColumn: 0, row: 2, makeIfNecessary: true) as? NSTableCellView)
        cell.layoutSubtreeIfNeeded()
        let button = try #require(findButton(in: cell))
        let rowRect = fixture.table.rect(ofRow: 2)
        try #require(fixture.table.visibleRect.contains(rowRect))
        let point: NSPoint
        switch region {
        case "title":
            let title = try #require(cell.textField)
            point = title.convert(NSPoint(x: title.bounds.midX, y: title.bounds.midY), to: nil)
        case "detail":
            let detail = try #require(button.subviews.compactMap { $0 as? NSTextField }.first { $0 !== cell.textField })
            point = detail.convert(NSPoint(x: detail.bounds.midX, y: detail.bounds.midY), to: nil)
        case "icon":
            let icon = try #require(cell.imageView)
            point = icon.convert(NSPoint(x: icon.bounds.midX, y: icon.bounds.midY), to: nil)
        case "leading edge":
            point = fixture.table.convert(NSPoint(x: rowRect.minX + 1, y: rowRect.midY), to: nil)
        default:
            point = fixture.table.convert(NSPoint(x: rowRect.maxX - 1, y: rowRect.midY), to: nil)
        }
        let root = try #require(fixture.window.contentView)
        let hit = try #require(root.hitTest(root.convert(point, from: nil)))
        if region == "leading edge" || region == "trailing edge" {
            #expect(hit === fixture.table || hit is NSTableRowView)
            #expect(hit === fixture.table || hit.isDescendant(of: fixture.table))
            #expect(fixture.table.target === fixture.table)
            #expect(fixture.table.action == #selector(AttentionQueueTableView.activateClickedRow(_:)))
        } else {
            #expect(hit === button)
            #expect(button.accessibilityLabel()?.contains("Topic-1.md") == true)
        }
        // Hit routing itself must neither activate a Note nor change selection.
        // Real mouse tracking is verified by the application UI journey.
        #expect(fixture.opened.isEmpty)
        #expect(fixture.table.selectedRow == -1)
    }

    @Test("Return and accessibility confirmation open the selected current notification")
    func selectedActivation() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let table = fixture.table
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        #expect(table.accessibilityPerformConfirm())
        #expect(fixture.opened == [fixture.items[1].noteID])

        fixture.present()
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: fixture.window.windowNumber, context: nil,
                characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        table.keyDown(with: event)
        #expect(fixture.opened == [fixture.items[1].noteID, fixture.items[0].noteID])
        fixture.present()
        table.deselectAll(nil)
        #expect(!table.accessibilityPerformPress())
    }

    @Test("A notification accessibility action retains its identity and rejects removal before a queued reload")
    func rowActivationAndRemoval() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let cell = try #require(fixture.table.view(atColumn: 0, row: 2, makeIfNecessary: true))
        let button = try #require(findButton(in: cell))
        #expect(button.accessibilityLabel()?.contains("Topic-1.md") == true)
        #expect(button.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress)))
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        // The SDK's stock NSButton can report false after delivering its target
        // action. The opened stable identity is this operation's result oracle.
        _ = button.accessibilityPerformPress()
        #expect(fixture.opened == [fixture.items[1].noteID])
        #expect(fixture.table.selectedRow == 2)
        #expect(fixture.session.presentation.selectedItemID == fixture.itemID(fixture.items[1]))
        fixture.present()
        fixture.changes.send([fixture.items[0]])
        // The native view is intentionally retained before its queued reload.
        _ = button.accessibilityPerformPress()
        #expect(fixture.opened.count == 1)
        fixture.session.presentation.filter = .init(query: "No matching notification")
        #expect(!fixture.table.accessibilityPerformConfirm())
    }

    @Test("The native table accessibility tree exposes a named Press action for each notification")
    func vendedAccessibilityActivation() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        let targetID = "scholium.notification.change.\(fixture.items[1].id.uuidString.lowercased())"
        let tree = accessibilityTree(in: fixture.table)
        let target = try #require(
            findAccessibleElement(targetID, in: fixture.table),
            Comment(rawValue: "The named notification must be reachable through the table's actual accessibility children. " + tree.joined(separator: " | ")))
        #expect(target.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress)))
        #expect(target.accessibilityLabel()?.contains("Topic-1.md") == true)
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        _ = target.accessibilityPerformPress()
        #expect(fixture.opened == [fixture.items[1].noteID])
        #expect(fixture.table.selectedRow == 2)
        #expect(fixture.session.presentation.selectedItemID == fixture.itemID(fixture.items[1]))
    }

    private func findAccessibleElement(_ id: String, in object: NSObject, depth: Int = 0) -> (any NSAccessibilityProtocol)? {
        guard depth < 10 else { return nil }
        if let accessible = object as? any NSAccessibilityProtocol,
            accessible.accessibilityIdentifier() == id,
            accessible.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress))
        {
            return accessible
        }
        let children = accessibilityChildren(of: object)
        for child in children {
            if let child = child as? NSObject, let found = findAccessibleElement(id, in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private func accessibilityTree(in root: NSObject) -> [String] {
        var result: [String] = []
        var visited: Set<ObjectIdentifier> = []
        func visit(_ object: NSObject, depth: Int) {
            guard result.count < 40, depth < 10, visited.insert(ObjectIdentifier(object)).inserted else { return }
            if let accessible = object as? any NSAccessibilityProtocol {
                result.append(
                    "\(depth):\(type(of: object)):role=\(accessible.accessibilityRole()?.rawValue ?? "nil")"
                        + ":id=\(accessible.accessibilityIdentifier() ?? "nil")"
                        + ":press=\(accessible.isAccessibilitySelectorAllowed(#selector(NSAccessibilityProtocol.accessibilityPerformPress)))")
            } else {
                result.append("\(depth):\(type(of: object)):proxy:children=\(accessibilityChildren(of: object).count)")
            }
            for child in accessibilityChildren(of: object) {
                if let child = child as? NSObject { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return result
    }

    private func accessibilityChildren(of object: NSObject) -> [Any] {
        if let accessible = object as? any NSAccessibilityProtocol { return accessible.accessibilityChildren() ?? [] }
        // AppKit's table row/column proxies implement this public getter without
        // declaring the complete protocol. Keep its NSArray untyped: SDK row
        // protocol bridging is stricter than these native proxy objects.
        let selector = #selector(NSAccessibilityProtocol.accessibilityChildren)
        if object.responds(to: selector), let children = object.perform(selector)?.takeUnretainedValue() as? [Any] { return children }
        // Current AppKit table proxies can expose children only through the
        // attribute API even when their protocol accessor has no children.
        return (object.accessibilityAttributeValue(.children) as? NSArray)?.map { $0 } ?? []
    }

    private func findButton(in view: NSView) -> NSButton? {
        (view as? NSButton) ?? view.subviews.lazy.compactMap(findButton).first
    }

    @MainActor
    private final class Fixture {
        let changes = PassthroughSubject<[DocumentChangeSummary]?, Never>()
        let items: [DocumentChangeSummary]
        let session: AttentionPopoverSession
        let controller: AttentionQueueViewController
        let table: NSTableView
        let window: NSWindow
        private let openedNotes: OpenedNotes
        var opened: [UUID] { openedNotes.values }

        init() throws {
            _ = NSApplication.shared
            let projection = WindowWorkspaceProjectionController { throw DiscoverySearchExecutionError.workspaceUnavailable }
            projection.replaceCatalog(.init(generatedAt: Date(), notes: [], attention: [], graph: nil))
            let vaultID = UUID()
            items = (0..<2).map { ordinal in
                .init(
                    noteID: UUID(), vaultID: vaultID, role: .topicKnowledge, relativePath: "Topic-\(ordinal).md",
                    startingRevision: DocumentFingerprint(content: "Before"), endingRevision: DocumentFingerprint(content: "After"),
                    savedAt: Date(timeIntervalSince1970: Double(2 - ordinal)), baselineState: .known)
            }
            let opened = OpenedNotes()
            openedNotes = opened
            session = AttentionPopoverSession(
                presentation: AttentionPresentationState(),
                workspaceController: WindowWorkspaceController(workspaceStore: makeTestWorkspaceStore(), requestedTriptychID: nil),
                projectionController: projection,
                dependencies: .init(
                    documentChangeChanges: changes.eraseToAnyPublisher(),
                    documentChangeErrorChanges: Just<String?>(nil).eraseToAnyPublisher(),
                    refresh: {},
                    showDocumentChange: { change in
                        opened.values.append(change.noteID)
                        return true
                    }))
            changes.send(items)
            session.present()
            controller = AttentionQueueViewController(session: session)
            controller.preferredContentSize = NSSize(width: 420, height: 360)
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.setContentSize(NSSize(width: 420, height: 360))
            controller.view.layoutSubtreeIfNeeded()
            table = try #require(Self.findTable(controller.view))
            table.layoutSubtreeIfNeeded()
            #expect(table.numberOfRows == 3)
        }

        func present() { session.present() }
        func itemID(_ change: DocumentChangeSummary) -> String {
            "change:\(change.vaultID.uuidString.lowercased()):\(change.noteID.uuidString.lowercased())"
        }
        func close() {
            session.dismiss()
            window.contentViewController = nil
            window.close()
        }

        private static func findTable(_ view: NSView) -> NSTableView? {
            (view as? NSTableView) ?? view.subviews.lazy.compactMap(findTable).first
        }
    }

    @MainActor
    private final class OpenedNotes { var values: [UUID] = [] }

}
