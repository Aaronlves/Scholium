import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts

struct AgentChatCapabilitySnapshot: Sendable {
    let methods: AgentChatMethodInventory
    let tools: [AgentChatConnectedTool]
    let configuration: CodexChatToolConfiguration
    let skillRoots: [String]
}

enum AgentChatZoteroConnectionState: Equatable {
    case disconnected, checking, available, unavailable
}

/// A stopped turn cannot begin a new capability operation. Once a runtime
/// mutation has been sent, loss of admission makes its outcome uncertain.
@MainActor
func requireAgentCapabilityAdmission(_ admitted: () -> Bool, afterCommit: Bool = false) throws {
    guard admitted() else {
        throw ScholiumMCPFailure(
            code: afterCommit ? .operationUncertain : .invalidRequest,
            message: afterCommit
                ? "The turn ended after the capability change began; its result may have been saved."
                : "The turn ended before the capability operation began.",
            recovery: afterCommit
                ? "Inspect current Scholium capabilities before trying this change again."
                : "Start a new turn and inspect current capabilities before retrying.")
    }
}

/// Connection-scoped runtime observations; installed configuration stays runtime-owned.
@MainActor
final class AgentChatCapabilitiesController: ObservableObject {
    @Published private(set) var methods: [AgentChatMethod] = []
    @Published private(set) var methodErrors: [String] = []
    @Published private(set) var tools: [AgentChatConnectedTool] = []
    @Published private(set) var methodError: String?
    @Published private(set) var toolError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isChanging = false
    @Published private(set) var hasMethods = false
    @Published private(set) var hasTools = false
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var workspaceError: String?
    var skillRoots: [String] { workspaceURL.map { [AgentChatWorkspace.skillsDirectory(in: $0).path] } ?? [] }
    @Published private(set) var authenticatingTool: String?
    @Published private(set) var authorizationURL: URL?
    @Published private(set) var authenticationNotice: String?
    @Published private(set) var authenticationError: String?
    @Published private(set) var authenticationFeedbackTool: String?
    @Published private(set) var toolConnections: [AgentChatToolConnection] = []
    @Published private(set) var toolConfigurationError: String?
    @Published private(set) var toolConfigurationNotice: String?
    @Published private(set) var toolConfigurationErrorTool: String?
    @Published private(set) var toolConfigurationNoticeTool: String?
    private var toolConfiguration: CodexChatToolConfiguration?
    private(set) var configurationHome: URL?
    private(set) var isShared = false
    private var runtime: CodexAppServer?
    private var cwd: URL?
    private var generation = UUID()
    private var task: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var requestedThreadID: String?
    private var connectionGeneration = UUID()
    private var authenticationTask: Task<Void, Never>?
    private var authenticationThreadID: String?
    private var agentAuthenticationThreadIDs: [String: String] = [:]
    private var needsRootApplication = false
    var workspaceReady: Bool { workspaceURL != nil && !needsRootApplication }
    var mayChange: () -> Bool = { false }
    var isConnected: Bool { runtime != nil }

    func attach(_ runtime: CodexAppServer, cwd: URL, home: URL, isShared: Bool, threadID: String?) async {
        detach()
        self.runtime = runtime
        self.cwd = cwd
        configurationHome = home
        self.isShared = isShared
        workspaceURL = cwd
        needsRootApplication = true
        // Each process discovers only its own Triptych's additional Skills.
        refresh(threadID: threadID, permitsRootApplication: true)
        await task?.value
    }

    func detach() {
        connectionGeneration = UUID()
        authenticationTask?.cancel()
        authenticationTask = nil
        authenticatingTool = nil
        authorizationURL = nil
        authenticationThreadID = nil
        agentAuthenticationThreadIDs.removeAll()
        authenticationNotice = nil
        authenticationError = nil
        authenticationFeedbackTool = nil
        toolConfiguration = nil
        toolConnections = []
        toolConfigurationError = nil
        toolConfigurationNotice = nil
        toolConfigurationErrorTool = nil
        toolConfigurationNoticeTool = nil
        generation = UUID()
        task?.cancel()
        changeTask?.cancel()
        task = nil
        changeTask = nil
        runtime = nil
        cwd = nil
        methods = []
        tools = []
        methodErrors = []
        methodError = nil
        toolError = nil
        isRefreshing = false
        isChanging = false
        hasMethods = false
        hasTools = false
        configurationHome = nil
        isShared = false
        requestedThreadID = nil
        workspaceURL = nil
        workspaceError = nil
        needsRootApplication = false
    }

