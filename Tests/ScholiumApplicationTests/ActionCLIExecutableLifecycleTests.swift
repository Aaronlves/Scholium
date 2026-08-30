import ScholiumContracts
import Foundation
@testable import ScholiumApplication
import Testing

@Suite("Executable Research Action CLI lifecycle")
struct ActionCLIExecutableLifecycleTests {
    @Test("Agent help is complete, self-describing, and keeps pairing on stdin")
    func agentHelpContract() throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(".build/agent-help", isDirectory: true)
        let cli = ActionCLIProcess(binaryPath: binaryPath, home: root)
        let commands = [
            "preflight-analysis", "start", "pair", "reload", "query", "discuss-reply",
            "extend-write-set",
            "write", "write-zotero-binding", "resolve-write-conflict",
            "submit-result", "continue",
            "method-context", "improve-method", "end",
        ]

        let rootHelp = String(
            decoding: try cli.run(["help"]).stdout,
            as: UTF8.self
        )
        #expect(!rootHelp.contains("pairing-code.txt"))
        #expect(!rootHelp.contains("< pairing"))
        #expect(rootHelp.contains("scholium record list --note <stable-note-uuid>"))
        #expect(rootHelp.contains("scholium record read <record-uuid>"))

        for command in commands {
            #expect(rootHelp.contains("scholium agent \(command)"))
            let result = try cli.run([
                "help", "agent", command, "--format", "json",
            ])
            let report = try #require(
                JSONSerialization.jsonObject(with: result.stdout)
                    as? [String: Any]
            )
            #expect(report["schema_version"] as? Int == 2)
            #expect(report["path"] as? [String] == ["agent", command])
            let renderedHelp = try #require(report["help"] as? String)
            #expect(renderedHelp.contains("Input contract:"))
            #expect(renderedHelp.contains("Output:"))
            #expect(renderedHelp.contains("Next:"))
            let contract = try #require(
                report["agent_command"] as? [String: Any]
            )
            #expect(!(contract["usage"] as? String ?? "").isEmpty)
            #expect(!(contract["input_contract"] as? String ?? "").isEmpty)
            #expect(!(contract["input"] as? String ?? "").isEmpty)
            #expect(!(contract["output"] as? String ?? "").isEmpty)
            #expect(!(contract["next_steps"] as? [String] ?? []).isEmpty)
        }
        #expect(!rootHelp.contains("scholium agent context"))
        try cli.expectFailure(
            ["agent", "context", "--run", "abcdefghijklmnopqrstuvwx"],
            contains: "Unknown command 'agent context'"
        )

        let pairHelp = String(
            decoding: try cli.run([
                "help", "agent", "pair", "--format", "json",
            ]).stdout,
            as: UTF8.self
        )
        #expect(pairHelp.contains("standard input"))
        #expect(!pairHelp.contains("pairing-code.txt"))

        let threePartHelp = String(
            decoding: try cli.run([
                "help", "zotero", "mcp", "config", "--format", "json",
            ]).stdout,
            as: UTF8.self
        )
        #expect(threePartHelp.contains("scholium zotero mcp config"))
        let inlineThreePartHelp = String(
            decoding: try cli.run([
                "zotero", "mcp", "config", "--help", "--format", "json",
            ]).stdout,
            as: UTF8.self
        )
        #expect(inlineThreePartHelp.contains("scholium zotero mcp config"))
    }

    @Test("A deployed external-Agent workspace discovers Skills and executes every Platform Action through the CLI")
    func everyPlatformActionThroughExternalCLI() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            ".build/m/\(String(UUID().uuidString.prefix(8)))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bridgeContainer) }

        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.homeURL.appendingPathComponent(
                "ApplicationSupport",
                isDirectory: true
            ),
            workspaceRegistryStorageURL: fixture.homeURL.appendingPathComponent(
                "registry",
                isDirectory: true
            )
        )))
        defer { Task { await runtime.shutdown() } }
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            switch request.operation {
            case .start:
                guard let triptychID = request.triptychID,
                      let start = request.startRequest else {
                    throw LocalAgentBridgeError.invalidRequest
                }
                let started = try await runtime.startResearchAgentRun(
                    triptychID: triptychID,
                    request: start
                )
                return .started(
                    receipt: started.receipt,
                    credential: started.credential
                )
            case .context:
                guard let run = request.run,
                      let credential = request.credential else {
                    throw LocalAgentBridgeError.invalidRequest
                }
                return .context(try await runtime.researchAgentContext(
                    credential: credential,
                    run: run
                ))
            case .query:
                guard let run = request.run,
                      let credential = request.credential,
                      let contextRequest = request.contextRequest else {
                    throw LocalAgentBridgeError.invalidRequest
                }
                return .researchContext(try await runtime.queryResearchContext(
                    credential: credential,
                    run: run,
                    request: contextRequest
                ))
            case .discussionReply:
                guard let run = request.run,
                      let credential = request.credential,
                      let reply = request.discussionReplyRequest else {
                    throw LocalAgentBridgeError.invalidRequest
                }
                return .discussionReply(
                    try await runtime.replyToResearchAgentDiscussion(
                        credential: credential,
                        run: run,
                        request: reply
                    )
                )
            case .writeDocument:
                guard let run = request.run,
                      let credential = request.credential,
                      let intent = request.documentWriteIntent else {
                    throw LocalAgentBridgeError.invalidRequest
                }
                return .documentWrite(try await runtime.writeResearchDocument(
                    credential: credential,
                    run: run,
                    intent: intent
                ))
            case .submitResult:
                guard let run = request.run,
                      let credential = request.credential,
                      let submission = request.resultSubmission else {
                    throw LocalAgentBridgeError.invalidRequest
                }
                return .resultReceipt(try await runtime.submitResearchAgentResult(
                    credential: credential,
                    run: run,
                    submission: submission
                ))
            case .preflightAnalysisCreation, .pair, .revokeSession,
                    .extendWriteSet, .writeZoteroBinding,
                    .resolveWriteConflict, .continueResearch,
                    .methodImprovementContext, .submitMethodImprovement, .end:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        let deployedSkills = try Self.deployExternalAgentWorkspace(
            triptychID: fixture.assignment.id,
            fixtureRoot: fixture.rootURL,
            cli: cli,
            environment: environment
        )
        let analysisBefore = try Data(contentsOf: fixture.rootURL
            .appendingPathComponent("Analyses/Analysis.md"))
        let topicBefore = try Data(contentsOf: fixture.rootURL
            .appendingPathComponent("Topics/Topic.md"))
        let workBefore = try Data(contentsOf: fixture.rootURL
            .appendingPathComponent("Works/Draft Argument.md"))

        let discuss = try await Self.startActionThroughCLI(
            .discuss,
            target: fixture.analysisTarget,
            triptychID: fixture.assignment.id,
            cli: cli,
            environment: environment
        )
        try Self.verifyExternalInstructionDelivery(
            actionID: .discuss,
            run: discuss.receipt.run,
            context: discuss.context,
            deployedSkills: deployedSkills,
            cli: cli,
            environment: environment
        )
        try Self.executeEvidenceQueriesThroughCLI(
            context: discuss.context,
            cli: cli,
            environment: environment
        )
        let replyStatementID = UUID()
        let reply: [String: String] = [
            "statement_id": replyStatementID.uuidString,
            "attribution": "External CLI simulation Agent",
            "text": "The disposable Analysis contains one synthetic claim and one explicit limitation.",
        ]
        let replyOutput = try cli.run(
            ["agent", "discuss-reply", "--run", discuss.receipt.run.rawValue,
             "--from", "-"],
            stdin: try Self.encoder().encode(reply),
            environment: environment
        )
        let replyReceipt = try Self.decoder().decode(
            ResearchAgentDiscussionReplyReceipt.self,
            from: replyOutput.stdout
        )
        #expect(replyReceipt.statementID == replyStatementID)
        #expect(replyReceipt.recordFormed)

        let simulations: [(
            action: ResearchActionID,
            target: ResearchActionNoteSnapshot,
            marker: String?
        )] = [
            (.analyze, fixture.analysisTarget, "external-cli-analyze-write"),
            (.synthesize, fixture.topicTarget, "external-cli-synthesize-write"),
            (.write, fixture.workTarget, "external-cli-write-write"),
            (.critique, fixture.workTarget, nil),
            (.checkFidelity, fixture.topicTarget, nil),
        ]
        for simulation in simulations {
            let targetURL = Self.fixtureDocumentURL(
                root: fixture.rootURL,
                target: simulation.target
            )
            let readOnlySourceBefore = simulation.marker == nil
                ? try Data(contentsOf: targetURL)
                : nil
            let started = try await Self.startActionThroughCLI(
                simulation.action,
                target: simulation.target,
                triptychID: fixture.assignment.id,
                cli: cli,
                environment: environment,
                sourceRoute: simulation.action == .analyze
                    ? .researcherProvided
                    : nil
            )
            try Self.verifyExternalInstructionDelivery(
                actionID: simulation.action,
                run: started.receipt.run,
                context: started.context,
                deployedSkills: deployedSkills,
                cli: cli,
                environment: environment
            )
            try Self.executeEvidenceQueriesThroughCLI(
                context: started.context,
                cli: cli,
                environment: environment
            )
            if let marker = simulation.marker {
                let member = try #require(started.context.boundedWriteSet.first)
                #expect(member.operations.contains(.modifyMarkdown))
                let writePayload: [String: String] = [
                    "role": member.role.rawValue,
                    "relative_path": member.relativePath,
                    "operation": ResearchDocumentWriteOperation.modifyMarkdown.rawValue,
                    "content": "# \(simulation.target.title)\n\n\(marker)\n",
                ]
                let writeOutput = try cli.run(
                    ["agent", "write", "--run", started.receipt.run.rawValue,
                     "--from", "-"],
                    stdin: try Self.encoder().encode(writePayload),
                    environment: environment
                )
                let writeReport = try #require(
                    JSONSerialization.jsonObject(with: writeOutput.stdout)
                        as? [String: Any]
                )
                #expect(writeReport["state"] as? String == "committed")
            } else {
                #expect(started.context.boundedWriteSet.isEmpty)
            }

            let submission = try Self.simulatedResult(
                action: simulation.action,
                context: started.context
            )
            if simulation.action == .analyze {
                let recordsBeforeInvalid = try await handle.research
                    .finishedResearchRecords(noteID: simulation.target.noteID)
                let invalid = try ResearchAgentResultSubmission(
                    recordTitle: submission.recordTitle,
                    disposition: submission.disposition,
                    academicResults: submission.academicResults,
                    fidelityOutcomes: [
                        FidelityCheckOutcome(
                            check: .content,
                            state: .passed,
                            summary: "The external Analyze simulation completed its bounded content self-check."
                        ),
                        FidelityCheckOutcome(
                            check: .citations,
                            state: .passed,
                            summary: "The external Analyze simulation completed its bounded citation self-check."
                        ),
                    ],
                    literatureRecommendations: submission.literatureRecommendations
                )
                let failure = try cli.runExpectingFailure(
                    ["agent", "submit-result", "--run", started.receipt.run.rawValue,
                     "--from", "-"],
                    stdin: try Self.encoder().encode(invalid),
                    environment: environment
                )
                let report = try #require(
                    JSONSerialization.jsonObject(with: failure.stderr)
                        as? [String: Any]
                )
                #expect(report["code"] as? String == "invalid_request")
                #expect((report["message"] as? String)?.contains(
                    "fidelity_outcomes"
                ) == true)
                let recovery = try #require(
                    report["recovery"] as? [String: Any]
                )
                #expect(recovery["safe_to_retry"] as? Bool == true)
                #expect(recovery["must_reuse_request_identity"] as? Bool == true)
                #expect(recovery["next_step"] as? String == "correct_request")
                let recordsAfterInvalid = try await handle.research
                    .finishedResearchRecords(noteID: simulation.target.noteID)
                #expect(recordsAfterInvalid == recordsBeforeInvalid)
                let reload = try cli.run(
                    ["agent", "reload", "--run", started.receipt.run.rawValue],
                    environment: environment
                )
                let reloaded = try Self.decoder().decode(
                    ResearchAuthenticatedRunContext.self,
                    from: reload.stdout
                )
                #expect(reloaded.brief.run == started.receipt.run)
                #expect(reloaded.brief.state == .prepared)
                #expect(String(
                    decoding: try Data(contentsOf: targetURL),
                    as: UTF8.self
                ).contains("external-cli-analyze-write"))
            }
            let resultOutput = try cli.run(
                ["agent", "submit-result", "--run", started.receipt.run.rawValue,
                 "--from", "-"],
                stdin: try Self.encoder().encode(submission),
                environment: environment
            )
            let receipt = try Self.decoder().decode(
                ResearchAgentResultReceipt.self,
                from: resultOutput.stdout
            )
            #expect(receipt.state == .finalized)
            #expect(receipt.recordFormed)
            if let readOnlySourceBefore {
                #expect(try Data(contentsOf: targetURL) == readOnlySourceBefore)
            }
        }

        let analysisAfter = try Data(contentsOf: fixture.rootURL
            .appendingPathComponent("Analyses/Analysis.md"))
        let topicAfter = try Data(contentsOf: fixture.rootURL
            .appendingPathComponent("Topics/Topic.md"))
        let workAfter = try Data(contentsOf: fixture.rootURL
            .appendingPathComponent("Works/Draft Argument.md"))
        #expect(analysisAfter != analysisBefore)
        #expect(topicAfter != topicBefore)
        #expect(workAfter != workBefore)
        #expect(String(decoding: analysisAfter, as: UTF8.self)
            .contains("external-cli-analyze-write"))
        #expect(String(decoding: topicAfter, as: UTF8.self)
            .contains("external-cli-synthesize-write"))
        #expect(String(decoding: workAfter, as: UTF8.self)
            .contains("external-cli-write-write"))

        server.stop()
        await runtime.shutdown()
        let recordedActions = try Set([
            fixture.analysisTarget.noteID,
            fixture.topicTarget.noteID,
            fixture.workTarget.noteID,
        ].flatMap { noteID in
            try Self.recordActionsThroughCLI(
                noteID: noteID,
                triptychID: fixture.assignment.id,
                cli: cli
            )
        })
        #expect(recordedActions == Set(ResearchActionID.allCases))
    }

    @Test("The real researcher CLI reads and CAS-updates managed Metadata without changing source")
    func researcherMetadataCLI() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let target = "\(fixture.analysisTarget.note.vaultID.uuidString):\(fixture.analysisTarget.note.relativePath)"

        let exactReadTarget = "\(fixture.analysisTarget.note.vaultID.uuidString):Exact Read.md"
        let exactRead = try cli.run(["read", exactReadTarget]).stdout
        #expect(exactRead == ActionCLIFixture.exactReadSource)

        let initial = try #require(
            JSONSerialization.jsonObject(with: try cli.run([
                "note", "metadata-read", target, "--format", "json",
            ]).stdout) as? [String: Any]
        )
        let initialRevision = try #require(initial["metadata_sha256"] as? String)
        let initialSourceRevision = try #require(initial["source_sha256"] as? String)
        #expect((initial["fields"] as? [String: Any])?["language"] as? String == "Greek")

        let valueURL = fixture.rootURL.appendingPathComponent("metadata-value.json")
        try Data(#""Latin""#.utf8).write(to: valueURL, options: .atomic)
        let updated = try #require(
            JSONSerialization.jsonObject(with: try cli.run([
                "note", "metadata-set", target, "language",
                "--value-from", valueURL.path,
                "--expected", initialRevision,
            ]).stdout) as? [String: Any]
        )
        let updatedRevision = try #require(updated["metadata_sha256"] as? String)
        #expect(updatedRevision != initialRevision)
        #expect(updated["source_sha256"] as? String == initialSourceRevision)
        #expect((updated["fields"] as? [String: Any])?["language"] as? String == "Latin")

        try cli.expectFailure([
            "note", "metadata-set", target, "language",
            "--value-from", valueURL.path,
            "--expected", initialRevision,
        ], contains: "Metadata revision mismatch")

        let removed = try #require(
            JSONSerialization.jsonObject(with: try cli.run([
                "note", "metadata-remove", target, "language",
                "--expected", updatedRevision,
            ]).stdout) as? [String: Any]
        )
        #expect(removed["source_sha256"] as? String == initialSourceRevision)
        #expect((removed["fields"] as? [String: Any])?["language"] == nil)
    }

    @Test("The real CLI preflights direct Analysis creation, starts without pairing, writes, and ends")
    func agentStartContextWriteAndEnd() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            ".build/m/\(String(UUID().uuidString.prefix(8)))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bridgeContainer) }

        let run = try #require(
            ResearchRunLocator(rawValue: "agentstartcontextwriteend")
        )
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "a", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .analyze
            }
        )
        let registration = try ResearchSkillRegistration(
            actionID: .analyze,
            displayName: "Analysis Method",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Analysis Method\n\nKeep source limits visible.\n"
        )
        let context = try ResearchAuthenticatedRunContext(
            brief: ResearchRunBrief(
                run: run,
                actionID: .analyze,
                state: .prepared,
                initialObjectTitle: fixture.analysisTarget.title,
                initialObjectRole: .analysis,
                academicPurpose: "Analyze the Zotero paper.",
                capabilities: ResearchRunCapabilityAvailability(
                    search: true,
                    read: true,
                    relations: true,
                    metadata: true,
                    records: true,
                    researchState: true,
                    zotero: true,
                    writeInitialObject: true,
                    extendWriteSet: false
                )
            ),
            requiredSkills: try Self.requiredSkills(for: method),
            resultContract: try ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: try profile.contentRevision()
            ),
            boundedWriteSet: []
        )
        let preflightInput = try ResearchAgentAnalysisCreationPreflightRequest(
            requestID: UUID(uuidString: "00000000-0000-4000-8000-000000000813")!,
            destination: ResearchAgentAnalysisDestination(
                managedDefaultFilename: fixture.analysisTarget.note.relativePath
            ),
            metadata: AnalysisCreationMetadata(sourceType: .journalArticle),
            sourceRoute: .researcherProvided
        )
        let newAnalysis = ResearchAgentNewAnalysisRequest(preflight: preflightInput)
        let creationPreflight = ResearchAgentAnalysisCreationPreflight(
            request: preflightInput,
            analysisVaultID: fixture.analysisTarget.note.vaultID,
            applicableFields: PropertyContractCatalog.contracts(for: .analysis),
            preferredFields: [],
            fixedYAMLFields: PropertyContractCatalog.authoredCanonicalKeys,
            targetState: ResearchAgentAnalysisTargetState(
                target: fixture.analysisTarget.note,
                stableIdentity: nil,
                fingerprint: nil,
                sourceState: .absent
            ),
            status: .ready,
            startNewAnalysis: newAnalysis,
            recovery: AgentOperationRecovery(
                safeToRetry: true,
                mustReuseRequestIdentity: true,
                nextStep: .startWithReturnedTemplate
            ),
            message: "The managed root Analysis destination is ready."
        )
        let startRequest = try ResearchAgentStartRequest(
            actionID: .analyze,
            newAnalysis: newAnalysis,
            academicInputs: [
                "research-request": .freeText("Analyze the Zotero paper."),
            ]
        )
        let startReceipt = try ResearchAgentStartReceipt(
            run: run,
            actionID: .analyze,
            target: fixture.analysisTarget,
            state: .prepared,
            message: "The Agent-originated Run is active."
        )
        let writeEntry = try ResearchBoundedWriteSetEntry(
            handle: ResearchWriteTargetHandle(
                runID: UUID(),
                noteID: fixture.analysisTarget.noteID
            ),
            noteID: fixture.analysisTarget.noteID,
            note: fixture.analysisTarget.note,
            role: .analysis,
            title: fixture.analysisTarget.title,
            allowedOperations: [.modifyMarkdown],
            expectedRevision: fixture.analysisTarget.fingerprint,
            authorizationBasis: .initialAction,
            expiresAt: Date().addingTimeInterval(600)
        )
        let writeView = ResearchBoundedWriteSetViewEntry(writeEntry)
        let writeOperationID = UUID()
        let endReceipt = try ResearchRunEndReceipt(
            run: run,
            recoveryRetained: false,
            message: "The Run ended and refuses new Agent operations."
        )
        let preflightAttempts = LockedCounter()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            switch request.operation {
            case .preflightAnalysisCreation:
                guard request.triptychID == fixture.assignment.id,
                      request.analysisCreationPreflightRequest == preflightInput else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                if preflightAttempts.increment() == 1 {
                    throw LocalAgentBridgeError.outcomeUnknown(
                        LocalAgentBridgeErrorPayload.outcomeUnknownRecovery(
                            for: request
                        )
                    )
                }
                return .analysisCreationPreflight(creationPreflight)
            case .start:
                guard request.triptychID == fixture.assignment.id,
                      request.startRequest == startRequest,
                      request.run == nil else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .started(receipt: startReceipt, credential: credential)
            case .context:
                guard request.run == run, request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .context(context)
            case .writeDocument:
                guard request.run == run,
                      request.credential == credential,
                      request.documentWriteIntent?.role == .analysis,
                      request.documentWriteIntent?.relativePath
                        == fixture.analysisTarget.note.relativePath,
                      request.documentWriteIntent?.operation == .modifyMarkdown else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .documentWrite(ResearchDocumentWriteResult(
                    operationID: writeOperationID,
                    state: .committed,
                    target: writeView,
                    message: "The bounded write committed."
                ))
            case .end:
                guard request.run == run, request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .endReceipt(endReceipt)
            case .pair, .revokeSession, .query, .discussionReply,
                    .extendWriteSet, .writeZoteroBinding,
                    .resolveWriteConflict, .submitResult, .continueResearch,
                    .methodImprovementContext, .submitMethodImprovement:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let freshAgentHome = fixture.rootURL.appendingPathComponent(
            "fresh-agent-home",
            isDirectory: true
        )
        #expect(!FileManager.default.fileExists(atPath: freshAgentHome.path))
        let cli = ActionCLIProcess(binaryPath: binaryPath, home: freshAgentHome)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        let doctor = try cli.run(
            ["doctor", "--format", "json"],
            environment: environment
        )
        let doctorObject = try #require(
            JSONSerialization.jsonObject(with: doctor.stdout) as? [String: Any]
        )
        #expect(doctorObject["schema_version"] as? Int == 1)
        let applicationSupportURL = freshAgentHome.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        let applicationSupportMode = try #require(
            FileManager.default.attributesOfItem(
                atPath: applicationSupportURL.path
            )[.posixPermissions] as? NSNumber
        ).intValue
        #expect(applicationSupportMode == 0o700)
        let unknown = try cli.runExpectingFailure(
            [
                "agent", "preflight-analysis", "--triptych",
                fixture.assignment.id.uuidString,
                "--from", "-",
            ],
            stdin: try Self.encoder().encode(preflightInput),
            environment: environment
        )
        let unknownObject = try #require(
            JSONSerialization.jsonObject(with: unknown.stderr) as? [String: Any]
        )
        #expect(unknownObject["code"] as? String == "outcome_unknown")
        #expect((unknownObject["recovery"] as? [String: Any])?["next_step"]
            as? String == "rerun_creation_preflight")

        // Execute the returned operation-specific next step with the same
        // request identity; the second standalone invocation must converge.
        let preflighted = try cli.run(
            [
                "agent", "preflight-analysis", "--triptych",
                fixture.assignment.id.uuidString,
                "--from", "-",
            ],
            stdin: try Self.encoder().encode(preflightInput),
            environment: environment
        )
        let preflightObject = try #require(
            JSONSerialization.jsonObject(with: preflighted.stdout)
                as? [String: Any]
        )
        #expect(preflightObject["status"] as? String == "ready")
        #expect(preflightObject["start_new_analysis"] != nil)
        #expect((preflightObject["recovery"] as? [String: Any])?["next_step"]
            as? String == "start_with_returned_template")
        let started = try cli.run(
            [
                "agent", "start", "--triptych", fixture.assignment.id.uuidString,
                "--from", "-",
            ],
            stdin: try Self.encoder().encode(startRequest),
            environment: environment
        )
        let startedReport = try Self.decoder().decode(
            CLIAgentStartReport.self,
            from: started.stdout
        )
        let startedOutput = String(decoding: started.stdout, as: UTF8.self)
        #expect(startedReport.receipt == startReceipt)
        #expect(startedReport.context.brief.run == run)
        #expect(startedReport.context.requiredSkills.map(\.name) == [
            "scholium-core-protocol", "scholium-analyze",
        ])
        #expect(startedOutput.contains(run.rawValue))
        #expect(!startedOutput.contains(credential.secret))

        let credentialURL = freshAgentHome
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Agent Sessions", isDirectory: true)
            .appendingPathComponent(run.rawValue + ".json")
        let homeMode = try #require(
            FileManager.default.attributesOfItem(atPath: freshAgentHome.path)[
                .posixPermissions
            ] as? NSNumber
        ).intValue
        #expect(homeMode == 0o700)
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: credentialURL.path)[
                .posixPermissions
            ] as? NSNumber
        ).intValue
        #expect(mode == 0o600)

        let write = try cli.run(
            ["agent", "write", "--run", run.rawValue, "--from", "-"],
            stdin: try JSONSerialization.data(withJSONObject: [
                "role": "analysis",
                "relative_path": fixture.analysisTarget.note.relativePath,
                "content": "# Zotero analysis\n\nThe bounded result.\n",
            ]),
            environment: environment
        )
        #expect(String(decoding: write.stdout, as: UTF8.self).contains("committed"))

        let ended = try cli.run(
            ["agent", "end", "--run", run.rawValue],
            environment: environment
        )
        #expect(String(decoding: ended.stdout, as: UTF8.self)
            .contains("\"ended\" : true"))
        #expect(!FileManager.default.fileExists(atPath: credentialURL.path))
    }

    @Test("Agent start resolves a UUID-shaped Triptych name before direct-ID fallback")
    func agentStartUUIDShapedTriptychName() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let uuidShapedName = UUID().uuidString.lowercased()
        let fixture = try await ActionCLIFixture.make(triptychName: uuidShapedName)
        defer { fixture.remove() }
        let bridgeContainer = fixture.rootURL.appendingPathComponent(
            "uuid-name-bridge",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        let run = try #require(
            ResearchRunLocator(rawValue: "uuidshapedtriptychname")
        )
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "u", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let request = try ResearchAgentStartRequest(
            actionID: .analyze,
            target: fixture.analysisTarget.note,
            sourceRoute: .researcherProvided
        )
        let receipt = try ResearchAgentStartReceipt(
            run: run,
            actionID: .analyze,
            target: fixture.analysisTarget,
            state: .prepared,
            message: "The Agent-originated Run is active."
        )
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .analyze
            }
        )
        let registration = try ResearchSkillRegistration(
            actionID: .analyze,
            displayName: "Analysis Method",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Analysis Method\n"
        )
        let context = try ResearchAuthenticatedRunContext(
            brief: ResearchRunBrief(
                run: run,
                actionID: .analyze,
                state: .prepared,
                initialObjectTitle: fixture.analysisTarget.title,
                initialObjectRole: .analysis,
                academicPurpose: nil,
                capabilities: ResearchRunCapabilityAvailability(
                    search: true,
                    read: true,
                    relations: true,
                    metadata: true,
                    records: true,
                    researchState: true,
                    zotero: true,
                    writeInitialObject: true,
                    extendWriteSet: false
                )
            ),
            requiredSkills: try Self.requiredSkills(for: method),
            resultContract: try ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: try profile.contentRevision()
            ),
            boundedWriteSet: []
        )
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { bridgeRequest in
            switch bridgeRequest.operation {
            case .start:
                guard bridgeRequest.triptychID == fixture.assignment.id,
                      bridgeRequest.startRequest == request else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .started(receipt: receipt, credential: credential)
            case .context:
                guard bridgeRequest.run == run,
                      bridgeRequest.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .context(context)
            default:
                throw LocalAgentBridgeError.permissionDenied
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let result = try cli.run(
            [
                "agent", "start", "--triptych", uuidShapedName,
                "--from", "-",
            ],
            stdin: try Self.encoder().encode(request),
            environment: [
                "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
            ]
        )
        let report = try Self.decoder().decode(
            CLIAgentStartReport.self,
            from: result.stdout
        )
        #expect(report.receipt.run == run)
        #expect(report.context.brief.run == run)
    }

    @Test("The real CLI pairs, reloads Discuss context, and removes its credential after the reply forms a Record")
    func agentPairingContextAndDiscussionReplyCompletion() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            ".build/m/\(String(UUID().uuidString.prefix(8)))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bridgeContainer) }

        let run = try #require(
            ResearchRunLocator(rawValue: "abcdefghijklmnopqrstuvwx")
        )
        let code = try #require(
            ResearchPairingCode(rawValue: "23456789ABCDEFGHJKLMNPQR")
        )
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "s", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .discuss
            }
        )
        let registration = try ResearchSkillRegistration(
            actionID: .discuss,
            displayName: "Discussion Method",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Discussion Method\n\nPreserve alternatives.\n"
        )
        let profileRevision = try profile.contentRevision()
        let context = try ResearchAuthenticatedRunContext(
            brief: ResearchRunBrief(
                run: run,
                actionID: .discuss,
                state: .prepared,
                initialObjectTitle: "Agency",
                initialObjectRole: .topic,
                academicPurpose: nil,
                capabilities: ResearchRunCapabilityAvailability(
                    search: true,
                    read: true,
                    relations: true,
                    metadata: true,
                    records: true,
                    researchState: true,
                    zotero: true,
                    writeInitialObject: false,
                    extendWriteSet: false,
                    discussionReply: true
                )
            ),
            requiredSkills: try Self.requiredSkills(for: method),
            resultContract: try ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: profileRevision
            ),
            boundedWriteSet: []
        )
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try ResearchAuthenticatedRunContext(
                brief: context.brief,
                requiredSkills: context.requiredSkills + [
                    try .systemAdapter(.zoteroIntegration),
                ],
                resultContract: context.resultContract,
                boundedWriteSet: context.boundedWriteSet
            )
        }
        let statementID = UUID()
        let replyReceipt = try ResearchAgentDiscussionReplyReceipt(
            run: run,
            discussionID: UUID(),
            statementID: statementID,
            state: .recorded,
            message: "The Agent reply was recorded and the Discussion formed its Research Record."
        )
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            switch request.operation {
            case .preflightAnalysisCreation, .start:
                throw LocalAgentBridgeError.invalidRequest
            case .pair:
                guard request.run == run, request.pairingCode == code else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .credential(credential)
            case .context:
                guard request.run == run, request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .context(context)
            case .discussionReply:
                guard request.run == run,
                      request.credential == credential,
                      request.discussionReplyRequest?.statementID == statementID else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .discussionReply(replyReceipt)
            case .revokeSession, .query,
                    .extendWriteSet, .writeDocument, .writeZoteroBinding,
                    .resolveWriteConflict, .submitResult, .continueResearch,
                    .methodImprovementContext, .submitMethodImprovement, .end:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        try cli.expectFailure(
            ["agent", "pair", "--run", run.rawValue],
            stdin: Data(repeating: 0x41, count: 257),
            environment: environment,
            contains: "exceeded its 256-byte limit"
        )
        let paired = try cli.run(
            ["agent", "pair", "--run", run.rawValue],
            stdin: Data((code.rawValue + "\n").utf8),
            environment: environment
        )
        let pairingReport = try Self.decoder().decode(
            CLIAgentPairingReport.self,
            from: paired.stdout
        )
        let pairingOutput = String(decoding: paired.stdout, as: UTF8.self)
        #expect(pairingOutput.contains("\"paired\" : true"))
        #expect(pairingReport.paired)
        #expect(pairingReport.run == run)
        #expect(pairingReport.context.brief.run == run)
        #expect(!pairingOutput.contains(credential.secret))
        #expect(!pairingOutput.contains(code.rawValue))
        let credentialURL = fixture.homeURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Agent Sessions", isDirectory: true)
            .appendingPathComponent(run.rawValue + ".json")
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: credentialURL.path)[
                .posixPermissions
            ] as? NSNumber
        ).intValue
        #expect(mode == 0o600)

        let contextOutput = pairingOutput
        #expect(contextOutput.contains("scholium-core-protocol"))
        #expect(contextOutput.contains("scholium-discussion-protocol"))
        #expect(contextOutput.contains("scholium-discuss"))
        #expect(!contextOutput.contains("Preserve alternatives."))
        #expect(!contextOutput.contains("# Discussion Method"))
        #expect(!contextOutput.contains(credential.secret))

        var storedCredential = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: credentialURL)
            ) as? [String: Any]
        )
        storedCredential["unexpected_authority"] = "must fail closed"
        try JSONSerialization.data(withJSONObject: storedCredential)
            .write(to: credentialURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialURL.path
        )
        let invalidSession = try cli.runExpectingFailure(
            ["agent", "reload", "--run", run.rawValue],
            environment: environment,
        )
        let invalidSessionReport = try #require(
            JSONSerialization.jsonObject(with: invalidSession.stderr)
                as? [String: Any]
        )
        #expect(invalidSessionReport["code"] as? String == "session_expired")
        #expect(
            (invalidSessionReport["message"] as? String)?.contains(
                "copy a new handoff"
            ) == true
        )
        let invalidSessionRecovery = try #require(
            invalidSessionReport["recovery"] as? [String: Any]
        )
        #expect(
            invalidSessionRecovery["next_step"] as? String
                == "copy_new_handoff_and_pair_same_run"
        )
        storedCredential.removeValue(forKey: "unexpected_authority")
        try JSONSerialization.data(withJSONObject: storedCredential)
            .write(to: credentialURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialURL.path
        )

        let reply = try cli.run(
            ["agent", "discuss-reply", "--run", run.rawValue, "--from", "-"],
            stdin: try Self.encoder().encode([
                "statement_id": statementID.uuidString,
                "attribution": "External Agent",
                "text": "A bounded philosophical response.",
            ]),
            environment: environment
        )
        let replyOutput = String(decoding: reply.stdout, as: UTF8.self)
        #expect(replyOutput.contains("\"record_formed\" : true"))
        #expect(!replyOutput.contains(credential.secret))
        #expect(!FileManager.default.fileExists(atPath: credentialURL.path))
    }

    @Test("The real CLI hides write identities for document and Zotero-binding writes")
    func agentBoundedWriteCLI() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            ".build/m/\(String(UUID().uuidString.prefix(8)))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bridgeContainer) }
        let run = try #require(ResearchRunLocator(
            rawValue: "zyxwvutsrqponmlkjihgfedc"
        ))
        let code = try #require(ResearchPairingCode(
            rawValue: "RQPNMLKJHGFEDCBA98765432"
        ))
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "w", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let hiddenRequestID = UUID()
        let hiddenOperationID = UUID()
        let hiddenBindingOperationID = UUID()
        let completeSource = "\u{FEFF}---\r\ntitle: Complete CLI source\r\n---\r\n# Complete CLI source\r\n"
        let entry = try ResearchBoundedWriteSetEntry(
            handle: ResearchWriteTargetHandle(runID: UUID(), noteID: UUID()),
            noteID: UUID(),
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Agency.md"
            ),
            role: .topic,
            title: "Agency",
            allowedOperations: [.modifyMarkdown],
            expectedRevision: DocumentFingerprint(content: "before"),
            authorizationBasis: .initialAction,
            expiresAt: Date().addingTimeInterval(600)
        )
        let observedIDs = LockedAgentWriteRequestIDs()
        let observedBindingIDs = LockedAgentWriteRequestIDs()
        let analysisID = UUID()
        let analysisEntry = try ResearchBoundedWriteSetEntry(
            handle: ResearchWriteTargetHandle(runID: UUID(), noteID: analysisID),
            noteID: analysisID,
            note: VaultQualifiedNoteID(
                vaultID: UUID(),
                relativePath: "Analysis.md"
            ),
            role: .analysis,
            title: "Analysis",
            allowedOperations: [.setZoteroBinding, .clearZoteroBinding],
            expectedRevision: DocumentFingerprint(content: "analysis"),
            zoteroBindingsRevision: DocumentFingerprint(content: "[]"),
            authorizationBasis: .collaborationPolicy,
            authorizationPolicy: .fullAccess,
            policyRevision: DocumentFingerprint(content: "full-access"),
            expiresAt: Date().addingTimeInterval(600)
        )
        let entryRevision = try #require(entry.expectedRevision)
        let relatedSeeds = [
            try ResearchRelatedNotesResolvedSeed(
                inputName: "Agency",
                note: entry.note,
                role: .topic,
                title: "Agency",
                fingerprint: entryRevision
            ),
            try ResearchRelatedNotesResolvedSeed(
                inputName: "Draft Argument",
                note: VaultQualifiedNoteID(
                    vaultID: UUID(),
                    relativePath: "Draft Argument.md"
                ),
                role: .work,
                title: "Draft Argument",
                fingerprint: DocumentFingerprint(content: "draft")
            ),
        ]
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            guard request.run == run else {
                throw LocalAgentBridgeError.permissionDenied
            }
            switch request.operation {
            case .preflightAnalysisCreation, .start:
                throw LocalAgentBridgeError.invalidRequest
            case .pair:
                guard request.pairingCode == code else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .credential(credential)
            case .context:
                guard request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .context(try Self.minimalContext(
                    run: run,
                    actionID: .write
                ))
            case .query:
                guard request.credential == credential,
                      let contextRequest = request.contextRequest,
                      contextRequest.clauses.count == 1,
                      let clause = contextRequest.clauses.first,
                      clause.kind == .relatedNotes,
                      clause.noteNames == ["Agency", "Draft Argument"],
                      clause.limit == 5 else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                let query = try ResearchContextQuery(
                    request: contextRequest,
                    runID: UUID(),
                    triptychID: UUID()
                )
                let related = try ResearchRelatedNotesResult(
                    state: .empty,
                    resolvedSeeds: relatedSeeds,
                    unresolvedNames: [],
                    candidates: [],
                    hasMore: false
                )
                return .researchContext(try ResearchContextResponse(
                    query: query,
                    outcomes: [try ResearchContextClauseOutcome(
                        clause: clause,
                        availability: .current,
                        items: [],
                        relatedNotes: related
                    )]
                ))
            case .extendWriteSet:
                guard request.credential == credential,
                      request.writeSetIntent?.targets.first?.relativePath
                        == "Agency.md" else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .writeSet(ResearchWriteSetExtensionResult(
                    requestID: hiddenRequestID,
                    state: .allowedSubset,
                    entries: [ResearchBoundedWriteSetViewEntry(entry)],
                    message: "The approved document is ready."
                ))
            case .writeDocument:
                guard request.credential == credential,
                      let intent = request.documentWriteIntent,
                      intent.role == .topic,
                      intent.relativePath == "Agency.md" else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                if intent.operation == .modifySource {
                    guard intent.source == completeSource else {
                        throw LocalAgentBridgeError.permissionDenied
                    }
                }
                observedIDs.append(intent.requestID)
                return .documentWrite(ResearchDocumentWriteResult(
                    operationID: hiddenOperationID,
                    state: .committed,
                    target: ResearchBoundedWriteSetViewEntry(entry),
                    message: "The exact document write committed and read back."
                ))
            case .writeZoteroBinding:
                guard request.credential == credential,
                      let intent = request.zoteroBindingWriteIntent,
                      intent.role == .analysis,
                      intent.relativePath == "Analysis.md",
                      intent.operation == .setZoteroBinding,
                      intent.library == .group(42),
                      intent.itemKey == "ITEM_42" else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                observedBindingIDs.append(intent.requestID)
                return .zoteroBindingWrite(ResearchZoteroBindingWriteResult(
                    operationID: hiddenBindingOperationID,
                    state: .committed,
                    target: ResearchBoundedWriteSetViewEntry(analysisEntry),
                    message: "The portable Zotero binding committed and read back."
                ))
            case .revokeSession, .discussionReply,
                    .resolveWriteConflict, .submitResult,
                    .continueResearch, .methodImprovementContext,
                    .submitMethodImprovement, .end:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }
        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        _ = try cli.run(
            ["agent", "pair", "--run", run.rawValue],
            stdin: Data((code.rawValue + "\n").utf8),
            environment: environment
        )
        let related = try cli.run(
            [
                "agent", "related", "--run", run.rawValue,
                "--note", "Agency", "--note", "Draft Argument",
                "--limit", "5",
            ],
            environment: environment
        )
        let relatedOutput = String(decoding: related.stdout, as: UTF8.self)
        #expect(relatedOutput.contains("\"kind\" : \"related_notes\""))
        #expect(relatedOutput.contains("Draft Argument"))
        let extensionJSON = try JSONSerialization.data(withJSONObject: [
            "schema_version": ResearchWriteSetExtensionIntent.currentSchemaVersion,
            "targets": [[
                "role": "topic",
                "relative_path": "Agency.md",
                "operations": ["modify_markdown"],
            ]],
            "academic_reason": "Update the relevant topic note.",
        ])
        let extended = try cli.run(
            ["agent", "extend-write-set", "--run", run.rawValue, "--from", "-"],
            stdin: extensionJSON,
            environment: environment
        )
        let extensionOutput = String(decoding: extended.stdout, as: UTF8.self)
        #expect(extensionOutput.contains("Agency.md"))
        #expect(!extensionOutput.contains(hiddenRequestID.uuidString))
        #expect(!extensionOutput.contains("request_id"))

        try cli.expectFailure(
            ["agent", "write", "--run", run.rawValue, "--from", "-"],
            stdin: try JSONSerialization.data(withJSONObject: [
                "role": "topic",
                "relative_path": "Agency.md",
            ]),
            environment: environment,
            contains: "content"
        )

        let emptyBody = try cli.run(
            ["agent", "write", "--run", run.rawValue, "--from", "-"],
            stdin: try JSONSerialization.data(withJSONObject: [
                "role": "topic",
                "relative_path": "Agency.md",
                "content": "",
            ]),
            environment: environment
        )
        #expect(String(decoding: emptyBody.stdout, as: UTF8.self).contains("committed"))

        let metadataJSON = try JSONSerialization.data(withJSONObject: [
            "role": "topic",
            "relative_path": "Agency.md",
            "operation": "modify_metadata",
            "metadata": [[
                "key": "aliases",
                "value": ["Ordinary JSON value"],
            ]],
        ])
        let metadataWrite = try cli.run(
            ["agent", "write", "--run", run.rawValue, "--from", "-"],
            stdin: metadataJSON,
            environment: environment
        )
        #expect(String(decoding: metadataWrite.stdout, as: UTF8.self)
            .contains("committed"))

        let sourceWrite = try cli.run(
            ["agent", "write", "--run", run.rawValue, "--from", "-"],
            stdin: try JSONSerialization.data(withJSONObject: [
                "role": "topic",
                "relative_path": "Agency.md",
                "operation": "modify_source",
                "source": completeSource,
            ]),
            environment: environment
        )
        #expect(String(decoding: sourceWrite.stdout, as: UTF8.self)
            .contains("committed"))

        let writeJSON = try JSONSerialization.data(withJSONObject: [
            "role": "topic",
            "relative_path": "Agency.md",
            "content": "# Agency\n\nBounded update.\n",
        ])
        let first = try cli.run(
            ["agent", "write", "--run", run.rawValue, "--from", "-"],
            stdin: writeJSON,
            environment: environment
        )
        let second = try cli.run(
            ["agent", "write", "--run", run.rawValue, "--from", "-"],
            stdin: writeJSON,
            environment: environment
        )
        #expect(first.stdout == second.stdout)
        let writeOutput = String(decoding: first.stdout, as: UTF8.self)
        #expect(writeOutput.contains("committed"))
        #expect(!writeOutput.contains(hiddenOperationID.uuidString))
        #expect(!writeOutput.contains("operation_id"))
        #expect(observedIDs.values.count == 5)
        #expect(Set(observedIDs.values).count == 4)

        let bindingJSON = try JSONSerialization.data(withJSONObject: [
            "role": "analysis",
            "relative_path": "Analysis.md",
            "operation": "set_zotero_binding",
            "library": ["kind": "group", "group_id": 42],
            "item_key": "item_42",
        ])
        let firstBinding = try cli.run(
            [
                "agent", "write-zotero-binding", "--run", run.rawValue,
                "--from", "-",
            ],
            stdin: bindingJSON,
            environment: environment
        )
        let secondBinding = try cli.run(
            [
                "agent", "write-zotero-binding", "--run", run.rawValue,
                "--from", "-",
            ],
            stdin: bindingJSON,
            environment: environment
        )
        #expect(firstBinding.stdout == secondBinding.stdout)
        let bindingOutput = String(decoding: firstBinding.stdout, as: UTF8.self)
        #expect(bindingOutput.contains("committed"))
        #expect(!bindingOutput.contains(hiddenBindingOperationID.uuidString))
        #expect(!bindingOutput.contains("operation_id"))
        #expect(observedBindingIDs.values.count == 2)
        #expect(Set(observedBindingIDs.values).count == 1)
    }

    @Test("The real CLI exposes current Search plus direct fingerprinted Record retrieval")
    func searchV7Contract() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let triptych = fixture.assignment.id.uuidString
        let analyses = try #require(fixture.assignment.vault(for: .paperAnalysis))

        let jsonl = try cli.run([
            "search", "synthetic", "--triptych", triptych,
            "--limit", "2", "--format", "jsonl",
        ])
        let lines = String(decoding: jsonl.stdout, as: UTF8.self)
            .split(separator: "\n")
        #expect(lines.count == 3)
        let records = try lines.map { line in
            try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        #expect(records.first?["type"] as? String == "search_summary")
        #expect(records.first?["contract_version"] as? Int == SearchContract.currentVersion)
        #expect(records.first?["provider"] as? String == SearchProvider.note.rawValue)
        #expect(records.first?["scope"] as? String == SearchPresentationScope.triptych.rawValue)
        let availability = try #require(records.first?["availability"] as? [String: Any])
        #expect(availability["provider"] as? String == SearchProvider.note.rawValue)
        #expect(availability["status"] as? String == "current")
        #expect(records.first?["freshness_token"] as? [String: Any] != nil)
        let explanation = try #require(records.first?["explanation"] as? [String: Any])
        #expect(explanation["scope"] as? String == SearchPresentationScope.triptych.rawValue)
        #expect(explanation["normalization"] as? [Any] != nil)
        #expect(explanation["ordering"] as? String == SearchExplanationOrdering.noteExactIdentityThenBM25ThenTitleRolePath.rawValue)
        #expect(explanation["limitations"] as? [Any] != nil)
        #expect(records.dropFirst().allSatisfy { $0["type"] as? String == "search_result" })
        #expect(records.dropFirst().allSatisfy {
            $0["provider"] as? String == SearchProvider.note.rawValue
                && $0["contract_version"] as? Int == SearchContract.currentVersion
                && $0["vault_id"] != nil
                && $0["relative_path"] != nil
                && $0["match_reasons"] != nil
                && $0["locator"] != nil
                && $0["fingerprint"] != nil
                && $0["freshness_token"] != nil
        })
        #expect(records.dropFirst().allSatisfy { $0["score"] == nil && $0["index_generation"] == nil })

        let text = String(decoding: try cli.run([
            "search", "synthetic", "--vault", analyses.id.uuidString,
            "--triptych", triptych, "--format", "text",
        ]).stdout, as: UTF8.self)
        #expect(text.contains("Search contract=\(SearchContract.currentVersion) provider=note"))
        #expect(text.contains("Explain: provider=note"))
        #expect(text.contains(
            "scope=\(SearchPresentationScope.currentVault.rawValue)"
        ))
        #expect(text.contains("normalization="))
        #expect(text.contains("ordering="))
        #expect(text.contains("limitations="))
        #expect(text.contains("note Analyses:Analysis.md:"))
        #expect(text.contains("[retrieval_lead;"))
        #expect(text.contains("fingerprint="))
        #expect(text.contains("freshness="))

        let propertySearch = try cli.run([
            "search", #"property:language="Greek""#,
            "--triptych", triptych, "--format", "jsonl",
        ])
        let propertyRows = try String(decoding: propertySearch.stdout, as: UTF8.self)
            .split(separator: "\n")
            .map { line in
                try #require(
                    JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any]
                )
            }
        #expect(propertyRows.first?["provider"] as? String == SearchProvider.note.rawValue)
        #expect(propertyRows.dropFirst().contains {
            $0["relative_path"] as? String == "Analysis.md"
                && $0["match_reasons"] != nil
        }, Comment(
            rawValue: String(decoding: propertySearch.stdout, as: UTF8.self)
        ))

        let summarySearch = try cli.run([
            "search", "summary:inheritance",
            "--triptych", triptych, "--format", "jsonl",
        ])
        let summaryRows = try String(decoding: summarySearch.stdout, as: UTF8.self)
            .split(separator: "\n")
            .map { line in
                try #require(
                    JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any]
                )
            }
        #expect(summaryRows.dropFirst().count == 1)
        #expect(summaryRows.dropFirst().first?["relative_path"] as? String == "Analysis.md")
        #expect(summaryRows.dropFirst().first?["matched_field"] as? String == "summary")
        #expect(summaryRows.dropFirst().first?["locator"] as? [String: Any] != nil)

        let relationSearch = try cli.run([
            "search", #"from-note:"Analysis" relation:supports"#,
            "--triptych", triptych, "--format", "jsonl",
        ])
        let relationRows = try String(decoding: relationSearch.stdout, as: UTF8.self)
            .split(separator: "\n")
            .map { line in
                try #require(
                    JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any]
                )
            }
        #expect(relationRows.first?["provider"] as? String == SearchProvider.note.rawValue)
        #expect(relationRows.dropFirst().contains {
            $0["relative_path"] as? String == "Topic.md"
                && $0["match_reasons"] != nil
        })

        let noMatch = try cli.run([
            "search", "no-such-search-term", "--triptych", triptych,
        ])
        let noMatchText = String(decoding: noMatch.stdout, as: UTF8.self)
        #expect(noMatchText.contains("provider=note"))
        #expect(noMatchText.hasSuffix("No matches.\n"))

        let recordSearch = try cli.run([
            "search", "kind:record synthetic", "--triptych", triptych,
            "--format", "jsonl",
        ])
        let recordSummaryLine = try #require(
            String(decoding: recordSearch.stdout, as: UTF8.self)
                .split(separator: "\n")
                .first
        )
        let recordSummary = try #require(
            JSONSerialization.jsonObject(with: Data(recordSummaryLine.utf8)) as? [String: Any]
        )
        #expect(recordSummary["contract_version"] as? Int == SearchContract.currentVersion)
        #expect(recordSummary["provider"] as? String == SearchProvider.record.rawValue)
        let recordAvailability = try #require(
            recordSummary["availability"] as? [String: Any]
        )
        #expect(recordAvailability["provider"] as? String == SearchProvider.record.rawValue)

        let relatedRecords = try cli.run([
            "record", "list", "--note", fixture.analysisTarget.noteID.uuidString,
            "--triptych", triptych, "--format", "jsonl",
        ])
        let relatedRows = try String(decoding: relatedRecords.stdout, as: UTF8.self)
            .split(separator: "\n")
            .map { line in
                try #require(
                    JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any]
                )
            }
        #expect(relatedRows.count == 2)
        #expect(relatedRows[0]["type"] as? String == "record_list_summary")
        #expect(relatedRows[0]["schema_version"] as? Int == 2)
        #expect(relatedRows[0]["record_count"] as? Int == 1)
        #expect(relatedRows[0]["corpus_complete"] as? Bool == true)
        #expect(relatedRows[0]["source_manifest_hash"] as? String != nil)
        #expect(relatedRows[1]["type"] as? String == "research_record_summary")
        #expect(
            (relatedRows[1]["record_id"] as? String)?.lowercased()
                == fixture.recordID.uuidString.lowercased()
        )
        #expect(relatedRows[1]["record_fingerprint"] as? [String: Any] != nil)
        let participants = try #require(
            relatedRows[1]["participating_notes"] as? [[String: Any]]
        )
        #expect(participants.contains {
            ($0["note_id"] as? String)?.lowercased()
                == fixture.analysisTarget.noteID.uuidString.lowercased()
        })

        let noRelatedRecords = try cli.run([
            "record", "list", "--note", fixture.workTarget.noteID.uuidString,
            "--triptych", triptych, "--format", "jsonl",
        ])
        let noRelatedRows = String(decoding: noRelatedRecords.stdout, as: UTF8.self)
            .split(separator: "\n")
        #expect(noRelatedRows.count == 1)
        let noRelatedSummary = try #require(
            JSONSerialization.jsonObject(with: Data(noRelatedRows[0].utf8))
                as? [String: Any]
        )
        #expect(noRelatedSummary["record_count"] as? Int == 0)

        let exactRecord = try cli.run([
            "record", "read", fixture.recordID.uuidString,
            "--triptych", triptych, "--format", "json",
        ])
        let recordEnvelope = try #require(
            JSONSerialization.jsonObject(with: exactRecord.stdout) as? [String: Any]
        )
        #expect(recordEnvelope["type"] as? String == "research_record")
        #expect(recordEnvelope["record_fingerprint"] as? [String: Any] != nil)
        let completeRecord = try #require(recordEnvelope["record"] as? [String: Any])
        #expect(
            (completeRecord["id"] as? String)?.lowercased()
                == fixture.recordID.uuidString.lowercased()
        )
        #expect(completeRecord["statements"] as? [[String: Any]] != nil)

        let missingRecord = try cli.runExpectingFailure([
            "record", "read", "00000000-0000-0000-0000-000000000001",
            "--triptych", triptych, "--format", "json",
        ])
        let missingRecordReport = try #require(
            JSONSerialization.jsonObject(with: missingRecord.stderr) as? [String: Any]
        )
        #expect(missingRecordReport["code"] as? String == "record_not_found")

        let missingNoteRecords = try cli.runExpectingFailure([
            "record", "list", "--note", "00000000-0000-0000-0000-000000000002",
            "--triptych", triptych, "--format", "jsonl",
        ])
        let missingNoteReport = try #require(
            JSONSerialization.jsonObject(with: missingNoteRecords.stderr) as? [String: Any]
        )
        #expect(missingNoteReport["code"] as? String == "note_not_found")

        let unreadableRecordURL = fixture.rootURL.appendingPathComponent(
            ".scholium/research-records/v1/records/00000000-0000-4000-8000-000000000003.json"
        )
        try Data("{\"schema_version\":17".utf8).write(
            to: unreadableRecordURL,
            options: .atomic
        )

        let partialSearch = try cli.run([
            "search", "kind:record synthetic", "--triptych", triptych,
            "--format", "jsonl",
        ])
        let partialSearchRows = try String(
            decoding: partialSearch.stdout,
            as: UTF8.self
        ).split(separator: "\n").map { line in
            try #require(
                JSONSerialization.jsonObject(with: Data(line.utf8))
                    as? [String: Any]
            )
        }
        let partialAvailability = try #require(
            partialSearchRows.first?["availability"] as? [String: Any]
        )
        #expect(partialAvailability["status"] as? String == "partial")
        #expect(partialSearchRows.dropFirst().contains {
            ($0["record_id"] as? String)?.lowercased()
                == fixture.recordID.uuidString.lowercased()
        })

        let partialList = try cli.run([
            "record", "list", "--note", fixture.analysisTarget.noteID.uuidString,
            "--triptych", triptych, "--format", "jsonl",
        ])
        let partialListRows = try String(
            decoding: partialList.stdout,
            as: UTF8.self
        ).split(separator: "\n").map { line in
            try #require(
                JSONSerialization.jsonObject(with: Data(line.utf8))
                    as? [String: Any]
            )
        }
        #expect(partialListRows.first?["corpus_complete"] as? Bool == false)
        #expect(partialListRows.count == 2)
        #expect(
            (partialListRows[1]["record_id"] as? String)?.lowercased()
                == fixture.recordID.uuidString.lowercased()
        )

        let readableNeighbor = try cli.run([
            "record", "read", fixture.recordID.uuidString,
            "--triptych", triptych, "--format", "json",
        ])
        #expect(readableNeighbor.stdout == exactRecord.stdout)

        let unresolvedPartialRecord = try cli.runExpectingFailure([
            "record", "read", "00000000-0000-0000-0000-000000000004",
            "--triptych", triptych, "--format", "json",
        ])
        let unresolvedPartialReport = try #require(
            JSONSerialization.jsonObject(with: unresolvedPartialRecord.stderr)
                as? [String: Any]
        )
        #expect(unresolvedPartialReport["code"] as? String == "unavailable")

        let negativeStructured = try cli.run([
            "search", "-has:broken-link", "--triptych", triptych,
            "--limit", "1", "--format", "jsonl",
        ])
        let negativeSummary = try #require(
            String(decoding: negativeStructured.stdout, as: UTF8.self)
                .split(separator: "\n")
                .first
        )
        let negativeRecord = try #require(
            JSONSerialization.jsonObject(with: Data(negativeSummary.utf8)) as? [String: Any]
        )
        #expect(negativeRecord["type"] as? String == "search_summary")
        #expect(negativeRecord["contract_version"] as? Int == SearchContract.currentVersion)
        let negativeResultLine = try #require(
            String(decoding: negativeStructured.stdout, as: UTF8.self)
                .split(separator: "\n")
                .dropFirst()
                .first
        )
        let negativeResult = try #require(
            JSONSerialization.jsonObject(with: Data(negativeResultLine.utf8))
                as? [String: Any]
        )
        let matchReasons = try #require(negativeResult["match_reasons"] as? [[String: Any]])
        #expect(matchReasons.first?["kind"] as? String == "structured")
        let structured = try #require(matchReasons.first?["structured"] as? [String: Any])
        #expect(structured["field"] as? String == "has")
        #expect(structured["value"] as? String == "broken-link")
        #expect(structured["excluded"] as? Bool == true)

        let typedFailure = try cli.runExpectingFailure([
            "search", "review:reviewed", "--triptych", triptych,
            "--format", "jsonl",
        ])
        let failureLines = String(decoding: typedFailure.stderr, as: UTF8.self)
            .split(separator: "\n")
        #expect(failureLines.count == 1)
        let failure = try #require(
            JSONSerialization.jsonObject(with: Data(failureLines[0].utf8))
                as? [String: Any]
        )
        #expect(failure["code"] as? String == "search_query_diagnostic")
        let diagnostic = try #require(failure["diagnostic"] as? [String: Any])
        #expect(diagnostic["code"] as? String == "unsupportedField")
        #expect(diagnostic["utf16_lower_bound"] as? Int == 0)
        #expect(diagnostic["utf16_upper_bound"] as? Int == 15)

        try cli.expectFailure(
            ["search", "review:reviewed", "--triptych", triptych],
            contains: "not supported by the current Search contract"
        )

        try cli.expectFailure(
            ["search", "role:analyses", "--triptych", triptych],
            contains: "outside the query"
        )
        try cli.expectFailure(
            ["search", "synthetic", "--workspace"],
            contains: "unknown option"
        )
        for unsupportedAlias in ["--record", "--property", "--relation"] {
            try cli.expectFailure(
                ["search", "synthetic", unsupportedAlias, "value", "--triptych", triptych],
                contains: "unknown option"
            )
        }
        try cli.expectFailure(
            ["search", "synthetic"],
            contains: "choose --vault"
        )
    }

    @Test("The real CLI submits one canonical Result and Continue request through the authenticated bridge")
    func agentResultAndContinuationCLI() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            ".build/m/\(String(UUID().uuidString.prefix(8)))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bridgeContainer) }

        let run = try #require(ResearchRunLocator(
            rawValue: "resultcontinueabcdefghij"
        ))
        let code = try #require(ResearchPairingCode(
            rawValue: "BCDEFGHJKLMNPQR23456789A"
        ))
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "r", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .critique
            }
        )
        var rawResults: [String: ResearchAcademicFieldValue] = [:]
        for definition in profile.academicResultFields
            where definition.requirement != .excluded {
            rawResults[definition.fieldID.rawValue] = switch definition.kind {
            case .freeText:
                .freeText("The fixture preserves one bounded philosophical assessment.")
            case .singleChoice:
                .singleChoice(try #require(definition.choices.first?.value))
            case .multipleChoice:
                .multipleChoice([try #require(definition.choices.first?.value)])
            }
        }
        let resultSubmission = try ResearchAgentResultSubmission(
            recordTitle: ResearchRecordTitle("CLI lifecycle result"),
            academicResults: ResearchAcademicFieldValues(
                rawValues: rawResults,
                definitions: profile.academicResultFields
            )
        )
        let continuation = try ResearchContinuationRequest(
            nextActionID: .write,
            targetRole: .work,
            targetRelativePath: "Draft Argument.md",
            academicPurpose: "Test one explicit premise in a separate Run.",
            handoff: [ResearchContinuationHandoffItem(
                content: "The prior assessment identifies one premise gap.",
                epistemicStatus: .agentReconstruction,
                nextUse: "Revise only if the current Work still has the gap."
            )]
        )
        let expectedReceipt = try ResearchAgentResultReceipt(
            disposition: .completed,
            state: .finalized,
            recordFormed: true,
            message: "The canonical Result formed one Research Record."
        )
        let expectedContinuation = try ResearchContinuationResult(
            state: .pendingResearcherDecision,
            message: "The bounded Continue request awaits researcher approval."
        )
        let observed = LockedAgentLifecycleRequests()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            guard request.run == run else {
                throw LocalAgentBridgeError.permissionDenied
            }
            switch request.operation {
            case .preflightAnalysisCreation, .start:
                throw LocalAgentBridgeError.invalidRequest
            case .pair:
                guard request.pairingCode == code else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .credential(credential)
            case .context:
                guard request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .context(try Self.minimalContext(
                    run: run,
                    actionID: .critique
                ))
            case .submitResult:
                guard request.credential == credential,
                      let submission = request.resultSubmission else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                observed.capture(result: submission)
                return .resultReceipt(expectedReceipt)
            case .continueResearch:
                guard request.credential == credential,
                      let continuation = request.continuationRequest else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                observed.capture(continuation: continuation)
                return .continuation(expectedContinuation)
            case .revokeSession, .query, .discussionReply,
                    .extendWriteSet, .writeDocument,
                    .writeZoteroBinding,
                    .resolveWriteConflict, .methodImprovementContext,
                    .submitMethodImprovement, .end:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        _ = try cli.run(
            ["agent", "pair", "--run", run.rawValue],
            stdin: Data((code.rawValue + "\n").utf8),
            environment: environment
        )
        let encoder = Self.encoder()
        let decoder = Self.decoder()
        let resultOutput = try cli.run(
            ["agent", "submit-result", "--run", run.rawValue, "--from", "-"],
            stdin: try encoder.encode(resultSubmission),
            environment: environment
        )
        let resultReceipt = try decoder.decode(
            ResearchAgentResultReceipt.self,
            from: resultOutput.stdout
        )
        #expect(resultReceipt == expectedReceipt)
        #expect(observed.result == resultSubmission)
        #expect(!String(decoding: resultOutput.stdout, as: UTF8.self).contains(
            credential.secret
        ))
        let credentialURL = fixture.homeURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Agent Sessions", isDirectory: true)
            .appendingPathComponent(run.rawValue + ".json")
        #expect(FileManager.default.fileExists(atPath: credentialURL.path))
        let storedCredential = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: credentialURL))
                as? [String: Any]
        )
        #expect(storedCredential["expires_at"] != nil)

        let continuationOutput = try cli.run(
            ["agent", "continue", "--run", run.rawValue, "--from", "-"],
            stdin: try encoder.encode(continuation),
            environment: environment
        )
        #expect(try decoder.decode(
            ResearchContinuationResult.self,
            from: continuationOutput.stdout
        ) == expectedContinuation)
        #expect(observed.continuation == continuation)
        #expect(!String(decoding: continuationOutput.stdout, as: UTF8.self).contains(
            credential.secret
        ))
        try cli.expectFailure(
            ["action", "complete", "--from", "-"],
            stdin: try encoder.encode(resultSubmission),
            contains: "Unknown command 'action complete'"
        )
    }

    @Test("The CLI prunes only exact expired Session credentials without an Agent cleanup command")
    func expiredCredentialPruningIsAutomaticAndBounded() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = fixture.rootURL.appendingPathComponent(
            "credential-pruning-bridge",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        let expiredRun = try #require(ResearchRunLocator(
            rawValue: "expiredcredentialrunabcd"
        ))
        let currentRun = try #require(ResearchRunLocator(
            rawValue: "currentcredentialrunabcd"
        ))
        let expiredCode = try #require(ResearchPairingCode(
            rawValue: "23456789ABCDEFGHJKLMNPQR"
        ))
        let currentCode = try #require(ResearchPairingCode(
            rawValue: "RQPNMLKJHGFEDCBA98765432"
        ))
        let expiredCredential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "e", count: 48),
            expiresAt: Date().addingTimeInterval(-60)
        )
        let currentCredential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "c", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            switch request.operation {
            case .pair:
                if request.run == expiredRun,
                   request.pairingCode == expiredCode {
                    return .credential(expiredCredential)
                }
                if request.run == currentRun,
                   request.pairingCode == currentCode {
                    return .credential(currentCredential)
                }
                throw LocalAgentBridgeError.permissionDenied
            case .context:
                if request.run == expiredRun,
                   request.credential == expiredCredential {
                    return .context(try Self.minimalContext(
                        run: expiredRun,
                        actionID: .critique
                    ))
                }
                if request.run == currentRun,
                   request.credential == currentCredential {
                    return .context(try Self.minimalContext(
                        run: currentRun,
                        actionID: .critique
                    ))
                }
                throw LocalAgentBridgeError.permissionDenied
            default:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        _ = try cli.run(
            ["agent", "pair", "--run", expiredRun.rawValue],
            stdin: Data((expiredCode.rawValue + "\n").utf8),
            environment: environment
        )
        let sessionsURL = fixture.homeURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Agent Sessions", isDirectory: true)
        let expiredURL = sessionsURL.appendingPathComponent(
            expiredRun.rawValue + ".json"
        )
        #expect(FileManager.default.fileExists(atPath: expiredURL.path))

        let malformedURL = sessionsURL.appendingPathComponent("malformed.json")
        try Data("not a credential".utf8).write(to: malformedURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: malformedURL.path
        )
        let symlinkTarget = fixture.rootURL.appendingPathComponent("outside.txt")
        try Data("leave untouched".utf8).write(to: symlinkTarget)
        let symlinkURL = sessionsURL.appendingPathComponent("unsafe.json")
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: symlinkTarget
        )

        _ = try cli.run(
            ["agent", "pair", "--run", currentRun.rawValue],
            stdin: Data((currentCode.rawValue + "\n").utf8),
            environment: environment
        )
        #expect(!FileManager.default.fileExists(atPath: expiredURL.path))
        #expect(FileManager.default.fileExists(atPath: malformedURL.path))
        #expect(FileManager.default.fileExists(atPath: symlinkURL.path))
        #expect(try String(contentsOf: symlinkTarget, encoding: .utf8)
            == "leave untouched")
        #expect(FileManager.default.fileExists(
            atPath: sessionsURL.appendingPathComponent(
                currentRun.rawValue + ".json"
            ).path
        ))
    }

    @Test("The real CLI exposes true Run drift as structured stale_run")
    func agentReloadStaleCLI() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            ".build/m/\(String(UUID().uuidString.prefix(8)))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bridgeContainer) }

        let run = try #require(ResearchRunLocator(
            rawValue: "stalerunabcdefghijklmnop"
        ))
        let code = try #require(ResearchPairingCode(
            rawValue: "BCDEFGHJKLMNPQR23456789A"
        ))
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "s", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let contextRequests = LockedCounter()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            switch request.operation {
            case .pair:
                guard request.run == run,
                      request.pairingCode == code else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .credential(credential)
            case .context:
                guard request.run == run,
                      request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                if contextRequests.increment() == 1 {
                    return .context(try Self.minimalContext(
                        run: run,
                        actionID: .critique
                    ))
                }
                throw ResearchAgentConnectionError.runStale(.targetChanged)
            default:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        _ = try cli.run(
            ["agent", "pair", "--run", run.rawValue],
            stdin: Data((code.rawValue + "\n").utf8),
            environment: environment
        )
        let failure = try cli.runExpectingFailure(
            ["agent", "reload", "--run", run.rawValue],
            environment: environment
        )
        let report = try #require(
            JSONSerialization.jsonObject(with: failure.stderr) as? [String: Any]
        )
        #expect(report["code"] as? String == "stale_run")
        #expect(report["schema_version"] as? Int == 2)
        #expect((report["message"] as? String)?.contains(
            "start a new Action"
        ) == true)
        #expect(report["command"] as? String == "agent reload")
        let recovery = try #require(report["recovery"] as? [String: Any])
        #expect(recovery["safe_to_retry"] as? Bool == false)
        #expect(recovery["must_reuse_request_identity"] as? Bool == false)
        #expect(recovery["next_step"] as? String
            == "start_new_action_from_current_revision")
    }

    @Test("Initial context delivery failure retains one paired Session for reload")
    func initialContextFailureReloadsWithoutRePairing() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = fixture.rootURL.appendingPathComponent(
            "initial-context-reload-bridge",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        let run = try #require(ResearchRunLocator(
            rawValue: "initialcontextreloadrun"
        ))
        let code = try #require(ResearchPairingCode(
            rawValue: "BCDEFGHJKLMNPQR23456789A"
        ))
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "i", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let pairingRequests = LockedCounter()
        let contextRequests = LockedCounter()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            switch request.operation {
            case .pair:
                guard request.run == run,
                      request.pairingCode == code else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                _ = pairingRequests.increment()
                return .credential(credential)
            case .context:
                guard request.run == run,
                      request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                if contextRequests.increment() == 1 {
                    throw LocalAgentBridgeError.unavailable
                }
                return .context(try Self.minimalContext(
                    run: run,
                    actionID: .critique
                ))
            default:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        let failedPair = try cli.runExpectingFailure(
            ["agent", "pair", "--run", run.rawValue],
            stdin: Data((code.rawValue + "\n").utf8),
            environment: environment
        )
        let report = try #require(
            JSONSerialization.jsonObject(with: failedPair.stderr)
                as? [String: Any]
        )
        #expect(report["code"] as? String == "initial_context_unavailable")
        let recovery = try #require(report["recovery"] as? [String: Any])
        #expect(recovery["safe_to_retry"] as? Bool == true)
        #expect(recovery["next_step"] as? String == "reload_current_run")
        let credentialURL = fixture.homeURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Agent Sessions", isDirectory: true)
            .appendingPathComponent(run.rawValue + ".json")
        #expect(FileManager.default.fileExists(atPath: credentialURL.path))

        let reloaded = try cli.run(
            ["agent", "reload", "--run", run.rawValue],
            environment: environment
        )
        #expect(try Self.decoder().decode(
            ResearchAuthenticatedRunContext.self,
            from: reloaded.stdout
        ).brief.run == run)
        #expect(pairingRequests.count == 1)
        #expect(contextRequests.count == 2)
    }

    @Test("A credential-store failure revokes the new Session and preserves the Run recovery route")
    func credentialStoreFailureRevokesNewSession() throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let root = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
            .appendingPathComponent(
                "ScholiumAgentSessionFailure-\(UUID().uuidString)",
                isDirectory: true
            )
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bridgeContainer = root.appendingPathComponent("bridge", isDirectory: true)
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let run = try #require(
            ResearchRunLocator(rawValue: "sessionstorefailurerecovery")
        )
        let pairingCode = try #require(
            ResearchPairingCode(rawValue: "23456789ABCDEFGHJKLMNPQR")
        )
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "r", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let sessionsURL = home
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Agent Sessions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionsURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let revokedCredential = LockedRevokedCredential()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            switch request.operation {
            case .pair:
                guard request.run == run,
                      request.pairingCode == pairingCode,
                      FileManager.default.fileExists(atPath: sessionsURL.path) else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                try FileManager.default.removeItem(at: sessionsURL)
                try Data("occupied".utf8).write(to: sessionsURL)
                return .credential(credential)
            case .revokeSession:
                guard request.run == nil,
                      request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                revokedCredential.capture(request.credential)
                return .sessionRevoked(ResearchAgentSessionRevocationReceipt(
                    sessionID: credential.sessionID
                ))
            default:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: home)
        let result = try cli.runExpectingFailure(
            ["agent", "pair", "--run", run.rawValue],
            stdin: Data((pairingCode.rawValue + "\n").utf8),
            environment: [
                "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
            ]
        )
        let report = try #require(
            JSONSerialization.jsonObject(with: result.stderr) as? [String: Any]
        )
        let recovery = try #require(report["recovery"] as? [String: Any])
        #expect(report["code"] as? String == "session_store_unavailable")
        #expect(recovery["safe_to_retry"] as? Bool == false)
        #expect(recovery["must_reuse_request_identity"] as? Bool == true)
        #expect(
            recovery["next_step"] as? String
                == "copy_new_handoff_and_pair_same_run"
        )
        #expect((report["message"] as? String)?.contains(run.rawValue) == true)
        #expect(!String(decoding: result.stderr, as: UTF8.self).contains(credential.secret))
        #expect(revokedCredential.value == credential)
    }

    @Test("A direct-start credential-store failure revokes its Session and retains the Run")
    func directStartCredentialStoreFailureRevokesNewSession() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = fixture.rootURL.appendingPathComponent(
            "start-session-store-failure-bridge",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        let run = try #require(
            ResearchRunLocator(rawValue: "startsessionstorefailure")
        )
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "d", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let request = try ResearchAgentStartRequest(
            actionID: .analyze,
            target: fixture.analysisTarget.note,
            sourceRoute: .researcherProvided
        )
        let receipt = try ResearchAgentStartReceipt(
            run: run,
            actionID: .analyze,
            target: fixture.analysisTarget,
            state: .prepared,
            message: "The Agent-originated Run is active."
        )
        let sessionsURL = fixture.homeURL
            .appendingPathComponent("ApplicationSupport", isDirectory: true)
            .appendingPathComponent("Agent Sessions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sessionsURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let revokedCredential = LockedRevokedCredential()
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { bridgeRequest in
            switch bridgeRequest.operation {
            case .start:
                guard bridgeRequest.triptychID == fixture.assignment.id,
                      bridgeRequest.startRequest == request,
                      FileManager.default.fileExists(atPath: sessionsURL.path) else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                try FileManager.default.removeItem(at: sessionsURL)
                try Data("occupied".utf8).write(to: sessionsURL)
                return .started(receipt: receipt, credential: credential)
            case .revokeSession:
                guard bridgeRequest.credential == credential,
                      bridgeRequest.run == nil else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                revokedCredential.capture(bridgeRequest.credential)
                return .sessionRevoked(ResearchAgentSessionRevocationReceipt(
                    sessionID: credential.sessionID
                ))
            default:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let result = try cli.runExpectingFailure(
            [
                "agent", "start", "--triptych",
                fixture.assignment.id.uuidString, "--from", "-",
            ],
            stdin: try JSONEncoder().encode(request),
            environment: [
                "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
            ]
        )
        let report = try #require(
            JSONSerialization.jsonObject(with: result.stderr) as? [String: Any]
        )
        let recovery = try #require(report["recovery"] as? [String: Any])
        #expect(report["code"] as? String == "session_store_unavailable")
        #expect(
            recovery["next_step"] as? String
                == "copy_new_handoff_and_pair_same_run"
        )
        #expect((report["message"] as? String)?.contains(run.rawValue) == true)
        #expect(!String(decoding: result.stderr, as: UTF8.self).contains(
            credential.secret
        ))
        #expect(revokedCredential.value == credential)
    }


    @Test("Help, version, doctor, and strict parsing work without a configured Triptych")
    func discoveryAndStrictParsing() throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-cli-discovery-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = ActionCLIProcess(binaryPath: binaryPath, home: root)

        let version = try cli.run(["version", "--format", "json"])
        let versionObject = try #require(
            JSONSerialization.jsonObject(with: version.stdout) as? [String: Any]
        )
        #expect(
            versionObject["cli_version"] as? String
                == ScholiumProductIdentity.marketingVersion
        )
        #expect(versionObject["release_label"] as? String == "development")
        #expect(versionObject["build_number"] as? String == "0")
        let help = try cli.run([
            "help", "agent", "start", "--format", "json",
        ])
        #expect(String(decoding: help.stdout, as: UTF8.self).contains("agent start"))
        let updateHelp = try cli.run(["help", "update"])
        #expect(String(decoding: updateHelp.stdout, as: UTF8.self).contains(
            "scholium update [--check]"
        ))
        let retiredCommand = ["biblio", "graphy"].joined()
        let rootHelp = try cli.run(["help"])
        let rootHelpText = String(decoding: rootHelp.stdout, as: UTF8.self)
        #expect(!rootHelpText.contains(retiredCommand))
        #expect(!rootHelpText.contains("prepare-fidelity"))
        #expect(!rootHelpText.contains("scholium action prepare"))
        try cli.expectFailure(
            ["help", "action"],
            contains: "Unknown help topic 'action'"
        )
        let resultHelp = try cli.run([
            "help", "agent", "submit-result", "--format", "json",
        ])
        let resultHelpText = String(decoding: resultHelp.stdout, as: UTF8.self)
        #expect(resultHelpText.contains("issues_found"))
        #expect(resultHelpText.contains("findings"))
        #expect(resultHelpText.contains("academic_results {values:{}}"))
        try cli.expectFailure([retiredCommand], contains: "Unknown command")
        let doctor = try cli.run(["doctor", "--format", "json"])
        #expect(String(decoding: doctor.stdout, as: UTF8.self).contains("triptych_count"))
        try cli.expectFailure(
            ["skills", "catalog", "--format", "json"],
            contains: "Unknown command 'skills catalog'"
        )
        try cli.expectFailure(
            ["workflow", "validate", "--from", "-", "--format", "json"],
            contains: "Unknown command 'workflow validate'"
        )
        try cli.expectFailure(
            ["update", "--format", "yaml"],
            contains: "Update supports --format text or json"
        )
        let updateFailure = try cli.runExpectingFailure(["update", "--format", "json"])
        let updateReport = try #require(
            JSONSerialization.jsonObject(with: updateFailure.stderr) as? [String: Any]
        )
        #expect(updateReport["code"] as? String == "invalid_installation")
        #expect(updateReport["command"] as? String == "update")
        #expect(updateReport["help"] as? String == "scholium help update")
    }

    @Test("The real CLI fills Method-improvement revisions from authenticated context and submits one bounded target")
    func agentMethodImprovementCLI() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }
        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let bridgeContainer = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            ".build/m/\(String(UUID().uuidString.prefix(8)))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeContainer,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bridgeContainer) }

        let locator = try #require(ResearchRunLocator(
            rawValue: "methodimprovementrunabcd"
        ))
        let code = try #require(ResearchPairingCode(
            rawValue: "ABCDEFGHJKLMNPQR23456789"
        ))
        let credential = try ResearchConnectionCredential(
            sessionID: UUID(),
            secret: String(repeating: "m", count: 48),
            expiresAt: Date().addingTimeInterval(3_600)
        )
        let registration = try ResearchSkillRegistration(
            actionID: .synthesize,
            displayName: "Synthesis Method",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Synthesis Method\n"
        )
        let improvement = try ResearchMethodImprovementRun(
            id: UUID(),
            parentRecordID: UUID(),
            triptychID: UUID(),
            registrationKey: registration.key,
            actionID: .synthesize,
            method: method,
            feedbackRevision: UUID(),
            feedbackText: "Clarify how rival formulations remain visible.",
            expectedResultFingerprint: DocumentFingerprint(content: "result")
        )
        let context = try ResearchMethodImprovementContext(
            run: locator,
            improvement: improvement
        )
        let replacement = "# Revised Synthesis Method\n"
        let expectedReceipt = try ResearchMethodImprovementReceipt(
            runID: improvement.id,
            requestID: UUID(),
            disposition: .replace,
            targetID: "primary-method",
            startingRevision: method.primaryMarkdownRevision,
            endingRevision: DocumentFingerprint(content: replacement),
            feedbackCleared: true,
            diagnosis: "The primary Method needs one bounded clarification."
        )
        let observed = LockedMethodImprovementSubmission()
        let endReceipt = try ResearchRunEndReceipt(
            run: locator,
            recoveryRetained: false,
            message: "The Method improvement Run ended."
        )
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { request in
            guard request.run == locator else {
                throw LocalAgentBridgeError.permissionDenied
            }
            switch request.operation {
            case .preflightAnalysisCreation, .start:
                throw LocalAgentBridgeError.invalidRequest
            case .pair:
                guard request.pairingCode == code else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .credential(credential)
            case .context, .methodImprovementContext:
                guard request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .methodImprovementContext(context)
            case .submitMethodImprovement:
                guard request.credential == credential,
                      let submission = request.methodImprovementSubmission else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                observed.capture(submission)
                return .methodImprovementReceipt(try ResearchMethodImprovementReceipt(
                    runID: expectedReceipt.runID,
                    requestID: submission.requestID,
                    disposition: expectedReceipt.disposition,
                    targetID: expectedReceipt.targetID,
                    startingRevision: expectedReceipt.startingRevision,
                    endingRevision: expectedReceipt.endingRevision,
                    feedbackCleared: expectedReceipt.feedbackCleared,
                    diagnosis: expectedReceipt.diagnosis,
                    completedAt: expectedReceipt.completedAt
                ))
            case .end:
                guard request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .endReceipt(endReceipt)
            case .revokeSession, .query, .discussionReply,
                    .extendWriteSet, .writeDocument,
                    .writeZoteroBinding,
                    .resolveWriteConflict, .submitResult, .continueResearch:
                throw LocalAgentBridgeError.invalidRequest
            }
        }
        defer { server.stop() }

        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let environment = [
            "SCHOLIUM_AGENT_BRIDGE_CONTAINER": bridgeContainer.path,
        ]
        let paired = try cli.run(
            ["agent", "pair", "--run", locator.rawValue],
            stdin: Data((code.rawValue + "\n").utf8),
            environment: environment
        )
        let pairObject = try #require(
            JSONSerialization.jsonObject(with: paired.stdout) as? [String: Any]
        )
        #expect(pairObject["context_kind"] as? String == "method_improvement")
        let pairedContext = try #require(pairObject["context"])
        #expect(try Self.decoder().decode(
            ResearchMethodImprovementContext.self,
            from: JSONSerialization.data(withJSONObject: pairedContext)
        ) == context)
        let loaded = try cli.run(
            ["agent", "method-context", "--run", locator.rawValue],
            environment: environment
        )
        #expect(try Self.decoder().decode(
            ResearchMethodImprovementContext.self,
            from: loaded.stdout
        ) == context)
        let draft = try ResearchMethodImprovementDraft(
            targetID: "primary-method",
            disposition: .replace,
            replacementSource: replacement,
            diagnosis: expectedReceipt.diagnosis
        )
        let submitted = try cli.run(
            ["agent", "improve-method", "--run", locator.rawValue, "--from", "-"],
            stdin: try Self.encoder().encode(draft),
            environment: environment
        )
        let receipt = try Self.decoder().decode(
            ResearchMethodImprovementReceipt.self,
            from: submitted.stdout
        )
        #expect(receipt.feedbackCleared)
        let captured = try #require(observed.value)
        #expect(captured.feedbackRevision == context.feedbackRevision)
        #expect(captured.expectedResultFingerprint
            == context.expectedResultFingerprint)
        #expect(captured.expectedTargetRevision
            == method.primaryMarkdownRevision)
        #expect(captured.replacementSource == replacement)
        #expect(!String(decoding: submitted.stdout, as: UTF8.self).contains(
            credential.secret
        ))
        _ = try cli.run(
            ["agent", "end", "--run", locator.rawValue],
            environment: environment
        )
    }

    private static func startActionThroughCLI(
        _ actionID: ResearchActionID,
        target: ResearchActionNoteSnapshot,
        triptychID: UUID,
        cli: ActionCLIProcess,
        environment: [String: String],
        sourceRoute: ResearchAgentSourceRoute? = nil
    ) async throws -> (
        receipt: ResearchAgentStartReceipt,
        context: ResearchAuthenticatedRunContext
    ) {
        let request = try ResearchAgentStartRequest(
            actionID: actionID,
            target: target.note,
            academicInputs: [
                "research-request": .freeText(
                    "Execute the \(actionID.rawValue) Action against only this disposable fixture."
                ),
            ],
            sourceRoute: sourceRoute
        )
        let startOutput = try cli.run(
            ["agent", "start", "--triptych", triptychID.uuidString,
             "--from", "-"],
            stdin: try encoder().encode(request),
            environment: environment
        )
        let report = try decoder().decode(
            CLIAgentStartReport.self,
            from: startOutput.stdout
        )
        let receipt = report.receipt
        #expect(receipt.actionID == actionID)
        #expect(receipt.target.noteID == target.noteID)
        let context = report.context
        #expect(context.brief.actionID == actionID)
        #expect(context.nextActions.contains {
            actionID == .discuss
                ? $0.kind == .reply
                : $0.kind == .submitResult
        })
        return (receipt, context)
    }

    private static func simulatedResult(
        action: ResearchActionID,
        context: ResearchAuthenticatedRunContext
    ) throws -> ResearchAgentResultSubmission {
        let academicResults: ResearchAcademicFieldValues
        let fidelityOutcomes: [FidelityCheckOutcome]
        if action == .checkFidelity {
            academicResults = try ResearchAcademicFieldValues(
                rawValues: [:],
                definitions: []
            )
            let contract = try #require(context.fidelityContract)
            fidelityOutcomes = contract.checks
                .sorted { $0.rawValue < $1.rawValue }
                .map { check in
                    let unavailable = contract.requiredUnavailableChecks
                        .contains(check)
                    return FidelityCheckOutcome(
                        check: check,
                        state: unavailable ? .unavailable : .passed,
                        summary: unavailable
                            ? (contract.evidenceLimitation
                                ?? "The simulated Run has no formal source envelope for this check.")
                            : "The external CLI simulation found no inconsistency in the disposable checked scope."
                    )
                }
        } else {
            var rawValues: [String: ResearchAcademicFieldValue] = [:]
            for definition in context.resultContract.academicFields
                where definition.requirement == .required {
                rawValues[definition.fieldID.rawValue] = switch definition.kind {
                case .freeText:
                    .freeText(
                        "Bounded external CLI simulation result for \(definition.label)."
                    )
                case .singleChoice:
                    .singleChoice(try #require(definition.choices.first?.value))
                case .multipleChoice:
                    .multipleChoice([try #require(definition.choices.first?.value)])
                }
            }
            academicResults = try ResearchAcademicFieldValues(
                rawValues: rawValues,
                definitions: context.resultContract.academicFields
            )
            try ResearchAcademicProfileCatalog.validatePlatformResultRules(
                academicResults,
                actionID: action
            )
            fidelityOutcomes = []
        }
        return try ResearchAgentResultSubmission(
            recordTitle: ResearchRecordTitle(
                "External CLI \(action.rawValue) simulation"
            ),
            academicResults: academicResults,
            fidelityOutcomes: fidelityOutcomes,
            literatureRecommendations: action == .analyze ? [] : nil
        )
    }

    private static func executeEvidenceQueriesThroughCLI(
        context: ResearchAuthenticatedRunContext,
        cli: ActionCLIProcess,
        environment: [String: String]
    ) throws {
        let evidenceActions = context.nextActions.filter {
            $0.kind == .query
                && ($0.requirement == .required
                    || $0.label.contains("Search the current Triptych"))
        }
        #expect(evidenceActions.contains {
            $0.requirement == .required
                && $0.label.contains("exact current Target revision")
        })
        #expect(evidenceActions.contains {
            $0.requirement == .whenNeeded
                && $0.label.contains("Search the current Triptych")
        })
        for action in evidenceActions {
            let template = try #require(action.inputTemplate)
                .replacingOccurrences(
                    of: "REPLACE_WITH_BOUNDED_SEARCH_QUERY",
                    with: "synthetic"
                )
            let arguments = Array(action.command.dropFirst())
            let output = try cli.run(
                arguments,
                stdin: Data(template.utf8),
                environment: environment
            )
            let response = try decoder().decode(
                ResearchContextResponse.self,
                from: output.stdout
            )
            #expect(!response.outcomes.isEmpty)
        }
    }

    private static func verifyExternalInstructionDelivery(
        actionID: ResearchActionID,
        run: ResearchRunLocator,
        context: ResearchAuthenticatedRunContext,
        deployedSkills: URL,
        cli: ActionCLIProcess,
        environment: [String: String]
    ) throws {
        let registeredCore = deployedSkills
            .appendingPathComponent("scholium-core-protocol", isDirectory: true)
        let protocolFiles = [
            "SKILL.md",
            "references/runtime-kernel.md",
            "references/project-entry.md",
            "references/active-run.md",
            "references/mutation-recovery.md",
            "references/completion.md",
            "references/workspace-bootstrap.md",
            "references/analyze-result.md",
            "references/synthesize-result.md",
            "references/write-result.md",
            "references/critique-result.md",
            "references/check-fidelity-result.md",
            "references/discuss-result.md",
        ]
        let receivedCore = try protocolFiles.map { relativePath in
            try String(
                contentsOf: registeredCore.appendingPathComponent(relativePath),
                encoding: .utf8
            )
        }.joined(separator: "\n")
        let normalizedCore = receivedCore
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        #expect(normalizedCore.contains(
            "state-gated protocol modules, not Agent-selected Modes"
        ))
        #expect(normalizedCore.contains(
            "Follow each typed `next_actions` requirement."
        ))
        #expect(normalizedCore.contains(
            "Calling a query is not evidence that returned material was read, relied on, or supports the Result"
        ))
        #expect(normalizedCore.contains(
            "a finalized Result needs no extra end operation"
        ))
        #expect(!FileManager.default.fileExists(
            atPath: registeredCore
                .appendingPathComponent("references/runtime-protocol.md").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: registeredCore
                .appendingPathComponent("references/mixed-mode.md").path
        ))

        let skillName = actionID.projectSkillName
        let registeredMethod = deployedSkills
            .appendingPathComponent(skillName, isDirectory: true)
            .appendingPathComponent("SKILL.md")
        let receivedMethod = try String(
            contentsOf: registeredMethod,
            encoding: .utf8
        )
        #expect(receivedMethod.contains("name: \(skillName)"))
        let methodRequirement = try #require(context.requiredSkills.first {
            $0.kind == .actionMethod
        })
        #expect(methodRequirement.name == skillName)
        #expect(methodRequirement.primaryMarkdownRevision
            == DocumentFingerprint(content: receivedMethod))
        #expect(context.requiredSkills.contains(.coreProtocol))
        #expect(context.requiredSkills.contains {
            $0.name == skillName
        })
        #expect(FileManager.default.fileExists(atPath: deployedSkills
            .appendingPathComponent("general-research-helper/SKILL.md").path))
        let serializedContext = String(
            decoding: try encoder().encode(context),
            as: UTF8.self
        )
        #expect(!serializedContext.contains(receivedCore))
        #expect(!serializedContext.contains(receivedMethod))
        #expect(!serializedContext.contains(deployedSkills.path))

        let reload = try cli.run(
            ["agent", "reload", "--run", run.rawValue],
            environment: environment
        )
        let reloaded = try decoder().decode(
            ResearchAuthenticatedRunContext.self,
            from: reload.stdout
        )
        #expect(reloaded.requiredSkills == context.requiredSkills)
        #expect(reloaded.brief.actionID == actionID)
    }

    private static func deployExternalAgentWorkspace(
        triptychID: UUID,
        fixtureRoot: URL,
        cli: ActionCLIProcess,
        environment: [String: String]
    ) throws -> URL {
        let output = try cli.run(
            ["workspace", "skill-sources", "--triptych", triptychID.uuidString,
             "--format", "json"],
            environment: environment
        )
        let manifest = try decoder().decode(
            WorkspaceSkillSourceManifest.self,
            from: output.stdout
        )
        #expect(manifest.triptychID == triptychID)
        #expect(Set(manifest.skills.filter {
            $0.ownership == .scholiumManaged
        }.map(\.name)) == Set(ResearchSystemSkillID.allCases.map(\.rawValue)))
        #expect(Set(manifest.skills.compactMap(\.actionID))
            == Set(ResearchActionID.allCases))

        let skills = fixtureRoot
            .appendingPathComponent("External Agent Workspace", isDirectory: true)
            .appendingPathComponent(".agents/skills", isDirectory: true)
        try FileManager.default.createDirectory(
            at: skills,
            withIntermediateDirectories: true
        )
        let general = skills.appendingPathComponent(
            "general-research-helper",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: general,
            withIntermediateDirectories: true
        )
        try Data("# General Research Helper\n".utf8).write(
            to: general.appendingPathComponent("SKILL.md")
        )
        for source in manifest.skills {
            try FileManager.default.createSymbolicLink(
                at: skills.appendingPathComponent(source.name, isDirectory: true),
                withDestinationURL: URL(
                    fileURLWithPath: source.sourceDirectory,
                    isDirectory: true
                )
            )
        }
        return skills
    }

    private static func recordActionsThroughCLI(
        noteID: UUID,
        triptychID: UUID,
        cli: ActionCLIProcess
    ) throws -> [ResearchActionID] {
        let output = try cli.run([
            "record", "list", "--note", noteID.uuidString,
            "--triptych", triptychID.uuidString, "--format", "jsonl",
        ])
        return try String(decoding: output.stdout, as: UTF8.self)
            .split(separator: "\n")
            .dropFirst()
            .compactMap { line in
                let row = try #require(
                    JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any]
                )
                guard let rawAction = row["action_id"] as? String else {
                    return nil
                }
                return ResearchActionID(rawValue: rawAction)
            }
    }

    private static func fixtureDocumentURL(
        root: URL,
        target: ResearchActionNoteSnapshot
    ) -> URL {
        let directory = switch target.role {
        case .analysis: "Analyses"
        case .topic: "Topics"
        case .work: "Works"
        }
        return root.appendingPathComponent(directory, isDirectory: true)
            .appendingPathComponent(target.note.relativePath)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func minimalContext(
        run: ResearchRunLocator,
        actionID: ResearchActionID
    ) throws -> ResearchAuthenticatedRunContext {
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == actionID
            }
        )
        let registration = try ResearchSkillRegistration(
            actionID: actionID,
            displayName: "Fixture Method",
            primaryMarkdown: .machineLocal()
        )
        let method = try ResearchMethodSnapshot(
            registration: registration,
            primaryMarkdownSource: "# Fixture Method\n"
        )
        let recommendedReading: ResearchRecommendedReadingDirectory?
        if actionID == .synthesize || actionID == .write
            || actionID == .critique {
            recommendedReading = try ResearchRecommendedReadingDirectory(
                seedFingerprint: DocumentFingerprint(content: "fixture Work"),
                freshnessToken: SearchFreshnessToken(
                    "related-content:unavailable"
                ),
                state: .unavailable,
                candidates: [],
                hasMore: false,
                limitation: "Recommended Reading is unavailable in this isolated CLI fixture."
            )
        } else {
            recommendedReading = nil
        }
        return try ResearchAuthenticatedRunContext(
            brief: ResearchRunBrief(
                run: run,
                actionID: actionID,
                state: .prepared,
                initialObjectTitle: "Fixture",
                initialObjectRole: actionID == .analyze ? .analysis : .work,
                academicPurpose: nil,
                capabilities: ResearchRunCapabilityAvailability(
                    search: true,
                    read: true,
                    relations: true,
                    metadata: true,
                    records: true,
                    researchState: true,
                    zotero: true,
                    writeInitialObject: false,
                    extendWriteSet: false
                )
            ),
            requiredSkills: try requiredSkills(for: method),
            resultContract: try ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: try profile.contentRevision()
            ),
            boundedWriteSet: [],
            recommendedReading: recommendedReading
        )
    }

    private static func requiredSkills(
        for method: ResearchMethodSnapshot
    ) throws -> [ResearchRequiredSkill] {
        var skills: [ResearchRequiredSkill] = [.coreProtocol]
        if method.registration.actionID == .discuss {
            skills.append(try .systemAdapter(.discussionProtocol))
        }
        skills.append(try .actionMethod(method))
        return skills
    }

    private static func readPayload(_ data: Data) throws -> CLIReadPayload {
        try JSONDecoder().decode(CLIReadPayload.self, from: data)
    }

    private static func actionRequest(
        actionID: ResearchActionID,
        target: ResearchActionNoteSnapshot,
        availability: [ResearchActionAvailability],
        instruction: String? = nil
    ) throws -> ResearchActionExecutionRequest {
        let repairReasons = availability.first { $0.id == actionID }?.repairReasons ?? []
        let presented = try #require(availability.first {
            $0.id == actionID && $0.isEnabled
        }, "Expected enabled \(actionID.rawValue); repair reasons: \(repairReasons)")
        var values: [ResearchAcademicFieldID: ResearchAcademicFieldValue] = [:]
        if let instruction,
           let field = presented.profile.profile.academicInputFields.first(where: {
               $0.kind == .freeText
           }) {
            values[field.fieldID] = .freeText(instruction)
        }
        return ResearchActionExecutionRequest(
            actionID: actionID,
            expectedProfileRevision: presented.profile.profileRevision,
            expectedProfileDocumentRevision:
                presented.profile.profileDocumentRevision,
            target: target,
            platformInputs: try ResearchActionPlatformInputs(),
            academicInputs: try ResearchAcademicFieldValues(
                values: values,
                definitions: presented.profile.profile.academicInputFields
            )
        )
    }

}

