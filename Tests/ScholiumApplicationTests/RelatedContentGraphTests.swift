import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

@Suite("Related-content authored graph paths")
struct RelatedContentGraphTests {
    @Test("Direct and reverse traversal retain the actual authored source occurrence")
    func directAndIncoming() async throws {
        let outgoing = GraphFixture(["Seed.md": "Context [[Target]].", "Target.md": "Target text."])
        let direct = try #require(try await outgoing.result()?.contexts[outgoing.id("Target.md")])
        #expect(direct.proximity == 1 && direct.paths.count == 1)
        #expect(direct.paths[0].steps[0].source == outgoing.id("Seed.md"))
        #expect(direct.paths[0].steps[0].traversal == .outgoing)
        let incoming = GraphFixture(["Seed.md": "Context text.", "Target.md": "Target [[Seed]]."])
        let reverse = try #require(try await incoming.result()?.contexts[incoming.id("Target.md")])
        #expect(reverse.proximity == 1)
        #expect(reverse.paths[0].steps[0].source == incoming.id("Target.md"))
        #expect(reverse.paths[0].steps[0].destination == incoming.id("Seed.md"))
        #expect(reverse.paths[0].steps[0].traversal == .incoming)
        #expect(reverse.paths[0].steps[0].occurrence.target == "Seed")
    }

    @Test("All four two-step traversal directions work without inventing directed edges")
    func allDirections() async throws {
        let cases: [(String, String, String, [RelatedContentGraphTraversal])] = [
            ("Context [[Middle]].", "Middle [[Target]].", "Target text.", [.outgoing, .outgoing]),
            ("Context [[Middle]].", "Middle text.", "Target [[Middle]].", [.outgoing, .incoming]),
            ("Context text.", "Middle [[Seed]] [[Target]].", "Target text.", [.incoming, .outgoing]),
            ("Context text.", "Middle [[Seed]].", "Target [[Middle]].", [.incoming, .incoming]),
        ]
        for (seed, middle, target, expected) in cases {
            let fixture = GraphFixture(["Seed.md": seed, "Middle.md": middle, "Target.md": target])
            let context = try #require(try await fixture.result()?.contexts[fixture.id("Target.md")])
            #expect(context.proximity == 0.25)
            #expect(context.paths.count == 1)
            #expect(context.paths[0].steps.map(\.traversal) == expected)
            for step in context.paths[0].steps {
                #expect(fixture.graph.outgoing[step.source]?.contains { $0.occurrence == step.occurrence && $0.destination?.note == step.destination } == true)
            }
        }
    }

    @Test("Three-hop targets and cycles never become two-hop candidates or return the seed")
    func distanceAndCycles() async throws {
        let fixture = GraphFixture([
            "Seed.md": "Context [[Seed]] [[Middle]].", "Middle.md": "Middle [[Seed]] [[Near]].",
            "Near.md": "Near [[Far]].", "Far.md": "Far text.",
        ])
        let result = try #require(try await fixture.result(existing: ["Far.md"]))
        #expect(result.contexts[fixture.id("Seed.md")] == nil)
        #expect(result.contexts[fixture.id("Middle.md")]?.proximity == 1)
        #expect(result.contexts[fixture.id("Near.md")]?.proximity == 0.25)
        #expect(result.contexts[fixture.id("Far.md")] == nil)
        #expect(result.candidates.allSatisfy { $0.note != fixture.id("Seed.md") })
    }

    @Test("Repeated and reciprocal occurrences do not multiply proximity or degree")
    func deduplication() async throws {
        let ordinary = GraphFixture(["Seed.md": "Context [[Middle]].", "Middle.md": "Middle [[Target]].", "Target.md": "Target text."])
        let repeated = GraphFixture([
            "Seed.md": "Context [[Middle]] [[Middle]] [[Middle]].",
            "Middle.md": "Middle [[Seed]] [[Target]] [[Target]].", "Target.md": "Target [[Middle]].",
        ])
        let baseline = try #require(try await ordinary.result()?.contexts[ordinary.id("Target.md")])
        let context = try #require(try await repeated.result()?.contexts[repeated.id("Target.md")])
        #expect(context.proximity == baseline.proximity && context.proximity == 0.25)
        #expect(context.paths.count == 1)
        #expect(context.paths[0].steps[1].occurrence.span.utf16LowerBound < 20)
    }

    @Test("Complete distinct degree discounts hubs even beyond bounded graph-only expansion")
    func hubDiscountAndExpansion() async throws {
        var documents: [String: String] = ["Seed.md": "Context [[Middle]].", "Target.md": "Target text."]
        let extras = (0..<260).map { String(format: "Extra%03d", $0) }
        documents["Middle.md"] = "Middle [[Target]] " + extras.map { "[[\($0)]]" }.joined(separator: " ")
        for extra in extras { documents[extra + ".md"] = "Extra text." }
        let fixture = GraphFixture(documents)
        let result = try #require(try await fixture.result(existing: ["Target.md"]))
        let context = try #require(result.contexts[fixture.id("Target.md")])
        #expect(abs(context.proximity - 0.5 / 262) < 0.0000001)
        #expect(result.candidates.count == RelatedContentContract.maximumGraphCandidates)
        #expect(result.hasMore)
        #expect(!result.candidates.contains { $0.note == fixture.id("Target.md") })
    }

