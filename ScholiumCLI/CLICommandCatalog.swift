import Foundation

extension ScholiumCLI {
    struct CLIOptionRule: Sendable {
        let takesValue: Bool
        let repeatable: Bool

        static let value = Self(takesValue: true, repeatable: false)
        static let repeatableValue = Self(takesValue: true, repeatable: true)
        static let flag = Self(takesValue: false, repeatable: false)
    }

    struct CLICommandRule: Sendable {
        let pathLength: Int
        let positionalCount: ClosedRange<Int>
        let options: [String: CLIOptionRule]

        init(
            pathLength: Int,
            positionalCount: ClosedRange<Int> = 0 ... 0,
            options: [String: CLIOptionRule] = [:]
        ) {
            self.pathLength = pathLength
            self.positionalCount = positionalCount
            self.options = options
        }
    }

    struct CLICommandSpecification {
        let rule: CLICommandRule
        let help: String

        init(
            rule: CLICommandRule,
            help: String
        ) {
            self.rule = rule
            self.help = help
        }

        var usage: String {
            let firstLine = help.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? help
            return firstLine.hasPrefix("Usage: ")
                ? String(firstLine.dropFirst("Usage: ".count))
                : firstLine
        }
    }

    /// The sole syntax-and-help registry for executable command paths. Handler
    /// dispatch remains explicit in CLIEntry; it does not restate option or
    /// positional grammar.
    static let commandSpecifications = ordinaryCommandSpecifications

    static let rootCommandUsage: String = {
        let meta = [
            "scholium help [command [subcommand]] [--format text|json]",
            "scholium version [--format text|json]",
        ]
        let registered = commandSpecifications.keys.sorted().compactMap {
            commandSpecifications[$0]?.usage
        }
        return (meta + registered).map { "  " + $0 }.joined(separator: "\n")
    }()

    static func commandSpecificationKey(
        matching arguments: [String]
    ) -> String? {
        commandSpecifications.keys
            .filter { key in
                let components = key.split(separator: " ").map(String.init)
                return components.count <= arguments.count
                    && Array(arguments.prefix(components.count)) == components
            }
            .max { left, right in
                left.split(separator: " ").count
                    < right.split(separator: " ").count
            }
    }

    static func commandUsageError(_ key: String) -> CLIError {
        guard let specification = commandSpecifications[key] else {
            return .usage("Run 'scholium help \(key)' to inspect supported commands.")
        }
        return .usage("Usage: \(specification.usage)")
    }

