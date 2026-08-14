import ScholiumContracts
import Foundation
import Testing
@testable import ScholiumApplication

@Suite("Headless workspace runtime")
struct WorkspaceRuntimeTests {
    @Test("Portable Analysis Zotero bindings project through a reopened workspace")
    func portableAnalysisZoteroBindingProjectsOnOpen() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let firstRuntime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let firstHandle = try await firstRuntime.openWorkspace(id: fixture.assignment.id)
        let firstSnapshot = try await firstHandle.snapshot()
        let firstProjection = try #require(firstSnapshot.discovery.catalog.notes.first {
            $0.reference.vaultID == fixture.analysisNoteID.vaultID
                && $0.reference.relativePath == fixture.analysisNoteID.relativePath
        })
        let noteID = try #require(
            firstProjection.reference.stableNoteID.flatMap(UUID.init(uuidString:))
        )
        let original = try await firstHandle.zoteroBindings.zoteroBindings()
        let expected = try AnalysisZoteroBinding(
            noteID: noteID,
            library: .user,
            itemKey: "QAITEM01"
        )
        _ = try await firstHandle.zoteroBindings.setZoteroBinding(
            expected,
            expectedRevision: original.revision
        )
        await firstRuntime.shutdown()

        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let snapshot = try await handle.snapshot()
        let projected = try #require(snapshot.discovery.catalog.notes.first {
            $0.reference.vaultID == fixture.analysisNoteID.vaultID
                && $0.reference.relativePath == fixture.analysisNoteID.relativePath
        })

        #expect(projected.reference.stableNoteID == noteID.uuidString.lowercased())
        #expect(projected.zoteroBinding == expected)
        await runtime.shutdown()
    }

    @Test("Fresh machine registration preserves a portable Triptych and vault identities")
    func freshRegistrationPreservesPortableIdentities() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let manifestURL = fixture.rootURL.appendingPathComponent(
            ".scholium/manifest.json"
        )
        let originalManifest = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            TriptychManifest.self,
            from: originalManifest
        )
        let freshSupport = fixture.rootURL.appendingPathComponent(
            "Fresh Application Support",
            isDirectory: true
        )
        let freshRegistry = fixture.rootURL.appendingPathComponent(
            "Fresh Registry",
            isDirectory: true
        )
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: freshSupport,
            workspaceRegistryStorageURL: freshRegistry
        )))

        let handle = try await runtime.configureTriptych(
            paperAnalysisURL: fixture.analysesURL,
            topicKnowledgeURL: fixture.topicsURL,
            outputURL: fixture.worksURL,
            portableContainerURL: fixture.rootURL,
            triptychName: "Reopened Fixture"
        )

        #expect(handle.assignment.id == manifest.id)
        for slot in WorkspaceVaultSlot.allCases {
            #expect(handle.assignment.vault(for: slot)?.id == manifest.vaultIDs[slot])
        }
        #expect(try Data(contentsOf: manifestURL) == originalManifest)
        await runtime.shutdown()
    }

    @Test("Invalid portable identity fails before fresh machine registration mutates local state")
    func invalidPortableIdentityFailsBeforeRegistration() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let manifestURL = fixture.rootURL.appendingPathComponent(
            ".scholium/manifest.json"
        )
        let invalidManifest = Data("{\"schemaVersion\":999}".utf8)
        try invalidManifest.write(to: manifestURL, options: .atomic)
        let freshSupport = fixture.rootURL.appendingPathComponent(
            "Invalid Fresh Application Support",
            isDirectory: true
        )
        let freshRegistry = fixture.rootURL.appendingPathComponent(
            "Invalid Fresh Registry",
            isDirectory: true
        )
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: freshSupport,
            workspaceRegistryStorageURL: freshRegistry
        )))

        await #expect(throws: (any Error).self) {
            _ = try await runtime.configureTriptych(
                paperAnalysisURL: fixture.analysesURL,
                topicKnowledgeURL: fixture.topicsURL,
                outputURL: fixture.worksURL,
                portableContainerURL: fixture.rootURL
            )
        }

        #expect(try Data(contentsOf: manifestURL) == invalidManifest)
        #expect(!FileManager.default.fileExists(
            atPath: freshSupport.appendingPathComponent("vault-registry.json").path
        ))
        await runtime.shutdown()
    }

    @Test("Rejected overlapping vaults leave every machine-local registry unchanged")
    func overlapFailsBeforeAnyRegistrationMutation() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let registryURLs = [
            fixture.applicationSupportURL.appendingPathComponent("vault-registry.json"),
            fixture.applicationSupportURL.appendingPathComponent(
                "portable-control-access.json"
            ),
            fixture.registryStorageURL.appendingPathComponent(
                "workspace-registry-v2.json"
            ),
        ]
        let originalBytes = try registryURLs.map { try Data(contentsOf: $0) }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))

        await #expect(throws: WorkspaceRegistryError.self) {
            _ = try await runtime.configureTriptych(
                paperAnalysisURL: fixture.analysesURL,
                topicKnowledgeURL: fixture.analysesURL,
                outputURL: fixture.worksURL,
                portableContainerURL: fixture.rootURL
            )
        }

        for (url, expected) in zip(registryURLs, originalBytes) {
            #expect(try Data(contentsOf: url) == expected)
        }
        await runtime.shutdown()
    }

    @Test("Two portable manifests cannot assign different identities to one shared vault")
    func sharedVaultIdentityConflictLeavesRegistriesUnchanged() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let secondRoot = fixture.rootURL.appendingPathComponent(
            "Second Triptych",
            isDirectory: true
        )
        let secondTopics = secondRoot.appendingPathComponent("Topics", isDirectory: true)
        let secondWorks = secondRoot.appendingPathComponent("Works", isDirectory: true)
        let secondControl = secondRoot.appendingPathComponent(".scholium", isDirectory: true)
        for url in [secondTopics, secondWorks, secondControl] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let secondManifest = TriptychManifest(vaultIDs: [
            .paperAnalysis: UUID(),
            .topicKnowledge: UUID(),
            .output: UUID(),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let secondManifestURL = secondControl.appendingPathComponent("manifest.json")
        try encoder.encode(secondManifest).write(to: secondManifestURL, options: .atomic)

        let registryURLs = [
            fixture.applicationSupportURL.appendingPathComponent("vault-registry.json"),
            fixture.applicationSupportURL.appendingPathComponent(
                "portable-control-access.json"
            ),
            fixture.registryStorageURL.appendingPathComponent(
                "workspace-registry-v2.json"
            ),
        ]
        let originalRegistryBytes = try registryURLs.map { try Data(contentsOf: $0) }
        let originalManifestBytes = try Data(contentsOf: secondManifestURL)
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))

        await #expect(throws: VaultIdentityRegistryError.self) {
            _ = try await runtime.configureTriptych(
                paperAnalysisURL: fixture.analysesURL,
                topicKnowledgeURL: secondTopics,
                outputURL: secondWorks,
                portableContainerURL: secondRoot
            )
        }

        for (url, expected) in zip(registryURLs, originalRegistryBytes) {
            #expect(try Data(contentsOf: url) == expected)
        }
        #expect(try Data(contentsOf: secondManifestURL) == originalManifestBytes)
        await runtime.shutdown()
    }

    @Test("One shared vault identity cannot be assigned two Triptych roles")
    func sharedVaultRoleConflictLeavesRegistriesUnchanged() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let analysesID = try #require(
            fixture.assignment.vault(for: .paperAnalysis)?.id
        )
        let secondRoot = fixture.rootURL.appendingPathComponent(
            "Role Conflict Triptych",
            isDirectory: true
        )
        let secondAnalyses = secondRoot.appendingPathComponent(
            "Analyses",
            isDirectory: true
        )
        let secondWorks = secondRoot.appendingPathComponent("Works", isDirectory: true)
        let secondControl = secondRoot.appendingPathComponent(".scholium", isDirectory: true)
        for url in [secondAnalyses, secondWorks, secondControl] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let secondManifest = TriptychManifest(vaultIDs: [
            .paperAnalysis: UUID(),
            .topicKnowledge: analysesID,
            .output: UUID(),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let secondManifestURL = secondControl.appendingPathComponent("manifest.json")
        try encoder.encode(secondManifest).write(to: secondManifestURL, options: .atomic)

        let registryURLs = [
            fixture.applicationSupportURL.appendingPathComponent("vault-registry.json"),
            fixture.applicationSupportURL.appendingPathComponent(
                "portable-control-access.json"
            ),
            fixture.registryStorageURL.appendingPathComponent(
                "workspace-registry-v2.json"
            ),
        ]
        let originalRegistryBytes = try registryURLs.map { try Data(contentsOf: $0) }
        let originalManifestBytes = try Data(contentsOf: secondManifestURL)
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))

        await #expect(throws: WorkspaceRegistryError.self) {
            _ = try await runtime.configureTriptych(
                paperAnalysisURL: secondAnalyses,
                topicKnowledgeURL: fixture.analysesURL,
                outputURL: secondWorks,
                portableContainerURL: secondRoot
            )
        }

        for (url, expected) in zip(registryURLs, originalRegistryBytes) {
            #expect(try Data(contentsOf: url) == expected)
        }
        #expect(try Data(contentsOf: secondManifestURL) == originalManifestBytes)
        await runtime.shutdown()
    }

    @Test("Document preview API is source-revision and graph-generation checked")
    func revisionCheckedDocumentPreviewCatalog() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        try Data("---\ntitle: Agency\n---\n[[Freedom]]\n".utf8).write(
            to: fixture.analysesURL.appendingPathComponent("Agency.md"),
            options: .atomic
        )
        try Data("---\ntitle: Freedom\n---\nA topic note about agency.\n".utf8).write(
            to: fixture.topicsURL.appendingPathComponent("Freedom.md"),
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
        let analysesSnapshot = try #require(initial.snapshot.vaults.first {
            $0.vault.id == fixture.analysisNoteID.vaultID
        })
        let volumeValues = try fixture.analysesURL.resourceValues(forKeys: [
            .volumeSupportsCaseSensitiveNamesKey,
        ])
        #expect(analysesSnapshot.pathComparisonPolicy == VaultPathComparisonPolicy(
            caseSensitive: volumeValues.volumeSupportsCaseSensitiveNames ?? true,
            normalizationSensitive: false
        ))
        if case .snapshot(let event) = initial {
            let analysis = try #require(event.snapshot.document(id: fixture.analysisNoteID))
            #expect(analysis.document.rawContent.contains("Freedom enables action"))
            #expect(analysis.fileMetadata.byteCount == analysis.document.sourceBytes.count)
            #expect(analysis.fileMetadata.modificationDate != nil)
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

    @Test("Document import commits exact bytes to the selected vault root and republishes the Note")
    func importMarkdownIntoSelectedVault() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let sourceURL = fixture.rootURL.appendingPathComponent("Imported.md")
        let source = Data([0xEF, 0xBB, 0xBF]) + Data(
            "---\r\nunknown: [source material\r\n---\r\n# Imported\r\n".utf8
        )
        try source.write(to: sourceURL)
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let topicsID = try #require(
            fixture.assignment.vault(for: .topicKnowledge)?.id
        )

        let imported = try await handle.documents.importMarkdown(
            at: sourceURL,
            intoVault: topicsID
        ).committedValue

        #expect(imported.relativePath == "Imported.md")
        #expect(try Data(contentsOf: sourceURL) == source)
        #expect(try Data(contentsOf: fixture.topicsURL.appendingPathComponent("Imported.md")) == source)
        #expect(try await handle.snapshot().document(id: VaultQualifiedNoteID(
            vaultID: topicsID,
            relativePath: "Imported.md"
        ))?.fingerprint == imported.fingerprint)
        await runtime.shutdown()
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

        let hits = try await handle.discovery.search(SearchRequest(
            query: "freedom",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 20
        ))
        let noteHits = hits.results.compactMap { result -> NoteSearchResult? in
            guard case .note(let note) = result else { return nil }
            return note
        }
        #expect(noteHits.contains {
            $0.vaultID == fixture.analysisNoteID.vaultID
        })
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
        ).committedValue
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

    @Test("Live opening publishes one usable vault before the complete Triptych")
    func progressiveLiveOpening() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let measurementDocumentCount = 16
        let measurementBody = String(
            repeating: "A bounded catalog measurement paragraph.\n\n",
            count: 96
        )
        for index in 0..<measurementDocumentCount {
            try Data(
                "# Catalog Measurement \(index)\n\n\(measurementBody)".utf8
            ).write(to: fixture.analysesURL.appendingPathComponent(
                "Catalog Measurement \(index).md"
            ))
        }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let handle = try await runtime.openWorkspace(
            id: fixture.assignment.id,
            openingVault: .paperAnalysis
        )
        let activationGate = OpeningActivationReconciliationGate()
        await handle.setProgressiveActivationReconciliationBarrierForTesting {
            await activationGate.wait()
        }
        let stream = await handle.events.events()
        var iterator = stream.makeAsyncIterator()
        let openingEvent = try #require(await iterator.next())
        let openingMeasurement = await handle.latestRefreshMeasurement

        #expect(openingEvent.snapshot.phase == .opening(
            availableVault: .paperAnalysis
        ))
        #expect(openingMeasurement.readDuration <= openingMeasurement.totalDuration)
        #expect(openingEvent.snapshot.vaults.map(\.slot) == [.paperAnalysis])
        #expect(openingEvent.snapshot.discovery.searchGeneration == nil)
        #expect(openingEvent.snapshot.discovery.catalog.graph == nil)
        #expect(!openingEvent.snapshot.research.finishedResearchRecordProjectionIsComplete)
        #expect(await handle.ownedBackgroundTaskCount >= 2)

        let openedDocument = try await handle.documents.load(fixture.analysisNoteID)
        #expect(openedDocument.rawContent.contains("Freedom enables action"))
        do {
            _ = try await handle.discovery.search(SearchRequest(
                query: "freedom",
                presentationScope: .triptych,
                executionScope: .triptych,
                limit: 20
            ))
            Issue.record("Opening Search presented an incomplete Triptych as complete.")
        } catch let error as ScholiumApplicationError {
            guard case .workspaceStillLoading(let id) = error else {
                Issue.record("Unexpected opening Search error: \(error)")
                await runtime.shutdown()
                return
            }
            #expect(id == fixture.assignment.id)
        }

        try await Task.sleep(for: .milliseconds(500))
        #expect(try await handle.snapshot().phase == .opening(
            availableVault: .paperAnalysis
        ))
        await handle.openingPresentationDidComplete()
        await activationGate.waitUntilArrived()
        let phaseWhileReconciling = try? await handle.snapshot().phase
        #expect(phaseWhileReconciling == .opening(availableVault: .paperAnalysis))
        #expect(await handle.watcherReadinessEvidence == nil)
        await activationGate.release()
        await handle.setProgressiveActivationReconciliationBarrierForTesting(nil)

        var completed = false
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(20))
            if try await handle.snapshot().phase.isComplete {
                completed = true
                break
            }
        }
        #expect(completed)
        let completeEvent = try #require(await iterator.next())
        #expect(completeEvent.snapshot.phase == .complete)
        #expect(completeEvent.snapshot.vaults.count == 3)
        #expect(
            completeEvent.snapshot.vaults.flatMap(\.documents).count
                == 3 + measurementDocumentCount
        )
        #expect(completeEvent.snapshot.discovery.searchGeneration != nil)
        #expect(completeEvent.snapshot.discovery.catalog.graph != nil)

        let response = try await handle.discovery.search(SearchRequest(
            query: "freedom",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 20
        ))
        #expect(!response.results.isEmpty)
        #expect(await handle.watcherReadinessEvidence != nil)

        await runtime.shutdown()
        #expect(await handle.ownedBackgroundTaskCount == 0)
        #expect(await iterator.next() == nil)
    }

    @Test("Library-only progressive opening completes through its bounded fallback")
    func progressiveLiveOpeningWithoutDocumentPresentation() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let handle = try await runtime.openWorkspace(
            id: fixture.assignment.id,
            openingVault: .paperAnalysis
        )
        #expect(try await handle.snapshot().phase == .opening(
            availableVault: .paperAnalysis
        ))

        var completed = false
        for _ in 0..<150 {
            try await Task.sleep(for: .milliseconds(20))
            if try await handle.snapshot().phase.isComplete {
                completed = true
                break
            }
        }
        #expect(completed)

        await runtime.shutdown()
        #expect(await handle.ownedBackgroundTaskCount == 0)
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
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        #expect(try await runtime.defaultWorkspace().id == fixture.assignment.id)
        #expect(try await runtime.availableWorkspaces().map(\.id).contains(second.id))
        await runtime.shutdown()
    }

    @Test("Two Triptychs share one pooled vault repository and watcher but retain independent indexes")
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

    @Test("Shared vaults cannot cross-contaminate ordinary results or broken links")
    func sharedVaultSearchIsolation() async throws {
        let fixture = try await ApplicationFixture.make(registerLiveAccess: true)
        defer { fixture.remove() }
        try Data("# FirstTriptychTerm\n\n[[Missing First]]\n".utf8).write(
            to: fixture.topicsURL.appendingPathComponent("Freedom.md"),
            options: .atomic
        )
        let secondAssignment = try await fixture.makeSecondLiveAssignmentSharingAnalyses()
        let secondTopic = fixture.rootURL
            .appendingPathComponent("Second Triptych/Topics/Other.md")
        try Data("# SecondTriptychTerm\n\n[[Missing Second]]\n".utf8).write(
            to: secondTopic,
            options: .atomic
        )

        let runtime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )))
        let first = try await runtime.openWorkspace(id: fixture.assignment.id)
        let second = try await runtime.openWorkspace(id: secondAssignment.id)

        func results(_ query: String, in handle: WorkspaceHandle) async throws
            -> [NoteSearchResult]
        {
            let response = try await handle.discovery.search(SearchRequest(
                query: query,
                presentationScope: .triptych,
                executionScope: .triptych,
                limit: 50
            ))
            return response.results.compactMap { result in
                guard case .note(let note) = result else { return nil }
                return note
            }
        }

        #expect(try await results("FirstTriptychTerm", in: first).map(\.relativePath)
            == ["Freedom.md"])
        #expect(try await results("FirstTriptychTerm", in: second).isEmpty)
        #expect(try await results("SecondTriptychTerm", in: first).isEmpty)
        #expect(try await results("SecondTriptychTerm", in: second).map(\.relativePath)
            == ["Other.md"])
        #expect(try await results("has:broken-link", in: first).map(\.relativePath)
            == ["Freedom.md"])
        #expect(try await results("has:broken-link", in: second).map(\.relativePath)
            == ["Other.md"])
        let firstIndex = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(
                fixture.assignment.id.uuidString.lowercased(),
                isDirectory: true
            )
            .appendingPathComponent("indexes/search-v7.sqlite")
        let secondIndex = fixture.applicationSupportURL
            .appendingPathComponent("Triptychs", isDirectory: true)
            .appendingPathComponent(
                secondAssignment.id.uuidString.lowercased(),
                isDirectory: true
            )
            .appendingPathComponent("indexes/search-v7.sqlite")
        #expect(firstIndex != secondIndex)
        #expect(FileManager.default.fileExists(atPath: firstIndex.path))
        #expect(FileManager.default.fileExists(atPath: secondIndex.path))
        await runtime.shutdown()
    }

    @Test("Search rejects forged Vault and Note scopes before provider execution")
    func searchScopeAuthorizationFailsClosed() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let forgedVault = UUID()
        let vaultResponse = try await handle.discovery.search(SearchRequest(
            query: "kind:record",
            presentationScope: .currentVault,
            executionScope: .currentVault(forgedVault),
            limit: 20
        ))
        #expect(vaultResponse.results.isEmpty)
        #expect(vaultResponse.diagnostics.map(\.code) == [.notApplicable])

        let mismatched = try await handle.discovery.search(SearchRequest(
            query: "freedom",
            presentationScope: .triptych,
            executionScope: .currentVault(fixture.analysisNoteID.vaultID),
            limit: 20
        ))
        #expect(mismatched.results.isEmpty)
        #expect(mismatched.diagnostics.map(\.code) == [.notApplicable])

        let forgedNote = SearchSourceSnapshot(
            noteID: VaultQualifiedNoteID(
                vaultID: fixture.analysisNoteID.vaultID,
                relativePath: "Not Authorized.md"
            ),
            editorSessionID: UUID(),
            source: "# Forged",
            editorRevision: 1
        )
        let noteResponse = try await handle.discovery.search(SearchRequest(
            query: "property:language",
            presentationScope: .thisNote,
            executionScope: .currentNote(forgedNote),
            limit: 20
        ))
        #expect(noteResponse.results.isEmpty)
        #expect(noteResponse.diagnostics.map(\.code) == [.notApplicable])
        await runtime.shutdown()
    }

    @Test("Direct relation Search uses the same complete Graph manifest and preserves source provenance")
    func directRelationSearchIntegration() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        try Data("# Anchor\n\n+[[Target]]\n".utf8).write(
            to: fixture.topicsURL.appendingPathComponent("Anchor.md"),
            options: .atomic
        )
        try Data("# Target\n\nA bounded relation target.\n".utf8).write(
            to: fixture.topicsURL.appendingPathComponent("Target.md"),
            options: .atomic
        )
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)

        let response = try await handle.discovery.search(SearchRequest(
            query: "from-note:Anchor relation:supports",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 20
        ))
        #expect(response.diagnostics.isEmpty)
        let target = try #require(response.results.compactMap { result -> NoteSearchResult? in
            guard case .note(let note) = result else { return nil }
            return note
        }.first)
        #expect(target.relativePath == "Target.md")
        let relationship = try #require(target.matchReasons.compactMap {
            reason -> SearchRelationshipMatch? in
            guard case .relationship(let match) = reason else { return nil }
            return match
        }.first)
        #expect(relationship.direction == .fromNote)
        #expect(relationship.relation == .supports)
        #expect(relationship.occurrences.first?.sourceNote.relativePath == "Anchor.md")
        #expect(relationship.occurrences.first?.locator.line == 3)

        let narrowed = try await handle.discovery.search(SearchRequest(
            query: "missing-term from-note:Anchor relation:supports",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 20
        ))
        #expect(narrowed.results.isEmpty)
        await runtime.shutdown()
    }

    @Test("Source catalog deltas equal a clean rebuild and one save parses only one file")
    func sourceCatalogIncrementalEquivalence() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        for index in 0..<5 {
            try Data("# Extra \(index)\n\nCached projection \(index).\n".utf8).write(
                to: fixture.analysesURL.appendingPathComponent("Extra \(index).md")
            )
        }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let services = await handle.services
        let original = try await handle.documents.load(fixture.analysisNoteID)
        _ = try await handle.documents.save(
            fixture.analysisNoteID,
            changeSet: .body("Freedom enables precisely bounded action.\n"),
            expectedRevision: original.fingerprint
        )
        let catalog = try #require(
            services.sourceCatalogs[fixture.analysisNoteID.vaultID]
        )
        let saveProjection = try await catalog.snapshot(refreshFolders: false)
        #expect(saveProjection.measurement.enumeratedFiles == 6)
        #expect(saveProjection.measurement.readFiles == 1)
        #expect(saveProjection.measurement.parsedDocuments == 1)

        try await catalog.apply(VaultWatchEvent(
            added: [],
            modified: [],
            deleted: [fixture.analysisNoteID.relativePath],
            sequence: 0,
            requiresFullRescan: false,
            rootChanged: false
        ))
        #expect(try await catalog.snapshot(refreshFolders: false).documents
            .contains { $0.relativePath == fixture.analysisNoteID.relativePath })

        let addedURL = fixture.analysesURL.appendingPathComponent("Added.md")
        try Data("# Added\n\n[[Missing Added]]\n".utf8).write(to: addedURL)
        try await catalog.apply(VaultWatchEvent(
            added: ["Added.md"],
            modified: [],
            deleted: [],
            sequence: 1,
            requiresFullRescan: false,
            rootChanged: false
        ))
        let addedProjection = try await catalog.snapshot(refreshFolders: false)
        #expect(addedProjection.measurement.enumeratedFiles == 0)
        #expect(addedProjection.measurement.readFiles == 1)
        #expect(addedProjection.measurement.parsedDocuments == 1)
        let renamedURL = fixture.analysesURL.appendingPathComponent("Renamed.md")
        try FileManager.default.moveItem(at: addedURL, to: renamedURL)
        try await catalog.apply(VaultWatchEvent(
            added: ["Renamed.md"],
            modified: [],
            deleted: ["Added.md"],
            sequence: 2,
            requiresFullRescan: false,
            rootChanged: false
        ))
        try FileManager.default.removeItem(at: renamedURL)
        try await catalog.apply(VaultWatchEvent(
            added: [],
            modified: [],
            deleted: ["Renamed.md"],
            sequence: 3,
            requiresFullRescan: false,
            rootChanged: false
        ))
        try await catalog.apply(.reconciliationRequired(sequence: 4))

        let incremental = try await catalog.snapshot(refreshFolders: false)
        let clean = try await VaultSourceCatalog(
            repository: try #require(
                services.repositories[fixture.analysisNoteID.vaultID]
            ),
            vaultRole: .sourceCorpus
        ).snapshot(refreshFolders: false)
        #expect(incremental.documents.map(\.relativePath)
            == clean.documents.map(\.relativePath))
        #expect(incremental.documents.map(\.fingerprint)
            == clean.documents.map(\.fingerprint))
        #expect(incremental.sourceVersions == clean.sourceVersions)
        #expect(incremental.fileMetadata == clean.fileMetadata)
        #expect(Set(incremental.semantics.keys) == Set(clean.semantics.keys))
        #expect(incremental.folders == clean.folders)

        let incrementalWorkspace = try await handle.discovery.refresh()
        let incrementalResults = try await handle.discovery.search(SearchRequest(
            query: "precisely bounded",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 20
        ))
        await runtime.shutdown()

        let cleanRuntime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let cleanHandle = try await cleanRuntime.openWorkspace(id: fixture.assignment.id)
        let cleanWorkspace = try await cleanHandle.snapshot()
        let cleanResults = try await cleanHandle.discovery.search(SearchRequest(
            query: "precisely bounded",
            presentationScope: .triptych,
            executionScope: .triptych,
            limit: 20
        ))
        let incrementalDocuments = incrementalWorkspace.vaults.flatMap(\.documents)
        let cleanDocuments = cleanWorkspace.vaults.flatMap(\.documents)
        #expect(incrementalDocuments.map(\.id) == cleanDocuments.map(\.id))
        #expect(incrementalDocuments.map(\.fingerprint) == cleanDocuments.map(\.fingerprint))
        #expect(incrementalDocuments.map(\.lifecycle) == cleanDocuments.map(\.lifecycle))
        #expect(incrementalWorkspace.discovery.catalog.graph?.diagnostics
            == cleanWorkspace.discovery.catalog.graph?.diagnostics)
        let incrementalNoteResults = incrementalResults.results.compactMap {
            result -> NoteSearchResult? in
            guard case .note(let note) = result else { return nil }
            return note
        }
        let cleanNoteResults = cleanResults.results.compactMap {
            result -> NoteSearchResult? in
            guard case .note(let note) = result else { return nil }
            return note
        }
        #expect(incrementalNoteResults.map(\.vaultID)
            == cleanNoteResults.map(\.vaultID))
        #expect(incrementalNoteResults.map(\.relativePath)
            == cleanNoteResults.map(\.relativePath))
        await cleanRuntime.shutdown()
    }

    @Test("Library projection defers Search offsets without rereading source")
    func sourceCatalogDefersSearchProjection() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let services = await handle.services
        let catalog = VaultSourceCatalog(
            repository: try #require(
                services.repositories[fixture.analysisNoteID.vaultID]
            ),
            vaultRole: .sourceCorpus
        )

        let library = try await catalog.snapshot(
            refreshFolders: false,
            projectionRequirement: .library
        )
        #expect(!library.documents.isEmpty)
        #expect(library.semantics.count == library.documents.count)
        #expect(library.searchProjections.isEmpty)
        #expect(library.measurement.readFiles == library.documents.count)
        #expect(library.measurement.projectedDocuments == 0)

        let search = try await catalog.snapshot(
            refreshFolders: false,
            projectionRequirement: .search
        )
        #expect(search.documents.map(\.fingerprint) == library.documents.map(\.fingerprint))
        #expect(search.searchProjections.count == search.documents.count)
        #expect(search.measurement.readFiles == 0)
        #expect(search.measurement.parsedDocuments == 0)
        #expect(search.measurement.projectedDocuments == search.documents.count)
        await runtime.shutdown()
    }

    @Test("A failed source reconcile retains the prior complete catalog generation")
    func failedCatalogReconcileIsTransactional() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        let failureURL = fixture.analysesURL.appendingPathComponent("Z-Failure.md")
        let failureSource = "# Failure sentinel\n\nOriginal.\n"
        try Data(failureSource.utf8).write(to: failureURL)
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL,
            workspaceRegistryStorageURL: fixture.registryStorageURL
        )
        let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
        let services = await handle.services
        let catalog = try #require(
            services.sourceCatalogs[fixture.analysisNoteID.vaultID]
        )
        let initial = try await catalog.snapshot(refreshFolders: false)
        let initialGeneration = initial.generation
        let initialTarget = try #require(initial.documents.first {
            $0.relativePath == fixture.analysisNoteID.relativePath
        })
        let targetURL = fixture.analysesURL.appendingPathComponent(
            fixture.analysisNoteID.relativePath
        )
        try Data("# Changed during failed reconcile\n".utf8).write(to: targetURL)
        try Data([0xFF, 0xFE, 0xFF]).write(to: failureURL)

        await #expect(throws: (any Error).self) {
            try await catalog.reconcile()
        }
        try Data(failureSource.utf8).write(to: failureURL)
        let retained = try await catalog.snapshot(refreshFolders: false)
        #expect(retained.generation == initialGeneration)
        #expect(retained.documents.first {
            $0.relativePath == fixture.analysisNoteID.relativePath
        }?.fingerprint == initialTarget.fingerprint)

        try await catalog.reconcile()
        let repaired = try await catalog.snapshot(refreshFolders: false)
        #expect(repaired.generation > initialGeneration)
        #expect(repaired.documents.first {
            $0.relativePath == fixture.analysisNoteID.relativePath
        }?.fingerprint != initialTarget.fingerprint)
        await runtime.shutdown()
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

private actor OpeningActivationReconciliationGate {
    private var arrived = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        arrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilArrived() async {
        if arrived { return }
        await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
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
