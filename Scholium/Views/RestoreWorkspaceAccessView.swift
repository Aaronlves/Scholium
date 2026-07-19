import AppKit
import SwiftUI

/// One authorization repair for an already configured Triptych. It never
/// exposes Welcome, Triptych creation, or the other configured locations.
struct RestoreWorkspaceAccessView: View {
    let recovery: WorkspaceAccessRecovery
    let restore: (URL) async throws -> Void
    let closeWindow: () -> Void

    @State private var isRestoring = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore Access")
                .font(.title2.weight(.semibold))

            Text(explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(recovery.expectedPath)
                .font(.callout.monospaced())
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
        .padding(20)
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = String(
            localized: "Restore Access",
            table: "Localizable",
            bundle: .module
        )
        panel.directoryURL = URL(
            fileURLWithPath: recovery.expectedPath,
            isDirectory: true
        ).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isRestoring = true
        errorMessage = nil
        Task {
            do {
                try await restore(url)
                isRestoring = false
            } catch {
                errorMessage = error.localizedDescription
                isRestoring = false
            }
        }
    }
}
