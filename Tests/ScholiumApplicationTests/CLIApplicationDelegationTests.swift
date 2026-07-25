import Foundation
import ScholiumContracts
import Testing

@Suite("CLI Application delegation")
struct CLIApplicationDelegationTests {
    @Test("CLI command families delegate to one snapshot runtime")
    func commandFamiliesUseApplicationCapabilities() throws {
        let sources = try CLISources.load()

        #expect(sources.context.contains("WorkspaceRuntime.snapshot("))
        #expect(sources.entry.contains("let context = try await CLIContext.make()"))
        #expect(sources.entry.contains("await context.shutdown()"))
        #expect(sources.workspace.contains("handle.discovery.search("))
        #expect(sources.workspace.contains("handle.discovery.snapshot().catalog"))
        #expect(sources.workspace.contains("let research = handle.research"))
        #expect(sources.workspace.contains("research.activeDiscussions(noteID: nil)"))
        #expect(sources.entry.contains(#"case "discuss":"#))
        #expect(sources.workspace.contains("research.activeDiscussion(id: id)"))
        #expect(sources.workspace.contains("research.appendDiscussionStatement("))
        #expect(sources.document.contains("handle.documents.load("))
        #expect(sources.document.contains("handle.documents.create("))
        #expect(sources.document.contains("handle.documents.save("))
        #expect(sources.document.contains("handle.documents.move("))
        #expect(sources.document.contains("handle.documents.deletePermanently("))
        #expect(sources.entry.contains(#"case "zotero":"#))
        #expect(sources.entry.contains("context: context"))
        #expect(sources.zotero.contains("context.runtime.zotero"))
        #expect(sources.zotero.contains("operations.handle(requestData: frame.body)"))
        #expect(!sources.zotero.contains("ZoteroMCPServer("))
        #expect(!sources.zotero.contains("ZoteroMCPTransportLocator."))
    }

    @Test("Function CLI is a thin Contracts-to-Application adapter")
    func functionCommandsDelegateWithoutRoutingPolicy() throws {
        let sources = try CLISources.load()

        #expect(sources.entry.contains(#"case "function":"#))
        #expect(sources.function.contains("handle.research.availableFunctions(for: target)"))
        #expect(sources.function.contains("handle.research.prepareFunction(request)"))
        #expect(sources.function.contains("handle.research.functionRun(id: runID)"))
        #expect(sources.function.contains("handle.research.prepareAutomaticFidelity("))
        #expect(!sources.function.contains("select-resources"))
        #expect(sources.function.contains("handle.research.completeFunction(submission)"))
        #expect(sources.function.contains("handle.research.cancelFunction(runID: runID)"))
        #expect(!sources.function.contains("import " + "ScholiumCore"))
        #expect(!sources.function.contains("supportedFunctions"))
        #expect(!sources.function.contains("supported_modes"))
        #expect(!sources.function.contains("packageID"))
        #expect(!sources.function.contains("createCheckpoint"))
    }

