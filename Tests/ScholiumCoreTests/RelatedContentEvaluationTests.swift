import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// A fixed, authored diagnostic corpus, not judgments from the researcher or a
/// claim of philosophical truth. All prose and source titles below are invented.
/// Grades concern usefulness for the stated writing task, never evidential status.
///
/// Run before and after a change with distinct
/// SCHOLIUM_RECOMMENDATION_EVALUATION_LABEL values. The development split may guide
/// tuning. The heldout split is a separate regression sample; it is visible to
/// developers and therefore is not a blind or independently adjudicated test set.
/// No quality threshold freezes today's misses or false positives into a contract.
@Suite("Related content authored evaluation")
struct RelatedContentEvaluationTests {
    private enum Split: String, Codable { case development, heldout }

    private struct Item {
        let id: String
        let role: VaultRole
        let text: String
        let grade: Int
        let equivalenceGroup: String?
    }

    private struct Scenario {
        let id: String
        let split: Split
        let category: String
        let focus: String
        let judgment: String
        let items: [Item]
    }

    private struct CaseResult: Codable {
        let id: String
        let split: Split
        let category: String
        let candidateCount: Int
        let returnedPassageCount: Int
        let rankedNoteIDs: [String]
        let grades: [Int]
        let candidateUsefulRecall: Double?
        let usefulRecallAt6: Double?
        let usefulPrecisionAt6: Double
        let returnedUsefulPrecision: Double?
        let ndcgAt6: Double?
        let distinctMaterialRecallAt6: Double?
        let distinctMaterialNDCGAt6: Double?
        let firstUsefulRank: Int?
        let reciprocalRank: Double?
        let redundantPassages: Int
    }

    private struct Aggregate: Codable {
        let split: Split
        let cases: Int
        let casesWithUsefulJudgments: Int
        let meanCandidateUsefulRecall: Double?
        let meanUsefulRecallAt6: Double?
        let meanUsefulPrecisionAt6: Double
        let meanReturnedUsefulPrecision: Double?
        let meanNDCGAt6: Double?
        let meanDistinctMaterialRecallAt6: Double?
        let meanDistinctMaterialNDCGAt6: Double?
        let meanReciprocalRank: Double?
        let redundantPassages: Int
        let noUsefulJudgmentCases: Int
        let noUsefulJudgmentCasesReturningResults: Int
    }

    private struct Report: Codable {
        let corpusVersion: Int
        let judgmentAuthority: String
        let pipeline: String
        let metricDefinition: String
        let relatedContractVersion: Int
        let rankingPolicyVersion: Int
        let cases: [CaseResult]
        let aggregates: [Aggregate]
    }

    @Test("Measure graded recommendation quality through indexed candidate retrieval")
    func authoredCorpus() async throws {
        let corpus = Self.corpus
        #expect(corpus.count == 36)
        #expect(Set(corpus.map(\.id)).count == corpus.count)
        #expect(corpus.filter { $0.split == .development }.count == 18)
        #expect(corpus.filter { $0.split == .heldout }.count == 18)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/recommendation-evaluation", isDirectory: true)
        let fixtureRoot = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        var results: [CaseResult] = []
        for scenario in corpus {
            results.append(try await evaluate(scenario, root: fixtureRoot))
        }
        let aggregates = [Split.development, .heldout].map { aggregate($0, results: results) }
        let report = Report(
            corpusVersion: 1,
            judgmentAuthority: "Synthetic agent-authored judgments; not researcher acceptance or blind evaluation.",
            pipeline: "SQLite synchronize -> relatedMaterialSourceCandidates -> current fixture source -> actor relatedPassages",
            metricDefinition:
                "Grades: 0 irrelevant, 1 indirectly useful, 2 directly useful. Rank metrics use first occurrence per Note in the first six displayed passages. nDCG gain=2^grade-1, discount=log2(rank+1). Precision@6 divides useful Notes by six, so unfilled slots earn zero; returned precision divides by distinct returned Notes. Recall denominators include every judged useful Note, including indexed-candidate misses. No-useful-judgment recall, nDCG and reciprocal rank are null, not perfect scores. Redundancy counts repeated Note/equivalence-group passages separately. Distinct-material recall and nDCG merge explicitly authored equivalence groups; repeated material earns no additional gain, while retaining its displayed slot.",
            relatedContractVersion: RelatedContentContract.currentVersion,
            rankingPolicyVersion: RelatedContentContract.rankingPolicyVersion,
            cases: results, aggregates: aggregates)
        let label = ProcessInfo.processInfo.environment["SCHOLIUM_RECOMMENDATION_EVALUATION_LABEL"] ?? "latest"
        let safeLabel = label.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        #expect(!safeLabel.isEmpty)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reportURL = root.appendingPathComponent("\(safeLabel.isEmpty ? "latest" : safeLabel).json")
        try encoder.encode(report).write(to: reportURL, options: .atomic)
        for value in aggregates {
            print(
                "Authored recommendation evaluation [\(value.split.rawValue), \(value.cases) cases]: "
                    + "nDCG@6=\(formatted(value.meanNDCGAt6)), "
                    + "candidateRecall=\(formatted(value.meanCandidateUsefulRecall)), "
                    + "recall@6=\(formatted(value.meanUsefulRecallAt6)), "
                    + "precision@6=\(formatted(value.meanUsefulPrecisionAt6)), "
                    + "returnedPrecision=\(formatted(value.meanReturnedUsefulPrecision)), "
                    + "MRR=\(formatted(value.meanReciprocalRank)), "
                    + "materialNDCG=\(formatted(value.meanDistinctMaterialNDCGAt6)), "
                    + "materialRecall=\(formatted(value.meanDistinctMaterialRecallAt6)), redundantPassages=\(value.redundantPassages)")
        }
        print("Authored recommendation evaluation report: \(reportURL.path)")
    }