private struct CLIReadPayload: Decodable {
    let sha256: String
    let content: String
}

private struct CLIAgentStartReport: Decodable {
    let receipt: ResearchAgentStartReceipt
    let context: ResearchAuthenticatedRunContext
}

private struct CLIAgentPairingReport: Decodable {
    let paired: Bool
    let run: ResearchRunLocator
    let context: ResearchAuthenticatedRunContext
}

private struct CLICancellationReport: Decodable {
    let runID: UUID
}

private final class LockedAgentWriteRequestIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID] = []

    var values: [UUID] { lock.withLock { storage } }

    func append(_ value: UUID) {
        lock.withLock { storage.append(value) }
    }
}

private final class LockedAgentLifecycleRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: ResearchAgentResultSubmission?
    private var storedContinuation: ResearchContinuationRequest?

    var result: ResearchAgentResultSubmission? {
        lock.withLock { storedResult }
    }

    var continuation: ResearchContinuationRequest? {
        lock.withLock { storedContinuation }
    }

    func capture(result: ResearchAgentResultSubmission) {
        lock.withLock { storedResult = result }
    }

    func capture(continuation: ResearchContinuationRequest) {
        lock.withLock { storedContinuation = continuation }
    }
}

private final class LockedMethodImprovementSubmission: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ResearchMethodImprovementSubmission?

    var value: ResearchMethodImprovementSubmission? {
        lock.withLock { stored }
    }

    func capture(_ submission: ResearchMethodImprovementSubmission) {
        lock.withLock { stored = submission }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private final class LockedRevokedCredential: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ResearchConnectionCredential?

    var value: ResearchConnectionCredential? {
        lock.withLock { stored }
    }

    func capture(_ credential: ResearchConnectionCredential?) {
        lock.withLock { stored = credential }
    }
}