    @Test("Distinct intermediate contributions sum and explanatory paths stay bounded")
    func multiplePaths() async throws {
        let fixture = GraphFixture([
            "Seed.md": "Context [[M1]] [[M2]] [[M3]] [[M4]] [[M5]].",
            "M1.md": "Middle [[Target]].", "M2.md": "Middle [[Target]].", "M3.md": "Middle [[Target]].",
            "M4.md": "Middle [[Target]].", "M5.md": "Middle [[Target]].", "Target.md": "Target text.",
        ])
        let context = try #require(try await fixture.result()?.contexts[fixture.id("Target.md")])
        #expect(context.proximity == 1)
        #expect(context.paths.count == RelatedContentContract.maximumGraphPathsPerCandidate)
        #expect(context.paths.map { $0.steps[0].destination.relativePath } == ["M1.md", "M2.md", "M3.md"])
    }

    @Test("Exact unsaved seed replaces saved outgoing occurrences in forward and reverse walks")
    func unsavedOverlay() async throws {
        let fixture = GraphFixture([
            "Seed.md": "Context [[Old]].", "Old.md": "Old [[OldTarget]].", "OldTarget.md": "Old target.",
            "New.md": "New [[NewTarget]].", "NewTarget.md": "New target.",
        ])
        let source = "Unsaved context [[New]]."
        let result = try #require(try await fixture.result(source: source, existing: ["OldTarget.md"]))
        #expect(result.contexts[fixture.id("Old.md")] == nil)
        #expect(result.contexts[fixture.id("OldTarget.md")] == nil)
        #expect(result.contexts[fixture.id("New.md")]?.proximity == 1)
        #expect(result.contexts[fixture.id("NewTarget.md")]?.proximity == 0.25)
        #expect(result.contexts[fixture.id("New.md")]?.paths[0].steps[0].occurrence.localContext.contains("Unsaved") == true)
        #expect(fixture.graph.outgoing[fixture.id("Seed.md")]?.first?.occurrence.target == "Old")
    }

    @Test("Ambiguous, unresolved and nonresearch intermediates cannot authorize paths")
    func ambiguityAndAccess() async throws {
        let ambiguous = GraphFixture([
            "Seed.md": "Context [[Shared]] [[Missing]].", "one/Shared.md": "One [[Target]].",
            "two/Shared.md": "Two [[Target]].", "Target.md": "Target text.",
        ])
        #expect(try await ambiguous.result()?.contexts.isEmpty == true)
        let inaccessible = GraphFixture(
            ["Seed.md": "Context [[Private]].", "Private.md": "Private [[Target]].", "Target.md": "Target text."],
            roles: ["Private.md": .other])
        #expect(try await inaccessible.result()?.contexts.isEmpty == true)
        let wrongManifest = GraphFixture(["Seed.md": "Context [[Target]].", "Target.md": "Target text."])
        #expect(try await wrongManifest.result(manifest: "incompatible") == nil)
        #expect(try await wrongManifest.result(catalog: Array(wrongManifest.catalog.dropLast())) == nil)
    }

    @Test("Output role filtering does not exclude an authorized intermediate from another research role")
    func roles() async throws {
        let fixture = GraphFixture(
            ["Seed.md": "Context [[Middle]].", "Middle.md": "Middle [[Target]].", "Target.md": "Target text."],
            roles: ["Middle.md": .sourceCorpus])
        let result = try #require(try await fixture.result(candidateRoles: [.topic]))
        #expect(result.contexts[fixture.id("Middle.md")] == nil)
        #expect(result.contexts[fixture.id("Target.md")]?.proximity == 0.25)
        #expect(result.candidates.map(\.note) == [fixture.id("Target.md")])
    }

