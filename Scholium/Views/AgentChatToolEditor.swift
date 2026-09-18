import ScholiumContracts
import SwiftUI

struct AgentChatToolEditor: View {
    @ObservedObject var capabilities: AgentChatCapabilitiesController
    @State var edit: AgentChatToolEdit
    @State private var sharedTarget: Bool
    var onClose: () -> Void
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, address }
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter
    @State private var operation: Task<Void, Never>?
    @State private var error: String?
    @State private var confirmsSave = false
    @State private var confirmsRemoval = false
    @State private var isChoosingProgram = false

    init(capabilities: AgentChatCapabilitiesController, edit: AgentChatToolEdit, onClose: @escaping () -> Void) {
        self.capabilities = capabilities
        self._edit = State(initialValue: edit)
        self._sharedTarget = State(initialValue: capabilities.isShared)
        self.onClose = onClose
    }

    private var targetIsCurrent: Bool { capabilities.configurationHome == edit.home }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(edit.originalName == nil ? "Add Tool" : "Edit Tool").font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                toolField("Name", text: $edit.connection.name, field: .name)
                    .disabled(edit.originalName != nil)
                Picker("Connection", selection: $edit.connection.kind) {
                    Text("Remote").tag(AgentChatToolConnection.Kind.remote)
                    Text("Local").tag(AgentChatToolConnection.Kind.local)
                }.pickerStyle(.segmented).disabled(edit.originalName != nil)
                if edit.connection.kind == .remote {
                    toolField("Server Address", text: $edit.connection.address, field: .address)
                } else {
                    LabeledContent {
                        HStack {
                            TextField("", text: $edit.connection.address)
                                .focused($focusedField, equals: .address)
                                .accessibilityLabel(Text("Program", bundle: .module))
                            Button("Choose…", action: chooseProgram).disabled(isChoosingProgram)
                        }
                    } label: {
                        Text("Program", bundle: .module)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Arguments — One per Line").font(.caption)
                        TextEditor(
                            text: Binding(
                                get: { edit.connection.arguments.joined(separator: "\n") },
                                set: {
                                    edit.connection.arguments = $0.isEmpty ? [] : $0.components(separatedBy: "\n")
                                })
                        )
                        .frame(height: 80).border(.separator)
                        .accessibilityLabel("Arguments")
                    }
                }
                Toggle("Enabled", isOn: $edit.connection.enabled)
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Text("Authentication and Environment", bundle: .module)
                        .font(.headline).accessibilityAddTraits(.isHeader)
                    if edit.connection.kind == .remote {
                        toolField("Bearer Token Variable", text: $edit.connection.bearerTokenVariable)
                    } else if edit.connection.canEditEnvironmentVariables {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Environment Variables — One per Line").font(.caption)
                            TextEditor(
                                text: Binding(
                                    get: { edit.connection.environmentVariables.joined(separator: "\n") },
                                    set: {
                                        edit.connection.environmentVariables =
                                            $0.isEmpty ? [] : $0.components(separatedBy: "\n")
                                    })
                            )
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
            }.textFieldStyle(.roundedBorder).disabled(operation != nil)
            if sharedTarget {
                Text("Shared Codex Settings").font(.caption).foregroundStyle(.secondary)
            }
            Text(edit.home.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if !targetIsCurrent {
                Text("The connection changed. Your tool draft is retained. Reconnect to its configuration folder to continue.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                if edit.originalName != nil {
                    Button("Remove Tool…") { confirmsRemoval = true }.disabled(
                        operation != nil || !targetIsCurrent || !capabilities.canConfigureTools)
                }
                Button("Reload") {
                    operation = Task { @MainActor in
                        defer { operation = nil }
                        if let fresh = await capabilities.reloadToolEdit(edit) {
                            edit = fresh
                            error = nil
                        } else {
                            error =
                                capabilities.toolConfigurationError
                                ?? String(localized: "The tool configuration could not be reloaded.")
                        }
                    }
                }.disabled(operation != nil || !targetIsCurrent)
                Spacer()
                Button("Cancel", action: onClose).disabled(operation != nil)
                Button("Save") {
                    if sharedTarget { confirmsSave = true } else { save() }
                }
                .disabled(
                    operation != nil || !targetIsCurrent || !capabilities.canConfigureTools
                        || edit.connection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || edit.connection.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (edit.requiresAccessConfirmation && !edit.reuseAccessSettings))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { focusedField = edit.originalName == nil ? .name : .address }
        .disabled(isChoosingProgram)
        .confirmationDialog("Save Shared Tool Settings?", isPresented: $confirmsSave) {
            Button("Save") { save() }
        } message: {
            Text("This changes \(edit.connection.name) for clients using the same Codex settings folder.")
        }
        .confirmationDialog("Remove Tool?", isPresented: $confirmsRemoval) {
            Button("Remove", role: .destructive) { save(removing: true) }
        } message: {
            Text(
                "Remove the configuration for \(edit.connection.name)? Its program and sign-in credentials will be kept."
            )
        }
    }

    private func toolField(_ title: LocalizedStringKey, text: Binding<String>, field: Field? = nil) -> some View {
        LabeledContent {
            if let field {
                TextField("", text: text)
                    .focused($focusedField, equals: field)
                    .accessibilityLabel(Text(title, bundle: .module))
            } else {
                TextField("", text: text)
                    .accessibilityLabel(Text(title, bundle: .module))
            }
        } label: {
            Text(title, bundle: .module)
        }
    }

    private func save(removing: Bool = false) {
        guard operation == nil else { return }
        error = nil
        operation = Task { @MainActor in
            defer { operation = nil }
            if await capabilities.saveTool(edit, removing: removing) {
                onClose()
            } else {
                error =
                    capabilities.toolConfigurationError
                    ?? String(localized: "The tool configuration could not be saved.")
            }
        }
    }

    private func chooseProgram() {
        isChoosingProgram = true
        operation = Task { @MainActor in
            defer {
                operation = nil
                isChoosingProgram = false
            }
            do {
                if let url = try await fileSelectionPresenter.requiredForFileSelection().selectURL(
                    .init(kind: .files(allowedContentTypes: [])))
                {
                    edit.connection.address = url.path
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
