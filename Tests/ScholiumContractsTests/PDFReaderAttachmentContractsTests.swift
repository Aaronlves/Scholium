import Foundation
import ScholiumContracts
import Testing

@Suite("Shared PDF attachment ownership")
struct PDFReaderAttachmentContractsTests {
    @Test("Shared records retain portable identity without absolute paths or a vault owner")
    func portableSharedRecord() throws {
        let id = UUID()
        let record = PortableAttachmentRecord(
            id: id, vaultID: nil,
            location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(id.uuidString.lowercased())/Paper #1 中文.pdf")),
            importedSourceFingerprint: DocumentFingerprint(data: Data("original bytes".utf8)))
        let encoded = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(PortableAttachmentRecord.self, from: encoded) == record)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("bookmark") && !text.contains("absolutePath"))
    }

    @Test("Catalog decoding refuses a mismatched UUID directory, wrong owner, or absent original fingerprint")
    func invalidSharedOwnership() throws {
        let id = UUID()
        let fingerprint = DocumentFingerprint(data: Data("original bytes".utf8))
        let validPath = try AttachmentRelativePath("attachments/files/\(id.uuidString.lowercased())/Paper.pdf")
        let invalid = [
            PortableAttachmentRecord(
                id: id, vaultID: nil, location: .triptychRelative(try AttachmentRelativePath("attachments/files/\(UUID().uuidString.lowercased())/Paper.pdf")),
                importedSourceFingerprint: fingerprint),
            PortableAttachmentRecord(id: id, vaultID: UUID(), location: .triptychRelative(validPath), importedSourceFingerprint: fingerprint),
            PortableAttachmentRecord(id: id, vaultID: nil, location: .triptychRelative(validPath)),
            PortableAttachmentRecord(id: id, vaultID: nil, location: .vaultRelative(try AttachmentRelativePath("Attachments/Paper.pdf"))),
        ]
        for record in invalid {
            let encoded = try JSONEncoder().encode(record)
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(PortableAttachmentRecord.self, from: encoded) }
        }
    }
}
