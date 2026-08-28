import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

extension ResearchActionRunOperationsTests {
    @Test("Every Platform Action returns one complete authenticated Agent command path")
    func everyActionReturnsCurrentAgentTemplates() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = actionNote(try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        ))
        let topic = actionNote(try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        ))
        let work = actionNote(try await researchActionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        ))
        let cases: [(ResearchActionID, ResearchActionNoteSnapshot)] = [
            (.discuss, analysis),
            (.analyze, analysis),
            (.synthesize, topic),
            (.write, work),
            (.critique, work),
            (.checkFidelity, analysis),
        ]

        for (actionID, target) in cases {
            let platformInputs = actionID == .checkFidelity
                ? try ResearchActionPlatformInputs(fidelityChecks: [.content])
                : try ResearchActionPlatformInputs()
            let preparation = try await handle.research.prepareAction(
                try await actionRequest(
                    handle: handle,
                    actionID: actionID,
                    target: target,
                    platformInputs: platformInputs
                )
            )
            let handoff = try await handle.research.issueAgentHandoff(
                runID: preparation.runID
            )
            let credential = try await handle.research.pairAgent(
                run: handoff.run,
                pairingCode: handoff.pairingCode
            )
            let initialContext = try await runtime.researchAgentInitialContext(
                credential: credential,
                run: handoff.run
            )
            let context = try #require({
                if case .action(let context) = initialContext { return context }
                return nil
            }())
            #expect(context.nextActions.allSatisfy {
                Array($0.command.prefix(2)) == ["scholium", "agent"]
            })
            let evidenceQueries = context.nextActions.filter {
                $0.kind == .query
            }
            #expect(evidenceQueries.contains {
                $0.requirement == .required
                    && $0.label.contains("exact current Target revision")
                    && $0.inputTemplate?.contains("read_note") == true
            })
            #expect(evidenceQueries.contains {
                $0.requirement == .whenNeeded
                    && $0.label.contains("Search the current Triptych")
                    && $0.inputTemplate?.contains("discover_note") == true
                    && $0.inputTemplate?.contains(
                        "REPLACE_WITH_BOUNDED_SEARCH_QUERY"
                    ) == true
            })
            #expect(evidenceQueries.contains {
                $0.requirement == .whenNeeded
                    && $0.label.contains("Dynamically rank related")
                    && $0.command.contains("related")
                    && $0.command.contains("--note")
            })

            let expectsRecommendedReading = actionID == .synthesize
                || actionID == .write || actionID == .critique
            #expect((context.recommendedReading != nil)
                == expectsRecommendedReading)
            if expectsRecommendedReading {
                let directory = try #require(context.recommendedReading)
                #expect(directory.state == .current)
                #expect(!directory.candidates.isEmpty)
                if actionID == .synthesize {
                    #expect(directory.candidates.allSatisfy {
                        $0.role == .analysis
                    })
                } else {
                    #expect(directory.candidates.allSatisfy {
                        $0.role == .analysis || $0.role == .topic
                    })
                }
                let analysisCandidate = try #require(
                    directory.candidates.first {
                        $0.note == fixture.analysisID
                    }
                )
                if actionID == .write || actionID == .critique {
                    #expect(analysisCandidate.reasons.contains {
                        if case .directConnection = $0 { return true }
                        return false
                    })
                    #expect(analysisCandidate.reasons.contains {
                        if case .identityMention = $0 { return true }
                        return false
                    })
                    #expect(analysisCandidate.reasons.contains {
                        if case .lexicalOverlap = $0 { return true }
                        return false
                    })
                }
                let readActions = evidenceQueries.filter {
                    $0.label.contains("recommended Analyses")
                }
                #expect(!readActions.isEmpty)
                let requests = try readActions.map { action in
                    try JSONDecoder().decode(
                        ResearchContextRequest.self,
                        from: Data(try #require(action.inputTemplate).utf8)
                    )
                }
                let clauses = requests.flatMap(\.clauses)
                #expect(clauses.allSatisfy {
                    $0.kind == .readNote
                        && $0.note != nil
                        && $0.expectedFingerprint != nil
                        && $0.useEligibility == .contextUse
                })
                #expect(Set(clauses.compactMap(\.note))
                    == Set(directory.candidates.map(\.note)))
                #expect(Set(clauses.compactMap(\.expectedFingerprint))
                    == Set(directory.candidates.map(\.fingerprint)))
            }

            if actionID == .discuss {
                #expect(context.nextActions.suffix(2).map { $0.kind } == [
                    AgentCommandActionKind.reply,
                    AgentCommandActionKind.finish,
                ])
                let reply = try #require(context.nextActions.first {
                    $0.kind == .reply
                })
                #expect(reply.requirement == .required)
                let replyTemplate = try #require(reply.inputTemplate)
                #expect(replyTemplate.contains("statement_id"))
                #expect(replyTemplate.contains("attribution"))
            } else {
                let result = try #require(
                    context.nextActions.first {
                        $0.kind == AgentCommandActionKind.submitResult
                    }
                )
                let resultTemplate = try #require(result.inputTemplate)
                let object = try #require(
                    JSONSerialization.jsonObject(
                        with: Data(resultTemplate.utf8)
                    ) as? [String: Any]
                )
                #expect(object["schema_version"] as? Int
                    == ResearchAgentResultSubmission.currentSchemaVersion)
                #expect(object["record_title"] as? String != nil)
                #expect((object["context_use_claims"] as? [Any])?.isEmpty == true)
                #expect(object["fidelity_outcomes"] as? [Any] != nil)
                #expect(result.label.contains("fidelity_outcomes empty")
                    == (actionID != .checkFidelity))
                let academicResults = try #require(
                    object["academic_results"] as? [String: Any]
                )
                let values = try #require(
                    academicResults["values"] as? [String: Any]
                )
                let derivesDefaultFidelity = actionID == .checkFidelity
                #expect(derivesDefaultFidelity
                    ? values.isEmpty
                    : Set(values.keys) == Set(
                        preparation.snapshot.resultContract.academicFields
                            .filter { $0.requirement == .required }
                            .map { $0.fieldID.rawValue }
                    ))
                #expect((object["literature_recommendations"] != nil)
                    == (actionID == .analyze))

                let writes = context.nextActions.filter {
                    $0.kind == AgentCommandActionKind.write
                }
                let expectsWrite = [.analyze, .synthesize, .write]
                    .contains(actionID)
                #expect(writes.isEmpty == !expectsWrite)
                for write in writes {
                    #expect(write.requirement == .whenNeeded)
                    let template = try #require(write.inputTemplate)
                    #expect(template.contains("\"relative_path\""))
                    #expect(template.contains("\"operation\""))
                }
            }

            _ = try await runtime.endResearchAgentRun(
                credential: credential,
                run: handoff.run
            )
        }
        await runtime.shutdown()
    }

    @Test("Recommended Reading preserves selected-passage and research-request seed reasons")
    func recommendedReadingUsesFrozenTaskFocus() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let work = actionNote(try await researchActionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        ))
        let source = try await handle.documents.load(fixture.workID)
        let selection = try commentAnchor(
            in: source,
            quotation: "A claim requiring Critique"
        )
        let requestID = try #require(
            ResearchAcademicFieldID(rawValue: "research-request")
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .critique,
                target: work,
                platformInputs: ResearchActionPlatformInputs(
                    passage: selection
                ),
                academicValues: [
                    requestID: .freeText("Compare the draft with Agency."),
                ]
            )
        )
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let context = try await runtime.researchAgentContext(
            credential: credential,
            run: handoff.run
        )
        let directory = try #require(context.recommendedReading)
        let analysis = try #require(directory.candidates.first {
            $0.note == fixture.analysisID
        })
        #expect(analysis.reasons.contains { reason in
            guard case .lexicalOverlap(let lexical) = reason else { return false }
            return lexical.seedMatches.contains {
                $0.seedKind == .selectedPassage && $0.terms.contains("claim")
            }
        })
        let topic = try #require(directory.candidates.first {
            $0.note == fixture.topicID
        })
        #expect(topic.reasons.contains { reason in
            guard case .identityMention(let identity) = reason else { return false }
            return identity.mentions.contains {
                $0.seedKind == .researchRequest
                    && $0.identityKind == .title
                    && $0.matchedIdentity == "Agency"
            }
        })

        _ = try await runtime.endResearchAgentRun(
            credential: credential,
            run: handoff.run
        )
        await runtime.shutdown()
    }

    @Test("Agent related-Note query dynamically ranks candidates across exact seeds")
    func agentRelatedNotesRanksAcrossSeeds() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = actionNote(try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        ))
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: topic
            )
        )
        let handoff = try await handle.research.issueAgentHandoff(
            runID: preparation.runID
        )
        let credential = try await handle.research.pairAgent(
            run: handoff.run,
            pairingCode: handoff.pairingCode
        )
        let clause = try ResearchContextClause(
            kind: .relatedNotes,
            noteNames: ["Agency", "Draft Argument"],
            limit: 8,
            useEligibility: .referenceOnly
        )
        let response = try await runtime.queryResearchContext(
            credential: credential,
            run: handoff.run,
            request: ResearchContextRequest(clauses: [clause])
        )
        let outcome = try #require(response.outcomes.first)
        let related = try #require(outcome.relatedNotes)
        #expect(related.state == .current)
        #expect(related.resolvedSeeds.map(\.inputName) == [
            "Agency", "Draft Argument",
        ])
        let first = try #require(related.candidates.first)
        #expect(first.note == fixture.analysisID)
        #expect(first.matches.count == 2)
        #expect(Set(first.matches.map(\.seed.note)) == [
            fixture.topicID, fixture.workID,
        ])
        #expect(first.matches.allSatisfy { match in
            match.reasons.contains {
                if case .directConnection = $0 { return true }
                return false
            }
        })
        #expect(response.items.isEmpty)

        _ = try await runtime.endResearchAgentRun(
            credential: credential,
            run: handoff.run
        )
        await runtime.shutdown()
    }

    @Test("Completion source observation rejects same-byte path identity reuse")
    func completionObservationRevalidatesIdentityAfterSourceRead() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let gate = ControlledObservationTestGate()
        await handle.setResearchActionControlledObservationBarrierForTesting {
            await gate.wait()
        }
        let observation = Task {
            try await handle.researchActionControlledFingerprint(for: target)
        }
        #expect(await gate.waitUntilArrived())
        _ = try await handle.services.controlStore.purgeIdentity(
            id: target.noteID,
            vaultID: target.note.vaultID,
            relativePath: target.note.relativePath
        )
        let replacement = try #require(
            try await handle.services.controlStore.identity(
                forVaultID: target.note.vaultID,
                relativePath: target.note.relativePath,
                fingerprint: target.fingerprint
            )
        )
        #expect(replacement.id != target.noteID)
        await gate.release()
        do {
            _ = try await observation.value
            Issue.record("Expected the controlled observation to reject identity reuse.")
        } catch let error as ResearchActionRunContractError {
            guard case .targetIdentityChanged = error else {
                Issue.record("Unexpected controlled-observation error: \(error)")
                await handle.setResearchActionControlledObservationBarrierForTesting(nil)
                await runtime.shutdown()
                return
            }
        }
        await handle.setResearchActionControlledObservationBarrierForTesting(nil)
        await runtime.shutdown()
    }

    @Test("Real Analyze submission rejects same-byte target identity reuse")
    func analyzeSubmissionUsesControlledTargetObservation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(target)
            )
        )
        let run = try await handle.research.actionRunDetails(id: action.runID)
        let client = try await connectTestResearchAgent(to: run, handle: handle)
        let submission = try makeTestAgentResultSubmission(
            for: run,
            literatureRecommendations: []
        )
        _ = try await handle.services.controlStore.purgeIdentity(
            id: target.noteID,
            vaultID: target.note.vaultID,
            relativePath: target.note.relativePath
        )
        let replacement = try #require(
            try await handle.services.controlStore.identity(
                forVaultID: target.note.vaultID,
                relativePath: target.note.relativePath,
                fingerprint: target.fingerprint
            )
        )
        #expect(replacement.id != target.noteID)
        do {
            _ = try await submitTestAgentResult(
                submission,
                client: client,
                handle: handle
            )
            Issue.record("Expected Analyze completion to reject identity reuse.")
        } catch let error as ResearchActionRunContractError {
            guard case .targetIdentityChanged = error else {
                Issue.record("Unexpected Analyze completion error: \(error)")
                await runtime.shutdown()
                return
            }
        }
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: action.runID
        ).completion == nil)
        #expect(try await handle.research.finishedResearchRecords(
            noteID: target.noteID
        ).allSatisfy { $0.id != action.runID })
        await runtime.shutdown()
    }

    @Test("Action resolver follows the default matrix and explicit disabled Method state")
    func actionResolverDefaultMatrixAndDisabledMethod() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )

        let initial = try await handle.research.availableActions(
            for: actionNote(analysis)
        )
        #expect(initial.map(\.id) == [.discuss, .analyze, .checkFidelity])
        let allInitialActionsAreEnabled = initial.allSatisfy { $0.isEnabled }
        #expect(allInitialActionsAreEnabled)
        let discuss = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(analysis),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Clarify the current distinction."),
                ]
            )
        )
        #expect(discuss.instructions.contains("Clarify the current distinction."))
        try await handle.research.cancelActionRun(runID: discuss.runID)

        let fidelityRequest = try await actionRequest(
            handle: handle,
            actionID: .checkFidelity,
            target: actionNote(analysis),
            platformInputs: try ResearchActionPlatformInputs(
                fidelityChecks: [.content]
            )
        )
        let fidelity = try await handle.research.prepareAction(fidelityRequest)
        #expect(fidelity.snapshot.authority.readableNotes.map(\.noteID) == [analysis.noteID])
        #expect(fidelity.snapshot.platformInputs.fidelityChecks == [.content])
        try await handle.research.cancelActionRun(runID: fidelity.runID)

        let analyze = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        #expect(analyze.snapshot.method.registration.actionID == .analyze)
        #expect(analyze.snapshot.authority.writableNotes.map(\.noteID) == [analysis.noteID])
        try await handle.research.cancelActionRun(runID: analyze.runID)

        let registrations = try await handle.research.researchSkillRegistrations()
        let active = try #require(
            registrations.document.registration(for: .analyze)
        )
        let disabledRegistration = try ResearchSkillRegistration(
            key: active.key,
            actionID: active.actionID,
            displayName: active.displayName,
            primaryMarkdown: active.primaryMarkdown,
            skillFolder: active.skillFolder,
            isEnabled: false
        )
        _ = try await handle.research.saveResearchSkillRegistrations(
            try registrations.document.replacing(disabledRegistration),
            expectedRevision: registrations.revision
        )
        let disabled = try #require(
            try await handle.research.availableActions(for: actionNote(analysis))
                .first { $0.id == .analyze }
        )
        #expect(!disabled.isEnabled)
        #expect(disabled.repairReasons.contains {
            $0.code == .methodMissing || $0.code == .methodDisabled
        })
        await runtime.shutdown()
    }

    @Test("Action Discussion finishes portably without touching legacy activity")
    func actionDiscussionFinishDoesNotProjectLegacyActivity() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let legacyActivity = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("research-activity/research-activity.json")
        if !FileManager.default.fileExists(atPath: legacyActivity.path) {
            try FileManager.default.createDirectory(
                at: legacyActivity.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(
                "{\"schemaVersion\":2,\"events\":[],\"settlements\":[],\"exchanges\":[],\"pendingStates\":[],\"grants\":[]}".utf8
            ).write(to: legacyActivity)
        }
        let before = try LegacyResearchFileCanary(url: legacyActivity)
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(analysis),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Clarify the distinction."),
                ]
            )
        )
        let protectedRun = try await handle.research.actionRunDetails(id: preparation.runID)
        _ = try await handle.research.appendDiscussionStatement(
            discussionID: preparation.runID,
            author: .agent,
            attribution: "Research Agent",
            text: "The distinction remains bounded to the current Analysis."
        )
        _ = try await completeTestActionRun(handle: handle, submission:
            ResearchActionRunCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: protectedRun.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                finalTargetFingerprint: analysis.fingerprint,
                summary: "Returned one bounded clarification.",
                didModifyTarget: false,
                submittedAt: protectedRun.snapshot.preparedAt.addingTimeInterval(2)
            )
        )

        let record = try await handle.research.finishProtectedDiscussion(runID: preparation.runID)
        #expect(record.kind == .discussion)
        #expect(record.action?.actionID == .discuss)
        #expect(try LegacyResearchFileCanary(url: legacyActivity) == before)
        await runtime.shutdown()
    }

    @Test("A portable Discussion cannot substitute for its frozen Action run")
    func portableDiscussionMustMatchFrozenActionRun() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(analysis),
                academicValues: [
                    ResearchAcademicFieldID(rawValue: "research-request")!:
                        .freeText("Clarify the frozen Action boundary."),
                ]
            )
        )
        let protectedRun = try await handle.research.actionRunDetails(id: preparation.runID)
        _ = try await handle.research.appendDiscussionStatement(
            discussionID: preparation.runID,
            author: .agent,
            attribution: "Research Agent",
            text: "The reply remains attached to this exact run."
        )

        let activeURL = fixture.rootURL
            .appendingPathComponent(".scholium/research-records/v1/active", isDirectory: true)
            .appendingPathComponent(preparation.runID.uuidString.lowercased() + ".json")
        var payload = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: activeURL))
                as? [String: Any]
        )
        var action = try #require(payload["action"] as? [String: Any])
        action["action_id"] = ResearchActionID.analyze.rawValue
        payload["action"] = action
        try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            .write(to: activeURL, options: .atomic)

        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await completeTestActionRun(handle: handle, submission:
                ResearchActionRunCompletionSubmission(
                    runID: preparation.runID,
                    confirmationToken: protectedRun.snapshot.confirmationToken,
                    recordTitle: try ResearchRecordTitle("Test research result"),
                    finalTargetFingerprint: analysis.fingerprint,
                    summary: "A mismatched record must not complete the run.",
                    didModifyTarget: false
                )
            )
        }
        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await handle.research.finishProtectedDiscussion(runID: preparation.runID)
        }
        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await handle.research.finishDiscussion(
                discussionID: preparation.runID
            )
        }
        #expect(FileManager.default.fileExists(atPath: activeURL.path))
        await runtime.shutdown()
    }


    @Test("Action Runs use current Local Execution and emit one whitelisted portable Record")
    func actionExecutionUsesSeparatedStoresWithoutTouchingLegacyData() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let triptychSupport = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
        let legacyActivity = triptychSupport
            .appendingPathComponent("research-activity/research-activity.json")
        let legacyDialogue = triptychSupport
            .appendingPathComponent("dialogue/dialogue.json")
        let legacyBindings = fixture.rootURL
            .appendingPathComponent(".scholium", isDirectory: true)
            .appendingPathComponent("research-skill-bindings.json")
        let legacySeeds: [(URL, String)] = [
            (
                legacyActivity,
                "{\"schemaVersion\":2,\"events\":[],\"settlements\":[],\"exchanges\":[],\"pendingStates\":[],\"grants\":[]}"
            ),
            (legacyDialogue, "{\"schemaVersion\":3,\"entries\":{}}"),
            (
                legacyBindings,
                "{\"schema_version\":1,\"function_bindings\":{},\"function_skill_bindings\":{},\"function_practice_bindings\":{}}"
            ),
        ]
        for (url, source) in legacySeeds
            where !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(source.utf8).write(to: url)
        }
        let legacyURLs = [legacyActivity, legacyDialogue, legacyBindings]
        for url in legacyURLs {
            #expect(FileManager.default.fileExists(atPath: url.path))
            try FileManager.default.setAttributes(
                [
                    .posixPermissions: NSNumber(value: 0o640),
                    .modificationDate: Date(timeIntervalSince1970: 1_234),
                ],
                ofItemAtPath: url.path
            )
        }
        let before = try Dictionary(uniqueKeysWithValues: legacyURLs.map {
            ($0, try LegacyResearchFileCanary(url: $0))
        })

        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: actionNote(topic),
                platformInputs: try ResearchActionPlatformInputs(
                    focalNotes: [actionNote(analysis)]
                )
            )
        )
        let protectedRun = try await handle.research.actionRunDetails(id: action.runID)
        #expect(action.instructions.contains("authenticated Agent CLI"))
        #expect(action.instructions.contains("frozen Result Contract"))
        // Keep the original and resynthesis completions on the same timestamp
        // to prove lineage wins the tie, while keeping that timestamp after
        // both preparations so each portable record remains temporally valid.
        let submittedAt = Date().addingTimeInterval(60)
        let submission = ResearchActionRunCompletionSubmission(
            runID: protectedRun.runID,
            confirmationToken: protectedRun.snapshot.confirmationToken,
            recordTitle: try ResearchRecordTitle("Test research result"),
            actuallyUsedMaterialNoteIDs: [analysis.noteID],
            summary: "I read /Users/researcher/private/source.pdf.",
            didModifyTarget: false,
            submittedAt: submittedAt
        )
        let completed: ResearchActionRunCompletion
        do {
            completed = try await completeTestActionRun(handle: handle, submission: submission)
        } catch {
            Issue.record("Valid Action completion failed before record inspection: \(error)")
            throw error
        }
        #expect(completed.state == .complete)
        #expect(completed.actuallyUsedMaterialNoteIDs == [analysis.noteID])
        let repeated: ResearchActionRunCompletion
        do {
            repeated = try await completeTestActionRun(handle: handle, submission: submission)
        } catch {
            Issue.record("Idempotent Action completion failed: \(error)")
            throw error
        }
        #expect(repeated == completed)
        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await completeTestActionRun(handle: handle, submission:
                ResearchActionRunCompletionSubmission(
                    runID: protectedRun.runID,
                    confirmationToken: protectedRun.snapshot.confirmationToken,
                    recordTitle: try ResearchRecordTitle("Test research result"),
                    actuallyUsedMaterialNoteIDs: [analysis.noteID],
                    summary: "No Topic change was warranted by the selected information.",
                    didModifyTarget: false,
                    submittedAt: submittedAt.addingTimeInterval(0.000_1)
                )
            )
        }

        let localURL = await handle.services.localResearchExecutionStore.storageURL
            .appendingPathComponent(action.runID.uuidString.lowercased() + ".json")
        let portableURL = fixture.rootURL
            .appendingPathComponent(".scholium/research-records/v1/records", isDirectory: true)
            .appendingPathComponent(action.runID.uuidString.lowercased() + ".json")
        let localData = try Data(contentsOf: localURL)
        let portableData = try Data(contentsOf: portableURL)
        let portable: PortableResearchRecord
        do {
            portable = try JSONDecoder.scholium.decode(
                PortableResearchRecord.self,
                from: portableData
            )
        } catch {
            Issue.record("The just-written portable Action record did not decode: \(error)")
            throw error
        }
        #expect(portable.id == action.runID)
        #expect(portable.action?.actionID == .synthesize)
        #expect(portable.fidelityCompletion == .notRequired)
        #expect(portable.primaryNoteID == topic.noteID)
        #expect(Set(portable.participatingNotes.map(\.noteID)) == [
            topic.noteID,
            analysis.noteID,
        ])
        #expect(portable.actuallyUsedMaterials == [try PortableResearchMaterialUse(
            noteID: analysis.noteID,
            note: analysis.note,
            role: .analysis,
            title: analysis.title,
            revision: analysis.fingerprint
        )])
        #expect(portable.confirmedChanges.isEmpty)
        #expect(portable.discrepancies.isEmpty)
        #expect(portable.statements.isEmpty)
        let localEnvelope = try #require(
            JSONSerialization.jsonObject(with: localData) as? [String: Any]
        )
        let encodedLocalPayload = try #require(localEnvelope["payload"] as? String)
        let localPayload = try #require(
            Data(base64Encoded: encodedLocalPayload)
        )
        let localSource = String(decoding: localPayload, as: UTF8.self)
        let portableSource = String(decoding: portableData, as: UTF8.self)
        #expect(localSource.contains("prepared_instructions"))
        #expect(!portableSource.contains("/Users/researcher/private/source.pdf"))
        for forbidden in [
            "prepared_instructions", "activity_key", "confirmationToken",
            "function", "prompt", "bookmark", "absolute_path", "token_count",
            "transport_log", "window_state", "diff_hunks",
        ] {
            #expect(!portableSource.contains("\"\(forbidden)\""))
        }
        for (url, canary) in before {
            #expect(try LegacyResearchFileCanary(url: url) == canary)
        }

        let topicBytes = try await handle.documents.load(fixture.topicID).sourceBytes
        try Data("# Analysis\n\nA materially revised reconstruction.\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        let changed = try await handle.refresh()
        let attention = try #require(changed.discovery.catalog.attention.first {
            $0.kind == .materialChangedSinceUse
        })
        #expect(attention.note.stableNoteID == topic.noteID.uuidString.lowercased())
        #expect(attention.materialChangedSinceUse?.recordID == portable.id)
        #expect(attention.materialChangedSinceUse?.materialNoteID == analysis.noteID)
        #expect(attention.materialChangedSinceUse?.recordedRevision == analysis.fingerprint)
        #expect(attention.materialChangedSinceUse?.currentRevision != analysis.fingerprint)
        #expect(!attention.message.lowercased().contains("wrong"))
        #expect(!attention.message.lowercased().contains("outdated"))

        let attentionContext = try #require(attention.materialChangedSinceUse)
        let refreshedTopic = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let refreshedAnalysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let resynthesisRequest = try await actionRequest(
            handle: handle,
            actionID: .synthesize,
            target: actionNote(refreshedTopic),
            platformInputs: try ResearchActionPlatformInputs(
                focalNotes: [actionNote(refreshedAnalysis)]
            )
        )
        let resynthesis = try await handle.research.prepareResynthesis(
            resynthesisRequest,
            context: attentionContext
        )
        let child = try await handle.research.actionRunDetails(id: resynthesis.runID)
        #expect(child.snapshot.continuationLineage?.kind == .resynthesis)
        #expect(child.snapshot.continuationLineage?.parentRunID == portable.id)
        #expect(child.snapshot.continuationLineage?.requestID == resynthesis.runID)
        #expect(child.snapshot.resynthesisContext == attentionContext)
        #expect(child.snapshot.actionSnapshot.authority.writableNotes.map(\.noteID)
            == [topic.noteID])

        let rebuilt = try await handle.refresh()
        #expect(rebuilt.discovery.catalog.attention.first {
            $0.kind == .materialChangedSinceUse
        }?.id == attention.id)
        #expect(try await handle.documents.load(fixture.topicID).sourceBytes == topicBytes)
        #expect(try Data(contentsOf: portableURL) == portableData)

        _ = try await completeTestActionRun(handle: handle, submission:
            ResearchActionRunCompletionSubmission(
                runID: child.runID,
                confirmationToken: child.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                actuallyUsedMaterialNoteIDs: [refreshedAnalysis.noteID],
                summary: "The current Analysis revision was used without changing the Topic.",
                didModifyTarget: false,
                submittedAt: submittedAt
            )
        )
        let afterNewerSynthesis = try await handle.refresh()
        #expect(!afterNewerSynthesis.discovery.catalog.attention.contains {
            $0.kind == .materialChangedSinceUse
        })
        await #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try await handle.research.prepareResynthesis(
                resynthesisRequest,
                context: attentionContext
            )
        }
        #expect(try await handle.documents.load(fixture.topicID).sourceBytes == topicBytes)
        #expect(try Data(contentsOf: portableURL) == portableData)
        await runtime.shutdown()
    }

    @Test("Selected but unused Materials never create synthesis Attention")
    func unusedSynthesisMaterialDoesNotCreateAttention() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: actionNote(topic),
                platformInputs: try ResearchActionPlatformInputs(
                    focalNotes: [actionNote(analysis)]
                )
            )
        )
        let run = try await handle.research.actionRunDetails(id: preparation.runID)
        let submittedAt = Date()
        for invalid in [[UUID()], [analysis.noteID, analysis.noteID]] {
            await #expect(throws: ResearchActionRunContractError.self) {
                _ = try await completeTestActionRun(handle: handle, submission:
                    ResearchActionRunCompletionSubmission(
                        runID: run.runID,
                        confirmationToken: run.snapshot.confirmationToken,
                        recordTitle: try ResearchRecordTitle("Test research result"),
                        actuallyUsedMaterialNoteIDs: invalid,
                        summary: "Invalid actually-used testimony.",
                        didModifyTarget: false,
                        submittedAt: submittedAt
                    )
                )
            }
        }

        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await completeTestActionRun(handle: handle, submission:
                ResearchActionRunCompletionSubmission(
                    runID: run.runID,
                    confirmationToken: run.snapshot.confirmationToken,
                    recordTitle: try ResearchRecordTitle("Test research result"),
                    actuallyUsedMaterialNoteIDs: nil,
                    summary: "The Material-use report was omitted.",
                    didModifyTarget: false,
                    submittedAt: submittedAt
                )
            )
        }

        let completed = try await completeTestActionRun(handle: handle, submission:
            ResearchActionRunCompletionSubmission(
                runID: run.runID,
                confirmationToken: run.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                summary: "The selected Analysis was not used.",
                didModifyTarget: false,
                submittedAt: submittedAt
            )
        )
        #expect(completed.actuallyUsedMaterialNoteIDs == [])
        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(preparation.runID.uuidString.lowercased() + ".json")
        let portable = try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: Data(contentsOf: portableURL)
        )
        #expect(portable.actuallyUsedMaterials.isEmpty)
        #expect(portable.fidelityCompletion == .notRequired)
        try Data("# Analysis\n\nChanged but unused.\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        let refreshed = try await handle.refresh()
        #expect(!refreshed.discovery.catalog.attention.contains {
            $0.kind == .materialChangedSinceUse
        })
        await runtime.shutdown()
    }

    @Test("Unavailable current Action Fidelity remains explicit in its portable record")
    func unavailableActionFidelityIsRecordedAsUnverified() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .checkFidelity,
                target: actionNote(analysis),
                platformInputs: try ResearchActionPlatformInputs(
                    fidelityChecks: [.content]
                )
            )
        )
        let run = try await handle.research.actionRunDetails(id: preparation.runID)
        let receipt = try await submitTestAgentResult(
            for: run,
            handle: handle,
            fidelityOutcomes: [FidelityCheckOutcome(
                check: .content,
                state: .unavailable,
                summary: "The source was unavailable."
            )]
        )
        #expect(receipt.state == .unverified)
        let completion = try #require(
            try await handle.services.localResearchExecutionStore.record(
                id: preparation.runID
            ).completion
        )
        #expect(completion.state == .unverified)
        #expect(completion.actuallyUsedMaterialNoteIDs == [])

        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(preparation.runID.uuidString.lowercased() + ".json")
        let portable = try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: Data(contentsOf: portableURL)
        )
        #expect(portable.fidelityCompletion == .unverified)
        #expect(portable.actuallyUsedMaterials.isEmpty)
        await runtime.shutdown()
    }

    @Test("Completed Fidelity records process completion rather than a pass verdict")
    func completedActionFidelityIncludesIssuesFound() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .checkFidelity,
                target: actionNote(topic),
                platformInputs: try ResearchActionPlatformInputs(
                    fidelityChecks: [.content]
                )
            )
        )
        let run = try await handle.research.actionRunDetails(id: preparation.runID)
        let receipt = try await submitTestAgentResult(
            for: run,
            handle: handle,
            fidelityOutcomes: [FidelityCheckOutcome(
                check: .content,
                state: .issuesFound,
                summary: "One claim remained unsupported.",
                findings: ["The final inference lacks textual support."]
            )]
        )
        #expect(receipt.state == .finalized)

        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(preparation.runID.uuidString.lowercased() + ".json")
        let portable = try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: Data(contentsOf: portableURL)
        )
        #expect(portable.fidelityCompletion == .completed)
        await runtime.shutdown()
    }

    @Test("Multiple used Materials derive independently and disappear on whole Record deletion")
    func multipleUsedMaterialsRespectRecordExistence() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let secondURL = fixture.analysesURL.appendingPathComponent("Second.md")
        try Data("---\ntitle: Second Analysis\n---\n# Second Analysis\n".utf8)
            .write(to: secondURL, options: .atomic)
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        _ = try await handle.refresh()
        let topic = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let first = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let secondID = VaultQualifiedNoteID(
            vaultID: fixture.analysisID.vaultID,
            relativePath: "Second.md"
        )
        let second = try await researchActionTarget(
            secondID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: actionNote(topic),
                platformInputs: try ResearchActionPlatformInputs(
                    focalNotes: [actionNote(first), actionNote(second)]
                )
            )
        )
        let run = try await handle.research.actionRunDetails(id: preparation.runID)
        _ = try await completeTestActionRun(handle: handle, submission:
            ResearchActionRunCompletionSubmission(
                runID: run.runID,
                confirmationToken: run.snapshot.confirmationToken,
                recordTitle: try ResearchRecordTitle("Test research result"),
                actuallyUsedMaterialNoteIDs: [first.noteID, second.noteID],
                summary: "Both Analyses were used.",
                didModifyTarget: false
            )
        )

        try Data("# Analysis\n\nFirst revision changed.\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Analysis.md"),
            options: .atomic
        )
        try Data("# Second Analysis\n\nSecond revision changed.\n".utf8).write(
            to: secondURL,
            options: .atomic
        )
        var refreshed = try await handle.refresh()
        #expect(refreshed.discovery.catalog.attention.filter {
            $0.kind == .materialChangedSinceUse
        }.count == 2)

        try await handle.research.deleteResearchRecordPermanently(
            id: preparation.runID
        )
        refreshed = try await handle.refresh()
        #expect(!refreshed.discovery.catalog.attention.contains {
            $0.kind == .materialChangedSinceUse
        })
        await runtime.shutdown()
    }

    @Test("Action Critique forms one Result Record without a parallel output Note")
    func actionCritiqueUsesCanonicalResult() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let work = try await researchActionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .critique,
                target: actionNote(work)
            )
        )
        #expect(try await handle.snapshot().research.activities.contains {
            $0.runID == action.runID && $0.state == .waitingForAgent
        })
        let run = try await handle.research.actionRunDetails(id: action.runID)
        #expect(run.snapshot.request.target.fingerprint == work.fingerprint)

        let receipt = try await submitTestAgentResult(for: run, handle: handle)
        #expect(receipt.state == .finalized)
        #expect(receipt.recordFormed)

        let portable = try #require(
            try await handle.research.finishedResearchRecords(noteID: work.noteID)
                .first { $0.id == action.runID }
        )
        #expect(portable.action?.actionID == .critique)
        #expect(portable.primaryNoteID == work.noteID)
        #expect(!portable.academicResults.isEmpty)
        #expect(portable.confirmedChanges.isEmpty)
        #expect(portable.fidelityCompletion == .notRequired)
        let completedSnapshot = try await handle.snapshot()
        #expect(completedSnapshot.research.activities.allSatisfy {
            $0.runID != action.runID
        })
        #expect(completedSnapshot.research.resultArrivals.contains {
            $0.recordID == portable.id
        })
        #expect(completedSnapshot.research.noteReviewStates.first {
            $0.noteID == work.noteID
        }?.status == .noAgentChangesToReview)
        #expect(try await handle.snapshot().research.critiques.allSatisfy { critique in
            !critique.rounds.contains { $0.id == action.runID }
        })
        await runtime.shutdown()
    }


    @Test("Action Analyze may omit optional recommendations and still form one Record")
    func actionAnalyzeWithoutRecommendationsFinalizesRecord() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let protectedRun = try await handle.research.actionRunDetails(
            id: action.runID
        )
        #expect(!protectedRun.instructions.contains("## Feedback"))

        let receipt = try await submitTestAgentResult(
            for: protectedRun,
            handle: handle
        )
        #expect(receipt.state == .finalized)
        #expect(receipt.recordFormed)
        let record = try #require(
            try await handle.research.finishedResearchRecords(noteID: nil)
                .first { $0.id == action.runID }
        )
        #expect(record.action?.actionID == .analyze)
        #expect(record.literatureRecommendations.isEmpty)
        await runtime.shutdown()
    }

    @Test("Action Analyze records structured recommendations with safe source provenance")
    func actionAnalyzePortableRecordIncludesRecommendations() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let protectedRun = try await handle.research.actionRunDetails(id: action.runID)
        let source = try #require(protectedRun.snapshot.sourceReference)
        let client = try await connectTestResearchAgent(
            to: protectedRun,
            handle: handle
        )
        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(action.runID.uuidString.lowercased() + ".json")
        let privatePath = fixture.analysisSourceURL.path
        let embeddedPrivatePath = "opaque\(privatePath)"
        let leakingRecommendation = try ResearchLiteratureRecommendationSubmission(
            rawCitation: embeddedPrivatePath,
            title: embeddedPrivatePath,
            authors: [embeddedPrivatePath],
            doi: embeddedPrivatePath,
            sourceLocators: [embeddedPrivatePath],
            reason: embeddedPrivatePath,
            uncertainty: embeddedPrivatePath
        )
        let leakingSubmission = try makeTestAgentResultSubmission(
            for: protectedRun,
            literatureRecommendations: [leakingRecommendation]
        )
        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await submitTestAgentResult(
                leakingSubmission,
                client: client,
                handle: handle
            )
        }
        let rejected = try await handle.services.localResearchExecutionStore.record(
            id: action.runID
        )
        #expect(rejected.resultPayload == nil)
        #expect(rejected.completion == nil)
        #expect(!FileManager.default.fileExists(atPath: portableURL.path))
        let recommendations = [
            try ResearchLiteratureRecommendationSubmission(
                rawCitation: "A. Author, First Work (2020)",
                title: "First Work",
                authors: ["A. Author"],
                year: 2020,
                doi: "10.1000/first",
                sourceLocators: ["p. 42"],
                reason: "The analyzed source treats this work as its principal rival."
            ),
            try ResearchLiteratureRecommendationSubmission(
                rawCitation: "B. Author, Second Work (2021)",
                title: "Second Work",
                authors: ["B. Author"],
                year: 2021,
                zoteroItemKey: "ABCD1234",
                sourceLocators: ["n. 17"],
                reason: "The analyzed source identifies a bounded reply in this work.",
                uncertainty: "The page range was not independently checked."
            ),
        ]
        let submission = try makeTestAgentResultSubmission(
            for: protectedRun,
            literatureRecommendations: recommendations
        )
        let receipt = try await submitTestAgentResult(
            submission,
            client: client,
            handle: handle
        )
        #expect(receipt.state == .finalized)
        #expect(try await submitTestAgentResult(
            submission,
            client: client,
            handle: handle
        ) == receipt)

        let data = try Data(contentsOf: portableURL)
        let portable = try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: data
        )
        #expect(portable.sourceReference == source)
        #expect(portable.literatureRecommendations.count == 2)
        #expect(portable.literatureRecommendations.map(\.id) == [
            ResearchLiteratureRecommendation.stableID(
                runID: action.runID,
                ordinal: 0
            ),
            ResearchLiteratureRecommendation.stableID(
                runID: action.runID,
                ordinal: 1
            ),
        ])
        #expect(portable.literatureRecommendations.allSatisfy {
            $0.disposition.status == .unprocessed
                && $0.disposition.researcherNote == nil
        })
        let encoded = String(decoding: data, as: UTF8.self)
        #expect(!encoded.contains(fixture.analysisSourceURL.path))
        #expect(!encoded.contains("bookmark"))

        let zeroAction = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let zeroRun = try await handle.research.actionRunDetails(
            id: zeroAction.runID
        )
        let zeroReceipt = try await submitTestAgentResult(
            for: zeroRun,
            handle: handle,
            literatureRecommendations: []
        )
        #expect(zeroReceipt.state == .finalized)
        let records = try await handle.research.finishedResearchRecords(noteID: nil)
        #expect(records.count { $0.id == action.runID } == 1)
        #expect(records.count { $0.id == zeroAction.runID } == 1)
        #expect(
            records.first { $0.id == zeroAction.runID }?
                .literatureRecommendations.isEmpty == true
        )

        #expect(try await handle.research.sourceAccess(for: analysis).state == .available)
        try await handle.research.deleteResearchRecordPermanently(id: action.runID)
        #expect(!FileManager.default.fileExists(atPath: portableURL.path))
        do {
            _ = try await submitTestAgentResult(
                submission,
                client: client,
                handle: handle
            )
            Issue.record("A stale Result replay bypassed permanent Record deletion.")
        } catch ResearchActionRunContractError.invalidCompletion(let reason) {
            #expect(reason.contains("permanently deleted"))
        }
        #expect(!FileManager.default.fileExists(atPath: portableURL.path))
        #expect(try await handle.services.localResearchExecutionStore.recordIfPresent(
            id: action.runID
        ) == nil)
        #expect(try await handle.research.sourceAccess(for: analysis).state == .available)
        let afterRetry = try await handle.research.finishedResearchRecords(noteID: nil)
        #expect(afterRetry.allSatisfy { $0.id != action.runID })
        #expect(afterRetry.count { $0.id == zeroAction.runID } == 1)
        await runtime.shutdown()
    }

    @Test("Oversize Analyze recommendations are refused before durable completion")
    func oversizeAnalyzeRecommendationsDoNotStrandCompletion() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchActionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        let protectedRun = try await handle.research.actionRunDetails(
            id: action.runID
        )
        let client = try await connectTestResearchAgent(
            to: protectedRun,
            handle: handle
        )
        let largeReason = String(repeating: "x", count: 60 * 1024)
        let recommendations = try (0..<144).map { ordinal in
            try ResearchLiteratureRecommendationSubmission(
                rawCitation: "Source-grounded lead \(ordinal)",
                reason: largeReason
            )
        }

        let submission = try makeTestAgentResultSubmission(
            for: protectedRun,
            literatureRecommendations: recommendations
        )
        await #expect(throws: ResearchActionRunContractError.self) {
            _ = try await submitTestAgentResult(
                submission,
                client: client,
                handle: handle
            )
        }
        let rejected = try await handle.services.localResearchExecutionStore.record(
            id: action.runID
        )
        #expect(rejected.resultPayload == nil)
        #expect(rejected.completion == nil)
        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(action.runID.uuidString.lowercased() + ".json")
        #expect(!FileManager.default.fileExists(atPath: portableURL.path))

        try await handle.research.cancelActionRun(runID: action.runID)
        await runtime.shutdown()
    }

    @Test("Only Analyze accepts an explicit literature recommendations array")
    func nonAnalyzeRejectsRecommendationArray() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try await researchActionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: actionNote(topic)
            )
        )
        let protectedRun = try await handle.research.actionRunDetails(
            id: action.runID
        )
        let client = try await connectTestResearchAgent(
            to: protectedRun,
            handle: handle
        )
        let submission = try makeTestAgentResultSubmission(
            for: protectedRun,
            literatureRecommendations: []
        )
        await #expect(throws: ResearchAgentResultContractError.self) {
            _ = try await submitTestAgentResult(
                submission,
                client: client,
                handle: handle
            )
        }
        try await handle.research.cancelActionRun(runID: action.runID)
        await runtime.shutdown()
    }

}

private actor ControlledObservationTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var arrived = false

    func wait() async {
        arrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilArrived() async -> Bool {
        if arrived { return true }
        await withCheckedContinuation { arrivalContinuation = $0 }
        return true
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
