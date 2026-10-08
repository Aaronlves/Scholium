import Foundation
import ScholiumContracts
import Testing

@Suite("Portable Zotero citation companions")
struct ZoteroCitationCompanionTests {
    private let noteID = UUID(), vaultID = UUID()
    private let firstCode = #"ITEM CSL_CITATION {"citationItems":[{"id":"http://zotero.org/users/1/items/ABCDEFGH"}],"opaque":"é"}"#
    private let secondCode = #"ITEM CSL_CITATION {"citationItems":[{"id":"http://zotero.org/users/1/items/IJKLMNOP"}]}"#

    private func data(accepted: Bool = true) -> ZoteroCitationData {
        .init(
            fields: [
                .init(id: "one", kind: .citation, code: firstCode, text: "<i>Original</i>"),
                .init(id: "two", kind: .citation, code: secondCode, text: "<i>Original</i>"),
            ], documentData: "<data>\r\nopaque \"vendor\" data</data>",
            acceptedFields: accepted ? [.init(id: "one", code: firstCode), .init(id: "two", code: secondCode)] : nil)
    }

    private func document(_ source: String, data: ZoteroCitationData? = nil, fingerprint: DocumentFingerprint? = nil) -> NoteDocument {
        .init(
            relativePath: "Draft.md", rawContent: source,
            citationSnapshot: .init(
                noteID: noteID, vaultID: vaultID, revision: DocumentFingerprint(content: "exact companion bytes"),
                sourceFingerprint: fingerprint ?? DocumentFingerprint(content: source), data: data ?? self.data(), status: .available))
    }

    @Test("Repeated visible labels keep distinct field identity and source-owned text")
    func repeatedLabels() throws {
        let source = "😀 e\u{301} [*Same*](cite:one) and [*Same*](cite:two)."
        let note = document(source)
        let catalog = ZoteroMarkdownFields(parsing: note)
        #expect(catalog.canMutate)
        #expect(catalog.fields.map(\.code) == [firstCode, secondCode])
        #expect(catalog.fields.map(\.plainText) == ["Same", "Same"])
        #expect(!catalog.citationStateStale)
        let allCompleted = catalog.fields.allSatisfy { $0.isCompleted }
        #expect(allCompleted)
        #expect(catalog.readingProjection(source: source)?.source == "😀 e\u{301} *Same* and *Same*.")
        let html = SafeMarkdownRenderer.render(note).htmlBody
        #expect(html.contains("<em>Same</em>"))
        #expect(!html.contains("Original"))
        #expect(!html.contains("cite:"))
        let atStart = "[Same](cite:one) [Same](cite:two)"
        #expect(ZoteroMarkdownFields(parsing: document(atStart)).readingProjection(source: atStart)?.source == "Same Same")
    }

    @Test("Missing, malformed and unsupported citation links are static, never navigation")
    func missingCompanion() {
        for destination in ["cite:one", "cite:", "CITE:one", "cite:invalid?x=1", "scholium-zotero:2:AAAA"] {
            let source = "Before [Readable **label**](\(destination)) after."
            let note = NoteDocument(relativePath: "Static.md", rawContent: source)
            let catalog = ZoteroMarkdownFields(parsing: note)
            #expect(!catalog.canMutate)
            #expect(catalog.fields.isEmpty)
            #expect(MarkdownSemanticDocument(parsing: note).links.isEmpty)
            #expect(SourceResourceReferences.externalLinks(in: source).isEmpty)
            #expect(SourceResourceReferences.files(in: source, noteRelativePath: "Static.md").isEmpty)
            let html = SafeMarkdownRenderer.render(note).htmlBody
            #expect(html.contains("Readable <strong>label</strong>"))
            #expect(!html.contains("href="))
            #expect(note.rawContent == source)
        }
    }

