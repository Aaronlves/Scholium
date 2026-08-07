import ScholiumContracts
import Foundation

extension ScholiumCLI {
    static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func printHelp() {
        printHelp(path: [], format: .text)
    }

    static func printHelp(path: [String], format: CLIOutputFormat) {
        let text = helpText(for: path)
        switch format {
        case .text, .markdown:
            write(text + (text.hasSuffix("\n") ? "" : "\n"))
        case .json:
            let report = CLIHelpReport(
                path: path,
                help: text,
                agentCommand: agentCommandHelp[path.joined(separator: " ")]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            if let data = try? encoder.encode(report) {
                write(String(decoding: data, as: UTF8.self) + "\n")
            }
        case .jsonl:
            write(text + (text.hasSuffix("\n") ? "" : "\n"))
        }
    }

    static func helpText(for path: [String]) -> String {
        let key = path.joined(separator: " ")
        if let help = agentCommandHelp[key] { return help.text }
        if let help = commandHelp[key] { return help }
        if !path.isEmpty {
            let candidates = Set(commandHelp.keys)
                .union(agentCommandHelp.keys)
                .filter { $0.hasPrefix(key + " ") }
                .sorted()
            if !candidates.isEmpty {
                return """
                scholium \(key)

                Commands:
                \(candidates.map { "  " + $0.dropFirst(key.count + 1) }.joined(separator: "\n"))

                Run `scholium help \(key) <command>` for details.
                """
            }
            return "Unknown help topic '\(key)'. Run 'scholium help'."
        }
        return """
        Scholium CLI — agent-facing, local-first research access

        Usage:
          scholium help [command [subcommand]] [--format text|json]
          scholium version [--format text|json]
          scholium doctor [--format text|json]
          scholium vault list
          scholium search <query> --vault <selector> [--triptych <selector>]
              [--limit 1...500] [--format text|jsonl]
          scholium search <query> --triptych <uuid-or-unique-name>
              [--limit 1...500] [--format text|jsonl]
          scholium links incoming <vault>:<path> --format json
          scholium links outgoing <vault>:<path> --format json
          scholium links relationships <vault>:<path> --format json
          scholium links diagnostics --workspace [--triptych <uuid-or-unique-name>] --format json
          scholium graph trace <source> <target> --max-depth 3 --format json
          scholium graph relation-trace <source> <target> --max-depth 3 --format json
          scholium workspace catalog [--triptych <uuid-or-unique-name>] --format json
          scholium workspace attention [--triptych <uuid-or-unique-name>] [--kind <queue>] --format json
          scholium workspace bootstrap --triptych <uuid-or-unique-name> --target <directory>
              [--conventions-file <file>] [--format markdown|json]
          scholium action available --from <json|-> --format json
          scholium action prepare --from <json|-> --format json|markdown
          scholium action show <run-id> [--triptych <selector>] --format json|markdown
          scholium action prepare-fidelity <parent-run-id> [--triptych <selector>] --format json|markdown
          scholium action cancel <run-id> [--triptych <selector>]
          scholium read <vault>:<relative-path> [--format json]
          scholium note create <vault>:<path> --from <markdown-file>
          scholium note replace <vault>:<path> --from <markdown-file> --expected <sha256>
          scholium note move <vault>:<path> <new-path> --expected <sha256>
          scholium note set-aside <vault>:<path> --expected <sha256>
          scholium note trash <vault>:<path> --expected <sha256>
          scholium note delete <vault>:<Trash/path> --permanent --expected <sha256>
          scholium discuss list [--triptych <uuid-or-unique-name>]
              [--format json]
          scholium discuss show <discussion-id> [--triptych <uuid-or-unique-name>] [--format json]
          scholium discuss reply <discussion-id> --agent <name> (--text <reply> | --from <file|->)
              [--triptych <uuid-or-unique-name>]
          scholium zotero mcp config [--format text|json]
          scholium zotero mcp status [--probe] [--format text|json]
          scholium zotero mcp serve
        \(agentCommandUsage)
        Omitting --triptych requires exactly one configured Triptych.
        Triptych roles: analyses, topics, works
        Authenticated Agent commands preserve Run, Method, Practice, Research
        Context, Bounded Write Set, Result, and continuation boundaries. The
        CLI never scans Skill folders or grants edit permission.
        Workspace bootstrap is candidate-only: it never writes or overwrites AGENTS.md.
        Zotero MCP status locates Scholium's first-party CLI transport by default.
        Add --probe to perform only the MCP initialize lifecycle check; it does
        not read Zotero data or perform an import.
        Registry roles and accepted aliases:
        source_corpus, topic_knowledge, draft_project, other,
        sources, knowledge, project, and works.

        Existing-note mutations require the exact SHA-256 reported by
        `scholium read --format json`. Fingerprints prevent stale overwrites;
        they are revision checks, not permission tokens. The researcher remains
        responsible for deciding when an agent may edit Triptych files.
        """
    }

    static func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    static func writeError(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }
}

enum CLIOutputFormat: String {
    case text
    case json
    case jsonl
    case markdown
}

private struct CLIHelpReport: Encodable {
    let schemaVersion = 2
    let path: [String]
    let help: String
    let agentCommand: AgentCLICommandHelp?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case path, help
        case agentCommand = "agent_command"
    }
}

