import SwiftUI

/// The shared presentation boundary for Scholium's macOS Settings window.
/// Native controls retain their platform behavior; this layer supplies only
/// the editorial plane, hierarchy, spacing, and semantic colors shared by
/// every Settings pane.
@MainActor
func settingsTitle(
    _ title: LocalizedStringResource,
    detail: LocalizedStringResource
) -> some View {
    VStack(
        alignment: .leading,
        spacing: ScholiumMetrics.ResearchGuidance.titleDetailSpacing
    ) {
        Text(title)
            .font(ScholiumTypography.interface(.primaryTitle))
            .scholiumForeground(.primaryText)
            .accessibilityAddTraits(.isHeader)
        Text(detail)
            .font(ScholiumTypography.interface(.body))
            .scholiumForeground(.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(
        maxWidth: ScholiumMetrics.Settings.headerMaximumWidth,
        alignment: .leading
    )
    .accessibilityElement(children: .contain)
}

@MainActor
func settingsSectionTitle(
    _ title: LocalizedStringResource
) -> some View {
    Text(title)
        .font(ScholiumTypography.interface(.sectionTitle))
        .scholiumForeground(.primaryText)
        .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
        .accessibilityAddTraits(.isHeader)
}

@MainActor
func settingsEditorSection<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
        settingsSectionTitle(title)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

@MainActor
func researchSettingsSection<Content: View>(
    _ title: LocalizedStringResource,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
        settingsSectionTitle(title)
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

@MainActor
func researchSettingsCollectionRow<Content: View, Actions: View>(
    @ViewBuilder content: () -> Content,
    @ViewBuilder actions: () -> Actions
) -> some View {
    HStack(
        alignment: .top,
        spacing: ScholiumMetrics.ResearchGuidance.collectionRowColumnSpacing
    ) {
        content()
        Spacer(minLength: ScholiumGrid.Spacing.nestedContentInset)
        actions()
    }
    .padding(
        .vertical,
        ScholiumMetrics.ResearchGuidance.collectionRowVerticalInset
    )
}

private struct ScholiumSettingsPaneSurface: ViewModifier {
    let role: ScholiumColorRole

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(role.color)
    }
}

private struct ScholiumSettingsFormPresentation: ViewModifier {
    func body(content: Content) -> some View {
        ScrollView {
            content
                .formStyle(.columns)
                .padding(
                    .horizontal,
                    ScholiumMetrics.Settings.editorContentInset
                )
                .padding(
                    .vertical,
                    ScholiumMetrics.Settings.sectionSpacing
                )
                .frame(
                    maxWidth: ScholiumMetrics.Settings.formMaximumWidth,
                    alignment: .topLeading
                )
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .scholiumSettingsPaneSurface()
    }
}

extension View {
    func scholiumSettingsPaneSurface(
        _ role: ScholiumColorRole = .surfaceBackground
    ) -> some View {
        modifier(ScholiumSettingsPaneSurface(role: role))
    }

    func scholiumSettingsForm() -> some View {
        modifier(ScholiumSettingsFormPresentation())
    }
}