    @Test("Function CLI preserves legacy conditional values without making them active")
    func functionJSONRoundTrips() throws {
        let target = ResearchFunctionTarget(
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Work.md"),
            role: .work,
            fingerprint: DocumentFingerprint(content: "work"),
            title: "Work"
        )
        let request = ResearchFunctionRequest(
            function: .revise,
            target: target,
            instruction: "Strengthen only the stated inference.",
            scope: .whole,
            conditionalResources: [.revisionFeedback]
        )
        let submission = ResearchFunctionCompletionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            finalTargetFingerprint: DocumentFingerprint(content: "revised"),
            summary: "Revised and checked.",
            didModifyTarget: true,
            fidelityOutcomes: [FidelityCheckOutcome(
                check: .content,
                state: .passed,
                summary: "No unresolved fidelity finding."
            )],
            childRunIDs: [UUID()],
            submittedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let methodSelection = ResearchFunctionResourceSelectionSubmission(
            runID: UUID(),
            confirmationToken: UUID(),
            resources: [.revisionFeedback]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        #expect(try decoder.decode(
            ResearchFunctionRequest.self,
            from: encoder.encode(request)
        ) == request)
        #expect(throws: ResearchFunctionContractError.self) {
            try request.validate()
        }
        #expect(try decoder.decode(
            ResearchFunctionCompletionSubmission.self,
            from: encoder.encode(submission)
        ) == submission)
        #expect(try decoder.decode(
            ResearchFunctionResourceSelectionSubmission.self,
            from: encoder.encode(methodSelection)
        ) == methodSelection)
    }

    @Test("Bibliography CLI is a thin Contracts-to-Application adapter")
    func bibliographyCommandsDelegateWithoutPolicy() throws {
        let sources = try CLISources.load()

        #expect(sources.entry.contains(#"case "bibliography":"#))
        #expect(sources.bibliography.contains("handle.research.prepareRecommendation(request)"))
        #expect(sources.bibliography.contains("handle.research.recommendationRequest(id: requestID)"))
        #expect(sources.bibliography.contains("handle.research.completeRecommendation(submission)"))
        #expect(sources.bibliography.contains("handle.research.cancelRecommendation(id: requestID)"))
        #expect(!sources.bibliography.contains("import " + "ScholiumCore"))
        #expect(!sources.bibliography.contains("bibliographyRecommendation"))
        #expect(!sources.bibliography.contains("zotero.resolve"))
        #expect(!sources.bibliography.contains("recommended-bibliography.json"))
    }

    @Test("Search v4, catalog, read, and lifecycle output schemas remain stable")
    func serializedOutputContractsRemainStable() throws {
        let sources = try CLISources.load()

        #expect(sources.workspace.contains(
            #"[retrieval_lead; \(hit.rankReason.rawValue)]\n  \(hit.snippet)\n"#
        ))
        #expect(sources.workspace.contains(
            "let summary = SearchSummaryRecord(response: response)"
        ))
        #expect(sources.workspace.contains(
            "encoder.encode(SearchResultRecord(hit: hit))"
        ))
        #expect(sources.workspace.contains(#"let type = "search_summary""#))
        #expect(sources.workspace.contains(#"let type = "search_result""#))
        #expect(sources.workspace.contains("case contractVersion = \"contract_version\""))
        #expect(!sources.workspace.contains("raw_score"))
        #expect(sources.workspace.contains(
            "String(decoding: try encoder.encode(snapshot), as: UTF8.self) + \"\\n\""
        ))
        for key in ["vault_id", "vault_name", "relative_path", "sha256", "content"] {
            #expect(sources.document.contains("\"\(key)\""))
        }
        #expect(sources.document.contains("Created "))
        #expect(sources.document.contains("Replaced "))
        #expect(sources.document.contains("Moved "))
        #expect(sources.document.contains("Permanently deleted "))
        #expect(sources.zotero.contains(
            #"write("Zotero MCP transport: \(report.state.rawValue)\n")"#
        ))
        #expect(sources.zotero.contains(
            #"Data("Content-Length: \(body.count)\r\n\r\n".utf8) + body"#
        ))
        #expect(sources.zotero.contains(
            #"FileHandle.standardOutput.write(body + Data([0x0A]))"#
        ))
    }
}

private struct CLISources {
    let entry: String
    let context: String
    let workspace: String
    let document: String
    let zotero: String
    let function: String
    let bibliography: String

    static func load() throws -> Self {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let cli = root.appendingPathComponent("ScholiumCLI", isDirectory: true)
        return try Self(
            entry: String(
                contentsOf: cli.appendingPathComponent("CLIEntry.swift"),
                encoding: .utf8
            ),
            context: String(
                contentsOf: cli.appendingPathComponent("CLIContext.swift"),
                encoding: .utf8
            ),
            workspace: String(
                contentsOf: cli.appendingPathComponent("WorkspaceCommandHandlers.swift"),
                encoding: .utf8
            ),
            document: String(
                contentsOf: cli.appendingPathComponent("DocumentCommandHandler.swift"),
                encoding: .utf8
            ),
            zotero: String(
                contentsOf: cli.appendingPathComponent("ZoteroCommandHandler.swift"),
                encoding: .utf8
            ),
            function: String(
                contentsOf: cli.appendingPathComponent("ResearchFunctionCommandHandler.swift"),
                encoding: .utf8
            ),
            bibliography: String(
                contentsOf: cli.appendingPathComponent(
                    "RecommendedBibliographyCommandHandler.swift"
                ),
                encoding: .utf8
            )
        )
    }
}
