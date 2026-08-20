import Foundation
import ScholiumContracts
import Testing

@Suite("Agent-start creation contracts")
struct ResearchAgentStartContractsTests {
    @Test("New Analysis start is strict, typed, and distinct from an existing target")
    func newAnalysisRoundTrips() throws {
        let target = VaultQualifiedNoteID(
            vaultID: UUID(),
            relativePath: "New/Analysis.md"
        )
        let metadata = try AnalysisCreationMetadata(
            sourceType: .journalArticle,
            properties: [
                try CanonicalPropertyInput(
                    key: "title",
                    value: .string("A bounded article")
                ),
            ]
        )
        let source = try ResearchAgentNewAnalysisSource(
            library: .user,
            itemKey: "AbCd1234"
        )
        let creation = try ResearchAgentNewAnalysisRequest(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            target: target,
            metadata: metadata,
            source: source
        )
        let request = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: creation,
            academicPurpose: "Reconstruct the paper's argument."
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let decoded = try JSONDecoder().decode(
            ResearchAgentStartRequest.self,
            from: data
        )
        #expect(decoded == request)
        #expect(decoded.target == nil)
        #expect(decoded.newAnalysis == creation)
        #expect(decoded.newAnalysis?.source?.itemKey == "ABCD1234")
        #expect(decoded.sourceRoute == nil)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("new_analysis"))
        #expect(json.contains("vault_id"))
        #expect(json.contains("relative_path"))
        #expect(!json.contains("vaultID"))
        #expect(!json.contains("relativePath"))
    }

    @Test("New Analysis can declare a researcher-provided source without a path")
    func researcherProvidedSourceRoundTrips() throws {
        let creation = try ResearchAgentNewAnalysisRequest(
            target: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Researcher/Local Source Analysis.md"
            ),
            metadata: try AnalysisCreationMetadata(sourceType: .book),
            source: nil
        )
        let request = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: creation,
            sourceRoute: .researcherProvided
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(
            ResearchAgentStartRequest.self,
            from: data
        )
        #expect(decoded == request)
        #expect(decoded.newAnalysis?.source == nil)
        #expect(decoded.sourceRoute == .researcherProvided)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("machine_local_path"))
    }

    @Test("Agent start rejects ambiguous target selection and non-Analyze creation")
    func rejectsAmbiguousStart() throws {
        let creation = try ResearchAgentNewAnalysisRequest(
            target: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Analysis.md"
            ),
            metadata: try AnalysisCreationMetadata(sourceType: .journalArticle),
            source: try ResearchAgentNewAnalysisSource(
                library: .user,
                itemKey: "ABCD1234"
            )
        )
        let existing = try ResearchAgentStartRequest(
            actionID: .analyze,
            target: creation.target
        )
        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(existing)
            ) as? [String: Any]
        )
        object["new_analysis"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(creation)
        )
        #expect(throws: ResearchAgentStartContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAgentStartRequest.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        #expect(throws: ResearchAgentStartContractError.self) {
            try ResearchAgentStartRequest(
                actionID: .synthesize,
                newAnalysis: creation
            )
        }
        let withoutRoute = try ResearchAgentNewAnalysisRequest(
            target: creation.target,
            metadata: creation.metadata
        )
        #expect(throws: ResearchAgentStartContractError.self) {
            try ResearchAgentStartRequest(
                actionID: .analyze,
                newAnalysis: withoutRoute
            )
        }

        var camelCaseTarget = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(existing)
            ) as? [String: Any]
        )
        camelCaseTarget["target"] = [
            "vaultID": creation.target.vaultID.uuidString,
            "relativePath": creation.target.relativePath,
        ]
        #expect(throws: ResearchAgentStartContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAgentStartRequest.self,
                from: JSONSerialization.data(withJSONObject: camelCaseTarget)
            )
        }
    }
}
