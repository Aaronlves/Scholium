import ScholiumContracts
import SwiftUI

enum ResearchGuidanceCategory: String, CaseIterable, Identifiable {
    case skills = "Skills"
    case actionProfiles = "Action Profiles"
    case externalToolsCitations = "External Tools & Citations"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .skills:
            LocalizedStringResource("Skills", table: "Localizable", bundle: .module)
        case .actionProfiles:
            LocalizedStringResource("Action Profiles", table: "Localizable", bundle: .module)
        case .externalToolsCitations:
            LocalizedStringResource("External Tools & Citations", table: "Localizable", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .skills: "text.book.closed"
        case .actionProfiles: "list.bullet.rectangle"
        case .externalToolsCitations: "link"
        }
    }
}

struct ResearchGuidanceSettingsView: View {
    let category: ResearchGuidanceCategory

    var body: some View {
        Group {
            switch category {
            case .skills:
                ResearchMethodsSettingsView()
            case .actionProfiles:
                ActionProfilesSettingsView()
            case .externalToolsCitations:
                ResearchSourcesSettingsView()
            }
        }
        .scholiumSettingsPaneSurface()
        .accessibilityIdentifier("scholium.researchGuidance.detail")
    }
}

func actionTitle(_ actionID: ResearchActionID) -> String {
    switch actionID {
    case .discuss:
        ScholiumL10n.localized(LocalizedStringResource(
            "Discuss", table: "Localizable", bundle: .module
        ))
    case .analyze:
        ScholiumL10n.localized(LocalizedStringResource(
            "Analyze", table: "Localizable", bundle: .module
        ))
    case .synthesize:
        ScholiumL10n.localized(LocalizedStringResource(
            "Synthesize", table: "Localizable", bundle: .module
        ))
    case .write:
        ScholiumL10n.localized(LocalizedStringResource(
            "Write", table: "Localizable", bundle: .module
        ))
    case .critique:
        ScholiumL10n.localized(LocalizedStringResource(
            "Critique", table: "Localizable", bundle: .module
        ))
    case .checkFidelity:
        ScholiumL10n.localized(LocalizedStringResource(
            "Check Fidelity", table: "Localizable", bundle: .module
        ))
    }
}

func localizedInterfaceString(
    _ keyAndValue: String.LocalizationValue
) -> String {
    ScholiumL10n.string(keyAndValue)
}
