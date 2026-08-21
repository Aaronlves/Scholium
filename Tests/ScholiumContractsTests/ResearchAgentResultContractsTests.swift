import Foundation
import ScholiumContracts
import Testing

@Suite("Agent Result, Continue Research, and bounded-write contracts")
struct ResearchAgentResultContractsTests {
    @Test("Action defaults expose the staged academic Result Contract and fixed exclusivity rules")
    func actionResultDefaults() throws {
        let expected: [ResearchActionID: [String]] = [
            .discuss: ["Overall Conclusion", "Open Question"],
            .analyze: [
                "Source Reconstruction", "Coverage", "Reliability",
                "Agent Evaluation", "Further Research",
            ],
            .synthesize: [
                "Synthesis Outcome", "Contribution", "Unresolved Tension",
                "Next Step",
            ],
            .write: [
                "Writing Outcome", "Change Kind", "Remaining Pressure",
                "Evidence Basis",
            ],
            .critique: [
                "Assessment", "Issue Kind", "Significance", "Recommendation",
            ],
            .checkFidelity: [
                "Finding", "Finding Status", "Suggested Correction",
            ],
            .manuscript: [],
        ]
        for profile in ResearchAcademicProfileCatalog.defaultProfiles {
            #expect(
                profile.academicResultFields.map(\.label)
                    == expected[profile.actionID]
            )
        }

