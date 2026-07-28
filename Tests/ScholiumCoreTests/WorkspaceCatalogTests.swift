import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Triptych workspace catalog")
struct WorkspaceCatalogTests {
    @Test("Package catalog assembly reuses only fingerprint-bound semantics")
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

    @Test("Search expansion uses only direct links from one exact Topic concept")
    func relatedSearchIsDirectExplainableAndScopeBounded() throws {
        let analyses = vault("Analyses", .sourceCorpus)
        let topics = vault("Topics", .topicKnowledge)
        let works = vault("Works", .draftProject)
        let concept = note(
            "Agency.md",
            "---\ntitle: Agency\naliases: [Practical Identity]\n---\n+[[Paper Analysis]]"
        )
        let analysis = note(
            "Paper.md",
            "---\ntitle: Paper Analysis\n---\n[[Remote Source]]"
        )
        let remote = note("Remote.md", "---\ntitle: Remote Source\n---\nSource")
        let work = note(
            "Argument.md",
            "# Argument Draft\n\n+[[Agency]]"
        )
        let documents: [(RegisteredVault, NoteDocument)] = [
            (analyses, analysis),
            (analyses, remote),
            (topics, concept),
            (works, work),
        ]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { vault, document in
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
            return (id, MarkdownSemanticDocument(parsing: document))
        })
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { vault, document in
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                return catalogNote(vault, document, semantic: semantics[id])
            },
            documents: semantics,
            resolutionScope: .workspace,
            sourceManifestHash: "manifest"
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [analyses, topics, works],
            documents: [
                analyses.id: [analysis, remote],
                topics.id: [concept],
                works.id: [work],
            ],
            graph: graph
        )
        let searchGeneration = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "manifest"
        )

        let related = snapshot.relatedSearchResults(
            for: "\"Practical Identity\"",
            scope: .triptych,
            searchGeneration: searchGeneration
        )
        #expect(related.map(\.note.title) == ["Argument Draft", "Paper Analysis"])
        #expect(related.first?.relationship == .itemSupportsConcept)
        #expect(related.first?.explanation == "Supports Agency")
        #expect(related.first?.sourceLine == 3)
        #expect(related.last?.relationship == .conceptSupportsItem)
        #expect(related.last?.explanation == "Supported by Agency")
        #expect(!related.contains { $0.note.title == "Remote Source" })

        let analysesOnly = snapshot.relatedSearchResults(
            for: "Agency",
            scope: .currentVault(analyses.id),
            searchGeneration: searchGeneration
        )
        #expect(analysesOnly.map(\.note.title) == ["Paper Analysis"])
        #expect(snapshot.relatedSearchResults(
            for: "Agency",
            scope: .currentNote(SearchSourceSnapshot(
                noteID: VaultQualifiedNoteID(
                    vaultID: topics.id,
                    relativePath: concept.relativePath
                ),
                editorSessionID: UUID(),
                source: concept.rawContent,
                editorRevision: 0
            )),
            searchGeneration: searchGeneration
        ).isEmpty)

        let analysisID = VaultQualifiedNoteID(
            vaultID: analyses.id,
            relativePath: analysis.relativePath
        )
        #expect(snapshot.relatedSearchResults(
            for: "Agency",
            scope: .triptych,
            searchGeneration: searchGeneration,
            excluding: [analysisID]
        ).map(\.note.title) == ["Argument Draft"])
        #expect(snapshot.relatedSearchResults(
            for: "title:Agency",
            scope: .triptych,
            searchGeneration: searchGeneration
        ).isEmpty)
    }

    @Test("Related Search preserves opposition direction and undirected incompatibility")
    func relatedSearchPreservesStanceDirection() {
        let topics = vault("Topics", .topicKnowledge)
        let works = vault("Works", .draftProject)
        let concept = note(
            "Agency.md",
            "# Agency\n\n-[[Target Claim]]\n?[[Conflicting Claim]]"
        )
        let target = note("Target.md", "# Target Claim")
        let conflict = note("Conflict.md", "# Conflicting Claim")
        let opponent = note("Opponent.md", "# Opposing Draft\n\n-[[Agency]]")
        let incompatible = note("Incompatible.md", "# Incompatible Draft\n\n?[[Agency]]")
        let documents: [(RegisteredVault, NoteDocument)] = [
            (topics, concept),
            (works, target),
            (works, conflict),
            (works, opponent),
            (works, incompatible),
        ]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { vault, document in
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
            return (id, MarkdownSemanticDocument(parsing: document))
        })
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { vault, document in
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                return catalogNote(vault, document, semantic: semantics[id])
            },
            documents: semantics,
            resolutionScope: .workspace,
            sourceManifestHash: "manifest"
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [topics, works],
            documents: [
                topics.id: [concept],
                works.id: [target, conflict, opponent, incompatible],
            ],
            graph: graph
        )
        let results = snapshot.relatedSearchResults(
            for: "Agency",
            scope: .triptych,
            searchGeneration: SearchGenerationID(
                triptychID: UUID(),
                sequence: 1,
                sourceManifestHash: "manifest"
            )
        )
        let relationships = Dictionary(uniqueKeysWithValues: results.map {
            ($0.note.title, ($0.relationship, $0.explanation))
        })

        #expect(relationships["Target Claim"]?.0 == .conceptOpposesItem)
        #expect(relationships["Target Claim"]?.1 == "Opposed by Agency")
        #expect(relationships["Conflicting Claim"]?.0 == .incompatible)
        #expect(relationships["Conflicting Claim"]?.1 == "Incompatible with Agency")
        #expect(relationships["Opposing Draft"]?.0 == .itemOpposesConcept)
        #expect(relationships["Opposing Draft"]?.1 == "Opposes Agency")
        #expect(relationships["Incompatible Draft"]?.0 == .incompatible)
        #expect(relationships["Incompatible Draft"]?.1 == "Incompatible with Agency")
    }

    @Test("Related identity preserves diacritics while folding case")
    func relatedIdentityDoesNotEraseDiacritics() {
        let topics = vault("Topics", .topicKnowledge)
        let works = vault("Works", .draftProject)
        let topic = note("Cafe.md", "# Café\n")
        let draft = note("Draft.md", "# Draft\n\n+[[Café]]")
        let topicID = VaultQualifiedNoteID(vaultID: topics.id, relativePath: topic.relativePath)
        let draftID = VaultQualifiedNoteID(vaultID: works.id, relativePath: draft.relativePath)
        let topicSemantic = MarkdownSemanticDocument(parsing: topic)
        let draftSemantic = MarkdownSemanticDocument(parsing: draft)
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: [
                catalogNote(topics, topic, semantic: topicSemantic),
                catalogNote(works, draft, semantic: draftSemantic),
            ],
            documents: [topicID: topicSemantic, draftID: draftSemantic],
            resolutionScope: .workspace,
            sourceManifestHash: "manifest"
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [topics, works],
            documents: [topics.id: [topic], works.id: [draft]],
            graph: graph
        )
        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "manifest"
        )

        #expect(snapshot.relatedSearchResults(
            for: "CAFÉ",
            scope: .triptych,
            searchGeneration: generation
        ).isEmpty == false)
        #expect(snapshot.relatedSearchResults(
            for: "Cafe",
            scope: .triptych,
            searchGeneration: generation
        ).isEmpty)
    }

    @Test("Ambiguous Topic aliases never trigger graph expansion")
    func relatedSearchDoesNotGuessBetweenConcepts() {
        let topics = vault("Topics", .topicKnowledge)
        let first = note("Agency.md", "---\ntitle: Agency\naliases: [Identity]\n---\n")
        let second = note("Personhood.md", "---\ntitle: Personhood\naliases: [Identity]\n---\n")
        let documents = [first, second]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { document in
            let id = VaultQualifiedNoteID(vaultID: topics.id, relativePath: document.relativePath)
            return (id, MarkdownSemanticDocument(parsing: document))
        })
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { document in
                let id = VaultQualifiedNoteID(vaultID: topics.id, relativePath: document.relativePath)
                return catalogNote(topics, document, semantic: semantics[id])
            },
            documents: semantics,
            resolutionScope: .workspace,
            sourceManifestHash: "manifest"
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: documents],
            graph: graph
        )

        #expect(snapshot.relatedSearchResults(
            for: "Identity",
            scope: .triptych,
            searchGeneration: SearchGenerationID(
                triptychID: UUID(),
                sequence: 1,
                sourceManifestHash: "manifest"
            )
        ).isEmpty)
    }

    @Test("A legacy catalog note without aliases remains readable")
    func legacyCatalogNoteDefaultsAliases() throws {
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

        let decoded = try JSONDecoder().decode(WorkspaceCatalogNote.self, from: legacy)
        #expect(decoded.aliases.isEmpty)
        #expect(decoded.reference == note.reference)
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
        #expect(item?.message.contains("did not choose") == true)
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

    @Test("Set Aside and Trash remain outside ordinary Attention")
    func inactiveLocationsAreExcluded() {
        let topics = vault("Topics", .topicKnowledge)
        let setAside = note("Set Aside/Old.md", "---\ntitle: [broken\n---\n[[Missing]]")
        let trash = note("Trash/Deleted.md", "Isolated")
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: [setAside, trash]],
            settlementStates: [
                ref(topics, setAside).id: WorkspaceSettlementState(
                    settledFingerprint: DocumentFingerprint(content: "older"),
                    changedSinceSettled: true
                ),
            ]
        )

        #expect(snapshot.attention.isEmpty)
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
        #expect(item?.message.contains("Earlier Name.md") == true)
        #expect(item?.severity == .warning)
    }


    @Test("Only the canonical Analysis Zotero item key enters the catalog")
    func canonicalAnalysisZoteroItemKeyOnly() {
        let analysisVault = vault("Analyses", .sourceCorpus)
        let topicVault = vault("Topics", .topicKnowledge)
        let worksVault = vault("Works", .draftProject)
        let canonical = note(
            "Canonical.md",
            "---\ntitle: Canonical\nzotero_item_key: CANON001\n---\nAnalysis"
        )
        let legacyAlias = note(
            "Legacy Alias.md",
            "---\ntitle: Legacy Alias\nzoteroKey: ALIAS001\n---\nAnalysis"
        )
        let topic = note(
            "Topic.md",
            "---\nzotero_item_key: TOPIC001\n---\n# Topic"
        )
        let work = note(
            "Work.md",
            "---\nzotero_item_key: WORK001\n---\n# Work"
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [analysisVault, topicVault, worksVault],
            documents: [
                analysisVault.id: [canonical, legacyAlias],
                topicVault.id: [topic],
                worksVault.id: [work],
            ]
        )
        let notesByPath = Dictionary(uniqueKeysWithValues: snapshot.notes.map {
            ($0.reference.relativePath, $0)
        })

        #expect(notesByPath["Canonical.md"]?.zoteroItemKey == "CANON001")
        #expect(notesByPath["Legacy Alias.md"]?.zoteroItemKey == nil)
        #expect(notesByPath["Topic.md"]?.zoteroItemKey == nil)
        #expect(notesByPath["Work.md"]?.zoteroItemKey == nil)
    }


    private func vault(_ name: String, _ role: VaultRole) -> RegisteredVault {
        RegisteredVault(name: name, role: role, canonicalPath: "/fixtures/\(name)")
    }

    private func note(_ path: String, _ source: String) -> NoteDocument {
        NoteDocument(relativePath: path, rawContent: source)
    }

    private func catalogNote(
        _ vault: RegisteredVault,
        _ document: NoteDocument,
        semantic: MarkdownSemanticDocument?
    ) -> LinkCatalogNote {
        LinkCatalogNote(
            vaultID: vault.id,
            document: document,
            profile: WorkflowProfileResolver.resolve(
                vaultRole: vault.role,
                frontmatter: document.parsedFrontmatter,
                relativePath: document.relativePath
            ),
            semantic: semantic
        )
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
