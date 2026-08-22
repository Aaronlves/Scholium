import Foundation
import ScholiumContracts
import Testing

@Suite("Agent-start creation contracts")
struct ResearchAgentStartContractsTests {
    @Test("New Analysis start consumes a strict managed-root preflight payload")
    func newAnalysisRoundTrips() throws {
        let metadata = try AnalysisCreationMetadata(
            sourceType: .journalArticle,
            properties: [
                try CanonicalPropertyInput(
                    key: "title",
                    value: .string("A bounded article")
                ),
            ]
        )
        let preflight = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: "A bounded article.md"
            ),
            metadata: metadata,
            source: try ResearchAgentNewAnalysisSource(
                library: .user,
                itemKey: "AbCd1234"
            )
        )
        let creation = ResearchAgentNewAnalysisRequest(
            preflight: preflight,
            settingsRevision: SettingsRevision(
                fingerprint: DocumentFingerprint(content: "settings-v1")
            )
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
        #expect(decoded.newAnalysis?.destination.resolvedRelativePath
            == "A bounded article.md")
        #expect(decoded.sourceRoute == nil)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("new_analysis"))
        #expect(json.contains("managed_default_filename"))
        #expect(json.contains("settings_revision"))
        #expect(!json.contains("vault_id"))
        #expect(!json.contains("relative_path"))
    }

    @Test("Researcher-provided direct creation stays at the managed root")
    func researcherProvidedSourceRoundTrips() throws {
        let preflight = try ResearchAgentAnalysisCreationPreflightRequest(
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: "Local Source Analysis.md"
            ),
            metadata: try AnalysisCreationMetadata(sourceType: .book),
            sourceRoute: .researcherProvided
        )
        let creation = ResearchAgentNewAnalysisRequest(
            preflight: preflight,
            settingsRevision: SettingsRevision(
                fingerprint: DocumentFingerprint(content: "settings-v1")
            )
        )
        let request = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: creation
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(
            ResearchAgentStartRequest.self,
            from: data
        )
        #expect(decoded == request)
        #expect(decoded.newAnalysis?.source == nil)
        #expect(decoded.newAnalysis?.sourceRoute == .researcherProvided)
        #expect(decoded.sourceRoute == nil)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("managed_default_filename"))
        #expect(!json.contains("researcher_selected_relative_path"))
        #expect(!json.contains("machine_local_path"))
    }

    @Test("Creation destination and start reject free classification and ambiguous routes")
    func rejectsAmbiguousStart() throws {
        #expect(throws: ResearchAgentStartContractError.self) {
            _ = try ResearchAgentAnalysisDestination(
                managedDefaultFilename: "Agent/Analysis.md"
            )
        }
        var claimedSelection: [String: Any] = [
            "schema_version": ResearchAgentAnalysisDestination.currentSchemaVersion,
            "managed_default_filename": "Analysis.md",
            "researcher_selected_relative_path": "Agent/Analysis.md",
        ]
        #expect(throws: ResearchAgentStartContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAgentAnalysisDestination.self,
                from: JSONSerialization.data(withJSONObject: claimedSelection)
            )
        }
        claimedSelection.removeValue(forKey: "managed_default_filename")
        #expect(throws: ResearchAgentStartContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAgentAnalysisDestination.self,
                from: JSONSerialization.data(withJSONObject: claimedSelection)
            )
        }
        #expect(throws: ResearchAgentStartContractError.self) {
            _ = try ResearchAgentAnalysisCreationPreflightRequest(
                destination: ResearchAgentAnalysisDestination(
                    managedDefaultFilename: "Analysis.md"
                ),
                metadata: AnalysisCreationMetadata(sourceType: .journalArticle)
            )
        }

        let preflight = try ResearchAgentAnalysisCreationPreflightRequest(
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: "Analysis.md"
            ),
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle),
            source: ResearchAgentNewAnalysisSource(
                library: .user,
                itemKey: "ABCD1234"
            )
        )
        let creation = ResearchAgentNewAnalysisRequest(
            preflight: preflight,
            settingsRevision: SettingsRevision(
                fingerprint: DocumentFingerprint(content: "settings-v1")
            )
        )
        let existingTarget = VaultQualifiedNoteID(
            vaultID: UUID(),
            relativePath: "Analysis.md"
        )
        let existing = try ResearchAgentStartRequest(
            actionID: .analyze,
            target: existingTarget
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
        #expect(throws: ResearchAgentStartContractError.self) {
            try ResearchAgentStartRequest(
                actionID: .analyze,
                newAnalysis: creation,
                sourceRoute: .researcherProvided
            )
        }

        var camelCaseTarget = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(existing)
            ) as? [String: Any]
        )
        camelCaseTarget["target"] = [
            "vaultID": existingTarget.vaultID.uuidString,
            "relativePath": existingTarget.relativePath,
        ]
        #expect(throws: ResearchAgentStartContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAgentStartRequest.self,
                from: JSONSerialization.data(withJSONObject: camelCaseTarget)
            )
        }
    }
}
