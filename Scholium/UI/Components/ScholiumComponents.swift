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

/// The single presentation owner for matching icon controls in a content-owned
/// header. Its native Button or Menu child retains only activation, focus,
/// menu tracking, and accessibility semantics; this component owns the exact
/// target, ink, rounded-rectangle hover, focus and press surface, and control
/// style.
struct ScholiumEditorialIconControl<NativeControl: View>: View {
    @FocusState private var isFocused: Bool

    private let nativeControl: NativeControl
    private let isActive: Bool

    init(
        systemImage: String,
        isActive: Bool = false,
        @ViewBuilder nativeControl: (ScholiumEditorialIconControlLabel) -> NativeControl
    ) {
        self.nativeControl = nativeControl(ScholiumEditorialIconControlLabel(
            systemImage: systemImage
        ))
        self.isActive = isActive
    }

    var body: some View {
        nativeControl
            .menuStyle(.button)
            .buttonStyle(.plain)
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
            .foregroundStyle(
                isEmphasized
                    ? ScholiumColorRole.primaryText.color
                    : ScholiumColorRole.secondaryText.color
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

/// The stable Triptych-level Attention entry. Queue derivation and dismissal
/// remain outside this component; it owns exact aggregate presentation,
/// interaction feedback, and accessible state grammar without resembling an
/// inventory badge.
struct SidebarTriptychAttentionEntry: View {
    @Environment(\.locale) private var locale
    @Environment(\.scholiumAttentionPopoverIsPresented) private var isPresented
    @State private var isHovering = false
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
                    Text(Image(systemName: "exclamationmark.triangle"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(symbolColor)
                        .accessibilityHidden(true)
                }

                if case .active(let count) = state {
                    Text(count.formatted())
                        .font(ScholiumInterfaceTypography.metadata.monospacedDigit())
                        .foregroundStyle(ScholiumColorRole.attention.color)
                }
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarTriptychAttentionButtonStyle(
            isHovering: isHovering || isPresented,
            isFocused: isFocused
        ))
        .scholiumActivationFocus($isFocused)
        .fixedSize()
        .onHover { isHovering = $0 }
        .help(actionLabel)
        .accessibilityLabel(actionLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("scholium.triptychAttention")
    }

    private var action: () -> Void {
        state == .unavailable ? retry : open
    }

    private var actionLabel: String {
        state == .unavailable
            ? ScholiumL10n.string("Retry Triptych Attention", locale: locale)
            : ScholiumL10n.string("Open Triptych Attention", locale: locale)
    }

    private var accessibilityValue: String {
        switch state {
        case .zero:
            ScholiumL10n.string("No items need attention", locale: locale)
        case .active(let count):
            String.localizedStringWithFormat(
                ScholiumL10n.string("%lld requiring attention", locale: locale),
                Int64(count)
            )
        case .checking:
            ScholiumL10n.string("Checking Attention", locale: locale)
        case .unavailable:
            ScholiumL10n.string("Attention Unavailable", locale: locale)
        }
    }

    private var symbolColor: Color {
        switch state {
        case .active, .unavailable:
            ScholiumColorRole.attention.color
        case .zero, .checking:
            isHovering || isFocused || isPresented
                ? ScholiumColorRole.primaryText.color
                : ScholiumColorRole.secondaryText.color
        }
    }
}

private struct SidebarTriptychAttentionButtonStyle: ButtonStyle {
    let isHovering: Bool
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scholiumContentInteractionSurface(
                isHovering: isHovering,
                isFocused: isFocused,
                isPressed: configuration.isPressed,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

/// One quiet full-row Button treatment shared by editorial summary and action
/// rows. Callers retain their purpose-owned hit height and content insets; the
/// component owns only the common raised hover/press feedback.
struct ScholiumQuietRowButtonStyle: ButtonStyle {
    let isHovering: Bool
    let isFocused: Bool
    let minimumHeight: CGFloat
    let horizontalInset: CGFloat
    let verticalInset: CGFloat

    init(
        isHovering: Bool,
        isFocused: Bool = false,
        minimumHeight: CGFloat,
        horizontalInset: CGFloat = ScholiumGrid.Spacing.inlineControlGap,
        verticalInset: CGFloat
    ) {
        self.isHovering = isHovering
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
            .scholiumContentInteractionSurface(
                isHovering: isHovering,
                isFocused: isFocused,
                isPressed: configuration.isPressed,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

/// The stable Library / Set Aside / Trash state selector. One native `Menu`
/// owns both the quiet label and its checkmarked, mutually-exclusive commands;
/// Scholium adds no bezel, background, or second chevron.
struct ScholiumLibraryLocationPicker: View {
    @Binding var selection: NoteLocationScope
    let focus: FocusState<Bool>.Binding

    var body: some View {
        Menu {
            locationChoice("Library", value: .workspace)
            locationChoice("Set Aside", value: .setAside)
            locationChoice("Trash", value: .trash)
        } label: {
            ScholiumLibraryLocationPickerLabel(title: selectedTitle)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .tint(ScholiumColorRole.secondaryText.color)
        .fixedSize()
        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
        .scholiumContentControlPointerFeedback(
            isFocused: focus.wrappedValue,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
        .scholiumActivationFocus(focus)
        .accessibilityLabel("Location")
        .accessibilityValue(selectedTitle)
        .accessibilityIdentifier("scholium.locationPicker")
    }

    private func locationChoice(
        _ title: LocalizedStringKey,
        value: NoteLocationScope
    ) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
        } label: {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var selectedTitle: String {
        switch selection {
        case .workspace:
            ScholiumL10n.dynamicString("Library")
        case .setAside:
            ScholiumL10n.dynamicString("Set Aside")
        case .trash:
            ScholiumL10n.dynamicString("Trash")
        }
    }
}

private struct ScholiumLibraryLocationPickerLabel: View {
    @Environment(\.scholiumContentControlIsEmphasized) private var isEmphasized

    let title: String

    var body: some View {
        Text(title)
            .font(ScholiumInterfaceTypography.libraryLocation)
            .foregroundStyle(
                isEmphasized
                    ? ScholiumColorRole.primaryText.color
                    : ScholiumColorRole.secondaryText.color
            )
            .lineLimit(1)
            .contentShape(Rectangle())
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
        select(nextSlot)
        focusedSlot = nextSlot
    }
}

private struct ScholiumTriptychWorkspaceButton: View {
    @Environment(\.locale) private var locale
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    @State private var isHovering = false

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
                            ? ScholiumInterfaceTypography.libraryWorkspaceSelected
                            : ScholiumInterfaceTypography.libraryWorkspace
                    )
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(noteCount.map { $0.formatted() } ?? "—")
                    .font(ScholiumInterfaceTypography.metadata.monospacedDigit())
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ScholiumTriptychWorkspaceButtonStyle(surface: rowSurface))
        .scholiumActivationFocus(focusedSlot, equals: slot)
        .foregroundStyle(
            isSelected || isHovering || isFocused
                ? ScholiumColorRole.primaryText.color
                : ScholiumColorRole.secondaryText.color
        )
        .onHover { isHovering = $0 }
        .onMoveCommand(perform: move)
        .accessibilityLabel(ScholiumL10n.dynamicString(slot.displayName))
        .accessibilityValue(noteCountAccessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("scholium.vault.\(slot.rawValue)")
    }

    private var isFocused: Bool {
        focusedSlot.wrappedValue == slot
    }

    private var rowSurface: Color {
        if isSelected {
            return ScholiumColorRole.raisedSurfaceBackground
                .color(increasedContrast: increasedContrast)
        }
        return ScholiumContentInteractionSurface.color(
            isHovering: isHovering,
            isFocused: isFocused,
            increasedContrast: increasedContrast
        )
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

private struct ScholiumTriptychWorkspaceButtonStyle: ButtonStyle {
    let surface: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                surface,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.workspaceNavigationCornerRadius,
                    style: .continuous
                )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

/// Page-level content for a Library Location when no OutlineRow is being
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
            if density == .page {
                VStack(alignment: horizontalAlignment, spacing: indicatorSpacing) {
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
                    .foregroundStyle(ScholiumColorRole.primaryText.color)

                if let detail {
                    detail
                        .font(detailFont)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
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
                .font(indicatorFont)
                .foregroundStyle(role.color)
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

    private var indicatorSpacing: CGFloat {
        density == .page
            ? ScholiumGrid.Spacing.sectionSeparation
            : ScholiumGrid.Spacing.inlineControlGap
    }

    private var contentInset: CGFloat {
        density == .page
            ? ScholiumGrid.Spacing.regionContentInset
            : 0
    }

    private var indicatorFont: Font {
        density == .page ? .title2 : .body
    }

    private var titleFont: Font {
        density == .page ? .headline : ScholiumInterfaceTypography.rowTitle
    }

    private var detailFont: Font {
        density == .page ? .subheadline : ScholiumInterfaceTypography.metadata
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
                    ScholiumColorRole.attention.color.opacity(0.08),
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
                .background(ScholiumColorRole.attention.color.opacity(0.08))
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
                    .font(.headline)
                presentation.message
                    .font(.callout)
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = presentation.detail {
                    detail
                        .font(.caption)
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
struct ScholiumDocumentStatusToast<Actions: View>: View {
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
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: kind.symbol)
                    .scholiumForeground(kind.colorRole)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .scholiumForeground(.secondaryText)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            actions()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
