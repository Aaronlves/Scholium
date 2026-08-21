import Foundation

extension ScholiumCLI {
    struct CLIOptionRule: Sendable {
        let takesValue: Bool
        let repeatable: Bool

        static let value = Self(takesValue: true, repeatable: false)
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

    /// Rejects ambiguous command lines before Application state is opened.
    /// Handlers may still validate semantic combinations and values.
    static func validateCLIArguments(_ arguments: [String]) throws {
        guard !arguments.isEmpty else { return }
        let key = commandRuleKey(arguments)
        guard let rule = commandRules[key] else {
            let path = arguments.prefix(min(arguments.count, 2)).joined(separator: " ")
            throw CLIError.usage(
                "Unknown command '\(path)'. Run 'scholium help' to inspect supported commands."
            )
        }

        var counts: [String: Int] = [:]
        var positionals: [String] = []
        var index = rule.pathLength
        while index < arguments.count {
            let token = arguments[index]
            if token.hasPrefix("--") {
                guard let optionRule = rule.options[token] else {
                    throw CLIError.usage(
                        "Unknown option '\(token)' for 'scholium \(key)'. Run 'scholium help \(key)'."
                    )
                }
                counts[token, default: 0] += 1
                if !optionRule.repeatable, counts[token, default: 0] > 1 {
                    throw CLIError.usage("Option '\(token)' may be supplied only once.")
                }
                if optionRule.takesValue {
                    guard arguments.indices.contains(index + 1) else {
                        throw CLIError.usage("Option '\(token)' requires a value.")
                    }
                    let value = arguments[index + 1]
                    guard value == "-" || !value.hasPrefix("--") else {
                        throw CLIError.usage("Option '\(token)' requires a value.")
                    }
                    index += 2
                } else {
                    index += 1
                }
            } else if token.hasPrefix("-") && token != "-" {
                if key == "search", positionals.isEmpty {
                    // Search's finite query grammar owns leading clause
                    // exclusion. Preserve it as query text so the shared
                    // parser can distinguish valid structured exclusion from
                    // an invalid free-text-only negative query.
                    positionals.append(token)
                    index += 1
                } else {
                    throw CLIError.usage(
                        "Unknown option '\(token)' for 'scholium \(key)'. Run 'scholium help \(key)'."
                    )
                }
            } else {
                positionals.append(token)
                index += 1
            }
        }

        guard rule.positionalCount.contains(positionals.count) else {
            throw CLIError.usage(
                "Invalid arguments for 'scholium \(key)'. Run 'scholium help \(key)'."
            )
        }

        if key == "search" {
            let hasVault = counts["--vault", default: 0] > 0
            let hasTriptych = counts["--triptych", default: 0] > 0
            guard hasVault || hasTriptych else {
                throw CLIError.usage(
                    "Choose --vault <selector> or --triptych <uuid-or-unique-name>."
                )
            }
        }
        if key == "discuss reply",
           counts["--text", default: 0] > 0,
           counts["--from", default: 0] > 0 {
            throw CLIError.usage("Choose either --text or --from for a reply, not both.")
        }
    }

    private static func commandRuleKey(_ arguments: [String]) -> String {
        guard let command = arguments.first else { return "" }
        if command == "search" || command == "read" || command == "doctor" {
            return command
        }
        if command == "zotero", arguments.count >= 3, arguments[1] == "mcp",
           !arguments[2].hasPrefix("-") {
            return arguments.prefix(3).joined(separator: " ")
        }
        guard arguments.count >= 2 else { return command }
        return arguments.prefix(2).joined(separator: " ")
    }