    private static let ordinaryCommandSpecifications: [String: CLICommandSpecification] = {
        let format: [String: CLIOptionRule] = ["--format": .value]
        let selected: [String: CLIOptionRule] = [
            "--triptych": .value,
            "--format": .value,
        ]
        return [
            "mcp serve": .init(
                rule: .init(pathLength: 2),
                help: "Usage: scholium mcp serve\n\nRuns the local stdio MCP adapter for the currently running Scholium App. The adapter does not open a Triptych or read its filesystem directly."
            ),
            "doctor": .init(
                rule: .init(pathLength: 1, options: format),
                help: "Usage: scholium doctor [--format text|json]"
            ),
            "update": .init(
                rule: .init(pathLength: 1, options: ["--check": .flag, "--format": .value]),
                help: "Usage: scholium update [--check] [--format text|json]\n\nChecks the official release checksum, provenance, code signature, and architecture. Without --check, an explicit newer release is installed into ~/.local/bin without changing PATH or shell configuration."
            ),
            "vault list": .init(
                rule: .init(pathLength: 2, options: format),
                help: "Usage: scholium vault list [--format text|json]\n\nLists registered Triptychs and their three role vaults."
            ),
            "search": .init(
                rule: .init(
                    pathLength: 1,
                    positionalCount: 1 ... 1,
                    options: [
                        "--vault": .value, "--triptych": .value,
                        "--limit": .value, "--format": .value,
                    ]
                ),
                help: searchHelp
            ),
            "links incoming": .init(
                rule: .init(pathLength: 2, positionalCount: 1 ... 1, options: format),
                help: "Usage: scholium links incoming <vault>:<path> --format json"
            ),
            "links outgoing": .init(
                rule: .init(pathLength: 2, positionalCount: 1 ... 1, options: format),
                help: "Usage: scholium links outgoing <vault>:<path> --format json"
            ),
            "links diagnostics": .init(
                rule: .init(
                    pathLength: 2,
                    options: ["--workspace": .flag, "--triptych": .value, "--format": .value]
                ),
                help: "Usage: scholium links diagnostics --workspace [--triptych <selector>] --format json"
            ),
            "workspace catalog": .init(
                rule: .init(pathLength: 2, options: selected),
                help: "Usage: scholium workspace catalog [--triptych <selector>] --format json"
            ),
            "workspace attention": .init(
                rule: .init(
                    pathLength: 2,
                    options: ["--triptych": .value, "--kind": .value, "--format": .value]
                ),
                help: "Usage: scholium workspace attention [--triptych <selector>] [--kind <queue>] --format json"
            ),
            "read": .init(
                rule: .init(pathLength: 1, positionalCount: 1 ... 1, options: format),
                help: "Usage: scholium read <vault>:<relative-path> [--format text|json]"
            ),
            "note create": .init(
                rule: .init(
                    pathLength: 2,
                    positionalCount: 1 ... 1,
                    options: [
                        "--body-from": .value, "--authored-yaml-from": .value,
                        "--analysis-from": .value,
                    ]
                ),
                help: "Usage: scholium note create <vault>:<path> [--body-from <text-file>] [--authored-yaml-from <json-file>] [--analysis-from <json-file>]\n\nAlways creates fixed YAML with summary and keywords. Authored YAML JSON may supply {\"summary\":\"...\",\"keywords\":[\"...\"]}; omission keeps summary:null and keywords:[]. Body input is UTF-8 LF text without a top-level YAML envelope. Analysis JSON is {\"source_type\":\"journal_article\",\"fields\":[{\"key\":\"title\",\"value\":\"Example\"}]}; every managed field is optional."
            ),
            "note metadata-read": .init(
                rule: .init(pathLength: 2, positionalCount: 1 ... 1, options: format),
                help: "Usage: scholium note metadata-read <vault>:<path> [--format json]\n\nReads only the Note's validated portable Scholium Metadata record and its independent metadata_sha256 revision. Markdown source remains separate."
            ),
            "note metadata-set": .init(
                rule: .init(
                    pathLength: 2,
                    positionalCount: 2 ... 2,
                    options: ["--value-from": .value, "--expected": .value]
                ),
                help: "Usage: scholium note metadata-set <vault>:<path> <key> --value-from <json-file> --expected <metadata-sha256|absent>\n\nSets one role-valid managed field through the same complete-record CAS used by the app. The value file contains one JSON scalar, array, or object matching the field contract. Use absent only when metadata-read reports no record."
            ),
            "note metadata-remove": .init(
                rule: .init(
                    pathLength: 2,
                    positionalCount: 2 ... 2,
                    options: ["--expected": .value]
                ),
                help: "Usage: scholium note metadata-remove <vault>:<path> <key> --expected <metadata-sha256>\n\nRemoves one present managed field through the same complete-record CAS used by the app. It never changes YAML or Markdown."
            ),
            "note import": .init(
                rule: .init(pathLength: 2, positionalCount: 1 ... 1, options: ["--from": .value]),
                help: "Usage: scholium note import <vault>:<path> --from <markdown-file>\n\nImports complete authored Markdown source without applying managed New Note YAML."
            ),
            "note replace": .init(
                rule: .init(
                    pathLength: 2,
                    positionalCount: 1 ... 1,
                    options: ["--from": .value, "--expected": .value]
                ),
                help: "Usage: scholium note replace <vault>:<path> --from <markdown-file> --expected <sha256>"
            ),
            "note move": .init(
                rule: .init(
                    pathLength: 2,
                    positionalCount: 2 ... 2,
                    options: ["--expected": .value]
                ),
                help: "Usage: scholium note move <vault>:<path> <new-relative-path> --expected <sha256>"
            ),
            "note move-to-trash": .init(
                rule: .init(
                    pathLength: 2,
                    positionalCount: 1 ... 1,
                    options: ["--expected": .value]
                ),
                help: "Usage: scholium note move-to-trash <vault>:<path> --expected <sha256>\n\nMoves the exact Note to the macOS system Trash. Finder owns file restoration."
            ),
            "zotero mcp": .init(
                rule: .init(pathLength: 2, options: ["--probe": .flag, "--format": .value]),
                help: "Usage: scholium zotero mcp [status] [--probe] [--format text|json]"
            ),
            "zotero mcp config": .init(
                rule: .init(pathLength: 3, options: format),
                help: "Usage: scholium zotero mcp config [--format text|json]"
            ),
            "zotero mcp status": .init(
                rule: .init(pathLength: 3, options: ["--probe": .flag, "--format": .value]),
                help: "Usage: scholium zotero mcp status [--probe] [--format text|json]"
            ),
            "zotero mcp serve": .init(
                rule: .init(pathLength: 3),
                help: "Usage: scholium zotero mcp serve"
            ),
        ]
    }()
}
