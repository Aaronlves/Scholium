import Foundation
import ScholiumContracts

extension ScholiumCLI {
    static let productVersion = ScholiumProductIdentity.releaseLabel

    static func renderMetaCommandIfPresent(_ arguments: [String]) throws -> Bool {
        guard let first = arguments.first else { return false }
        if first == "version" || first == "--version" {
            let remainder = Array(arguments.dropFirst())
            try validateMetaArguments(remainder, allowsHelpPath: false)
            let format = try metaFormat(in: remainder)
            try renderVersion(format: format)
            return true
        }

        if first == "help" || first == "--help" || first == "-h" {
            let remainder = first == "help" ? Array(arguments.dropFirst()) : Array(arguments.dropFirst())
            try validateMetaArguments(remainder, allowsHelpPath: true)
            let format = try metaFormat(in: remainder)
            let path = helpPath(in: remainder)
            guard path.count <= 2 else {
                throw CLIError.usage("Help accepts at most a command and subcommand.")
            }
            printHelp(path: path, format: format)
            return true
        }

        if let helpIndex = arguments.firstIndex(where: { $0 == "--help" || $0 == "-h" }) {
            let format = try metaFormat(in: Array(arguments[(helpIndex + 1)...]))
            let path = Array(arguments[..<helpIndex].prefix(2))
            printHelp(path: path, format: format)
            return true
        }
        return false
    }

