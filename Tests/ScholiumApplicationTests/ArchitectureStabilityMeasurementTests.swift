import Foundation
import ScholiumContracts
import Testing
@testable import ScholiumApplication

@Suite("Architecture stability measurement", .serialized)
struct ArchitectureStabilityMeasurementTests {
    @Test("RDF-1 records a comparable full-open and add/edit/rename/delete refresh sequence")
    func rdf1RefreshSequence() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/architecture-refresh", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        let fixtureRoot = root.appendingPathComponent("rdf1", isDirectory: true)
        let stateRoot = root.appendingPathComponent("state", isDirectory: true)
        let applicationSupportURL = stateRoot.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        let registryStorageURL = stateRoot.appendingPathComponent(
            "Registry",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let generator = Process()
        generator.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        generator.arguments = [
            repositoryRoot.appendingPathComponent(
                "Tools/Scripts/generate-rdf1.py"
            ).path,
            "--output",
            fixtureRoot.path,
        ]
        let generatorOutput = Pipe()
        generator.standardOutput = generatorOutput
        generator.standardError = generatorOutput
        try generator.run()
        generator.waitUntilExit()
        let generatedOutput = String(
            data: generatorOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        #expect(generator.terminationStatus == 0, Comment(rawValue: generatedOutput))

        let manifestData = try Data(contentsOf: fixtureRoot.appendingPathComponent(
            "manifest.json"
        ))
        let manifest = try #require(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        let triptychManifest = try #require(
            manifest["triptych"] as? [String: Any]
        )
        let treeHash = try #require(
            triptychManifest["tree_sha256"] as? String
        )
        #expect(triptychManifest["note_count"] as? Int == 800)

