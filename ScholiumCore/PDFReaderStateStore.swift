import Foundation
import ScholiumContracts

/// Reading positions and window geometry are machine-local conveniences;
/// neither can bind a Note or authorize a PDF write.
public actor PDFReaderStateStore {
    private let directory: SecureRecordDirectory
    private var acceptedAttempts: [String: UInt64] = [:]
    private var closed = false

    public init(applicationSupportURL: URL, triptychID: UUID) throws {
        directory = SecureRecordDirectory(
            trustedRootURL: applicationSupportURL,
            components: ["Triptychs", triptychID.uuidString, "PDFReader", "State"],
            directoryMode: 0o700, fileMode: 0o600, maximumByteCount: 65_536)
        try directory.ensureDirectories([])
    }

    public func readingState(noteID: UUID, attachmentID: UUID) throws -> PDFReaderReadingState? {
        try requireOpen()
        guard let data = try directory.readIfPresent(directory: nil, fileName: readingName(noteID, attachmentID)) else { return nil }
        let state = try JSONDecoder().decode(PDFReaderReadingState.self, from: data)
        guard state.isValid else { throw PDFReaderError.invalidState }
        return state
    }

    public func saveReadingState(_ state: PDFReaderReadingState, noteID: UUID, attachmentID: UUID, windowID: UUID, attempt: UInt64) throws {
        try requireOpen()
        guard state.isValid else { throw PDFReaderError.invalidState }
        let name = readingName(noteID, attachmentID)
        try save(state, name: name, writer: "\(name):\(windowID.uuidString)", attempt: attempt)
    }

    public func windowState(windowID: UUID) throws -> PDFReaderWindowState? {
        try requireOpen()
        guard let data = try directory.readIfPresent(directory: nil, fileName: windowName(windowID)) else { return nil }
        let state = try JSONDecoder().decode(PDFReaderWindowState.self, from: data)
        guard state.isValid else { throw PDFReaderError.invalidState }
        return state
    }

    public func saveWindowState(_ state: PDFReaderWindowState, windowID: UUID, attempt: UInt64) throws {
        try requireOpen()
        guard state.isValid else { throw PDFReaderError.invalidState }
        let name = windowName(windowID)
        try save(state, name: name, writer: name, attempt: attempt)
    }

    private func save<T: Encodable>(_ state: T, name: String, writer: String, attempt: UInt64) throws {
        guard attempt > (acceptedAttempts[writer] ?? 0) else { return }
        _ = try directory.replace(JSONEncoder().encode(state), directory: nil, fileName: name)
        acceptedAttempts[writer] = attempt
    }

    public func close() { closed = true }

    private func requireOpen() throws {
        if closed { throw PDFReaderError.unreadable }
    }

    private func readingName(_ note: UUID, _ pdf: UUID) -> String { "note-\(note.uuidString)-pdf-\(pdf.uuidString).json" }
    private func windowName(_ window: UUID) -> String { "window-\(window.uuidString).json" }
}
