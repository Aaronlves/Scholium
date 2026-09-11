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

    private let displayWindows: @MainActor (UUID) -> [MCPJSONValue]
    private let displayNote: @MainActor (UUID, AgentNoteDisplayTarget, ScholiumMCPBridgeRequest) async throws -> Void
    private let runtime: WorkspaceRuntime
    private let flushEditors: EditorFlusher
    private let didConfirmChange: @MainActor (AgentChange) -> Void
    private let openTriptychs: OpenTriptychs

    init(
        runtime: WorkspaceRuntime,
        flushEditors: @escaping EditorFlusher,
        openTriptychs: @escaping OpenTriptychs,
        displayWindows: @escaping @MainActor (UUID) -> [MCPJSONValue] = { _ in [] },
        displayNote: @escaping @MainActor (UUID, AgentNoteDisplayTarget, ScholiumMCPBridgeRequest) async throws -> Void = { _, _, _ in
            throw WorkspaceStore.displayUnavailable()
        },
        didConfirmChange: @escaping @MainActor (AgentChange) -> Void = { _ in }
    ) {
        self.displayWindows = displayWindows
        self.displayNote = displayNote
        self.runtime = runtime
        self.flushEditors = flushEditors
        self.openTriptychs = openTriptychs
        self.didConfirmChange = didConfirmChange
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
        case .browse:
            return try await browse(request.arguments)
        case .search:
            return try await search(request.arguments)
        case .showNote:
            return try await showNote(request)
        case .readNote:
            return try await readNote(request.arguments)
        case .listAttachments:
            return try await listAttachments(request.arguments)
        case .readAttachment:
            return try await readAttachment(request.arguments)
        case .listLinks:
            return try await listLinks(request.arguments)
        case .createNote:
            return try await createNote(request.arguments)
        case .updateNote:
            return try await updateNote(request.arguments)
        case .updateMetadata, .updateAttachment:
            return try await updateRecord(request)
        case .moveNote:
            return try await moveNote(request.arguments)
        case .previewMove:
            return try await previewMove(request.arguments)
        case .listChanges:
            return try await listChanges(request.arguments)
        case .readChange:
            return try await readChange(request.arguments)
        case .undoChange:
            return try await undoChange(request.arguments)
        case .trashNote:
            return try await trashNote(request.arguments)
        case .capabilities, .configureSkill, .configureTool, .configureChat:
            throw invalid("conversation_token", "Capability management is available only inside an in-app Scholium Chat conversation.")
        }
    }

    private func showNote(_ request: ScholiumMCPBridgeRequest) async throws -> MCPJSONValue {
        let args = request.arguments
        try requireOnly(args, keys: ["triptych_id", "window_id", "note_id", "expected_fingerprint", "start_utf8", "end_utf8", "expected_text"])
        let triptych = try requiredUUID(args["triptych_id"], name: "triptych_id")
        let window = try requiredUUID(args["window_id"], name: "window_id")
        let note = try requiredUUID(args["note_id"], name: "note_id")
        try requireOpenTriptych(triptych)
        guard
            displayWindows(triptych).contains(where: {
                $0.objectValue?["window_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == window && $0.objectValue?["can_display"]?.boolValue == true
            })
        else { throw WorkspaceStore.displayUnavailable() }
        let handle = try await runtime.openWorkspace(id: triptych)
        let target = try await handle.agentCollaboration.displayTarget(
            noteID: note, expectedFingerprint: requiredFingerprint(args["expected_fingerprint"]),
            startUTF8: args["start_utf8"].map { try boundedInteger($0, name: "start_utf8", default: 0, range: 0...Int.max) },
            endUTF8: args["end_utf8"].map { try boundedInteger($0, name: "end_utf8", default: 1, range: 1...Int.max) },
            expectedText: args["expected_text"].map { try requiredStringAllowingEmpty($0, name: "expected_text") })
        try Task.checkCancellation()
        do { try await displayNote(window, target, request) } catch let error as AgentChatNoteMaterialError {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady, message: error.localizedDescription,
                recovery: "Keep the current editor intact, refresh the target source and request display again when the intended window is ready.")
        } catch is CancellationError {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady, message: "The display request was cancelled or superseded.",
                recovery: "Request display again only from the intended current window and conversation.")
        }
        return ok([
            "triptych_id": .string(triptych.uuidString.lowercased()), "window_id": .string(window.uuidString.lowercased()),
            "note_id": .string(note.uuidString.lowercased()), "relative_path": .string(target.note.relativePath),
            "fingerprint": fingerprintValue(target.fingerprint),
            "location_requested": .bool(target.range != nil), "line": target.range.map { .integer($0.line) } ?? .null, "activated": .bool(true),
        ])
    }

    private func listAttachments(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        try requireOnly(arguments, keys: ["triptych_id", "note_id", "offset", "limit", "expected_listing_fingerprint"])
        let triptych = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let note = try requiredUUID(arguments["note_id"], name: "note_id")
        let offset = try boundedInteger(arguments["offset"], name: "offset", default: 0, range: 0...Int.max)
        let limit = try boundedInteger(arguments["limit"], name: "limit", default: 20, range: 1...100)
        _ = try await currentSnapshot(triptychID: triptych)
        let handle = try await runtime.openWorkspace(id: triptych)
        let listing = try await handle.agentCollaboration.attachments(noteID: note)
        return try attachmentListingValue(
            listing, triptych: triptych, note: note, offset: offset, limit: limit,
            expected: arguments["expected_listing_fingerprint"])
    }

    private func attachmentListingValue(
        _ listing: AgentAttachmentListing, triptych: UUID, note: UUID,
        offset: Int = 0, limit: Int = 20, expected: MCPJSONValue? = nil
    ) throws -> MCPJSONValue {
        let fingerprint = try listing.fingerprint(triptychID: triptych, noteID: note)
        if let expected {
            guard try requiredFingerprint(expected) == fingerprint else {
                throw AgentCollaborationError.staleRevision(expected: try requiredFingerprint(expected), current: fingerprint)
            }
        } else if offset > 0 {
            throw invalid("expected_listing_fingerprint", "Continue with the exact listing fingerprint.")
        }
        let page = listing.attachments.dropFirst(min(offset, listing.attachments.count)).prefix(limit)
        return .object([
            "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"),
            "triptych_id": .string(triptych.uuidString.lowercased()), "note_id": .string(note.uuidString.lowercased()),
            "note_fingerprint": fingerprintValue(listing.noteFingerprint), "listing_fingerprint": fingerprintValue(fingerprint),
            "offset": .integer(offset), "total": .integer(listing.attachments.count), "has_more": .bool(offset < listing.attachments.count - page.count),
            "attachments": .array(
                page.map {
                    .object([
                        "attachment_id": .string($0.id.uuidString.lowercased()),
                        "filename": .string($0.filename), "relationship": .string($0.relationship.rawValue), "available": .bool($0.available),
                    ])
                }),
        ])
    }

    private func readAttachment(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: ["triptych_id", "note_id", "attachment_id", "expected_note_fingerprint", "expected_fingerprint", "mode", "page", "start_utf8", "max_utf8"])
        let triptych = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let note = try requiredUUID(arguments["note_id"], name: "note_id")
        let attachment = try requiredUUID(arguments["attachment_id"], name: "attachment_id")
        guard let mode = AgentAttachmentRead.Mode(rawValue: try requiredString(arguments["mode"], name: "mode")) else {
            throw invalid("mode", "Choose text or image.")
        }
        if mode == .image, arguments["start_utf8"] != nil || arguments["max_utf8"] != nil {
            throw invalid("mode", "Image mode accepts no text offsets or limits.")
        }
        let read = AgentAttachmentRead(
            mode: mode,
            page: try arguments["page"].map { try boundedInteger($0, name: "page", default: 1, range: 1...Int.max) },
            startUTF8: try boundedInteger(arguments["start_utf8"], name: "start_utf8", default: 0, range: 0...Int.max),
            maximumUTF8: try boundedInteger(arguments["max_utf8"], name: "max_utf8", default: 16_384, range: 1...65_536),
            expectedFingerprint: try arguments["expected_fingerprint"].map(requiredFingerprint))
        let expectedNote = try requiredFingerprint(arguments["expected_note_fingerprint"])
        _ = try await currentSnapshot(triptychID: triptych)
        let handle = try await runtime.openWorkspace(id: triptych)
        let content = try await handle.agentCollaboration.readAttachment(
            noteID: note, attachmentID: attachment, expectedNoteFingerprint: expectedNote, request: read)
        return .object([
            "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"),
            "triptych_id": .string(triptych.uuidString.lowercased()), "note_id": .string(note.uuidString.lowercased()),
            "attachment_id": .string(attachment.uuidString.lowercased()), "filename": .string(content.filename),
            "note_fingerprint": fingerprintValue(expectedNote),
            "fingerprint": fingerprintValue(content.fingerprint), "kind": .string(content.kind), "page": content.page.map(MCPJSONValue.integer) ?? .null,
            "total_pages": content.totalPages.map(MCPJSONValue.integer) ?? .null, "text": content.text.map(MCPJSONValue.string) ?? .null,
            "text_available": content.text.map { .bool(!$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } ?? .null,
            "start_utf8": .integer(content.startUTF8), "end_utf8": .integer(content.endUTF8), "total_utf8": .integer(content.totalUTF8),
            "has_more": .bool(content.endUTF8 < content.totalUTF8),
            "image": content.imagePNG.map {
                .object([
                    "mime_type": .string("image/png"), "data": .string($0.base64EncodedString()),
                    "pixel_width": .integer(content.pixelWidth ?? 0), "pixel_height": .integer(content.pixelHeight ?? 0),
                ])
            } ?? .null,
        ])
    }

    private func decodeMove(_ arguments: [String: MCPJSONValue]) throws -> (UUID, UUID, DocumentFingerprint, String, DocumentFingerprint) {
        try requireOnly(arguments, keys: ["triptych_id", "note_id", "expected_fingerprint", "relative_path", "expected_plan_fingerprint"])
        return (
            try requiredUUID(arguments["triptych_id"], name: "triptych_id"), try requiredUUID(arguments["note_id"], name: "note_id"),
            try requiredFingerprint(arguments["expected_fingerprint"]), try requiredString(arguments["relative_path"], name: "relative_path"),
            try requiredFingerprint(arguments["expected_plan_fingerprint"])
        )
    }

    private func moveEffectValue(_ effect: AgentNoteMoveEffect) -> MCPJSONValue {
        .object([
            "note_id": .string(effect.noteID.uuidString.lowercased()), "role": .string(Self.externalRole(effect.role)),
            "source_relative_path": .string(effect.source.relativePath), "relative_path": .string(effect.destination.relativePath),
            "before_fingerprint": fingerprintValue(effect.beforeFingerprint), "after_fingerprint": fingerprintValue(effect.afterFingerprint),
            "rewritten_occurrences": .integer(effect.rewrittenOccurrences),
        ])
    }

    private func moveNote(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        let (triptychID, noteID, expected, path, planFingerprint) = try decodeMove(arguments)
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let result = try await handle.agentCollaboration.moveNote(
            noteID: noteID, expectedFingerprint: expected, to: path, expectedPlanFingerprint: planFingerprint)
        didConfirmChange(result.change)
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()), "note_id": .string(noteID.uuidString.lowercased()),
            "change_id": .string(result.change.id.uuidString.lowercased()), "source_relative_path": .string(result.commit.movedNote.relativePath),
            "relative_path": .string(result.commit.destination.relativePath), "before_fingerprint": fingerprintValue(result.commit.previousRevision),
            "after_fingerprint": fingerprintValue(result.commit.committedRevision), "readback_verified": .bool(true),
            "effects": .array((result.change.moveEffects ?? []).map(moveEffectValue)),
            "derived_refresh_warning": result.derivedRefreshWarning.map(MCPJSONValue.string) ?? .null,
        ])
    }

    private func previewMove(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        try requireOnly(arguments, keys: ["triptych_id", "note_id", "expected_fingerprint", "relative_path", "offset", "limit", "expected_plan_fingerprint"])
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let noteID = try requiredUUID(arguments["note_id"], name: "note_id")
        let expected = try requiredFingerprint(arguments["expected_fingerprint"])
        let destination = try requiredString(arguments["relative_path"], name: "relative_path")
        let offset = try boundedInteger(arguments["offset"], name: "offset", default: 0, range: 0...Int.max)
        let limit = try boundedInteger(arguments["limit"], name: "limit", default: 20, range: 1...100)
        let planFingerprint = try arguments["expected_plan_fingerprint"].map { try requiredFingerprint($0) }
        guard offset == 0 || planFingerprint != nil else {
            throw invalid("expected_plan_fingerprint", "Continue with the full plan fingerprint from the first page.")
        }
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let preview = try await handle.agentCollaboration.previewMoveNote(noteID: noteID, expectedFingerprint: expected, to: destination)
        guard planFingerprint == nil || planFingerprint == preview.planFingerprint else {
            throw ScholiumMCPFailure(
                code: .staleRevision, message: "The move effects changed after the preview.", recovery: "Request a fresh preview before continuing.")
        }
        let effects: [MCPJSONValue] = preview.effects.map { effect in
            .object([
                "kind": .string(effect.source == preview.source ? "move" : "link_rewrite"),
                "note_id": .string(effect.noteID.uuidString.lowercased()), "role": .string(Self.externalRole(effect.role)),
                "source_relative_path": .string(effect.source.relativePath), "relative_path": .string(effect.destination.relativePath),
                "before_fingerprint": fingerprintValue(effect.beforeFingerprint), "after_fingerprint": fingerprintValue(effect.afterFingerprint),
                "rewritten_occurrences": .integer(effect.rewrittenOccurrences), "source_locator": .null, "reason": .null,
            ])
        }
        let blockers: [MCPJSONValue] = preview.blockers.map { blocked in
            let block = blocked.link
            return .object([
                "kind": .string("blocked"), "note_id": .string(blocked.noteID.uuidString.lowercased()),
                "role": .string(Self.externalRole(blocked.role)), "source_relative_path": .string(block.source.relativePath),
                "relative_path": .null, "before_fingerprint": fingerprintValue(block.sourceFingerprint),
                "after_fingerprint": .null, "rewritten_occurrences": .integer(0), "source_locator": Self.locatorValue(block.span),
                "reason": .string(block.reason),
            ])
        }
        let entries = effects + blockers
        let page = Array(entries.dropFirst(min(offset, entries.count)).prefix(limit))
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()), "note_id": .string(noteID.uuidString.lowercased()),
            "role": .string(Self.externalRole(preview.role)), "source_relative_path": .string(preview.source.relativePath),
            "relative_path": .string(preview.destination.relativePath), "fingerprint": fingerprintValue(preview.expectedFingerprint),
            "plan_fingerprint": fingerprintValue(preview.planFingerprint), "can_move": .bool(preview.blockers.isEmpty),
            "offset": .integer(offset), "limit": .integer(limit), "total": .integer(entries.count),
            "has_more": .bool(offset < entries.count && page.count < entries.count - offset), "entries": .array(page),
        ])
    }

    private func changeValue(_ change: AgentChange) -> MCPJSONValue {
        .object([
            "change_id": .string(change.id.uuidString.lowercased()), "note_id": .string(change.noteID.uuidString.lowercased()),
            "affected_note_count": .integer(change.moveEffects?.count ?? 1),
            "operation": .string(change.operation.rawValue), "state": .string(change.state.rawValue),
            "role": .string(Self.externalRole(change.role)),
            "original_relative_path": change.originalRelativePath.map(MCPJSONValue.string) ?? .null,
            "final_relative_path": change.finalRelativePath.map(MCPJSONValue.string) ?? .null,
            "before_fingerprint": change.beforeFingerprint.map(fingerprintValue) ?? .null,
            "after_fingerprint": change.afterFingerprint.map(fingerprintValue) ?? .null,
            "created_at": .string(Self.timestamp(change.createdAt)),
            "confirmed_at": change.confirmedAt.map { .string(Self.timestamp($0)) } ?? .null,
            "undone_at": change.undoneAt.map { .string(Self.timestamp($0)) } ?? .null,
        ])
    }

    private func listChanges(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        try requireOnly(arguments, keys: ["triptych_id", "note_id", "offset", "limit", "expected_listing_fingerprint"])
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let noteID = try optionalUUID(arguments["note_id"], name: "note_id")
        let limit = try boundedInteger(arguments["limit"], name: "limit", default: 20, range: 1...100)
        let offset = try boundedInteger(arguments["offset"], name: "offset", default: 0, range: 0...Int.max)
        let expected = try arguments["expected_listing_fingerprint"].map { try requiredFingerprint($0) }
        guard offset == 0 || expected != nil else {
            throw invalid("expected_listing_fingerprint", "Continue with the listing fingerprint returned by the first page.")
        }
        try requireOpenTriptych(triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let changes = try await handle.agentCollaboration.agentChanges().filter {
            noteID == nil || $0.noteID == noteID || $0.moveEffects?.contains(where: { $0.noteID == noteID }) == true
        }
        let values = changes.map(changeValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = DocumentFingerprint(
            data: try encoder.encode(
                MCPJSONValue.object([
                    "triptych_id": .string(triptychID.uuidString), "note_id": noteID.map { .string($0.uuidString) } ?? .null, "changes": .array(values),
                ])))
        guard expected == nil || expected == fingerprint else {
            throw ScholiumMCPFailure(code: .staleRevision, message: "The change listing has changed.", recovery: "Read the first page again before continuing.")
        }
        let page = Array(values.dropFirst(min(offset, values.count)).prefix(limit))
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()), "note_id": noteID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "listing_fingerprint": fingerprintValue(fingerprint), "offset": .integer(offset), "limit": .integer(limit),
            "total": .integer(values.count), "has_more": .bool(offset < values.count && page.count < values.count - offset), "changes": .array(page),
        ])
    }

    private func readChange(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        try requireOnly(arguments, keys: ["triptych_id", "change_id", "note_id", "offset", "limit", "effect_offset", "effect_limit"])
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let changeID = try requiredUUID(arguments["change_id"], name: "change_id")
        let limit = try boundedInteger(arguments["limit"], name: "limit", default: 200, range: 1...1000)
        let offset = try boundedInteger(arguments["offset"], name: "offset", default: 0, range: 0...Int.max)
        try requireOpenTriptych(triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let review = try await handle.agentCollaboration.agentChangeReview(id: changeID)
        let selectedNote = try optionalUUID(arguments["note_id"], name: "note_id") ?? review.change.noteID
        let sourceComparison: ExactSourceComparison?
        if selectedNote == review.change.noteID {
            sourceComparison = review.comparison
        } else {
            guard let linked = review.linkedComparisons.first(where: { $0.effect.noteID == selectedNote }) else {
                throw invalid("note_id", "This Note does not belong to the retained change.")
            }
            sourceComparison = linked.comparison
        }
        let effectOffset = try boundedInteger(arguments["effect_offset"], name: "effect_offset", default: 0, range: 0...Int.max)
        let effectLimit = try boundedInteger(arguments["effect_limit"], name: "effect_limit", default: 20, range: 1...100)
        let effects = review.change.moveEffects ?? []
        let effectPage = Array(effects.dropFirst(min(effectOffset, effects.count)).prefix(effectLimit))
        let ending: MCPJSONValue =
            switch review.endingRevisionState {
            case .current: .string("current")
            case .earlierRevision: .string("earlier_revision")
            case .unavailable: .string("unavailable")
            case nil: .null
            }
        var comparison: MCPJSONValue = .null
        if let source = sourceComparison {
            var rows: [MCPJSONValue] = []
            var byteCount = 0
            let encoder = JSONEncoder()
            for line in source.lines.dropFirst(min(offset, source.lines.count)).prefix(limit) {
                let kind =
                    switch line.kind {
                    case .unchanged: "unchanged"
                    case .startingOnly: "removed"
                    case .endingOnly: "added"
                    }
                let row: MCPJSONValue = .object([
                    "kind": .string(kind), "before_line": line.startingLineNumber.map(MCPJSONValue.integer) ?? .null,
                    "after_line": line.endingLineNumber.map(MCPJSONValue.integer) ?? .null, "text": .string(line.text),
                    "line_ending": .string(line.lineEnding.rawValue),
                ])
                let count = try encoder.encode(row).count
                guard count <= Self.maximumReadResponseByteCount else {
                    throw invalid("limit", "One comparison row exceeds the response size; inspect the retained comparison in Scholium.")
                }
                if byteCount + count > Self.maximumReadResponseByteCount { break }
                rows.append(row)
                byteCount += count
            }
            comparison = .object([
                "before_fingerprint": fingerprintValue(source.startingRevision), "after_fingerprint": fingerprintValue(source.endingRevision),
                "before_has_bom": .bool(source.startingHasUTF8BOM), "after_has_bom": .bool(source.endingHasUTF8BOM),
                "offset": .integer(offset), "limit": .integer(limit), "total": .integer(source.lines.count),
                "has_more": .bool(offset < source.lines.count && rows.count < source.lines.count - offset), "rows": .array(rows),
            ])
        }
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()), "change": changeValue(review.change),
            "ending_revision_state": ending, "can_undo": .bool(review.isDirectUndoAvailable), "comparison": comparison,
            "comparison_note_id": .string(selectedNote.uuidString.lowercased()),
            "undo_unavailable_reason": review.undoUnavailableReason.map(MCPJSONValue.string) ?? .null,
            "effects": .object([
                "offset": .integer(effectOffset), "limit": .integer(effectLimit), "total": .integer(effects.count),
                "has_more": .bool(effectOffset < effects.count && effectPage.count < effects.count - effectOffset),
                "entries": .array(effectPage.map(moveEffectValue)),
            ]),
        ])
    }

    private func decodeUndo(_ arguments: [String: MCPJSONValue]) throws -> (UUID, UUID, UUID, DocumentFingerprint) {
        try requireOnly(arguments, keys: ["triptych_id", "note_id", "change_id", "expected_fingerprint"])
        return (
            try requiredUUID(arguments["triptych_id"], name: "triptych_id"), try requiredUUID(arguments["note_id"], name: "note_id"),
            try requiredUUID(arguments["change_id"], name: "change_id"), try requiredFingerprint(arguments["expected_fingerprint"])
        )
    }

    private func undoChange(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        let (triptychID, noteID, changeID, expected) = try decodeUndo(arguments)
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let preview = try await handle.agentCollaboration.previewUndoAgentChange(id: changeID, expectedAfterFingerprint: expected)
        guard preview.noteID == noteID else { throw invalid("note_id", "The change belongs to another Note.") }
        let result = try await handle.agentCollaboration.undoAgentChange(id: changeID, expectedAfterFingerprint: expected)
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()), "note_id": .string(noteID.uuidString.lowercased()),
            "change_id": .string(changeID.uuidString.lowercased()), "source_relative_path": .string(preview.relativePath),
            "relative_path": .string(preview.movePreview?.destination.relativePath ?? preview.relativePath),
            "effects": .array((preview.movePreview?.effects ?? []).map(moveEffectValue)),
            "before_fingerprint": fingerprintValue(expected), "after_fingerprint": fingerprintValue(result.restoredFingerprint),
            "readback_verified": .bool(true), "undone": .bool(true),
        ])
    }

    private func browse(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        try requireOnly(arguments, keys: ["triptych_id", "role", "directory", "limit", "offset", "expected_listing_fingerprint"])
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let role = try arguments["role"].map { try requiredExternalRole($0) }
        let directory = try arguments["directory"].map { try requiredStringAllowingEmpty($0, name: "directory") } ?? ""
        if !directory.isEmpty {
            guard role != nil, (try? VaultRelativeFolderPath(directory)) != nil else {
                throw invalid("directory", "Supply an exact vault-relative directory and its role.")
            }
        }
        let limit = try boundedInteger(arguments["limit"], name: "limit", default: 20, range: 1...100)
        let offset = try boundedInteger(arguments["offset"], name: "offset", default: 0, range: 0...Int.max)
        let expected = try arguments["expected_listing_fingerprint"].map { try requiredFingerprint($0) }
        guard offset == 0 || expected != nil else {
            throw invalid("expected_listing_fingerprint", "Continue with the fingerprint returned by the first page.")
        }
        let snapshot = try await currentSnapshot(triptychID: triptychID)
        var entries: [MCPJSONValue] = []
        func entry(
            kind: String, role: VaultRole, path: String, title: String,
            noteID: UUID? = nil, fingerprint: DocumentFingerprint? = nil
        ) -> MCPJSONValue {
            .object([
                "kind": .string(kind), "role": .string(Self.externalRole(role)), "relative_path": .string(path),
                "title": .string(title), "note_id": noteID.map { .string($0.uuidString.lowercased()) } ?? .null,
                "fingerprint": fingerprint.map(fingerprintValue) ?? .null,
            ])
        }
        if let role {
            guard let vault = snapshot.vaults.first(where: { $0.vault.role == role }) else {
                throw ScholiumMCPFailure(
                    code: .workspaceNotReady, message: "The selected role vault is unavailable.", recovery: "Restore vault access and refresh workspace status."
                )
            }
            guard WorkspaceLibraryVisibility.includes(directory), directory.isEmpty || vault.folders.contains(where: { $0.rawValue == directory }) else {
                throw ScholiumMCPFailure(
                    code: .notFound, message: "The directory is not in the current Library.", recovery: "Browse its parent and use a current directory path.")
            }
            func isChild(_ path: String) -> Bool {
                WorkspaceLibraryVisibility.includes(path) && path.split(separator: "/").dropLast().joined(separator: "/") == directory
            }
            entries = vault.folders.filter { isChild($0.rawValue) }.sorted { $0.rawValue < $1.rawValue }.map {
                entry(kind: "directory", role: role, path: $0.rawValue, title: String($0.components.last!))
            }
            entries += vault.documents.filter { isChild($0.id.relativePath) }.sorted { $0.id.relativePath < $1.id.relativePath }.map {
                entry(
                    kind: "note", role: role, path: $0.id.relativePath, title: ResearchNoteTitleResolver.resolve(document: $0.document),
                    noteID: $0.stableIdentity.resolvedID, fingerprint: $0.fingerprint)
            }
        } else {
            entries = WorkspaceVaultSlot.allCases.compactMap { slot in snapshot.vaults.first { $0.slot == slot } }.map {
                entry(kind: "role", role: $0.vault.role, path: "", title: $0.vault.name)
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = DocumentFingerprint(
            data: try encoder.encode(
                MCPJSONValue.object([
                    "triptych_id": .string(triptychID.uuidString), "role": role.map { .string(Self.externalRole($0)) } ?? .null,
                    "directory": .string(directory), "entries": .array(entries),
                ])))
        guard expected == nil || expected == fingerprint else {
            throw ScholiumMCPFailure(
                code: .staleRevision, message: "The directory listing changed between pages.", recovery: "Restart browsing this directory at offset zero.")
        }
        let page = Array(entries.dropFirst(min(offset, entries.count)).prefix(limit))
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()), "role": role.map { .string(Self.externalRole($0)) } ?? .null,
            "directory": .string(directory), "listing_fingerprint": fingerprintValue(fingerprint),
            "offset": .integer(offset), "limit": .integer(limit), "total": .integer(entries.count),
            "has_more": .bool(offset < entries.count && page.count < entries.count - offset), "entries": .array(page),
        ])
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
                "triptychs": .array(
                    assignments.map { assignment in
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
                "triptych_id", "query", "roles", "limit", "offset",
            ]
        )
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let query = try requiredString(arguments["query"], name: "query")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
            query.utf16.count <= SearchContract.maximumQueryUTF16Count
        else {
            throw invalid("query", "Provide one nonempty bounded Search query.")
        }
        let noteLimit = try boundedInteger(
            arguments["limit"],
            name: "limit",
            default: 20,
            range: 1...100
        )
        let noteOffset = try boundedInteger(
            arguments["offset"],
            name: "offset",
            default: 0,
            range: 0...Int.max
        )
        let snapshot = try await currentSnapshot(triptychID: triptychID)
        let includedVaultIDs = try roleVaultIDs(
            arguments["roles"],
            snapshot: snapshot
        )
        let handle = try await runtime.openWorkspace(id: triptychID)
        let response = try await handle.discovery.search(
            SearchRequest(
                query: query,
                presentationScope: .triptych,
                executionScope: .triptych,
                limit: noteLimit,
                offset: noteOffset,
                includedVaultIDs: includedVaultIDs
            ))
        if let diagnostic = response.diagnostics.first {
            throw invalid("query", diagnostic.message)
        }
        let noteGroup: MCPJSONValue = {
            let noteResponse = response
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
        }()
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "query": .string(query),
            "notes": noteGroup,
        ])
    }

    private func readNote(
        _ arguments: [String: MCPJSONValue]
    ) async throws -> MCPJSONValue {
        try requireOnly(
            arguments,
            keys: ["triptych_id", "note_id", "start_line", "line_count", "include_context"]
        )
        let triptychID = try requiredUUID(arguments["triptych_id"], name: "triptych_id")
        let noteID = try requiredUUID(arguments["note_id"], name: "note_id")
        if let flag = arguments["include_context"], flag.boolValue == nil {
            throw invalid("include_context", "Use true or false to request saved Note details and material relationships.")
        }
        let startLine = try boundedInteger(
            arguments["start_line"],
            name: "start_line",
            default: 1,
            range: 1...Int.max
        )
        let lineCount = try boundedInteger(
            arguments["line_count"],
            name: "line_count",
            default: 200,
            range: 1...1_000
        )
        let snapshot = try await currentSnapshot(triptychID: triptychID)
        _ = try resolveNote(noteID, snapshot: snapshot)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let source = try await handle.agentCollaboration.currentNoteSource(noteID: noteID)
        let slice = try Self.exactLineSlice(
            source.source,
            startLine: startLine,
            requestedLineCount: lineCount
        )
        let context: MCPJSONValue
        if arguments["include_context"]?.boolValue == true {
            let records = try await handle.agentCollaboration.currentNoteContext(noteID: noteID, expectedFingerprint: source.fingerprint)
            guard records.note == source.note else {
                throw ScholiumMCPFailure(
                    code: .conflict, message: "This Note moved while its context was being read.",
                    recovery: "Read the Note again at its current location.")
            }
            context = try noteContextValue(records, triptych: triptychID, note: noteID)
        } else {
            context = .null
        }
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "note_id": .string(noteID.uuidString.lowercased()),
            "role": .string(Self.externalRole(source.role)),
            "relative_path": .string(source.note.relativePath),
            "fingerprint": fingerprintValue(source.fingerprint),
            "start_line": .integer(startLine),
            "line_count": .integer(slice.lineCount),
            "start_utf8": .integer(slice.startUTF8),
            "end_utf8": .integer(slice.endUTF8),
            "source": .string(slice.source),
            "context": context,
            "complete": .bool(slice.nextLine == nil),
            "next_line": slice.nextLine.map(MCPJSONValue.integer) ?? .null,
        ])
    }

    private func noteContextValue(_ context: AgentNoteContext, triptych: UUID, note: UUID) throws -> MCPJSONValue {
        let metadata: MCPJSONValue =
            context.metadata.map { snapshot in
                .object([
                    "fingerprint": fingerprintValue(snapshot.revision),
                    "fields": .object(snapshot.record.fields.mapValues(Self.metadataValue)),
                ])
            } ?? .null
        let binding: MCPJSONValue
        if let record = context.zoteroBinding {
            let library: MCPJSONValue =
                switch record.library {
                case .user: .object(["kind": .string("user")])
                case .group(let id): .object(["kind": .string("group"), "group_id": .integer(id)])
                }
            binding = .object([
                "library": library, "item_key": .string(record.itemKey),
                "reference": .string(try ZoteroReference(library: record.library, itemKey: record.itemKey).url.absoluteString),
            ])
        } else {
            binding = .null
        }
        let value: MCPJSONValue = .object([
            "metadata": metadata, "zotero_binding": binding,
            "zotero_bindings_fingerprint": context.zoteroBindingsRevision.map(fingerprintValue) ?? .null,
            "attachments": try attachmentListingValue(context.attachments, triptych: triptych, note: note),
        ])
        guard try JSONEncoder().encode(value).count <= 128 * 1_024 else {
            throw invalid(
                "include_context",
                "The saved Note context exceeds 128 KiB. Read the source without context and inspect its details in Scholium; attachments remain separately available through list_attachments."
            )
        }
        return value
    }

    private static func metadataValue(_ value: YAMLValue) -> MCPJSONValue {
        switch value {
        case .string(let value): .string(value)
        case .integer(let value): .integer(value)
        case .double(let value): .double(value)
        case .boolean(let value): .bool(value)
        case .null: .null
        case .array(let values): .array(values.map(metadataValue))
        case .object(let values): .object(values.mapValues(metadataValue))
        }
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
            range: 1...100
        )
        let offset = try boundedInteger(
            arguments["offset"],
            name: "offset",
            default: 0,
            range: 0...Int.max
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
                if let sourceID = stableIdentity(for: edge.source, snapshot: snapshot) {
                    let current = try await handle.agentCollaboration.currentNoteSource(noteID: sourceID)
                    guard current.note == edge.source,
                        snapshot.document(id: edge.source)?.fingerprint == current.fingerprint,
                        let content = NoteDocument.decodeUTF8PreservingBOM(current.source)
                    else {
                        throw ScholiumMCPFailure(
                            code: .conflict,
                            message: "The link source changed identity or revision during the read.",
                            recovery: "Read workspace status and request the current links again."
                        )
                    }
                    sourceDocument = NoteDocument(relativePath: current.note.relativePath, rawContent: content)
                } else {
                    sourceDocument = try await handle.documents.load(edge.source)
                }
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
            values.append(
                .object([
                    "occurrence_direction": .string("outgoing"),
                    "source_note_id": stableIdentity(
                        for: edge.source,
                        snapshot: snapshot
                    ).map { .string($0.uuidString.lowercased()) } ?? .null,
                    "destination_note_id": edge.destination.flatMap {
                        stableIdentity(for: $0.note, snapshot: snapshot)
                    }.map { .string($0.uuidString.lowercased()) } ?? .null,
                    "source_role": .string(
                        Self.externalRole(
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
                    "local_context": .string(
                        Self.localContext(
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
            relativePath.lowercased().hasSuffix(".md")
        else {
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
        guard
            let vault = snapshot.vaults.first(where: {
                $0.vault.role == role
            })
        else {
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
        didConfirmChange(result.change)
        return ok([
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "change_id": .string(result.change.id.uuidString.lowercased()),
            "note_id": .string(result.noteID.uuidString.lowercased()),
            "role": .string(Self.externalRole(result.role)),
            "relative_path": .string(result.relativePath),
            "fingerprint": fingerprintValue(result.fingerprint),
        ])
    }

    private func decodeUpdate(
        _ arguments: [String: MCPJSONValue]
    ) throws -> (triptychID: UUID, noteID: UUID, expected: DocumentFingerprint, update: AgentNoteUpdate) {
        try requireOnly(
            arguments,
            keys: [
                "triptych_id", "note_id", "expected_fingerprint", "mode",
                "content", "edits",
            ]
        )
        let triptychID = try requiredUUID(
            arguments["triptych_id"],
            name: "triptych_id"
        )
        let noteID = try requiredUUID(arguments["note_id"], name: "note_id")
        let expected = try requiredFingerprint(arguments["expected_fingerprint"])
        let rawMode = try requiredString(arguments["mode"], name: "mode")
        let update: AgentNoteUpdate
        switch rawMode {
        case "body", "source":
            guard arguments["edits"] == nil else { throw invalid("edits", "Use edits only with mode edits.") }
            let content = try requiredStringAllowingEmpty(arguments["content"], name: "content")
            update = rawMode == "body" ? .body(content) : .source(content)
        case "edits":
            guard arguments["content"] == nil,
                let values = arguments["edits"]?.arrayValue,
                (1...AgentSourceEdit.maximumCount).contains(values.count)
            else {
                throw invalid("edits", "Supply 1–100 exact edits and omit content.")
            }
            update = .edits(
                try values.map { value in
                    guard let edit = value.objectValue else { throw invalid("edits", "Each edit must be an object.") }
                    try requireOnly(edit, keys: ["start_utf8", "end_utf8", "expected_text", "replacement"])
                    guard let start = edit["start_utf8"]?.intValue, let end = edit["end_utf8"]?.intValue else {
                        throw invalid("edits", "Supply integer UTF-8 source offsets.")
                    }
                    return AgentSourceEdit(
                        startUTF8: start, endUTF8: end,
                        expectedText: try requiredStringAllowingEmpty(edit["expected_text"], name: "expected_text"),
                        replacement: try requiredStringAllowingEmpty(edit["replacement"], name: "replacement"))
                })
        default: throw invalid("mode", "Use body, source or edits.")
        }
        return (triptychID, noteID, expected, update)
    }

    func previewUpdate(_ request: ScholiumMCPBridgeRequest) async throws -> AgentNoteUpdatePreview {
        do {
            if request.tool == .updateMetadata || request.tool == .updateAttachment {
                let (triptych, note, expected) = try decodeRecordScope(request.arguments)
                try requireOpenTriptych(triptych)
                let handle = try await runtime.openWorkspace(id: triptych)
                if request.tool == .updateMetadata {
                    return try await handle.agentCollaboration.previewMetadata(
                        noteID: note, expectedSource: expected, update: decodeMetadata(request.arguments))
                }
                return try await handle.agentCollaboration.previewAttachment(
                    noteID: note, expectedSource: expected, update: decodeAttachment(request.arguments))
            }

            if request.tool == .moveNote {
                let (triptychID, noteID, expected, path, planFingerprint) = try decodeMove(request.arguments)
                try requireOpenTriptych(triptychID)
                let handle = try await runtime.openWorkspace(id: triptychID)
                return try await handle.agentCollaboration.previewMoveMutation(
                    noteID: noteID, expectedFingerprint: expected,
                    to: path, expectedPlanFingerprint: planFingerprint)
            }
            if request.tool == .undoChange {
                let (triptychID, noteID, changeID, expected) = try decodeUndo(request.arguments)
                try requireOpenTriptych(triptychID)
                let handle = try await runtime.openWorkspace(id: triptychID)
                let preview = try await handle.agentCollaboration.previewUndoAgentChange(id: changeID, expectedAfterFingerprint: expected)
                guard preview.noteID == noteID else { throw invalid("note_id", "The change belongs to another Note.") }
                return preview
            }
            guard request.tool == .updateNote else { throw invalid("tool", "Only Note updates and Undo have this comparison.") }
            let (triptychID, noteID, expected, update) = try decodeUpdate(request.arguments)
            try requireOpenTriptych(triptychID)
            let handle = try await runtime.openWorkspace(id: triptychID)
            return try await handle.agentCollaboration.previewUpdateNote(
                noteID: noteID, expectedFingerprint: expected, update: update)
        } catch let failure as ScholiumMCPFailure { throw failure } catch { throw Self.failure(for: error) }
    }

    private func decodeRecordScope(_ args: [String: MCPJSONValue]) throws -> (UUID, UUID, DocumentFingerprint) {
        (
            try requiredUUID(args["triptych_id"], name: "triptych_id"), try requiredUUID(args["note_id"], name: "note_id"),
            try requiredFingerprint(args["expected_fingerprint"])
        )
    }

    private func decodeMetadata(_ args: [String: MCPJSONValue]) throws -> AgentMetadataUpdate {
        try requireOnly(args, keys: ["triptych_id", "note_id", "expected_fingerprint", "expected_metadata_fingerprint", "set", "remove"])
        guard let revision = args["expected_metadata_fingerprint"] else {
            throw invalid("expected_metadata_fingerprint", "Supply the current Metadata fingerprint, or null for an absent record.")
        }
        guard args["set"] == nil || args["set"]?.objectValue != nil,
            args["remove"] == nil || args["remove"]?.arrayValue != nil
        else { throw invalid("set/remove", "Use a field mapping and a list of field keys.") }
        guard try JSONEncoder().encode(MCPJSONValue.object(args)).count <= 128 * 1_024 else {
            throw invalid("set/remove", "Use a Metadata patch of at most 128 KiB.")
        }
        let remove = try (args["remove"]?.arrayValue ?? []).map { try requiredString($0, name: "remove") }
        return try .init(
            expectedRevision: revision == .null ? nil : requiredFingerprint(revision),
            set: (args["set"]?.objectValue ?? [:]).mapValues(Self.managedValue), remove: remove)
    }

    private static func managedValue(_ value: MCPJSONValue) -> YAMLValue {
        switch value {
        case .string(let value): .string(value)
        case .integer(let value): .integer(value)
        case .double(let value): .double(value)
        case .bool(let value): .boolean(value)
        case .null: .null
        case .array(let values): .array(values.map(managedValue))
        case .object(let values): .object(values.mapValues(managedValue))
        }
    }

    private func decodeAttachment(_ args: [String: MCPJSONValue]) throws -> AgentAttachmentUpdate {
        try requireOnly(args, keys: ["triptych_id", "note_id", "expected_fingerprint", "action", "attachment_id", "expected_listing_fingerprint", "source"])
        guard let action = AgentAttachmentUpdate.Action(rawValue: try requiredString(args["action"], name: "action")) else {
            throw invalid("action", "Use add, replace or remove.")
        }
        var source: AgentAttachmentUpdate.Source?
        if let raw = args["source"] {
            guard let value = raw.objectValue else { throw invalid("source", "Select one existing Note attachment.") }
            try requireOnly(value, keys: ["note_id", "attachment_id", "expected_listing_fingerprint", "expected_fingerprint"])
            source = try .init(
                noteID: requiredUUID(value["note_id"], name: "source.note_id"),
                attachmentID: requiredUUID(value["attachment_id"], name: "source.attachment_id"),
                listingFingerprint: requiredFingerprint(value["expected_listing_fingerprint"]),
                fileFingerprint: requiredFingerprint(value["expected_fingerprint"]))
        }
        return try .init(
            action: action, attachmentID: requiredUUID(args["attachment_id"], name: "attachment_id"),
            listingFingerprint: requiredFingerprint(args["expected_listing_fingerprint"]), source: source)
    }

    private func updateRecord(_ request: ScholiumMCPBridgeRequest) async throws -> MCPJSONValue {
        let (triptych, note, expected) = try decodeRecordScope(request.arguments)
        // Decode before preparing the live workspace or invoking a writer.
        let metadata = request.tool == .updateMetadata ? try decodeMetadata(request.arguments) : nil
        let attachment = request.tool == .updateAttachment ? try decodeAttachment(request.arguments) : nil
        _ = try await currentSnapshot(triptychID: triptych)
        let handle = try await runtime.openWorkspace(id: triptych)
        let result: AgentNoteUpdateResult
        if let metadata {
            result = try await handle.agentCollaboration.updateMetadata(noteID: note, expectedSource: expected, update: metadata)
        } else if let attachment {
            result = try await handle.agentCollaboration.updateAttachment(noteID: note, expectedSource: expected, update: attachment)
        } else {
            throw invalid("tool", "Choose one published record operation.")
        }
        didConfirmChange(result.change)
        return ok([
            "triptych_id": .string(triptych.uuidString.lowercased()), "note_id": .string(note.uuidString.lowercased()),
            "change_id": .string(result.change.id.uuidString.lowercased()), "relative_path": .string(result.relativePath),
            "before_fingerprint": fingerprintValue(result.beforeFingerprint), "after_fingerprint": fingerprintValue(result.afterFingerprint),
            "readback_verified": .bool(result.readbackVerified),
        ])
    }

    private func updateNote(_ arguments: [String: MCPJSONValue]) async throws -> MCPJSONValue {
        let (triptychID, noteID, expected, update) = try decodeUpdate(arguments)
        _ = try await currentSnapshot(triptychID: triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let result = try await handle.agentCollaboration.updateNote(
            noteID: noteID,
            expectedFingerprint: expected,
            update: update
        )
        didConfirmChange(result.change)
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
        didConfirmChange(result.change)
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

    private func currentSnapshot(triptychID: UUID) async throws
        -> WorkspaceSnapshot
    {
        try requireOpenTriptych(triptychID)
        try await flushEditors(triptychID)
        let handle = try await runtime.openWorkspace(id: triptychID)
        let snapshot = try await handle.discovery.refresh()
        guard snapshot.phase.isComplete,
            let searchGeneration = snapshot.discovery.searchGeneration
        else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "Scholium has not completed the current Triptych source and Search generation.",
                recovery: "Wait for the App to finish loading, then call workspace status again."
            )
        }
        let sourceHash = Self.sourceManifestHash(snapshot)
        guard searchGeneration.sourceManifestHash == sourceHash,
            snapshot.discovery.catalog.graph?.sourceManifestHash == sourceHash
        else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "Scholium source, Search, and link generations are not yet coherent.",
                recovery: "Refresh the Triptych in the App, then call workspace status again."
            )
        }
        return snapshot
    }

    private func requireOpenTriptych(_ triptychID: UUID) throws {
        guard openTriptychs().contains(where: { $0.id == triptychID }) else {
            throw ScholiumMCPFailure(
                code: .notFound,
                message: "The requested Triptych is not open in Scholium.",
                recovery: "Call workspace status and select one currently open Triptych.")
        }
    }

    private func statusValue(_ snapshot: WorkspaceSnapshot) async throws -> MCPJSONValue {
        let sourceHash = Self.sourceManifestHash(snapshot)
        return ok([
            "current": .bool(true),
            "selection_required": .bool(false),
            "triptych_id": .string(snapshot.triptych.id.uuidString.lowercased()),
            "name": .string(snapshot.triptych.name),
            "windows": .array(displayWindows(snapshot.triptych.id)),
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
            "graph_generation": snapshot.discovery.catalog.graph.map {
                .object([
                    "sequence": .integer($0.generation),
                    "manifest_sha256": .string($0.sourceManifestHash),
                ])
            } ?? .null,
            "vaults": .array(
                snapshot.vaults.sorted {
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
                ["analyses", "topics", "works"].contains(role)
            else {
                throw invalid("roles", "Use only analyses, topics, or works.")
            }
            return role
        }
        guard Set(roles).count == roles.count else {
            throw invalid("roles", "Do not repeat a role.")
        }
        return Set(
            roles.compactMap { role in
                snapshot.vaults.first {
                    Self.externalRole($0.vault.role) == role
                }?.vault.id
            })
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
        .object(
            fields.merging([
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
                (48...57).contains($0.value) || (97...102).contains($0.value)
            }),
            let byteCount = object["byte_count"]?.intValue,
            byteCount >= 0
        else {
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
            let value = UUID(uuidString: string)
        else {
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

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    private static func sourceManifestHash(_ snapshot: WorkspaceSnapshot)
        -> String
    {
        SearchSourceManifest.hash(
            snapshot.vaults.flatMap { vault in
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
            range.lowerBound <= range.upperBound
        else { return "" }
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
    ) throws -> (source: String, lineCount: Int, nextLine: Int?, startUTF8: Int, endUTF8: Int) {
        if data.isEmpty {
            guard startLine == 1 else {
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "start_line is beyond the end of the Note.",
                    recovery: "Begin at source line 1."
                )
            }
            return ("", 0, nil, 0, 0)
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
            let candidateEnd =
                endIndex + 1 < starts.count
                ? starts[endIndex + 1]
                : data.count
            if candidateEnd - starts[startIndex] > maximumReadResponseByteCount,
                endIndex > startIndex
            {
                break
            }
            guard
                candidateEnd - starts[startIndex]
                    <= maximumReadResponseByteCount
            else {
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "One logical source line exceeds the bounded MCP response size.",
                    recovery: "Open the exact Note in Scholium or split the oversized source line."
                )
            }
            endIndex += 1
        }
        let endOffset = endIndex < starts.count ? starts[endIndex] : data.count
        let slice = data.subdata(in: starts[startIndex]..<endOffset)
        let source = NoteDocument.decodeUTF8PreservingBOM(slice)
        guard let source else {
            throw ScholiumMCPFailure(
                code: .internalError,
                message: "The exact UTF-8 source slice could not be represented.",
                recovery: "Inspect the Note in Scholium before retrying."
            )
        }
        let nextLine = endIndex < starts.count ? endIndex + 1 : nil
        return (source, endIndex - startIndex, nextLine, starts[startIndex], endOffset)
    }

    private static func failure(for error: Error) -> ScholiumMCPFailure {
        if let error = error as? ScholiumApplicationError {
            switch error {
            case .workspaceStillLoading, .noWorkspaceConfigured,
                .incompleteTriptych:
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
            case .noChanges:
                return ScholiumMCPFailure(
                    code: .noChanges,
                    message: "The proposed update would not change the Note.",
                    recovery: "No write or Agent Change was created. Continue without retrying this identical update."
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
            }
        }
        if let error = error as? TriptychTransactionError {
            switch error {
            case .invalidPlan, .preflightFailed:
                return .init(
                    code: .invalidRequest, message: error.localizedDescription,
                    recovery: "Inspect the target path, current source and link effects, then request a fresh preview.")
            case .transactionRolledBack:
                return .init(
                    code: .conflict, message: error.localizedDescription, recovery: "The owner rolled back the move. Read current source and preview again.")
            case .recoveryRequired(let record), .recoveryPersistenceFailed(let record, _):
                return .init(
                    code: .operationUncertain, message: error.localizedDescription,
                    recovery: "Inspect the per-file Recovery evidence in Scholium. Do not repeat the move automatically.",
                    recoveryDetails: .init(record: record))
            }
        }
        if let error = error as? AgentChangeError {
            switch error {
            case .missing:
                return .init(code: .notFound, message: "The Agent Change is unavailable.", recovery: "List current changes and use an exact change ID.")
            case .undoUnavailable, .notConfirmed, .alreadyFinal, .mismatchedBinding:
                return .init(
                    code: .invalidRequest, message: error.localizedDescription,
                    recovery: "Read the named change and its current state. Do not repeat a completed Undo.")
            case .invalid, .unsafeStore, .sourceTooLarge:
                return .init(
                    code: .workspaceNotReady, message: error.localizedDescription,
                    recovery: "Inspect Agent Changes in Scholium; retained evidence is unavailable and grants no restoration authority.")
            }
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
