import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Agent Change receipt presentation", .serialized)
@MainActor
struct AgentChangesPresentationTests {
    @Test("Opening a receipt never records cumulative review state", arguments: [false, true])
    func receiptDisplayDoesNotReview(succeeds: Bool) async throws {
        _ = NSApplication.shared
        let suite = "Scholium-AgentReceipt-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let change = AgentChange(
            id: UUID(), triptychID: UUID(), operation: .create, noteID: UUID(),
            role: .topicKnowledge, originalRelativePath: nil,
            finalRelativePath: "Created.md", beforeFingerprint: nil,
            afterFingerprint: DocumentFingerprint(content: "Current content"),
            state: .confirmed, createdAt: Date(), confirmedAt: Date(), undoneAt: nil
        )
        var continuation: CheckedContinuation<Void, Never>?
        var finished = false
        let host = NSHostingView(
            rootView: AgentChangeReceiptView(
                changeID: change.id,
                loadReview: { _ in
                    await withCheckedContinuation { continuation = $0 }
                    defer { finished = true }
                    if !succeeds { throw AgentChangeError.missing(change.id) }
                    return AgentChangeReview(
                        change: change, comparison: nil,
                        currentCreatedSource: "Current content",
                        endingRevisionState: .current
                    )
                },
                undo: { _ in Issue.record("Displaying a receipt must not undo it") }
            )
            .defaultAppStorage(defaults)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            continuation?.resume()
            window.contentView = nil
            window.close()
        }
        try await wait { continuation != nil }
        #expect(defaults.data(forKey: "scholium.agentChanges.viewedReceipts") == nil)
        continuation?.resume()
        continuation = nil
        try await wait { finished }
        #expect(defaults.data(forKey: "scholium.agentChanges.viewedReceipts") == nil)
    }

    private func wait(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !ready(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(ready())
    }
}
