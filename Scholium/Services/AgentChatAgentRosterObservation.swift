import Combine
import Foundation
import ScholiumContracts

/// Transient metadata observations owned by one open roster, never execution state.
@MainActor final class AgentChatAgentRosterObservation: ObservableObject {
    typealias ReadMetadata = @MainActor (AgentChatAgentRoster.Entry) async throws -> AgentChatChildHistory.Metadata

    struct Observation: Equatable {
        var metadata: AgentChatChildHistory.Metadata?
        var observedAt: Date?
        var refreshFailed = false
    }

    @Published private(set) var observations: [AgentChatAgentRoster.Entry.ObservationID: Observation] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastObservedAt: Date?
    private var generation = UUID()

    func refresh(
        entries: [AgentChatAgentRoster.Entry], readMetadata: ReadMetadata,
        now: () -> Date = Date.init
    ) async {
        guard !Task.isCancelled else { return }
        let generation = UUID()
        self.generation = generation
        let identities = Set(entries.map(\.observationID))
        observations = observations.filter { identities.contains($0.key) }
        lastObservedAt = observations.values.compactMap(\.observedAt).max()
        isRefreshing = true
        defer { if self.generation == generation { isRefreshing = false } }

        for entry in entries {
            guard !Task.isCancelled, self.generation == generation else { return }
            do {
                let metadata = try await readMetadata(entry)
                guard !Task.isCancelled, self.generation == generation else { return }
                guard metadata.id == entry.id else { throw AgentChatChildFailure.unverified }
                let date = now()
                observations[entry.observationID] = .init(metadata: metadata, observedAt: date)
                lastObservedAt = date
            } catch {
                guard !Task.isCancelled, self.generation == generation, !(error is CancellationError) else { return }
                var previous = observations[entry.observationID] ?? .init()
                previous.refreshFailed = true
                observations[entry.observationID] = previous
            }
        }
    }

    func cancel() {
        generation = UUID()
        isRefreshing = false
    }
}

/// Keep public historical reports separate from verified metadata observations.
struct AgentChatAgentRosterRow {
    enum Group: CaseIterable, Hashable {
        case active, notRunning, unavailable

        func label(locale: Locale) -> String {
            switch self {
            case .active: ScholiumL10n.string("Active Agents", locale: locale)
            case .notRunning: ScholiumL10n.string("Not Running", locale: locale)
            case .unavailable: ScholiumL10n.string("Unavailable", locale: locale)
            }
        }
    }

    let entry: AgentChatAgentRoster.Entry
    let observation: AgentChatAgentRosterObservation.Observation?

    var name: String {
        guard let name = observation?.metadata?.name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else { return entry.name }
        return name
    }

    var group: Group {
        guard observation?.refreshFailed != true else { return .unavailable }
        if let metadata = observation?.metadata {
            switch metadata.status {
            case .active: return .active
            case .idle: return .notRunning
            case .notLoaded, .systemError: return .unavailable
            }
        }
        switch entry.state {
        case .completed, .interrupted, .shutdown, .errored: return .notRunning
        case .pendingInit, .running, .notFound, nil: return .unavailable
        }
    }

    func status(locale: Locale) -> String {
        if observation?.refreshFailed == true { return ScholiumL10n.string("Refresh Failed", locale: locale) }
        if let metadata = observation?.metadata { return Self.metadataStatus(metadata, locale: locale) }
        return historicalStatus(locale: locale)
    }

    func retainedStatus(locale: Locale) -> String? {
        guard observation?.refreshFailed == true else { return nil }
        if let metadata = observation?.metadata {
            let status = ScholiumL10n.string("Last Observed: \(Self.metadataStatus(metadata, locale: locale))", locale: locale)
            guard let date = observation?.observedAt else { return status }
            return status + " · " + date.formatted(.dateTime.hour().minute().second().locale(locale))
        }
        return entry.state == nil ? nil : historicalStatus(locale: locale)
    }

    private func historicalStatus(locale: Locale) -> String {
        guard let state = entry.state else { return ScholiumL10n.string("State Unavailable", locale: locale) }
        return ScholiumL10n.string("Last Reported: \(state.label(locale: locale))", locale: locale)
    }

    private static func metadataStatus(_ metadata: AgentChatChildHistory.Metadata, locale: Locale) -> String {
        switch metadata.status {
        case .idle: return ScholiumL10n.string("Idle", locale: locale)
        case .notLoaded: return ScholiumL10n.string("Not Loaded", locale: locale)
        case .systemError: return ScholiumL10n.string("Runtime Error", locale: locale)
        case .active:
            var labels: [String] = []
            if metadata.activeFlags.contains("waitingOnApproval") {
                labels.append(ScholiumL10n.string("Waiting for Approval", locale: locale))
            }
            if metadata.activeFlags.contains("waitingOnUserInput") {
                labels.append(ScholiumL10n.string("Input Requested", locale: locale))
            }
            return labels.isEmpty ? ScholiumL10n.string("In Progress", locale: locale) : labels.joined(separator: " · ")
        }
    }
}
