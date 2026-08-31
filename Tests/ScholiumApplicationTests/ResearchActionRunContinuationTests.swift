import Foundation
import ScholiumContracts
@testable import ScholiumApplication
import Testing

extension ResearchActionRunOperationsTests {
    func actionNote(
        _ target: ResearchActionNoteSnapshot
    ) -> ResearchActionNoteSnapshot {
        let role: ResearchActionTargetRole = switch target.role {
        case .analysis: .analysis
        case .topic: .topic
        case .work: .work
        }
        return ResearchActionNoteSnapshot(
            noteID: target.noteID,
            note: target.note,
            role: role,
            fingerprint: target.fingerprint,
            title: target.title
        )
    }

    func actionRequest(
        handle: WorkspaceHandle,
        actionID: ResearchActionID,
        target: ResearchActionNoteSnapshot,
        platformInputs: ResearchActionPlatformInputs? = nil,
        academicValues: [ResearchAcademicFieldID: ResearchAcademicFieldValue] = [:]
    ) async throws -> ResearchActionExecutionRequest {
        let availability = try await handle.research.availableActions(for: target)
        let presented = try #require(availability.first { $0.id == actionID })
        return ResearchActionExecutionRequest(
            actionID: actionID,
            expectedProfileRevision: presented.profile.profileRevision,
            expectedProfileDocumentRevision:
                presented.profile.profileDocumentRevision,
            target: target,
            platformInputs: try (platformInputs ?? ResearchActionPlatformInputs()),
            academicInputs: try ResearchAcademicFieldValues(
                values: academicValues,
                definitions: presented.profile.profile.academicInputFields
            )
        )
    }

    static let zoteroItemJSON = #"""
    {
      "key": "META0001",
      "data": {
        "key": "META0001",
        "itemType": "journalArticle",
        "title": "Fittingness",
        "creators": [
          {"creatorType":"author","firstName":"Richard","lastName":"Chappell"},
          {"creatorType":"editor","firstName":"Example","lastName":"Editor"}
        ],
        "date": "2012",
        "language": "en",
        "publicationTitle": "The Philosophical Quarterly",
        "volume": "62",
        "issue": "249",
        "pages": "684-704",
        "DOI": "10.1111/example",
        "ISSN": "0031-8094",
        "citationKey": "ChappellFittingness2012",
        "abstractNote": "A bibliographic abstract.",
        "tags": [{"tag":"fittingness"},{"tag":"value"}],
        "collections": [],
        "dateModified": "2026-07-12T10:30:00Z"
      }
    }
    """#
}
