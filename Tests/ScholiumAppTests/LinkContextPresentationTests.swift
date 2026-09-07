import Testing
@testable import ScholiumApp

@Suite("Readable link contexts")
struct LinkContextPresentationTests {
    @Test("Reading uses labels without changing literal code or authored label punctuation")
    func readableSnippets() {
        #expect(LinkContextPresentation.readableText("Read [[Target|Visible label]] and [ordinary](other.md).") == "Read Visible label and ordinary.")
        #expect(LinkContextPresentation.readableText("研究 [[分析#一节|判断依据]]。") == "研究 判断依据。")
        #expect(LinkContextPresentation.readableText("[[Target|*literal*]]") == "*literal*")
        #expect(LinkContextPresentation.readableText("Code `[[literal]]`, link [[Note]].") == "Code [[literal]], link Note.")
    }

    @Test("Attached annotations appear separately while literal and malformed braces survive")
    func separateAnnotations() {
        #expect(LinkContextPresentation.readableText("参考 [[QA Topic]] 与 [[示例材料]]{{检验跨库导航，不代表来源支持。}}。") == "参考 QA Topic 与 示例材料。")
        #expect(LinkContextPresentation.readableText("😀 [[A|依据]]{{See [[B]] and *reason*.}} 与 [[C]]{{Other.}}。") == "😀 依据 与 C。")
        #expect(LinkContextPresentation.readableText("`[[A]]{{literal}}` and {{ordinary}} [[B]]{{unfinished") == "[[A]]{{literal}} and {{ordinary}} B{{unfinished")
    }
}
