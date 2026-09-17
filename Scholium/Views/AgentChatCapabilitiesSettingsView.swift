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

    private var userSkills: [AgentChatMethod] {
        capabilities.methods.filter { !$0.isProtected }
    }

    var body: some View {
        Group {
            statusSection
            if !zoteroOnly {
                CoreProtocolSettingsSection(coreProtocolURL: coreProtocolURL)
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
                        ForEach(userSkills) { method in
                            methodRow(method)
                        }
                    }
                }
                .id("agents.skills")
            }
            Section {

                VStack(alignment: .leading, spacing: 10) {
                    if zoteroOnly {
                        zoteroConnection
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
                        ForEach(
                            Array(Set(capabilities.tools.map(\.name) + capabilities.toolConnections.map(\.name)))
                                .filter {
                                    $0 != AgentChatCapabilitiesController.zoteroServerName
                                }.sorted(), id: \.self
                        ) { name in
                            toolRow(name)
                        }
                    }
                }
            } header: {
                Text(zoteroOnly ? "Zotero in Chat" : "Connected Tools", bundle: .module)
            }
            .id(zoteroOnly ? "zotero.chat" : "agents.tools")
            if let toolEdit {
                Section {
                    AgentChatToolEditor(capabilities: capabilities, edit: toolEdit, isZoteroTool: zoteroOnly) {
                        focusedToolAction = toolEdit.originalName ?? (zoteroOnly ? "zotero" : "add")
                        self.toolEdit = nil
                    }
                    .id(toolEdit.id)
                }
            }
        }
    }

    private func ownsTool(_ name: String?) -> Bool {
        guard let name else { return true }  // A shared configuration failure affects both pages.
        return (name == AgentChatCapabilitiesController.zoteroServerName) == zoteroOnly
    }

    private var statusSection: some View {
        Section {
            HStack {
                Text(zoteroOnly ? "Chat Tool Configuration" : "Skills and Tools", bundle: .module).font(
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
                Text(
                    "Connect Codex in Connection and Chat to configure Skills and Tools.", bundle: .module
                )
                .foregroundStyle(.secondary)
            } else if controller.hasActiveExecutions {
                Text("Wait for the Agent to finish before changing Skills or Tools.", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            if capabilities.configurationHome != nil {
                Text(capabilities.isShared ? "Shared Codex Settings" : "Scholium Codex Settings")
                    .font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: methodEnabledBinding(method)) {
                Text(method.selection.title)
            }
            .disabled(
                method.isProtected || controller.hasActiveExecutions || capabilities.isRefreshing
                    || capabilities.isChanging)

            Text(method.description).textSelection(.enabled)
            if !method.dependencies.isEmpty {
                Text("Declared Tools: \(method.dependencies.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
                if let server = capabilities.tools.first(where: {
                    $0.name == AgentChatCapabilitiesController.zoteroServerName
                }) {
                    Text(AgentChatToolLabels.state(server)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(
                        capabilities.usesDefaultZoteroConnection
                            ? "Included in Chat · Read Only" : "Connection Status Unavailable", bundle: .module
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                SettingsNavigationRequest.select(.zotero)
            } label: {
                Text("Open Zotero Settings", bundle: .module)
            }
        }
    }

    private var zoteroConnection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if capabilities.zoteroConnection != nil {
                toolRow(AgentChatCapabilitiesController.zoteroServerName)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Zotero")
                        Text(
                            capabilities.usesDefaultZoteroConnection
                                ? "Included in Chat · Read Only" : "Unavailable"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Configure…") {
                        toolEdit = capabilities.zoteroToolEdit(executable: controller.zoteroToolExecutable)
                    }
                    .focused($focusedToolAction, equals: "zotero")
                    .disabled(
                        !capabilities.canConfigureTools || controller.zoteroToolExecutable == nil
                            || toolEdit != nil)
                }
            }
            if let connection = capabilities.zoteroConnection,
                connection.kind != .local || connection.address != controller.zoteroToolExecutable?.path
                    || connection.arguments != ZoteroMCPTransportDescriptor.supportedLocal.readOnlyArguments
            {
                Text("Custom Zotero Configuration").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(
                    "The Zotero preset provides read-only tools. Saved configuration and local library availability are separate."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func toolRow(_ name: String) -> some View {
        let server = capabilities.tools.first { $0.name == name }
        let configuration = capabilities.toolConnections.first { $0.name == name }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        name == AgentChatCapabilitiesController.zoteroServerName
                            ? String(localized: "Zotero") : (server?.title ?? name)
                    ).lineLimit(1)
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
            ForEach(server?.tools ?? [], id: \.self) { Text($0).textSelection(.enabled) }
        }
        .padding(.vertical, 4)
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
        }.id("agents.protocol")
    }
}

struct AgentZoteroToolSettingsView: View {
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
