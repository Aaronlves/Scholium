import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

/// Opt-in diagnostics, separate from the release performance protocol.
@Suite(
    "Writing References performance", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_WRITING_REFERENCES"] == "1"))
struct WritingReferencesPerformanceTests {
    @Test("Recommendations over a generated multilingual collection retain exact locators")
    func largeCollection() async throws {
        let environment = ProcessInfo.processInfo.environment
        let count = Int(environment["SCHOLIUM_REFERENCE_NOTE_COUNT"] ?? "500") ?? 500
        let label = environment["SCHOLIUM_REFERENCE_MEASUREMENT_LABEL"] ?? "diagnostic"
        let threeVaults = environment["SCHOLIUM_REFERENCE_THREE_VAULTS"] == "1"
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let artifacts = repository.appendingPathComponent(".build/writing-references-performance", isDirectory: true)
        let root = artifacts.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let analyses = root.appendingPathComponent("01-analyses", isDirectory: true)
        let topics = root.appendingPathComponent("02-topics", isDirectory: true)
        let works = root.appendingPathComponent("03-works", isDirectory: true)
        for directory in [analyses, topics, works] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        var expectedSources: [String: String] = [:]
        var expectedRoles: [String: VaultRole] = [:]
        var corpusRoleCounts = ["source_corpus": 0, "topic_knowledge": 0, "draft_project": 0]
        for number in 0..<count {
            let name = String(format: "Note-%05d.md", number)
            let paragraphs = (0..<16).map { paragraph in
                "自由 agency and evidence distinguish an argument from its objection. "
                    + "第 \(paragraph) 段讨论理由、价值与行动。 "
                    + (paragraph.isMultiple(of: 4) ? "[[Other|freedom]]{{agency 自由 and evidence}} " : "")
                    + "The researcher compares alternatives with explicit uncertainty in discussion \(number)."
            }
            let source =
                "---\nsummary: agency 自由\nkeywords: [agency, evidence]\n---\n\n# Discussion \(number)\n\n"
                + paragraphs.joined(separator: "\n\n") + "\n"
            expectedSources[name] = source
            let role: VaultRole
            if threeVaults {
                let position = number % 25
                role = position < 8 ? .sourceCorpus : (position < 19 ? .topicKnowledge : .draftProject)
            } else {
                role = number.isMultiple(of: 2) ? .sourceCorpus : .topicKnowledge
            }
            expectedRoles[name] = role
            corpusRoleCounts[role.rawValue, default: 0] += 1
            let directory = role == .sourceCorpus ? analyses : (role == .topicKnowledge ? topics : works)
            try Data(source.utf8).write(to: directory.appendingPathComponent(name))
        }
        let draft = "# Draft\n\nagency evidence 自由\n"
        try Data(draft.utf8).write(to: works.appendingPathComponent("Draft.md"))
        expectedSources["Draft.md"] = draft
        expectedRoles["Draft.md"] = .draftProject
        print("Recommendation corpus role counts: \(corpusRoleCounts), plus one Works seed")
        let configuration = WorkspaceRuntime.Configuration.live(
            .init(
                applicationSupportURL: root.appendingPathComponent("app-state"),
                workspaceRegistryStorageURL: root.appendingPathComponent("registry")))
        var activeRuntime = WorkspaceRuntime(configuration: configuration)
        var samples: [[String: Any]] = []
        var searchSamples: [[String: Any]] = []
        var lifecycleSamples: [[String: Any]] = []
        var expectedPassages: [RelatedContentPassage]?

        func seconds(_ duration: Duration) -> Double {
            let value = duration.components
            return Double(value.seconds) + Double(value.attoseconds) / 1e18
        }

        func measureRecommendation(
            _ handle: WorkspaceHandle, vault: UUID, scenario: String, sample: Int,
            focus: String = "agency evidence 自由", source: String? = nil,
            expectedCount: Int = RelatedContentContract.maximumPassages
        ) async throws -> RelatedContentResponse {
            let request = RelatedContentRequest(
                seed: .init(
                    noteID: .init(vaultID: vault, relativePath: "Draft.md"),
                    source: source ?? draft + String(repeating: "\n", count: sample),
                    focuses: [.init(kind: .selectedPassage, text: focus)]))
            if threeVaults { #expect(request.candidateRoles.contains(.work)) }
            FileHandle.standardOutput.write(
                Data(
                    "Recommendation measurement phase: \(scenario), sample \(sample), pid \(ProcessInfo.processInfo.processIdentifier)\n".utf8))
            let started = ContinuousClock.now
            let response = try await handle.discovery.relatedContent(request)
            let elapsed = seconds(started.duration(to: .now))
            let measurement = try #require(await handle.lastRelatedContentMeasurement)
            #expect(response.state == .current)
            #expect(response.passages.count == expectedCount)
            var passageRoleCounts = ["source_corpus": 0, "topic_knowledge": 0, "draft_project": 0]
            for passage in response.passages {
                let currentSource = try #require(expectedSources[passage.candidate.note.relativePath])
                #expect(passage.candidate.vaultRole == expectedRoles[passage.candidate.note.relativePath])
                passageRoleCounts[passage.candidate.vaultRole.rawValue, default: 0] += 1
                #expect(passage.candidate.fingerprint == DocumentFingerprint(content: currentSource))
                let range = try #require(
                    Range(
                        NSRange(
                            location: passage.range.utf16LowerBound,
                            length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: currentSource))
                #expect(String(currentSource[range]) == passage.source)
            }
            samples.append([
                "scenario": scenario, "sample": sample, "seconds": elapsed, "passages": response.passages.count,
                "passage_role_counts": passageRoleCounts,
                "candidates": measurement.candidateCount,
                "index_seconds": seconds(measurement.indexDuration),
                "read_seconds": seconds(measurement.readDuration),
                "passage_seconds": seconds(measurement.passageDuration),
            ])
            print(
                "Writing References: \(count) notes, \(scenario) sample \(sample), "
                    + "\(String(format: "%.3f", elapsed)) s, \(response.passages.count) exact passages")
            print("Recommendation passage role counts: \(passageRoleCounts)")
            return response
        }

        func measureSearch(
            _ handle: WorkspaceHandle, scenario: String, query: String, expectedPath: String? = nil
        ) async throws {
            let started = ContinuousClock.now
            let response = try await handle.discovery.search(
                SearchRequest(query: query, presentationScope: .triptych, executionScope: .triptych, limit: 20))
            let elapsed = seconds(started.duration(to: .now))
            let notes = response.results.compactMap { result -> NoteSearchResult? in
                guard case .note(let note) = result else { return nil }
                return note
            }
            #expect(!notes.isEmpty)
            if let expectedPath { #expect(notes.map(\.relativePath) == [expectedPath]) }
            for note in notes {
                let currentSource = try #require(expectedSources[note.relativePath])
                #expect(note.fingerprint == DocumentFingerprint(content: currentSource))
                for locator in note.paragraphRanges + (note.sourceRange.map { [$0] } ?? []) {
                    let range = Range(
                        NSRange(location: locator.utf16LowerBound, length: locator.utf16UpperBound - locator.utf16LowerBound),
                        in: currentSource)
                    #expect(range != nil)
                }
            }
            searchSamples.append(["scenario": scenario, "seconds": elapsed, "results": notes.count])
            print("Search: \(count) notes, \(scenario), \(String(format: "%.3f", elapsed)) s, \(notes.count) current results")
        }

        do {
            let configureStarted = ContinuousClock.now
            let handle = try await activeRuntime.configureTriptych(
                paperAnalysisURL: analyses, topicKnowledgeURL: topics, outputURL: works,
                portableContainerURL: root, triptychName: "Recommendation diagnostic")
            let configureElapsed = seconds(configureStarted.duration(to: .now))
            lifecycleSamples.append(["scenario": "initial_configuration", "seconds": configureElapsed])
            print("Writing References lifecycle: initial configuration, \(String(format: "%.3f", configureElapsed)) s")
            let workspaceID = handle.assignment.id
            let vault = try #require(handle.assignment.vault(for: .output)?.id)

            // Preserve the original three samples and source shape for comparison with earlier reports.
            for sample in 0..<3 {
                let response = try await measureRecommendation(handle, vault: vault, scenario: "initial_session", sample: sample)
                if let expectedPassages { #expect(response.passages == expectedPassages) } else { expectedPassages = response.passages }
            }
            await activeRuntime.shutdown()

            activeRuntime = WorkspaceRuntime(configuration: configuration)
            let reopenStarted = ContinuousClock.now
            let reopened = try await activeRuntime.openWorkspace(id: workspaceID)
            let reopenElapsed = seconds(reopenStarted.duration(to: .now))
            lifecycleSamples.append(["scenario": "reopen_existing_state", "seconds": reopenElapsed])
            print("Writing References lifecycle: reopen existing state, \(String(format: "%.3f", reopenElapsed)) s")
            let restartedResponse = try await measureRecommendation(reopened, vault: vault, scenario: "first_after_restart", sample: 0)
            #expect(restartedResponse.passages == expectedPassages)

            for (sample, focus) in ["uncertainty alternatives", "理由 价值 行动", "freedom objection"].enumerated() {
                _ = try await measureRecommendation(reopened, vault: vault, scenario: "varied_focus", sample: sample, focus: focus)
            }
            // A selected prose paragraph exercises the focus-term budget within a larger unsaved draft.
            let selectedParagraph =
                "The researcher compares agency, freedom, evidence, reasons, values, action, arguments and objections "
                + "across alternative explanations, preserving uncertainty about interpretation while checking definitions, "
                + "premises, conclusions, examples, distinctions, assumptions, context, relevance, consistency, counterexamples, "
                + "references, annotations, terminology, scope, method, sources, and revisions."
            let longDraft =
                "# Draft\n\n"
                + (0..<50).map { paragraph in
                    paragraph == 25
                        ? selectedParagraph
                        : "Draft section \(paragraph) discusses agency, evidence and 自由, comparing an argument with its objection. "
                            + "The researcher records alternatives and uncertainty before revising the surrounding discussion."
                }.joined(separator: "\n\n") + "\n"
            _ = try await measureRecommendation(
                reopened, vault: vault, scenario: "selected_prose_in_50_paragraph_draft", sample: 0,
                focus: selectedParagraph, source: longDraft)
            for (scenario, query) in [("english", "agency evidence"), ("chinese", "自由"), ("annotation", "freedom")] {
                try await measureSearch(reopened, scenario: scenario, query: query)
            }

            // An external atomic edit plus the public refresh exercises changed-source indexing.
            let changedName = "Note-00000.md"
            let originalSource = try #require(expectedSources[changedName])
            let changedSource = originalSource + "\nIncrementalneedle identifies the newly added paragraph 自由。\n"
            let updateStarted = ContinuousClock.now
            try Data(changedSource.utf8).write(to: analyses.appendingPathComponent(changedName), options: .atomic)
            expectedSources[changedName] = changedSource
            _ = try await reopened.discovery.refresh()
            let updateElapsed = seconds(updateStarted.duration(to: .now))
            lifecycleSamples.append(["scenario": "single_note_atomic_edit_and_refresh", "seconds": updateElapsed])
            print("Writing References lifecycle: single note edit and refresh, \(String(format: "%.3f", updateElapsed)) s")
            let changedResponse = try await measureRecommendation(
                reopened, vault: vault, scenario: "first_after_update", sample: 0,
                focus: "incrementalneedle", source: "# Draft\n\nincrementalneedle\n", expectedCount: 1)
            #expect(changedResponse.passages.first?.candidate.note.relativePath == changedName)
            #expect(changedResponse.passages.first?.source.contains("Incrementalneedle") == true)
            try await measureSearch(reopened, scenario: "updated_note", query: "incrementalneedle", expectedPath: changedName)
            await activeRuntime.shutdown()
        } catch {
            await activeRuntime.shutdown()
            throw error
        }
        let report: [String: Any] = [
            "label": label, "notes": count, "paragraphs_per_note": 16,
            "three_vault_corpus": threeVaults, "corpus_note_counts": corpusRoleCounts, "additional_works_seed_notes": 1,
            "measurement":
                "Backend diagnostics; recommendation and search timings exclude opening, debounce and UI publication; lifecycle timings reported separately",
            "samples": samples, "search_samples": searchSamples, "lifecycle_samples": lifecycleSamples,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: artifacts.appendingPathComponent("\(label)-\(count).json"))
    }
}
