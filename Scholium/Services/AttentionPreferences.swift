import Foundation
import ScholiumContracts

enum AttentionPreferences {
    static let dismissalLedgerKey = "attention.dismissalLedger"

    static func normalizedDays(_ value: Int) -> Int {
        min(max(value, 1), 365)
    }

    static func ledgerNeedsRecovery(_ data: Data) -> Bool {
        !data.isEmpty && (try? JSONDecoder().decode(AttentionDismissalLedger.self, from: data)) == nil
    }

    static func decodeLedger(_ data: Data) -> AttentionDismissalLedger {
        if let ledger = try? JSONDecoder().decode(AttentionDismissalLedger.self, from: data) { return ledger }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["dismissedUntilByItemID"] as? [String: Any]
        else { return AttentionDismissalLedger() }
        var retained: [String: Date] = [:]
        for (id, value) in entries {
            guard let bytes = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
                let date = try? JSONDecoder().decode(Date.self, from: bytes), date.timeIntervalSinceReferenceDate.isFinite
            else { continue }
            retained[id] = date
        }
        return AttentionDismissalLedger(dismissedUntilByItemID: retained)
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
