import Foundation

/// User-selected operation policy, independent of research acceptance.
public enum AgentChatPermission: String, Codable, CaseIterable, Sendable {
  case ask, fullAccess

  public var approvalPolicy: String { self == .ask ? "on-request" : "never" }
  public var sandbox: String { self == .ask ? "read-only" : "danger-full-access" }
}

public struct AgentChatAttachment: Codable, Equatable, Identifiable, Sendable {
  public enum Extent: String, Codable, Sendable { case passage, wholeNote }
  public enum Source: String, Codable, Sendable { case editorSnapshot, savedSource }
  public let id: UUID
  public let noteID: UUID
  public let vaultID: UUID
  public let relativePath: String
  public let text: String
  public let fingerprint: DocumentFingerprint
  public let sourceLine: Int?
  public let sourceRange: SearchSourceRange?
  public let extent: Extent
  public let source: Source
  public let vaultRole: VaultRole?

  public init(
    noteID: UUID, vaultID: UUID, relativePath: String, text: String,
    fingerprint: DocumentFingerprint, sourceLine: Int? = nil, sourceRange: SearchSourceRange? = nil,
    extent: Extent = .passage, source: Source = .editorSnapshot, vaultRole: VaultRole? = nil
  ) {
    id = UUID()
    self.noteID = noteID
    self.vaultID = vaultID
    self.relativePath = relativePath
    self.text = text
    self.fingerprint = fingerprint
    self.sourceLine = sourceRange?.line ?? sourceLine
    self.sourceRange = sourceRange
    self.extent = extent; self.source = source; self.vaultRole = vaultRole
  }
}

/// Public coordination context, not independent child execution or write authority.
public struct AgentChatCoordinationTarget: Codable, Equatable, Sendable {
  public let parentThreadID: String
  public let childThreadID: String
  public let name: String?
  public init(parentThreadID: String, childThreadID: String, name: String? = nil) {
    self.parentThreadID = parentThreadID; self.childThreadID = childThreadID; self.name = name
  }
}

/// Researcher-selected Agent prose, distinct from Note and file snapshots.
public struct AgentChatReplyQuote: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let conversationID: UUID
  public let messageID: String
  public let text: String
  public init(conversationID: UUID, messageID: String, text: String) {
    id = UUID(); self.conversationID = conversationID; self.messageID = messageID; self.text = text
  }
}

public struct AgentChatMessage: Codable, Equatable, Identifiable, Sendable {
  public enum Role: String, Codable, Sendable { case user, assistant, operation }
  public enum Phase: String, Codable, Sendable { case commentary; case finalAnswer = "final_answer" }
  public let id: String
  public let role: Role
  public let changeID: UUID?
  public var text: String
  /// Public runtime classification. Absence means unknown, never presumed reasoning.
  public var phase: Phase?
  public var activity: AgentChatActivity?
  public var plan: AgentChatPlan?
  /// Runtime-confirmed turn identity, never inferred from message position.
  public var turnID: String?
  public var methods: [AgentChatMethodSelection]?
  public var coordinationTarget: AgentChatCoordinationTarget?
  public var replyQuotes: [AgentChatReplyQuote]?
  public let attachments: [AgentChatAttachment]
  public let localMaterials: [AgentChatLocalMaterial]

  public init(
    id: String = UUID().uuidString, role: Role, text: String,
    attachments: [AgentChatAttachment] = [], localMaterials: [AgentChatLocalMaterial] = [], changeID: UUID? = nil,
    activity: AgentChatActivity? = nil, phase: Phase? = nil
  ) {
    self.id = id
    self.role = role
    self.changeID = changeID
    self.text = text
    self.phase = phase
    self.attachments = attachments
    self.localMaterials = localMaterials
    self.activity = activity
  }
}

/// Public operation observations. Only a bridge receipt supplies Agent Change evidence.
public struct AgentChatActivity: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
      case read, readAttachment, search, create, update, trash, command, webSearch, tool, files, compaction, delegation
  }
  public enum Status: String, Codable, Sendable {
    case running, waitingForApproval, waitingForInput, completed, failed, declined, interrupted, uncertain
    public var isActive: Bool { self == .running || self == .waitingForApproval || self == .waitingForInput }
  }
  public enum Source: String, Codable, Sendable { case scholium, runtime }
  public struct File: Codable, Equatable, Sendable {
    public enum Effect: String, Codable, Sendable { case read, created, edited, unchanged, trashed, moved }
    public var path: String
    public var noteID: UUID?
    public var effect: Effect?
    public init(path: String, noteID: UUID? = nil, effect: Effect? = nil) {
      self.path = path
      self.noteID = noteID
      self.effect = effect
    }
  }
  public var kind: Kind
  public var status: Status
  public let source: Source
  public var subject: String
  public var detail: String
  public var files: [File]
  public var delegation: AgentChatDelegation?
  public var sourceObservation: AgentChatSourceObservation?
  public init(kind: Kind, status: Status = .running, source: Source,
              subject: String = "", detail: String = "", files: [File] = []) {
    self.kind = kind
    self.status = status
    self.source = source
    self.subject = subject
    self.detail = detail
    self.files = files
  }
}

