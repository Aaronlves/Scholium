import Foundation
import ScholiumContracts
import Testing

@Suite("Attachment contracts")
struct AttachmentContractsTests {
    @Test("Attachment locations preserve relative imports and absolute indexes distinctly")
    func locationRoundTrip() throws {
        let locations: [AttachmentLocation] = [
            .vaultRelative(try AttachmentRelativePath("Attachments/id/Figure.png")),
            try AttachmentLocation(absolutePath: "/Users/researcher/Figures/Figure.png"),
        ]
        for location in locations {
            let data = try JSONEncoder().encode(location)
            #expect(try JSONDecoder().decode(AttachmentLocation.self, from: data) == location)
        }
        #expect(throws: ImageAttachmentError.self) {
            try AttachmentLocation(absolutePath: "../Figure.png")
        }
    }

    @Test("Only absolute Markdown image destinations enter indexed availability checks")
    func indexedImagePaths() {
        let source = """
        ![Imported](../Attachments/id/Figure.png)
        ![Indexed](/Users/researcher/Figures/Figure%20one.png)
        [Ordinary link](/Users/researcher/Figures/Not-an-image.png)
        `![Code](/Users/researcher/Figures/Code.png)`
        """
        #expect(IndexedImageReferences.absolutePaths(in: source) == [
            "/Users/researcher/Figures/Figure one.png",
        ])
    }
}
