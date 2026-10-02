import Foundation
import ScholiumApplication
import Testing

struct WordDocumentArchiveOperationsTests {
    @Test("Word package I/O preserves nested parts and bilingual bytes")
    func roundTrip() async throws {
        let parts = [
            "[Content_Types].xml": Data("types".utf8),
            "word/document.xml": Data("editable 中文 philosophy".utf8),
            "word/_rels/footnotes.xml.rels": Data("links".utf8),
        ]
        let packed = try await WordDocumentArchiveOperations.pack(parts)
        let unpacked = try await WordDocumentArchiveOperations.unpack(packed)
        #expect(unpacked == parts)
    }

    @Test("Word package I/O rejects parts outside its temporary package")
    func rejectsParentPath() async {
        await #expect(throws: (any Error).self) {
            try await WordDocumentArchiveOperations.pack(["../outside.xml": Data()])
        }
    }
}
