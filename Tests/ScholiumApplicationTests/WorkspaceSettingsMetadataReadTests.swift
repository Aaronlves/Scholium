import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Settings metadata reads", .serialized)
struct WorkspaceSettingsMetadataReadTests {
    @Test("An unopened registration reads Settings without activating source owners", arguments: [false, true])
    func unopenedDoesNotActivateWorkspace(live: Bool) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime =
            live
            ? WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: fixture.applicationSupportURL,
                        workspaceRegistryStorageURL: fixture.registryStorageURL))) : settingsMetadataRuntime(fixture)
        do {
            let before = try settingsMetadataTree(fixture.rootURL)
            let settings = try await runtime.portableSettingsRecoverySnapshot(
                triptychID: fixture.assignment.id, expectedAssignment: fixture.assignment)
            let bytes = try Data(contentsOf: fixture.rootURL.appendingPathComponent(".scholium/settings.json"))
            #expect(
                settings.loadState
                    == .current(
                        .init(
                            settings: TriptychSettings(), revision: .init(fingerprint: .init(data: bytes)))))
            #expect(try settingsMetadataTree(fixture.rootURL) == before)
            #expect(await runtime.pooledVaultRuntimeCount == 0)
            #if DEBUG
                #expect(await runtime.openingFactoryCountForTesting == 0)
                #expect(await runtime.openingLookupCountForTesting == 0)
            #endif
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test(
        "A stale same-ID expected assignment is rejected before borrowing portable authority",
        arguments: [false, true])
    func expectedAssignmentPinsTheComposedSnapshot(borrowed: Bool) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = settingsMetadataRuntime(fixture)
        do {
            if borrowed { _ = try await runtime.workspace(id: fixture.assignment.id) }
            var staleTriptych = fixture.assignment.triptych
            staleTriptych.name += " — prior registration"
            let stale = TriptychAssignment(
                triptych: staleTriptych, vaults: fixture.assignment.vaults,
                hasCommonParent: fixture.assignment.hasCommonParent)
            if !borrowed {
                // If Core admission runs first this would report invalidManifest,
                // not the expected cohort cancellation.
                try Data("{ damaged manifest".utf8).write(
                    to: fixture.rootURL.appendingPathComponent(".scholium/manifest.json"))
            }
            let before = try settingsMetadataTree(fixture.rootURL)
            await #expect(throws: CancellationError.self) {
                _ = try await runtime.portableSettingsRecoverySnapshot(
                    triptychID: fixture.assignment.id, expectedAssignment: stale)
            }
            #expect(try settingsMetadataTree(fixture.rootURL) == before)
            #expect(await runtime.pooledVaultRuntimeCount == (borrowed ? 3 : 0))
            #if DEBUG
                #expect(await runtime.settingsReadCountForTesting == 0)
                #expect(await runtime.openingFactoryCountForTesting == (borrowed ? 1 : 0))
            #endif
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test("A borrowed activation remains the same owner and returns the same revision")
    func borrowedOwnerIsPreserved() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = settingsMetadataRuntime(fixture)
        do {
            let handle = try await runtime.workspace(id: fixture.assignment.id)
            let expected = try await handle.research.settingsRecoverySnapshot()
            let before = try settingsMetadataTree(fixture.rootURL)
            #expect(
                try await runtime.portableSettingsRecoverySnapshot(
                    triptychID: fixture.assignment.id, expectedAssignment: fixture.assignment) == expected)
            #expect(try await runtime.workspace(id: fixture.assignment.id) === handle)
            #expect(try settingsMetadataTree(fixture.rootURL) == before)
            #expect(await runtime.pooledVaultRuntimeCount == 3)
            #if DEBUG
                #expect(await runtime.openingFactoryCountForTesting == 1)
            #endif
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test(
        "Current, opaque-current, missing, old, future and corrupt Settings remain exact and read-only",
        arguments: ["missing", "current", "current_opaque", "old", "future", "corrupted"])
    func distinctSettingsStates(state: String) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let url = fixture.rootURL.appendingPathComponent(".scholium/settings.json")
        let expectedState: TriptychSettingsLoadState
        switch state {
        case "missing":
            try FileManager.default.removeItem(at: url)
            expectedState = .missing
        case "old":
            try Data(#"{"schemaVersion":5}"#.utf8).write(to: url)
            expectedState = .oldSchema(5)
        case "future":
            try Data(#"{"schemaVersion":999}"#.utf8).write(to: url)
            expectedState = .futureSchema(999)
        case "corrupted":
            try Data("{ damaged".utf8).write(to: url)
            expectedState = .corrupted
        default:
            if state == "current_opaque" {
                try Data(#"{"schemaVersion":10,"unknown":{"preserve":"exact"}}"#.utf8).write(to: url)
            }
            let bytes = try Data(contentsOf: url)
            expectedState = .current(.init(settings: TriptychSettings(), revision: .init(fingerprint: .init(data: bytes))))
        }
        let original = state == "missing" ? nil : try Data(contentsOf: url)
        let runtime = settingsMetadataRuntime(fixture)
        do {
            let before = try settingsMetadataTree(fixture.rootURL)
            let observed = try await runtime.portableSettingsRecoverySnapshot(triptychID: fixture.assignment.id)
            #expect(observed.loadState == expectedState)
            #expect(observed.revision == original.map { .init(fingerprint: .init(data: $0)) })
            #expect(try settingsMetadataTree(fixture.rootURL) == before)
            #expect(await runtime.pooledVaultRuntimeCount == 0)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test(
        "Missing, mismatched and unsupported manifests never authorize a metadata read",
        arguments: ["missing", "damaged", "wrong_id", "wrong_mapping", "unsupported"])
    func manifestAdmission(state: String) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let url = fixture.rootURL.appendingPathComponent(".scholium/manifest.json")
        if state == "missing" {
            try FileManager.default.removeItem(at: url)
        } else if state == "damaged" {
            try Data("{ damaged manifest".utf8).write(to: url)
        } else if state == "wrong_mapping" {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var manifest = try decoder.decode(TriptychManifest.self, from: Data(contentsOf: url))
            manifest.vaultIDs[.output] = UUID()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(manifest).write(to: url)
        } else {
            var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            switch state {
            case "wrong_id": object["id"] = UUID().uuidString
            case "unsupported": object["schemaVersion"] = 999
            default: Issue.record("Unknown manifest test state")
            }
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
        }
        try await expectMetadataFailureWithoutWrites(fixture)
    }

    @Test(
        "Existing corrupt identities and catalog remain strict",
        arguments: ["identities", "catalog", "legacy_catalog"])
    func strictPortablePreflight(state: String) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let control = fixture.rootURL.appendingPathComponent(".scholium", isDirectory: true)
        switch state {
        case "identities": try Data("{ damaged identity".utf8).write(to: control.appendingPathComponent("identities.json"))
        case "legacy_catalog":
            try FileManager.default.createDirectory(at: control.appendingPathComponent("attachments/v1"), withIntermediateDirectories: true)
        default:
            try Data("{ damaged catalog".utf8).write(to: control.appendingPathComponent("attachments/v2/\(UUID().uuidString.lowercased()).json"))
        }
        try await expectMetadataFailureWithoutWrites(fixture)
    }

    @Test("Unsupported manifest fails before interpreting identity or attachment authority")
    func manifestFailurePrecedesOtherControlInterpretation() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let control = fixture.rootURL.appendingPathComponent(".scholium", isDirectory: true)
        let manifest = control.appendingPathComponent("manifest.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        object["schemaVersion"] = 999
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: manifest)
        try Data("{ damaged identity".utf8).write(to: control.appendingPathComponent("identities.json"))
        try FileManager.default.createDirectory(at: control.appendingPathComponent("attachments/v1"), withIntermediateDirectories: true)
        let runtime = settingsMetadataRuntime(fixture)
        do {
            let before = try settingsMetadataTree(fixture.rootURL)
            await #expect {
                _ = try await runtime.portableSettingsRecoverySnapshot(triptychID: fixture.assignment.id)
            } throws: { error in
                guard case ScholiumApplicationError.portableControlRecoveryRequired(_, let reason) = error else { return false }
                return reason == TriptychControlError.invalidManifest.localizedDescription
            }
            #expect(try settingsMetadataTree(fixture.rootURL) == before)
            #expect(await runtime.pooledVaultRuntimeCount == 0)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test(
        "Linked portable roots, files and catalog directories cannot redirect metadata reads",
        arguments: ["root", "manifest", "settings", "identities", "catalog", "catalog_leaf"])
    func linkedControlIsRejected(state: String) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let relative: String
        switch state {
        case "root": relative = ".scholium"
        case "catalog": relative = ".scholium/attachments/v2"
        case "catalog_leaf":
            relative = ".scholium/attachments/v2/\(UUID().uuidString.lowercased()).json"
            try Data("{}".utf8).write(to: fixture.rootURL.appendingPathComponent(relative))
        default: relative = ".scholium/\(state).json"
        }
        let original = fixture.rootURL.appendingPathComponent(relative)
        let target = fixture.rootURL.appendingPathComponent("synthetic-link-target-\(state)")
        try FileManager.default.moveItem(at: original, to: target)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: target)
        try await expectMetadataFailureWithoutWrites(fixture)
    }

    @Test(
        "Portable access uses the existing exact-container grant policy",
        arguments: ["missing", "wrong_container", "damaged_bookmark"])
    func portableGrantRejection(state: String) async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let works = try #require(fixture.assignment.vault(for: .output))
        let existing = try #require(fixture.assignment.triptych.portableControlAccess)
        let access: PortableControlAccess?
        switch state {
        case "missing": access = nil
        case "wrong_container": access = .init(canonicalContainerPath: fixture.analysesURL.path, bookmarkData: existing.bookmarkData)
        default: access = .init(canonicalContainerPath: existing.canonicalContainerPath, bookmarkData: Data("not a bookmark".utf8))
        }
        let before = try settingsMetadataTree(fixture.rootURL)
        #expect(throws: WorkspaceRegistryError.self) {
            _ = try WorkspaceHandle.resolvePortableControlAccess(worksVault: works, access: access)
        }
        #expect(try settingsMetadataTree(fixture.rootURL) == before)
    }

    @Test("Unknown membership and shutdown cannot authorize Settings reads")
    func lifetimeAndMembership() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = settingsMetadataRuntime(fixture)
        await #expect(throws: ScholiumApplicationError.self) {
            _ = try await runtime.portableSettingsRecoverySnapshot(triptychID: UUID())
        }
        await runtime.shutdown()
        await #expect(throws: ScholiumApplicationError.self) {
            _ = try await runtime.portableSettingsRecoverySnapshot(triptychID: fixture.assignment.id)
        }
        #expect(await runtime.pooledVaultRuntimeCount == 0)
    }

    @Test("A damaged registry never becomes empty or authorizes portable access")
    func registryFailureIsPreserved() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let registry = fixture.registryStorageURL.appendingPathComponent("workspace-registration-v3.json")
        try Data("{ damaged registered membership".utf8).write(to: registry)
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL)))
        do {
            let before = try settingsMetadataTree(fixture.rootURL)
            await #expect(throws: WorkspaceRegistryError.self) {
                _ = try await runtime.portableSettingsRecoverySnapshot(triptychID: fixture.assignment.id)
            }
            #expect(try settingsMetadataTree(fixture.rootURL) == before)
            #expect(await runtime.pooledVaultRuntimeCount == 0)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    @Test("An unavailable peer vault does not require a source activation to read portable Settings")
    func unavailablePeerDoesNotOpenSource() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        try FileManager.default.moveItem(at: fixture.analysesURL, to: fixture.rootURL.appendingPathComponent("Offline Analyses"))
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: fixture.applicationSupportURL,
                    workspaceRegistryStorageURL: fixture.registryStorageURL)))
        do {
            let before = try settingsMetadataTree(fixture.rootURL)
            let observed = try await runtime.portableSettingsRecoverySnapshot(triptychID: fixture.assignment.id)
            guard case .current = observed.loadState else {
                Issue.record("Portable Settings were not readable with an unavailable peer root.")
                await runtime.shutdown()
                return
            }
            #expect(try settingsMetadataTree(fixture.rootURL) == before)
            #expect(await runtime.pooledVaultRuntimeCount == 0)
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    #if DEBUG
        @Test("Cancellation drains the finite reader and cannot publish a Settings snapshot", .timeLimit(.minutes(1)))
        func cancelledReaderIsDrained() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let runtime = settingsMetadataRuntime(fixture)
            let barrier = SettingsMetadataBarrier()
            await runtime.setSettingsReadBarrierForTesting { _ in await barrier.hold() }
            let reader = Task { try await runtime.portableSettingsRecoverySnapshot(triptychID: fixture.assignment.id) }
            try await withTaskCancellationHandler {
                do {
                    await barrier.waitForArrival()
                    try Task.checkCancellation()
                    reader.cancel()
                    await barrier.waitForCancellation()
                    try Task.checkCancellation()
                    #expect(await runtime.settingsReadCountForTesting == 1)
                    await barrier.release()
                    await #expect(throws: CancellationError.self) { _ = try await reader.value }
                    #expect(await runtime.settingsReadCountForTesting == 0)
                    #expect(await runtime.openingFactoryCountForTesting == 0)
                    await runtime.shutdown()
                } catch {
                    reader.cancel()
                    await barrier.abort()
                    _ = await reader.result
                    await runtime.shutdown()
                    throw error
                }
            } onCancel: {
                Task { await barrier.abort() }
            }
        }

        @Test("Shutdown joins a pending metadata read before it completes", .timeLimit(.minutes(1)))
        func shutdownJoinsReader() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let runtime = settingsMetadataRuntime(fixture)
            let barrier = SettingsMetadataBarrier()
            await runtime.setSettingsReadBarrierForTesting { _ in await barrier.hold() }
            let reader = Task { try await runtime.portableSettingsRecoverySnapshot(triptychID: fixture.assignment.id) }
            try await withTaskCancellationHandler {
                do {
                    await barrier.waitForArrival()
                    try Task.checkCancellation()
                    let shutdown = Task {
                        await runtime.shutdown()
                        await barrier.markShutdownFinished()
                    }
                    await barrier.waitForCancellation()
                    try Task.checkCancellation()
                    #expect(!(await barrier.shutdownFinished))
                    await barrier.release()
                    _ = await reader.result
                    await shutdown.value
                    #expect(await barrier.shutdownFinished)
                    #expect(await runtime.pooledVaultRuntimeCount == 0)
                    #expect(await runtime.openingFactoryCountForTesting == 0)
                } catch {
                    reader.cancel()
                    await barrier.abort()
                    _ = await reader.result
                    await runtime.shutdown()
                    throw error
                }
            } onCancel: {
                Task { await barrier.abort() }
            }
        }
    #endif

    private func expectMetadataFailureWithoutWrites(_ fixture: ApplicationFixture) async throws {
        let runtime = settingsMetadataRuntime(fixture)
        do {
            let before = try settingsMetadataTree(fixture.rootURL)
            await #expect(throws: (any Error).self) {
                _ = try await runtime.portableSettingsRecoverySnapshot(triptychID: fixture.assignment.id)
            }
            #expect(try settingsMetadataTree(fixture.rootURL) == before)
            #expect(await runtime.pooledVaultRuntimeCount == 0)
            #if DEBUG
                #expect(await runtime.openingFactoryCountForTesting == 0)
            #endif
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }
}