private struct ActionCLIProcess {
    struct Result {
        let stdout: Data
        let stderr: Data
        let status: Int32
    }

    let binaryPath: String
    let home: URL

    func run(
        _ arguments: [String],
        stdin: Data? = nil,
        environment additionalEnvironment: [String: String] = [:]
    ) throws -> Result {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "SCHOLIUM_HOME": home.path,
        ]) { _, isolated in isolated }.merging(additionalEnvironment) {
            _, explicit in explicit
        }
        process.standardOutput = output
        process.standardError = errors
        if stdin != nil { process.standardInput = input }
        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(stdin)
            try input.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        let result = Result(
            stdout: output.fileHandleForReading.readDataToEndOfFile(),
            stderr: errors.fileHandleForReading.readDataToEndOfFile(),
            status: process.terminationStatus
        )
        guard result.status == 0 else {
            throw ActionCLIProcessError.failed(
                arguments,
                String(decoding: result.stderr, as: UTF8.self)
            )
        }
        return result
    }

    func expectFailure(
        _ arguments: [String],
        stdin: Data? = nil,
        environment: [String: String] = [:],
        contains expected: String
    ) throws {
        let result = try runExpectingFailure(
            arguments,
            stdin: stdin,
            environment: environment
        )
        let stderr = String(decoding: result.stderr, as: UTF8.self)
        #expect(stderr.localizedCaseInsensitiveContains(expected))
    }

    func runExpectingFailure(
        _ arguments: [String],
        stdin: Data? = nil,
        environment: [String: String] = [:]
    ) throws -> Result {
        do {
            _ = try run(
                arguments,
                stdin: stdin,
                environment: environment
            )
            Issue.record("CLI command unexpectedly succeeded: \(arguments.joined(separator: " "))")
            throw ActionCLIProcessError.unexpectedSuccess(arguments)
        } catch let ActionCLIProcessError.failed(_, stderr) {
            return Result(stdout: Data(), stderr: Data(stderr.utf8), status: 1)
        }
    }
}

