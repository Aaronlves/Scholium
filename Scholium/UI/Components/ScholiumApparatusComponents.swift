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

/// The compact relationship vocabulary used by Connect. Directional marks are
/// mirrored pairs; incompatibility and neutral connection are deliberately
/// undirected. The glyph is always decorative because the row exposes the
/// complete relationship in text, pointer help, and accessibility.
enum ScholiumConnectionGlyphKind: Hashable, Sendable {
    case supports
    case supportedBy
    case opposes
    case opposedBy
    case incompatible
    case neutral

    fileprivate var mirrorsBasePath: Bool {
        switch self {
        case .supportedBy, .opposedBy: true
        default: false
        }
    }

    fileprivate var isDirectional: Bool {
        switch self {
        case .supports, .supportedBy, .opposes, .opposedBy: true
        case .incompatible, .neutral: false
        }
    }
}

struct ScholiumConnectionGlyph: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let kind: ScholiumConnectionGlyphKind

    var body: some View {
        ScholiumConnectionGlyphShape(kind: kind)
            .stroke(
                ScholiumColorRole.mutedText.color,
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .scaleEffect(x: mirrorsHorizontally ? -1 : 1, y: 1)
            .accessibilityHidden(true)
    }

    private var mirrorsHorizontally: Bool {
        kind.mirrorsBasePath != (kind.isDirectional && layoutDirection == .rightToLeft)
    }
}

private struct ScholiumConnectionGlyphShape: Shape {
    let kind: ScholiumConnectionGlyphKind

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 20
        let scaleY = rect.height / 20
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * scaleX, y: y * scaleY)
        }

        var path = Path()
        switch kind {
        case .supports, .supportedBy:
            path.move(to: point(3.1, 10.1))
            path.addCurve(
                to: point(16.9, 10.2),
                control1: point(7.1, 9.9),
                control2: point(11.8, 10.1)
            )
            path.move(to: point(4.4, 14.5))
            path.addCurve(
                to: point(10.5, 10),
                control1: point(6.2, 11.9),
                control2: point(8.1, 10.5)
            )
        case .opposes, .opposedBy:
            path.move(to: point(3.1, 10.1))
            path.addCurve(
                to: point(13.8, 10.2),
                control1: point(6.9, 9.9),
                control2: point(10.5, 10.1)
            )
            path.move(to: point(14.2, 5.7))
            path.addCurve(
                to: point(14.2, 14.3),
                control1: point(13.7, 8.5),
                control2: point(13.7, 11.4)
            )
        case .incompatible:
            path.move(to: point(3.1, 10.1))
            path.addCurve(
                to: point(9.2, 10.2),
                control1: point(5.6, 9.9),
                control2: point(7.6, 10)
            )
            path.addLine(to: point(10, 7.1))
            path.move(to: point(16.9, 10.1))
            path.addCurve(
                to: point(10.8, 10.2),
                control1: point(14.4, 9.9),
                control2: point(12.4, 10)
            )
            path.addLine(to: point(10, 13.1))
        case .neutral:
            path.move(to: point(5.4, 10.4))
            path.addCurve(
                to: point(14.6, 10.4),
                control1: point(8, 9.4),
                control2: point(12, 9.4)
            )
            path.addEllipse(in: CGRect(x: 2.4 * scaleX, y: 9 * scaleY, width: 2.8 * scaleX, height: 2.8 * scaleY))
            path.addEllipse(in: CGRect(x: 14.8 * scaleX, y: 9 * scaleY, width: 2.8 * scaleX, height: 2.8 * scaleY))
        }
        return path
    }
}

