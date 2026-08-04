import Foundation
import ScholiumContracts
@testable import ScholiumCore
import Testing

@Suite("Portable Research Record storage v1/schema 4 and Local Execution v3")
struct ResearchRecordV1StoresTests {
    @Test("A post-rename failure leaves exact committed bytes observable")
    func secureReplacementReportsPostRenameUncertainty() throws {
        enum InjectedFailure: Error { case afterRename }
        let fixture = try Fixture()
        defer { fixture.remove() }
        let directory = SecureRecordDirectory(
            trustedRootURL: fixture.root,
            components: ["post-rename-fault"],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 1_024,
            postCommitFault: { _ in throw InjectedFailure.afterRename }
        )
        try directory.ensureDirectories([])
        let expected = Data("exact committed state".utf8)

        do {
            _ = try directory.replace(
                expected,
                directory: nil,
                fileName: "state.json"
            )
            Issue.record("Expected typed post-rename commit uncertainty.")
        } catch let error as SecureRecordDirectoryError {
            guard case .replacementCommitUncertain = error else {
                Issue.record("Unexpected replacement error: \(error)")
                return
            }
        }
        #expect(try directory.read(directory: nil, fileName: "state.json") == expected)

        do {
            _ = try directory.replace(
                Data(repeating: 0, count: 2_048),
                directory: nil,
                fileName: "oversize.json"
            )
            Issue.record("Expected typed pre-rename refusal.")
        } catch let error as SecureRecordDirectoryError {
            guard case .replacementNotCommitted = error else {
                Issue.record("Unexpected replacement error: \(error)")
                return
            }
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.root
            .appendingPathComponent("post-rename-fault/oversize.json").path))
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

    @Test("Pinning replaces only the portable record pin")
    func portablePinReplacementPreservesRecord() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let recommendation = try makeRecommendation(ordinal: 0)
        let record = try makePortableRecord(
            actionID: .analyze,
            recommendations: [recommendation]
        )
        _ = try await store.createFinishedRecord(record)

        let pinned = try await store.setPinned(true, for: record.id)

        #expect(pinned.isPinned)
        #expect(pinned.id == record.id)
        #expect(pinned.triptychID == record.triptychID)
        #expect(pinned.kind == record.kind)
        #expect(pinned.action == record.action)
        #expect(pinned.method == record.method)
        #expect(pinned.primaryNoteID == record.primaryNoteID)
        #expect(pinned.participatingNotes == record.participatingNotes)
        #expect(pinned.statements == record.statements)
        #expect(pinned.actuallyUsedMaterials == record.actuallyUsedMaterials)
        #expect(pinned.fidelityCompletion == record.fidelityCompletion)
        #expect(pinned.confirmedChanges == record.confirmedChanges)
        #expect(pinned.discrepancies == record.discrepancies)
        #expect(pinned.literatureRecommendations == record.literatureRecommendations)
        #expect(pinned.sourceReference == record.sourceReference)
        #expect(pinned.startedAt == record.startedAt)
        #expect(pinned.finishedAt == record.finishedAt)
        #expect(try await store.record(id: record.id) == pinned)

        let restored = try await store.setPinned(false, for: record.id)
        #expect(restored == record)
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
        #expect(handled.isPinned == record.isPinned)

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

    @Test("Pin and disposition serialize across store instances without lost updates")
    func concurrentPinAndDispositionPreserveBothChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstStore = try fixture.portableStore()
        let secondStore = try fixture.portableStore()
        let recommendation = try makeRecommendation(ordinal: 0)
        let record = try makePortableRecord(
            actionID: .analyze,
            recommendations: [recommendation]
        )
        _ = try await firstStore.createFinishedRecord(record)

