import ScholiumContracts
import AppKit
import SwiftUI

/// Immutable window projection and actions used by the Search presentation.
/// Search state itself remains owned by `DiscoveryController`; persistence and
/// presentation routing stay explicit at the `ContentView` composition root.
struct ResearchSearchContext {
    let completionContext: SearchCompletionContext
    let savedSearches: [SavedSearch]
    let savedSearchLoadFailure: String?
    let recoverSavedSearches: () async -> Void
    let refresh: () async -> Void
    let dismiss: () -> Void
    let save: (String) -> Void
    let run: (SavedSearch) -> Void
    let rename: (UUID, String) -> Void
    let move: (UUID, Int) -> Void
    let delete: (UUID) -> Void
    let openNote: (SearchResultSelection) -> Void
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
    /// Availability is evidence returned for a query, not the initial value of
    /// an unqueried Search projection. Never display that default as a failure.
    static func status(for state: DiscoverySearchState) -> SearchStateBannerPresentation? {
        guard !state.criteria.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let issue = state.executionIssue { return executionIssue(issue) }
        guard !state.isRunning, state.responseRequestID != nil,
              state.criteria.scope != .thisNote else { return nil }
        return note(state.availability)
    }

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
        case .limited:
            SearchStateBannerPresentation(
                meaning: .unavailable,
                title: String(localized: "Search Limited to This Vault"),
                message: String(localized: "Showing indexed matches whose source is unchanged in this vault. New or externally changed notes appear after the Triptych finishes opening."),
                systemImage: "magnifyingglass.circle",
                action: nil
            )
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

    static func suppressesNoMatchContent(
        for availability: SearchAvailability,
        scope: SearchPresentationScope,
        hasExecutionIssue: Bool
    ) -> Bool {
        if hasExecutionIssue { return true }
        if scope == .thisNote { return false }
        return switch availability {
        case .unavailable, .building, .failed(lastGood: nil, reason: _):
            true
        case .current, .limited, .refreshing, .stale,
             .failed(lastGood: .some, reason: _):
            false
        }
    }
}

struct ResearchSearchView<Library: View>: View {
    @ObservedObject private var controller: DiscoveryController
    let context: ResearchSearchContext
    @ObservedObject var searchController: WindowSearchController
    let presentation: SearchPresentation
    let library: Library
    @State private var searchFocused = false
    @State private var searchTask: Task<Void, Never>?
    private var queryDraft: String {
        get { controller.search.criteria.query }
        nonmutating set {
            guard controller.search.criteria.query != newValue else { return }
            if !isActive {
                if isAdvanced { searchController.beginAdvanced() }
                else { searchController.begin(.general) }
            }
            suppressedCompletionQuery = nil
            controller.updateSearchQuery(newValue)
            PerformanceProbe.shared.beginSearch(query: newValue.trimmingCharacters(in: .whitespacesAndNewlines))
            scheduleSearch()
        }
    }
    @State private var showSaveSearch = false
    @State private var savedSearchName = ""
    @State private var renamingSearch: SavedSearch?
    @State private var renamedSearchName = ""
    @State private var completionSelection: Int?
    @State private var suppressedCompletionQuery: String?
    @State private var confirmsSavedSearchRecovery = false
    @State private var showsQueryExplanation = false

    init(
        controller: DiscoveryController,
        searchController: WindowSearchController,
        context: ResearchSearchContext,
        presentation: SearchPresentation,
        @ViewBuilder library: () -> Library
    ) {
        self.controller = controller
        self.searchController = searchController
        self.context = context
        self.presentation = presentation
        self.library = library()
    }

