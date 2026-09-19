import Foundation
import SwiftUI

/// Static interface destinations only. No runtime inventory, research content or
/// editable values enter Settings search. A result routes to the sole editor.
struct SettingsSearchTarget: Identifiable, Equatable {
    let id: String
    let destination: ScholiumSettingsDestination
    let sectionID: String
    let title: LocalizedStringResource
    let terms: [String]
    let aliases: [LocalizedStringResource]
    private let searchableLabels: [String]

    private init(
        _ id: String, _ destination: ScholiumSettingsDestination, _ title: LocalizedStringResource,
        _ terms: [String], section: String? = nil, aliases: [LocalizedStringResource] = []
    ) {
        self.id = id
        self.destination = destination
        self.sectionID = section ?? id
        self.title = LocalizedStringResource(title.defaultValue, table: title.table ?? "Localizable", bundle: .module)
        self.terms = terms
        self.aliases = aliases.map {
            LocalizedStringResource($0.defaultValue, table: $0.table ?? "Localizable", bundle: .module)
        }
        self.searchableLabels =
            ([self.title] + self.aliases).flatMap { label in
                ["en", "zh-Hans"].map { language in
                    var resource = label
                    resource.locale = Locale(identifier: language)
                    return String(localized: resource)
                }
            } + terms
    }

