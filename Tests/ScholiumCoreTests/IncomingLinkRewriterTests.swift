import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Source-located incoming link rewrites")
struct IncomingLinkRewriterTests {
    @Test("A confirmed move rewrites only links resolved to the moved note")
    func rewritesResolvedIncomingLinks() {
        let vaultID = UUID()
        let target = NoteDocument(relativePath: "Topics/B.md", rawContent: "# B\n")
        let source = NoteDocument(
            relativePath: "A.md",
            rawContent: """
            [[Topics/B|alias]] +[[Topics/B#Claim]] [B](Topics/B.md#Claim)
            `[[Topics/B]]`
            """
        )

        let plan = standalonePlan(
            vaultID: vaultID,
            documents: [source, target],
            moving: "Topics/B.md",
            to: "Topics/Renamed B.md"
        )

        #expect(plan.count == 1)
        #expect(plan[0].rewrittenOccurrences == 3)
        #expect(plan[0].updatedSource.contains("[[Topics/Renamed B|alias]]"))
        #expect(plan[0].updatedSource.contains("+[[Topics/Renamed B#Claim]]"))
        #expect(plan[0].updatedSource.contains("[B](Topics/Renamed B.md#Claim)"))
        #expect(plan[0].updatedSource.contains("`[[Topics/B]]`"))
    }

    @Test("Ambiguous stems are never rewritten")
    func leavesAmbiguousLinksAlone() {
        let vaultID = UUID()
        let source = NoteDocument(relativePath: "A.md", rawContent: "[[B]]\n")
        let first = NoteDocument(relativePath: "One/B.md", rawContent: "# First\n")
        let second = NoteDocument(relativePath: "Two/B.md", rawContent: "# Second\n")

        let plan = standalonePlan(
            vaultID: vaultID,
            documents: [source, first, second],
            moving: "One/B.md",
            to: "One/C.md"
        )

        #expect(plan.isEmpty)
    }

    @Test("A workspace graph rewrites resolved links from another vault")
    func rewritesCrossVaultIncomingLinks() {
        let analysisVault = UUID()
        let topicVault = UUID()
        let analysis = NoteDocument(
            relativePath: "Sources/Essai.md",
            rawContent: "# Essai\n"
        )
        let topic = NoteDocument(
            relativePath: "Debates/Topic.md",
            rawContent: "See -[[Sources/Essai#Thèse|source]] and [paper](Sources/Essai.md#Th%C3%A8se).\n"
        )
        let documents = [
            VaultQualifiedNoteID(vaultID: analysisVault, relativePath: analysis.relativePath): analysis,
            VaultQualifiedNoteID(vaultID: topicVault, relativePath: topic.relativePath): topic,
        ]
        let graph = workspaceGraph(documents)
        let plan = IncomingLinkRewriter.plan(
            documents: documents,
            graph: graph,
            moving: VaultQualifiedNoteID(vaultID: analysisVault, relativePath: analysis.relativePath),
            to: VaultQualifiedNoteID(vaultID: analysisVault, relativePath: "Sources/Étude finale.md")
        )

        #expect(plan.rewrites.count == 1)
        #expect(plan.rewrites[0].source.vaultID == topicVault)
        #expect(plan.rewrites[0].updatedSource.contains("-[[Sources/Étude finale#Thèse|source]]"))
        #expect(plan.rewrites[0].updatedSource.contains("[paper](Sources/Étude finale.md#Th%C3%A8se)"))
    }

