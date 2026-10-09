import Foundation
import ScholiumContracts

extension WorkspaceStore {
    /// Reads registered live owners only. Native preferences are admission and
    /// delivery gates, independent of source-write and runtime permissions.
    func observeAgentState(
        _ request: ScholiumMCPBridgeRequest, preferences: AgentContextAccessPreferences = .shared
    ) async throws -> MCPJSONValue {
        let caller: AgentContextCaller = request.conversationToken == nil ? .external : .chat
        let readsText = request.tool == .readContext
        func permitted() -> Bool {
            readsText ? preferences.allowsWorkingText(for: caller) : preferences.allowsState(for: caller)
        }
        guard permitted() else { throw ScholiumMCPFailure.contextAccessDenied() }
        let permissionRevision = preferences.revision
        if request.tool == .observeWorkspace, request.arguments["triptych_id"] == nil {
            guard caller == .external,
                Set(request.arguments.keys).isSubset(of: ["offset", "limit", "expected_listing_fingerprint"]), !Task.isCancelled
            else { throw contextInvalid() }
            let offset = try contextInteger(request.arguments["offset"], default: 0, range: 0...Int.max)
            let limit = try contextInteger(request.arguments["limit"], default: 20, range: 1...100)
            let scopes = Dictionary(grouping: noteDisplayWindows.values.compactMap { $0.state()?.triptychID }, by: { $0 })
            let items: [MCPJSONValue] = scopes.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
                .object(["triptych_id": .string(id.uuidString.lowercased()), "window_count": .integer(scopes[id]!.count)])
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let fingerprint = DocumentFingerprint(data: try encoder.encode(MCPJSONValue.array(items)))
            let expected = try request.arguments["expected_listing_fingerprint"].map(AgentWindowObservation.expectedFingerprint)
            guard offset <= items.count, offset == 0 || expected != nil else { throw contextInvalid() }
            if let expected, expected != fingerprint { throw contextStale() }
            let end = offset + min(limit, items.count - offset)
            guard permitted(), preferences.revision == permissionRevision, !Task.isCancelled else { throw ScholiumMCPFailure.contextAccessDenied() }
            return try boundedContext(
                .object([
                    "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"),
                    "observed_at": .string(ISO8601DateFormatter().string(from: Date())),
                    "triptychs": .object([
                        "offset": .integer(offset), "limit": .integer(limit), "total": .integer(items.count),
                        "has_more": .bool(end < items.count), "next_offset": end < items.count ? .integer(end) : .null,
                        "listing_fingerprint": .object(["sha256": .string(fingerprint.sha256), "byte_count": .integer(fingerprint.byteCount)]),
                        "items": .array(Array(items[offset..<end])),
                    ]),
                ]))
        }
        let triptych = try contextUUID(request.arguments["triptych_id"])
        let windowID = try request.arguments["window_id"].map { try contextUUID($0) }
        let keys: Set<String>
        switch request.tool {
        case .observeWorkspace, .observeResearchContext:
            keys = ["triptych_id", "window_id", "offset", "limit", "expected_listing_fingerprint"]
        case .readContext:
            keys = [
                "triptych_id", "window_id", "kind", "note_id", "expected_fingerprint", "kept_passage_id",
                "start_utf8", "max_utf8", "expected_start_utf8", "expected_end_utf8",
            ]
        default: throw contextInvalid()
        }
        guard Set(request.arguments.keys).isSubset(of: keys), !Task.isCancelled else { throw contextInvalid() }
        if caller == .chat {
            guard let windowID, admitsAgentObservation(request, windowID: windowID) else { throw contextUnavailable() }
        }
        func permissionCurrent() -> Bool { !Task.isCancelled && permitted() && preferences.revision == permissionRevision }

