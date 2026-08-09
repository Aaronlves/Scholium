import ScholiumContracts
import ScholiumResearchRecordsFeature
import SwiftUI

struct ResearchRecordBrowserContext {
    let setRecommendationDisposition:
        @MainActor (
            UUID,
            UUID,
            ResearchLiteratureRecommendationDispositionStatus
        ) async throws -> PortableResearchRecord
    let setRecommendationNote:
        @MainActor (
            UUID,
            UUID,
            String?
        ) async throws -> PortableResearchRecord
    let saveEvaluation:
        @MainActor (
            UUID,
            ResearcherEvaluationDraft,
            UUID?,
            DocumentFingerprint
        ) async throws -> PortableResearchRecord
    let clearEvaluation:
        @MainActor (
            UUID,
            UUID,
            DocumentFingerprint
        ) async throws -> PortableResearchRecord
    let deletePermanently: @MainActor (UUID) async throws -> Void
    let openNote: @MainActor (UUID, VaultQualifiedNoteID, Int?) -> Void
}

struct ResearchRecordBrowserView: View {
    let model: ResearchRecordBrowserModel
    let loadIssues: [String]
    let context: ResearchRecordBrowserContext

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if !loadIssues.isEmpty {
                ResearchRecordsLoadIssuesBanner(issues: loadIssues)
                ScholiumStructuralRule()
            }
            ResearchRecordsRouteView(
                model: model,
                context: context
            )
        }
        .scholiumSurface(.document)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .tint(ScholiumColorRole.accent.color)
        .alert(
            "Research Records Unavailable",
            isPresented: $model.isShowingError
        ) {
            Button("Dismiss", role: .cancel) { model.dismissError() }
        } message: {
            Text(model.errorMessage)
        }
    }
}

private struct ResearchRecordsLoadIssuesBanner: View {
    let issues: [String]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                ForEach(issues, id: \.self) { issue in
                    Text(issue)
                        .font(ScholiumTypography.interface(.compact))
                        .textSelection(.enabled)
                }
            }
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
        } label: {
            Label(
                "Some Research Records Could Not Be Loaded",
                systemImage: "exclamationmark.triangle"
            )
            .font(ScholiumTypography.interface(.rowTitle))
        }
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .padding(.vertical, ScholiumGrid.Spacing.inlineControlGap)
        .scholiumSurface(.denseEvidence)
        .accessibilityIdentifier("scholium.researchRecords.issues")
    }
}

private enum ResearchRecordLayout {
    static let readingMeasure = ScholiumMetrics.ResearchRecords.readingMeasure
}

private struct ResearchRecordsRouteView: View {
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    var body: some View {
        Group {
            switch model.route {
            case .collection:
                ResearchRecordsCollectionView(
                    model: model,
                    context: context
                )
            case .record:
                if let record = model.selectedRecord {
                    ResearchRecordWorkspaceView(
                        record: record,
                        model: model,
                        context: context
                    )
                    .id(record.id)
                } else {
                    ResearchRecordsCollectionView(
                        model: model,
                        context: context
                    )
                }
            case .recommendation:
                if let occurrence = model.selectedRecommendationOccurrence {
                    ResearchLiteratureRecommendationWorkspaceView(
                        occurrence: occurrence,
                        model: model,
                        context: context
                    )
                    .id(occurrence.id)
                } else {
                    ResearchRecordsCollectionView(
                        model: model,
                        context: context
                    )
                }
            }
        }
    }
}

private struct ResearchRecordsCollectionView: View {
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(
                    alignment: .center,
                    spacing: ScholiumGrid.Spacing.nestedContentInset
                ) {
                    ResearchRecordsCollectionSearch(model: model)
                        .frame(
                            minWidth: ScholiumMetrics.ResearchRecords
                                .collectionSearchMinimumWidth,
                            maxWidth: .infinity
                        )
                        .layoutPriority(1)
                    collectionControls
                }

                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    ResearchRecordsCollectionSearch(model: model)
                    collectionControls
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, ScholiumMetrics.ResearchRecords.pageEdge)
            .padding(.top, ScholiumGrid.Spacing.nestedContentInset)
            .padding(.bottom, ScholiumGrid.Spacing.nestedContentInset)

            ScholiumStructuralRule()

            Group {
                switch model.viewKind {
                case .records:
                    ResearchRecordCollectionIndex(model: model, context: context)
                case .recommendations:
                    ResearchReadingLeadCollectionIndex(model: model, context: context)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .scholiumSurface(.document)
        .accessibilityIdentifier("scholium.researchRecords.collection")
        .toolbar {
            ResearchRecordsCollectionToolbar(model: model)
        }
    }

    private var collectionControls: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchRecordsScopeMenu(model: model)
            ResearchRecordsFilterMenu(model: model)
        }
    }
}

private struct ResearchRecordsCollectionSearch: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        @Bindable var model = model
        switch model.viewKind {
        case .records:
            ResearchRecordsSearchField(
                prompt: "Search records",
                text: $model.searchText,
                identifier: "scholium.researchRecord.search"
            )
        case .recommendations:
            ResearchRecordsSearchField(
                prompt: "Search reading leads",
                text: $model.recommendationSearchText,
                identifier: "scholium.researchRecommendations.search"
            )
        }
    }
}

private struct ResearchRecordsFilterMenu: View {
    @FocusState private var isFocused: Bool
    let model: ResearchRecordBrowserModel

    var body: some View {
        @Bindable var model = model
        Menu {
            switch model.viewKind {
            case .records:
                Picker("Date", selection: $model.dateFilter) {
                    ForEach(ResearchRecordDateFilter.allCases, id: \.self) { filter in
                        Text(filter.interfaceTitle).tag(filter)
                    }
                }
                Picker("Method", selection: $model.methodFilterName) {
                    Text("Any Method").tag(Optional<String>.none)
                    ForEach(model.methodOptions, id: \.self) { method in
                        Text(method).tag(Optional(method))
                    }
                }
                Picker("Action", selection: $model.actionFilterID) {
                    Text("Any Action").tag(Optional<ResearchActionID>.none)
                    ForEach(model.actionOptions, id: \.self) { actionID in
                        Text(actionTitle(actionID)).tag(Optional(actionID))
                    }
                }
                Picker("Participant", selection: $model.participantFilter) {
                    Text("Any Participant")
                        .tag(Optional<ResearchRecordParticipantFilter>.none)
                    ForEach(model.participantOptions) { option in
                        switch option.filter {
                        case .author(let author):
                            Text(author.interfaceTitle).tag(Optional(option.filter))
                        case .note:
                            Text(
                                option.isTombstone ? "Deleted Note — \(option.title)" : option.title
                            )
                            .tag(Optional(option.filter))
                        }
                    }
                }
                Divider()
                Button("Clear Filters") { model.clearAllFilters() }
                    .disabled(activeFilterCount == 0 && model.searchText.isEmpty)
            case .recommendations:
                Picker("Status", selection: $model.recommendationFilter) {
                    Text("Unprocessed").tag(ResearchLiteratureRecommendationFilter.unprocessed)
                    Text("Handled").tag(ResearchLiteratureRecommendationFilter.handled)
                    Text("All").tag(ResearchLiteratureRecommendationFilter.all)
                }
                Divider()
                Button("Clear Filters") { model.clearRecommendationFilters() }
                    .disabled(
                        model.recommendationFilter == .unprocessed
                            && model.recommendationSearchText.isEmpty
                    )
            }
        } label: {
            ResearchRecordsMenuLabel(
                title: filterLabel,
                systemImage: "line.3.horizontal.decrease"
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .tint(ScholiumColorRole.secondaryText.color)
        .scholiumActivationFocus($isFocused)
        .scholiumContentControlPointerFeedback(
            isFocused: isFocused,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
        .fixedSize()
        .accessibilityIdentifier("scholium.researchRecords.filters")
    }

    private var activeFilterCount: Int {
        var count = 0
        if model.dateFilter != .any { count += 1 }
        if model.methodFilterName != nil { count += 1 }
        if model.actionFilterID != nil { count += 1 }
        if model.participantFilter != nil { count += 1 }
        return count
    }

    private var filterLabel: String {
        switch model.viewKind {
        case .records:
            activeFilterCount == 0 ? "Filters" : "Filters \(activeFilterCount)"
        case .recommendations:
            switch model.recommendationFilter {
            case .unprocessed: "Unprocessed"
            case .handled: "Handled"
            case .all: "All Leads"
            }
        }
    }
}

private struct ResearchRecordCollectionIndex: View {
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    var body: some View {
        if model.visibleEntries.isEmpty, model.isLoadingRecords {
            ProgressView("Loading Research Records…")
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("scholium.researchRecord.loading")
        } else if model.visibleEntries.isEmpty {
            ResearchRecordEmptyResults(model: model)
        } else {
            let showsNoteColumn = model.scope == .triptych
            VStack(spacing: 0) {
                ResearchRecordCollectionColumnHeader(model: model)
                    .padding(.horizontal, ScholiumMetrics.ResearchRecords.pageEdge)
                ScholiumStructuralRule()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.visibleEntries.enumerated()), id: \.element.id) {
                            entryIndex, entry in
                            ResearchRecordCollectionRow(
                                entry: entry,
                                showsNoteColumn: showsNoteColumn,
                                select: { model.select(entry.id) }
                            )
                            .onAppear {
                                model.loadMoreRecordsIfNeeded(currentID: entry.id)
                            }
                            .overlay(alignment: .bottom) {
                                if entryIndex < model.visibleEntries.count - 1 {
                                    ScholiumStructuralRule()
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        if model.isLoadingMoreRecords {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .frame(height: ScholiumMetrics.ResearchRecords.collectionRowHeight)
                                .accessibilityLabel("Loading more Records")
                        } else if model.recordLoadMoreErrorMessage != nil {
                            Button("Retry") { model.retryLoadingMoreRecords() }
                                .buttonStyle(.plain)
                                .font(ScholiumTypography.interface(.compact, emphasis: .medium))
                                .foregroundStyle(ScholiumColorRole.accent.color)
                                .frame(maxWidth: .infinity)
                                .frame(height: ScholiumMetrics.ResearchRecords.collectionRowHeight)
                                .accessibilityHint("Retry loading more Research Records")
                        }
                    }
                    .padding(.horizontal, ScholiumMetrics.ResearchRecords.pageEdge)
                    .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                    .padding(.bottom, ScholiumGrid.Spacing.sectionSeparation)
                }
                .accessibilityLabel("Research Records")
                .accessibilityIdentifier("scholium.researchRecord.list")
            }
        }
    }
}

private struct ResearchRecordCollectionColumnHeader: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        HStack(spacing: ScholiumMetrics.ResearchRecords.collectionColumnGap) {
            Color.clear
                .frame(
                    width: ScholiumMetrics.ResearchRecords.recordAttentionColumnWidth
                )
                .accessibilityHidden(true)
            ResearchRecordsSortableColumnHeader(
                title: "Record",
                count: model.recordResultCount,
                sort: model.recordSort,
                ascending: .titleAscending,
                descending: .titleDescending,
                defaultSort: .titleAscending,
                alignsLeading: true,
                select: { model.recordSort = $0 }
            )
                .frame(maxWidth: .infinity, alignment: .leading)
            ResearchRecordsSortableColumnHeader(
                title: "Action",
                sort: model.recordSort,
                ascending: .actionAscending,
                descending: .actionDescending,
                defaultSort: .actionAscending,
                select: { model.recordSort = $0 }
            )
                .frame(
                    width: ScholiumMetrics.ResearchRecords.recordActionColumnWidth,
                    alignment: .center
                )
            ResearchRecordsSortableColumnHeader(
                title: "Date",
                sort: model.recordSort,
                ascending: .finishedAtAscending,
                descending: .finishedAtDescending,
                defaultSort: .finishedAtDescending,
                select: { model.recordSort = $0 }
            )
                .frame(
                    width: ScholiumMetrics.ResearchRecords.recordDateColumnWidth,
                    alignment: .center
                )
        }
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ScholiumMetrics.ResearchRecords.collectionColumnHeaderHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Record, Action, Date")
        .accessibilityIdentifier("scholium.researchRecord.columnHeader")
    }
}

