import SwiftUI

/// The native container and its row geometry have one owner for both Inspector panes.
extension View {
    func researchListStyle() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .contentMargins(.top, ResearchInspectorLayout.topInset, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, ScholiumGrid.Dimension.preferredCustomTarget)
    }

    func researchListRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(.horizontal, ResearchInspectorLayout.listRowInset)
            .listRowInsets(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
    }
}
