import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Triptych workspace catalog")
struct WorkspaceCatalogTests {
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
            "---\ntitle: Argument Draft\n---\n+[[Agency]]"
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
                return LinkCatalogNote(vaultID: vault.id, document: document, semantic: semantics[id])
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
        #expect(related.first?.sourceLine == 4)
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

    @Test("Related identity preserves diacritics while folding case")
    func relatedIdentityDoesNotEraseDiacritics() {
        let topics = vault("Topics", .topicKnowledge)
        let works = vault("Works", .draftProject)
        let topic = note("Cafe.md", "---\ntitle: Café\n---\n")
        let draft = note("Draft.md", "---\ntitle: Draft\n---\n+[[Café]]")
        let topicID = VaultQualifiedNoteID(vaultID: topics.id, relativePath: topic.relativePath)
        let draftID = VaultQualifiedNoteID(vaultID: works.id, relativePath: draft.relativePath)
        let topicSemantic = MarkdownSemanticDocument(parsing: topic)
        let draftSemantic = MarkdownSemanticDocument(parsing: draft)
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: [
                LinkCatalogNote(vaultID: topics.id, document: topic, semantic: topicSemantic),
                LinkCatalogNote(vaultID: works.id, document: draft, semantic: draftSemantic),
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
                return LinkCatalogNote(vaultID: topics.id, document: document, semantic: semantics[id])
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
            reviewStates: [
                ref(source, sourceDoc).id: WorkspaceReviewState(
                    qualification: "qualified",
                    reviewedFingerprint: DocumentFingerprint(content: "previous"),
                    changedSinceReview: true
                ),
            ]
        )

        #expect(snapshot.attention.contains { $0.kind == .possibleOrphan })
        #expect(snapshot.attention.contains { $0.kind == .changedSinceReview })
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
            kind: .changedSinceReview,
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

        #expect(AttentionQueueFilter(kind: .changedSinceReview, query: "line 12")
            .apply(to: [item, other]) == [item])