    @Test("Application uses current graph cohort and enriches verified material without giving links relevance")
    func applicationIntegration() async throws {
        let fixture = try await ApplicationFixture.make()
        defer { fixture.remove() }
        try Data("# Middle\n\n[[Target]]\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("Middle.md"))
        try Data("# Target\n\nAgency requires a deliberate choice.\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("Target.md"))
        try Data("# Unrelated\n\nDifferent subject altogether.\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("Unrelated.md"))
        try Data("# ReverseMiddle\n\n[[Agency]]\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("ReverseMiddle.md"))
        try Data("# ReverseTarget\n\n[[ReverseMiddle]]\n\nAgency involves deliberate choice in this synthetic case.\n".utf8)
            .write(to: fixture.topicsURL.appendingPathComponent("ReverseTarget.md"))
        try Data("# Unregistered\n\nAgency deliberate choice outside registered membership.\n".utf8)
            .write(to: fixture.rootURL.appendingPathComponent("Unregistered.md"))
        let runtime = try await WorkspaceRuntime.snapshot(
            applicationSupportURL: fixture.applicationSupportURL, workspaceRegistryStorageURL: fixture.registryStorageURL)
        do {
            let handle = try await runtime.openWorkspace(id: fixture.assignment.id)
            let response = try await handle.discovery.relatedContent(
                .init(
                    seed: .init(
                        noteID: fixture.analysisNoteID, source: "# Agency\n\nAgency [[Middle]] [[Unrelated]] [[Unregistered]].",
                        focuses: [.init(kind: .selectedPassage, text: "agency deliberate choice")])))
            let target = try #require(response.passages.first { $0.candidate.note.relativePath == "Target.md" })
            #expect(target.candidate.graphContext?.paths.first?.steps.count == 2)
            #expect(target.candidate.graphContext?.proximity == 0.25)
            #expect(!response.passages.contains { $0.candidate.note.relativePath == "Unrelated.md" })
            #expect(
                (response.graphCandidates + response.identityCandidates + response.lexicalCandidates).allSatisfy {
                    $0.note.relativePath != "Unregistered.md"
                })
            #expect(response.graphCandidates.count <= RelatedContentContract.maximumGraphCandidates)
            let reverseResponse = try await handle.discovery.relatedContent(
                .init(
                    seed: .init(
                        noteID: fixture.analysisNoteID, source: "# Agency\n\nAgency context.",
                        focuses: [.init(kind: .selectedPassage, text: "agency deliberate choice")])))
            let reverseTarget = try #require(reverseResponse.passages.first { $0.candidate.note.relativePath == "ReverseTarget.md" })
            #expect(reverseTarget.candidate.graphContext?.paths.first?.steps.map(\.traversal) == [.incoming, .incoming])
            let snapshot = try await handle.snapshot()
            #expect(snapshot.discovery.catalog.graph?.outgoing[fixture.analysisNoteID]?.isEmpty == true)
            await #expect(throws: (any Error).self) {
                try await handle.discovery.relatedContent(
                    .init(
                        seed: .init(
                            noteID: .init(vaultID: UUID(), relativePath: "Unregistered.md"), source: "agency deliberate choice")))
            }
        } catch {
            await runtime.shutdown()
            throw error
        }
        await runtime.shutdown()
    }

    #if DEBUG
        enum GraphPreparationControl: CaseIterable, Equatable, Sendable {
            case unchanged, sourceIdenticalRefresh, changedSourceRefresh, failedRefresh, admittedRefresh, cancel, shutdown

            var observesRefresh: Bool { self == .admittedRefresh || self == .cancel || self == .shutdown }
        }

        @Test(
            "A suspended graph walk revalidates its cohort before any candidate source read",
            .timeLimit(.minutes(1)), arguments: GraphPreparationControl.allCases)
        func graphPreparationAdmission(control: GraphPreparationControl) async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let middle = fixture.topicsURL.appendingPathComponent("Middle.md")
            try Data("# Middle\n\n[[Target]]\n".utf8).write(to: middle)
            try Data("# Target\n\nAgency requires a deliberate choice.\n".utf8)
                .write(to: fixture.topicsURL.appendingPathComponent("Target.md"))
            let runtime: WorkspaceRuntime
            if control.observesRefresh {
                runtime = WorkspaceRuntime(
                    configuration: .live(
                        .init(applicationSupportURL: fixture.applicationSupportURL, workspaceRegistryStorageURL: fixture.registryStorageURL)))
            } else {
                runtime = try await WorkspaceRuntime.snapshot(
                    applicationSupportURL: fixture.applicationSupportURL, workspaceRegistryStorageURL: fixture.registryStorageURL)
            }
            let handle: WorkspaceHandle
            do { handle = try await runtime.openWorkspace(id: fixture.assignment.id) } catch {
                await runtime.shutdown()
                throw error
            }
            let gate = RelatedFinalValidationGate()
            let preflight = RelatedFinalValidationGate()
            let progress = RelatedObservationProgress()
            var query: Task<RelatedContentResponse, Error>?
            var shutdown: Task<Void, Never>?
            do {
                if control.observesRefresh {
                    await handle.openingPresentationDidComplete()
                    await handle.awaitOpeningCompletionForTesting()
                    _ = try await handle.refresh()
                    if let refresh = await handle.liveIndexRefreshTask?.task { await refresh.value }
                }
                let request = RelatedContentRequest(
                    seed: .init(
                        noteID: fixture.analysisNoteID, source: "# Agency\n\nAgency [[Middle]].",
                        focuses: [.init(kind: .selectedPassage, text: "agency deliberate choice")]))
                let original = try await handle.discovery.relatedContent(request)
                try #require(original.state == .current && !original.passages.isEmpty)
                try #require(await handle.lastRelatedContentMeasurement?.graphUsed == true)
                let initial = try await handle.snapshot()
                let initialSearch = try #require(initial.discovery.searchGeneration)
                let readsBefore = await handle.relatedContentSourceLoadAttemptsForTesting
                await handle.setRelatedContentGraphPreparedBarrierForTesting { await gate.holdOnce() }
                let pending = Task {
                    do {
                        let response = try await handle.discovery.relatedContent(request)
                        await progress.finishQuery()
                        await gate.finish()
                        return response
                    } catch {
                        await progress.finishQuery()
                        await gate.finish()
                        throw error
                    }
                }
                query = pending
                try #require(await gate.waitUntilArrived())
                #expect(await handle.relatedContentSourceLoadAttemptsForTesting == readsBefore)
                #expect(await handle.lastRelatedContentMeasurement == nil)
                switch control {
                case .unchanged: break
                case .sourceIdenticalRefresh:
                    let refreshed = try await handle.refresh()
                    #expect(refreshed.discovery.searchGeneration == initialSearch)
                    #expect(refreshed.discovery.catalog.graph?.generation != initial.discovery.catalog.graph?.generation)
                    #expect(refreshed.discovery.catalog.graph?.outgoing == initial.discovery.catalog.graph?.outgoing)
                case .changedSourceRefresh:
                    try Data("# Middle\n\nThe intermediary no longer links to Target.\n".utf8).write(to: middle)
                    let refreshed = try await handle.refresh()
                    #expect(refreshed.discovery.searchGeneration != initialSearch)
                case .failedRefresh:
                    try Data([0xFF, 0xFE, 0xFA]).write(to: fixture.topicsURL.appendingPathComponent("Unreadable.md"))
                    await #expect(throws: (any Error).self) { try await handle.refresh() }
                    #expect(await handle.derivedStateRequiresRefresh)
                case .admittedRefresh, .cancel, .shutdown:
                    await handle.setLiveInventoryPreflightBarrierForTesting { await preflight.holdOnce() }
                    try await runtime.deliverPooledVaultEventForTesting(
                        .reconciliationRequired(sequence: 100), vaultID: fixture.analysisNoteID.vaultID)
                    try #require(await preflight.waitUntilArrived())
                    #expect(await handle.liveIndexRefreshTask != nil)
                }
                // Refresh reads have their own owner. Compare only this query's
                // load attempts after the intervening operation has been admitted.
                let readsBeforeRelease = await handle.relatedContentSourceLoadAttemptsForTesting
                let publicationsBeforeRelease = await handle.events.publishedGeneration
                await gate.release()
                if control.observesRefresh {
                    try await waitForRelatedProbe {
                        let completed = await progress.queryFinished
                        let observing = await handle.relatedContentRefreshWaiters.count == 1
                        return completed || observing
                    }
                    #expect(!(await progress.queryFinished), "An admitted same-source batch escaped observation before completion")
                    #expect(await handle.relatedContentRefreshWaiters.count == 1)
                    #expect(await handle.relatedContentSourceLoadAttemptsForTesting == readsBeforeRelease)
                    #expect(await handle.lastRelatedContentMeasurement == nil)
                    #expect(await handle.liveIndexRefreshTask != nil)
                    switch control {
                    case .cancel: pending.cancel()
                    case .shutdown:
                        shutdown = Task { await runtime.shutdown() }
                        try await waitForRelatedProbe { await handle.isShutDown }
                    default:
                        let sharedRefresh = await handle.liveIndexRefreshTask?.task
                        await preflight.release()
                        await sharedRefresh?.value
                    }
                }
                switch control {
                case .cancel:
                    await #expect(throws: CancellationError.self) { try await pending.value }
                    #expect(await handle.liveIndexRefreshTask != nil, "Cancelling a graph observer cancelled shared refresh work")
                case .shutdown:
                    do {
                        _ = try await pending.value
                        Issue.record("A graph walk returned a response after its Handle shut down")
                    } catch ScholiumApplicationError.workspaceShutDown(let id) {
                        #expect(id == handle.id)
                    }
                default:
                    let response = try await pending.value
                    if control == .unchanged || control == .sourceIdenticalRefresh || control == .admittedRefresh {
                        #expect(response.state == .current && response.availability == .current(initialSearch))
                        #expect(response.passages == original.passages)
                        #expect(response.graphCandidates == original.graphCandidates)
                        #expect(await handle.relatedContentSourceLoadAttemptsForTesting > readsBeforeRelease)
                    } else {
                        #expect(response.state == .stale)
                        #expect(response.identityCandidates.isEmpty && response.lexicalCandidates.isEmpty)
                        #expect(response.graphCandidates.isEmpty && response.passages.isEmpty)
                        if control == .failedRefresh {
                            if case .failed(let lastGood, let reason) = response.availability {
                                #expect(lastGood == initialSearch && !reason.isEmpty)
                            } else {
                                Issue.record("A genuine preparation failure lost its typed availability at graph admission")
                            }
                        }
                    }
                }
                if control != .unchanged && control != .sourceIdenticalRefresh && control != .admittedRefresh {
                    #expect(await handle.relatedContentSourceLoadAttemptsForTesting == readsBeforeRelease)
                    #expect(await handle.lastRelatedContentMeasurement == nil)
                }
                #expect(await gate.entryCount == 1)
                #expect(await handle.events.publishedGeneration == publicationsBeforeRelease)
                #expect(await handle.relatedContentRefreshWaiters.isEmpty)
                if control == .cancel {
                    let sharedRefresh = await handle.liveIndexRefreshTask?.task
                    await preflight.release()
                    await sharedRefresh?.value
                }
                await handle.setRelatedContentGraphPreparedBarrierForTesting(nil)
                await handle.setLiveInventoryPreflightBarrierForTesting(nil)
            } catch {
                query?.cancel()
                await gate.release()
                await preflight.release()
                _ = try? await query?.value
                await handle.setRelatedContentGraphPreparedBarrierForTesting(nil)
                await handle.setLiveInventoryPreflightBarrierForTesting(nil)
                await runtime.shutdown()
                await shutdown?.value
                throw error
            }
            await runtime.shutdown()
            await shutdown?.value
        }

        @Test("A completed source-identical refresh does not strand Related at the same Search generation", .timeLimit(.minutes(1)))
        func sameSearchGenerationRefreshRemainsLive() async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            try Data("# Middle\n\n[[Target]]\n".utf8).write(to: fixture.topicsURL.appendingPathComponent("Middle.md"))
            let target = fixture.topicsURL.appendingPathComponent("Target.md")
            let targetBytes = Data("# Target\n\nAgency requires a deliberate choice.\n".utf8)
            try targetBytes.write(to: target)
            let runtime = try await WorkspaceRuntime.snapshot(
                applicationSupportURL: fixture.applicationSupportURL, workspaceRegistryStorageURL: fixture.registryStorageURL)
            let handle: WorkspaceHandle
            do { handle = try await runtime.openWorkspace(id: fixture.assignment.id) } catch {
                await runtime.shutdown()
                throw error
            }
            let request = RelatedContentRequest(
                seed: .init(
                    noteID: fixture.analysisNoteID, source: "# Agency\n\nAgency [[Middle]].",
                    focuses: [.init(kind: .selectedPassage, text: "agency deliberate choice")]))
            let gate = RelatedFinalValidationGate()
            var query: Task<RelatedContentResponse, Error>?
            do {
                let initialResult = try await handle.discovery.relatedContent(request)
                try #require(initialResult.state == .current && !initialResult.passages.isEmpty)
                try #require(await handle.lastRelatedContentMeasurement?.graphUsed == true)
                let initial = try await handle.snapshot()
                let initialSearch = try #require(initial.discovery.searchGeneration)
                let initialGraph = try #require(initial.discovery.catalog.graph?.generation)
                let initialSources = Dictionary(uniqueKeysWithValues: initial.vaults.flatMap(\.documents).map { ($0.id, $0.fingerprint) })
                await handle.setRelatedContentFinalValidationBarrierForTesting { await gate.holdOnce() }
                let pending = Task {
                    do {
                        let response = try await handle.discovery.relatedContent(request)
                        await gate.finish()
                        return response
                    } catch {
                        await gate.finish()
                        throw error
                    }
                }
                query = pending
                try #require(await gate.waitUntilArrived())
                let refreshed = try await handle.refresh()
                let refreshedGraph = try #require(refreshed.discovery.catalog.graph?.generation)
                #expect(refreshed.discovery.searchGeneration == initialSearch)
                #expect(refreshedGraph > initialGraph)
                #expect(refreshed.sourceInventoryRevision > initial.sourceInventoryRevision)
                #expect(Dictionary(uniqueKeysWithValues: refreshed.vaults.flatMap(\.documents).map { ($0.id, $0.fingerprint) }) == initialSources)
                #expect(try Data(contentsOf: target) == targetBytes)
                await gate.release()
                let response = try await pending.value
                print(
                    "RELATED_SAME_G state=\(response.state) search_unchanged=\(refreshed.discovery.searchGeneration == initialSearch) graph_advanced=\(refreshedGraph > initialGraph) publication_advanced=\(refreshed.sourceInventoryRevision > initial.sourceInventoryRevision)"
                )
                #expect(response.state == .current)
                #expect(response.availability == .current(initialSearch))
                #expect(response.passages.map(\.source) == initialResult.passages.map(\.source))
                await handle.setRelatedContentFinalValidationBarrierForTesting(nil)
            } catch {
                query?.cancel()
                await gate.release()
                _ = try? await query?.value
                await handle.setRelatedContentFinalValidationBarrierForTesting(nil)
                await runtime.shutdown()
                throw error
            }
            await runtime.shutdown()
        }

