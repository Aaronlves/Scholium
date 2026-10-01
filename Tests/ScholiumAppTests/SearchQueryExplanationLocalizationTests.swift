import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

struct SearchQueryExplanationLocalizationTests {
    private let chinese = Locale(identifier: "zh-Hans")
    private let english = Locale(identifier: "en")

    @Test("Query explanations localize grammar while preserving literal search values")
    func lexicalAndPropertyValues() {
        let lexical = SearchExplanationClause(
            kind: .lexical(.title, "Review / 源文本", .prefix, true), sourceRange: 0..<1)
        #expect(
            SearchQueryExplanationPresentation.clause(lexical, locale: chinese)
                == "标题不以“Review / 源文本”开头")
        #expect(
            SearchQueryExplanationPresentation.clause(lexical, locale: english)
                == "title does not begin with ‘Review / 源文本’")

        let property = SearchExplanationClause(
            kind: .property("review_state", "Review"), sourceRange: 0..<1)
        #expect(
            SearchQueryExplanationPresentation.clause(property, locale: chinese)
                == "属性 review_state 等于“Review”")
        let link = SearchExplanationClause(
            kind: .link(.toNote, "folder/Review.md"), sourceRange: 0..<1)
        #expect(
            SearchQueryExplanationPresentation.clause(link, locale: chinese)
                == "直接链接到“folder/Review.md”")
    }

    @Test("Paragraph explanations preserve Boolean nesting and localize their inner clauses")
    func nestedParagraphExpression() {
        func term(_ value: String) -> SearchExpression {
            .clause(.lexical(.init(field: nil, value: .term(value), sourceRange: 0..<1)))
        }
        let expression = SearchExpression.and([
            .or([term("Review"), term("Source")]), .not(term("localizable:key")),
        ])
        let paragraph = SearchExplanationClause(kind: .paragraph(expression), sourceRange: 0..<1)
        let result = SearchQueryExplanationPresentation.clause(paragraph, locale: chinese)
        #expect(result.hasPrefix("同一段落内："))
        #expect(result.contains("文本包含“Review” OR 文本包含“Source”"))
        #expect(result.contains("AND NOT (文本包含“localizable:key”)"))
        #expect(!result.contains("contains"))
        #expect(expression.rendered(\.queryDescription).contains("\"Review\" OR \"Source\""))
    }

    @Test("Approval scope labels use Chinese punctuation while retaining exact paths and patterns")
    func approvalScopeFormatting() {
        let permissions = AgentChatRuntimeApproval.Permissions(
            network: nil,
            rules: [.init(access: .write, path: .pattern("/fixture/Review/**/*.md"))],
            globScanMaxDepth: nil)
        let request = AgentChatRuntimeApproval(
            kind: .permissions, command: nil, cwd: "/fixture/Source",
            environmentID: nil, reason: nil, networkHost: nil, networkProtocol: nil,
            permissions: permissions, files: [], grantRoot: nil, grants: [.turn], rejection: .decline)
        let lines = request.scopeLines(locale: chinese)
        #expect(lines.contains("工作目录：/fixture/Source"))
        #expect(lines.contains { $0.contains("：") && $0.contains("/fixture/Review/**/*.md") })
        #expect(!lines.contains { $0.contains(": ") })
    }
}
