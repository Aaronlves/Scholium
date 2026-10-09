import AppKit
import Combine
import Foundation
import ScholiumContracts

/// Request-local projections of existing window owners. They carry no leases,
/// navigation authority, durable observation history or alternate source state.
enum AgentWindowObservation {
    static func fingerprint(_ value: MCPJSONValue) throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return DocumentFingerprint(content: String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    static func fingerprintValue(_ value: DocumentFingerprint) -> MCPJSONValue {
        .object(["sha256": .string(value.sha256), "byte_count": .integer(value.byteCount)])
    }

    static func expectedFingerprint(_ value: MCPJSONValue?) throws -> DocumentFingerprint {
        guard let object = value?.objectValue, Set(object.keys) == ["sha256", "byte_count"],
            let hash = object["sha256"]?.stringValue, hash.count == 64,
            hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
            let count = object["byte_count"]?.intValue, count >= 0
        else { throw failure(.invalidRequest) }
        return DocumentFingerprint(sha256: hash, byteCount: count)
    }

    static func integer(_ value: MCPJSONValue?, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let value else { return fallback }
        guard let integer = value.intValue, range.contains(integer) else { throw failure(.invalidRequest) }
        return integer
    }

    static func validPath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 4_096 && !path.hasPrefix("/")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
            && !path.unicodeScalars.contains(where: { $0.value == 0 })
    }

    static func role(_ role: VaultRole) -> String {
        switch role {
        case .sourceCorpus: "analyses"
        case .topicKnowledge: "topics"
        case .draftProject: "works"
        case .other: "unavailable"
        }
    }

    static func mode(_ mode: NotePresentationMode) -> String {
        mode == .read ? "review" : mode == .source ? "source" : "edit"
    }

    static func locator(_ range: SearchSourceRange) -> MCPJSONValue {
        .object([
            "start_utf16": .integer(range.utf16LowerBound), "end_utf16": .integer(range.utf16UpperBound),
            "start_line": .integer(range.line), "start_column": .integer(range.column),
            "end_line": .integer(range.endLine), "end_column": .integer(range.endColumn),
        ])
    }

    /// The shared Chat DTO predates nullable session state. New observations
    /// must distinguish an absent owner from an observed clean session while
    /// leaving the Chat-only wire contract unchanged.
    static func researchDocumentValue(_ document: AgentChatDocumentObservation, hasRetainedSession: Bool) -> MCPJSONValue {
        var value = document.jsonValue.objectValue!
        if !hasRetainedSession, var note = value["active_note"]?.objectValue {
            for flag in ["dirty", "saving", "conflict"] { note[flag] = .null }
            value["active_note"] = .object(note)
        }
        return .object(value)
    }

    static func page(_ items: [MCPJSONValue], offset: Int, limit: Int) -> MCPJSONValue {
        let boundedOffset = min(offset, items.count)
        let page = Array(items.dropFirst(boundedOffset).prefix(limit))
        let end = boundedOffset + page.count
        return .object([
            "offset": .integer(offset), "limit": .integer(limit), "total": .integer(items.count),
            "has_more": .bool(end < items.count), "next_offset": end < items.count ? .integer(end) : .null,
            "items": .array(page),
        ])
    }

    static func admitPage(_ arguments: [String: MCPJSONValue], inventory: MCPJSONValue) throws -> (Int, Int, DocumentFingerprint) {
        let offset = try integer(arguments["offset"], default: 0, range: 0...Int.max)
        let limit = try integer(arguments["limit"], default: 20, range: 1...100)
        let maximumCount: Int
        if let items = inventory.arrayValue {
            maximumCount = items.count
        } else {
            maximumCount = inventory.objectValue?.values.compactMap { $0.arrayValue?.count }.max() ?? 0
        }
        guard offset <= maximumCount else { throw failure(.invalidRequest) }
        let current = try fingerprint(inventory)
        if let expected = arguments["expected_listing_fingerprint"] {
            guard try expectedFingerprint(expected) == current else { throw failure(.staleRevision) }
        } else if offset > 0 {
            throw failure(.invalidRequest)
        }
        return (offset, limit, current)
    }

