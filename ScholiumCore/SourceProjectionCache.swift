import CryptoKit
import Darwin
import Foundation
import ScholiumContracts

/// Disposable machine-local Catalog syntax and Search text/coordinates. A caller must load
/// the source afresh; this store neither loads Notes nor authorizes their use.
public struct SourceProjectionCache: Sendable {
    // Both the stored record and decoded payload are bounded per Note.
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
            formatVersion: 2, projectionVersion: 2, markdownParserVersion: "0.8.0", yamlParserVersion: "6.2.2",
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

    /// Catalog syntax is independent of Search schema, ranking and tokenization.
    /// Increment projectionVersion when Scholium's compact syntax, title,
    /// property, heading or block-anchor derivation changes.
    struct CatalogPolicy: Codable, Equatable {
        let formatVersion: Int
        let projectionVersion: Int
        let markdownParserVersion: String
        let yamlParserVersion: String

        static let current = CatalogPolicy(
            formatVersion: 1, projectionVersion: 1,
            markdownParserVersion: "0.8.0", yamlParserVersion: "6.2.2")
    }

    struct CatalogFrame: Codable {
        let policy: CatalogPolicy
        let vaultID: UUID
        let role: VaultRole
        let profile: SchemaProfileID
        let relativePathUTF8: Data
        let fingerprint: DocumentFingerprint
        let payloadDigest: String
        let payload: Data
    }

    private let applicationSupportURL: URL
    private let vaultID: UUID
    private let role: VaultRole
    private let storage: SecureRecordDirectory

    public init(applicationSupportURL: URL, vaultID: UUID, role: VaultRole) {
        let trustedRoot = applicationSupportURL.resolvingSymlinksInPath().standardizedFileURL
        self.applicationSupportURL = trustedRoot
        self.vaultID = vaultID
        self.role = role
        storage = SecureRecordDirectory(
            trustedRootURL: trustedRoot,
            components: ["Vaults", vaultID.uuidString, "source-projections-v1"],
            directoryMode: 0o700, fileMode: 0o600,
            maximumByteCount: Self.maximumRecordByteCount, fileExtensions: [.json, .plist])
    }

    public func load(for document: NoteDocument) -> SearchDocumentProjection? {
        let name = Self.fileName(document.relativePath)
        var observed: Data?
        do {
            guard let bytes = try storage.readIfPresent(directory: nil, fileName: name) else { return nil }
            observed = bytes
            guard Self.policyState(bytes, catalog: false) == .current else {
                discardIfRetired(name, observed: bytes, catalog: false)
                return nil
            }
            let frame = try PropertyListDecoder().decode(Frame.self, from: bytes)
            // A different fresh source or role may belong to another live
            // participant; it is a miss, not a damaged record to delete.
            guard frame.vaultID == vaultID, frame.role == role,
                frame.profile == WorkflowProfileResolver.resolve(vaultRole: role),
                frame.relativePathUTF8 == Data(document.relativePath.utf8), frame.fingerprint == document.fingerprint
            else { return nil }
            guard frame.policy == .current, frame.payloadDigest == Self.digest(frame.payload) else {
                discard(name, observed: bytes)
                return nil
            }
            let payload = try SearchProjectionBlobCodec.decode(frame.payload, maximumDecodedByteCount: Self.maximumRecordByteCount)
            let stored = try PropertyListDecoder().decode(StoredProjection.self, from: payload)
            let projection = try stored.projection()
            guard Self.valid(projection, document: document) else {
                discard(name, observed: bytes)
                return nil
            }
            return projection
        } catch {
            if let observed { discard(name, observed: observed) }
            return nil
        }
    }

