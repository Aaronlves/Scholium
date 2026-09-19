import AppKit
import Combine
import ScholiumApplication
import ScholiumContracts

@MainActor
extension AgentChatController {
    func connect(executable: URL, home: URL, helper: URL, signInIfNeeded: Bool = false) {
        guard !isRenewingSettings else { return }
        beginConnection(executable: executable, home: home, helper: helper, signInIfNeeded: signInIfNeeded)
    }

    func beginConnection(executable: URL, home: URL, helper: URL, signInIfNeeded: Bool) {
        guard connectionState == .disconnected, isLoaded else { return }
        connectedExecutable = executable
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
                try await connection.start(executable: executable, home: home, workingDirectory: workspace)
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
                await self.recoverConnection(after: error.localizedDescription)
            }
        }
    }

    func readAccount(_ result: MCPJSONValue) {
        account = result.objectValue?["account"]?.objectValue?["type"]?.stringValue
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
        guard let runtime, connectionState == .ready, !hasActiveExecutions else { return }
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
            } catch { self?.connectionError = error.localizedDescription }
        }
    }
}
