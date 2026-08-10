import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApp

@Suite("Zotero presentation bridge")
struct ZoteroBridgeTests {
    @Test("Exact item navigation preserves user and group library identity")
    func exactItemNavigationURL() throws {
        let user = try AnalysisZoteroBinding(
            noteID: UUID(),
            library: .user,
            itemKey: "abc-1_x"
        )
        #expect(
            ZoteroBridge.itemURL(binding: user)?.absoluteString
                == "zotero://select/library/items/ABC-1_X"
        )
        let group = try AnalysisZoteroBinding(
            noteID: UUID(),
            library: .group(42),
            itemKey: "item_2"
        )
        #expect(
            ZoteroBridge.itemURL(binding: group)?.absoluteString
                == "zotero://select/groups/42/items/ITEM_2"
        )
    }
}
