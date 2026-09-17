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

    var body: some View {
        Group {
            Section {
                LabeledContent("Status") {
                    Text(connectionStatus)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    connectionActions
                }
                if let error = controller.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Chat in Scholium")
            } footer: {
                Text(
                    "Scholium finds Codex and prepares the connection automatically. Connection settings and saved chat history are managed on this Mac."
                )
            }
            .id("agents.connection")
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

struct AgentChatConnectionAdvancedSettingsView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @ObservedObject var controller: AgentChatController
    @AppStorage("agent.codex.executable") private var executable = ""
    @AppStorage("agent.codex.home") private var home = ""
    @AppStorage("agent.scholium.helper") private var cli = ""
    @State private var fileSelectionTask: Task<Void, Never>?
    @State private var fileSelectionError: String?

    var body: some View {
        Group {
            Section {
                Text(
                    "Override automatic locations only when using a custom Codex installation.",
                    bundle: .module
                )
                .foregroundStyle(.secondary)
                if controller.state != .disconnected {
                    Text("Disconnect Codex to change connection paths.", bundle: .module)
                        .foregroundStyle(.secondary)
                }

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
            } header: {
                Text("Custom Connection Paths", bundle: .module)
            }
            .id("agents.paths")

            if let version = controller.runtimeVersion {
                Section("Runtime") {
                    Text(version)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

        }
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
                            guard controller.state == .disconnected else {
                                fileSelectionError = ScholiumL10n.string("Disconnect Codex to change connection paths.")
                                return
                            }
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