    @Test("Same relative paths in two remote vaults remain ambiguous and untouched")
    func samePathAcrossVaultsIsAmbiguous() {
        let sourceVault = UUID()
        let firstVault = UUID()
        let secondVault = UUID()
        let source = NoteDocument(relativePath: "A.md", rawContent: "[[Shared/B]]\n")
        let first = NoteDocument(relativePath: "Shared/B.md", rawContent: "first\n")
        let second = NoteDocument(relativePath: "Shared/B.md", rawContent: "second\n")
        let documents = [
            VaultQualifiedNoteID(vaultID: sourceVault, relativePath: source.relativePath): source,
            VaultQualifiedNoteID(vaultID: firstVault, relativePath: first.relativePath): first,
            VaultQualifiedNoteID(vaultID: secondVault, relativePath: second.relativePath): second,
        ]
        let plan = IncomingLinkRewriter.plan(
            documents: documents,
            graph: workspaceGraph(documents),
            moving: VaultQualifiedNoteID(vaultID: firstVault, relativePath: first.relativePath),
            to: VaultQualifiedNoteID(vaultID: firstVault, relativePath: "Shared/C.md")
        )

        #expect(plan.rewrites.isEmpty)
    }

    @Test("A stale graph cannot rewrite a link that is ambiguous in current documents")
    func staleGraphCannotAuthorizeRewrite() {
        let sourceVault = UUID()
        let firstVault = UUID()
        let secondVault = UUID()
        let source = NoteDocument(relativePath: "A.md", rawContent: "[[B]]\n")
        let first = NoteDocument(relativePath: "B.md", rawContent: "first\n")
        var documents = [
            VaultQualifiedNoteID(vaultID: sourceVault, relativePath: source.relativePath): source,
            VaultQualifiedNoteID(vaultID: firstVault, relativePath: first.relativePath): first,
        ]
        let staleGraph = workspaceGraph(documents)
        let second = NoteDocument(relativePath: "B.md", rawContent: "second\n")
        documents[VaultQualifiedNoteID(vaultID: secondVault, relativePath: second.relativePath)] = second

        let plan = IncomingLinkRewriter.plan(
            documents: documents,
            graph: staleGraph,
            moving: VaultQualifiedNoteID(vaultID: firstVault, relativePath: first.relativePath),
            to: VaultQualifiedNoteID(vaultID: firstVault, relativePath: "C.md")
        )

        #expect(plan.rewrites.isEmpty)
    }

    @Test("A move is blocked when the new path would retarget a cross-vault link")
    func destinationCollisionIsReported() {
        let analysisVault = UUID()
        let topicVault = UUID()
        let source = NoteDocument(relativePath: "Topic.md", rawContent: "[[Old/B]]\n")
        let moving = NoteDocument(relativePath: "Old/B.md", rawContent: "analysis\n")
        let collision = NoteDocument(relativePath: "New/C.md", rawContent: "topic collision\n")
        let documents = [
            VaultQualifiedNoteID(vaultID: topicVault, relativePath: source.relativePath): source,
            VaultQualifiedNoteID(vaultID: analysisVault, relativePath: moving.relativePath): moving,
            VaultQualifiedNoteID(vaultID: topicVault, relativePath: collision.relativePath): collision,
        ]
        let plan = IncomingLinkRewriter.plan(
            documents: documents,
            graph: workspaceGraph(documents),
            moving: VaultQualifiedNoteID(vaultID: analysisVault, relativePath: moving.relativePath),
            to: VaultQualifiedNoteID(vaultID: analysisVault, relativePath: collision.relativePath)
        )

        #expect(plan.rewrites.isEmpty)
        #expect(plan.blockedIncomingLinks.count == 1)
        #expect(plan.blockedIncomingLinks[0].source.vaultID == topicVault)
    }

