import SwiftUI

/// Sidebar spacing derives from the shared grid, independently of Inspector
/// geometry. Containers use the outer rail; row copy uses one additional inset.
/// Native control sizing, outline indentation and text baselines remain native.
enum ScholiumSidebarLayout {
    static let edgeInset = ScholiumGrid.Spacing.nestedContentInset
    static let rowInset = ScholiumGrid.Spacing.nestedContentInset
    static var textInset: CGFloat { edgeInset + rowInset }
    static let itemSpacing = ScholiumGrid.Spacing.inlineControlGap
    static let textSpacing = ScholiumGrid.Spacing.labelAccessoryGap
    static let controlWidth = ScholiumGrid.foundationUnit * 9
    static let controlHeight = ScholiumGrid.foundationUnit * 8
    static let controlGap = ScholiumGrid.Spacing.labelAccessoryGap
    static let sectionSpacing = ScholiumGrid.Spacing.sectionSeparation
    static let headerHeight = ScholiumGrid.foundationUnit * 10
}

/// Title rows and their trailing actions share the same container edge.
struct ScholiumSidebarHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: ScholiumSidebarLayout.itemSpacing) {
            content
        }
        .frame(maxWidth: .infinity, minHeight: ScholiumSidebarLayout.headerHeight)
        .padding(.horizontal, ScholiumSidebarLayout.edgeInset)
    }
}

struct ScholiumSidebarHeaderActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: ScholiumSidebarLayout.controlGap) {
            content
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }
}

/// The label owns its complete hit area; native controls own activation and state.
struct ScholiumSidebarHeaderIcon: View {
    let systemImage: String
    // At body size, the compose symbol's visible strokes sit half a point down
    // and right of the archive/ellipsis optical center. Scale the correction
    // with the symbol's text style; the surrounding hit area remains unchanged.
    @ScaledMetric(relativeTo: .body) private var composeOpticalCorrection: CGFloat = 0.5

    var body: some View {
        Image(systemName: systemImage)
            .font(.body)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(ScholiumNativeColorRole.secondaryLabel.color)
            .offset(
                x: systemImage == "square.and.pencil" ? -composeOpticalCorrection : 0,
                y: systemImage == "square.and.pencil" ? -composeOpticalCorrection : 0
            )
            .frame(width: ScholiumSidebarLayout.controlWidth, height: ScholiumSidebarLayout.controlHeight)
            .contentShape(Rectangle())
    }
}

extension View {
    func scholiumSidebarHeaderControl() -> some View {
        self.menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .tint(nil as Color?)
    }
}
