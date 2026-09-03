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
        #expect(english.strings.count == 100)
        #expect(simplifiedChinese.strings.keys == english.strings.keys)
        #expect(english.string("Markdown editor, Edit mode") == "Markdown editor, Edit mode")
        #expect(
            simplifiedChinese.string("Markdown editor, Edit mode")
                == "Markdown 编辑器，编辑模式"
        )
        #expect(simplifiedChinese.string("Note title") == "笔记标题")
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
