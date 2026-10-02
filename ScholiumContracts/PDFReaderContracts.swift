import Foundation

public struct PDFReaderRevision: Hashable, Sendable {
    public let fingerprint: DocumentFingerprint
    public let device: UInt64
    public let inode: UInt64
    public let parentDevice: UInt64
    public let parentInode: UInt64

    public init(fingerprint: DocumentFingerprint, device: UInt64, inode: UInt64, parentDevice: UInt64, parentInode: UInt64) {
        self.fingerprint = fingerprint
        self.device = device
        self.inode = inode
        self.parentDevice = parentDevice
        self.parentInode = parentInode
    }
}

/// Immutable PDF bytes, separate from PDFKit's window-owned mutable document.
public struct PDFReaderSnapshot: Sendable {
    public let record: PortableAttachmentRecord
    public let data: Data
    public let revision: PDFReaderRevision
    public let recoveryCandidates: [PDFReaderRecovery]

    public init(record: PortableAttachmentRecord, data: Data, revision: PDFReaderRevision, recoveryCandidates: [PDFReaderRecovery] = []) {
        self.record = record
        self.data = data
        self.revision = revision
        self.recoveryCandidates = recoveryCandidates
    }
}

public struct PDFReaderRecovery: Codable, Hashable, Sendable {
    public let id: UUID
    public let attachmentID: UUID
    public let createdAt: Date
    public let expectedFingerprint: DocumentFingerprint
    public let candidateFingerprint: DocumentFingerprint

    public init(id: UUID, attachmentID: UUID, createdAt: Date, expectedFingerprint: DocumentFingerprint, candidateFingerprint: DocumentFingerprint) {
        self.id = id
        self.attachmentID = attachmentID
        self.createdAt = createdAt
        self.expectedFingerprint = expectedFingerprint
        self.candidateFingerprint = candidateFingerprint
    }
}

/// Preparation does not create a Note relationship; the editor writes the
/// returned ordinary filesystem path into authored YAML using its source transaction.
public struct PDFReaderImport: Sendable {
    public let snapshot: PDFReaderSnapshot
    public let noteRelativePath: String
    public let wasNew: Bool

    public init(snapshot: PDFReaderSnapshot, noteRelativePath: String, wasNew: Bool) {
        self.snapshot = snapshot
        self.noteRelativePath = noteRelativePath
        self.wasNew = wasNew
    }
}

public struct PDFReaderReadingState: Codable, Hashable, Sendable {
    public var pageIndex: Int
    public var pointX: Double
    public var pointY: Double
    public var scaleFactor: Double
    public var autoScales: Bool

    public init(pageIndex: Int = 0, pointX: Double = 0, pointY: Double = 0, scaleFactor: Double = 1, autoScales: Bool = true) {
        self.pageIndex = pageIndex
        self.pointX = pointX
        self.pointY = pointY
        self.scaleFactor = scaleFactor
        self.autoScales = autoScales
    }

    public var isValid: Bool {
        pageIndex >= 0 && pointX.isFinite && pointY.isFinite
            && scaleFactor.isFinite && scaleFactor > 0 && scaleFactor <= 100
    }
}

public struct PDFReaderWindowState: Codable, Hashable, Sendable {
    public var isVisible: Bool
    public var paneWidth: Double

    public init(isVisible: Bool = false, paneWidth: Double = 440) {
        self.isVisible = isVisible
        self.paneWidth = paneWidth
    }

    public var isValid: Bool { paneWidth.isFinite && paneWidth >= 200 && paneWidth <= 10_000 }
}

public enum PDFReaderError: Error, Equatable, LocalizedError, Sendable {
    case invalidBinding
    case missing
    case unreadable
    case malformed
    case locked
    case tooLarge
    case changed
    case sourceChanged
    case destinationExists
    case unsafePath
    case invalidState
    case saveUncertain(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBinding: "The Note's pdf property does not identify a registered shared PDF."
        case .missing: "The shared PDF is missing. Choose an existing PDF or attach a new copy."
        case .unreadable: "Scholium cannot read this PDF. Check its permissions and availability."
        case .malformed: "The file is not a readable PDF."
        case .locked: "This PDF is encrypted or does not permit annotation. Use an unlocked copy."
        case .tooLarge: "This PDF exceeds the 512 MB reader limit."
        case .changed: "The PDF changed outside this reader. Your annotations remain available; reload or export them before continuing."
        case .sourceChanged: "The source PDF changed since it was imported. Import it as a new version to preserve the existing annotations."
        case .destinationExists: "A file already exists at the export destination. Choose a new filename."
        case .unsafePath: "The PDF path is linked, outside its registered folder, or no longer identifies the original file."
        case .invalidState: "The PDF reading position could not be saved."
        case .saveUncertain(let location):
            "The PDF save could not be verified. Recovery copies are retained at \(location). Keep the reader open or export your annotations."
        case .io(let message): "The PDF could not be accessed: \(message)"
        }
    }
}

public protocol PDFReaderUseCases: Sendable {
    func boundPDF(for target: SourceAttachmentTarget, authoredPath: String?) async throws -> PDFReaderSnapshot?
    func boundPDFRecoveries(for target: SourceAttachmentTarget, authoredPath: String?) async throws -> [PDFReaderRecovery]
    func availablePDFs() async throws -> [PortableAttachmentRecord]
    /// Exact originals reuse their registered annotated copy by default.
    /// An explicit new version creates a separate copy even when one already exists.
    func importPDF(at sourceURL: URL, for target: SourceAttachmentTarget, zoteroSource: ZoteroPDFSource?, allowNewVersion: Bool) async throws -> PDFReaderImport
    /// An explicitly confirmed local file; observed Zotero fields are rechecked
    /// during copying and never persisted as source provenance.
    func importLocalCopy(_ candidate: ZoteroPDFLocalCopyCandidate, for target: SourceAttachmentTarget, allowNewVersion: Bool) async throws -> PDFReaderImport
    func attachPDF(attachmentID: UUID, for target: SourceAttachmentTarget) async throws -> PDFReaderImport
    func loadPDF(attachmentID: UUID) async throws -> PDFReaderSnapshot
    func savePDF(candidate: Data, expected: PDFReaderSnapshot) async throws -> PDFReaderSnapshot
    func exportPDF(candidate: Data, to destination: URL) async throws
    func recoveryData(_ recovery: PDFReaderRecovery) async throws -> Data
    func recoveries(attachmentID: UUID) async throws -> [PDFReaderRecovery]
    func readingState(noteID: UUID, attachmentID: UUID) async throws -> PDFReaderReadingState?
    func saveReadingState(_ state: PDFReaderReadingState, noteID: UUID, attachmentID: UUID, windowID: UUID, attempt: UInt64) async throws
    func windowState(windowID: UUID) async throws -> PDFReaderWindowState?
    func saveWindowState(_ state: PDFReaderWindowState, windowID: UUID, attempt: UInt64) async throws
}
