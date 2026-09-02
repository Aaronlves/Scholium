import Foundation
import ScholiumContracts

extension ScholiumCLI {
    static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func options(_ name: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == name,
                  arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
    }

    static func printHelp() throws {
        try printHelp(path: [], format: .text)
    }

    static func printHelp(path: [String], format: CLIOutputFormat) throws {
        let text = try helpText(for: path)
        switch format {
        case .text, .markdown, .jsonl:
            write(text + (text.hasSuffix("\n") ? "" : "\n"))
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [
                .prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
            ]
            let data = try encoder.encode(CLIHelpReport(path: path, help: text))
            write(String(decoding: data, as: UTF8.self) + "\n")
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
            throw CLIError.usage(
                "Unknown help topic '\(key)'. Run 'scholium help'."
            )
        }
        return """
        Scholium CLI — local Triptych maintenance and MCP adapter

        Commands:
        \(rootCommandUsage)

        `scholium mcp serve` is the fixed external collaboration surface. It
        connects only to the currently running App and does not open a
        Triptych or read research files itself.

        Omitting --triptych requires exactly one configured Triptych.
        Triptych roles: analyses, topics, works.

        Existing-note maintenance commands require the exact SHA-256 reported
        by `scholium read --format json`. A fingerprint is a revision check,
        never permission to change research material.
        """
    }

    static func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    static func writeError(_ string: String) {
        FileHandle.standardError.write(Data(string.utf8))
    }

    static var searchHelp: String {
        let capabilities = SearchCapabilities.current
        let noteFields = capabilities.capability(for: .note)?
            .fields.map { "\($0.name):" }.joined(separator: ", ") ?? ""
        let examples = capabilities.capability(for: .note)?.examples
            .map { "  scholium search '\($0)' --triptych <selector>" }
            .joined(separator: "\n") ?? ""
        return """
        Usage: scholium search <query> (--vault <selector> [--triptych <selector>] | --triptych <selector>) [--limit <count>] [--format text|jsonl]

        The positional query uses the shared Search v\(capabilities.contractVersion)
        grammar and searches current Notes. Fields: \(noteFields)

        Examples:
        \(examples)
        """
    }
}

enum CLIOutputFormat: String {
    case text
    case json
    case jsonl
    case markdown
}

private struct CLIHelpReport: Encodable {
    let schemaVersion = 3
    let path: [String]
    let help: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case path, help
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
        case .usage(let message): message
        case .invalidUTF8(let path): "File is not valid UTF-8: \(path)"
        case .noteNotFound(let target): "The workspace note was not found: \(target)"
        case .unavailable(let message): message
        case .searchDiagnostic(let diagnostic): diagnostic.message
        }
    }
}
