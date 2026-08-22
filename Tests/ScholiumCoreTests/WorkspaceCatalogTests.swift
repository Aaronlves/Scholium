import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Triptych workspace catalog")
struct WorkspaceCatalogTests {
    @Test("Workspace catalog assembly reuses only fingerprint-bound semantics")
    func catalogReusesFingerprintBoundSemantics() throws {
        let topics = vault("Topics", .topicKnowledge)
        let document = note("Topic.md", "# Authoritative Title\n\nBody")
        let projectedDocument = note(
            "Projected.md",
            "# Cached Semantic Title\n\nBody"
        )
        let projected = MarkdownSemanticDocument(parsing: projectedDocument)
        let fingerprintBound = MarkdownSemanticDocument(
            fingerprint: document.fingerprint,
            blocks: projected.blocks,
            inlines: projected.inlines,
            headings: projected.headings,
            callouts: projected.callouts,
            footnoteDefinitions: projected.footnoteDefinitions,
            footnoteReferences: projected.footnoteReferences,
            mathExpressions: projected.mathExpressions,
            links: projected.links,
            diagnostics: projected.diagnostics
        )
        let id = VaultQualifiedNoteID(
            vaultID: topics.id,
            relativePath: document.relativePath
        )

        let reused = WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: [document]],
            semanticDocuments: [id: fingerprintBound]
        )
        let stale = WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: [document]],
            semanticDocuments: [id: projected]
        )

        #expect(try #require(reused.notes.first).title == "Cached Semantic Title")
        #expect(try #require(stale.notes.first).title == "Authoritative Title")
    }

    @Test("Incomplete retired catalog projections are rejected")
    func incompleteCatalogNoteIsRejected() throws {
        let topics = vault("Topics", .topicKnowledge)
        let document = note("Topic.md", "---\ntitle: Topic\n---\nBody")
        let note = try #require(WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: [document]]
        ).notes.first)
        let encoded = try JSONEncoder().encode(note)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["aliases"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WorkspaceCatalogNote.self, from: legacy)
        }
    }

    @Test("Analysis catalog notes project portable managed academic identity fields")
    func analysisAcademicIdentity() throws {
        let analyses = vault("Analyses", .sourceCorpus)
        let document = note("Scanlon.md", "Analysis")
        let noteID = UUID()
        let record = NoteMetadataRecord(
            noteID: noteID,
            fields: [
                "title": .string("What We Owe to Each Other"),
                "authors": .array([.object([
                    "family": .string("Scanlon"),
                    "given": .string("T. M."),
                ])]),
                "publication_date": .string("1998-01-01T00:00:00.000Z"),
            ]
        )
        let qualifiedID = VaultQualifiedNoteID(
            vaultID: analyses.id,
            relativePath: document.relativePath
        )
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: [analyses],
            documents: [analyses.id: [document]],
            stableNoteIDs: [qualifiedID: noteID],
            noteMetadataByID: [
                noteID: NoteMetadataSnapshot(
                    record: record,
                    revision: DocumentFingerprint(data: try record.encodedPortableData())
                ),
            ]
        )
        let result = try #require(catalog.notes.first)
        #expect(result.authors == ["T. M. Scanlon"])
        #expect(result.publicationDate == "1998-01-01T00:00:00.000Z")
    }

    @Test("Retired workflow metadata does not create Attention")
    func retiredWorkflowStateIsNotAttention() {
        let source = vault("Analyses", .sourceCorpus)
        let topic = vault("Topics", .topicKnowledge)
        let sourceDoc = note("Paper.md", "---\ntitle: Paper\nsource_access: missing\n---\n-[[Reasons]]")
        let topicDoc = note("Reasons.md", "---\ntitle: Reasons\nsettlement_status: unsettled\nprose_permission: blocked\n---\n+[[Paper]]")
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [source, topic],
            documents: [source.id: [sourceDoc], topic.id: [topicDoc]]
        )

        #expect(snapshot.attention.isEmpty)
    }

    @Test("Attention reports only canonical structural issues without promoting them")
    func canonicalAttention() {
        let source = vault("Analyses", .sourceCorpus)
        let work = vault("Works", .draftProject)
        let sourceDoc = note("Paper.md", "---\ntitle: Paper\n---\nAnalysis")
        let malformed = note("Claim.md", "---\ntitle: [broken\n---\nUse [[Missing Note]].")
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [source, work],
            documents: [source.id: [sourceDoc], work.id: [malformed]],
            settlementStates: [
                ref(source, sourceDoc).id: WorkspaceSettlementState(
                    settledFingerprint: DocumentFingerprint(content: "previous"),
                    changedSinceSettled: true
                ),
            ]
        )

        #expect(snapshot.attention.contains { $0.kind == .possibleOrphan })
        #expect(snapshot.attention.contains { $0.kind == .changedSinceSettled })
        #expect(snapshot.attention.contains { $0.kind == .malformedMetadata })
        let broken = snapshot.attention.first { $0.kind == .brokenConnection }
        #expect(broken?.note.relativePath == "Claim.md")
        #expect(broken?.locator?.line == 4)
        #expect(Set(snapshot.attention.map(\.kind)).isSubset(of: Set(AttentionQueueKind.allCases)))
    }

    @Test("A resolved neutral same-vault link prevents Possible Orphan")
    func neutralConnectionPreventsPossibleOrphan() {
        let topics = vault("Topics", .topicKnowledge)
        let first = note("First.md", "See [[Second]].")
        let second = note("Second.md", "A connected note.")

        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: [first, second]]
        )

        #expect(!snapshot.attention.contains { $0.kind == .possibleOrphan })
    }

    @Test("An unresolved outgoing link does not count as an orphan-preventing connection")
    func unresolvedConnectionDoesNotPreventPossibleOrphan() {
        let topics = vault("Topics", .topicKnowledge)
        let document = note("Unresolved.md", "See [[Missing]].")

        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: [document]]
        )

        #expect(snapshot.attention.contains {
            $0.kind == .possibleOrphan && $0.note.relativePath == document.relativePath
        })
        #expect(snapshot.attention.contains {
            $0.kind == .brokenConnection && $0.note.relativePath == document.relativePath
        })
    }

    @Test("Ambiguous Connections remain unresolved and source anchored")
    func ambiguousConnectionAttention() {
        let analyses = vault("Analyses", .sourceCorpus)
        let topics = vault("Topics", .topicKnowledge)
        let works = vault("Works", .draftProject)
        let analysis = note("Paper.md", "Analysis")
        let topic = note("Paper.md", "Topic")
        let work = note("Draft.md", "See [[Paper]].")

        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [analyses, topics, works],
            documents: [analyses.id: [analysis], topics.id: [topic], works.id: [work]]
        )

        let item = snapshot.attention.first { $0.kind == .ambiguousConnection }
        #expect(item?.note.relativePath == "Draft.md")
        #expect(item?.locator?.line == 1)
        #expect(item?.message == "Multiple matching Notes")
    }

    @Test("Attention filtering and timed dismissal share one deterministic contract")
    func attentionFilterAndDismissal() {
        let vault = vault("Topics", .topicKnowledge)
        let reference = VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: "Reasons.md"
        )
        let item = AttentionQueueItem(
            kind: .changedSinceSettled,
            severity: .warning,
            note: reference,
            message: "The committed source changed.",
            locator: SourceLocator(file: "Reasons.md", line: 12, column: 1)
        )
        let other = AttentionQueueItem(
            kind: .possibleOrphan,
            severity: .information,
            note: reference,
            message: "Possible orphan."
        )

        #expect(AttentionQueueFilter(kind: .changedSinceSettled, query: "line 12")
            .apply(to: [item, other]) == [item])

        let now = Date(timeIntervalSince1970: 1_000_000)
        var ledger = AttentionDismissalLedger()
        ledger.dismiss(item, forDays: 7, at: now)
        #expect(ledger.visible([item, other], at: now) == [other])
        #expect(ledger.visible([item, other], at: now.addingTimeInterval(8 * 86_400)) == [item, other])
        ledger.removeExpired(at: now.addingTimeInterval(8 * 86_400))
        #expect(ledger.dismissedUntilByItemID.isEmpty)
    }

    @Test("Leave Unchanged binds one Triptych Material revision pair")
    func materialRevisionDismissalIsExactAndBackwardCompatible() throws {
        let triptychID = UUID()
        let topicID = UUID()
        let materialID = UUID()
        let material = VaultNoteReference(
            vaultID: UUID(),
            vaultName: "Analyses",
            vaultRole: .sourceCorpus,
            relativePath: "Analysis.md",
            stableNoteID: materialID.uuidString.lowercased()
        )
        let topic = VaultNoteReference(
            vaultID: UUID(),
            vaultName: "Topics",
            vaultRole: .topicKnowledge,
            relativePath: "Topic.md",
            stableNoteID: topicID.uuidString.lowercased()
        )
        let recorded = DocumentFingerprint(content: "recorded")
        func item(recordID: UUID, current: String) -> AttentionQueueItem {
            AttentionQueueItem(
                kind: .materialChangedSinceUse,
                severity: .warning,
                note: topic,
                message: "The actually-used Analysis revision changed.",
                materialChangedSinceUse: MaterialChangedSinceUseAttentionContext(
                    triptychID: triptychID,
                    recordID: recordID,
                    topicNoteID: topicID,
                    materialNoteID: materialID,
                    material: material,
                    recordedRevision: recorded,
                    currentRevision: DocumentFingerprint(content: current)
                )
            )
        }

        let first = item(recordID: UUID(), current: "current-one")
        let equivalentRecord = item(recordID: UUID(), current: "current-one")
        let laterRevision = item(recordID: UUID(), current: "current-two")
        let otherTopicID = UUID()
        let otherTopic = AttentionQueueItem(
            kind: .materialChangedSinceUse,
            severity: .warning,
            note: VaultNoteReference(
                vaultID: topic.vaultID,
                vaultName: topic.vaultName,
                vaultRole: topic.vaultRole,
                relativePath: "Other Topic.md",
                stableNoteID: otherTopicID.uuidString.lowercased()
            ),
            message: "The same actually-used Analysis revision changed.",
            materialChangedSinceUse: MaterialChangedSinceUseAttentionContext(
                triptychID: triptychID,
                recordID: UUID(),
                topicNoteID: otherTopicID,
                materialNoteID: materialID,
                material: material,
                recordedRevision: recorded,
                currentRevision: DocumentFingerprint(content: "current-one")
            )
        )
        let otherTriptych = AttentionQueueItem(
            kind: .materialChangedSinceUse,
            severity: .warning,
            note: topic,
            message: "A copied Triptych owns an independent decision.",
            materialChangedSinceUse: MaterialChangedSinceUseAttentionContext(
                triptychID: UUID(),
                recordID: UUID(),
                topicNoteID: topicID,
                materialNoteID: materialID,
                material: material,
                recordedRevision: recorded,
                currentRevision: DocumentFingerprint(content: "current-one")
            )
        )
        #expect(first.id == equivalentRecord.id)
        #expect(first.id != otherTopic.id)
        #expect(first.id != otherTriptych.id)
        #expect(first.id != laterRevision.id)

        var ledger = AttentionDismissalLedger()
        ledger.leaveUnchanged(first)
        #expect(ledger.visible([
            first, equivalentRecord, otherTopic, laterRevision, otherTriptych,
        ]) == [laterRevision, otherTriptych])

        let encoded = try JSONEncoder().encode(ledger)
        #expect(try JSONDecoder().decode(
            AttentionDismissalLedger.self,
            from: encoded
        ) == ledger)
        var legacy = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "revisionBoundItemIDs")
        #expect(try JSONDecoder().decode(
            AttentionDismissalLedger.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        ).revisionBoundItemIDs.isEmpty)
    }

    @Test("Folder spellings never suppress ordinary Attention")
    func folderNamesDoNotSuppressAttention() {
        let topics = vault("Topics", .topicKnowledge)
        let archived = note("Archive/Old.md", "---\ntitle: [broken\n---\n[[Missing]]")
        let removed = note("Removed/Deleted.md", "Isolated")
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: [archived, removed]],
            settlementStates: [
                ref(topics, archived).id: WorkspaceSettlementState(
                    settledFingerprint: DocumentFingerprint(content: "older"),
                    changedSinceSettled: true
                ),
            ]
        )

        #expect(snapshot.attention.contains {
            $0.note.relativePath == archived.relativePath
        })
        #expect(snapshot.attention.contains {
            $0.note.relativePath == removed.relativePath
        })
    }

    @Test("Unresolved stable identity appears as dismissible derived Attention")
    func unresolvedIdentityAttention() {
        let works = vault("Works", .draftProject)
        let document = note("Drafts/Renamed.md", "A duplicated external file.")
        let ambiguity = NoteIdentityAmbiguity(
            vaultID: works.id,
            relativePath: document.relativePath,
            fingerprint: document.fingerprint,
            candidates: [
                NoteIdentityRecord(
                    vaultID: works.id,
                    relativePath: "Drafts/Earlier Name.md",
                    fingerprint: document.fingerprint
                ),
                NoteIdentityRecord(
                    vaultID: works.id,
                    relativePath: "Drafts/Other Copy.md",
                    fingerprint: document.fingerprint
                ),
            ]
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [works],
            documents: [works.id: [document]],
            identityAmbiguitiesByVault: [works.id: [ambiguity]]
        )

        let item = snapshot.attention.first { $0.kind == .unresolvedIdentity }
        #expect(item?.note.relativePath == document.relativePath)
        #expect(item?.message == "Multiple candidates")
        #expect(item?.severity == .warning)
    }


    @Test("Only a stable-ID Analysis binding enters the catalog")
    func portableAnalysisZoteroBindingOnly() throws {
        let analysisVault = vault("Analyses", .sourceCorpus)
        let topicVault = vault("Topics", .topicKnowledge)
        let worksVault = vault("Works", .draftProject)
        let canonical = note(
            "Canonical.md",
            "---\ntitle: Canonical\nzotero_item_key: CANON001\n---\nAnalysis"
        )
        let unbound = note(
            "Unbound.md",
            "---\ntitle: Unbound\nzotero_item_key: YAML001\n---\nAnalysis"
        )
        let topic = note(
            "Topic.md",
            "---\nzotero_item_key: TOPIC001\n---\n# Topic"
        )
        let work = note(
            "Work.md",
            "---\nzotero_item_key: WORK001\n---\n# Work"
        )
        let analysisID = UUID()
        let topicID = UUID()
        let analysisBinding = try AnalysisZoteroBinding(
            noteID: analysisID,
            library: .user,
            itemKey: "bound001"
        )
        let topicBinding = try AnalysisZoteroBinding(
            noteID: topicID,
            library: .user,
            itemKey: "topic001"
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [analysisVault, topicVault, worksVault],
            documents: [
                analysisVault.id: [canonical, unbound],
                topicVault.id: [topic],
                worksVault.id: [work],
            ],
            stableNoteIDs: [
                VaultQualifiedNoteID(vaultID: analysisVault.id, relativePath: canonical.relativePath): analysisID,
                VaultQualifiedNoteID(vaultID: topicVault.id, relativePath: topic.relativePath): topicID,
            ],
            zoteroBindingsByNoteID: [
                analysisID: analysisBinding,
                topicID: topicBinding,
            ]
        )
        let notesByPath = Dictionary(uniqueKeysWithValues: snapshot.notes.map {
            ($0.reference.relativePath, $0)
        })

        #expect(notesByPath["Canonical.md"]?.zoteroBinding == analysisBinding)
        #expect(notesByPath["Unbound.md"]?.zoteroBinding == nil)
        #expect(notesByPath["Topic.md"]?.zoteroBinding == nil)
        #expect(notesByPath["Work.md"]?.zoteroBinding == nil)
    }


    private func vault(_ name: String, _ role: VaultRole) -> RegisteredVault {
        RegisteredVault(name: name, role: role, canonicalPath: "/fixtures/\(name)")
    }

    private func note(_ path: String, _ source: String) -> NoteDocument {
        NoteDocument(relativePath: path, rawContent: source)
    }

    private func ref(_ vault: RegisteredVault, _ note: NoteDocument) -> VaultNoteReference {
        VaultNoteReference(
            vaultID: vault.id,
            vaultName: vault.name,
            vaultRole: vault.role,
            relativePath: note.relativePath
        )
    }

}
