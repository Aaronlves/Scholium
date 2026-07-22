import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing

@Suite("Executable Research Function CLI lifecycle")
struct FunctionCLIExecutableLifecycleTests {
    @Test("The real CLI exposes the Search v3 text and JSONL contracts")
    func searchV3Contract() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_FUNCTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await FunctionCLIFixture.make()
        defer { fixture.remove() }
        let cli = FunctionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
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
        #expect(records.first?["contract_version"] as? Int == SearchContractV3.contractVersion)
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
            "search", "-review:reviewed", "--triptych", triptych,
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

    @Test("The real CLI preserves one complete Function lifecycle")
    func lifecycle() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_FUNCTION_CLI_BINARY"
        ], !binaryPath.isEmpty else {
            // The dedicated verifier supplies the built executable. Ordinary
            // package-test runs retain their delivery-neutral unit coverage.
            return
        }

        let fixture = try await FunctionCLIFixture.make()
        defer { fixture.remove() }
        let cli = FunctionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let encoder = Self.encoder()
        let decoder = Self.decoder()

        let availability = try cli.run(
            ["function", "available", "--from", "-", "--format", "json"],
            stdin: try encoder.encode(fixture.analysisTarget)
        )
        let available = try decoder.decode(
            [ResearchFunctionAvailability].self,
            from: availability.stdout
        )
        #expect(available.contains { $0.function == .discuss && $0.isEnabled })

        let dialogueRequest = ResearchFunctionRequest(
            function: .discuss,
            target: fixture.analysisTarget,
            instruction: "State the synthetic fixture's bounded academic outcome.",
            dialogueResponseModules: [
                .criticalReflection,
                .philosophicalSignificance,
            ]
        )
        let dialogueRequestURL = fixture.rootURL.appendingPathComponent("dialogue.json")
        try encoder.encode(dialogueRequest).write(to: dialogueRequestURL, options: .atomic)
        let dialogueResult = try cli.run([
            "function", "prepare", "--from", dialogueRequestURL.path,
            "--format", "json",
        ])
        let dialogue = try decoder.decode(
            ResearchFunctionPreparation.self,
            from: dialogueResult.stdout
        )
        #expect(dialogue.snapshot.request.dialogueResponseModules == [
            .criticalReflection,
            .philosophicalSignificance,
        ])
        #expect(Set(dialogue.nextActions?.map(\.kind) ?? []) == [
            .reply, .promote, .complete, .inspect, .cancel,
        ])
        let shownDialogueRun = try decoder.decode(
            ResearchFunctionPreparation.self,
            from: try cli.run([
                "function", "show", dialogue.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        #expect(shownDialogueRun.snapshot == dialogue.snapshot)

        let shownResult = try cli.run([
            "dialogue", "show", dialogue.runID.uuidString,
            "--triptych", fixture.assignment.id.uuidString,
            "--format", "json",
        ])
        let shown = try decoder.decode(DialogueEntry.self, from: shownResult.stdout)
        #expect(shown.responseContract.knownModules == [
            .criticalReflection,
            .philosophicalSignificance,
        ])

        let replyURL = fixture.rootURL.appendingPathComponent("reply.md")
        try Data("Synthetic attributed transport evidence only.\n".utf8)
            .write(to: replyURL, options: .atomic)
        _ = try cli.run([
            "dialogue", "reply", dialogue.runID.uuidString,
            "--triptych", fixture.assignment.id.uuidString,
            "--agent", "CLI Acceptance Fixture",
            "--from", replyURL.path,
        ])
        let replied = try decoder.decode(
            DialogueEntry.self,
            from: try cli.run([
                "dialogue", "show", dialogue.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        #expect(replied.replies.first?.agentName == "CLI Acceptance Fixture")

        let dialogueCompletion = ResearchFunctionCompletionSubmission(
            runID: dialogue.runID,
            confirmationToken: dialogue.snapshot.confirmationToken,
            finalTargetFingerprint: fixture.analysisTarget.fingerprint,
            summary: "Recorded synthetic Dialogue transport evidence.",
            didModifyTarget: false
        )
        let dialogueCompleted = try decoder.decode(
            ResearchFunctionCompletion.self,
            from: try cli.run([
                "function", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(dialogueCompletion)).stdout
        )
        #expect(dialogueCompleted.state == .complete)

        let reviseRequest = ResearchFunctionRequest(
            function: .revise,
            target: fixture.workTarget
        )
        let revise = try decoder.decode(
            ResearchFunctionPreparation.self,
            from: try cli.run([
                "function", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(reviseRequest)).stdout
        )
        #expect(revise.awaitsResourceSelection)

        let premature = ResearchFunctionCompletionSubmission(
            runID: revise.runID,
            confirmationToken: revise.snapshot.confirmationToken,
            finalTargetFingerprint: fixture.workTarget.fingerprint,
            summary: "This completion must be refused before method selection.",
            didModifyTarget: false
        )
        try cli.expectFailure([
            "function", "complete", "--from", "-",
            "--triptych", fixture.assignment.id.uuidString,
            "--format", "json",
        ], stdin: try encoder.encode(premature), contains: "conditional methods")

        let wrongConfirmation = ResearchFunctionResourceSelectionSubmission(
            runID: revise.runID,
            confirmationToken: UUID(),
            resources: []
        )
        try cli.expectFailure([
            "function", "select-resources", "--from", "-",
            "--triptych", fixture.assignment.triptych.name,
            "--format", "json",
        ], stdin: try encoder.encode(wrongConfirmation), contains: "does not match")

        let methodSelection = ResearchFunctionResourceSelectionSubmission(
            runID: revise.runID,
            confirmationToken: revise.snapshot.confirmationToken,
            resources: []
        )
        let finalizedRevise = try decoder.decode(
            ResearchFunctionPreparation.self,
            from: try cli.run([
                "function", "select-resources", "--from", "-",
                "--triptych", fixture.assignment.triptych.name,
                "--format", "json",
            ], stdin: try encoder.encode(methodSelection)).stdout
        )
        #expect(finalizedRevise.snapshot.request.conditionalResources == [])

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

        let awaiting = try decoder.decode(
            ResearchFunctionCompletion.self,
            from: try cli.run([
                "function", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                finalTargetFingerprint: finalWorkFingerprint,
                summary: "Reported a synthetic Work revision.",
                didModifyTarget: true
            ))).stdout
        )
        #expect(awaiting.state == .awaitingFidelity)
        #expect(awaiting.nextActions?.first?.kind == .prepareFidelity)

        let automatic = try decoder.decode(
            AutomaticFidelityPreparation.self,
            from: try cli.run([
                "function", "prepare-fidelity", revise.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        let fidelity = automatic.preparation
        #expect(fidelity.snapshot.request.target.fingerprint == finalWorkFingerprint)
        #expect(fidelity.snapshot.resolvedFidelityInvocation == .automatic(parentRunID: revise.runID))
        let fidelityCompletion = try decoder.decode(
            ResearchFunctionCompletion.self,
            from: try cli.run([
                "function", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(ResearchFunctionCompletionSubmission(
                runID: fidelity.runID,
                confirmationToken: fidelity.snapshot.confirmationToken,
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
            AutomaticFidelityPreparation.self,
            from: try cli.run([
                "function", "prepare-fidelity", revise.runID.uuidString,
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ]).stdout
        )
        #expect(reusedAutomatic.reusedExistingEvidence)
        let parentAction = try #require(reusedAutomatic.nextActions?.first {
            $0.kind == .complete
        })
        let parentInput = try #require(parentAction.inputTemplate)
        let parentSubmission = try decoder.decode(
            ResearchFunctionCompletionSubmission.self,
            from: Data(parentInput.utf8)
        )
        let verifiedParent = try decoder.decode(
            ResearchFunctionCompletion.self,
            from: try cli.run([
                "function", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(parentSubmission)).stdout
        )
        #expect(verifiedParent.state == .complete)
        #expect(verifiedParent.childRunIDs == [fidelity.runID])

        let cancellable = try decoder.decode(
            ResearchFunctionPreparation.self,
            from: try cli.run([
                "function", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(ResearchFunctionRequest(
                function: .discuss,
                target: ResearchFunctionTarget(
                    noteID: fixture.workTarget.noteID,
                    note: fixture.workTarget.note,
                    role: .work,
                    fingerprint: finalWorkFingerprint,
                    title: fixture.workTarget.title
                ),
                instruction: "Prepare a cancellable synthetic Dialogue.",
                dialogueResponseModules: []
            ))).stdout
        )
        for _ in 0..<2 {
            let cancellation = try decoder.decode(
                CLICancellationReport.self,
                from: try cli.run([
                    "function", "cancel", cancellable.runID.uuidString,
                    "--triptych", fixture.assignment.id.uuidString,
                ]).stdout
            )
            #expect(cancellation.runID == cancellable.runID)
        }

        let markdown = try cli.run([
            "function", "prepare", "--from", "-", "--format", "markdown",
        ], stdin: try encoder.encode(ResearchFunctionRequest(
            function: .discuss,
            target: ResearchFunctionTarget(
                noteID: fixture.workTarget.noteID,
                note: fixture.workTarget.note,
                role: .work,
                fingerprint: finalWorkFingerprint,
                title: fixture.workTarget.title
            ),
            instruction: "Render a Markdown handoff fixture.",
            dialogueResponseModules: [.remainingQuestions]
        )))
        #expect(String(decoding: markdown.stdout, as: UTF8.self).contains("Scholium"))

        try cli.expectFailure(
            ["function", "prepare", "--from", "-", "--format", "json"],
            stdin: Data("{malformed".utf8),
            contains: "invalid_json"
        )
        try cli.expectFailure(
            ["function", "prepare", "--from", "-", "--format", "json"],
            stdin: try encoder.encode(ResearchFunctionRequest(
                function: .revise,
                target: fixture.analysisTarget
            )),
            contains: "analysis Target"
        )
        let duplicateMaterial = ResearchFunctionMaterial(
            noteID: fixture.analysisTarget.noteID,
            note: fixture.analysisTarget.note,
            role: fixture.analysisTarget.role,
            fingerprint: fixture.analysisTarget.fingerprint,
            title: fixture.analysisTarget.title
        )
        try cli.expectFailure(
            ["function", "prepare", "--from", "-", "--format", "json"],
            stdin: try encoder.encode(ResearchFunctionRequest(
                function: .discuss,
                target: fixture.analysisTarget,
                materials: [duplicateMaterial],
                instruction: "Reject Target duplication."
            )),
            contains: "Target"
        )
    }

    @Test("Help, version, doctor, and strict parsing work without a configured Triptych")
    func discoveryAndStrictParsing() throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_FUNCTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "scholium-cli-discovery-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = FunctionCLIProcess(binaryPath: binaryPath, home: root)

        let version = try cli.run(["version", "--format", "json"])
        #expect(String(decoding: version.stdout, as: UTF8.self).contains("cli_version"))
        let help = try cli.run(["function", "prepare", "--help", "--format", "json"])
        #expect(String(decoding: help.stdout, as: UTF8.self).contains("function prepare"))
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

    @Test("The real CLI preserves the Recommended Bibliography lifecycle")
    func bibliographyLifecycle() async throws {
        guard let binaryPath = ProcessInfo.processInfo.environment[
            "SCHOLIUM_FUNCTION_CLI_BINARY"
        ], !binaryPath.isEmpty else { return }

        let fixture = try await FunctionCLIFixture.make()
        defer { fixture.remove() }
        let cli = FunctionCLIProcess(binaryPath: binaryPath, home: fixture.homeURL)
        let encoder = Self.encoder()
        let decoder = Self.decoder()
        let analysis = RecommendedBibliographyTarget(
            noteID: fixture.analysisTarget.noteID,
            note: fixture.analysisTarget.note,
            fingerprint: fixture.analysisTarget.fingerprint,
            title: fixture.analysisTarget.title
        )

        let request = RecommendedBibliographyRequest(
            target: analysis,
            goals: [.objections, .classicWorks],
            purpose: "Screen only source-grounded reading leads."
        )
        let requestURL = fixture.rootURL.appendingPathComponent("bibliography-request.json")
        try encoder.encode(request).write(to: requestURL, options: .atomic)
        let preparation = try decoder.decode(
            RecommendedBibliographyPreparation.self,
            from: try cli.run([
                "bibliography", "prepare", "--from", requestURL.path,
                "--format", "json",
            ]).stdout
        )
        #expect(preparation.request == request)
        #expect(preparation.method.packageID == "scholium-source-analyzer")

        let shown = try cli.run([
            "bibliography", "show", preparation.id.uuidString,
            "--triptych", fixture.assignment.id.uuidString,
            "--format", "markdown",
        ])
        #expect(String(decoding: shown.stdout, as: UTF8.self).contains(
            "Reading leads, not evidence"
        ))

        let first = Self.bibliographyCandidate(title: "A Bounded Objection")
        let second = Self.bibliographyCandidate(title: "A Bounded Objection")
        let completion = RecommendedBibliographyCompletionSubmission(
            requestID: preparation.id,
            confirmationToken: preparation.confirmationToken,
            targetFingerprint: analysis.fingerprint,
            sourceScope: "Synthetic complete source fixture",
            candidates: [first, second]
        )
        let completionURL = fixture.rootURL.appendingPathComponent("bibliography-completion.json")
        try encoder.encode(completion).write(to: completionURL, options: .atomic)
        let projection = try decoder.decode(
            RecommendedBibliographyProjection.self,
            from: try cli.run([
                "bibliography", "complete", "--from", completionURL.path,
                "--triptych", fixture.assignment.triptych.name,
                "--format", "json",
            ]).stdout
        )
        #expect(projection.state == .complete)
        #expect(projection.candidates.count == 2)
        #expect(projection.candidates[1].matchState == .duplicate)
        #expect(projection.candidates[1].duplicateOfCandidateID == first.id)

        let cancellable = try decoder.decode(
            RecommendedBibliographyPreparation.self,
            from: try cli.run([
                "bibliography", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(RecommendedBibliographyRequest(
                target: analysis,
                goals: []
            ))).stdout
        )
        for _ in 0..<2 {
            let cancelled = try decoder.decode(
                BibliographyCancellationReport.self,
                from: try cli.run([
                    "bibliography", "cancel", cancellable.id.uuidString,
                    "--triptych", fixture.assignment.id.uuidString,
                ]).stdout
            )
            #expect(cancelled.requestID == cancellable.id)
            #expect(cancelled.state == "cancelled")
        }

        let wrongConfirmation = try decoder.decode(
            RecommendedBibliographyPreparation.self,
            from: try cli.run([
                "bibliography", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(RecommendedBibliographyRequest(
                target: analysis
            ))).stdout
        )
        try cli.expectFailure([
            "bibliography", "complete", "--from", "-",
            "--triptych", fixture.assignment.id.uuidString,
            "--format", "json",
        ], stdin: try encoder.encode(RecommendedBibliographyCompletionSubmission(
            requestID: wrongConfirmation.id,
            confirmationToken: UUID(),
            targetFingerprint: analysis.fingerprint,
            sourceScope: "Synthetic source",
            candidates: []
        )), contains: "confirmation token")
        _ = try cli.run([
            "bibliography", "cancel", wrongConfirmation.id.uuidString,
            "--triptych", fixture.assignment.id.uuidString,
        ])

        let workTarget = RecommendedBibliographyTarget(
            noteID: fixture.workTarget.noteID,
            note: fixture.workTarget.note,
            fingerprint: fixture.workTarget.fingerprint,
            title: fixture.workTarget.title
        )
        try cli.expectFailure(
            ["bibliography", "prepare", "--from", "-", "--format", "json"],
            stdin: try encoder.encode(RecommendedBibliographyRequest(target: workTarget)),
            contains: "only for an Analysis"
        )
        try cli.expectFailure(
            ["bibliography", "prepare", "--from", "-", "--format", "json"],
            stdin: Data("{malformed".utf8),
            contains: "data"
        )

        let stale = try decoder.decode(
            RecommendedBibliographyPreparation.self,
            from: try cli.run([
                "bibliography", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(RecommendedBibliographyRequest(
                target: analysis
            ))).stdout
        )
        try Data("---\ntitle: Analysis\n---\n# Analysis\n\nChanged after preparation.\n".utf8)
            .write(to: fixture.analysisURL, options: .atomic)
        try cli.expectFailure([
            "bibliography", "complete", "--from", "-",
            "--triptych", fixture.assignment.id.uuidString,
            "--format", "json",
        ], stdin: try encoder.encode(RecommendedBibliographyCompletionSubmission(
            requestID: stale.id,
            confirmationToken: stale.confirmationToken,
            targetFingerprint: analysis.fingerprint,
            sourceScope: "Synthetic source",
            candidates: []
        )), contains: "changed")
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

    private static func bibliographyCandidate(
        title: String
    ) -> RecommendedBibliographyCandidate {
        RecommendedBibliographyCandidate(
            identity: BibliographyCandidateIdentity(
                rawCitation: "A. Author, \(title), 2020",
                title: title,
                authors: ["A. Author"],
                year: 2020,
                doi: "10.1000/bounded-objection",
                isChapter: false
            ),
            goals: [.objections],
            reason: "The source discusses this as a bounded objection.",
            evidence: BibliographyRecommendationEvidence(
                discussionStatus: .substantivelyDiscussed,
                sourceLocators: ["pp. 10–12"],
                metadataVerified: true,
                verificationProvenance: "Synthetic fixture metadata"
            ),
            requiredNextCheck: "Inspect the complete recommended source."
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

private struct BibliographyCancellationReport: Decodable {
    let requestID: UUID
    let state: String

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case state
    }
}

private struct FunctionCLIProcess {
    struct Result {
        let stdout: Data
        let stderr: Data
        let status: Int32
    }

    let binaryPath: String
    let home: URL

    func run(_ arguments: [String], stdin: Data? = nil) throws -> Result {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "SCHOLIUM_HOME": home.path,
        ]) { _, isolated in isolated }
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
            throw FunctionCLIProcessError.failed(
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
        } catch let FunctionCLIProcessError.failed(_, stderr) {
            #expect(stderr.localizedCaseInsensitiveContains(expected))
        }
    }
}

private enum FunctionCLIProcessError: Error {
    case failed([String], String)
}

private struct FunctionCLIFixture {
    let rootURL: URL
    let homeURL: URL
    let assignment: TriptychAssignment
    let analysisTarget: ResearchFunctionTarget
    let workTarget: ResearchFunctionTarget
    let analysisURL: URL

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ScholiumFunctionCLI-\(UUID().uuidString)",
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

        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: appSupport,
            workspaceRegistryStorageURL: registry
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: root,
            triptychName: "Function CLI Fixture"
        )
        let assignment = handle.assignment
        let analysisVault = try #require(assignment.vault(for: .paperAnalysis))
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
        let workTarget = try await target(workID, role: .work, handle: handle)
        await runtime.shutdown()
        return Self(
            rootURL: root,
            homeURL: home,
            assignment: assignment,
            analysisTarget: analysisTarget,
            workTarget: workTarget,
            analysisURL: analysisURL
        )
    }

    private static func target(
        _ id: VaultQualifiedNoteID,
        role: ResearchFunctionTargetRole,
        handle: WorkspaceHandle
    ) async throws -> ResearchFunctionTarget {
        let note = try #require(try await handle.snapshot().document(id: id))
        return ResearchFunctionTarget(
            noteID: try #require(note.stableIdentity.resolvedID),
            note: id,
            role: role,
            lifecycle: note.lifecycle,
            fingerprint: note.fingerprint,
            title: note.document.parsedFrontmatter["title"]?.scalarString
                ?? id.relativePath
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
