import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

/// Generated judgments exercise retrieval behavior, not researcher acceptance.
/// A useful Note here means only that its authored paragraph addresses the
/// fixture's stated topic; neither stance nor evidential role is inferred.
@Suite("Related content synthetic quality")
struct RelatedContentQualityTests {
    private let vault = UUID(uuidString: "BA88E941-69DD-4AD5-8746-F700A889D154")!

    private struct Judgments {
        let useful: Set<String>
        let irrelevant: Set<String>
    }

    private struct Quality {
        let precision: Double?
        let noteRecall: Double?
        let usefulPassages: Int
        let irrelevantPassages: Int
        let distinctNotes: Int
        let reciprocalRank: Double
    }

    private func source(_ path: String, _ text: String, role: VaultRole = .sourceCorpus) -> RelatedContentSource {
        let document = NoteDocument(relativePath: path, rawContent: text)
        return .init(
            candidate: .init(
                note: .init(vaultID: vault, relativePath: path), vaultRole: role,
                title: path, fingerprint: document.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: []))),
            document: document)
    }

    private func request(focus: String, surroundingText: String = "") -> RelatedContentRequest {
        .init(
            seed: .init(
                noteID: .init(vaultID: vault, relativePath: "Draft.md"),
                source: surroundingText + "\n\n" + focus,
                focuses: [.init(kind: .selectedPassage, text: focus)]))
    }

    private func evaluate(
        _ name: String, request: RelatedContentRequest, sources: [RelatedContentSource], judgments: Judgments
    ) throws -> (passages: [RelatedContentPassage], quality: Quality) {
        #expect(judgments.useful.isDisjoint(with: judgments.irrelevant))
        #expect(Set(sources.map { $0.candidate.note.relativePath }) == judgments.useful.union(judgments.irrelevant))
        let passages = try TriptychSearchIndex.relatedPassages(request, sources: sources)
        // Order may not depend on source traversal or dictionary insertion.
        #expect(try TriptychSearchIndex.relatedPassages(request, sources: sources.reversed()) == passages)
        for passage in passages {
            let original = try #require(sources.first { $0.candidate.note == passage.candidate.note })
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound),
                    in: original.document.rawContent))
            #expect(String(original.document.rawContent[range]) == passage.source)
            #expect(passage.candidate.fingerprint == original.document.fingerprint)
            #expect(passage.range.line == 1 + original.document.rawContent[..<range.lowerBound].utf8.filter { $0 == 10 }.count)
        }
        let retrieved = Set(passages.map { $0.candidate.note.relativePath })
        let useful = passages.filter { judgments.useful.contains($0.candidate.note.relativePath) }.count
        let irrelevant = passages.filter { judgments.irrelevant.contains($0.candidate.note.relativePath) }.count
        let quality = Quality(
            precision: passages.isEmpty ? nil : Double(useful) / Double(passages.count),
            noteRecall: judgments.useful.isEmpty ? nil : Double(retrieved.intersection(judgments.useful).count) / Double(judgments.useful.count),
            usefulPassages: useful, irrelevantPassages: irrelevant, distinctNotes: retrieved.count,
            reciprocalRank: passages.firstIndex { judgments.useful.contains($0.candidate.note.relativePath) }.map { 1.0 / Double($0 + 1) } ?? 0)
        // Empty result precision and empty judgment recall are undefined, not 1.
        print(
            "Synthetic recommendation quality [\(name)]: passages=\(passages.count), "
                + "useful=\(useful), irrelevant=\(irrelevant), distinctNotes=\(quality.distinctNotes), "
                + "precision=\(quality.precision.map { String(format: "%.3f", $0) } ?? "n/a"), "
                + "noteRecall=\(quality.noteRecall.map { String(format: "%.3f", $0) } ?? "n/a"), "
                + "reciprocalRank=\(String(format: "%.3f", quality.reciprocalRank))")
        return (passages, quality)
    }

    @Test("Explicit bilingual focus excludes the surrounding draft's unrelated topic")
    func focusedBilingualRetrieval() throws {
        let sources = [
            source("English.md", "Freedom and autonomy can describe different forms of self-government."),
            source("中文.md", "\u{FEFF}# 概念区分\r\n\r\n自由与自主在这一段中是待比较的概念。\r\n", role: .topicKnowledge),
            source("Garden.md", "Gardening roses requires pruning roses and preparing garden soil."),
            source("Single Word.md", "Freedom is the name of a garden rose cultivar."),
        ]
        let result = try evaluate(
            "explicit bilingual focus", request: request(focus: "freedom autonomy 自由 自主", surroundingText: String(repeating: "gardening roses ", count: 80)),
            sources: sources, judgments: .init(useful: ["English.md", "中文.md"], irrelevant: ["Garden.md", "Single Word.md"]))
        #expect(result.quality.precision == 1)
        #expect(result.quality.noteRecall == 1)
        #expect(
            result.passages.allSatisfy { passage in
                passage.matches.contains { $0.seedKind == .selectedPassage }
            })
    }

    @Test("Metadata-only and code-only topic labels do not count as relevant prose")
    func propertyAndCodeExclusion() throws {
        let result = try evaluate(
            "authored paragraph requirement", request: request(focus: "freedom autonomy"),
            sources: [
                source("Useful.md", "Freedom and autonomy are compared in the authored discussion."),
                source("Keywords.md", "---\nkeywords: [freedom, autonomy]\nsummary: freedom autonomy\n---\n\nThe specimen has green leaves."),
                source("Code.md", "```text\nfreedom autonomy\n```\n\nThe specimen has yellow leaves."),
                source("Heading.md", "# Freedom autonomy\n\nThe specimen has red leaves."),
            ],
            judgments: .init(useful: ["Useful.md"], irrelevant: ["Keywords.md", "Code.md", "Heading.md"]))
        #expect(result.quality.precision == 1)
        #expect(result.quality.noteRecall == 1)
    }

    @Test("Annotation relevance belongs to its authoring Note and never its link target")
    func annotationAttribution() throws {
        let result = try evaluate(
            "annotation ownership", request: request(focus: "freedom autonomy"),
            sources: [
                source("Annotator.md", "Read [[Target]]{{freedom autonomy need separate definitions}} before continuing."),
                source("Target.md", "This passage catalogs green leaves and flower stems."),
                source("Destination.md", "Consult [[freedom autonomy|botanical inventory]] for specimen numbers."),
            ], judgments: .init(useful: ["Annotator.md"], irrelevant: ["Target.md", "Destination.md"]))
        #expect(result.quality.precision == 1)
        #expect(result.quality.noteRecall == 1)
        #expect(result.passages.first?.source.contains("{{freedom autonomy") == true)
    }

    @Test("Long Notes and duplicate paragraphs cannot crowd out distinct relevant Notes")
    func noteDiversity() throws {
        let repeated = "Freedom and autonomy are compared through the example of voting."
        let result = try evaluate(
            "note diversity", request: request(focus: "freedom autonomy"),
            sources: [
                source(
                    "Long.md",
                    ([repeated, repeated] + (1...7).map { "Freedom autonomy discussion number \($0) considers another case." }).joined(separator: "\n\n")),
                source("Alternative.md", "Freedom autonomy comparison considers collective decisions.", role: .topicKnowledge),
                source("Objection.md", "Freedom autonomy comparison raises a distinct objection."),
                source("Distinction.md", "Freedom autonomy comparison separates two definitions."),
                source("Unrelated.md", "The botanical specimen blooms in summer."),
            ],
            judgments: .init(useful: ["Long.md", "Alternative.md", "Objection.md", "Distinction.md"], irrelevant: ["Unrelated.md"]))
        #expect(result.quality.precision == 1)
        #expect(result.quality.noteRecall == 1)
        #expect(Set(result.passages.prefix(4).map { $0.candidate.note }).count == 4)
        #expect(result.passages.filter { $0.candidate.note.relativePath == "Long.md" }.count <= 2)
        #expect(result.passages.filter { $0.source == repeated }.count <= 1)
    }

    @Test("No matching material yields no recommendation and no invented quality score")
    func noMatch() throws {
        let result = try evaluate(
            "no match", request: request(focus: "freedom autonomy"),
            sources: [source("Botany.md", "Plants have green leaves."), source("植物.md", "植物拥有绿色的叶子。")],
            judgments: .init(useful: [], irrelevant: ["Botany.md", "植物.md"]))
        #expect(result.passages.isEmpty)
        #expect(result.quality.precision == nil)
        #expect(result.quality.noteRecall == nil)
        #expect(result.quality.irrelevantPassages == 0)
    }

    @Test("Complete focus coverage outranks a repeated two-term annotation")
    func distinctiveFocusCoverage() throws {
        let focus = "freedom autonomy deliberation responsibility"
        // The broad paragraph addresses all four named concepts. The narrow
        // annotation merely repeats two labels. Metadata-only Notes keep the
        // corpus realistic: many indexed topic labels have no usable paragraph.
        // Judgments are independent of the implementation's BM25F weights.
        let broad = source(
            "Broad.md",
            "Freedom and autonomy concern how a person governs an action, while deliberation describes considering alternatives and responsibility concerns answering for the choice. This synthetic paragraph distinguishes the concepts rather than treating them as interchangeable labels, and its remaining words explain why the comparison belongs in a discussion about individual decisions."
        )
        let narrow = source("Repeated.md", "[[Target]]{{" + String(repeating: "freedom autonomy ", count: 8) + "}} Read more.")
        let metadataOnly = (1...10).map {
            source("Metadata\($0).md", "---\nkeywords: [freedom, autonomy, deliberation, responsibility]\n---\n\nGreen specimen leaves.")
        }
        let result = try evaluate(
            "distinctive focus coverage", request: request(focus: focus), sources: [broad, narrow] + metadataOnly,
            judgments: .init(useful: ["Broad.md"], irrelevant: Set(metadataOnly.map { $0.candidate.note.relativePath }).union(["Repeated.md"])))
        #expect(result.passages.first?.candidate.note.relativePath == "Broad.md")
        #expect(result.quality.noteRecall == 1)
    }

    @Test("Within one Note explicit focus prefers broader coverage while source-only retrieval retains field ranking")
    func withinNoteFocusCoverage() throws {
        let focus = "freedom autonomy deliberation responsibility"
        let broad =
            "Freedom and autonomy concern how a person governs an action, while deliberation describes considering alternatives and responsibility concerns answering for the choice. This synthetic paragraph distinguishes the concepts rather than treating them as interchangeable labels, and its remaining words explain why the comparison belongs in a discussion about individual decisions."
        let narrow = "[[Target]]{{" + String(repeating: "freedom autonomy ", count: 8) + "}} Read more."
        let unrelated = (1...10).map { "Green specimen leaves in sample \($0)." }
        let mixed = source("Mixed.md", ([broad, narrow] + unrelated).joined(separator: "\r\n\r\n"))
        let focused = try TriptychSearchIndex.relatedPassages(request(focus: focus), sources: [mixed])
        let sourceOnlyRequest = RelatedContentRequest(
            seed: .init(noteID: .init(vaultID: vault, relativePath: "Draft.md"), source: focus))
        let sourceOnly = try TriptychSearchIndex.relatedPassages(sourceOnlyRequest, sources: [mixed])

        // The assertions identify exact paragraphs independently of scores.
        // This fixture does not label every paragraph in Mixed.md as useful.
        #expect(focused.map(\.source) == [broad, narrow])
        #expect(sourceOnly.map(\.source) == [narrow, broad])
        #expect(Set(focused.map(\.range)) == Set(sourceOnly.map(\.range)))
        for passage in focused + sourceOnly {
            let range = try #require(
                Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound),
                    in: mixed.document.rawContent))
            #expect(String(mixed.document.rawContent[range]) == passage.source)
        }
    }

    @Test("Semantic challenge reports lexical gaps separately from contract acceptance")
    func semanticChallengeDiagnostics() throws {
        // These labels are explicit synthetic judgments. There is deliberately
        // no passing precision/recall threshold for this diagnostic: enforcing
        // the present false positives or misses would freeze a known limitation.
        // Inspect its emitted quality metrics when changing the ranking policy.
        let result = try evaluate(
            "semantic challenge (diagnostic only)", request: request(focus: "freedom autonomy"),
            sources: [
                source("Direct.md", "Freedom and autonomy are contrasted as forms of self-government."),
                source("Paraphrase.md", "Self-determination concerns governing oneself rather than being controlled by another person."),
                source("跨语言.md", "这一段讨论个人自主与免受外部控制的自由。"),
                source("Printer.md", "Freedom and autonomy are the names of two printer configuration presets."),
            ], judgments: .init(useful: ["Direct.md", "Paraphrase.md", "跨语言.md"], irrelevant: ["Printer.md"]))
        // The direct lexical case remains an independent positive anchor even
        // while synonym, cross-language and sense-disambiguation quality evolves.
        #expect(result.passages.contains { $0.candidate.note.relativePath == "Direct.md" })
    }
}
