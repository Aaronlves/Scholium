import ScholiumContracts
import SwiftUI

struct NoteFileActions {
    let duplicate: @MainActor (NoteMutationTarget, String) async throws -> Void
    let move: @MainActor (NoteMutationTarget, String) async throws -> Void
}

struct NoteFileOperationView: View {
    @Environment(\.dismiss) private var dismiss

    let request: NoteFileRequest
    let actions: NoteFileActions

    @State private var destination = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        FileOperationSheet(title: Text(sheetTitle), message: Text(helpText)) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
                FileOperationPath(path: target.relativePath)
                VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                    Text(fieldTitle).font(.callout)
                    TextField(fieldPlaceholder, text: $destination)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text(fieldTitle))
                        .accessibilityIdentifier("scholium.noteFile.destination")
                        .disabled(isWorking)
                }
            }
        } actions: {
            if isWorking { ProgressView().controlSize(.small).accessibilityLabel(Text(actionTitle)) }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
            Button(actionTitle) { perform() }
                .disabled(requestedDestinationPath == nil || isWorking)
                .keyboardShortcut(.defaultAction)
        }
        .interactiveDismissDisabled(isWorking)
        .accessibilityIdentifier("scholium.noteFileOperation")
        .onAppear { configureDefaults() }
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var target: NoteMutationTarget {
        switch request {
        case .duplicate(let target), .rename(let target), .move(let target): target
        }
    }

    private var sheetTitle: LocalizedStringResource {
        switch request {
        case .duplicate: "Duplicate Note"
        case .rename: "Rename Note"
        case .move: "Move Note"
        }
    }

    private var actionTitle: LocalizedStringResource {
        switch request {
        case .duplicate: "Duplicate"
        case .rename: "Rename"
        case .move: "Move"
        }
    }

    private var alertTitle: String {
        String(
            format: ScholiumL10n.string("Could Not %@", locale: Locale.current),
            locale: Locale.current,
            ScholiumL10n.localized(actionTitle, locale: Locale.current)
        )
    }

    private var helpText: LocalizedStringResource {
        switch request {
        case .duplicate:
            "Create a copy at a new location in this vault."
        case .rename:
            "Choose a new filename. The note stays in its current folder."
        case .move:
            "Enter the destination path within this vault."
        }
    }

    private var fieldTitle: LocalizedStringResource {
        if case .rename = request { "Name" } else { "Location" }
    }

    private var fieldPlaceholder: LocalizedStringResource {
        if case .rename = request { "Note Name" } else { "Folder/Note.md" }
    }

    private var requestedDestinationPath: String? {
        switch request {
        case .rename(let target):
            guard
                let renamed = noteRenameDestination(
                    sourceRelativePath: target.relativePath,
                    requestedName: destination
                ), renamed != target.relativePath
            else { return nil }
            return renamed
        case .duplicate, .move:
            let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func configureDefaults() {
        switch request {
        case .duplicate(let target):
            let base = (target.relativePath as NSString).deletingPathExtension
            destination = base + " Copy.md"
        case .rename(let target):
            destination =
                URL(fileURLWithPath: target.relativePath)
                .deletingPathExtension()
                .lastPathComponent
        case .move(let target):
            destination = target.relativePath
        }
    }

    private func perform() {
        guard let requestedDestinationPath else { return }
        isWorking = true
        Task {
            do {
                switch request {
                case .duplicate(let source):
                    try await actions.duplicate(source, requestedDestinationPath)
                case .rename(let source):
                    try await actions.move(source, requestedDestinationPath)
                case .move(let source):
                    try await actions.move(source, requestedDestinationPath)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }

}

func noteRenameDestination(
    sourceRelativePath: String,
    requestedName: String
) -> String? {
    let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty,
        name != ".",
        name != "..",
        !name.contains("/"),
        !name.contains(":")
    else { return nil }
    let fileName =
        URL(fileURLWithPath: name).pathExtension
            .caseInsensitiveCompare("md") == .orderedSame
        ? name
        : name + ".md"
    let parent = (sourceRelativePath as NSString).deletingLastPathComponent
    guard parent != ".", !parent.isEmpty else { return fileName }
    return (parent as NSString).appendingPathComponent(fileName)
}
