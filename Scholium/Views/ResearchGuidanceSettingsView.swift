import ScholiumContracts
import SwiftUI

enum ResearchGuidanceCategory: String, CaseIterable, Identifiable {
    case methods = "Methods"
    case profilesPractices = "Profiles & Practices"
    case collaboration = "Collaboration"
    case sources = "Sources & Integrations"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .methods:
            LocalizedStringResource("Methods", table: "Localizable", bundle: .module)
        case .profilesPractices:
            LocalizedStringResource("Profiles & Practices", table: "Localizable", bundle: .module)
        case .collaboration:
            LocalizedStringResource("Collaboration", table: "Localizable", bundle: .module)
        case .sources:
            LocalizedStringResource("Sources & Integrations", table: "Localizable", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .methods: "text.book.closed"
        case .profilesPractices: "wrench.and.screwdriver"
        case .collaboration: "lock.shield"
        case .sources: "link"
        }
    }
}

struct ResearchGuidanceSettingsView: View {
    let category: ResearchGuidanceCategory

    var body: some View {
        Group {
            switch category {
            case .methods:
                ResearchMethodsSettingsView()
            case .profilesPractices:
                ProfilesPracticesSettingsView()
            case .collaboration:
                ResearchPermissionSettingsView()
            case .sources:
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
