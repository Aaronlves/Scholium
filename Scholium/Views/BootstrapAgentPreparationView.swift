import AppKit
import ScholiumContracts
import SwiftUI

/// Optional first-launch machine preparation. This view owns only local
/// presentation state; the installed CLI remains Application-owned and every
/// research authorization still begins from an exact Run handoff.
struct BootstrapAgentPreparationView: View {
    let triptychRootURL: URL
    let commandLineToolStatus: () async -> CommandLineToolStatus
    let installCommandLineTool: () async throws -> CommandLineToolStatus
    let allowsBack: Bool
    let isCompletingBootstrap: Bool
    let goBack: () -> Void
    let setUpLater: () -> Void
    let confirmSetup: () -> Void

    @State private var status: CommandLineToolStatus?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var promptCopied = false
    @State private var showsPrompt = false
    @State private var showsConfirmation = false

    var body: some View {
        preparationPane
        .task { await refreshStatus() }
        .sheet(isPresented: $showsPrompt) {
            BootstrapAgentPromptSheet(prompt: setupPrompt)
        }
        .alert("Confirm Agent Setup", isPresented: $showsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Confirm") { confirmSetup() }
        } message: {
            Text(
                "I confirm that my Agent project and workspace root both use \(triptychRootPath), and that the Agent created or verified the applicable instruction file without overwriting existing instructions."
            )
        }
        .accessibilityIdentifier("scholium.bootstrap.agentPreparation")
    }

