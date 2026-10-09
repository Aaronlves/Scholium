import Combine
import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApp

@Suite("Library browsing preserves Inspector context", .serialized)
@MainActor
struct LibraryInspectorLifecycleTests {
    @Test("Role-only browsing commits Library once without refreshing either Inspector pane")
    func roleBrowsingRetainsResearchContext() async throws {
        try await withFixture { fixture in
            let window = try await fixture.makeWindow()
            let peer = try await fixture.makeWindow()
            let retained = try await RetainedContext.capture(window)
            let peerContext = try await RetainedContext.capture(peer, query: "independent")
            try await fixture.finishStartupPublication()
            let probe = try fixture.observe(window)
            let peerProbe = try fixture.observe(peer)
            #expect(window.researchController !== peer.researchController)
            #expect(retained.session !== peerContext.session)

            for (index, role) in [WorkspaceVaultSlot.topicKnowledge, .output, .paperAnalysis].enumerated() {
                try await window.prepareWorkspaceSelection(role, sourceScope: .library)
                await drainScheduledWork()
                let vault = try #require(fixture.capabilities.assignment.vault(for: role))
                #expect(window.currentRegisteredVault?.id == vault.id)
                #expect(window.shellState.selectedWorkspace == role)
                #expect(window.notes.allSatisfy { $0.workspaceSnapshot?.id.vaultID == vault.id })
                retained.check(window)
                peerContext.check(peer)
                #expect(peer.shellState.selectedWorkspace == .paperAnalysis)
                #expect(probe.counts.projectionPublications == index + 1)
                probe.expectNoRefreshOrResearchPublication()
                #expect(peerProbe.counts.projectionPublications == 0)
                peerProbe.expectNoRefreshOrResearchPublication()
            }
            #expect(try String(contentsOf: fixture.analyses.appendingPathComponent("Shared.md"), encoding: .utf8) == Fixture.source)
        }
    }

    @Test("Rejected and superseded staged role selections preserve the existing panes")
    func unsuccessfulBrowsingPreservesContext() async throws {
        try await withFixture { fixture in
            let window = try await fixture.makeWindow()
            let retained = try await RetainedContext.capture(window)
            try await fixture.finishStartupPublication()
            let probe = try fixture.observe(window)
            let originalVault = window.currentRegisteredVault?.id
            let originalNotes = window.notes.map(\.relativePath)

            do {
                try await window.prepareWorkspaceSelection(.topicKnowledge, sourceScope: .library) {
                    throw RejectedDestination()
                }
                Issue.record("A rejected destination committed its Library selection")
            } catch is RejectedDestination {}

            var replacement: DiscoveryLibraryRequest?
            do {
                try await window.prepareWorkspaceSelection(.topicKnowledge, sourceScope: .library) {
                    // Supersede after staging, immediately before the guarded commit.
                    replacement = window.discoveryController.beginLibraryRequest(
                        workspaceSlot: .topicKnowledge, sourceScope: .library,
                        presentation: .stagedReplacement)
                }
                Issue.record("An obsolete destination committed after its request was replaced")
            } catch is CancellationError {}
            let currentRequest = try #require(replacement)
            #expect(window.discoveryController.isCurrentLibraryRequest(currentRequest))
            #expect(window.discoveryController.receiveLibraryResult(for: currentRequest))
            await drainScheduledWork()
            #expect(window.currentRegisteredVault?.id == originalVault)
            #expect(window.shellState.selectedWorkspace == .paperAnalysis)
            #expect(window.notes.map(\.relativePath) == originalNotes)
            retained.check(window)
            #expect(probe.counts.projectionPublications == 0)
            probe.expectNoRefreshOrResearchPublication()
        }
    }

