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

    enum PendingDocument: CaseIterable { case dirty, failedSave, conflict, composing }

    @Test("The Library selector browses roles without preparing the retained document", arguments: PendingDocument.allCases)
    func roleSelectorPreservesPendingDocument(pending: PendingDocument) async throws {
        try await withFixture { fixture in
            let window = try await fixture.makeWindow()
            let document = try #require(window.documentController.selectedDocument)
            let session = window.documentController.session(for: document.editingTarget)
            window.rememberPresentationMode(.source)
            session.originalEditingSource = Fixture.source
            session.editingRevision = DocumentFingerprint(content: Fixture.source)
            session.preparePresentationMode(.source)
            let editor = session.editorSession
            editor.loadDocument(Fixture.source, documentID: editor.bridgeDocumentID, mode: .source)
            let addition = "Unsaved 中文 e\u{301} 🦉.\n"
            let end = EditorSourceOffsetMap(source: Fixture.source).editorUTF16Length
            try #require(
                editor.acceptEditorChanges(
                    [.init(from: end, to: end, insert: addition, exactInsert: addition)],
                    baseGeneration: 0, resultingGeneration: 1))
            let draft = Fixture.source + addition
            session.editingSource = draft
            let selection = MarkdownEditorSelectionRange(anchor: 3, head: 7)
            try #require(
                editor.updateInteraction(
                    selections: [selection], line: 1, column: 8, lineCount: 5,
                    documentVersion: editor.generation, interactionRevision: 1, focusTarget: .editor,
                    context: MarkdownEditorContext(
                        selections: [selection], activeInlineConstructs: [], activeBlockConstructs: [],
                        composing: pending == .composing, availableCommands: [], undoLabel: "Typing", redoLabel: nil)))
            switch pending {
            case .dirty, .composing: break
            case .failedSave:
                session.editError = "Synthetic save failure"
                session.canRetrySave = true
            case .conflict:
                session.conflict = DocumentConflictSnapshot(
                    relativePath: document.relativePath, editorSource: draft, diskSource: "Different disk revision\n",
                    baseRevision: DocumentFingerprint(content: Fixture.source))
            }
            // Session mode changes publish chrome asynchronously. Establish the
            // intended Source baseline before capturing what browsing must retain.
            try await fixture.finishStartupPublication()
            try #require(window.presentedDocumentMode == .source)
            let retained = try await RetainedContext.capture(window)
            retained.check(window)
            let originalError = session.editError
            let originalConflict = session.conflict
            let focusRevision = editor.focusRequestRevision
            let generation = editor.generation
            let context = editor.context
            let originalSaveError = window.lastSaveError

            window.requestTriptychWorkspace(.topicKnowledge)
            await window.documentTransitionCoordinator.waitForIdle()

            #expect(window.shellState.selectedWorkspace == .topicKnowledge)
            #expect(window.currentRegisteredVault?.id == fixture.capabilities.assignment.vault(for: .topicKnowledge)?.id)
            #expect(window.requestedWorkspaceSelection == nil)
            #expect(session.retainedExactSource.utf8.elementsEqual(draft.utf8))
            #expect(editor.checkedSource.utf8.elementsEqual(draft.utf8))
            #expect(session.hasUnsavedChanges)
            #expect(session.editError == originalError && session.conflict == originalConflict)
            #expect(window.lastSaveError == originalSaveError)
            #expect(editor.detachmentSuspensionID == nil)
            #expect(editor.generation == generation && editor.focusRequestRevision == focusRevision)
            #expect(editor.context == context)
            #expect(editor.context?.selections == [selection])
            #expect(editor.isComposing == (pending == .composing))
            #expect(try Data(contentsOf: fixture.analyses.appendingPathComponent("Shared.md")) == Data(Fixture.source.utf8))
            retained.check(window)
        }
    }

    @Test("Repeated, superseded and canceled Library intents preserve the selected document")
    func roleSelectorRequestLifetime() async throws {
        try await withFixture { fixture in
            let window = try await fixture.makeWindow()
            let retained = try await RetainedContext.capture(window)
            try await fixture.finishStartupPublication()
            window.requestTriptychWorkspace(.topicKnowledge)
            window.requestTriptychWorkspace(.topicKnowledge)
            window.requestTriptychWorkspace(.output)
            window.requestTriptychWorkspace(.topicKnowledge)
            await window.documentTransitionCoordinator.waitForIdle()
            #expect(window.shellState.selectedWorkspace == .topicKnowledge)
            #expect(window.requestedWorkspaceSelection == nil)
            retained.check(window)

            window.requestTriptychWorkspace(.output)
            window.documentTransitionCoordinator.cancelAll()
            await window.documentTransitionCoordinator.waitForIdle()
            #expect(window.shellState.selectedWorkspace == .topicKnowledge)
            #expect(window.requestedWorkspaceSelection == nil)
            retained.check(window)

            window.requestTriptychWorkspace(.output)
            await window.documentTransitionCoordinator.waitForIdle()
            #expect(window.shellState.selectedWorkspace == .output)
            #expect(window.requestedWorkspaceSelection == nil)
            retained.check(window)
        }
    }

    /// Measures queue admission through committed window Library projection.
    /// AppKit/SwiftUI layout and paint are outside this model boundary.
    @Test(
        "Measure role browsing with a retained dirty source at realistic corpus sizes",
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_LIBRARY_BROWSING"] == "1"),
        arguments: [500, 5_000])
    func roleBrowsingMeasurement(noteCount: Int) async throws {
        try await withFixture(noteCount: noteCount) { fixture in
            let window = try await fixture.makeWindow()
            let document = try #require(window.documentController.selectedDocument)
            let session = window.documentController.session(for: document.editingTarget)
            session.suppressAutosave = true
            session.originalEditingSource = Fixture.source
            session.editingRevision = DocumentFingerprint(content: Fixture.source)
            session.preparePresentationMode(.source)
            window.rememberPresentationMode(.source)
            let editor = session.editorSession
            editor.loadDocument(Fixture.source, documentID: editor.bridgeDocumentID, mode: .source)
            let addition = "Unsaved bilingual research paragraph. 未保存的研究文字。\n"
            let end = EditorSourceOffsetMap(source: Fixture.source).editorUTF16Length
            try #require(
                editor.acceptEditorChanges(
                    [.init(from: end, to: end, insert: addition, exactInsert: addition)],
                    baseGeneration: 0, resultingGeneration: 1))
            let draft = Fixture.source + addition
            session.editingSource = draft
            let selection = MarkdownEditorSelectionRange(anchor: 3, head: 7)
            try #require(
                editor.updateInteraction(
                    selections: [selection], line: 1, column: 8, lineCount: 5,
                    documentVersion: editor.generation, interactionRevision: 1, focusTarget: .editor,
                    context: MarkdownEditorContext(
                        selections: [selection], activeInlineConstructs: [], activeBlockConstructs: [],
                        composing: false, availableCommands: [], undoLabel: "Typing", redoLabel: nil)))
            let retained = try await RetainedContext.capture(window)
            try await fixture.finishStartupPublication()
            try #require(window.workspaceProjectionController.vaultSnapshotsByID.values.reduce(0) { $0 + $1.documents.count } == noteCount)
            let probe = try fixture.observe(window)
            let generation = editor.generation
            let focusRevision = editor.focusRequestRevision
            let roles: [(String, WorkspaceVaultSlot)] = [("topics", .topicKnowledge), ("works", .output), ("analyses", .paperAnalysis)]
            var samples: [String: [Double]] = [:]
            var sortOrders: [String: String] = [:]
            for iteration in 0..<12 {
                for (label, role) in roles {
                    let start = ContinuousClock.now
                    window.requestTriptychWorkspace(role)
                    await window.documentTransitionCoordinator.waitForIdle()
                    let committed = ContinuousClock.now
                    let visible = window.filteredNotes
                    let ready = ContinuousClock.now
                    if iteration >= 3 {
                        samples["queue:" + label, default: []].append(Self.milliseconds(start.duration(to: committed)))
                        samples["ordering:" + label, default: []].append(Self.milliseconds(committed.duration(to: ready)))
                        samples["ready:" + label, default: []].append(Self.milliseconds(start.duration(to: ready)))
                    }
                    sortOrders[label] = window.discoveryController.library.sortOrder.rawValue
                    #expect(visible.count == window.notes.count)
                    // Correctness checks and source readback are excluded from elapsed.
                    #expect(window.shellState.selectedWorkspace == role)
                    #expect(window.requestedWorkspaceSelection == nil)
                    #expect(window.currentRegisteredVault?.id == fixture.capabilities.assignment.vault(for: role)?.id)
                    #expect(editor.checkedSource.utf8.elementsEqual(draft.utf8) && session.hasUnsavedChanges)
                    #expect(editor.generation == generation && editor.focusRequestRevision == focusRevision)
                    #expect(editor.context?.selections == [selection])
                    #expect(editor.detachmentSuspensionID == nil)
                    #expect(try Data(contentsOf: fixture.analyses.appendingPathComponent("Shared.md")) == Data(Fixture.source.utf8))
                    retained.check(window)
                }
            }
            probe.expectNoRefreshOrResearchPublication()
            #expect(probe.counts.projectionPublications == 36)
            for (label, _) in roles {
                for boundary in ["queue", "ordering", "ready"] {
                    Self.printLibraryMeasurement(
                        label, boundary: boundary, sortOrder: sortOrders[label] ?? "unavailable", noteCount: noteCount,
                        samples: samples[boundary + ":" + label, default: []])
                }
            }
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func printLibraryMeasurement(_ role: String, boundary: String, sortOrder: String, noteCount: Int, samples: [Double]) {
        let sorted = samples.sorted()
        let mean = samples.reduce(0, +) / Double(samples.count)
        let standardDeviation = (samples.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(samples.count)).squareRoot()
        let formatted: (Double) -> String = { String(format: "%.4f", $0) }
        print(
            "LIBRARY_BROWSING_MEASURE boundary=\(boundary) sort=\(sortOrder) notes=\(noteCount) role=\(role) warmups=3 samples=\(samples.count)"
                + " median_ms=\(formatted(sorted[sorted.count / 2])) mean_ms=\(formatted(mean)) stddev_ms=\(formatted(standardDeviation))"
                + " min_ms=\(formatted(sorted.first!)) max_ms=\(formatted(sorted.last!)) raw_ms=\(samples.map(formatted).joined(separator: ","))")
    }

    private struct RejectedDestination: Error {}

    /// Yield queued main-actor debounce tasks without waiting for the production delay.
    private static func drainScheduledWork() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private func drainScheduledWork() async { await Self.drainScheduledWork() }

    private func withFixture(noteCount: Int = 4, _ body: (Fixture) async throws -> Void) async throws {
        let fixture = try await Fixture.make(noteCount: noteCount)
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

        static func make(noteCount: Int = 4) async throws -> Fixture {
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
                // Real source-backed summaries distributed across all roles.
                // Setup/index construction is intentionally outside timed browsing.
                for index in 0..<max(0, noteCount - 4) {
                    let directory = [analyses, topics, works][index % 3]
                        .appendingPathComponent("Section-\((index / 3) % 20)")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let paragraphs = (0..<12).map { paragraph in
                        "Synthetic research paragraph \(paragraph) on topic \(index % 31). 中文语境 retains authored prose and [[Peer]]{{A source-owned note.}}."
                    }.joined(separator: "\n\n")
                    let body =
                        "---\ntitle: 'Synthetic Research \(index)'\nauthor: 'Researcher \(index % 19)'\nkeywords: [ethics, topic-\(index % 31)]\nstatus: draft\n---\n\n# Synthetic \(index)\n\n\(paragraphs)\n"
                    try Data(body.utf8).write(to: directory.appendingPathComponent("Research-\(index).md"))
                }
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
