import ScholiumContracts
import Testing

@Suite("Readable link contexts")
struct ResearchExcerptPresentationTests {
    @Test("Reading uses labels without changing literal code or authored label punctuation")
    func readableSnippets() {
        #expect(ResearchExcerptPresentation.readableText("Read [[Target|Visible label]] and [ordinary](other.md).") == "Read Visible label and ordinary.")
        #expect(ResearchExcerptPresentation.readableText("研究 [[分析#一节|判断依据]]。") == "研究 判断依据。")
        #expect(ResearchExcerptPresentation.readableText("[[Target|*literal*]]") == "*literal*")
        #expect(ResearchExcerptPresentation.readableText("Code `[[literal]]`, link [[Note]].") == "Code [[literal]], link Note.")
    }

    @Test("Attached annotations appear separately while literal and malformed braces survive")
    func separateAnnotations() {
        #expect(ResearchExcerptPresentation.readableText("参考 [[QA Topic]] 与 [[示例材料]]{{检验跨库导航，不代表来源支持。}}。") == "参考 QA Topic 与 示例材料。")
        #expect(ResearchExcerptPresentation.readableText("😀 [[A|依据]]{{See [[B]] and *reason*.}} 与 [[C]]{{Other.}}。") == "😀 依据 与 C。")
        #expect(
            ResearchExcerptPresentation.readableText("`[[A]]{{literal}}` and {{ordinary}} [[B]]{{unfinished")
                == "[[A]]{{literal}} and {{ordinary}} B{{unfinished")
    }
}
