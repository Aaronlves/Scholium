import Foundation
import Testing
@testable import ScholiumCore

@Suite("Read-only Zotero metadata matching")
struct ZoteroMetadataTests {
    @Test("A supplied item key is authoritative and never falls through to another item")
    func exactItemKeyPrecedesFallbacks() {
        let source = ZoteroSourceIdentity(
            itemKey: "match001",
            doi: "10.1000/shared",
            title: "Shared Title",
            authors: ["Researcher"],
            year: 2026
        )
        let exact = item(key: "MATCH001", title: "Exact Item")
        let sameDOI = item(key: "OTHER001", title: "Other Item", doi: "10.1000/shared")

        switch ZoteroMetadataMatcher.match(source: source, candidates: [sameDOI, exact]) {
        case .matched(let match, let basis):
            #expect(match.key == "MATCH001")
            #expect(basis == .itemKey)
        default:
            Issue.record("Expected the exact Zotero item key to win.")
        }

        switch ZoteroMetadataMatcher.match(source: source, candidates: [sameDOI]) {
        case .notFound: break
        default: Issue.record("A missing supplied item key must not silently fall back.")
        }
    }

    @Test("DOI and ISBN matching normalize stable identifier spellings")
    func stableIdentifiers() {
        let doiSource = ZoteroSourceIdentity(doi: "https://doi.org/10.1000/ABC")
        let doiItem = item(key: "DOI00001", title: "DOI", doi: "doi:10.1000/abc")
        assertUnique(doiSource, [doiItem], key: "DOI00001", basis: .doiOrISBN)

        let isbnSource = ZoteroSourceIdentity(isbn: "978-0-521-34792-1")
        let isbnItem = item(key: "ISBN0001", title: "ISBN", isbn: "978 0 521 34792 1")
        assertUnique(isbnSource, [isbnItem], key: "ISBN0001", basis: .doiOrISBN)
    }

    @Test("A non-unique identifier is surfaced as ambiguity")
    func identifierAmbiguity() {
        let source = ZoteroSourceIdentity(doi: "10.1000/duplicate")
        let candidates = [
            item(key: "SECOND02", title: "Second", doi: "10.1000/duplicate"),
            item(key: "FIRST001", title: "First", doi: "10.1000/duplicate"),
        ]
        switch ZoteroMetadataMatcher.match(source: source, candidates: candidates) {
        case .ambiguous(let matches, let basis):
            #expect(matches.map(\.key) == ["FIRST001", "SECOND02"])
            #expect(basis == .doiOrISBN)
        default:
            Issue.record("Duplicate identifiers must never select an arbitrary item.")
        }
    }

    @Test("Citation key is used after DOI or ISBN")
    func citationKeyFallback() {
        let source = ZoteroSourceIdentity(citationKey: "FootAbortion1967")
        let candidate = item(
            key: "CITE0001",
            title: "A Citation",
            citationKey: "footabortion1967"
        )
        assertUnique(source, [candidate], key: "CITE0001", basis: .citationKey)
    }

    @Test("Exact title, author, and year accepts canonical author ordering")
    func titleAuthorYearFallback() {
        let source = ZoteroSourceIdentity(
            title: "The Problem of Abortion",
            authors: ["Foot, Philippa"],
            year: 1967
        )
        let candidate = item(
            key: "FOOT1967",
            title: "The Problem of Abortion",
            authors: ["Philippa Foot"],
            year: 1967
        )
        assertUnique(source, [candidate], key: "FOOT1967", basis: .titleAuthorYear)
    }

    @Test("Title fallback stays ambiguous and incomplete metadata stays explicit")
    func titleAmbiguityAndInsufficientMetadata() {
        let source = ZoteroSourceIdentity(title: "Same", authors: ["A. Author"], year: 2020)
        let candidates = [
            item(key: "SAME0001", title: "Same", authors: ["A. Author"], year: 2020),
            item(key: "SAME0002", title: "Same", authors: ["A. Author"], year: 2020),
        ]
        switch ZoteroMetadataMatcher.match(source: source, candidates: candidates) {
        case .ambiguous(let matches, let basis):
            #expect(matches.count == 2)
            #expect(basis == .titleAuthorYear)
        default:
            Issue.record("Duplicate title/author/year matches must remain ambiguous.")
        }

        switch ZoteroMetadataMatcher.match(
            source: ZoteroSourceIdentity(title: "Title Only"),
            candidates: candidates
        ) {
        case .insufficientMetadata: break
        default: Issue.record("Title alone is not a sufficient Zotero identity.")
        }
    }

