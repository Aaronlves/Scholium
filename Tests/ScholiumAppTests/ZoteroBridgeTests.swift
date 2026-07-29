import Foundation
import Testing
@testable import ScholiumApp

@Suite("Zotero presentation bridge")
struct ZoteroBridgeTests {
    @Test("Exact item navigation normalizes only bounded Zotero keys")
    func exactItemNavigationURL() {
        #expect(
            ZoteroBridge.itemURL(zoteroKey: "  abc-1_x  ")?.absoluteString
                == "zotero://select/library/items/ABC-1_X"
        )
        #expect(ZoteroBridge.itemURL(zoteroKey: nil) == nil)
        #expect(ZoteroBridge.itemURL(zoteroKey: "   ") == nil)
        #expect(ZoteroBridge.itemURL(zoteroKey: "item/child") == nil)
        #expect(ZoteroBridge.itemURL(zoteroKey: String(repeating: "A", count: 65)) == nil)
    }
}
