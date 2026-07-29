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
          scholium skills catalog [--triptych <uuid-or-unique-name>] [--format text|json]
          scholium skills show <skill-id> [--triptych <uuid-or-unique-name>]
              [--resource <relative-path>] [--format text|json]
          scholium skills resources <skill-id> [--triptych <uuid-or-unique-name>]
              [--format text|json]
          scholium workflow validate --from <file|-> [--triptych <selector>] --format json
          scholium workflow assemble --from <file|-> [--triptych <selector>]
              --format markdown|json
          scholium workflow audit-plan --from <file|-> --format json
          scholium action available --from <json|-> --format json
          scholium action prepare --from <json|-> --format json|markdown
          scholium action show <run-id> [--triptych <selector>] --format json|markdown
          scholium action prepare-fidelity <parent-run-id> [--triptych <selector>] --format json|markdown
          scholium action complete --from <json|-> [--triptych <selector>] --format json
          scholium action cancel <run-id> [--triptych <selector>]
          scholium bibliography prepare --from <json|-> --format json|markdown
          scholium bibliography show <request-id> [--triptych <selector>] --format json|markdown
          scholium bibliography complete --from <json|-> [--triptych <selector>] --format json
          scholium bibliography cancel <request-id> [--triptych <selector>]
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
          scholium agent mcp serve
        Omitting --triptych requires exactly one configured Triptych.
        Triptych roles: analyses, topics, works
        Workflow contracts add exact task boundaries, phase isolation, Practice
        resources, fingerprints, and audit planning. The CLI never scans
        global Skill folders or grants edit permission.
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
    static var commandHelp: [String: String] {
        [
            "vault list": "Usage: scholium vault list [--format text|json]\n\nLists registered Triptychs and their three role vaults.",
            "search": "Usage: scholium search <query> (--vault <selector> [--triptych <selector>] | --triptych <selector>) [--limit <count>] [--format text|jsonl]",
            "links incoming": "Usage: scholium links incoming <vault>:<path> --format json",
            "links outgoing": "Usage: scholium links outgoing <vault>:<path> --format json",
            "links relationships": "Usage: scholium links relationships <vault>:<path> --format json",
            "links diagnostics": "Usage: scholium links diagnostics --workspace [--triptych <selector>] --format json",
            "graph trace": "Usage: scholium graph trace <source> <target> [--max-depth <1...10>] --format json",
            "graph relation-trace": "Usage: scholium graph relation-trace <source> <target> [--max-depth <1...10>] --format json",
            "workspace catalog": "Usage: scholium workspace catalog [--triptych <selector>] --format json",
            "workspace attention": "Usage: scholium workspace attention [--triptych <selector>] [--kind <queue>] --format json",
            "workspace bootstrap": "Usage: scholium workspace bootstrap --triptych <selector> --target <directory> [--conventions-file <file>] [--format markdown|json]",
            "skills catalog": "Usage: scholium skills catalog [--triptych <selector>] [--format text|json]",
            "skills show": "Usage: scholium skills show <skill-id> [--triptych <selector>] [--resource <relative-path>] [--format text|json]",
            "skills resources": "Usage: scholium skills resources <skill-id> [--triptych <selector>] [--format text|json]",
            "workflow validate": "Usage: scholium workflow validate --from <json|-> [--triptych <selector>] --format json",
            "workflow assemble": "Usage: scholium workflow assemble --from <json|-> [--triptych <selector>] --format markdown|json",
            "workflow audit-plan": "Usage: scholium workflow audit-plan --from <json|-> --format json",
            "action available": "Usage: scholium action available --from <target-json|-> --format json",
            "action prepare": "Usage: scholium action prepare --from <request-json|-> --format json|markdown",
            "action show": "Usage: scholium action show <run-id> [--triptych <selector>] --format json|markdown",
            "action prepare-fidelity": "Usage: scholium action prepare-fidelity <parent-run-id> [--triptych <selector>] --format json|markdown\n\nPrepares or reuses the required final-revision Fidelity child for a completed Analyze, Synthesize, or Write Action.",
            "action complete": "Usage: scholium action complete --from <completion-json|-> [--triptych <selector>] --format json",
            "action cancel": "Usage: scholium action cancel <run-id> [--triptych <selector>] [--format json]",
            "bibliography prepare": "Usage: scholium bibliography prepare --from <request-json|-> --format json|markdown",
            "bibliography show": "Usage: scholium bibliography show <request-id> [--triptych <selector>] --format json|markdown",
            "bibliography complete": "Usage: scholium bibliography complete --from <completion-json|-> [--triptych <selector>] --format json",
            "bibliography cancel": "Usage: scholium bibliography cancel <request-id> [--triptych <selector>] [--format json]",
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
            "agent mcp serve": "Usage: scholium agent mcp serve",
        ]
    }
}

struct WorkflowValidationReport: Encodable {
    let schemaVersion = 1
    let structurallyValid = true
    let executable: Bool
    let contract: ResearchWorkflowContract
    let phases: [WorkflowValidationPhaseReport]
    let warnings: [String]
    let blockingConflicts: [String]

    init(envelope: ResolvedResearchWorkflowEnvelope) {
        executable = envelope.isExecutable
        contract = envelope.contract
        phases = envelope.phases.map(WorkflowValidationPhaseReport.init)
        warnings = envelope.warnings
        blockingConflicts = envelope.blockingConflicts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case structurallyValid = "structurally_valid"
        case executable
        case contract
        case phases
        case warnings
        case blockingConflicts = "blocking_conflicts"
    }
}

struct WorkflowValidationPhaseReport: Encodable {
    let phase: Int
    let mode: ResearchSkillMode
    let packages: [WorkflowValidationPackageReport]
    let warnings: [String]
    let blockingConflicts: [String]

    init(_ resolved: ResolvedResearchWorkflowPhase) {
        phase = resolved.contract.phase
        mode = resolved.contract.mode
        packages = resolved.packages.map(WorkflowValidationPackageReport.init)
        warnings = resolved.warnings
        blockingConflicts = resolved.blockingConflicts
    }

    private enum CodingKeys: String, CodingKey {
        case phase
        case mode
        case packages
        case warnings
        case blockingConflicts = "blocking_conflicts"
    }
}

struct WorkflowValidationPackageReport: Encodable {
    let id: String
    let origin: ResearchSkillOrigin
    let version: String
    let packageRevision: DocumentFingerprint
    let loadedResources: [WorkflowValidationResourceReport]

    init(_ package: ResolvedResearchSkillSelection) {
        id = package.id
        origin = package.origin
        version = package.version
        packageRevision = package.packageRevision
        loadedResources = package.loadedResources.map(WorkflowValidationResourceReport.init)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case origin
        case version
        case packageRevision = "package_revision"
        case loadedResources = "loaded_resources"
    }
}

struct WorkflowValidationResourceReport: Encodable {
    let relativePath: String
    let revision: DocumentFingerprint

    init(_ resource: ResolvedResearchSkillResource) {
        relativePath = resource.relativePath
        revision = resource.revision
    }

    private enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case revision
    }
}

enum CLIError: LocalizedError {
    case usage(String)
    case invalidUTF8(String)
    case noteNotFound(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        case .invalidUTF8(let path): return "File is not valid UTF-8: \(path)"
        case .noteNotFound(let target): return "The workspace note was not found: \(target)"
        case .unavailable(let message): return message
        }
    }
}
