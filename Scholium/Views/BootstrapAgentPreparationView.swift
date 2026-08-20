import ScholiumContracts
import SwiftUI

/// Optional first-launch Agent preparation. This view copies researcher-owned
/// instructions; the external Agent owns CLI installation and every research
/// authorization still begins from an exact Run handoff.
struct BootstrapAgentPreparationView: View {
    let triptychRootURL: URL
    let allowsBack: Bool
    let isCompletingBootstrap: Bool
    let goBack: () -> Void
    let setUpLater: () -> Void
    let confirmSetup: () -> Void

    @State private var errorMessage: String?
    @State private var promptCopied = false
    @State private var showsPrompt = false
    @State private var showsConfirmation = false

    var body: some View {
        preparationPane
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
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    VStack(alignment: .leading, spacing: ScholiumMetrics.Onboarding.agentStatusSpacing) {
                        Text("Prepare an Agent")
                            .font(ScholiumTypography.interface(.primaryTitle))
                            .accessibilityAddTraits(.isHeader)
                        Text("Optional. Research access still begins only from a specific Scholium Run handoff.")
                            .font(ScholiumTypography.interface(.body))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: ScholiumMetrics.Onboarding.agentDetailSpacing) {
                        Text("Project and workspace location")
                            .font(ScholiumTypography.interface(.small, emphasis: .strong))
                            .scholiumForeground(.secondaryText)
                        Text(triptychRootPath)
                            .font(ScholiumTypography.exact(.small))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .accessibilityLabel("Agent project and workspace location")
                            .accessibilityValue(triptychRootPath)
                    }

                    Divider()

                    BootstrapAgentTaskRow(number: 1, title: "Copy setup instructions") {
                        VStack(alignment: .leading, spacing: ScholiumMetrics.Onboarding.agentTaskContentSpacing) {
                            Text(promptCopied
                                ? "Setup Prompt Copied"
                                : "The prompt authorizes the Agent to install the official CLI, then prepare this project.")
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(promptCopied ? .confirmed : .secondaryText)

                            HStack(spacing: ScholiumMetrics.Onboarding.agentTaskSpacing) {
                                Button("Preview…") { showsPrompt = true }
                                Button {
                                    copySetupPrompt()
                                } label: {
                                    Label(
                                        promptCopied ? "Copy Again" : "Copy Prompt",
                                        systemImage: promptCopied ? "checkmark" : "document.on.document"
                                    )
                                }
                                .accessibilityHint("Copies the complete Agent setup instructions to the Clipboard")
                            }
                        }
                    }

                    Divider()

                    BootstrapAgentTaskRow(number: 2, title: "Let the Agent finish setup") {
                        Text("The Agent installs and verifies the CLI, reads Scholium's Agent help, and prepares the applicable project instructions and Skill discovery links.")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    BootstrapAgentTaskRow(number: 3, title: "Return and confirm") {
                        Text("After the Agent reports Ready, confirm below. Scholium records only your confirmation; it cannot inspect the external configuration.")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Label {
                        Text("A local connection does not imply a local model. Cloud-provider data practices still apply.")
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "network")
                            .scholiumForeground(.mutedText)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.destructive)
                            .textSelection(.enabled)
                            .accessibilityLabel("Agent setup error: \(errorMessage)")
                    }
                }
                .padding(.top, ScholiumMetrics.Onboarding.agentContentTopInset)
                .padding(.horizontal, ScholiumMetrics.Onboarding.stepHorizontalInset)
                .padding(.bottom, ScholiumMetrics.Onboarding.footerHorizontalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
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
                .disabled(isCompletingBootstrap || !promptCopied)
                if isCompletingBootstrap {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Finishing Triptych setup")
                }
            }
            .padding(.horizontal, ScholiumMetrics.Onboarding.footerHorizontalInset)
            .padding(.vertical, ScholiumMetrics.Onboarding.footerVerticalInset)
        }
        .background(ScholiumColorRole.documentBackground.color)
    }

    private var triptychRootPath: String {
        triptychRootURL.standardizedFileURL.path(percentEncoded: false)
    }

    private var setupPrompt: String {
        BootstrapAgentPreparationPrompt.text(triptychRootURL: triptychRootURL)
    }

    private func copySetupPrompt() {
        guard ScholiumPasteboardWriter.general.writeText(setupPrompt) else {
            errorMessage = String(
                localized: "Scholium could not copy the Agent setup instructions.",
                table: "Localizable",
                bundle: .module
            )
            return
        }
        errorMessage = nil
        promptCopied = true
    }

}

