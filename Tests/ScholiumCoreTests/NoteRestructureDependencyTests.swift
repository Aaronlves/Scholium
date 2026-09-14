import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumCore

@Suite("Note reorganization source dependencies")
struct NoteRestructureDependencyTests {
    @Test("Footnote dependencies transfer recursively, rename destination collisions, and preserve shared source definitions")
    func footnoteClosure() throws {
        let passage = "中文[^a]. ^claim"
        let source = "\u{FEFF}---\r\ncustom: 'same' # keep\r\n---\r\n" + passage + "\r\n\r\nKeep[^b].\r\n\r\n[^a]: First[^b].\r\n[^b]: Shared.\r\n"
        let result = try plan(source, target: "Existing[^a].\r\n\r\n[^a]: Other.\r\n", passage: passage)
        let destination = try #require(result.target)
        #expect(destination.contains("中文[^a-2]. ^claim"))
        #expect(destination.contains("[^a-2]: First[^b]."))
        #expect(destination.contains("[^b]: Shared."))
        #expect(result.source?.hasPrefix("\u{FEFF}---\r\ncustom: 'same' # keep\r\n---\r\n[[Target#^claim]]\r\n\r\nKeep[^b].") == true)
        #expect(result.source?.contains("[^a]: First") == false)
        #expect(result.source?.contains("[^b]: Shared.") == true)
    }

    @Test("Copy keeps the source byte-identical and prevents filling an existing undefined target footnote")
    func copiedFootnote() throws {
        let passage = "Claim[^1]. ^claim"
        let source = passage + "\n\n[^1]: Authority.\n"
        let result = try plan(source, target: "Unresolved[^1].\n", passage: passage, operation: .copy)
        #expect(result.source == source)
        #expect(result.target?.contains("Claim[^1-2].") == true)
        #expect(result.target?.contains("[^1-2]: Authority.") == true)
    }

