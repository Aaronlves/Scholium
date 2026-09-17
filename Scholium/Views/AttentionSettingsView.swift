import ScholiumContracts
import SwiftUI

/// A reminder draft belongs to the exact portable settings version where editing began.
struct AttentionSettingsDraft: Equatable {
    let triptychID: UUID
    let triptychName: String
    let triptychLocation: String?
    let revision: SettingsRevision
    let needsRepair: Bool
    var savedSettings: TriptychSettings
    var dismissalDays: Int

    init?(snapshot: WorkspaceSettingsSnapshot) {
        guard let triptychID = snapshot.activeTriptychID,
            let revision = snapshot.portableSettingsState.editableRevision
        else { return nil }
        self.triptychID = triptychID
        let assignment = snapshot.registeredTriptychs.first { $0.id == triptychID }
        self.triptychName = assignment?.triptych.name ?? triptychID.uuidString
        self.triptychLocation = assignment?.vault(for: .output)?.canonicalPath
        self.revision = revision
        if case .needsReview = snapshot.portableSettingsState {
            self.needsRepair = true
        } else {
            self.needsRepair = false
        }
        self.savedSettings = snapshot.triptychSettings
        self.dismissalDays = snapshot.triptychSettings.attentionDismissalDays
    }

    var isDirty: Bool { dismissalDays != savedSettings.attentionDismissalDays }

    var settingsToSave: TriptychSettings {
        var settings = savedSettings
        settings.attentionDismissalDays = dismissalDays
        return settings
    }

    func matches(_ snapshot: WorkspaceSettingsSnapshot) -> Bool {
        triptychID == snapshot.activeTriptychID
            && revision == snapshot.portableSettingsState.editableRevision
    }
}

