import Foundation
import Testing
@testable import ScholiumApp

struct ScholiumLocalizationTests {
    private let simplifiedChinese = Locale(identifier: "zh-Hans")
    private let english = Locale(identifier: "en")

    @Test("Interface catalog localizes current Settings destinations")
    func settingsDestinations() {
        #expect(
            ScholiumL10n.localized(
                ScholiumL10n.Settings.integrations,
                locale: simplifiedChinese
            ) == "集成"
        )
        #expect(
            ScholiumL10n.localized(
                ScholiumL10n.Settings.document,
                locale: simplifiedChinese
            ) == "文稿"
        )
        #expect(
            ScholiumL10n.string("Agents & Chat", locale: simplifiedChinese)
                == "智能体与聊天"
        )
        #expect(
            ScholiumL10n.string("Keyboard Shortcuts", locale: simplifiedChinese)
                == "键盘快捷键"
        )
        #expect(
            ScholiumL10n.string("Zotero Not Available", locale: simplifiedChinese)
                == "Zotero 不可用"
        )
    }

    @Test("Agents and Agent Changes localize without lifecycle vocabulary")
    func agentCollaboration() {
        #expect(
            ScholiumL10n.string("No Agent Changes", locale: simplifiedChinese)
                == "没有智能体更改"
        )




        #expect(ScholiumL10n.string("Undo", locale: simplifiedChinese) == "撤销")
        #expect(
            ScholiumL10n.string(
                "Show Core Protocol in Finder…",
                locale: simplifiedChinese
            ) == "在 Finder 中显示核心协议…"
        )
        #expect(
            ScholiumL10n.string(
                "MCP tool availability is not permission to modify research material. Write scope comes only from the researcher’s explicit request in the external conversation.",
                locale: simplifiedChinese
            ) == "MCP 工具可用并不意味着有权修改研究材料。写入范围只来自研究者在外部对话中的明确请求。"
        )
    }

    @Test("Current document and file controls resolve in Simplified Chinese")
    func ordinaryInterfaceCopy() {
        let expectations: [(String.LocalizationValue, String)] = [
            ("Save", "保存"),
            ("Triptych", "脉络"),
            ("Vault", "研究库"),
            ("Library", "研究文档"),
            ("Review", "审阅"),
            ("Edit", "编辑"),
            ("Source", "源文本"),
            ("Settle", "暂定"),
            ("Move to Trash…", "移至纸篓…"),
            ("Rename Note", "重命名笔记"),
            ("Move Note", "移动笔记"),
            ("No Document Selected", "未选择文档"),
            ("Expand All Folders", "展开所有文件夹"),
        ]
        for (key, expected) in expectations {
            #expect(ScholiumL10n.string(key, locale: simplifiedChinese) == expected)
        }

        let count = String(
            format: ScholiumL10n.string("%lld notes", locale: simplifiedChinese),
            locale: simplifiedChinese,
            Int64(3)
        )
        #expect(count == "3 篇文档")

    }

    @Test("Inspector localizes projections, attention, and occurrence semantics")
    func inspectorInterfaceCopy() {
        let expectations: [(String.LocalizationValue, String)] = [
            ("Overview", "概览"),
            ("Outgoing Links", "本笔记指向的链接"),
            ("Incoming Links", "指向本笔记的链接"),
            ("NEEDS ATTENTION", "需要注意"),
            ("Edit at Source", "在源笔记中编辑"),
            ("Edit Link Annotation", "编辑链接注释"),
        ]
        for (key, expected) in expectations {
            #expect(ScholiumL10n.string(key, locale: simplifiedChinese) == expected)
        }

        let context = String(
            format: ScholiumL10n.string("Context: %@", locale: simplifiedChinese),
            locale: simplifiedChinese,
            "原文"
        )
        #expect(context == "上下文：原文")

        let incomingWithoutAnnotation = String(
            format: ScholiumL10n.string(
                "Incoming link from %@. No link annotation",
                locale: simplifiedChinese
            ),
            locale: simplifiedChinese,
            "判断"
        )
        #expect(incomingWithoutAnnotation == "来自 判断 的传入连接。无链接注释")
    }

    @Test("The application name remains verbatim")
    func verbatimProductName() {
        #expect(ScholiumL10n.string("Scholium", locale: simplifiedChinese) == "Scholium")
        #expect(ScholiumL10n.string("Review", locale: english) == "Review")
    }

    @Test("Interface catalog excludes retired Agent lifecycle surfaces")
    func interfaceCatalogHasNoRetiredEntries() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalog = try String(
            contentsOf: repository.appendingPathComponent(
                "Scholium/Resources/Localizable.xcstrings"
            ),
            encoding: .utf8
        )

        #expect(!catalog.contains("垃圾箱"))
        #expect(ScholiumL10n.string("Move Note to Trash", locale: simplifiedChinese) == "将笔记移到废纸篓")
        for retiredKey in [
            "\"Research Action\" :",
            "\"Discussion\" :",
            "\"Copy Handoff\" :",
            "\"Academic Profile\" :",
            "\"Synthesis Material Changed\" :",
        ] {
            #expect(!catalog.contains(retiredKey))
        }
    }
}
