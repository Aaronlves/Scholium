import Foundation
import ScholiumContracts

private struct BibliographyCancellationOutput: Encodable {
    let requestID: UUID
    let state: String

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case state
    }
}

extension ScholiumCLI {
    static func runBibliography(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(
                "Usage: scholium bibliography <prepare|show|complete|cancel> ..."
            )
        }
        let encoder = bibliographyEncoder()
        let decoder = bibliographyDecoder()

        switch subcommand {
        case "prepare":
            guard let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium bibliography prepare --from <json|-> --format json|markdown"
                )
            }
            let request = try decoder.decode(
                RecommendedBibliographyRequest.self,
                from: bibliographyInput(input)
            )
            let assignment = try await context.triptych(containing: [request.target.note.vaultID])
            let handle = try await context.handle(for: assignment)
            let preparation = try await handle.research.prepareRecommendation(request)
            switch option("--format", in: arguments) ?? "markdown" {
            case "json":
                write(String(decoding: try encoder.encode(preparation), as: UTF8.self) + "\n")
            case "markdown":
                write(preparation.instructions)
                if !preparation.instructions.hasSuffix("\n") { write("\n") }
            default:
                throw CLIError.usage(
                    "Bibliography prepare supports --format json or markdown."
                )
            }

        case "show":
            guard arguments.count >= 2, let requestID = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(
                    "Usage: scholium bibliography show <request-id> [--triptych <selector>] --format json|markdown"
                )
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let preparation = try await handle.research.recommendationRequest(id: requestID)
            switch option("--format", in: arguments) ?? "markdown" {
            case "json":
                write(String(decoding: try encoder.encode(preparation), as: UTF8.self) + "\n")
            case "markdown":
                write(preparation.instructions)
                if !preparation.instructions.hasSuffix("\n") { write("\n") }
            default:
                throw CLIError.usage(
                    "Bibliography show supports --format json or markdown."
                )
            }

        case "complete":
            guard let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium bibliography complete --from <json|-> [--triptych <selector>] --format json"
                )
            }
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Bibliography complete supports --format json.")
            }
            let submission = try decoder.decode(
                RecommendedBibliographyCompletionSubmission.self,
                from: bibliographyInput(input)
            )
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            let projection = try await handle.research.completeRecommendation(submission)
            write(String(decoding: try encoder.encode(projection), as: UTF8.self) + "\n")

        case "cancel":
            guard arguments.count >= 2, let requestID = UUID(uuidString: arguments[1]) else {
                throw CLIError.usage(
                    "Usage: scholium bibliography cancel <request-id> [--triptych <selector>]"
                )
            }
            guard (option("--format", in: arguments) ?? "json") == "json" else {
                throw CLIError.usage("Bibliography cancel supports --format json.")
            }
            let assignment = try await context.selectedTriptych(
                selector: option("--triptych", in: arguments)
            )
            let handle = try await context.handle(for: assignment)
            try await handle.research.cancelRecommendation(id: requestID)
            let output = BibliographyCancellationOutput(
                requestID: requestID,
                state: "cancelled"
            )
            write(String(decoding: try encoder.encode(output), as: UTF8.self) + "\n")

        default:
            throw CLIError.usage("Unknown bibliography command '\(subcommand)'.")
        }
    }

    private static func bibliographyInput(_ specification: String) throws -> Data {
        if specification == "-" { return FileHandle.standardInput.readDataToEndOfFile() }
        let path = (specification as NSString).expandingTildeInPath
        return try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
    }

    private static func bibliographyEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func bibliographyDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
