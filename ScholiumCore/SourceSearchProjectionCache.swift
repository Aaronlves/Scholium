import CryptoKit
import Foundation
import ScholiumContracts

/// Disposable machine-local Search text and coordinates. A caller must load
/// the source afresh; this store neither loads Notes nor authorizes their use.
public struct SourceSearchProjectionCache: Sendable {
    // Bounded per Note, including binary offset maps. Oversize records are misses.
    static let maximumRecordByteCount = 32 * 1_024 * 1_024

    struct Policy: Codable, Equatable {
        let formatVersion: Int
        let projectionVersion: Int
        let markdownParserVersion: String
        let yamlParserVersion: String
        let searchVersion: Int
        let schemaVersion: Int
        let tokenizerVersion: Int
        let rankingVersion: Int

        static let current = Policy(
            formatVersion: 1, projectionVersion: 1, markdownParserVersion: "0.8.0", yamlParserVersion: "6.2.2",
            searchVersion: SearchContract.currentVersion, schemaVersion: SearchContract.schemaVersion,
            tokenizerVersion: SearchContract.tokenizerPolicyVersion, rankingVersion: SearchContract.rankingPolicyVersion)
    }

    struct Frame: Codable {
        let policy: Policy
        let vaultID: UUID
        let role: VaultRole
        let profile: SchemaProfileID
        let relativePathUTF8: Data
        let fingerprint: DocumentFingerprint
        let payloadDigest: String
        let payload: Data
    }

    private let vaultID: UUID
    private let role: VaultRole
    private let storage: SecureRecordDirectory

    public init(applicationSupportURL: URL, vaultID: UUID, role: VaultRole) {
        self.vaultID = vaultID
        self.role = role
        storage = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Vaults", vaultID.uuidString, "source-projections-v1"],
            directoryMode: 0o700, fileMode: 0o600,
            maximumByteCount: Self.maximumRecordByteCount)
    }

    public func load(for document: NoteDocument) -> SearchDocumentProjection? {
        do {
            guard let bytes = try storage.readIfPresent(directory: nil, fileName: Self.fileName(document.relativePath)) else { return nil }
            let frame = try JSONDecoder().decode(Frame.self, from: bytes)
            guard frame.policy == .current, frame.vaultID == vaultID, frame.role == role,
                frame.profile == WorkflowProfileResolver.resolve(vaultRole: role),
                frame.relativePathUTF8 == Data(document.relativePath.utf8), frame.fingerprint == document.fingerprint,
                frame.payloadDigest == Self.digest(frame.payload)
            else { return nil }
            let stored = try PropertyListDecoder().decode(StoredProjection.self, from: frame.payload)
            let projection = try stored.projection()
            guard Self.valid(projection, document: document) else { return nil }
            return projection
        } catch {
            return nil
        }
    }

    /// Persistence failures are nonfatal: the freshly generated projection
    /// remains usable and the next process recomputes it from exact source.
    public func store(_ projection: SearchDocumentProjection, for document: NoteDocument) {
        guard Self.valid(projection, document: document) else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let payload = try encoder.encode(StoredProjection(projection))
            let frame = Frame(
                policy: .current, vaultID: vaultID, role: role, profile: WorkflowProfileResolver.resolve(vaultRole: role),
                relativePathUTF8: Data(document.relativePath.utf8), fingerprint: document.fingerprint,
                payloadDigest: Self.digest(payload), payload: payload)
            let bytes = try JSONEncoder().encode(frame)
            guard bytes.count <= Self.maximumRecordByteCount else { return }
            _ = try storage.replace(bytes, directory: nil, fileName: Self.fileName(document.relativePath))
        } catch {
            // Caches never change source success or recovery semantics.
        }
    }

    public func invalidate(path: String) {
        try? storage.removeIfPresent(directory: nil, fileName: Self.fileName(path))
    }

    public func prune(currentPaths: Set<String>) {
        let retained = Set(currentPaths.map(Self.fileName))
        guard let names = try? storage.fileNames(in: nil) else { return }
        for name in names where name.hasSuffix(".projection.json") && !retained.contains(name) {
            try? storage.removeIfPresent(directory: nil, fileName: name)
        }
    }

    static func fileName(_ path: String) -> String { digest(Data(path.utf8)) + ".projection.json" }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func valid(_ projection: SearchDocumentProjection, document: NoteDocument) -> Bool {
        guard Data(projection.path.utf8) == Data(document.relativePath.utf8),
            Data(projection.title.utf8) == Data(ResearchNoteTitleResolver.resolve(document: document).utf8),
            !projection.hasBrokenLink,
            projection.sourceLineStartsUTF16 == lineStarts(document.rawContent)
        else { return false }
        let sourceCount = document.rawContent.utf16.count
        let starts = projection.sourceLineStartsUTF16
        func validRange(_ range: SearchSourceRange) -> Bool {
            guard range.utf16LowerBound >= 0, range.utf16UpperBound >= range.utf16LowerBound,
                range.utf16UpperBound <= sourceCount,
                range.line > 0, range.line <= starts.count, range.endLine >= range.line, range.endLine <= starts.count,
                range.column > 0, range.endColumn > 0,
                range.line == starts.count || range.utf16LowerBound < starts[range.line],
                range.endLine == starts.count || range.utf16UpperBound < starts[range.endLine]
            else { return false }
            return range.column == range.utf16LowerBound - starts[range.line - 1] + 1
                && range.endColumn == range.utf16UpperBound - starts[range.endLine - 1] + 1
        }
        func validSegment(_ segment: SearchTextSegment) -> Bool {
            segment.ordinal >= 0 && (segment.sourceRange.map(validRange) ?? true)
                && SearchProjectionValidation.valid(
                    offsets: segment.offsetMap, normalizedUTF16Count: segment.normalizedText.utf16.count,
                    sourceUTF16Bounds: segment.sourceRange.map { (lower: $0.utf16LowerBound, upper: $0.utf16UpperBound) },
                    sourceUTF16Count: sourceCount)
        }
        // The source builder assigns one consecutive ordinal across the complete
        // document segment list. Paragraph body segments use local ordinal 0;
        // their annotations retain their global document ordinals.
        guard projection.segments.first?.field == .title,
            projection.segments.enumerated().allSatisfy({ index, segment in segment.ordinal == index }),
            projection.segments.allSatisfy(validSegment),
            projection.paragraphs.allSatisfy({ paragraph in
                validRange(paragraph.range) && paragraph.range.utf16LowerBound < paragraph.range.utf16UpperBound
                    && paragraph.segments.allSatisfy { segment in
                        validSegment(segment)
                            && (segment.sourceRange.map {
                                $0.utf16LowerBound >= paragraph.range.utf16LowerBound && $0.utf16UpperBound <= paragraph.range.utf16UpperBound
                            } ?? true)
                    }
            }),
            zip(projection.paragraphs, projection.paragraphs.dropFirst()).allSatisfy({ previous, next in
                previous.range.utf16LowerBound <= next.range.utf16LowerBound
            })
        else { return false }
        let material =
            projection.segments.map { segment in
                "\(segment.field.rawValue)\u{1F}\(segment.ordinal)\u{1F}\(segment.normalizedText)"
                    + segment.relatedRankingText.keys.sorted().map { key in
                        "\u{1F}\(key)\u{1F}\(segment.relatedRankingText[key] ?? "")"
                    }.joined()
            }.joined(separator: "\u{1E}") + "\u{1D}false"
        return projection.projectionHash == digest(Data(material.utf8))
    }

    private static func lineStarts(_ source: String) -> [Int] {
        let units = Array(source.utf16)
        var starts = [0]
        var index = 0
        while index < units.count {
            if units[index] == 13 {
                if index + 1 < units.count && units[index + 1] == 10 { index += 1 }
                starts.append(index + 1)
            } else if units[index] == 10 {
                starts.append(index + 1)
            }
            index += 1
        }
        return starts
    }
}

