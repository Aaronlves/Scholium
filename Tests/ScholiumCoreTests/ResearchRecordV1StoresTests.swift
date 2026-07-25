import Foundation
import ScholiumContracts
@testable import ScholiumCore
import Testing

@Suite("Portable Research Record v1 and Local Execution v2")
struct ResearchRecordV1StoresTests {
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
        let listing = try await reopened.listing(location: .records)
        #expect(listing.records.map(\.id) == [record.id])
        #expect(listing.issues.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: abandoned.path))
        #expect(try await reopened.record(id: record.id) == stored)
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

        let listing = try await store.listing(location: .records)
        #expect(listing.records.map(\.id) == [record.id])
        #expect(listing.issues.count == 1)
        #expect(listing.issues.first?.fileName == corruptURL.lastPathComponent)
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
        let listing = try await first.listing(location: .records)
        #expect(listing.records.count == 1)
        #expect(listing.issues.isEmpty)
    }

    @Test("Settle keeps one portable current state per Note")
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

        #expect(first == repeated)
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

    @Test("Local Execution v2 ignores a matching legacy grant")
    func legacyGrantCannotAuthorizeV2Completion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let runID = UUID()
        let localStore = try fixture.localStore()
        let seed = try makeLocalExecutionRecord(runID: runID, grant: nil)
        let target = seed.snapshot.request.target
        let localAuthorization = try LocalResearchExecutionStore.prepareGrant(
            activityID: runID,
            origin: activityReference(target),
            writeScope: .currentNote,
            allowedTargets: [activityReference(target)],
            startingFingerprints: [target.noteID: target.fingerprint],
            issuedAt: Date(timeIntervalSince1970: 10)
        )
        let localRecord = try makeLocalExecutionRecord(
            runID: runID,
            grant: localAuthorization.grant
        )
        _ = try await localStore.create(localRecord)

        let legacyDirectory = fixture.triptychSupport
            .appendingPathComponent("research-activity", isDirectory: true)
        let legacyStore = ResearchActivityStore(storageURL: legacyDirectory)
        let legacy = try await legacyStore.issueGrant(
            activityID: runID,
            origin: activityReference(target),
            writeScope: .currentNote,
            allowedTargets: [activityReference(target)],
            startingFingerprints: [target.noteID: target.fingerprint],
            issuedAt: Date(timeIntervalSince1970: 10)
        )

        await #expect(throws: ResearchActivityGrantError.self) {
            _ = try await localStore.authorizeCompletion(
                activityID: runID,
                activityKey: legacy.activityKey,
                at: Date(timeIntervalSince1970: 20)
            )
        }
        #expect(try await localStore.authorizeCompletion(
            activityID: runID,
            activityKey: localAuthorization.activityKey,
            at: Date(timeIntervalSince1970: 20)
        ).state == .active)
        #expect(await legacyStore.grant(activityID: runID)?.state == .active)
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

    @Test("Local Execution v2 rejects undeclared fields including raw keys")
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

    private func makePortableRecord() throws -> PortableResearchRecord {
        let action = try makeActionSnapshot()
        let note = try PortableResearchNoteRevision(
            noteID: action.target.noteID,
            note: action.target.note,
            role: action.target.role,
            title: action.target.title,
            startingRevision: action.target.fingerprint,
            endingRevision: action.target.fingerprint
        )
        return try PortableResearchRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            triptychID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            kind: .action,
            action: ResearchActionRecordIdentity(snapshot: action),
            method: try PortableResearchMethodReference(snapshot: action),
            participatingNotes: [note],
            statements: [try PortableResearchStatement(
                author: .agent,
                kind: .agentFeedback,
                attribution: "Agent",
                text: "No source change was needed.",
                createdAt: Date(timeIntervalSince1970: 20)
            )],
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20)
        )
    }

    private func makeLocalExecutionRecord(
        runID: UUID,
        grant: ResearchActivityGrant?,
        noteID: UUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    ) throws -> LocalResearchExecutionRecord {
        let action = try makeActionSnapshot(noteID: noteID)
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
            grant: grant
        )
    }

    private func makeActionSnapshot(
        noteID: UUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    ) throws -> ResearchActionSnapshot {
        let definition = ResearchActionDefinition.synthesize
        let target = ResearchActionNoteSnapshot(
            noteID: noteID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                relativePath: "Problem.md"
            ),
            role: .topic,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: "# Topic\n"),
            title: "Problem"
        )
        let profile = try ResearchActionProfile(
            definition: definition,
            buttonName: "Synthesize",
            order: 100,
            applicableRoles: [.topic],
            showInActions: true,
            modules: [],
            sourceRequirement: .none,
            capabilities: try ResearchActionCapabilityDeclaration(
                readableRoles: [.topic],
                candidateWritableRoles: [.topic],
                candidateWriteOperations: [.modifyMarkdown]
            ),
            feedbackRequirement: .requested
        )
        return try ResearchActionSnapshot(
            definition: definition,
            target: target,
            method: try ResearchActionMethodSnapshot(
                packageID: "scholium-synthesize",
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
            parameters: try ResearchActionParameterModel(profile: profile),
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
