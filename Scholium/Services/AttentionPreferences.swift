import ScholiumContracts
import Foundation

/// A read-only presentation projection over the current catalog and dismissal
/// ledger. It owns no queue state: Sidebar consumes the exact current-Scope
/// value while the popover continues to derive its own scoped task list.
struct AttentionScopeCounts: Equatable, Sendable {
    private let values: [WorkspaceVaultSlot: Int]

    init(values: [WorkspaceVaultSlot: Int]) {
        self.values = values
    }

    func count(for slot: WorkspaceVaultSlot) -> Int {
        values[slot, default: 0]
    }
}

enum AttentionPreferences {
    static let dismissalLedgerKey = "attention.dismissalLedger"

    static func normalizedDays(_ value: Int) -> Int {
        min(max(value, 1), 365)
    }

    static func decodeLedger(_ data: Data) -> AttentionDismissalLedger {
        guard !data.isEmpty,
              let ledger = try? JSONDecoder().decode(AttentionDismissalLedger.self, from: data) else {
            return AttentionDismissalLedger()
        }
        return ledger
    }

    static func encodeLedger(_ ledger: AttentionDismissalLedger) -> Data {
        (try? JSONEncoder().encode(ledger)) ?? Data()
    }

    static func visibleScopeCounts(
        catalog: WorkspaceCatalogSnapshot?,
        assignment: TriptychAssignment?,
        dismissalLedgerData: Data
    ) -> AttentionScopeCounts? {
        guard let catalog, let assignment else { return nil }
        let visibleItems = decodeLedger(dismissalLedgerData).visible(catalog.attention)
        let values = Dictionary(uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map { slot in
            let vaultID = assignment.vault(for: slot)?.id
            return (slot, visibleItems.count { $0.note.vaultID == vaultID })
        })
        return AttentionScopeCounts(values: values)
    }
}
