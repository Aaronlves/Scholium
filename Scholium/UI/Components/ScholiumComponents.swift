import ScholiumContracts
import SwiftUI

struct ScholiumStructuralRule: View {
    @Environment(\.scholiumReduceTransparency) private var reduceTransparency
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast

    let orientation: Axis

    init(orientation: Axis = .horizontal) {
        self.orientation = orientation
    }

    var body: some View {
        let style = ScholiumBoundaryRole.structuralDivider.style(
            increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency
        )

        Rectangle()
            .fill(
                style.colorRole.color(increasedContrast: increasedContrast)
                    .opacity(style.opacity)
            )
            .frame(
                width: orientation == .vertical ? style.lineWidth : nil,
                height: orientation == .horizontal ? style.lineWidth : nil
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum ScholiumSegmentedControlSize: Sendable {
    case regular
    case compact
}

struct ScholiumSegmentedControlOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let accessibilityIdentifier: String?

    init(
        _ value: Value,
        title: String,
        accessibilityIdentifier: String? = nil
    ) {
        self.value = value
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var id: Value { value }
}

/// The single presentation owner for horizontal, mutually exclusive local
/// choices. Feature owners retain the selected value; this component owns the
/// equal segments, quiet track, raised selection plate, pointer feedback,
/// keyboard traversal, and accessibility grouping.
struct ScholiumSegmentedControl<Value: Hashable>: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var focusedValue: Value?

    @Binding private var selection: Value
    private let options: [ScholiumSegmentedControlOption<Value>]
    private let label: String
    private let size: ScholiumSegmentedControlSize
    private let accessibilityIdentifier: String?

    init(
        selection: Binding<Value>,
        options: [ScholiumSegmentedControlOption<Value>],
        label: String,
        size: ScholiumSegmentedControlSize = .regular,
        accessibilityIdentifier: String? = nil
    ) {
        _selection = selection
        self.options = options
        self.label = label
        self.size = size
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        Group {
            if let accessibilityIdentifier {
                control.accessibilityIdentifier(accessibilityIdentifier)
            } else {
                control
            }
        }
    }

    private var control: some View {
        HStack(spacing: ScholiumMetrics.SegmentedControl.segmentSpacing) {
            ForEach(options) { option in
                if let accessibilityIdentifier = option.accessibilityIdentifier {
                    segment(for: option)
                        .accessibilityIdentifier(accessibilityIdentifier)
                } else {
                    segment(for: option)
                }
            }
        }
        .padding(ScholiumMetrics.SegmentedControl.trackInset)
        .background(
            ScholiumColorRole.surfaceBackground.color,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.segmentedControlCornerRadius,
                style: .continuous
            )
        )
        .scholiumBoundary(
            .subtleBoundary,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.segmentedControlCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityValue(Text(verbatim: selectedTitle))
    }

    private func segment(
        for option: ScholiumSegmentedControlOption<Value>
    ) -> some View {
        ScholiumSegmentButton(
            title: option.title,
            isSelected: selection == option.value,
            focusedValue: $focusedValue,
            value: option.value,
            size: size,
            select: { select(option.value) },
            move: { moveFocus(from: option.value, direction: $0) }
        )
        .frame(minWidth: 0, maxWidth: .infinity)
    }

    private var selectedTitle: String {
        options.first(where: { $0.value == selection })?.title ?? ""
    }

    private func select(_ value: Value) {
        guard selection != value else { return }
        selection = value
    }

    private func moveFocus(from value: Value, direction: MoveCommandDirection) {
        guard let index = options.firstIndex(where: { $0.value == value }) else {
            return
        }
        let visualStep: Int
        switch direction {
        case .left:
            visualStep = layoutDirection == .leftToRight ? -1 : 1
        case .right:
            visualStep = layoutDirection == .leftToRight ? 1 : -1
        default:
            return
        }
        let nextIndex = (index + visualStep + options.count) % options.count
        let nextValue = options[nextIndex].value
        selection = nextValue
        focusedValue = nextValue
    }
}

private struct ScholiumSegmentButton<Value: Hashable>: View {
    @State private var isHovering = false

    let title: String
    let isSelected: Bool
    let focusedValue: FocusState<Value?>.Binding
    let value: Value
    let size: ScholiumSegmentedControlSize
    let select: () -> Void
    let move: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: select) {
            Text(verbatim: title)
                .font(
                    size == .regular
                        ? ScholiumTypography.interface(
                            .body,
                            emphasis: isSelected ? .strong : nil
                        )
                        : ScholiumTypography.interface(
                            .compact,
                            emphasis: isSelected ? .strong : .medium
                        )
                )
                .scholiumForeground(
                    isSelected || isHovering || isFocused
                        ? .primaryText
                        : .secondaryText
                )
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, horizontalInset)
                .frame(maxWidth: .infinity, minHeight: minimumHeight)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
        }
        .scholiumActivationPointer()
        .buttonStyle(
            ScholiumSegmentButtonStyle(
                isSelected: isSelected,
                isHovering: isHovering,
                isFocused: isFocused
            )
        )
        .scholiumActivationFocus(focusedValue, equals: value)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    Task { @MainActor in
                        await Task.yield()
                        guard focusedValue.wrappedValue == value else { return }
                        focusedValue.wrappedValue = nil
                    }
                }
        )
        .onMoveCommand(perform: move)
        .scholiumHoverState { isHovering = $0 }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isFocused: Bool {
        focusedValue.wrappedValue == value
    }

    private var minimumHeight: CGFloat {
        size == .regular
            ? ScholiumMetrics.SegmentedControl.regularSegmentMinimumHeight
            : ScholiumMetrics.SegmentedControl.compactSegmentMinimumHeight
    }

    private var horizontalInset: CGFloat {
        size == .regular
            ? ScholiumMetrics.SegmentedControl.regularHorizontalInset
            : ScholiumMetrics.SegmentedControl.compactHorizontalInset
    }
}

