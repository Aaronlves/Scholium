import ScholiumContracts
import SwiftUI

/// Window-owned Attention projection. Derived items and refresh status are
/// supplied by the root; opening a result remains a typed Discovery intent.
struct AttentionQueueContext {
    let items: [AttentionQueueItem]
    let errorMessage: String?
    let isRefreshing: Bool
    let dismissalDays: Int
    let refresh: () async -> Void
    let close: () -> Void
}

struct AttentionQueueView: View {
    @ObservedObject private var controller: DiscoveryController
    let context: AttentionQueueContext
    @State private var filter = AttentionQueueFilter()
    @AppStorage(AttentionPreferences.dismissalLedgerKey)
    private var dismissalLedgerData = Data()

    init(controller: DiscoveryController, context: AttentionQueueContext) {
        self.controller = controller
        self.context = context
    }

    private var allItems: [AttentionQueueItem] {
        context.items
    }

    private var visibleItems: [AttentionQueueItem] {
        let ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        return filter.apply(to: ledger.visible(allItems))
    }

    private var dismissedCount: Int {
        let ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        return allItems.filter { ledger.isDismissed($0) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Attention")
                        .font(.title2.weight(.semibold))
                    Text("Derived structural reminders. They never determine evidence, quality, or permission to use a note.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Library") { context.close() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    kindPicker
                    Spacer()
                    refreshControls
                }

                VStack(alignment: .leading, spacing: 8) {
                    kindPicker
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 12) {
                        refreshControls
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if let error = context.errorMessage {
                ContentUnavailableView(
                    "Could Not Refresh Attention",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if visibleItems.isEmpty, !context.isRefreshing {
                ContentUnavailableView(
                    filter.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "No Items in This View"
                        : "No Matching Attention",
                    systemImage: "checkmark.circle",
                    description: Text("Scholium found no matching derived issues. Dismissed items return after \(dismissalDurationText).")
                )
            } else {
                List(visibleItems) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol(item.kind))
                            .foregroundStyle(color(item.severity))
                            .frame(width: 18)
                            .accessibilityHidden(true)

                        Button {
                            open(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.kind.displayName)
                                    .font(.headline)
                                Text(item.message)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(sourceDescription(item))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Open the affected note and exact source line when available")

                        Button(dismissalActionTitle) {
                            dismissAttention(item)
                        }
                        .controlSize(.small)
                        .help("Hide this derived reminder for \(dismissalDurationText)")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .searchable(text: queryBinding, placement: .toolbar, prompt: "Search Attention")
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .task {
            pruneExpiredDismissals()
            await context.refresh()
        }
    }

    private var kindBinding: Binding<AttentionQueueKind?> {
        Binding(get: { filter.kind }, set: { filter.kind = $0 })
    }

    private var kindPicker: some View {
        Picker("Kind", selection: kindBinding) {
            Text("All Attention").tag(AttentionQueueKind?.none)
            ForEach(AttentionQueueKind.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(Optional(kind))
            }
        }
        .frame(maxWidth: 280)
    }

    @ViewBuilder
    private var refreshControls: some View {
        if dismissedCount > 0 {
            Text("\(dismissedCount) dismissed")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Dismissed items return after \(dismissalDurationText).")
        }
        if context.isRefreshing {
            ProgressView("Refreshing Attention")
                .controlSize(.small)
        }
        Button("Refresh") { Task { await context.refresh() } }
            .disabled(context.isRefreshing)
    }

    private var queryBinding: Binding<String> {
        Binding(get: { filter.query }, set: { filter.query = $0 })
    }

    private var normalizedDismissalDays: Int {
        AttentionPreferences.normalizedDays(context.dismissalDays)
    }

    private var dismissalDurationText: String {
        normalizedDismissalDays == 1 ? "1 day" : "\(normalizedDismissalDays) days"
    }

    private var dismissalActionTitle: String {
        normalizedDismissalDays == 1 ? "Dismiss for 1 Day" : "Dismiss for \(normalizedDismissalDays) Days"
    }

    private func sourceDescription(_ item: AttentionQueueItem) -> String {
        "\(item.note.vaultName) — \(item.note.relativePath)"
            + (item.locator.map { " — line \($0.line)" } ?? "")
    }

    private func open(_ item: AttentionQueueItem) {
        controller.requestOpen(item.note, sourceLocator: item.locator)
        context.close()
    }

    private func dismissAttention(_ item: AttentionQueueItem) {
        var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        ledger.removeExpired()
        ledger.dismiss(item, forDays: normalizedDismissalDays)
        dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
    }

    private func pruneExpiredDismissals() {
        var ledger = AttentionPreferences.decodeLedger(dismissalLedgerData)
        ledger.removeExpired()
        dismissalLedgerData = AttentionPreferences.encodeLedger(ledger)
    }

    private func symbol(_ kind: AttentionQueueKind) -> String {
        switch kind {
        case .possibleOrphan: "circle.dashed"
        case .changedSinceReview: "clock.arrow.circlepath"
        case .malformedMetadata: "exclamationmark.braces"
        case .brokenConnection: "link.badge.plus"
        case .ambiguousConnection: "questionmark.diamond"
        case .unqualifiedAnalysisReliance: "exclamationmark.triangle"
        case .unresolvedIdentity: "person.text.rectangle"
        }
    }

    private func color(_ severity: AttentionSeverity) -> Color {
        switch severity {
        case .information: .secondary
        case .warning: .orange
        }
    }
}
