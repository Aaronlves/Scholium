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
        #expect(sources.workspace.contains("handle.discovery.links("))
        #expect(sources.workspace.contains("handle.discovery.relationships("))
        #expect(sources.workspace.contains("handle.discovery.linkDiagnostics("))
        #expect(sources.workspace.contains("handle.discovery.traceLinks("))
        #expect(sources.workspace.contains("handle.discovery.traceRelationships("))
        #expect(!sources.workspace.contains("tracePaths("))
        #expect(!sources.workspace.contains("relationshipTracePaths("))
        #expect(!sources.workspace.contains("subjectNote == nil"))
        #expect(sources.workspace.contains(
            "context.runtime.skillDiscoverySourceManifest("
        ))
        #expect(sources.workspace.contains("Workspace Skill sources supports --format json"))
        let discoveryStart = try #require(sources.runtime.range(
            of: "    public func skillDiscoverySourceManifest("
        ))
        let discoveryEnd = try #require(sources.runtime.range(
            of: "    public func registeredVaults()",
            range: discoveryStart.upperBound..<sources.runtime.endIndex
        ))
        let discovery = String(
            sources.runtime[discoveryStart.lowerBound..<discoveryEnd.lowerBound]
        )
        #expect(discovery.contains("ResearchConfigurationStore("))
        #expect(discovery.contains("configuration.skillDiscoverySourceManifest("))
        #expect(!discovery.contains("openWorkspace("))
        #expect(!discovery.contains("WorkspaceHandle.open("))
        #expect(!discovery.contains("sourceInventory("))
        #expect(!discovery.contains("searchIndex"))
        #expect(sources.workspace.contains("let research = handle.research"))
        #expect(sources.workspace.contains("research.activeDiscussions(noteID: nil)"))
        #expect(sources.entry.contains(#"case "discuss":"#))
        #expect(sources.workspace.contains("research.activeDiscussion(id: id)"))
        #expect(sources.workspace.contains("research.replyToDiscussionAndFinish("))
        #expect(sources.document.contains("handle.documents.load("))
        #expect(sources.document.contains("handle.documents.metadata("))
        #expect(sources.document.contains("handle.documents.saveMetadata("))
        #expect(sources.document.contains("expectedRevision: expectedRevision"))
        #expect(sources.document.contains("metadata_sha256"))
        #expect(!sources.document.contains("import " + "ScholiumCore"))
        #expect(!sources.document.contains("note-metadata/v1"))
        #expect(sources.document.contains("handle.documents.importMarkdownSource("))
        #expect(sources.document.contains("handle.documents.save("))
        #expect(sources.document.contains("handle.documents.move("))
        #expect(sources.document.contains("handle.documents.prepareSystemTrash("))
        #expect(sources.document.contains("handle.documents.moveToSystemTrash("))
        #expect(!sources.document.contains("--delete-associated-records"))
        #expect(sources.entry.contains(#"case "zotero":"#))
        #expect(sources.entry.contains("context: context"))
        #expect(sources.zotero.contains("context.runtime.zotero"))
        #expect(sources.zotero.contains("operations.handle(requestData: frame.body)"))
        #expect(!sources.zotero.contains("ZoteroMCPServer("))
        #expect(!sources.zotero.contains("ZoteroMCPTransportLocator."))
    }

    @Test("External Agent Actions use one Contracts-to-Application command family")
    func agentCommandsDelegateWithoutParallelActionRouting() throws {
        let sources = try CLISources.load()

        #expect(!sources.entry.contains(#"case "action":"#))
        #expect(!sources.output.contains("scholium action prepare"))
        #expect(sources.agent.contains("operations.start("))
        #expect(sources.agent.contains("credentialStore.prepare()"))
        #expect(sources.agent.contains("operations.revokeSession(credential)"))
        #expect(sources.agent.contains("operations.context("))
        #expect(sources.agent.contains("operations.query("))
        #expect(sources.agent.contains("operations.submitResult("))
        #expect(sources.agent.contains("operations.continueResearch("))
        #expect(sources.agent.contains("operations.end("))
        #expect(sources.agent.contains("ResearchAgentStartRequest.self"))
        #expect(sources.agent.contains("ResearchActionTargetRole"))
        #expect(!sources.agent.contains("import " + "ScholiumCore"))
        for parallelActionOwner in [
            "ResearchFunction",
            "ResearchActionUseCases",
            "ResearchActionRunCoordinator",
            "ResearchActionExecutionRequest",
            "prepareResearchAction",
        ] {
            #expect(!sources.agent.contains(parallelActionOwner))
        }
        #expect(!sources.agent.contains("packageID"))
        #expect(!sources.agent.contains("createCheckpoint"))
    }

    @Test("CLI JSON uses the public Action request and authenticated Agent Result contracts")
    func actionJSONRoundTrips() throws {
        let target = ResearchActionNoteSnapshot(
            noteID: UUID(),
            note: VaultQualifiedNoteID(vaultID: UUID(), relativePath: "Work.md"),
            role: .work,
            fingerprint: DocumentFingerprint(content: "work"),
            title: "Work"
        )
        let profile = try #require(
            ResearchAcademicProfileCatalog.defaultProfiles.first {
                $0.actionID == .write
            }
        )
        let request = ResearchActionExecutionRequest(
            actionID: .write,
            expectedProfileRevision: DocumentFingerprint(content: "profile"),
            expectedProfileDocumentRevision: nil,
            target: target,
            platformInputs: try ResearchActionPlatformInputs(),
            academicInputs: try ResearchAcademicFieldValues(
                values: [:],
                definitions: profile.academicInputFields
            )
        )
        var rawResults: [String: ResearchAcademicFieldValue] = [:]
        for definition in profile.academicResultFields
            where definition.requirement != .excluded {
            rawResults[definition.fieldID.rawValue] = switch definition.kind {
            case .freeText:
                .freeText("Revised one bounded claim and retained uncertainty.")
            case .singleChoice:
                .singleChoice(try #require(definition.choices.first?.value))
            case .multipleChoice:
                .multipleChoice([try #require(definition.choices.first?.value)])
            }
        }
        let submission = try ResearchAgentResultSubmission(
            recordTitle: ResearchRecordTitle("CLI delegated result"),
            academicResults: ResearchAcademicFieldValues(
                rawValues: rawResults,
                definitions: profile.academicResultFields
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        #expect(try decoder.decode(
            ResearchActionExecutionRequest.self,
            from: encoder.encode(request)
        ) == request)
        #expect(try decoder.decode(
            ResearchAgentResultSubmission.self,
            from: encoder.encode(submission)
        ) == submission)
    }

    @Test("Search v9, catalog, read, and operation output schemas remain stable")
    func serializedOutputContractsRemainStable() throws {
        let sources = try CLISources.load()

        #expect(sources.workspace.contains(
            "for result in response.results"
        ))
        #expect(sources.workspace.contains(
            "let summary = SearchSummaryRecord(response: response)"
        ))
        #expect(sources.workspace.contains(
            "encoder.encode(SearchResultJSONRecord("
        ))
        #expect(sources.workspace.contains(#"let type = "search_summary""#))
        #expect(sources.workspace.contains(#"let type = "search_result""#))
        #expect(sources.workspace.contains("let availability: SearchAvailabilityRecord"))
        #expect(sources.workspace.contains("let normalization: [SearchExplanationNormalization]"))
        #expect(sources.workspace.contains("let ordering: SearchExplanationOrdering"))
        #expect(sources.workspace.contains("let limitations: [SearchExplanationLimitation]"))
        #expect(sources.workspace.contains("let provider = SearchProvider.note"))
        #expect(sources.workspace.contains("let provider = SearchProvider.record"))
        #expect(sources.workspace.contains("let matchReasons: [SearchMatchReasonRecord]"))
        #expect(sources.workspace.contains("let locator: NoteSearchLocatorRecord"))
        #expect(sources.workspace.contains("let locator: RecordSearchLocatorRecord"))
        #expect(sources.workspace.contains("let statementAuthor: PortableResearchStatementAuthor?"))
        #expect(sources.workspace.contains("let fingerprint: DocumentFingerprint"))
        #expect(sources.workspace.contains("let freshnessToken: SearchFreshnessToken"))
        #expect(sources.workspace.contains("encoder.keyEncodingStrategy = .convertToSnakeCase"))
        #expect(sources.output.contains("let capabilities = SearchCapabilities.current"))
        #expect(sources.catalog.contains("help: searchHelp"))
        #expect(sources.arguments.contains("commandSpecifications[key]?.rule"))
        #expect(!sources.arguments.contains("commandRules"))
        #expect(sources.output.contains("commandSpecifications[key]"))
        #expect(!sources.output.contains("commandHelp"))
        #expect(!sources.workspace.contains("raw_score"))
        #expect(sources.workspace.contains(
            "String(decoding: try encoder.encode(snapshot), as: UTF8.self) + \"\\n\""
        ))
        for key in ["vault_id", "vault_name", "relative_path", "sha256", "content"] {
            #expect(sources.document.contains("\"\(key)\""))
        }
        #expect(sources.document.contains("write(document.rawContent)"))
        #expect(!sources.document.contains("write(document.rawContent + \"\\n\")"))
        #expect(sources.document.contains("Created "))
        #expect(sources.document.contains("Replaced "))
        #expect(sources.document.contains("Moved "))
        #expect(sources.document.contains("to the macOS Trash"))
        #expect(sources.document.contains("Finder owns file restoration"))
        #expect(sources.document.contains("let document = outcome.committedValue"))
        #expect(sources.document.contains("writeMutationWarnings(outcome)"))
        #expect(sources.document.contains("do not repeat the mutation"))
        #expect(!sources.document.contains("outcome.cleanupWarnings"))
        #expect(!sources.document.contains("machine-local cleanup is still pending"))
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
    let runtime: String
    let workspace: String
    let output: String
    let document: String
    let zotero: String
    let agent: String
    let arguments: String
    let catalog: String

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
            runtime: String(
                contentsOf: root.appendingPathComponent(
                    "ScholiumApplication/WorkspaceRuntime.swift"
                ),
                encoding: .utf8
            ),
            workspace: String(
                contentsOf: cli.appendingPathComponent("WorkspaceCommandHandlers.swift"),
                encoding: .utf8
            ),
            output: String(
                contentsOf: cli.appendingPathComponent("CLIOutput.swift"),
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
            agent: String(
                contentsOf: cli.appendingPathComponent("AgentCommandHandler.swift"),
                encoding: .utf8
            ),
            arguments: String(
                contentsOf: cli.appendingPathComponent("CLIArguments.swift"),
                encoding: .utf8
            ),
            catalog: String(
                contentsOf: cli.appendingPathComponent("CLICommandCatalog.swift"),
                encoding: .utf8
            )
        )
    }
}
