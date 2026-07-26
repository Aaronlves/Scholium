import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumCore

@Suite("Machine-local Research Permission policy store", .serialized)
struct ResearchPermissionPolicyStoreTests {
    @Test("A missing store is Ask Every Time without creating vault or machine state")
    func missingStoreUsesQuietDefault() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let snapshot = try await fixture.store.snapshot()
        #expect(snapshot.document.triptychDefault == .askEveryTime)
        #expect(snapshot.document.skillOverrides.isEmpty)
        #expect(snapshot.revision == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.storage.path))
    }

    @Test("Triptych and per-Skill policies reopen with private atomic storage")
    func saveAndReopen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try await fixture.store.saveTriptychDefault(
            .askOnlyForWorks,
            expectedRevision: nil
        )
        let subject = try fixture.subject()
        let second = try await fixture.store.saveOverride(
            packageID: subject.packageID,
            policy: .triptychWide,
            approvedEnvelopeDigest: subject.envelopeDigest,
            expectedRevision: first.revision
        )

        let reopened = try await fixture.reopenedStore.snapshot()
        #expect(reopened == second)
        #expect(reopened.document.triptychDefault == .askOnlyForWorks)
        #expect(reopened.document.override(for: subject.packageID)?.policy
            == .triptychWide)
        #expect(reopened.document.override(for: subject.packageID)?
            .approvedEnvelopeDigest == subject.envelopeDigest)

        for url in [fixture.policyURL, fixture.lockURL] {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fixture.storage.path
        )
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue
            == 0o700)
    }

    @Test("Independent window-facing store instances observe one policy revision")
    func independentInstancesConverge() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstStore = fixture.store
        let secondStore = fixture.reopenedStore
        let first = try await firstStore.saveTriptychDefault(
            .triptychWide,
            expectedRevision: nil
        )
        #expect(try await secondStore.snapshot() == first)

        let subject = try fixture.subject()
        let second = try await secondStore.saveOverride(
            packageID: subject.packageID,
            policy: .askEveryTime,
            approvedEnvelopeDigest: subject.envelopeDigest,
            expectedRevision: first.revision
        )
        #expect(try await firstStore.snapshot() == second)
    }

    @Test("Stale writes cannot replace a newer policy")
    func staleRevisionFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = try await fixture.store.saveTriptychDefault(
            .askOnlyForWorks,
            expectedRevision: nil
        )
        let second = try await fixture.store.saveTriptychDefault(
            .triptychWide,
            expectedRevision: first.revision
        )

        await #expect(throws: ResearchPermissionPolicyStoreError.staleRevision) {
            _ = try await fixture.reopenedStore.saveTriptychDefault(
                .askEveryTime,
                expectedRevision: first.revision
            )
        }
        #expect(try await fixture.store.snapshot() == second)
    }

    @Test("Concurrent store instances serialize one expected revision")
    func concurrentInstancesSerialize() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let firstStore = fixture.store
        let secondStore = fixture.reopenedStore

        async let first = saveSucceeds(
            store: firstStore,
            policy: .askOnlyForWorks
        )
        async let second = saveSucceeds(
            store: secondStore,
            policy: .triptychWide
        )
        let results = await [first, second]
        #expect(results.filter { $0 }.count == 1)
        #expect(try await fixture.store.snapshot().revision != nil)
    }

    @Test("Removing an override restores inheritance without changing the default")
    func removeOverride() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let base = try await fixture.store.saveTriptychDefault(
            .triptychWide,
            expectedRevision: nil
        )
        let subject = try fixture.subject()
        let overridden = try await fixture.store.saveOverride(
            packageID: subject.packageID,
            policy: .askEveryTime,
            approvedEnvelopeDigest: subject.envelopeDigest,
            expectedRevision: base.revision
        )
        let removed = try await fixture.store.removeOverride(
            packageID: subject.packageID,
            expectedRevision: overridden.revision
        )
        #expect(removed.document.triptychDefault == .triptychWide)
        #expect(removed.document.skillOverrides.isEmpty)
    }

    @Test("Cross-Triptych, malformed, linked, and over-permissive policy files fail closed")
    func unsafeOrCorruptStateFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try await fixture.store.saveTriptychDefault(
            .triptychWide,
            expectedRevision: nil
        )
        let validBytes = try Data(contentsOf: fixture.policyURL)

        var object = try #require(
            JSONSerialization.jsonObject(with: validBytes) as? [String: Any]
        )
        object["triptych_id"] = UUID().uuidString
        let crossTriptych = try JSONSerialization.data(withJSONObject: object)
        try crossTriptych.write(to: fixture.policyURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: fixture.policyURL.path
        )
        await #expect(throws: ResearchPermissionPolicyStoreError.corruptStore) {
            _ = try await fixture.reopenedStore.snapshot()
        }
        #expect(try Data(contentsOf: fixture.policyURL) == crossTriptych)

        try validBytes.write(to: fixture.policyURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: fixture.policyURL.path
        )
        await #expect(throws: ResearchPermissionPolicyStoreError.corruptStore) {
            _ = try await fixture.reopenedStore.snapshot()
        }

        try FileManager.default.removeItem(at: fixture.policyURL)
        let external = fixture.root.appendingPathComponent("external.json")
        try validBytes.write(to: external, options: .atomic)
        try FileManager.default.createSymbolicLink(
            at: fixture.policyURL,
            withDestinationURL: external
        )
        await #expect(throws: ResearchPermissionPolicyStoreError.corruptStore) {
            _ = try await fixture.reopenedStore.snapshot()
        }
        #expect(try Data(contentsOf: external) == validBytes)
    }

    private struct Fixture {
        let root: URL
        let storage: URL
        let triptychID = UUID()

        init() throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            root = repositoryRoot
                .appendingPathComponent(".build/test-fixtures", isDirectory: true)
                .appendingPathComponent(
                    "ResearchPermissionPolicyStore-\(UUID().uuidString)",
                    isDirectory: true
                )
            storage = root.appendingPathComponent("Standing", isDirectory: true)
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        var store: ResearchPermissionPolicyStore {
            ResearchPermissionPolicyStore(storageURL: storage, triptychID: triptychID)
        }

        var reopenedStore: ResearchPermissionPolicyStore {
            ResearchPermissionPolicyStore(storageURL: storage, triptychID: triptychID)
        }

        var policyURL: URL {
            storage.appendingPathComponent("standing-permissions-v1.json")
        }

        var lockURL: URL {
            storage.appendingPathComponent(".standing-permissions-v1.lock")
        }

        func subject() throws -> ResearchPermissionSubject {
            try ResearchPermissionSubject(
                packageID: "bounded-method",
                displayName: "Bounded Method",
                packageRevision: DocumentFingerprint(content: "skill"),
                profiles: [try ResearchPermissionProfileRevision(
                    actionID: .write,
                    targetRole: .work,
                    profileRevision: DocumentFingerprint(content: "profile")
                )]
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func saveSucceeds(
        store: ResearchPermissionPolicyStore,
        policy: ResearchPermissionPolicy
    ) async -> Bool {
        do {
            _ = try await store.saveTriptychDefault(
                policy,
                expectedRevision: nil
            )
            return true
        } catch ResearchPermissionPolicyStoreError.staleRevision {
            return false
        } catch {
            Issue.record("Unexpected concurrent policy-store error: \(error)")
            return false
        }
    }
}
