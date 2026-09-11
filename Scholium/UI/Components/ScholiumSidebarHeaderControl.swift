import SwiftUI

/// Local native-sidebar layout defaults, independent of the editorial geometry used by document-related panes.
enum ScholiumSidebarLayout {
    static let edgeInset: CGFloat = 12
    static let rowInset: CGFloat = 12
    static var textInset: CGFloat { edgeInset + rowInset }
    static let controlWidth: CGFloat = 36
    static let controlHeight: CGFloat = 32
    static let controlGap: CGFloat = 4
    static let sectionSpacing: CGFloat = 16
    static let headerHeight: CGFloat = 40
}

/// Title rows and their trailing actions share the same container edge.
struct ScholiumSidebarHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
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
