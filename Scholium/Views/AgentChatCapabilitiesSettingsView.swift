import AppKit
import ScholiumContracts
import SwiftUI

struct AgentChatCapabilitiesSettingsView: View {
    @ObservedObject var controller: AgentChatController
    @ObservedObject var capabilities: AgentChatCapabilitiesController
    var zoteroOnly = false
    var coreProtocolURL: URL? = nil
    @FocusState private var focusedToolAction: String?

    @Environment(\.openURL) private var openURL

    @State private var pendingMethod: AgentChatMethod?
    @State private var pendingEnabled = false
    @State private var pendingAuthentication: AgentChatConnectedTool?
    @State private var pendingConfiguration: URL?
    @State private var confirmationError: String?
    @State private var confirmsSharedChange = false
    @State private var toolEdit: AgentChatToolEdit?
    @State private var capabilityFilter = ""

    private var userSkills: [AgentChatMethod] {
        capabilities.methods.filter { !$0.isProtected }
    }

    private var filteredUserSkills: [AgentChatMethod] {
        userSkills.filter { method in
            matchesCapabilityFilter(
                method.selection.title,
                method.selection.name,
                method.description,
                method.dependencies.joined(separator: " ")
            )
        }
    }

    private var toolNames: [String] {
        Array(Set(capabilities.tools.map(\.name) + capabilities.toolConnections.map(\.name))).sorted()
    }

    private var filteredToolNames: [String] {
        toolNames.filter { name in
            let server = capabilities.tools.first { $0.name == name }
            let configuration = capabilities.toolConnections.first { $0.name == name }
            return matchesCapabilityFilter(
                name,
                server?.title,
                server?.tools.joined(separator: " "),
                configuration?.kind.rawValue
            )
        }
    }

