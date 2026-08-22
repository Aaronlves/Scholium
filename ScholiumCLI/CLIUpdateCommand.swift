import Foundation
import ScholiumCLIUpdate

extension ScholiumCLI {
    static func runUpdate(_ arguments: [String]) async throws {
        let formatValue = option("--format", in: arguments) ?? "text"
        guard let format = CLIOutputFormat(rawValue: formatValue),
              format == .text || format == .json else {
            throw CLIError.usage("Update supports --format text or json.")
        }

        let executable = currentExecutableURL()
        let expectedRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .standardizedFileURL
        let actualRoot = executable.deletingLastPathComponent().standardizedFileURL
        guard actualRoot == expectedRoot else {
            throw CLIUpdateError.invalidInstallation(
                "expected \(expectedRoot.path), found \(actualRoot.path)"
            )
        }

        let report = try await CLIUpdateEngine().run(
            currentExecutable: executable,
            currentIdentity: currentBuildIdentity(),
            mode: arguments.contains("--check") ? .check : .apply
        )
        if format == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            write(String(decoding: try encoder.encode(report), as: UTF8.self) + "\n")
            return
        }

        switch report.state {
        case .upToDate:
            write("Scholium CLI is up to date (\(report.current.releaseLabel)).\n")
        case .updateAvailable:
            write(
                "Scholium CLI update available: \(report.available.releaseLabel). "
                    + "Run 'scholium update' to install it.\n"
            )
        case .updated:
            write(
                "Updated Scholium CLI from \(report.current.releaseLabel) "
                    + "to \(report.available.releaseLabel).\n"
            )
        }
    }
}