    /// UTF-8 paging never normalizes BOM, line endings or Unicode. A caller
    /// cannot start inside a scalar; a bounded end advances to the last full one.
    static func exactSlice(_ source: String, start: Int, maximum: Int) throws -> (text: String, end: Int) {
        let bytes = source.utf8
        guard start >= 0, start <= bytes.count, maximum > 0 else { throw failure(.invalidRequest) }
        let lower = bytes.index(bytes.startIndex, offsetBy: start)
        guard lower == bytes.endIndex || bytes[lower] & 0xC0 != 0x80 else { throw failure(.invalidRequest) }
        var end = start + min(maximum, bytes.count - start)
        var upper = bytes.index(bytes.startIndex, offsetBy: end)
        while upper != bytes.endIndex, bytes[upper] & 0xC0 == 0x80 {
            end -= 1
            upper = bytes.index(before: upper)
        }
        guard end > start || start == bytes.count else { throw failure(.invalidRequest) }
        return (String(decoding: bytes[lower..<upper], as: UTF8.self), end)
    }

    static func failure(_ code: ScholiumMCPFailureCode) -> ScholiumMCPFailure {
        .init(
            code: code,
            message: code == .staleRevision
                ? "The requested context changed." : code == .invalidRequest ? "The context request is invalid." : "The requested context is unavailable.",
            recovery: "Observe the intended Scholium window again and use its exact current identities and revision.")
    }
}

private func agentObservationTriptych(_ state: WindowWorkspaceSessionState) -> UUID? { state.assignment?.id }
private func agentObservationRuntime(_ state: WindowWorkspaceSessionState) -> UUID? { state.activeServicesID }

extension WindowModel {
    func agentWindowRecoverySummary() -> MCPJSONValue {
        let research = researchController
        let loaded = research.researchSnapshot != nil
        let documents = documentController
        var errors = [String]()
        if research.agentChangesError != nil { errors.append("agent_changes") }
        if research.pendingChangesError != nil { errors.append("pending_changes") }
        if research.transactionRecoveryError != nil { errors.append("transaction_recovery") }
        if research.interruptedSaveRecoveryError != nil { errors.append("interrupted_save_recovery") }
        if documents.identityResolutionError != nil { errors.append("note_identity") }
        return .object([
            "snapshot_available": .bool(loaded),
            "pending_changes_count": research.pendingChanges.map { .integer($0.count) } ?? .null,
            "agent_changes_count": research.agentChanges.map { .integer($0.count) } ?? .null,
            "transaction_recovery_count": loaded ? .integer(research.transactionRecoveryRecords.count) : .null,
            "interrupted_save_recovery_count": loaded ? .integer(research.interruptedSaveRecoveries.count) : .null,
            "attention_count": workspaceProjectionController.catalog.map { .integer($0.attention.count) } ?? .null,
            "identity_recovering": .bool(documents.isResolvingIdentity),
            "identity_ambiguity_count": workspaceProjectionController.snapshotPhase == nil ? .null : .integer(documents.identityAmbiguities.count),
            "identity_pending_rebinding_count": workspaceProjectionController.snapshotPhase == nil
                ? .null : .integer(documents.pendingIdentityRebindings.count),
            "identity_migration_failure_count": workspaceProjectionController.snapshotPhase == nil
                ? .null : .integer(documents.identityMigrationFailures.count),
            "errors": .array(errors.map(MCPJSONValue.string)),
        ])
    }

    func agentWindowStateSummary() -> MCPJSONValue {
        .object([
            "window_id": .string(nativeWindowID.uuidString.lowercased()),
            "kind": .string(isDetachedDocumentWindow ? "document" : "main"),
            "selected_tab_id": documentTabController.selectedTabID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "tab_count": .integer(documentTabController.tabs.count),
            "restoring": .bool(!shellState.hasCompletedInitialRestore),
            "transferring": .bool(transferInProgress),
            "closing": .bool(windowCloseCoordinator.isPreparingOrFinalized),
        ])
    }