        let manuscript = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .manuscript
            }
        )
        let contract = try ResearchResultContract(
            profile: manuscript,
            registrationKey: ResearchSkillRegistrationKey(rawValue: UUID()),
            profileRevision: try manuscript.contentRevision()
        )
        #expect(contract.academicFields.isEmpty)

        let synthesis = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .synthesize
            }
        )
        let invalid = try ResearchAcademicFieldValues(
            rawValues: [
                "synthesis-outcome": .freeText("A bounded synthesis."),
                "contribution": .multipleChoice([
                    "adds", "no-warranted-change",
                ]),
            ],
            definitions: synthesis.academicResultFields
        )
        #expect(throws: ResearchAcademicProfileError.self) {
            try ResearchAcademicProfileCatalog.validatePlatformResultRules(
                invalid,
                actionID: .synthesize
            )
        }
    }

    @Test("Agent Result submission is strict and its receipt exposes no repository or Session identity")
    func strictResultSubmissionAndMinimalReceipt() throws {
        let submission = try ResearchAgentResultSubmission(
            recordTitle: ResearchRecordTitle("A bounded result"),
            academicResults: ResearchAcademicFieldValues(
                rawValues: [:],
                definitions: []
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(submission)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["record_title"] as? String == "A bounded result")
        #expect(object["schema_version"] as? Int == 2)
        object["session_secret"] = "must-not-be-accepted"
        #expect(throws: ResearchAgentResultContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchAgentResultSubmission.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        let receipt = try ResearchAgentResultReceipt(
            disposition: .completed,
            state: .finalized,
            recordFormed: true,
            message: "The result was finalized."
        )
        let receiptObject = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(receipt))
                as? [String: Any]
        )
        #expect(Set(receiptObject.keys) == [
            "schema_version", "disposition", "state", "record_formed", "message",
        ])
        #expect(receiptObject["schema_version"] as? Int == 3)
        let source = String(decoding: try encoder.encode(receipt), as: UTF8.self)
        for forbidden in [
            "run_id", "record_id", "triptych_id", "fingerprint", "secret",
            "nonce", "capability",
        ] {
            #expect(!source.contains(forbidden))
        }
    }

    @Test("Fidelity attachment receipts and source constraints are strict and nonauthorizing")
    func strictFidelityAttachmentContracts() throws {
        let note = VaultQualifiedNoteID(
            vaultID: UUID(),
            relativePath: "Analysis.md"
        )
        let target = ResearchFunctionTarget(
            noteID: UUID(),
            note: note,
            role: .analysis,
            fingerprint: DocumentFingerprint(content: "# Analysis\n"),
            title: "Analysis"
        )
        let inspection = try ResearchContextRequest(clauses: [
            ResearchContextClause(
                kind: .readNote,
                note: target.note,
                expectedFingerprint: target.fingerprint,
                limit: 1,
                useEligibility: .contextUse
            ),
        ])

        let constraint = try ResearchFidelityRunContract(
            checks: [.content, .citations],
            targets: [target],
            materials: [],
            scope: .whole,
            sourceReference: nil,
            requiredUnavailableChecks: [.citations],
            evidenceLimitation: "No formal source envelope is available.",
            inspectionRequests: [inspection]
        )
        #expect(try JSONDecoder().decode(
            ResearchFidelityRunContract.self,
            from: JSONEncoder().encode(constraint)
        ) == constraint)
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try ResearchFidelityRunContract(
                checks: [.content],
                targets: [target],
                materials: [],
                scope: .whole,
                sourceReference: nil,
                requiredUnavailableChecks: [.citations],
                evidenceLimitation: "The constraint exceeds the declared checks.",
                inspectionRequests: [inspection]
            )
        }
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try ResearchFidelityRunContract(
                checks: [.citations],
                targets: [target],
                materials: [],
                scope: .whole,
                sourceReference: nil,
                requiredUnavailableChecks: [.citations],
                inspectionRequests: [inspection]
            )
        }

        #expect(constraint.checks == [.content, .citations])
    }

    @Test("Stored Run Results accept only canonical SHA-256 fingerprints")
    func strictStoredResultFingerprint() throws {
        let academicResults = try ResearchAcademicFieldValues(
            rawValues: [:],
            definitions: []
        )
        func payload(_ fingerprint: DocumentFingerprint) throws {
            _ = try ResearchRunResultPayload(
                runID: UUID(),
                submissionFingerprint: fingerprint,
                recordTitle: ResearchRecordTitle("Stored result"),
                disposition: .completed,
                academicResults: academicResults,
                contextUseReport: nil,
                fidelityOutcomes: [],
                literatureRecommendations: nil,
                submittedAt: Date(timeIntervalSince1970: 1)
            )
        }

        try payload(DocumentFingerprint(content: "canonical"))
        #expect(throws: ResearchAgentResultContractError.self) {
            try payload(DocumentFingerprint(
                sha256: String(repeating: "A", count: 64),
                byteCount: 1
            ))
        }
        #expect(throws: ResearchAgentResultContractError.self) {
            try payload(DocumentFingerprint(
                sha256: String(repeating: "g", count: 64),
                byteCount: 1
            ))
        }
        #expect(throws: ResearchAgentResultContractError.self) {
            try payload(DocumentFingerprint(
                sha256: String(repeating: "0", count: 64),
                byteCount: -1
            ))
        }
    }

    @Test("Continue Research records are strict and preserve one bounded non-authorizing handoff")
    func strictContinuationRecord() throws {
        let item = try ResearchContinuationHandoffItem(
            content: "The prior source reconstructs the distinction narrowly.",
            epistemicStatus: .agentReconstruction,
            nextUse: "Test the distinction against the next Topic note."
        )
        let request = try ResearchContinuationRequest(
            nextActionID: .synthesize,
            targetRole: .topic,
            targetRelativePath: "Topics/Agency.md",
            academicPurpose: "Determine whether the distinction changes the Topic synthesis.",
            handoff: [item]
        )
        let now = Date(timeIntervalSince1970: 10)
        let record = try ResearchContinuationRequestRecord(
            id: UUID(),
            parentRunID: UUID(),
            triptychID: UUID(),
            request: request,
            requestFingerprint: request.contentFingerprint(),
            policy: .askEveryTime,
            policyRevision: DocumentFingerprint(content: "policy"),
            state: .pending,
            receivedAt: now,
            expiresAt: now.addingTimeInterval(600)
        )
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(
            ResearchContinuationRequestRecord.self,
            from: data
        ) == record)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["inherited_context_cache"] = true
        #expect(throws: ResearchContinuationContractError.self) {
            _ = try JSONDecoder().decode(
                ResearchContinuationRequestRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        let source = String(decoding: data, as: UTF8.self)
        for forbidden in ["prompt", "write_capability", "query_response", "cache"] {
            #expect(!source.contains(forbidden))
        }
    }

    @Test("Bounded write-set stored contracts reject undeclared fields at every authority-bearing layer")
    func strictBoundedWriteContracts() throws {
        let runID = UUID()
        let noteID = UUID()
        let note = VaultQualifiedNoteID(
            vaultID: UUID(),
            relativePath: "Topics/Agency.md"
        )
        let entry = try ResearchBoundedWriteSetEntry(
            handle: ResearchWriteTargetHandle(runID: runID, noteID: noteID),
            noteID: noteID,
            note: note,
            role: .topic,
            title: "Agency",
            allowedOperations: [.modifyMarkdown],
            expectedRevision: DocumentFingerprint(content: "before"),
            authorizationBasis: .initialAction,
            expiresAt: Date(timeIntervalSince1970: 600)
        )
        let writeSet = try ResearchBoundedWriteSet(
            runID: runID,
            triptychID: UUID(),
            entries: [entry]
        )
        let data = try JSONEncoder().encode(writeSet)
        #expect(try JSONDecoder().decode(
            ResearchBoundedWriteSet.self,
            from: data
        ) == writeSet)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["blanket_write"] = true
        #expect(throws: ResearchBoundedWriteSetError.self) {
            _ = try JSONDecoder().decode(
                ResearchBoundedWriteSet.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
        let entries = try #require(object["entries"] as? [[String: Any]])
        var entryObject = try #require(entries.first)
        entryObject["reusable_capability"] = "no"
        #expect(throws: ResearchBoundedWriteSetError.self) {
            _ = try JSONDecoder().decode(
                ResearchBoundedWriteSetEntry.self,
                from: JSONSerialization.data(withJSONObject: entryObject)
            )
        }
    }

    @Test("Public Property inputs use ordinary JSON values and non-Property selectors may omit property_keys")
    func publicPropertyJSONIsStable() throws {
        let input = try JSONDecoder().decode(
            CanonicalPropertyInput.self,
            from: Data(#"{"key":"authors","value":[{"family":"Scanlon","given":"T. M."}]}"#.utf8)
        )
        #expect(input.value == .array([.object([
            "family": .string("Scanlon"),
            "given": .string("T. M."),
        ])]))
        let encoded = try JSONEncoder().encode(input)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object["value"] is [[String: Any]])
        #expect(!String(decoding: encoded, as: UTF8.self).contains("_0"))

        let selector = try JSONDecoder().decode(
            ResearchWriteSetTargetSelector.self,
            from: Data(#"{"role":"topic","relative_path":"Agency.md","operations":["modify_markdown"]}"#.utf8)
        )
        #expect(selector.propertyKeys.isEmpty)
        #expect(selector.operations == [.modifyMarkdown])

        func intentObject(
            operation: String,
            content: String? = nil,
            source: String? = nil,
            properties: [[String: Any]]? = nil
        ) -> [String: Any] {
            var object: [String: Any] = [
                "schema_version": ResearchDocumentWriteIntent.currentSchemaVersion,
                "request_id": UUID().uuidString,
                "role": "topic",
                "relative_path": "Agency.md",
                "operation": operation,
            ]
            if let content { object["content"] = content }
            if let source { object["source"] = source }
            if let properties { object["properties"] = properties }
            return object
        }
        let createIntent = try JSONDecoder().decode(
            ResearchDocumentWriteIntent.self,
            from: JSONSerialization.data(withJSONObject: intentObject(
                operation: "create_note"
            ))
        )
        #expect(createIntent.content.isEmpty)
        #expect(createIntent.properties.isEmpty)
        let propertyIntent = try JSONDecoder().decode(
            ResearchDocumentWriteIntent.self,
            from: JSONSerialization.data(withJSONObject: intentObject(
                operation: "modify_properties",
                properties: [["key": "summary", "value": "Exact"]]
            ))
        )
        #expect(propertyIntent.content.isEmpty)
        #expect(propertyIntent.properties.map(\.key) == ["summary"])
        let completeSource = "\u{FEFF}---\r\ntitle: Exact\r\n---\r\n# Exact\r\n"
        let sourceIntent = try JSONDecoder().decode(
            ResearchDocumentWriteIntent.self,
            from: JSONSerialization.data(withJSONObject: intentObject(
                operation: "modify_source",
                source: completeSource
            ))
        )
        #expect(sourceIntent.source == completeSource)
        #expect(sourceIntent.content.isEmpty)
        #expect(sourceIntent.properties.isEmpty)
        #expect(throws: ResearchBoundedWriteSetError.self) {
            _ = try JSONDecoder().decode(
                ResearchDocumentWriteIntent.self,
                from: JSONSerialization.data(withJSONObject: intentObject(
                    operation: "modify_source"
                ))
            )
        }
        #expect(throws: ResearchBoundedWriteSetError.self) {
            _ = try JSONDecoder().decode(
                ResearchDocumentWriteIntent.self,
                from: JSONSerialization.data(withJSONObject: intentObject(
                    operation: "modify_markdown"
                ))
            )
        }
        #expect(try JSONDecoder().decode(
            ResearchDocumentWriteIntent.self,
            from: JSONSerialization.data(withJSONObject: intentObject(
                operation: "modify_markdown",
                content: ""
            ))
        ).content.isEmpty)

        let manuscript = try #require(
            PlatformActionCatalog.definition(for: .manuscript)
        )
        #expect(manuscript.extensionWriteOperations.isEmpty)
        #expect(!manuscript.operations.contains(.modifyInitialNote))
        #expect(!manuscript.operations.contains(.extendWriteSet))
    }
}