private struct ScholiumSegmentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast

    let isSelected: Bool
    let isHovering: Bool
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                    .fill(
                        ScholiumContentInteractionSurface.selectionColor(
                            isSelected: true,
                            isHovering: isEnabled && isHovering,
                            isFocused: isEnabled && isFocused,
                            isPressed: isEnabled && configuration.isPressed,
                            increasedContrast: increasedContrast
                        )
                    )
                    .scholiumBoundary(
                        .subtleBoundary,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                    .scholiumElevation(.floatingControl)
                } else {
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                    .fill(
                        ScholiumContentInteractionSurface.color(
                            isHovering: isEnabled && isHovering,
                            isFocused: isEnabled && isFocused,
                            isPressed: isEnabled && configuration.isPressed,
                            increasedContrast: increasedContrast
                        )
                    )
                }
            }
            .opacity(isEnabled && configuration.isPressed ? 0.78 : 1)
    }
}

/// One neutral tag presentation shared by read-only About and the editable
/// Properties surface. An optional trailing symbol extends the capsule without
/// changing its height or text rhythm.
struct ScholiumTagCapsuleLabel: View {
    let text: String
    let trailingSystemImage: String?

    init(
        _ text: String,
        trailingSystemImage: String? = nil
    ) {
        self.text = text
        self.trailingSystemImage = trailingSystemImage
    }

    var body: some View {
        HStack(spacing: ScholiumMetrics.Properties.tagContentSpacing) {
            Text(text)
                .font(ScholiumTypography.interface(.small))
                .fixedSize(horizontal: false, vertical: true)
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .scholiumForeground(.secondaryText)
            }
        }
        .scholiumForeground(.primaryText)
        .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
        .padding(.vertical, ScholiumMetrics.Properties.tagVerticalInset)
        .background(
            ScholiumColorRole.raisedSurfaceBackground.color,
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(ScholiumColorRole.separator.color, lineWidth: 1)
        )
    }
}