private struct ResearchReadingLeadCollectionIndex: View {
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    var body: some View {
        if model.visibleRecommendationOccurrences.isEmpty {
            ResearchLiteratureRecommendationEmptyResults(model: model)
        } else {
            let occurrences = model.visibleRecommendationOccurrences
            VStack(spacing: 0) {
                ResearchReadingLeadCollectionColumnHeader(
                    resultCount: model.recommendationResultCount
                )
                    .padding(.horizontal, ScholiumMetrics.ResearchRecords.pageEdge)
                ScholiumStructuralRule()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(occurrences.enumerated()), id: \.element.id) {
                            occurrenceIndex, occurrence in
                            ResearchLiteratureRecommendationListRow(
                                occurrence: occurrence,
                                isHandled:
                                    model.recommendationDispositionStatus(
                                        for: occurrence.id
                                    ) == .handled,
                                isMutating: model.mutatingRecommendationIDs.contains(
                                    occurrence.id
                                ),
                                select: { model.selectRecommendation(occurrence.id) },
                                setHandled: { isHandled in
                                    model.setRecommendationDisposition(
                                        occurrenceID: occurrence.id,
                                        status: isHandled ? .handled : .unprocessed,
                                        update: context.setRecommendationDisposition
                                    )
                                }
                            )
                            .onAppear {
                                model.loadMoreRecommendationsIfNeeded(
                                    currentID: occurrence.id
                                )
                            }
                            .overlay(alignment: .bottom) {
                                if occurrenceIndex < occurrences.count - 1 {
                                    ScholiumStructuralRule()
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, ScholiumMetrics.ResearchRecords.pageEdge)
                    .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
                    .padding(.bottom, ScholiumGrid.Spacing.sectionSeparation)
                }
                .accessibilityLabel("Reading Leads")
                .accessibilityIdentifier("scholium.researchRecommendations.list")
            }
        }
    }
}

private struct ResearchReadingLeadCollectionColumnHeader: View {
    let resultCount: Int

    var body: some View {
        HStack(spacing: ScholiumMetrics.ResearchRecords.collectionColumnGap) {
            HStack(spacing: ScholiumMetrics.ResearchRecords.readingLeadSelectionGap) {
                Color.clear
                    .frame(
                        width: ScholiumMetrics.ResearchRecords.readingLeadHandledColumnWidth
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Handled")
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    ResearchRecordsLedgerColumnLabel("Title")
                    ResearchRecordsLedgerCount(resultCount)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
            ResearchRecordsLedgerColumnLabel("Author(s)")
                .frame(
                    width: ScholiumMetrics.ResearchRecords.readingLeadAuthorColumnWidth,
                    alignment: .leading
                )
            ResearchRecordsLedgerColumnLabel("Year")
                .frame(
                    width: ScholiumMetrics.ResearchRecords.readingLeadYearColumnWidth,
                    alignment: .trailing
                )
            ResearchRecordsLedgerColumnLabel("Publication")
                .frame(
                    width: ScholiumMetrics.ResearchRecords.readingLeadPublicationColumnWidth,
                    alignment: .leading
                )
        }
        .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ScholiumMetrics.ResearchRecords.collectionColumnHeaderHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchRecommendation.columnHeader")
    }
}

private struct ResearchRecordsLedgerColumnLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(ScholiumTypography.interface(.small, emphasis: .strong))
            .foregroundStyle(ScholiumColorRole.mutedText.color)
            .tracking(0.8)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

private struct ResearchRecordsLedgerCount: View {
    let count: Int

    init(_ count: Int) {
        self.count = count
    }

    var body: some View {
        Text(count.formatted())
            .font(ScholiumTypography.interface(.small, tabularDigits: true))
            .foregroundStyle(ScholiumColorRole.mutedText.color)
            .lineLimit(1)
            .accessibilityLabel(
                String.localizedStringWithFormat(
                    String(localized: "%lld results"),
                    Int64(count)
                )
            )
    }
}

private struct ResearchRecordsSortableColumnHeader: View {
    let title: LocalizedStringKey
    var count: Int?
    let sort: RecordSearchSortOrder
    let ascending: RecordSearchSortOrder
    let descending: RecordSearchSortOrder
    let defaultSort: RecordSearchSortOrder
    let alignsLeading: Bool
    let select: (RecordSearchSortOrder) -> Void

    init(
        title: LocalizedStringKey,
        count: Int? = nil,
        sort: RecordSearchSortOrder,
        ascending: RecordSearchSortOrder,
        descending: RecordSearchSortOrder,
        defaultSort: RecordSearchSortOrder,
        alignsLeading: Bool = false,
        select: @escaping (RecordSearchSortOrder) -> Void
    ) {
        self.title = title
        self.count = count
        self.sort = sort
        self.ascending = ascending
        self.descending = descending
        self.defaultSort = defaultSort
        self.alignsLeading = alignsLeading
        self.select = select
    }

    var body: some View {
        Button {
            select(nextSort)
        } label: {
            HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                ResearchRecordsLedgerColumnLabel(title)
                if let count {
                    ResearchRecordsLedgerCount(count)
                }
                if isSelected {
                    Image(systemName: sort == ascending ? "chevron.up" : "chevron.down")
                        .font(ScholiumTypography.interface(.small, emphasis: .medium))
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: titleAlignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(accessibilitySortValue)
        .accessibilityHint("Sort this column")
    }

    private var isSelected: Bool {
        sort == ascending || sort == descending
    }

    private var nextSort: RecordSearchSortOrder {
        guard isSelected else { return defaultSort }
        return sort == ascending ? descending : ascending
    }

    private var titleAlignment: Alignment {
        alignsLeading ? .leading : .center
    }

    private var accessibilitySortValue: String {
        guard isSelected else { return String(localized: "Not sorted") }
        return sort == ascending
            ? String(localized: "Sorted ascending")
            : String(localized: "Sorted descending")
    }
}

private struct ResearchRecordCollectionRow: View {
    @FocusState private var isFocused: Bool

    let entry: ResearchRecordIndexEntry
    let showsNoteColumn: Bool
    let select: () -> Void

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: ScholiumMetrics.ResearchRecords.collectionRowCornerRadius,
            style: .continuous
        )
        Button(action: select) {
            HStack(
                alignment: .center,
                spacing: ScholiumMetrics.ResearchRecords.collectionColumnGap
            ) {
                ResearchRecordCollectionAttention(entry: entry)
                .frame(
                    width: ScholiumMetrics.ResearchRecords.recordAttentionColumnWidth,
                    alignment: .center
                )

                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
                ) {
                    Text(entry.title)
                        .font(ScholiumTypography.interface(.body))
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if showsNoteColumn {
                        Text(entry.noteTitle)
                            .font(ScholiumTypography.interface(.small))
                            .foregroundStyle(ScholiumColorRole.mutedText.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionCapsule
                    .frame(
                        width: ScholiumMetrics.ResearchRecords.recordActionColumnWidth,
                        alignment: .center
                    )

                Text(entry.finishedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(ScholiumTypography.interface(.compact, tabularDigits: true))
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(
                        width: ScholiumMetrics.ResearchRecords.recordDateColumnWidth,
                        alignment: .center
                    )
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ScholiumMetrics.ResearchRecords.collectionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isFocused: isFocused,
                in: shape
            )
        )
        .scholiumActivationFocus($isFocused)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityHint("Open this Research Record")
        .frame(height: ScholiumMetrics.ResearchRecords.collectionRowHeight)
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchRecord.row.\(entry.id.uuidString)")
    }

    private var actionCapsule: some View {
        Text(actionTitle(entry.actionID))
            .font(ScholiumTypography.interface(.compact, emphasis: .medium))
            .foregroundStyle(ScholiumColorRole.secondaryText.color)
            .lineLimit(1)
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(height: ScholiumMetrics.ResearchRecords.recordActionCapsuleHeight)
            .background {
                Capsule(style: .continuous)
                    .fill(ScholiumColorRole.secondaryText.color.opacity(0.08))
            }
            .accessibilityHidden(true)
    }

    private var rowAccessibilityLabel: String {
        let state = entry.resultDisposition == .completed
            ? ""
            : "\(String(localized: "Blocked")), "
        let date = entry.finishedAt.formatted(date: .long, time: .omitted)
        return "\(state)\(entry.title), \(entry.noteTitle), \(actionTitle(entry.actionID)), \(date)"
    }
}

private struct ResearchRecordCollectionAttention: View {
    let entry: ResearchRecordIndexEntry

    var body: some View {
        if let attention {
            Image(systemName: "exclamationmark.triangle")
                .font(ScholiumTypography.interface(.compact, emphasis: .medium))
                .foregroundStyle(ScholiumColorRole.attention.color)
                .help(attention.detail)
                .accessibilityLabel(attention.detail)
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    private var attention: ResearchRecordAttentionPresentation? {
        var issues: [ResearchRecordAttentionPresentation] = []
        if entry.resultDisposition != .completed {
            issues.append(ResearchRecordAttentionPresentation(
                title: String(localized: "Blocked"),
                detail: String(localized: "Blocked")
            ))
        }
        if entry.actionID == .analyze {
            issues.append(contentsOf: [
                reliabilityIssue(entry.reliability),
                coverageIssue(entry.coverage),
            ].compactMap { $0 })
        }
        guard !issues.isEmpty else { return nil }
        guard issues.count > 1 else { return issues[0] }
        return ResearchRecordAttentionPresentation(
            title: String.localizedStringWithFormat(
                String(localized: "%lld issues"),
                Int64(issues.count)
            ),
            detail: issues.map(\.detail).joined(separator: "\n")
        )
    }

    private func reliabilityIssue(
        _ state: ResearchRecordLedgerFieldState
    ) -> ResearchRecordAttentionPresentation? {
        switch state {
        case .value(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized != "no material limitations identified" else { return nil }
            let limitations = value.split(separator: ",").filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let title = limitations.count > 1
                ? String.localizedStringWithFormat(
                    String(localized: "%lld limitations"),
                    Int64(limitations.count)
                )
                : value
            return issue(
                title: title,
                field: String(localized: "Reliability"),
                value: value
            )
        case .notSupplied:
            return issue(
                title: String(localized: "Reliability missing"),
                field: String(localized: "Reliability"),
                value: String(localized: "Not supplied")
            )
        case .unavailable:
            return issue(
                title: String(localized: "Reliability unavailable"),
                field: String(localized: "Reliability"),
                value: String(localized: "Field unavailable")
            )
        case .notApplicable:
            return nil
        }
    }

    private func coverageIssue(
        _ state: ResearchRecordLedgerFieldState
    ) -> ResearchRecordAttentionPresentation? {
        switch state {
        case .value(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized != "all declared scope" else { return nil }
            let title = switch normalized {
            case "specified part only", "partial": String(localized: "Partial scope")
            default: value
            }
            return issue(
                title: title,
                field: String(localized: "Coverage"),
                value: value
            )
        case .notSupplied:
            return issue(
                title: String(localized: "Coverage missing"),
                field: String(localized: "Coverage"),
                value: String(localized: "Not supplied")
            )
        case .unavailable:
            return issue(
                title: String(localized: "Coverage unavailable"),
                field: String(localized: "Coverage"),
                value: String(localized: "Field unavailable")
            )
        case .notApplicable:
            return nil
        }
    }

    private func issue(
        title: String,
        field: String,
        value: String
    ) -> ResearchRecordAttentionPresentation {
        return ResearchRecordAttentionPresentation(
            title: title,
            detail: "\(field): \(value)"
        )
    }
}

private struct ResearchRecordAttentionPresentation {
    let title: String
    let detail: String
}

private struct ResearchRecordsViewIndex: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @FocusState private var focusedView: ResearchRecordsViewKind?

    let model: ResearchRecordBrowserModel

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            ForEach(ResearchRecordsViewKind.allCases, id: \.self) { viewKind in
                ResearchRecordsViewIndexButton(
                    viewKind: viewKind,
                    isSelected: model.viewKind == viewKind,
                    focusedView: $focusedView,
                    select: { model.viewKind = viewKind },
                    move: { moveFocus(from: viewKind, direction: $0) }
                )
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
        .accessibilityIdentifier("scholium.researchRecords.view")
    }

    private func moveFocus(
        from viewKind: ResearchRecordsViewKind,
        direction: MoveCommandDirection
    ) {
        let views = ResearchRecordsViewKind.allCases
        guard let index = views.firstIndex(of: viewKind) else { return }
        let visualStep: Int
        switch direction {
        case .left:
            visualStep = layoutDirection == .leftToRight ? -1 : 1
        case .right:
            visualStep = layoutDirection == .leftToRight ? 1 : -1
        default:
            return
        }
        let nextIndex = (index + visualStep + views.count) % views.count
        let nextView = views[nextIndex]
        model.viewKind = nextView
        focusedView = nextView
    }
}

private struct ResearchRecordsViewIndexButton: View {
    let viewKind: ResearchRecordsViewKind
    let isSelected: Bool
    let focusedView: FocusState<ResearchRecordsViewKind?>.Binding
    let select: () -> Void
    let move: (MoveCommandDirection) -> Void

    var body: some View {
        Button(action: select) {
            Text(title)
                .font(
                    isSelected
                        ? ScholiumTypography.interface(.compact, emphasis: .strong)
                        : ScholiumTypography.interface(.compact, emphasis: .medium)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
                )
                .contentShape(selectionShape)
                .scholiumContentControlInk()
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isSelected: isSelected,
                isFocused: isFocused,
                in: selectionShape
            )
        )
        .scholiumActivationFocus(focusedView, equals: viewKind)
        .onMoveCommand(perform: move)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier(
            "scholium.researchRecords.view.\(viewKind.rawValue)"
        )
    }

    private var title: String {
        switch viewKind {
        case .records:
            "Records"
        case .recommendations:
            "Reading Leads"
        }
    }

    private var isFocused: Bool {
        focusedView.wrappedValue == viewKind
    }

    private var selectionShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ScholiumShape.editorialControlCornerRadius,
            style: .continuous
        )
    }
}

private struct ResearchRecordsRoundedLinkButton<Label: View>: View {
    @FocusState private var isFocused: Bool
    let action: () -> Void
    let label: Label

    init(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    ))
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isFocused: isFocused,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        )
        .scholiumActivationFocus($isFocused)
    }
}

private struct ResearchRecordsMenuLabel: View {
    @Environment(\.scholiumContentControlIsEmphasized) private var isEmphasized
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(ScholiumTypography.interface(.compact, emphasis: .medium))
            .foregroundStyle(
                isEmphasized
                    ? ScholiumColorRole.primaryText.color
                    : ScholiumColorRole.secondaryText.color
            )
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                ))
    }
}

