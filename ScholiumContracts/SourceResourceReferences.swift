import Foundation
import Markdown

/// A projection of authored Markdown. No record can create a relationship absent from source.
public enum SourceResourceReferences {
    public struct File: Hashable, Sendable {
        public let destination: String
        public let relativePath: AttachmentRelativePath?
        public let absolutePath: String?
        public let isImage: Bool
    }
    public struct ExternalLink: Hashable, Sendable, Identifiable {
        public let url: URL
        public let destination: String
        public let label: String
        public let line: Int
        public let occurrence: Int
        public var id: Int { occurrence }
        public var canOpen: Bool {
            switch url.scheme?.lowercased() {
            case "javascript", "data", "vbscript": false
            case "zotero": (try? ZoteroReference(url: url)) != nil
            default: true
            }
        }
    }
    public static func files(in body: String, noteRelativePath: String) -> [File] {
        var walker = ResourceWalker(noteRelativePath: noteRelativePath)
        walker.visit(Document(parsing: body))
        return walker.files
    }
    public static func externalLinks(in body: String, noteURL: URL? = nil, vaultRoots: [URL] = []) -> [ExternalLink] {
        var walker = ResourceWalker(noteRelativePath: "", noteURL: noteURL, vaultRoots: vaultRoots)
        walker.visit(Document(parsing: body))
        return walker.external
    }
    public static func file(destination: String, noteRelativePath: String, isImage: Bool = false)
        -> File?
    {
        guard !destination.hasPrefix("//"), let decoded = destination.removingPercentEncoding,
            !decoded.contains("\0"), !destination.contains("?"), !destination.contains("#"),
            URLComponents(string: destination)?.scheme == nil
        else { return nil }
        let ext = (decoded as NSString).pathExtension.lowercased()
        guard isImage || (!ext.isEmpty && !["md", "markdown"].contains(ext)) else { return nil }
        if decoded.hasPrefix("/") {
            guard URL(fileURLWithPath: decoded).standardizedFileURL.path == decoded else { return nil }
            return File(
                destination: destination, relativePath: nil, absolutePath: decoded, isImage: isImage)
        }
        var parts = noteRelativePath.split(separator: "/").dropLast().map(String.init)
        for component in decoded.split(separator: "/", omittingEmptySubsequences: false) {
            if component == "." { continue }
            if component == ".." {
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            } else {
                guard !component.isEmpty else { return nil }
                parts.append(String(component))
            }
        }
        guard let path = try? AttachmentRelativePath(parts.joined(separator: "/")) else { return nil }
        return File(destination: destination, relativePath: path, absolutePath: nil, isImage: isImage)
    }
    public static func derivedID(vaultID: UUID, path: String) -> UUID {
        let hex = String(
            DocumentFingerprint(data: Data((vaultID.uuidString + ":" + path).utf8)).sha256.prefix(32))
        let parts = [8, 4, 4, 4, 12]
        var cursor = hex.startIndex
        let value = parts.map { count in
            let end = hex.index(cursor, offsetBy: count)
            defer { cursor = end }
            return String(hex[cursor..<end])
        }.joined(separator: "-")
        return UUID(uuidString: value)!
    }
}

private struct ResourceWalker: MarkupWalker {
    let noteRelativePath: String
    var noteURL: URL? = nil
    var vaultRoots: [URL] = []
    var files: [SourceResourceReferences.File] = []
    var external: [SourceResourceReferences.ExternalLink] = []
    mutating func visitLink(_ link: Markdown.Link) {
        guard let destination = link.destination else { return }
        if let url = externalURL(destination) {
            external.append(
                .init(
                    url: url, destination: destination, label: link.plainText,
                    line: link.range?.lowerBound.line ?? 1, occurrence: external.count))
        }
        if let file = SourceResourceReferences.file(
            destination: destination, noteRelativePath: noteRelativePath)
        {
            files.append(file)
        }
        descendInto(link)
    }
    private func externalURL(_ destination: String) -> URL? {
        guard !destination.isEmpty, !destination.hasPrefix("#"), !destination.contains("\0") else { return nil }
        if destination.hasPrefix("//") { return URL(string: "https:" + destination) }
        guard let parsed = URL(string: destination) else { return nil }
        if let scheme = parsed.scheme, scheme.lowercased() != "file" {
            return scheme.lowercased() == "scholium-note" ? nil : parsed
        }
        let fileURL: URL
        if parsed.isFileURL {
            fileURL = parsed.standardizedFileURL
        } else if destination.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: parsed.path).standardizedFileURL
        } else if let noteURL {
            guard let resolved = URL(string: destination, relativeTo: noteURL)?.absoluteURL, resolved.isFileURL else { return nil }
            fileURL = resolved.standardizedFileURL
        } else {
            return nil
        }
        // Classification is lexical only; opening still uses its own access checks.
        let path = fileURL.path
        return vaultRoots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        } ? nil : fileURL
    }
    mutating func visitImage(_ image: Markdown.Image) {
        if let source = image.source, let url = externalURL(source) {
            external.append(
                .init(
                    url: url, destination: source, label: image.plainText,
                    line: image.range?.lowerBound.line ?? 1, occurrence: external.count))
        }
        if let source = image.source,
            let file = SourceResourceReferences.file(
                destination: source, noteRelativePath: noteRelativePath, isImage: true)
        {
            files.append(file)
        }
    }
}