public struct AgentChatConversation: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let triptychID: UUID
  public var title: String
  public var archivedAt: Date?
  public var threadID: String?
  public var permission: AgentChatPermission
  public var preferences: AgentChatPreferences
  public var contextUsage: AgentChatContextUsage?
  public var lastRunStatus: AgentChatActivity.Status?
  public var branchOrigin: AgentChatBranchOrigin?
  public var selectedMethods: [AgentChatMethodSelection]?
  public var messages: [AgentChatMessage]
  public var draft: String
  public var draftCoordinationTarget: AgentChatCoordinationTarget?
  public var draftReplyQuotes: [AgentChatReplyQuote]?
  /// Unsent adjustments, keyed by the exact runtime child identity.
  public var childDrafts: [String: String] = [:]
  public var attachments: [AgentChatAttachment]
  public var localMaterials: [AgentChatLocalMaterial]
  /// Retained until the server has acknowledged this exact message.
  public var pendingMessageID: String?
  public var updatedAt: Date

  public init(triptychID: UUID) {
    id = UUID()
    self.triptychID = triptychID
    title = ""
    permission = .ask
    preferences = .init()
    messages = []
    draft = ""
    attachments = []
    localMaterials = []
    updatedAt = Date()
  }
}

public struct AgentChatBranchOrigin: Codable, Equatable, Sendable {
  public enum Position: String, Codable, Sendable { case through, before }
  public let conversationID: UUID
  public let turnID: String
  public let position: Position
  public init(conversationID: UUID, turnID: String, position: Position = .through) {
    self.conversationID = conversationID
    self.turnID = turnID
    self.position = position
  }
}

/// Exact client-local association, not a path supplied by the model.
public enum AgentChatReference {
  public struct Target: Equatable, Sendable {
    public let noteID: UUID
    public let vaultID: UUID?
    public let line: Int?
    public let revision: String?
  }

  public static func url(noteID: UUID, line: Int? = nil, revision: DocumentFingerprint? = nil,
    vaultID: UUID? = nil) -> URL {
    var components = URLComponents()
    components.scheme = "scholium-note"
    components.host = noteID.uuidString.lowercased()
    var query: [URLQueryItem] = []
    if let line, line > 0 { query.append(.init(name: "line", value: String(line))) }
    if let revision { query.append(.init(name: "revision", value: revision.sha256)) }
    if let vaultID { query.append(.init(name: "vault", value: vaultID.uuidString.lowercased())) }
    if !query.isEmpty { components.queryItems = query }
    return components.url!
  }

  public static func parse(_ url: URL) -> Target? {
    guard url.scheme == "scholium-note", let host = url.host, let id = UUID(uuidString: host),
      url.path.isEmpty || url.path == "/", url.user == nil, url.password == nil, url.port == nil,
      url.fragment == nil
    else { return nil }
    let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard values.allSatisfy({ ["line", "revision", "vault"].contains($0.name) }),
      Set(values.map(\.name)).count == values.count else { return nil }
    let lineValue = values.first { $0.name == "line" }
    let line = lineValue?.value.flatMap(Int.init)
    if lineValue != nil, line == nil || line! < 1 { return nil }
    let revisionValue = values.first { $0.name == "revision" }
    let revision = revisionValue?.value?.lowercased()
    if revisionValue != nil {
      guard let revision, revision.utf8.count == 64,
        revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
    }
    let vaultValue = values.first { $0.name == "vault" }
    let vaultID = vaultValue?.value.flatMap(UUID.init(uuidString:))
    if vaultValue != nil, vaultID == nil { return nil }
    return .init(noteID: id, vaultID: vaultID, line: line, revision: revision)
  }
}

extension AgentChatActivity.Kind {
  public static func forTool(_ tool: ScholiumMCPToolName) -> AgentChatActivity.Kind {
    switch tool {
    case .moveNote: .files
    case .previewMove, .showNote: .tool
    case .readNote: .read
    case .readAttachment: .readAttachment
    case .browse, .search, .listLinks, .listAttachments, .workspaceStatus, .listChanges, .readChange: .search
    case .createNote: .create
    case .updateNote, .undoChange: .update
    case .trashNote: .trash
    }
  }

}
