import Foundation
import ScholiumContracts

/// App-owned page marginalia. An Annotation is durable page state, not a
/// Research Activity event or a Research Record entry.
public actor PageAnnotationStore {
    private static let currentSchemaVersion = 1

    private struct Payload: Codable {
        var schemaVersion: Int
        var annotations: [AnnotationRecord]
        var migratedLegacyAnnotationIDs: Set<UUID>
    }

    public let storageURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private var payload: Payload
    private let loadFailure: String?

    public init(storageURL: URL, fileManager: FileManager = .default) {
        self.storageURL = storageURL
        self.fileURL = storageURL.appendingPathComponent("page-annotations.json")
        self.fileManager = fileManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let decoded = try decoder.decode(Payload.self, from: data)
                guard decoded.schemaVersion == Self.currentSchemaVersion else {
                    payload = Self.emptyPayload
                    loadFailure = "Unsupported Page Annotation schema version \(decoded.schemaVersion)."
                    return
                }
                payload = decoded
                loadFailure = nil
            } catch {
                payload = Self.emptyPayload
                loadFailure = error.localizedDescription
            }
        } else {
            payload = Self.emptyPayload
            loadFailure = nil
        }
    }

    public func healthError() -> String? {
        loadFailure.map {
            ResearchRecordStoreError.unreadableStore(kind: "Page Annotation", reason: $0)
                .localizedDescription
        }
    }

    public func annotations(for noteID: UUID) -> [AnnotationRecord] {
        payload.annotations
            .filter { $0.noteID == noteID }
            .sorted(by: Self.annotationOrder)
    }

    public func allAnnotations() -> [AnnotationRecord] {
        payload.annotations.sorted(by: Self.annotationOrder)
    }

    @discardableResult
    public func add(_ annotation: AnnotationRecord) throws -> AnnotationRecord {
        try requireHealthyStore()
        guard !annotation.text.isEmpty else {
            throw AnnotationStoreError.emptyAnnotation
        }
        guard !payload.annotations.contains(where: { $0.id == annotation.id }) else {
            throw AnnotationStoreError.duplicateAnnotation(annotation.id)
        }
        var proposed = payload
        proposed.annotations.append(annotation)
        try commit(proposed)
        return annotation
    }

    @discardableResult
    public func update(
        noteID: UUID,
        annotationID: UUID,
        text: String
    ) throws -> AnnotationRecord {
        try requireHealthyStore()
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AnnotationStoreError.emptyAnnotation
        }
        guard let index = payload.annotations.firstIndex(where: {
            $0.noteID == noteID && $0.id == annotationID
        }) else {
            throw AnnotationStoreError.annotationNotFound(annotationID)
        }
        var proposed = payload
        proposed.annotations[index].text = normalized
        proposed.annotations[index].updatedAt = Date()
        let updated = proposed.annotations[index]
        try commit(proposed)
        return updated
    }

    @discardableResult
    public func setResolved(
        noteID: UUID,
        annotationID: UUID,
        resolved: Bool
    ) throws -> AnnotationRecord {
        try requireHealthyStore()
        guard let index = payload.annotations.firstIndex(where: {
            $0.noteID == noteID && $0.id == annotationID
        }) else {
            throw AnnotationStoreError.annotationNotFound(annotationID)
        }
        var proposed = payload
        proposed.annotations[index].resolvedAt = resolved ? Date() : nil
        proposed.annotations[index].updatedAt = Date()
        let updated = proposed.annotations[index]
        try commit(proposed)
        return updated
    }

    @discardableResult
    public func reattach(
        noteID: UUID,
        annotationID: UUID,
        anchor: ResearcherCommentAnchor
    ) throws -> AnnotationRecord {
        try requireHealthyStore()
        guard let index = payload.annotations.firstIndex(where: {
            $0.noteID == noteID && $0.id == annotationID
        }) else {
            throw AnnotationStoreError.annotationNotFound(annotationID)
        }
        var attached = anchor
        attached.state = .attached
        var proposed = payload
        proposed.annotations[index].anchor = attached
        proposed.annotations[index].updatedAt = Date()
        let updated = proposed.annotations[index]
        try commit(proposed)
        return updated
    }

    /// Reattaches only when the saved quotation and bounded context resolve
    /// to one exact range. Ambiguous marginalia remain visibly unattached.
    public func reattachAll(
        noteID: UUID,
        to document: NoteDocument
    ) throws -> [AnnotationRecord] {
        try requireHealthyStore()
        let indices = payload.annotations.indices.filter {
            payload.annotations[$0].noteID == noteID
        }
        guard !indices.isEmpty else { return [] }
        var proposed = payload
        var changed = false
        for index in indices {
            var annotation = proposed.annotations[index]
            let anchor = annotation.anchor
            guard anchor.fingerprint != document.fingerprint
                    || anchor.state == .needsReattachment else { continue }
            let candidates = Self.ranges(of: anchor.quotation, in: document.rawContent)
            let reliable = candidates.filter {
                Self.contextMatches(anchor: anchor, range: $0, source: document.rawContent)
            }
            guard reliable.count == 1, let range = reliable.first else {
                if annotation.anchor.state != .needsReattachment {
                    annotation.anchor.state = .needsReattachment
                    annotation.updatedAt = Date()
                    proposed.annotations[index] = annotation
                    changed = true
                }
                continue
            }
            let utf16Start = range.lowerBound.utf16Offset(in: document.rawContent)
            let utf16End = range.upperBound.utf16Offset(in: document.rawContent)
            let prefix = document.rawContent[..<range.lowerBound]
            let startLine = prefix.reduce(into: 1) { if $1.isNewline { $0 += 1 } }
            let selected = document.rawContent[range]
            let endLine = selected.dropLast().reduce(into: startLine) {
                if $1.isNewline { $0 += 1 }
            }
            let utf8Start = prefix.utf8.count
            let utf8End = document.rawContent[..<range.upperBound].utf8.count
            annotation.anchor.fingerprint = document.fingerprint
            annotation.anchor.utf8Range = utf8Start..<utf8End
            annotation.anchor.utf16Range = utf16Start..<utf16End
            annotation.anchor.line = startLine
            annotation.anchor.endLine = max(startLine, endLine)
            annotation.anchor.state = .attached
            annotation.updatedAt = Date()
            proposed.annotations[index] = annotation
            changed = true
        }
        if changed { try commit(proposed) }
        return proposed.annotations
            .filter { $0.noteID == noteID }
            .sorted(by: Self.annotationOrder)
    }

    @discardableResult
    public func remove(
        noteID: UUID,
        annotationID: UUID
    ) throws -> AnnotationRecord {
        try requireHealthyStore()
        guard let index = payload.annotations.firstIndex(where: {
            $0.noteID == noteID && $0.id == annotationID
        }) else {
            throw AnnotationStoreError.annotationNotFound(annotationID)
        }
        var proposed = payload
        let removed = proposed.annotations.remove(at: index)
        try commit(proposed)
        return removed
    }

    /// Removes every marginal note owned by one page. Permanent document
    /// deletion uses the returned values as its rollback copy.
    @discardableResult
    public func purge(noteID: UUID) throws -> [AnnotationRecord] {
        try requireHealthyStore()
        let removed = payload.annotations.filter { $0.noteID == noteID }
        guard !removed.isEmpty else { return [] }
        var proposed = payload
        proposed.annotations.removeAll { $0.noteID == noteID }
        try commit(proposed)
        return removed.sorted(by: Self.annotationOrder)
    }

    /// Restores a deletion transaction's exact page marginalia. Existing IDs
    /// make recovery idempotent after an interrupted rollback.
    public func restorePurgedAnnotations(_ annotations: [AnnotationRecord]) throws {
        try requireHealthyStore()
        let existingIDs = Set(payload.annotations.map(\.id))
        let additions = annotations.filter { !existingIDs.contains($0.id) }
        guard !additions.isEmpty else { return }
        var proposed = payload
        proposed.annotations.append(contentsOf: additions)
        try commit(proposed)
    }

    /// One-way compatibility import. Legacy Review state itself never enters
    /// this page store and no activity event is inferred.
    public func importLegacyAnnotations(_ annotations: [AnnotationRecord]) throws {
        try requireHealthyStore()
        let additions = annotations.filter { annotation in
            !payload.migratedLegacyAnnotationIDs.contains(annotation.id)
                && !payload.annotations.contains(where: { $0.id == annotation.id })
        }
        guard !additions.isEmpty else { return }
        var proposed = payload
        proposed.annotations.append(contentsOf: additions)
        proposed.migratedLegacyAnnotationIDs.formUnion(additions.map(\.id))
        try commit(proposed)
    }

    private static var emptyPayload: Payload {
        Payload(
            schemaVersion: currentSchemaVersion,
            annotations: [],
            migratedLegacyAnnotationIDs: []
        )
    }

    private func requireHealthyStore() throws {
        if let loadFailure {
            throw ResearchRecordStoreError.unreadableStore(
                kind: "Page Annotation",
                reason: loadFailure
            )
        }
    }

    private func commit(_ proposed: Payload) throws {
        try requireHealthyStore()
        try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(proposed)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let canonical = try decoder.decode(Payload.self, from: data)
        try data.write(to: fileURL, options: .atomic)
        payload = canonical
    }

    private static func ranges(
        of needle: String,
        in source: String
    ) -> [Range<String.Index>] {
        guard !needle.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var cursor = source.startIndex
        while cursor < source.endIndex,
              let range = source.range(of: needle, range: cursor..<source.endIndex) {
            result.append(range)
            cursor = range.upperBound
        }
        return result
    }

    private static func contextMatches(
        anchor: ResearcherCommentAnchor,
        range: Range<String.Index>,
        source: String
    ) -> Bool {
        let beforeNeedle = String(
            anchor.contextBefore.suffix(ResearcherCommentAnchorBuilder.contextLength)
        )
        let afterNeedle = String(
            anchor.contextAfter.prefix(ResearcherCommentAnchorBuilder.contextLength)
        )
        let beforeStart = source.index(
            range.lowerBound,
            offsetBy: -beforeNeedle.count,
            limitedBy: source.startIndex
        ) ?? source.startIndex
        let afterEnd = source.index(
            range.upperBound,
            offsetBy: afterNeedle.count,
            limitedBy: source.endIndex
        ) ?? source.endIndex
        let before = String(source[beforeStart..<range.lowerBound])
        let after = String(source[range.upperBound..<afterEnd])
        return (beforeNeedle.isEmpty || before.hasSuffix(beforeNeedle))
            && (afterNeedle.isEmpty || after.hasPrefix(afterNeedle))
    }

    private static func annotationOrder(_ lhs: AnnotationRecord, _ rhs: AnnotationRecord) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public enum AnnotationStoreError: LocalizedError, Sendable {
    case emptyAnnotation
    case duplicateAnnotation(UUID)
    case annotationNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .emptyAnnotation:
            "An Annotation cannot be empty."
        case .duplicateAnnotation(let id):
            "Annotation already exists: \(id.uuidString)"
        case .annotationNotFound(let id):
            "Annotation was not found: \(id.uuidString)"
        }
    }
}
