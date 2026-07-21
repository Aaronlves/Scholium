import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

struct ScholiumLocalizationTests {
    private let simplifiedChinese = Locale(identifier: "zh-Hans")
    private let english = Locale(identifier: "en")

    @Test("Interface catalog localizes Settings tabs without changing the source language")
    func settingsTabs() {
        #expect(
            ScholiumL10n.localized(
                ScholiumL10n.Settings.researchGuidance,
                locale: english
            ) == "Research Guidance"
        )
        #expect(
            ScholiumL10n.localized(
                ScholiumL10n.Settings.researchGuidance,
                locale: simplifiedChinese
            ) == "研究指导"
        )
        #expect(
            ScholiumL10n.localized(
                ScholiumL10n.Settings.appearance,
                locale: simplifiedChinese
            ) == "外观"
        )
        #expect(
            ScholiumL10n.localized(
                ScholiumL10n.Settings.zotero,
                locale: simplifiedChinese
            ) == "Zotero"
        )
    }

    @Test("Research Function presentation localizes independently of stable identifiers")
    func researchFunctions() {
        #expect(ResearchFunctionID.dialogue.interfaceTitle(locale: english) == "Dialogue")
        #expect(ResearchFunctionID.dialogue.interfaceTitle(locale: simplifiedChinese) == "对话")
        #expect(ResearchFunctionID.develop.interfaceTitle(locale: simplifiedChinese) == "发展")
        #expect(ResearchFunctionID.fidelity.interfaceTitle(locale: simplifiedChinese) == "核查")
        #expect(
            ResearchFunctionID.critique.interfaceHelp(locale: simplifiedChinese)
                == "请求对这篇写作进行署名评析"
        )

        #expect(ResearchFunctionID.dialogue.interfaceIdentifier == "dialogue")
        #expect(ResearchFunctionID.fidelity.interfaceIdentifier == "fidelity")
    }

    @Test("Default interface catalog resolves ordinary controls in Simplified Chinese")
    func ordinaryInterfaceCopy() {
        #expect(ScholiumL10n.string("Callout", locale: simplifiedChinese) == "Callout")
        #expect(ScholiumL10n.string("Save", locale: simplifiedChinese) == "保存")
        #expect(ScholiumL10n.string("Triptych", locale: simplifiedChinese) == "脉络")
        #expect(ScholiumL10n.string("Vault", locale: simplifiedChinese) == "研究库")
        #expect(ScholiumL10n.string("Library", locale: simplifiedChinese) == "研究文档")
        #expect(ScholiumL10n.string("Analyses", locale: simplifiedChinese) == "分析")
        #expect(ScholiumL10n.string("Topics", locale: simplifiedChinese) == "议题")
        #expect(ScholiumL10n.string("Works", locale: simplifiedChinese) == "写作")
        #expect(ScholiumL10n.string("Human Review", locale: simplifiedChinese) == "研究者评审")
        #expect(ScholiumL10n.string("Qualification", locale: simplifiedChinese) == "评审结论")
        #expect(ScholiumL10n.string("Qualified", locale: simplifiedChinese) == "通过评审")
        #expect(ScholiumL10n.string("Unqualified", locale: simplifiedChinese) == "未通过评审")
        #expect(ScholiumL10n.string("Attention", locale: simplifiedChinese) == "关注")
        #expect(ScholiumL10n.string("Connections", locale: simplifiedChinese) == "关联")
        #expect(ScholiumL10n.string("Checkpoint", locale: simplifiedChinese) == "恢复点")
        #expect(ScholiumL10n.string("Snapshot", locale: simplifiedChinese) == "快照")
        #expect(ScholiumL10n.string("Comment", locale: simplifiedChinese) == "注释")
        #expect(ScholiumL10n.string("Response", locale: simplifiedChinese) == "回应")
        #expect(ScholiumL10n.string("Review", locale: simplifiedChinese) == "审阅")
        #expect(ScholiumL10n.string("Research Status", locale: simplifiedChinese) == "内容状态")
        #expect(ScholiumL10n.string("Research Record", locale: simplifiedChinese) == "研究记录")
        #expect(ScholiumL10n.string("Restore Access", locale: simplifiedChinese) == "恢复访问权限")
        #expect(ScholiumL10n.string("Hide Sidebar", locale: simplifiedChinese) == "隐藏边栏")
        #expect(ScholiumL10n.string("Show Sidebar", locale: simplifiedChinese) == "显示边栏")
        #expect(
            ScholiumL10n.string("Hide Research Inspector", locale: simplifiedChinese)
                == "隐藏研究检查器"
        )
        #expect(
            ScholiumL10n.string("Show Research Inspector", locale: simplifiedChinese)
                == "显示研究检查器"
        )
        #expect(
            ScholiumL10n.string("RECOMMENDED BIBLIOGRAPHY", locale: simplifiedChinese)
                == "推荐文献"
        )
        #expect(ScholiumL10n.string("Save", locale: english) == "Save")
    }

    @Test("Application and Skill names remain verbatim")
    func verbatimProductAndSkillNames() {
        #expect(ScholiumL10n.string("Scholium", locale: simplifiedChinese) == "Scholium")
        #expect(
            ScholiumL10n.string("Built-in Source Analyzer", locale: simplifiedChinese)
                == "内置 Source Analyzer"
        )
    }

    @Test("Lifecycle destinations use approved Simplified Chinese terminology")
    func lifecycleDestinationTerminology() {
        #expect(ScholiumL10n.string("Set Aside", locale: simplifiedChinese) == "搁置")
        #expect(ScholiumL10n.string("SET ASIDE", locale: simplifiedChinese) == "搁置")
        #expect(ScholiumL10n.string("Trash", locale: simplifiedChinese) == "纸篓")
        #expect(ScholiumL10n.string("TRASH", locale: simplifiedChinese) == "纸篓")
        #expect(ScholiumL10n.string("Move to Trash…", locale: simplifiedChinese) == "移至纸篓…")
        #expect(ScholiumL10n.string("Put Back…", locale: simplifiedChinese) == "放回…")
        #expect(ScholiumL10n.string("Back to Library", locale: simplifiedChinese) == "返回研究文档")

        let englishCount = String(
            format: ScholiumL10n.string("%lld notes", locale: english),
            locale: english,
            Int64(3)
        )
        let chineseCount = String(
            format: ScholiumL10n.string("%lld notes", locale: simplifiedChinese),
            locale: simplifiedChinese,
            Int64(3)
        )
        #expect(ScholiumL10n.string("1 note", locale: english) == "1 note")
        #expect(englishCount == "3 notes")
        #expect(chineseCount == "3 篇文档")

        let researcherTitle = "QA 议题：Trash/Set Aside"
        let putBackLabel = String(
            format: ScholiumL10n.string("Put Back %@", locale: simplifiedChinese),
            locale: simplifiedChinese,
            researcherTitle
        )
        #expect(putBackLabel == "放回 QA 议题：Trash/Set Aside")
    }

    @Test("Lifecycle catalog retires alternate Trash terms and card-only keys")
    func lifecycleDestinationCatalogHasNoRetiredEntries() throws {
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
        #expect(!catalog.contains("废纸篓"))
        for retiredCardKey in [
            "\"Collapse %@\" :",
            "\"Collapse %arg\" :",
            "\"Could Not Open %@\" :",
            "\"Could Not Open %arg\" :",
            "\"No notes are currently in %@.\" :",
            "\"No notes are currently in %arg.\" :",
            "\"Open note in %arg\" :",
            "\"Opening %@…\" :",
            "\"Opening %arg…\" :",
        ] {
            #expect(!catalog.contains(retiredCardKey))
        }
    }
}
