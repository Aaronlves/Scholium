import SwiftUI

/// Shared grouping and insets for source passages in Links and Related Material.
struct ResearchPassageCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            content()
                .font(ScholiumTypography.interface(.control))
                .lineSpacing(ScholiumGrid.Apparatus.passageLineSpacing)
                // GroupBox contributes its native gutter. The remaining inset
                // brings passage text onto the note heading's text rail.
                .padding(.leading, ScholiumGrid.Apparatus.iconColumnWidth)
                .padding(.trailing, ScholiumGrid.Apparatus.connectionOccurrenceVerticalInset)
                .padding(.vertical, ScholiumGrid.Apparatus.connectionOccurrenceVerticalInset)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Real excerpts and their initial placeholders share one bounded reading measure.
struct ResearchPassageExcerpt: View {
    let text: Text

    var body: some View {
        ResearchText(text: text).lineLimit(5)
    }
}
