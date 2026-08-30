import SwiftUI

private struct ScholiumApparatusHeadingModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(ScholiumTypography.interface(.small, emphasis: .strong))
            .tracking(0.7)
            .scholiumForeground(.secondaryText)
    }
}

extension View {
    /// The single visual token for every Inspector and Research Record section heading.
    func scholiumApparatusHeadingStyle() -> some View {
        modifier(ScholiumApparatusHeadingModifier())
    }
}

/// The production Overview / Connect index. It owns only visual
/// selection and keyboard traversal; the surrounding window remains the mode
/// state owner.
struct ScholiumInspectorModeIndex: View {
    let selectedMode: ResearchInspectorMode
    let select: (ResearchInspectorMode) -> Void

    var body: some View {
        ScholiumSegmentedControl(
            selection: Binding(
                get: { selectedMode },
                set: { select($0) }
            ),
            options: ResearchInspectorMode.allCases.map { mode in
                ScholiumSegmentedControlOption(
                    mode,
                    title: String(localized: mode.interfaceTitleResource),
                    accessibilityIdentifier: "scholium.inspectorMode.\(mode.rawValue)"
                )
            },
            label: String(localized: "Research Inspector"),
            size: .compact,
            accessibilityIdentifier: "scholium.inspectorMode"
        )
        .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
        .frame(minHeight: ScholiumMetrics.Apparatus.headerHeight)
    }
}

/// One Inspector section with a shared heading, internal rhythm, optional
/// trailing action, and no implicit boundary. It owns presentation only;
/// feature state and actions remain with the feature that supplies its content.
struct ScholiumApparatusSection<Content: View, Trailing: View>: View {
    let title: LocalizedStringResource
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: LocalizedStringResource,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ScholiumApparatusFactValueStyle: Hashable {
    case researchContent
    case exactContent
    case revisionIdentity
}

struct ScholiumApparatusFact: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
    let monospacedDigits: Bool
    let valueStyle: ScholiumApparatusFactValueStyle

    init(
        id: String,
        label: String,
        value: String,
        monospacedDigits: Bool = false,
        valueStyle: ScholiumApparatusFactValueStyle = .researchContent
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.monospacedDigits = monospacedDigits
        self.valueStyle = valueStyle
    }
}

/// Short facts share one label column for scanning. At a genuinely narrow
/// width the complete group changes to a stacked layout; individual rows
/// never choose their own structure.
struct ScholiumApparatusFactGrid: View {
    let facts: [ScholiumApparatusFact]