private struct ResearchRecordsScopeMenu: View {
    @FocusState private var isFocused: Bool

    let model: ResearchRecordBrowserModel

    var body: some View {
        Menu {
            if model.canScopeToNote {
                scopeChoice("This Note", value: .thisNote)
            }
            scopeChoice("Triptych", value: .triptych)
        } label: {
            ResearchRecordsMenuLabel(
                title: scopeTitle,
                systemImage: "square.stack.3d.up"
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .scholiumActivationFocus($isFocused)
        .scholiumContentControlPointerFeedback(
            isFocused: isFocused,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
        .tint(ScholiumColorRole.secondaryText.color)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Scope")
        .accessibilityValue(scopeTitle)
        .accessibilityIdentifier("scholium.researchRecords.scope")
    }

    @ViewBuilder
    private func scopeChoice(
        _ title: String,
        value: ResearchRecordsScope
    ) -> some View {
        Button {
            model.scope = value
        } label: {
            if model.scope == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var scopeTitle: String {
        switch model.scope {
        case .thisNote:
            "This Note"
        case .triptych:
            "Triptych"
        }
    }
}

private struct ResearchRecordsSearchField: View {
    let prompt: String
    @Binding var text: String
    let identifier: String

    var body: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Image(systemName: "magnifyingglass")
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                ResearchRecordsClearSearchButton { text = "" }
            }
        }
        .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
        .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
        .background(
            ScholiumColorRole.surfaceBackground.color,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
        .scholiumBoundary(
            .subtleBoundary,
            in: RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
    }
}

private struct ResearchRecordsClearSearchButton: View {
    @FocusState private var isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .scholiumContentControlInk(
                    resting: .mutedText,
                    emphasized: .primaryText
                )
                .frame(
                    width: ScholiumMetrics.Accessibility.minimumCustomTarget,
                    height: ScholiumMetrics.Accessibility.minimumCustomTarget
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    ))
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isFocused: isFocused,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        )
        .scholiumActivationFocus($isFocused)
        .accessibilityLabel("Clear Search")
    }
}

/// One ink-first action treatment shared by both Research Records views. It
/// keeps native Button behavior while avoiding a second bezeled visual system
/// inside the editorial reading plane.
private struct ResearchRecordActionButton: View {
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    let title: String
    let systemImage: String
    let role: ButtonRole?
    let identifier: String
    let externalFocus: FocusState<Bool>.Binding?
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        identifier: String,
        focus: FocusState<Bool>.Binding? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.identifier = identifier
        externalFocus = focus
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(systemName: systemImage)
                    .font(ScholiumTypography.interface(.small, emphasis: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(ScholiumTypography.interface(.sectionTitle))
            }
            .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
            .frame(minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
            .scholiumContentControlInk(
                resting: actionRestingRole,
                emphasized: actionEmphasizedRole
            )
            .opacity(isEnabled ? 1 : 0.42)
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isFocused: actionFocus.wrappedValue,
                in: RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                )
            )
        )
        .scholiumActivationFocus(actionFocus)
        .accessibilityIdentifier(identifier)
    }

    private var actionRestingRole: ScholiumColorRole {
        role == .destructive ? .destructive : .secondaryText
    }

    private var actionEmphasizedRole: ScholiumColorRole {
        role == .destructive ? .destructive : .primaryText
    }

    private var actionFocus: FocusState<Bool>.Binding {
        externalFocus ?? $isFocused
    }
}

private struct ResearchLiteratureRecommendationEmptyResults: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        ScholiumContentStateView(
            model.recommendationFilter == .unprocessed
                ? "No Unprocessed Recommendations"
                : "No Matching Recommendations",
            detail: Text(emptyDescription),
            indicator: .symbol("books.vertical")
        ) {
            if !model.recommendationSearchText.isEmpty
                || model.recommendationFilter != .unprocessed
            {
                Button("Clear Filters") { model.clearRecommendationFilters() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDescription: String {
        if model.recommendationFilter == .unprocessed,
            model.recommendationSearchText.isEmpty
        {
            return "Analyze Records in this scope contain no reading leads awaiting handling."
        }
        return "Clear the search or choose another handling status."
    }
}

private struct ResearchLiteratureRecommendationListRow: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    let occurrence: ResearchLiteratureRecommendationOccurrence
    let isHandled: Bool
    let isMutating: Bool
    let select: () -> Void
    let setHandled: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: ScholiumMetrics.ResearchRecords.collectionRowCornerRadius,
            style: .continuous
        )
        Button(action: select) {
            HStack(
                alignment: .center,
                spacing: ScholiumMetrics.ResearchRecords.collectionColumnGap
            ) {
                HStack(spacing: ScholiumMetrics.ResearchRecords.readingLeadSelectionGap) {
                    Color.clear
                        .frame(
                            width: ScholiumMetrics.ResearchRecords.readingLeadHandledColumnWidth
                        )
                        .accessibilityHidden(true)

                    Text(occurrence.displayTitle)
                        .font(ScholiumTypography.interface(.body))
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    occurrence.recommendation.authors.isEmpty
                        ? "Not recorded"
                        : occurrence.recommendation.authors.formatted()
                )
                .font(ScholiumTypography.interface(.compact))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    width: ScholiumMetrics.ResearchRecords.readingLeadAuthorColumnWidth,
                    alignment: .leading
                )

                Text(occurrence.recommendation.year.map(String.init) ?? "Not recorded")
                    .font(ScholiumTypography.interface(.compact, tabularDigits: true))
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                    .lineLimit(1)
                    .frame(
                        width: ScholiumMetrics.ResearchRecords.readingLeadYearColumnWidth,
                        alignment: .trailing
                    )

                Text(occurrence.recommendation.publication ?? "Not recorded")
                    .font(ScholiumTypography.interface(.compact))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(
                        width: ScholiumMetrics.ResearchRecords
                            .readingLeadPublicationColumnWidth,
                        alignment: .leading
                    )
            }
            .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: ScholiumMetrics.ResearchRecords.collectionRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ScholiumContentControlButtonStyle(
                isFocused: isFocused,
                in: shape
            )
        )
        .scholiumActivationFocus($isFocused)
        .accessibilityHint("Open this Reading Lead")
        .overlay(alignment: .leading) {
            Toggle(
                "Handled",
                isOn: Binding(
                    get: { isHandled },
                    set: { newValue in
                        withAnimation(
                            ScholiumMotion.symbolReplacement(
                                reduceMotion: reduceMotion
                            )
                        ) {
                            setHandled(newValue)
                        }
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(isMutating)
            .frame(
                width: ScholiumMetrics.ResearchRecords.readingLeadHandledColumnWidth,
                alignment: .center
            )
            .padding(.horizontal, ScholiumGrid.Spacing.nestedContentInset)
            .accessibilityIdentifier(
                "scholium.researchRecommendation.rowHandled.\(occurrence.recommendation.id.uuidString)"
            )
            .accessibilityValue(
                isHandled ? "Handled" : "Unprocessed"
            )
            .accessibilityHint(
                "Marks only whether you have processed this Reading Lead"
            )
            .help(isHandled ? "Mark as unprocessed" : "Mark as handled")
            .animation(
                ScholiumMotion.symbolReplacement(reduceMotion: reduceMotion),
                value: isHandled
            )
        }
        .frame(height: ScholiumMetrics.ResearchRecords.collectionRowHeight)
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "scholium.researchRecommendation.row.\(occurrence.recommendation.id.uuidString)"
        )
    }
}

private struct ResearchLiteratureRecommendationDetailView: View {
    @Environment(\.scholiumReduceMotion) private var reduceMotion
    let occurrence: ResearchLiteratureRecommendationOccurrence
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext
    @State private var isEditingNote = false
    @State private var noteDraft = ""

    var body: some View {
        readingPlane
            .scholiumSurface(.document)
            .accessibilityIdentifier("scholium.researchRecommendation.detail")
            .sheet(isPresented: $isEditingNote) {
                ResearchLiteratureRecommendationNoteSheet(
                    draft: $noteDraft,
                    save: { note in
                        try await model.setRecommendationNote(
                            occurrenceID: occurrence.id,
                            note: note,
                            update: context.setRecommendationNote
                        )
                    },
                    dismiss: { isEditingNote = false }
                )
            }
    }

    private var readingPlane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                recommendationHeader
                ScholiumStructuralRule()
                bibliographicOverview

                ScholiumStructuralRule()
                recommendationReason

                ScholiumStructuralRule()
                researcherNote

                ScholiumStructuralRule()
                provenance

