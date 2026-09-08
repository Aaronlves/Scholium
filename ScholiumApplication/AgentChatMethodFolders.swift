import Foundation

/// Validate explicit local discovery roots without reading or modifying Skill contents.
public enum AgentChatMethodFolders {
  public static func directory(_ url: URL) throws -> URL {
    guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    let directory = url.resolvingSymlinksInPath().standardizedFileURL
    guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    else { throw CocoaError(.fileReadUnsupportedScheme) }
    return directory
  }
}
