import SwiftUI

/// The identity of one Settings editing location. Search, contextual links and
/// scroll anchors share its pane and Agent segment instead of rebuilding routes.
struct SettingsSection: Hashable, Identifiable {
    let id: String
    let destination: ScholiumSettingsDestination
    let agentCategory: AgentSettingsCategory?

    private init(_ id: String, _ destination: ScholiumSettingsDestination, agentCategory: AgentSettingsCategory? = nil) {
        self.id = id
        self.destination = destination
        self.agentCategory = agentCategory
    }

    static let workspaceRegistration = Self("workspace.registration", .workspace)
    static let workspaceName = Self("workspace.name", .workspace)
    static let workspaceFolders = Self("workspace.folders", .workspace)
    static let workspacePortable = Self("workspace.portable", .workspace)
    static let workspaceSettingsRecovery = Self("workspace.settingsRecovery", .workspace)
    static let workspaceChangesHistory = Self("workspace.changesHistory", .workspace)

    static let appearanceProfile = Self("appearance.profile", .document)
    static let appearanceReading = Self("appearance.reading", .document)
    static let appearanceHyphenation = Self("appearance.hyphenation", .document)
    static let appearanceBody = Self("appearance.body", .document)
    static let appearanceHeadingFont = Self("appearance.headingFont", .document)
    static let appearanceHeadings = Self("appearance.headings", .document)
    static let appearanceStyles = Self("appearance.styles", .document)
    static let appearanceSource = Self("appearance.source", .document)
    static let appearanceCSS = Self("appearance.css", .document)
    static let appearanceFile = Self("appearance.file", .document)

    static func appearanceHeading(_ level: AppearanceHeadingLevel) -> Self {
        Self("appearance.\(level.rawValue)", .document)
    }

    static let writingContinuation = Self("writing.continuation", .writing)
    static let writingModel = Self("writing.model", .writing)
    static let writingSelection = Self("writing.selection", .writing)

    static let agentChatSidebar = Self("agents.chatSidebar", .agents, agentCategory: .connection)
    static let agentConnection = Self("agents.connection", .agents, agentCategory: .connection)
    static let agentBehavior = Self("agents.behavior", .agents, agentCategory: .connection)
    static let agentPaths = Self("agents.paths", .agents, agentCategory: .connection)
    static let agentCoreProtocol = Self("agents.protocol", .agents, agentCategory: .capabilities)
    static let agentSkills = Self("agents.skills", .agents, agentCategory: .capabilities)
    static let agentTools = Self("agents.tools", .agents, agentCategory: .capabilities)
    static let agentExternal = Self("agents.external", .agents, agentCategory: .externalAccess)

    static func agentContextState(_ caller: AgentContextCaller) -> Self {
        Self("agents.context.\(caller.rawValue).state", .agents, agentCategory: caller == .chat ? .connection : .externalAccess)
    }

    static func agentContextWorkingText(_ caller: AgentContextCaller) -> Self {
        Self("agents.context.\(caller.rawValue).workingText", .agents, agentCategory: caller == .chat ? .connection : .externalAccess)
    }

    static let zoteroDesktop = Self("zotero.desktop", .zotero)
    static let zoteroChat = Self("zotero.chat", .zotero)

    static func shortcut(_ command: ScholiumHotkeyCommand) -> Self {
        Self(command.rawValue, .shortcuts)
    }
}

enum AppearanceHeadingLevel: String, CaseIterable, Identifiable {
    case h1, h2, h3, h4, h5, h6

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .h1: "H1"
        case .h2: "H2"
        case .h3: "H3"
        case .h4: "H4"
        case .h5: "H5"
        case .h6: "H6"
        }
    }
}
