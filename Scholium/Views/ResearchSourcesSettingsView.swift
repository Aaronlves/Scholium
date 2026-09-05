import SwiftUI

struct ResearchSourcesSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
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
