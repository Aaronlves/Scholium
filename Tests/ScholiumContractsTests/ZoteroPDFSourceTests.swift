import Foundation
import ScholiumContracts
import Testing

@Suite("Portable Zotero PDF identity")
struct ZoteroPDFSourceTests {
    @Test("Durable dedup separates databases and libraries, and survives Codable")
    func identityAndRoundTrip() throws {
        let first = try source(serverID: "DATABASE-A", library: .user)
        let otherDatabase = try source(serverID: "DATABASE-B", library: .user)
        let otherLibrary = try source(serverID: "DATABASE-A", library: .group(42))
        #expect(Set([first.stableIdentity, otherDatabase.stableIdentity, otherLibrary.stableIdentity]).count == 3)
        #expect(try JSONDecoder().decode(ZoteroPDFSource.self, from: JSONEncoder().encode(first)) == first)
    }

    @Test("A malformed persisted attachment is rejected instead of producing an unsafe reference")
    func rejectsMalformedPersistence() throws {
        let value = try source(serverID: "DATABASE-A", library: .user)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["attachmentKey"] = "../unsafe"
        let bytes = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ZoteroPDFImportError.invalidResponse) { try JSONDecoder().decode(ZoteroPDFSource.self, from: bytes) }
    }

    @Test("Missing database identity never becomes durable provenance")
    func durableIdentityRemainsRequired() {
        #expect(throws: ZoteroPDFImportError.invalidResponse) { try source(serverID: "", library: .user) }
        #expect(throws: ZoteroPDFImportError.invalidResponse) { try source(serverID: " ", library: .user) }
    }

    @Test("Ephemeral local-copy observations validate the observed namespace and metadata", arguments: [0, 1, 2, 3, 4])
    func rejectsMalformedLocalObservation(variant: Int) {
        #expect(throws: ZoteroPDFImportError.invalidResponse) {
            try ZoteroPDFLocalCopyObservation(
                library: ZoteroLibraryMetadata(identity: .group(42), name: "Fixture Group"),
                observedLibraryID: variant == 0 ? 43 : 42,
                item: ZoteroItemMetadata(key: "PARENT01", itemType: "book", title: "Fixture Book"),
                parentVersion: variant == 1 ? -1 : 0,
                parentMetadataFingerprint: variant == 2 ? DocumentFingerprint(content: "") : DocumentFingerprint(content: "parent metadata"),
                attachmentKey: variant == 3 ? "../unsafe" : "PDF00001", attachmentVersion: 0,
                attachmentMetadataFingerprint: DocumentFingerprint(content: "attachment metadata"),
                title: "Fixture PDF", filename: variant == 4 ? "../Fixture.pdf" : "Fixture.pdf", linkMode: .importedFile)
        }
    }

    @Test("Only exact child and local file-URL routes extend the read policy")
    func narrowRequestPolicy() throws {
        let children = try #require(ZoteroLocalRequestPolicy.makeReadRequest(library: .group(42), path: "items/PARENT01/children"))
        let file = try #require(ZoteroLocalRequestPolicy.makeReadRequest(library: .group(42), path: "items/PDF00001/file/view/url"))
        #expect(children.url?.path == "/api/groups/42/items/PARENT01/children")
        #expect(file.value(forHTTPHeaderField: "Accept") == "text/plain")
        #expect(file.httpMethod == "GET" && file.httpBody == nil)
        for path in [
            "items/PDF00001/file", "items/PDF00001/file/view", "items/PDF00001/children/../file/view/url", "items/../children", "items/PDF00001/file/upload",
        ] {
            #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: path) == nil)
        }
    }

    private func source(serverID: String, library: ZoteroLibraryIdentity) throws -> ZoteroPDFSource {
        try ZoteroPDFSource(
            library: ZoteroLibraryMetadata(identity: library, name: "Fixture Library"),
            item: ZoteroItemMetadata(key: "PARENT01", itemType: "book", title: "Fixture Book"),
            attachmentKey: "PDF00001", attachmentVersion: 12, title: "Fixture PDF", filename: "Fixture.pdf",
            linkMode: .importedFile, serverID: serverID, attachmentMetadataFingerprint: DocumentFingerprint(content: "fixture metadata"))
    }
}
