import SwiftUI

/// One authorization repair for an already configured Triptych. It never
/// exposes Welcome, Triptych creation, or the other configured locations.
struct RestoreWorkspaceAccessView: View {
    @Environment(\.scholiumFileSelectionPresenter) private var fileSelectionPresenter

    let recovery: WorkspaceAccessRecovery
    let restore: (URL) async throws -> Void
    let closeWindow: () -> Void

    @State private var isRestoring = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
            Text("Restore Access")
                .font(ScholiumTypography.interface(.primaryTitle))

            Text(explanation)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(recovery.expectedPath)
                .font(ScholiumTypography.exact(.body))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .scholiumForeground(.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Close Window") { closeWindow() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Folder…") { chooseFolder() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRestoring)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(width: 500)
        .interactiveDismissDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.restoreAccess")
    }

    private var explanation: String {
        switch recovery.kind {
        case .vault:
            String(
                localized: "Choose the same registered vault folder again so macOS can renew Scholium’s access. Other Triptych locations remain unchanged.",
                table: "Localizable",
                bundle: .module
            )
        case .portableControl:
            String(
                localized: "Choose the folder containing Works again so Scholium can renew access to the adjacent portable .scholium folder. Other Triptych locations remain unchanged.",
                table: "Localizable",
                bundle: .module
            )
        }
    }

    private func chooseFolder() {
        let expectedURL = URL(
            fileURLWithPath: recovery.expectedPath,
            isDirectory: true
        )
        let request = ScholiumFileSelectionRequest(
            prompt: String(
                localized: "Restore Access",
                table: "Localizable",
                bundle: .module
            ),
            initialDirectoryURL: expectedURL.deletingLastPathComponent(),
            kind: .directory(canCreateDirectories: false),
            constraint: .exactCanonicalDirectory(
                expectedURL,
                rejectionMessage: String(
                    localized: "Choose the same registered folder shown above.",
                    table: "Localizable",
                    bundle: .module
                )
            )
        )
        Task { @MainActor in
            do {
                guard let url = try await fileSelectionPresenter
                    .requiredForFileSelection()
                    .selectURL(request) else { return }
                isRestoring = true
                errorMessage = nil
                try await restore(url)
                isRestoring = false
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                isRestoring = false
            }
        }
    }
}
