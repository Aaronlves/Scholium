import AppKit
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Native research table geometry", .serialized)
@MainActor
struct NativeResearchTableTests {
    @Test("Native columns follow the viewport without user-created overflow", arguments: [false, true])
    func nativeViewportProbe(threeColumns: Bool) async throws {
        _ = NSApplication.shared
        let columns = definitions(threeColumns: threeColumns)
        let view = NativeResearchTableView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 300), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer {
            window.contentView = nil
            window.close()
        }
        let rows = [
            NativeResearchTable.Row(
                id: "a", cells: threeColumns ? ["Reasons.md", "Edited · Viewed", "Sep 14, 12:30"] : ["Reasons.md", "论证/行动理由"], help: "论证/Reasons.md"),
            NativeResearchTable.Row(
                id: "b", cells: threeColumns ? ["另一篇哲学研究笔记.md", "Created", "Sep 14, 12:31"] : ["另一篇哲学研究笔记.md", "Drafts/Research"], help: "Drafts/另一篇哲学研究笔记.md"),
        ]
        var selected: String?
        view.onSelection = { selected = $0 }
        view.update(columns: columns, rows: rows, selectedID: "a")
        view.layoutSubtreeIfNeeded()
        let table = view.table
        #expect(table.numberOfRows == 2 && !table.allowsMultipleSelection)
        #expect(table.usesAlternatingRowBackgroundColors && !view.hasHorizontalScroller)
        #expect(!table.allowsColumnResizing)
        assertNativeFits(view)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(selected == "b")

        let widths = table.tableColumns.map(\.width)
        view.update(columns: columns, rows: Array(rows.reversed()), selectedID: "b")
        view.layoutSubtreeIfNeeded()
        #expect(table.tableColumns.map(\.width) == widths)
        #expect(table.selectedRow == 0)
        #expect(view.table === table)

        for width in [CGFloat(560), 1100, 680] {
            window.setContentSize(NSSize(width: width, height: 300))
            view.layoutSubtreeIfNeeded()
            assertNativeFits(view)
        }
        view.table.isEnabled = false
        #expect(!view.selectionShouldChange(in: table))
        view.update(columns: columns, rows: [], selectedID: nil)
        #expect(table.numberOfRows == 0 && !table.usesAlternatingRowBackgroundColors)
        assertNativeFits(view)
    }

    private func definitions(threeColumns: Bool) -> [NativeResearchTable.Column] {
        if threeColumns {
            return [
                .init(id: "note", title: "Note"),
                .init(id: "change", title: "Change", width: 180),
                .init(id: "date", title: "Date", width: 145, secondary: true),
            ]
        }
        return [
            .init(id: "name", title: "Name"),
            .init(id: "folder", title: "Folder", width: 240, secondary: true),
        ]
    }

    private func assertNativeFits(_ view: NativeResearchTableView) {
        let width = view.contentSize.width
        #expect(abs(view.table.frame.width - width) < 0.01)
        if !view.table.tableColumns.isEmpty {
            let first = view.table.rect(ofColumn: 0)
            let last = view.table.rect(ofColumn: view.table.tableColumns.count - 1)
            #expect(first.minX >= 0 && last.maxX <= width)
            #expect(abs((width - last.maxX) - first.minX) < 1)
        }
    }
}
