import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

struct SearchDiagnosticLocalizationTests {
    private let chinese = Locale(identifier: "zh-Hans")
    private let english = Locale(identifier: "en")

    @Test("Search diagnostics localize typed reasons without parsing protocol messages")
    func typedDiagnosticPresentation() {
        func diagnostic(_ reason: SearchQueryDiagnosticReason) -> SearchQueryDiagnostic {
            .init(reason: reason, message: "Foreign protocol text stays unchanged.", utf16LowerBound: 0, utf16UpperBound: 1)
        }
        let property = diagnostic(.propertyPrefixUnsupported)
        #expect(
            SearchDiagnosticPresentation.message(property, locale: chinese)
                == "属性相等条件使用精确匹配，不支持前缀。")
        #expect(
            SearchDiagnosticPresentation.message(property, locale: english)
                == "Property equality is exact and does not support prefixes.")
        #expect(property.message == "Foreign protocol text stays unchanged.")

        let field = diagnostic(.unknownField(field: "Review"))
        #expect(SearchDiagnosticPresentation.message(field, locale: chinese) == "未知搜索字段“Review:”。")
        let bounded = diagnostic(.queryTooLong(limit: 16_384))
        #expect(
            SearchDiagnosticPresentation.message(bounded, locale: chinese)
                == "搜索查询最多包含 16,384 个 UTF-16 代码单元。")
        let ambiguity = diagnostic(
            .ambiguousLinkIdentity(
                identity: "Review", candidates: ["Analyses/Review.md", "Topics/审阅.md"]))
        let message = SearchDiagnosticPresentation.message(ambiguity, locale: chinese)
        #expect(message.contains("链接标识“Review”有歧义："))
        #expect(message.contains("Analyses/Review.md") && message.contains("Topics/审阅.md"))
        #expect(!message.contains("Foreign protocol"))
    }

    @Test("Identity recovery explains the reading and mutation boundary in either language")
    func identityAmbiguityExplanation() {
        #expect(
            IdentityResolutionPresentation.ambiguity(candidateCount: 0, locale: chinese)
                == "此文件的先前标识尚未确定。你可以继续阅读；确认其标识前，依赖标识的恢复和文件更改仍不可用。")
        #expect(
            IdentityResolutionPresentation.ambiguity(candidateCount: 1, locale: english)
                .hasPrefix("This file matches one previous note."))
        #expect(
            IdentityResolutionPresentation.ambiguity(candidateCount: 3, locale: chinese)
                .hasPrefix("此文件与 3 篇先前笔记匹配。"))
    }
}