    private var hasCapabilityFilter: Bool {
        !capabilityFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasSkillSectionContent: Bool {
        capabilities.isConnected || capabilities.workspaceURL != nil || capabilities.workspaceError != nil
            || capabilities.methodError != nil || !capabilities.methodErrors.isEmpty
            || capabilities.hasMethods || !userSkills.isEmpty
    }

    private var hasToolSectionContent: Bool {
        zoteroOnly || capabilities.isConnected || !toolNames.isEmpty
            || capabilities.toolConfigurationError != nil || capabilities.toolConfigurationNotice != nil
            || capabilities.authenticationError != nil || capabilities.authenticationNotice != nil
            || capabilities.authenticatingTool != nil || capabilities.toolError != nil
    }

    var body: some View {
        Group {
            statusSection
            if !zoteroOnly {
                if capabilities.isConnected {
                    capabilityFilterSection
                }
                CoreProtocolSettingsSection(coreProtocolURL: coreProtocolURL)
                if hasSkillSectionContent {
                    Section("Skills") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let workspace = capabilities.workspaceURL {
                                Text("This Triptych").font(.caption).foregroundStyle(.secondary)
                                Text(
                                    "Chat uses AGENTS.md and the skills folder in this Triptych’s .scholium workspace."
                                )
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                Button("Open Chat Workspace in Finder") { NSWorkspace.shared.open(workspace) }
                            }
                            if let error = capabilities.workspaceError {
                                Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if let error = capabilities.methodError {
                                Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            ForEach(capabilities.methodErrors, id: \.self) {
                                Text($0).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if capabilities.hasMethods && userSkills.isEmpty {
                                Text("No Skills Found").foregroundStyle(.secondary)
                            }
                            if !filteredUserSkills.isEmpty {
                                ForEach(Array(filteredUserSkills.enumerated()), id: \.element.id) { index, method in
                                    if index > 0 {
                                        Divider().padding(.leading, 8)
                                    }
                                    methodRow(method)
                                }
                            } else if hasCapabilityFilter && !userSkills.isEmpty {
                                Text("No Skills Match Filter")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .id(SettingsSection.agentSkills)
                }
            }
            if hasToolSectionContent {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if zoteroOnly {
                            zoteroCapability
                        } else {
                            zoteroSummary
                            Button("Add Tool…") { toolEdit = capabilities.editTool() }
                                .focused($focusedToolAction, equals: "add")
                                .disabled(!capabilities.canConfigureTools || toolEdit != nil)
                        }
                        if let error = capabilities.toolConfigurationError,
                            ownsTool(capabilities.toolConfigurationErrorTool),
                            capabilities.toolConfigurationErrorTool == nil || toolEdit == nil
                        {
                            Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if let notice = capabilities.toolConfigurationNotice,
                            ownsTool(capabilities.toolConfigurationNoticeTool)
                        {
                            Text(notice).foregroundStyle(.secondary)
                        }
                        if let error = capabilities.authenticationError,
                            ownsTool(capabilities.authenticationFeedbackTool)
                        {
                            Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if let notice = capabilities.authenticationNotice,
                            ownsTool(capabilities.authenticationFeedbackTool)
                        {
                            Text(notice).foregroundStyle(.secondary)
                        }
                        if let name = capabilities.authenticatingTool, ownsTool(name) {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                            if let url = capabilities.authorizationURL {
                                Link("Continue Sign-In", destination: url)
                            } else {
                                ProgressView("Preparing Sign-In…").controlSize(.small)
                            }
                        }
                        if let error = capabilities.toolError {
                            Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if !zoteroOnly && capabilities.hasTools && capabilities.tools.isEmpty
                            && capabilities.toolConnections.isEmpty
                        {
                            Text("No Connected Tools").foregroundStyle(.secondary)
                        }
                        if !zoteroOnly {
                            if !filteredToolNames.isEmpty {
                                ForEach(filteredToolNames, id: \.self) { name in
                                    toolRow(name)
                                }
                            } else if hasCapabilityFilter && !toolNames.isEmpty {
                                Text("No Connected Tools Match Filter")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(zoteroOnly ? "Zotero in Chat" : "Connected Tools", bundle: .module)
                }
                .id(zoteroOnly ? SettingsSection.zoteroChat : .agentTools)
            }
            if let toolEdit {
                Section {
                    AgentChatToolEditor(capabilities: capabilities, edit: toolEdit) {
                        focusedToolAction = toolEdit.originalName ?? (zoteroOnly ? "zotero" : "add")
                        self.toolEdit = nil
                    }
                    .id(toolEdit.id)
                }
            }
        }
    }

    private var capabilityFilterSection: some View {
        Section {
            TextField("Filter Skills and Tools", text: $capabilityFilter)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter Skills and Tools")
                .accessibilityIdentifier("scholium.settings.capabilityFilter")
        } footer: {
            Text("Filters the currently loaded runtime inventory; it does not change configuration.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .id("agents.capabilityFilter")
    }

    private func matchesCapabilityFilter(_ values: String?...) -> Bool {
        let query = capabilityFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return values.compactMap { $0 }.contains {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    private func ownsTool(_ name: String?) -> Bool {
        guard name != nil else { return true }  // A shared configuration failure affects both pages.
        return !zoteroOnly
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text(zoteroOnly ? "Chat Connection" : "Runtime Status", bundle: .module).font(
                    .headline)
                Spacer()
                if capabilities.isRefreshing || capabilities.isChanging {
                    ProgressView().controlSize(.small).accessibilityLabel("Skills and Tools")
                }
                Button("Refresh") {
                    capabilities.refresh(threadID: controller.selected?.threadID, reloadWorkspace: true)
                }
                .disabled(
                    !capabilities.isConnected || capabilities.isRefreshing || capabilities.isChanging)
            }
            if let confirmationError { Text(confirmationError).foregroundStyle(.secondary) }
            if !capabilities.isConnected {
                if zoteroOnly {
                    Text("Connect Codex in Agents & Chat to use Zotero in Chat.", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connect Codex in Connection and Chat to configure Skills and Tools.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
                Button("Open Connection and Chat") {
                    SettingsNavigationRequest.reveal(.agentConnection)
                }
            } else if controller.hasActiveExecutions {
                Text("Wait for the Agent to finish before changing Skills or Tools.", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            if !zoteroOnly, capabilities.configurationHome != nil {
                LabeledContent("Configuration") {
                    Text(capabilities.isShared ? "Shared Codex Settings" : "Scholium Codex Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !zoteroOnly, let version = controller.runtimeVersion {
                LabeledContent("Runtime") {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .task(id: controller.selected?.threadID) {
            capabilities.refresh(threadID: controller.selected?.threadID)
        }
        .confirmationDialog(
            pendingAuthentication == nil
                ? String(localized: "Change Shared Codex Settings?", bundle: .module)
                : String(localized: "Sign In Using Shared Settings?", bundle: .module),
            isPresented: $confirmsSharedChange
        ) {
            Button(
                pendingAuthentication == nil
                    ? String(localized: "Apply Change", bundle: .module)
                    : String(localized: "Sign In", bundle: .module)
            ) {
                defer {
                    pendingMethod = nil
                    pendingAuthentication = nil
                    pendingConfiguration = nil
                }
                guard capabilities.configurationHome == pendingConfiguration else {
                    confirmationError = String(localized: "The connection changed. Review the setting again.")
                    return
                }
                if let pendingAuthentication {
                    beginSignIn(pendingAuthentication)
                } else if let pendingMethod {
                    capabilities.setEnabled(
                        pendingMethod, enabled: pendingEnabled, threadID: controller.selected?.threadID)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingMethod = nil
                pendingAuthentication = nil
                pendingConfiguration = nil
            }
        } message: {
            if pendingAuthentication != nil {
                Text("Codex manages sign-in credentials for this shared settings folder.")
            } else {
                Text("This setting also applies to other clients using this Codex settings folder.")
            }
        }
    }

    private func methodRow(_ method: AgentChatMethod) -> some View {
        HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Toggle(isOn: methodEnabledBinding(method)) {
                Text(method.selection.title)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 170, alignment: .leading)
            .disabled(
                method.isProtected || controller.hasActiveExecutions || capabilities.isRefreshing
                    || capabilities.isChanging)

            VStack(alignment: .leading, spacing: 4) {
                Text(method.description)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !method.dependencies.isEmpty {
                    Text("Declared Tools: \(method.dependencies.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, ScholiumMetrics.Settings.rowVerticalInset)
        .accessibilityElement(children: .contain)
    }

    private func methodEnabledBinding(_ method: AgentChatMethod) -> Binding<Bool> {
        Binding(
            get: { method.enabled },
            set: { enabled in
                if capabilities.isShared {
                    pendingMethod = method
                    pendingEnabled = enabled
                    pendingAuthentication = nil
                    pendingConfiguration = capabilities.configurationHome
                    confirmationError = nil
                    confirmsSharedChange = true
                } else {
                    capabilities.setEnabled(method, enabled: enabled, threadID: controller.selected?.threadID)
                }
            }
        )
    }

    private var zoteroSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Zotero", bundle: .module)
                Text(zoteroStatusText, bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                SettingsNavigationRequest.select(.zotero)
            } label: {
                Text("Open Zotero Settings", bundle: .module)
            }
        }
    }

    private var zoteroCapability: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(zoteroStatusText, bundle: .module)
                .foregroundStyle(.secondary)
            Text(
                "Chat uses Scholium's bundled Zotero connection for library reads, indexed attachment text and confirmed item changes. Import BibTeX and RIS in Zotero. No separate runtime installation is required.",
                bundle: .module
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var zoteroStatusText: LocalizedStringKey {
        switch capabilities.zoteroConnectionState {
        case .disconnected: "Unavailable"
        case .checking: "Checking…"
        case .available: "Available in Chat"
        case .unavailable: "Zotero connection unavailable"
        }
    }

    private func toolRow(_ name: String) -> some View {
        let server = capabilities.tools.first { $0.name == name }
        let configuration = capabilities.toolConnections.first { $0.name == name }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(server?.title ?? name).lineLimit(1)
                    if let server {
                        Text(AgentChatToolLabels.state(server)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(configuration?.enabled == false ? "Disabled" : "Connection Status Unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if configuration?.isEditable == true {
                    Button("Edit…") { toolEdit = capabilities.editTool(named: name) }
                        .focused($focusedToolAction, equals: name)
                        .disabled(!capabilities.canConfigureTools || toolEdit != nil)
                }
                if let server,
                    server.authStatus == "notLoggedIn" || server.connectionStatus == "authenticationRequired"
                {
                    Button("Sign In") { requestSignIn(server) }.disabled(!capabilities.canSignIn(server))
                }
            }
            if let configuration {
                if !configuration.isEditable {
                    Text("Managed Configuration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let server, !server.tools.isEmpty {
                Text(server.tools.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, ScholiumMetrics.Settings.rowVerticalInset)
        .accessibilityElement(children: .contain)
    }

    private func requestSignIn(_ server: AgentChatConnectedTool) {
        confirmationError = nil
        if capabilities.isShared {
            pendingAuthentication = server
            pendingMethod = nil
            pendingConfiguration = capabilities.configurationHome
            confirmsSharedChange = true
        } else {
            beginSignIn(server)
        }
    }

    private func beginSignIn(_ server: AgentChatConnectedTool) {
        capabilities.signIn(server, threadID: controller.selected?.threadID) { url in openURL(url) }
    }

}

struct CoreProtocolSettingsSection: View {
    let coreProtocolURL: URL?

    var body: some View {
        Section("Core Protocol") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Always included in Scholium Chat", systemImage: "checkmark.shield")
                    Spacer(minLength: 8)
                    Text("Protected Skill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Applied automatically to every Scholium Chat turn.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let coreProtocolURL {
                    Button("Show Core Protocol in Finder…") {
                        NSWorkspace.shared.activateFileViewerSelecting([coreProtocolURL])
                    }
                } else {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scholium.agent.core-protocol")
        }.id(SettingsSection.agentCoreProtocol)
    }
}

struct AgentZoteroCapabilitySettingsView: View {
    @ObservedObject var controller: AgentChatController
    @ObservedObject var capabilities: AgentChatCapabilitiesController

    var body: some View {
        AgentChatCapabilitiesSettingsView(
            controller: controller, capabilities: capabilities, zoteroOnly: true)
    }
}

enum AgentChatToolLabels {
    static func state(_ server: AgentChatConnectedTool) -> String {
        switch server.connectionStatus {
        case "connected": return String(localized: "Connected", bundle: .module)
        case "starting": return String(localized: "Connecting…", bundle: .module)
        case "notStarted": return String(localized: "Not Started", bundle: .module)
        case "authenticationRequired": return String(localized: "Sign-in Required", bundle: .module)
        case "failed": return String(localized: "Connection Failed", bundle: .module)
        case "cancelled": return String(localized: "Cancelled", bundle: .module)
        case "disabled": return String(localized: "Disabled", bundle: .module)
        default:
            return server.authStatus == "notLoggedIn"
                ? String(localized: "Sign-in Required", bundle: .module)
                : String(localized: "Connection Status Unavailable", bundle: .module)
        }
    }
}
