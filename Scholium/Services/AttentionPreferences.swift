import ScholiumContracts
import Foundation

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

    /// Returns the exact visible Triptych aggregate. The assignment remains an
    /// availability gate so a window never presents a count before its
    /// configured Triptych is ready.
    static func visibleTotalCount(
        catalog: WorkspaceCatalogSnapshot?,
        assignment: TriptychAssignment?,
        dismissalLedgerData: Data
    ) -> Int? {
        guard let catalog, assignment != nil else { return nil }
        return decodeLedger(dismissalLedgerData).visible(catalog.attention).count
    }
}
