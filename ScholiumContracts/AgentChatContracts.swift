import Foundation

/// User-selected operation policy, independent of research acceptance.
public enum AgentChatPermission: String, Codable, CaseIterable, Sendable {
  case ask, fullAccess

  public var approvalPolicy: String { self == .ask ? "on-request" : "never" }
  public var sandbox: String { self == .ask ? "read-only" : "danger-full-access" }
}

public struct AgentChatAttachment: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let noteID: UUID
  public let vaultID: UUID
  public let relativePath: String
  public let text: String
  public let fingerprint: DocumentFingerprint
  public let sourceLine: Int?

  public init(
    noteID: UUID, vaultID: UUID, relativePath: String, text: String,
    fingerprint: DocumentFingerprint, sourceLine: Int? = nil
  ) {
    id = UUID()
    self.noteID = noteID
    self.vaultID = vaultID
    self.relativePath = relativePath
    self.text = text
    self.fingerprint = fingerprint
    self.sourceLine = sourceLine
  }
}

public struct AgentChatMessage: Codable, Equatable, Identifiable, Sendable {
  public enum Role: String, Codable, Sendable { case user, assistant, operation }
  public let id: String
  public let role: Role
  public let changeID: UUID?
  public var text: String
  public var activity: AgentChatActivity?
  public let attachments: [AgentChatAttachment]

  public init(
    id: String = UUID().uuidString, role: Role, text: String,
    attachments: [AgentChatAttachment] = [], changeID: UUID? = nil,
    activity: AgentChatActivity? = nil
  ) {
    self.id = id
    self.role = role
    self.changeID = changeID
    self.text = text
    self.attachments = attachments
    self.activity = activity
  }
}

/// Public operation observations. Only a bridge receipt supplies Agent Change evidence.
public struct AgentChatActivity: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case read, search, create, update, trash, command, webSearch, tool, files
  }
  public enum Status: String, Codable, Sendable {
    case running, waitingForApproval, completed, failed, declined, interrupted, uncertain
    public var isActive: Bool { self == .running || self == .waitingForApproval }
  }
  public enum Source: String, Codable, Sendable { case scholium, runtime }
  public struct File: Codable, Equatable, Sendable {
    public enum Effect: String, Codable, Sendable { case read, created, edited, unchanged, trashed }
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
  public var messages: [AgentChatMessage]
  public var draft: String
  public var attachments: [AgentChatAttachment]
  /// Retained until the server has acknowledged this exact message.
  public var pendingMessageID: String?
  public var updatedAt: Date

  public init(triptychID: UUID) {
    id = UUID()
    self.triptychID = triptychID
    title = ""
    permission = .ask
    messages = []
    draft = ""
    attachments = []
    updatedAt = Date()
  }
}

/// Exact client-local association, not a path supplied by the model.
public enum AgentChatReference {
  public static func url(noteID: UUID, line: Int? = nil) -> URL {
    var components = URLComponents()
    components.scheme = "scholium-note"
    components.host = noteID.uuidString.lowercased()
    if let line, line > 0 {
      components.queryItems = [URLQueryItem(name: "line", value: String(line))]
    }
    return components.url!
  }

  public static func parse(_ url: URL) -> (noteID: UUID, line: Int?)? {
    guard url.scheme == "scholium-note", let host = url.host, let id = UUID(uuidString: host),
      url.path.isEmpty || url.path == "/", url.user == nil, url.password == nil, url.port == nil,
      url.fragment == nil
    else { return nil }
    let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    guard values.allSatisfy({ $0.name == "line" }), values.count <= 1 else { return nil }
    let line = values.first?.value.flatMap(Int.init)
    if !values.isEmpty, line == nil || line! < 1 { return nil }
    return (id, line)
  }
}
