import Foundation
import SwiftUI

/// Immutable availability and choice values used by the Library-only Filter
/// menu. DiscoveryController remains the sole owner of selected filters and
/// ordering; this value contains no mutable presentation or domain state.
struct SidebarLibraryFilterOptions: Equatable, Sendable {
    let catalogIsAvailable: Bool
    let graphIsAvailable: Bool
    let tags: [String]
    let authors: [String]
    let years: [Int]
    let propertyKeys: [String]
    let propertyValues: [String: [String]]
}

func sidebarActiveLibraryFilterCount(_ filters: DiscoveryFilterState) -> Int {
    [
        filters.needsAttention,
        filters.hasExplicitConnections,
        filters.hasMalformedMetadata,
        filters.tag != nil,
        filters.author != nil,
        filters.year != nil,
        filters.propertyKey != nil && filters.propertyValue != nil,
    ].count(where: { $0 })
}

func sidebarHasScopedDebateImportanceFilter(
    _ filters: DiscoveryFilterState
) -> Bool {
    filters.propertyKey == "debate_importance_scope"
        && filters.propertyValue?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
}

/// Library Filter presentation only. All mutations are complete replacement
/// intents sent back to DiscoveryController through the owning Sidebar.
struct SidebarLibraryFilterMenu: View {
    let filters: DiscoveryFilterState
    let sortOrder: NoteSortOrder
    let options: SidebarLibraryFilterOptions
    let replaceFilters: (DiscoveryFilterState) -> Void
    let selectSortOrder: (NoteSortOrder) -> Void
    let clearFilters: () -> Void

    private var activeFilterCount: Int {
        sidebarActiveLibraryFilterCount(filters)
    }

    var body: some View {
        Menu {
            Section("Integrity") {
                Toggle("Needs Attention", isOn: filterBinding(\.needsAttention))
                    .disabled(!options.catalogIsAvailable)
                Toggle(
                    "Explicit Connections",
                    isOn: filterBinding(\.hasExplicitConnections)
                )
                .disabled(!options.graphIsAvailable)
                Toggle(
                    "Malformed Metadata",
                    isOn: filterBinding(\.hasMalformedMetadata)
                )
                .disabled(!options.catalogIsAvailable)
            }
            Section("Metadata") {
                Menu("Tag") {
                    Button("All Tags") { updateFilters { $0.tag = nil } }
                    Divider()
                    ForEach(options.tags, id: \.self) { tag in
                        filterChoice(tag, selected: filters.tag == tag) {
                            updateFilters { $0.tag = tag }
                        }
                    }
                }
                .disabled(options.tags.isEmpty)
                if !options.authors.isEmpty {
                    Menu("Author") {
                        Button("Any Author") { updateFilters { $0.author = nil } }
                        Divider()
                        ForEach(options.authors, id: \.self) { author in
                            filterChoice(author, selected: filters.author == author) {
                                updateFilters { $0.author = author }
                            }
                        }
                    }
                }
                if !options.years.isEmpty {
                    Menu("Year") {
                        Button("Any Year") { updateFilters { $0.year = nil } }
                        Divider()
                        ForEach(options.years, id: \.self) { year in
                            let title = year.formatted(.number.grouping(.never))
                            filterChoice(title, selected: filters.year == year) {
                                updateFilters { $0.year = year }
                            }
                        }
                    }
                }
            }
            if !options.propertyKeys.isEmpty {
                Section("Properties") {
                    Button("Any Property") {
                        updateFilters {
                            $0.propertyKey = nil
                            $0.propertyValue = nil
                        }
                    }
                    ForEach(options.propertyKeys, id: \.self) { key in
                        Menu(propertyLabel(key)) {
                            ForEach(options.propertyValues[key] ?? [], id: \.self) { value in
                                filterChoice(
                                    value,
                                    selected: filters.propertyKey == key
                                        && filters.propertyValue == value
                                ) {
                                    updateFilters {
                                        $0.propertyKey = key
                                        $0.propertyValue = value
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section("Order") {
                Menu("Sort") {
                    ForEach(NoteSortOrder.allCases) { order in
                        filterChoice(order.title, selected: sortOrder == order) {
                            selectSortOrder(order)
                        }
                        .disabled(
                            order == .debateImportanceDescending
                                && !sidebarHasScopedDebateImportanceFilter(filters)
                        )
                    }
                }
            }
            if activeFilterCount > 0 {
                Section("Actions") {
                    Button("Clear All Filters", action: clearFilters)
                }
            }
        } label: {
            Label(
                "Filter",
                systemImage: activeFilterCount == 0
                    ? "line.3.horizontal.decrease"
                    : "line.3.horizontal.decrease.circle.fill"
            )
            .labelStyle(.iconOnly)
            .frame(
                width: ScholiumMetrics.Accessibility.preferredCustomTarget,
                height: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(activeFilterCount == 0
            ? "Filter and sort Library notes"
            : "\(activeFilterCount) Library filters active")
        .accessibilityLabel("Library filters")
        .accessibilityValue(activeFilterCount == 0
            ? "No filters active"
            : "\(activeFilterCount) filters active")
        .accessibilityIdentifier("scholium.libraryFilters")
    }

    @ViewBuilder
    private func filterChoice(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    private func filterBinding<Value>(
        _ keyPath: WritableKeyPath<DiscoveryFilterState, Value>
    ) -> Binding<Value> {
        Binding(
            get: { filters[keyPath: keyPath] },
            set: { value in updateFilters { $0[keyPath: keyPath] = value } }
        )
    }

    private func updateFilters(
        _ update: (inout DiscoveryFilterState) -> Void
    ) {
        var updatedFilters = filters
        update(&updatedFilters)
        replaceFilters(updatedFilters)
    }

    private func propertyLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
