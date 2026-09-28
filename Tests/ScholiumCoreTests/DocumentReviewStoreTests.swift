import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Document review store", .serialized)
struct DocumentReviewStoreTests {
    @Test("A to B to C stays cumulative; stale window cannot roll baseline back")
    func cumulativeAndCrossWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let note = UUID()
        let vault = UUID()
        let a = Data("\u{feff}A\r\n".utf8)
        let b = Data("\u{feff}B\r\n".utf8)
        let c = Data("\u{feff}C\r\n".utf8)
        let store = try fixture.store()
        try await store.initializeExisting(noteID: note, vaultID: vault, source: a)
        #expect(try await store.baseline(noteID: note, vaultID: vault)?.fingerprint == DocumentFingerprint(data: a))
        let displayedB = try await store.capture(
            noteID: note, vaultID: vault, role: .topicKnowledge,
            relativePath: "Note.md", endingData: b
        )
        let staleC = try await store.capture(
            noteID: note, vaultID: vault, role: .topicKnowledge,
            relativePath: "Note.md", endingData: c
        )
        let first = try await store.markReviewed(displayedB.token)
        #expect(first.startingRevision == DocumentFingerprint(data: a))
        #expect(first.endingRevision == DocumentFingerprint(data: b))
        #expect(try await store.markReviewed(displayedB.token).id == first.id)
        await #expect(throws: DocumentChangeError.self) {
            _ = try await store.markReviewed(
                DocumentChangeCapture(
                    id: displayedB.token.id, noteID: note,
                    baselineID: UUID(), endingRevision: displayedB.token.endingRevision
                ))
        }
        await #expect(throws: DocumentChangeError.self) {
            _ = try await store.markReviewed(staleC.token)
        }
        let reopened = try fixture.store()
        #expect(try await reopened.baseline(noteID: note, vaultID: vault)?.fingerprint == DocumentFingerprint(data: b))
        let displayedC = try await reopened.capture(
            noteID: note, vaultID: vault, role: .topicKnowledge,
            relativePath: "Note.md", endingData: c
        )
        #expect(displayedC.startingData == b)
        _ = try await reopened.markReviewed(displayedC.token)
        #expect(try await reopened.history().count == 2)
        await #expect(throws: DocumentChangeError.self) {
            _ = try await reopened.capture(
                noteID: note, vaultID: vault, role: .topicKnowledge,
                relativePath: "Note.md", endingData: c
            )
        }
        let detail = try await reopened.historyDetail(id: first.id)
        #expect(detail.startingData == a && detail.endingData == b)
        try await reopened.deleteHistory(ids: [first.id])
        #expect(try await reopened.history().count == 1)
        #expect(try await reopened.baseline(noteID: note, vaultID: vault)?.fingerprint == DocumentFingerprint(data: c))
    }

    @Test("New and unreadable origins have no invented empty preimage")
    func honestOriginsAndNetZero() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let vault = UUID()
        let newID = UUID()
        let unknownID = UUID()
        let existingID = UUID()
        let source = Data("# Source\n".utf8)
        try await store.initializeNew(noteID: newID, vaultID: vault)
        try await store.initializeExisting(noteID: unknownID, vaultID: vault, source: nil)
        try await store.initializeExisting(noteID: existingID, vaultID: vault, source: source)
        let fresh = try await store.capture(
            noteID: newID, vaultID: vault, role: .sourceCorpus,
            relativePath: "New.md", endingData: source
        )
        #expect(fresh.baselineState == .newDocument && fresh.startingData == nil)
        let unknown = try await store.capture(
            noteID: unknownID, vaultID: vault, role: .sourceCorpus,
            relativePath: "Unknown.md", endingData: source
        )
        #expect(unknown.baselineState == .unavailable && unknown.startingData == nil)
        let reviewed = try await store.markReviewed(fresh.token)
        #expect(reviewed.wasNewDocument && reviewed.startingRevision == nil)
        await #expect(throws: DocumentChangeError.self) {
            _ = try await store.capture(
                noteID: existingID, vaultID: vault, role: .sourceCorpus,
                relativePath: "Existing.md", endingData: source
            )
        }
        await #expect(throws: DocumentChangeError.self) {
            try await store.initializeExisting(noteID: existingID, vaultID: UUID(), source: source)
        }
    }

    @Test("History expiration and clearing preserve active baseline and captures")
    func retentionPreservesPending() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let note = UUID()
        let vault = UUID()
        let a = Data("A".utf8)
        let b = Data("B".utf8)
        let c = Data("C".utf8)
        try await store.initializeExisting(noteID: note, vaultID: vault, source: a)
        let capture = try await store.capture(
            noteID: note, vaultID: vault, role: .topicKnowledge,
            relativePath: "Note.md", endingData: b
        )
        _ = try await store.markReviewed(capture.token, at: Date(timeIntervalSince1970: 1_000))
        let pendingC = try await store.capture(
            noteID: note, vaultID: vault, role: .topicKnowledge,
            relativePath: "Note.md", endingData: c
        )
        #expect(try await store.retention() == .days90)
        try await store.setRetention(.days30)
        #expect(try await store.expireHistory(now: Date(timeIntervalSince1970: 1_000 + 31 * 86_400)))
        #expect(try await store.history().isEmpty)
        #expect(try await store.baseline(noteID: note, vaultID: vault)?.fingerprint == DocumentFingerprint(data: b))
        #expect(try await store.markReviewed(pendingC.token).endingRevision == DocumentFingerprint(data: c))
        try await store.clearHistory()
        #expect(try await store.historyUsage().count == 0)
        #expect(try await store.baseline(noteID: note, vaultID: vault)?.fingerprint == DocumentFingerprint(data: c))
    }

    @Test("Only receipt versions captured with reviewed source receive age-based coverage")
    func explicitReceiptFrontierAndRetention() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let vault = UUID()
        let note = UUID()
        let old = change(noteID: note, state: .confirmed)
        let later = change(noteID: note, state: .confirmed)
        let oldVersion = DocumentReviewStore.ReceiptVersion(old)
        let laterVersion = DocumentReviewStore.ReceiptVersion(later)
        try await store.initializeExisting(
            noteID: note, vaultID: vault, source: Data("A".utf8),
            receiptVersions: [oldVersion]
        )
        // The displayed B snapshot has only the old and later receipts.
        // A confirmation or Undo that arrives after capture has a different
        // version and cannot inherit this batch's coverage.
        let displayed = try await store.capture(
            noteID: note, vaultID: vault, role: .topicKnowledge,
            relativePath: "Note.md", endingData: Data("B".utf8),
            receiptVersions: [oldVersion, laterVersion]
        )
        let reviewedAt = Date(timeIntervalSince1970: 1_000)
        let batch = try await store.markReviewed(displayed.token, at: reviewedAt)
        let muchLater = Date(timeIntervalSince1970: 1_000 + 91 * 86_400)
        #expect(
            !(try await store.hasReclaimableCoverage(
                noteID: note, vaultID: vault, receipt: oldVersion, now: muchLater
            )))
        #expect(
            try await store.hasReclaimableCoverage(
                noteID: note, vaultID: vault, receipt: laterVersion, now: muchLater
            ))
        let undone = change(id: later.id, noteID: note, state: .undone)
        #expect(
            !(try await store.hasReclaimableCoverage(
                noteID: note, vaultID: vault,
                receipt: DocumentReviewStore.ReceiptVersion(undone), now: muchLater
            )))
        try await store.deleteHistory(ids: [batch.id])
        try await store.setRetention(.forever)
        #expect(
            !(try await store.hasReclaimableCoverage(
                noteID: note, vaultID: vault, receipt: laterVersion, now: muchLater
            )))
        try await store.setRetention(.days90)
        #expect(
            !(try await store.hasReclaimableCoverage(
                noteID: note, vaultID: vault, receipt: laterVersion,
                now: Date(timeIntervalSince1970: 1_000 + 10 * 86_400)
            )))
    }

    @Test("A multi-Note receipt needs aged review coverage for every affected Note")
    func linkedReceiptCoverage() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let vault = UUID()
        let first = UUID()
        let second = UUID()
        let moveVersion = DocumentReviewStore.ReceiptVersion(
            change(
                noteID: first, state: .confirmed
            ))
        for note in [first, second] {
            try await store.initializeExisting(noteID: note, vaultID: vault, source: Data("A".utf8))
        }
        let oldReview = Date(timeIntervalSince1970: 1_000)
        let now = Date(timeIntervalSince1970: 1_000 + 91 * 86_400)
        let firstCapture = try await store.capture(
            noteID: first, vaultID: vault, role: .sourceCorpus,
            relativePath: "First.md", endingData: Data("B".utf8),
            receiptVersions: [moveVersion]
        )
        _ = try await store.markReviewed(firstCapture.token, at: oldReview)
        #expect(
            try await store.hasReclaimableCoverage(
                noteID: first, vaultID: vault, receipt: moveVersion, now: now
            ))
        #expect(
            !(try await store.hasReclaimableCoverage(
                noteID: second, vaultID: vault, receipt: moveVersion, now: now
            )))
        let secondCapture = try await store.capture(
            noteID: second, vaultID: vault, role: .sourceCorpus,
            relativePath: "Second.md", endingData: Data("B".utf8),
            receiptVersions: [moveVersion]
        )
        _ = try await store.markReviewed(secondCapture.token, at: oldReview)
        #expect(
            try await store.hasReclaimableCoverage(
                noteID: second, vaultID: vault, receipt: moveVersion, now: now
            ))
    }

    private func change(
        id: UUID = UUID(), noteID: UUID,
        state: AgentChangeRecoveryState
    ) -> AgentChange {
        AgentChange(
            id: id, triptychID: UUID(), operation: .update,
            noteID: noteID, role: .topicKnowledge,
            originalRelativePath: "Note.md", finalRelativePath: "Note.md",
            beforeFingerprint: .init(data: Data("A".utf8)),
            afterFingerprint: .init(data: Data("B".utf8)),
            state: state, createdAt: Date(timeIntervalSince1970: 100),
            confirmedAt: Date(timeIntervalSince1970: 101),
            undoneAt: state == .undone ? Date(timeIntervalSince1970: 102) : nil
        )
    }

    private struct Fixture {
        let root: URL
        let triptychID = UUID()

        init() throws {
            root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".build/core-unit-state", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func store() throws -> DocumentReviewStore {
            try DocumentReviewStore(applicationSupportURL: root, triptychID: triptychID)
        }

        func dispose() { try? FileManager.default.removeItem(at: root) }
    }
}