    static let all: [Self] = {
        [
            Self(
                "workspace.registration", .workspace, "Registered Triptychs",
                ["Workspace", "Triptych", "registration", "工作区", "三联体", "注册"]),
            Self("workspace.name", .workspace, "Name", ["Triptych name", "三联体名称", "工作区名称"]),
            Self(
                "workspace.folders", .workspace, "Research Folders",
                [
                    "folders", "locations", "paths", "Analyses", "Topics", "Works", "研究文件夹", "路径", "分析库",
                    "主题库", "作品库",
                ]),
            Self(
                "workspace.portable", .workspace, "Portable Triptych Data",
                ["authorization", "access", "portable data", "授权", "访问", "便携数据"]),
            Self(
                "workspace.settingsRecovery", .workspace, "Portable Settings",
                ["restore defaults", "recovery", "damaged settings", "恢复默认", "修复设置", "设置损坏"],
                aliases: ["Restore Portable Settings Defaults…"]),
            Self(
                "appearance.profile", .document, "Profile", ["appearance", "configuration", "repair profile", "文稿外观", "外观配置", "修复外观"],
                aliases: ["Rename Appearance…", "Restore Default Appearance…", "Save Appearance", "Recover Default Appearance…", "Repair Saved Profile"]),
            Self(
                "appearance.bodyFont", .document, "Body Font", ["reading", "font", "阅读", "正文字体"],
                section: "appearance.reading"),
            Self(
                "appearance.bodySize", .document, "Body font size", ["body size", "字号", "正文字号"],
                section: "appearance.reading"),
            Self(
                "appearance.width", .document, "Line width", ["line width", "行宽"],
                section: "appearance.reading"),
            Self(
                "appearance.lineSpacing", .document, "Line spacing", ["line spacing", "行距"],
                section: "appearance.reading"),
            Self("appearance.alignment", .document, "Alignment", ["对齐"], section: "appearance.reading"),
            Self(
                "appearance.hyphenation", .document, "Hyphenation",
                ["hyphenation", "hyphens", "syllables", "断词", "音节"],
                section: "appearance.hyphenation"),
            Self(
                "appearance.paragraphSpacing", .document, "Paragraph spacing", ["paragraph", "段间距"],
                section: "appearance.body"),
            Self(
                "appearance.indent", .document, "First-line indent", ["indent", "首行缩进"],
                section: "appearance.body"),
            Self(
                "appearance.headingFont", .document, "Heading Font", ["heading typography", "标题字体", "标题排版"]),
            Self(
                "appearance.headingStyle", .document, "Heading Style", ["标题样式"],
                section: "appearance.headingFont"),
            Self(
                "appearance.headingWeight", .document, "Heading Weight", ["标题字重"],
                section: "appearance.headingFont"),
            Self(
                "appearance.headingSpacing", .document, "Heading Line Spacing", ["标题行距"],
                section: "appearance.headingFont"),
            Self(
                "appearance.headings", .document, "Heading Hierarchy",
                [
                    "heading levels", "heading level", "scale", "space before", "space after", "标题层级", "标题级别",
                    "比例", "段前间距", "段后间距",
                ]),
            Self("appearance.styles", .document, "Text Styles", ["bold", "italic", "粗体", "斜体"]),
            Self("appearance.source", .document, "Source Font", ["源码字体"]),
            Self("appearance.sourceSize", .document, "Source font size", ["源码字号"], section: "appearance.source"),
            Self("appearance.bodyBoldFont", .document, "Body Bold Font", ["正文粗体字体"], section: "appearance.styles"),
            Self("appearance.bodyItalicFont", .document, "Body Italic Font", ["正文斜体字体"], section: "appearance.styles"),
            Self("appearance.headingBoldFont", .document, "Heading Bold Font", ["标题粗体字体"], section: "appearance.styles"),
            Self("appearance.headingItalicFont", .document, "Heading Italic Font", ["标题斜体字体"], section: "appearance.styles"),
            Self(
                "appearance.css", .document, "CSS Snippets",
                [
                    "Advanced CSS", "letter spacing", "word spacing", "kerning", "ligatures",
                    "Open CSS Folder", "CSS", "高级排版", "字距", "词距", "字偶距", "连字",
                ], aliases: ["Import CSS Snippet…", "Open CSS Folder"]),
            Self(
                "appearance.file", .document, "Configuration File",
                ["reload appearance", "configuration guide", "配置文件", "重新载入外观"],
                aliases: ["Show in Finder…", "Reload", "Configuration Guide…"]),
            Self(
                "writing.continuation", .writing, ScholiumL10n.WritingAssistance.enable,
                ["Writing Assistance", "Writing Continuation", "autocomplete", "completion", "sentence", "写作辅助", "写作续写", "续写", "补全"]),
            Self(
                "writing.model", .writing, ScholiumL10n.WritingAssistance.model, ["续写模型"], section: "writing.continuation"),
            Self(
                "writing.selection", .writing, "Selection Actions",
                ["selection", "prompt", "instruction", "选段操作", "选区操作", "指令"]),
            Self(
                "agents.connection", .agents, "Chat in Scholium",
                ["Agents & Chat", "connect", "sign in", "Codex", "聊天", "智能体", "连接", "登录"]),
            Self(
                "agents.behavior", .agents, "Return while Agent is working",
                ["return", "queue", "steer", "send", "回车", "排队", "发送行为"]),
            Self(
                "agents.paths", .agents, "Custom Connection Paths",
                [
                    "Codex Application", "Connection Helper", "Existing Codex Settings Folder", "runtime",
                    "自定义连接路径", "运行时",
                ], aliases: ["Scholium Connection Helper", "Use Automatic Setup"]),
            Self("agents.protocol", .agents, "Core Protocol", ["核心协议"]),
            Self("agents.skills", .agents, "Skills", ["skills", "methods", "技能"]),
            Self(
                "agents.tools", .agents, "Connected Tools",
                ["tools", "MCP", "authentication", "工具", "工具授权"],
                aliases: [
                    "Server Address", "Bearer Token Variable", "Authentication and Environment",
                    "Environment Variables — One per Line", "Reuse Existing Access Settings", "Arguments — One per Line",
                ]),
            Self(
                "agents.external", .agents, "External Access",
                [
                    "External Agent Hosts", "bridge", "Claude", "setup command", "外部智能体", "外部接入", "桥接",
                    "配置命令",
                ], aliases: ["Copy Codex Setup Command", "Copy Claude Setup Command"]),
            Self(
                "notifications.timing", .notifications, "Reminder Timing",
                ["notifications", "reminders", "timing", "通知", "提醒", "间隔"]),
            Self("notifications.return", .notifications, "Return dismissed items after", ["提醒恢复时间"], section: "notifications.timing"),
            Self(
                "notifications.dismissed", .notifications, "Dismissed Items on This Mac",
                ["restore dismissed", "已忽略", "恢复提醒"],
                aliases: ["Restore All Dismissed Items on This Mac"]),
            Self(
                "zotero.desktop", .zotero, "Local Zotero API",
                ["Zotero", "citation", "library", "local API", "文献", "引用", "本地 API"]),
            Self(
                "zotero.chat", .zotero, "Zotero in Chat",
                ["Zotero connection", "Zotero in Chat", "聊天 Zotero"]),
        ]
            + (1...6).map { level in
                Self(
                    "appearance.h\(level)", .document, LocalizedStringResource(stringLiteral: "H\(level)"),
                    ["H\(level)", "H\(level) spacing", "H\(level) 间距"])
            }
            + ScholiumHotkeyCommand.customizableCommands.map { command in
                Self(
                    "shortcut.\(command.rawValue)", .shortcuts, command.title,
                    [
                        "Keyboard Shortcuts", "shortcut", "hotkey", "快捷键",
                    ], section: command.rawValue, aliases: [command.menuPath])
            }
    }()

    static func matches(_ query: String) -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return all.filter { target in
            target.searchableLabels.contains {
                $0.localizedCaseInsensitiveContains(query)
            }
        }.sorted { lhs, rhs in
            let leftExact = lhs.searchableLabels.contains {
                $0.localizedCaseInsensitiveCompare(query) == .orderedSame
            }
            let rightExact = rhs.searchableLabels.contains {
                $0.localizedCaseInsensitiveCompare(query) == .orderedSame
            }
            return leftExact && !rightExact
        }
    }
}
