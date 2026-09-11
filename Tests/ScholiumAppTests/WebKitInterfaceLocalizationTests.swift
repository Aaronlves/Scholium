import Foundation
import Testing

@testable import ScholiumApp

@Suite("WebKit interface localization")
struct WebKitInterfaceLocalizationTests {
    @Test("English and Simplified Chinese tables provide the same complete WebKit surface")
    func localizedTablesAreComplete() throws {
        let english = WebKitInterfaceLocalization.localized(languageTag: "en")
        let simplifiedChinese = WebKitInterfaceLocalization.localized(languageTag: "zh-Hans")

        #expect(english.languageTag == "en")
        #expect(simplifiedChinese.languageTag == "zh-Hans")
        #expect(simplifiedChinese.string("YAML frontmatter") == "YAML 文档头")
        #expect(simplifiedChinese.strings.keys == english.strings.keys)
        #expect(english.string("Markdown editor, Edit mode") == "Markdown editor, Edit mode")
        #expect(
            simplifiedChinese.string("Markdown editor, Edit mode")
                == "Markdown 编辑器，编辑模式"
        )
        #expect(simplifiedChinese.string("Note title") == "笔记标题")
        let philosophicalCalloutLabels = [
            "Callout": "语义块",
            "Orientation": "导读",
            "Source": "文献",
            "Connections": "关联",
            "Statement": "论点",
            "Illustration": "例证",
            "Quotation": "引文",
            "Caution": "限定",
        ]
        for (key, expectedLabel) in philosophicalCalloutLabels {
            #expect(simplifiedChinese.string(key) == expectedLabel)
        }
        #expect(
            simplifiedChinese.string(
                "Marks a limitation, unresolved dependency, source restriction, or interpretive warning."
            ) == "标明适用范围、待决依赖、文献限制或解释上的保留。"
        )
        #expect(
            simplifiedChinese.string("Comment for lines {start} through {end}")
                == "评论第 {start} 至 {end} 行"
        )
    }

    @Test("Edit and Review HTML declare the resolved interface language without changing research text")
    @MainActor
    func webDocumentsDeclareInterfaceLanguage() throws {
        let localization = WebKitInterfaceLocalization.localized(languageTag: "zh-CN")
        let researchText = "价值是否提供规范性理由？"
        let editHTML = try #require(
            MarkdownEditorWebView.editorHTML(localization: localization)
        )
        let reviewHTML = SafeMarkdownReadWebView.Coordinator.documentHTML(
            body: "<p>\(researchText)</p>",
            localization: localization
        )

        #expect(editHTML.contains(#"<html lang="zh-Hans">"#))
        #expect(editHTML.contains(#"name="scholium-interface-localization""#))
        #expect(reviewHTML.contains(#"<html lang="zh-Hans">"#))
        #expect(reviewHTML.contains(researchText))
        #expect(!reviewHTML.contains("Selection actions"))
        #expect(!reviewHTML.contains(">Comment<"))
    }

    @Test("Edit localization payload is bounded JSON rather than executable markup")
    @MainActor
    func editPayloadIsInertJSON() throws {
        let localization = WebKitInterfaceLocalization.localized(languageTag: "zh-Hans")
        let html = try #require(MarkdownEditorWebView.editorHTML(localization: localization))
        let match = try #require(
            html.firstMatch(
                of: /<meta name="scholium-interface-localization" content="([A-Za-z0-9+\/=]+)">/
            )
        )
        let data = try #require(Data(base64Encoded: String(match.1)))
        let decoded = try JSONDecoder().decode(WebKitInterfaceLocalization.self, from: data)

        #expect(decoded == localization)
        #expect(!String(decoding: data, as: UTF8.self).contains("</script>"))
    }
}