struct AttentionSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var draft: AttentionSettingsDraft?
    @State private var isSaving = false
    @State private var isReloading = false
    @State private var confirmsReload = false
    @State private var errorMessage: String?
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var dismissalLedgerData = Data()

    private let durations = [1, 3, 7, 14, 30]

    var body: some View {
        Form {
            Section {
                if let draft {
                    LabeledContent("Triptych") {
                        VStack(alignment: .trailing) {
                            Text(draft.triptychName)
                            if let location = draft.triptychLocation {
                                Text(location)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(location)
                            }
                        }
                        .frame(
                            maxWidth: ScholiumMetrics.Settings.formExplanationMaximumWidth, alignment: .trailing
                        )
                        .textSelection(.enabled)
                    }
                    if draft.needsRepair {
                        Label(
                            "Saved reminder timing is invalid. The default is in use; save this value or choose another timing to repair it.",
                            systemImage: "exclamationmark.triangle")
                    }
                    reminderTimingPicker
                    reminderActions
                } else if settingsModel.isRefreshing || isReloading {
                    ProgressView("Loading Reminder Timing")
                } else {
                    Text("Open a Triptych with readable portable settings to change reminder timing.")
                        .foregroundStyle(.secondary)
                    Button("Open Portable Settings Recovery") {
                        SettingsNavigationRequest.select(.workspace)
                    }
                    Button("Reload Reminder Timing") { reload() }
                        .disabled(isReloading || settingsModel.isRefreshing)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Reminder Timing")
            } footer: {
                Text("This Triptych", bundle: .module)
            }.id("notifications.timing")
            Section {
                if AttentionPreferences.ledgerNeedsRecovery(dismissalLedgerData) {
                    Label(
                        "Some dismissed reminders could not be loaded. Available entries are retained; restore dismissed items to repair these settings.",
                        systemImage: "exclamationmark.triangle")
                }
                Button("Restore All Dismissed Items on This Mac") {
                    var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
                    ledger.removeAll()
                    dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
                }
                .disabled(!hasDismissedAttention)
                .id("notifications.dismissed")
            } header: {
                Text("Dismissed Items on This Mac")
            } footer: {
                Text("Restores dismissed reminders on this Mac without changing Triptych data.")
            }
        }
        .scholiumSettingsFormStyle()
        .scholiumSettingsSearchDestination()
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.settings.notifications.form")
        .onAppear { loadInitialDraftIfAvailable() }
        .onChange(of: settingsModel.snapshot) { _, _ in loadInitialDraftIfAvailable() }
        .onChange(of: settingsModel.isRefreshing) { _, _ in loadInitialDraftIfAvailable() }
        .confirmationDialog("Discard Unsaved Reminder Changes?", isPresented: $confirmsReload) {
            Button("Discard Draft and Reload", role: .destructive) { reload() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Reload the active Triptych’s saved reminder timing. Your current draft will be replaced only after it loads successfully."
            )
        }
    }

    private var hasDismissedAttention: Bool {
        AttentionPreferences.ledgerNeedsRecovery(dismissalLedgerData)
            || !AttentionPreferences.decodeLedger(dismissalLedgerData).dismissedUntilByItemID.isEmpty
    }

    private var isCurrentDraft: Bool {
        guard let draft else { return false }
        return draft.matches(settingsModel.snapshot)
            && !settingsModel.requiresSettingsReconciliation(for: draft.triptychID)
    }

    private var availableDurations: [Int] {
        Array(Set(durations + [draft?.dismissalDays].compactMap { $0 })).sorted()
    }

    private var reminderTimingPicker: some View {
        Picker(
            "Return dismissed items after",
            selection: Binding(
                get: { draft?.dismissalDays ?? TriptychSettings().attentionDismissalDays },
                set: { draft?.dismissalDays = $0 }
            )
        ) {
            ForEach(availableDurations, id: \.self) { days in
                Text(days == 1 ? "1 day" : "\(days) days").tag(days)
            }
        }
        .disabled(isSaving || isReloading)
        .accessibilityIdentifier("scholium.settings.notifications.duration")
    }

    @ViewBuilder
    private var reminderActions: some View {
        if !isCurrentDraft {
            Label {
                if draft?.triptychID != settingsModel.snapshot.activeTriptychID {
                    Text(
                        "The active Triptych changed. Your reminder draft is still attached to the Triptych shown above."
                    )
                } else {
                    Text(
                        "Saved settings changed or need to be reread. Your reminder draft is preserved; reload before saving."
                    )
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .foregroundStyle(.secondary)
        }
        HStack {
            Button("Save Reminder Timing") { save() }
                .disabled(
                    isSaving || isReloading || settingsModel.isRefreshing
                        || (draft?.isDirty != true && draft?.needsRepair != true) || !isCurrentDraft
                )
                .accessibilityIdentifier("scholium.settings.notifications.save")
            if draft?.isDirty == true || draft?.needsRepair == true || !isCurrentDraft {
                Button("Reload Reminder Timing") {
                    if draft?.isDirty == true { confirmsReload = true } else { reload() }
                }
                .disabled(isSaving || isReloading)
            }
            if isSaving || isReloading {
                ProgressView().controlSize(.small)
                    .accessibilityLabel(isSaving ? "Saving Reminder Timing" : "Loading Reminder Timing")
            }
        }
    }

    private func loadInitialDraftIfAvailable() {
        guard draft == nil, !isReloading, !settingsModel.isRefreshing else { return }
        draft = AttentionSettingsDraft(snapshot: settingsModel.snapshot)
    }

    private func reload() {
        isReloading = true
        errorMessage = nil
        Task {
            let refreshed = await settingsModel.refresh()
            if refreshed, let replacement = AttentionSettingsDraft(snapshot: settingsModel.snapshot) {
                draft = replacement
            } else {
                errorMessage =
                    settingsModel.errorMessage
                    ?? localizedInterfaceString(
                        "Reminder timing could not be loaded. Your draft has been preserved.")
            }
            isReloading = false
        }
    }

    private func save() {
        guard let submittedDraft = draft, isCurrentDraft else { return }
        errorMessage = nil
        isSaving = true
        Task {
            do {
                let settings = submittedDraft.settingsToSave
                let result = try await settingsModel.saveTriptychSettings(
                    settings,
                    targetTriptychID: submittedDraft.triptychID,
                    expectedRevision: submittedDraft.revision
                )
                if result.targetIsCurrent {
                    draft = AttentionSettingsDraft(snapshot: settingsModel.snapshot)
                    errorMessage = result.warning
                } else {
                    draft?.savedSettings = settings
                    errorMessage = localizedInterfaceString(
                        "Reminder timing was saved to the Triptych shown above. Reload to view the active Triptych."
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
