import Foundation
import ScholiumContracts
@testable import ScholiumCore
import Testing

@Suite("Research Activity records")
struct ResearchActivityStoreTests {
    @Test("Settling a fingerprint is idempotent and creates one Settled event")
    func settlementIsIdempotent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchActivityStore(storageURL: fixture.support)
        let note = reference()
        let fingerprint = DocumentFingerprint(content: "# A note\n")

        let first = try await store.settle(
            note: note,
            fingerprint: fingerprint,
            rationale: "Stable for the current argument."
        )
        let second = try await store.settle(note: note, fingerprint: fingerprint)

        #expect(first == second)
        #expect(await store.allSettlements().count == 1)
        let events = await store.events(for: note.noteID)
        #expect(events.map(\.kind) == [.settled])
        #expect(events.first?.origin.title == "Astonishment and the practical option-space")
    }

    @Test("Only researcher Finish creates Commented after an agent reply")
    func commentExchangeFinishCreatesOneEvent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchActivityStore(storageURL: fixture.support)
        let note = reference()
        let fingerprint = DocumentFingerprint(content: "A selected passage")
        let anchor = ResearcherCommentAnchor(
            fingerprint: fingerprint,
            utf8Range: 0..<3,
            utf16Range: 0..<3,
            line: 1,
            endLine: 1,
            quotation: "A s"
        )
        let exchange = CommentExchange(
            note: note,
            anchor: anchor,
            turns: [CommentExchangeTurn(author: .researcher, text: "Can you clarify this?")]
        )
        _ = try await store.createExchange(exchange)
        #expect(await store.events(for: note.noteID).isEmpty)

        _ = try await store.appendExchangeTurn(
            exchangeID: exchange.id,
            turn: CommentExchangeTurn(author: .agent, text: "Here is a distinction.")
        )
        #expect(await store.events(for: note.noteID).isEmpty)
        #expect(await store.pendingStates(for: note.noteID).map(\.kind) == [.responseReady])

        _ = try await store.finishExchange(exchangeID: exchange.id)
        _ = try await store.finishExchange(exchangeID: exchange.id)
        #expect(await store.events(for: note.noteID).map(\.kind) == [.commented])
        #expect(await store.pendingStates(for: note.noteID).isEmpty)
    }

    @Test("Follow Up keeps one Comment exchange open until the latest agent reply is reviewed")
    func commentExchangeFollowUpRequiresLatestReply() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchActivityStore(storageURL: fixture.support)
        let note = reference()
        let fingerprint = DocumentFingerprint(content: "A selected passage")
        let anchor = ResearcherCommentAnchor(
            fingerprint: fingerprint,
            utf8Range: 0..<3,
            utf16Range: 0..<3,
            line: 1,
            endLine: 1,
            quotation: "A s"
        )
        let exchange = CommentExchange(
            note: note,
            anchor: anchor,
            turns: [CommentExchangeTurn(author: .researcher, text: "First question")]
        )
        _ = try await store.createExchange(exchange)
        _ = try await store.appendExchangeTurn(
            exchangeID: exchange.id,
            turn: CommentExchangeTurn(author: .agent, text: "First reply")
        )
        _ = try await store.appendExchangeTurn(
            exchangeID: exchange.id,
            turn: CommentExchangeTurn(author: .researcher, text: "Follow up")
        )

        await #expect(throws: CommentExchangeError.self) {
            _ = try await store.finishExchange(exchangeID: exchange.id)
        }
        #expect(await store.events(for: note.noteID).isEmpty)

        _ = try await store.appendExchangeTurn(
            exchangeID: exchange.id,
            turn: CommentExchangeTurn(author: .agent, text: "Second reply")
        )
        _ = try await store.finishExchange(exchangeID: exchange.id)
        #expect(await store.events(for: note.noteID).map(\.kind) == [.commented])
    }

    @Test("Discuss stays Response ready until the researcher finishes it")
    func discussionFinishCreatesOneEvent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchActivityStore(storageURL: fixture.support)
        let note = reference()
        let runID = UUID()

        _ = try await store.setPendingState(PendingResearchState(
            id: runID,
            noteID: note.noteID,
            kind: .responseReady,
            activityID: runID,
            route: .discuss
        ))
        #expect(await store.events(for: note.noteID).isEmpty)

        let first = try await store.finishDiscussion(note: note, runID: runID)
        let second = try await store.finishDiscussion(note: note, runID: runID)
        #expect(first.id == second.id)
        #expect(first.activityID == second.activityID)
        #expect(await store.events(for: note.noteID).map(\.kind) == [.discussed])
        #expect(await store.pendingStates(for: note.noteID).isEmpty)
    }

    @Test("Comment and Discuss responses remain independently actionable")
    func responseReadyRoutesDoNotSupersedeEachOther() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchActivityStore(storageURL: fixture.support)
        let note = reference()
        let commentID = UUID()
        let discussionID = UUID()

        _ = try await store.setPendingState(PendingResearchState(
            id: commentID,
            noteID: note.noteID,
            kind: .responseReady,
            activityID: commentID,
            route: .comment
        ))
        _ = try await store.setPendingState(PendingResearchState(
            id: discussionID,
            noteID: note.noteID,
            kind: .responseReady,
            activityID: discussionID,
            route: .discuss
        ))

        let pending = await store.pendingStates(for: note.noteID)
        #expect(Set(pending.compactMap(\.route)) == [.comment, .discuss])
    }

    @Test("Legacy private comments import as Annotation without creating activity")
    func legacyCommentsBecomeAnnotationsOnly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = PageAnnotationStore(storageURL: fixture.support)
        let activityStore = ResearchActivityStore(storageURL: fixture.support)
        let note = reference()
        let annotation = AnnotationRecord(
            id: UUID(),
            noteID: note.noteID,
            vaultID: note.note.vaultID,
            relativePath: note.note.relativePath,
            text: "Private reading note",
            anchor: ResearcherCommentAnchor(
                fingerprint: DocumentFingerprint(content: "note"),
                utf8Range: 0..<1,
                utf16Range: 0..<1,
                line: 1,
                endLine: 1,
                quotation: "n"
            )
        )

        try await store.importLegacyAnnotations([annotation])
        try await store.importLegacyAnnotations([annotation])

        let imported = await store.allAnnotations()
        #expect(imported.count == 1)
        #expect(imported.first?.id == annotation.id)
        #expect(imported.first?.text == annotation.text)
        #expect(imported.first?.anchor == annotation.anchor)
        #expect(await activityStore.events(for: note.noteID).isEmpty)
    }

    @Test("Page Annotation reopens beside the same passage without research activity")
    func pageAnnotationPersistsAcrossStoreReopen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let note = reference()
        let source = "A distinction worth keeping beside the page."
        let fingerprint = DocumentFingerprint(content: source)
        let annotation = AnnotationRecord(
            noteID: note.noteID,
            vaultID: note.note.vaultID,
            relativePath: note.note.relativePath,
            text: "Clarify which sense of distinction is intended.",
            anchor: ResearcherCommentAnchor(
                fingerprint: fingerprint,
                utf8Range: 2..<13,
                utf16Range: 2..<13,
                line: 1,
                endLine: 1,
                quotation: "distinction"
            )
        )

        let firstStore = PageAnnotationStore(storageURL: fixture.support)
        try await firstStore.add(annotation)

        let reopenedStore = PageAnnotationStore(storageURL: fixture.support)
        let reopened = await reopenedStore.annotations(for: note.noteID)
        #expect(reopened.count == 1)
        #expect(reopened.first?.id == annotation.id)
        #expect(reopened.first?.noteID == annotation.noteID)
        #expect(reopened.first?.text == annotation.text)
        #expect(reopened.first?.anchor == annotation.anchor)

        let activityStore = ResearchActivityStore(storageURL: fixture.support)
        #expect(await activityStore.events(for: note.noteID).isEmpty)
        #expect(await activityStore.pendingStates(for: note.noteID).isEmpty)
    }

    @Test("Activity key persists only as a digest and completion retries are idempotent")
    func keyedMultiTargetCompletion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = ResearchActivityStore(storageURL: fixture.support)
        let origin = reference()
        let related = ResearchActivityNoteReference(
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Works/Revised argument.md"
            ),
            role: .work,
            title: "Revised argument"
        )
        let authorization = try await store.issueGrant(
            origin: origin,
            writeScope: .selectedNotes,
            allowedTargets: [origin, related],
            startingFingerprints: [
                origin.noteID: DocumentFingerprint(content: "origin before"),
                related.noteID: DocumentFingerprint(content: "related before"),
            ]
        )
        let storedBytes = try Data(contentsOf: fixture.activityFile)
        let storedText = String(decoding: storedBytes, as: UTF8.self)
        #expect(!storedText.contains(authorization.activityKey))
        #expect(storedText.contains(authorization.grant.keyDigest))

        await #expect(throws: ResearchActivityGrantError.self) {
            _ = try await store.authorizeCompletion(
                activityID: authorization.grant.activityID,
                activityKey: "wrong-key"
            )
        }

        let report = MultiTargetCompletionReport(
            activityID: authorization.grant.activityID,
            candidateModifiedNotes: [origin.note, related.note],
            confirmedModifiedNotes: [origin, related],
            observedFingerprints: [
                origin.noteID: DocumentFingerprint(content: "origin after"),
                related.noteID: DocumentFingerprint(content: "related after"),
            ],
            summary: "Updated two authorized notes."
        )
        let events = [origin, related].map { note in
            ResearchActivityEvent(
                activityID: authorization.grant.activityID,
                note: note,
                kind: note.role == .work ? .revised : .developed,
                occurredAt: report.completedAt,
                origin: origin,
                confirmedModifiedNotes: report.confirmedModifiedNotes,
                unmodifiedNotes: report.unmodifiedNotes,
                researchRecordID: authorization.grant.activityID
            )
        }
        _ = try await store.completeGrant(
            activityID: authorization.grant.activityID,
            activityKey: authorization.activityKey,
            completionPayloadDigest: "same-payload",
            report: report,
            projectedEvents: events
        )
        _ = try await store.completeGrant(
            activityID: authorization.grant.activityID,
            activityKey: authorization.activityKey,
            completionPayloadDigest: "same-payload",
            report: report,
            projectedEvents: events
        )

        #expect(await store.allEvents().count == 2)
        #expect(await store.allPendingStates().count == 2)
        #expect(await store.grant(activityID: authorization.grant.activityID)?.state == .completed)
        await #expect(throws: ResearchActivityGrantError.self) {
            _ = try await store.completeGrant(
                activityID: authorization.grant.activityID,
                activityKey: authorization.activityKey,
                completionPayloadDigest: "different-payload",
                report: report,
                projectedEvents: events
            )
        }
    }

    @Test("Version one store is backed up before migration")
    func versionOneMigrationCreatesBackup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacy: [String: Any] = [
            "schemaVersion": 1,
            "events": [],
            "settlements": [],
            "annotations": [],
            "exchanges": [],
            "pendingStates": [],
            "grants": [],
            "migratedLegacyAnnotationIDs": [],
        ]
        try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
            .write(to: fixture.activityFile, options: .atomic)

        let store = ResearchActivityStore(storageURL: fixture.support)
        #expect(await store.healthError() == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.migrationBackup.path))

        let migrated = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fixture.activityFile)
        ) as? [String: Any]
        #expect(migrated?["schemaVersion"] as? Int == 2)
    }

    private func reference() -> ResearchActivityNoteReference {
        let vaultID = UUID()
        return ResearchActivityNoteReference(
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: "Topics/Astonishment.md"
            ),
            role: .topic,
            title: "Astonishment and the practical option-space"
        )
    }

    private final class Fixture {
        let root: URL
        let support: URL
        var activityFile: URL {
            support.appendingPathComponent("research-activity.json")
        }
        var migrationBackup: URL {
            support.appendingPathComponent("research-activity.v1.backup.json")
        }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            support = root.appendingPathComponent("records", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