    package func loadCatalog(for document: NoteDocument) -> WorkspaceSourceProjection? {
        let name = Self.catalogFileName(document.relativePath)
        var observed: Data?
        do {
            guard let bytes = try storage.readIfPresent(directory: nil, fileName: name) else { return nil }
            observed = bytes
            guard Self.policyState(bytes, catalog: true) == .current else {
                discardIfRetired(name, observed: bytes, catalog: true)
                return nil
            }
            let frame = try PropertyListDecoder().decode(CatalogFrame.self, from: bytes)
            guard frame.vaultID == vaultID, frame.role == role,
                frame.profile == WorkflowProfileResolver.resolve(vaultRole: role),
                frame.relativePathUTF8 == Data(document.relativePath.utf8), frame.fingerprint == document.fingerprint
            else { return nil }
            guard frame.policy == .current, frame.payloadDigest == Self.digest(frame.payload) else {
                discard(name, observed: bytes)
                return nil
            }
            let payload = try SearchProjectionBlobCodec.decode(frame.payload, maximumDecodedByteCount: Self.maximumRecordByteCount)
            let projection = try PropertyListDecoder().decode(WorkspaceSourceProjection.self, from: payload)
            guard projection.isValid(for: document, vaultID: vaultID) else {
                discard(name, observed: bytes)
                return nil
            }
            return projection
        } catch {
            if let observed { discard(name, observed: observed) }
            return nil
        }
    }

    func isBound(to vaultID: UUID, role: VaultRole) -> Bool {
        self.vaultID == vaultID && self.role == role
    }

