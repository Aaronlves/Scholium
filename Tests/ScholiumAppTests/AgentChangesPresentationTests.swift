import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Agent Changes native presentation", .serialized)
@MainActor
struct AgentChangesPresentationTests {
    @Test("Both history scopes use native single selection without reading or mutating on selection", arguments: [false, true])
    func nativeCollection(conversation: Bool) async throws {
        _ = NSApplication.shared
        let triptych = UUID()
        let changes = ["Reasons.md", "论证/Reasons.md", "研究/一个较长的哲学论证笔记标题.md"].enumerated().map { index, path in
            AgentChange(
                id: UUID(), triptychID: triptych, operation: .update, noteID: UUID(), role: .topicKnowledge,
                originalRelativePath: path, finalRelativePath: path, beforeFingerprint: nil, afterFingerprint: nil,
                state: .confirmed, createdAt: Date(timeIntervalSince1970: Double(index)), confirmedAt: nil, undoneAt: nil)
        }
        var reviewReads = 0
        let host = NSHostingView(
            rootView: AgentChangesView(
                scope: conversation ? .conversation(changes.map(\.id)) : .current,
                load: { changes },
                loadReview: { _ in
                    reviewReads += 1
                    throw CancellationError()
                },
                undo: { _ in Issue.record("Selecting history must never undo a change") }))
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        try await wait { self.find(NSTableView.self, in: host)?.numberOfRows == changes.count }
        let table = try #require(find(NSTableView.self, in: host))
        #expect(table.tableColumns.count == 3)
        #expect(table.usesAlternatingRowBackgroundColors && !table.allowsMultipleSelection)
        #expect(table.style != .sourceList)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        try await wait { table.selectedRow == 1 }
        #expect(reviewReads == 0)
        #expect(table.accessibilityLabel() == String(localized: conversation ? "Conversation Changes" : "Agent Changes"))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("contrast-dark", .accessibilityHighContrastDarkAqua)] {
            host.appearance = NSAppearance(named: appearance)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/agent-changes-review")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: output.appendingPathComponent("\(conversation ? "conversation" : "agent")-\(name).png"))
        }
    }

    @Test("Viewed records only a successfully displayed confirmed detail", arguments: [false, true])
    func viewedAfterDisplay(succeeds: Bool) async throws {
        _ = NSApplication.shared
        let suite = "Scholium-AgentChanges-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let change = AgentChange(
            id: UUID(), triptychID: UUID(), operation: .create, noteID: UUID(), role: .topicKnowledge,
            originalRelativePath: nil, finalRelativePath: "Created.md", beforeFingerprint: nil,
            afterFingerprint: DocumentFingerprint(content: "Current content"), state: .confirmed,
            createdAt: Date(), confirmedAt: Date(), undoneAt: nil)
        var continuation: CheckedContinuation<Void, Never>?
        var finished = false
        let host = NSHostingView(
            rootView: AgentChangesView(
                scope: .exact(change.id), load: { [change] },
                loadReview: { _ in
                    await withCheckedContinuation { continuation = $0 }
                    defer { finished = true }
                    if !succeeds { throw AgentChangeError.missing(change.id) }
                    return AgentChangeReview(
                        change: change, comparison: nil,
                        currentCreatedSource: "Current content", endingRevisionState: .current)
                }, undo: { _ in Issue.record("Displaying a detail must not undo it") }
            )
            .defaultAppStorage(defaults))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        try await wait { continuation != nil }
        #expect(AgentChangeViewedLedger(data: defaults.data(forKey: AgentChangeViewedLedger.key) ?? Data()).ids.isEmpty)
        continuation?.resume()
        try await wait { finished }
        if succeeds {
            try await wait { AgentChangeViewedLedger(data: defaults.data(forKey: AgentChangeViewedLedger.key) ?? Data()).ids.contains(change.id) }
        } else {
            await Task.yield()
            #expect(AgentChangeViewedLedger(data: defaults.data(forKey: AgentChangeViewedLedger.key) ?? Data()).ids.isEmpty)
        }
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
}