/// The production Overview / Connect / Actions index. It owns only visual
/// selection and keyboard traversal; the surrounding window remains the mode
/// state owner.
struct ScholiumInspectorModeIndex: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var focusedMode: ResearchInspectorMode?

    let selectedMode: ResearchInspectorMode
    let select: (ResearchInspectorMode) -> Void

    var body: some View {
        HStack(spacing: ScholiumMetrics.Apparatus.modeColumnSpacing) {
            ForEach(ResearchInspectorMode.allCases) { mode in
                ScholiumInspectorModeButton(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    focusedMode: $focusedMode,
                    select: { selectMode(mode) },
                    move: { moveFocus(from: mode, direction: $0) }
                )
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .padding(.horizontal, ScholiumMetrics.Apparatus.contentInset)
        .frame(minHeight: ScholiumMetrics.Apparatus.headerHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Research Inspector")
    }

    private func selectMode(_ mode: ResearchInspectorMode) {
        select(mode)
    }

    private func moveFocus(
        from mode: ResearchInspectorMode,
        direction: MoveCommandDirection
    ) {
        let modes = ResearchInspectorMode.allCases
        guard let index = modes.firstIndex(of: mode) else { return }
        let visualStep: Int
        switch direction {
        case .left:
            visualStep = layoutDirection == .leftToRight ? -1 : 1
        case .right:
            visualStep = layoutDirection == .leftToRight ? 1 : -1
        default:
            return
        }
        let nextIndex = (index + visualStep + modes.count) % modes.count
        let nextMode = modes[nextIndex]
        select(nextMode)
        focusedMode = nextMode
    }
}

private struct ScholiumInspectorModeButton: View {
    @State private var isHovering = false

    let mode: ResearchInspectorMode
    let isSelected: Bool
    let focusedMode: FocusState<ResearchInspectorMode?>.Binding
    let select: () -> Void
    let move: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: select) {
            Text(mode.interfaceTitleResource)
                .font(
                    isSelected
                        ? ScholiumInterfaceTypography.apparatusModeSelected
                        : ScholiumInterfaceTypography.apparatusMode
                )
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ScholiumMetrics.Apparatus.headerHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable()
        .focused(focusedMode, equals: mode)
        .foregroundStyle(
            isSelected || isHovering
                ? ScholiumColorRole.primaryText.color
                : ScholiumColorRole.secondaryText.color
        )
        .overlay(alignment: .bottom) {
            ScholiumEditorialIndexUnderline(
                isSelected: isSelected,
                isHovering: isHovering,
                width: ScholiumMetrics.Apparatus.selectedModeIndicatorWidth,
                height: ScholiumMetrics.Apparatus.selectedModeIndicatorHeight
            )
        }
        .onHover { isHovering = $0 }
        .onMoveCommand(perform: move)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("scholium.inspectorMode.\(mode.rawValue)")
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
                                        minWidth: ScholiumMetrics.Apparatus.factLabelMinimumWidth,
                                        alignment: .trailing
                                    )
                                    .gridColumnAlignment(.trailing)
                                factValue(
                                    fact.value,
                                    monospacedDigits: fact.monospacedDigits
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
                                    monospacedDigits: fact.monospacedDigits
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

/// Shared visual content for every full-row Inspector operation. Feature-owned
/// buttons retain their own routing and focus behavior around this content.
struct ScholiumApparatusActionRowContent: View {
    let title: Text
    let systemImage: String
    let detail: Text?
    let showsChevron: Bool

    init(
        title: Text,
        systemImage: String,
        detail: Text? = nil,
        showsChevron: Bool = true
    ) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: ScholiumMetrics.Apparatus.iconToTextSpacing
        ) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .frame(width: ScholiumMetrics.Apparatus.iconColumnWidth)
                .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.actionCopySpacing
            ) {
                title
                    .font(ScholiumInterfaceTypography.apparatusActionTitle)
                    .foregroundStyle(ScholiumColorRole.primaryText.color)
                if let detail {
                    detail
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

    @State private var isHovering = false

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
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(ScholiumQuietRowButtonStyle(
            isHovering: isHovering,
            minimumHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
            verticalInset: 0
        ))
        .padding(.horizontal, -ScholiumGrid.Spacing.inlineControlGap)
        .onHover { isHovering = $0 }
        .help(actionLabel)
        .accessibilityLabel(Text(actionLabel))
        .accessibilityIdentifier(accessibilityIdentifier)
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .accessibilityHidden(true)
                }
            },
            content: {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumMetrics.Apparatus.actionCopySpacing
                ) {
                    Text(title)
                        .font(ScholiumInterfaceTypography.apparatusBody.weight(.semibold))
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(ScholiumInterfaceTypography.apparatusResearchContent)
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
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
