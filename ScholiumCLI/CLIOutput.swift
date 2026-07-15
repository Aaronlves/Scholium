import ScholiumContracts
import Foundation

extension ScholiumCLI {
    static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func allOptions(_ name: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == name, arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
    }

    static func printHelp() {
        write("""
        Scholium CLI — agent-facing, local-first research access

        Usage:
          scholium vault list
          scholium search <query> --vault <selector> [--format text|jsonl]
          scholium search <query> --workspace [--triptych <uuid-or-unique-name>] [filters]
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
          scholium skills assemble --mode <mode> [--skill <id> ...]
              [--triptych <uuid-or-unique-name>]
          scholium skills assemble --mode mixed
              --phase <mode>[:skill-id,skill-id] ...
          scholium workflow validate --from <file|-> [--triptych <selector>] --format json
          scholium workflow assemble --from <file|-> [--triptych <selector>]
              --format markdown|json
          scholium workflow audit-plan --from <file|-> --format json
          scholium read <vault>:<relative-path> [--format json]
          scholium note create <vault>:<path> --from <markdown-file>
          scholium note replace <vault>:<path> --from <markdown-file> --expected <sha256>
          scholium note move <vault>:<path> <new-path> --expected <sha256>
          scholium note set-aside <vault>:<path> --expected <sha256>
          scholium note trash <vault>:<path> --expected <sha256>
          scholium note delete <vault>:<Trash/path> --permanent --expected <sha256>
          scholium dialogue list [--triptych <uuid-or-unique-name>]
              [--note <vault>:<relative-path>] [--format json]
          scholium dialogue show <dialogue-id> [--triptych <uuid-or-unique-name>] [--format json]
          scholium dialogue reply <dialogue-id> --triptych <uuid-or-unique-name> --agent <name>
              (--text <reply> | --from <file>) [--note <vault>:<path>] [--comment <uuid>]
          scholium zotero mcp config [--format text|json]
          scholium zotero mcp status [--probe] [--format text|json]
          scholium zotero mcp serve
        Omitting --triptych uses the compatibility default Triptych.
        Triptych roles: analyses, topics, works
        `skills assemble` is a compact package-assembly compatibility interface.
        Workflow contracts add exact task boundaries, phase isolation, Practice
        resources, fingerprints, and audit planning. Neither interface scans
        global Skill folders or grants edit permission.
        Workspace bootstrap is candidate-only: it never writes or overwrites AGENTS.md.
        Zotero MCP status locates Scholium's first-party CLI transport by default.
        Add --probe to perform only the MCP initialize lifecycle check; it does
        not read Zotero data or perform an import.
        Legacy registry spellings and aliases remain accepted for compatibility:
        source_corpus, topic_knowledge, dissertation_control, draft_project,
        other, unclassified, sources, knowledge, dissertation, and project.

        Existing-note mutations require the exact SHA-256 reported by
        `scholium read --format json`. Fingerprints prevent stale overwrites;
        they are revision checks, not permission tokens. The researcher remains
        responsible for deciding when an agent may edit Triptych files.
        """ + "\n")
    }

    static func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    static func writeError(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
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