                ScholiumStructuralRule()
                ResearchLiteratureRecommendationTechnicalDetails(occurrence: occurrence)
            }
            .padding(.horizontal, ScholiumMetrics.ResearchRecords.pageEdge)
            .padding(.top, ScholiumGrid.Spacing.sectionSeparation)
            .padding(.bottom, ScholiumGrid.Spacing.regionContentInset * 2)
            .frame(maxWidth: ResearchRecordLayout.readingMeasure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ScholiumColorRole.documentBackground.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reading Lead Research")
        .accessibilityIdentifier("scholium.researchRecommendation.reading")
    }

    private var recommendationHeader: some View {
        HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(occurrence.displayTitle)
                .font(ScholiumTypography.scholarly(.title))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHeading(.h1)
            handledControl
        }
    }

    @ViewBuilder
    private var handledControl: some View {
        let isHandled =
            model.recommendationDispositionStatus(for: occurrence.id) == .handled
        if isHandled {
            handledButton(isHandled: true)
                .buttonStyle(.bordered)
                .tint(ScholiumColorRole.secondaryText.color)
        } else {
            handledButton(isHandled: false)
                .buttonStyle(.borderedProminent)
                .tint(ScholiumColorRole.accent.color)
        }
    }

    private func handledButton(isHandled: Bool) -> some View {
        Button {
            withAnimation(
                ScholiumMotion.symbolReplacement(reduceMotion: reduceMotion)
            ) {
                model.setRecommendationDisposition(
                    occurrenceID: occurrence.id,
                    status: isHandled ? .unprocessed : .handled,
                    update: context.setRecommendationDisposition
                )
            }
        } label: {
            ZStack {
                handledButtonLabel(isHandled: false)
                    .hidden()
                handledButtonLabel(isHandled: isHandled)
                    .id(isHandled)
                    .transition(.opacity)
            }
            .font(ScholiumTypography.interface(.compact, emphasis: .medium))
        }
        .disabled(model.mutatingRecommendationIDs.contains(occurrence.id))
        .controlSize(.regular)
        .accessibilityLabel(
            isHandled ? "Mark as unprocessed" : "Mark as handled"
        )
        .accessibilityValue(isHandled ? "Handled" : "Unprocessed")
        .accessibilityHint(
            "Marks only whether you have processed this Reading Lead"
        )
        .accessibilityIdentifier(
            "scholium.researchRecommendation.handled.\(occurrence.recommendation.id.uuidString)"
        )
        .help(isHandled ? "Mark as unprocessed" : "Mark as handled")
        .animation(
            ScholiumMotion.symbolReplacement(reduceMotion: reduceMotion),
            value: isHandled
        )
    }

    private func handledButtonLabel(isHandled: Bool) -> some View {
        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Image(systemName: isHandled ? "checkmark" : "clock")
                .contentTransition(.symbolEffect(.replace))
            if isHandled {
                Text("Handled")
            } else {
                Text("Mark as handled")
            }
        }
    }

    private var bibliographicOverview: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text(occurrence.recommendation.rawCitation)
                .font(ScholiumTypography.scholarly(.body))
                .foregroundStyle(ScholiumColorRole.mutedText.color)
                .lineSpacing(ScholiumMetrics.Apparatus.bodyLineSpacing)
                .textSelection(.enabled)
                .accessibilityLabel(
                    Text(
                        verbatim: "\(String(localized: "Full citation")), "
                            + occurrence.recommendation.rawCitation
                    )
                )

            ViewThatFits(in: .horizontal) {
                HStack(
                    alignment: .top,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    bibliography
                        .frame(
                            minWidth: ScholiumMetrics.Apparatus.factGridMinimumWidth,
                            maxWidth: .infinity,
                            alignment: .topLeading
                        )
                        .layoutPriority(1)
                    discoveryLocators
                        .frame(
                            width: ScholiumMetrics.Apparatus.factGridMinimumWidth,
                            alignment: .topLeading
                        )
                }

                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    bibliography
                    ScholiumStructuralRule()
                    discoveryLocators
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bibliography: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("BIBLIOGRAPHY")
                .scholiumApparatusHeadingStyle()
                .accessibilityHeading(.h2)
            ScholiumApparatusFactGrid(facts: [
                ScholiumApparatusFact(
                    id: "authors",
                    label: String(localized: "Authors"),
                    value: occurrence.recommendation.authors.isEmpty
                        ? String(localized: "Not recorded")
                        : occurrence.recommendation.authors.formatted()
                ),
                ScholiumApparatusFact(
                    id: "year",
                    label: String(localized: "Year"),
                    value: occurrence.recommendation.year.map(String.init)
                        ?? String(localized: "Not recorded"),
                    monospacedDigits: occurrence.recommendation.year != nil
                ),
                ScholiumApparatusFact(
                    id: "publication",
                    label: String(localized: "Publication"),
                    value: occurrence.recommendation.publication
                        ?? String(localized: "Not recorded")
                ),
                ScholiumApparatusFact(
                    id: "doi",
                    label: "DOI",
                    value: occurrence.recommendation.doi
                        ?? String(localized: "Not recorded")
                ),
                ScholiumApparatusFact(
                    id: "zotero",
                    label: String(localized: "Zotero item key"),
                    value: occurrence.recommendation.zoteroItemKey
                        ?? String(localized: "Not recorded")
                ),
            ])
        }
    }

    private var discoveryLocators: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("DISCOVERY LOCATORS")
                .scholiumApparatusHeadingStyle()
                .accessibilityHeading(.h2)
            if occurrence.recommendation.sourceLocators.isEmpty {
                Text("No discovery locators were recorded.")
                    .font(ScholiumTypography.interface(.compact))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            } else {
                ForEach(
                    Array(occurrence.recommendation.sourceLocators.enumerated()),
                    id: \.offset
                ) { _, locator in
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: ScholiumGrid.Spacing.inlineControlGap
                    ) {
                        Image(systemName: "text.quote")
                            .font(
                                ScholiumTypography.interface(
                                    .small,
                                    emphasis: .medium
                                )
                            )
                            .foregroundStyle(ScholiumColorRole.secondaryText.color)
                            .accessibilityHidden(true)
                        Text(locator)
                            .font(ScholiumTypography.scholarly(.body))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var recommendationReason: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("WHY IT WAS RECOMMENDED")
                .scholiumApparatusHeadingStyle()
                .accessibilityHeading(.h2)
            Text(occurrence.recommendation.reason)
                .font(ScholiumTypography.scholarly(.body))
                .textSelection(.enabled)
            if let uncertainty = occurrence.recommendation.uncertainty {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.labelAccessoryGap
                ) {
                    Text("UNCERTAINTY")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    Text(uncertainty)
                        .font(ScholiumTypography.scholarly(.body))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var researcherNote: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchRecordEvidenceSectionHeader(
                title: "RESEARCHER NOTE",
                identifier: "scholium.researchRecommendation.noteHeader",
                accessibilityHint: "Review or edit the researcher note"
            ) {
                noteDraft = occurrence.recommendation.disposition.researcherNote ?? ""
                isEditingNote = true
            }
            if let note = occurrence.recommendation.disposition.researcherNote {
                Text(note)
                    .font(ScholiumTypography.scholarly(.body))
                    .textSelection(.enabled)
            } else {
                Text("No researcher note has been added.")
                    .font(ScholiumTypography.interface(.compact))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("SOURCE & PARENT")
                .scholiumApparatusHeadingStyle()
                .accessibilityHeading(.h2)

            if let source = occurrence.parentRecord.sourceReference {
                ResearchRecordEvidenceEntry(
                    symbol: "doc",
                    title: source.displayName,
                    metadata: [String(localized: "Analyzed source")],
                    identifier: "scholium.researchRecommendation.source"
                )
            } else {
                ResearchRecordEvidenceEntry(
                    symbol: "doc.slash",
                    title: String(localized: "Source unavailable"),
                    body: String(localized: "No analyzed source was recorded."),
                    identifier: "scholium.researchRecommendation.source"
                )
            }

            ResearchRecordEvidenceEntry(
                symbol: "doc.text.magnifyingglass",
                title: occurrence.contextTitle,
                metadata: [
                    String(localized: "Analysis"),
                    occurrence.parentRecord.finishedAt.formatted(
                        .dateTime.year().month().day()
                    ),
                ],
                identifier: "scholium.researchRecommendation.openAnalysis",
                accessibilityHint: "Open this Analysis"
            ) {
                guard let participant = analysisParticipant else { return }
                context.openNote(participant.noteID, participant.note, nil)
            }
            .disabled(analysisParticipant == nil)

            ResearchRecordEvidenceEntry(
                symbol: "doc.text",
                title: String(localized: "Parent Research Record"),
                metadata: [
                    occurrence.parentRecord.method?.displayName
                        ?? String(localized: "Analyze"),
                    occurrence.parentRecord.finishedAt.formatted(
                        .dateTime.year().month().day().hour().minute()
                    ),
                ],
                identifier: "scholium.researchRecommendation.openParentRecord",
                accessibilityHint: "Open the parent Research Record"
            ) {
                model.openParentRecord(occurrence.parentRecord.id)
            }
        }
    }

    private var analysisParticipant: PortableResearchNoteRevision? {
        guard let participant = occurrence.parentRecord.researchRecordContextParticipant,
            !participant.isTombstone
        else { return nil }
        return participant
    }
}

private struct ResearchLiteratureRecommendationNoteSheet: View {
    @Binding var draft: String
    let save: @MainActor (String?) async throws -> Void
    let dismiss: () -> Void
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(spacing: ScholiumGrid.Spacing.sectionSeparation) {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.sectionSeparation
                ) {
                    Text("Researcher Note")
                        .font(ScholiumTypography.scholarly(.title))
                        .accessibilityHeading(.h1)
                    Text(
                        "This note records how you handled the reading lead. Saving an empty note removes it without changing the handling status."
                    )
                    .font(ScholiumTypography.interface(.compact))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    TextEditor(text: $draft)
                        .font(ScholiumTypography.scholarly(.body))
                        .scrollContentBackground(.hidden)
                        .padding(ScholiumGrid.Spacing.inlineControlGap)
                        .frame(minHeight: 120, idealHeight: 180)
                        .background(
                            ScholiumColorRole.surfaceBackground.color,
                            in: RoundedRectangle(
                                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                                style: .continuous
                            )
                        )
                        .scholiumBoundary(
                            .subtleBoundary,
                            in: RoundedRectangle(
                                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                                style: .continuous
                            )
                        )
                        .accessibilityLabel("Researcher note")
                        .accessibilityIdentifier(
                            "scholium.researchRecommendation.noteEditor"
                        )
                    if let saveErrorMessage {
                        Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                            .font(ScholiumTypography.interface(.compact, emphasis: .medium))
                            .foregroundStyle(ScholiumColorRole.attention.color)
                            .textSelection(.enabled)
                            .accessibilityIdentifier(
                                "scholium.researchRecommendation.noteSaveError"
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving researcher note")
                }
                Button("Cancel", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("Save", action: beginSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(ScholiumGrid.Spacing.regionContentInset)
        .frame(
            minWidth: 440,
            idealWidth: 480,
            maxWidth: 620,
            minHeight: 320,
            idealHeight: 400,
            maxHeight: 640
        )
        .scholiumSurface(.document)
        .tint(ScholiumColorRole.accent.color)
    }

    private func beginSave() {
        guard !isSaving else { return }
        isSaving = true
        saveErrorMessage = nil
        let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            do {
                try await save(normalized.isEmpty ? nil : normalized)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                saveErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct ResearchRecordEmptyResults: View {
    let model: ResearchRecordBrowserModel

    var body: some View {
        ScholiumContentStateView(
            title,
            detail: Text(detail),
            indicator: .symbol("doc.text.magnifyingglass")
        ) {
            if hasExplicitFilters {
                Button("Clear Filters") { model.clearAllFilters() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("scholium.researchRecords.empty")
    }

    private var title: LocalizedStringResource {
        if !hasExplicitFilters, model.totalRecordCount == 0 {
            return "No Research Records Yet"
        }
        if !hasExplicitFilters, model.scope == .thisNote {
            return "No Research Records for This Note"
        }
        return "No Matching Research Records"
    }

    private var detail: LocalizedStringResource {
        if !hasExplicitFilters, model.totalRecordCount == 0 {
            return "Finished Research Actions will appear here."
        }
        if !hasExplicitFilters, model.scope == .thisNote {
            return "Choose Triptych to review every Record."
        }
        return "Clear a filter or search the complete Triptych."
    }

    private var hasExplicitFilters: Bool {
        !model.searchText.isEmpty
            || model.dateFilter != .any
            || model.methodFilterName != nil
            || model.actionFilterID != nil
            || model.participantFilter != nil
    }
}

private struct ResearchRecordsBackToolbarButton: View {
    let action: () -> Void

    var body: some View {
        ScholiumNativeToolbarButton(
            title: String(localized: "Back to Records"),
            systemImage: "chevron.left",
            identifier: "scholium.researchRecords.back",
            keyEquivalent: "[",
            keyEquivalentModifierMask: .command,
            action: action
        )
    }
}

private struct ResearchRecordsRouteToolbarTitle: View {
    let title: LocalizedStringResource

    var body: some View {
        Text(title)
            .font(ScholiumTypography.interface(.body))
            .foregroundStyle(ScholiumColorRole.primaryText.color)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("scholium.researchRecords.routeTitle")
    }
}

private struct ResearchRecordsCollectionToolbar: ToolbarContent {
    let model: ResearchRecordBrowserModel

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            viewItem.sharedBackgroundVisibility(.hidden)
        } else {
            viewItem
        }
    }

    private var viewItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ResearchRecordsViewIndex(model: model)
                .frame(width: ScholiumMetrics.ResearchRecords.viewIndexWidth)
        }
    }
}

private struct ResearchLiteratureRecommendationDetailToolbar: ToolbarContent {
    let model: ResearchRecordBrowserModel

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            backItem.sharedBackgroundVisibility(.hidden)
            titleItem.sharedBackgroundVisibility(.hidden)
        } else {
            backItem
            titleItem
        }
    }

    private var backItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ResearchRecordsBackToolbarButton(action: model.backToCollection)
        }
    }

    private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ResearchRecordsRouteToolbarTitle(title: "Reading Lead")
        }
    }
}

private struct ResearchRecordDetailToolbar: ToolbarContent {
    let model: ResearchRecordBrowserModel
    @Binding var isEvidencePresented: Bool

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            backItem.sharedBackgroundVisibility(.hidden)
            titleItem.sharedBackgroundVisibility(.hidden)
            evidenceItem.sharedBackgroundVisibility(.hidden)
        } else {
            backItem
            titleItem
            evidenceItem
        }
    }

    private var backItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ResearchRecordsBackToolbarButton(action: model.backToCollection)
        }
    }

    private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ResearchRecordsRouteToolbarTitle(title: "Record")
        }
    }

    private var evidenceItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ScholiumNativeToolbarButton(
                title: String(localized: isEvidencePresented
                    ? "Hide Evidence & Judgment"
                    : "Show Evidence & Judgment"),
                systemImage: "sidebar.trailing",
                identifier: "scholium.researchRecord.toggleEvidence",
                accessibilityValue: isEvidencePresented ? "Shown" : "Hidden"
            ) {
                isEvidencePresented.toggle()
            }
        }
    }
}

private struct ResearchLiteratureRecommendationWorkspaceView: View {
    let occurrence: ResearchLiteratureRecommendationOccurrence
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext

    var body: some View {
        ResearchLiteratureRecommendationDetailView(
            occurrence: occurrence,
            model: model,
            context: context
        )
        .scholiumSurface(.document)
        .accessibilityIdentifier("scholium.researchRecommendation.workspace")
        .toolbar {
            ResearchLiteratureRecommendationDetailToolbar(model: model)
        }
    }
}

