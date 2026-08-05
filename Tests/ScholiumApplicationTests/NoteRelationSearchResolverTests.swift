import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Application direct-relation Search resolution")
struct NoteRelationSearchResolverTests {
    @Test("Directed relation queries preserve subject and object direction with source provenance")
    func directedRelationsPreserveDirection() throws {
        let fixture = Fixture()
        let support = fixture.edge(
            containing: fixture.anchorID,
            target: fixture.targetID,
            kind: .supports,
            line: 3
        )
        let opposition = fixture.edge(
            containing: fixture.rivalID,
            target: fixture.anchorID,
            kind: .opposes,
            line: 5
        )
        let catalog = fixture.catalog(relationships: [support, opposition])

        let fromSupport = try fixture.resolve(
            "from-note:Anchor relation:supports",
            catalog: catalog
        )
        let toSupport = try fixture.resolve(
            "to-note:Target relation:supports",
            catalog: catalog
        )
        let fromOpposition = try fixture.resolve(
            "from-note:Rival relation:opposes",
            catalog: catalog
        )
        let toOpposition = try fixture.resolve(
            "to-note:Anchor relation:opposes",
            catalog: catalog
        )

        #expect(Set(fromSupport.matches.keys) == [fixture.targetID])
        #expect(Set(toSupport.matches.keys) == [fixture.anchorID])
        #expect(Set(fromOpposition.matches.keys) == [fixture.anchorID])
        #expect(Set(toOpposition.matches.keys) == [fixture.rivalID])
        #expect(fromSupport.matches[fixture.targetID]?.direction == .fromNote)
        #expect(toSupport.matches[fixture.anchorID]?.direction == .toNote)
        #expect(
            fromSupport.matches[fixture.targetID]?.occurrences.first?.sourceNote
                == fixture.anchorID
        )
        #expect(
            fromOpposition.matches[fixture.anchorID]?.occurrences.first?.sourceNote
                == fixture.rivalID
        )
    }

    @Test("Neutral and incompatible relation queries are symmetric for from and to anchors")
    func undirectedRelationsAreSymmetric() throws {
        let fixture = Fixture()
        let neutral = fixture.edge(
            containing: fixture.anchorID,
            target: fixture.targetID,
            kind: .neutral,
            line: 7
        )
        let incompatible = fixture.edge(
            containing: fixture.rivalID,
            target: fixture.anchorID,
            kind: .incompatible,
            line: 9
        )
        let catalog = fixture.catalog(relationships: [neutral, incompatible])

        for query in [
            "from-note:Anchor relation:neutral",
            "to-note:Anchor relation:neutral",
        ] {
            let resolution = try fixture.resolve(query, catalog: catalog)
            #expect(Set(resolution.matches.keys) == [fixture.targetID])
            #expect(resolution.diagnostic == nil)
        }
        for query in [
            "from-note:Anchor relation:incompatible",
            "to-note:Anchor relation:incompatible",
        ] {
            let resolution = try fixture.resolve(query, catalog: catalog)
            #expect(Set(resolution.matches.keys) == [fixture.rivalID])
            #expect(resolution.diagnostic == nil)
        }
    }

    @Test("Exact aliases obey authorized scope while missing and ambiguous identities fail closed")
    func identityAndScopeFailClosed() throws {
        let fixture = Fixture(includeDuplicateAnchor: true)
        let support = fixture.edge(
            containing: fixture.anchorID,
            target: fixture.targetID,
            kind: .supports,
            line: 11
        )
        let crossVault = fixture.edge(
            containing: fixture.anchorID,
            target: fixture.duplicateAnchorID,
            kind: .supports,
            line: 12
        )
        let catalog = fixture.catalog(relationships: [support, crossVault])

        let scopedAlias = try fixture.resolve(
            #"from-note:"Anchor Alias" relation:supports"#,
            scope: .currentVault(fixture.primaryVault.id),
            catalog: catalog
        )
        #expect(Set(scopedAlias.matches.keys) == [fixture.targetID])

        let ambiguous = try fixture.resolve(
            "from-note:Anchor relation:supports",
            catalog: catalog
        )
        #expect(ambiguous.matches.isEmpty)
        #expect(ambiguous.diagnostic?.code == .ambiguousIdentity)

        let missing = try fixture.resolve(
            "from-note:Missing relation:supports",
            catalog: catalog
        )
        #expect(missing.matches.isEmpty)
        #expect(missing.diagnostic?.code == .notApplicable)

        let thisNote = try fixture.resolve(
            "from-note:Anchor relation:supports",
            scope: .currentNote(SearchSourceSnapshot(
                noteID: fixture.anchorID,
                editorSessionID: UUID(),
                source: "# Anchor\n",
                editorRevision: 1
            )),
            catalog: catalog
        )
        #expect(thisNote.matches.isEmpty)
        #expect(thisNote.diagnostic?.code == .notApplicable)
    }

    @Test("A Graph from another source manifest fails the complete relation clause closed")
    func manifestMismatchFailsClosed() throws {
        let vault = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/fixture/topics"
        )
        let anchor = NoteDocument(
            relativePath: "Anchor.md",
            rawContent: "---\ntitle: Anchor\n---\n"
        )
        let target = NoteDocument(
            relativePath: "Target.md",
            rawContent: "---\ntitle: Target\n---\n"
        )
        let catalog = WorkspaceCatalogBuilder.build(
            vaults: [vault],
            documents: [vault.id: [anchor, target]],
            graph: GraphSnapshot(
                contractVersion: GraphSnapshot.currentContractVersion,
                generation: 1,
                sourceManifestHash: "graph-manifest",
                outgoing: [:],
                incoming: [:],
                diagnostics: [],
                relationships: []
            )
        )
        let ast = try #require(
            SearchQueryParser.parse(
                "bounded-term from-note:Anchor.md relation:supports"
            ).ast
        )
        let generation = SearchGenerationID(
            triptychID: UUID(),
            sequence: 1,
            sourceManifestHash: "search-manifest"
        )

        let resolution = NoteRelationSearchResolver.resolve(
            ast: ast,
            scope: .triptych,
            catalog: catalog,
            searchGeneration: generation
        )

        #expect(resolution.matches.isEmpty)
        #expect(resolution.diagnostic?.code == .notApplicable)
        #expect(
            resolution.diagnostic?.message
                == "Direct relation Search is unavailable until Graph and Note Search share one complete source manifest."
        )
    }
}

