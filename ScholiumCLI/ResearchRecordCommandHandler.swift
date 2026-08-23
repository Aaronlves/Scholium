import Foundation
import ScholiumContracts

extension ScholiumCLI {
    static func runRecord(
        _ arguments: [String],
        context: CLIContext
    ) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage(
                "Usage: scholium record <list|read> ... [--triptych <uuid-or-unique-name>]"
            )
        }
        let assignment = try await context.selectedTriptych(
            selector: option("--triptych", in: arguments)
        )
        let handle = try await context.handle(for: assignment)
        let research = try completeRecordSnapshot(
            try await handle.research.snapshot()
        )

        switch subcommand {
        case "list":
            try runRecordList(
                arguments,
                assignment: assignment,
                discovery: try await handle.discovery.snapshot(),
                research: research
            )
        case "read":
            try runRecordRead(
                arguments,
                assignment: assignment,
                research: research
            )
        default:
            throw CLIError.usage(
                "Unknown Record command '\(subcommand)'. Run 'scholium help record'."
            )
        }
    }

    private static func runRecordList(
        _ arguments: [String],
        assignment: TriptychAssignment,
        discovery: WorkspaceDiscoverySnapshot,
        research: WorkspaceResearchSnapshot
    ) throws {
        guard let noteText = option("--note", in: arguments),
              let noteID = UUID(uuidString: noteText) else {
            throw CLIError.usage(
                "Usage: scholium record list --note <stable-note-uuid> [--triptych <selector>] [--format text|jsonl]"
            )
        }
        let isCurrentNote = discovery.catalog.notes.contains { note in
            note.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == noteID
        }
        let isRecordParticipant = research.finishedResearchRecords.contains { record in
            record.participatingNotes.contains { $0.noteID == noteID }
        }
        guard isCurrentNote || isRecordParticipant else {
            throw CLIError.noteNotFound(noteID.uuidString.lowercased())
        }

        let records = research.finishedResearchRecords
            .filter { record in
                record.participatingNotes.contains { $0.noteID == noteID }
            }
            .sorted(by: ordersRecords)
        let entries = try records.map { record in
            RecordListEntry(
                record: record,
                fingerprint: try requiredRecordFingerprint(
                    record.id,
                    research: research
                )
            )
        }
        let format = option("--format", in: arguments) ?? "text"
        switch format {
        case "jsonl":
            let encoder = recordJSONEncoder()
            let summary = RecordListSummary(
                triptychID: assignment.id,
                noteID: noteID,
                recordCount: entries.count,
                sourceManifestHash: research.finishedResearchRecordSourceManifestHash
            )
            write(String(decoding: try encoder.encode(summary), as: UTF8.self) + "\n")
            for entry in entries {
                write(String(decoding: try encoder.encode(entry), as: UTF8.self) + "\n")
            }
        case "text":
            if entries.isEmpty {
                write("No finished Research Records participate in Note \(noteID.uuidString.lowercased()).\n")
                return
            }
            write(
                "Research Records for Note \(noteID.uuidString.lowercased()) "
                    + "count=\(entries.count) manifest=\(research.finishedResearchRecordSourceManifestHash)\n"
            )
            for entry in entries {
                let action = entry.actionID?.rawValue ?? ResearchActionID.discuss.rawValue
                let method = entry.methodName ?? "none"
                write(
                    "\(entry.recordID.uuidString.lowercased()) "
                        + "\(entry.finishedAt.formatted(.iso8601)) \(entry.title)\n"
                )
                write(
                    "  action=\(action) method=\(method) "
                        + "fingerprint=\(entry.recordFingerprint.sha256):"
                        + "\(entry.recordFingerprint.byteCount)\n"
                )
            }
        default:
            throw CLIError.usage("Record list supports --format text or jsonl.")
        }
    }

    private static func runRecordRead(
        _ arguments: [String],
        assignment: TriptychAssignment,
        research: WorkspaceResearchSnapshot
    ) throws {
        guard arguments.count >= 2,
              let recordID = UUID(uuidString: arguments[1]) else {
            throw CLIError.usage(
                "Usage: scholium record read <record-uuid> [--triptych <selector>] [--format json]"
            )
        }
        guard let record = research.finishedResearchRecords.first(where: {
            $0.id == recordID
        }) else {
            throw CLIError.recordNotFound(recordID)
        }
        let format = option("--format", in: arguments) ?? "json"
        guard format == "json" else {
            throw CLIError.usage("Record read supports --format json.")
        }
        let envelope = try RecordReadEnvelope(
            triptychID: assignment.id,
            record: record,
            fingerprint: requiredRecordFingerprint(
                record.id,
                research: research
            )
        )
        write(
            String(
                decoding: try recordJSONEncoder(prettyPrinted: true).encode(envelope),
                as: UTF8.self
            ) + "\n"
        )
    }

    private static func completeRecordSnapshot(
        _ snapshot: WorkspaceResearchSnapshot
    ) throws -> WorkspaceResearchSnapshot {
        guard snapshot.finishedResearchRecordProjectionIsComplete else {
            throw CLIError.unavailable(
                "Research Records are unavailable because the portable Record corpus could not be read completely."
            )
        }
        return snapshot
    }

    private static func requiredRecordFingerprint(
        _ id: UUID,
        research: WorkspaceResearchSnapshot
    ) throws -> DocumentFingerprint {
        guard let fingerprint = research.finishedResearchRecordFingerprints[id] else {
            throw CLIError.unavailable(
                "Research Record \(id.uuidString.lowercased()) has no exact portable-byte fingerprint in the current complete projection."
            )
        }
        return fingerprint
    }

    private static func ordersRecords(
        _ lhs: PortableResearchRecord,
        _ rhs: PortableResearchRecord
    ) -> Bool {
        if lhs.finishedAt != rhs.finishedAt { return lhs.finishedAt > rhs.finishedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func recordJSONEncoder(
        prettyPrinted: Bool = false
    ) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private struct RecordListSummary: Encodable {
        let type = "record_list_summary"
        let schemaVersion = 1
        let triptychID: UUID
        let noteID: UUID
        let recordCount: Int
        let sourceManifestHash: String
    }

    private struct RecordParticipant: Encodable {
        let noteID: UUID
        let vaultID: UUID
        let relativePath: String
        let role: ResearchActionTargetRole
        let title: String

        init(_ participant: PortableResearchNoteRevision) {
            noteID = participant.noteID
            vaultID = participant.note.vaultID
            relativePath = participant.note.relativePath
            role = participant.role
            title = participant.title
        }
    }

    private struct RecordListEntry: Encodable {
        let type = "research_record_summary"
        let schemaVersion = 1
        let recordID: UUID
        let recordFingerprint: DocumentFingerprint
        let title: String
        let kind: PortableResearchRecordKind
        let actionID: ResearchActionID?
        let methodName: String?
        let primaryNoteID: UUID?
        let participatingNotes: [RecordParticipant]
        let startedAt: Date
        let finishedAt: Date

        init(
            record: PortableResearchRecord,
            fingerprint: DocumentFingerprint
        ) {
            recordID = record.id
            recordFingerprint = fingerprint
            title = record.title.value
            kind = record.kind
            actionID = record.action?.actionID
            methodName = record.method?.displayName
            primaryNoteID = record.primaryNoteID
            participatingNotes = record.participatingNotes.map(RecordParticipant.init)
            startedAt = record.startedAt
            finishedAt = record.finishedAt
        }
    }

    private struct RecordReadEnvelope: Encodable {
        let type = "research_record"
        let schemaVersion = 1
        let triptychID: UUID
        let recordFingerprint: DocumentFingerprint
        let record: PortableResearchRecord

        init(
            triptychID: UUID,
            record: PortableResearchRecord,
            fingerprint: DocumentFingerprint
        ) throws {
            guard record.triptychID == triptychID else {
                throw CLIError.recordNotFound(record.id)
            }
            self.triptychID = triptychID
            recordFingerprint = fingerprint
            self.record = record
        }
    }
}
