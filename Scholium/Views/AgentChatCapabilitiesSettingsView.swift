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
  @State private var showsMethods = true
  @State private var showsTools = true
  @State private var toolEdit: AgentChatToolEdit?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Methods and Tools").font(.headline)
        Spacer()
        if capabilities.isRefreshing || capabilities.isChanging {
          ProgressView().controlSize(.small).accessibilityLabel("Methods and Tools")
        }
        Button("Refresh") { capabilities.refresh(threadID: controller.selected?.threadID, applyAssociations: true) }
          .disabled(!capabilities.isConnected || capabilities.isRefreshing || capabilities.isChanging)
      }
      if let confirmationError { Text(confirmationError).foregroundStyle(.secondary) }
      if let home = capabilities.configurationHome {
        Text(capabilities.isShared ? "Shared Codex Settings" : "Scholium Codex Settings")
          .font(.caption).foregroundStyle(.secondary)
        if capabilities.isShared {
          Text(home.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            .lineLimit(2).truncationMode(.middle).help(home.path)
        }
      }
      DisclosureGroup("Methods", isExpanded: $showsMethods) {
        VStack(alignment: .leading, spacing: 10) {
          Button("Add Methods Folder…", action: chooseFolder)
            .disabled(!capabilities.canChangeAssociations || folderSelectionTask != nil)
          if let error = folderSelectionError ?? capabilities.associationError {
            Text(error).foregroundStyle(.secondary).textSelection(.enabled)
          }
          if !capabilities.associatedFolders.isEmpty {
            DisclosureGroup("Associated Folders") {
              VStack(alignment: .leading, spacing: 8) {
                ForEach(capabilities.associatedFolders, id: \.self) { path in
                  HStack {
                    Text(path).font(.caption).lineLimit(2).truncationMode(.middle)
                      .help(path).textSelection(.enabled)
                    Spacer(minLength: 4)
                    Button {
                      capabilities.removeAssociation(path, threadID: controller.selected?.threadID)
                    } label: { Image(systemName: "minus.circle") }
                      .help("Remove Association").accessibilityLabel("Remove Association: \(path)")
                      .disabled(!capabilities.canChangeAssociations)
                  }
                }
              }.padding(.top, 6)
            }
          }
          if let error = capabilities.methodError { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
          ForEach(capabilities.methodErrors, id: \.self) { Text($0).foregroundStyle(.secondary).textSelection(.enabled) }
          if capabilities.hasMethods && capabilities.methods.isEmpty { Text("No Methods Found").foregroundStyle(.secondary) }
          ForEach(capabilities.methods) { method in
            DisclosureGroup {
              VStack(alignment: .leading, spacing: 6) {
                Text(method.description).textSelection(.enabled)
                Text(method.selection.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if !method.dependencies.isEmpty {
                  Text("Declared Tools: \(method.dependencies.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.secondary)
                }
              }.padding(.vertical, 4)
            } label: {
              Toggle(isOn: Binding(get: { method.enabled }, set: { enabled in
                if capabilities.isShared {
                  pendingMethod = method; pendingEnabled = enabled; pendingAuthentication = nil
                  pendingConfiguration = capabilities.configurationHome
                  confirmationError = nil; confirmsSharedChange = true
                } else {
                  capabilities.setEnabled(method, enabled: enabled, threadID: controller.selected?.threadID)
                }
              })) { Text(method.selection.title) }
              .disabled(method.isProtected || controller.hasActiveExecutions || capabilities.isRefreshing || capabilities.isChanging)
            }
          }
        }.padding(.top, 6)
      }
      DisclosureGroup("Connected Tools", isExpanded: $showsTools) {
        VStack(alignment: .leading, spacing: 10) {
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
          ForEach(Array(Set(capabilities.tools.map(\.name) + capabilities.toolConnections.map(\.name))).sorted(), id: \.self) { name in
            toolRow(name)
          }
        }.padding(.top, 6)
      }
    }
    .onDisappear { folderSelectionTask?.cancel() }
    .sheet(item: $toolEdit) { edit in
      AgentChatToolEditor(capabilities: capabilities, edit: edit)
    }
    .confirmationDialog(pendingAuthentication == nil
      ? String(localized: "Change Shared Codex Settings?", bundle: .module)
      : String(localized: "Sign In Using Shared Settings?", bundle: .module), isPresented: $confirmsSharedChange) {
      Button(pendingAuthentication == nil ? String(localized: "Apply Change", bundle: .module)
        : String(localized: "Sign In", bundle: .module)) {
        defer { pendingMethod = nil; pendingAuthentication = nil; pendingConfiguration = nil }
        guard capabilities.configurationHome == pendingConfiguration else {
          confirmationError = String(localized: "The connection changed. Review the setting again.")
          return
        }
        if let pendingAuthentication { beginSignIn(pendingAuthentication) }
        else if let pendingMethod { capabilities.setEnabled(pendingMethod, enabled: pendingEnabled, threadID: controller.selected?.threadID) }
      }
      Button("Cancel", role: .cancel) { pendingMethod = nil; pendingAuthentication = nil; pendingConfiguration = nil }
    } message: {
      if pendingAuthentication != nil {
        Text("Codex manages sign-in credentials for this shared settings folder.")
      } else {
        Text("This setting also applies to other clients using this Codex settings folder.")
      }
    }
  }

  private func toolRow(_ name: String) -> some View {
    let server = capabilities.tools.first { $0.name == name }
    let configuration = capabilities.toolConnections.first { $0.name == name }
    return DisclosureGroup {
      VStack(alignment: .leading, spacing: 4) {
        Text(name).font(.caption).foregroundStyle(.secondary)
        if let configuration {
          Text(configuration.address).font(.caption).textSelection(.enabled)
          if !configuration.isEditable { Text("Managed Configuration").font(.caption).foregroundStyle(.secondary) }
        }
        ForEach(server?.tools ?? [], id: \.self) { Text($0).textSelection(.enabled) }
      }.padding(.top, 4)
    } label: {
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
          Button("Edit…") { toolEdit = capabilities.editTool(named: name) }.disabled(!capabilities.canConfigureTools)
        }
        if let server, server.authStatus == "notLoggedIn" || server.connectionStatus == "authenticationRequired" {
          Button("Sign In") { requestSignIn(server) }.disabled(!capabilities.canSignIn(server))
        }
      }
    }
  }

  private func requestSignIn(_ server: AgentChatConnectedTool) {
    confirmationError = nil
    if capabilities.isShared {
      pendingAuthentication = server; pendingMethod = nil
      pendingConfiguration = capabilities.configurationHome; confirmsSharedChange = true
    } else { beginSignIn(server) }
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
        guard let url = try await fileSelectionPresenter.requiredForFileSelection()
          .selectURL(.init(kind: .directory(canCreateDirectories: false))) else { return }
        try Task.checkCancellation()
        guard capabilities.configurationHome == home else {
          folderSelectionError = String(localized: "The connection changed. Choose the methods folder again.")
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
      return server.authStatus == "notLoggedIn" ? String(localized: "Sign-in Required", bundle: .module)
        : String(localized: "Connection Status Unavailable", bundle: .module)
    }
  }
}
