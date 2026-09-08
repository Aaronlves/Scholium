import ScholiumContracts
import SwiftUI

struct AgentChatToolEditor: View {
  @ObservedObject var capabilities: AgentChatCapabilitiesController
  @State var edit: AgentChatToolEdit
  @State var showsAdvanced = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
  @State private var operation: Task<Void, Never>?
  @State private var error: String?
  @State private var confirmsSave = false
  @State private var confirmsRemoval = false
  @State private var isChoosingProgram = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(edit.originalName == nil ? "Add Tool" : "Edit Tool").font(.headline).accessibilityAddTraits(.isHeader)
      Form {
        TextField("Name", text: $edit.connection.name).disabled(edit.originalName != nil)
        Picker("Connection", selection: $edit.connection.kind) {
          Text("Remote").tag(AgentChatToolConnection.Kind.remote)
          Text("Local").tag(AgentChatToolConnection.Kind.local)
        }.pickerStyle(.segmented).disabled(edit.originalName != nil)
        if edit.connection.kind == .remote {
          TextField("Server Address", text: $edit.connection.address)
        } else {
          HStack {
            TextField("Program", text: $edit.connection.address)
            Button("Choose…", action: chooseProgram).disabled(isChoosingProgram)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("Arguments — One per Line").font(.caption)
            TextEditor(text: Binding(get: { edit.connection.arguments.joined(separator: "\n") },
              set: { edit.connection.arguments = $0.isEmpty ? [] : $0.components(separatedBy: "\n") }))
              .frame(height: 80).border(.separator)
              .accessibilityLabel("Arguments")
          }
        }
        Toggle("Enabled", isOn: $edit.connection.enabled)
        DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
          if edit.connection.kind == .remote {
            TextField("Bearer Token Variable", text: $edit.connection.bearerTokenVariable,
              prompt: Text("Optional"))
          } else if edit.connection.canEditEnvironmentVariables {
            VStack(alignment: .leading, spacing: 4) {
              Text("Environment Variables — One per Line").font(.caption)
              TextEditor(text: Binding(get: { edit.connection.environmentVariables.joined(separator: "\n") },
                set: { edit.connection.environmentVariables = $0.isEmpty ? [] : $0.components(separatedBy: "\n") }))
                .frame(height: 60).border(.separator).accessibilityLabel("Environment Variables")
            }
          } else {
            Text("Environment settings are managed by the runtime configuration.")
          }
          Text("Variable names only. Values come from the runtime environment.")
            .font(.caption).foregroundStyle(.secondary)
        }
        if edit.requiresAccessConfirmation {
          Toggle("Reuse Existing Access Settings", isOn: $edit.reuseAccessSettings)
        }
      }.formStyle(.grouped).disabled(operation != nil)
      if capabilities.isShared {
        Text("Shared Codex Settings").font(.caption).foregroundStyle(.secondary)
        Text(edit.home.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }
      if let error { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
      HStack {
        if edit.originalName != nil {
          Button("Remove Tool…") { confirmsRemoval = true }.disabled(operation != nil || !capabilities.canConfigureTools)
        }
        Button("Reload") {
          operation = Task { @MainActor in
            defer { operation = nil }
            if let fresh = await capabilities.reloadToolEdit(edit) { edit = fresh; error = nil }
            else { error = capabilities.toolConfigurationError ?? String(localized: "The tool configuration could not be reloaded.") }
          }
        }.disabled(operation != nil)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(operation != nil)
        Button("Save") {
          if capabilities.isShared { confirmsSave = true } else { save() }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(operation != nil || !capabilities.canConfigureTools || edit.connection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || edit.connection.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || (edit.requiresAccessConfirmation && !edit.reuseAccessSettings))
      }
    }
    .padding(20).frame(width: 460)
    .disabled(isChoosingProgram)
    .interactiveDismissDisabled(operation != nil)
    .confirmationDialog("Save Shared Tool Settings?", isPresented: $confirmsSave) {
      Button("Save") { save() }
    } message: { Text("This changes \(edit.connection.name) for clients using the same Codex settings folder.") }
    .confirmationDialog("Remove Tool?", isPresented: $confirmsRemoval) {
      Button("Remove", role: .destructive) { save(removing: true) }
    } message: { Text("Remove the configuration for \(edit.connection.name)? Its program and sign-in credentials will be kept.") }
  }

  private func save(removing: Bool = false) {
    guard operation == nil else { return }
    error = nil
    operation = Task { @MainActor in
      defer { operation = nil }
      if await capabilities.saveTool(edit, removing: removing) { dismiss() }
      else { error = capabilities.toolConfigurationError ?? String(localized: "The tool configuration could not be saved.") }
    }
  }

  private func chooseProgram() {
    isChoosingProgram = true
    operation = Task { @MainActor in
      defer { operation = nil; isChoosingProgram = false }
      do {
        if let url = try await fileSelectionPresenter.requiredForFileSelection().selectURL(.init(kind: .files(allowedContentTypes: []))) {
          edit.connection.address = url.path
        }
      } catch { self.error = error.localizedDescription }
    }
  }
}
