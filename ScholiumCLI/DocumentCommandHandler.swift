import Foundation
import ScholiumContracts

extension ScholiumCLI {
    static func runRead(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let specification = arguments.first else {
            throw commandUsageError("read")
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
        // Text mode is an exact-source stream so redirection and Agent reads
        // preserve the authoritative bytes, including final-newline state.
        write(document.rawContent)
    }

    static func runNote(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw commandUsageError("note")
        }
        switch subcommand {
        case "create":
            guard arguments.count >= 2 else {
                throw commandUsageError("note create")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let body =
                try option("--from", in: arguments)
                .map(sourceContent(from:)) ?? ""
            let outcome = try await handle.documents.createManagedNote(
                try ManagedNoteCreationRequest(
                    vaultID: vault.id,
                    destination: .exact(relativePath: path),
                    source: body
                )
            )
            let document = outcome.committedValue
            write("Created \(vault.name):\(document.id.relativePath)\nSHA-256: \(document.document.fingerprint.sha256)\n")
            writeMutationWarnings(outcome)
        case "import":
            guard arguments.count >= 2, let input = option("--from", in: arguments) else {
                throw commandUsageError("note import")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let outcome = try await handle.documents.importMarkdownSource(
                try sourceContent(from: input),
                at: VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            )
            let document = outcome.committedValue
            write("Imported \(vault.name):\(path)\nSHA-256: \(document.fingerprint.sha256)\n")
            writeMutationWarnings(outcome)
        case "replace":
            guard arguments.count >= 2,
                let input = option("--from", in: arguments),
                let expected = option("--expected", in: arguments)
            else {
                throw commandUsageError("note replace")
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
                throw commandUsageError("note move")
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
        case "move-to-trash":
            guard arguments.count >= 2,
                let expected = option("--expected", in: arguments)
            else {
                throw commandUsageError("note move-to-trash")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let noteID = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let current = try await handle.documents.load(noteID)
            try requireExpected(expected, current: current.fingerprint)
            let snapshots = try await handle.documents.snapshot()
            guard
                let note = snapshots.first(where: { $0.vault.id == vault.id })?
                    .documents.first(where: { $0.id == noteID }),
                let stableNoteID = note.stableIdentity.resolvedID
            else {
                throw CLIError.usage(
                    "The Note has no resolved stable identity; refresh and resolve it before moving it to Trash."
                )
            }
            let preview = try await handle.documents.prepareSystemTrash(
                NoteMutationTarget(
                    documentID: noteID,
                    stableNoteID: stableNoteID,
                    revision: current.fingerprint
                )
            )
            let outcome = try await handle.documents.moveToSystemTrash(preview)
            write(
                "Moved \(vault.name):\(path) to the macOS Trash. Finder owns file restoration.\n"
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

    }
}
