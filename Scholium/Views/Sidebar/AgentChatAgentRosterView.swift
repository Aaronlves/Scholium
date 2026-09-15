import ScholiumContracts
import SwiftUI

/// A historical roster enriched by explicitly read metadata, with no execution admission.
struct AgentChatAgentRosterView: View {
    let entries: [AgentChatAgentRoster.Entry]
    let readMetadata: AgentChatAgentRosterObservation.ReadMetadata
    let open: (AgentChatAgentRoster.Entry) -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
    @StateObject private var observation = AgentChatAgentRosterObservation()
    @State private var refreshID = UUID()

    private struct RefreshID: Equatable {
        let entries: [AgentChatAgentRoster.Entry.ObservationID]
        let request: UUID
    }

    private var rows: [AgentChatAgentRosterRow] {
        entries.map { .init(entry: $0, observation: observation.observations[$0.observationID]) }
    }

    enum Item: Identifiable {
        enum ID: Hashable {
            case heading(AgentChatAgentRosterRow.Group)
            case agent(AgentChatAgentRoster.Entry.ObservationID)
        }

        case heading(AgentChatAgentRosterRow.Group, count: Int)
        case agent(AgentChatAgentRosterRow)

        var id: ID {
            switch self {
            case .heading(let group, _): .heading(group)
            case .agent(let row): .agent(row.entry.observationID)
            }
        }
    }

    static func displayItems(rows: [AgentChatAgentRosterRow]) -> [Item] {
        AgentChatAgentRosterRow.Group.allCases.flatMap { group in
            let members = rows.filter { $0.group == group }
            return members.isEmpty ? [] : [.heading(group, count: members.count)] + members.map(Item.agent)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
            HStack {
                Text(ScholiumL10n.string("\(entries.count) agents", locale: locale)).font(.headline)
                Spacer(minLength: 0)
                Button {
                    refreshID = UUID()
                } label: {
                    Label {
                        Text("Refresh", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(observation.isRefreshing || entries.isEmpty)
                .accessibilityIdentifier("scholium.chat.agentRoster.refresh")
                Button(action: close) { Text("Close", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ScholiumGrid.Spacing.inlineControlGap) {
                    // A single stable identity per direct lazy child keeps rows
                    // coherent when a metadata observation moves them between groups.
                    ForEach(Self.displayItems(rows: rows)) { item in
                        switch item {
                        case .heading(let group, let count):
                            HStack {
                                Text(verbatim: group.label(locale: locale))
                                Text(verbatim: String(count)).monospacedDigit()
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isHeader)
                        case .agent(let row): agentRow(row)
                        }
                    }
                    if entries.isEmpty {
                        Text("No Agents Reported", bundle: .module).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: 300)
            .scrollBounceBehavior(.basedOnSize)
            if observation.isRefreshing {
                Text("Loading…", bundle: .module).font(.caption).foregroundStyle(.secondary)
            } else if let date = observation.lastObservedAt {
                HStack {
                    Text("Last Observed", bundle: .module)
                    Text(date, format: .dateTime.hour().minute().second())
                }
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else if !entries.isEmpty {
                Text("Reported Agent States", bundle: .module).font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.body).padding(ScholiumSidebarLayout.textInset).frame(width: 320)
        .tint(nil as Color?)
        .accessibilityIdentifier("scholium.chat.agentRoster")
        .task(id: RefreshID(entries: entries.map(\.observationID), request: refreshID)) {
            await observation.refresh(entries: entries, readMetadata: readMetadata)
        }
        .onDisappear { observation.cancel() }
    }

    private func agentRow(_ row: AgentChatAgentRosterRow) -> some View {
        Button {
            open(row.entry)
        } label: {
            HStack(spacing: ScholiumGrid.Spacing.inlineControlGap) {
                VStack(alignment: .leading, spacing: ScholiumGrid.Spacing.labelAccessoryGap) {
                    Text(verbatim: row.name).lineLimit(2).foregroundStyle(.primary)
                    Text(verbatim: row.status(locale: locale)).font(.caption).foregroundStyle(.secondary)
                    if let retained = row.retainedStatus(locale: locale) {
                        Text(verbatim: retained).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: ScholiumGrid.Dimension.preferredCustomTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(Text(verbatim: row.name))
        .accessibilityLabel(Text(ScholiumL10n.string("Open Agent: \(row.name)", locale: locale)))
        .accessibilityValue([row.status(locale: locale), row.retainedStatus(locale: locale)].compactMap { $0 }.joined(separator: ". "))
        .accessibilityIdentifier("scholium.chat.agentRoster.\(row.entry.id)")
    }
}