        if request.tool == .observeWorkspace, windowID == nil {
            let offset = try contextInteger(request.arguments["offset"], default: 0, range: 0...Int.max)
            let limit = try contextInteger(request.arguments["limit"], default: 20, range: 1...100)
            let windows: [(AgentNoteDisplayWindow, MCPJSONValue)] = noteDisplayWindows.keys.sorted { $0.uuidString < $1.uuidString }.compactMap {
                id -> (AgentNoteDisplayWindow, MCPJSONValue)? in
                guard let registration = noteDisplayWindows[id], registration.state()?.triptychID == triptych else { return nil }
                let captured = registration.stateSummary?().objectValue ?? [:]
                var summary: [String: MCPJSONValue] = [:]
                for key in ["kind", "selected_tab_id", "tab_count", "restoring", "transferring", "closing"] {
                    summary[key] = captured[key] ?? .null
                }
                summary["window_id"] = .string(id.uuidString.lowercased())
                summary["available"] = .bool(registration.state()?.canObserve == true)
                return (registration, .object(summary))
            }
            guard !windows.isEmpty else { throw contextUnavailable() }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let identity = MCPJSONValue.array(
                windows.map {
                    MCPJSONValue.object([
                        "registration": .string($0.0.registrationID.uuidString), "summary": $0.1,
                    ])
                })
            let fingerprint = DocumentFingerprint(data: try encoder.encode(identity))
            let expected = try request.arguments["expected_listing_fingerprint"].map(AgentWindowObservation.expectedFingerprint)
            guard offset <= windows.count, offset == 0 || expected != nil else { throw contextInvalid() }
            if let expected, expected != fingerprint { throw contextStale() }
            let end = offset + min(limit, windows.count - offset)
            let result = MCPJSONValue.object([
                "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok"),
                "triptych_id": .string(triptych.uuidString.lowercased()), "observed_at": .string(ISO8601DateFormatter().string(from: Date())),
                "windows": .object([
                    "offset": .integer(offset), "limit": .integer(limit), "total": .integer(windows.count),
                    "has_more": .bool(end < windows.count), "next_offset": end < windows.count ? .integer(end) : .null,
                    "listing_fingerprint": .object(["sha256": .string(fingerprint.sha256), "byte_count": .integer(fingerprint.byteCount)]),
                    "items": .array(windows[offset..<end].map { $0.1 }),
                ]),
            ])
            guard permissionCurrent() else { throw ScholiumMCPFailure.contextAccessDenied() }
            return try boundedContext(result)
        }
        guard let windowID, let registration = noteDisplayWindows[windowID],
            let observe = registration.observeAgentState
        else { throw contextUnavailable() }
        func current() -> Bool {
            guard permissionCurrent(), noteDisplayWindows[windowID]?.registrationID == registration.registrationID,
                let state = registration.state(), state.triptychID == triptych,
                caller == .chat ? state.canDisplay : state.canObserve
            else { return false }
            return caller == .external || admitsAgentObservation(request, windowID: windowID)
        }
        guard current() else { throw contextUnavailable() }
        let result: MCPJSONValue
        do { result = try await observe(request, current) } catch {
            guard permissionCurrent() else { throw ScholiumMCPFailure.contextAccessDenied() }
            guard current() else { throw contextUnavailable() }
            // Window owners use fixed safe typed failures, never raw diagnostics.
            if let failure = error as? ScholiumMCPFailure {
                throw ScholiumMCPFailure(
                    code: failure.code,
                    message: "The requested context could not be captured with its current identity, revision and access.",
                    recovery: "Inspect the context in Scholium and request a fresh bounded observation or exact read.")
            }
            throw contextUnavailable()
        }
        guard permissionCurrent() else { throw ScholiumMCPFailure.contextAccessDenied() }
        guard current() else { throw contextUnavailable() }
        guard var fields = result.objectValue else { throw contextInvalid() }
        let expectedKeys: Set<String>
        switch request.tool {
        case .observeWorkspace: expectedKeys = ["window", "listing_fingerprint", "tabs"]
        case .observeResearchContext:
            expectedKeys = ["window", "listing_fingerprint", "document_surface", "active_note", "library", "search", "related_material", "kept_passages"]
        case .readContext:
            expectedKeys = ["kind", "origin", "note", "fingerprint", "source_locator", "text_fingerprint", "kept_passage_id", "text", "coverage"]
        default: throw contextInvalid()
        }
        guard Set(fields.keys) == expectedKeys else { throw contextInvalid() }
        fields["schema_version"] = .integer(ScholiumMCPContract.currentToolSchemaVersion)
        fields["status"] = .string("ok")
        fields["triptych_id"] = .string(triptych.uuidString.lowercased())
        fields["window_id"] = .string(windowID.uuidString.lowercased())
        fields["observed_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        return try boundedContext(.object(fields))
    }
}

private func boundedContext(_ result: MCPJSONValue) throws -> MCPJSONValue {
    guard try JSONEncoder().encode(result).count <= ScholiumMCPContract.maximumContextObservationUTF8ByteCount else {
        throw contextInvalid()
    }
    return result
}

private func contextUUID(_ value: MCPJSONValue?) throws -> UUID {
    guard let id = value?.stringValue.flatMap(UUID.init(uuidString:)) else { throw contextInvalid() }
    return id
}

private func contextInteger(_ value: MCPJSONValue?, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
    guard let value else { return fallback }
    guard let number = value.intValue, range.contains(number) else { throw contextInvalid() }
    return number
}

private func contextInvalid() -> ScholiumMCPFailure {
    .init(
        code: .invalidRequest, message: "The context request does not match its bounded contract.",
        recovery: "Supply explicit Triptych/window identities and the returned revision or listing fingerprint. Reduce the requested page if needed.")
}

private func contextUnavailable() -> ScholiumMCPFailure {
    .init(
        code: .workspaceNotReady, message: "The requested live context is unavailable.",
        recovery: "Request a fresh snapshot from the intended open Triptych and window.")
}

private func contextStale() -> ScholiumMCPFailure {
    .init(code: .staleRevision, message: "The context listing changed.", recovery: "Restart the listing from its first page.")
}