private struct StoredProjection: Codable {
    let title: String
    let aliases: [String]
    let headings: [String]
    let summary: String?
    let authors: [String]
    let publicationDate: String?
    let tags: [String]
    let body: String
    let callouts: String
    let calloutRoles: Set<String>
    let footnotes: String
    let linkAnnotations: String
    let path: String
    let hasBrokenLink: Bool
    let sourceLineStartsUTF16: [Int]
    let segments: [StoredParagraphSegment]
    let paragraphs: [StoredParagraph]
    let projectionHash: String

    init(_ projection: SearchDocumentProjection) throws {
        title = projection.title
        aliases = projection.aliases
        headings = projection.headings
        summary = projection.summary
        authors = projection.authors
        publicationDate = projection.publicationDate
        tags = projection.tags
        body = projection.body
        callouts = projection.callouts
        calloutRoles = projection.calloutRoles
        footnotes = projection.footnotes
        linkAnnotations = projection.linkAnnotations
        path = projection.path
        hasBrokenLink = projection.hasBrokenLink
        sourceLineStartsUTF16 = projection.sourceLineStartsUTF16
        segments = try projection.segments.map(StoredParagraphSegment.init)
        paragraphs = try projection.paragraphs.map(StoredParagraph.init)
        projectionHash = projection.projectionHash
    }

    func projection() throws -> SearchDocumentProjection {
        SearchDocumentProjection(
            title: title, aliases: aliases, headings: headings, summary: summary, authors: authors,
            publicationDate: publicationDate, tags: tags, body: body, callouts: callouts,
            calloutRoles: calloutRoles, footnotes: footnotes, linkAnnotations: linkAnnotations,
            path: path, hasBrokenLink: hasBrokenLink, sourceLineStartsUTF16: sourceLineStartsUTF16,
            segments: try segments.map { try $0.projection() }, paragraphs: try paragraphs.map { try $0.projection() },
            projectionHash: projectionHash)
    }
}
