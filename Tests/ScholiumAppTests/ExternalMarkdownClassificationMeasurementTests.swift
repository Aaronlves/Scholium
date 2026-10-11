import Foundation
import ScholiumApplication
import ScholiumContracts
import Testing

@testable import ScholiumApp

/// Opt-in, nonforeground diagnostics. These distributions are not a product gate.
@Suite("External Markdown ownership measurements", .serialized)
@MainActor
struct ExternalMarkdownClassificationMeasurementTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCHOLIUM_EXTERNAL_OWNERSHIP_MEASUREMENT"] == "1"))
    func ownershipCosts() async throws {
        for (triptychs, notes) in [(0, 0), (1, 0), (10, 0), (50, 0), (100, 0), (1, 500), (1, 10_000)] {
            let fixture = try MeasurementFixture(triptychs: triptychs, notes: notes)
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let runtime = WorkspaceRuntime(
                configuration: .live(
                    .init(
                        applicationSupportURL: fixture.root.appendingPathComponent("ApplicationSupport"),
                        workspaceRegistryStorageURL: fixture.registryRoot)))
            do {
                let firstStart = ContinuousClock.now
                let assignments = try await runtime.availableWorkspaces()
                let firstResult = MarkdownFileOpeningController.managedNote(at: fixture.external, assignments: assignments)
                emit("first_ownership", fixture: fixture, sample: 0, start: firstStart)
                #expect(assignments.count == triptychs)
                #expect(firstResult == nil)
                for sample in -3..<30 {
                    let registryStart = ContinuousClock.now
                    let current = try await runtime.availableWorkspaces()
                    emit("registry", fixture: fixture, sample: sample, start: registryStart)
                    #expect(current.count == triptychs)

                    let classifyStart = ContinuousClock.now
                    let result = MarkdownFileOpeningController.managedNote(at: fixture.external, assignments: current)
                    emit("classify", fixture: fixture, sample: sample, start: classifyStart)
                    #expect(result == nil)

                    let ownershipStart = ContinuousClock.now
                    let fresh = try await runtime.availableWorkspaces()
                    let combined = MarkdownFileOpeningController.managedNote(at: fixture.external, assignments: fresh)
                    emit("ownership", fixture: fixture, sample: sample, start: ownershipStart)
                    #expect(combined == nil)
                }
                if let expected = assignments.last, let vault = expected.vault(for: .topicKnowledge) {
                    let managed = URL(fileURLWithPath: vault.canonicalPath).appendingPathComponent("Managed.md")
                    try Data("# Synthetic managed\n".utf8).write(to: managed)
                    for sample in -3..<30 {
                        let start = ContinuousClock.now
                        let result = MarkdownFileOpeningController.managedNote(at: managed, assignments: assignments)
                        emit("managed_classify", fixture: fixture, sample: sample, start: start)
                        #expect(result?.triptychID == expected.id)
                        #expect(result?.reference.vaultID == vault.id)
                        #expect(result?.reference.relativePath == "Managed.md")
                    }
                }
                await runtime.shutdown()
            } catch {
                await runtime.shutdown()
                throw error
            }
        }
    }

    private func emit(_ metric: String, fixture: MeasurementFixture, sample: Int, start: ContinuousClock.Instant) {
        guard sample >= 0 else { return }
        let duration = start.duration(to: .now).components
        let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        print("EXTERNAL_OWNERSHIP metric=\(metric) triptychs=\(fixture.triptychs) notes=\(fixture.notes) sample=\(sample) ms=\(milliseconds)")
    }

    private struct RegistryFile: Encodable {
        let schemaVersion = 3
        let vaults: [RegisteredVault]
        let triptychs: [ScholiumTriptych]
        let defaultTriptychID: UUID?
    }

    private struct MeasurementFixture {
        let root: URL
        let registryRoot: URL
        let external: URL
        let triptychs: Int
        let notes: Int

        init(triptychs: Int, notes: Int) throws {
            self.triptychs = triptychs
            self.notes = notes
            root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/ExternalOwnershipMeasurement-\(UUID())", isDirectory: true)
            registryRoot = root.appendingPathComponent("ApplicationSupport/Workspace", isDirectory: true)
            external = root.appendingPathComponent("Outside.md")
            do {
                try FileManager.default.createDirectory(at: registryRoot, withIntermediateDirectories: true)
                try Data("\u{FEFF}# Exact synthetic external 中文 😀\r\n".utf8).write(to: external)
                var vaults: [RegisteredVault] = []
                var registrations: [ScholiumTriptych] = []
                let date = Date(timeIntervalSince1970: 0)
                for index in 0..<triptychs {
                    var ids: [WorkspaceVaultSlot: UUID] = [:]
                    for slot in WorkspaceVaultSlot.allCases {
                        let folder = root.appendingPathComponent("Triptych-\(index)/\(slot.displayName)", isDirectory: true)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let id = UUID()
                        ids[slot] = id
                        vaults.append(
                            RegisteredVault(
                                id: id, name: slot.displayName, role: slot.vaultRole,
                                canonicalPath: folder.path, registeredAt: date))
                    }
                    registrations.append(
                        ScholiumTriptych(
                            name: String(format: "Synthetic %04d", index),
                            paperAnalysisVaultID: ids[.paperAnalysis]!, topicKnowledgeVaultID: ids[.topicKnowledge]!,
                            outputVaultID: ids[.output]!, createdAt: date, updatedAt: date))
                }
                if notes > 0 {
                    let folder = root.appendingPathComponent("Triptych-0/Topics", isDirectory: true)
                    for index in 0..<notes {
                        try Data("# Synthetic \(index)\n".utf8).write(to: folder.appendingPathComponent("Note-\(index).md"))
                    }
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(
                    RegistryFile(
                        vaults: vaults, triptychs: registrations,
                        defaultTriptychID: registrations.first?.id)
                )
                .write(to: registryRoot.appendingPathComponent("workspace-registration-v3.json"))
            } catch {
                try? FileManager.default.removeItem(at: root)
                throw error
            }
        }
    }
}