private struct AgentCLICommandHelp: Encodable {
    let usage: String
    let inputContract: String
    let input: String
    let output: String
    let nextSteps: [String]

    var text: String {
        """
        Usage: \(usage)

        Input contract: \(inputContract)
        Input: \(input)

        Output: \(output)

        Next:
        \(nextSteps.map { "  " + $0 }.joined(separator: "\n"))
        """
    }

    private enum CodingKeys: String, CodingKey {
        case usage, input, output
        case inputContract = "input_contract"
        case nextSteps = "next_steps"
    }
}

private extension ScholiumCLI {
    static let agentCommandOrder = [
        "agent pair",
        "agent context",
        "agent reload",
        "agent query",
        "agent extend-write-set",
        "agent write",
        "agent resolve-write-conflict",
        "agent submit-result",
        "agent continue",
        "agent method-context",
        "agent improve-method",
        "agent end",
    ]

    static var agentCommandUsage: String {
        agentCommandOrder.compactMap { key in
            agentCommandHelp[key].map { "  " + $0.usage }
        }.joined(separator: "\n")
    }

    static var agentCommandHelp: [String: AgentCLICommandHelp] {
        let roles = ResearchActionTargetRole.allCases.map(\.rawValue)
            .joined(separator: ", ")
        let writeOperations = ResearchDocumentWriteOperation.allCases
            .map(\.rawValue)
            .joined(separator: ", ")
        let contextClauses = ResearchContextClauseKind.allCases.map(\.rawValue)
            .joined(separator: ", ")
        let epistemicStatuses = ResearchContinuationEpistemicStatus.allCases
            .map(\.rawValue)
            .joined(separator: ", ")

        return [
            "agent pair": AgentCLICommandHelp(
                usage: "scholium agent pair --run <locator>",
                inputContract: "ResearchPairingCode on standard input",
                input: "When prompted, enter the one-time Pairing Code from the current handoff. Do not put it in an argument, URL, file, or log.",
                output: "AgentPairingReport with paired=true and the Run locator. The exchanged Session credential is stored in protected local state and is not printed.",
                nextSteps: [
                    "scholium agent context --run <locator>",
                ]
            ),
            "agent context": AgentCLICommandHelp(
                usage: "scholium agent context --run <locator>",
                inputContract: "Authenticated Run locator; no JSON body",
                input: "Use the Run locator from the handoff. The CLI loads the hidden Session credential from protected local state.",
                output: "ResearchAuthenticatedRunContext: Core Protocol on first delivery, Run Brief, frozen Method and Practices, Result Contract, current bounded write set, and any continuation handoff.",
                nextSteps: [
                    "scholium agent query --run <locator> --from <json|-> when more Research Context is needed",
                    "scholium agent reload --run <locator> whenever current Run state is uncertain",
                ]
            ),
            "agent reload": AgentCLICommandHelp(
                usage: "scholium agent reload --run <locator>",
                inputContract: "Authenticated Run locator; no JSON body",
                input: "Use the current Run locator. No earlier Research Context response is accepted as input or replayed.",
                output: "ResearchAuthenticatedRunContext with the current Run Brief, frozen Method and Practices, Result Contract, bounded write set, and continuation handoff. The one-time Core Protocol is not replayed.",
                nextSteps: [
                    "Follow the returned current state and run the applicable agent command",
                    "scholium agent end --run <locator> to stop an unfinished Run",
                ]
            ),
            "agent query": AgentCLICommandHelp(
                usage: "scholium agent query --run <locator> --from <json|->",
                inputContract: "ResearchContextRequest schema \(ResearchContextRequest.currentSchemaVersion)",
                input: "Strict JSON fields: schemaVersion, id, clauses (1...\(ResearchContextRequest.maximumClauses)). Every clause has schemaVersion, id, kind [\(contextClauses)], scope=triptych, limit 1...\(ResearchContextClause.maximumLimit), useEligibility, and only the query, sectionHeading, or cursor fields allowed by its closed kind.",
                output: "ResearchContextResponse schema \(ResearchContextResponse.currentSchemaVersion) with one visible availability, items, limitations, and optional stateless continuation cursor for every requested clause.",
                nextSteps: [
                    "Repeat scholium agent query with a narrower request when needed",
                    "Use the returned context in the current Method, then continue to the applicable write or Result command",
                ]
            ),
            "agent extend-write-set": AgentCLICommandHelp(
                usage: "scholium agent extend-write-set --run <locator> --from <json|->",
                inputContract: "ResearchWriteSetExtensionIntent schema \(ResearchWriteSetExtensionIntent.currentSchemaVersion)",
                input: "Strict JSON fields: schema_version, targets (1...\(ResearchBoundedWriteSet.maximumEntriesPerRequest)); each target has role [\(roles)], relative_path, and operations [\(writeOperations)]; academic_reason explains why the current Method needs these targets.",
                output: "AgentWriteSetReport with state, the current capability-free bounded-write-set entries, and a message.",
                nextSteps: [
                    "scholium agent reload --run <locator> after a pending researcher decision",
                    "scholium agent write --run <locator> --from <json|-> for one returned ready member",
                ]
            ),
            "agent write": AgentCLICommandHelp(
                usage: "scholium agent write --run <locator> --from <json|->",
                inputContract: "AgentDocumentWriteDraft",
                input: "Strict JSON fields: role [\(roles)], relative_path, optional operation [\(writeOperations)] defaulting to modify_markdown, and content containing the complete intended UTF-8 Markdown.",
                output: "AgentDocumentWriteReport with state, the current target view, and a message. Scholium supplies identity, revision, checkpoint, and retry authority.",
                nextSteps: [
                    "scholium agent resolve-write-conflict --run <locator> --from <json|-> when the returned state is conflict",
                    "Continue with another ready member or scholium agent submit-result after a confirmed write",
                ]
            ),
            "agent resolve-write-conflict": AgentCLICommandHelp(
                usage: "scholium agent resolve-write-conflict --run <locator> --from <json|->",
                inputContract: "AgentWriteConflictResolutionDraft",
                input: "Strict JSON fields: role [\(roles)], relative_path, and action [refresh_authority, abandon_write].",
                output: "AgentWriteConflictResolutionReport with state, the updated target view, and a message.",
                nextSteps: [
                    "After refresh_authority, query or reread the changed Markdown before creating a new agent write input",
                    "After abandon_write, continue with another member or submit an accurate Result",
                ]
            ),
            "agent submit-result": AgentCLICommandHelp(
                usage: "scholium agent submit-result --run <locator> --from <json|->",
                inputContract: "ResearchAgentResultSubmission schema \(ResearchAgentResultSubmission.currentSchemaVersion) plus the current Run result_contract",
                input: "Strict JSON fields: schema_version, disposition [completed, blocked], academic_results filled exactly from result_contract, context_use_claims with returned source_reference envelopes and testimony, fidelity_outcomes, and optional literature_recommendations only when the contract permits them.",
                output: "ResearchAgentResultReceipt with disposition, finalization state, whether a portable Record was formed, and a message.",
                nextSteps: [
                    "scholium agent continue --run <locator> --from <json|-> only for a distinct next Action",
                    "Stop after a finalized Result when no distinct next Action is needed",
                ]
            ),
            "agent continue": AgentCLICommandHelp(
                usage: "scholium agent continue --run <locator> --from <json|->",
                inputContract: "ResearchContinuationRequest schema \(ResearchContinuationRequest.currentSchemaVersion)",
                input: "Strict JSON fields: schema_version, next_action_id, target_role [\(roles)], target_relative_path, academic_purpose, handoff items, and fidelity_checks [content, citations]. Each handoff item has content, epistemic_status [\(epistemicStatuses)], next_use, and source_references.",
                output: "ResearchContinuationResult with pending_researcher_decision, created, declined, stale, or expired state; a created result also returns the fresh next Run and handoff context.",
                nextSteps: [
                    "Pair the returned next_run only when state is created and the researcher has received its new handoff",
                    "Otherwise follow the returned state and message; no authority carries forward",
                ]
            ),
            "agent method-context": AgentCLICommandHelp(
                usage: "scholium agent method-context --run <locator>",
                inputContract: "Authenticated Method-improvement Run locator; no JSON body",
                input: "Use the locator from an explicit Improve Current Method handoff. The CLI loads the hidden Session credential.",
                output: "ResearchMethodImprovementContext with the unchanged researcher feedback, finalized Result fingerprint, and exact primary Method and linked Practice targets.",
                nextSteps: [
                    "scholium agent improve-method --run <locator> --from <json|-> for at most one returned target_id",
                    "scholium agent end --run <locator> if the improvement Run cannot continue",
                ]
            ),
            "agent improve-method": AgentCLICommandHelp(
                usage: "scholium agent improve-method --run <locator> --from <json|->",
                inputContract: "ResearchMethodImprovementDraft",
                input: "Strict JSON fields: target_id from method-context, disposition [replace, diagnosed_no_change, unavailable], optional replacement_source only for replace, and diagnosis.",
                output: "ResearchMethodImprovementReceipt with the target, starting and ending revisions, disposition, diagnosis, and whether unchanged feedback was cleared.",
                nextSteps: [
                    "scholium agent end --run <locator>",
                ]
            ),
            "agent end": AgentCLICommandHelp(
                usage: "scholium agent end --run <locator>",
                inputContract: "Authenticated Run locator; no JSON body",
                input: "Use the current unfinished Run locator. No Result or cancellation payload is accepted.",
                output: "ResearchRunEndReceipt with retained-recovery truth and a message; the acknowledged local Session credential is then removed.",
                nextSteps: [
                    "Stop using this Run locator; new Agent access requires a new researcher-provided handoff",
                ]
            ),
        ]
    }

