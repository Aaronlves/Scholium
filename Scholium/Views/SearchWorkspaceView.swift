import ScholiumContracts
import AppKit
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

/// Search-local mapping from provider-owned availability into the shared
/// presentation meanings in `Design.md`. It is deliberately not a runtime
/// state owner: Search providers retain their typed availability and
/// transitions, while this value owns only visible wording, tone, and action.
enum SearchStatePresentationMeaning: Equatable, Sendable {
    case loading
    case unavailable
    case stale
    case error

    var colorRole: ScholiumColorRole {
        switch self {
        case .loading:
            .information
        case .unavailable, .stale:
            .attention
        case .error:
            .destructive
        }
    }
}

enum SearchStateBannerAction: Equatable, Sendable {
    case refresh
    case retry

    var title: String {
        switch self {
        case .refresh:
            String(localized: "Refresh")
        case .retry:
            String(localized: "Retry")
        }
    }
}

struct SearchStateBannerPresentation: Equatable, Sendable {
    let meaning: SearchStatePresentationMeaning
    let title: String
    let message: String
    let systemImage: String
    let action: SearchStateBannerAction?
}

enum SearchStatePresentation {
    static func executionIssue(
        _ issue: SearchExecutionIssue
    ) -> SearchStateBannerPresentation {
        switch issue {
        case .unavailable(let message):
            SearchStateBannerPresentation(
                meaning: .unavailable,
                title: String(localized: "Search Unavailable"),
                message: message,
                systemImage: "magnifyingglass.circle",
                action: nil
            )
        case .failed(let message):
            SearchStateBannerPresentation(
                meaning: .error,
                title: String(localized: "Search Failed"),
                message: message,
                systemImage: "exclamationmark.triangle",
                action: .retry
            )
        }
    }

    static func note(
        _ availability: SearchAvailability
    ) -> SearchStateBannerPresentation? {
        switch availability {
        case .unavailable:
            SearchStateBannerPresentation(
                meaning: .unavailable,
                title: String(localized: "Search Index Unavailable"),
                message: String(localized: "No complete local Search index is available for this Triptych."),
                systemImage: "magnifyingglass.circle",
                action: .refresh
            )
        case .building(let progress):
            SearchStateBannerPresentation(
                meaning: .loading,
                title: String(localized: "Building Search Index"),
                message: progress.total > 0
                    ? String(localized: "Indexed \(progress.completed) of \(progress.total) notes.")
                    : String(localized: "Preparing the local Triptych index."),
                systemImage: "arrow.triangle.2.circlepath",
                action: nil
            )
        case .current:
            nil
        case .refreshing:
            SearchStateBannerPresentation(
                meaning: .loading,
                title: String(localized: "Refreshing Search Index"),
                message: String(localized: "Showing results from the last complete index while the replacement is built."),
                systemImage: "arrow.triangle.2.circlepath",
                action: nil
            )
        case .stale(_, let reason):
            SearchStateBannerPresentation(
                meaning: .stale,
                title: String(localized: "Search Index Is Stale"),
                message: String(localized: "The last complete Search index remains available. Details: \(reason)"),
                systemImage: "clock.badge.exclamationmark",
                action: .refresh
            )
        case .failed(let lastGood, let reason):
            SearchStateBannerPresentation(
                meaning: .error,
                title: String(localized: "Search Index Failed"),
                message: lastGood == nil
                    ? String(localized: "Scholium could not build a usable Search index. Details: \(reason)")
                    : String(localized: "Scholium could not publish a replacement Search index. The last complete results remain available. Details: \(reason)"),
                systemImage: "exclamationmark.triangle",
                action: .retry
            )
        }
    }

