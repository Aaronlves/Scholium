import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

struct ResearchCompactExcerptTests {
    @Test("Caller budgets bound the source slice while retaining a late anchor", arguments: [40, 80, 180])
    func configurableBudget(limit: Int) throws {
        let source =
            String(repeating: "earlier context ", count: 30) + "late anchor "
            + String(repeating: "following context ", count: 30)
        let excerpt = ResearchCompactExcerpt(
            text: source, matches: [try range(of: "anchor", in: source)], characterLimit: limit)

        #expect(sourceSlice(of: excerpt).count <= limit)
        #expect(try highlightedText(in: excerpt) == ["anchor"])
        #expect(source.contains(sourceSlice(of: excerpt)))
    }

    @Test("Invalid budgets clamp to one grapheme", arguments: [0, -1, Int.min])
    func minimumBudget(limit: Int) throws {
        let excerpt = ResearchCompactExcerpt(text: "abc", matches: [1..<2], characterLimit: limit)

        #expect(excerpt.text == "… b …")
        #expect(try highlightedText(in: excerpt) == ["b"])
    }

    @Test("Compact windows prefer late distinct matches to early repeated wording", arguments: [false, true])
    func distinctMatchCoverage(chinese: Bool) throws {
        let repeated = chinese ? "不是" : "not"
        let concepts = chinese ? ["自决", "归责"] : ["Autonomy", "responsibility"]
        let qualification =
            chinese ? "自决和归责并不等同，仍需分别论证。" : "Autonomy and responsibility remain distinct."
        let source =
            (chinese ? "不是。不是。不是。" : "not not not. ")
            + String(repeating: chinese ? "背景" : "context ", count: chinese ? 90 : 22)
            + qualification
        let supplied = allRanges(of: repeated, in: source) + (try concepts.map { try range(of: $0, in: source) })
        let excerpt = ResearchCompactExcerpt(text: source, matches: supplied)

        #expect(excerpt.text.contains(qualification))
        #expect(try highlightedText(in: excerpt) == concepts)
        #expect(sourceSlice(of: excerpt).count <= 180)
        #expect(source.contains(sourceSlice(of: excerpt)))
    }

    @Test("Equivalent supplied matches share canonical lexical identity")
    func equivalentMatchIdentity() throws {
        let repeated = ["CAFÉ", "café", "cafe\u{301}"]
        let concepts = ["自决", "归责"]
        let source = repeated.joined(separator: " ") + ". " + String(repeating: "背景", count: 90) + "自决和归责仍有区别。"
        let supplied = try (repeated + concepts).map { term in
            let range = try #require(source.range(of: term, options: .literal))
            let utf16 = NSRange(range, in: source)
            return utf16.location..<NSMaxRange(utf16)
        }
        let excerpt = ResearchCompactExcerpt(text: source, matches: supplied)

        #expect(excerpt.text.contains("自决和归责仍有区别。"))
        #expect(try highlightedText(in: excerpt) == concepts)
    }

    @Test("Sentence preference cannot discard a fitting distinct match cluster")
    func retainsClusterAcrossSentences() throws {
        let source = "Autonomy.\nAn intervening qualification.\nResponsibility remains distinct."
        let terms = ["Autonomy", "Responsibility"]
        let excerpt = ResearchCompactExcerpt(text: source, matches: try terms.map { try range(of: $0, in: source) })

        #expect(excerpt.text == source)
        #expect(!excerpt.isOmitted)
        #expect(try highlightedText(in: excerpt) == terms)
    }

    @Test("A supplied match larger than the budget never becomes a partial witness")
    func noPartialMatchHighlight() throws {
        let source = "Earlier prose. abcdefghijklmnopqrstuvwxyz follows."
        let excerpt = ResearchCompactExcerpt(
            text: source, matches: [try range(of: "abcdefghijklmnopqrstuvwxyz", in: source)], characterLimit: 8)

        #expect(sourceSlice(of: excerpt).count <= 8)
        #expect(source.contains(sourceSlice(of: excerpt)))
        #expect(excerpt.text.contains("abcdefgh"))
        #expect(excerpt.matches.isEmpty)
    }

    @Test("Repeated labels focus the authored late link without highlighting either label")
    func authoredRepeatedLabelFocus() throws {
        let source =
            "Target stands here. " + String(repeating: "Earlier context remains available. ", count: 15)
            + "The authored [[Target]] qualifies this claim."
        let occurrence = try #require(links(in: source).first)
        let passage = ResearchLinkPassage(occurrence: occurrence)
        let excerpt = ResearchCompactExcerpt(text: passage.text, matches: passage.focus)
        let lastLabel = try #require(passage.text.range(of: "Target", options: .backwards))
        let expected = NSRange(lastLabel, in: passage.text)

        #expect(passage.focus == [expected.location..<NSMaxRange(expected)])
        #expect(passage.highlights.isEmpty)
        #expect(excerpt.text.contains("The authored Target qualifies this claim."))
        #expect(!excerpt.text.contains("Target stands here."))
        #expect(passage.text == ResearchExcerptPresentation.readableText(occurrence.localContext))
    }

