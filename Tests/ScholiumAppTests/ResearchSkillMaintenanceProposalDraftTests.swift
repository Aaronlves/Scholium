import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Researcher Skill external proposal drafting")
struct ResearchSkillMaintenanceProposalDraftTests {
    @Test("Proposal request contains the exact complete current package boundary")
    func proposalRequestHandoff() throws {
        let current = ResearchSkillProposedPackage(files: [
            ResearchSkillMaintenanceFile(
                relativePath: "SKILL.md",
                source: "---\nname: Method\ndescription: Test.\n---\nCurrent."
            ),
            ResearchSkillMaintenanceFile(
                relativePath: "references/method.md",
                source: "Current method reference."
            ),
        ])
        let purpose = "Adapt the method to repeated counterexample work."
        let request = try ResearchSkillMaintenanceProposalDraft.proposalRequest(
            packageID: "local-method",
            currentPackage: current,
            expectedPackageRevision: current.packageRevision,
            purpose: purpose
        )

        #expect(request.contains("local-method"))
        #expect(request.contains(current.packageRevision.sha256))
        #expect(request.contains(purpose))
        #expect(request.contains("SKILL.md"))
        #expect(request.contains("references/method.md"))
        #expect(request.contains("omission means deletion"))
        #expect(request.contains("Return only one complete ResearchSkillProposedPackage JSON object"))
    }

    @Test("Returned JSON imports a complete package and compares every file")
    func proposalImportAndComparison() throws {
        let returnedData = try JSONSerialization.data(withJSONObject: [
            "files": [
                [
                    "relativePath": "SKILL.md",
                    "source": "---\nname: Method\ndescription: Test.\n---\nProposed.",
                ],
                [
                    "relativePath": "references/kept.md",
                    "source": "Unchanged reference.",
                ],
                [
                    "relativePath": "evals/adversarial.md",
                    "source": "New adversarial case.",
                ],
            ],
        ], options: [.sortedKeys])
        let returnedJSON = String(decoding: returnedData, as: UTF8.self)
        let proposed = try ResearchSkillMaintenanceProposalDraft.decode(returnedJSON)
        let current = ResearchSkillProposedPackage(files: [
            ResearchSkillMaintenanceFile(
                relativePath: "SKILL.md",
                source: "---\nname: Method\ndescription: Test.\n---\nCurrent."
            ),
            ResearchSkillMaintenanceFile(
                relativePath: "references/kept.md",
                source: "Unchanged reference."
            ),
            ResearchSkillMaintenanceFile(
                relativePath: "templates/retired.md",
                source: "Retired template."
            ),
        ])

        let comparisons = ResearchSkillMaintenanceProposalDraft.comparisons(
            current: current,
            proposed: proposed
        )
        #expect(comparisons.map(\.relativePath) == [
            "SKILL.md",
            "evals/adversarial.md",
            "references/kept.md",
            "templates/retired.md",
        ])
        #expect(comparisons.first { $0.relativePath == "SKILL.md" }?.kind == .modified)
        #expect(comparisons.first { $0.relativePath == "evals/adversarial.md" }?.kind == .added)
        #expect(comparisons.first { $0.relativePath == "references/kept.md" }?.kind == .unchanged)
        #expect(comparisons.first { $0.relativePath == "templates/retired.md" }?.kind == .removed)
        let canonicalJSON = try ResearchSkillMaintenanceProposalDraft.encode(proposed)
        #expect(try ResearchSkillMaintenanceProposalDraft.decode(canonicalJSON) == proposed)
    }

    @Test("Proposal request refuses a stale whole-package revision")
    func staleCurrentPackageIsRejected() {
        let current = ResearchSkillProposedPackage(files: [
            ResearchSkillMaintenanceFile(
                relativePath: "SKILL.md",
                source: "---\nname: Method\ndescription: Test.\n---\nCurrent."
            ),
        ])
        #expect(throws: ResearchSkillMaintenanceProposalDraftError.self) {
            _ = try ResearchSkillMaintenanceProposalDraft.proposalRequest(
                packageID: "local-method",
                currentPackage: current,
                expectedPackageRevision: DocumentFingerprint(content: "stale"),
                purpose: "Update the method."
            )
        }
    }
}
