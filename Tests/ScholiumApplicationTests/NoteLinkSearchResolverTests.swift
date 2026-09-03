import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Application direct-link Search resolution")
struct NoteLinkSearchResolverTests {
    @Test("Directed link queries preserve authored direction and occurrence provenance")
    func directedLinksPreserveDirection() throws {
        let fixture = Fixture()
        let catalog = fixture.catalog()

        let fromAnchor = try fixture.resolve("from-note:Anchor", catalog: catalog)
        let toTarget = try fixture.resolve("to-note:Target", catalog: catalog)
        let toAnchor = try fixture.resolve("to-note:Anchor", catalog: catalog)

        #expect(Set(fromAnchor.matches.keys) == [fixture.targetID])
        #expect(Set(toTarget.matches.keys) == [fixture.anchorID])
        #expect(Set(toAnchor.matches.keys) == [fixture.rivalID])
        #expect(fromAnchor.matches[fixture.targetID]?.direction == .fromNote)
        #expect(toTarget.matches[fixture.anchorID]?.direction == .toNote)
        #expect(fromAnchor.matches[fixture.targetID]?.occurrences.first?.sourceNote == fixture.anchorID)
        #expect(toAnchor.matches[fixture.rivalID]?.occurrences.first?.sourceNote == fixture.rivalID)
        #expect(fromAnchor.matches[fixture.targetID]?.occurrences.first?.annotationSpan != nil)
    }

    @Test("Exact aliases obey authorized scope while missing and ambiguous identities fail closed")
    func identityAndScopeFailClosed() throws {
        let fixture = Fixture(includeDuplicateAnchor: true)
        let catalog = fixture.catalog()

        let scopedAlias = try fixture.resolve(
            #"from-note:"Anchor Alias""#,
            scope: .currentVault(fixture.primaryVault.id),
            catalog: catalog
        )
        #expect(Set(scopedAlias.matches.keys) == [fixture.targetID])

        let ambiguous = try fixture.resolve("from-note:Anchor", catalog: catalog)
        #expect(ambiguous.matches.isEmpty)
        #expect(ambiguous.diagnostic?.code == .ambiguousIdentity)

        let missing = try fixture.resolve("from-note:Missing", catalog: catalog)
        #expect(missing.matches.isEmpty)
        #expect(missing.diagnostic?.code == .notApplicable)

        let thisNote = try fixture.resolve(
            "from-note:Anchor",
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

    @Test("A Graph from another source manifest fails the complete link clause closed")
    func manifestMismatchFailsClosed() throws {
        let fixture = Fixture()
        let catalog = fixture.catalog(graphManifest: "graph-manifest")
        let ast = try #require(SearchQueryParser.parse("bounded-term from-note:Anchor").ast)

        let resolution = NoteLinkSearchResolver.resolve(
            ast: ast,
            scope: .triptych,
            catalog: catalog,
            searchGeneration: SearchGenerationID(
                triptychID: UUID(),
                sequence: 1,
                sourceManifestHash: "search-manifest"
            )
        )

        #expect(resolution.matches.isEmpty)
        #expect(resolution.diagnostic?.code == .notApplicable)
        #expect(resolution.diagnostic?.message ==
            "Direct link Search is unavailable until Graph and Note Search share one complete source manifest.")
    }
}

private extension NoteLinkSearchResolverTests {
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
        let anchorStableID = UUID(uuidString: "d5f95945-59fb-4f95-a286-95633c44ad64")!

        var anchorID: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: primaryVault.id, relativePath: "Anchor.md")
        }
        var targetID: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: primaryVault.id, relativePath: "Target.md")
        }
        var rivalID: VaultQualifiedNoteID {
            VaultQualifiedNoteID(vaultID: primaryVault.id, relativePath: "Rival.md")
        }

        init(includeDuplicateAnchor: Bool = false) {
            self.includeDuplicateAnchor = includeDuplicateAnchor
        }

        func catalog(graphManifest: String? = nil) -> WorkspaceCatalogSnapshot {
            let primaryDocuments = [
                NoteDocument(
                    relativePath: anchorID.relativePath,
                    rawContent: "# Anchor\n\n[[Target]]{{A **multiline** reason.\n\n- Evidence}}\n"
                ),
                NoteDocument(relativePath: targetID.relativePath, rawContent: "# Target\n"),
                NoteDocument(
                    relativePath: rivalID.relativePath,
                    rawContent: "# Rival\n\n[[Anchor]]{{A challenge.}}\n"
                ),
            ]
            var documentsByVault = [primaryVault.id: primaryDocuments]
            let duplicate = NoteDocument(
                relativePath: "Anchor.md",
                rawContent: "# A distinct first-level heading\n"
            )
            if includeDuplicateAnchor { documentsByVault[secondaryVault.id] = [duplicate] }

            var semantic: [VaultQualifiedNoteID: MarkdownSemanticDocument] = [:]
            for (vaultID, documents) in documentsByVault {
                for document in documents {
                    semantic[VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath)] =
                        MarkdownSemanticDocument(parsing: document)
                }
            }
            let graph = LinkGraphBuilder.build(
                generation: 1,
                catalog: documentsByVault.flatMap { vaultID, documents in
                    documents.map { document in
                        let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath)
                        return LinkCatalogNote(
                            vaultID: vaultID,
                            document: document,
                            profile: .topicMarkdown,
                            semantic: semantic[id]
                        )
                    }
                },
                documents: semantic,
                resolutionScope: .workspace,
                sourceManifestHash: graphManifest ?? manifest
            )
            let anchorMetadata = NoteMetadataRecord(
                noteID: anchorStableID,
                fields: ["aliases": .array([.string("Anchor Alias")])]
            )
            return WorkspaceCatalogBuilder.build(
                vaults: includeDuplicateAnchor ? [primaryVault, secondaryVault] : [primaryVault],
                documents: documentsByVault,
                graph: graph,
                stableNoteIDs: [anchorID: anchorStableID],
                noteMetadataByID: [
                    anchorStableID: NoteMetadataSnapshot(
                        record: anchorMetadata,
                        revision: DocumentFingerprint(content: "anchor metadata")
                    ),
                ]
            )
        }

        func resolve(
            _ query: String,
            scope: SearchExecutionScope = .triptych,
            catalog: WorkspaceCatalogSnapshot
        ) throws -> NoteLinkSearchResolver.Resolution {
            let parsed = SearchQueryParser.parse(query)
            #expect(parsed.diagnostics.isEmpty)
            return NoteLinkSearchResolver.resolve(
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
