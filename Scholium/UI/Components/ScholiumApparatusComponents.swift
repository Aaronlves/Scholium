import SwiftUI

/// One Inspector section with a shared heading, internal rhythm, optional
/// trailing action, and optional structural rule. It owns presentation only;
/// feature state and actions remain with the feature that supplies its content.
struct ScholiumApparatusSection<Content: View, Trailing: View>: View {
    let title: LocalizedStringResource
    let showsDivider: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: LocalizedStringResource,
        showsDivider: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.showsDivider = showsDivider
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ScholiumMetrics.Apparatus.sectionContentSpacing
        ) {
            HStack(spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
                Text(title)
                    .font(ScholiumInterfaceTypography.apparatusLabel)
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer(minLength: ScholiumMetrics.Apparatus.iconToTextSpacing)
                trailing()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, ScholiumMetrics.Apparatus.sectionContentInset)

            if showsDivider {
                ScholiumStructuralRule()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension ScholiumApparatusSection where Trailing == EmptyView {
    init(
        _ title: LocalizedStringResource,
        showsDivider: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title,
            showsDivider: showsDivider,
            content: content,
            trailing: { EmptyView() }
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