        let analysesURL = fixtureRoot.appendingPathComponent(
            "01-analyses",
            isDirectory: true
        )
        let topicsURL = fixtureRoot.appendingPathComponent(
            "02-topics",
            isDirectory: true
        )
        let worksURL = fixtureRoot.appendingPathComponent(
            "03-works",
            isDirectory: true
        )
        let configurationRuntime = WorkspaceRuntime(configuration: .live(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL
        )))
        let configured: WorkspaceHandle
        do {
            configured = try await configurationRuntime.configureTriptych(
                paperAnalysisURL: analysesURL,
                topicKnowledgeURL: topicsURL,
                outputURL: worksURL,
                portableContainerURL: fixtureRoot,
                triptychName: "RDF-1 Architecture Measurement"
            )
        } catch {
            await configurationRuntime.shutdown()
            throw error
        }
        let assignment = configured.assignment
        await configurationRuntime.shutdown()

        let runtime = WorkspaceRuntime(configuration: .snapshot(.init(
            applicationSupportURL: applicationSupportURL,
            workspaceRegistryStorageURL: registryStorageURL,
            assignments: [assignment]
        )))
        do {
            let handle = try await runtime.openWorkspace(id: assignment.id)
            let initial = await handle.latestRefreshMeasurement
            let services = await handle.services
            let dependencies = services.snapshotBuilderDependencies
            let analysesID = try #require(
                assignment.vault(for: .paperAnalysis)?.id
            )
            let catalog = try #require(dependencies.sourceCatalogs[analysesID])
            let relativePath = "Architecture/Delta.md"
            let renamedPath = "Architecture/Delta Renamed.md"
            let noteURL = analysesURL.appendingPathComponent(relativePath)
            let renamedURL = analysesURL.appendingPathComponent(renamedPath)
            try FileManager.default.createDirectory(
                at: noteURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try Data("# Architecture Delta\n\nInitial delta.\n".utf8).write(
                to: noteURL
            )
            try await catalog.apply(VaultWatchEvent(
                added: [relativePath],
                modified: [],
                deleted: [],
                sequence: 1,
                requiresFullRescan: false,
                rootChanged: false
            ))
            let added = try await build(
                assignment: assignment,
                dependencies: dependencies,
                graphGeneration: 2
            )

            try Data("# Architecture Delta\n\nEdited delta.\n".utf8).write(
                to: noteURL,
                options: .atomic
            )
            try await catalog.apply(VaultWatchEvent(
                added: [],
                modified: [relativePath],
                deleted: [],
                sequence: 2,
                requiresFullRescan: false,
                rootChanged: false
            ))
            let edited = try await build(
                assignment: assignment,
                dependencies: dependencies,
                graphGeneration: 3
            )

            try FileManager.default.moveItem(at: noteURL, to: renamedURL)
            try await catalog.apply(VaultWatchEvent(
                added: [renamedPath],
                modified: [],
                deleted: [relativePath],
                sequence: 3,
                requiresFullRescan: false,
                rootChanged: false
            ))
            let renamed = try await build(
                assignment: assignment,
                dependencies: dependencies,
                graphGeneration: 4
            )

            try FileManager.default.removeItem(at: renamedURL)
            try await catalog.apply(VaultWatchEvent(
                added: [],
                modified: [],
                deleted: [renamedPath],
                sequence: 4,
                requiresFullRescan: false,
                rootChanged: false
            ))
            let deleted = try await build(
                assignment: assignment,
                dependencies: dependencies,
                graphGeneration: 5
            )

            #expect(initial.enumeratedFiles == 800)
            #expect(initial.readFiles == 800)
            #expect(initial.parsedDocuments == 800)
            #expect(initial.projectedDocuments == 800)
            for measurement in [added, edited, renamed] {
                #expect(measurement.enumeratedFiles == 0)
                #expect(measurement.readFiles == 1)
                #expect(measurement.parsedDocuments == 1)
                #expect(measurement.projectedDocuments == 1)
            }
            #expect(deleted.enumeratedFiles == 0)
            #expect(deleted.readFiles == 0)
            #expect(deleted.parsedDocuments == 0)
            #expect(deleted.projectedDocuments == 0)

            let reportPayload: [String: Any] = [
                "schema": "scholium-architecture-refresh-measurement-v1",
                "rdf1_tree_sha256": treeHash,
                "steps": [
                    report(initial, step: "cold_open"),
                    report(added, step: "add"),
                    report(edited, step: "edit"),
                    report(renamed, step: "rename"),
                    report(deleted, step: "delete"),
                ],
            ]
            let reportData = try JSONSerialization.data(
                withJSONObject: reportPayload,
                options: [.sortedKeys]
            )
            print(
                "SCHOLIUM_ARCHITECTURE_REFRESH_MEASUREMENT "
                    + String(decoding: reportData, as: UTF8.self)
            )
            await runtime.shutdown()
        } catch {
            await runtime.shutdown()
            throw error
        }
    }

    private func report(
        _ measurement: WorkspaceRefreshMeasurement,
        step: String
    ) -> [String: Any] {
        [
            "step": step,
            "workspace_generation": measurement.workspaceGeneration,
            "enumerated_files": measurement.enumeratedFiles,
            "read_files": measurement.readFiles,
            "parsed_documents": measurement.parsedDocuments,
            "projected_documents": measurement.projectedDocuments,
            "metadata_records_read": measurement.metadataRecordsRead,
            "snapshot_source_bytes": measurement.snapshotSourceBytes,
            "enumeration_ms": milliseconds(measurement.enumerationDuration),
            "read_ms": milliseconds(measurement.readDuration),
            "parse_ms": milliseconds(measurement.parseDuration),
            "projection_ms": milliseconds(measurement.projectionDuration),
            "identity_projection_ms": milliseconds(
                measurement.identityProjectionDuration
            ),
            "graph_ms": milliseconds(measurement.graphDuration),
            "research_state_ms": milliseconds(
                measurement.researchStateDuration
            ),
            "search_document_projection_ms": milliseconds(
                measurement.searchDocumentProjectionDuration
            ),
            "search_ms": milliseconds(measurement.searchDuration),
            "snapshot_assembly_ms": milliseconds(
                measurement.snapshotAssemblyDuration
            ),
            "total_ms": milliseconds(measurement.totalDuration),
        ]
    }

    private func build(
        assignment: TriptychAssignment,
        dependencies: WorkspaceSnapshotBuilderDependencies,
        graphGeneration: Int
    ) async throws -> WorkspaceRefreshMeasurement {
        let indexed = try await dependencies.searchIndex.workspaceGeneration()
        let result = try await WorkspaceSnapshotBuilder.build(
            assignment: assignment,
            mode: .snapshot,
            dependencies: dependencies,
            graphGeneration: graphGeneration,
            workspaceGeneration: indexed + 1
        )
        return result.measurement
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
