import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Settlement store", .serialized)
struct SettlementStoreTests {
    @Test("Settle replaces one note judgment and survives restart")
    func replacementAndRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let noteID = UUID()
        let firstRevision = DocumentFingerprint(content: "first")
        let secondRevision = DocumentFingerprint(content: "second")

        _ = try await store.settle(
            noteID: noteID,
            fingerprint: firstRevision,
            rationale: "Initial judgment"
        )
        let replacement = try await store.settle(
            noteID: noteID,
            fingerprint: secondRevision,
            rationale: "Reconsidered"
        )
        #expect(replacement.fingerprint == secondRevision)
        let reopened = try fixture.store()
        let listing = try await reopened.listing()
        #expect(listing.issues.isEmpty)
        #expect(listing.settlements.count == 1)
        #expect(listing.settlements.first?.fingerprint == secondRevision)
        #expect(try await reopened.latest(noteID: noteID)?.id == replacement.id)
    }

    @Test("Unknown fields fail closed without rewriting portable data")
    func unknownFieldFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.dispose() }
        let store = try fixture.store()
        let noteID = UUID()
        _ = try await store.settle(
            noteID: noteID,
            fingerprint: DocumentFingerprint(content: "source"),
            rationale: nil
        )
        let url = fixture.settlementURL(noteID)
        let original = try Data(contentsOf: url)
        var object = try #require(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        object["unsupported"] = true
        let damaged = try JSONSerialization.data(withJSONObject: object)
        try damaged.write(to: url, options: .atomic)

        let listing = try await store.listing()
        #expect(listing.settlements.isEmpty)
        #expect(listing.issues.count == 1)
        #expect(try Data(contentsOf: url) == damaged)
    }

    private struct Fixture {
        let root: URL
        let controlURL: URL
        let supportURL: URL
        let triptychID = UUID()

        init() throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            root = repositoryRoot
                .appendingPathComponent(".build/core-unit-state", isDirectory: true)
                .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
            controlURL = root.appendingPathComponent(".scholium", isDirectory: true)
            supportURL = root.appendingPathComponent("support", isDirectory: true)
            try FileManager.default.createDirectory(
                at: controlURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: supportURL,
                withIntermediateDirectories: true
            )
        }

        func store() throws -> SettlementStore {
            try SettlementStore(
                controlURL: controlURL,
                applicationSupportURL: supportURL,
                triptychID: triptychID
            )
        }

        func settlementURL(_ noteID: UUID) -> URL {
            controlURL
                .appendingPathComponent("research-records/v1/settlements")
                .appendingPathComponent("\(noteID.uuidString.lowercased()).json")
        }

        func dispose() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