        enum RefreshObservationControl: CaseIterable, Equatable, Sendable {
            case harmless, followOn, bufferedDuringSourceMutation, bufferedCancellation, bufferedShutdown, changedSource, changedSourceWithFollowOn,
                failedPreparationWithFollowOn, cancel,
                shutdown

            var buffersDuringMutation: Bool {
                self == .bufferedDuringSourceMutation || self == .bufferedCancellation || self == .bufferedShutdown
            }

            var changesSource: Bool { self == .changedSource || self == .changedSourceWithFollowOn }
        }

        @Test(
            "Related observes harmless admitted work without requiring publication or repeating retrieval",
            .timeLimit(.minutes(1)), arguments: RefreshObservationControl.allCases)
        func admittedRefreshObservation(control: RefreshObservationControl) async throws {
            let fixture = try await ApplicationFixture.make()
            defer { fixture.remove() }
            let middle = fixture.topicsURL.appendingPathComponent("Middle.md")
            try Data("# Middle\n\n[[Target]]\n".utf8).write(to: middle)
            try Data("# Target\n\nAgency requires a deliberate choice.\n".utf8)
                .write(to: fixture.topicsURL.appendingPathComponent("Target.md"))
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(applicationSupportURL: fixture.applicationSupportURL, workspaceRegistryStorageURL: fixture.registryStorageURL)))
            let handle: WorkspaceHandle
            do { handle = try await runtime.openWorkspace(id: fixture.assignment.id) } catch {
                await runtime.shutdown()
                throw error
            }
            let queryGate = RelatedFinalValidationGate()
            let firstPreflight = RelatedFinalValidationGate()
            let secondPreflight = RelatedFinalValidationGate()
            let changedPublication = RelatedFinalValidationGate()
            let progress = RelatedObservationProgress()
            var query: Task<RelatedContentResponse, Error>?
            var shutdown: Task<Void, Never>?
            var sourceLease: WorkspaceSourceOperationLease?
            do {
                await handle.openingPresentationDidComplete()
                await handle.awaitOpeningCompletionForTesting()
                _ = try await handle.refresh()
                if let live = await handle.liveIndexRefreshTask?.task { await live.value }
                let request = RelatedContentRequest(
                    seed: .init(
                        noteID: fixture.analysisNoteID, source: "# Agency\n\nAgency [[Middle]].",
                        focuses: [.init(kind: .selectedPassage, text: "agency deliberate choice")]))
                let original = try await handle.discovery.relatedContent(request)
                try #require(original.state == .current && !original.passages.isEmpty)
                try #require(await handle.lastRelatedContentMeasurement?.graphUsed == true)
                let initial = try await handle.snapshot()
                let initialSearch = try #require(initial.discovery.searchGeneration)
                let publications = await handle.events.publishedGeneration
                let graphAttempts = await handle.nextGraphGeneration
                await handle.setRelatedContentFinalValidationBarrierForTesting { await queryGate.holdOnce() }
                await handle.setLiveInventoryPreflightBarrierForTesting {
                    switch await progress.nextPreflight() {
                    case 1: await firstPreflight.holdOnce()
                    case 2 where control == .followOn: await secondPreflight.holdOnce()
                    case 3 where control == .changedSourceWithFollowOn: await secondPreflight.holdOnce()
                    default: break
                    }
                }
                let pending = Task {
                    do {
                        let response = try await handle.discovery.relatedContent(request)
                        await progress.finishQuery()
                        await queryGate.finish()
                        return response
                    } catch {
                        await progress.finishQuery()
                        await queryGate.finish()
                        throw error
                    }
                }
                query = pending
                try #require(await queryGate.waitUntilArrived())
                if control.buffersDuringMutation {
                    sourceLease = try await handle.beginSourceMutation()
                }
                try await runtime.deliverPooledVaultEventForTesting(.reconciliationRequired(sequence: 100), vaultID: fixture.analysisNoteID.vaultID)
                if control.buffersDuringMutation {
                    #expect(await handle.liveIndexRefreshTask == nil)
                    await queryGate.release()
                    try await waitForRelatedProbe {
                        let completed = await progress.queryFinished
                        let observing = await handle.sourceOperationGate.waitingCount > 0
                        return completed || observing
                    }
                    #expect(!(await progress.queryFinished), "A buffered harmless event escaped observation while its source gate was held")
                    if control == .bufferedCancellation || control == .bufferedShutdown {
                        if control == .bufferedCancellation {
                            pending.cancel()
                            await #expect(throws: CancellationError.self) { try await pending.value }
                        } else {
                            shutdown = Task { await runtime.shutdown() }
                            await #expect(throws: (any Error).self) { try await pending.value }
                        }
                        #expect(await handle.sourceOperationGate.waitingCount == 0)
                        #expect(await handle.sourceOperationGate.currentSourceMutation == sourceLease, "Observation changed the admitted mutation lease")
                        #expect(await handle.relatedContentRefreshWaiters.isEmpty)
                        #expect(await queryGate.entryCount == 1)
                        await firstPreflight.release()
                        await secondPreflight.release()
                        if let held = sourceLease {
                            sourceLease = nil
                            await handle.endSourceMutation(held)
                        }
                        await handle.setRelatedContentFinalValidationBarrierForTesting(nil)
                        await handle.setLiveInventoryPreflightBarrierForTesting(nil)
                        await handle.setCapturedSearchManifestBarrierForTesting(nil)
                        await handle.setPreparedSourceCatalogBarrierForTesting(nil)
                        await changedPublication.release()
                        await runtime.shutdown()
                        await shutdown?.value
                        return
                    }
                    if let held = sourceLease {
                        sourceLease = nil
                        await handle.endSourceMutation(held)
                    }
                }
                try #require(await firstPreflight.waitUntilArrived())
                await queryGate.release()
                try await waitForRelatedProbe {
                    let completed = await progress.queryFinished
                    let observing = await handle.relatedContentRefreshWaiters.count == 1
                    return completed || observing
                }
                #expect(!(await progress.queryFinished), "The query returned while its captured harmless preflight was still held")
                #expect(await handle.relatedContentRefreshWaiters.count == 1)
                switch control {
                case .cancel:
                    pending.cancel()
                    await #expect(throws: CancellationError.self) { try await pending.value }
                    #expect(await handle.relatedContentRefreshWaiters.isEmpty)
                    #expect(await handle.liveIndexRefreshTask != nil)
                case .shutdown:
                    shutdown = Task { await runtime.shutdown() }
                    await #expect(throws: (any Error).self) { try await pending.value }
                    #expect(await handle.relatedContentRefreshWaiters.isEmpty)
                case .followOn:
                    try await runtime.deliverPooledVaultEventForTesting(.reconciliationRequired(sequence: 101), vaultID: fixture.analysisNoteID.vaultID)
                    await firstPreflight.release()
                    try #require(await secondPreflight.waitUntilArrived())
                    try await waitForRelatedProbe { await handle.relatedContentRefreshWaiters.count == 1 }
                    #expect(!(await progress.queryFinished))
                    await secondPreflight.release()
                case .changedSource, .changedSourceWithFollowOn:
                    if control == .changedSourceWithFollowOn {
                        await handle.setCapturedSearchManifestBarrierForTesting { await changedPublication.holdOnce() }
                    }
                    let changed = "# Middle\n\nThe intermediary no longer links to Target.\n"
                    try Data(changed.utf8).write(to: middle)
                    let topicsID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
                    try await runtime.deliverPooledVaultEventForTesting(
                        .init(added: [], modified: ["Middle.md"], deleted: [], sequence: 101, requiresFullRescan: false, rootChanged: false), vaultID: topicsID)
                    let repository = try await handle.repository(vaultID: topicsID)
                    let authoritative = try await repository.load(relativePath: "Middle.md")
                    #expect(authoritative.sourceBytes == Data(changed.utf8))
                    #expect(authoritative.fingerprint != initial.document(id: .init(vaultID: topicsID, relativePath: "Middle.md"))?.fingerprint)
                    if control == .changedSourceWithFollowOn {
                        await firstPreflight.release()
                        try #require(await changedPublication.waitUntilArrived())
                        try await runtime.deliverPooledVaultEventForTesting(.reconciliationRequired(sequence: 102), vaultID: fixture.analysisNoteID.vaultID)
                        await changedPublication.release()
                        try #require(await secondPreflight.waitUntilArrived())
                        try await waitForRelatedProbe {
                            let completed = await progress.queryFinished
                            let observing = await handle.relatedContentRefreshWaiters.count == 1
                            return completed || observing
                        }
                        let completed = await progress.queryFinished
                        #expect(completed, "An obsolete query joined later held work after its captured cohort changed")
                        if !completed { await secondPreflight.release() }
                        let stale = try await pending.value
                        #expect(stale.state == .stale && stale.passages.isEmpty)
                        if completed { #expect(await handle.liveIndexRefreshTask != nil, "The query cancelled the later shared work") }
                    }
                case .failedPreparationWithFollowOn:
                    await handle.setPreparedSourceCatalogBarrierForTesting { vaultID in
                        guard vaultID == fixture.analysisNoteID.vaultID else { return }
                        switch await progress.nextPreparation() {
                        case 1: await changedPublication.holdOnce()
                        case 2: await secondPreflight.holdOnce()
                        default: break
                        }
                    }
                    let unreadable = fixture.topicsURL.appendingPathComponent("Unreadable.md")
                    let invalidBytes = Data([0xFF, 0xFE, 0xFD])
                    try invalidBytes.write(to: unreadable)
                    let topicsID = try #require(fixture.assignment.vault(for: .topicKnowledge)?.id)
                    try await runtime.deliverPooledVaultEventForTesting(
                        .init(added: ["Unreadable.md"], modified: [], deleted: [], sequence: 101, requiresFullRescan: false, rootChanged: false),
                        vaultID: topicsID)
                    #expect(try Data(contentsOf: unreadable) == invalidBytes)
                    await firstPreflight.release()
                    try #require(await changedPublication.waitUntilArrived())
                    try await runtime.deliverPooledVaultEventForTesting(.reconciliationRequired(sequence: 102), vaultID: fixture.analysisNoteID.vaultID)
                    await changedPublication.release()
                    try #require(await secondPreflight.waitUntilArrived())
                    try await waitForRelatedProbe {
                        let completed = await progress.queryFinished
                        let observing = await handle.relatedContentRefreshWaiters.count == 1
                        return completed || observing
                    }
                    let completed = await progress.queryFinished
                    #expect(completed, "A known failed derived preparation kept an invalid query waiting behind later held work")
                    #expect(await handle.derivedStateRequiresRefresh)
                    let status = await handle.events.derivedRefreshStatus
                    let failureReason: String
                    if case .failed(let issue) = status {
                        failureReason = issue.reason
                        #expect(!failureReason.isEmpty)
                    } else {
                        Issue.record("The genuine preparation error lost its failed publication")
                        failureReason = ""
                    }
                    if !completed { await secondPreflight.release() }
                    let failed = try await pending.value
                    #expect(failed.state == .stale && failed.passages.isEmpty)
                    if case .failed(let lastGood, let reason) = failed.availability {
                        #expect(lastGood == initialSearch && reason == failureReason)
                    } else {
                        Issue.record("A genuine derived failure was returned as transient current-generation staleness")
                    }
                    #expect(try await handle.snapshot().discovery.searchGeneration == initialSearch)
                    #expect(await queryGate.entryCount == 1)
                    try FileManager.default.removeItem(at: unreadable)
                    await handle.setPreparedSourceCatalogBarrierForTesting(nil)
                    let retry = Task { try await handle.refresh() }
                    await secondPreflight.release()
                    let retried = try await retry.value
                    #expect(retried.discovery.searchGeneration == initialSearch)
                    #expect(!(await handle.derivedStateRequiresRefresh))
                    await handle.setRelatedContentFinalValidationBarrierForTesting(nil)
                    let recovered = try await handle.discovery.relatedContent(request)
                    #expect(recovered.state == .current && recovered.availability == .current(initialSearch))
                    #expect(recovered.passages.map(\.source) == original.passages.map(\.source))
                case .harmless, .bufferedDuringSourceMutation, .bufferedCancellation, .bufferedShutdown: break
                }
                await firstPreflight.release()
                await secondPreflight.release()
                if control != .cancel && control != .shutdown && control != .failedPreparationWithFollowOn {
                    let response = try await pending.value
                    let final = try await handle.snapshot()
                    if control.changesSource {
                        #expect(response.state == .stale && response.passages.isEmpty)
                        #expect(final.discovery.searchGeneration != initialSearch)
                    } else {
                        #expect(response.state == .current && response.availability == .current(initialSearch))
                        #expect(response.passages.map(\.source) == original.passages.map(\.source))
                        #expect(final.sourceInventoryRevision == initial.sourceInventoryRevision)
                        #expect(await handle.events.publishedGeneration == publications)
                        #expect(await handle.nextGraphGeneration == graphAttempts)
                    }
                }
                #expect(await queryGate.entryCount == 1, "Observation repeated candidate/source/ranking work")
                #expect(await handle.relatedContentRefreshWaiters.isEmpty)
                await handle.setRelatedContentFinalValidationBarrierForTesting(nil)
                await handle.setLiveInventoryPreflightBarrierForTesting(nil)
                await handle.setCapturedSearchManifestBarrierForTesting(nil)
                await handle.setPreparedSourceCatalogBarrierForTesting(nil)
                await changedPublication.release()
            } catch {
                query?.cancel()
                if let held = sourceLease {
                    sourceLease = nil
                    await handle.endSourceMutation(held)
                }
                await queryGate.release()
                await firstPreflight.release()
                await secondPreflight.release()
                await changedPublication.release()
                _ = try? await query?.value
                await handle.setRelatedContentFinalValidationBarrierForTesting(nil)
                await handle.setLiveInventoryPreflightBarrierForTesting(nil)
                await handle.setCapturedSearchManifestBarrierForTesting(nil)
                await handle.setPreparedSourceCatalogBarrierForTesting(nil)
                await runtime.shutdown()
                await shutdown?.value
                throw error
            }
            await runtime.shutdown()
            await shutdown?.value
        }

        private func waitForRelatedProbe(_ predicate: @escaping @Sendable () async -> Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !(await predicate()) {
                try #require(ContinuousClock.now < deadline, "Related observation did not reach its deterministic test boundary")
                await Task.yield()
            }
        }
    #endif
}

