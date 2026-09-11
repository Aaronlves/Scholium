import ScholiumContracts
import SwiftUI

private struct ScholiumAttentionPopoverIsPresentedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var scholiumAttentionPopoverIsPresented: Bool {
        get { self[ScholiumAttentionPopoverIsPresentedKey.self] }
        set { self[ScholiumAttentionPopoverIsPresentedKey.self] = newValue }
    }
}

private struct AttentionPopoverPresenter: ViewModifier {
    let anchor: AttentionPopoverAnchor
    @ObservedObject var session: AttentionPopoverSession

    func body(content: Content) -> some View {
        content
            .environment(
                \.scholiumAttentionPopoverIsPresented,
                session.isPresented(from: anchor)
            )
            .popover(
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
                AttentionQueueView(
                    presentation: session.presentation,
                    session: session
                )
                .scholiumButtonStyle(.automatic)
                .frame(
                    width: ScholiumMetrics.Attention.popoverWidth,
                    height: ScholiumMetrics.Attention.popoverHeight
                )
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
    @Environment(\.locale) private var locale
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
        guard presentation.notificationFilter.showsIssues else { return [] }
        let visible = ledger.visible(scopedItems)
        return AttentionStructuralNotificationSearch.apply(
            to: visible,
            filter: presentation.filter
        )
    }

    private var visibleAgentChanges: [AgentChange] {
        session.visibleAgentChanges(for: presentation, locale: locale)
    }

    private var visibleSettlementRequirements: [WorkspaceSettlementRequirement] {
        session.visibleSettlementRequirements(
            for: presentation,
            locale: locale
        )
    }

    private var visibleItemIDs: [String] {
        visibleAgentChanges.map(agentChangeItemID)
            + visibleSettlementRequirements.map(settlementItemID)
            + visibleItems.map(\.id)
    }

    private var hasVisibleNotifications: Bool {
        !visibleAgentChanges.isEmpty
            || !visibleSettlementRequirements.isEmpty
            || !visibleItems.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if !hasVisibleNotifications, session.isLoadingInitialContent {
                loadingState
            } else if !hasVisibleNotifications,
                let error = completeErrorMessage
            {
                completeErrorState(error)
            } else if !hasVisibleNotifications {
                emptyState
            } else {
                queueList
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            pruneExpiredDismissals()
            presentation.reconcileVisibleItems(visibleItemIDs)
            if session.isLoadingInitialContent {
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
            HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                Text("Notifications")
                    .font(ScholiumTypography.interface(.sectionTitle))
                    .accessibilityAddTraits(.isHeader)
                scopeSummary
                Spacer(minLength: 0)
            }

            ContextSearchField(
                text: filterQuery, prompt: "Search", identifier: "scholium.attentionSearch",
                options: [
                    .init(title: "All Notifications", selected: notificationFilter.wrappedValue == .all) { notificationFilter.wrappedValue = .all },
                    .init(title: "Agent Changes", selected: notificationFilter.wrappedValue == .agentChanges) {
                        notificationFilter.wrappedValue = .agentChanges
                    },
                    .init(title: "Settlement Reminders", selected: notificationFilter.wrappedValue == .settlements) {
                        notificationFilter.wrappedValue = .settlements
                    },
                    .init(title: "All Issues", selected: notificationFilter.wrappedValue == .issues) { notificationFilter.wrappedValue = .issues },
                ]
            )
            .focused($filterFocused)

            if let status = refreshStatus {
                HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Image(systemName: status.symbol)
                        .scholiumForeground(status.colorRole)
                        .accessibilityHidden(true)
                    Text(status.message)
                        .font(ScholiumTypography.interface(.small, emphasis: .medium))
                        .scholiumForeground(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if status.offersRetry {
                        Button {
                            Task { await session.refresh() }
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .labelStyle(.iconOnly)
                        }
                        .scholiumButtonStyle(.borderless)
                        .help("Retry")
                        .disabled(session.isRefreshing)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("scholium.attentionRefreshStatus")
            }
        }
        .padding(.horizontal, ScholiumGrid.Spacing.sectionSeparation)
        .padding(.vertical, ScholiumGrid.Spacing.nestedContentInset)
    }

    @ViewBuilder
    private var scopeSummary: some View {
        if let scopeTitle {
            Text(scopeTitle)
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
                .scholiumForeground(.secondaryText)
        }
    }

    private var scopeTitle: String? {
        if presentation.noteScope != nil {
            return ScholiumL10n.dynamicString("This Note")
        }
        return presentation.workspaceSlot.map {
            ScholiumL10n.dynamicString($0.displayName)
        }
    }

    private var queueList: some View {
        List(selection: selectedItem) {
            if !visibleAgentChanges.isEmpty {
                notificationCategory("Agent Changes")
                ForEach(visibleAgentChanges) { change in
                    AgentChangeNotificationRow(
                        change: change,
                        title: session.noteTitle(for: change),
                        endingRevisionState: session.endingRevisionState(for: change),
                        inspect: { inspect(change) }
                    )
                    .tag(agentChangeItemID(change))
                }
            }
            if !visibleSettlementRequirements.isEmpty {
                notificationCategory("Settlement Reminders")
                ForEach(visibleSettlementRequirements) { requirement in
                    SettlementRequirementNotificationRow(
                        requirement: requirement,
                        inspect: { inspect(requirement) }
                    )
                    .tag(settlementItemID(requirement))
                }
            }
            ForEach(AttentionIssueGroup.allCases) { group in
                let items = visibleItems.filter(group.contains)
                if !items.isEmpty {
                    notificationCategory(group.titleResource)
                    ForEach(items) { item in
                        AttentionQueueRow(
                            item: item,
                            title: session.noteTitle(for: item),
                            locator: locatorDescription(for: item),
                            dismissalDays: normalizedDismissalDays,
                            inspect: { inspect(item) },
                            dismiss: { dismiss(item, forDays: $0) }
                        )
                        .tag(item.id)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("scholium.attentionList")
    }

    private var loadingState: some View {
        ProgressView("Loading Notifications…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("scholium.attentionLoading")
    }

    private func completeErrorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Could Not Load Notifications", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button {
                Task { await session.refresh() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .help("Retry")
            .disabled(session.isRefreshing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scholium.attentionError")
    }

    private var emptyState: some View {
        ContentUnavailableView(emptyTitle, systemImage: "checkmark.circle")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("scholium.attentionEmpty")
    }

    private var emptyTitle: LocalizedStringResource {
        let query = presentation.filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty && presentation.notificationFilter == .all
            ? "No Notifications"
            : "No Matching Notifications"
    }

    private var selectedItem: Binding<String?> {
        Binding(
            get: { presentation.selectedItemID },
            set: { presentation.select($0) }
        )
    }

    private var notificationFilter: Binding<AttentionNotificationFilter> {
        Binding(
            get: { presentation.notificationFilter },
            set: { presentation.notificationFilter = $0 }
        )
    }

    private var filterQuery: Binding<String> {
        Binding(
            get: { presentation.filter.query },
            set: { presentation.filter = AttentionQueueFilter(query: $0) }
        )
    }

    private var normalizedDismissalDays: Int {
        session.dismissalDays
    }

    private func notificationCategory(
        _ title: LocalizedStringResource
    ) -> some View {
        Text(title)
            .font(ScholiumTypography.interface(.small))
            .scholiumForeground(.secondaryText)
            .padding(
                .leading,
                ScholiumGrid.Dimension.iconTrackWidth
                    + ScholiumGrid.Spacing.inlineControlGap
                    + ScholiumGrid.Spacing.labelAccessoryGap
            )
            .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
            .padding(.bottom, ScholiumGrid.Spacing.opticalAlignmentAdjustment)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    private func settlementItemID(
        _ requirement: WorkspaceSettlementRequirement
    ) -> String {
        "settlement:\(requirement.noteID.uuidString.lowercased())"
    }

    private func agentChangeItemID(_ change: AgentChange) -> String {
        "agent-change:\(change.id.uuidString.lowercased())"
    }

    private func locatorDescription(for item: AttentionQueueItem) -> String {
        item.note.relativePath + (item.locator.map { ":\($0.line)" } ?? "")
    }

    private func inspect(_ item: AttentionQueueItem) {
        presentation.select(item.id)
        session.inspect(item)
    }

    private func inspect(_ requirement: WorkspaceSettlementRequirement) {
        presentation.select(settlementItemID(requirement))
        session.inspect(requirement)
    }

    private func inspect(_ change: AgentChange) {
        presentation.select(agentChangeItemID(change))
        session.inspect(change)
    }

    private func dismiss(_ item: AttentionQueueItem, forDays days: Int) {
        presentation.select(item.id)
        var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        ledger.removeExpired()
        ledger.dismiss(item, forDays: days)
        dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
    }

    private func pruneExpiredDismissals() {
        var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        ledger.removeExpired()
        dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
    }

    private var completeErrorMessage: String? {
        let messages = [session.agentChangesError, session.catalogError]
            .compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private struct RefreshStatus {
        let symbol: String
        let message: String
        let colorRole: ScholiumColorRole
        let offersRetry: Bool
    }

    private var refreshStatus: RefreshStatus? {
        if session.isRefreshing, hasVisibleNotifications {
            return RefreshStatus(
                symbol: "arrow.triangle.2.circlepath",
                message: AttentionNotificationCopy.refreshing(locale: locale),
                colorRole: .information,
                offersRetry: false
            )
        }
        switch session.derivedRefreshStatus {
        case .opening:
            return RefreshStatus(
                symbol: "arrow.triangle.2.circlepath",
                message: AttentionNotificationCopy.refreshing(locale: locale),
                colorRole: .information,
                offersRetry: false
            )
        case .stale(let issue):
            return RefreshStatus(
                symbol: "clock.badge.exclamationmark",
                message: AttentionNotificationCopy.stale(
                    reason: issue.reason,
                    locale: locale
                ),
                colorRole: .attention,
                offersRetry: true
            )
        case .failed(let issue):
            return RefreshStatus(
                symbol: "exclamationmark.triangle",
                message: AttentionNotificationCopy.refreshFailed(
                    reason: issue.reason,
                    locale: locale
                ),
                colorRole: .destructive,
                offersRetry: true
            )
        case .current, nil:
            if let error = session.agentChangesError {
                return RefreshStatus(
                    symbol: "exclamationmark.triangle",
                    message: ScholiumL10n.string(
                        "Agent Changes Unavailable",
                        locale: locale
                    ) + ". " + error,
                    colorRole: .destructive,
                    offersRetry: true
                )
            }
            if let error = session.catalogError, session.catalogIsAvailable {
                return RefreshStatus(
                    symbol: "exclamationmark.triangle",
                    message: AttentionNotificationCopy.refreshFailed(
                        reason: error,
                        locale: locale
                    ),
                    colorRole: .destructive,
                    offersRetry: true
                )
            }
            return nil
        }
    }
}

/// Persistent Note-level reminder derived from current source, Research
/// state and the one Settlement marker. It has no dismissal path: only a
/// successful Settle of the exact current revision removes it.
struct SettlementRequirementNotificationRow: View {
    let requirement: WorkspaceSettlementRequirement
    let inspect: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: inspect) {
            HStack(alignment: .center, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(systemName: "exclamationmark.circle")
                    .scholiumForeground(.attention)
                    .frame(width: ScholiumGrid.Dimension.iconTrackWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: requirement.title)
                        .font(ScholiumTypography.interface(.rowTitle))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    Text("Current Revision Not Settled")
                        .font(ScholiumTypography.interface(.small))
                        .scholiumForeground(.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ScholiumQuietRowButtonStyle(
                isFocused: isFocused,
                minimumHeight: ScholiumGrid.Dimension.preferredCustomTarget,
                horizontalInset: ScholiumGrid.Spacing.labelAccessoryGap,
                verticalInset: ScholiumGrid.Spacing.opticalAlignmentAdjustment
            )
        )
        .scholiumActivationFocus($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Open Note")
        .accessibilityIdentifier(
            "scholium.notification.settlement.\(requirement.noteID.uuidString)"
        )
        .listRowSeparator(.hidden)
    }

    private var accessibilitySummary: String {
        String.localizedStringWithFormat(
            String(localized: "Current Revision Not Settled, %@"),
            requirement.title
        ) + ", " + requirement.note.relativePath
    }
}

struct AgentChangeNotificationRow: View {
    @Environment(\.locale) private var locale

    let change: AgentChange
    let title: String
    let endingRevisionState: AgentChangeEndingRevisionState?
    let inspect: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: inspect) {
            HStack(alignment: .center, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Image(
                    systemName: AgentChangePresentation.operationSymbol(
                        for: change.operation
                    )
                )
                .scholiumForeground(.agentAuthorship)
                .frame(width: ScholiumGrid.Dimension.iconTrackWidth)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: title)
                            .font(ScholiumTypography.interface(.rowTitle))
                            .lineLimit(2)
                            .layoutPriority(1)
                        Spacer(minLength: 4)
                        Text(change.confirmedAt ?? change.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                    }
                    Text(
                        verbatim: ScholiumL10n.localized(
                            AgentChangePresentation.operationTitle(for: change.operation), locale: locale
                        ) + " · "
                            + ScholiumL10n.localized(
                                AgentChangePresentation.stateTitle(for: change, endingRevisionState: endingRevisionState), locale: locale
                            )
                    )
                    .font(ScholiumTypography.interface(.small))
                    .scholiumForeground(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(
            ScholiumQuietRowButtonStyle(
                isFocused: isFocused,
                minimumHeight: ScholiumGrid.Dimension.preferredCustomTarget,
                horizontalInset: ScholiumGrid.Spacing.labelAccessoryGap,
                verticalInset: ScholiumGrid.Spacing.opticalAlignmentAdjustment
            )
        )
        .scholiumActivationFocus($isFocused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint("Inspect Agent Change")
        .accessibilityIdentifier(
            "scholium.notification.agentChange.\(change.id.uuidString.lowercased())"
        )
        .listRowSeparator(.hidden)
    }

    private var accessibilitySummary: String {
        let date = (change.confirmedAt ?? change.createdAt).formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(locale)
        )
        return [
            ScholiumL10n.localized(
                AgentChangePresentation.operationTitle(for: change.operation),
                locale: locale
            ),
            title,
            AgentChangePresentation.path(for: change),
            ScholiumL10n.localized(
                AgentChangePresentation.stateTitle(
                    for: change,
                    endingRevisionState: endingRevisionState
                ),
                locale: locale
            ),
            date,
        ].joined(separator: ", ")
    }
}

struct AttentionQueueRow: View {
    @Environment(\.locale) private var locale

    let item: AttentionQueueItem
    let title: String
    let locator: String
    let dismissalDays: Int
    let inspect: () -> Void
    let dismiss: (Int) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Button(action: inspect) {
                HStack(alignment: .center, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Image(
                        systemName: item.severity == .warning
                            ? "exclamationmark.triangle"
                            : "info.circle"
                    )
                    .scholiumForeground(severityColorRole)
                    .frame(width: ScholiumGrid.Dimension.iconTrackWidth)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: title)
                            .font(ScholiumTypography.interface(.rowTitle))
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Text(verbatim: AttentionIssueCopy.message(for: item, locale: locale))
                            .font(ScholiumTypography.interface(.small))
                            .scholiumForeground(.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .scholiumButtonStyle(.plain)
            .scholiumActivationFocus($isFocused)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint("Open Note")
            .accessibilityIdentifier("scholium.attentionOpen.\(item.id)")

            dismissalMenu
        }
        .padding(.horizontal, ScholiumGrid.Spacing.labelAccessoryGap)
        .padding(.vertical, ScholiumGrid.Spacing.opticalAlignmentAdjustment)
        .frame(
            maxWidth: .infinity,
            minHeight: ScholiumGrid.Dimension.preferredCustomTarget
        )
        .contentShape(Rectangle())
        .scholiumContentControlPointerFeedback(
            isFocused: isFocused,
            in: notificationRowShape
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.attentionItem.\(item.id)")
        .listRowSeparator(.hidden)
    }

    private var dismissalMenu: some View {
        Menu {
            ForEach(dismissalDurations, id: \.self) { days in
                Button(days == 1 ? "For 1 Day" : "For \(days) Days") {
                    dismiss(days)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .scholiumForeground(.secondaryText)
                .frame(
                    width: ScholiumGrid.Dimension.preferredCustomTarget,
                    height: ScholiumGrid.Dimension.preferredCustomTarget
                )
                .accessibilityHidden(true)
        }
        .scholiumMenuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Dismiss…")
        .accessibilityLabel("Dismiss…")
        .accessibilityIdentifier("scholium.attentionDismiss.\(item.id)")
    }

    private var notificationRowShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: ScholiumShape.editorialControlCornerRadius,
            style: .continuous
        )
    }

    private var accessibilitySummary: String {
        [
            item.kind.localizedDisplayName(locale: locale),
            title,
            AttentionIssueCopy.message(for: item, locale: locale),
            locator,
        ].joined(separator: ", ")
    }

    private var dismissalDurations: [Int] {
        Array(Set([1, 7, 30, dismissalDays])).sorted()
    }

    private var severityColorRole: ScholiumColorRole {
        item.severity == .warning
            ? .attention
            : .information
    }
}
