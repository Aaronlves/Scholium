import ScholiumContracts
import SwiftUI

enum ResearchGuidanceCategory: String, CaseIterable, Identifiable {
    case methods = "Methods"
    case researcherSkills = "Researcher Skills"
    case permissions = "Permissions"
    case sources = "Sources & Integrations"
    case recovery = "Recovery & Technical"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .methods:
            LocalizedStringResource("Methods", table: "Localizable", bundle: .module)
        case .researcherSkills:
            LocalizedStringResource("Researcher Skills", table: "Localizable", bundle: .module)
        case .permissions:
            LocalizedStringResource("Permissions", table: "Localizable", bundle: .module)
        case .sources:
            LocalizedStringResource("Sources & Integrations", table: "Localizable", bundle: .module)
        case .recovery:
            LocalizedStringResource("Recovery & Technical", table: "Localizable", bundle: .module)
        }
    }

    var symbol: String {
        switch self {
        case .methods: "text.book.closed"
        case .researcherSkills: "wrench.and.screwdriver"
        case .permissions: "lock.shield"
        case .sources: "link"
        case .recovery: "arrow.counterclockwise"
        }
    }
}

struct ResearcherSkillDraftKey: Hashable {
    let triptychID: UUID
    let packageID: String
}

struct ResearchActionProfileDraftKey: Hashable {
    let triptychID: UUID
    let packageID: String
    let actionID: ResearchActionID
}

@MainActor
final class ResearchGuidanceDraftStore: ObservableObject {
    @Published private var skillDraftSources: [ResearcherSkillDraftKey: String] = [:]
    private var savedSkillSources: [ResearcherSkillDraftKey: String] = [:]
    @Published private var profileDrafts: [
        ResearchActionProfileDraftKey: ResearchActionProfileDraft
    ] = [:]
    private var savedProfileDrafts: [
        ResearchActionProfileDraftKey: ResearchActionProfileDraft
    ] = [:]

    func synchronizeSkills(
        triptychID: UUID,
        skills: [ResearchSkillPackage]
    ) {
        for skill in skills {
            let key = ResearcherSkillDraftKey(
                triptychID: triptychID,
                packageID: skill.id
            )
            if let saved = savedSkillSources[key], skillDraftSources[key] != saved {
                // Preserve the researcher's draft while making Discard return
                // to the latest source now visible from the Triptych.
                savedSkillSources[key] = skill.source
            } else {
                savedSkillSources[key] = skill.source
                skillDraftSources[key] = skill.source
            }
        }
    }

    func source(
        for skill: ResearchSkillPackage,
        triptychID: UUID
    ) -> String {
        skillDraftSources[ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: skill.id
        )] ?? skill.source
    }

    func updateSource(
        _ source: String,
        triptychID: UUID,
        packageID: String
    ) {
        skillDraftSources[ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: packageID
        )] = source
    }

    func hasUnsavedChanges(
        for skill: ResearchSkillPackage,
        triptychID: UUID
    ) -> Bool {
        let key = ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: skill.id
        )
        return source(for: skill, triptychID: triptychID)
            != (savedSkillSources[key] ?? skill.source)
    }

    func discardChanges(
        for skill: ResearchSkillPackage,
        triptychID: UUID
    ) {
        let key = ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: skill.id
        )
        skillDraftSources[key] = savedSkillSources[key] ?? skill.source
    }

    func markSkillSaved(
        _ source: String,
        triptychID: UUID,
        packageID: String
    ) {
        let key = ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: packageID
        )
        savedSkillSources[key] = source
        skillDraftSources[key] = source
    }

    func removeSkill(triptychID: UUID, packageID: String) {
        let key = ResearcherSkillDraftKey(
            triptychID: triptychID,
            packageID: packageID
        )
        savedSkillSources.removeValue(forKey: key)
        skillDraftSources.removeValue(forKey: key)
    }

    func synchronizeProfile(
        key: ResearchActionProfileDraftKey,
        draft: ResearchActionProfileDraft
    ) {
        if let saved = savedProfileDrafts[key], profileDrafts[key] != saved {
            savedProfileDrafts[key] = draft
        } else {
            savedProfileDrafts[key] = draft
            profileDrafts[key] = draft
        }
    }

    func profileDraft(
        for key: ResearchActionProfileDraftKey,
        fallback: ResearchActionProfileDraft
    ) -> ResearchActionProfileDraft {
        profileDrafts[key] ?? fallback
    }

    func updateProfileDraft(
        _ draft: ResearchActionProfileDraft,
        for key: ResearchActionProfileDraftKey
    ) {
        profileDrafts[key] = draft
    }

    func profileHasUnsavedChanges(
        for key: ResearchActionProfileDraftKey,
        fallback: ResearchActionProfileDraft
    ) -> Bool {
        profileDraft(for: key, fallback: fallback)
            != (savedProfileDrafts[key] ?? fallback)
    }

    func discardProfileChanges(
        for key: ResearchActionProfileDraftKey,
        fallback: ResearchActionProfileDraft
    ) {
        profileDrafts[key] = savedProfileDrafts[key] ?? fallback
    }

    func markProfileSaved(
        _ draft: ResearchActionProfileDraft,
        for key: ResearchActionProfileDraftKey
    ) {
        savedProfileDrafts[key] = draft
        profileDrafts[key] = draft
    }

    func removeProfile(for key: ResearchActionProfileDraftKey) {
        savedProfileDrafts.removeValue(forKey: key)
        profileDrafts.removeValue(forKey: key)
    }
}

struct ResearchGuidanceSettingsView: View {
    @AppStorage("scholium.settings.researchGuidanceCategory")
    private var persistedCategory = ResearchGuidanceCategory.methods.rawValue
    @State private var category: ResearchGuidanceCategory = .methods
    @ObservedObject var draftStore: ResearchGuidanceDraftStore

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
                case .researcherSkills:
                    ResearcherSkillsSettingsView(draftStore: draftStore)
                case .permissions:
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

extension ResearchActionProfileBinding {
    func replacingShowInActions(_ showInActions: Bool) throws -> Self {
        try ResearchActionProfileBinding(
            packageID: packageID,
            profile: ResearchActionProfile(
                definition: profile.definition,
                buttonName: profile.buttonName,
                order: profile.order,
                applicableRoles: profile.applicableRoles,
                showInActions: showInActions,
                modules: profile.modules,
                sourceRequirement: profile.sourceRequirement,
                capabilities: profile.capabilities,
                feedbackRequirement: profile.feedbackRequirement
            )
        )
    }

    func replacingOrder(_ order: Int) throws -> Self {
        try ResearchActionProfileBinding(
            packageID: packageID,
            profile: ResearchActionProfile(
                definition: profile.definition,
                buttonName: profile.buttonName,
                order: order,
                applicableRoles: profile.applicableRoles,
                showInActions: profile.showInActions,
                modules: profile.modules,
                sourceRequirement: profile.sourceRequirement,
                capabilities: profile.capabilities,
                feedbackRequirement: profile.feedbackRequirement
            )
        )
    }
}
