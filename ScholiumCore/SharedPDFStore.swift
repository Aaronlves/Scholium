import Foundation
import PDFKit
import ScholiumContracts

/// One shared portable PDF byte owner. Catalog entries locate files and
/// provenance; only authored Note source establishes a binding.
public actor SharedPDFStore {
    private let controlURL: URL
    private let control: TriptychControlStore
    private let rootAccess: VaultDescriptorAccess
    private let attachments: VaultAttachmentStore
    private let recovery: SecureRecordDirectory
    private let recoveryLock: AdvisoryFileLock
    private var closed = false
    private var importInProgress = false
    private var importWaiters: [CheckedContinuation<Void, Never>] = []
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var beforeCommitForTesting: (@Sendable (URL) throws -> Void)?
    private var afterCommitForTesting: (@Sendable (URL) throws -> Void)?
    private var onClosingForTesting: (@Sendable () -> Void)?

    public init(controlURL: URL, controlStore: TriptychControlStore, applicationSupportURL: URL, triptychID: UUID) throws {
        self.controlURL = controlURL.standardizedFileURL
        control = controlStore
        rootAccess = try VaultDescriptorAccess(rootURL: self.controlURL)
        attachments = VaultAttachmentStore(vaultURL: self.controlURL)
        recovery = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Triptychs", triptychID.uuidString, "PDFReader", "Recovery"],
            directoryMode: 0o700, fileMode: 0o600, maximumByteCount: PDFReaderFileAccess.maximumBytes,
            filePolicy: .pdfRecovery)
        try recovery.ensureDirectories([])
        recoveryLock = try AdvisoryFileLock(directory: recovery, fileName: "recovery.lock")
    }

    public func records() async throws -> [PortableAttachmentRecord] {
        guard !closed else { throw PDFReaderError.unreadable }
        try rootAccess.verifyRootIdentity()
        return try await control.attachmentRecords().filter {
            if case .triptychRelative(let path) = $0.location {
                return path.rawValue.lowercased().hasSuffix(".pdf")
            }
            return false
        }
    }

    public func importPDF(
        at selectedURL: URL, zoteroSource: ZoteroPDFSource?, allowNewVersion: Bool, revalidateSource: (@Sendable () async throws -> Void)? = nil
    ) async throws -> (snapshot: PDFReaderSnapshot, wasNew: Bool) {
        guard !closed else { throw PDFReaderError.unreadable }
        await acquireImport()
        defer { releaseImport() }
        try Task.checkCancellation()
        guard !closed else { throw PDFReaderError.unreadable }
        try rootAccess.verifyRootIdentity()
        guard selectedURL.isFileURL else { throw PDFReaderError.unsafePath }
        let started = selectedURL.startAccessingSecurityScopedResource()
        defer { if started { selectedURL.stopAccessingSecurityScopedResource() } }
        let source = try PDFReaderFileAccess.read(at: selectedURL.standardizedFileURL)
        try Self.validate(source.data)
        try Task.checkCancellation()
        let current = try await records()
        try await revalidateSource?()
        let verifiedSource = try PDFReaderFileAccess.read(at: selectedURL.standardizedFileURL)
        guard verifiedSource.revision == source.revision, verifiedSource.data == source.data else { throw PDFReaderError.sourceChanged }
        let matching = current.filter { record in
            if let zoteroSource { return record.zoteroSource?.stableIdentity == zoteroSource.stableIdentity }
            return record.zoteroSource == nil && record.importedSourceFingerprint == source.revision.fingerprint
        }
        if !allowNewVersion, let existing = matching.first(where: { $0.importedSourceFingerprint == source.revision.fingerprint }) {
            return (try await load(attachmentID: existing.id), false)
        }
        if zoteroSource != nil, !matching.isEmpty, !allowNewVersion { throw PDFReaderError.sourceChanged }
        guard !closed else { throw PDFReaderError.unreadable }
        try rootAccess.verifyRootIdentity()
        try Task.checkCancellation()
        let id = UUID()
        var filename = selectedURL.lastPathComponent
        if !filename.lowercased().hasSuffix(".pdf") { filename += ".pdf" }
        let file = try await attachments.copySharedDocumentSnapshot(source.data, filename: filename, attachmentID: id)
        do {
            try Task.checkCancellation()
            guard !closed else { throw PDFReaderError.unreadable }
            try rootAccess.verifyRootIdentity()
            let registered = try await control.registerAttachment(
                vaultID: nil, location: file.location, preferredID: id,
                importedSourceFingerprint: source.revision.fingerprint, zoteroSource: zoteroSource)
            return (try await load(attachmentID: registered.record.id), true)
        } catch {
            // Only confirmed absence of our catalog entry permits attempt-owned cleanup.
            if let catalog = try? await control.attachmentRecords(), !catalog.contains(where: { $0.id == id }),
                let path = file.copiedRelativePath
            {
                try? await attachments.removeCopiedDocumentIfExact(relativePath: path, expectedFingerprint: source.revision.fingerprint)
            }
            throw error
        }
    }

    public func load(attachmentID: UUID) async throws -> PDFReaderSnapshot {
        let record = try await record(attachmentID)
        let read = try read(record)
        try Self.validate(read.data)
        for transaction in try retainedRecoveries(attachmentID: attachmentID)
        where transaction.candidateFingerprint == read.revision.fingerprint {
            if try recoveryData(transaction) == read.data {
                // Matching current bytes prove that an interrupted prior save
                // already committed. Cleanup never writes to the shared PDF.
                try removeRecovery(transaction)
            }
        }
        return PDFReaderSnapshot(
            record: record, data: read.data, revision: read.revision, recoveryCandidates: try retainedRecoveries(attachmentID: attachmentID))
    }

    public func resolve(noteURL: URL, authoredPath: String) async throws -> PDFReaderSnapshot {
        let record = try await bindingRecord(noteURL: noteURL, authoredPath: authoredPath)
        return try await load(attachmentID: record.id)
    }

    public func bindingRecord(noteURL: URL, authoredPath: String) async throws -> PortableAttachmentRecord {
        guard !authoredPath.isEmpty, !authoredPath.contains("\0"), !authoredPath.hasPrefix("/"),
            !authoredPath.hasPrefix("//"), URLComponents(string: authoredPath)?.scheme == nil
        else { throw PDFReaderError.invalidBinding }
        // YAML paths are filesystem text, not URL/Markdown percent-encoded destinations.
        let resolved = noteURL.deletingLastPathComponent().appendingPathComponent(authoredPath).standardizedFileURL
        let rootParts = controlURL.pathComponents
        let parts = resolved.pathComponents
        guard parts.count > rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else { throw PDFReaderError.invalidBinding }
        let relative = parts.dropFirst(rootParts.count).joined(separator: "/")
        guard
            let record = try await records().first(where: {
                if case .triptychRelative(let path) = $0.location { return path.rawValue == relative }
                return false
            })
        else { throw PDFReaderError.invalidBinding }
        return record
    }

    public func rebaseBinding(authoredPath: String, from sourceNoteURL: URL, to destinationNoteURL: URL) async throws -> String {
        let record = try await bindingRecord(noteURL: sourceNoteURL, authoredPath: authoredPath)
        return try await self.authoredPath(attachmentID: record.id, noteURL: destinationNoteURL)
    }

    public func authoredPath(attachmentID: UUID, noteURL: URL) async throws -> String {
        let record = try await record(attachmentID)
        let destination = try url(record)
        var sourceParts = noteURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        var destinationParts = destination.pathComponents
        while !sourceParts.isEmpty, !destinationParts.isEmpty, sourceParts[0] == destinationParts[0] {
            sourceParts.removeFirst()
            destinationParts.removeFirst()
        }
        return (Array(repeating: "..", count: sourceParts.count) + destinationParts).joined(separator: "/")
    }

    public func save(candidate: Data, expected: PDFReaderSnapshot) async throws -> PDFReaderSnapshot {
        guard !closed else { throw PDFReaderError.unreadable }
        try Self.validate(candidate, saving: true)
        guard expected.revision.fingerprint == DocumentFingerprint(data: expected.data) else { throw PDFReaderError.changed }
        let transaction: PDFReaderRecovery?
        if candidate != expected.data {
            let summary = PDFReaderRecovery(
                id: UUID(), attachmentID: expected.record.id, createdAt: Date(), expectedFingerprint: expected.revision.fingerprint,
                candidateFingerprint: DocumentFingerprint(data: candidate))
            try retain(summary, expected: expected.data, candidate: candidate)
            transaction = summary
        } else {
            transaction = nil
        }
        let record = try await record(expected.record.id)
        guard record == expected.record else { throw PDFReaderError.changed }
        let current = try read(record)
        guard !closed else { throw PDFReaderError.unreadable }
        try Self.validate(current.data, saving: true)
        guard current.revision == expected.revision, current.data == expected.data else { throw PDFReaderError.changed }
        if candidate == current.data {
            return PDFReaderSnapshot(
                record: record, data: current.data, revision: current.revision, recoveryCandidates: try retainedRecoveries(attachmentID: record.id))
        }
        let fileURL = try url(record)
        do {
            guard !closed else { throw PDFReaderError.unreadable }
            try rootAccess.verifyRootIdentity()
            let revision = expected.revision
            let root = controlURL
            let hook = beforeCommitForTesting
            _ = try ExactFileReplacement.replace(
                at: fileURL, expected: current.data, candidate: candidate,
                preCommitHook: { location in
                    try hook?(location)
                    let final = try PDFReaderFileAccess.readExact(at: location, root: root)
                    guard final.revision == revision else { throw PDFReaderError.changed }
                },
                maximumByteCount: PDFReaderFileAccess.maximumBytes,
                expectedIdentity: ExactFileReplacementIdentity(
                    device: revision.device, inode: revision.inode,
                    parentDevice: revision.parentDevice, parentInode: revision.parentInode))
            let verified = try read(record)
            guard verified.data == candidate else { throw PDFReaderError.changed }
            try afterCommitForTesting?(fileURL)
            if let transaction { try removeRecovery(transaction) }
            return PDFReaderSnapshot(
                record: record, data: verified.data, revision: verified.revision, recoveryCandidates: try retainedRecoveries(attachmentID: record.id))
        } catch {
            // The baseline and candidate survive every uncertain commit and app exit.
            if let error = error as? ExactFileReplacementError {
                if case .revisionConflict = error { throw PDFReaderError.changed }
                throw PDFReaderError.saveUncertain("\(recovery.directoryURL.path); \(fileURL.deletingLastPathComponent().path): \(error.localizedDescription)")
            }
            if let error = error as? PDFReaderError { throw error }
            throw PDFReaderError.saveUncertain(recovery.directoryURL.path)
        }
    }

    public func recoveryData(_ summary: PDFReaderRecovery) throws -> Data {
        try recoveryLock.withSharedLock {
            let metadata = try recovery.read(directory: nil, fileName: "\(summary.id.uuidString).json")
            guard try JSONDecoder().decode(PDFReaderRecovery.self, from: metadata) == summary else { throw PDFReaderError.changed }
            let data = try recovery.read(directory: summary.id.uuidString, fileName: "candidate.pdf")
            guard DocumentFingerprint(data: data) == summary.candidateFingerprint else { throw PDFReaderError.changed }
            try Self.validate(data)
            return data
        }
    }

    public func recoveries(attachmentID: UUID) throws -> [PDFReaderRecovery] {
        try retainedRecoveries(attachmentID: attachmentID)
    }

    public static func export(candidate: Data, to destination: URL) throws {
        try validate(candidate)
        guard destination.isFileURL else { throw PDFReaderError.unsafePath }
        let started = destination.startAccessingSecurityScopedResource()
        defer { if started { destination.stopAccessingSecurityScopedResource() } }
        do {
            _ = try ExactFileReplacement.replace(
                at: destination.standardizedFileURL, expected: nil, candidate: candidate, maximumByteCount: PDFReaderFileAccess.maximumBytes)
        } catch let error as ExactFileReplacementError {
            if case .revisionConflict = error { throw PDFReaderError.destinationExists }
            throw PDFReaderError.io(error.localizedDescription)
        }
    }

    private func record(_ id: UUID) async throws -> PortableAttachmentRecord {
        guard let record = try await records().first(where: { $0.id == id }) else { throw PDFReaderError.missing }
        return record
    }

    private func url(_ record: PortableAttachmentRecord) throws -> URL {
        guard case .triptychRelative(let path) = record.location, record.vaultID == nil,
            path.components.count == 4, path.components[0] == "attachments", path.components[1] == "files",
            path.components[2] == Substring(record.id.uuidString.lowercased())
        else { throw PDFReaderError.unsafePath }
        return controlURL.appendingPathComponent(path.rawValue)
    }

    private func read(_ record: PortableAttachmentRecord) throws -> PDFReaderFileAccess.Read {
        guard !closed else { throw PDFReaderError.unreadable }
        try rootAccess.verifyRootIdentity()
        let read = try PDFReaderFileAccess.read(at: url(record), root: controlURL)
        guard !closed else { throw PDFReaderError.unreadable }
        try rootAccess.verifyRootIdentity()
        return read
    }

    private static func validate(_ data: Data, saving: Bool = false) throws {
        guard data.count <= PDFReaderFileAccess.maximumBytes else { throw PDFReaderError.tooLarge }
        guard let document = PDFDocument(data: data) else { throw PDFReaderError.malformed }
        guard !document.isLocked, !saving || document.allowsCommenting else { throw PDFReaderError.locked }
        guard document.pageCount > 0 else { throw PDFReaderError.malformed }
    }

    private func retain(_ transaction: PDFReaderRecovery, expected: Data, candidate: Data) throws {
        try recoveryLock.withExclusiveLock {
            let directory = transaction.id.uuidString
            try recovery.ensureDirectories([directory])
            _ = try recovery.createExclusive(expected, directory: directory, fileName: "baseline.pdf")
            _ = try recovery.createExclusive(candidate, directory: directory, fileName: "candidate.pdf")
            _ = try recovery.createExclusive(JSONEncoder().encode(transaction), directory: nil, fileName: "\(directory).json")
            try recovery.synchronize(directory: directory)
        }
    }

    private func retainedRecoveries(attachmentID: UUID) throws -> [PDFReaderRecovery] {
        try recoveryLock.withSharedLock {
            try recovery.fileNames(in: nil).filter { $0.hasSuffix(".json") }.map {
                try JSONDecoder().decode(PDFReaderRecovery.self, from: recovery.read(directory: nil, fileName: $0))
            }.filter { $0.attachmentID == attachmentID }.sorted { $0.createdAt < $1.createdAt }
        }
    }

    private func removeRecovery(_ transaction: PDFReaderRecovery) throws {
        try recoveryLock.withExclusiveLock {
            let name = "\(transaction.id.uuidString).json"
            let exact = try recovery.read(directory: nil, fileName: name)
            guard try JSONDecoder().decode(PDFReaderRecovery.self, from: exact) == transaction else { throw PDFReaderError.changed }
            let baseline = try recovery.read(directory: transaction.id.uuidString, fileName: "baseline.pdf")
            let candidate = try recovery.read(directory: transaction.id.uuidString, fileName: "candidate.pdf")
            guard DocumentFingerprint(data: baseline) == transaction.expectedFingerprint,
                DocumentFingerprint(data: candidate) == transaction.candidateFingerprint
            else { throw PDFReaderError.changed }
            try recovery.remove(directory: nil, fileName: name, expected: exact)
            try recovery.remove(directory: transaction.id.uuidString, fileName: "baseline.pdf", expected: baseline)
            try recovery.remove(directory: transaction.id.uuidString, fileName: "candidate.pdf", expected: candidate)
            try? recovery.removeEmptyDirectory(transaction.id.uuidString)
        }
    }

    public func close() async {
        closed = true
        onClosingForTesting?()
        if importInProgress {
            await withCheckedContinuation { closeWaiters.append($0) }
        }
    }

    private func acquireImport() async {
        if importInProgress {
            await withCheckedContinuation { importWaiters.append($0) }
        } else {
            importInProgress = true
        }
    }

    private func releaseImport() {
        if importWaiters.isEmpty {
            importInProgress = false
            let waiting = closeWaiters
            closeWaiters.removeAll()
            for continuation in waiting { continuation.resume() }
        } else {
            importWaiters.removeFirst().resume()
        }
    }

    func setBeforeCommitForTesting(_ hook: (@Sendable (URL) throws -> Void)?) { beforeCommitForTesting = hook }
    func setAfterCommitForTesting(_ hook: (@Sendable (URL) throws -> Void)?) { afterCommitForTesting = hook }
    func setOnClosingForTesting(_ hook: (@Sendable () -> Void)?) { onClosingForTesting = hook }
}