    @Test("Exact BOM and CRLF bytes outside link targets are preserved")
    func preservesEnvelopeBytes() {
        let vaultID = UUID()
        let source = NoteDocument(
            relativePath: "A.md",
            rawContent: "\u{FEFF}---\r\ntitle: 'A' # keep\r\n---\r\n+[[B|别名]]\r\n"
        )
        let target = NoteDocument(relativePath: "B.md", rawContent: "B\r\n")
        let documents = [
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: source.relativePath): source,
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath): target,
        ]
        let plan = IncomingLinkRewriter.plan(
            documents: documents,
            graph: workspaceGraph(documents),
            moving: VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath),
            to: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "资料/乙.md")
        )

        #expect(plan.rewrites.first?.updatedSource == "\u{FEFF}---\r\ntitle: 'A' # keep\r\n---\r\n+[[资料/乙|别名]]\r\n")
    }

    @Test("A coherent snapshot plan matches complete graph re-derivation")
    func validatedSnapshotPlanMatchesCompletePlan() throws {
        let analysisVault = UUID()
        let topicVault = UUID()
        let source = NoteDocument(
            relativePath: "Debates/Topic.md",
            rawContent: "See +[[Sources/Essay#Claim|source]].\n"
        )
        let target = NoteDocument(
            relativePath: "Sources/Essay.md",
            rawContent: "# Claim\n"
        )
        let unrelated = NoteDocument(
            relativePath: "Unrelated.md",
            rawContent: "No links.\n"
        )
        let documents = [
            VaultQualifiedNoteID(vaultID: topicVault, relativePath: source.relativePath): source,
            VaultQualifiedNoteID(vaultID: analysisVault, relativePath: target.relativePath): target,
            VaultQualifiedNoteID(vaultID: topicVault, relativePath: unrelated.relativePath): unrelated,
        ]
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let catalog = documents.map { id, document in
            LinkCatalogNote(
                vaultID: id.vaultID,
                document: document,
                semantic: semantics[id]
            )
        }
        let graph = LinkGraphBuilder.build(
            generation: 19,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace,
            sourceManifestHash: sourceManifestHash(documents)
        )
        let moving = VaultQualifiedNoteID(
            vaultID: analysisVault,
            relativePath: target.relativePath
        )
        let destination = VaultQualifiedNoteID(
            vaultID: analysisVault,
            relativePath: "Sources/Renamed Essay.md"
        )

        let complete = IncomingLinkRewriter.plan(
            documents: documents,
            graph: graph,
            moving: moving,
            to: destination
        )
        let snapshot = try #require(
            IncomingLinkRewriter.planUsingValidatedSnapshot(
                documents: documents,
                catalog: catalog,
                graph: graph,
                moving: moving,
                to: destination
            )
        )

        #expect(snapshot == complete)
    }

    @Test("A coherent Folder snapshot plan matches complete graph re-derivation")
    func validatedFolderSnapshotPlanMatchesCompletePlan() throws {
        let vaultID = UUID()
        let sourceFolder = try VaultRelativeFolderPath("Source")
        let destinationFolder = try VaultRelativeFolderPath("Target/Source")
        let first = NoteDocument(
            relativePath: "Source/First.md",
            rawContent: "# First\n\nSee [[Source/Second]].\n"
        )
        let second = NoteDocument(
            relativePath: "Source/Second.md",
            rawContent: "# Second\n"
        )
        let reference = NoteDocument(
            relativePath: "Reference.md",
            rawContent: "See [[Source/First]].\n"
        )
        let documents = Dictionary(uniqueKeysWithValues: [first, second, reference].map {
            document in
            (
                VaultQualifiedNoteID(
                    vaultID: vaultID,
                    relativePath: document.relativePath
                ),
                document
            )
        })
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let catalog = documents.map { id, document in
            LinkCatalogNote(
                vaultID: id.vaultID,
                document: document,
                semantic: semantics[id]
            )
        }
        let graph = LinkGraphBuilder.build(
            generation: 23,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace,
            sourceManifestHash: sourceManifestHash(documents)
        )
        let moves = [first, second].map { document in
            let source = VaultQualifiedNoteID(
                vaultID: vaultID,
                relativePath: document.relativePath
            )
            return FolderNoteMovePlan(
                stableNoteID: UUID(),
                source: source,
                destination: VaultQualifiedNoteID(
                    vaultID: vaultID,
                    relativePath: "Target/" + document.relativePath
                ),
                expectedRevision: document.fingerprint
            )
        }

        let complete = IncomingLinkRewriter.folderPlan(
            documents: documents,
            graph: graph,
            vaultID: vaultID,
            sourceFolder: sourceFolder,
            destinationFolder: destinationFolder,
            noteMoves: moves
        )
        let snapshot = try #require(
            IncomingLinkRewriter.folderPlanUsingValidatedSnapshot(
                documents: documents,
                catalog: catalog,
                graph: graph,
                vaultID: vaultID,
                sourceFolder: sourceFolder,
                destinationFolder: destinationFolder,
                noteMoves: moves
            )
        )

        #expect(snapshot == complete)
        #expect(snapshot.rewrites.count == 2)
    }

    @Test("An incomplete snapshot catalog cannot authorize a fast move plan")
    func incompleteSnapshotPlanFailsClosed() {
        let vaultID = UUID()
        let source = NoteDocument(relativePath: "A.md", rawContent: "[[B]]\n")
        let target = NoteDocument(relativePath: "B.md", rawContent: "B\n")
        let documents = [
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: source.relativePath): source,
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath): target,
        ]
        let graph = workspaceGraph(documents)
        let incompleteCatalog = [LinkCatalogNote(
            vaultID: vaultID,
            document: source
        )]

        #expect(IncomingLinkRewriter.planUsingValidatedSnapshot(
            documents: documents,
            catalog: incompleteCatalog,
            graph: graph,
            moving: VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath),
            to: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Moved/B.md")
        ) == nil)
    }

    @Test("A graph from another source manifest cannot authorize a fast move plan")
    func staleSnapshotGraphFailsClosed() {
        let vaultID = UUID()
        let source = NoteDocument(relativePath: "A.md", rawContent: "[[B]]\n")
        let target = NoteDocument(relativePath: "B.md", rawContent: "B\n")
        let documents = [
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: source.relativePath): source,
            VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath): target,
        ]
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let catalog = documents.map { id, document in
            LinkCatalogNote(
                vaultID: id.vaultID,
                document: document,
                semantic: semantics[id]
            )
        }
        let staleGraph = LinkGraphBuilder.build(
            generation: 8,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace,
            sourceManifestHash: "not-the-current-source-manifest"
        )

        #expect(IncomingLinkRewriter.planUsingValidatedSnapshot(
            documents: documents,
            catalog: catalog,
            graph: staleGraph,
            moving: VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath),
            to: VaultQualifiedNoteID(vaultID: vaultID, relativePath: "Moved/B.md")
        ) == nil)
    }

    private func workspaceGraph(
        _ documents: [VaultQualifiedNoteID: NoteDocument]
    ) -> GraphSnapshot {
        let semantics = documents.mapValues(MarkdownSemanticDocument.init(parsing:))
        let catalog = documents.map { id, document in
            LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: semantics[id])
        }
        return LinkGraphBuilder.build(
            generation: 7,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .workspace,
            sourceManifestHash: sourceManifestHash(documents)
        )
    }

    private func sourceManifestHash(
        _ documents: [VaultQualifiedNoteID: NoteDocument]
    ) -> String {
        SearchSourceManifest.hash(documents.map { id, document in
            SearchSourceManifestEntry(
                vaultID: id.vaultID,
                relativePath: id.relativePath,
                fingerprint: document.fingerprint
            )
        })
    }

    private func standalonePlan(
        vaultID: UUID,
        documents: [NoteDocument],
        moving oldRelativePath: String,
        to newRelativePath: String
    ) -> [IncomingLinkRewrite] {
        let qualified = Dictionary(uniqueKeysWithValues: documents.map { document in
            (VaultQualifiedNoteID(vaultID: vaultID, relativePath: document.relativePath), document)
        })
        let semantics = qualified.mapValues(MarkdownSemanticDocument.init(parsing:))
        let catalog = qualified.map { id, document in
            LinkCatalogNote(vaultID: id.vaultID, document: document, semantic: semantics[id])
        }
        let graph = LinkGraphBuilder.build(
            generation: 0,
            catalog: catalog,
            documents: semantics,
            resolutionScope: .sourceVault
        )
        return IncomingLinkRewriter.plan(
            documents: qualified,
            graph: graph,
            moving: VaultQualifiedNoteID(vaultID: vaultID, relativePath: oldRelativePath),
            to: VaultQualifiedNoteID(vaultID: vaultID, relativePath: newRelativePath)
        ).rewrites
    }
}
