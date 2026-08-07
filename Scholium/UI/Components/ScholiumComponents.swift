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

/// One restrained selection mark shared by editorial indexes. Each consumer
/// retains its own purpose-named dimensions; this component owns only color
/// and visibility treatment.
struct ScholiumEditorialIndexUnderline: View {
    let isSelected: Bool
    var isHovering = false
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                isSelected
                    ? ScholiumColorRole.accent.color
                    : ScholiumColorRole.secondaryText.color.opacity(isHovering ? 0.45 : 0)
            )
            .frame(width: width, height: height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum SidebarAttentionAlertState: Equatable {
    case active(count: Int)
    case checking
    case unavailable
}

/// The rare current-Scope Attention exception. Queue derivation and dismissal
/// remain outside this component; it owns only the stable alert grammar used
/// at the Sidebar's navigation level.
struct SidebarAttentionAlert: View {
    let state: SidebarAttentionAlertState
    let open: () -> Void
    let retry: () -> Void

    var body: some View {
        switch state {
        case .active(let count):
            Button(action: open) {
                content(
                    title: "ATTENTION",
                    trailing: count.formatted(),
                    showsProgress: false
                )
            }
            .buttonStyle(SidebarAttentionAlertButtonStyle())
            .help("Open Attention")
            .accessibilityValue("\(count) items")
            .accessibilityIdentifier("scholium.location.attention")
        case .checking:
            content(
                title: "Checking Attention",
                trailing: nil,
                showsProgress: true
            )
            .modifier(SidebarAttentionAlertSurface())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("scholium.attentionChecking")
        case .unavailable:
            Button(action: retry) {
                content(
                    title: "Attention Unavailable",
                    trailing: "Retry",
                    showsProgress: false
                )
            }
            .buttonStyle(SidebarAttentionAlertButtonStyle())
            .help("Retry Attention")
            .accessibilityHint("Retries loading the derived Attention queue.")
            .accessibilityIdentifier("scholium.attentionUnavailable")
        }
    }

    private func content(
        title: LocalizedStringKey,
        trailing: String?,
        showsProgress: Bool
    ) -> some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(ScholiumColorRole.attention.color)
                .frame(width: ScholiumMetrics.Library.leadingSlotWidth)
                .accessibilityHidden(true)
            Text(title)
                .font(ScholiumInterfaceTypography.editorialLabel)
                .tracking(0.7)
            Spacer(minLength: 0)
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            } else if let trailing {
                Text(trailing)
                    .font(ScholiumInterfaceTypography.metadata.monospacedDigit())
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
        }
        .foregroundStyle(ScholiumColorRole.primaryText.color)
    }
}

private struct SidebarAttentionAlertSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                alignment: .leading
            )
            .background(
                ScholiumColorRole.raisedSurfaceBackground.color,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
    }
}

private struct SidebarAttentionAlertButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SidebarAttentionAlertSurface())
            .opacity(configuration.isPressed ? 0.76 : 1)
    }
}

/// One quiet full-row Button treatment shared by editorial summary and action
/// rows. Callers retain their purpose-owned hit height and content insets; the
/// component owns only the common raised hover/press feedback.
struct ScholiumQuietRowButtonStyle: ButtonStyle {
    let isHovering: Bool
    let minimumHeight: CGFloat
    let horizontalInset: CGFloat
    let verticalInset: CGFloat

    init(
        isHovering: Bool,
        minimumHeight: CGFloat,
        horizontalInset: CGFloat = ScholiumGrid.Spacing.inlineControlGap,
        verticalInset: CGFloat
    ) {
        self.isHovering = isHovering
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
            .background(
                isHovering || configuration.isPressed
                    ? ScholiumColorRole.raisedSurfaceBackground.color
                    : Color.clear,
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

    var body: some View {
        Menu {
            locationChoice("Library", value: .workspace)
            locationChoice("Set Aside", value: .setAside)
            locationChoice("Trash", value: .trash)
        } label: {
            Text(selectedTitle)
                .font(ScholiumInterfaceTypography.libraryLocation)
                .foregroundStyle(ScholiumColorRole.accent.color)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .tint(ScholiumColorRole.accent.color)
        .fixedSize()
        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
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
