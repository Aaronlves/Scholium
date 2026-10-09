import Foundation
import SwiftUI

/// Static interface destinations only. No runtime inventory, research content or
/// editable values enter Settings search. A result routes to the sole editor.
struct SettingsSearchTarget: Identifiable, Equatable {
    let id: String
    let section: SettingsSection
    var destination: ScholiumSettingsDestination { section.destination }
    let title: LocalizedStringResource
    let terms: [String]
    let aliases: [LocalizedStringResource]
    private let searchableLabels: [String]

    private init(
        _ id: String, _ section: SettingsSection, _ title: LocalizedStringResource,
        _ terms: [String], aliases: [LocalizedStringResource] = []
    ) {
        self.id = id
        self.section = section
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
                "workspace.registration", .workspaceRegistration, "Registered Triptychs",
                ["Workspace", "Triptych", "registration", "工作区", "三联体", "注册"],
                aliases: ["Open Workspace Settings"]),
            Self(
                "workspace.name", .workspaceName, "Name", ["Triptych name", "三联体名称", "工作区名称"],
                aliases: ["Triptych Details"]),
            Self(
                "workspace.folders", .workspaceFolders, "Research Folders",
                [
                    "folders", "locations", "paths", "Analyses", "Topics", "Works", "研究文件夹", "路径", "分析库",
                    "主题库", "作品库",
                ]),
            Self(
                "workspace.portable", .workspacePortable, "Portable Triptych Data",
                ["authorization", "access", "portable data", "授权", "访问", "便携数据"]),
            Self(
                "workspace.settingsRecovery", .workspaceSettingsRecovery, "Portable Settings",
                ["restore defaults", "recovery", "damaged settings", "恢复默认", "修复设置", "设置损坏"],
                aliases: ["Restore Portable Settings Defaults…"]),
            Self(
                "workspace.changesHistory", .workspaceChangesHistory, "Changes History",
                ["reviewed history", "retention", "clear reviewed history", "修改历史", "保留期限", "清除已查看历史"],
                aliases: ["Keep Reviewed History", "Clear Reviewed History…"]),
            Self(
                "appearance.profile", .appearanceProfile, "Profile", ["appearance", "configuration", "repair profile", "文稿外观", "外观配置", "修复外观"],
                aliases: ["Rename Appearance…", "Restore Default Appearance…", "Save Appearance", "Recover Default Appearance…", "Repair Saved Profile"]),
            Self(
                "appearance.bodyFont", .appearanceReading, "Body Font", ["reading", "font", "阅读", "正文字体"]),
            Self(
                "appearance.bodySize", .appearanceReading, "Body font size", ["body size", "字号", "正文字号"]),
            Self(
                "appearance.width", .appearanceReading, "Reading line width", ["line width", "阅读行宽", "行宽"]),
            Self(
                "appearance.lineSpacing", .appearanceReading, "Line spacing", ["line spacing", "行距"]),
            Self("appearance.alignment", .appearanceReading, "Alignment", ["对齐"]),
            Self(
                "appearance.hyphenation", .appearanceHyphenation, "Hyphenation",
                ["hyphenation", "hyphens", "syllables", "断词", "音节"]),
            Self(
                "appearance.paragraphSpacing", .appearanceBody, "Paragraph spacing", ["paragraph", "段间距"]),
            Self(
                "appearance.indent", .appearanceBody, "First-line indent", ["indent", "首行缩进"]),
            Self(
                "appearance.headingFont", .appearanceHeadingFont, "Heading Font", ["heading typography", "标题字体", "标题排版"]),
            Self(
                "appearance.headingStyle", .appearanceHeadingFont, "Heading Style", ["标题样式"]),
            Self(
                "appearance.headingWeight", .appearanceHeadingFont, "Heading Weight", ["标题字重"]),
            Self(
                "appearance.headingSpacing", .appearanceHeadingFont, "Heading Line Spacing", ["标题行距"]),
            Self(
                "appearance.headings", .appearanceHeadings, "Heading Hierarchy",
                [
                    "heading levels", "heading level", "scale", "space before", "space after", "标题层级", "标题级别",
                    "比例", "段前间距", "段后间距",
                ]),
            Self("appearance.styles", .appearanceStyles, "Text Styles", ["bold", "italic", "粗体", "斜体"]),
            Self("appearance.source", .appearanceSource, "Source Font", ["源码字体"]),
            Self("appearance.sourceSize", .appearanceSource, "Source font size", ["源码字号"]),
            Self("appearance.bodyBoldFont", .appearanceStyles, "Body Bold Font", ["正文粗体字体"]),
            Self("appearance.bodyItalicFont", .appearanceStyles, "Body Italic Font", ["正文斜体字体"]),
            Self("appearance.headingBoldFont", .appearanceStyles, "Heading Bold Font", ["标题粗体字体"]),
            Self("appearance.headingItalicFont", .appearanceStyles, "Heading Italic Font", ["标题斜体字体"]),
            Self(
                "appearance.css", .appearanceCSS, "CSS Snippets",
                [
                    "Advanced CSS", "letter spacing", "word spacing", "kerning", "ligatures",
                    "Open CSS Folder", "CSS", "高级排版", "字距", "词距", "字偶距", "连字",
                ], aliases: ["Import CSS Snippet…", "Open CSS Folder"]),
            Self(
                "appearance.file", .appearanceFile, "Configuration File",
                ["reload appearance", "configuration guide", "配置文件", "重新载入外观"],
                aliases: ["Show in Finder…", "Reload", "Configuration Guide…"]),
            Self(
                "writing.continuation", .writingContinuation, ScholiumL10n.WritingAssistance.enable,
                ["Writing Assistance", "Writing Continuation", "autocomplete", "completion", "sentence", "写作辅助", "写作续写", "续写", "补全"]),
            Self(
                "writing.model", .writingModel, ScholiumL10n.WritingAssistance.model, ["续写模型", "解释模型", "润色模型"]),
            Self(
                "writing.selection", .writingSelection, "Selection Actions",
                ["selection", "prompt", "instruction", "选段操作", "选区操作", "指令"]),
            Self(
                "agents.chatSidebar", .agentChatSidebar, "Show Chat in Sidebar",
                ["Chat Sidebar", "show", "hide", "enable", "disable", "built-in Chat", "聊天边栏", "显示聊天", "隐藏聊天", "启用聊天", "关闭聊天"]),
            Self(
                "agents.context.chat.state", .agentContextState(.chat), "Allow Chat agents to inspect Scholium state",
                ["Chat state access", "Agent Context Access", "open Notes", "聊天状态访问", "智能体上下文访问", "已打开笔记"]),
            Self(
                "agents.context.chat.workingText", .agentContextWorkingText(.chat), "Allow Chat agents to read working text",
                ["Chat working text", "unsaved text", "Kept Passages", "聊天工作文本", "未保存文本", "保留段落"]),
            Self(
                "agents.context.external.state", .agentContextState(.external), "Allow external agents to inspect Scholium state",
                ["External state access", "MCP state", "外部状态访问", "MCP 状态"]),
            Self(
                "agents.context.external.workingText", .agentContextWorkingText(.external), "Allow external agents to read working text",
                ["External working text", "MCP working text", "外部工作文本", "MCP 工作文本"]),
            Self(
                "agents.connection", .agentConnection, "Chat in Scholium",
                ["Agents & Chat", "connect", "sign in", "Codex", "聊天", "智能体", "连接", "登录"],
                aliases: ["Open Connection and Chat"]),
            Self(
                "agents.behavior", .agentBehavior, "Return while Agent is working",
                ["return", "queue", "steer", "send", "回车", "排队", "发送行为"]),
            Self(
                "agents.paths", .agentPaths, "Custom Connection Paths",
                [
                    "Codex Application", "Connection Helper", "Existing Codex Settings Folder", "runtime",
                    "自定义连接路径", "运行时",
                ], aliases: ["Scholium Connection Helper", "Use Automatic Setup"]),
            Self("agents.protocol", .agentCoreProtocol, "Core Protocol", ["核心协议"]),
            Self("agents.skills", .agentSkills, "Skills", ["skills", "methods", "技能"]),
            Self(
                "agents.tools", .agentTools, "Connected Tools",
                ["tools", "MCP", "authentication", "工具", "工具授权"],
                aliases: [
                    "Server Address", "Bearer Token Variable", "Authentication and Environment",
                    "Environment Variables — One per Line", "Reuse Existing Access Settings", "Arguments — One per Line",
                ]),
            Self(
                "agents.external", .agentExternal, "External Access",
                [
                    "External Agent Hosts", "bridge", "Claude", "setup command", "外部智能体", "外部接入", "桥接",
                    "配置命令",
                ], aliases: ["Copy Codex Setup Command", "Copy Claude Setup Command"]),
            Self(
                "zotero.desktop", .zoteroDesktop, "Local Zotero API",
                ["Zotero", "citation", "library", "local API", "文献", "引用", "本地 API"],
                aliases: ["Zotero Desktop"]),
            Self(
                "zotero.chat", .zoteroChat, "Zotero in Chat",
                ["Zotero connection", "Zotero in Chat", "聊天 Zotero"]),
        ]
            + AppearanceHeadingLevel.allCases.map { level in
                let label = level.rawValue.uppercased()
                return Self(
                    "appearance.\(level.rawValue)", .appearanceHeading(level), level.title,
                    [label, "\(label) spacing", "\(label) 间距"])
            }
            + ScholiumHotkeyCommand.customizableCommands.map { command in
                Self(
                    "shortcut.\(command.rawValue)", .shortcut(command), command.title,
                    [
                        "Keyboard Shortcuts", "shortcut", "hotkey", "快捷键",
                    ], aliases: [command.menuPath])
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