    var body: some View {
        Group {
            if !visibleFacts.isEmpty {
                ViewThatFits(in: .horizontal) {
                    Grid(
                        alignment: .leading,
                        horizontalSpacing: ScholiumMetrics.Apparatus.factColumnSpacing,
                        verticalSpacing: ScholiumMetrics.Apparatus.rowSpacing
                    ) {
                        ForEach(visibleFacts) { fact in
                            GridRow(alignment: .firstTextBaseline) {
                                factLabel(fact.label)
                                    .multilineTextAlignment(.trailing)
                                    .frame(
                                        width: ScholiumMetrics.Apparatus.factLabelMinimumWidth,
                                        alignment: .trailing
                                    )
                                    .gridColumnAlignment(.trailing)
                                factValue(
                                    fact.value,
                                    monospacedDigits: fact.monospacedDigits,
                                    valueStyle: fact.valueStyle
                                )
                                .frame(
                                    minWidth: ScholiumMetrics.Apparatus.factValueMinimumWidth,
                                    idealWidth: ScholiumMetrics.Apparatus.factValueMinimumWidth,
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .gridColumnAlignment(.leading)
                            }
                        }
                    }
                    .frame(
                        minWidth: ScholiumMetrics.Apparatus.factGridMinimumWidth,
                        maxWidth: .infinity,
                        alignment: .leading
                    )

                    VStack(
                        alignment: .leading,
                        spacing: ScholiumMetrics.Apparatus.readingBlockSpacing
                    ) {
                        ForEach(visibleFacts) { fact in
                            VStack(
                                alignment: .leading,
                                spacing: ScholiumMetrics.Apparatus.longTextLabelSpacing
                            ) {
                                factLabel(fact.label)
                                factValue(
                                    fact.value,
                                    monospacedDigits: fact.monospacedDigits,
                                    valueStyle: fact.valueStyle
                                )
                                .padding(
                                    .leading,
                                    ScholiumMetrics.Apparatus.longTextIndent
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var visibleFacts: [ScholiumApparatusFact] {
        facts.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func factLabel(_ label: String) -> some View {
        Text(label)
            .font(ScholiumTypography.interface(.compact, emphasis: .strong))
            .scholiumForeground(.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func factValue(
        _ value: String,
        monospacedDigits: Bool,
        valueStyle: ScholiumApparatusFactValueStyle
    ) -> some View {
        Text(value)
            .font(factValueFont(monospacedDigits: monospacedDigits, style: valueStyle))
            .scholiumForeground(.primaryText)
            .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func factValueFont(
        monospacedDigits: Bool,
        style: ScholiumApparatusFactValueStyle
    ) -> Font {
        switch style {
        case .researchContent:
            monospacedDigits
                ? ScholiumTypography.scholarly(.body, tabularDigits: true)
                : ScholiumTypography.scholarly(.body)
        case .exactContent:
            ScholiumTypography.exact(.body)
        case .revisionIdentity:
            ScholiumTypography.exact(.small)
        }
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
                .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                .scholiumForeground(.secondaryText)
            Text(text)
                .font(
                    monospacedDigits
                        ? ScholiumTypography.scholarly(.body, tabularDigits: true)
                        : ScholiumTypography.scholarly(.body)
                )
                .scholiumForeground(.primaryText)
                .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, ScholiumMetrics.Apparatus.longTextIndent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared visual content for every full-row Inspector operation. Feature-owned
/// buttons retain their own routing and focus behavior around this content.
struct ScholiumApparatusActionRowContent: View {
    let title: Text
    let systemImage: String
    let detail: Text?
    let trailingState: Text?
    let showsProgress: Bool
    let showsChevron: Bool

    init(
        title: Text,
        systemImage: String,
        detail: Text? = nil,
        trailingState: Text? = nil,
        showsProgress: Bool = false,
        showsChevron: Bool = true
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.trailingState = trailingState
        self.showsProgress = showsProgress
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: ScholiumMetrics.Apparatus.iconToTextSpacing
        ) {
            Group {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(ScholiumTypography.interface(
                            .compact,
                            emphasis: .strong
                        ))
                        .scholiumForeground(.secondaryText)
                }
            }
            .frame(width: ScholiumMetrics.Apparatus.iconColumnWidth)
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.actionCopySpacing
            ) {
                title
                    .font(ScholiumTypography.interface(.sectionTitle))
                    .scholiumForeground(.primaryText)
                if let detail {
                    detail
                        .font(ScholiumTypography.scholarly(.body))
                        .scholiumForeground(.secondaryText)
                        .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trailingState {
                trailingState
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .scholiumForeground(.mutedText)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// An actionable Inspector section heading. The heading remains an interface
/// label while the complete row is one native Button; the section content
/// stays ordinary selectable/readable material rather than becoming part of
/// the control.
struct ScholiumApparatusSectionHeaderButton: View {
    let title: LocalizedStringResource
    let actionLabel: LocalizedStringResource
    let systemImage: String
    let accessibilityIdentifier: String
    let action: () -> Void

    init(
        _ title: LocalizedStringResource,
        actionLabel: LocalizedStringResource,
        systemImage: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.actionLabel = actionLabel
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                Text(title)
                    .scholiumApparatusHeadingStyle()
                Spacer(minLength: ScholiumMetrics.Apparatus.iconToTextSpacing)
                Image(systemName: systemImage)
                    .font(ScholiumTypography.interface(.small, emphasis: .medium))
                    .scholiumForeground(.mutedText)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(
            ScholiumQuietRowButtonStyle(
                minimumHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                verticalInset: 0
            )
        )
        .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
        .help(actionLabel)
        .accessibilityLabel(Text(actionLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

/// A native full-row disclosure heading shared by Inspector and sheet
/// progressive disclosure. The heading, indicator, trailing value, and empty
/// row space form one Button while the disclosed content remains outside the
/// control for ordinary reading and interaction.
struct ScholiumDisclosureHeaderButton<Label: View, Trailing: View>: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion

    let isExpanded: Bool
    let accessibilityLabel: Text
    let accessibilityIdentifier: String
    let minimumHeight: CGFloat
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @ViewBuilder let trailing: () -> Trailing

    init(
        isExpanded: Bool,
        accessibilityLabel: Text,
        accessibilityIdentifier: String,
        minimumHeight: CGFloat = ScholiumMetrics.Accessibility.preferredCustomTarget,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.isExpanded = isExpanded
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.minimumHeight = minimumHeight
        self.action = action
        self.label = label
        self.trailing = trailing
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                Image(systemName: "chevron.right")
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .scholiumForeground(.mutedText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(
                        ScholiumMotion.disclosure(reduceMotion: reduceMotion),
                        value: isExpanded
                    )
                    .accessibilityHidden(true)
                label()
                Spacer(minLength: ScholiumMetrics.Apparatus.iconToTextSpacing)
                trailing()
            }
        }
        .buttonStyle(
            ScholiumQuietRowButtonStyle(
                minimumHeight: minimumHeight,
                verticalInset: 0
            )
        )
        .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

extension ScholiumDisclosureHeaderButton where Trailing == EmptyView {
    init(
        isExpanded: Bool,
        accessibilityLabel: Text,
        accessibilityIdentifier: String,
        minimumHeight: CGFloat = ScholiumMetrics.Accessibility.preferredCustomTarget,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.init(
            isExpanded: isExpanded,
            accessibilityLabel: accessibilityLabel,
            accessibilityIdentifier: accessibilityIdentifier,
            minimumHeight: minimumHeight,
            action: action,
            label: label,
            trailing: { EmptyView() }
        )
    }
}

extension ScholiumApparatusSection where Trailing == EmptyView {
    init(
        _ title: LocalizedStringResource,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title,
            content: content,
            trailing: { EmptyView() }
        )
    }
}

enum ScholiumApparatusStateDensity: Equatable {
    case line
    case block
}

/// Compact state feedback shared by Overview, Connect, and Actions. Ordinary
/// status stays on one visual line when possible; diagnostic and recovery copy
/// remains fully readable and never receives an artificial line limit.
struct ScholiumApparatusStateView<Actions: View>: View {
    let title: LocalizedStringResource
    let detail: String?
    let systemImage: String
    let showsProgress: Bool
    let density: ScholiumApparatusStateDensity
    @ViewBuilder let actions: () -> Actions

    init(
        _ title: LocalizedStringResource,
        detail: String? = nil,
        systemImage: String,
        showsProgress: Bool = false,
        density: ScholiumApparatusStateDensity = .line,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.showsProgress = showsProgress
        self.density = density
        self.actions = actions
    }

    var body: some View {
        ScholiumApparatusRow(
            leading: {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(ScholiumTypography.interface(.compact, emphasis: .medium))
                        .scholiumForeground(.secondaryText)
                        .accessibilityHidden(true)
                }
            },
            content: {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.actionCopySpacing
                ) {
                    Text(title)
                        .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                        .scholiumForeground(.primaryText)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(ScholiumTypography.scholarly(.body))
                            .scholiumForeground(.secondaryText)
                            .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if density == .block {
                        actions()
                            .padding(.top, ScholiumMetrics.Apparatus.actionCopySpacing)
                    }
                }
            },
            trailing: {
                if density == .line {
                    actions()
                }
            }
        )
        .accessibilityElement(children: .contain)
    }
}

extension ScholiumApparatusStateView where Actions == EmptyView {
    init(
        _ title: LocalizedStringResource,
        detail: String? = nil,
        systemImage: String,
        showsProgress: Bool = false,
        density: ScholiumApparatusStateDensity = .line
    ) {
        self.init(
            title,
            detail: detail,
            systemImage: systemImage,
            showsProgress: showsProgress,
            density: density,
            actions: { EmptyView() }
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
