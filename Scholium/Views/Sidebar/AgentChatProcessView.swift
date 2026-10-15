import ScholiumContracts
import SwiftUI

/// A bounded tail while following latest; a stable first identity while reading
/// history. The conversation's reading session owns both paging and continuity.
struct AgentChatProcessWindow: Equatable {
    static let pageSize = 32
    private(set) var first: String?
    private var hasLoadedEarlier = false

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
        // Reaching the bottom during ordinary scrolling is not a request to
        // discard an explicitly loaded activity page and shrink the transcript.
        let start = preservesReading || hasLoadedEarlier ? startIndex(in: messages) : max(0, messages.count - Self.pageSize)
        first = messages[start].id
    }

    mutating func earlier(in messages: [AgentChatMessage]) {
        guard !messages.isEmpty else { return }
        hasLoadedEarlier = true
        first = messages[max(0, startIndex(in: messages) - Self.pageSize)].id
    }

    private func startIndex(in messages: [AgentChatMessage]) -> Int {
        first.flatMap { first in messages.firstIndex { $0.id == first } }
            ?? max(0, messages.count - Self.pageSize)
    }
}

/// Segment before paging so a growing or partially mounted tool run retains its
/// first identity. Commentary and plans keep their original order and boundaries.
struct AgentChatProcessSegment: Identifiable {
    let messages: [AgentChatMessage]
    var id: String { (messages[0].activity == nil ? "message:" : "tools:") + messages[0].id }
    var groupsActivities: Bool { messages[0].activity != nil }

    static func project(_ messages: [AgentChatMessage]) -> [Self] {
        var result: [Self] = []
        var activities: [AgentChatMessage] = []
        for message in messages {
            if message.activity != nil {
                activities.append(message)
            } else {
                if !activities.isEmpty {
                    result.append(.init(messages: activities))
                    activities = []
                }
                result.append(.init(messages: [message]))
            }
        }
        if !activities.isEmpty { result.append(.init(messages: activities)) }
        return result
    }
}

/// A disclosure over retained public items; it owns no execution or inferred reasoning.
struct AgentChatProcessView<Row: View>: View {
    let messages: [AgentChatMessage]
    @Binding var window: AgentChatProcessWindow
    let forceExpanded: Bool
    var isActive = false
    var status: AgentChatTurnPresentation? = nil
    var preservesReading = false
    var hasInspectedActivity = false
    var inspectedActivityIDs: Set<String> = []
    var revealedActivityID: String? = nil
    var animates = true
    var inspect: () -> Void = {}
    @Binding var userExpansion: Bool?
    @Binding var toolGroupExpansions: [String: Bool]
    @ViewBuilder let row: (AgentChatMessage) -> Row
    @Environment(\.locale) private var locale

    // Keep live public commentary readable; only an uninspected, ended process
    // folds automatically. Live updates never replace an explicit choice.
    private var isExpanded: Bool {
        let inspectedTools =
            !toolGroupExpansions.isEmpty
            && AgentChatProcessSegment.project(messages).contains { toolGroupExpansions[$0.id] == true }
        return forceExpanded || (userExpansion ?? (isActive || hasInspectedActivity || inspectedTools))
    }

    private var visibleSegments: [(segment: AgentChatProcessSegment, messages: [AgentChatMessage])] {
        var visibleIDs = Set(window.indices(messages: messages, inspectedIDs: inspectedActivityIDs).map { messages[$0].id })
        let segments = AgentChatProcessSegment.project(messages)
        // A long tool run must not page away the public progress that explains
        // it. Retain that one preceding item without mounting older tool rows.
        for index in segments.indices where index > 0 && segments[index].messages[0].activity != nil {
            if segments[index].messages.contains(where: { visibleIDs.contains($0.id) }) {
                visibleIDs.insert(segments[index - 1].messages[0].id)
            }
        }
        return segments.compactMap { segment in
            let visible = segment.messages.filter { visibleIDs.contains($0.id) }
            return visible.isEmpty ? nil : (segment, visible)
        }
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
                ForEach(visibleSegments, id: \.segment.id) { entry in
                    if entry.segment.groupsActivities {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: {
                                    entry.segment.messages.contains { $0.id == revealedActivityID }
                                        || (toolGroupExpansions[entry.segment.id]
                                            ?? entry.segment.messages.contains { inspectedActivityIDs.contains($0.id) })
                                },
                                set: { expanded in
                                    inspect()
                                    toolGroupExpansions[entry.segment.id] = expanded
                                })
                        ) {
                            ForEach(entry.messages) { row($0) }
                        } label: {
                            VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                                Text("Tool Calls (\(entry.segment.messages.count))", bundle: .module).font(.callout)
                                AgentChatActivityIssues(messages: entry.segment.messages)
                            }
                        }
                        .disclosureGroupStyle(AgentChatDisclosureStyle(animates: animates))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("scholium.chat.process.\(entry.segment.id)")
                    } else {
                        ForEach(entry.messages) { row($0) }
                    }
                }
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
