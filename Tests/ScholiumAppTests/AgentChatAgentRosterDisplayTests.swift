import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Agent roster display sequence") @MainActor
struct AgentChatAgentRosterDisplayTests {
    @Test("Metadata regrouping retains one stable Agent identity with the newly observed row content")
    func regrouping() throws {
        let activeEntry = AgentChatAgentRoster.Entry(
            id: "a", name: "/root/source-check", state: .running, messageID: "spawn-a", senderThreadID: "parent")
        let endedEntry = AgentChatAgentRoster.Entry(
            id: "b", name: "/root/objections", state: .completed, messageID: "spawn-b", senderThreadID: "parent")
        let historical = AgentChatAgentRosterView.displayItems(rows: [
            .init(entry: activeEntry, observation: nil), .init(entry: endedEntry, observation: nil),
        ])
        #expect(
            historical.map(\.id) == [
                .heading(.notRunning), .agent(endedEntry.observationID),
                .heading(.unavailable), .agent(activeEntry.observationID),
            ])

        let active = AgentChatAgentRosterRow(
            entry: activeEntry,
            observation: .init(
                metadata: .init(
                    id: "a", parentID: "parent", name: "原文核验", role: nil,
                    status: .active, activeFlags: [], isPaginated: true)))
        let observed = AgentChatAgentRosterView.displayItems(rows: [active, .init(entry: endedEntry, observation: nil)])
        #expect(
            observed.map(\.id) == [
                .heading(.active), .agent(activeEntry.observationID),
                .heading(.notRunning), .agent(endedEntry.observationID),
            ])
        #expect(Set(observed.map(\.id)).count == observed.count)
        let moved = try #require(observed.first { $0.id == .agent(activeEntry.observationID) })
        guard case .agent(let row) = moved else {
            Issue.record("The stable Agent identity resolved to a heading")
            return
        }
        #expect(row.name == "原文核验" && row.status(locale: Locale(identifier: "en")) == "In Progress")
        #expect(row.entry == activeEntry)

        let failed = AgentChatAgentRosterRow(
            entry: activeEntry,
            observation: .init(metadata: active.observation?.metadata, refreshFailed: true))
        let refreshed = AgentChatAgentRosterView.displayItems(rows: [failed, .init(entry: endedEntry, observation: nil)])
        #expect(refreshed.map(\.id) == historical.map(\.id))
        let failedItem = try #require(refreshed.first { $0.id == .agent(activeEntry.observationID) })
        guard case .agent(let failedRow) = failedItem else {
            Issue.record("The failed Agent identity resolved to a heading")
            return
        }
        #expect(failedRow.name == "原文核验" && failedRow.status(locale: Locale(identifier: "en")) == "Refresh Failed")
    }
}
