import ScholiumContracts
import SwiftUI

/// A bounded presentation window over a retained process. The runtime history
/// remains complete; only the rows currently needed for browsing are mounted.
struct AgentChatProcessWindow {
    static let pageSize = 32

    static func indices(
        messages: [AgentChatMessage], loadedCount: Int, inspectedIDs: Set<String>
    ) -> [Int] {
        let start = max(0, messages.count - max(Self.pageSize, loadedCount))
        let inspected = Set(
            messages.indices.filter { inspectedIDs.contains(messages[$0].id) })
        return messages.indices.filter { $0 >= start || inspected.contains($0) }
    }

    static func hasEarlier(messages: [AgentChatMessage], loadedCount: Int) -> Bool {
        messages.count > max(Self.pageSize, loadedCount)
    }

    static func nextCount(messages: [AgentChatMessage], loadedCount: Int) -> Int {
        min(messages.count, max(Self.pageSize, loadedCount) + Self.pageSize)
    }
}

/// A disclosure over retained public items; it owns no execution or inferred reasoning.
struct AgentChatProcessView<Row: View>: View {
    let messages: [AgentChatMessage]
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
    @State private var loadedMessageCount = AgentChatProcessWindow.pageSize

    private var needsAttention: Bool {
        messages.contains {
            $0.activity?.status == .uncertain || $0.activity?.status == .interrupted
                || $0.activity?.status == .waitingForApproval
                || $0.activity?.status == .waitingForInput
                || $0.activity?.status == .failed
        }
    }

    private var visibleMessages: [AgentChatMessage] {
        AgentChatProcessWindow.indices(
            messages: messages, loadedCount: loadedMessageCount, inspectedIDs: inspectedActivityIDs
        ).map { messages[$0] }
    }

    private var hasEarlierMessages: Bool {
        AgentChatProcessWindow.hasEarlier(messages: messages, loadedCount: loadedMessageCount)
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
                        loadedMessageCount = AgentChatProcessWindow.nextCount(
                            messages: messages, loadedCount: loadedMessageCount)
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
        .onChange(of: messages.count) { _, count in
            loadedMessageCount = min(max(AgentChatProcessWindow.pageSize, loadedMessageCount), count)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.process.\(messages.first?.id ?? "")")
    }
}