func settingsMetadataRuntime(_ fixture: ApplicationFixture) -> WorkspaceRuntime {
    WorkspaceRuntime(
        configuration: .snapshot(
            .init(
                applicationSupportURL: fixture.applicationSupportURL,
                workspaceRegistryStorageURL: fixture.registryStorageURL,
                assignments: [fixture.assignment])))
}

/// Only test-owned trees; records links without following them. Includes
/// identity/timestamp observations so identical-byte replacements also differ.
func settingsMetadataTree(_ root: URL) throws -> [String: String] {
    var result: [String: String] = [:]
    var enumerationError: Error?
    let enumerator = try #require(
        FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }))
    for case let url as URL in enumerator {
        let relative = String(url.path.dropFirst(root.path.count + 1))
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values.isSymbolicLink == true {
            enumerator.skipDescendants()
            result[relative] = "link:" + (try FileManager.default.destinationOfSymbolicLink(atPath: url.path))
        } else if values.isDirectory == true {
            result[relative] = "directory"
        } else {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = try Data(contentsOf: url)
            result[relative] = "\(DocumentFingerprint(data: bytes).sha256):\(attrs[.systemFileNumber] ?? "nil"):\(attrs[.modificationDate] ?? "nil")"
        }
    }
    if let enumerationError { throw enumerationError }
    return result
}

#if DEBUG
    private actor SettingsMetadataBarrier {
        private var arrived = false
        private var cancelled = false
        private var aborted = false
        private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
        private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var shutdownFinished = false

        func hold() async {
            guard !aborted else { return }
            arrived = true
            arrivalWaiters.forEach { $0.resume() }
            arrivalWaiters.removeAll()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation = $0 }
            } onCancel: {
                Task { await self.didCancel() }
            }
        }
        func waitForArrival() async {
            if !arrived { await withCheckedContinuation { arrivalWaiters.append($0) } }
        }
        func waitForCancellation() async {
            if !cancelled { await withCheckedContinuation { cancellationWaiters.append($0) } }
        }
        private func didCancel() {
            cancelled = true
            cancellationWaiters.forEach { $0.resume() }
            cancellationWaiters.removeAll()
        }
        func release() {
            continuation?.resume()
            continuation = nil
        }
        func abort() {
            aborted = true
            arrived = true
            arrivalWaiters.forEach { $0.resume() }
            arrivalWaiters.removeAll()
            didCancel()
            release()
        }
        func markShutdownFinished() { shutdownFinished = true }
    }
#endif