    private var preparationPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prepare an Agent")
                            .font(.title.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Text("Optional. Research access still begins only from a specific Scholium Run handoff.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Project and workspace location")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(triptychRootPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .accessibilityLabel("Agent project and workspace location")
                            .accessibilityValue(triptychRootPath)
                    }

                    Divider()

                    BootstrapAgentTaskRow(number: 1, title: "Install and verify Scholium CLI") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 10) {
                                if let status {
                                    Label(statusLabel(status), systemImage: statusSymbol(status))
                                        .font(.caption)
                                        .scholiumForeground(status.state == .installed ? .confirmed : .secondaryText)
                                        .accessibilityLabel("Scholium CLI status")
                                        .accessibilityValue(statusLabel(status))
                                } else {
                                    ProgressView("Checking…")
                                        .controlSize(.small)
                                }
                                Spacer(minLength: 8)
                                if let actionTitle = cliActionTitle {
                                    Button(actionTitle) {
                                        Task { await performCLIAction() }
                                    }
                                    .disabled(isWorking)
                                }
                                if isWorking {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityLabel("Installing Scholium CLI")
                                }
                            }
                            if let status {
                                Text(status.installPath)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let repairMessage = status.repairMessage {
                                    Text(repairMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    Divider()

                    BootstrapAgentTaskRow(number: 2, title: "Copy setup instructions") {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(promptCopied
                                ? "Setup Prompt Copied"
                                : "Ask the Agent to prepare its project and applicable instruction file.")
                                .font(.caption)
                                .scholiumForeground(promptCopied ? .confirmed : .secondaryText)

                            HStack(spacing: 10) {
                                Button("Preview…") { showsPrompt = true }
                                Button {
                                    copySetupPrompt()
                                } label: {
                                    Label(
                                        promptCopied ? "Copy Again" : "Copy Prompt",
                                        systemImage: promptCopied ? "checkmark" : "document.on.document"
                                    )
                                }
                                .disabled(!cliIsReady)
                                .accessibilityHint("Copies the complete Agent setup instructions to the Clipboard")
                            }
                        }
                    }

                    Divider()

                    BootstrapAgentTaskRow(number: 3, title: "Return and confirm") {
                        Text("After the Agent reports Ready, confirm below. Scholium records only your confirmation; it cannot inspect the external configuration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Label {
                        Text("A local connection does not imply a local model. Cloud-provider data practices still apply.")
                            .font(.caption)
                            .scholiumForeground(.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "network")
                            .scholiumForeground(.mutedText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .scholiumForeground(.destructive)
                            .textSelection(.enabled)
                            .accessibilityLabel("Agent setup error: \(errorMessage)")
                    }
                }
                .padding(.top, 58)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 12) {
                Button("Back", action: goBack)
                    .keyboardShortcut(.cancelAction)
                    .disabled(!allowsBack || isCompletingBootstrap)
                Spacer()
                Button("Set Up Later", action: setUpLater)
                    .disabled(isCompletingBootstrap)
                Button("I’ve Set Up My Agent") {
                    showsConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isCompletingBootstrap || !cliIsReady || !promptCopied)
                if isCompletingBootstrap {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Finishing Triptych setup")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(ScholiumColorRole.documentBackground.color)
    }

    private var triptychRootPath: String {
        triptychRootURL.standardizedFileURL.path(percentEncoded: false)
    }

    private var setupPrompt: String {
        BootstrapAgentPreparationPrompt.text(triptychRootURL: triptychRootURL)
    }

    private var cliIsReady: Bool {
        status?.state == .installed
    }

    private var cliActionTitle: LocalizedStringResource? {
        guard let status else { return nil }
        return switch status.state {
        case .notInstalled: "Install and Verify"
        case .updateAvailable: "Update and Verify"
        case .installed: "Check Again"
        case .bundledToolUnavailable, .invalidInstallation: nil
        }
    }

    private func refreshStatus() async {
        status = await commandLineToolStatus()
    }

    private func performCLIAction() async {
        guard let status else { return }
        errorMessage = nil
        switch status.state {
        case .notInstalled, .updateAvailable:
            isWorking = true
            defer { isWorking = false }
            do {
                self.status = try await installCommandLineTool()
            } catch {
                errorMessage = error.localizedDescription
                self.status = await commandLineToolStatus()
            }
        case .installed:
            await refreshStatus()
        case .bundledToolUnavailable, .invalidInstallation:
            break
        }
    }

    private func copySetupPrompt() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(setupPrompt, forType: .string) else {
            errorMessage = "Scholium could not copy the Agent setup instructions."
            return
        }
        errorMessage = nil
        promptCopied = true
    }

    private func statusLabel(_ status: CommandLineToolStatus) -> String {
        switch status.state {
        case .bundledToolUnavailable: "Not included in this build"
        case .notInstalled: "Ready to install"
        case .updateAvailable: "Update available"
        case .installed: status.isOnCurrentPATH ? "Installed and discoverable" : "Installed"
        case .invalidInstallation: "Needs attention"
        }
    }

    private func statusSymbol(_ status: CommandLineToolStatus) -> String {
        switch status.state {
        case .installed: status.isOnCurrentPATH ? "checkmark.circle" : "checkmark"
        case .notInstalled, .updateAvailable: "terminal"
        case .bundledToolUnavailable, .invalidInstallation: "exclamationmark.triangle"
        }
    }
}

enum BootstrapAgentPreparationPrompt {
    static func text(triptychRootURL: URL) -> String {
        let root = triptychRootURL.standardizedFileURL.path(percentEncoded: false)
        return """
        Prepare an external Agent project for Scholium.

        Project root and workspace root (use this exact same folder):
        \(root)

        1. Open or create a separate Agent project whose project root and workspace root are both the exact folder above.
        2. Verify the installed Scholium CLI by running:
           $HOME/.local/bin/scholium version --format json
           $HOME/.local/bin/scholium doctor --format json
           Then read: $HOME/.local/bin/scholium help agent
        3. Inspect this root and its ancestors for applicable AGENTS.md and CLAUDE.md instructions before creating anything.
        4. If no applicable instruction file exists, create the instruction file yourself at the project root:
           - Create AGENTS.md when your Agent supports it.
           - If you are Claude Code, create only the minimal CLAUDE.md needed for Claude and have it refer to AGENTS.md instead of duplicating the rules.
           - Never overwrite, merge, shadow, or silently replace an existing instruction file. Report the exact blocker instead.
           - Read every file back and report the exact paths you created or used.
        5. In those instructions, prefer Scholium-provided CLI and Agent tools for research work. Ordinary read tools remain your choice.
        6. Follow Scholium's file rules strictly:
           - Treat exact Markdown bytes as authoritative.
           - Never edit .scholium directly.
           - Preserve BOM, newline style, comments, unknown YAML, ordering, quoting, multiline values, and final newlines outside an explicitly changed range.
           - For an existing Note mutation that needs Scholium's bounded-write, checkpoint, conflict, and recovery guarantees, use the current Run's authenticated, fingerprint-checked Scholium mutation path. A raw filesystem write is an external edit, not a Scholium-authorized write.
        7. Do not read Triptych research files or request a pairing code now. Wait for a specific Research Run handoff from Scholium.
        8. If PATH, a shell profile, or Agent configuration must change, first name the exact file and proposed change and wait for my confirmation.

        Finish by reporting either Ready, including the project root, workspace root, CLI result, and instruction-file paths, or one precise blocker.
        """
    }
}

private struct BootstrapAgentTaskRow<Content: View>: View {
    let number: Int
    let title: LocalizedStringResource
    @ViewBuilder let content: Content

    init(
        number: Int,
        title: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.number = number
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number, format: .number)
                .font(.caption.weight(.semibold))
                .scholiumForeground(.accent)
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .stroke(ScholiumColorRole.accent.color, lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.body.weight(.semibold))
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BootstrapAgentPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prompt: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent Setup Prompt")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(ScholiumColorRole.navigationSurfaceBackground.color)

            Divider()

            ScrollView {
                Text(prompt)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
            }
            .background(ScholiumColorRole.documentBackground.color)
        }
        .frame(minWidth: 620, minHeight: 560)
    }
}
