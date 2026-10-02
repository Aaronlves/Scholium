import Foundation
import ScholiumContracts
import ScholiumCore

/// Shared by a Triptych's windows; PDFKit documents remain window-local.
public actor PDFReaderOperations: PDFReaderUseCases {
    private let store: SharedPDFStore
    private let state: PDFReaderStateStore
    private let control: TriptychControlStore
    private let repositories: [UUID: VaultRepository]
    private let zotero: ZoteroOperations
    private var closed = false

    init(
        controlURL: URL, controlStore: TriptychControlStore, repositories: [UUID: VaultRepository], applicationSupportURL: URL, triptychID: UUID,
        zotero: ZoteroOperations
    ) throws {
        store = try SharedPDFStore(controlURL: controlURL, controlStore: controlStore, applicationSupportURL: applicationSupportURL, triptychID: triptychID)
        state = try PDFReaderStateStore(applicationSupportURL: applicationSupportURL, triptychID: triptychID)
        control = controlStore
        self.repositories = repositories
        self.zotero = zotero
    }

    public func boundPDF(for target: SourceAttachmentTarget, authoredPath: String?) async throws -> PDFReaderSnapshot? {
        try requireOpen()
        guard let authoredPath else { return nil }
        guard !authoredPath.isEmpty else { throw PDFReaderError.invalidBinding }
        let noteURL = try await verifiedNoteURL(target)
        return try await store.resolve(noteURL: noteURL, authoredPath: authoredPath)
    }

    public func availablePDFs() async throws -> [PortableAttachmentRecord] {
        try requireOpen()
        return try await store.records()
    }

    public func boundPDFRecoveries(for target: SourceAttachmentTarget, authoredPath: String?) async throws -> [PDFReaderRecovery] {
        try requireOpen()
        guard let authoredPath else { return [] }
        let record = try await boundAttachmentRecord(for: target, authoredPath: authoredPath)
        return try await store.recoveries(attachmentID: record.id)
    }

    public func importPDF(at sourceURL: URL, for target: SourceAttachmentTarget, zoteroSource: ZoteroPDFSource?, allowNewVersion: Bool) async throws
        -> PDFReaderImport
    {
        let noteURL = try await verifiedNoteURL(target)
        let validateSource: (@Sendable () async throws -> Void)?
        if let zoteroSource {
            let candidate = ZoteroPDFImportCandidate(source: zoteroSource, originalURL: sourceURL)
            validateSource = { [zotero] in try await zotero.revalidatePDFImport(candidate) }
        } else {
            validateSource = nil
        }
        let imported = try await store.importPDF(at: sourceURL, zoteroSource: zoteroSource, allowNewVersion: allowNewVersion, revalidateSource: validateSource)
        try requireOpen()
        return PDFReaderImport(
            snapshot: imported.snapshot,
            noteRelativePath: try await store.authoredPath(attachmentID: imported.snapshot.record.id, noteURL: noteURL), wasNew: imported.wasNew)
    }

    public func attachPDF(attachmentID: UUID, for target: SourceAttachmentTarget) async throws -> PDFReaderImport {
        let noteURL = try await verifiedNoteURL(target)
        return PDFReaderImport(
            snapshot: try await store.load(attachmentID: attachmentID),
            noteRelativePath: try await store.authoredPath(attachmentID: attachmentID, noteURL: noteURL), wasNew: false)
    }

    public func importLocalCopy(_ candidate: ZoteroPDFLocalCopyCandidate, for target: SourceAttachmentTarget, allowNewVersion: Bool) async throws
        -> PDFReaderImport
    {
        let noteURL = try await verifiedNoteURL(target)
        let imported = try await store.importPDF(
            at: candidate.originalURL, zoteroSource: nil, allowNewVersion: allowNewVersion,
            revalidateSource: { [zotero] in try await zotero.revalidatePDFLocalCopy(candidate) })
        try requireOpen()
        return PDFReaderImport(
            snapshot: imported.snapshot,
            noteRelativePath: try await store.authoredPath(attachmentID: imported.snapshot.record.id, noteURL: noteURL), wasNew: imported.wasNew)
    }

    public func loadPDF(attachmentID: UUID) async throws -> PDFReaderSnapshot {
        try requireOpen()
        return try await store.load(attachmentID: attachmentID)
    }

    public func savePDF(candidate: Data, expected: PDFReaderSnapshot) async throws -> PDFReaderSnapshot {
        try requireOpen()
        return try await store.save(candidate: candidate, expected: expected)
    }

    public func exportPDF(candidate: Data, to destination: URL) throws {
        try requireOpen()
        try SharedPDFStore.export(candidate: candidate, to: destination)
    }

    public func recoveryData(_ recovery: PDFReaderRecovery) async throws -> Data {
        try requireOpen()
        return try await store.recoveryData(recovery)
    }

    public func recoveries(attachmentID: UUID) async throws -> [PDFReaderRecovery] {
        try requireOpen()
        return try await store.recoveries(attachmentID: attachmentID)
    }

    public func readingState(noteID: UUID, attachmentID: UUID) async throws -> PDFReaderReadingState? {
        try requireOpen()
        return try await state.readingState(noteID: noteID, attachmentID: attachmentID)
    }

    public func saveReadingState(_ state: PDFReaderReadingState, noteID: UUID, attachmentID: UUID, windowID: UUID, attempt: UInt64) async throws {
        try requireOpen()
        try await self.state.saveReadingState(state, noteID: noteID, attachmentID: attachmentID, windowID: windowID, attempt: attempt)
    }

    public func windowState(windowID: UUID) async throws -> PDFReaderWindowState? {
        try requireOpen()
        return try await state.windowState(windowID: windowID)
    }

    public func saveWindowState(_ state: PDFReaderWindowState, windowID: UUID, attempt: UInt64) async throws {
        try requireOpen()
        try await self.state.saveWindowState(state, windowID: windowID, attempt: attempt)
    }

    func shutdown() async {
        closed = true
        await store.close()
        await state.close()
    }

    func rebaseBinding(_ path: String, from source: VaultQualifiedNoteID, to destination: VaultQualifiedNoteID) async throws -> String {
        try requireOpen()
        guard let sourceRepository = repositories[source.vaultID], let destinationRepository = repositories[destination.vaultID] else {
            throw PDFReaderError.invalidBinding
        }
        return try await store.rebaseBinding(
            authoredPath: path, from: sourceRepository.vaultURL.appendingPathComponent(source.relativePath),
            to: destinationRepository.vaultURL.appendingPathComponent(destination.relativePath))
    }

    func boundAttachmentRecord(for target: SourceAttachmentTarget, authoredPath: String) async throws -> PortableAttachmentRecord {
        let noteURL = try await verifiedNoteURL(target)
        return try await store.bindingRecord(noteURL: noteURL, authoredPath: authoredPath)
    }

    private func verifiedNoteURL(_ target: SourceAttachmentTarget) async throws -> URL {
        try requireOpen()
        guard let repository = repositories[target.vaultID] else { throw PDFReaderError.invalidBinding }
        let document = try await repository.load(relativePath: target.relativePath)
        guard
            let identity = try await control.identity(
                forVaultID: target.vaultID, relativePath: target.relativePath,
                fingerprint: document.fingerprint, createIfMissing: false), identity.id == target.noteID
        else { throw DocumentAttachmentError.noteIdentityChanged(target.relativePath) }
        try requireOpen()
        return await repository.vaultURL.appendingPathComponent(target.relativePath)
    }

    private func requireOpen() throws {
        if closed { throw PDFReaderError.unreadable }
    }
}
