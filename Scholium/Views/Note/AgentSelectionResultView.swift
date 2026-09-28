import SwiftUI

/// Presentation of a window-owned writing result. Dismissal never owns operations.
struct AgentSelectionResultView: View {
    @ObservedObject var result: AgentSelectionResult
    let close: () -> Void
    var width: CGFloat = 380
    var pasteboardWriter: any PasteboardWriting = ScholiumPasteboardWriter.general
    @State private var copyFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(result.title).font(.headline)
                Spacer()
                Button("Continue in Chat", systemImage: "bubble.left.and.bubble.right") {
                    close()
                    result.continueInChat()
                }
                .labelStyle(.iconOnly)
                .help("Continue in Chat")
                .disabled(!result.canContinueInChat)
                .accessibilityIdentifier("scholium.selectionResult.continue")
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .help("Close")
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.selectionResult.close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if result.adopt != nil {
                        DisclosureGroup("Original") {
                            Text(result.original).textSelection(.enabled)
                        }
                    }
                    if let reply = result.finalReply {
                        if result.adopt != nil {
                            Text(reply).textSelection(.enabled)
                        } else {
                            Text(.init(reply)).textSelection(.enabled)
                        }
                    } else if !result.isGenerating, !result.isStopped, result.error == nil {
                        Text("No completed reply.")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if result.versions.count > 1 {
                HStack {
                    Button("Previous Version", systemImage: "chevron.left") { result.previousVersion() }
                        .labelStyle(.iconOnly)
                        .help("Previous Version")
                        .disabled(result.selectedVersionIndex == 0 || result.isAdopting || result.isAdopted)
                    Text(ScholiumL10n.string("Version \(result.selectedVersionIndex + 1) of \(result.versions.count)"))
                        .monospacedDigit()
                    Button("Next Version", systemImage: "chevron.right") { result.nextVersion() }
                        .labelStyle(.iconOnly)
                        .help("Next Version")
                        .disabled(result.selectedVersionIndex == result.versions.count - 1 || result.isAdopting || result.isAdopted)
                    Spacer()
                }
                .accessibilityIdentifier("scholium.selectionResult.versions")
            }
            operationStatus
            if copyFailed {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("Could not copy the reply. Choose Copy to try again.", systemImage: "exclamationmark.triangle")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss") { copyFailed = false }
                }
                .font(.caption)
                .accessibilityIdentifier("scholium.selectionResult.copyError")
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    secondaryActions
                    Spacer(minLength: 12)
                    replacementAction
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        secondaryActions
                        Spacer()
                    }
                    if result.adopt != nil {
                        HStack {
                            Spacer()
                            replacementAction
                        }
                    }
                }
            }
        }
        .environment(
            \.openURL,
            OpenURLAction { url in
                if url.scheme == "scholium-note" { return result.openReference(url) ? .handled : .discarded }
                return ["https", "http"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
            }
        )
        .onChange(of: result.selectedVersionIndex) { _, _ in copyFailed = false }
        .padding(16)
        .frame(width: width, height: 340)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.selectionResult")
    }

    @ViewBuilder
    private var operationStatus: some View {
        if let message = result.adoptionError ?? result.error {
            ScrollView {
                Label {
                    Text(message).textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 72)
            .accessibilityIdentifier("scholium.selectionResult.error")
        } else if result.isStopped {
            Text("Generation stopped.")
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if result.isGenerating || result.isAdopting {
            HStack {
                ProgressView().controlSize(.small)
                Text(ScholiumL10n.string(result.isAdopting ? "Replacing selection…" : "Preparing reply…"))
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        ScholiumCopyButton(contentIdentity: "\(result.selectedVersionIndex):\(result.finalReply ?? "")") {
            let copied = copyReply()
            copyFailed = !copied
            if !copied {
                NSAccessibility.post(
                    element: NSApp as Any, notification: .announcementRequested,
                    userInfo: [
                        .announcement: ScholiumL10n.string("Could not copy the reply. Choose Copy to try again."),
                        .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                    ])
            }
            return copied
        }
        .buttonStyle(.borderless)
        .disabled(result.finalReply == nil)
        .accessibilityIdentifier("scholium.selectionResult.copy")
        Button {
            if result.isGenerating { result.stop() } else { result.regenerate() }
        } label: {
            ZStack {
                // Reserve the longest lifecycle label so narrow footers do not
                // switch layout when Regenerate becomes Stop or Retry.
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .hidden().accessibilityHidden(true)
                Label(
                    ScholiumL10n.string(result.isGenerating ? "Stop" : result.error == nil ? "Regenerate" : "Retry"),
                    systemImage: result.isGenerating ? "stop" : "arrow.clockwise")
            }
        }
        .disabled(!result.isGenerating && !result.canRegenerate)
        .accessibilityIdentifier(result.isGenerating ? "scholium.selectionResult.stop" : "scholium.selectionResult.regenerate")
    }

    @ViewBuilder
    private var replacementAction: some View {
        if result.adopt != nil {
            Button(ScholiumL10n.string(result.isAdopted ? "Replaced" : "Replace Selection")) {
                result.adoptSelectedVersion()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!result.canAdopt)
            .accessibilityIdentifier("scholium.selectionResult.adopt")
        }
    }

    func copyReply() -> Bool {
        guard let reply = result.finalReply else { return false }
        return pasteboardWriter.writeText(reply)
    }
}