    static func record(
        _ availability: RecordSearchAvailability
    ) -> SearchStateBannerPresentation? {
        switch availability {
        case .unavailable:
            SearchStateBannerPresentation(
                meaning: .unavailable,
                title: String(localized: "Research Record Search Unavailable"),
                message: String(localized: "No complete Research Record search projection is available."),
                systemImage: "magnifyingglass.circle",
                action: .refresh
            )
        case .building(let progress):
            SearchStateBannerPresentation(
                meaning: .loading,
                title: String(localized: "Preparing Research Records"),
                message: progress.total > 0
                    ? String(localized: "Prepared \(progress.completed) of \(progress.total) records.")
                    : String(localized: "Preparing the Research Record search projection."),
                systemImage: "arrow.triangle.2.circlepath",
                action: nil
            )
        case .current:
            nil
        case .refreshing:
            SearchStateBannerPresentation(
                meaning: .loading,
                title: String(localized: "Refreshing Research Records"),
                message: String(localized: "Showing results from the last complete Research Record search projection while the replacement is prepared."),
                systemImage: "arrow.triangle.2.circlepath",
                action: nil
            )
        case .stale(_, let reason):
            SearchStateBannerPresentation(
                meaning: .stale,
                title: String(localized: "Research Record Search Is Stale"),
                message: String(localized: "The last complete Research Record search projection remains available. Details: \(reason)"),
                systemImage: "clock.badge.exclamationmark",
                action: .refresh
            )
        case .failed(let lastGood, let reason):
            SearchStateBannerPresentation(
                meaning: .error,
                title: String(localized: "Research Record Search Failed"),
                message: lastGood == nil
                    ? String(localized: "Scholium could not build a usable Research Record search projection. Details: \(reason)")
                    : String(localized: "Scholium could not publish a replacement Research Record search projection. The last complete results remain available. Details: \(reason)"),
                systemImage: "exclamationmark.triangle",
                action: .retry
            )
        }
    }

    static func suppressesNoMatchContent(
        for availability: SearchProviderAvailability,
        scope: SearchPresentationScope,
        hasExecutionIssue: Bool
    ) -> Bool {
        if hasExecutionIssue { return true }
        if scope == .thisNote { return false }
        return switch availability {
        case .note(.unavailable), .note(.building),
             .note(.failed(lastGood: nil, reason: _)),
             .record(.unavailable), .record(.building),
             .record(.failed(lastGood: nil, reason: _)):
            true
        case .note, .record:
            false
        }
    }
}

struct SpotlightSearchPanelView: View {
    @ObservedObject private var controller: DiscoveryController
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @Environment(\.scholiumIncreasedContrast) private var increasedContrast
    let context: SpotlightSearchContext
    let maxPanelHeight: CGFloat?
    @FocusState private var searchFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    @State private var compositionTask: Task<Void, Never>?
    @State private var queryDraft = ""
    @State private var showSaveSearch = false
    @State private var savedSearchName = ""
    @State private var renamingSearch: SavedSearch?
    @State private var renamedSearchName = ""
    @State private var completionSelection: Int?
    @State private var suppressedCompletionQuery: String?

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

            if !visibleCompletions.isEmpty {
                completionList
            }

            if let diagnostic = controller.search.diagnostics.first {
                searchDiagnostic(diagnostic)
            }