    @Test("Companion authority requires exact source bytes and a checked available status")
    func revisionAndStatusGuards() {
        let source = "[Same](cite:one) and [Same](cite:two)"
        let stale = document(source, fingerprint: DocumentFingerprint(content: source + "\n"))
        #expect(!ZoteroMarkdownFields(parsing: stale).canMutate)
        #expect(ZoteroMarkdownFields(parsing: stale).fields.isEmpty)
        for status in [ZoteroCitationSnapshot.Status.unresolved, .unsupported] {
            let unavailable = NoteDocument(
                relativePath: "Empty.md", rawContent: "Plain readable text",
                citationSnapshot: .init(
                    noteID: noteID, vaultID: vaultID, status: status))
            #expect(!ZoteroMarkdownFields(parsing: unavailable).canMutate)
        }
        let absent = NoteDocument(
            relativePath: "New.md", rawContent: "Plain text",
            citationSnapshot: .init(
                noteID: noteID, vaultID: vaultID, status: .absent))
        #expect(ZoteroMarkdownFields(parsing: absent).canMutate)
    }

    @Test("Malformed YAML retains citation refusal without interpreting uncertain source ranges")
    func malformedFrontmatterCompanionAuthority() throws {
        let sources = [
            "\u{FEFF}---\r\nbroken: [\r\n---\r\nReadable 😀 e\u{301} prose.",
            "\u{FEFF}---\r\nbroken: [\r\nReadable 😀 e\u{301} prose.",
        ]
        for source in sources {
            for status in [ZoteroCitationSnapshot.Status.available, .unresolved, .unsupported] {
                let note = NoteDocument(
                    relativePath: "Malformed.md", rawContent: source,
                    citationSnapshot: .init(
                        noteID: noteID, vaultID: vaultID,
                        sourceFingerprint: DocumentFingerprint(content: source),
                        data: status == .available ? data() : nil, status: status))
                #expect(note.frontmatterState == .malformed)
                let catalog = ZoteroMarkdownFields(parsing: note)
                #expect(!catalog.canMutate)
                #expect(catalog.fields.isEmpty && catalog.documentState == nil)
                #expect(catalog.metadataSpans.isEmpty)
                #expect(catalog.readingProjection(source: source)?.source.utf8.elementsEqual(source.utf8) == true)
                #expect(note.sourceBytes == Data(source.utf8))
            }
        }
        // Malformed ordinary YAML is not itself a citation problem. Checked
        // companion absence remains distinct from authority that cannot be read.
        let source = try #require(sources.first)
        let ordinary = NoteDocument(relativePath: "Ordinary.md", rawContent: source)
        let absent = ordinary.withCitationSnapshot(.init(noteID: noteID, vaultID: vaultID, status: .absent))
        #expect(ZoteroMarkdownFields(parsing: ordinary).canMutate)
        #expect(ZoteroMarkdownFields(parsing: absent).canMutate)
        let marked = NoteDocument(relativePath: "Missing.md", rawContent: source + " [Readable](cite:one)")
        #expect(!ZoteroMarkdownFields(parsing: marked).canMutate)
        #expect(ZoteroMarkdownFields(parsing: marked).fields.isEmpty)
    }

    @Test("Copied IDs refuse association while known deletion retains metadata and marks stale")
    func copiesAndDeletion() {
        let copied = ZoteroMarkdownFields(parsing: document("[Same](cite:one) [Same](cite:one) [Other](cite:two)"))
        #expect(!copied.canMutate)
        #expect(copied.diagnostics.filter { $0.kind == .duplicateID }.count == 2)
        #expect(!copied.fields.contains { $0.id == "one" })
        let deleted = ZoteroMarkdownFields(parsing: document("[Same](cite:two)"))
        #expect(deleted.canMutate)
        #expect(deleted.fields.map(\.id) == ["two"])
        #expect(deleted.citationStateStale)
        let unknown = ZoteroMarkdownFields(parsing: document("[Same](cite:foreign)"))
        #expect(!unknown.canMutate)
        #expect(unknown.fields.isEmpty)
    }

