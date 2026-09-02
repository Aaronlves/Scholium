import Foundation
import ScholiumContracts

public enum ResearchRecordStoreError: LocalizedError, Hashable, Sendable {
    case missing(UUID)
    case alreadyExists(UUID)
    case invalid(UUID?)
    case staleRevision(
        recordID: UUID,
        expected: DocumentFingerprint,
        current: DocumentFingerprint
    )
    case stepMissing(recordID: UUID, stepID: UUID)
    case operationUncertain(UUID)
    case unsafeStore(String)
    case coordinationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missing:
            "The Research Record was not found."
        case .alreadyExists:
            "The Research Record identity is already present."
        case .invalid:
            "The Research Record is damaged or has an unsupported schema."
        case .staleRevision:
            "The Research Record fingerprint is stale."
        case .stepMissing:
            "The Research Record step was not found."
        case .operationUncertain:
            "The Research Record operation may have committed."
        case .unsafeStore(let reason):
            "Research Records are unavailable: \(reason)"
        case .coordinationFailed(let reason):
            "Research Record file coordination failed: \(reason)"
        }
    }
}

/// Strict portable authority for the replacement continuing-inquiry contract.
/// One file is one Record; legacy Record and Settlement namespaces are never read.
public actor ResearchRecordStore {
    private static let maximumRecordByteCount = 4 * 1_024 * 1_024

    public nonisolated let storageURL: URL
    private let triptychID: UUID
    private let storage: SecureRecordDirectory
    private let lock: AdvisoryFileLock

    public init(
        controlURL: URL,
        applicationSupportURL: URL,
        triptychID: UUID
    ) throws {
        self.triptychID = triptychID
        storageURL = controlURL
            .appendingPathComponent("inquiry-records", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        storage = SecureRecordDirectory(
            trustedRootURL: controlURL,
            components: ["inquiry-records", "v1"],
            directoryMode: 0o755,
            fileMode: 0o600,
            maximumByteCount: Self.maximumRecordByteCount
        )
        let coordination = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Triptychs", triptychID.uuidString],
            directoryMode: 0o700,
            fileMode: 0o600,
            maximumByteCount: 1
        )
        do {
            try coordination.ensureDirectories([])
            lock = try AdvisoryFileLock(
                directory: coordination,
                fileName: "inquiry-records-v1.lock"
            )
            try lock.withExclusiveLock {
                try Self.coordinateWrite(at: storageURL) {
                    try storage.ensureDirectories([])
                    try storage.removeAbandonedStagingFiles(in: [nil])
                }
            }
        } catch {
            throw ResearchRecordStoreError.unsafeStore(error.localizedDescription)
        }
    }

    public func listing() throws -> ResearchRecordListing {
        try withSharedCoordination {
            var records: [ResearchRecordRevision] = []
            var issues: [ResearchRecordStoreIssue] = []
            for name in try storage.fileNames(in: nil) {
                guard name.hasSuffix(".json") else {
                    issues.append(ResearchRecordStoreIssue(
                        fileName: name,
                        reason: "The inquiry-record directory contains an unsupported entry."
                    ))
                    continue
                }
                do {
                    let expectedID = try recordID(from: name)
                    records.append(try decodeRevision(
                        storage.read(directory: nil, fileName: name),
                        expectedID: expectedID
                    ))
                } catch {
                    issues.append(ResearchRecordStoreIssue(
                        fileName: name,
                        reason: error.localizedDescription
                    ))
                }
            }
            records.sort {
                if $0.record.lastSubstantiveAt != $1.record.lastSubstantiveAt {
                    return $0.record.lastSubstantiveAt > $1.record.lastSubstantiveAt
                }
                let questionOrder = $0.record.question.localizedStandardCompare(
                    $1.record.question
                )
                if questionOrder != .orderedSame { return questionOrder == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
            return ResearchRecordListing(
                records: records,
                issues: issues.sorted { $0.fileName < $1.fileName }
            )
        }
    }

    public func record(id: UUID) throws -> ResearchRecordRevision {
        try withSharedCoordination {
            do {
                return try decodeRevision(
                    storage.read(directory: nil, fileName: fileName(id)),
                    expectedID: id
                )
            } catch let error as SecureRecordDirectoryError {
                if case .notFound = error { throw ResearchRecordStoreError.missing(id) }
                throw ResearchRecordStoreError.unsafeStore(error.localizedDescription)
            }
        }
    }

    public func create(
        id: UUID = UUID(),
        stepID: UUID = UUID(),
        question: String,
        submittedBy: ResearchRecordSubmitter,
        bodyMarkdown: String,
        revisesStepIDs: [UUID] = [],
        noteReferences: [ResearchRecordNoteReference] = [],
        recordedAt: Date = Date()
    ) throws -> ResearchRecordProgressResult {
        let step = try ResearchRecordStep(
            id: stepID,
            recordedAt: recordedAt,
            submittedBy: submittedBy,
            bodyMarkdown: bodyMarkdown,
            revisesStepIDs: revisesStepIDs,
            noteReferences: noteReferences
        )
        let record = try ResearchRecord(
            id: id,
            triptychID: triptychID,
            question: question,
            steps: [step]
        )
        try validatePortableText(record)
        return try withExclusiveCoordination {
            do {
                let readback = try storage.createExclusive(
                    encode(record),
                    directory: nil,
                    fileName: fileName(id)
                )
                return ResearchRecordProgressResult(
                    kind: .created,
                    revision: try decodeRevision(readback, expectedID: id),
                    stepID: stepID
                )
            } catch let error as SecureRecordDirectoryError {
                switch error {
                case .alreadyExists:
                    throw ResearchRecordStoreError.alreadyExists(id)
                case .replacementCommitUncertain:
                    throw ResearchRecordStoreError.operationUncertain(id)
                default:
                    throw ResearchRecordStoreError.unsafeStore(error.localizedDescription)
                }
            }
        }
    }

    public func append(
        recordID: UUID,
        expectedFingerprint: DocumentFingerprint,
        stepID: UUID = UUID(),
        submittedBy: ResearchRecordSubmitter,
        bodyMarkdown: String,
        revisesStepIDs: [UUID] = [],
        noteReferences: [ResearchRecordNoteReference] = [],
        replacementQuestion: String? = nil,
        recordedAt: Date = Date()
    ) throws -> ResearchRecordProgressResult {
        try withExclusiveCoordination {
            let current = try readForMutation(
                id: recordID,
                expectedFingerprint: expectedFingerprint
            )
            let step = try ResearchRecordStep(
                id: stepID,
                recordedAt: recordedAt,
                submittedBy: submittedBy,
                bodyMarkdown: bodyMarkdown,
                revisesStepIDs: revisesStepIDs,
                noteReferences: noteReferences
            )
            let updated = try current.record.appending(
                step,
                question: replacementQuestion
            )
            try validatePortableText(updated)
            let revision = try replace(updated, expectedID: recordID)
            return ResearchRecordProgressResult(
                kind: .appended,
                revision: revision,
                stepID: stepID
            )
        }
    }

    public func correct(
        recordID: UUID,
        stepID: UUID,
        expectedFingerprint: DocumentFingerprint,
        correctionID: UUID = UUID(),
        submittedBy: ResearchRecordSubmitter,
        bodyMarkdown: String,
        revisesStepIDs: [UUID],
        noteReferences: [ResearchRecordNoteReference],
        correctedAt: Date = Date()
    ) throws -> ResearchRecordRevision {
        try withExclusiveCoordination {
            let current = try readForMutation(
                id: recordID,
                expectedFingerprint: expectedFingerprint
            )
            guard current.record.steps.contains(where: { $0.id == stepID }) else {
                throw ResearchRecordStoreError.stepMissing(
                    recordID: recordID,
                    stepID: stepID
                )
            }
            let correction = try ResearchRecordCorrection(
                id: correctionID,
                correctedAt: correctedAt,
                submittedBy: submittedBy,
                bodyMarkdown: bodyMarkdown,
                revisesStepIDs: revisesStepIDs,
                noteReferences: noteReferences
            )
            let updated = try current.record.correcting(
                stepID: stepID,
                with: correction
            )
            try validatePortableText(updated)
            return try replace(updated, expectedID: recordID)
        }
    }

    private func readForMutation(
        id: UUID,
        expectedFingerprint: DocumentFingerprint
    ) throws -> ResearchRecordRevision {
        let data: Data
        do {
            data = try storage.read(directory: nil, fileName: fileName(id))
        } catch let error as SecureRecordDirectoryError {
            if case .notFound = error { throw ResearchRecordStoreError.missing(id) }
            throw ResearchRecordStoreError.unsafeStore(error.localizedDescription)
        }
        let currentFingerprint = DocumentFingerprint(data: data)
        guard currentFingerprint == expectedFingerprint else {
            throw ResearchRecordStoreError.staleRevision(
                recordID: id,
                expected: expectedFingerprint,
                current: currentFingerprint
            )
        }
        return try decodeRevision(data, expectedID: id)
    }

    private func replace(
        _ record: ResearchRecord,
        expectedID: UUID
    ) throws -> ResearchRecordRevision {
        do {
            let readback = try storage.replace(
                encode(record),
                directory: nil,
                fileName: fileName(expectedID)
            )
            return try decodeRevision(readback, expectedID: expectedID)
        } catch let error as SecureRecordDirectoryError {
            if case .replacementCommitUncertain = error {
                throw ResearchRecordStoreError.operationUncertain(expectedID)
            }
            throw ResearchRecordStoreError.unsafeStore(error.localizedDescription)
        }
    }

    private func encode(_ record: ResearchRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        guard data.count <= Self.maximumRecordByteCount else {
            throw ResearchRecordStoreError.invalid(record.id)
        }
        return data
    }

    private func decodeRevision(
        _ data: Data,
        expectedID: UUID
    ) throws -> ResearchRecordRevision {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(ResearchRecord.self, from: data)
            guard record.id == expectedID, record.triptychID == triptychID else {
                throw ResearchRecordStoreError.invalid(expectedID)
            }
            try validatePortableText(record)
            return ResearchRecordRevision(
                record: record,
                fingerprint: DocumentFingerprint(data: data)
            )
        } catch let error as ResearchRecordStoreError {
            throw error
        } catch {
            throw ResearchRecordStoreError.invalid(expectedID)
        }
    }

    private func validatePortableText(_ record: ResearchRecord) throws {
        let submitters = record.steps.flatMap { step in
            [step.submittedBy] + step.corrections.map(\.submittedBy)
        }
        let bodies = record.steps.flatMap { step in
            [step.bodyMarkdown] + step.corrections.map(\.bodyMarkdown)
        }
        guard !ResearchStoreCodingValidation.containsAbsolutePath(record.question),
              submitters.allSatisfy({
                  !ResearchStoreCodingValidation.containsAbsolutePath($0.displayName)
              }),
              bodies.allSatisfy({
                  !ResearchStoreCodingValidation.containsAbsolutePath($0)
              }) else {
            throw ResearchRecordStoreError.invalid(record.id)
        }
    }

    private func fileName(_ id: UUID) -> String {
        "\(id.uuidString.lowercased()).json"
    }

    private func recordID(from fileName: String) throws -> UUID {
        let raw = String(fileName.dropLast(".json".count))
        guard let id = UUID(uuidString: raw), raw == id.uuidString.lowercased() else {
            throw ResearchRecordStoreError.invalid(nil)
        }
        return id
    }

    private func withExclusiveCoordination<T>(_ operation: () throws -> T) throws -> T {
        try lock.withExclusiveLock {
            try Self.coordinateWrite(at: storageURL, operation)
        }
    }

    private func withSharedCoordination<T>(_ operation: () throws -> T) throws -> T {
        try lock.withSharedLock {
            try Self.coordinateRead(at: storageURL, operation)
        }
    }

    private static func coordinateWrite<T>(
        at url: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            guard coordinatedURL.standardizedFileURL == url.standardizedFileURL else {
                result = .failure(ResearchRecordStoreError.coordinationFailed(
                    "The coordinated Record root moved during the operation."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError {
            throw ResearchRecordStoreError.coordinationFailed(
                coordinationError.localizedDescription
            )
        }
        guard let result else {
            throw ResearchRecordStoreError.coordinationFailed(
                "The file coordinator did not execute the write."
            )
        }
        return try result.get()
    }

    private static func coordinateRead<T>(
        at url: URL,
        _ operation: () throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            guard coordinatedURL.standardizedFileURL == url.standardizedFileURL else {
                result = .failure(ResearchRecordStoreError.coordinationFailed(
                    "The coordinated Record root moved during the operation."
                ))
                return
            }
            result = Result { try operation() }
        }
        if let coordinationError {
            throw ResearchRecordStoreError.coordinationFailed(
                coordinationError.localizedDescription
            )
        }
        guard let result else {
            throw ResearchRecordStoreError.coordinationFailed(
                "The file coordinator did not execute the read."
            )
        }
        return try result.get()
    }
}
