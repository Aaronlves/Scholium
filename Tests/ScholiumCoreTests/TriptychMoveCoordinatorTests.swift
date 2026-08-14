import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Triptych transactional note movement")
struct TriptychMoveCoordinatorTests {
    @Test("A move commits cross-vault resolved incoming rewrites")
    func commitsMoveAndCrossVaultRewrites() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try await fixture.create(
            vault: .paperAnalysis,
            path: "Sources/B.md",
            content: "\u{FEFF}# B\r\n"
        )
        _ = try await fixture.create(
            vault: .topicKnowledge,
            path: "Topics/A.md",
            content: "+[[Sources/B#Claim|paper]]\r\n"
        )
        let (documents, graph) = try await fixture.workspaceGraph()
        let sourceID = fixture.id(.paperAnalysis, "Sources/B.md")
        let destinationID = fixture.id(.paperAnalysis, "Sources/Renamed B.md")
        let plan = IncomingLinkRewriter.plan(
            documents: documents,
            graph: graph,
            moving: sourceID,
            to: destinationID
        )

        let commit = try await fixture.moveCoordinator().move(
            plan,
            expectedRevision: target.fingerprint
        )

        #expect(commit.movedNote == sourceID)
        #expect(commit.destination == destinationID)
        #expect(commit.rewrites.count == 1)
        #expect(try await fixture.repository(.paperAnalysis).load(relativePath: destinationID.relativePath).rawContent == "\u{FEFF}# B\r\n")
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await fixture.repository(.paperAnalysis).load(relativePath: sourceID.relativePath)
        }
        #expect(try await fixture.repository(.topicKnowledge).load(relativePath: "Topics/A.md").rawContent == "+[[Sources/Renamed B#Claim|paper]]\r\n")
    }

    @Test("A stale source fails before the destination or any rewrite mutates")
    func sourceConflictStopsBeforeMutation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try await fixture.create(vault: .paperAnalysis, path: "B.md", content: "old\n")
        let linked = try await fixture.create(vault: .topicKnowledge, path: "A.md", content: "[[B]]\n")
        let (documents, graph) = try await fixture.workspaceGraph()
        let plan = IncomingLinkRewriter.plan(
            documents: documents,
            graph: graph,
            moving: fixture.id(.paperAnalysis, "B.md"),
            to: fixture.id(.paperAnalysis, "C.md")
        )
        _ = try await fixture.repository(.paperAnalysis).save(
            relativePath: "B.md",
            changeSet: .exactContent("external\n"),
            expectedRevision: target.fingerprint
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await fixture.moveCoordinator().move(plan, expectedRevision: target.fingerprint)
        }
        #expect(try await fixture.repository(.paperAnalysis).load(relativePath: "B.md").rawContent == "external\n")
        #expect(try await fixture.repository(.topicKnowledge).load(relativePath: "A.md").fingerprint == linked.fingerprint)
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await fixture.repository(.paperAnalysis).load(relativePath: "C.md")
        }
    }

    @Test("Every incoming rewrite revision is checked before the note moves")
    func rewriteConflictStopsBeforeMutation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try await fixture.create(vault: .paperAnalysis, path: "B.md", content: "B\n")
        let linked = try await fixture.create(vault: .topicKnowledge, path: "A.md", content: "[[B]]\n")
        let plan = try await fixture.planMove(from: fixture.id(.paperAnalysis, "B.md"), to: "C.md")
        _ = try await fixture.repository(.topicKnowledge).save(
            relativePath: "A.md",
            changeSet: .exactContent("external [[B]]\n"),
            expectedRevision: linked.fingerprint
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await fixture.moveCoordinator().move(plan, expectedRevision: target.fingerprint)
        }
        #expect(try await fixture.repository(.paperAnalysis).load(relativePath: "B.md").fingerprint == target.fingerprint)
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await fixture.repository(.paperAnalysis).load(relativePath: "C.md")
        }
        #expect(try await fixture.repository(.topicKnowledge).load(relativePath: "A.md").rawContent == "external [[B]]\n")
    }

    @Test("Failure after one rewrite restores the move and exact source bytes")
    func failureAfterRewriteRollsBackEverything() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try await fixture.create(vault: .paperAnalysis, path: "B.md", content: "B\n")
        let topic = try await fixture.create(vault: .topicKnowledge, path: "A.md", content: "[[B]]\r\n")
        _ = try await fixture.create(vault: .output, path: "W.md", content: "+[[B|evidence]]\n")
        let plan = try await fixture.planMove(from: fixture.id(.paperAnalysis, "B.md"), to: "C.md")
        let coordinator = fixture.moveCoordinator(
            faults: TriptychTransactionFaultPlan(points: [.afterRewrite(0)])
        )

        await #expect(throws: TriptychTransactionError.self) {
            _ = try await coordinator.move(plan, expectedRevision: target.fingerprint)
        }

        #expect(try await fixture.repository(.paperAnalysis).load(relativePath: "B.md").rawContent == "B\n")
        await #expect(throws: VaultRepositoryError.self) {
            _ = try await fixture.repository(.paperAnalysis).load(relativePath: "C.md")
        }
        #expect(try await fixture.repository(.topicKnowledge).load(relativePath: "A.md").sourceBytes == topic.sourceBytes)
        #expect(try await fixture.recovery.pending().isEmpty)
    }

    @Test("A rollback race persists vault-qualified recovery for every affected file")
    func rollbackFailurePersistsRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try await fixture.create(vault: .paperAnalysis, path: "B.md", content: "B\n")
        _ = try await fixture.create(vault: .topicKnowledge, path: "A.md", content: "[[B]]\n")
        let plan = try await fixture.planMove(from: fixture.id(.paperAnalysis, "B.md"), to: "C.md")
        let coordinator = fixture.moveCoordinator(
            faults: TriptychTransactionFaultPlan(
                points: [.afterRewrite(0), .beforeRewriteRollback(0)]
            )
        )

        do {
            _ = try await coordinator.move(plan, expectedRevision: target.fingerprint)
            Issue.record("Expected recovery-required result")
        } catch let TriptychTransactionError.recoveryRequired(record) {
            #expect(record.files.contains { $0.role == .movedNote })
            #expect(record.files.contains { $0.role == .incomingLinkRewrite })
            #expect(record.files.contains { $0.vaultID == fixture.vaultID(.topicKnowledge) })
        }
        #expect(try await fixture.recovery.pending().count == 1)
        let reopened = try TriptychMutationRecoveryStore(
            storageURL: fixture.appSupport
                .appendingPathComponent("Triptychs/\(fixture.triptychID.uuidString)")
        )
        #expect(try await reopened.pending().count == 1)
    }

    @Test("Duplicate stems and identical relative paths are never rewritten")
    func ambiguousWorkspaceTargetIsNeverGuessed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try await fixture.create(vault: .paperAnalysis, path: "Shared/B.md", content: "one\n")
        _ = try await fixture.create(vault: .output, path: "Shared/B.md", content: "two\n")
        let source = try await fixture.create(vault: .topicKnowledge, path: "A.md", content: "[[Shared/B]]\n")
        let (documents, graph) = try await fixture.workspaceGraph()
        let plan = IncomingLinkRewriter.plan(
            documents: documents,
            graph: graph,
            moving: fixture.id(.paperAnalysis, "Shared/B.md"),
            to: fixture.id(.paperAnalysis, "Shared/C.md")
        )
        #expect(plan.rewrites.isEmpty)

        _ = try await fixture.moveCoordinator().move(plan, expectedRevision: target.fingerprint)
        #expect(try await fixture.repository(.topicKnowledge).load(relativePath: "A.md").fingerprint == source.fingerprint)
    }

    @Test("Unicode paths and exact BOM CRLF source survive a coordinated move")
    func unicodeAndEnvelopeFidelity() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try await fixture.create(
            vault: .paperAnalysis,
            path: "资料/é.md",
            content: "\u{FEFF}---\r\ntitle: \"é\" # exact\r\n---\r\n正文\r\n"
        )
        let link = try await fixture.create(
            vault: .topicKnowledge,
            path: "论题.md",
            content: "前文 +[[资料/é#标题|来源]] 后文\r\n"
        )
        let plan = try await fixture.planMove(
            from: fixture.id(.paperAnalysis, "资料/é.md"),
            to: "资料/研究.md"
        )
        _ = try await fixture.moveCoordinator().move(plan, expectedRevision: target.fingerprint)

        let moved = try await fixture.repository(.paperAnalysis).load(relativePath: "资料/研究.md")
        #expect(moved.sourceBytes == target.sourceBytes)
        let rewritten = try await fixture.repository(.topicKnowledge).load(relativePath: "论题.md")
        #expect(rewritten.rawContent == link.rawContent.replacingOccurrences(of: "资料/é", with: "资料/研究"))
    }

    @Test("Traversal, symlink escape, and repository identity mismatch fail closed")
    func containmentAndIdentityPreflight() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let target = try await fixture.create(vault: .paperAnalysis, path: "B.md", content: "B\n")
        let source = fixture.id(.paperAnalysis, "B.md")
        let (_, graph) = try await fixture.workspaceGraph()

        let traversal = IncomingLinkRewritePlan(
            movedNote: source,
            destination: fixture.id(.paperAnalysis, "../Escape.md"),
            graphGeneration: graph.generation,
            rewrites: []
        )
        await #expect(throws: TriptychTransactionError.self) {
            _ = try await fixture.moveCoordinator().move(traversal, expectedRevision: target.fingerprint)
        }

        let outside = fixture.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fixture.vaultURL(.paperAnalysis).appendingPathComponent("Escape"),
            withDestinationURL: outside
        )
        let symlink = IncomingLinkRewritePlan(
            movedNote: source,
            destination: fixture.id(.paperAnalysis, "Escape/C.md"),
            graphGeneration: graph.generation,
            rewrites: []
        )
        await #expect(throws: TriptychTransactionError.self) {
            _ = try await fixture.moveCoordinator().move(symlink, expectedRevision: target.fingerprint)
        }

        let wrongRepositories = [
            fixture.vaultID(.paperAnalysis): fixture.repository(.topicKnowledge),
        ]
        let mismatched = TriptychMoveCoordinator(
            triptychID: fixture.triptychID,
            repositories: wrongRepositories,
            recoveryStore: fixture.recovery
        )
        let ordinary = IncomingLinkRewritePlan(
            movedNote: source,
            destination: fixture.id(.paperAnalysis, "C.md"),
            graphGeneration: graph.generation,
            rewrites: []
        )
        await #expect(throws: TriptychTransactionError.self) {
            _ = try await mismatched.move(ordinary, expectedRevision: target.fingerprint)
        }
        #expect(try await fixture.repository(.paperAnalysis).load(relativePath: "B.md").fingerprint == target.fingerprint)
    }

    @Test("Independent recovery stores merge concurrent record and resolve mutations")
    func recoveryStoreSerializesAcrossRuntimes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try TriptychMutationRecoveryStore(storageURL: root)
        let second = try TriptychMutationRecoveryStore(storageURL: root)
        let triptychID = UUID()
        let vaultID = UUID()
        func record(_ path: String) -> TriptychMutationRecoveryRecord {
            TriptychMutationRecoveryRecord(
                triptychID: triptychID,
                operation: .noteSave,
                failure: "Fixture",
                files: [TriptychMutationRecoveryFile(
                    vaultID: vaultID,
                    path: path,
                    role: .savedNote,
                    beforeRevision: DocumentFingerprint(content: "before"),
                    intendedRevision: DocumentFingerprint(content: "after"),
                    observedRevision: nil,
                    state: .unreadable,
                    detail: "Fixture"
                )]
            )
        }
        let a = record("A.md")
        let b = record("B.md")

        async let firstRecord: Void = first.record(a)
        async let secondRecord: Void = second.record(b)
        _ = try await (firstRecord, secondRecord)
        #expect(Set(try await first.pending().map(\.id)) == [a.id, b.id])

        let c = record("C.md")
        async let resolveA: Void = first.resolve(a)
        async let recordC: Void = second.record(c)
        _ = try await (resolveA, recordC)
        #expect(Set(try await second.pending().map(\.id)) == [b.id, c.id])
    }

    @Test("A second store cannot clean another writer's live staging file")
    func recoveryStoreInitializationWaitsForWriter() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Init-Lock-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let stagingReady = BlockingTestSignal()
        let releaseWriter = BlockingTestSignal()
        let writer = try TriptychMutationRecoveryStore(
            storageURL: root,
            preCommitFault: { fileName in
                guard fileName.hasSuffix(".json") else { return }
                stagingReady.signal()
                _ = releaseWriter.wait(seconds: 10)
            }
        )
        let record = TriptychMutationRecoveryRecord(
            triptychID: UUID(),
            operation: .noteSave,
            failure: "Fixture",
            files: []
        )
        let write = Task { try await writer.record(record) }
        #expect(stagingReady.wait(seconds: 2))

        let initializerStarted = BlockingTestSignal()
        let initializerFinished = BlockingTestSignal()
        let second = Task.detached {
            initializerStarted.signal()
            defer { initializerFinished.signal() }
            return try TriptychMutationRecoveryStore(storageURL: root)
        }
        #expect(initializerStarted.wait(seconds: 2))
        #expect(!initializerFinished.wait(seconds: 0.05))
        releaseWriter.signal()

        try await write.value
        let reopened = try await second.value
        #expect(try await reopened.pending() == [record])
    }

    @Test("A stale resolver cannot delete newer evidence for the same recovery ID")
    func recoveryStoreResolveIsExact() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Exact-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try TriptychMutationRecoveryStore(storageURL: root)
        let second = try TriptychMutationRecoveryStore(storageURL: root)
        let triptychID = UUID()
        let vaultID = UUID()
        let id = UUID()
        func record(state: TriptychMutationRecoveryState) -> TriptychMutationRecoveryRecord {
            TriptychMutationRecoveryRecord(
                id: id,
                triptychID: triptychID,
                operation: .noteCreation,
                failure: "Fixture \(state.rawValue)",
                files: [TriptychMutationRecoveryFile(
                    vaultID: vaultID,
                    path: "Created.md",
                    role: .createdNote,
                    beforeRevision: nil,
                    intendedRevision: DocumentFingerprint(content: "created"),
                    observedRevision: nil,
                    state: state,
                    detail: "Fixture"
                )]
            )
        }
        let old = record(state: .missing)
        let updated = record(state: .externallyChanged)
        try await first.record(old)
        try await second.record(updated)

        await #expect(throws: (any Error).self) {
            try await first.resolve(old)
        }
        #expect(try await second.pending() == [updated])
    }

    @Test("Recovery-store post-replace uncertainty preserves authoritative readback")
    func recoveryStorePostReplaceUncertaintyIsDurable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Uncertain-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let normal = try TriptychMutationRecoveryStore(storageURL: root)
        let triptychID = UUID()
        let vaultID = UUID()
        func record(_ path: String) -> TriptychMutationRecoveryRecord {
            TriptychMutationRecoveryRecord(
                triptychID: triptychID,
                operation: .noteSave,
                failure: "Fixture",
                files: [TriptychMutationRecoveryFile(
                    vaultID: vaultID,
                    path: path,
                    role: .savedNote,
                    beforeRevision: DocumentFingerprint(content: "before"),
                    intendedRevision: DocumentFingerprint(content: "after"),
                    observedRevision: nil,
                    state: .unreadable,
                    detail: "Fixture"
                )]
            )
        }
        let first = record("First.md")
        try await normal.record(first)
        let uncertain = try TriptychMutationRecoveryStore(
            storageURL: root,
            postCommitFault: { fileName in
                guard fileName.hasSuffix(".json") else { return }
                throw CocoaError(.fileWriteUnknown)
            }
        )
        let second = record("Second.md")
        await #expect(throws: (any Error).self) {
            try await uncertain.record(second)
        }

        let reopened = try TriptychMutationRecoveryStore(storageURL: root)
        #expect(Set(try await reopened.pending().map(\.id)) == [first.id, second.id])
    }

    @Test("Recovery deletion uncertainty retries from authoritative absence")
    func recoveryStoreDeleteUncertaintyIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Delete-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let normal = try TriptychMutationRecoveryStore(storageURL: root)
        let record = TriptychMutationRecoveryRecord(
            triptychID: UUID(),
            operation: .noteSave,
            failure: "Fixture",
            files: [TriptychMutationRecoveryFile(
                vaultID: UUID(),
                path: "Note.md",
                role: .savedNote,
                beforeRevision: DocumentFingerprint(content: "before"),
                intendedRevision: DocumentFingerprint(content: "after"),
                observedRevision: nil,
                state: .unreadable,
                detail: "Fixture"
            )]
        )
        try await normal.record(record)
        let uncertain = try TriptychMutationRecoveryStore(
            storageURL: root,
            postCommitFault: { fileName in
                guard fileName.hasSuffix(".json") else { return }
                throw CocoaError(.fileWriteUnknown)
            }
        )
        await #expect(throws: (any Error).self) {
            try await uncertain.resolve(record)
        }

        let reopened = try TriptychMutationRecoveryStore(storageURL: root)
        #expect(try await reopened.pending().isEmpty)
        try await reopened.resolve(record)
        #expect(try await reopened.pending().isEmpty)
    }

    @Test("Reopening restores a recovery record isolated by an interrupted deletion")
    func recoveryStoreRestoresInterruptedDeletionIsolation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Delete-Crash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TriptychMutationRecoveryStore(storageURL: root)
        let record = TriptychMutationRecoveryRecord(
            triptychID: UUID(),
            operation: .noteSave,
            failure: "Fixture",
            files: []
        )
        try await store.record(record)
        let fileName = record.id.uuidString.lowercased() + ".json"
        let recordsURL = root.appendingPathComponent("records", isDirectory: true)
        try FileManager.default.moveItem(
            at: recordsURL.appendingPathComponent(fileName),
            to: recordsURL.appendingPathComponent(".scholium-deleting-\(fileName)")
        )

        let reopened = try TriptychMutationRecoveryStore(storageURL: root)
        #expect(try await reopened.pending() == [record])
        try await reopened.resolve(record)
        #expect(try await reopened.pending().isEmpty)
    }

    @Test("One corrupt recovery record does not hide valid pending duties")
    func recoveryStoreIsolatesCorruptRecord() async throws {
        let triptychID = UUID()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Corrupt-\(UUID().uuidString)")
        let root = base
            .appendingPathComponent(triptychID.uuidString)
            .appendingPathComponent("transactions")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try TriptychMutationRecoveryStore(storageURL: root)
        let valid = TriptychMutationRecoveryRecord(
            triptychID: triptychID,
            operation: .noteSave,
            failure: "Valid",
            files: []
        )
        try await store.record(valid)
        let corruptID = UUID()
        let corruptURL = root
            .appendingPathComponent("records", isDirectory: true)
            .appendingPathComponent(corruptID.uuidString.lowercased() + ".json")
        try Data("not json".utf8).write(to: corruptURL)

        let pending = try await store.pending()
        #expect(pending.contains { $0.id == valid.id })
        let issue = try #require(pending.first { $0.id == corruptID })
        #expect(issue.triptychID == triptychID)
        #expect(issue.files.first?.state == .unreadable)
        await #expect(throws: (any Error).self) {
            try await store.resolve(issue)
        }
        #expect(try Data(contentsOf: corruptURL) == Data("not json".utf8))
        #expect(try await store.pending().contains { $0.id == valid.id })
    }

    @Test("A non-record directory entry does not hide valid pending duties")
    func recoveryStoreIsolatesInvalidRecordName() async throws {
        let triptychID = UUID()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Invalid-Name-\(UUID().uuidString)")
        let root = base
            .appendingPathComponent(triptychID.uuidString)
            .appendingPathComponent("transactions")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try TriptychMutationRecoveryStore(storageURL: root)
        let valid = TriptychMutationRecoveryRecord(
            triptychID: triptychID,
            operation: .noteSave,
            failure: "Valid",
            files: []
        )
        try await store.record(valid)
        let invalidURL = root
            .appendingPathComponent("records", isDirectory: true)
            .appendingPathComponent(".DS_Store")
        try Data("finder metadata".utf8).write(to: invalidURL)

        let pending = try await store.pending()
        #expect(pending.contains { $0.id == valid.id })
        let issue = try #require(pending.first { $0.files.first?.path == "records/.DS_Store" })
        #expect(issue.triptychID == triptychID)
        #expect(issue.files.first?.state == .unreadable)
        await #expect(throws: (any Error).self) {
            try await store.resolve(issue)
        }
        #expect(try Data(contentsOf: invalidURL) == Data("finder metadata".utf8))
        #expect(try await store.pending().contains { $0.id == valid.id })
    }

    @Test("Many pending recovery records cannot consume a new record's byte budget")
    func recoveryStoreBudgetsEachRecordIndependently() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Scholium-Recovery-Budget-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TriptychMutationRecoveryStore(storageURL: root)
        let triptychID = UUID()
        let vaultID = UUID()
        let detail = String(repeating: "x", count: 100_000)
        for index in 0..<90 {
            try await store.record(TriptychMutationRecoveryRecord(
                triptychID: triptychID,
                operation: .noteSave,
                failure: "Fixture",
                files: [TriptychMutationRecoveryFile(
                    vaultID: vaultID,
                    path: "\(index).md",
                    role: .savedNote,
                    beforeRevision: DocumentFingerprint(content: "before"),
                    intendedRevision: DocumentFingerprint(content: "after"),
                    observedRevision: nil,
                    state: .unreadable,
                    detail: detail
                )]
            ))
        }
        let final = TriptychMutationRecoveryRecord(
            triptychID: triptychID,
            operation: .noteCreation,
            failure: "Small final duty",
            files: [TriptychMutationRecoveryFile(
                vaultID: vaultID,
                path: "Final.md",
                role: .createdNote,
                beforeRevision: nil,
                intendedRevision: DocumentFingerprint(content: "created"),
                observedRevision: nil,
                state: .unreadable,
                detail: "small"
            )]
        )
        try await store.record(final)

        let records = try await store.pending()
        #expect(records.count == 91)
        #expect(records.contains { $0.id == final.id })
    }

    private struct Fixture {
        let root: URL
        let appSupport: URL
        let triptychID = UUID()
        let repositories: [WorkspaceVaultSlot: VaultRepository]
        let ids: [WorkspaceVaultSlot: UUID]
        let recovery: TriptychMutationRecoveryStore

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Scholium-Move-\(UUID().uuidString)", isDirectory: true)
            appSupport = root.appendingPathComponent("Application Support", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            var built: [WorkspaceVaultSlot: VaultRepository] = [:]
            var vaultIDs: [WorkspaceVaultSlot: UUID] = [:]
            for slot in WorkspaceVaultSlot.allCases {
                let id = UUID()
                let url = root.appendingPathComponent(slot.displayName, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                built[slot] = try VaultRepository(
                    vaultURL: url,
                    identity: VaultIdentity(id: id, canonicalPath: url.path, bookmarkData: nil),
                    applicationSupportURL: appSupport,
                    vaultRole: slot.vaultRole
                )
                vaultIDs[slot] = id
            }
            repositories = built
            ids = vaultIDs
            recovery = try TriptychMutationRecoveryStore(
                storageURL: appSupport.appendingPathComponent("Triptychs/\(triptychID.uuidString)")
            )
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
        func vaultID(_ slot: WorkspaceVaultSlot) -> UUID { ids[slot]! }
        func vaultURL(_ slot: WorkspaceVaultSlot) -> URL {
            root.appendingPathComponent(slot.displayName, isDirectory: true)
        }
        func repository(_ slot: WorkspaceVaultSlot) -> VaultRepository { repositories[slot]! }
        var repositoryMap: [UUID: VaultRepository] {
            Dictionary(uniqueKeysWithValues: repositories.map { slot, repository in
                (vaultID(slot), repository)
            })
        }
        func id(_ slot: WorkspaceVaultSlot, _ path: String) -> VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: vaultID(slot), relativePath: path)
        }

        func create(
            vault slot: WorkspaceVaultSlot,
            path: String,
            content: String
        ) async throws -> NoteDocument {
            try await repository(slot).create(relativePath: path, content: content)
        }

        func workspaceGraph() async throws -> ([VaultQualifiedNoteID: NoteDocument], GraphSnapshot) {
            var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
            for slot in WorkspaceVaultSlot.allCases {
                for path in try await repository(slot).markdownRelativePaths(includeLifecycle: true) {
                    let document = try await repository(slot).load(relativePath: path)
                    documents[id(slot, path)] = document
                }
            }
            let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
            let catalog = documents.map { id, document in
                LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: semantics[id])
            }
            let graph = LinkGraphBuilder.build(
                generation: 23,
                catalog: catalog,
                documents: semantics,
                resolutionScope: .workspace
            )
            return (documents, graph)
        }

        func planMove(
            from source: VaultQualifiedNoteID,
            to destinationPath: String
        ) async throws -> IncomingLinkRewritePlan {
            let (documents, graph) = try await workspaceGraph()
            return IncomingLinkRewriter.plan(
                documents: documents,
                graph: graph,
                moving: source,
                to: VaultQualifiedNoteID(vaultID: source.vaultID, relativePath: destinationPath)
            )
        }

        func moveCoordinator(
            faults: TriptychTransactionFaultPlan = .none
        ) -> TriptychMoveCoordinator {
            TriptychMoveCoordinator(
                triptychID: triptychID,
                repositories: repositoryMap,
                recoveryStore: recovery,
                faultPlan: faults
            )
        }
    }
}

private final class BlockingTestSignal: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func signal() {
        semaphore.signal()
    }

    func wait(seconds: TimeInterval) -> Bool {
        semaphore.wait(timeout: .now() + seconds) == .success
    }
}
