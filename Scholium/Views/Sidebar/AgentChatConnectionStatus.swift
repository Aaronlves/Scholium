import SwiftUI

/// Shared connection projection; the shell presents diagnostics.
struct AgentChatConnectionStatus: View {
    @ObservedObject var controller: AgentChatController
    @Binding var diagnosticsPresentation: AgentChatDiagnosticsPresentation?
    @Environment(\.openSettings) private var openSettings

    private var executionError: String? {
        controller.selectedID.flatMap { controller.executions[$0]?.error }
    }

    @ViewBuilder
    var body: some View {
        if controller.isRenewingSettings {
            if let error = controller.settingsRenewalError {
                ScholiumSidebarState(Text("Settings Could Not Be Applied"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                    Button("Retry") { controller.renewSettingsWhenIdle() }
                    AgentChatDiagnosticsButton(
                        controller: controller, presentation: $diagnosticsPresentation, error: error)
                }
            } else {
                ScholiumSidebarState(Text("Applying Settings…"), indicator: .progress)
            }
        } else if controller.isLoaded {
            if controller.connectionState == .disconnected {
                if let error = controller.connectionError {
                    ScholiumSidebarState(
                        Text("Connection Failed", bundle: .module),
                        detail: Text("Retry the connection or open Diagnostics.", bundle: .module),
                        indicator: .symbol("exclamationmark.triangle", role: .attention)
                    ) {
                        Button("Retry") { controller.connectConfigured() }
                        AgentChatDiagnosticsButton(
                            controller: controller, presentation: $diagnosticsPresentation, error: error)
                    }
                } else {
                    ScholiumSidebarState(Text("Not Connected"), indicator: .symbol("network")) {
                        Button("Connect Codex") { controller.connectConfigured() }
                    }
                }
            } else if controller.connectionState == .connecting {
                ScholiumSidebarState(Text("Connecting…"), indicator: .progress)
            } else if controller.account == nil {
                if let error = controller.connectionError {
                    ScholiumSidebarState(
                        Text("Sign-In Failed", bundle: .module),
                        detail: Text("Try signing in again or open Diagnostics.", bundle: .module),
                        indicator: .symbol("exclamationmark.triangle", role: .attention)
                    ) {
                        Button("Sign in with ChatGPT") { controller.login() }.disabled(controller.isBusy)
                        AgentChatDiagnosticsButton(
                            controller: controller, presentation: $diagnosticsPresentation, error: error)
                    }
                } else {
                    ScholiumSidebarState(Text("Sign-In Required"), indicator: .symbol("person.crop.circle")) {
                        Button("Sign in with ChatGPT") { controller.login() }.disabled(controller.isBusy)
                    }
                }
            }
        }
        if let error = controller.capabilities.workspaceError {
            ScholiumSidebarState(Text("Skills Could Not Be Loaded"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                Button("Refresh Skills") {
                    controller.capabilities.refresh(threadID: controller.selected?.threadID, reloadWorkspace: true)
                }.disabled(controller.isBusy || controller.capabilities.isRefreshing)
                AgentChatDiagnosticsButton(
                    controller: controller, presentation: $diagnosticsPresentation, error: error)
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
        if let error = executionError {
            ScholiumSidebarState(Text("Conversation Needs Attention"), indicator: .symbol("exclamationmark.triangle", role: .attention)) {
                AgentChatDiagnosticsButton(
                    controller: controller, presentation: $diagnosticsPresentation, error: error)
                if controller.connectionState == .disconnected {
                    Button("Agent Settings…") {
                        SettingsNavigationRequest.select(.agents, agentCategory: .connection)
                        openSettings()
                    }
                }
            }
        }
    }

}
