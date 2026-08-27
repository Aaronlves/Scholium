import ScholiumContracts
import Foundation

extension ScholiumCLI {
    static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func printHelp() throws {
        try printHelp(path: [], format: .text)
    }

    static func printHelp(path: [String], format: CLIOutputFormat) throws {
        let key = path.joined(separator: " ")
        let specification = commandSpecifications[key]
        let text = try helpText(for: path)
        switch format {
        case .text, .markdown:
            write(text + (text.hasSuffix("\n") ? "" : "\n"))
        case .json:
            let report = CLIHelpReport(
                path: path,
                help: text,
                agentCommand: specification?.agentCommand
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

    static func helpText(for path: [String]) throws -> String {
        let key = path.joined(separator: " ")
        if let specification = commandSpecifications[key] {
            return specification.help
        }
        if !path.isEmpty {
            let candidates = commandSpecifications.keys
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
            throw CLIError.usage("Unknown help topic '\(key)'. Run 'scholium help'.")
        }
        return """
        Scholium CLI — agent-facing, local-first research access

        Commands:
        \(rootCommandUsage)
        Omitting --triptych requires exactly one configured Triptych.
        Triptych roles: analyses, topics, works
        Authenticated Agent commands preserve Run, Method, selected references, Research
        Context, Bounded Write Set, Result, and continuation boundaries. The
        CLI never scans arbitrary Skill folders or grants edit permission.
        Workspace Skill sources reports every exact System and current Method
        source for host-native project discovery; it creates no link itself.
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

struct AgentCLICommandHelp: Encodable {
    let rule: ScholiumCLI.CLICommandRule
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

extension ScholiumCLI {
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
            "agent preflight-analysis": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--triptych": .value, "--from": .value]
                ),
                usage: "scholium agent preflight-analysis --triptych <selector> --from <json|->",
                inputContract: "ResearchAgentAnalysisCreationPreflightRequest schema \(ResearchAgentAnalysisCreationPreflightRequest.currentSchemaVersion)",
                input: "Strict JSON fields: schema_version, request_id, destination {schema_version, managed_default_filename}, metadata {source_type, optional fields}, optional authored_yaml {summary, keywords}, and exactly one of source {library, item_key} or source_route=researcher_provided. Every managed field is optional. Omitted authored values remain summary:null and keywords:[]. Direct Agent creation always resolves one Markdown filename at the Analyses-vault root.",
                output: "The current Analyses vault identity, source-type applicable fields, Settings-preferred optional fields, fixed YAML fields, exact destination and stable/source/Trash state, one status, retry contract, and—only when ready—the exact start_new_analysis payload.",
                nextSteps: [
                    "Use start_new_analysis unchanged inside agent start only when status is ready",
                    "For every other status, follow recovery.next_step; never add (retry), silently recreate a missing identity, or substitute placeholders",
                    "For missing/trashed source, each researcher-controlled creation_branches item separately states must_reuse_request_identity and next_step",
                ]
            ),
            "agent start": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--triptych": .value, "--from": .value]
                ),
                usage: "scholium agent start --triptych <selector> --from <json|->",
                inputContract: "ResearchAgentStartRequest schema \(ResearchAgentStartRequest.currentSchemaVersion)",
                input: "Strict JSON fields: schema_version, action_id, exactly one of existing target {vault_id, relative_path} or the unchanged new_analysis payload returned by agent preflight-analysis, optional source_route=researcher_provided only for an existing Analysis, and academic_inputs containing every required current Profile field. Each academic input is a typed freeText, singleChoice, or multipleChoice value. Optional Settings preferences grant no authority and cannot invalidate creation; replay requires the exact complete start payload.",
                output: "AgentStartReport with the ResearchAgentStartReceipt and initial ResearchAuthenticatedRunContext. The context identifies the minimum required project-discovered Skills and contains no Skill prose or source path. The Session credential is stored in protected local state and is not printed.",
                nextSteps: [
                    "Before the first Scholium Run in this workspace, run scholium workspace skill-sources --triptych <selector> --format json and register every returned source as a project Skill",
                    "Run agent preflight-analysis first for every new Analysis",
                    "Apply every returned required_skills entry, then continue with the current evidence actions, Bounded Write Set, and Result Contract; other non-Scholium Skills remain available within the Run boundary",
                    "If initial context delivery fails after Session creation, run scholium agent reload --run <locator>; do not repeat start",
                ]
            ),
            "agent pair": AgentCLICommandHelp(
                rule: .init(pathLength: 2, options: ["--run": .value]),
                usage: "scholium agent pair --run <locator>",
                inputContract: "ResearchPairingCode on standard input",
                input: "When prompted, enter the one-time Pairing Code from the current handoff. Do not put it in an argument, URL, file, or log.",
                output: "AgentPairingReport with paired=true, the Run locator, context_kind, and the Run owner's initial ResearchAuthenticatedRunContext or ResearchMethodImprovementContext. Action context identifies the minimum required project-discovered Skills and contains no Skill prose or source path. The exchanged Session credential is stored in protected local state and is not printed.",
                nextSteps: [
                    "Follow the handoff's conditional first-workspace Skill registration instruction before pairing",
                    "Apply every returned required_skills entry, then continue with the current evidence actions, Bounded Write Set, and Result Contract; other non-Scholium Skills remain available within the Run boundary",
                    "If initial context delivery fails after pairing succeeds, run scholium agent reload --run <locator>; do not pair again",
                ]
            ),
            "agent reload": AgentCLICommandHelp(
                rule: .init(pathLength: 2, options: ["--run": .value]),
                usage: "scholium agent reload --run <locator>",
                inputContract: "Authenticated Run locator; no JSON body",
                input: "Use the current Run locator. No earlier Research Context response is accepted as input or replayed.",
                output: "The current ResearchAuthenticatedRunContext, or ResearchMethodImprovementContext for an improvement Run. Action context includes the same minimum required_skills plus typed required/when-needed evidence actions including Search, exact current boundaries, and only required Result fields in its fillable template. A changed target, Material, formal source, feedback, or Method returns a structured error instead of a usable context.",
                nextSteps: [
                    "Follow the returned current state and run the applicable agent command",
                    "On stale_run, stop this Run; do not retry a write or Result against the changed boundary",
                    "scholium agent end --run <locator> to stop an unfinished Run",
                ]
            ),
            "agent query": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
                usage: "scholium agent query --run <locator> --from <json|->",
                inputContract: "ResearchContextRequest schema \(ResearchContextRequest.currentSchemaVersion)",
                input: "Strict snake-case JSON fields: schema_version, id, clauses (1...\(ResearchContextRequest.maximumClauses)). Every clause has schema_version, id, kind [\(contextClauses)], scope=triptych, limit 1...\(ResearchContextClause.maximumLimit), use_eligibility, and only the fields allowed by its closed kind. Ordinary read_note uses query; a Fidelity inspection request supplied by Scholium instead uses exact note {vault_id, relative_path} plus expected_fingerprint. Send supplied inspection requests unchanged; do not reconstruct identity or fingerprints.",
                output: "ResearchContextResponse schema \(ResearchContextResponse.currentSchemaVersion) with one visible availability, items, limitations, and optional stateless continuation cursor for every requested clause.",
                nextSteps: [
                    "Repeat scholium agent query with a narrower request when needed",
                    "Use the returned context in the current Method, then continue to the applicable write or Result command",
                ]
            ),
            "agent discuss-reply": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
                usage: "scholium agent discuss-reply --run <locator> --from <json|->",
                inputContract: "AgentDiscussionReplyDraft",
                input: "Strict JSON fields: statement_id (a stable UUID reused for an outcome-unknown retry), attribution, and text. The input appends one Agent-attributed turn to the active Discussion for this authenticated Discuss Run; it does not accept a local source path.",
                output: "ResearchAgentDiscussionReplyReceipt with recorded or already_recorded state. The portable Discussion remains the scholarly owner of the turn.",
                nextSteps: [
                    "Repeat the same statement_id and content after an uncertain result; an exact retry is idempotent",
                    "Continue the exchange with another attributed turn, or finish it with scholium agent finish-discussion --run <locator>",
                    "Use scholium agent end --run <locator> only to cancel the unfinished Run",
                ]
            ),
            "agent finish-discussion": AgentCLICommandHelp(
                rule: .init(pathLength: 2, options: ["--run": .value]),
                usage: "scholium agent finish-discussion --run <locator>",
                inputContract: "Authenticated Discuss Run locator; no JSON body",
                input: "Use the current Discuss Run after at least one durable Agent turn. Finishing forms the canonical portable Discussion Record and revokes this Run's Session; it does not edit a Note, submit a generic Result, or imply researcher acceptance.",
                output: "ResearchAgentDiscussionFinishReceipt with finished=true and record_formed=true. The acknowledged local Session credential is then removed.",
                nextSteps: [
                    "Stop using this Run locator after success",
                    "If outcome_unknown is returned, do not retry with the revoked credential; stop and report so the researcher can inspect the Discussion and Record",
                ]
            ),
            "agent extend-write-set": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
                usage: "scholium agent extend-write-set --run <locator> --from <json|->",
                inputContract: "ResearchWriteSetExtensionIntent schema \(ResearchWriteSetExtensionIntent.currentSchemaVersion)",
                input: "Strict JSON fields: schema_version, targets (1...\(ResearchBoundedWriteSet.maximumEntriesPerRequest)); each target has role [\(roles)], relative_path, and operations [\(writeOperations)]. Only modify_metadata also requires nonempty metadata_keys with the exact requested managed keys. academic_reason explains why the current Method needs these targets.",
                output: "AgentWriteSetReport with state, the current capability-free bounded-write-set entries, and a message.",
                nextSteps: [
                    "scholium agent reload --run <locator> after a pending researcher decision",
                    "scholium agent write --run <locator> --from <json|-> for one returned ready member",
                    "scholium agent write-zotero-binding --run <locator> --from <json|-> for one returned Analysis binding operation",
                ]
            ),
            "agent write": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
                usage: "scholium agent write --run <locator> --from <json|->",
                inputContract: "AgentDocumentWriteDraft",
                input: "Strict JSON fields: role [\(roles)], relative_path, optional operation [\(documentWriteOperations)] defaulting to modify_markdown. modify_markdown requires content and changes the body only. modify_source requires the complete authored Markdown source. create_note may omit content, may add authored_yaml {summary, keywords}, and always creates the fixed summary/keywords scaffold. modify_metadata uses metadata [{key, value}]. Analysis create_note may add analysis_metadata {source_type, optional fields:[{key,value}]}. Authored source and portable Metadata remain separate transactions.",
                output: "AgentDocumentWriteReport with state, the current target view, and a message. Scholium supplies identity, expected revision, atomic write, and retry authority.",
                nextSteps: [
                    "scholium agent resolve-write-conflict --run <locator> --from <json|-> when the returned state is conflict",
                    "Continue with another ready member or scholium agent submit-result after a confirmed write",
                ]
            ),
            "agent write-zotero-binding": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
                usage: "scholium agent write-zotero-binding --run <locator> --from <json|->",
                inputContract: "AgentZoteroBindingWriteDraft",
                input: "Strict JSON fields: role=analysis, relative_path, and operation set_zotero_binding or clear_zotero_binding. set_zotero_binding also requires library ({kind:user} or {kind:group,group_id:<positive integer>}) and item_key; clear_zotero_binding accepts neither. This command cannot write Markdown, Scholium Metadata, or Zotero library data.",
                output: "AgentZoteroBindingWriteReport with state, current target view, message, and any bounded recovery warning. Scholium supplies stable Analysis identity, portable binding revision, and one-use write authority.",
                nextSteps: [
                    "scholium agent reload --run <locator> after conflict or uncertain recovery state",
                    "Continue with another ready member or submit the Result after a confirmed binding update",
                ]
            ),
            "agent resolve-write-conflict": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
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
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
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
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
                usage: "scholium agent continue --run <locator> --from <json|->",
                inputContract: "ResearchContinuationRequest schema \(ResearchContinuationRequest.currentSchemaVersion)",
                input: "Strict JSON fields: schema_version, next_action_id, target_role [\(roles)], target_relative_path, academic_purpose, handoff items, and fidelity_checks [content, citations]. Each handoff item has content, epistemic_status [\(epistemicStatuses)], next_use, and source_references.",
                output: "ResearchContinuationResult with pending_researcher_decision, created, declined, stale, or expired state; a created result also returns the fresh next Run, handoff context, and complete authenticated Run context with its minimum required_skills.",
                nextSteps: [
                    "When state is created, apply the returned context.required_skills and continue through that context's next_actions; the existing Session already owns the attached child Run",
                    "Otherwise follow the returned state and message; no authority carries forward",
                ]
            ),
            "agent method-context": AgentCLICommandHelp(
                rule: .init(pathLength: 2, options: ["--run": .value]),
                usage: "scholium agent method-context --run <locator>",
                inputContract: "Authenticated Method-improvement Run locator; no JSON body",
                input: "Use the locator from an explicit Improve Current Method handoff. The CLI loads the hidden Session credential.",
                output: "ResearchMethodImprovementContext with the unchanged researcher feedback, finalized Result fingerprint, and exact Skill entry target.",
                nextSteps: [
                    "scholium agent improve-method --run <locator> --from <json|-> for at most one returned target_id",
                    "scholium agent end --run <locator> if the improvement Run cannot continue",
                ]
            ),
            "agent improve-method": AgentCLICommandHelp(
                rule: .init(
                    pathLength: 2,
                    options: ["--run": .value, "--from": .value]
                ),
                usage: "scholium agent improve-method --run <locator> --from <json|->",
                inputContract: "ResearchMethodImprovementDraft",
                input: "Strict JSON fields: target_id from method-context, disposition [replace, diagnosed_no_change, unavailable], optional replacement_source only for replace, and diagnosis.",
                output: "ResearchMethodImprovementReceipt with the target, starting and ending revisions, disposition, diagnosis, and whether unchanged feedback was cleared.",
                nextSteps: [
                    "scholium agent end --run <locator>",
                ]
            ),
            "agent end": AgentCLICommandHelp(
                rule: .init(pathLength: 2, options: ["--run": .value]),
                usage: "scholium agent end --run <locator>",
                inputContract: "Authenticated Run locator; no JSON body",
                input: "Use the current unfinished Run locator. No Result or cancellation payload is accepted.",
                output: "ResearchRunEndReceipt with retained-recovery truth and a message; the acknowledged local Session credential is then removed.",
                nextSteps: [
                    "Stop using this Run locator; new Agent access requires a new researcher-provided handoff",
                    "If outcome_unknown is returned, do not retry End with the revoked credential; stop and report so the researcher can inspect Scholium's Run and recovery state",
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

}


enum CLIError: LocalizedError {
    case usage(String)
    case invalidUTF8(String)
    case noteNotFound(String)
    case recordNotFound(UUID)
    case unavailable(String)
    case searchDiagnostic(SearchQueryDiagnostic)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        case .invalidUTF8(let path): return "File is not valid UTF-8: \(path)"
        case .noteNotFound(let target): return "The workspace note was not found: \(target)"
        case .recordNotFound(let id):
            return "The finished Research Record was not found: \(id.uuidString.lowercased())"
        case .unavailable(let message): return message
        case .searchDiagnostic(let diagnostic): return diagnostic.message
        }
    }
}
