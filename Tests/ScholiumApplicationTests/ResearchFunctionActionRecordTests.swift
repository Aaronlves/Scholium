import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

extension ResearchFunctionOperationsTests {
    @Test("Action resolver follows the default matrix and explicit disabled Method state")
    func actionResolverDefaultMatrixAndDisabledMethod() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchFunctionTarget(
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
                parameterValues: [
                    ResearchActionModuleID(rawValue: "researcher-request")!:
                        .text("Clarify the current distinction."),
                ]
            )
        )
        #expect(discuss.instructions.contains("\"feedbackRequirement\" : \"none\""))
        try await handle.research.cancelProtectedFunction(runID: discuss.runID)

        let fidelityRequest = try await actionRequest(
            handle: handle,
            actionID: .checkFidelity,
            target: actionNote(analysis),
            parameterValues: [
                ResearchActionModuleID(rawValue: "fidelity-checks")!:
                    .choices([ResearchActionModuleChoiceValue(rawValue: "content")!]),
            ]
        )
        let fidelity = try await handle.research.prepareAction(fidelityRequest)
        #expect(fidelity.snapshot.authority.readableNotes.map(\.noteID) == [analysis.noteID])
        try await handle.research.cancelProtectedFunction(runID: fidelity.runID)

        let analyze = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .analyze,
                target: actionNote(analysis)
            )
        )
        #expect(analyze.snapshot.parameters.values["source"] != nil)
        #expect(analyze.snapshot.authority.writableNotes.map(\.noteID) == [analysis.noteID])
        try await handle.research.cancelProtectedFunction(runID: analyze.runID)

        let bindings = try #require(
            try await handle.research.workingMethodBindings()
        )
        _ = try await handle.research.disableWorkingMethod(
            for: .analyze,
            expectedBindingRevision: bindings.revision
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

    @Test("A custom Action button resolves one Skill and freezes a reproducible snapshot")
    func customActionResolutionAndPreparation() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let actionID = ResearchActionID(researcherOwnedRawValue: "socratic-pressure")!
        let package = try await handle.research.createSkill(
            id: "socratic-pressure",
            source: customActionSkillSource(actionID: actionID)
        )
        let binding = try customActionProfileBinding(
            actionID: actionID,
            packageID: package.id,
            moduleID: "question",
            buttonName: "Socratic Pressure",
            feedbackRequirement: .required
        )
        _ = try await handle.research.saveActionProfile(
            binding,
            expectedDocumentRevision: nil
        )
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )

        let topicActions = try await handle.research.availableActions(
            for: actionNote(topic)
        )
        let custom = try #require(topicActions.first { $0.id == actionID })
        #expect(custom.buttonName == "Socratic Pressure")
        #expect(custom.group == .researcherSkill)
        #expect(custom.isEnabled)
        #expect(!(try await handle.research.availableActions(for: actionNote(work)))
            .contains { $0.id == actionID })

        let questionID = ResearchActionModuleID(rawValue: "question")!
        let request = try await actionRequest(
            handle: handle,
            actionID: actionID,
            target: actionNote(topic),
            parameterValues: [
                questionID: .text("What remains after the strongest reply?"),
            ]
        )
        let first = try await handle.research.prepareAction(request)
        _ = try await handle.research.finishDiscussion(discussionID: first.runID)
        let second = try await handle.research.prepareAction(request)
        #expect(first.snapshot == second.snapshot)
        #expect(first.snapshot.actionID == actionID)
        #expect(first.snapshot.method.packageID == package.id)
        let expectedProfileRevision = try binding.profile.contentRevision()
        #expect(first.snapshot.resolvedProfile.profileRevision
            == expectedProfileRevision)
        #expect(first.snapshot.authority.readableNotes.map(\.noteID) == [topic.noteID])
        #expect(first.snapshot.authority.writableNotes.isEmpty)
        #expect(first.instructions.contains("\"action\" : \"socratic-pressure\""))
        #expect(first.instructions.contains("\"feedbackRequirement\" : \"required\""))
        #expect(first.instructions.contains("What remains after the strongest reply?"))
        #expect(first.instructions.contains("scholium-discussion-protocol"))
        try await handle.research.cancelProtectedFunction(runID: first.runID)
        _ = try await handle.research.finishDiscussion(discussionID: second.runID)
        try await handle.research.cancelProtectedFunction(runID: second.runID)
        await runtime.shutdown()
    }

    @Test("A stale Action Profile presentation cannot authorize preparation")
    func staleActionProfileCannotReplay() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let actionID = ResearchActionID(researcherOwnedRawValue: "profile-race")!
        let package = try await handle.research.createSkill(
            id: "profile-race",
            source: customActionSkillSource(actionID: actionID)
        )
        let firstBinding = try customActionProfileBinding(
            actionID: actionID,
            packageID: package.id,
            moduleID: "question",
            buttonName: "Profile Race"
        )
        let firstDocument = try await handle.research.saveActionProfile(
            firstBinding,
            expectedDocumentRevision: nil
        )
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let staleRequest = try await actionRequest(
            handle: handle,
            actionID: actionID,
            target: actionNote(topic),
            parameterValues: [
                ResearchActionModuleID(rawValue: "question")!: .text("Old input"),
            ]
        )
        let replacement = try customActionProfileBinding(
            actionID: actionID,
            packageID: package.id,
            moduleID: "question",
            buttonName: "Profile Race",
            readableRoles: [.topic, .analysis]
        )
        _ = try await handle.research.saveActionProfile(
            replacement,
            expectedDocumentRevision: firstDocument.revision
        )

        await #expect(throws: ResearchActionExecutionContractError.self) {
            _ = try await handle.research.prepareAction(staleRequest)
        }
        await runtime.shutdown()
    }

    @Test("An Action sheet cannot replay after its execution kind changes")
    func staleActionExecutionKindCannotReplay() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )

        await #expect(throws: ResearchActionExecutionContractError.staleResolution) {
            _ = try await handle.research.prepareAction(
                try await actionRequest(
                    handle: handle,
                    actionID: .synthesize,
                    expectedExecutionKind: .discussion,
                    target: actionNote(topic)
                )
            )
        }
        #expect(try await handle.research.checkpoints().checkpoints.isEmpty)
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
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(analysis),
                parameterValues: [
                    ResearchActionModuleID(rawValue: "researcher-request")!:
                        .text("Clarify the distinction."),
                ]
            )
        )
        let protectedRun = try await handle.research.protectedFunctionRun(id: preparation.runID)
        _ = try await handle.research.appendDiscussionStatement(
            discussionID: preparation.runID,
            author: .agent,
            attribution: "Research Agent",
            text: "The distinction remains bounded to the current Analysis."
        )
        _ = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: protectedRun.snapshot.confirmationToken,
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
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .discuss,
                target: actionNote(analysis),
                parameterValues: [
                    ResearchActionModuleID(rawValue: "researcher-request")!:
                        .text("Clarify the frozen Action boundary."),
                ]
            )
        )
        let protectedRun = try await handle.research.protectedFunctionRun(id: preparation.runID)
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

        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeProtectedFunction(
                ResearchFunctionCompletionSubmission(
                    runID: preparation.runID,
                    confirmationToken: protectedRun.snapshot.confirmationToken,
                    finalTargetFingerprint: analysis.fingerprint,
                    summary: "A mismatched record must not complete the run.",
                    didModifyTarget: false
                )
            )
        }
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.finishProtectedDiscussion(runID: preparation.runID)
        }
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.finishDiscussion(
                discussionID: preparation.runID
            )
        }
        #expect(FileManager.default.fileExists(atPath: activeURL.path))
        await runtime.shutdown()
    }


    @Test("Action runs use Local Execution v3 and emit one whitelisted portable record")
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
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let materialsModuleID = try #require(
            ResearchActionModuleID(rawValue: "materials")
        )
        let action = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: actionNote(topic),
                parameterValues: [
                    materialsModuleID: .notes([actionNote(analysis)]),
                ]
            )
        )
        let protectedRun = try await handle.research.protectedFunctionRun(id: action.runID)
        #expect(action.instructions.contains("actuallyUsedMaterialNoteIDs is required"))
        #expect(action.instructions.contains("\"actuallyUsedMaterialNoteIDs\" : ["))
        // Keep the original and resynthesis completions on the same timestamp
        // to prove lineage wins the tie, while keeping that timestamp after
        // both preparations so each portable record remains temporally valid.
        let submittedAt = Date().addingTimeInterval(60)
        let activity = try researchActivityCompletion(
            for: protectedRun,
            candidateModifiedNotes: [topic.note],
            summary: "No Topic change was warranted by the selected information.",
            submittedAt: submittedAt
        )
        await #expect(throws: PortableResearchRecordError.self) {
            _ = try await handle.research.completeProtectedFunction(
                ResearchFunctionCompletionSubmission(
                    runID: protectedRun.runID,
                    confirmationToken: protectedRun.snapshot.confirmationToken,
                    actuallyUsedMaterialNoteIDs: [analysis.noteID],
                    summary: "I read /Users/researcher/private/source.pdf.",
                    didModifyTarget: false,
                    activityCompletion: activity,
                    submittedAt: submittedAt
                )
            )
        }
        let submission = ResearchFunctionCompletionSubmission(
            runID: protectedRun.runID,
            confirmationToken: protectedRun.snapshot.confirmationToken,
            actuallyUsedMaterialNoteIDs: [analysis.noteID],
            summary: "No Topic change was warranted by the selected information.",
            didModifyTarget: false,
            activityCompletion: activity,
            submittedAt: submittedAt
        )
        let completed: ResearchFunctionCompletion
        do {
            completed = try await handle.research.completeProtectedFunction(submission)
        } catch {
            Issue.record("Valid Action completion failed before record inspection: \(error)")
            throw error
        }
        #expect(completed.state == .complete)
        #expect(completed.actuallyUsedMaterialNoteIDs == [analysis.noteID])
        let repeated: ResearchFunctionCompletion
        do {
            repeated = try await handle.research.completeProtectedFunction(submission)
        } catch {
            Issue.record("Idempotent Action completion failed: \(error)")
            throw error
        }
        #expect(repeated == completed)
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeProtectedFunction(
                ResearchFunctionCompletionSubmission(
                    runID: protectedRun.runID,
                    confirmationToken: protectedRun.snapshot.confirmationToken,
                    actuallyUsedMaterialNoteIDs: [analysis.noteID],
                    summary: "No Topic change was warranted by the selected information.",
                    didModifyTarget: false,
                    activityCompletion: activity,
                    submittedAt: submittedAt.addingTimeInterval(0.000_1)
                )
            )
        }

        let localURL = triptychSupport
            .appendingPathComponent("research-execution-v3", isDirectory: true)
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
        #expect(portable.actuallyUsedMaterials == [try PortableResearchMaterialUse(
            noteID: analysis.noteID,
            note: analysis.note,
            role: .analysis,
            title: analysis.title,
            revision: analysis.fingerprint
        )])
        #expect(portable.confirmedChanges.isEmpty)
        #expect(portable.discrepancies == [PortableResearchDiscrepancy(
            id: PortableResearchDiscrepancy.stableID(
                runID: action.runID,
                noteID: topic.noteID,
                kind: .reportedButUnmodified
            ),
            noteID: topic.noteID,
            kind: .reportedButUnmodified
        )])
        let localSource = String(decoding: localData, as: UTF8.self)
        let portableSource = String(decoding: portableData, as: UTF8.self)
        #expect(localSource.contains("prepared_instructions"))
        #expect(!localSource.contains(activity.activityKey))
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
        let refreshedTopic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let refreshedAnalysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let resynthesisRequest = try await actionRequest(
            handle: handle,
            actionID: .synthesize,
            target: actionNote(refreshedTopic),
            parameterValues: [
                materialsModuleID: .notes([actionNote(refreshedAnalysis)]),
            ]
        )
        let resynthesis = try await handle.research.prepareResynthesis(
            resynthesisRequest,
            context: attentionContext
        )
        let child = try await handle.research.protectedFunctionRun(id: resynthesis.runID)
        #expect(child.snapshot.continuationLineage?.kind == .resynthesis)
        #expect(child.snapshot.continuationLineage?.parentRunID == portable.id)
        #expect(child.snapshot.continuationLineage?.requestID == resynthesis.runID)
        #expect(child.snapshot.resynthesisContext == attentionContext)
        #expect(child.snapshot.checkpointID != nil)
        #expect(child.snapshot.actionSnapshot?.authority.writableNotes.map(\.noteID)
            == [topic.noteID])

        let rebuilt = try await handle.refresh()
        #expect(rebuilt.discovery.catalog.attention.first {
            $0.kind == .materialChangedSinceUse
        }?.id == attention.id)
        #expect(try await handle.documents.load(fixture.topicID).sourceBytes == topicBytes)
        #expect(try Data(contentsOf: portableURL) == portableData)

        let resynthesisActivity = try researchActivityCompletion(
            for: child,
            candidateModifiedNotes: [refreshedTopic.note],
            summary: "The current Analysis revision was used without changing the Topic.",
            submittedAt: submittedAt
        )
        _ = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: child.runID,
                confirmationToken: child.snapshot.confirmationToken,
                actuallyUsedMaterialNoteIDs: [refreshedAnalysis.noteID],
                summary: "The current Analysis revision was used without changing the Topic.",
                didModifyTarget: false,
                activityCompletion: resynthesisActivity,
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
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let materialsModuleID = try #require(
            ResearchActionModuleID(rawValue: "materials")
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: actionNote(topic),
                parameterValues: [
                    materialsModuleID: .notes([actionNote(analysis)]),
                ]
            )
        )
        let run = try await handle.research.protectedFunctionRun(id: preparation.runID)
        let submittedAt = Date()
        let activity = try researchActivityCompletion(
            for: run,
            candidateModifiedNotes: [topic.note],
            summary: "The selected Analysis was not used.",
            submittedAt: submittedAt
        )

        for invalid in [[UUID()], [analysis.noteID, analysis.noteID]] {
            await #expect(throws: ResearchFunctionContractError.self) {
                _ = try await handle.research.completeProtectedFunction(
                    ResearchFunctionCompletionSubmission(
                        runID: run.runID,
                        confirmationToken: run.snapshot.confirmationToken,
                        actuallyUsedMaterialNoteIDs: invalid,
                        summary: "Invalid actually-used testimony.",
                        didModifyTarget: false,
                        activityCompletion: activity,
                        submittedAt: submittedAt
                    )
                )
            }
        }

        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeProtectedFunction(
                ResearchFunctionCompletionSubmission(
                    runID: run.runID,
                    confirmationToken: run.snapshot.confirmationToken,
                    actuallyUsedMaterialNoteIDs: nil,
                    summary: "The Material-use report was omitted.",
                    didModifyTarget: false,
                    activityCompletion: activity,
                    submittedAt: submittedAt
                )
            )
        }

        let completed = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: run.runID,
                confirmationToken: run.snapshot.confirmationToken,
                summary: "The selected Analysis was not used.",
                didModifyTarget: false,
                activityCompletion: activity,
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
        let analysis = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .checkFidelity,
                target: actionNote(analysis),
                parameterValues: [
                    ResearchActionModuleID(rawValue: "fidelity-checks")!:
                        .choices([ResearchActionModuleChoiceValue(rawValue: "content")!]),
                ]
            )
        )
        let run = try await handle.research.protectedFunctionRun(id: preparation.runID)
        let completion = try await handle.research.completeAction(
            ResearchActionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: run.snapshot.confirmationToken,
                finalTargetFingerprint: analysis.fingerprint,
                actuallyUsedMaterialNoteIDs: [],
                summary: "The exact recorded revision could not be checked.",
                didModifyTarget: false,
                fidelityOutcomes: [FidelityCheckOutcome(
                    check: .content,
                    state: .unavailable,
                    summary: "The source was unavailable."
                )]
            )
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
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .checkFidelity,
                target: actionNote(topic),
                parameterValues: [
                    ResearchActionModuleID(rawValue: "fidelity-checks")!:
                        .choices([ResearchActionModuleChoiceValue(rawValue: "content")!]),
                ]
            )
        )
        let run = try await handle.research.protectedFunctionRun(id: preparation.runID)
        let completion = try await handle.research.completeAction(
            ResearchActionCompletionSubmission(
                runID: preparation.runID,
                confirmationToken: run.snapshot.confirmationToken,
                finalTargetFingerprint: topic.fingerprint,
                actuallyUsedMaterialNoteIDs: [],
                summary: "The exact revision was checked and one issue was retained.",
                didModifyTarget: false,
                fidelityOutcomes: [FidelityCheckOutcome(
                    check: .content,
                    state: .issuesFound,
                    summary: "One claim remained unsupported.",
                    findings: ["The final inference lacks textual support."]
                )]
            )
        )
        #expect(completion.state == .complete)

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

    @Test("Multiple used Materials derive independently and disappear on tombstone or record deletion")
    func multipleUsedMaterialsRespectLifecycleAndRecordExistence() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let secondURL = fixture.analysesURL.appendingPathComponent("Second.md")
        try Data("---\ntitle: Second Analysis\n---\n# Second Analysis\n".utf8)
            .write(to: secondURL, options: .atomic)
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        _ = try await handle.refresh()
        let topic = try await researchFunctionTarget(
            fixture.topicID,
            role: .topic,
            handle: handle
        )
        let first = try await researchFunctionTarget(
            fixture.analysisID,
            role: .analysis,
            handle: handle
        )
        let secondID = VaultQualifiedNoteID(
            vaultID: fixture.analysisID.vaultID,
            relativePath: "Second.md"
        )
        let second = try await researchFunctionTarget(
            secondID,
            role: .analysis,
            handle: handle
        )
        let materialsModuleID = try #require(
            ResearchActionModuleID(rawValue: "materials")
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .synthesize,
                target: actionNote(topic),
                parameterValues: [
                    materialsModuleID: .notes([
                        actionNote(first), actionNote(second),
                    ]),
                ]
            )
        )
        let run = try await handle.research.protectedFunctionRun(id: preparation.runID)
        let activity = try researchActivityCompletion(
            for: run,
            candidateModifiedNotes: [topic.note],
            summary: "Both Analyses were used."
        )
        _ = try await handle.research.completeProtectedFunction(
            ResearchFunctionCompletionSubmission(
                runID: run.runID,
                confirmationToken: run.snapshot.confirmationToken,
                actuallyUsedMaterialNoteIDs: [first.noteID, second.noteID],
                summary: "Both Analyses were used.",
                didModifyTarget: false,
                activityCompletion: activity
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

        let currentSecond = try await handle.documents.load(secondID)
        let movedSecond = try await handle.documents.move(
            secondID,
            to: "Trash/Second.md",
            expectedRevision: currentSecond.fingerprint
        ).committedValue
        let trashedSecond = try await handle.documents.load(movedSecond.destination)
        _ = try await handle.documents.deletePermanently(
            movedSecond.destination,
            expectedRevision: trashedSecond.fingerprint
        )
        refreshed = try await handle.refresh()
        let surviving = refreshed.discovery.catalog.attention.filter {
            $0.kind == .materialChangedSinceUse
        }
        #expect(surviving.count == 1)
        #expect(surviving.first?.materialChangedSinceUse?.materialNoteID == first.noteID)
        let tombstonedRecord = try #require(
            try await handle.research.finishedResearchRecords(noteID: nil)
                .first { $0.id == preparation.runID }
        )
        #expect(tombstonedRecord.participatingNotes.contains {
            $0.noteID == second.noteID && $0.isTombstone
        })
        #expect(tombstonedRecord.actuallyUsedMaterials.contains {
            $0.noteID == second.noteID
        })

        try await handle.research.deleteResearchRecordPermanently(
            id: preparation.runID
        )
        refreshed = try await handle.refresh()
        #expect(!refreshed.discovery.catalog.attention.contains {
            $0.kind == .materialChangedSinceUse
        })
        await runtime.shutdown()
    }

    @Test("Action Critique records its separate modified output Note")
    func actionCritiquePortableRecordIncludesOutput() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let work = try await researchFunctionTarget(
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
        let protectedRun = try await handle.research.protectedFunctionRun(id: action.runID)
        let output = try #require(protectedRun.snapshot.preparedOutput)
        let original = try await handle.documents.load(output.note)
        let saved = try await handle.documents.save(
            output.note,
            changeSet: .exactContent(
                original.rawContent
                    + "\n## Specific Findings\n\n"
                    + "### Untraced: The central inference needs one explicit premise\n"
                    + "Target Line: 1\n"
            ),
            expectedRevision: original.fingerprint
        ).committedValue

        let submission = ResearchFunctionCompletionSubmission(
            runID: protectedRun.runID,
            confirmationToken: protectedRun.snapshot.confirmationToken,
            finalTargetFingerprint: work.fingerprint,
            summary: "Recorded one bounded Critique finding.",
            didModifyTarget: false,
            outputFingerprint: saved.document.fingerprint
        )
        let completion = try await handle.research.completeProtectedFunction(submission)
        #expect(completion.state == .complete)
        await runtime.shutdown()

        // Simulate a process failure after Local completion persistence but
        // before the Critique association captured its findings.
        let registryURL = fixture.rootURL
            .appendingPathComponent(".scholium/critiques.json")
        var registry = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: registryURL))
                as? [String: Any]
        )
        var associations = try #require(registry["associations"] as? [Any])
        let associationIndex = try #require(associations.firstIndex {
            guard let value = $0 as? [String: Any],
                  let rounds = value["rounds"] as? [[String: Any]] else {
                return false
            }
            return rounds.contains {
                ($0["id"] as? String)?.lowercased()
                    == action.runID.uuidString.lowercased()
            }
        })
        var association = try #require(
            associations[associationIndex] as? [String: Any]
        )
        var rounds = try #require(association["rounds"] as? [[String: Any]])
        let roundIndex = try #require(rounds.firstIndex {
            ($0["id"] as? String)?.lowercased()
                == action.runID.uuidString.lowercased()
        })
        rounds[roundIndex]["actionableFindings"] = []
        rounds[roundIndex].removeValue(forKey: "localExecutionFindingsCaptured")
        association["rounds"] = rounds
        associations[associationIndex] = association
        registry["associations"] = associations
        try JSONSerialization.data(
            withJSONObject: registry,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: registryURL, options: .atomic)

        let reopenedRuntime = fixture.runtime()
        let reopened = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
        #expect(try await reopened.research.completeProtectedFunction(submission) == completion)
        let repairedRegistry = String(
            decoding: try Data(contentsOf: registryURL),
            as: UTF8.self
        )
        #expect(repairedRegistry.contains(
            "The central inference needs one explicit premise"
        ))
        let laterOutput = try await reopened.documents.load(output.note)
        _ = try await reopened.documents.save(
            output.note,
            changeSet: .exactContent(
                laterOutput.rawContent + "\nA later researcher edit.\n"
            ),
            expectedRevision: laterOutput.fingerprint
        )
        try FileManager.default.removeItem(
            at: fixture.rootURL
                .appendingPathComponent("Works", isDirectory: true)
                .appendingPathComponent(output.note.relativePath)
        )
        #expect(try await reopened.research.completeProtectedFunction(submission) == completion)

        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(action.runID.uuidString.lowercased() + ".json")
        let portable = try JSONDecoder.scholium.decode(
            PortableResearchRecord.self,
            from: Data(contentsOf: portableURL)
        )
        let outputParticipant = try #require(portable.participatingNotes.first {
            $0.note == output.note
        })
        #expect(outputParticipant.startingRevision == output.fingerprint)
        #expect(outputParticipant.endingRevision == saved.document.fingerprint)
        #expect(portable.confirmedChanges == [try PortableResearchConfirmedChange(
            noteID: outputParticipant.noteID,
            startingRevision: output.fingerprint,
            endingRevision: saved.document.fingerprint
        )])
        #expect(portable.fidelityCompletion == .notRequired)
        await reopenedRuntime.shutdown()
    }

    @Test("A crashed Critique handoff reconciles Local-v3 as the sole execution authority")
    func actionCritiqueHandoffRecoversAfterRestart() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .critique,
                target: actionNote(work)
            )
        )
        let localURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v3", isDirectory: true)
            .appendingPathComponent(preparation.runID.uuidString.lowercased() + ".json")
        let localDecoder = JSONDecoder()
        localDecoder.dateDecodingStrategy = .deferredToDate
        let local = try localDecoder.decode(
            LocalExecutionTestProjection.self,
            from: Data(contentsOf: localURL)
        )
        let registryURL = fixture.rootURL
            .appendingPathComponent(".scholium/critiques.json")
        var registry = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: registryURL))
                as? [String: Any]
        )
        var associations = try #require(registry["associations"] as? [Any])
        let associationIndex = try #require(associations.firstIndex {
            guard let value = $0 as? [String: Any],
                  let rounds = value["rounds"] as? [[String: Any]] else {
                return false
            }
            return rounds.contains {
                ($0["id"] as? String)?.lowercased()
                    == preparation.runID.uuidString.lowercased()
            }
        })
        var association = try #require(
            associations[associationIndex] as? [String: Any]
        )
        var rounds = try #require(association["rounds"] as? [[String: Any]])
        let roundIndex = try #require(rounds.firstIndex {
            ($0["id"] as? String)?.lowercased()
                == preparation.runID.uuidString.lowercased()
        })
        let registryEncoder = JSONEncoder()
        registryEncoder.dateEncodingStrategy = .iso8601
        rounds[roundIndex]["functionSnapshot"] = try JSONSerialization.jsonObject(
            with: registryEncoder.encode(local.snapshot)
        )
        rounds[roundIndex]["functionInstructions"] = local.preparedInstructions
        association["rounds"] = rounds
        associations[associationIndex] = association
        registry["associations"] = associations
        try JSONSerialization.data(
            withJSONObject: registry,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: registryURL, options: .atomic)
        await runtime.shutdown()

        let reopenedRuntime = fixture.runtime()
        let reopened = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
        let firstReopenedSnapshot = try await reopened.snapshot()
        #expect(try await reopened.services.localResearchExecutionStore.listing().records.count {
            $0.id == preparation.runID
        } == 1)
        let projectedRound = try #require(
            firstReopenedSnapshot.research.critiques
                .flatMap(\.rounds)
                .first { $0.id == preparation.runID }
        )
        #expect(projectedRound.functionSnapshot == nil)
        #expect(projectedRound.functionInstructions == nil)
        let recovered = try await reopened.research.protectedFunctionRun(id: preparation.runID)
        #expect(recovered.snapshot == local.snapshot)
        let repairedSource = String(
            decoding: try Data(contentsOf: registryURL),
            as: UTF8.self
        )
        #expect(!repairedSource.contains("\"functionSnapshot\""))
        #expect(!repairedSource.contains("\"functionInstructions\""))
        try await reopened.research.cancelProtectedFunction(runID: preparation.runID)
        await reopenedRuntime.shutdown()
    }

    @Test("A pre-Local Critique handoff installs the exact staged run after restart")
    func actionCritiquePreLocalHandoffIsInstalledAfterRestart() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let work = try await researchFunctionTarget(
            fixture.workID,
            role: .work,
            handle: handle
        )
        let preparation = try await handle.research.prepareAction(
            try await actionRequest(
                handle: handle,
                actionID: .critique,
                target: actionNote(work)
            )
        )
        let localURL = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(fixture.assignment.id.uuidString, isDirectory: true)
            .appendingPathComponent("research-execution-v3", isDirectory: true)
            .appendingPathComponent(preparation.runID.uuidString.lowercased() + ".json")
        let localDecoder = JSONDecoder()
        localDecoder.dateDecodingStrategy = .deferredToDate
        let local = try localDecoder.decode(
            LocalExecutionTestProjection.self,
            from: Data(contentsOf: localURL)
        )
        #expect(local.snapshot.checkpointID == nil)

        let registryURL = fixture.rootURL
            .appendingPathComponent(".scholium/critiques.json")
        var registry = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: registryURL))
                as? [String: Any]
        )
        var associations = try #require(registry["associations"] as? [Any])
        let associationIndex = try #require(associations.firstIndex {
            guard let value = $0 as? [String: Any],
                  let rounds = value["rounds"] as? [[String: Any]] else {
                return false
            }
            return rounds.contains {
                ($0["id"] as? String)?.lowercased()
                    == preparation.runID.uuidString.lowercased()
            }
        })
        var association = try #require(
            associations[associationIndex] as? [String: Any]
        )
        var rounds = try #require(association["rounds"] as? [[String: Any]])
        let roundIndex = try #require(rounds.firstIndex {
            ($0["id"] as? String)?.lowercased()
                == preparation.runID.uuidString.lowercased()
        })
        let registryEncoder = JSONEncoder()
        registryEncoder.dateEncodingStrategy = .iso8601
        rounds[roundIndex]["functionSnapshot"] = try JSONSerialization.jsonObject(
            with: registryEncoder.encode(local.snapshot)
        )
        rounds[roundIndex]["functionInstructions"] = local.preparedInstructions
        association["rounds"] = rounds
        associations[associationIndex] = association
        registry["associations"] = associations
        let stagedRegistryData = try JSONSerialization.data(
            withJSONObject: registry,
            options: [.prettyPrinted, .sortedKeys]
        )
        try stagedRegistryData.write(to: registryURL, options: .atomic)
        try FileManager.default.removeItem(at: localURL)
        let sourceMachineExecutionStore = await handle.services
            .localResearchExecutionStore
        try await sourceMachineExecutionStore.stageCritiqueHandoff(
            snapshot: local.snapshot,
            preparedInstructions: local.preparedInstructions
        )
        await runtime.shutdown()

        // A different Mac sees the portable staging through sync but does not
        // possess the machine-local intent. It must preserve the staging
        // and refuse to manufacture an executable run on that machine.
        let remoteApplicationSupport = fixture.rootURL.appendingPathComponent(
            "Remote Application Support",
            isDirectory: true
        )
        let remoteRuntime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: remoteApplicationSupport,
            assignments: [fixture.assignment]
        )))
        let remote = try await remoteRuntime.openWorkspace(id: fixture.assignment.id)
        let remoteSnapshot = try await remote.snapshot()
        let remoteRound = try #require(
            remoteSnapshot.research.critiques
                .flatMap(\.rounds)
                .first { $0.id == preparation.runID }
        )
        #expect(remoteRound.functionSnapshot == local.snapshot)
        #expect(try await remote.services.localResearchExecutionStore.listing().records.allSatisfy {
            $0.id != preparation.runID
        })
        #expect(remoteSnapshot.research.healthIssues.contains {
            $0.contains("no matching machine-local intent")
        })
        await remoteRuntime.shutdown()

        // Even on the source machine, externally changed portable prose is
        // testimony to preserve, not authority from which Scholium may
        // manufacture Local execution state.
        rounds[roundIndex]["functionInstructions"] = local.preparedInstructions
            + "\nExternally changed instructions."
        association["rounds"] = rounds
        associations[associationIndex] = association
        registry["associations"] = associations
        try JSONSerialization.data(
            withJSONObject: registry,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: registryURL, options: .atomic)
        let inconsistentRuntime = fixture.runtime()
        let inconsistent = try await inconsistentRuntime.openWorkspace(
            id: fixture.assignment.id
        )
        let inconsistentSnapshot = try await inconsistent.snapshot()
        #expect(try await inconsistent.services.localResearchExecutionStore.listing().records.allSatisfy {
            $0.id != preparation.runID
        })
        #expect(inconsistentSnapshot.research.healthIssues.contains {
            $0.contains("no matching machine-local intent")
        })
        #expect(!FileManager.default.fileExists(atPath: localURL.path))
        await inconsistentRuntime.shutdown()
        try stagedRegistryData.write(to: registryURL, options: .atomic)

        let reopenedRuntime = fixture.runtime()
        let reopened = try await reopenedRuntime.openWorkspace(id: fixture.assignment.id)
        let reopenedSnapshot = try await reopened.snapshot()
        let projectedRound = try #require(
            reopenedSnapshot.research.critiques
                .flatMap(\.rounds)
                .first { $0.id == preparation.runID }
        )
        #expect(projectedRound.functionSnapshot == nil)
        #expect(projectedRound.functionInstructions == nil)
        #expect(try await reopened.services.localResearchExecutionStore.listing().records.count {
            $0.id == preparation.runID
        } == 1)
        let recovered = try await reopened.research.protectedFunctionRun(id: preparation.runID)
        #expect(recovered.snapshot == local.snapshot)
        #expect(recovered.instructions == local.preparedInstructions)
        try await reopened.research.cancelProtectedFunction(runID: preparation.runID)
        await reopenedRuntime.shutdown()
    }

    @Test("Action Analyze records structured recommendations with safe source provenance")
    func actionAnalyzePortableRecordIncludesRecommendations() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let analysis = try await researchFunctionTarget(
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
        let protectedRun = try await handle.research.protectedFunctionRun(id: action.runID)
        let source = try #require(protectedRun.snapshot.sourceReference)
        let submittedAt = Date()
        let writeCompletion = try actionWriteCompletion(
            for: action,
            summary: "The source supports no warranted Analysis change.",
            submittedAt: submittedAt
        )
        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(action.runID.uuidString.lowercased() + ".json")
        let missingRecommendations = ResearchActionCompletionSubmission(
            runID: protectedRun.runID,
            confirmationToken: protectedRun.snapshot.confirmationToken,
            summary: "The source supports no warranted Analysis change.",
            didModifyTarget: false,
            writeCompletion: writeCompletion,
            submittedAt: submittedAt
        )
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeAction(missingRecommendations)
        }
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
        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeAction(
                ResearchActionCompletionSubmission(
                    runID: protectedRun.runID,
                    confirmationToken: protectedRun.snapshot.confirmationToken,
                    summary: "The source supports no warranted Analysis change.",
                    didModifyTarget: false,
                    writeCompletion: writeCompletion,
                    literatureRecommendations: [leakingRecommendation],
                    submittedAt: submittedAt
                )
            )
        }
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: action.runID
        ).completion == nil)
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
        let submission = ResearchActionCompletionSubmission(
            runID: protectedRun.runID,
            confirmationToken: protectedRun.snapshot.confirmationToken,
            summary: "The source supports no warranted Analysis change.",
            didModifyTarget: false,
            writeCompletion: writeCompletion,
            literatureRecommendations: recommendations,
            submittedAt: submittedAt
        )
        let completion = try await handle.research.completeAction(submission)
        #expect(completion.literatureRecommendationCount == 2)
        #expect(try await handle.research.completeAction(submission) == completion)

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
        let zeroRun = try await handle.research.protectedFunctionRun(
            id: zeroAction.runID
        )
        let zeroSubmittedAt = Date().addingTimeInterval(1)
        let zeroWriteCompletion = try actionWriteCompletion(
            for: zeroAction,
            summary: "No additional reading leads were warranted.",
            submittedAt: zeroSubmittedAt
        )
        let zeroCompletion = try await handle.research.completeAction(
            ResearchActionCompletionSubmission(
                runID: zeroRun.runID,
                confirmationToken: zeroRun.snapshot.confirmationToken,
                summary: "No additional reading leads were warranted.",
                didModifyTarget: false,
                writeCompletion: zeroWriteCompletion,
                literatureRecommendations: [],
                submittedAt: zeroSubmittedAt
            )
        )
        #expect(zeroCompletion.literatureRecommendationCount == 0)
        let records = try await handle.research.finishedResearchRecords(noteID: nil)
        #expect(records.count { $0.id == action.runID } == 1)
        #expect(records.count { $0.id == zeroAction.runID } == 1)
        #expect(
            records.first { $0.id == zeroAction.runID }?
                .literatureRecommendations.isEmpty == true
        )

        let retainedLocalCompletion = try #require(
            try await handle.services.localResearchExecutionStore.record(
                id: action.runID
            ).completion
        )
        #expect(try await handle.research.sourceAccess(for: analysis).state == .available)
        try await handle.research.deleteResearchRecordPermanently(id: action.runID)
        #expect(!FileManager.default.fileExists(atPath: portableURL.path))
        do {
            _ = try await handle.research.completeAction(submission)
            Issue.record("A stale completion replay bypassed permanent Record deletion.")
        } catch ResearchFunctionContractError.invalidCompletion(let reason) {
            #expect(reason.contains("permanently deleted"))
        }
        #expect(!FileManager.default.fileExists(atPath: portableURL.path))
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: action.runID
        ).completion == retainedLocalCompletion)
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
        let analysis = try await researchFunctionTarget(
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
        let protectedRun = try await handle.research.protectedFunctionRun(
            id: action.runID
        )
        let submittedAt = Date()
        let writeCompletion = try actionWriteCompletion(
            for: action,
            summary: "The source supports no warranted Analysis change.",
            submittedAt: submittedAt
        )
        let largeReason = String(repeating: "x", count: 60 * 1024)
        let recommendations = try (0..<144).map { ordinal in
            try ResearchLiteratureRecommendationSubmission(
                rawCitation: "Source-grounded lead \(ordinal)",
                reason: largeReason
            )
        }

        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeAction(
                ResearchActionCompletionSubmission(
                    runID: protectedRun.runID,
                    confirmationToken: protectedRun.snapshot.confirmationToken,
                    summary: "The source supports no warranted Analysis change.",
                    didModifyTarget: false,
                    writeCompletion: writeCompletion,
                    literatureRecommendations: recommendations,
                    submittedAt: submittedAt
                )
            )
        }
        #expect(try await handle.services.localResearchExecutionStore.record(
            id: action.runID
        ).completion == nil)
        let portableURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(action.runID.uuidString.lowercased() + ".json")
        #expect(!FileManager.default.fileExists(atPath: portableURL.path))

        try await handle.research.cancelProtectedFunction(runID: action.runID)
        await runtime.shutdown()
    }

    @Test("Only Analyze accepts an explicit literature recommendations array")
    func nonAnalyzeRejectsRecommendationArray() async throws {
        let fixture = try await ResearchFixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topic = try await researchFunctionTarget(
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
        let protectedRun = try await handle.research.protectedFunctionRun(
            id: action.runID
        )
        let writeCompletion = try actionWriteCompletion(
            for: action,
            summary: "No synthesis was warranted."
        )

        await #expect(throws: ResearchFunctionContractError.self) {
            _ = try await handle.research.completeAction(
                ResearchActionCompletionSubmission(
                    runID: action.runID,
                    confirmationToken: protectedRun.snapshot.confirmationToken,
                    summary: "No synthesis was warranted.",
                    didModifyTarget: false,
                    writeCompletion: writeCompletion,
                    literatureRecommendations: []
                )
            )
        }
        try await handle.research.cancelProtectedFunction(runID: action.runID)
        await runtime.shutdown()
    }

    private func actionWriteCompletion(
        for preparation: ResearchActionPreparation,
        summary: String,
        submittedAt: Date = Date()
    ) throws -> ResearchActionWriteCompletionSubmission {
        let prefix = "Write key: "
        let writeKey = try #require(
            preparation.instructions
                .split(separator: "\n")
                .map(String.init)
                .first(where: { $0.hasPrefix(prefix) })
                .map { String($0.dropFirst(prefix.count)) }
        )
        return ResearchActionWriteCompletionSubmission(
            runID: preparation.runID,
            writeKey: writeKey,
            candidateModifiedNotes: [],
            summary: summary,
            submittedAt: submittedAt
        )
    }

}
