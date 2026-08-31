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

/// A shared Properties/About group boundary. Visual grouping uses whitespace;
/// the semantic label remains available to assistive technologies.
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
        content
            .padding(
                .top,
                separatesFromPrevious
                    ? ScholiumMetrics.Properties.semanticGroupSeparation
                    : 0
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityHeading(.h3)
    }
}

/// The single presentation owner for matching icon controls in a content-owned
/// header. Its native Button or Menu child retains only activation, focus,
/// menu tracking, and accessibility semantics; this component owns the exact
/// target, ink, rounded-rectangle hover, focus and press surface, and control
/// style.
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
        self.nativeControl = nativeControl(ScholiumEditorialIconControlLabel(
            systemImage: systemImage
        ))
        self.isActive = isActive
        self.isVisuallyRevealed = isVisuallyRevealed
    }

    var body: some View {
        nativeControl
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .scholiumContentControlPointerFeedback(
                isActive: isActive,
                isFocused: isFocused,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
            .scholiumActivationFocus($isFocused)
            .opacity(isVisuallyRevealed || isFocused ? 1 : 0)
    }
}

struct ScholiumEditorialIconControlLabel: View {
    @Environment(\.scholiumContentControlIsEmphasized) private var isEmphasized

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .frame(
                width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                height: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
            .contentShape(Rectangle())
            .scholiumForeground(
                isEmphasized
                    ? .primaryText
                    : .secondaryText
            )
            .tint(
                isEmphasized
                    ? ScholiumColorRole.primaryText.color
                    : ScholiumColorRole.secondaryText.color
            )
    }
}

enum SidebarTriptychAttentionState: Equatable {
    case zero
    case active(count: Int)
    case checking
    case unavailable
}

/// The stable Triptych-level Notifications entry. Queue derivation and dismissal
/// remain outside this component; it owns exact aggregate presentation,
/// interaction feedback, and accessible state grammar without resembling an
/// inventory badge.
struct SidebarTriptychAttentionEntry: View {
    @Environment(\.locale) private var locale
    @Environment(\.scholiumAttentionPopoverIsPresented) private var isPresented
    @FocusState private var isFocused: Bool

    let state: SidebarTriptychAttentionState
    let open: () -> Void
    let retry: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(
                alignment: .firstTextBaseline,
                spacing: ScholiumGrid.Spacing.labelAccessoryGap
            ) {
                if state == .checking {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityHidden(true)
                        .frame(height: ScholiumMetrics.Accessibility.preferredCustomTarget)
                } else {
                    Text(Image(systemName: "bell"))
                        .font(ScholiumTypography.interface(.rowTitle))
                        .scholiumContentControlInk(
                            resting: symbolRestingRole,
                            emphasized: symbolEmphasizedRole
                        )
                        .accessibilityHidden(true)
                }

                if case .active(let count) = state {
                    Text(count.formatted())
                        .font(ScholiumTypography.interface(.small, emphasis: .medium, tabularDigits: true))
                        .scholiumForeground(.attention)
                }
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isSelected: isPresented,
                isFocused: isFocused,
                pressedOpacity: 0.76,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        )
        .scholiumActivationFocus($isFocused)
        .fixedSize()
        .help(actionLabel)
        .accessibilityLabel(actionLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("scholium.triptychNotifications")
    }

    private var action: () -> Void {
        state == .unavailable ? retry : open
    }

    private var actionLabel: String {
        state == .unavailable
            ? ScholiumL10n.string("Retry Triptych Notifications", locale: locale)
            : ScholiumL10n.string("Open Triptych Notifications", locale: locale)
    }

    private var accessibilityValue: String {
        switch state {
        case .zero:
            ScholiumL10n.string("No notifications", locale: locale)
        case .active(let count):
            String.localizedStringWithFormat(
                ScholiumL10n.string("%lld notifications", locale: locale),
                Int64(count)
            )
        case .checking:
            ScholiumL10n.string("Checking Notifications", locale: locale)
        case .unavailable:
            ScholiumL10n.string("Notifications Unavailable", locale: locale)
        }
    }

    private var symbolRestingRole: ScholiumColorRole {
        switch state {
        case .active, .unavailable:
            .attention
        case .zero, .checking:
            .secondaryText
        }
    }

    private var symbolEmphasizedRole: ScholiumColorRole {
        switch state {
        case .active, .unavailable:
            .attention
        case .zero, .checking:
            .primaryText
        }
    }
}