private struct ResearchRecordWorkspaceView: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext
    @State private var confirmsPermanentDeletion = false
    @State private var isEvidencePresented = true
    @FocusState private var isDeletionControlFocused: Bool

    var body: some View {
        ScholiumRecordDetailSplitView(
            isEvidencePresented: isEvidencePresented,
            reading: readingPlane,
            evidence: evidenceRail
        )
        .ignoresSafeArea(.container, edges: .top)
        .scholiumSurface(.document)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchRecord.workspace")
        .toolbar {
            ResearchRecordDetailToolbar(
                model: model,
                isEvidencePresented: $isEvidencePresented
            )
        }
        .alert("Delete This Research Record Permanently?", isPresented: $confirmsPermanentDeletion)
        {
            Button("Cancel", role: .cancel) {}
            Button("Delete Permanently", role: .destructive) {
                Task {
                    await model.deletePermanently(
                        recordID: record.id,
                        update: context.deletePermanently
                    )
                }
            }
        } message: {
            Text(
                "This removes the portable record from every derived Note view. It does not delete source Markdown, checkpoints, exact-note recovery, or unrelated records. This action cannot be undone."
            )
        }
        .onChange(of: confirmsPermanentDeletion) { wasPresented, isPresented in
            guard wasPresented && !isPresented else { return }
            Task { @MainActor in
                await Task.yield()
                isDeletionControlFocused = true
            }
        }
    }

    private var readingPlane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                    ResearchRecordDetailHeader(
                        record: record,
                        model: model,
                        deleteFocus: $isDeletionControlFocused,
                        confirmsPermanentDeletion: $confirmsPermanentDeletion
                    )
                    ScholiumStructuralRule()
                    ResearchFinalizedResultView(
                        record: record,
                        presentation: .recordDetail
                    )
                    ScholiumStructuralRule()
                    ResearchRecordStatementSection(
                        statements: record.statements,
                        focusedStatementID: model.focusedStatementID,
                        primaryParticipant: primaryParticipant,
                        openNote: context.openNote
                    )
                    if hasContinuity {
                        ScholiumStructuralRule()
                        ResearchRecordContinuitySection(record: record, model: model)
                    }
                    if !record.literatureRecommendations.isEmpty {
                        ScholiumStructuralRule()
                        ResearchRecordLiteratureRecommendationsSection(
                            record: record,
                            model: model
                        )
                    }
                }
                .padding(.horizontal, ScholiumMetrics.ResearchRecords.pageEdge)
                .padding(.top, ScholiumGrid.Spacing.sectionSeparation)
                .padding(.bottom, ScholiumGrid.Spacing.regionContentInset * 2)
                .frame(maxWidth: ResearchRecordLayout.readingMeasure, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(ScholiumColorRole.documentBackground.color)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Research Record Reading")
            .accessibilityIdentifier("scholium.researchRecord.detail")
            .onAppear {
                if let statementID = model.focusedStatementID {
                    proxy.scrollTo(statementID, anchor: .center)
                }
            }
            .onChange(of: model.focusedStatementID) { _, statementID in
                guard let statementID else { return }
                proxy.scrollTo(statementID, anchor: .center)
            }
        }
    }

    private var evidenceRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.sectionSeparation) {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text("Evidence & Judgment")
                        .font(ScholiumTypography.scholarly(.sectionTitle))
                        .accessibilityHeading(.h1)
                    Text("What this Record used, changed, and leaves to the researcher.")
                        .font(ScholiumTypography.interface(.compact))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScholiumStructuralRule()
                ResearchRecordParticipantSection(
                    participants: record.participatingNotes,
                    primaryNoteID: record.primaryNoteID,
                    context: context
                )

                ScholiumStructuralRule()
                ResearchRecordContextUseSection(
                    entries: record.contextUseReport?.entries ?? [],
                    materials: record.actuallyUsedMaterials,
                    primaryNoteID: record.primaryNoteID,
                    model: model,
                    context: context
                )

                ScholiumStructuralRule()
                ResearchRecordEvidenceSection(
                    resultDisposition: record.resultDisposition,
                    fidelityCompletion: record.fidelityCompletion,
                    changes: record.confirmedChanges,
                    discrepancies: record.discrepancies,
                    participants: record.participatingNotes
                )

                ScholiumStructuralRule()
                ResearchRecordResearcherEvaluationSection(
                    record: record,
                    save: { draft, expectedRevision, resultFingerprint in
                        try await context.saveEvaluation(
                            record.id,
                            draft,
                            expectedRevision,
                            resultFingerprint
                        )
                    },
                    clear: { expectedRevision, resultFingerprint in
                        try await context.clearEvaluation(
                            record.id,
                            expectedRevision,
                            resultFingerprint
                        )
                    },
                    didUpdateRecord: model.acceptUpdatedRecord
                )

                ScholiumStructuralRule()
                ResearchRecordTechnicalDetails(record: record)
            }
            .padding(.horizontal, ScholiumGrid.Spacing.regionContentInset)
            .padding(.top, ScholiumGrid.Spacing.regionContentInset)
            .padding(.bottom, ScholiumGrid.Spacing.regionContentInset * 2)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Evidence and Judgment")
        .accessibilityIdentifier("scholium.researchRecord.evidence")
    }

    private var primaryParticipant: PortableResearchNoteRevision? {
        record.researchRecordContextParticipant
    }

    private var hasContinuity: Bool {
        model.continuationParent(for: record) != nil
            || !model.continuationChildren(for: record.id).isEmpty
    }
}

