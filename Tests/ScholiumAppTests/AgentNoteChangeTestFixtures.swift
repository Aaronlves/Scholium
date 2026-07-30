import Foundation
import ScholiumContracts

enum AgentNoteChangeTestFixtures {
    static func record(
        triptychID: UUID,
        receivedAt: Date = Date(),
        relativePath: String = "Topics/Attention.md",
        reason: String = "This Topic needs a separately authorized phase."
    ) throws -> AgentNoteChangeRequestRecord {
        let noteID = UUID()
        return try AgentNoteChangeRequestRecord(
            request: AgentNoteChangeRequest(
                triptychID: triptychID,
                parentRunID: UUID(),
                parentAction: try actionRevision(
                    definition: .analyze,
                    packageID: "scholium-analyze"
                ),
                requestedAction: try actionRevision(
                    definition: .synthesize,
                    packageID: "scholium-synthesize"
                ),
                targets: [try AgentNoteChangeTarget(
                    noteID: noteID,
                    note: VaultQualifiedNoteID(
                        vaultID: UUID(),
                        relativePath: relativePath
                    ),
                    role: .topic,
                    expectedFingerprint: fingerprint("topic")
                )],
                operations: [.modifyMarkdown],
                agentReason: reason
            ),
            receivedAt: receivedAt,
            validFor: 120
        )
    }

    private static func actionRevision(
        definition: ResearchActionDefinition,
        packageID: String
    ) throws -> AgentNoteChangeActionRevision {
        try AgentNoteChangeActionRevision(
            definition: definition,
            packageID: packageID,
            skillRevision: fingerprint("skill-\(packageID)"),
            profileOrigin: .applicationDefault,
            profileRevision: fingerprint("profile-\(packageID)"),
            profileDocumentRevision: nil
        )
    }

    private static func fingerprint(_ value: String) -> DocumentFingerprint {
        DocumentFingerprint(data: Data(value.utf8))
    }
}
