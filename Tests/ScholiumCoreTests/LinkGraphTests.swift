import Foundation
import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Deterministic shared link graph")
struct LinkGraphTests {
    @Test("Workspace resolution follows a unique cross-vault link")
    func uniqueCrossVaultResolution() {
        let analysisVault = UUID()
        let topicVault = UUID()
        let analysis = NoteDocument(
            relativePath: "Papers/Foot.md",
            rawContent: "# The Problem of Abortion\n\nAnalysis"
        )
        let topic = NoteDocument(
            relativePath: "Abortion.md",
            rawContent: "Use +[[The Problem of Abortion]]."
        )
        let analysisID = VaultQualifiedNoteID(vaultID: analysisVault, relativePath: analysis.relativePath)
        let topicID = VaultQualifiedNoteID(vaultID: topicVault, relativePath: topic.relativePath)
        let documents = [
            analysisID: MarkdownSemanticDocument(parsing: analysis),
            topicID: MarkdownSemanticDocument(parsing: topic),
        ]
        let catalog = [
            LinkCatalogNote(
                vaultID: analysisVault,
                document: analysis,
                profile: .analysis,
                semantic: documents[analysisID]
            ),
            LinkCatalogNote(vaultID: topicVault, document: topic, semantic: documents[topicID]),
        ]

        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: catalog,
            documents: documents,
            resolutionScope: .workspace
        )

