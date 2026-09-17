import AppKit
import ScholiumApplication
import SwiftUI

enum AgentSettingsCategory: String, CaseIterable, Identifiable {
    case connection, capabilities, externalAccess
    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .connection: LocalizedStringResource("Connection and Chat", bundle: .module)
        case .capabilities: LocalizedStringResource("Skills and Tools", bundle: .module)
        case .externalAccess: LocalizedStringResource("External Access", bundle: .module)
        }
    }

    static func matchingSearch(_ searchQuery: String) -> Self? {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !query.isEmpty else { return nil }
        if ["external", "bridge", "host", "claude", "外部", "桥接", "宿主"].contains(where: query.contains) {
            return .externalAccess
        }
        if ["skill", "tool", "protocol", "authentication", "技能", "工具", "协议", "授权"].contains(
            where: query.contains)
        {
            return .capabilities
        }
        if [
            "connection", "chat", "login", "sign", "codex", "path", "return", "queue", "steer", "连接",
            "聊天", "登录", "路径", "回车", "排队",
        ].contains(where: query.contains) {
            return .connection
        }
        return nil
    }
}

struct AgentIntegrationSettingsView: View {
    let searchQuery: String
    private let coreProtocolURL = try? ScholiumAgentIntegrationResources.coreProtocolSkillDirectoryURL()
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @Environment(\.agentChatSettingsController) private var chatController
    @Environment(\.scholiumSettingsSearchTarget) private var searchTarget
    @Environment(\.scholiumSettingsSearchRevision) private var searchRevision
    @AppStorage("scholium.settings.agentCategory") private var persistedCategory =
        AgentSettingsCategory.connection.rawValue
    @AppStorage("scholium.settings.navigationRevision") private var navigationRevision = ""
    @State private var navigation = SettingsSearchNavigation<AgentSettingsCategory>(
        category: .connection)
    @State private var hasRestoredCategory = false

    init(searchQuery: String = "") { self.searchQuery = searchQuery }

    var body: some View {
        VStack(spacing: 0) {
            Picker(selection: categoryBinding) {
                ForEach(AgentSettingsCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            } label: {
                Text("Agent settings", bundle: .module)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            ScholiumSettingsPaneHost(
                selection: navigation.category, identifier: "scholium.settings.agents.pages"
            ) { category in
                switch category {
                case .connection:
                    Form {
                        if let chatController {
                            AgentChatConnectionSettingsView(controller: chatController)
                        } else {
                            Section("Chat in Scholium") {
                                Text("Open a Triptych to manage its Chat connection.", bundle: .module)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Section {
                            AgentChatInputSettingsControls()
                        } header: {
                            Text("Chat Behavior", bundle: .module)
                        }
                        .id("agents.behavior")
                        if let chatController {
                            AgentChatConnectionAdvancedSettingsView(controller: chatController)
                        }
                    }
                    .scholiumSettingsFormStyle()
                    .scholiumSettingsSearchDestination()
                case .capabilities:
                    Form {
                        if let chatController {
                            AgentChatCapabilitiesSettingsView(
                                controller: chatController, capabilities: chatController.capabilities, coreProtocolURL: coreProtocolURL)
                        } else {
                            CoreProtocolSettingsSection(coreProtocolURL: coreProtocolURL)
                            Section("Skills and Tools") {
                                Text("Open a Triptych to manage its Skills and Tools.", bundle: .module)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .scholiumSettingsFormStyle()
                    .scholiumSettingsSearchDestination()
                case .externalAccess:
                    Form { ExternalAgentHostsSettingsView(settingsModel: settingsModel) }
                        .scholiumSettingsFormStyle()
                        .scholiumSettingsSearchDestination()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.agents")
        .onAppear { updateSearchNavigation() }
        .onChange(of: navigationRevision) { _, _ in
            navigation = SettingsSearchNavigation(
                category: AgentSettingsCategory(rawValue: persistedCategory) ?? .connection)
        }
        .onChange(of: searchQuery) { _, _ in updateSearchNavigation() }
        .onChange(of: searchTarget) { _, _ in updateSearchNavigation() }
        .onChange(of: searchRevision) { _, _ in updateSearchNavigation() }
    }

    private var categoryBinding: Binding<AgentSettingsCategory> {
        Binding(
            get: { navigation.category },
            set: { category in
                navigation.category = category
                if !navigation.isSearching { persistedCategory = category.rawValue }
            })
    }

    private func updateSearchNavigation() {
        if !hasRestoredCategory {
            navigation.category = AgentSettingsCategory(rawValue: persistedCategory) ?? .connection
            hasRestoredCategory = true
        }
        let matching: AgentSettingsCategory?
        switch searchTarget {
        case "agents.protocol", "agents.skills", "agents.tools": matching = .capabilities
        case "agents.external": matching = .externalAccess
        case "agents.connection", "agents.behavior", "agents.paths": matching = .connection
        default: matching = AgentSettingsCategory.matchingSearch(searchQuery)
        }
        navigation.updateSearch(query: searchQuery, matching: matching)
    }
}

private struct ExternalAgentHostsSettingsView: View {
    @ObservedObject var settingsModel: WorkspaceSettingsModel
    @State private var copyStatus: String?

    private let helperURL = ScholiumAgentIntegrationResources.chatHelperURL()

    var body: some View {
        Group {
            Section("Status") {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    statusRow("Scholium App", detail: String(localized: "Available"), available: true)
                    switch settingsModel.agentBridgeAvailability {
                    case .available:
                        statusRow("App Bridge", detail: String(localized: "Available"), available: true)
                    case .unavailable(let reason):
                        statusRow("App Bridge", detail: reason, available: false)
                    }
                    statusRow(
                        "Connection Helper",
                        detail: helperURL == nil
                            ? String(localized: "Unavailable") : String(localized: "Available"),
                        available: helperURL != nil
                    )
                }
            }

            .id("agents.external")
            Section("Setup") {
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
                    .disabled(helperURL == nil)

                    if let copyStatus { Text(copyStatus).font(.caption).textSelection(.enabled) }

                    if helperURL == nil {
                        Text("The bundled connection helper is unavailable. Reinstall Scholium to restore it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Core Protocol") {
                Button {
                    SettingsNavigationRequest.select(.agents, agentCategory: .capabilities)
                } label: {
                    Text("Open Skills and Tools", bundle: .module)
                }
            }

        }
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
            Text(verbatim: detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func copySetupCommand(for host: AgentIntegrationHost) {
        guard let helperURL else { return }
        let command = host.command(helperURL: helperURL)
        let copied = ScholiumPasteboardWriter.general.writeText(command)
        copyStatus =
            copied
            ? String(
                format: ScholiumL10n.string("%@ setup command copied", locale: Locale.current),
                locale: Locale.current,
                host.title
            )
            : String(
                format: ScholiumL10n.string(
                    "%@ setup command could not be copied.", locale: Locale.current),
                locale: Locale.current,
                host.title
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

    func command(helperURL: URL) -> String {
        let executable = Self.shellQuoted(helperURL.path)
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
