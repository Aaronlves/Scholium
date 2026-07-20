import Foundation
import ScholiumContracts
import Testing

@Suite("Research Function Skill binding contracts")
struct ResearchFunctionSkillBindingContractsTests {
    @Test("A Settings selection round-trips without adding interface presentation data")
    func selectionRoundTrip() throws {
        let selection = ResearchFunctionSkillSelection(
            function: .revise,
            supplementalPackageIDs: ["prose-method", "prose-method"],
            selectedPractices: [
                ResearchPracticeSelection(
                    packageID: "my-practices",
                    practiceID: "philosophical-expositor"
                ),
                ResearchPracticeSelection(
                    packageID: "my-practices",
                    practiceID: "philosophical-expositor"
                ),
            ]
        )
        #expect(selection.supplementalPackageIDs == ["prose-method"])
        #expect(selection.selectedPractices.map(\.selectionID) == [
            "my-practices:philosophical-expositor"
        ])

        let data = try JSONEncoder().encode(selection)
        #expect(try JSONDecoder().decode(
            ResearchFunctionSkillSelection.self,
            from: data
        ) == selection)
    }

    @Test("Status presents friendly candidate metadata while retaining opaque selection IDs")
    func settingsStatusMetadata() {
        let candidate = ResearchFunctionSkillCandidate(
            packageID: "my-prose-method",
            name: "My Prose Method",
            description: "Preserve philosophical commitments while improving expression.",
            version: "local",
            supportedFunctions: [.revise],
            availableRoles: [.supplemental]
        )
        let selection = ResearchFunctionSkillSelection(
            function: .revise,
            supplementalPackageIDs: [candidate.packageID]
        )
        let status = ResearchFunctionSkillBindingStatus(
            function: .revise,
            candidates: [candidate],
            selection: selection,
            bindingRevision: DocumentFingerprint(content: "binding"),
            issue: nil
        )

        #expect(status.candidates.first?.name == "My Prose Method")
        #expect(status.selection.supplementalPackageIDs == ["my-prose-method"])
        #expect(status.issue == nil)
    }

    @Test("Maintenance recovery preserves expected state, undo metadata, and partial listing issues")
    func maintenanceRecoveryRoundTrip() throws {
        let packageRevision = DocumentFingerprint(content: "restored")
        let displacedRevision = DocumentFingerprint(content: "displaced")
        let sourceSnapshot = ResearchSkillMaintenanceSnapshot(
            id: UUID(),
            packageID: "researcher-method",
            packageRevision: packageRevision,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let undoSnapshot = ResearchSkillMaintenanceSnapshot(
            id: UUID(),
            packageID: "researcher-method",
            packageRevision: displacedRevision,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let listing = ResearchSkillMaintenanceSnapshotListing(
            snapshots: [sourceSnapshot, undoSnapshot],
            issues: [ResearchSkillMaintenanceSnapshotIssue(
                entryName: UUID().uuidString,
                snapshotID: UUID(),
                code: .invalidPackage,
                summary: "A linked package was rejected."
            )]
        )
        let outcome = ResearchSkillMaintenanceRestoreOutcome(
            packageID: "researcher-method",
            replacedPackageRevision: displacedRevision,
            restoredPackageRevision: packageRevision,
            snapshotID: sourceSnapshot.id,
            undoSnapshot: undoSnapshot,
            restoredAt: Date(timeIntervalSince1970: 300)
        )

        for value in [
            try JSONEncoder().encode(ResearchSkillMaintenanceExpectedCurrentState.present(
                displacedRevision
            )),
            try JSONEncoder().encode(ResearchSkillMaintenanceExpectedCurrentState.missing),
        ] {
            _ = try JSONDecoder().decode(
                ResearchSkillMaintenanceExpectedCurrentState.self,
                from: value
            )
        }
        let listingData = try JSONEncoder().encode(listing)
        #expect(try JSONDecoder().decode(
            ResearchSkillMaintenanceSnapshotListing.self,
            from: listingData
        ) == listing)
        let outcomeData = try JSONEncoder().encode(outcome)
        #expect(try JSONDecoder().decode(
            ResearchSkillMaintenanceRestoreOutcome.self,
            from: outcomeData
        ) == outcome)
    }
}
