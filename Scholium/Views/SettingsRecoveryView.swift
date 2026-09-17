import ScholiumContracts
import SwiftUI

/// Recovery belongs to portable configuration, never the registered folders or
/// research source. Confirmation pins both the target and its observed bytes.
struct PortableSettingsRecoverySection: View {
    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    let triptychID: UUID
    @State private var request: WorkspaceSettingsRecoveryRequest?
    @State private var confirmsRestore = false
    @State private var isPreparing = false
    @State private var preparationTask: Task<Void, Never>?
    @State private var preparationGeneration: UInt64 = 0
    @State private var message: String?
    @State private var preservedURL: URL?

    private var isCurrent: Bool { settingsModel.snapshot.activeTriptychID == triptychID }
    private var isBusy: Bool { isPreparing || settingsModel.isRestoringSettings }

    var body: some View {
        Section {
            if isCurrent {
                if let status { Label(status, systemImage: "exclamationmark.triangle") }
                HStack {
                    Button("Restore Portable Settings Defaults…") { prepare() }
                        .disabled(isBusy || settingsModel.isRefreshing)
                        .accessibilityIdentifier("scholium.settings.portable.restore")
                    Button("Reload Portable Settings") {
                        Task { _ = await settingsModel.refresh() }
                    }
                    .disabled(isBusy || settingsModel.isRefreshing)
                    if isBusy { ProgressView().controlSize(.small) }
                }
                if let error = settingsModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .textSelection(.enabled)
                }
                if let message {
                    Text(message).textSelection(.enabled)
                        .accessibilityIdentifier("scholium.settings.portable.result")
                }
                if let preservedURL {
                    LabeledContent("Previous Settings Copy") {
                        Text(preservedURL.path(percentEncoded: false))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            } else {
                Text("Select this Triptych again to inspect its portable settings.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Portable Settings")
        } footer: {
            Text("This Triptych. Restoring settings preserves registered folders, research files and other preferences.")
        }
        .id("workspace.settingsRecovery")
        .confirmationDialog("Restore Portable Settings Defaults?", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("Restore Portable Settings Defaults", role: .destructive) { restore() }
            Button("Cancel", role: .cancel) { request = nil }
        } message: {
            Text(
                "Replace this Triptych’s portable settings with defaults. The existing file is preserved as a separate copy. Unsaved reminder changes stay as a draft and must be reloaded before saving."
            )
        }
        .onDisappear { cancelPreparation() }
        .onChange(of: isPaneActive) { _, active in
            if !active { cancelPreparation() }
        }
        .onChange(of: settingsModel.snapshot.activeTriptychID) { _, _ in
            cancelPreparation()
            message = nil
            preservedURL = nil
        }
    }

    private var status: String? {
        switch settingsModel.portableSettingsState {
        case .current: nil
        case .needsReview: ScholiumL10n.string("Some portable settings are invalid. Available values remain in use; repair or restore the affected settings.")
        case .missing: ScholiumL10n.string("Portable settings are missing. Default values are in use.")
        case .oldSchema: ScholiumL10n.string("Portable settings use an older format. The existing file has been preserved.")
        case .futureSchema: ScholiumL10n.string("Portable settings use a newer format. The existing file has been preserved.")
        case .corrupted: ScholiumL10n.string("Portable settings are damaged. Default values are in use; the existing file has been preserved.")
        case .readFailed(let reason): reason
        case .unavailable: ScholiumL10n.string("Portable settings are unavailable. Reload or restore folder access to try again.")
        }
    }

    private func prepare() {
        guard isCurrent, !isBusy else { return }
        preparationGeneration &+= 1
        let generation = preparationGeneration
        isPreparing = true
        message = nil
        preparationTask = Task { @MainActor in
            defer { if generation == preparationGeneration { isPreparing = false } }
            do {
                let prepared = try await settingsModel.prepareSettingsRecovery(triptychID: triptychID)
                guard generation == preparationGeneration, isPaneActive, isCurrent else { return }
                request = prepared
                confirmsRestore = true
            } catch is CancellationError {
                return
            } catch {
                guard generation == preparationGeneration, isPaneActive, isCurrent else { return }
                message = error.localizedDescription
            }
        }
    }

    private func cancelPreparation() {
        preparationGeneration &+= 1
        isPreparing = false
        preparationTask?.cancel()
        preparationTask = nil
        request = nil
        confirmsRestore = false
    }

    private func restore() {
        guard let request else { return }
        self.request = nil
        Task { @MainActor in
            do {
                let commit = try await settingsModel.restoreSettingsDefaults(request)
                guard isCurrent else { return }
                preservedURL = commit.recovery.preservedSettingsURL
                message =
                    commit.derivedRefreshWarning == nil
                    ? ScholiumL10n.string("Portable settings were restored to defaults.")
                    : ScholiumL10n.string("Defaults were saved. Research views will refresh when the workspace is available.")
            } catch {
                guard isCurrent else { return }
                message = error.localizedDescription
            }
        }
    }
}
