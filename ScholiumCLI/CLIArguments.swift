import Foundation

extension ScholiumCLI {
    /// Rejects ambiguous command lines before Application state is opened.
    /// Handlers may still validate semantic combinations and values.
    static func validateCLIArguments(_ arguments: [String]) throws {
        guard !arguments.isEmpty else { return }
        guard let key = commandSpecificationKey(matching: arguments) else {
            let path = arguments.prefix { !$0.hasPrefix("-") }
                .prefix(3)
                .joined(separator: " ")
            throw CLIError.usage(
                "Unknown command '\(path)'. Run 'scholium help' to inspect supported commands."
            )
        }
        guard let rule = commandSpecifications[key]?.rule else {
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
    }

}
