import AppKit
import ScholiumApplication
import SwiftUI

struct AgentIntegrationSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel

    private let cliURL = ScholiumAgentIntegrationResources.scholiumCLIURL()
    private let coreProtocolURL = try? ScholiumAgentIntegrationResources
        .coreProtocolSkillDirectoryURL()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Agent Integration",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Connect an external Agent host to the currently running Scholium App through the local MCP adapter.",
                        table: "Localizable",
                        bundle: .module
                    )
                )

                researchSettingsSection("AVAILABILITY") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        statusRow("Scholium App", detail: "Available", available: true)
                        switch settingsModel.agentBridgeAvailability {
                        case .available:
                            statusRow("App Bridge", detail: "Available", available: true)
                        case .unavailable(let reason):
                            statusRow("App Bridge", detail: reason, available: false)
                        }
                        statusRow(
                            "Scholium CLI",
                            detail: cliURL?.path ?? "Not found at $HOME/.local/bin/scholium",
                            available: cliURL != nil
                        )
                    }
                }

                researchSettingsSection("SETUP") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Text("These commands register the same local stdio server at user scope. Scholium copies the command only; it does not edit either host’s settings or claim setup succeeded.")
                            .font(ScholiumTypography.interface(.body))
                            .scholiumForeground(.secondaryText)
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

                        if cliURL == nil {
                            Text("Install the compatible Scholium CLI before copying a setup command.")
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(.attention)
                        }
                    }
                }

                researchSettingsSection("CORE PROTOCOL") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        Text("The release-bundled scholium-core-protocol folder is an ordinary Skill. You may inspect it and install it in your Agent host alongside your own method Skills.")
                            .font(ScholiumTypography.interface(.body))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Show Core Protocol in Finder…") {
                            guard let coreProtocolURL else { return }
                            NSWorkspace.shared.activateFileViewerSelecting([coreProtocolURL])
                        }
                        .disabled(coreProtocolURL == nil)
                    }
                }

                Text("MCP tool availability is not permission to modify research material. Write scope comes only from the researcher’s explicit request in the external conversation.")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.researchGuidance.agentIntegration")
    }

    private func statusRow(
        _ title: LocalizedStringKey,
        detail: String,
        available: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Label(title, systemImage: available ? "checkmark.circle" : "exclamationmark.triangle")
                .font(ScholiumTypography.interface(.body, emphasis: .strong))
                .scholiumForeground(available ? .confirmed : .attention)
                .frame(width: 150, alignment: .leading)
            Text(verbatim: detail)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func copySetupCommand(for host: AgentIntegrationHost) {
        guard let cliURL else { return }
        let command = host.command(cliURL: cliURL)
        let copied = ScholiumPasteboardWriter.general.writeText(command)
        settingsModel.presentFeedback(
            copied ? "\(host.title) setup command copied"
                : "\(host.title) setup command could not be copied.",
            kind: copied ? .confirmation : .error
        )
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
