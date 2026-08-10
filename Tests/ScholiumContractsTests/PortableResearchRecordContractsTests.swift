import Foundation
import ScholiumContracts
import Testing

@Suite("Portable Research Record contracts")
struct PortableResearchRecordContractsTests {
    @Test("A Comment stores only a revision-bound inclusive line range")
    func lineReferenceRoundTrip() throws {
        let fingerprint = DocumentFingerprint(content: "first\nsecond\nthird")
        let reference = try ResearchLineReference(
            fingerprint: fingerprint,
            line: 2,
            endLine: 3
        )
        let statement = try PortableResearchStatement(
            author: .researcher,
            kind: .discussionTurn,
            attribution: "Researcher",
            text: "The distinction needs another premise.",
            createdAt: Date(timeIntervalSince1970: 10),
            lineReference: reference
        )
        let data = try JSONEncoder.scholium.encode(statement)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let encodedReference = try #require(
            object["line_reference"] as? [String: Any]
        )

        #expect(object["passage"] == nil)
        #expect(encodedReference["line"] as? Int == 2)
        #expect(encodedReference["end_line"] as? Int == 3)
        #expect(encodedReference["quotation"] == nil)
        #expect(encodedReference["utf8_range"] == nil)
        #expect(try JSONDecoder.scholium.decode(
            PortableResearchStatement.self,
            from: data
        ) == statement)

        var unknown = encodedReference
        unknown["quotation"] = "must not decode"
        var invalidStatement = object
        invalidStatement["line_reference"] = unknown
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchStatement.self,
                from: JSONSerialization.data(withJSONObject: invalidStatement)
            )
        }
        #expect(throws: PortableResearchRecordError.self) {
            _ = try ResearchLineReference(
                fingerprint: fingerprint,
                line: 3,
                endLine: 2
            )
        }
        #expect(throws: PortableResearchRecordError.self) {
            _ = try PortableResearchStatement(
                author: .researcher,
                kind: .discussionTurn,
                attribution: "Researcher",
                text: "Ambiguous location",
                passage: CommentAnchor(
                    fingerprint: fingerprint,
                    utf8Range: 0..<5,
                    utf16Range: 0..<5,
                    line: 1,
                    endLine: 1,
                    quotation: "first"
                ),
                lineReference: reference
            )
        }
    }

    @Test("Record encoding exposes only the portable scholarly whitelist")
    func recordFieldWhitelist() throws {
        let record = try makeRecord()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(object.keys) == [
            "schema_version", "id", "triptych_id", "record_title", "kind", "action", "method",
            "participating_notes", "statements", "actually_used_materials",
            "fidelity_completion", "confirmed_changes", "discrepancies",
            "literature_recommendations", "started_at", "finished_at",
            "primary_note_id", "result_disposition",
            "academic_results",
        ])
        #expect(object["schema_version"] as? Int == 8)
        #expect(object["record_title"] as? String == "The remaining pressure")
        #expect(object["fidelity_completion"] as? String == "not_required")
        let changes = try #require(object["confirmed_changes"] as? [[String: Any]])
        #expect(changes.first?["actor"] as? String == "agent")
        let source = String(decoding: data, as: UTF8.self)
        for forbidden in [
            "function", "execution_kind", "prepared_instructions", "prompt",
            "activity_key", "bookmark", "absolute_path", "token_count",
            "transport_log", "window_state", "diff_hunks",
        ] {
            #expect(!source.contains("\"\(forbidden)\""))
        }
        #expect(try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: data
        ) == record)
    }

    @Test("Schema 8 requires a frozen title and rejects every retired schema")
    func schemaSevenIsStrict() throws {
        for invalidTitle in ["", "line one\nline two", "/Users/researcher/private.md"] {
            #expect(throws: PortableResearchRecordError.self) {
                _ = try ResearchRecordTitle(invalidTitle)
            }
        }

        for fidelity in [
            PortableResearchFidelityCompletion.notRequired,
            .completed,
            .unverified,
        ] {
            let action = try makeRecord(fidelityCompletion: fidelity)
            #expect(try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONEncoder.scholium.encode(action)
            ) == action)
        }

        let record = try makeRecord()
        let encoded = try JSONEncoder.scholium.encode(record)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        for version in [1, 2, 3, 4, 5, 6] {
            object["schema_version"] = version
            #expect(throws: PortableResearchRecordError.self) {
                _ = try JSONDecoder.scholium.decode(
                    PortableResearchRecord.self,
                    from: JSONSerialization.data(withJSONObject: object)
                )
            }
        }

        object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "record_title")
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "literature_recommendations")
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "actually_used_materials")
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["fidelity_completion"] = "not_applicable"
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        object["fidelity_completion"] = "unknown"
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test("Analyze recommendation identities are fixed by parent run and ordinal")
    func analyzeRecommendationIdentityAndOrderFailClosed() throws {
        let recordID = UUID(
            uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        )!
        let disposition = try PortableResearchRecommendationDisposition(
            status: .unprocessed,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let recommendations = try [
            ResearchLiteratureRecommendation(
                id: ResearchLiteratureRecommendation.stableID(
                    runID: recordID,
                    ordinal: 0
                ),
                rawCitation: "First source-grounded lead",
                reason: "The source identifies the first work as a live objection.",
                disposition: disposition
            ),
            ResearchLiteratureRecommendation(
                id: ResearchLiteratureRecommendation.stableID(
                    runID: recordID,
                    ordinal: 1
                ),
                rawCitation: "Second source-grounded lead",
                reason: "The source uses the second work to frame its reply.",
                disposition: disposition
            ),
        ]
        let record = try makeAnalyzeRecord(recommendations: recommendations)
        let encoded = try JSONEncoder.scholium.encode(record)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let originalRecommendations = try #require(
            object["literature_recommendations"] as? [[String: Any]]
        )

        var wrongIdentity = originalRecommendations
        wrongIdentity[0]["id"] = UUID().uuidString
        object["literature_recommendations"] = wrongIdentity
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        object["literature_recommendations"] = Array(
            originalRecommendations.reversed()
        )
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }

        object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "source_reference")
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        }
    }

    @Test("Actually-used Materials must match their portable participant facts")
    func actuallyUsedMaterialsMatchParticipants() throws {
        let record = try makeRecord(includeMaterialUse: true)
        var object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder.scholium.encode(record)
            ) as? [String: Any]
        )
        var materials = try #require(
            object["actually_used_materials"] as? [[String: Any]]
        )
        var material = try #require(materials.first)

        for (key, replacement) in [
            ("role", "work"),
            ("title", "Contradictory title"),
            ("note", [
                "vaultID": UUID().uuidString,
                "relativePath": "Analysis.md",
            ]),
        ] as [(String, Any)] {
            let original = material[key]
            material[key] = replacement
            materials[0] = material
            object["actually_used_materials"] = materials
            #expect(throws: PortableResearchRecordError.self) {
                _ = try JSONDecoder.scholium.decode(
                    PortableResearchRecord.self,
                    from: JSONSerialization.data(withJSONObject: object)
                )
            }
            material[key] = original
        }
    }

    @Test("Unknown portable fields and absolute paths fail closed")
    func unknownFieldsAndPathsFailClosed() throws {
        let record = try makeRecord()
        let encoder = JSONEncoder.scholium
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(record))
                as? [String: Any]
        )
        for forbidden in [
            "prompt", "raw_key", "diff_hunks", "token_count", "transport_log",
            "bookmark", "absolute_path", "window_state",
        ] {
            object[forbidden] = "must not decode"
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: PortableResearchRecordError.self) {
                _ = try JSONDecoder.scholium.decode(
                    PortableResearchRecord.self,
                    from: data
                )
            }
            object.removeValue(forKey: forbidden)
        }

        #expect(throws: PortableResearchRecordError.self) {
            _ = try PortableResearchStatement(
                author: .agent,
                kind: .agentFeedback,
                attribution: "Agent",
                text: "I read /Users/researcher/private/source.pdf."
            )
        }
        #expect(throws: PortableResearchRecordError.self) {
            _ = try PortableResearchNoteRevision(
                noteID: UUID(),
                note: VaultQualifiedNoteID(
                    vaultID: UUID(),
                    relativePath: "/Users/researcher/private/Topic.md"
                ),
                role: .topic,
                title: "Topic",
                startingRevision: DocumentFingerprint(content: "topic"),
                endingRevision: DocumentFingerprint(content: "topic")
            )
        }
        #expect(throws: PortableResearchRecordError.self) {
            _ = try PortableResearchStatement(
                author: .researcher,
                kind: .discussionTurn,
                attribution: "Researcher",
                text: "Inspect this passage.",
                passage: CommentAnchor(
                    fingerprint: DocumentFingerprint(content: "path"),
                    utf8Range: 0..<20,
                    utf16Range: 0..<20,
                    line: 1,
                    endLine: 1,
                    quotation: "/Users/researcher/private/source.pdf"
                )
            )
        }

        var nested = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(record))
                as? [String: Any]
        )
        var participants = try #require(
            nested["participating_notes"] as? [[String: Any]]
        )
        var participant = try #require(participants.first)
        var note = try #require(participant["note"] as? [String: Any])
        note["bookmark"] = "private-bookmark-bytes"
        participant["note"] = note
        participants[0] = participant
        nested["participating_notes"] = participants
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: nested)
            )
        }

        nested = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(record))
                as? [String: Any]
        )
        participants = try #require(
            nested["participating_notes"] as? [[String: Any]]
        )
        participant = try #require(participants.first)
        var fingerprint = try #require(
            participant["starting_revision"] as? [String: Any]
        )
        fingerprint["absolute_path"] = "/Users/researcher/private/source.pdf"
        participant["starting_revision"] = fingerprint
        participants[0] = participant
        nested["participating_notes"] = participants
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: nested)
            )
        }

        nested = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(record))
                as? [String: Any]
        )
        var method = try #require(nested["method"] as? [String: Any])
        method["display_name"] = "C:\\Users\\researcher\\SKILL.md"
        nested["method"] = method
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: nested)
            )
        }
    }

    @Test("Discrepancy identities are deterministic for exact completion retry")
    func discrepancyIdentityIsDeterministic() {
        let runID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let noteID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let changed = PortableResearchDiscrepancy.stableID(
            runID: runID,
            noteID: noteID,
            kind: .changedButNotReported
        )
        #expect(changed == PortableResearchDiscrepancy.stableID(
            runID: runID,
            noteID: noteID,
            kind: .changedButNotReported
        ))
        #expect(changed != PortableResearchDiscrepancy.stableID(
            runID: runID,
            noteID: noteID,
            kind: .reportedButUnmodified
        ))
    }

    @Test("Portable Method attribution retains only registration, display name, and Practice names")
    func methodAttributionIsMinimal() throws {
        let snapshot = try makeActionSnapshot(practiceNames: [
            "Conceptual Analyst",
            "Dialectical Partner",
        ])
        let reference = try PortableResearchMethodReference(snapshot: snapshot)
        #expect(reference.practiceNames == [
            "Conceptual Analyst",
            "Dialectical Partner",
        ])
        let data = try JSONEncoder.scholium.encode(reference)
        let encoded = String(decoding: data, as: UTF8.self)
        #expect(!encoded.localizedCaseInsensitiveContains("package"))
        #expect(!encoded.contains("resource"))
        #expect(!encoded.contains("method_source"))
        #expect(try JSONDecoder.scholium.decode(
            PortableResearchMethodReference.self,
            from: data
        ) == reference)
    }

    @Test("Actually-used Materials cannot be inferred from participating notes")
    func materialUseRemainsExplicit() throws {
        let record = try makeRecord()
        #expect(record.participatingNotes.count == 1)
        #expect(record.actuallyUsedMaterials.isEmpty)
    }

    @Test("Changes and Material use must match participating Note revisions")
    func evidenceMustMatchParticipants() throws {
        let snapshot = try makeActionSnapshot()
        let ending = DocumentFingerprint(content: "# Topic\nRevised")
        let participant = try PortableResearchNoteRevision(
            noteID: snapshot.target.noteID,
            note: snapshot.target.note,
            role: snapshot.target.role,
            title: snapshot.target.title,
            startingRevision: snapshot.target.fingerprint,
            endingRevision: ending
        )

        #expect(throws: PortableResearchRecordError.self) {
            _ = try PortableResearchRecord(
                triptychID: UUID(),
                title: try ResearchRecordTitle("Invalid material use"),
                kind: .action,
                action: ResearchActionRecordIdentity(snapshot: snapshot),
                method: try PortableResearchMethodReference(snapshot: snapshot),
                participatingNotes: [participant],
                statements: [],
                actuallyUsedMaterials: [try PortableResearchMaterialUse(
                    noteID: participant.noteID,
                    note: participant.note,
                    role: participant.role,
                    title: participant.title,
                    revision: DocumentFingerprint(content: "a different revision")
                )],
                fidelityCompletion: .notRequired,
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 20)
            )
        }

        #expect(throws: PortableResearchRecordError.self) {
            _ = try PortableResearchRecord(
                triptychID: UUID(),
                title: try ResearchRecordTitle("Invalid confirmed change"),
                kind: .action,
                action: ResearchActionRecordIdentity(snapshot: snapshot),
                method: try PortableResearchMethodReference(snapshot: snapshot),
                participatingNotes: [participant],
                statements: [],
                fidelityCompletion: .notRequired,
                confirmedChanges: [try PortableResearchConfirmedChange(
                    noteID: participant.noteID,
                    actor: .agent,
                    startingRevision: snapshot.target.fingerprint,
                    endingRevision: DocumentFingerprint(content: "another ending")
                )],
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 20)
            )
        }
    }

    @Test("A safe Source Reference is portable without a machine locator")
    func sourceReferenceIsPathFree() throws {
        let source = try ResearchSourceReference(
            identity: .localFile(
                id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
            ),
            displayName: "Source.pdf",
            fingerprint: DocumentFingerprint(content: "source bytes")
        )
        let record = try makeRecord(sourceReference: source)
        let data = try JSONEncoder.scholium.encode(record)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["source_reference"] != nil)
        let encoded = String(decoding: data, as: UTF8.self)
        #expect(!encoded.contains("bookmark"))
        #expect(!encoded.contains("absolute_path"))
        #expect(!encoded.contains("/Users/"))
        #expect(try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: data
        ) == record)
    }

    @Test("Researcher evaluation and Method feedback are separate authored partitions")
    func evaluationAndMethodFeedbackPartitions() throws {
        #expect(throws: PortableResearchRecordError.self) {
            _ = try PortableResearcherEvaluation(
                observedIssues: [.sourceOrAttribution],
                noIssuesObserved: true
            )
        }
        #expect(throws: PortableResearchRecordError.self) {
            _ = try ResearcherEvaluationDraft(note: "/Users/private/claim.md")
        }

        let base = try makeRecord()
        let evaluation = try PortableResearcherEvaluation(
            observedIssues: [.conceptOrInterpretation],
            valuableDiscovery: true,
            note: "The distinction is useful, but the interpretation needs qualification.",
            updatedAt: Date(timeIntervalSince1970: 30)
        )
        let comment = try PortableResearchMethodFeedbackComment(
            text: "Require an explicit alternative-reading check before conclusion.",
            sourceEvaluationRevision: evaluation.revision,
            updatedAt: Date(timeIntervalSince1970: 31)
        )
        let evaluated = try PortableResearchRecord(
            id: base.id,
            triptychID: base.triptychID,
            title: base.title,
            kind: base.kind,
            action: base.action,
            method: base.method,
            sourceReference: base.sourceReference,
            continuationLineage: base.continuationLineage,
            primaryNoteID: base.primaryNoteID,
            participatingNotes: base.participatingNotes,
            statements: base.statements,
            resultDisposition: base.resultDisposition,
            academicResults: base.academicResults,
            contextUseReport: base.contextUseReport,
            actuallyUsedMaterials: base.actuallyUsedMaterials,
            fidelityCompletion: base.fidelityCompletion,
            confirmedChanges: base.confirmedChanges,
            discrepancies: base.discrepancies,
            literatureRecommendations: base.literatureRecommendations,
            startedAt: base.startedAt,
            finishedAt: base.finishedAt,
            researcherEvaluation: evaluation,
            methodFeedbackComment: comment
        )

        #expect(try base.finalizedResultFingerprint()
            == evaluated.finalizedResultFingerprint())
        #expect(evaluated.researcherEvaluation?.author == .researcher)
        #expect(evaluated.methodFeedbackComment?.author == .researcher)
        let data = try JSONEncoder.scholium.encode(evaluated)
        let source = String(decoding: data, as: UTF8.self)
        #expect(source.contains("researcher_evaluation"))
        #expect(source.contains("method_feedback_comment"))
        #expect(!source.contains("evaluation_history"))
        #expect(try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: data
        ) == evaluated)
    }

    @Test("Note Review round trips independently and schema 7 Records fail closed")
    func noteReviewRoundTripAndRecordSchemaCut() throws {
        let record = try makeRecord()
        let noteID = try #require(record.confirmedChanges.first?.noteID)
        let review = try PortableResearchNoteReview(
            noteID: noteID,
            observedRevision: DocumentFingerprint(content: "saved source"),
            reviewedAt: Date(timeIntervalSince1970: 40),
            coveredActivities: [PortableResearchNoteActivityReference(
                recordID: record.id,
                noteID: noteID
            )]
        )
        let reviewData = try JSONEncoder.scholium.encode(review)
        #expect(try JSONDecoder.scholium.decode(
            PortableResearchNoteReview.self,
            from: reviewData
        ) == review)
        var reviewObject = try #require(
            JSONSerialization.jsonObject(with: reviewData) as? [String: Any]
        )
        reviewObject["schema_version"] = 0
        #expect(throws: PortableResearchNoteReviewError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchNoteReview.self,
                from: JSONSerialization.data(withJSONObject: reviewObject)
            )
        }
        reviewObject["schema_version"] = PortableResearchNoteReview
            .currentSchemaVersion
        reviewObject["unexpected_review_owner"] = true
        #expect(throws: PortableResearchNoteReviewError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchNoteReview.self,
                from: JSONSerialization.data(withJSONObject: reviewObject)
            )
        }

        var legacy = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder.scholium.encode(record)
            ) as? [String: Any]
        )
        legacy["schema_version"] = 7
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: legacy)
            )
        }
        legacy["schema_version"] = PortableResearchRecord.currentSchemaVersion
        legacy["researcher_review_disposition"] = [:]
        #expect(throws: PortableResearchRecordError.self) {
            _ = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: JSONSerialization.data(withJSONObject: legacy)
            )
        }
    }

    @Test("Confirmed Agent change may begin after the participant Run-start revision")
    func confirmedChangeBaselineMayFollowRunStart() throws {
        let base = try makeRecord()
        let participant = try #require(base.participatingNotes.first)
        let externalRevision = DocumentFingerprint(content: "# Topic\nExternal edit\n")
        let agentRevision = DocumentFingerprint(content: "# Topic\nAgent edit\n")
        let changedParticipant = try PortableResearchNoteRevision(
            noteID: participant.noteID,
            note: participant.note,
            role: participant.role,
            title: participant.title,
            startingRevision: participant.startingRevision,
            endingRevision: agentRevision
        )
        let record = try PortableResearchRecord(
            id: base.id,
            triptychID: base.triptychID,
            title: base.title,
            kind: base.kind,
            action: base.action,
            method: base.method,
            primaryNoteID: base.primaryNoteID,
            participatingNotes: [changedParticipant],
            statements: base.statements,
            fidelityCompletion: base.fidelityCompletion,
            confirmedChanges: [try PortableResearchConfirmedChange(
                noteID: participant.noteID,
                actor: .agent,
                startingRevision: externalRevision,
                endingRevision: agentRevision
            )],
            startedAt: base.startedAt,
            finishedAt: base.finishedAt
        )
        #expect(record.participatingNotes[0].startingRevision
            != record.confirmedChanges[0].startingRevision)
        #expect(throws: PortableResearchRecordError.invalidConfirmedChange) {
            _ = try PortableResearchConfirmedChange(
                noteID: participant.noteID,
                actor: .researcher,
                startingRevision: externalRevision,
                endingRevision: agentRevision
            )
        }
    }

    @Test("Discussion Records cannot acquire Researcher Response state")
    func discussionRejectsResearcherResponse() throws {
        let base = try makeRecord()
        let participant = try #require(base.participatingNotes.first)
        let evaluation = try PortableResearcherEvaluation(noIssuesObserved: true)
        let reply = try PortableResearchStatement(
            author: .researcher,
            kind: .discussionTurn,
            attribution: "Researcher",
            text: "Keep this distinction explicit."
        )
        #expect(throws: PortableResearchRecordError.invalidRecord) {
            _ = try PortableResearchRecord(
                id: base.id,
                triptychID: base.triptychID,
                title: base.title,
                kind: .discussion,
                action: base.action,
                method: base.method,
                primaryNoteID: participant.noteID,
                participatingNotes: [participant],
                statements: [reply],
                fidelityCompletion: .notApplicable,
                startedAt: base.startedAt,
                finishedAt: base.finishedAt,
                researcherEvaluation: evaluation
            )
        }
    }

    private func makeRecord(
        sourceReference: ResearchSourceReference? = nil,
        includeMaterialUse: Bool = false,
        fidelityCompletion: PortableResearchFidelityCompletion = .notRequired
    ) throws -> PortableResearchRecord {
        let snapshot = try makeActionSnapshot()
        let ending = DocumentFingerprint(content: "# Topic\nRevised")
        let note = try PortableResearchNoteRevision(
            noteID: snapshot.target.noteID,
            note: snapshot.target.note,
            role: snapshot.target.role,
            title: snapshot.target.title,
            startingRevision: snapshot.target.fingerprint,
            endingRevision: ending
        )
        let feedback = try PortableResearchStatement(
            author: .agent,
            kind: .agentFeedback,
            attribution: "Agent",
            text: "I qualified the objection and left the residual pressure open.",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let analysisID = UUID(
            uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
        )!
        let analysisNote = VaultQualifiedNoteID(
            vaultID: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            relativePath: "Analysis.md"
        )
        let analysisRevision = DocumentFingerprint(content: "# Analysis\n")
        let analysisParticipant = try PortableResearchNoteRevision(
            noteID: analysisID,
            note: analysisNote,
            role: .analysis,
            title: "Analysis",
            startingRevision: analysisRevision,
            endingRevision: analysisRevision
        )
        let materialUse = try PortableResearchMaterialUse(
            noteID: analysisID,
            note: analysisNote,
            role: .analysis,
            title: "Analysis",
            revision: analysisRevision
        )
        return try PortableResearchRecord(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            triptychID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            title: try ResearchRecordTitle("The remaining pressure"),
            kind: .action,
            action: ResearchActionRecordIdentity(snapshot: snapshot),
            method: try PortableResearchMethodReference(snapshot: snapshot),
            sourceReference: sourceReference,
            primaryNoteID: snapshot.target.noteID,
            participatingNotes: includeMaterialUse ? [note, analysisParticipant] : [note],
            statements: [feedback],
            actuallyUsedMaterials: includeMaterialUse ? [materialUse] : [],
            fidelityCompletion: fidelityCompletion,
            confirmedChanges: [try PortableResearchConfirmedChange(
                noteID: snapshot.target.noteID,
                actor: .agent,
                startingRevision: snapshot.target.fingerprint,
                endingRevision: ending
            )],
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20)
        )
    }

    private func makeAnalyzeRecord(
        recommendations: [ResearchLiteratureRecommendation]
    ) throws -> PortableResearchRecord {
        let base = try makeRecord(sourceReference: ResearchSourceReference(
            identity: .localFile(
                id: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
            ),
            displayName: "Source.pdf",
            fingerprint: DocumentFingerprint(content: "source bytes")
        ))
        return try PortableResearchRecord(
            id: base.id,
            triptychID: base.triptychID,
            title: base.title,
            kind: base.kind,
            action: ResearchActionRecordIdentity(actionID: .analyze),
            method: base.method,
            sourceReference: base.sourceReference,
            continuationLineage: base.continuationLineage,
            primaryNoteID: base.primaryNoteID,
            participatingNotes: base.participatingNotes,
            statements: base.statements,
            actuallyUsedMaterials: base.actuallyUsedMaterials,
            fidelityCompletion: base.fidelityCompletion,
            confirmedChanges: base.confirmedChanges,
            discrepancies: base.discrepancies,
            literatureRecommendations: recommendations,
            startedAt: base.startedAt,
            finishedAt: base.finishedAt
        )
    }

    private func makeActionSnapshot(
        practiceNames: [String] = []
    ) throws -> ResearchActionSnapshot {
        let definition = ResearchActionDefinition.synthesize
        let target = ResearchActionNoteSnapshot(
            noteID: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            note: VaultQualifiedNoteID(
                vaultID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
                relativePath: "Problem.md"
            ),
            role: .topic,
            lifecycle: .active,
            fingerprint: DocumentFingerprint(content: "# Topic\n"),
            title: "Problem"
        )
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .synthesize
            }
        )
        let profileRevision = try profile.contentRevision()
        let registration = try ResearchSkillRegistration(
            key: ResearchSkillRegistrationKey(
                rawValue: UUID(
                    uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE"
                )!
            ),
            actionID: .synthesize,
            displayName: "Synthesize",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Synthesize\n\nExact method.\n",
            practices: try practiceNames.enumerated().map { index, name in
                try ResearchPracticeSnapshot(
                    title: name,
                    relativePath: "Practice-\(index).md",
                    source: "# \(name)\n\nExact Practice.\n"
                )
            }
        )
        let resolvedProfile = try ResearchActionResolvedProfileSnapshot(
            profile: profile,
            profileRevision: profileRevision,
            profileDocumentRevision: DocumentFingerprint(content: "profiles")
        )
        return try ResearchActionSnapshot(
            definition: definition,
            target: target,
            method: method,
            resolvedProfile: resolvedProfile,
            platformInputs: ResearchActionPlatformInputs(),
            academicInputs: ResearchAcademicFieldValues(
                values: [:],
                definitions: profile.academicInputFields
            ),
            resultContract: ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: profileRevision
            ),
            authority: try ResearchAuthorityEnvelope(
                readableNotes: [target],
                writableNotes: [target],
                writeOperations: [.modifyMarkdown],
                editablePropertyKeys: []
            )
        )
    }
}

private extension JSONEncoder {
    static var scholium: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var scholium: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
