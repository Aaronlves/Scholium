import ScholiumContracts
import SwiftUI

struct SystemTrashConfirmationView: View {
    let preview: SystemTrashDeletionPreview
    let confirm: (SystemTrashDeletionPreview) async throws -> Void
    let cancel: () -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        FileOperationSheet(
            title: Text("Move to macOS Trash?"),
            message: Text("These items will move to the macOS Trash. You can restore them in Finder.")
        ) {
            GroupBox("Files and Folders") {
                FileOperationList {
                    VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                        ForEach(preview.sources) { source in
                            FileOperationPath(path: source.relativePath, symbol: source.kind == .folder ? "folder" : "doc.text")
                        }
                    }
                }
            }
            Text("If the operation cannot finish, Scholium keeps the result and provides recovery.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("scholium.systemTrashError")
            }
        } actions: {
            if isWorking {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Moving items to Trash…")
            }
            Spacer()
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
            Button("Move to Trash", role: .destructive) { perform() }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorking)
        }
        .interactiveDismissDisabled(isWorking)
        .accessibilityIdentifier("scholium.systemTrashConfirmation")
    }

    private func perform() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await confirm(preview)
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
