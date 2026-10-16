import ScholiumContracts
import SwiftUI

struct StorageChangesHistorySettingsSection: View {
    private struct ClearTarget {
        let id: UUID
        let name: String
    }

    private struct LoadRequest: Equatable {
        let triptychID: UUID
        let isActive: Bool
        let revision: UInt64
    }

    private struct MutationFailure {
        let triptychID: UUID
        let message: String
    }

    @Environment(\.scholiumSettingsPaneIsActive) private var isPaneActive
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    let triptychID: UUID
    let triptychName: String

    @State private var snapshot: WorkspaceChangesHistorySnapshot?
    @State private var isLoading = true
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var clearTarget: ClearTarget?
    @State private var loadGeneration = 0
    @State private var loadedTriptychID: UUID?
    @State private var refreshRevision: UInt64 = 0
    @State private var mutationFailure: MutationFailure?

    private var currentSnapshot: WorkspaceChangesHistorySnapshot? {
        loadedTriptychID == triptychID ? snapshot : nil
    }

    private var currentErrorMessage: String? {
        if let mutationFailure, mutationFailure.triptychID == triptychID {
            return mutationFailure.message
        }
        return loadedTriptychID == triptychID ? errorMessage : nil
    }

    var body: some View {
        let request = LoadRequest(triptychID: triptychID, isActive: isPaneActive, revision: refreshRevision)
        return Section("Changes History — This Mac") {
            Text("For \(triptychName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(
                "Keep Reviewed History",
                selection: Binding(
                    get: { currentSnapshot?.retention ?? .days90 },
                    set: { choice in
                        let targetID = triptychID
                        Task { await setRetention(choice, for: targetID) }
                    }
                )
            ) {
                Text("30 Days").tag(DocumentChangeRetention.days30)
                Text("90 Days").tag(DocumentChangeRetention.days90)
                Text("1 Year").tag(DocumentChangeRetention.days365)
                Text("Forever").tag(DocumentChangeRetention.forever)
            }
            .pickerStyle(.menu)
            .disabled(isLoading || isMutating || currentSnapshot == nil)
            .accessibilityIdentifier("scholium.settings.changesRetention")

            if let snapshot = currentSnapshot {
                LabeledContent("Reviewed History") {
                    Text("\(snapshot.usage.count) records · \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.usage.byteCount), countStyle: .file))")
                }
                if snapshot.usage.protectedByteCount > 0 {
                    LabeledContent("Comparison & Operation Data") {
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount: Int64(snapshot.usage.protectedByteCount),
                                countStyle: .file
                            ))
                    }
                    .help("Saved comparison baselines and Agent receipts needed for Undo or recovery can remain after reviewed history is cleared.")
                }
            } else if isLoading || loadedTriptychID != triptychID {
                ProgressView("Loading Changes History…")
            }

            if let currentErrorMessage {
                Label(currentErrorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Retry") {
                    if mutationFailure?.triptychID == triptychID { mutationFailure = nil }
                    refreshRevision &+= 1
                }
                .disabled(isLoading || isMutating)
            }

            Button("Clear Reviewed History…", role: .destructive) {
                clearTarget = ClearTarget(id: triptychID, name: triptychName)
            }
            .disabled(isLoading || isMutating || (currentSnapshot?.usage.count ?? 0) == 0)
            .accessibilityIdentifier("scholium.settings.clearChangesHistory")
        }
        .id(SettingsSection.storageChangesHistory)
        .task(id: request) {
            guard request.isActive, !Task.isCancelled else { return }
            await load(for: request.triptychID)
        }
        .onChange(of: isPaneActive) { _, active in
            if !active { clearTarget = nil }
        }
        .onReceive(settingsModel.changesHistoryUpdates) { changedID in
            if isPaneActive, changedID == triptychID { refreshRevision &+= 1 }
        }
        .onChange(of: triptychID) { _, _ in clearTarget = nil }
        .confirmationDialog(
            "Clear Reviewed History for This Triptych?",
            isPresented: Binding(
                get: { clearTarget != nil },
                set: { if !$0 { clearTarget = nil } }
            )
        ) {
            Button("Clear Reviewed History", role: .destructive) {
                guard let target = clearTarget else { return }
                clearTarget = nil
                Task { await clearHistory(for: target.id) }
            }
            Button("Cancel", role: .cancel) { clearTarget = nil }
        } message: {
            Text(
                "Reviewed comparisons for \(clearTarget?.name ?? triptychName) on this Mac will be deleted. Current Note text and pending Changes, including their starting versions, remain available."
            )
        }
    }

    private func isCurrentTarget(_ targetID: UUID) -> Bool {
        loadedTriptychID == targetID && settingsModel.selectedTriptychID == targetID
    }

    private func load(for targetID: UUID) async {
        guard settingsModel.selectedTriptychID == targetID, !Task.isCancelled else { return }
        if loadedTriptychID != targetID { snapshot = nil }
        loadedTriptychID = targetID
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer {
            if loadedTriptychID == targetID, loadGeneration == generation { isLoading = false }
        }
        do {
            let loaded = try await settingsModel.changesHistory(triptychID: targetID)
            try Task.checkCancellation()
            guard isCurrentTarget(targetID), loadGeneration == generation else { return }
            snapshot = loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, isCurrentTarget(targetID), loadGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func beginMutation(for targetID: UUID) {
        isMutating = true
        if mutationFailure?.triptychID == targetID { mutationFailure = nil }
        if isCurrentTarget(targetID) {
            loadGeneration &+= 1
            isLoading = false
            errorMessage = nil
        }
    }

    private func installMutationSnapshot(_ changed: WorkspaceChangesHistorySnapshot, for targetID: UUID) {
        guard isCurrentTarget(targetID) else { return }
        // An earlier automatic read cannot replace the committed operation result.
        loadGeneration &+= 1
        isLoading = false
        snapshot = changed
    }

    private func recordMutationFailure(_ error: Error, for targetID: UUID) {
        mutationFailure = MutationFailure(triptychID: targetID, message: error.localizedDescription)
        // Reconcile through the visible pane's owned read. Failure feedback remains
        // pinned to the operation target while that read or later navigation runs.
        if isCurrentTarget(targetID) { refreshRevision &+= 1 }
    }

    private func setRetention(
        _ choice: DocumentChangeRetention,
        for targetID: UUID
    ) async {
        guard targetID == triptychID, snapshot != nil, !isMutating else { return }
        beginMutation(for: targetID)
        defer { isMutating = false }
        do {
            let changed = try await settingsModel.setChangesHistoryRetention(
                choice, triptychID: targetID
            )
            installMutationSnapshot(changed, for: targetID)
        } catch {
            recordMutationFailure(error, for: targetID)
        }
    }

    private func clearHistory(for targetID: UUID) async {
        guard !isMutating else { return }
        beginMutation(for: targetID)
        defer { isMutating = false }
        do {
            let cleared = try await settingsModel.clearChangesHistory(triptychID: targetID)
            installMutationSnapshot(cleared, for: targetID)
        } catch {
            recordMutationFailure(error, for: targetID)
        }
    }
}
