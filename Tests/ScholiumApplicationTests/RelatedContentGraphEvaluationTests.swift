import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

/// Small, fixed, agent-authored judgments for graph ablation, not researcher
/// acceptance, blind evaluation, philosophical evidence, or a general benchmark.
/// Both arms call discovery.relatedContent over identical bytes and generations.
/// All candidates are Topics to isolate graph refinement from role diversity.
@Suite("Related content graph quality ablation")
struct RelatedContentGraphEvaluationTests {
    private enum ScenarioID: String, Codable {
        case tiedMaterial = "tied-material"
        case unconnectedMaterial = "unconnected-material"
        case hubDistractors = "hub-distractors"
    }

    private struct Item: Codable {
        let path: String
        let source: String
        let paragraph: String?
        let grade: Int
    }

    private struct Scenario: Codable {
        let id: ScenarioID
        let task: String
        let judgment: String
        let focus: String
        let seedLinks: [String]
        let items: [Item]

        var seedSource: String { "# Agency\n\nWorking draft.\n\n" + Self.links(seedLinks) }

        static func links(_ paths: [String]) -> String {
            // Aliases keep target titles out of the lexical seed; the exact same
            // links remain present in the graph-ineligible control arm.
            paths.map { "- [[\($0.dropLast(3))|connection]]\n" }.joined()
        }
    }

    private struct ScoredResponse: Codable {
        // Retain full exact-source paragraph and graph-occurrence locators,
        // source fingerprints, reasons, and the actual displayed order.
        let response: RelatedContentResponse
        let gradesAt6: [Int]
        let usefulRecallAt6: Double
        let ndcgAt6: Double
    }

    private struct CaseResult: Codable {
        let scenario: Scenario
        let request: RelatedContentRequest
        let topicVaultID: UUID
        let sourceManifestHash: String
        let withoutGraph: ScoredResponse
        let withGraph: ScoredResponse
        let recallAt6Delta: Double
        let ndcgAt6Delta: Double
    }

    private struct Report: Encodable {
        let corpusVersion = 1
        let judgmentAuthority = "Fixed synthetic agent-authored grades; not researcher acceptance or blind evaluation."
        let treatment =
            "Identical sources, request, index, and snapshot runtime. Control temporarily marks derived graph state ineligible via existing actor state; treatment restores it. Both arms call discovery.relatedContent. No production switch, source edit, or reindex between arms."
        let metricDefinition =
            "Grades: 0 irrelevant, 1 indirectly useful, 2 directly useful for the stated synthetic task. Recall@6 counts distinct useful Notes in the first six displayed slots, divided by all judged useful Notes. nDCG@6 uses gain=2^grade-1 and discount=log2(rank+1), with zero gain for repeated Notes and unfilled slots; ideal order includes all judgments. Deltas are withGraph minus withoutGraph. No aggregate or general usefulness claim."
        let cases: [CaseResult]
    }