    @Test("Zotero JSON decoding preserves compact and expanded bibliographic metadata")
    func metadataDecoding() throws {
        let json = #"""
        {
          "key": "META0001",
          "data": {
            "key": "META0001",
            "itemType": "journalArticle",
            "title": "Fittingness",
            "creators": [
              {"creatorType":"author","firstName":"Richard","lastName":"Chappell"},
              {"creatorType":"editor","firstName":"Ignored","lastName":"Editor"}
            ],
            "date": "2012",
            "publicationTitle": "The Philosophical Quarterly",
            "volume": "62",
            "issue": "249",
            "pages": "684-704",
            "DOI": "10.1111/example",
            "ISBN": "978-1-2345-6789-0",
            "citationKey": "ChappellFittingness2012",
            "abstractNote": "A source abstract.",
            "publisher": "Example Press",
            "edition": "2",
            "url": "https://example.test/item",
            "collections": ["COLL0001"],
            "dateModified": "2026-07-12T10:30:00Z"
          }
        }
        """#
        let result = try #require(ZoteroMetadataDecoder.decodeItems(from: Data(json.utf8)).first)
        #expect(result.key == "META0001")
        #expect(result.authors == ["Richard Chappell"])
        #expect(result.year == 2012)
        #expect(result.containerTitle == "The Philosophical Quarterly")
        #expect(result.volume == "62")
        #expect(result.issue == "249")
        #expect(result.pages == "684-704")
        #expect(result.doi == "10.1111/example")
        #expect(result.isbn == "978-1-2345-6789-0")
        #expect(result.citationKey == "ChappellFittingness2012")
        #expect(result.abstract == "A source abstract.")
        #expect(result.publisher == "Example Press")
        #expect(result.edition == "2")
        #expect(result.url == "https://example.test/item")
        #expect(result.collectionKeys == ["COLL0001"])
        #expect(result.dateModified != nil)
    }

    @Test("Legacy citation key in Extra and exact collection names remain readable")
    func compatibilityMetadataDecoding() throws {
        let itemJSON = #"""
        {"data":{"key":"EXTRA001","itemType":"book","title":"Book","extra":"Citation Key: LegacyKey"}}
        """#
        let collectionJSON = "{\"data\":{\"key\":\"COLL0001\",\"name\":\"Core Sources\"}}"
        #expect(try ZoteroMetadataDecoder.decodeItems(from: Data(itemJSON.utf8)).first?.citationKey == "LegacyKey")
        #expect(try ZoteroMetadataDecoder.decodeCollectionName(from: Data(collectionJSON.utf8)) == "Core Sources")
    }

    @Test("The transport policy permits only bodyless loopback GET reads")
    func readOnlyRequestPolicy() throws {
        let request = try #require(ZoteroLocalRequestPolicy.makeReadRequest(
            path: "items",
            query: [
                URLQueryItem(name: "q", value: "10.1000/example"),
                URLQueryItem(name: "qmode", value: "everything"),
                URLQueryItem(name: "limit", value: "50"),
            ]
        ))
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.url?.scheme == "http")
        #expect(request.url?.host == "127.0.0.1")
        #expect(request.url?.port == 23119)
        #expect(request.url?.path == "/api/users/0/items")
        #expect(request.value(forHTTPHeaderField: "Zotero-API-Version") == "3")

        let itemRequest = try #require(
            ZoteroLocalRequestPolicy.makeReadRequest(path: "items/FXS00026")
        )
        #expect(itemRequest.url?.path == "/api/users/0/items/FXS00026")
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "collections/COLL0001") != nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "items/FXS00026/children") == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "attachments/FXS00026") == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(path: "../items") == nil)
        #expect(ZoteroLocalRequestPolicy.makeReadRequest(
            path: "items",
            query: [URLQueryItem(name: "include", value: "bib")]
        ) == nil)
    }

    private func assertUnique(
        _ source: ZoteroSourceIdentity,
        _ candidates: [ZoteroItemMetadata],
        key: String,
        basis: ZoteroMatchBasis,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        switch ZoteroMetadataMatcher.match(source: source, candidates: candidates) {
        case .matched(let match, let actualBasis):
            #expect(match.key == key, sourceLocation: sourceLocation)
            #expect(actualBasis == basis, sourceLocation: sourceLocation)
        default:
            Issue.record("Expected one deterministic Zotero match.", sourceLocation: sourceLocation)
        }
    }

    private func item(
        key: String,
        title: String,
        authors: [String] = [],
        year: Int? = nil,
        doi: String? = nil,
        isbn: String? = nil,
        citationKey: String? = nil
    ) -> ZoteroItemMetadata {
        ZoteroItemMetadata(
            key: key,
            title: title,
            authors: authors,
            year: year,
            doi: doi,
            isbn: isbn,
            citationKey: citationKey
        )
    }
}