/// A shared Properties/About group boundary. The concise visible heading and
/// spacing carry the same semantic group to sighted and assistive readers.
struct ScholiumPropertyGroup<Content: View>: View {
    let label: String
    let separatesFromPrevious: Bool
    let content: Content

    init(
        label: String,
        separatesFromPrevious: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.separatesFromPrevious = separatesFromPrevious
        self.content = content()
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Properties.fieldBlockSeparation
        ) {
            Text(verbatim: label)
                .font(ScholiumTypography.interface(.compact, emphasis: .strong))
                .scholiumForeground(.secondaryText)
                .accessibilityHeading(.h3)
                .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
        .padding(
            .top,
            separatesFromPrevious
                ? ScholiumMetrics.Properties.semanticGroupSeparation
                : 0
        )
        .accessibilityElement(children: .contain)
    }
}

/// The single presentation owner for matching icon controls in a content-owned
/// header. Its native Button or Menu child owns Liquid Glass interaction and
/// accessibility semantics; this component preserves the exact 28pt target,
/// Scholium ink, visibility, and active-state emphasis.
struct ScholiumEditorialIconControl<NativeControl: View>: View {
    @FocusState private var isFocused: Bool

    private let nativeControl: NativeControl
    private let isActive: Bool
    private let isVisuallyRevealed: Bool

    init(
        systemImage: String,
        isActive: Bool = false,
        isVisuallyRevealed: Bool = true,
        @ViewBuilder nativeControl: (ScholiumEditorialIconControlLabel) -> NativeControl
    ) {
        self.nativeControl = nativeControl(
            ScholiumEditorialIconControlLabel(
                systemImage: systemImage
            ))
        self.isActive = isActive
        self.isVisuallyRevealed = isVisuallyRevealed
    }

    var body: some View {
        nativeControl
            .scholiumIconControl()
            .focused($isFocused)
            .environment(\.scholiumContentControlIsEmphasized, isActive)
            .opacity(isVisuallyRevealed || isFocused ? 1 : 0)
    }
}

struct ScholiumEditorialIconControlLabel: View {
    @Environment(\.scholiumContentControlIsEmphasized) private var isEmphasized

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .frame(
                width: ScholiumMetrics.Accessibility.minimumCustomTarget,
                height: ScholiumMetrics.Accessibility.minimumCustomTarget
            )
            .contentShape(Rectangle())
            .scholiumForeground(
                isEmphasized
                    ? .primaryText
                    : .secondaryText
            )
    }
}

/// One quiet full-row Button treatment shared by editorial summary and action
/// rows. Callers retain their purpose-owned hit height and content insets; the
/// component owns only the common raised hover/press feedback.
struct ScholiumQuietRowButtonStyle: ButtonStyle {
    let isFocused: Bool
    let minimumHeight: CGFloat
    let horizontalInset: CGFloat
    let verticalInset: CGFloat

    init(
        isFocused: Bool = false,
        minimumHeight: CGFloat,
        horizontalInset: CGFloat = ScholiumGrid.Spacing.inlineControlGap,
        verticalInset: CGFloat
    ) {
        self.isFocused = isFocused
        self.minimumHeight = minimumHeight
        self.horizontalInset = horizontalInset
        self.verticalInset = verticalInset
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, verticalInset)
            .frame(
                maxWidth: .infinity,
                minHeight: minimumHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .scholiumContentControlButtonFeedback(
                isFocused: isFocused,
                isPressed: configuration.isPressed,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
    }
}

enum ScholiumContentStatePlacement: Equatable {
    case centered
    case leading
}

enum ScholiumContentStateDensity: Equatable {
    case page
    case compact
}

enum ScholiumContentStateIndicator {
    case symbol(String, role: ScholiumColorRole = .secondaryText)
    case progress
}

/// The shared visible grammar for page- and pane-level Loading, Empty,
/// Unavailable, Error, and no-selection content. Feature owners retain their
/// domain state and actions; this view owns only indicator, copy hierarchy,
/// measure, spacing, adaptation, and accessibility grouping.
struct ScholiumContentStateView<Actions: View>: View {
    let title: Text
    let detail: Text?
    let indicator: ScholiumContentStateIndicator
    let placement: ScholiumContentStatePlacement
    let density: ScholiumContentStateDensity
    @ViewBuilder let actions: () -> Actions