private struct ResearchRecordContinuitySection: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("CONTINUITY")
                .scholiumApparatusHeadingStyle()
                .accessibilityHeading(.h2)

            if let parent = model.continuationParent(for: record) {
                continuityButton(
                    title:
                        "Continued from \(parent.title.value)",
                    detail: parent.finishedAt.formatted(
                        .dateTime.year().month().day().hour().minute()),
                    symbol: "arrow.turn.up.left",
                    recordID: parent.id
                )
            }

            let children = model.continuationChildren(for: record.id)
            if !children.isEmpty {
                Text("Continue Research")
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                ForEach(children) { child in
                    continuityButton(
                        title: child.title.value,
                        detail: child.finishedAt.formatted(
                            .dateTime.year().month().day().hour().minute()
                        ),
                        symbol: "arrow.turn.down.right",
                        recordID: child.id
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchRecord.continuity")
    }

    private func continuityButton(
        title: String,
        detail: String,
        symbol: String,
        recordID: UUID
    ) -> some View {
        ResearchRecordsRoundedLinkButton {
            model.openRecord(id: recordID)
        } label: {
            HStack(alignment: .top, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(systemName: symbol)
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .frame(width: ScholiumMetrics.Apparatus.iconColumnWidth)
                    .accessibilityHidden(true)
                VStack(
                    alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
                ) {
                    Text(title)
                        .font(ScholiumTypography.interface(.rowTitle))
                        .foregroundStyle(ScholiumColorRole.primaryText.color)
                    Text(detail)
                        .font(ScholiumTypography.interface(.small, emphasis: .medium))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                    .accessibilityHidden(true)
            }
            .frame(
                maxWidth: .infinity, minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
            )
            .padding(.horizontal, ScholiumGrid.Spacing.labelAccessoryGap)
        }
        .accessibilityHint("Open this continuation Record")
    }
}

/// The production counterpart of the original prototype's evidence row. One
/// symbol and one title lead either 12pt body copy or compact provenance.
/// Those roles stay separate so a complete explanation never inherits the
/// 10pt metadata treatment.
private struct ResearchRecordEvidenceEntry: View {
    @FocusState private var isFocused: Bool

    let symbol: String
    let title: String
    let bodyText: String?
    let metadata: [String]
    let tertiary: String?
    let emphasizesTertiary: Bool
    let focusPresentation: ScholiumActivationFocusPresentation
    let identifier: String
    let action: (() -> Void)?
    let accessibilityHint: LocalizedStringResource?

    init(
        symbol: String,
        title: String,
        body: String,
        tertiary: String? = nil,
        emphasizesTertiary: Bool = false,
        focusPresentation: ScholiumActivationFocusPresentation = .contentSurface,
        identifier: String,
        accessibilityHint: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.bodyText = body.isEmpty ? nil : body
        self.metadata = []
        self.tertiary = tertiary
        self.emphasizesTertiary = emphasizesTertiary
        self.focusPresentation = focusPresentation
        self.identifier = identifier
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    init(
        symbol: String,
        title: String,
        metadata: [String],
        tertiary: String? = nil,
        emphasizesTertiary: Bool = false,
        focusPresentation: ScholiumActivationFocusPresentation = .contentSurface,
        identifier: String,
        accessibilityHint: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.bodyText = nil
        self.metadata = metadata.filter { !$0.isEmpty }
        self.tertiary = tertiary
        self.emphasizesTertiary = emphasizesTertiary
        self.focusPresentation = focusPresentation
        self.identifier = identifier
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(
                        ScholiumContentControlButtonStyle(
                            isFocused: usesContentFocusSurface && isFocused,
                            in: RoundedRectangle(
                                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                                style: .continuous
                            )
                        )
                    )
                    .scholiumActivationFocus(
                        $isFocused,
                        presentation: focusPresentation
                    )
                    .accessibilityHint(
                        Text(
                            accessibilityHint ?? "Open recorded evidence"
                        ))
            } else {
                content
                    .textSelection(.enabled)
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: ScholiumMetrics.Apparatus.iconToTextSpacing) {
            Image(systemName: symbol)
                .font(ScholiumTypography.interface(.rowTitle))
                .scholiumContentControlInk(
                    resting: .secondaryText,
                    emphasized: action == nil ? .secondaryText : .accent
                )
                .frame(
                    width: ScholiumMetrics.ResearchRecords.evidenceIconColumnWidth,
                    height: 16
                )
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
            ) {
                Text(title)
                    .font(ScholiumTypography.interface(.sectionTitle))
                    .foregroundStyle(ScholiumColorRole.primaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
                if !metadata.isEmpty {
                    metadataView
                }
                if let bodyText, !bodyText.isEmpty {
                    Text(bodyText)
                        .font(ScholiumTypography.interface(.compact))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tertiary, !tertiary.isEmpty {
                    Text(tertiary)
                        .font(ScholiumTypography.scholarly(.body))
                        .foregroundStyle(
                            emphasizesTertiary
                                ? ScholiumColorRole.primaryText.color
                                : ScholiumColorRole.secondaryText.color
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ScholiumGrid.Spacing.labelAccessoryGap)
        .padding(.vertical, ScholiumGrid.Spacing.opticalAlignmentAdjustment)
        .frame(
            maxWidth: .infinity,
            minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
            alignment: .leading
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: ScholiumShape.editorialControlCornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }

    private var metadataView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                metadataLabels
            }
            VStack(alignment: .leading, spacing: 0) {
                metadataLabels
            }
        }
        .font(ScholiumTypography.interface(.small, emphasis: .medium))
        .foregroundStyle(ScholiumColorRole.mutedText.color)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var usesContentFocusSurface: Bool {
        focusPresentation == .contentSurface
    }

    @ViewBuilder
    private var metadataLabels: some View {
        ForEach(Array(metadata.enumerated()), id: \.offset) { _, item in
            Text(item)
        }
    }
}

/// Collection headings stay quiet when the complete set already fits in the
/// rail. Overflow turns the heading itself into the one disclosure control so
/// the evidence rows never acquire a second column of utility buttons.
private struct ResearchRecordEvidenceSectionHeader: View {
    @FocusState private var isFocused: Bool

    let title: LocalizedStringKey
    let count: Int?
    let identifier: String
    let accessibilityValue: String?
    let accessibilityHint: LocalizedStringResource?
    let action: (() -> Void)?

    init(
        title: LocalizedStringKey,
        count: Int? = nil,
        identifier: String,
        accessibilityValue: String? = nil,
        accessibilityHint: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.count = count
        self.identifier = identifier
        self.accessibilityValue = accessibilityValue
        self.accessibilityHint = accessibilityHint
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    framedHeaderContent
                }
                .buttonStyle(
                    ScholiumContentControlButtonStyle(
                        isFocused: isFocused,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                )
                .scholiumActivationFocus($isFocused)
                .accessibilityLabel(Text(title))
                .accessibilityHeading(.h2)
                .accessibilityValue(accessibilityValue ?? "")
                .accessibilityHint(Text(accessibilityHint ?? "Open this section"))
                .accessibilityIdentifier(identifier)
            } else {
                framedHeaderContent
                    .accessibilityElement(children: .combine)
                    .accessibilityHeading(.h2)
                    .accessibilityIdentifier(identifier)
            }
        }
    }

    private var headerContent: some View {
        HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(title)
                .scholiumApparatusHeadingStyle()
            Spacer(minLength: 0)
            if let count, count > 0 {
                Text("\(count)")
                    .font(
                        ScholiumTypography.interface(.small, emphasis: .medium, tabularDigits: true)
                    )
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
            }
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(ScholiumTypography.interface(.small, emphasis: .strong))
                    .scholiumContentControlInk(
                        resting: .mutedText,
                        emphasized: .accent
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    private var framedHeaderContent: some View {
        headerContent
            .padding(.horizontal, ScholiumGrid.Spacing.labelAccessoryGap)
            .frame(
                maxWidth: .infinity,
                minHeight: ScholiumMetrics.ResearchRecords.evidenceSectionHeaderHeight,
                alignment: .leading
            )
            .contentShape(
                RoundedRectangle(
                    cornerRadius: ScholiumShape.editorialControlCornerRadius,
                    style: .continuous
                ))
    }
}

private struct ResearchRecordEvidenceCollectionPopover<Content: View>: View {
    let title: LocalizedStringKey
    let count: Int
    let identifier: String
    let content: Content

    init(
        title: LocalizedStringKey,
        count: Int,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(ScholiumTypography.interface(.sectionTitle))
                    .accessibilityHeading(.h1)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Text("\(count)")
                    .font(
                        ScholiumTypography.interface(.small, emphasis: .medium, tabularDigits: true)
                    )
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)

            ScholiumStructuralRule()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    content
                }
                .padding(ScholiumGrid.Spacing.regionContentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(
            width: ScholiumMetrics.ResearchRecords.evidenceCollectionPopoverWidth,
            height: ScholiumMetrics.ResearchRecords.evidenceCollectionPopoverHeight
        )
        .scholiumSurface(.document)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

private struct ResearchRecordContextUseSection: View {
    let entries: [ContextUseEntry]
    let materials: [PortableResearchMaterialUse]
    let primaryNoteID: UUID?
    let model: ResearchRecordBrowserModel
    let context: ResearchRecordBrowserContext
    @State private var isShowingAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchRecordEvidenceSectionHeader(
                title: "CONTEXT USED",
                count: itemCount,
                identifier: "scholium.researchRecord.contextUseHeader",
                accessibilityValue: hasMore
                    ? "\(itemCount) items, showing the first \(previewLimit)"
                    : "\(itemCount) items",
                accessibilityHint: "Show every recorded Context item",
                action: hasMore ? { isShowingAll = true } : nil
            )
            .popover(
                isPresented: $isShowingAll,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                ResearchRecordEvidenceCollectionPopover(
                    title: "Context Used",
                    count: itemCount,
                    identifier: "scholium.researchRecord.contextUsePopover"
                ) {
                    allItems
                }
            }

            if entries.isEmpty && materials.isEmpty {
                ResearchRecordEvidenceEntry(
                    symbol: "text.quote",
                    title: "No verified context use",
                    body: "Selection or delivery was not treated as scholarly use.",
                    identifier: "scholium.researchRecord.contextUse.empty"
                )
            } else if !entries.isEmpty {
                ForEach(Array(orderedEntries.prefix(previewLimit))) { entry in
                    entryView(entry, identifierSuffix: nil)
                }
            } else {
                ForEach(Array(orderedMaterials.prefix(previewLimit))) { material in
                    materialView(material, identifierSuffix: nil)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var allItems: some View {
        if !entries.isEmpty {
            ForEach(orderedEntries) { entry in
                entryView(
                    entry,
                    identifierSuffix: ".all",
                    focusPresentation: .native
                )
            }
        } else {
            ForEach(orderedMaterials) { material in
                materialView(
                    material,
                    identifierSuffix: ".all",
                    focusPresentation: .native
                )
            }
        }
    }

    private var itemCount: Int {
        entries.isEmpty ? materials.count : entries.count
    }

    private var hasMore: Bool {
        itemCount > previewLimit
    }

    private var previewLimit: Int {
        ScholiumMetrics.ResearchRecords.evidencePreviewLimit
    }

    /// The Action's focal Note leads, followed by other actionable scholarly
    /// sources. Exact but unresolved references remain in the complete set.
    private var orderedEntries: [ContextUseEntry] {
        entries.enumerated()
            .sorted { left, right in
                let leftRank = contextRank(left.element)
                let rightRank = contextRank(right.element)
                return leftRank == rightRank
                    ? left.offset < right.offset
                    : leftRank < rightRank
            }
            .map(\.element)
    }

    private var orderedMaterials: [PortableResearchMaterialUse] {
        materials.sorted { left, right in
            let leftRank = materialRank(left)
            let rightRank = materialRank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            if left.role != right.role {
                return roleRank(left.role) < roleRank(right.role)
            }
            return left.noteID.uuidString < right.noteID.uuidString
        }
    }

    private func contextRank(_ entry: ContextUseEntry) -> Int {
        guard let destination = destination(for: entry) else { return 2 }
        guard case .note(let noteID, _, _) = destination else { return 1 }
        return noteID == primaryNoteID ? 0 : 1
    }

    private func materialRank(_ material: PortableResearchMaterialUse) -> Int {
        material.noteID == primaryNoteID ? 0 : 1
    }

    private func roleRank(_ role: ResearchActionTargetRole) -> Int {
        switch role {
        case .topic: 0
        case .analysis: 1
        case .work: 2
        }
    }

    private func entryView(
        _ entry: ContextUseEntry,
        identifierSuffix: String?,
        focusPresentation: ScholiumActivationFocusPresentation = .contentSurface
    ) -> some View {
        ResearchRecordContextUseEntryView(
            entry: entry,
            destination: destination(for: entry),
            identifierSuffix: identifierSuffix,
            focusPresentation: focusPresentation,
            open: open
        )
    }

    private func materialView(
        _ material: PortableResearchMaterialUse,
        identifierSuffix: String?,
        focusPresentation: ScholiumActivationFocusPresentation = .contentSurface
    ) -> some View {
        ResearchRecordEvidenceEntry(
            symbol: "text.quote",
            title: material.title,
            metadata: [material.role.interfaceTitle, "Agent-reported use"],
            focusPresentation: focusPresentation,
            identifier:
                "scholium.researchRecord.material.\(material.noteID.uuidString)\(identifierSuffix ?? "")",
            accessibilityHint: "Open this reported research material",
            action: {
                isShowingAll = false
                context.openNote(material.noteID, material.note, nil)
            }
        )
    }

    private func open(_ destination: ResearchContextUseDestination) {
        isShowingAll = false
        switch destination {
        case .note(let noteID, let note, let line):
            context.openNote(noteID, note, line)
        case .record(let recordID, let statementID):
            model.openRecord(id: recordID, statementID: statementID)
        }
    }

    private func destination(for entry: ContextUseEntry) -> ResearchContextUseDestination? {
        let source = entry.sourceReference
        switch source.owner.kind {
        case .note:
            guard let noteID = UUID(uuidString: source.owner.stableObjectIdentity),
                let vaultID = source.owner.vaultID,
                let relativePath = source.owner.relativePath
            else { return nil }
            return .note(
                noteID,
                VaultQualifiedNoteID(vaultID: vaultID, relativePath: relativePath),
                source.locator.sourceRange?.line
            )
        case .record:
            guard let recordID = source.owner.recordID,
                model.record(id: recordID) != nil
            else { return nil }
            return .record(recordID, source.locator.statementID)
        case .material, .researcherState:
            return nil
        }
    }

}

private enum ResearchContextUseDestination {
    case note(UUID, VaultQualifiedNoteID, Int?)
    case record(UUID, UUID?)
}

private struct ResearchRecordContextUseEntryView: View {
    let entry: ContextUseEntry
    let destination: ResearchContextUseDestination?
    let identifierSuffix: String?
    let focusPresentation: ScholiumActivationFocusPresentation
    let open: (ResearchContextUseDestination) -> Void

    var body: some View {
        ResearchRecordEvidenceEntry(
            symbol: "text.quote",
            title: title,
            metadata: [locatorDescription],
            tertiary: entry.testimony,
            focusPresentation: focusPresentation,
            identifier:
                "scholium.researchRecord.contextUse.\(entry.id.uuidString)\(identifierSuffix ?? "")",
            accessibilityHint: destination == nil
                ? nil
                : "Open the exact recorded evidence context",
            action: destination.map { destination in
                { open(destination) }
            }
        )
    }

    private var title: String {
        let source = entry.sourceReference
        switch source.owner.kind {
        case .note:
            guard let relativePath = source.owner.relativePath else { return "Recorded Note" }
            return URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
        case .record:
            return
                "Research Record \(source.owner.recordID?.uuidString.lowercased().prefix(8) ?? "")"
        case .material:
            return "Source Material"
        case .researcherState:
            return "Researcher State"
        }
    }

    private var locatorDescription: String {
        let locator = entry.sourceReference.locator
        return switch locator.kind {
        case .sourceRange:
            if let range = locator.sourceRange {
                range.line == range.endLine
                    ? "Line \(range.line)"
                    : "Lines \(range.line)–\(range.endLine)"
            } else {
                "Recorded source range"
            }
        case .recordStatement:
            "Attributed statement \(locator.statementID?.uuidString.lowercased().prefix(8) ?? "")"
        case .materialLocator:
            locator.materialLocator ?? "Recorded material locator"
        case .wholeObject:
            "Whole recorded object"
        case .unknown:
            "Exact locator unavailable"
        }
    }

}

private struct ResearchRecordLiteratureRecommendationsSection: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("READING LEADS")
                .scholiumApparatusHeadingStyle()
                .accessibilityHeading(.h2)
            ForEach(record.literatureRecommendations) { recommendation in
                ResearchRecordsRoundedLinkButton {
                    model.openRecommendation(
                        recordID: record.id,
                        recommendationID: recommendation.id
                    )
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(
                            alignment: .leading,
                            spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment
                        ) {
                            Text(recommendation.title ?? recommendation.rawCitation)
                                .font(ScholiumTypography.scholarly(.body))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let title = recommendation.title,
                                title != recommendation.rawCitation
                            {
                                Text(recommendation.rawCitation)
                                    .font(ScholiumTypography.scholarly(.body))
                                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                                    .lineLimit(2)
                            }
                        }
                        Text(
                            recommendation.disposition.status == .handled
                                ? "Handled"
                                : "Unprocessed"
                        )
                        .font(ScholiumTypography.interface(.small, emphasis: .medium))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    }
                    .padding(.horizontal, ScholiumGrid.Spacing.labelAccessoryGap)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget
                    )
                }
                .accessibilityHint("Open this Reading Lead")
                .accessibilityIdentifier(
                    "scholium.researchRecord.recommendation.\(recommendation.id.uuidString)"
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ResearchRecordDetailHeader: View {
    let record: PortableResearchRecord
    let model: ResearchRecordBrowserModel
    let deleteFocus: FocusState<Bool>.Binding
    @Binding var confirmsPermanentDeletion: Bool

    var body: some View {
        let actionID =
            record.kind == .discussion
            ? ResearchActionID.discuss
            : record.action?.actionID ?? .discuss
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Text(verbatim: actionTitle(actionID))
                        .foregroundStyle(ScholiumColorRole.accent.color)
                    if record.resultDisposition == .blocked {
                        Text("BLOCKED")
                            .foregroundStyle(ScholiumColorRole.attention.color)
                    }
                    Text(record.finishedAt, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                }
                .font(ScholiumTypography.interface(.small, emphasis: .strong, tabularDigits: true))
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                ScholiumInkIconControl(
                    title: "Delete Research Record…",
                    systemImage: "trash",
                    identifier: "scholium.researchRecord.deletePermanently",
                    role: .destructive,
                    emphasizedColorRole: .destructive,
                    focus: deleteFocus
                ) {
                    confirmsPermanentDeletion = true
                }
                .accessibilityHint(
                    "Ask for confirmation before permanently deleting only this portable record"
                )
                .disabled(model.mutatingRecordIDs.contains(record.id))
            }

            Text(record.title.value)
                .font(ScholiumTypography.scholarly(.title))
                .foregroundStyle(ScholiumColorRole.primaryText.color)
                .textSelection(.enabled)
                .accessibilityHeading(.h1)

            if !headerMetadata(record: record, actionID: actionID).isEmpty {
                HStack(
                    alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap
                ) {
                    Image(systemName: headerSymbol)
                        .font(ScholiumTypography.interface(.compact, emphasis: .medium))
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .accessibilityHidden(true)
                    ViewThatFits(in: .horizontal) {
                        HStack(
                            alignment: .firstTextBaseline,
                            spacing: ScholiumGrid.Spacing.nestedContentInset
                        ) {
                            headerMetadataLabels(record: record, actionID: actionID)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            headerMetadataLabels(record: record, actionID: actionID)
                        }
                    }
                    .font(ScholiumTypography.interface(.small, emphasis: .medium))
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
                }
                .textSelection(.enabled)
            }
        }
    }

    private func headerMetadata(
        record: PortableResearchRecord,
        actionID: ResearchActionID
    ) -> [String] {
        let action = actionTitle(actionID)
        let method: String?
        if let name = record.method?.displayName {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty,
                normalized.caseInsensitiveCompare(action) != .orderedSame,
                normalized.caseInsensitiveCompare("\(action) Note") != .orderedSame,
                normalized.caseInsensitiveCompare(
                    record.researchRecordFocalNoteTitle ?? ""
                ) != .orderedSame
            {
                method = normalized
            } else {
                method = nil
            }
        } else {
            method = nil
        }
        let source: String?
        if let name = record.sourceReference?.displayName,
            name.caseInsensitiveCompare(
                record.researchRecordFocalNoteTitle ?? ""
            ) != .orderedSame
        {
            source = name
        } else {
            source = nil
        }
        return [
            record.researchRecordFocalNoteTitle,
            record.researchRecordContextParticipant?.role.interfaceTitle,
            method,
            source,
        ]
        .compactMap { $0 }
    }

    @ViewBuilder
    private func headerMetadataLabels(
        record: PortableResearchRecord,
        actionID: ResearchActionID
    ) -> some View {
        ForEach(
            Array(headerMetadata(record: record, actionID: actionID).enumerated()), id: \.offset
        ) {
            _, item in
            Text(item)
        }
    }

    private var headerSymbol: String {
        switch record.researchRecordContextParticipant?.role {
        case .analysis: "doc.text.magnifyingglass"
        case .topic: "doc.text"
        case .work: "books.vertical"
        case nil: "doc.text"
        }
    }
}

private struct ResearchRecordParticipantSection: View {
    let participants: [PortableResearchNoteRevision]
    let primaryNoteID: UUID?
    let context: ResearchRecordBrowserContext
    @State private var isShowingAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchRecordEvidenceSectionHeader(
                title: "PARTICIPANTS",
                count: participants.count,
                identifier: "scholium.researchRecord.participantsHeader",
                accessibilityValue: hasMore
                    ? "\(participants.count) items, showing the first \(previewLimit)"
                    : "\(participants.count) items",
                accessibilityHint: "Show every participating Note",
                action: hasMore ? { isShowingAll = true } : nil
            )
            .popover(
                isPresented: $isShowingAll,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .trailing
            ) {
                ResearchRecordEvidenceCollectionPopover(
                    title: "Participants",
                    count: participants.count,
                    identifier: "scholium.researchRecord.participantsPopover"
                ) {
                    ForEach(orderedParticipants) { participant in
                        participantView(
                            participant,
                            identifierSuffix: ".all",
                            focusPresentation: .native
                        )
                    }
                }
            }

            ForEach(Array(orderedParticipants.prefix(previewLimit))) { participant in
                participantView(participant, identifierSuffix: nil)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var hasMore: Bool {
        participants.count > previewLimit
    }

    private var previewLimit: Int {
        ScholiumMetrics.ResearchRecords.evidencePreviewLimit
    }

    /// The Action's focal Note leads the current scholarly routes. Tombstones
    /// remain visible after every current Note in the complete provenance set.
    private var orderedParticipants: [PortableResearchNoteRevision] {
        participants.sorted { left, right in
            let leftRank = participantRank(left)
            let rightRank = participantRank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            if left.role != right.role {
                return roleRank(left.role) < roleRank(right.role)
            }
            return left.noteID.uuidString < right.noteID.uuidString
        }
    }

    private func participantRank(_ participant: PortableResearchNoteRevision) -> Int {
        if participant.isTombstone { return 2 }
        return participant.noteID == primaryNoteID ? 0 : 1
    }

    private func roleRank(_ role: ResearchActionTargetRole) -> Int {
        switch role {
        case .topic: 0
        case .analysis: 1
        case .work: 2
        }
    }

    @ViewBuilder
    private func participantView(
        _ participant: PortableResearchNoteRevision,
        identifierSuffix: String?,
        focusPresentation: ScholiumActivationFocusPresentation = .contentSurface
    ) -> some View {
        if participant.isTombstone {
            ResearchRecordEvidenceEntry(
                symbol: "trash.slash",
                title: participant.title,
                metadata: [participant.role.interfaceTitle, "Deleted Note"],
                focusPresentation: focusPresentation,
                identifier:
                    "scholium.researchRecord.tombstone.\(participant.noteID.uuidString)\(identifierSuffix ?? "")"
            )
        } else {
            ResearchRecordEvidenceEntry(
                symbol: participantSymbol(participant.role),
                title: participant.title,
                metadata: [participant.role.interfaceTitle, "Current Note"],
                focusPresentation: focusPresentation,
                identifier:
                    "scholium.researchRecord.note.\(participant.noteID.uuidString)\(identifierSuffix ?? "")",
                accessibilityHint: "Open this participating Note in the focused workspace",
                action: {
                    isShowingAll = false
                    context.openNote(participant.noteID, participant.note, nil)
                }
            )
        }
    }

    private func participantSymbol(_ role: ResearchActionTargetRole) -> String {
        switch role {
        case .analysis: "doc.text.magnifyingglass"
        case .topic: "doc.text"
        case .work: "books.vertical"
        }
    }
}

private struct ResearchRecordStatementSection: View {
    let statements: [PortableResearchStatement]
    let focusedStatementID: UUID?
    let primaryParticipant: PortableResearchNoteRevision?
    let openNote: @MainActor (UUID, VaultQualifiedNoteID, Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.nestedContentInset) {
            Text("ATTRIBUTED RECORD")
                .scholiumApparatusHeadingStyle()
                .accessibilityHeading(.h2)
                .accessibilityIdentifier("scholium.researchRecord.attributedHeading")
            if statements.isEmpty {
                Text("No attributed prose was recorded.")
                    .font(ScholiumTypography.interface(.compact))
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
            } else {
                ForEach(statements) { statement in
                    ResearchRecordStatementView(
                        statementID: statement.id,
                        attribution: statement.attribution,
                        author: statement.author,
                        text: statement.text,
                        createdAt: statement.createdAt,
                        lineReference: statement.lineReference,
                        primaryParticipant: primaryParticipant,
                        openNote: openNote
                    )
                    .id(statement.id)
                    .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
                    .background(
                        statement.id == focusedStatementID
                            ? ScholiumColorRole.accent.color.opacity(0.10)
                            : Color.clear,
                        in: RoundedRectangle(
                            cornerRadius: ScholiumShape.editorialControlCornerRadius,
                            style: .continuous
                        )
                    )
                    .accessibilityAddTraits(
                        statement.id == focusedStatementID ? .isSelected : []
                    )
                    if statement.id != statements.last?.id {
                        ScholiumStructuralRule()
                            .padding(
                                .leading,
                                ScholiumMetrics.ResearchRecords.statementAttributionWidth
                                    + ScholiumMetrics.ResearchRecords.statementColumnGap
                            )
                    }
                }
            }
        }
    }
}

private struct ResearchRecordStatementView: View {
    let statementID: UUID
    let attribution: String
    let author: PortableResearchStatementAuthor
    let text: String
    let createdAt: Date
    let lineReference: ResearchLineReference?
    let primaryParticipant: PortableResearchNoteRevision?
    let openNote: @MainActor (UUID, VaultQualifiedNoteID, Int?) -> Void

    var body: some View {
        HStack(
            alignment: .top,
            spacing: ScholiumMetrics.ResearchRecords.statementColumnGap
        ) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Image(systemName: authorSymbol)
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .accessibilityHidden(true)
                    Text(author.interfaceTitle)
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                }
                .foregroundStyle(authorColor)
                .accessibilityIdentifier(
                    "scholium.researchRecord.statementRole.\(statementID.uuidString)"
                )

                if let distinctAttribution {
                    Text(distinctAttribution)
                        .font(ScholiumTypography.interface(.small, emphasis: .medium))
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(createdAt, format: .dateTime.month().day().hour().minute())
                    .font(ScholiumTypography.interface(.small, emphasis: .medium))
                    .foregroundStyle(ScholiumColorRole.mutedText.color)
            }
            .frame(
                width: ScholiumMetrics.ResearchRecords.statementAttributionWidth,
                alignment: .topLeading
            )

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Text(text)
                    .font(ScholiumTypography.scholarly(.body))
                    .foregroundStyle(ScholiumColorRole.primaryText.color)
                    .lineSpacing(ScholiumGrid.Spacing.labelAccessoryGap)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let lineReference, let primaryParticipant, !primaryParticipant.isTombstone {
                    ResearchRecordActionButton(
                        "Open Lines \(lineReference.line)–\(lineReference.endLine)",
                        systemImage: "text.line.first.and.arrowtriangle.forward",
                        identifier: "scholium.researchRecord.openLines"
                    ) {
                        openNote(
                            primaryParticipant.noteID,
                            primaryParticipant.note,
                            lineReference.line
                        )
                    }
                    .accessibilityHint("Open the original revision-bound Comment location")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(author.interfaceTitle), \(attribution)")
        .accessibilityIdentifier(
            "scholium.researchRecord.statement.\(statementID.uuidString)"
        )
    }

    private var authorColor: Color {
        switch author {
        case .researcher: ScholiumColorRole.accent.color
        case .agent: ScholiumColorRole.agentAuthorship.color
        }
    }

    private var authorSymbol: String {
        switch author {
        case .researcher: "person"
        case .agent: "sparkle"
        }
    }

    private var distinctAttribution: String? {
        let trimmed = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            trimmed.caseInsensitiveCompare(author.interfaceTitle) != .orderedSame
        else {
            return nil
        }
        return trimmed
    }
}

private struct ResearchRecordEvidenceSection: View {
    let resultDisposition: ResearchAgentResultDisposition
    let fidelityCompletion: PortableResearchFidelityCompletion
    let changes: [PortableResearchConfirmedChange]
    let discrepancies: [PortableResearchDiscrepancy]
    let participants: [PortableResearchNoteRevision]

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ResearchRecordEvidenceSectionHeader(
                title: "EFFECTS",
                identifier: "scholium.researchRecord.effectsHeader"
            )

            ResearchRecordEvidenceEntry(
                symbol: changes.isEmpty ? "lock.open" : "doc.badge.arrow.up",
                title: changes.isEmpty
                    ? "No source changes"
                    : "\(changes.count) confirmed source changes",
                body: changeDetail,
                identifier: "scholium.researchRecord.effects.changes"
            )
            ResearchRecordEvidenceEntry(
                symbol: resultDisposition == .completed
                    ? "checkmark.seal"
                    : "exclamationmark.circle",
                title: resultDisposition == .completed
                    ? "Record finalized"
                    : "Record blocked",
                body: resultDisposition == .completed
                    ? "The scholarly result was finalized as a portable Record."
                    : "The Run ended without a completed scholarly result.",
                identifier: "scholium.researchRecord.effects.result"
            )
            ResearchRecordEvidenceEntry(
                symbol: fidelityCompletion == .unverified
                    ? "exclamationmark.triangle"
                    : fidelityCompletion == .notApplicable
                        ? "minus.circle"
                        : "checkmark.seal",
                title: fidelityTitle,
                body: fidelityDetail,
                identifier: fidelityCompletion == .unverified
                    ? "scholium.researchRecord.fidelity.unverified"
                    : "scholium.researchRecord.effects.fidelity"
            )
            ForEach(discrepancies) { discrepancy in
                ResearchRecordEvidenceEntry(
                    symbol: "exclamationmark.triangle",
                    title: "Recorded discrepancy",
                    body: discrepancy.interfaceDescription(participants: participants),
                    identifier: "scholium.researchRecord.discrepancy.\(discrepancy.id.uuidString)"
                )
            }
        }
    }

    private var changeDetail: String {
        guard !changes.isEmpty else {
            return String(localized: "Research sources remain unchanged.")
        }
        let titles = changes.compactMap { change in
            participants.first { $0.noteID == change.noteID }?.title
        }
        guard !titles.isEmpty else {
            return String(localized: "Scholium confirmed the recorded revision changes.")
        }
        return String(
            localized: "Scholium confirmed changes to \(titles.joined(separator: ", "))."
        )
    }

    private var fidelityTitle: String {
        switch fidelityCompletion {
        case .notRequired: String(localized: "Fidelity not required")
        case .completed: String(localized: "Fidelity completed")
        case .unverified: String(localized: "Fidelity unverified")
        case .notApplicable: String(localized: "Fidelity not applicable")
        }
    }

    private var fidelityDetail: String {
        switch fidelityCompletion {
        case .notRequired:
            String(localized: "This Action did not require source-fidelity verification.")
        case .completed:
            String(localized: "Recorded revision fidelity was completed.")
        case .unverified:
            String(localized: "Fidelity could not be completed for this recorded revision.")
        case .notApplicable:
            String(localized: "Source-fidelity verification does not apply to this Record.")
        }
    }
}

private struct ResearchRecordResearcherEvaluationSection: View {
    let record: PortableResearchRecord
    let save: ResearcherEvaluationView.Save
    let clear: ResearcherEvaluationView.Clear
    let didUpdateRecord: (PortableResearchRecord) -> Void
    @State private var isPresentingEditor = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Button {
                isPresentingEditor = true
            } label: {
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text("RESEARCHER EVALUATION")
                        .scholiumApparatusHeadingStyle()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .scholiumContentControlInk(
                            resting: .mutedText,
                            emphasized: .accent
                        )
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, ScholiumGrid.Spacing.labelAccessoryGap)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ScholiumMetrics.ResearchRecords.evidenceSectionHeaderHeight,
                    alignment: .leading
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    ))
            }
            .buttonStyle(
                ScholiumContentControlButtonStyle(
                    isFocused: isFocused,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
            )
            .scholiumActivationFocus($isFocused)
            .accessibilityLabel("Researcher Evaluation")
            .accessibilityHeading(.h2)
            .accessibilityValue(
                record.researcherEvaluation == nil ? "Not yet evaluated" : "Evaluation saved"
            )
            .accessibilityHint("Review or edit the researcher evaluation")
            .accessibilityIdentifier("scholium.researchRecord.evaluationEditor")
            .sheet(isPresented: $isPresentingEditor, onDismiss: restoreFocus) {
                ResearchRecordEvaluationSheet(
                    record: record,
                    save: save,
                    clear: clear,
                    didUpdateRecord: didUpdateRecord
                )
            }

            if let evaluation = record.researcherEvaluation {
                if evaluation.noIssuesObserved {
                    ResearchRecordEvidenceEntry(
                        symbol: "checkmark.circle",
                        title: "No issues observed",
                        body: "The researcher marked no issue in this Record.",
                        identifier: "scholium.researchRecord.evaluation.noIssues"
                    )
                }
                if !evaluation.observedIssues.isEmpty {
                    ResearchRecordEvidenceEntry(
                        symbol: "exclamationmark.bubble",
                        title: "\(evaluation.observedIssues.count) observed issues",
                        body: evaluation.observedIssues
                            .map(\.interfaceTitle)
                            .joined(separator: ", "),
                        identifier: "scholium.researchRecord.evaluation.issues"
                    )
                }
                if evaluation.valuableDiscovery {
                    ResearchRecordEvidenceEntry(
                        symbol: "sparkles",
                        title: "Valuable discovery",
                        body: "The researcher marked this result as worth retaining.",
                        identifier: "scholium.researchRecord.evaluation.discovery"
                    )
                }
                if let note = evaluation.note {
                    ResearchRecordEvidenceEntry(
                        symbol: "note.text",
                        title: "Researcher note",
                        metadata: ["Researcher-authored judgment"],
                        tertiary: note,
                        emphasizesTertiary: true,
                        identifier: "scholium.researchRecord.evaluation.note"
                    )
                }
            } else {
                ResearchRecordEvidenceEntry(
                    symbol: "person.crop.circle",
                    title: "Not yet evaluated",
                    body: "Add a researcher judgment without changing the Agent result.",
                    identifier: "scholium.researchRecord.evaluation.empty"
                )
            }

        }
    }

    private func restoreFocus() {
        Task { @MainActor in
            await Task.yield()
            isFocused = true
        }
    }
}

