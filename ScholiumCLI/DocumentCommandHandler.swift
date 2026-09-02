import ScholiumContracts
import Foundation

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
        case "metadata-read":
            guard arguments.count >= 2 else {
                throw commandUsageError("note metadata-read")
            }
            let format = option("--format", in: arguments) ?? "json"
            guard format == "json" else {
                throw CLIError.usage("Metadata read supports --format json.")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let source = try await handle.documents.load(id)
            let metadata = try await handle.documents.metadata(id)
            try writeMetadataReport(
                vault: vault,
                path: path,
                source: source,
                metadata: metadata
            )
        case "metadata-set":
            guard arguments.count >= 3,
                  let valuePath = option("--value-from", in: arguments),
                  let expected = option("--expected", in: arguments) else {
                throw commandUsageError("note metadata-set")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let current = try await handle.documents.metadata(id)
            let expectedRevision = try requireExpectedMetadata(expected, current: current)
            let value = try metadataValue(
                from: Data(try sourceContent(from: valuePath).utf8)
            )
            var fields = current?.record.fields ?? [:]
            fields[arguments[2]] = value
            let outcome = try await handle.documents.saveMetadata(
                id,
                fields: fields,
                expectedRevision: expectedRevision
            )
            let source = try await handle.documents.load(id)
            try writeMetadataReport(
                vault: vault,
                path: path,
                source: source,
                metadata: outcome.committedValue
            )
            writeMutationWarnings(outcome)
        case "metadata-remove":
            guard arguments.count >= 3,
                  let expected = option("--expected", in: arguments) else {
                throw commandUsageError("note metadata-remove")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            guard let current = try await handle.documents.metadata(id),
                  current.record.fields[arguments[2]] != nil else {
                throw CLIError.usage(
                    "That managed Metadata field is not present. Run metadata-read before removing it."
                )
            }
            let expectedRevision = try requireExpectedMetadata(expected, current: current)
            var fields = current.record.fields
            fields.removeValue(forKey: arguments[2])
            let outcome = try await handle.documents.saveMetadata(
                id,
                fields: fields,
                expectedRevision: expectedRevision
            )
            let source = try await handle.documents.load(id)
            try writeMetadataReport(
                vault: vault,
                path: path,
                source: source,
                metadata: outcome.committedValue
            )
            writeMutationWarnings(outcome)
        case "create":
            guard arguments.count >= 2 else {
                throw commandUsageError("note create")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let body = try option("--body-from", in: arguments)
                .map(sourceContent(from:)) ?? ""
            let metadata = try option("--analysis-from", in: arguments).map {
                try JSONDecoder().decode(
                    AnalysisCreationMetadata.self,
                    from: Data(try sourceContent(from: $0).utf8)
                )
            }
            let authoredYAML = try option("--authored-yaml-from", in: arguments).map {
                try JSONDecoder().decode(
                    AuthoredNoteYAML.self,
                    from: Data(try sourceContent(from: $0).utf8)
                )
            }
            let outcome = try await handle.documents.createManagedNote(
                try ManagedNoteCreationRequest(
                    vaultID: vault.id,
                    destination: .exact(relativePath: path),
                    body: body,
                    authoredYAML: authoredYAML,
                    analysisMetadata: metadata
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
                  let expected = option("--expected", in: arguments) else {
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
                  let expected = option("--expected", in: arguments) else {
                throw commandUsageError("note move-to-trash")
            }
            let (vault, path) = try await context.resolveTarget(arguments[1])
            let assignment = try await context.triptych(containing: [vault.id])
            let handle = try await context.handle(for: assignment)
            let noteID = VaultQualifiedNoteID(vaultID: vault.id, relativePath: path)
            let current = try await handle.documents.load(noteID)
            try requireExpected(expected, current: current.fingerprint)
            let snapshots = try await handle.documents.snapshot()
            guard let note = snapshots.first(where: { $0.vault.id == vault.id })?
                .documents.first(where: { $0.id == noteID }),
                  let stableNoteID = note.stableIdentity.resolvedID else {
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

    private static func requireExpectedMetadata(
        _ expected: String,
        current: NoteMetadataSnapshot?
    ) throws -> DocumentFingerprint? {
        if expected == "absent" {
            guard current == nil else {
                throw CLIError.usage(
                    "Metadata revision mismatch. Run metadata-read and use its current metadata_sha256."
                )
            }
            return nil
        }
        guard let current,
              expected.lowercased() == current.revision.sha256.lowercased() else {
            throw CLIError.usage(
                "Metadata revision mismatch. Run metadata-read and use its current metadata_sha256."
            )
        }
        return current.revision
    }

    private static func writeMetadataReport(
        vault: RegisteredVault,
        path: String,
        source: NoteDocument,
        metadata: NoteMetadataSnapshot?
    ) throws {
        let report: [String: Any] = [
            "vault_id": vault.id.uuidString,
            "vault_name": vault.name,
            "relative_path": path,
            "source_sha256": source.fingerprint.sha256,
            "metadata_sha256": metadata?.revision.sha256 ?? NSNull(),
            "fields": (metadata?.record.fields ?? [:]).mapValues(metadataJSONObject),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        write(String(decoding: data, as: UTF8.self) + "\n")
    }

    private static func metadataValue(from data: Data) throws -> YAMLValue {
        let object = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        )
        return try metadataValue(fromJSONObject: object)
    }

    private static func metadataValue(fromJSONObject object: Any) throws -> YAMLValue {
        switch object {
        case is NSNull:
            return .null
        case let value as String:
            return .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .boolean(value.boolValue)
            }
            let double = value.doubleValue
            if double.rounded() == double,
               double >= Double(Int.min), double <= Double(Int.max) {
                return .integer(value.intValue)
            }
            return .double(double)
        case let values as [Any]:
            return .array(try values.map(metadataValue(fromJSONObject:)))
        case let values as [String: Any]:
            return .object(try values.mapValues(metadataValue(fromJSONObject:)))
        default:
            throw CLIError.usage("Metadata values must be valid JSON values.")
        }
    }

    private static func metadataJSONObject(_ value: YAMLValue) -> Any {
        switch value {
        case .string(let value): value
        case .integer(let value): value
        case .double(let value): value
        case .boolean(let value): value
        case .null: NSNull()
        case .array(let values): values.map(metadataJSONObject)
        case .object(let values): values.mapValues(metadataJSONObject)
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
        if let warning = outcome.portableMetadataRecoveryWarning {
            writeError(
                "scholium: warning: The source operation committed, but portable Note metadata recovery is incomplete. Inspect Metadata before continuing; do not repeat the mutation. \(warning)\n"
            )
        }
    }
}
