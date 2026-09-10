import AppKit
import ScholiumApplication
import SwiftUI

struct AgentIntegrationSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.agentChatSettingsController) private var chatController

    @State private var showsExternalAgentHosts = false

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            if let chatController {
        AgentChatConnectionSettingsView(
            controller: chatController,
            onShowExternalAgentHosts: { showsExternalAgentHosts = true }
        )
        .id(chatController.triptychID)
      } else {
        settingsEditorSection("Chat in Scholium") {
            Text("Open a Triptych to manage its Chat connection.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        settingsEditorSection("Advanced") {
            Button("External Agent Hosts…") {
                showsExternalAgentHosts = true
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 760, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .top)
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.agents")
        .sheet(isPresented: $showsExternalAgentHosts) {
            ExternalAgentHostsSettingsView(settingsModel: settingsModel)
        }
    }
}

private struct ExternalAgentHostsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settingsModel: WorkspaceSettingsModel
    @State private var copyStatus: String?

    private let cliURL = ScholiumAgentIntegrationResources.scholiumCLIURL()
    private let coreProtocolURL = try? ScholiumAgentIntegrationResources
        .coreProtocolSkillDirectoryURL()

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            settingsTitle(
                "External Agent Hosts",
                detail: "Connect an external Agent host to Scholium through the local bridge."
            )

            settingsFormSection("Status") {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    statusRow("Scholium App", detail: String(localized: "Available"), available: true)
                    switch settingsModel.agentBridgeAvailability {
                    case .available:
                        statusRow("App Bridge", detail: String(localized: "Available"), available: true)
                    case .unavailable(let reason):
                        statusRow("App Bridge", detail: reason, available: false)
                    }
                    statusRow(
                        "Scholium CLI",
                        detail: cliURL == nil ? String(localized: "Unavailable") : String(localized: "Available"),
                        available: cliURL != nil
                    )
                }
            }

            settingsFormSection("Setup") {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Text("Copies a setup command. Run it in your Agent host to connect.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Button("Copy Codex Setup Command") {
                            copySetupCommand(for: .codex)
                        }
                        Button("Copy Claude Setup Command") {
                            copySetupCommand(for: .claude)
                        }
                    }
                    .disabled(cliURL == nil)

                    if let copyStatus { Text(copyStatus).font(.caption).textSelection(.enabled) }

                    if cliURL == nil {
                        Text("Install the compatible Scholium CLI before copying a setup command.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            settingsFormSection("Core Protocol") {
                Button("Show Core Protocol in Finder…") {
                    guard let coreProtocolURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([coreProtocolURL])
                }
                .disabled(coreProtocolURL == nil)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 760, height: 360, alignment: .topLeading)
    }

    private func statusRow(
        _ title: LocalizedStringKey,
        detail: String,
        available: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Label(title, systemImage: available ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)
            Text(verbatim: detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func copySetupCommand(for host: AgentIntegrationHost) {
        guard let cliURL else { return }
        let command = host.command(cliURL: cliURL)
        let copied = ScholiumPasteboardWriter.general.writeText(command)
        copyStatus = copied ? "\(host.title) setup command copied"
            : "\(host.title) setup command could not be copied."

    }
}

private enum AgentIntegrationHost {
    case codex
    case claude

    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    func command(cliURL: URL) -> String {
        let executable = Self.shellQuoted(cliURL.path)
        return switch self {
        case .codex:
            "codex mcp add scholium -- \(executable) mcp serve"
        case .claude:
            "claude mcp add scholium --scope user -- \(executable) mcp serve"
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