private struct ResearchRecordEvaluationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let record: PortableResearchRecord
    let save: ResearcherEvaluationView.Save
    let clear: ResearcherEvaluationView.Clear
    let didUpdateRecord: (PortableResearchRecord) -> Void

    @State private var hasUnsavedChanges = false
    @State private var confirmsDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("Researcher Evaluation")
                    .font(ScholiumTypography.interface(.sectionTitle))
                    .accessibilityHeading(.h1)
                Text(
                    "Review or record your judgment without changing the Agent's finalized result."
                )
                .font(ScholiumTypography.interface(.compact))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
            .frame(maxWidth: .infinity, alignment: .leading)

            ScholiumStructuralRule()

            ScrollView {
                ResearcherEvaluationView(
                    record: record,
                    save: save,
                    clear: clear,
                    didUpdateRecord: didUpdateRecord,
                    draftStateDidChange: { hasUnsavedChanges = $0 },
                    showsIntroduction: false
                )
                .padding(ScholiumGrid.Spacing.regionContentInset)
            }

            ScholiumStructuralRule()

            HStack {
                Button("Done", action: attemptDismiss)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("scholium.researchRecord.evaluationDismiss")
                Spacer(minLength: 0)
            }
            .padding(ScholiumGrid.Spacing.regionContentInset)
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 500, idealHeight: 620)
        .scholiumSurface(.document)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.researchRecord.evaluationSheet")
        .alert(
            "Discard the Unsaved Evaluation Draft?",
            isPresented: $confirmsDiscard
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Draft and Close", role: .destructive) {
                hasUnsavedChanges = false
                dismiss()
            }
        } message: {
            Text("The saved evaluation and finalized Research Result will remain unchanged.")
        }
    }

    private func attemptDismiss() {
        if hasUnsavedChanges {
            confirmsDiscard = true
        } else {
            dismiss()
        }
    }
}