        let now = Date(timeIntervalSince1970: 1_000_000)
        var ledger = AttentionDismissalLedger()
        ledger.dismiss(item, forDays: 7, at: now)
        #expect(ledger.visible([item, other], at: now) == [other])
        #expect(ledger.visible([item, other], at: now.addingTimeInterval(8 * 86_400)) == [item, other])
        ledger.removeExpired(at: now.addingTimeInterval(8 * 86_400))
        #expect(ledger.dismissedUntilByItemID.isEmpty)
    }

    @Test("Set Aside and Trash remain outside ordinary Attention")
    func inactiveLocationsAreExcluded() {
        let topics = vault("Topics", .topicKnowledge)
        let setAside = note("Set Aside/Old.md", "---\ntitle: [broken\n---\n[[Missing]]")
        let trash = note("Trash/Deleted.md", "Isolated")
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [topics],
            documents: [topics.id: [setAside, trash]],
            reviewStates: [
                ref(topics, setAside).id: WorkspaceReviewState(
                    qualification: "qualified",
                    reviewedFingerprint: DocumentFingerprint(content: "older"),
                    changedSinceReview: true
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

    @Test("Target-to-containing support from an Unqualified Analysis creates source-anchored Attention")
    func unqualifiedAnalysisSupportUse() {
        let source = vault("Analyses", .sourceCorpus)
        let topic = vault("Topics", .topicKnowledge)
        let analysis = note("Papers/Foot.md", "---\ntitle: The Problem of Abortion\n---\nAnalysis")
        let synthesis = note(
            "Abortion.md",
            "A claim needing support.\n-[[The Problem of Abortion]]\n"
        )
        let sourceReference = ref(source, analysis)
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [source, topic],
            documents: [source.id: [analysis], topic.id: [synthesis]],
            reviewStates: [sourceReference.id: WorkspaceReviewState(qualification: "unqualified")]
        )

        let item = snapshot.attention.first { $0.kind == .unqualifiedAnalysisReliance }
        #expect(item?.note.relativePath == "Abortion.md")
        #expect(item?.locator?.line == 2)
        #expect(item?.severity == .warning)
        #expect(item?.message.contains("explicitly supported by") == true)
    }

    @Test("Neutral, opposite-direction, incompatible, and legacy links are not scholarly reliance")
    func neutralAnalysisConnectionsAreNotReliance() {
        let source = vault("Analyses", .sourceCorpus)
        let topic = vault("Topics", .topicKnowledge)
        let analysis = note("Paper.md", "---\ntitle: Paper Analysis\n---\nAnalysis")
        let synthesis = note(
            "Topic.md",
            """
            [[Paper Analysis]]
            +[[Paper Analysis]]
            ?[[Paper Analysis]]
            [[Paper Analysis|:supports]]
            """
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [source, topic],
            documents: [source.id: [analysis], topic.id: [synthesis]],
            reviewStates: [
                ref(source, analysis).id: WorkspaceReviewState(qualification: "unqualified"),
            ]
        )

        #expect(snapshot.attention.allSatisfy { $0.kind != .unqualifiedAnalysisReliance })
    }

    @Test("A neutral Analysis link in a Source callout is an explicit citation")
    func unqualifiedAnalysisCitationUse() {
        let source = vault("Analyses", .sourceCorpus)
        let work = vault("Works", .draftProject)
        let analysis = note("Paper.md", "---\ntitle: Paper Analysis\n---\nAnalysis")
        let draft = note(
            "Argument.md",
            """
            A draft claim.

            > [!cite] Source
            > [[Paper Analysis]]
            """
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [source, work],
            documents: [source.id: [analysis], work.id: [draft]],
            reviewStates: [
                ref(source, analysis).id: WorkspaceReviewState(qualification: "unqualified"),
            ]
        )

        let item = snapshot.attention.first { $0.kind == .unqualifiedAnalysisReliance }
        #expect(item?.note.relativePath == "Argument.md")
        #expect(item?.locator?.line == 4)
        #expect(item?.message.contains("Source callout") == true)
    }

    @Test("A neutral Analysis link in a footnote is an explicit citation")
    func unqualifiedAnalysisFootnoteUse() {
        let source = vault("Analyses", .sourceCorpus)
        let topic = vault("Topics", .topicKnowledge)
        let analysis = note("Paper.md", "---\ntitle: Paper Analysis\n---\nAnalysis")
        let synthesis = note(
            "Topic.md",
            "Claim text.[^source]\n\n[^source]: See [[Paper Analysis]].\n"
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [source, topic],
            documents: [source.id: [analysis], topic.id: [synthesis]],
            reviewStates: [
                ref(source, analysis).id: WorkspaceReviewState(qualification: "unqualified"),
            ]
        )

        let item = snapshot.attention.first { $0.kind == .unqualifiedAnalysisReliance }
        #expect(item?.locator?.line == 3)
        #expect(item?.message.contains("footnote") == true)
    }

    @Test("Zotero source selection includes only Analyses linked from the opened Topic")
    func analysesLinkedFromTopic() {
        let analysisVault = vault("Analyses", .sourceCorpus)
        let topicVault = vault("Topics", .topicKnowledge)
        let used = note(
            "Used.md",
            "---\ntitle: Used Analysis\nauthors: [A. Scholar]\nyear: 2024\ndoi: 10.1000/used\nisbn: 978-1-2345-6789-0\nzotero_citation_key: ScholarUsed2024\nzotero_item_key: USED0001\n---\nSee [[Transitive Analysis]]."
        )
        let transitive = note(
            "Transitive.md",
            "---\ntitle: Transitive Analysis\nzotero_item_key: TRANS001\n---\nAnalysis"
        )
        let unlinked = note(
            "Unlinked.md",
            "---\ntitle: Unlinked Analysis\nzotero_item_key: NONE0001\n---\nSee [[Topic]]."
        )
        let duplicate = note(
            "Duplicate.md",
            "---\ntitle: Duplicate Analysis\nzotero_item_key: used0001\n---\nAnalysis"
        )
        let keyless = note(
            "Keyless.md",
            "---\ntitle: Keyless Analysis\nauthors: [Another Scholar]\nyear: 2024\ndoi: 10.1000/keyless\n---\nAnalysis"
        )
        let topic = note(
            "Topic.md",
            "Use [[Used Analysis]], [[Duplicate Analysis]], and [[Keyless Analysis]]."
        )
        let allDocuments: [(RegisteredVault, NoteDocument)] = [
            (analysisVault, used),
            (analysisVault, transitive),
            (analysisVault, unlinked),
            (analysisVault, duplicate),
            (analysisVault, keyless),
            (topicVault, topic),
        ]
        let semantics = Dictionary(uniqueKeysWithValues: allDocuments.map { vault, document in
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
            return (id, MarkdownSemanticDocument(parsing: document))
        })
        let linkCatalog = allDocuments.map { vault, document in
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
            return LinkCatalogNote(vaultID: vault.id, document: document, semantic: semantics[id])
        }
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: linkCatalog,
            documents: semantics,
            resolutionScope: .workspace
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [analysisVault, topicVault],
            documents: [
                analysisVault.id: [used, transitive, unlinked, duplicate, keyless],
                topicVault.id: [topic],
            ],
            graph: graph
        )

        let selected = snapshot.zoteroSourceAnalyses(
            linkedFrom: ref(topicVault, topic),
            analysesVaultID: analysisVault.id
        )
        #expect(selected.map(\.title) == ["Used Analysis"])
        #expect(selected.first?.zoteroItemKey == "USED0001")
        #expect(selected.first?.zoteroSourceIdentity?.doi == "10.1000/used")
        #expect(selected.first?.zoteroSourceIdentity?.isbn == "978-1-2345-6789-0")
        #expect(selected.first?.zoteroSourceIdentity?.citationKey == "ScholarUsed2024")
        #expect(selected.first?.zoteroSourceIdentity?.authors == ["A. Scholar"])
        #expect(selected.first?.zoteroSourceIdentity?.year == 2024)
    }

    @Test("Zotero source selection applies to Works but not Unclassified notes")
    func analysesLinkedFromWorkOnly() {
        let analysisVault = vault("Analyses", .sourceCorpus)
        let worksVault = vault("Works", .draftProject)
        let unclassifiedVault = vault("Unclassified", .other)
        let analysis = note(
            "Paper.md",
            "---\ntitle: Paper Analysis\nzotero_item_key: PAPER001\n---\nAnalysis"
        )
        let work = note("Argument.md", "Use [[Paper Analysis]].")
        let unclassified = note("Scratch.md", "Use [[Paper Analysis]].")
        let allDocuments: [(RegisteredVault, NoteDocument)] = [
            (analysisVault, analysis),
            (worksVault, work),
            (unclassifiedVault, unclassified),
        ]
        let semantics = Dictionary(uniqueKeysWithValues: allDocuments.map { vault, document in
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
            return (id, MarkdownSemanticDocument(parsing: document))
        })
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: allDocuments.map { vault, document in
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                return LinkCatalogNote(vaultID: vault.id, document: document, semantic: semantics[id])
            },
            documents: semantics,
            resolutionScope: .workspace
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [analysisVault, worksVault, unclassifiedVault],
            documents: [
                analysisVault.id: [analysis],
                worksVault.id: [work],
                unclassifiedVault.id: [unclassified],
            ],
            graph: graph
        )

        #expect(snapshot.zoteroSourceAnalyses(
            linkedFrom: ref(worksVault, work),
            analysesVaultID: analysisVault.id
        ).map(\.title) == ["Paper Analysis"])
        #expect(snapshot.zoteroSourceAnalyses(
            linkedFrom: ref(unclassifiedVault, unclassified),
            analysesVaultID: analysisVault.id
        ).isEmpty)
    }

    @Test("Zotero sources cannot come from an Analysis vault outside the active Triptych")
    func sourceMustBelongToActiveAnalysesVault() {
        let activeAnalyses = vault("Active Analyses", .sourceCorpus)
        let staleAnalyses = vault("Old Analyses", .sourceCorpus)
        let topicVault = vault("Topics", .topicKnowledge)
        let stale = note(
            "Stale.md",
            "---\ntitle: Stale Analysis\nzotero_item_key: STALE001\n---\nAnalysis"
        )
        let topic = note("Topic.md", "Do not use [[Stale Analysis]] as a Zotero source.")
        let allDocuments: [(RegisteredVault, NoteDocument)] = [
            (staleAnalyses, stale),
            (topicVault, topic),
        ]
        let semantics = Dictionary(uniqueKeysWithValues: allDocuments.map { vault, document in
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
            return (id, MarkdownSemanticDocument(parsing: document))
        })
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: allDocuments.map { vault, document in
                let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: document.relativePath)
                return LinkCatalogNote(vaultID: vault.id, document: document, semantic: semantics[id])
            },
            documents: semantics,
            resolutionScope: .workspace
        )
        let snapshot = WorkspaceCatalogBuilder.build(
            vaults: [activeAnalyses, staleAnalyses, topicVault],
            documents: [staleAnalyses.id: [stale], topicVault.id: [topic]],
            graph: graph
        )

        #expect(snapshot.zoteroSourceAnalyses(
            linkedFrom: ref(topicVault, topic),
            analysesVaultID: activeAnalyses.id
        ).isEmpty)
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
