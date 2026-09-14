import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Note destination presentation", .serialized)
@MainActor
struct NoteRestructurePresentationTests {
    @Test("Native destination rows remain single-select and striped through filtering and reflow", arguments: [false, true])
    func nativeDestinationPicker(merge: Bool) async throws {
        _ = NSApplication.shared
        let vault = UUID()
        func target(_ path: String) -> NoteMutationTarget {
            .init(documentID: .init(vaultID: vault, relativePath: path), stableNoteID: UUID(), revision: .init(content: "Fixture"))
        }
        let destinations = [
            "论证/Reasons.md", "解释/Reasons.md", "自由意志/实践理由与行动的可理解性.md",
            "Drafts/Very long note title about philosophical argument and interpretation.md",
            "Research/Working Notes/Objections and Replies.md", "Root note.md",
        ].map(target)
        let request = WindowNoteRestructureRequest(
            source: target("议题/Source note.md"), selectionUTF8: merge ? nil : 0..<5,
            action: merge ? nil : .move, destinations: destinations)
        let host = NSHostingView(
            rootView: NoteRestructureView(
                request: request,
                prepare: { _ in throw CancellationError() },
                commit: { _ in Issue.record("Choosing a target must not commit a mutation") }))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        try await wait { self.find(NSTableView.self, in: host)?.numberOfRows == destinations.count }
        let table = try #require(find(NSTableView.self, in: host))
        let search = try #require(find(NSSearchField.self, in: host))
        #expect(table.tableColumns.count == 2)
        #expect(table.usesAlternatingRowBackgroundColors)
        #expect(!table.allowsMultipleSelection && table.style != .sourceList)
        #expect(search.maximumRecents == 0)
        try await capture(host, name: "\(merge ? "merge" : "move")-light", appearance: .aqua)

        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        try await wait { table.selectedRow == 0 }
        search.stringValue = "解释"
        search.sendAction(search.action, to: search.target)
        try await wait { table.numberOfRows == 1 && table.selectedRow == -1 }
        #expect(find(NSTableView.self, in: host) === table)
        #expect(find(NSSearchField.self, in: host) === search)

        search.stringValue = "not-a-destination"
        search.sendAction(search.action, to: search.target)
        try await wait { table.numberOfRows == 0 }
        window.setContentSize(NSSize(width: 560, height: 420))
        try await capture(host, name: "\(merge ? "merge" : "move")-empty-dark", appearance: .darkAqua)
        search.stringValue = ""
        search.sendAction(search.action, to: search.target)
        try await wait { table.numberOfRows == destinations.count }
        try await capture(host, name: "\(merge ? "merge" : "move")-narrow-contrast", appearance: .accessibilityHighContrastAqua)
        #expect(table.usesAlternatingRowBackgroundColors && table.selectedRow == -1)
        #expect(search.frame.width > 0 && search.frame.maxX <= host.bounds.width)
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    private func wait(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !ready(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(ready())
    }

    private func capture(_ host: NSView, name: String, appearance: NSAppearance.Name) async throws {
        host.appearance = NSAppearance(named: appearance)
        host.window?.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/note-picker-review")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
    }
}
