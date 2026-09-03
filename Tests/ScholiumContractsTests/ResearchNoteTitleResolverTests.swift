import Foundation
import Testing
@testable import ScholiumContracts

@Suite("Role-aware research note titles")
struct ResearchNoteTitleResolverTests {
    @Test("Analysis resolves managed title, then filename and ignores YAML and body headings")
    func analysisFallbackOrder() {
        let property = note(
            "Folder/Filename.md",
            "---\ntitle: YAML Title\n---\n# Heading Title\n"
        )
        let metadata = NoteMetadataSnapshot(
            record: NoteMetadataRecord(
                noteID: UUID(),
                fields: ["title": .string("Managed Title")]
            ),
            revision: DocumentFingerprint(content: "managed")
        )
        #expect(ResearchNoteTitleResolver.resolve(
            document: property,
            profile: .analysis,
            metadata: metadata
        ) == ResearchNoteTitleResolution(
            title: "Managed Title",
            source: .managedMetadata
        ))
        #expect(ResearchNoteTitleResolver.resolve(
            document: property,
            profile: .analysis
        ) == ResearchNoteTitleResolution(
            title: "Filename",
            source: .filename
        ))

        let heading = note("Folder/Filename.md", "# Heading Title\n")
        #expect(ResearchNoteTitleResolver.resolve(
            document: heading,
            profile: .analysis
        ) == ResearchNoteTitleResolution(
            title: "Filename",
            source: .filename
        ))

        let filename = note("Folder/Filename.md", "Body only.\n")
        #expect(ResearchNoteTitleResolver.resolve(
            document: filename,
            profile: .analysis
        ) == ResearchNoteTitleResolution(title: "Filename", source: .filename))
    }

    @Test("Topic and Work use filenames and ignore YAML and body headings")
    func authoredNotesUseFilenames() {
        let source = note(
            "Folder/Filename.md",
            "---\ntitle: Ignored YAML\n---\n# Authored Heading\n"
        )
        for profile in [SchemaProfileID.topicMarkdown, .draftProject] {
            #expect(ResearchNoteTitleResolver.resolve(
                document: source,
                profile: profile
            ) == ResearchNoteTitleResolution(
                title: "Filename",
                source: .filename
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
