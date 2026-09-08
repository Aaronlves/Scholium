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
  @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
  @AppStorage("agent.codex.executable") private var executable = ""
  @AppStorage("agent.codex.home") private var home = ""
  @AppStorage("agent.scholium.cli") private var cli = ""
  @State private var fileSelectionTask: Task<Void, Never>?
  @State private var fileSelectionError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Chat in Scholium").font(.headline)
      Text(
        controller.state == .disconnected
          ? String(localized: "Not Connected")
          : controller.state == .connecting
            ? String(localized: "Connecting…")
            : controller.account == nil
              ? String(localized: "Sign-in Required") : String(localized: "Connected")
      )
      .foregroundStyle(.secondary)
      HStack {
        if controller.state == .disconnected {
          Button("Connect Codex") { controller.connectConfigured() }.disabled(!controller.isLoaded)
        } else {
          if controller.account == nil {
            Button("Sign in with ChatGPT") { controller.login() }.disabled(controller.isBusy)
          }
          Button("Disconnect") { Task { await controller.disconnectByUser() } }
        }
      }
      if let error = controller.error { Text(error).font(.callout).foregroundStyle(.secondary) }
      Text(
        "Scholium finds Codex and prepares the connection automatically. Connection settings and saved chat history are managed on this Mac."
      )
      .font(.callout).foregroundStyle(.secondary)
      DisclosureGroup("Advanced Connection Settings") {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            "Only change these locations if you use a custom installation. Leave them empty for automatic setup."
          )
          .font(.caption).foregroundStyle(.secondary)
          pathRow("Codex Application", value: $executable, directory: false)
          pathRow("Scholium Connection Helper", value: $cli, directory: false)
          pathRow("Existing Codex Settings Folder", value: $home, directory: true)
          Text(
            "An existing Codex folder also uses its login, tools and settings. By default, Scholium keeps a separate login."
          )
          .font(.caption).foregroundStyle(.secondary)
          if let fileSelectionError {
            Text(fileSelectionError).font(.caption).foregroundStyle(.secondary)
          }
          Button("Use Automatic Setup") {
            executable = ""
            cli = ""
            home = ""
          }
          .disabled(controller.state != .disconnected)
          if let version = controller.runtimeVersion {
            Text(version).font(.caption).textSelection(.enabled)
          }
        }.padding(.top, 8)
      }
      Divider()
      AgentChatCapabilitiesSettingsView(controller: controller, capabilities: controller.capabilities)
    }
    .task(id: controller.selected?.threadID) {
      controller.capabilities.refresh(threadID: controller.selected?.threadID)
    }
    .onDisappear { fileSelectionTask?.cancel() }
  }

  private func pathRow(_ title: LocalizedStringKey, value: Binding<String>, directory: Bool)
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption)
      HStack {
        TextField(title, text: value).textFieldStyle(.roundedBorder)
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
