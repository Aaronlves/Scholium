import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Headless workspace runtime")
struct WorkspaceRuntimeTests {
    @Test("Document preview API is source-revision and graph-generation checked")
    func revisionCheckedDocumentPreviewCatalog() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        try Data("# Agency\n\n[[Freedom]]\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Agency.md"),
            options: .atomic
        )
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.discovery.refresh()
        let graph = try #require(snapshot.discovery.catalog.graph)
        let source = try #require(snapshot.document(id: fixture.analysisNoteID)?.document)

        let catalog = try await handle.documents.documentPreviewCatalog(
            source: fixture.analysisNoteID,
            sourceFingerprint: source.fingerprint,
            graphGeneration: graph.generation
        )
        let staleRevision = try await handle.documents.documentPreviewCatalog(
            source: fixture.analysisNoteID,
            sourceFingerprint: DocumentFingerprint(content: "stale"),
            graphGeneration: graph.generation
        )
        let staleGraph = try await handle.documents.documentPreviewCatalog(
            source: fixture.analysisNoteID,
            sourceFingerprint: source.fingerprint,
            graphGeneration: graph.generation - 1
        )

        #expect(catalog.links.count == 1)
        #expect(catalog.links.first?.title == "Freedom")
        #expect(staleRevision.links.isEmpty)
        #expect(staleGraph.links.isEmpty)
        await runtime.shutdown()
    }

    @Test("Snapshot mode reuses handle identity and publishes complete generations")
    func snapshotIdentityAndEvents() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )

        let first = try await runtime.openWorkspace(id: fixture.assignment.id)
        let second = try await runtime.openWorkspace(id: fixture.assignment.id)
        #expect(first === second)
        #expect(first.documents === second.documents)
        #expect(first.discovery === second.discovery)
        #expect(first.research === second.research)
        #expect(await first.ownedBackgroundTaskCount == 0)

        let stream = await first.events.events()
        var iterator = stream.makeAsyncIterator()
        let initial = try #require(await iterator.next())
        #expect(initial.generation == 0)
        #expect(initial.snapshot.vaults.count == 3)
        #expect(initial.snapshot.vaults.flatMap(\.documents).count == 3)
        if case .snapshot(let event) = initial {
            let analysis = try #require(event.snapshot.document(id: fixture.analysisNoteID))
            #expect(analysis.document.rawContent.contains("Freedom enables action"))
            #expect(analysis.fileMetadata.byteCount == analysis.document.sourceBytes.count)
            #expect(analysis.review == nil)
            #expect(analysis.graphCounts.incoming == 0)
        } else {
            Issue.record("The first event was not the initial complete snapshot.")
        }

        try Data("# Agency\n\nFreedom enables revised action.\n".utf8)
            .write(to: fixture.analysesURL.appendingPathComponent("Agency.md"), options: .atomic)
        let refreshed = try await first.discovery.refresh()
        let update = try #require(await iterator.next())
        #expect(update.generation == 1)
        #expect(update.snapshot.generatedAt == refreshed.generatedAt)
        if case .inventoryChanged(let event) = update {
            #expect(event.changed == [fixture.analysisNoteID])
            #expect(event.added.isEmpty)
            #expect(event.removed.isEmpty)
        } else {
            Issue.record("An external source revision did not publish inventoryChanged.")
        }
        #expect(
            update.snapshot.document(id: fixture.analysisNoteID)?.fingerprint
                != initial.snapshot.document(id: fixture.analysisNoteID)?.fingerprint
        )

        _ = try await first.discovery.refresh()
        let derived = try #require(await iterator.next())
        #expect(derived.generation == 2)
        if case .derivedStateChanged = derived {
            // Expected: no source inventory changed in this refresh.
        } else {
            Issue.record("An unchanged explicit refresh was not derivedStateChanged.")
        }

        await runtime.shutdown()
        #expect(await iterator.next() == nil)
    }

    @Test("Discovery uses Core search and snapshot membership remains fixed")
    func discoveryAndFrozenMembership() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let hits = try await handle.discovery.search(
            SearchQuery("freedom"),
            scope: .workspace
        )
        #expect(hits.contains { $0.vaultID == fixture.analysisNoteID.vaultID })
        #expect(try await runtime.availableWorkspaces().map(\.id) == [fixture.assignment.id])

        await runtime.shutdown()
        do {
            _ = try await runtime.openWorkspace(id: fixture.assignment.id)
            Issue.record("A shut-down runtime reopened a workspace.")
        } catch let error as ScholiumApplicationError {
            guard case .runtimeShutDown = error else {
                Issue.record("Unexpected shutdown error: \(error)")
                return
            }
        }
    }

    @Test("Document writes retain VaultRepository revision gates")
    func revisionGatedSave() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisNoteID)

        try Data("# Agency\n\nAn external editor changed this note.\n".utf8)
            .write(to: fixture.analysesURL.appendingPathComponent("Agency.md"), options: .atomic)
        do {
            _ = try await handle.documents.save(
                fixture.analysisNoteID,
                changeSet: .body("A stale write must not land.\n"),
                expectedRevision: original.fingerprint
            )
            Issue.record("A stale document revision was accepted.")
        } catch let error as VaultRepositoryError {
            guard case .conflict = error else {
                Issue.record("Unexpected repository error: \(error)")
                return
            }
        }

        let current = try await handle.documents.load(fixture.analysisNoteID)
        #expect(current.rawContent.contains("external editor"))
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let saved = try await handle.documents.save(
            fixture.analysisNoteID,
            changeSet: .body("A revision-gated application commit.\n"),
            expectedRevision: current.fingerprint
        )
        let event = try #require(await iterator.next())
        if case .sourceCommitted(let commit) = event {
            #expect(commit.note.fingerprint == saved.document.fingerprint)
            if case .save = commit.kind {
                // Expected.
            } else {
                Issue.record("A save was classified as a restore.")
            }
        } else {
            Issue.record("A successful source commit did not publish sourceCommitted.")
        }
        await runtime.shutdown()
    }

    @Test("Cancelled subscribers are removed")
    func subscriberCancellation() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            assignments: [fixture.assignment]
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let source = handle.events
        let stream = await source.events()
        let subscriber = Task {
            for await _ in stream {
                if Task.isCancelled { break }
            }
        }
        for _ in 0..<20 where await source.subscriberCount != 1 {
            await Task.yield()
        }
        #expect(await source.subscriberCount == 1)

        subscriber.cancel()
        _ = await subscriber.result
        for _ in 0..<20 where await source.subscriberCount != 0 {
            await Task.yield()
        }
        #expect(await source.subscriberCount == 0)
        await runtime.shutdown()
    }

    @Test("Live mode owns refresh tasks while snapshot mode owns none")
    func liveWatcherLifecycle() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        #expect(await handle.ownedBackgroundTaskCount > 0)
        let readiness = try #require(await handle.watcherReadinessEvidence)
        #expect(readiness.activationReconciliationCompleted)
        #expect(readiness.watchedVaultIDs == Set(fixture.assignment.vaults.values.map(\.id)))
        let reopened = try await runtime.openWorkspace(id: fixture.assignment.id)
        #expect(handle.events === reopened.events)

        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        _ = try #require(await iterator.next())
        let before = try await handle.snapshot()
            .document(id: fixture.analysisNoteID)?.fingerprint
        try Data("# Agency\n\nA live external revision.\n".utf8)
            .write(to: fixture.analysesURL.appendingPathComponent("Agency.md"), options: .atomic)

        var observedChange = false
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(20))
            let current = try await handle.snapshot()
                .document(id: fixture.analysisNoteID)?.fingerprint
            if current != before {
                observedChange = true
                break
            }
        }
        #expect(observedChange)
        let event = try #require(await iterator.next())
        if case .inventoryChanged(let inventory) = event {
            #expect(inventory.changed.contains(fixture.analysisNoteID))
        } else {
            Issue.record("The live watcher did not publish inventoryChanged.")
        }

        await runtime.shutdown()
        #expect(await handle.ownedBackgroundTaskCount == 0)
        #expect(await handle.watcherReadinessEvidence == nil)
        #expect(await iterator.next() == nil)
    }

    @Test("Native live events publish one stable-identity move to every window")
    func liveRenamePublishesMoveToTwoWindows() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let firstWindow = try await runtime.openWorkspace(id: fixture.assignment.id)
        let secondWindow = try await runtime.openWorkspace(id: fixture.assignment.id)
        #expect(firstWindow === secondWindow)

        let original = try #require(
            try await firstWindow.snapshot().document(id: fixture.analysisNoteID)
        )
        let stableID = try #require(original.stableIdentity.resolvedID)
        let firstStream = await firstWindow.events.events()
        let secondStream = await secondWindow.events.events()
        var firstIterator = firstStream.makeAsyncIterator()
        var secondIterator = secondStream.makeAsyncIterator()
        _ = try #require(await firstIterator.next())
        _ = try #require(await secondIterator.next())

        let destinationPath = "Agency Renamed.md"
        try FileManager.default.moveItem(
            at: fixture.analysesURL.appendingPathComponent("Agency.md"),
            to: fixture.analysesURL.appendingPathComponent(destinationPath)
        )
        let destinationID = VaultQualifiedNoteID(
            vaultID: fixture.analysisNoteID.vaultID,
            relativePath: destinationPath
        )
        var observed = false
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(25))
            if try await firstWindow.snapshot().document(id: destinationID) != nil {
                observed = true
                break
            }
        }
        #expect(observed)

        for event in [
            try #require(await firstIterator.next()),
            try #require(await secondIterator.next()),
        ] {
            guard case .inventoryChanged(let inventory) = event else {
                Issue.record("A window did not receive the resolved rename generation.")
                continue
            }
            #expect(inventory.added.isEmpty)
            #expect(inventory.removed.isEmpty)
            let move = try #require(inventory.moved.first)
            #expect(move.stableNoteID == stableID)
            #expect(move.previousLocation == fixture.analysisNoteID)
            #expect(move.location == destinationID)
            #expect(inventory.snapshot.document(id: destinationID)?.stableIdentity.resolvedID == stableID)
        }

        await runtime.shutdown()
        #expect(await firstIterator.next() == nil)
        #expect(await secondIterator.next() == nil)
        #expect(await firstWindow.ownedBackgroundTaskCount == 0)
    }

    @Test("Snapshot runtime preserves the persisted default Triptych")
    func snapshotPreservesDefaultWorkspace() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let second = try await fixture.makeSecondAssignment(name: "Aardvark")
        let live = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        try await live.setDefaultWorkspace(id: fixture.assignment.id)
        await live.shutdown()
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        #expect(try await runtime.defaultWorkspace().id == fixture.assignment.id)
        #expect(try await runtime.availableWorkspaces().map(\.id).contains(second.id))
        await runtime.shutdown()
    }

    @Test("Two Triptychs share one pooled vault repository, index, and watcher")
    func sharedVaultPoolFansOutToBothTriptychs() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let secondAssignment = try await fixture.makeSecondLiveAssignmentSharingAnalyses()
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        async let firstOpen = runtime.openWorkspace(id: fixture.assignment.id)
        async let secondOpen = runtime.openWorkspace(id: secondAssignment.id)
        let (first, second) = try await (firstOpen, secondOpen)
        #expect(await runtime.pooledVaultRuntimeCount == 5)
        #expect(await runtime.pooledVaultSubscriberCount(
            vaultID: fixture.analysisNoteID.vaultID
        ) == 2)
        #expect(await runtime.pooledVaultOwnsNativeWatcher(
            vaultID: fixture.analysisNoteID.vaultID
        ) == true)

        let firstStream = await first.events.events()
        let secondStream = await second.events.events()
        var firstIterator = firstStream.makeAsyncIterator()
        var secondIterator = secondStream.makeAsyncIterator()
        _ = try #require(await firstIterator.next())
        _ = try #require(await secondIterator.next())
        let beforeFirst = try #require(
            try await first.snapshot().document(id: fixture.analysisNoteID)?.fingerprint
        )
        let beforeSecond = try #require(
            try await second.snapshot().document(id: fixture.analysisNoteID)?.fingerprint
        )
        try Data("# Agency\n\nShared pooled event.\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Agency.md"),
            options: .atomic
        )

        var bothObserved = false
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(25))
            let firstRevision = try await first.snapshot()
                .document(id: fixture.analysisNoteID)?.fingerprint
            let secondRevision = try await second.snapshot()
                .document(id: fixture.analysisNoteID)?.fingerprint
            if firstRevision != beforeFirst, secondRevision != beforeSecond {
                bothObserved = true
                break
            }
        }
        #expect(bothObserved)
        guard case .inventoryChanged = try #require(await firstIterator.next()) else {
            Issue.record("The first Triptych missed the pooled vault event.")
            await runtime.shutdown()
            return
        }
        guard case .inventoryChanged = try #require(await secondIterator.next()) else {
            Issue.record("The second Triptych missed the pooled vault event.")
            await runtime.shutdown()
            return
        }
        await runtime.shutdown()
        #expect(await firstIterator.next() == nil)
        #expect(await secondIterator.next() == nil)
    }

    @Test("Delayed self FSEvents do not rebuild a published save generation")
    func selfEventIsNoOp() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let original = try await handle.documents.load(fixture.analysisNoteID)
        _ = try await handle.documents.save(
            fixture.analysisNoteID,
            changeSet: .body("One authoritative self-save.\n"),
            expectedRevision: original.fingerprint
        )
        let committedGeneration = await handle.events.publishedGeneration
        try await Task.sleep(for: .seconds(1))
        #expect(await handle.events.publishedGeneration == committedGeneration)
        await runtime.shutdown()
    }
}

