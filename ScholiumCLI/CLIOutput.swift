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
          scholium workspace skill-sources [--triptych <uuid-or-unique-name>] --format json
          scholium workspace attention [--triptych <uuid-or-unique-name>] [--kind <queue>] --format json
          scholium workspace bootstrap --triptych <uuid-or-unique-name> --target <directory>
              [--conventions-file <file>] [--format markdown|json]
          scholium action available --from <json|-> --format json
          scholium action prepare --from <json|-> --format json|markdown
          scholium action show <run-id> [--triptych <selector>] --format json|markdown
          scholium action cancel <run-id> [--triptych <selector>]
          scholium read <vault>:<relative-path> [--format json]
          scholium note create <vault>:<path> [--body-from <text-file>]
              [--analysis-from <json-file>]
          scholium note import <vault>:<path> --from <markdown-file>
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
        CLI never scans arbitrary Skill folders or grants edit permission.
        Workspace Skill sources reports exact registered project-discovery
        candidates; it creates no link and exposes no machine-local Method.
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
        "agent start",
        "agent pair",
        "agent context",
        "agent prepare-fidelity",
        "agent reload",
        "agent query",
        "agent discuss-reply",
        "agent extend-write-set",
        "agent write",
        "agent write-zotero-binding",
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
        let documentWriteOperations = ResearchDocumentWriteOperation.allCases
            .filter { !$0.isZoteroBindingOperation }
            .map(\.rawValue)
            .joined(separator: ", ")
        let contextClauses = ResearchContextClauseKind.allCases.map(\.rawValue)
            .joined(separator: ", ")
        let epistemicStatuses = ResearchContinuationEpistemicStatus.allCases
            .map(\.rawValue)
            .joined(separator: ", ")

        return [
            "agent start": AgentCLICommandHelp(
                usage: "scholium agent start --triptych <selector> --from <json|->",
                inputContract: "ResearchAgentStartRequest schema \(ResearchAgentStartRequest.currentSchemaVersion)",
                input: "Strict JSON fields: schema_version, action_id, exactly one of target {vault_id, relative_path} or new_analysis {schema_version, request_id, target {vault_id, relative_path}, metadata {source_type, properties}, optional source {library, item_key}}, optional source_route=researcher_provided, and optional academic_purpose. new_analysis is Analyze-only: Scholium uses the managed creator, binds an explicitly declared Zotero route when present, or accepts a researcher-provided source without a path, then resolves the ordinary Action Profile, Method, revision, and Bounded Write Set.",
                output: "ResearchAgentStartReceipt with the new Run locator, Action, target revision, state, and a non-secret message. The Session credential is stored in protected local state and is not printed.",
                nextSteps: [
                    "scholium agent context --run <locator>",
                    "Continue with the returned current Bounded Write Set and Result Contract; no Pairing Code is required",
                ]
            ),
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
                output: "ResearchAuthenticatedRunContext: Core Protocol on first delivery, Run Brief with current state, frozen Method and Practices, Result Contract, any exact Fidelity target/material/source boundary with ready inspection_requests, current bounded write set, continuation handoff, and typed next_actions.",
                nextSteps: [
                    "scholium agent query --run <locator> --from <json|-> when more Research Context is needed",
                    "scholium agent reload --run <locator> whenever current Run state is uncertain",
                ]
            ),
            "agent prepare-fidelity": AgentCLICommandHelp(
                usage: "scholium agent prepare-fidelity --run <parent-locator>",
                inputContract: "Authenticated parent Run locator; no JSON body",
                input: "Use this only after the parent Result returns awaiting_fidelity. The CLI authenticates the parent Session; raw child UUIDs do not grant access.",
                output: "ResearchAgentFidelityPreparationReceipt. An unfinished exact-revision child returns both a new opaque child_run locator attached read-only to the same protected Session and its complete child_context. That context contains the exact target revisions, frozen Materials and scope, a formal source_reference or required unavailable checks, ready inspection_requests, and a submit-result next_action with a strict input_template. Reusable completed evidence instead reports the parent Record state. No Session secret is printed.",
                nextSteps: [
                    "Send every returned child_context.fidelity_contract.inspection_requests item unchanged through scholium agent query --run <child_run> --from -",
                    "After inspecting the responses, fill child_context.next_actions[submit_result].input_template and run its command; Scholium links the lineage-bound child to the parent automatically",
                ]
            ),
            "agent reload": AgentCLICommandHelp(
                usage: "scholium agent reload --run <locator>",
                inputContract: "Authenticated Run locator; no JSON body",
                input: "Use the current Run locator. No earlier Research Context response is accepted as input or replayed.",
                output: "ResearchAuthenticatedRunContext with the current Run state and exact current boundaries. A changed target, Material, or formal source returns structured code stale_run instead of a usable context. The one-time Core Protocol is not replayed.",
                nextSteps: [
                    "Follow the returned current state and run the applicable agent command",
                    "On stale_run, stop this Run; do not retry a write or Result against the changed boundary",
                    "scholium agent end --run <locator> to stop an unfinished Run",
                ]
            ),
            "agent query": AgentCLICommandHelp(
                usage: "scholium agent query --run <locator> --from <json|->",
                inputContract: "ResearchContextRequest schema \(ResearchContextRequest.currentSchemaVersion)",
                input: "Strict JSON fields: schemaVersion, id, clauses (1...\(ResearchContextRequest.maximumClauses)). Every clause has schemaVersion, id, kind [\(contextClauses)], scope=triptych, limit 1...\(ResearchContextClause.maximumLimit), useEligibility, and only the fields allowed by its closed kind. Ordinary read_note uses query; a Fidelity inspection request supplied by Scholium instead uses exact note {vaultID, relativePath} plus expectedFingerprint. Send supplied inspection requests unchanged; do not reconstruct identity or fingerprints.",
                output: "ResearchContextResponse schema \(ResearchContextResponse.currentSchemaVersion) with one visible availability, items, limitations, and optional stateless continuation cursor for every requested clause.",
                nextSteps: [
                    "Repeat scholium agent query with a narrower request when needed",
                    "Use the returned context in the current Method, then continue to the applicable write or Result command",
                ]
            ),
            "agent discuss-reply": AgentCLICommandHelp(
                usage: "scholium agent discuss-reply --run <locator> --from <json|->",
                inputContract: "AgentDiscussionReplyDraft",
                input: "Strict JSON fields: statement_id (a stable UUID reused for an outcome-unknown retry), attribution, and text. The input appends one Agent-attributed turn to the active Discussion for this authenticated Discuss Run; it does not accept a local source path.",
                output: "ResearchAgentDiscussionReplyReceipt with recorded or already_recorded state. The portable Discussion remains the scholarly owner of the turn.",
                nextSteps: [
                    "Repeat the same statement_id and content after an uncertain result; an exact retry is idempotent",
                    "The researcher finishes the Discussion, or scholium agent end --run <locator> cancels the unfinished Run",
                ]
            ),
            "agent extend-write-set": AgentCLICommandHelp(
                usage: "scholium agent extend-write-set --run <locator> --from <json|->",
                inputContract: "ResearchWriteSetExtensionIntent schema \(ResearchWriteSetExtensionIntent.currentSchemaVersion)",
                input: "Strict JSON fields: schema_version, targets (1...\(ResearchBoundedWriteSet.maximumEntriesPerRequest)); each target has role [\(roles)], relative_path, and operations [\(writeOperations)]. Only modify_properties also requires nonempty property_keys with the exact requested top-level keys. academic_reason explains why the current Method needs these targets.",
                output: "AgentWriteSetReport with state, the current capability-free bounded-write-set entries, and a message.",
                nextSteps: [
                    "scholium agent reload --run <locator> after a pending researcher decision",
                    "scholium agent write --run <locator> --from <json|-> for one returned ready member",
                    "scholium agent write-zotero-binding --run <locator> --from <json|-> for one returned Analysis binding operation",
                ]
            ),
            "agent write": AgentCLICommandHelp(
                usage: "scholium agent write --run <locator> --from <json|->",
                inputContract: "AgentDocumentWriteDraft",
                input: "Strict JSON fields: role [\(roles)], relative_path, optional operation [\(documentWriteOperations)] defaulting to modify_markdown. modify_markdown requires content (an explicit empty string intentionally clears the body) and changes the body only. modify_source requires source containing the complete Markdown document, including any YAML. create_note may omit content and applies the current managed seed. modify_properties uses properties [{key, value}], where value is an ordinary JSON scalar, array, or object. Analysis create_note may add analysis_metadata {source_type, properties:[{key,value}]}. Source input is validated and committed as exact authored bytes; it is never reconstructed from Properties.",
                output: "AgentDocumentWriteReport with state, the current target view, and a message. Scholium supplies identity, expected revision, atomic write, and retry authority.",
                nextSteps: [
                    "scholium agent resolve-write-conflict --run <locator> --from <json|-> when the returned state is conflict",
                    "Continue with another ready member or scholium agent submit-result after a confirmed write",
                ]
            ),
            "agent write-zotero-binding": AgentCLICommandHelp(
                usage: "scholium agent write-zotero-binding --run <locator> --from <json|->",
                inputContract: "AgentZoteroBindingWriteDraft",
                input: "Strict JSON fields: role=analysis, relative_path, and operation set_zotero_binding or clear_zotero_binding. set_zotero_binding also requires library ({kind:user} or {kind:group,group_id:<positive integer>}) and item_key; clear_zotero_binding accepts neither. This command cannot write Markdown, Properties, or Zotero library data.",
                output: "AgentZoteroBindingWriteReport with state, current target view, message, and any bounded recovery warning. Scholium supplies stable Analysis identity, portable binding revision, and one-use write authority.",
                nextSteps: [
                    "scholium agent reload --run <locator> after conflict or uncertain recovery state",
                    "Continue with another ready member or submit the Result after a confirmed binding update",
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
                input: "Strict JSON fields: schema_version, record_title, disposition [completed, blocked], academic_results filled exactly from result_contract, context_use_claims with returned source_reference envelopes and testimony, fidelity_outcomes, and optional literature_recommendations only when the contract permits them. Every Fidelity outcome requires check [content, citations], state [passed, issues_found, unavailable], a nonempty attributed summary, and findings as an array of strings. passed requires empty findings; issues_found requires at least one finding; unavailable must be used for each fidelity_contract.required_unavailable_checks. For the default Check Fidelity profile, submit academic_results {values:{}} because Scholium derives the aggregate Finding fields from outcomes; a researcher-customized profile remains explicit in the returned template. The authenticated context next_actions supplies the complete strict template. record_title is the concise, one-line Record identity, not a duplicate academic result.",
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
            "workspace skill-sources": "Usage: scholium workspace skill-sources [--triptych <selector>] --format json\n\nReports the release-managed Core Protocol and exact enabled Triptych-managed Method folders that an authorized setup Agent may link into its host's project-level Skill directory. It creates no link, scans no arbitrary folder, and exposes no machine-local Method locator.",
            "workspace attention": "Usage: scholium workspace attention [--triptych <selector>] [--kind <queue>] --format json",
            "workspace bootstrap": "Usage: scholium workspace bootstrap --triptych <selector> --target <directory> [--conventions-file <file>] [--format markdown|json]",
            "action available": "Usage: scholium action available --from <target-json|-> --format json",
            "action prepare": "Usage: scholium action prepare --from <request-json|-> --format json|markdown",
            "action show": "Usage: scholium action show <run-id> [--triptych <selector>] --format json|markdown",
            "action cancel": "Usage: scholium action cancel <run-id> [--triptych <selector>] [--format json]",
            "read": "Usage: scholium read <vault>:<relative-path> [--format text|json]",
            "note create": "Usage: scholium note create <vault>:<path> [--body-from <text-file>] [--analysis-from <json-file>]\n\nCreates through the role's managed New Note YAML. Body input is UTF-8 LF text without a top-level YAML envelope, not complete Markdown source. Analysis JSON is {\"source_type\":\"journal_article\",\"properties\":[{\"key\":\"title\",\"value\":\"Example\"}]}; value is an ordinary JSON scalar, array, or object. Researcher creation does not enforce Agent-only required fields.",
            "note import": "Usage: scholium note import <vault>:<path> --from <markdown-file>\n\nImports complete authored Markdown source without applying managed New Note YAML.",
            "note replace": "Usage: scholium note replace <vault>:<path> --from <markdown-file> --expected <sha256>",
            "note move": "Usage: scholium note move <vault>:<path> <new-relative-path> --expected <sha256>",
            "note set-aside": "Usage: scholium note set-aside <vault>:<path> --expected <sha256>",
            "note trash": "Usage: scholium note trash <vault>:<path> --expected <sha256>",
            "note delete": "Usage: scholium note delete <vault>:<Trash/path> --permanent --expected <sha256>",
            "discuss list": "Usage: scholium discuss list [--triptych <selector>] [--format text|json]",
            "discuss show": "Usage: scholium discuss show <discussion-id> [--triptych <selector>] [--format text|json]",
            "discuss reply": "Usage: scholium discuss reply <discussion-id> --agent <name> (--text <reply> | --from <file|->) [--triptych <selector>]\n\nThis is a researcher-operated manual attribution route. External Agents must use the authenticated scholium agent discuss-reply command.",
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
