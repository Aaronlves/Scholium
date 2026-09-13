import SwiftUI

/// Fact values use semantic typography according to their display role.
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

/// Short operation facts use one readable label-and-value rhythm at every
/// supported comparison width.
struct ScholiumApparatusFactList: View {
    let facts: [ScholiumApparatusFact]

    var body: some View {
        Group {
            if !visibleFacts.isEmpty {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
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

enum ScholiumApparatusStateDensity: Equatable {
    case line
    case block
}

/// Compact state feedback shared by the Inspector panes. Ordinary status stays
/// on one visual line when possible; diagnostic and recovery copy remains fully
/// readable and never receives an artificial line limit.
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
