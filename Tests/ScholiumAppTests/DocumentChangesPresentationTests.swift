import AppKit
import ScholiumContracts
import SwiftUI
import Testing

@testable import ScholiumApp

@Suite("Document Changes presentation", .serialized)
@MainActor
struct DocumentChangesPresentationTests {
    @Test("The sheet never acknowledges a Note merely by showing or closing its comparison")
    func openingAndClosingDoesNotMarkReviewed() async throws {
        _ = NSApplication.shared
        let noteID = UUID()
        let vaultID = UUID()
        let source = "情绪 is fitting."
        let summary = DocumentChangeSummary(
            noteID: noteID, vaultID: vaultID, role: .topicKnowledge,
            relativePath: "情绪.md",
            startingRevision: DocumentFingerprint(content: "情绪 is apt."),
            endingRevision: DocumentFingerprint(content: source),
            savedAt: Date(), baselineState: .known
        )
        let capture = DocumentChangeCapture(
            id: UUID(), noteID: noteID, baselineID: UUID(),
            endingRevision: summary.endingRevision
        )
        var reviewReads = 0
        var marks = 0
        let host = NSHostingView(
            rootView: DocumentChangesView(
                scope: .note(noteID), invalidationRevision: 0,
                loadPending: { [summary] },
                loadReview: { selected in
                    #expect(selected == noteID)
                    reviewReads += 1
                    return DocumentChangeReview(
                        summary: summary, capture: capture, comparison: nil,
                        startingSource: nil, endingSource: source
                    )
                },
                loadHistory: { [] },
                loadHistoryDetail: { _ in throw CancellationError() },
                markReviewed: { _ in
                    marks += 1
                    throw CancellationError()
                },
                deleteHistory: { _ in Issue.record("No history record exists") },
                didChange: {}
            ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        try await wait { reviewReads > 0 }
        #expect(marks == 0)
        window.contentView = nil
        window.close()
        await Task.yield()
        #expect(marks == 0)
    }

    @Test("A sheet bound to one runtime rejects a later Triptych or activation")
    func routeBindingCannotRetarget() throws {
        let triptych = UUID()
        let original = TriptychRuntimeIdentity(triptychID: triptych, activationID: UUID())
        let replacement = TriptychRuntimeIdentity(triptychID: triptych, activationID: UUID())
        let other = TriptychRuntimeIdentity(triptychID: UUID(), activationID: UUID())
        let binding = DocumentChangesRouteBinding(
            runtimeIdentity: original, operations: EmptyChangesOperations()
        )
        _ = try binding.requireCurrent(original)
        #expect(throws: DocumentChangeError.self) { _ = try binding.requireCurrent(replacement) }
        #expect(throws: DocumentChangeError.self) { _ = try binding.requireCurrent(other) }
        #expect(throws: DocumentChangeError.self) { _ = try binding.requireCurrent(nil) }
    }

    private func wait(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !ready(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(ready())
    }
}

private struct EmptyChangesOperations: DocumentChangeUseCases {
    func pendingChanges() async throws -> [DocumentChangeSummary] { [] }
    func changeReview(noteID: UUID) async throws -> DocumentChangeReview {
        throw CancellationError()
    }
    func markReviewed(capture: DocumentChangeCapture) async throws -> ReviewedDocumentChange {
        throw CancellationError()
    }
    func reviewedHistory() async throws -> [ReviewedDocumentChange] { [] }
    func reviewedChange(id: UUID) async throws -> ReviewedDocumentChangeDetail {
        throw CancellationError()
    }
    func deleteReviewedHistory(ids: [UUID]) async throws {}
    func clearReviewedHistory() async throws {}
    func retention() async throws -> DocumentChangeRetention { .days90 }
    func setRetention(_ retention: DocumentChangeRetention) async throws {}
    func historyUsage() async throws -> DocumentChangeHistoryUsage {
        .init(count: 0, byteCount: 0, protectedByteCount: 0)
    }
}
