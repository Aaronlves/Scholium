import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Agent roster metadata observations") @MainActor
struct AgentChatAgentRosterObservationTests {
    private let locale = Locale(identifier: "en")

    @Test(
        "Metadata distinguishes active, idle, unavailable and unloaded Agents",
        arguments: [
            AgentChatChildHistory.Metadata.Status.active, .idle, .notLoaded, .systemError,
        ])
    func metadataStates(_ status: AgentChatChildHistory.Metadata.Status) async throws {
        let entry = entry(state: .completed)
        let owner = AgentChatAgentRosterObservation()
        let observedAt = Date(timeIntervalSince1970: 100)
        await owner.refresh(entries: [entry], readMetadata: { _ in metadata(status: status) }, now: { observedAt })
        let observation = try #require(owner.observations[entry.observationID])
        let row = AgentChatAgentRosterRow(entry: entry, observation: observation)
        #expect(row.name == "Research reviewer")
        #expect(owner.lastObservedAt == observedAt && observation.observedAt == observedAt && !owner.isRefreshing)
        switch status {
        case .active:
            #expect(row.group == .active && row.status(locale: locale) == "In Progress")
        case .idle:
            #expect(row.group == .notRunning && row.status(locale: locale) == "Idle")
        case .notLoaded:
            #expect(row.group == .unavailable && row.status(locale: locale) == "Not Loaded")
        case .systemError:
            #expect(row.group == .unavailable && row.status(locale: locale) == "Runtime Error")
        }
        #expect(row.entry == entry && row.retainedStatus(locale: locale) == nil)
    }

    @Test("Active waiting flags remain visible without inventing a completed outcome")
    func waitingFlags() {
        let row = AgentChatAgentRosterRow(
            entry: entry(state: .completed),
            observation: .init(metadata: metadata(status: .active, flags: ["waitingOnApproval", "waitingOnUserInput"])))
        #expect(row.group == .active)
        #expect(row.status(locale: locale) == "Waiting for Approval · Input Requested")
    }

    @Test("Historical ended work stays counted, while old running reports never claim current activity")
    func historicalStates() {
        let ended = AgentChatAgentRosterRow(entry: entry(state: .completed), observation: nil)
        #expect(ended.group == .notRunning && ended.status(locale: locale) == "Last Reported: Completed")
        let active = AgentChatAgentRosterRow(entry: entry(state: .running), observation: nil)
        #expect(active.group == .unavailable && active.status(locale: locale) == "Last Reported: In Progress")
        let unknown = AgentChatAgentRosterRow(entry: entry(state: nil), observation: nil)
        #expect(unknown.group == .unavailable && unknown.status(locale: locale) == "State Unavailable")
    }

    @Test("Failed refresh keeps the observed name, status and original time but marks them as prior observations")
    func failedRefresh() async throws {
        let entry = entry(state: .completed)
        let owner = AgentChatAgentRosterObservation()
        let observedAt = Date(timeIntervalSince1970: 100)
        await owner.refresh(entries: [entry], readMetadata: { _ in metadata(status: .active) }, now: { observedAt })
        await owner.refresh(entries: [entry], readMetadata: { _ in throw Failure.unavailable }, now: { Date(timeIntervalSince1970: 200) })
        let observation = try #require(owner.observations[entry.observationID])
        let row = AgentChatAgentRosterRow(entry: entry, observation: observation)
        #expect(row.group == .unavailable && row.name == "Research reviewer")
        #expect(row.status(locale: locale) == "Refresh Failed")
        #expect(row.retainedStatus(locale: locale)?.hasPrefix("Last Observed: In Progress · ") == true)
        #expect(observation.observedAt == observedAt && owner.lastObservedAt == observedAt)
        #expect(row.entry == entry && !owner.isRefreshing)
        await owner.refresh(entries: [entry], readMetadata: { _ in metadata(status: .idle, name: "Updated reviewer") })
        let recovered = AgentChatAgentRosterRow(entry: entry, observation: owner.observations[entry.observationID])
        #expect(recovered.group == .notRunning && recovered.name == "Updated reviewer")
        #expect(recovered.retainedStatus(locale: locale) == nil)
    }

