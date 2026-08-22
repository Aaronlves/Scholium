import ScholiumContracts
import SwiftUI

struct ResearchPermissionSettingsView: View {
    @EnvironmentObject private var settingsModel: WorkspaceSettingsModel
    @State private var loadedTriptychID: UUID?
    @State private var snapshot: ResearchCollaborationPolicySnapshot?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Agent Access",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Choose when an Agent may extend a Run’s bounded write set in this Triptych.",
                        table: "Localizable",
                        bundle: .module
                    )
                )

                researchSettingsSection(LocalizedStringResource(
                    "AGENT WRITE ACCESS FOR THIS TRIPTYCH",
                    table: "Localizable",
                    bundle: .module
                )) {
                    if let snapshot {
                        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                            Picker(
                                "Agent access policy",
                                selection: Binding(
                                    get: { snapshot.document.policy },
                                    set: { save($0) }
                                )
                            ) {
                                ForEach(ResearchCollaborationPolicy.allCases, id: \.self) {
                                    policy in
                                    Text(title(policy)).tag(policy)
                                }
                            }
                            .pickerStyle(.inline)
                            .accessibilityIdentifier(
                                "scholium.researchGuidance.collaboration.policy"
                            )

                            Text(detail(snapshot.document.policy))
                                .font(ScholiumTypography.interface(.body))
                                .scholiumForeground(.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if isWorking {
                        ScholiumContentStateView(
                            "Loading Agent Access Policy…",
                            indicator: .progress,
                            placement: .leading,
                            density: .compact
                        )
                    } else {
                        ScholiumContentStateView(
                            "Agent Access Unavailable",
                            detail: Text(errorMessage ?? "Open a complete Triptych."),
                            indicator: .symbol("lock.slash", role: .attention),
                            placement: .leading,
                            density: .compact
                        )
                    }
                }

            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSettingsPaneSurface()
        .disabled(
            isWorking
                || loadedTriptychID != settingsModel.activeTriptychServicesID
        )
        .task(id: settingsModel.activeTriptychServicesID) { await reload() }
        .accessibilityIdentifier("scholium.researchGuidance.agentAccess")
        .alert("Could Not Update Agent Access", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Dismiss", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func title(_ policy: ResearchCollaborationPolicy) -> String {
        switch policy {
        case .askEveryTime:
            localizedInterfaceString("Ask Me Every Time")
        case .askOnlyForWorks:
            localizedInterfaceString("Ask Me Only for Works")
        case .fullAccess:
            localizedInterfaceString("Full Triptych Access")
        }
    }

    private func detail(_ policy: ResearchCollaborationPolicy) -> String {
        switch policy {
        case .askEveryTime:
            localizedInterfaceString(
                "Ask once for each proposed extension set. The researcher may allow a subset; approved members remain valid only for the current Run."
            )
        case .askOnlyForWorks:
            localizedInterfaceString(
                "Analysis and Topic members may be added after all machine checks; any Work member still requires one explicit decision."
            )
        case .fullAccess:
            localizedInterfaceString(
                "Allow machine-validated extensions within this Triptych without another sheet. Every actual write still requires a nonreusable capability bound to the complete approved set and that document's expected revision."
            )
        }
    }

    @MainActor
    private func reload() async {
        guard let triptychID = settingsModel.activeTriptychServicesID else {
            loadedTriptychID = nil
            snapshot = nil
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let loaded = try await settingsModel.collaborationPolicy()
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            snapshot = loaded
            loadedTriptychID = triptychID
            errorMessage = nil
        } catch {
            guard triptychID == settingsModel.activeTriptychServicesID else { return }
            snapshot = nil
            loadedTriptychID = triptychID
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ policy: ResearchCollaborationPolicy) {
        guard let snapshot else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                self.snapshot = try await settingsModel.saveCollaborationPolicy(
                    ResearchCollaborationPolicyDocument(
                        triptychID: snapshot.document.triptychID,
                        policy: policy
                    ),
                    expectedRevision: snapshot.revision
                )
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
