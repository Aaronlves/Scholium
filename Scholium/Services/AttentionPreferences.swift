import Foundation
import ScholiumCore

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
}
