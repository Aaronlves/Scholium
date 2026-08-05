import ScholiumContracts
import SwiftUI

enum ResearchGuidanceCategory: String, CaseIterable, Identifiable {
    case methods = "Methods"
    case profilesPractices = "Profiles & Practices"
    case collaboration = "Collaboration"
    case sources = "Sources & Integrations"
    case recovery = "Recovery & Technical"

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
        case .recovery:
            LocalizedStringResource("Recovery & Technical", table: "Localizable", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .methods: "text.book.closed"
        case .profilesPractices: "wrench.and.screwdriver"
        case .collaboration: "lock.shield"
        case .sources: "link"
        case .recovery: "arrow.counterclockwise"
        }
    }
}

struct ResearchGuidanceSettingsView: View {
    @AppStorage("scholium.settings.researchGuidanceCategory")
    private var persistedCategory = ResearchGuidanceCategory.methods.rawValue
    @State private var category: ResearchGuidanceCategory = .methods

    var body: some View {
        HSplitView {
            List(ResearchGuidanceCategory.allCases, selection: $category) { item in
                Label {
                    Text(item.localizedTitle)
                } icon: {
                    Image(systemName: item.symbol)
                }
                    .tag(item)
                    .accessibilityIdentifier(
                        "scholium.researchGuidance.category.\(item.id)"
                    )
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 240)
            .accessibilityIdentifier("scholium.researchGuidance.categoryList")

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
                case .recovery:
                    ResearchRecoverySettingsView()
                }
            }
            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            category = ResearchGuidanceCategory(rawValue: persistedCategory) ?? .methods
        }
        .onChange(of: category) { _, value in
            persistedCategory = value.rawValue
        }
    }
}

func settingsTitle(
    _ title: LocalizedStringResource,
    detail: LocalizedStringResource
) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
        Text(detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

func researchSettingsSection<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
