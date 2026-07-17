import Foundation
import ScholiumContracts
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private struct RecommendedBibliographyStoredRecord: Codable, Hashable, Sendable {
    var preparation: RecommendedBibliographyPreparation
    var projection: RecommendedBibliographyProjection
}

private struct RecommendedBibliographyDocument: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var records: [RecommendedBibliographyStoredRecord] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case records
    }
}

/// Portable, app-owned recommendation state. This store never reads or writes
/// note bytes and never treats a recommendation as source evidence.
public actor RecommendedBibliographyStore {
    public nonisolated let fileURL: URL

    private let controlURL: URL
    private let lockURL: URL
    private let fileManager: FileManager

    public init(controlURL: URL, fileManager: FileManager = .default) {
        self.controlURL = controlURL.standardizedFileURL
        self.fileURL = controlURL.standardizedFileURL
            .appendingPathComponent("recommended-bibliography.json", isDirectory: false)
        self.lockURL = controlURL.standardizedFileURL
            .appendingPathComponent("recommended-bibliography.lock", isDirectory: false)
        self.fileManager = fileManager
    }

    public func overview(
        targetNoteID: UUID
    ) throws -> RecommendedBibliographyOverview {
        try withStoreLock(.shared) {
            let records = records(for: targetNoteID, in: try loadUnlocked())
            let latest = records.first
            let result = records.first {
                $0.projection.state == .complete
                    || ($0.projection.state == .stale
                        && $0.projection.completedAt != nil)
            }
            let active = records.first { $0.projection.state == .prepared }
            return RecommendedBibliographyOverview(
                result: result?.projection,
                activePreparation: active?.preparation,
                latestRun: latest?.projection
            )
        }
    }

    public func latest(
        targetNoteID: UUID
    ) throws -> RecommendedBibliographyProjection? {
        try overview(targetNoteID: targetNoteID).result
    }

    public func preparation(id: UUID) throws -> RecommendedBibliographyPreparation {
        try withStoreLock(.shared) {
            guard let preparation = try loadUnlocked().records.first(where: {
                $0.preparation.id == id
            })?.preparation else {
                throw RecommendedBibliographyError.requestNotFound(id)
            }
            return preparation
        }
    }

    public func projection(id: UUID) throws -> RecommendedBibliographyProjection {
        try withStoreLock(.shared) {
            guard let projection = try loadUnlocked().records.first(where: {
                $0.preparation.id == id
            })?.projection else {
                throw RecommendedBibliographyError.requestNotFound(id)
            }
            return projection
        }
    }

    public func save(
        preparation: RecommendedBibliographyPreparation
    ) throws -> RecommendedBibliographyProjection {
        try withStoreLock(.exclusive) {
            var document = try loadUnlocked()
            if let existing = document.records.first(where: {
                $0.preparation.id == preparation.id
            }) {
                guard existing.preparation == preparation else {
                    throw RecommendedBibliographyError.alreadyCompleted(preparation.id)
                }
                return existing.projection
            }
            if let active = document.records.first(where: {
                $0.preparation.request.target.noteID == preparation.request.target.noteID
                    && $0.projection.state == .prepared
            }) {
                throw RecommendedBibliographyError.activeRequestExists(active.preparation.id)
            }
            let projection = RecommendedBibliographyProjection(
                id: preparation.id,
                request: preparation.request,
                method: preparation.method,
                state: .prepared,
                preparedAt: preparation.preparedAt
            )
            document.records.append(RecommendedBibliographyStoredRecord(
                preparation: preparation,
                projection: projection
            ))
            try persistUnlocked(document)
            return projection
        }
    }

    public func complete(
        requestID: UUID,
        sourceScope: String,
        candidates: [RecommendedBibliographyCandidate],
        completedAt: Date = Date()
    ) throws -> RecommendedBibliographyProjection {
        let completedAt = Date(
            timeIntervalSince1970: floor(completedAt.timeIntervalSince1970)
        )
        return try withStoreLock(.exclusive) {
            var document = try loadUnlocked()
            guard let index = document.records.firstIndex(where: {
                $0.preparation.id == requestID
            }) else {
                throw RecommendedBibliographyError.requestNotFound(requestID)
            }
            let current = document.records[index]
            switch current.projection.state {
            case .complete:
                if current.projection.sourceScope == sourceScope,
                   current.projection.candidates == candidates {
                    return current.projection
                }
                throw RecommendedBibliographyError.alreadyCompleted(requestID)
            case .cancelled:
                throw RecommendedBibliographyError.cancelled(requestID)
            case .stale:
                throw RecommendedBibliographyError.targetChanged
            case .prepared:
                break
            }
            let projection = RecommendedBibliographyProjection(
                id: current.preparation.id,
                request: current.preparation.request,
                method: current.preparation.method,
                state: .complete,
                sourceScope: sourceScope,
                candidates: candidates,
                preparedAt: current.preparation.preparedAt,
                completedAt: completedAt
            )
            document.records[index].projection = projection
            try persistUnlocked(document)
            return projection
        }
    }

    public func markStale(id: UUID) throws {
        try withStoreLock(.exclusive) {
            var document = try loadUnlocked()
            guard let index = document.records.firstIndex(where: {
                $0.preparation.id == id
            }) else {
                throw RecommendedBibliographyError.requestNotFound(id)
            }
            let current = document.records[index].projection
            guard current.state != .cancelled, current.state != .stale else { return }
            document.records[index].projection = RecommendedBibliographyProjection(
                id: current.id,
                request: current.request,
                method: current.method,
                state: .stale,
                sourceScope: current.sourceScope,
                candidates: current.candidates,
                preparedAt: current.preparedAt,
                completedAt: current.completedAt
            )
            try persistUnlocked(document)
        }
    }

    public func cancel(id: UUID) throws {
        try withStoreLock(.exclusive) {
            var document = try loadUnlocked()
            guard let index = document.records.firstIndex(where: {
                $0.preparation.id == id
            }) else {
                throw RecommendedBibliographyError.requestNotFound(id)
            }
            let current = document.records[index].projection
            if current.state == .cancelled { return }
            guard current.state != .complete else {
                throw RecommendedBibliographyError.alreadyCompleted(id)
            }
            document.records[index].projection = RecommendedBibliographyProjection(
                id: current.id,
                request: current.request,
                method: current.method,
                state: .cancelled,
                sourceScope: current.sourceScope,
                candidates: current.candidates,
                preparedAt: current.preparedAt,
                completedAt: current.completedAt
            )
            try persistUnlocked(document)
        }
    }

    public func dismiss(requestID: UUID, candidateID: UUID) throws {
        try withStoreLock(.exclusive) {
            var document = try loadUnlocked()
            guard let recordIndex = document.records.firstIndex(where: {
                $0.projection.id == requestID
            }) else {
                throw RecommendedBibliographyError.requestNotFound(requestID)
            }
            let projection = document.records[recordIndex].projection
            guard let candidateIndex = projection.candidates.firstIndex(where: {
                $0.id == candidateID
            }) else {
                throw RecommendedBibliographyError.candidateNotFound(candidateID)
            }
            var candidates = projection.candidates
            let candidate = candidates[candidateIndex]
            candidates[candidateIndex] = candidate.deriving(
                matchState: candidate.matchState,
                matchedAnalysis: candidate.matchedAnalysis,
                matchedZoteroItemKey: candidate.matchedZoteroItemKey,
                duplicateOfCandidateID: candidate.duplicateOfCandidateID,
                isDismissed: true
            )
            document.records[recordIndex].projection = RecommendedBibliographyProjection(
                id: projection.id,
                request: projection.request,
                method: projection.method,
                state: projection.state,
                sourceScope: projection.sourceScope,
                candidates: candidates,
                preparedAt: projection.preparedAt,
                completedAt: projection.completedAt
            )
            try persistUnlocked(document)
        }
    }

    private func loadUnlocked() throws -> RecommendedBibliographyDocument {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return RecommendedBibliographyDocument()
        }
        let values = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw RecommendedBibliographyError.storeUnavailable(
                "Recommended Bibliography storage is not a safe regular file."
            )
        }
        do {
            let document = try JSONDecoder.researchPersistence.decode(
                RecommendedBibliographyDocument.self,
                from: Data(contentsOf: fileURL)
            )
            guard document.schemaVersion == RecommendedBibliographyDocument.currentSchemaVersion else {
                throw RecommendedBibliographyError.storeUnavailable(
                    "Recommended Bibliography uses an unsupported schema version."
                )
            }
            return document
        } catch let error as RecommendedBibliographyError {
            throw error
        } catch {
            throw RecommendedBibliographyError.storeUnavailable(
                "Recommended Bibliography storage is malformed: \(error.localizedDescription)"
            )
        }
    }

    private func persistUnlocked(_ document: RecommendedBibliographyDocument) throws {
        let data = try JSONEncoder.researchPersistence.encode(document)
        try data.write(to: fileURL, options: .atomic)
        let readback = try Data(contentsOf: fileURL)
        guard readback == data else {
            throw RecommendedBibliographyError.storeUnavailable(
                "Recommended Bibliography storage could not be verified after writing."
            )
        }
    }

    private func records(
        for targetNoteID: UUID,
        in document: RecommendedBibliographyDocument
    ) -> [RecommendedBibliographyStoredRecord] {
        document.records
            .filter { $0.projection.request.target.noteID == targetNoteID }
            .sorted { lhs, rhs in
                if lhs.preparation.preparedAt != rhs.preparation.preparedAt {
                    return lhs.preparation.preparedAt > rhs.preparation.preparedAt
                }
                return lhs.preparation.id.uuidString > rhs.preparation.id.uuidString
            }
    }

    private enum StoreLockMode {
        case shared
        case exclusive

        var operation: Int32 { self == .shared ? LOCK_SH : LOCK_EX }
    }

    private func withStoreLock<T>(
        _ mode: StoreLockMode,
        operation: () throws -> T
    ) throws -> T {
        try ensureControlDirectory()
        let descriptor = lockURL.path.withCString {
            open($0, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw RecommendedBibliographyError.storeUnavailable(
                "Recommended Bibliography could not acquire its coordination file."
            )
        }
        defer { close(descriptor) }
        guard flock(descriptor, mode.operation) == 0 else {
            throw RecommendedBibliographyError.storeUnavailable(
                "Recommended Bibliography could not coordinate App and CLI access."
            )
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func ensureControlDirectory() throws {
        if !fileManager.fileExists(atPath: controlURL.path) {
            try fileManager.createDirectory(at: controlURL, withIntermediateDirectories: true)
        }
        let values = try controlURL.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw RecommendedBibliographyError.storeUnavailable(
                "The portable Scholium control directory is unsafe."
            )
        }
    }
}

private extension JSONEncoder {
    static var researchPersistence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var researchPersistence: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
