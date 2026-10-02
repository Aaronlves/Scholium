import CoreGraphics
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Note-bound PDF application lifecycle")
struct PDFReaderOperationsTests {
    @Test("All roles share one PDF, dirty authored paths drive resolution, and Note/folder moves preserve the binding")
    func sharedBindingsAndMoves() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let runtime = fixture.runtime()
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let fixturePDF = fixture.root.appendingPathComponent("Original.pdf")
        let originalBytes = Self.pdf()
        try originalBytes.write(to: fixturePDF)
        var attachmentID: UUID?
        var analysisID: VaultQualifiedNoteID?
        for slot in WorkspaceVaultSlot.allCases {
            let vault = try #require(fixture.assignment.vault(for: slot))
            let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: "Bound.md")
            let snapshot = try await handle.refresh()
            let summary = try #require(snapshot.document(id: id))
            let noteID = try #require(summary.stableIdentity.resolvedID)
            let target = SourceAttachmentTarget(noteID: noteID, vaultID: vault.id, relativePath: id.relativePath)
            let prepared: PDFReaderImport
            if let attachmentID {
                prepared = try await handle.pdfReader.attachPDF(attachmentID: attachmentID, for: target)
            } else {
                prepared = try await handle.pdfReader.importPDF(at: fixturePDF, for: target, zoteroSource: nil, allowNewVersion: false)
                attachmentID = prepared.snapshot.record.id
            }
            // The editor's current path can be read before saving its YAML.
            #expect(try await handle.pdfReader.boundPDF(for: target, authoredPath: prepared.noteRelativePath)?.record.id == attachmentID)
            #expect(try await handle.pdfReader.boundPDF(for: target, authoredPath: nil) == nil)
            await #expect(throws: PDFReaderError.invalidBinding) { try await handle.pdfReader.boundPDF(for: target, authoredPath: "") }
            let before = try await handle.documents.load(id)
            let planned = try NoteInfoMetadataPlanner.plan(document: before, edits: ["pdf": .string(prepared.noteRelativePath)])
            let patch = try #require(planned)
            let saved = try await handle.documents.save(id, changeSet: .exactContent(patch.resultingSource), expectedRevision: before.fingerprint)
                .committedValue
            #expect(saved.document.rawContent.hasSuffix("---\r\nBody stays exact.\r\n"))
            #expect(saved.document.rawContent.contains("custom: 'retained' # comment\r\n"))
            if slot == .paperAnalysis { analysisID = id }
        }
        #expect(try await handle.pdfReader.availablePDFs().count == 1)
        let sourceID = try #require(analysisID)
        let source = try await handle.documents.load(sourceID)
        _ = try await handle.documents.move(sourceID, to: "Nested/Bound.md", expectedRevision: source.fingerprint)
        let nestedID = VaultQualifiedNoteID(vaultID: sourceID.vaultID, relativePath: "Nested/Bound.md")
        let nested = try await handle.documents.load(nestedID)
        let nestedPath = try PDFNoteBinding.path(in: nested)
        let nestedBinding = try #require(nestedPath)
        #expect(nestedBinding.hasPrefix("../../.scholium/attachments/files/"))
        // A missing shared PDF does not prevent preserving its authored locator on move.
        let record = try #require(try await handle.pdfReader.availablePDFs().first)
        guard case .triptychRelative(let path) = record.location else { throw PDFReaderError.unsafePath }
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent(".scholium/\(path.rawValue)"))
        let destinationParent = try await handle.documents.createUntitledFolder(inVault: sourceID.vaultID, parentRelativePath: nil).committedValue
        _ = try await handle.documents.moveFolder(inVault: sourceID.vaultID, from: destinationParent.rawValue, to: "Deep")
        _ = try await handle.documents.moveFolder(inVault: sourceID.vaultID, from: "Nested", to: "Deep/Nested")
        let deep = try await handle.documents.load(VaultQualifiedNoteID(vaultID: sourceID.vaultID, relativePath: "Deep/Nested/Bound.md"))
        let deepPath = try PDFNoteBinding.path(in: deep)
        let deepBinding = try #require(deepPath)
        #expect(deepBinding.hasPrefix("../../../.scholium/attachments/files/"))
        #expect(deep.rawContent.contains("custom: 'retained' # comment\r\n"))
        #expect(try Data(contentsOf: fixturePDF) == originalBytes)
        await runtime.shutdown()
        await #expect(throws: PDFReaderError.unreadable) { try await handle.pdfReader.availablePDFs() }
    }

    @Test("Explicit Local Copy retains no Zotero mapping and reuses only the local digest")
    func localCopyPersistenceAndReuse() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let original = fixture.root.appendingPathComponent("Original.pdf")
        let bytes = Self.pdf()
        try bytes.write(to: original)
        let script = LocalCopyImportScript(Self.localCopyResponses(original: original, revalidations: 2))
        let zotero = ZoteroOperations(requestLoader: { try await script.load($0) })
        let candidate = try await localCopyCandidate(zotero)
        let runtime = fixture.runtime(zotero: zotero)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await localCopyTarget(handle: handle, fixture: fixture)
        let noteURL = fixture.root.appendingPathComponent("Analyses/Bound.md")
        let noteBytes = try Data(contentsOf: noteURL)
        let first = try await handle.pdfReader.importLocalCopy(candidate, for: target, allowNewVersion: false)
        #expect(first.wasNew && first.snapshot.record.zoteroSource == nil)
        #expect(first.snapshot.record.importedSourceFingerprint == DocumentFingerprint(data: bytes))
        #expect(first.snapshot.data == bytes)
        let reused = try await handle.pdfReader.importLocalCopy(candidate, for: target, allowNewVersion: false)
        #expect(!reused.wasNew && reused.snapshot.record.id == first.snapshot.record.id)
        #expect(try await handle.pdfReader.availablePDFs().count == 1)
        #expect(try Data(contentsOf: original) == bytes)
        #expect(try Data(contentsOf: noteURL) == noteBytes)
        #expect(await script.requestCount == 11)
        await runtime.shutdown()
    }

    @Test("Local-copy observation changes at the copy boundary leave no attachment")
    func localCopyMetadataRace() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let original = fixture.root.appendingPathComponent("Original.pdf")
        let bytes = Self.pdf()
        try bytes.write(to: original)
        let script = LocalCopyImportScript(
            Self.localCopyResponses(
                original: original, changedAttachment: Self.localAttachment.replacingOccurrences(of: "Fixture PDF", with: "Changed PDF")))
        let zotero = ZoteroOperations(requestLoader: { try await script.load($0) })
        let candidate = try await localCopyCandidate(zotero)
        let runtime = fixture.runtime(zotero: zotero)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await localCopyTarget(handle: handle, fixture: fixture)
        await #expect(throws: ZoteroPDFImportError.sourceChanged) {
            try await handle.pdfReader.importLocalCopy(candidate, for: target, allowNewVersion: false)
        }
        #expect(try await handle.pdfReader.availablePDFs().isEmpty)
        #expect(try Data(contentsOf: original) == bytes)
        await runtime.shutdown()
    }

    @Test("The second coordinated bytes read still rejects a Local Copy replacement during API revalidation")
    func localCopyBytesRace() async throws {
        let fixture = try await Fixture.make()
        defer { fixture.remove() }
        let original = fixture.root.appendingPathComponent("Original.pdf")
        let bytes = Self.pdf()
        try bytes.write(to: original)
        let changed = bytes + Data("\n% fixture concurrent replacement\n".utf8)
        let script = LocalCopyImportScript(Self.localCopyResponses(original: original)) {
            try changed.write(to: original, options: .atomic)
        }
        let zotero = ZoteroOperations(requestLoader: { try await script.load($0) })
        let candidate = try await localCopyCandidate(zotero)
        let runtime = fixture.runtime(zotero: zotero)
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let target = try await localCopyTarget(handle: handle, fixture: fixture)
        await #expect(throws: PDFReaderError.sourceChanged) {
            try await handle.pdfReader.importLocalCopy(candidate, for: target, allowNewVersion: false)
        }
        #expect(try await handle.pdfReader.availablePDFs().isEmpty)
        #expect(try Data(contentsOf: original) == changed)
        #expect(await script.requestCount == 8)
        await runtime.shutdown()
    }

    private func localCopyCandidate(_ zotero: ZoteroOperations) async throws -> ZoteroPDFLocalCopyCandidate {
        let hit = ZoteroSearchHit(
            library: ZoteroLibraryMetadata(identity: .group(42), name: "Fixture Group"),
            item: ZoteroItemMetadata(key: "PARENT01", itemType: "book", title: "Fixture Book"))
        guard case .localCopy(let observation) = try #require(try await zotero.pdfImportOptions(for: hit).first)
        else { throw ZoteroPDFImportError.invalidResponse }
        return try await zotero.resolvePDFLocalCopy(observation)
    }

    private func localCopyTarget(handle: WorkspaceHandle, fixture: Fixture) async throws -> SourceAttachmentTarget {
        let vault = try #require(fixture.assignment.vault(for: .paperAnalysis))
        let id = VaultQualifiedNoteID(vaultID: vault.id, relativePath: "Bound.md")
        let snapshot = try await handle.refresh()
        let noteID = try #require(snapshot.document(id: id)?.stableIdentity.resolvedID)
        return SourceAttachmentTarget(noteID: noteID, vaultID: vault.id, relativePath: id.relativePath)
    }

    private static func localCopyResponses(original: URL, revalidations: Int = 1, changedAttachment: String? = nil) -> [String] {
        var responses = [localParent, "[\(localAttachment)]", localAttachment, localParent, original.absoluteString]
        for _ in 0..<revalidations {
            responses += [changedAttachment ?? localAttachment, localParent]
            if changedAttachment == nil { responses.append(original.absoluteString) }
        }
        return responses
    }

    private static let localParent = """
        {"key":"PARENT01","version":0,"library":{"type":"group","id":42,"name":"Fixture Group"},"data":{"key":"PARENT01","version":0,"itemType":"book","title":"Fixture Book"}}
        """
    private static let localAttachment = """
        {"key":"PDF00001","version":0,"library":{"type":"group","id":42,"name":"Fixture Group"},"data":{"key":"PDF00001","version":0,"itemType":"attachment","parentItem":"PARENT01","title":"Fixture PDF","contentType":"application/pdf","linkMode":"imported_file","filename":"Original.pdf"}}
        """

    private static func pdf() -> Data {
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data)!
        var box = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.move(to: CGPoint(x: 20, y: 20))
        context.addLine(to: CGPoint(x: 180, y: 180))
        context.strokePath()
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private struct Fixture: Sendable {
        let root: URL
        let support: URL
        let assignment: TriptychAssignment

        static func make() async throws -> Fixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/pdf-application-fixtures/\(UUID().uuidString)")
            let support = root.appendingPathComponent("State")
            let folders = ["Analyses", "Topics", "Works"]
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            for folder in folders {
                let url = root.appendingPathComponent(folder)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data("\u{FEFF}---\r\ncustom: 'retained' # comment\r\n---\r\nBody stays exact.\r\n".utf8).write(to: url.appendingPathComponent("Bound.md"))
            }
            let runtime = WorkspaceRuntime(configuration: .live(.init(applicationSupportURL: support, workspaceRegistryStorageURL: support)))
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: root.appendingPathComponent(folders[0]), topicKnowledgeURL: root.appendingPathComponent(folders[1]),
                outputURL: root.appendingPathComponent(folders[2]), portableContainerURL: root, triptychName: "PDF Fixture")
            let assignment = handle.assignment
            await runtime.shutdown()
            return Fixture(root: root, support: support, assignment: assignment)
        }

        func runtime(zotero: ZoteroOperations? = nil) -> WorkspaceRuntime {
            WorkspaceRuntime(configuration: .snapshot(.init(applicationSupportURL: support, assignments: [assignment])), zotero: zotero)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

private actor LocalCopyImportScript {
    private var responses: [String]
    private let afterFinalResponse: @Sendable () throws -> Void
    private(set) var requestCount = 0

    init(_ responses: [String], afterFinalResponse: @escaping @Sendable () throws -> Void = {}) {
        self.responses = responses
        self.afterFinalResponse = afterFinalResponse
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url, !responses.isEmpty else { throw URLError(.badServerResponse) }
        #expect(request.value(forHTTPHeaderField: "Zotero-Server-ID") == nil)
        requestCount += 1
        let bytes = Data(responses.removeFirst().utf8)
        if responses.isEmpty { try afterFinalResponse() }
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]))
        return (bytes, response)
    }
}