private struct GraphFixture {
    let vaultID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let triptychID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let documents: [String: NoteDocument]
    let catalog: [WorkspaceCatalogNote]
    let linkCatalog: [LinkCatalogNote]
    let graph: GraphSnapshot

    init(_ sources: [String: String], roles: [String: VaultRole] = [:]) {
        let taskVaultID = vaultID
        let taskDocuments = Dictionary(uniqueKeysWithValues: sources.map { ($0.key, NoteDocument(relativePath: $0.key, rawContent: $0.value)) })
        documents = taskDocuments
        let taskCatalog: [WorkspaceCatalogNote] = taskDocuments.keys.sorted().compactMap { path in
            guard let document = taskDocuments[path] else { return nil }
            return .init(
                reference: .init(vaultID: taskVaultID, vaultName: "Disposable", vaultRole: roles[path] ?? .topicKnowledge, relativePath: path),
                title: ResearchNoteTitleResolver.resolve(document: document), fingerprint: document.fingerprint, validationWarnings: [])
        }
        catalog = taskCatalog
        let taskLinkCatalog = taskDocuments.keys.sorted().compactMap { path in
            taskDocuments[path].map { LinkCatalogNote(vaultID: taskVaultID, document: $0) }
        }
        linkCatalog = taskLinkCatalog
        let manifest = SearchSourceManifest.hash(
            taskCatalog.map {
                .init(vaultID: $0.reference.vaultID, relativePath: $0.reference.relativePath, fingerprint: $0.fingerprint)
            })
        graph = LinkGraphBuilder.build(
            generation: 1, catalog: taskLinkCatalog,
            documents: Dictionary(
                taskDocuments.map { (VaultQualifiedNoteID(vaultID: taskVaultID, relativePath: $0.key), MarkdownSemanticDocument(parsing: $0.value)) },
                uniquingKeysWith: { first, _ in first }),
            resolutionScope: .workspace, sourceManifestHash: manifest)
    }

