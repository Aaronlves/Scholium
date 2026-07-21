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

    init(_ title: String, detail: String? = nil, kind: ScholiumInlineStatusKind) {
        self.title = title
        self.detail = detail
        self.kind = kind
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
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
