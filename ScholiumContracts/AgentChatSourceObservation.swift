import Foundation

/// Retained public provenance. It grants no source or operation authority.
public enum AgentChatSourceObservation: Codable, Equatable, Sendable {
    case noteRead(NoteRead)
    case webAccess(WebAccess)
    case zoteroReadReport(ZoteroReadReport)

    public struct NoteRead: Codable, Equatable, Sendable {
        public let noteID: UUID
        public let fingerprint: DocumentFingerprint
        public let startLine: Int
        public let lineCount: Int
        public let reachedEnd: Bool
        public let excerpt: String
        public let excerptIsTruncated: Bool
        public init(
            noteID: UUID, fingerprint: DocumentFingerprint, startLine: Int,
            lineCount: Int, reachedEnd: Bool, excerpt: String, excerptIsTruncated: Bool
        ) {
            self.noteID = noteID
            self.fingerprint = fingerprint
            self.startLine = startLine
            self.lineCount = lineCount
            self.reachedEnd = reachedEnd
            self.excerpt = excerpt
            self.excerptIsTruncated = excerptIsTruncated
        }
    }

    public struct WebAccess: Codable, Equatable, Sendable {
        public enum Action: String, Codable, Sendable { case openPage, findInPage }
        public let action: Action
        public let url: URL
        public init(action: Action, url: URL) {
            self.action = action
            self.url = url
        }
    }
}
