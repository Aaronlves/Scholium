import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related Material focused excerpt windows")
struct RelatedContentExcerptTests {
    @Test("Late EN and ZH concept clusters retain a fitting qualification", arguments: [false, true])
    func lateConcepts(chinese: Bool) {
        let qualification =
            chinese
            ? "这里不是把自决和归责等同；这两个概念仍需分别论证。"
            : "Autonomy and responsibility do not amount to the same claim; each needs an argument."
        let text =
            (chinese ? "不是。" : "Not. ")
            + String(repeating: chinese ? "这里是无关的背景。" : "Unrelated background. ", count: 40)
            + qualification
        let terms = chinese ? ["不是", "自决", "归责"] : ["not", "autonomy", "responsibility"]
        let result = preview(text, terms: terms)
        #expect(result.text.contains(qualification))
        #expect(result.text.hasPrefix("…"))
        checkHighlights(result, source: text, terms: terms)
    }

    @Test("A wide cluster fitting the window wins over the early lone term")
    func wideCluster() {
        var text = "not " + String(repeating: "x ", count: 248)
        #expect(text.count == 500)
        text += "autonomy" + String(repeating: " ", count: 202) + "responsibility"
        let result = preview(text, terms: ["not", "autonomy", "responsibility"])
        #expect(result.text.contains("autonomy"))
        #expect(result.text.contains("responsibility"))
        #expect(result.text.count <= 242)
        checkHighlights(result, source: text, terms: ["not", "autonomy", "responsibility"])
    }

    @Test("A wide qualified paragraph retains its exact source behind the bounded excerpt")
    func wideQualificationSource() throws {
        let text =
            String(repeating: ".", count: 476) + "It is not the case that autonomy and "
            + String(repeating: ".", count: 197) + "responsibility are identical; this is an objection."
        let vault = UUID()
        let document = NoteDocument(relativePath: "Context.md", rawContent: text)
        let candidate = RelatedContentCandidate(
            note: .init(vaultID: vault, relativePath: document.relativePath), vaultRole: .topicKnowledge,
            title: "Context", fingerprint: document.fingerprint,
            reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
        let request = RelatedContentRequest(
            seed: .init(
                noteID: .init(vaultID: vault, relativePath: "Active.md"), source: "autonomy responsibility",
                focuses: [.init(kind: .selectedPassage, text: "autonomy responsibility")]))
        let passages = try TriptychSearchIndex.relatedPassages(request, sources: [.init(candidate: candidate, document: document)])
        let passage = try #require(passages.first)
        #expect(passage.source == text)
        #expect(passage.range.utf16LowerBound == 0)
        #expect(passage.range.utf16UpperBound == text.utf16.count)
        #expect(passage.excerpt.hasPrefix("…"))
        #expect(passage.excerpt.contains("autonomy"))
        #expect(passage.excerpt.contains("responsibility"))
        // The fixed crop cannot promise every qualification for a wide cluster;
        // its checked paragraph remains the complete object for source opening.
        #expect(passage.excerpt.count <= 242)
    }

    @Test("Repeated common language cannot outrank distinct concepts")
    func distinctBeforeRepeated() {
        let text =
            String(repeating: "not ", count: 70) + String(repeating: "background ", count: 30)
            + "Autonomy and responsibility remain distinct."
        let result = preview(text, terms: ["not", "autonomy", "responsibility"])
        #expect(result.text.contains("Autonomy and responsibility"))
    }

    @Test("Saturated repeat ties retain the earlier cluster and equivalent terms add no weight")
    func saturatedAndEquivalent() {
        let text =
            "Agency agency autonomy form the first cluster. " + String(repeating: "background ", count: 40)
            + String(repeating: "agency ", count: 50) + "autonomy forms the later cluster."
        let result = preview(text, terms: ["agency", "autonomy"])
        #expect(result.text.contains("first cluster"))
        #expect(result.text == preview(text, terms: ["AGENCY", "agency", "autonomy", "autonomy"]).text)
    }

    @Test("Complete-text highlights retain Unicode source graphemes")
    func unicodeOffsets() throws {
        let text = String(repeating: "Background 🦉. ", count: 40) + "cafe\u{301}\r\n\tﬃ and λόγος. 👨‍👩‍👧‍👦"
        let result = preview(text, terms: ["cafe", "ffi", "λογοσ"])
        let highlighted = try result.ranges.map { range in
            let indices = try #require(Range(NSRange(location: range.lowerBound, length: range.count), in: result.text))
            return String(result.text[indices])
        }
        #expect(Set(highlighted) == ["cafe\u{301}", "ﬃ", "λόγος"])
        #expect(result.text.contains("👨‍👩‍👧‍👦"))
        checkHighlights(result, source: text, terms: ["cafe", "ffi", "λογοσ"])
    }

    @Test("Focus owns the window; source terms are used only without focused matches")
    func sourceFallback() {
        let text =
            "Seed material appears here. " + String(repeating: "background ", count: 40)
            + "Autonomy and responsibility belong here."
        let source: [RelatedContentSeedTermMatch] = [.init(seedKind: .sourceNote, terms: ["seed", "material"])]
        let focused = source + [.init(seedKind: .selectedPassage, terms: ["autonomy", "responsibility"])]
        #expect(TriptychSearchIndex.relatedExcerpt(text, matches: source).text.contains("Seed material"))
        #expect(TriptychSearchIndex.relatedExcerpt(text, matches: focused).text.contains("Autonomy and responsibility"))
    }

    @Test("No visible complete match uses a bounded prefix without fabricated highlights")
    func emptyAndOversized() {
        for text in ["", "A short unrelated sentence.", String(repeating: "x", count: 300)] {
            let result = preview(text, terms: [String(repeating: "x", count: 300), "absent"])
            #expect(result.text == String(text.prefix(240)) + (text.count > 240 ? "…" : ""))
            #expect(result.ranges.isEmpty)
        }
    }

    @Test("Cropping inside an attached run cannot create a highlight for its suffix")
    func croppedBoundary() {
        let text =
            "agency " + String(repeating: "x", count: 593) + "agency" + String(repeating: " ", count: 103)
            + "autonomy responsibility " + String(repeating: "background ", count: 30)
        let result = preview(text, terms: ["agency", "autonomy", "responsibility"])
        checkHighlights(result, source: text, terms: ["agency", "autonomy", "responsibility"])
        #expect(result.text.hasPrefix("…agency"))
        #expect(result.ranges.count == 2)
        #expect(result.text.contains("autonomy responsibility"))
        #expect(result.text.count <= 242)
    }

    private func preview(_ text: String, terms: [String]) -> (text: String, ranges: [Range<Int>]) {
        TriptychSearchIndex.relatedExcerpt(text, matches: [.init(seedKind: .selectedPassage, terms: terms)])
    }

    private func checkHighlights(_ preview: (text: String, ranges: [Range<Int>]), source: String, terms: [String]) {
        let content = preview.text.dropFirst(preview.text.hasPrefix("…") ? 1 : 0)
            .dropLast(preview.text.hasSuffix("…") ? 1 : 0)
        #expect(source.contains(content))
        #expect(preview.ranges.count <= 64)
        for range in preview.ranges {
            guard let indices = Range(NSRange(location: range.lowerBound, length: range.count), in: preview.text) else {
                Issue.record("Highlight is outside the excerpt or splits a Character")
                continue
            }
            let literal = SearchTextNormalization.lexicalNormalize(String(preview.text[indices]))
            #expect(terms.map(SearchTextNormalization.lexicalNormalize).contains(literal))
        }
    }
}
