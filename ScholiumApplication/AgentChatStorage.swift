import Foundation
import ScholiumContracts

/// Machine-local drafts and public presentation; runtime logs remain runtime-owned.
public actor AgentChatStorage {
  private struct Archive: Codable {
    let version: Int
    let conversations: [AgentChatConversation]
  }
  public let root: URL
  public init(root: URL) { self.root = root }

  public func load() throws -> [AgentChatConversation] {
    try prepare()
    let url = root.appendingPathComponent("conversations.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      (values.fileSize ?? 0) <= 64 * 1_024 * 1_024
    else { throw CocoaError(.fileReadCorruptFile) }
    let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
    guard archive.version == 10,
      Set(archive.conversations.map(\.id)).count == archive.conversations.count
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    return archive.conversations
  }

  public func save(_ conversations: [AgentChatConversation]) throws {
    try prepare()
    let url = root.appendingPathComponent("conversations.json")
    if FileManager.default.fileExists(atPath: url.path),
      try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true
    {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    let data = try JSONEncoder().encode(Archive(version: 10, conversations: conversations))
    guard data.count <= 64 * 1_024 * 1_024 else { throw CocoaError(.fileWriteOutOfSpace) }
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func prepare() throws {
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
  }
}
