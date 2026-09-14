import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Exact-source note reorganization")
struct NoteRestructureTests {
    @Test("Moving a paragraph preserves its identity and rewrites incoming references without changing adjacent bytes")
    func movePreservesIdentity() throws {
        let vault = UUID()
        let source = note(vault, "Source.md", "\u{FEFF}---\r\nunknown: 'keep' # comment\r\n---\r\nClaim 中文. ^claim\r\n\r\nKeep this.\r\n")
        let target = note(vault, "Target.md", "Target.\r\n")
        let incoming = note(vault, "Incoming.md", "[[Source#^claim|Claim]]{{Authored context.}}\r\n")
        let docs = Dictionary(uniqueKeysWithValues: [source, target, incoming])
        let span = try #require(ParagraphAnchorPlanner.anchors(in: source.1).first).paragraphSpan
        let plan = try prepare(source: source, target: target, range: span.utf8Range, operation: .move, documents: docs)
        #expect(plan.movedAnchorIDs == ["claim"])
        #expect(plan.edits.first(where: { $0.note == target.0 })?.after == "Target.\r\n\r\nClaim 中文. ^claim")
        #expect(plan.edits.first(where: { $0.note == incoming.0 })?.after == "[[Target#^claim|Claim]]{{Authored context.}}\r\n")
        #expect(
            plan.edits.first(where: { $0.note == source.0 })?.after
                == "\u{FEFF}---\r\nunknown: 'keep' # comment\r\n---\r\n[[Target#^claim]]\r\n\r\nKeep this.\r\n")
    }

    @Test("Copy gets a new deterministic identity while outside links continue to reference the original")
    func copySeparatesIdentity() throws {
        let vault = UUID()
        let source = note(vault, "Source.md", "Claim [[#^claim|itself]]. ^claim\n")
        let target = note(vault, "Target.md", "")
        let incoming = note(vault, "Incoming.md", "[[Source#^claim]]\n")
        let docs = Dictionary(uniqueKeysWithValues: [source, target, incoming])
        let range = try #require(ParagraphAnchorPlanner.anchors(in: source.1).first).paragraphSpan.utf8Range
        let request = NoteRestructureRequest(source: mutation(source), selectionUTF8: range, destination: .existing(mutation(target)), operation: .copy)
        let plan = try NoteRestructurePlanner.prepare(request, documents: docs, graph: graph(docs))
        let again = try NoteRestructurePlanner.prepare(request, documents: docs, graph: graph(docs))
        #expect(plan == again)
        #expect(plan.edits.count == 1)
        let id = try #require(plan.movedAnchorIDs.first)
        #expect(id != "claim")
        #expect(plan.edits.first?.after == "Claim [[Target#^\(id)|itself]]. ^\(id)")
    }

    @Test("Move refuses duplicate IDs, partial paragraphs, and undefined footnotes")
    func refusesUnsafeSelections() throws {
        let vault = UUID()
        let source = note(vault, "Source.md", "Claim. ^same\n")
        let target = note(vault, "Target.md", "Other. ^same\n")
        let docs = Dictionary(uniqueKeysWithValues: [source, target])
        #expect(throws: NoteRestructureError.self) {
            try prepare(source: source, target: target, range: source.1.bodyByteRange, operation: .move, documents: docs)
        }
        let empty = note(vault, "Target.md", "")
        #expect(throws: NoteRestructureError.self) {
            try prepare(source: source, target: empty, range: 1..<5, operation: .move, documents: Dictionary(uniqueKeysWithValues: [source, empty]))
        }
        let footnote = note(vault, "Source.md", "Claim[^missing].\n")
        let span = try #require(MarkdownSemanticDocument(parsing: footnote.1).blocks.first).span
        #expect(throws: NoteRestructureError.self) {
            try prepare(
                source: footnote, target: empty, range: span.utf8Range, operation: .move, documents: Dictionary(uniqueKeysWithValues: [footnote, empty]))
        }
    }

    @Test("A stale destination fails before the source changes")
    func staleDestination() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        _ = try await fixture.repository.save(
            relativePath: "Target.md", changeSet: .exactContent("External.\n"), expectedRevision: plan.edits.first!.expectedRevision!)
        await #expect(throws: VaultRepositoryError.self) { try await fixture.coordinator().commit(plan) }
        #expect(try await fixture.repository.load(relativePath: "Source.md").rawContent == "Claim. ^claim\n")
        #expect(try await fixture.recovery.pending().isEmpty)
    }

    @Test("A same-spelling heading reference does not follow a moved paragraph identifier")
    func headingIsNotBlockIdentity() throws {
        let vault = UUID()
        let source = note(vault, "Source.md", "# claim\n\nBody. ^claim\n")
        let target = note(vault, "Target.md", "")
        let incoming = note(vault, "Incoming.md", "[[Source#claim]]\n")
        let docs = Dictionary(uniqueKeysWithValues: [source, target, incoming])
        let range = try #require(ParagraphAnchorPlanner.anchors(in: source.1).first).paragraphSpan.utf8Range
        let plan = try prepare(source: source, target: target, range: range, operation: .move, documents: docs)
        #expect(!plan.edits.contains(where: { $0.note == incoming.0 }))
    }

    @Test("Merge rejects new ambiguity for references already pointing to the destination")
    func mergeProtectsDestinationIncomingReferences() throws {
        let vault = UUID()
        let source = note(vault, "Source.md", "# Claims\n\nOne.\n")
        let target = note(vault, "Target.md", "# Claims\n\nTwo.\n")
        let incoming = note(vault, "Incoming.md", "[[Target#Claims]]\n")
        let docs = Dictionary(uniqueKeysWithValues: [source, target, incoming])
        #expect(throws: NoteRestructureError.self) {
            try prepare(source: source, target: target, range: source.1.bodyByteRange, operation: .merge, documents: docs)
        }
    }

    @Test("A shortcut link becomes self-contained while its original definition stays exact")
    func shortcutReferenceDependency() throws {
        let vault = UUID()
        let source = note(vault, "Source.md", "[site]\n\n[site]: https://example.com\n")
        let target = note(vault, "Target.md", "")
        let docs = Dictionary(uniqueKeysWithValues: [source, target])
        let range = try #require(MarkdownSemanticDocument(parsing: source.1).blocks.first).span.utf8Range
        let plan = try prepare(source: source, target: target, range: range, operation: .move, documents: docs)
        #expect(plan.edits.first(where: { $0.note == target.0 })?.after?.contains("[site](https://example.com)") == true)
        #expect(plan.edits.first(where: { $0.note == source.0 })?.after?.contains("[site]: https://example.com") == true)
    }

    @Test("A complete merge plans original-file Trash and keeps heading and paragraph references live", arguments: ["\u{FEFF}", "\u{FEFF}---\n\n---\n"])
    func mergeTransfersReferences(prefix: String) throws {
        let vault = UUID()
        let source = note(vault, "Source.md", prefix + "# Argument\n\nClaim[^1]. ^claim\n\n[^1]: Authority.\n")
        let target = note(vault, "Target.md", "# Target\n")
        let incoming = note(vault, "Incoming.md", "[[Source]] [[Source#Argument]] [[Source#^claim]]\n")
        let docs = Dictionary(uniqueKeysWithValues: [source, target, incoming])
        let plan = try prepare(source: source, target: target, range: source.1.bodyByteRange, operation: .merge, documents: docs)
        #expect(plan.edits.last?.note == source.0)
        #expect(plan.edits.last?.after == nil)
        #expect(plan.edits.first?.after == "# Target\n\n# Argument\n\nClaim[^1]. ^claim\n\n[^1]: Authority.\n")
        #expect(plan.edits.first(where: { $0.note == incoming.0 })?.after == "[[Target]] [[Target#Argument]] [[Target#^claim]]\n")
    }

    @Test("Interrupted extraction removes only the exact newly created file and keeps original source")
    func newNoteRollback() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let base = try await fixture.plan()
        let source = try await fixture.repository.load(relativePath: "Source.md")
        let id = base.request.source.documentID
        let target = try await fixture.repository.load(relativePath: "Target.md")
        let docs = [id: source, VaultQualifiedNoteID(vaultID: fixture.vault, relativePath: target.relativePath): target]
        let request = NoteRestructureRequest(
            source: base.request.source, selectionUTF8: base.request.selectionUTF8, destination: .newNote(relativePath: "Extracted.md"), operation: .move)
        let plan = try NoteRestructurePlanner.prepare(request, documents: docs, graph: graph(docs))
        let coordinator = NoteRestructureCoordinator(
            triptychID: fixture.triptych, repositories: [fixture.vault: fixture.repository], recoveryStore: fixture.recovery,
            afterWrite: { _ in
                #expect(try await fixture.recovery.pending().first?.restructureEdits == plan.edits)
                throw Injected.failure
            })
        await #expect(throws: TriptychTransactionError.self) { try await coordinator.commit(plan) }
        #expect(try await fixture.repository.load(relativePath: "Source.md").rawContent == source.rawContent)
        await #expect(throws: VaultRepositoryError.self) { try await fixture.repository.load(relativePath: "Extracted.md") }
        #expect(try await fixture.recovery.pending().isEmpty)
    }

    @Test("An injected failure restores every written file and removes the durable plan")
    func rollbackAfterFirstWrite() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        let coordinator = NoteRestructureCoordinator(
            triptychID: fixture.triptych, repositories: [fixture.vault: fixture.repository], recoveryStore: fixture.recovery,
            afterWrite: { _ in throw Injected.failure })
        await #expect(throws: TriptychTransactionError.self) { try await coordinator.commit(plan) }
        #expect(try await fixture.repository.load(relativePath: "Source.md").rawContent == "Claim. ^claim\n")
        #expect(try await fixture.repository.load(relativePath: "Target.md").rawContent == "Target.\n")
        #expect(try await fixture.recovery.pending().isEmpty)
    }

    @Test("An external edit during failure is retained together with exact original recovery bytes")
    func preservesConcurrentExternalEdit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        let coordinator = NoteRestructureCoordinator(
            triptychID: fixture.triptych, repositories: [fixture.vault: fixture.repository], recoveryStore: fixture.recovery,
            afterWrite: { _ in
                let current = try await fixture.repository.load(relativePath: "Target.md")
                _ = try await fixture.repository.save(
                    relativePath: "Target.md", changeSet: .exactContent("External revision.\n"), expectedRevision: current.fingerprint)
                throw Injected.failure
            })
        await #expect(throws: TriptychTransactionError.self) { try await coordinator.commit(plan) }
        #expect(try await fixture.repository.load(relativePath: "Target.md").rawContent == "External revision.\n")
        let record = try #require(try await fixture.recovery.pending().first)
        #expect(record.restructureEdits == plan.edits)
        let reopened = try TriptychMutationRecoveryStore(storageURL: fixture.recovery.storageURL)
        #expect(try await reopened.pending().first?.restructureEdits == plan.edits)
    }

    private enum Injected: Error { case failure }

    @Test("A new incoming reference during transfer stops source removal and survives rollback")
    func externalIncomingReferenceStopsTransfer() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let base = try await fixture.plan()
        let incoming = try await fixture.repository.create(relativePath: "Incoming.md", content: "Research.\n")
        let source = try await fixture.repository.load(relativePath: "Source.md")
        let target = try await fixture.repository.load(relativePath: "Target.md")
        let docs = Dictionary(
            uniqueKeysWithValues: [source, target, incoming].map { (VaultQualifiedNoteID(vaultID: fixture.vault, relativePath: $0.relativePath), $0) })
        let plan = try NoteRestructurePlanner.prepare(base.request, documents: docs, graph: graph(docs))
        let coordinator = NoteRestructureCoordinator(
            triptychID: fixture.triptych, repositories: [fixture.vault: fixture.repository], recoveryStore: fixture.recovery,
            afterWrite: { _ in
                _ = try await fixture.repository.save(
                    relativePath: "Incoming.md", changeSet: .exactContent("[[Source#^claim]]\n"), expectedRevision: incoming.fingerprint)
            })
        await #expect(throws: TriptychTransactionError.self) { try await coordinator.commit(plan) }
        #expect(try await fixture.repository.load(relativePath: "Incoming.md").rawContent == "[[Source#^claim]]\n")
        #expect(try await fixture.repository.load(relativePath: "Source.md").rawContent == source.rawContent)
        #expect(try await fixture.repository.load(relativePath: "Target.md").rawContent == target.rawContent)
    }

    @Test("External deletion after rollback preflight retains destination content and the recovery record")
    func rollbackRechecksEveryFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try await fixture.plan()
        let coordinator = NoteRestructureCoordinator(
            triptychID: fixture.triptych, repositories: [fixture.vault: fixture.repository], recoveryStore: fixture.recovery,
            afterWrite: { _ in throw Injected.failure },
            beforeRollbackWrite: { index in
                if index == 0 {
                    try await fixture.repository.removeCreatedFileForRollback(relativePath: "Source.md", createdRevision: plan.request.source.revision)
                }
            })
        await #expect(throws: TriptychTransactionError.self) { try await coordinator.commit(plan) }
        #expect(try await fixture.repository.load(relativePath: "Target.md").rawContent.contains("Claim. ^claim"))
        #expect(try await fixture.recovery.pending().first?.restructureEdits == plan.edits)
    }

    @Test("An uncertain new identity retains committed extraction source and its recovery evidence")
    func identityUncertaintyDoesNotDeleteSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let base = try await fixture.plan()
        let source = try await fixture.repository.load(relativePath: "Source.md")
        let target = try await fixture.repository.load(relativePath: "Target.md")
        let docs = Dictionary(uniqueKeysWithValues: [source, target].map { (VaultQualifiedNoteID(vaultID: fixture.vault, relativePath: $0.relativePath), $0) })
        let request = NoteRestructureRequest(
            source: base.request.source, selectionUTF8: base.request.selectionUTF8, destination: .newNote(relativePath: "Extracted.md"), operation: .move)
        let plan = try NoteRestructurePlanner.prepare(request, documents: docs, graph: graph(docs))
        await #expect(throws: TriptychTransactionError.self) {
            try await fixture.coordinator().commit(plan, finishCreation: { _ in throw Injected.failure })
        }
        #expect(try await fixture.repository.load(relativePath: "Extracted.md").rawContent == "Claim. ^claim")
        #expect(try await fixture.repository.load(relativePath: "Source.md").rawContent == "[[Extracted#^claim]]\n")
        #expect(try await fixture.recovery.pending().first?.restructureEdits == plan.edits)
    }

    private func note(_ vault: UUID, _ path: String, _ source: String) -> (VaultQualifiedNoteID, NoteDocument) {
        (VaultQualifiedNoteID(vaultID: vault, relativePath: path), NoteDocument(relativePath: path, rawContent: source))
    }
    private func mutation(_ note: (VaultQualifiedNoteID, NoteDocument)) -> NoteMutationTarget {
        NoteMutationTarget(documentID: note.0, stableNoteID: UUID(), revision: note.1.fingerprint)
    }
    private func graph(_ documents: [VaultQualifiedNoteID: NoteDocument]) -> GraphSnapshot {
        LinkGraphBuilder.build(
            generation: 1, catalog: documents.map { LinkCatalogNote(vaultID: $0.key.vaultID, document: $0.value) },
            documents: documents.mapValues(MarkdownSemanticDocument.init(parsing:)), resolutionScope: .workspace)
    }
    private func prepare(
        source: (VaultQualifiedNoteID, NoteDocument), target: (VaultQualifiedNoteID, NoteDocument), range: Range<Int>, operation: NoteRestructureOperation,
        documents: [VaultQualifiedNoteID: NoteDocument]
    ) throws -> NoteRestructurePreview {
        try NoteRestructurePlanner.prepare(
            NoteRestructureRequest(source: mutation(source), selectionUTF8: range, destination: .existing(mutation(target)), operation: operation),
            documents: documents, graph: graph(documents))
    }

    private struct Fixture: Sendable {
        let root: URL
        let vault = UUID()
        let triptych = UUID()
        let repository: VaultRepository
        let recovery: TriptychMutationRecoveryStore
        init() throws {
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
                ".build/restructure-fixtures/\(UUID())", isDirectory: true)
            let vaultURL = root.appendingPathComponent("vault", isDirectory: true)
            try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
            repository = try VaultRepository(
                vaultURL: vaultURL, identity: VaultIdentity(id: vault, canonicalPath: vaultURL.path, bookmarkData: nil),
                applicationSupportURL: root.appendingPathComponent("support"), vaultRole: .topicKnowledge)
            recovery = try TriptychMutationRecoveryStore(
                storageURL: root.appendingPathComponent("Triptychs/\(triptych.uuidString)/transactions", isDirectory: true))
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
        func coordinator() -> NoteRestructureCoordinator {
            NoteRestructureCoordinator(triptychID: triptych, repositories: [vault: repository], recoveryStore: recovery)
        }
        func plan() async throws -> NoteRestructurePreview {
            let source = try await repository.create(relativePath: "Source.md", content: "Claim. ^claim\n")
            let target = try await repository.create(relativePath: "Target.md", content: "Target.\n")
            let sourceID = VaultQualifiedNoteID(vaultID: vault, relativePath: source.relativePath)
            let targetID = VaultQualifiedNoteID(vaultID: vault, relativePath: target.relativePath)
            let docs = [sourceID: source, targetID: target]
            let graph = LinkGraphBuilder.build(
                generation: 1, catalog: docs.map { LinkCatalogNote(vaultID: vault, document: $0.value) },
                documents: docs.mapValues(MarkdownSemanticDocument.init(parsing:)), resolutionScope: .workspace)
            return try NoteRestructurePlanner.prepare(
                NoteRestructureRequest(
                    source: NoteMutationTarget(documentID: sourceID, stableNoteID: UUID(), revision: source.fingerprint),
                    selectionUTF8: ParagraphAnchorPlanner.anchors(in: source).first!.paragraphSpan.utf8Range,
                    destination: .existing(NoteMutationTarget(documentID: targetID, stableNoteID: UUID(), revision: target.fingerprint)), operation: .move),
                documents: docs, graph: graph)
        }
    }
}