    static var searchHelp: String {
        let capabilities = SearchCapabilities.current
        let noteFields = capabilities.capability(for: .note)?
            .fields.map { "\($0.name):" }.joined(separator: ", ") ?? ""
        let recordFields = capabilities.capability(for: .record)?
            .fields.map { "\($0.name):" }.joined(separator: ", ") ?? ""
        let examples = capabilities.providers
            .flatMap(\.examples)
            .map { "  scholium search '\($0)' --triptych <selector>" }
            .joined(separator: "\n")
        return """
        Usage: scholium search <query> (--vault <selector> [--triptych <selector>] | --triptych <selector>) [--limit <count>] [--format text|jsonl]

        The positional query uses the shared Search v\(capabilities.contractVersion) grammar. Search Notes by default or select portable Research Records inside the query with kind:record.
        Note fields: \(noteFields)
        Record fields: \(recordFields)
        Provider choice, properties, and relationships are query clauses, not separate CLI options.

        Examples:
        \(examples)
        """
    }

    static var commandHelp: [String: String] {
        [
            "vault list": "Usage: scholium vault list [--format text|json]\n\nLists registered Triptychs and their three role vaults.",
            "search": searchHelp,
            "links incoming": "Usage: scholium links incoming <vault>:<path> --format json",
            "links outgoing": "Usage: scholium links outgoing <vault>:<path> --format json",
            "links relationships": "Usage: scholium links relationships <vault>:<path> --format json",
            "links diagnostics": "Usage: scholium links diagnostics --workspace [--triptych <selector>] --format json",
            "graph trace": "Usage: scholium graph trace <source> <target> [--max-depth <1...10>] --format json",
            "graph relation-trace": "Usage: scholium graph relation-trace <source> <target> [--max-depth <1...10>] --format json",
            "workspace catalog": "Usage: scholium workspace catalog [--triptych <selector>] --format json",
            "workspace attention": "Usage: scholium workspace attention [--triptych <selector>] [--kind <queue>] --format json",
            "workspace bootstrap": "Usage: scholium workspace bootstrap --triptych <selector> --target <directory> [--conventions-file <file>] [--format markdown|json]",
            "action available": "Usage: scholium action available --from <target-json|-> --format json",
            "action prepare": "Usage: scholium action prepare --from <request-json|-> --format json|markdown",
            "action show": "Usage: scholium action show <run-id> [--triptych <selector>] --format json|markdown",
            "action prepare-fidelity": "Usage: scholium action prepare-fidelity <parent-run-id> [--triptych <selector>] --format json|markdown\n\nPrepares or reuses the required final-revision Fidelity child for a completed Analyze, Synthesize, or Write Action.",
            "action cancel": "Usage: scholium action cancel <run-id> [--triptych <selector>] [--format json]",
            "read": "Usage: scholium read <vault>:<relative-path> [--format text|json]",
            "note create": "Usage: scholium note create <vault>:<path> --from <markdown-file>",
            "note replace": "Usage: scholium note replace <vault>:<path> --from <markdown-file> --expected <sha256>",
            "note move": "Usage: scholium note move <vault>:<path> <new-relative-path> --expected <sha256>",
            "note set-aside": "Usage: scholium note set-aside <vault>:<path> --expected <sha256>",
            "note trash": "Usage: scholium note trash <vault>:<path> --expected <sha256>",
            "note delete": "Usage: scholium note delete <vault>:<Trash/path> --permanent --expected <sha256>",
            "discuss list": "Usage: scholium discuss list [--triptych <selector>] [--format text|json]",
            "discuss show": "Usage: scholium discuss show <discussion-id> [--triptych <selector>] [--format text|json]",
            "discuss reply": "Usage: scholium discuss reply <discussion-id> --agent <name> (--text <reply> | --from <file|->) [--triptych <selector>]",
            "zotero mcp config": "Usage: scholium zotero mcp config [--format text|json]",
            "zotero mcp status": "Usage: scholium zotero mcp status [--probe] [--format text|json]",
            "zotero mcp serve": "Usage: scholium zotero mcp serve",
        ]
    }
}


enum CLIError: LocalizedError {
    case usage(String)
    case invalidUTF8(String)
    case noteNotFound(String)
    case unavailable(String)
    case searchDiagnostic(SearchQueryDiagnostic)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        case .invalidUTF8(let path): return "File is not valid UTF-8: \(path)"
        case .noteNotFound(let target): return "The workspace note was not found: \(target)"
        case .unavailable(let message): return message
        case .searchDiagnostic(let diagnostic): return diagnostic.message
        }
    }
}
