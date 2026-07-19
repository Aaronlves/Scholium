import Foundation
import ScholiumApplication
import Testing

@Suite("Scholium delivery paths")
struct ScholiumPathsTests {
    @Test("Scholium creates isolated app state without importing another product")
    func isolatedApplicationState() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let otherProduct = base.appendingPathComponent("OtherProduct", isDirectory: true)
        try FileManager.default.createDirectory(at: otherProduct, withIntermediateDirectories: true)
        try Data("unrelated".utf8).write(to: otherProduct.appendingPathComponent("marker.txt"))

        let current = try ScholiumPaths.applicationSupportURL(baseURL: base)

        #expect(current.lastPathComponent == "Scholium")
        #expect(FileManager.default.fileExists(atPath: otherProduct.appendingPathComponent("marker.txt").path))
        #expect(!FileManager.default.fileExists(atPath: current.appendingPathComponent("marker.txt").path))
    }

    @Test("The CLI discovers the sandboxed app's shared Application Support")
    func sandboxedApplicationSupportDiscovery() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let home = base.appendingPathComponent("home", isDirectory: true)
        let container = home.appendingPathComponent(
            "Library/Containers/com.scholium.app/Data/Library/Application Support/Scholium",
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
