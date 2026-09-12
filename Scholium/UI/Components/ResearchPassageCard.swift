import SwiftUI

/// Shared grouping and insets for source passages in Links and Related Material.
struct ResearchPassageCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            content()
                .padding(ScholiumGrid.Apparatus.connectionOccurrenceVerticalInset)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
