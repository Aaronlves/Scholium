import ScholiumContracts
import SwiftUI

struct FolderFileActions {
    let move: @MainActor (FolderMutationTarget, String) async throws -> Void
}

struct FolderFileOperationView: View {
    @Environment(\.dismiss) private var dismiss

    let request: FolderFileRequest
    let folderRelativePaths: [String]
    let actions: FolderFileActions

    @State private var proposedName = ""
    @State private var selectedParent: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.DocumentWorkflow.sectionSpacing) {
            Label(title, systemImage: symbol)
                .font(ScholiumTypography.interface(.primaryTitle))

            switch request {
            case .rename:
                LabeledContent("Name") {
                    TextField("Folder name", text: $proposedName)
                        .frame(minWidth: 300)
                        .accessibilityIdentifier("scholium.folderName")
                }
            case .move:
                LabeledContent("Destination") {
                    Picker("Destination", selection: $selectedParent) {
                        Text("Vault Root").tag(String?.none)
                        ForEach(availableParents, id: \.self) { path in
                            Text(path).tag(String?.some(path))
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 300)
                    .accessibilityIdentifier("scholium.folderDestination")
                }
            }

            Text(helpText)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionTitle) { perform() }
                    .buttonStyle(.borderedProminent)
                    .disabled(destinationRelativePath == nil || isWorking)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ScholiumMetrics.DocumentWorkflow.sheetContentInset)
        .frame(minWidth: 0, idealWidth: 520, minHeight: 0, idealHeight: 260)
        .onAppear { configureDefaults() }
        .alert("Could Not \(actionTitle) Folder", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var target: FolderMutationTarget { request.target }

    private var title: String {
        switch request {
        case .rename:
            String(localized: "Rename Folder", table: "Localizable", bundle: .module)
        case .move:
            String(localized: "Move Folder", table: "Localizable", bundle: .module)
        }
    }

    private var actionTitle: String {
        switch request {
        case .rename:
            String(localized: "Rename", table: "Localizable", bundle: .module)
        case .move:
            String(localized: "Move", table: "Localizable", bundle: .module)
        }
    }

    private var symbol: String {
        switch request {
        case .rename: "pencil"
        case .move: "folder"
        }
    }

    private var helpText: String {
        String(
            localized: "The folder is only a path-based classification. Scholium preserves each descendant note’s stable identity and moves non-Markdown contents without changing their bytes.",
            table: "Localizable",
            bundle: .module
        )
    }

    private var availableParents: [String] {
        let sourcePrefix = target.relativePath + "/"
        return folderRelativePaths.filter { path in
            path != target.relativePath
                && !path.hasPrefix(sourcePrefix)
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var currentParent: String? {
        let components = target.relativePath.split(separator: "/").map(String.init)
        guard components.count > 1 else { return nil }
        return components.dropLast().joined(separator: "/")
    }

    private var destinationRelativePath: String? {
        let proposed: String
        switch request {
        case .rename:
            let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
                return nil
            }
            proposed = currentParent.map { $0 + "/" + name } ?? name
        case .move:
            proposed = selectedParent.map { $0 + "/" + target.name } ?? target.name
        }
        guard proposed != target.relativePath,
              (try? VaultRelativeFolderPath(proposed)) != nil else { return nil }
        return proposed
    }

    private func configureDefaults() {
        proposedName = target.name
        selectedParent = currentParent
    }

    private func perform() {
        guard let destinationRelativePath else { return }
        isWorking = true
        Task {
            do {
                try await actions.move(target, destinationRelativePath)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isWorking = false
            }
        }
    }
}