enum BootstrapAgentPreparationPrompt {
    static func text(triptychRootURL: URL) -> String {
        let root = triptychRootURL.resolvingSymlinksInPath()
            .standardizedFileURL.path(percentEncoded: false)
        return """
        Prepare an external Agent project for Scholium.

        Project root and workspace root (use this exact same folder):
        \(root)

        CLI installation authorization:
        \(ScholiumCLIInstallationInstructions.text)

        Project preparation:
        1. Open or create a separate Agent project whose project root and workspace root are both the exact folder above.
        2. Inspect this root and its ancestors for applicable AGENTS.md and CLAUDE.md instructions before creating anything.
        3. Obtain Scholium's exact project Skill sources with:
           $HOME/.local/bin/scholium workspace skill-sources --format json
           - Accept only schema_version 1.
           - Require workspace_root to equal the exact project root above.
           - Do not scan for, infer, or substitute any other Skill source.
        4. Determine which supported Agent host you are currently running in and use only its project-level Skill discovery directory under the exact workspace root:
           - Codex: .agents/skills
           - Claude Code: .claude/skills
           - For another host, create no discovery directory or link unless its current project-level Agent Skills location is already authoritatively known; otherwise report that discovery setup is unsupported.
           - Require every existing discovery-directory component beneath the workspace root to be a real directory, not a symlink, and require the resolved discovery directory to remain beneath the exact workspace root. Create only missing directory components; otherwise stop and report the exact blocker.
        5. For every entry returned in skills, create one directory symlink whose leaf name is exactly name and whose target is exactly source_directory.
           - Create links only inside the selected project-level Skill discovery directory.
           - If a destination is already a symlink to the same resolved source, leave it unchanged.
           - If a destination is a file, directory, dangling link, or points anywhere else, stop and report the exact conflict. Never overwrite, merge, rename, or repair it.
           - Do not copy or edit Skill contents and do not inspect sibling directories. This setup instruction permits only resolving the exact returned folder and confirming its SKILL.md exists; the link itself never grants permission to read research or edit .scholium.
           - Read back every link target without loading the Method body, then report the exact links created or reused.
        6. If no applicable AGENTS.md exists, generate its exact candidate with the manifest's triptych_id and workspace_root:
           $HOME/.local/bin/scholium workspace bootstrap --triptych <triptych_id> --target <workspace_root>
           Verify the target again, create AGENTS.md without replacing any existing path, read it back exactly, and remove only any task-owned temporary candidate. If an applicable AGENTS.md already exists, use it unchanged.
           If you are Claude Code and no applicable CLAUDE.md exists, create only the minimal CLAUDE.md needed for Claude and have it refer to AGENTS.md instead of duplicating the rules.
           Never overwrite, merge, shadow, or silently replace an existing instruction file. Report the exact blocker instead.
        7. Use the current host's own Skill listing to confirm that every returned name is discovered from the exact project link. Do not inspect or modify skills in another scope. If a newly created discovery directory requires a restart or new Agent task, report that requirement as the blocker and do not claim Ready yet.
        8. Follow Scholium's file rules strictly:
           - Treat exact Markdown bytes as authoritative.
           - Never edit .scholium directly.
           - Preserve BOM, newline style, comments, unknown YAML, ordering, quoting, multiline values, and final newlines outside an explicitly changed range.
           - For an existing Note mutation that needs Scholium's bounded-write, diff, Undo, conflict, and recovery guarantees, use the current Run's authenticated, fingerprint-checked Scholium mutation path. A raw filesystem write is an external edit, not a Scholium-authorized write.
        9. Do not read Triptych research files or request a pairing code now. A later researcher request may start an eligible Run through `scholium agent start`; a GUI-created Run still begins from its specific copied handoff.

        Finish by reporting either Ready, including the Agent host, project root, workspace root, CLI result, instruction-file paths, discovery links, and confirmed host discovery, or one precise blocker.
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
        HStack(alignment: .top, spacing: ScholiumMetrics.Onboarding.decisionRowSpacing) {
            Text(number, format: .number)
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .scholiumForeground(.accent)
                .frame(width: 24, height: 24)
                .overlay {
                    Circle()
                        .stroke(ScholiumColorRole.accent.color, lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text(title)
                    .font(ScholiumTypography.interface(.sectionTitle))
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
                    .font(ScholiumTypography.interface(.sectionTitle))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, ScholiumMetrics.Onboarding.agentPromptHeaderHorizontalInset)
            .padding(.vertical, ScholiumGrid.Spacing.sectionSeparation)
            .background(ScholiumColorRole.navigationSurfaceBackground.color)

            Divider()

            ScrollView {
                Text(prompt)
                    .font(ScholiumTypography.exact(.body))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ScholiumMetrics.Onboarding.agentPromptBodyInset)
            }
            .background(ScholiumColorRole.documentBackground.color)
        }
        .frame(minWidth: 620, minHeight: 560)
    }
}
