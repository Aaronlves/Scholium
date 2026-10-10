import AppKit
import Combine
import ScholiumApplication
import ScholiumContracts

@MainActor
extension AgentChatController {
    func connect(
        executable: URL, home: URL, helper: URL, signInIfNeeded: Bool = false,
        automaticallyDiscovered: Bool = false
    ) {
        guard !isRenewingSettings else { return }
        beginConnection(
            executable: executable, home: home, helper: helper,
            signInIfNeeded: signInIfNeeded, automaticallyDiscovered: automaticallyDiscovered)
    }

    func beginConnection(
        executable: URL, home: URL, helper: URL, signInIfNeeded: Bool,
        automaticallyDiscovered: Bool = false
    ) {
        guard connectionState == .disconnected, isLoaded else { return }
        connectedExecutable = executable
        connectedAutomaticallyDiscovered = automaticallyDiscovered
        connectionState = .connecting
        connectionError = nil
        let connection = CodexAppServer()
        let connectionToken = UUID()
        runtime = connection
        connectionID = connectionToken
        helperURL = helper
        connectedHome = home

        eventTask = Task { [weak self] in
            for await event in connection.events {
                guard !Task.isCancelled, let self, self.connectionID == connectionToken else { break }
                await self.receive(event)
            }
        }
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard self.connectionID == connectionToken, !Task.isCancelled else { return }
                let directory = try await workspaceDirectory()
                guard self.connectionID == connectionToken, !Task.isCancelled else { return }
                let workspace = try AgentChatWorkspace.prepare(directory, runtimeHome: home)
                workingDirectory = workspace
                try await connection.start(
                    executable: executable, home: home,
                    workingDirectory: workspace,
                    automaticallyDiscovered: automaticallyDiscovered)
                guard self.connectionID == connectionToken else {
                    await connection.close()
                    return
                }
                let initialized = try await connection.request(
                    "initialize",
                    params: [
                        "clientInfo": .object([
                            "name": .string("scholium"), "title": .string("Scholium"),
                            "version": .string(ScholiumProductIdentity.marketingVersion),
                        ]),
                        // Required to receive the full per-command permission profile for approval display.
                        "capabilities": .object(["experimentalApi": .bool(true)]),
                    ])
                self.runtimeVersion = initialized.objectValue?["userAgent"]?.stringValue
                try await connection.notify("initialized")
                let result = try await connection.request("account/read")
                guard self.connectionID == connectionToken else { return }
                self.readAccount(result)
                let list = try await connection.chatModels()
                guard self.connectionID == connectionToken else { return }
                self.models = list
                let defaults = try await connection.chatDefaults()
                guard self.connectionID == connectionToken else { return }
                self.runtimeDefaults = defaults
                await self.capabilities.attach(
                    connection, cwd: workspace, home: home,
                    isShared: home.standardizedFileURL != self.runtimeHome.standardizedFileURL,
                    threadID: self.selected?.threadID)
                guard self.connectionID == connectionToken, !Task.isCancelled else { return }
                self.connectionState = .ready
                self.connectedAt = .now
                self.rememberConnectedAccount()
                if self.account != nil { self.refreshQuota() }
                if let selectedID = self.selectedID { self.refreshHistory(in: selectedID) }
                if signInIfNeeded && self.account == nil { self.login() }
            } catch {
                guard self.connectionID == connectionToken else { return }
                await self.recoverConnection(after: ScholiumErrorLocalization.message(error))
            }
        }
    }

    func readAccount(_ result: MCPJSONValue) {
        account = result.objectValue?["account"]?.objectValue?["type"]?.stringValue
    }

    var canRefreshRuntime: Bool {
        connectionState == .ready && !isRefreshingRuntime && !isRenewingSettings
    }

    /// Refresh managed sign-in before rediscovering models. This reads the
    /// current process without renewing threads, interrupting work or replaying input.
    func refreshRuntime(refreshToken: Bool = true) {
        // Account events invalidate an in-flight snapshot. Coalesce them in the
        // same operation rather than dropping the event or renewing auth again.
        if !refreshToken { runtimeAccountRevision &+= 1 }
        if canRefreshRuntime || !refreshToken {
            // A read begun for the previous account cannot supply this refresh
            // or prevent the newly verified account from reading its own usage.
            quotaTask?.cancel()
            quotaTask = nil
            isRefreshingQuota = false
        }
        guard canRefreshRuntime, let runtime, let connection = connectionID else { return }
        let refresh = UUID()
        runtimeRefreshID = refresh
        isRefreshingRuntime = true
        runtimeRefreshError = nil
        runtimeRefreshedAt = nil
        runtimeRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.runtimeRefreshID == refresh {
                    self.runtimeRefreshID = nil
                    self.runtimeRefreshTask = nil
                    self.isRefreshingRuntime = false
                }
            }
            do {
                var renewToken = refreshToken
                while true {
                    let accountRevision = self.runtimeAccountRevision
                    do {
                        let requestsTokenRenewal = renewToken
                        renewToken = false
                        let result = try await runtime.request(
                            "account/read", params: ["refreshToken": .bool(requestsTokenRenewal)])
                        guard self.connectionID == connection, !Task.isCancelled else { return }
                        guard self.runtimeAccountRevision == accountRevision else { continue }
                        guard let accountValue = result.objectValue?["account"],
                            accountValue == .null || accountValue.objectValue?["type"]?.stringValue != nil
                        else { throw CodexConnectionError.invalidMessage }
                        self.readAccount(result)
                        self.rememberConnectedAccount()
                        if self.account != nil {
                            self.refreshQuota()
                        } else {
                            self.quotaTask?.cancel()
                            self.quotaTask = nil
                            self.isRefreshingQuota = false
                            self.quotas = []
                            self.quotaError = nil
                        }
                        let models = try await runtime.chatModels()
                        let defaults = try await runtime.chatDefaults()
                        guard self.connectionID == connection, !Task.isCancelled else { return }
                        guard self.runtimeAccountRevision == accountRevision else { continue }
                        // Publish a complete catalog/defaults pair. A failed
                        // read keeps it and every saved conversation choice.
                        self.models = models
                        self.runtimeDefaults = defaults
                        self.runtimeRefreshedAt = .now
                        return
                    } catch {
                        guard self.connectionID == connection, !Task.isCancelled else { return }
                        if self.runtimeAccountRevision != accountRevision { continue }
                        throw error
                    }
                }
            } catch {
                guard self.connectionID == connection, !Task.isCancelled else { return }
                self.runtimeRefreshError = ScholiumErrorLocalization.message(error)
            }
        }
    }

    func cancelRuntimeRefresh() {
        runtimeRefreshID = nil
        runtimeRefreshTask?.cancel()
        runtimeRefreshTask = nil
        isRefreshingRuntime = false
        runtimeRefreshError = nil
        runtimeRefreshedAt = nil
    }

    func rememberConnectedAccount() {
        if automaticConnection, account != nil {
            connectionDefaults.set(true, forKey: connectionIntentKey)
        }
    }

    func recoverConnection(after message: String) async {
        if let connectedAt, connectedAt.duration(to: .now) >= .seconds(30) { reconnectAttempt = 0 }
        connectedAt = nil
        let shouldRecover = automaticConnection && connectionDefaults.bool(forKey: connectionIntentKey)
        await closeConnection(retainingAutomaticConnection: shouldRecover)
        guard shouldRecover else {
            connectionError = message
            return
        }
        guard automaticConnection, runtime == nil, connectionState == .disconnected else { return }
        guard reconnectAttempt < 3 else {
            connectionError = message
            return
        }
        let delay = Duration.seconds(1 << reconnectAttempt)
        reconnectAttempt += 1
        connectionError = nil
        connectionState = .connecting
        reconnectTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.automaticConnection, !Task.isCancelled else { return }
            self.connectionState = .disconnected
            self.connectConfigured(automatically: true)
        }
    }

    func disconnectByUser() async {
        connectionDefaults.set(false, forKey: connectionIntentKey)
        await disconnect()
    }

    func login() {
        guard let runtime, connectionState == .ready, !hasActiveExecutions, !isRefreshingRuntime else { return }
        connectionError = nil
        let connectionID = connectionID
        connectionTask = Task { [weak self] in
            do {
                let result = try await runtime.request(
                    "account/login/start", params: ["type": .string("chatgpt")])
                guard self?.connectionID == connectionID else { return }
                guard let raw = result.objectValue?["authUrl"]?.stringValue,
                    let url = URL(string: raw), url.scheme == "https",
                    let host = url.host, host == "auth.openai.com" || host == "chatgpt.com"
                else {
                    throw CodexConnectionError.invalidMessage
                }
                NSWorkspace.shared.open(url)
            } catch { self?.connectionError = ScholiumErrorLocalization.message(error) }
        }
    }
}
