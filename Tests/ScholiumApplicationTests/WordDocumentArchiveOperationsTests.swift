import Foundation
import ScholiumApplication
import Testing

struct WordDocumentArchiveOperationsTests {
    @Test("Word package I/O preserves nested parts and bilingual bytes")
    func roundTrip() async throws {
        let applicationSupportURL = try makeStorage()
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        let parts = [
            "[Content_Types].xml": Data("types".utf8),
            "word/document.xml": Data("editable 中文 philosophy".utf8),
            "word/_rels/footnotes.xml.rels": Data("links".utf8),
        ]
        let packed = try await WordDocumentArchiveOperations.pack(parts, applicationSupportURL: applicationSupportURL)
        let unpacked = try await WordDocumentArchiveOperations.unpack(packed, applicationSupportURL: applicationSupportURL)
        #expect(unpacked == parts)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporaryRoot(in: applicationSupportURL).path) == [".derived-state.lock"])
    }

    @Test("Word package I/O rejects parts outside its temporary package")
    func rejectsParentPath() async throws {
        let applicationSupportURL = try makeStorage()
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        await #expect(throws: (any Error).self) {
            try await WordDocumentArchiveOperations.pack(["../outside.xml": Data()], applicationSupportURL: applicationSupportURL)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporaryRoot(in: applicationSupportURL).path) == [".derived-state.lock"])
    }

    @Test("Invalid Word archives also remove their managed temporary job")
    func invalidArchiveCleansUp() async throws {
        let applicationSupportURL = try makeStorage()
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }
        await #expect(throws: (any Error).self) {
            try await WordDocumentArchiveOperations.unpack(Data("not a generated archive".utf8), applicationSupportURL: applicationSupportURL)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporaryRoot(in: applicationSupportURL).path) == [".derived-state.lock"])
    }

    private func makeStorage() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/word-archive-tests/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func temporaryRoot(in support: URL) -> URL { support.appendingPathComponent("Temporary/WordExports-v1", isDirectory: true) }
}
