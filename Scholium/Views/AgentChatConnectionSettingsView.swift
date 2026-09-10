import SwiftUI

private struct AgentChatSettingsControllerKey: EnvironmentKey {
  static let defaultValue: AgentChatController? = nil
}

extension EnvironmentValues {
  var agentChatSettingsController: AgentChatController? {
    get { self[AgentChatSettingsControllerKey.self] }
    set { self[AgentChatSettingsControllerKey.self] = newValue }
  }
}

struct AgentChatConnectionSettingsView: View {
  @ObservedObject var controller: AgentChatController
  var onShowExternalAgentHosts: (() -> Void)? = nil
  @State private var showsAdvancedConnectionSettings = false
  @State private var showsSkillsAndTools = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      settingsEditorSection("Chat in Scholium") {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .center, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(connectionStatus)
              .foregroundStyle(.secondary)
            connectionActions
          }
          if let error = controller.error { Text(error).font(.callout).foregroundStyle(.secondary) }
          Text(
            "Scholium finds Codex and prepares the connection automatically. Connection settings and saved chat history are managed on this Mac."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      settingsEditorSection("Advanced") {
        VStack(alignment: .leading, spacing: 8) {
          Button("Advanced Connection Settings…") {
            showsAdvancedConnectionSettings = true
          }
          Button("Skills and Tools…") {
            showsSkillsAndTools = true
          }
          if let onShowExternalAgentHosts {
            Button("External Agent Hosts…", action: onShowExternalAgentHosts)
          }
        }
      }
    }
    .sheet(isPresented: $showsAdvancedConnectionSettings) {
      AgentChatConnectionAdvancedSettingsView(controller: controller)
    }
    .sheet(isPresented: $showsSkillsAndTools) {
      AgentChatCapabilitiesSettingsSheet(
        controller: controller,
        capabilities: controller.capabilities
      )
    }
  }

  private var connectionStatus: String {
    switch controller.state {
    case .disconnected:
      String(localized: "Not Connected")
    case .connecting:
      String(localized: "Connecting…")
    default:
      controller.account == nil
        ? String(localized: "Sign-in Required")
        : String(localized: "Connected")
    }
  }

  @ViewBuilder
  private var connectionActions: some View {
    if controller.state == .disconnected {
      Button("Connect Codex") { controller.connectConfigured() }
        .disabled(!controller.isLoaded)
    } else {
      if controller.account == nil {
        Button("Sign in with ChatGPT") { controller.login() }
          .disabled(controller.isBusy)
      }
      Button("Disconnect") { Task { await controller.disconnectByUser() } }
    }
  }
}

private struct AgentChatConnectionAdvancedSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
  @ObservedObject var controller: AgentChatController
  @AppStorage("agent.codex.executable") private var executable = ""
  @AppStorage("agent.codex.home") private var home = ""
  @AppStorage("agent.scholium.helper") private var cli = ""
  @State private var fileSelectionTask: Task<Void, Never>?
  @State private var fileSelectionError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
      settingsTitle(
        "Advanced Connection Settings",
        detail: "Override automatic locations only when using a custom Codex installation."
      )

      VStack(alignment: .leading, spacing: 12) {
        pathRow("Codex Application", value: $executable, directory: false)
        pathRow("Scholium Connection Helper", value: $cli, directory: false)
        pathRow("Existing Codex Settings Folder", value: $home, directory: true)
        Text(
          "An existing Codex folder also uses its login, tools and settings. By default, Scholium keeps a separate login."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        if let fileSelectionError {
          Text(fileSelectionError)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Button("Use Automatic Setup") {
          executable = ""
          cli = ""
          home = ""
        }
        .disabled(controller.state != .disconnected)
      }

      if let version = controller.runtimeVersion {
        settingsEditorSection("Runtime") {
          Text(version)
            .font(.caption)
            .textSelection(.enabled)
        }
      }

      HStack {
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 680, height: 380, alignment: .topLeading)
    .onDisappear { fileSelectionTask?.cancel() }
  }

  private func pathRow(_ title: LocalizedStringKey, value: Binding<String>, directory: Bool)
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption)
      HStack {
        TextField("", text: value)
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel(Text(title))
        Button("Choose…") {
          fileSelectionError = nil
          let request = ScholiumFileSelectionRequest(
            kind: directory
              ? .directory(canCreateDirectories: true)
              : .files(allowedContentTypes: [])
          )
          fileSelectionTask = Task { @MainActor in
            defer { fileSelectionTask = nil }
            do {
              guard
                let url =
                  try await fileSelectionPresenter
                  .requiredForFileSelection().selectURL(request)
              else { return }
              try Task.checkCancellation()
              value.wrappedValue = url.path
            } catch is CancellationError {
              return
            } catch {
              fileSelectionError = error.localizedDescription
            }
          }
        }
      }
    }.disabled(controller.state != .disconnected || fileSelectionTask != nil)
  }

}

private struct AgentChatCapabilitiesSettingsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var controller: AgentChatController
  @ObservedObject var capabilities: AgentChatCapabilitiesController

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ScrollView {
        AgentChatCapabilitiesSettingsView(
          controller: controller,
          capabilities: capabilities
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }

      HStack {
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 760, height: 360)
    .task(id: controller.selected?.threadID) {
      capabilities.refresh(threadID: controller.selected?.threadID)
    }
  }
}