    @Test("Ablate authored graph refinement through the Application retrieval path")
    func authoredGraphAblation() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let artifacts = repository.appendingPathComponent(".build/recommendation-graph-evaluation", isDirectory: true)
        let runRoot = artifacts.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runRoot) }
        var results: [CaseResult] = []
        for scenario in Self.scenarios {
            results.append(try await evaluate(scenario, root: runRoot.appendingPathComponent(scenario.id.rawValue)))
        }
        let label = ProcessInfo.processInfo.environment["SCHOLIUM_RECOMMENDATION_EVALUATION_LABEL"] ?? "latest"
        let safeLabel = label.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        try #require(!safeLabel.isEmpty)
        let reportURL = artifacts.appendingPathComponent("\(safeLabel).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Report(cases: results)).write(to: reportURL, options: .atomic)
        for result in results {
            print(
                "Synthetic graph ablation [\(result.scenario.id.rawValue)]: "
                    + "recall@6 \(formatted(result.withoutGraph.usefulRecallAt6)) -> \(formatted(result.withGraph.usefulRecallAt6)) "
                    + "(delta \(formatted(result.recallAt6Delta))); "
                    + "nDCG@6 \(formatted(result.withoutGraph.ndcgAt6)) -> \(formatted(result.withGraph.ndcgAt6)) "
                    + "(delta \(formatted(result.ndcgAt6Delta)))")
        }
        print("Synthetic graph ablation report with judgments and exact locators: \(reportURL.path)")
    }

    private func evaluate(_ scenario: Scenario, root: URL) async throws -> CaseResult {
        try #require(Set(scenario.items.map(\.path)).count == scenario.items.count)
        try #require(scenario.items.allSatisfy { (0...2).contains($0.grade) })
        let fixture = try await makeFixture(scenario, root: root)
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL, workspaceRegistryStorageURL: fixture.registryStorageURL)
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let snapshot = try await handle.snapshot()
            let graph = try #require(snapshot.discovery.catalog.graph)
            let generation = try #require(snapshot.discovery.searchGeneration)
            #expect(graph.sourceManifestHash == generation.sourceManifestHash)
            let topicVaultID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
            let request = RelatedContentRequest(
                seed: .init(
                    noteID: fixture.analysisNoteID, source: scenario.seedSource,
                    focuses: [.init(kind: .selectedPassage, text: scenario.focus)]),
                candidateRoles: [.topic])
            let withoutGraph = try await handle.relatedContentWithoutGraphForEvaluation(request)
            let withGraph = try await handle.discovery.relatedContent(request)
            // Repeat the control after graph enrichment to detect leaked context
            // in cached projections without rebuilding or changing source bytes.
            #expect(try await handle.relatedContentWithoutGraphForEvaluation(request) == withoutGraph)
            #expect(withoutGraph.freshnessToken == withGraph.freshnessToken)
            #expect(withoutGraph.availability == withGraph.availability)
            #expect(withGraph.availability == .current(generation))
            #expect(withGraph.freshnessToken == .triptych(generation))
            #expect(withoutGraph.graphCandidates.isEmpty)
            let controlCandidates = withoutGraph.identityCandidates + withoutGraph.lexicalCandidates
            let treatedCandidates = withGraph.identityCandidates + withGraph.lexicalCandidates
            #expect(controlCandidates.map(\.note) == treatedCandidates.map(\.note))
            #expect(controlCandidates.map(\.reason) == treatedCandidates.map(\.reason))
            #expect(controlCandidates.map(\.fingerprint) == treatedCandidates.map(\.fingerprint))
            #expect(controlCandidates.allSatisfy { $0.graphContext == nil })
            #expect(withoutGraph.passages.allSatisfy { $0.candidate.graphContext == nil })

            for response in [withoutGraph, withGraph] {
                #expect(response.state == .current)
                #expect(response.omittedSourceCount == 0)
                #expect(response.seedFingerprint == request.seed.fingerprint)
                try verifyLocators(response, scenario: scenario, topicVaultID: topicVaultID, snapshot: snapshot, graph: graph)
            }
            for item in scenario.items {
                #expect(try Data(contentsOf: fixture.topicsURL.appendingPathComponent(item.path)) == Data(item.source.utf8))
            }
            #expect(try Data(contentsOf: fixture.analysesURL.appendingPathComponent("Agency.md")) == Data(scenario.seedSource.utf8))
            let finalSnapshot = try await handle.snapshot()
            #expect(finalSnapshot.discovery.searchGeneration == generation)
            #expect(finalSnapshot.discovery.catalog.graph?.outgoing == graph.outgoing)
            let baseline = try score(withoutGraph, scenario: scenario)
            let connected = try score(withGraph, scenario: scenario)
            try verifyScenario(scenario.id, baseline: baseline, connected: connected)
            await runtime.shutdown()
            return .init(
                scenario: scenario, request: request, topicVaultID: topicVaultID, sourceManifestHash: generation.sourceManifestHash,
                withoutGraph: baseline, withGraph: connected,
                recallAt6Delta: connected.usefulRecallAt6 - baseline.usefulRecallAt6,
                ndcgAt6Delta: connected.ndcgAt6 - baseline.ndcgAt6)
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    private func verifyLocators(
        _ response: RelatedContentResponse, scenario: Scenario, topicVaultID: UUID,
        snapshot: WorkspaceSnapshot, graph: GraphSnapshot
    ) throws {
        for passage in response.passages {
            #expect(passage.candidate.note.vaultID == topicVaultID)
            #expect(passage.candidate.vaultRole == .topicKnowledge)
            let item = try #require(scenario.items.first { $0.path == passage.candidate.note.relativePath })
            let paragraph = try #require(item.paragraph)
            let expectedRange = (item.source as NSString).range(of: paragraph)
            try #require(expectedRange.location != NSNotFound)
            #expect(passage.range.utf16LowerBound == expectedRange.location)
            #expect(passage.range.utf16UpperBound == NSMaxRange(expectedRange))
            #expect(passage.range.line == 3 && passage.range.endLine == 3)
            #expect(passage.range.column == 1 && passage.range.endColumn == paragraph.utf16.count + 1)
            #expect(passage.candidate.fingerprint == DocumentFingerprint(content: item.source))
            #expect(Data(passage.source.utf8) == Data(paragraph.utf8))
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: item.source))
            #expect(Data(item.source[range].utf8) == Data(passage.source.utf8))
        }
        let candidates =
            response.identityCandidates + response.lexicalCandidates + response.graphCandidates
            + response.passages.map(\.candidate)
        for candidate in candidates {
            let current = try #require(snapshot.document(id: candidate.note))
            #expect(candidate.fingerprint == current.fingerprint)
            for path in candidate.graphContext?.paths ?? [] {
                #expect(path.isValid)
                for step in path.steps {
                    let source = try #require(snapshot.document(id: step.source)?.document.rawContent)
                    let range = try #require(Range(step.occurrence.span.nsRange, in: source))
                    #expect(String(source[range]) == "[[\(step.occurrence.target)|connection]]")
                    #expect(step.occurrence.resolution == .resolved(step.destination))
                    #expect(
                        graph.outgoing[step.source]?.contains {
                            $0.occurrence == step.occurrence && $0.destination?.note == step.destination
                        } == true)
                }
            }
        }
    }

    private func score(_ response: RelatedContentResponse, scenario: Scenario) throws -> ScoredResponse {
        let judgments = Dictionary(uniqueKeysWithValues: scenario.items.map { ($0.path, $0.grade) })
        let useful = Set(judgments.filter { $0.value > 0 }.keys)
        try #require(!useful.isEmpty)
        var seen = Set<String>()
        let grades = try response.passages.prefix(6).map { passage in
            let path = passage.candidate.note.relativePath
            let grade = try #require(judgments[path])
            return seen.insert(path).inserted ? grade : 0
        }
        let ideal = discountedGain(Array(judgments.values.sorted(by: >).prefix(6)))
        return .init(
            response: response, gradesAt6: grades,
            usefulRecallAt6: Double(seen.intersection(useful).count) / Double(useful.count),
            ndcgAt6: discountedGain(grades) / ideal)
    }

    private func discountedGain(_ grades: [Int]) -> Double {
        grades.enumerated().reduce(0) { $0 + (pow(2, Double($1.element)) - 1) / log2(Double($1.offset + 2)) }
    }

    private func formatted(_ value: Double) -> String { String(format: "%.3f", value) }

    private func verifyScenario(_ id: ScenarioID, baseline: ScoredResponse, connected: ScoredResponse) throws {
        let before = baseline.response.passages.map { $0.candidate.note.relativePath }
        let after = connected.response.passages.map { $0.candidate.note.relativePath }
        switch id {
        case .tiedMaterial:
            #expect(before.count == 6)
            #expect(!before.contains("Z Objection.md"))
            #expect(after.first == "Z Objection.md")
            let useful = try #require(connected.response.passages.first { $0.candidate.note.relativePath == "Z Objection.md" })
            #expect(useful.candidate.graphContext?.proximity == 1)
            #expect(useful.candidate.graphContext?.paths.first?.steps.map(\.traversal) == [.outgoing])
            #expect(connected.usefulRecallAt6 > baseline.usefulRecallAt6)
            #expect(connected.ndcgAt6 > baseline.ndcgAt6)
        case .unconnectedMaterial, .hubDistractors:
            #expect(before.first == "Z Strong.md")
            #expect(after.first == "Z Strong.md")
            let strong = try #require(connected.response.passages.first { $0.candidate.note.relativePath == "Z Strong.md" })
            #expect(strong.candidate.graphContext == nil)
            let garden = try #require(connected.response.graphCandidates.first { $0.note.relativePath == "Garden.md" })
            let gardenContext = try #require(garden.graphContext)
            #expect(gardenContext.proximity == 1)
            #expect(garden.reason == .graphConnection(gardenContext))
            #expect(!baseline.response.lexicalCandidates.contains { $0.note == garden.note })
            #expect(!baseline.response.identityCandidates.contains { $0.note == garden.note })
            #expect(!after.contains("Garden.md"))
            #expect(!after.contains("Hub.md") && !after.contains("Bridge.md"))
            #expect(connected.usefulRecallAt6 >= baseline.usefulRecallAt6)
            if id == .unconnectedMaterial {
                for item in Self.distractors.prefix(6) {
                    let context = try #require(
                        connected.response.lexicalCandidates.first { $0.note.relativePath == item.path }?.graphContext)
                    #expect(context.proximity == 1)
                    #expect(context.paths.first?.steps.map(\.traversal) == [.outgoing])
                }
            }
            if id == .hubDistractors {
                let candidates = connected.response.lexicalCandidates + connected.response.identityCandidates
                let hubNeighbor = try #require(candidates.first { $0.note.relativePath == "A Agenda.md" }?.graphContext)
                let selective = try #require(candidates.first { $0.note.relativePath == "Z Comparison.md" }?.graphContext)
                #expect(hubNeighbor.paths.first?.steps.count == 2)
                #expect(abs(hubNeighbor.proximity - 0.5 / Double(Self.distractors.count + 1)) < 0.0000001)
                #expect(selective.proximity == 0.25)
                #expect(selective.proximity > hubNeighbor.proximity)
                #expect(!before.contains("Z Comparison.md"))
                #expect(after.contains("Z Comparison.md"))
                #expect(connected.ndcgAt6 > baseline.ndcgAt6)
            }
        }
    }

    // Reuse ApplicationFixture's ownership/cleanup and registry setup pattern,
    // but keep this evaluation's generated vaults and indexes under .build.
    private func makeFixture(_ scenario: Scenario, root: URL) async throws -> ApplicationFixture {
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let registry = root.appendingPathComponent("Registry", isDirectory: true)
        for directory in [analyses, topics, works, support] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(scenario.seedSource.utf8).write(to: analyses.appendingPathComponent("Agency.md"))
        for item in scenario.items { try Data(item.source.utf8).write(to: topics.appendingPathComponent(item.path)) }
        let runtime = WorkspaceRuntime(
            configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: registry)))
        do {
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: root, triptychName: "Synthetic graph ablation")
            let assignment = handle.assignment
            let analysesID = try #require(assignment.vault(for: .paperAnalysis)?.id)
            await runtime.shutdown()
            return .init(
                rootURL: root, applicationSupportURL: support, registryStorageURL: registry,
                analysesURL: analyses, topicsURL: topics, worksURL: works, assignment: assignment,
                analysisNoteID: .init(vaultID: analysesID, relativePath: "Agency.md"))
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    private static func item(_ path: String, _ paragraph: String, grade: Int = 0, crlf: Bool = false) -> Item {
        let newline = crlf ? "\r\n" : "\n"
        let source = (crlf ? "\u{FEFF}" : "") + "# \(path.dropLast(3)) 🧭\(newline)\(newline)\(paragraph)\(newline)"
        return .init(path: path, source: source, paragraph: paragraph, grade: grade)
    }

    // Eight words, one occurrence of each focus term, equal field lengths and
    // role, distinct short prose. These are lexical ties, not duplicate passages.
    private static var distractors: [Item] {
        [
            item("A Agenda.md", "Freedom autonomy workshop timetable lists speakers before lunch."),
            item("B Schedule.md", "Freedom autonomy lecture calendar assigns rooms every Monday."),
            item("C Poster.md", "Freedom autonomy conference poster advertises dates without arguments."),
            item("D Register.md", "Freedom autonomy library register tracks borrowers during renovations."),
            item("E Budget.md", "Freedom autonomy event budget allocates funds for refreshments."),
            item("F Travel.md", "Freedom autonomy travel itinerary reserves trains between campuses."),
            item("G Catering.md", "Freedom autonomy catering order specifies lunches without nuts."),
            item("H Tickets.md", "Freedom autonomy ticket office records payments before departure."),
            item("I Equipment.md", "Freedom autonomy equipment checklist counts microphones before setup."),
            item("J Parking.md", "Freedom autonomy parking notice directs visitors toward garages."),
            item("K Shipping.md", "Freedom autonomy shipping label lists addresses without commentary."),
            item("L Lodging.md", "Freedom autonomy hotel booking reserves bedrooms for visitors."),
        ]
    }

    private static var scenarios: [Scenario] {
        let six = Array(distractors.prefix(6))
        let strong = item(
            "Z Strong.md", "Freedom autonomy coercion endorsement distinguish permission from pressure.", grade: 2, crlf: true)
        let garden = item("Garden.md", "Green leaves grow near a river.")
        let bridge = Item(
            path: "Bridge.md", source: "# Bridge\n\n" + Scenario.links(["Z Comparison.md"]), paragraph: nil, grade: 0)
        let hub = Item(
            path: "Hub.md", source: "# Hub\n\n" + Scenario.links(distractors.map(\.path)), paragraph: nil, grade: 0)
        return [
            .init(
                id: .tiedMaterial, task: "Find a question about whether freedom requires autonomous endorsement.",
                judgment: "The objection question is directly useful (2); event administration sharing the two terms is irrelevant (0).",
                focus: "freedom autonomy", seedLinks: ["Z Objection.md"],
                items: six + [
                    item("Z Objection.md", "Freedom autonomy distinction challenges whether choices require endorsement.", grade: 2, crlf: true)
                ]),
            .init(
                id: .unconnectedMaterial, task: "Distinguish coercion and endorsement when comparing freedom and autonomy.",
                judgment: "The unconnected distinction is directly useful (2); linked administrative and garden prose is irrelevant (0).",
                focus: "freedom autonomy coercion endorsement", seedLinks: six.map(\.path) + ["Garden.md"],
                items: six + [strong, garden]),
            .init(
                id: .hubDistractors, task: "Distinguish coercion and endorsement when comparing freedom and autonomy.",
                judgment:
                    "The unconnected distinction is directly useful (2); the narrower voluntary-choice comparison is indirectly useful (1). Hub, bridge, administrative and garden items are irrelevant (0). Grades do not derive from connectivity.",
                focus: "freedom autonomy coercion endorsement", seedLinks: ["Hub.md", "Bridge.md", "Garden.md"],
                items: distractors + [
                    strong, garden, hub, bridge,
                    item("Z Comparison.md", "Freedom autonomy distinction frames questions about voluntary choice.", grade: 1),
                ]),
        ]
    }
}

private extension WorkspaceHandle {
    /// Test-only access to the existing graph-eligibility seam. Snapshot mode
    /// has no watcher or other caller here; defer restores the state even when
    /// retrieval throws. Source bytes, catalog, index and request stay identical.
    func relatedContentWithoutGraphForEvaluation(_ request: RelatedContentRequest) async throws -> RelatedContentResponse {
        try #require(mode == .snapshot)
        try #require(!derivedStateRequiresRefresh)
        derivedStateRequiresRefresh = true
        defer { derivedStateRequiresRefresh = false }
        return try await discovery.relatedContent(request)
    }
}