private struct ResearchRecordTechnicalDetails: View {
    let record: PortableResearchRecord

    var body: some View {
        ResearchRecordsTechnicalDetailsDisclosure(
            identifier: "scholium.researchRecord.technicalDetails"
        ) {
            VStack(
                alignment: .leading,
                spacing: ScholiumMetrics.Apparatus.readingBlockSpacing
            ) {
                ScholiumApparatusFactGrid(facts: facts)
                ForEach(record.participatingNotes) { participant in
                    ResearchRecordRevisionDetails(participant: participant)
                }
            }
        }
    }

    private var facts: [ScholiumApparatusFact] {
        [
            ScholiumApparatusFact(
                id: "kind",
                label: String(localized: "Record kind"),
                value: record.kind.interfaceTitle
            ),
            ScholiumApparatusFact(
                id: "schema",
                label: String(localized: "Schema"),
                value: String(
                    localized: "Portable Research Record, version \(record.schemaVersion)"
                )
            ),
            ScholiumApparatusFact(
                id: "integrity",
                label: String(localized: "Integrity"),
                value: String(localized: "Finalized, current schema")
            ),
            ScholiumApparatusFact(
                id: "identifier",
                label: String(localized: "Record identifier"),
                value: record.id.uuidString.lowercased(),
                valueStyle: .revisionIdentity
            ),
            ScholiumApparatusFact(
                id: "method",
                label: String(localized: "Method"),
                value: record.method?.displayName ?? String(localized: "Not recorded")
            ),
            ScholiumApparatusFact(
                id: "practices",
                label: String(localized: "Practices"),
                value: record.method?.practiceNames.isEmpty == false
                    ? record.method?.practiceNames.joined(separator: ", ") ?? ""
                    : String(localized: "Not recorded")
            ),
            ScholiumApparatusFact(
                id: "source",
                label: String(localized: "Source"),
                value: record.sourceReference?.displayName
                    ?? String(localized: "Not recorded")
            ),
        ]
    }
}

private struct ResearchRecordRevisionDetails: View {
    let participant: PortableResearchNoteRevision

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text(participant.title)
                .font(ScholiumTypography.interface(.small, emphasis: .strong))
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
            ScholiumApparatusFactGrid(facts: [
                ScholiumApparatusFact(
                    id: "\(participant.id)-starting",
                    label: String(localized: "Starting revision"),
                    value: participant.startingRevision.sha256,
                    valueStyle: .revisionIdentity
                ),
                ScholiumApparatusFact(
                    id: "\(participant.id)-ending",
                    label: String(localized: "Ending revision"),
                    value: participant.endingRevision?.sha256
                        ?? String(localized: "Deleted Note"),
                    valueStyle: participant.endingRevision == nil
                        ? .researchContent
                        : .revisionIdentity
                ),
            ])
        }
    }
}

private struct ResearchLiteratureRecommendationTechnicalDetails: View {
    let occurrence: ResearchLiteratureRecommendationOccurrence

    var body: some View {
        ResearchRecordsTechnicalDetailsDisclosure(
            identifier: "scholium.researchRecommendation.technicalDetails"
        ) {
            ScholiumApparatusFactGrid(facts: [
                ScholiumApparatusFact(
                    id: "source-revision",
                    label: String(localized: "Exact source revision"),
                    value: occurrence.parentRecord.sourceReference?.fingerprint.sha256
                        ?? String(localized: "Not recorded"),
                    valueStyle: occurrence.parentRecord.sourceReference == nil
                        ? .researchContent
                        : .revisionIdentity
                ),
                ScholiumApparatusFact(
                    id: "parent-record",
                    label: String(localized: "Parent Record"),
                    value: occurrence.parentRecord.id.uuidString.lowercased(),
                    valueStyle: .revisionIdentity
                ),
            ])
        }
    }
}

private struct ResearchRecordsTechnicalDetailsDisclosure<Content: View>: View {
    let identifier: String
    let content: Content
    @State private var isExpanded = false
    @FocusState private var isFocused: Bool

    init(
        identifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.identifier = identifier
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Image(systemName: "chevron.right")
                        .font(ScholiumTypography.interface(.small, emphasis: .strong))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(ScholiumColorRole.mutedText.color)
                        .accessibilityHidden(true)
                    Text("TECHNICAL DETAILS")
                        .scholiumApparatusHeadingStyle()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, ScholiumGrid.Spacing.labelAccessoryGap)
                .frame(
                    maxWidth: .infinity,
                    minHeight: ScholiumMetrics.Accessibility.preferredCustomTarget,
                    alignment: .leading
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    ))
            }
            .buttonStyle(
                ScholiumContentControlButtonStyle(
                    isFocused: isFocused,
                    in: RoundedRectangle(
                        cornerRadius: ScholiumShape.editorialControlCornerRadius,
                        style: .continuous
                    )
                )
            )
            .scholiumActivationFocus($isFocused)
            .accessibilityLabel("Technical Details")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier(identifier)

            if isExpanded {
                content
                    .padding(.top, ScholiumGrid.Spacing.inlineControlGap)
            }
        }
    }
}

extension PortableResearchObservedIssue {
    fileprivate var interfaceTitle: String {
        switch self {
        case .sourceOrAttribution:
            String(localized: "Source or Attribution")
        case .conceptOrInterpretation:
            String(localized: "Concept or Interpretation")
        case .argumentOrObjectionReply:
            String(localized: "Argument or Objection/Reply")
        case .epistemicIdentityOrResearcherState:
            String(localized: "Epistemic Identity or Researcher State")
        case .evidentialScopeOrRestraint:
            String(localized: "Evidential Scope or Restraint")
        case .researchHelpOrNextStep:
            String(localized: "Research Help or Next Step")
        case .other:
            String(localized: "Other")
        }
    }
}

extension ResearchRecordDateFilter {
    fileprivate var interfaceTitle: LocalizedStringResource {
        switch self {
        case .any: "Any Date"
        case .today: "Today"
        case .pastSevenDays: "Past 7 Days"
        case .pastThirtyDays: "Past 30 Days"
        }
    }
}

extension PortableResearchStatementAuthor {
    fileprivate var interfaceTitle: String {
        switch self {
        case .researcher:
            String(localized: "Researcher", table: "Localizable", bundle: .module)
        case .agent:
            String(localized: "Agent", table: "Localizable", bundle: .module)
        }
    }
}

extension PortableResearchRecordKind {
    fileprivate var interfaceTitle: String {
        switch self {
        case .action:
            String(localized: "Action", table: "Localizable", bundle: .module)
        case .discussion:
            String(localized: "Discussion", table: "Localizable", bundle: .module)
        }
    }
}

extension ResearchActionTargetRole {
    fileprivate var interfaceTitle: String {
        switch self {
        case .analysis:
            String(localized: "Analysis", table: "Localizable", bundle: .module)
        case .topic:
            String(localized: "Topic", table: "Localizable", bundle: .module)
        case .work:
            String(localized: "Work", table: "Localizable", bundle: .module)
        }
    }
}

extension PortableResearchDiscrepancy {
    fileprivate func interfaceDescription(
        participants: [PortableResearchNoteRevision]
    ) -> String {
        let title =
            participants.first { $0.noteID == noteID }?.title
            ?? String(localized: "Unknown Note", table: "Localizable", bundle: .module)
        switch kind {
        case .changedButNotReported:
            return String(
                localized: "\(title) changed without an Agent report.",
                table: "Localizable",
                bundle: .module
            )
        case .reportedButUnmodified:
            return String(
                localized: "\(title) was reported as changed without a confirmed revision change.",
                table: "Localizable",
                bundle: .module
            )
        }
    }
}
