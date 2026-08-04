import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing

@Suite("Executable Research Action CLI lifecycle")
struct ActionCLIExecutableLifecycleTests {
    @Test("The Agent MCP wrapper stays on stdio and reports an absent App without opening a snapshot runtime")
    func agentMCPUnavailableContract() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let bridgeSupport = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent(
            ".build/m/\(String(UUID().uuidString.prefix(8)))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: bridgeSupport,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: bridgeSupport) }
        let triptychID = fixture.assignment.id.uuidString.lowercased()
        let requestID = UUID().uuidString.lowercased()
        let messages: [[String: Any]] = [
            [
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": ["protocolVersion": "2025-06-18"],
            ],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            [
                "jsonrpc": "2.0", "id": 3, "method": "tools/call",
                "params": [
                    "name": "show_note_change_request",
                    "arguments": [
                        "triptych_id": triptychID,
                        "request_id": requestID,
                        "coordination_key": String(repeating: "a", count: 73),
                    ],
                ],
            ],
        ]
        let input = try messages.reduce(into: Data()) { result, message in
            result.append(try JSONSerialization.data(
                withJSONObject: message,
                options: [.sortedKeys]
            ))
            result.append(0x0A)
        }
        let result = try cli.run(
            ["agent", "mcp", "serve"],
            stdin: input,
            environment: [
                "SCHOLIUM_AGENT_BRIDGE_APPLICATION_SUPPORT": bridgeSupport.path,
            ]
        )
        #expect(result.stderr.isEmpty)
        let responses = try String(decoding: result.stdout, as: UTF8.self)
            .split(separator: "\n")
            .map {
                try #require(JSONSerialization.jsonObject(
                    with: Data($0.utf8)
                ) as? [String: Any])
            }
        #expect(responses.count == 3)
        let tools = try #require(
            (responses[1]["result"] as? [String: Any])?["tools"]
                as? [[String: Any]]
        )
        #expect(Set(tools.compactMap { $0["name"] as? String }) == [
            "request_note_changes",
            "show_note_change_request",
            "cancel_note_change_request",
        ])
        let callResult = try #require(responses[2]["result"] as? [String: Any])
        #expect(callResult["isError"] as? Bool == true)
        let structured = try #require(
            callResult["structuredContent"] as? [String: Any]
        )
        let bridgeError = try #require(structured["error"] as? [String: Any])
        #expect(bridgeError["code"] as? String == "unavailable")
    }

    @Test("The real CLI exposes the Search v4 text and JSONL contracts")
    func searchV4Contract() async throws {
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
        #expect(records.first?["contract_version"] as? Int == SearchContractV4.contractVersion)
        #expect(records.first?["scope"] as? String == SearchPresentationScope.triptych.rawValue)
        #expect(records.dropFirst().allSatisfy { $0["type"] as? String == "search_result" })
        #expect(records.dropFirst().allSatisfy { $0["score"] == nil && $0["index_generation"] == nil })

        let text = String(decoding: try cli.run([
            "search", "synthetic", "--vault", analyses.id.uuidString,
            "--triptych", triptych, "--format", "text",
        ]).stdout, as: UTF8.self)
        #expect(text.contains("Analyses:Analysis.md:"))
        #expect(text.contains("[retrieval_lead;"))

        let noMatch = try cli.run([
            "search", "no-such-search-term", "--triptych", triptych,
        ])
        #expect(String(decoding: noMatch.stdout, as: UTF8.self) == "No matches.\n")

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

        try cli.expectFailure(
            ["search", "review:reviewed", "--triptych", triptych],
            contains: "Unknown Search field review:"
        )

        try cli.expectFailure(
            ["search", "role:analyses", "--triptych", triptych],
            contains: "removed"
        )
        try cli.expectFailure(
            ["search", "synthetic", "--workspace"],
            contains: "unknown option"
        )
        try cli.expectFailure(
            ["search", "synthetic"],
            contains: "choose --vault"
        )
    }

    @Test("The real CLI preserves one complete Action lifecycle")
    func lifecycle() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_ACTION_CLI_BINARY"
        ], !binaryPath.isEmpty else {
            // The dedicated verifier supplies the built executable. Ordinary
            // package-test runs retain their delivery-neutral unit coverage.
            return
        }

        let fixture = try await ActionCLIFixture.make()
        defer { fixture.remove() }
        let cli = ActionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let encoder = Self.encoder()
        let decoder = Self.decoder()

        let availability = try cli.run(
            ["action", "available", "--from", "-", "--format", "json"],
            stdin: try encoder.encode(fixture.analysisTarget)
        )
        let available = try decoder.decode(
            [ResearchActionAvailability].self,
            from: availability.stdout
        )
        #expect(available.contains { $0.id == .discuss && $0.isEnabled })

        let dialogueRequest = try Self.actionRequest(
            actionID: .discuss,
            target: fixture.analysisTarget,
            availability: available,
            instruction: "State the synthetic fixture's bounded academic outcome."
        )
        let dialogueRequestURL = fixture.rootURL.appendingPathComponent("dialogue.json")
        try encoder.encode(dialogueRequest).write(to: dialogueRequestURL, options: .atomic)
        let dialogueResult = try cli.run([
            "action", "prepare", "--from", dialogueRequestURL.path,
            "--format", "json",
        ])
        let dialogue = try decoder.decode(
            ResearchActionPreparation.self,
            from: dialogueResult.stdout
        )
        #expect(dialogue.snapshot.actionID == .discuss)
        #expect(Set(dialogue.nextActions.map(\.kind)) == [
            .reply, .complete, .inspect, .cancel,
        ])
        let shownDialogueRun = try decoder.decode(
            ResearchActionPreparation.self,
            from: try cli.run([
                "action", "show", dialogue.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        #expect(shownDialogueRun.snapshot == dialogue.snapshot)

        let shownResult = try cli.run([
            "discuss", "show", dialogue.runID.uuidString,
            "--triptych", fixture.assignment.id.uuidString,
            "--format", "json",
        ])
        let shown = try decoder.decode(
            PortableResearchDiscussion.self,
            from: shownResult.stdout
        )
        #expect(shown.id == dialogue.runID)
        #expect(shown.statements.last?.author == .researcher)
        #expect(shown.statements.last?.attribution == "Researcher")
        #expect(
            shown.statements.last?.text
                == "State the synthetic fixture's bounded academic outcome."
        )

        let replyURL = fixture.rootURL.appendingPathComponent("reply.md")
        try Data("Synthetic attributed transport evidence only.\n".utf8)
            .write(to: replyURL, options: .atomic)
        _ = try cli.run([
            "discuss", "reply", dialogue.runID.uuidString,
            "--triptych", fixture.assignment.id.uuidString,
            "--agent", "CLI Acceptance Fixture",
            "--from", replyURL.path,
        ])
        let replied = try decoder.decode(
            PortableResearchDiscussion.self,
            from: try cli.run([
                "discuss", "show", dialogue.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        #expect(replied.statements.last?.author == .agent)
        #expect(replied.statements.last?.attribution == "CLI Acceptance Fixture")
        #expect(
            replied.statements.last?.text
                == "Synthetic attributed transport evidence only."
        )

        let dialogueCompletion = ResearchActionCompletionSubmission(
            runID: dialogue.runID,
            confirmationToken: try Self.confirmationToken(for: dialogue),
            finalTargetFingerprint: fixture.analysisTarget.fingerprint,
            summary: "Recorded synthetic Discuss transport evidence.",
            didModifyTarget: false
        )
        let dialogueCompleted = try decoder.decode(
            ResearchActionCompletion.self,
            from: try cli.run([
                "action", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(dialogueCompletion)).stdout
        )
        #expect(dialogueCompleted.state == .complete)

        let analyzeRequest = try Self.actionRequest(
            actionID: .analyze,
            target: fixture.analysisTarget,
            availability: available,
            instruction: "Retain one source-grounded reading lead."
        )
        let analyze = try decoder.decode(
            ResearchActionPreparation.self,
            from: try cli.run([
                "action", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(analyzeRequest)).stdout
        )
        let analyzeWriteCompletion = ResearchActionWriteCompletionSubmission(
            runID: analyze.runID,
            writeKey: try Self.writeKey(for: analyze),
            candidateModifiedNotes: [],
            summary: "Reported no candidate Markdown change."
        )
        let analyzeCompleted = try decoder.decode(
            ResearchActionCompletion.self,
            from: try cli.run([
                "action", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(ResearchActionCompletionSubmission(
                runID: analyze.runID,
                confirmationToken: try Self.confirmationToken(for: analyze),
                finalTargetFingerprint: fixture.analysisTarget.fingerprint,
                summary: "Retained one source-grounded reading lead.",
                didModifyTarget: false,
                writeCompletion: analyzeWriteCompletion,
                literatureRecommendations: [
                    try ResearchLiteratureRecommendationSubmission(
                        rawCitation: "A. Author, A Relevant Work (2020)",
                        title: "A Relevant Work",
                        authors: ["A. Author"],
                        year: 2020,
                        doi: "10.1000/relevant",
                        sourceLocators: ["p. 42"],
                        reason: "The analyzed source presents this work as a live rival."
                    ),
                ]
            ))).stdout
        )
        #expect(analyzeCompleted.state == .complete)
        #expect(analyzeCompleted.literatureRecommendationCount == 1)
        let analyzeRecordURL = fixture.rootURL
            .appendingPathComponent(
                ".scholium/research-records/v1/records",
                isDirectory: true
            )
            .appendingPathComponent(analyze.runID.uuidString.lowercased() + ".json")
        let analyzeRecord = try decoder.decode(
            PortableResearchRecord.self,
            from: Data(contentsOf: analyzeRecordURL)
        )
        #expect(analyzeRecord.schemaVersion == 4)
        #expect(analyzeRecord.literatureRecommendations.count == 1)
        #expect(
            analyzeRecord.literatureRecommendations[0].disposition.status
                == .unprocessed
        )

        let workAvailable = try decoder.decode(
            [ResearchActionAvailability].self,
            from: try cli.run(
                ["action", "available", "--from", "-", "--format", "json"],
                stdin: try encoder.encode(fixture.workTarget)
            ).stdout
        )
        let writeRequest = try Self.actionRequest(
            actionID: .write,
            target: fixture.workTarget,
            availability: workAvailable,
            instruction: "Strengthen only the stated inference."
        )
        let write = try decoder.decode(
            ResearchActionPreparation.self,
            from: try cli.run([
                "action", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(writeRequest)).stdout
        )
        #expect(write.snapshot.actionID == .write)

        let readBefore = try Self.readPayload(try cli.run([
            "read", "Works:Draft Argument.md", "--format", "json",
        ]).stdout)
        let revisedSourceURL = fixture.rootURL.appendingPathComponent("revised-work.md")
        try Data("---\ntitle: Draft Argument\nkind: chapter\n---\n# Draft Argument\n\nA synthetically revised claim.\n".utf8)
            .write(to: revisedSourceURL, options: .atomic)
        try cli.expectFailure([
            "note", "replace", "Works:Draft Argument.md",
            "--from", revisedSourceURL.path,
            "--expected", String(repeating: "0", count: 64),
        ], contains: "Revision mismatch")
        _ = try cli.run([
            "note", "replace", "Works:Draft Argument.md",
            "--from", revisedSourceURL.path,
            "--expected", readBefore.sha256,
        ])
        let readAfter = try Self.readPayload(try cli.run([
            "read", "Works:Draft Argument.md", "--format", "json",
        ]).stdout)
        #expect(readAfter.sha256 != readBefore.sha256)
        let finalWorkFingerprint = DocumentFingerprint(
            sha256: readAfter.sha256,
            byteCount: Data(readAfter.content.utf8).count
        )
        let writeCompletion = ResearchActionWriteCompletionSubmission(
            runID: write.runID,
            writeKey: try Self.writeKey(for: write),
            candidateModifiedNotes: [fixture.workTarget.note],
            summary: "Reported the candidate Work path after the synthetic revision."
        )

        let awaiting = try decoder.decode(
            ResearchActionCompletion.self,
            from: try cli.run([
                "action", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(ResearchActionCompletionSubmission(
                runID: write.runID,
                confirmationToken: try Self.confirmationToken(for: write),
                finalTargetFingerprint: finalWorkFingerprint,
                summary: "Reported a synthetic Work revision.",
                didModifyTarget: true,
                writeCompletion: writeCompletion
            ))).stdout
        )
        #expect(awaiting.state == .awaitingFidelity)
        #expect(awaiting.nextActions.first?.kind == .prepareFidelity)

        let automatic = try decoder.decode(
            ResearchActionFidelityPreparation.self,
            from: try cli.run([
                "action", "prepare-fidelity", write.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        let fidelity = automatic.preparation
        #expect(fidelity.snapshot.target.fingerprint == finalWorkFingerprint)
        #expect(fidelity.snapshot.actionID == .checkFidelity)
        let fidelityCompletion = try decoder.decode(
            ResearchActionCompletion.self,
            from: try cli.run([
                "action", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(ResearchActionCompletionSubmission(
                runID: fidelity.runID,
                confirmationToken: try Self.confirmationToken(for: fidelity),
                finalTargetFingerprint: finalWorkFingerprint,
                summary: "Synthetic revision-bound transport evidence.",
                didModifyTarget: false,
                fidelityOutcomes: [.init(
                    check: .content,
                    state: .passed,
                    summary: "The fixture reported no structural fidelity issue."
                )]
            ))).stdout
        )
        #expect(fidelityCompletion.state == .complete)

        let reusedAutomatic = try decoder.decode(
            ResearchActionFidelityPreparation.self,
            from: try cli.run([
                "action", "prepare-fidelity", write.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        #expect(reusedAutomatic.reusedExistingEvidence)
        let parentAction = try #require(reusedAutomatic.nextActions.first {
            $0.kind == .complete
        })
        let parentInput = try #require(parentAction.inputTemplate)
        let parentSubmission = try decoder.decode(
            ResearchActionCompletionSubmission.self,
            from: Data(parentInput.utf8)
        )
        let verifiedParent = try decoder.decode(
            ResearchActionCompletion.self,
            from: try cli.run([
                "action", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(parentSubmission)).stdout
        )
        #expect(verifiedParent.state == .complete)
        #expect(verifiedParent.childRunIDs == [fidelity.runID])

        let currentWorkTarget = ResearchActionNoteSnapshot(
            noteID: fixture.workTarget.noteID,
            note: fixture.workTarget.note,
            role: .work,
            lifecycle: fixture.workTarget.lifecycle,
            fingerprint: finalWorkFingerprint,
            title: fixture.workTarget.title
        )
        let currentWorkAvailable = try decoder.decode(
            [ResearchActionAvailability].self,
            from: try cli.run(
                ["action", "available", "--from", "-", "--format", "json"],
                stdin: try encoder.encode(currentWorkTarget)
            ).stdout
        )
        let cancellable = try decoder.decode(
            ResearchActionPreparation.self,
            from: try cli.run([
                "action", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(Self.actionRequest(
                actionID: .discuss,
                target: currentWorkTarget,
                availability: currentWorkAvailable,
                instruction: "Prepare a cancellable synthetic Discussion."
            ))).stdout
        )
        for _ in 0..<2 {
            let cancellation = try decoder.decode(
                CLICancellationReport.self,
                from: try cli.run([
                    "action", "cancel", cancellable.runID.uuidString,
                    "--triptych", fixture.assignment.id.uuidString,
                ]).stdout
            )
            #expect(cancellation.runID == cancellable.runID)
        }
        let cancelledDiscussion = try decoder.decode(
            PortableResearchDiscussion.self,
            from: try cli.run([
                "discuss", "show", cancellable.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        #expect(cancelledDiscussion.id == cancellable.runID)
        #expect(cancelledDiscussion.awaitsAgentReply)
        #expect(
            cancelledDiscussion.statements.last?.text
                == "Prepare a cancellable synthetic Discussion."
        )
        try cli.expectFailure(
            ["action", "prepare", "--from", "-", "--format", "json"],
            stdin: try encoder.encode(Self.actionRequest(
                actionID: .discuss,
                target: currentWorkTarget,
                availability: currentWorkAvailable,
                instruction: "This second Discussion must remain blocked."
            )),
            contains: "already active"
        )

        let markdown = try cli.run([
            "action", "prepare", "--from", "-", "--format", "markdown",
        ], stdin: try encoder.encode(Self.actionRequest(
            actionID: .discuss,
            target: fixture.topicTarget,
            availability: try decoder.decode(
                [ResearchActionAvailability].self,
                from: cli.run(
                    ["action", "available", "--from", "-", "--format", "json"],
                    stdin: try encoder.encode(fixture.topicTarget)
                ).stdout
            ),
            instruction: "Render a Markdown handoff fixture."
        )))
        #expect(String(decoding: markdown.stdout, as: UTF8.self).contains("Scholium"))

        try cli.expectFailure(
            ["action", "prepare", "--from", "-", "--format", "json"],
            stdin: Data("{malformed".utf8),
            contains: "invalid_json"
        )
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
        #expect(String(decoding: version.stdout, as: UTF8.self).contains("cli_version"))
        let help = try cli.run(["action", "prepare", "--help", "--format", "json"])
        #expect(String(decoding: help.stdout, as: UTF8.self).contains("action prepare"))
        let retiredCommand = ["biblio", "graphy"].joined()
        let rootHelp = try cli.run(["help"])
        #expect(!String(decoding: rootHelp.stdout, as: UTF8.self).contains(retiredCommand))
        try cli.expectFailure([retiredCommand], contains: "Unknown command")
        let doctor = try cli.run(["doctor", "--format", "json"])
        #expect(String(decoding: doctor.stdout, as: UTF8.self).contains("triptych_count"))
        try cli.expectFailure(
            ["skills", "catalog", "--resouce", "references/method.md", "--format", "json"],
            contains: "Unknown option '--resouce'"
        )
        try cli.expectFailure(
            ["skills", "catalog", "--format"],
            contains: "requires a value"
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
        var values: [ResearchActionModuleID: ResearchActionParameterValue] = [:]
        if let instruction,
           let module = presented.profile.profile.modules.first(where: {
               $0.kind == .boundedText
           }) {
            values[module.id] = .text(instruction)
        }
        return ResearchActionExecutionRequest(
            actionID: actionID,
            expectedExecutionKind: presented.definition.executionKind,
            expectedProfileRevision: presented.profile.profileRevision,
            expectedProfileDocumentRevision:
                presented.profile.profileDocumentRevision,
            target: target,
            parameterValues: values
        )
    }

    private static func confirmationToken(
        for preparation: ResearchActionPreparation
    ) throws -> UUID {
        let template = try #require(preparation.nextActions.first {
            $0.kind == .complete
        }?.inputTemplate)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(template.utf8))
                as? [String: Any]
        )
        let rawToken = try #require(object["confirmationToken"] as? String)
        return try #require(UUID(uuidString: rawToken))
    }

    private static func writeKey(
        for preparation: ResearchActionPreparation
    ) throws -> String {
        let prefix = "Write key: "
        return String(try #require(
            preparation.instructions
                .split(separator: "\n")
                .map(String.init)
                .first(where: { $0.hasPrefix(prefix) })?
                .dropFirst(prefix.count)
        ))
    }

}

private struct CLIReadPayload: Decodable {
    let sha256: String
    let content: String
}

private struct CLICancellationReport: Decodable {
    let runID: UUID
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
        contains expected: String
    ) throws {
        do {
            _ = try run(arguments, stdin: stdin)
            Issue.record("CLI command unexpectedly succeeded: \(arguments.joined(separator: " "))")
        } catch let ActionCLIProcessError.failed(_, stderr) {
            #expect(stderr.localizedCaseInsensitiveContains(expected))
        }
    }
}

private enum ActionCLIProcessError: Error {
    case failed([String], String)
}

private struct ActionCLIFixture {
    let rootURL: URL
    let homeURL: URL
    let assignment: TriptychAssignment
    let analysisTarget: ResearchActionNoteSnapshot
    let topicTarget: ResearchActionNoteSnapshot
    let workTarget: ResearchActionNoteSnapshot

    static func make() async throws -> Self {
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
        let analysisURL = analyses.appendingPathComponent("Analysis.md")
        try Data("---\ntitle: Analysis\n---\n# Analysis\n\nA synthetic analysis claim.\n".utf8)
            .write(to: analysisURL, options: .atomic)
        try Data("---\ntitle: Topic\n---\n# Topic\n\nA synthetic topic.\n".utf8)
            .write(to: topics.appendingPathComponent("Topic.md"), options: .atomic)
        try Data("---\ntitle: Draft Argument\nkind: chapter\n---\n# Draft Argument\n\nA synthetic work claim.\n".utf8)
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
            triptychName: "Action CLI Fixture"
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
        let analysisTarget = try await target(analysisID, role: .analysis, handle: handle)
        _ = try await handle.research.bindSourceAccess(
            ResearchSourceBindingRequest(
                target: ResearchFunctionTarget(
                    noteID: analysisTarget.noteID,
                    note: analysisTarget.note,
                    role: .analysis,
                    lifecycle: analysisTarget.lifecycle,
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
        await runtime.shutdown()
        return Self(
            rootURL: root,
            homeURL: home,
            assignment: assignment,
            analysisTarget: analysisTarget,
            topicTarget: topicTarget,
            workTarget: workTarget
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
            lifecycle: note.lifecycle,
            fingerprint: note.fingerprint,
            title: note.document.parsedFrontmatter["title"]?.scalarString
                ?? id.relativePath
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