    func refresh(threadID: String?, reloadWorkspace: Bool = false) {
        refresh(threadID: threadID, permitsRootApplication: reloadWorkspace && mayChange())
    }

    private func refresh(threadID: String?, permitsRootApplication: Bool) {
        requestedThreadID = threadID
        if isChanging {
            tools = []
            hasTools = false
            return
        }
        guard let runtime, let cwd, !isChanging else { return }
        task?.cancel()
        let request = UUID()
        generation = request
        isRefreshing = true
        hasMethods = false
        hasTools = false
        methods = []
        tools = []
        methodError = nil
        toolError = nil
        methodErrors = []
        toolConfiguration = nil
        toolConnections = []
        toolConfigurationError = nil
        toolConfigurationErrorTool = nil
        let applyRoots = permitsRootApplication
        if applyRoots { needsRootApplication = true }
        if needsRootApplication && !applyRoots && workspaceError == nil {
            workspaceError = String(localized: "Refresh Skills when the current operation finishes to reload the workspace.")
        }
        isChanging = applyRoots
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == request {
                    isRefreshing = false
                    isChanging = false
                }
            }
            if applyRoots {
                do {
                    try await runtime.setChatMethodFolders(skillRoots)
                    guard generation == request, !Task.isCancelled else { return }
                    needsRootApplication = false
                    workspaceError = nil
                } catch {
                    guard generation == request, !Task.isCancelled else { return }
                    workspaceError = error.localizedDescription
                }
                isChanging = false
            }
            if !needsRootApplication {
                do {
                    let inventory = try await runtime.chatMethods(cwd: cwd)
                    guard generation == request, !Task.isCancelled else { return }
                    methods = inventory.methods
                    methodErrors = inventory.errors
                    hasMethods = true
                } catch {
                    guard generation == request, !Task.isCancelled else { return }
                    methodError = error.localizedDescription
                }
            }
            do {
                let inventory = try await runtime.chatConnectedTools(threadID: requestedThreadID)
                guard generation == request, !Task.isCancelled else { return }
                tools = inventory
                hasTools = true
            } catch {
                guard generation == request, !Task.isCancelled else { return }
                toolError = error.localizedDescription
            }
            if let home = configurationHome {
                do {
                    let configuration = try await runtime.chatToolConfiguration(home: home)
                    guard generation == request, !Task.isCancelled else { return }
                    toolConfiguration = configuration
                    toolConnections = configuration.connections
                } catch {
                    guard generation == request, !Task.isCancelled else { return }
                    toolConfigurationErrorTool = nil
                    toolConfigurationError = error.localizedDescription
                }
            }
        }
    }

    var canConfigureTools: Bool {
        isConnected && mayChange() && !isChanging && !isRefreshing && authenticatingTool == nil && toolConfiguration != nil
    }

    /// Chat uses Scholium's bundled Zotero MCP connection. It is managed by
    /// the application and is intentionally not a user-editable connection.
    var zoteroConnectionState: AgentChatZoteroConnectionState {
        guard isConnected else { return .disconnected }
        if isRefreshing { return .checking }
        if toolConnections.contains(where: {
            $0.name.caseInsensitiveCompare("scholium-zotero") == .orderedSame && $0.enabled
        }) {
            return .available
        }
        if tools.contains(where: { $0.name.caseInsensitiveCompare("scholium-zotero") == .orderedSame }) { return .available }
        // The connection is injected into each Chat thread rather than the
        // user's global Codex config. Once this runtime has loaded its tool
        // configuration, the managed helper is available for the next turn.
        return toolConfiguration != nil ? .available : .unavailable
    }

    func editTool(named name: String? = nil) -> AgentChatToolEdit? {
        guard canConfigureTools, let home = configurationHome, let snapshot = toolConfiguration else { return nil }
        let connection = name.flatMap { name in toolConnections.first(where: { $0.name == name }) }
        if name != nil && connection?.isEditable != true { return nil }
        return .init(
            home: home, originalName: name, revision: snapshot.version,
            needsAccessConfirmation: { snapshot.requiresAccessConfirmation($0, originalName: name) },
            connection: connection ?? .init())
    }

    func reloadToolEdit(_ edit: AgentChatToolEdit) async -> AgentChatToolEdit? {
        guard isConnected, !isChanging, !isRefreshing, let runtime, configurationHome == edit.home else { return nil }
        let connection = connectionGeneration
        toolConfigurationError = nil
        toolConfigurationErrorTool = edit.connection.name
        do {
            let snapshot = try await runtime.chatToolConfiguration(home: edit.home)
            guard connectionGeneration == connection, !Task.isCancelled else { return nil }
            toolConfiguration = snapshot
            toolConnections = snapshot.connections
            toolConfigurationError = nil
            return editTool(named: edit.originalName)
        } catch {
            guard connectionGeneration == connection, !Task.isCancelled else { return nil }
            toolConfigurationErrorTool = edit.connection.name
            toolConfigurationError = error.localizedDescription
            return nil
        }
    }

    func saveTool(_ edit: AgentChatToolEdit, removing: Bool = false) async -> Bool {
        toolConfigurationErrorTool = edit.connection.name
        guard canConfigureTools, let runtime, let snapshot = toolConfiguration,
            configurationHome == edit.home, snapshot.version == edit.revision
        else {
            toolConfigurationError = String(localized: "The connection or running operation changed. Reload before saving.")
            return false
        }
        let connection = connectionGeneration
        isChanging = true
        toolConfigurationError = nil
        toolConfigurationNotice = nil
        toolConfigurationNoticeTool = edit.connection.name
        defer { if connectionGeneration == connection { isChanging = false } }
        do {
            let overridden = try await runtime.writeChatTool(
                edit.connection, originalName: edit.originalName,
                snapshot: snapshot, removing: removing, reuseAccessSettings: edit.reuseAccessSettings)
            guard connectionGeneration == connection, !Task.isCancelled else { return false }
            if overridden {
                toolConfigurationNoticeTool = edit.connection.name
                toolConfigurationNotice = String(localized: "Saved. Another configuration overrides this connection.")
            }
            isChanging = false
            refresh(threadID: requestedThreadID)
            return true
        } catch {
            guard connectionGeneration == connection, !Task.isCancelled else { return false }
            toolConfigurationErrorTool = edit.connection.name
            toolConfigurationError = error.localizedDescription
            return false
        }
    }

    func contains(_ selection: AgentChatMethodSelection) -> Bool {
        hasMethods && methods.contains { $0.enabled && $0.selection.path == selection.path && $0.selection.name == selection.name }
    }

    func canSignIn(_ server: AgentChatConnectedTool) -> Bool {
        isConnected && !isRefreshing && !isChanging && authenticatingTool == nil && agentAuthenticationThreadIDs.isEmpty
            && tools.contains(server) && (server.authStatus == "notLoggedIn" || server.connectionStatus == "authenticationRequired")
    }

    func signIn(_ server: AgentChatConnectedTool, threadID: String?, open: @escaping @MainActor (URL) -> Void) {
        authenticationFeedbackTool = server.name
        authenticationNotice = nil
        guard canSignIn(server), let runtime else {
            authenticationError = String(localized: "Tool sign-in is unavailable. Refresh the connection status and try again.")
            return
        }
        let connection = connectionGeneration
        authenticatingTool = server.name
        authenticationThreadID = threadID
        authorizationURL = nil
        authenticationNotice = nil
        authenticationError = nil
        authenticationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await runtime.chatToolSignIn(name: server.name, threadID: threadID)
                guard connectionGeneration == connection, !Task.isCancelled,
                    authenticatingTool == server.name, authenticationThreadID == threadID
                else { return }
                authorizationURL = url
                open(url)
            } catch {
                guard connectionGeneration == connection, !Task.isCancelled,
                    authenticatingTool == server.name, authenticationThreadID == threadID
                else { return }
                authenticatingTool = nil
                authenticationThreadID = nil
                authorizationURL = nil
                authenticationFeedbackTool = server.name
                authenticationNotice = nil
                authenticationError = error.localizedDescription
            }
        }
    }

    func authenticationCompleted(_ params: [String: MCPJSONValue], visibleThreadID: String?) {
        guard let name = params["name"]?.stringValue,
            let success = params["success"]?.boolValue
        else { return }
        let uiAuthentication =
            name == authenticatingTool
            && params["threadId"]?.stringValue == authenticationThreadID
        let agentThread = agentAuthenticationThreadIDs[name]
        let agentAuthentication =
            agentThread.map { thread in
                params["threadId"]?.stringValue == (thread.isEmpty ? nil : thread)
            } ?? false
        guard uiAuthentication || agentAuthentication else { return }
        authenticationFeedbackTool = name
        if agentAuthentication, let agentThread {
            agentAuthenticationThreadIDs.removeValue(forKey: name)
            authenticationNotice = success ? String(localized: "Signed In: \(name)") : nil
            authenticationError =
                success
                ? nil
                : params["error"]?.stringValue
                    ?? String(localized: "Tool sign-in was not completed.")
            let refreshThread = agentThread.isEmpty ? nil : agentThread
            refresh(threadID: refreshThread)
            return
        }
        authenticatingTool = nil
        authenticationThreadID = nil
        authorizationURL = nil
        authenticationTask?.cancel()
        authenticationTask = nil
        authenticationNotice = success ? String(localized: "Signed In: \(name)") : nil
        authenticationError =
            success
            ? nil
            : params["error"]?.stringValue
                ?? String(localized: "Tool sign-in was not completed.")
        refresh(threadID: visibleThreadID)
    }

    /// Agent-facing capability operations deliberately do not use `mayChange`.
    /// The native Settings surface still waits for idle executions, while an
    /// active Chat turn may inspect capabilities, change Skill enablement or
    /// request tool sign-in. MCP connection writes remain researcher-only;
    /// active-turn admission never substitutes for native configuration consent.
    func agentCapabilitySnapshot(threadID: String?, admitted: @MainActor () -> Bool) async throws -> AgentChatCapabilitySnapshot {
        try requireAgentCapabilityAdmission(admitted)
        guard let runtime, let cwd, let home = configurationHome else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "The Agent runtime is not connected.", recovery: "Connect the Scholium Agent runtime and inspect capabilities again.")
        }
        guard !needsRootApplication else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady, message: "The Triptych Skills could not be loaded.", recovery: "Refresh Skills in Settings or reconnect Chat.")
        }
        let roots = skillRoots
        let methods = try await runtime.chatMethods(cwd: cwd)
        try requireAgentCapabilityAdmission(admitted)
        let tools = try await runtime.chatConnectedTools(threadID: threadID)
        try requireAgentCapabilityAdmission(admitted)
        let configuration = try await runtime.chatToolConfiguration(home: home)
        try requireAgentCapabilityAdmission(admitted)
        return .init(methods: methods, tools: tools, configuration: configuration, skillRoots: roots)
    }

    func agentSetSkill(
        path: String, name: String?, enabled: Bool, threadID: String?, admitted: @MainActor () -> Bool
    ) async throws -> AgentChatMethod {
        try requireAgentCapabilityAdmission(admitted)
        guard let runtime, let cwd else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "The Agent runtime is not connected.", recovery: "Connect the Scholium Agent runtime and retry the Skill change.")
        }
        guard !isChanging else {
            throw ScholiumMCPFailure(
                code: .conflict,
                message: "Another Skill or tool configuration change is in progress.", recovery: "Inspect capabilities again after that change finishes.")
        }
        let connection = connectionGeneration
        isChanging = true
        defer { if connectionGeneration == connection { isChanging = false } }
        let inventory = try await runtime.chatMethods(cwd: cwd)
        try requireAgentCapabilityAdmission(admitted)
        guard connectionGeneration == connection else { throw CancellationError() }
        guard
            let method = inventory.methods.first(where: {
                $0.selection.path == path && (name == nil || $0.selection.name == name)
            })
        else {
            throw ScholiumMCPFailure(
                code: .notFound,
                message: "The requested Skill is not present in the current runtime inventory.",
                recovery: "Inspect capabilities and use the exact current Skill path.")
        }
        guard !method.isProtected else {
            throw ScholiumMCPFailure(
                code: .invalidRequest,
                message: "The Scholium Core Protocol is protected and cannot be disabled.", recovery: "Choose a researcher-owned Skill instead.")
        }
        let effective: Bool
        do {
            effective = try await runtime.setChatMethod(method, enabled: enabled)
        } catch {
            throw ScholiumMCPFailure(
                code: .operationUncertain,
                message: "The Skill change was sent, but its result was not confirmed.",
                recovery: "Inspect the current Skill setting before trying again.")
        }
        try requireAgentCapabilityAdmission(admitted, afterCommit: true)
        guard connectionGeneration == connection else {
            throw ScholiumMCPFailure(
                code: .operationUncertain, message: "The Skill change was saved on a replaced connection.",
                recovery: "Inspect the current Skill setting before trying again.")
        }
        isChanging = false
        refresh(threadID: threadID)
        return .init(
            selection: method.selection, description: method.description, enabled: effective,
            scope: method.scope, dependencies: method.dependencies)
    }

    func agentSignIn(name: String, threadID: String?, admitted: @MainActor () -> Bool) async throws -> URL {
        try requireAgentCapabilityAdmission(admitted)
        guard let runtime, !name.isEmpty else {
            throw ScholiumMCPFailure(
                code: .workspaceNotReady,
                message: "Tool sign-in is unavailable.", recovery: "Inspect connected tools and choose an observed connection.")
        }
        guard authenticatingTool == nil, agentAuthenticationThreadIDs.isEmpty else {
            throw ScholiumMCPFailure(
                code: .conflict,
                message: "Another tool sign-in is already waiting.", recovery: "Complete the existing authorization flow before starting another.")
        }
        agentAuthenticationThreadIDs[name] = threadID ?? ""
        let connection = connectionGeneration
        do {
            let tools = try await runtime.chatConnectedTools(threadID: threadID)
            try requireAgentCapabilityAdmission(admitted)
            guard connectionGeneration == connection else { throw CancellationError() }
            guard let tool = tools.first(where: { $0.name == name }) else {
                throw ScholiumMCPFailure(
                    code: .notFound,
                    message: "The requested MCP connection is not in the current runtime inventory.",
                    recovery: "Inspect capabilities and use an observed connection name.")
            }
            guard tool.authStatus == "notLoggedIn" || tool.connectionStatus == "authenticationRequired" else {
                throw ScholiumMCPFailure(
                    code: .invalidRequest,
                    message: "This MCP connection does not currently require sign-in.",
                    recovery: "Inspect its current authentication and connection status before retrying.")
            }
            let url: URL
            do {
                url = try await runtime.chatToolSignIn(name: name, threadID: threadID)
            } catch {
                throw ScholiumMCPFailure(
                    code: .operationUncertain,
                    message: "The sign-in request was sent, but its result was not confirmed.",
                    recovery: "Inspect this connection's sign-in status before trying again.")
            }
            try requireAgentCapabilityAdmission(admitted, afterCommit: true)
            guard connectionGeneration == connection else {
                throw ScholiumMCPFailure(
                    code: .operationUncertain, message: "The sign-in request completed on a replaced connection.",
                    recovery: "Inspect this connection's sign-in status before trying again.")
            }
            return url
        } catch {
            agentAuthenticationThreadIDs.removeValue(forKey: name)
            throw error
        }
    }

    func setEnabled(_ method: AgentChatMethod, enabled: Bool, threadID: String?) {
        guard mayChange(), let runtime, !isChanging, !isRefreshing,
            !method.isProtected, methods.contains(method)
        else { return }
        requestedThreadID = threadID
        isChanging = true
        hasMethods = false
        let current = generation
        changeTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == current { isChanging = false } }
            do {
                let effective = try await runtime.setChatMethod(method, enabled: enabled)
                guard generation == current, !Task.isCancelled else { return }
                isChanging = false
                refresh(threadID: requestedThreadID)
                if effective != enabled { methodError = String(localized: "The runtime kept a different Skill setting.") }
            } catch {
                guard generation == current, !Task.isCancelled else { return }
                isChanging = false
                refresh(threadID: requestedThreadID)
                methodError = error.localizedDescription
            }
        }
    }
}
