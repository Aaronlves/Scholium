import ScholiumContracts
import SwiftUI

private enum ResearchPermissionChoice: Hashable {
    case inherited
    case needsRenewal
    case policy(ResearchPermissionPolicy)
}
struct ResearchPermissionSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var snapshot: ResearchPermissionSettingsSnapshot?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Permissions",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Choose when Scholium may issue a validated, short-lived grant without asking again. These policies never enlarge a Skill or Action Profile, and do not monitor external agents or network activity.",
                        table: "Localizable",
                        bundle: .module
                    )
                )

                if let snapshot {
                    triptychDefaultSection(snapshot)
                    skillOverridesSection(snapshot)
                } else if isWorking {
                    ProgressView("Loading permissions…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView {
                        Label("Permissions Unavailable", systemImage: "lock.slash")
                    } description: {
                        Text(errorMessage ?? "Open a complete Triptych to manage Research Guidance permissions.")
                    } actions: {
                        if settingsModel.activeTriptychServicesID != nil {
                            Button("Try Again") { Task { await reload() } }
                        }
                    }
                }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("scholium.researchGuidance.permissions")
        .disabled(
            isWorking
                || loadedTriptychID != settingsModel.activeTriptychServicesID
        )
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
    }

    @ViewBuilder
    private func triptychDefaultSection(
        _ snapshot: ResearchPermissionSettingsSnapshot
    ) -> some View {
        researchSettingsSection(LocalizedStringResource(
            "TRIPTYCH DEFAULT",
            table: "Localizable",
            bundle: .module
        )) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(
                    "Default policy",
                    selection: Binding(
                        get: { snapshot.policy.document.triptychDefault },
                        set: { policy in
                            Task { await saveTriptychPolicy(policy) }
                        }
                    )
                ) {
                    ForEach(ResearchPermissionPolicy.allCases, id: \.self) { policy in
                        Text(policyTitle(policy)).tag(policy)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier(
                    "scholium.researchGuidance.permissions.triptychPolicy"
                )

                Text(policyDetail(snapshot.policy.document.triptychDefault))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            "scholium.researchGuidance.permissions.error"
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func skillOverridesSection(
        _ snapshot: ResearchPermissionSettingsSnapshot
    ) -> some View {
        researchSettingsSection(LocalizedStringResource(
            "SKILL OVERRIDES",
            table: "Localizable",
            bundle: .module
        )) {
            if snapshot.skills.isEmpty {
                Text("No active Skills have permission envelopes in this Triptych.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(snapshot.skills.enumerated()), id: \.element.id) {
                        index,
                        skill in
                        skillPolicyRow(skill)
                        if index < snapshot.skills.count - 1 {
                            Divider().padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func skillPolicyRow(_ skill: ResearchPermissionSkillStatus) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.displayName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(skill.packageID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)

                if skill.status == .missingSkill {
                    Button("Remove Override") {
                        Task { await removeSkillOverride(packageID: skill.packageID) }
                    }
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.permissions.skill.\(skill.packageID).remove"
                    )
                } else {
                    Picker(
                        "Policy for \(skill.displayName)",
                        selection: Binding(
                            get: { permissionChoice(for: skill) },
                            set: { choice in
                                Task {
                                    await saveSkillChoice(
                                        choice,
                                        skill: skill
                                    )
                                }
                            }
                        )
                    ) {
                        if skill.status == .invalidated {
                            Text("Needs Renewal")
                                .tag(ResearchPermissionChoice.needsRenewal)
                                .disabled(true)
                        }
                        Text("Use Triptych Default")
                            .tag(ResearchPermissionChoice.inherited)
                        ForEach(ResearchPermissionPolicy.allCases, id: \.self) { policy in
                            Text(policyTitle(policy))
                                .tag(ResearchPermissionChoice.policy(policy))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                    .accessibilityLabel("Policy for \(skill.displayName)")
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.permissions.skill.\(skill.packageID).policy"
                    )
                }
            }

            Text(skillStatusDetail(skill))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(
                    "scholium.researchGuidance.permissions.skill.\(skill.packageID).status"
                )
        }
    }

    private func permissionChoice(
        for skill: ResearchPermissionSkillStatus
    ) -> ResearchPermissionChoice {
        if skill.status == .invalidated { return .needsRenewal }
        guard let policy = skill.overridePolicy else { return .inherited }
        return .policy(policy)
    }

    private func policyTitle(_ policy: ResearchPermissionPolicy) -> String {
        switch policy {
        case .askEveryTime:
            localizedInterfaceString("Ask Me Every Time")
        case .askOnlyForWorks:
            localizedInterfaceString("Ask Me Only for Works")
        case .triptychWide:
            localizedInterfaceString("Triptych-wide")
        }
    }

    private func policyDetail(_ policy: ResearchPermissionPolicy) -> String {
        switch policy {
        case .askEveryTime:
            localizedInterfaceString(
                "Ask before every additional Note or write-capable child phase. The Target you selected by clicking an Action is already authorized."
            )
        case .askOnlyForWorks:
            localizedInterfaceString(
                "Allow validated Analysis and Topic continuations, but ask before every request that could modify a Work."
            )
        case .triptychWide:
            localizedInterfaceString(
                "Allow validated continuations within this Triptych only when every Skill, Profile, request, identity, and revision boundary also permits them."
            )
        }
    }

    private func skillStatusDetail(
        _ skill: ResearchPermissionSkillStatus
    ) -> String {
        switch skill.status {
        case .inherited:
            localizedInterfaceString("Uses the current Triptych default.")
        case .approved:
            localizedInterfaceString("Applies only to this exact Skill and Action Profile envelope.")
        case .invalidated:
            localizedInterfaceString("The Skill or one of its Action Profiles changed. Ask Me Every Time applies until you renew or remove this override.")
        case .missingSkill:
            localizedInterfaceString("This Skill is no longer active. Its retained override cannot authorize a run and may be removed.")
        }
    }

    @MainActor
    private func reload() async {
        guard let requestedTriptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            snapshot = nil
            errorMessage = nil
            isWorking = false
            return
        }
        isWorking = true
        errorMessage = nil
        do {
            let loaded = try await settingsModel.researchPermissionSettings()
            try Task.checkCancellation()
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            snapshot = loaded
            loadedTriptychID = requestedTriptychID
        } catch is CancellationError {
            return
        } catch {
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            snapshot = nil
            loadedTriptychID = requestedTriptychID
            errorMessage = error.localizedDescription
        }
        if settingsModel.activeTriptychServicesID == requestedTriptychID {
            isWorking = false
        }
    }

    @MainActor
    private func saveTriptychPolicy(_ policy: ResearchPermissionPolicy) async {
        guard let current = snapshot,
              loadedTriptychID == settingsModel.activeTriptychServicesID,
              current.policy.document.triptychDefault != policy else { return }
        await performSave {
            try await settingsModel.saveTriptychPermissionPolicy(
                policy,
                expectedRevision: current.policy.revision
            )
        }
    }

    @MainActor
    private func saveSkillChoice(
        _ choice: ResearchPermissionChoice,
        skill: ResearchPermissionSkillStatus
    ) async {
        guard let current = snapshot,
              loadedTriptychID == settingsModel.activeTriptychServicesID else { return }
        switch choice {
        case .inherited:
            await performSave {
                try await settingsModel.removeSkillPermissionOverride(
                    packageID: skill.packageID,
                    expectedRevision: current.policy.revision
                )
            }
        case .policy(let policy):
            guard let subject = skill.subject else { return }
            await performSave {
                try await settingsModel.saveSkillPermissionOverride(
                    packageID: skill.packageID,
                    policy: policy,
                    expectedEnvelopeDigest: subject.envelopeDigest,
                    expectedRevision: current.policy.revision
                )
            }
        case .needsRenewal:
            break
        }
    }

    @MainActor
    private func removeSkillOverride(packageID: String) async {
        guard let current = snapshot,
              loadedTriptychID == settingsModel.activeTriptychServicesID else { return }
        await performSave {
            try await settingsModel.removeSkillPermissionOverride(
                packageID: packageID,
                expectedRevision: current.policy.revision
            )
        }
    }

    @MainActor
    private func performSave(
        _ operation: () async throws -> ResearchPermissionSettingsSnapshot
    ) async {
        guard let requestedTriptychID = loadedTriptychID else { return }
        isWorking = true
        errorMessage = nil
        do {
            let saved = try await operation()
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            snapshot = saved
        } catch {
            guard settingsModel.activeTriptychServicesID == requestedTriptychID else {
                return
            }
            let saveError = error.localizedDescription
            await reload()
            if settingsModel.activeTriptychServicesID == requestedTriptychID {
                errorMessage = saveError
            }
        }
        if settingsModel.activeTriptychServicesID == requestedTriptychID {
            isWorking = false
        }
    }
}
