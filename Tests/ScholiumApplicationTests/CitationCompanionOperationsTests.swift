import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication
@testable import ScholiumCore

@Suite("Managed citation companion operations")
struct CitationCompanionOperationsTests {
    private static let source =
        "\u{FEFF}---\r\ncustom: 'unchanged' # keep\r\n---\r\n# Agency\r\n\r\n[(Smith, 2024)](cite:cFirst) and [(Smith, 2024)](cite:cSecond).\r\n"

    private static func data(style: String = "original-style") -> ZoteroCitationData {
        let fields: [ZoteroCitationFieldData] = [
            .init(
                id: "cFirst", kind: .citation,
                code: "ITEM CSL_CITATION {\"citationItems\":[{\"id\":\"FIRST\"}],\"unknown\":[1,2]}",
                text: "(Smith, 2024)"),
            .init(
                id: "cSecond", kind: .citation,
                code: "ITEM CSL_CITATION {\"citationItems\":[{\"id\":\"SECOND\",\"locator\":\"12\"}]}",
                text: "(Smith, 2024)"),
        ]
        return .init(
            fields: fields, documentData: style,
            acceptedFields: fields.map { .init(id: $0.id, code: $0.code) })
    }

    @Test("Exact portable Markdown and metadata-only citation changes survive restart and publish")
    func saveAndRestart() async throws {
        try await withFixture { fixture, runtime, handle in
            let saved = try await install(fixture, handle)
            #expect(saved.rawContent.utf8.elementsEqual(Self.source.utf8))
            let first = try #require(saved.citationSnapshot)
            #expect(first.status == .available)
            #expect(first.data == Self.data())
            let catalog = ZoteroMarkdownFields(parsing: saved)
            #expect(catalog.fields.map(\.id) == ["cFirst", "cSecond"])
            #expect(catalog.fields.map(\.code) == Self.data().fields.map(\.code))
            let events = await handle.events.events()
            var iterator = events.makeAsyncIterator()
            _ = await iterator.next()
            let target = try await capturedSaveTarget(
                handle, fixture.analysisNoteID, revision: saved.fingerprint)
            let changed = try await handle.documents.save(
                target,
                changeSet: .citationSource(
                    saved.rawContent,
                    .init(expectedRevision: first.revision, data: Self.data(style: "new-style")))
            )
            .committedValue.document
            #expect(changed.sourceBytes == saved.sourceBytes)
            #expect(changed.citationSnapshot?.revision != first.revision)
            #expect(changed.citationSnapshot?.data?.documentData == "new-style")
            let publication = try #require(await iterator.next())
            guard case .sourceCommitted(let event) = publication else {
                Issue.record("Metadata-only citation save did not invalidate document sessions.")
                return
            }
            #expect(event.note.id == fixture.analysisNoteID)
            #expect(event.note.fingerprint == saved.fingerprint)
            let summary = try #require(try await handle.snapshot().document(id: fixture.analysisNoteID))
            #expect(
                try await handle.hydrate(summary).document.citationSnapshot == changed.citationSnapshot)
            await runtime.shutdown()

            let reopenedRuntime = makeRuntime(fixture)
            do {
                let reopened = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
                let document = try await reopened.documents.load(fixture.analysisNoteID)
                #expect(document.sourceBytes == saved.sourceBytes)
                #expect(document.citationSnapshot == changed.citationSnapshot)
                #expect(try await reopened.recoveryRecords().isEmpty)
                await reopenedRuntime.shutdown()
            } catch {
                await reopenedRuntime.shutdown()
                throw error
            }
        }
    }

    @Test("External source absence and restoration retain exact citation authority across restart")
    func externalSourceRestoration() async throws {
        try await withFixture { fixture, runtime, handle in
            let saved = try await install(fixture, handle)
            _ = try await handle.refresh()
            let citation = try #require(saved.citationSnapshot)
            let control = await handle.services.controlStore
            let identity = try #require(try await control.identityRecord(id: citation.noteID))
            #expect(identity.citationCompanionRequired == true)
            let companionURL = fixture.rootURL.appendingPathComponent(
                ".scholium/citations/v1/\(citation.noteID.uuidString.lowercased()).json")
            let companionBytes = try Data(contentsOf: companionURL)
            let sourceURL = fixture.analysesURL.appendingPathComponent(
                fixture.analysisNoteID.relativePath)
            let absentSourceURL = fixture.rootURL.appendingPathComponent("Absent source.md")

            // Exercise external absence/restoration with the same file outside every
            // vault. Finder owns restoration; this fixture does not invoke system Trash.
            try FileManager.default.moveItem(at: sourceURL, to: absentSourceURL)
            #expect(try await handle.refresh().document(id: fixture.analysisNoteID) == nil)
            #expect(try await control.identityRecord(id: citation.noteID) == identity)
            #expect(try Data(contentsOf: companionURL) == companionBytes)
            await runtime.shutdown()

            let absentRuntime = makeRuntime(fixture)
            do {
                let absent = try await absentRuntime.openWorkspace(id: fixture.assignment.id)
                #expect(try await absent.snapshot().document(id: fixture.analysisNoteID) == nil)
                let reopenedControl = await absent.services.controlStore
                #expect(try await reopenedControl.identityRecord(id: citation.noteID) == identity)
                #expect(try Data(contentsOf: companionURL) == companionBytes)
                #expect(try Data(contentsOf: absentSourceURL) == saved.sourceBytes)

                try FileManager.default.moveItem(at: absentSourceURL, to: sourceURL)
                let refreshed = try await absent.refresh()
                #expect(
                    refreshed.document(id: fixture.analysisNoteID)?.stableIdentity.resolvedID
                        == citation.noteID)
                let restored = try await absent.documents.load(fixture.analysisNoteID)
                #expect(restored.sourceBytes == saved.sourceBytes)
                #expect(restored.citationSnapshot == citation)
                let fields = ZoteroMarkdownFields(parsing: restored)
                #expect(fields.canMutate)
                #expect(fields.fields.map(\.id) == ["cFirst", "cSecond"])
                #expect(fields.fields.map(\.code) == Self.data().fields.map(\.code))
                #expect(try await reopenedControl.identityRecord(id: citation.noteID) == identity)
                #expect(try Data(contentsOf: companionURL) == companionBytes)
                #expect(try await absent.recoveryRecords().isEmpty)
                await absentRuntime.shutdown()
            } catch {
                await absentRuntime.shutdown()
                throw error
            }

            let restoredRuntime = makeRuntime(fixture)
            do {
                let reopened = try await restoredRuntime.openWorkspace(id: fixture.assignment.id)
                let restored = try await reopened.documents.load(fixture.analysisNoteID)
                #expect(restored.sourceBytes == saved.sourceBytes)
                #expect(restored.citationSnapshot == citation)
                #expect(
                    try await reopened.snapshot().document(id: fixture.analysisNoteID)?
                        .stableIdentity.resolvedID == citation.noteID)
                #expect(try Data(contentsOf: companionURL) == companionBytes)
                #expect(try await reopened.recoveryRecords().isEmpty)
                await restoredRuntime.shutdown()
            } catch {
                await restoredRuntime.shutdown()
                throw error
            }
        }
    }

    @Test("Ordinary source edits preserve companion authority and expose unresolved association")
    func sourceEditDoesNotRebindCompanion() async throws {
        try await withFixture { fixture, _, handle in
            let saved = try await install(fixture, handle)
            let before = try #require(saved.citationSnapshot)
            let target = try await capturedSaveTarget(
                handle, fixture.analysisNoteID, revision: saved.fingerprint)
            let edited = try await handle.documents.save(
                target, changeSet: .exactContent(saved.rawContent + "External prose.\r\n")
            )
            .committedValue.document
            #expect(edited.citationSnapshot?.status == .unresolved)
            #expect(edited.citationSnapshot?.revision == before.revision)
            #expect(edited.citationSnapshot?.sourceFingerprint == saved.fingerprint)
            #expect(edited.citationSnapshot?.data == before.data)
            #expect(!ZoteroMarkdownFields(parsing: edited).canMutate)
            let reload = try await handle.documents.load(fixture.analysisNoteID)
            #expect(reload.citationSnapshot == edited.citationSnapshot)
            #expect(reload.sourceBytes == Data((saved.rawContent + "External prose.\r\n").utf8))
        }
    }

    @Test("Duplicate remints occurrences and move retains Note-owned metadata")
    func duplicateAndMove() async throws {
        try await withFixture { fixture, _, handle in
            let saved = try await install(fixture, handle)
            let target = try await capturedSaveTarget(
                handle, fixture.analysisNoteID, revision: saved.fingerprint)
            let duplicate = try await handle.documents.duplicate(target, to: "Agency copy.md")
                .committedValue
            let duplicateSnapshot = try #require(duplicate.citationSnapshot)
            #expect(duplicateSnapshot.status == .available)
            #expect(duplicateSnapshot.noteID != target.stableNoteID)
            #expect(
                duplicateSnapshot.data?.fields.map(\.code)
                    == saved.citationSnapshot?.data?.fields.map(\.code))
            let duplicateIDs = duplicateSnapshot.data?.fields.map(\.id) ?? []
            #expect(Set(duplicateIDs).count == 2)
            #expect(Set(duplicateIDs).isDisjoint(with: ["cFirst", "cSecond"]))
            var expectedCopy = Self.source
            for (old, new) in zip(["cFirst", "cSecond"], duplicateIDs) {
                expectedCopy = expectedCopy.replacingOccurrences(of: "cite:\(old)", with: "cite:\(new)")
            }
            #expect(duplicate.sourceBytes == Data(expectedCopy.utf8))
            #expect(
                try await handle.documents.load(fixture.analysisNoteID).citationSnapshot
                    == saved.citationSnapshot)

            let duplicateTarget = NoteMutationTarget(
                documentID: .init(
                    vaultID: fixture.analysisNoteID.vaultID, relativePath: duplicate.relativePath),
                stableNoteID: duplicateSnapshot.noteID, revision: duplicate.fingerprint)
            do {
                _ = try await handle.prepareNoteRestructure(
                    .init(
                        source: target, selectionUTF8: nil, destination: .existing(duplicateTarget),
                        operation: .merge))
                Issue.record("Source-only reorganization transferred citation authority.")
            } catch NoteRestructureError.unavailable(let message) {
                #expect(message.contains("citation companions"))
            }

            _ = try await handle.documents.move(target, to: "Moved/Agency.md")
            let moved = try await handle.documents.load(
                .init(vaultID: target.documentID.vaultID, relativePath: "Moved/Agency.md"))
            #expect(moved.sourceBytes == saved.sourceBytes)
            #expect(moved.citationSnapshot == saved.citationSnapshot)
            #expect(try await handle.recoveryRecords().isEmpty)
        }
    }

    @Test("A Markdown-only compact import is readable without borrowing another Note's metadata")
    func compactImportIsUnresolved() async throws {
        try await withFixture { fixture, _, handle in
            let original = try await install(fixture, handle)
            let imported = try await handle.documents.importMarkdownSource(
                original.rawContent,
                at: .init(vaultID: fixture.analysisNoteID.vaultID, relativePath: "Imported.md")
            )
            .committedValue
            #expect(imported.sourceBytes == original.sourceBytes)
            #expect(imported.citationSnapshot?.status == .absent)
            #expect(imported.citationSnapshot?.noteID != original.citationSnapshot?.noteID)
            #expect(!ZoteroMarkdownFields(parsing: imported).canMutate)
            #expect(imported.citationSnapshot?.data == nil)
        }
    }

    @Test("Incoming link rewrites retain companion bytes without declaring the new source current")
    func linkRewriteInvalidatesAssociation() async throws {
        try await withFixture { fixture, _, handle in
            let linkedID = VaultQualifiedNoteID(
                vaultID: fixture.analysisNoteID.vaultID, relativePath: "Target.md")
            let linked = try await handle.documents.importMarkdownSource("# Target\n", at: linkedID)
                .committedValue
            let original = try await handle.documents.load(fixture.analysisNoteID)
            let target = try await capturedSaveTarget(
                handle, fixture.analysisNoteID, revision: original.fingerprint)
            let saved = try await handle.documents.save(
                target,
                changeSet: .citationSource(
                    Self.source + "[[Target]]\r\n", .init(expectedRevision: nil, data: Self.data()))
            )
            .committedValue.document
            _ = try await handle.documents.move(
                linkedID, to: "Renamed.md", expectedRevision: linked.fingerprint)
            let rewritten = try await handle.documents.load(fixture.analysisNoteID)
            #expect(rewritten.sourceBytes == Data((Self.source + "[[Renamed]]\r\n").utf8))
            #expect(rewritten.citationSnapshot?.status == .unresolved)
            #expect(rewritten.citationSnapshot?.revision == saved.citationSnapshot?.revision)
            #expect(rewritten.citationSnapshot?.sourceFingerprint == saved.fingerprint)
        }
    }

    @Test("Duplicate compact IDs and stale companion saves preserve both committed preimages")
    func invalidAndStaleSave() async throws {
        try await withFixture { fixture, _, handle in
            let saved = try await install(fixture, handle)
            let before = try #require(saved.citationSnapshot)
            let target = try await capturedSaveTarget(
                handle, fixture.analysisNoteID, revision: saved.fingerprint)
            do {
                _ = try await handle.documents.save(
                    target,
                    changeSet: .citationSource(
                        saved.rawContent + "[(Smith, 2024)](cite:cFirst)\r\n",
                        .init(expectedRevision: before.revision, data: Self.data())))
                Issue.record("Duplicate citation identity was persisted.")
            } catch ZoteroCitationError.invalidSource {}
            #expect(try await handle.documents.load(target.documentID).sourceBytes == saved.sourceBytes)
            #expect(try await handle.documents.load(target.documentID).citationSnapshot == before)

            _ = try await handle.documents.save(
                target,
                changeSet: .citationSource(
                    saved.rawContent,
                    .init(expectedRevision: before.revision, data: Self.data(style: "changed"))))
            let current = try await handle.documents.load(target.documentID)
            do {
                _ = try await handle.documents.save(
                    target,
                    changeSet: .citationSource(
                        saved.rawContent,
                        .init(expectedRevision: before.revision, data: Self.data(style: "stale"))))
                Issue.record("A stale citation companion overwrote its newer revision.")
            } catch ZoteroCitationSaveError.companionConflict {}
            #expect(
                try await handle.documents.load(target.documentID).citationSnapshot
                    == current.citationSnapshot)
            #expect(try await handle.recoveryRecords().isEmpty)
        }
    }

    @Test("Source-only Agent Undo cannot authorize independently retained citation state")
    func sourceOnlyAgentUndoRefused() async throws {
        try await withFixture { fixture, _, handle in
            let saved = try await install(fixture, handle)
            let snapshot = try #require(saved.citationSnapshot)
            let changeID = UUID()
            do {
                try await handle.requireSourceOnlyAgentUndo(
                    noteID: snapshot.noteID, vaultID: snapshot.vaultID, changeID: changeID)
                Issue.record("A source-only receipt authorized companion-aware Undo.")
            } catch AgentChangeError.undoUnavailable(let rejected) {
                #expect(rejected == changeID)
            }
            #expect(try await handle.documents.load(fixture.analysisNoteID).citationSnapshot == snapshot)
        }
    }

    @Test("Resolve reconciles a paired save and startup retains externally conflicted evidence")
    func pairedRecoveryRouting() async throws {
        try await withFixture { fixture, _, handle in
            let original = try await handle.documents.load(fixture.analysisNoteID)
            let target = try await capturedSaveTarget(
                handle, fixture.analysisNoteID, revision: original.fingerprint)
            let services = await handle.services
            let interrupted = ZoteroCitationSaveCoordinator(
                triptychID: handle.id, repositories: services.repositories,
                controlStore: services.controlStore, recoveryStore: services.transactionRecoveryStore,
                afterSource: { throw InterruptedForTest.stop })
            do {
                _ = try await interrupted.save(
                    target: target, source: Self.source,
                    edit: .init(expectedRevision: nil, data: Self.data()))
                Issue.record("The injected paired save did not stop.")
            } catch ZoteroCitationSaveError.recoveryRequired {}
            let first = try #require(
                try await services.transactionRecoveryStore.pendingCitationSaves().first)
            #expect(try await handle.research.recoveryRecords().contains(where: { $0.id == first.id }))
            #expect(
                try await handle.documents.load(target.documentID).sourceBytes == Data(Self.source.utf8))
            try await handle.research.resolveRecoveryRecord(first.id)
            let recovered = try await handle.documents.load(target.documentID)
            #expect(recovered.citationSnapshot?.status == .available)
            #expect(recovered.citationSnapshot?.data == Self.data())
            #expect(try await services.transactionRecoveryStore.pendingCitationSaves().isEmpty)

            let secondTarget = NoteMutationTarget(
                documentID: target.documentID, stableNoteID: target.stableNoteID,
                revision: recovered.fingerprint)
            do {
                _ = try await interrupted.save(
                    target: secondTarget, source: recovered.rawContent + "Candidate.\r\n",
                    edit: .init(
                        expectedRevision: recovered.citationSnapshot?.revision,
                        data: Self.data(style: "candidate")))
                Issue.record("The second injected paired save did not stop.")
            } catch ZoteroCitationSaveError.recoveryRequired {}
            let pending = try #require(
                try await services.transactionRecoveryStore.pendingCitationSaves().first)
            let external = Data((Self.source + "Newer external writing.\r\n").utf8)
            let sourceURL = fixture.analysesURL.appendingPathComponent(
                fixture.analysisNoteID.relativePath)
            try external.write(to: sourceURL, options: .atomic)
            let issues = try await handle.documents.recoverInterruptedTransactions()
            #expect(!issues.isEmpty)
            #expect(try Data(contentsOf: sourceURL) == external)
            #expect(
                try await services.transactionRecoveryStore.pendingCitationSaves().map(\.id) == [pending.id]
            )
            #expect(
                try await handle.documents.load(target.documentID).citationSnapshot?.revision
                    == recovered.citationSnapshot?.revision)
        }
    }

    private enum InterruptedForTest: Error { case stop }

    @Test(
        "Only explicit Resolve accounts for retained citation evidence without overwriting newer source",
        arguments: [false, true])
    func explicitRetainedEvidenceCompletion(newerSource: Bool) async throws {
        try await withFixture { fixture, _, handle in
            let original = try await install(fixture, handle)
            let target = try await capturedSaveTarget(
                handle, fixture.analysisNoteID, revision: original.fingerprint)
            let services = await handle.services
            let candidateSource = Self.source + "Accepted candidate.\r\n"
            let interrupted = ZoteroCitationSaveCoordinator(
                triptychID: handle.id, repositories: services.repositories,
                controlStore: services.controlStore, recoveryStore: services.transactionRecoveryStore,
                afterSource: nil, afterCompanion: { throw InterruptedForTest.stop })
            await #expect(throws: ZoteroCitationSaveError.self) {
                try await interrupted.save(
                    target: target, source: candidateSource,
                    edit: .init(
                        expectedRevision: original.citationSnapshot?.revision,
                        data: Self.data(style: "candidate")))
            }
            let recovery = try #require(
                try await services.transactionRecoveryStore.pendingCitationSaves().first)
            let displaced = try TriptychControlStore.citationCompanionEncoding(
                .init(
                    noteID: target.stableNoteID, vaultID: target.documentID.vaultID,
                    sourceFingerprint: original.fingerprint, data: Self.data(style: "displaced-external")))
            try await services.transactionRecoveryStore.retainDisplacedCitationCompanion(
                recovery, bytes: displaced)
            let sourceURL = fixture.analysesURL.appendingPathComponent(
                fixture.analysisNoteID.relativePath)
            if newerSource {
                try Data((candidateSource + "Newer external work.\r\n").utf8).write(
                    to: sourceURL, options: .atomic)
            }
            let currentSource = try Data(contentsOf: sourceURL)
            let currentCompanion = try await services.controlStore.citationCompanionBytes(
                noteID: target.stableNoteID)

            let issues = try await handle.documents.recoverInterruptedTransactions()
            #expect(!issues.isEmpty)
            #expect(
                try await services.transactionRecoveryStore.pendingCitationSaves().map(\.id) == [
                    recovery.id
                ])
            #expect(try await services.transactionRecoveryStore.retainedCitationSaves().isEmpty)
            if newerSource {
                await #expect(throws: ZoteroCitationSaveError.self) {
                    try await handle.research.resolveRecoveryRecord(recovery.id)
                }
                #expect(
                    try await services.transactionRecoveryStore.pendingCitationSaves().map(\.id) == [
                        recovery.id
                    ])
                #expect(try await services.transactionRecoveryStore.retainedCitationSaves().isEmpty)
            } else {
                try await handle.research.resolveRecoveryRecord(recovery.id)
                #expect(try await handle.research.recoveryRecords().isEmpty)
                #expect(try await services.transactionRecoveryStore.pendingCitationSaves().isEmpty)
                #expect(
                    try await services.transactionRecoveryStore.retainedCitationSaves().map(\.id) == [
                        recovery.id
                    ])
            }
            #expect(try Data(contentsOf: sourceURL) == currentSource)
            #expect(
                try await services.controlStore.citationCompanionBytes(noteID: target.stableNoteID)
                    == currentCompanion)
            #expect(
                try await services.transactionRecoveryStore.citationSaveEvidence(recovery)
                    .companionDisplaced == displaced)
        }
    }

    @Test("Companion-only invalidation waits for the source gate and preserves refresh failure state")
    func companionOnlyObservation() async throws {
        try await withFixture { fixture, _, handle in
            let saved = try await install(fixture, handle)
            let snapshot = try #require(saved.citationSnapshot)
            let control = fixture.rootURL.appendingPathComponent(
                ".scholium/citations/v1/\(snapshot.noteID.uuidString.lowercased()).json")
            let bytes = try Data(contentsOf: control)
            let changed = try #require(String(data: bytes, encoding: .utf8))
                .replacingOccurrences(of: "original-style", with: "synchronized-style")
            try Data(changed.utf8).write(to: control, options: .atomic)
            let workspace = try await handle.snapshot()
            let failed = WorkspaceDerivedRefreshStatus.failed(
                .init(
                    reason: "Retained failure", affectedVaultIDs: [fixture.analysisNoteID.vaultID],
                    lastKnownGood: .init(snapshot: workspace)))
            await handle.events.publishDerivedStateChanged(snapshot: workspace, status: failed)
            let events = await handle.events.events()
            var iterator = events.makeAsyncIterator()
            _ = await iterator.next()
            let beforeGeneration = await handle.events.publishedGeneration
            let lease = try await handle.acquireWorkspaceSourceOperation(.sourceMutation)
            await handle.receiveCitationControlEvent(.reconciliationRequired(sequence: 1))
            await handle.receiveCitationControlEvent(.reconciliationRequired(sequence: 2))
            for _ in 0..<50 { await Task.yield() }
            #expect(await handle.events.publishedGeneration == beforeGeneration)
            await handle.releaseWorkspaceSourceOperation(lease)
            await handle.citationControlInvalidationTask?.value
            let event = try #require(await iterator.next())
            guard case .citationAuthorityInvalidated(let invalidation) = event else {
                Issue.record("A portable citation event did not invalidate essential authority.")
                return
            }
            #expect(invalidation.affectedNoteIDs == nil)
            #expect(invalidation.derivedRefreshStatus == failed)
            let observed = try await handle.documents.load(fixture.analysisNoteID)
            #expect(observed.sourceBytes == saved.sourceBytes)
            #expect(observed.citationSnapshot?.revision != snapshot.revision)
            #expect(observed.citationSnapshot?.data?.documentData == "synchronized-style")
            try FileManager.default.removeItem(at: control)
            let missing = try await handle.documents.load(fixture.analysisNoteID)
            #expect(missing.sourceBytes == saved.sourceBytes)
            #expect(missing.citationSnapshot?.status == .unresolved)
            var unsupported = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            unsupported["schemaVersion"] = 99
            let unsupportedBytes = try JSONSerialization.data(
                withJSONObject: unsupported, options: [.sortedKeys])
            try unsupportedBytes.write(to: control, options: .atomic)
            let unavailable = try await handle.documents.load(fixture.analysisNoteID)
            #expect(unavailable.sourceBytes == saved.sourceBytes)
            #expect(unavailable.citationSnapshot?.status == .unsupported)
            #expect(try Data(contentsOf: control) == unsupportedBytes)
        }
    }

    @Test("Opening inventory preserves a duplicate's journaled identity until creation recovery")
    func creationReservationSurvivesRestart() async throws {
        try await withFixture { fixture, runtime, handle in
            let services = await handle.services
            let reservedID = UUID()
            let path = "Interrupted duplicate.md"
            let sourceBytes = Data(Self.source.utf8)
            let companion = ZoteroCitationCompanion(
                noteID: reservedID, vaultID: fixture.analysisNoteID.vaultID,
                sourceFingerprint: .init(data: sourceBytes), data: Self.data())
            _ = try await services.transactionRecoveryStore.prepareCitationSave(
                noteID: reservedID, vaultID: fixture.analysisNoteID.vaultID, relativePath: path,
                sourceBefore: nil, sourceAfter: sourceBytes, companionBefore: nil,
                companionAfter: TriptychControlStore.citationCompanionEncoding(companion),
                companionRequiredBefore: false)
            let repository = try await handle.repository(vaultID: fixture.analysisNoteID.vaultID)
            _ = try await repository.create(relativePath: path, content: Self.source)
            await runtime.shutdown()

            let reopenedRuntime = makeRuntime(fixture)
            do {
                let reopened = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
                let id = VaultQualifiedNoteID(vaultID: fixture.analysisNoteID.vaultID, relativePath: path)
                #expect(try await reopened.snapshot().document(id: id)?.stableIdentity == .unresolved)
                let controlStore = await reopened.services.controlStore
                #expect(
                    try await controlStore.identityRecord(vaultID: id.vaultID, relativePath: path) == nil)
                #expect(try await reopened.documents.recoverInterruptedTransactions().isEmpty)
                await reopened.sourceCommitRefreshTask?.value
                let recovered = try await reopened.documents.load(id)
                #expect(recovered.citationSnapshot?.noteID == reservedID)
                #expect(recovered.citationSnapshot?.status == .available)
                #expect(
                    try await reopened.snapshot().document(id: id)?.stableIdentity.resolvedID == reservedID)
                #expect(try await reopened.research.recoveryRecords().isEmpty)
                await reopenedRuntime.shutdown()
            } catch {
                await reopenedRuntime.shutdown()
                throw error
            }
        }
    }

    private func install(_ fixture: ApplicationFixture, _ handle: WorkspaceHandle) async throws
        -> NoteDocument
    {
        let original = try await handle.documents.load(fixture.analysisNoteID)
        #expect(original.citationSnapshot?.status == .absent)
        let target = try await capturedSaveTarget(
            handle, fixture.analysisNoteID, revision: original.fingerprint)
        let saved = try await handle.documents.save(
            target,
            changeSet: .citationSource(Self.source, .init(expectedRevision: nil, data: Self.data())))
        return saved.committedValue.document
    }

    private func makeRuntime(_ fixture: ApplicationFixture) -> WorkspaceRuntime {
        WorkspaceRuntime(
            configuration: .snapshot(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL, assignments: [fixture.assignment])))
    }

    private func withFixture(
        _ body: (ApplicationFixture, WorkspaceRuntime, WorkspaceHandle) async throws -> Void
    ) async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let rootURL = repositoryRoot.appendingPathComponent(
            ".build/CitationCompanionOperations-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fixture = try await ApplicationFixture.make(rootURL: rootURL)
        let runtime = makeRuntime(fixture)
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            try await body(fixture, runtime, handle)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }
}