    @Test("Bibliography markers associate only with matching bibliography metadata")
    func bibliography() {
        let source = "<!--cite-bibliography:bib-->\r\n\r\nFang. *Book*.\r\n\r\n<!--/cite-bibliography-->"
        let data = ZoteroCitationData(fields: [.init(id: "bib", kind: .bibliography, code: "BIBL {} CSL_BIBLIOGRAPHY", text: "Vendor")])
        let catalog = ZoteroMarkdownFields(parsing: document(source, data: data))
        #expect(catalog.canMutate)
        #expect(catalog.fields.first?.fallbackMarkdown == "Fang. *Book*.")
        #expect(catalog.fields.first?.isCompleted == true)
        #expect(catalog.fields.first?.markerSpans.count == 2)
        let mismatch = ZoteroCitationData(fields: [.init(id: "bib", kind: .citation, code: firstCode, text: "Vendor")])
        #expect(!ZoteroMarkdownFields(parsing: document(source, data: mismatch)).canMutate)
        #expect(!ZoteroMarkdownFields(parsing: document(source + "\r\n\r\n<!--/cite-bibliography-->", data: data)).canMutate)
        #expect(!ZoteroMarkdownFields(parsing: document(source.replacingOccurrences(of: "\r\n\r\n", with: "\r\n"), data: data)).canMutate)
    }

