import ScholiumContracts
import SwiftUI

private struct AttentionPopoverContent: View {
    @ObservedObject var session: AttentionPopoverSession

    var body: some View {
        if let presentation = session.presentation {
            AttentionQueueView(
                presentation: presentation,
                session: session
            )
            .frame(
                width: ScholiumMetrics.Attention.popoverWidth,
                height: ScholiumMetrics.Attention.popoverHeight
            )
            .scholiumSurface(.denseEvidence)
        }
    }
}

private struct AttentionPopoverPresenter: ViewModifier {
    let anchor: AttentionPopoverAnchor
    @ObservedObject var session: AttentionPopoverSession

    func body(content: Content) -> some View {
        content.popover(
            isPresented: Binding(
                get: { session.isPresented(from: anchor) },
                set: { isPresented in
                    if !isPresented, session.isPresented(from: anchor) {
                        session.dismiss()
                    }
                }
            ),
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            AttentionPopoverContent(session: session)
        }
    }
}

extension View {
    @ViewBuilder
    func scholiumAttentionPopover(
        anchor: AttentionPopoverAnchor,
        session: AttentionPopoverSession?
    ) -> some View {
        if let session {
            modifier(AttentionPopoverPresenter(anchor: anchor, session: session))
        } else {
            self
        }
    }
}

/// The transient popover projection for one exact Workspace. Derived queue
/// data remains immutable input from the Workspace session; only filter,
/// selection, Note scope, and machine-local dismissal state are mutable here.
struct AttentionQueueView: View {
    @ObservedObject private var presentation: AttentionPresentationState
    @ObservedObject private var session: AttentionPopoverSession
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var dismissalLedgerData = Data()
    @FocusState private var filterFocused: Bool

    init(
        presentation: AttentionPresentationState,
        session: AttentionPopoverSession
    ) {
        _presentation = ObservedObject(wrappedValue: presentation)
        _session = ObservedObject(wrappedValue: session)
    }

    private var scopedItems: [AttentionQueueItem] {
        session.scopedItems(for: presentation)
    }

    private var visibleItems: [AttentionQueueItem] {
        let ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        return presentation.filter.apply(to: ledger.visible(scopedItems))
    }

    private var visibleItemIDs: [String] { visibleItems.map(\.id) }

