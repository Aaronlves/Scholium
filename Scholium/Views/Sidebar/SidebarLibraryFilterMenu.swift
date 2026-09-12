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
    let propertyKeys: [String]
    let propertyValues: [String: [String]]
}

func sidebarActiveLibraryFilterCount(_ filters: DiscoveryFilterState) -> Int {
    [
        filters.needsAttention,
        filters.hasLinkAnnotations,
        filters.hasMalformedMetadata,
        filters.tag != nil,
        filters.author != nil,
        filters.propertyKey != nil && filters.propertyValue != nil,
    ].count(where: { $0 })
}

/// Library Filter presentation only. All mutations are complete replacement
/// intents sent back to DiscoveryController through the owning Sidebar.
struct SidebarLibraryFilterMenu: View {
    let filters: DiscoveryFilterState
    let sortOrder: NoteSortOrder
    let options: SidebarLibraryFilterOptions
    let canChangeFolderDisclosure: Bool
    let shouldCollapseFolders: Bool
    let toggleAllFolders: () -> Void
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
                    "Malformed Metadata",
                    isOn: filterBinding(\.hasMalformedMetadata)
                )
                .disabled(!options.catalogIsAvailable)
            }
            Section("Content") {
                Toggle(
                    "Link Annotations",
                    isOn: filterBinding(\.hasLinkAnnotations)
                )
                .disabled(!options.graphIsAvailable)
            }
            Section("Metadata") {
                Menu("Keyword") {
                    filterChoice(String(localized: "All Keywords"), selected: filters.tag == nil) { updateFilters { $0.tag = nil } }
                    Divider()
                    ForEach(options.tags, id: \.self) { tag in
                        filterChoice(tag, selected: filters.tag == tag) {
                            updateFilters { $0.tag = tag }
                        }
                    }
                }
                .disabled(options.tags.isEmpty && filters.tag == nil)
                if !options.authors.isEmpty || filters.author != nil {
                    Menu("Author") {
                        filterChoice(String(localized: "Any Author"), selected: filters.author == nil) { updateFilters { $0.author = nil } }
                        Divider()
                        ForEach(options.authors, id: \.self) { author in
                            filterChoice(author, selected: filters.author == author) {
                                updateFilters { $0.author = author }
                            }
                        }
                    }
                }
                if !options.propertyKeys.isEmpty || filters.propertyKey != nil {
                    Menu("Metadata Field") {
                        filterChoice(String(localized: "Any Metadata Field"), selected: filters.propertyKey == nil) {
                            updateFilters {
                                $0.propertyKey = nil
                                $0.propertyValue = nil
                            }
                        }
                        Divider()
                        ForEach(options.propertyKeys, id: \.self) { key in
                            Menu(propertyLabel(key)) {
                                ForEach(options.propertyValues[key] ?? [], id: \.self) { value in
                                    filterChoice(value, selected: filters.propertyKey == key && filters.propertyValue == value) {
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
            }
            if activeFilterCount > 0 {
                Button("Clear All Filters", action: clearFilters)
            }
            Divider()
            Menu("Sort By") {
                ForEach(NoteSortOrder.allCases) { order in
                    filterChoice(order.title, selected: sortOrder == order) {
                        selectSortOrder(order)
                    }
                }
            }
            Section("Folders") {
                Button(
                    shouldCollapseFolders
                        ? "Collapse All Folders"
                        : "Expand All Folders",
                    action: toggleAllFolders
                )
                .disabled(!canChangeFolderDisclosure)
            }
        } label: {
            ScholiumSidebarHeaderIcon(
                systemImage: activeFilterCount == 0
                    ? "line.3.horizontal.decrease"
                    : "line.3.horizontal.decrease.circle.fill")
        }
        .scholiumSidebarHeaderControl()
        .help(
            activeFilterCount == 0
                ? "Organize, filter, and sort Library notes"
                : "\(activeFilterCount) Library filters active"
        )
        .accessibilityLabel("Organize Library")
        .accessibilityValue(
            activeFilterCount == 0
                ? "No filters active"
                : "\(activeFilterCount) filters active"
        )
        .accessibilityIdentifier("scholium.libraryFilters")
    }

    @ViewBuilder
    private func filterChoice(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Toggle(title, isOn: Binding(get: { selected }, set: { _ in action() }))
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