    func observeAgentState(_ request: ScholiumMCPBridgeRequest, admitted: @escaping @MainActor () -> Bool) async throws -> MCPJSONValue {
        let departure = AgentChatObservationDeparture()
        let closeAttempt = windowCloseCoordinator.closeAttemptSequence
        let lifecycleRegistry = nativeWindowCoordinator?.registry
        let terminationAttempt = lifecycleRegistry?.terminationAttemptSequence
        var subscriptions = [
            departure.observing($transferInProgress),
            departure.observing(windowWorkspaceController.$state.map(agentObservationTriptych)),
            departure.observing(windowWorkspaceController.$state.map(agentObservationRuntime)),
            departure.observing(documentController.$selectedDocument),
            departure.observing(documentController.$currentPresentationMode),
            departure.observing(documentController.$chromeProjection.map(\.mode)),
            departure.observing(documentTabController.$tabs),
            departure.observing(documentTabController.$selectedTabID),
        ]
        if let lifecycleRegistry {
            subscriptions.append(departure.observing(lifecycleRegistry.$terminationAttemptSequence))
        }
        if request.conversationToken != nil {
            subscriptions.append(contentsOf: [
                departure.observing(chatSidebarPreferences.$isEnabled),
                departure.observing(shellState.$libraryVisible),
                departure.observing(shellState.$sidebarContent),
                departure.observing(shellState.$selectedWorkspace),
                departure.observingNotification(NSWindow.didResignKeyNotification),
                departure.observingNotification(NSWindow.willBeginSheetNotification),
            ])
        }
        defer { subscriptions.forEach { $0.cancel() } }
        func current() -> Bool {
            !Task.isCancelled && admitted() && departure.isCurrent && !transferInProgress
                && nativeWindowCoordinator?.registry === lifecycleRegistry
                && lifecycleRegistry?.isTerminationAttemptInProgress != true
                && terminationAttempt != UInt64.max && lifecycleRegistry?.terminationAttemptSequence == terminationAttempt
                && (request.conversationToken == nil || (isChatSidebarEnabled && shellState.libraryVisible && shellState.sidebarContent == .chat))
                && !windowCloseCoordinator.isPreparingOrFinalized && windowCloseCoordinator.closeAttemptSequence == closeAttempt
                && request.arguments["triptych_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == workspaceAssignment?.id
                && request.arguments["window_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == nativeWindowID
        }
        guard current() else { throw AgentWindowObservation.failure(.workspaceNotReady) }
        let result: MCPJSONValue
        switch request.tool {
        case .observeWorkspace:
            result = try agentWorkspaceObservation(request.arguments)
        case .observeResearchContext:
            let active = try await agentActiveDocument(includeSource: false, admitted: current)
            guard current() else { throw AgentWindowObservation.failure(.workspaceNotReady) }
            result = try agentResearchContextObservation(request.arguments, document: active.observation)
        case .readContext:
            result = try await readAgentContext(request.arguments, admitted: current)
        default:
            throw AgentWindowObservation.failure(.invalidRequest)
        }
        guard current() else { throw AgentWindowObservation.failure(.workspaceNotReady) }
        return result
    }

    private func agentWindowDetails() -> MCPJSONValue {
        var result = agentWindowStateSummary().objectValue!
        result["selected_role"] = .string(AgentWindowObservation.role(shellState.selectedWorkspace.vaultRole))
        result["sidebar"] = .object([
            "visible": .bool(shellState.libraryVisible), "content": .string(shellState.sidebarContent == .chat ? "chat" : "library"),
        ])
        result["inspector"] = .object(["visible": .bool(shellState.inspector.isVisible), "mode": .string(shellState.inspector.mode.rawValue)])
        result["focus_layout"] = .bool(shellState.isFocusLayoutActive)
        result["recovery"] = agentWindowRecoverySummary()
        result["software"] = .object([
            "version": (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map(MCPJSONValue.string) ?? .null,
            "build": (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).map(MCPJSONValue.string) ?? .null,
        ])
        var phase = "unavailable"
        if let snapshotPhase = workspaceProjectionController.snapshotPhase { phase = snapshotPhase.isComplete ? "complete" : "opening" }
        var derived = "unavailable"
        switch workspaceProjectionController.derivedRefreshStatus {
        case .opening: derived = "opening"
        case .current: derived = "current"
        case .stale: derived = "stale"
        case .failed: derived = "failed"
        case nil: break
        }
        let search = workspaceProjectionController.searchGeneration
        let graph = workspaceProjectionController.linkGraph
        var errors = [String]()
        if workspaceProjectionController.catalogError != nil { errors.append("catalog") }
        if windowWorkspaceController.state.accessRecovery != nil { errors.append("access_recovery") }
        if windowWorkspaceController.state.recoveryMessage != nil { errors.append("workspace_recovery") }
        result["workspace"] = .object([
            "availability": .string(windowWorkspaceController.activeCapabilities == nil ? "unavailable" : phase),
            "phase": .string(phase),
            "generated_at": workspaceProjectionController.catalog.map { .string(ISO8601DateFormatter().string(from: $0.generatedAt)) } ?? .null,
            "refreshing": .bool(workspaceProjectionController.isRefreshingCatalog), "derived_state": .string(derived),
            "search_generation": search.map { .object(["sequence": .integer($0.sequence), "manifest_sha256": .string($0.sourceManifestHash)]) } ?? .null,
            "graph_generation": graph.map { .object(["sequence": .integer($0.generation), "manifest_sha256": .string($0.sourceManifestHash)]) } ?? .null,
            "errors": .array(errors.map(MCPJSONValue.string)),
        ])
        var windowErrors = [String]()
        if shellState.windowSessionPersistenceError != nil { windowErrors.append("window_session") }
        if !shellState.operationIssues.isEmpty { windowErrors.append("operation_issue") }
        result["errors"] = .array(windowErrors.map(MCPJSONValue.string))
        return .object(result)
    }

    private func agentNoteReference(_ reference: VaultNoteReference) -> MCPJSONValue? {
        guard let assignment = workspaceAssignment,
            assignment.vaults.values.contains(where: { $0.id == reference.vaultID }),
            reference.vaultRole != .other, AgentWindowObservation.validPath(reference.relativePath)
        else { return nil }
        return .object([
            "vault_id": .string(reference.vaultID.uuidString.lowercased()),
            "note_id": reference.stableNoteID.flatMap(UUID.init(uuidString:)).map { .string($0.uuidString.lowercased()) } ?? .null,
            "role": .string(AgentWindowObservation.role(reference.vaultRole)), "relative_path": .string(reference.relativePath),
        ])
    }

    private func agentTabValue(_ tab: DocumentTabItem) -> MCPJSONValue {
        let session = documentController.peekRetainedSession(for: tab.document.editingTarget)
        var note: MCPJSONValue = .null
        if let descriptor = tab.document.workspaceDescriptor, var value = agentNoteReference(descriptor.reference)?.objectValue {
            let revision: AgentChatDocumentObservation.Revision
            if session?.hasUnsavedChanges == true {
                revision = .unavailable(.sourceSnapshotUnavailable)
            } else if let saved = documentController.snapshots[descriptor.sessionKey] {
                revision = .savedSource(saved.fingerprint)
            } else {
                revision = .unavailable(.loading)
            }
            value["mode"] = .string(
                AgentWindowObservation.mode(tab.id == documentTabController.selectedTabID ? presentedDocumentMode : session?.presentationMode ?? .read))
            value["revision"] = revision.jsonValue
            value["dirty"] = session.map { .bool($0.hasUnsavedChanges) } ?? .null
            value["saving"] = session.map { .bool($0.isSavingEdit) } ?? .null
            value["conflict"] = session.map { .bool($0.conflict != nil) } ?? .null
            note = .object(value)
        }
        var errors = [String]()
        if session?.editError != nil { errors.append("document_save") }
        if session?.conflict != nil { errors.append("document_conflict") }
        return .object([
            "tab_id": .string(tab.id.uuidString.lowercased()), "selected": .bool(tab.id == documentTabController.selectedTabID),
            "document_surface": .string(note == .null ? "unavailable" : "triptych_note"),
            "note": note, "errors": .array(errors.map(MCPJSONValue.string)),
        ])
    }

    private func agentWorkspaceObservation(_ arguments: [String: MCPJSONValue]) throws -> MCPJSONValue {
        let items = documentTabController.tabs.map(agentTabValue)
        // Inventory pagination binds identities and order, not frequently
        // changing save flags or every inactive editor's content.
        let inventory: [MCPJSONValue] = documentTabController.tabs.map { tab in
            .object([
                "tab_id": MCPJSONValue.string(tab.id.uuidString.lowercased()),
                "note": tab.document.workspaceDescriptor.flatMap { agentNoteReference($0.reference) } ?? .null,
            ])
        }
        let (offset, limit, fingerprint) = try AgentWindowObservation.admitPage(arguments, inventory: .array(inventory))
        return .object([
            "window": agentWindowDetails(), "listing_fingerprint": AgentWindowObservation.fingerprintValue(fingerprint),
            "tabs": AgentWindowObservation.page(items, offset: offset, limit: limit),
        ])
    }

    private func agentResearchContextObservation(_ arguments: [String: MCPJSONValue], document: AgentChatDocumentObservation) throws -> MCPJSONValue {
        let library = discoveryController.library
        let catalogReferences = Dictionary(
            (workspaceProjectionController.catalog?.notes ?? []).map {
                (VaultQualifiedNoteID(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath), $0.reference)
            },
            uniquingKeysWith: { first, _ in first })
        let libraryItems: [MCPJSONValue] = library.selectedRowIDs.sorted().compactMap { path in
            guard AgentWindowObservation.validPath(path), let vaultID = library.selectionScope?.vaultID,
                workspaceAssignment?.vaults.values.contains(where: { $0.id == vaultID }) == true
            else { return nil }
            let reference = catalogReferences[VaultQualifiedNoteID(vaultID: vaultID, relativePath: path)]
            return .object([
                "kind": .string(reference == nil ? "folder_or_unavailable" : "note"),
                "vault_id": .string(vaultID.uuidString.lowercased()), "relative_path": .string(path),
                "note": reference.flatMap(agentNoteReference) ?? .null,
            ])
        }
        let search = discoveryController.search
        let searchItems: [MCPJSONValue] = search.results.compactMap { result in
            guard case .note(let note) = result,
                let identity = agentNoteReference(
                    .init(
                        vaultID: note.vaultID, vaultName: note.vaultName, vaultRole: note.vaultRole, relativePath: note.relativePath,
                        stableNoteID: note.stableNoteID))
            else { return nil }
            return .object([
                "result_id": .string(note.resultID), "selected": .bool(search.selectedResultID == note.resultID),
                "note": identity, "fingerprint": AgentWindowObservation.fingerprintValue(note.fingerprint),
                "source_locator": note.sourceRange.map(AgentWindowObservation.locator) ?? .null,
            ])
        }
        let related = researchController.relatedMaterials
        let relatedItems: [MCPJSONValue] = related.cards.compactMap { card in
            guard let identity = agentNoteReference(card.reference) else { return nil }
            return .object([
                "passage_id": .string(card.id), "note": identity,
                "fingerprint": AgentWindowObservation.fingerprintValue(card.candidate.fingerprint),
                "source_locator": AgentWindowObservation.locator(card.passage.range),
            ])
        }
        let kept = researchController.keptPassages
        let keptLifetimes = kept.observedEntryLifetimes
        let keptItems: [MCPJSONValue] = kept.entries.compactMap { entry in
            guard let identity = agentNoteReference(entry.reference) else { return nil }
            return .object([
                "kept_passage_id": .string(entry.id), "note": identity,
                "fingerprint": AgentWindowObservation.fingerprintValue(entry.fingerprint),
                "source_locator": AgentWindowObservation.locator(entry.range),
                "action_locator": AgentWindowObservation.locator(entry.sourceRange), "origin": .string("kept_snapshot"),
            ])
        }
        let inventory: MCPJSONValue = .object([
            "library": .array(libraryItems), "search": .array(searchItems), "related_material": .array(relatedItems), "kept_passages": .array(keptItems),
            "kept_lifetimes": .array(
                kept.entries.map { entry in
                    .object(["id": .string(entry.id), "lifetime": keptLifetimes[entry.id].map { .string($0.uuidString.lowercased()) } ?? .null])
                }),
        ])
        let (offset, limit, fingerprint) = try AgentWindowObservation.admitPage(arguments, inventory: inventory)
        let hasRetainedSession =
            currentDocumentDescriptor.map {
                documentController.peekRetainedSession(for: .workspace($0.sessionKey)) != nil
            } ?? false
        var result = AgentWindowObservation.researchDocumentValue(document, hasRetainedSession: hasRetainedSession).objectValue!
        result["window"] = agentWindowDetails()
        result["listing_fingerprint"] = AgentWindowObservation.fingerprintValue(fingerprint)
        result["library"] = .object([
            "role": .string(AgentWindowObservation.role(library.workspaceSlot.vaultRole)), "source_scope": .string("library"),
            "loading": .bool(library.sourceIsLoading), "has_error": .bool(library.sourceError != nil),
            "unavailable_reference_count": .integer(library.selectedRowIDs.count - libraryItems.count),
            "selection": AgentWindowObservation.page(libraryItems, offset: offset, limit: limit),
        ])
        result["search"] = .object([
            "scope": .string(search.criteria.scope.rawValue), "query_present": .bool(!search.criteria.query.isEmpty),
            "query_text_omitted": .bool(true), "running": .bool(search.isRunning),
            "availability": .string(agentSearchAvailability(search.availability)),
            "has_error": .bool(search.executionIssue != nil), "has_more_results": .bool(search.hasMore),
            "unavailable_reference_count": .integer(search.results.count - searchItems.count),
            "indeterminate_document_count": .integer(search.indeterminateDocumentCount),
            "results": AgentWindowObservation.page(searchItems, offset: offset, limit: limit),
        ])
        result["related_material"] = .object([
            "loading": .bool(related.isLoading), "did_search": .bool(related.didSearch), "has_error": .bool(related.issue != nil),
            "needs_refresh": .bool(related.needsRefresh), "context_changed": .bool(related.contextChanged),
            "omitted_count": .integer(related.omittedCount), "seed_text_omitted": .bool(true),
            "unavailable_reference_count": .integer(related.cards.count - relatedItems.count),
            "passages": AgentWindowObservation.page(relatedItems, offset: offset, limit: limit),
        ])
        result["kept_passages"] = .object([
            "has_error": .bool(kept.errorMessage != nil), "unavailable_reference_count": .integer(kept.entries.count - keptItems.count),
            "passages": AgentWindowObservation.page(keptItems, offset: offset, limit: limit),
        ])
        return .object(result)
    }

    private func agentSearchAvailability(_ availability: SearchAvailability) -> String {
        switch availability {
        case .unavailable: "unavailable"
        case .building: "building"
        case .current: "current"
        case .limited: "limited"
        case .refreshing: "refreshing"
        case .stale: "stale"
        case .failed: "failed"
        }
    }

    private func agentActiveDocument(includeSource: Bool, admitted: @escaping @MainActor () -> Bool) async throws -> (
        observation: AgentChatDocumentObservation, source: String?
    ) {
        guard admitted() else { throw AgentWindowObservation.failure(.workspaceNotReady) }
        guard let descriptor = currentDocumentDescriptor else {
            return (.init(surface: documentController.selectedDocument == nil ? .none : .unavailable), nil)
        }
        guard agentNoteReference(descriptor.reference) != nil,
            descriptor.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == descriptor.sessionKey.noteID
        else { throw AgentWindowObservation.failure(.workspaceNotReady) }
        let session = documentController.peekRetainedSession(for: .workspace(descriptor.sessionKey))
        let mode = presentedDocumentMode
        var source: String?
        let revision: AgentChatDocumentObservation.Revision
        let selection: AgentChatDocumentObservation.Selection
        if let session, mode != .read {
            if includeSource {
                let snapshot = try await session.editorSession.currentAgentSourceSnapshot()
                source = snapshot.source
                revision = .editorSnapshot(snapshot.fingerprint)
                selection = snapshot.selection
            } else {
                (revision, selection) = try await session.editorSession.currentChatMetadata()
            }
        } else if let session, let note = documentController.snapshots[descriptor.sessionKey] {
            if session.hasUnsavedChanges {
                revision = .unavailable(.sourceSnapshotUnavailable)
                selection = .unavailable(.staleRenderer)
            } else {
                revision = .savedSource(note.fingerprint)
                source = includeSource ? note.document.rawContent : nil
                if session.renderedReadFingerprint != note.fingerprint.sha256 {
                    selection = .unavailable(.staleRenderer)
                } else if let readSelection = session.readSelection,
                    let exact = MarkdownReviewSourceSelection.review(readSelection, source: note.document.rawContent)
                {
                    selection = .exactSourceRange(exact.sourceRange.utf16LowerBound..<exact.sourceRange.utf16UpperBound, in: note.document.rawContent)
                } else {
                    selection = session.readSelection == nil ? .none : .unavailable(.sourceMappingUnavailable)
                }
            }
        } else {
            revision = .unavailable(.loading)
            selection = .unavailable(.loading)
        }
        guard admitted(), documentController.selectedDocument?.workspaceDescriptor == descriptor, presentedDocumentMode == mode,
            documentController.peekRetainedSession(for: .workspace(descriptor.sessionKey)) === session
        else { throw AgentWindowObservation.failure(.workspaceNotReady) }
        return (
            .init(
                surface: .triptychNote,
                activeNote: .init(
                    vaultID: descriptor.reference.vaultID, noteID: descriptor.sessionKey.noteID, role: descriptor.reference.vaultRole,
                    relativePath: descriptor.reference.relativePath, mode: mode, revision: revision,
                    dirty: session?.hasUnsavedChanges ?? false, saving: session?.isSavingEdit ?? false,
                    conflict: session?.conflict != nil, selection: selection), hasSaveError: session?.editError != nil), source
        )
    }

    private func readAgentContext(_ arguments: [String: MCPJSONValue], admitted: @escaping @MainActor () -> Bool) async throws -> MCPJSONValue {
        let expected = try AgentWindowObservation.expectedFingerprint(arguments["expected_fingerprint"])
        let start = try AgentWindowObservation.integer(arguments["start_utf8"], default: 0, range: 0...Int.max)
        let maximum = try AgentWindowObservation.integer(arguments["max_utf8"], default: 16_384, range: 1...65_536)
        guard let kind = arguments["kind"]?.stringValue else { throw AgentWindowObservation.failure(.invalidRequest) }
        let text: String
        let origin: String
        let note: MCPJSONValue
        let locator: MCPJSONValue
        var keptCurrent: (() -> Bool)?
        if kind == "kept_passage" {
            guard arguments["expected_start_utf8"] == nil, arguments["expected_end_utf8"] == nil else { throw AgentWindowObservation.failure(.invalidRequest) }
            guard let id = arguments["kept_passage_id"]?.stringValue,
                let entry = researchController.keptPassages.entries.first(where: { $0.id == id }),
                let identity = agentNoteReference(entry.reference)
            else { throw AgentWindowObservation.failure(.notFound) }
            if let requested = arguments["note_id"] {
                guard let noteID = requested.stringValue.flatMap(UUID.init(uuidString:)) else { throw AgentWindowObservation.failure(.invalidRequest) }
                guard entry.reference.stableNoteID.flatMap(UUID.init(uuidString:)) == noteID else { throw AgentWindowObservation.failure(.staleRevision) }
            }
            guard entry.fingerprint == expected else { throw AgentWindowObservation.failure(.staleRevision) }
            let kept = researchController.keptPassages
            guard let lifetime = kept.entryLifetime(for: entry) else { throw AgentWindowObservation.failure(.workspaceNotReady) }
            keptCurrent = { kept.entryLifetime(for: entry) == lifetime }
            text = entry.text
            origin = "kept_snapshot"
            note = identity
            locator = AgentWindowObservation.locator(entry.range)
        } else if kind == "active_note" || kind == "selection" {
            guard arguments["kept_passage_id"] == nil else { throw AgentWindowObservation.failure(.invalidRequest) }
            if kind == "active_note" {
                guard arguments["expected_start_utf8"] == nil, arguments["expected_end_utf8"] == nil else {
                    throw AgentWindowObservation.failure(.invalidRequest)
                }
            } else {
                guard let start = arguments["expected_start_utf8"]?.intValue, let end = arguments["expected_end_utf8"]?.intValue,
                    start >= 0, end > start
                else { throw AgentWindowObservation.failure(.invalidRequest) }
            }
            guard let requestedNote = arguments["note_id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                throw AgentWindowObservation.failure(.invalidRequest)
            }
            guard currentDocumentDescriptor?.sessionKey.noteID == requestedNote else { throw AgentWindowObservation.failure(.staleRevision) }
            let captured = try await agentActiveDocument(includeSource: true, admitted: admitted)
            guard admitted(), let active = captured.observation.activeNote, let source = captured.source else {
                throw AgentWindowObservation.failure(.workspaceNotReady)
            }
            guard active.noteID == requestedNote else { throw AgentWindowObservation.failure(.staleRevision) }
            let current: DocumentFingerprint
            switch active.revision {
            case .savedSource(let fingerprint):
                current = fingerprint
                origin = "saved_source"
            case .editorSnapshot(let fingerprint):
                current = fingerprint
                origin = "editor_snapshot"
            case .unavailable: throw AgentWindowObservation.failure(.workspaceNotReady)
            }
            guard current == expected else { throw AgentWindowObservation.failure(.staleRevision) }
            note = .object([
                "vault_id": .string(active.vaultID.uuidString.lowercased()), "note_id": .string(active.noteID.uuidString.lowercased()),
                "role": .string(AgentWindowObservation.role(active.role)), "relative_path": .string(active.relativePath),
            ])
            if kind == "selection" {
                guard case .range(let extent) = active.selection,
                    arguments["expected_start_utf8"]?.intValue == extent.startUTF8,
                    arguments["expected_end_utf8"]?.intValue == extent.endUTF8
                else { throw AgentWindowObservation.failure(.staleRevision) }
                text = String(decoding: source.utf8.dropFirst(extent.startUTF8).prefix(extent.endUTF8 - extent.startUTF8), as: UTF8.self)
                locator = active.selection.jsonValue
            } else {
                text = source
                locator = .object(["state": .string("whole_note"), "start_utf8": .integer(0), "end_utf8": .integer(source.utf8.count)])
            }
        } else {
            throw AgentWindowObservation.failure(.invalidRequest)
        }
        guard admitted(), keptCurrent?() != false else { throw AgentWindowObservation.failure(.workspaceNotReady) }
        let slice = try AgentWindowObservation.exactSlice(text, start: start, maximum: maximum)
        // Whole-Note source was already captured and compared with expected.
        // Passage snapshots have a distinct material fingerprint.
        let textFingerprint = kind == "active_note" ? expected : DocumentFingerprint(content: text)
        return .object([
            "kind": .string(kind), "origin": .string(origin), "note": note,
            "fingerprint": AgentWindowObservation.fingerprintValue(expected), "source_locator": locator,
            "text_fingerprint": AgentWindowObservation.fingerprintValue(textFingerprint),
            "kept_passage_id": kind == "kept_passage" ? arguments["kept_passage_id"]! : .null,
            "text": .string(slice.text),
            "coverage": .object([
                "basis": .string("context"), "total_utf8": .integer(text.utf8.count), "start_utf8": .integer(start), "end_utf8": .integer(slice.end),
                "has_more": .bool(slice.end < text.utf8.count), "next_start_utf8": slice.end < text.utf8.count ? .integer(slice.end) : .null,
            ]),
        ])
    }
}
