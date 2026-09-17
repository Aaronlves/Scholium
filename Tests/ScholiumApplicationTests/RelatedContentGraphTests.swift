import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Related-content authored graph paths")
struct RelatedContentGraphTests {
    @Test("Direct and reverse traversal retain the actual authored source occurrence")
    func directAndIncoming() throws {
        let outgoing = GraphFixture(["Seed.md": "Context [[Target]].", "Target.md": "Target text."])
        let direct = try #require(outgoing.result()?.contexts[outgoing.id("Target.md")])
        #expect(direct.proximity == 1 && direct.paths.count == 1)
        #expect(direct.paths[0].steps[0].source == outgoing.id("Seed.md"))
        #expect(direct.paths[0].steps[0].traversal == .outgoing)
        let incoming = GraphFixture(["Seed.md": "Context text.", "Target.md": "Target [[Seed]]."])
        let reverse = try #require(incoming.result()?.contexts[incoming.id("Target.md")])
        #expect(reverse.proximity == 1)
        #expect(reverse.paths[0].steps[0].source == incoming.id("Target.md"))
        #expect(reverse.paths[0].steps[0].destination == incoming.id("Seed.md"))
        #expect(reverse.paths[0].steps[0].traversal == .incoming)
        #expect(reverse.paths[0].steps[0].occurrence.target == "Seed")
    }

    @Test("All four two-step traversal directions work without inventing directed edges")
    func allDirections() throws {
        let cases: [(String, String, String, [RelatedContentGraphTraversal])] = [
            ("Context [[Middle]].", "Middle [[Target]].", "Target text.", [.outgoing, .outgoing]),
            ("Context [[Middle]].", "Middle text.", "Target [[Middle]].", [.outgoing, .incoming]),
            ("Context text.", "Middle [[Seed]] [[Target]].", "Target text.", [.incoming, .outgoing]),
            ("Context text.", "Middle [[Seed]].", "Target [[Middle]].", [.incoming, .incoming]),
        ]
        for (seed, middle, target, expected) in cases {
            let fixture = GraphFixture(["Seed.md": seed, "Middle.md": middle, "Target.md": target])
            let context = try #require(fixture.result()?.contexts[fixture.id("Target.md")])
            #expect(context.proximity == 0.25)
            #expect(context.paths.count == 1)
            #expect(context.paths[0].steps.map(\.traversal) == expected)
            for step in context.paths[0].steps {
                #expect(fixture.graph.outgoing[step.source]?.contains { $0.occurrence == step.occurrence && $0.destination?.note == step.destination } == true)
            }
        }
    }

    @Test("Three-hop targets and cycles never become two-hop candidates or return the seed")
    func distanceAndCycles() throws {
        let fixture = GraphFixture([
            "Seed.md": "Context [[Seed]] [[Middle]].", "Middle.md": "Middle [[Seed]] [[Near]].",
            "Near.md": "Near [[Far]].", "Far.md": "Far text.",
        ])
        let result = try #require(try fixture.result(existing: ["Far.md"]))
        #expect(result.contexts[fixture.id("Seed.md")] == nil)
        #expect(result.contexts[fixture.id("Middle.md")]?.proximity == 1)
        #expect(result.contexts[fixture.id("Near.md")]?.proximity == 0.25)
        #expect(result.contexts[fixture.id("Far.md")] == nil)
        #expect(result.candidates.allSatisfy { $0.note != fixture.id("Seed.md") })
    }

    @Test("Repeated and reciprocal occurrences do not multiply proximity or degree")
    func deduplication() throws {
        let ordinary = GraphFixture(["Seed.md": "Context [[Middle]].", "Middle.md": "Middle [[Target]].", "Target.md": "Target text."])
        let repeated = GraphFixture([
            "Seed.md": "Context [[Middle]] [[Middle]] [[Middle]].",
            "Middle.md": "Middle [[Seed]] [[Target]] [[Target]].", "Target.md": "Target [[Middle]].",
        ])
        let baseline = try #require(ordinary.result()?.contexts[ordinary.id("Target.md")])
        let context = try #require(repeated.result()?.contexts[repeated.id("Target.md")])
        #expect(context.proximity == baseline.proximity && context.proximity == 0.25)
        #expect(context.paths.count == 1)
        #expect(context.paths[0].steps[1].occurrence.span.utf16LowerBound < 20)
    }

    @Test("Complete distinct degree discounts hubs even beyond bounded graph-only expansion")
    func hubDiscountAndExpansion() throws {
        var documents: [String: String] = ["Seed.md": "Context [[Middle]].", "Target.md": "Target text."]
        let extras = (0..<260).map { String(format: "Extra%03d", $0) }
        documents["Middle.md"] = "Middle [[Target]] " + extras.map { "[[\($0)]]" }.joined(separator: " ")
        for extra in extras { documents[extra + ".md"] = "Extra text." }
        let fixture = GraphFixture(documents)
        let result = try #require(try fixture.result(existing: ["Target.md"]))
        let context = try #require(result.contexts[fixture.id("Target.md")])
        #expect(abs(context.proximity - 0.5 / 262) < 0.0000001)
        #expect(result.candidates.count == RelatedContentContract.maximumGraphCandidates)
        #expect(result.hasMore)
        #expect(!result.candidates.contains { $0.note == fixture.id("Target.md") })
    }

