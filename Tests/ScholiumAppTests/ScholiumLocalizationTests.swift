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
                ScholiumL10n.Settings.triptychs,
                locale: simplifiedChinese
            ) == "脉络"
        )
        #expect(
            ScholiumL10n.localized(
                ScholiumL10n.Settings.metadata,
                locale: simplifiedChinese
            ) == "元数据"
        )
        #expect(
            ScholiumL10n.string("Ready to install", locale: simplifiedChinese)
                == "可安装"
        )
        #expect(
            ScholiumL10n.string("Installed and discoverable", locale: simplifiedChinese)
                == "已安装且可发现"
        )
        #expect(
            ScholiumL10n.string("Connected", locale: simplifiedChinese)
                == "已连接"
        )
        #expect(
            ScholiumL10n.string("Zotero Not Available", locale: simplifiedChinese)
                == "Zotero 不可用"
        )
    }

    @Test("Public Research Actions localize without exposing protected mechanism names")
    func researchActions() {
        #expect(ScholiumL10n.string("Discuss", locale: english) == "Discuss")
        #expect(ScholiumL10n.string("Discuss", locale: simplifiedChinese) == "讨论")
        #expect(ScholiumL10n.string("Analyze", locale: simplifiedChinese) == "分析")
        #expect(ScholiumL10n.string("Synthesize", locale: simplifiedChinese) == "综合")
        #expect(ScholiumL10n.string("Write", locale: simplifiedChinese) == "写入")
        #expect(ScholiumL10n.string("Critique", locale: simplifiedChinese) == "评析")
        #expect(ScholiumL10n.string("Check Fidelity", locale: simplifiedChinese) == "核查忠实度")
    }

    @Test("Default interface catalog resolves ordinary controls in Simplified Chinese")
    func ordinaryInterfaceCopy() {
        #expect(ScholiumL10n.string("Callout", locale: simplifiedChinese) == "Callout")
        #expect(ScholiumL10n.string("Save", locale: simplifiedChinese) == "保存")
        #expect(ScholiumL10n.string("Triptych", locale: simplifiedChinese) == "脉络")
        #expect(ScholiumL10n.string("Vault", locale: simplifiedChinese) == "研究库")
        #expect(ScholiumL10n.string("Library", locale: simplifiedChinese) == "研究文档")
        #expect(
            ScholiumL10n.string("Expand All Folders", locale: simplifiedChinese)
                == "展开所有文件夹"
        )
        #expect(
            ScholiumL10n.string("Collapse All Folders", locale: simplifiedChinese)
                == "折叠所有文件夹"
        )
        #expect(ScholiumL10n.string("Analyses", locale: simplifiedChinese) == "分析")
        #expect(ScholiumL10n.string("Topics", locale: simplifiedChinese) == "议题")
        #expect(ScholiumL10n.string("Works", locale: simplifiedChinese) == "写作")
        #expect(ScholiumL10n.string("Attention", locale: simplifiedChinese) == "关注")
        #expect(ScholiumL10n.string("Connect", locale: simplifiedChinese) == "连接")
        #expect(ScholiumL10n.string("Snapshot", locale: simplifiedChinese) == "快照")
        #expect(ScholiumL10n.string("Comment", locale: simplifiedChinese) == "评论")
        #expect(ScholiumL10n.string("Response", locale: simplifiedChinese) == "回应")
        #expect(ScholiumL10n.string("Review", locale: simplifiedChinese) == "审阅")
        #expect(ScholiumL10n.string("Edit", locale: simplifiedChinese) == "编辑")
        #expect(ScholiumL10n.string("Source", locale: simplifiedChinese) == "源文本")
        #expect(ScholiumL10n.string("Review", locale: english) == "Review")
        #expect(ScholiumL10n.string("Edit", locale: english) == "Edit")
        #expect(ScholiumL10n.string("Settle", locale: simplifiedChinese) == "暂定")
        #expect(ScholiumL10n.string("Completion", locale: simplifiedChinese) == "完成度")
        #expect(ScholiumL10n.string("Incomplete", locale: simplifiedChinese) == "未完成")
        #expect(ScholiumL10n.string("Research Scope", locale: simplifiedChinese) == "研究范围")
        #expect(ScholiumL10n.string("Source basis", locale: simplifiedChinese) == "来源依据")
        #expect(ScholiumL10n.string("Research Record", locale: simplifiedChinese) == "研究记录")
        #expect(ScholiumL10n.string("Restore Access", locale: simplifiedChinese) == "恢复访问权限")
        #expect(
            ScholiumL10n.string("Remove Registration…", locale: simplifiedChinese)
                == "移除此 Mac 上的注册…"
        )
        #expect(
            ScholiumL10n.string("Remove This Triptych Registration?", locale: simplifiedChinese)
                == "移除此脉络注册？"
        )
        #expect(
            ScholiumL10n.string("Remove Registration", locale: simplifiedChinese)
                == "移除注册"
        )
        #expect(
            ScholiumL10n.string("Archive and Rebuild…", locale: simplifiedChinese)
                == "归档并重建…"
        )
        #expect(
            ScholiumL10n.string(
                "Archive and Reset Skill Access…",
                locale: simplifiedChinese
            ) == "归档并重置技能访问…"
        )
        #expect(
            ScholiumL10n.string(
                "Archive and Reset Recovery Policy…",
                locale: simplifiedChinese
            ) == "归档并重置恢复策略…"
        )
        #expect(
            ScholiumL10n.string(
                "Archive Unreadable Saved Searches…",
                locale: simplifiedChinese
            ) == "归档无法读取的已存搜索…"
        )
        #expect(
            ScholiumL10n.string("Quit Scholium", locale: simplifiedChinese)
                == "退出 Scholium"
        )
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
            ScholiumL10n.string("Research Records", locale: simplifiedChinese)
                == "研究记录"
        )
        #expect(
            ScholiumL10n.string("Literature Recommendations", locale: simplifiedChinese)
                == "文献推荐"
        )
        #expect(ScholiumL10n.string("Unprocessed", locale: simplifiedChinese) == "未处理")
        #expect(ScholiumL10n.string("Handled", locale: simplifiedChinese) == "已处理")
        #expect(
            ScholiumL10n.string("This Note Records", locale: simplifiedChinese)
                == "此笔记的记录"
        )
        #expect(
            ScholiumL10n.string("Triptych Records", locale: simplifiedChinese)
                == "研究脉络记录"
        )
        #expect(
            ScholiumL10n.string("ATTRIBUTED RECORD", locale: simplifiedChinese)
                == "署名记录"
        )
        #expect(ScholiumL10n.string("Storage Unavailable", locale: simplifiedChinese) == "存储不可用")
        #expect(ScholiumL10n.string("Details", locale: simplifiedChinese) == "详细信息")
        #expect(ScholiumL10n.string("Quit", locale: simplifiedChinese) == "退出")
        #expect(ScholiumL10n.string("Retry", locale: simplifiedChinese) == "重试")
        #expect(
            ScholiumL10n.string("No Document Selected", locale: simplifiedChinese)
                == "未选择文档"
        )
        #expect(
            ScholiumL10n.string(
                "Select a note in the Library to read or edit.",
                locale: simplifiedChinese
            ) == "请在研究文档中选择一则笔记，以开始阅读或编辑。"
        )
        #expect(ScholiumL10n.string("Save", locale: english) == "Save")
        #expect(
            ScholiumL10n.string(
                "The folder moved, but this window is waiting for the committed refresh.",
                locale: simplifiedChinese
            ) == "文件夹已移动，但此窗口仍在等待已提交内容刷新完成。"
        )
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

    @Test("The application name remains verbatim")
    func verbatimProductName() {
        #expect(ScholiumL10n.string("Scholium", locale: simplifiedChinese) == "Scholium")
    }

    @Test("Application-owned Action modules and handoff controls localize")
    func researchActionCopy() {
        #expect(ScholiumL10n.string("Request", locale: simplifiedChinese) == "请求")
        #expect(ScholiumL10n.string("Materials", locale: simplifiedChinese) == "材料")
        #expect(ScholiumL10n.string("Read-only", locale: simplifiedChinese) == "只读")
        #expect(
            ScholiumL10n.string("REQUESTED NOTES", locale: simplifiedChinese)
                == "请求的笔记"
        )
        #expect(
            ScholiumL10n.string("Loading…", locale: simplifiedChinese)
                == "正在加载…"
        )
        #expect(
            ScholiumL10n.string(
                "Copy New Handoff",
                locale: simplifiedChinese
            ) == "复制新交接说明"
        )
        #expect(
            ScholiumL10n.string("Copy Handoff", locale: simplifiedChinese)
                == "复制交接说明"
        )
        #expect(
            ScholiumL10n.string(
                "Does not change research documents.",
                locale: simplifiedChinese
            ) == "不会更改研究文档。"
        )
        #expect(
            String(
                format: ScholiumL10n.string(
                    "Can update this %@. The Agent may add other relevant Notes to this Run before changing them.",
                    locale: simplifiedChinese
                ),
                "议题"
            ) == "可以更新当前议题。智能体也可先将其他相关笔记加入此次运行，再进行更改。"
        )
        #expect(
            ScholiumL10n.string(
                "Closing this sheet leaves the Action active.",
                locale: simplifiedChinese
            ) == "关闭此工作表后，此操作仍会保持进行中。"
        )
        #expect(
            ScholiumL10n.string("Handoff ready", locale: simplifiedChinese)
                == "交接说明已就绪"
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

    @Test("System Trash and file operations use approved Simplified Chinese terminology")
    func fileOperationTerminology() {
        #expect(ScholiumL10n.string("Move to Trash…", locale: simplifiedChinese) == "移至纸篓…")
        #expect(ScholiumL10n.string("Back to Library", locale: simplifiedChinese) == "返回研究文档")
        #expect(ScholiumL10n.string("Rename Note", locale: simplifiedChinese) == "重命名笔记")
        #expect(ScholiumL10n.string("Rename Note…", locale: simplifiedChinese) == "重命名笔记…")
        #expect(ScholiumL10n.string("Move Note", locale: simplifiedChinese) == "移动笔记")
        #expect(ScholiumL10n.string("Move Note…", locale: simplifiedChinese) == "移动笔记…")
        #expect(
            ScholiumL10n.string(
                "Another folder operation is already in progress.",
                locale: simplifiedChinese
            ) == "另一个文件夹操作正在进行。"
        )

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

        let nativeStrings = SidebarNativeStrings(locale: simplifiedChinese)
        #expect(nativeStrings.newNote == "新建笔记")
        #expect(nativeStrings.newFolder == "新建文件夹")
        #expect(
            nativeStrings.disclosureLabel(
                isExpanded: false,
                title: "Cluster-01"
            ) == "展开 Cluster-01"
        )
        #expect(
            nativeStrings.disclosureLabel(
                isExpanded: true,
                title: "Cluster-01"
            ) == "折叠 Cluster-01"
        )
        #expect(
            nativeStrings.folderAccessibilityValue(
                isEmpty: false,
                isExpanded: true
            ) == "已展开"
        )
    }

    @Test("Interface catalog retires alternate terms and replaced keys")
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
        #expect(!catalog.contains("废纸篓"))
        // `Collapse %@` is now the native Folder disclosure label. It no
        // longer denotes the retired Note-card collapse action.
        for retiredCardKey in [
            "\"Collapse %arg\" :",
            "\"Could Not Open %@\" :",
            "\"Could Not Open %arg\" :",
            "\"No notes are currently in %@.\" :",
            "\"No notes are currently in %arg.\" :",
            "\"Open note in %arg\" :",
            "\"Opening %@…\" :",
            "\"Opening %arg…\" :",
            "\"Move or Rename Note…\" :",
            "\"Move or Rename…\" :",
        ] {
            #expect(!catalog.contains(retiredCardKey))
        }
    }
}
