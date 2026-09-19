import AppKit
import Combine
import ScholiumApplication
import ScholiumContracts

@MainActor
extension AgentChatController {
    func admitsDisplay(_ request: ScholiumMCPBridgeRequest, windowID: UUID) -> Bool {
        guard let token = request.conversationToken, let owner = executionID(for: token), selectedID == owner,
            let context = request.runtimeContext, context == runtimeContext(for: token), executions[owner]?.state == .working,
            let scope = executions[owner]?.displayScope, scope.windowID == windowID, displayWindow(owner) == scope
        else { return false }
        return conversation(owner)?.isAvailable == true
    }

    func handle(_ request: ScholiumMCPBridgeRequest) async -> ScholiumMCPBridgeResponse {
        func refusal(_ message: String) -> ScholiumMCPBridgeResponse {
            try! .init(
                requestID: request.requestID,
                error: .init(
                    code: .invalidRequest, message: message,
                    recovery: "Check the active Scholium conversation and its permission setting."))
        }
        guard let requestToken = request.conversationToken,
            let conversationID = executionID(for: requestToken),
            executions[conversationID]?.state == .working,
            let owner = conversation(conversationID), owner.isAvailable == true,
            let context = request.runtimeContext, context == runtimeContext(for: requestToken),
            let admission = executions[conversationID]?.admissionID
        else { return refusal("The conversation is not accepting operations.") }
        func isAdmitted() -> Bool {
            executions[conversationID]?.admissionID == admission
                && runtimeContext(for: requestToken) == context
        }
        let rawTriptych = request.arguments["triptych_id"]?.stringValue
        guard rawTriptych == nil || rawTriptych.flatMap(UUID.init(uuidString:)) == triptychID else {
            return refusal("The operation targets a different Triptych.")
        }
        let messageID = "bridge:\(request.requestID)"
        let operationTurnID = executions[conversationID]?.turnID
        let admittedPermission = executions[conversationID]?.permission ?? .ask
        let kind = AgentChatActivity.Kind.forTool(request.tool)
        let noteID = request.arguments["note_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        let knownPath = owner.messages.reversed().compactMap { message in
            message.activity?.files.first { $0.noteID == noteID && noteID != nil }?.path
        }.first
        let path = request.arguments["relative_path"]?.stringValue ?? knownPath ?? ""
        var activity = AgentChatActivity(
            kind: kind, source: .scholium,
            subject: path.isEmpty ? (request.arguments["query"]?.stringValue ?? "") : path,
            files: path.isEmpty && noteID == nil ? [] : [.init(path: path, noteID: noteID)])
        func record(_ status: AgentChatActivity.Status) {
            activity.status = status
            recordActivity(activity, id: messageID, conversationID: conversationID, turnID: operationTurnID)
            persist()
        }
        record(.running)
        if request.tool.isChatControl {
            let response = await handleCapabilityTool(request, conversationID: conversationID)
            activity.status =
                response.error == nil
                ? .completed : (response.error?.code == .operationUncertain ? .uncertain : .failed)
            activity.detail = response.error.map { $0.message + "\n" + $0.recovery } ?? ""
            recordActivity(activity, id: messageID, conversationID: conversationID, turnID: operationTurnID)
            persist()
            return response
        }
        if kind.isMutation, admittedPermission == .ask {
            var location = path
            var updatePreview: AgentNoteUpdatePreview?
            if request.tool == .updateNote || request.tool == .undoChange || request.tool == .moveNote {
                do {
                    var arguments = request.arguments
                    arguments["triptych_id"] = .string(triptychID.uuidString.lowercased())
                    let preview = try await previewUpdate(.init(tool: request.tool, arguments: arguments))
                    updatePreview = preview
                    location = preview.relativePath
                } catch {
                    guard !Task.isCancelled, isAdmitted() else {
                        record(.interrupted)
                        return refusal("The operation stopped before approval.")
                    }
                    if let failure = error as? ScholiumMCPFailure {
                        activity.detail =
                            failure.code == .noChanges
                            ? String(localized: "The content is unchanged; no write was made.", bundle: .module)
                            : String(localized: "The proposed changes could not be compared. Read the Note again before retrying.", bundle: .module)
                        record(failure.code == .noChanges ? .completed : .failed)
                        return try! .init(requestID: request.requestID, error: failure)
                    }
                    activity.detail = String(localized: "The proposed changes could not be compared. Read the Note again before retrying.", bundle: .module)
                    record(.failed)
                    return refusal("Note comparison failed: \(error.localizedDescription)")
                }
            } else if let note = request.arguments["note_id"] {
                let read = await toolHandler(
                    .init(
                        tool: .readNote,
                        arguments: [
                            "triptych_id": .string(triptychID.uuidString.lowercased()), "note_id": note,
                            "line_count": .integer(1),
                        ]))
                location = read.result?.objectValue?["relative_path"]?.stringValue ?? location
            }
            activity.subject = location
            activity.files = [.init(path: location, noteID: noteID)]
            guard !Task.isCancelled, isAdmitted() else {
                record(.interrupted)
                return refusal("The operation stopped before approval.")
            }
            let content =
                request.arguments["body"]?.stringValue ?? request.arguments["content"]?.stringValue ?? ""
            let detail = updatePreview == nil ? [location, content].filter { !$0.isEmpty }.joined(separator: "\n\n") : location
            let id = UUID()
            record(.waitingForApproval)
            let allowed = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled {
                        continuation.resume(returning: false)
                        return
                    }
                    executions[conversationID]?.approvals.append(
                        .init(
                            id: id, title: Self.operationTitle(request), detail: detail,
                            questions: [], updatePreview: updatePreview))
                    executions[conversationID]?.replies[id] = { reply in
                        if case .note(let allowed) = reply { continuation.resume(returning: allowed) } else { continuation.resume(returning: false) }
                    }
                    notifyInput(in: conversationID)
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.answer(id, allow: false) }
            }
            guard allowed else {
                record(Task.isCancelled || executions[conversationID]?.state != .working ? .interrupted : .declined)
                return refusal("The researcher declined this operation.")
            }
        }
        guard !Task.isCancelled, isAdmitted()
        else {
            record(.interrupted)
            return refusal("The conversation stopped before this operation began.")
        }
        record(.running)
        var arguments = request.arguments
        arguments["triptych_id"] = .string(triptychID.uuidString.lowercased())
        if request.tool == .showNote {
            guard let scope = executions[conversationID]?.displayScope, admitsDisplay(request, windowID: scope.windowID),
                arguments["window_id"] == nil || arguments["window_id"]?.stringValue.flatMap(UUID.init(uuidString:)) == scope.windowID
            else {
                activity.detail = String(localized: "Select this conversation in its original window before requesting display.")
                record(.failed)
                return refusal("The display request has no current originating window and conversation.")
            }
            arguments["window_id"] = .string(scope.windowID.uuidString.lowercased())
        }
        let response = await toolHandler(
            .init(
                requestID: request.requestID, tool: request.tool, arguments: arguments,
                conversationToken: request.tool == .showNote ? request.conversationToken : nil,
                runtimeContext: request.tool == .showNote ? request.runtimeContext : nil))
        let result = response.result?.objectValue ?? [:]
        let changeID = result["change_id"]?.stringValue.flatMap(UUID.init(uuidString:))
        activity.status =
            response.error == nil
            ? .completed : (response.error?.code == .operationUncertain ? .uncertain : .failed)
        activity.detail = response.error.map { $0.message + "\n" + $0.recovery } ?? ""
        if response.error?.code == .staleRevision || response.error?.code == .conflict {
            activity.detail = String(
                localized:
                    "The note changed before this edit could be applied. Read it again before deciding how to continue."
            )
        } else if response.error?.code == .operationUncertain {
            activity.detail = String(
                localized:
                    "This operation's result is not confirmed. Check the current file before attempting another edit."
            )
        }
        if response.error?.code == .noChanges {
            activity.status = .completed
            activity.detail = String(localized: "The content is unchanged; no write was made.")
        }
        if request.tool == .previewMove, response.error == nil,
            let from = result["source_relative_path"]?.stringValue, let to = result["relative_path"]?.stringValue
        {
            activity.detail = String(localized: "Preview") + ": " + from + " → " + to
        }
        let returnedPath =
            (request.tool == .previewMove ? result["source_relative_path"]?.stringValue : nil)
            ?? result["relative_path"]?.stringValue
            ?? result["original_location"]?.objectValue?["relative_path"]?.stringValue ?? path
        let returnedID = result["note_id"]?.stringValue.flatMap(UUID.init(uuidString:)) ?? noteID
        if !returnedPath.isEmpty {
            activity.subject = returnedPath
            var effect: AgentChatActivity.File.Effect?
            if response.error?.code == .noChanges { effect = .unchanged }
            if response.error == nil {
                if kind == .read { effect = .read }
                if changeID != nil {
                    switch kind {
                    case .create: effect = .created
                    case .trash: effect = result["moved_to_system_trash"]?.boolValue == true ? .trashed : nil
                    case .update:
                        if let before = result["before_fingerprint"], let after = result["after_fingerprint"],
                            result["readback_verified"]?.boolValue == true
                        {
                            effect = before == after ? .unchanged : .edited
                        }
                    default: break
                    }
                }
            }
            activity.files = [.init(path: returnedPath, noteID: returnedID, effect: effect)]
        }
        if request.tool == .moveNote || request.tool == .undoChange, response.error == nil, result["readback_verified"]?.boolValue == true,
            let effects = result["effects"]?.arrayValue, !effects.isEmpty
        {
            activity.files = effects.compactMap { value in
                guard let effect = value.objectValue, let path = effect["relative_path"]?.stringValue,
                    let id = effect["note_id"]?.stringValue.flatMap(UUID.init(uuidString:))
                else { return nil }
                return .init(path: path, noteID: id, effect: effect["source_relative_path"] == effect["relative_path"] ? .edited : .moved)
            }
        }
        if kind.isMutation, response.error == nil, activity.files.allSatisfy({ $0.effect == nil }) {
            activity.status = .uncertain
        }
        if request.tool == .showNote, response.error == nil {
            activity.detail =
                result["location_requested"]?.boolValue == true
                ? String(localized: "Passage location requested.") : String(localized: "Note activated in the current window.")
            activity.files = [.init(path: returnedPath, noteID: returnedID)]
        }
        if request.tool == .readAttachment, response.error == nil, let filename = result["filename"]?.stringValue {
            activity.subject = filename
            activity.files = [.init(path: filename, effect: .read)]
            let image = result["image"]?.objectValue != nil
            activity.detail =
                image
                ? String(localized: "Rendered image only; no extracted text or OCR.")
                : String(localized: "Text excerpt only; original page appearance is not supplied.")
            if result["text_available"]?.boolValue == false { activity.detail = String(localized: "This selection contains no readable text.") }
            if let page = result["page"]?.intValue { activity.detail += "\n" + String(localized: "Page \(page)") }
            if result["has_more"]?.boolValue == true { activity.detail += "\n" + String(localized: "More text remains in this selection.") }
        }
        if kind == .read, response.error == nil {
            activity.sourceObservation = AgentChatReadObservation.parse(result)
        }
        recordActivity(activity, id: messageID, conversationID: conversationID, changeID: changeID, turnID: operationTurnID)
        persist()
        return response
    }

    private func handleCapabilityTool(
        _ request: ScholiumMCPBridgeRequest,
        conversationID: UUID
    ) async -> ScholiumMCPBridgeResponse {
        do {
            let result: MCPJSONValue
            switch request.tool {
            case .capabilities:
                try agentRequireOnly(request.arguments, keys: [])
                result = try await agentCapabilitiesValue(for: conversationID)
            case .configureSkill:
                result = try await agentConfigureSkill(request.arguments, conversationID: conversationID)
            case .configureTool:
                result = try await agentConfigureTool(request.arguments, conversationID: conversationID)
            case .configureChat:
                result = try await agentConfigureChat(request.arguments, conversationID: conversationID)
            default:
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "The selected tool is not a Chat capability tool.", recovery: "Call the published Scholium Chat capability tool names.")
            }
            return try! .init(requestID: request.requestID, result: result)
        } catch let failure as ScholiumMCPFailure {
            return try! .init(requestID: request.requestID, error: failure)
        } catch is CancellationError {
            return try! .init(
                requestID: request.requestID,
                error: .init(
                    code: .operationUncertain,
                    message: "The capability change was cancelled before its result was confirmed.",
                    recovery: "Inspect Scholium capabilities before attempting the operation again."))
        } catch let error as CodexChatToolConfigurationError {
            return try! .init(
                requestID: request.requestID,
                error: .init(
                    code: .invalidRequest, message: error.localizedDescription,
                    recovery: "Inspect the current capability state and supply the exact fields required by the tool."))
        } catch let error as CocoaError {
            return try! .init(
                requestID: request.requestID,
                error: .init(
                    code: .invalidRequest, message: error.localizedDescription,
                    recovery: "Supply existing absolute local directories and retry."))
        } catch {
            return try! .init(
                requestID: request.requestID,
                error: .init(
                    code: .workspaceNotReady, message: error.localizedDescription,
                    recovery: "Inspect Scholium capabilities and reconnect the Agent runtime if necessary."))
        }
    }

    private func agentCapabilitiesValue(for conversationID: UUID) async throws -> MCPJSONValue {
        let threadID = conversation(conversationID)?.threadID
        let snapshot = try await capabilities.agentCapabilitySnapshot(threadID: threadID)
        return .object([
            "schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion),
            "status": .string("ok"),
            "triptych_id": .string(triptychID.uuidString.lowercased()),
            "conversation_id": .string(conversationID.uuidString.lowercased()),
            "conversation": agentConversationValue(conversationID),
            "skill_roots": .array(snapshot.skillRoots.map(MCPJSONValue.string)),
            "skills": .array(snapshot.methods.methods.map(agentMethodValue)),
            "skill_errors": .array(snapshot.methods.errors.map(MCPJSONValue.string)),
            "connected_tools": .array(snapshot.tools.map(agentConnectedToolValue)),
            "tool_configuration": agentToolConfigurationValue(snapshot.configuration),
        ])
    }

    private func agentConfigureSkill(
        _ arguments: [String: MCPJSONValue],
        conversationID: UUID
    ) async throws -> MCPJSONValue {
        try agentRequireOnly(arguments, keys: ["action", "path", "name"])
        let action = try agentRequiredString(arguments["action"], name: "action")
        let threadID = conversation(conversationID)?.threadID
        switch action {
        case "enable", "disable":
            let path = try agentRequiredString(arguments["path"], name: "path")
            let name = try agentOptionalString(arguments["name"], name: "name")
            let method = try await capabilities.agentSetSkill(path: path, name: name, enabled: action == "enable", threadID: threadID)
            let roots = (try? await capabilities.agentCapabilitySnapshot(threadID: threadID).skillRoots) ?? capabilities.skillRoots
            return agentOK([
                "action": .string(action), "path": .string(method.selection.path),
                "effective_enabled": .bool(method.enabled), "skill_roots": .array(roots.map(MCPJSONValue.string)),
            ])

        default:
            throw agentInvalid("action", "Choose enable or disable.")
        }
    }

    private func agentConfigureTool(
        _ arguments: [String: MCPJSONValue],
        conversationID: UUID
    ) async throws -> MCPJSONValue {
        try agentRequireOnly(
            arguments,
            keys: [
                "action", "expected_version", "name", "kind", "address", "args", "enabled",
                "bearer_token_env_var", "env_vars", "reuse_access_settings",
            ])
        let action = try agentRequiredString(arguments["action"], name: "action")
        let threadID = conversation(conversationID)?.threadID
        if action == "sign_in" {
            let name = try agentRequiredString(arguments["name"], name: "name")
            let url = try await capabilities.agentSignIn(name: name, threadID: threadID)
            return agentOK([
                "action": .string(action), "applies_to": .string("authorization_flow"),
                "authorization_url": .string(url.absoluteString), "configuration": .object([:]),
            ])
        }
        guard ["add", "update", "set_enabled", "remove"].contains(action) else {
            throw agentInvalid("action", "Choose add, update, set_enabled, remove or sign_in.")
        }
        if action == "add" {
            _ = try agentRequiredString(arguments["name"], name: "name")
        }
        let expectedVersion = try agentRequiredString(arguments["expected_version"], name: "expected_version")
        let snapshot = try await capabilities.agentCapabilitySnapshot(threadID: threadID)
        let existing: AgentChatToolConnection?
        if let name = try agentOptionalString(arguments["name"], name: "name") {
            existing = snapshot.configuration.connections.first { $0.name == name }
        } else {
            existing = nil
        }
        if action != "add", existing == nil {
            throw ScholiumMCPFailure(
                code: .notFound,
                message: "The requested MCP connection is not in the current configuration.",
                recovery: "Inspect capabilities and use its exact connection name.")
        }
        if let existing, !existing.isEditable {
            throw CodexChatToolConfigurationError.managedConnection
        }
        let removing = action == "remove"
        let connection = try agentToolConnection(arguments, existing: existing)
        let reuse = try agentOptionalBool(arguments["reuse_access_settings"], name: "reuse_access_settings") ?? false
        let result = try await capabilities.agentWriteTool(
            connection, originalName: existing?.name,
            expectedVersion: expectedVersion, removing: removing, reuseAccessSettings: reuse, threadID: threadID)
        return agentOK([
            "action": .string(action), "applies_to": .string("runtime_configuration"),
            "authorization_url": .null,
            "configuration": agentToolConfigurationValue(result.configuration, overridden: result.overridden),
        ])
    }

    private func agentConfigureChat(
        _ arguments: [String: MCPJSONValue],
        conversationID: UUID
    ) async throws -> MCPJSONValue {
        try agentRequireOnly(arguments, keys: ["action", "permission", "model", "effort", "web_search", "skill_paths"])
        guard let current = conversation(conversationID), current.isAvailable == true else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "The addressed Chat conversation is unavailable.", recovery: "Use the active conversation's current capability context.")
        }
        let action = try agentRequiredString(arguments["action"], name: "action")
        switch action {
        case "set_permission":
            let raw = try agentRequiredString(arguments["permission"], name: "permission")
            guard let permission = AgentChatPermission(rawValue: raw) else {
                throw agentInvalid("permission", "Choose ask or fullAccess.")
            }
            update(in: conversationID) { $0.permission = permission }
        case "set_model":
            let model = try agentOptionalString(arguments["model"], name: "model")
            guard model == nil || models.contains(where: { $0.model == model }) else {
                throw agentInvalid("model", "Choose a model from the current runtime model inventory, or null for its default.")
            }
            update(in: conversationID) {
                if $0.preferences.model != model { $0.contextUsage = nil }
                $0.preferences.model = model
                $0.preferences.effort = nil
            }
        case "set_effort":
            let effort = try agentOptionalString(arguments["effort"], name: "effort")
            let model = model(for: current.preferences)
            guard effort == nil || model?.efforts.contains(effort!) == true else {
                throw agentInvalid("effort", "Choose an effort supported by the conversation's current model, or null for its default.")
            }
            update(in: conversationID) { $0.preferences.effort = effort }
        case "set_web_search":
            let raw = try agentRequiredString(arguments["web_search"], name: "web_search")
            guard let mode = AgentChatPreferences.WebSearch(rawValue: raw) else {
                throw agentInvalid("web_search", "Choose runtimeDefault, disabled, cached or live.")
            }
            update(in: conversationID) { $0.preferences.webSearch = mode }
        case "set_selected_skills":
            let paths = try agentRequiredStringArray(arguments["skill_paths"], name: "skill_paths")
            let inventory = try await capabilities.agentCapabilitySnapshot(threadID: current.threadID)
            var selections: [AgentChatMethodSelection] = []
            for path in paths {
                guard let method = inventory.methods.methods.first(where: { $0.selection.path == path && $0.enabled && !$0.isProtected }) else {
                    throw ScholiumMCPFailure(
                        code: .notFound,
                        message: "A selected Skill is unavailable or disabled in the current runtime.",
                        recovery: "Inspect capabilities and use an enabled researcher-owned Skill path.")
                }
                selections.append(method.selection)
            }
            guard Set(selections.map(\.path)).count == selections.count else {
                throw agentInvalid("skill_paths", "Do not repeat a Skill path.")
            }
            update(in: conversationID) { $0.selectedMethods = selections.isEmpty ? nil : selections }
        default:
            throw agentInvalid("action", "Choose set_permission, set_model, set_effort, set_web_search or set_selected_skills.")
        }
        persist()
        return agentOK([
            "action": .string(action), "applies_to": .string("next_turn"),
            "conversation": agentConversationValue(conversationID),
        ])
    }

    private func agentToolConnection(
        _ arguments: [String: MCPJSONValue],
        existing: AgentChatToolConnection?
    ) throws -> AgentChatToolConnection {
        let name = try agentOptionalString(arguments["name"], name: "name") ?? existing?.name ?? ""
        let kind: AgentChatToolConnection.Kind
        if let raw = try agentOptionalString(arguments["kind"], name: "kind") {
            guard let value = AgentChatToolConnection.Kind(rawValue: raw) else {
                throw agentInvalid("kind", "Choose local or remote.")
            }
            kind = value
        } else if let existing {
            kind = existing.kind
        } else {
            throw agentInvalid("kind", "Add a local or remote MCP connection.")
        }
        let address = try agentOptionalString(arguments["address"], name: "address") ?? existing?.address ?? ""
        let args = try agentOptionalStringArray(arguments["args"], name: "args") ?? existing?.arguments ?? []
        let enabled = try agentOptionalBool(arguments["enabled"], name: "enabled") ?? existing?.enabled ?? true
        let bearer =
            try agentOptionalString(arguments["bearer_token_env_var"], name: "bearer_token_env_var")
            ?? existing?.bearerTokenVariable ?? ""
        let environment =
            try agentOptionalStringArray(arguments["env_vars"], name: "env_vars")
            ?? existing?.environmentVariables ?? []
        return .init(
            name: name, kind: kind, address: address, arguments: args, enabled: enabled,
            bearerTokenVariable: bearer, environmentVariables: environment,
            canEditEnvironmentVariables: existing?.canEditEnvironmentVariables ?? true,
            isEditable: existing?.isEditable ?? true)
    }

    private func agentConversationValue(_ conversationID: UUID) -> MCPJSONValue {
        guard let conversation = conversation(conversationID) else { return .object([:]) }
        return .object([
            "permission": .string(conversation.permission.rawValue),
            "model": conversation.preferences.model.map(MCPJSONValue.string) ?? .null,
            "effort": conversation.preferences.effort.map(MCPJSONValue.string) ?? .null,
            "web_search": .string(conversation.preferences.webSearch.rawValue),
            "thread_id": conversation.threadID.map(MCPJSONValue.string) ?? .null,
            "selected_skill_paths": .array((conversation.selectedMethods ?? []).map { .string($0.path) }),
        ])
    }

    private func agentMethodValue(_ method: AgentChatMethod) -> MCPJSONValue {
        .object([
            "name": .string(method.selection.name), "title": .string(method.selection.title),
            "path": .string(method.selection.path), "description": .string(method.description),
            "enabled": .bool(method.enabled), "scope": .string(method.scope),
            "protected": .bool(method.isProtected), "dependencies": .array(method.dependencies.map(MCPJSONValue.string)),
        ])
    }

    private func agentConnectedToolValue(_ tool: AgentChatConnectedTool) -> MCPJSONValue {
        .object([
            "name": .string(tool.name), "title": .string(tool.title),
            "connection_status": tool.connectionStatus.map(MCPJSONValue.string) ?? .null,
            "auth_status": .string(tool.authStatus), "tools": .array(tool.tools.map(MCPJSONValue.string)),
        ])
    }

    private func agentToolConfigurationValue(_ configuration: CodexChatToolConfiguration, overridden: Bool? = nil) -> MCPJSONValue {
        var value: [String: MCPJSONValue] = [
            "file": .string(configuration.file), "version": .string(configuration.version),
            "connections": .array(
                configuration.connections.map { connection in
                    .object([
                        "name": .string(connection.name), "kind": .string(connection.kind.rawValue),
                        "address": .string(connection.address), "args": .array(connection.arguments.map(MCPJSONValue.string)),
                        "enabled": .bool(connection.enabled), "bearer_token_env_var": .string(connection.bearerTokenVariable),
                        "env_vars": .array(connection.environmentVariables.map(MCPJSONValue.string)),
                        "editable": .bool(connection.isEditable),
                    ])
                }),
        ]
        if let overridden { value["overridden"] = .bool(overridden) }
        return .object(value)
    }

    private func agentOK(_ fields: [String: MCPJSONValue]) -> MCPJSONValue {
        .object(fields.merging(["schema_version": .integer(ScholiumMCPContract.currentToolSchemaVersion), "status": .string("ok")]) { current, _ in current })
    }

    private func agentInvalid(_ field: String, _ message: String) -> ScholiumMCPFailure {
        .init(code: .invalidRequest, message: "Invalid \(field): \(message)", recovery: "Use the published Scholium Chat capability schema.")
    }

    private func agentRequireOnly(_ arguments: [String: MCPJSONValue], keys: Set<String>) throws {
        guard Set(arguments.keys).isSubset(of: keys) else {
            throw agentInvalid("arguments", "The request contains fields outside the published capability schema.")
        }
    }

    private func agentRequiredString(_ value: MCPJSONValue?, name: String) throws -> String {
        guard let string = value?.stringValue, !string.isEmpty else {
            throw agentInvalid(name, "Provide a nonempty string.")
        }
        return string
    }

    private func agentOptionalString(_ value: MCPJSONValue?, name: String) throws -> String? {
        guard let value else { return nil }
        if case .null = value { return nil }
        guard let string = value.stringValue else { throw agentInvalid(name, "Provide a string or null.") }
        return string
    }

    private func agentOptionalBool(_ value: MCPJSONValue?, name: String) throws -> Bool? {
        guard let value else { return nil }
        if case .null = value { return nil }
        guard let bool = value.boolValue else { throw agentInvalid(name, "Provide a boolean or null.") }
        return bool
    }

    private func agentRequiredStringArray(_ value: MCPJSONValue?, name: String) throws -> [String] {
        guard let values = value?.arrayValue else { throw agentInvalid(name, "Provide an array of strings.") }
        return try values.enumerated().map { index, value in
            guard let string = value.stringValue, !string.isEmpty else {
                throw agentInvalid(name, "Item \(index) must be a nonempty string.")
            }
            return string
        }
    }

    private func agentOptionalStringArray(_ value: MCPJSONValue?, name: String) throws -> [String]? {
        guard let value else { return nil }
        if case .null = value { return nil }
        return try agentRequiredStringArray(value, name: name)
    }

    func receive(_ event: [String: MCPJSONValue]) async {
        if await continuationExecution?.receive(event) == true { return }
        guard let method = event["method"]?.stringValue else { return }
        let params = event["params"]?.objectValue ?? [:]
        if method == "mcpServer/oauthLogin/completed" {
            capabilities.authenticationCompleted(params, visibleThreadID: selected?.threadID)
            return
        }
        if method == "skills/changed" {
            capabilities.refresh(threadID: selected?.threadID)
            return
        }
        if let id = event["id"] {
            handleServerRequest(id, method: method, params: params)
            return
        }
        if method == "scholium/disconnected" {
            await recoverConnection(after: String(localized: "Codex disconnected. Unconfirmed operations will not be resent."))
            return
        }
        if method == "account/login/completed" || method == "account/updated" {
            if let runtime, let value = try? await runtime.request("account/read") { readAccount(value) }
            rememberConnectedAccount()
            if account != nil { refreshQuota() } else { quotas = [] }
            return
        }
        if method == "account/rateLimits/updated" {
            // Sparse updates cannot clear or replace a complete quota snapshot.
            refreshQuota()
            return
        }
        guard let thread = params["threadId"]?.stringValue,
            let conversationID = conversations.first(where: { $0.threadID == thread })?.id
        else { return }
        if method == "serverRequest/resolved", let requestID = params["requestId"],
            let approval = executions[conversationID]?.approvals.first(where: { $0.runtimeRequestID == requestID })
        {
            if approval.runtimeApproval != nil {
                recordRuntimeApproval(
                    approval, in: conversationID,
                    status: approval.runtimeDecision.map { $0.isGrant ? .completed : .declined } ?? .interrupted)
                let otherPending =
                    executions[conversationID]?.approvals.contains {
                        $0.id != approval.id && $0.runtimeItemID == approval.runtimeItemID
                    } == true
                if !otherPending, let item = approval.runtimeItemID, let decision = approval.runtimeDecision {
                    update(in: conversationID) { conversation in
                        if let index = conversation.messages.firstIndex(where: { $0.id == "runtime:\(item)" }),
                            conversation.messages[index].activity?.status == .waitingForApproval
                        {
                            conversation.messages[index].activity?.status = decision.isGrant ? .running : .declined
                        }
                    }
                }
            } else {
                recordQuestion(
                    approval, in: conversationID,
                    status: approval.submission == true ? .completed : approval.submission == false ? .declined : .interrupted)
            }
            executions[conversationID]?.approvals.removeAll { $0.id == approval.id }
            executions[conversationID]?.questionAnswers.removeValue(forKey: approval.id)
            executions[conversationID]?.replies.removeValue(forKey: approval.id)
            persist()
            return
        }
        do {
            if let observation = try CodexChatTranscript.event(event) {
                applyTranscript(observation, in: conversationID)
            }
        } catch {
            executions[conversationID]?.error = String(localized: "Codex returned an invalid protocol message.", bundle: .module)
        }
    }

    private func applyTranscript(_ event: CodexChatTranscript.Event, in conversationID: UUID) {
        switch event.content {
        case .contextUsage(let usage):
            update(in: conversationID) { $0.contextUsage = usage }
            persist()
        case .plan(let plan):
            let id = "plan:\(plan.turnID)"
            update(in: conversationID) { conversation in
                if let index = conversation.messages.firstIndex(where: { $0.id == id }) {
                    conversation.messages[index].plan = plan
                } else {
                    var message = AgentChatMessage(id: id, role: .assistant, text: "")
                    message.plan = plan
                    message.turnID = plan.turnID
                    conversation.messages.append(message)
                }
            }
            persist()
        case .turnStarted(let turn):
            attributeTurn(turn, in: conversationID)
            if executions[conversationID]?.completedTurns.contains(turn.id) == false {
                executions[conversationID]?.turnID = turn.id
                update(in: conversationID) { $0.lastRunStatus = .running }
                if executions[conversationID]?.state == .stopping {
                    interruptActiveTurn(in: conversationID)
                } else if executions[conversationID]?.state != .compacting {
                    executions[conversationID]?.state = .working
                }
            }
        case .turnCompleted(let turn):
            guard executions[conversationID]?.completedTurns.contains(turn.id) != true else { return }
            let shouldNotify =
                executions[conversationID]?.turnID == turn.id
                && executions[conversationID]?.state != .stopping
                && executions[conversationID]?.admissionID != nil
                && executions[conversationID]?.completedTurns.contains(turn.id) == false
            let mayAdvanceQueue =
                executions[conversationID]?.turnID == turn.id
                && executions[conversationID]?.state != .stopping
                && turn.status == .completed
            attributeTurn(turn, in: conversationID)
            executions[conversationID]?.completedTurns.insert(turn.id)
            if let active = executions[conversationID]?.turnID, active != turn.id { return }
            if let error = turn.error { executions[conversationID]?.error = error }
            update(in: conversationID) { conversation in
                conversation.lastRunStatus = turn.status.runStatus
                for index in conversation.messages.indices where conversation.messages[index].plan?.turnID == turn.id {
                    conversation.messages[index].plan?.runStatus = turn.status.runStatus
                }
            }
            finishPendingInteractions(in: conversationID)
            update(in: conversationID) { conversation in
                for index in conversation.messages.indices
                where conversation.messages[index].turnID == turn.id
                    && conversation.messages[index].activity?.kind == .compaction
                    && conversation.messages[index].activity?.status.isActive == true
                {
                    conversation.messages[index].activity?.status = .interrupted
                }
            }
            executions[conversationID]?.turnID = nil
            executions[conversationID]?.admissionID = nil
            executions[conversationID]?.state = .ready
            if shouldNotify,
                let notification: AgentChatNotificationRoute.Event = turn.status == .completed
                    ? .completed : turn.status == .failed ? .failed : nil
            {
                executions[conversationID]?.notificationTurnID = turn.id
                notify(notification, in: conversationID, turnID: turn.id)
            }
            for approval in executions[conversationID]?.approvals ?? [] { answer(approval.id, allow: false) }
            persist()
            if !mayAdvanceQueue { executions[conversationID]?.automaticallyAdvancesQueue = false }
            executions[conversationID]?.pendingQueueAdvanceTurnID = mayAdvanceQueue ? turn.id : nil
            drainQueuedMessage(in: conversationID)
        case .item(let item, let completed, let context):
            if !completed, let turn = event.turnID, executions[conversationID]?.completedTurns.contains(turn) == true { return }
            switch item.content {
            case .activity(let value):
                if let context { executions[conversationID]?.runtimeItems[item.id] = context }
                guard !item.isManagedTool, let activity = AgentChatActivityProjection.withLocalizedFailure(value) else { return }
                if activity.kind == .compaction,
                    event.turnID == nil || event.turnID == executions[conversationID]?.turnID
                {
                    if !completed, executions[conversationID]?.state != .stopping { executions[conversationID]?.state = .compacting }
                    if completed, executions[conversationID]?.state == .compacting { executions[conversationID]?.state = .working }
                }
                recordActivity(activity, id: "runtime:\(item.id)", conversationID: conversationID, turnID: event.turnID)
                if completed || activity.kind == .compaction { persist() }
            case .assistant(let text, let phase):
                update(in: conversationID) {
                    if !text.isEmpty, $0.messages.first(where: { $0.id == item.id })?.text != text { $0.unreadAt = Date() }
                    if let index = $0.messages.firstIndex(where: { $0.id == item.id }) {
                        $0.messages[index].text = text
                        $0.messages[index].phase = phase
                        if let turn = event.turnID { $0.messages[index].turnID = turn }
                    } else {
                        var message = AgentChatMessage(id: item.id, role: .assistant, text: text, phase: phase)
                        message.turnID = event.turnID ?? executions[conversationID]?.turnID
                        $0.messages.append(message)
                    }
                }
                retainAsyncQuestions(item, in: conversationID)
                persist()
            case .user(let text, let hasAdditionalMaterial):
                if completed, !hasAdditionalMaterial, let replies = CodexChatAsyncQuestions.decode(text) {
                    receiveQuestionReplies(replies, in: conversationID)
                    persist()
                }
            }
        case .activityDelta(let id, let text):
            update(in: conversationID) { conversation in
                if let index = conversation.messages.firstIndex(where: { $0.id == "runtime:\(id)" }),
                    var activity = conversation.messages[index].activity
                {
                    AgentChatCommandOutput.appending(text, to: &activity)
                    conversation.messages[index].activity = activity
                }
            }
        case .assistantDelta(let id, let text):
            update(in: conversationID) {
                if !text.isEmpty { $0.unreadAt = Date() }
                if let index = $0.messages.firstIndex(where: { $0.id == id }) {
                    $0.messages[index].text += text
                } else {
                    var message = AgentChatMessage(id: id, role: .assistant, text: text)
                    message.turnID = event.turnID ?? executions[conversationID]?.turnID
                    $0.messages.append(message)
                }
            }
        }
    }

    private static func operationTitle(_ request: ScholiumMCPBridgeRequest) -> String {
        switch request.tool {
        case .createNote: String(localized: "Create Note")
        case .updateNote:
            switch request.arguments["mode"]?.stringValue {
            case "source": String(localized: "Replace Note Source")
            case "edits": String(localized: "Edit Note")
            default: String(localized: "Replace Note Body")
            }
        case .moveNote: String(localized: "Move Note")
        case .undoChange: String(localized: "Undo Agent Change?")
        case .trashNote: String(localized: "Move Note to Trash")
        default: String(localized: "Operation")
        }
    }

    private static func displayJSON(_ value: MCPJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func handleServerRequest(
        _ id: MCPJSONValue, method: String, params: [String: MCPJSONValue]
    ) {
        guard let runtime else { return }
        guard id.stringValue != nil || id.intValue != nil,
            !executions.values.contains(where: { $0.approvals.contains { $0.runtimeRequestID == id } })
        else {
            connectionError = ScholiumL10n.string("Codex sent an ambiguous interaction request. Reconnect to continue.")
            connectionID = nil
            invalidateExecutions()
            Task { [weak self] in await self?.disconnect() }
            return
        }
        let supported = [
            "item/commandExecution/requestApproval", "item/fileChange/requestApproval",
            "item/permissions/requestApproval", "item/tool/requestUserInput",
            "mcpServer/elicitation/request",
        ]
        let conversationID = params["threadId"]?.stringValue.flatMap { thread in
            conversations.first { $0.threadID == thread }?.id
        }
        guard supported.contains(method), let conversationID,
            executions[conversationID]?.state == .working
        else {
            if !supported.contains(method) {
                connectionError = String(localized: "Codex requested an interaction this client does not support.")
            }
            Task { try? await runtime.reject(id: id) }
            return
        }
        if method == "item/tool/requestUserInput" {
            handleQuestionRequest(id, params: params, in: conversationID, runtime: runtime)
            return
        }
        handleRuntimeApproval(id, method: method, params: params, in: conversationID, runtime: runtime)
    }

    private func handleRuntimeApproval(
        _ requestID: MCPJSONValue, method: String, params: [String: MCPJSONValue],
        in owner: UUID, runtime: CodexAppServer
    ) {
        do {
            guard let turn = params["turnId"]?.stringValue, executions[owner]?.turnID == turn,
                executions[owner]?.admissionID != nil
            else { throw CodexConnectionError.invalidMessage }
            let itemID: String
            if method == "mcpServer/elicitation/request" {
                itemID = "elicitation:" + Self.displayJSON(requestID)
            } else {
                guard let id = params["itemId"]?.stringValue, !id.isEmpty else { throw CodexConnectionError.invalidMessage }
                itemID = id
            }
            let item = executions[owner]?.runtimeItems[itemID]
            let request = try CodexChatRuntimeApproval.parse(method: method, params: params, item: item)
            let localID = UUID()
            let connection = connectionID
            let approval = AgentChatApproval(
                id: localID, title: "", detail: "", questions: [],
                runtimeRequestID: requestID, turnID: turn,
                runtimeApproval: request.presentation, runtimeItemID: itemID)
            executions[owner]?.approvals.append(approval)
            notifyInput(in: owner)
            update(in: owner) { conversation in
                if let index = conversation.messages.firstIndex(where: { $0.id == "runtime:\(itemID)" }),
                    conversation.messages[index].activity?.status.isActive == true
                {
                    conversation.messages[index].activity?.status = .waitingForApproval
                }
            }
            recordRuntimeApproval(approval, in: owner, status: .waitingForApproval)
            persist()
            executions[owner]?.replies[localID] = { [weak self] reply in
                guard case .runtime(let decision) = reply, let result = try? request.response(for: decision) else { return }
                Task { [weak self] in
                    guard let self, connection != nil, self.connectionID == connection,
                        self.executions[owner]?.turnID == turn,
                        !decision.isGrant || self.executions[owner]?.state == .working
                    else { return }
                    do { try await runtime.respond(id: requestID, result: result) } catch {
                        guard self.connectionID == connection,
                            let index = self.executions[owner]?.approvals.firstIndex(where: { $0.id == localID })
                        else { return }
                        self.executions[owner]?.approvals[index].failure = ScholiumL10n.string(
                            "The response was not confirmed. Stop this turn before continuing.")
                        if let pending = self.executions[owner]?.approvals[index] { self.recordRuntimeApproval(pending, in: owner, status: .uncertain) }
                        self.persist()
                    }
                }
            }
        } catch {
            executions[owner]?.error = ScholiumL10n.string("This operation's scope could not be displayed. No permission was granted.")
            Task { try? await runtime.reject(id: requestID) }
        }
    }

    private func handleQuestionRequest(
        _ requestID: MCPJSONValue, params: [String: MCPJSONValue],
        in owner: UUID, runtime: CodexAppServer
    ) {
        do {
            guard let turn = params["turnId"]?.stringValue, executions[owner]?.turnID == turn
            else { throw CodexConnectionError.invalidMessage }
            let questions = try CodexChatQuestions.parse(params)
            let localID = UUID()
            let connection = connectionID
            var context: String?
            var toolDetails: String?
            if let itemID = params["itemId"]?.stringValue,
                let question = try executions[owner]?.runtimeItems[itemID]?.toolQuestion()
            {
                context = question.identity
                toolDetails = question.arguments.map(Self.displayJSON)
            }
            let approval = AgentChatApproval(
                id: localID, title: "", detail: "", questions: questions,
                toolInputDetails: toolDetails, runtimeRequestID: requestID, turnID: turn,
                runtimeItemID: params["itemId"]?.stringValue, toolQuestionContext: context)
            executions[owner]?.approvals.append(approval)
            notifyInput(in: owner)
            recordQuestion(approval, in: owner, status: .waitingForInput)
            persist()
            executions[owner]?.replies[localID] = { [weak self] reply in
                guard case .questions(let values) = reply else { return }
                let result: MCPJSONValue = .object([
                    "answers": .object(values.mapValues { .object(["answers": .array([.string($0)])]) })
                ])
                Task { [weak self] in
                    guard let self, connection != nil, self.connectionID == connection,
                        self.executions[owner]?.turnID == turn, self.executions[owner]?.state == .working
                    else { return }
                    do { try await runtime.respond(id: requestID, result: result) } catch {
                        guard self.connectionID == connection,
                            let index = self.executions[owner]?.approvals.firstIndex(where: { $0.id == localID })
                        else { return }
                        self.executions[owner]?.approvals[index].failure = String(
                            localized:
                                "The response was not confirmed. Stop this turn before continuing.", bundle: .module)
                        if let pending = self.executions[owner]?.approvals[index] { self.recordQuestion(pending, in: owner, status: .uncertain) }
                        self.persist()
                    }
                }
            }
        } catch {
            executions[owner]?.error = String(localized: "This question could not be displayed. No answer was sent.", bundle: .module)
            Task { try? await runtime.reject(id: requestID) }
        }
    }
}
