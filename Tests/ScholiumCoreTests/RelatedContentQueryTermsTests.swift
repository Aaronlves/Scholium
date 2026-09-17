import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Related content complete focus preparation")
struct RelatedContentQueryTermsTests {
    @Test("A long focus samples through its final concepts instead of stopping at its introduction")
    func completeSelection() {
        let introduction = (0..<100).map { "context\($0)" }.joined(separator: " ")
        let value = introduction + " freedom autonomy"
        let terms = RelatedContentQueryTerms.terms(in: value, limit: 32)
        #expect(terms.count == 32)
        #expect(terms.first == "context0")
        #expect(terms.last == "autonomy")
        #expect((40...60).contains { terms.contains("context\($0)") })
        #expect(terms == RelatedContentQueryTerms.terms(in: value, limit: 32))
        #expect(terms != Array(RelatedContentQueryTerms.orderedTokens(in: value).prefix(32)))
    }

    @Test("An unquoted final two-term focus survives a long introduction together")
    func finalConceptPair() {
        let introduction = (0..<100).map { "context\($0)" }.joined(separator: " ")
        for budget in 2...32 {
            let terms = RelatedContentQueryTerms.terms(in: introduction + " freedom autonomy", limit: budget)
            #expect(Array(terms.suffix(2)) == ["freedom", "autonomy"])
            #expect(terms.count == budget)
        }
    }

    @Test("A concluding concept pair remains eligible when both words appeared earlier")
    func repeatedFinalConcepts() {
        let context = (0..<100).map { "context\($0)" }
        let value =
            context.prefix(13).joined(separator: " ") + " intentionality "
            + context.dropFirst(13).prefix(27).joined(separator: " ") + " consciousness "
            + context.dropFirst(40).joined(separator: " ") + " intentionality consciousness"
        for limit in 2...32 {
            let terms = RelatedContentQueryTerms.terms(in: value, limit: limit)
            #expect(terms.contains("intentionality"))
            #expect(terms.contains("consciousness"))
            #expect(terms.count == limit)
            #expect(Set(terms).count == limit)
        }
    }

    @Test("A long CJK focus retains its authored technical words without translation")
    func minorityScriptTerms() {
        let explanation = "讨论经验结构时需要分别说明意识活动如何指向对象以及对象呈现的方式并区分表象内容与主体立场还应检查不同描述之间能否保持同一个问题"
        let value = explanation + " intentional object " + String(explanation.reversed()) + " phenomenal character " + explanation
        let terms = RelatedContentQueryTerms.terms(in: value, limit: 32)
        #expect(terms.count == 32)
        #expect(Set(["intentional", "object", "phenomenal", "character"]).isSubset(of: Set(terms)))
        #expect(terms.contains { SearchTokenization.containsCJK($0) })
        #expect(terms.allSatisfy { RelatedContentQueryTerms.orderedTokens(in: value).contains($0) })

        let english = (0..<100).map { "context\($0)" }.joined(separator: " ")
        let inverse = english + " 意向对象 " + String(english.reversed()) + " 现象特征 " + english
        let inverseTerms = RelatedContentQueryTerms.terms(in: inverse, limit: 32)
        #expect(Set(["意向", "向对", "对象", "现象", "象特", "特征"]).isSubset(of: Set(inverseTerms)))
        #expect(inverseTerms.count == 32)
    }

    @Test("Closed quoted concepts survive long surrounding prose without consuming the whole budget")
    func quotedConcepts() {
        let surrounding = (0..<100).map { "context\($0)" }
        let value =
            surrounding.prefix(40).joined(separator: " ") + " “not sufficient” "
            + surrounding.dropFirst(40).joined(separator: " ") + " finalconcept"
        let terms = RelatedContentQueryTerms.terms(in: value, limit: 32)
        #expect(terms.count == 32)
        #expect(terms.contains("not"))
        #expect(terms.contains("sufficient"))
        #expect(terms.first == "context0")
        #expect(terms.last == "finalconcept")
        #expect(RelatedContentQueryTerms.quotedPhrases(in: value) == ["not sufficient"])
    }

    @Test("Small focuses retain order and negation without expanding to synonyms")
    func smallFocus() {
        #expect(
            RelatedContentQueryTerms.terms(in: "The reason is not sufficient; not necessary, never conclusive.", limit: 32)
                == ["reason", "not", "sufficient", "necessary", "never", "conclusive"])
        #expect(RelatedContentQueryTerms.orderedTokens(in: "Reason reason NOT reason") == ["reason", "reason", "not", "reason"])
        #expect(RelatedContentQueryTerms.terms(in: "happy", limit: 32) == ["happy"])
    }

    @Test("Unicode normalization and CJK script transitions retain the established lexical projection")
    func unicodeAndCJK() {
        #expect(RelatedContentQueryTerms.terms(in: "CAFÉ cafe\u{301} 自由意志 autonomy", limit: 32) == ["café", "自由", "由意", "意志", "autonomy"])
        #expect(RelatedContentQueryTerms.orderedTokens(in: "自由freedom自主") == ["自由", "freedom", "自主"])
        let cjk = "自由意志自主责任充分必要条件情感理由价值判断"
        let selected = RelatedContentQueryTerms.terms(in: cjk, limit: 6)
        let expectedTokens = SearchTokenization.queryTokens(for: cjk)
        #expect(selected.count == 6)
        #expect(selected.first == expectedTokens.first)
        #expect(selected.last == expectedTokens.last)
        #expect(selected.allSatisfy { expectedTokens.contains($0) })
    }

    @Test("Quotes preserve authored function words, multilingual wording and only closed spans")
    func phraseBoundaries() {
        #expect(
            RelatedContentQueryTerms.quotedPhrases(in: "“NOT a sufficient condition” and 「充分条件」 then \"not a sufficient condition\" and 『非必要条件』")
                == ["not a sufficient condition", "充分条件", "非必要条件"])
        #expect(RelatedContentQueryTerms.quotedPhrases(in: "unquoted necessary condition") == [])
        #expect(RelatedContentQueryTerms.quotedPhrases(in: "an author's reason isn't “an unfinished phrase") == [])
        #expect(RelatedContentQueryTerms.quotedPhrases(in: "\"  reason\n for   action  \"") == ["reason for action"])
        #expect(RelatedContentQueryTerms.quotedPhrases(in: "\\\"not a quote\\\"") == [])
    }

    @Test("All query budgets are bounded, unique and deterministic, including very small limits")
    func limits() {
        let input = (0..<150).map { "term\($0)" }.joined(separator: " ") + " “not sufficient”"
        for limit in -1...32 {
            let selected = RelatedContentQueryTerms.terms(in: input, limit: limit)
            #expect(selected.count == max(0, limit))
            #expect(Set(selected).count == selected.count)
            #expect(selected == RelatedContentQueryTerms.terms(in: input, limit: limit))
        }
        #expect(RelatedContentQueryTerms.terms(in: "the and of", limit: 32).isEmpty)
        #expect(RelatedContentQueryTerms.quotedPhrases(in: "\"first phrase\" \"second phrase\"", limit: 1) == ["first phrase"])
        #expect(RelatedContentQueryTerms.quotedPhrases(in: "\"first phrase\"", limit: 0).isEmpty)
        #expect(RelatedContentQueryTerms.quotedPhrases(in: "\"" + String(repeating: "longword ", count: 17) + "\"").isEmpty)
    }
}
