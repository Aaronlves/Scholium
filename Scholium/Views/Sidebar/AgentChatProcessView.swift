import ScholiumContracts
import SwiftUI

/// A disclosure over retained public items; it owns no execution or inferred reasoning.
struct AgentChatProcessView<Row: View>: View {
    let messages: [AgentChatMessage]
    let isActive: Bool
    let forceExpanded: Bool
    var status: AgentChatTurnPresentation? = nil
    var preservesReading = false
    var hasInspectedActivity = false
    var animates = true
    var inspect: () -> Void = {}
    @Binding var userExpansion: Bool?
    @ViewBuilder let row: (AgentChatMessage) -> Row
    @State private var isExpanded = false

    private var needsAttention: Bool {
        messages.contains {
            $0.activity?.status == .uncertain || $0.activity?.status == .interrupted
                || $0.activity?.status == .waitingForApproval
                || $0.activity?.status == .waitingForInput
                || $0.activity?.status == .failed
        }
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
                ForEach(messages) { row($0) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                if let status {
                    AgentChatTurnStatus(presentation: status, animates: animates, isActivityDisclosure: true)
                } else {
                    Text("Process", bundle: .module).font(.callout).foregroundStyle(.secondary)
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scholium.chat.process.\(messages.first?.id ?? "")")
    }
}
