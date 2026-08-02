import ScholiumContracts
import SwiftUI

struct NoteLifecycleActions {
    let duplicate: @MainActor (NoteLifecycleTarget, String) async throws -> Void
    let move: @MainActor (NoteLifecycleTarget, String) async throws -> Void
}

struct NoteLifecycleView: View {
    @Environment(\.dismiss) private var dismiss

    let request: NoteLifecycleRequest
    let actions: NoteLifecycleActions

    @State private var destination = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Label(sheetTitle, systemImage: symbol)
                        .font(.title2.weight(.semibold))
                    Spacer()
                }

                adaptiveField(
                    fieldTitle,
                    wide: {
                        TextField(fieldPlaceholder, text: $destination)
                            .font(.body.monospaced())
                            .frame(minWidth: 300)
                    },
                    compact: {
                        TextField(fieldPlaceholder, text: $destination)
                            .font(.body.monospaced())
                    }
                )

                Text(helpText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(actionTitle) { perform() }
                        .buttonStyle(.borderedProminent)
                        .disabled(requestedDestinationPath == nil || isWorking)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, idealWidth: 540, minHeight: 0, idealHeight: 460)
        .onAppear { configureDefaults() }
        .alert("Could Not \(actionTitle)", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func adaptiveField<WideContent: View, CompactContent: View>(
        _ title: String,
        @ViewBuilder wide: () -> WideContent,
        @ViewBuilder compact: () -> CompactContent
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            LabeledContent(title) {
                wide()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.callout.weight(.medium))
                compact()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sheetTitle: String {
        switch request {
        case .duplicate: "Duplicate Note"
        case .rename: "Rename Note"
        case .move: "Move Note"
        }
    }

    private var actionTitle: String {
        switch request {
        case .duplicate: "Duplicate"
        case .rename: "Rename"
        case .move: "Move"
        }
    }

    private var symbol: String {
        switch request {
        case .duplicate: "plus.square.on.square"
        case .rename: "pencil"
        case .move: "folder"
        }
    }

    private var helpText: String {
        switch request {
        case .duplicate:
            "The duplicate preserves the exact source bytes and receives a new stable note identity."
        case .rename:
            "Renaming preserves the note's folder, identity, Discussion, and Research Record."
        case .move:
            "Moving preserves the note identity, Discussion, and Research Record."
        }
    }

    private var fieldTitle: String {
        if case .rename = request { "Name" } else { "Location" }
    }

    private var fieldPlaceholder: String {
        if case .rename = request { "Note Name" } else { "Folder/Note.md" }
    }

    private var requestedDestinationPath: String? {
        switch request {
        case .rename(let target):
            guard let renamed = noteRenameDestination(
                sourceRelativePath: target.relativePath,
                requestedName: destination
            ), renamed != target.relativePath else { return nil }
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
            destination = URL(fileURLWithPath: target.relativePath)
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
          !name.contains(":") else { return nil }
    let fileName = URL(fileURLWithPath: name).pathExtension
        .caseInsensitiveCompare("md") == .orderedSame
        ? name
        : name + ".md"
    let parent = (sourceRelativePath as NSString).deletingLastPathComponent
    guard parent != ".", !parent.isEmpty else { return fileName }
    return (parent as NSString).appendingPathComponent(fileName)
}
