import Foundation
import ScholiumContracts

enum SettlementPresentationState: Hashable, Sendable {
    case settled
    case changedSinceSettlement
    case notYetSettled
    case unavailable
}

struct SettlementPresentation: Hashable, Sendable {
    let state: SettlementPresentationState
    let settledAt: Date?
    let researcher: String?
    let rationale: String?

    static let unavailable = SettlementPresentation(
        state: .unavailable,
        settledAt: nil,
        researcher: nil,
        rationale: nil
    )

    static func resolve(
        noteID: UUID?,
        currentRevision: DocumentFingerprint?,
        requirement: WorkspaceSettlementRequirement?,
        settlements: [SettlementRecord]
    ) -> SettlementPresentation {
        guard let noteID, let currentRevision else { return .unavailable }
        let latest =
            requirement?.previousSettlement
            ?? settlements.filter { $0.noteID == noteID }
            .max { $0.settledAt < $1.settledAt }
        guard let latest else {
            return SettlementPresentation(
                state: .notYetSettled,
                settledAt: nil,
                researcher: nil,
                rationale: nil
            )
        }
        let isCurrent = requirement == nil && latest.fingerprint == currentRevision
        return SettlementPresentation(
            state: isCurrent ? .settled : .changedSinceSettlement,
            settledAt: latest.settledAt,
            researcher: latest.researcher,
            rationale: latest.rationale
        )
    }
}
