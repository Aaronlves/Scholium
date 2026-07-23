import Foundation
import Testing
@testable import ScholiumContracts

@Suite("Role-aware research note titles")
struct ResearchNoteTitleResolverTests {
    @Test("Analysis resolves YAML title, then H1, then filename")
    func analysisFallbackOrder() {
        let property = note(
            "Folder/Filename.md",
            "---\ntitle: YAML Title\n---\n# Heading Title\n"
        )
        #expect(ResearchNoteTitleResolver.resolve(
            document: property,
            profile: .analysis
        ) == ResearchNoteTitleResolution(
            title: "YAML Title",
            source: .analysisProperty
        ))

        let heading = note("Folder/Filename.md", "# Heading Title\n")
        #expect(ResearchNoteTitleResolver.resolve(
            document: heading,
            profile: .analysis
        ) == ResearchNoteTitleResolution(
            title: "Heading Title",
            source: .firstLevelOneHeading
        ))

        let filename = note("Folder/Filename.md", "Body only.\n")
        #expect(ResearchNoteTitleResolver.resolve(
            document: filename,
            profile: .analysis
        ) == ResearchNoteTitleResolution(title: "Filename", source: .filename))
    }

    @Test("Topic and Work ignore YAML title and share H1 fallback")
    func authoredNotesUseDocumentTitles() {
        let source = note(
            "Folder/Filename.md",
            "---\ntitle: Ignored YAML\n---\n# Authored Heading\n"
        )
        for profile in [SchemaProfileID.topicMarkdown, .draftProject] {
            #expect(ResearchNoteTitleResolver.resolve(
                document: source,
                profile: profile
            ) == ResearchNoteTitleResolution(
                title: "Authored Heading",
                source: .firstLevelOneHeading
            ))
        }

        let noHeading = note(
            "Folder/Filename.md",
            "---\ntitle: Ignored YAML\n---\nBody only.\n"
        )
        #expect(ResearchNoteTitleResolver.resolve(
            document: noHeading,
            profile: .draftProject
        ) == ResearchNoteTitleResolution(title: "Filename", source: .filename))
    }

    private func note(_ path: String, _ source: String) -> NoteDocument {
        NoteDocument(relativePath: path, rawContent: source)
    }
}