            Divider()
                .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)

            searchScopeBar

            if let explanationText {
                Text(explanationText)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
                    .padding(.bottom, ScholiumMetrics.Search.explanationBottomInset)
                    .accessibilityLabel("Explain Query: \(explanationText)")
            }

            if isExpanded {
                searchAvailabilityBanner

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
        .scholiumEditorialSurface(
            .searchOverlay,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.searchOverlayCornerRadius,
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
            queryDraft = controller.search.criteria.query
            searchFocused = true
            normalizeSelection()
        }
        .onChange(of: controller.search.criteria.query) { _, value in
            guard value != queryDraft, !searchFieldHasMarkedText else { return }
            queryDraft = value
            completionSelection = nil
            suppressedCompletionQuery = nil
        }
        .onChange(of: controller.search.results) { _, _ in
            normalizeSelection()
        }
        .background {
            if !controller.search.isRunning,
               !controller.search.criteria.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PerformanceReadyBoundary(
                    generation: [
                        controller.search.criteria.query,
                        String(controller.search.results.count),
                        String(controller.search.hasMore),
                    ].joined(separator: ":")
                ) {
                    PerformanceProbe.shared.markSearchResultsReady(
                        query: controller.search.criteria.query,
                        resultCount: controller.search.results.count
                    )
                }
                .frame(width: 0, height: 0)
            }
        }
        .onMoveCommand(perform: moveSelection)
        .onDisappear {
            searchTask?.cancel()
            compositionTask?.cancel()
        }
        .onExitCommand {
            if !visibleCompletions.isEmpty {
                suppressedCompletionQuery = queryDraft
                completionSelection = nil
                searchFocused = true
            } else {
                context.dismiss()
            }
        }
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
        HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Image(systemName: "magnifyingglass")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.secondaryText)
                .accessibilityHidden(true)

            TextField(
                "",
                text: query,
                prompt: Text("Spotlight Search")
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            )
                .textFieldStyle(.plain)
                .font(ScholiumTypography.interface(.body))
                .lineLimit(1)
                .focused($searchFocused)
                .accessibilityIdentifier("scholium.searchField")
                .accessibilityLabel("Search")
                .onKeyPress(.downArrow) {
                    if !moveCompletion(.down) { moveSelection(.down) }
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    if !moveCompletion(.up) { moveSelection(.up) }
                    return .handled
                }
                .onKeyPress(.tab) {
                    acceptCompletion(preferFirst: true) ? .handled : .ignored
                }
                .onSubmit {
                    compositionTask?.cancel()
                    if acceptCompletion(preferFirst: false) { return }
                    let changed = applyQueryDraft()
                    if changed || controller.search.isRunning
                        || controller.search.selectedResultID == nil {
                        scheduleSearch()
                    } else {
                        openSelectedResult()
                    }
                }

            if !queryDraft.isEmpty {
                Button {
                    query.wrappedValue = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scholiumForeground(.secondaryText)
                }
                .buttonStyle(.plain)
                .frame(
                    minWidth: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
                )
                .contentShape(Rectangle())
                .help("Clear Search")
                .accessibilityLabel("Clear Search")
            }

            savedSearchesMenu

            Button {
                context.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .scholiumForeground(.secondaryText)
            }
            .buttonStyle(.borderless)
            .frame(
                minWidth: ScholiumMetrics.Accessibility.preferredCustomTarget,
                minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
            .contentShape(Rectangle())
            .keyboardShortcut(.cancelAction)
            .help("Close Search")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("scholium.closeSearchButton")
        }
        .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
        .frame(height: ScholiumGrid.Dimension.regionHeaderHeight)
    }

    private var searchScopeBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: ScholiumGrid.Spacing.nestedContentInset) {
                scopePicker
                    .frame(width: ScholiumMetrics.Search.scopeWidth)

                Spacer(minLength: ScholiumGrid.Spacing.nestedContentInset)

                searchSummary
            }

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                scopePicker
                    .frame(maxWidth: .infinity)
                searchSummary
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
        .padding(.vertical, ScholiumMetrics.Search.scopeBarVerticalInset)
    }

    private var visibleCompletions: [SearchCompletion] {
        guard searchFocused,
              suppressedCompletionQuery != queryDraft,
              !searchFieldHasMarkedText else { return [] }
        return SearchCapabilities.current.completions(for: queryDraft)
    }

    private var completionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleCompletions.enumerated()), id: \.element.id) {
                index, completion in
                Button {
                    apply(completion)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: ScholiumMetrics.Search.resultContentSpacing) {
                        Text(completion.displayText)
                            .font(ScholiumTypography.exact(.body))
                        Text(completion.detail)
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
                    .frame(minHeight: 32)
                    .background(
                        completionSelection == index
                            ? ScholiumColorRole.raisedSurfaceBackground.color
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(completion.displayText), \(completion.detail)")
                .accessibilityAddTraits(
                    completionSelection == index ? .isSelected : []
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search query completions")
    }

    private func moveCompletion(_ direction: MoveCommandDirection) -> Bool {
        let completions = visibleCompletions
        guard !completions.isEmpty else { return false }
        let current = completionSelection
            ?? (direction == .down ? -1 : completions.count)
        completionSelection = direction == .down
            ? min(current + 1, completions.count - 1)
            : max(current - 1, 0)
        controller.selectSearchResult(nil)
        return true
    }

    private func acceptCompletion(preferFirst: Bool) -> Bool {
        let completions = visibleCompletions
        guard !completions.isEmpty,
              let index = completionSelection ?? (preferFirst ? 0 : nil),
              completions.indices.contains(index) else { return false }
        apply(completions[index])
        return true
    }

    private func apply(_ completion: SearchCompletion) {
        queryDraft = completion.replacementText
        completionSelection = nil
        suppressedCompletionQuery = completion.replacementText
        _ = applyQueryDraft()
        searchFocused = true
    }

    private func searchDiagnostic(_ diagnostic: SearchQueryDiagnostic) -> some View {
        let message = localizedDiagnostic(diagnostic)
        return Label(message, systemImage: "exclamationmark.circle")
            .font(ScholiumTypography.interface(.small))
            .scholiumForeground(.destructive)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
            .padding(.bottom, ScholiumMetrics.Search.diagnosticBottomInset)
            .accessibilityLabel(String(localized: "Invalid search query: \(message)"))
    }

    @ViewBuilder
    private var searchAvailabilityBanner: some View {
        if let executionIssue = controller.search.executionIssue {
            operationalBanner(SearchStatePresentation.executionIssue(executionIssue))
        } else if controller.search.criteria.scope == .thisNote {
            EmptyView()
        } else {
            switch controller.search.availability {
            case .record(let availability):
                recordAvailabilityBanner(availability)
            case .note(let availability):
                noteAvailabilityBanner(availability)
            }
        }
    }

    @ViewBuilder
    private func noteAvailabilityBanner(_ availability: SearchAvailability) -> some View {
        if let presentation = SearchStatePresentation.note(availability) {
            operationalBanner(presentation)
        }
    }

    @ViewBuilder
    private func recordAvailabilityBanner(
        _ availability: RecordSearchAvailability
    ) -> some View {
        if let presentation = SearchStatePresentation.record(availability) {
            operationalBanner(presentation)
        }
    }

    private func operationalBanner(
        _ presentation: SearchStateBannerPresentation
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            VStack(alignment: .leading, spacing: ScholiumMetrics.Search.availabilityDetailSpacing) {
                Label(presentation.title, systemImage: presentation.systemImage)
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .scholiumForeground(presentation.meaning.colorRole)
                Text(presentation.message)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            if let action = presentation.action {
                Button(action.title) { Task { await context.refresh() } }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumMetrics.Search.availabilityVerticalInset)
        .background(
            ScholiumColorRole.raisedSurfaceBackground.color(
                increasedContrast: increasedContrast
            ),
            in: ConcentricRectangle()
        )
        .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
    }

    private var scopePicker: some View {
        ScholiumSegmentedControl(
            selection: scope,
            options: SearchPresentationScope.visibleModes.map { mode in
                ScholiumSegmentedControlOption(
                    mode,
                    title: localizedScopeTitle(mode)
                )
            },
            label: String(localized: "Search scope"),
            size: .compact,
            accessibilityIdentifier: "scholium.searchMode"
        )
    }

    @ViewBuilder
    private var searchSummary: some View {
        if isExpanded, !controller.search.isRunning {
            Text(searchResultSummary)
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
                .scholiumForeground(.secondaryText)
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
            ScholiumContentStateView(
                "Searching…",
                indicator: .progress
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !controller.search.diagnostics.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if suppressesNoMatchContent {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.search.results.isEmpty {
            ScholiumContentStateView(
                "No Search Results",
                detail: Text("No results match the current query and scope."),
                indicator: .symbol("magnifyingglass")
            )
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

    private var suppressesNoMatchContent: Bool {
        guard controller.search.results.isEmpty else { return false }
        return SearchStatePresentation.suppressesNoMatchContent(
            for: controller.search.availability,
            scope: controller.search.criteria.scope,
            hasExecutionIssue: controller.search.executionIssue != nil
        )
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
                    Menu {
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
                    } label: {
                        if search.needsEditingDiagnostic != nil {
                            Label(search.name, systemImage: "exclamationmark.triangle")
                        } else {
                            Text(search.name)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "bookmark")
                .scholiumForeground(.secondaryText)
        }
        .buttonStyle(.borderless)
        .frame(
            minWidth: ScholiumMetrics.Accessibility.preferredCustomTarget,
            minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
        )
        .contentShape(Rectangle())
        .help("Saved Searches")
        .accessibilityLabel("Saved Searches")
    }

    private var query: Binding<String> {
        Binding(
            get: { queryDraft },
            set: { value in
                queryDraft = value
                scheduleCompositionAwareQueryCommit(value)
            }
        )
    }

    private var scope: Binding<SearchPresentationScope> {
        Binding(
            get: { controller.search.criteria.scope },
            set: { value in
                controller.selectSearchScope(value)
                scheduleSearch()
            }
        )
    }

    private var results: some View {
        ScrollViewReader { proxy in
            List {
                if !controller.search.results.isEmpty {
                    Section {
                        ForEach(controller.search.results) { result in
                            searchResultButton(result)
                        }
                    } header: {
                        searchSectionHeader("Search Results")
                    }
                }

            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .accessibilityIdentifier("scholium.searchResults")
            .onChange(of: controller.search.selectedResultID) { _, selected in
                guard let selected else { return }
                proxy.scrollTo(selected, anchor: .center)
            }
        }
    }

    private func searchResultButton(_ result: SearchResult) -> some View {
        let resultID = SearchResultIdentity.result(result)
        let accessibilityLabel: String = switch result {
        case .note(let note):
            "\(note.title), \(note.context ?? localizedMatchedField(note.matchedField)), \(note.vaultName), "
                + String(localized: "Line \(note.sourceLine)")
                + (note.searchStructuredReasonDescription.map { ", \($0)" } ?? "")
        case .record(let record):
            "Research Record, \(record.context), \(record.matchedReason)"
        }
        return Button {
            controller.selectSearchResult(resultID)
            open(.result(result))
        } label: {
            WorkspaceSearchResultRow(
                result: result,
                scope: controller.search.criteria.scope
            )
        }
        .buttonStyle(.plain)
        .id(resultID)
        .listRowInsets(searchResultInsets)
        .listRowBackground(resultRowBackground(resultID))
        .listRowSeparatorTint(resultSeparatorColor)
        .accessibilityAddTraits(
            controller.search.selectedResultID == resultID ? .isSelected : []
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the selected Search result")
        .accessibilityIdentifier("scholium.searchResult." + result.id)
    }

    private var searchResultInsets: EdgeInsets {
        EdgeInsets(
            top: ScholiumMetrics.Search.resultVerticalInset,
            leading: ScholiumMetrics.Search.resultHorizontalInset,
            bottom: ScholiumMetrics.Search.resultVerticalInset,
            trailing: ScholiumMetrics.Search.resultHorizontalInset
        )
    }

    private var resultSeparatorColor: Color {
        ScholiumColorRole.separator.color(increasedContrast: increasedContrast)
    }

    @ViewBuilder
    private func resultRowBackground(_ resultID: String) -> some View {
        if controller.search.selectedResultID == resultID {
            ZStack(alignment: .leading) {
                ScholiumColorRole.documentBackground.color(
                    increasedContrast: increasedContrast
                )
                Rectangle()
                    .fill(ScholiumColorRole.accent.color(
                        increasedContrast: increasedContrast
                    ))
                    .frame(width: ScholiumMetrics.Search.selectionIndicatorWidth)
            }
        } else {
            Color.clear
        }
    }

    private func searchSectionHeader(
        _ title: LocalizedStringKey,
        detail: LocalizedStringKey? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
            Text(title)
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .scholiumForeground(.secondaryText)
            if let detail {
                Text(detail)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.mutedText)
            }
        }
        .textCase(nil)
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .accessibilityAddTraits(.isHeader)
    }

    private var searchResultSummary: String {
        let searchCount = controller.search.results.count
        if controller.search.hasMore {
            return String(localized: "\(searchCount)+ Results")
        }
        return searchCount == 1
            ? String(localized: "1 Result")
            : String(localized: "\(searchCount) Results")
    }

    private var explanationText: String? {
        guard controller.search.diagnostics.isEmpty,
              let explanation = controller.search.explanation else { return nil }
        let scope = localizedScopeTitle(explanation.scope)
        let providerName = explanation.provider == .note ? "Notes" : "Research Records"
        let providerSource = explanation.providerWasExplicit ? "explicit" : "default"
        let provider = "\(providerName) (\(providerSource) provider)"
        let clauses = explanation.clauses.map(explanationClause)
        let conjunction: String = switch explanation.operator {
        case .and: " and "
        }
        let query = clauses.isEmpty
            ? "Search \(provider) in \(scope)."
            : "Search \(provider) in \(scope) where "
                + clauses.joined(separator: conjunction) + "."
        let normalization = explanation.normalization
            .map(localizedNormalization)
            .joined(separator: "; ")
        let limitations = explanation.limitations
            .map(localizedLimitation)
            .joined(separator: "; ")
        return query + " Normalization: \(normalization). Ordering: "
            + localizedOrdering(explanation.ordering) + ". Limits: \(limitations)."
    }

    private func explanationClause(_ clause: SearchExplanationClause) -> String {
        switch clause.kind {
        case .lexical(let field, let value, let kind, let excluded):
            let location = field.map { "\($0.rawValue) " } ?? "text "
            let operation = kind == .prefix ? "begins with" : "contains"
            return (excluded ? "not " : "") + location + operation + " ‘\(value)’"
        case .structured(let field, let value, let excluded):
            return (excluded ? "not " : "") + "\(field.rawValue) is \(value)"
        case .property(let key, let value):
            return value.map { "Property \(key) equals ‘\($0)’" }
                ?? "Property \(key) is present"
        case .relation(let direction, let identity, let relation, let symmetric):
            if symmetric {
                return "has a direct undirected \(relation.rawValue) connection with ‘\(identity)’"
            }
            switch (direction, relation) {
            case (.fromNote, .supports):
                return "is directly supported by ‘\(identity)’"
            case (.fromNote, .opposes):
                return "is directly opposed by ‘\(identity)’"
            case (.toNote, .supports):
                return "directly supports ‘\(identity)’"
            case (.toNote, .opposes):
                return "directly opposes ‘\(identity)’"
            case (_, .neutral), (_, .incompatible):
                preconditionFailure("Symmetric relations are handled above.")
            }
        case .record(let field, let value, let kind, let excluded):
            let location = field.map { "\($0.rawValue) " } ?? "record text "
            let operation = kind == .prefix ? "begins with" : "matches"
            return (excluded ? "not " : "") + location + operation + " ‘\(value)’"
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        controller.selectSearchResult(nil)
        searchTask = Task {
            guard !Task.isCancelled else { return }
            await context.refresh()
        }
    }

    private func scheduleCompositionAwareQueryCommit(_ value: String) {
        compositionTask?.cancel()
        compositionTask = Task { @MainActor in
            while searchFieldHasMarkedText {
                do {
                    try await Task.sleep(for: .milliseconds(10))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, queryDraft == value else { return }
            if applyQueryDraft() { scheduleSearch() }
        }
    }

    @discardableResult
    private func applyQueryDraft() -> Bool {
        guard controller.search.criteria.query != queryDraft else { return false }
        controller.updateSearchQuery(queryDraft)
        PerformanceProbe.shared.beginSearch(
            query: queryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return true
    }

    private var searchFieldHasMarkedText: Bool {
        guard searchFocused,
              let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }
        return editor.hasMarkedText()
    }

    private func normalizeSelection() {
        let resultIDs = allResultIDs
        if let selected = controller.search.selectedResultID,
           resultIDs.contains(selected) {
            return
        }
        controller.selectSearchResult(nil)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let resultIDs = allResultIDs
        guard !resultIDs.isEmpty, direction == .up || direction == .down else { return }
        let currentIndex = controller.search.selectedResultID
            .flatMap { resultIDs.firstIndex(of: $0) }
            ?? (direction == .down ? -1 : resultIDs.count)
        let nextIndex = direction == .down
            ? min(currentIndex + 1, resultIDs.count - 1)
            : max(currentIndex - 1, 0)
        controller.selectSearchResult(resultIDs[nextIndex])
    }

    private func openSelectedResult() {
        guard let selected = controller.search.selectedResultID else {
            return
        }
        if let result = controller.search.results.first(where: {
            SearchResultIdentity.result($0) == selected
        }) {
            open(.result(result))
        }
    }

    private func open(_ result: SearchResultSelection) {
        controller.requestOpen(result)
    }

    private var allResultIDs: [String] {
        controller.search.results.map(SearchResultIdentity.result)
    }

    private func localizedScopeTitle(_ scope: SearchPresentationScope) -> String {
        switch scope {
        case .thisNote: String(localized: "This Note")
        case .currentVault: String(localized: "This Vault")
        case .triptych: String(localized: "Triptych")
        }
    }

    private func localizedNormalization(_ rule: SearchExplanationNormalization) -> String {
        switch rule {
        case .canonicalUnicodeCaseWhitespace:
            "canonical Unicode, case, and whitespace"
        case .lexicalUnicodeCaseDiacriticWhitespace:
            "lexical Unicode, case, diacritic, and whitespace normalization"
        case .cjkCharacterAndOverlappingBigramProjection:
            "CJK character and overlapping-bigram projection with substring verification"
        case .caseSensitiveTopLevelPropertyKey:
            "case-sensitive top-level Property keys"
        }
    }

    private func localizedOrdering(_ ordering: SearchExplanationOrdering) -> String {
        switch ordering {
        case .noteExactIdentityThenBM25ThenTitleRolePath:
            "exact Note identity, then one-corpus lexical relevance, then normalized title, vault role, and path"
        case .recordFinishedAtThenUUID:
            "finished time descending, then Record UUID"
        }
    }

    private func localizedLimitation(_ limitation: SearchExplanationLimitation) -> String {
        switch limitation {
        case .authorizedScopeOnly:
            "authorized scope only"
        case .retrievalLeadNotEvidence:
            "retrieval leads are not evidence or researcher judgments"
        case .noCrossProviderRanking:
            "providers are not cross-ranked"
        case .noteRelationsDirectOnly:
            "Note relations are direct and never transitive"
        case .recordNoCrossObjectRelevance:
            "Record lexical matching does not create cross-object relevance"
        }
    }

    private func localizedDiagnostic(_ diagnostic: SearchQueryDiagnostic) -> String {
        switch diagnostic.code {
        case .emptyClause:
            String(localized: "A Search clause cannot be empty.")
        case .unclosedPhrase:
            String(localized: "The quoted phrase is not closed.")
        case .invalidEscape:
            String(localized: "Only escaped quotes and backslashes are valid inside a Search phrase.")
        case .invalidPrefix:
            String(localized: "A prefix must contain at least two non-CJK characters and place * only at the end.")
        case .cjkPrefixUnsupported:
            String(localized: "CJK clauses do not use *. Continuous character matching is automatic.")
        case .unknownField:
            String(localized: "This Search field is not supported.")
        case .unsupportedField:
            String(localized: "This known Search field is not available in the current contract.")
        case .providerMismatch:
            String(localized: "This field does not apply to the selected Search provider.")
        case .unsupportedScopeSelector:
            String(localized: "Choose Search scope with the visible scope control.")
        case .duplicateClause:
            String(localized: "This Search clause may appear only once.")
        case .missingCompanion:
            String(localized: "This Search clause requires its companion clause.")
        case .ambiguousIdentity:
            diagnostic.message
        case .notApplicable:
            diagnostic.message
        case .missingFieldValue:
            String(localized: "This Search field requires a value.")
        case .unknownStructuredValue:
            String(localized: "This structured value is not a canonical Scholium value.")
        case .unsupportedSyntax:
            String(localized: "This syntax is outside Scholium’s finite Search grammar.")
        case .onlyExcludedFreeText:
            String(localized: "Add a positive term or a structured callout or broken-link condition.")
        case .needsEditing:
            diagnostic.message
        }
    }

    private func localizedMatchedField(_ field: SearchMatchedField) -> String {
        switch field {
        case .title: String(localized: "title")
        case .alias: String(localized: "alias")
        case .heading: String(localized: "heading")
        case .summary: String(localized: "summary")
        case .author: String(localized: "author")
        case .publicationDate: String(localized: "publication date")
        case .tag: String(localized: "tag")
        case .path: String(localized: "path")
        case .callout: String(localized: "callout")
        case .footnote: String(localized: "footnote")
        case .brokenLink: String(localized: "broken link")
        case .body: String(localized: "body")
        }
    }

}

private extension NoteSearchResult {
    var searchStructuredReasonDescription: String? {
        for reason in matchReasons {
            switch reason {
            case .lexical:
                continue
            case .property(let property):
                if let value = property.normalizedValue {
                    return "property:\(property.key)=\(value)"
                }
                return property.isEmpty
                    ? "property:\(property.key) (present-empty)"
                    : "property:\(property.key) (\(property.valueKind.rawValue))"
            case .relationship(let relationship):
                let source = relationship.occurrences.first.map {
                    " @ \($0.sourceNote.relativePath):\($0.locator.line)"
                } ?? ""
                return "\(relationship.direction.rawValue):\(relationship.anchorIdentity) "
                    + "relation:\(relationship.relation.rawValue)" + source
            }
        }
        return nil
    }
}

private struct WorkspaceSearchResultRow: View {
    let result: SearchResult
    let scope: SearchPresentationScope

    @ViewBuilder
    var body: some View {
        switch result {
        case .note(let note):
            NoteSearchResultRow(note: note, scope: scope)
        case .record(let record):
            RecordSearchResultRow(record: record)
        }
    }
}

private struct NoteSearchResultRow: View {
    let note: NoteSearchResult
    let scope: SearchPresentationScope

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Search.savedSearchFieldSpacing) {
            HStack {
                Text(note.title)
                    .font(ScholiumTypography.interface(.rowTitle))
                    .lineLimit(1)
                Spacer()
                Text(note.vaultName)
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .lineLimit(1)
            }

            Text(highlightedSnippet)
                .font(ScholiumTypography.scholarly(.body))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text(note.vaultRole.displayName)
                Text(parentPath)
                if scope == .thisNote {
                    Text(String(localized: "Line \(note.sourceRange?.line ?? note.sourceLine), Column \(note.sourceRange?.column ?? 1)"))
                }
                if let reason = note.searchStructuredReasonDescription {
                    Text(reason)
                        .lineLimit(1)
                } else {
                    Text(rankDescription)
                }
                Text("Retrieval lead")
            }
            .font(ScholiumTypography.interface(.small, emphasis: .medium))
            .scholiumForeground(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .frame(minHeight: ScholiumMetrics.Search.resultRowHeight)
    }

    private var highlightedSnippet: AttributedString {
        var result = AttributedString(note.snippet)
        let utf16Count = note.snippet.utf16.count
        for highlight in note.highlights
        where highlight.utf16LowerBound >= 0
            && highlight.utf16UpperBound >= highlight.utf16LowerBound
            && highlight.utf16UpperBound <= utf16Count {
            let lower = String.Index(utf16Offset: highlight.utf16LowerBound, in: note.snippet)
            let upper = String.Index(utf16Offset: highlight.utf16UpperBound, in: note.snippet)
            guard let lower = AttributedString.Index(lower, within: result),
                  let upper = AttributedString.Index(upper, within: result) else { continue }
            result[lower..<upper].backgroundColor =
                ScholiumNativeColorRole.searchMatchHighlight.color
        }
        return result
    }

    private var parentPath: String {
        let parent = (note.relativePath as NSString).deletingLastPathComponent
        return parent.isEmpty ? String(localized: "Root") : parent
    }

    private var rankDescription: String {
        switch note.rankReason {
        case .exactTitle: String(localized: "Exact title")
        case .exactAlias: String(localized: "Exact alias")
        case .exactFilename: String(localized: "Exact filename")
        case .exactPath: String(localized: "Exact path")
        case .lexicalRelevance: String(localized: "Matched \(localizedMatchedField)")
        case .structuredFilter: String(localized: "Structured filter")
        }
    }

    private var localizedMatchedField: String {
        switch note.matchedField {
        case .title: String(localized: "title")
        case .alias: String(localized: "alias")
        case .heading: String(localized: "heading")
        case .summary: String(localized: "summary")
        case .author: String(localized: "author")
        case .publicationDate: String(localized: "publication date")
        case .tag: String(localized: "tag")
        case .body: String(localized: "body")
        case .callout: String(localized: "callout")
        case .footnote: String(localized: "footnote")
        case .brokenLink: String(localized: "broken link")
        case .path: String(localized: "path")
        }
    }
}

private struct RecordSearchResultRow: View {
    let record: RecordSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumMetrics.Search.savedSearchFieldSpacing) {
            HStack {
                Text(record.context)
                    .font(ScholiumTypography.interface(.rowTitle))
                    .lineLimit(1)
                Spacer()
                Text("Research Record")
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
            }
            Text(record.snippet)
                .font(ScholiumTypography.scholarly(.body))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if let actionID = record.actionID { Text(actionID) }
                if let methodName = record.methodName { Text(methodName) }
                Text(record.matchedReason)
                if let author = record.statementAuthor {
                    Text(author == .researcher ? "Researcher" : "Agent")
                }
                Text("Retrieval lead")
            }
            .font(ScholiumTypography.interface(.small, emphasis: .medium))
            .scholiumForeground(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .frame(minHeight: ScholiumMetrics.Search.resultRowHeight)
    }
}
