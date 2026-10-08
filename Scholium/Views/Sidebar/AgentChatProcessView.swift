import ScholiumContracts
import SwiftUI

/// A bounded tail while following latest; a stable first identity while reading
/// history. The conversation's reading session owns both paging and continuity.
struct AgentChatProcessWindow: Equatable {
    static let pageSize = 32
    private(set) var first: String?

    func indices(messages: [AgentChatMessage], inspectedIDs: Set<String>) -> [Int] {
        let start = startIndex(in: messages)
        let inspected = Set(
            messages.indices.filter { inspectedIDs.contains(messages[$0].id) })
        return messages.indices.filter { $0 >= start || inspected.contains($0) }
    }

    func hasEarlier(messages: [AgentChatMessage]) -> Bool {
        startIndex(in: messages) > 0
    }

    mutating func reconcile(in messages: [AgentChatMessage], preservesReading: Bool) {
        guard !messages.isEmpty else { return }
        let start = preservesReading ? startIndex(in: messages) : max(0, messages.count - Self.pageSize)
        first = messages[start].id
    }

    mutating func earlier(in messages: [AgentChatMessage]) {
        guard !messages.isEmpty else { return }
        first = messages[max(0, startIndex(in: messages) - Self.pageSize)].id
    }

    private func startIndex(in messages: [AgentChatMessage]) -> Int {
        first.flatMap { first in messages.firstIndex { $0.id == first } }
            ?? max(0, messages.count - Self.pageSize)
    }
}

/// A disclosure over retained public items; it owns no execution or inferred reasoning.
struct AgentChatProcessView<Row: View>: View {
    let messages: [AgentChatMessage]
    @Binding var window: AgentChatProcessWindow
    let isActive: Bool
    let forceExpanded: Bool
    var status: AgentChatTurnPresentation? = nil
    var preservesReading = false
    var hasInspectedActivity = false
    var inspectedActivityIDs: Set<String> = []
    var animates = true
    var inspect: () -> Void = {}
    @Binding var userExpansion: Bool?
    @ViewBuilder let row: (AgentChatMessage) -> Row
    @Environment(\.locale) private var locale
    @State private var isExpanded = false

    private var needsAttention: Bool {
        messages.contains {
            $0.activity?.status == .uncertain || $0.activity?.status == .interrupted
                || $0.activity?.status == .waitingForApproval
                || $0.activity?.status == .waitingForInput
                || $0.activity?.status == .failed
        }
    }

    private var visibleMessages: [AgentChatMessage] {
        window.indices(messages: messages, inspectedIDs: inspectedActivityIDs).map { messages[$0] }
    }

    private var hasEarlierMessages: Bool {
        window.hasEarlier(messages: messages)
    }

    private var processTitle: String {
        if let activity = messages.reversed().compactMap(\.activity).first {
            return AgentChatActivityProjection.title(activity, locale: locale)
        }
        if messages.contains(where: { $0.plan != nil }) {
            return ScholiumL10n.string("Plan", locale: locale)
        }
        return ScholiumL10n.string("Activity", locale: locale)
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { isExpanded },
                set: { expanded in
                    inspect()
                    userExpansion = expanded
                    isExpanded = expanded
                })
        ) {
            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                if hasEarlierMessages {
                    Button {
                        inspect()
                        window.earlier(in: messages)
                    } label: {
                        Label("Load Earlier Activity", systemImage: ScholiumSidebarAction.earlier.symbol)
                    }
                    .buttonStyle(ScholiumContentActionButtonStyle())
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget)
                    .accessibilityIdentifier("scholium.chat.process.earlier.\(messages.first?.id ?? "")")
                }
                ForEach(visibleMessages) { row($0) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let status {
                    AgentChatTurnStatus(
                        presentation: status, isVisible: animates)
                } else {
                    Text(verbatim: processTitle).font(.callout).foregroundStyle(.secondary)
                }
                AgentChatActivityIssues(messages: messages)
            }
        }
        .disclosureGroupStyle(AgentChatDisclosureStyle(animates: animates))
        .onChange(of: isActive, initial: true) { _, active in
            if needsAttention || forceExpanded {
                isExpanded = true
            } else if let userExpansion {
                isExpanded = userExpansion
            } else if active || hasInspectedActivity {
                // Restoring a completed process must also reveal its retained
                // open child details. An explicit parent choice still wins.
                isExpanded = true
            } else if !preservesReading && !hasInspectedActivity && userExpansion != true {
                isExpanded = false
            }
        }
        .onChange(of: forceExpanded) { _, force in if force { isExpanded = true } }
        .onChange(of: needsAttention) { _, needed in if needed { isExpanded = true } }
        .onChange(of: messages.count, initial: true) { _, _ in
            window.reconcile(in: messages, preservesReading: preservesReading)
        }
        .onChange(of: preservesReading) { _, preservesReading in
            window.reconcile(in: messages, preservesReading: preservesReading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.process.\(messages.first?.id ?? "")")
    }
}