/// Compact Run-bound operations shared by the Document notification stack and
/// the complete Notifications queue. The caller owns surrounding information.
struct ResearchActivityNotificationControls: View {
    private enum ControlFocus: Hashable {
        case openAction
        case reviewResult
        case more
    }

    let notification: ResearchActivityNotification
    let openAction: () -> Void
    let endAction: () -> Void
    let reviewResult: () -> Void
    let followUp: () -> Void
    let dismiss: () -> Void

    @State private var confirmsEndAction = false
    @FocusState private var focusedControl: ControlFocus?

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            if notification.result != nil {
                Button("Review Result", action: reviewResult)
                    .accessibilityIdentifier(
                        "scholium.notification.action.reviewResult.\(notification.runID.uuidString)"
                    )
                    .scholiumActivationFocus(
                        $focusedControl,
                        equals: .reviewResult,
                        presentation: .native
                    )
                    .onKeyPress(.space) {
                        reviewResult()
                        return .handled
                    }
                Menu {
                    Button("Follow Up…", action: followUp)
                        .accessibilityIdentifier(
                            "scholium.notification.action.followUp.\(notification.runID.uuidString)"
                        )
                    Button("Dismiss", action: dismiss)
                        .accessibilityIdentifier(
                            "scholium.notification.action.dismiss.\(notification.runID.uuidString)"
                        )
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                    .accessibilityIdentifier(
                        "scholium.notification.action.more.\(notification.runID.uuidString)"
                    )
                    .scholiumActivationFocus(
                        $focusedControl,
                        equals: .more,
                        presentation: .native
                    )
            } else {
                Button("Open", action: openAction)
                    .accessibilityIdentifier(
                        "scholium.notification.action.open.\(notification.runID.uuidString)"
                    )
                    .scholiumActivationFocus(
                        $focusedControl,
                        equals: .openAction,
                        presentation: .native
                    )
                    .onKeyPress(.space) {
                        openAction()
                        return .handled
                    }
                Menu {
                    Button("End Action…", role: .destructive) {
                        confirmsEndAction = true
                    }
                    .accessibilityIdentifier(
                        "scholium.notification.action.end.\(notification.runID.uuidString)"
                    )
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier(
                    "scholium.notification.action.more.\(notification.runID.uuidString)"
                )
                .scholiumActivationFocus(
                    $focusedControl,
                    equals: .more,
                    presentation: .native
                )
            }
        }
        .controlSize(.small)
        .confirmationDialog(
            "End this Action?",
            isPresented: $confirmsEndAction,
            titleVisibility: .visible
        ) {
            Button("Keep Action", role: .cancel) {}
            Button("End Action", role: .destructive, action: endAction)
        } message: {
            Text("Scholium will revoke Agent access and end this unfinished Run. Existing recovery evidence remains available.")
        }
    }
}

/// The shared visual grammar for top-of-window notifications. Domain owners
/// supply state and operations; the banner owns concise copy, truncation,
/// adaptation, surface treatment, and accessibility grouping.
struct ScholiumNotificationBanner<Actions: View>: View {
    let systemImage: String
    let colorRole: ScholiumColorRole
    let title: String
    let detail: String?
    let maximumWidth: CGFloat
    let accessibilityIdentifier: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(
            alignment: .center,
            spacing: ScholiumGrid.Spacing.nestedContentInset
        ) {
            ScholiumNotificationBannerCopy(
                systemImage: systemImage,
                colorRole: colorRole,
                title: title,
                detail: detail
            )
            actions()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .scholiumNotificationBannerSurface(
            maximumWidth: maximumWidth,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
}

private struct ScholiumNotificationBannerCopy: View {
    let systemImage: String
    let colorRole: ScholiumColorRole
    let title: String
    let detail: String?

    var body: some View {
        HStack(
            alignment: .center,
            spacing: ScholiumGrid.Spacing.inlineControlGap
        ) {
            Image(systemName: systemImage)
                .font(ScholiumTypography.interface(.body, emphasis: .strong))
                .scholiumForeground(colorRole)
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
            ) {
                Text(verbatim: title)
                    .font(ScholiumTypography.interface(.rowTitle))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(-1)
        }
    }
}

private struct ScholiumNotificationBannerSurfaceModifier: ViewModifier {
    let maximumWidth: CGFloat
    let accessibilityIdentifier: String

    func body(content: Content) -> some View {
        content
            .padding(
                .horizontal,
                ScholiumMetrics.Workspace.compactNoticeHorizontalInset
            )
            .padding(
                .vertical,
                ScholiumMetrics.Workspace.compactNoticeVerticalInset
            )
            .scholiumContentFittingWidth(maximumWidth: maximumWidth)
            .scholiumEditorialSurface(.floatingControl, in: notificationShape)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var notificationShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ScholiumShape.inlineStatusCornerRadius,
            style: .continuous
        )
    }
}

private extension View {
    func scholiumNotificationBannerSurface(
        maximumWidth: CGFloat,
        accessibilityIdentifier: String
    ) -> some View {
        modifier(
            ScholiumNotificationBannerSurfaceModifier(
                maximumWidth: maximumWidth,
                accessibilityIdentifier: accessibilityIdentifier
            )
        )
    }
}

private struct ResearchActivityStackDisclosure {
    let count: Int
    let isExpanded: Bool
    let toggle: () -> Void
}

private struct ResearchActivityStackDisclosureButton: View {
    let disclosure: ResearchActivityStackDisclosure