struct ApplicationFixture: Sendable {
    let rootURL: URL
    let applicationSupportURL: URL
    let registryStorageURL: URL
    let analysesURL: URL
    let topicsURL: URL
    let worksURL: URL
    let assignment: TriptychAssignment
    let analysisNoteID: VaultQualifiedNoteID

    static func make(registerLiveAccess: Bool = false) async throws -> Self {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScholiumApplicationTests-\(UUID().uuidString)", isDirectory: true)
        let applicationSupportURL = rootURL.appendingPathComponent("Application Support", isDirectory: true)
        let analysesURL = rootURL.appendingPathComponent("Analyses", isDirectory: true)
        let topicsURL = rootURL.appendingPathComponent("Topics", isDirectory: true)
        let worksURL = rootURL.appendingPathComponent("Works", isDirectory: true)
        let registryStorageURL = rootURL.appendingPathComponent("Registry", isDirectory: true)
        for url in [applicationSupportURL, analysesURL, topicsURL, worksURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try Data("# Agency\n\nFreedom enables action.\n".utf8)
            .write(to: analysesURL.appendingPathComponent("Agency.md"))
        try Data("# Freedom\n\nA topic note about agency.\n".utf8)
            .write(to: topicsURL.appendingPathComponent("Freedom.md"))
        try Data("# Chapter\n\nA draft argument.\n".utf8)
            .write(to: worksURL.appendingPathComponent("Chapter.md"))

        _ = registerLiveAccess
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analysesURL,
            topicKnowledgeURL: topicsURL,
            outputURL: worksURL,
            portableContainerURL: rootURL,
            triptychName: "Fixture"
        )
        let assignment = handle.assignment
        let analysesID = try #require(assignment.vault(for: .paperAnalysis)?.id)
        await runtime.shutdown()
        return Self(
            rootURL: rootURL,
            applicationSupportURL: applicationSupportURL,
            registryStorageURL: registryStorageURL,
            analysesURL: analysesURL,
            topicsURL: topicsURL,
            worksURL: worksURL,
            assignment: assignment,
            analysisNoteID: VaultQualifiedNoteID(
                vaultID: analysesID,
                relativePath: "Agency.md"
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func makeSecondAssignment(name: String) async throws -> TriptychAssignment {
        let suffix = UUID().uuidString
        let container = rootURL.appendingPathComponent("Triptych-\(suffix)", isDirectory: true)
        let analyses = container.appendingPathComponent("Analyses", isDirectory: true)
        let topics = container.appendingPathComponent("Topics", isDirectory: true)
        let works = container.appendingPathComponent("Works", isDirectory: true)
        for url in [container, analyses, topics, works] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analyses,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: container,
            triptychName: name
        )
        await runtime.shutdown()
        return handle.assignment
    }

    func makeSecondLiveAssignmentSharingAnalyses() async throws -> TriptychAssignment {
        let container = rootURL.appendingPathComponent(
            "Second Triptych",
            isDirectory: true
        )
        let topics = container.appendingPathComponent("Topics", isDirectory: true)
        let works = container.appendingPathComponent("Works", isDirectory: true)
        for url in [container, topics, works] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try Data("# Other Topic\n".utf8).write(
            to: topics.appendingPathComponent("Other.md")
        )
        try Data("# Other Work\n".utf8).write(
            to: works.appendingPathComponent("Other.md")
        )
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL
        )))
        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: analysesURL,
            topicKnowledgeURL: topics,
            outputURL: works,
            portableContainerURL: container,
            triptychName: "Second"
        )
        await runtime.shutdown()
        return handle.assignment
    }
}