    func id(_ path: String) -> VaultQualifiedNoteID { .init(vaultID: vaultID, relativePath: path) }
    func result(
        source: String? = nil, existing: [String] = [], manifest: String? = nil,
        catalog: [WorkspaceCatalogNote]? = nil, candidateRoles: [RelatedContentCandidateRole] = [.analysis, .topic, .work]
    ) async throws -> RelatedContentGraphCandidates.Result? {
        let request = RelatedContentRequest(
            seed: .init(noteID: id("Seed.md"), source: source ?? documents["Seed.md"]!.rawContent), candidateRoles: candidateRoles)
        let candidates = existing.compactMap { path -> RelatedContentCandidate? in
            guard let note = self.catalog.first(where: { $0.reference.relativePath == path }) else { return nil }
            return .init(
                note: id(path), vaultRole: note.reference.vaultRole, title: note.title, fingerprint: note.fingerprint,
                reason: .lexicalOverlap(.init(matchedFields: [], seedMatches: [])))
        }
        return try await RelatedContentGraphCandidates.build(
            request: request, graph: graph,
            searchGeneration: .init(triptychID: triptychID, sequence: 1, sourceManifestHash: manifest ?? graph.sourceManifestHash),
            catalog: catalog ?? self.catalog, linkCatalog: linkCatalog, existingCandidates: candidates)
    }
}

#if DEBUG
    private actor RelatedFinalValidationGate {
        private let arrival = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private let releaseSignal = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        private var didArrive = false
        private(set) var entryCount = 0

        func holdOnce() async {
            entryCount += 1
            guard !didArrive else { return }
            didArrive = true
            arrival.continuation.yield(())
            arrival.continuation.finish()
            var iterator = releaseSignal.stream.makeAsyncIterator()
            _ = await iterator.next()
        }

        func waitUntilArrived() async -> Bool {
            var iterator = arrival.stream.makeAsyncIterator()
            return await iterator.next() != nil
        }

        func finish() { arrival.continuation.finish() }

        func release() {
            releaseSignal.continuation.yield(())
            releaseSignal.continuation.finish()
            arrival.continuation.finish()
        }
    }
#endif

#if DEBUG
    private actor RelatedObservationProgress {
        private var preflights = 0
        private var preparations = 0
        private(set) var queryFinished = false
        func nextPreflight() -> Int {
            preflights += 1
            return preflights
        }
        func nextPreparation() -> Int {
            preparations += 1
            return preparations
        }
        func finishQuery() { queryFinished = true }
    }
#endif
