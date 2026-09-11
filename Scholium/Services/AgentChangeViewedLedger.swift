import Foundation
import ScholiumContracts

/// Machine-local reading preference, separate from mutation evidence and Settlement.
struct AgentChangeViewedLedger: Codable {
    static let key = "scholium.agentChanges.viewedReceipts"
    var ids: Set<UUID> = []

    init(data: Data) { self = (try? JSONDecoder().decode(Self.self, from: data)) ?? Self() }
    init() {}
    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    mutating func setViewed(_ viewed: Bool, id: UUID) {
        if viewed { ids.insert(id) } else { ids.remove(id) }
    }
    func pending(_ changes: [AgentChange], receiptIDs: Set<UUID>) -> [AgentChange] {
        changes.filter { receiptIDs.contains($0.id) && $0.state == .confirmed && !ids.contains($0.id) }
            .sorted { ($0.confirmedAt ?? $0.createdAt) > ($1.confirmedAt ?? $1.createdAt) }
    }
}