    @Test("Distinct intermediate contributions sum and explanatory paths stay bounded")
    func multiplePaths() throws {
        let fixture = GraphFixture([
            "Seed.md": "Context [[M1]] [[M2]] [[M3]] [[M4]] [[M5]].",
            "M1.md": "Middle [[Target]].", "M2.md": "Middle [[Target]].", "M3.md": "Middle [[Target]].",
            "M4.md": "Middle [[Target]].", "M5.md": "Middle [[Target]].", "Target.md": "Target text.",
        ])
        let context = try #require(fixture.result()?.contexts[fixture.id("Target.md")])
        #expect(context.proximity == 1)
        #expect(context.paths.count == RelatedContentContract.maximumGraphPathsPerCandidate)
        #expect(context.paths.map { $0.steps[0].destination.relativePath } == ["M1.md", "M2.md", "M3.md"])
    }

    @Test("Exact unsaved seed replaces saved outgoing occurrences in forward and reverse walks")
    func unsavedOverlay() throws {
        let fixture = GraphFixture([
            "Seed.md": "Context [[Old]].", "Old.md": "Old [[OldTarget]].", "OldTarget.md": "Old target.",
            "New.md": "New [[NewTarget]].", "NewTarget.md": "New target.",
        ])
        let source = "Unsaved context [[New]]."
        let result = try #require(try fixture.result(source: source, existing: ["OldTarget.md"]))
        #expect(result.contexts[fixture.id("Old.md")] == nil)
        #expect(result.contexts[fixture.id("OldTarget.md")] == nil)
        #expect(result.contexts[fixture.id("New.md")]?.proximity == 1)
        #expect(result.contexts[fixture.id("NewTarget.md")]?.proximity == 0.25)
        #expect(result.contexts[fixture.id("New.md")]?.paths[0].steps[0].occurrence.localContext.contains("Unsaved") == true)
        #expect(fixture.graph.outgoing[fixture.id("Seed.md")]?.first?.occurrence.target == "Old")
    }

    @Test("Ambiguous, unresolved and nonresearch intermediates cannot authorize paths")
    func ambiguityAndAccess() throws {
        let ambiguous = GraphFixture([
            "Seed.md": "Context [[Shared]] [[Missing]].", "one/Shared.md": "One [[Target]].",
            "two/Shared.md": "Two [[Target]].", "Target.md": "Target text.",
        ])
        #expect(try ambiguous.result()?.contexts.isEmpty == true)
        let inaccessible = GraphFixture(
            ["Seed.md": "Context [[Private]].", "Private.md": "Private [[Target]].", "Target.md": "Target text."],
            roles: ["Private.md": .other])
        #expect(try inaccessible.result()?.contexts.isEmpty == true)
        let wrongManifest = GraphFixture(["Seed.md": "Context [[Target]].", "Target.md": "Target text."])
        #expect(try wrongManifest.result(manifest: "incompatible") == nil)
        #expect(try wrongManifest.result(catalog: Array(wrongManifest.catalog.dropLast())) == nil)
    }

    @Test("Output role filtering does not exclude an authorized intermediate from another research role")
    func roles() throws {
        let fixture = GraphFixture(
            ["Seed.md": "Context [[Middle]].", "Middle.md": "Middle [[Target]].", "Target.md": "Target text."],
            roles: ["Middle.md": .sourceCorpus])
        let result = try #require(try fixture.result(candidateRoles: [.topic]))
        #expect(result.contexts[fixture.id("Middle.md")] == nil)
        #expect(result.contexts[fixture.id("Target.md")]?.proximity == 0.25)
        #expect(result.candidates.map(\.note) == [fixture.id("Target.md")])
    }

