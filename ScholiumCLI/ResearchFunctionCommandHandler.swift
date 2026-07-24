import Foundation
import ScholiumContracts

extension ScholiumCLI {
    static func runFunction(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(
                "Usage: scholium function <available|prepare|show|prepare-fidelity|complete|cancel> ..."
            )
        }
        let encoder = researchFunctionEncoder()
        let decoder = researchFunctionDecoder()

        switch subcommand {
        case "available":
            guard let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium function available --from <json|-> [--format json]"
                )
            }
            let target = try decoder.decode(
                ResearchFunctionTarget.self,
                from: researchFunctionInput(input)
            )
            let assignment = try await context.triptych(containing: [target.note.vaultID])
            let handle = try await context.handle(for: assignment)
            let result = try await handle.research.availableFunctions(for: target)
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Function available supports --format json.")
            }
            write(String(decoding: try encoder.encode(result), as: UTF8.self) + "\n")

        case "prepare":
            guard let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium function prepare --from <json|-> --format json|markdown"
                )
            }
            let request = try decoder.decode(
                ResearchFunctionRequest.self,
                from: researchFunctionInput(input)
            )
            let vaultIDs = Set(
                [request.target.note.vaultID]
                    + request.materials.map(\.note.vaultID)
            )
            let assignment = try await context.triptych(containing: vaultIDs)
            let handle = try await context.handle(for: assignment)
            let preparation = try await handle.research.prepareFunction(request)
            switch option("--format", in: arguments) ?? "markdown" {
            case "json":
                write(String(decoding: try encoder.encode(preparation), as: UTF8.self) + "\n")
            case "markdown":
                write(preparation.instructions)
                if !preparation.instructions.hasSuffix("\n") { write("\n") }
            default:
                throw CLIError.usage("Function prepare supports --format json or markdown.")
            }

        case "show":
            guard arguments.count >= 2, let runID = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(
                    "Usage: scholium function show <run-id> [--triptych <selector>] --format json|markdown"
                )
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let preparation = try await handle.research.functionRun(id: runID)
            switch option("--format", in: arguments) ?? "markdown" {
            case "json":
                write(String(decoding: try encoder.encode(preparation), as: UTF8.self) + "\n")
            case "markdown":
                write("# Scholium Function Run\n\n")
                write("Run ID: \(runID.uuidString.lowercased())\n")
                write("State: \(preparation.state.rawValue)\n\n")
                write(preparation.instructions)
                if !preparation.instructions.hasSuffix("\n") { write("\n") }
            default:
                throw CLIError.usage("Function show supports --format json or markdown.")
            }

        case "prepare-fidelity":
            guard arguments.count >= 2, let parentRunID = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(
                    "Usage: scholium function prepare-fidelity <parent-run-id> [--triptych <selector>] --format json|markdown"
                )
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let automatic = try await handle.research.prepareAutomaticFidelity(
                parentRunID: parentRunID
            )
            switch option("--format", in: arguments) ?? "markdown" {
            case "json":
                write(String(decoding: try encoder.encode(automatic), as: UTF8.self) + "\n")
            case "markdown":
                write(automatic.preparation.instructions)
                if !automatic.preparation.instructions.hasSuffix("\n") { write("\n") }
            default:
                throw CLIError.usage(
                    "Function prepare-fidelity supports --format json or markdown."
                )
            }

        case "complete":
            guard let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium function complete --from <json|-> [--triptych <selector>] --format json"
                )
            }
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Function complete supports --format json.")
            }
            let submission = try decoder.decode(
                ResearchFunctionCompletionSubmission.self,
                from: researchFunctionInput(input)
            )
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let completion = try await handle.research.completeFunction(submission)
            write(String(decoding: try encoder.encode(completion), as: UTF8.self) + "\n")

        case "cancel":
            guard arguments.count >= 2,
                  let runID = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(
                    "Usage: scholium function cancel <run-id> [--triptych <selector>]"
                )
            }
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Function cancel supports --format json.")
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            try await handle.research.cancelFunction(runID: runID)
            write(String(
                decoding: try encoder.encode(FunctionCancellationReport(runID: runID)),
                as: UTF8.self
            ) + "\n")

        default:
            throw CLIError.usage("Unknown function command '\(subcommand)'.")
        }
    }

    private static func researchFunctionInput(_ specification: String) throws -> Data {
        if specification == "-" {
            return FileHandle.standardInput.readDataToEndOfFile()
        }
        let url = URL(fileURLWithPath: (specification as NSString).expandingTildeInPath)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func researchFunctionEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func researchFunctionDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct FunctionCancellationReport: Encodable {
    let runID: UUID
    let state = ResearchFunctionRunState.cancelled
}
