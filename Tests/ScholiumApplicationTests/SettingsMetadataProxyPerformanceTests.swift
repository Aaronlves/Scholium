import Foundation
import ScholiumContracts
import Testing

@testable import ScholiumApplication

/// Service attribution only. Run explicitly after the focused tests; never
/// reads preferences or a user-selected path. Its only input is repo TestVaults.
@Suite(
    "Settings current workspace service proxy baseline", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_MEASURE_SETTINGS_METADATA_PROXY"] == "1"))
struct SettingsMetadataProxyPerformanceTests {
    @Test("Current workspace Settings route over one closed synthetic seed")
    func sameClosedSeed() async throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let standard = repository.appendingPathComponent("TestVaults", isDirectory: true)
        let fixtureManifest = try Data(contentsOf: standard.appendingPathComponent("fixture-manifest.json"))
        let envelope = try #require(JSONSerialization.jsonObject(with: fixtureManifest) as? [String: Any])
        let expected = try #require(envelope["files_sha256"] as? [String: String])
        let standardFiles = try proxyFileHashes(standard)
        for (path, digest) in expected { try #require(standardFiles[path] == digest) }
        let notePaths = expected.keys.filter {
            $0.hasSuffix(".md") && ["01-analyses/", "02-topics/", "03-works/"].contains(where: $0.hasPrefix)
        }
        try #require(notePaths.count == 500)
        let output = repository.appendingPathComponent(".build/settings-metadata-proxy", isDirectory: true)
        let runID = UUID().uuidString.lowercased()
        let root = output.appendingPathComponent(runID, isDirectory: true)
        let copied = root.appendingPathComponent("fixture", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let registry = root.appendingPathComponent("Registry", isDirectory: true)
        let closedSupport = root.appendingPathComponent("closed-support", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: standard, to: copied)
        let beforeSeedSource = try proxyFileHashes(copied)
        let seeding = WorkspaceRuntime(
            configuration: .live(
                .init(
                    applicationSupportURL: support, workspaceRegistryStorageURL: registry)))
        let assignment: TriptychAssignment
        do {
            assignment = try await seeding.configureTriptych(
                paperAnalysisURL: copied.appendingPathComponent("01-analyses", isDirectory: true),
                topicKnowledgeURL: copied.appendingPathComponent("02-topics", isDirectory: true),
                outputURL: copied.appendingPathComponent("03-works", isDirectory: true),
                portableContainerURL: copied, triptychName: "Synthetic Settings proxy"
            ).assignment
            await seeding.shutdown()
        } catch {
            await seeding.shutdown()
            throw error
        }
        let sourceAfterSeed = try proxyFileHashes(copied, excludingControl: true)
        try #require(sourceAfterSeed == beforeSeedSource)
        try assertProxyClosed(support)
        let control = copied.appendingPathComponent(".scholium", isDirectory: true)
        let identityData = try Data(contentsOf: control.appendingPathComponent("identities.json"))
        let identities = try #require(JSONSerialization.jsonObject(with: identityData) as? [String: Any])
        let records = try #require(identities["records"] as? [[String: Any]])
        let expectedIdentities = Set(
            notePaths.compactMap { path -> String? in
                let pieces = path.split(separator: "/", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else { return nil }
                let slot: WorkspaceVaultSlot
                switch pieces[0] {
                case "01-analyses": slot = .paperAnalysis
                case "02-topics": slot = .topicKnowledge
                case "03-works": slot = .output
                default: return nil
                }
                return assignment.triptych.vaultID(for: slot).uuidString.lowercased() + ":" + pieces[1]
            })
        let actualIdentities = Set(
            try records.map { record -> String in
                let id = try #require(record["vaultID"] as? String)
                let path = try #require(record["relativePath"] as? String)
                return id.lowercased() + ":" + path
            })
        try #require(records.count == 500 && actualIdentities == expectedIdentities)
        let portableOracle = try proxyFileHashes(control)
        let registryOracle = try proxyFileHashes(registry)
        let assignmentOracle = proxyAssignmentDigest(assignment)
        try FileManager.default.copyItem(at: support, to: closedSupport)
        let supportOracle = try proxyFileHashes(closedSupport)
        let settingsBytes = try Data(contentsOf: control.appendingPathComponent("settings.json"))
        let expectedSettings = TriptychSettingsRecoverySnapshot(
            loadState: .current(.init(settings: TriptychSettings(), revision: .init(fingerprint: .init(data: settingsBytes)))),
            revision: .init(fingerprint: .init(data: settingsBytes)))
        var report: [String: Any] = [
            "schema": "scholium-settings-workspace-service-proxy-baseline-v1", "status": "prepared",
            "measurement_scope": "Application APIs only; no Settings window, native input/paint or cold-disk claim.",
            "setup": "One complete live seed outside timers; same source paths/registration/control bytes; closed support restored to same path for every arm.",
            "fresh_runtime_definition": "Unopened snapshot runtime with identical compatible derived state; OS caches are not purged.",
            "borrowed_definition":
                "Existing full snapshot handle opened before timer; measures the current workspace(...).research.settingsRecoverySnapshot route only.",
            "baseline_context":
                "Prechange current API only, six observations. A later paired API diagnostic uses a new UUID seed; no exact paired comparison across those separate runs.",
            "fixture_note_count": 500, "identity_record_count": records.count,
            "source_digest": try proxyDigest(sourceAfterSeed),
            "portable_digest": try proxyDigest(portableOracle),
            "registry_digest": try proxyDigest(registryOracle), "assignment_digest": assignmentOracle,
            "manifest_sha256": try #require(portableOracle["manifest.json"]),
            "settings_sha256": DocumentFingerprint(data: settingsBytes).sha256,
            "closed_support_digest": try proxyDigest(supportOracle),
            "fixture_manifest_sha256": DocumentFingerprint(data: fixtureManifest).sha256,
            "developer_directory": ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "not set",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "retained_owned_fixture": root.path,
            "build_configuration": proxyBuildConfiguration,
        ]
        let reportURL = output.appendingPathComponent("settings-proxy-\(runID).json")
        func save() throws {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: reportURL, options: .atomic)
        }
        try save()
        var samples: [[String: Any]] = []
        for borrowed in [false, true] {
            for round in 0..<3 {
                // Each observation gets the same closed support bytes at
                // exactly the same canonical paths; no bookmark is cloned.
                let arms = ["workspace"]
                for arm in arms {
                    try assertProxyClosed(support)
                    try FileManager.default.removeItem(at: support)
                    try FileManager.default.copyItem(at: closedSupport, to: support)
                    try #require(proxyFileHashes(support) == supportOracle)
                    let runtime = WorkspaceRuntime(
                        configuration: .snapshot(
                            .init(
                                applicationSupportURL: support, workspaceRegistryStorageURL: registry, assignments: [assignment])))
                    do {
                        let existing = borrowed ? try await runtime.workspace(id: assignment.id) : nil
                        try #require(proxyAssignmentDigest(assignment) == assignmentOracle)
                        let clock = ContinuousClock()
                        let start = clock.now
                        let observed = try await runtime.workspace(id: assignment.id).research.settingsRecoverySnapshot()
                        let duration = start.duration(to: clock.now)
                        try #require(observed == expectedSettings)
                        let pooled = await runtime.pooledVaultRuntimeCount
                        try #require(pooled == 3)
                        if let existing {
                            try #require(try await runtime.workspace(id: assignment.id) === existing)
                        }
                        try #require(proxyFileHashes(copied, excludingControl: true) == sourceAfterSeed)
                        try #require(proxyFileHashes(control) == portableOracle)
                        try #require(proxyFileHashes(registry) == registryOracle)
                        await runtime.shutdown()
                        try assertProxyClosed(support)
                        let components = duration.components
                        samples.append([
                            "scenario": borrowed ? "borrowed_open" : "fresh_unopened",
                            "arm": arm, "round": round,
                            "api_ms": Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15,
                            "pooled_vault_owners_after_api": pooled,
                            "exact_settings_revision_and_state": true,
                            "source_portable_registry_unchanged": true,
                            "closed_journals_verified": true,
                        ])
                        report["samples"] = samples
                        report["status"] = "in_progress"
                        try save()
                    } catch {
                        await runtime.shutdown()
                        report["status"] = "failed"
                        report["failure"] = error.localizedDescription
                        try? save()
                        throw error
                    }
                }
            }
        }
        try #require(samples.count == 6)
        try #require(proxyFileHashes(standard) == standardFiles)
        report["status"] = "completed"
        report["all_oracles_passed"] = true
        try save()
        print("Settings service proxy completed: \(reportURL.path), 6 current-API observations; service-only, no native latency claim.")
    }
}

private var proxyBuildConfiguration: String {
    #if DEBUG
        "debug"
    #else
        "release"
    #endif
}

private func proxyAssignmentDigest(_ assignment: TriptychAssignment) -> String {
    let fields = WorkspaceVaultSlot.allCases.map { slot in
        "\(slot.rawValue):\(assignment.triptych.vaultID(for: slot).uuidString):\(assignment.vault(for: slot)?.canonicalPath ?? "missing")"
    }
    return DocumentFingerprint(content: ([assignment.id.uuidString] + fields).joined(separator: "\n")).sha256
}

private func proxyDigest(_ values: [String: String]) throws -> String {
    DocumentFingerprint(data: try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])).sha256
}

private func proxyFileHashes(_ root: URL, excludingControl: Bool = false) throws -> [String: String] {
    var values: [String: String] = [:]
    var enumerationError: Error?
    let enumerator = try #require(
        FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey], options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }))
    for case let url as URL in enumerator {
        let relative = String(url.path.dropFirst(root.path.count + 1))
        if excludingControl, relative == ".scholium" || relative.hasPrefix(".scholium/") {
            enumerator.skipDescendants()
            continue
        }
        let properties = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        try #require(properties.isSymbolicLink != true)
        if properties.isDirectory == true { continue }
        try #require(properties.isRegularFile == true)
        values[relative] = DocumentFingerprint(data: try Data(contentsOf: url)).sha256
    }
    if let enumerationError { throw enumerationError }
    return values
}

private func assertProxyClosed(_ root: URL) throws {
    let files = try proxyFileHashes(root)
    try #require(
        !files.keys.contains {
            $0.hasSuffix("-wal") || $0.hasSuffix("-shm") || $0.hasSuffix("-journal")
        })
}
