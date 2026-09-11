import Foundation

/// An immutable local-file snapshot and the exact representation offered as input.
public struct AgentChatLocalMaterial: Codable, Equatable, Identifiable, Sendable {
    public enum CaptureOrigin: String, Codable, Sendable { case clipboard, drop }
    public enum Source: Codable, Equatable, Sendable {
        case file(URL)
        case imageCapture(CaptureOrigin)
    }
    public enum Kind: String, Codable, Sendable { case text, pdf, image, unsupported }
    public enum Issue: String, Codable, Sendable { case unreadable, unsupported, tooLarge, locked, noText }
    public struct Page: Codable, Equatable, Sendable {
        public let number: Int
        public let text: String
        public init(number: Int, text: String) {
            self.number = number
            self.text = text
        }
    }
    public struct PageImage: Codable, Equatable, Sendable {
        public let number: Int
        public let storedFileName: String
        public let fingerprint: DocumentFingerprint
        public init(number: Int, storedFileName: String, fingerprint: DocumentFingerprint) {
            self.number = number
            self.storedFileName = storedFileName
            self.fingerprint = fingerprint
        }
    }
    public let id: UUID
    public let source: Source
    public let storedFileName: String?
    public let fingerprint: DocumentFingerprint?
    public let capturedFileName: String?
    public let capturedFingerprint: DocumentFingerprint?
    public let kind: Kind
    public let text: String
    public let pages: [Page]
    public let pageImages: [PageImage]
    public let issue: Issue?
    public var fileName: String {
        switch source {
        case .file(let url): url.lastPathComponent
        case .imageCapture(.clipboard): "Clipboard Image"
        case .imageCapture(.drop): "Dropped Image"
        }
    }
    public var requiresImageInput: Bool { kind == .image || !pageImages.isEmpty }
    public var pagesWithoutText: [Int] { pages.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.number) }

    public init(
        id: UUID, source: Source, storedFileName: String?, fingerprint: DocumentFingerprint?,
        kind: Kind, text: String = "", pages: [Page] = [], pageImages: [PageImage] = [], issue: Issue? = nil,
        capturedFileName: String? = nil, capturedFingerprint: DocumentFingerprint? = nil
    ) {
        self.id = id
        self.source = source
        self.storedFileName = storedFileName
        self.fingerprint = fingerprint
        self.kind = kind
        self.text = text
        self.pages = pages
        self.pageImages = pageImages
        self.issue = issue
        self.capturedFileName = capturedFileName
        self.capturedFingerprint = capturedFingerprint
    }
}
