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
            "schema_version", "id", "triptych_id", "kind", "action", "method",
            "participating_notes", "statements", "actually_used_materials",
            "fidelity_completion", "confirmed_changes", "discrepancies",
            "started_at", "finished_at", "is_pinned", "primary_note_id",
        ])
        #expect(object["schema_version"] as? Int == 3)
        #expect(object["fidelity_completion"] as? String == "not_required")
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

    @Test("Schema 3 requires explicit Material and Fidelity completion fields")
    func schemaThreeIsStrict() throws {
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

        for version in [1, 2] {
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
        var resources = try #require(
            method["loaded_resources"] as? [[String: Any]]
        )
        resources[0]["relative_path"] = "C:\\Users\\researcher\\SKILL.md"
        method["loaded_resources"] = resources
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

    @Test("Portable Method resources allow safe non-Markdown templates and evals")
    func nonMarkdownMethodResourcesRemainPortable() throws {
        let snapshot = try makeActionSnapshot(resourcePaths: [
            "SKILL.md",
            "templates/completion.json",
            "evals/cases.yaml",
        ])
        let reference = try PortableResearchMethodReference(snapshot: snapshot)
        #expect(reference.loadedResources.map(\.relativePath) == [
            "SKILL.md",
            "evals/cases.yaml",
            "templates/completion.json",
        ])
        let data = try JSONEncoder.scholium.encode(reference)
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
                kind: .action,
                action: ResearchActionRecordIdentity(snapshot: snapshot),
                method: try PortableResearchMethodReference(snapshot: snapshot),
                participatingNotes: [participant],
                statements: [],
                fidelityCompletion: .notRequired,
                confirmedChanges: [try PortableResearchConfirmedChange(
                    noteID: participant.noteID,
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
                startingRevision: snapshot.target.fingerprint,
                endingRevision: ending
            )],
            startedAt: Date(timeIntervalSince1970: 10),
            finishedAt: Date(timeIntervalSince1970: 20)
        )
    }

    private func makeActionSnapshot(
        resourcePaths: [String] = ["SKILL.md"]
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
        let profile = try ResearchActionProfile(
            definition: definition,
            buttonName: "Synthesize",
            order: 100,
            applicableRoles: [.topic],
            showInActions: true,
            modules: [],
            sourceRequirement: .none,
            capabilities: try ResearchActionCapabilityDeclaration(
                readableRoles: [.analysis, .topic],
                candidateWritableRoles: [.topic],
                candidateWriteOperations: [.modifyMarkdown]
            ),
            feedbackRequirement: .requested
        )
        return try ResearchActionSnapshot(
            definition: definition,
            target: target,
            method: try ResearchActionMethodSnapshot(
                packageID: "scholium-synthesize",
                origin: .triptych,
                version: "working",
                packageRevision: DocumentFingerprint(content: "package"),
                loadedResources: resourcePaths.map {
                    ResearchActionResourceSnapshot(
                        relativePath: $0,
                        revision: DocumentFingerprint(content: "method:\($0)")
                    )
                }
            ),
            resolvedProfile: try ResearchActionResolvedProfileSnapshot(
                origin: .applicationDefault,
                profile: profile,
                profileRevision: profile.contentRevision(),
                profileDocumentRevision: nil
            ),
            parameters: try ResearchActionParameterModel(profile: profile),
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
