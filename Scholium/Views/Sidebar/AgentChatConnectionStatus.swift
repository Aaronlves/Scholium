import SwiftUI

/// Shared connection projection; the shell presents diagnostics.
struct AgentChatConnectionStatus: View {
    @ObservedObject var controller: AgentChatController
    @Environment(\.openSettings) private var openSettings
    let showDiagnostics: (String) -> Void

    @ViewBuilder
    var body: some View {
        if controller.isRenewingSettings {
            if let error = controller.settingsRenewalError {
                ScholiumSidebarState(Text("Settings Could Not Be Applied"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                    Button("Retry") { controller.renewSettingsWhenIdle() }
                    Button("Diagnostics…") {
                        showDiagnostics(error)
                    }
                }
            } else {
                ScholiumSidebarState(Text("Applying Settings…"), indicator: .progress)
            }
        } else if controller.isLoaded {
            if controller.connectionState == .disconnected {
                ScholiumSidebarState(Text("Not Connected"), indicator: .symbol("network")) {
                    Button("Connect Codex") { controller.connectConfigured() }
                }
            } else if controller.connectionState == .connecting {
                ScholiumSidebarState(Text("Connecting…"), indicator: .progress)
            } else if controller.account == nil {
                ScholiumSidebarState(Text("Sign-In Required"), indicator: .symbol("person.crop.circle")) {
                    Button("Sign in with ChatGPT") { controller.login() }.disabled(controller.isBusy)
                }
            }
        }
        if let error = controller.capabilities.workspaceError {
            ScholiumSidebarState(Text("Skills Could Not Be Loaded"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                Button("Refresh Skills") {
                    controller.capabilities.refresh(threadID: controller.selected?.threadID, reloadWorkspace: true)
                }.disabled(controller.isBusy || controller.capabilities.isRefreshing)
                Button("Diagnostics…") {
                    showDiagnostics(error)
                }
            }
        }
        if controller.historyUnavailable {
            ScholiumSidebarState(
                Text("Conversation Unavailable"),
                detail: Text("This conversation is saved here, but unavailable in the connected runtime."),
                indicator: .symbol("exclamationmark.triangle", role: .attention)
            ) {
                Button("Retry") { controller.retryHistory() }.disabled(controller.isBusy)
                Button("New Conversation") { controller.newConversation() }
            }
        }
        if let error = controller.error {
            ScholiumSidebarState(Text("Conversation Needs Attention"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                Button("Diagnostics…") {
                    showDiagnostics(error)
                }
                if controller.state == .disconnected {
                    Button("Agent Settings…") {
                        SettingsNavigationRequest.select(.agents, agentCategory: .connection)
                        openSettings()
                    }
                }
            }
        }
    }

}
