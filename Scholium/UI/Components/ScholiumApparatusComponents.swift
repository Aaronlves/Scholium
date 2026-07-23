import SwiftUI

private struct ScholiumApparatusHeadingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(ScholiumInterfaceTypography.apparatusLabel)
            .tracking(0.7)
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
    }
}

extension View {
    /// The single visual token for every Inspector section and group heading.
    func scholiumApparatusHeadingStyle() -> some View {
        modifier(ScholiumApparatusHeadingModifier())
    }
}

/// One Inspector section with a shared heading, internal rhythm, optional
/// trailing action, and optional structural rule. It owns presentation only;
/// feature state and actions remain with the feature that supplies its content.
struct ScholiumApparatusSection<Content: View, Trailing: View>: View {
    let title: LocalizedStringResource
    let showsDivider: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: LocalizedStringResource,
        showsDivider: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.showsDivider = showsDivider
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 0
        ) {
            HStack(spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                Text(title)
                    .scholiumApparatusHeadingStyle()
                Spacer(minLength: ScholiumMetrics.Apparatus.iconToTextSpacing)
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, ScholiumMetrics.Apparatus.sectionContentSpacing)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)

            if showsDivider {
                ScholiumStructuralRule()
                    .padding(.top, ScholiumMetrics.Apparatus.contentToRuleSpacing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScholiumApparatusFact: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
    let monospacedDigits: Bool

    init(
        id: String,
        label: String,
        value: String,
        monospacedDigits: Bool = false
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.monospacedDigits = monospacedDigits
    }
}

/// Short facts share one label column for scanning. At a genuinely narrow
/// proposal the complete group changes to a stacked layout; individual rows
/// never choose their own structure.
struct ScholiumApparatusFactGrid: View {
    let facts: [ScholiumApparatusFact]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(
                alignment: .leading,
                horizontalSpacing: ScholiumGrid.Spacing.inlineControlGap,
                verticalSpacing: ScholiumMetrics.Apparatus.rowSpacing
            ) {
                ForEach(facts) { fact in
                    GridRow(alignment: .firstTextBaseline) {
                        factLabel(fact.label)
                            .frame(
                                width: ScholiumMetrics.Apparatus.factLabelWidth,
                                alignment: .leading
                            )
                        factValue(fact.value, monospacedDigits: fact.monospacedDigits)
                    }
                }
            }
            .frame(
                minWidth: ScholiumMetrics.Apparatus.factGridMinimumWidth,
                maxWidth: .infinity,
                alignment: .leading
            )

            VStack(alignment: .leading, spacing: ScholiumMetrics.Apparatus.readingBlockSpacing) {
                ForEach(facts) { fact in
                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.Apparatus.longTextLabelSpacing
                    ) {
                        factLabel(fact.label)
                        factValue(fact.value, monospacedDigits: fact.monospacedDigits)
                            .padding(.leading, ScholiumMetrics.Apparatus.longTextIndent)
                    }
                }
            }
        }
    }

    private func factLabel(_ label: String) -> some View {
        Text(label)
            .font(ScholiumInterfaceTypography.apparatusBody.weight(.semibold))
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func factValue(
        _ value: String,
        monospacedDigits: Bool
    ) -> some View {
        Text(value)
            .font(
                monospacedDigits
                    ? ScholiumInterfaceTypography.apparatusResearchContent.monospacedDigit()
                    : ScholiumInterfaceTypography.apparatusResearchContent
            )
            .foregroundStyle(ScholiumColorRole.primaryText.color)
            .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Scope and Limitations always use a reading block, independent of their
/// current character count, so information hierarchy remains stable.
struct ScholiumApparatusReadingBlock: View {
    let label: String
    let text: String
    var monospacedDigits = false

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Apparatus.longTextLabelSpacing
        ) {
            Text(label)
                .font(ScholiumInterfaceTypography.apparatusBody.weight(.semibold))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            Text(text)
                .font(
                    monospacedDigits
                        ? ScholiumInterfaceTypography.apparatusResearchContent.monospacedDigit()
                        : ScholiumInterfaceTypography.apparatusResearchContent
                )
                .foregroundStyle(ScholiumColorRole.primaryText.color)
                .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, ScholiumMetrics.Apparatus.longTextIndent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Native full-row Inspector operation. Shape, focus, and the trailing
/// affordance identify actionability without relying on link-blue text.
struct ScholiumApparatusActionButton: View {
    let title: LocalizedStringResource
    let systemImage: String
    let detail: String?
    let showsChevron: Bool
    let action: () -> Void

    @State private var isHovering = false

    init(
        _ title: LocalizedStringResource,
        systemImage: String,
        detail: String? = nil,
        showsChevron: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.showsChevron = showsChevron
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .frame(width: ScholiumMetrics.Apparatus.iconColumnWidth)
                    .accessibilityHidden(true)

                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.actionCopySpacing
                ) {
                    Text(title)
                        .font(ScholiumInterfaceTypography.apparatusActionTitle)
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                            .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsChevron {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .padding(.vertical, ScholiumMetrics.Apparatus.actionRowVerticalInset)
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                isHovering
                    ? ScholiumColorRole.raisedSurfaceBackground.color
                    : Color.clear,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityHint(detail ?? "")
    }
}

extension ScholiumApparatusSection where Trailing == EmptyView {
    init(
        _ title: LocalizedStringResource,
        showsDivider: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title,
            showsDivider: showsDivider,
            content: content,
            trailing: { EmptyView() }
        )
    }
}

/// One aligned Inspector row. Symbols occupy a fixed column, text receives the
/// flexible width, and any trailing action stays on the shared content edge.
/// This is a scan/alignment component, not a generic application row.
struct ScholiumApparatusRow<Leading: View, Content: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.leading = leading
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: ScholiumMetrics.Apparatus.iconToTextSpacing
        ) {
            leading()
                .frame(
                    width: ScholiumMetrics.Apparatus.iconColumnWidth,
                    alignment: .center
                )

            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .frame(
            minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
            alignment: .leading
        )
    }
}

extension ScholiumApparatusRow where Trailing == EmptyView {
    init(
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            leading: leading,
            content: content,
            trailing: { EmptyView() }
        )
    }
}
