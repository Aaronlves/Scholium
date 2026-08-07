import ScholiumContracts
import Foundation

extension ScholiumCLI {
    static func runRead(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let specification = arguments.first else {
            throw CLIError.usage("Usage: scholium read <vault>:<relative-path>")
        }
        let format = option("--format", in: arguments) ?? "text"
        guard format == "text" || format == "json" else {
            throw CLIError.usage("Read supports --format text or json.")
        }
        let (vault, relativePath) = try await context.resolveTarget(specification)
        let assignment = try await context.triptych(containing: [vault.id])
        let handle = try await context.handle(for: assignment)
        let document = try await handle.documents.load(
            VaultQualifiedNoteID(vaultID: vault.id, relativePath: relativePath)
        )
        if format == "json" {
            let payload: [String: String] = [
                "vault_id": vault.id.uuidString,
                "vault_name": vault.name,
                "relative_path": relativePath,
                "sha256": document.fingerprint.sha256,
                "content": document.rawContent,
            ]
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            write(String(decoding: data, as: UTF8.self) + "\n")
            return
        }
        write(document.rawContent)
        if !document.rawContent.hasSuffix("\n") { write("\n") }
    }

    static func runNote(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(
                "Usage: scholium note <create|replace|move|set-aside|trash|delete> ..."
            )
        }
        switch subcommand {
        case "create":
            guard arguments.count >= 2, let input = option("--from", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium note create <vault>:<path> --from <markdown-file>"
                )
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let content = try sourceContent(from: input)
            let outcome = try await handle.documents.create(
                VaultQualifiedNoteID(vaultID: vault.id, relativePath: path),
                content: content
            )
            let document = outcome.committedValue
            write("Created \(vault.name):\(path)\nSHA-256: \(document.fingerprint.sha256)\n")
            writeMutationWarnings(outcome)
        case "replace":
            guard arguments.count >= 2,
                  let input = option("--from", in: arguments),
                  let expected = option("--expected", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium note replace <vault>:<path> --from <markdown-file> --expected <sha256>"
                )
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let noteID = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let current = try await handle.documents.load(noteID)
            try requireExpected(expected, current: current.fingerprint)
            let outcome = try await handle.documents.save(
                noteID,
                changeSet: .exactContent(try sourceContent(from: input)),
                expectedRevision: current.fingerprint
            )
            let result = outcome.committedValue
            write(
                "Replaced \(vault.name):\(path)\nSHA-256: \(result.document.fingerprint.sha256)\n"
            )
            writeMutationWarnings(outcome)
        case "move":
            guard arguments.count >= 3, let expected = option("--expected", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium note move <vault>:<path> <new-relative-path> --expected <sha256>"
                )
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let noteID = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let current = try await handle.documents.load(noteID)
            try requireExpected(expected, current: current.fingerprint)
            let outcome = try await handle.documents.move(
                noteID,
                to: arguments[2],
                expectedRevision: current.fingerprint
            )
            let result = outcome.committedValue
            write("Moved \(vault.name):\(path) -> \(result.destination.relativePath)\n")
            writeMutationWarnings(outcome)
        case "set-aside", "trash":
            guard arguments.count >= 2, let expected = option("--expected", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium note \(subcommand) <vault>:<path> --expected <sha256>"
                )
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let noteID = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let current = try await handle.documents.load(noteID)
            try requireExpected(expected, current: current.fingerprint)
            let outcome = subcommand == "set-aside"
                ? try await handle.documents.setAside(
                    noteID,
                    expectedRevision: current.fingerprint
                )
                : try await handle.documents.moveToTrash(
                    noteID,
                    expectedRevision: current.fingerprint
                )
            let result = outcome.committedValue
            write("Moved \(vault.name):\(path) -> \(result.destination.relativePath)\n")
            writeMutationWarnings(outcome)
        case "delete":
            guard arguments.count >= 2,
                  arguments.contains("--permanent"),
                  let expected = option("--expected", in: arguments) else {
                throw CLIError.usage(
                    "Usage: scholium note delete <vault>:<Trash/path.md> --permanent --expected <sha256>"
                )
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            guard path.hasPrefix("Trash/") else {
                throw CLIError.usage(
                    "Permanent deletion is allowed only for a note already in Trash."
                )
            }
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let noteID = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let current = try await handle.documents.load(noteID)
            try requireExpected(expected, current: current.fingerprint)
            let outcome = try await handle.documents.deletePermanently(
                noteID,
                expectedRevision: current.fingerprint
            )
            write(
                "Permanently deleted \(vault.name):\(path). Recovery history was retained.\n"
            )
            writeMutationWarnings(outcome)
        default:
            throw CLIError.usage("Unknown note command '\(subcommand)'.")
        }
    }

    private static func sourceContent(from path: String) throws -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let content = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw CLIError.invalidUTF8(path)
        }
        return content
    }

    private static func requireExpected(
        _ expectedSHA256: String,
        current: DocumentFingerprint
    ) throws {
        guard expectedSHA256.lowercased() == current.sha256.lowercased() else {
            throw CLIError.usage(
                "Revision mismatch. Re-read the note and use its current SHA-256 fingerprint."
            )
        }
    }

    private static func writeMutationWarnings<CommittedValue: Sendable>(
        _ outcome: WorkspaceMutationOutcome<CommittedValue>
    ) {
        if let warning = outcome.derivedRefreshWarning {
            writeError(
                "scholium: warning: The source operation committed, but derived views may be stale. Refresh them; do not repeat the mutation. \(warning)\n"
            )
        }
        if let warning = outcome.identityRecoveryWarning {
            writeError(
                "scholium: warning: The source operation committed, but stable note identity recovery is incomplete. Do not repeat the mutation. \(warning)\n"
            )
        }
        for warning in outcome.cleanupWarnings {
            writeError(
                "scholium: warning: The source operation committed, but machine-local cleanup is still pending. Do not repeat the mutation. \(warning.message)\n"
            )
        }
    }
}