    private static func validateMetaArguments(
        _ arguments: [String],
        allowsHelpPath: Bool
    ) throws {
        var positionalCount = 0
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token == "--format" {
                guard arguments.indices.contains(index + 1) else {
                    throw CLIError.usage("Option '--format' requires a value.")
                }
                index += 2
            } else if token.hasPrefix("-") {
                throw CLIError.usage("Unknown option '\(token)'.")
            } else if allowsHelpPath {
                positionalCount += 1
                index += 1
            } else {
                throw CLIError.usage("Unexpected argument '\(token)'.")
            }
        }
        if positionalCount > 2 {
            throw CLIError.usage("Help accepts at most a command and subcommand.")
        }
    }

    private static func metaFormat(in arguments: [String]) throws -> CLIOutputFormat {
        let formatIndexes = arguments.indices.filter { arguments[$0] == "--format" }
        guard formatIndexes.count <= 1 else {
            throw CLIError.usage("Option '--format' may be supplied only once.")
        }
        guard let index = formatIndexes.first else { return .text }
        guard arguments.indices.contains(index + 1) else {
            throw CLIError.usage("Option '--format' requires a value.")
        }
        let value = arguments[index + 1]
        guard value == "text" || value == "json" else {
            throw CLIError.usage("Help and version support --format text or json.")
        }
        return CLIOutputFormat(rawValue: value) ?? .text
    }

    private static func helpPath(in arguments: [String]) -> [String] {
        var path: [String] = []
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--format" {
                index += 2
            } else if !arguments[index].hasPrefix("-") {
                path.append(arguments[index])
                index += 1
            } else {
                index += 1
            }
        }
        return path
    }

    private static func renderVersion(format: CLIOutputFormat) throws {
        let bundleVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let version = bundleVersion?.isEmpty == false ? bundleVersion! : productVersion
        if format == .json {
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "schema_version": 1,
                    "product": "Scholium",
                    "cli_version": version,
                ],
                options: [.prettyPrinted, .sortedKeys]
            )
            write(String(decoding: data, as: UTF8.self) + "\n")
        } else {
            write("Scholium CLI \(version)\n")
        }
    }

    static func runDoctor(_ arguments: [String], context: CLIContext) async throws {
        let formatValue = option("--format", in: arguments) ?? "text"
        guard let format = CLIOutputFormat(rawValue: formatValue),
              format == .text || format == .json else {
            throw CLIError.usage("Doctor supports --format text or json.")
        }
        let assignments = try await context.assignments()
        let catalog = try await context.runtime.researchGuidance.catalog()
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let report = CLIDoctorReport(
            cliVersion: productVersion,
            executable: executable,
            pathDiscoverable: executableIsDiscoverable(executable),
            isolatedHome: ProcessInfo.processInfo.environment["SCHOLIUM_HOME"] != nil,
            triptychCount: assignments.count,
            triptychs: assignments.map { assignment in
                CLIDoctorTriptych(
                    id: assignment.id,
                    name: assignment.triptych.name,
                    roles: WorkspaceVaultSlot.allCases.filter { slot in
                        assignment.vault(for: slot) != nil
                    }.map(\.rawValue)
                )
            },
            protectedSkillCount: catalog.entries.count,
            zoteroState: context.runtime.zotero.report().state.rawValue
        )
        if format == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            write(String(decoding: try encoder.encode(report), as: UTF8.self) + "\n")
        } else {
            write("Scholium CLI \(report.cliVersion)\n")
            write("Executable: \(report.executable)\n")
            write("PATH discovery: \(report.pathDiscoverable ? "ready" : "not available in this shell")\n")
            write("Triptychs: \(report.triptychCount)\n")
            for triptych in report.triptychs {
                write("  \(triptych.id.uuidString.lowercased())  \(triptych.name)  [\(triptych.roles.joined(separator: ", "))]\n")
            }
            write("Protected Skills: \(report.protectedSkillCount)\n")
            write("Zotero transport: \(report.zoteroState)\n")
            if report.triptychCount == 0 {
                write("Repair: configure Analyses, Topics, and Works in Scholium, then run doctor again.\n")
            }
        }
    }

    private static func executableIsDiscoverable(_ executable: String) -> Bool {
        let name = URL(fileURLWithPath: executable).lastPathComponent
        return (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .contains { directory in
                FileManager.default.isExecutableFile(
                    atPath: URL(fileURLWithPath: directory)
                        .appendingPathComponent(name)
                        .standardizedFileURL.path
                )
            }
    }

    static func writeCLIError(_ error: Error, arguments: [String]) {
        let wantsJSON = arguments.indices.contains { index in
            arguments[index] == "--format"
                && arguments.indices.contains(index + 1)
                && arguments[index + 1] == "json"
        }
        guard wantsJSON else {
            writeError("scholium: \(error.localizedDescription)\n")
            return
        }
        let report = CLIErrorReport(
            code: errorCode(for: error),
            message: error.localizedDescription,
            command: arguments.prefix(2).joined(separator: " "),
            help: "scholium help " + arguments.prefix(2).joined(separator: " ")
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(report) {
            writeError(String(decoding: data, as: UTF8.self) + "\n")
        } else {
            writeError("scholium: \(error.localizedDescription)\n")
        }
    }

    private static func errorCode(for error: Error) -> String {
        if let cli = error as? CLIError {
            switch cli {
            case .usage: return "usage_error"
            case .invalidUTF8: return "invalid_utf8"
            case .noteNotFound: return "note_not_found"
            case .unavailable: return "unavailable"
            }
        }
        if error is DecodingError { return "invalid_json" }
        return "operation_failed"
    }
}

private struct CLIDoctorReport: Encodable {
    let schemaVersion = 1
    let cliVersion: String
    let executable: String
    let pathDiscoverable: Bool
    let isolatedHome: Bool
    let triptychCount: Int
    let triptychs: [CLIDoctorTriptych]
    let protectedSkillCount: Int
    let zoteroState: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case cliVersion = "cli_version"
        case executable
        case pathDiscoverable = "path_discoverable"
        case isolatedHome = "isolated_home"
        case triptychCount = "triptych_count"
        case triptychs
        case protectedSkillCount = "protected_skill_count"
        case zoteroState = "zotero_state"
    }
}

private struct CLIDoctorTriptych: Encodable {
    let id: UUID
    let name: String
    let roles: [String]
}

private struct CLIErrorReport: Encodable {
    let schemaVersion = 1
    let error = true
    let code: String
    let message: String
    let command: String
    let help: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case error, code, message, command, help
    }
}