    var body: some View {
        Button(action: disclosure.toggle) {
            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text(verbatim: "\(disclosure.count)")
                Image(
                    systemName: disclosure.isExpanded
                        ? "chevron.up"
                        : "chevron.down"
                )
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help(disclosureLabel)
        .accessibilityLabel(disclosureLabel)
        .accessibilityValue("\(disclosure.count) Notifications")
        .accessibilityIdentifier("scholium.notificationStack.disclosure")
    }

    private var disclosureLabel: String {
        if disclosure.isExpanded {
            return String(localized: "Hide Notifications")
        }
        return String(localized: "Show Notifications")
    }
}

private enum ResearchActivityNotificationStackItem: Identifiable {
    case settlement(WorkspaceSettlementRequirement)
    case action(ResearchActivityNotification)

    var id: String {
        switch self {
        case .settlement(let requirement):
            "settlement:\(requirement.noteID.uuidString):"
                + "\(requirement.currentRevision.sha256):"
                + "\(requirement.currentRevision.byteCount)"
        case .action(let notification):
            "action:\(notification.runID.uuidString)"
        }
    }
}

/// One direct notification or a bounded stack shared by Settlement reminders
/// and Action activity. The first real notification stays fixed while the
/// remaining real notifications reveal below it through hover or disclosure.
struct ResearchActivityNotificationStack: View {
    @Environment(\.locale) private var locale
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isPinnedExpanded = false

    let notifications: [ResearchActivityNotification]
    let settlementRequirement: WorkspaceSettlementRequirement?
    let expansionRequestGeneration: UInt64
    let reviewSettlementChanges: (WorkspaceSettlementRequirement) -> Void
    let openAction: (ResearchActivityNotification) -> Void
    let endAction: (ResearchActivityNotification) -> Void
    let reviewResult: (ResearchActivityNotification) -> Void
    let followUp: (ResearchActivityNotification) -> Void
    let dismiss: (ResearchActivityNotification) -> Void

    @ViewBuilder
    var body: some View {
        if let firstItem = items.first {
            if notificationCount == 1 {
                banner(for: firstItem, disclosure: nil)
                    .accessibilityIdentifier(
                        "scholium.researchActivityNotificationStack"
                    )
            } else {
                multipleNotificationStack(firstItem: firstItem)
            }
        }
    }

    private func multipleNotificationStack(
        firstItem: ResearchActivityNotificationStackItem
    ) -> some View {
        let shape = notificationShape
        let disclosure = ResearchActivityStackDisclosure(
            count: notificationCount,
            isExpanded: isExpanded,
            toggle: { isPinnedExpanded.toggle() }
        )
        return VStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            banner(for: firstItem, disclosure: disclosure)
            if isExpanded {
                expandedRows
                    .transition(
                        ScholiumMotion.activityNotificationStackExpansionTransition(
                            reduceMotion: reduceMotion
                        )
                    )
            }
        }
            .background(alignment: .bottom) {
                if !isExpanded { stackLayers(shape: shape) }
            }
            .padding(.bottom, isExpanded ? 0 : maximumLayerOffset)
            .zIndex(isExpanded ? 2 : 0)
            .scholiumHoverState { isHovering = $0 }
            .onChange(of: expansionRequestGeneration) { _, _ in
                isPinnedExpanded = true
            }
            .onChange(of: notificationIdentities) { _, identities in
                if identities.count < 2 { isPinnedExpanded = false }
            }
            .onKeyPress(.escape) {
                guard isExpanded else { return .ignored }
                isPinnedExpanded = false
                isHovering = false
                return .handled
            }
            .animation(
                ScholiumMotion.activityNotificationStackExpansion(
                    reduceMotion: reduceMotion
                ),
                value: isExpanded
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(countTitle)
            .accessibilityIdentifier(
                "scholium.researchActivityNotificationStack"
            )
    }