    private static let commandRules: [String: CLICommandRule] = {
        let format: [String: CLIOptionRule] = ["--format": .value]
        let selected: [String: CLIOptionRule] = [
            "--triptych": .value,
            "--format": .value,
        ]
        var rules: [String: CLICommandRule] = [
            "agent start": .init(
                pathLength: 2,
                options: ["--triptych": .value, "--from": .value]
            ),
            "agent pair": .init(pathLength: 2, options: ["--run": .value]),
            "agent context": .init(pathLength: 2, options: ["--run": .value]),
            "agent prepare-fidelity": .init(
                pathLength: 2,
                options: ["--run": .value]
            ),
            "agent reload": .init(pathLength: 2, options: ["--run": .value]),
            "agent query": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent discuss-reply": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent extend-write-set": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent write": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent write-zotero-binding": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent resolve-write-conflict": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent submit-result": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent continue": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent method-context": .init(
                pathLength: 2,
                options: ["--run": .value]
            ),
            "agent improve-method": .init(
                pathLength: 2,
                options: ["--run": .value, "--from": .value]
            ),
            "agent end": .init(pathLength: 2, options: ["--run": .value]),
            "doctor": .init(pathLength: 1, options: format),
            "vault list": .init(pathLength: 2, options: format),
            "search": .init(
                pathLength: 1,
                positionalCount: 1 ... 1,
                options: [
                    "--vault": .value,
                    "--triptych": .value,
                    "--limit": .value,
                    "--format": .value,
                ]
            ),
            "links incoming": .init(pathLength: 2, positionalCount: 1 ... 1, options: format),
            "links outgoing": .init(pathLength: 2, positionalCount: 1 ... 1, options: format),
            "links relationships": .init(pathLength: 2, positionalCount: 1 ... 1, options: format),
            "links diagnostics": .init(
                pathLength: 2,
                options: ["--workspace": .flag, "--triptych": .value, "--format": .value]
            ),
            "graph trace": .init(
                pathLength: 2,
                positionalCount: 2 ... 2,
                options: ["--max-depth": .value, "--format": .value]
            ),
            "graph relation-trace": .init(
                pathLength: 2,
                positionalCount: 2 ... 2,
                options: ["--max-depth": .value, "--format": .value]
            ),
            "workspace catalog": .init(pathLength: 2, options: selected),
            "workspace skill-sources": .init(pathLength: 2, options: selected),
            "workspace attention": .init(
                pathLength: 2,
                options: ["--triptych": .value, "--kind": .value, "--format": .value]
            ),
            "workspace bootstrap": .init(
                pathLength: 2,
                options: [
                    "--triptych": .value,
                    "--target": .value,
                    "--conventions-file": .value,
                    "--format": .value,
                ]
            ),
            "action available": .init(pathLength: 2, options: ["--from": .value, "--format": .value]),
            "action prepare": .init(pathLength: 2, options: ["--from": .value, "--format": .value]),
            "action show": .init(pathLength: 2, positionalCount: 1 ... 1, options: selected),
            "action prepare-fidelity": .init(pathLength: 2, positionalCount: 1 ... 1, options: selected),
            "action cancel": .init(pathLength: 2, positionalCount: 1 ... 1, options: selected),
            "read": .init(pathLength: 1, positionalCount: 1 ... 1, options: format),
            "note create": .init(
                pathLength: 2,
                positionalCount: 1 ... 1,
                options: ["--body-from": .value, "--analysis-from": .value]
            ),
            "note import": .init(
                pathLength: 2,
                positionalCount: 1 ... 1,
                options: ["--from": .value]
            ),
            "note replace": .init(pathLength: 2, positionalCount: 1 ... 1, options: ["--from": .value, "--expected": .value]),
            "note move": .init(pathLength: 2, positionalCount: 2 ... 2, options: ["--expected": .value]),
            "note set-aside": .init(pathLength: 2, positionalCount: 1 ... 1, options: ["--expected": .value]),
            "note trash": .init(pathLength: 2, positionalCount: 1 ... 1, options: ["--expected": .value]),
            "note delete": .init(pathLength: 2, positionalCount: 1 ... 1, options: ["--permanent": .flag, "--expected": .value]),
            "discuss list": .init(pathLength: 2, options: ["--triptych": .value, "--format": .value]),
            "discuss show": .init(pathLength: 2, positionalCount: 1 ... 1, options: selected),
            "discuss reply": .init(
                pathLength: 2,
                positionalCount: 1 ... 1,
                options: [
                    "--triptych": .value,
                    "--agent": .value,
                    "--text": .value,
                    "--from": .value,
                ]
            ),
            "zotero mcp config": .init(pathLength: 3, options: format),
            "zotero mcp": .init(pathLength: 2, options: ["--probe": .flag, "--format": .value]),
            "zotero mcp status": .init(pathLength: 3, options: ["--probe": .flag, "--format": .value]),
            "zotero mcp serve": .init(pathLength: 3),
        ]
        return rules
    }()
}