private enum ActionCLIProcessError: Error {
    case failed([String], String)
    case unexpectedSuccess([String])
}

private struct ActionCLIFixture {
    static let exactReadSource = Data(
        "\u{FEFF}---\r\ntitle: Exact CLI Read\r\n---\r\n# Exact CLI Read\r\nNo final newline".utf8
    )

    let rootURL: URL
    let homeURL: URL
    let assignment: TriptychAssignment
    let analysisTarget: ResearchActionNoteSnapshot
    let topicTarget: ResearchActionNoteSnapshot
    let workTarget: ResearchActionNoteSnapshot
    let recordID: UUID

    static func make(
        triptychName: String = "Action CLI Fixture"
    ) async throws -> Self {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/test-fixtures", isDirectory: true)
            .appendingPathComponent(
                "ScholiumActionCLI-\(UUID().uuidString)",
                isDirectory: true
            )
        let home = root.appendingPathComponent("home", isDirectory: true)
        let appSupport = home.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let registry = home.appendingPathComponent("registry", isDirectory: true)
        let analyses = root.appendingPathComponent("Analyses", isDirectory: true)
        let topics = root.appendingPathComponent("Topics", isDirectory: true)
        let works = root.appendingPathComponent("Works", isDirectory: true)
        for directory in [home, appSupport, registry, analyses, topics, works] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: home.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: appSupport.path
        )
        let analysisURL = analyses.appendingPathComponent("Analysis.md")
        try Data(
            "---\nsummary: inheritance-handoff map\n---\n# Analysis\n\nA synthetic analysis claim.\n\n+[[Topic]]\n".utf8
        )
            .write(to: analysisURL, options: .atomic)
        try exactReadSource.write(
            to: analyses.appendingPathComponent("Exact Read.md"),
            options: .atomic
        )
        try Data("# Topic\n\nA synthetic topic.\n".utf8)
            .write(to: topics.appendingPathComponent("Topic.md"), options: .atomic)
        try Data("# Draft Argument\n\nA synthetic work claim.\n".utf8)
            .write(to: works.appendingPathComponent("Draft Argument.md"), options: .atomic)
        let analysisSourceURL = root.appendingPathComponent("Synthetic Source.md")
        try Data(
            "# Synthetic Source\n\nA source-grounded rival is discussed on page 42.\n".utf8
        ).write(to: analysisSourceURL, options: .atomic)

        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: appSupport,
            workspaceRegistryStorageURL: registry
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: root,
            triptychName: triptychName
        )
        let assignment = handle.assignment
        let analysisVault = try #require(assignment.vault(for: .paperAnalysis))
        let topicVault = try #require(assignment.vault(for: .topicKnowledge))
        let workVault = try #require(assignment.vault(for: .output))
        let analysisID = VaultQualifiedNoteID(
            vaultID: analysisVault.id,
            relativePath: "Analysis.md"
        )
        let workID = VaultQualifiedNoteID(
            vaultID: workVault.id,
            relativePath: "Draft Argument.md"
        )
        _ = try await handle.documents.saveMetadata(
            analysisID,
            fields: ["language": .string("Greek")],
            expectedRevision: nil
        )
        _ = try await handle.refresh()
        let analysisTarget = try await target(analysisID, role: .analysis, handle: handle)
        _ = try await handle.research.bindSourceAccess(
            ResearchSourceBindingRequest(
                target: ResearchActionNoteSnapshot(
                    noteID: analysisTarget.noteID,
                    note: analysisTarget.note,
                    role: .analysis,
                    fingerprint: analysisTarget.fingerprint,
                    title: analysisTarget.title
                ),
                selection: .localFile(analysisSourceURL)
            )
        )
        try installExecutableVerifierBookmarkIfRequested(
            applicationSupportURL: appSupport,
            triptychID: assignment.id,
            analysisNoteID: analysisTarget.noteID,
            sourceURL: analysisSourceURL,
            fixtureRootURL: root
        )
        let topicTarget = try await target(
            VaultQualifiedNoteID(vaultID: topicVault.id, relativePath: "Topic.md"),
            role: .topic,
            handle: handle
        )
        let workTarget = try await target(workID, role: .work, handle: handle)
        let discussion = try await handle.research.createDiscussion(
            target: ResearchActionNoteSnapshot(
                noteID: analysisTarget.noteID,
                note: analysisTarget.note,
                role: .analysis,
                fingerprint: analysisTarget.fingerprint,
                title: analysisTarget.title
            ),
            focalNotes: [],
            passage: nil,
            researcherMessage: "Inspect the synthetic Analysis Record."
        )
        let record = try await handle.research.replyToDiscussionAndFinish(
            discussionID: discussion.id,
            statementID: UUID(),
            attribution: "Research Agent",
            text: "The synthetic Analysis retains one exact finished Record."
        )
        await runtime.shutdown()
        return Self(
            rootURL: root,
            homeURL: home,
            assignment: assignment,
            analysisTarget: analysisTarget,
            topicTarget: topicTarget,
            workTarget: workTarget,
            recordID: record.id
        )
    }

    private static func target(
        _ id: VaultQualifiedNoteID,
        role: ResearchActionTargetRole,
        handle: WorkspaceHandle
    ) async throws -> ResearchActionNoteSnapshot {
        let note = try #require(try await handle.snapshot().document(id: id))
        return ResearchActionNoteSnapshot(
            noteID: try #require(note.stableIdentity.resolvedID),
            note: id,
            role: role,
            fingerprint: note.fingerprint,
            title: ResearchNoteTitleResolver.resolve(
                document: note.document,
                vaultRole: note.vaultRole,
                metadata: note.metadata
            ).title
        )
    }

    /// SwiftPM executes tests through Apple's testing helper while the CLI is
    /// a separate ad-hoc executable. The dedicated executable verifier signs
    /// a minimal bookmark binder and a copied CLI with one disposable identity,
    /// then asks this fixture to replace only the bookmark bytes created by the
    /// test host. All other binding state still comes from the production use
    /// case and the CLI must resolve and validate the real security scope.
    private static func installExecutableVerifierBookmarkIfRequested(
        applicationSupportURL: URL,
        triptychID: UUID,
        analysisNoteID: UUID,
        sourceURL: URL,
        fixtureRootURL: URL
    ) throws {
        guard let helperPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BOOKMARK_HELPER"
        ], !helperPath.isEmpty else { return }

        let bookmarkURL = fixtureRootURL.appendingPathComponent(
            "action-cli-source.bookmark"
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = [sourceURL.path, bookmarkURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            throw ActionCLIFixtureError.bookmarkHelperFailed(message)
        }

        let bookmark = try Data(contentsOf: bookmarkURL)
        let bindingURL = applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(triptychID.uuidString, isDirectory: true)
            .appendingPathComponent("source-access", isDirectory: true)
            .appendingPathComponent("source-bindings-v1.json")
        var payload = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: bindingURL))
                as? [String: Any]
        )
        var bindings = try #require(payload["bindings"] as? [[String: Any]])
        let index = try #require(bindings.firstIndex {
            ($0["analysisNoteID"] as? String)?.lowercased()
                == analysisNoteID.uuidString.lowercased()
        })
        bindings[index]["bookmarkData"] = bookmark.base64EncodedString()
        payload["bindings"] = bindings
        try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: bindingURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: bindingURL.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private enum ActionCLIFixtureError: LocalizedError {
    case bookmarkHelperFailed(String)

    var errorDescription: String? {
        switch self {
        case .bookmarkHelperFailed(let message):
            "The Action CLI bookmark fixture failed: \(message)"
        }
    }
}