    @Test("Full lists and quotations retain exact syntax; partial containers are rejected")
    func completeBlocks() throws {
        for passage in ["- First\n- Second", "> A quotation.\n> Continued.", "# A heading"] {
            let result = try plan(passage + "\n\nRemain.\n", target: "", passage: passage)
            #expect(result.target == passage)
            #expect(result.source == "[[Target]]\n\nRemain.\n")
        }
        #expect(throws: NoteRestructureError.self) {
            try plan("- First\n- Second\n", target: "", passage: "First")
        }
    }

    @Test("A moved heading keeps incoming authored references live")
    func headingReference() throws {
        let result = try plan("# Heading\n\nRemain.\n", target: "", passage: "# Heading", incoming: "[[Source#Heading]] [label][r]\n\n[r]: Source.md#Heading\n")
        #expect(result.incoming?.contains("[[Target#Heading]]") == true)
        #expect(result.incoming == "[[Target#Heading]] [label](Target.md#Heading)\n\n[r]: Source.md#Heading\n")
    }

    @Test("Relative images and document attachments retain their vault target across folders and title syntax")
    func resourceRelocation() throws {
        let passage = "![图片](../Assets/a%20b.png \"Image\") and [PDF](<../Assets/paper.pdf> 'Paper'). ^claim"
        let result = try plan(passage + "\n", target: "", passage: passage, sourcePath: "Topics/Source.md", targetPath: "Works/Drafts/Target.md")
        #expect(result.target == "![图片](../../Assets/a%20b.png \"Image\") and [PDF](../../Assets/paper.pdf \"Paper\"). ^claim")
    }

    @Test("Reference links retain labels and targets without introducing definitions into the destination")
    func referenceDefinitions() throws {
        let source = "Use [*author*][book] and [site].\n\n[book]: https://example.com/book \"Book\"\n[site]: https://example.com\n"
        let result = try plan(source, target: "Existing [book].\n", passage: source, operation: .merge)
        #expect(result.target?.contains("Use [*author*](https://example.com/book \"Book\") and [site](https://example.com).") == true)
        #expect(result.target?.contains("[book]:") == false)
        #expect(result.target?.hasPrefix("Existing [book].\n") == true)
    }

    @Test("Literal code resembling dependencies remains exact")
    func literalCode() throws {
        let source = "```markdown\n[^missing] [site]\n[site]: invalid prose text\n![x](../Assets/a.png)\n```"
        let result = try plan(source, target: "", passage: source, sourcePath: "Topics/Source.md", targetPath: "Works/Target.md", operation: .copy)
        #expect(result.target == source)
    }

    @Test("Duplicate and cyclic footnotes have deterministic bounded outcomes")
    func duplicateAndCycle() throws {
        #expect(throws: NoteRestructureError.self) {
            try plan("Claim[^1].\n\n[^1]: One.\n[^1]: Two.\n", target: "", passage: "Claim[^1].")
        }
        let result = try plan("Claim[^a]. ^claim\n\n[^a]: First[^b].\n[^b]: Second[^a].\n", target: "", passage: "Claim[^a]. ^claim")
        #expect(result.target?.components(separatedBy: "[^a]:").count == 2)
        #expect(result.target?.components(separatedBy: "[^b]:").count == 2)
    }

    @Test(
        "Resource relocation preserves encoded filename bytes separately from a real fragment",
        arguments: [
            ("a%23b.png", "Assets/a#b.png", "Assets/a"),
            ("a%2520b.png", "Assets/a%20b.png", "Assets/a b.png"),
            ("a%3Fb.png", "Assets/a?b.png", "Assets/a"),
            ("a%25b.png", "Assets/a%b.png", "Assets/ab.png"),
        ])
    func encodedResourceTargets(_ filename: String, _ expected: String, _ wrong: String) throws {
        let passage = "![image](../Assets/" + filename + "#view). ^claim"
        let result = try plan(passage, target: "", passage: passage, sourcePath: "Topics/Source.md", targetPath: "Works/Drafts/Target.md")
        let after = try #require(result.target)
        #expect(after == "![image](../../Assets/" + filename + "#view). ^claim")
        let link = try #require(NoteRestructureMarkdownLinks(NoteDocument(relativePath: "Works/Drafts/Target.md", rawContent: after)).occurrences.first)
        let parts = link.destination.split(separator: "#", maxSplits: 1)
        #expect(parts.count == 2)
        #expect(parts.last == "view")
        let target = try #require(
            SourceResourceReferences.file(destination: String(parts[0]), noteRelativePath: "Works/Drafts/Target.md", isImage: true)?.relativePath)
        #expect(target.rawValue == expected)
        #expect(target.rawValue != wrong)
    }

    @Test(
        "Merge keeps comment and mathematics literals byte-exact",
        arguments: [
            "%%\n[unused]: https://example.com\n[inline](../Assets/a.png) [[Missing]]\n%%",
            "<!-- [inline](../Assets/a.png) [[Missing]] -->",
            "$$\n[unused]: https://example.com\n[inline](../Assets/a.png) [[Missing]]\n$$",
        ])
    func protectedDependencySource(_ literal: String) throws {
        let source = "\u{FEFF}" + literal + "\n\n正文。\n"
        let result = try plan(source, target: "Target.\n", passage: literal, sourcePath: "Topics/Source.md", targetPath: "Works/Target.md", operation: .merge)
        #expect(result.target == "Target.\n\n" + literal + "\n\n正文。\n")
        #expect(result.source == nil)
    }

    @Test(
        "Append refuses destination constructs that would consume transferred source",
        arguments: [
            "```text\nUnfinished", "<!-- open", "%% open", "<script>\nunfinished",
        ])
    func refusesLiteralSwallowing(_ target: String) throws {
        for operation in [NoteRestructureOperation.move, .merge, .copy] {
            #expect(throws: NoteRestructureError.self) {
                try plan("Claim.\n", target: target, passage: "Claim.", operation: operation)
            }
        }
    }

    @Test("Append after a closed literal keeps transferred prose active")
    func closedLiteralAppend() throws {
        for target in ["```text\nFinished\n```", "<!-- closed -->", "%% closed %%"] {
            let result = try plan("Claim. ^claim", target: target, passage: "Claim. ^claim", operation: .merge)
            #expect(result.target == target + "\n\nClaim. ^claim")
            let document = NoteDocument(relativePath: "Target.md", rawContent: try #require(result.target))
            #expect(ParagraphAnchorPlanner.anchors(in: document).map(\.id) == ["claim"])
        }
    }

    @Test("Footnote resource links use exact projected source ranges across folders", arguments: ["\n", "\r\n"])
    func footnoteResourceRelocation(_ newline: String) throws {
        let passage = "中文😀[^a]. ^claim"
        let definition =
            "[^a]:  [PDF](<../Assets/a%20b.pdf> 'Book')" + newline
            + "\t![图](../Assets/image.png) and `![literal](../Assets/code.png)`" + newline
            + "  [二](../Assets/second.pdf)"
        let source =
            "\u{FEFF}---" + newline + "custom: 'keep' # exact" + newline + "---" + newline
            + passage + newline + newline + definition + newline
        for operation in [NoteRestructureOperation.move, .copy, .merge] {
            let result = try plan(
                source, target: "", passage: passage, sourcePath: "Topics/Source.md",
                targetPath: "Works/Drafts/Target.md", operation: operation)
            let target = try #require(result.target)
            #expect(target.contains("[^a]:  [PDF](../../Assets/a%20b.pdf \"Book\")"))
            #expect(target.contains("\t![图](../../Assets/image.png) and `![literal](../Assets/code.png)`"))
            #expect(target.contains("  [二](../../Assets/second.pdf)"))
            let links = try NoteRestructureMarkdownLinks(NoteDocument(relativePath: "Works/Drafts/Target.md", rawContent: target)).occurrences
                .filter { !$0.raw.hasPrefix("[^") }
            #expect(links.map(\.destination) == ["../../Assets/a%20b.pdf", "../../Assets/image.png", "../../Assets/second.pdf"])
            if operation == .copy { #expect(result.source == source) }
        }
    }

    @Test(
        "New reference captures are escaped locally while original target bytes remain exact",
        arguments: ["[book]", "[label][book]", "![book]", "[book][]", "[*book*][BOOK]"])
    func literalReferenceCapture(_ literal: String) throws {
        let target = "[book]: https://different.example \"Book\"\n\nExisting [book].\n"
        let passage = "See " + literal + ". ^claim"
        let result = try plan(passage, target: target, passage: passage, operation: .merge)
        let after = try #require(result.target)
        #expect(after.hasPrefix(target + "\nSee "))
        #expect(after.contains("\\["))
        let links = try NoteRestructureMarkdownLinks(NoteDocument(relativePath: "Target.md", rawContent: after)).occurrences
        #expect(links.count == 1)
        #expect(links.first?.raw == "[book]")
    }

    @Test(
        "Nested definition declarations cannot silently capture destination prose",
        arguments: [
            "- [book]: https://original.example\n\n  See [book].\n",
            "> [book]: https://original.example\n>\n> See [book].\n",
            "1. [book]: https://original.example\n\n   See [book].\n",
        ])
    func nestedDefinitionScope(_ source: String) throws {
        #expect(throws: NoteRestructureError.self) {
            try plan(source, target: "Existing [book].\n", passage: source, operation: .merge)
        }
    }

    @Test("Reference shielding preserves escaped text, code, wikilinks and unrelated labels exactly")
    func alreadyLiteralReferences() throws {
        let source = "`[book]` and \\[book] and [other] and [[Source]]. ^claim"
        let target = "[book]: https://example.com\n"
        let result = try plan(source, target: target, passage: source, operation: .copy)
        let after = try #require(result.target)
        #expect(after.contains("`[book]` and \\[book] and [other] and [[Source]]"))
        #expect(result.source == source)
    }

    @Test(
        "Footnote and literal-block definitions cannot capture outer body text",
        arguments: [
            "Footnote[^a].\n\n[^a]: Note.\n  [book]: https://example.com\n",
            "%%\n[book]: https://example.com\n%%",
            "$$\n[book]: https://example.com\n$$",
        ])
    func isolatedDefinitionScope(_ trailing: String) throws {
        let passage = "See [book]. ^claim"
        let result = try plan(passage + "\n\n" + trailing, target: "", passage: passage)
        #expect(result.target == passage)
    }

    @Test("A multiline footnote link retains its authored CRLF and continuation prefix")
    func multilineFootnoteLink() throws {
        let passage = "Claim[^a]. ^claim"
        let source = passage + "\r\n\r\n[^a]: [多行\r\n  标签](../Assets/a.pdf)\r\n"
        let result = try plan(source, target: "", passage: passage, sourcePath: "Topics/Source.md", targetPath: "Works/Drafts/Target.md")
        #expect(result.target == passage + "\r\n\r\n[^a]: [多行\r\n  标签](../../Assets/a.pdf)")
    }

    private func plan(
        _ source: String, target: String, passage: String, sourcePath: String = "Source.md", targetPath: String = "Target.md",
        operation: NoteRestructureOperation = .move, incoming: String? = nil
    ) throws -> (source: String?, target: String?, incoming: String?) {
        let vault = UUID()
        let sourceID = VaultQualifiedNoteID(vaultID: vault, relativePath: sourcePath)
        let targetID = VaultQualifiedNoteID(vaultID: vault, relativePath: targetPath)
        let incomingID = VaultQualifiedNoteID(vaultID: vault, relativePath: "Incoming.md")
        let from = NoteDocument(relativePath: sourcePath, rawContent: source)
        let to = NoteDocument(relativePath: targetPath, rawContent: target)
        var documents = [sourceID: from, targetID: to]
        if let incoming { documents[incomingID] = NoteDocument(relativePath: "Incoming.md", rawContent: incoming) }
        let stringRange = try #require(source.range(of: passage))
        let start = source[..<stringRange.lowerBound].utf8.count
        let request = NoteRestructureRequest(
            source: .init(documentID: sourceID, stableNoteID: UUID(), revision: from.fingerprint),
            selectionUTF8: start..<(start + passage.utf8.count),
            destination: .existing(.init(documentID: targetID, stableNoteID: UUID(), revision: to.fingerprint)), operation: operation)
        let graph = LinkGraphBuilder.build(
            generation: 1, catalog: documents.map { LinkCatalogNote(vaultID: vault, document: $0.value) },
            documents: documents.mapValues(MarkdownSemanticDocument.init(parsing:)), resolutionScope: .workspace)
        let preview = try NoteRestructurePlanner.prepare(request, documents: documents, graph: graph)
        var result = documents.mapValues { Optional($0.rawContent) }
        for edit in preview.edits { result[edit.note] = .some(edit.after) }
        return (result[sourceID] ?? nil, result[targetID] ?? nil, result[incomingID] ?? nil)
    }
}
