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
        FileOperationSheet(title: Text(title), message: Text(helpText)) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.bodySectionSpacing) {
                FileOperationPath(path: target.relativePath, symbol: "folder")
                VStack(alignment: .leading, spacing: ScholiumMetrics.ResearchSheet.fieldSpacing) {
                    switch request {
                    case .rename:
                        Text("Name").font(.callout)
                        TextField("Folder name", text: $proposedName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("scholium.folderName")
                    case .move:
                        Picker("Destination", selection: $selectedParent) {
                            Text("Vault Root").tag(String?.none)
                            ForEach(availableParents, id: \.self) { path in
                                Text(verbatim: path).tag(String?.some(path))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("scholium.folderDestination")
                    }
                }
                .disabled(isWorking)
            }
        } actions: {
            if isWorking { ProgressView().controlSize(.small).accessibilityLabel(Text(actionTitle)) }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)
            Button(actionTitle) { perform() }
                .disabled(destinationRelativePath == nil || isWorking)
                .keyboardShortcut(.defaultAction)
        }
        .interactiveDismissDisabled(isWorking)
        .accessibilityIdentifier("scholium.folderFileOperation")
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

    private var alertTitle: String {
        String(
            format: ScholiumL10n.string("Could Not %@ Folder", locale: Locale.current),
            locale: Locale.current,
            actionTitle
        )
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

    private var helpText: String {
        String(
            localized:
                "The folder and all its contents stay together.",
            table: "Localizable",
            bundle: .module
        )
    }

    private var availableParents: [String] {
        let sourcePrefix = target.relativePath + "/"
        return folderRelativePaths.filter { path in
            WorkspaceLibraryVisibility.includes(path)
                && path != target.relativePath
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
            (try? VaultRelativeFolderPath(proposed)) != nil
        else { return nil }
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