private extension NoteRelationSearchResolverTests {
    struct Fixture {
        let primaryVault = RegisteredVault(
            name: "Topics",
            role: .topicKnowledge,
            canonicalPath: "/fixture/topics"
        )
        let secondaryVault = RegisteredVault(
            name: "Analyses",
            role: .sourceCorpus,
            canonicalPath: "/fixture/analyses"
        )
        let manifest = "complete-search-graph-manifest"
        let includeDuplicateAnchor: Bool

        var anchorID: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: primaryVault.id, relativePath: "Anchor.md")
        }

        var targetID: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: primaryVault.id, relativePath: "Target.md")
        }

        var rivalID: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: primaryVault.id, relativePath: "Rival.md")
        }

        var duplicateAnchorID: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: secondaryVault.id, relativePath: "Other Anchor.md")
        }

        init(includeDuplicateAnchor: Bool = false) {
            self.includeDuplicateAnchor = includeDuplicateAnchor
        }

        func catalog(relationships: [RelationshipEdge]) -> WorkspaceCatalogSnapshot {
            var documents: [UUID: [NoteDocument]] = [
                primaryVault.id: [
                    NoteDocument(
                        relativePath: anchorID.relativePath,
                        rawContent: "---\ntitle: Anchor\naliases: [Anchor Alias]\n---\n# Anchor\n"
                    ),
                    NoteDocument(relativePath: targetID.relativePath, rawContent: "# Target\n"),
                    NoteDocument(relativePath: rivalID.relativePath, rawContent: "# Rival\n"),
                ],
            ]
            if includeDuplicateAnchor {
                documents[secondaryVault.id] = [NoteDocument(
                    relativePath: duplicateAnchorID.relativePath,
                    rawContent: "---\ntitle: Anchor\n---\n# Other Anchor\n"
                )]
            }
            return WorkspaceCatalogBuilder.build(
                vaults: includeDuplicateAnchor
                    ? [primaryVault, secondaryVault]
                    : [primaryVault],
                documents: documents,
                graph: GraphSnapshot(
                    contractVersion: GraphSnapshot.currentContractVersion,
                    generation: 1,
                    sourceManifestHash: manifest,
                    outgoing: [:],
                    incoming: [:],
                    diagnostics: [],
                    relationships: relationships
                )
            )
        }

        func edge(
            containing: VaultQualifiedNoteID,
            target: VaultQualifiedNoteID,
            kind: VectorLinkKind,
            line: Int
        ) -> RelationshipEdge {
            RelationshipEdge.vector(
                containing: containing,
                target: target,
                targetPath: target.relativePath,
                kind: kind,
                locator: SourceLocator(
                    file: containing.relativePath,
                    line: line,
                    column: 1
                ),
                syntax: .vectorWikilink,
                resolution: .resolved(target.relativePath)
            )
        }

        func resolve(
            _ query: String,
            scope: SearchExecutionScope = .triptych,
            catalog: WorkspaceCatalogSnapshot
        ) throws -> NoteRelationSearchResolver.Resolution {
            let parsed = SearchQueryParser.parse(query)
            #expect(parsed.diagnostics.isEmpty)
            return NoteRelationSearchResolver.resolve(
                ast: try #require(parsed.ast),
                scope: scope,
                catalog: catalog,
                searchGeneration: SearchGenerationID(
                    triptychID: UUID(),
                    sequence: 1,
                    sourceManifestHash: manifest
                )
            )
        }
    }
}
