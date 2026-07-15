import Foundation
import ScholiumApplication
import Testing

@Suite("Scholium delivery paths")
struct ScholiumPathsTests {
    @Test("Legacy KB Manager state is copied without deleting the original")
    func legacyMigration() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("KBManager", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacy.appendingPathComponent("marker.txt"))

        let current = try ScholiumPaths.applicationSupportURL(baseURL: base)

        #expect(current.lastPathComponent == "Scholium")
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("marker.txt").path))
        #expect(try String(contentsOf: current.appendingPathComponent("marker.txt"), encoding: .utf8) == "legacy")
    }

    @Test("The CLI discovers the sandboxed app's shared Application Support")
    func sandboxedApplicationSupportDiscovery() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let home = base.appendingPathComponent("home", isDirectory: true)
        let container = home.appendingPathComponent(
            "Library/Containers/com.kbmanager.app/Data/Library/Application Support/Scholium",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let discovered = try ScholiumPaths.sharedApplicationSupportURL(
            homeURL: home,
            fallbackBaseURL: base.appendingPathComponent("fallback", isDirectory: true)
        )

        #expect(discovered.standardizedFileURL == container.standardizedFileURL)
    }

    @Test("An isolated CLI home also isolates workspace registry state")
    func isolatedCLIWorkspaceState() throws {
        let isolatedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let state = try ScholiumPaths.workspaceRegistryURL(
            homeURL: isolatedHome,
            environment: ["SCHOLIUM_HOME": "/a/different/process/value"]
        )

        #expect(state.standardizedFileURL == isolatedHome
            .appendingPathComponent("registry", isDirectory: true)
            .standardizedFileURL)
    }
}
