import Foundation
import ScholiumContracts

extension ScholiumCLI {
    static func runAction(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(
                "Usage: scholium action <available|prepare|show|prepare-fidelity|complete|cancel> ..."
            )
        }
        let encoder = researchActionEncoder()
        let decoder = researchActionDecoder()

        switch subcommand {
        case "available":
            guard let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium action available --from <json|-> [--format json]"
                )
            }
            let target = try decoder.decode(
                ResearchActionNoteSnapshot.self,
                from: researchActionInput(input)
            )
            let assignment = try await context.triptych(containing: [target.note.vaultID])
            let handle = try await context.handle(for: assignment)
            let result = try await handle.research.availableActions(for: target)
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Action available supports --format json.")
            }
            write(String(decoding: try encoder.encode(result), as: UTF8.self) + "\n")

        case "prepare":
            guard let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium action prepare --from <json|-> --format json|markdown"
                )
            }
            let request = try decoder.decode(
                ResearchActionExecutionRequest.self,
                from: researchActionInput(input)
            )
            let parameterVaultIDs = request.parameterValues.values.flatMap { value -> [UUID] in
                guard case .notes(let notes) = value else { return [] }
                return notes.map(\.note.vaultID)
            }
            let vaultIDs = Set([request.target.note.vaultID] + parameterVaultIDs)
            let assignment = try await context.triptych(containing: vaultIDs)
            let handle = try await context.handle(for: assignment)
            let preparation = try await handle.research.prepareAction(request)
            switch option("--format", in: arguments) ?? "markdown" {
            case "json":
                write(String(decoding: try encoder.encode(preparation), as: UTF8.self) + "\n")
            case "markdown":
                write(preparation.instructions)
                if !preparation.instructions.hasSuffix("\n") { write("\n") }
            default:
                throw CLIError.usage("Action prepare supports --format json or markdown.")
            }

        case "show":
            guard arguments.count >= 2, let runID = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(
                    "Usage: scholium action show <run-id> [--triptych <selector>] --format json|markdown"
                )
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let preparation = try await handle.research.actionRun(id: runID)
            switch option("--format", in: arguments) ?? "markdown" {
            case "json":
                write(String(decoding: try encoder.encode(preparation), as: UTF8.self) + "\n")
            case "markdown":
                write("# Scholium Action Run\n\n")
                write("Run ID: \(runID.uuidString.lowercased())\n")
                write("State: \(preparation.state.rawValue)\n\n")
                write(preparation.instructions)
                if !preparation.instructions.hasSuffix("\n") { write("\n") }
            default:
                throw CLIError.usage("Action show supports --format json or markdown.")
            }

        case "prepare-fidelity":
            guard arguments.count >= 2, let parentRunID = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(
                    "Usage: scholium action prepare-fidelity <parent-run-id> [--triptych <selector>] --format json|markdown"
                )
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let automatic = try await handle.research.prepareActionFidelity(
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
                    "Action prepare-fidelity supports --format json or markdown."
                )
            }

        case "complete":
            guard let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium action complete --from <json|-> [--triptych <selector>] --format json"
                )
            }
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Action complete supports --format json.")
            }
            let submission = try decoder.decode(
                ResearchActionCompletionSubmission.self,
                from: researchActionInput(input)
            )
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let completion = try await handle.research.completeAction(submission)
            write(String(decoding: try encoder.encode(completion), as: UTF8.self) + "\n")

        case "cancel":
            guard arguments.count >= 2,
                  let runID = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(
                    "Usage: scholium action cancel <run-id> [--triptych <selector>]"
                )
            }
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Action cancel supports --format json.")
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            try await handle.research.cancelAction(runID: runID)
            write(String(
                decoding: try encoder.encode(ActionCancellationReport(runID: runID)),
                as: UTF8.self
            ) + "\n")

        default:
            throw CLIError.usage("Unknown action command '\(subcommand)'.")
        }
    }

    private static func researchActionInput(_ specification: String) throws -> Data {
        if specification == "-" {
            return FileHandle.standardInput.readDataToEndOfFile()
        }
        let url = URL(fileURLWithPath: (specification as NSString).expandingTildeInPath)
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private static func researchActionEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func researchActionDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct ActionCancellationReport: Encodable {
    let runID: UUID
    let state = ResearchActionRunState.cancelled
}
