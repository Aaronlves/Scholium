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
                        "Long-lived source, citation, bibliography, agent-handoff, and command-line configuration lives here. Action-specific source choice remains in the Action sheet.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
                AgentCLISettingsView()
                Divider()
                ZoteroSettingsView()
                Divider()
                ResearchCitationMethodSettingsView { citationStatus = $0 }
                Divider()
                RecommendedBibliographyMethodSettingsView()
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: 720, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("scholium.researchGuidance.sources")
    }
}
