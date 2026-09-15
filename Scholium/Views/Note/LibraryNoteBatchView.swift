import ScholiumContracts
import SwiftUI

/// Presents a window-owned operation. This view never retains mutation authority
/// or starts an operation task; closing a result leaves recovery with its owner.
struct LibraryNoteBatchView: View {
    let request: LibraryNoteBatchRequest
    let folderRelativePaths: [String]
    let outcome: LibraryNoteBatchOutcome?
    let isWorking: Bool
    let move: (String) -> Void
    let cancel: () -> Void
    let retry: () -> Void
    let close: () -> Void
    let openRecovery: () -> Void

    @State private var destination: String?

    var body: some View {
        FileOperationSheet(
            title: outcome == nil ? Text("Move Notes") : Text("File Operation Results"),
            message: outcome == nil
                ? Text("Move the selected notes into one folder in this vault. Their filenames stay the same.")
                : Text("Completed: \(outcome?.succeededCount ?? 0) of \(request.targets.count)")
        ) {
            if let outcome {
                if case .move(let folder) = outcome.operation {
                    LabeledContent("Destination") { folderName(folder) }
                        .font(.callout)
                }
                FileOperationList { results(outcome) }
            } else {
                destinationPicker
                GroupBox {
                    FileOperationList { sourceNotes }
                } label: {
                    Text("Selected notes: \(request.targets.count)")
                }
            }
        } actions: {
            footer
        }
        .interactiveDismissDisabled(isWorking)
        .accessibilityIdentifier("scholium.libraryBatch")
        .onChange(of: request.id) { destination = nil }
        .onChange(of: folderRelativePaths) {
            if let destination, !folderRelativePaths.contains(destination) {
                self.destination = nil
            }
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
            Picker("Destination folder", selection: $destination) {
                Text("Choose…").tag(nil as String?)
                ForEach(folderRelativePaths, id: \.self) { folder in
                    folderName(folder).tag(folder as String?)
                }
            }
            .pickerStyle(.menu)
            .disabled(isWorking || folderRelativePaths.isEmpty)
            .accessibilityIdentifier("scholium.libraryBatch.destination")
            if folderRelativePaths.isEmpty {
                Text("No destination folders are available. Close this sheet and refresh the Library.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sourceNotes: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
            ForEach(request.targets) { target in
                FileOperationPath(path: target.relativePath)
            }
        }
    }

    private func results(_ outcome: LibraryNoteBatchOutcome) -> some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
            ForEach(outcome.items) { item in
                VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                    FileOperationPath(path: item.target.relativePath).fontWeight(.medium)
                    resultStatus(item, operation: outcome.operation)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .succeeded = item.status, let path = item.destinationRelativePath {
                        LabeledContent("Current location") {
                            Text(verbatim: path)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scholium.libraryBatch.result.\(item.id)")
            }
            ForEach(Array(outcome.warnings.enumerated()), id: \.offset) { _, warning in
                Text(verbatim: warning)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if outcome.recoveryRequired {
                Text("Review recovery before attempting more file operations.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scholium.libraryBatch.recoveryRequired")
            }
        }
    }

    @ViewBuilder
    private func resultStatus(_ item: LibraryNoteBatchItemResult, operation: LibraryNoteBatchOperation) -> some View {
        switch item.status {
        case .succeeded:
            Label(operation == .systemTrash ? "Moved to macOS Trash" : "Moved", systemImage: "checkmark.circle")
        case .failed(let message):
            Label("Not completed: \(message)", systemImage: "exclamationmark.triangle").textSelection(.enabled)
        case .unattempted:
            Text("Not attempted")
        case .cancelled:
            Text("Cancelled before moving")
        case .outcomeUnknown(let message):
            Label("Outcome unknown: \(message)", systemImage: "exclamationmark.triangle").textSelection(.enabled)
        }
    }

    private var footer: some View {
        HStack(spacing: ScholiumMetrics.ResearchSheet.footerControlSpacing) {
            if isWorking {
                ProgressView().controlSize(.small)
                Text("Moving notes…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel Remaining", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.libraryBatch.cancelRemaining")
            } else if let outcome {
                Spacer()
                Button("Close", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.libraryBatch.close")
                if outcome.recoveryRequired {
                    Button("Review Recovery…", action: openRecovery)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("scholium.libraryBatch.reviewRecovery")
                } else if !outcome.retryTargets.isEmpty {
                    Button("Retry Remaining…", action: retry)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("scholium.libraryBatch.retry")
                }
            } else {
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.libraryBatch.cancel")
                Button("Move") {
                    guard let destination, folderRelativePaths.contains(destination) else { return }
                    move(destination)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(destination == nil || !folderRelativePaths.contains(destination ?? ""))
                .accessibilityIdentifier("scholium.libraryBatch.move")
            }
        }
    }

    private func folderName(_ path: String) -> Text {
        path.isEmpty ? Text("Vault Root") : Text(verbatim: path)
    }
}
