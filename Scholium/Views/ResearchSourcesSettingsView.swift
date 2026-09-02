import SwiftUI

struct ResearchSourcesSettingsView: View {
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
                        "Manage read-only external research tools available on this Mac.",
                        table: "Localizable",
                        bundle: .module
                    )
                )
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
