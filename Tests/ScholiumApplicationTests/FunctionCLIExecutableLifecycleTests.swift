import ScholiumContracts
import Foundation
import ScholiumApplication
import Testing

@Suite("Executable Research Function CLI lifecycle")
struct FunctionCLIExecutableLifecycleTests {
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
            ["function", "availability", "--from", "-", "--format", "json"],
            stdin: try encoder.encode(fixture.analysisTarget)
        )
        let available = try decoder.decode(
            [ResearchFunctionAvailability].self,
            from: availability.stdout
        )
        #expect(available.contains { $0.function == .dialogue && $0.isEnabled })

        let dialogueRequest = ResearchFunctionRequest(
            function: .dialogue,
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

        let shownResult = try cli.run([
            "dialogue", "show", dialogue.runID.uuidString,
            "--triptych", fixture.assignment.id.uuidString,
            "--format", "json",
        ])
        let shown = try decoder.decode(DialogueEntry.self, from: shownResult.stdout)
        #expect(shown.responseContract?.knownModules == [
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
        #expect(revise.awaitsMethodSelection)

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

        let wrongConfirmation = ResearchFunctionMethodSelectionSubmission(
            runID: revise.runID,
            confirmationToken: UUID(),
            methods: []
        )
        try cli.expectFailure([
            "function", "select-methods", "--from", "-",
            "--triptych", fixture.assignment.triptych.name,
            "--format", "json",
        ], stdin: try encoder.encode(wrongConfirmation), contains: "does not match")

        let methodSelection = ResearchFunctionMethodSelectionSubmission(
            runID: revise.runID,
            confirmationToken: revise.snapshot.confirmationToken,
            methods: []
        )
        let finalizedRevise = try decoder.decode(
            ResearchFunctionPreparation.self,
            from: try cli.run([
                "function", "select-methods", "--from", "-",
                "--triptych", fixture.assignment.triptych.name,
                "--format", "json",
            ], stdin: try encoder.encode(methodSelection)).stdout
        )
        #expect(finalizedRevise.snapshot.request.methods == [])

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

        let finalWorkTarget = ResearchFunctionTarget(
            noteID: fixture.workTarget.noteID,
            note: fixture.workTarget.note,
            role: .work,
            fingerprint: finalWorkFingerprint,
            title: fixture.workTarget.title
        )
        let fidelity = try decoder.decode(
            ResearchFunctionPreparation.self,
            from: try cli.run([
                "function", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(ResearchFunctionRequest(
                function: .fidelity,
                target: finalWorkTarget,
                checks: [.content]
            ))).stdout
        )
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

        let verifiedParent = try decoder.decode(
            ResearchFunctionCompletion.self,
            from: try cli.run([
                "function", "complete", "--from", "-",
                "--triptych", fixture.assignment.id.uuidString,
                "--format", "json",
            ], stdin: try encoder.encode(ResearchFunctionCompletionSubmission(
                runID: revise.runID,
                confirmationToken: revise.snapshot.confirmationToken,
                finalTargetFingerprint: finalWorkFingerprint,
                summary: "Linked the synthetic final-revision evidence.",
                didModifyTarget: true,
                childRunIDs: [fidelity.runID]
            ))).stdout
        )
        #expect(verifiedParent.state == .complete)
        #expect(verifiedParent.childRunIDs == [fidelity.runID])

        let cancellable = try decoder.decode(
            ResearchFunctionPreparation.self,
            from: try cli.run([
                "function", "prepare", "--from", "-", "--format", "json",
            ], stdin: try encoder.encode(ResearchFunctionRequest(
                function: .dialogue,
                target: finalWorkTarget,
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
            function: .dialogue,
            target: finalWorkTarget,
            instruction: "Render a Markdown handoff fixture.",
            dialogueResponseModules: [.remainingQuestions]
        )))
        #expect(String(decoding: markdown.stdout, as: UTF8.self).contains("Scholium"))

        try cli.expectFailure(
            ["function", "prepare", "--from", "-", "--format", "json"],
            stdin: Data("{malformed".utf8),
            contains: "data"
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
                function: .dialogue,
                target: fixture.analysisTarget,
                materials: [duplicateMaterial],
                instruction: "Reject Target duplication."
            )),
            contains: "Target"
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
}

private struct CLIReadPayload: Decodable {
    let sha256: String
    let content: String
}

private struct CLICancellationReport: Decodable {
    let runID: UUID
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
        try Data("---\ntitle: Analysis\n---\n# Analysis\n\nA synthetic analysis claim.\n".utf8)
            .write(to: analyses.appendingPathComponent("Analysis.md"), options: .atomic)
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
            workTarget: workTarget
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
