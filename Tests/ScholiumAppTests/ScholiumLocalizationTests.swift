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
        #expect(ResearchFunctionID.discuss.interfaceTitle(locale: english) == "Discuss")
        #expect(ResearchFunctionID.discuss.interfaceTitle(locale: simplifiedChinese) == "讨论")
        #expect(ResearchFunctionID.develop.interfaceTitle(locale: simplifiedChinese) == "发展")
        #expect(ResearchFunctionID.fidelity.interfaceTitle(locale: simplifiedChinese) == "核查")
        #expect(
            ResearchFunctionID.critique.interfaceHelp(locale: simplifiedChinese)
                == "请求对这篇写作进行署名评析"
        )

        #expect(ResearchFunctionID.discuss.interfaceIdentifier == "discuss")
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
        #expect(ScholiumL10n.string("Attention", locale: simplifiedChinese) == "关注")
        #expect(ScholiumL10n.string("Connect", locale: simplifiedChinese) == "连接")
        #expect(ScholiumL10n.string("Checkpoint", locale: simplifiedChinese) == "恢复点")
        #expect(ScholiumL10n.string("Snapshot", locale: simplifiedChinese) == "快照")
        #expect(ScholiumL10n.string("Comment", locale: simplifiedChinese) == "评论")
        #expect(ScholiumL10n.string("Response", locale: simplifiedChinese) == "回应")
        #expect(ScholiumL10n.string("Review", locale: simplifiedChinese) == "审阅")
        #expect(ScholiumL10n.string("Edit", locale: simplifiedChinese) == "编辑")
        #expect(ScholiumL10n.string("Source", locale: simplifiedChinese) == "源文本")
        #expect(ScholiumL10n.string("Review", locale: english) == "Review")
        #expect(ScholiumL10n.string("Edit", locale: english) == "Edit")
        #expect(ScholiumL10n.string("Work with Agent", locale: simplifiedChinese) == "与 Agent 协作")
        #expect(ScholiumL10n.string("Settle", locale: simplifiedChinese) == "暂定")
        #expect(ScholiumL10n.string("RESEARCH ACTIVITY", locale: simplifiedChinese) == "研究活动")
        #expect(ScholiumL10n.string("Completion", locale: simplifiedChinese) == "完成度")
        #expect(ScholiumL10n.string("Incomplete", locale: simplifiedChinese) == "未完成")
        #expect(ScholiumL10n.string("Research Scope", locale: simplifiedChinese) == "研究范围")
        #expect(ScholiumL10n.string("Source basis", locale: simplifiedChinese) == "来源依据")
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
        #expect(ScholiumL10n.string("Storage Unavailable", locale: simplifiedChinese) == "存储不可用")
        #expect(ScholiumL10n.string("Details", locale: simplifiedChinese) == "详细信息")
        #expect(ScholiumL10n.string("Quit", locale: simplifiedChinese) == "退出")
        #expect(ScholiumL10n.string("Retry", locale: simplifiedChinese) == "重试")
        #expect(ScholiumL10n.string("Save", locale: english) == "Save")
    }

    @Test("Appearance line-width controls use localized labels and explanations")
    func appearanceLineWidthCopy() {
        #expect(ScholiumL10n.string("Layout", locale: simplifiedChinese) == "布局")
        #expect(ScholiumL10n.string("Line width", locale: simplifiedChinese) == "行宽")
        #expect(
            ScholiumL10n.string("character-width units", locale: simplifiedChinese)
                == "字符宽度单位"
        )
        #expect(
            ScholiumL10n.string(
                "Line width is measured in CSS character-width units; the exact number of characters varies by typeface.",
                locale: simplifiedChinese
            ) == "行宽以 CSS 字符宽度单位计量；每行的实际字符数会随字体而变化。"
        )
    }

    @Test("Application and Skill names remain verbatim")
    func verbatimProductAndSkillNames() {
        #expect(ScholiumL10n.string("Scholium", locale: simplifiedChinese) == "Scholium")
        #expect(
            ScholiumL10n.string("Built-in Source Analyzer", locale: simplifiedChinese)
                == "内置 Source Analyzer"
        )
    }

    @Test("Application-owned Action modules and handoff controls localize")
    func researchActionCopy() {
        #expect(ScholiumL10n.string("Request", locale: simplifiedChinese) == "请求")
        #expect(ScholiumL10n.string("Materials", locale: simplifiedChinese) == "材料")
        #expect(ScholiumL10n.string("Read-only", locale: simplifiedChinese) == "只读")
        #expect(
            ScholiumL10n.string("REQUESTED AUTHORITY", locale: simplifiedChinese)
                == "请求的权限"
        )
        #expect(
            ScholiumL10n.string("Loading…", locale: simplifiedChinese)
                == "正在加载…"
        )
        #expect(
            ScholiumL10n.string(
                "Current Action details are unavailable. Scholium will not allow this request.",
                locale: simplifiedChinese
            ) == "当前操作详情不可用。Scholium 不会允许此请求。"
        )
        #expect(
            ScholiumL10n.string(
                "Allow These Notes Once",
                locale: simplifiedChinese
            ) == "仅本次允许这些笔记"
        )
        #expect(
            ScholiumL10n.string("Cancel the Run", locale: simplifiedChinese)
                == "取消本次运行"
        )
        #expect(
            ScholiumL10n.string(
                "Expected revision %@; current revision matches",
                locale: simplifiedChinese
            ) == "预期修订为 %@；当前修订一致"
        )
        #expect(
            ScholiumL10n.string(
                "Copy and Choose Agent App…",
                locale: simplifiedChinese
            ) == "复制并选择智能体应用…"
        )
        #expect(
            ScholiumL10n.string(
                "A prepared Action still needs cancellation.",
                locale: simplifiedChinese
            ) == "仍有一个已准备的操作需要取消。"
        )
        #expect(
            ScholiumL10n.string("Retry Cancellation", locale: simplifiedChinese)
                == "重试取消"
        )
        #expect(
            ScholiumL10n.string("Retrying Cancellation…", locale: simplifiedChinese)
                == "正在重试取消…"
        )
        #expect(
            ScholiumL10n.string(
                "Resolve the pending Action cancellation before starting another Action.",
                locale: simplifiedChinese
            ) == "请先解决待处理的操作取消，再开始另一项操作。"
        )
        #expect(
            ScholiumL10n.string(
                "Waiting for interrupted Action cleanup…",
                locale: simplifiedChinese
            ) == "正在等待被中断的操作完成清理…"
        )
        #expect(
            ScholiumL10n.string(
                "Action preparation was cancelled.",
                locale: simplifiedChinese
            ) == "操作准备已取消。"
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
