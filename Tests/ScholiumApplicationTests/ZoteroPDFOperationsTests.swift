import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Read-only Zotero PDF import discovery")
struct ZoteroPDFOperationsTests {
    @Test("Discovery preserves group bibliography, PDF identity, and current metadata")
    func discoveryAndResolution() async throws {
        let fixture = PDFImportScript([
            .json(Self.parent), .json("[\(Self.attachment)]"),
            .json(Self.attachment), .json(Self.parent), .text("file:///fixture/Original.pdf"),
        ])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        let sources = try await operations.pdfAttachments(for: Self.hit)
        let source = try #require(sources.first)
        #expect(sources.count == 1)
        #expect(source.library.identity == .group(42))
        #expect(source.item == Self.hit.item)
        #expect(source.attachmentKey == "PDF00001")
        #expect(source.attachmentVersion == 12)
        #expect(source.itemReference.url.absoluteString == "zotero://select/groups/42/items/PARENT01")
        #expect(source.pdfReference.url.absoluteString == "zotero://open-pdf/groups/42/items/PDF00001")
        let candidate = try await operations.resolvePDFImport(source)
        #expect(candidate.originalURL.path == "/fixture/Original.pdf")
        let requests = await fixture.requests
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
        #expect(requests.allSatisfy { $0.url?.host == "127.0.0.1" && $0.url?.port == 23119 })
        #expect(requests.dropFirst().allSatisfy { $0.value(forHTTPHeaderField: "Zotero-Server-ID") == "DATABASE-1" })
        #expect(requests.last?.value(forHTTPHeaderField: "Accept") == "text/plain")
    }

    @Test("Non-PDF and URL-only children are excluded without losing real PDFs")
    func excludesNonPDF() async throws {
        let other = Self.attachment.replacingOccurrences(of: "application/pdf", with: "text/html")
        let linkedURL = Self.attachment.replacingOccurrences(of: "imported_file", with: "linked_url")
        let fixture = PDFImportScript([.json(Self.parent), .json("[\(other),\(linkedURL),\(Self.attachment)]")])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        let sources = try await operations.pdfAttachments(for: Self.hit)
        #expect(sources.map(\.attachmentKey) == ["PDF00001"])
    }

