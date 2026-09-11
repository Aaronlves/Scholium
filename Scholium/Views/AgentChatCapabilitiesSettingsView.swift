import AppKit
import ScholiumContracts
import SwiftUI

struct AgentChatCapabilitiesSettingsView: View {
    @ObservedObject var controller: AgentChatController
    @ObservedObject var capabilities: AgentChatCapabilitiesController
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @Environment(\.openURL) private var openURL
    @State private var folderSelectionTask: Task<Void, Never>?
    @State private var folderSelectionError: String?
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Skills and Tools").font(.headline)
                Spacer()
                if capabilities.isRefreshing || capabilities.isChanging {
                    ProgressView().controlSize(.small).accessibilityLabel("Skills and Tools")
                }
                Button("Refresh") { capabilities.refresh(threadID: controller.selected?.threadID, applyAssociations: true) }
                    .disabled(!capabilities.isConnected || capabilities.isRefreshing || capabilities.isChanging)
            }
            if let confirmationError { Text(confirmationError).foregroundStyle(.secondary) }
            if capabilities.configurationHome != nil {
                Text(capabilities.isShared ? "Shared Codex Settings" : "Scholium Codex Settings")
                    .font(.caption).foregroundStyle(.secondary)
            }
            coreProtocolSection
            settingsEditorSection("Skills") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Add Skills Folder…", action: chooseFolder)
                        .disabled(!capabilities.canChangeAssociations || folderSelectionTask != nil)
                    if let error = folderSelectionError ?? capabilities.associationError {
                        Text(error).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if !capabilities.associatedFolders.isEmpty {
                        Text("Associated Folders")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(capabilities.associatedFolders, id: \.self) { path in
                                HStack {
                                    Label(skillFolderName(path), systemImage: "folder")
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Button {
                                        capabilities.removeAssociation(path, threadID: controller.selected?.threadID)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .help("Remove Association")
                                    .accessibilityLabel("Remove Association: \(skillFolderName(path))")
                                    .disabled(!capabilities.canChangeAssociations)
                                }
                            }
                        }
                    }
                    if let error = capabilities.methodError { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                    ForEach(capabilities.methodErrors, id: \.self) { Text($0).foregroundStyle(.secondary).textSelection(.enabled) }
                    if capabilities.hasMethods && userSkills.isEmpty { Text("No Skills Found").foregroundStyle(.secondary) }
                    ForEach(userSkills) { method in
                        methodRow(method)
                    }
                }
            }
            settingsEditorSection("Connected Tools") {
                VStack(alignment: .leading, spacing: 10) {
                    zoteroConnection
                    Button("Add Tool…") { toolEdit = capabilities.editTool() }.disabled(!capabilities.canConfigureTools)
                    if let error = capabilities.toolConfigurationError { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let notice = capabilities.toolConfigurationNotice { Text(notice).foregroundStyle(.secondary) }
                    if let error = capabilities.authenticationError { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                    if let notice = capabilities.authenticationNotice { Text(notice).foregroundStyle(.secondary) }
                    if let name = capabilities.authenticatingTool {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                        if let url = capabilities.authorizationURL {
                            Link("Continue Sign-In", destination: url)
                        } else {
                            ProgressView("Preparing Sign-In…").controlSize(.small)
                        }
                    }
                    if let error = capabilities.toolError { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                    if capabilities.hasTools && capabilities.tools.isEmpty && capabilities.toolConnections.isEmpty {
                        Text("No Connected Tools").foregroundStyle(.secondary)
                    }
                    ForEach(
                        Array(Set(capabilities.tools.map(\.name) + capabilities.toolConnections.map(\.name))).filter {
                            $0 != AgentChatCapabilitiesController.zoteroServerName
                        }.sorted(), id: \.self
                    ) { name in
                        toolRow(name)
                    }
                }
            }
        }
        .onDisappear { folderSelectionTask?.cancel() }
        .sheet(item: $toolEdit) { edit in
            AgentChatToolEditor(capabilities: capabilities, edit: edit)
        }
        .confirmationDialog(
            pendingAuthentication == nil
                ? String(localized: "Change Shared Codex Settings?", bundle: .module)
                : String(localized: "Sign In Using Shared Settings?", bundle: .module), isPresented: $confirmsSharedChange
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
                    capabilities.setEnabled(pendingMethod, enabled: pendingEnabled, threadID: controller.selected?.threadID)
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

    private var coreProtocolSection: some View {
        settingsEditorSection("Core Protocol") {
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
                if let coreProtocolURL = capabilities.coreProtocolURL {
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
        }
    }

    private func skillFolderName(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? String(localized: "Skills") : name
    }

    private func methodRow(_ method: AgentChatMethod) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: methodEnabledBinding(method)) {
                Text(method.selection.title)
            }
            .disabled(method.isProtected || controller.hasActiveExecutions || capabilities.isRefreshing || capabilities.isChanging)

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

    private var zoteroConnection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if capabilities.zoteroConnection != nil {
                toolRow(AgentChatCapabilitiesController.zoteroServerName)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Zotero")
                        Text(capabilities.usesDefaultZoteroConnection ? "Included in Chat · Read Only" : "Unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Configure…") { toolEdit = capabilities.zoteroToolEdit(executable: controller.zoteroToolExecutable) }
                        .disabled(!capabilities.canConfigureTools || controller.zoteroToolExecutable == nil)
                }
            }
            if let connection = capabilities.zoteroConnection,
                connection.kind != .local || connection.address != controller.zoteroToolExecutable?.path
                    || connection.arguments != ZoteroMCPTransportDescriptor.supportedLocal.readOnlyArguments
            {
                Text("Custom Zotero Configuration").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("The Zotero preset provides read-only tools. Saved configuration and local library availability are separate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Local Zotero API").font(.caption)
                if capabilities.isCheckingZotero {
                    ProgressView().controlSize(.small)
                } else if let info = capabilities.zoteroLibraryInfo {
                    Text(zoteroStatus(info.status)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not Checked").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check Connection") { capabilities.checkZotero() }.disabled(!capabilities.canCheckZotero)
            }
            if capabilities.zoteroLibraryInfo?.status == .apiDisabled {
                Text("In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’, then test again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func zoteroStatus(_ status: ZoteroAvailability) -> String {
        switch status {
        case .available, .itemMissing: String(localized: "Connected")
        case .apiDisabled: String(localized: "Access Disabled in Zotero")
        case .appUnavailable: String(localized: "Zotero Not Available")
        }
    }

    private func toolRow(_ name: String) -> some View {
        let server = capabilities.tools.first { $0.name == name }
        let configuration = capabilities.toolConnections.first { $0.name == name }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name == AgentChatCapabilitiesController.zoteroServerName ? String(localized: "Zotero") : (server?.title ?? name)).lineLimit(1)
                    if let server {
                        Text(AgentChatToolLabels.state(server)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(configuration?.enabled == false ? "Disabled" : "Connection Status Unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if configuration?.isEditable == true {
                    Button("Edit…") { toolEdit = capabilities.editTool(named: name) }.disabled(!capabilities.canConfigureTools)
                }
                if let server, server.authStatus == "notLoggedIn" || server.connectionStatus == "authenticationRequired" {
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

    private func chooseFolder() {
        guard folderSelectionTask == nil else { return }
        folderSelectionError = nil
        let home = capabilities.configurationHome
        folderSelectionTask = Task { @MainActor in
            defer { folderSelectionTask = nil }
            do {
                guard
                    let url = try await fileSelectionPresenter.requiredForFileSelection()
                        .selectURL(.init(kind: .directory(canCreateDirectories: false)))
                else { return }
                try Task.checkCancellation()
                guard capabilities.configurationHome == home else {
                    folderSelectionError = String(localized: "The connection changed. Choose the Skills folder again.")
                    return
                }
                capabilities.associate(url, threadID: controller.selected?.threadID)
            } catch is CancellationError {
                return
            } catch { folderSelectionError = error.localizedDescription }
        }
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
