import Combine
import Foundation
import ScholiumApplication
import ScholiumContracts

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
  @Published private(set) var associatedFolders: [String] = []
  @Published private(set) var associationError: String?
  @Published private(set) var authenticatingTool: String?
  @Published private(set) var authorizationURL: URL?
  @Published private(set) var authenticationNotice: String?
  @Published private(set) var authenticationError: String?
  @Published private(set) var toolConnections: [AgentChatToolConnection] = []
  @Published private(set) var toolConfigurationError: String?
  @Published private(set) var toolConfigurationNotice: String?
  static let zoteroServerName = "scholium-zotero"
  @Published private(set) var zoteroLibraryInfo: ZoteroLibraryInfo?
  @Published private(set) var isCheckingZotero = false
  private var zoteroStatusTask: Task<Void, Never>?
  private let zotero: (any ZoteroUseCases)?
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
  private let defaults: UserDefaults
  private var needsRootApplication = false
  init(defaults: UserDefaults = .standard, zotero: (any ZoteroUseCases)? = nil) { self.defaults = defaults; self.zotero = zotero }
  private var folderPreferenceKey: String? {
    configurationHome.map { "agent.methodFolders.\($0.standardizedFileURL.path)" }
  }
  private var savedFolders: [String] {
    folderPreferenceKey.flatMap { defaults.stringArray(forKey: $0) } ?? []
  }
  var mayChange: () -> Bool = { false }
  var isConnected: Bool { runtime != nil }

  /// The bundled protocol is a protected application resource, not part of
  /// the runtime-owned optional Skill inventory.
  var coreProtocolURL: URL? {
    try? ScholiumAgentIntegrationResources.coreProtocolSkillDirectoryURL()
  }

  func attach(_ runtime: CodexAppServer, cwd: URL, home: URL, isShared: Bool, threadID: String?) async {
    detach()
    self.runtime = runtime; self.cwd = cwd
    configurationHome = home; self.isShared = isShared
    associatedFolders = savedFolders
    needsRootApplication = !associatedFolders.isEmpty
    // These are the new process's saved launch roots, not a user configuration edit.
    refresh(threadID: threadID, permitsRootApplication: true)
    await task?.value
  }

  func detach() {
    connectionGeneration = UUID()
    zoteroStatusTask?.cancel(); zoteroStatusTask = nil; zoteroLibraryInfo = nil; isCheckingZotero = false
    authenticationTask?.cancel(); authenticationTask = nil
    authenticatingTool = nil; authorizationURL = nil; authenticationThreadID = nil
    authenticationNotice = nil; authenticationError = nil
    toolConfiguration = nil; toolConnections = []; toolConfigurationError = nil; toolConfigurationNotice = nil
    generation = UUID()
    task?.cancel(); changeTask?.cancel()
    task = nil; changeTask = nil; runtime = nil; cwd = nil
    methods = []; tools = []; methodErrors = []
    methodError = nil; toolError = nil
    isRefreshing = false; isChanging = false; hasMethods = false; hasTools = false
    configurationHome = nil; isShared = false
    requestedThreadID = nil
    associatedFolders = []; associationError = nil; needsRootApplication = false
  }

  func refresh(threadID: String?, applyAssociations: Bool = false) {
    refresh(threadID: threadID, permitsRootApplication: applyAssociations && mayChange())
  }

  private func refresh(threadID: String?, permitsRootApplication: Bool) {
    requestedThreadID = threadID
    if isChanging { tools = []; hasTools = false; return }
    guard let runtime, let cwd, !isChanging else { return }
    if associatedFolders != savedFolders {
      associatedFolders = savedFolders
      needsRootApplication = true
    }
    task?.cancel()
    let request = UUID(); generation = request
    isRefreshing = true; hasMethods = false; hasTools = false
    methods = []; tools = []; methodError = nil; toolError = nil; methodErrors = []
    toolConfiguration = nil; toolConnections = []; toolConfigurationError = nil
    let applyRoots = permitsRootApplication && (needsRootApplication || !associatedFolders.isEmpty)
    if applyRoots { needsRootApplication = true }
    if needsRootApplication && !applyRoots && associationError == nil {
      associationError = String(localized: "Refresh Skills when the current operation finishes to apply folder changes.")
    }
    isChanging = applyRoots
    task = Task { [weak self] in
      guard let self else { return }
      defer { if generation == request { isRefreshing = false; isChanging = false } }
      if applyRoots {
        do {
          try await runtime.setChatMethodFolders(associatedFolders)
          guard generation == request, !Task.isCancelled else { return }
          needsRootApplication = false; associationError = nil
        } catch {
          guard generation == request, !Task.isCancelled else { return }
          associationError = error.localizedDescription
        }
        isChanging = false
      }
      if !needsRootApplication {
      do {
        let inventory = try await runtime.chatMethods(cwd: cwd)
        guard generation == request, !Task.isCancelled else { return }
        methods = inventory.methods; methodErrors = inventory.errors; hasMethods = true
      } catch {
        guard generation == request, !Task.isCancelled else { return }
        methodError = error.localizedDescription
      }
      }
      do {
        let inventory = try await runtime.chatConnectedTools(threadID: requestedThreadID)
        guard generation == request, !Task.isCancelled else { return }
        tools = inventory; hasTools = true
      } catch {
        guard generation == request, !Task.isCancelled else { return }
        toolError = error.localizedDescription
      }
      if let home = configurationHome {
        do {
          let configuration = try await runtime.chatToolConfiguration(home: home)
          guard generation == request, !Task.isCancelled else { return }
          toolConfiguration = configuration; toolConnections = configuration.connections
        } catch {
          guard generation == request, !Task.isCancelled else { return }
          toolConfigurationError = error.localizedDescription
        }
      }
    }
  }

  var canConfigureTools: Bool {
    isConnected && mayChange() && !isChanging && !isRefreshing && authenticatingTool == nil && toolConfiguration != nil
  }

  var zoteroConnection: AgentChatToolConnection? { toolConnections.first { $0.name == Self.zoteroServerName } }
  var usesDefaultZoteroConnection: Bool { toolConfiguration != nil && zoteroConnection == nil }
  var canCheckZotero: Bool { isConnected && zotero != nil && !isCheckingZotero }

  func zoteroToolEdit(executable: URL?) -> AgentChatToolEdit? {
    if zoteroConnection != nil { return editTool(named: Self.zoteroServerName) }
    guard let executable, executable.isFileURL, var edit = editTool() else { return nil }
    edit.connection = .init(name: Self.zoteroServerName, kind: .local, address: executable.path,
      arguments: ZoteroMCPTransportDescriptor.supportedLocal.readOnlyArguments, enabled: true)
    return edit
  }

  func checkZotero() {
    guard canCheckZotero, let zotero else { return }
    let connection = connectionGeneration
    isCheckingZotero = true
    zoteroStatusTask = Task { [weak self] in
      let info = await zotero.libraryInfo()
      guard let self, connectionGeneration == connection, !Task.isCancelled else { return }
      zoteroLibraryInfo = info; isCheckingZotero = false; zoteroStatusTask = nil
    }
  }

  func editTool(named name: String? = nil) -> AgentChatToolEdit? {
    guard canConfigureTools, let home = configurationHome, let snapshot = toolConfiguration else { return nil }
    let connection = name.flatMap { name in toolConnections.first(where: { $0.name == name }) }
    if name != nil && connection?.isEditable != true { return nil }
    return .init(home: home, originalName: name, revision: snapshot.version,
      needsAccessConfirmation: { snapshot.requiresAccessConfirmation($0, originalName: name) },
      connection: connection ?? .init())
  }

  func reloadToolEdit(_ edit: AgentChatToolEdit) async -> AgentChatToolEdit? {
    guard isConnected, !isChanging, !isRefreshing, let runtime, configurationHome == edit.home else { return nil }
    let connection = connectionGeneration
    do {
      let snapshot = try await runtime.chatToolConfiguration(home: edit.home)
      guard connectionGeneration == connection, !Task.isCancelled else { return nil }
      toolConfiguration = snapshot; toolConnections = snapshot.connections
      toolConfigurationError = nil
      return editTool(named: edit.originalName)
    } catch {
      guard connectionGeneration == connection, !Task.isCancelled else { return nil }
      toolConfigurationError = error.localizedDescription
      return nil
    }
  }

  func saveTool(_ edit: AgentChatToolEdit, removing: Bool = false) async -> Bool {
    guard canConfigureTools, let runtime, let snapshot = toolConfiguration,
      configurationHome == edit.home, snapshot.version == edit.revision else {
      toolConfigurationError = String(localized: "The connection or running operation changed. Reload before saving.")
      return false
    }
    let connection = connectionGeneration
    isChanging = true; toolConfigurationError = nil; toolConfigurationNotice = nil
    defer { if connectionGeneration == connection { isChanging = false } }
    do {
      let overridden = try await runtime.writeChatTool(edit.connection, originalName: edit.originalName,
        snapshot: snapshot, removing: removing, reuseAccessSettings: edit.reuseAccessSettings)
      guard connectionGeneration == connection, !Task.isCancelled else { return false }
      if overridden { toolConfigurationNotice = String(localized: "Saved. Another configuration overrides this connection.") }
      isChanging = false
      refresh(threadID: requestedThreadID)
      return true
    } catch {
      guard connectionGeneration == connection, !Task.isCancelled else { return false }
      toolConfigurationError = error.localizedDescription
      return false
    }
  }

  var canChangeAssociations: Bool { isConnected && mayChange() && !isChanging && !isRefreshing }

  func associate(_ directory: URL, threadID: String?) {
    guard canChangeAssociations else {
      associationError = String(localized: "Finish the current operation before changing Skill folders.")
      return
    }
    do {
      let path = try AgentChatMethodFolders.directory(directory).path
      let folders = savedFolders
      setFolders(folders.contains(path) ? folders : folders + [path], threadID: threadID)
    } catch { associationError = error.localizedDescription }
  }

  func removeAssociation(_ path: String, threadID: String?) {
    guard canChangeAssociations, associatedFolders.contains(path) else { return }
    setFolders(savedFolders.filter { $0 != path }, threadID: threadID)
  }

  private func setFolders(_ paths: [String], threadID: String?) {
    guard let key = folderPreferenceKey else { return }
    guard paths != associatedFolders || needsRootApplication else { return }
    associatedFolders = paths
    defaults.set(paths, forKey: key)
    needsRootApplication = true
    refresh(threadID: threadID, applyAssociations: true)
  }

  func contains(_ selection: AgentChatMethodSelection) -> Bool {
    hasMethods && methods.contains { $0.enabled && $0.selection.path == selection.path && $0.selection.name == selection.name }
  }

  func canSignIn(_ server: AgentChatConnectedTool) -> Bool {
    isConnected && !isRefreshing && !isChanging && authenticatingTool == nil
      && tools.contains(server) && (server.authStatus == "notLoggedIn" || server.connectionStatus == "authenticationRequired")
  }

  func signIn(_ server: AgentChatConnectedTool, threadID: String?, open: @escaping @MainActor (URL) -> Void) {
    guard canSignIn(server), let runtime else {
      authenticationError = String(localized: "Tool sign-in is unavailable. Refresh the connection status and try again.")
      return
    }
    let connection = connectionGeneration
    authenticatingTool = server.name; authenticationThreadID = threadID
    authorizationURL = nil; authenticationNotice = nil; authenticationError = nil
    authenticationTask = Task { [weak self] in
      guard let self else { return }
      do {
        let url = try await runtime.chatToolSignIn(name: server.name, threadID: threadID)
        guard connectionGeneration == connection, !Task.isCancelled,
          authenticatingTool == server.name, authenticationThreadID == threadID else { return }
        authorizationURL = url
        open(url)
      } catch {
        guard connectionGeneration == connection, !Task.isCancelled,
          authenticatingTool == server.name, authenticationThreadID == threadID else { return }
        authenticatingTool = nil; authenticationThreadID = nil; authorizationURL = nil
        authenticationError = error.localizedDescription
      }
    }
  }

  func authenticationCompleted(_ params: [String: MCPJSONValue], visibleThreadID: String?) {
    guard let name = params["name"]?.stringValue, name == authenticatingTool,
      params["threadId"]?.stringValue == authenticationThreadID,
      let success = params["success"]?.boolValue else { return }
    authenticatingTool = nil; authenticationThreadID = nil; authorizationURL = nil
    authenticationTask?.cancel(); authenticationTask = nil
    authenticationNotice = success ? String(localized: "Signed In: \(name)") : nil
    authenticationError = success ? nil : params["error"]?.stringValue
      ?? String(localized: "Tool sign-in was not completed.")
    refresh(threadID: visibleThreadID)
  }

  func setEnabled(_ method: AgentChatMethod, enabled: Bool, threadID: String?) {
    guard mayChange(), let runtime, !isChanging, !isRefreshing,
      !method.isProtected, methods.contains(method) else { return }
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
