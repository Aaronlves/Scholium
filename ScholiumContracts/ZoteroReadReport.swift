import Foundation

/// What an identified public runtime event reported. Never an App-verified read receipt.
public struct ZoteroReadReport: Codable, Equatable, Sendable {
    public enum Representation: String, Codable, Sendable {
        case text = "utf8_text", pdfText = "pdf_text", pdfImage = "pdf_page_image", image, annotation
    }
    public struct TextRange: Codable, Equatable, Sendable {
        public let start: Int
        public let end: Int
        public let total: Int
        public init(start: Int, end: Int, total: Int) { self.start = start; self.end = end; self.total = total }
    }
    public let server: String
    public let tool: String
    public let reference: ZoteroReference
    public let representation: Representation
    public let fingerprint: String
    public let range: TextRange?
    public let excerpt: String
    public let excerptIsTruncated: Bool
    public let comment: String?
    public let commentIsTruncated: Bool
    public let pageLabel: String?

    public init(server: String, tool: String, reference: ZoteroReference, representation: Representation,
                fingerprint: String, range: TextRange? = nil, excerpt: String = "", excerptIsTruncated: Bool = false,
                comment: String? = nil, commentIsTruncated: Bool = false, pageLabel: String? = nil) {
        self.server = server; self.tool = tool; self.reference = reference; self.representation = representation
        self.fingerprint = fingerprint; self.range = range; self.excerpt = excerpt; self.excerptIsTruncated = excerptIsTruncated
        self.comment = comment; self.commentIsTruncated = commentIsTruncated; self.pageLabel = pageLabel
    }

    /// Retained history is also checked before presentation; decoding grants no new trust.
    public var isValid: Bool {
        guard !server.isEmpty, server.utf8.count <= 128,
              server.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }),
              fingerprint.utf8.count == 64,
              fingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              excerpt.utf8.count <= 1_600, (comment?.utf8.count ?? 0) <= 1_600,
              (pageLabel?.utf8.count ?? 0) <= 256 else { return false }
        if representation == .annotation {
            return tool == "zotero_read_annotation" && reference.kind == .pdf && reference.annotationKey != nil && range == nil
        }
        guard tool == "zotero_read_original", reference.annotationKey == nil, comment == nil, pageLabel == nil else { return false }
        let pdf = representation == .pdfText || representation == .pdfImage
        guard pdf == (reference.kind == .pdf), pdf == (reference.page != nil) else { return false }
        if representation == .text || representation == .pdfText {
            guard let range else { return false }
            return range.start >= 0 && range.end >= range.start && range.end <= range.total
                && range.total <= 20 * 1_024 * 1_024 && range.end - range.start <= 65_536
                && excerpt.utf8.count <= range.end - range.start
                && (excerptIsTruncated ? excerpt.utf8.count < range.end - range.start : excerpt.utf8.count == range.end - range.start)
        }
        return range == nil && excerpt.isEmpty && !excerptIsTruncated
    }

    public func matches(_ citation: ZoteroReference) -> Bool {
        guard isValid, citation.library == reference.library, citation.itemKey == reference.itemKey else { return false }
        if let annotation = citation.annotationKey {
            return representation == .annotation && reference.annotationKey == annotation
                && (citation.page == nil || citation.page == reference.page)
        }
        guard representation != .annotation else { return false }
        if citation.kind == .pdf, reference.kind != .pdf { return false }
        return citation.page == nil || (citation.kind == .pdf && citation.page == reference.page)
    }
}