    @Test("Failed initial reads retain only the historical report and reject mismatched metadata identities")
    func failedInitialRead() async throws {
        let entry = entry(state: .interrupted)
        let owner = AgentChatAgentRosterObservation()
        await owner.refresh(entries: [entry], readMetadata: { _ in metadata(id: "other", status: .active) })
        let observation = try #require(owner.observations[entry.observationID])
        let row = AgentChatAgentRosterRow(entry: entry, observation: observation)
        #expect(observation.metadata == nil && observation.observedAt == nil && owner.lastObservedAt == nil)
        #expect(row.name == entry.name && row.group == .unavailable)
        #expect(row.retainedStatus(locale: locale) == "Last Reported: Interrupted")
    }

    @Test("A blank runtime name falls back to the exact supplied path")
    func blankName() {
        let entry = entry(state: nil)
        let row = AgentChatAgentRosterRow(entry: entry, observation: .init(metadata: metadata(status: .idle, name: " \n ")))
        #expect(row.name == entry.name)
    }

    @Test("A late response from an older roster scope cannot replace a newer observation")
    func supersededRead() async throws {
        let first = entry(state: .running)
        let second = entry(state: .running, sender: "new-parent")
        let owner = AgentChatAgentRosterObservation()
        let started = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<AgentChatChildHistory.Metadata, Never>?
        let oldTask = Task {
            await owner.refresh(
                entries: [first],
                readMetadata: { _ in
                    await withCheckedContinuation { continuation in
                        pending = continuation
                        started.continuation.yield()
                    }
                })
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        await owner.refresh(entries: [second], readMetadata: { _ in metadata(status: .idle, name: "New scope") })
        try #require(pending).resume(returning: metadata(status: .active, name: "Old scope"))
        await oldTask.value
        #expect(owner.observations[first.observationID] == nil)
        #expect(owner.observations[second.observationID]?.metadata?.name == "New scope")
        #expect(owner.observations.count == 1 && !owner.isRefreshing)
        started.continuation.finish()
    }

    @Test("Closing or cancelling the roster discards late reads and does not continue to another Agent", arguments: [true, false])
    func cancelledRead(_ close: Bool) async throws {
        let first = entry(state: .running)
        let second = AgentChatAgentRoster.Entry(
            id: "second-child", name: "Another Agent", state: nil, messageID: "another-report", senderThreadID: "parent")
        let owner = AgentChatAgentRosterObservation()
        let started = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<AgentChatChildHistory.Metadata, Never>?
        var calls = 0
        let task = Task {
            await owner.refresh(
                entries: [first, second],
                readMetadata: { _ in
                    calls += 1
                    return await withCheckedContinuation { continuation in
                        pending = continuation
                        started.continuation.yield()
                    }
                })
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        if close { owner.cancel() } else { task.cancel() }
        try #require(pending).resume(returning: metadata(status: .active))
        await task.value
        #expect(owner.observations.isEmpty && !owner.isRefreshing && owner.lastObservedAt == nil)
        #expect(calls == 1)
        started.continuation.finish()
    }

    private enum Failure: Error { case unavailable }

    private func entry(state: AgentChatDelegation.State?, sender: String = "parent") -> AgentChatAgentRoster.Entry {
        .init(id: "child", name: "/root/reviewer", state: state, messageID: "report", senderThreadID: sender)
    }

    private func metadata(
        id: String = "child", status: AgentChatChildHistory.Metadata.Status,
        name: String = "Research reviewer", flags: [String] = []
    ) -> AgentChatChildHistory.Metadata {
        .init(id: id, parentID: "parent", name: name, role: nil, status: status, activeFlags: flags, isPaginated: true)
    }
}
