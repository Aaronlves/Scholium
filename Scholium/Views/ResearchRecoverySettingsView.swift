import ScholiumContracts
import SwiftUI

struct ResearchRecoverySettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var listing = ResearchSkillMaintenanceSnapshotListing(
        snapshots: [],
        issues: []
    )
    @State private var skills: [ResearchSkillPackage] = []
    @State private var recoveryPolicy = ResearchRecoveryPolicySnapshot(
        retention: .defaultValue,
        revision: nil,
        settledSnapshotCount: 0,
        maximumSnapshotsForOneNote: 0
    )
    @State private var pendingPolicyChange: ResearchRecoveryPolicyChangePreview?
    @State private var pendingRestore: ResearchSkillMaintenanceSnapshot?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Recovery & Technical",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Manage settled Note versions, inspect machine-local Skill recovery snapshots, and reveal the current portable Skills folder.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                researchSettingsSection(LocalizedStringResource(
                    "SETTLED VERSIONS",
                    table: "Localizable",
                    bundle: .module
                )) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Keep per Note")
                            Text("Settle preserves the exact saved revision of that Note. Temporary Action recovery is managed separately.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 24)
                        Picker(
                            "Keep per Note",
                            selection: Binding(
                                get: { recoveryPolicy.retention },
                                set: { preparePolicyChange($0) }
                            )
                        ) {
                            ForEach(SettledSnapshotRetention.allCases, id: \.self) {
                                Text(retentionTitle($0)).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        .disabled(isWorking)
                        .accessibilityIdentifier("scholium.recovery.settledRetention")
                    }
                    Text(settledVersionSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                researchSettingsSection(LocalizedStringResource(
                    "SKILL RECOVERY",
                    table: "Localizable",
                    bundle: .module
                )) {
                    if listing.snapshots.isEmpty {
                        Text("No Skill recovery snapshots are available.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(listing.snapshots) { snapshot in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: snapshot.packageID)
                                        Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Restore…") { pendingRestore = snapshot }
                                        .disabled(isWorking)
                                }
                                .frame(minHeight: 40)
                                Divider()
                            }
                        }
                    }
                    ForEach(listing.issues, id: \.id) { issue in
                        Label(issue.summary, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(ScholiumColorRole.attention.color)
                    }
                }
                researchSettingsSection(LocalizedStringResource(
                    "FILES",
                    table: "Localizable",
                    bundle: .module
                )) {
                    Button("Reveal Skills Folder") { revealSkillsFolder() }
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .disabled(loadedTriptychID != settingsModel.activeTriptychServicesID)
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .confirmationDialog(
            "Remove Older Settled Versions?",
            isPresented: Binding(
                get: { pendingPolicyChange != nil },
                set: { if !$0 { pendingPolicyChange = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apply and Remove Older Versions", role: .destructive) {
                applyPendingPolicyChange()
            }
            Button("Cancel", role: .cancel) { pendingPolicyChange = nil }
        } message: {
            if let pendingPolicyChange {
                Text("This will remove \(pendingPolicyChange.snapshotIDsToRemove.count) older settled versions across \(pendingPolicyChange.affectedNoteCount) Notes. Current Markdown and temporary Action recovery are not removed.")
            }
        }
        .confirmationDialog(
            "Restore Complete Skill Package?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Complete Package") { restoreSnapshot() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Scholium rechecks the current package revision and creates an undo snapshot before replacement when possible.")
        }
        .alert("Recovery Operation Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("Dismiss", role: .cancel) {} } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() async {
        guard let requestedTriptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            listing = ResearchSkillMaintenanceSnapshotListing(snapshots: [], issues: [])
            skills = []
            recoveryPolicy = ResearchRecoveryPolicySnapshot(
                retention: .defaultValue,
                revision: nil,
                settledSnapshotCount: 0,
                maximumSnapshotsForOneNote: 0
            )
            pendingPolicyChange = nil
            pendingRestore = nil
            return
        }
        loadedTriptychID = nil
        pendingPolicyChange = nil
        pendingRestore = nil
        do {
            async let loadedListing = settingsModel.researchSkillMaintenanceSnapshots()
            async let loadedSkills = settingsModel.researchSkills()
            async let loadedPolicy = settingsModel.recoveryPolicy()
            let (newListing, newSkills, newPolicy) = try await (
                loadedListing,
                loadedSkills,
                loadedPolicy
            )
            try Task.checkCancellation()
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            listing = newListing
            skills = newSkills
            recoveryPolicy = newPolicy
            loadedTriptychID = requestedTriptychID
        } catch is CancellationError {
            return
        } catch {
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func preparePolicyChange(_ retention: SettledSnapshotRetention) {
        guard retention != recoveryPolicy.retention,
              !isWorking,
              let requestedTriptychID = settingsModel.activeTriptychServicesID else {
            return
        }
        let expectedRevision = recoveryPolicy.revision
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let preview = try await settingsModel.prepareRecoveryPolicyChange(
                    retention,
                    expectedRevision: expectedRevision
                )
                guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                    return
                }
                if preview.snapshotIDsToRemove.isEmpty {
                    let outcome = try await settingsModel.applyRecoveryPolicyChange(preview)
                    guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                        return
                    }
                    recoveryPolicy = outcome.snapshot
                } else {
                    pendingPolicyChange = preview
                }
            } catch {
                guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyPendingPolicyChange() {
        guard let preview = pendingPolicyChange,
              preview.triptychID == settingsModel.activeTriptychServicesID else {
            pendingPolicyChange = nil
            return
        }
        let requestedTriptychID = preview.triptychID
        pendingPolicyChange = nil
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let outcome = try await settingsModel.applyRecoveryPolicyChange(preview)
                guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                    return
                }
                recoveryPolicy = outcome.snapshot
            } catch {
                guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                    return
                }
                errorMessage = error.localizedDescription
                await reload()
            }
        }
    }

    private func retentionTitle(_ retention: SettledSnapshotRetention) -> String {
        switch retention {
        case .keep10:
            String(localized: "10 versions", table: "Localizable", bundle: .module)
        case .keep30:
            String(localized: "30 versions", table: "Localizable", bundle: .module)
        case .keep50:
            String(localized: "50 versions", table: "Localizable", bundle: .module)
        case .neverDelete:
            String(localized: "Do Not Delete Automatically", table: "Localizable", bundle: .module)
        }
    }

    private var settledVersionSummary: String {
        String(
            localized: "\(recoveryPolicy.settledSnapshotCount) settled versions are stored on this Mac. The largest Note history contains \(recoveryPolicy.maximumSnapshotsForOneNote).",
            table: "Localizable",
            bundle: .module
        )
    }

    private func restoreSnapshot() {
        guard let snapshot = pendingRestore else { return }
        pendingRestore = nil
        let current = skills.first {
            $0.origin == .triptych && $0.id == snapshot.packageID
        }
        let expectedState: ResearchSkillMaintenanceExpectedCurrentState
        if let revision = current?.revision {
            expectedState = .present(revision)
        } else {
            expectedState = .missing
        }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                _ = try await settingsModel.restoreResearchSkillMaintenance(
                    snapshotID: snapshot.id,
                    expectedCurrentState: expectedState
                )
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func revealSkillsFolder() {
        Task { @MainActor in
            do { settingsModel.openExternal(try await settingsModel.researchSkillsURL()) }
            catch { errorMessage = error.localizedDescription }
        }
    }

}
