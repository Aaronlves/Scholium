import Foundation

/// References to the existing preference owners, not another saved state.
/// Keep an isolated value for the Settings session; live owners stay lazy.
@MainActor
struct SettingsPreferences {
    private struct Owners {
        let writingAssistance: WritingAssistancePreferences
        let selectionActions: SelectionActionPreferences
        let chatSidebar: ChatSidebarPreferences
        let agentContextAccess: AgentContextAccessPreferences
    }

    let defaults: UserDefaults
    private let owners: Owners?

    static let standard = SettingsPreferences(defaults: .standard, owners: nil)

    var writingAssistance: WritingAssistancePreferences { owners?.writingAssistance ?? .shared }
    var selectionActions: SelectionActionPreferences { owners?.selectionActions ?? .shared }
    var chatSidebar: ChatSidebarPreferences { owners?.chatSidebar ?? .shared }
    var agentContextAccess: AgentContextAccessPreferences { owners?.agentContextAccess ?? .shared }

    init(defaults: UserDefaults) {
        self.init(
            defaults: defaults,
            owners: Owners(
                writingAssistance: WritingAssistancePreferences(defaults: defaults),
                selectionActions: SelectionActionPreferences(defaults: defaults),
                chatSidebar: ChatSidebarPreferences(defaults: defaults),
                agentContextAccess: AgentContextAccessPreferences(defaults: defaults)
            )
        )
    }

    private init(defaults: UserDefaults, owners: Owners?) {
        self.defaults = defaults
        self.owners = owners
    }
}
