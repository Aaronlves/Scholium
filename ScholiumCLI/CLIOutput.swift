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
            let report = CLIHelpReport(path: path, help: text)
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
        if let help = commandHelp[key] { return help }
        if !path.isEmpty {
            let candidates = commandHelp.keys.filter { $0.hasPrefix(key + " ") }.sorted()
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
          scholium agent pair --run <locator> < pairing-code.txt
          scholium agent context --run <locator>
          scholium agent reload --run <locator>
          scholium agent query --run <locator> --from <json|->
          scholium agent extend-write-set --run <locator> --from <json|->
          scholium agent write --run <locator> --from <json|->
          scholium agent resolve-write-conflict --run <locator> --from <json|->
          scholium agent submit-result --run <locator> --from <json|->
          scholium agent continue --run <locator> --from <json|->
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
    let schemaVersion = 1
    let path: [String]
    let help: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case path, help
    }
}

private extension ScholiumCLI {
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
            "agent pair": "Usage: scholium agent pair --run <locator>\n\nReads the one-time Pairing Code from standard input. The hidden Session credential is stored in protected local state and is never printed.",
            "agent context": "Usage: scholium agent context --run <locator>\n\nReturns the authenticated Run Brief, frozen Method and Practices, and Result Contract.",
            "agent reload": "Usage: scholium agent reload --run <locator>\n\nReloads current Run state without replaying earlier Research Context responses or the one-time Core Protocol.",
            "agent query": "Usage: scholium agent query --run <locator> --from <json|->\n\nRuns one authenticated, provider-neutral Research Context query. Scholium supplies the Run, Triptych, scope, and current generation before retrieval.",
            "agent extend-write-set": "Usage: scholium agent extend-write-set --run <locator> --from <json|->\n\nRequests one or more role-and-path targets for this Run's bounded write set. Scholium resolves stable identity, revision, permission, and recovery state.",
            "agent write": "Usage: scholium agent write --run <locator> --from <json|->\n\nWrites one authorized role-and-path member. The input contains role, relative_path, optional operation, and exact Markdown content; Scholium carries hidden identity and revision state.",
            "agent resolve-write-conflict": "Usage: scholium agent resolve-write-conflict --run <locator> --from <json|->\n\nResolves one known conflict with action refresh_authority or abandon_write. Refresh creates a new Before Agent Work checkpoint for the exact current document; query and reread that Markdown, then retry with agent write. Abandon records that this attempt will not be retried and narrows only that member.",
            "agent submit-result": "Usage: scholium agent submit-result --run <locator> --from <json|->\n\nSubmits only the frozen academic Result fields, explicit source-use testimony, and Action-specific scholarly outputs. Scholium supplies and verifies machine facts before forming one Research Record.",
            "agent continue": "Usage: scholium agent continue --run <locator> --from <json|->\n\nCreates a separately resolved next Action from one finalized Result. Only the explicit academic purpose and handoff are carried forward; Method, Profile, permissions, references, and Research Context are resolved again.",
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