    @Test("Explicit conversion replaces only carriers and preserves opaque bytes and source trivia")
    func conversion() throws {
        func encoded(_ object: [String: Any]) throws -> String {
            try JSONSerialization.data(withJSONObject: object).base64EncodedString()
        }
        let embedded = "[Same *e\u{301}*](scholium-zotero:1:\(try encoded(["id": "one", "kind": "citation", "code": firstCode, "text": "<i>Vendor</i>"])))"
        let bibOpen =
            "<!--scholium-zotero-field:1:\(try encoded(["id": "bib", "kind": "bibliography", "code": "BIBL {} CSL_BIBLIOGRAPHY", "text": "Vendor bibliography"]))-->"
        let docMarker =
            "<!--scholium-zotero-document:1:\(try encoded(["data": "opaque\r\npreferences", "acceptedFields": [["id": "one", "code": firstCode], ["id": "bib", "code": "BIBL {} CSL_BIBLIOGRAPHY"]]]))-->"
        let prefix = "\u{FEFF}---\r\n# untouched\r\nunknown: 'quoted'\r\n---\r\n😀 "
        let source =
            prefix + embedded + " end.\r\n\r\n" + bibOpen + "\r\n\r\nFang. *Book.*\r\n\r\n<!--/scholium-zotero-field-->\r\n\r\n" + docMarker + "\r\nTail"
        let note = NoteDocument(relativePath: "Convert.md", rawContent: source)
        let converted = try ZoteroMarkdownFields.convertEmbeddedToCompanion(in: note)
        let expected =
            prefix
            + "[Same *e\u{301}*](cite:one) end.\r\n\r\n<!--cite-bibliography:bib-->\r\n\r\nFang. *Book.*\r\n\r\n<!--/cite-bibliography-->\r\n\r\n\r\nTail"
        #expect(Data(converted.source.utf8) == Data(expected.utf8))
        #expect(Data(converted.data.fields[0].code.utf8) == Data(firstCode.utf8))
        #expect(converted.data.documentData == "opaque\r\npreferences")
        #expect(converted.data.fields.map(\.id) == ["one", "bib"])
        #expect(!ZoteroMarkdownFields(parsing: document(converted.source, data: converted.data)).citationStateStale)
        #expect(Data(note.rawContent.utf8) == Data(source.utf8))
        #expect(ZoteroMarkdownFields(parsing: note).canMutate)
        #expect(throws: ZoteroCitationError.self) {
            try ZoteroMarkdownFields.convertEmbeddedToCompanion(in: NoteDocument(relativePath: "Duplicate.md", rawContent: embedded + " " + embedded))
        }
    }

    @Test("Managed duplication remints occurrences without changing readable prose or vendor data")
    func duplicate() throws {
        let source = "Before [Same](cite:one) and [Same](cite:two).\r\nAfter e\u{301}"
        let duplicated = try ZoteroMarkdownFields.duplicateCompanion(in: document(source))
        let fields = duplicated.data.fields
        #expect(fields.count == 2)
        #expect(Set(fields.map(\.id)).count == 2)
        #expect(fields.allSatisfy { !["one", "two"].contains($0.id) && ZoteroCitationData.isValidOccurrenceID($0.id) })
        #expect(fields.map(\.code) == [firstCode, secondCode])
        #expect(duplicated.data.acceptedFields?.map(\.id) == fields.map(\.id))
        let restored = duplicated.source.replacingOccurrences(of: "cite:" + fields[0].id, with: "cite:one")
            .replacingOccurrences(of: "cite:" + fields[1].id, with: "cite:two")
        #expect(Data(restored.utf8) == Data(source.utf8))
        #expect(!ZoteroMarkdownFields(parsing: document(duplicated.source, data: duplicated.data)).citationStateStale)
    }

    @Test("Record bounds, ownership, schema and unknown members fail closed")
    func durableValidation() throws {
        let source = "[Same](cite:one) [Same](cite:two)"
        let record = ZoteroCitationCompanion(noteID: noteID, vaultID: vaultID, sourceFingerprint: DocumentFingerprint(content: source), data: data())
        let bytes = try JSONEncoder().encode(record)
        #expect(try ZoteroCitationCompanion.decode(bytes) == record)
        #expect(throws: ZoteroCitationError.ownershipMismatch) { try record.validate(noteID: UUID(), vaultID: vaultID) }
        #expect(throws: ZoteroCitationError.sourceMismatch) {
            try record.validate(noteID: noteID, vaultID: vaultID, sourceFingerprint: DocumentFingerprint(content: source + " "))
        }
        #expect(throws: ZoteroCitationError.unsupportedVersion) { try ZoteroCitationData(schemaVersion: 2).validate() }
        #expect(throws: ZoteroCitationError.invalidData) {
            try ZoteroCitationData(fields: [.init(id: "same", kind: .citation, code: "x", text: "x"), .init(id: "same", kind: .citation, code: "y", text: "y")])
                .validate()
        }
        #expect(throws: ZoteroCitationError.invalidData) {
            try ZoteroCitationData(documentData: String(repeating: "x", count: ZoteroCitationData.maximumDocumentDataUTF16Count + 1)).validate()
        }
        #expect(!ZoteroCitationData.isValidOccurrenceID("valid\n"))
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        object["futureAuthority"] = "must not discard"
        let future = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ZoteroCitationError.unsupportedVersion) { try ZoteroCitationCompanion.decode(future) }
    }

    @Test("Attaching a snapshot and citation source changes preserve exact text")
    func documentContract() throws {
        let source = "\u{FEFF}---\r\ncustom: 'keep' # exact\r\n---\r\ne\u{301}"
        let note = NoteDocument(relativePath: "Exact.md", rawContent: source)
        let snapshot = ZoteroCitationSnapshot(noteID: noteID, vaultID: vaultID, status: .absent)
        let attached = note.withCitationSnapshot(snapshot)
        #expect(attached.sourceBytes == note.sourceBytes)
        #expect(attached.fingerprint == note.fingerprint)
        #expect(attached.citationSnapshot == snapshot)
        let edit = ZoteroCitationEdit(expectedRevision: nil, data: .init())
        #expect(Data(try attached.applying(.citationSource(source, edit), timestampKey: "modified").utf8) == note.sourceBytes)
        #expect(attached.withCitationSnapshot(nil).citationSnapshot == nil)
    }
}
