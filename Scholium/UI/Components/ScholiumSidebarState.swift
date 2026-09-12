import SwiftUI

/// Sidebar loading, empty and recovery copy share one compact visual recipe.
/// Callers own state, wording and actions; this view owns no lifecycle or I/O.
struct ScholiumSidebarState<Actions: View>: View {
    let title: Text
    let detail: Text?
    let indicator: ScholiumContentStateIndicator
    @ViewBuilder let actions: () -> Actions

    init(
        _ title: Text, detail: Text? = nil,
        indicator: ScholiumContentStateIndicator,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.detail = detail
        self.indicator = indicator
        self.actions = actions
    }

    var body: some View {
        ScholiumContentStateView(
            title: title, detail: detail, indicator: indicator,
            placement: .leading, density: .compact, actions: actions
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, ScholiumSidebarLayout.textInset)
        .padding(.vertical, ScholiumSidebarLayout.sectionSpacing)
        .accessibilityElement(children: .contain)
    }
}

extension ScholiumSidebarState where Actions == EmptyView {
    init(_ title: Text, detail: Text? = nil, indicator: ScholiumContentStateIndicator) {
        self.init(title, detail: detail, indicator: indicator) { EmptyView() }
    }
}