        #expect(graph.outgoing[topicID]?.first?.destination?.note == analysisID)
        #expect(graph.incoming[analysisID]?.first?.source == topicID)
        #expect(!graph.diagnostics.contains { $0.source == topicID })
        let support = graph.relationships.first { $0.predicate == .supports }
        #expect(support?.subjectNote == topicID)
        #expect(support?.objectNote == analysisID)
    }

    @Test("Unclosed comments never publish hidden links into GraphSnapshot")
    func unclosedCommentGraphBoundary() {
        let vaultID = UUID()
        let source = NoteDocument(
            relativePath: "Source.md",
            rawContent: "Visible.\n%%\n+[[Hidden Target]]"
        )
        let target = NoteDocument(relativePath: "Hidden Target.md", rawContent: "# Hidden Target")
        let sourceID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: source.relativePath)
        let targetID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath)
        let documents = [
            sourceID: MarkdownSemanticDocument(parsing: source),
            targetID: MarkdownSemanticDocument(parsing: target),
        ]
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: [
                LinkCatalogNote(vaultID: vaultID, document: source, semantic: documents[sourceID]),
                LinkCatalogNote(vaultID: vaultID, document: target, semantic: documents[targetID]),
            ],
            documents: documents
        )

        #expect(graph.outgoing[sourceID, default: []].isEmpty)
        #expect(graph.incoming[targetID, default: []].isEmpty)
        #expect(graph.relationships.isEmpty)
    }

    @Test("Relationship endpoints remain vault-qualified when relative paths collide")
    func crossVaultRelationshipIdentity() {
        let analysisVault = UUID()
        let worksVault = UUID()
        let analysis = NoteDocument(
            relativePath: "Shared.md",
            rawContent: "# Analysis Target"
        )
        let work = NoteDocument(
            relativePath: "Shared.md",
            rawContent: "+[[Analysis Target]]"
        )
        let analysisID = VaultQualifiedNoteID(vaultID: analysisVault, relativePath: analysis.relativePath)
        let workID = VaultQualifiedNoteID(vaultID: worksVault, relativePath: work.relativePath)
        let documents = [
            analysisID: MarkdownSemanticDocument(parsing: analysis),
            workID: MarkdownSemanticDocument(parsing: work),
        ]
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: [
                LinkCatalogNote(
                    vaultID: analysisVault,
                    document: analysis,
                    profile: .analysis,
                    semantic: documents[analysisID]
                ),
                LinkCatalogNote(vaultID: worksVault, document: work, semantic: documents[workID]),
            ],
            documents: documents,
            resolutionScope: .workspace
        )

        let edge = graph.relationships.first { $0.predicate == .supports }
        #expect(edge?.subjectPath == "Shared.md")
        #expect(edge?.objectPath == "Shared.md")
        #expect(edge?.subjectNote == workID)
        #expect(edge?.objectNote == analysisID)
        #expect(edge?.subjectNote != edge?.objectNote)
    }

    @Test("Workspace resolution never guesses between duplicate cross-vault stems")
    func ambiguousCrossVaultResolution() {
        let sourceVault = UUID()
        let firstVault = UUID()
        let secondVault = UUID()
        let source = NoteDocument(relativePath: "Source.md", rawContent: "See [[Shared]].")
        let first = NoteDocument(relativePath: "One/Shared.md", rawContent: "First")
        let second = NoteDocument(relativePath: "Two/Shared.md", rawContent: "Second")
        let sourceID = VaultQualifiedNoteID(vaultID: sourceVault, relativePath: source.relativePath)
        let firstID = VaultQualifiedNoteID(vaultID: firstVault, relativePath: first.relativePath)
        let secondID = VaultQualifiedNoteID(vaultID: secondVault, relativePath: second.relativePath)
        let documents = [
            sourceID: MarkdownSemanticDocument(parsing: source),
            firstID: MarkdownSemanticDocument(parsing: first),
            secondID: MarkdownSemanticDocument(parsing: second),
        ]
        let catalog = [
            LinkCatalogNote(vaultID: sourceVault, document: source, semantic: documents[sourceID]),
            LinkCatalogNote(vaultID: firstVault, document: first, semantic: documents[firstID]),
            LinkCatalogNote(vaultID: secondVault, document: second, semantic: documents[secondID]),
        ]

        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: catalog,
            documents: documents,
            resolutionScope: .workspace
        )

        #expect(graph.outgoing[sourceID]?.first?.destination == nil)
        #expect(graph.diagnostics.contains { $0.source == sourceID && $0.code == .ambiguous })
    }

    @Test("A same-vault match wins over a cross-vault match")
    func sameVaultResolutionPriority() {
        let sourceVault = UUID()
        let otherVault = UUID()
        let source = NoteDocument(relativePath: "Folder/Source.md", rawContent: "See [[Target]].")
        let local = NoteDocument(relativePath: "Folder/Target.md", rawContent: "Local")
        let remote = NoteDocument(relativePath: "Target.md", rawContent: "Remote")
        let sourceID = VaultQualifiedNoteID(vaultID: sourceVault, relativePath: source.relativePath)
        let localID = VaultQualifiedNoteID(vaultID: sourceVault, relativePath: local.relativePath)
        let remoteID = VaultQualifiedNoteID(vaultID: otherVault, relativePath: remote.relativePath)
        let documents = [
            sourceID: MarkdownSemanticDocument(parsing: source),
            localID: MarkdownSemanticDocument(parsing: local),
            remoteID: MarkdownSemanticDocument(parsing: remote),
        ]
        let catalog = [
            LinkCatalogNote(vaultID: sourceVault, document: source, semantic: documents[sourceID]),
            LinkCatalogNote(vaultID: sourceVault, document: local, semantic: documents[localID]),
            LinkCatalogNote(vaultID: otherVault, document: remote, semantic: documents[remoteID]),
        ]

        let resolution = LinkGraphBuilder.resolve(
            "Target",
            from: sourceID,
            catalog: catalog,
            scope: .workspace
        )
        #expect(resolution == .resolved(localID))
    }

    @Test("Indexed graph builds preserve every link-resolution priority")
    func indexedBuildPreservesResolutionPriority() throws {
        let sourceVault = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let firstRemoteVault = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let secondRemoteVault = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let source = NoteDocument(
            relativePath: "Folder/Source.md",
            rawContent: """
            # Local Section

            [[#Local Section]]
            [[Folder/Exact]]
            [[Relative]]
            [[FolderOnly]]
            [[VaultOnly]]
            [[Local Alias]]
            [[Remote/Exact]]
            [[Remote/UniqueExact]]
            [[RemoteStem]]
            [[Remote Alias]]
            [[Collision]]
            [[Missing]]
            """
        )
        let sourceID = VaultQualifiedNoteID(
            vaultID: sourceVault,
            relativePath: source.relativePath
        )
        let sourceSemantic = MarkdownSemanticDocument(parsing: source)

        func note(
            _ vaultID: UUID,
            _ path: String,
            title: String? = nil,
            aliases: [String] = []
        ) -> LinkCatalogNote {
            LinkCatalogNote(
                id: VaultQualifiedNoteID(vaultID: vaultID, relativePath: path),
                title: title,
                aliases: aliases
            )
        }

        let exactRoot = note(sourceVault, "Folder/Exact.md")
        let exactRelative = note(sourceVault, "Folder/Relative.md")
        let sameFolderStem = note(sourceVault, "Folder/FolderOnly.md")
        let competingVaultStem = note(sourceVault, "Elsewhere/FolderOnly.md")
        let vaultWideStem = note(sourceVault, "Elsewhere/VaultOnly.md")
        let localDeclared = note(
            sourceVault,
            "Elsewhere/LocalDeclared.md",
            title: "Local Alias",
            aliases: ["Local Alias"]
        )
        let remoteExact = note(firstRemoteVault, "Remote/UniqueExact.md")
        let competingRemoteDeclared = note(
            secondRemoteVault,
            "Elsewhere/DeclaredExact.md",
            aliases: ["UniqueExact"]
        )
        let remoteStem = note(firstRemoteVault, "Elsewhere/RemoteStem.md")
        let remoteDeclared = note(
            firstRemoteVault,
            "Elsewhere/RemoteDeclared.md",
            aliases: ["Remote Alias"]
        )
        let firstCollision = note(firstRemoteVault, "One/Collision.md")
        let secondCollision = note(secondRemoteVault, "Two/Collision.md")
        let catalog = [
            LinkCatalogNote(vaultID: sourceVault, document: source, semantic: sourceSemantic),
            exactRoot,
            exactRelative,
            sameFolderStem,
            competingVaultStem,
            vaultWideStem,
            localDeclared,
            remoteExact,
            competingRemoteDeclared,
            remoteStem,
            remoteDeclared,
            firstCollision,
            secondCollision,
        ]

        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: catalog,
            documents: [sourceID: sourceSemantic],
            resolutionScope: .workspace
        )
        let outgoing = try #require(graph.outgoing[sourceID])
        let resolutions = Dictionary(
            uniqueKeysWithValues: outgoing.map {
                ($0.occurrence.target, $0.occurrence.resolution)
            }
        )

        #expect(resolutions[""] == .resolved(sourceID))
        #expect(resolutions["Folder/Exact"] == .resolved(exactRoot.id))
        #expect(resolutions["Relative"] == .resolved(exactRelative.id))
        #expect(resolutions["FolderOnly"] == .resolved(sameFolderStem.id))
        #expect(resolutions["VaultOnly"] == .resolved(vaultWideStem.id))
        #expect(resolutions["Local Alias"] == .resolved(localDeclared.id))
        #expect(resolutions["Remote/Exact"] == .resolved(exactRoot.id))
        #expect(resolutions["Remote/UniqueExact"] == .resolved(remoteExact.id))
        #expect(resolutions["RemoteStem"] == .resolved(remoteStem.id))
        #expect(resolutions["Remote Alias"] == .resolved(remoteDeclared.id))
        #expect(
            resolutions["Collision"]
                == .ambiguous([firstCollision.id, secondCollision.id].sorted())
        )
        #expect(resolutions["Missing"] == .broken("Missing"))
        #expect(graph.diagnostics.filter { $0.code == .ambiguous }.count == 1)
        #expect(graph.diagnostics.filter { $0.code == .broken }.count == 1)
    }

    @Test("Graph build handles the 1,560-note and 46,800-link activation workload")
    func activationScaleWorkload() {
        let vaultIDs = [
            UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
            UUID(uuidString: "60000000-0000-0000-0000-000000000006")!,
        ]
        let notesPerVault = 520
        let linksPerNote = 30
        var catalog: [LinkCatalogNote] = []
        var documents: [VaultQualifiedNoteID: MarkdownSemanticDocument] = [:]
        catalog.reserveCapacity(vaultIDs.count * notesPerVault)
        documents.reserveCapacity(vaultIDs.count * notesPerVault)

        for (vaultIndex, vaultID) in vaultIDs.enumerated() {
            for noteIndex in 0..<notesPerVault {
                let path = "Notes/Note-\(noteIndex).md"
                let links = (1...linksPerNote).map { offset in
                    let target = (noteIndex + offset) % notesPerVault
                    return "[[Notes/Note-\(target)]]"
                }.joined(separator: " ")
                let document = NoteDocument(
                    relativePath: path,
                    rawContent: "# Fixture \(vaultIndex)-\(noteIndex)\n\n\(links)\n"
                )
                let id = VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)
                let semantic = MarkdownSemanticDocument(parsing: document)
                catalog.append(LinkCatalogNote(
                    vaultID: vaultID,
                    document: document,
                    semantic: semantic
                ))
                documents[id] = semantic
            }
        }

        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: catalog,
            documents: documents,
            resolutionScope: .workspace
        )
        let outgoingCount = graph.outgoing.values.reduce(0) { $0 + $1.count }
        let incomingCount = graph.incoming.values.reduce(0) { $0 + $1.count }

        #expect(catalog.count == 1_560)
        #expect(documents.count == 1_560)
        #expect(outgoingCount == 46_800)
        #expect(incomingCount == 46_800)
        #expect(graph.outgoing.count == 1_560)
        #expect(graph.incoming.count == 1_560)
        #expect(graph.diagnostics.isEmpty)
        #expect(graph.relationships.count == 46_800)
    }

    @Test("Retired relation arrows never create explicit evidence")
    func v4ArrowDirection() {
        let vaultID = UUID()
        let claim = NoteDocument(relativePath: "02 Claims/Project Claims/Claim.md", rawContent: "# Claim\n\n## Relations\n- `supports` -> [[Target]]\n")
        let target = NoteDocument(relativePath: "02 Claims/Project Claims/Target.md", rawContent: "# Target\n")
        let claimID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: claim.relativePath)
        let targetID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: target.relativePath)
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: [LinkCatalogNote(vaultID: vaultID, document: claim), LinkCatalogNote(vaultID: vaultID, document: target)],
            documents: [claimID: MarkdownSemanticDocument(parsing: claim), targetID: MarkdownSemanticDocument(parsing: target)]
        )
        #expect(!graph.relationships.contains { $0.predicate == .supports || $0.predicate == .incompatibleWith })
        #expect(graph.relationships.contains {
            $0.predicate == .connected
                && !$0.isExplicit
                && Set([$0.subjectPath, $0.objectPath]) == Set([claim.relativePath, target.relativePath])
        })
    }
    @Test("Retired reified relation blocks contribute only neutral wikilinks")
    func reifiedDirection() {
        let vaultID = UUID()
        let record = NoteDocument(relativePath: "04 Positions and Relations/Complex Relation Records/Pressure.md", rawContent: "# Pressure\n\n## Relation\n- Subject: [[Objection]]\n- Predicate: `pressures`\n- Object: [[Claim]]\n")
        let objection = NoteDocument(relativePath: "03 Inferences/Objection.md", rawContent: "# Objection\n")
        let claim = NoteDocument(relativePath: "02 Claims/Project Claims/Claim.md", rawContent: "# Claim\n")
        let docs = [record, objection, claim]
        let ids = docs.map { VaultQualifiedNoteID(vaultID: vaultID, relativePath: $0.relativePath) }
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: docs.map { LinkCatalogNote(vaultID: vaultID, document: $0) },
            documents: Dictionary(uniqueKeysWithValues: zip(ids, docs.map { MarkdownSemanticDocument(parsing: $0) }))
        )
        #expect(!graph.relationships.contains { $0.predicate == .pressures })
        #expect(graph.relationships.contains {
            $0.predicate == .connected
                && [$0.subjectPath, $0.objectPath].contains(record.relativePath)
                && [$0.subjectPath, $0.objectPath].contains(objection.relativePath)
        })
    }
    @Test("Embeds remain raw links without becoming semantic relationships")
    func embedIsNotRelationship() {
        let source = document("Output/Draft.md", "![[Assets/Figure.png]]")
        let figure = document("Assets/Figure.png.md", "binary fixture placeholder")
        let documents = [source, figure]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { (id($0.relativePath), MarkdownSemanticDocument(parsing: $0)) })
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0, semantic: semantics[id($0.relativePath)]!) },
            documents: semantics
        )
        #expect(snapshot.outgoing[id(source.relativePath)]?.count == 1)
        #expect(snapshot.outgoing[id(source.relativePath)]?.first?.occurrence.syntax == .embed)
        #expect(snapshot.relationships.isEmpty)
    }
    @Test("Retired typed arrows do not run endpoint rules")
    func v4EndpointDiagnostic() {
        let vaultID = UUID()
        let question = NoteDocument(relativePath: "01 Questions/Q.md", rawContent: "# Q\n\n## Relations\n- `evidence_for` -> [[Claim]]\n")
        let claim = NoteDocument(relativePath: "02 Claims/Project Claims/Claim.md", rawContent: "# Claim\n")
        let qID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: question.relativePath)
        let cID = VaultQualifiedNoteID(vaultID: vaultID, relativePath: claim.relativePath)
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: [LinkCatalogNote(vaultID: vaultID, document: question), LinkCatalogNote(vaultID: vaultID, document: claim)],
            documents: [qID: MarkdownSemanticDocument(parsing: question), cID: MarkdownSemanticDocument(parsing: claim)]
        )
        #expect(!graph.diagnostics.contains { $0.code == .invalidRelationshipEndpoint })
        #expect(graph.relationships.contains { $0.predicate == .connected && !$0.isExplicit })
    }
    private let vaultID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("Resolution order never fuzzy-selects duplicate stems")
    func deterministicResolution() {
        let catalog = [
            LinkCatalogNote(id: id("Topics/Agency.md"), title: "Agency"),
            LinkCatalogNote(id: id("Papers/Agency.md"), title: "A Different Agency"),
            LinkCatalogNote(id: id("Topics/Control.md"), title: "Control", aliases: ["Guidance Control"])
        ]

        #expect(LinkGraphBuilder.resolve("Agency", from: id("Topics/Source.md"), catalog: catalog) == .resolved(id("Topics/Agency.md")))
        #expect(LinkGraphBuilder.resolve("Agency", from: id("Output/Draft.md"), catalog: catalog) == .ambiguous([id("Papers/Agency.md"), id("Topics/Agency.md")]))
        #expect(LinkGraphBuilder.resolve("Guidance Control", from: id("Output/Draft.md"), catalog: catalog) == .resolved(id("Topics/Control.md")))
        #expect(LinkGraphBuilder.resolve("Agenc", from: id("Output/Draft.md"), catalog: catalog) == .broken("Agenc"))
    }

    @Test("Topic aliases come from managed Metadata and never from unknown YAML")
    func aliasesRespectMetadataAuthority() throws {
        let source = document(
            "Output/Draft.md",
            "[[Managed Alias]] [[YAML Alias]]"
        )
        let topic = document(
            "Topics/Control.md",
            "---\naliases: [YAML Alias]\n---\n# Control\n"
        )
        let topicID = id(topic.relativePath)
        let record = NoteMetadataRecord(
            noteID: UUID(),
            fields: ["aliases": .array([.string("Managed Alias")])]
        )
        let metadata = NoteMetadataSnapshot(
            record: record,
            revision: DocumentFingerprint(data: try record.encodedPortableData())
        )
        let semantics = [
            id(source.relativePath): MarkdownSemanticDocument(parsing: source),
            topicID: MarkdownSemanticDocument(parsing: topic),
        ]
        let graph = LinkGraphBuilder.build(
            generation: 1,
            catalog: [
                LinkCatalogNote(vaultID: vaultID, document: source),
                LinkCatalogNote(
                    vaultID: vaultID,
                    document: topic,
                    profile: .topicMarkdown,
                    metadata: metadata
                ),
            ],
            documents: semantics
        )
        let resolutions = graph.outgoing[id(source.relativePath), default: []]
            .map(\.occurrence.resolution)

        #expect(resolutions.contains(.resolved(topicID)))
        #expect(resolutions.contains(.broken("YAML Alias")))
    }

    @Test("Headings and blocks resolve to exact full-file source spans")
    func destinations() {
        let source = document("Output/Draft.md", "See [[Topics/Control#Argument]] and [[Topics/Control#^core]].")
        let target = document("Topics/Control.md", """
        ---
        title: Control
        aliases: [Guidance Control]
        ---
        # Argument

        The central claim. ^core
        """)
        let sourceSemantic = MarkdownSemanticDocument(parsing: source)
        let targetSemantic = MarkdownSemanticDocument(parsing: target)
        let snapshot = LinkGraphBuilder.build(
            generation: 7,
            catalog: [
                LinkCatalogNote(vaultID: vaultID, document: source, semantic: sourceSemantic),
                LinkCatalogNote(vaultID: vaultID, document: target, semantic: targetSemantic)
            ],
            documents: [id(source.relativePath): sourceSemantic, id(target.relativePath): targetSemantic]
        )

        let sourceEdges: [LinkGraphEdge] = snapshot.outgoing[id(source.relativePath)] ?? []
        let destinations: [LinkDestination] = sourceEdges.compactMap { $0.destination }
        #expect(destinations.count == 2)
        let hasHeading = destinations.contains { destination in
            destination.kind == LinkDestinationKind.heading && destination.span?.start.line == 5
        }
        let hasBlock = destinations.contains { destination in
            destination.kind == LinkDestinationKind.block && destination.span?.start.line == 7
        }
        #expect(hasHeading)
        #expect(hasBlock)
        #expect(snapshot.diagnostics.isEmpty)
    }

    @Test("Fragment-only links resolve inside the containing note")
    func sameNoteFragment() {
        let note = document(
            "Topics/Control.md",
            "# Overview\n\nSee [the argument](#The%20Argument) and [[#The Argument]].\n\n## The Argument\n\nClaim.\n"
        )
        let noteID = id(note.relativePath)
        let semantic = MarkdownSemanticDocument(parsing: note)
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: [LinkCatalogNote(vaultID: vaultID, document: note, semantic: semantic)],
            documents: [noteID: semantic]
        )

        let destinations = snapshot.outgoing[noteID, default: []].compactMap(\.destination)
        #expect(destinations.count == 2)
        #expect(destinations.allSatisfy {
            $0.note == noteID
                && $0.kind == .heading
                && $0.span?.start.line == 5
        })
        #expect(snapshot.diagnostics.isEmpty)
    }

    @Test("Legacy typed aliases and untyped links remain neutral graph connections")
    func relationshipSemantics() {
        let source = document(
            "Output/X.md",
            "[[Papers/B|:supports]] [[Papers/C|old label:incompatible_with]] [[Topics/T]]"
        )
        let paper = document("Papers/B.md", "Paper")
        let incompatible = document("Papers/C.md", "Paper")
        let topic = document("Topics/T.md", "Topic")
        let documents = [source, paper, incompatible, topic]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { (id($0.relativePath), MarkdownSemanticDocument(parsing: $0)) })
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0, semantic: semantics[id($0.relativePath)]!) },
            documents: semantics
        )

        #expect(!snapshot.relationships.contains {
            $0.predicate == .supports || $0.predicate == .incompatibleWith
        })
        #expect(snapshot.relationships.count == 3)
        #expect(snapshot.relationships.allSatisfy {
            $0.predicate == .connected && !$0.isExplicit && !$0.isDirectional
        })
        #expect(semantics[id(source.relativePath)]?.diagnostics.filter {
            $0.code == .noncanonicalRelationshipSyntax
        }.count == 2)
    }

    @Test("The four canonical link forms preserve neutral, support, opposition, and incompatibility semantics")
    func canonicalVectorDirections() {
        let a = document("Claims/A.md", "[[Claims/B]] +[[Claims/C]] -[[Claims/D]] ?[[Claims/E]]")
        let b = document("Claims/B.md", "")
        let c = document("Claims/C.md", "")
        let d = document("Claims/D.md", "")
        let e = document("Claims/E.md", "")
        let documents = [a, b, c, d, e]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map {
            (id($0.relativePath), MarkdownSemanticDocument(parsing: $0))
        })
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map {
                LinkCatalogNote(vaultID: vaultID, document: $0, semantic: semantics[id($0.relativePath)]!)
            },
            documents: semantics
        )

        #expect(snapshot.relationships.count == 4)
        #expect(snapshot.relationships.contains {
            $0.predicate == .connected
                && !$0.isExplicit
                && !$0.isDirectional
                && Set([$0.subjectPath, $0.objectPath]) == Set(["Claims/A.md", "Claims/B.md"])
        })
        #expect(snapshot.relationships.contains {
            $0.predicate == .supports
                && $0.isExplicit
                && $0.isDirectional
                && $0.subjectPath == "Claims/A.md"
                && $0.objectPath == "Claims/C.md"
        })
        #expect(snapshot.relationships.contains {
            $0.predicate == .opposes
                && $0.isExplicit
                && $0.isDirectional
                && $0.subjectPath == "Claims/A.md"
                && $0.objectPath == "Claims/D.md"
        })
        #expect(snapshot.relationships.contains {
            $0.predicate == .incompatibleWith
                && $0.isExplicit
                && !$0.isDirectional
                && Set([$0.subjectPath, $0.objectPath]) == Set(["Claims/A.md", "Claims/E.md"])
        })
    }

    @Test("Repeated vector support normalizes duplicate authoring")
    func vectorSupportNormalization() {
        let a = document("Claims/A.md", "+[[Claims/B]] +[[Claims/B]]")
        let b = document("Claims/B.md", "")
        let documents = [a, b]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { (id($0.relativePath), MarkdownSemanticDocument(parsing: $0)) })
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0, semantic: semantics[id($0.relativePath)]!) },
            documents: semantics
        )

        let support = snapshot.relationships.filter { $0.predicate == .supports }
        #expect(support.count == 1)
        #expect(support[0].subjectPath == "Claims/A.md")
        #expect(support[0].objectPath == "Claims/B.md")
        #expect(support[0].occurrences.count == 2)
        #expect(Set(support[0].occurrences.map(\.sourceNote)) == [id("Claims/A.md")])
        #expect(snapshot.diagnostics.contains { $0.code == .duplicateRelationship })
    }

    @Test("Reciprocal support remains two distinct vector edges")
    func reciprocalVectorSupport() {
        let a = document("Claims/A.md", "+[[Claims/B]]")
        let b = document("Claims/B.md", "+[[Claims/A]]")
        let documents = [a, b]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { (id($0.relativePath), MarkdownSemanticDocument(parsing: $0)) })
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0, semantic: semantics[id($0.relativePath)]!) },
            documents: semantics
        )

        let support = snapshot.relationships.filter { $0.predicate == .supports }
        #expect(support.count == 2)
        #expect(Set(support.map { "\($0.subjectPath)->\($0.objectPath)" }) == ["Claims/A.md->Claims/B.md", "Claims/B.md->Claims/A.md"])
    }

    @Test("Reciprocal incompatibility normalizes to one undirected edge")
    func reciprocalVectorIncompatibility() {
        let a = document("Claims/A.md", "?[[Claims/B]]")
        let b = document("Claims/B.md", "?[[Claims/A]]")
        let documents = [a, b]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { (id($0.relativePath), MarkdownSemanticDocument(parsing: $0)) })
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0, semantic: semantics[id($0.relativePath)]!) },
            documents: semantics
        )

        let incompatibilities = snapshot.relationships.filter {
            $0.predicate == .incompatibleWith
        }
        #expect(incompatibilities.count == 1)
        #expect(!incompatibilities[0].isDirectional)
        #expect(incompatibilities[0].occurrences.count == 2)
        #expect(Set(incompatibilities[0].occurrences.map(\.sourceNote))
            == [id("Claims/A.md"), id("Claims/B.md")])
        #expect(snapshot.diagnostics.contains { $0.code == .duplicateRelationship })
    }

    @Test("Vector links retain aliases and resolve headings and blocks")
    func vectorDestinations() throws {
        let source = document("Output/Draft.md", "+[[Guidance Control#Argument|short]] and -[[Topics/Control#^core]].")
        let target = document("Topics/Control.md", """
        # Argument

        The central claim. ^core
        """)
        let documents = [source, target]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { (id($0.relativePath), MarkdownSemanticDocument(parsing: $0)) })
        let targetMetadata = metadata(fields: [
            "aliases": .array([.string("Guidance Control")]),
        ])
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map {
                LinkCatalogNote(
                    vaultID: vaultID,
                    document: $0,
                    profile: $0.relativePath.hasPrefix("Topics/") ? .topicMarkdown : .draftProject,
                    metadata: $0.relativePath.hasPrefix("Topics/") ? targetMetadata : nil,
                    semantic: semantics[id($0.relativePath)]!
                )
            },
            documents: semantics
        )

        let outgoing = try #require(snapshot.outgoing[id(source.relativePath)])
        #expect(outgoing.count == 2)
        #expect(outgoing[0].occurrence.alias == "short")
        #expect(outgoing[0].occurrence.vectorKind == .supports)
        #expect(outgoing[0].destination?.kind == .heading)
        #expect(outgoing[0].destination?.span?.start.line == 1)
        #expect(outgoing[1].occurrence.vectorKind == .opposes)
        #expect(outgoing[1].destination?.kind == .block)
        #expect(outgoing[1].destination?.span?.start.line == 3)
    }

    @Test("Broken and ambiguous vectors remain unresolved and source located")
    func unresolvedVectors() {
        let source = document("Output/Draft.md", "+[[Agency]]\n?[[Missing]]")
        let documents = [
            source,
            document("Topics/Agency.md", "# Agency"),
            document("Papers/Agency.md", "# A different Agency")
        ]
        let semantics = Dictionary(uniqueKeysWithValues: documents.map { (id($0.relativePath), MarkdownSemanticDocument(parsing: $0)) })
        let snapshot = LinkGraphBuilder.build(
            generation: 1,
            catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0, semantic: semantics[id($0.relativePath)]!) },
            documents: semantics
        )

        #expect(snapshot.diagnostics.contains {
            $0.code == .ambiguous && $0.source.relativePath == source.relativePath && $0.span.start.line == 1
        })
        #expect(snapshot.diagnostics.contains {
            $0.code == .broken && $0.source.relativePath == source.relativePath && $0.span.start.line == 2
        })
        #expect(snapshot.relationships.contains {
            $0.vectorKind == .supports && $0.resolution == .ambiguous(["Papers/Agency.md", "Topics/Agency.md"])
        })
        #expect(snapshot.relationships.contains {
            $0.vectorKind == .incompatible && $0.resolution == .broken("Missing")
        })
    }

    @Test("Graph rebuilds keep vector IDs, ordering, provenance, and source bytes stable")
    func deterministicVectorRebuild() throws {
        let a = document("Claims/甲.md", "+[[Claims/Beta]]\n?[[Claims/Gamma]]")
        let b = document("Claims/Beta.md", "-[[Claims/甲]]")
        let c = document("Claims/Gamma.md", "[[Claims/甲]]")
        let originalSource = [a, b, c].map(\.rawContent)

        func build(_ documents: [NoteDocument], generation: Int) -> GraphSnapshot {
            let semantics = Dictionary(uniqueKeysWithValues: documents.map { (id($0.relativePath), MarkdownSemanticDocument(parsing: $0)) })
            return LinkGraphBuilder.build(
                generation: generation,
                catalog: documents.map { LinkCatalogNote(vaultID: vaultID, document: $0, semantic: semantics[id($0.relativePath)]!) },
                documents: semantics
            )
        }

        let first = build([a, b, c], generation: 1)
        let rebuilt = build([c, a, b], generation: 99)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        #expect(try encoder.encode(first.relationships) == encoder.encode(rebuilt.relationships))
        #expect(try encoder.encode(first.diagnostics) == encoder.encode(rebuilt.diagnostics))
        #expect(first.contractVersion == GraphSnapshot.currentContractVersion)
        #expect([a, b, c].map(\.rawContent) == originalSource)
    }

    private func id(_ path: String) -> VaultQualifiedNoteID {
        VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)
    }

    private func document(_ path: String, _ source: String) -> NoteDocument {
        NoteDocument(relativePath: path, rawContent: source)
    }

    private func metadata(fields: [String: YAMLValue]) -> NoteMetadataSnapshot {
        let record = NoteMetadataRecord(noteID: UUID(), fields: fields)
        return NoteMetadataSnapshot(
            record: record,
            revision: DocumentFingerprint(content: String(describing: fields))
        )
    }
}
