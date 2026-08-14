import Foundation
import ScholiumContracts
@testable import ScholiumCore
import Testing

@Suite("Portable Research Record storage v1/schema 9 and Local Execution schema 12")
struct ResearchRecordV1StoresTests {
    @Test("Portable Record maps a primitive lock failure to its store error")
    func portableStoreMapsPrimitiveLockFailure() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let lockURL = fixture.triptychSupport.appendingPathComponent(
            "portable-records-v1.lock",
            isDirectory: false
        )
        try FileManager.default.createSymbolicLink(
            at: lockURL,
            withDestinationURL: fixture.root.appendingPathComponent("substituted-lock")
        )

        do {
            _ = try fixture.portableStore()
            Issue.record("Expected the portable Record owner to reject the substituted lock.")
        } catch let error as ResearchRecordStoreV1Error {
            guard case .unsafeStore = error else {
                Issue.record("Unexpected portable store error: \(error)")
                return
            }
        }
    }

    @Test("Portable Settle exposes typed commit uncertainty after rename")
    func portableSettlementMapsPostRenameUncertainty() async throws {
        enum InjectedFailure: Error { case afterRename }
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let noteID = UUID()
        let fingerprint = DocumentFingerprint(content: "settled")
        await store.setPostCommitFaultForTesting { _ in
            throw InjectedFailure.afterRename
        }

        do {
            _ = try await store.settle(
                noteID: noteID,
                fingerprint: fingerprint,
                rationale: "This replacement crossed rename."
            )
            Issue.record("Expected portable Settle commit uncertainty.")
        } catch let error as ResearchRecordStoreV1Error {
            guard case .replacementCommitUncertain = error else {
                Issue.record("Unexpected portable Settle error: \(error)")
                return
            }
        }
        let listing = try await store.settlementListing()
        #expect(listing.issues.isEmpty)
        #expect(listing.settlements.map(\.fingerprint) == [fingerprint])
    }

    @Test("Portable records commit one file and recover around abandoned staging files")
    func portableAtomicWriteAndCrashRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let record = try makePortableRecord()

        let stored = try await store.createFinishedRecord(record)
        let recordURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        #expect(FileManager.default.fileExists(atPath: recordURL.path))
        #expect(stored.id == record.id)

        let abandoned = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent(".scholium-pending-crashed-run")
        try Data("partial".utf8).write(to: abandoned)
        let reopened = try fixture.portableStore()
        let listing = try await reopened.listing()
        #expect(listing.records.map(\.id) == [record.id])
        #expect(listing.issues.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(try await reopened.record(id: record.id) == stored)
    }

    @Test("Record listings fingerprint the exact persisted JSON bytes")
    func portableListingFingerprintsExactBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let record = try makePortableRecord()
        _ = try await store.createFinishedRecord(record)
        let recordURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        let canonicalBytes = try Data(contentsOf: recordURL)
        var exactBytes = canonicalBytes
        exactBytes.append(contentsOf: Data("\n ".utf8))
        try exactBytes.write(to: recordURL)

        let listing = try await store.listing()
        let revision = try #require(listing.revisions.first)

        #expect(listing.issues.isEmpty)
        #expect(revision.record == record)
        #expect(revision.fingerprint == DocumentFingerprint(data: exactBytes))
        #expect(revision.fingerprint != DocumentFingerprint(data: canonicalBytes))
        #expect(record.schemaVersion == PortableResearchRecord.currentSchemaVersion)
    }

    @Test("Record listing order and source manifests are input-order independent")
    func portableListingOrderAndManifestAreStable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let first = try makePortableRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        )
        let second = try makePortableRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAB")!
        )
        _ = try await store.createFinishedRecord(second)
        _ = try await store.createFinishedRecord(first)

        let listing = try await store.listing()
        let reversed = PortableResearchRecordListing(
            revisions: Array(listing.revisions.reversed()),
            issues: listing.issues
        )

        #expect(listing.revisions.map(\.id) == [first.id, second.id])
        #expect(reversed.revisions == listing.revisions)
        #expect(reversed.sourceManifestHash == listing.sourceManifestHash)
    }

    @Test("Disposition and researcher note replace only one recommendation occurrence")
    func recommendationMutationPreservesRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let first = try makeRecommendation(ordinal: 0)
        let second = try makeRecommendation(
            ordinal: 1,
            citation: "A second reading lead"
        )
        let record = try makePortableRecord(
            actionID: .analyze,
            recommendations: [first, second]
        )
        _ = try await store.createFinishedRecord(record)

        let handled = try await store.setRecommendationDisposition(
            .handled,
            recommendationID: first.id,
            recordID: record.id,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        #expect(handled.literatureRecommendations[0].disposition.status == .handled)
        #expect(handled.literatureRecommendations[0].disposition.researcherNote == nil)
        #expect(handled.literatureRecommendations[1] == second)
        #expect(handled.statements == record.statements)
        #expect(handled.title == record.title)

        let noted = try await store.setRecommendationNote(
            "Compare its account of the objection.",
            recommendationID: first.id,
            recordID: record.id,
            updatedAt: Date(timeIntervalSince1970: 40)
        )
        #expect(noted.literatureRecommendations[0].disposition.status == .handled)
        #expect(
            noted.literatureRecommendations[0].disposition.researcherNote
                == "Compare its account of the objection."
        )
        #expect(noted.literatureRecommendations[1] == second)
        #expect(try await store.record(id: record.id) == noted)

        let recordURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        let exactBytesBeforeRefusal = try Data(contentsOf: recordURL)
        await #expect(throws: ResearchLiteratureRecommendationError.self) {
            _ = try await store.setRecommendationNote(
                "private=/Users/researcher/Research Notes.txt",
                recommendationID: first.id,
                recordID: record.id,
                updatedAt: Date(timeIntervalSince1970: 50)
            )
        }
        #expect(try Data(contentsOf: recordURL) == exactBytesBeforeRefusal)
        #expect(try await store.record(id: record.id) == noted)
    }

    @Test("Recommendation replacement distinguishes pre-commit failure from uncertainty")
    func recommendationReplacementFailurePhases() async throws {
        enum InjectedFailure: Error { case fault }
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let recommendation = try makeRecommendation(ordinal: 0)
        let record = try makePortableRecord(
            actionID: .analyze,
            recommendations: [recommendation]
        )
        _ = try await store.createFinishedRecord(record)

        await store.setPreCommitFaultForTesting { _ in throw InjectedFailure.fault }
        do {
            _ = try await store.setRecommendationDisposition(
                .handled,
                recommendationID: recommendation.id,
                recordID: record.id
            )
            Issue.record("Expected a typed pre-commit failure.")
        } catch let error as ResearchRecordStoreV1Error {
            guard case .replacementNotCommitted = error else {
                Issue.record("Unexpected replacement error: \(error)")
                return
            }
        }
        #expect(try await store.record(id: record.id) == record)

        await store.setPreCommitFaultForTesting(nil)
        await store.setPostCommitFaultForTesting { _ in throw InjectedFailure.fault }
        do {
            _ = try await store.setRecommendationDisposition(
                .handled,
                recommendationID: recommendation.id,
                recordID: record.id,
                updatedAt: Date(timeIntervalSince1970: 30)
            )
            Issue.record("Expected typed post-commit uncertainty.")
        } catch let error as ResearchRecordStoreV1Error {
            guard case .replacementCommitUncertain = error else {
                Issue.record("Unexpected replacement error: \(error)")
                return
            }
        }
        let committed = try await store.record(id: record.id)
        #expect(committed.literatureRecommendations[0].disposition.status == .handled)
    }

    @Test("Portable record permanent deletion is bounded to the selected record")
    func portableRecordPermanentDeletionIsBounded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let record = try makePortableRecord()
        let unrelated = try makePortableRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAB")!
        )
        _ = try await store.createFinishedRecord(record)
        _ = try await store.createFinishedRecord(unrelated)
        let manifestBeforeDeletion = try await store.listing().sourceManifestHash
        let recordsURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        #expect(try await store.deletePermanently(id: record.id) == record)
        #expect(!FileManager.default.fileExists(atPath: recordsURL.path))
        let listingAfterDeletion = try await store.listing()
        #expect(listingAfterDeletion.records == [unrelated])
        #expect(listingAfterDeletion.revisions.map(\.id) == [unrelated.id])
        #expect(listingAfterDeletion.sourceManifestHash != manifestBeforeDeletion)
        #expect(try await store.record(id: unrelated.id) == unrelated)
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.record(id: record.id)
        }
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.createFinishedRecord(record)
        }
        let reopened = try fixture.portableStore()
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await reopened.createFinishedRecord(record)
        }
    }

    @Test("Permanent deletion and completion repair cannot race a Record back into existence")
    func concurrentPermanentDeletionAndRepairRemainDeleted() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let deletingStore = try fixture.portableStore()
        let repairingStore = try fixture.portableStore()
        let record = try makePortableRecord(
            actionID: .analyze,
            recommendations: [try makeRecommendation(ordinal: 0)]
        )
        _ = try await deletingStore.createFinishedRecord(record)

        async let deletedRecord = deletingStore.deletePermanently(id: record.id)
        async let repairWonBeforeDeletion: Bool = {
            do {
                _ = try await repairingStore.createFinishedRecord(record)
                return true
            } catch ResearchRecordStoreV1Error.recordPermanentlyDeleted(let id)
                where id == record.id {
                return false
            }
        }()
        let (deleted, _) = try await (deletedRecord, repairWonBeforeDeletion)

        #expect(deleted == record)
        #expect(try await deletingStore.listing().records.isEmpty)
        let reopened = try fixture.portableStore()
        do {
            _ = try await reopened.createFinishedRecord(record)
            Issue.record("A completion repair recreated a permanently deleted Record.")
        } catch ResearchRecordStoreV1Error.recordPermanentlyDeleted(let id) {
            #expect(id == record.id)
        }
    }

    @Test("One corrupt portable file does not hide valid records")
    func portableCorruptionIsIsolated() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let record = try makePortableRecord()
        _ = try await store.createFinishedRecord(record)
        let cleanListing = try await store.listing()
        let recordsURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
        let corruptURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee.json")
        try Data("{\"schema_version\":1,".utf8).write(to: corruptURL)
        let mismatchURL = recordsURL.appendingPathComponent(
            "ffffffff-ffff-ffff-ffff-ffffffffffff.json"
        )
        let validRecordURL = recordsURL.appendingPathComponent(
            record.id.uuidString.lowercased() + ".json"
        )
        try Data(contentsOf: validRecordURL).write(to: mismatchURL)

        let listing = try await store.listing()
        #expect(listing.records.map(\.id) == [record.id])
        #expect(listing.revisions.map(\.id) == [record.id])
        #expect(listing.issues.count == 2)
        #expect(
            Set(listing.issues.map(\.fileName))
                == Set([corruptURL.lastPathComponent, mismatchURL.lastPathComponent])
        )
        #expect(listing.sourceManifestHash == cleanListing.sourceManifestHash)
    }

    @Test("An interrupted permanent-deletion rename restores on reopen")
    func interruptedPermanentDeletionRenameRecovers() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let record = try makePortableRecord()
        _ = try await store.createFinishedRecord(record)
        let fileName = record.id.uuidString.lowercased() + ".json"
        let records = fixture.control.appendingPathComponent(
            "research-records/v1/records",
            isDirectory: true
        )
        try FileManager.default.moveItem(
            at: records.appendingPathComponent(fileName),
            to: records.appendingPathComponent(".scholium-deleting-\(fileName)")
        )

        let reopened = try fixture.portableStore()
        #expect(try await reopened.record(id: record.id) == record)
        #expect(try await reopened.listing().issues.isEmpty)
    }

    @Test("Lifecycle post-commit uncertainty reconciles exact deletion state")
    func lifecyclePostCommitUncertaintyReconciles() async throws {
        enum InjectedFailure: Error { case afterCommit }
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let record = try makePortableRecord()
        _ = try await store.createFinishedRecord(record)

        await store.setPostCommitFaultForTesting { _ in
            throw InjectedFailure.afterCommit
        }
        #expect(try await store.deletePermanently(id: record.id) == record)
        let reopened = try fixture.portableStore()
        #expect(try await reopened.listing().records.isEmpty)
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await reopened.createFinishedRecord(record)
        }
    }

    @Test("Deletion retries durably fence a marker commit uncertainty before unlinking")
    func deletionMarkerCommitUncertaintyRetainsThenFencesRecord() async throws {
        enum InjectedFailure: Error { case afterMarkerRename }
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let record = try makePortableRecord()
        _ = try await store.createFinishedRecord(record)

        await store.setRecordDeletionMarkerPostCommitFaultForTesting { _ in
            throw InjectedFailure.afterMarkerRename
        }
        do {
            _ = try await store.deletePermanently(id: record.id)
            Issue.record("Expected marker commit uncertainty before Record deletion.")
        } catch let error as ResearchRecordStoreV1Error {
            guard case .lifecycleCommitUncertain = error else {
                Issue.record("Unexpected lifecycle error: \(error)")
                return
            }
        }
        #expect(try await store.record(id: record.id) == record)

        await store.setRecordDeletionMarkerPostCommitFaultForTesting(nil)
        #expect(try await store.deletePermanently(id: record.id) == record)
        let reopened = try fixture.portableStore()
        do {
            _ = try await reopened.createFinishedRecord(record)
            Issue.record("Repair bypassed a durable permanent-deletion tombstone.")
        } catch ResearchRecordStoreV1Error.recordPermanentlyDeleted(let id) {
            #expect(id == record.id)
        }
    }

    @Test("Concurrent store instances make one idempotent record")
    func concurrentPortableCreateIsIdempotent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try fixture.portableStore()
        let second = try fixture.portableStore()
        let record = try makePortableRecord()

        async let firstResult = first.createFinishedRecord(record)
        async let secondResult = second.createFinishedRecord(record)
        let results = try await [firstResult, secondResult]

        #expect(results.allSatisfy { $0.id == record.id })
        let listing = try await first.listing()
        #expect(listing.records.count == 1)
        #expect(listing.issues.isEmpty)
    }

    @Test("Finish moves one active Discussion into one idempotent record")
    func discussionFinishIsOneRecoverableTransition() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let discussion = try makePortableDiscussion()
        _ = try await store.createActiveDiscussion(discussion)
        let agent = try PortableResearchStatement(
            author: .agent,
            kind: .discussionTurn,
            attribution: "Research Agent",
            text: "The residual pressure remains open.",
            createdAt: Date(timeIntervalSince1970: 12)
        )
        let active = try await store.appendDiscussionStatement(
            agent,
            to: discussion.id,
            at: Date(timeIntervalSince1970: 12)
        )

        let record = try await store.finishDiscussion(
            id: discussion.id,
            participatingNotes: active.participatingNotes,
            finishedAt: Date(timeIntervalSince1970: 20)
        )
        let repeated = try await store.finishDiscussion(
            id: discussion.id,
            participatingNotes: active.participatingNotes,
            finishedAt: Date(timeIntervalSince1970: 30)
        )

        #expect(record == repeated)
        #expect(record.kind == .discussion)
        #expect(record.statements.count == 2)
        #expect(try await store.activeDiscussions().discussions.isEmpty)
        #expect(try await store.listing().records == [record])
    }

    @Test("Interrupted Discussion finish reconciles the exact active-record pair")
    func discussionFinishRecoveryRemovesOnlyExactDuplicate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let discussion = try makePortableDiscussion()
        _ = try await store.createActiveDiscussion(discussion)
        let record = try discussion.finishedRecord(
            participatingNotes: discussion.participatingNotes,
            finishedAt: Date(timeIntervalSince1970: 20)
        )
        _ = try await store.createFinishedRecord(record)

        let reopened = try fixture.portableStore()
        #expect(try await reopened.activeDiscussions().discussions.isEmpty)
        #expect(try await reopened.record(id: discussion.id) == record)
    }

    @Test("Passage anchors reattach only at one reliable source location")
    func discussionPassageDriftIsBounded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let unique = try makePortableDiscussion(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            source: "claim"
        )
        _ = try await store.createActiveDiscussion(unique)
        let reattached = try await store.reconcileDiscussionPassages(
            id: unique.id,
            primaryDocument: NoteDocument(
                relativePath: "Topic.md",
                rawContent: "prefix claim suffix"
            )
        )
        #expect(reattached.passage?.state == .attached)
        #expect(reattached.passage?.fingerprint == DocumentFingerprint(
            content: "prefix claim suffix"
        ))
        _ = try await store.finishDiscussion(
            id: unique.id,
            participatingNotes: reattached.participatingNotes,
            finishedAt: Date(timeIntervalSince1970: 20)
        )

        let ambiguous = try makePortableDiscussion(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            source: "claim"
        )
        _ = try await store.createActiveDiscussion(ambiguous)
        let detached = try await store.reconcileDiscussionPassages(
            id: ambiguous.id,
            primaryDocument: NoteDocument(
                relativePath: "Topic.md",
                rawContent: "claim and claim"
            )
        )
        #expect(detached.passage?.state == .needsReattachment)
        #expect(detached.passage?.fingerprint == ambiguous.passage?.fingerprint)
    }

    @Test("Permanent deletion purges active drafts and tombstones finished participants")
    func discussionDeletionPreservesFinishedRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let finishedDraft = try makePortableDiscussion(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        )
        _ = try await store.createActiveDiscussion(finishedDraft)
        let finished = try await store.finishDiscussion(
            id: finishedDraft.id,
            participatingNotes: finishedDraft.participatingNotes,
            finishedAt: Date(timeIntervalSince1970: 20)
        )
        let active = try makePortableDiscussion()
        _ = try await store.createActiveDiscussion(active)

        let deletedNoteID = active.primaryNoteID
        try await store.handlePermanentDeletion(noteIDs: [deletedNoteID])

        #expect(try await store.activeDiscussions().discussions.isEmpty)
        let retained = try await store.record(id: finished.id)
        #expect(retained.statements == finished.statements)
        #expect(retained.fidelityCompletion == finished.fidelityCompletion)
        #expect(retained.participatingNotes.first {
            $0.noteID == deletedNoteID
        }?.isTombstone == true)
        #expect(retained.participatingNotes.first {
            $0.noteID != deletedNoteID
        }?.isTombstone == false)
    }

    @Test("Only one active Discussion may own a primary Note")
    func activeDiscussionPrimaryNoteIsUniqueAcrossStoreInstances() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstStore = try fixture.portableStore()
        let secondStore = try fixture.portableStore()
        let first = try makePortableDiscussion()
        let second = try makePortableDiscussion(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        )

        _ = try await firstStore.createActiveDiscussion(first)
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await secondStore.createActiveDiscussion(second)
        }
        let listing = try await firstStore.activeDiscussions()
        #expect(listing.issues.isEmpty)
        #expect(listing.discussions.map(\.id) == [first.id])
    }

    @Test("Synced duplicate primary Discussions fail listing health")
    func syncedDuplicatePrimaryDiscussionIsAnIssue() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let first = try makePortableDiscussion()
        let second = try makePortableDiscussion(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        )
        _ = try await store.createActiveDiscussion(first)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let syncedURL = store.storageURL
            .appendingPathComponent("active", isDirectory: true)
            .appendingPathComponent(second.id.uuidString.lowercased() + ".json")
        try encoder.encode(second).write(to: syncedURL, options: .atomic)

        let listing = try await store.activeDiscussions()
        #expect(listing.discussions.count == 2)
        #expect(listing.issues.count == 2)
        #expect(listing.issues.allSatisfy {
            $0.reason.contains("multiple active Discussions")
        })
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.activeDiscussion(id: first.id)
        }
        let reply = try PortableResearchStatement(
            author: .agent,
            kind: .discussionTurn,
            attribution: "Synthetic Agent",
            text: "This must not be appended while the primary identity is ambiguous."
        )
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.appendDiscussionStatement(reply, to: first.id)
        }
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.finishDiscussion(
                id: first.id,
                participatingNotes: first.participatingNotes
            )
        }
    }

    @Test("Deletion marker and active creation share one cross-process gate")
    func deletionMarkerBlocksAnotherStoreInstance() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let deletingStore = try fixture.portableStore()
        let creatingStore = try fixture.portableStore()
        let discussion = try makePortableDiscussion()

        try await deletingStore.markNoteDeletionStarted(
            noteIDs: [discussion.primaryNoteID]
        )
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await creatingStore.createActiveDiscussion(discussion)
        }
        try await deletingStore.clearNoteDeletionMarkers(
            noteIDs: [discussion.primaryNoteID]
        )
        _ = try await creatingStore.createActiveDiscussion(discussion)
    }

    @Test("Settle updates one portable current judgment per Note")
    func settlementIsCurrentStateNotHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let noteID = UUID()
        let firstRevision = DocumentFingerprint(content: "first")
        let secondRevision = DocumentFingerprint(content: "second")

        let first = try await store.settle(
            noteID: noteID,
            fingerprint: firstRevision,
            rationale: "Current working basis.",
            settledAt: Date(timeIntervalSince1970: 10)
        )
        let repeated = try await store.settle(
            noteID: noteID,
            fingerprint: firstRevision,
            rationale: nil,
            settledAt: Date(timeIntervalSince1970: 20)
        )
        let replacement = try await store.settle(
            noteID: noteID,
            fingerprint: secondRevision,
            rationale: "Settled again after revision.",
            settledAt: Date(timeIntervalSince1970: 30)
        )

        #expect(repeated.id != first.id)
        #expect(repeated.fingerprint == firstRevision)
        #expect(repeated.settledAt == Date(timeIntervalSince1970: 20))
        #expect(repeated.rationale == nil)
        #expect(replacement.id != first.id)
        #expect(replacement.fingerprint == secondRevision)
        let listing = try await store.settlementListing()
        #expect(listing.settlements == [replacement])
        let directory = fixture.control
            .appendingPathComponent("research-records/v1/settlements", isDirectory: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json") }.count == 1)
    }

    @Test("Deletion rollback never overwrites a newly created Settle state")
    func settlementRollbackPreservesConcurrentState() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let noteID = UUID()
        let original = try await store.settle(
            noteID: noteID,
            fingerprint: DocumentFingerprint(content: "original"),
            rationale: nil,
            settledAt: Date(timeIntervalSince1970: 10)
        )
        try await store.purgeSettlement(noteID: noteID)
        let concurrent = try await store.settle(
            noteID: noteID,
            fingerprint: DocumentFingerprint(content: "concurrent"),
            rationale: "A newer researcher action.",
            settledAt: Date(timeIntervalSince1970: 20)
        )

        await #expect(throws: ResearchRecordStoreV1Error.self) {
            try await store.restoreSettlement(original)
        }
        #expect(try await store.latestSettlement(noteID: noteID) == concurrent)
    }

    @Test("Deletion compare-and-purge preserves a concurrently replaced Settle")
    func settlementCompareAndPurgeRejectsConcurrentReplacement() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let noteID = UUID()
        let captured = try await store.settle(
            noteID: noteID,
            fingerprint: DocumentFingerprint(content: "captured"),
            rationale: nil,
            settledAt: Date(timeIntervalSince1970: 10)
        )
        let concurrent = try await store.settle(
            noteID: noteID,
            fingerprint: DocumentFingerprint(content: "concurrent"),
            rationale: "A later researcher action.",
            settledAt: Date(timeIntervalSince1970: 20)
        )

        await #expect(throws: ResearchRecordStoreV1Error.self) {
            try await store.purgeSettlement(noteID: noteID, matching: captured)
        }
        #expect(try await store.latestSettlement(noteID: noteID) == concurrent)

        let initiallyAbsent = UUID()
        let newlyCreated = try await store.settle(
            noteID: initiallyAbsent,
            fingerprint: DocumentFingerprint(content: "new"),
            rationale: nil
        )
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            try await store.purgeSettlement(noteID: initiallyAbsent, matching: nil)
        }
        #expect(try await store.latestSettlement(noteID: initiallyAbsent) == newlyCreated)
    }

    @Test("Portable Settle state rejects absolute paths before writing")
    func settlementRejectsAbsolutePaths() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        await #expect(throws: PortableResearchRecordError.self) {
            _ = try await store.settle(
                noteID: UUID(),
                fingerprint: DocumentFingerprint(content: "settled"),
                rationale: "Checked against /Users/researcher/private/source.pdf."
            )
        }
        #expect(try await store.settlementListing().settlements.isEmpty)

        let noteID = UUID()
        _ = try await store.settle(
            noteID: noteID,
            fingerprint: DocumentFingerprint(content: "valid"),
            rationale: nil
        )
        let url = fixture.control
            .appendingPathComponent("research-records/v1/settlements", isDirectory: true)
            .appendingPathComponent(noteID.uuidString.lowercased() + ".json")
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        var settlement = try #require(object["settlement"] as? [String: Any])
        settlement["raw_key"] = "must-not-be-ignored"
        object["settlement"] = settlement
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let listing = try await store.settlementListing()
        #expect(listing.settlements.isEmpty)
        #expect(listing.issues.map(\.fileName) == [url.lastPathComponent])

        let nestedID = UUID()
        _ = try await store.settle(
            noteID: nestedID,
            fingerprint: DocumentFingerprint(content: "nested"),
            rationale: nil
        )
        let nestedURL = url.deletingLastPathComponent()
            .appendingPathComponent(nestedID.uuidString.lowercased() + ".json")
        var nestedObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: nestedURL))
                as? [String: Any]
        )
        var nestedSettlement = try #require(
            nestedObject["settlement"] as? [String: Any]
        )
        var fingerprint = try #require(
            nestedSettlement["fingerprint"] as? [String: Any]
        )
        fingerprint["bookmark"] = "must-not-be-ignored"
        nestedSettlement["fingerprint"] = fingerprint
        nestedObject["settlement"] = nestedSettlement
        try JSONSerialization.data(withJSONObject: nestedObject).write(to: nestedURL)

        let nestedListing = try await store.settlementListing()
        #expect(nestedListing.settlements.isEmpty)
        #expect(Set(nestedListing.issues.map(\.fileName)) == [
            url.lastPathComponent,
            nestedURL.lastPathComponent,
        ])
    }
    @Test("Bounded write facts and Function completion commit in one record transition")
    func localWriteReportAndCompletionAreAtomic() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runID = UUID()
        let store = try fixture.localStore()
        let seed = try makeLocalExecutionRecord(runID: runID)
        let target = seed.snapshot.request.target
        _ = try await store.create(seed)
        let report = try ResearchRunWriteReport(
            runID: runID,
            confirmedModifiedNotes: [],
            unmodifiedNotes: [writeReference(target)],
            observedFingerprints: [target.noteID: target.fingerprint],
            completedAt: Date(timeIntervalSince1970: 20)
        )
        let completion = ResearchFunctionCompletion(
            runID: runID,
            function: .develop,
            state: .complete,
            recordTitle: try ResearchRecordTitle("No change was warranted"),
            targetFingerprint: target.fingerprint,
            materialFingerprints: [:],
            summary: "No change was warranted.",
            didModifyTarget: false,
            fidelityOutcomes: [],
            completedAt: report.completedAt
        )

        let completed = try await store.setCompletion(
            completion,
            writeReport: report,
            submissionDigest: "function-submission-digest",
            runID: runID
        )
        #expect(completed.writeReport == report)
        #expect(completed.completion == completion)
        #expect(completed.completionSubmissionDigest == "function-submission-digest")
        #expect(try await store.record(id: runID) == completed)

        let repeated = try await store.setCompletion(
            completion,
            writeReport: report,
            submissionDigest: "function-submission-digest",
            runID: runID
        )
        #expect(repeated == completed)
    }

    @Test("New stores preserve every legacy file byte, digest, mode, and mtime")
    func legacyFilesRemainByteUnchanged() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacyActivity = fixture.triptychSupport
            .appendingPathComponent("research-activity/research-activity.json")
        let legacyDialogue = fixture.triptychSupport
            .appendingPathComponent("dialogue/dialogue.json")
        let legacyBindings = fixture.control
            .appendingPathComponent("research-skill-bindings.json")
        for (url, source) in [
            (legacyActivity, "legacy activity and grants\n"),
            (legacyDialogue, "legacy dialogue\n"),
            (legacyBindings, "legacy bindings\n"),
        ] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(source.utf8).write(to: url)
            try FileManager.default.setAttributes(
                [
                    .posixPermissions: NSNumber(value: 0o640),
                    .modificationDate: Date(timeIntervalSince1970: 1_234),
                ],
                ofItemAtPath: url.path
            )
        }
        let before = try Dictionary(uniqueKeysWithValues: [
            legacyActivity, legacyDialogue, legacyBindings,
        ].map { ($0, try LegacyCanary(url: $0)) })

        let portable = try fixture.portableStore()
        let local = try fixture.localStore()
        _ = try await portable.createFinishedRecord(makePortableRecord())
        _ = try await portable.settle(
            noteID: UUID(),
            fingerprint: DocumentFingerprint(content: "settled"),
            rationale: nil
        )
        _ = try await local.create(makeLocalExecutionRecord(runID: UUID()))

        for (url, canary) in before {
            #expect(try LegacyCanary(url: url) == canary)
        }
    }

    @Test("A corrupt execution file is isolated and cannot become current Run state")
    func corruptLocalExecutionFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let good = try makeLocalExecutionRecord(runID: UUID())
        _ = try await store.create(good)
        let corruptID = UUID()
        let corruptURL = store.storageURL
            .appendingPathComponent(corruptID.uuidString.lowercased() + ".json")
        try Data("{\"schema_version\":2".utf8).write(to: corruptURL)

        let listing = try await store.listing()
        #expect(listing.records.map(\.id) == [good.id])
        #expect(listing.issues.count == 1)
        await #expect(throws: Error.self) {
            _ = try await store.record(id: corruptID)
        }
    }

    @Test("Local Execution schema 12 round-trips and rejects retired schema 11")
    func localExecutionSchemaCutover() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let record = try makeLocalExecutionRecord(runID: UUID())
        let stored = try await store.create(record)
        #expect(stored.schemaVersion == 12)

        let url = store.storageURL
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        let currentBytes = try Data(contentsOf: url)
        #expect(try JSONDecoder().decode(
            LocalResearchExecutionRecord.self,
            from: currentBytes
        ) == stored)
        var object = try #require(
            JSONSerialization.jsonObject(with: currentBytes) as? [String: Any]
        )
        #expect(object["schema_version"] as? Int == 12)
        object["schema_version"] = 11
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let listing = try await store.listing()
        #expect(listing.records.isEmpty)
        #expect(listing.issues.map(\.fileName) == [url.lastPathComponent])
        await #expect(throws: Error.self) {
            _ = try await store.record(id: record.id)
        }
    }

    @Test("Current Local Execution rejects undeclared fields including raw keys")
    func localExecutionRejectsUnknownFields() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let record = try makeLocalExecutionRecord(runID: UUID())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(record))
                as? [String: Any]
        )
        object["raw_activity_key"] = "must-never-persist"
        let url = store.storageURL
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let listing = try await store.listing()
        #expect(listing.records.isEmpty)
        #expect(listing.issues.map(\.fileName) == [url.lastPathComponent])
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            try await store.validateStoreHealth()
        }
    }

    @Test("Durable Analyze completion requires and freezes its recommendation report")
    func localAnalyzeCompletionRecommendationShapeIsFrozen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let runID = UUID()
        let local = try makeLocalExecutionRecord(
            runID: runID,
            actionID: .analyze
        )
        _ = try await store.create(local)
        let first = [try ResearchLiteratureRecommendationSubmission(
            rawCitation: "First source-grounded lead",
            reason: "The source identifies this work as a live objection."
        )]
        let replacement = [try ResearchLiteratureRecommendationSubmission(
            rawCitation: "Replacement lead",
            reason: "This later payload must not replace the first report."
        )]
        let awaiting = ResearchFunctionCompletion(
            runID: runID,
            function: .develop,
            state: .awaitingFidelity,
            recordTitle: try ResearchRecordTitle("Analyze completion awaiting fidelity"),
            targetFingerprint: local.snapshot.request.target.fingerprint,
            materialFingerprints: [:],
            summary: "Analyze completion awaiting exact-revision Fidelity.",
            didModifyTarget: true,
            fidelityOutcomes: [],
            literatureRecommendations: first,
            completedAt: Date(timeIntervalSince1970: 20)
        )
        let report = try ResearchRunWriteReport(
            runID: runID,
            confirmedModifiedNotes: [writeReference(local.snapshot.request.target)],
            unmodifiedNotes: [],
            observedFingerprints: [
                local.snapshot.request.target.noteID:
                    local.snapshot.request.target.fingerprint,
            ],
            completedAt: awaiting.completedAt
        )
        _ = try await store.setCompletion(
            awaiting,
            writeReport: report,
            submissionDigest: "first-submission",
            runID: runID
        )
        let tamperedTerminal = ResearchFunctionCompletion(
            runID: runID,
            function: .develop,
            state: .complete,
            recordTitle: awaiting.recordTitle,
            targetFingerprint: awaiting.targetFingerprint,
            materialFingerprints: awaiting.materialFingerprints,
            summary: awaiting.summary,
            didModifyTarget: awaiting.didModifyTarget,
            fidelityOutcomes: [],
            literatureRecommendations: replacement,
            completedAt: awaiting.completedAt
        )
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.setCompletion(
                tamperedTerminal,
                writeReport: report,
                submissionDigest: "replacement-submission",
                runID: runID
            )
        }
        #expect(try await store.record(id: runID).completion == awaiting)

        let url = store.storageURL
            .appendingPathComponent(runID.uuidString.lowercased() + ".json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(
                try await store.record(id: runID)
            )) as? [String: Any]
        )
        var completion = try #require(object["completion"] as? [String: Any])
        completion.removeValue(forKey: "literatureRecommendations")
        object["completion"] = completion
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let listing = try await store.listing()
        #expect(listing.records.isEmpty)
        #expect(listing.issues.map(\.fileName) == [url.lastPathComponent])
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.record(id: runID)
        }
    }

    @Test("Permanent-deletion cleanup removes only executions containing the Note")
    func localExecutionPurgeIsIdentityBound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let deletedNoteID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let retainedNoteID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let deletedRun = try makeLocalExecutionRecord(
            runID: UUID(),
            noteID: deletedNoteID
        )
        let retainedRun = try makeLocalExecutionRecord(
            runID: UUID(),
            noteID: retainedNoteID
        )
        _ = try await store.create(deletedRun)
        _ = try await store.create(retainedRun)

        let removed = try await store.purgeExecutions(containing: [deletedNoteID])

        #expect(removed == [deletedRun.id])
        #expect(try await store.recordIfPresent(id: deletedRun.id) == nil)
        #expect(try await store.record(id: retainedRun.id) == retainedRun)
    }

    @Test("Researcher Response replaces Evaluation and Method Feedback in one CAS")
    func researcherResponseCAS() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let original = try makePortableRecord()
        _ = try await store.createFinishedRecord(original)
        let resultFingerprint = try original.finalizedResultFingerprint()
        let first = try await store.saveResearcherResponse(
            ResearcherResponseDraft(
                evaluation: ResearcherEvaluationDraft(
                    observedIssues: [.sourceOrAttribution],
                    note: "The attribution needs a narrower locator."
                ),
                methodFeedbackText: "Ask for a counter-reading before synthesis."
            ),
            recordID: original.id,
            expectedEvaluationRevision: nil,
            expectedMethodFeedbackRevision: nil,
            expectedResultFingerprint: resultFingerprint,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let firstRevision = try #require(first.researcherEvaluation?.revision)
        let firstFeedbackRevision = try #require(first.methodFeedbackComment?.revision)
        #expect(try first.finalizedResultFingerprint() == resultFingerprint)
        #expect(first.researcherEvaluation?.author == .researcher)
        #expect(first.methodFeedbackComment?.sourceEvaluationRevision == firstRevision)

        let feedbackOnly = try await store.saveResearcherResponse(
            ResearcherResponseDraft(
                evaluation: ResearcherEvaluationDraft(
                    observedIssues: [.sourceOrAttribution],
                    note: "The attribution needs a narrower locator."
                ),
                methodFeedbackText: "Require the counter-reading before synthesis."
            ),
            recordID: original.id,
            expectedEvaluationRevision: firstRevision,
            expectedMethodFeedbackRevision: firstFeedbackRevision,
            expectedResultFingerprint: resultFingerprint,
            updatedAt: Date(timeIntervalSince1970: 31)
        )
        let feedbackOnlyRevision = try #require(
            feedbackOnly.methodFeedbackComment?.revision
        )
        #expect(feedbackOnly.researcherEvaluation?.revision == firstRevision)
        #expect(feedbackOnlyRevision != firstFeedbackRevision)
        #expect(feedbackOnly.methodFeedbackComment?.sourceEvaluationRevision
            == firstRevision)

        await #expect(
            throws: PortableResearcherResponseMutationError.staleEvaluationRevision
        ) {
            _ = try await store.saveResearcherResponse(
                ResearcherResponseDraft(
                    evaluation: ResearcherEvaluationDraft(noIssuesObserved: true),
                    methodFeedbackText: nil
                ),
                recordID: original.id,
                expectedEvaluationRevision: nil,
                expectedMethodFeedbackRevision: feedbackOnlyRevision,
                expectedResultFingerprint: resultFingerprint
            )
        }
        await #expect(
            throws: PortableResearcherResponseMutationError.staleMethodFeedbackRevision
        ) {
            _ = try await store.saveResearcherResponse(
                ResearcherResponseDraft(
                    evaluation: ResearcherEvaluationDraft(noIssuesObserved: true),
                    methodFeedbackText: nil
                ),
                recordID: original.id,
                expectedEvaluationRevision: firstRevision,
                expectedMethodFeedbackRevision: nil,
                expectedResultFingerprint: resultFingerprint
            )
        }

        let cleared = try await store.saveResearcherResponse(
            ResearcherResponseDraft(evaluation: nil, methodFeedbackText: nil),
            recordID: original.id,
            expectedEvaluationRevision: firstRevision,
            expectedMethodFeedbackRevision: feedbackOnlyRevision,
            expectedResultFingerprint: resultFingerprint
        )
        #expect(cleared.researcherEvaluation == nil)
        #expect(cleared.methodFeedbackComment == nil)
        #expect(try cleared.finalizedResultFingerprint() == resultFingerprint)

        enum InjectedFailure: Error { case afterRename }
        await store.setPostCommitFaultForTesting { _ in
            throw InjectedFailure.afterRename
        }
        do {
            _ = try await store.saveResearcherResponse(
                ResearcherResponseDraft(
                    evaluation: ResearcherEvaluationDraft(noIssuesObserved: true),
                    methodFeedbackText: "Retain the response together."
                ),
                recordID: original.id,
                expectedEvaluationRevision: nil,
                expectedMethodFeedbackRevision: nil,
                expectedResultFingerprint: resultFingerprint
            )
            Issue.record("Expected Response replacement commit uncertainty.")
        } catch let error as ResearchRecordStoreV1Error {
            guard case .replacementCommitUncertain = error else {
                Issue.record("Unexpected Response replacement error: \(error)")
                return
            }
        }
        let reconciled = try await store.record(id: original.id)
        #expect(reconciled.researcherEvaluation?.noIssuesObserved == true)
        #expect(reconciled.methodFeedbackComment?.text == "Retain the response together.")
        #expect(reconciled.methodFeedbackComment?.sourceEvaluationRevision
            == reconciled.researcherEvaluation?.revision)
        #expect(try reconciled.finalizedResultFingerprint() == resultFingerprint)
    }

    @Test("Note Review derives and cumulatively covers confirmed Record activities")
    func noteReviewCoverage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let base = try makePortableRecord()
        let participant = try #require(base.participatingNotes.first)
        let ending = DocumentFingerprint(content: "agent ending")
        let secondNoteID = UUID(
            uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
        )!
        let secondStarting = DocumentFingerprint(content: "second starting")
        let secondEnding = DocumentFingerprint(content: "second agent ending")
        let secondParticipant = try PortableResearchNoteRevision(
            noteID: secondNoteID,
            note: VaultQualifiedNoteID(
                vaultID: participant.note.vaultID,
                relativePath: "Second.md"
            ),
            role: .work,
            title: "Second",
            startingRevision: secondStarting,
            endingRevision: secondEnding
        )
        let changed = try PortableResearchRecord(
            id: base.id,
            triptychID: base.triptychID,
            title: base.title,
            kind: base.kind,
            action: base.action,
            method: base.method,
            primaryNoteID: base.primaryNoteID,
            participatingNotes: [
                try PortableResearchNoteRevision(
                    noteID: participant.noteID,
                    note: participant.note,
                    role: participant.role,
                    title: participant.title,
                    startingRevision: participant.startingRevision,
                    endingRevision: ending
                ),
                secondParticipant,
            ],
            statements: base.statements,
            fidelityCompletion: base.fidelityCompletion,
            confirmedChanges: [
                try PortableResearchConfirmedChange(
                    noteID: participant.noteID,
                    actor: .agent,
                    startingRevision: participant.startingRevision,
                    endingRevision: ending
                ),
                try PortableResearchConfirmedChange(
                    noteID: secondNoteID,
                    actor: .agent,
                    startingRevision: secondStarting,
                    endingRevision: secondEnding
                ),
            ],
            startedAt: base.startedAt,
            finishedAt: base.finishedAt
        )
        _ = try await store.createFinishedRecord(changed)
        let manifest = try await store.listing().sourceManifestHash
        let review = try await store.markCurrentNoteReviewed(
            noteID: participant.noteID,
            observedRevision: ending,
            expectedRecordSourceManifestHash: manifest,
            reviewedAt: Date(timeIntervalSince1970: 50)
        )
        #expect(review.coveredActivities == [PortableResearchNoteActivityReference(
            recordID: changed.id,
            noteID: participant.noteID
        )])
        #expect(try await store.noteReviewListing().reviews == [review])

        #expect(try await store.noteReviewListing().reviews.allSatisfy {
            $0.noteID != secondNoteID
        })

        await #expect(throws: PortableResearchNoteReviewMutationError.noPendingAgentChanges) {
            _ = try await store.markCurrentNoteReviewed(
                noteID: participant.noteID,
                observedRevision: ending,
                expectedRecordSourceManifestHash: manifest
            )
        }

        let lateBase = try makePortableRecord(
            id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!
        )
        let lateParticipant = try #require(lateBase.participatingNotes.first)
        let laterEnding = DocumentFingerprint(content: "later agent ending")
        let lateRecord = try PortableResearchRecord(
            id: lateBase.id,
            triptychID: lateBase.triptychID,
            title: lateBase.title,
            kind: lateBase.kind,
            action: lateBase.action,
            method: lateBase.method,
            primaryNoteID: lateBase.primaryNoteID,
            participatingNotes: [try PortableResearchNoteRevision(
                noteID: lateParticipant.noteID,
                note: lateParticipant.note,
                role: lateParticipant.role,
                title: lateParticipant.title,
                startingRevision: lateParticipant.startingRevision,
                endingRevision: laterEnding
            )],
            statements: lateBase.statements,
            fidelityCompletion: lateBase.fidelityCompletion,
            confirmedChanges: [try PortableResearchConfirmedChange(
                noteID: lateParticipant.noteID,
                actor: .agent,
                startingRevision: lateParticipant.startingRevision,
                endingRevision: laterEnding
            )],
            startedAt: lateBase.startedAt,
            finishedAt: lateBase.finishedAt
        )
        _ = try await store.createFinishedRecord(lateRecord)
        #expect(try await store.noteReviewListing().reviews.first?
            .coveredActivities.count == 1)
        let updatedManifest = try await store.listing().sourceManifestHash
        let updated = try await store.markCurrentNoteReviewed(
            noteID: participant.noteID,
            observedRevision: laterEnding,
            expectedRecordSourceManifestHash: updatedManifest,
            reviewedAt: Date(timeIntervalSince1970: 60)
        )
        #expect(Set(updated.coveredActivities) == [
            PortableResearchNoteActivityReference(
                recordID: changed.id,
                noteID: participant.noteID
            ),
            PortableResearchNoteActivityReference(
                recordID: lateRecord.id,
                noteID: participant.noteID
            ),
        ])
    }

    private func makePortableRecord(
        id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        actionID: ResearchActionID = .synthesize,
        recommendations: [ResearchLiteratureRecommendation] = []
    ) throws -> PortableResearchRecord {
        let action = try makeActionSnapshot(actionID: actionID)
        let note = try PortableResearchNoteRevision(
            noteID: action.target.noteID,
            note: action.target.note,
            role: action.target.role,
            title: action.target.title,
            startingRevision: action.target.fingerprint,
            endingRevision: action.target.fingerprint
        )
        return try PortableResearchRecord(
            id: id,
            triptychID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            title: ResearchRecordTitle("No source change was needed"),
            kind: .action,
            action: ResearchActionRecordIdentity(snapshot: action),
            method: try PortableResearchMethodReference(snapshot: action),
            sourceReference: actionID == .analyze
                ? try ResearchSourceReference(
                    identity: .localFile(id: id),
                    displayName: "Source.pdf",
                    fingerprint: DocumentFingerprint(content: "source bytes")
                )
                : nil,
            participatingNotes: [note],
            statements: [try PortableResearchStatement(
                author: .agent,
                kind: .agentFeedback,
                attribution: "Agent",
                text: "No source change was needed.",
                createdAt: Date(timeIntervalSince1970: 20)
            )],
            fidelityCompletion: .notRequired,
            literatureRecommendations: recommendations,
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20)
        )
    }

    private func makeRecommendation(
        recordID: UUID = UUID(
            uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        )!,
        ordinal: Int,
        citation: String = "A source-grounded reading lead"
    ) throws -> ResearchLiteratureRecommendation {
        try ResearchLiteratureRecommendation(
            id: ResearchLiteratureRecommendation.stableID(
                runID: recordID,
                ordinal: ordinal
            ),
            rawCitation: citation,
            title: citation,
            doi: "10.1000/reading-lead",
            sourceLocators: ["p. 42"],
            reason: "The analyzed source discusses this work as a live objection.",
            disposition: PortableResearchRecommendationDisposition(
                status: .unprocessed,
                updatedAt: Date(timeIntervalSince1970: 20)
            )
        )
    }

    private func makePortableDiscussion(
        id: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        source: String = "claim"
    ) throws -> PortableResearchDiscussion {
        let vaultID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let primaryID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let focalID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let primaryFingerprint = DocumentFingerprint(content: source)
        let primary = try PortableResearchNoteRevision(
            noteID: primaryID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Topic.md"),
            role: .topic,
            title: "Topic",
            startingRevision: primaryFingerprint,
            endingRevision: primaryFingerprint
        )
        let focalFingerprint = DocumentFingerprint(content: "analysis")
        let focal = try PortableResearchNoteRevision(
            noteID: focalID,
            note: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Analysis.md"),
            role: .analysis,
            title: "Analysis",
            startingRevision: focalFingerprint,
            endingRevision: focalFingerprint
        )
        let range = try #require(source.range(of: "claim"))
        let lower = range.lowerBound.utf16Offset(in: source)
        let upper = range.upperBound.utf16Offset(in: source)
        let anchor = try #require(CommentAnchorBuilder.anchor(
            in: source,
            fingerprint: primaryFingerprint,
            utf16Range: lower..<upper
        ))
        let statement = try PortableResearchStatement(
            author: .researcher,
            kind: .discussionTurn,
            attribution: "Researcher",
            text: "Test this claim.",
            createdAt: Date(timeIntervalSince1970: 10),
            passage: anchor
        )
        return try PortableResearchDiscussion(
            id: id,
            triptychID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            primaryNoteID: primaryID,
            participatingNotes: [primary, focal],
            statements: [statement],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10)
        )
    }

    private func makeLocalExecutionRecord(
        runID: UUID,
        actionID: ResearchActionID = .synthesize,
        noteID: UUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    ) throws -> LocalResearchExecutionRecord {
        let action = try makeActionSnapshot(noteID: noteID, actionID: actionID)
        let target = ResearchFunctionTarget(
            noteID: action.target.noteID,
            note: action.target.note,
            role: .topic,
            lifecycle: .active,
            fingerprint: action.target.fingerprint,
            title: action.target.title
        )
        let request = ResearchFunctionRequest(
            function: .develop,
            target: target
        )
        let snapshot = ResearchFunctionSnapshot(
            runID: runID,
            request: request,
            actionSnapshot: action,
            recordKind: .functionEnvelope,
            recordID: runID,
            checkpointID: UUID(
                uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB"
            ),
            confirmationToken: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            preparedAt: Date(timeIntervalSince1970: 10)
        )
        return try LocalResearchExecutionRecord(
            triptychID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            snapshot: snapshot,
            preparedInstructions: "Local protected instructions."
        )
    }

    private func makeActionSnapshot(
        noteID: UUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
        actionID: ResearchActionID = .synthesize
    ) throws -> ResearchActionSnapshot {
        let definition = actionID == .analyze
            ? ResearchActionDefinition.analyze
            : ResearchActionDefinition.synthesize
        let targetRole: ResearchActionTargetRole = actionID == .analyze
            ? .analysis
            : .topic
        let target = ResearchActionNoteSnapshot(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                relativePath: actionID == .analyze ? "Analysis.md" : "Problem.md"
            ),
            role: targetRole,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: "# Topic\n"),
            title: actionID == .analyze ? "Analysis" : "Problem"
        )
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == actionID
            }
        )
        let profileRevision = try profile.contentRevision()
        let registration = try ResearchSkillRegistration(
            key: ResearchSkillRegistrationKey(
                rawValue: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!
            ),
            actionID: actionID,
            displayName: profile.displayName,
            primaryMarkdown: .machineLocal()
        )
        return try ResearchActionSnapshot(
            definition: definition,
            target: target,
            method: try ResearchMethodSnapshot(
                registration: registration,
                primaryMarkdownSource: "# \(profile.displayName)\n\nExact test method.\n",
                practices: []
            ),
            resolvedProfile: try ResearchActionResolvedProfileSnapshot(
                profile: profile,
                profileRevision: profileRevision,
                profileDocumentRevision: DocumentFingerprint(content: "profiles")
            ),
            platformInputs: try ResearchActionPlatformInputs(),
            academicInputs: try ResearchAcademicFieldValues(
                values: [:],
                definitions: profile.academicInputFields
            ),
            resultContract: try ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: profileRevision
            ),
            authority: try ResearchAuthorityEnvelope(
                readableNotes: [target],
                writableNotes: [target],
                writeOperations: [.modifyMarkdown],
                editablePropertyKeys: []
            )
        )
    }

    private func writeReference(
        _ target: ResearchFunctionTarget
    ) throws -> ResearchRunWriteNoteReference {
        try ResearchRunWriteNoteReference(
            noteID: target.noteID,
            note: target.note,
            role: target.role,
            title: target.title
        )
    }

    private struct LegacyCanary: Equatable {
        let bytes: Data
        let digest: DocumentFingerprint
        let mode: Int
        let modificationDate: Date

        init(url: URL) throws {
            bytes = try Data(contentsOf: url)
            digest = DocumentFingerprint(data: bytes)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            mode = try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
            modificationDate = try #require(attributes[.modificationDate] as? Date)
        }
    }

    private struct Fixture {
        let root: URL
        let control: URL
        let support: URL
        let triptychSupport: URL
        let triptychID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        init() throws {
            let repository = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            root = repository.appendingPathComponent(
                ".build/session11-record-tests/\(UUID().uuidString)",
                isDirectory: true
            )
            control = root.appendingPathComponent("Works/.scholium", isDirectory: true)
            support = root.appendingPathComponent("Application Support", isDirectory: true)
            triptychSupport = support
                .appendingPathComponent("Triptychs", isDirectory: true)
                .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: control,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: triptychSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        }

        func portableStore() throws -> PortableResearchRecordStore {
            try PortableResearchRecordStore(
                controlURL: control,
                applicationSupportURL: support,
                triptychID: triptychID
            )
        }

        func localStore() throws -> LocalResearchExecutionStore {
            try LocalResearchExecutionStore(
                applicationSupportURL: support,
                triptychID: triptychID
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
