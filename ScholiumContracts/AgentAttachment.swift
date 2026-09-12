import Foundation

public struct AgentAttachment: Codable, Hashable, Sendable {
    public enum Relationship: String, Codable, Sendable { case document, authoredImage }
    public let id: UUID
    public let relationship: Relationship
    public let location: AttachmentLocation
    public let available: Bool
    public var filename: String { location.filename }
    public init(id: UUID, relationship: Relationship, location: AttachmentLocation, available: Bool) {
        self.id = id
        self.relationship = relationship
        self.location = location
        self.available = available
    }
}

public struct AgentAttachmentListing: Codable, Sendable {
    public let noteFingerprint: DocumentFingerprint
    public let attachments: [AgentAttachment]
    public init(noteFingerprint: DocumentFingerprint, attachments: [AgentAttachment]) {
        self.noteFingerprint = noteFingerprint
        self.attachments = attachments
    }
    public func fingerprint(triptychID: UUID, noteID: UUID) throws -> DocumentFingerprint {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data((triptychID.uuidString.lowercased() + ":" + noteID.uuidString.lowercased()).utf8)
        data.append(try encoder.encode(self))
        return DocumentFingerprint(data: data)
    }

}

public struct AgentAttachmentRead: Sendable {
    public enum Mode: String, Sendable { case text, image }
    public let mode: Mode
    public let page: Int?
    public let startUTF8: Int
    public let maximumUTF8: Int
    public let expectedFingerprint: DocumentFingerprint?
    public init(mode: Mode, page: Int? = nil, startUTF8: Int = 0, maximumUTF8: Int = 16 * 1_024, expectedFingerprint: DocumentFingerprint? = nil) {
        self.mode = mode
        self.page = page
        self.startUTF8 = startUTF8
        self.maximumUTF8 = maximumUTF8
        self.expectedFingerprint = expectedFingerprint
    }
}

public struct AgentAttachmentContent: Sendable {
    public let filename: String
    public let fingerprint: DocumentFingerprint
    public let kind: String
    public let page: Int?
    public let totalPages: Int?
    public let text: String?
    public let startUTF8: Int
    public let endUTF8: Int
    public let totalUTF8: Int
    public let imagePNG: Data?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public init(
        filename: String, fingerprint: DocumentFingerprint, kind: String, page: Int? = nil, totalPages: Int? = nil,
        text: String? = nil, startUTF8: Int = 0, endUTF8: Int = 0, totalUTF8: Int = 0,
        imagePNG: Data? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil
    ) {
        self.filename = filename
        self.fingerprint = fingerprint
        self.kind = kind
        self.page = page
        self.totalPages = totalPages
        self.text = text
        self.startUTF8 = startUTF8
        self.endUTF8 = endUTF8
        self.totalUTF8 = totalUTF8
        self.imagePNG = imagePNG
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
