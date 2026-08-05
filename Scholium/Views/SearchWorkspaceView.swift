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
                .opacity(0.55)
                .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)

            searchScopeBar

            if let explanationText {
                Text(explanationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
                    .padding(.bottom, 6)
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
            .buttonStyle(.borderless)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
            .keyboardShortcut(.cancelAction)
            .help("Close Search")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("scholium.closeSearchButton")
        }
        .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
        .frame(height: 48)
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
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(completion.displayText)
                            .font(.body.monospaced())
                        Text(completion.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
                    .frame(minHeight: 32)
                    .background(
                        completionSelection == index
                            ? ScholiumColorRole.accent.color.opacity(0.12)
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
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
            .padding(.bottom, 7)
            .accessibilityLabel(String(localized: "Invalid search query: \(message)"))
    }

    @ViewBuilder
    private var searchAvailabilityBanner: some View {
        if let searchError = controller.search.errorMessage {
            operationalBanner(
                title: String(localized: "Search Unavailable"),
                message: searchError,
                systemImage: "exclamationmark.triangle",
                offersRetry: true
            )
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
        switch availability {
            case .unavailable:
                EmptyView()
            case .building(let progress):
                operationalBanner(
                    title: String(localized: "Building Search Index"),
                    message: progress.total > 0
                        ? String(localized: "Indexed \(progress.completed) of \(progress.total) notes.")
                        : String(localized: "Preparing the local Triptych index."),
                    systemImage: "arrow.triangle.2.circlepath",
                    offersRetry: false
                )
            case .current:
                EmptyView()
            case .refreshing:
                operationalBanner(
                    title: String(localized: "Refreshing Search Index"),
                    message: String(localized: "Showing results from the last complete index while the replacement is built."),
                    systemImage: "arrow.triangle.2.circlepath",
                    offersRetry: false
                )
            case .stale(_, let reason):
                operationalBanner(
                    title: String(localized: "Search Index Is Stale"),
                    message: String(localized: "The last complete Search index remains available. Details: \(reason)"),
                    systemImage: "clock.badge.exclamationmark",
                    offersRetry: false
                )
            case .failed(_, let reason):
                operationalBanner(
                    title: String(localized: "Search Index Failed"),
                    message: String(localized: "Scholium could not publish a replacement Search index. Details: \(reason)"),
                    systemImage: "exclamationmark.triangle",
                    offersRetry: true
                )
        }
    }

    @ViewBuilder
    private func recordAvailabilityBanner(
        _ availability: RecordSearchAvailability
    ) -> some View {
        switch availability {
        case .unavailable:
            EmptyView()
        case .building(let progress):
            operationalBanner(
                title: String(localized: "Preparing Research Records"),
                message: String(localized: "Prepared \(progress.completed) of \(progress.total) records."),
                systemImage: "arrow.triangle.2.circlepath",
                offersRetry: false
            )
        case .current:
            EmptyView()
        case .refreshing:
            operationalBanner(
                title: String(localized: "Refreshing Research Records"),
                message: String(localized: "The Record query projection is refreshing."),
                systemImage: "arrow.triangle.2.circlepath",
                offersRetry: false
            )
        case .stale(_, let reason), .failed(_, let reason):
            operationalBanner(
                title: String(localized: "Research Record Search Unavailable"),
                message: reason,
                systemImage: "exclamationmark.triangle",
                offersRetry: true
            )
        }
    }

    private func operationalBanner(
        title: String,
        message: String,
        systemImage: String,
        offersRetry: Bool
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            if offersRetry {
                Button("Retry") { Task { await context.refresh() } }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Color.orange.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, ScholiumMetrics.Search.responsiveMargin)
        .accessibilityElement(children: .combine)
    }

    private var scopePicker: some View {
        Picker("Search scope", selection: scope) {
            ForEach(SearchPresentationScope.visibleModes, id: \.self) { mode in
                Text(localizedScopeTitle(mode)).tag(mode)
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
        } else if !controller.search.diagnostics.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if suppressesNoMatchContent {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if controller.search.results.isEmpty {
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

    private var suppressesNoMatchContent: Bool {
        guard controller.search.results.isEmpty else { return false }
        if controller.search.criteria.scope == .thisNote { return false }
        return switch controller.search.availability {
        case .note(.unavailable), .note(.building), .note(.failed(lastGood: nil, reason: _)),
             .record(.unavailable), .record(.building), .record(.failed(lastGood: nil, reason: _)):
            true
        case .note, .record:
            false
        }
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
        }
        .buttonStyle(.borderless)
        .frame(minWidth: 28, minHeight: 28)
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
                .font(ScholiumInterfaceTypography.editorialLabel)
                .scholiumForeground(.secondaryText)
            if let detail {
                Text(detail)
                    .font(.caption2)
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
        let query = controller.search.criteria.query
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let parsed = SearchQueryParser.parse(query)
        guard parsed.diagnostics.isEmpty, let ast = parsed.ast else { return nil }
        let scope = localizedScopeTitle(controller.search.criteria.scope)
        let provider = ast.provider == .note ? "Notes" : "Research Records"
        let clauses = ast.explanation.clauses.map(explanationClause)
        if clauses.isEmpty { return "Search \(provider) in \(scope)." }
        return "Search \(provider) in \(scope) where "
            + clauses.joined(separator: " and ") + "."
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
        case .year: String(localized: "year")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title)
                    .font(ScholiumInterfaceTypography.rowTitle)
                    .lineLimit(1)
                Spacer()
                Text(note.vaultName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(highlightedSnippet)
                .font(.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
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
            .font(ScholiumInterfaceTypography.metadata)
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
            result[lower..<upper].backgroundColor = Color(nsColor: .findHighlightColor)
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
        case .year: String(localized: "year")
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.context)
                    .font(ScholiumInterfaceTypography.rowTitle)
                    .lineLimit(1)
                Spacer()
                Text("Research Record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(record.snippet)
                .font(.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 8) {
                if let actionID = record.actionID { Text(actionID) }
                if let methodName = record.methodName { Text(methodName) }
                Text(record.matchedReason)
                if let author = record.statementAuthor {
                    Text(author == .researcher ? "Researcher" : "Agent")
                }
                Text("Retrieval lead")
            }
            .font(ScholiumInterfaceTypography.metadata)
            .scholiumForeground(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .frame(minHeight: ScholiumMetrics.Search.resultRowHeight)
    }
}
