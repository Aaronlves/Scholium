import Foundation
import ScholiumContracts
@testable import ScholiumCore
import Testing

@Suite("Portable Research Record storage and enveloped Local Execution storage")
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

    @Test(
        "Unsupported schema-11 Records remain byte-unchanged and nonauthorizing",
        arguments: [false, true]
    )
    func unsupportedRecordSchemaRemainsUnchanged(
        hasDeletedParticipant: Bool
    ) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let record = try makePortableRecord()
        _ = try await store.createFinishedRecord(record)
        let recordURL = fixture.control
            .appendingPathComponent("research-records/v1/records", isDirectory: true)
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: recordURL))
                as? [String: Any]
        )
        object["schema_version"] = 11
        var participants = try #require(
            object["participating_notes"] as? [[String: Any]]
        )
        for index in participants.indices {
            participants[index]["is_tombstone"] = hasDeletedParticipant && index == 0
        }
        object["participating_notes"] = participants
        try JSONSerialization.data(withJSONObject: object).write(to: recordURL)
        let before = try LegacyCanary(url: recordURL)

        let reopened = try fixture.portableStore()
        let listing = try await reopened.listing()

        #expect(listing.records.isEmpty)
        #expect(listing.issues.map(\.fileName) == [recordURL.lastPathComponent])
        #expect(try LegacyCanary(url: recordURL) == before)
        let isPermanentlyDeleted = await reopened.isRecordPermanentlyDeleted(id: record.id)
        #expect(!isPermanentlyDeleted)
    }

    @Test("Unsupported schema-1 Discussions remain byte-unchanged and nonauthorizing")
    func unsupportedDiscussionSchemaRemainsUnchanged() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let discussion = try makePortableDiscussion()
        _ = try await store.createActiveDiscussion(discussion)
        let discussionURL = fixture.control
            .appendingPathComponent("research-records/v1/active", isDirectory: true)
            .appendingPathComponent(discussion.id.uuidString.lowercased() + ".json")
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: discussionURL))
                as? [String: Any]
        )
        object["schema_version"] = 1
        object["participating_notes"] = try #require(
            object["participating_notes"] as? [[String: Any]]
        ).map { participant in
            var participant = participant
            participant["is_tombstone"] = false
            return participant
        }
        try JSONSerialization.data(withJSONObject: object).write(to: discussionURL)
        let before = try LegacyCanary(url: discussionURL)

        let reopened = try fixture.portableStore()
        let listing = try await reopened.activeDiscussions()

        #expect(listing.discussions.isEmpty)
        #expect(listing.issues.map(\.fileName) == [discussionURL.lastPathComponent])
        #expect(try LegacyCanary(url: discussionURL) == before)
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

    @Test("First Agent reply atomically moves one Discussion into one idempotent Record")
    func discussionFinishIsOneRecoverableTransition() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let discussion = try makePortableDiscussion()
        _ = try await store.createActiveDiscussion(discussion)
        let agent = try PortableResearchStatement(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000987")!,
            author: .agent,
            kind: .discussionTurn,
            attribution: "Research Agent",
            text: "The residual pressure remains open.",
            createdAt: Date(timeIntervalSince1970: 12)
        )
        let first = try await store.finishDiscussion(
            id: discussion.id,
            appendingAgentStatement: agent,
            participatingNotes: discussion.participatingNotes,
            finishedAt: Date(timeIntervalSince1970: 20)
        )
        let repeated = try await store.finishDiscussion(
            id: discussion.id,
            appendingAgentStatement: try PortableResearchStatement(
                id: agent.id,
                author: .agent,
                kind: .discussionTurn,
                attribution: agent.attribution,
                text: agent.text,
                createdAt: Date(timeIntervalSince1970: 30)
            ),
            participatingNotes: [],
            finishedAt: Date(timeIntervalSince1970: 30)
        )

        #expect(!first.replyWasAlreadyRecorded)
        #expect(repeated.replyWasAlreadyRecorded)
        #expect(first.record == repeated.record)
        #expect(first.record.kind == .discussion)
        #expect(first.record.statements.count == 2)
        #expect(try await store.activeDiscussions().discussions.isEmpty)
        #expect(try await store.listing().records == [first.record])

        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await store.finishDiscussion(
                id: discussion.id,
                appendingAgentStatement: try PortableResearchStatement(
                    id: agent.id,
                    author: .agent,
                    kind: .discussionTurn,
                    attribution: agent.attribution,
                    text: "A conflicting retry.",
                    createdAt: Date(timeIntervalSince1970: 31)
                ),
                participatingNotes: [],
                finishedAt: Date(timeIntervalSince1970: 31)
            )
        }
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

    @Test("Discarding a participating active Discussion does not rewrite finished Records")
    func discussionDiscardDoesNotRewriteFinishedRecord() async throws {
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
        let removed = try await store.discardActiveDiscussions(noteIDs: [deletedNoteID])

        #expect(removed == [active.id])
        #expect(try await store.activeDiscussions().discussions.isEmpty)
        let retained = try await store.record(id: finished.id)
        #expect(retained == finished)
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
        let finished = try makePortableRecord()
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await creatingStore.createFinishedRecord(finished)
        }
        await #expect(throws: ResearchRecordStoreV1Error.self) {
            _ = try await creatingStore.settle(
                noteID: discussion.primaryNoteID,
                fingerprint: DocumentFingerprint(content: "late"),
                rationale: nil
            )
        }
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

    @Test("Unsupported Settlement bytes remain unchanged and nonauthorizing")
    func unsupportedSettlementIsPreserved() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let noteID = UUID()
        _ = try await store.settle(
            noteID: noteID,
            fingerprint: DocumentFingerprint(content: "legacy"),
            rationale: nil
        )
        let url = fixture.control
            .appendingPathComponent(
                "research-records/v1/settlements",
                isDirectory: true
            )
            .appendingPathComponent(noteID.uuidString.lowercased() + ".json")
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        object["schema_version"] = 1
        var settlement = try #require(object["settlement"] as? [String: Any])
        settlement.removeValue(forKey: "coveredActivities")
        object["settlement"] = settlement
        let legacyBytes = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        try legacyBytes.write(to: url)

        let listing = try await store.settlementListing()
        #expect(listing.settlements.isEmpty)
        #expect(listing.issues.map(\.fileName) == [url.lastPathComponent])
        await #expect(throws: PortableResearchRecordError.self) {
            _ = try await store.settle(
                noteID: noteID,
                fingerprint: DocumentFingerprint(content: "current"),
                rationale: nil
            )
        }
        #expect(try Data(contentsOf: url) == legacyBytes)
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
    @Test("Bounded write facts and Action completion commit in one record transition")
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
        let completion = ResearchActionRunCompletion(
            runID: runID,
            actionID: seed.snapshot.request.actionID,
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
            submissionDigest: "action-submission-digest",
            runID: runID
        )
        #expect(completed.writeReport == report)
        #expect(completed.completion == completion)
        #expect(completed.completionSubmissionDigest == "action-submission-digest")
        #expect(try await store.record(id: runID) == completed)

        let repeated = try await store.setCompletion(
            completion,
            writeReport: report,
            submissionDigest: "action-submission-digest",
            runID: runID
        )
        #expect(repeated == completed)
    }

    @Test("A completed Local Execution compacts to one terminal receipt")
    func completedExecutionCompacts() async throws {
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
        let completion = ResearchActionRunCompletion(
            runID: runID,
            actionID: seed.snapshot.request.actionID,
            state: .complete,
            recordTitle: try ResearchRecordTitle("Terminal receipt"),
            targetFingerprint: target.fingerprint,
            materialFingerprints: [:],
            summary: "Finished.",
            didModifyTarget: false,
            fidelityOutcomes: [],
            completedAt: report.completedAt
        )
        _ = try await store.setCompletion(
            completion,
            writeReport: report,
            submissionDigest: "digest",
            runID: runID
        )

        let compacted = try await store.compactCompleted(runID: runID)

        #expect(compacted.isCompacted)
        #expect(compacted.preparedInstructions.isEmpty)
        #expect(compacted.boundedWriteSet.entries.isEmpty)
        #expect(compacted.writeSetExtensionRecords.isEmpty)
        #expect(compacted.documentWriteRecords.isEmpty)
        #expect(compacted.writeConflictResolutionRecords.isEmpty)
        #expect(compacted.writeReport == report)
        #expect(compacted.completion == completion)
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

    @Test("An unwrapped execution requires explicit byte-exact archival before deletion")
    func corruptLocalExecutionFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let good = try makeLocalExecutionRecord(runID: UUID())
        _ = try await store.create(good)
        let corruptID = UUID()
        let corruptURL = store.storageURL
            .appendingPathComponent(corruptID.uuidString.lowercased() + ".json")
        let legacyBytes = Data("{\"schema_version\":16}".utf8)
        try legacyBytes.write(to: corruptURL)

        let listing = try await store.listing()
        #expect(listing.records.map(\.id) == [good.id])
        #expect(listing.issues.count == 1)
        await #expect(throws: Error.self) {
            _ = try await store.record(id: corruptID)
        }
        let recovery: LocalResearchExecutionRecoveryPreview
        do {
            try await store.validateDeletionAuthority()
            Issue.record("Expected unwrapped local execution recovery.")
            return
        } catch SystemTrashPreparationError.localExecutionRecoveryRequired(let preview) {
            recovery = preview
        }
        #expect(recovery.items == [LocalResearchExecutionRecoveryItem(
            fileName: corruptURL.lastPathComponent,
            fingerprint: DocumentFingerprint(data: legacyBytes)
        )])

        let changedBytes = Data("{\"schema_version\":15}".utf8)
        try changedBytes.write(to: corruptURL)
        await #expect(throws: LocalResearchExecutionStoreError.self) {
            _ = try await store.archiveUnsupportedExecutions(recovery)
        }
        #expect(try Data(contentsOf: corruptURL) == changedBytes)
        let archivedURL = store.storageURL
            .appendingPathComponent("unsupported-executions", isDirectory: true)
            .appendingPathComponent(corruptURL.lastPathComponent)
        #expect(!FileManager.default.fileExists(atPath: archivedURL.path))

        try legacyBytes.write(to: corruptURL)
        let commit = try await store.archiveUnsupportedExecutions(recovery)
        #expect(commit.archivedFileNames == [corruptURL.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: corruptURL.path))
        #expect(try Data(contentsOf: archivedURL) == legacyBytes)
        try await store.validateDeletionAuthority()
    }

    @Test("Stable Local Execution envelope scopes deletion across payload revisions")
    func localExecutionSchemaCutover() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let record = try makeLocalExecutionRecord(runID: UUID())
        let stored = try await store.create(record)
        #expect(stored == record)

        let url = store.storageURL
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        let currentBytes = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(
            LocalResearchExecutionEnvelope.self,
            from: currentBytes
        )
        #expect(envelope.formatIdentifier == LocalResearchExecutionEnvelope.formatIdentifier)
        #expect(envelope.formatRevision == LocalResearchExecutionEnvelope.currentFormatRevision)
        #expect(envelope.payloadRevision == LocalResearchExecutionEnvelope.currentPayloadRevision)
        #expect(try JSONDecoder().decode(
            LocalResearchExecutionRecord.self,
            from: envelope.payload
        ) == stored)
        var object = try #require(
            JSONSerialization.jsonObject(with: currentBytes) as? [String: Any]
        )
        object["payload_revision"] = LocalResearchExecutionEnvelope
            .currentPayloadRevision + 1
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let listing = try await store.listing()
        #expect(listing.records.isEmpty)
        #expect(listing.issues.map(\.fileName) == [url.lastPathComponent])
        try await store.validateDeletionAuthority()
        let noteIDs = LocalResearchExecutionStore.noteIDs(in: record)
        #expect(try await store.activeExecutionIDs(containing: [UUID()]).isEmpty)
        do {
            _ = try await store.activeExecutionIDs(containing: noteIDs)
            Issue.record("Expected scoped recovery for an unsupported live payload.")
        } catch SystemTrashPreparationError.localExecutionRecoveryRequired(let preview) {
            #expect(Set(preview.affectedNoteIDs ?? []) == noteIDs)
            #expect(preview.items.map(\.fileName) == [url.lastPathComponent])
        }
        await #expect(throws: LocalResearchExecutionStoreError.self) {
            _ = try await store.record(id: record.id)
        }
    }

    @Test("A nested payload schema failure has scoped exact-byte recovery")
    func nestedLocalExecutionPayloadRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let noteID = UUID()
        let record = try makeLocalExecutionRecord(runID: UUID(), noteID: noteID)
        _ = try await store.create(record)
        let url = store.storageURL
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        let envelope = try JSONDecoder().decode(
            LocalResearchExecutionEnvelope.self,
            from: Data(contentsOf: url)
        )
        var payload = try #require(
            JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any]
        )
        var boundedWriteSet = try #require(
            payload["bounded_write_set"] as? [String: Any]
        )
        boundedWriteSet["schema_version"] = ResearchBoundedWriteSet
            .currentSchemaVersion + 1
        payload["bounded_write_set"] = boundedWriteSet
        let unreadablePayload = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        )
        let unreadableEnvelope = LocalExecutionEnvelopeFixture(
            envelope: envelope,
            payload: unreadablePayload
        )
        let unreadableBytes = try JSONEncoder().encode(unreadableEnvelope)
        try unreadableBytes.write(to: url)

        try await store.validateDeletionAuthority()
        #expect(try await store.activeExecutionIDs(containing: [UUID()]).isEmpty)
        let recovery: LocalResearchExecutionRecoveryPreview
        do {
            _ = try await store.activeExecutionIDs(containing: [noteID])
            Issue.record("Expected nested-payload recovery for the participating Note.")
            return
        } catch SystemTrashPreparationError.localExecutionRecoveryRequired(let preview) {
            recovery = preview
        }
        #expect(recovery.affectedNoteIDs == [noteID])
        #expect(recovery.items == [LocalResearchExecutionRecoveryItem(
            fileName: url.lastPathComponent,
            fingerprint: DocumentFingerprint(data: unreadableBytes)
        )])

        _ = try await store.archiveUnsupportedExecutions(recovery)
        let archivedURL = store.storageURL
            .appendingPathComponent("unsupported-executions", isDirectory: true)
            .appendingPathComponent(url.lastPathComponent)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: archivedURL) == unreadableBytes)
        #expect(try await store.activeExecutionIDs(containing: [noteID]).isEmpty)
    }

    @Test("Terminal envelope permits cleanup without decoding its payload revision")
    func terminalEnvelopePermitsUnsupportedPayloadCleanup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let noteID = UUID()
        let record = try makeLocalExecutionRecord(runID: UUID(), noteID: noteID)
        _ = try await store.create(record)
        let url = store.storageURL
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        var envelope = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url))
                as? [String: Any]
        )
        envelope["payload_revision"] = LocalResearchExecutionEnvelope
            .currentPayloadRevision + 1
        envelope["authority_state"] = "terminal"
        try JSONSerialization.data(withJSONObject: envelope).write(to: url)

        try await store.validateDeletionAuthority()
        #expect(try await store.activeExecutionIDs(containing: [noteID]).isEmpty)
        #expect(try await store.purgeExecutions(containing: [noteID]) == [record.id])
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Agent creation schema failure is isolated from system Trash authority")
    func agentAnalysisCreationSchemaIsNotDeletionAuthority() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let localStore = try fixture.localStore()
        let store = try fixture.creationReservationStore()
        let runID = UUID()
        let url = store.storageURL
            .appendingPathComponent(runID.uuidString.lowercased() + ".json")
        try Data("{\"schema_version\":999}".utf8).write(to: url)

        try await localStore.validateDeletionAuthority()
        do {
            _ = try await store.reservation(id: runID)
            Issue.record("Expected the unsupported creation-record schema to fail closed.")
        } catch AgentAnalysisCreationReservationStoreError
            .unsupportedSchemaVersion(let version) {
            #expect(version == 999)
        }
    }

    @Test("Agent Analysis creation binding phases are strict and exact-request idempotent")
    func agentAnalysisCreationBindingPhases() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.creationReservationStore()
        let runID = UUID()
        let noteID = UUID()
        let target = VaultQualifiedNoteID(
            vaultID: UUID(),
            relativePath: "Agent/Bound Analysis.md"
        )
        let binding = try AnalysisZoteroBinding(
            noteID: noteID,
            library: .user,
            itemKey: "BOUND001"
        )
        let record = try AgentAnalysisCreationReservation(
            triptychID: fixture.triptychID,
            runID: runID,
            requestFingerprint: DocumentFingerprint(content: "exact request"),
            creationPayloadFingerprint: DocumentFingerprint(content: "exact creation"),
            startRequestFingerprint: DocumentFingerprint(content: "exact start"),
            target: target,
            reservedIdentityID: noteID,
            requestedBinding: binding,
            sourceRoute: nil,
            initialMetadata: try AnalysisCreationMetadata(
                sourceType: .journalArticle
            ),
            initialAuthoredYAML: nil,
            academicPurpose: "Exact purpose"
        )

        #expect(try await store.create(record) == record)
        #expect(try await store.create(record) == record)
        let revisedReservation = try AgentAnalysisCreationReservation(
            triptychID: fixture.triptychID,
            runID: runID,
            requestFingerprint: DocumentFingerprint(content: "current Settings request"),
            creationPayloadFingerprint: DocumentFingerprint(content: "current Settings creation"),
            startRequestFingerprint: DocumentFingerprint(content: "current Settings start"),
            target: target,
            reservedIdentityID: noteID,
            requestedBinding: binding,
            sourceRoute: nil,
            initialMetadata: record.initialMetadata,
            initialAuthoredYAML: record.initialAuthoredYAML,
            academicPurpose: "Exact purpose"
        )
        #expect(try await store.revisePrecommit(
            expected: record,
            replacement: revisedReservation
        ) == revisedReservation)
        await #expect(throws: AgentAnalysisCreationReservationStoreError.self) {
            _ = try await store.revisePrecommit(
                expected: record,
                replacement: revisedReservation
            )
        }
        let committedSource = DocumentFingerprint(content: "committed source")
        #expect(try await store.confirmSource(
            runID: runID,
            fingerprint: committedSource
        ).committedSourceFingerprint == committedSource)
        #expect(try await store.confirmSource(
            runID: runID,
            fingerprint: committedSource
        ).committedSourceFingerprint == committedSource)
        await #expect(throws: AgentAnalysisCreationReservationStoreError.self) {
            _ = try await store.confirmSource(
                runID: runID,
                fingerprint: DocumentFingerprint(content: "different source")
            )
        }
        #expect(try await store.advanceBinding(
            runID: runID,
            to: .writing
        ).bindingState == .writing)
        #expect(try await store.advanceBinding(
            runID: runID,
            to: .retryable
        ).bindingState == .retryable)
        _ = try await store.advanceBinding(
            runID: runID,
            to: .writing
        )
        #expect(try await store.advanceBinding(
            runID: runID,
            to: .committed
        ).bindingState == .committed)
        let committed = try await store.reservation(id: runID)
        let forbiddenRevision = try AgentAnalysisCreationReservation(
            triptychID: fixture.triptychID,
            runID: runID,
            requestFingerprint: DocumentFingerprint(content: "too late"),
            creationPayloadFingerprint: DocumentFingerprint(content: "too late creation"),
            startRequestFingerprint: DocumentFingerprint(content: "too late start"),
            target: target,
            reservedIdentityID: noteID,
            requestedBinding: binding,
            sourceRoute: nil,
            initialMetadata: record.initialMetadata,
            initialAuthoredYAML: record.initialAuthoredYAML,
            academicPurpose: "Exact purpose",
            committedSourceFingerprint: committedSource,
            bindingState: .committed
        )
        await #expect(throws: AgentAnalysisCreationReservationStoreError.self) {
            _ = try await store.revisePrecommit(
                expected: committed,
                replacement: forbiddenRevision
            )
        }
        await #expect(throws: AgentAnalysisCreationReservationStoreError.self) {
            _ = try await store.advanceBinding(
                runID: runID,
                to: .writing
            )
        }

        let changed = try AgentAnalysisCreationReservation(
            triptychID: fixture.triptychID,
            runID: runID,
            requestFingerprint: DocumentFingerprint(content: "changed request"),
            creationPayloadFingerprint: DocumentFingerprint(content: "changed creation"),
            startRequestFingerprint: DocumentFingerprint(content: "changed start"),
            target: target,
            reservedIdentityID: noteID,
            requestedBinding: binding,
            sourceRoute: nil,
            initialMetadata: record.initialMetadata,
            initialAuthoredYAML: record.initialAuthoredYAML,
            academicPurpose: "Changed purpose"
        )
        await #expect(throws: AgentAnalysisCreationReservationStoreError.self) {
            _ = try await store.create(changed)
        }

        let researcherProvided = try AgentAnalysisCreationReservation(
            triptychID: fixture.triptychID,
            runID: UUID(),
            requestFingerprint: DocumentFingerprint(content: "researcher request"),
            creationPayloadFingerprint: DocumentFingerprint(content: "researcher creation"),
            startRequestFingerprint: DocumentFingerprint(content: "researcher start"),
            target: VaultQualifiedNoteID(
                vaultID: target.vaultID,
                relativePath: "Researcher Provided.md"
            ),
            reservedIdentityID: UUID(),
            requestedBinding: nil,
            sourceRoute: .researcherProvided,
            initialMetadata: try AnalysisCreationMetadata(
                sourceType: .journalArticle
            ),
            initialAuthoredYAML: nil,
            academicPurpose: nil
        )
        let storedResearcher = try await store.create(
            researcherProvided
        )
        #expect(storedResearcher == researcherProvided)
        #expect(storedResearcher.schemaVersion == AgentAnalysisCreationReservation.currentSchemaVersion)
        #expect(storedResearcher.bindingState == nil)
        await #expect(throws: AgentAnalysisCreationReservationStoreError.self) {
            _ = try await store.advanceBinding(
                runID: researcherProvided.runID,
                to: .writing
            )
        }
    }

    @Test("Current Local Execution rejects undeclared fields including raw keys")
    func localExecutionRejectsUnknownFields() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let record = try makeLocalExecutionRecord(runID: UUID())
        _ = try await store.create(record)
        let url = store.storageURL
            .appendingPathComponent(record.id.uuidString.lowercased() + ".json")
        let currentBytes = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(
            LocalResearchExecutionEnvelope.self,
            from: currentBytes
        )
        let payload = envelope.payload
        var object = try #require(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        object["raw_activity_key"] = "must-never-persist"
        let modifiedPayload = try JSONSerialization.data(withJSONObject: object)
        let modifiedEnvelope = LocalExecutionEnvelopeFixture(
            envelope: envelope,
            payload: modifiedPayload
        )
        try JSONEncoder().encode(modifiedEnvelope).write(to: url)

        let listing = try await store.listing()
        #expect(listing.records.isEmpty)
        #expect(listing.issues.map(\.fileName) == [url.lastPathComponent])
        try await store.validateDeletionAuthority()
        let affectedNoteIDs = LocalResearchExecutionStore.noteIDs(in: record)
        do {
            _ = try await store.activeExecutionIDs(containing: affectedNoteIDs)
            Issue.record("Expected scoped recovery for the rejected current payload.")
        } catch SystemTrashPreparationError.localExecutionRecoveryRequired(let preview) {
            #expect(Set(preview.affectedNoteIDs ?? []) == affectedNoteIDs)
            #expect(preview.items.map(\.fileName) == [url.lastPathComponent])
        }
        await #expect(throws: LocalResearchExecutionStoreError.self) {
            _ = try await store.record(id: record.id)
        }
    }

    @Test("Durable Analyze completion freezes supplied recommendations and permits omission")
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
        let awaiting = ResearchActionRunCompletion(
            runID: runID,
            actionID: .analyze,
            state: .complete,
            recordTitle: try ResearchRecordTitle("Analyze completion"),
            targetFingerprint: local.snapshot.request.target.fingerprint,
            materialFingerprints: [:],
            summary: "Analyze completion includes the Method fidelity self-check.",
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
        let tamperedTerminal = ResearchActionRunCompletion(
            runID: runID,
            actionID: .analyze,
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
        await #expect(throws: LocalResearchExecutionStoreError.self) {
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
        let currentBytes = try Data(contentsOf: url)
        var envelope = try #require(
            JSONSerialization.jsonObject(with: currentBytes) as? [String: Any]
        )
        let encodedPayload = try #require(envelope["payload"] as? String)
        let payload = try #require(Data(base64Encoded: encodedPayload))
        var object = try #require(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        var completion = try #require(object["completion"] as? [String: Any])
        completion.removeValue(forKey: "literatureRecommendations")
        object["completion"] = completion
        let modifiedPayload = try JSONSerialization.data(withJSONObject: object)
        envelope["payload"] = modifiedPayload.base64EncodedString()
        envelope["payload_fingerprint"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(DocumentFingerprint(data: modifiedPayload))
        )
        try JSONSerialization.data(withJSONObject: envelope).write(to: url)

        let listing = try await store.listing()
        #expect(listing.records.count == 1)
        #expect(listing.issues.isEmpty)
        #expect(try await store.record(id: runID).completion?
            .literatureRecommendations == nil)
    }

    @Test("System Trash cleanup removes only executions containing the Note")
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

    @Test("Prepared execution is an active deletion conflict only for participating Notes")
    func activeExecutionDetectionIsIdentityBound() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.localStore()
        let activeNoteID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let unrelatedNoteID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let activeRun = try makeLocalExecutionRecord(
            runID: UUID(),
            noteID: activeNoteID
        )
        _ = try await store.create(activeRun)

        #expect(try await store.activeExecutionIDs(containing: [activeNoteID]) == [activeRun.id])
        #expect(try await store.activeExecutionIDs(containing: [unrelatedNoteID]).isEmpty)
    }

    @Test("Method Feedback replaces only the parent Record comment in one CAS")
    func methodFeedbackCAS() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.portableStore()
        let original = try makePortableRecord()
        _ = try await store.createFinishedRecord(original)
        let resultFingerprint = try original.finalizedResultFingerprint()
        let first = try await store.saveMethodFeedback(
            ResearchMethodFeedbackDraft(
                text: "Ask for a counter-reading before synthesis."
            ),
            recordID: original.id,
            expectedMethodFeedbackRevision: nil,
            expectedResultFingerprint: resultFingerprint,
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let firstFeedbackRevision = try #require(first.methodFeedbackComment?.revision)
        #expect(try first.finalizedResultFingerprint() == resultFingerprint)

        let revised = try await store.saveMethodFeedback(
            ResearchMethodFeedbackDraft(
                text: "Require the counter-reading before synthesis."
            ),
            recordID: original.id,
            expectedMethodFeedbackRevision: firstFeedbackRevision,
            expectedResultFingerprint: resultFingerprint,
            updatedAt: Date(timeIntervalSince1970: 31)
        )
        let revisedFeedbackRevision = try #require(
            revised.methodFeedbackComment?.revision
        )
        #expect(revisedFeedbackRevision != firstFeedbackRevision)

        await #expect(
            throws: PortableResearchMethodFeedbackMutationError
                .staleMethodFeedbackRevision
        ) {
            _ = try await store.saveMethodFeedback(
                nil,
                recordID: original.id,
                expectedMethodFeedbackRevision: nil,
                expectedResultFingerprint: resultFingerprint
            )
        }

        let cleared = try await store.saveMethodFeedback(
            nil,
            recordID: original.id,
            expectedMethodFeedbackRevision: revisedFeedbackRevision,
            expectedResultFingerprint: resultFingerprint
        )
        #expect(cleared.methodFeedbackComment == nil)
        #expect(try cleared.finalizedResultFingerprint() == resultFingerprint)

        enum InjectedFailure: Error { case afterRename }
        await store.setPostCommitFaultForTesting { _ in
            throw InjectedFailure.afterRename
        }
        do {
            _ = try await store.saveMethodFeedback(
                ResearchMethodFeedbackDraft(
                    text: "Retain this feedback."
                ),
                recordID: original.id,
                expectedMethodFeedbackRevision: nil,
                expectedResultFingerprint: resultFingerprint
            )
            Issue.record("Expected Method Feedback replacement commit uncertainty.")
        } catch let error as ResearchRecordStoreV1Error {
            guard case .replacementCommitUncertain = error else {
                Issue.record("Unexpected Method Feedback replacement error: \(error)")
                return
            }
        }
        let reconciled = try await store.record(id: original.id)
        #expect(reconciled.methodFeedbackComment?.text == "Retain this feedback.")
        #expect(try reconciled.finalizedResultFingerprint() == resultFingerprint)
    }

    @Test("Settle derives the current Note's confirmed Agent activities")
    func settlementCoversCurrentAgentActivities() async throws {
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
        let settlement = try await store.settle(
            noteID: participant.noteID,
            fingerprint: ending,
            rationale: nil,
            settledAt: Date(timeIntervalSince1970: 50)
        )
        #expect(settlement.coveredActivities == [SettlementActivityReference(
            recordID: changed.id,
            noteID: participant.noteID
        )])

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
        #expect(try await store.latestSettlement(noteID: participant.noteID)?
            .coveredActivities == settlement.coveredActivities)
        let updated = try await store.settle(
            noteID: participant.noteID,
            fingerprint: laterEnding,
            rationale: nil,
            settledAt: Date(timeIntervalSince1970: 60)
        )
        #expect(Set(updated.coveredActivities) == [
            SettlementActivityReference(
                recordID: changed.id,
                noteID: participant.noteID
            ),
            SettlementActivityReference(
                recordID: lateRecord.id,
                noteID: participant.noteID
            ),
        ])
        #expect(updated.coveredActivities.allSatisfy {
            $0.noteID != secondNoteID
        })
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
            action: try ResearchActionRecordIdentity(snapshot: action),
            method: try PortableResearchMethodReference(snapshot: action),
            sourceReference: actionID == .analyze
                ? try ResearchSourceReference(
                    identity: .localFile(id: id),
                    displayName: "Source.pdf",
                    fingerprint: DocumentFingerprint(content: "source bytes")
                )
                : nil,
            analysisSourceRoute: actionID == .analyze ? .scholiumSource : nil,
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
        let request = ResearchActionRunRequest(
            actionID: actionID,
            target: action.target
        )
        let snapshot = try ResearchActionRunSnapshot(
            runID: runID,
            request: request,
            actionSnapshot: action,
            recordID: runID,
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
            skillFolder: .machineLocal()
        )
        return try ResearchActionSnapshot(
            definition: definition,
            target: target,
            method: try ResearchSkillBindingSnapshot(
                registration: registration,
                registrationRevision: DocumentFingerprint(
                    content: "registrations"
                ),
                skillFolderPath: "/Users/researcher/Skills/\(actionID.rawValue)",
                skillFolderIsAvailable: true
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
                editableMetadataKeys: []
            )
        )
    }

    private func writeReference(
        _ target: ResearchActionNoteSnapshot
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

    private struct LocalExecutionEnvelopeFixture: Codable {
        let formatIdentifier: String
        let formatRevision: Int
        let payloadRevision: Int
        let runID: UUID
        let triptychID: UUID
        let noteIDs: [UUID]
        let authorityState: LocalResearchExecutionEnvelope.AuthorityState
        let payloadFingerprint: DocumentFingerprint
        let payload: Data

        init(envelope: LocalResearchExecutionEnvelope, payload: Data) {
            formatIdentifier = envelope.formatIdentifier
            formatRevision = envelope.formatRevision
            payloadRevision = envelope.payloadRevision
            runID = envelope.runID
            triptychID = envelope.triptychID
            noteIDs = envelope.noteIDs
            authorityState = envelope.authorityState
            payloadFingerprint = DocumentFingerprint(data: payload)
            self.payload = payload
        }

        private enum CodingKeys: String, CodingKey {
            case formatIdentifier = "format_identifier"
            case formatRevision = "format_revision"
            case payloadRevision = "payload_revision"
            case runID = "run_id"
            case triptychID = "triptych_id"
            case noteIDs = "note_ids"
            case authorityState = "authority_state"
            case payloadFingerprint = "payload_fingerprint"
            case payload
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

        func creationReservationStore() throws -> AgentAnalysisCreationReservationStore {
            try AgentAnalysisCreationReservationStore(
                applicationSupportURL: support,
                triptychID: triptychID
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
