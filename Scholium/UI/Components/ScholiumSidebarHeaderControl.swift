import SwiftUI

/// Shared title-row geometry keeps Library and both Chat presentations on one grid.
struct ScholiumSidebarHeader<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
      content
    }
    .frame(maxWidth: .infinity, minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
    .padding(.horizontal, ScholiumMetrics.Library.contentInset)
  }
}

/// The trailing action group of a panel header, separate from the window toolbar.
struct ScholiumSidebarHeaderActions<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
      content
    }
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityElement(children: .contain)
  }
}

/// Shared by Library and Chat headers: semantic ink, native activation and one hover owner.
struct ScholiumSidebarHeaderIcon: View {
  static let foreground = Color(nsColor: .secondaryLabelColor)

  let systemImage: String
  var body: some View {
    Image(systemName: systemImage)
      .font(ScholiumTypography.interface(.control))
      .symbolRenderingMode(.monochrome)
      .frame(
        width: ScholiumMetrics.Accessibility.minimumCustomTarget,
        height: ScholiumMetrics.Accessibility.minimumCustomTarget
      )
  }
}

extension View {
  func scholiumSidebarHeaderControl(isActive: Bool = false) -> some View {
    frame(
      width: ScholiumMetrics.Accessibility.preferredCustomTarget,
      height: ScholiumMetrics.Accessibility.preferredCustomTarget
    )
    .menuStyle(.button)
    .buttonStyle(.borderless)
    .tint(ScholiumSidebarHeaderIcon.foreground)
    .menuIndicator(.hidden)
    .scholiumContentControlPointerFeedback(isActive: isActive, in: Circle())
  }
}