    @Test("An unpartitioned Zotero database cannot create a durable import mapping")
    func missingServerIdentity() async throws {
        let fixture = PDFImportScript([.json(Self.parent, serverID: nil)])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        await #expect(throws: ZoteroPDFImportError.stableIdentityUnavailable) {
            try await operations.pdfAttachments(for: Self.hit)
        }
    }

    @Test("Missing identity yields an observed local-copy choice, never a durable source")
    func explicitLocalCopyDiscovery() async throws {
        let fixture = PDFImportScript([
            .json(Self.observedParent, serverID: nil), .json("[\(Self.observedAttachment)]", serverID: nil),
            .json(Self.observedAttachment, serverID: nil), .json(Self.observedParent, serverID: nil),
            .json("file:///fixture/Original.pdf", serverID: nil),
        ])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        let options = try await operations.pdfImportOptions(for: Self.hit)
        guard case .localCopy(let observation) = try #require(options.first) else {
            Issue.record("Expected explicit local-copy choice")
            return
        }
        #expect(observation.observedLibraryID == 42)
        #expect(observation.parentVersion == 0 && observation.attachmentVersion == 0)
        let candidate = try await operations.resolvePDFLocalCopy(observation)
        #expect(candidate.originalURL.path == "/fixture/Original.pdf")
        #expect(candidate.observation == observation)
        #expect(await fixture.requests.allSatisfy { $0.value(forHTTPHeaderField: "Zotero-Server-ID") == nil })
    }

    @Test("Identity-capable discovery stays on the pinned route; malformed identities never downgrade")
    func explicitBranchAdmission() async throws {
        let verified = PDFImportScript([.json(Self.parent), .json("[\(Self.attachment)]")])
        let operations = ZoteroOperations(requestLoader: { try await verified.load($0) })
        let option = try #require(try await operations.pdfImportOptions(for: Self.hit).first)
        guard case .verifiedSource(let source) = option else {
            Issue.record("Verified source was downgraded")
            return
        }
        #expect(source.serverID == "DATABASE-1")
        #expect(await verified.requests.last?.value(forHTTPHeaderField: "Zotero-Server-ID") == source.serverID)
        let malformed = PDFImportScript([.json(Self.observedParent, serverID: " ")])
        let invalid = ZoteroOperations(requestLoader: { try await malformed.load($0) })
        await #expect(throws: ZoteroPDFImportError.stableIdentityUnavailable) { try await invalid.pdfImportOptions(for: Self.hit) }
        #expect(await malformed.requests.count == 1)
    }

    @Test("Local-copy metadata drift is rejected even when synced versions stay zero", arguments: [true, false])
    func localCopyObservationDrift(parentChanged: Bool) async throws {
        let changedParent = Self.observedParent.replacingOccurrences(of: "\"itemType\":\"book\"", with: "\"extra\":\"changed\",\"itemType\":\"book\"")
        let changedAttachment = Self.observedAttachment.replacingOccurrences(of: "PDF Original", with: "Replacement PDF")
        let fixture = PDFImportScript([
            .json(Self.observedParent, serverID: nil), .json("[\(Self.observedAttachment)]", serverID: nil),
            .json(parentChanged ? Self.observedAttachment : changedAttachment, serverID: nil),
            .json(parentChanged ? changedParent : Self.observedParent, serverID: nil),
        ])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        guard case .localCopy(let observation) = try #require(try await operations.pdfImportOptions(for: Self.hit).first) else { return }
        await #expect(throws: ZoteroPDFImportError.sourceChanged) { try await operations.resolvePDFLocalCopy(observation) }
        #expect(await fixture.requests.count == 4)
    }

    @Test("A local-copy locator move fails revalidation")
    func localCopyLocatorDrift() async throws {
        let fixture = PDFImportScript([
            .json(Self.observedParent, serverID: nil), .json("[\(Self.observedAttachment)]", serverID: nil),
            .json(Self.observedAttachment, serverID: nil), .json(Self.observedParent, serverID: nil), .json("file:///fixture/Original.pdf", serverID: nil),
            .json(Self.observedAttachment, serverID: nil), .json(Self.observedParent, serverID: nil), .json("file:///moved/Original.pdf", serverID: nil),
        ])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        guard case .localCopy(let observation) = try #require(try await operations.pdfImportOptions(for: Self.hit).first) else { return }
        let candidate = try await operations.resolvePDFLocalCopy(observation)
        await #expect(throws: ZoteroPDFImportError.sourceChanged) { try await operations.revalidatePDFLocalCopy(candidate) }
    }

    @Test("The local-copy branch rejects a newly identified database or another returned library", arguments: [true, false])
    func localCopyBoundaryChanged(identityAppeared: Bool) async throws {
        let otherLibrary = Self.observedAttachment.replacingOccurrences(of: "\"id\":42", with: "\"id\":43")
        let fixture = PDFImportScript([
            .json(Self.observedParent, serverID: nil),
            .json("[\(identityAppeared ? Self.observedAttachment : otherLibrary)]", serverID: identityAppeared ? "DATABASE-1" : nil),
        ])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        if identityAppeared {
            await #expect(throws: ZoteroPDFImportError.sourceChanged) { try await operations.pdfImportOptions(for: Self.hit) }
        } else {
            await #expect(throws: ZoteroPDFImportError.invalidResponse) { try await operations.pdfImportOptions(for: Self.hit) }
        }
    }

    @Test("A Zotero profile switch is refused even when item keys remain equal")
    func databaseSwitch() async throws {
        let fixture = PDFImportScript([.json(Self.parent), .json("[\(Self.attachment)]", serverID: "DATABASE-2")])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        await #expect(throws: ZoteroPDFImportError.sourceChanged) {
            try await operations.pdfAttachments(for: Self.hit)
        }
    }

    @Test("Attachment metadata changes fail before original bytes are opened")
    func changedAttachmentMetadata() async throws {
        let changed = Self.attachment.replacingOccurrences(of: "\"title\":\"PDF Original\"", with: "\"title\":\"Replacement PDF\"")
        let fixture = PDFImportScript([.json(Self.parent), .json("[\(Self.attachment)]"), .json(changed)])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        let source = try #require(try await operations.pdfAttachments(for: Self.hit).first)
        await #expect(throws: ZoteroPDFImportError.sourceChanged) {
            try await operations.resolvePDFImport(source)
        }
        #expect(await fixture.requests.count == 3)
    }

    @Test(
        "Original URLs reject remote hosts, traversal, mismatched files, and URL parameters",
        arguments: [
            "https://example.invalid/Original.pdf", "file://server/fixture/Original.pdf",
            "file:///fixture/../Original.pdf", "file:///fixture/Replacement.pdf", "file:///fixture/Original.pdf?query=value",
        ])
    func rejectedOriginalURL(_ locator: String) async throws {
        let fixture = PDFImportScript([
            .json(Self.parent), .json("[\(Self.attachment)]"),
            .json(Self.attachment), .json(Self.parent), .text(locator),
        ])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        let source = try #require(try await operations.pdfAttachments(for: Self.hit).first)
        await #expect(throws: ZoteroPDFImportError.originalUnavailable) {
            try await operations.resolvePDFImport(source)
        }
    }

    @Test("Revalidation rejects a moved original while keeping attachment identity")
    func movedOriginal() async throws {
        let fixture = PDFImportScript([
            .json(Self.parent), .json("[\(Self.attachment)]"),
            .json(Self.attachment), .json(Self.parent), .text("file:///fixture/Original.pdf"),
            .json(Self.attachment), .json(Self.parent), .text("file:///different/Original.pdf"),
        ])
        let operations = ZoteroOperations(requestLoader: { try await fixture.load($0) })
        let source = try #require(try await operations.pdfAttachments(for: Self.hit).first)
        let candidate = try await operations.resolvePDFImport(source)
        await #expect(throws: ZoteroPDFImportError.sourceChanged) {
            try await operations.revalidatePDFImport(candidate)
        }
    }

    @Test("Cancellation is not reported as an unavailable Zotero app")
    func cancellation() async throws {
        let operations = ZoteroOperations(requestLoader: { _ in throw CancellationError() })
        await #expect(throws: CancellationError.self) {
            try await operations.pdfAttachments(for: Self.hit)
        }
    }

    private static let hit = ZoteroSearchHit(
        library: ZoteroLibraryMetadata(identity: .group(42), name: "Synthetic Library"),
        item: ZoteroItemMetadata(key: "PARENT01", itemType: "book", title: "Synthetic Book"))
    private static let parent = """
        {"key":"PARENT01","version":11,"data":{"key":"PARENT01","itemType":"book","title":"Synthetic Book"}}
        """
    private static let attachment = """
        {"key":"PDF00001","version":12,"data":{"key":"PDF00001","itemType":"attachment","parentItem":"PARENT01","title":"PDF Original","contentType":"application/pdf","linkMode":"imported_file","filename":"Original.pdf"}}
        """
    private static let observedParent = """
        {"key":"PARENT01","version":0,"library":{"type":"group","id":42,"name":"Synthetic Library"},"data":{"key":"PARENT01","version":0,"itemType":"book","title":"Synthetic Book"}}
        """
    private static let observedAttachment = """
        {"key":"PDF00001","version":0,"library":{"type":"group","id":42,"name":"Synthetic Library"},"data":{"key":"PDF00001","version":0,"itemType":"attachment","parentItem":"PARENT01","title":"PDF Original","contentType":"application/pdf","linkMode":"imported_file","filename":"Original.pdf"}}
        """
}

private actor PDFImportScript {
    struct Response: Sendable {
        let bytes: Data
        let serverID: String?

        static func json(_ string: String, serverID: String? = "DATABASE-1") -> Self {
            Self(bytes: Data(string.utf8), serverID: serverID)
        }

        static func text(_ string: String) -> Self { .json(string) }
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [Response]) { self.responses = responses }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url, !responses.isEmpty else { throw URLError(.badServerResponse) }
        requests.append(request)
        let response = responses.removeFirst()
        let headers = response.serverID.map { ["Zotero-Server-ID": $0] } ?? [:]
        let http = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers))
        return (response.bytes, http)
    }
}