    private var dismissedCount: Int {
        let ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        return scopedItems.count(where: { ledger.isDismissed($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if !session.catalogIsAvailable, session.isRefreshing {
                loadingState
            } else if !session.catalogIsAvailable, let error = session.catalogError {
                completeErrorState(error)
            } else if visibleItems.isEmpty {
                emptyState
            } else {
                queueList
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .task {
            pruneExpiredDismissals()
            presentation.reconcileVisibleItems(visibleItemIDs)
            if !session.catalogIsAvailable {
                await session.refresh()
            }
        }
        .onChange(of: visibleItemIDs) { _, itemIDs in
            presentation.reconcileVisibleItems(itemIDs)
        }
        .onChange(of: presentation.filterFocusRequestGeneration) { _, _ in
            filterFocused = true
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            Text("Attention")
                .font(ScholiumInterfaceTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    scopeSummary
                    kindPicker
                    refreshButton
                }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    scopeSummary
                    HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                        kindPicker
                        refreshButton
                    }
                }
            }

            TextField("Search Attention", text: filterQuery)
                .textFieldStyle(.roundedBorder)
                .focused($filterFocused)
                .accessibilityIdentifier("scholium.attentionSearch")

            if let status = refreshStatus {
                HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Image(systemName: status.symbol)
                        .foregroundStyle(status.color)
                        .accessibilityHidden(true)
                    Text(status.message)
                        .font(ScholiumInterfaceTypography.metadata)
                        .foregroundStyle(ScholiumColorRole.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if status.offersRetry {
                        Button("Retry") { Task { await session.refresh() } }
                            .disabled(session.isRefreshing)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scholium.attentionRefreshStatus")
            }
        }
        .padding(ScholiumGrid.Spacing.sectionSeparation)
    }

    private var scopeSummary: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
            Text(ScholiumL10n.dynamicString(presentation.workspaceSlot.displayName))
                .font(ScholiumInterfaceTypography.rowTitle)
            Text(presentation.noteScope == nil ? "All Notes" : "This Note")
                .font(ScholiumInterfaceTypography.metadata)
                .foregroundStyle(ScholiumColorRole.secondaryText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var kindPicker: some View {
        Picker("Issue Type", selection: filterKind) {
            Text("All Issues").tag(AttentionQueueKind?.none)
            ForEach(AttentionIssueGroup.allCases) { group in
                Section(ScholiumL10n.dynamicString(group.title)) {
                    ForEach(group.kinds, id: \.self) { kind in
                        Text(ScholiumL10n.dynamicString(kind.displayName)).tag(Optional(kind))
                    }
                }
            }
        }
        .labelsHidden()
        .frame(maxWidth: 190)
        .accessibilityIdentifier("scholium.attentionKindFilter")
    }

    private var refreshButton: some View {
        Button {
            Task { await session.refresh() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
        }
        .help("Refresh Attention")
        .disabled(session.isRefreshing)
        .accessibilityIdentifier("scholium.attentionRefresh")
    }

    private var queueList: some View {
        List(selection: selectedItem) {
            ForEach(AttentionIssueGroup.allCases) { group in
                let items = visibleItems.filter(group.contains)
                if !items.isEmpty {
                    Section(ScholiumL10n.dynamicString(group.title)) {
                        ForEach(items) { item in
                            AttentionQueueRow(
                                item: item,
                                noteTitle: noteTitle(for: item),
                                locator: locatorDescription(for: item),
                                dismissalDays: normalizedDismissalDays,
                                inspect: { inspect(item) },
                                dismiss: { dismiss(item, forDays: $0) },
                                resynthesize: { resynthesize(item) },
                                leaveUnchanged: { leaveUnchanged(item) }
                            )
                            .tag(item.id)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("scholium.attentionList")
    }

    private var loadingState: some View {
        VStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            ProgressView()
                .controlSize(.small)
            Text("Loading Attention…")
                .font(ScholiumInterfaceTypography.rowTitle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scholium.attentionLoading")
    }

    private func completeErrorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could Not Load Attention", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") { Task { await session.refresh() } }
                .disabled(session.isRefreshing)
        }
        .accessibilityIdentifier("scholium.attentionError")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "checkmark.circle")
        } description: {
            Text(emptyDescription)
        } actions: {
            if dismissedCount > 0 {
                Text("\(dismissedCount) dismissed")
                    .font(ScholiumInterfaceTypography.metadata)
            }
        }
        .accessibilityIdentifier("scholium.attentionEmpty")
    }

    private var emptyTitle: String {
        let query = presentation.filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty && presentation.filter.kind == nil
            ? "No Attention Needed"
            : "No Matching Attention"
    }

    private var emptyDescription: String {
        presentation.noteScope == nil
            ? "Scholium found no visible derived issues in this Scope."
            : "Scholium found no visible derived issues for this Note."
    }

    private var selectedItem: Binding<String?> {
        Binding(
            get: { presentation.selectedItemID },
            set: { presentation.select($0) }
        )
    }

    private var filterKind: Binding<AttentionQueueKind?> {
        Binding(
            get: { presentation.filter.kind },
            set: { presentation.filter.kind = $0 }
        )
    }

    private var filterQuery: Binding<String> {
        Binding(
            get: { presentation.filter.query },
            set: { presentation.filter.query = $0 }
        )
    }

    private var normalizedDismissalDays: Int {
        session.dismissalDays
    }

    private func noteTitle(for item: AttentionQueueItem) -> String {
        session.noteTitle(for: item)
    }

    private func locatorDescription(for item: AttentionQueueItem) -> String {
        item.note.relativePath + (item.locator.map { ":\($0.line)" } ?? "")
    }

    private func inspect(_ item: AttentionQueueItem) {
        presentation.select(item.id)
        session.inspect(item)
    }

    private func resynthesize(_ item: AttentionQueueItem) {
        presentation.select(item.id)
        session.resynthesize(item)
    }

    private func dismiss(_ item: AttentionQueueItem, forDays days: Int) {
        presentation.select(item.id)
        var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        ledger.removeExpired()
        ledger.dismiss(item, forDays: days)
        dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
    }

    private func leaveUnchanged(_ item: AttentionQueueItem) {
        presentation.select(item.id)
        var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        ledger.removeExpired()
        ledger.leaveUnchanged(item)
        dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
    }

    private func pruneExpiredDismissals() {
        var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        ledger.removeExpired()
        dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
    }

    private struct RefreshStatus {
        let symbol: String
        let message: String
        let color: Color
        let offersRetry: Bool
    }

    private var refreshStatus: RefreshStatus? {
        if session.isRefreshing, session.catalogIsAvailable {
            return RefreshStatus(
                symbol: "arrow.triangle.2.circlepath",
                message: "Refreshing — showing the last available results.",
                color: ScholiumColorRole.information.color,
                offersRetry: false
            )
        }
        switch session.derivedRefreshStatus {
        case .stale(let issue):
            return RefreshStatus(
                symbol: "clock.badge.exclamationmark",
                message: "Results may be out of date. \(issue.reason)",
                color: ScholiumColorRole.attention.color,
                offersRetry: true
            )
        case .failed(let issue):
            return RefreshStatus(
                symbol: "exclamationmark.triangle",
                message: "Refresh failed. Showing the last available results. \(issue.reason)",
                color: ScholiumColorRole.destructive.color,
                offersRetry: true
            )
        case .current, nil:
            if let error = session.catalogError, session.catalogIsAvailable {
                return RefreshStatus(
                    symbol: "exclamationmark.triangle",
                    message: "Refresh failed. Showing the last available results. \(error)",
                    color: ScholiumColorRole.destructive.color,
                    offersRetry: true
                )
            }
            return nil
        }
    }
}

/// Shared production task row. Preview Catalog reuses this exact row so
/// typography, action wrapping, title truncation, and locator density do not
/// drift from the production Attention popover.
struct AttentionQueueRow: View {
    let item: AttentionQueueItem
    let noteTitle: String
    let locator: String
    let dismissalDays: Int
    let inspect: () -> Void
    let dismiss: (Int) -> Void
    let resynthesize: () -> Void
    let leaveUnchanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(systemName: symbol)
                    .foregroundStyle(severityColor)
                    .frame(width: ScholiumGrid.Dimension.iconTrackWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
                    Text(ScholiumL10n.dynamicString(item.kind.displayName))
                        .font(ScholiumInterfaceTypography.rowTitle)
                    Text(item.message)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
                Text(noteTitle)
                    .font(ScholiumInterfaceTypography.libraryNoteTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(locator)
                    .font(ScholiumInterfaceTypography.metadata.monospaced())
                    .foregroundStyle(ScholiumColorRole.secondaryText.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, ScholiumGrid.Dimension.iconTrackWidth + ScholiumGrid.Spacing.inlineControlGap)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) { actions }
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) { actions }
            }
            .controlSize(.small)
            .padding(.leading, ScholiumGrid.Dimension.iconTrackWidth + ScholiumGrid.Spacing.inlineControlGap)
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.attentionItem.\(item.id)")
    }

    @ViewBuilder
    private var actions: some View {
        Button("Inspect", action: inspect)
        if item.materialChangedSinceUse != nil {
            Button("Resynthesize", action: resynthesize)
            Button("Leave Unchanged", action: leaveUnchanged)
        } else {
            Menu("Dismiss…") {
                ForEach(dismissalDurations, id: \.self) { days in
                    Button(days == 1 ? "For 1 Day" : "For \(days) Days") {
                        dismiss(days)
                    }
                }
            }
        }
    }

    private var dismissalDurations: [Int] {
        Array(Set([1, 7, 30, dismissalDays])).sorted()
    }

    private var severityColor: Color {
        item.severity == .warning
            ? ScholiumColorRole.attention.color
            : ScholiumColorRole.information.color
    }

    private var symbol: String {
        switch item.kind {
        case .possibleOrphan: "circle.dashed"
        case .changedSinceSettled: "clock.arrow.circlepath"
        case .materialChangedSinceUse: "arrow.trianglehead.2.clockwise.rotate.90"
        case .changeAttributionNeeded: "person.crop.circle.badge.questionmark"
        case .malformedMetadata: "exclamationmark.braces"
        case .brokenConnection: "link.badge.plus"
        case .ambiguousConnection: "questionmark.diamond"
        case .unresolvedIdentity: "person.text.rectangle"
        }
    }
}
