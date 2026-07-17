import ScholiumContracts
import SwiftUI

/// Immutable window projection and actions used by the Search presentation.
/// Search state itself remains owned by `DiscoveryController`; persistence and
/// presentation routing stay explicit at the `ContentView` composition root.
struct SpotlightSearchContext {
    let savedSearches: [SavedSearch]
    let refresh: () async -> Void
    let dismiss: () -> Void
    let save: (String) -> Void
    let run: (SavedSearch) -> Void
    let rename: (UUID, String) -> Void
    let move: (UUID, Int) -> Void
    let delete: (UUID) -> Void
}

struct SpotlightSearchPanelView: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let context: SpotlightSearchContext
    let maxPanelHeight: CGFloat?
    @FocusState private var searchFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    @State private var showSaveSearch = false
    @State private var savedSearchName = ""
    @State private var renamingSearch: SavedSearch?
    @State private var renamedSearchName = ""

    init(
        controller: DiscoveryController,
        context: SpotlightSearchContext,
        maxPanelHeight: CGFloat? = nil
    ) {
        self.controller = controller
        self.context = context
        self.maxPanelHeight = maxPanelHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Divider()
                .opacity(0.55)
                .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)

            searchScopeBar

            if isExpanded {
                if let searchError = controller.search.errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Label("Search Unavailable", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                        Text(searchError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Retry") { Task { await context.refresh() } }
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        Color.orange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .padding(.horizontal, 28)
                    .accessibilityElement(children: .combine)
                }

                searchContent
            }
        }
        .frame(
            minWidth: 0,
            idealWidth: ScholiumMetrics.Search.preferredWidth,
            maxWidth: ScholiumMetrics.Search.maximumWidth
        )
        .frame(
            height: isExpanded
                ? expandedPanelHeight
                : ScholiumMetrics.Search.collapsedHeight,
            alignment: .top
        )
        .scholiumGlassSurface(
            .searchOverlay,
            in: RoundedRectangle(
                cornerRadius: ScholiumMetrics.Search.cornerRadius,
                style: .continuous
            ),
            elevation: .searchOverlay
        )
        .animation(
            ScholiumMotion.searchExpansion(reduceMotion: reduceMotion),
            value: isExpanded
        )
        .accessibilityElement(children: .contain)
        .onAppear {
            searchFocused = true
            normalizeSelection()
        }
        .onChange(of: controller.search.hits) { _, _ in
            normalizeSelection()
        }
        .onChange(of: controller.search.relatedItems) { _, _ in
            normalizeSelection()
        }
        .background {
            if !controller.search.isRunning,
               !controller.search.criteria.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PerformanceReadyBoundary(
                    generation: [
                        controller.search.criteria.query,
                        String(controller.search.hits.count),
                        String(controller.search.relatedItems.count),
                    ].joined(separator: ":")
                ) {
                    PerformanceProbe.shared.markSearchResultsReady(
                        query: controller.search.criteria.query,
                        resultCount: controller.search.hits.count
                    )
                }
                .frame(width: 0, height: 0)
            }
        }
        .onMoveCommand(perform: moveSelection)
        .onDisappear { searchTask?.cancel() }
        .onExitCommand(perform: context.dismiss)
        .alert("Save Search", isPresented: $showSaveSearch) {
            TextField("Search name", text: $savedSearchName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { context.save(savedSearchName) }
        } message: {
            Text("Saved searches remain in Scholium’s Application Support folder and never modify a vault.")
        }
        .alert("Rename Saved Search", isPresented: Binding(
            get: { renamingSearch != nil },
            set: { if !$0 { renamingSearch = nil } }
        )) {
            TextField("Search name", text: $renamedSearchName)
            Button("Cancel", role: .cancel) { renamingSearch = nil }
            Button("Rename") {
                if let renamingSearch {
                    context.rename(renamingSearch.id, renamedSearchName)
                }
                renamingSearch = nil
            }
            .disabled(renamedSearchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                "",
                text: query,
                prompt: Text("Spotlight Search").foregroundStyle(.secondary)
            )
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1)
                .focused($searchFocused)
                .accessibilityIdentifier("scholium.searchField")
                .accessibilityLabel("Search")
                .onSubmit {
                    if controller.search.isRunning
                        || controller.search.criteria.selectedResultID == nil {
                        Task { await context.refresh() }
                    } else {
                        openSelectedResult()
                    }
                }

            if !controller.search.criteria.query.isEmpty {
                Button {
                    query.wrappedValue = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
                .help("Clear Search")
                .accessibilityLabel("Clear Search")
            }

            savedSearchesMenu
                .transition(.opacity.combined(with: .scale(scale: 0.9)))

            Button {
                context.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
            .help("Close Search")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("scholium.closeSearchButton")
        }
        .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
        .frame(height: 58)
    }

    private var searchScopeBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                scopePicker
                    .frame(width: ScholiumMetrics.Search.scopeWidth)

                Spacer(minLength: 12)

                searchSummary
            }

            VStack(alignment: .leading, spacing: 8) {
                scopePicker
                    .frame(maxWidth: .infinity)
                searchSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
        .padding(.vertical, 6)
    }

    private var scopePicker: some View {
        Picker("Search scope", selection: scope) {
            ForEach(SearchPresentationScope.visibleModes, id: \.self) { mode in
                Text(mode.displayTitle).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("scholium.searchMode")
    }

    @ViewBuilder
    private var searchSummary: some View {
        if isExpanded, !controller.search.isRunning {
            Text(searchResultSummary)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private var expandedPanelHeight: CGFloat {
        max(
            ScholiumMetrics.Search.collapsedHeight,
            min(
                ScholiumMetrics.Search.expandedHeight,
                maxPanelHeight ?? ScholiumMetrics.Search.expandedHeight
            )
        )
    }

    @ViewBuilder
    private var searchContent: some View {
        if controller.search.isRunning {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.search.hits.isEmpty && controller.search.relatedItems.isEmpty {
            ContentUnavailableView.search(text: controller.search.criteria.query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            results
        }
    }

    private var isExpanded: Bool {
        !controller.search.criteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var savedSearchesMenu: some View {
        Menu {
            Button("Save Current Search…") {
                savedSearchName = controller.search.criteria.query
                showSaveSearch = true
            }
            .disabled(controller.search.criteria.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !context.savedSearches.isEmpty {
                Divider()
                ForEach(Array(context.savedSearches.enumerated()), id: \.element.id) { index, search in
                    Menu(search.name) {
                        Button("Run Search") { context.run(search) }
                        Button("Rename…") {
                            renamedSearchName = search.name
                            renamingSearch = search
                        }
                        Divider()
                        Button("Move Up") { context.move(search.id, -1) }
                            .disabled(index == 0)
                        Button("Move Down") { context.move(search.id, 1) }
                            .disabled(index == context.savedSearches.count - 1)
                        Divider()
                        Button("Delete", role: .destructive) {
                            context.delete(search.id)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "bookmark")
        }
        .buttonStyle(.glass)
        .help("Saved Searches")
        .accessibilityLabel("Saved Searches")
    }

    private var query: Binding<String> {
        Binding(
            get: { controller.search.criteria.query },
            set: { value in
                controller.updateSearchQuery(value)
                PerformanceProbe.shared.beginSearch(
                    query: value.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                scheduleSearch()
            }
        )
    }

    private var scope: Binding<SearchPresentationScope> {
        Binding(
            get: { controller.search.criteria.scope.canonical },
            set: { value in
                controller.selectSearchScope(value)
                scheduleSearch(immediate: true)
            }
        )
    }

    private var results: some View {
        List(selection: selectedResult) {
            if !controller.search.hits.isEmpty {
                Section("Search Results") {
                    ForEach(controller.search.hits, id: \.self) { hit in
                        let resultID = SearchResultIdentity.lexical(hit)
                        Button {
                            controller.selectSearchResult(resultID)
                            open(.lexical(hit))
                        } label: {
                            WorkspaceSearchResultRow(
                                hit: hit,
                                triptychLabel: Self.triptychLabel(for: hit.vaultRole)
                            )
                        }
                        .buttonStyle(.plain)
                        .tag(resultID)
                        .accessibilityLabel(
                            "\(hit.title), \(hit.context ?? hit.matchedField.rawValue.capitalized), "
                                + "\(hit.vaultName), line \(hit.sourceLine)"
                        )
                        .accessibilityHint("Opens the result at the matching source location")
                        .accessibilityIdentifier("scholium.searchResult.\(hit.relativePath)")
                    }
                }
            }

            if !controller.search.relatedItems.isEmpty {
                Section {
                    ForEach(controller.search.relatedItems) { item in
                        let resultID = SearchResultIdentity.related(item)
                        Button {
                            controller.selectSearchResult(resultID)
                            open(.related(item))
                        } label: {
                            RelatedSearchResultRow(
                                item: item,
                                triptychLabel: Self.triptychLabel(for: item.note.reference.vaultRole)
                            )
                        }
                        .buttonStyle(.plain)
                        .tag(resultID)
                        .accessibilityLabel(
                            "\(item.note.title), \(item.explanation), "
                                + "\(item.note.reference.vaultName)"
                        )
                        .accessibilityHint("Opens this directly connected note")
                        .accessibilityIdentifier(
                            "scholium.relatedSearchResult.\(item.note.reference.relativePath)"
                        )
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Related")
                        Text("Direct Topic connections. Related items do not affect search ranking.")
                            .font(.caption2)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(.clear)
    }

    private var selectedResult: Binding<String?> {
        Binding(
            get: { controller.search.criteria.selectedResultID },
            set: { controller.selectSearchResult($0) }
        )
    }

    private var searchResultSummary: String {
        let searchCount = controller.search.hits.count
        let relatedCount = controller.search.relatedItems.count
        let searchLabel = searchCount == 1 ? "1 Search Result" : "\(searchCount) Search Results"
        guard relatedCount > 0 else { return searchLabel }
        let relatedLabel = relatedCount == 1 ? "1 Related" : "\(relatedCount) Related"
        return "\(searchLabel) — \(relatedLabel)"
    }

    private static let triptychRoles: [(roles: Set<VaultRole>, label: String)] = [
        ([.sourceCorpus], "Analyses"),
        ([.topicKnowledge], "Topics"),
        ([.dissertationControl, .draftProject], "Works"),
    ]

    private static func triptychLabel(for role: VaultRole) -> String {
        triptychRoles.first(where: { $0.roles.contains(role) })?.label ?? "Unclassified"
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        controller.selectSearchResult(nil)
        searchTask = Task {
            if !immediate { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            await context.refresh()
        }
    }

    private func normalizeSelection() {
        let resultIDs = allResultIDs
        if let selected = controller.search.criteria.selectedResultID,
           resultIDs.contains(selected) {
            return
        }
        controller.selectSearchResult(resultIDs.first)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let resultIDs = allResultIDs
        guard !resultIDs.isEmpty, direction == .up || direction == .down else { return }
        let currentIndex = controller.search.criteria.selectedResultID
            .flatMap { resultIDs.firstIndex(of: $0) }
            ?? (direction == .down ? -1 : resultIDs.count)
        let nextIndex = direction == .down
            ? min(currentIndex + 1, resultIDs.count - 1)
            : max(currentIndex - 1, 0)
        controller.selectSearchResult(resultIDs[nextIndex])
    }

    private func openSelectedResult() {
        guard let selected = controller.search.criteria.selectedResultID else {
            return
        }
        if let hit = controller.search.hits.first(where: {
            SearchResultIdentity.lexical($0) == selected
        }) {
            open(.lexical(hit))
            return
        }
        if let item = controller.search.relatedItems.first(where: {
            SearchResultIdentity.related($0) == selected
        }) {
            open(.related(item))
        }
    }

    private func open(_ result: SearchResultSelection) {
        controller.requestOpen(result)
        context.dismiss()
    }

    private var allResultIDs: [String] {
        controller.search.hits.map(SearchResultIdentity.lexical)
            + controller.search.relatedItems.map(SearchResultIdentity.related)
    }
}

private struct WorkspaceSearchResultRow: View {
    let hit: SearchHit
    let triptychLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(hit.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(hit.vaultName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(highlightedSnippet)
                .font(.body)
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(hit.context ?? hit.matchedField.rawValue.capitalized)
                Text("Line \(hit.sourceLine)")
                Text(triptychLabel)
                Text("Retrieval lead")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .frame(minHeight: ScholiumMetrics.Search.resultRowHeight)
    }

    private var highlightedSnippet: AttributedString {
        var result = AttributedString(hit.snippet)
        let utf16Count = hit.snippet.utf16.count
        for highlight in hit.highlights
        where highlight.utf16LowerBound >= 0
            && highlight.utf16UpperBound >= highlight.utf16LowerBound
            && highlight.utf16UpperBound <= utf16Count {
            let lower = String.Index(utf16Offset: highlight.utf16LowerBound, in: hit.snippet)
            let upper = String.Index(utf16Offset: highlight.utf16UpperBound, in: hit.snippet)
            guard let lower = AttributedString.Index(lower, within: result),
                  let upper = AttributedString.Index(upper, within: result) else { continue }
            result[lower..<upper].backgroundColor = .yellow.opacity(0.45)
        }
        return result
    }
}

private struct RelatedSearchResultRow: View {
    let item: RelatedSearchItem
    let triptychLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(item.note.reference.vaultName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(item.explanation)
                .font(.body)
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(triptychLabel)
                Text(item.note.reference.relativePath)
                Text("Graph relation")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .frame(minHeight: ScholiumMetrics.Search.resultRowHeight)
    }
}