    init(
        _ title: LocalizedStringResource,
        detail: Text? = nil,
        indicator: ScholiumContentStateIndicator,
        placement: ScholiumContentStatePlacement = .centered,
        density: ScholiumContentStateDensity = .page,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.init(title: Text(title), detail: detail, indicator: indicator, placement: placement, density: density, actions: actions)
    }

    init(
        title: Text,
        detail: Text? = nil,
        indicator: ScholiumContentStateIndicator,
        placement: ScholiumContentStatePlacement = .centered,
        density: ScholiumContentStateDensity = .page,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.detail = detail
        self.indicator = indicator
        self.placement = placement
        self.density = density
        self.actions = actions
    }

    var body: some View {
        Group {
            if placement == .centered || density == .page {
                VStack(
                    alignment: horizontalAlignment,
                    spacing: contentGroupSpacing
                ) {
                    indicatorView
                    copyAndActions
                }
            } else {
                HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    indicatorView
                        .frame(width: ScholiumGrid.Dimension.iconTrackWidth)
                    copyAndActions
                }
            }
        }
        .multilineTextAlignment(textAlignment)
        .frame(maxWidth: ScholiumMetrics.ContentState.readableWidth, alignment: frameAlignment)
        .padding(contentInset)
        .frame(
            maxWidth: .infinity,
            maxHeight: placement == .centered ? .infinity : nil,
            alignment: frameAlignment
        )
        .accessibilityElement(children: .contain)
    }