        async let pinned = firstStore.setPinned(true, for: record.id)
        async let handled = secondStore.setRecommendationDisposition(
            .handled,
            recommendationID: recommendation.id,
            recordID: record.id,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        _ = try await (pinned, handled)

        let final = try await firstStore.record(id: record.id)
        #expect(final.isPinned)
        #expect(final.literatureRecommendations[0].disposition.status == .handled)
        #expect(final.literatureRecommendations[0].rawCitation == recommendation.rawCitation)
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
        let recordsURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        #expect(try await store.deletePermanently(id: record.id) == record)
        #expect(!FileManager.default.fileExists(atPath: recordsURL.path))
        #expect(try await store.listing().records == [unrelated])
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
        let corruptURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee.json")
        try Data("{\"schema_version\":1,".utf8).write(to: corruptURL)

        let listing = try await store.listing()
        #expect(listing.records.map(\.id) == [record.id])
        #expect(listing.issues.count == 1)
        #expect(listing.issues.first?.fileName == corruptURL.lastPathComponent)
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


    @Test("Local Execution v3 keeps only the Agent coordination digest")
    func localCoordinationKeyIsTransient() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runID = UUID()
        let seed = try makeLocalExecutionRecord(runID: runID, grant: nil)
        let actionSnapshot = try #require(seed.snapshot.actionSnapshot)
        let authorization = try LocalResearchExecutionStore
            .prepareAgentCoordination(
                triptychID: seed.triptychID,
                parentRunID: runID,
                actionRevision: try AgentNoteChangeActionRevision(
                    actionSnapshot: actionSnapshot
                ),
                issuedAt: Date(timeIntervalSince1970: 10),
                validFor: 60
            )
        let record = try makeLocalExecutionRecord(
            runID: runID,
            grant: nil,
            coordinationGrant: authorization.grant
        )
        let store = try fixture.localStore()
        _ = try await store.create(record)
        let data = try Data(contentsOf: store.storageURL
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json"))
        let source = String(decoding: data, as: UTF8.self)
        #expect(source.contains(authorization.grant.keyDigest))
        #expect(!source.contains(authorization.coordinationKey))
        #expect(try await store.record(id: record.id).agentCoordinationGrant
            == authorization.grant)
        let requestID = UUID()
        #expect(try await store.bindAgentCoordinationRequest(
            runID: record.id,
            expectedGrant: authorization.grant,
            requestID: requestID
        ).agentCoordinationRequestID == requestID)
        #expect(try await store.bindAgentCoordinationRequest(
            runID: record.id,
            expectedGrant: authorization.grant,
            requestID: requestID
        ).agentCoordinationRequestID == requestID)
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.bindAgentCoordinationRequest(
                runID: record.id,
                expectedGrant: authorization.grant,
                requestID: UUID()
            )
        }
    }

    @Test("Local write grant and Function completion commit in one record transition")
    func localGrantAndCompletionAreAtomic() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runID = UUID()
        let store = try fixture.localStore()
        let seed = try makeLocalExecutionRecord(runID: runID, grant: nil)
        let target = seed.snapshot.request.target
        let authorization = try LocalResearchExecutionStore.prepareGrant(
            activityID: runID,
            origin: activityReference(target),
            writeScope: .currentNote,
            allowedTargets: [activityReference(target)],
            startingFingerprints: [target.noteID: target.fingerprint],
            issuedAt: Date(timeIntervalSince1970: 10)
        )
        _ = try await store.create(try makeLocalExecutionRecord(
            runID: runID,
            grant: authorization.grant
        ))
        let report = MultiTargetCompletionReport(
            activityID: runID,
            candidateModifiedNotes: [],
            confirmedModifiedNotes: [],
            unmodifiedNotes: [],
            unreportedChangedNotes: [],
            observedFingerprints: [target.noteID: target.fingerprint],
            summary: "No change was warranted.",
            completedAt: Date(timeIntervalSince1970: 20)
        )
        let completion = ResearchFunctionCompletion(
            runID: runID,
            function: .develop,
            state: .complete,
            targetFingerprint: target.fingerprint,
            materialFingerprints: [:],
            summary: "No change was warranted.",
            didModifyTarget: false,
            fidelityOutcomes: [],
            completedAt: report.completedAt
        )

        let completed = try await store.completeExecution(
            activityID: runID,
            activityKey: authorization.activityKey,
            completionPayloadDigest: "candidate-report-digest",
            report: report,
            completion: completion,
            submissionDigest: "function-submission-digest"
        )
        #expect(completed.grant?.state == .completed)
        #expect(completed.grant?.completionReport == report)
        #expect(completed.completion == completion)
        #expect(completed.completionSubmissionDigest == "function-submission-digest")
        #expect(try await store.record(id: runID) == completed)

        let repeated = try await store.completeExecution(
            activityID: runID,
            activityKey: authorization.activityKey,
            completionPayloadDigest: "candidate-report-digest",
            report: report,
            completion: completion,
            submissionDigest: "function-submission-digest"
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
        _ = try await local.create(makeLocalExecutionRecord(runID: UUID(), grant: nil))

        for (url, canary) in before {
            #expect(try LegacyCanary(url: url) == canary)
        }
    }

    @Test("A corrupt execution file is isolated and cannot authorize a grant")
    func corruptLocalExecutionFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let good = try makeLocalExecutionRecord(runID: UUID(), grant: nil)
        _ = try await store.create(good)
        let corruptID = UUID()
        let corruptURL = store.storageURL
            .appendingPathComponent(corruptID.uuidString.lowercased() + ".json")
        try Data("{\"schema_version\":2".utf8).write(to: corruptURL)

        let listing = try await store.listing()
        #expect(listing.records.map(\.id) == [good.id])
        #expect(listing.issues.count == 1)
        await #expect(throws: Error.self) {
            _ = try await store.authorizeCompletion(
                activityID: corruptID,
                activityKey: "legacy-or-guessed-key",
                at: Date()
            )
        }
    }

    @Test("Local Execution v3 rejects undeclared fields including raw keys")
    func localExecutionRejectsUnknownFields() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let record = try makeLocalExecutionRecord(runID: UUID(), grant: nil)
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
            grant: nil,
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
            targetFingerprint: local.snapshot.request.target.fingerprint,
            materialFingerprints: [:],
            summary: "Analyze completion awaiting exact-revision Fidelity.",
            didModifyTarget: true,
            fidelityOutcomes: [],
            literatureRecommendations: first,
            completedAt: Date(timeIntervalSince1970: 20)
        )
        _ = try await store.setCompletion(
            awaiting,
            submissionDigest: "first-submission",
            runID: runID
        )
        let tamperedTerminal = ResearchFunctionCompletion(
            runID: runID,
            function: .develop,
            state: .complete,
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
            grant: nil,
            noteID: deletedNoteID
        )
        let retainedRun = try makeLocalExecutionRecord(
            runID: UUID(),
            grant: nil,
            noteID: retainedNoteID
        )
        _ = try await store.create(deletedRun)
        _ = try await store.create(retainedRun)

        let removed = try await store.purgeExecutions(containing: [deletedNoteID])

        #expect(removed == [deletedRun.id])
        #expect(try await store.recordIfPresent(id: deletedRun.id) == nil)
        #expect(try await store.record(id: retainedRun.id) == retainedRun)
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
        grant: ResearchActivityGrant?,
        coordinationGrant: AgentCoordinationGrant? = nil,
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
            target: target,
            writeScope: .currentNote,
            authorizedWriteTargets: [target]
        )
        let snapshot = ResearchFunctionSnapshot(
            runID: runID,
            request: request,
            actionSnapshot: action,
            recordKind: .functionEnvelope,
            recordID: runID,
            activityID: grant?.activityID,
            confirmationToken: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            preparedAt: Date(timeIntervalSince1970: 10)
        )
        return try LocalResearchExecutionRecord(
            triptychID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            snapshot: snapshot,
            preparedInstructions: "Local protected instructions.",
            grant: grant,
            agentCoordinationGrant: coordinationGrant
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
        let sourceModuleID = ResearchActionModuleID(rawValue: "source")!
        let modules: [ResearchActionModuleDefinition] = actionID == .analyze
            ? [try .sourceReference(
                id: sourceModuleID,
                label: "Source",
                isRequired: true
            )]
            : []
        let profile = try ResearchActionProfile(
            definition: definition,
            buttonName: actionID == .analyze ? "Analyze" : "Synthesize",
            order: 100,
            applicableRoles: [targetRole],
            showInActions: true,
            modules: modules,
            sourceRequirement: actionID == .analyze ? .required : .none,
            capabilities: try ResearchActionCapabilityDeclaration(
                readableRoles: [targetRole],
                candidateWritableRoles: [targetRole],
                candidateWriteOperations: [.modifyMarkdown]
            ),
            feedbackRequirement: .requested
        )
        return try ResearchActionSnapshot(
            definition: definition,
            target: target,
            method: try ResearchActionMethodSnapshot(
                packageID: actionID == .analyze
                    ? "scholium-analyze"
                    : "scholium-synthesize",
                origin: .triptych,
                version: "working",
                packageRevision: DocumentFingerprint(content: "package"),
                loadedResources: [ResearchActionResourceSnapshot(
                    relativePath: "SKILL.md",
                    revision: DocumentFingerprint(content: "method")
                )]
            ),
            resolvedProfile: try ResearchActionResolvedProfileSnapshot(
                origin: .applicationDefault,
                profile: profile,
                profileRevision: profile.contentRevision(),
                profileDocumentRevision: nil
            ),
            parameters: try ResearchActionParameterModel(
                profile: profile,
                values: actionID == .analyze
                    ? [sourceModuleID: .source(try ResearchSourceReference(
                        identity: .localFile(),
                        displayName: "Source.pdf",
                        fingerprint: DocumentFingerprint(content: "source")
                    ))]
                    : [:]
            ),
            authority: try ResearchAuthorityEnvelope(
                readableNotes: [target],
                writableNotes: [target],
                writeOperations: [.modifyMarkdown],
                editablePropertyKeys: []
            )
        )
    }

    private func activityReference(
        _ target: ResearchFunctionTarget
    ) -> ResearchActivityNoteReference {
        ResearchActivityNoteReference(
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
