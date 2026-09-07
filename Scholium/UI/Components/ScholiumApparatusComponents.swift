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
    /// The single visual token for every Inspector and provenance section heading.
    func scholiumApparatusHeadingStyle() -> some View {
        modifier(ScholiumApparatusHeadingModifier())
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

/// Inspector labels share one compact axis with their value or native editor.
/// At narrow widths, the complete field stacks.
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

/// Short source facts use the same leading reading edge as editable About
/// fields. A stacked label-and-value rhythm remains legible at every supported
/// Inspector width and avoids turning scholarly metadata into a cramped table.
struct ScholiumApparatusFactList: View {
    let facts: [ScholiumApparatusFact]

    var body: some View {
        Group {
            if !visibleFacts.isEmpty {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Properties.fieldBlockSeparation
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
            .font(ScholiumTypography.interface(.small, emphasis: .medium))
            .scholiumForeground(.mutedText)
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
        .scholiumActivationPointer()
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
