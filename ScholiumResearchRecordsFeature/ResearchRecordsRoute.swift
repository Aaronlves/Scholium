import Foundation
import ScholiumContracts

package enum ResearchRecordsViewKind: String, CaseIterable, Codable, Hashable, Sendable {
    case records
    case recommendations
}

package enum ResearchRecordsScope: String, CaseIterable, Hashable, Sendable {
    case thisNote
    case triptych
}

/// Why a Records window was asked to present a destination. A review request
/// may grant transient, window-local direct-undo presentation; ordinary
/// browsing never does.
package enum ResearchRecordsWindowPurpose: Hashable, Sendable {
    case browse
    case reviewResult
    case followUp
}

/// The complete transient destination owned by one Triptych-keyed Research
/// Records window. Portable Records remain the only durable owner.
package enum ResearchRecordsRoute: Equatable, Sendable {
    case collection
    case record(UUID)
    case recommendation(ResearchLiteratureRecommendationOccurrenceID)

    package var recordID: UUID? {
        guard case .record(let id) = self else { return nil }
        return id
    }

    package var recommendationID: ResearchLiteratureRecommendationOccurrenceID? {
        guard case .recommendation(let id) = self else { return nil }
        return id
    }
}

/// A one-shot presentation request for the one Research Records window owned
/// by a Triptych. It carries routing state only, never Record data or authority.
package struct ResearchRecordsWindowRequest: Hashable, Sendable {
    package let triptychID: UUID
    package let noteID: UUID?
    package let initialView: ResearchRecordsViewKind
    package let purpose: ResearchRecordsWindowPurpose
    package let recordID: UUID?
    package let expectedRecordFingerprint: DocumentFingerprint?
    package let expectedFinalizedResultFingerprint: DocumentFingerprint?
    package let statementID: UUID?

    package init(
        triptychID: UUID,
        noteID: UUID? = nil,
        initialView: ResearchRecordsViewKind = .records,
        purpose: ResearchRecordsWindowPurpose = .browse,
        recordID: UUID? = nil,
        expectedRecordFingerprint: DocumentFingerprint? = nil,
        expectedFinalizedResultFingerprint: DocumentFingerprint? = nil,
        statementID: UUID? = nil
    ) {
        self.triptychID = triptychID
        self.noteID = noteID
        self.initialView = initialView
        self.purpose = purpose
        self.recordID = recordID
        self.expectedRecordFingerprint = expectedRecordFingerprint
        self.expectedFinalizedResultFingerprint = expectedFinalizedResultFingerprint
        self.statementID = statementID
    }
}