    @Test("Repeated authored links retain distinct focus positions")
    func repeatedAuthoredOccurrences() throws {
        let occurrences = links(in: "[[Target|Same]] occurs first, while [[Target|Same]] occurs second.")
        #expect(occurrences.count == 2)
        let first = ResearchLinkPassage(occurrence: try #require(occurrences.first))
        let second = ResearchLinkPassage(occurrence: try #require(occurrences.last))
        let lastLabel = try #require(second.text.range(of: "Same", options: .backwards))
        let expected = NSRange(lastLabel, in: second.text)

        #expect(first.text == second.text)
        #expect(first.focus != second.focus)
        #expect(first.focus.first?.lowerBound == 0)
        #expect(second.focus == [expected.location..<NSMaxRange(expected)])
        #expect(first.highlights.isEmpty && second.highlights.isEmpty)
    }

    @Test("Unicode offsets and multiline annotations preserve the visible alias focus")
    func annotatedUnicodeAliasFocus() throws {
        let source = "An earlier line.\n👩🏽‍🔬 cafe\u{301} 前文 [[目标#章节|自由👩🏽‍🔬]]{{第一行解释\n第二行 [[隐藏]]。}} 后文。"
        let occurrence = try #require(links(in: source).first { $0.target == "目标" })
        let passage = ResearchLinkPassage(occurrence: occurrence)
        let expected = try range(of: "自由👩🏽‍🔬", in: passage.text)

        #expect(passage.text == "👩🏽‍🔬 cafe\u{301} 前文 自由👩🏽‍🔬 后文。")
        #expect(passage.focus == [expected])
        #expect(passage.highlights == [expected])
        #expect(passage.text == ResearchExcerptPresentation.readableText(occurrence.localContext))
        #expect(occurrence.annotation?.markdown.contains("第二行 [[隐藏]]") == true)
    }

    @Test("Ordinary Markdown aliases focus the rendered wording across lines")
    func renderedMarkdownAliasFocus() throws {
        let source = "A preceding line.\n前文 [**visible**\nlabel](https://example.com) follows."
        let occurrence = try #require(links(in: source).first)
        let passage = ResearchLinkPassage(occurrence: occurrence)
        let expected = try range(of: "visible\nlabel", in: passage.text)

        #expect(passage.text == "前文 visible\nlabel follows.")
        #expect(passage.focus == [expected])
        #expect(passage.highlights == [expected])
    }

    @Test("A literal marker-like phrase does not compete with the authored link")
    func markerCollision() throws {
        let occurrence = try #require(links(in: "ScholiumLinkPassageAnchor precedes [[Target]].").first)
        let passage = ResearchLinkPassage(occurrence: occurrence)

        #expect(passage.focus == [try range(of: "Target", in: passage.text)])
        #expect(passage.text == "ScholiumLinkPassageAnchor precedes Target.")
    }

    @Test("An occurrence hidden within a separately shown annotation has no invented focus")
    func hiddenAnnotationLinkHasNoFocus() throws {
        let occurrence = try #require(
            links(in: "Before [[Outer]]{{This [[Inner]] stays in the annotation.}} after.")
                .first { $0.target == "Inner" })
        let passage = ResearchLinkPassage(occurrence: occurrence)

        #expect(passage.text == "Before Outer after.")
        #expect(passage.focus.isEmpty && passage.highlights.isEmpty)
    }

    @Test("A context that no longer proves its stored occurrence keeps text but no focus")
    func mismatchedContextHasNoFocus() throws {
        let original = try #require(links(in: "Before [[Target|label]] after.").first)
        let changed = LinkOccurrence(
            syntax: original.syntax, target: original.target, alias: original.alias, fragment: original.fragment,
            localContext: "Before [[Other|label]] after.", isExternal: original.isExternal,
            span: original.span, linkSpan: original.linkSpan)
        let passage = ResearchLinkPassage(occurrence: changed)

        #expect(passage.text == "Before label after.")
        #expect(passage.focus.isEmpty && passage.highlights.isEmpty)
    }

    @Test("Short readable text and its whitespace remain exact")
    func preservesShortText() throws {
        let source = "  This is not\t evidence.\nIt is a question.  "
        let match = try range(of: "evidence", in: source)
        let excerpt = ResearchCompactExcerpt(text: source, matches: [match])

        #expect(excerpt.text == source)
        #expect(excerpt.matches == [match])
        #expect(!excerpt.isOmitted)
    }

    @Test("Late matches retain their following qualification as two exact sentences")
    func selectsLateSentences() throws {
        let background = String(repeating: "Historical detail remains elsewhere. ", count: 12)
        let passage = "The result is not necessary.\n\tIt holds only under this assumption."
        let source = background + passage + " Later examples concern a different question."
        let excerpt = ResearchCompactExcerpt(text: source, matches: [try range(of: "necessary", in: source)])

        #expect(excerpt.text == "… " + passage + " …")
        #expect(excerpt.isOmitted)
        #expect(try highlightedText(in: excerpt) == ["necessary"])
        #expect(excerpt.text.contains("not necessary"))
    }

    @Test("One complete long sentence is preferred to an incomplete neighboring sentence")
    func selectsOneSentence() throws {
        let before = String(repeating: "Earlier context ", count: 20) + "ends here. "
        let passage =
            "This carefully delimited account makes the central claim conditional on the stated assumptions and leaves all contrary evidence available for examination."
        let after = " " + String(repeating: "Later context ", count: 20) + "ends here."
        let source = before + passage + after
        let excerpt = ResearchCompactExcerpt(text: source, matches: [try range(of: "conditional", in: source)])

        #expect(excerpt.text == "… " + passage + " …")
        #expect(try highlightedText(in: excerpt) == ["conditional"])
    }

    @Test("A short passage contains at most two sentences even when three would fit")
    func limitsSentenceCount() {
        let excerpt = ResearchCompactExcerpt(text: "First sentence. Second sentence. Third sentence.")

        #expect(excerpt.text == "First sentence. Second sentence. …")
        #expect(excerpt.isOmitted)
    }

    @Test("Long sentences keep a late match and nearby negation inside word boundaries")
    func boundsLongSentence() throws {
        let source =
            String(repeating: "background reasoning ", count: 30)
            + "not merely necessary under these assumptions "
            + String(repeating: "further discussion ", count: 30) + "."
        let excerpt = ResearchCompactExcerpt(text: source, matches: [try range(of: "necessary", in: source)])
        let slice = sourceSlice(of: excerpt)

        #expect(excerpt.text.hasPrefix("… ") && excerpt.text.hasSuffix(" …"))
        #expect(slice.count <= 180)
        #expect(source.contains(slice))
        #expect(slice.contains("not merely necessary"))
        #expect(try highlightedText(in: excerpt) == ["necessary"])
        let sourceRange = try #require(source.range(of: slice))
        #expect(source[source.index(before: sourceRange.lowerBound)].isWhitespace)
        #expect(source[sourceRange.upperBound].isWhitespace)
    }

    @Test("A nearly full-width match keeps a small leading negation when it fits")
    func preservesLeadingQualificationAtBudget() throws {
        let matchedWord = String(repeating: "x", count: 168)
        let source =
            String(repeating: "background ", count: 20) + "not merely " + matchedWord
            + String(repeating: " further context", count: 20)
        let excerpt = ResearchCompactExcerpt(text: source, matches: [try range(of: matchedWord, in: source)])

        #expect(excerpt.text.contains("not merely " + matchedWord))
        #expect(sourceSlice(of: excerpt).count <= 180)
        #expect(try highlightedText(in: excerpt) == [matchedWord])
    }

    @Test("Omission markers identify only the boundaries that omit source")
    func identifiesBoundaryOmissions() throws {
        let source = "Anchor begins " + String(repeating: "a lengthy discussion ", count: 30) + "finalword"
        let beginning = ResearchCompactExcerpt(text: source, matches: [try range(of: "Anchor", in: source)])
        let ending = ResearchCompactExcerpt(text: source, matches: [try range(of: "finalword", in: source)])

        #expect(!beginning.text.hasPrefix("… ") && beginning.text.hasSuffix(" …"))
        #expect(ending.text.hasPrefix("… ") && !ending.text.hasSuffix(" …"))
        #expect(try highlightedText(in: beginning) == ["Anchor"])
        #expect(try highlightedText(in: ending) == ["finalword"])
    }

    @Test("Mixed Chinese, emoji and combining characters retain valid UTF-16 highlights")
    func preservesUnicode() throws {
        let background = String(repeating: "这是较早的背景材料。", count: 30)
        let passage = "这个结论并不意味着自由👩🏽‍🔬。\n“cafe\u{301}”仍然保留其原有形式。"
        let source = background + passage + "后续问题需要进一步考察。"
        let excerpt = ResearchCompactExcerpt(
            text: source,
            matches: [
                try range(of: "自由", in: source), try range(of: "👩🏽‍🔬", in: source),
                try range(of: "cafe\u{301}", in: source),
            ])

        #expect(excerpt.text == "… " + passage + " …")
        #expect(try highlightedText(in: excerpt) == ["自由", "👩🏽‍🔬", "cafe\u{301}"])
        #expect(source.contains(sourceSlice(of: excerpt)))
    }

    @Test("Malformed ranges neither crash nor displace the first valid match")
    func rejectsInvalidRanges() throws {
        let source =
            "👩🏽‍🔬 " + String(repeating: "Earlier material. ", count: 20)
            + "A valid anchor appears here. Its qualification follows."
        let valid = try range(of: "anchor", in: source)
        let excerpt = ResearchCompactExcerpt(
            text: source, matches: [-2..<1, 0..<1, 0..<2, 4..<4, Int.max - 1..<Int.max, valid])

        #expect(excerpt.text.contains("A valid anchor appears here. Its qualification follows."))
        #expect(try highlightedText(in: excerpt) == ["anchor"])
        #expect(excerpt.text.hasPrefix("… "))
    }

    @Test("A very long single word uses an explicitly omitted grapheme slice")
    func boundsUnbrokenToken() throws {
        let source = String(repeating: "a", count: 400) + "needle" + String(repeating: "b", count: 400)
        let excerpt = ResearchCompactExcerpt(text: source, matches: [try range(of: "needle", in: source)])

        #expect(sourceSlice(of: excerpt).count <= 180)
        #expect(source.contains(sourceSlice(of: excerpt)))
        #expect(excerpt.text.hasPrefix("… ") && excerpt.text.hasSuffix(" …"))
        #expect(try highlightedText(in: excerpt) == ["needle"])
    }

    @Test("Bounds never split an extended emoji grapheme")
    func preservesGraphemeBoundaries() throws {
        let cluster = "👩🏽‍🔬"
        let source = String(repeating: cluster, count: 400)
        let lower = cluster.utf16.count * 350
        let excerpt = ResearchCompactExcerpt(text: source, matches: [lower..<(lower + cluster.utf16.count)])
        let slice = sourceSlice(of: excerpt)

        #expect(slice.count <= 180)
        #expect(slice.allSatisfy { String($0) == cluster })
        #expect(try highlightedText(in: excerpt) == [cluster])
        #expect(excerpt.isOmitted)
    }

    @Test("Abbreviations and quoted wording remain part of an exact source slice")
    func preservesQuotedWording() throws {
        let source =
            String(repeating: "Earlier context. ", count: 20)
            + "Dr. Smith wrote, “It is not established.” The claim remains conditional."
        let excerpt = ResearchCompactExcerpt(text: source, matches: [try range(of: "established", in: source)])

        #expect(excerpt.text.contains("“It is not established.”"))
        #expect(source.contains(sourceSlice(of: excerpt)))
        #expect(try highlightedText(in: excerpt) == ["established"])
    }

    @Test("Empty text and invalid-only matches produce a safe initial excerpt")
    func emptyAndUnmatched() {
        let empty = ResearchCompactExcerpt(text: "", matches: [0..<1])
        #expect(empty.text.isEmpty && empty.matches.isEmpty && !empty.isOmitted)
        let source = String(repeating: "unmatched prose ", count: 30)
        let unmatched = ResearchCompactExcerpt(text: source, matches: [-2..<0, 2..<2])
        #expect(unmatched.matches.isEmpty)
        #expect(!unmatched.text.hasPrefix("… ") && unmatched.text.hasSuffix(" …"))
        #expect(source.hasPrefix(sourceSlice(of: unmatched)))
    }

    private func range(of text: String, in source: String) throws -> Range<Int> {
        let range = try #require(source.range(of: text))
        let utf16 = NSRange(range, in: source)
        return utf16.location..<NSMaxRange(utf16)
    }

    private func allRanges(of text: String, in source: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var cursor = source.startIndex
        while cursor < source.endIndex, let range = source.range(of: text, range: cursor..<source.endIndex) {
            let utf16 = NSRange(range, in: source)
            ranges.append(utf16.location..<NSMaxRange(utf16))
            cursor = range.upperBound
        }
        return ranges
    }

    private func links(in source: String) -> [LinkOccurrence] {
        MarkdownSemanticDocument(parsing: NoteDocument(relativePath: "fixture.md", rawContent: source)).links
    }

    private func highlightedText(in excerpt: ResearchCompactExcerpt) throws -> [String] {
        try excerpt.matches.map { match in
            let range = try #require(Range(NSRange(location: match.lowerBound, length: match.count), in: excerpt.text))
            return String(excerpt.text[range])
        }
    }

    private func sourceSlice(of excerpt: ResearchCompactExcerpt) -> String {
        var text = excerpt.text
        if text.hasPrefix("… ") { text.removeFirst(2) }
        if text.hasSuffix(" …") { text.removeLast(2) }
        return text
    }
}
