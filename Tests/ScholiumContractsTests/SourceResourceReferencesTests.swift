import Foundation
import Testing

@testable import ScholiumContracts

@Suite("Source-owned properties and resource links")
struct SourceResourceReferencesTests {
    @Test("Creation preserves complete arbitrary YAML bytes for every role")
    func exactCreation() throws {
        let source =
            "\u{feff}---\r\n# Preserve comment\r\n\"研究 问题\": '行动理由'\r\ncustom:\r\n  nested: [1, true]\r\nsummary: |\r\n  First line\r\n  Second line\r\n---\r\nBody"
        for role in [VaultRole.sourceCorpus, .topicKnowledge, .draftProject] {
            let request = try ManagedNoteCreationRequest(
                vaultID: UUID(), destination: .exact(relativePath: "Test.md"), source: source)
            #expect(try ManagedNoteSourceBuilder.source(for: request, vaultRole: role) == source)
        }
    }

    @Test("Only authored link occurrences create Zotero relations")
    func zoteroOccurrences() throws {
        let body = """
            [First](zotero://select/library/items/ITEM0001)
            [PDF](zotero://open-pdf/groups/42/items/PDF00001?page=2&annotation=ANN00001)
            [Again](zotero://select/library/items/ITEM0001)
            `[Hidden](zotero://select/library/items/HIDDEN01)`
            <!-- [Hidden](zotero://select/library/items/HIDDEN02) -->
            [Invalid](zotero://open-pdf/library/items/PDF00001?page=0)
            """
        let links = SourceResourceReferences.externalLinks(in: body)
        #expect(links.map(\.label) == ["First", "PDF", "Again", "Invalid"])
        #expect(Set(links.map(\.id)).count == 4)
        #expect(!links[3].canOpen)
        #expect((try ZoteroReference(url: links[1].url)).library == .group(42))
        #expect((try ZoteroReference(url: links[1].url)).page == 2)
        #expect((try ZoteroReference(url: links[1].url)).annotationKey == "ANN00001")
        #expect(SourceResourceReferences.externalLinks(in: "No links").isEmpty)
    }

    @Test("External links include web and mail links but exclude internal files and keep unsafe destinations non-opening")
    func externalDestinations() {
        let source = """
            [Web](https://example.org/paper?q=1#section)
            <https://example.org/auto>
            [Mail](mailto:reader@example.org)
            [File](Attachments/paper.pdf)
            [Note](Topic.md)
            [Unsafe](javascript:alert)
            `[Code](https://example.org/hidden)`
            """
        let links = SourceResourceReferences.externalLinks(in: source)
        #expect(
            links.map(\.url.absoluteString) == [
                "https://example.org/paper?q=1#section", "https://example.org/auto",
                "mailto:reader@example.org", "javascript:alert",
            ])
        #expect(links.map(\.line) == [1, 2, 3, 6])
        #expect(!links[3].canOpen)
    }

    @Test("External means outside all registered vaults, independent of service")
    func externalVaultBoundary() {
        let source = """
            [Local](Attachments/paper.pdf)
            [Other vault](../../works/draft.md)
            [Outside](../../../outside/file.pdf)
            [Absolute inside](file:///research/topics/Attachments/paper.pdf)
            [Absolute outside](file:///elsewhere/file.pdf)
            [App](obsidian://open?vault=Example&file=Note)
            [FTP](ftp://example.org/paper.pdf)
            [Internal](scholium-note://note)
            [Section](#heading)
            ![Remote image](https://example.org/image.png)
            """
        let links = SourceResourceReferences.externalLinks(
            in: source,
            noteURL: URL(fileURLWithPath: "/research/topics/folder/Note.md"),
            vaultRoots: [URL(fileURLWithPath: "/research/topics"), URL(fileURLWithPath: "/research/works")])
        #expect(links.map(\.label) == ["Outside", "Absolute outside", "App", "FTP", "Remote image"])
        #expect(links[0].url.path == "/outside/file.pdf")
    }

    @Test("Local files use exact contained paths and exclude links to Notes or remote URLs")
    func containedFiles() throws {
        let source = """
            [PDF](../Attachments/A%20File.pdf)
            ![Diagram](../Attachments/diagram.png)
            [Note](../Topic.md)
            [Web](https://example.com/file.pdf)
            [Escape](../../outside.pdf)
            [Protocol](//host/file.pdf)
            `[Hidden](../Attachments/hidden.pdf)`
            """
        let files = SourceResourceReferences.files(in: source, noteRelativePath: "Folder/Note.md")
        #expect(files.count == 2)
        #expect(files[0].relativePath?.rawValue == "Attachments/A File.pdf")
        #expect(files[1].isImage)
        let vault = UUID()
        #expect(
            SourceResourceReferences.derivedID(vaultID: vault, path: "Attachments/A File.pdf")
                == SourceResourceReferences.derivedID(vaultID: vault, path: "Attachments/A File.pdf"))
        #expect(
            SourceResourceReferences.derivedID(vaultID: vault, path: "a.pdf")
                != SourceResourceReferences.derivedID(vaultID: UUID(), path: "a.pdf"))
    }
}