    private var expandedRows: some View {
        ScrollView {
            LazyVStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                ForEach(Array(items.dropFirst())) { item in
                    banner(for: item, disclosure: nil)
                }
            }
        }
        .frame(
            maxHeight: ScholiumMetrics.ActivityNotificationStack.expandedMaximumHeight
        )
        .scholiumContentFittingWidth(
            maximumWidth: ScholiumMetrics.ActivityNotificationStack.maximumWidth
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchActivityNotificationRows")
    }

    private var notificationShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ScholiumShape.inlineStatusCornerRadius,
            style: .continuous
        )
    }

    @ViewBuilder
    private func stackLayers(
        shape: RoundedRectangle
    ) -> some View {
        if visibleLayerCount > 1 {
            ZStack {
                ForEach(
                    Array((1..<visibleLayerCount).reversed()),
                    id: \.self
                ) { depth in
                    shape
                        .fill(ScholiumColorRole.surfaceBackground.color)
                        .scholiumBoundary(.floatingBoundary, in: shape)
                        .scaleEffect(
                            x: 1 - CGFloat(depth)
                                * ScholiumMetrics.ActivityNotificationStack
                                    .horizontalScaleStep,
                            y: 1,
                            anchor: .center
                        )
                        .offset(y: layerOffset(for: depth))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var visibleLayerCount: Int {
        min(
            notificationCount,
            ScholiumMetrics.ActivityNotificationStack.visibleLayerLimit
        )
    }

    private var isExpanded: Bool {
        notificationCount > 1
            && (isPinnedExpanded || isHovering)
    }

    private var maximumLayerOffset: CGFloat {
        CGFloat(max(0, visibleLayerCount - 1))
            * ScholiumMetrics.ActivityNotificationStack.collapsedLayerOffset
    }

    private func layerOffset(for depth: Int) -> CGFloat {
        CGFloat(depth)
            * ScholiumMetrics.ActivityNotificationStack.collapsedLayerOffset
    }

    private var countTitle: String {
        return String.localizedStringWithFormat(
            ScholiumL10n.string("%lld Notifications", locale: locale),
            Int64(notificationCount)
        )
    }

    private var notificationCount: Int {
        items.count
    }

    private var items: [ResearchActivityNotificationStackItem] {
        var result = settlementRequirement.map {
            [ResearchActivityNotificationStackItem.settlement($0)]
        } ?? []
        result.append(contentsOf: notifications.map {
            ResearchActivityNotificationStackItem.action($0)
        })
        return result
    }

    private var notificationIdentities: [String] {
        items.map(\.id)
    }

    @ViewBuilder
    private func banner(
        for item: ResearchActivityNotificationStackItem,
        disclosure: ResearchActivityStackDisclosure?
    ) -> some View {
        switch item {
        case .settlement(let requirement):
            SettlementRequirementNotificationBanner(
                requirement: requirement,
                disclosure: disclosure,
                reviewChanges: { reviewSettlementChanges(requirement) }
            )
        case .action(let notification):
            ResearchActivityNotificationBannerRow(
                notification: notification,
                disclosure: disclosure,
                openAction: { openAction(notification) },
                endAction: { endAction(notification) },
                reviewResult: { reviewResult(notification) },
                followUp: { followUp(notification) },
                dismiss: { dismiss(notification) }
            )
        }
    }
}

private struct SettlementRequirementNotificationBanner: View {
    let requirement: WorkspaceSettlementRequirement
    let disclosure: ResearchActivityStackDisclosure?
    let reviewChanges: () -> Void

    var body: some View {
        ScholiumNotificationBanner(
            systemImage: "exclamationmark.circle",
            colorRole: .attention,
            title: String(localized: "Current Revision Not Settled"),
            detail: detail,
            maximumWidth: ScholiumMetrics.ActivityNotificationStack.maximumWidth,
            accessibilityIdentifier:
                "scholium.notification.settlement.\(requirement.noteID.uuidString)"
        ) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if !requirement.pendingActivities.isEmpty {
                    Button("Review Changes", action: reviewChanges)
                }
                if let disclosure {
                    ResearchActivityStackDisclosureButton(
                        disclosure: disclosure
                    )
                }
            }
            .controlSize(.small)
        }
    }

    private var detail: String {
        guard !requirement.pendingActivities.isEmpty else {
            return requirement.title
        }
        return "\(requirement.title) · \(requirement.pendingActivities.count) Agent Changes"
    }
}

private struct ResearchActivityNotificationBannerRow: View {
    @Environment(\.locale) private var locale

    let notification: ResearchActivityNotification
    let disclosure: ResearchActivityStackDisclosure?
    let openAction: () -> Void
    let endAction: () -> Void
    let reviewResult: () -> Void
    let followUp: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ScholiumNotificationBanner(
            systemImage: stateSymbol,
            colorRole: stateColor,
            title: stateTitle,
            detail: "\(actionTitle) · \(targetTitle)",
            maximumWidth: ScholiumMetrics.ActivityNotificationStack.maximumWidth,
            accessibilityIdentifier:
                "scholium.notification.action.\(notification.runID.uuidString)"
        ) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                ResearchActivityNotificationControls(
                    notification: notification,
                    openAction: openAction,
                    endAction: endAction,
                    reviewResult: reviewResult,
                    followUp: followUp,
                    dismiss: dismiss
                )
                if let disclosure {
                    ResearchActivityStackDisclosureButton(
                        disclosure: disclosure
                    )
                }
            }
        }
    }

    private var targetTitle: String {
        notification.targetTitle.isEmpty
            ? ScholiumL10n.string("Research Action", locale: locale)
            : notification.targetTitle
    }

    private var stateTitle: String {
        ResearchActivityNotificationCopy.stateTitle(
            notification.state,
            locale: locale
        )
    }

    private var actionTitle: String {
        ResearchActivityNotificationCopy.actionTitle(
            notification.actionID,
            locale: locale
        )
    }

    private var stateSymbol: String {
        switch notification.state {
        case .waitingForAgent: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .needsAttention: "exclamationmark.triangle"
        case .resultReady: "doc.text.magnifyingglass"
        case .recoveryRequired: "wrench.and.screwdriver"
        }
    }

    private var stateColor: ScholiumColorRole {
        switch notification.state {
        case .needsAttention, .recoveryRequired: .attention
        case .waitingForAgent, .running, .resultReady: .secondaryText
        }
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

/// The Analyses / Topics / Works top-level navigator. It owns row presentation,
/// neutral Note totals, pointer feedback, and vertical keyboard traversal;
/// WindowShellState remains the sole owner of the selected workspace.
struct ScholiumTriptychWorkspaceNavigator: View {
    @FocusState private var focusedSlot: WorkspaceVaultSlot?

    let selectedSlot: WorkspaceVaultSlot?
    let noteCounts: SidebarWorkspaceNoteCounts
    let select: (WorkspaceVaultSlot) -> Void

    var body: some View {
        VStack(spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
            ForEach(WorkspaceVaultSlot.allCases) { slot in
                ScholiumTriptychWorkspaceButton(
                    slot: slot,
                    noteCount: noteCounts.count(for: slot),
                    isSelected: selectedSlot == slot,
                    focusedSlot: $focusedSlot,
                    select: { selectSlot(slot) },
                    move: { moveFocus(from: slot, direction: $0) }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Triptych Workspaces")
    }

    private func selectSlot(_ slot: WorkspaceVaultSlot) {
        guard selectedSlot != slot else { return }
        select(slot)
    }

    private func moveFocus(
        from slot: WorkspaceVaultSlot,
        direction: MoveCommandDirection
    ) {
        let slots = WorkspaceVaultSlot.allCases
        guard let index = slots.firstIndex(of: slot) else { return }
        let step: Int
        switch direction {
        case .up:
            step = -1
        case .down:
            step = 1
        default:
            return
        }
        let nextIndex = index + step
        guard slots.indices.contains(nextIndex) else { return }
        let nextSlot = slots[nextIndex]
        guard noteCounts.count(for: nextSlot) != nil else { return }
        select(nextSlot)
        focusedSlot = nextSlot
    }
}

private struct ScholiumTriptychWorkspaceButton: View {
    @Environment(\.locale) private var locale

    let slot: WorkspaceVaultSlot
    let noteCount: Int?
    let isSelected: Bool
    let focusedSlot: FocusState<WorkspaceVaultSlot?>.Binding
    let select: () -> Void
    let move: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text(ScholiumL10n.dynamicString(slot.displayName))
                    .font(
                        isSelected
                            ? ScholiumTypography.interface(.body, emphasis: .strong)
                            : ScholiumTypography.interface(.body)
                    )
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(noteCount.map { $0.formatted() } ?? "—")
                    .font(ScholiumTypography.interface(.small, emphasis: .medium, tabularDigits: true))
                    .scholiumForeground(.mutedText)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
            .contentShape(Rectangle())
            .scholiumContentControlInk()
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isSelected: isSelected,
                isFocused: isFocused,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.workspaceNavigationCornerRadius,
                    style: .continuous
                )
            )
        )
        .scholiumActivationFocus(focusedSlot, equals: slot)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    Task { @MainActor in
                        await Task.yield()
                        guard focusedSlot.wrappedValue == slot else { return }
                        focusedSlot.wrappedValue = nil
                    }
                }
        )
        .onMoveCommand(perform: move)
        .disabled(noteCount == nil)
        .accessibilityLabel(ScholiumL10n.dynamicString(slot.displayName))
        .accessibilityValue(noteCountAccessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("scholium.vault.\(slot.rawValue)")
    }

    private var isFocused: Bool {
        focusedSlot.wrappedValue == slot
    }

    private var noteCountAccessibilityValue: String {
        guard let noteCount else {
            return ScholiumL10n.string("Note count unavailable", locale: locale)
        }
        return String.localizedStringWithFormat(
            ScholiumL10n.string("%lld notes", locale: locale),
            Int64(noteCount)
        )
    }
}

