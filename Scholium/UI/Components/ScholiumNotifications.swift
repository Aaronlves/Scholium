import SwiftUI

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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: ScholiumGrid.Spacing.nestedContentInset) {
                copy
                actions().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                copy
                actions().frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .scholiumNotificationBannerSurface(
            maximumWidth: maximumWidth,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }
    private var copy: some View {
        ScholiumNotificationBannerCopy(systemImage: systemImage, colorRole: colorRole,
                                       title: title, detail: detail)
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
                    .textSelection(.enabled)
                if let detail, !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .lineLimit(3)
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
            .scholiumFloatingSurface(in: notificationShape)
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
        ScholiumNotificationBanner(
            systemImage: kind.symbol,
            colorRole: kind.colorRole,
            title: kind.dismissesAutomatically ? message : kind.accessibilityLabel,
            detail: kind.dismissesAutomatically ? nil : message,
            maximumWidth: maximumWidth,
            accessibilityIdentifier: "\(accessibilityIdentifierPrefix).\(kind.accessibilityIdentifierSuffix)"
        ) {
            if !kind.dismissesAutomatically {
                Button("Dismiss", action: dismiss)
                    .scholiumButtonStyle(.borderless)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .accessibilityLabel(kind.accessibilityLabel)
        .accessibilityValue(message)
        .task(id: id) {
            AccessibilityNotification.Announcement("\(kind.accessibilityLabel). \(message)").post()
            guard kind.dismissesAutomatically else { return }
            try? await Task.sleep(for: ScholiumFeedbackPolicy.transientLifetime)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}
