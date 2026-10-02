import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("PDF reading state lifecycle")
struct PDFReaderStateStoreTests {
    @Test("Late writes cannot regress one window, independent writers remain valid, and state survives recreation")
    func orderingAndRelaunch() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let root = repository.appendingPathComponent(".build/pdf-state-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let triptych = UUID()
        let store = try PDFReaderStateStore(applicationSupportURL: root, triptychID: triptych)
        let note = UUID()
        let pdf = UUID()
        let firstWindow = UUID()
        let secondWindow = UUID()
        let latest = PDFReaderReadingState(pageIndex: 9, pointX: 17, pointY: 120, scaleFactor: 1.7, autoScales: false)
        try await store.saveReadingState(latest, noteID: note, attachmentID: pdf, windowID: firstWindow, attempt: 12)
        try await store.saveReadingState(PDFReaderReadingState(pageIndex: 1), noteID: note, attachmentID: pdf, windowID: firstWindow, attempt: 11)
        #expect(try await store.readingState(noteID: note, attachmentID: pdf) == latest)
        let other = PDFReaderReadingState(pageIndex: 4)
        try await store.saveReadingState(other, noteID: note, attachmentID: pdf, windowID: secondWindow, attempt: 1)
        #expect(try await store.readingState(noteID: note, attachmentID: pdf) == other)
        let windowState = PDFReaderWindowState(isVisible: true, paneWidth: 550)
        try await store.saveWindowState(windowState, windowID: firstWindow, attempt: 7)
        try await store.saveWindowState(PDFReaderWindowState(isVisible: false), windowID: firstWindow, attempt: 6)
        let recreated = try PDFReaderStateStore(applicationSupportURL: root, triptychID: triptych)
        #expect(try await recreated.readingState(noteID: note, attachmentID: pdf) == other)
        #expect(try await recreated.windowState(windowID: firstWindow) == windowState)
        #expect(try await recreated.readingState(noteID: UUID(), attachmentID: pdf) == nil)
        await #expect(throws: PDFReaderError.invalidState) {
            try await recreated.saveReadingState(PDFReaderReadingState(pageIndex: -1), noteID: note, attachmentID: pdf, windowID: firstWindow, attempt: 1)
        }
        await #expect(throws: PDFReaderError.invalidState) {
            try await recreated.saveWindowState(PDFReaderWindowState(paneWidth: .infinity), windowID: firstWindow, attempt: 1)
        }
        await recreated.close()
        await #expect(throws: PDFReaderError.unreadable) {
            try await recreated.saveWindowState(PDFReaderWindowState(), windowID: firstWindow, attempt: 2)
        }
    }
}