    @Test("Application uses current graph cohort and enriches verified material without giving links relevance")
    func applicationIntegration() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        try Data("# Middle\n\n[[Target]]\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("Middle.md"))
        try Data("# Target\n\nAgency requires a deliberate choice.\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("Target.md"))
        try Data("# Unrelated\n\nDifferent subject altogether.\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("Unrelated.md"))
        try Data("# ReverseMiddle\n\n[[Agency]]\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("ReverseMiddle.md"))
        try Data("# ReverseTarget\n\n[[ReverseMiddle]]\n\nAgency involves deliberate choice in this synthetic case.\n".utf8)
            .write(to: fixture.topicsURL.appendingPathComponent("ReverseTarget.md"))
        try Data("# Unregistered\n\nAgency deliberate choice outside registered membership.\n".utf8)
            .write(to: fixture.rootURL.appendingPathComponent("Unregistered.md"))
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL, workspaceRegistryStorageURL: fixture.registryStorageURL)
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let response = try await handle.discovery.relatedContent(
                .init(
                    seed: .init(
                        noteID: fixture.analysisNoteID, source: "# Agency\n\nAgency [[Middle]] [[Unrelated]] [[Unregistered]].",
                        focuses: [.init(kind: .selectedPassage, text: "agency deliberate choice")])))
            let target = try #require(response.passages.first { $0.candidate.note.relativePath == "Target.md" })
            #expect(target.candidate.graphContext?.paths.first?.steps.count == 2)
            #expect(target.candidate.graphContext?.proximity == 0.25)
            #expect(!response.passages.contains { $0.candidate.note.relativePath == "Unrelated.md" })
            #expect(
                (response.graphCandidates + response.identityCandidates + response.lexicalCandidates).allSatisfy {
                    $0.note.relativePath != "Unregistered.md"
                })
            #expect(response.graphCandidates.count <= RelatedContentContract.maximumGraphCandidates)
            let reverseResponse = try await handle.discovery.relatedContent(
                .init(
                    seed: .init(
                        noteID: fixture.analysisNoteID, source: "# Agency\n\nAgency context.",
                        focuses: [.init(kind: .selectedPassage, text: "agency deliberate choice")])))
            let reverseTarget = try #require(reverseResponse.passages.first { $0.candidate.note.relativePath == "ReverseTarget.md" })
            #expect(reverseTarget.candidate.graphContext?.paths.first?.steps.map(\.traversal) == [.incoming, .incoming])
            let snapshot = try await handle.snapshot()
            #expect(snapshot.discovery.catalog.graph?.outgoing[fixture.analysisNoteID]?.isEmpty == true)
            await #expect(throws: (any Error).self) {
                try await handle.discovery.relatedContent(
                    .init(
                        seed: .init(
                            noteID: .init(vaultID: UUID(), relativePath: "Unregistered.md"), source: "agency deliberate choice")))
            }
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
    }
}

private struct GraphFixture {
    let vaultID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let triptychID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let documents: [String: NoteDocument]
    let catalog: [WorkspaceCatalogNote]
    let linkCatalog: [LinkCatalogNote]
    let graph: GraphSnapshot

    init(_ sources: [String: String], roles: [String: VaultRole] = [:]) {
        let taskVaultID = vaultID
        let taskDocuments = Dictionary(uniqueKeysWithValues: sources.map { ($0.key, NoteDocument(relativePath: $0.key, rawContent: $0.value)) })
        documents = taskDocuments
        let taskCatalog: [WorkspaceCatalogNote] = taskDocuments.keys.sorted().compactMap { path in
            guard let document = taskDocuments[path] else { return nil }
            return .init(
                reference: .init(vaultID: taskVaultID, vaultName: "Disposable", vaultRole: roles[path] ?? .topicKnowledge, relativePath: path),
                title: ResearchNoteTitleResolver.resolve(document: document), fingerprint: document.fingerprint, validationWarnings: [])
        }
        catalog = taskCatalog
        let taskLinkCatalog = taskDocuments.keys.sorted().compactMap { path in
            taskDocuments[path].map { LinkCatalogNote(vaultID: taskVaultID, document: $0) }
        }
        linkCatalog = taskLinkCatalog
        let manifest = SearchSourceManifest.hash(
            taskCatalog.map {
                .init(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath, fingerprint: $0.fingerprint)
            })
        graph = LinkGraphBuilder.build(
            generation: 1, catalog: taskLinkCatalog,
            documents: Dictionary(
                taskDocuments.map { (VaultQualifiedNoteID(vaultID: taskVaultID, relativePath: $0.key), MarkdownSemanticDocument(parsing: $0.value)) },
                uniquingKeysWith: { first, _ in first }),
            resolutionScope: .workspace, sourceManifestHash: manifest)
    }

    func id(_ path: String) -> VaultQualifiedNoteID { .init(vaultID: vaultID, relativePath: path) }
    func result(
        source: String? = nil, existing: [String] = [], manifest: String? = nil,
        catalog: [WorkspaceCatalogNote]? = nil, candidateRoles: [RelatedContentCandidateRole] = [.analysis, .topic, .work]
    ) throws -> RelatedContentGraphCandidates.Result? {
        let request = RelatedContentRequest(
            seed: .init(noteID: id("Seed.md"), source: source ?? documents["Seed.md"]!.rawContent), candidateRoles: candidateRoles)
        let candidates = existing.compactMap { path -> RelatedContentCandidate? in
            guard let note = self.catalog.first(where: { $0.reference.relativePath == path }) else { return nil }
            return .init(
                note: id(path), vaultRole: note.reference.vaultRole, title: note.title, fingerprint: note.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [], seedMatches: [])))
        }
        return try RelatedContentGraphCandidates.build(
            request: request, graph: graph,
            searchGeneration: .init(triptychID: triptychID, sequence: 1, sourceManifestHash: manifest ?? graph.sourceManifestHash),
            catalog: catalog ?? self.catalog, linkCatalog: linkCatalog, existingCandidates: candidates)
    }
}
