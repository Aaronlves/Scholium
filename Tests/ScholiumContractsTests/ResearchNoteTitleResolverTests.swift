import Foundation
import Testing
@testable import ScholiumContracts

@Suite("Filename-authoritative research note titles")
struct ResearchNoteTitleResolverTests {
    @Test("Every library uses the filename and ignores academic metadata, YAML, and headings")
    func everyLibraryUsesFilename() {
        let source = note(
            "Folder/Filename.md",
            "---\ntitle: Ignored YAML\n---\n# Authored Heading\n"
        )
        #expect(ResearchNoteTitleResolver.resolve(document: source) == "Filename")

        let noHeading = note(
            "Folder/Filename.md",
            "---\ntitle: Ignored YAML\n---\nBody only.\n"
        )
        #expect(ResearchNoteTitleResolver.resolve(document: noHeading) == "Filename")
    }

    private func note(_ path: String, _ source: String) -> NoteDocument {
        NoteDocument(relativePath: path, rawContent: source)
    }
}
