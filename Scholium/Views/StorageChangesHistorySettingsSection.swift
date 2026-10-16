import ScholiumContracts
import SwiftUI

struct StorageChangesHistorySettingsSection: View {
    private struct ClearTarget {
        let id: UUID
        let name: String
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

    private var currentSnapshot: WorkspaceChangesHistorySnapshot? {
        loadedTriptychID == triptychID ? snapshot : nil
    }

    var body: some View {
        Section("Changes History — This Mac") {
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

            if loadedTriptychID == triptychID, let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button("Retry") { Task { await load() } }
                    .disabled(isLoading || isMutating)
            }

            Button("Clear Reviewed History…", role: .destructive) {
                clearTarget = ClearTarget(id: triptychID, name: triptychName)
            }
            .disabled(isLoading || isMutating || (currentSnapshot?.usage.count ?? 0) == 0)
            .accessibilityIdentifier("scholium.settings.clearChangesHistory")
        }
        .id(SettingsSection.storageChangesHistory)
        .task(id: triptychID) { await load() }
        .onChange(of: isPaneActive) { _, active in
            if !active { clearTarget = nil }
        }
        .onReceive(settingsModel.changesHistoryUpdates) { changedID in
            if isPaneActive, changedID == triptychID { Task { await load() } }
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

    private func load() async {
        let targetID = triptychID
        if loadedTriptychID != targetID { snapshot = nil }
        loadedTriptychID = targetID
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await settingsModel.changesHistory(triptychID: targetID)
            guard triptychID == targetID, loadGeneration == generation else { return }
            snapshot = loaded
        } catch is CancellationError {
            return
        } catch {
            guard triptychID == targetID, loadGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func setRetention(
        _ choice: DocumentChangeRetention,
        for targetID: UUID
    ) async {
        guard targetID == triptychID, snapshot != nil, !isMutating else { return }
        isMutating = true
        errorMessage = nil
        do {
            let changed = try await settingsModel.setChangesHistoryRetention(
                choice, triptychID: targetID
            )
            if targetID == triptychID { snapshot = changed }
        } catch {
            if targetID == triptychID {
                let issue = error.localizedDescription
                await load()
                errorMessage = issue
            }
        }
        isMutating = false
    }

    private func clearHistory(for targetID: UUID) async {
        guard !isMutating else { return }
        isMutating = true
        errorMessage = nil
        do {
            let cleared = try await settingsModel.clearChangesHistory(triptychID: targetID)
            if targetID == triptychID { snapshot = cleared }
        } catch {
            if targetID == triptychID {
                let issue = error.localizedDescription
                await load()
                errorMessage = issue
            }
        }
        isMutating = false
    }
}
