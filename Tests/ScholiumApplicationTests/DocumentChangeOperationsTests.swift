import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Document Changes application", .serialized)
struct DocumentChangeOperationsTests {
    @Test("External saved edits accumulate across restart; review captures displayed ending only")
    func externalCumulativeReview() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let runtime = makeRuntime(fixture)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let sourceURL = fixture.analysesURL.appendingPathComponent("Agency.md")
        let original = try Data(contentsOf: sourceURL)
        let note = try #require(
            try await handle.snapshot()
                .document(id: fixture.analysisNoteID))
        let noteID = try #require(note.stableIdentity.resolvedID)
        #expect(try await handle.changes.pendingChanges().isEmpty)
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        let b = Data("# Agency\n\nFreedom enables action, with limits.\n".utf8)
        let c = Data("# Agency\n\nFreedom enables action, with limits and reasons.\n".utf8)
        try b.write(to: sourceURL, options: .atomic)
        let pendingB = try await handle.changes.pendingChanges()
        #expect(pendingB.count == 1)
        #expect(pendingB.first?.startingRevision == DocumentFingerprint(data: original))
        #expect(pendingB.first?.endingRevision == DocumentFingerprint(data: b))
        let displayedB = try await handle.changes.changeReview(noteID: noteID)
        #expect(displayedB.comparison?.startingRevision == DocumentFingerprint(data: original))
        #expect(displayedB.comparison?.endingRevision == DocumentFingerprint(data: b))

        try c.write(to: sourceURL, options: .atomic)
        let reviewedB = try await handle.changes.markReviewed(capture: displayedB.capture)
        #expect(reviewedB.endingRevision == DocumentFingerprint(data: b))
        let latestSnapshot = try await handle.snapshot()
        await handle.events.publishDerivedStateChanged(snapshot: latestSnapshot)
        let coalesced = try #require(await iterator.next())
        #expect(coalesced.snapshot.documentChangesGeneration == 1)
        #expect(try Data(contentsOf: sourceURL) == c)
        #expect(try await handle.changes.pendingChanges().first?.startingRevision == DocumentFingerprint(data: b))
        #expect(try await handle.changes.pendingChanges().first?.endingRevision == DocumentFingerprint(data: c))
        #expect(try await handle.changes.reviewedHistory().count == 1)
        await runtime.shutdown()

        let reopened = makeRuntime(fixture)
        let reopenedHandle = try await reopened.openWorkspace(id: fixture.assignment.id)
        #expect(try await reopenedHandle.changes.pendingChanges().first?.startingRevision == DocumentFingerprint(data: b))
        let displayedC = try await reopenedHandle.changes.changeReview(noteID: noteID)
        _ = try await reopenedHandle.changes.markReviewed(capture: displayedC.capture)
        #expect(try await reopenedHandle.changes.pendingChanges().isEmpty)
        #expect(try await reopenedHandle.changes.reviewedHistory().count == 2)
        try await reopenedHandle.changes.deleteReviewedHistory(ids: [reviewedB.id])
        #expect(try await reopenedHandle.changes.reviewedHistory().count == 1)
        #expect(try Data(contentsOf: sourceURL) == c)
        let authored = "# Agency\n\nThe researcher revises the account.\n"
        _ = try await reopenedHandle.documents.save(
            try await capturedSaveTarget(reopenedHandle, fixture.analysisNoteID, revision: DocumentFingerprint(data: c)),
            changeSet: .exactContent(authored))
        let pendingAuthored = try await reopenedHandle.changes.pendingChanges()
        #expect(pendingAuthored.first?.startingRevision == DocumentFingerprint(data: c))
        #expect(pendingAuthored.first?.endingRevision == DocumentFingerprint(data: Data(authored.utf8)))
        #expect(try Data(contentsOf: sourceURL) == Data(authored.utf8))
        await reopened.shutdown()
    }

    @Test("A new external Note is explicit, with no empty-file comparison")
    func newlyObservedNote() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let runtime = makeRuntime(fixture)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        #expect(try await handle.changes.pendingChanges().isEmpty)
        let file = fixture.topicsURL.appendingPathComponent("Fresh.md")
        let source = Data("# Fresh\n\nA new topic.\n".utf8)
        try source.write(to: file, options: .atomic)
        let pending = try await handle.changes.pendingChanges()
        let fresh = try #require(pending.first { $0.relativePath == "Fresh.md" })
        #expect(fresh.baselineState == .newDocument)
        #expect(fresh.startingRevision == nil)
        let review = try await handle.changes.changeReview(noteID: fresh.noteID)
        #expect(review.comparison == nil && review.startingSource == nil)
        #expect(review.endingSource == String(decoding: source, as: UTF8.self))
        await runtime.shutdown()
    }

    @Test("Receipt cleanup keeps uncertain evidence and an uncovered linked move")
    func receiptCleanupRequiresCompleteReviewedCoverage() async throws {
        let fixture = try await makeFixture()
        defer { fixture.remove() }
        let runtime = makeRuntime(fixture)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let services = await handle.services
        let reviews = try #require(services.documentReviewStore)
        let receipts = services.agentChangeStore
        let analysesVault = try #require(fixture.assignment.vault(for: .paperAnalysis))
        let topicsVault = try #require(fixture.assignment.vault(for: .topicKnowledge))
        let primaryID = UUID()
        let linkedID = UUID()
        let unchanged = Data("Exact source\n".utf8)
        let linkedBefore = Data("[[Old]]\n".utf8)
        let linkedAfter = Data("[[New]]\n".utf8)
        let primaryEffect = AgentNoteMoveEffect(
            noteID: primaryID, role: .sourceCorpus,
            source: .init(vaultID: analysesVault.id, relativePath: "Old.md"),
            destination: .init(vaultID: analysesVault.id, relativePath: "New.md"),
            beforeFingerprint: .init(data: unchanged),
            afterFingerprint: .init(data: unchanged), rewrittenOccurrences: 0
        )
        let linkedEffect = AgentNoteMoveEffect(
            noteID: linkedID, role: .topicKnowledge,
            source: .init(vaultID: topicsVault.id, relativePath: "Link.md"),
            destination: .init(vaultID: topicsVault.id, relativePath: "Link.md"),
            beforeFingerprint: .init(data: linkedBefore),
            afterFingerprint: .init(data: linkedAfter), rewrittenOccurrences: 1
        )
        let move = AgentMoveEvidence(
            primary: primaryEffect,
            linkedSources: [
                .init(
                    effect: linkedEffect,
                    beforeData: linkedBefore, afterData: linkedAfter)
            ]
        )
        let preparedMove = try await receipts.prepare(
            operation: .move, noteID: primaryID, role: .sourceCorpus,
            originalRelativePath: "Old.md", finalRelativePath: "New.md",
            beforeData: unchanged, afterData: unchanged, move: move
        )
        let confirmedMove = try await receipts.confirm(
            id: preparedMove.id,
            observedAfterFingerprint: primaryEffect.afterFingerprint,
            observedMoveFingerprints: [
                primaryID: primaryEffect.afterFingerprint,
                linkedID: linkedEffect.afterFingerprint,
            ]
        )
        try await reviews.initializeNew(noteID: primaryID, vaultID: analysesVault.id)
        try await reviews.initializeNew(noteID: linkedID, vaultID: topicsVault.id)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let primaryCapture = try await reviews.capture(
            noteID: primaryID, vaultID: analysesVault.id, role: .sourceCorpus,
            relativePath: "New.md", endingData: unchanged,
            receiptVersions: [.init(confirmedMove)]
        )
        _ = try await reviews.markReviewed(primaryCapture.token, at: oldDate)
        #expect(!(try await handle.reclaimReviewedOperationReceipts()))
        #expect(try await receipts.change(id: preparedMove.id).state == .confirmed)

        let pendingID = UUID()
        let uncertainID = UUID()
        let before = Data("A".utf8)
        let after = Data("B".utf8)
        let pending = try await receipts.prepare(
            operation: .update, noteID: pendingID, role: .topicKnowledge,
            originalRelativePath: "Pending.md", finalRelativePath: "Pending.md",
            beforeData: before, afterData: after
        )
        let uncertain = try await receipts.prepare(
            operation: .update, noteID: uncertainID, role: .topicKnowledge,
            originalRelativePath: "Uncertain.md", finalRelativePath: "Uncertain.md",
            beforeData: before, afterData: after
        )
        _ = try await receipts.markOutcomeUncertain(id: uncertain.id)

        let linkedCapture = try await reviews.capture(
            noteID: linkedID, vaultID: topicsVault.id, role: .topicKnowledge,
            relativePath: "Link.md", endingData: linkedAfter,
            receiptVersions: [.init(confirmedMove)]
        )
        _ = try await reviews.markReviewed(linkedCapture.token, at: oldDate)
        #expect(try await handle.reclaimReviewedOperationReceipts())
        await #expect(throws: AgentChangeError.self) {
            _ = try await receipts.change(id: preparedMove.id)
        }
        #expect(try await receipts.change(id: pending.id).state == .prepared)
        #expect(try await receipts.change(id: uncertain.id).state == .outcomeUncertain)
        await runtime.shutdown()
    }

    private func makeFixture() async throws -> ApplicationFixture {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/application-unit-state", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try await ApplicationFixture.make(rootURL: root)
    }

    private func makeRuntime(_ fixture: ApplicationFixture) -> WorkspaceRuntime {
        WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    assignments: [fixture.assignment],
                    defaultWorkspaceID: fixture.assignment.id
                )))
    }
}
