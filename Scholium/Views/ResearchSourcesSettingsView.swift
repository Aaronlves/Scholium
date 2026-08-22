import ScholiumContracts
import SwiftUI

struct ResearchSourcesSettingsView: View {
    @State private var citationStatus: ResearchCitationMethodStatus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                settingsTitle(
                    LocalizedStringResource(
                        "External Tools & Citations",
                        table: "Localizable",
                        bundle: .module
                    ),
                    detail: LocalizedStringResource(
                        "Manage the citation style for this Triptych and external tools available on this Mac.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                ResearchCitationMethodSettingsView { citationStatus = $0 }
                Divider()
                AgentCLISettingsView()
                Divider()
                ZoteroSettingsView()
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.researchGuidance.externalToolsCitations")
    }
}
