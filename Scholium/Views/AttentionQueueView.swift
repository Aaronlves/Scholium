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

private struct AttentionPopoverContent: View {
    @ObservedObject var session: AttentionPopoverSession

    var body: some View {
        AttentionQueueView(
            presentation: session.presentation,
            session: session
        )
        .frame(
            width: ScholiumMetrics.Attention.popoverWidth,
            height: ScholiumMetrics.Attention.popoverHeight
        )
        .scholiumSurface(.denseEvidence)
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
        let typed = if let kind = presentation.notificationFilter.issueKind {
            visible.filter { $0.kind == kind }
        } else {
            visible
        }
        return AttentionStructuralNotificationSearch.apply(
            to: typed,
            filter: presentation.filter
        )
    }

    private var visibleActivityNotifications: [ResearchActivityNotification] {
        session.visibleActivityNotifications(for: presentation)
    }

    private var visibleSettlementRequirements: [WorkspaceSettlementRequirement] {
        session.visibleSettlementRequirements(
            for: presentation,
            locale: locale
        )
    }

    private var visibleItemIDs: [String] {
        visibleActivityNotifications.map(activityItemID)
            + visibleSettlementRequirements.map(settlementItemID)
            + visibleItems.map(\.id)
    }

    private var dismissedCount: Int {
        let ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        return scopedItems.count(where: { ledger.isDismissed($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()

            if visibleActivityNotifications.isEmpty,
               visibleSettlementRequirements.isEmpty,
               !session.catalogIsAvailable, session.isRefreshing {
                loadingState
            } else if visibleActivityNotifications.isEmpty,
                      visibleSettlementRequirements.isEmpty,
                      !session.catalogIsAvailable, let error = session.catalogError {
                completeErrorState(error)
            } else if visibleItems.isEmpty
                        && visibleActivityNotifications.isEmpty
                        && visibleSettlementRequirements.isEmpty {
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
            Text("Notifications")
                .font(ScholiumTypography.interface(.sectionTitle))
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

            TextField("Search Notifications", text: filterQuery)
                .textFieldStyle(.roundedBorder)
                .focused($filterFocused)
                .accessibilityIdentifier("scholium.attentionSearch")

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
            Text(scopeTitle)
                .font(ScholiumTypography.interface(.rowTitle))
            Text(presentation.noteScope == nil ? "All Notes" : "This Note")
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
                .scholiumForeground(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var scopeTitle: String {
        presentation.workspaceSlot.map {
            ScholiumL10n.dynamicString($0.displayName)
        } ?? ScholiumL10n.dynamicString("Triptych")
    }

    private var kindPicker: some View {
        Picker("Notification Type", selection: notificationFilter) {
            Text("All Notifications").tag(AttentionNotificationFilter.all)
            Text("Action Activities").tag(AttentionNotificationFilter.activities)
            Text("Settlement Reminders").tag(AttentionNotificationFilter.settlements)
            Text("All Issues").tag(AttentionNotificationFilter.issues)
            ForEach(AttentionIssueGroup.allCases) { group in
                Section(ScholiumL10n.dynamicString(group.title)) {
                    ForEach(group.kinds, id: \.self) { kind in
                        Text(kind.localizedDisplayNameResource)
                            .tag(AttentionNotificationFilter.issue(kind))
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
        .help("Refresh Notifications")
        .disabled(session.isRefreshing)
        .accessibilityIdentifier("scholium.attentionRefresh")
    }

    private var queueList: some View {
        List(selection: selectedItem) {
            if !visibleActivityNotifications.isEmpty {
                Section {
                    ForEach(visibleActivityNotifications) { notification in
                        ResearchActivityNotificationRow(
                            notification: notification,
                            openAction: { session.openAction(notification) },
                            endAction: { session.endAction(notification) },
                            reviewResult: {
                                session.reviewResult(notification)
                            },
                            followUp: { session.followUp(notification) },
                            dismiss: {
                                session.dismissActivity(notification)
                            }
                        )
                        .tag(activityItemID(notification))
                    }
                } header: {
                    Text("ACTION ACTIVITIES")
                }
            }
            if !visibleSettlementRequirements.isEmpty {
                Section {
                    ForEach(visibleSettlementRequirements) { requirement in
                        SettlementRequirementNotificationRow(
                            requirement: requirement,
                            reviewChanges: {
                                session.reviewChanges(requirement)
                            }
                        )
                        .tag(settlementItemID(requirement))
                    }
                } header: {
                    Text("Settlement Reminders")
                        .textCase(.uppercase)
                }
            }
            ForEach(AttentionIssueGroup.allCases) { group in
                let items = visibleItems.filter(group.contains)
                if !items.isEmpty {
                    Section {
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
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ScholiumL10n.dynamicString(group.title))
                            Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                            Text(items.count.formatted())
                                .monospacedDigit()
                                .scholiumForeground(.mutedText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("scholium.attentionList")
    }

    private var loadingState: some View {
        ScholiumContentStateView(
            "Loading Notifications…",
            indicator: .progress,
            density: .compact
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scholium.attentionLoading")
    }

    private func completeErrorState(_ message: String) -> some View {
        ScholiumContentStateView(
            "Could Not Load Notifications",
            detail: Text(message),
            indicator: .symbol("exclamationmark.triangle", role: .attention),
            density: .compact
        ) {
            Button("Retry") { Task { await session.refresh() } }
                .disabled(session.isRefreshing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scholium.attentionError")
    }

    private var emptyState: some View {
        ScholiumContentStateView(
            emptyTitle,
            detail: Text(emptyDescription),
            indicator: .symbol("checkmark.circle"),
            density: .compact
        ) {
            if dismissedCount > 0 {
                Text("\(dismissedCount) dismissed")
                    .font(ScholiumTypography.interface(.small, emphasis: .medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("scholium.attentionEmpty")
    }

    private var emptyTitle: LocalizedStringResource {
        let query = presentation.filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty && presentation.notificationFilter == .all
            ? "No Notifications"
            : "No Matching Notifications"
    }

    private var emptyDescription: String {
        AttentionNotificationCopy.emptyDescription(
            noteScoped: presentation.noteScope != nil,
            locale: locale
        )
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
            set: { presentation.filter.query = $0 }
        )
    }

    private var normalizedDismissalDays: Int {
        session.dismissalDays
    }

    private func activityItemID(_ notification: ResearchActivityNotification) -> String {
        "action:\(notification.runID.uuidString.lowercased())"
    }

    private func settlementItemID(
        _ requirement: WorkspaceSettlementRequirement
    ) -> String {
        "settlement:\(requirement.noteID.uuidString.lowercased())"
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
        let colorRole: ScholiumColorRole
        let offersRetry: Bool
    }

    private var refreshStatus: RefreshStatus? {
        if session.isRefreshing, session.catalogIsAvailable {
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

/// Issue-first task row for the Notifications popover. It keeps the short derived
/// condition ahead of Note context while preserving linear actions and source
/// identity without promoting the row into a card.
struct ResearchActivityNotificationRow: View {
    let notification: ResearchActivityNotification
    let openAction: () -> Void
    let endAction: () -> Void
    let reviewResult: () -> Void
    let followUp: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack(alignment: .firstTextBaseline) {
                Label(stateTitle, systemImage: stateSymbol)
                    .font(ScholiumTypography.interface(.rowTitle))
                    .scholiumForeground(stateColor)
                Spacer(minLength: ScholiumGrid.Spacing.inlineControlGap)
                Text(actionTitle)
                    .font(ScholiumTypography.interface(.small, emphasis: .medium))
                    .scholiumForeground(.secondaryText)
            }

            Text(notification.targetTitle.isEmpty
                ? String(localized: "Research Action")
                : notification.targetTitle)
                .font(ScholiumTypography.interface(.body))
                .lineLimit(1)
                .truncationMode(.middle)

            if !notification.affectedNotes.isEmpty {
                DisclosureGroup("Affected Notes (\(notification.affectedNotes.count))") {
                    VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                        ForEach(notification.affectedNotes) { note in
                            Text(verbatim: note.title)
                                .font(ScholiumTypography.interface(.small))
                                .scholiumForeground(.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, ScholiumGrid.Spacing.labelAccessoryGap)
                }
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
            }

            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                Spacer(minLength: 0)
                ResearchActivityNotificationControls(
                    notification: notification,
                    openAction: openAction,
                    endAction: endAction,
                    reviewResult: reviewResult,
                    followUp: followUp,
                    dismiss: dismiss
                )
            }
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "scholium.notification.action.\(notification.runID.uuidString)"
        )
    }

    private var stateTitle: String {
        ResearchActivityNotificationCopy.stateTitle(notification.state)
    }

    private var stateSymbol: String {
        switch notification.state {
        case .waitingForAgent: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .needsAttention: "exclamationmark.triangle"
        case .resultReady: "doc.text.magnifyingglass"
        case .recoveryRequired: "wrench.and.screwdriver"
        }
    }

    private var stateColor: ScholiumColorRole {
        switch notification.state {
        case .needsAttention, .recoveryRequired: .attention
        case .waitingForAgent, .running, .resultReady: .secondaryText
        }
    }

    private var actionTitle: String {
        ResearchActivityNotificationCopy.actionTitle(notification.actionID)
    }
}

/// Persistent Note-level reminder derived from current source, Research
/// Records, and the one Settlement marker. It has no dismissal path: only a
/// successful Settle of the exact current revision removes it.
struct SettlementRequirementNotificationRow: View {
    let requirement: WorkspaceSettlementRequirement
    let reviewChanges: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(
                alignment: .center,
                spacing: ScholiumGrid.Spacing.nestedContentInset
            ) {
                identity
                controls
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            VStack(
                alignment: .leading,
                spacing: ScholiumGrid.Spacing.inlineControlGap
            ) {
                identity
                controls
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "scholium.notification.settlement.\(requirement.noteID.uuidString)"
        )
    }

    private var identity: some View {
        HStack(
            alignment: .center,
            spacing: ScholiumGrid.Spacing.labelAccessoryGap
        ) {
            Image(systemName: "exclamationmark.circle")
                .font(ScholiumTypography.interface(.body))
                .scholiumForeground(.attention)
                .accessibilityHidden(true)
            Text("Current Revision Not Settled")
                .font(ScholiumTypography.interface(.rowTitle))
                .fixedSize(horizontal: true, vertical: false)
            if !requirement.pendingActivities.isEmpty {
                Text("\(requirement.pendingActivities.count) Agent Changes")
                    .font(
                        ScholiumTypography.interface(
                            .small,
                            emphasis: .medium
                        )
                    )
                    .scholiumForeground(.secondaryText)
                    .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
                    .padding(
                        .vertical,
                        ScholiumGrid.Spacing.opticalAlignmentAdjustment
                    )
                    .background(
                        ScholiumColorRole.raisedSurfaceBackground.color,
                        in: Capsule(style: .continuous)
                    )
                    .scholiumBoundary(
                        .subtleBoundary,
                        in: Capsule(style: .continuous)
                    )
            }
            Text("—")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.mutedText)
                .accessibilityHidden(true)
            Text(verbatim: requirement.title)
                .font(ScholiumTypography.interface(.body))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(-1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var controls: some View {
        HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
            if !requirement.pendingActivities.isEmpty {
                Button("Review Changes", action: reviewChanges)
            }
        }
        .controlSize(.small)
    }

    private var accessibilitySummary: String {
        if requirement.pendingActivities.isEmpty {
            return String.localizedStringWithFormat(
                String(localized: "Current Revision Not Settled, %@"),
                requirement.title
            )
        }
        return String.localizedStringWithFormat(
            String(localized: "Current Revision Not Settled, %@, %lld Agent Changes"),
            requirement.title,
            Int64(requirement.pendingActivities.count)
        )
    }
}

struct AttentionQueueRow: View {
    @Environment(\.locale) private var locale

    let item: AttentionQueueItem
    let noteTitle: String
    let locator: String
    let dismissalDays: Int
    let inspect: () -> Void
    let dismiss: (Int) -> Void
    let resynthesize: () -> Void
    let leaveUnchanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            issueSummary

            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.opticalAlignmentAdjustment) {
                Text(noteTitle)
                    .font(ScholiumTypography.interface(.rowTitle))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(locator)
                    .font(ScholiumTypography.exact(.small))
                    .scholiumForeground(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    Spacer(minLength: 0)
                    actions
                }
                VStack(alignment: .trailing, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    actions
                }
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, ScholiumGrid.Spacing.labelAccessoryGap)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.attentionItem.\(item.id)")
    }

    private var issueSummary: some View {
        HStack(alignment: .firstTextBaseline, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
            Text(item.kind.localizedDisplayNameResource)
                .font(ScholiumTypography.interface(.small, emphasis: .medium))
                .scholiumForeground(severityColorRole)
                .padding(.horizontal, ScholiumGrid.Spacing.inlineControlGap)
                .padding(.vertical, ScholiumGrid.Spacing.opticalAlignmentAdjustment)
                .background(
                    ScholiumColorRole.raisedSurfaceBackground.color,
                    in: Capsule(style: .continuous)
                )
                .scholiumBoundary(
                    .subtleBoundary,
                    in: Capsule(style: .continuous)
                )
                .fixedSize(horizontal: true, vertical: false)

            Text("/")
                .font(ScholiumTypography.interface(.small))
                .scholiumForeground(.mutedText)
                .accessibilityHidden(true)

            Text(verbatim: AttentionIssueCopy.message(for: item, locale: locale))
                .font(ScholiumTypography.interface(.compact))
                .scholiumForeground(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button("Inspect", action: inspect)
        if item.synthesisMaterialChanged != nil {
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

    private var severityColorRole: ScholiumColorRole {
        item.severity == .warning
            ? .attention
            : .information
    }
}