    private var copyAndActions: some View {
        VStack(alignment: horizontalAlignment, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            VStack(alignment: horizontalAlignment, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                title
                    .font(titleFont)
                    .scholiumForeground(.primaryText)

                if let detail {
                    detail
                        .font(detailFont)
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            actions()
                .controlSize(.small)
                .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
        }
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .symbol(let name, let role):
            Image(systemName: name)
                .scholiumSymbolStyle(indicatorSymbolStyle)
                .scholiumForeground(role)
                .accessibilityHidden(true)
        case .progress:
            ProgressView()
                .controlSize(density == .page ? .small : .mini)
                .accessibilityHidden(true)
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        placement == .centered ? .center : .leading
    }

    private var textAlignment: TextAlignment {
        placement == .centered ? .center : .leading
    }

    private var frameAlignment: Alignment {
        placement == .centered ? .center : .leading
    }

    private var contentInset: CGFloat {
        density == .page
            ? ScholiumGrid.Spacing.regionContentInset
            : 0
    }

    private var contentGroupSpacing: CGFloat {
        density == .page
            ? ScholiumGrid.Spacing.sectionSeparation
            : ScholiumGrid.Spacing.inlineControlGap
    }

    private var indicatorSymbolStyle: ScholiumSymbolStyle {
        density == .page ? .large : .prominent
    }

    private var titleFont: Font {
        density == .page
            ? ScholiumTypography.interface(.sectionTitle)
            : ScholiumTypography.interface(.rowTitle)
    }

    private var detailFont: Font {
        density == .page
            ? ScholiumTypography.interface(.body)
            : ScholiumTypography.interface(.small, emphasis: .medium)
    }
}

extension ScholiumContentStateView where Actions == EmptyView {
    init(
        _ title: LocalizedStringResource,
        detail: Text? = nil,
        indicator: ScholiumContentStateIndicator,
        placement: ScholiumContentStatePlacement = .centered,
        density: ScholiumContentStateDensity = .page
    ) {
        self.init(
            title,
            detail: detail,
            indicator: indicator,
            placement: placement,
            density: density,
            actions: { EmptyView() }
        )
    }

    init(
        title: Text,
        detail: Text? = nil,
        indicator: ScholiumContentStateIndicator,
        placement: ScholiumContentStatePlacement = .centered,
        density: ScholiumContentStateDensity = .page
    ) {
        self.title = title
        self.detail = detail
        self.indicator = indicator
        self.placement = placement
        self.density = density
        self.actions = { EmptyView() }
    }
}

struct ScholiumRecoveryNoticePresentation {
    let title: LocalizedStringKey
    let message: Text
    let detail: Text?
    let systemImage: String

    init(
        _ title: LocalizedStringKey,
        message: Text,
        detail: Text? = nil,
        systemImage: String
    ) {
        self.title = title
        self.message = message
        self.detail = detail
        self.systemImage = systemImage
    }
}

enum ScholiumRecoveryNoticeRegion {
    case documentInline
    case workspaceBanner
}

/// Persistent recovery presentation shared across workflow-owned recovery
/// states. Callers retain the domain state, operation, and action lifecycle;
/// this component owns only the visible grammar and region adaptation.
struct ScholiumRecoveryNotice<Action: View>: View {
    let presentation: ScholiumRecoveryNoticePresentation
    let region: ScholiumRecoveryNoticeRegion
    @ViewBuilder let action: () -> Action

    init(
        _ presentation: ScholiumRecoveryNoticePresentation,
        region: ScholiumRecoveryNoticeRegion,
        @ViewBuilder action: @escaping () -> Action
    ) {
        self.presentation = presentation
        self.region = region
        self.action = action
    }

    var body: some View {
        switch region {
        case .documentInline:
            noticeContent
                .padding(ScholiumGrid.Spacing.nestedContentInset)
                .background(
                    ScholiumColorRole.raisedSurfaceBackground.color,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                        style: .continuous
                    )
                )
                .scholiumBoundary(
                    .subtleBoundary,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                        style: .continuous
                    )
                )
        case .workspaceBanner:
            noticeContent
                .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
                .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ScholiumColorRole.raisedSurfaceBackground.color)
                .overlay(alignment: .bottom) {
                    ScholiumStructuralRule()
                }
        }
    }

    private var noticeContent: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                noticeDescription
                Spacer(minLength: ScholiumGrid.Spacing.nestedContentInset)
                action()
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                noticeDescription
                action()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var noticeDescription: some View {
        HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: presentation.systemImage)
                .scholiumForeground(.attention)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
                Text(presentation.title)
                    .font(ScholiumTypography.interface(.sectionTitle))
                presentation.message
                    .font(ScholiumTypography.interface(.body))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = presentation.detail {
                    detail
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum ScholiumDocumentStatusKind: Sendable {
    case attention
    case destructive

    var colorRole: ScholiumColorRole {
        switch self {
        case .attention: .attention
        case .destructive: .destructive
        }
    }

    var symbol: String {
        switch self {
        case .attention: "exclamationmark.triangle"
        case .destructive: "xmark.octagon"
        }
    }
}

/// Persistent Document-owned source-integrity feedback. The caller retains
/// the autosave or conflict state and supplies only the recovery actions that
/// are valid for that exact state.
struct ScholiumDocumentStatusNotice<Actions: View>: View {
    let title: String
    let detail: String
    let kind: ScholiumDocumentStatusKind
    @ViewBuilder let actions: () -> Actions

    init(
        _ title: String,
        detail: String,
        kind: ScholiumDocumentStatusKind,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.detail = detail
        self.kind = kind
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .center, spacing: ScholiumMetrics.Notice.contentSpacing) {
            HStack(alignment: .center, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(systemName: kind.symbol)
                    .scholiumForeground(kind.colorRole)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ScholiumMetrics.Notice.detailSpacing) {
                    Text(title)
                        .font(ScholiumTypography.interface(.sectionTitle))
                    Text(detail)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
        .padding(.vertical, ScholiumMetrics.Notice.verticalInset)
        .frame(maxWidth: 520, alignment: .leading)
        .scholiumEditorialSurface(
            .boundedPanel,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(detail)
    }
}
