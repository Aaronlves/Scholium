import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

#if DEBUG
    /// Generated, nonprivate disk fixtures presented through the native feature.
    /// Copying, workspace configuration, hydration, image-admission preflight and
    /// source oracles are outside mode timers. Hidden layout is not visible paint
    /// or a WindowModel navigation, focus, or end-to-end acceptance measurement.
    @MainActor
    @Suite(
        "Generated stress document mode diagnostics", .serialized,
        .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MODE_STRESS_FIXTURE"] != nil))
    struct StressDocumentModeDiagnosticTests {
        private typealias Shared = DocumentModeSwitchPerformanceDiagnosticTests
        private static let roleFolders = ["01-analyses", "02-topics", "03-works"]

        private enum Scenario: String, CaseIterable {
            case longProse = "long_prose"
            case denseLinks = "dense_links"
            case nestedCallouts = "nested_callouts"
            case formatMatrix = "format_matrix"
            case imageGallery = "image_gallery"
            case sourceFidelity = "source_fidelity"

            var fixturePath: String {
                switch self {
                case .longProse: "01-analyses/Stress/Stress Long Prose.md"
                case .denseLinks: "02-topics/Stress/Stress Dense Links.md"
                case .nestedCallouts: "02-topics/Stress/Stress Nested Callouts.md"
                case .formatMatrix: "03-works/Stress/Stress Format Matrix.md"
                case .imageGallery: "02-topics/Stress/Stress Image Gallery.md"
                case .sourceFidelity: "03-works/Stress/Stress Source Fidelity.md"
                }
            }

            var heading: String? {
                switch self {
                case .denseLinks: "### Link batch 1200"
                case .nestedCallouts: "## Callout group 0320"
                case .formatMatrix: "### Format block 0060"
                case .imageGallery: "### Large image 0001"
                case .longProse, .sourceFidelity: nil
                }
            }
        }

        @Test("All six mode directions preserve generated source and nonempty Undo")
        func generatedStressModes() async throws {
            let environment = ProcessInfo.processInfo.environment
            try #require(environment["SCHOLIUM_MODE_ROUNDTRIP_ONLY"] != "1", "Stress diagnostics require the complete six-direction matrix.")
            let scenarios: [Scenario]
            if let name = environment["SCHOLIUM_MODE_STRESS_SCENARIO"] {
                scenarios = [try #require(Scenario(rawValue: name), "Unknown stress mode scenario.")]
            } else {
                scenarios = Scenario.allCases
            }
            let repository = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let buildRoot = repository.appendingPathComponent(".build", isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath()
            let suppliedFixture = URL(fileURLWithPath: try #require(environment["SCHOLIUM_MODE_STRESS_FIXTURE"]))
                .standardizedFileURL
            try #require(try suppliedFixture.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true)
            let fixture = suppliedFixture.resolvingSymlinksInPath()
            try #require(fixture.path.hasPrefix(buildRoot.path + "/"))
            let originalFiles = try Self.inventory(at: fixture, notesOnly: false)
            let originalNotes = Self.noteInventory(originalFiles)
            let manifest = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("stress-manifest.json")))
                    as? [String: Any])
            try #require(manifest["schema_version"] as? Int == 1)
            try #require(manifest["synthetic_nonprivate"] as? Bool == true)
            try #require(manifest["registration_roots"] as? [String] == Self.roleFolders)
            let manifestScenarios = try #require(manifest["scenarios"] as? [String: String])
            let counts = try #require(manifest["counts"] as? [String: Int])
            let noteCount = try #require(counts["notes"])
            try #require((508...20_000).contains(noteCount) && originalNotes.count == noteCount)
            for scenario in Scenario.allCases {
                try #require(manifestScenarios[scenario.rawValue] == scenario.fixturePath)
            }

            let root = buildRoot.appendingPathComponent("stress-document-mode-runtime/\(UUID().uuidString.lowercased())", isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath()
            try #require(root.path.hasPrefix(buildRoot.path + "/"))
            try #require(root != fixture && !root.path.hasPrefix(fixture.path + "/") && !fixture.path.hasPrefix(root.path + "/"))
            let manager = FileManager.default
            try #require(!manager.fileExists(atPath: root.path))
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            defer {
                do { try manager.removeItem(at: root) } catch { Issue.record(error) }
            }
            let working = root.appendingPathComponent("fixture", isDirectory: true)
            try manager.copyItem(at: fixture, to: working)
            try Self.requireSameInventory(originalNotes, actual: Self.inventory(at: working, notesOnly: true), label: "Initial copy Notes")
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: root.appendingPathComponent("state/Application Support", isDirectory: true),
                        workspaceRegistryStorageURL: root.appendingPathComponent("state/Registry", isDirectory: true))))
            do {
                let configurationStart = ContinuousClock.now
                let handle = try await runtime.configureTriptych(
                    paperAnalysisURL: working.appendingPathComponent(Self.roleFolders[0], isDirectory: true),
                    topicKnowledgeURL: working.appendingPathComponent(Self.roleFolders[1], isDirectory: true),
                    outputURL: working.appendingPathComponent(Self.roleFolders[2], isDirectory: true),
                    portableContainerURL: working, triptychName: "Generated Stress Mode Diagnostic")
                let workspace = try await handle.snapshot()
                try #require(workspace.phase.isComplete && workspace.vaults.count == Self.roleFolders.count)
                try Self.report([
                    "metric": "stress-mode-setup", "units": "milliseconds",
                    "workspaceConfigurationMilliseconds": Self.milliseconds(configurationStart.duration(to: .now)),
                    "fixtureNotes": noteCount, "fixtureFiles": originalFiles.count,
                    "fixtureInventorySHA256": Self.digest(originalFiles),
                    "scope": "Native hidden feature source-restored layout; excludes visible paint, native focus and WindowModel routing.",
                    "setupExcludedFromModeTimers": true,
                ])
                try await Self.reportCapacityBoundary(manifestScenarios, working: working, handle: handle)
                for scenario in scenarios {
                    try Task.checkCancellation()
                    do {
                        let hydrationStart = ContinuousClock.now
                        let currentWorkspace = try await handle.snapshot()
                        let note = try await Self.hydrate(scenario.fixturePath, in: working, workspace: currentWorkspace, documents: handle.documents)
                        let hydrationMilliseconds = Self.milliseconds(hydrationStart.duration(to: .now))
                        let preparationStart = ContinuousClock.now
                        let sourceFile = working.appendingPathComponent(scenario.fixturePath)
                        let sourceBytes = try Data(contentsOf: sourceFile)
                        try #require(note.document.sourceBytes == sourceBytes)
                        let source = note.document.rawContent
                        let data = try await Self.fixtureData(
                            scenario: scenario, source: source, note: note, documents: handle.documents, manifest: manifest)
                        try Self.report([
                            "metric": "stress-mode-hydration", "units": "milliseconds", "fixture": scenario.rawValue,
                            "milliseconds": hydrationMilliseconds,
                            "fixturePreparationMilliseconds": Self.milliseconds(preparationStart.duration(to: .now)),
                            "sourceUTF8Bytes": sourceBytes.count, "sourceSHA256": note.fingerprint.sha256,
                            "targetSourceUTF16LowerBound": data.viewportRange.location,
                            "targetSourceUTF16UpperBound": data.viewportRange.location + data.viewportRange.length,
                            "setupExcludedFromModeTimers": true, "nonemptyUndoSeed": true,
                        ])
                        let harness = try Shared.Harness(
                            data: data, note: note, workspace: currentWorkspace,
                            documents: handle.documents, sourceFile: sourceFile, seedHistory: true,
                            workspaceAfterCommit: { previousGraph in
                                try await Self.completeWorkspace(after: previousGraph, note: note, handle: handle)
                            })
                        do {
                            try await harness.run()
                            await harness.closeAndDrain()
                        } catch {
                            await harness.closeAndDrain()
                            throw error
                        }
                        let unchanged = try Data(contentsOf: sourceFile) == sourceBytes
                        try #require(unchanged, "Stress mode and Undo checks changed the copied Note bytes.")
                        try Self.report(["metric": "stress-mode-scenario-outcome", "fixture": scenario.rawValue, "flowCompleted": true])
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        Issue.record(error)
                        try Self.report([
                            "metric": "stress-mode-scenario-outcome", "fixture": scenario.rawValue,
                            "flowCompleted": false, "error": String(describing: error),
                        ])
                    }
                }
                await runtime.shutdown()
                try Self.requirePreserved(fixture: fixture, working: working, originalFiles: originalFiles, originalNotes: originalNotes)
            } catch {
                await runtime.shutdown()
                do {
                    try Self.requirePreserved(fixture: fixture, working: working, originalFiles: originalFiles, originalNotes: originalNotes)
                } catch { Issue.record(error) }
                throw error
            }
        }

        private static func hydrate(
            _ fixturePath: String, in working: URL, workspace: WorkspaceSnapshot, documents: any DocumentUseCases
        ) async throws -> WorkspaceNoteSnapshot {
            let components = fixturePath.split(separator: "/", omittingEmptySubsequences: false)
            let role = try #require(components.first.map(String.init))
            try #require(roleFolders.contains(role) && components.count > 1 && !components.contains(".."))
            let root = working.appendingPathComponent(role, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
            let vault = try #require(workspace.vaults.first { $0.vault.canonicalPath == root.path })
            let relativePath = components.dropFirst().joined(separator: "/")
            let summary = try #require(vault.documents.first { $0.id.relativePath == relativePath })
            return try await documents.hydrate(summary)
        }

        private static func fixtureData(
            scenario: Scenario, source: String, note: WorkspaceNoteSnapshot,
            documents: any DocumentUseCases, manifest: [String: Any]
        ) async throws -> Shared.FixtureData {
            let raw: String
            let visible: String
            if let heading = scenario.heading {
                raw = heading
                visible = String(heading.drop(while: { $0 == "#" || $0 == " " }))
            } else if scenario == .longProse {
                let paragraphs = source.split(separator: "\n").filter { $0.hasPrefix("Record ") && $0.contains(", paragraph ") }
                try #require(paragraphs.count > 1)
                raw = String(paragraphs[paragraphs.count / 2])
                visible = raw
            } else {
                raw = "中文 English café e\u{301} 🧭; no final newline."
                visible = raw
            }
            let range = try uniqueRange(raw, in: source)
            var imageWidth: Int?
            var imageDestination: String?
            var imageSourceRange: NSRange?
            if scenario == .imageGallery {
                let images = try await documents.exportImages(for: note.id, markdownSource: source)
                let destination = "../Attachments/stress/image-large-0001.png"
                let targetAdmitted = images[destination] != nil
                try report([
                    "metric": "stress-mode-image-admission", "fixture": scenario.rawValue,
                    "admittedImages": images.count,
                    "admittedEncodedImageBytes": images.values.reduce(0) { $0 + $1.data.count },
                    "targetImageAdmitted": targetAdmitted,
                    "preflightExcludedFromModeTimers": true,
                    "scope": "Application-authorized encoded image resources; not decoded image memory. Preflight warms source file reads.",
                ])
                try #require(targetAdmitted, "The selected large gallery image was not admitted by Documents.exportImages.")
                let dimensions = try #require(manifest["stress_large_image_dimensions"] as? [Int])
                let width = try #require(dimensions.first)
                try #require(width > 0)
                imageWidth = width
                imageDestination = destination
                imageSourceRange = try uniqueRange("![Synthetic image 0001](\(destination))", in: source)
            }
            return Shared.FixtureData(
                name: "stress_\(scenario.rawValue)", source: source, viewportRange: range, viewportText: visible,
                editorViewportTexts: raw == visible ? [raw] : [raw, visible], expectedVisibleImageWidth: imageWidth,
                expectedVisibleImageDestination: imageDestination, expectedVisibleImageSourceRange: imageSourceRange)
        }

        private static func completeWorkspace(
            after graphGeneration: Int, note: WorkspaceNoteSnapshot, handle: WorkspaceHandle
        ) async throws -> WorkspaceSnapshot {
            // Source-only commits return before their queued derived refresh.
            // This isolated runtime has one writer: the harness's history seed
            // or final Undo/Redo flush. Observe its new complete generation
            // without adding a second refresh or timing background index work.
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                let workspace = try await handle.snapshot()
                if workspace.phase.isComplete,
                    let graph = workspace.discovery.catalog.graph, graph.generation > graphGeneration,
                    workspace.document(id: note.id)?.fingerprint == note.fingerprint
                {
                    return workspace
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            Issue.record("The committed stress source did not publish a newer complete graph before the diagnostic deadline.")
            throw MarkdownEditorSession.SessionError.unavailable
        }

        private static func uniqueRange(_ raw: String, in source: String) throws -> NSRange {
            let exact = source as NSString
            let range = exact.range(of: raw, options: .literal)
            try #require(range.location != NSNotFound && range.length > 0)
            let remaining = NSRange(location: NSMaxRange(range), length: exact.length - NSMaxRange(range))
            try #require(exact.range(of: raw, options: .literal, range: remaining).location == NSNotFound)
            let line = exact.lineRange(for: range)
            try #require(line.location == range.location)
            return range
        }

        private static func reportCapacityBoundary(
            _ paths: [String: String], working: URL, handle: WorkspaceHandle
        ) async throws {
            let path = try #require(paths["near_source_limit"])
            try #require(path == "01-analyses/Stress/Stress Near Source Limit.md")
            let workspace = try await handle.snapshot()
            let note = try await hydrate(path, in: working, workspace: workspace, documents: handle.documents)
            try report([
                "metric": "stress-source-capacity-observation", "fixture": "near_source_limit",
                "sourceUTF8Bytes": note.document.sourceBytes.count,
                "nativeSourceReadAdmitted": true, "modeMatrixExcluded": true,
                "editorAdmission": NSNull(),
                "scope": "Generated source-capacity boundary; editor admission is separate from mode timings and was not attempted here.",
            ])
        }

        private static func inventory(at root: URL, notesOnly: Bool) throws -> [String: DocumentFingerprint] {
            let manager = FileManager.default
            let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            try #require(rootValues.isDirectory == true && rootValues.isSymbolicLink != true)
            var directories = [root]
            var result: [String: DocumentFingerprint] = [:]
            while let directory = directories.popLast() {
                for file in try manager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                {
                    let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                    try #require(values.isSymbolicLink != true)
                    if values.isDirectory == true {
                        if !notesOnly || file.lastPathComponent != ".scholium" { directories.append(file) }
                    } else {
                        try #require(values.isRegularFile == true)
                        let relative = String(file.path.dropFirst(root.path.count + 1))
                        if !notesOnly || isNote(relative) {
                            result[relative] = DocumentFingerprint(data: try Data(contentsOf: file))
                        }
                    }
                }
            }
            return result
        }

        private static func isNote(_ path: String) -> Bool {
            guard let role = path.split(separator: "/").first else { return false }
            return roleFolders.contains(String(role)) && (path as NSString).pathExtension.lowercased() == "md"
        }

        private static func noteInventory(_ allFiles: [String: DocumentFingerprint]) -> [String: DocumentFingerprint] {
            allFiles.filter { isNote($0.key) }
        }

        private static func requireSameInventory(
            _ expected: [String: DocumentFingerprint], actual: [String: DocumentFingerprint], label: String
        ) throws {
            let changed = Set(expected.keys).union(actual.keys).filter { expected[$0] != actual[$0] }.sorted()
            let unchanged = changed.isEmpty
            try #require(unchanged, Comment(rawValue: "\(label) changed: \(changed.count) files; first paths: \(changed.prefix(8).joined(separator: ", "))."))
        }

        private static func requirePreserved(
            fixture: URL, working: URL, originalFiles: [String: DocumentFingerprint], originalNotes: [String: DocumentFingerprint]
        ) throws {
            try requireSameInventory(originalFiles, actual: inventory(at: fixture, notesOnly: false), label: "Generated originals")
            try requireSameInventory(originalNotes, actual: inventory(at: working, notesOnly: true), label: "Copied Notes")
        }

        private static func digest(_ inventory: [String: DocumentFingerprint]) -> String {
            let records = inventory.keys.sorted().map { "\($0)\u{1F}\(inventory[$0]!.sha256)\u{1F}\(inventory[$0]!.byteCount)" }
            return DocumentFingerprint(content: records.joined(separator: "\n")).sha256
        }

        private static func report(_ record: [String: Any]) throws {
            let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            try FileHandle.standardOutput.write(contentsOf: bytes + Data([0x0A]))
        }

        private static func milliseconds(_ duration: Duration) -> Double {
            let value = duration.components
            return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1_000_000_000_000_000
        }
    }
#endif