    private func evaluate(_ scenario: Scenario, root: URL) async throws -> CaseResult {
        #expect(!scenario.judgment.isEmpty)
        #expect(Set(scenario.items.map(\.id)).count == scenario.items.count)
        #expect(scenario.items.allSatisfy { (0...2).contains($0.grade) })
        let vaults = [
            RegisteredVault(name: "Analyses", role: .sourceCorpus, canonicalPath: "/synthetic/analyses"),
            RegisteredVault(name: "Topics", role: .topicKnowledge, canonicalPath: "/synthetic/topics"),
            RegisteredVault(name: "Works", role: .draftProject, canonicalPath: "/synthetic/works"),
        ]
        let works = try #require(vaults.first { $0.role == .draftProject })
        let documents = try scenario.items.map { item in
            let vault = try #require(vaults.first { $0.role == item.role })
            return SearchIndexDocument(
                vaultID: vault.id, vaultName: vault.name, vaultRole: vault.role,
                document: .init(relativePath: "\(item.id).md", rawContent: item.text))
        }
        let seedID = VaultQualifiedNoteID(vaultID: works.id, relativePath: "Active.md")
        let request = RelatedContentRequest(
            seed: .init(noteID: seedID, source: scenario.focus, focuses: [.init(kind: .selectedPassage, text: scenario.focus)]))
        let index = try TriptychSearchIndex(
            databaseURL: root.appendingPathComponent("\(scenario.id).sqlite"), triptychID: UUID(), vaults: vaults)
        _ = try await index.synchronize(documents)
        let response = try await index.relatedMaterialSourceCandidates(request)
        #expect(response.state == .current || response.state == .empty)
        var seen: Set<VaultQualifiedNoteID> = []
        let candidates = (response.identityCandidates + response.lexicalCandidates).filter { seen.insert($0.note).inserted }
        let sources = try candidates.map { candidate in
            let document = try #require(documents.first { $0.vaultID == candidate.note.vaultID && $0.relativePath == candidate.note.relativePath })
            return RelatedContentSource(candidate: candidate, document: document.document)
        }
        let passages = try await index.relatedPassages(request, sources: sources)
        // Query stability is separate from quality judgments. A cache hit or
        // reversed current-source traversal must not change the recommendation.
        #expect(try await index.relatedPassages(request, sources: sources.reversed()) == passages)
        for passage in passages {
            let source = try #require(sources.first { $0.candidate.note == passage.candidate.note })
            #expect(passage.candidate.fingerprint == source.document.fingerprint)
            #expect(passage.candidate.vaultRole == source.candidate.vaultRole)
            let range = try #require(
                Range(
                    NSRange(location: passage.range.utf16LowerBound, length: passage.range.utf16UpperBound - passage.range.utf16LowerBound),
                    in: source.document.rawContent))
            #expect(String(source.document.rawContent[range]) == passage.source)
        }
        let judgments = Dictionary(uniqueKeysWithValues: scenario.items.map { ("\($0.id).md", $0.grade) })
        let usefulIDs = Set(judgments.filter { $0.value > 0 }.keys)
        var rankedIDs: [String] = []
        var equivalences: Set<String> = []
        var redundant = 0
        var materialGrades: [Int] = []
        var usefulMaterialReturned: Set<String> = []
        var materialJudgments: [String: Int] = [:]
        for item in scenario.items {
            let group = item.equivalenceGroup ?? "\(item.id).md"
            materialJudgments[group] = max(materialJudgments[group] ?? 0, item.grade)
        }
        for passage in passages.prefix(6) {
            let path = passage.candidate.note.relativePath
            let item = try #require(scenario.items.first { "\($0.id).md" == path })
            if !rankedIDs.contains(path) { rankedIDs.append(path) }
            let group = item.equivalenceGroup ?? path
            let novelMaterial = equivalences.insert(group).inserted
            if !novelMaterial { redundant += 1 }
            materialGrades.append(novelMaterial ? item.grade : 0)
            if item.grade > 0 { usefulMaterialReturned.insert(group) }
        }
        let grades = rankedIDs.map { judgments[$0] ?? 0 }
        let ideal = scenario.items.map(\.grade).sorted(by: >).prefix(6)
        let idealGain = discountedGain(Array(ideal))
        let usefulReturned = rankedIDs.filter { usefulIDs.contains($0) }.count
        let usefulMaterialCount = materialJudgments.values.filter { $0 > 0 }.count
        let materialIdealGain = discountedGain(Array(materialJudgments.values.sorted(by: >).prefix(6)))
        let firstUseful = grades.firstIndex { $0 > 0 }.map { $0 + 1 }
        return CaseResult(
            id: scenario.id, split: scenario.split, category: scenario.category,
            candidateCount: candidates.count, returnedPassageCount: passages.count,
            rankedNoteIDs: rankedIDs, grades: grades,
            candidateUsefulRecall: usefulIDs.isEmpty
                ? nil : Double(Set(candidates.map { $0.note.relativePath }).intersection(usefulIDs).count) / Double(usefulIDs.count),
            usefulRecallAt6: usefulIDs.isEmpty ? nil : Double(usefulReturned) / Double(usefulIDs.count),
            usefulPrecisionAt6: Double(usefulReturned) / 6,
            returnedUsefulPrecision: rankedIDs.isEmpty ? nil : Double(usefulReturned) / Double(rankedIDs.count),
            ndcgAt6: idealGain == 0 ? nil : discountedGain(grades) / idealGain,
            distinctMaterialRecallAt6: usefulMaterialCount == 0 ? nil : Double(usefulMaterialReturned.count) / Double(usefulMaterialCount),
            distinctMaterialNDCGAt6: materialIdealGain == 0 ? nil : discountedGain(materialGrades) / materialIdealGain,
            firstUsefulRank: firstUseful,
            reciprocalRank: usefulIDs.isEmpty ? nil : firstUseful.map { 1 / Double($0) } ?? 0,
            redundantPassages: redundant)
    }

    private func discountedGain(_ grades: [Int]) -> Double {
        grades.enumerated().reduce(0) { $0 + (pow(2, Double($1.element)) - 1) / log2(Double($1.offset + 2)) }
    }

    private func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func formatted(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "n/a" }

    private func aggregate(_ split: Split, results: [CaseResult]) -> Aggregate {
        let selected = results.filter { $0.split == split }
        let noUseful = selected.filter { $0.usefulRecallAt6 == nil }
        return .init(
            split: split, cases: selected.count, casesWithUsefulJudgments: selected.count - noUseful.count,
            meanCandidateUsefulRecall: mean(selected.compactMap(\.candidateUsefulRecall)),
            meanUsefulRecallAt6: mean(selected.compactMap(\.usefulRecallAt6)),
            meanUsefulPrecisionAt6: mean(selected.map(\.usefulPrecisionAt6)) ?? 0,
            meanReturnedUsefulPrecision: mean(selected.compactMap(\.returnedUsefulPrecision)),
            meanNDCGAt6: mean(selected.compactMap(\.ndcgAt6)),
            meanDistinctMaterialRecallAt6: mean(selected.compactMap(\.distinctMaterialRecallAt6)),
            meanDistinctMaterialNDCGAt6: mean(selected.compactMap(\.distinctMaterialNDCGAt6)),
            meanReciprocalRank: mean(selected.compactMap(\.reciprocalRank)),
            redundantPassages: selected.reduce(0) { $0 + $1.redundantPassages },
            noUsefulJudgmentCases: noUseful.count,
            noUsefulJudgmentCasesReturningResults: noUseful.filter { $0.returnedPassageCount > 0 }.count)
    }

    private static func note(_ id: String, _ role: VaultRole, _ grade: Int, _ text: String, group: String? = nil) -> Item {
        .init(id: id, role: role, text: text, grade: grade, equivalenceGroup: group)
    }

    private static func scenario(
        _ id: String, _ split: Split, _ category: String, _ focus: String, _ judgment: String, _ items: [Item]
    ) -> Scenario {
        .init(id: id, split: split, category: category, focus: focus, judgment: judgment, items: items)
    }

    private static var corpus: [Scenario] {
        [
            scenario(
                "salience-01", .development, "salience", "The discussion should consider the argument and its important implications for supervenience.",
                "The rare target concept is directly useful; generic reasoning advice is indirect; event discussion is unrelated.",
                [
                    note(
                        "Dependence", .topicKnowledge, 2,
                        "Supervenience asks whether a difference in one family of properties requires a difference in another."),
                    note("Reasoning", .draftProject, 1, "An argument should distinguish its premises from the implications of its conclusion."),
                    note(
                        "Meeting", .sourceCorpus, 0, "The discussion should consider the important implications of an event booking and its catering argument."),
                ]),
            scenario(
                "salience-02", .development, "salience", "We need to explain how the issue affects the account of akrasia in this chapter.",
                "Akrasia is the topic; chapter organization is indirect; an accounting issue is irrelevant.",
                [
                    note("Akrasia", .topicKnowledge, 2, "Akrasia concerns acting against one's considered judgment about what to do."),
                    note("Outline", .draftProject, 1, "This chapter should explain the account before presenting an objection."),
                    note("Invoice", .sourceCorpus, 0, "We need to explain how the issue affects the account of this invoice in the chapter budget."),
                ]),
            scenario(
                "salience-03", .heldout, "salience", "This question requires a careful discussion of the relation between evidence and defeasibility.",
                "Defeasibility directly addresses the focus; collecting evidence is indirect; event planning is irrelevant.",
                [
                    note(
                        "Defeasibility", .topicKnowledge, 2,
                        "Defeasibility concerns reasons that can lose their justificatory force when further information appears."),
                    note("Evidence", .sourceCorpus, 1, "Evidence should be collected before comparing possible explanations."),
                    note(
                        "Event", .draftProject, 0, "This question requires a careful discussion of the relation between event evidence and catering expenses."),
                ]),
            scenario(
                "salience-04", .heldout, "salience", "For the purposes of this argument we should examine the role of intentionality.",
                "Intentionality is central; argument organization is indirect; role assignments are irrelevant.",
                [
                    note(
                        "Intentionality", .topicKnowledge, 2, "Intentionality concerns the directedness of a mental state toward an object or state of affairs."
                    ),
                    note("Structure", .draftProject, 1, "The argument should explain the role of a premise before deriving the conclusion."),
                    note("Roster", .sourceCorpus, 0, "For the purposes of this meeting we should examine the role of the argument coordinator."),
                ]),
            scenario(
                "tail-01", .development, "long-focus",
                "This opening sentence supplies background about a chapter that is being revised for clarity and organization while several examples remain provisional because their details require a later discussion with readers and editors. The central issue is moral luck.",
                "The final sentence specifies moral luck; editorial process overlap is irrelevant.",
                [
                    note("Luck", .topicKnowledge, 2, "Moral luck asks whether factors outside an agent's control affect moral assessment."),
                    note("Control", .sourceCorpus, 1, "An agent's control over an action matters when responsibility is assessed."),
                    note(
                        "Editing", .draftProject, 0,
                        "This opening sentence supplies background about a chapter being revised for clarity and organization with provisional examples and readers."
                    ),
                ]),
            scenario(
                "tail-02", .development, "long-focus",
                "At the beginning I introduce the plan and explain why various sections need revision before discussing several examples in greater detail for the reader who may not yet know how all parts fit together. My question concerns epistemic injustice.",
                "Epistemic injustice at the tail is central; revision planning is unrelated.",
                [
                    note(
                        "Injustice", .topicKnowledge, 2, "Epistemic injustice includes cases in which prejudice distorts the credibility accorded to a speaker."
                    ),
                    note("Credibility", .sourceCorpus, 1, "Credibility judgments affect whether testimony is accepted."),
                    note(
                        "Revision", .draftProject, 0,
                        "At the beginning I introduce the plan and explain why sections need revision before discussing examples in detail for the reader."),
                ]),
            scenario(
                "tail-03", .heldout, "long-focus",
                "The following introductory remarks locate the discussion within a larger project and explain the arrangement of chapters without settling their conclusions because multiple versions of the framework are still under consideration by the writer. The precise target is counterfactual dependence.",
                "Counterfactual dependence is directly useful; introductory project prose is unrelated.",
                [
                    note("Counterfactual", .topicKnowledge, 2, "Counterfactual dependence asks whether an outcome would differ if a condition were absent."),
                    note("Causation", .sourceCorpus, 1, "Causation and explanatory relevance should be distinguished when describing an outcome."),
                    note(
                        "Project", .draftProject, 0,
                        "The following introductory remarks locate the discussion within a larger project and explain chapters without settling conclusions or versions."
                    ),
                ]),
            scenario(
                "tail-04", .heldout, "long-focus",
                "We can begin with a broad explanation of the structure and motivation of this project before turning to more difficult details about terminology and examples that have caused confusion in previous discussions with colleagues. What matters here is phenomenal consciousness.",
                "Phenomenal consciousness is central; project terminology chatter is unrelated.",
                [
                    note("Consciousness", .topicKnowledge, 2, "Phenomenal consciousness concerns what an experience is like for its subject."),
                    note("Perception", .sourceCorpus, 1, "Perception provides a subject with information about the surrounding environment."),
                    note(
                        "Terminology", .draftProject, 0,
                        "We can begin with a broad explanation of structure and motivation before difficult details about terminology and confusing examples."),
                ]),
            scenario(
                "phrase-01", .development, "phrase-and-negation", "necessary condition for responsibility",
                "The complete relation is direct; the reversed relation is nearby but indirect; separate keywords are irrelevant.",
                [
                    note(
                        "Necessary", .topicKnowledge, 2,
                        "Is control a necessary condition for responsibility? A counterexample would preserve responsibility without control."),
                    note("Sufficient", .sourceCorpus, 1, "Responsibility is a sufficient condition for inclusion in the accountability discussion."),
                    note("Catalog", .draftProject, 0, "The necessary stationery order lists a condition report and a responsibility roster."),
                ]),
            scenario(
                "phrase-02", .development, "phrase-and-negation", "Desire is not sufficient for a reason to act.",
                "Both sides of the exact dispute are useful, with a direct counterexample most useful; negation does not make a passage irrelevant.",
                [
                    note(
                        "Counterexample", .topicKnowledge, 2, "Desire is not sufficient for a reason to act: an uninformed desire may favor a pointless action."
                    ),
                    note("Opposing", .sourceCorpus, 1, "Desire is sufficient for a reason to act according to the fictional proposal considered here."),
                    note("Holiday", .draftProject, 0, "The travel agency named Desire reports sufficient bookings for a holiday act."),
                ]),
            scenario(
                "phrase-03", .heldout, "phrase-and-negation", "fitting attitude account of value",
                "The intact technical phrase is direct; a general attitude discussion is indirect; clothing fit is irrelevant.",
                [
                    note(
                        "Fitting", .topicKnowledge, 2,
                        "A fitting attitude account of value connects value with attitudes that are appropriate toward their objects."),
                    note("Attitude", .sourceCorpus, 1, "An attitude can have an object without accurately representing that object."),
                    note("Tailoring", .draftProject, 0, "Fitting a jacket requires an attitude survey and an account of its retail value."),
                ]),
            scenario(
                "phrase-04", .heldout, "phrase-and-negation", "Not every explanation is a justification.",
                "The distinction is direct; a contrary universal is still dialectically relevant; invoice justification is unrelated.",
                [
                    note(
                        "Distinction", .topicKnowledge, 2,
                        "Not every explanation is a justification: explaining why a person acted need not show that the action was reasonable."),
                    note("Conflation", .sourceCorpus, 1, "Every explanation is a justification in the invented position being challenged."),
                    note("Invoice", .draftProject, 0, "Every invoice needs an explanation field and a justification code for processing."),
                ]),
            scenario(
                "source-01", .development, "source-lookup", "What does the fictional paper Lantern on Agency argue about control?",
                "The named invented source is direct; concept overview is indirect; a lantern product is irrelevant.",
                [
                    note(
                        "Lantern on Agency", .sourceCorpus, 2,
                        "# Lantern on Agency\n\nThis fictional paper argues that control requires an ability to revise an action after considering reasons."),
                    note("Control Overview", .topicKnowledge, 1, "Control can refer to initiation, guidance, or revision of an action."),
                    note("Lantern Product", .draftProject, 0, "The Lantern agency sells a control panel for garden lighting."),
                ]),
            scenario(
                "source-02", .development, "source-lookup", "Compare the premise in the invented source Cedar on Testimony with its conclusion.",
                "The source's premise and conclusion are direct; testimony overview is indirect; timber sales are irrelevant.",
                [
                    note(
                        "Cedar on Testimony", .sourceCorpus, 2,
                        "# Cedar on Testimony\n\nThe invented source begins with a premise about speaker reliability and reaches a conclusion about accepting testimony."
                    ),
                    note("Testimony", .topicKnowledge, 1, "Testimony involves learning from what another person tells us."),
                    note("Cedar Order", .draftProject, 0, "Compare the cedar source invoice premise code with the conclusion of the delivery order."),
                ]),
            scenario(
                "source-03", .heldout, "source-lookup", "Find the definition from the fictional article Harbor on Reasons.",
                "The definition in the named source is direct; reasons overview is indirect; an article stock record is irrelevant.",
                [
                    note(
                        "Harbor on Reasons", .sourceCorpus, 2,
                        "# Harbor on Reasons\n\nThe fictional article defines a reason as a consideration that counts in favor of an action."),
                    note("Reasons Overview", .topicKnowledge, 1, "Reasons for action may conflict, requiring comparison before a decision."),
                    note(
                        "Harbor Inventory", .draftProject, 0, "Find the definition of the harbor article inventory code and the reasons for a delayed shipment."
                    ),
                ]),
            scenario(
                "source-04", .heldout, "source-lookup", "Where does the invented paper Willow on Memory qualify its claim?",
                "The invented source's qualification is direct; memory overview is indirect; hardware advertising is irrelevant.",
                [
                    note(
                        "Willow on Memory", .sourceCorpus, 2,
                        "# Willow on Memory\n\nThe invented paper qualifies its claim: memory may justify a belief only when no defeating information is available."
                    ),
                    note("Memory Overview", .topicKnowledge, 1, "Memory preserves information while sometimes altering its details."),
                    note("Willow Hardware", .draftProject, 0, "The Willow memory device qualifies for a paper rebate claim."),
                ]),
            scenario(
                "concept-01", .development, "concept-aggregation", "Distinguish normative reasons from motivating reasons.",
                "A comparison is direct; a one-sided source discussion is indirect; product labels are irrelevant.",
                [
                    note(
                        "Reasons Distinction", .topicKnowledge, 2,
                        "Normative reasons count in favor of acting, whereas motivating reasons concern the considerations for which a person acts."),
                    note("Motivation Analysis", .sourceCorpus, 1, "Motivating reasons can figure in an explanation of what a person did."),
                    note("Reasons Labels", .draftProject, 0, "Normative Reasons and Motivating Reasons are labels on two unrelated office binders."),
                ]),
            scenario(
                "concept-02", .development, "concept-aggregation", "How do freedom and autonomy differ?",
                "A comparison is direct; one-concept background is indirect; printer presets are irrelevant.",
                [
                    note(
                        "Freedom Autonomy", .topicKnowledge, 2,
                        "Freedom can concern the absence of interference; autonomy can concern governing oneself. Their relation requires further argument."),
                    note("Freedom Analysis", .sourceCorpus, 1, "Freedom from interference allows a person to pursue an available course of action."),
                    note("Printer", .draftProject, 0, "Freedom and Autonomy are names of printer presets that differ in page size."),
                ]),
            scenario(
                "concept-03", .heldout, "concept-aggregation", "Clarify the distinction between causal explanation and rational justification.",
                "An explicit comparison is direct; one-sided explanation background is indirect; headings-only labels are irrelevant.",
                [
                    note(
                        "Explanation Justification", .topicKnowledge, 2,
                        "A causal explanation identifies how an event occurred; rational justification concerns whether there was adequate reason for a judgment or action."
                    ),
                    note("Causal Analysis", .sourceCorpus, 1, "A causal explanation may cite mechanisms responsible for an event."),
                    note("Labels", .draftProject, 0, "# Causal explanation and rational justification\n\nThe office closes on Friday."),
                ]),
            scenario(
                "concept-04", .heldout, "concept-aggregation", "Compare constitutive and instrumental value.",
                "The explicit contrast is direct; instrumental value alone is indirect; equipment valuations are irrelevant.",
                [
                    note(
                        "Value Comparison", .topicKnowledge, 2,
                        "Constitutive value belongs to something as a part of a valuable whole; instrumental value belongs to something as a means to another end."
                    ),
                    note("Instrumental Analysis", .sourceCorpus, 1, "Instrumental value depends on a contribution toward a further end."),
                    note("Equipment", .draftProject, 0, "Compare the instrumental equipment value with the constitutive inventory category."),
                ]),
            scenario(
                "work-01", .development, "own-writing", "Continue my earlier argument that responsibility requires an opportunity to respond.",
                "The author's existing argument is direct; general source background is indirect; a task roster is irrelevant.",
                [
                    note(
                        "Earlier Argument", .draftProject, 2,
                        "My argument is that responsibility requires an opportunity to respond: without that opportunity, the demand cannot guide action."),
                    note("Responsibility Analysis", .sourceCorpus, 1, "Responsibility is sometimes assessed by considering an agent's opportunities."),
                    note("Office", .topicKnowledge, 0, "Continue the earlier responsibility roster and respond to the office opportunity newsletter."),
                ]),
            scenario(
                "work-02", .development, "own-writing", "Reuse my distinction between acknowledging a feeling and endorsing it.",
                "The prior draft distinction is direct; background on feeling is indirect; attendance acknowledgment is irrelevant.",
                [
                    note(
                        "Prior Draft", .draftProject, 2,
                        "I distinguish acknowledging a feeling from endorsing it. Acknowledgment admits that the feeling occurs without treating it as justified."
                    ),
                    note("Feeling Analysis", .sourceCorpus, 1, "A feeling can occur even when its subject judges it inappropriate."),
                    note("Attendance", .topicKnowledge, 0, "Reuse the acknowledging form by endorsing attendance at the Feeling workshop."),
                ]),
            scenario(
                "work-03", .heldout, "own-writing", "Find my previous objection to equating confidence with evidence.",
                "The writer's existing objection is direct; source background is indirect; marketing confidence is irrelevant.",
                [
                    note(
                        "Previous Objection", .draftProject, 2,
                        "My objection to equating confidence with evidence is that confidence may increase without any new information."),
                    note("Evidence Analysis", .sourceCorpus, 1, "Evidence can change the rational confidence appropriate to a belief."),
                    note("Marketing", .topicKnowledge, 0, "Find the previous Confidence campaign and evidence folder before logging an objection ticket."),
                ]),
            scenario(
                "work-04", .heldout, "own-writing", "Develop the example from my draft about choosing under uncertainty.",
                "The writer's existing example is direct; general background is indirect; file selection is irrelevant.",
                [
                    note(
                        "Draft Example", .draftProject, 2,
                        "My draft example describes choosing under uncertainty between two routes when the reliability of each report is unknown."),
                    note("Uncertainty Analysis", .sourceCorpus, 1, "Uncertainty may concern the outcome of an available action."),
                    note("File Dialog", .topicKnowledge, 0, "Develop the draft dialog for choosing a file named Uncertainty."),
                ]),
            scenario(
                "duplicate-01", .development, "duplicate-material", "agency control reasons",
                "Copies are relevant but redundant; a distinct conceptual distinction provides additional material.",
                [
                    note("Original", .sourceCorpus, 2, "Agency involves control guided by reasons that the agent can consider.", group: "same-excerpt"),
                    note("Copied", .topicKnowledge, 2, "Agency involves control guided by reasons that the agent can consider.", group: "same-excerpt"),
                    note("Alternative", .draftProject, 2, "Agency and control come apart when reasons are recognized but execution fails."),
                    note("Unrelated", .sourceCorpus, 0, "The shipping agency control code records reasons for a delayed parcel."),
                ]),
            scenario(
                "duplicate-02", .development, "duplicate-material", "deliberation options choice",
                "Formatting variants repeat one passage; a distinct limitation adds useful material.",
                [
                    note("Original", .sourceCorpus, 2, "Deliberation compares options before a choice is made.", group: "same-excerpt"),
                    note("Formatted", .topicKnowledge, 2, "**Deliberation** compares options before a choice is made.", group: "same-excerpt"),
                    note("Limit", .draftProject, 2, "Deliberation can overlook options, so a choice may rest on an incomplete comparison."),
                    note("Menu", .sourceCorpus, 0, "Deliberation is a restaurant menu with options for a Choice delivery service."),
                ]),
            scenario(
                "duplicate-03", .heldout, "duplicate-material", "belief evidence revision",
                "Copies are relevant but redundant; a new evidential qualification adds value.",
                [
                    note(
                        "Original", .sourceCorpus, 2, "Belief revision should respond to evidence that undermines an earlier judgment.", group: "same-excerpt"),
                    note("Copied", .draftProject, 2, "Belief revision should respond to evidence that undermines an earlier judgment.", group: "same-excerpt"),
                    note("Qualification", .topicKnowledge, 2, "Belief revision also depends on whether apparent evidence is itself trustworthy."),
                    note("Archive", .sourceCorpus, 0, "Belief is the archive folder containing evidence of a brochure revision."),
                ]),
            scenario(
                "duplicate-04", .heldout, "duplicate-material", "emotion appraisal situation",
                "Near-identical passages are redundant; a distinct question about appraisal is useful.",
                [
                    note(
                        "Original", .sourceCorpus, 2, "An emotion may involve an appraisal of a situation as significant for the subject.",
                        group: "near-excerpt"),
                    note(
                        "Near Copy", .topicKnowledge, 2, "An emotion may involve an appraisal of the situation as significant for its subject.",
                        group: "near-excerpt"),
                    note("Question", .draftProject, 2, "Does emotion require appraisal when the subject cannot articulate why the situation matters?"),
                    note("Estate", .sourceCorpus, 0, "Emotion is the estate agency handling an appraisal of the property situation."),
                ]),
            scenario(
                "language-01", .development, "paraphrase-and-language", "freedom autonomy",
                "A paraphrase and Chinese equivalent are useful despite lacking query words; product presets are irrelevant.",
                [
                    note(
                        "Paraphrase", .topicKnowledge, 2,
                        "Self-government concerns directing one's own life rather than submitting to another person's control."),
                    note("Chinese", .sourceCorpus, 2, "自由与自主涉及行动空间以及个人如何决定自己的生活。"),
                    note("Printer", .draftProject, 0, "Freedom and Autonomy are two printer preset names."),
                ]),
            scenario(
                "language-02", .development, "paraphrase-and-language", "必要条件和充分条件有什么区别",
                "English and Chinese explanations directly address the distinction; delivery conditions are unrelated.",
                [
                    note(
                        "English", .topicKnowledge, 2, "A necessary condition must hold for an outcome, whereas a sufficient condition guarantees the outcome."),
                    note("Chinese", .sourceCorpus, 2, "必要条件不可缺少；充分条件一旦成立就足以保证结果。"),
                    note("Delivery", .draftProject, 0, "配送条件要求填写地址，并说明两个快递选项有什么区别。"),
                ]),
            scenario(
                "language-03", .heldout, "paraphrase-and-language", "acting against better judgment",
                "Akrasia and the Chinese paraphrase address the question; a theatre review does not.",
                [
                    note("Akrasia", .topicKnowledge, 2, "Akrasia occurs when a person does what they themselves consider the worse option."),
                    note("Chinese", .sourceCorpus, 2, "意志薄弱的例子是一个人明知另一个选项更好，却仍然选择较差的行动。"),
                    note("Theatre", .draftProject, 0, "Acting against Better Judgment is a theatre booking code."),
                ]),
            scenario(
                "language-04", .heldout, "paraphrase-and-language", "情绪是否具有认知内容",
                "The English and Chinese discussions address emotional content; product branding does not.",
                [
                    note("English", .topicKnowledge, 2, "Can an emotion represent an object as dangerous even without an explicit belief about danger?"),
                    note("Chinese", .sourceCorpus, 2, "情绪可能把对象呈现为危险的，这引出了它是否具有认知内容的问题。"),
                    note("Product", .draftProject, 0, "情绪是一款笔记本电脑的型号，认知内容是其广告栏名称。"),
                ]),
            scenario(
                "empty-01", .development, "no-useful-material", "supererogation demandingness",
                "The corpus contains no material relevant to this philosophical question.",
                [
                    note("Plants", .sourceCorpus, 0, "The garden contains green leaves and yellow flowers."),
                    note("Calendar", .topicKnowledge, 0, "The office closes at five on Friday."),
                    note("Recipe", .draftProject, 0, "Mix flour with water before baking bread."),
                ]),
            scenario(
                "empty-02", .development, "no-useful-material", "autonomy deliberation",
                "Only metadata and code mention the query; there is no relevant authored prose.",
                [
                    note("Metadata", .sourceCorpus, 0, "---\nkeywords: [autonomy, deliberation]\n---\n\nThe garden contains green leaves."),
                    note("Code", .topicKnowledge, 0, "```text\nautonomy deliberation\n```\n\nThe office closes on Friday."),
                    note("Recipe", .draftProject, 0, "Mix flour with water before baking bread."),
                ]),
            scenario(
                "empty-03", .heldout, "no-useful-material", "counterfactual epistemology",
                "No useful source exists; an empty recommendation is appropriate.",
                [
                    note("Tickets", .sourceCorpus, 0, "The train tickets are stored in the blue envelope."),
                    note("Garden", .topicKnowledge, 0, "Water the flowers before the afternoon heat."),
                    note("Dinner", .draftProject, 0, "Dinner will be served after the guests arrive."),
                ]),
            scenario(
                "empty-04", .heldout, "no-useful-material", "intentionality representation",
                "A heading and link destination are labels without relevant authored prose.",
                [
                    note("Heading", .sourceCorpus, 0, "# Intentionality representation\n\nThe train leaves at noon."),
                    note("Destination", .topicKnowledge, 0, "See [[intentionality representation|travel itinerary]] for the platform number."),
                    note("Dinner", .draftProject, 0, "Dinner will be served after the guests arrive."),
                ]),
        ]
    }
}