    @Test("A real source refresh still updates Links after Library-only browsing")
    func sourceRefreshStillPublishes() async throws {
        try await withFixture { fixture in
            let window = try await fixture.makeWindow()
            let retained = try await RetainedContext.capture(window)
            try await window.prepareWorkspaceSelection(.topicKnowledge, sourceScope: .library)
            await drainScheduledWork()
            let active = try #require(window.selectedDocument)
            let before = PreparedConnectionsProjection(
                graph: window.linkGraph, catalogNotes: window.workspaceCatalog?.notes,
                current: active)
            #expect(before.groups(direction: .outgoing, query: "").flatMap(\.items).count == 1)
            let generation = window.linkGraph?.generation
            let changed = Fixture.source + "\nA second authored occurrence: [[Peer]].\n"
            try Data(changed.utf8).write(to: fixture.analyses.appendingPathComponent("Shared.md"))
            let refreshed = try #require(await window.refreshAfterResearchHandoff())
            let after = PreparedConnectionsProjection(
                graph: window.linkGraph, catalogNotes: window.workspaceCatalog?.notes,
                current: active)
            let updatedItems = after.groups(direction: .outgoing, query: "").flatMap(\.items)
            #expect(updatedItems.count == 2)
            #expect(updatedItems.allSatisfy { $0.source?.fingerprint == DocumentFingerprint(content: changed) })
            #expect(before.groups(direction: .outgoing, query: "").flatMap(\.items).count == 1)
            #expect(window.linkGraph?.generation == refreshed.discovery.catalog.graph?.generation)
            #expect(window.linkGraph?.generation != generation)
            #expect(
                window.workspaceCatalog?.notes.first { $0.reference.vaultID == active.vaultID && $0.reference.relativePath == active.relativePath }?.fingerprint
                    == DocumentFingerprint(content: changed))
            #expect(window.shellState.selectedWorkspace == .topicKnowledge)
            #expect(window.selectedDocument == active)
            #expect(window.documentController.session(for: retained.document.editingTarget) === retained.session)
            #expect(window.researchController.linksInspector.location(for: retained.locationKey) == retained.location)
            #expect(window.researchController.linksInspector.direction == .outgoing)
        }
    }

    @Test("A staged role cannot overwrite a newer accepted source inventory", arguments: [false, true])
    func newerSourceWinsOverStagedRole(deleteDestination: Bool) async throws {
        try await withFixture { fixture in
            let window = try await fixture.makeWindow()
            let retained = try await RetainedContext.capture(window)
            let targetVault = try #require(fixture.capabilities.assignment.vault(for: .topicKnowledge))
            let staged = try await window.stageRegisteredVault(targetVault, slot: .topicKnowledge)
            let target = fixture.topics.appendingPathComponent("Shared.md")
            let changed = "# Revised Topic\n\nNew exact source and [[Shared]].\n"
            if deleteDestination {
                try FileManager.default.removeItem(at: target)
            } else {
                try Data(changed.utf8).write(to: target)
            }
            let refreshed = try #require(await window.refreshAfterResearchHandoff())
            let accepted = try #require(refreshed.vault(id: targetVault.id))
            let graphGeneration = window.linkGraph?.generation
            let selected = try window.commitStagedWorkspaceLibrarySelection(staged)
            #expect(selected.identityRecovery.identities == accepted.identityRecovery.identities)
            let committed = try #require(window.workspaceProjectionController.vaultSnapshot(id: targetVault.id))
            #expect(committed.documents.map(\.id) == accepted.documents.map(\.id))
            #expect(window.notes.map(\.relativePath).sorted() == accepted.documents.map { $0.id.relativePath }.sorted())
            #expect(committed.identityRecovery.identities == accepted.identityRecovery.identities)
            if deleteDestination {
                #expect(window.notes.isEmpty)
            } else {
                #expect(window.notes.first?.workspaceSnapshot?.fingerprint == DocumentFingerprint(content: changed))
                #expect(committed.documents.first?.fingerprint == DocumentFingerprint(content: changed))
            }
            #expect(window.linkGraph?.generation == graphGeneration)
            #expect(window.linkGraph?.generation == refreshed.discovery.catalog.graph?.generation)
            retained.check(window)
        }
    }

    private struct RejectedDestination: Error {}

    /// Yield queued main-actor debounce tasks without waiting for the production delay.
    private static func drainScheduledWork() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private func drainScheduledWork() async { await Self.drainScheduledWork() }

    private func withFixture(_ body: (Fixture) async throws -> Void) async throws {
        let fixture = try await Fixture.make()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        do {
            try await body(fixture)
            await fixture.shutdown()
        } catch {
            await fixture.shutdown()
            throw error
        }
    }

    @MainActor
    private final class Fixture {
        static let source = "# Analysis\n\nOriginal authored context: [[Peer]].\n"
        let root: URL
        let analyses: URL
        let topics: URL
        let store: WorkspaceStore
        let capabilities: WindowWorkspaceCapabilities
        let snapshot: WorkspaceSnapshot
        private var windows: [WindowModel] = []

        private init(root: URL, store: WorkspaceStore, capabilities: WindowWorkspaceCapabilities, snapshot: WorkspaceSnapshot) {
            self.root = root
            analyses = root.appendingPathComponent("Triptych/Analyses")
            topics = root.appendingPathComponent("Triptych/Topics")
            self.store = store
            self.capabilities = capabilities
            self.snapshot = snapshot
        }

        static func make() async throws -> Fixture {
            let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let root = repository.appendingPathComponent(".build/library-inspector-lifecycle/\(UUID())")
            var store: WorkspaceStore?
            do {
                let triptych = root.appendingPathComponent("Triptych")
                let analyses = triptych.appendingPathComponent("Analyses")
                let topics = triptych.appendingPathComponent("Topics")
                let works = triptych.appendingPathComponent("Works")
                for directory in [analyses, topics, works] {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                }
                try Data(source.utf8).write(to: analyses.appendingPathComponent("Shared.md"))
                try Data("Exact material.\n".utf8).write(to: analyses.appendingPathComponent("Peer.md"))
                try Data("# Topic\n\nDifferent same-path source.\n".utf8).write(to: topics.appendingPathComponent("Shared.md"))
                try Data("# Work\n\nIndependent writing.\n".utf8).write(to: works.appendingPathComponent("Shared.md"))
                let created = try WorkspaceStore(applicationSupportURL: root.appendingPathComponent("Support"))
                store = created
                let capabilities = try await created.configureTriptychCapabilities(
                    paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                    portableContainerURL: triptych, triptychName: "Library Inspector fixture")
                let snapshot = try await capabilities.discovery.refresh()
                await LibraryInspectorLifecycleTests.drainScheduledWork()
                return Fixture(root: root, store: created, capabilities: capabilities, snapshot: snapshot)
            } catch {
                await store?.shutdownApplicationRuntime()
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }

        func makeWindow() async throws -> WindowModel {
            let window = WindowModel(workspaceStore: store, requestedTriptychID: capabilities.id)
            windows.append(window)
            await window.refreshWorkspaceAssignment(preferredTriptychID: capabilities.id)
            try await window.openWorkspaceVault(.paperAnalysis)
            window.documentController.rememberPresentationMode(.read)
            try await window.openNote("Shared.md")
            await window.libraryRevealTask?.value
            await LibraryInspectorLifecycleTests.drainScheduledWork()
            return window
        }

        func finishStartupPublication() async throws {
            // Refresh returns from Application before its asynchronous event
            // reaches WorkspaceStore. Establish that delivery boundary before
            // counting role-only publications, keeping live observers enabled.
            let ready = try await capabilities.discovery.refresh()
            let generation = try #require(ready.discovery.catalog.graph?.generation)
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while (store.workspaceSnapshots[capabilities.id]?.discovery.catalog.graph?.generation ?? -1) < generation {
                try #require(ContinuousClock.now < deadline, "Startup snapshot was not delivered")
                try await Task.sleep(for: .milliseconds(1))
            }
            await LibraryInspectorLifecycleTests.drainScheduledWork()
        }

        func observe(_ window: WindowModel) throws -> ProjectionProbe {
            let latest = store.workspaceSnapshots[capabilities.id] ?? snapshot
            return ProjectionProbe(
                window: window, snapshot: latest, runtimeIdentity: capabilities.runtimeIdentity,
                generation: store.workspaceEvents[capabilities.id]?.generation ?? 0)
        }

        func shutdown() async {
            for window in windows {
                window.libraryRevealTask?.cancel()
                window.documentTransitionCoordinator.cancelAll()
                window.researchController.unbind()
                window.workspaceProjectionController.reset()
                window.workspaceCancellables.removeAll()
                window.windowWorkspaceController.cancelAll()
                for tab in window.documentTabController.tabs {
                    window.documentController.session(for: tab.document.editingTarget).cancelScheduledWork()
                }
            }
            await store.shutdownApplicationRuntime()
            windows.removeAll()
        }
    }

    @MainActor
    private final class ProjectionProbe {
        final class Counts {
            var catalogReads = 0
            var scheduledRefreshes = 0
            var refreshingPublications = 0
            var projectionPublications = 0
            var linksPublications = 0
            var cardPublications = 0
            var seedPublications = 0
            var loadingPublications = 0
        }
        let counts = Counts()
        private var observations: Set<AnyCancellable> = []

        init(window: WindowModel, snapshot: WorkspaceSnapshot, runtimeIdentity: TriptychRuntimeIdentity, generation: UInt64) {
            let counts = counts
            let controller = WindowWorkspaceProjectionController(
                catalogRefreshDelay: .zero,
                sleep: { _ in counts.scheduledRefreshes += 1 },
                loadCatalog: { [weak window] in
                    counts.catalogReads += 1
                    guard let window else { throw CancellationError() }
                    return try await window.discoveryController.discoverySnapshot().catalog
                })
            _ = controller.activate(snapshot: snapshot, runtimeIdentity: runtimeIdentity, generation: generation, context: window.workspaceProjectionContext)
            window.workspaceProjectionController = controller
            controller.$state.dropFirst().sink { state in
                counts.projectionPublications += 1
                if state.isRefreshingCatalog { counts.refreshingPublications += 1 }
            }.store(in: &observations)
            window.researchController.linksInspector.objectWillChange.sink {
                counts.linksPublications += 1
            }.store(in: &observations)
            let materials = window.researchController.relatedMaterials
            materials.$cards.dropFirst().sink { _ in counts.cardPublications += 1 }.store(in: &observations)
            materials.$seed.dropFirst().sink { _ in counts.seedPublications += 1 }.store(in: &observations)
            materials.$isLoading.dropFirst().sink { _ in counts.loadingPublications += 1 }.store(in: &observations)
        }

        func expectNoRefreshOrResearchPublication() {
            #expect(counts.catalogReads == 0)
            #expect(counts.scheduledRefreshes == 0)
            #expect(counts.refreshingPublications == 0)
            #expect(counts.linksPublications == 0)
            #expect(counts.cardPublications == 0)
            #expect(counts.seedPublications == 0)
            #expect(counts.loadingPublications == 0)
        }
    }

    @MainActor
    private struct RetainedContext {
        let document: WindowSelectedDocument
        let session: DocumentSessionModel
        let mode: NotePresentationMode
        let inspector: ResearchInspectorState
        let research: ResearchController
        let links: LinksInspectorSession
        let related: RelatedMaterialsSession
        let locationKey: String
        let location: LinksInspectorSession.Location
        let seedID: UUID
        let cards: [RelatedMaterialCard]

        static func capture(_ window: WindowModel, query: String = "Peer") async throws -> Self {
            let document = try #require(window.documentController.selectedDocument)
            let descriptor = try #require(document.workspaceDescriptor)
            let current = try #require(window.selectedDocument)
            let research = window.researchController
            research.showResearchInspector(true)
            research.selectInspectorMode(.related)
            research.linksInspector.direction = .outgoing
            let groups = InspectorLinkGroup.make(
                ConnectionsProjection.make(
                    graph: window.linkGraph, catalogNotes: window.workspaceCatalog?.notes,
                    current: current, direction: .outgoing
                ).items)
            let group = try #require(groups.first)
            let key = "\(current.vaultID.uuidString):\(current.relativePath):outgoing"
            research.linksInspector.update(key) {
                $0.query = query
                $0.collapsedGroups = [group.id]
                $0.scrollID = group.id
            }
            let peer = try #require(window.workspaceCatalog?.notes.first { $0.reference.relativePath == "Peer.md" })
            let seedSnapshot = RelatedContentSeedSnapshot(noteID: current, source: Fixture.source)
            let seed = RelatedMaterialsSeed(
                request: .init(seed: seedSnapshot),
                attachment: .init(
                    noteID: descriptor.sessionKey.noteID, vaultID: current.vaultID, relativePath: current.relativePath,
                    text: Fixture.source, fingerprint: seedSnapshot.fingerprint, sourceLine: 1))
            let candidate = RelatedContentCandidate(
                note: .init(vaultID: peer.reference.vaultID, relativePath: peer.reference.relativePath),
                vaultRole: peer.reference.vaultRole, title: peer.title, fingerprint: peer.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [.body], seedMatches: [])))
            let passage = RelatedContentPassage(
                candidate: candidate,
                range: .init(utf16LowerBound: 0, utf16UpperBound: 15, line: 1, column: 1, endLine: 1, endColumn: 16),
                source: "Exact material.", displayText: "Exact material.", excerpt: "Exact material.", excerptMatches: [], matches: [])
            await research.relatedMaterials.find(
                capture: { seed },
                retrieve: { request in
                    .init(
                        requestID: request.id, seedFingerprint: request.seed.fingerprint, freshnessToken: .init("fixture"),
                        availability: .unavailable, state: .current, identityCandidates: [], lexicalCandidates: [candidate],
                        identityHasMore: false, lexicalHasMore: false, passages: [passage])
                }, references: [peer.reference]
            ).value
            #expect(research.relatedMaterials.cards.count == 1)
            return Self(
                document: document, session: window.documentController.session(for: document.editingTarget),
                mode: window.presentedDocumentMode, inspector: window.shellState.inspector,
                research: research, links: research.linksInspector, related: research.relatedMaterials,
                locationKey: key, location: research.linksInspector.location(for: key),
                seedID: seed.request.id, cards: research.relatedMaterials.cards)
        }

        func check(_ window: WindowModel) {
            #expect(window.documentController.selectedDocument == document)
            #expect(window.documentController.session(for: document.editingTarget) === session)
            #expect(window.presentedDocumentMode == mode)
            #expect(window.shellState.inspector == inspector)
            #expect(window.researchController === research)
            #expect(window.researchController.linksInspector === links)
            #expect(window.researchController.relatedMaterials === related)
            #expect(links.direction == .outgoing)
            #expect(links.location(for: locationKey) == location)
            #expect(related.seed?.request.id == seedID)
            #expect(related.cards == cards)
            #expect(!related.isLoading)
        }
    }
}
