import ScholiumContracts
import Testing

struct AgentChatTranscriptMessageIDsTests {
    @Test("Every coverage mode includes the plan identity without inventing item identities")
    func coverageModes() {
        let emptyModes: [AgentChatTranscript.Turn.Items] = [.full([]), .references([]), .notLoaded]
        for content in emptyModes {
            let turn = AgentChatTranscript.Turn(id: "turn", status: .completed, items: content)
            #expect(turn.messageIDs == ["plan:turn"])
            expectFrozenExpression(turn)
        }

        let references: Set<String> = ["reference", "runtime:already-prefixed", "client"]
        let originalBytes = byteRepresentatives(references)
        let turn = AgentChatTranscript.Turn(id: "turn", status: .completed, items: .references(references))
        #expect(turn.messageIDs == ["reference", "runtime:already-prefixed", "client", "plan:turn"])
        expectFrozenExpression(turn)
        #expect(byteRepresentatives(references) == originalBytes)
    }

    @Test("Full items preserve client identities, empty client values and namespace collisions")
    func fullItemIdentities() {
        let items = [
            item("first"),
            item("second", client: "client"),
            item("first", client: "first"),
            item("runtime:first", client: ""),
        ]
        let turn = AgentChatTranscript.Turn(id: "turn", status: .completed, items: .full(items))
        #expect(
            turn.messageIDs == [
                "first", "runtime:first", "second", "runtime:second", "client",
                "runtime:runtime:first", "", "plan:turn",
            ])
        expectFrozenExpression(turn)
    }

    @Test("Canonical duplicates retain the original expression's exact Unicode representatives", arguments: [false, true])
    func exactUnicodeRepresentatives(decomposedFirst: Bool) throws {
        let first = decomposedFirst ? "e\u{301}" : "é"
        let later = decomposedFirst ? "é" : "e\u{301}"
        try #require(first == later)
        try #require(!first.utf8.elementsEqual(later.utf8))

        // The initial item wins its ID and runtime-ID collisions. The client
        // plan identity precedes the getter's final generated plan identity.
        let full = AgentChatTranscript.Turn(
            id: first, status: .completed,
            items: .full([
                item(first, client: later),
                item("runtime:\(later)", client: "runtime:\(later)"),
                item(later, client: "plan:\(later)"),
            ]))
        #expect(
            byteRepresentatives(full.messageIDs)
                == byteRepresentatives([first, "runtime:\(first)", "runtime:runtime:\(later)", "plan:\(later)"]))
        expectFrozenExpression(full)

        let references: Set<String> = ["reference", "plan:\(later)"]
        let referencesBefore = byteRepresentatives(references)
        let referenced = AgentChatTranscript.Turn(id: first, status: .completed, items: .references(references))
        #expect(byteRepresentatives(referenced.messageIDs) == referencesBefore)
        expectFrozenExpression(referenced)
        #expect(byteRepresentatives(references) == referencesBefore)

        let unloaded = AgentChatTranscript.Turn(id: first, status: .completed, items: .notLoaded)
        #expect(byteRepresentatives(unloaded.messageIDs) == byteRepresentatives(["plan:\(first)"]))
        expectFrozenExpression(unloaded)
    }

    private func item(_ id: String, client: String? = nil) -> AgentChatTranscript.Item {
        .init(id: id, content: .user(text: "Synthetic public input", hasAdditionalMaterial: false), clientMessageID: client)
    }

    private func expectFrozenExpression(_ turn: AgentChatTranscript.Turn) {
        let expected = originalExpression(turn)
        let actual = turn.messageIDs
        #expect(actual == expected)
        // Set<String> equality alone accepts different NFC/NFD representatives.
        #expect(byteRepresentatives(actual) == byteRepresentatives(expected))
    }

    private func byteRepresentatives(_ ids: Set<String>) -> Set<[UInt8]> {
        Set(ids.map { Array($0.utf8) })
    }

    /// Freeze the previous getter independently of the production construction.
    private func originalExpression(_ turn: AgentChatTranscript.Turn) -> Set<String> {
        let ids: Set<String>
        switch turn.itemContent {
        case .full(let items):
            ids = Set(items.flatMap { [$0.id, "runtime:\($0.id)"] + ($0.clientMessageID.map { [$0] } ?? []) })
        case .references(let references): ids = references
        case .notLoaded: ids = []
        }
        return ids.union(["plan:\(turn.id)"])
    }
}
