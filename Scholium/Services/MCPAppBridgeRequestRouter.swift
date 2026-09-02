import Foundation
import ScholiumApplication
import ScholiumContracts

/// Translates one authenticated local bridge request into the running App's
/// existing workspace owners. It owns no workspace, source, Search, graph, or
/// mutation state of its own.
@MainActor
final class MCPAppBridgeRequestRouter {
    typealias EditorFlusher = @MainActor @Sendable (UUID) async throws -> Void
    typealias OpenTriptychs = @MainActor @Sendable () -> [TriptychAssignment]

    private static let maximumReadResponseByteCount = 1_024 * 1_024

    private let runtime: WorkspaceRuntime
    private let flushEditors: EditorFlusher
    private let openTriptychs: OpenTriptychs

    init(
        runtime: WorkspaceRuntime,
        flushEditors: @escaping EditorFlusher,
        openTriptychs: @escaping OpenTriptychs
    ) {
        self.runtime = runtime
        self.flushEditors = flushEditors
        self.openTriptychs = openTriptychs
    }

    func handle(_ request: ScholiumMCPBridgeRequest) async
        -> ScholiumMCPBridgeResponse
    {
        do {
            return try ScholiumMCPBridgeResponse(
                requestID: request.requestID,
                result: try await execute(request)
            )
        } catch let failure as ScholiumMCPFailure {
            return try! ScholiumMCPBridgeResponse(
                requestID: request.requestID,
                error: failure
            )
        } catch {
            return try! ScholiumMCPBridgeResponse(
                requestID: request.requestID,
                error: Self.failure(for: error)
            )
        }
    }

    private func execute(_ request: ScholiumMCPBridgeRequest) async throws
        -> MCPJSONValue
    {
        switch request.tool {
        case .workspaceStatus:
            return try await workspaceStatus(request.arguments)
        case .search:
            return try await search(request.arguments)
        case .readNote:
            return try await readNote(request.arguments)
        case .readRecord:
            return try await readRecord(request.arguments)
        case .listLinks:
            return try await listLinks(request.arguments)
        case .createNote:
            return try await createNote(request.arguments)
        case .updateNote:
            return try await updateNote(request.arguments)
        case .trashNote:
            return try await trashNote(request.arguments)
        case .recordProgress:
            return try await recordProgress(request.arguments)
        case .correctRecordStep:
            return try await correctRecordStep(request.arguments)
        }
    }