/// Page-level Library content when no OutlineRow is being
/// presented. It deliberately uses the shared peripheral page edge rather
/// than the tighter row-surface inset used by Notes and Folders.
struct ScholiumLibrarySourceState<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScholiumMetrics.Library.contentInset)
            .padding(.vertical, ScholiumMetrics.Library.sourceStateVerticalInset)
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
        self.title = Text(title)
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

/// Shared presentation for ordered operation feedback. Feature owners retain
/// queue state and operation semantics; this component owns concise toast copy,
/// persistent notification grammar, announcement, and bounded lifetime.
struct ScholiumOperationFeedback: View {
    let id: UUID
    let message: String
    let kind: ScholiumFeedbackKind
    let maximumWidth: CGFloat
    let accessibilityIdentifierPrefix: String
    let dismiss: () -> Void

    var body: some View {
        Group {
            if kind.dismissesAutomatically {
                transientToast
            } else {
                persistentNotice
            }
        }
        .task(id: id) {
            AccessibilityNotification.Announcement(
                "\(kind.accessibilityLabel). \(message)"
            ).post()
            guard kind.dismissesAutomatically else { return }
            try? await Task.sleep(for: ScholiumFeedbackPolicy.transientLifetime)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private var transientToast: some View {
        HStack(alignment: .center, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: kind.symbol)
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(kind.colorRole)
                .accessibilityHidden(true)
            Text(verbatim: message)
                .font(ScholiumTypography.interface(.small))
                .lineLimit(1)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
        .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
        .padding(.vertical, ScholiumMetrics.Notice.verticalInset)
        .scholiumContentFittingWidth(maximumWidth: maximumWidth)
        .scholiumEditorialSurface(
            .floatingControl,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.accessibilityLabel)
        .accessibilityValue(message)
        .accessibilityIdentifier(
            "\(accessibilityIdentifierPrefix).\(kind.accessibilityIdentifierSuffix)"
        )
    }

    private var persistentNotice: some View {
        HStack(
            alignment: .center,
            spacing: ScholiumGrid.Spacing.nestedContentInset
        ) {
            ScholiumNotificationBannerCopy(
                systemImage: kind.symbol,
                colorRole: kind.colorRole,
                title: kind.accessibilityLabel,
                detail: message
            )
            Button("Dismiss", action: dismiss)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .padding(
            .horizontal,
            ScholiumMetrics.Workspace.compactNoticeHorizontalInset
        )
        .padding(
            .vertical,
            ScholiumMetrics.Workspace.compactNoticeVerticalInset
        )
        .scholiumContentFittingWidth(maximumWidth: maximumWidth)
        .scholiumEditorialSurface(
            .floatingControl,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.inlineStatusCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.accessibilityLabel)
        .accessibilityValue(message)
        .accessibilityIdentifier(
            "\(accessibilityIdentifierPrefix).\(kind.accessibilityIdentifierSuffix)"
        )
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
            .floatingControl,
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