    /// Persistence failures are nonfatal: the freshly generated projection
    /// remains usable and the next process recomputes it from exact source.
    public func store(_ projection: SearchDocumentProjection, for document: NoteDocument) {
        guard Self.valid(projection, document: document) else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let material = try encoder.encode(StoredProjection(projection))
            guard material.count <= Self.maximumRecordByteCount else { return }
            let payload = try SearchProjectionBlobCodec.encode(material)
            let frame = Frame(
                policy: .current, vaultID: vaultID, role: role, profile: WorkflowProfileResolver.resolve(vaultRole: role),
                relativePathUTF8: Data(document.relativePath.utf8), fingerprint: document.fingerprint,
                payloadDigest: Self.digest(payload), payload: payload)
            let bytes = try encoder.encode(frame)
            guard bytes.count <= Self.maximumRecordByteCount else { return }
            try mutateRecords {
                guard try mayReplace(Self.fileName(document.relativePath), catalog: false) else { return }
                _ = try storage.replace(bytes, directory: nil, fileName: Self.fileName(document.relativePath))
            }
        } catch {
            // Caches never change source success or recovery semantics.
        }
    }

    package func storeCatalog(_ projection: WorkspaceSourceProjection, for document: NoteDocument) {
        guard projection.isValid(for: document, vaultID: vaultID) else { return }
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let material = try encoder.encode(projection)
            guard material.count <= Self.maximumRecordByteCount else { return }
            let payload = try SearchProjectionBlobCodec.encode(material)
            let frame = CatalogFrame(
                policy: .current, vaultID: vaultID, role: role, profile: WorkflowProfileResolver.resolve(vaultRole: role),
                relativePathUTF8: Data(document.relativePath.utf8), fingerprint: document.fingerprint,
                payloadDigest: Self.digest(payload), payload: payload)
            let bytes = try encoder.encode(frame)
            guard bytes.count <= Self.maximumRecordByteCount else { return }
            try mutateRecords {
                guard try mayReplace(Self.catalogFileName(document.relativePath), catalog: true) else { return }
                _ = try storage.replace(bytes, directory: nil, fileName: Self.catalogFileName(document.relativePath))
            }
        } catch {
            // Source success never depends on disposable persistence.
        }
    }

    public func invalidate(path: String) {
        try? mutateRecords {
            for (name, catalog) in [(Self.fileName(path), false), (Self.catalogFileName(path), true)] {
                if try mayReplace(name, catalog: catalog) { try storage.removeIfPresent(directory: nil, fileName: name) }
            }
        }
    }

    public func prune(currentPaths: Set<String>) {
        let retained = Set(currentPaths.flatMap { [Self.fileName($0), Self.catalogFileName($0)] })
        try? mutateRecords {
            for name in try storage.fileNames(in: nil) where !retained.contains(name) {
                guard let catalog = Self.recordKind(name),
                    let replaceable = try? mayReplace(name, catalog: catalog), replaceable
                else { continue }
                try storage.removeIfPresent(directory: nil, fileName: name)
            }
        }
    }

    /// Clears only recognized disposable records. The lifetime shared lease
    /// keeps maintenance away; the ordinary record lock serializes active
    /// cache writers. Unknown/future frames and permanent locks survive.
    public func clearRecognizedRecords() throws -> ScholiumStorageClearResult {
        try Task.checkCancellation()
        do {
            let existing = try storage.openStorageDirectory(createIfMissing: false)
            Darwin.close(existing)
        } catch SecureRecordDirectoryError.notFound {
            return .init()
        }
        do {
            return try mutateRecords {
                let parent = try storage.openStorageDirectory(createIfMissing: false)
                defer { Darwin.close(parent) }
                var removedFiles = 0
                var removedBytes: Int64 = 0
                var preservedFiles = 0
                var failedFiles = 0
                for name in try storage.fileNames(parent: parent, includingStaging: true) {
                    try Task.checkCancellation()
                    if [DerivedStateStorage.lockFileName, ".projection-records.lock"].contains(name) { continue }
                    guard Self.recordKind(name) != nil else {
                        preservedFiles += 1
                        continue
                    }
                    do {
                        let bytes = try storage.read(parent: parent, fileName: name)
                        guard Self.recordPolicy(bytes, fileName: name) != .unknown else {
                            preservedFiles += 1
                            continue
                        }
                        try storage.remove(directory: nil, fileName: name, expected: bytes)
                        removedFiles += 1
                        removedBytes += Int64(bytes.count)
                    } catch {
                        preservedFiles += 1
                        failedFiles += 1
                    }
                }
                return .init(removedFiles: removedFiles, removedBytes: removedBytes, preservedFiles: preservedFiles, failedFiles: failedFiles)
            }
        } catch DerivedStateStorageError.inUse { return .init(busyDirectories: 1) }
    }

    static func isRecognizedRecordFileName(_ name: String) -> Bool { recordKind(name) != nil }

    static func fileName(_ path: String) -> String { digest(Data(path.utf8)) + ".projection.plist" }
    static func catalogFileName(_ path: String) -> String { digest(Data(path.utf8)) + ".catalog.plist" }

    /// All cache mutations take the lifetime lease before this short record
    /// lock. Maintenance takes the lifetime lock exclusively, so it cannot reap
    /// an atomic writer's hidden staging file. Never unlink the record lock.
    private func mutateRecords<T>(_ operation: () throws -> T) throws -> T {
        let lease = try DerivedStateStorage.vaultCacheMutationLease(applicationSupportURL: applicationSupportURL, vaultID: vaultID)
        defer { withExtendedLifetime(lease) {} }
        let lock = try AdvisoryFileLock(directory: storage, fileName: ".projection-records.lock")
        return try lock.withExclusiveLock(operation)
    }

    private func discard(_ name: String, observed: Data) {
        try? mutateRecords {
            // Another process may have repaired/replaced it since the read.
            guard try storage.readIfPresent(directory: nil, fileName: name) == observed else { return }
            try storage.removeIfPresent(directory: nil, fileName: name)
        }
    }

    private func discardIfRetired(_ name: String, observed: Data, catalog: Bool) {
        if Self.policyState(observed, catalog: catalog) != .unknown { discard(name, observed: observed) }
    }

    private func mayReplace(_ name: String, catalog: Bool) throws -> Bool {
        guard let bytes = try storage.readIfPresent(directory: nil, fileName: name) else { return true }
        return Self.policyState(bytes, catalog: catalog) != .unknown
    }

    /// Policy/framing classification only. `current` does not validate or
    /// inflate the source-derived payload; normal loading still does both.
    enum RecordPolicy: Equatable { case current, retired, corrupt, unknown }

    /// Registered storage retires only known old policy or damaged framing;
    /// unreferenced storage may also retire recognized current records.
    /// Unknown filenames/extensions/policies remain nonauthorizing and intact.
    static func recordPolicy(_ bytes: Data, fileName: String) -> RecordPolicy {
        guard let catalog = recordKind(fileName) else { return .unknown }
        return policyState(bytes, catalog: catalog)
    }

    /// Shared with derived-state maintenance. Call only after the same bounded
    /// descriptor read used by this cache; an unreadable record is preserved.
    static func isReclaimableRecord(_ bytes: Data, fileName: String) -> Bool {
        recordPolicy(bytes, fileName: fileName) != .unknown
    }

    /// Reserved interrupted atomic writes have no final record suffix. The
    /// lifecycle owner must first establish that exact staging filename.
    static func isReclaimableTemporaryRecord(_ bytes: Data) -> Bool {
        policyState(bytes, catalog: true) != .unknown || policyState(bytes, catalog: false) != .unknown
    }

    private static func recordKind(_ name: String) -> Bool? {
        let suffix: String
        let catalog: Bool
        if name.hasSuffix(".catalog.plist") {
            suffix = ".catalog.plist"
            catalog = true
        } else if name.hasSuffix(".projection.plist") {
            suffix = ".projection.plist"
            catalog = false
        } else if name.hasSuffix(".projection.json") {
            suffix = ".projection.json"
            catalog = false
        } else {
            return nil
        }
        let hash = name.dropLast(suffix.count).utf8
        guard hash.count == 64, hash.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else { return nil }
        return catalog
    }

    /// Unknown or future policy remains byte-unchanged and nonauthorizing.
    /// Unreadable/oversized records also remain untouched: bounded decoding
    /// cannot establish which policy owns them.
    private static func policyState(_ bytes: Data, catalog: Bool) -> RecordPolicy {
        let value: Any
        var format = PropertyListSerialization.PropertyListFormat.binary
        if let plist = try? PropertyListSerialization.propertyList(from: bytes, format: &format) {
            // Foundation accepts some truncated binary headers as an OpenStep
            // string. That is a damaged known binary record, not a new policy.
            if bytes.starts(with: Data("bplist00".utf8)), format != .binary { return .corrupt }
            value = plist
        } else if let json = try? JSONSerialization.jsonObject(with: bytes) {
            value = json
        } else {
            return .corrupt
        }
        guard let frame = value as? [String: Any], let policy = frame["policy"] as? [String: Any] else { return .unknown }
        let knownFrameKeys: Set<String> = ["policy", "vaultID", "role", "profile", "relativePathUTF8", "fingerprint", "payloadDigest", "payload"]
        guard Set(frame.keys).isSubset(of: knownFrameKeys) else { return .unknown }
        let currentIntegers: [String: Int]
        if catalog {
            currentIntegers = ["formatVersion": CatalogPolicy.current.formatVersion, "projectionVersion": CatalogPolicy.current.projectionVersion]
        } else {
            let current = Policy.current
            currentIntegers = [
                "formatVersion": current.formatVersion, "projectionVersion": current.projectionVersion,
                "searchVersion": current.searchVersion, "schemaVersion": current.schemaVersion,
                "tokenizerVersion": current.tokenizerVersion, "rankingVersion": current.rankingVersion,
            ]
        }
        guard Set(policy.keys) == Set(currentIntegers.keys).union(["markdownParserVersion", "yamlParserVersion"]) else { return .unknown }
        var retired = false
        for (key, current) in currentIntegers {
            guard let stored = policy[key] as? Int, stored <= current else { return .unknown }
            if stored < current { retired = true }
        }
        let parsers =
            catalog
            ? [("markdownParserVersion", CatalogPolicy.current.markdownParserVersion), ("yamlParserVersion", CatalogPolicy.current.yamlParserVersion)]
            : [("markdownParserVersion", Policy.current.markdownParserVersion), ("yamlParserVersion", Policy.current.yamlParserVersion)]
        for (key, current) in parsers {
            guard let stored = policy[key] as? String,
                let storedVersion = Self.versionComponents(stored), let currentVersion = Self.versionComponents(current),
                !currentVersion.lexicographicallyPrecedes(storedVersion)
            else { return .unknown }
            if storedVersion != currentVersion { retired = true }
        }
        return retired ? .retired : .current
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (0x30...0x39).contains($0) } }) else { return nil }
        let values = pieces.compactMap { Int($0) }
        return pieces.count == 3 && values.count == 3 && values.allSatisfy { $0 >= 0 } ? values : nil
    }

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
