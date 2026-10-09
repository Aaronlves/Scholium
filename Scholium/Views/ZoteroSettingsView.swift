import AppKit
import ScholiumContracts
import SwiftUI

struct ZoteroSettingsView: View {
    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var info = ZoteroLibraryInfo(
        status: .appUnavailable, lastSuccessfulConnection: nil)
    @State private var isTesting = false
    @State private var errorMessage: String?

    var body: some View {
        Section("Zotero Desktop") {
            LabeledContent("Local API") {
                Label(statusTitle, systemImage: statusSymbol)
                    .foregroundStyle(.primary)
            }
            LabeledContent("Last Connected") {
                Text(
                    info.lastSuccessfulConnection?.formatted(date: .abbreviated, time: .shortened)
                        ?? localizedInterfaceString("Never")
                )
                .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    zoteroActions
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    zoteroActions
                }
            }
            Text(
                "Scholium uses Zotero Desktop's localhost API, not its private database. Chat item changes require confirmation and Zotero's local write authorization. Import BibTeX and RIS in Zotero."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if info.status == .apiDisabled {
                Text(
                    "In Zotero Advanced settings, enable ‘Allow other applications on this computer to communicate with Zotero’, then test again."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
        .task(id: isPaneActive) {
            guard isPaneActive else { return }
            let current = await settingsModel.zoteroConnectionInfo()
            guard !Task.isCancelled else { return }
            info = current
        }
        .accessibilityIdentifier("scholium.settings.zotero.connection")
    }

    @ViewBuilder
    private var zoteroActions: some View {
        Button("Open Zotero") {
            Task { await settingsModel.openZotero() }
        }
        Button("Check Connection") { refresh() }
            .disabled(isTesting)
        Button("Clear History", role: .destructive) {
            Task {
                try? await settingsModel.clearZoteroConnectionHistory()
                info = await settingsModel.zoteroConnectionInfo()
            }
        }
        .accessibilityLabel("Clear Connection History")
    }

    private var statusTitle: String {
        switch info.status {
        case .available, .itemMissing:
            localizedInterfaceString("Connected")
        case .apiDisabled:
            localizedInterfaceString("Access Disabled in Zotero")
        case .appUnavailable:
            localizedInterfaceString("Zotero Not Available")
        }
    }

    private var statusSymbol: String {
        info.status == .available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private func refresh() {
        isTesting = true
        Task {
            do {
                info = try await settingsModel.refreshZoteroLibraryInfo()
                errorMessage = nil
            } catch {
                info = await settingsModel.zoteroConnectionInfo()
                errorMessage = error.localizedDescription
            }
            isTesting = false
        }
    }
}
