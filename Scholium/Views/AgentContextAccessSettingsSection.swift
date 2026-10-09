import SwiftUI

struct AgentContextAccessSettingsSection: View {
    let caller: AgentContextCaller
    @ObservedObject var preferences: AgentContextAccessPreferences

    var body: some View {
        Section {
            Toggle(isOn: stateAccess) {
                switch caller {
                case .chat: Text("Allow Chat agents to inspect Scholium state", bundle: .module)
                case .external: Text("Allow external agents to inspect Scholium state", bundle: .module)
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("scholium.settings.agentContext.\(caller.rawValue).state")
            .id("agents.context.\(caller.rawValue).state")
            Text("Shows which Notes are open, research pane state, retrieval freshness and recovery status on request.", bundle: .module)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if preferences.invalidStoredKeys.contains(stateKey) {
                Text("Stored state access is invalid and disabled. Change this checkbox to save a valid choice.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle(isOn: workingTextAccess) {
                switch caller {
                case .chat: Text("Allow Chat agents to read working text", bundle: .module)
                case .external: Text("Allow external agents to read working text", bundle: .module)
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("scholium.settings.agentContext.\(caller.rawValue).workingText")
            .id("agents.context.\(caller.rawValue).workingText")
            Text(
                "Includes the active Note's unsaved text, its selected passage and Kept Passages. Conversation drafts and queued messages stay private.",
                bundle: .module
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if preferences.invalidStoredKeys.contains(workingTextKey) {
                Text("Stored working-text access is invalid and disabled. Change this checkbox to save a valid choice.", bundle: .module)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(
                "These read grants take effect immediately and are independent of Ask for Approval or Full Access for Note changes and runtime operations.",
                bundle: .module
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Agent Context Access — This Mac", bundle: .module)
        }
    }

    private var stateKey: String {
        caller == .chat ? AgentContextAccessPreferences.chatStateKey : AgentContextAccessPreferences.externalStateKey
    }

    private var workingTextKey: String {
        caller == .chat ? AgentContextAccessPreferences.chatWorkingTextKey : AgentContextAccessPreferences.externalWorkingTextKey
    }

    private var stateAccess: Binding<Bool> {
        switch caller {
        case .chat: $preferences.chatStateAccess
        case .external: $preferences.externalStateAccess
        }
    }

    private var workingTextAccess: Binding<Bool> {
        switch caller {
        case .chat: $preferences.chatWorkingTextAccess
        case .external: $preferences.externalWorkingTextAccess
        }
    }
}
