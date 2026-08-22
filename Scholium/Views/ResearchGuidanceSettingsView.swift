import ScholiumContracts
import SwiftUI

enum ResearchGuidanceCategory: String, CaseIterable, Identifiable {
    case methodsPractices = "Methods & Practices"
    case actionProfiles = "Action Profiles"
    case agentAccess = "Agent Access"
    case externalToolsCitations = "External Tools & Citations"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .methodsPractices:
            LocalizedStringResource("Methods & Practices", table: "Localizable", bundle: .module)
        case .actionProfiles:
            LocalizedStringResource("Action Profiles", table: "Localizable", bundle: .module)
        case .agentAccess:
            LocalizedStringResource("Agent Access", table: "Localizable", bundle: .module)
        case .externalToolsCitations:
            LocalizedStringResource("External Tools & Citations", table: "Localizable", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .methodsPractices: "text.book.closed"
        case .actionProfiles: "list.bullet.rectangle"
        case .agentAccess: "lock.shield"
        case .externalToolsCitations: "link"
        }
    }
}

struct ResearchGuidanceSettingsView: View {
    let category: ResearchGuidanceCategory

    var body: some View {
        Group {
            switch category {
            case .methodsPractices:
                MethodsPracticesSettingsView()
            case .actionProfiles:
                ActionProfilesSettingsView()
            case .agentAccess:
                ResearchPermissionSettingsView()
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
    case .manuscript:
        ScholiumL10n.localized(LocalizedStringResource(
            "Manuscript", table: "Localizable", bundle: .module
        ))
    default: actionID.rawValue.replacingOccurrences(of: "-", with: " ").capitalized
    }
}

func localizedInterfaceString(
    _ keyAndValue: String.LocalizationValue
) -> String {
    ScholiumL10n.string(keyAndValue)
}
