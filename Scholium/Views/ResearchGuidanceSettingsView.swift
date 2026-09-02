import ScholiumContracts
import SwiftUI

enum ResearchGuidanceCategory: String, CaseIterable, Identifiable {
    case agentIntegration = "Agent Integration"
    case externalToolsCitations = "External Tools & Citations"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .agentIntegration:
            LocalizedStringResource("Agent Integration", table: "Localizable", bundle: .module)
        case .externalToolsCitations:
            LocalizedStringResource("External Tools & Citations", table: "Localizable", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .agentIntegration: "point.3.connected.trianglepath.dotted"
        case .externalToolsCitations: "link"
        }
    }
}

struct ResearchGuidanceSettingsView: View {
    let category: ResearchGuidanceCategory

    var body: some View {
        Group {
            switch category {
            case .agentIntegration:
                AgentIntegrationSettingsView()
            case .externalToolsCitations:
                ResearchSourcesSettingsView()
            }
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.researchGuidance.detail")
    }
}

func localizedInterfaceString(
    _ keyAndValue: String.LocalizationValue
) -> String {
    ScholiumL10n.string(keyAndValue)
}
