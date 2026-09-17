import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

/// Explicitly opt-in, read-only evaluation of an authorized copy beneath this
/// checkout's .build. Reports contain measurements, opaque identities and exact
/// selected ranges, never source text, raw Note identities, query terms, paths,
/// or source fingerprints.
@Suite(
    "Writing References private-copy diagnostics", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_PRIVATE_REFERENCE_COPY"] != nil))
struct WritingReferencesPrivateCorpusTests {
    private enum Failure: Error {
        case invalidCopy, invalidLabel, invalidSource, insufficientCases, invalidResult, changedCopy, measurementUnavailable
        case operationFailed(stage: String, errorType: String, domain: String, code: Int)
    }

    private struct Source {
        let slot: WorkspaceVaultSlot
        let relativePath: String
        let document: NoteDocument
        let paragraphs: [String]
    }

    private struct QueryCase {
        let source: Source
        let focus: String
    }

    private struct Sample: Codable {
        let scenario: String
        let ordinal: Int
        let role: String
        let sourceUTF16Count: Int
        let focusUTF16Count: Int
        let seconds: Double
        let indexSeconds: Double
        let readSeconds: Double
        let passageSeconds: Double
        let candidates: Int
        let passages: Int
        let passageRoleCounts: [String: Int]
    }

    private struct JudgmentFile: Decodable {
        let cases: [JudgmentCase]
    }

    private struct JudgmentCase: Decodable {
        let id: String
        let split: String
        let seedRole: String
        let seedPath: String
        let focus: String
        let judgments: [Judgment]
    }

    private struct Judgment: Decodable {
        let role: String
        let path: String
        let grade: Int
    }

    private struct PassageCoordinates: Codable {
        let opaqueNoteID: String
        let lowerUTF16: Int
        let upperUTF16: Int
    }

    private struct QualitySample: Codable {
        let ordinal: Int
        let id: String
        let split: String
        let seconds: Double
        let passages: Int
        let distinctResultNotes: Int
        let judgedUsefulNotes: Int
        let retrievedJudgedUsefulNotes: Int
        let retrievedJudgedNonUsefulNotes: Int
        let unjudgedResultNotes: Int
        let returnedGradeCounts: [String: Int]
        let firstJudgedUsefulPassageRank: Int?
        let judgedUsefulRecallAt6: Double?
        /// SHA256(role + unit separator + relative path), never a raw identity.
        /// Allows a private offline rank-fusion experiment without source logs.
        let rankedOpaqueNoteIDs: [String]
        let lexicalCandidateOpaqueNoteIDs: [String]
        /// Display order, with source UTF-16 bounds for private offline review
        /// against the authorized copy already checked by this measurement.
        let selectedPassages: [PassageCoordinates]
    }

    private struct Report: Codable {
        let selectionPolicyVersion: Int
        let measurement: String
        let corpusNotes: Int
        let corpusBytes: Int
        let corpusRoleCounts: [String: Int]
        let eligibleSeedNotes: Int
        let copyPreparationSeconds: Double
        let initialConfigurationSeconds: Double
        let variedQueryCount: Int
        let variedMedianSeconds: Double
        let variedP95Seconds: Double
        let samples: [Sample]
        let qualityMeasurement: String
        let qualitySamples: [QualitySample]
    }

    @Test("Authorized copied paragraphs yield current exact references and bounded private diagnostics")
    func copiedCollection() async throws {
        // Errors from Foundation or the runtime may embed private URLs. Keep
        // those errors out of test-runner output, including on failed runs.
        do {
            try await measureCopy()
        } catch let failure as Failure {
            throw failure
        } catch {
            throw sanitized(error, stage: "preparation_or_report")
        }
    }

    private func measureCopy() async throws {
        let manager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .standardizedFileURL
        let build = repository.appendingPathComponent(".build", isDirectory: true)
        guard let supplied = environment["SCHOLIUM_PRIVATE_REFERENCE_COPY"], supplied.hasPrefix("/") else {
            throw Failure.invalidCopy
        }
        let copy = URL(fileURLWithPath: supplied, isDirectory: true).standardizedFileURL
        try validateDirectory(build, beneath: repository)
        try validateDirectory(copy, beneath: build)
        let sourceDirectories = Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map {
                ($0, copy.appendingPathComponent($0.displayName, isDirectory: true))
            })
        for directory in sourceDirectories.values { try validateDirectory(directory, beneath: copy) }
        let before = try manifest(copy)
        let roleManifests = try sourceDirectories.mapValues { try manifest($0) }
        let sources = try loadSources(sourceDirectories)
        let cases = try selectedCases(sources)
        let label = environment["SCHOLIUM_PRIVATE_REFERENCE_LABEL"] ?? "diagnostic"
        guard !label.isEmpty, label.count <= 64,
            label.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 })
        else { throw Failure.invalidLabel }
        let artifacts = build.appendingPathComponent("recommendation-private-evaluation", isDirectory: true)
        try manager.createDirectory(at: artifacts, withIntermediateDirectories: true)
        try validateDirectory(artifacts, beneath: build)
        // Preserve the supplied copy. The runtime owns a second disposable copy
        // because its portable control container must be the Works parent.
        guard !artifacts.path.hasPrefix(copy.path + "/"), artifacts != copy else { throw Failure.invalidCopy }
        let judgmentURL = artifacts.appendingPathComponent("judgments.json")
        var judgmentCases: [JudgmentCase] = []
        if manager.fileExists(atPath: judgmentURL.path) {
            try validateItem(judgmentURL, beneath: artifacts)
            judgmentCases = try JSONDecoder().decode(JudgmentFile.self, from: Data(contentsOf: judgmentURL)).cases
        }
        let state = artifacts.appendingPathComponent("state-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: state, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: state) }
        try validateDirectory(state, beneath: artifacts)
        let workingCopy = state.appendingPathComponent("corpus", isDirectory: true)
        let directories = Dictionary(
            uniqueKeysWithValues: WorkspaceVaultSlot.allCases.map {
                ($0, workingCopy.appendingPathComponent($0.displayName, isDirectory: true))
            })
        let copyStarted = ContinuousClock.now
        do {
            try manager.createDirectory(at: workingCopy, withIntermediateDirectories: false)
            try validateDirectory(workingCopy, beneath: state)
            for slot in WorkspaceVaultSlot.allCases {
                try manager.copyItem(at: sourceDirectories[slot]!, to: directories[slot]!)
                try validateDirectory(directories[slot]!, beneath: workingCopy)
                guard try manifest(directories[slot]!) == roleManifests[slot] else { throw Failure.changedCopy }
            }
        } catch {
            throw sanitized(error, stage: "copy_preparation")
        }
        let copyPreparationSeconds = seconds(copyStarted.duration(to: .now))
        let runtime = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: state.appendingPathComponent("app-state"),
                    workspaceRegistryStorageURL: state.appendingPathComponent("registry"))))
        var samples: [Sample] = []
        var qualitySamples: [QualitySample] = []
        let configurationSeconds: Double
        var operationStage = "configure_triptych"
        do {
            let started = ContinuousClock.now
            let handle = try await runtime.configureTriptych(
                paperAnalysisURL: directories[.paperAnalysis]!, topicKnowledgeURL: directories[.topicKnowledge]!,
                outputURL: directories[.output]!, portableContainerURL: workingCopy,
                triptychName: "Private-copy recommendation diagnostic")
            configurationSeconds = seconds(started.duration(to: .now))
            for sample in 0..<3 {
                operationStage = "initial_recommendation_\(sample)"
                samples.append(
                    try await measure(
                        cases[0], handle: handle, directories: directories,
                        scenario: sample == 0 ? "first_after_configuration" : "warm_repeat", ordinal: sample
                    ).sample)
            }
            for (ordinal, query) in cases.enumerated() {
                operationStage = "varied_recommendation_\(ordinal)"
                samples.append(
                    try await measure(query, handle: handle, directories: directories, scenario: "varied", ordinal: ordinal).sample)
            }
            for (ordinal, judgment) in judgmentCases.enumerated() {
                operationStage = "judged_recommendation_\(ordinal)"
                guard opaqueIdentifier(judgment.id),
                    ["development", "heldout"].contains(judgment.split),
                    let slot = slot(named: judgment.seedRole),
                    let source = sources.first(where: { $0.slot == slot && $0.relativePath == judgment.seedPath }),
                    !judgment.focus.isEmpty, judgment.focus.utf16.count <= RelatedContentContract.maximumFocusUTF16Count
                else { throw Failure.invalidSource }
                let measured = try await measure(
                    .init(source: source, focus: judgment.focus), handle: handle, directories: directories,
                    scenario: "judged", ordinal: ordinal)
                samples.append(measured.sample)
                qualitySamples.append(
                    try quality(
                        judgment, ordinal: ordinal, response: measured.response, elapsed: measured.sample.seconds,
                        handle: handle, sources: sources))
            }
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw sanitized(error, stage: operationStage)
        }
        guard try manifest(copy) == before else { throw Failure.changedCopy }
        for slot in WorkspaceVaultSlot.allCases {
            guard try manifest(directories[slot]!) == roleManifests[slot] else { throw Failure.changedCopy }
        }
        let varied = samples.filter { $0.scenario == "varied" }.map(\.seconds).sorted()
        let report = Report(
            selectionPolicyVersion: 1,
            measurement:
                "Read-only source evaluation on a second disposable copy. Copy preparation and initial configuration are separate; backend query time excludes both, editor debounce, and UI publication. Generated portable control state is outside the three source roots. Twenty varied queries are a limited sample, not a production p95 guarantee.",
            corpusNotes: sources.count, corpusBytes: sources.reduce(0) { $0 + $1.document.sourceBytes.count },
            corpusRoleCounts: Dictionary(grouping: sources, by: { $0.slot.vaultRole.rawValue }).mapValues(\.count),
            eligibleSeedNotes: sources.filter { !$0.paragraphs.isEmpty }.count,
            copyPreparationSeconds: copyPreparationSeconds,
            initialConfigurationSeconds: configurationSeconds, variedQueryCount: varied.count,
            variedMedianSeconds: (varied[9] + varied[10]) / 2,
            variedP95Seconds: varied[Int(ceil(Double(varied.count) * 0.95)) - 1], samples: samples,
            qualityMeasurement:
                "Recall@6 concerns only explicitly judged useful Notes (grade > 0), deduplicated by Note. Unjudged results remain unknown. Incomplete judgments do not establish full precision, nDCG, philosophical correctness, or researcher acceptance.",
            qualitySamples: qualitySamples)
        let reportURL = artifacts.appendingPathComponent("report-\(label).json")
        if manager.fileExists(atPath: reportURL.path) { try validateItem(reportURL, beneath: artifacts) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: .atomic)
        print("Private-copy recommendation diagnostics: \(sources.count) Notes; 20 varied queries; exact source checks and unchanged-copy checks passed.")
    }

    private func measure(
        _ query: QueryCase, handle: WorkspaceHandle, directories: [WorkspaceVaultSlot: URL], scenario: String, ordinal: Int
    ) async throws -> (sample: Sample, response: RelatedContentResponse) {
        guard let vault = handle.assignment.vault(for: query.source.slot) else { throw Failure.invalidSource }
        let seed = VaultQualifiedNoteID(vaultID: vault.id, relativePath: query.source.relativePath)
        let request = RelatedContentRequest(
            seed: .init(
                noteID: seed, source: query.source.document.rawContent,
                focuses: [.init(kind: .selectedPassage, text: query.focus)]))
        let started = ContinuousClock.now
        let response = try await handle.discovery.relatedContent(request)
        let elapsed = seconds(started.duration(to: .now))
        guard let measurement = await handle.lastRelatedContentMeasurement else { throw Failure.measurementUnavailable }
        guard response.state == .current || response.state == .empty,
            response.passages.count <= RelatedContentContract.maximumPassages
        else { throw Failure.invalidResult }
        var roleCounts: [String: Int] = [:]
        for passage in response.passages {
            guard
                let slot = WorkspaceVaultSlot.allCases.first(where: {
                    handle.assignment.vault(for: $0)?.id == passage.candidate.note.vaultID
                }), let directory = directories[slot], passage.candidate.vaultRole == slot.vaultRole,
                passage.candidate.note != seed
            else { throw Failure.invalidResult }
            let url = directory.appendingPathComponent(passage.candidate.note.relativePath).standardizedFileURL
            try validateItem(url, beneath: directory)
            let bytes = try Data(contentsOf: url)
            guard passage.candidate.fingerprint == DocumentFingerprint(data: bytes),
                let source = NoteDocument.decodeUTF8PreservingBOM(bytes),
                let range = Range(
                    NSRange(
                        location: passage.range.utf16LowerBound,
                        length: passage.range.utf16UpperBound - passage.range.utf16LowerBound), in: source),
                String(source[range]) == passage.source
            else { throw Failure.invalidResult }
            roleCounts[slot.vaultRole.rawValue, default: 0] += 1
        }
        let sample = Sample(
            scenario: scenario, ordinal: ordinal, role: query.source.slot.vaultRole.rawValue,
            sourceUTF16Count: query.source.document.rawContent.utf16.count, focusUTF16Count: query.focus.utf16.count,
            seconds: elapsed, indexSeconds: seconds(measurement.indexDuration), readSeconds: seconds(measurement.readDuration),
            passageSeconds: seconds(measurement.passageDuration), candidates: measurement.candidateCount,
            passages: response.passages.count, passageRoleCounts: roleCounts)
        return (sample, response)
    }

    private func quality(
        _ item: JudgmentCase, ordinal: Int, response: RelatedContentResponse, elapsed: Double,
        handle: WorkspaceHandle, sources: [Source]
    ) throws -> QualitySample {
        var grades: [VaultQualifiedNoteID: Int] = [:]
        for judgment in item.judgments {
            guard let slot = slot(named: judgment.role), (0...2).contains(judgment.grade),
                sources.contains(where: { $0.slot == slot && $0.relativePath == judgment.path }),
                let vault = handle.assignment.vault(for: slot)
            else { throw Failure.invalidSource }
            let note = VaultQualifiedNoteID(vaultID: vault.id, relativePath: judgment.path)
            guard grades[note] == nil else { throw Failure.invalidSource }
            grades[note] = judgment.grade
        }
        let expectedUseful = grades.values.filter { $0 > 0 }.count
        var seen = Set<VaultQualifiedNoteID>()
        var useful = 0
        var nonUseful = 0
        var unjudged = 0
        var firstUseful: Int?
        var gradeCounts: [String: Int] = [:]
        for (index, passage) in response.passages.prefix(6).enumerated() {
            let note = passage.candidate.note
            guard seen.insert(note).inserted else { continue }
            guard let grade = grades[note] else {
                unjudged += 1
                continue
            }
            gradeCounts[String(grade), default: 0] += 1
            if grade > 0 {
                useful += 1
                if firstUseful == nil { firstUseful = index + 1 }
            } else {
                nonUseful += 1
            }
        }
        return QualitySample(
            ordinal: ordinal, id: item.id, split: item.split, seconds: elapsed, passages: response.passages.count,
            distinctResultNotes: seen.count, judgedUsefulNotes: expectedUseful, retrievedJudgedUsefulNotes: useful,
            retrievedJudgedNonUsefulNotes: nonUseful, unjudgedResultNotes: unjudged, returnedGradeCounts: gradeCounts,
            firstJudgedUsefulPassageRank: firstUseful,
            judgedUsefulRecallAt6: expectedUseful == 0 ? nil : Double(useful) / Double(expectedUseful),
            rankedOpaqueNoteIDs: response.passages.map { opaqueNoteID($0.candidate) },
            lexicalCandidateOpaqueNoteIDs: response.lexicalCandidates.map(opaqueNoteID),
            selectedPassages: response.passages.map {
                PassageCoordinates(
                    opaqueNoteID: opaqueNoteID($0.candidate),
                    lowerUTF16: $0.range.utf16LowerBound,
                    upperUTF16: $0.range.utf16UpperBound)
            })
    }

    private func opaqueNoteID(_ candidate: RelatedContentCandidate) -> String {
        DocumentFingerprint(content: candidate.vaultRole.rawValue + "\u{1F}" + candidate.note.relativePath).sha256
    }

    private func slot(named role: String) -> WorkspaceVaultSlot? {
        WorkspaceVaultSlot.allCases.first { $0.vaultRole.rawValue == role }
    }

    private func opaqueIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64
            && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }

    private func loadSources(_ directories: [WorkspaceVaultSlot: URL]) throws -> [Source] {
        var sources: [Source] = []
        for slot in WorkspaceVaultSlot.allCases {
            guard let directory = directories[slot] else { throw Failure.invalidCopy }
            for relativePath in try manifest(directory).keys.sorted() where relativePath.lowercased().hasSuffix(".md") {
                let data = try Data(contentsOf: directory.appendingPathComponent(relativePath))
                guard let text = NoteDocument.decodeUTF8PreservingBOM(data) else { throw Failure.invalidSource }
                let document = NoteDocument(relativePath: relativePath, rawContent: text)
                var paragraphs: [String] = []
                if text.utf16.count <= RelatedContentContract.maximumSeedUTF16Count {
                    let semantic = MarkdownSemanticDocument(parsing: document)
                    paragraphs = semantic.blocks.compactMap { block in
                        guard block.kind == .paragraph, (80...RelatedContentContract.maximumPassageUTF16Count).contains(block.span.utf16Range.count),
                            let range = Range(block.span.nsRange, in: text)
                        else { return nil }
                        let readable = ResearchExcerptPresentation.readableText(String(text[range]), includingAnnotations: true)
                        return readable.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count >= 40 ? readable : nil
                    }.sorted { $0.utf16.count < $1.utf16.count }
                }
                sources.append(.init(slot: slot, relativePath: relativePath, document: document, paragraphs: paragraphs))
            }
        }
        return sources
    }

    private func selectedCases(_ sources: [Source]) throws -> [QueryCase] {
        var result: [QueryCase] = []
        for slot in WorkspaceVaultSlot.allCases {
            let eligible = sources.filter { $0.slot == slot && !$0.paragraphs.isEmpty }.sorted {
                if $0.document.sourceBytes.count != $1.document.sourceBytes.count {
                    return $0.document.sourceBytes.count < $1.document.sourceBytes.count
                }
                return $0.relativePath < $1.relativePath
            }
            let count = slot == .output ? 6 : 7
            guard eligible.count >= count else { throw Failure.insufficientCases }
            for index in 0..<count {
                let source = eligible[index * (eligible.count - 1) / (count - 1)]
                let percentile = index == count - 1 && slot == .output ? 0.9 : [0.2, 0.5, 0.9][index % 3]
                let paragraph = Int(Double(source.paragraphs.count - 1) * percentile)
                result.append(.init(source: source, focus: source.paragraphs[paragraph]))
            }
        }
        guard result.count == 20 else { throw Failure.insufficientCases }
        return result
    }

    private func manifest(_ directory: URL) throws -> [String: DocumentFingerprint] {
        var result: [String: DocumentFingerprint] = [:]
        func visit(_ parent: URL) throws {
            for url in try FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            {
                try validateItem(url, beneath: directory)
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                if values.isRegularFile == true {
                    let relative = String(url.path.dropFirst(directory.path.count + 1))
                    result[relative] = DocumentFingerprint(data: try Data(contentsOf: url))
                } else if values.isDirectory == true {
                    try visit(url)
                } else {
                    throw Failure.invalidCopy
                }
            }
        }
        try visit(directory)
        return result
    }

    private func validateDirectory(_ url: URL, beneath root: URL) throws {
        try validateItem(url, beneath: root)
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw Failure.invalidCopy }
    }

    private func validateItem(_ url: URL, beneath root: URL) throws {
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),
            url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL,
            try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
        else { throw Failure.invalidCopy }
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func sanitized(_ error: any Error, stage: String) -> Failure {
        if let failure = error as? Failure { return failure }
        let bridged = error as NSError
        return .operationFailed(stage: stage, errorType: String(reflecting: type(of: error)), domain: bridged.domain, code: bridged.code)
    }
}
