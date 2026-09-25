import SwiftUI

/// Names each retained Sidebar page independently in the accessibility tree.
struct ScholiumSidebarPageSurface<Content: View>: View {
    let label: LocalizedStringKey
    let identifier: String
    let content: Content

    init(
        label: LocalizedStringKey,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
    }
}
