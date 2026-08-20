import Foundation
import ScholiumContracts
import Testing

@Suite("Workspace Skill discovery contracts")
struct WorkspaceSkillDiscoveryContractsTests {
    @Test("Manifest round-trips only bounded absolute Skill sources")
    func roundTrip() throws {
        let manifest = try WorkspaceSkillSourceManifest(
            triptychID: UUID(),
            triptychName: "Value Theory",
            workspaceRoot: "/Research/Value Theory",
            skills: [
                try WorkspaceSkillSource(
                    name: "scholium-write",
                    sourceDirectory: "/Research/Value Theory/.scholium/skill-folders/write",
                    ownership: .researcherOwned,
                    actionID: .write
                ),
                try WorkspaceSkillSource(
                    name: "scholium-core-protocol",
                    sourceDirectory: "/Users/researcher/.local/bin/ScholiumCore/skills/core",
                    ownership: .scholiumManaged
                ),
            ]
        )

        let data = try JSONEncoder().encode(manifest)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["schema_version"] as? Int == 1)
        #expect(object["workspace_root"] as? String == "/Research/Value Theory")
        #expect(try JSONDecoder().decode(
            WorkspaceSkillSourceManifest.self,
            from: data
        ) == manifest)
        #expect(manifest.skills.first?.name == "scholium-core-protocol")
    }

    @Test("Unsafe names, relative sources, and mismatched ownership are rejected")
    func rejectsUnsafeSources() {
        #expect(throws: WorkspaceSkillDiscoveryContractError.self) {
            _ = try WorkspaceSkillSource(
                name: "../write",
                sourceDirectory: "/Research/write",
                ownership: .researcherOwned,
                actionID: .write
            )
        }
        #expect(throws: WorkspaceSkillDiscoveryContractError.self) {
            _ = try WorkspaceSkillSource(
                name: "scholium-write",
                sourceDirectory: ".scholium/write",
                ownership: .researcherOwned,
                actionID: .write
            )
        }
        #expect(throws: WorkspaceSkillDiscoveryContractError.self) {
            _ = try WorkspaceSkillSource(
                name: "scholium-core-protocol",
                sourceDirectory: "/Resources/core",
                ownership: .scholiumManaged,
                actionID: .write
            )
        }
        let unsupported = Data("""
        {
          "schema_version": 2,
          "triptych_id": "00000000-0000-0000-0000-000000000001",
          "triptych_name": "Discovery",
          "workspace_root": "/Research/Discovery",
          "skills": []
        }
        """.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                WorkspaceSkillSourceManifest.self,
                from: unsupported
            )
        }
    }
}
