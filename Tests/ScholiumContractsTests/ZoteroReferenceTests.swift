import Foundation
import ScholiumContracts
import Testing

@Suite("Library-qualified Zotero references")
struct ZoteroReferenceTests {
    @Test("Item, physical PDF page and annotation references retain their exact identities")
    func referenceRoundTrips() throws {
        let references = [
            try ZoteroReference(library: .user, itemKey: " item_1 "),
            try ZoteroReference(library: .group(42), itemKey: "ITEM_1"),
            try ZoteroReference(library: .user, kind: .pdf, itemKey: "ATTACH01", page: 12),
            try ZoteroReference(library: .group(42), kind: .pdf, itemKey: "ATTACH01", page: 3, annotationKey: "anno0001"),
            try ZoteroReference(library: .user, kind: .pdf, itemKey: "ATTACH01", annotationKey: "ANNO0001"),
        ]
        for reference in references {
            #expect(try ZoteroReference(url: reference.url) == reference)
            #expect(try JSONDecoder().decode(ZoteroReference.self, from: JSONEncoder().encode(reference)) == reference)
        }
        #expect(references[3].url.absoluteString == "zotero://open-pdf/groups/42/items/ATTACH01?page=3&annotation=ANNO0001")
        #expect(references[4].url.absoluteString == "zotero://open-pdf/library/items/ATTACH01?annotation=ANNO0001")
        #expect(references[0] != references[1])
    }

    @Test("Invalid locators cannot silently lose scope or downgrade to item selection")
    func rejectsInvalidLocators() throws {
        for raw in [
            "https://select/library/items/ITEM0001", "zotero://debug/",
            "zotero://select/groups/0/items/ITEM0001", "zotero://select/groups/-1/items/ITEM0001",
            "zotero://select/library/items/ITEM0001?page=1", "zotero://select/library/items/ITEM0001?annotation=ANNO0001",
            "zotero://open-pdf/library/items/ITEM0001?page=0", "zotero://open-pdf/library/items/ITEM0001?page=1.5",
            "zotero://open-pdf/library/items/ITEM0001?page=1&page=2", "zotero://open-pdf/library/items/ITEM0001?annotation=A&annotation=B",
            "zotero://open-pdf/library/items/ITEM0001?annotation=", "zotero://open-pdf/library/items/ITEM0001?file=/private/file",
            "zotero://open-pdf/library/items/ITEM0001?page=99999999999999999999999999999999",
            "zotero://select/library/items/ITEM0001/", "zotero://select/library/items/A%2FB",
            "zotero://select/library/items/%20ITEM0001", "zotero://select/library/items/..",
            "zotero://user@select/library/items/ITEM0001", "zotero://select:23119/library/items/ITEM0001",
            "zotero://select/library/items/ITEM0001#other",
        ] {
            let url = try #require(URL(string: raw))
            #expect(throws: ZoteroReference.InvalidReference.self) { try ZoteroReference(url: url) }
        }
    }

    @Test("Decoding cannot bypass the positive page and target invariants")
    func decodingIsValidated() throws {
        let reference = try ZoteroReference(library: .user, kind: .pdf, itemKey: "ATTACH01", page: 1)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(reference)) as? [String: Any])
        object["page"] = 0
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ZoteroReference.self, from: JSONSerialization.data(withJSONObject: object)) }
        object["page"] = 1
        object["kind"] = "item"
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ZoteroReference.self, from: JSONSerialization.data(withJSONObject: object)) }
        #expect(throws: ZoteroReference.InvalidReference.self) { try ZoteroReference(library: .group(-1), itemKey: "A") }
    }
}