    private var isActive: Bool { searchController.presentation == presentation }
    private var isAdvanced: Bool { presentation == .advanced }
    private var showsResults: Bool { isActive && (isAdvanced || isExpanded) }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            ZStack(alignment: .top) {
                library
                    .opacity(showsResults ? 0 : 1)
                    .allowsHitTesting(!showsResults)
                    .accessibilityHidden(showsResults)
                if showsResults {
                    VStack(spacing: 0) {
                        searchScopeBar
                        if !visibleCompletions.isEmpty { completionList }
                        if let diagnostic = controller.search.diagnostics.first {
                            searchDiagnostic(diagnostic)
                        }
                        searchAvailabilityBanner
                        searchContent
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("scholium.searchWorkspace")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .onAppear {
            normalizeSelection()
            if isActive, !queryDraft.isEmpty { scheduleSearch() }
        }
        .onChange(of: controller.search.criteria.query) { _, _ in
            completionSelection = nil
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
        .onChange(of: isActive) { _, active in
            if !active { completionSelection = nil }
            if active, !queryDraft.isEmpty, controller.search.results.isEmpty { scheduleSearch() }
        }
        .onMoveCommand { if isActive { moveSelection($0) } }
        .onDisappear {
            searchTask?.cancel()
        }
        .onExitCommand {
            guard isActive else { return }
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
            .scholiumActivationPointer()
            Button("Save") { context.save(savedSearchName) }
            .scholiumActivationPointer()
        } message: {
            Text("Saved searches remain in Scholium’s Application Support folder and never modify a vault.")
        }
        .alert("Rename Saved Search", isPresented: Binding(
            get: { renamingSearch != nil },
            set: { if !$0 { renamingSearch = nil } }
        )) {
            TextField("Search name", text: $renamedSearchName)
            Button("Cancel", role: .cancel) { renamingSearch = nil }
            .scholiumActivationPointer()
            Button("Rename") {
                if let renamingSearch {
                    context.rename(renamingSearch.id, renamedSearchName)
                }
                renamingSearch = nil
            }
            .scholiumActivationPointer()
            .disabled(renamedSearchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Archive Unreadable Saved Searches?",
            isPresented: $confirmsSavedSearchRecovery,
            titleVisibility: .visible
        ) {
            Button("Archive and Reset", role: .destructive) {
                Task { await context.recoverSavedSearches() }
            }
            .scholiumActivationPointer()
            Button("Cancel", role: .cancel) {}
            .scholiumActivationPointer()
        } message: {
            Text("Scholium will preserve the unreadable Saved Search file under a unique recovery name, then start with an empty Saved Searches list. No vault files will be changed.")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            ResearchSearchField(
                text: query,
                placeholder: "\(ScholiumL10n.string("Search")) · \(localizedScopeTitle(controller.search.criteria.scope))",
                scope: scope,
                openAdvanced: isAdvanced ? nil : { searchController.beginAdvanced() },
                isActive: isActive,
                focusRequestID: isActive ? searchController.focusRequestID : nil,
                replacementID: searchController.inputReplacementID,
                beganEditing: {
                    searchFocused = true
                },
                endedEditing: { searchFocused = false },
                command: handleSearchCommand
            )
            if isActive && !isAdvanced {
                Button(action: context.dismiss) { Image(systemName: "xmark") }
                    .scholiumButtonStyle(.borderless)
                    .help("Close Search")
                    .accessibilityLabel("Close Search")
                    .accessibilityIdentifier("scholium.closeSearchButton")
            }
        }
        .padding(.horizontal, isAdvanced ? 24 : ScholiumSidebarLayout.edgeInset)
        .padding(.top, isAdvanced ? 20 : 10)
        .padding(.bottom, isAdvanced ? 4 : 8)
    }

    private func handleSearchCommand(_ command: ResearchSearchField.Command) -> Bool {
        switch command {
        case .down:
            if !moveCompletion(.down) { moveSelection(.down) }
        case .up:
            if !moveCompletion(.up) { moveSelection(.up) }
        case .complete:
            return acceptCompletion(preferFirst: true)
        case .submit:
            if acceptCompletion(preferFirst: false) { return true }
            if controller.search.isRunning || controller.search.selectedResultID == nil {
                scheduleSearch()
            } else { openSelectedResult() }
        case .cancel:
            if !visibleCompletions.isEmpty {
                suppressedCompletionQuery = queryDraft
                completionSelection = nil
            } else { context.dismiss() }
        }
        return true
    }

    private var searchScopeBar: some View {
        HStack(spacing: 12) {
            Text(localizedScopeTitle(controller.search.criteria.scope))
                .lineLimit(1)
            searchSummary
            Spacer(minLength: 0)
            if isAdvanced {
                savedSearchesMenu
                Button { showsQueryExplanation = true } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .help("Explain Query")
                .accessibilityLabel("Explain Query")
                .disabled(explanationText == nil)
                .popover(isPresented: $showsQueryExplanation) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Explain Query").font(ScholiumTypography.interface(.sectionTitle))
                        ScrollView {
                            Text(explanationText ?? "")
                                .font(ScholiumTypography.interface(.body))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                    }
                    .padding(20)
                    .frame(width: 360)
                    .accessibilityIdentifier("scholium.searchExplanation")
                }
            }
        }
        .font(ScholiumTypography.interface(.small))
        .scholiumForeground(.secondaryText)
        .controlSize(.small)
        .tint(ScholiumColorRole.primaryText.color)
        .padding(.horizontal, isAdvanced ? 24 : ScholiumSidebarLayout.edgeInset)
        .padding(.top, isAdvanced ? 8 : 0)
        .padding(.bottom, 12)
    }

    private var visibleCompletions: [SearchCompletion] {
        guard isAdvanced, searchFocused,
              suppressedCompletionQuery != queryDraft,
              !searchFieldHasMarkedText else { return [] }
        return SearchCapabilities.current.completions(
            for: queryDraft,
            scope: controller.search.criteria.scope,
            provider: .note,
            context: context.completionContext
        )
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
                .scholiumActivationPointer()
                .scholiumButtonStyle(.plain)
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
        searchController.replaceQuery(completion.replacementText)
        scheduleSearch()
        completionSelection = nil
        suppressedCompletionQuery = completion.replacementText
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
        if let presentation = SearchStatePresentation.status(for: controller.search),
           !blocksResults || !controller.search.results.isEmpty {
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
                    .scholiumActivationPointer()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumMetrics.Search.availabilityVerticalInset)
        .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
    }

    @ViewBuilder
    private var searchSummary: some View {
        if isExpanded, !controller.search.isRunning {
            Text(searchResultSummary)
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.secondaryText)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if !isExpanded {
            ContentUnavailableView("Search Notes", systemImage: "magnifyingglass",
                                   description: Text("Enter a search term to begin."))
                .accessibilityIdentifier("scholium.searchReady")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.search.isRunning {
            ProgressView("Searching…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !controller.search.diagnostics.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if blocksResults,
                  let presentation = SearchStatePresentation.status(for: controller.search) {
            ContentUnavailableView {
                Label(presentation.title, systemImage: presentation.systemImage)
            } description: {
                Text(presentation.message)
            } actions: {
                if let action = presentation.action {
                    Button(action.title) { Task { await context.refresh() } }
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.search.results.isEmpty {
            ContentUnavailableView("No Search Results", systemImage: "magnifyingglass",
                                   description: Text("No results match the current query and scope."))
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

    private var blocksResults: Bool {
        guard controller.search.results.isEmpty else { return false }
        return SearchStatePresentation.suppressesNoMatchContent(
            for: controller.search.availability, scope: controller.search.criteria.scope,
            hasExecutionIssue: controller.search.executionIssue != nil)
    }

    private var savedSearchesMenu: some View {
        Menu {
            Button("Save Current Search…") {
                savedSearchName = controller.search.criteria.query
                showSaveSearch = true
            }
            .scholiumActivationPointer()
            .disabled(controller.search.criteria.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !context.savedSearches.isEmpty {
                Divider()
                ForEach(Array(context.savedSearches.enumerated()), id: \.element.id) { index, search in
                    Menu {
                        Button("Run Search") { context.run(search) }
                        .scholiumActivationPointer()
                        Button("Rename…") {
                            renamedSearchName = search.name
                            renamingSearch = search
                        }
                        .scholiumActivationPointer()
                        Divider()
                        Button("Move Up") { context.move(search.id, -1) }
                            .scholiumActivationPointer()
                            .disabled(index == 0)
                        Button("Move Down") { context.move(search.id, 1) }
                            .scholiumActivationPointer()
                            .disabled(index == context.savedSearches.count - 1)
                        Divider()
                        Button("Delete", role: .destructive) {
                            context.delete(search.id)
                        }
                        .scholiumActivationPointer()
                    } label: {
                        if search.needsEditingDiagnostic != nil {
                            Label(search.name, systemImage: "exclamationmark.triangle")
                        } else {
                            Text(search.name)
                        }
                    }
                    .scholiumActivationPointer()
                }
            }
            if context.savedSearchLoadFailure != nil {
                Divider()
                Button("Archive Unreadable Saved Searches…", role: .destructive) {
                    confirmsSavedSearchRecovery = true
                }
                .scholiumActivationPointer()
            }
        } label: {
            Text("Saved Searches")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Saved Searches")
        .accessibilityLabel("Saved Searches")
    }

    private var query: Binding<String> {
        Binding(
            get: { queryDraft },
            set: { value in
                queryDraft = value

            }
        )
    }

    private var scope: Binding<SearchPresentationScope> {
        Binding(
            get: { controller.search.criteria.scope },
            set: { value in
                controller.selectSearchScope(value)
                if isActive { scheduleSearch() }
            }
        )
    }

    private var results: some View {
        ScrollViewReader { proxy in
            List(selection: Binding(get: { controller.search.selectedResultID },
                                    set: { controller.selectSearchResult($0) })) {
                ForEach(controller.search.results) { result in
                    searchResultButton(result)
                }

            }
            .listStyle(.inset)
            .scrollContentBackground(isAdvanced ? .automatic : .hidden)
            .accessibilityIdentifier("scholium.searchResults")
            .onKeyPress(.return) {
                openSelectedResult()
                return .handled
            }
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
        }
        return WorkspaceSearchResultRow(
            result: result,
            compact: !isAdvanced
        )
        .tag(resultID)
        .onTapGesture {
            controller.selectSearchResult(resultID)
            open(.result(result))
        }
        .accessibilityAction {
            controller.selectSearchResult(resultID)
            open(.result(result))
        }
        .id(resultID)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the selected Search result")
        .accessibilityIdentifier("scholium.searchResult." + result.id)
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
        let heading = scope
        let clauses = explanation.clauses.map(explanationClause)
        return ([heading] + clauses).joined(separator: "\n")
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
            return value.map { "Metadata \(key) equals ‘\($0)’" }
                ?? "Metadata \(key) is present"
        case .link(let direction, let identity):
            return direction == .fromNote
                ? "is a direct destination of a link authored in ‘\(identity)’"
                : "directly links to ‘\(identity)’"
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        controller.selectSearchResult(nil)
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard !Task.isCancelled, isActive else { return }
            await context.refresh()
        }
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
            return
        }
    }

    private func open(_ result: SearchResultSelection) {
        context.openNote(result)
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
        case .tag: String(localized: "keyword")
        case .path: String(localized: "path")
        case .callout: String(localized: "callout")
        case .footnote: String(localized: "footnote")
        case .linkAnnotation: String(localized: "link annotation")
        case .brokenLink: String(localized: "broken link")
        case .body: String(localized: "body")
        }
    }

}

private extension NoteSearchResult {
    var hasYAMLMatch: Bool {
        if matchedField == .summary || matchedField == .tag { return true }
        return matchReasons.contains {
            if case .property(let property) = $0 { return property.key == "summary" || property.key == "keywords" }
            return false
        }
    }

    var searchStructuredReasonDescription: String? {
        for reason in matchReasons {
            switch reason {
            case .lexical:
                continue
            case .structured(let structured):
                let exclusion = structured.excluded ? "-" : ""
                return "\(exclusion)\(structured.field.rawValue):\(structured.value)"
            case .property(let property):
                if let value = property.normalizedValue {
                    return "property:\(property.key)=\(value)"
                }
                return property.isEmpty
                    ? "property:\(property.key) (present-empty)"
                    : "property:\(property.key) (\(property.valueKind.rawValue))"
            case .link(let link):
                let source = link.occurrences.first.map {
                    " @ \($0.sourceNote.relativePath):\($0.linkSpan.start.line)"
                } ?? ""
                return "\(link.direction.rawValue):\(link.anchorIdentity)" + source
            }
        }
        return nil
    }
}

private struct WorkspaceSearchResultRow: View {
    let result: SearchResult
    let compact: Bool

    @ViewBuilder
    var body: some View {
        switch result {
        case .note(let note): NoteSearchResultRow(note: note, compact: compact)
        }
    }
}

private struct NoteSearchResultRow: View {
    let note: NoteSearchResult
    let compact: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(ScholiumTypography.interface(.rowTitle))
                    .lineLimit(1)
                if !note.hasYAMLMatch && !note.snippet.isEmpty {
                    Text(highlightedSnippet)
                        .font(ScholiumTypography.interface(.small))
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : 2)
                        .multilineTextAlignment(.leading)
                }
                Text("\(compact ? note.vaultName : location) · \(note.searchStructuredReasonDescription ?? rankDescription)")
                    .font(ScholiumTypography.interface(.small))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .help("\(note.vaultName)/\(note.relativePath)")
    }

    private var location: String {
        let parent = (note.relativePath as NSString).deletingLastPathComponent
        let path = parent.isEmpty ? note.vaultName : "\(note.vaultName) / \(parent)"
        guard let range = note.sourceRange else { return path }
        return path + " · " + String(localized: "Line \(range.line), Column \(range.column)")
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
            result[lower..<upper].font = ScholiumTypography.interface(.small, emphasis: .strong)
        }
        return result
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
        case .tag: String(localized: "keyword")
        case .body: String(localized: "body")
        case .callout: String(localized: "callout")
        case .footnote: String(localized: "footnote")
        case .linkAnnotation: String(localized: "link annotation")
        case .brokenLink: String(localized: "broken link")
        case .path: String(localized: "path")
        }
    }
}