    private func workspaceStatus(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(arguments, keys: ["triptych_id"])
        let assignments = openTriptychs()
            .sorted { $0.id.uuidString < $1.id.uuidString }
        guard !assignments.isEmpty else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "Scholium has no open Triptych.",
                recovery: "Open a Triptych in the Scholium App, then call workspace status again."
            )
        }
        let requestedID = try optionalUUID(arguments["triptych_id"], name: "triptych_id")
        if requestedID == nil, assignments.count > 1 {
            return ok([
                "current": .bool(false),
                "selection_required": .bool(true),
                "triptychs": .array(assignments.map { assignment in
                    .object([
                        "triptych_id": .string(assignment.id.uuidString.lowercased()),
                        "name": .string(assignment.triptych.name),
                    ])
                }),
            ])
        }
        let selectedID = requestedID ?? assignments[0].id
        guard assignments.contains(where: { $0.id == selectedID }) else {
            throw ScholiumMCPFailure(
                code: .notFound,
                message: "The requested Triptych is not open in Scholium.",
                recovery: "Use one of the Triptych IDs returned by workspace status."
            )
        }
        let snapshot = try await currentSnapshot(triptychID: selectedID)
        return try await statusValue(snapshot)
    }

    private func search(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: [
                "triptych_id", "query", "providers", "roles", "note_limit",
                "note_offset", "record_limit", "record_offset",
            ]
        )
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let query = try requiredString(arguments["query"], name: "query")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              query.utf16.count <= SearchContract.maximumQueryUTF16Count else {
            throw invalid("query", "Provide one nonempty bounded Search query.")
        }
        let noteLimit = try boundedInteger(
            arguments["note_limit"],
            name: "note_limit",
            default: 20,
            range: 1 ... 100
        )
        let noteOffset = try boundedInteger(
            arguments["note_offset"],
            name: "note_offset",
            default: 0,
            range: 0 ... Int.max
        )
        let recordLimit = try boundedInteger(
            arguments["record_limit"],
            name: "record_limit",
            default: 20,
            range: 1 ... 100
        )
        let recordOffset = try boundedInteger(
            arguments["record_offset"],
            name: "record_offset",
            default: 0,
            range: 0 ... Int.max
        )
        let providerSelection = try searchProviderSelection(arguments["providers"])
        let snapshot = try await currentSnapshot(triptychID: triptychID)
        let includedVaultIDs = try roleVaultIDs(
            arguments["roles"],
            snapshot: snapshot
        )
        let handle = try await runtime.openWorkspace(id: triptychID)
        let response = try await handle.discovery.unifiedSearch(UnifiedSearchRequest(
            query: query,
            providerSelection: providerSelection,
            presentationScope: .triptych,
            executionScope: .triptych,
            noteLimit: noteLimit,
            noteOffset: noteOffset,
            recordLimit: recordLimit,
            recordOffset: recordOffset,
            includedVaultIDs: includedVaultIDs
        ))
        if let diagnostic = response.notes?.diagnostics.first
            ?? response.records?.diagnostics.first {
            throw invalid("query", diagnostic.message)
        }
        let noteGroup = response.notes.map { noteResponse -> MCPJSONValue in
            let results = noteResponse.results.compactMap { result -> MCPJSONValue? in
            guard case .note(let note) = result else { return nil }
            var value: [String: MCPJSONValue] = [
                "note_id": note.stableNoteID.map(MCPJSONValue.string) ?? .null,
                "role": .string(Self.externalRole(note.vaultRole)),
                "relative_path": .string(note.relativePath),
                "title": .string(note.title),
                "fingerprint": fingerprintValue(note.fingerprint),
                "match_reason": .string(note.matchedField.rawValue),
                "rank_reason": .string(note.rankReason.rawValue),
                "snippet": .string(note.snippet),
            ]
            if let range = note.sourceRange {
                value["source_locator"] = .object([
                    "line": .integer(range.line),
                    "column": .integer(range.column),
                    "end_line": .integer(range.endLine),
                    "end_column": .integer(range.endColumn),
                ])
            } else {
                value["source_locator"] = .null
            }
            return .object(value)
            }
            return .object([
                "freshness": .string(noteResponse.freshnessToken.rawValue),
                "offset": .integer(noteOffset),
                "limit": .integer(noteLimit),
                "total": noteResponse.totalResultCount.map(MCPJSONValue.integer) ?? .null,
                "has_more": .bool(noteResponse.hasMore),
                "results": .array(results),
            ])
        } ?? .null
        let recordGroup = response.records.map { recordResponse -> MCPJSONValue in
            .object([
                "generation": recordGenerationValue(recordResponse.generation),
                "offset": .integer(recordResponse.offset),
                "limit": .integer(recordResponse.limit),
                "total": .integer(recordResponse.totalResultCount),
                "has_more": .bool(recordResponse.hasMore),
                "isolated_issue_count": .integer(recordResponse.isolatedIssues.count),
                "results": .array(recordResponse.results.map { result in
                    .object([
                        "record_id": .string(result.recordID.uuidString.lowercased()),
                        "question": .string(result.question),
                        "last_substantive_at": .string(Self.timestamp(result.lastSubstantiveAt)),
                        "fingerprint": fingerprintValue(result.fingerprint),
                        "matched_field": .string(result.matchedField.rawValue),
                        "matched_step_id": result.matchedStepID.map {
                            .string($0.uuidString.lowercased())
                        } ?? .null,
                        "rank_reason": .string(result.rankReason.rawValue),
                        "snippet": .string(result.snippet),
                    ])
                }),
            ])
        } ?? .null
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "query": .string(query),
            "notes": noteGroup,
            "records": recordGroup,
        ])
    }

    private func readNote(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: ["triptych_id", "note_id", "start_line", "line_count"]
        )
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let noteID = try requiredUUID(arguments["note_id"], name: "note_id")
        let startLine = try boundedInteger(
            arguments["start_line"],
            name: "start_line",
            default: 1,
            range: 1 ... Int.max
        )
        let lineCount = try boundedInteger(
            arguments["line_count"],
            name: "line_count",
            default: 200,
            range: 1 ... 1_000
        )
        let snapshot = try await currentSnapshot(triptychID: triptychID)
        let note = try resolveNote(noteID, snapshot: snapshot)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let document = try await handle.documents.load(note.id)
        let slice = try Self.exactLineSlice(
            document.sourceBytes,
            startLine: startLine,
            requestedLineCount: lineCount
        )
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "note_id": .string(noteID.uuidString.lowercased()),
            "role": .string(Self.externalRole(note.vaultRole)),
            "relative_path": .string(note.id.relativePath),
            "fingerprint": fingerprintValue(document.fingerprint),
            "start_line": .integer(startLine),
            "line_count": .integer(slice.lineCount),
            "source": .string(slice.source),
            "complete": .bool(slice.nextLine == nil),
            "next_line": slice.nextLine.map(MCPJSONValue.integer) ?? .null,
        ])
    }

    private func readRecord(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: ["triptych_id", "record_id", "step_offset", "step_limit"]
        )
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let recordID = try requiredUUID(arguments["record_id"], name: "record_id")
        let offset = try boundedInteger(
            arguments["step_offset"],
            name: "step_offset",
            default: 0,
            range: 0 ... Int.max
        )
        let limit = try boundedInteger(
            arguments["step_limit"],
            name: "step_limit",
            default: 20,
            range: 1 ... 100
        )
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let revision = try await handle.agentCollaboration.researchRecord(id: recordID)
        let steps = Array(revision.record.steps.dropFirst(offset).prefix(limit))
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "record_id": .string(recordID.uuidString.lowercased()),
            "question": .string(revision.record.question),
            "fingerprint": fingerprintValue(revision.fingerprint),
            "step_offset": .integer(offset),
            "step_limit": .integer(limit),
            "total_steps": .integer(revision.record.steps.count),
            "has_more": .bool(offset + steps.count < revision.record.steps.count),
            "steps": .array(steps.map(recordStepValue)),
        ])
    }

    private func listLinks(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: ["triptych_id", "note_id", "direction", "limit", "offset"]
        )
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let noteID = try requiredUUID(arguments["note_id"], name: "note_id")
        let rawDirection = try requiredString(arguments["direction"], name: "direction")
        guard let direction = WorkspaceLinkDirection(rawValue: rawDirection) else {
            throw invalid("direction", "Use incoming or outgoing.")
        }
        let limit = try boundedInteger(
            arguments["limit"],
            name: "limit",
            default: 100,
            range: 1 ... 100
        )
        let offset = try boundedInteger(
            arguments["offset"],
            name: "offset",
            default: 0,
            range: 0 ... Int.max
        )
        let snapshot = try await currentSnapshot(triptychID: triptychID)
        let note = try resolveNote(noteID, snapshot: snapshot)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let edges = try await handle.discovery.links(for: note.id, direction: direction)
        let page = Array(edges.dropFirst(min(offset, edges.count)).prefix(limit))
        var documents: [VaultQualifiedNoteID: NoteDocument] = [:]
        var values: [MCPJSONValue] = []
        for edge in page {
            let sourceDocument: NoteDocument
            if let existing = documents[edge.source] {
                sourceDocument = existing
            } else {
                sourceDocument = try await handle.documents.load(edge.source)
                documents[edge.source] = sourceDocument
            }
            let occurrenceMarkup = Self.exactSubstring(
                sourceDocument.sourceBytes,
                range: edge.occurrence.span.utf8Range
            )
            let linkMarkup = Self.exactSubstring(
                sourceDocument.sourceBytes,
                range: edge.occurrence.linkSpan.utf8Range
            )
            let destinationNote = edge.destination?.note
            values.append(.object([
                "occurrence_direction": .string("outgoing"),
                "source_note_id": stableIdentity(
                    for: edge.source,
                    snapshot: snapshot
                ).map { .string($0.uuidString.lowercased()) } ?? .null,
                "destination_note_id": edge.destination.flatMap {
                    stableIdentity(for: $0.note, snapshot: snapshot)
                }.map { .string($0.uuidString.lowercased()) } ?? .null,
                "source_role": .string(Self.externalRole(
                    snapshot.document(id: edge.source)?.vaultRole ?? .other
                )),
                "source_relative_path": .string(edge.source.relativePath),
                "destination_role": destinationNote.map { destination in
                    .string(Self.externalRole(snapshot.document(id: destination)?.vaultRole ?? .other))
                } ?? .null,
                "destination_relative_path": destinationNote.map { .string($0.relativePath) } ?? .null,
                "occurrence_markup": .string(occurrenceMarkup),
                "link_markup": .string(linkMarkup),
                "annotation_markup": edge.occurrence.annotation.map { annotation in
                    .string(Self.exactSubstring(sourceDocument.sourceBytes, range: annotation.span.utf8Range))
                } ?? .null,
                "annotation_text": edge.occurrence.annotation.map { .string($0.text) } ?? .null,
                "authored_target": .string(edge.occurrence.target),
                "local_context": .string(Self.localContext(
                    in: sourceDocument.rawContent,
                    containing: edge.occurrence.span
                )),
                "source_fingerprint": fingerprintValue(sourceDocument.fingerprint),
                "source_locator": Self.locatorValue(edge.occurrence.span),
                "link_locator": Self.locatorValue(edge.occurrence.linkSpan),
                "annotation_locator": edge.occurrence.annotation.map {
                    Self.locatorValue($0.contentSpan)
                } ?? .null,
            ]))
        }
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "note_id": .string(noteID.uuidString.lowercased()),
            "direction": .string(rawDirection),
            "graph_generation": snapshot.discovery.catalog.graph.map {
                .integer($0.generation)
            } ?? .null,
            "offset": .integer(offset),
            "limit": .integer(limit),
            "has_more": .bool(offset + page.count < edges.count),
            "links": .array(values),
        ])
    }

    private func createNote(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: [
                "triptych_id", "role", "relative_path", "body", "summary",
                "keywords",
            ]
        )
        let triptychID = try requiredUUID(
            arguments["triptych_id"],
            name: "triptych_id"
        )
        let role = try requiredExternalRole(arguments["role"])
        let relativePath = try requiredString(
            arguments["relative_path"],
            name: "relative_path"
        )
        guard relativePath.utf8.count <= 4_096,
              relativePath.lowercased().hasSuffix(".md") else {
            throw invalid(
                "relative_path",
                "Provide one bounded exact vault-relative .md path."
            )
        }
        let body = try requiredStringAllowingEmpty(
            arguments["body"],
            name: "body"
        )
        let summary = try optionalString(arguments["summary"], name: "summary")
        let keywords = try stringArray(
            arguments["keywords"],
            name: "keywords",
            default: []
        )
        let snapshot = try await currentSnapshot(triptychID: triptychID)
        guard let vault = snapshot.vaults.first(where: {
            $0.vault.role == role
        }) else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "The selected role vault is unavailable in this Triptych.",
                recovery: "Inspect workspace status and select one reported role."
            )
        }
        let noteID = UUID()
        let request: ManagedNoteCreationRequest
        do {
            request = try ManagedNoteCreationRequest(
                vaultID: vault.vault.id,
                destination: .exact(relativePath: relativePath),
                body: body,
                authoredYAML: try AuthoredNoteYAML(
                    summary: summary,
                    keywords: keywords
                ),
                analysisMetadata: nil,
                authority: .mcp(reservedIdentity: noteID)
            )
        } catch {
            throw invalid(
                "body",
                error.localizedDescription
            )
        }
        let handle = try await runtime.openWorkspace(id: triptychID)
        let result = try await handle.agentCollaboration.createNote(request)
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "change_id": .string(result.change.id.uuidString.lowercased()),
            "note_id": .string(result.noteID.uuidString.lowercased()),
            "role": .string(Self.externalRole(result.role)),
            "relative_path": .string(result.relativePath),
            "fingerprint": fingerprintValue(result.fingerprint),
        ])
    }

    private func updateNote(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: [
                "triptych_id", "note_id", "expected_fingerprint", "mode",
                "content",
            ]
        )
        let triptychID = try requiredUUID(
            arguments["triptych_id"],
            name: "triptych_id"
        )
        let noteID = try requiredUUID(arguments["note_id"], name: "note_id")
        let expected = try requiredFingerprint(arguments["expected_fingerprint"])
        let rawMode = try requiredString(arguments["mode"], name: "mode")
        guard let mode = AgentNoteUpdateMode(rawValue: rawMode) else {
            throw invalid("mode", "Use body or source.")
        }
        let content = try requiredStringAllowingEmpty(
            arguments["content"],
            name: "content"
        )
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let result = try await handle.agentCollaboration.updateNote(
            noteID: noteID,
            expectedFingerprint: expected,
            mode: mode,
            content: content
        )
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "change_id": .string(result.change.id.uuidString.lowercased()),
            "note_id": .string(result.noteID.uuidString.lowercased()),
            "relative_path": .string(result.relativePath),
            "before_fingerprint": fingerprintValue(result.beforeFingerprint),
            "after_fingerprint": fingerprintValue(result.afterFingerprint),
            "readback_verified": .bool(result.readbackVerified),
        ])
    }

    private func trashNote(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: ["triptych_id", "note_id", "expected_fingerprint"]
        )
        let triptychID = try requiredUUID(
            arguments["triptych_id"],
            name: "triptych_id"
        )
        let noteID = try requiredUUID(arguments["note_id"], name: "note_id")
        let expected = try requiredFingerprint(arguments["expected_fingerprint"])
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let result = try await handle.agentCollaboration.trashNote(
            noteID: noteID,
            expectedFingerprint: expected
        )
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "change_id": .string(result.change.id.uuidString.lowercased()),
            "note_id": .string(result.noteID.uuidString.lowercased()),
            "original_location": .object([
                "role": .string(Self.externalRole(result.change.role)),
                "relative_path": .string(result.originalRelativePath),
            ]),
            "moved_to_system_trash": .bool(true),
        ])
    }

    private func recordProgress(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: [
                "triptych_id", "target", "agent_label", "body_markdown",
                "revises_step_ids", "note_references",
            ]
        )
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let target = try recordProgressTarget(arguments["target"])
        let submitter: ResearchRecordSubmitter
        do {
            submitter = try ResearchRecordSubmitter(displayName: requiredString(
                arguments["agent_label"],
                name: "agent_label"
            ))
        } catch {
            throw invalid("agent_label", error.localizedDescription)
        }
        let body = try requiredString(arguments["body_markdown"], name: "body_markdown")
        let revises = try uuidArray(arguments["revises_step_ids"], name: "revises_step_ids")
        let references = try noteReferences(arguments["note_references"])
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let result = try await handle.agentCollaboration.recordProgress(.init(
            target: target,
            submittedBy: submitter,
            bodyMarkdown: body,
            revisesStepIDs: revises,
            noteReferences: references
        ))
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "branch": .string(result.kind.rawValue),
            "record_id": .string(result.revision.id.uuidString.lowercased()),
            "step_id": .string(result.stepID.uuidString.lowercased()),
            "question": .string(result.revision.record.question),
            "fingerprint": fingerprintValue(result.revision.fingerprint),
        ])
    }

    private func correctRecordStep(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: [
                "triptych_id", "record_id", "step_id", "expected_fingerprint",
                "agent_label", "body_markdown", "revises_step_ids",
                "note_references",
            ]
        )
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let recordID = try requiredUUID(arguments["record_id"], name: "record_id")
        let stepID = try requiredUUID(arguments["step_id"], name: "step_id")
        let expected = try requiredFingerprint(arguments["expected_fingerprint"])
        let submitter: ResearchRecordSubmitter
        do {
            submitter = try ResearchRecordSubmitter(displayName: requiredString(
                arguments["agent_label"],
                name: "agent_label"
            ))
        } catch {
            throw invalid("agent_label", error.localizedDescription)
        }
        let body = try requiredString(arguments["body_markdown"], name: "body_markdown")
        let revises = try uuidArray(arguments["revises_step_ids"], name: "revises_step_ids")
        let references = try noteReferences(arguments["note_references"])
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let revision = try await handle.agentCollaboration.correctRecordStep(.init(
            recordID: recordID,
            stepID: stepID,
            expectedFingerprint: expected,
            submittedBy: submitter,
            bodyMarkdown: body,
            revisesStepIDs: revises,
            noteReferences: references
        ))
        guard let step = revision.record.steps.first(where: { $0.id == stepID }),
              let correction = step.corrections.last else {
            throw ScholiumMCPFailure(
                code: .internalError,
                message: "The stored correction could not be confirmed.",
                recovery: "Read the Record again before any further correction."
            )
        }
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "record_id": .string(recordID.uuidString.lowercased()),
            "step_id": .string(stepID.uuidString.lowercased()),
            "correction_id": .string(correction.id.uuidString.lowercased()),
            "corrected_at": .string(Self.timestamp(correction.correctedAt)),
            "body_markdown": .string(step.currentBodyMarkdown),
            "fingerprint": fingerprintValue(revision.fingerprint),
        ])
    }

    private func currentSnapshot(triptychID: UUID) async throws
        -> WorkspaceSnapshot
    {
        guard openTriptychs().contains(where: { $0.id == triptychID }) else {
            throw ScholiumMCPFailure(
                code: .notFound,
                message: "The requested Triptych is not open in Scholium.",
                recovery: "Call workspace status and select one currently open Triptych."
            )
        }
        try await flushEditors(triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let snapshot = try await handle.discovery.refresh()
        guard snapshot.phase.isComplete,
              let searchGeneration = snapshot.discovery.searchGeneration else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "Scholium has not completed the current Triptych source and Search generation.",
                recovery: "Wait for the App to finish loading, then call workspace status again."
            )
        }
        let sourceHash = Self.sourceManifestHash(snapshot)
        guard searchGeneration.sourceManifestHash == sourceHash,
              snapshot.discovery.catalog.graph?.sourceManifestHash == sourceHash else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "Scholium source, Search, and link generations are not yet coherent.",
                recovery: "Refresh the Triptych in the App, then call workspace status again."
            )
        }
        return snapshot
    }

    private func statusValue(_ snapshot: WorkspaceSnapshot) async throws -> MCPJSONValue {
        let sourceHash = Self.sourceManifestHash(snapshot)
        let handle = try await runtime.openWorkspace(id: snapshot.triptych.id)
        let recordGeneration = try await handle.discovery.unifiedSearch(.init(
            query: "",
            providerSelection: .records,
            presentationScope: .triptych,
            executionScope: .triptych,
            noteLimit: 1,
            recordLimit: 1
        )).records?.generation
        return ok([
            "current": .bool(true),
            "selection_required": .bool(false),
            "triptych_id": .string(snapshot.triptych.id.uuidString.lowercased()),
            "name": .string(snapshot.triptych.name),
            "source_generation": .object([
                "manifest_sha256": .string(sourceHash),
                "note_count": .integer(snapshot.vaults.flatMap(\.documents).count),
            ]),
            "search_generation": snapshot.discovery.searchGeneration.map {
                .object([
                    "sequence": .integer($0.sequence),
                    "manifest_sha256": .string($0.sourceManifestHash),
                ])
            } ?? .null,
            "record_search_generation": recordGeneration.map(recordGenerationValue)
                ?? .null,
            "graph_generation": snapshot.discovery.catalog.graph.map {
                .object([
                    "sequence": .integer($0.generation),
                    "manifest_sha256": .string($0.sourceManifestHash),
                ])
            } ?? .null,
            "vaults": .array(snapshot.vaults.sorted {
                $0.slot.rawValue < $1.slot.rawValue
            }.map { vault in
                .object([
                    "role": .string(Self.externalRole(vault.vault.role)),
                    "vault_id": .string(vault.vault.id.uuidString.lowercased()),
                    "note_count": .integer(vault.documents.count),
                ])
            }),
        ])
    }

    private func roleVaultIDs(
        _ value: MCPJSONValue?,
        snapshot: WorkspaceSnapshot
    ) throws -> Set<UUID>? {
        guard let value else { return nil }
        guard let values = value.arrayValue, !values.isEmpty else {
            throw invalid("roles", "Provide one or more of analyses, topics, or works.")
        }
        let roles = try values.map { item -> String in
            guard let role = item.stringValue,
                  ["analyses", "topics", "works"].contains(role) else {
                throw invalid("roles", "Use only analyses, topics, or works.")
            }
            return role
        }
        guard Set(roles).count == roles.count else {
            throw invalid("roles", "Do not repeat a role.")
        }
        return Set(roles.compactMap { role in
            snapshot.vaults.first {
                Self.externalRole($0.vault.role) == role
            }?.vault.id
        })
    }

    private func searchProviderSelection(
        _ value: MCPJSONValue?
    ) throws -> SearchProviderSelection {
        guard let value else { return .all }
        guard let values = value.arrayValue, !values.isEmpty else {
            throw invalid("providers", "Provide note, record, or both.")
        }
        let providers = try values.map { item -> String in
            guard let provider = item.stringValue,
                  provider == "note" || provider == "record" else {
                throw invalid("providers", "Use only note and record.")
            }
            return provider
        }
        guard Set(providers).count == providers.count else {
            throw invalid("providers", "Do not repeat a provider.")
        }
        if providers.count == 2 { return .all }
        return providers[0] == "note" ? .notes : .records
    }

    private func recordProgressTarget(
        _ value: MCPJSONValue?
    ) throws -> ResearchRecordProgressTarget {
        guard let object = value?.objectValue,
              let kind = object["kind"]?.stringValue else {
            throw invalid("target", "Provide one new or existing target object.")
        }
        switch kind {
        case "new":
            guard Set(object.keys) == ["kind", "question"] else {
                throw invalid("target", "A new target requires only kind and question.")
            }
            return .new(question: try requiredString(
                object["question"],
                name: "target.question"
            ))
        case "existing":
            guard Set(object.keys).isSubset(of: [
                "kind", "record_id", "expected_fingerprint",
                "replacement_question",
            ]), object["record_id"] != nil,
               object["expected_fingerprint"] != nil else {
                throw invalid(
                    "target",
                    "An existing target requires record_id and expected_fingerprint."
                )
            }
            return .existing(
                recordID: try requiredUUID(
                    object["record_id"],
                    name: "target.record_id"
                ),
                expectedFingerprint: try requiredFingerprint(
                    object["expected_fingerprint"]
                ),
                replacementQuestion: try optionalNullableString(
                    object["replacement_question"],
                    name: "target.replacement_question"
                )
            )
        default:
            throw invalid("target.kind", "Use new or existing.")
        }
    }

    private func uuidArray(
        _ value: MCPJSONValue?,
        name: String
    ) throws -> [UUID] {
        guard let value else { return [] }
        guard let values = value.arrayValue else {
            throw invalid(name, "Provide an array of UUID strings.")
        }
        let result = try values.map { try requiredUUID($0, name: name) }
        guard Set(result).count == result.count else {
            throw invalid(name, "Do not repeat a UUID.")
        }
        return result
    }

    private func noteReferences(
        _ value: MCPJSONValue?
    ) throws -> [ResearchRecordNoteReference] {
        guard let value else { return [] }
        guard let values = value.arrayValue else {
            throw invalid("note_references", "Provide an array of Note reference objects.")
        }
        return try values.map { item in
            guard let object = item.objectValue,
                  Set(object.keys) == ["note_id", "relation", "revision"],
                  let rawRelation = object["relation"]?.stringValue,
                  let relation = ResearchRecordNoteRelation(rawValue: rawRelation) else {
                throw invalid(
                    "note_references",
                    "Each reference requires note_id, basis or modified relation, and revision."
                )
            }
            do {
                return try ResearchRecordNoteReference(
                    noteID: requiredUUID(object["note_id"], name: "note_id"),
                    relation: relation,
                    revision: requiredFingerprint(object["revision"])
                )
            } catch let failure as ScholiumMCPFailure {
                throw failure
            } catch {
                throw invalid("note_references", error.localizedDescription)
            }
        }
    }

    private func resolveNote(
        _ noteID: UUID,
        snapshot: WorkspaceSnapshot
    ) throws -> WorkspaceNoteSnapshot {
        let matches = snapshot.vaults.flatMap(\.documents).filter {
            $0.stableIdentity.resolvedID == noteID
        }
        guard !matches.isEmpty else {
            throw ScholiumMCPFailure(
                code: .notFound,
                message: "The stable Note identity is not present in the current Triptych.",
                recovery: "Search or inspect current links again and use the returned Note identity."
            )
        }
        guard matches.count == 1, let match = matches.first else {
            throw ScholiumMCPFailure(
                code: .ambiguous,
                message: "The stable Note identity is ambiguous in current portable state.",
                recovery: "Resolve the identity conflict in the Scholium App before retrying."
            )
        }
        return match
    }

    private func stableIdentity(
        for note: VaultQualifiedNoteID,
        snapshot: WorkspaceSnapshot
    ) -> UUID? {
        snapshot.document(id: note)?.stableIdentity.resolvedID
    }

    private func ok(_ fields: [String: MCPJSONValue]) -> MCPJSONValue {
        .object(fields.merging([
            "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion),
            "status": .string("ok"),
        ]) { current, _ in current })
    }

    private func requireOnly(
        _ arguments: [String: MCPJSONValue],
        keys: Set<String>
    ) throws {
        guard Set(arguments.keys).isSubset(of: keys) else {
            throw invalid(
                "arguments",
                "The request contains fields outside the published tool schema."
            )
        }
    }

    private func requiredString(
        _ value: MCPJSONValue?,
        name: String
    ) throws -> String {
        guard let value = value?.stringValue, !value.isEmpty else {
            throw invalid(name, "Provide a nonempty string.")
        }
        return value
    }

    private func requiredStringAllowingEmpty(
        _ value: MCPJSONValue?,
        name: String
    ) throws -> String {
        guard let value = value?.stringValue else {
            throw invalid(name, "Provide a string.")
        }
        return value
    }

    private func optionalString(
        _ value: MCPJSONValue?,
        name: String
    ) throws -> String? {
        guard let value else { return nil }
        guard let string = value.stringValue else {
            throw invalid(name, "Provide a string or omit this field.")
        }
        return string
    }

    private func optionalNullableString(
        _ value: MCPJSONValue?,
        name: String
    ) throws -> String? {
        guard let value else { return nil }
        if case .null = value { return nil }
        guard let string = value.stringValue else {
            throw invalid(name, "Provide a string, null, or omit this field.")
        }
        return string
    }

    private func stringArray(
        _ value: MCPJSONValue?,
        name: String,
        default defaultValue: [String]
    ) throws -> [String] {
        guard let value else { return defaultValue }
        guard let values = value.arrayValue else {
            throw invalid(name, "Provide an array of strings.")
        }
        let strings = try values.map { item -> String in
            guard let string = item.stringValue else {
                throw invalid(name, "Provide only strings.")
            }
            return string
        }
        guard Set(strings).count == strings.count else {
            throw invalid(name, "Do not repeat a value.")
        }
        return strings
    }

    private func requiredExternalRole(
        _ value: MCPJSONValue?
    ) throws -> VaultRole {
        guard let role = value?.stringValue else {
            throw invalid("role", "Use analyses, topics, or works.")
        }
        switch role {
        case "analyses": return .sourceCorpus
        case "topics": return .topicKnowledge
        case "works": return .draftProject
        default:
            throw invalid("role", "Use analyses, topics, or works.")
        }
    }

    private func requiredFingerprint(
        _ value: MCPJSONValue?
    ) throws -> DocumentFingerprint {
        guard let object = value?.objectValue,
              Set(object.keys) == ["sha256", "byte_count"],
              let sha256 = object["sha256"]?.stringValue,
              sha256.count == 64,
              sha256.unicodeScalars.allSatisfy({
                  (48 ... 57).contains($0.value) || (97 ... 102).contains($0.value)
              }),
              let byteCount = object["byte_count"]?.intValue,
              byteCount >= 0 else {
            throw invalid(
                "expected_fingerprint",
                "Provide canonical lowercase SHA-256 and a nonnegative byte_count."
            )
        }
        return DocumentFingerprint(sha256: sha256, byteCount: byteCount)
    }

    private func requiredUUID(
        _ value: MCPJSONValue?,
        name: String
    ) throws -> UUID {
        guard let string = value?.stringValue,
              let value = UUID(uuidString: string) else {
            throw invalid(name, "Provide a valid UUID string.")
        }
        return value
    }

    private func optionalUUID(
        _ value: MCPJSONValue?,
        name: String
    ) throws -> UUID? {
        guard let value else { return nil }
        return try requiredUUID(value, name: name)
    }

    private func boundedInteger(
        _ value: MCPJSONValue?,
        name: String,
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) throws -> Int {
        guard let value else { return defaultValue }
        guard let integer = value.intValue, range.contains(integer) else {
            throw invalid(name, "Provide a whole number from \(range.lowerBound) through \(range.upperBound).")
        }
        return integer
    }

    private func invalid(_ field: String, _ recovery: String)
        -> ScholiumMCPFailure
    {
        ScholiumMCPFailure(
            code: .invalidRequest,
            message: "The MCP field '\(field)' is invalid.",
            recovery: recovery
        )
    }

    private func fingerprintValue(_ fingerprint: DocumentFingerprint)
        -> MCPJSONValue
    {
        .object([
            "sha256": .string(fingerprint.sha256),
            "byte_count": .integer(fingerprint.byteCount),
        ])
    }

    private func recordGenerationValue(
        _ generation: RecordSearchGenerationID
    ) -> MCPJSONValue {
        .object([
            "sequence": .integer(generation.sequence),
            "manifest_sha256": .string(generation.sourceManifestHash),
            "record_count": .integer(generation.recordCount),
        ])
    }

    private func recordStepValue(_ step: ResearchRecordStep) -> MCPJSONValue {
        .object([
            "step_id": .string(step.id.uuidString.lowercased()),
            "recorded_at": .string(Self.timestamp(step.recordedAt)),
            "submitted_by": .string(step.submittedBy.displayName),
            "original_body_markdown": .string(step.bodyMarkdown),
            "body_markdown": .string(step.currentBodyMarkdown),
            "revises_step_ids": .array(step.currentRevisesStepIDs.map {
                .string($0.uuidString.lowercased())
            }),
            "note_references": .array(step.currentNoteReferences.map(
                noteReferenceValue
            )),
            "corrections": .array(step.corrections.map { correction in
                .object([
                    "correction_id": .string(correction.id.uuidString.lowercased()),
                    "corrected_at": .string(Self.timestamp(correction.correctedAt)),
                    "submitted_by": .string(correction.submittedBy.displayName),
                    "body_markdown": .string(correction.bodyMarkdown),
                    "revises_step_ids": .array(correction.revisesStepIDs.map {
                        .string($0.uuidString.lowercased())
                    }),
                    "note_references": .array(correction.noteReferences.map(
                        noteReferenceValue
                    )),
                ])
            }),
        ])
    }

    private func noteReferenceValue(
        _ reference: ResearchRecordNoteReference
    ) -> MCPJSONValue {
        .object([
            "note_id": .string(reference.noteID.uuidString.lowercased()),
            "relation": .string(reference.relation.rawValue),
            "revision": fingerprintValue(reference.revision),
        ])
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func sourceManifestHash(_ snapshot: WorkspaceSnapshot)
        -> String
    {
        SearchSourceManifest.hash(snapshot.vaults.flatMap { vault in
            vault.documents.map { note in
                SearchSourceManifestEntry(
                    vaultID: vault.vault.id,
                    relativePath: note.id.relativePath,
                    fingerprint: note.fingerprint
                )
            }
        })
    }

    private static func externalRole(_ role: VaultRole) -> String {
        switch role {
        case .sourceCorpus: "analyses"
        case .topicKnowledge: "topics"
        case .draftProject: "works"
        case .other: "unsupported"
        }
    }

    private static func exactSubstring(
        _ data: Data,
        range: Range<Int>
    ) -> String {
        guard range.lowerBound >= 0,
              range.upperBound <= data.count,
              range.lowerBound <= range.upperBound else { return "" }
        return String(decoding: data.subdata(in: range), as: UTF8.self)
    }

    private static func locatorValue(_ span: SourceSpan) -> MCPJSONValue {
        .object([
            "line": .integer(span.start.line),
            "column": .integer(span.start.utf16Column),
            "end_line": .integer(span.end.line),
            "end_column": .integer(span.end.utf16Column),
        ])
    }

    private static func localContext(in source: String, containing span: SourceSpan) -> String {
        let nsSource = source as NSString
        let start = min(max(0, span.utf16LowerBound), nsSource.length)
        let upper = min(max(start, span.utf16UpperBound), nsSource.length)
        let startLine = nsSource.lineRange(for: NSRange(location: start, length: 0))
        let endLocation = upper > start ? upper - 1 : upper
        let endLine = nsSource.lineRange(for: NSRange(location: endLocation, length: 0))
        let lower = startLine.location
        let end = NSMaxRange(endLine)
        return nsSource.substring(with: NSRange(location: lower, length: end - lower))
            .trimmingCharacters(in: .newlines)
    }

    private static func exactLineSlice(
        _ data: Data,
        startLine: Int,
        requestedLineCount: Int
    ) throws -> (source: String, lineCount: Int, nextLine: Int?) {
        if data.isEmpty {
            guard startLine == 1 else {
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "start_line is beyond the end of the Note.",
                    recovery: "Begin at source line 1."
                )
            }
            return ("", 0, nil)
        }
        var starts = [0]
        for (offset, byte) in data.enumerated()
            where byte == 0x0A && offset + 1 < data.count {
            starts.append(offset + 1)
        }
        guard startLine <= starts.count else {
            throw ScholiumMCPFailure(
                code: .invalidRequest,
                message: "start_line is beyond the end of the Note.",
                recovery: "Continue only from the next_line returned by the preceding read."
            )
        }
        let startIndex = startLine - 1
        var endIndex = startIndex
        let requestedEnd = min(starts.count, startIndex + requestedLineCount)
        while endIndex < requestedEnd {
            let candidateEnd = endIndex + 1 < starts.count
                ? starts[endIndex + 1]
                : data.count
            if candidateEnd - starts[startIndex] > maximumReadResponseByteCount,
               endIndex > startIndex {
                break
            }
            guard candidateEnd - starts[startIndex]
                    <= maximumReadResponseByteCount else {
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "One logical source line exceeds the bounded MCP response size.",
                    recovery: "Open the exact Note in Scholium or split the oversized source line."
                )
            }
            endIndex += 1
        }
        let endOffset = endIndex < starts.count ? starts[endIndex] : data.count
        let slice = data.subdata(in: starts[startIndex] ..< endOffset)
        let source = startIndex == 0
            ? NoteDocument.decodeUTF8PreservingBOM(slice)
            : String(data: slice, encoding: .utf8)
        guard let source else {
            throw ScholiumMCPFailure(
                code: .internalError,
                message: "The exact UTF-8 source slice could not be represented.",
                recovery: "Inspect the Note in Scholium before retrying."
            )
        }
        let nextLine = endIndex < starts.count ? endIndex + 1 : nil
        return (source, endIndex - startIndex, nextLine)
    }

    private static func failure(for error: Error) -> ScholiumMCPFailure {
        if let error = error as? ScholiumApplicationError {
            switch error {
            case .workspaceStillLoading, .noWorkspaceConfigured,
                 .incompleteTriptych, .critiqueStoreUnavailable:
                return ScholiumMCPFailure(
                    code: .workspaceNotReady,
                    message: "The requested current workspace state is unavailable.",
                    recovery: "Resolve the visible App state, then call workspace status again."
                )
            case .workspaceNotFound:
                return ScholiumMCPFailure(
                    code: .notFound,
                    message: "The requested Triptych is not open.",
                    recovery: "Call workspace status and select a current Triptych ID."
                )
            default: break
            }
        }
        if let error = error as? WorkspaceGraphQueryError {
            switch error {
            case .graphUnavailable:
                return ScholiumMCPFailure(
                    code: .workspaceNotReady,
                    message: "The current link generation is unavailable.",
                    recovery: "Refresh the Triptych and call workspace status again."
                )
            case .noteNotFound:
                return ScholiumMCPFailure(
                    code: .notFound,
                    message: "The requested Note is not in the current link generation.",
                    recovery: "Search or read the current Note identity again."
                )
            }
        }
        if let error = error as? VaultRepositoryError {
            switch error {
            case .fileDoesNotExist:
                return ScholiumMCPFailure(
                    code: .notFound,
                    message: "The requested Note is no longer present.",
                    recovery: "Refresh workspace status and resolve the current Note identity."
                )
            case .conflict:
                return ScholiumMCPFailure(
                    code: .conflict,
                    message: "The Note changed during the operation.",
                    recovery: "Read the current Note again before continuing."
                )
            default: break
            }
        }
        if let error = error as? AgentCollaborationError {
            switch error {
            case .noteNotFound:
                return ScholiumMCPFailure(
                    code: .notFound,
                    message: "The stable Note identity is not present.",
                    recovery: "Search or inspect current links again and use a current Note identity."
                )
            case .noteAmbiguous:
                return ScholiumMCPFailure(
                    code: .ambiguous,
                    message: "The stable Note identity is ambiguous.",
                    recovery: "Resolve the identity conflict in Scholium before retrying."
                )
            case .staleRevision:
                return ScholiumMCPFailure(
                    code: .staleRevision,
                    message: "The supplied Note fingerprint is no longer current.",
                    recovery: "Read the Note again, reconsider the requested change, and send a new request only if still authorized."
                )
            case .pathOccupied:
                return ScholiumMCPFailure(
                    code: .pathOccupied,
                    message: "The exact requested Note path is occupied.",
                    recovery: "Choose another exact .md path after inspecting current workspace state."
                )
            case .invalidRequest(let reason):
                return ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: reason,
                    recovery: "Correct the request without broadening its research scope."
                )
            case .changeConfirmationUncertain:
                return ScholiumMCPFailure(
                    code: .operationUncertain,
                    message: "Scholium could not confirm the final mutation evidence.",
                    recovery: "Do not retry automatically. Recheck status and the target identity, path, and fingerprint."
                )
            case .recordNotFound, .recordStepNotFound:
                return ScholiumMCPFailure(
                    code: .notFound,
                    message: error.localizedDescription,
                    recovery: "Search or read current Research Records again and use the returned identities."
                )
            case .staleRecordRevision:
                return ScholiumMCPFailure(
                    code: .staleRevision,
                    message: "The supplied Research Record fingerprint is no longer current.",
                    recovery: "Read the Record again, reconsider the step, and retry only if still authorized."
                )
            case .recordUnavailable(let reason):
                return ScholiumMCPFailure(
                    code: .workspaceNotReady,
                    message: reason,
                    recovery: "Inspect Research Records in Scholium before retrying."
                )
            case .recordOperationUncertain:
                return ScholiumMCPFailure(
                    code: .operationUncertain,
                    message: "Scholium could not confirm the Research Record write.",
                    recovery: "Do not retry automatically. Read the Record and compare its current fingerprint and steps."
                )
            }
        }
        if error is AgentChangeError {
            return ScholiumMCPFailure(
                code: .operationUncertain,
                message: "Scholium could not safely finalize the Agent Change evidence.",
                recovery: "Do not retry automatically. Inspect Agent Changes and current Note source in the App."
            )
        }
        if let error = error as? DocumentCreationError {
            switch error {
            case .portableIdentityAlreadyExists:
                return ScholiumMCPFailure(
                    code: .pathOccupied,
                    message: "The exact requested Note path is occupied.",
                    recovery: "Choose another exact .md path after inspecting current workspace state."
                )
            default:
                return ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: error.localizedDescription,
                    recovery: "Correct the authored body or YAML values and retry only the same explicit scope."
                )
            }
        }
        return ScholiumMCPFailure(
            code: .internalError,
            message: "Scholium could not complete the local MCP operation.",
            recovery: "Inspect the running App state, then begin again with workspace status."
        )
    }
}
