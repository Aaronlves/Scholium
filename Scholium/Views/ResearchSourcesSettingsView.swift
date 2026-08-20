import ScholiumContracts
import SwiftUI

struct ResearchSourcesSettingsView: View {
    @State private var citationStatus: ResearchCitationMethodStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "Sources & Integrations",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Manage machine-local CLI and Zotero access plus the Triptych citation style.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                AgentCLISettingsView()
                Divider()
                ZoteroSettingsView()
                Divider()
                ResearchCitationMethodSettingsView { citationStatus = $0 }
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.researchGuidance.sources")
    }
}
