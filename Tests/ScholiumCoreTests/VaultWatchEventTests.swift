import Testing
import ScholiumContracts
@testable import ScholiumCore

@Suite("Vault watch event reconciliation")
struct VaultWatchEventTests {
    @Test("Initial-open events remain complete until reconciliation")
    func initialOpenJournalPreservesEvents() {
        var journal = VaultWatchEventJournal(capacity: 8)
        journal.append(event(added: ["A.md"], sequence: 10))
        journal.append(event(modified: ["B.md"], sequence: 11))
        journal.append(event(deleted: ["C.md"], sequence: 12))

        let drained = journal.drain()
        #expect(drained?.added == ["A.md"])
        #expect(drained?.modified == ["B.md"])
        #expect(drained?.deleted == ["C.md"])
        #expect(drained?.sequence == 12)
        #expect(drained?.requiresFullRescan == false)
        #expect(journal.events.isEmpty)
        #expect(journal.drain() == nil)
    }

    @Test("Overflow and event-ID reset require a bounded full reconciliation")
    func overflowAndResetRequireFullReconciliation() {
        var overflow = VaultWatchEventJournal(capacity: 2)
        overflow.append(event(added: ["A.md"], sequence: 20))
        overflow.append(event(modified: ["B.md"], sequence: 21))
        overflow.append(event(deleted: ["C.md"], sequence: 22))

        #expect(overflow.overflowed)
        #expect(overflow.drain()?.requiresFullRescan == true)

        var reset = VaultWatchEventJournal(capacity: 4)
        reset.append(event(modified: ["A.md"], sequence: 100))
        reset.append(event(modified: ["A.md"], sequence: 4))
        let resetEvent = reset.drain()
        #expect(resetEvent?.requiresFullRescan == true)
        #expect(resetEvent?.sequence == 100)
    }

    @Test("Root changes survive coalescing and require recovery")
    func rootChangeSurvivesCoalescing() {
        var journal = VaultWatchEventJournal()
        journal.append(VaultWatchEvent(
            added: [],
            modified: [],
            deleted: [],
            sequence: 42,
            requiresFullRescan: true,
            rootChanged: true
        ))

        let drained = journal.drain()
        #expect(drained?.rootChanged == true)
        #expect(drained?.requiresFullRescan == true)
    }

    private func event(
        added: [String] = [],
        modified: [String] = [],
        deleted: [String] = [],
        sequence: UInt64
    ) -> VaultWatchEvent {
        VaultWatchEvent(
            added: added,
            modified: modified,
            deleted: deleted,
            sequence: sequence,
            requiresFullRescan: false,
            rootChanged: false
        )
    }
}
