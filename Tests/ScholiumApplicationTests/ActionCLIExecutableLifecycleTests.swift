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
            "preflight-analysis", "start", "pair", "context", "reload", "query", "discuss-reply",
            "finish-discussion",
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
            secret: String(repeating: "a", count: 48)
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
            coreProtocol: "Scholium Core Protocol",
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
            method: ResearchMethodContext(snapshot: method),
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
            case .pair, .revokeSession, .query, .discussionReply, .discussionFinish,
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
        let startedOutput = String(decoding: started.stdout, as: UTF8.self)
        #expect(startedOutput.contains(run.rawValue))
        #expect(!startedOutput.contains(credential.secret))

        let credentialURL = freshAgentHome
            .appendingPathComponent("sessions", isDirectory: true)
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

        let loaded = try cli.run(
            ["agent", "context", "--run", run.rawValue],
            environment: environment
        )
        #expect(String(decoding: loaded.stdout, as: UTF8.self)
            .contains("Scholium Core Protocol"))
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
            secret: String(repeating: "u", count: 48)
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
        let server = try LocalAgentBridgeServer(
            applicationSupportURL: bridgeContainer
        ) { bridgeRequest in
            guard bridgeRequest.operation == .start,
                  bridgeRequest.triptychID == fixture.assignment.id,
                  bridgeRequest.startRequest == request else {
                throw LocalAgentBridgeError.permissionDenied
            }
            return .started(receipt: receipt, credential: credential)
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
        #expect(String(decoding: result.stdout, as: UTF8.self)
            .contains(run.rawValue))
    }

    @Test("The real CLI pairs, reloads Discuss context, and removes its credential after Finish")
    func agentPairingContextAndDiscussionFinish() async throws {
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
            secret: String(repeating: "s", count: 48)
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
            coreProtocol: "Scholium Core Protocol",
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
                    discussionReply: true,
                    discussionFinish: true
                )
            ),
            method: ResearchMethodContext(snapshot: method),
            resultContract: try ResearchResultContract(
                profile: profile,
                registrationKey: registration.key,
                profileRevision: profileRevision
            ),
            boundedWriteSet: []
        )
        let adapter = try ResearchZoteroIntegrationAdapter(
            skillMarkdown: "# Zotero Integration\n",
            capabilityContractMarkdown: "# Capability Contract\n"
        )
        #expect(throws: ResearchAgentConnectionContractError.self) {
            _ = try ResearchAuthenticatedRunContext(
                coreProtocol: context.coreProtocol,
                brief: context.brief,
                method: context.method,
                zoteroIntegrationAdapter: adapter,
                resultContract: context.resultContract,
                boundedWriteSet: context.boundedWriteSet
            )
        }
        let finishReceipt = try ResearchAgentDiscussionFinishReceipt(
            run: run,
            discussionID: UUID(),
            message: "The Discussion finished and formed one portable Research Record."
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
            case .discussionFinish:
                guard request.run == run, request.credential == credential else {
                    throw LocalAgentBridgeError.permissionDenied
                }
                return .discussionFinish(finishReceipt)
            case .revokeSession, .query, .discussionReply,
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
        let pairingOutput = String(decoding: paired.stdout, as: UTF8.self)
        #expect(pairingOutput.contains("\"paired\" : true"))
        #expect(!pairingOutput.contains(credential.secret))
        #expect(!pairingOutput.contains(code.rawValue))
        let credentialURL = fixture.homeURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(run.rawValue + ".json")
        let mode = try #require(
            FileManager.default.attributesOfItem(atPath: credentialURL.path)[
                .posixPermissions
            ] as? NSNumber
        ).intValue
        #expect(mode == 0o600)

        let loaded = try cli.run(
            ["agent", "context", "--run", run.rawValue],
            environment: environment
        )
        let contextOutput = String(decoding: loaded.stdout, as: UTF8.self)
        #expect(contextOutput.contains("Preserve alternatives."))
        #expect(contextOutput.contains("Scholium Core Protocol"))
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
        try cli.expectFailure(
            ["agent", "context", "--run", run.rawValue],
            environment: environment,
            contains: "No valid local Connection Session exists"
        )
        storedCredential.removeValue(forKey: "unexpected_authority")
        try JSONSerialization.data(withJSONObject: storedCredential)
            .write(to: credentialURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: credentialURL.path
        )

        let finished = try cli.run(
            ["agent", "finish-discussion", "--run", run.rawValue],
            environment: environment
        )
        let finishOutput = String(decoding: finished.stdout, as: UTF8.self)
        #expect(finishOutput.contains("\"finished\" : true"))
        #expect(finishOutput.contains("\"record_formed\" : true"))
        #expect(!finishOutput.contains(credential.secret))
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
            secret: String(repeating: "w", count: 48)
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
            case .revokeSession, .context, .query, .discussionReply, .discussionFinish,
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

    @Test("The real CLI exposes Search v9 plus direct fingerprinted Record retrieval")
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
        #expect(relatedRows[0]["record_count"] as? Int == 1)
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
            secret: String(repeating: "r", count: 48)
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
            case .revokeSession, .context, .query, .discussionReply, .discussionFinish,
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
            secret: String(repeating: "s", count: 48)
        )
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
            secret: String(repeating: "r", count: 48)
        )
        let sessionsURL = home.appendingPathComponent("sessions", isDirectory: true)
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
            secret: String(repeating: "d", count: 48)
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
        let sessionsURL = fixture.homeURL.appendingPathComponent(
            "sessions",
            isDirectory: true
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
            secret: String(repeating: "m", count: 48)
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
            case .methodImprovementContext:
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
            case .revokeSession, .context, .query, .discussionReply, .discussionFinish,
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
        _ = try cli.run(
            ["agent", "pair", "--run", locator.rawValue],
            stdin: Data((code.rawValue + "\n").utf8),
            environment: environment
        )
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
        _ = try await handle.research.appendDiscussionStatement(
            discussionID: discussion.id,
            author: .agent,
            attribution: "Research Agent",
            text: "The synthetic Analysis retains one exact finished Record."
        )
        let record = try await handle.research.finishDiscussion(
            discussionID: discussion.id
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
