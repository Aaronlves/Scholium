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

struct ScholiumPanelHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ScholiumInterfaceTypography.sectionTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .scholiumForeground(.secondaryText)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .accessibilityElement(children: .contain)
    }
}

extension ScholiumPanelHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

enum ScholiumInlineStatusKind: Sendable {
    case information
    case attention
    case destructive
    case confirmed
    case agentAuthorship

    var colorRole: ScholiumColorRole {
        switch self {
        case .information: .information
        case .attention: .attention
        case .destructive: .destructive
        case .confirmed: .confirmed
        case .agentAuthorship: .agentAuthorship
        }
    }

    var symbol: String {
        switch self {
        case .information: "info.circle"
        case .attention: "exclamationmark.triangle"
        case .destructive: "xmark.octagon"
        case .confirmed: "checkmark.circle"
        case .agentAuthorship: "sparkles"
        }
    }
}

struct ScholiumInlineStatus: View {
    let title: String
    let detail: String?
    let kind: ScholiumInlineStatusKind
    let verticalAlignment: VerticalAlignment

    init(
        _ title: String,
        detail: String? = nil,
        kind: ScholiumInlineStatusKind,
        verticalAlignment: VerticalAlignment = .firstTextBaseline
    ) {
        self.title = title
        self.detail = detail
        self.kind = kind
        self.verticalAlignment = verticalAlignment
    }

    var body: some View {
        HStack(alignment: verticalAlignment, spacing: 8) {
            Image(systemName: kind.symbol)
                .scholiumForeground(kind.colorRole)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .scholiumForeground(.secondaryText)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Persistent Document-owned source-integrity feedback. The caller retains
/// the autosave or conflict state and supplies only the recovery actions that
/// are valid for that exact state.
struct ScholiumDocumentStatusToast<Actions: View>: View {
    let title: String
    let detail: String
    let kind: ScholiumInlineStatusKind
    @ViewBuilder let actions: () -> Actions

    init(
        _ title: String,
        detail: String,
        kind: ScholiumInlineStatusKind,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.detail = detail
        self.kind = kind
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ScholiumInlineStatus(
                title,
                detail: detail,
                kind: kind,
                verticalAlignment: .center
            )
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

extension ScholiumDocumentStatusToast where Actions == EmptyView {
    init(
        _ title: String,
        detail: String,
        kind: ScholiumInlineStatusKind
    ) {
        self.init(title, detail: detail, kind: kind) { EmptyView() }
    }
}

struct ScholiumSourceAnchorRow: View {
    let title: String
    let location: String
    let detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "text.page.badge.magnifyingglass")
                    .scholiumForeground(.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(location)
                        .font(.caption)
                        .scholiumForeground(.secondaryText)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .scholiumForeground(.secondaryText)
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open source location")
    }
}

struct ScholiumEmptyState<ActionLabel: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: (() -> Void)?
    @ViewBuilder let actionLabel: () -> ActionLabel

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(detail)
        } actions: {
            if let action {
                Button(action: action, label: actionLabel)
            }
        }
    }
}

extension ScholiumEmptyState where ActionLabel == EmptyView {
    init(title: String, detail: String, systemImage: String) {
        self.init(
            title: title,
            detail: detail,
            systemImage: systemImage,
            action: nil
        ) { EmptyView() }
    }
}

struct ScholiumNoteRow: View {
    let title: String
    let role: String
    let location: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body)
                .scholiumForeground(.secondaryText)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(role)
                    .font(.caption)
                    .scholiumForeground(.secondaryText)
                    .lineLimit(1)
                Text(location)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
