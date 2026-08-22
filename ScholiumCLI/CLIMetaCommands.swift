import Darwin
import Foundation
import ScholiumContracts
import ScholiumCLIUpdate

extension ScholiumCLI {
    static let productVersion = ScholiumProductIdentity.marketingVersion

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
        let identity = currentBuildIdentity()
        if format == .json {
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "schema_version": 1,
                    "product": "Scholium",
                    "cli_version": identity.marketingVersion,
                    "release_label": identity.releaseLabel,
                    "build_number": identity.buildNumber,
                ],
                options: [.prettyPrinted, .sortedKeys]
            )
            write(String(decoding: data, as: UTF8.self) + "\n")
        } else {
            write(
                "Scholium CLI \(identity.marketingVersion) "
                    + "(\(identity.releaseLabel); build \(identity.buildNumber))\n"
            )
        }
    }

    typealias BuildIdentity = CLIReleaseIdentity

    static func currentBuildIdentity() -> BuildIdentity {
        for candidate in buildProvenanceCandidates() {
            guard let data = try? Data(contentsOf: candidate),
                  let values = try? PropertyListSerialization.propertyList(
                      from: data,
                      options: [],
                      format: nil
                  ) as? [String: Any],
                  values["schema"] as? String == "scholium-build-provenance-v1",
                  let marketingVersion = values["marketing_version"] as? String,
                  !marketingVersion.isEmpty,
                  let releaseLabel = values["release_label"] as? String,
                  !releaseLabel.isEmpty,
                  let buildNumber = values["build_number"] as? String,
                  !buildNumber.isEmpty else {
                continue
            }
            return BuildIdentity(
                marketingVersion: marketingVersion,
                releaseLabel: releaseLabel,
                buildNumber: buildNumber,
                packageMode: values["package_mode"] as? String,
                gitExactTag: values["git_exact_tag"] as? String
            )
        }
        return BuildIdentity(
            marketingVersion: productVersion,
            releaseLabel: "development",
            buildNumber: "0",
            packageMode: "development"
        )
    }

    private static func buildProvenanceCandidates() -> [URL] {
        let executable = currentExecutableURL()
        let directory = executable.deletingLastPathComponent()
        var candidates = [
            directory
                .appendingPathComponent(
                    "Scholium_ScholiumCore.bundle/Contents/Resources",
                    isDirectory: true
                )
                .appendingPathComponent("ScholiumBuildProvenance.plist"),
        ]
        if directory.lastPathComponent == "Helpers" {
            candidates.append(
                directory.deletingLastPathComponent()
                    .appendingPathComponent("Resources", isDirectory: true)
                    .appendingPathComponent("ScholiumBuildProvenance.plist")
            )
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(
                resources.appendingPathComponent("ScholiumBuildProvenance.plist")
            )
        }
        return candidates
    }

    static func currentExecutableURL() -> URL {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: Int(size))
            let status = buffer.withUnsafeMutableBufferPointer { pointer in
                _NSGetExecutablePath(pointer.baseAddress, &size)
            }
            if status == 0 {
                let pathBytes = buffer.prefix { $0 != 0 }.map {
                    UInt8(bitPattern: $0)
                }
                return URL(
                    fileURLWithPath: String(decoding: pathBytes, as: UTF8.self),
                    isDirectory: false
                ).standardizedFileURL.resolvingSymlinksInPath()
            }
        }
        if let executable = Bundle.main.executableURL {
            return executable.standardizedFileURL.resolvingSymlinksInPath()
        }
        return URL(
            fileURLWithPath: CommandLine.arguments[0],
            isDirectory: false
        ).standardizedFileURL.resolvingSymlinksInPath()
    }

    static func runDoctor(_ arguments: [String], context: CLIContext) async throws {
        let formatValue = option("--format", in: arguments) ?? "text"
        guard let format = CLIOutputFormat(rawValue: formatValue),
              format == .text || format == .json else {
            throw CLIError.usage("Doctor supports --format text or json.")
        }
        let assignments = try await context.assignments()
        let executable = currentExecutableURL().path
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
            platformActionCount: PlatformActionCatalog.definitions.count,
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
            write("Platform Actions: \(report.platformActionCount)\n")
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
        let requestedFormat = arguments.indices.compactMap { index -> String? in
            arguments[index] == "--format"
                && arguments.indices.contains(index + 1)
                ? arguments[index + 1]
                : nil
        }.first
        let isAgentCommand = arguments.first == "agent"
        guard requestedFormat == "json" || requestedFormat == "jsonl"
                || isAgentCommand else {
            writeError("scholium: \(error.localizedDescription)\n")
            return
        }
        let commandPath = arguments.first == "update"
            ? arguments.prefix(1)
            : arguments.prefix(2)
        let report = CLIErrorReport(
            code: errorCode(for: error),
            message: error.localizedDescription,
            command: commandPath.joined(separator: " "),
            help: "scholium help " + commandPath.joined(separator: " "),
            diagnostic: searchDiagnostic(for: error),
            recovery: (error as? any AgentCommandErrorCodeProviding)?
                .agentCommandRecovery
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = requestedFormat == "jsonl"
            ? [.sortedKeys, .withoutEscapingSlashes]
            : [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(report) {
            writeError(String(decoding: data, as: UTF8.self) + "\n")
        } else {
            writeError("scholium: \(error.localizedDescription)\n")
        }
    }

    private static func errorCode(for error: Error) -> String {
        if let structured = error as? any AgentCommandErrorCodeProviding {
            return structured.agentCommandErrorCode
        }
        if let cli = error as? CLIError {
            switch cli {
            case .usage: return "usage_error"
            case .invalidUTF8: return "invalid_utf8"
            case .noteNotFound: return "note_not_found"
            case .unavailable: return "unavailable"
            case .searchDiagnostic: return "search_query_diagnostic"
            }
        }
        if error is DecodingError { return "invalid_json" }
        if let update = error as? CLIUpdateError { return update.code }
        return "operation_failed"
    }

    private static func searchDiagnostic(for error: Error) -> SearchQueryDiagnostic? {
        guard let cli = error as? CLIError,
              case .searchDiagnostic(let diagnostic) = cli else { return nil }
        return diagnostic
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
    let platformActionCount: Int
    let zoteroState: String

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case cliVersion = "cli_version"
        case executable
        case pathDiscoverable = "path_discoverable"
        case isolatedHome = "isolated_home"
        case triptychCount = "triptych_count"
        case triptychs
        case platformActionCount = "platform_action_count"
        case zoteroState = "zotero_state"
    }
}

private struct CLIDoctorTriptych: Encodable {
    let id: UUID
    let name: String
    let roles: [String]
}

private struct CLIErrorReport: Encodable {
    let schemaVersion = 2
    let error = true
    let code: String
    let message: String
    let command: String
    let help: String
    let diagnostic: SearchQueryDiagnostic?
    let recovery: AgentOperationRecovery?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case error, code, message, command, help, diagnostic, recovery
    }
}
