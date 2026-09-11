import Foundation
import ScholiumContracts
import Testing

@Suite("Attachment contracts")
struct AttachmentContractsTests {
    @Test("Portable attachment locations keep external paths out of control records")
    func locationRoundTrip() throws {
        let locations: [AttachmentLocation] = [
            .vaultRelative(try AttachmentRelativePath("Attachments/id/Figure.png")),
            .external(try ExternalAttachmentReference(filename: "Figure.png")),
        ]
        for location in locations {
            let data = try JSONEncoder().encode(location)
            #expect(try JSONDecoder().decode(AttachmentLocation.self, from: data) == location)
        }
        let externalData = try JSONEncoder().encode(
            AttachmentLocation.external(try ExternalAttachmentReference(filename: "Figure.png"))
        )
        #expect(!String(decoding: externalData, as: UTF8.self).contains("/"))
        #expect(throws: ExternalAttachmentReferenceError.self) {
            try ExternalAttachmentReference(filename: "../Figure.png")
        }
        #expect(throws: ExternalAttachmentReferenceError.self) {
            try JSONDecoder().decode(
                ExternalAttachmentReference.self,
                from: Data(#"{"filename":"../Figure.png"}"#.utf8)
            )
        }
    }

    @Test("Legacy absolute-path attachment records are rejected")
    func legacyAbsolutePathLocationIsNotDecoded() throws {
        let data = Data(#"{"kind":"absolutePath","path":"/Users/researcher/Figure.png"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AttachmentLocation.self, from: data)
        }
    }

    @Test("Document attachment records bind a Finder file to one stable Note")
    func documentAttachmentRoundTrip() throws {
        let record = DocumentAttachmentRecord(
            id: UUID(),
            noteID: UUID(),
            vaultID: UUID(),
            location: .vaultRelative(
                try AttachmentRelativePath(
                    "Attachments/identity/Emotion and Reasons.pdf"
                ))
        )
        let data = try JSONEncoder().encode(record)

        #expect(
            try JSONDecoder().decode(
                DocumentAttachmentRecord.self,
                from: data
            ) == record)
        #expect(record.filename == "Emotion and Reasons.pdf")
    }

    @Test("Only absolute Markdown image destinations enter indexed availability checks")
    func indexedImagePaths() {
        let source = """
            ![Imported](../Attachments/id/Figure.png)
            ![Indexed](/Users/researcher/Figures/Figure%20one.png)
            [Ordinary link](/Users/researcher/Figures/Not-an-image.png)
            `![Code](/Users/researcher/Figures/Code.png)`
            """
        #expect(
            IndexedImageReferences.absolutePaths(in: source) == [
                "/Users/researcher/Figures/Figure one.png"
            ])
    }
}
